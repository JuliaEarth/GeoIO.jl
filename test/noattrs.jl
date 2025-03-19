@testset "GeoTables without attributes" begin
  pset = [Point(0.0, 0.0), Point(1.0, 0.0), Point(0.0, 1.0)]
  gtb1 = georef(nothing, pset)

  # Shapefile
  file = joinpath(savedir, "noattribs.shp")
  GeoIO.save(file, gtb1, warn=false)
  gtb2 = GeoIO.load(file)
  @test all(ismissing, gtb2[:, 1])
  @test gtb2.geometry == gtb1.geometry

  # GeoParquet
  file = joinpath(savedir, "noattribs.parquet")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1

  # GeoPackage
  file = joinpath(savedir, "noattribs.gpkg")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1

  # CSV
  file = joinpath(savedir, "noattribs.csv")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file, coords=[:x, :y])
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1

  # GSLIB
  file = joinpath(savedir, "noattribs.gslib")
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1

  # VTK
  file = joinpath(savedir, "noattribs.vts")
  gtb1 = georef(nothing, CartesianGrid(10, 10))
  GeoIO.save(file, gtb1)
  gtb2 = GeoIO.load(file)
  @test isnothing(values(gtb2))
  @test gtb2 == gtb1

  # MSH
  gtb = GeoIO.load(joinpath(datadir, "tetrahedron1.msh"))
  mesh = gtb.geometry
  file = joinpath(savedir, "noattribs.msh")
  gtb1 = georef(nothing, mesh)
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
