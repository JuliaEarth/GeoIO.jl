# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gpkgread(fname; layer=1)
  db = SQLite.DB(fname)
  assertgpkg(db)
  table = gpkgtable(db; layer)
  geoms = gpkggeoms(db; layer)
  DBInterface.close!(db)
  georef(table, geoms)
end

function assertgpkg(db)

  # Requirement 6: PRAGMA integrity_check returns a single row with the value 'ok'
  # Requirement 7: PRAGMA foreign_key_check (w/ no parameter value) returns an empty result set
  if first(DBInterface.execute(db, "PRAGMA integrity_check;")).integrity_check != "ok" ||
     !(isempty(DBInterface.execute(db, "PRAGMA foreign_key_check;")))
    throw(ErrorException("database integrity at risk or foreign key violation(s)"))
  end

  # Requirement 10: must include a gpkg_spatial_ref_sys table
  # Requirement 13: must include a gpkg_contents table

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

function gpkgtable(db, ; layer=1)
  table = DBInterface.execute(
    db,
    """
SELECT c.table_name, c.identifier, 
g.column_name, g.geometry_type_name, g.z, g.m, c.min_x, c.min_y, 
c.max_x, c.max_y, 
(SELECT type FROM sqlite_master WHERE lower(name) = 
lower(c.table_name) AND type IN ('table', 'view')) AS object_type 
  FROM gpkg_geometry_columns g 
  JOIN gpkg_contents c ON (g.table_name = c.table_name)
  WHERE 
  c.data_type = 'features' LIMIT $layer
    """
  )
  tb = map(table) do row
    tn = row.table_name
    tableinfo = SQLite.tableinfo(db, tn).name
    # returns NamedTuple of AbstractVectors, also known as a "column table"
    
    # if there are no aspatial fields in column table then return nothing to table
    if isone(length(tableinfo))
      return nothing
    end
    # remove `column_name` field from tableinfo to avoid querying the GeoPackage geometry column 
    deleteat!(tableinfo, findall(x -> isequal(x, row.column_name), tableinfo))
    columns = join(tableinfo, ", ")

    rowvals = map(DBInterface.execute(db, "SELECT $columns from $tn")) do rv
      NamedTuple(rv)
    end
    rowvals
  end
  isnothing(first(tb)) ? first(tb) : vcat(tb...) 
end

# https://www.geopackage.org/spec/#:~:text=2.1.5.1.2.%20Table%20Data%20Values
#------------------------------------------------------------------------------
# # Requirement 21: a gpkg_contents table row with a "features" data_type
# SHALL contain a gpkg_geometry_columns table
#
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
function gpkggeoms(db, ; layer=1)
  tb = DBInterface.execute(
    db,
    """
SELECT g.table_name AS tn, g.column_name AS cn, c.srs_id as crs, g.z as elev, srs.organization as org, srs.organization_coordsys_id as org_coordsys_id,
( SELECT type FROM sqlite_master WHERE lower(name) = lower(c.table_name) AND type IN ('table', 'view')) AS object_type
FROM gpkg_geometry_columns g, gpkg_spatial_ref_sys srs
JOIN gpkg_contents c ON ( g.table_name = c.table_name )
WHERE c.data_type = 'features'
AND (SELECT type FROM sqlite_master WHERE lower(name) = lower(c.table_name) AND type IN ('table', 'view')) IS NOT NULL
AND g.srs_id = srs.srs_id
AND g.srs_id = c.srs_id
AND g.z IN (0, 1, 2)
AND g.m = 0
 LIMIT $layer;
    """
  )
  firstrow = [row for row in first(tb)]
  # Note: first feature table that is read specifies the CRS to be used on all feature tables resulted from SELECT statement

  srsid, org, orgcoordsysid = firstrow[3], firstrow[5], firstrow[6]
  crs = Cartesian{NoDatum} # an srs_id of -1 uses undefined Cartesian CRS
  if iszero(srsid) # an srs_id of 0 uses undefined Geographic CRS
    crs = LatLon{WGS84Latest}
  elseif !isone(abs(srsid))
    if org == "EPSG"
      crs = CoordRefSystems.get(EPSG{orgcoordsysid})
    elseif org == "ESRI"
      crs = CoordRefSystems.get(ERSI{orgcoordsysid})
    end
  end

  featuretablegeoms = map((row.tn, row.cn) for row in tb) do (tn, cn)
    # get feature geometry from geometry column in feature table
    gpkgbinary = DBInterface.execute(db, "SELECT $cn FROM $tn;")
    headerlen = 0
    geomcollection = map(gpkgbinary) do blob
      if blob[1][1:2] != UInt8[0x47, 0x50]
        @warn "Missing magic 'GP' string in GPkgBinaryGeometry"
      end
      io = IOBuffer(blob[1])
      seek(io, 3)
      flag = read(io, UInt8)

      # envelope contents indicator code (3-bit unsigned integer)
      envelope = (flag & (0x07 << 1)) >> 1
      envelopecode = 0
      if !iszero(envelope)
        if isone(envelope)
          envelopecode = 2 # 2D envelope [minx, maxx, miny, maxy], 32 bytes
        elseif isequal(2, envelope)
          envelopecode = 3 # 2D+Z envelope [minx, maxx, miny, maxy, minz, maxz], 48 bytes
        elseif isequal(3, envelope)
          envelopecode = 4 # 2D+M envelope [minx, maxx, miny, maxy, minm, maxm] (is not supported)
        elseif isequal(4, envelope)
          envelopecode = 5 # 2D+ZM envelope [minx, maxx, miny, maxy, minz, maxz, minm, maxm] (is not supported)
        else # 5-7: invalid
          throw(ErrorException("exceeded dimensional limit for geometry"))
        end
      end # else no envelope (space saving slower indexing option), 0 bytes

      headerlen = 8 + 8 * 2 * envelopecode # calculate header size in byte stream 
      seek(io, headerlen) # skip reading envelope bytes
      # start reading Well-Known Binary geometry
      wkbbyteswap = isone(read(io, UInt8)) ? ltoh : ntoh
      # Note that Julia does not convert the endianness for you.
      # Use ntoh or ltoh for this purpose.

      wkbtypebits = read(io, UInt32)
      zextent = isequal(envelopecode, 3)
      if zextent # if the geometry type is a 3D geometry type
        # if WKBGeometry is specified in `extended WKB` remove the the dimensionality bit flag that indicates a Z dimension
        wkbtype = !iszero(wkbtypebits & ewkbmaskbits) ? wkbtypebits & 0x000000F : wkbtypebits - 1000
        # if WKBGeometry is specified in `ISO WKB` and we simply subtract the round number added to the type number that indicates a Z dimensions.
      else
        wkbtype = wkbtypebits
      end

      geom = gpkgwkbgeom(io, crs, wkbtype, zextent, wkbbyteswap)
      if !isnothing(geom)
        geom
      end
    end
    geomcollection
  end
  # efficient method for concatenating arrays of arrays 
  reduce(vcat, featuretablegeoms) # Future versions of Julia might change the reduce algorithm
end
