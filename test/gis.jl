@testset "GIS" begin
  tab =
    (variable=[0.07, 0.34, 0.69, 0.62, 0.91], code=[1, 2, 3, 4, 5], name=["word1", "word2", "word3", "word4", "word5"])
  points1 = Point.([(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)])
  points2 = Point.([LatLon(0, 0), LatLon(1, 1), LatLon(2, 2), LatLon(3, 3), LatLon(4, 4)])
  rings1 =
    Ring.([
      [(0, 0), (1, 1), (2, 2)],
      [(0, 0), (-1, -1), (-2, -2)],
      [(0, 0), (-1, 1), (-2, 2)],
      [(0, 0), (1, -1), (2, -2)],
      [(0, 0), (1, 1), (-2, -2)]
    ])
  rings2 =
    Ring.([
      Point.([LatLon(0, 0), LatLon(1, 1), LatLon(2, 2)]),
      Point.([LatLon(0, 0), LatLon(-1, -1), LatLon(-2, -2)]),
      Point.([LatLon(0, 0), LatLon(-1, 1), LatLon(-2, 2)]),
      Point.([LatLon(0, 0), LatLon(1, -1), LatLon(2, -2)]),
      Point.([LatLon(0, 0), LatLon(1, 1), LatLon(-2, -2)])
    ])
  polys1 = PolyArea.(rings1)
  polys2 = PolyArea.(rings2)

  # points
  gtb1 = georef(tab, points1)

  # Shapefile
  file = joinpath(savedir, "gis-points.shp")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test gtb2 == gtb1

  # GeoPackage
  # note: GeoPackage does not preserve column order
  file = joinpath(savedir, "gis-points.gpkg")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test Set(names(gtb2)) == Set(names(gtb1))
  @test gtb2.geometry == gtb1.geometry
  @test gtb2.variable == gtb1.variable
  @test gtb2.code == gtb1.code
  @test gtb2.name == gtb1.name

  # GeoJSON
  # note 1: GeoJSON only saves `LatLon{WGS84Latest}`
  # testing with a geotable with correct CRS
  # note 2: GeoJSON loads data in Float32 by default
  # explissity loading as Float64
  gtb1 = georef(tab, points2)
  file = joinpath(savedir, "gis-points.geojson")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file, numbertype=Float64)
  @test gtb2 == gtb1

  # rings
  gtb1 = georef(tab, rings1)

  # Shapefile
  # note: Shapefile saves Chains as MultiChain
  # using a halper to workaround this
  file = joinpath(savedir, "gis-rings.shp")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test _isequal(gtb2.geometry, gtb1.geometry)
  @test values(gtb2) == values(gtb1)

  # GeoPackage
  # note: GeoPackage does not preserve column order
  file = joinpath(savedir, "gis-rings.gpkg")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test Set(names(gtb2)) == Set(names(gtb1))
  @test gtb2.geometry == gtb1.geometry
  @test gtb2.variable == gtb1.variable
  @test gtb2.code == gtb1.code
  @test gtb2.name == gtb1.name

  # GeoJSON
  # note 1: GeoJSON only saves `LatLon{WGS84Latest}`
  # testing with a geotable with correct CRS
  # note 2: GeoJSON loads data in Float32 by default
  # explissity loading as Float64
  gtb1 = georef(tab, rings2)
  file = joinpath(savedir, "gis-rings.geojson")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file, numbertype=Float64)
  @test gtb2 == gtb1

  # polygons
  gtb1 = georef(tab, polys1)

  # Shapefile
  # note: Shapefile saves PolyArea as MultiPolyArea
  # using a halper to workaround this
  file = joinpath(savedir, "gis-polys.shp")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test _isequal(gtb2.geometry, gtb1.geometry)
  @test values(gtb2) == values(gtb1)

  # GeoPackage
  # note: GeoPackage does not preserve column order
  file = joinpath(savedir, "gis-polys.gpkg")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test Set(names(gtb2)) == Set(names(gtb1))
  @test gtb2.geometry == gtb1.geometry
  @test gtb2.variable == gtb1.variable
  @test gtb2.code == gtb1.code
  @test gtb2.name == gtb1.name

  # GeoJSON
  # note 1: GeoJSON only saves `LatLon{WGS84Latest}`
  # testing with a geotable with correct CRS
  # note 2: GeoJSON loads data in Float32 by default
  # explissity loading as Float64
  gtb1 = georef(tab, polys2)
  file = joinpath(savedir, "gis-polys.geojson")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file, numbertype=Float64)
  @test gtb2 == gtb1
end
