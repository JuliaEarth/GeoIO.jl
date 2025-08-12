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

# GeoTIFF format
import GeoTIFF

# GIS formats
import Shapefile as SHP
import GeoJSON as GJS
import GeoParquet as GPQ
import GeoInterface as GI
import GeoFormatTypes as GFT

# SQLite Database Interface
import SQLite

# PROJJSON CRS
import JSON3

# VTK extensions
const VTKEXTS = [".vtu", ".vtp", ".vtr", ".vts", ".vti"]

# image extensions
const IMGEXTS = [".png", ".jpg", ".jpeg"]

# GeoTiff extensions
const GEOTIFFEXTS = [".tif", ".tiff"]

# CDM extensions
const CDMEXTS = [".grib", ".nc"]

# supported formats
const FORMATS = [
  (extension=".csv", load="CSV.jl", save="CSV.jl"),
  (extension=".geojson", load="GeoJSON.jl", save="GeoJSON.jl"),
  (extension=".gpkg", load="GeoIO.jl", save="GeoIO.jl"),
  (extension=".grib", load="GRIBDatasets.jl", save=""),
  (extension=".gslib", load="GslibIO.jl", save="GslibIO.jl"),
  (extension=".jpeg", load="ImageIO.jl", save="ImageIO.jl"),
  (extension=".jpg", load="ImageIO.jl", save="ImageIO.jl"),
 # (extension=".kml", load="GeoIO.jl", save="GeoIO.jl"),
  (extension=".msh", load="GeoIO.jl", save="GeoIO.jl"),
  (extension=".nc", load="NCDatasets.jl", save="NCDatasets.jl"),
  (extension=".obj", load="GeoIO.jl", save="GeoIO.jl"),
  (extension=".off", load="GeoIO.jl", save="GeoIO.jl"),
  (extension=".parquet", load="GeoParquet.jl", save="GeoParquet.jl"),
  (extension=".ply", load="PlyIO.jl", save="PlyIO.jl"),
  (extension=".png", load="ImageIO.jl", save="ImageIO.jl"),
  (extension=".shp", load="Shapefile.jl", save="Shapefile.jl"),
  (extension=".stl", load="GeoIO.jl", save="GeoIO.jl"),
  (extension=".tif", load="GeoTIFF.jl", save="GeoTIFF.jl"),
  (extension=".tiff", load="GeoTIFF.jl", save="GeoTIFF.jl"),
  (extension=".vti", load="ReadVTK.jl", save="WriteVTK.jl"),
  (extension=".vtp", load="ReadVTK.jl", save="WriteVTK.jl"),
  (extension=".vtr", load="ReadVTK.jl", save="WriteVTK.jl"),
  (extension=".vts", load="ReadVTK.jl", save="WriteVTK.jl"),
  (extension=".vtu", load="ReadVTK.jl", save="WriteVTK.jl")
]

"""
    formats([io]; sortby=:extension)

Displays in `io` (defaults to `stdout` if `io` is not given) a table with 
all formats supported by GeoIO.jl and the packages used to load and save each of them. 

Optionally, sort the table by the `:extension`, `:load` or `:save` columns using the `sortby` argument.
"""
function formats(io=stdout; sortby=:extension)
  if sortby ∉ (:extension, :load, :save)
    throw(ArgumentError("invalid `sortby` value, use one of `:extension`, `:load` or `:save`"))
  end
  sorted = sort(FORMATS, by=(row -> row[sortby]))
  pretty_table(io, sorted, alignment=:c, crop=:none, show_subheader=false)
end

# basic utilities
include("utils.jl")

# utilities for CRS strings
include("crsstrings.jl")

# utilities for geometry conversion
include("conversion.jl")

# extra code for backends
include("extra/cdm.jl")
include("extra/csv.jl")
include("extra/gpkg.jl")
include("extra/geotiff.jl")
include("extra/gis.jl")
include("extra/img.jl")
include("extra/msh.jl")
include("extra/obj.jl")
include("extra/off.jl")
include("extra/ply.jl")
include("extra/stl.jl")
include("extra/vtk.jl")

# user functions
include("load.jl")
include("save.jl")

# precompile popular formats
include("precompile.jl")

end
