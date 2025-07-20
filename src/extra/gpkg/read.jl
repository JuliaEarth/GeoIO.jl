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
  
  min_z = max_z = min_m = max_m = nothing
  
  if has_envelope && envelope_type >= 1
    min_x = ltoh(read(io, Float64))
    max_x = ltoh(read(io, Float64))
    min_y = ltoh(read(io, Float64))
    max_y = ltoh(read(io, Float64))
  else
    # Default envelope when not present
    min_x = max_x = min_y = max_y = 0.0
  end
  
  if has_envelope
    if envelope_type >= 2
      min_z = ltoh(read(io, Float64))
      max_z = ltoh(read(io, Float64))
    end
    if envelope_type >= 3
      min_m = ltoh(read(io, Float64))
      max_m = ltoh(read(io, Float64))
    end
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
  
  coords_list = [x, y]
  
  if has_z
    z = read_value(read(io, Float64))
    push!(coords_list, z)
  end
  
  if has_m
    m = read_value(read(io, Float64))
  end
  
  return coords_list
end

function create_point_from_coords(coords_list::Vector{Float64}, crs_type)
  x, y = coords_list[1], coords_list[2]
  
  if isnan(x) && isnan(y)
    return nothing
  end
  
  # Handle different CRS types properly
  if isnothing(crs_type)
    # No CRS specified - use raw coordinates as Cartesian
    return Point(coords_list...)
  end
  
  # Determine CRS characteristics using CoordRefSystems.jl
  # For geographic coordinate systems (LatLon family)
  if crs_type <: LatLon
    # WKB stores geographic coordinates as x=longitude, y=latitude
    # LatLon constructor expects (latitude, longitude) order
    return Point(crs_type(y, x))  # LatLon(lat, lon) from WKB(x=lon, y=lat)
  elseif crs_type <: LatLonAlt
    # LatLonAlt always expects (lat, lon, alt)
    return Point(crs_type(y, x, coords_list[3]))
  else
    # For projected coordinate systems
    # Projected systems always have 2 coordinates. If file has Z, use Cartesian
    if length(coords_list) >= 3
      return Point(Cartesian(x, y, coords_list[3]))
    else
      return Point(crs_type(x, y))
    end
  end
end

function parse_wkb_point(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  coords_list = read_coordinate_values(io, byte_order, has_z, has_m)
  return create_point_from_coords(coords_list, crs_type)
end

function parse_wkb_linestring(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type; is_ring::Bool=false)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  num_points = read_value(read(io, UInt32))
  
  # Parse all points using map-do syntax
  points = map(1:num_points) do i
    coords_list = read_coordinate_values(io, byte_order, has_z, has_m)
    create_point_from_coords(coords_list, crs_type)
  end
  
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

function parse_wkb_polygon(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  num_rings = read_value(read(io, UInt32))
  
  # Parse exterior ring using ring parsing function
  exterior_ring = parse_wkb_linestring(io, byte_order, has_z, has_m, crs_type; is_ring=true)
  
  # Parse interior rings (holes) using map-do syntax
  hole_rings = map(2:num_rings) do ring_idx
    parse_wkb_linestring(io, byte_order, has_z, has_m, crs_type; is_ring=true)
  end
  
  # Always use the second branch approach as suggested in review
  return PolyArea(exterior_ring, hole_rings...)
end

function parse_wkb_geometry(blob::Vector{UInt8}, offset::Int, crs_type)
  io = IOBuffer(blob[offset+1:end])
  
  byte_order = read(io, UInt8)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  wkb_type = read_value(read(io, UInt32))
  
  base_type = wkb_type & 0x0FFFFFFF
  has_z = (wkb_type & WKB_Z) != 0
  has_m = (wkb_type & WKB_M) != 0
  
  if base_type == WKB_POINT
    return parse_wkb_point(io, byte_order, has_z, has_m, crs_type)
  elseif base_type == WKB_LINESTRING
    return parse_wkb_linestring(io, byte_order, has_z, has_m, crs_type)
  elseif base_type == WKB_POLYGON
    return parse_wkb_polygon(io, byte_order, has_z, has_m, crs_type)
  elseif base_type == WKB_MULTIPOINT
    return parse_wkb_multipoint(io, byte_order, has_z, has_m, crs_type)
  elseif base_type == WKB_MULTILINESTRING
    return parse_wkb_multilinestring(io, byte_order, has_z, has_m, crs_type)
  elseif base_type == WKB_MULTIPOLYGON
    return parse_wkb_multipolygon(io, byte_order, has_z, has_m, crs_type)
  else
    error("Unsupported WKB geometry type: $base_type")
  end
end

function parse_wkb_multipoint(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  num_points = read_value(read(io, UInt32))
  
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
    
    if inner_base_type != WKB_POINT
      error("Expected WKB_POINT ($WKB_POINT) in multipoint, got $inner_base_type")
    end
    
    # Use the same point creation logic as standalone points
    parse_wkb_point(io, byte_order_inner, inner_has_z, inner_has_m, crs_type)
  end
  
  # Create Multi geometry - simplified approach
  return Multi(points)
end

function parse_wkb_multilinestring(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  num_lines = read_value(read(io, UInt32))
  
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
    
    parse_wkb_linestring(io, byte_order_inner, inner_has_z, inner_has_m, crs_type; is_ring=false)
  end
  
  # Create Multi geometry - simplified approach
  return Multi(lines)
end

function parse_wkb_multipolygon(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  num_polygons = read_value(read(io, UInt32))
  
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
    
    parse_wkb_polygon(io, byte_order_inner, inner_has_z, inner_has_m, crs_type)
  end
  
  # Create Multi geometry - simplified approach
  return Multi(polygons)
end

function parse_gpb(blob::Vector{UInt8}, crs_type)
  header, offset = parse_gpb_header(blob)
  geometry = parse_wkb_geometry(blob, offset, crs_type)
  return geometry, header.srs_id
end

function get_crs_from_srid(db::SQLite.DB, srid::Int32)
  # Handle special cases
  if srid == 0
    return nothing
  elseif srid == -1
    return Cartesian{NoDatum}
  end
  
  # Handle well-known EPSG codes directly
  if srid == 4326
    return LatLon{WGS84Latest}
  elseif srid in [3857, 900913]  # Web Mercator variants
    return Mercator{WGS84Latest}
  elseif srid >= 32601 && srid <= 32660  # UTM North zones
    return Cartesian{WGS84Latest}
  elseif srid >= 32701 && srid <= 32760  # UTM South zones
    return Cartesian{WGS84Latest}
  end
  
  # Query the database for the CRS definition
  query = """
    SELECT definition
    FROM gpkg_spatial_ref_sys
    WHERE srs_id = ?
  """
  
  srs_result = DBInterface.execute(db, query, [srid])
  result = []
  for row in srs_result
    push!(result, row.definition)
  end
  
  if isempty(result)
    # Default for unknown SRID values
    @warn "Unknown SRID $srid, defaulting to WGS84"
    return LatLon{WGS84Latest}
  end
  
  # Parse the WKT definition - use basic validation instead of try-catch
  definition = result[1]
  if isnothing(definition) || isempty(strip(definition))
    @warn "Empty CRS definition for SRID $srid, defaulting to WGS84"
    return LatLon{WGS84Latest}
  end
  
  # Basic WKT format validation before parsing
  definition_upper = uppercase(strip(definition))
  if startswith(definition_upper, "GEOGCS") || startswith(definition_upper, "GEOGCRS")
    # Geographic coordinate system - likely LatLon based
    return LatLon{WGS84Latest}
  elseif startswith(definition_upper, "PROJCS") || startswith(definition_upper, "PROJCRS")
    # Projected coordinate system - likely Cartesian based
    return Cartesian{WGS84Latest}
  else
    # Unknown format, default to WGS84
    @warn "Unrecognized CRS definition format for SRID $srid, defaulting to WGS84"
    return LatLon{WGS84Latest}
  end
end

function gpkgread(fname::String; layer::Int=1, kwargs...)
  db = SQLite.DB(fname)
  
  # Get feature table names
  contents_query = """
    SELECT table_name, data_type
    FROM gpkg_contents
    WHERE data_type = 'features'
    ORDER BY table_name
  """
  contents_result = DBInterface.execute(db, contents_query)
  contents = [row.table_name for row in contents_result]
  
  isempty(contents) && error("No vector feature tables found in GeoPackage")
  layer > length(contents) && error("Layer $layer not found. GeoPackage contains $(length(contents)) feature layers")
  
  table_name = contents[layer]
  
  # Get geometry column information
  geom_query = """
    SELECT column_name, srs_id
    FROM gpkg_geometry_columns
    WHERE table_name = ?
  """
  geom_result = DBInterface.execute(db, geom_query, [table_name])
  geom_info = first(geom_result)
  geom_column = geom_info.column_name
  srs_id = Int32(geom_info.srs_id)
  crs = get_crs_from_srid(db, srs_id)
  
  # Get all data from the table
  data_query = "SELECT * FROM \"$table_name\""
  data_result = DBInterface.execute(db, data_query)
  
  # Step 1: Extract the table of attributes as a valid Tables.jl table
  table_data = []
  geometries = Geometry[]
  
  for row in data_result
    blob = getproperty(row, Symbol(geom_column))
    
    # Step 2: Extract the geometry column (i.e. geometrycollection)
    if !ismissing(blob) && !isnothing(blob)
      geom, _ = parse_gpb(blob, crs)
      if !isnothing(geom)
        push!(geometries, geom)
        
        # Create attribute row without geometry column
        row_dict = Dict()
        for name in propertynames(row)
          if name != Symbol(geom_column)
            row_dict[name] = getproperty(row, name)
          end
        end
        push!(table_data, (; row_dict...))
      end
    end
  end
  
  close(db)
  
  isempty(geometries) && error("No valid geometries found in table $table_name")
  
  # Handle case with no attribute columns (only geometry)
  if !isempty(table_data) && isempty(first(table_data))
    # No attributes - pass nothing to georef
    return georef(nothing, geometries)
  else
    # Create Tables.jl compatible table
    table = Tables.rowtable(table_data)
    
    # Step 3: Call georef(table, geoms) to produce the final result
    return georef(table, geometries)
  end
end