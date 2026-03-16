@testset "nlayers and multi-layer warning" begin
  @testset "nlayers" begin
    @test GeoIO.nlayers(joinpath(datadir, "points.geojson")) == 1
    @test GeoIO.nlayers(joinpath(datadir, "points.gpkg")) == 1
    @test GeoIO.nlayers(joinpath(datadir, "points.shp")) == 1
    @test GeoIO.nlayers(joinpath(datadir, "iterator.tif")) == 2
  end

  @testset "multi-layer warning" begin
    file = joinpath(datadir, "iterator.tif")
    gtb = @test_logs (:warn, r"layers") GeoIO.load(file)
    @test gtb isa AbstractGeoTable
    gtb = GeoIO.load(file; warn=false)
    @test gtb isa AbstractGeoTable
  end
end
