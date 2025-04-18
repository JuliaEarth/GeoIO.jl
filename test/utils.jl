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

  # Helper function to remove metadata fields
  function remove_metadata(obj)
    filtered = Dict{String,Any}()
    for (k, v) in pairs(obj)
      key = String(k)  # Convert Symbol to String
      if key ∉ ["area", "bbox", "scope"]
        if v isa AbstractDict
          filtered[key] = remove_metadata(v)
        elseif v isa Vector
          filtered[key] = [x isa AbstractDict ? remove_metadata(x) : x for x in v]
        else
          filtered[key] = v
        end
      end
    end
    filtered
  end

  for code in epsgcodes
    # Get both JSON strings with pretty printing
    projjson = GeoIO.projjsonstring(EPSG{code}, multiline=true)
    gdaljson = gdalprojjsonstring(EPSG{code}, multiline=true)

    # Parse both to objects and remove metadata
    proj_obj = remove_metadata(JSON3.read(projjson))
    gdal_obj = remove_metadata(JSON3.read(gdaljson))

    # test against schema
    @test isvalidprojjson(projjson)

    # Compare structures and provide detailed error message
    if proj_obj != gdal_obj
      # Find differences
      diff_keys = String[]
      for key in union(keys(proj_obj), keys(gdal_obj))
        if !haskey(proj_obj, key)
          push!(diff_keys, "Missing in ours: $key")
        elseif !haskey(gdal_obj, key)
          push!(diff_keys, "Extra in ours: $key")
        elseif proj_obj[key] != gdal_obj[key]
          push!(diff_keys, "Different value for $key:")
          push!(diff_keys, "  Ours:  $(proj_obj[key])")
          push!(diff_keys, "  GDAL:  $(gdal_obj[key])")
        end
      end
      
      # Print detailed differences
      println("\nDifferences for EPSG:$code:")
      for diff in diff_keys
        println(diff)
      end
      println("\nOur JSON:")
      println(projjson)
      println("\nGDAL JSON:")
      println(gdaljson)
    end

    @test proj_obj == gdal_obj
  end
end 
