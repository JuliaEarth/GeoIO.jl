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

@testset "projjsonstring used codes" failfast=false begin
  
  epsgcodes = Int[  
    # https://github.com/JuliaEarth/CoordRefSystems.jl/blob/10b3f944ece7d5c4669eed6dc163ae8d9761afcd/src/get.jl
    2157, 2193, 3035, 3310, 3395, 3857, 4171, 4207, 4208, 4230, 4231, 4267, 4269, 4274, 4275, 4277, 
    4314, 4326, 4618, 4659, 4666, 4668, 4674, 4745, 4746, 4988, 4989, 5070, 5324, 5527, 8086, 8232,
    8237, 8240, 8246, 8249, 8252, 8255, 9777, 9782, 9988, 10176, 10414, 25832, 27700, 28355, 29903,       
    # 32662,  # deprecated in 2008, https://github.com/JuliaEarth/CoordRefSystems.jl/issues/262
    2180, 32600, 32700,
    
    # WKT strings with non-standard measurment units
    27573, 3407,
    # WKT projjson with base_crs.datum.prime_meridian
    31288, 
    ]
  @test GeoIO.projjsonstring.(epsgcodes) isa Vector{String}
  
end
# This is only to organize the tests by CRS type for ease of debugging
wktdicts = GeoIO.epsg2wktdict.(epsgcodes)
crstypes = GeoIO.get_main_key.(wktdicts)
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
    res = @test isempty(delta_keys(gdaljson, ourjson))
    # res = @test isempty(delta_paths(gdaljson, ourjson))
    # if res isa Test.Fail 
      # projjson_diff(gdaljson, ourjson) |> show
    # end
  end
  
end
end
