# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gpkgtable(fname; layer=1)
  db = gpkgdatabase(fname)
  table = gpkgextract(db; layer)
  DBInterface.close!(db)
  table
end

function gpkgdatabase(fname)
  # connect to SQLite database on disk
  db = SQLite.DB(fname)

  # According to https://www.geopackage.org/spec/#r6
  # PRAGMA integrity_check returns a single row with the value 'ok'
  if first(DBInterface.execute(db, "PRAGMA integrity_check;")).integrity_check != "ok"
    throw(ErrorException("database integrity at risk"))
  end

  # According to https://www.geopackage.org/spec/#r7
  # PRAGMA foreign_key_check (w/ no parameter value) returns an empty result set
  if !(isempty(DBInterface.execute(db, "PRAGMA foreign_key_check;")))
    throw(ErrorException("foreign key violation(s)"))
  end

  # According to https://www.geopackage.org/spec/#r10
  # A GeoPackage SHALL include a 'gpkg_spatial_ref_sys' table
  if isnothing(SQLite.tableinfo(db, "gpkg_spatial_ref_sys"))
    throw(ErrorException("missing required metadata tables in the GeoPackage SQL database"))
  end

  # According to https://www.geopackage.org/spec/#r13
  # A GeoPackage SHALL include a 'gpkg_contents' table
  if isnothing(SQLite.tableinfo(db, "gpkg_contents"))
    throw(ErrorException("missing required metadata tables in the GeoPackage SQL database"))
  end

  db
end

function gpkgextract(db; layer=1)
  # get the feature table given the layer number
  layerinfo = DBInterface.execute(
    db,
    """
    SELECT g.table_name AS tablename, g.column_name AS geomcolumn, g.z,
    c.srs_id AS srsid, srs.organization AS org, srs.organization_coordsys_id AS code
    FROM gpkg_geometry_columns g, gpkg_spatial_ref_sys srs
    """ *
    # According to https://www.geopackage.org/spec/#r24
    # The column_name column value in a gpkg_geometry_columns row
    # SHALL be the name of a column in the table or view specified
    # by the table_name column value for that row.
    """
    JOIN gpkg_contents c ON ( g.table_name = c.table_name )
    """ *
    # According to https://www.geopackage.org/spec/#r23
    # gpkg_geometry_columns table_name column SHALL reference values
    # in the gpkg_contents table_name column for rows with a data_type
    # of 'features'
    """
    WHERE c.data_type = 'features'
    """ *
    # According to https://www.geopackage.org/spec/#r146
    # The srs_id value in a gpkg_geometry_columns table row SHALL
    # match the srs_id column value from the corresponding row in
    # the gpkg_contents table.
    """
    AND g.srs_id = c.srs_id
    LIMIT 1 OFFSET ($layer-1);
    """
  )

  isnothing(layerinfo) && throw(ErrorException("layer $layer not found in GeoPackage"))
  metadata = first(layerinfo)

  # org is a case-insensitive name of the defining organization e.g. EPSG or epsg
  org = uppercase(metadata.org)
  # code is a numeric ID of the spatial reference system assigned by the organization
  code = metadata.code
  # According to https://www.geopackage.org/spec/#r33
  # Feature table geometry columns SHALL contain geometries
  # with the srs_id specified for the column by the
  # gpkg_geometry_columns table srs_id column value.
  srsid = metadata.srsid

  # According to https://www.geopackage.org/spec/#r27
  # The z value in a gpkg_geometry_columns table row SHALL be one of 0, 1, or 2
  # 0: z values prohibited; 1: z values mandatory; 2: z values optional
  z = isone(metadata.z)
  crs = if srsid == 0 || srsid == 99999
    # An srs_id of 0 SHALL be used for undefined geographic coordinate reference systems
    # An srs_id of 99999 is recognized as a placeholder code, we will default to undefined geographic crs
    z ? LatLonAlt{WGS84Latest} : LatLon{WGS84Latest}
  elseif srsid == -1
    # An srs_id of -1 SHALL be used for undefined Cartesian coordinate reference systems
    z ? Cartesian3D{NoDatum} : Cartesian2D{NoDatum}
  elseif code in (0, -1)
    # typically srs_id and code values are the same, however if code is undefined (0,-1)
    # and if srs_id is defined then default to getting a CRS type given srs_id instead of code
    CoordRefSystems.get(EPSG{srsid})
  elseif org == "EPSG"
    CoordRefSystems.get(EPSG{code})
  elseif org == "ESRI"
    CoordRefSystems.get(ESRI{code})
  else
    error("Unsupported CRS specification (org: $org, code: $code, srsid: $srsid)")
  end

  # According to https://www.geopackage.org/spec/#r14
  # The table_name column value in a gpkg_contents table row 
  # SHALL contain the name of a SQLite table or view.
  tablename = metadata.tablename

  # According to https://www.geopackage.org/spec/#r30
  # A feature table or view SHALL have only one geometry column.
  geomcolumn = metadata.geomcolumn |> Symbol

  # Retrieve names of columns with attributes (i.e., ≠ geometry)
  # pk is the index of the column within the primary key,
  # or 0 for columns that are not part of the primary key
  tabinfo = SQLite.tableinfo(db, tablename)
  columns = [Symbol(name) for (name, pk) in zip(tabinfo.name, tabinfo.pk) if pk == 0]
  attribs = setdiff(columns, [geomcolumn])

  # load feature table from database
  gpkgtable = DBInterface.execute(db, "SELECT $(join(columns, ',')) FROM \"$tablename\";")

  # extract rows with Meshes.jl geometries
  map(Tables.rows(gpkgtable)) do row
    # retrieve attribute values
    vals = (; (col => Tables.getcolumn(row, col) for col in attribs)...)

    # retrieve geometry bytes
    geombytes = Tables.getcolumn(row, geomcolumn)

    # convert bytes to geometry or missing value
    geom = if ismissing(geombytes)
      missing
    else
      # wrap bytes into IO buffer
      buff = IOBuffer(geombytes)

      # skip GPKG binary header bytes
      skipgpkgheader!(buff)

      # convert WKB geometry into Meshes.jl geometry
      wkb2meshes(buff, crs)
    end

    # return row as named tuple with geometry
    (; vals..., geometry=geom)
  end
end

# According to https://www.geopackage.org/spec/#r19
# A GeoPackage SHALL store feature table geometries in
# SQL BLOBs using the Standard GeoPackageBinary format
function skipgpkgheader!(buff)
  # check the GeoPackageBinaryHeader for the 'GP' magic
  read(buff, UInt16) == 0x5047 || @warn "Missing magic 'GP' string in GPkgBinaryGeometry"

  # skip version (0 => version 1)
  skip(buff, 1)

  # bit layout of GeoPackageBinary flag byte
  # https://www.geopackage.org/spec/#flags_layout
  # ---------------------------------------
  # bit # 7 # 6 # 5 # 4 # 3 # 2 # 1 # 0 #
  # use # R # R # X # Y # E # E # E # B #
  # ---------------------------------------
  # R: reserved for future use; set to 0
  # X: GeoPackageBinary type
  # Y: empty geometry flag
  # E: envelope contents indicator code (3-bit unsigned integer)
  # B: byte order for SRS_ID and envelope values in header
  E = (read(buff, UInt8) & 0b00001110) >> 1

  # skip srs id
  skip(buff, 4)

  # skip calculated envelope size given envelope code E
  # Float64[no envelope]                        => skip 0 bytes
  # Float64[minx, maxx, miny, maxy]             => skip 32 bytes
  # Float64[minx, maxx, miny, maxy, minz, maxz] => skip 48 bytes
  E > 0 && skip(buff, 8 * 2 * (E + 1))
end

# ------------------------------------------------------------------
# GeoPackage Writer: saves GeoTable to GeoPackage SQLite database
# ------------------------------------------------------------------

function gpkgwrite(fname, geotable; layername="data", kwargs...)
  geoms = domain(geotable)
  table = values(geotable)
  CRS = crs(geoms)

  # SRS info
  srsid, org, orgcode, srsname, wktdef = _gpkgsrsinfo(CRS)

  # Z dimension flag: 0=prohibited, 1=mandatory
  z = CoordRefSystems.ncoords(CRS) ≥ 3 ? 1 : 0

  # geometry type name from first geometry
  geomtype = _gpkggeomtype(geoms[1])

  # remove existing file
  isfile(fname) && rm(fname)

  # create database
  db = SQLite.DB(fname)

  try
    # set GPKG application ID (0x47504B47 = 'GPKG') and version 1.3.1
    DBInterface.execute(db, "PRAGMA application_id = 1196444487;")
    DBInterface.execute(db, "PRAGMA user_version = 10301;")

    # create required metadata tables
    _gpkgcreatemeta!(db)

    # insert default SRS entries required by spec
    _gpkgdefaultsrs!(db)

    # insert actual CRS if not a default one
    if srsid ∉ (0, -1)
      DBInterface.execute(
        db,
        "INSERT OR IGNORE INTO gpkg_spatial_ref_sys (srs_name, srs_id, organization, organization_coordsys_id, definition) VALUES (?, ?, ?, ?, ?);",
        (srsname, srsid, org, orgcode, wktdef)
      )
    end

    # create feature table
    _gpkgcreatefeaturetable!(db, layername, table)

    # insert contents metadata
    DBInterface.execute(
      db,
      "INSERT INTO gpkg_contents (table_name, data_type, identifier, srs_id) VALUES (?, 'features', ?, ?);",
      (layername, layername, srsid)
    )

    # insert geometry column metadata
    DBInterface.execute(
      db,
      "INSERT INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m) VALUES (?, 'geom', ?, ?, ?, 0);",
      (layername, geomtype, srsid, z)
    )

    # insert features
    _gpkginsertfeatures!(db, layername, geoms, table, srsid)
  finally
    DBInterface.close!(db)
  end

  fname
end

# create required GeoPackage metadata tables
function _gpkgcreatemeta!(db)
  DBInterface.execute(db, """
    CREATE TABLE gpkg_spatial_ref_sys (
      srs_name TEXT NOT NULL,
      srs_id INTEGER NOT NULL PRIMARY KEY,
      organization TEXT NOT NULL,
      organization_coordsys_id INTEGER NOT NULL,
      definition TEXT NOT NULL,
      description TEXT
    );
  """)

  DBInterface.execute(db, """
    CREATE TABLE gpkg_contents (
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
      CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
    );
  """)

  DBInterface.execute(db, """
    CREATE TABLE gpkg_geometry_columns (
      table_name TEXT NOT NULL,
      column_name TEXT NOT NULL,
      geometry_type_name TEXT NOT NULL,
      srs_id INTEGER NOT NULL,
      z TINYINT NOT NULL,
      m TINYINT NOT NULL,
      CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
      CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
      CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
    );
  """)
end

# insert default SRS entries required by the GeoPackage spec
function _gpkgdefaultsrs!(db)
  DBInterface.execute(db, """
    INSERT INTO gpkg_spatial_ref_sys (srs_name, srs_id, organization, organization_coordsys_id, definition) VALUES
    ('Undefined geographic SRS', 0, 'NONE', 0, 'undefined'),
    ('Undefined cartesian SRS', -1, 'NONE', -1, 'undefined');
  """)
end

# create the feature table with geometry and attribute columns
function _gpkgcreatefeaturetable!(db, layername, table)
  colsql = ["fid INTEGER PRIMARY KEY AUTOINCREMENT", "geom BLOB"]
  if !isnothing(table)
    schema = Tables.schema(table)
    for (name, type) in zip(schema.names, schema.types)
      push!(colsql, "\"$(name)\" $(_gpkgsqltype(type))")
    end
  end
  DBInterface.execute(db, "CREATE TABLE \"$layername\" ($(join(colsql, ", ")));")
end

# insert all features into the feature table
function _gpkginsertfeatures!(db, layername, geoms, table, srsid)
  ngeom = nelements(geoms)

  if isnothing(table)
    DBInterface.execute(db, "BEGIN TRANSACTION;")
    for i in 1:ngeom
      blob = _gpkgbinary(geoms[i], srsid)
      DBInterface.execute(db, "INSERT INTO \"$layername\" (geom) VALUES (?);", (blob,))
    end
    DBInterface.execute(db, "COMMIT;")
  else
    schema = Tables.schema(table)
    cols = Tables.columns(table)
    colnames = join(["geom"; ["\"$(n)\"" for n in schema.names]], ", ")
    ncols = length(schema.names) + 1
    placeholders = join(fill("?", ncols), ", ")
    sql = "INSERT INTO \"$layername\" ($colnames) VALUES ($placeholders);"

    DBInterface.execute(db, "BEGIN TRANSACTION;")
    for i in 1:ngeom
      blob = _gpkgbinary(geoms[i], srsid)
      vals = Any[blob]
      for name in schema.names
        push!(vals, Tables.getcolumn(cols, name)[i])
      end
      DBInterface.execute(db, sql, vals)
    end
    DBInterface.execute(db, "COMMIT;")
  end
end

# create GPKG binary blob (header + WKB) for a geometry
function _gpkgbinary(geom, srsid)
  buff = IOBuffer()
  # GeoPackageBinary header
  write(buff, UInt8(0x47)) # 'G'
  write(buff, UInt8(0x50)) # 'P'
  write(buff, UInt8(0))    # version 1
  write(buff, UInt8(0x01)) # flags: little endian, no envelope, non-empty, standard
  write(buff, htol(Int32(srsid)))
  # WKB geometry
  meshes2wkb!(buff, geom)
  take!(buff)
end

# extract SRS info from CRS type
function _gpkgsrsinfo(CRS)
  try
    code = CoordRefSystems.code(CRS)
    id, org = _gpkgsrsidorg(code)
    wktdef = CoordRefSystems.wkt2(code)
    srsname = "$org:$id"
    (id, org, id, srsname, wktdef)
  catch
    if CRS <: LatLon || CRS <: LatLonAlt
      (0, "NONE", 0, "Undefined geographic SRS", "undefined")
    else
      (-1, "NONE", -1, "Undefined cartesian SRS", "undefined")
    end
  end
end

_gpkgsrsidorg(::Type{EPSG{Code}}) where {Code} = (Code, "EPSG")
_gpkgsrsidorg(::Type{ESRI{Code}}) where {Code} = (Code, "ESRI")

# determine WKB geometry type name for gpkg_geometry_columns
function _gpkggeomtype(geom)
  if geom isa Point
    "POINT"
  elseif geom isa Chain
    "LINESTRING"
  elseif geom isa Polygon
    "POLYGON"
  elseif geom isa Multi
    g1 = first(parent(geom))
    if g1 isa Point
      "MULTIPOINT"
    elseif g1 isa Chain
      "MULTILINESTRING"
    elseif g1 isa Polygon
      "MULTIPOLYGON"
    else
      "GEOMETRY"
    end
  else
    "GEOMETRY"
  end
end

# map Julia types to SQLite column types
function _gpkgsqltype(T)
  T = nonmissingtype(T)
  if T <: Bool
    "INTEGER"
  elseif T <: Integer
    "INTEGER"
  elseif T <: AbstractFloat
    "REAL"
  elseif T <: AbstractString
    "TEXT"
  else
    "TEXT"
  end
end
