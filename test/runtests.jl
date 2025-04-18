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
import JSON3
import ReadVTK
import GeoInterface as GI
import Shapefile as SHP
import ArchGDAL as AG
import GeoJSON as GJS

using Unitful: cm

# environment settings
isCI = "CI" ∈ keys(ENV)
islinux = Sys.islinux()
datadir = joinpath(@__DIR__, "data")
savedir = mktempdir()

include("testutils.jl")

testfiles = [
  "utils.jl",
  "io/images.jl",
  "io/stl.jl",
  "io/obj.jl",
  "io/off.jl",
  "io/msh.jl",
  "io/ply.jl",
  "io/csv.jl",
  "io/gslib.jl",
  "io/vtk.jl",
  "io/netcdf.jl",
  "io/grib.jl",
  "io/geotiff.jl",
  "io/shapefile.jl",
  "io/geojson.jl",
  "io/geopackage.jl",
  "io/geoparquet.jl",
  "io/kml.jl",
  "formats.jl",
  "convert.jl",
  "gis.jl",
  "noattrs.jl"
]

@testset "GeoIO.jl" begin
  for testfile in testfiles
    println("Testing $testfile...")
    include(testfile)
  end
end
