# test/wkt2projjson.jl
using GeoIO
using JSON3
using CoordRefSystems
using Test

@testset "WKT2 to PROJJSON" begin
  # Test basic functionality
  @test typeof(GeoIO.projjsonstring(EPSG{4326})) <: String

  # Test common CRS codes
  wgs84_json = GeoIO.projjsonstring(EPSG{4326})
  wgs84_obj = JSON3.read(wgs84_json, Dict)
  @test wgs84_obj["type"] == "GeographicCRS"
  @test wgs84_obj["name"] == "WGS 84"
  @test wgs84_obj["id"]["authority"] == "EPSG"
  @test wgs84_obj["id"]["code"] == 4326

  if hasmethod(CoordRefSystems.get, (Type{EPSG{3857}},))
    mercator_json = GeoIO.projjsonstring(EPSG{3857})
    mercator_obj = JSON3.read(mercator_json, Dict)
    @test mercator_obj["type"] == "ProjectedCRS"
    @test haskey(mercator_obj, "base_crs")
    @test mercator_obj["id"]["code"] == 3857
  end

  if hasmethod(CoordRefSystems.get, (Type{EPSG{32632}},))
    utm_json = GeoIO.projjsonstring(EPSG{32632})
    utm_obj = JSON3.read(utm_json, Dict)
    @test utm_obj["type"] == "ProjectedCRS"
    @test occursin("UTM", utm_obj["name"])
  end

  json_multiline = GeoIO.projjsonstring(EPSG{4326}, multiline=true)
  @test count('\n', json_multiline) > 1
  json_compact = GeoIO.projjsonstring(EPSG{4326}, multiline=false)
  @test count('\n', json_compact) <= 1
end
