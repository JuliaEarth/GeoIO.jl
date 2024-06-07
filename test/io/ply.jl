@testset "PLY" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "beethoven.ply"))
    @test gtb.geometry isa SimpleMesh
    @test isnothing(values(gtb, 0))
    @test isnothing(values(gtb, 1))
    @test isnothing(values(gtb, 2))
  end

  @testset "save" begin
    file1 = joinpath(datadir, "beethoven.ply")
    file2 = joinpath(savedir, "beethoven.ply")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    mesh = gtb1.geometry
    gtb1 = georef((; a=rand(nelements(mesh))), mesh)
    file = joinpath(savedir, "plywithdata.ply")
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)
  end
end
