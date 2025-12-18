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

# According to https://www.geopackage.org/spec/#r2
# a GeoPackage should contain "GPKG" in ASCII in
# "application_id" field of SQLite db header
const GPKG_APPLICATION_ID = 0x47504B47
const GPKG_1_4_VERSION = 10400

# If the geometry type_name value is "GEOMETRY" then the feature table geometry column
# MAY contain geometries of any allowed geometry type
function SQLite.sqlitetype_(::Type{Vector{UInt8}})
  return "GEOMETRY"
end

function gpkgwrite(fname, geotable;)
  db = SQLite.DB(fname)

  # https://sqlite.org/pragma.html#pragma_synchronous
  # Commits can be orders of magnitude faster with
  # Setting PRAGMA synchronous=OFF but,
  # can cause the database to go corrupt
  # if there is an operating system crash or power failure.
  DBInterface.execute(db, "PRAGMA synchronous=0")

  table = values(geotable)
  domain = GeoTables.domain(geotable)
  crs = GeoTables.crs(domain)
  geom = collect(domain)

  # According to https://www.geopackage.org/spec/#r2
  # A GeoPackage SHALL contain a value of 0x47504B47 ("GPKG" in ASCII)
  # in the "application_id" field and an appropriate value in "user_version" field
  # of the SQLite database header to indicate that it is a GeoPackage
  DBInterface.execute(db, "PRAGMA application_id = $GPKG_APPLICATION_ID ")
  DBInterface.execute(db, "PRAGMA user_version = $GPKG_1_4_VERSION ")

  creategpkgtables(db, table, domain, crs, geom)

  # https://sqlite.org/pragma.html#pragma_optimize
  # Applications with short-lived database connections should run "PRAGMA optimize;"
  # just once, prior to closing each database connection.
  DBInterface.execute(db, "PRAGMA optimize;")

  DBInterface.close!(db)
end

function creategpkgtables(db, table, domain, crs, geom)
  if crs <: Cartesian
    org = ""
    srsid = -1
  elseif crs <: LatLon
    org = "EPSG"
    srsid = 4326
  else
    org = string(CoordRefSystems.code(crs))[1:4]
    srsid = parse(Int32, string(CoordRefSystems.code(crs))[6:(end - 1)])
  end
  gpkgbinary = map(geom) do feature
    gpkgbinheader = writegpkgheader(srsid, feature)
    io = IOBuffer()
    meshes2wkb(io, feature)
    vcat(gpkgbinheader, take!(io))
  end

  features =
  # if no values in table then store only geometry in features
    isnothing(table) ? [(; geom=g,) for (_, g) in zip(1:length(gpkgbinary), gpkgbinary)] :
    # else store the geometry as the first column and the remaining table columns in features
    [(; geom=g, t...) for (t, g) in zip(Tables.rowtable(table), gpkgbinary)]

  rows = Tables.rows(features)
  sch = Tables.schema(rows)
  columns = [
    string(SQLite.esc_id(String(sch.names[i])), ' ', SQLite.sqlitetype(sch.types !== nothing ? sch.types[i] : Any))
    for i in eachindex(sch.names)
  ]

  # https://www.geopackage.org/spec/#r29
  # A feature table SHALL have a primary key column of type INTEGER and that column SHALL act as a rowid alias.
  # The use of the AUTOINCREMENT keyword is optional but recommended.
  # The AUTOINCREMENT keyword imposes extra overhead and should be avoided if not strictly needed.
  DBInterface.execute(db, "CREATE TABLE IF NOT EXISTS features ( $(join(columns, ',')));")

  # generate the SQL parameter string for binding values, chop removes the last comma, resulting in "?,?,?"
  params = chop(repeat("?,", length(sch.names)))
  # generate the comma-separated list of escaped column names for the SQL query
  columns = join(SQLite.esc_id.(string.(sch.names)), ",")
  # Note: the `sql` statement is not actually executed, but only compiled
  # mainly for usage where the same statement is executed multiple times with different parameters bound as values
  stmt = SQLite.Stmt(db, "INSERT INTO features ($columns) VALUES ($params)";)

  # used for holding references to bound statement values via bind!
  handle = SQLite._get_stmt_handle(stmt)

  # an explicit write transaction is started by statements like CREATE, DELETE, DROP, INSERT, or UPDATE
  # the default transaction behavior is DEFERRED.
  # DEFERRED means that the transaction does not actually start until the database is first accessed
  SQLite.transaction(db) do
    row = nothing
    if row === nothing
      # advance the iterator to obtain the next element
      state = iterate(rows)
      # exit transaction if iterator is empty
      state === nothing && return
      row, st = state
    end
    while true
      # bind the values of the current row to the prepared SQL statement
      Tables.eachcolumn(sch, row) do val, col, _
        SQLite.bind!(stmt, col, val)
      end

      # executes the prepared statement and GC.@preserve prevents the 'row' object from being garbage collected
      r = GC.@preserve row SQLite.C.sqlite3_step(handle)
      if r == SQLite.C.SQLITE_DONE
        # insertion successful, reset for next execution
        SQLite.C.sqlite3_reset(handle)
      elseif r != SQLite.C.SQLITE_ROW
        # error occurred (e.g., SQLITE_BUSY, SQLITE_ERROR, or others).
        # throw a Julia-specific SQLite exception after resetting the statement handle.
        e = SQLite.sqliteexception(db, stmt)
        SQLite.C.sqlite3_reset(handle)
        throw(e)
      end
      # advance to the next row
      state = iterate(rows, st)
      # break the loop if iterator is exhausted
      state === nothing && break
      row, st = state
    end

    # collect bounding box for all content in geotable
    bbox = boundingbox(domain)
    # bounding box minimum easting or longitude, and northing or latitude
    mincoords = CoordRefSystems.raw(coords(bbox.min))
    # bounding box maximum easting or longitude, and northing or latitude
    maxcoords = CoordRefSystems.raw(coords(bbox.max))
    # the bounding box (min_x, min_y, max_x, max_y) provides an informative bounding box of the content
    minx, miny, maxx, maxy = mincoords[1], mincoords[2], maxcoords[1], maxcoords[2]
    # 0: z values prohibited; 1: z values mandatory;
    # (x,y{,z}) where x is easting or longitude, y is northing or latitude, and z is optional elevation
    z = paramdim(first(geom)) > 2 ? 1 : 0

    # According to https://www.geopackage.org/spec/#r10
    # A GeoPackage SHALL include a gpkg_spatial_ref_sys table
    DBInterface.execute(
      db,
      """
    CREATE TABLE IF NOT EXISTS gpkg_spatial_ref_sys (
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
    INSERT OR REPLACE INTO gpkg_spatial_ref_sys
        (srs_name, srs_id, organization, organization_coordsys_id, definition, description, definition_12_063)
        VALUES
        ('Undefined Cartesian SRS', -1, 'NONE', -1, 'undefined', 'undefined geographic coordinate reference system', 'undefined'),
        ('Undefined geographic SRS', 0, 'NONE', 0, 'undefined', 'undefined geographic coordinate reference system', 'undefined'),
        ('WGS 84 geodectic', 4326, 'EPSG', 4326, 'GEOGCRS["WGS 84",DATUM["World Geodetic System 1984",ELLIPSOID["WGS 84",6378137,298.257223563,LENGTHUNIT["metre",1]]],PRIMEM["Greenwich",0,ANGLEUNIT["degree",0.0174532925199433]],CS[ellipsoidal,2],AXIS["geodetic latitude (Lat)",north,ORDER[1],ANGLEUNIT["degree",0.0174532925199433]],AXIS["geodetic longitude (Lon)",east,ORDER[2],ANGLEUNIT["degree",0.0174532925199433]],ID["EPSG",4326]]', 'longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid', 'GEOGCRS["WGS 84",DATUM["World Geodetic System 1984",ELLIPSOID["WGS 84",6378137,298.257223563,LENGTHUNIT["metre",1]]],PRIMEM["Greenwich",0,ANGLEUNIT["degree",0.0174532925199433]],CS[ellipsoidal,2],AXIS["geodetic latitude (Lat)",north,ORDER[1],ANGLEUNIT["degree",0.0174532925199433]],AXIS["geodetic longitude (Lon)",east,ORDER[2],ANGLEUNIT["degree",0.0174532925199433]],ID["EPSG",4326]]');
      """
    )
    # Insert non-existing CRS record into gpkg_spatial_ref_sys table.
    if srsid != 4326 && srsid > 0
      # According to https://www.geopackage.org/spec/#r115
      # This conforms to the Well-Known Text for Coordinate Reference Systems extension
      # the gpkg_spatial_ref_sys table SHALL have an additional column called definition_12_063
      DBInterface.execute(
        db,
        """
    INSERT OR REPLACE INTO gpkg_spatial_ref_sys
            (srs_name, srs_id, organization, organization_coordsys_id, definition, description, definition_12_063)
            VALUES
            (?, ?, ?, ?, ?, ?, ?);
        """,
        ["", srsid, org, srsid, CoordRefSystems.wkt2(crs), "", CoordRefSystems.wkt2(crs)]
      )
    end

    # According to https://www.geopackage.org/spec/#r13
    # A GeoPackage SHALL include a gpkg_contents table
    DBInterface.execute(
      db,
      """
    CREATE TABLE IF NOT EXISTS gpkg_contents (
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
    INSERT OR REPLACE INTO gpkg_contents
            (table_name, data_type, identifier, min_x, min_y, max_x, max_y, srs_id)
            VALUES
            (?, ?, ?, ?, ?, ?, ?, ?);
      """,
      ["features", "features", "features", minx, miny, maxx, maxy, srsid]
    )

    # According to https://www.geopackage.org/spec/#r21
    # A  GeoPackage with a gpkg_contents table row with a "features" data_type
    # SHALL contain a gpkg_geometry_columns table
    DBInterface.execute(
      db,
      """
    CREATE TABLE IF NOT EXISTS gpkg_geometry_columns (
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
    INSERT OR REPLACE INTO gpkg_geometry_columns
            (table_name, column_name, geometry_type_name, srs_id, z, m)
            VALUES
            (?, ?, ?, ?, ?, ?);
      """,
      ["features", "geom", "GEOMETRY", srsid, z, 0]
    )

    # https://www.geopackage.org/spec/#r77
    # Extended GeoPackage requires spatial indexes on feature table geometry columns
    # using the SQLite Virtual Table R-trees
    DBInterface.execute(
      db,
      # creates a spatial index using rtree_<t>_<c>
      # where <t> and <c> are replaced with the names of the feature table and geometry column being indexed.
      """
    CREATE VIRTUAL TABLE IF NOT EXISTS rtree_features_geom USING
      rtree(id, minx, maxx, miny, maxy)
      """
    )
    bboxes = map(geom) do ft
      bbox = boundingbox(ft)
      mincoords = CoordRefSystems.raw(coords(bbox.min))
      maxcoords = CoordRefSystems.raw(coords(bbox.max))
      minx, miny, maxx, maxy = mincoords[1], mincoords[2], maxcoords[1], maxcoords[2]
      return (minx, maxx, miny, maxy)
    end

    # The R-tree Spatial Indexes extension provides a means to encode an R-tree index for geometry values
    # And provides a significant performance advantage for searches with basic envelope spatial criteria
    # that return subsets of the rows in a feature table with a non-trivial number (thousands or more) of rows.
    # The index data structure needs to be manually populated, updated and queried.
    stmt = SQLite.Stmt(db, "INSERT OR REPLACE INTO rtree_features_geom VALUES (?, ?, ?, ?, ?)")
    handle = SQLite._get_stmt_handle(stmt)
    for i in 1:length(gpkgbinary)
      # min-value and max-value pairs (stored as 32-bit floating point numbers)
      minx, maxx, miny, maxy = bboxes[i]
      # virtual table 64-bit signed integer primary key id column
      SQLite.bind!(stmt, 1, i)
      # min/max x/y parameters
      SQLite.bind!(stmt, 2, minx)
      SQLite.bind!(stmt, 3, maxx)
      SQLite.bind!(stmt, 4, miny)
      SQLite.bind!(stmt, 5, maxy)

      # Evaluates a SQL Statement and returns SQLITE_DONE, or SQLITE_BUSY, SQLITE_ROW, SQLITE_ERROR, or SQLITE_MISUSE.
      r = GC.@preserve row SQLite.C.sqlite3_step(handle)
      if r != SQLite.C.SQLITE_DONE
        e = SQLite.sqliteexception(db, stmt)
        SQLite.C.sqlite3_reset(handle)
        throw(e)
      end
      # invoke sqlite3_reset() to ensure a statement is finished
      SQLite.C.sqlite3_reset(handle)
    end

    DBInterface.execute(
      db,
      """
    CREATE TABLE IF NOT EXISTS gpkg_extensions (
          table_name TEXT,
          column_name TEXT,
          extension_name TEXT NOT NULL,
          definition TEXT NOT NULL,
          scope TEXT NOT NULL,
          CONSTRAINT ge_tce UNIQUE (table_name, column_name, extension_name)
        )
        """
    )

    DBInterface.execute(
      db,
      """
    INSERT OR REPLACE INTO gpkg_extensions
        (table_name, column_name, extension_name, definition, scope)
        VALUES
        ('features', 'geom', 'gpkg_rtree_index', 'http://www.geopackage.org/spec120/#extension_rtree', 'write-only');
      """
    )
  end
end

function writegpkgheader(srsid, geom)
  io = IOBuffer()
  # 'GP' in ASCII
  write(io, [0x47, 0x50])
  # 8-bit unsigned integer, 0 = version 1
  write(io, zero(UInt8))

  # bit layout of GeoPackageBinary flags byte indicates:
  # The geometry header includes an envelope [minx, maxx, miny, maxy]
  # and Little Endian (least significant byte first) is the byte order used for SRS ID and envelope values in the header.
  flagsbyte = UInt8(0x07 >> 1)
  write(io, flagsbyte)

  # write the SRS ID, with the endianness specified by the byte order flag
  write(io, htol(Int32(srsid)))

  # write the envelope for all content in GeoPackage SQL Geometry Binary Format
  bbox = boundingbox(geom)
  # [minx, maxx, miny, maxy]
  write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.min))[2])))
  write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.max))[2])))
  write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.min))[1])))
  write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.max))[1])))
  if paramdim(geom) >= 3
    # [..., minz, maxz]
    write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.min))[3])))
    write(io, htol(Float64(CoordRefSystems.raw(coords(bbox.max))[3])))
  end

  return take!(io)
end
