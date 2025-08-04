using PrecompileTools

@setup_workload begin
  datadir = joinpath(@__DIR__, "..", "test", "data")
  @compile_workload begin
    load(joinpath(datadir, "points.shp"))
    load(joinpath(datadir, "lines.shp"))
    load(joinpath(datadir, "polygons.shp"))
    load(joinpath(datadir, "points.geojson"))
    load(joinpath(datadir, "lines.geojson"))
    load(joinpath(datadir, "polygons.geojson"))
    load(joinpath(datadir, "points.parquet"))
    load(joinpath(datadir, "lines.parquet"))
    load(joinpath(datadir, "polygons.parquet"))
#    load(joinpath(datadir, "field.kml"))
    load(joinpath(datadir, "points.gpkg"))
    load(joinpath(datadir, "lines.gpkg"))
    load(joinpath(datadir, "polygons.gpkg"))
  end
end
