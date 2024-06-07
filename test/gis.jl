@testset "GIS conversion" begin
  fnames = [
    "points.geojson",
    "points.gpkg",
    "points.shp",
    "lines.geojson",
    "lines.gpkg",
    "lines.shp",
    "polygons.geojson",
    "polygons.gpkg",
    "polygons.shp",
    "land.shp",
    "path.shp",
    "zone.shp",
    "issue32.shp"
  ]

  # saved and loaded tables are the same
  for fname in fnames, fmt in [".shp", ".geojson", ".gpkg"]
    # input and output file names
    f1 = joinpath(datadir, fname)
    f2 = joinpath(savedir, replace(fname, "." => "-") * fmt)

    # load and save table
    kwargs = endswith(f1, ".geojson") ? (; numbertype=Float64) : ()
    gt1 = GeoIO.load(f1; fix=false, kwargs...)
    GeoIO.save(f2, gt1)
    kwargs = endswith(f2, ".geojson") ? (; numbertype=Float64) : ()
    gt2 = GeoIO.load(f2; fix=false, kwargs...)

    # compare domain and values
    d1 = domain(gt1)
    d2 = domain(gt2)
    @test _isequal(d1, d2)
    t1 = values(gt1)
    t2 = values(gt2)
    c1 = Tables.columns(t1)
    c2 = Tables.columns(t2)
    n1 = Tables.columnnames(c1)
    n2 = Tables.columnnames(c2)
    @test Set(n1) == Set(n2)
    for n in n1
      x1 = Tables.getcolumn(c1, n)
      x2 = Tables.getcolumn(c2, n)
      @test x1 == x2
    end
  end
end
