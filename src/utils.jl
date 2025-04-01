# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# helper type alias
const Met{T} = Quantity{T,u"𝐋",typeof(u"m")}
const Deg{T} = Quantity{T,NoDims,typeof(u"°")}

# return the default length unit if not set
lengthunit(u) = isnothing(u) ? m : u

function asgeotable(table)
  crs = GI.crs(table)
  cols = Tables.columns(table)
  names = Tables.columnnames(cols)
  gcol = geomcolumn(names)
  vars = setdiff(names, [gcol])
  etable = isempty(vars) ? nothing : (; (v => Tables.getcolumn(cols, v) for v in vars)...)
  geoms = Tables.getcolumn(cols, gcol)
  domain = geom2meshes.(geoms, Ref(crs))
  georef(etable, domain)
end

# helper function to find the
# geometry column of a table
function geomcolumn(names)
  snames = string.(names)
  gnames = ["geometry", "geom", "shape"]
  gnames = [gnames; uppercase.(gnames); uppercasefirst.(gnames); [""]]
  select = findfirst(∈(snames), gnames)
  if isnothing(select)
    throw(ErrorException("geometry column not found"))
  else
    Symbol(gnames[select])
  end
end

# add "_" to `name` until it is unique compared to the table `names`
function uniquename(names, name)
  uname = name
  while uname ∈ names
    uname = Symbol(uname, :_)
  end
  uname
end

# make `newnames` unique compared to the table `names`
function uniquenames(names, newnames)
  map(newnames) do name
    uniquename(names, name)
  end
end

# GDAL implementation (kept for reference)
function gdal_projjsonstring(code; multiline=false)
  spref = spatialref(code)
  wktptr = Ref{Cstring}()
  options = ["MULTILINE=$(multiline ? "YES" : "NO")"]
  GDAL.osrexporttoprojjson(spref, wktptr, options)
  unsafe_string(wktptr[])
end

function projjsonstring(code; multiline=false)
  # Get WKT2 string from CoordRefSystems
  wkt2_str = CoordRefSystems.wkt2(code)
  
  # Convert WKT2 to PROJJSON
  wkt2_to_projjson(wkt2_str, multiline)
end

# Helper function to parse a WKT token and its content
function parse_wkt_node(str, pos=1)
  # Skip whitespace
  while pos <= length(str) && isspace(str[pos])
    pos += 1
  end
  
  # Check for end of input
  pos > length(str) && return nothing, pos
  
  # Detect quoted string
  if str[pos] == '"'
    endpos = findnext('"', str, pos+1)
    while endpos !== nothing && endpos+1 <= length(str) && str[endpos+1] == '"'
      # Handle escaped quotes
      endpos = findnext('"', str, endpos+2)
    end
    endpos === nothing && error("Unclosed quote in WKT string")
    return str[pos+1:endpos-1], endpos+1
  end
  
  # Detect keyword/node
  if isuppercase(str[pos])
    # Find keyword
    keyword_end = pos
    while keyword_end <= length(str) && (isalnum(str[keyword_end]) || str[keyword_end] == '_')
      keyword_end += 1
    end
    keyword = str[pos:keyword_end-1]
    
    # Find opening bracket
    bracket_pos = findnext('[', str, keyword_end)
    bracket_pos === nothing && error("Expected opening bracket after keyword $keyword")
    
    # Parse content within brackets
    content = []
    pos = bracket_pos + 1
    
    while pos <= length(str) && str[pos] != ']'
      # Parse the node or value
      node, next_pos = parse_wkt_node(str, pos)
      node !== nothing && push!(content, node)
      pos = next_pos
      
      # Skip commas and whitespace
      while pos <= length(str) && (isspace(str[pos]) || str[pos] == ',')
        pos += 1
      end
    end
    
    # Move past closing bracket
    pos = pos <= length(str) ? pos + 1 : pos
    
    return (keyword, content), pos
  end
  
  # Parse number
  if isdigit(str[pos]) || str[pos] == '-' || str[pos] == '.'
    num_end = pos
    while num_end <= length(str) && (isdigit(str[num_end]) || str[num_end] == '.' || str[num_end] == '-' || 
                                     str[num_end] == '+' || str[num_end] == 'e' || str[num_end] == 'E')
      num_end += 1
    end
    numstr = str[pos:num_end-1]
    if '.' in numstr || 'e' in lowercase(numstr)
      return parse(Float64, numstr), num_end
    else
      return parse(Int, numstr), num_end
    end
  end
  
  # Unknown token
  error("Unexpected character in WKT string at position $pos: $(str[pos])")
end

# Convert a WKT node to PROJJSON
function wkt_node_to_projjson(node)
  if isa(node, Tuple) && length(node) == 2 && isa(node[1], AbstractString)
    # This is a node with keyword and content
    keyword, content = node
    
    # Process based on keyword
    if keyword == "GEOGCRS"
      return geographic_crs_to_projjson(content)
    elseif keyword == "PROJCRS"
      return projected_crs_to_projjson(content)
    elseif keyword == "GEODCRS"
      return geodetic_crs_to_projjson(content)
    elseif keyword == "VERTCRS"
      return vertical_crs_to_projjson(content)
    elseif keyword == "COMPOUNDCRS"
      return compound_crs_to_projjson(content)
    elseif keyword == "BOUNDCRS"
      return bound_crs_to_projjson(content)
    elseif keyword == "DATUM"
      return datum_to_projjson(content)
    elseif keyword == "ENSEMBLE"
      return datum_ensemble_to_projjson(content)
    elseif keyword == "ELLIPSOID"
      return ellipsoid_to_projjson(content)
    elseif keyword == "CS"
      return cs_to_projjson(content)
    elseif keyword == "AXIS"
      return axis_to_projjson(content)
    elseif keyword == "ANGLEUNIT" || keyword == "LENGTHUNIT"
      return unit_to_projjson(content, keyword)
    elseif keyword == "ID"
      return id_to_projjson(content)
    elseif keyword == "PARAMETER"
      return parameter_to_projjson(content)
    elseif keyword == "CONVERSION"
      return conversion_to_projjson(content)
    else
      # Return a simple object with the keyword and content for debugging
      return Dict("keyword" => keyword, "content" => [isa(c, Tuple) ? wkt_node_to_projjson(c) : c for c in content])
    end
  elseif isa(node, AbstractString) || isa(node, Number)
    # Simple value
    return node
  else
    error("Unexpected node type: $(typeof(node))")
  end
end

# Conversion functions for specific CRS types
function geographic_crs_to_projjson(content)
  json = Dict{String, Any}(
    "type" => "GeographicCRS",
    "name" => isa(content[1], AbstractString) ? content[1] : "Unknown"
  )
  
  # Process other items
  for i in 2:length(content)
    if isa(content[i], Tuple) && length(content[i]) == 2
      keyword, subcontent = content[i]
      
      if keyword == "DATUM"
        json["datum"] = datum_to_projjson(subcontent)
      elseif keyword == "ENSEMBLE"
        json["datum_ensemble"] = datum_ensemble_to_projjson(subcontent)
      elseif keyword == "CS"
        json["coordinate_system"] = cs_to_projjson(subcontent)
      elseif keyword == "ID"
        json["id"] = id_to_projjson(subcontent)
      end
    end
  end
  
  return json
end

function geodetic_crs_to_projjson(content)
  json = Dict{String, Any}(
    "type" => "GeodeticCRS",
    "name" => isa(content[1], AbstractString) ? content[1] : "Unknown"
  )
  
  # Process similar to geographic CRS
  for i in 2:length(content)
    if isa(content[i], Tuple) && length(content[i]) == 2
      keyword, subcontent = content[i]
      
      if keyword == "DATUM"
        json["datum"] = datum_to_projjson(subcontent)
      elseif keyword == "ENSEMBLE"
        json["datum_ensemble"] = datum_ensemble_to_projjson(subcontent)
      elseif keyword == "CS"
        json["coordinate_system"] = cs_to_projjson(subcontent)
      elseif keyword == "ID"
        json["id"] = id_to_projjson(subcontent)
      end
    end
  end
  
  return json
end

function projected_crs_to_projjson(content)
  json = Dict{String, Any}(
    "type" => "ProjectedCRS",
    "name" => isa(content[1], AbstractString) ? content[1] : "Unknown"
  )
  
  # Process projected CRS components
  for i in 2:length(content)
    if isa(content[i], Tuple) && length(content[i]) == 2
      keyword, subcontent = content[i]
      
      if keyword == "BASEGEOGCRS"
        json["base_crs"] = geographic_crs_to_projjson(subcontent)
      elseif keyword == "CONVERSION"
        json["conversion"] = conversion_to_projjson(subcontent)
      elseif keyword == "CS"
        json["coordinate_system"] = cs_to_projjson(subcontent)
      elseif keyword == "ID"
        json["id"] = id_to_projjson(subcontent)
      end
    end
  end
  
  return json
end

function vertical_crs_to_projjson(content)
  json = Dict{String, Any}(
    "type" => "VerticalCRS",
    "name" => isa(content[1], AbstractString) ? content[1] : "Unknown"
  )
  
  for i in 2:length(content)
    if isa(content[i], Tuple) && length(content[i]) == 2
      keyword, subcontent = content[i]
      
      if keyword == "VDATUM"
        json["datum"] = Dict(
          "type" => "VerticalReferenceFrame",
          "name" => isa(subcontent[1], AbstractString) ? subcontent[1] : "Unknown"
        )
      elseif keyword == "CS"
        json["coordinate_system"] = cs_to_projjson(subcontent)
      elseif keyword == "ID"
        json["id"] = id_to_projjson(subcontent)
      end
    end
  end
  
  return json
end

function compound_crs_to_projjson(content)
  json = Dict{String, Any}(
    "type" => "CompoundCRS",
    "name" => isa(content[1], AbstractString) ? content[1] : "Unknown",
    "components" => []
  )
  
  # Extract components
  for i in 2:length(content)
    if isa(content[i], Tuple) && length(content[i]) == 2
      component = wkt_node_to_projjson(content[i])
      push!(json["components"], component)
    elseif isa(content[i], Tuple) && content[i][1] == "ID"
      json["id"] = id_to_projjson(content[i][2])
    end
  end
  
  return json
end

function bound_crs_to_projjson(content)
  json = Dict{String, Any}(
    "type" => "BoundCRS"
  )
  
  # Process BoundCRS components
  for i in 1:length(content)
    if isa(content[i], Tuple) && length(content[i]) == 2
      keyword, subcontent = content[i]
      
      if keyword == "SOURCE"
        json["source_crs"] = wkt_node_to_projjson(subcontent[1])
      elseif keyword == "TARGET"
        json["target_crs"] = wkt_node_to_projjson(subcontent[1])
      elseif keyword == "ABRIDGEDTRANSFORMATION"
        json["transformation"] = Dict(
          "name" => isa(subcontent[1], AbstractString) ? subcontent[1] : "Unknown"
        )
      end
    end
  end
  
  return json
end

function datum_to_projjson(content)
  json = Dict{String, Any}(
    "type" => "GeodeticReferenceFrame",
    "name" => isa(content[1], AbstractString) ? content[1] : "Unknown"
  )
  
  for i in 2:length(content)
    if isa(content[i], Tuple) && length(content[i]) == 2
      keyword, subcontent = content[i]
      
      if keyword == "ELLIPSOID"
        json["ellipsoid"] = ellipsoid_to_projjson(subcontent)
      elseif keyword == "ID"
        json["id"] = id_to_projjson(subcontent)
      end
    end
  end
  
  return json
end

function datum_ensemble_to_projjson(content)
  json = Dict{String, Any}(
    "name" => isa(content[1], AbstractString) ? content[1] : "Unknown",
    "members" => []
  )
  
  for i in 2:length(content)
    if isa(content[i], Tuple) && length(content[i]) == 2
      keyword, subcontent = content[i]
      
      if keyword == "MEMBER"
        member = Dict{String, Any}(
          "name" => isa(subcontent[1], AbstractString) ? subcontent[1] : "Unknown"
        )
        
        # Check for ID in the MEMBER
        for j in 2:length(subcontent)
          if isa(subcontent[j], Tuple) && subcontent[j][1] == "ID"
            member["id"] = id_to_projjson(subcontent[j][2])
          end
        end
        
        push!(json["members"], member)
      elseif keyword == "ELLIPSOID"
        json["ellipsoid"] = ellipsoid_to_projjson(subcontent)
      elseif keyword == "ENSEMBLEACCURACY"
        json["accuracy"] = string(subcontent[1])
      elseif keyword == "ID"
        json["id"] = id_to_projjson(subcontent)
      end
    end
  end
  
  return json
end

function ellipsoid_to_projjson(content)
  name = isa(content[1], AbstractString) ? content[1] : "Unknown"
  
  # Get semi-major axis and inverse flattening
  semi_major_axis = nothing
  inverse_flattening = nothing
  
  if length(content) >= 3
    semi_major_axis = isa(content[2], Number) ? content[2] : nothing
    inverse_flattening = isa(content[3], Number) ? content[3] : nothing
  end
  
  json = Dict{String, Any}(
    "name" => name
  )
  
  if semi_major_axis !== nothing
    json["semi_major_axis"] = semi_major_axis
  end
  
  if inverse_flattening !== nothing
    json["inverse_flattening"] = inverse_flattening
  end
  
  return json
end

function cs_to_projjson(content)
  subtype = lowercase(string(content[1]))
  dimension = isa(content[2], Number) ? content[2] : 2
  
  json = Dict{String, Any}(
    "subtype" => subtype,
    "axis" => []
  )
  
  # Extract axes from CS content
  for i in 3:length(content)
    if isa(content[i], Tuple) && content[i][1] == "AXIS"
      push!(json["axis"], axis_to_projjson(content[i][2]))
    end
  end
  
  return json
end

function axis_to_projjson(content)
  name = isa(content[1], AbstractString) ? content[1] : "Unknown"
  direction = isa(content[2], AbstractString) ? lowercase(content[2]) : "unknown"
  
  json = Dict{String, Any}(
    "name" => name,
    "direction" => direction
  )
  
  # Extract abbreviation if present (typically in parentheses in the name)
  m = match(r"(.+)\s*\((.+)\)", name)
  if m !== nothing
    json["name"] = strip(m.captures[1])
    json["abbreviation"] = strip(m.captures[2])
  end
  
  # Process unit information
  for i in 3:length(content)
    if isa(content[i], Tuple)
      keyword = content[i][1]
      subcontent = content[i][2]
      
      if keyword == "ANGLEUNIT" || keyword == "LENGTHUNIT"
        unit_type = lowercase(replace(keyword, "UNIT" => ""))
        json["unit"] = unit_type
      end
    end
  end
  
  return json
end

function unit_to_projjson(content, keyword)
  name = isa(content[1], AbstractString) ? content[1] : "Unknown"
  conversion_factor = isa(content[2], Number) ? content[2] : nothing
  
  unit_type = lowercase(replace(string(keyword), "UNIT" => ""))
  
  json = Dict{String, Any}(
    "type" => unit_type,
    "name" => name
  )
  
  if conversion_factor !== nothing
    json["conversion_factor"] = conversion_factor
  end
  
  # Extract ID if present
  for i in 3:length(content)
    if isa(content[i], Tuple) && content[i][1] == "ID"
      json["id"] = id_to_projjson(content[i][2])
    end
  end
  
  return json
end

function id_to_projjson(content)
  if length(content) >= 2
    authority = isa(content[1], AbstractString) ? content[1] : "Unknown"
    code = content[2]
    
    return Dict{String, Any}(
      "authority" => authority,
      "code" => code
    )
  end
  
  return Dict{String, Any}("authority" => "Unknown", "code" => 0)
end

function parameter_to_projjson(content)
  name = isa(content[1], AbstractString) ? content[1] : "Unknown"
  value = isa(content[2], Number) ? content[2] : 0
  
  json = Dict{String, Any}(
    "name" => name,
    "value" => value
  )
  
  # Extract unit and ID if present
  for i in 3:length(content)
    if isa(content[i], Tuple)
      keyword = content[i][1]
      subcontent = content[i][2]
      
      if keyword == "ANGLEUNIT" || keyword == "LENGTHUNIT"
        unit_type = lowercase(replace(keyword, "UNIT" => ""))
        json["unit"] = unit_type
      elseif keyword == "ID"
        json["id"] = id_to_projjson(subcontent)
      end
    end
  end
  
  return json
end

function conversion_to_projjson(content)
  name = isa(content[1], AbstractString) ? content[1] : "Unknown"
  
  json = Dict{String, Any}(
    "name" => name,
    "method" => Dict{String, Any}(),
    "parameters" => []
  )
  
  # Process conversion components
  for i in 2:length(content)
    if isa(content[i], Tuple)
      keyword = content[i][1]
      subcontent = content[i][2]
      
      if keyword == "METHOD"
        method_name = isa(subcontent[1], AbstractString) ? subcontent[1] : "Unknown"
        json["method"]["name"] = method_name
        
        # Extract ID if present
        for j in 2:length(subcontent)
          if isa(subcontent[j], Tuple) && subcontent[j][1] == "ID"
            json["method"]["id"] = id_to_projjson(subcontent[j][2])
          end
        end
      elseif keyword == "PARAMETER"
        push!(json["parameters"], parameter_to_projjson(subcontent))
      end
    end
  end
  
  return json
end

function wkt2_to_projjson(wkt2_str::AbstractString, multiline=false)
  # Parse the WKT string into a tree
  node, _ = parse_wkt_node(wkt2_str)
  
  if node === nothing
    error("Failed to parse WKT string")
  end
  
  # Convert the tree to PROJJSON
  json = wkt_node_to_projjson(node)
  
  # Add the schema reference
  json["\$schema"] = "https://proj.org/schemas/v0.4/projjson.schema.json"
  
  # Convert to JSON string
  indent = multiline ? 2 : 0
  return JSON3.write(json, indent)
end

spatialref(code) = AG.importUserInput(codestring(code))

codestring(::Type{EPSG{Code}}) where {Code} = "EPSG:$Code"
codestring(::Type{ESRI{Code}}) where {Code} = "ESRI:$Code"

function projjsoncode(json)
  id = json["id"]
  code = Int(id["code"])
  authority = id["authority"]
  if authority == "EPSG"
    EPSG{code}
  elseif authority == "ESRI"
    ESRI{code}
  else
    throw(ArgumentError("unsupported authority '$authority' in ProjJSON"))
  end
end

function projjsoncode(jsonstr::AbstractString)
  json = JSON3.read(jsonstr)
  projjsoncode(json)
end

function projjson(CRS)
  try
    code = CoordRefSystems.code(CRS)
    jsonstr = projjsonstring(code)
    json = JSON3.read(jsonstr, Dict)
    GFT.ProjJSON(json)
  catch
    nothing
  end
end

function geojson(CRS)
  try
    code = CoordRefSystems.code(CRS)
    GFT.GeoJSON(CoordRefSystems.wkt2(code))
  catch
    nothing
  end
end
