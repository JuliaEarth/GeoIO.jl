using GeoIO
using Tables
using Meshes
using GeoTables
using Test, Random
using ReferenceTests
using Colors
using Dates
import ReadVTK
import GeoInterface as GI
import Shapefile as SHP
import ArchGDAL as AG
import GeoJSON as GJS

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

testfiles = ["formats.jl", "convert.jl", "load.jl", "save.jl", "gisconversion.jl", "noattrs.jl"]

@testset "GeoIO.jl" begin
  for testfile in testfiles
    println("Testing $testfile...")
    include(testfile)
  end
end
