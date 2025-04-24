epsgcodes = [
  # GEOGCRS
  4326,  # WGS 84
  4269,  # NAD83
  
  # GEOD CRS
  10176, 4988, 9988,
  
  # PROJ CRS
  3857,  # Web Mercator
  2193,  # NZGD2000 / New Zealand Transverse Mercator
  32631, # WGS 84 / UTM zone 31N
  3003,  # Monte Mario / Italy zone 1
  5514,  # S-JTSK / Krovak East North
  6933,  # WGS 84 / NSIDC EASE-Grid 2.0 North
  3035   # ETRS89 / LAEA Europe
]



@testset "WKT2 -> PROJJSON" begin

  @testset "code = $(crs)" for crs in epsgcodes
    jsondict = GeoIO.projjsonstring(EPSG{crs})
    ourjson = jsondict |> JSON3.read
    
    @test isvalidprojjson(ourjson)
    
  end
  
end
