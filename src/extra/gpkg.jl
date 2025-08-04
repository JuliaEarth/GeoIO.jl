
# List of well known binary geometry types.
# These are used within the GeoPackageBinary SQL BLOBs
@enum wkbGeometryType::Int64 begin
    wkbUnknown = 0
    wkbPoint = 1
    wkbLineString = 2
    wkbPolygon = 3
    wkbMultiPoint = 4
    wkbMultiLineString = 5
    wkbMultiPolygon = 6
    wkbGeometryCollection = 7
    wkbCircularString = 8
    wkbCompoundCurve = 9
    wkbCurvePolygon = 10
    wkbMultiCurve = 11
    wkbMultiSurface = 12
    wkbCurve = 13
    wkbSurface = 14

    wkbNone = 100 # pure attribute records
    wkbLinearRing = 101

    # ISO SQL/MM Part 3: Spatial
    # Z-aware types
    wkbPointZ = 1001
    wkbLineStringZ = 1002
    wkbPolygonZ = 1003
    wkbMultiPointZ = 1004
    wkbMultiLineStringZ = 1005
    wkbMultiPolygonZ = 1006
    wkbGeometryCollectionZ = 1007
    wkbCircularStringZ = 1008
    wkbCompoundCurveZ = 1009
    wkbCurvePolygonZ = 1010
    wkbMultiCurveZ = 1011
    wkbMultiSurfaceZ = 1012
    wkbCurveZ = 1013
    wkbSurfaceZ = 1014

    # ISO SQL/MM Part 3.
    # M-aware types
    wkbPointM = 2001
    wkbLineStringM = 2002
    wkbPolygonM = 2003
    wkbMultiPointM = 2004
    wkbMultiLineStringM = 2005
    wkbMultiPolygonM = 2006
    wkbGeometryCollectionM = 2007
    wkbCircularStringM = 2008
    wkbCompoundCurveM = 2009
    wkbCurvePolygonM = 2010
    wkbMultiCurveM = 2011
    wkbMultiSurfaceM = 2012
    wkbCurveM = 2013
    wkbSurfaceM = 2014

    # ISO SQL/MM Part 3.
    # ZM-aware types ... Meshes.jl doesn't generally support this?
    wkbPointZM = 3001
    wkbLineStringZM = 3002
    wkbPolygonZM = 3003
    wkbMultiPointZM = 3004
    wkbMultiLineStringZM = 3005
    wkbMultiPolygonZM = 3006
    wkbGeometryCollectionZM = 3007
    wkbCircularStringZM = 3008
    wkbCompoundCurveZM = 3009
    wkbCurvePolygonZM = 3010
    wkbMultiCurveZM = 3011
    wkbMultiSurfaceZM = 3012
    wkbCurveZM = 3013
    wkbSurfaceZM = 3014

    # 2.5D extension as per 99-402
    # https://lists.osgeo.org/pipermail/postgis-devel/2004-December/000702.html
    wkbPoint25D = 0x80000001
    wkbLineString25D = 0x80000002
    wkbPolygon25D = 0x80000003
    wkbMultiPoint25D = 0x80000004
    wkbMultiLineString25D = 0x80000005
    wkbMultiPolygon25D = 0x80000006
    wkbGeometryCollection25D = 0x80000007
end

const wkbXDR = 0
const wkbNDR = 1

const wkb25DBit = 0x80000000

macro BSWAP(x)
    if ENDIAN_BOM == 0x01020304
        return :($(esc(x)) == wkbNDR)
    else
        return :($(esc(x)) == wkbXDR)
    end
end


# Requirement 1: first 16 bytes is null-terminated ASCII string "SQLite format 3"
const MAGIC_HEADER_STRING::Vector{UInt8} = UInt8[
    0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66,
    0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00
]

# 'GP' in ASCII
const MAGIC_GPKG_BINARY_STRING = UInt8[ 0x47, 0x50 ]

# Requirement 2: contains "GPKG" in ASCII in "application_id" field of SQLite db header
# Reminder: We have to set this (on-write) after there's some content
# so the database file is not zero length

const GP10_APPLICATION_ID = 74777363 #0x47503130
const GP11_APPLICATION_ID = 119643780 # 0x47503131
const GPKG_APPLICATION_ID = 1196444487 # 0x47504B47
const GPKG_1_2_VERSION = 10200
const GPKG_1_3_VERSION = 10300
const GPKG_1_4_VERSION = 10400


const CREATE_GPKG_GEOMETRY_COLUMNS =
    "CREATE TABLE gpkg_geometry_columns ("*
    "table_name TEXT NOT NULL,"*
    "column_name TEXT NOT NULL,"*
    "geometry_type_name TEXT NOT NULL,"*
    "srs_id INTEGER NOT NULL,"*
    "z TINYINT NOT NULL,"*
    "m TINYINT NOT NULL,"*
    "CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),"*
    "CONSTRAINT uk_gc_table_name UNIQUE (table_name),"*
    "CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES "*
    "gpkg_contents(table_name),"*
    "CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys "*
    "(srs_id)"*
    ")"

const CREATE_GPKG_REQUIRED_METADATA =  "CREATE TABLE gpkg_spatial_ref_sys ("*
                    "srs_name TEXT NOT NULL,"*
                    "srs_id INTEGER NOT NULL PRIMARY KEY,"*
                    "organization TEXT NOT NULL,"*
                    "organization_coordsys_id INTEGER NOT NULL,"*
                    "definition  TEXT NOT NULL,"*
                    "description TEXT,"*
                    "definition_12_063 TEXT NOT NULL,"*
                    "epoch DOUBLE"*
                ")"*
                ";"*
                "INSERT INTO gpkg_spatial_ref_sys ("*
                "srs_name, srs_id, organization, organization_coordsys_id, "*
                "definition, description, definition_12_063"*
                ") VALUE ("*

                "'WGS 84 geodetic', 4326, 'EPSG', 4326, '"*
                "GEOGCS[\"WGS 84\",DATUM[\"WGS_1984\",SPHEROID[\"WGS "*
                "84\",6378137,298.257223563,AUTHORITY[\"EPSG\",\"7030\"]],"*
                "AUTHORITY[\"EPSG\",\"6326\"]],PRIMEM[\"Greenwich\",0,AUTHORITY["*
                "\"EPSG\",\"8901\"]],UNIT[\"degree\",0.0174532925199433,AUTHORITY["*
                "\"EPSG\",\"9122\"]],AXIS[\"Latitude\",NORTH],AXIS[\"Longitude\","*
                "EAST],AUTHORITY[\"EPSG\",\"4326\"]]"*
                "', 'longitude/latitude coordinates in decimal degrees on the WGS "*
                "84 spheroid', "*

                "'GEODCRS[\"WGS 84\", DATUM[\"World Geodetic System 1984\", "*
                "ELLIPSOID[\"WGS 84\",6378137, 298.257223563, "*
                "LENGTHUNIT[\"metre\", 1.0]]], PRIMEM[\"Greenwich\", 0.0, "*
                "ANGLEUNIT[\"degree\",0.0174532925199433]], CS[ellipsoidal, "*
                "2], AXIS[\"latitude\", north, ORDER[1]], AXIS[\"longitude\", "*
                "east, ORDER[2]], ANGLEUNIT[\"degree\", 0.0174532925199433], "*
                "ID[\"EPSG\", 4326]]'"*
                ")"*
                ";"*
                "INSERT INTO gpkg_spatial_ref_sys ("*
                "srs_name, srs_id, organization, organization_coordsys_id, "*
                " definition, description, definition_12_063"*
                ") VALUES ("*
                "'Undefined Cartesian SRS', -1, 'NONE', -1, 'undefined', "*
                "'undefined Cartesian coordinate reference system', 'undefined'"*
                ")"*
                ";"*
                "INSERT INTO gpkg_spatial_ref_sys ("*
                "srs_name, srs_id, organization, organization_coordsys_id, "*
                "definition, description, definition_12_063"*
                ") VALUES ("*
                "'Undefined geographic SRS' 0, 'NONE', 0, 'undefined', "*
                "'undefined geographic coordinate reference system', 'undefined'"*
                ")"*
                ";"*
                "CREATE TABLE gpkg_contents ("*
                "table_name TEXT NOT NULL PRIMARY KEY,"*
                "data_type TEXT NOT NULL,"*
                "identifier TEXT UNIQUE,"*
                "description TEXT DEFAULT '',"*
                "last_change DATETIME NOT NULL DEFAULT "*
                "(strftime('%Y-%m-%dT%H:%M:%fZ','now')),"*
                "min_x DOUBLE, min_y DOUBLE,"*
                "max_x DOUBLE, max_y DOUBLE,"*
                "srs_id INTEGER,"*
                "CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES "*
                "gpkg_spatial_ref_sys(srs_id)"*
                ")"*
                ";"

function gpkgread(fname; kwargs... )
    # Requirement 3: File name has to end in ".gpkg"
    if !(endswith(fname,".gpkg")) @error "the file extension is not .gpkg'" end
    db_header_string = open(fname, "r") do  io
        read(io, 16)
    end
    if(db_header_string != MAGIC_HEADER_STRING)
        @error "missing magic header string"
    end

    db = SQLite.DB(fname)

    @timeit to "identify geopackage" begin
        gpkg_identify(db)
    end
    show(to)

    local mesh_geometry

    @timeit to "read geopackage" begin
        gpkg_attrs, mesh_geometry, geom_attrs = read_gpkg_tables(db)
    end
    show(to)
    SQLite.close(db)

    return GeoTables.georef(geom_attrs, mesh_geometry)
       # return GeoTables.georef(gpkg_attrs, [Point(NaN, NaN)])

end

function gpkgwrite(fname, geotable; )


    db = SQLite.DB(fname)

    @timeit to "write geopackage" begin

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



# -------------------------
# OPTIONAL METADATA TABLES
# -------------------------
            stmt_sql = SQLite.Stmt(db, CREATE_GPKG_REQUIRED_METADATA*CREATE_GPKG_GEOMETRY_COLUMNS )
            DBInterface.execute(stmt_sql)


            stmt_sql = SQLite.Stmt(db, "PRAGMA application_id = $GPKG_APPLICATION_ID ")
            DBInterface.execute(stmt_sql)
            stmt_sql = SQLite.Stmt(db, "PRAGMA user_version = $GPKG_1_4_VERSION ")
            DBInterface.execute(stmt_sql)

        end

        to_gpkg(db, geotable)
    end
    show(to)

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

# -----------------
# HELPER FUNCTIONS
# -----------------

const to = TimerOutput()





# Requirement 5: columns of tables are only declared using one of the GeoPackage data types
# Extended GeoPackages contain additional data types
#
# Requirement 5 Warning
# ⚠ data type mismatches could theoretically be checked for but tests would scale poorly ⚠
#
# GeoPackage writers SHOULD validate the data as it is being inserted
# GeoPackage readers SHOULD allow for the possibility that unexpected values are present.

function _julia_sqlite_datatype(gpkg_type::AbstractString, kwargs...)
    if startswith(gpkg_type, "INT")
        if(gpkg_type != "INT" && gpkg_type != "INTEGER")
            @warn "field format $gpkg_type not supported (interpreted as int)"
        end
        return Int64
    elseif gpkg_type == "BOOLEAN"
        return Bool
    elseif gpkg_type == "TINYINT"
        return Int8
    elseif gpkg_type == "SMALLINT"
        return Int16
    elseif gpkg_type == "MEDIUMINT"
        return Int32
    elseif gpkg_type == "FLOAT"
        return Float32
    elseif gpkg_type == "DOUBLE" || gpkg_type == "REAL"
        return Float64
    elseif gpkg_type == "TEXT"
        return String # UTF-8 or UTF-16, determined by PRAGMA encoding
    elseif gpkg_type == "BLOB"
        return Any
    elseif startswith(gpkg_type, "DATE")
        return Any
    else
        @warn "field format $gpkg_type not recognized, okay have a nice day"
        return Any
    end
end

# Requirement 20: GeoPackage SHALL store feature table geometries with the basic simple feature geometry types
# https://www.geopackage.org/spec140/index.html#geometry_types
function meshes_creategeometry(wkb_type, crs, C)
    if  wkb_type == wkbPoint || wkb_type == wkbPointZ

        return Meshes.Point(crs(C...))

    elseif wkb_type == wkbLineString || wkb_type == wkbLineStringZ

        return (C[1] == C[end]) ?
            Meshes.Ring([Meshes.Point(crs(coords...)) for coords in C[2:end]]...)  : Meshes.Rope([Meshes.Point(coords...) for coords in C]...)

    elseif wkb_type == wkbPolygon || wkb_type == wkbPolygonZ

        rings = map(C) do ring_coords
            coords = map(ring_coords) do svec
                Meshes.Point(crs(svec...))
            end
            Meshes.Ring(coords)
        end

        outer_ring = first(rings)
        holes = length(rings) > 1 ? rings[2:end] : Meshes.Ring[]
        return Meshes.PolyArea(outer_ring, holes...)

    else
        @error "what $wkb_type is this"
    end # @TODO: add support for non-linear geometry types
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

function _gpkg_crs_wkt_extension(db)
    stmt_sql = "SELECT extension_name FROM gpkg_extensions;"
    ext_name = DBInterface.execute(db, stmt_sql) |> first |> only
    return ext_name == "gpkg_crs_wkt"
end

function read_gpkg_tables(db)
    gpkg_table_info = SQLite.tableinfo(db, "gpkg_spatial_ref_sys")
    # @TODO: gpkg_contents tableinfo
    has_gpkg_extensions = _has_gpkg_optional_metadata_table(db)
    if (has_gpkg_extensions)
    end


    has_gpkg_attributes = _has_gpkg_attributes(db)
    has_vector_features = _has_gpkg_geometry_columns(db)
    if has_vector_features
        println("vector")
        gpkg_table_info = SQLite.tableinfo(db, "gpkg_geometry_columns")

        geometry = get_feature_table_geometry_columns(db)

        vector_features = get_feature_tables(db)
        feature_tables = get_feature_attributes(db, vector_features)

        if has_gpkg_attributes

            println("attributes")
            #gpkg_attributes = get_gpkg_attributes(db)

            #return gpkg_attributes, geometry, feature_tables
        end
        return nothing, geometry, feature_tables

    elseif has_gpkg_attributes
        println("attributes")
        gpkg_attributes = get_gpkg_attributes(db)
        return gpkg_attributes, nothing, nothing
    else
        @error "data_type not supported yet, looks for 'features' by default and falls back to 'attributes' "
    end
end


function _has_gpkg_geometry_columns(db)
     stmt_sql = "SELECT 1 from sqlite_master WHERE "*
               "name = 'gpkg_geometry_columns' AND "*
                "type IN ('table', 'view');"
    geometry_columns = DBInterface.execute(db, stmt_sql) |> collect
    return !isempty(geometry_columns)
end

# Requirement 58: optionally includes a gpkg_extensions table
function _has_gpkg_optional_metadata_table(db)
    stmt_sql=  "SELECT 1 FROM sqlite_master WHERE name = 'gpkg_extensions' "*
               "AND type IN ('table', 'view')"
    extensions = DBInterface.execute(db, stmt_sql) |> collect
    return !isempty(extensions)
end



# Requirement 118: gpkg_contents table SHALL contain
# a row with a data_type column value of "attributes"
# for each attributes data table or view.

function _has_gpkg_attributes(db)
    stmt_sql = "SELECT COUNT(*) FROM sqlite_master WHERE " *
               "name = 'gpkg_contents' AND " *
               "type IN ('table', 'view');"
    has_gpkg_contents_table = DBInterface.execute(db, stmt_sql) |> first |> only

    if has_gpkg_contents_table == 1
        stmt_sql_datatype = "SELECT COUNT(*) FROM gpkg_contents WHERE " *
                            "data_type = 'attributes';"
        has_attributes_datatype = DBInterface.execute(db, stmt_sql_datatype) |> first |> only
        return has_attributes_datatype > 0
    else
        return false
    end
end

#
#
# Requirement 119 & 151: GeoPackage MAY contain tables and views
# containing attributes and attribute sets
function get_gpkg_attributes(db)
    stmt_sql = "SELECT table_name as tn FROM gpkg_contents WHERE data_type = 'attributes'"
    attributes = DBInterface.execute(db, stmt_sql)
    gpkg_attrs = map(attributes) do sqlite_row
        tn = sqlite_row.tn
        DBInterface.execute(SQLite.Stmt(db, "SELECT * FROM $tn")) |> Tables.rows
    end
    attr_tables = map(gpkg_attrs) do row
        map(Tables.columnnames(row)) do col
            Tables.getcolumn(row, col)
        end
    end
    return attr_tables
end


# Requirement 21: a gpkg_contents table row with a "features" data_type
# SHALL contain a gpkg_geometry_columns table

function get_feature_tables(db)
    stmt_sql = "SELECT c.table_name, c.identifier, 1 as is_aspatial, "*
            "g.column_name, g.geometry_type_name, g.z, g.m, c.min_x, c.min_y, "*
            "c.max_x, c.max_y, 1 AS is_in_gpkg_contents, "*
            "(SELECT type FROM sqlite_master WHERE lower(name) = "*
            "lower(c.table_name) AND type IN ('table', 'view')) AS object_type "*
            "  FROM gpkg_geometry_columns g "*
            "  JOIN gpkg_contents c ON (g.table_name = c.table_name)"*
            "  WHERE "*
            "  c.data_type = 'features' "
    features = DBInterface.execute(db, stmt_sql)
    return features
end

# Third component of the SQL schema for vector features in a GeoPackage
function get_feature_attributes(db, features)

    attrs = map(features) do sqlite_row
        _select_aspatial_attributes(db, sqlite_row)
    end

    if isempty(attrs)
        return NamedTuple()
    end

    feature_attrs = reduce( (i, h) -> begin
                               jk = keys(i)
                               len_i = isempty(i) ? 0 : length(first(i))

                               kj = keys(h)
                               len_h = isempty(h) ? 0 : length(first(h))

                               all = unique(vcat(collect(jk), collect(kj)))

                               vals = map(all) do k
                                   newcol = Vector{Any}()

                                   if haskey(i, k)
                                       append!(newcol, i[k])
                                   else
                                       append!(newcol,  fill(nothing, len_i))
                                   end

                                   if haskey(h, k)
                                       append!(newcol, h[k])
                                   else
                                       append!(newcol,  fill(nothing, len_h))
                                   end

                                   return newcol
                               end
                               return NamedTuple{Tuple(all)}(vals)
                           end , attrs, init=NamedTuple())
    return feature_attrs
end

function _select_aspatial_attributes(db, row)
    tn = row.table_name
    table_info = SQLite.tableinfo(db, tn)
    ft_attrs = table_info.name

    # delete gpkg_geometry_columns column name, usually 'geom' or 'geometry'
    deleteat!(ft_attrs, findall(x -> x == row.column_name, ft_attrs))
    attrs_str = join(ft_attrs, ", ")
    stmt_sql = iszero(length(ft_attrs)) ? "" : "SELECT $attrs_str FROM $tn"
    attrs_result = iszero(length(stmt_sql)) ? false : DBInterface.execute(db, stmt_sql) |> Tables.columns
    columns, names = Tables.columns(attrs_result), Tables.columnnames(attrs_result)
    return NamedTuple{Tuple(names)}([
        Tables.getcolumn(columns, nm) for nm in names
    ])

end

# Requirement 25: The geometry_type_name value in a gpkg_geometry_columns row
# SHALL be one of the uppercase geometry type names specified

# Requirement 26: The srs_id value in a gpkg_geometry_columns table row
# SHALL be an srs_id column value from the gpkg_spatial_ref_sys table.
#
# Requirement 27: The z value in a gpkg_geometry_columns table row SHALL be one of 0, 1, or 2.
# Requirement 28: The m value in a gpkg_geometry_columns table row SHALL be one of 0, 1, or 2.
#
# Requirement 146: The srs_id value in a gpkg_geometry_columns table row
# SHALL match the srs_id column value from the corresponding row in the gpkg_contents table.
#
# Requirement 22: gpkg_geometry_columns table
# SHALL contain one row record for the geometry column
# in each vector feature data table
#
#Requirement 23: gpkg_geometry_columns table_name column
# SHALL reference values in the gpkg_contents table_name column
# for rows with a data_type of 'features'

# Amalgamation SQL execution, collecting matching vector feature tables
# and then parsing their geopackage binary format containg wkb geometries
function get_feature_table_geometry_columns(db)
    stmt_sql = "SELECT g.table_name AS tn, g.column_name AS cn, c.srs_id as crs, g.z as elev, " *
           "( SELECT type FROM sqlite_master WHERE lower(name) = lower(c.table_name) AND type IN ('table', 'view')) AS object_type " *
           "FROM gpkg_geometry_columns g " *
           "JOIN gpkg_contents c ON ( g.table_name = c.table_name ) " *
           "WHERE c.data_type = 'features' " *
           "AND (SELECT type FROM sqlite_master WHERE lower(name) = lower(c.table_name) AND type IN ('table', 'view')) IS NOT NULL "*
           #"AND g.srs_id IN (SELECT srs_id FROM gpkg_spatial_ref_sys ) "*
           "AND g.srs_id = c.srs_id "*
           "AND g.z IN (0, 1, 2) "*
           "AND g.m IN (0, 1, 2);"
    stmt_sql = SQLite.Stmt(db, stmt_sql)
    geoms = DBInterface.execute(stmt_sql)
    geom_specs = Set( (row.tn, Symbol(row.cn), row.crs, row.elev) for row in geoms )
    meshes = Geometry[]
    for (tn, cn, crs, elev) in geom_specs
        # Requirement 24: The column_name column value in a gpkg_geometry_columns row
        # SHALL be the name of a column in the table or view specified
        # by the table_name column value for that row.
        stmt_sql = "SELECT $cn FROM $tn"
        gpkg_binary = DBInterface.execute(db, stmt_sql)
        for blob in (b for b in gpkg_binary if !ismissing(getproperty(b, cn)))
            sql_blob = getproperty(blob, cn)
            # parsing only the necessary information from
            # GeoPackageBinary header, see _ function for more details
            srs_id, has_extent_z, checkpoint = _gpkg_header_from_WKB(sql_blob, length(sql_blob))
            # remaining bytes available after reading GeoPackage Binary header
            # read in the WKBGeometry one sql blob at a time
            io = IOBuffer(view(sql_blob, checkpoint:length(sql_blob)))
            # view() returns a lightweight array
            # that lazily references (or is effectively a view into) the parent array
            data = import_geometry_from_wkb(io, srs_id, has_extent_z)

            if isa(data, Vector{<:Geometry})
                for feature in data
                    push!(meshes, feature)
                end
            elseif !isnothing(data)
                push!(meshes, data)
            end
        end
    end
    return meshes
end

# Requirement 19: SHALL store feature table geometries
# with or without optional elevation (Z) and/or measure (M) values
# in SQL BLOBs using the Standard GeoPackageBinary format

function _gpkg_header_from_WKB(sqlblob, bloblen)

    if (bloblen < 8 || sqlblob[1:2] != MAGIC_GPKG_BINARY_STRING || sqlblob[3] != 0)
        @error "GeoPackageBinaryHeader missing format specifications in table"
    end
    io = IOBuffer(sqlblob)

    seek(io, 3)

    flagsbyte = read(io, UInt8)
    # empty geometry flag
    # bempty = (flagsbyte & (0x01 << 4)) >> 4

    # ⚠ ExtendedGeoPackageBinary was removed from the specification for interoperability concerns
    # It is intended to be a bridge to enable use of geometry types
    # like EllipiticalCurve in Extended GeoPackages until
    # standard encodings of such types are developed and
    # published for the Well Known Binary (WKB) format.
    # bextended = (flagsbyte & (0x01 << 5)) >> 5 # For user-defined geometry types

    ebyteorder = (flagsbyte & 0x01) # byte order
    # for SRS_ID and envelope values in header (1-bit Boolean)

    bextent_has_xy = false
    bextent_has_z = false
    bextent_has_m = false

    bswap = @BSWAP(ebyteorder)

    # Envelope: envelope contents indicator code (3-bit unsigned integer)
    envelope = (flagsbyte & ( 0x07 << 1 )) >> 1

    if envelope != 0 # no envelope (space saving slower indexing option), 0 bytes
        if isone(envelope)
            bextent_has_xy = true # envelope is [minx, maxx, miny, maxy], 32 bytes
        elseif envelope == 2 # envelope is [minx, maxx, miny, maxy, minz, maxz], 48 bytes
            bextent_has_z = true
        elseif envelope == 3 # envelope is [minx, maxx, miny, maxy, minm, maxm], 48 bytes
            bextent_has_m = true
        elseif envelope == 4 # envelope is [minx, maxx, miny, maxy, minz, maxz, minm, maxm], 64 bytes
            bextent_has_z = true
            bextent_has_m = true
        else
            @error "envelope geometry only exists in 2, 3 or 4-dimensional coordinate space."
        end
    end

    # SrsId #
    srsid = bswap ? Base.bswap(read(io, UInt32)) : read(io, UInt32)

    minx, miny, maxx, maxy = 0.0, 0.0, 0.0, 0.0 # x is easting or longitude, y is northing or latitude
    minz, minm, maxz, maxm = 0.0, 0.0, 0.0, 0.0 # z is optional elevation, m is optional measure
    # measure is included for interoperability with the Observations & Measurement Standard

    if bextent_has_xy
        minx = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)
        miny = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)
        maxx = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)
        maxy = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)
    end

    if bextent_has_z
        minz = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)
        maxz = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)
    end

    if bextent_has_m
        minm = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)
        maxm = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)
    end

    headerlen = position(io)

    return srsid, bextent_has_z, headerlen+1
end

function import_sf_from_wkb(io, srs_id, has_z, wkb_type, bswap)
    # this srs_id (specfied in geopackage binary) can
    srs_id = iszero(srs_id) || isone(abs(srs_id)) ?
    ( isone(abs(srs_id)) ? Cartesian{NoDatum} : LatLon{WGS84Latest} ) :
    ( Int(srs_id) > 54000 ? CoordRefSystems.get(ESRI{Int(srs_id)}) : CoordRefSystems.get(EPSG{Int(srs_id)}) )
# Conflicts that arose here and were ?resolved
# --------------------------------------------
# this conversion of Cartesian <--> Geographic works mostly
#
# Conversion error collecting 2D and 3D features in the same geotable
#
# Although I'm not so sure what the most correct way is for handling
# reading the undefined and/or cartographic/geographic reference systems
#


    if wkb_type == wkbPoint || wkb_type == wkbPointZ
        elem = _wkb_coordinate(io, has_z, bswap)
        return meshes_creategeometry(wkb_type, srs_id, elem)
    elseif wkb_type == wkbPolygon || wkb_type == wkbPolygonZ
        elem = _wkb_polygon(io, has_z, bswap)
        return meshes_creategeometry(wkb_type, srs_id, elem)
    elseif wkb_type == wkbLineString || wkb_type == wkbLineStringZ
        elem = _wkb_linestring(io, has_z, bswap)
        return meshes_creategeometry(wkb_type, srs_id, elem)
    else
        @warn("unknown type, non standard: $wkb_type, hit the road")
    end
end

function import_geometry_from_wkb(io, srs_id, has_z::Bool)
    ebyteorder = read(io, UInt8)
    bswap = @BSWAP(ebyteorder)

    v_wkb_type = bswap ? Base.bswap(read(io, UInt32)) : read(io, UInt32)
    local wkb_type
    try
        wkb_type::wkbGeometryType = wkbGeometryType(v_wkb_type)
    catch e
        @warn "wkbGeometrytype $v_wkb_type is not found in our list standard and non-standard types"
    end

    wkb_enum::AbstractString = string(wkb_type)
    if occursin("Multi", wkb_enum)
        melems::Vector = _wkb_geometrycollection(io, srs_id, has_z, bswap)
        return Meshes.Multi(melems)
    elseif wkb_type == wkbGeometryCollection || wkb_type == wkbGeometryCollectionZ
        elems::Vector{Geometry} = _wkb_geometrycollection(io, srs_id, has_z, bswap)
        return elems
    else
        return import_sf_from_wkb(io, srs_id, has_z, wkb_type, bswap)
    end
end




function _wkb_coordinate(io, has_z, bswap)

    x = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)
    y = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)

    if has_z
        z = bswap ? Base.bswap(read(io, Float64)) : read(io, Float64)
        return SVector{3, Float64}(x,y,z)
    end

    return SVector{2, Float64}(x,y)
end

# Unitful coordinate values address many pitfalls in geospatial applications



# a non-standard WKB representation,
# functionally equivalent to LineString but separate identity in GIS simple features data model
# It exists to serve as a component of a Polygon
function _wkb_linearring(io, has_z, bswap)

    num_points = bswap ? Base.bswap(read(io, UInt32)) : read(io, UInt32)

    points::Vector{SVector{has_z ? 3 : 2 , Float64}} = map(1:num_points) do _
        _wkb_coordinate(io, has_z, bswap)
    end

    return points
end

function _wkb_polygon(io, has_z, bswap)

    num_rings = bswap ? Base.bswap(read(io, UInt32)) :  read(io, UInt32)

    rings = map(1:num_rings) do _
        _wkb_linearring(io, has_z, bswap)
    end

    return rings
end

function _wkb_linestring(io, has_z, bswap)

    num_points = bswap ? Base.bswap(read(io, UInt32)) : read(io, UInt32)

    points::Vector{SVector{has_z ? 3 : 2 , Float64}} = map(1:num_points) do _
        _wkb_coordinate(io, has_z, bswap)
    end
    return points
end

function _wkb_geometrycollection(io, srs_id, has_z, bswap)

    num_geoms = bswap ? Base.bswap(read(io, UInt32)) :  read(io, UInt32)

    geomcollection = map(1:num_geoms) do _
        import_geometry_from_wkb(io, srs_id, has_z)
    end

    return geomcollection
end



#---------------------------
# SQLite Query Optimization
# --------------------------
#
# - Avoid OR-connected constraints, use IN operator, or UNION constraints separately
#
# - GROUP BY or DISTINCT logic can determine if the current row is part of the same group
#   or if the current row is distinct simply by comparing the current row to the previous row
#   - faster than the alternative of comparing each row to all prior rows
#
#.-
#
# --------------------------
