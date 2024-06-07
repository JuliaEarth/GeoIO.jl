@testset "GRIB" begin
  @testset "load" begin
    # the "regular_gg_ml.grib" file is a test file from the GRIBDatasets.jl package
    # link: https://github.com/JuliaGeo/GRIBDatasets.jl/blob/main/test/sample-data/regular_gg_ml.grib
    file = joinpath(datadir, "regular_gg_ml.grib")
    if Sys.iswindows()
      @test_throws ErrorException GeoIO.load(file)
    else
      gtb = GeoIO.load(file)
      @test gtb.geometry isa RectilinearGrid
      @test isnothing(values(gtb))
      @test isnothing(values(gtb, 0))
    end
  end

  @testset "save" begin
    # error: saving GRIB files is not supported
    file = joinpath(savedir, "error.grib")
    gtb = georef((; a=rand(4)), CartesianGrid(2, 2))
    @test_throws ErrorException GeoIO.save(file, gtb)
  end
end
