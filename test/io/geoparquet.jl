@testset "GeoParquet" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "points.parquet"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa PointSet
    @test gtb.geometry[1] isa Point

    gtb = GeoIO.load(joinpath(datadir, "lines.parquet"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa Chain

    gtb = GeoIO.load(joinpath(datadir, "polygons.parquet"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa PolyArea

    gtb = GeoIO.load(joinpath(datadir, "points_latlon.parquet"))
    @test crs(gtb.geometry) <: LatLon
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa PointSet
    @test gtb.geometry[1] isa Point

    gtb = GeoIO.load(joinpath(datadir, "points_projected.parquet"))
    @test crs(gtb.geometry) <: Robinson
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa PointSet
    @test gtb.geometry[1] isa Point

    @test GeoIO.load(joinpath(datadir, "lines.parquet")) isa AbstractGeoTable
  end

  @testset "save" begin
    file1 = joinpath(datadir, "points.parquet")
    file2 = joinpath(savedir, "points.parquet")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "lines.parquet")
    file2 = joinpath(savedir, "lines.parquet")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "polygons.parquet")
    file2 = joinpath(savedir, "polygons.parquet")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test sort(Tables.columnnames(values(gtb1))) == sort(Tables.columnnames(values(gtb2)))
    @test length(domain(gtb1)) == length(domain(gtb2))
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "points_latlon.parquet")
    file2 = joinpath(savedir, "points_latlon.parquet")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test sort(Tables.columnnames(values(gtb1))) == sort(Tables.columnnames(values(gtb2)))
    @test length(domain(gtb1)) == length(domain(gtb2))
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "points_projected.parquet")
    file2 = joinpath(savedir, "points_projected.parquet")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test sort(Tables.columnnames(values(gtb1))) == sort(Tables.columnnames(values(gtb2)))
    @test length(domain(gtb1)) == length(domain(gtb2))
    @test values(gtb1, 0) == values(gtb2, 0)
  end
end
