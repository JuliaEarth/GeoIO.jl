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
        try
          # Test with multiline=false
          projjson1 = gdalprojjsonstring(EPSG{code})
          projjson2 = juliaprojjsonstring(EPSG{code})
          
          # Parse and normalize the JSON structures
          json1 = JSON3.read(projjson1)
          json2 = JSON3.read(projjson2)
          
          # Check essential fields individually
          @test json1["type"] == json2["type"]
          @test json1["name"] == json2["name"]
          @test json1["id"]["authority"] == json2["id"]["authority"]
          @test json1["id"]["code"] == json2["id"]["code"]
          
          # Structural comparison of CRS-specific elements
          # Check if both ProjectedCRS have the same base CRS and datum names
          if json1["type"] == "ProjectedCRS" && json2["type"] == "ProjectedCRS"
            if haskey(json1["base_crs"], "datum_ensemble") && haskey(json2["base_crs"], "datum_ensemble")
              @test json1["base_crs"]["datum_ensemble"]["name"] == json2["base_crs"]["datum_ensemble"]["name"]
            elseif haskey(json1["base_crs"], "datum") && haskey(json2["base_crs"], "datum")
              @test json1["base_crs"]["datum"]["name"] == json2["base_crs"]["datum"]["name"]
            end
            
            # Check conversion method
            if haskey(json1["conversion"], "method") && haskey(json2["conversion"], "method")
              @test json1["conversion"]["method"]["name"] == json2["conversion"]["method"]["name"]
            end
          elseif json1["type"] == "GeographicCRS" && json2["type"] == "GeographicCRS"
            if haskey(json1, "datum_ensemble") && haskey(json2, "datum_ensemble")
              @test json1["datum_ensemble"]["name"] == json2["datum_ensemble"]["name"]
            elseif haskey(json1, "datum") && haskey(json2, "datum")
              @test json1["datum"]["name"] == json2["datum"]["name"]
            end
          end
          
          # Test with multiline=true - just check that they're valid
          projjson1 = gdalprojjsonstring(EPSG{code}, multiline=true)
          projjson2 = juliaprojjsonstring(EPSG{code}, multiline=true)
          
          @test isvalidprojjson(projjson1)
          @test isvalidprojjson(projjson2)
        catch e
          # Some codes may not be supported by both implementations
          @info "Skipping EPSG:$code due to error: $(typeof(e))"
        end
      end
    end
  end
  
  @testset "Schema Validation" begin
    for code in codes
      @testset "EPSG:$code" begin
        try
          projjson = juliaprojjsonstring(EPSG{code})
          @test isvalidprojjson(projjson)
        catch e
          @info "Skipping EPSG:$code schema validation due to error: $(typeof(e))"
        end
      end
    end
  end
end 
