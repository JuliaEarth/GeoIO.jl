# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# Main entry point  
function gpkgread(fname::String; layer::Int=1, kwargs...)
  db = SQLite.DB(fname)
  
  # 1. Read metadata to extract names of tables and CRS type
  table_name, geom_column, crs_type = gpkgmetadata(db, layer)
  
  # 2. Get all column names from the table
  columns_result = DBInterface.execute(db, "PRAGMA table_info(\"$table_name\")")
  all_columns = [row.name for row in Tables.rows(columns_result)]
  
  # 3. Build vectors for each column by processing row by row
  
  # Get first row to determine column types
  table_result = DBInterface.execute(db, "SELECT * FROM \"$table_name\" LIMIT 1")
  first_row_state = iterate(Tables.rows(table_result))
  
  if isnothing(first_row_state)
    error("No data found in table $table_name")
  end
  
  first_row = first_row_state[1]
  
  # Initialize column vectors with proper types based on first row
  column_data = Dict{Symbol, Vector}()
  for col_name in all_columns
    col_symbol = Symbol(col_name)
    sample_value = Tables.getcolumn(first_row, col_symbol)
    if col_name == geom_column
      column_data[col_symbol] = Any[]  # Geometry column stays as Any for mixed types
    else
      # Use the actual type from SQLite for attribute columns
      column_data[col_symbol] = Vector{typeof(sample_value)}()
    end
  end
  
  # Process first row
  for col_name in all_columns
    col_symbol = Symbol(col_name)
    if col_name == geom_column
      # Parse geometry blob
      blob = Tables.getcolumn(first_row, col_symbol)
      if ismissing(blob) || isnothing(blob)
        push!(column_data[col_symbol], blob)
      else
        push!(column_data[col_symbol], parse_wkb_geometry_from_blob(blob, crs_type))
      end
    else
      # Store attribute data as-is
      push!(column_data[col_symbol], Tables.getcolumn(first_row, col_symbol))
    end
  end
  
  # Query and process remaining rows
  table_result = DBInterface.execute(db, "SELECT * FROM \"$table_name\"")
  row_count = 0
  for row in Tables.rows(table_result)
    row_count += 1
    if row_count == 1
      continue  # Skip first row since we already processed it
    end
    
    for col_name in all_columns
      col_symbol = Symbol(col_name)
      if col_name == geom_column
        # Parse geometry blob
        blob = Tables.getcolumn(row, col_symbol)
        if ismissing(blob) || isnothing(blob)
          push!(column_data[col_symbol], blob)
        else
          push!(column_data[col_symbol], parse_wkb_geometry_from_blob(blob, crs_type))
        end
      else
        # Store attribute data as-is
        push!(column_data[col_symbol], Tables.getcolumn(row, col_symbol))
      end
    end
  end
  
  # 4. Build final table
  final_names = Symbol[]
  final_columns = Any[]
  
  for col_name in all_columns
    if col_name == geom_column
      push!(final_names, :geometry)
    else
      push!(final_names, Symbol(col_name))
    end
    push!(final_columns, column_data[Symbol(col_name)])
  end
  
  close(db)
  
  return (; zip(final_names, final_columns)...)
end

function gpkgmetadata(db::SQLite.DB, layer::Int)
  # Get feature table names
  contents_result = DBInterface.execute(db,
    """
    SELECT table_name, data_type
    FROM gpkg_contents
    WHERE data_type = 'features'
    ORDER BY table_name
    """)
  
  # Use Iterators.drop to get the requested layer
  rows = Tables.rows(contents_result)
  layer_iter = Iterators.drop(rows, layer - 1)
  
  if isempty(layer_iter)
    error("Layer $layer not found in GeoPackage")
  end
  first_row = first(layer_iter)
  
  table_name = first_row.table_name
  
  # Get geometry column information
  geom_result = DBInterface.execute(db,
    """
    SELECT column_name, srs_id
    FROM gpkg_geometry_columns
    WHERE table_name = ?
    """, [table_name])
  geom_info = first(Tables.rows(geom_result))
  geom_column = geom_info.column_name
  srs_id = geom_info.srs_id
  
  # Get CRS from SRID according to GeoPackage specification
  # Handle special cases per GeoPackage spec
  if srs_id == 0
    crs_type = LatLon{WGS84Latest}
  elseif srs_id == -1
    # Undefined Cartesian coordinate reference system - determine dimensionality from geometry_columns
    geom_cols_result = DBInterface.execute(db,
      """
      SELECT z
      FROM gpkg_geometry_columns
      WHERE table_name = ? AND column_name = ?
      """, [table_name, geom_column])
    
    geom_state = iterate(Tables.rows(geom_cols_result))
    if !isnothing(geom_state)
      z_flag = geom_state[1].z
      if z_flag == 1
        crs_type = Cartesian{NoDatum,3}
      else
        crs_type = Cartesian{NoDatum,2}
      end
    else
      crs_type = Cartesian{NoDatum,2}
    end
  else
    # Query the database for the organization and organization_coordsys_id
    srs_result = DBInterface.execute(db,
      """
      SELECT organization, organization_coordsys_id
      FROM gpkg_spatial_ref_sys
      WHERE srs_id = ?
      """, [srs_id])
    
    org_state = iterate(Tables.rows(srs_result))
    if isnothing(org_state)
      # SRID not found - use fallback to Cartesian (allowed by spec)
      crs_type = Cartesian{NoDatum}
    else
      org_info = org_state[1]
      
      # Per GeoPackage spec, organization and organization_coordsys_id are NOT NULL
      org_name = uppercase(org_info.organization)
      coord_id = org_info.organization_coordsys_id
      
      if org_name == "EPSG"
        crs_type = CoordRefSystems.get(EPSG{coord_id})
      elseif org_name == "ESRI"
        crs_type = CoordRefSystems.get(ESRI{coord_id})
      else
        # Per spec: other organizations or NONE
        crs_type = Cartesian{NoDatum}
      end
    end
  end
  
  return table_name, geom_column, crs_type
end


# GeoPackage Binary Header structure
struct GeoPackageBinaryHeader
  magic::UInt16
  version::UInt8
  flags::UInt8
  srs_id::Int32
  min_x::Float64
  max_x::Float64
  min_y::Float64
  max_y::Float64
  min_z::Union{Float64,Nothing}
  max_z::Union{Float64,Nothing}
  min_m::Union{Float64,Nothing}
  max_m::Union{Float64,Nothing}
end

function parse_gpb_header(blob::Vector{UInt8})
  io = IOBuffer(blob)
  
  magic = read(io, UInt16)
  magic == 0x5047 || error("Invalid GeoPackage binary header")
  
  version = read(io, UInt8)
  flags = read(io, UInt8)
  
  srs_id = ltoh(read(io, Int32))
  
  envelope_type = flags >> 1 & 0x07
  has_envelope = envelope_type > 0
  
  if has_envelope && envelope_type >= 1
    min_x = ltoh(read(io, Float64))
    max_x = ltoh(read(io, Float64))
    min_y = ltoh(read(io, Float64))
    max_y = ltoh(read(io, Float64))
  else
    # Default envelope when not present
    min_x = max_x = min_y = max_y = 0.0
  end
  
  # Initialize z and m coordinates based on envelope type
  if has_envelope && envelope_type >= 2
    min_z = ltoh(read(io, Float64))
    max_z = ltoh(read(io, Float64))
  else
    min_z = max_z = nothing
  end
  
  if has_envelope && envelope_type >= 3
    min_m = ltoh(read(io, Float64))
    max_m = ltoh(read(io, Float64))
  else
    min_m = max_m = nothing
  end
  
  header = GeoPackageBinaryHeader(
    magic, version, flags, srs_id,
    min_x, max_x, min_y, max_y,
    min_z, max_z, min_m, max_m
  )
  
  return header, position(io)
end

# Parse GeoPackage Binary (GPB) format - combines header and WKB geometry
function parse_wkb_geometry_from_blob(blob::Vector{UInt8}, crs_type)
  header, offset = parse_gpb_header(blob)
  io = IOBuffer(blob[offset+1:end])
  parse_wkb_geometry(io, crs_type)
end

function parse_wkb_geometry(io::IOBuffer, crs_type)
  byte_order = read(io, UInt8)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  wkb_type = read_value(read(io, UInt32))
  base_type = wkb_type & 0x0FFFFFFF
  
  # Determine coordinate dimensionality from CRS type
  ndims = CoordRefSystems.ncoords(crs_type)
  
  # Create parse_coords closure that reads coordinates based on CRS dimensionality
  parse_coords = io -> read_coords_from_buffer(io, read_value, ndims)

  if base_type == WKB_POINT
    return parse_wkb_point(io, parse_coords, crs_type)
  elseif base_type == WKB_LINESTRING
    return parse_wkb_linestring(io, parse_coords, crs_type)
  elseif base_type == WKB_POLYGON
    return parse_wkb_polygon(io, parse_coords, crs_type)
  elseif base_type == WKB_MULTIPOINT
    return parse_wkb_multipoint(io, parse_coords, crs_type)
  elseif base_type == WKB_MULTILINESTRING
    return parse_wkb_multilinestring(io, parse_coords, crs_type)
  elseif base_type == WKB_MULTIPOLYGON
    return parse_wkb_multipolygon(io, parse_coords, crs_type)
  else
    error("Unsupported WKB geometry type: $base_type")
  end
end

# Read coordinates from buffer based on CRS dimensionality
function read_coords_from_buffer(io::IOBuffer, read_value::Function, ndims::Int)
  
  if ndims == 2
    x = read_value(read(io, Float64))
    y = read_value(read(io, Float64))
    return (x, y)
  elseif ndims == 3
    x = read_value(read(io, Float64))
    y = read_value(read(io, Float64))
    z = read_value(read(io, Float64))
    return (x, y, z)
  else
    error("Unsupported number of dimensions: $ndims")
  end
end


# Convert coordinate buffer to CRS coordinates
function create_crs_coord(buff::Tuple, crs_type::Type{<:CRS})
  if crs_type <: LatLon
    crs_type(buff[2], buff[1])  # LatLon(lat, lon) from WKB(x=lon, y=lat)
  elseif crs_type <: LatLonAlt
    crs_type(buff[2], buff[1], buff[3])  # LatLonAlt(lat, lon, alt)
  else
    crs_type(buff...)  # fallback for other coordinate systems
  end
end

function parse_wkb_point(io::IOBuffer, parse_coords::Function, crs_type)
  buff = parse_coords(io)
  coord = create_crs_coord(buff, crs_type)
  return Point(coord)
end

# Batch parse multiple points efficiently
function parse_wkb_points(io::IOBuffer, n::Int, parse_coords::Function, crs_type::Type{<:CRS})
  # Read n coordinate buffers and convert to points
  map(1:n) do _
    buff = parse_coords(io)
    coord = create_crs_coord(buff, crs_type)
    Point(coord)
  end
end

function parse_wkb_linestring(io::IOBuffer, parse_coords::Function, crs_type; is_ring::Bool=false)
  num_points = Int(ltoh(read(io, UInt32)))
  
  # Use batch processing
  points = parse_wkb_points(io, num_points, parse_coords, crs_type)
  
  # Check if WKB writer included duplicate closing point (varies by implementation)
  has_equal_ends = length(points) >= 2 && points[1] == points[end]
  
  # Two-flag logic explained:
  # - is_ring: Semantic flag indicating this linestring is part of a polygon structure
  # - has_equal_ends: WKB format flag indicating if writer included duplicate closing point
  if is_ring || has_equal_ends
    # Return a Ring, exclude duplicate last point if present
    if has_equal_ends
      return Ring(points[1:end-1]...)
    else
      return Ring(points...)
    end
  else
    # It's an open linestring, return a Rope
    return Rope(points...)
  end
end

function parse_wkb_polygon(io::IOBuffer, parse_coords::Function, crs_type)
  num_rings = Int(ltoh(read(io, UInt32)))
  
  # Parse exterior ring using ring parsing function
  exterior_ring = parse_wkb_linestring(io, parse_coords, crs_type; is_ring=true)
  
  # Parse interior rings (holes) using map-do syntax
  hole_rings = map(2:num_rings) do ring_idx
    parse_wkb_linestring(io, parse_coords, crs_type; is_ring=true)
  end
  
  return PolyArea(exterior_ring, hole_rings...)
end


function parse_wkb_multipoint(io::IOBuffer, parse_coords::Function, crs_type)
  num_points = Int(ltoh(read(io, UInt32)))
  
  points = map(1:num_points) do _
    # Skip sub-geometry header (byte_order and wkb_type)
    skip(io, 5)
    parse_wkb_point(io, parse_coords, crs_type)
  end
  
  return Multi(points)
end

function parse_wkb_multilinestring(io::IOBuffer, parse_coords::Function, crs_type)
  num_lines = Int(ltoh(read(io, UInt32)))
  
  lines = map(1:num_lines) do _
    # Skip sub-geometry header (byte_order and wkb_type)
    skip(io, 5)
    parse_wkb_linestring(io, parse_coords, crs_type)
  end
  
  return Multi(lines)
end

function parse_wkb_multipolygon(io::IOBuffer, parse_coords::Function, crs_type)
  num_polygons = Int(ltoh(read(io, UInt32)))
  
  polygons = map(1:num_polygons) do _
    # Skip sub-geometry header (byte_order and wkb_type)
    skip(io, 5)
    parse_wkb_polygon(io, parse_coords, crs_type)
  end
  
  return Multi(polygons)
end