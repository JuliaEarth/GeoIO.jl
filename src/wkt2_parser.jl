"""
    WKT2 AST parser for coordinate reference systems
"""


# Abstract type for all WKT2 nodes
abstract type WKT2Node end

# Token types
@enum TokenType begin
  LBRACKET
  RBRACKET
  COMMA
  STRING
  NUMBER
  IDENTIFIER
  EOF
end

struct Token
  type::TokenType
  value::String
  line::Int
  column::Int
end

# AST node types
struct WKT2String <: WKT2Node
  value::String
end

struct WKT2Number <: WKT2Node
  value::Number
  is_integer::Bool
end

struct WKT2Identifier <: WKT2Node
  value::String
end

struct WKT2Object <: WKT2Node
  keyword::String
  args::Vector{WKT2Node}
end

# Lexer
mutable struct Lexer
  input::String
  position::Int
  line::Int
  column::Int
end

function Lexer(input::String)
  Lexer(input, 1, 1, 1)
end

function peek(l::Lexer)
  if l.position > length(l.input)
    return '\0'
  end
  l.input[l.position]
end

function advance(l::Lexer)
  char = peek(l)
  l.position += 1
  if char == '\n'
    l.line += 1
    l.column = 1
  else
    l.column += 1
  end
  char
end

function skip_whitespace(l::Lexer)
  while isspace(peek(l))
    advance(l)
  end
end

function read_string(l::Lexer)
  advance(l) # Skip opening quote
  start_pos = l.position
  while peek(l) != '"' && peek(l) != '\0'
    advance(l)
  end
  if peek(l) == '\0'
    error("Unterminated string at line $(l.line), column $(l.column)")
  end
  str = l.input[start_pos:l.position-1]
  advance(l) # Skip closing quote
  str
end

function read_number(l::Lexer)
  start_pos = l.position
  has_decimal = false
  has_exponent = false
  
  # Handle sign
  if peek(l) == '-' || peek(l) == '+'
    advance(l)
  end
  
  # Read digits before decimal point
  while isdigit(peek(l))
    advance(l)
  end
  
  # Handle decimal point and following digits
  if peek(l) == '.'
    has_decimal = true
    advance(l)
    while isdigit(peek(l))
      advance(l)
    end
  end
  
  # Handle scientific notation (e or E)
  if lowercase(peek(l)) == 'e'
    has_exponent = true
    advance(l)
    # Handle exponent sign
    if peek(l) == '-' || peek(l) == '+'
      advance(l)
    end
    # Read exponent digits
    while isdigit(peek(l))
      advance(l)
    end
  end
  
  num_str = l.input[start_pos:l.position-1]
  # Always parse as Float64 if exponent or decimal is present
  if has_exponent || has_decimal
    (parse(Float64, num_str), false)
  else
    # Try parsing as Int64 first, fall back to Float64 if too large or contains exponent implicitly
    try
        (parse(Int64, num_str), true)
    catch
        (parse(Float64, num_str), false)
    end
  end
end

function read_identifier(l::Lexer)
  start_pos = l.position
  while isletter(peek(l)) || isdigit(peek(l)) || peek(l) == '_'
    advance(l)
  end
  l.input[start_pos:l.position-1]
end

function next_token(l::Lexer)::Token
  skip_whitespace(l)
  
  char = peek(l)
  line = l.line
  col = l.column
  
  if char == '\0'
    return Token(EOF, "", line, col)
  elseif char == '['
    advance(l)
    return Token(LBRACKET, "[", line, col)
  elseif char == ']'
    advance(l)
    return Token(RBRACKET, "]", line, col)
  elseif char == ','
    advance(l)
    return Token(COMMA, ",", line, col)
  elseif char == '"'
    return Token(STRING, read_string(l), line, col)
  elseif isdigit(char) || char == '-' || char == '+'
    num, _ = read_number(l)
    return Token(NUMBER, string(num), line, col)
  elseif isletter(char)
    return Token(IDENTIFIER, read_identifier(l), line, col)
  else
    error("Unexpected character '$char' at line $line, column $col")
  end
end

# Parser
mutable struct Parser
  lexer::Lexer
  current_token::Token
end

function Parser(input::String)
  lexer = Lexer(input)
  Parser(lexer, next_token(lexer))
end

function advance_token(p::Parser)
  p.current_token = next_token(p.lexer)
end

function expect(p::Parser, type::TokenType)
  if p.current_token.type != type
    error("Expected $(type), got $(p.current_token.type) at line $(p.current_token.line), column $(p.current_token.column)")
  end
  token = p.current_token
  advance_token(p)
  token
end

function parse_value(p::Parser)::WKT2Node
  token = p.current_token
  if token.type == STRING
    advance_token(p)
    WKT2String(token.value)
  elseif token.type == NUMBER
    advance_token(p)
    num, is_int = read_number(Lexer(token.value))
    WKT2Number(num, is_int)
  elseif token.type == IDENTIFIER
    advance_token(p)
    if p.current_token.type == LBRACKET
      parse_object(p, token.value)
    else
      WKT2Identifier(token.value)
    end
  elseif token.type == LBRACKET
    advance_token(p)
    args = WKT2Node[]
    while p.current_token.type != RBRACKET
      push!(args, parse_value(p))
      if p.current_token.type == COMMA
        advance_token(p)
      end
    end
    expect(p, RBRACKET)
    WKT2Object("", args)
  else
    error("Unexpected token $(token.type) at line $(token.line), column $(token.column)")
  end
end

function parse_object(p::Parser, keyword::String)::WKT2Object
  expect(p, LBRACKET)
  args = WKT2Node[]
  while p.current_token.type != RBRACKET
    push!(args, parse_value(p))
    if p.current_token.type == COMMA
      advance_token(p)
    end
  end
  expect(p, RBRACKET)
  WKT2Object(keyword, args)
end

function parse_wkt2(input::String)::WKT2Node
  parser = Parser(input)
  if parser.current_token.type == IDENTIFIER
    keyword = parser.current_token.value
    advance_token(parser)
    parse_object(parser, keyword)
  else
    parse_value(parser)
  end
end

# Helper functions to convert AST to PROJJSON
function node_to_json(node::WKT2String)
  node.value
end

function node_to_json(node::WKT2Number)
  if node.is_integer
    Int(node.value)
  else
    node.value
  end
end

function node_to_json(node::WKT2Identifier)
  node.value
end

function node_to_json(node::WKT2Object)
  if node.keyword == "GEOGCRS"
    geogcrs_to_json(node)
  elseif node.keyword == "PROJCRS"
    projcrs_to_json(node)
  elseif node.keyword == "ENSEMBLE"
    ensemble_to_json(node)
  elseif node.keyword == "ELLIPSOID"
    ellipsoid_to_json(node)
  elseif node.keyword == "ID"
    id_to_json(node)
  elseif node.keyword == "CS"
    cs_to_json(node)
  elseif node.keyword == "AXIS"
    axis_to_json(node)
  elseif node.keyword == "UNIT" || node.keyword == "ANGLEUNIT" || 
         node.keyword == "LENGTHUNIT" || node.keyword == "SCALEUNIT"
    unit_to_json(node)
  else
    Dict{String,Any}("type" => node.keyword,
                     "args" => map(node_to_json, node.args))
  end
end

# These functions will be implemented next to handle specific CRS components
function geogcrs_to_json(node::WKT2Object)
  name = node_to_json(node.args[1])
  
  json = Dict{String,Any}(
    "\$schema" => "https://proj.org/schemas/v0.7/projjson.schema.json",
    "type" => "GeographicCRS",
    "name" => name
  )
  
  # Process remaining arguments
  for arg in node.args[2:end]
    if arg isa WKT2Object
      if arg.keyword == "ENSEMBLE"
        json["datum_ensemble"] = ensemble_to_json(arg)
      elseif arg.keyword == "DATUM"
        json["datum"] = datum_to_json(arg)
      elseif arg.keyword == "CS"
        cs = cs_to_json(arg)
        json["coordinate_system"] = cs
      elseif arg.keyword == "AXIS"
        if !haskey(json, "coordinate_system")
          json["coordinate_system"] = Dict{String,Any}(
            "subtype" => "Ellipsoidal",
            "axis" => []
          )
        end
        push!(json["coordinate_system"]["axis"], axis_to_json(arg))
      elseif arg.keyword == "ANGLEUNIT"
        # Store unit for later use with axes
        json["unit"] = unit_to_json(arg)
      elseif arg.keyword == "ID"
        json["id"] = id_to_json(arg)
      end
    end
  end
  
  # Apply unit to axes if not already set
  if haskey(json, "unit") && haskey(json, "coordinate_system")
    unit = json["unit"]
    delete!(json, "unit")
    for axis in json["coordinate_system"]["axis"]
      if !haskey(axis, "unit")
        axis["unit"] = unit
      end
    end
  end
  
  json
end

function ensemble_to_json(node::WKT2Object)
  name = node_to_json(node.args[1])
  ensemble = Dict{String,Any}(
    "name" => name,
    "members" => []
  )
  
  for arg in node.args[2:end]
    if arg isa WKT2Object
      if arg.keyword == "MEMBER"
        push!(ensemble["members"], member_to_json(arg))
      elseif arg.keyword == "ELLIPSOID"
        # Simplified ellipsoid for ensemble
        ensemble["ellipsoid"] = simple_ellipsoid_to_json(arg)
      elseif arg.keyword == "ENSEMBLEACCURACY"
        # Convert accuracy to float string
        ensemble["accuracy"] = string(Float64(node_to_json(arg.args[1])))
      elseif arg.keyword == "ID"
        ensemble["id"] = id_to_json(arg)
      end
    end
  end
  
  ensemble
end

function member_to_json(node::WKT2Object)
  name = node_to_json(node.args[1])
  member = Dict{String,Any}("name" => name)
  
  for arg in node.args[2:end]
    if arg isa WKT2Object && arg.keyword == "ID"
      member["id"] = id_to_json(arg)
    end
  end
  
  member
end

function ellipsoid_to_json(node::WKT2Object)
  ellipsoid = simple_ellipsoid_to_json(node)
  
  # Process remaining arguments for optional units and ID (for top-level definition)
  for arg in node.args[4:end]
    if arg isa WKT2Object
      if arg.keyword == "LENGTHUNIT"
        ellipsoid["unit"] = unit_to_json(arg)
      elseif arg.keyword == "ID"
        ellipsoid["id"] = id_to_json(arg)
      end
    end
  end
  
  ellipsoid
end

# Helper for simplified ellipsoid (name, semi-major, inv-flattening only)
function simple_ellipsoid_to_json(node::WKT2Object)
  Dict{String,Any}(
    "name" => node_to_json(node.args[1]),
    "semi_major_axis" => node_to_json(node.args[2]),
    "inverse_flattening" => node_to_json(node.args[3])
  )
end

function cs_to_json(node::WKT2Object)
  subtype = node_to_json(node.args[1])
  # Ensure correct casing based on common subtypes
  subtype_lower = lowercase(subtype)
  if subtype_lower == "cartesian"
      subtype = "Cartesian" # Capitalize Cartesian
  else
      subtype = subtype_lower # Keep others lowercase (like ellipsoidal)
  end
  
  cs = Dict{String,Any}(
    "subtype" => subtype,
    "axis" => []
  )
  
  # Process AXIS arguments directly attached to CS
  for arg in node.args[3:end] # Start from 3rd arg (after subtype and dim)
      if arg isa WKT2Object && arg.keyword == "AXIS"
          push!(cs["axis"], axis_to_json(arg))
      end
  end

  cs
end

function axis_to_json(node::WKT2Object)
  # Extract name and abbreviation from first argument
  name_str = node_to_json(node.args[1])
  name_parts = match(r"(.*?)\s*\((.*?)\)", name_str)
  
  axis = Dict{String,Any}()
  if name_parts !== nothing
    axis["name"] = strip(name_parts[1])
    axis["abbreviation"] = strip(name_parts[2])
  else
    axis["name"] = strip(name_str)
    axis["abbreviation"] = ""
  end
  
  # Direction is always the second argument
  axis["direction"] = lowercase(node_to_json(node.args[2]))
  
  # Process unit if present
  for arg in node.args[3:end]
    if arg isa WKT2Object && (arg.keyword == "LENGTHUNIT" || arg.keyword == "ANGLEUNIT")
      axis["unit"] = node_to_json(arg.args[1])  # Just take the name field
      break
    end
  end
  
  # Default to metre if no unit specified and name suggests linear measurement
  if !haskey(axis, "unit")
    name_lower = lowercase(axis["name"])
    if contains(name_lower, "easting") || contains(name_lower, "northing") ||
       contains(name_lower, "height") || contains(name_lower, "x") || contains(name_lower, "y")
      axis["unit"] = "metre"
    else
      axis["unit"] = "degree"
    end
  end
  
  axis
end

function unit_to_json(node::WKT2Object)
  name = node_to_json(node.args[1])
  conversion = node_to_json(node.args[2])
  
  unit = Dict{String,Any}(
    "name" => name,
    "conversion_factor" => conversion
  )
  
  # Process ID if present
  if length(node.args) > 2
    for arg in node.args[3:end]
      if arg isa WKT2Object && arg.keyword == "ID"
        unit["id"] = id_to_json(arg)
      end
    end
  end
  
  unit
end

function id_to_json(node::WKT2Object)
  authority = node_to_json(node.args[1])
  code = node_to_json(node.args[2])  # This is already a number from node_to_json(WKT2Number)
  
  Dict{String,Any}(
    "authority" => authority,
    "code" => Int(code)  # Just convert to Int in case it's a float
  )
end

function datum_to_json(node::WKT2Object)
  name = node_to_json(node.args[1])
  
  datum = Dict{String,Any}(
    "type" => "GeodeticReferenceFrame",
    "name" => name
  )
  
  for arg in node.args[2:end]
    if arg isa WKT2Object
      if arg.keyword == "ELLIPSOID"
        # Use simplified ellipsoid for datum
        datum["ellipsoid"] = simple_ellipsoid_to_json(arg)
      end
    end
  end
  
  datum
end

function projcrs_to_json(node::WKT2Object)
  name = node_to_json(node.args[1])
  
  json = Dict{String,Any}(
    "\$schema" => "https://proj.org/schemas/v0.7/projjson.schema.json",
    "type" => "ProjectedCRS",
    "name" => name
  )
  
  # Process remaining arguments
  for arg in node.args[2:end]
    if arg isa WKT2Object
      if arg.keyword == "BASEGEOGCRS"
        json["base_crs"] = basegeogcrs_to_json(arg)
      elseif arg.keyword == "CONVERSION"
        json["conversion"] = conversion_to_json(arg)
      elseif arg.keyword == "CS"
        json["coordinate_system"] = cs_to_json(arg)
      elseif arg.keyword == "AXIS"
        if !haskey(json, "coordinate_system")
          json["coordinate_system"] = Dict{String,Any}(
            "subtype" => "Cartesian",
            "axis" => []
          )
        end
        push!(json["coordinate_system"]["axis"], axis_to_json(arg))
      elseif arg.keyword == "LENGTHUNIT"
        # Store unit for later use with axes
        json["unit"] = unit_to_json(arg)
      elseif arg.keyword == "ID"
        json["id"] = id_to_json(arg)
      end
    end
  end
  
  # Apply unit to axes if not already set
  if haskey(json, "unit") && haskey(json, "coordinate_system")
    unit = json["unit"]
    delete!(json, "unit")
    for axis in json["coordinate_system"]["axis"]
      if !haskey(axis, "unit")
        axis["unit"] = unit
      end
    end
  end
  
  json
end

function basegeogcrs_to_json(node::WKT2Object)
  name = node_to_json(node.args[1])
  
  base_crs = Dict{String,Any}(
    "name" => name
  )
  
  # Process remaining arguments
  cs_defined = false
  temp_unit = nothing
  axes_list = []
  explicit_cs = nothing # Store explicitly parsed CS

  for arg in node.args[2:end]
    if arg isa WKT2Object
      if arg.keyword == "ENSEMBLE"
        base_crs["datum_ensemble"] = ensemble_to_json(arg)
      elseif arg.keyword == "DATUM"
        base_crs["datum"] = datum_to_json(arg) # Will use simple ellipsoid, no ID
      elseif arg.keyword == "CS"
        explicit_cs = cs_to_json(arg) # Store the parsed CS
        cs_defined = true
      elseif arg.keyword == "AXIS"
          # Collect axes if CS not defined explicitly first
          if !cs_defined
              push!(axes_list, axis_to_json(arg))
          end
      elseif arg.keyword == "ANGLEUNIT"
        # Store unit temporarily if CS not defined explicitly first
        if !cs_defined
            temp_unit = unit_to_json(arg) # Use the full unit object
        end
      elseif arg.keyword == "ID"
        base_crs["id"] = id_to_json(arg)
      end
    end
  end
  
  # If CS was explicitly defined, use it
  if cs_defined
      base_crs["coordinate_system"] = explicit_cs
  # If CS was not defined explicitly, create it from collected axes/unit
  elseif !isempty(axes_list)
      cs = Dict{String,Any}(
          "subtype" => "ellipsoidal", # Use lowercase for the default ellipsoidal
          "axis" => axes_list
      )
      # Apply temp unit if available and axes don't have units
      if !isnothing(temp_unit)
          unit_name = get(temp_unit, "name", "degree") # Extract name or default
          for axis in cs["axis"]
              if !haskey(axis, "unit")
                  axis["unit"] = unit_name # Apply just the unit name string
              end
          end
      end
      base_crs["coordinate_system"] = cs
  # If CS was not defined AND no axes were found, add a default ellipsoidal CS
  else
      base_crs["coordinate_system"] = Dict{String,Any}(
          "subtype" => "ellipsoidal", # Use lowercase for the default ellipsoidal
          "axis" => [
              Dict{String,Any}(
                  "name" => "Geodetic latitude",
                  "abbreviation" => "Lat",
                  "direction" => "north",
                  "unit" => "degree"
              ),
              Dict{String,Any}(
                  "name" => "Geodetic longitude",
                  "abbreviation" => "Lon",
                  "direction" => "east",
                  "unit" => "degree"
              )
          ]
      )
  end

  base_crs
end

function conversion_to_json(node::WKT2Object)
  name = node_to_json(node.args[1])
  
  conversion = Dict{String,Any}(
    "name" => name,
    "method" => Dict{String,Any}(),
    "parameters" => []
  )
  
  # Process remaining arguments
  for arg in node.args[2:end]
    if arg isa WKT2Object
      if arg.keyword == "METHOD"
        conversion["method"] = method_to_json(arg)
      elseif arg.keyword == "PARAMETER"
        push!(conversion["parameters"], parameter_to_json(arg))
      end
    end
  end
  
  conversion
end

function method_to_json(node::WKT2Object)
  name = node_to_json(node.args[1])
  method = Dict{String,Any}("name" => name)
  
  # Process remaining arguments for ID
  for arg in node.args[2:end]
    if arg isa WKT2Object && arg.keyword == "ID"
      method["id"] = id_to_json(arg)
    end
  end
  
  method
end

function parameter_to_json(node::WKT2Object)
  name = node_to_json(node.args[1])
  value = node_to_json(node.args[2])

  # Round float values to reduce minor precision differences
  if value isa Float64
      value = round(value, digits=12)
  end

  param = Dict{String,Any}(
    "name" => name,
    "value" => value
  )
  
  # Process unit and ID directly from parameter arguments
  for arg in node.args[3:end]
    if arg isa WKT2Object
      if arg.keyword in ["LENGTHUNIT", "ANGLEUNIT", "SCALEUNIT"]
        # Extract unit name directly
        param["unit"] = node_to_json(arg.args[1]) 
      elseif arg.keyword == "ID"
         # ID belongs to the parameter itself
         param["id"] = id_to_json(arg)
      end
    end
  end
  
  # Infer unit only if not explicitly provided
  if !haskey(param, "unit")
    name_lower = lowercase(name)
    if contains(name_lower, "angle") || 
       contains(name_lower, "longitude") || 
       contains(name_lower, "latitude") ||
       contains(name_lower, "azimuth") ||
       contains(name_lower, "rotation")
      param["unit"] = "degree"
    elseif contains(name_lower, "scale") ||
           contains(name_lower, "factor")
      param["unit"] = "unity"
    else
      param["unit"] = "metre"
    end
  end
  
  param
end

# Update the wkt2toprojjson function to use the new parser
function wkt2toprojjson(wkt2str::String; multiline=false)
  # Parse WKT2 string to AST
  ast = parse_wkt2(wkt2str)
  
  # Convert AST to PROJJSON
  json = node_to_json(ast)
  
  # Convert to JSON string
  if multiline
    JSON3.write(json, indent=2, allow_inf=true)
  else
    JSON3.write(json, allow_inf=true)
  end
end 