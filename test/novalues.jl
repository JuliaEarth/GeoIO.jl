@testset "GeoTables without values" begin
  # Shapefile
  pset = [Point(0.0, 0.0), Point(1.0, 0.0), Point(0.0, 1.0)]
  gtb1 = georef(nothing, pset)
  file = joinpath(savedir, "noattribs.shp")
  GeoIO.save(file, gtb1, warn=false)
  gtb2 = GeoIO.load(file)
  @test all(ismissing, gtb2[:, 1])
  @test gtb2.geometry == gtb1.geometry

  # GeoParquet
  pset = [Point(0.0, 0.0), Point(1.0, 0.0), Point(0.0, 1.0)]
  gtb1 = georef(nothing, pset)
  file = joinpath(savedir, "noattribs.parquet")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1

  # GeoPackage
  pset = [Point(LatLon(30, 60)), Point(LatLon(30, 61)), Point(LatLon(31, 60))]
  gtb1 = georef(nothing, pset)
  file = joinpath(savedir, "noattribs.gpkg")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test isequal((id = [1, 2, 3],), values(gtb2))
  gtb1o = georef((id = [1, 2, 3],), pset)
  @test gtb2 == gtb1o

  # CSV
  pset = [Point(0.0, 0.0), Point(1.0, 0.0), Point(0.0, 1.0)]
  gtb1 = georef(nothing, pset)
  file = joinpath(savedir, "noattribs.csv")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file, coords=["x", "y"])
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1

  # GSLIB
  pset = [Point(0.0, 0.0), Point(1.0, 0.0), Point(0.0, 1.0)]
  gtb1 = georef(nothing, pset)
  file = joinpath(savedir, "noattribs.gslib")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1

  # VTK
  grid = CartesianGrid(10, 10)
  gtb1 = georef(nothing, grid)
  file = joinpath(savedir, "noattribs.vts")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1

  # MSH
  mesh = GeoIO.load(joinpath(datadir, "tetrahedron1.msh")).geometry
  gtb1 = georef(nothing, mesh)
  file = joinpath(savedir, "noattribs.msh")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1

  # GeoJSON
  pset = [Point(LatLon(30, 60)), Point(LatLon(30, 61)), Point(LatLon(31, 60))]
  gtb1 = georef(nothing, pset)
  file = joinpath(savedir, "noattribs.geojson")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1
end
