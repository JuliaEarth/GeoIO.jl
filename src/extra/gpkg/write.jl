# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gpkgwrite(fname, geotable;)
  db = SQLite.DB(fname)

  DBInterface.execute(db, "PRAGMA synchronous=0")
  # Commits can be orders of magnitude faster with
  # Setting PRAGMA synchronous=OFF but,
  # can cause the database to go corrupt
  # if there is an operating system crash or power failure.

  table = values(geotable)
  domain = GeoTables.domain(geotable)
  crs = GeoTables.crs(domain)
  geom = collect(domain)
  DBInterface.execute(db, "PRAGMA application_id = $GPKG_APPLICATION_ID ")
  DBInterface.execute(db, "PRAGMA user_version = $GPKG_1_4_VERSION ")
  creategpkgtables(db, table, domain, crs, geom)
  DBInterface.execute(db, "PRAGMA optimize;")
  # Applications with short-lived database connections should run "PRAGMA optimize;"
  # just once, prior to closing each database connection.
  DBInterface.close!(db)
end

function creategpkgtables(db, table, domain, crs, geom)
  if crs <: Cartesian
    srs = ""
    srid = -1
  elseif crs <: LatLon{WGS84Latest}
    srs = "EPSG"
    srid = 4326
  else
    srs = string(CoordRefSystems.code(crs))[1:4]
    srid = parse(Int32, srs)
  end
  gpkgbinary = map(geom) do ft
    gpkgbinheader = writegpkgheader(srid, ft)
    io = IOBuffer()
    writewkbgeom(io, ft)
    vcat(gpkgbinheader, take!(io))
  end

  geomtype = _geomtype(geom)
  GeomType = _sqlitetype(geomtype)

  table =
    isnothing(table) ? [(; geom=GeomType(g),) for (_, g) in zip(1:length(gpkgbinary), gpkgbinary)] :
    [(; t..., geom=GeomType(g)) for (t, g) in zip(Tables.rowtable(table), gpkgbinary)]
  rows = Tables.rows(table)
  sch = Tables.schema(rows)
  columns = [
    string(SQLite.esc_id(String(sch.names[i])), ' ', SQLite.sqlitetype(sch.types !== nothing ? sch.types[i] : Any))
    for i in eachindex(sch.names)
  ]

  # https://www.geopackage.org/spec/#r29
  #  A feature table SHALL have a primary key column of type INTEGER and that column SHALL act as a rowid alias.
  DBInterface.execute(db, "CREATE TABLE features ($(join(columns, ',')));")
  # The use of the AUTOINCREMENT keyword is optional but recommended. 
  # Implementers MAY omit the AUTOINCREMENT keyword for performance reasons, with the understanding that doing so has the potential to allow primary key identifiers to be reused.

  params = chop(repeat("?,", length(sch.names)))
  columns = join(SQLite.esc_id.(string.(sch.names)), ",")
  stmt = SQLite.Stmt(db, "INSERT INTO features ($columns) VALUES ($params)";)
  handle = SQLite._get_stmt_handle(stmt)
  SQLite.transaction(db) do
    row = nothing
    if row === nothing
      state = iterate(rows)
      state === nothing && return
      row, st = state
    end
    while true
      Tables.eachcolumn(sch, row) do val, col, _
        SQLite.bind!(stmt, col, val)
      end
      r = GC.@preserve row SQLite.C.sqlite3_step(handle)
      if r == SQLite.C.SQLITE_DONE
        SQLite.C.sqlite3_reset(handle)
      elseif r != SQLite.C.SQLITE_ROW
        e = SQLite.sqliteexception(db, stmt)
        SQLite.C.sqlite3_reset(handle)
        throw(e)
      end
      state = iterate(rows, st)
      state === nothing && break
      row, st = state
    end
  end

  bbox = boundingbox(domain)
  mincoords = CoordRefSystems.raw(coords(bbox.min))
  maxcoords = CoordRefSystems.raw(coords(bbox.max))
  minx, miny, maxx, maxy = mincoords[1], mincoords[2], maxcoords[1], maxcoords[2]
  z = paramdim((geom |> first)) > 2 ? 1 : 0

  SQLite.transaction(db) do
    DBInterface.execute(
      db,
      """
    CREATE TABLE gpkg_spatial_ref_sys (
            srs_name TEXT NOT NULL, srs_id INTEGER NOT NULL PRIMARY KEY,
            organization TEXT NOT NULL, organization_coordsys_id INTEGER NOT NULL,
            definition  TEXT NOT NULL, description TEXT,
            definition_12_063 TEXT NOT NULL
    );
    """
    )

    #  According to https://www.geopackage.org/spec/#r11
    # The gpkg_spatial_ref_sys table SHALL contain at a minimum
    # 1. the record with an srs_id of 4326 SHALL correspond to WGS-84 as defined by EPSG in 4326
    # 2. the record with an srs_id of -1 SHALL be used for undefined Cartesian coordinate reference systems
    # 3. the record with an srs_id of 0 SHALL be used for undefined geographic coordinate reference systems
    DBInterface.execute(
      db,
      """
   INSERT INTO gpkg_spatial_ref_sys 
        (srs_name, srs_id, organization, organization_coordsys_id, definition, description, definition_12_063) 
        VALUES 
        ('Undefined Cartesian SRS', -1, 'NONE', -1, 'undefined', 'undefined geographic coordinate reference system', 'undefined'),
        ('Undefined geographic SRS', 0, 'NONE', 0, 'undefined', 'undefined geographic coordinate reference system', 'undefined'),
        ('WGS 84 geodectic', 4326, 'EPSG', 4326, 'GEOGCRS["WGS 84",DATUM["World Geodetic System 1984",ELLIPSOID["WGS 84",6378137,298.257223563,LENGTHUNIT["metre",1]]],PRIMEM["Greenwich",0,ANGLEUNIT["degree",0.0174532925199433]],CS[ellipsoidal,2],AXIS["geodetic latitude (Lat)",north,ORDER[1],ANGLEUNIT["degree",0.0174532925199433]],AXIS["geodetic longitude (Lon)",east,ORDER[2],ANGLEUNIT["degree",0.0174532925199433]],ID["EPSG",4326]]', 'longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid', 'GEOGCRS["WGS 84",DATUM["World Geodetic System 1984",ELLIPSOID["WGS 84",6378137,298.257223563,LENGTHUNIT["metre",1]]],PRIMEM["Greenwich",0,ANGLEUNIT["degree",0.0174532925199433]],CS[ellipsoidal,2],AXIS["geodetic latitude (Lat)",north,ORDER[1],ANGLEUNIT["degree",0.0174532925199433]],AXIS["geodetic longitude (Lon)",east,ORDER[2],ANGLEUNIT["degree",0.0174532925199433]],ID["EPSG",4326]]');
      """
    )

    if srid != 4326 && srid > 0
      DBInterface.execute(  # Insert non-existing CRS record into gpkg_spatial_ref_sys table. srs_id referenced by gpkg_contents, gpkg_geometry_columns
        db,
        """
    INSERT INTO gpkg_spatial_ref_sys 
            (srs_name, srs_id, organization, organization_coordsys_id, definition, description, definition_12_063)
            VALUES
            (?, ?, ?, ?, ?, ?, ?);
        """,
        ["", srid, srs, srid, CoordRefSystems.wkt2(crs), "", CoordRefSystems.wkt2(crs)]
      )
    end

    DBInterface.execute(
      db,
      """
    CREATE TABLE gpkg_contents (
            table_name TEXT NOT NULL PRIMARY KEY,
            data_type TEXT NOT NULL,
            identifier TEXT UNIQUE NOT NULL,
            description TEXT DEFAULT '',
            last_change DATETIME NOT NULL DEFAULT
            (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
            min_x DOUBLE, min_y DOUBLE,
            max_x DOUBLE, max_y DOUBLE,
            srs_id INTEGER,
            CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES
            gpkg_spatial_ref_sys(srs_id)
    );
    """
    )

    DBInterface.execute(
      db,
      """
    INSERT INTO gpkg_contents 
            (table_name, data_type, identifier, min_x, min_y, max_x, max_y, srs_id)
            VALUES
            (?, ?, ?, ?, ?, ?, ?, ?);
      """,
      ["features", "features", "features", minx, miny, maxx, maxy, srid]
    )

    DBInterface.execute(
      db,
      """
    CREATE TABLE gpkg_geometry_columns (
          table_name TEXT NOT NULL,
          column_name TEXT NOT NULL,
          geometry_type_name TEXT NOT NULL,
          srs_id INTEGER NOT NULL,
          z TINYINT NOT NULL,
          m TINYINT NOT NULL,
          CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
          CONSTRAINT uk_gc_table_name UNIQUE (table_name),
          CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
          CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys (srs_id)
    );
    """
    )

    DBInterface.execute(
      db,
      """
    INSERT INTO gpkg_geometry_columns 
            (table_name, column_name, geometry_type_name, srs_id, z, m)
            VALUES
            (?, ?, ?, ?, ?, ?);
      """,
      ["features", "geom", geomtype, srid, z, 0]
    )
  end
end

function _wkbtype(geometry)
  if geometry isa Point
    return wkbPoint
  elseif geometry isa Rope || geometry isa Ring
    return wkbLineString
  elseif geometry isa PolyArea
    return wkbPolygon
  elseif geometry isa Multi
    fg = parent(geometry) |> first
    return wkbGeometryType(Int(_wkbtype(fg)) + 3)
  else
    @error "my hovercraft is full of eels: $geometry"
  end
end

function _wkbsetz(type::wkbGeometryType)
  return wkbGeometryType(Int(type) + 1000)
  # ISO WKB Flavour
end

function writegpkgheader(srsid, geom)
  io = IOBuffer()
  write(io, [0x47, 0x50]) # 'GP' in ASCII
  write(io, zero(UInt8)) #  0 = version 1

  flagsbyte = UInt8(0x07 >> 1)
  write(io, flagsbyte)

  write(io, htol(Int32(srsid)))

  bbox = boundingbox(geom)
  write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.min))[2])))
  write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.max))[2])))
  write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.min))[1])))
  write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.max))[1])))

  if paramdim(geom) >= 3
    write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.min))[3])))
    write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.max))[3])))
  end

  return take!(io)
end

function writewkbgeom(io, geom)
  wkbtype = paramdim(geom) < 3 ? _wkbtype(geom) : _wkbsetz(_wkbtype(geom))
  write(io, htol(one(UInt8)))
  write(io, htol(UInt32(wkbtype)))
  _wkbgeom(io, wkbtype, geom)
end

function writewkbsf(io, wkbtype, geom)
  if wkbtype == wkbPolygon || wkbtype == wkbPolygonZ
    _wkbpolygon(io, wkbtype, [boundary(geom::PolyArea)])
  elseif wkbtype == wkbLineString || wkbtype == wkbLineString
    coordlist = vertices(geom)
    if typeof(geom) <: Ring
      return _wkblinearring(io, wkbtype, coordlist)
    end
    _wkblinestring(io, wkbtype, coordlist)
  elseif wkbtype == wkbPoint || wkbtype == wkbPointZ
    coordinates = CoordRefSystems.raw(coords(geom))
    _wkbcoordinates(io, wkbtype, coordinates)
  else
    throw(ErrorException("Well-Known Binary Geometry not supported: $wkbtype"))
  end
end

function _wkbgeom(io, wkbtype, geom)
  if Int(wkbtype) > 3
    _wkbmulti(io, wkbtype, geom)
  else
    writewkbsf(io, wkbtype, geom)
  end
end

function _wkbcoordinates(io, wkbtype, coords)
  write(io, htol(coords[2]))
  write(io, htol(coords[1]))

  if (UInt32(wkbtype) > 1000) || !(iszero(Int(wkbtype) & (0x80000000 | 0x40000000)))
    write(io, htol(coords[3]))
  end
end

function _wkblinestring(io, wkb_type, coord_list)
  write(io, htol(UInt32(length(coord_list))))
  for n_coords in coord_list
    coordinates = CoordRefSystems.raw(coords(n_coords))
    _wkbcoordinates(io, wkb_type, coordinates)
  end
end

function _wkblinearring(io, wkb_type, coord_list)
  write(io, htol(UInt32(length(coord_list) + 1)))
  for n_coords in coord_list
    coordinates = CoordRefSystems.raw(coords(n_coords))
    _wkbcoordinates(io, wkb_type, coordinates)
  end
  _wkbcoordinates(io, wkb_type, CoordRefSystems.raw(first(coord_list) |> coords))
end

function _wkbpolygon(io, wkb_type, rings)
  write(io, htol(UInt32(length(rings))))
  for ring in rings
    coord_list = vertices(ring)
    _wkblinestring(io, wkb_type, coord_list)
  end
end

function _wkbmulti(io, wkbtype, geoms)
  write(io, htol(UInt32(length(geoms |> parent))))
  for sf in geoms |> parent
    write(io, one(UInt8))
    write(io, UInt32(Int(wkbMultiPolygon) - 3))
    writewkbsf(io, wkbGeometryType(Int(wkbtype) - 3), sf)
  end
end