# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gpkgread(fname; layer=1)
  db = SQLite.DB(fname)
  assertgpkg(db)
  geoms = gpkggeoms(db; layer)
  table = gpkgvalues(db; layer)
  DBInterface.close!(db)
  if eltype(table) <: Nothing
    return georef(nothing, geoms)
  else
    georef(table, geoms)
  end
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
  tbcount = first(DBInterface.execute(
    db,
    """
  SELECT COUNT(*) AS n FROM sqlite_master WHERE 
  name IN ('gpkg_spatial_ref_sys', 'gpkg_contents') AND 
  type IN ('table', 'view');
    """
  ))
  if tbcount.n != 2
    throw(ErrorException("missing required metadata tables in the GeoPackage SQL database"))
  end
end

function gpkgvalues(db, ; layer=1)
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
  fields = nothing
  table = map(table) do query
    tn = query.table_name
    tableinfo = SQLite.tableinfo(db, tn).name
    # returns NamedTuple of AbstractVectors, also known as a "column table"

    # remove `column_name` field from tableinfo in-place
    # to avoid querying the geometry column that stores feature geometry
    deleteat!(tableinfo, findall(x -> isequal(x, query.column_name), tableinfo))
    columns = join(tableinfo, ", ")

    # keep the shortest set of fields if there is more than one feature table
    if isnothing(fields) || length(columns) < length(fields)
      fields = columns
    end

    # if there are no fields in column table then return nothing to table
    if iszero(length(fields))
      return nothing
    end
    rowvals = map(DBInterface.execute(db, "SELECT $fields from $tn")) do rv
      NamedTuple(rv)
    end
    rowvals
  end
  vcat(table...)
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
AND g.m IN (0, 1, 2)
 LIMIT $layer;
    """
  )
  featuretablegeoms = map((row.tn, row.cn, row.org, row.org_coordsys_id) for row in tb) do (tn, cn, org, orgcoordsysid)
    # get feature geometry from geometry column in feature table
    gpkgbinary = DBInterface.execute(db, "SELECT $cn FROM $tn;")
    headerlen = 0

    gpkgblobs = filter(map(NamedTuple, gpkgbinary)) do row
      !ismissing(getfield(row, Symbol(cn))) # ignore all rows with missing geometries
    end

    geomcollection = map(gpkgblobs) do blob
      if blob[1][1:2] != UInt8[0x47, 0x50]
        @warn "Missing magic 'GP' string in GPkgBinaryGeometry"
      end
      io = IOBuffer(blob[1])
      seek(io, 3)
      flag = read(io, UInt8)
      # Note that Julia does not convert the endianness for you.
      # Use ntoh or ltoh for this purpose.
      bswap = isone(flag & 0x01) ? ltoh : ntoh
      srsid = bswap(read(io, Int32))
      envelope = (flag & (0x07 << 1)) >> 1
      envelopedims = 0
      if !iszero(envelope)
        if isone(envelope)
          envelopedims = 1 # 2D
        elseif isequal(2, envelope)
          envelopedims = 2 # 2D+Z
        elseif isequal(3, envelope)
          envelopedims = 3 # 2D+M is not supported
        elseif isequal(4, envelope)
          envelopedims = 4 # 2D+ZM is not supported
        else
          throw(ErrorException("exceeded dimensional limit for geometry, file may be corrupted or reader is broken"))
        end
      end # else no envelope (space saving slower indexing option), 0 bytes

      # header size in byte stream
      headerlen = 8 + 8 * 4 * envelopedims
      seek(io, headerlen)
      wkbbyteswap = isone(read(io, UInt8)) ? ltoh : ntoh
      wkbtypebits = read(io, UInt32)
      zextent = isequal(envelopedims, 2)
      if zextent
        wkbtype =
          wkbtypebits & ewkbmaskbits ? wkbGeometryType(wkbtypebits & 0x000000F) : wkbGeometryType(wkbtypebits - 1000)
      else
        wkbtype = wkbGeometryType(wkbtypebits)
      end

      if iszero(srsid)
        crs = LatLon{WGS84Latest}
      elseif !isone(abs(srsid))
        if org == "EPSG"
          crs = CoordRefSystems.get(EPSG{orgcoordsysid})
        elseif org == "ESRI"
          crs = CoordRefSystems.get(ERSI{orgcoordsysid})
        end
      else
        crs = Cartesian{NoDatum}
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