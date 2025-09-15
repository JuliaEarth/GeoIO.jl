# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# According to https://www.geopackage.org/spec/#r2
# a GeoPackage should contain "GPKG" in ASCII in 
# "application_id" field of SQLite db header
const GPKG_APPLICATION_ID = Int(0x47504B47)
const GPKG_1_4_VERSION = 10400

include("gpkg/read.jl")
include("gpkg/write.jl")
