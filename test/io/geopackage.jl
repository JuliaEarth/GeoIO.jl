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

  @testset "gpkgbinary" begin
    # note: If the geometry type_name value is "GEOMETRYCOLLECTION" then the
    # feature table geometry column MAY contain geometries of type GeometryCollection
    # containing zero or more geometries of any allowed geometry type
    geoms =  [
        Multi([
        Point(LatLon{WGS84Latest}(1.0,1.0)),
        Rope([Point(LatLon{WGS84Latest}(1.0,1.0)), Point(LatLon{WGS84Latest}(2.0,1.0))]),
        PolyArea([
            Ring(
                [
                    Point(LatLon{WGS84Latest}(1.0,1.0)),
                    Point(LatLon{WGS84Latest}(2.0,1.0)),
                    Point(LatLon{WGS84Latest}(3.0,1.0)),
                    Point(LatLon{WGS84Latest}(1.0,1.0)),
                ]
            ),
            Ring(
                [
                    Point(LatLon{WGS84Latest}(0.0,0.0)),
                    Point(LatLon{WGS84Latest}(2.0,1.0)),
                    Point(LatLon{WGS84Latest}(3.0,1.0)),
                    Point(LatLon{WGS84Latest}(0.0,0.0))
                ]
            )
        ])
      ]),
        Multi([
                Point(LatLon{WGS84Latest}(1.0,1.0)),
                Point(LatLon{WGS84Latest}(2.0,1.0)),
                Point(LatLon{WGS84Latest}(3.0,1.0)),
        ]),
        Multi([
            Ring(
                [
                    Point(LatLon{WGS84Latest}(1.0,1.0)),
                    Point(LatLon{WGS84Latest}(2.0,1.0)),
                    Point(LatLon{WGS84Latest}(3.0,1.0)),
                    Point(LatLon{WGS84Latest}(1.0,1.0)),
                ]
            ),
            Ring(
                [
                    Point(LatLon{WGS84Latest}(0.0,0.0)),
                    Point(LatLon{WGS84Latest}(2.0,1.0)),
                    Point(LatLon{WGS84Latest}(3.0,1.0)),
                    Point(LatLon{WGS84Latest}(0.0,0.0))
                ]
            )
        ]),
        Multi(
            [
         PolyArea([
            Ring(
                [
                    Point(LatLon{WGS84Latest}(1.0,1.0)),
                    Point(LatLon{WGS84Latest}(2.0,1.0)),
                    Point(LatLon{WGS84Latest}(3.0,1.0)),
                    Point(LatLon{WGS84Latest}(1.0,1.0)),
                ]
            ),
            Ring(
                [
                    Point(LatLon{WGS84Latest}(0.0,0.0)),
                    Point(LatLon{WGS84Latest}(2.0,1.0)),
                    Point(LatLon{WGS84Latest}(3.0,1.0)),
                    Point(LatLon{WGS84Latest}(0.0,0.0))
                ]
            )
        ]),
        PolyArea([
            Ring(
                [
                    Point(LatLon{WGS84Latest}(1.0,1.0)),
                    Point(LatLon{WGS84Latest}(2.0,1.0)),
                    Point(LatLon{WGS84Latest}(3.0,1.0)),
                    Point(LatLon{WGS84Latest}(1.0,1.0)),
                ]
            ),
            Ring(
                [
                    Point(LatLon{WGS84Latest}(0.0,0.0)),
                    Point(LatLon{WGS84Latest}(2.0,1.0)),
                    Point(LatLon{WGS84Latest}(3.0,1.0)),
                    Point(LatLon{WGS84Latest}(0.0,0.0))
                ]
            )
        ])
            ]
        )

              ]
    gtb1 = georef(nothing, geoms)
    file1 = joinpath(savedir, "gdal.gpkg")
    GeoIO.save(file1, gtb1)
    gtb2 = GeoIO.load(file1)
    @test typeof(gtb2.geometry[1]) <: Multi
    @test typeof(gtb2.geometry[2]) <: MultiPoint
    @test typeof(gtb2.geometry[3]) <: MultiChain
    @test typeof(gtb2.geometry[4]) <: MultiPolygon

    # test for GeoPackage spatial reference system records
    # that are not contained in the minimal `gpkg_spatial_ref_sys` SQLite table
    file1 = joinpath(savedir, "srs.gpkg")
    geoms = [Point(WebMercator{WGS84Latest}(1.0,1.0))]
    gtb1 = georef(nothing, geoms)
    GeoIO.save(file1, gtb1)
    gtb2 = GeoIO.load(file1)
    @test crs(gtb2) <: WebMercator{WGS84Latest}

    # tests to ensure correct CRS is applied to feature table geometries
    # test for GeodeticLatLonAlt{WGS84Latest} CRS
    geoms = [Point(LatLonAlt{WGS84Latest}(1.0,1.0,1.0))]
    gtb1 = georef(nothing, geoms)
    GeoIO.save(file1, gtb1)
    gtb2 = GeoIO.load(file1)
    @test CoordRefSystems.ncoords(crs(gtb2)) == 3
    @test crs(gtb2) <: GeodeticLatLonAlt{WGS84Latest}

    # test for Cartesian3D{NoDatum} CRS
    geoms = [Point(Cartesian3D{NoDatum}(1.0,1.0,1.0))]
    gtb1 = georef(nothing, geoms)
    GeoIO.save(file1, gtb1)
    gtb2 = GeoIO.load(file1)
    @test CoordRefSystems.ncoords(crs(gtb2)) == 3
    @test crs(gtb2) <: Cartesian3D{NoDatum}

    # test to guarantee table values when feature table geometries are missing
    # in the geometry column of the vector `features` user data table
    file1 = joinpath(datadir, "missing.gpkg")
    gtb1 = GeoIO.loadvalues(file1)
    @test gtb1 == (id = [1,2], identifier = ["A","B"])
  end
end
