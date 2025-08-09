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
  
  # Filter out geometry column to get only attribute columns
  attr_columns = filter(col -> col != geom_column, all_columns)
  
  # 3. Execute queries to get attribute and geometry data separately
  if !isempty(attr_columns)
    # Build query for attribute columns only
    attr_columns_str = join(["\"$col\"" for col in attr_columns], ", ")
    table_result = DBInterface.execute(db, "SELECT $attr_columns_str FROM \"$table_name\"")
    cols = Tables.columns(table_result)
    names = Tables.columnnames(cols)
    table = NamedTuple{names}([Tables.getcolumn(cols, name) for name in names])
  else
    # No attribute columns, only geometry
    table = nothing
  end
  
  geom_result = DBInterface.execute(db, "SELECT \"$geom_column\" FROM \"$table_name\"")
  
  # 4. Read geometries (including missing/nothing values for asgeotable to handle)
  geoms = gpkgreadgeoms(geom_result, geom_column, crs_type)
  
  close(db)
  
  # 5. Combine attributes with geoms into a Tables.jl table
  # asgeotable() will handle missing/nothing geometries automatically
  if isnothing(table)
    # Only geometry column
    return (geometry=geoms,)
  else
    return (; zip(Tables.columnnames(table), Tables.columns(table))..., geometry=geoms)
  end
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
  
  # Use iterate to get the first row
  state = iterate(layer_iter)
  if isnothing(state)
    error("Layer $layer not found in GeoPackage")
  end
  first_row = state[1]
  
  table_name = first_row.table_name
  
  # Get geometry column information
  geom_result = DBInterface.execute(db,
    """
    SELECT column_name, srs_id
    FROM gpkg_geometry_columns
    WHERE table_name = ?
    """, [table_name])
  # Get geometry column information using iterate
  geom_state = iterate(Tables.rows(geom_result))
  if isnothing(geom_state)
    error("No geometry column found for table $table_name")
  end
  geom_info = geom_state[1]
  geom_column = geom_info.column_name
  srs_id = geom_info.srs_id
  crs_type = get_crs_from_srid(db, srs_id)
  
  return table_name, geom_column, crs_type
end

# This function is no longer needed - table_result is already a valid Tables.jl table

function gpkgreadgeoms(geom_result, geom_column::String, crs_type)
  geometries = Union{Geometry,Missing,Nothing}[]
  
  # Use Tables.rows interface
  for row in Tables.rows(geom_result)
    # Use Tables.getcolumn for accessing column values
    blob = Tables.getcolumn(row, Symbol(geom_column))
    if ismissing(blob) || isnothing(blob)
      push!(geometries, blob)  # Keep original missing/nothing value
    else
      # Valid blob data - parse the geometry
      geom = parse_gpb(blob, crs_type)
      push!(geometries, geom)
    end
  end
  
  return geometries
end

# Get CRS from SRID according to GeoPackage specification
# Reference: https://www.geopackage.org/spec/#gpkg_spatial_ref_sys_cols
# SRID possibilities:
#  0: Undefined geographic coordinate reference system
# -1: Undefined Cartesian coordinate reference system  
#  1-32766: Reserved for OGC use (EPSG codes)
#  32767-65535: Reserved for GeoPackage use
#  >65535: User-defined coordinate reference systems
function get_crs_from_srid(db::SQLite.DB, srid::Integer)
  # Handle special cases per GeoPackage spec
  if srid == 0
    # Undefined geographic coordinate reference system - use WGS84 as default
    return LatLon{WGS84Latest}
  elseif srid == -1
    # Undefined Cartesian coordinate reference system
    return Cartesian{NoDatum}
  end
  
  # Query the database for the organization and organization_coordsys_id
  srs_result = DBInterface.execute(db,
    """
    SELECT organization, organization_coordsys_id
    FROM gpkg_spatial_ref_sys
    WHERE srs_id = ?
    """, [srid])
  
  # Try to get the organization info
  org_info = nothing
  for row in srs_result
    org_info = row
    break
  end
  
  if isnothing(org_info)
    error("SRID $srid not found in gpkg_spatial_ref_sys table")
  end
  
  org_name = uppercase(org_info.organization)
  coord_id = org_info.organization_coordsys_id
  
  if org_name == "EPSG"
    return CoordRefSystems.get(EPSG{coord_id})
  elseif org_name == "ESRI"
    return CoordRefSystems.get(ESRI{coord_id})
  else
    # NONE organization indicates undefined/custom CRS
    # Also handles empty organization names and other organizations (custom authorities)
    # Use Cartesian as fallback for all undefined/custom cases
    return Cartesian{NoDatum}
  end
end

# Parse GeoPackage Binary (GPB) format - combines header and WKB geometry
function parse_gpb(blob::Vector{UInt8}, crs_type)
  header, offset = parse_gpb_header(blob)
  parse_wkb_geometry(blob, offset, crs_type)
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

function parse_wkb_geometry(blob::Vector{UInt8}, offset::Int, crs_type)
  io = IOBuffer(blob[offset+1:end])
  
  byte_order = read(io, UInt8)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  wkb_type = read_value(read(io, UInt32))
  
  base_type = wkb_type & 0x0FFFFFFF
  
  # Determine coordinate dimensionality from CRS type
  # Ignore WKB Z/M flags as they contradict the layer's CRS
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
    return parse_wkb_multipoint(io, read_value, crs_type)
  elseif base_type == WKB_MULTILINESTRING
    return parse_wkb_multilinestring(io, read_value, crs_type)
  elseif base_type == WKB_MULTIPOLYGON
    return parse_wkb_multipolygon(io, read_value, crs_type)
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

# Skip WKB coordinates including any Z/M values that we ignore
function skip_wkb_coords(io::IOBuffer, byte_order::UInt8, wkb_type::UInt32)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  # Always skip X and Y
  read_value(read(io, Float64))  # x
  read_value(read(io, Float64))  # y
  
  # Skip Z if present in WKB
  if (wkb_type & WKB_Z) != 0
    read_value(read(io, Float64))
  end
  
  # Skip M if present in WKB (we never use it)
  if (wkb_type & WKB_M) != 0
    read_value(read(io, Float64))
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
  # Validate coordinates
  if isnan(buff[1]) || isnan(buff[2])
    error("Invalid coordinates: NaN values found")
  end
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
  # We need both because polygon rings should always return Ring regardless of WKB format variation
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
  
  # Always use the second branch approach as suggested in review
  return PolyArea(exterior_ring, hole_rings...)
end


function parse_wkb_multipoint(io::IOBuffer, read_value::Function, crs_type)
  num_points = Int(read_value(read(io, UInt32)))
  ndims = CoordRefSystems.ncoords(crs_type)
  
  points = map(1:num_points) do _
    # Read sub-geometry header
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    skip(io, 4)  # Skip wkb_type since we know it's a point
    
    # Create parse_coords closure for this sub-geometry
    parse_coords = io -> read_coords_from_buffer(io, read_value_inner, ndims)
    
    # Call existing point parsing function
    parse_wkb_point(io, parse_coords, crs_type)
  end
  
  return Multi(points)
end

function parse_wkb_multilinestring(io::IOBuffer, read_value::Function, crs_type)
  num_lines = Int(read_value(read(io, UInt32)))
  ndims = CoordRefSystems.ncoords(crs_type)
  
  lines = map(1:num_lines) do _
    # Read sub-geometry header
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    skip(io, 4)  # Skip wkb_type since we know it's a linestring
    
    # Create parse_coords closure for this sub-geometry
    parse_coords = io -> read_coords_from_buffer(io, read_value_inner, ndims)
    
    # Call existing linestring parsing function
    parse_wkb_linestring(io, parse_coords, crs_type)
  end
  
  return Multi(lines)
end

function parse_wkb_multipolygon(io::IOBuffer, read_value::Function, crs_type)
  num_polygons = Int(read_value(read(io, UInt32)))
  ndims = CoordRefSystems.ncoords(crs_type)
  
  polygons = map(1:num_polygons) do _
    # Read sub-geometry header
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    skip(io, 4)  # Skip wkb_type since we know it's a polygon
    
    # Create parse_coords closure for this sub-geometry
    parse_coords = io -> read_coords_from_buffer(io, read_value_inner, ndims)
    
    # Call existing polygon parsing function
    parse_wkb_polygon(io, parse_coords, crs_type)
  end
  
  return Multi(polygons)
end