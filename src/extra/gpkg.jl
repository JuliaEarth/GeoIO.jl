# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# Shared WKB type constants
const WKB_POINT = 0x00000001
const WKB_LINESTRING = 0x00000002
const WKB_POLYGON = 0x00000003
const WKB_MULTIPOINT = 0x00000004
const WKB_MULTILINESTRING = 0x00000005
const WKB_MULTIPOLYGON = 0x00000006

const WKB_Z = 0x80000000
const WKB_M = 0x40000000
const WKB_ZM = 0xC0000000

include("gpkg/read.jl")
include("gpkg/write.jl")