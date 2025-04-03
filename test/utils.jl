@testset "WKT2 -> PROJJSON" begin
  epsgcodes = [
    4326,  # WGS 84
    3857,  # Web Mercator
    4269,  # NAD83
    2193,  # NZGD2000 / New Zealand Transverse Mercator
    32631, # WGS 84 / UTM zone 31N
    3003,  # Monte Mario / Italy zone 1
    5514,  # S-JTSK / Krovak East North
    6933,  # WGS 84 / NSIDC EASE-Grid 2.0 North
    3035   # ETRS89 / LAEA Europe
  ]

  for code in epsgcodes
    projjson = GeoIO.projjsonstring(EPSG{code})

    # test against schema
    @test isvalidprojjson(projjson)

    # test against GDAL
    gdaljson = gdalprojjsonstring(EPSG{code})
    @test projjson == gdaljson
  end
end 
