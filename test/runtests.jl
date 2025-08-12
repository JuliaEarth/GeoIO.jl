using GeoIO
using Tables
using Meshes
using GeoTables
using CoordRefSystems
using Test, Random
using ReferenceTests
using FixedPointNumbers
using Colors
using Dates
using Unitful
using JSON3
using JSONSchema
import ReadVTK
import GeoInterface as GI
import Shapefile as SHP
import GeoJSON as GJS

using Unitful: cm

# environment settings
isCI = "CI" ∈ keys(ENV)
islinux = Sys.islinux()
datadir = joinpath(@__DIR__, "data")
savedir = mktempdir()

# test utilities
include("testutils.jl")

testfiles = [
  # CRS strings
  "crsstrings.jl",

  # geometry conversion
  "conversion.jl",

  # supported formats
  "formats.jl",

  # IO tests
  "io/csv.jl",
  "io/geojson.jl",
  "io/geopackage.jl",
  "io/geoparquet.jl",
  "io/geotiff.jl",
  "io/grib.jl",
  "io/gslib.jl",
  "io/images.jl",
  "io/kml.jl",
  "io/msh.jl",
  "io/netcdf.jl",
  "io/obj.jl",
  "io/off.jl",
  "io/ply.jl",
  "io/shapefile.jl",
  "io/stl.jl",
  "io/vtk.jl",

  # known issues with GIS formats
  "gisissues.jl",

  # geotables without values
  "novalues.jl"
]

@testset "GeoIO.jl" begin
  for testfile in testfiles
    println("Testing $testfile...")
    include(testfile)
  end
end
