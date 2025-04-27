@testset "wkt to projjson" begin
  supported_epsg_codes = Int[  # https://github.com/JuliaEarth/CoordRefSystems.jl/blob/10b3f944ece7d5c4669eed6dc163ae8d9761afcd/src/get.jl#L42-L107
    2157,
    2193,
    3035,
    3310,
    3395,
    3857,
    4171,
    4207,
    4208,
    4230,
    4231,
    4267,
    4269,
    4274,
    4275,
    4277,
    4314,
    4326,
    4618,
    4659,
    4666,
    4668,
    4674,
    4745,
    4746,
    4988,
    4989,
    5070,
    5324,
    5527,
    8086,
    8232,
    8237,
    8240,
    8246,
    8249,
    8252,
    8255,
    9777,
    9782,
    9988,
    10176,
    10414,
    25832,
    27700,
    28355,
    29903,
    # 32662,  # deprecated in 2008, https://github.com/JuliaEarth/CoordRefSystems.jl/issues/262
    2180,
    (32600 .+ (1:60))...,
    (32700 .+ (1:60))...
  ]
  projjson_json_schema = JSONSchema.Schema(JSON.parsefile(joinpath(datadir, "projjson.schema.json")))
  @testset "PROJJSON JSON Schema compliance" begin
    @testset "code: $code" for code in supported_epsg_codes
      projjson_string = GeoIO.projjsonstring(CoordRefSystems.EPSG{code})
      projjson_json_obj = JSON.parse(projjson_string)
      @test nothing === JSONSchema.validate(projjson_json_schema, projjson_json_obj)
    end
  end
  # TODO: more testing, compare against Proj
end
