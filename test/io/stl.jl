@testset "STL" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron_ascii.stl"))
    @test eltype(gtb.NORMAL) <: Vec{3}
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float64}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4

    gtb = GeoIO.load(joinpath(datadir, "tetrahedron_bin.stl"))
    @test eltype(gtb.NORMAL) <: Vec{3}
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float32}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4
  end

  @testset "save" begin
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
    @test_logs (:warn,) GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test Meshes.lentype(gtb1.geometry) <: Meshes.Met{Float64}
    @test Meshes.lentype(gtb2.geometry) <: Meshes.Met{Float32}

    # error: STL format only supports 3D triangle meshes
    gtb = GeoTable(CartesianGrid(2, 2, 2))
    file = joinpath(savedir, "error.stl")
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end
end