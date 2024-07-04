@testset "GIS" begin
  tab =
    (float=[0.07, 0.34, 0.69, 0.62, 0.91], int=[1, 2, 3, 4, 5], string=["word1", "word2", "word3", "word4", "word5"])
  points = Point.([LatLon(0, 0), LatLon(1, 1), LatLon(2, 2), LatLon(3, 3), LatLon(4, 4)])
  rings =
    Ring.([
      Point.([LatLon(0, 0), LatLon(1, 1), LatLon(2, 2)]),
      Point.([LatLon(0, 0), LatLon(-1, -1), LatLon(-2, -2)]),
      Point.([LatLon(0, 0), LatLon(-1, 1), LatLon(-2, 2)]),
      Point.([LatLon(0, 0), LatLon(1, -1), LatLon(2, -2)]),
      Point.([LatLon(0, 0), LatLon(1, 1), LatLon(-2, -2)])
    ])
  polys = PolyArea.(rings)

  # points
  gtb1 = georef(tab, points)

  # Shapefile
  file = joinpath(savedir, "gis-points.shp")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test_broken gtb2.geometry == gtb1.geometry
  @test values(gtb2) == values(gtb1)

  # GeoJSON
  # note: GeoJSON loads data in Float32 by default
  # explicitly loading as Float64
  file = joinpath(savedir, "gis-points.geojson")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file, numbertype=Float64)
  @test gtb2 == gtb1

  # GeoPackage
  # note: GeoPackage does not preserve column order
  file = joinpath(savedir, "gis-points.gpkg")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test Set(names(gtb2)) == Set(names(gtb1))
  @test_broken gtb2.geometry == gtb1.geometry
  @test gtb2.float == gtb1.float
  @test gtb2.int == gtb1.int
  @test gtb2.string == gtb1.string

  # rings
  gtb1 = georef(tab, rings)

  # Shapefile
  # note: Shapefile saves Chain as MultiChain
  # using a helper to workaround this
  file = joinpath(savedir, "gis-rings.shp")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test_broken _isequal(gtb2.geometry, gtb1.geometry)
  @test values(gtb2) == values(gtb1)

  # GeoJSON
  # note: GeoJSON loads data in Float32 by default
  # explissity loading as Float64
  file = joinpath(savedir, "gis-rings.geojson")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file, numbertype=Float64)
  @test gtb2 == gtb1

  # GeoPackage
  # note: GeoPackage does not preserve column order
  file = joinpath(savedir, "gis-rings.gpkg")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test Set(names(gtb2)) == Set(names(gtb1))
  @test_broken gtb2.geometry == gtb1.geometry
  @test gtb2.float == gtb1.float
  @test gtb2.int == gtb1.int
  @test gtb2.string == gtb1.string

  # polygons
  gtb1 = georef(tab, polys)

  # Shapefile
  # note: Shapefile saves PolyArea as MultiPolyArea
  # using a halper to workaround this
  file = joinpath(savedir, "gis-polys.shp")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test_broken _isequal(gtb2.geometry, gtb1.geometry)
  @test values(gtb2) == values(gtb1)

  # GeoJSON
  # note: GeoJSON loads data in Float32 by default
  # explissity loading as Float64
  file = joinpath(savedir, "gis-polys.geojson")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file, numbertype=Float64)
  @test gtb2 == gtb1

  # GeoPackage
  # note: GeoPackage does not preserve column order
  file = joinpath(savedir, "gis-polys.gpkg")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test Set(names(gtb2)) == Set(names(gtb1))
  @test_broken gtb2.geometry == gtb1.geometry
  @test gtb2.float == gtb1.float
  @test gtb2.int == gtb1.int
  @test gtb2.string == gtb1.string
end
