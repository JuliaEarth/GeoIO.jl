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

function projjsonstring(code; multiline=false)
  wkt2str = CoordRefSystems.wkt2(code)
  wkt2_to_projjson(wkt2str, multiline=multiline)
end

# Constants for WKT2 to PROJJSON conversion
const DEG_TO_RAD = π / 180

function wkt2_to_projjson(wkt2str; multiline=false)
  # For now, let's implement a basic parser that handles common CRS types
  # First identify the type of CRS
  if startswith(wkt2str, "GEOGCRS")
    return parse_geogcrs(wkt2str, multiline=multiline)
  elseif startswith(wkt2str, "PROJCRS")
    return parse_projcrs(wkt2str, multiline=multiline)
  elseif startswith(wkt2str, "COMPOUNDCRS")
    return parse_compoundcrs(wkt2str, multiline=multiline)
  elseif startswith(wkt2str, "VERTCRS")
    return parse_vertcrs(wkt2str, multiline=multiline)
  else
    # For unsupported types, try a generic approach
    return parse_geogcrs(wkt2str, multiline=multiline)
  end
end

function parse_geogcrs(wkt2str; multiline=false)
  # Create a basic GeographicCRS PROJJSON structure
  # Extract key components from the WKT2 string
  
  # Extract name using regex
  name_match = match(r"GEOGCRS\[\"([^\"]+)\"", wkt2str)
  name = name_match !== nothing ? name_match.captures[1] : "Unknown"
  
  # Build PROJJSON with essential components
  json = Dict{String,Any}(
    "\$schema" => "https://proj.org/schemas/v0.7/projjson.schema.json",
    "type" => "GeographicCRS",
    "name" => name
  )
  
  # Extract datum ensemble or datum
  if contains(wkt2str, "ENSEMBLE")
    # Handle datum ensemble
    ensemble_match = match(r"ENSEMBLE\[\"([^\"]+)\"", wkt2str)
    if ensemble_match !== nothing
      json["datum_ensemble"] = Dict{String,Any}(
        "name" => ensemble_match.captures[1],
        "members" => []
      )
      
      # Extract members
      member_matches = collect(eachmatch(r"MEMBER\[\"([^\"]+)\".*?ID\[\"EPSG\",(\d+)\]", wkt2str))
      for m in member_matches
        push!(json["datum_ensemble"]["members"], Dict{String,Any}(
          "name" => m.captures[1],
          "id" => Dict{String,Any}(
            "authority" => "EPSG",
            "code" => parse(Int, m.captures[2])
          )
        ))
      end
      
      # Extract ellipsoid
      ellipsoid_match = match(r"ELLIPSOID\[\"([^\"]+)\",(\d+\.?\d*),(\d+\.?\d*)", wkt2str)
      if ellipsoid_match !== nothing
        json["datum_ensemble"]["ellipsoid"] = Dict{String,Any}(
          "name" => ellipsoid_match.captures[1],
          "semi_major_axis" => parse(Float64, ellipsoid_match.captures[2]),
          "inverse_flattening" => parse(Float64, ellipsoid_match.captures[3])
        )
      end
      
      # Extract accuracy
      accuracy_match = match(r"ENSEMBLEACCURACY\[(\d+\.?\d*)\]", wkt2str)
      if accuracy_match !== nothing
        json["datum_ensemble"]["accuracy"] = accuracy_match.captures[1]
      end
      
      # Extract ID of the datum ensemble
      ensemble_id_match = match(r"ENSEMBLE\[.*?ID\[\"EPSG\",(\d+)\]\]", wkt2str)
      if ensemble_id_match !== nothing
        json["datum_ensemble"]["id"] = Dict{String,Any}(
          "authority" => "EPSG",
          "code" => parse(Int, ensemble_id_match.captures[1])
        )
      end
    end
  elseif contains(wkt2str, "DATUM")
    # Handle datum
    datum_match = match(r"DATUM\[\"([^\"]+)\"", wkt2str)
    if datum_match !== nothing
      json["datum"] = Dict{String,Any}(
        "type" => "GeodeticReferenceFrame",
        "name" => datum_match.captures[1]
      )
      
      # Extract ellipsoid
      ellipsoid_match = match(r"ELLIPSOID\[\"([^\"]+)\",(\d+\.?\d*),(\d+\.?\d*)", wkt2str)
      if ellipsoid_match !== nothing
        json["datum"]["ellipsoid"] = Dict{String,Any}(
          "name" => ellipsoid_match.captures[1],
          "semi_major_axis" => parse(Float64, ellipsoid_match.captures[2]),
          "inverse_flattening" => parse(Float64, ellipsoid_match.captures[3])
        )
      end
    end
  end
  
  # Extract coordinate system
  json["coordinate_system"] = Dict{String,Any}(
    "subtype" => "ellipsoidal",
    "axis" => []
  )
  
  # Extract axis information
  axis_matches = collect(eachmatch(r"AXIS\[\"([^\"]+)\"\s*,\s*(\w+)\]", wkt2str))
  for (i, m) in enumerate(axis_matches)
    axis_name = m.captures[1]
    axis_direction = m.captures[2]
    
    # Extract abbreviation if present in the format "Name (Abbrev)"
    name_parts = match(r"(.*)\s*\((.*)\)", axis_name)
    name = name_parts !== nothing ? name_parts.captures[1] : axis_name
    abbrev = name_parts !== nothing ? name_parts.captures[2] : ""
    
    # Convert first character to lowercase for PROJJSON
    if !isempty(name)
      name = lowercase(name[1]) * name[2:end]
    end
    
    push!(json["coordinate_system"]["axis"], Dict{String,Any}(
      "name" => name,
      "abbreviation" => abbrev,
      "direction" => lowercase(axis_direction),
      "unit" => "degree"
    ))
  end
  
  # Extract CRS ID
  crs_id_match = match(r"ID\[\"EPSG\",(\d+)\]\]$", wkt2str)
  if crs_id_match !== nothing
    json["id"] = Dict{String,Any}(
      "authority" => "EPSG",
      "code" => parse(Int, crs_id_match.captures[1])
    )
  end
  
  # Return JSON string
  if multiline
    return JSON3.write(json, indent=2, allow_inf=true)
  else
    return JSON3.write(json, allow_inf=true)
  end
end

function parse_projcrs(wkt2str; multiline=false)
  # Extract basic information about the projected CRS
  name_match = match(r"PROJCRS\[\"([^\"]+)\"", wkt2str)
  name = name_match !== nothing ? name_match.captures[1] : "Unknown"
  
  # Create the basic structure
  json = Dict{String,Any}(
    "\$schema" => "https://proj.org/schemas/v0.7/projjson.schema.json",
    "type" => "ProjectedCRS",
    "name" => name
  )
  
  # Extract base CRS information
  basegeog_match = match(r"BASEGEOGCRS\[\"([^\"]+)\"", wkt2str)
  if basegeog_match !== nothing
    json["base_crs"] = Dict{String,Any}(
      "type" => "GeographicCRS",
      "name" => basegeog_match.captures[1],
      "coordinate_system" => Dict{String,Any}(
        "subtype" => "ellipsoidal",
        "axis" => []
      )
    )
    
    # Extract base CRS datum or datum ensemble
    if contains(wkt2str, "ENSEMBLE")
      # Handle datum ensemble
      ensemble_match = match(r"ENSEMBLE\[\"([^\"]+)\"", wkt2str)
      if ensemble_match !== nothing
        json["base_crs"]["datum_ensemble"] = Dict{String,Any}(
          "name" => ensemble_match.captures[1],
          "members" => []
        )
        
        # Extract members
        member_matches = collect(eachmatch(r"MEMBER\[\"([^\"]+)\".*?ID\[\"EPSG\",(\d+)\]", wkt2str))
        for m in member_matches
          push!(json["base_crs"]["datum_ensemble"]["members"], Dict{String,Any}(
            "name" => m.captures[1],
            "id" => Dict{String,Any}(
              "authority" => "EPSG",
              "code" => parse(Int, m.captures[2])
            )
          ))
        end
        
        # Extract ellipsoid
        ellipsoid_match = match(r"ELLIPSOID\[\"([^\"]+)\",(\d+\.?\d*),(\d+\.?\d*)", wkt2str)
        if ellipsoid_match !== nothing
          json["base_crs"]["datum_ensemble"]["ellipsoid"] = Dict{String,Any}(
            "name" => ellipsoid_match.captures[1],
            "semi_major_axis" => parse(Float64, ellipsoid_match.captures[2]),
            "inverse_flattening" => parse(Float64, ellipsoid_match.captures[3])
          )
        end
      end
    elseif contains(wkt2str, "DATUM")
      # Handle datum
      datum_match = match(r"DATUM\[\"([^\"]+)\"", wkt2str)
      if datum_match !== nothing
        json["base_crs"]["datum"] = Dict{String,Any}(
          "type" => "GeodeticReferenceFrame",
          "name" => datum_match.captures[1]
        )
        
        # Extract ellipsoid
        ellipsoid_match = match(r"ELLIPSOID\[\"([^\"]+)\",(\d+\.?\d*),(\d+\.?\d*)", wkt2str)
        if ellipsoid_match !== nothing
          json["base_crs"]["datum"]["ellipsoid"] = Dict{String,Any}(
            "name" => ellipsoid_match.captures[1],
            "semi_major_axis" => parse(Float64, ellipsoid_match.captures[2]),
            "inverse_flattening" => parse(Float64, ellipsoid_match.captures[3])
          )
        end
      end
    end
    
    # Extract base CRS ID
    base_id_match = match(r"BASEGEOGCRS\[.*?ID\[\"EPSG\",(\d+)\]", wkt2str)
    if base_id_match !== nothing
      json["base_crs"]["id"] = Dict{String,Any}(
        "authority" => "EPSG",
        "code" => parse(Int, base_id_match.captures[1])
      )
    end
  end
  
  # Extract conversion information
  conversion_match = match(r"CONVERSION\[\"([^\"]+)\"", wkt2str)
  if conversion_match !== nothing
    json["conversion"] = Dict{String,Any}(
      "name" => conversion_match.captures[1],
      "method" => Dict{String,Any}(),
      "parameters" => []
    )
    
    # Extract method
    method_match = match(r"METHOD\[\"([^\"]+)\"", wkt2str)
    if method_match !== nothing
      json["conversion"]["method"]["name"] = method_match.captures[1]
      
      # Extract method ID if available
      method_id_match = match(r"METHOD\[.*?ID\[\"EPSG\",(\d+)\]", wkt2str)
      if method_id_match !== nothing
        json["conversion"]["method"]["id"] = Dict{String,Any}(
          "authority" => "EPSG",
          "code" => parse(Int, method_id_match.captures[1])
        )
      end
    end
    
    # Extract parameters
    param_matches = collect(eachmatch(r"PARAMETER\[\"([^\"]+)\",(\d+\.?\d*)", wkt2str))
    for m in param_matches
      param = Dict{String,Any}(
        "name" => m.captures[1],
        "value" => parse(Float64, m.captures[2]),
        "unit" => "metre"  # Default unit, would need to be extracted properly
      )
      push!(json["conversion"]["parameters"], param)
    end
  end
  
  # Extract coordinate system
  json["coordinate_system"] = Dict{String,Any}(
    "subtype" => "Cartesian",
    "axis" => []
  )
  
  # Extract axis information
  axis_matches = collect(eachmatch(r"AXIS\[\"([^\"]+)\"\s*,\s*(\w+)\]", wkt2str))
  for (i, m) in enumerate(axis_matches[end-1:end])  # Usually last 2 axes for projected CRS
    axis_name = m.captures[1]
    axis_direction = m.captures[2]
    
    # Extract abbreviation if present in the format "Name (Abbrev)"
    name_parts = match(r"(.*)\s*\((.*)\)", axis_name)
    name = name_parts !== nothing ? name_parts.captures[1] : axis_name
    abbrev = name_parts !== nothing ? name_parts.captures[2] : ""
    
    # Convert first character to lowercase for PROJJSON
    if !isempty(name)
      name = lowercase(name[1]) * name[2:end]
    end
    
    push!(json["coordinate_system"]["axis"], Dict{String,Any}(
      "name" => name,
      "abbreviation" => abbrev,
      "direction" => lowercase(axis_direction),
      "unit" => "metre"
    ))
  end
  
  # Extract CRS ID
  crs_id_match = match(r"ID\[\"EPSG\",(\d+)\]\]$", wkt2str)
  if crs_id_match !== nothing
    json["id"] = Dict{String,Any}(
      "authority" => "EPSG",
      "code" => parse(Int, crs_id_match.captures[1])
    )
  end
  
  # Return JSON string
  if multiline
    return JSON3.write(json, indent=2, allow_inf=true)
  else
    return JSON3.write(json, allow_inf=true)
  end
end

function parse_compoundcrs(wkt2str; multiline=false)
  # Extract basic information
  name_match = match(r"COMPOUNDCRS\[\"([^\"]+)\"", wkt2str)
  name = name_match !== nothing ? name_match.captures[1] : "Unknown"
  
  # Create basic structure
  json = Dict{String,Any}(
    "\$schema" => "https://proj.org/schemas/v0.7/projjson.schema.json",
    "type" => "CompoundCRS",
    "name" => name,
    "components" => []
  )
  
  # For a more complete implementation, we'd need to parse the components
  # This would involve complex recursion or pattern matching
  
  # Extract CRS ID
  crs_id_match = match(r"ID\[\"EPSG\",(\d+)\]\]$", wkt2str)
  if crs_id_match !== nothing
    json["id"] = Dict{String,Any}(
      "authority" => "EPSG",
      "code" => parse(Int, crs_id_match.captures[1])
    )
  end
  
  if multiline
    return JSON3.write(json, indent=2, allow_inf=true)
  else
    return JSON3.write(json, allow_inf=true)
  end
end

function parse_vertcrs(wkt2str; multiline=false)
  # Extract basic information
  name_match = match(r"VERTCRS\[\"([^\"]+)\"", wkt2str)
  name = name_match !== nothing ? name_match.captures[1] : "Unknown"
  
  # Create basic structure
  json = Dict{String,Any}(
    "\$schema" => "https://proj.org/schemas/v0.7/projjson.schema.json",
    "type" => "VerticalCRS",
    "name" => name
  )
  
  # Extract vertical datum
  vdatum_match = match(r"VDATUM\[\"([^\"]+)\"", wkt2str)
  if vdatum_match !== nothing
    json["datum"] = Dict{String,Any}(
      "type" => "VerticalReferenceFrame",
      "name" => vdatum_match.captures[1]
    )
    
    # Extract datum ID
    vdatum_id_match = match(r"VDATUM\[.*?ID\[\"EPSG\",(\d+)\]", wkt2str)
    if vdatum_id_match !== nothing
      json["datum"]["id"] = Dict{String,Any}(
        "authority" => "EPSG",
        "code" => parse(Int, vdatum_id_match.captures[1])
      )
    end
  end
  
  # Extract coordinate system
  json["coordinate_system"] = Dict{String,Any}(
    "subtype" => "vertical",
    "axis" => []
  )
  
  # Extract axis information
  axis_match = match(r"AXIS\[\"([^\"]+)\"\s*,\s*(\w+)\]", wkt2str)
  if axis_match !== nothing
    axis_name = axis_match.captures[1]
    axis_direction = axis_match.captures[2]
    
    # Extract abbreviation if present
    name_parts = match(r"(.*)\s*\((.*)\)", axis_name)
    name = name_parts !== nothing ? name_parts.captures[1] : axis_name
    abbrev = name_parts !== nothing ? name_parts.captures[2] : ""
    
    # Convert first character to lowercase for PROJJSON
    if !isempty(name)
      name = lowercase(name[1]) * name[2:end]
    end
    
    push!(json["coordinate_system"]["axis"], Dict{String,Any}(
      "name" => name,
      "abbreviation" => abbrev,
      "direction" => lowercase(axis_direction),
      "unit" => "metre"
    ))
  end
  
  # Extract CRS ID
  crs_id_match = match(r"ID\[\"EPSG\",(\d+)\]\]$", wkt2str)
  if crs_id_match !== nothing
    json["id"] = Dict{String,Any}(
      "authority" => "EPSG",
      "code" => parse(Int, crs_id_match.captures[1])
    )
  end
  
  if multiline
    return JSON3.write(json, indent=2, allow_inf=true)
  else
    return JSON3.write(json, allow_inf=true)
  end
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
    wkt2str = CoordRefSystems.wkt2(CRS)
    jsonstr = wkt2_to_projjson(wkt2str)
    json = JSON3.read(jsonstr, Dict)
    GFT.ProjJSON(json)
  catch e
    @warn "Failed to convert to PROJJSON: $e"
    nothing
  end
end
