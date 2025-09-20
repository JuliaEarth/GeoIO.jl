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
  # If the power never goes out and no programs ever crash
  # on you system then Synchronous = OFF is for you

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

CREATE TABLE gpkg_contents (
        table_name TEXT NOT NULL PRIMARY KEY,
        data_type TEXT NOT NULL,
        identifier TEXT UNIQUE,
        description TEXT DEFAULT '',
        last_change DATETIME NOT NULL DEFAULT
        (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
        min_x DOUBLE, min_y DOUBLE,
        max_x DOUBLE, max_y DOUBLE,
        srs_id INTEGER,
        CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES
        gpkg_spatial_ref_sys(srs_id)
);

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
    DBInterface.execute(db, "PRAGMA application_id = $GPKG_APPLICATION_ID ")
    DBInterface.execute(db, "PRAGMA user_version = $GPKG_1_4_VERSION ")
  end

  #  According to https://www.geopackage.org/spec/#r11
  # The gpkg_spatial_ref_sys table SHALL contain at a minimum
  # 1. the record with an srs_id of 4326 SHALL correspond to WGS-84 as defined by EPSG in 4326
  # 2. the record with an srs_id of -1 SHALL be used for undefined Cartesian coordinate reference systems
  # 3. the record with an srs_id of 0 SHALL be used for undefined geographic coordinate reference systems
  tb = [(
    srs_name="Undefined Cartesian SRS",
    srs_id=-1,
    organization="NONE",
    organization_coordsys_id=-1,
    definition="undefined",
    description="undefined geographic coordinate reference system",
    definition_12_063="undefined"
  )]
  SQLite.load!(tb, db, "gpkg_spatial_ref_sys", replace=true)
  tb = [(
    srs_name="Undefined geographic SRS",
    srs_id=0,
    organization="NONE",
    organization_coordsys_id=0,
    definition="undefined",
    description="undefined geographic coordinate reference system",
    definition_12_063="undefined"
  )]
  SQLite.load!(tb, db, "gpkg_spatial_ref_sys", replace=true)
  tb = [(
    srs_name="WGS 84 geodectic",
    srs_id=4326,
    organization="EPSG",
    organization_coordsys_id=4326,
    definition=CoordRefSystems.wkt2(EPSG{4326}),
    description="longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid",
    definition_12_063=CoordRefSystems.wkt2(EPSG{4326})
  )]
  SQLite.load!(tb, db, "gpkg_spatial_ref_sys", replace=true)

  table = values(geotable)
  domain = GeoTables.domain(geotable)
  crs = GeoTables.crs(domain)
  geom = collect(domain)

  _extracttablevals(db, table, domain, crs, geom)
end

function _extracttablevals(db, table, domain, crs, geom)
  if crs <: Cartesian
    srs = ""
    srid = -1
  elseif crs <: LatLon{WGS84Latest}
    srs = "EPSG"
    srid = 4326
  else
    srs = string(CoordRefSystems.code(crs))
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
    isnothing(table) ? [(; geom=GeomType(g),) for (i, g) in zip(1:length(gpkgbinary), gpkgbinary)] :
    [(; t..., geom=GeomType(g)) for (t, g) in zip(Tables.rowtable(table), gpkgbinary)]
  SQLite.load!(table, db, replace=false) # autogenerates table name
  # replace=false controls whether an INSERT INTO ... statement is generated or a REPLACE INTO ....
  tn =
    (
      DBInterface.execute(
        db,
        """ SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN ("gpkg_contents", "gpkg_spatial_ref_sys", "gpkg_geometry_columns") """
      ) |> first
    ).name

  bbox = boundingbox(domain)
  mincoords = CoordRefSystems.raw(coords(bbox.min))
  maxcoords = CoordRefSystems.raw(coords(bbox.max))
  contents = [(
    table_name=tn,
    data_type="features",
    identifier=tn,
    description="",
    last_change=Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SSZ"),
    min_x=mincoords[1],
    min_y=mincoords[2],
    max_x=maxcoords[1],
    max_y=maxcoords[2],
    srs_id=srid
  )]
  SQLite.load!(contents, db, "gpkg_contents", replace=true)
  if srid != 4326
    srstb = [(
      srs_name="",
      srs_id=srid,
      organization=srs[1:4],
      organization_coordsys_id=srid,
      definition=CoordRefSystems.wkt2(crs),
      description="",
      definition_12_063=CoordRefSystems.wkt2(crs)
    )]
    SQLite.load!(srstb, db, "gpkg_spatial_ref_sys", replace=true)
  end
  geomcolumns = [(
    table_name=tn,
    column_name="geom",
    geometry_type_name=geomtype,
    srs_id=srid,
    z=paramdim((geom |> first)) > 2 ? 1 : 0,
    m=0
  )]
  SQLite.load!(geomcolumns, db, "gpkg_geometry_columns", replace=true)
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

function writegpkgheader(srs_id, geom)
  io = IOBuffer()
  write(io, [0x47, 0x50]) # 'GP' in ASCII
  write(io, zero(UInt8)) #  0 = version 1

  flagsbyte = UInt8(0x07 >> 1)
  write(io, flagsbyte)

  write(io, htol(UInt32(srs_id)))

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
  if wkbtype == wkbPolygon || wkbtype == wkbPolygonZ || wkbtype == wkbPolygon25D
    _wkbpolygon(io, wkbtype, [boundary(geom::PolyArea)])
  elseif wkbtype == wkbLineString || wkbtype == wkbLineString || wkbtype == wkbLineString25D
    coordlist = vertices(geom)
    if typeof(geom) <: Ring
      return _wkblinearring(io, wkbtype, coordlist)
    end
    _wkblinestring(io, wkbtype, coordlist)
  elseif wkbtype == wkbPoint || wkbtype == wkbPointZ || wkbtype == wkbPoint25D
    coordinates = CoordRefSystems.raw(coords(geom))
    _wkbcoordinates(io, wkbtype, coordinates)
  else
    @error "my hovercraft is full of eels: $wkbtype"
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
  write(io, htol(Float64(coords[2])))
  write(io, htol(Float64(coords[1])))

  if (UInt32(wkbtype) > 1000) || !(iszero(Int(wkbtype) & (0x80000000 | 0x40000000)))
    write(io, htol(Float64(coords[3])))
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