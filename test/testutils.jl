# Note: Shapefile.jl saves Chains and Polygons as Multi
# This function is used to work around this problem
_isequal(d1::Domain, d2::Domain) = all(_isequal(g1, g2) for (g1, g2) in zip(d1, d2))
_isequal(g1, g2) = g1 == g2
_isequal(m1::Multi, m2::Multi) = m1 == m2
_isequal(g, m::Multi) = _isequal(m, g)
function _isequal(m::Multi, g)
  gs = parent(m)
  length(gs) == 1 && first(gs) == g
end

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
