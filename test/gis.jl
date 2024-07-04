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
  gtpoint = georef(tab, points)
  gtring = georef(tab, rings)
  gtpoly = georef(tab, polys)

  # Shapefile
  file = joinpath(savedir, "gis-points.shp")
  GeoIO.save(file, gtpoint)
  gtb = GeoIO.load(file)
  @test_broken gtb.geometry == gtpoint.geometry
  @test values(gtb) == values(gtpoint)

  # note: Shapefile saves PolyArea as MultiPolyArea
  # using a halper to workaround this
  file = joinpath(savedir, "gis-polys.shp")
  GeoIO.save(file, gtring)
  gtb = GeoIO.load(file)
  @test_broken _isequal(gtb.geometry, gtring.geometry)
  @test values(gtb) == values(gtring)

  # note: Shapefile saves PolyArea as MultiPolyArea
  # using a halper to workaround this
  file = joinpath(savedir, "gis-polys.shp")
  GeoIO.save(file, gtpoly)
  gtb = GeoIO.load(file)
  @test_broken _isequal(gtb.geometry, gtpoly.geometry)
  @test values(gtb) == values(gtpoly)

  # GeoJSON
  # note: GeoJSON loads data in Float32 by default
  # explicitly loading as Float64
  file = joinpath(savedir, "gis-points.geojson")
  GeoIO.save(file, gtpoint)
  gtb = GeoIO.load(file, numbertype=Float64)
  @test gtb == gtpoint

  file = joinpath(savedir, "gis-rings.geojson")
  GeoIO.save(file, gtring)
  gtb = GeoIO.load(file, numbertype=Float64)
  @test gtb == gtring

  file = joinpath(savedir, "gis-polys.geojson")
  GeoIO.save(file, gtpoly)
  gtb = GeoIO.load(file, numbertype=Float64)
  @test gtb == gtpoly

  # GeoPackage
  # note: GeoPackage does not preserve column order
  file = joinpath(savedir, "gis-points.gpkg")
  GeoIO.save(file, gtpoint)
  gtb = GeoIO.load(file)
  @test Set(names(gtb)) == Set(names(gtpoint))
  @test_broken gtb.geometry == gtpoint.geometry
  @test gtb.float == gtpoint.float
  @test gtb.int == gtpoint.int
  @test gtb.string == gtpoint.string

  file = joinpath(savedir, "gis-rings.gpkg")
  GeoIO.save(file, gtring)
  gtb = GeoIO.load(file)
  @test Set(names(gtb)) == Set(names(gtring))
  @test_broken gtb.geometry == gtring.geometry
  @test gtb.float == gtring.float
  @test gtb.int == gtring.int
  @test gtb.string == gtring.string

  file = joinpath(savedir, "gis-polys.gpkg")
  GeoIO.save(file, gtpoly)
  gtb = GeoIO.load(file)
  @test Set(names(gtb)) == Set(names(gtpoly))
  @test_broken gtb.geometry == gtpoly.geometry
  @test gtb.float == gtpoly.float
  @test gtb.int == gtpoly.int
  @test gtb.string == gtpoly.string
end
