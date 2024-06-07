@testset "Images" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "image.jpg"))
    @test gtb.geometry isa TransformedGrid
    @test length(gtb.color) == length(gtb.geometry)
  end

  @testset "save" begin
    file1 = joinpath(datadir, "image.jpg")
    file2 = joinpath(savedir, "image.jpg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1.geometry == gtb2.geometry
    @test psnr_equality()(gtb1.color, gtb2.color)

    # error: image formats only support grids
    file = joinpath(savedir, "error.jpg")
    gtb = georef((; a=rand(10)), rand(Point{2}, 10))
    @test_throws ArgumentError GeoIO.save(file, gtb)
    # error: image formats need data to save
    gtb = georef(nothing, CartesianGrid(2, 2))
    @test_throws ArgumentError GeoIO.save(file, gtb)
    # error: color column not found
    gtb = georef((; a=rand(4)), CartesianGrid(2, 2))
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end
end
