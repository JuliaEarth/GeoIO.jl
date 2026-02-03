@testset "GeoPackage" begin
  @testset "load" begin
    gtb = GeoIO.load(joinpath(datadir, "points.gpkg"))
    @test crs(gtb.geometry) <: LatLon
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa PointSet
    @test gtb.geometry[1] isa Point

    gtb = GeoIO.load(joinpath(datadir, "lines.gpkg"))
    @test crs(gtb.geometry) <: LatLon
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa Chain

    gtb = GeoIO.load(joinpath(datadir, "polygons.gpkg"))
    @test crs(gtb.geometry) <: LatLon
    @test length(gtb.geometry) == 5
    @test gtb.code[1] isa Integer
    @test gtb.name[1] isa String
    @test gtb.variable[1] isa Real
    @test gtb.geometry isa GeometrySet
    @test gtb.geometry[1] isa PolyArea

    @test GeoIO.load(joinpath(datadir, "lines.gpkg")) isa AbstractGeoTable
  end

  @testset "save" begin
    # note: GeoPackage does not preserve column order
    file1 = joinpath(datadir, "points.gpkg")
    file2 = joinpath(savedir, "points.gpkg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test Set(names(gtb2)) == Set(names(gtb1))
    @test gtb2.geometry == gtb1.geometry
    @test gtb2.code == gtb1.code
    @test gtb2.name == gtb1.name
    @test gtb2.variable == gtb1.variable

    file1 = joinpath(datadir, "lines.gpkg")
    file2 = joinpath(savedir, "lines.gpkg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test Set(names(gtb2)) == Set(names(gtb1))
    @test gtb2.geometry == gtb1.geometry
    @test gtb2.code == gtb1.code
    @test gtb2.name == gtb1.name
    @test gtb2.variable == gtb1.variable

    file1 = joinpath(datadir, "polygons.gpkg")
    file2 = joinpath(savedir, "polygons.gpkg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test Set(names(gtb2)) == Set(names(gtb1))
    @test gtb2.geometry == gtb1.geometry
    @test gtb2.code == gtb1.code
    @test gtb2.name == gtb1.name
    @test gtb2.variable == gtb1.variable
  end

  @testset "wkb" begin
    # note: If the geometry type_name value is "GEOMETRYCOLLECTION"
    # then the feature table geometry column MAY contain geometries
    # of type GeometryCollection containing zero or more geometries
    # of any allowed geometry type
    file1 = joinpath(datadir, "geomcollection.gpkg")
    file2 = joinpath(savedir, "geomcollection.gpkg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test Set(names(gtb2)) == Set(names(gtb1))
    @test gtb2.geometry == gtb1.geometry

    # note: GeoPackage may contain sqlite null for missing geometries
    file1 = joinpath(datadir, "missing.gpkg")
    file2 = joinpath(savedir, "missing.gpkg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test Set(names(gtb2)) == Set(names(gtb1))
    @test gtb2.geometry == gtb1.geometry

    # test for GeoPackage with spatial reference system records
    # that are not Cartesian or WGS84
    file1 = joinpath(datadir, "crs.gpkg")
    file2 = joinpath(savedir, "crs.gpkg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test Set(names(gtb2)) == Set(names(gtb1))
    @test gtb2.geometry == gtb1.geometry

    # test for GeoPackage containing 3d geometry
    file1 = joinpath(datadir, "geometry3d.gpkg")
    file2 = joinpath(savedir, "geometry3d.gpkg")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test Set(names(gtb2)) == Set(names(gtb1))
    @test gtb2.geometry == gtb1.geometry
  end
end
