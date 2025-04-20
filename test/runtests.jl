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
import ReadVTK
import JSON3
import GeoInterface as GI
import GeoFormatTypes as GFT
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
