@testset "OFF" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron.off"))
    @test eltype(gtb.COLOR) <: RGBA{Float64}
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float64}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4

    # custom lenunit
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron.off"), lenunit=cm)
    @test unit(Meshes.lentype(crs(gtb.geometry))) == cm
  end

  @testset "save" begin
    file1 = joinpath(datadir, "tetrahedron.off")
    file2 = joinpath(savedir, "tetrahedron.off")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1, color=:COLOR)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    # error: OFF format only supports 3D Ngon meshes
    gtb = GeoTable(CartesianGrid(2, 2, 2))
    file = joinpath(savedir, "error.off")
    @test_throws ArgumentError GeoIO.save(file, gtb)
    # error: color column must be a iterable of colors
    mesh = domain(gtb1)
    gtb = georef((; COLOR=rand(4)), mesh)
    file = joinpath(savedir, "error.off")
    @test_throws ArgumentError GeoIO.save(file, gtb, color="COLOR")
  end
end
