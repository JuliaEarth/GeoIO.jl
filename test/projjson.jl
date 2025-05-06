epsgcodes = [
  # GEOGCRS
  4326,  # WGS 84
  4269,  # NAD83
  4171, 4207, 4274, 4668, 8237, 8249,4275,4674,4746,8086,8255,
  # GEOD CRS
  10176, 4988, 9988, 10297,
  
  # PROJ CRS
  3857,  # Web Mercator
  2193,  # NZGD2000 / New Zealand Transverse Mercator
  32631, # WGS 84 / UTM zone 31N
  3003,  # Monte Mario / Italy zone 1
  5514,  # S-JTSK / Krovak East North
  6933,  # WGS 84 / NSIDC EASE-Grid 2.0 North
  3035   # ETRS89 / LAEA Europe
]

  
wktdicts = GeoIO.epsg2wktdict.(epsgcodes); crstypes = GeoIO.get_main_key.(wktdicts)
crs_structs = [(code = c, wktdict = w, type = t) for (c, w, t) in zip(epsgcodes, wktdicts, crstypes)]

# TODO: remove failfast, for debugging
@testset "WKT2 -> PROJJSON" failfast=false begin

@testset for type in [:GEOGCRS, :GEODCRS, :PROJCRS]
  filterd_crs =  filter(crs -> crs.type == type, crs_structs)
  
  @testset "code = $(crs.code)" for crs in filterd_crs
    jsondict = GeoIO.wktdict2jsondict(crs.wktdict)
    ourjson = jsondict |> json_round_trip
    
    @test isvalidprojjson(ourjson)
    
    gdaljson = gdalprojjsondict(EPSG{crs.code})
    diff = test_diff_json(gdaljson, ourjson)
    res = @test isempty(diff)
    if res isa Test.Fail 
      diff_json(gdaljson, ourjson) |> show
    end
  end
  
end
end
