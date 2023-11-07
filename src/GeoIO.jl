# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

module GeoIO

using Meshes
using Tables
using GeoTables
using PrettyTables

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

# supported formats
const FORMATS = [
  (format=".ply", load="PlyIO.jl", save=""),
  (format=".kml", load="ArchGDAL.jl", save=""),
  (format=".gslib", load="GslibIO.jl", save="GslibIO.jl"),
  (format=".shp", load="Shapefile.jl", save="Shapefile.jl"),
  (format=".geojson", load="GeoJSON.jl", save="GeoJSON.jl"),
  (format=".parquet", load="GeoParquet.jl", save="GeoParquet.jl"),
  (format=".gpkg", load="ArchGDAL.jl", save="ArchGDAL.jl"),
  (format=".png", load="ImageIO.jl", save="ImageIO.jl"),
  (format=".jgp", load="ImageIO.jl", save="ImageIO.jl"),
  (format=".jpeg", load="ImageIO.jl", save="ImageIO.jl"),
  (format=".tif", load="ImageIO.jl", save="ImageIO.jl"),
  (format=".tiff", load="ImageIO.jl", save="ImageIO.jl")
]

"""
    formats([io]; sortby=:format)

Displays in `io` (defaults to `stdout` if `io` is not given) a table with 
all formats supported by GeoIO.jl and the packages used to load and save each of them. 

Optionally, sort the table by the `:format`, `:load` or `:save` columns using the `sortby` argument.
"""
function formats(io::IO=stdout; sortby::Symbol=:format)
  if sortby ∉ (:format, :load, :save)
    throw(ArgumentError("`:$sortby` is not a valid column name, use one of these: `:format`, `:load` or `:save`"))
  end
  sorted = sort(FORMATS, by=(row -> row[sortby]))
  pretty_table(io, sorted, alignment=:c, crop=:none, show_subheader=false)
end

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
