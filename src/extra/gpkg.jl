# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gpkgtable(fname; layer, warn)
  db = gpkgdatabase(fname)
  if warn
    result = DBInterface.execute(db, "SELECT COUNT(*) AS count FROM gpkg_geometry_columns")
    nlayers = Int(first(result).count)
    if nlayers > 1
      @warn """
      File has $nlayers layers. Use `layer=i` for any `i` in the range `1:$nlayers`
      to load a specific layer. You can disable this warning by setting `warn=false`.
      """
    end
  end
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
    """ *
    # According to https://www.geopackage.org/spec/#r24
    # The column_name column value in a gpkg_geometry_columns row
    # SHALL be the name of a column in the table or view specified
    # by the table_name column value for that row.
    """
    JOIN gpkg_contents c ON (g.table_name = c.table_name)
    """ *
    # According to https://www.geopackage.org/spec/#r16
    # Values of the gpkg_contents table srs_id column
    # SHALL reference values in the gpkg_spatial_ref_sys table srs_id column.
    """
    JOIN gpkg_spatial_ref_sys srs ON c.srs_id = srs.srs_id
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
  CRS = gpkgcrs(!iszero(metadata.z), srsid; org=org, code=code)

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

function gpkgwrite(fname, geotable)
  # remove file if necessary
  isfile(fname) && rm(fname)

  # initialize database
  db = SQLite.DB(fname)

  # setting synchronous to OFF is a good option when creating a new database from scratch
  # see SQLite documentation https://sqlite.org/pragma.html#pragma_synchronous
  DBInterface.execute(db, "PRAGMA synchronous = OFF")

  # According to https://www.geopackage.org/spec/#r2
  # A GeoPackage SHALL contain a value of 0x47504B47 ("GPKG" in ASCII)
  # in the "application_id" field and an appropriate value in "user_version"
  # field of the SQLite db header to indicate that it is a GeoPackage
  DBInterface.execute(db, "PRAGMA application_id = 0x47504B47")
  DBInterface.execute(db, "PRAGMA user_version = 10400")

  # write GPKG tables to database
  writegpkgtables!(db, geotable)

  # Applications with short-lived database connections should
  # run "PRAGMA optimize;" just once, prior to closing each database connection.
  # See SQLite documentation https://sqlite.org/pragma.html#pragma_optimize
  DBInterface.execute(db, "PRAGMA optimize")

  DBInterface.close!(db)
end

function writegpkgtables!(db, geotable)
  DBInterface.transaction(db) do
    # required metadata tables and metadata table
    # that identifies geometry columns and types
    writegpkgspatialrefsys!(db, geotable)
    writegpkgcontents!(db, geotable)
    writegpkggeomcolumns!(db, geotable)

    # create and insert vector feature user data tables
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
  # The gpkg_spatial_ref_sys table SHALL contain at a minimum
  # 1. the record with an srs_id of 4326 SHALL correspond to WGS-84 as defined by EPSG in 4326
  # 2. the record with an srs_id of -1 SHALL be used for undefined Cartesian coordinate reference systems
  # 3. the record with an srs_id of 0 SHALL be used for undefined geographic coordinate reference systems
  DBInterface.execute(
    db,
    """
    INSERT OR REPLACE INTO gpkg_spatial_ref_sys
      (srs_name, srs_id, organization, organization_coordsys_id, definition, description)
    VALUES ('Undefined Cartesian SRS', -1, 'NONE', -1, 'undefined', 'undefined Cartesian coordinate reference systems'),
      ('Undefined geographic SRS', 0, 'NONE', 0, 'undefined', 'undefined geographic coordinate reference system'),
      ('WGS 84 geodetic', 4326, 'EPSG', 4326, 'GEOGCRS["WGS 84",DATUM["World Geodetic System 1984",ELLIPSOID["WGS 84",6378137,298.257223563,LENGTHUNIT["metre",1]]],PRIMEM["Greenwich",0,ANGLEUNIT["degree",0.0174532925199433]],CS[ellipsoidal,2],AXIS["geodetic latitude (Lat)",north,ORDER[1],ANGLEUNIT["degree",0.0174532925199433]],AXIS["geodetic longitude (Lon)",east,ORDER[2],ANGLEUNIT["degree",0.0174532925199433]],ID["EPSG",4326]]', 'longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid')
    """
  )

  # insert non-existing CRS record into gpkg_spatial_ref_sys table.
  if srsid != 4326 && srsid > 0
    org, srsid, srswkt = gpkgspatialrefsys(CRS)
    # According to https://www.geopackage.org/spec/#r115
    # This conforms to the Well-Known Text for Coordinate Reference Systems extension
    # this implementation of gpkg_spatial_ref_sys table does not contain the additional column definition_12_063
    DBInterface.execute(
      db,
      """
      INSERT OR REPLACE INTO gpkg_spatial_ref_sys
        (srs_name, srs_id, organization, organization_coordsys_id, definition, description)
      VALUES ('', ?, ?, ?, ?, '')
      """,
      (srsid, org, srsid, srswkt)
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
    VALUES ('features', 'features', 'features', ?, ?, ?, ?, ?)
    """,
    (extent[1], extent[3], extent[2], extent[4], srsid)
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
  # "features" data_type SHALL contain a gpkg_geometry_columns
  DBInterface.execute(
    db,
    """
    CREATE TABLE gpkg_geometry_columns (
      table_name         TEXT NOT NULL,
      column_name        TEXT NOT NULL,
      geometry_type_name TEXT NOT NULL,
      srs_id             INTEGER NOT NULL,
      z                  TINYINT NOT NULL,
      m                  TINYINT NOT NULL,
        CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
        CONSTRAINT uk_gc_table_name UNIQUE (table_name),
        CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
        CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys (srs_id)
    )
    """
  )
  DBInterface.execute(
    db,
    """
    INSERT OR REPLACE INTO gpkg_geometry_columns
      (table_name, column_name, geometry_type_name, srs_id, z, m)
    VALUES ('features', 'geometry', ?, ?, ?, 0)
    """,
    (gtype, srsid, z)
  )
end

function writegpkgfeaturetable!(db, geotable)
  dom = domain(geotable)
  CRS = crs(dom)

  sch = Tables.schema(geotable)
  coldefs = map(zip(sch.names, sch.types)) do (name, type)
    if name == :geometry
      "geometry $(sqlgeomtype(dom))"
    else
      "$(SQLite.esc_id(string(name))) $(SQLite.sqlitetype(type))"
    end
  end

  # See example feature table definition SQL https://www.geopackage.org/spec/#example_feature_table_sql
  # According to https://www.geopackage.org/spec/#r29
  # A feature table SHALL have a primary key column of type INTEGER
  # and that column SHALL act as a rowid alias
  DBInterface.execute(db, "CREATE TABLE features (fid INTEGER PRIMARY KEY NOT NULL, $(join(coldefs, ',')))")

  # According to https://www.geopackage.org/spec/#r77
  # Extended GeoPackage requires spatial indexes on feature table geometry columns
  # using the SQLite Virtual Table R-trees
  DBInterface.execute(
    db,
    # creates a spatial index using rtree_<t>_<c>
    # where <t> and <c> are replaced with the names of the feature table and geometry column being indexed.
    "CREATE VIRTUAL TABLE rtree_features_geometry USING rtree(id, minx, maxx, miny, maxy)"
  )

  # prepared SQL statement and handle
  vars = join(SQLite.esc_id.(string.(sch.names)), ",")
  vals = join(repeat("?", length(sch.names)), ",")
  stmt = SQLite.Stmt(db, "INSERT OR REPLACE INTO features ($vars) VALUES ($vals)")
  # write rows of geotable to database
  for row in Tables.rows(geotable)
    # bind the values of the current row to the prepared SQL statement
    params = map(Tables.columnnames(row)) do col
      val = Tables.getcolumn(row, col)
      if val isa Geometry
        # convert Meshes.Geometry to GeoPackageBinary SQL Geometry BLOB
        meshes2gpkgbinary(CRS, val, Float64.(gpkgextent(val)))
      else
        val
      end
    end
    DBInterface.execute(stmt, params)

    # The R-tree Spatial Indexes extension provides a means to encode an R-tree index for geometry values
    # This implementation does not define triggers to maintain the R-tree spatial indexes
    # all rows within SQLite tables have a 64-bit signed integer key that uniquely identifies the row within its table
    # The R-tree function id parameter is the virtual table 64-bit signed integer primary key id column
    fid = SQLite.last_insert_rowid(db)
    # The R-tree min/max x/y parameters are min- and max-value pairs (stored as 32-bit floating point numbers)
    extent = Float32.(gpkgextent(row.geometry))
    # The index data structure needs to be manually populated
    DBInterface.execute(
      db,
      "INSERT OR REPLACE INTO rtree_features_geometry VALUES (?, ?, ?, ?, ?)",
      (fid, extent[1], extent[2], extent[3], extent[4])
    )
  end

  # https://www.geopackage.org/spec/#r75
  # The "gpkg_rtree_index" extension name uses a gpkg_extensions table extension_name
  # column value to specify implementation of spatial indexes on a geometry column
  creategpkgextensions(db)
end

function creategpkgextensions(db)
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
    VALUES ('features', 'geometry', 'gpkg_rtree_index', 'http://www.geopackage.org/spec120/#extension_rtree', 'write-only')
    """
  )
end

function meshes2gpkgbinary(crs, geom, extent)
  # store feature geometry in SQL BLOB specified by GeoPackageBinary format
  buff = IOBuffer()
  gpkgbinaryheader!(buff, crs, extent)
  meshes2wkb!(buff, geom)
  take!(buff)
end

function gpkgbinaryheader!(buff, crs, extent)
  # 'GP' in ASCII
  write(buff, [0x47, 0x50])

  # 8-bit unsigned integer, 0 = version 1
  write(buff, zero(UInt8))

  if CoordRefSystems.ncoords(crs) == 3
    # bit layout of GeoPackageBinary flags byte indicates:
    # The geometry header includes an envelope [minx, maxx, miny, maxy, minz, maxz]
    # and Little Endian (least significant byte first) is the byte order used for SRS ID and envelope values in the header
    write(buff, 0b00000101)
  else
    # The geometry header includes an envelope [minx, maxx, miny, maxy] and least significant byte first is the byte order
    write(buff, 0b00000011)
  end

  # write the SRS ID, with the endianness specified by the byte order flag
  write(buff, htol(gpkgsrsid(crs)))

  # write the envelope for all content in GeoPackage SQL Geometry Binary Format
  # [minx, maxx, miny, maxy]
  write(buff, htol(extent[1]))
  write(buff, htol(extent[2]))
  write(buff, htol(extent[3]))
  write(buff, htol(extent[4]))
  if CoordRefSystems.ncoords(crs) == 3
    # [..., minz, maxz]
    write(buff, htol(extent[5]))
    write(buff, htol(extent[6]))
  end
end

function gpkgextent(obj)
  bbox = boundingbox(obj)
  cmin = coords(minimum(bbox))
  cmax = coords(maximum(bbox))
  exts = gpkgextent(cmin, cmax)
  ustrip.(exts)
end

gpkgextent(cmin::LatLon, cmax::LatLon) = (cmin.lon, cmax.lon, cmin.lat, cmax.lat)
gpkgextent(cmin::LatLonAlt, cmax::LatLonAlt) = (cmin.lon, cmax.lon, cmin.lat, cmax.lat, cmin.alt, cmax.alt)
gpkgextent(cmin::Projected, cmax::Projected) = (cmin.x, cmax.x, cmin.y, cmax.y)
gpkgextent(cmin::Cartesian2D, cmax::Cartesian2D) = (cmin.x, cmax.x, cmin.y, cmax.y)
gpkgextent(cmin::Cartesian3D, cmax::Cartesian3D) = (cmin.x, cmax.x, cmin.y, cmax.y, cmin.z, cmax.z)

gpkgspatialrefsys(::Type{T}) where {T<:CRS} =
  CoordRefSystems.code(T) <: EPSG ? "EPSG" : "ESRI", gpkgsrsid(T), CoordRefSystems.wkt2(T)
gpkgspatialrefsys(::Cartesian) = "NONE", -1, ""

gpkgsrsid(CRS) = Int32(CoordRefSystems.integer(CoordRefSystems.code(CRS)))
gpkgsrsid(::Type{T}) where {T<:Cartesian} = Int32(-1)

sqlgeomtype(dom::Domain) = sqlgeomtype(eltype(dom))
sqlgeomtype(::Type{<:Point}) = "POINT"
sqlgeomtype(::Type{<:Chain}) = "LINESTRING"
sqlgeomtype(::Type{<:Polygon}) = "POLYGON"
sqlgeomtype(::Type{<:MultiPoint}) = "MULTIPOINT"
sqlgeomtype(::Type{<:MultiChain}) = "MULTILINESTRING"
sqlgeomtype(::Type{<:MultiPolygon}) = "MULTIPOLYGON"
sqlgeomtype(::Type{<:Multi}) = "GEOMETRYCOLLECTION"
sqlgeomtype(::Type{<:Geometry}) = "GEOMETRY"
