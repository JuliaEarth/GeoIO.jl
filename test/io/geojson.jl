@testset "GeoJSON" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "points.geojson"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa PointSet
    @test gtb.geometry[1] isa Point

    gtb = GeoIO.load(joinpath(datadir, "lines.geojson"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa Chain

    gtb = GeoIO.load(joinpath(datadir, "polygons.geojson"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa PolyArea

    @test GeoIO.load(joinpath(datadir, "lines.geojson")) isa AbstractGeoTable
  end

  @testset "save" begin
    file1 = joinpath(datadir, "points.geojson")
    file2 = joinpath(savedir, "points.geojson")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "lines.geojson")
    file2 = joinpath(savedir, "lines.geojson")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "polygons.geojson")
    file2 = joinpath(savedir, "polygons.geojson")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)
  end
end
