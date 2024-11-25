@testset "GeoTiff" begin
  @testset "load" begin
    file = joinpath(datadir, "test.tif")
    gtb = GeoIO.load(file)
    @test crs(gtb.geometry) <: Cartesian
    @test propertynames(gtb) == [:color, :geometry]
    @test eltype(gtb.color) <: Colorant
    @test gtb.geometry isa CartesianGrid
    @test size(gtb.geometry) == (100, 100)

    # the "test_gray.tif" file is an upscale of a NaturalEarth file
    # link: https://www.naturalearthdata.com/downloads/50m-gray-earth/50m-gray-earth-with-shaded-relief-and-water/
    file = joinpath(datadir, "test_gray.tif")
    gtb = GeoIO.load(file)
    @test crs(gtb.geometry) <: Cartesian
    @test propertynames(gtb) == [:color, :geometry]
    @test eltype(gtb.color) <: Colorant
    @test gtb.geometry isa CartesianGrid
    @test size(gtb.geometry) == (108, 108)

    # the "natural_earth_1.tif" file is an upscale of a NaturalEarth file
    # link: https://www.naturalearthdata.com/downloads/10m-raster-data/10m-natural-earth-1/
    file = joinpath(datadir, "natural_earth_1.tif")
    gtb = GeoIO.load(file)
    @test crs(gtb.geometry) <: LatLon
    @test propertynames(gtb) == [:color, :geometry]
    @test eltype(gtb.color) <: Colorant
    @test gtb.geometry isa TransformedGrid
    @test size(gtb.geometry) == (162, 81)

    # the "natural_earth_1_projected.tif" file is a project version of "natural_earth_1.tif"
    file = joinpath(datadir, "natural_earth_1_projected.tif")
    gtb = GeoIO.load(file)
    @test crs(gtb.geometry) <: PlateCarree
    @test propertynames(gtb) == [:color, :geometry]
    @test eltype(gtb.color) <: Colorant
    @test gtb.geometry isa TransformedGrid
    @test size(gtb.geometry) == (162, 81)

    # the "utm.tif" file is from the GeoTIFF/test-data repo
    # link: https://github.com/GeoTIFF/test-data/blob/main/files/utm.tif
    file = joinpath(datadir, "utm.tif")
    gtb = GeoIO.load(file)
    @test crs(gtb.geometry) <: utmnorth(17)
    @test propertynames(gtb) == [:color, :geometry]
    @test eltype(gtb.color) <: Colorant
    @test gtb.geometry isa TransformedGrid
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

    file1 = joinpath(datadir, "test_gray.tif")
    file2 = joinpath(savedir, "test_gray.tif")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "utm.tif")
    file2 = joinpath(savedir, "utm.tif")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test isapprox(gtb1.geometry, gtb2.geometry, atol=1e-6u"m")
    @test values(gtb1) == values(gtb2)
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "natural_earth_1.tif")
    file2 = joinpath(savedir, "natural_earth_1.tif")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test isapprox(gtb1.geometry, gtb2.geometry, atol=1e-6u"m")
    @test values(gtb1) == values(gtb2)
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "natural_earth_1_projected.tif")
    file2 = joinpath(savedir, "natural_earth_1_projected.tif")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test isapprox(gtb1.geometry, gtb2.geometry, atol=1e-6u"m")
    @test values(gtb1) == values(gtb2)
    @test values(gtb1, 0) == values(gtb2, 0)

    # float data
    # single channel
    file = joinpath(savedir, "float_single.tif")
    grid = CartesianGrid(10, 10)
    gtb1 = georef((; color=rand(100)), grid)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test eltype(gtb2.color) <: Gray
    @test gtb1.geometry == gtb2.geometry
    @test values(gtb1, 0) == values(gtb2, 0)
    # multiple channels
    file = joinpath(savedir, "float_multi.tif")
    gtb1 = georef((channel1=rand(100), channel2=rand(100)), grid)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test eltype(gtb2.channel1) <: Float64
    @test eltype(gtb2.channel2) <: Float64
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    # int data
    # single channel
    file = joinpath(savedir, "int_single.tif")
    grid = CartesianGrid(10, 10)
    gtb1 = georef((; color=rand(1:10, 100)), grid)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test eltype(gtb2.color) <: Gray
    @test gtb1.geometry == gtb2.geometry
    @test values(gtb1, 0) == values(gtb2, 0)
    # multiple channels
    file = joinpath(savedir, "int_multi.tif")
    gtb1 = georef((channel1=rand(1:10, 100), channel2=rand(1:10, 100)), grid)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test eltype(gtb2.channel1) <: FixedPoint
    @test eltype(gtb2.channel2) <: FixedPoint
    @test gtb1.geometry == gtb2.geometry
    @test values(gtb1, 0) == values(gtb2, 0)

    # uint data
    # single channel
    file = joinpath(savedir, "uint_single.tif")
    grid = CartesianGrid(10, 10)
    gtb1 = georef((; color=rand(UInt(1):UInt(10), 100)), grid)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test eltype(gtb2.color) <: Gray
    @test gtb1.geometry == gtb2.geometry
    @test values(gtb1, 0) == values(gtb2, 0)
    # multiple channels
    file = joinpath(savedir, "uint_multi.tif")
    gtb1 = georef((channel1=rand(UInt(1):UInt(10), 100), channel2=rand(UInt(1):UInt(10), 100)), grid)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test eltype(gtb2.channel1) <: FixedPoint
    @test eltype(gtb2.channel2) <: FixedPoint
    @test gtb1.geometry == gtb2.geometry
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
