UNKNOWN_SRID = -2
DEFAULT_SRID = 0

# Requirement 2: contains "GPKG" in ASCII in "application_id" field of SQLite db header
# Reminder: We have to set this (on-write) after there's some content
# so the database file is not zero length

const GP10_APPLICATION_ID::UInt32 = 0x47503130
const GP11_APPLICATION_ID::UInt32 = 0x47503131
const GPKG_APPLICATION_ID::UInt32= 0x47504B47
const GPKG_1_2_VERSION::UInt32= 10200
const GPKG_1_3_VERSION::UInt32= 10300
const GPKG_1_4_VERSION::UInt32= 10400


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
