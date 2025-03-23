# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

module WKT2ProjJSON

using JSON3

"""
    wkt2_to_projjson(wkt::AbstractString) -> String

Convert a WKT2 string to a PROJJSON string.
"""
function wkt2_to_projjson(wkt::AbstractString)
  wkt_obj = parse_wkt2(wkt)
  projjson_obj = convert_to_projjson(wkt_obj)
  return JSON3.write(projjson_obj)
end

"""
    parse_wkt2(wkt::AbstractString) -> Dict

Parse a WKT2 string into a structured representation.
"""
function parse_wkt2(wkt::AbstractString)
  wkt = strip(wkt)

  open_count = count('[', wkt)
  close_count = count(']', wkt)

  if open_count > close_count
    wkt = wkt * repeat("]", open_count - close_count)
    @warn "Added $(open_count - close_count) missing closing bracket(s)"
  end

  wkt = normalize_wkt(wkt)
  obj, _ = parse_wkt2_node(wkt, 1)
  return obj
end

function parse_wkt2_node(wkt::AbstractString, pos::Int)
  while pos <= length(wkt) && isspace(wkt[pos])
    pos += 1
  end

  if pos > length(wkt)
    error("Unexpected end of WKT string")
  end

  start_pos = pos
  while pos <= length(wkt) && !isspace(wkt[pos]) && wkt[pos] != '['
    pos += 1
  end

  keyword = wkt[start_pos:(pos - 1)]

  while pos <= length(wkt) && isspace(wkt[pos])
    pos += 1
  end

  if pos > length(wkt) || wkt[pos] != '['
    error("Expected '[' after keyword $keyword at position $pos. Context: $(get_context(wkt, pos))")
  end

  pos += 1

  node = Dict{String,Any}("type" => keyword)

  items = []
  while pos <= length(wkt) && wkt[pos] != ']'
    while pos <= length(wkt) && isspace(wkt[pos])
      pos += 1
    end

    if pos > length(wkt) || wkt[pos] == ']'
      break
    end

    if wkt[pos] == '"'
      string_value, new_pos = parse_quoted_string(wkt, pos)
      push!(items, string_value)
      pos = new_pos
    elseif (isdigit(wkt[pos]) || wkt[pos] == '-' || wkt[pos] == '.')
      num_value, new_pos = parse_number(wkt, pos)
      push!(items, num_value)
      pos = new_pos
    elseif wkt[pos] == '['
      child_node, new_pos = parse_wkt2_node(wkt, pos)
      push!(items, child_node)
      pos = new_pos
    else
      start_keyword_pos = pos
      while pos <= length(wkt) && !isspace(wkt[pos]) && wkt[pos] != ',' && wkt[pos] != ']' && wkt[pos] != '['
        pos += 1
      end
      potential_keyword = wkt[start_keyword_pos:(pos - 1)]

      whitespace_pos = pos
      while whitespace_pos <= length(wkt) && isspace(wkt[whitespace_pos])
        whitespace_pos += 1
      end

      if whitespace_pos <= length(wkt) && wkt[whitespace_pos] == '['
        child_node, new_pos = parse_wkt2_node(wkt, start_keyword_pos)
        push!(items, child_node)
        pos = new_pos
      else
        keyword_str = potential_keyword
        push!(items, keyword_str)
        pos = whitespace_pos
      end
    end

    while pos <= length(wkt) && isspace(wkt[pos])
      pos += 1
    end

    if pos <= length(wkt) && wkt[pos] == ','
      pos += 1
    end
  end

  if pos <= length(wkt) && wkt[pos] == ']'
    pos += 1
  else
    error("Expected closing bracket ']' at position $pos. Context: $(get_context(wkt, pos))")
  end

  if keyword == "GEOGCRS" ||
     keyword == "PROJCRS" ||
     keyword == "VERTCRS" ||
     keyword == "GEODCRS" ||
     keyword == "COMPOUNDCRS" ||
     keyword == "BASEGEOGCRS"
    if length(items) > 0
      node["name"] = items[1]
      process_crs_items!(node, keyword, items)
    end
  elseif keyword == "DATUM" || keyword == "VDATUM" || keyword == "EDATUM"
    if length(items) > 0
      node["name"] = items[1]
      process_datum_items!(node, items)
    end
  elseif keyword == "ELLIPSOID"
    if length(items) >= 3
      node["name"] = items[1]
      node["semi_major_axis"] = items[2]
      node["inverse_flattening"] = items[3]
      process_ellipsoid_items!(node, items)
    end
  elseif keyword == "ID"
    if length(items) >= 2
      node["authority"] = items[1]
      node["code"] = typeof(items[2]) <: Number ? items[2] : items[2]
    end
  elseif keyword == "AXIS"
    if length(items) >= 2
      name_abbr = items[1]
      m = match(r"(.*)\s*\((.*)\)", name_abbr)
      if m !== nothing
        node["name"] = strip(m[1])
        node["abbreviation"] = strip(m[2])
      else
        node["name"] = name_abbr
        node["abbreviation"] = ""
      end
      node["direction"] = items[2]
    end
  elseif keyword == "CS"
    if length(items) >= 2
      node["subtype"] = items[1]
      node["dimension"] = items[2]
    end
  elseif keyword == "UNIT" || keyword == "LENGTHUNIT" || keyword == "ANGLEUNIT" || keyword == "SCALEUNIT"
    if length(items) >= 2
      node["name"] = items[1]
      node["conversion_factor"] = items[2]
      if keyword == "LENGTHUNIT"
        node["type"] = "LinearUnit"
      elseif keyword == "ANGLEUNIT"
        node["type"] = "AngularUnit"
      elseif keyword == "SCALEUNIT"
        node["type"] = "ScaleUnit"
      else
        node["type"] = "Unit"
      end
    end
  elseif keyword == "ENSEMBLE"
    if length(items) > 0
      node["name"] = items[1]
      process_ensemble_items!(node, items)
    end
  elseif keyword == "MEMBER"
    if length(items) > 0
      node["name"] = items[1]
      process_member_items!(node, items)
    end
  elseif keyword == "PRIMEM"
    if length(items) >= 2
      node["name"] = items[1]
      node["longitude"] = items[2]
      process_primem_items!(node, items)
    end
  elseif keyword == "METHOD"
    if length(items) >= 1
      node["name"] = items[1]
      process_method_items!(node, items)
    end
  elseif keyword == "PARAMETER"
    if length(items) >= 2
      node["name"] = items[1]
      node["value"] = items[2]
      process_parameter_items!(node, items)
    end
  elseif keyword == "CONVERSION"
    if length(items) >= 1
      node["name"] = items[1]
      process_conversion_items!(node, items)
    end
  elseif keyword == "ENSEMBLEACCURACY"
    if length(items) > 0
      node["value"] = items[1]
    end
  else
    node["items"] = items
  end

  return node, pos
end

function parse_number(wkt::AbstractString, pos::Int)
  start_pos = pos
  while pos <= length(wkt) &&
    (isdigit(wkt[pos]) || wkt[pos] == '.' || wkt[pos] == 'e' || wkt[pos] == 'E' || wkt[pos] == '-' || wkt[pos] == '+')
    pos += 1
  end
  num_str = wkt[start_pos:(pos - 1)]
  if occursin('.', num_str) || occursin('e', lowercase(num_str))
    return parse(Float64, num_str), pos
  else
    return parse(Int, num_str), pos
  end
end

"""
    get_context(wkt::AbstractString, pos::Int, context_size::Int=20) -> String

Get a substring around the specified position to provide context in error messages.
"""
function get_context(wkt::AbstractString, pos::Int, context_size::Int=20)
  start_pos = max(1, pos - context_size)
  end_pos = min(length(wkt), pos + context_size)

  before = wkt[start_pos:min(pos, length(wkt))]
  after = pos < length(wkt) ? wkt[(pos + 1):end_pos] : ""

  return "...$(before)⟨HERE⟩$(after)..."
end

"""
    parse_wkt2_content(wkt::AbstractString, pos::Int) -> Tuple{Array, Int}

Parse WKT2 content starting at position `pos` (after an opening bracket).
Returns the parsed content and the new position.
"""
function parse_wkt2_content(wkt::AbstractString, pos::Int)
  pos += 1

  content = []
  in_string = false
  start_pos = pos
  nesting_level = 0

  while pos <= length(wkt)
    if wkt[pos] == ']' && !in_string && nesting_level == 0
      if start_pos < pos
        token = strip(wkt[start_pos:(pos - 1)])
        if !isempty(token)
          if (token[1] == '"' && token[end] == '"') || (isdigit(token[1]) || token[1] == '-' || token[1] == '.')
            push!(content, parse_primitive(token))
          end
        end
      end
      break
    end

    if wkt[pos] == '"' && (pos == 1 || wkt[pos - 1] != '\\')
      in_string = !in_string
    end

    if !in_string
      if wkt[pos] == '['
        nesting_level += 1
        if nesting_level == 1
          if start_pos < pos
            token = strip(wkt[start_pos:(pos - 1)])
            if !isempty(token)
              keyword = token
              nested_content, new_pos = parse_wkt2_content(wkt, pos)
              push!(content, Dict("type" => keyword, "content" => nested_content))
              pos = new_pos
              start_pos = pos
              continue
            end
          end
        end
      elseif wkt[pos] == ']'
        nesting_level -= 1
      elseif wkt[pos] == ',' && nesting_level == 0
        if start_pos < pos
          token = strip(wkt[start_pos:(pos - 1)])
          if !isempty(token)
            push!(content, parse_primitive(token))
          end
        end
        start_pos = pos + 1
      end
    end

    pos += 1
  end

  if pos <= length(wkt) && wkt[pos] == ']'
    pos += 1
  else
    error("Expected ']' at position $pos")
  end

  return content, pos
end

function parse_primitive(token::AbstractString)
  if token[1] == '"' && token[end] == '"'
    return replace(token[2:(end - 1)], "\"\"" => "\"")
  end

  if isdigit(token[1]) || token[1] == '-' || token[1] == '.'
    if occursin('.', token) || occursin('e', lowercase(token))
      return parse(Float64, token)
    else
      return parse(Int, token)
    end
  end

  return token
end

"""
    find_matching_bracket(wkt::AbstractString, start_pos::Int) -> Int

Find the matching closing bracket for an opening bracket at position `start_pos`.
Returns the position of the closing bracket.
"""
function find_matching_bracket(wkt::AbstractString, start_pos::Int)
  if start_pos > length(wkt) || wkt[start_pos] != '['
    error("Expected '[' at position $start_pos. Context: $(get_context(wkt, start_pos))")
  end

  level = 1
  pos = start_pos + 1
  in_string = false

  while pos <= length(wkt)
    char = wkt[pos]

    if in_string
      if char == '"'
        if pos + 1 <= length(wkt) && wkt[pos + 1] == '"'
          pos += 2
        else
          in_string = false
          pos += 1
        end
      else
        pos += 1
      end
    else
      if char == '"'
        in_string = true
        pos += 1
      elseif char == '['
        level += 1
        pos += 1
      elseif char == ']'
        level -= 1
        if level == 0
          return pos
        end
        pos += 1
      else
        pos += 1
      end
    end
  end

  error(
    "No matching closing bracket found for opening bracket at position $start_pos. Context: $(get_context(wkt, start_pos))"
  )
end

"""
    parse_nested_item(wkt::AbstractString, pos::Int) -> Tuple{Any, Int}

Parse a single item within a nested content section.
"""
function parse_nested_item(wkt::AbstractString, pos::Int)
  while pos <= length(wkt) && isspace(wkt[pos])
    pos += 1
  end

  if pos > length(wkt)
    return nothing, pos
  end

  if wkt[pos] == '"'
    return parse_quoted_string(wkt, pos)
  elseif isdigit(wkt[pos]) || wkt[pos] == '-' || wkt[pos] == '.'
    start_pos = pos
    while pos <= length(wkt) &&
      (isdigit(wkt[pos]) || wkt[pos] == '.' || wkt[pos] == 'e' || wkt[pos] == 'E' || wkt[pos] == '-' || wkt[pos] == '+')
      pos += 1
    end
    num_str = wkt[start_pos:(pos - 1)]
    if occursin('.', num_str) || occursin('e', lowercase(num_str))
      return parse(Float64, num_str), pos
    else
      return parse(Int, num_str), pos
    end
  elseif wkt[pos] == '['
    bracket_end = find_matching_bracket(wkt, pos)
    nested_wkt = wkt[(pos + 1):(bracket_end - 1)]
    nested_items = []
    nested_pos = 1

    while nested_pos <= length(nested_wkt)
      nested_item, new_pos = parse_nested_item(nested_wkt, nested_pos)
      if nested_item !== nothing
        push!(nested_items, nested_item)
      end
      nested_pos = new_pos

      while nested_pos <= length(nested_wkt) && isspace(nested_wkt[nested_pos])
        nested_pos += 1
      end
      if nested_pos <= length(nested_wkt) && nested_wkt[nested_pos] == ','
        nested_pos += 1
      end
    end

    return nested_items, bracket_end + 1
  else
    return parse_wkt2_node(wkt, pos)
  end
end

"""
    normalize_wkt(wkt::AbstractString) -> String

Normalize a WKT string by reducing multiple whitespace characters to a single space,
while preserving the content inside quoted strings.
"""
function normalize_wkt(wkt::AbstractString)
  result = ""
  in_string = false
  i = 1

  while i <= length(wkt)
    if i > length(wkt)
      break
    end

    c = wkt[i]

    if c == '"'
      result *= c
      in_string = !in_string
      i += 1

      if in_string
        while i <= length(wkt)
          c = wkt[i]
          result *= c

          if c == '"'
            if i + 1 <= length(wkt) && wkt[i + 1] == '"'
              result *= wkt[i + 1]
              i += 2
            else
              in_string = false
              i += 1
              break
            end
          else
            i += 1
          end
        end
        continue
      end
    elseif c == '[' || c == ']' || c == ',' || c == '.'
      result *= c
      i += 1
    elseif isspace(c) && !in_string
      result *= ' '
      while i + 1 <= length(wkt) && isspace(wkt[i + 1])
        i += 1
      end
      i += 1
    else
      result *= c
      i += 1
    end
  end

  if in_string
    @warn "Normalized WKT string ended with an unterminated string"
  end

  return result
end

"""
    parse_quoted_string(wkt::AbstractString, start_pos::Int) -> Tuple{String, Int}

Parse a quoted string starting at the specified position.
Returns the parsed string (without quotes) and the position after the closing quote.
"""
function parse_quoted_string(wkt::AbstractString, start_pos::Int)
  if start_pos > length(wkt) || wkt[start_pos] != '"'
    error("Expected '\"' at position $start_pos. Context: $(get_context(wkt, start_pos))")
  end

  result = ""
  pos = start_pos + 1

  while pos <= length(wkt)
    char = wkt[pos]

    if char == '"'
      if pos + 1 <= length(wkt) && wkt[pos + 1] == '"'
        result *= '"'
        pos += 2
      else
        return result, pos + 1
      end
    else
      result *= char
      pos += 1
    end
  end

  error("Unterminated string starting at position $start_pos. Context: $(get_context(wkt, start_pos))")
end

"""
    process_crs_items!(node::Dict, keyword::String, items::Vector)

Process CRS-specific items based on the CRS type.
"""
function process_crs_items!(node::Dict, keyword::String, items::Vector)
  if keyword == "GEOGCRS"
    node["type"] = "GeographicCRS"

    axes = []
    unit = nothing

    for (i, item) in enumerate(items)
      if i == 1
        continue
      elseif typeof(item) <: Dict && get(item, "type", "") == "DATUM"
        node["datum"] = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "ENSEMBLE"
        node["datum_ensemble"] = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "CS"
        if !haskey(node, "coordinate_system")
          node["coordinate_system"] = Dict{String,Any}()
        end
        node["coordinate_system"]["subtype"] = get(item, "subtype", "unknown")
        node["coordinate_system"]["dimension"] = get(item, "dimension", 2)
      elseif typeof(item) <: Dict && get(item, "type", "") == "AXIS"
        push!(axes, item)
      elseif typeof(item) <: Dict && (get(item, "type", "") in ["UNIT", "LENGTHUNIT", "ANGLEUNIT"])
        unit = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
        node["id"] = item
      end
    end

    if !haskey(node, "coordinate_system")
      node["coordinate_system"] = Dict{String,Any}("subtype" => "ellipsoidal", "dimension" => 2)
    end

    if !isempty(axes)
      node["coordinate_system"]["axis"] = axes

      if unit !== nothing
        for axis in node["coordinate_system"]["axis"]
          axis["unit"] = convert_unit(unit)
        end
      end
    end

  elseif keyword == "PROJCRS"
    node["type"] = "ProjectedCRS"

    axes = []
    unit = nothing

    for (i, item) in enumerate(items)
      if i == 1
        continue
      elseif typeof(item) <: Dict && (get(item, "type", "") == "BASEGEOGCRS" || get(item, "type", "") == "GEOGCRS")
        base_crs = item
        base_crs["type"] = "GeographicCRS"
        node["base_crs"] = base_crs
      elseif typeof(item) <: Dict && get(item, "type", "") == "CONVERSION"
        node["conversion"] = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "CS"
        if !haskey(node, "coordinate_system")
          node["coordinate_system"] = Dict{String,Any}()
        end
        node["coordinate_system"]["subtype"] = get(item, "subtype", "unknown")
        node["coordinate_system"]["dimension"] = get(item, "dimension", 2)
      elseif typeof(item) <: Dict && get(item, "type", "") == "AXIS"
        push!(axes, item)
      elseif typeof(item) <: Dict && (get(item, "type", "") in ["UNIT", "LENGTHUNIT", "ANGLEUNIT"])
        unit = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
        node["id"] = item
      end
    end

    if !haskey(node, "coordinate_system")
      node["coordinate_system"] = Dict{String,Any}("subtype" => "cartesian", "dimension" => 2)
    end

    if !isempty(axes)
      node["coordinate_system"]["axis"] = axes

      if unit !== nothing
        for axis in node["coordinate_system"]["axis"]
          axis["unit"] = convert_unit(unit)
        end
      end
    end

  elseif keyword == "VERTCRS"
    node["type"] = "VerticalCRS"

    axes = []
    unit = nothing

    for (i, item) in enumerate(items)
      if i == 1
        continue
      elseif typeof(item) <: Dict && get(item, "type", "") == "VDATUM"
        node["datum"] = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "ENSEMBLE"
        node["datum_ensemble"] = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "CS"
        if !haskey(node, "coordinate_system")
          node["coordinate_system"] = Dict{String,Any}()
        end
        node["coordinate_system"]["subtype"] = get(item, "subtype", "unknown")
        node["coordinate_system"]["dimension"] = get(item, "dimension", 1)
      elseif typeof(item) <: Dict && get(item, "type", "") == "AXIS"
        push!(axes, item)
      elseif typeof(item) <: Dict && (get(item, "type", "") in ["UNIT", "LENGTHUNIT", "ANGLEUNIT"])
        unit = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
        node["id"] = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "GEOIDMODEL"
        node["geoid_model"] = item
      end
    end

    if !haskey(node, "coordinate_system")
      node["coordinate_system"] = Dict{String,Any}("subtype" => "vertical", "dimension" => 1)
    end

    if !isempty(axes)
      node["coordinate_system"]["axis"] = axes

      if unit !== nothing
        for axis in node["coordinate_system"]["axis"]
          axis["unit"] = convert_unit(unit)
        end
      end
    end

  elseif keyword == "GEODCRS"
    node["type"] = "GeodeticCRS"

    axes = []
    unit = nothing

    for (i, item) in enumerate(items)
      if i == 1
        continue
      elseif typeof(item) <: Dict && get(item, "type", "") == "DATUM"
        node["datum"] = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "ENSEMBLE"
        node["datum_ensemble"] = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "CS"
        if !haskey(node, "coordinate_system")
          node["coordinate_system"] = Dict{String,Any}()
        end
        node["coordinate_system"]["subtype"] = get(item, "subtype", "unknown")
        node["coordinate_system"]["dimension"] = get(item, "dimension", 3)
      elseif typeof(item) <: Dict && get(item, "type", "") == "AXIS"
        push!(axes, item)
      elseif typeof(item) <: Dict && (get(item, "type", "") in ["UNIT", "LENGTHUNIT", "ANGLEUNIT"])
        unit = item
      elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
        node["id"] = item
      end
    end

    if !haskey(node, "coordinate_system")
      node["coordinate_system"] = Dict{String,Any}("subtype" => "ellipsoidal", "dimension" => 3)
    end

    if !isempty(axes)
      node["coordinate_system"]["axis"] = axes

      if unit !== nothing
        for axis in node["coordinate_system"]["axis"]
          axis["unit"] = convert_unit(unit)
        end
      end
    end

  elseif keyword == "COMPOUNDCRS"
    node["type"] = "CompoundCRS"
    components = []
    for (i, item) in enumerate(items)
      if i == 1
        continue
      elseif typeof(item) <: Dict && (get(item, "type", "") in ["GEOGCRS", "PROJCRS", "VERTCRS", "GEODCRS"])
        push!(components, item)
      elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
        node["id"] = item
      end
    end
    if !isempty(components)
      node["components"] = components
    end
  end
end

"""
    process_datum_items!(node::Dict, items::Vector)

Process datum-specific items.
"""
function process_datum_items!(node::Dict, items::Vector)
  for (i, item) in enumerate(items)
    if i == 1
      continue
    elseif typeof(item) <: Dict && get(item, "type", "") == "ELLIPSOID"
      node["ellipsoid"] = item
    elseif typeof(item) <: Dict && get(item, "type", "") == "PRIMEM"
      node["prime_meridian"] = item
    elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
      node["id"] = item
    end
  end
end

"""
    process_ellipsoid_items!(node::Dict, items::Vector)

Process ellipsoid-specific items.
"""
function process_ellipsoid_items!(node::Dict, items::Vector)
  for (i, item) in enumerate(items)
    if i <= 3
      continue
    elseif typeof(item) <: Dict && get(item, "type", "") == "LENGTHUNIT"
      node["unit"] = item["name"]
    elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
      node["id"] = item
    end
  end
end

"""
    process_cs(cs_node::Dict, items::Vector) -> Dict

Process a coordinate system node and extract axes.
"""
function process_cs(cs_node::Dict, items::Vector)
  result =
    Dict{String,Any}("subtype" => get(cs_node, "subtype", "unknown"), "dimension" => get(cs_node, "dimension", 0))

  if haskey(cs_node, "id")
    result["id"] = cs_node["id"]
  end

  return result
end

"""
    process_ensemble_items!(node::Dict, items::Vector)

Process datum ensemble-specific items.
"""
function process_ensemble_items!(node::Dict, items::Vector)
  members = []

  for (i, item) in enumerate(items)
    if i == 1
      continue
    elseif typeof(item) <: Dict && get(item, "type", "") == "MEMBER"
      push!(members, item)
    elseif typeof(item) <: Dict && get(item, "type", "") == "ELLIPSOID"
      node["ellipsoid"] = item
    elseif typeof(item) <: Dict && get(item, "type", "") == "ENSEMBLEACCURACY"
      node["accuracy"] = get(item, "value", 0.0)
    elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
      node["id"] = item
    end
  end

  if !isempty(members)
    node["members"] = members
  end
end

"""
    process_member_items!(node::Dict, items::Vector)

Process ensemble member-specific items.
"""
function process_member_items!(node::Dict, items::Vector)
  for (i, item) in enumerate(items)
    if i == 1
      continue
    elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
      node["id"] = item
    end
  end
end

"""
    process_primem_items!(node::Dict, items::Vector)

Process prime meridian-specific items.
"""
function process_primem_items!(node::Dict, items::Vector)
  for (i, item) in enumerate(items)
    if i <= 2
      continue
    elseif typeof(item) <: Dict && (get(item, "type", "") == "ANGLEUNIT" || get(item, "type", "") == "UNIT")
      node["unit"] = item["name"]
    elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
      node["id"] = item
    end
  end
end

"""
    process_method_items!(node::Dict, items::Vector)

Process method-specific items.
"""
function process_method_items!(node::Dict, items::Vector)
  for (i, item) in enumerate(items)
    if i == 1
      continue
    elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
      node["id"] = item
    end
  end
end

"""
    process_parameter_items!(node::Dict, items::Vector)

Process projection parameter-specific items.
"""
function process_parameter_items!(node::Dict, items::Vector)
  for (i, item) in enumerate(items)
    if i <= 2
      continue
    elseif typeof(item) <: Dict && (get(item, "type", "") in ["LENGTHUNIT", "ANGLEUNIT", "SCALEUNIT", "UNIT"])
      node["unit"] = item
    elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
      node["id"] = item
    end
  end
end

"""
    process_conversion_items!(node::Dict, items::Vector)

Process conversion-specific items.
"""
function process_conversion_items!(node::Dict, items::Vector)
  method = nothing
  parameters = []

  for (i, item) in enumerate(items)
    if i == 1
      continue
    elseif typeof(item) <: Dict && get(item, "type", "") == "METHOD"
      method = item
    elseif typeof(item) <: Dict && get(item, "type", "") == "PARAMETER"
      push!(parameters, item)
    elseif typeof(item) <: Dict && get(item, "type", "") == "ID"
      node["id"] = item
    end
  end

  if method !== nothing
    node["method"] = method
  end

  if !isempty(parameters)
    node["parameters"] = parameters
  end
end

"""
    convert_to_projjson(wkt_obj::Dict) -> Dict

Convert a parsed WKT2 object to PROJJSON format.
"""
function convert_to_projjson(wkt_obj::Dict)
  result = Dict{String,Any}("\$schema" => "https://proj.org/schemas/v0.7/projjson.schema.json")

  wkt_type = get(wkt_obj, "type", "")

  if wkt_type == "GeographicCRS"
    converted = convert_geographic_crs(wkt_obj)
    merge!(result, converted)
  elseif wkt_type == "ProjectedCRS"
    converted = convert_projected_crs(wkt_obj)
    merge!(result, converted)
  elseif wkt_type == "VerticalCRS"
    converted = convert_vertical_crs(wkt_obj)
    merge!(result, converted)
  elseif wkt_type == "CompoundCRS"
    converted = convert_compound_crs(wkt_obj)
    merge!(result, converted)
  else
    result["type"] = wkt_type
    result["name"] = get(wkt_obj, "name", "Unknown")
  end
  return result
end

"""
    convert_geographic_crs(wkt_obj::Dict) -> Dict

Convert a WKT2 GeographicCRS to PROJJSON.
"""
function convert_geographic_crs(wkt_obj::Dict)
  result = Dict{String,Any}("type" => "GeographicCRS", "name" => get(wkt_obj, "name", "Unknown"))

  if haskey(wkt_obj, "datum")
    result["datum"] = convert_datum(wkt_obj["datum"])
  elseif haskey(wkt_obj, "datum_ensemble")
    result["datum_ensemble"] = convert_datum_ensemble(wkt_obj["datum_ensemble"])
  end

  if haskey(wkt_obj, "coordinate_system")
    result["coordinate_system"] = convert_coordinate_system(wkt_obj["coordinate_system"])
  end

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

"""
    convert_projected_crs(wkt_obj::Dict) -> Dict

Convert a WKT2 ProjectedCRS to PROJJSON.
"""
function convert_projected_crs(wkt_obj::Dict)
  result = Dict{String,Any}("type" => "ProjectedCRS", "name" => get(wkt_obj, "name", "Unknown"))

  if haskey(wkt_obj, "base_crs")
    result["base_crs"] = convert_geographic_crs(wkt_obj["base_crs"])
  end

  if haskey(wkt_obj, "conversion")
    result["conversion"] = convert_conversion(wkt_obj["conversion"])
  end

  if haskey(wkt_obj, "coordinate_system")
    result["coordinate_system"] = convert_coordinate_system(wkt_obj["coordinate_system"])
  end

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

"""
    convert_vertical_crs(wkt_obj::Dict) -> Dict

Convert a WKT2 VerticalCRS to PROJJSON.
"""
function convert_vertical_crs(wkt_obj::Dict)
  result = Dict{String,Any}("type" => "VerticalCRS", "name" => get(wkt_obj, "name", "Unknown"))

  if haskey(wkt_obj, "datum")
    result["datum"] = convert_vertical_datum(wkt_obj["datum"])
  end

  if haskey(wkt_obj, "coordinate_system")
    result["coordinate_system"] = convert_coordinate_system(wkt_obj["coordinate_system"])
  end

  if haskey(wkt_obj, "geoid_model")
    result["geoid_model"] = convert_geoid_model(wkt_obj["geoid_model"])
  end

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

"""
    convert_geoid_model(wkt_obj::Dict) -> Dict

Convert a WKT2 GEOIDMODEL to PROJJSON.
"""
function convert_geoid_model(wkt_obj::Dict)
  result = Dict{String,Any}("type" => "GeoidModel")

  if haskey(wkt_obj, "name")
    result["name"] = wkt_obj["name"]
  elseif haskey(wkt_obj, "items") && length(wkt_obj["items"]) >= 1
    result["name"] = wkt_obj["items"][1]
  end

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  elseif haskey(wkt_obj, "items") && length(wkt_obj["items"]) >= 2 && typeof(wkt_obj["items"][2]) <: Dict
    result["id"] = convert_id(wkt_obj["items"][2])
  end

  return result
end

"""
    convert_compound_crs(wkt_obj::Dict) -> Dict

Convert a WKT2 CompoundCRS to PROJJSON.
"""
function convert_compound_crs(wkt_obj::Dict)
  result = Dict{String,Any}("type" => "CompoundCRS", "name" => get(wkt_obj, "name", "Unknown"))

  if haskey(wkt_obj, "components")
    components = []
    for component in wkt_obj["components"]
      push!(components, convert_to_projjson(component))
    end
    result["components"] = components
  end

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

"""
    convert_datum(wkt_obj::Dict) -> Dict

Convert a WKT2 Datum to PROJJSON.
"""
function convert_datum(wkt_obj::Dict)
  result = Dict{String,Any}("type" => "GeodeticReferenceFrame", "name" => get(wkt_obj, "name", "Unknown"))

  if haskey(wkt_obj, "ellipsoid")
    result["ellipsoid"] = convert_ellipsoid(wkt_obj["ellipsoid"])
  end

  if haskey(wkt_obj, "prime_meridian")
    result["prime_meridian"] = convert_prime_meridian(wkt_obj["prime_meridian"])
  end

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

"""
    convert_vertical_datum(wkt_obj::Dict) -> Dict

Convert a WKT2 VerticalDatum to PROJJSON.
"""
function convert_vertical_datum(wkt_obj::Dict)
  result = Dict{String,Any}("type" => "VerticalReferenceFrame", "name" => get(wkt_obj, "name", "Unknown"))

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

"""
    convert_datum_ensemble(wkt_obj::Dict) -> Dict

Convert a WKT2 DatumEnsemble to PROJJSON.
"""
function convert_datum_ensemble(wkt_obj::Dict)
  result = Dict{String,Any}("type" => "DatumEnsemble", "name" => get(wkt_obj, "name", "Unknown"))

  if haskey(wkt_obj, "members")
    members = []
    for member in wkt_obj["members"]
      member_dict = Dict{String,Any}("name" => get(member, "name", "Unknown"))

      if haskey(member, "id")
        member_dict["id"] = convert_id(member["id"])
      end

      push!(members, member_dict)
    end
    result["members"] = members
  end

  if haskey(wkt_obj, "ellipsoid")
    result["ellipsoid"] = convert_ellipsoid(wkt_obj["ellipsoid"])
  end

  if haskey(wkt_obj, "accuracy")
    result["accuracy"] = wkt_obj["accuracy"]
  end

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

"""
    convert_ellipsoid(wkt_obj::Dict) -> Dict

Convert a WKT2 Ellipsoid to PROJJSON.
"""
function convert_ellipsoid(wkt_obj::Dict)
  result = Dict{String,Any}(
    "name" => get(wkt_obj, "name", "Unknown"),
    "semi_major_axis" => get(wkt_obj, "semi_major_axis", 0.0)
  )

  if haskey(wkt_obj, "inverse_flattening")
    result["inverse_flattening"] = wkt_obj["inverse_flattening"]
  elseif haskey(wkt_obj, "semi_minor_axis")
    result["semi_minor_axis"] = wkt_obj["semi_minor_axis"]
  end

  if haskey(wkt_obj, "unit")
    result["unit"] = wkt_obj["unit"]
  end

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

"""
    convert_prime_meridian(wkt_obj::Dict) -> Dict

Convert a WKT2 PrimeMeridian to PROJJSON.
"""
function convert_prime_meridian(wkt_obj::Dict)
  result = Dict{String,Any}("name" => get(wkt_obj, "name", "Unknown"), "longitude" => get(wkt_obj, "longitude", 0.0))

  if haskey(wkt_obj, "unit")
    result["unit"] = wkt_obj["unit"]
  end

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

"""
    convert_coordinate_system(wkt_obj::Dict) -> Dict

Convert a WKT2 CoordinateSystem to PROJJSON.
"""
function convert_coordinate_system(wkt_obj::Dict)
  result = Dict{String,Any}("subtype" => get(wkt_obj, "subtype", "unknown"))

  if haskey(wkt_obj, "dimension")
    result["dimension"] = wkt_obj["dimension"]
  end

  if haskey(wkt_obj, "axis") && !isempty(wkt_obj["axis"])
    axes = []
    for axis in wkt_obj["axis"]
      axis_obj = Dict{String,Any}(
        "name" => get(axis, "name", "Unknown"),
        "abbreviation" => get(axis, "abbreviation", ""),
        "direction" => get(axis, "direction", "unspecified")
      )
      if haskey(axis, "unit")
        axis_obj["unit"] = convert_unit(axis["unit"])
      end
      push!(axes, axis_obj)
    end
    result["axis"] = axes
  else
    result["axis"] = []
  end

  return result
end

"""
    convert_conversion(wkt_obj::Dict) -> Dict

Convert a WKT2 Conversion to PROJJSON.
"""
function convert_conversion(wkt_obj::Dict)
  result = Dict{String,Any}("name" => get(wkt_obj, "name", "Unknown"))

  if haskey(wkt_obj, "method")
    method_dict = Dict{String,Any}("name" => get(wkt_obj["method"], "name", "Unknown"))

    if haskey(wkt_obj["method"], "id")
      method_dict["id"] = convert_id(wkt_obj["method"]["id"])
    end

    result["method"] = method_dict
  end

  if haskey(wkt_obj, "parameters")
    parameters = []
    for param in wkt_obj["parameters"]
      param_obj = Dict{String,Any}("name" => get(param, "name", "Unknown"), "value" => get(param, "value", 0.0))

      if haskey(param, "unit")
        param_obj["unit"] = convert_unit(param["unit"])
      end

      if haskey(param, "id")
        param_obj["id"] = convert_id(param["id"])
      end

      push!(parameters, param_obj)
    end
    result["parameters"] = parameters
  end

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

"""
    convert_id(wkt_obj::Dict) -> Dict

Convert a WKT2 ID to PROJJSON.
"""
function convert_id(wkt_obj::Dict)
  return Dict{String,Any}(
    "authority" => get(wkt_obj, "authority", "UNKNOWN"),
    "code" => get(wkt_obj, "code", "UNKNOWN")
  )
end

"""
    convert_unit(wkt_obj::Dict) -> Dict

Convert a WKT2 Unit to PROJJSON.
"""
function convert_unit(wkt_obj::Dict)
  unit_type_map =
    Dict("LENGTHUNIT" => "LinearUnit", "ANGLEUNIT" => "AngularUnit", "SCALEUNIT" => "ScaleUnit", "UNIT" => "Unit")

  result = Dict{String,Any}(
    "type" => get(unit_type_map, get(wkt_obj, "type", "Unit"), "Unit"),
    "name" => get(wkt_obj, "name", "unknown"),
    "conversion_factor" => get(wkt_obj, "conversion_factor", 1.0)
  )

  if haskey(wkt_obj, "id")
    result["id"] = convert_id(wkt_obj["id"])
  end

  return result
end

end
