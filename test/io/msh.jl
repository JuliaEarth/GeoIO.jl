@testset "MSH" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron1.msh"))
    @test eltype(gtb.data) <: AbstractVector
    @test length(first(gtb.data)) == 3
    vtable = values(gtb, 0)
    @test eltype(vtable.data) <: Float64
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float64}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4

    gtb = GeoIO.load(joinpath(datadir, "tetrahedron2.msh"))
    @test nonmissingtype(eltype(gtb.data)) <: AbstractMatrix
    @test size(first(skipmissing(gtb.data))) == (3, 3)
    vtable = values(gtb, 0)
    @test nonmissingtype(eltype(vtable.data)) <: AbstractVector
    @test length(first(skipmissing(vtable.data))) == 3
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float64}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4

    # custom lenunit
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron1.msh"), lenunit=cm)
    @test unit(Meshes.lentype(crs(gtb.geometry))) == cm
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron2.msh"), lenunit=cm)
    @test unit(Meshes.lentype(crs(gtb.geometry))) == cm
  end

  @testset "save" begin
    file1 = joinpath(datadir, "tetrahedron1.msh")
    file2 = joinpath(savedir, "tetrahedron1.msh")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1, vcolumn=:data, ecolumn=:data)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "tetrahedron2.msh")
    file2 = joinpath(savedir, "tetrahedron2.msh")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1, vcolumn="data", ecolumn="data")
    gtb2 = GeoIO.load(file2)
    @test isequal(gtb1.data, gtb2.data)
    @test gtb1.geometry == gtb2.geometry
    vtable1 = values(gtb1, 0)
    vtable2 = values(gtb2, 0)
    @test isequal(vtable1.data, vtable2.data)

    # error: MSH format only supports 3D meshes
    gtb = GeoTable(CartesianGrid(2, 2))
    file = joinpath(savedir, "error.msh")
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end
end
