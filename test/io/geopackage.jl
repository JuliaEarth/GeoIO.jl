@testset "GeoPackage" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "points.gpkg"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa PointSet
    @test gtb.geometry[1] isa Point

    gtb = GeoIO.load(joinpath(datadir, "lines.gpkg"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa Chain

    gtb = GeoIO.load(joinpath(datadir, "polygons.gpkg"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa PolyArea

    @test GeoIO.load(joinpath(datadir, "lines.gpkg")) isa AbstractGeoTable
  end

  @testset "save" begin
    file1 = joinpath(datadir, "points.gpkg")
    file2 = joinpath(savedir, "points.gpkg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "lines.gpkg")
    file2 = joinpath(savedir, "lines.gpkg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "polygons.gpkg")
    file2 = joinpath(savedir, "polygons.gpkg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)
  end
end
