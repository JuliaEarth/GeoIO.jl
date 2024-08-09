# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

module GeoIO

using Meshes
using Tables
using Colors
using Unitful
using GeoTables
using StaticArrays
using PrettyTables
using CoordRefSystems
using Meshes: SubDomain
using Format: generate_formatter
using TransformsBase: Identity, →
using Unitful: m

# image formats
import FileIO

# VTK formats
import ReadVTK
import WriteVTK
import VTKBase
import VTKBase.PolyData
import VTKBase.VTKCellTypes

# CDM formats
import CommonDataModel as CDM
import GRIBDatasets
import NCDatasets

# mesh formats
import PlyIO

# CSV format
import CSV

# geostats formats
import GslibIO

# GIS formats
import Shapefile as SHP
import GeoJSON as GJS
import ArchGDAL as AG
import GeoParquet as GPQ
import GeoInterface as GI
import GeoFormatTypes as GFT

# image extensions
const IMGEXTS = [".png", ".jpg", ".jpeg"]

# VTK extensions
const VTKEXTS = [".vtu", ".vtp", ".vtr", ".vts", ".vti"]

# Common Data Model extensions
const CDMEXTS = [".grib", ".nc"]

# GeoTiff extensions
const GEOTIFFEXTS = [".tif", ".tiff"]

# supported formats
const FORMATS = [
  (extension=".stl", load="GeoIO.jl", save="GeoIO.jl"),
  (extension=".obj", load="GeoIO.jl", save="GeoIO.jl"),
  (extension=".off", load="GeoIO.jl", save="GeoIO.jl"),
  (extension=".msh", load="GeoIO.jl", save="GeoIO.jl"),
  (extension=".ply", load="PlyIO.jl", save="PlyIO.jl"),
  (extension=".csv", load="CSV.jl", save="CSV.jl"),
  (extension=".vtu", load="ReadVTK.jl", save="WriteVTK.jl"),
  (extension=".vtp", load="ReadVTK.jl", save="WriteVTK.jl"),
  (extension=".vtr", load="ReadVTK.jl", save="WriteVTK.jl"),
  (extension=".vts", load="ReadVTK.jl", save="WriteVTK.jl"),
  (extension=".vti", load="ReadVTK.jl", save="WriteVTK.jl"),
  (extension=".grib", load="GRIBDatasets.jl", save=""),
  (extension=".nc", load="NCDatasets.jl", save="NCDatasets.jl"),
  (extension=".kml", load="ArchGDAL.jl", save=""),
  (extension=".gslib", load="GslibIO.jl", save="GslibIO.jl"),
  (extension=".shp", load="Shapefile.jl", save="Shapefile.jl"),
  (extension=".geojson", load="GeoJSON.jl", save="GeoJSON.jl"),
  (extension=".parquet", load="GeoParquet.jl", save="GeoParquet.jl"),
  (extension=".gpkg", load="ArchGDAL.jl", save="ArchGDAL.jl"),
  (extension=".png", load="ImageIO.jl", save="ImageIO.jl"),
  (extension=".jpg", load="ImageIO.jl", save="ImageIO.jl"),
  (extension=".jpeg", load="ImageIO.jl", save="ImageIO.jl"),
  (extension=".tif", load="ArchGDAL.jl", save="ArchGDAL.jl"),
  (extension=".tiff", load="ArchGDAL.jl", save="ArchGDAL.jl")
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
include("extra/vtkread.jl")
include("extra/vtkwrite.jl")
include("extra/stl.jl")
include("extra/obj.jl")
include("extra/off.jl")
include("extra/msh.jl")
include("extra/ply.jl")
include("extra/csv.jl")
include("extra/img.jl")
include("extra/cdm.jl")
include("extra/gdal.jl")
include("extra/geotiff.jl")

# user functions
include("load.jl")
include("save.jl")

# precompile popular formats
include("precompile.jl")

end
