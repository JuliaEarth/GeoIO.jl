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
  wkt2toprojjson(wkt2str, multiline=multiline)
end

# Helper function to extract units from WKT2 string
function extractunit(wkt2str, unittype)
  # Match unit pattern: UNITTYPE["name", factor, ID["EPSG", code]]
  pattern = Regex("$(unittype)\\[\"([^\"]+)\"(?:,\\s*(\\d+\\.?\\d*))?(?:,\\s*ID\\[\"([^\"]+)\",\\s*(\\d+)\\])?\\]")
  unit_match = match(pattern, wkt2str)
  
  if unit_match !== nothing
    unit_name = unit_match.captures[1]
    # Default factor is 1.0 if not specified
    unit_factor = unit_match.captures[2] !== nothing ? parse(Float64, unit_match.captures[2]) : 1.0
    
    # Build unit dictionary
    unit_dict = Dict{String,Any}(
      "name" => unit_name,
      "conversion_factor" => unit_factor
    )
    
    # Add ID if present
    if unit_match.captures[3] !== nothing && unit_match.captures[4] !== nothing
      unit_dict["id"] = Dict{String,Any}(
        "authority" => unit_match.captures[3],
        "code" => parse(Int, unit_match.captures[4])
      )
    end
    
    return unit_dict
  end
  
  # Standard default units by type if not found explicitly
  unit_defaults = Dict(
    "LENGTHUNIT" => Dict{String,Any}("name" => "metre", "conversion_factor" => 1.0),
    "ANGLEUNIT" => Dict{String,Any}("name" => "degree", "conversion_factor" => 0.0174532925199433),
    "SCALEUNIT" => Dict{String,Any}("name" => "unity", "conversion_factor" => 1.0),
    "TIMEUNIT" => Dict{String,Any}("name" => "second", "conversion_factor" => 1.0)
  )
  
  # Return appropriate default or a generic default
  return get(unit_defaults, unittype, Dict{String,Any}("name" => "unknown", "conversion_factor" => 1.0))
end

function wkt2toprojjson(wkt2str; multiline=false)
  # First identify the type of CRS
  if startswith(wkt2str, "GEOGCRS")
    parsegeogcrs(wkt2str, multiline=multiline)
  elseif startswith(wkt2str, "PROJCRS")
    parseprojcrs(wkt2str, multiline=multiline)
  elseif startswith(wkt2str, "COMPOUNDCRS")
    parsecompoundcrs(wkt2str, multiline=multiline)
  elseif startswith(wkt2str, "VERTCRS")
    parsevertcrs(wkt2str, multiline=multiline)
  else
    # For unsupported types, try a generic approach
    parsegeogcrs(wkt2str, multiline=multiline)
  end
end

function parsegeogcrs(wkt2str; multiline=false)
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
      member_matches = collect(eachmatch(r"MEMBER\[\"([^\"]+)\".*?ID\[\"([^\"]+)\",(\d+)\]", wkt2str))
      for m in member_matches
        push!(json["datum_ensemble"]["members"], Dict{String,Any}(
          "name" => m.captures[1],
          "id" => Dict{String,Any}(
            "authority" => m.captures[2],
            "code" => parse(Int, m.captures[3])
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
        
        # Extract ellipsoid units
        ellipsoid_unit = extractunit(wkt2str, "LENGTHUNIT")
        json["datum_ensemble"]["ellipsoid"]["unit"] = ellipsoid_unit
      end
      
      # Extract accuracy
      accuracy_match = match(r"ENSEMBLEACCURACY\[(\d+\.?\d*)\]", wkt2str)
      if accuracy_match !== nothing
        json["datum_ensemble"]["accuracy"] = accuracy_match.captures[1]
      end
      
      # Extract ID of the datum ensemble
      ensemble_id_match = match(r"ENSEMBLE\[.*?ID\[\"([^\"]+)\",(\d+)\]\]", wkt2str)
      if ensemble_id_match !== nothing
        json["datum_ensemble"]["id"] = Dict{String,Any}(
          "authority" => ensemble_id_match.captures[1],
          "code" => parse(Int, ensemble_id_match.captures[2])
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
        
        # Extract ellipsoid units
        ellipsoid_unit = extractunit(wkt2str, "LENGTHUNIT")
        json["datum"]["ellipsoid"]["unit"] = ellipsoid_unit
      end
      
      # Extract datum ID
      datum_id_match = match(r"DATUM\[.*?ID\[\"([^\"]+)\",(\d+)\]", wkt2str)
      if datum_id_match !== nothing
        json["datum"]["id"] = Dict{String,Any}(
          "authority" => datum_id_match.captures[1],
          "code" => parse(Int, datum_id_match.captures[2])
        )
      end
    end
  end
  
  # Extract axis information
  axis_matches = collect(eachmatch(r"AXIS\[\"([^\"]+)\"\s*,\s*(\w+)", wkt2str))
  
  # Determine coordinate system subtype
  cs_type = extractcstype(wkt2str)
  if cs_type === nothing
    cs_type = determinecsstype(axis_matches)
  end
  
  # Create coordinate system
  json["coordinate_system"] = Dict{String,Any}(
    "subtype" => cs_type,
    "axis" => []
  )
  
  # Extract angle unit for the coordinate system
  cs_unit = extractunit(wkt2str, "ANGLEUNIT")
  
  # Process axes
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
    
    # Determine axis unit based on direction and type
    axis_unit = cs_unit
    if lowercase(axis_direction) == "up" || lowercase(axis_direction) == "down" || 
       lowercase(axis_direction) == "height" || lowercase(axis_direction) == "depth"
      # Height axis typically uses length unit
      axis_unit = extractunit(wkt2str, "LENGTHUNIT")
    end
    
    push!(json["coordinate_system"]["axis"], Dict{String,Any}(
      "name" => name,
      "abbreviation" => abbrev,
      "direction" => lowercase(axis_direction),
      "unit" => axis_unit
    ))
  end
  
  # Extract CRS ID
  crs_id_match = match(r"ID\[\"([^\"]+)\",(\d+)\]\]$", wkt2str)
  if crs_id_match !== nothing
    json["id"] = Dict{String,Any}(
      "authority" => crs_id_match.captures[1],
      "code" => parse(Int, crs_id_match.captures[2])
    )
  end
  
  # Return JSON string
  if multiline
    JSON3.write(json, indent=2, allow_inf=true)
  else
    JSON3.write(json, allow_inf=true)
  end
end

function parseprojcrs(wkt2str; multiline=false)
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
    # Extract base CRS axis information
    base_axis_matches = collect(eachmatch(r"AXIS\[\"([^\"]+)\"\s*,\s*(\w+)", wkt2str))
    base_axes = base_axis_matches[1:min(2, length(base_axis_matches))]
    
    # Determine base CRS coordinate system subtype
    base_cs_type = extractcstype(wkt2str)
    if base_cs_type === nothing
      base_cs_type = determinecsstype(base_axes)
    end
    
    json["base_crs"] = Dict{String,Any}(
      "type" => "GeographicCRS",
      "name" => basegeog_match.captures[1],
      "coordinate_system" => Dict{String,Any}(
        "subtype" => base_cs_type,
        "axis" => []
      )
    )
    
    # Extract angle unit for the base coordinate system
    base_cs_unit = extractunit(wkt2str, "ANGLEUNIT")
    
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
        member_matches = collect(eachmatch(r"MEMBER\[\"([^\"]+)\".*?ID\[\"([^\"]+)\",(\d+)\]", wkt2str))
        for m in member_matches
          push!(json["base_crs"]["datum_ensemble"]["members"], Dict{String,Any}(
            "name" => m.captures[1],
            "id" => Dict{String,Any}(
              "authority" => m.captures[2],
              "code" => parse(Int, m.captures[3])
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
          
          # Extract ellipsoid units
          ellipsoid_unit = extractunit(wkt2str, "LENGTHUNIT")
          json["base_crs"]["datum_ensemble"]["ellipsoid"]["unit"] = ellipsoid_unit
        end
        
        # Extract ensemble ID
        ensemble_id_match = match(r"ENSEMBLE\[.*?ID\[\"([^\"]+)\",(\d+)\]\]", wkt2str)
        if ensemble_id_match !== nothing
          json["base_crs"]["datum_ensemble"]["id"] = Dict{String,Any}(
            "authority" => ensemble_id_match.captures[1],
            "code" => parse(Int, ensemble_id_match.captures[2])
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
          
          # Extract ellipsoid units
          ellipsoid_unit = extractunit(wkt2str, "LENGTHUNIT")
          json["base_crs"]["datum"]["ellipsoid"]["unit"] = ellipsoid_unit
        end
        
        # Extract datum ID
        datum_id_match = match(r"DATUM\[.*?ID\[\"([^\"]+)\",(\d+)\]", wkt2str)
        if datum_id_match !== nothing
          json["base_crs"]["datum"]["id"] = Dict{String,Any}(
            "authority" => datum_id_match.captures[1],
            "code" => parse(Int, datum_id_match.captures[2])
          )
        end
      end
    end
    
    # Extract base CRS ID
    base_id_match = match(r"BASEGEOGCRS\[.*?ID\[\"([^\"]+)\",(\d+)\]", wkt2str)
    if base_id_match !== nothing
      json["base_crs"]["id"] = Dict{String,Any}(
        "authority" => base_id_match.captures[1],
        "code" => parse(Int, base_id_match.captures[2])
      )
    end
    
    # Process base CRS axes
    if !isempty(base_axes)  # We have base CRS axes
      for m in base_axes
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
        
        # Determine axis unit based on direction and type
        axis_unit = base_cs_unit
        if lowercase(axis_direction) == "up" || lowercase(axis_direction) == "down" || 
           lowercase(axis_direction) == "height" || lowercase(axis_direction) == "depth"
          # Height axis typically uses length unit
          axis_unit = extractunit(wkt2str, "LENGTHUNIT")
        end
        
        push!(json["base_crs"]["coordinate_system"]["axis"], Dict{String,Any}(
          "name" => name,
          "abbreviation" => abbrev,
          "direction" => lowercase(axis_direction),
          "unit" => axis_unit
        ))
      end
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
      method_id_match = match(r"METHOD\[.*?ID\[\"([^\"]+)\",(\d+)\]", wkt2str)
      if method_id_match !== nothing
        json["conversion"]["method"]["id"] = Dict{String,Any}(
          "authority" => method_id_match.captures[1],
          "code" => parse(Int, method_id_match.captures[2])
        )
      end
    end
    
    # Extract parameters with their units
    param_pattern = r"PARAMETER\[\"([^\"]+)\",\s*([^,]+)(?:,\s*(LENGTHUNIT|ANGLEUNIT|SCALEUNIT)\[([^\]]+)\])?"
    param_matches = collect(eachmatch(param_pattern, wkt2str))
    
    for m in param_matches
      param_name = m.captures[1]
      param_value = parse(Float64, m.captures[2])
      
      param = Dict{String,Any}(
        "name" => param_name,
        "value" => param_value
      )
      
      # Extract unit if specified
      if m.captures[3] !== nothing
        unit_type = m.captures[3]
        unit_section = "$(unit_type)$(m.captures[4])"
        
        # Get the appropriate pattern based on the unit type
        if unit_type == "LENGTHUNIT"
          param["unit"] = extractunit(unit_section, "LENGTHUNIT")
        elseif unit_type == "ANGLEUNIT"
          param["unit"] = extractunit(unit_section, "ANGLEUNIT")
        elseif unit_type == "SCALEUNIT"
          param["unit"] = extractunit(unit_section, "SCALEUNIT")
        end
      else
        # Infer unit type based on parameter name
        param_name_lower = lowercase(param_name)
        if contains(param_name_lower, "angle") || 
           contains(param_name_lower, "longitude") || 
           contains(param_name_lower, "latitude") ||
           contains(param_name_lower, "azimuth") ||
           contains(param_name_lower, "rotation")
          param["unit"] = extractunit(wkt2str, "ANGLEUNIT")
        elseif contains(param_name_lower, "scale") ||
              contains(param_name_lower, "factor")
          param["unit"] = extractunit(wkt2str, "SCALEUNIT")
        else
          param["unit"] = extractunit(wkt2str, "LENGTHUNIT")
        end
      end
      
      push!(json["conversion"]["parameters"], param)
    end
  end
  
  # Extract all axes for the projected CRS
  all_axis_matches = collect(eachmatch(r"AXIS\[\"([^\"]+)\"\s*,\s*(\w+)", wkt2str))
  
  # Extract projected CRS axes - typically the last 2 or 3 axes
  proj_axes = length(all_axis_matches) > 2 ? all_axis_matches[3:end] : all_axis_matches
  
  # Determine projected CRS coordinate system subtype
  proj_cs_type = extractcstype(wkt2str)
  if proj_cs_type === nothing
    proj_cs_type = determinecsstype(proj_axes)
  end
  
  # Extract coordinate system
  json["coordinate_system"] = Dict{String,Any}(
    "subtype" => proj_cs_type,
    "axis" => []
  )
  
  # Extract length unit for projected coordinate system
  proj_cs_unit = extractunit(wkt2str, "LENGTHUNIT")
  
  # Process projected CRS axes
  for m in proj_axes
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
      "unit" => proj_cs_unit
    ))
  end
  
  # Extract CRS ID
  crs_id_match = match(r"ID\[\"([^\"]+)\",(\d+)\]\]$", wkt2str)
  if crs_id_match !== nothing
    json["id"] = Dict{String,Any}(
      "authority" => crs_id_match.captures[1],
      "code" => parse(Int, crs_id_match.captures[2])
    )
  end
  
  # Return JSON string
  if multiline
    JSON3.write(json, indent=2, allow_inf=true)
  else
    JSON3.write(json, allow_inf=true)
  end
end

function parsecompoundcrs(wkt2str; multiline=false)
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
  
  # Extract component CRSs
  # This is a complex process as we need to identify where each component starts and ends
  # using bracket balancing
  
  # Helper function to extract balanced WKT section
  function extract_balanced_section(text, start_idx)
    # Find opening bracket
    open_idx = findnext('[', text, start_idx)
    if open_idx === nothing
      return nothing, 0
    end
    
    # Count brackets to ensure we have a balanced section
    bracket_count = 1
    pos = open_idx + 1
    while bracket_count > 0 && pos <= length(text)
      if text[pos] == '['
        bracket_count += 1
      elseif text[pos] == ']'
        bracket_count -= 1
      end
      pos += 1
    end
    
    # If brackets are balanced, return the section
    if bracket_count == 0
      return SubString(text, start_idx, pos - 1), pos
    else
      return nothing, 0
    end
  end
  
  # Find positions of all component CRSs
  component_types = ["GEOGCRS", "PROJCRS", "VERTCRS", "TIMECRS", "ENGINEERINGCRS", "PARAMETRICCRS", "DERIVEDPROJCRS", "GEODCRS"]
  
  # Skip the COMPOUNDCRS part itself
  pos = 1
  compound_section, pos = extract_balanced_section(wkt2str, pos)
  
  while pos < length(wkt2str)
    # Find next component type
    start_type = nothing
    start_pos = length(wkt2str) + 1
    
    for crs_type in component_types
      type_pos = findnext(crs_type, wkt2str, pos)
      if type_pos !== nothing && type_pos < start_pos
        start_type = crs_type
        start_pos = type_pos
      end
    end
    
    if start_type === nothing
      break
    end
    
    # Extract the balanced section for this component
    component_wkt, next_pos = extract_balanced_section(wkt2str, start_pos)
    
    if component_wkt !== nothing
      # Now parse the component based on its type
      if startswith(component_wkt, "GEOGCRS")
        component_json = JSON3.read(parsegeogcrs(component_wkt), Dict{String,Any})
        push!(json["components"], component_json)
      elseif startswith(component_wkt, "PROJCRS")
        component_json = JSON3.read(parseprojcrs(component_wkt), Dict{String,Any})
        push!(json["components"], component_json)
      elseif startswith(component_wkt, "VERTCRS")
        component_json = JSON3.read(parsevertcrs(component_wkt), Dict{String,Any})
        push!(json["components"], component_json)
      elseif startswith(component_wkt, "TIMECRS")
        # Implement a basic TimeCRS parser
        name_match = match(r"TIMECRS\[\"([^\"]+)\"", component_wkt)
        time_name = name_match !== nothing ? name_match.captures[1] : "Time component"
        time_crs = Dict{String,Any}(
          "type" => "TimeCRS",
          "name" => time_name,
          "coordinate_system" => Dict{String,Any}(
            "subtype" => "temporal",
            "axis" => []
          )
        )
        
        # Extract time datum if present
        time_datum_match = match(r"TDATUM\[\"([^\"]+)\"", component_wkt)
        if time_datum_match !== nothing
          time_crs["datum"] = Dict{String,Any}(
            "type" => "TimeReferenceFrame",
            "name" => time_datum_match.captures[1]
          )
        end
        
        # Extract axis information
        axis_match = match(r"AXIS\[\"([^\"]+)\"\s*,\s*(\w+)", component_wkt)
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
          
          # Time unit
          time_unit = extractunit(component_wkt, "TIMEUNIT")
          
          push!(time_crs["coordinate_system"]["axis"], Dict{String,Any}(
            "name" => name,
            "abbreviation" => abbrev,
            "direction" => lowercase(axis_direction),
            "unit" => time_unit
          ))
        end
        
        # Extract CRS ID if present
        time_id_match = match(r"ID\[\"([^\"]+)\",(\d+)\]", component_wkt)
        if time_id_match !== nothing
          time_crs["id"] = Dict{String,Any}(
            "authority" => time_id_match.captures[1],
            "code" => parse(Int, time_id_match.captures[2])
          )
        end
        
        push!(json["components"], time_crs)
      else
        # Generic placeholder for other CRS types
        push!(json["components"], Dict{String,Any}(
          "type" => "Unknown",
          "name" => "Unsupported component"
        ))
      end
    end
    
    # Move to the next component
    pos = next_pos
  end
  
  # Extract CRS ID
  crs_id_match = match(r"ID\[\"([^\"]+)\",(\d+)\]\]$", wkt2str)
  if crs_id_match !== nothing
    json["id"] = Dict{String,Any}(
      "authority" => crs_id_match.captures[1],
      "code" => parse(Int, crs_id_match.captures[2])
    )
  end
  
  if multiline
    JSON3.write(json, indent=2, allow_inf=true)
  else
    JSON3.write(json, allow_inf=true)
  end
end

function parsevertcrs(wkt2str; multiline=false)
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
    vdatum_id_match = match(r"VDATUM\[.*?ID\[\"([^\"]+)\",(\d+)\]", wkt2str)
    if vdatum_id_match !== nothing
      json["datum"]["id"] = Dict{String,Any}(
        "authority" => vdatum_id_match.captures[1],
        "code" => parse(Int, vdatum_id_match.captures[2])
      )
    end
  end
  
  # Extract axis information
  axis_matches = collect(eachmatch(r"AXIS\[\"([^\"]+)\"\s*,\s*(\w+)", wkt2str))
  
  # Determine coordinate system subtype
  cs_type = extractcstype(wkt2str)
  if cs_type === nothing
    cs_type = determinecsstype(axis_matches)
  end
  
  # Extract coordinate system - override with "vertical" for VerticalCRS if not already vertical
  if cs_type != "vertical"
    cs_type = "vertical"
  end
  
  json["coordinate_system"] = Dict{String,Any}(
    "subtype" => cs_type,
    "axis" => []
  )
  
  # Extract length unit for the vertical coordinate system
  vert_cs_unit = extractunit(wkt2str, "LENGTHUNIT")
  
  # Process axis information
  for m in axis_matches
    axis_name = m.captures[1]
    axis_direction = m.captures[2]
    
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
      "unit" => vert_cs_unit
    ))
  end
  
  # Extract CRS ID
  crs_id_match = match(r"ID\[\"([^\"]+)\",(\d+)\]\]$", wkt2str)
  if crs_id_match !== nothing
    json["id"] = Dict{String,Any}(
      "authority" => crs_id_match.captures[1],
      "code" => parse(Int, crs_id_match.captures[2])
    )
  end
  
  if multiline
    JSON3.write(json, indent=2, allow_inf=true)
  else
    JSON3.write(json, allow_inf=true)
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
    jsonstr = wkt2toprojjson(wkt2str)
    json = JSON3.read(jsonstr, Dict)
    GFT.ProjJSON(json)
  catch e
    @warn "Failed to convert to PROJJSON: $e"
    nothing
  end
end

# Helper function to determine the coordinate system subtype based on axis count and direction
function determinecsstype(axis_matches)
  # No axes defined
  if isempty(axis_matches)
    return "unknown"
  end
  
  # Count axes
  num_axes = length(axis_matches)
  
  # Extract directions
  directions = [lowercase(m.captures[2]) for m in axis_matches]
  
  # Handle common cases
  if num_axes == 2 || num_axes == 3
    # Check for typical Cartesian system
    if all(d in ["east", "north", "up"] for d in directions) || 
       all(d in ["west", "south", "down"] for d in directions) ||
       all(d in ["south", "west", "down"] for d in directions) ||
       all(d in ["north", "east", "up"] for d in directions)
      return "Cartesian"
    end
    
    # Check for ellipsoidal system
    if all(d in ["north", "east", "up"] for d in directions) ||
       all(d in ["south", "west", "down"] for d in directions) ||
       all(d in ["latitude", "longitude", "height"] for d in directions) ||
       all(d in ["longitude", "latitude", "height"] for d in directions)
      return "ellipsoidal"
    end
  end
  
  # Single axis cases
  if num_axes == 1
    direction = directions[1]
    if direction in ["up", "down", "height", "depth"]
      return "vertical"
    elseif direction in ["future", "past"]
      return "temporal"
    end
  end
  
  # Default to cartesian if we can't determine
  return "Cartesian"
end

# Extract CS subtype directly from the WKT string if specified
function extractcstype(wkt2str)
  # Try to find explicit CS type
  cs_type_match = match(r"CS\[\"([^\"]+)\"", wkt2str)
  if cs_type_match !== nothing
    cs_type = cs_type_match.captures[1]
    # Map WKT CS types to PROJJSON subtypes
    type_map = Dict(
      "Cartesian" => "Cartesian",
      "ellipsoidal" => "ellipsoidal",
      "vertical" => "vertical",
      "Spherical" => "spherical",
      "ordinal" => "ordinal",
      "parametric" => "parametric",
      "temporal" => "temporal"
    )
    return get(type_map, cs_type, lowercase(cs_type))
  end
  
  # If not found, return nothing and let caller use axis-based determination
  return nothing
end
