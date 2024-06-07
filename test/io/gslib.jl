@testset "GSLIB" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "grid.gslib"))
    @test gtb.geometry isa CartesianGrid
    @test gtb."Porosity"[1] isa Float64
    @test gtb."Lithology"[1] isa Float64
    @test gtb."Water Saturation"[1] isa Float64
    @test isnan(gtb."Water Saturation"[end])
  end

  @testset "save" begin
    file1 = joinpath(datadir, "grid.gslib")
    file2 = joinpath(savedir, "grid.gslib")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1.geometry == gtb2.geometry
    @test values(gtb1, 0) == values(gtb2, 0)
  end
end
