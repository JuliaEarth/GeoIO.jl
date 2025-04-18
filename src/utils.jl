# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

include("wkt2_parser.jl")

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