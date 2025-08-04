
function gpkgwrite(fname, geotable; )


    db = SQLite.DB(fname)


    # DBInterface.execute(db, "PRAGMA foreign_keys = ON")

    #DBInterface.execute(db, "PRAGMA journal_mode=WAL;")
    # Write transactions are very fast since they only involve writing the content once
    # (versus twice for rollback-journal transactions) and because the writes are all sequential

    DBInterface.execute(db, "PRAGMA synchronous=0")
    # Commits can be orders of magnitude faster with
    # Setting PRAGMA synchronous=OFF can cause the database to go corrupt
    # if there is an operating-system crash or power failure,
    # though this setting is safe from damage due to application crashes.

    SQLite.transaction(db) do

# -------------------------
# REQUIRED METADATA TABLES
# -------------------------

# Requirement 11: The gpkg_spatial_ref_sys table SHALL contain at a minimum:
#  1. The record with an srs_id of 4326 SHALL correspond to WGS-84 as defined by EPSG in 4326.
#  OR
#  2. The record with an srs_id of -1 SHALL be used for undefined Cartesian coordinate reference systems.
#  OR
#  3. The record with an srs_id of 0 SHALL be used for undefined geographic coordinate reference systems.
        stmt = CREATE_GPKG_REQUIRED_METADATA*
# -------------------------
# OPTIONAL METADATA TABLES
# -------------------------
        stmt *= CREATE_GPKG_GEOMETRY_COLUMNS

        stmt_sql = SQLite.Stmt(db, stmt)
        DBInterface.execute(stmt_sql)


        stmt_sql = SQLite.Stmt(db, "PRAGMA application_id = $GPKG_APPLICATION_ID ")
        DBInterface.execute(stmt_sql)
        stmt_sql = SQLite.Stmt(db, "PRAGMA user_version = $GPKG_1_4_VERSION ")
        DBInterface.execute(stmt_sql)

    end

    to_gpkg(db, geotable)

    SQLite.close(db)

    return
end


function to_gpkg(db, gt::GeoTable)
    table = values(gt)
    domain = GeoTables.domain(gt)
    crs = GeoTables.crs(domain)
    geometry = collect(domain)

    if crs <: Cartesian
        crs = -1
    elseif crs <: LatLon{WGS84Latest}
        crs = Int32(4326)
    end

    println("crs: ", crs)
    gpkgbin_blobs = Vector{Vector{UInt8}}()

    for geom::Geometry in geometry
        gpkgbin_header = _gpkg_update_header(crs, geom)
        io = IOBuffer()
        _import_to_wkb(io, geom)
        wkb_blob = take!(io)
        push!(gpkgbin_blobs, vcat(gpkgbin_header, wkb_blob))
    end

    table = merge(table, (geom=gpkgbin_blobs,))
    SQLite.load!(table, db, replace=false) # autogenerates table name
    # replace=false controls whether
    # an INSERT INTO ... statement is generated or a REPLACE INTO ....
    println(table |> DataFrame)
    tn = DBInterface.execute(db, "SELECT name FROM sqlite_master WHERE type='table'")
    nm = ""
    for row in tn
        nm = row.name
    end

    bbox = boundingbox(domain)
    min_coords = CoordRefSystems.raw(coords(bbox.min))
    max_coords = CoordRefSystems.raw(coords(bbox.max))

    contents_table = [(table_name = nm,
                      data_type = "features",
                      identifier = nm,
                      min_x = min_coords[1],
                      min_y = min_coords[2],
                      max_x = max_coords[1],
                      max_y = max_coords[2],
                      srs_id = crs
                      )]

    println(contents_table |> DataFrame)
    SQLite.load!(contents_table, db, "gpkg_contents", replace=true)

    geometry_columns_table =  [(table_name = nm,
                                column_name = "geom",
                                geometry_type_name = nm,
                                srs_id = crs,
                                z = paramdim(first(geometry)) >= 2 ? 1 : 0,
                                m = 0
                                )]

    println(geometry_columns_table |> DataFrame)
    SQLite.load!(geometry_columns_table, db, "gpkg_geometry_columns", replace=true)


end

function gpkg_gtype(geoms::AbstractVector{<:Geometry})

  T = eltype(geoms)

  if T <: Point
    return "POINT"
  elseif T <: Rope
    return "LINESTRING"
  elseif T <: Ring
    return "LINESTRING"
  elseif T <: PolyArea
    return "POLYGON"
  elseif T <: Multi

      element_type = eltype(parent(first(geoms)))
      return "MULTI"*gpkg_gtype(element_type)
  else
      return "GEOMETRY"
  end

end

function _gpkg_update_header(srs_id, geometry, envelope::Int=1)

    io = IOBuffer()
    write(io, MAGIC_GPKG_BINARY_STRING) # 'GP' in ASCII
    write(io, UInt8(0)) #  0 = version 1

    flagsbyte = UInt8(0x20 | (envelope << 1))
    write(io, flagsbyte)

    bswap = @BSWAP (flagsbyte & 0x01)

    bswap ? write(io, Base.bswap(srs_id)) : write(io, srs_id)

    if isone(envelope)
        bbox = boundingbox(geometry)
        if bswap
            write(io, Base.bswap(Float64(CoordRefSystems.raw(coords(bbox.min))[1])))
            write(io, Base.bswap(Float64(CoordRefSystems.raw(coords(bbox.max))[1])))
            write(io, Base.bswap(Float64(CoordRefSystems.raw(coords(bbox.min))[2])))
            write(io, Base.bswap(Float64(CoordRefSystems.raw(coords(bbox.max))[2])))
        else
            write(io, Float64(CoordRefSystems.raw(coords(bbox.min))[1]))
            write(io, Float64(CoordRefSystems.raw(coords(bbox.max))[1]))
            write(io, Float64(CoordRefSystems.raw(coords(bbox.min))[2]))
            write(io, Float64(CoordRefSystems.raw(coords(bbox.max))[2]))
        end
    end

    if isone(envelope-1) && paramdim(geometry) >= 3
        bbox = boundingbox(geometry)
        if bswap
            write(io, Base.bswap(Float64(CoordRefSystems.raw(coords(bbox.min))[3])))
            write(io, Base.bswap(Float64(CoordRefSystems.raw(coords(bbox.max))[3])))
        else
            write(io, Float64(CoordRefSystems.raw(coords(bbox.min))[3]))
            write(io, Float64(CoordRefSystems.raw(coords(bbox.max))[3]))
        end
    end

    return take!(io)

end


function wkb_set_z(type::wkbGeometryType)
    return wkbGeometryType(Int(type)+1000)
    # ISO WKB simply adds a round number to the type number to indicate extra dimensions
end

function wkb_has_z(type::wkbGeometryType)
    return Int(type) > 1000
end

function wkbtype(geometry)
    if geometry isa Point
        return wkbPoint
    elseif geometry isa Rope || geometry isa Ring
        return wkbLineString
    elseif geometry isa PolyArea
        return wkbPolygon
    elseif geometry isa Multi
        fg = parent(geometry) |> first
        return wkbGeometryType(Int(wkbtype(fg))+3)
    else
        @error "my hovercraft is full of eels: $geometry"
    end
end

function _import_to_wkb(io, geometry)
    gtype = isone(paramdim(geometry)-1) ? wkb_set_z(wkbtype(geometry)) :  wkbtype(geometry)
    create_wkb_geometry(io, geometry, gtype)
end

function create_wkb_geometry(io, geometry, gtype)
    if Int(gtype) > 3
        write(io, UInt8(0x01))
        write(io, UInt32(gtype))
        write(io, UInt32(length(parent(geometry))) )

        for geom in parent(geometry)
            create_wkb_geometry(io, geom, wkbtype(geom))
        end
    else
        import_wkb_geometry(io, geometry, gtype)
    end
end

function import_wkb_geometry(io, geometry, wkb_type)

    write(io, UInt8(0x01))

    bswap = @BSWAP(one(0x01))

    if wkb_type == wkbPolygon || wkb_type == wkbPolygonZ

        _to_wkb_polygon(io, wkb_type, [boundary(geometry::PolyArea)])

    elseif wkb_type == wkbLineString || wkb_type == wkbLineStringZ

        coordinate_list = vertices(geometry)
        bswap ? Base.bswap(write(io, UInt32(wkb_type))) : write(io, UInt32(wkb_type))

        if geometry isa Ring
            bswap ? Base.bswap(write(io, UInt32(length(coordinate_list)+1))) : write(io, UInt32(length(coordinate_list)+1))
        else
            bswap ? Base.bswap(write(io, UInt32(length(coordinate_list)))) : write(io, UInt32(length(coordinate_list)))
        end

        _to_wkb_linestring(io, wkb_type, coordinate_list)

       if geometry isa Ring
           coordinates = CoordRefSystems.raw(coords( coordinate_list |> first ))
           _to_wkb_coordinates(io, wkb_type, coordinates)
       end

    elseif wkb_type == wkbPoint || wkb_type == wkbPointZ

        coordinates = CoordRefSystems.raw(coords(geometry::Point))
        _to_wkb_coordinates(io, wkb_type, coordinates)

    else
        @error "What is the $wkb_type ? not recognized; simple features only"
    end
end

function _to_wkb_coordinates(io, wkb_type, coords)


    bswap = @BSWAP(one(0x01))

    bswap ? Base.bswap(write(io, UInt32(wkb_type))) : write(io, UInt32(wkb_type))
    bswap ? Base.bswap(write(io, Float64(coords[1]))) : write(io, Float64(coords[1]))
    bswap ? Base.bswap(write(io, Float64(coords[2]))) : write(io, Float64(coords[2]))

    if wkb_has_z(wkb_type)
        write(io, Float64(coords[3]))
    end
end

function _to_wkb_linestring(io, wkb_type, coord_list)
    for n_coords::Point in coord_list
        coordinates = CoordRefSystems.raw(coords(n_coords))
        _to_wkb_coordinates(io, wkb_type, coordinates)
    end
end

function _to_wkb_polygon(io, wkb_type, rings)
    write(io, UInt32(wkb_type))
    write(io, UInt32(length(rings)))

    for ring in rings
        coord_list = vertices(ring)
        write(io, UInt32(length(coord_list) + 1))
        _to_wkb_linestring(io, wkb_type, coord_list)
    end
end
