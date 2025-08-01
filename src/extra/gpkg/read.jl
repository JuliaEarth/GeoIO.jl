# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

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

function read_coordinate_values(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  x = read_value(read(io, Float64))
  y = read_value(read(io, Float64))
  
  coords = if has_z
    z = read_value(read(io, Float64))
    (x, y, z)
  else
    (x, y)
  end
  
  # skip M coordinate if present (we don't use it)
  if has_m
    read_value(read(io, Float64))
  end
  
  return coords
end

function parse_wkb_geometry(blob::Vector{UInt8}, offset::Int, crs_type)
  io = IOBuffer(blob[offset+1:end])
  
  byte_order = read(io, UInt8)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  wkb_type = read_value(read(io, UInt32))
  
  base_type = wkb_type & 0x0FFFFFFF
  has_z = (wkb_type & WKB_Z) != 0
  has_m = (wkb_type & WKB_M) != 0
  
  # Create parse_coords closure that captures byte_order, has_z, has_m
  parse_coords = function(io_inner)
    return read_coordinate_values(io_inner, byte_order, has_z, has_m)
  end

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

function create_point_from_coords(coords, crs_type)
  x, y = coords[1], coords[2]
  
  if isnan(x) && isnan(y)
    return nothing
  end
  
  # Determine CRS characteristics using CoordRefSystems.jl
  # For geographic coordinate systems (LatLon family)
  if crs_type <: LatLon
    # WKB stores geographic coordinates as x=longitude, y=latitude
    # LatLon constructor expects (latitude, longitude) order
    return Point(crs_type(y, x))  # LatLon(lat, lon) from WKB(x=lon, y=lat)
  elseif crs_type <: LatLonAlt
    # LatLonAlt always expects (lat, lon, alt)
    return Point(crs_type(y, x, coords[3]))
  else
    # For projected coordinate systems
    # Projected systems always have 2 coordinates. If file has Z, use Cartesian
    if length(coords) >= 3
      return Point(Cartesian(x, y, coords[3]))
    else
      return Point(crs_type(x, y))
    end
  end
end

function create_crs_coord_from_buffer(buff, crs_type)
  if crs_type <: LatLon
    return crs_type(buff[2], buff[1])  # LatLon(lat, lon) from WKB(x=lon, y=lat)
  elseif crs_type <: LatLonAlt
    return crs_type(buff[2], buff[1], buff[3])  # LatLonAlt(lat, lon, alt)
  else
    return crs_type(buff...)  # fallback for other coordinate systems
  end
end

function parse_wkb_points(io::IOBuffer, n::Int, parse_coords::Function, crs_type)
  # Read n chunks of coordinates and convert them to crs_type objects  
  coords_vector = map(1:n) do _
    buff = parse_coords(io)
    create_crs_coord_from_buffer(buff, crs_type)
  end
  
  # Return Point.(coords)
  return Point.(coords_vector)
end

function parse_wkb_point(io::IOBuffer, parse_coords::Function, crs_type)
  coords = parse_coords(io)
  return create_point_from_coords(coords, crs_type)
end

function parse_wkb_linestring(io::IOBuffer, parse_coords::Function, crs_type; is_ring::Bool=false)
  num_points = Int(ltoh(read(io, UInt32)))
  
  # Use batch processing for points
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


function parse_wkb_multipoint(io::IOBuffer, parse_coords::Function, crs_type)
  num_points = Int(ltoh(read(io, UInt32)))
  
  # Parse all points using map-do syntax
  points = map(1:num_points) do i
    # Each point has its own header in multi-geometry
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    wkb_type_inner = read_value_inner(read(io, UInt32))
    
    # Parse the individual geometry's Z/M flags from its own header
    inner_base_type = wkb_type_inner & 0x0FFFFFFF
    inner_has_z = (wkb_type_inner & WKB_Z) != 0
    inner_has_m = (wkb_type_inner & WKB_M) != 0
    
    # Create inner parse_coords for this specific point
    inner_parse_coords = function(io_inner)
      return read_coordinate_values(io_inner, byte_order_inner, inner_has_z, inner_has_m)
    end
    
    # Use the same point creation logic as standalone points
    parse_wkb_point(io, inner_parse_coords, crs_type)
  end
  
  # Create Multi geometry - simplified approach
  return Multi(points)
end

function parse_wkb_multilinestring(io::IOBuffer, parse_coords::Function, crs_type)
  num_lines = Int(ltoh(read(io, UInt32)))
  
  # Parse all linestrings using map-do syntax
  # For MultiLineString, all components are Rope to maintain type consistency
  lines = map(1:num_lines) do i
    # Each linestring has its own header in multi-geometry
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    wkb_type_inner = read_value_inner(read(io, UInt32))
    
    # Parse the individual geometry's Z/M flags from its own header
    inner_base_type = wkb_type_inner & 0x0FFFFFFF
    inner_has_z = (wkb_type_inner & WKB_Z) != 0
    inner_has_m = (wkb_type_inner & WKB_M) != 0
    
    # Create inner parse_coords for this specific linestring
    inner_parse_coords = function(io_inner)
      return read_coordinate_values(io_inner, byte_order_inner, inner_has_z, inner_has_m)
    end
    
    parse_wkb_linestring(io, inner_parse_coords, crs_type; is_ring=false)
  end
  
  # Create Multi geometry - simplified approach
  return Multi(lines)
end

function parse_wkb_multipolygon(io::IOBuffer, parse_coords::Function, crs_type)
  num_polygons = Int(ltoh(read(io, UInt32)))
  
  # Parse all polygons using map-do syntax
  polygons = map(1:num_polygons) do i
    # Each polygon has its own header in multi-geometry
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    wkb_type_inner = read_value_inner(read(io, UInt32))
    
    # Parse the individual geometry's Z/M flags from its own header
    inner_base_type = wkb_type_inner & 0x0FFFFFFF
    inner_has_z = (wkb_type_inner & WKB_Z) != 0
    inner_has_m = (wkb_type_inner & WKB_M) != 0
    
    # Create inner parse_coords for this specific polygon
    inner_parse_coords = function(io_inner)
      return read_coordinate_values(io_inner, byte_order_inner, inner_has_z, inner_has_m)
    end
    
    parse_wkb_polygon(io, inner_parse_coords, crs_type)
  end
  
  # Create Multi geometry - simplified approach
  return Multi(polygons)
end

# Parse GeoPackage Binary (GPB) format - combines header and WKB geometry
function parse_gpb(blob::Vector{UInt8}, crs_type)
  header, offset = parse_gpb_header(blob)
  geometry = parse_wkb_geometry(blob, offset, crs_type)
  return geometry, header.srs_id
end

# Get CRS from SRID according to GeoPackage specification
# SRID possibilities:
#  0: Undefined geographic coordinate reference system
# -1: Undefined Cartesian coordinate reference system  
#  1-32766: Reserved for OGC use
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
  
  # Process first row directly (forward-only iterator)
  org_info = nothing
  for row in srs_result
    org_info = row
    break
  end
  
  if isnothing(org_info)
    return Cartesian{NoDatum}
  end
  
  # Handle different CRS organizations
  org = ismissing(org_info.organization) ? "" : uppercase(org_info.organization)
  coord_id = org_info.organization_coordsys_id
  
  if org == "EPSG"
    return CoordRefSystems.get(EPSG{coord_id})
  elseif org == "ESRI"
    return CoordRefSystems.get(ESRI{coord_id})
  elseif org == "NONE" || org == ""
    # NONE organization indicates undefined/custom CRS
    return Cartesian{NoDatum}
  else
    # Other organizations (custom authorities) - use Cartesian as fallback
    # This branch is reachable for custom organization names
    return Cartesian{NoDatum}
  end
end

function gpkgreadtable(table_result, geom_column::String)
  # Get the first row to determine structure
  row_iter = Tables.rows(table_result)
  first_row = nothing
  for row in row_iter
    first_row = row
    break
  end
  
  if isnothing(first_row)
    return nothing
  end
  
  # Get attribute names from the first row (geometry column already excluded)
  attr_names = propertynames(first_row)
  if isempty(attr_names)
    return nothing
  end
  
  # Collect all rows in a single pass
  rows = Vector{Vector{Any}}()
  for row in Tables.rows(table_result)
    push!(rows, [getproperty(row, name) for name in attr_names])
  end
  
  if isempty(rows)
    return nothing
  end
  
  # Create a named tuple of vectors (Tables.jl compatible)
  columns = NamedTuple{Tuple(attr_names)}([
    [row[i] for row in rows] for i in 1:length(attr_names)
  ])
  
  return columns
end

function gpkgreadgeoms(data_result, geom_column::String, crs_type)
  geometries = Geometry[]
  geom_sym = Symbol(geom_column)
  
  for row in data_result
    blob = getproperty(row, geom_sym)
    if !ismissing(blob) && !isnothing(blob)
      geom, _ = parse_gpb(blob, crs_type)
      if !isnothing(geom)
        push!(geometries, geom)
      end
    end
  end
  
  return geometries
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
  # Count total layers and find the requested one without allocating an array
  table_name = ""  # Initialize with correct type to avoid Union{Nothing,String}
  layer_count = 0
  
  for row in contents_result
    layer_count += 1
    if layer_count == layer
      table_name = row.table_name
    end
  end
  
  if layer_count == 0
    error("No vector feature tables found in GeoPackage")
  end
  
  if layer > layer_count
    error("Layer $layer not found. GeoPackage contains $layer_count feature layers")
  end
  
  if table_name == ""
    error("Failed to retrieve table name for layer $layer")
  end
  
  # Get geometry column information
  geom_result = DBInterface.execute(db,
    """
    SELECT column_name, srs_id
    FROM gpkg_geometry_columns
    WHERE table_name = ?
    """, [table_name])
  geom_info = first(geom_result)
  geom_column = geom_info.column_name
  srs_id = geom_info.srs_id
  crs_type = get_crs_from_srid(db, srs_id)
  
  return table_name, geom_column, crs_type
end

function gpkgread(fname::String; layer::Int=1, kwargs...)
  db = SQLite.DB(fname)
  
  # 1. Read metadata to extract names of tables and CRS type
  table_name, geom_column, crs_type = gpkgmetadata(db, layer)
  
  # 2. Get all column names from the table
  columns_result = DBInterface.execute(db, "PRAGMA table_info(\"$table_name\")")
  all_columns = [row.name for row in columns_result]
  
  # Filter out geometry column to get only attribute columns
  attr_columns = filter(col -> col != geom_column, all_columns)
  
  # 3. Execute queries to get attribute and geometry data separately
  if !isempty(attr_columns)
    # Build query for attribute columns only
    attr_columns_str = join(["\"$col\"" for col in attr_columns], ", ")
    table_result = DBInterface.execute(db, "SELECT $attr_columns_str FROM \"$table_name\"")
    table = gpkgreadtable(table_result, geom_column)
  else
    # No attribute columns, only geometry
    table = nothing
  end
  
  geom_result = DBInterface.execute(db, "SELECT \"$geom_column\" FROM \"$table_name\"")
  
  # 4. Read geometries given the database object, the appropriate table name and CRS type
  geoms = gpkgreadgeoms(geom_result, geom_column, crs_type)
  
  close(db)
  
  # 5. Combine attributes with geoms into a final geotable
  if isnothing(table) || isempty(table)
    return georef(nothing, geoms)
  else
    return georef(table, geoms)
  end
end