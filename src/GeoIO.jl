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

# VTK formats
import ReadVTK
import VTKBase.VTKCellTypes

# GIS formats
import Shapefile as SHP
import GeoJSON as GJS
import ArchGDAL as AG
import GeoParquet as GPQ
import GeoInterface as GI

# image extensions
const IMGEXTS = [".png", ".jpg", ".jpeg", ".tif", ".tiff"]

# VTK extensions
const VTKEXTS = [".vtu", ".vtp", ".vtr"]

# supported formats
const FORMATS = [
  (extension=".ply", load="PlyIO.jl", save=""),
  (extension=".vtu", load="ReadVTK.jl", save=""),
  (extension=".vtp", load="ReadVTK.jl", save=""),
  (extension=".vtr", load="ReadVTK.jl", save=""),
  (extension=".kml", load="ArchGDAL.jl", save=""),
  (extension=".gslib", load="GslibIO.jl", save="GslibIO.jl"),
  (extension=".shp", load="Shapefile.jl", save="Shapefile.jl"),
  (extension=".geojson", load="GeoJSON.jl", save="GeoJSON.jl"),
  (extension=".parquet", load="GeoParquet.jl", save="GeoParquet.jl"),
  (extension=".gpkg", load="ArchGDAL.jl", save="ArchGDAL.jl"),
  (extension=".png", load="ImageIO.jl", save="ImageIO.jl"),
  (extension=".jgp", load="ImageIO.jl", save="ImageIO.jl"),
  (extension=".jpeg", load="ImageIO.jl", save="ImageIO.jl"),
  (extension=".tif", load="ImageIO.jl", save="ImageIO.jl"),
  (extension=".tiff", load="ImageIO.jl", save="ImageIO.jl")
]

"""
    formats([io]; sortby=:format)

Displays in `io` (defaults to `stdout` if `io` is not given) a table with 
all formats supported by GeoIO.jl and the packages used to load and save each of them. 

Optionally, sort the table by the `:extension`, `:load` or `:save` columns using the `sortby` argument.
"""
function formats(io::IO=stdout; sortby::Symbol=:extension)
  if sortby ∉ (:extension, :load, :save)
    throw(ArgumentError("`:$sortby` is not a valid column name, use one of these: `:extension`, `:load` or `:save`"))
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
include("extra/vtk.jl")

# user functions
include("load.jl")
include("save.jl")

# precompile popular formats
include("precompile.jl")

end
