@testset "KML" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "field.kml"))
    @test crs(gtb.geometry) <: LatLon
    @test length(gtb.geometry) == 4
    @test gtb.Name[1] isa String
    @test gtb.Description[1] isa String
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa PolyArea
  end
end
