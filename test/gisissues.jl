@testset "Known GIS issues" begin
  table =
    (float=[0.07, 0.34, 0.69, 0.62, 0.91], int=[1, 2, 3, 4, 5], string=["word1", "word2", "word3", "word4", "word5"])
  points = Point.([LatLon(0, 0), LatLon(1, 1), LatLon(2, 2), LatLon(3, 3), LatLon(4, 4)])
  rings =
    Ring.([
      Point.([LatLon(0, 0), LatLon(1, 1), LatLon(2, 2)]),
      Point.([LatLon(0, 0), LatLon(-2, -2), LatLon(-1, -1)]),
      Point.([LatLon(0, 0), LatLon(-1, 1), LatLon(-2, 2)]),
      Point.([LatLon(0, 0), LatLon(2, -2), LatLon(1, -1)]),
      Point.([LatLon(0, 0), LatLon(1, 1), LatLon(-2, -2)])
    ])
  polys = PolyArea.(rings)

  gtpoint = georef(table, points)
  gtring = georef(table, rings)
  gtpoly = georef(table, polys)

  # Shapefile
  file = joinpath(savedir, "gis-points.shp")
  GeoIO.save(file, gtpoint, warn=false)
  gtb = GeoIO.load(file)
  @test gtb.geometry == gtpoint.geometry
  @test values(gtb) == values(gtpoint)

  # note: Shapefile saves Chain as MultiChain
  file = joinpath(savedir, "gis-rings.shp")
  GeoIO.save(file, gtring, warn=false)
  gtb = GeoIO.load(file)
  @test isequalshp(gtb.geometry, gtring.geometry)
  @test values(gtb) == values(gtring)

  # note: Shapefile saves PolyArea as MultiPolyArea
  file = joinpath(savedir, "gis-polys.shp")
  GeoIO.save(file, gtpoly, warn=false)
  gtb = GeoIO.load(file)
  @test isequalshp(gtb.geometry, gtpoly.geometry)
  @test values(gtb) == values(gtpoly)

  # GeoJSON
  # note: GeoJSON does not preserve column order
  file = joinpath(savedir, "gis-points.geojson")
  GeoIO.save(file, gtpoint)
  gtb = GeoIO.load(file)
  @test Set(names(gtb)) == Set(names(gtpoint))
  @test gtb.geometry == gtpoint.geometry
  @test gtb.float == gtpoint.float
  @test gtb.int == gtpoint.int
  @test gtb.string == gtpoint.string

  file = joinpath(savedir, "gis-rings.geojson")
  GeoIO.save(file, gtring)
  gtb = GeoIO.load(file)
  @test Set(names(gtb)) == Set(names(gtring))
  @test gtb.geometry == gtring.geometry
  @test gtb.float == gtring.float
  @test gtb.int == gtring.int
  @test gtb.string == gtring.string

  file = joinpath(savedir, "gis-polys.geojson")
  GeoIO.save(file, gtpoly)
  gtb = GeoIO.load(file)
  @test Set(names(gtb)) == Set(names(gtpoly))
  @test gtb.geometry == gtpoly.geometry
  @test gtb.float == gtpoly.float
  @test gtb.int == gtpoly.int
  @test gtb.string == gtpoly.string

  # GeoPackage
  # note: GeoPackage does not preserve column order
  file = joinpath(savedir, "gis-points.gpkg")
  GeoIO.save(file, gtpoint)
  gtb = GeoIO.load(file)
  @test Set([n for n in names(gtb) if n != "id"]) == Set(names(gtpoint))
  @test gtb.geometry == gtpoint.geometry
  @test gtb.float == gtpoint.float
  @test gtb.int == gtpoint.int
  @test gtb.string == gtpoint.string

  file = joinpath(savedir, "gis-rings.gpkg")
  GeoIO.save(file, gtring)
  gtb = GeoIO.load(file)
  @test Set([n for n in names(gtb) if n != "id"]) == Set(names(gtring))
  @test gtb.geometry == gtring.geometry
  @test gtb.float == gtring.float
  @test gtb.int == gtring.int
  @test gtb.string == gtring.string

  file = joinpath(savedir, "gis-polys.gpkg")
  GeoIO.save(file, gtpoly)
  gtb = GeoIO.load(file)
  @test Set([n for n in names(gtb) if n != "id"]) == Set(names(gtpoly))
  @test gtb.geometry == gtpoly.geometry
  @test gtb.float == gtpoly.float
  @test gtb.int == gtpoly.int
  @test gtb.string == gtpoly.string
end
