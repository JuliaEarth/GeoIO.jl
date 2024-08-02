@testset "GeoTiff" begin
  @testset "load" begin
    file = joinpath(datadir, "test.tif")
    gtb = GeoIO.load(file)
    @test crs(gtb.geometry) <: Cartesian
    @test propertynames(gtb) == [:BAND1, :BAND2, :BAND3, :geometry]
    @test eltype(gtb.BAND1) <: UInt8
    @test eltype(gtb.BAND2) <: UInt8
    @test eltype(gtb.BAND3) <: UInt8
    @test gtb.geometry isa Meshes.TransformedGrid
    @test size(gtb.geometry) == (100, 100)

    file = joinpath(datadir, "utm.tif")
    gtb = GeoIO.load(file)
    @test crs(gtb.geometry) <: UTMNorth{17}
    @test propertynames(gtb) == [:BAND1, :geometry]
    @test eltype(gtb.BAND1) <: UInt8
    @test gtb.geometry isa Meshes.TransformedGrid
    @test size(gtb.geometry) == (100, 100)
  end

  @testset "save" begin
    file1 = joinpath(datadir, "test.tif")
    file2 = joinpath(savedir, "test.tif")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    # error: GeoTiff format only supports 2D grids
    file = joinpath(savedir, "error.tif")
    gtb = georef((; a=rand(8)), CartesianGrid(2, 2, 2))
    @test_throws ArgumentError GeoIO.save(file, gtb)
    # error: GeoTiff format needs data to save
    gtb = georef(nothing, CartesianGrid(2, 2))
    @test_throws ArgumentError GeoIO.save(file, gtb)
    # error: all variables must have the same type
    gtb = georef((a=rand(1:9, 25), b=rand(25)), CartesianGrid(5, 5))
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end
end
