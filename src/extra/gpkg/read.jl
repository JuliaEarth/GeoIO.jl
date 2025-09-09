# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# query SQLite.Table given *.gpkg filename; optionally specify quantity of tables and features query
# default behavior for select statement is limit result to 1 feature geometry row and corresponding attributes row
# limited to only 1 feature table to select geopackage binary geometry from.
function gpkgread(fname ;ntables=1, nfeatures=1)
    db = SQLite.DB(fname)
    gpkg_identify(db)
    geom = gpkgmesh(db, ; ntables=ntables, nfeatures=nfeatures)
    attrs = gpkgmeshattrs(db, ; ntables=ntables, nfeatures=nfeatures)
    GeoTables.georef(attrs, geom)
end


function gpkg_identify(db)::Bool

    application_id = DBInterface.execute(db, "PRAGMA application_id;") |> first |> only
    user_version = DBInterface.execute(db, "PRAGMA user_version;") |> first |> only

    if !(_has_gpkg_required_metadata_tables(db))
        @error "missing required metadata tables"
    end

    # Requirement 6: PRAGMA integrity_check returns a single row with the value 'ok'
    # Requirement 7: PRAGMA foreign_key_check (w/ no parameter value) returns an empty result set
    if (application_id != GP10_APPLICATION_ID) &&
            (application_id != GP11_APPLICATION_ID) &&
                (application_id != GPKG_APPLICATION_ID)
        @warn "application_id not recognized"
        return false
    elseif(application_id == GPKG_APPLICATION_ID) &&
        !(
            (user_version >= GPKG_1_2_VERSION && user_version < GPKG_1_2_VERSION + 99) ||
            (user_version >= GPKG_1_3_VERSION && user_version < GPKG_1_3_VERSION + 99) ||
            (user_version >= GPKG_1_4_VERSION && user_version < GPKG_1_4_VERSION + 99)
        )
        @warn "application_id is valid but user version is not recognized"
    elseif(
        DBInterface.execute(db, "PRAGMA integrity_check;") |> first |> only != "ok"
        ) || !(
            isempty(DBInterface.execute(db, "PRAGMA foreign_key_check;"))
          )
        @error "database integrity at risk or foreign key violation(s)"
        return false
    end
    return true
end

# Requirement 10: must include a gpkg_spatial_ref_sys table
# Requirement 13: must include a gpkg_contents table
function _has_gpkg_required_metadata_tables(db)
    stmt_sql = "SELECT COUNT(*) FROM sqlite_master WHERE "*
               "name IN ('gpkg_spatial_ref_sys', 'gpkg_contents') AND "*
                "type IN ('table', 'view');"
    required_metadata_tables = DBInterface.execute(db, stmt_sql) |> first |> only
    return (required_metadata_tables == 2)
end



function gpkgmeshattrs(db, ;ntables::Int=1, nfeatures=1)
    stmt_sql = "SELECT c.table_name, c.identifier, "*
            "g.column_name, g.geometry_type_name, g.z, g.m, c.min_x, c.min_y, "*
            "c.max_x, c.max_y, "*
            "(SELECT type FROM sqlite_master WHERE lower(name) = "*
            "lower(c.table_name) AND type IN ('table', 'view')) AS object_type "*
            "  FROM gpkg_geometry_columns g "*
            "  JOIN gpkg_contents c ON (g.table_name = c.table_name)"*
            "  WHERE "*
            "  c.data_type = 'features' LIMIT $ntables"
    feature_tables = DBInterface.execute(db, stmt_sql)
    tb = []; fields = "fid," ^ 10^5
    for query in feature_tables
        tn = query.table_name; cn = query.column_name;
        ft_attrs  = SQLite.tableinfo(db, tn).name
        deleteat!(ft_attrs, findall(x -> isequal(x, cn), ft_attrs))
        rp_attrs = join(ft_attrs, ", ")
        # keep the shortest set of attributes to avoid KeyError {Key} not found
        fields = length(fields) > length(rp_attrs) ? rp_attrs : fields # smelly hack, eval shortest common subset of fields instead
        stmt_sql = "SELECT $fields from $tn LIMIT $nfeatures;"
        if isone(nfeatures)
            rowvalues = DBInterface.execute(db, stmt_sql) |> first
            push!(tb, rowvalues)
        else
            for rv in DBInterface.execute(db, stmt_sql)
                push!(tb, NamedTuple(rv))
            end
        end
    end
    return tb
end


##############################################################################
########### Features - Geometry Columns: Table Data Values ###################
##############################################################################
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
#
function gpkgmesh(db, ;ntables=1, nfeatures=1)
    stmt_sql ="""
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
                LIMIT $ntables;
                """
    tb = DBInterface.execute(db, stmt_sql)
    meshes = Meshes.Geometry[]
    for (tn, cn, org, org_coordsys_id) in [(row.tn, row.cn, row.org, row.org_coordsys_id) for row in tb]
        stmt_sql = "SELECT $cn FROM $tn LIMIT $nfeatures;"
        gpkgbinary = DBInterface.execute(db, stmt_sql)
        headerlen = 0
        for blob in gpkgbinary
            io = IOBuffer(blob[1])
            seek(io, 3)
            flag = read(io, UInt8)
            # Note that Julia does not convert the endianness for you.
            # Use ntoh or ltoh for this purpose.
            bswap = isone(flag & 0x01) ? ltoh : ntoh

            srs_id = bswap(read(io, UInt32))

            envelope = (flag & (0x07 << 1)) >> 1
            envelopedims = 0

            if !iszero(envelope)
                if isone(envelope)
                    envelopedims = 1 # 2D
                elseif isequal(2, envelope)
                    envelopedims = 2 # 2D+Z
                elseif isequal(3, envelope)
                    envelopedims = 3 # 2D+M
                elseif isequal(4, envelope)
                    envelopedims = 4 # 2D+ZM
                else
                    @error "exceeded dimensional limit for geometry, file may be corrupted or reader is broken"
                    false
                end
            else
                true # no envelope (space saving slower indexing option), 0 bytes
            end

            # header size in byte stream
            headerlen = 8 + 8 * 4 * envelopedims
            seek(io, headerlen)

            ebyteorder = read(io, UInt8)

            bswap = isone(ebyteorder) ? ltoh : ntoh
            
            wkbtype = wkbGeometryType(read(io, UInt32))

            zextent = isequal(envelopedims, 2)
            
            mesh = meshfromwkb(io, srs_id, org, org_coordsys_id, wkbtype, zextent, bswap)

            if !isnothing(mesh)
                push!(meshes, mesh)
            end
        end
    end
    return meshes
end

function meshfromwkb(io, srs_id, org, org_coordsys_id, ewkbtype, extent_has_z, bswap)
    if iszero(srs_id)
        crs = LatLon{WGS84Latest}
    elseif isone(abs(srs_id))
        crs = extent_has_z ? Cartesian{NoDatum, 3} : Cartesian{NoDatum, 2}
    else
        if org == "EPSG"
            crs = CoordRefSystems.get(EPSG{org_coordsys_id})
        elseif org == "ESRI"
            crs = CoordRefSystems.get(ERSI{org_coordsys_id})
        else
            Cartesian{NoDatum}
        end
    end

    if occursin("Multi", string(ewkbtype))
        elems::Vector = wkbmultigeometry(io, crs, extent_has_z, bswap)
        return Meshes.Multi(elems)
    else
        elem = meshfromsf(io, crs, ewkbtype, extent_has_z, bswap)
        return elem
    end
end

################################################################
# Requirement 20: GeoPackage SHALL store feature table geometries
#  with the basic simple feature geometry types
# https://www.geopackage.org/spec140/index.html#geometry_types
#
function meshfromsf(io, crs, ewkbtype, extent_has_z, bswap)
    if isequal(ewkbtype, wkbPoint)
        elem = wkbcoordinate(io, extent_has_z, bswap)
        return Meshes.Point(crs(elem...))
    elseif isequal(ewkbtype, wkbLineString)
        elem = wkblinestring(io, extent_has_z, bswap)
        if first(elem) != last(elem)
             return Meshes.Rope([Meshes.Point(crs(coords...)) for coords in elem]...)
        else
             return Meshes.Ring([Meshes.Point(crs(coords...)) for coords in elem[2:end]]...)
        end
    elseif isequal(ewkbtype, wkbPolygon)
        elem = wkbpolygon(io, extent_has_z, bswap)
        rings = map(elem) do ring
            coords = map(ring) do point
                Meshes.Point(crs(point...))
            end
            Meshes.Ring(coords)
        end

        outer_ring = first(rings)
        holes = isone(length(rings)) ? rings[2:end] : Meshes.Ring[]
        return Meshes.PolyArea(outer_ring, holes...)
    end
end

function wkbcoordinate(io, z, bswap)
    x = bswap(read(io, Float64))
    y = bswap(read(io, Float64))

    if z
        z = bswap(read(io, Float64))
        return x, y, z
    end

    return x, y
end

function wkblinestring(io, z, bswap)
    npoints = bswap(read(io, UInt32))

    points = map(1:npoints) do _
        wkbcoordinate(io, z, bswap)
    end
    return points
end

function wkbpolygon(io, z, bswap)
    nrings = bswap(read(io, UInt32))

    rings = map(1:nrings) do _
        wkblinestring(io, z, bswap)
    end
    return rings
end

function wkbmultigeometry(io, crs, z, bswap)
    ngeoms = bswap(read(io, UInt32))

    geomcollection = map(1:ngeoms) do _
            bswap = isone(read(io, UInt8)) ? ltoh : ntoh
            ewkbtype = wkbGeometryType(read(io, UInt32))
            meshfromsf(io, crs, ewkbtype, z, bswap)
        end
    return geomcollection
end
