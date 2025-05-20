@testset "projjson" begin
  jsonstr = GeoIO.projjsonstring(EPSG{4326})
  @test isvalidprojjson(JSON3.read(jsonstr))
  
  epsgcodes = Int[
    # https://github.com/JuliaEarth/CoordRefSystems.jl/blob/10b3f944ece7d5c4669eed6dc163ae8d9761afcd/src/get.jl
    2157, 2193, 3035, 3310, 3395, 3857, 4171, 4207, 4208, 4230, 4231, 4267, 4269, 4274, 4275, 4277,
    4314, 4326, 4618, 4659, 4666, 4668, 4674, 4745, 4746, 4988, 4989, 5070, 5324, 5527, 8086, 8232,
    8237, 8240, 8246, 8249, 8252, 8255, 9777, 9782, 9988, 10176, 10414, 25832, 27700, 28355, 29903,
    # 32662,  # deprecated in 2008, https://github.com/JuliaEarth/CoordRefSystems.jl/issues/262
    2180, 32600, 32700,
    
    # WKT strings with non-standard measurment units
    3407,
    # WKT projjson with base_crs.datum.prime_meridian
    31288,
    # WKT projjson with coordinate_system.axis[1].meridian
    2986,
  ]

  # This is to organize the tests by CRS type for ease of debugging
  wktdicts = GeoIO.epsg2wktdict.(epsgcodes)
  crstypes = GeoIO.rootkey.(wktdicts)
  crsstructs = [(code=c, type=t, wkt=w) for (c, t, w) in zip(epsgcodes, crstypes, wktdicts)]

  @testset for type in [:GEOGCRS, :GEODCRS, :PROJCRS]
    filterdcrs = filter(crs -> crs.type == type, crsstructs)

    @testset "code = $(crs.code)" for crs in filterdcrs
      ourjson = GeoIO.wkt2json(crs.wkt) |> jsonroundtrip
      @test isvalidprojjson(ourjson)
      gdaljson = gdalprojjsondict(EPSG{crs.code})
      @test isempty(deltaprojjson(gdaljson, ourjson))
    end
  end
end
