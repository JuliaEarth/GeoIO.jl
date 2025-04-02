@testset "WKT2 -> PROJJSON" begin
  # A subset of EPSG codes to test with
  # We'll use a small subset to avoid long test times
  codes = [
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

  @testset "Comparison with GDAL" begin
    for code in codes
      @testset "EPSG:$code" begin
        # Test with multiline=false
        projjson1 = gdalprojjsonstring(EPSG{code})
        projjson2 = GeoIO.projjsonstring(EPSG{code})
        
        # Parse and normalize the JSON structures for comparison
        normalized1 = normalize_json_for_comparison(projjson1)
        normalized2 = normalize_json_for_comparison(projjson2)
        
        # Compare normalized JSON strings
        @test normalized1 == normalized2
        
        # Test with multiline=true - check that they're valid
        projjson1 = gdalprojjsonstring(EPSG{code}, multiline=true)
        projjson2 = GeoIO.projjsonstring(EPSG{code}, multiline=true)
        
        @test isvalidprojjson(projjson1)
        @test isvalidprojjson(projjson2)
      end
    end
  end
  
  @testset "Schema Validation" begin
    for code in codes
      @testset "EPSG:$code" begin
        projjson = GeoIO.projjsonstring(EPSG{code})
        @test isvalidprojjson(projjson)
      end
    end
  end
end 
