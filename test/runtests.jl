using GeoIO
using Tables
using Meshes
using GeoTables
using Test, Random
using ReferenceTests
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

@testset "GeoIO.jl" begin
  @testset "formats" begin
    io = IOBuffer()
    exts = [".ply", ".kml", ".gslib", ".shp", ".geojson", ".parquet", ".gpkg", ".png", ".jpg", ".jpeg", ".tif", ".tiff"]

    GeoIO.formats(io)
    iostr = String(take!(io))
    @test all(occursin(iostr), exts)

    GeoIO.formats(io, sortby=:load)
    iostr = String(take!(io))
    @test all(occursin(iostr), exts)

    GeoIO.formats(io, sortby=:save)
    iostr = String(take!(io))
    @test all(occursin(iostr), exts)

    # throws
    @test_throws ArgumentError GeoIO.formats(sortby=:test)
  end

  @testset "convert" begin
    points = Point2[(0, 0), (2.2, 2.2), (0.5, 2)]
    outer = Point2[(0, 0), (2.2, 2.2), (0.5, 2), (0, 0)]

    # GI functions
    @test GI.ngeom(Segment(points[1], points[2])) == 2
    @test GI.ngeom(Rope(points)) == 3
    @test GI.ngeom(Ring(points)) == 4
    @test GI.ngeom(PolyArea(points)) == 1
    @test GI.ngeom(Multi(points)) == 3
    @test GI.ngeom(Multi([Rope(points), Rope(points)])) == 2
    @test GI.ngeom(Multi([PolyArea(points), PolyArea(points)])) == 2

    # Shapefile.jl
    ps = [SHP.Point(0, 0), SHP.Point(2.2, 2.2), SHP.Point(0.5, 2)]
    exterior = [SHP.Point(0, 0), SHP.Point(2.2, 2.2), SHP.Point(0.5, 2), SHP.Point(0, 0)]
    box = SHP.Rect(0.0, 0.0, 2.2, 2.2)
    point = SHP.Point(1.0, 1.0)
    chain = SHP.LineString{SHP.Point}(view(ps, 1:3))
    poly = SHP.SubPolygon([SHP.LinearRing{SHP.Point}(view(exterior, 1:4))])
    multipoint = SHP.MultiPoint(box, ps)
    multichain = SHP.Polyline(box, [0, 3], repeat(ps, 2))
    multipoly = SHP.Polygon(box, [0, 4], repeat(exterior, 2))
    @test GeoIO.geom2meshes(point) == Point(1.0, 1.0)
    @test GeoIO.geom2meshes(chain) == Rope(points)
    @test GeoIO.geom2meshes(poly) == PolyArea(points)
    @test GeoIO.geom2meshes(multipoint) == Multi(points)
    @test GeoIO.geom2meshes(multichain) == Multi([Rope(points), Rope(points)])
    @test GeoIO.geom2meshes(multipoly) == Multi([PolyArea(points), PolyArea(points)])
    # degenerate chain with 2 equal points
    ps = [SHP.Point(2.2, 2.2), SHP.Point(2.2, 2.2)]
    chain = SHP.LineString{SHP.Point}(view(ps, 1:2))
    @test GeoIO.geom2meshes(chain) == Ring((2.2, 2.2))

    # ArchGDAL.jl
    ps = [(0, 0), (2.2, 2.2), (0.5, 2)]
    outer = [(0, 0), (2.2, 2.2), (0.5, 2), (0, 0)]
    point = AG.createpoint(1.0, 1.0)
    chain = AG.createlinestring(ps)
    poly = AG.createpolygon(outer)
    multipoint = AG.createmultipoint(ps)
    multichain = AG.createmultilinestring([ps, ps])
    multipoly = AG.createmultipolygon([[outer], [outer]])
    polyarea = PolyArea(outer[begin:(end - 1)])
    @test GeoIO.geom2meshes(point) == Point(1.0, 1.0)
    @test GeoIO.geom2meshes(chain) == Rope(points)
    @test GeoIO.geom2meshes(poly) == polyarea
    @test GeoIO.geom2meshes(multipoint) == Multi(points)
    @test GeoIO.geom2meshes(multichain) == Multi([Rope(points), Rope(points)])
    @test GeoIO.geom2meshes(multipoly) == Multi([polyarea, polyarea])
    # degenerate chain with 2 equal points
    chain = AG.createlinestring([(2.2, 2.2), (2.2, 2.2)])
    @test GeoIO.geom2meshes(chain) == Ring((2.2, 2.2))

    # GeoJSON.jl
    points = Point2f[(0, 0), (2.2, 2.2), (0.5, 2)]
    outer = Point2f[(0, 0), (2.2, 2.2), (0.5, 2)]
    point = GJS.read("""{"type":"Point","coordinates":[1,1]}""")
    chain = GJS.read("""{"type":"LineString","coordinates":[[0,0],[2.2,2.2],[0.5,2]]}""")
    poly = GJS.read("""{"type":"Polygon","coordinates":[[[0,0],[2.2,2.2],[0.5,2],[0,0]]]}""")
    multipoint = GJS.read("""{"type":"MultiPoint","coordinates":[[0,0],[2.2,2.2],[0.5,2]]}""")
    multichain =
      GJS.read("""{"type":"MultiLineString","coordinates":[[[0,0],[2.2,2.2],[0.5,2]],[[0,0],[2.2,2.2],[0.5,2]]]}""")
    multipoly = GJS.read(
      """{"type":"MultiPolygon","coordinates":[[[[0,0],[2.2,2.2],[0.5,2],[0,0]]],[[[0,0],[2.2,2.2],[0.5,2],[0,0]]]]}"""
    )
    @test GeoIO.geom2meshes(point) == Point2f(1.0, 1.0)
    @test GeoIO.geom2meshes(chain) == Rope(points)
    @test GeoIO.geom2meshes(poly) == PolyArea(outer)
    @test GeoIO.geom2meshes(multipoint) == Multi(points)
    @test GeoIO.geom2meshes(multichain) == Multi([Rope(points), Rope(points)])
    @test GeoIO.geom2meshes(multipoly) == Multi([PolyArea(outer), PolyArea(outer)])
    # degenerate chain with 2 equal points
    chain = GJS.read("""{"type":"LineString","coordinates":[[2.2,2.2],[2.2,2.2]]}""")
    @test GeoIO.geom2meshes(chain) == Ring(Point2f(2.2, 2.2))
  end

  @testset "load" begin
    @testset "Images" begin
      table = GeoIO.load(joinpath(datadir, "image.jpg"))
      @test table.geometry isa CartesianGrid
      @test length(table.color) == length(table.geometry)
    end

    @testset "STL" begin
      gtb = GeoIO.load(joinpath(datadir, "tetrahedron_ascii.stl"))
      @test eltype(gtb.NORMAL) <: Vec3
      @test gtb.geometry isa SimpleMesh
      @test embeddim(gtb.geometry) == 3
      @test coordtype(gtb.geometry) <: Float64
      @test eltype(gtb.geometry) <: Triangle
      @test length(gtb.geometry) == 4

      gtb = GeoIO.load(joinpath(datadir, "tetrahedron_bin.stl"))
      @test eltype(gtb.NORMAL) <: Vec3f
      @test gtb.geometry isa SimpleMesh
      @test embeddim(gtb.geometry) == 3
      @test coordtype(gtb.geometry) <: Float32
      @test eltype(gtb.geometry) <: Triangle
      @test length(gtb.geometry) == 4
    end

    @testset "PLY" begin
      table = GeoIO.load(joinpath(datadir, "beethoven.ply"))
      @test table.geometry isa SimpleMesh
      @test isnothing(values(table, 0))
      @test isnothing(values(table, 1))
      @test isnothing(values(table, 2))
    end

    @testset "CSV" begin
      table = GeoIO.load(joinpath(datadir, "points.csv"), coords=["x", "y"])
      @test eltype(table.code) <: Integer
      @test eltype(table.name) <: AbstractString
      @test eltype(table.variable) <: Real
      @test table.geometry isa PointSet
      @test length(table.geometry) == 5
    end

    @testset "GSLIB" begin
      table = GeoIO.load(joinpath(datadir, "grid.gslib"))
      @test table.geometry isa CartesianGrid
      @test table."Porosity"[1] isa Float64
      @test table."Lithology"[1] isa Float64
      @test table."Water Saturation"[1] isa Float64
      @test isnan(table."Water Saturation"[end])
    end

    @testset "VTK" begin
      file = ReadVTK.get_example_file("celldata_appended_binary_compressed.vtu", output_directory=savedir)
      table = GeoIO.load(file)
      @test table.geometry isa SimpleMesh
      @test eltype(table.cell_ids) <: Int
      @test eltype(table.element_ids) <: Int
      @test eltype(table.levels) <: Int
      @test eltype(table.indicator_amr) <: Float64
      @test eltype(table.indicator_shock_capturing) <: Float64

      # the "spiral.vtp" file was generated from the ReadVTK.jl test code
      # link: https://github.com/JuliaVTK/ReadVTK.jl/blob/main/test/runtests.jl#L309
      file = joinpath(datadir, "spiral.vtp")
      table = GeoIO.load(file)
      @test table.geometry isa SimpleMesh
      @test eltype(table.h) <: Float64
      vtable = values(table, 0)
      @test eltype(vtable.theta) <: Float64

      # the "rectilinear.vtr" file was generated from the WriteVTR.jl test code
      # link: https://github.com/JuliaVTK/WriteVTK.jl/blob/master/test/rectilinear.jl
      file = joinpath(datadir, "rectilinear.vtr")
      table = GeoIO.load(file)
      @test table.geometry isa RectilinearGrid
      @test eltype(table.myCellData) <: Float32
      vtable = values(table, 0)
      @test eltype(vtable.p_values) <: Float32
      @test eltype(vtable.q_values) <: Float32
      @test size(eltype(vtable.myVector)) == (3,)
      @test eltype(eltype(vtable.myVector)) <: Float32
      @test size(eltype(vtable.tensor)) == (3, 3)
      @test eltype(eltype(vtable.tensor)) <: Float32

      # the "structured.vts" file was generated from the WriteVTR.jl test code
      # link: https://github.com/JuliaVTK/WriteVTK.jl/blob/master/test/structured.jl
      file = joinpath(datadir, "structured.vts")
      table = GeoIO.load(file)
      @test table.geometry isa StructuredGrid
      @test eltype(table.myCellData) <: Float32
      vtable = values(table, 0)
      @test eltype(vtable.p_values) <: Float32
      @test eltype(vtable.q_values) <: Float32
      @test size(eltype(vtable.myVector)) == (3,)
      @test eltype(eltype(vtable.myVector)) <: Float32

      # the "imagedata.vti" file was generated from the WriteVTR.jl test code
      # link: https://github.com/JuliaVTK/WriteVTK.jl/blob/master/test/imagedata.jl
      file = joinpath(datadir, "imagedata.vti")
      table = GeoIO.load(file)
      @test table.geometry isa CartesianGrid
      @test eltype(table.myCellData) <: Float32
      vtable = values(table, 0)
      @test size(eltype(vtable.myVector)) == (2,)
      @test eltype(eltype(vtable.myVector)) <: Float32
    end

    @testset "NetCDF" begin
      # the "test.nc" file is a slice of the "gistemp250_GHCNv4.nc" file from NASA
      # link: https://data.giss.nasa.gov/pub/gistemp/gistemp250_GHCNv4.nc.gz
      file = joinpath(datadir, "test.nc")
      table = GeoIO.load(file)
      @test table.geometry isa RectilinearGrid
      @test isnothing(values(table))
      vtable = values(table, 0)
      @test length(vtable.tempanomaly) == nvertices(table.geometry)
      @test length(first(vtable.tempanomaly)) == 100

      # the "test_kw.nc" file is a slice of the "gistemp250_GHCNv4.nc" file from NASA
      # link: https://data.giss.nasa.gov/pub/gistemp/gistemp250_GHCNv4.nc.gz
      file = joinpath(datadir, "test_kw.nc")
      table = GeoIO.load(file, x="lon_x", y="lat_y", t="time_t")
      @test table.geometry isa RectilinearGrid
      @test isnothing(values(table))
      vtable = values(table, 0)
      @test length(vtable.tempanomaly) == nvertices(table.geometry)
      @test length(first(vtable.tempanomaly)) == 100

      # timeless vertex data
      file = joinpath(datadir, "test_data.nc")
      table = GeoIO.load(file)
      @test table.geometry isa RectilinearGrid
      @test isnothing(values(table))
      vtable = values(table, 0)
      @test length(vtable.tempanomaly) == nvertices(table.geometry)
      @test length(first(vtable.tempanomaly)) == 100
      @test length(vtable.data) == nvertices(table.geometry)
      @test eltype(vtable.data) <: Float64
    end

    @testset "GRIB" begin
      # the "regular_gg_ml.grib" file is a test file from the GRIBDatasets.jl package
      # link: https://github.com/JuliaGeo/GRIBDatasets.jl/blob/main/test/sample-data/regular_gg_ml.grib
      file = joinpath(datadir, "regular_gg_ml.grib")
      if Sys.iswindows()
        @test_throws ErrorException GeoIO.load(file)
      else
        table = GeoIO.load(file)
        @test table.geometry isa RectilinearGrid
        @test isnothing(values(table))
        @test isnothing(values(table, 0))
      end
    end

    @testset "Shapefile" begin
      table = GeoIO.load(joinpath(datadir, "points.shp"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa PointSet
      @test table.geometry[1] isa Point

      table = GeoIO.load(joinpath(datadir, "lines.shp"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa Multi
      @test parent(table.geometry[1])[1] isa Chain

      table = GeoIO.load(joinpath(datadir, "polygons.shp"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa Multi
      @test parent(table.geometry[1])[1] isa PolyArea

      table = GeoIO.load(joinpath(datadir, "path.shp"))
      @test Tables.schema(table).names == (:ZONA, :geometry)
      @test length(table.geometry) == 6
      @test table.ZONA == ["PA 150", "BR 364", "BR 163", "BR 230", "BR 010", "Estuarina PA"]
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa Multi

      table = GeoIO.load(joinpath(datadir, "zone.shp"))
      @test Tables.schema(table).names == (:PERIMETER, :ACRES, :MACROZONA, :Hectares, :area_m2, :geometry)
      @test length(table.geometry) == 4
      @test table.PERIMETER == [5.850803650776888e6, 9.539471535859613e6, 1.01743436941e7, 7.096124186552936e6]
      @test table.ACRES == [3.23144676827e7, 2.50593712407e8, 2.75528426573e8, 1.61293042687e8]
      @test table.MACROZONA == ["Estuario", "Fronteiras Antigas", "Fronteiras Intermediarias", "Fronteiras Novas"]
      @test table.Hectares == [1.30772011078e7, 1.01411677447e8, 1.11502398263e8, 6.52729785685e7]
      @test table.area_m2 == [1.30772011078e11, 1.01411677447e12, 1.11502398263e12, 6.52729785685e11]
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa Multi

      table = GeoIO.load(joinpath(datadir, "land.shp"))
      @test Tables.schema(table).names == (:featurecla, :scalerank, :min_zoom, :geometry)
      @test length(table.geometry) == 127
      @test all(==("Land"), table.featurecla)
      @test all(∈([0, 1]), table.scalerank)
      @test all(∈([0.0, 0.5, 1.0, 1.5]), table.min_zoom)
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa Multi

      # https://github.com/JuliaEarth/GeoIO.jl/issues/32
      @test GeoIO.load(joinpath(datadir, "issue32.shp")) isa AbstractGeoTable
      @test GeoIO.load(joinpath(datadir, "lines.shp")) isa AbstractGeoTable
    end

    @testset "GeoJSON" begin
      table = GeoIO.load(joinpath(datadir, "points.geojson"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa PointSet
      @test table.geometry[1] isa Point

      table = GeoIO.load(joinpath(datadir, "lines.geojson"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa Chain

      table = GeoIO.load(joinpath(datadir, "polygons.geojson"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa PolyArea

      @test GeoIO.load(joinpath(datadir, "lines.geojson")) isa AbstractGeoTable
    end

    @testset "KML" begin
      table = GeoIO.load(joinpath(datadir, "field.kml"))
      @test length(table.geometry) == 4
      @test table.Name[1] isa String
      @test table.Description[1] isa String
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa PolyArea
    end

    @testset "GeoPackage" begin
      table = GeoIO.load(joinpath(datadir, "points.gpkg"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa PointSet
      @test table.geometry[1] isa Point

      table = GeoIO.load(joinpath(datadir, "lines.gpkg"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa Chain

      table = GeoIO.load(joinpath(datadir, "polygons.gpkg"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa PolyArea

      @test GeoIO.load(joinpath(datadir, "lines.gpkg")) isa AbstractGeoTable
    end

    @testset "GeoParquet" begin
      table = GeoIO.load(joinpath(datadir, "points.parquet"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa PointSet
      @test table.geometry[1] isa Point

      table = GeoIO.load(joinpath(datadir, "lines.parquet"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa Chain

      table = GeoIO.load(joinpath(datadir, "polygons.parquet"))
      @test length(table.geometry) == 5
      @test table.code[1] isa Integer
      @test table.name[1] isa String
      @test table.variable[1] isa Real
      @test table.geometry isa GeometrySet
      @test table.geometry[1] isa PolyArea

      @test GeoIO.load(joinpath(datadir, "lines.parquet")) isa AbstractGeoTable
    end
  end

  @testset "save" begin
    @testset "Images" begin
      fname = "image.jpg"
      img1 = joinpath(datadir, fname)
      img2 = joinpath(savedir, fname)
      gtb1 = GeoIO.load(img1)
      GeoIO.save(img2, gtb1)
      gtb2 = GeoIO.load(img2)
      @test gtb1.geometry == gtb2.geometry
      @test psnr_equality()(gtb1.color, gtb2.color)
    end

    @testset "STL" begin
      # STL ASCII
      file1 = joinpath(datadir, "tetrahedron_ascii.stl")
      file2 = joinpath(savedir, "tetrahedron_ascii.stl")
      gtb1 = GeoIO.load(file1)
      GeoIO.save(file2, gtb1, ascii=true)
      gtb2 = GeoIO.load(file2)
      @test gtb1 == gtb2
      @test values(gtb1, 0) == values(gtb2, 0)

      # STL Binary
      file1 = joinpath(datadir, "tetrahedron_bin.stl")
      file2 = joinpath(savedir, "tetrahedron_bin.stl")
      gtb1 = GeoIO.load(file1)
      GeoIO.save(file2, gtb1)
      gtb2 = GeoIO.load(file2)
      @test gtb1 == gtb2
      @test values(gtb1, 0) == values(gtb2, 0)

      # STL Binary: conversion to Float32
      file1 = joinpath(datadir, "tetrahedron_ascii.stl")
      file2 = joinpath(savedir, "tetrahedron_converted.stl")
      gtb1 = GeoIO.load(file1)
      GeoIO.save(file2, gtb1)
      gtb2 = GeoIO.load(file2)
      @test coordtype(gtb1.geometry) <: Float64
      @test coordtype(gtb2.geometry) <: Float32

      # error: STL format only supports 3D triangle meshes
      gtb = GeoTable(CartesianGrid(2, 2, 2))
      file = joinpath(savedir, "error.stl")
      @test_throws ArgumentError GeoIO.save(file, gtb)
    end

    @testset "PLY" begin
      file1 = joinpath(datadir, "beethoven.ply")
      file2 = joinpath(savedir, "beethoven.ply")
      table1 = GeoIO.load(file1)
      GeoIO.save(file2, table1)
      table2 = GeoIO.load(file2)
      @test table1 == table2
      @test values(table1, 0) == values(table2, 0)
    end

    @testset "CSV" begin
      file1 = joinpath(datadir, "points.csv")
      file2 = joinpath(savedir, "points.csv")
      gtb1 = GeoIO.load(file1, coords=[:x, :y])
      GeoIO.save(file2, gtb1, coords=["x", "y"])
      gtb2 = GeoIO.load(file2, coords=[:x, :y])
      @test gtb1 == gtb2
      @test values(gtb1, 0) == values(gtb2, 0)

      grid = CartesianGrid(2, 2, 2)
      gtb1 = georef((; a=rand(8)), grid)
      file = joinpath(savedir, "grid.csv")
      GeoIO.save(file, gtb1)
      gtb2 = GeoIO.load(file, coords=[:x, :y, :z])
      @test gtb1.a == gtb2.a
      @test nelements(gtb1.geometry) == nelements(gtb2.geometry)
      @test collect(gtb2.geometry) == centroid.(gtb1.geometry)

      # make coordinate names unique
      pset = PointSet(rand(Point2, 10))
      gtb1 = georef((x=rand(10), y=rand(10)), pset)
      file = joinpath(savedir, "pset.csv")
      GeoIO.save(file, gtb1)
      gtb2 = GeoIO.load(file, coords=[:x_, :y_])
      @test propertynames(gtb1) == propertynames(gtb2)
      @test gtb1.x == gtb2.x
      @test gtb1.y == gtb2.y
      @test gtb1.geometry == gtb2.geometry

      # float format
      x = [0.6895, 0.9878, 0.3654, 0.1813, 0.9138, 0.7121]
      y = [0.3925, 0.4446, 0.6582, 0.3511, 0.1831, 0.8398]
      a = [0.1409, 0.7653, 0.4576, 0.8148, 0.5576, 0.7857]
      pset = PointSet(Point.(x, y))
      gtb1 = georef((; a), pset)
      file = joinpath(savedir, "pset2.csv")
      GeoIO.save(file, gtb1, floatformat="%.2f")
      gtb2 = GeoIO.load(file, coords=[:x, :y])
      xf = [0.69, 0.99, 0.37, 0.18, 0.91, 0.71]
      yf = [0.39, 0.44, 0.66, 0.35, 0.18, 0.84]
      af = [0.14, 0.77, 0.46, 0.81, 0.56, 0.79]
      @test gtb2.a == af
      @test gtb2.geometry == PointSet(Point.(xf, yf))

      # throw: invalid number of coordinate names
      file = joinpath(savedir, "throw.csv")
      gtb = georef((; a=rand(10)), rand(Point2, 10))
      @test_throws ArgumentError GeoIO.save(file, gtb, coords=["x", "y", "z"])
      # throw: geometries with more than 3 dimensions
      gtb = georef((; a=rand(10)), rand(Point{4,Float64}, 10))
      @test_throws ArgumentError GeoIO.save(file, gtb)
    end

    @testset "VTK" begin
      file1 = ReadVTK.get_example_file("celldata_appended_binary_compressed.vtu", output_directory=savedir)
      file2 = joinpath(savedir, "unstructured.vtu")
      table1 = GeoIO.load(file1)
      GeoIO.save(file2, table1)
      table2 = GeoIO.load(file2)
      @test table1 == table2
      @test values(table1, 0) == values(table2, 0)

      file1 = joinpath(datadir, "spiral.vtp")
      file2 = joinpath(savedir, "spiral.vtp")
      table1 = GeoIO.load(file1)
      GeoIO.save(file2, table1)
      table2 = GeoIO.load(file2)
      @test table1 == table2
      @test values(table1, 0) == values(table2, 0)

      file1 = joinpath(datadir, "rectilinear.vtr")
      file2 = joinpath(savedir, "rectilinear.vtr")
      table1 = GeoIO.load(file1)
      GeoIO.save(file2, table1)
      table2 = GeoIO.load(file2)
      @test table1 == table2
      @test values(table1, 0) == values(table2, 0)

      file1 = joinpath(datadir, "structured.vts")
      file2 = joinpath(savedir, "structured.vts")
      table1 = GeoIO.load(file1)
      GeoIO.save(file2, table1)
      table2 = GeoIO.load(file2)
      @test table1 == table2
      @test values(table1, 0) == values(table2, 0)

      file1 = joinpath(datadir, "imagedata.vti")
      file2 = joinpath(savedir, "imagedata.vti")
      table1 = GeoIO.load(file1)
      GeoIO.save(file2, table1)
      table2 = GeoIO.load(file2)
      @test table1 == table2
      @test values(table1, 0) == values(table2, 0)

      # save cartesian grid in vtr file
      file = joinpath(savedir, "cartesian.vtr")
      table1 = georef((; a=rand(100)), CartesianGrid(10, 10))
      GeoIO.save(file, table1)
      table2 = GeoIO.load(file)
      @test table2.geometry isa RectilinearGrid
      @test nvertices(table2.geometry) == nvertices(table1.geometry)
      @test vertices(table2.geometry) == vertices(table1.geometry)
      @test values(table2) == values(table1)

      # save cartesian grid in vts file
      file = joinpath(savedir, "cartesian.vts")
      table1 = georef((; a=rand(100)), CartesianGrid(10, 10))
      GeoIO.save(file, table1)
      table2 = GeoIO.load(file)
      @test table2.geometry isa StructuredGrid
      @test nvertices(table2.geometry) == nvertices(table1.geometry)
      @test vertices(table2.geometry) == vertices(table1.geometry)
      @test values(table2) == values(table1)

      # save rectilinear grid in vts file
      file = joinpath(savedir, "rectilinear.vts")
      table1 = georef((; a=rand(100)), RectilinearGrid(0:10, 0:10))
      GeoIO.save(file, table1)
      table2 = GeoIO.load(file)
      @test table2.geometry isa StructuredGrid
      @test nvertices(table2.geometry) == nvertices(table1.geometry)
      @test vertices(table2.geometry) == vertices(table1.geometry)
      @test values(table2) == values(table1)

      # save views
      grid = CartesianGrid(10, 10)
      mesh = convert(SimpleMesh, grid)
      rgrid = convert(RectilinearGrid, grid)
      sgrid = convert(StructuredGrid, grid)
      etable = (; a=rand(100))

      gtb = georef(etable, mesh)
      file = joinpath(savedir, "unstructured_view.vtu")
      GeoIO.save(file, view(gtb, 1:25))
      vgtb = GeoIO.load(file)
      @test vgtb.a == view(gtb.a, 1:25)
      @test parent(vgtb.geometry) isa SimpleMesh
      @test vgtb.geometry == view(gtb.geometry, 1:25)

      gtb = georef(etable, mesh)
      file = joinpath(savedir, "polydata_view.vtp")
      GeoIO.save(file, view(gtb, 1:25))
      vgtb = GeoIO.load(file)
      @test vgtb.a == view(gtb.a, 1:25)
      @test parent(vgtb.geometry) isa SimpleMesh
      @test vgtb.geometry == view(gtb.geometry, 1:25)

      gtb = georef(etable, rgrid)
      file = joinpath(savedir, "rectilinear_view.vtr")
      GeoIO.save(file, view(gtb, 1:25))
      vgtb = GeoIO.load(file)
      @test vgtb.a == view(gtb.a, 1:25)
      @test parent(vgtb.geometry) isa RectilinearGrid
      @test vgtb.geometry == view(gtb.geometry, 1:25)

      gtb = georef(etable, sgrid)
      file = joinpath(savedir, "structured_view.vts")
      GeoIO.save(file, view(gtb, 1:25))
      vgtb = GeoIO.load(file)
      @test vgtb.a == view(gtb.a, 1:25)
      @test parent(vgtb.geometry) isa StructuredGrid
      @test vgtb.geometry == view(gtb.geometry, 1:25)

      gtb = georef(etable, grid)
      file = joinpath(savedir, "imagedata_view.vti")
      GeoIO.save(file, view(gtb, 1:25))
      vgtb = GeoIO.load(file)
      @test vgtb.a == view(gtb.a, 1:25)
      @test parent(vgtb.geometry) isa CartesianGrid
      @test vgtb.geometry == view(gtb.geometry, 1:25)

      # mask column with different name
      gtb = georef((; MASK=rand(100)), grid)
      file = joinpath(savedir, "imagedata_view.vti")
      GeoIO.save(file, view(gtb, 1:25))
      vgtb = GeoIO.load(file, mask=:MASK_)
      @test vgtb == GeoIO.load(file, mask="MASK_") # mask as string
      @test vgtb.MASK == view(gtb.MASK, 1:25)
      @test parent(vgtb.geometry) isa CartesianGrid
      @test vgtb.geometry == view(gtb.geometry, 1:25)

      # throw: the vtr format does not support structured grids
      table = GeoIO.load(joinpath(datadir, "structured.vts"))
      @test_throws ErrorException GeoIO.save(joinpath(savedir, "structured.vtr"), table)
    end

    @testset "NetCDF" begin
      file1 = joinpath(datadir, "test.nc")
      file2 = joinpath(savedir, "test.nc")
      gtb1 = GeoIO.load(file1)
      GeoIO.save(file2, gtb1)
      gtb2 = GeoIO.load(file2)
      @test gtb1 == gtb2
      @test isequal(values(gtb1, 0).tempanomaly, values(gtb2, 0).tempanomaly)

      # grids
      grid = CartesianGrid(10, 10)
      rgrid = convert(RectilinearGrid, grid)

      file = joinpath(savedir, "cartesian.nc")
      gtb1 = GeoTable(grid)
      GeoIO.save(file, gtb1)
      gtb2 = GeoIO.load(file)
      @test gtb2.geometry isa RectilinearGrid
      @test gtb2.geometry == rgrid

      file = joinpath(savedir, "rectilinear.nc")
      gtb1 = GeoTable(rgrid)
      GeoIO.save(file, gtb1)
      gtb2 = GeoIO.load(file)
      @test gtb2.geometry isa RectilinearGrid
      @test gtb2.geometry == rgrid

      # error: domain is not a grid
      file = joinpath(savedir, "error.nc")
      gtb = georef((; a=rand(10)), rand(Point2, 10))
      @test_throws ArgumentError GeoIO.save(file, gtb)
    end

    @testset "GRIB" begin
      # error: saving GRIB files is not supported
      file = joinpath(savedir, "error.grib")
      gtb = georef((; a=rand(4)), CartesianGrid(2, 2))
      @test_throws ErrorException GeoIO.save(file, gtb)
    end
  end

  @testset "GIS conversion" begin
    fnames = [
      "points.geojson",
      "points.gpkg",
      "points.shp",
      "lines.geojson",
      "lines.gpkg",
      "lines.shp",
      "polygons.geojson",
      "polygons.gpkg",
      "polygons.shp",
      "land.shp",
      "path.shp",
      "zone.shp",
      "issue32.shp"
    ]

    # saved and loaded tables are the same
    for fname in fnames, fmt in [".shp", ".geojson", ".gpkg"]
      # input and output file names
      f1 = joinpath(datadir, fname)
      f2 = joinpath(savedir, replace(fname, "." => "-") * fmt)

      # load and save table
      kwargs = endswith(f1, ".geojson") ? (; numbertype=Float64) : ()
      gt1 = GeoIO.load(f1; fix=false, kwargs...)
      GeoIO.save(f2, gt1)
      kwargs = endswith(f2, ".geojson") ? (; numbertype=Float64) : ()
      gt2 = GeoIO.load(f2; fix=false, kwargs...)

      # compare domain and values
      d1 = domain(gt1)
      d2 = domain(gt2)
      @test _isequal(d1, d2)
      t1 = values(gt1)
      t2 = values(gt2)
      c1 = Tables.columns(t1)
      c2 = Tables.columns(t2)
      n1 = Tables.columnnames(c1)
      n2 = Tables.columnnames(c2)
      @test Set(n1) == Set(n2)
      for n in n1
        x1 = Tables.getcolumn(c1, n)
        x2 = Tables.getcolumn(c2, n)
        @test x1 == x2
      end
    end
  end
end
