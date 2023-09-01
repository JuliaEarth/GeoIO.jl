# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

module GeoIO

using Meshes
using Tables

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

# GADM data
import GADM

# image extensions
const IMGEXT = (".png", ".jpg", ".jpeg", ".tif", ".tiff")

# conversions
include("conversion.jl")

# TODO: remove
include("geotable.jl")

# extra code for backends
include("extra/ply.jl")
include("extra/gdal.jl")

# user functions
include("load.jl")
include("save.jl")
include("gadm.jl")

# precompile popular formats
include("precompile.jl")

end
