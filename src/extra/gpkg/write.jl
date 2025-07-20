# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# WKB type constants (shared with read.jl)
const WKB_POINT = 0x00000001
const WKB_LINESTRING = 0x00000002
const WKB_POLYGON = 0x00000003
const WKB_MULTIPOINT = 0x00000004
const WKB_MULTILINESTRING = 0x00000005
const WKB_MULTIPOLYGON = 0x00000006

const WKB_Z = 0x80000000
const WKB_M = 0x40000000
const WKB_ZM = 0xC0000000

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
  
  # For now, just handle simple polygons without holes
  # TODO: Add proper hole support if needed
  all_rings = [exterior_ring]
  
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
  # Clean up existing metadata (ignore if tables don't exist)
  DBInterface.execute(db, "DELETE FROM gpkg_contents WHERE table_name = ? AND EXISTS (SELECT 1 FROM gpkg_contents WHERE table_name = ?)", [layer, layer])
  DBInterface.execute(db, "DELETE FROM gpkg_geometry_columns WHERE table_name = ? AND EXISTS (SELECT 1 FROM gpkg_geometry_columns WHERE table_name = ?)", [layer, layer])
  
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