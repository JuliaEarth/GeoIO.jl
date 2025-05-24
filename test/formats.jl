@testset "Supported formats" begin
  io = IOBuffer()
  exts = [".ply", ".kml", ".gslib", ".shp", ".geojson", ".parquet", ".gpkg", ".png", ".jpg", ".jpeg", ".tif", ".tiff"]

  GeoIO.formats(io)
  iostr = String(take!(io))
  @test all(occursin(iostr), exts)

  GeoIO.formats(io, sortby=:load)
  iostr = String(take!(io))
  @test all(occursin(iostr), exts)

  GeoIO.formats(io, sortby=:save)
  iostr = String(take!(io))
  @test all(occursin(iostr), exts)

  # throws
  @test_throws ArgumentError GeoIO.formats(sortby=:test)
end
