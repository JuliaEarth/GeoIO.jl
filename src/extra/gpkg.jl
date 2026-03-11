# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# -------
# READING
# -------

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
    SELECT g.z,
      g.table_name AS tablename,
      g.column_name AS geomcolumn,
      c.srs_id AS srsid,
      srs.organization AS org,
      srs.organization_coordsys_id AS code
    FROM gpkg_geometry_columns g
    JOIN gpkg_spatial_ref_sys srs ON g.srs_id = srs.srs_id
    """ *
    # According to https://www.geopackage.org/spec/#r24
    # The column_name column value in a gpkg_geometry_columns row
    # SHALL be the name of a column in the table or view specified
    # by the table_name column value for that row.
    """
    JOIN gpkg_contents c ON (g.table_name = c.table_name)
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
    LIMIT 1 OFFSET ($layer-1)
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
  CRS = gpkgcrs(metadata.z != 0, srsid; org=org, code=code)

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
      wkb2meshes(buff, CRS)
    end

    # return row as named tuple with geometry
    (; vals..., geometry=geom)
  end
end

# Determine the Julia CRS type from GeoPackage metadata
function gpkgcrs(is3D, srsid; org="NONE", code=0)
  if srsid == 0 || srsid == 99999
    # An srs_id of 0 SHALL be used for undefined geographic coordinate reference systems
    # An srs_id of 99999 is recognized as a placeholder code, we will default to undefined geographic crs
    is3D ? LatLonAlt{WGS84Latest} : LatLon{WGS84Latest}
  elseif srsid == -1
    # An srs_id of -1 SHALL be used for undefined Cartesian coordinate reference systems
    is3D ? Cartesian3D{NoDatum} : Cartesian2D{NoDatum}
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

# -------
# WRITING
# -------

function gpkgwrite(fname, geotable)
  # remove file if it already exists
  isfile(fname) && rm(fname)

  # initialize SQLite database
  db = SQLite.DB(fname)

  # setting synchronous to OFF is a good option when creating a new database from scratch
  # see SQLite documentation https://sqlite.org/pragma.html#pragma_synchronous
  DBInterface.execute(db, "PRAGMA synchronous = OFF")

  # According to https://www.geopackage.org/spec/#r2
  # A GeoPackage SHALL contain a value of 0x47504B47 ("GPKG" in ASCII)
  # in the "application_id" field of the SQLite database header to indicate
  # that it is a GeoPackage. An appropriate user_version SHALL also be set.
  DBInterface.execute(db, "PRAGMA application_id = 0x47504B47")
  DBInterface.execute(db, "PRAGMA user_version = 10400")

  # write all GeoPackage tables to the database in a single transaction
  writegpkgtables!(db, geotable)

  # Applications with short-lived database connections should
  # run "PRAGMA optimize;" just once, prior to closing each database connection.
  # See SQLite documentation https://sqlite.org/pragma.html#pragma_optimize
  DBInterface.execute(db, "PRAGMA optimize")

  DBInterface.close!(db)
end

function writegpkgtables!(db, geotable)
  SQLite.transaction(db) do
    # required metadata tables: spatial reference system, contents, and geometry columns
    writegpkgspatialrefsys!(db, geotable)
    writegpkgcontents!(db, geotable)
    writegpkggeomcolumns!(db, geotable)

    # create and populate the vector feature user data table
    writegpkgfeaturetable!(db, geotable)
  end
end

function writegpkgspatialrefsys!(db, geotable)
  CRS = crs(domain(geotable))
  srsid = gpkgsrsid(CRS)

  # According to https://www.geopackage.org/spec/#r10
  # A GeoPackage SHALL include a gpkg_spatial_ref_sys table
  DBInterface.execute(
    db,
    """
    CREATE TABLE gpkg_spatial_ref_sys (
      srs_id                   INTEGER NOT NULL PRIMARY KEY,
      srs_name                 TEXT    NOT NULL,
      organization             TEXT    NOT NULL,
      organization_coordsys_id INTEGER NOT NULL,
      definition               TEXT    NOT NULL,
      description              TEXT
    )
    """
  )

  # According to https://www.geopackage.org/spec/#r11
  # The gpkg_spatial_ref_sys table SHALL contain at a minimum:
  # 1. a record with an srs_id of 4326 corresponding to WGS-84 as defined by EPSG
  # 2. a record with an srs_id of -1 for undefined Cartesian coordinate reference systems
  # 3. a record with an srs_id of 0 for undefined geographic coordinate reference systems
  DBInterface.execute(
    db,
    """
    INSERT OR REPLACE INTO gpkg_spatial_ref_sys
      (srs_name, srs_id, organization, organization_coordsys_id, definition, description)
    VALUES
      ('Undefined Cartesian SRS', -1, 'NONE', -1, 'undefined', 'undefined Cartesian coordinate reference system'),
      ('Undefined geographic SRS', 0, 'NONE', 0, 'undefined', 'undefined geographic coordinate reference system'),
      ('WGS 84 geodetic', 4326, 'EPSG', 4326,
       'GEOGCRS["WGS 84",DATUM["World Geodetic System 1984",ELLIPSOID["WGS 84",6378137,298.257223563,LENGTHUNIT["metre",1]]],PRIMEM["Greenwich",0,ANGLEUNIT["degree",0.0174532925199433]],CS[ellipsoidal,2],AXIS["geodetic latitude (Lat)",north,ORDER[1],ANGLEUNIT["degree",0.0174532925199433]],AXIS["geodetic longitude (Lon)",east,ORDER[2],ANGLEUNIT["degree",0.0174532925199433]],ID["EPSG",4326]]',
       'longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid')
    """
  )

  # insert the CRS record for this dataset if it is not one of the mandatory ones
  if srsid != 4326 && srsid != 0 && srsid != -1
    org, srsid_, srswkt = gpkgspatialrefsys(CRS)
    # According to https://www.geopackage.org/spec/#r115
    # This conforms to the Well-Known Text for Coordinate Reference Systems extension
    DBInterface.execute(
      db,
      """
      INSERT OR REPLACE INTO gpkg_spatial_ref_sys
        (srs_name, srs_id, organization, organization_coordsys_id, definition, description)
      VALUES ('', ?, ?, ?, ?, '')
      """,
      (srsid_, org, srsid_, srswkt),
    )
  end
end

function writegpkgcontents!(db, geotable)
  dom = domain(geotable)
  extent = Float64.(gpkgextent(dom))
  srsid = gpkgsrsid(crs(dom))

  # According to https://www.geopackage.org/spec/#r13
  # A GeoPackage SHALL include a gpkg_contents table
  DBInterface.execute(
    db,
    """
    CREATE TABLE gpkg_contents (
      table_name  TEXT     NOT NULL PRIMARY KEY,
      data_type   TEXT     NOT NULL,
      identifier  TEXT     NOT NULL UNIQUE,
      description TEXT              DEFAULT '',
      last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
      min_x       DOUBLE,
      min_y       DOUBLE,
      max_x       DOUBLE,
      max_y       DOUBLE,
      srs_id      INTEGER,
        CONSTRAINT fk_gc_r_srs_id
        FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
    )
    """
  )

  DBInterface.execute(
    db,
    """
    INSERT OR REPLACE INTO gpkg_contents
      (table_name, data_type, identifier, min_x, min_y, max_x, max_y, srs_id)
    VALUES ('features', 'features', 'features', $(extent[1]), $(extent[3]), $(extent[2]), $(extent[4]), $srsid)
    """
  )
end

function writegpkggeomcolumns!(db, geotable)
  dom = domain(geotable)
  CRS = crs(dom)
  gtype = sqlgeomtype(dom)
  srsid = gpkgsrsid(CRS)
  z = CoordRefSystems.ncoords(CRS) == 3 ? 1 : 0

  # According to https://www.geopackage.org/spec/#r21
  # A GeoPackage with a gpkg_contents table row with a
  # "features" data_type SHALL contain a gpkg_geometry_columns table
  DBInterface.execute(
    db,
    """
    CREATE TABLE gpkg_geometry_columns (
      table_name         TEXT    NOT NULL,
      column_name        TEXT    NOT NULL,
      geometry_type_name TEXT    NOT NULL,
      srs_id             INTEGER NOT NULL,
      z                  TINYINT NOT NULL,
      m                  TINYINT NOT NULL,
        CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
        CONSTRAINT uk_gc_table_name UNIQUE (table_name),
        CONSTRAINT fk_gc_tn  FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
        CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id)     REFERENCES gpkg_spatial_ref_sys(srs_id)
    )
    """
  )

  DBInterface.execute(
    db,
    """
    INSERT OR REPLACE INTO gpkg_geometry_columns
      (table_name, column_name, geometry_type_name, srs_id, z, m)
    VALUES ('features', 'geometry', '$gtype', $srsid, $z, 0)
    """
  )
end

function writegpkgfeaturetable!(db, geotable)
  dom = domain(geotable)
  CRS = crs(dom)
  is3D = CoordRefSystems.ncoords(CRS) == 3

  sch = Tables.schema(geotable)
  coldefs = map(zip(sch.names, sch.types)) do (name, type)
    if name == :geometry
      "geometry $(sqlgeomtype(dom))"
    else
      "$(SQLite.esc_id(string(name))) $(SQLite.sqlitetype(type))"
    end
  end

  # See sample feature table definition here https://www.geopackage.org/spec/#example_feature_table_sql
  # This implementation omits the AUTOINCREMENT keyword in the feature table definition
  # (primary key identifiers may be reused; see https://www.geopackage.org/spec/#K6a)
  DBInterface.execute(db, "CREATE TABLE features ($(join(coldefs, ',')))")

  # According to https://www.geopackage.org/spec/#r77
  # Extended GeoPackage requires spatial indexes on feature table geometry columns
  # using SQLite Virtual Table R-trees
  # creates a spatial index using rtree_<t>_<c>
  # where <t> and <c> are replaced with the names of the feature table and geometry column being indexed.
  DBInterface.execute(
    db,
    "CREATE VIRTUAL TABLE rtree_features_geometry USING rtree(id, minx, maxx, miny, maxy)"
  )

  # prepared SQL statement for batch inserts
  vars = join(SQLite.esc_id.(string.(sch.names)), ",")
  vals = join(repeat(["?"], length(sch.names)), ",")
  stmt = SQLite.Stmt(db, "INSERT OR REPLACE INTO features ($vars) VALUES ($vals)")

  # write rows of geotable to database
  for row in Tables.rows(geotable)
    extent = nothing
    params = map(Tables.columnnames(row)) do col
      val = Tables.getcolumn(row, col)
      if val isa Geometry
        # The R-tree stores min/max x/y as 32-bit floats; use Float64 for the gpkg binary header
        extent = Float32.(gpkgextent(val))
        # convert Meshes.Geometry to GeoPackageBinary SQL Geometry BLOB
        meshes2gpkgbinary(CRS, val, Float64.(extent), is3D)
      else
        val
      end
    end
    DBInterface.execute(stmt, params)

    # The R-tree Spatial Indexes extension data structure needs to be manually populated.
    # This implementation does not define triggers to maintain the R-tree spatial indexes.
    fid = SQLite.last_insert_rowid(db)
    if !isnothing(extent)
      DBInterface.execute(
        db,
        "INSERT OR REPLACE INTO rtree_features_geometry VALUES (?, ?, ?, ?, ?)",
        (fid, extent[1], extent[2], extent[3], extent[4]),
      )
    end
  end

  # https://www.geopackage.org/spec/#r75
  # Register the rtree index extension in gpkg_extensions
  creategpkgextensions!(db)
end

function creategpkgextensions!(db)
  DBInterface.execute(
    db,
    """
    CREATE TABLE gpkg_extensions (
      table_name     TEXT,
      column_name    TEXT,
      extension_name TEXT NOT NULL,
      definition     TEXT NOT NULL,
      scope          TEXT NOT NULL,
        CONSTRAINT ge_tce UNIQUE (table_name, column_name, extension_name)
    )
    """
  )
  DBInterface.execute(
    db,
    """
    INSERT OR REPLACE INTO gpkg_extensions
      (table_name, column_name, extension_name, definition, scope)
    VALUES ('features', 'geometry', 'gpkg_rtree_index',
            'http://www.geopackage.org/spec120/#extension_rtree', 'write-only')
    """
  )
end

# Convert a Meshes.jl geometry to GeoPackageBinary BLOB bytes
function meshes2gpkgbinary(CRS, geom, extent, is3D)
  buff = IOBuffer()
  gpkgbinaryheader!(buff, CRS, extent, is3D)
  meshes2wkb!(buff, geom, is3D)
  take!(buff)
end

function gpkgbinaryheader!(buff, CRS, extent, is3D)
  # Magic number 'GP' in ASCII (0x47, 0x50)
  write(buff, [0x47, 0x50])

  # version: 8-bit unsigned integer, 0 = version 1
  write(buff, zero(UInt8))

  if is3D
    # bit layout of GeoPackageBinary flags byte:
    # envelope indicator E=3 ([minx,maxx,miny,maxy,minz,maxz]) + Little Endian byte order
    write(buff, 0b00000101)
  else
    # envelope indicator E=1 ([minx,maxx,miny,maxy]) + Little Endian byte order
    write(buff, 0b00000011)
  end

  # SRS ID in Little Endian byte order
  write(buff, htol(gpkgsrsid(CRS)))

  # envelope: [minx, maxx, miny, maxy]
  write(buff, htol(extent[1]))
  write(buff, htol(extent[2]))
  write(buff, htol(extent[3]))
  write(buff, htol(extent[4]))

  if is3D
    # extended envelope: [..., minz, maxz]
    write(buff, htol(extent[5]))
    write(buff, htol(extent[6]))
  end
end

# Compute the spatial extent of a domain or geometry for the GeoPackage envelope
function gpkgextent(obj)
  bbox = boundingbox(obj)
  cmin = coords(minimum(bbox))
  cmax = coords(maximum(bbox))
  exts = gpkgextent(cmin, cmax)
  ustrip.(exts)
end

gpkgextent(cmin::LatLon, cmax::LatLon) = (cmin.lon, cmax.lon, cmin.lat, cmax.lat)
gpkgextent(cmin::LatLonAlt, cmax::LatLonAlt) = (cmin.lon, cmax.lon, cmin.lat, cmax.lat, cmin.alt, cmax.alt)
gpkgextent(cmin::CoordRefSystems.Projected, cmax::CoordRefSystems.Projected) = (cmin.x, cmax.x, cmin.y, cmax.y)
gpkgextent(cmin::Cartesian2D, cmax::Cartesian2D) = (cmin.x, cmax.x, cmin.y, cmax.y)
gpkgextent(cmin::Cartesian3D, cmax::Cartesian3D) = (cmin.x, cmax.x, cmin.y, cmax.y, cmin.z, cmax.z)

# Returns (organization, srs_id, wkt_definition) for a CRS type
function gpkgspatialrefsys(CRS::Type{<:CoordRefSystems.CRS})
  srsid = gpkgsrsid(CRS)
  wkt = try
    CoordRefSystems.wkt2(CRS)
  catch
    "undefined"
  end
  "EPSG", srsid, wkt
end

gpkgspatialrefsys(::Type{<:Cartesian}) = ("NONE", Int32(-1), "undefined")

# Map CRS type to EPSG integer code (srs_id in GeoPackage)
function gpkgsrsid(CRS::Type)
  if CRS <: Cartesian
    Int32(-1)
  elseif CRS <: LatLon || CRS <: LatLonAlt
    # WGS84 geographic CRS
    Int32(4326)
  else
    try
      Int32(CoordRefSystems.integer(CoordRefSystems.code(CRS)))
    catch
      Int32(0)
    end
  end
end

# Infer SQL geometry type name from domain element type
sqlgeomtype(dom::Domain) = sqlgeomtype(eltype(dom))
sqlgeomtype(::Type{<:Point}) = "POINT"
sqlgeomtype(::Type{<:Chain}) = "LINESTRING"
sqlgeomtype(::Type{<:Polygon}) = "POLYGON"
sqlgeomtype(::Type{<:MultiPoint}) = "MULTIPOINT"
sqlgeomtype(::Type{<:MultiChain}) = "MULTILINESTRING"
sqlgeomtype(::Type{<:MultiPolygon}) = "MULTIPOLYGON"
sqlgeomtype(::Type{<:Multi}) = "GEOMETRYCOLLECTION"
sqlgeomtype(::Type{<:Geometry}) = "GEOMETRY"
