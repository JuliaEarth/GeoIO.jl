# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

module GeoIO

using Meshes
using Tables
using GeoTables

# image formats
import FileIO

# mesh formats
import PlyIO

# geostats formats
import GslibIO

# GIS formats
import Shapefile as SHP
import GeoJSON as GJS
import ArchGDAL as AG
import GeoParquet as GPQ
import GeoInterface as GI

# image extensions
const IMGEXT = (".png", ".jpg", ".jpeg", ".tif", ".tiff")

include("utils.jl")

# conversions
include("conversion.jl")

# extra code for backends
include("extra/ply.jl")
include("extra/gdal.jl")

# user functions
include("load.jl")
include("save.jl")

# precompile popular formats
include("precompile.jl")

end
