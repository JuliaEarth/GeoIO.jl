# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gpkgread(fname; layer=1)
  db = gpkgdatabase(fname)
  table, geoms = gpkgextract(db; layer)
  DBInterface.close!(db)
  georef(table, geoms)
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
  # A GeoPackage SHALL include a 'gpkg_contents` table
  if isnothing(SQLite.tableinfo(db, "gpkg_contents"))
    throw(ErrorException("missing required metadata tables in the GeoPackage SQL database"))
  end

  db
end

function gpkgextract(db; layer=1)
  # get the feature table or Any[] returned in sqlite query results
  metadata = first(
    DBInterface.execute(
      db,
      """
      SELECT g.table_name AS tablename, g.column_name AS geomcolumn, 
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
  )

  # According to https://www.geopackage.org/spec/#r33
  # Feature table geometry columns SHALL contain geometries
  # with the srs_id specified for the column by the
  # gpkg_geometry_columns table srs_id column value.
  org = metadata.org
  code = metadata.code
  srsid = metadata.srsid
  if srsid == 0
    crs = LatLon{NoDatum}
  elseif srsid == 4326
    crs = LatLon{WGS84Latest}
  elseif srsid == -1
    crs = Cartesian{NoDatum}
  else
    if org == "EPSG"
      crs = CoordRefSystems.get(EPSG{code})
    elseif org == "ESRI"
      crs = CoordRefSystems.get(ESRI{code})
    end
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
  gpkgtable = DBInterface.execute(db, "SELECT $(join(columns, ',')) FROM $tablename;")

  # extract attribute table and geometries
  pairs = map(Tables.rows(gpkgtable)) do row
    # retrieve attribute values as a named tuple
    vals = (; (col => Tables.getcolumn(row, col) for col in attribs)...)

    # retrieve geometry binary data as IO buffer
    buff = IOBuffer(Tables.getcolumn(row, geomcolumn))

    miss = findall(blob -> ismissing(blob), buff)
    if !isempty(miss)
       @warn "Dropping $(length(miss)) rows with missing geometries." 
    end

    # seek start of geometry (e.g., discard envelope)
    wkbgeom = seekgeom(buff)

    # convert buffer into Meshes.jl geometry
    geom = wkb2geom(wkbgeom, crs)

    vals, geom
  end

  # handle tables without attributes
  table = isempty(attribs) ? nothing : first.(pairs)
  geoms = GeometrySet(last.(pairs))

  table, geoms
end

# According to https://www.geopackage.org/spec/#r19
# A GeoPackage SHALL store feature table geometries in
# SQL BLOBs using the Standard GeoPackageBinary format
function seekgeom(buff)
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
  flag = read(buff, UInt8)
  E = (flag & 0b00001110) >> 1

  # skip srs id
  skip(buff, 4)

  # skip envelope
  E > 0 && skip(buff, 8 * 2 * (E + 1))

  buff
end
