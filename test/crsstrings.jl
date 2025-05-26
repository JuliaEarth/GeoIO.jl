@testset "PROJJSON" begin
  epsgcodes = [
    # https://github.com/JuliaEarth/CoordRefSystems.jl/blob/10b3f944ece7d5c4669eed6dc163ae8d9761afcd/src/get.jl
    2157, 2193, 3035, 3310, 3395, 3857, 4171, 4207, 4208, 4230, 4231, 4267, 4269, 4274, 4275, 4277,
    4314, 4326, 4618, 4659, 4666, 4668, 4674, 4745, 4746, 4988, 4989, 5070, 5324, 5527, 8086, 8232,
    8237, 8240, 8246, 8249, 8252, 8255, 9777, 9782, 9988, 10176, 10414, 25832, 27700, 28355, 29903,
    # 32662,  # deprecated in 2008, https://github.com/JuliaEarth/CoordRefSystems.jl/issues/262
    2180, 32600, 32700,
    
    # CRS codes with WKT fields that do not occur in the prior codes.
    # These WKT fields are only relavent in special circumstances such
    # as when using custom measurment units.
    2986, # a PROJJSON with coordinate_system.axis[1].meridian
    3407, # a PROJJSON with non-standard units ("Clarke's foot") requires unit.conversion_factor
    31288, # a PROJJSON with base_crs.datum.prime_meridian
    
    # Additional codes the exhibit edge cases (EC) when comparing our output with GDAL.
    # These edge cases are documented and worked around in the deltaprojjson function.
    # In a way, these codes test our testing functions.
    2157,  # EC#0
    4267,  # EC#1
    22248, # EC#2 
  ]

  # organize tests by CRS type for ease of debugging
  epsgs = [EPSG{code} for code in epsgcodes]
  wktstrs = CoordRefSystems.wkt2.(epsgs)
  wktdicts = GeoIO.wktstr2wktdict.(wktstrs)
  crstypes = GeoIO.rootkey.(wktdicts)
  crstuples = [(code=c, type=t, wkt=w) for (c, t, w) in zip(epsgcodes, crstypes, wktdicts)]

  @testset for type in [:GEOGCRS, :GEODCRS, :PROJCRS]
    filtered = filter(crs -> crs.type == type, crstuples)
    @testset "code = $(crs.code)" for crs in filtered
      ourjson = GeoIO.wkt2json(crs.wkt)
      @test isvalidprojjson(ourjson)
      gdaljson = gdalprojjsondict(EPSG{crs.code})
      @test isempty(deltaprojjson(gdaljson, ourjson))
    end
  end
end
