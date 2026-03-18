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

    # multi-layer GeoPackage warning
    file = joinpath(datadir, "gdal.gpkg")
    gtb = GeoIO.load(file, warn=false)
    @test gtb isa AbstractGeoTable
    gtb = @test_logs (:warn, r"File has 16 layers") (:warn, r"Dropping 1 rows with missing geometries") GeoIO.load(file)
    @test gtb isa AbstractGeoTable
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
    # heterogeneous multi-geometries are stored as "GEOMETRYCOLLECTION" in GPKGBINARY format,
    # but are loaded as Multi{Geometry} for convenience and consistency with other formats
    file = joinpath(savedir, "multigeom.gpkg")
    geoms = [
      Multi([
        Point(LatLon(1.0, 1.0)),
        Rope(Point.([LatLon(1.0, 1.0), LatLon(2.0, 1.0)])),
        PolyArea([
          Ring(Point.([LatLon(1.0, 1.0), LatLon(2.0, 1.0), LatLon(3.0, 1.0)])),
          Ring(Point.([LatLon(0.0, 0.0), LatLon(3.0, 1.0), LatLon(2.0, 1.0)]))
        ])
      ]),
      Multi(Point.([LatLon(1.0, 1.0), LatLon(2.0, 1.0), LatLon(3.0, 1.0)])),
      Multi([
        Ring(Point.([LatLon(1.0, 1.0), LatLon(2.0, 1.0), LatLon(3.0, 1.0)])),
        Ring(Point.([LatLon(0.0, 0.0), LatLon(3.0, 1.0), LatLon(2.0, 1.0)]))
      ]),
      Multi([
        PolyArea([
          Ring(Point.([LatLon(1.0, 1.0), LatLon(2.0, 1.0), LatLon(3.0, 1.0)])),
          Ring(Point.([LatLon(0.0, 0.0), LatLon(3.0, 1.0), LatLon(2.0, 1.0)]))
        ]),
        PolyArea([
          Ring(Point.([LatLon(1.0, 1.0), LatLon(2.0, 1.0), LatLon(3.0, 1.0)])),
          Ring(Point.([LatLon(0.0, 0.0), LatLon(3.0, 1.0), LatLon(2.0, 1.0)]))
        ])
      ])
    ]
    gtb1 = georef(nothing, geoms)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test gtb2 == gtb1

    # make sure CRS is preserved when saving and loading
    file = joinpath(savedir, "crs.gpkg")
    geoms = [Point(WebMercator{WGS84Latest}(1.0, 1.0))]
    gtb1 = georef(nothing, geoms)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test crs(gtb2) <: WebMercator{WGS84Latest}
    geoms = [Point(LatLonAlt{WGS84Latest}(1.0, 1.0, 1.0))]
    gtb1 = georef(nothing, geoms)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test crs(gtb2) <: LatLonAlt{WGS84Latest}
    geoms = [Point(Cartesian3D{NoDatum}(1.0, 1.0, 1.0))]
    gtb1 = georef(nothing, geoms)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test crs(gtb2) <: Cartesian3D{NoDatum}

    # make sure table values are present when geometries are missing
    file = joinpath(datadir, "missing.gpkg")
    gtb = GeoIO.loadvalues(file)
    @test gtb == (id=[1, 2], identifier=["A", "B"])

    # chains with equal start and end points are rings
    file = joinpath(savedir, "isclosed.gpkg")
    geoms = [Rope(Point.([LatLon(1.0, 1.0), LatLon(2.0, 2.0), LatLon(3.0, 3.0), LatLon(1.0, 1.0)]))]
    gtb1 = georef(nothing, geoms)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    ring = only(gtb2.geometry)
    @test ring isa Ring
    @test nvertices(ring) == 3
  end
end
