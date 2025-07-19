using SQLite
using Tables
using GeoInterface
using GeoFormatTypes
using CoordRefSystems
using Meshes
using GeoTables
using Meshes: paramdim, boundingbox, vertices, boundary, coords

struct GeoPackageBinaryHeader
  magic::UInt16
  version::UInt8
  flags::UInt8
  srs_id::Int32
  min_x::Union{Float64,Nothing}
  max_x::Union{Float64,Nothing}
  min_y::Union{Float64,Nothing}
  max_y::Union{Float64,Nothing}
  min_z::Union{Float64,Nothing}
  max_z::Union{Float64,Nothing}
  min_m::Union{Float64,Nothing}
  max_m::Union{Float64,Nothing}
end

# Table wrapper that implements GeoInterface.crs for GeoPackage tables
struct GeoPackageTable{T}
  table::T
  crs::Any
end

# Implement Tables.jl interface for the wrapper
Tables.istable(::Type{GeoPackageTable{T}}) where T = Tables.istable(T)
Tables.rowaccess(::Type{GeoPackageTable{T}}) where T = Tables.rowaccess(T)
Tables.columnaccess(::Type{GeoPackageTable{T}}) where T = Tables.columnaccess(T)
Tables.rows(gt::GeoPackageTable) = Tables.rows(gt.table)
Tables.columns(gt::GeoPackageTable) = Tables.columns(gt.table)
Tables.columnnames(gt::GeoPackageTable) = Tables.columnnames(gt.table)
Tables.getcolumn(gt::GeoPackageTable, i::Int) = Tables.getcolumn(gt.table, i)
Tables.getcolumn(gt::GeoPackageTable, nm::Symbol) = Tables.getcolumn(gt.table, nm)
Tables.schema(gt::GeoPackageTable) = Tables.schema(gt.table)

# Implement GeoInterface.crs method
GeoInterface.crs(gt::GeoPackageTable) = gt.crs

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
  
  min_x = min_y = max_x = max_y = nothing
  min_z = max_z = min_m = max_m = nothing
  
  if has_envelope
    if envelope_type >= 1
      min_x = ltoh(read(io, Float64))
      max_x = ltoh(read(io, Float64))
      min_y = ltoh(read(io, Float64))
      max_y = ltoh(read(io, Float64))
    end
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

function parse_wkb_point(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  x = read_value(read(io, Float64))
  y = read_value(read(io, Float64))
  
  if isnan(x) && isnan(y)
    return nothing
  end
  
  coords_list = [x, y]
  
  if has_z
    z = read_value(read(io, Float64))
    push!(coords_list, z)
  end
  
  if has_m
    m = read_value(read(io, Float64))
  end
  
  # Create point with appropriate CRS
  if crs_type <: LatLon
    if length(coords_list) == 2
      return Point(crs_type(y, x))  # LatLon(lat, lon) - note swapped order
    else
      return Point(crs_type(y, x, coords_list[3]))
    end
  else
    return Point(coords_list...)
  end
end

function parse_wkb_linestring(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  num_points = read_value(read(io, UInt32))
  
  # Create the first point to determine the concrete type
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
  
  # Create first point with appropriate CRS
  first_point = if crs_type <: LatLon
    if length(coords_list) == 2
      Point(crs_type(y, x))  # LatLon(lat, lon) - note swapped order
    else
      Point(crs_type(y, x, coords_list[3]))
    end
  else
    Point(coords_list...)
  end
  
  # Initialize typed array with the correct concrete type
  points = [first_point]
  
  # Parse remaining points
  for i in 2:num_points
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
    
    # Create point with appropriate CRS
    if crs_type <: LatLon
      if length(coords_list) == 2
        push!(points, Point(crs_type(y, x)))  # LatLon(lat, lon) - note swapped order
      else
        push!(points, Point(crs_type(y, x, coords_list[3])))
      end
    else
      push!(points, Point(coords_list...))
    end
  end
  
  # Check if the linestring is closed (first point equals last point)
  if length(points) >= 2 && points[1] == points[end]
    # It's a closed linestring, return a Ring (exclude the duplicate last point)
    return Ring(points[1:end-1])
  else
    # It's an open linestring, return a Rope
    return Rope(points)
  end
end

function parse_wkb_linestring_as_rope(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  num_points = read_value(read(io, UInt32))
  
  # Create the first point to determine the concrete type
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
  
  # Create first point with appropriate CRS
  first_point = if crs_type <: LatLon
    if length(coords_list) == 2
      Point(crs_type(y, x))  # LatLon(lat, lon) - note swapped order
    else
      Point(crs_type(y, x, coords_list[3]))
    end
  else
    Point(coords_list...)
  end
  
  # Initialize typed array with the correct concrete type
  points = [first_point]
  
  # Parse remaining points
  for i in 2:num_points
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
    
    # Create point with appropriate CRS
    if crs_type <: LatLon
      if length(coords_list) == 2
        push!(points, Point(crs_type(y, x)))  # LatLon(lat, lon) - note swapped order
      else
        push!(points, Point(crs_type(y, x, coords_list[3])))
      end
    else
      push!(points, Point(coords_list...))
    end
  end
  
  # For MultiLineString components, always return Rope to maintain consistency
  return Rope(points)
end

function parse_wkb_polygon(io::IOBuffer, byte_order::UInt8, has_z::Bool, has_m::Bool, crs_type)
  read_value = byte_order == 0x01 ? ltoh : ntoh
  
  num_rings = read_value(read(io, UInt32))
  
  if num_rings == 0
    return nothing
  end
  
  num_points = read_value(read(io, UInt32))
  
  # Create the first point to determine the concrete type
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
  
  # Create first point with appropriate CRS
  first_point = if crs_type <: LatLon
    if length(coords_list) == 2
      Point(crs_type(y, x))  # LatLon(lat, lon) - note swapped order
    else
      Point(crs_type(y, x, coords_list[3]))
    end
  else
    Point(coords_list...)
  end
  
  # Initialize typed array with the correct concrete type
  exterior_points = [first_point]
  
  # Parse remaining points
  for i in 2:num_points
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
    
    # Create point with appropriate CRS
    if crs_type <: LatLon
      if length(coords_list) == 2
        push!(exterior_points, Point(crs_type(y, x)))  # LatLon(lat, lon) - note swapped order
      else
        push!(exterior_points, Point(crs_type(y, x, coords_list[3])))
      end
    else
      push!(exterior_points, Point(coords_list...))
    end
  end
  
  exterior_ring = Ring(exterior_points[1:end-1])
  
  hole_rings = Ring[]
  for ring_idx in 2:num_rings
    num_points = read_value(read(io, UInt32))
    
    # Create the first point to determine the concrete type
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
    
    # Create first point with appropriate CRS
    first_hole_point = if crs_type <: LatLon
      if length(coords_list) == 2
        Point(crs_type(y, x))  # LatLon(lat, lon) - note swapped order
      else
        Point(crs_type(y, x, coords_list[3]))
      end
    else
      Point(coords_list...)
    end
    
    # Initialize typed array with the correct concrete type
    hole_points = [first_hole_point]
    
    # Parse remaining points
    for i in 2:num_points
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
      
      # Create point with appropriate CRS
      if crs_type <: LatLon
        if length(coords_list) == 2
          push!(hole_points, Point(crs_type(y, x)))  # LatLon(lat, lon) - note swapped order
        else
          push!(hole_points, Point(crs_type(y, x, coords_list[3])))
        end
      else
        push!(hole_points, Point(coords_list...))
      end
    end
    
    push!(hole_rings, Ring(hole_points[1:end-1]))
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
    num_points = read_value(read(io, UInt32))
    
    # Parse first point to determine type
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    wkb_type_inner = read_value_inner(read(io, UInt32))
    first_pt = parse_wkb_point(io, byte_order_inner, has_z, has_m, crs_type)
    
    points = first_pt !== nothing ? [first_pt] : Point[]
    
    for i in 2:num_points
      byte_order_inner = read(io, UInt8)
      read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
      wkb_type_inner = read_value_inner(read(io, UInt32))
      pt = parse_wkb_point(io, byte_order_inner, has_z, has_m, crs_type)
      pt !== nothing && push!(points, pt)
    end
    return Multi(points)
  elseif base_type == WKB_MULTILINESTRING
    num_lines = read_value(read(io, UInt32))
    
    # Parse first line to determine type
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    wkb_type_inner = read_value_inner(read(io, UInt32))
    first_line = parse_wkb_linestring_as_rope(io, byte_order_inner, has_z, has_m, crs_type)
    
    # All components will be Rope to maintain consistency
    lines = first_line !== nothing ? [first_line] : Rope[]
    
    for i in 2:num_lines
      byte_order_inner = read(io, UInt8)
      read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
      wkb_type_inner = read_value_inner(read(io, UInt32))
      line = parse_wkb_linestring_as_rope(io, byte_order_inner, has_z, has_m, crs_type)
      line !== nothing && push!(lines, line)
    end
    return Multi(lines)
  elseif base_type == WKB_MULTIPOLYGON
    num_polygons = read_value(read(io, UInt32))
    
    # Parse first polygon to determine type
    byte_order_inner = read(io, UInt8)
    read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
    wkb_type_inner = read_value_inner(read(io, UInt32))
    first_poly = parse_wkb_polygon(io, byte_order_inner, has_z, has_m, crs_type)
    
    polygons = first_poly !== nothing ? [first_poly] : PolyArea[]
    
    for i in 2:num_polygons
      byte_order_inner = read(io, UInt8)
      read_value_inner = byte_order_inner == 0x01 ? ltoh : ntoh
      wkb_type_inner = read_value_inner(read(io, UInt32))
      poly = parse_wkb_polygon(io, byte_order_inner, has_z, has_m, crs_type)
      poly !== nothing && push!(polygons, poly)
    end
    return Multi(polygons)
  elseif base_type == WKB_GEOMETRYCOLLECTION
    num_geoms = read_value(read(io, UInt32))
    geoms = Geometry[]
    for i in 1:num_geoms
      remaining_blob = read(io)
      prepend!(remaining_blob, [byte_order])
      seekstart(io)
      write(io, remaining_blob)
      seekstart(io)
      geom = parse_wkb_geometry(remaining_blob, 0, crs_type)
      geom !== nothing && push!(geoms, geom)
    end
    return GeometrySet(geoms)
  else
    error("Unsupported WKB geometry type: $base_type")
  end
end

function parse_gpb(blob::Vector{UInt8}, crs_type)
  header, offset = parse_gpb_header(blob)
  geometry = parse_wkb_geometry(blob, offset, crs_type)
  return geometry, header.srs_id
end

function get_crs_from_srid(db::SQLite.DB, srid::Int32)
  if srid == 4326
    return LatLon{WGS84Latest}
  elseif srid == 0
    return nothing
  elseif srid == -1
    return Cartesian{NoDatum}
  end
  
  query = """
    SELECT definition
    FROM gpkg_spatial_ref_sys
    WHERE srs_id = ?
  """
  
  srs_result = SQLite.DBInterface.execute(db, query, [srid])
  result = []
  for row in srs_result
    push!(result, (definition=row.definition,))
  end
  
  if isempty(result)
    return LatLon{WGS84Latest}  # Default to WGS84 for unknown SRIDs
  end
  
  return LatLon{WGS84Latest}
end

function gpkgread(fname::String; layer::Int=1, kwargs...)
  db = SQLite.DB(fname)
  
  contents_query = """
    SELECT table_name, data_type
    FROM gpkg_contents
    WHERE data_type = 'features'
    ORDER BY table_name
  """
  
  contents_result = SQLite.DBInterface.execute(db, contents_query)
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
  
  geom_result = SQLite.DBInterface.execute(db, geom_query, [table_name])
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
  data_result = SQLite.DBInterface.execute(db, data_query)
  
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
  
  if all(g -> g isa Point, geometries)
    domain = PointSet(geometries)
  else
    domain = GeometrySet(geometries)
  end
  
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
  
  # Convert CRS to the format expected by GeoInterface
  gi_crs = if !isnothing(crs)
    if crs <: LatLon{WGS84Latest}
      GeoFormatTypes.EPSG{1}((4326,))
    else
      nothing
    end
  else
    nothing
  end
  
  return GeoPackageTable(table, gi_crs)
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
  elseif crs <: LatLon{WGS84Latest} || crs <: LatLon{WGS84{1762}}
    return Int32(4326)
  elseif crs <: Cartesian{NoDatum}
    return Int32(-1)
  else
    return Int32(4326)
  end
end

function ensure_gpkg_tables(db::SQLite.DB)
  SQLite.DBInterface.execute(db, """
    CREATE TABLE IF NOT EXISTS gpkg_spatial_ref_sys (
      srs_name TEXT NOT NULL,
      srs_id INTEGER NOT NULL PRIMARY KEY,
      organization TEXT NOT NULL,
      organization_coordsys_id INTEGER NOT NULL,
      definition TEXT NOT NULL,
      description TEXT
    )
  """)
  
  SQLite.DBInterface.execute(db, """
    INSERT OR IGNORE INTO gpkg_spatial_ref_sys 
    (srs_name, srs_id, organization, organization_coordsys_id, definition, description)
    VALUES 
    ('WGS 84', 4326, 'EPSG', 4326, 'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]]', 'WGS 84'),
    ('Undefined geographic SRS', 0, 'NONE', 0, 'undefined', 'undefined geographic coordinate reference system'),
    ('Undefined Cartesian SRS', -1, 'NONE', -1, 'undefined', 'undefined Cartesian coordinate reference system')
  """)
  
  SQLite.DBInterface.execute(db, """
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
  
  SQLite.DBInterface.execute(db, """
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
  if all(g -> g isa Point, geoms)
    return "POINT"
  elseif all(g -> g isa Rope, geoms)
    return "LINESTRING"
  elseif all(g -> g isa Ring, geoms)
    return "LINESTRING"  # Ring is saved as LINESTRING to match GDAL behavior
  elseif all(g -> g isa PolyArea, geoms)
    return "POLYGON"
  elseif all(g -> g isa Multi{<:Point}, geoms)
    return "MULTIPOINT"
  elseif all(g -> g isa Multi{<:Rope}, geoms)
    return "MULTILINESTRING"
  elseif all(g -> g isa Multi{<:PolyArea}, geoms)
    return "MULTIPOLYGON"
  else
    return "GEOMETRY"
  end
end

function gpkgwrite(fname::String, geotable; layer::String="features", kwargs...)
  db = SQLite.DB(fname)
  
  ensure_gpkg_tables(db)
  
  # Drop existing table if it exists to avoid data duplication  
  SQLite.DBInterface.execute(db, "DROP TABLE IF EXISTS \"$layer\"")
  try
    SQLite.DBInterface.execute(db, "DELETE FROM gpkg_contents WHERE table_name = ?", [layer])
    SQLite.DBInterface.execute(db, "DELETE FROM gpkg_geometry_columns WHERE table_name = ?", [layer])
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
  
  SQLite.DBInterface.execute(db, create_table_sql)
  
  bbox = boundingbox(domain)
  min_coords = CoordRefSystems.raw(coords(bbox.min))
  max_coords = CoordRefSystems.raw(coords(bbox.max))
  
  SQLite.DBInterface.execute(db, """
    INSERT OR REPLACE INTO gpkg_contents 
    (table_name, data_type, identifier, min_x, min_y, max_x, max_y, srs_id)
    VALUES (?, 'features', ?, ?, ?, ?, ?, ?)
  """, [layer, layer, min_coords[1], min_coords[2], max_coords[1], max_coords[2], srs_id])
  
  geom_type = infer_geometry_type(geoms)
  z_flag = paramdim(first(geoms)) >= 3 ? 1 : 0
  
  SQLite.DBInterface.execute(db, """
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
      SQLite.DBInterface.execute(db, insert_sql, [gpb_blob])
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
      
      SQLite.DBInterface.execute(db, insert_sql, values)
    end
  end
  close(db)
  
  return fname
end