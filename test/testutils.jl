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

# Helper function to validate PROJJSON against schema
function isvalidprojjson(jsonstr)
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
end
