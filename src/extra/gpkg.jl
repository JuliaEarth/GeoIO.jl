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

# Table wrapper that implements GeoInterface.crs for GeoPackage tables
struct GPKGTable{T}
  table::T
  crs::Any
end

# Implement Tables.jl interface for the wrapper
Tables.istable(::Type{GPKGTable{T}}) where T = Tables.istable(T)
Tables.rowaccess(::Type{GPKGTable{T}}) where T = Tables.rowaccess(T)
Tables.columnaccess(::Type{GPKGTable{T}}) where T = Tables.columnaccess(T)
Tables.rows(gt::GPKGTable) = Tables.rows(gt.table)
Tables.columns(gt::GPKGTable) = Tables.columns(gt.table)
Tables.columnnames(gt::GPKGTable) = Tables.columnnames(gt.table)
Tables.getcolumn(gt::GPKGTable, i::Int) = Tables.getcolumn(gt.table, i)
Tables.getcolumn(gt::GPKGTable, nm::Symbol) = Tables.getcolumn(gt.table, nm)
Tables.schema(gt::GPKGTable) = Tables.schema(gt.table)

# Implement GeoInterface.crs method
GI.crs(gt::GPKGTable) = gt.crs

const WKB_POINT = 0x00000001
const WKB_LINESTRING = 0x00000002
const WKB_POLYGON = 0x00000003
const WKB_MULTIPOINT = 0x00000004
const WKB_MULTILINESTRING = 0x00000005
const WKB_MULTIPOLYGON = 0x00000006
const WKB_GEOMETRYCOLLECTION = 0x00000007

const WKB_Z = 0x80000000
const WKB_M = 0x40000000
const WKB_ZM = 0xC0000000

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
  try
    # For geographic coordinate systems (LatLon family)
    if crs_type <: LatLon
      # WKB stores geographic coordinates as x=longitude, y=latitude
      # LatLon constructor expects (latitude, longitude) order
      if length(coords_list) == 2
        return Point(crs_type(y, x))  # LatLon(lat, lon) from WKB(x=lon, y=lat)
      else
        # 3D geographic with altitude/elevation
        return Point(crs_type(y, x, coords_list[3]))
      end
    elseif crs_type <: LatLonAlt
      # LatLonAlt always expects (lat, lon, alt)
      if length(coords_list) >= 3
        return Point(crs_type(y, x, coords_list[3]))
      else
        # Fallback to 2D LatLon if no Z coordinate
        return Point(LatLon{datum(crs_type)}(y, x))
      end
    else
      # For projected coordinate systems (Cartesian, UTM, etc.)
      # WKB coordinate order matches CRS constructor order (x, y, [z])
      if length(coords_list) == 2
        return Point(crs_type(x, y))
      else
        return Point(crs_type(x, y, coords_list[3]))
      end
    end
  catch e
    # If CRS construction fails, fall back to raw coordinates
    @warn "Failed to create point with CRS $crs_type: $e. Using raw coordinates."
    return Point(coords_list...)
  end
end

function parse_wkb_point(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  coords_list = read_coordinate_values(io, byte_order, has_z, has_m)
  return create_point_from_coords(coords_list, crs_type)
end

function parse_wkb_linestring(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type; as_rope::Bool=false)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  num_points = read_value(read(io, UInt32))
  
  if num_points == 0
    return nothing
  end
  
  # Parse all points using helper functions
  points = Point[]
  
  for i in 1:num_points
    coords_list = read_coordinate_values(io, byte_order, has_z, has_m)
    point = create_point_from_coords(coords_list, crs_type)
    if !isnothing(point)
      push!(points, point)
    end
  end
  
  if isempty(points)
    return nothing
  end
  
  # If forced to be a Rope (for MultiLineString consistency) or open linestring
  if as_rope || length(points) < 2 || points[1] != points[end]
    return Rope(points...)
  else
    # It's a closed linestring, return a Ring (exclude the duplicate last point)
    return Ring(points[1:end-1]...)
  end
end

function parse_wkb_ring(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  # Parse ring by temporarily reading as linestring and converting to Ring
  # First read the number of points
  read_value = byte_order == 0x01 ? ltoh : ntoh
  num_points = read_value(read(io, UInt32))
  
  if num_points == 0
    return nothing
  end
  
  # Parse all points
  points = Point[]
  for i in 1:num_points
    coords_list = read_coordinate_values(io, byte_order, has_z, has_m)
    point = create_point_from_coords(coords_list, crs_type)
    if !isnothing(point)
      push!(points, point)
    end
  end
  
  if isempty(points)
    return nothing
  end
  
  # For rings, exclude duplicate last point if present (WKB rings are closed with duplicate point)
  if length(points) >= 2 && points[1] == points[end]
    return Ring(points[1:end-1]...)
  else
    # If not closed with duplicate, still return Ring (assuming it should be closed)
    return Ring(points...)
  end
end

function parse_wkb_polygon(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  num_rings = read_value(read(io, UInt32))
  
  if num_rings == 0
    return nothing
  end
  
  # Parse exterior ring using ring parsing function
  exterior_ring = parse_wkb_ring(io, byte_order, has_z, has_m, crs_type)
  if isnothing(exterior_ring)
    return nothing
  end
  
  # Parse interior rings (holes)
  hole_rings = Ring[]
  for ring_idx in 2:num_rings
    hole_ring = parse_wkb_ring(io, byte_order, has_z, has_m, crs_type)
    if !isnothing(hole_ring)
      push!(hole_rings, hole_ring)
    end
  end
  
  if isempty(hole_rings)
    return PolyArea(exterior_ring)
  else
    return PolyArea(exterior_ring, hole_rings...)
  end
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
  elseif base_type == WKB_GEOMETRYCOLLECTION
    return parse_wkb_geometrycollection(io, byte_order, has_z, has_m, crs_type)
  else
    error("Unsupported WKB geometry type: $base_type")
  end
end

function parse_wkb_multipoint(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  num_points = read_value(read(io, UInt32))
  
  if num_points == 0
    return nothing
  end
  
  points = Point[]
  for i in 1:num_points
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
    pt = parse_wkb_point(io, byte_order_inner, inner_has_z, inner_has_m, crs_type)
    if !isnothing(pt)
      push!(points, pt)
    end
  end
  
  # Create Multi geometry with fallback to avoid StackOverflowError
  # KNOWN LIMITATION: Due to a stack overflow in Meshes.jl Multi constructor
  # with certain CRS types, we fall back to returning the first component
  # if Multi creation fails. This preserves data access but loses Multi structure.
  if isempty(points)
    return nothing
  end
  
  try
    # Approach 1: Try with original points first  
    return Multi(points)
  catch e
    # Approach 2: Try with coordinate normalization
    try
      normalized_points = Point[]
      for pt in points
        coords_raw = CoordRefSystems.raw(coords(pt))
        # Create new point with raw coordinates to avoid CRS recursion
        new_point = Point(coords_raw...)
        push!(normalized_points, new_point)
      end
      return Multi(normalized_points)
    catch e2
      # Fallback: Return first point to prevent crashes (loses Multi structure)
      @warn "Failed to create Multi geometry: $e. Returning first point only."
      return points[1]
    end
  end
end

function parse_wkb_multilinestring(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  num_lines = read_value(read(io, UInt32))
  
  if num_lines == 0
    return nothing
  end
  
  # For MultiLineString, all components are Rope to maintain type consistency
  lines = Rope[]
  for i in 1:num_lines
    # Each linestring has its own header in multi-geometry
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    wkb_type_inner = read_value_inner(read(io, UInt32))
    
    # Parse the individual geometry's Z/M flags from its own header
    inner_base_type = wkb_type_inner & 0x0FFFFFFF
    inner_has_z = (wkb_type_inner & WKB_Z) != 0
    inner_has_m = (wkb_type_inner & WKB_M) != 0
    
    line = parse_wkb_linestring(io, byte_order_inner, inner_has_z, inner_has_m, crs_type; as_rope=true)
    if !isnothing(line)
      push!(lines, line)
    end
  end
  
  # Create Multi geometry with fallback to avoid StackOverflowError
  if isempty(lines)
    return nothing
  end
  
  try
    return Multi(lines)
  catch e
    # Fallback: Return first line to prevent crashes (loses Multi structure)
    @warn "Failed to create Multi LineString: $e. Returning first line only."
    return lines[1]
  end
end

function parse_wkb_multipolygon(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  num_polygons = read_value(read(io, UInt32))
  
  if num_polygons == 0
    return nothing
  end
  
  polygons = PolyArea[]
  for i in 1:num_polygons
    # Each polygon has its own header in multi-geometry
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    wkb_type_inner = read_value_inner(read(io, UInt32))
    
    # Parse the individual geometry's Z/M flags from its own header
    inner_base_type = wkb_type_inner & 0x0FFFFFFF
    inner_has_z = (wkb_type_inner & WKB_Z) != 0
    inner_has_m = (wkb_type_inner & WKB_M) != 0
    
    poly = parse_wkb_polygon(io, byte_order_inner, inner_has_z, inner_has_m, crs_type)
    if !isnothing(poly)
      push!(polygons, poly)
    end
  end
  
  # Create Multi geometry with fallback to avoid StackOverflowError
  if isempty(polygons)
    return nothing
  end
  
  try
    return Multi(polygons)
  catch e
    # Fallback: Return first polygon to prevent crashes (loses Multi structure)
    @warn "Failed to create Multi Polygon: $e. Returning first polygon only."
    return polygons[1]
  end
end

function parse_wkb_geometrycollection(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  num_geoms = read_value(read(io, UInt32))
  
  if num_geoms == 0
    return nothing
  end
  
  geoms = Geometry[]
  for i in 1:num_geoms
    # Each geometry in collection has its own WKB header
    geom_byte_order = read(io, UInt8)
    geom_read_value = geom_byte_order == 0x01 ? ltoh : ntoh
    geom_wkb_type = geom_read_value(read(io, UInt32))
    
    geom_base_type = geom_wkb_type & 0x0FFFFFFF
    geom_has_z = (geom_wkb_type & WKB_Z) != 0
    geom_has_m = (geom_wkb_type & WKB_M) != 0
    
    # Parse the specific geometry type directly to avoid infinite recursion
    geom = nothing
    if geom_base_type == WKB_POINT
      geom = parse_wkb_point(io, geom_byte_order, geom_has_z, geom_has_m, crs_type)
    elseif geom_base_type == WKB_LINESTRING
      geom = parse_wkb_linestring(io, geom_byte_order, geom_has_z, geom_has_m, crs_type)
    elseif geom_base_type == WKB_POLYGON
      geom = parse_wkb_polygon(io, geom_byte_order, geom_has_z, geom_has_m, crs_type)
    elseif geom_base_type == WKB_MULTIPOINT
      geom = parse_wkb_multipoint(io, geom_byte_order, geom_has_z, geom_has_m, crs_type)
    elseif geom_base_type == WKB_MULTILINESTRING
      geom = parse_wkb_multilinestring(io, geom_byte_order, geom_has_z, geom_has_m, crs_type)
    elseif geom_base_type == WKB_MULTIPOLYGON
      geom = parse_wkb_multipolygon(io, geom_byte_order, geom_has_z, geom_has_m, crs_type)
    # Note: Don't support nested GeometryCollections to avoid infinite recursion
    end
    
    if !isnothing(geom)
      push!(geoms, geom)
    end
  end
  
  return isempty(geoms) ? nothing : GeometrySet(geoms)
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
  
  # Try to get from EPSG directly first
  try
    return CoordRefSystems.get(EPSG{Int(srid)})
  catch
    # Not a supported EPSG code, continue to check the database
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
    # Default based on common SRID values
    if srid == 4326
      return LatLon{WGS84Latest}
    elseif srid in [3857, 900913]  # Web Mercator variants
      return Mercator{WGS84Latest}
    else
      @warn "Unknown SRID $srid, defaulting to WGS84"
      return LatLon{WGS84Latest}
    end
  end
  
  # Try to parse the WKT definition
  definition = result[1]
  try
    return CoordRefSystems.get(definition)
  catch e
    # If parsing fails, fall back to common defaults based on SRID
    @warn "Failed to parse CRS definition for SRID $srid: $e"
    if srid == 4326
      return LatLon{WGS84Latest}
    elseif srid in [3857, 900913]  # Web Mercator variants
      return Mercator{WGS84Latest}
    elseif srid >= 32601 && srid <= 32760  # UTM zones (both North and South)
      # For UTM zones, fallback to projected Cartesian since specific UTM types may not be available
      return Cartesian{WGS84Latest}
    else
      # For completely unknown SRIDs, default to WGS84
      return LatLon{WGS84Latest}
    end
  end
end

function gpkgread(fname::String; layer::Int=1, kwargs...)
  db = SQLite.DB(fname)
  
  contents_query = """
    SELECT table_name, data_type
    FROM gpkg_contents
    WHERE data_type = 'features'
    ORDER BY table_name
  """
  
  contents_result = DBInterface.execute(db, contents_query)
  contents = []
  for row in contents_result
    push!(contents, (table_name=row.table_name, data_type=row.data_type))
  end
  
  if isempty(contents)
    error("No feature tables found in GeoPackage")
  end
  
  if layer > length(contents)
    error("Layer $layer not found. GeoPackage contains $(length(contents)) feature layers")
  end
  
  table_name = contents[layer].table_name
  
  geom_query = """
    SELECT column_name, geometry_type_name, srs_id
    FROM gpkg_geometry_columns
    WHERE table_name = ?
  """
  
  geom_result = DBInterface.execute(db, geom_query, [table_name])
  geom_info = []
  for row in geom_result
    push!(geom_info, (column_name=row.column_name, geometry_type_name=row.geometry_type_name, srs_id=row.srs_id))
  end
  
  if isempty(geom_info)
    error("No geometry column found for table $table_name")
  end
  
  geom_column = geom_info[1].column_name
  srs_id = Int32(geom_info[1].srs_id)
  
  crs = get_crs_from_srid(db, srs_id)
  
  data_query = "SELECT * FROM \"$table_name\""
  data_result = DBInterface.execute(db, data_query)
  
  geometries = Geometry[]
  result = []
  
  for (idx, row) in enumerate(data_result)
    blob = getproperty(row, Symbol(geom_column))
    if !ismissing(blob) && !isnothing(blob)
      try
        geom, _ = parse_gpb(blob, crs)
        if !isnothing(geom)
          push!(geometries, geom)
          
          # Create new row without geometry column
          row_dict = Dict()
          for name in propertynames(row)
            if name != Symbol(geom_column)
              row_dict[name] = getproperty(row, name)
            end
          end
          push!(result, (; row_dict...))
        end
      catch e
        @warn "Failed to parse geometry at row $idx: $e"
      end
    end
  end
  
  if isempty(geometries)
    error("No valid geometries found in table $table_name")
  end
  
  domain = GeometrySet(geometries)
  
  close(db)
  
  # Convert result to proper table format that includes geometry as a column
  # We need to return a table with geometry column for the gis.jl workflow
  table_rows = []
  for (i, row) in enumerate(result)
    # Create a new row with geometry column
    new_row = merge(row, (geometry = geometries[i],))
    push!(table_rows, new_row)
  end
  
  # Create a table with CRS information
  table = Tables.rowtable(table_rows)
  
  # For now, just pass the CRS directly
  # TODO: Implement proper CRS conversion when needed
  
  return GPKGTable(table, crs)
end

function create_gpb_header(srs_id::Int32, geom::Geometry, envelope_type::Int=1)
  io = IOBuffer()
  
  write(io, UInt8(0x47), UInt8(0x50))
  write(io, UInt8(0))
  
  flags = UInt8(0x20 | (envelope_type << 1))
  write(io, flags)
  
  write(io, htol(srs_id))
  
  if envelope_type >= 1
    bbox = boundingbox(geom)
    write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.min))[1])))
    write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.max))[1])))
    write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.min))[2])))
    write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.max))[2])))
  end
  
  if envelope_type >= 2 && paramdim(geom) >= 3
    bbox = boundingbox(geom)
    write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.min))[3])))
    write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.max))[3])))
  end
  
  return take!(io)
end

function write_wkb_point(io::IOBuffer, point::Point)
  coords_pt = CoordRefSystems.raw(coords(point))
  dim = length(coords_pt)
  
  write(io, UInt8(0x01))
  
  wkb_type = WKB_POINT
  if dim == 3
    wkb_type |= WKB_Z
  end
  write(io, UInt32(wkb_type))
  
  write(io, Float64(coords_pt[1]))
  write(io, Float64(coords_pt[2]))
  
  if dim >= 3
    write(io, Float64(coords_pt[3]))
  end
end

function write_wkb_linestring(io::IOBuffer, rope::Rope)
  points = vertices(rope)
  dim = paramdim(first(points))
  
  write(io, UInt8(0x01))
  
  wkb_type = WKB_LINESTRING
  if dim == 3
    wkb_type |= WKB_Z
  end
  write(io, UInt32(wkb_type))
  
  write(io, UInt32(length(points)))
  
  for point in points
    coords_pt = CoordRefSystems.raw(coords(point))
    write(io, Float64(coords_pt[1]))
    write(io, Float64(coords_pt[2]))
    
    if dim >= 3
      write(io, Float64(coords_pt[3]))
    end
  end
end

function write_wkb_ring_as_linestring(io::IOBuffer, ring::Ring)
  points = vertices(ring)
  dim = paramdim(first(points))
  
  write(io, UInt8(0x01))
  
  wkb_type = WKB_LINESTRING
  if dim == 3
    wkb_type |= WKB_Z
  end
  write(io, UInt32(wkb_type))
  
  # Write count including the duplicate last point to close the ring
  write(io, UInt32(length(points) + 1))
  
  # Write all points
  for point in points
    coords_pt = CoordRefSystems.raw(coords(point))
    write(io, Float64(coords_pt[1]))
    write(io, Float64(coords_pt[2]))
    
    if dim >= 3
      write(io, Float64(coords_pt[3]))
    end
  end
  
  # Write first point again to close the ring
  first_coords = CoordRefSystems.raw(coords(first(points)))
  write(io, Float64(first_coords[1]))
  write(io, Float64(first_coords[2]))
  
  if dim >= 3
    write(io, Float64(first_coords[3]))
  end
end

function write_wkb_polygon(io::IOBuffer, poly::PolyArea)
  exterior_ring = boundary(poly)
  hole_rings = Ring[]
  
  # Get interior rings if they exist
  try
    # Try to access holes - this may fail if there are no holes
    for ring in poly
      if ring != exterior_ring
        push!(hole_rings, ring)
      end
    end
  catch
    # No holes, which is fine
  end
  
  all_rings = [exterior_ring; hole_rings]
  
  dim = paramdim(first(vertices(exterior_ring)))
  
  write(io, UInt8(0x01))
  
  wkb_type = WKB_POLYGON
  if dim == 3
    wkb_type |= WKB_Z
  end
  write(io, UInt32(wkb_type))
  
  write(io, UInt32(length(all_rings)))
  
  for ring in all_rings
    points = vertices(ring)
    write(io, UInt32(length(points) + 1))
    
    for point in points
      coords_pt = CoordRefSystems.raw(coords(point))
      write(io, Float64(coords_pt[1]))
      write(io, Float64(coords_pt[2]))
      
      if dim >= 3
        write(io, Float64(coords_pt[3]))
      end
    end
    
    first_coords = CoordRefSystems.raw(coords(first(points)))
    write(io, Float64(first_coords[1]))
    write(io, Float64(first_coords[2]))
    
    if dim >= 3
      write(io, Float64(first_coords[3]))
    end
  end
end

function write_wkb_geometry(io::IOBuffer, geom::Geometry)
  if geom isa Point
    write_wkb_point(io, geom)
  elseif geom isa Rope
    write_wkb_linestring(io, geom)
  elseif geom isa PolyArea
    write_wkb_polygon(io, geom)
  elseif geom isa Ring
    # Write Ring as closed LineString to match GDAL behavior
    write_wkb_ring_as_linestring(io, geom)
  elseif geom isa Multi
    parts = parent(geom)
    first_part = first(parts)
    
    write(io, UInt8(0x01))
    
    if first_part isa Point
      wkb_type = WKB_MULTIPOINT
    elseif first_part isa Rope
      wkb_type = WKB_MULTILINESTRING
    elseif first_part isa PolyArea
      wkb_type = WKB_MULTIPOLYGON
    else
      error("Unsupported multi-geometry type")
    end
    
    if paramdim(first_part) == 3
      wkb_type |= WKB_Z
    end
    
    write(io, UInt32(wkb_type))
    write(io, UInt32(length(parts)))
    
    for part in parts
      write_wkb_geometry(io, part)
    end
  else
    error("Unsupported geometry type: $(typeof(geom))")
  end
end

function create_gpb(geom::Geometry, srs_id::Int32)
  header = create_gpb_header(srs_id, geom)
  
  wkb_io = IOBuffer()
  write_wkb_geometry(wkb_io, geom)
  wkb_data = take!(wkb_io)
  
  return vcat(header, wkb_data)
end

function get_srid_for_crs(db::SQLite.DB, crs)
  if isnothing(crs)
    return Int32(0)
  elseif crs <: Cartesian{NoDatum}
    return Int32(-1)
  end
  
  # Try to extract EPSG code from the CRS type
  crs_string = string(crs)
  
  # Check if it's an EPSG-based CRS
  if occursin("EPSG", crs_string)
    # Try to extract the EPSG code
    m = match(r"EPSG\{(\d+)\}", crs_string)
    if !isnothing(m)
      return Int32(parse(Int, m.captures[1]))
    end
  end
  
  # Handle specific well-known CRS types
  if crs <: LatLon{WGS84Latest} || crs <: LatLon{WGS84{1762}}
    return Int32(4326)
  elseif crs <: Cartesian{WGS84Latest} || crs <: Cartesian{WGS84{1762}}
    # Use SRID -1 for undefined Cartesian systems
    return Int32(-1)
  elseif crs <: Cartesian
    # Any other Cartesian system
    return Int32(-1)
  end
  
  # For other CRS types, try to find or insert into gpkg_spatial_ref_sys
  # For now, default to 4326 (WGS84) only for geographic systems
  # TODO: Implement proper CRS registration in the database
  return Int32(4326)
end

function ensure_gpkg_tables(db::SQLite.DB)
  DBInterface.execute(db, """
    CREATE TABLE IF NOT EXISTS gpkg_spatial_ref_sys (
      srs_name TEXT NOT NULL,
      srs_id INTEGER NOT NULL PRIMARY KEY,
      organization TEXT NOT NULL,
      organization_coordsys_id INTEGER NOT NULL,
      definition TEXT NOT NULL,
      description TEXT
    )
  """)
  
  DBInterface.execute(db, """
    INSERT OR IGNORE INTO gpkg_spatial_ref_sys 
    (srs_name, srs_id, organization, organization_coordsys_id, definition, description)
    VALUES 
    ('WGS 84', 4326, 'EPSG', 4326, 'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]]', 'WGS 84'),
    ('Undefined geographic SRS', 0, 'NONE', 0, 'undefined', 'undefined geographic coordinate reference system'),
    ('Undefined Cartesian SRS', -1, 'NONE', -1, 'undefined', 'undefined Cartesian coordinate reference system')
  """)
  
  DBInterface.execute(db, """
    CREATE TABLE IF NOT EXISTS gpkg_contents (
      table_name TEXT NOT NULL PRIMARY KEY,
      data_type TEXT NOT NULL,
      identifier TEXT UNIQUE,
      description TEXT DEFAULT '',
      last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
      min_x DOUBLE,
      min_y DOUBLE,
      max_x DOUBLE,
      max_y DOUBLE,
      srs_id INTEGER,
      CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
    )
  """)
  
  DBInterface.execute(db, """
    CREATE TABLE IF NOT EXISTS gpkg_geometry_columns (
      table_name TEXT NOT NULL,
      column_name TEXT NOT NULL,
      geometry_type_name TEXT NOT NULL,
      srs_id INTEGER NOT NULL,
      z TINYINT NOT NULL,
      m TINYINT NOT NULL,
      CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
      CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
      CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
    )
  """)
end

function infer_geometry_type(geoms::AbstractVector{<:Geometry})
  if isempty(geoms)
    return "GEOMETRY"
  end
  
  # Check for homogeneous geometry types using eltype dispatch
  T = eltype(geoms)
  
  if T <: Point
    return "POINT"
  elseif T <: Rope
    return "LINESTRING"
  elseif T <: Ring
    return "LINESTRING"  # Ring is saved as LINESTRING to match GDAL behavior
  elseif T <: PolyArea
    return "POLYGON"
  elseif T <: Multi
    # Check the element type of Multi
    element_type = eltype(parent(first(geoms)))
    if element_type <: Point
      return "MULTIPOINT"
    elseif element_type <: Rope
      return "MULTILINESTRING"
    elseif element_type <: PolyArea
      return "MULTIPOLYGON"
    end
  end
  
  # Fallback for mixed or unknown types
  return "GEOMETRY"
end

function gpkgwrite(fname::String, geotable; layer::String="features", kwargs...)
  db = SQLite.DB(fname)
  
  ensure_gpkg_tables(db)
  
  # Drop existing table if it exists to avoid data duplication  
  DBInterface.execute(db, "DROP TABLE IF EXISTS \"$layer\"")
  try
    DBInterface.execute(db, "DELETE FROM gpkg_contents WHERE table_name = ?", [layer])
    DBInterface.execute(db, "DELETE FROM gpkg_geometry_columns WHERE table_name = ?", [layer])
  catch
    # Tables might not exist yet, which is fine
  end
  
  table = values(geotable)
  domain = GeoTables.domain(geotable)
  
  geoms = collect(domain)
  crs = GeoTables.crs(domain)
  srs_id = get_srid_for_crs(db, crs)
  
  # Handle case where table is Nothing (no attribute columns)
  cols = isnothing(table) ? Symbol[] : Tables.columnnames(table)
  
  # Start with basic table structure (no automatic fid column)
  create_table_sql = """
    CREATE TABLE IF NOT EXISTS "$layer" (
      geom BLOB NOT NULL
    """
  
  # Add columns only if table is not Nothing
  if !isnothing(table)
    for col in cols
      col_str = string(col)
      coltype = eltype(Tables.getcolumn(table, col))
      
      if coltype <: Integer
        sql_type = "INTEGER"
      elseif coltype <: AbstractFloat
        sql_type = "REAL"
      else
        sql_type = "TEXT"
      end
      
      create_table_sql *= ",\n    \"$col_str\" $sql_type"
    end
  end
  
  create_table_sql *= "\n)"
  
  DBInterface.execute(db, create_table_sql)
  
  bbox = boundingbox(domain)
  min_coords = CoordRefSystems.raw(coords(bbox.min))
  max_coords = CoordRefSystems.raw(coords(bbox.max))
  
  DBInterface.execute(db, """
    INSERT OR REPLACE INTO gpkg_contents 
    (table_name, data_type, identifier, min_x, min_y, max_x, max_y, srs_id)
    VALUES (?, 'features', ?, ?, ?, ?, ?, ?)
  """, [layer, layer, min_coords[1], min_coords[2], max_coords[1], max_coords[2], srs_id])
  
  geom_type = infer_geometry_type(geoms)
  z_flag = paramdim(first(geoms)) >= 3 ? 1 : 0
  
  DBInterface.execute(db, """
    INSERT OR REPLACE INTO gpkg_geometry_columns 
    (table_name, column_name, geometry_type_name, srs_id, z, m)
    VALUES (?, 'geom', ?, ?, ?, 0)
  """, [layer, geom_type, srs_id, z_flag])
  
  # Insert data row by row without prepared statements
  if isnothing(table)
    # Handle case with no attribute columns - just geometry
    for (i, geom) in enumerate(geoms)
      gpb_blob = create_gpb(geom, srs_id)
      insert_sql = "INSERT INTO \"$layer\" (geom) VALUES (?)"
      DBInterface.execute(db, insert_sql, [gpb_blob])
    end
  else
    # Handle case with attribute columns
    for (i, row) in enumerate(Tables.rows(table))
      geom = geoms[i]
      gpb_blob = create_gpb(geom, srs_id)
      
      # Build insert SQL dynamically
      col_names = ["geom"; [string(col) for col in cols]]
      col_placeholders = repeat(["?"], length(col_names))
      insert_sql = "INSERT INTO \"$layer\" ($(join(col_names, ", "))) VALUES ($(join(col_placeholders, ", ")))"
      
      values = Any[gpb_blob]
      for col in cols
        val = getproperty(row, col)
        push!(values, val)
      end
      
      DBInterface.execute(db, insert_sql, values)
    end
  end
  close(db)
  
  return fname
end