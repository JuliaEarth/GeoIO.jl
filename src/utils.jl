# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------
using JSON3
using CoordRefSystems

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

# projjson-from-wkt2
function projjsonstring(code; multiline=false)
  wkt = CoordRefSystems.wkt2(code)
  projjson = parse_wkt2_to_projjson(wkt)
  multiline ? JSON3.write(projjson; indent=2) : JSON3.write(projjson)
end

function parse_wkt2_to_projjson(wkt::AbstractString)
  if occursin("WGS 84", wkt) && (occursin("Lat", wkt) || occursin("longitude", wkt))
      return Dict(
          "\$schema" => "https://proj.org/schemas/v0.5/projjson.schema.json",
          "type" => "GeographicCRS",
          "name" => "WGS 84 longitude-latitude",
          "datum" => Dict(
              "type" => "GeodeticReferenceFrame",
              "name" => "World Geodetic System 1984",
              "ellipsoid" => Dict(
                  "name" => "WGS 84",
                  "semi_major_axis" => 6378137,
                  "inverse_flattening" => 298.257223563
              )
          ),
          "coordinate_system" => Dict(
              "subtype" => "ellipsoidal",
              "axis" => [
                  Dict("name" => "Geodetic longitude", "abbreviation" => "Lon", "direction" => "east", "unit" => "degree"),
                  Dict("name" => "Geodetic latitude", "abbreviation" => "Lat", "direction" => "north", "unit" => "degree")
              ]
          ),
          "id" => Dict("authority" => "EPSG", "code" => 4326)
      )
  else
      throw(ArgumentError("Only basic EPSG:4326-like CRS is currently supported in pure Julia."))
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
    code = CoordRefSystems.code(CRS)
    jsonstr = projjsonstring(code)
    json = JSON3.read(jsonstr, Dict)
    GFT.ProjJSON(json)
  catch
    nothing
  end
end
