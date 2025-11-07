# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gpkgread(fname; layer=1)
  db = SQLite.DB(fname)
  assertgpkg(db)
  table, geoms = gpkgtable(db; layer)
  DBInterface.close!(db)
  georef(table, geoms)
end

function assertgpkg(db)
  # According to https://www.geopackage.org/spec/#r6 and https://www.geopackage.org/spec/#r7
  # PRAGMA integrity_check returns a single row with the value 'ok'
  # PRAGMA foreign_key_check (w/ no parameter value) returns an empty result set
  if first(DBInterface.execute(db, "PRAGMA integrity_check;")).integrity_check != "ok" ||
     !(isempty(DBInterface.execute(db, "PRAGMA foreign_key_check;")))
    throw(ErrorException("database integrity at risk or foreign key violation(s)"))
  end
  # According to https://www.geopackage.org/spec/#r10 and https://www.geopackage.org/spec/#r13
  # A GeoPackage SHALL include a 'gpkg_spatial_ref_sys' table and a 'gpkg_contents table'
  if first(DBInterface.execute(
    db,
    """
  SELECT COUNT(*) AS n FROM sqlite_master WHERE 
  name IN ('gpkg_spatial_ref_sys', 'gpkg_contents') AND 
  type IN ('table', 'view');
    """
  )).n != 2
    throw(ErrorException("missing required metadata tables in the GeoPackage SQL database"))
  end
end

# According to Geometry Columns Table Requirements
# https://www.geopackage.org/spec/#:~:text=2.1.5.1.2.%20Table%20Data%20Values
#------------------------------------------------------------------------------
# Requirement 22: gpkg_geometry_columns table
# SHALL contain one row record for the geometry column
# in each vector feature data table
#
# Requirement 23: gpkg_geometry_columns table_name column
# SHALL reference values in the gpkg_contents table_name column
# for rows with a data_type of 'features'
#
# Requirement 24: The column_name column value in a gpkg_geometry_columns row
# SHALL be the name of a column in the table or view specified by the table_name
# column value for that row.
#
# Requirement 25: The geometry_type_name value in a gpkg_geometry_columns row
# SHALL be one of the uppercase geometry type names specified

# Requirement 26: The srs_id value in a gpkg_geometry_columns table row
# SHALL be an srs_id column value from the gpkg_spatial_ref_sys table.
#
# Requirement 27: The z value in a gpkg_geometry_columns table row SHALL be one
# of 0, 1, or 2.
#
# Requirement 28: The m value in a gpkg_geometry_columns table row SHALL be one
# of 0, 1, or 2.
#
# Requirement 146: The srs_id value in a gpkg_geometry_columns table row
# SHALL match the srs_id column value from the corresponding row in the
# gpkg_contents table.
function gpkgtable(db, ; layer=1)
  rowtable = DBInterface.execute(
    # According to https://www.geopackage.org/spec/#r16 
    # Values of the gpkg_contents table srs_id column 
    # SHALL reference values in the gpkg_spatial_ref_sys table srs_id column
    # According to https://www.geopackage.org/spec/#r18
    # The gpkg_contents table SHALL contain a row 
    # with a lowercase data_type column value of "features" 
    # for each vector features user data table or view.
    db,
    """
    SELECT g.table_name AS tablename, g.column_name AS columnname, 
    c.srs_id AS srsid, g.z, srs.organization AS org, srs.organization_coordsys_id AS orgcoordsysid,
    ( SELECT type FROM sqlite_master WHERE lower(name) = lower(c.table_name) AND type IN ('table', 'view')) AS object_type
    FROM gpkg_geometry_columns g, gpkg_spatial_ref_sys srs
    JOIN gpkg_contents c ON ( g.table_name = c.table_name )
    WHERE c.data_type = 'features'
    AND object_type IS NOT NULL
    AND g.srs_id = srs.srs_id
    AND g.srs_id = c.srs_id
    AND g.z IN (0, 1, 2)
    AND g.m = 0
    LIMIT $layer;
    """
  )

  # Note: first feature table that is read specifies the CRS to be used on all feature tables resulted from SELECT statement
  firstrow = first(rowtable)

  # According to https://www.geopackage.org/spec/#r33, feature table geometry columns
  # SHALL contain geometries with the srs_id specified 
  # for the column by the gpkg_geometry_columns table srs_id column value.
  srsid, org, orgcoordsysid = firstrow.srsid, firstrow.org, firstrow.orgcoordsysid

  # an srs_id of 0 uses undefined Geographic CRS
  if iszero(srsid)
    crs = LatLon{WGS84Latest}
    # if srs_id not equal to -1
  elseif srsid != -1
    # CRS assigned by the org 
    if org == "EPSG"
      # orgcoordsysid is the numeric id of the CRS assigned by the org
      crs = CoordRefSystems.get(EPSG{orgcoordsysid})
    elseif org == "ESRI"
      crs = CoordRefSystems.get(ERSI{orgcoordsysid})
    end
  else
    # defaults to undefined Cartesian CRS
    crs = Cartesian{NoDatum}
  end

  results = map((row.tablename, row.columnname) for row in rowtable) do (tablename, columnname)
    # According to https://www.geopackage.org/spec/#r14
    # The table_name column value in a gpkg_contents table row 
    # SHALL contain the name of a SQLite table or view.
    tableinfo = SQLite.tableinfo(db, tablename)
    # "pk" (either zero for columns that are not part of the primary key, or the 1-based index of the column within the primary key)
    columns = [name for (name, pk) in zip(tableinfo.name, tableinfo.pk) if pk == 0]
    gpkgbinary = DBInterface.execute(db, "SELECT  $(join(columns, ',')) FROM $tablename;")
    # length of the GeoPackageBinaryHeader 
    headerlen = 0
    geomcollection = map(gpkgbinary) do row
      # According to https://www.geopackage.org/spec/#r30
      # A feature table or view SHALL have only one geometry column.
      columnindex = findfirst(==(Symbol(columnname)), keys(row))
      rowvals = map(keys(row)[[begin:(columnindex - 1); (columnindex + 1):end]]) do key
        key, getproperty(row, key)
      end
      # get the column of SQL Geometry Binary specified by gpkg_geometry_columns table in column_name field
      blob = getproperty(row, Symbol(columnname))

      # According to https://www.geopackage.org/spec/#r19
      # A GeoPackage SHALL store feature table geometries in SQL BLOBs using the Standard GeoPackageBinary format
      # check the GeoPackageBinaryHeader for the first byte[2] to be 'GP' in ASCII
      if blob[1:2] != UInt8[0x47, 0x50]
        @warn "Missing magic 'GP' string in GPkgBinaryGeometry"
      end

      # create in-memory I/O stream of GeoPackage SQL Geometry Binary Format starting after byte[2] magic = 0x4750;
      io = IOBuffer(blob)
      # skip the magic string in header
      seek(io, 3)

      # bit layout of GeoPackageBinary flags byte
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
      flag = read(io, UInt8)

      # 0x07 is a 3-bit mask 0x00001110
      # left-shift moves the 3-bit mask by one to align with E bits in flag layout
      # bitwise AND operation isolates the E bits
      # right-shift moves the E bits by one to align with the least significant bits
      # results in a 3-bit unsigned integer
      envelope = (flag & (0x07 << 1)) >> 1
      
      # calculate GeoPackageBinaryHeader size in byte stream given extent of envelope:
      # envelope is [minx, maxx, miny, maxy, minz, maxz], 48 bytes or envelope is [minx, maxx, miny, maxy], 32 bytes or no envelope, 0 bytes
      # byte[2] magic + byte[1] version + byte[1] flags + byte[4] srs_id + byte[(8*2)×(x,y{,z})] envelope
      headerlen = iszero(envelope) ? 8 : 8 + 8 * 2 * (envelope + 1)

      # Skip reading the double[] envelope and start reading Well-Known Binary geometry 
      seek(io, headerlen)

      geom = gpkgwkbgeom(io, crs)
      if !isnothing(geom)
        # returns a tuple of the corresponding aspatial attributes and the geometries for each row in the feature table
        return (NamedTuple(rowvals), geom)
      end
    end
    geomcollection
  end
  # efficient method for concatenating arrays of arrays 
  table = reduce(vcat, results)
  # unpack results to return aspatial and spatial results
  getindex.(table, 1), getindex.(table, 2)
end
