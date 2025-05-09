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
import ArchGDAL as AG
import GeoJSON as GJS

using Unitful: cm

# environment settings
isCI = "CI" ∈ keys(ENV)
islinux = Sys.islinux()
datadir = joinpath(@__DIR__, "data")
savedir = mktempdir()

# Note: Shapefile.jl saves Chains and Polygons as Multi
# This function is used to work around this problem
_isequal(d1::Domain, d2::Domain) = all(_isequal(g1, g2) for (g1, g2) in zip(d1, d2))

_isequal(g1, g2) = g1 == g2
_isequal(m1::Multi, m2::Multi) = m1 == m2
_isequal(g, m::Multi) = _isequal(m, g)
function _isequal(m::Multi, g)
  gs = parent(m)
  length(gs) == 1 && first(gs) == g
end

testfiles = [
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

  # other tests
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
