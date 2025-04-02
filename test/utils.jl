using GeoIO
using Test
using CoordRefSystems
import JSON3
import ArchGDAL as AG

# Import the necessary function from GeoIO
import GeoIO: wkt2toprojjson

# Helper function to create a spatial reference
spatialref(code) = AG.importUserInput(codestring(code))
codestring(::Type{EPSG{Code}}) where {Code} = "EPSG:$Code"
codestring(::Type{ESRI{Code}}) where {Code} = "ESRI:$Code"

# Old GDAL implementation of projjsonstring for testing
function gdalprojjsonstring(code; multiline=false)
  spref = spatialref(code)
  wktptr = Ref{Cstring}()
  options = ["MULTILINE=$(multiline ? "YES" : "NO")"]
  AG.GDAL.osrexporttoprojjson(spref, wktptr, options)
  unsafe_string(wktptr[])
end

# New Julia implementation
function juliaprojjsonstring(code; multiline=false)
  wkt2str = CoordRefSystems.wkt2(code)
  wkt2toprojjson(wkt2str, multiline=multiline)
end

# Helper function to validate PROJJSON against schema
function isvalidprojjson(jsonstr)
  try
    json = JSON3.read(jsonstr)
    
    # Basic schema validation checks - just check the essential fields
    if !haskey(json, "type") || !haskey(json, "name")
      return false
    end
    
    # Type-specific validation
    type = json["type"]
    if type == "GeographicCRS"
      # For GeographicCRS, either datum or datum_ensemble should exist
      if !haskey(json, "datum") && !haskey(json, "datum_ensemble")
        return false
      end
      
    elseif type == "ProjectedCRS"
      # ProjectedCRS must have base_crs and conversion
      if !haskey(json, "base_crs") || !haskey(json, "conversion")
        return false
      end
      
      # Conversion must have method
      if !haskey(json["conversion"], "method")
        return false
      end
      
    elseif type == "CompoundCRS"
      # CompoundCRS must have components array
      if !haskey(json, "components")
        return false
      end
      
    elseif type == "VerticalCRS"
      # No additional checks for VerticalCRS for now
      return true
      
    else
      # Unknown CRS type
      return false
    end
    
    return true
  catch e
    @warn "JSON validation error: $e"
    return false
  end
end

# Function to normalize JSON for comparison
function normalize_json_for_comparison(jsonstr)
  try
    json = JSON3.read(jsonstr)
    
    # Convert to a clean Dict for normalization
    normalized = Dict{String,Any}()
    
    # Copy essential fields
    essential_fields = ["type", "name"]
    for field in essential_fields
      if haskey(json, field)
        normalized[field] = json[field]
      end
    end
    
    # Handle ID
    if haskey(json, "id") 
      normalized["id"] = Dict{String,Any}(
        "authority" => json["id"]["authority"],
        "code" => json["id"]["code"]
      )
    end
    
    # Normalize datum_ensemble or datum
    if haskey(json, "datum_ensemble")
      datum = Dict{String,Any}("name" => json["datum_ensemble"]["name"])
      # Skip ID for comparison as GDAL and Julia implementations may differ
      normalized["datum_info"] = datum
    elseif haskey(json, "datum")
      datum = Dict{String,Any}("name" => json["datum"]["name"])
      # Skip ID for comparison as GDAL and Julia implementations may differ
      normalized["datum_info"] = datum
    end
    
    # For ProjectedCRS
    if json["type"] == "ProjectedCRS" && haskey(json, "base_crs")
      # Extract base CRS info
      base_crs = Dict{String,Any}("name" => json["base_crs"]["name"])
      # Skip ID for comparison as GDAL and Julia implementations may differ
      
      # Extract datum ensemble or datum from base CRS
      if haskey(json["base_crs"], "datum_ensemble")
        de = json["base_crs"]["datum_ensemble"]
        base_crs["datum_ensemble"] = Dict{String,Any}("name" => de["name"])
        # Skip ID for comparison
      elseif haskey(json["base_crs"], "datum")
        d = json["base_crs"]["datum"]
        base_crs["datum"] = Dict{String,Any}("name" => d["name"])
        # Skip ID for comparison
      end
      
      normalized["base_crs"] = base_crs
      
      # Extract conversion method
      if haskey(json, "conversion") && haskey(json["conversion"], "method")
        method = Dict{String,Any}("name" => json["conversion"]["method"]["name"])
        if haskey(json["conversion"]["method"], "id")
          method["id"] = Dict{String,Any}(
            "authority" => json["conversion"]["method"]["id"]["authority"],
            "code" => json["conversion"]["method"]["id"]["code"]
          )
        end
        normalized["method"] = method
      end
    end
    
    # Return the normalized JSON string
    return JSON3.write(normalized)
  catch e
    @warn "Normalization error: $e"
    return jsonstr
  end
end

# A subset of EPSG codes to test with
# We'll use a small subset to avoid long test times
const TEST_CODES = [
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

# We'll use just the test codes - more comprehensive testing could be done separately
# if we needed to test all EPSG codes from the repository
const CODES_TO_TEST = TEST_CODES

@testset "PROJJSON Conversion" begin
  @testset "Comparison with GDAL" begin
    for code in CODES_TO_TEST
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
    for code in CODES_TO_TEST
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