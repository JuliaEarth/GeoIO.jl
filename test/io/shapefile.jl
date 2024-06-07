@testset "Shapefile" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "points.shp"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa PointSet
    @test gtb.geometry[1] isa Point

    gtb = GeoIO.load(joinpath(datadir, "lines.shp"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa Multi
    @test parent(gtb.geometry[1])[1] isa Chain

    gtb = GeoIO.load(joinpath(datadir, "polygons.shp"))
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa Multi
    @test parent(gtb.geometry[1])[1] isa PolyArea

    gtb = GeoIO.load(joinpath(datadir, "path.shp"))
    @test Tables.schema(gtb).names == (:ZONA, :geometry)
    @test length(gtb.geometry) == 6
    @test gtb.ZONA == ["PA 150", "BR 364", "BR 163", "BR 230", "BR 010", "Estuarina PA"]
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa Multi

    gtb = GeoIO.load(joinpath(datadir, "zone.shp"))
    @test Tables.schema(gtb).names == (:PERIMETER, :ACRES, :MACROZONA, :Hectares, :area_m2, :geometry)
    @test length(gtb.geometry) == 4
    @test gtb.PERIMETER == [5.850803650776888e6, 9.539471535859613e6, 1.01743436941e7, 7.096124186552936e6]
    @test gtb.ACRES == [3.23144676827e7, 2.50593712407e8, 2.75528426573e8, 1.61293042687e8]
    @test gtb.MACROZONA == ["Estuario", "Fronteiras Antigas", "Fronteiras Intermediarias", "Fronteiras Novas"]
    @test gtb.Hectares == [1.30772011078e7, 1.01411677447e8, 1.11502398263e8, 6.52729785685e7]
    @test gtb.area_m2 == [1.30772011078e11, 1.01411677447e12, 1.11502398263e12, 6.52729785685e11]
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa Multi

    gtb = GeoIO.load(joinpath(datadir, "land.shp"))
    @test Tables.schema(gtb).names == (:featurecla, :scalerank, :min_zoom, :geometry)
    @test length(gtb.geometry) == 127
    @test all(==("Land"), gtb.featurecla)
    @test all(∈([0, 1]), gtb.scalerank)
    @test all(∈([0.0, 0.5, 1.0, 1.5]), gtb.min_zoom)
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa Multi

    # https://github.com/JuliaEarth/GeoIO.jl/issues/32
    @test GeoIO.load(joinpath(datadir, "issue32.shp")) isa AbstractGeoTable
    @test GeoIO.load(joinpath(datadir, "lines.shp")) isa AbstractGeoTable
  end

  @testset "save" begin
    file1 = joinpath(datadir, "points.shp")
    file2 = joinpath(savedir, "points.shp")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "lines.shp")
    file2 = joinpath(savedir, "lines.shp")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "polygons.shp")
    file2 = joinpath(savedir, "polygons.shp")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)
  end
end
