@testset "OBJ" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron.obj"))
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4

    # custom lenunit
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron.obj"), lenunit=cm)
    @test unit(Meshes.lentype(crs(gtb.geometry))) == cm
  end

  @testset "save" begin
    file1 = joinpath(datadir, "tetrahedron.obj")
    file2 = joinpath(savedir, "tetrahedron.obj")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    # error: OBJ format only supports 3D Ngon meshes
    gtb = GeoTable(CartesianGrid(2, 2, 2))
    file = joinpath(savedir, "error.obj")
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end
end
