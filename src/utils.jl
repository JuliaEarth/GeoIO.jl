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
  geoms = Tables.getcolumn(cols, gcol)

  #Convert geoms one at a time, catching errors
  rows = length(geoms)
  domain = Vector{Geometry}(undef, rows)
  valid_mask = trues(rows)

  for i in 1:rows
    try 
      domain[i] = geom2meshes(geoms[i], crs)
    catch e
      valid_mask[i] = false
    end
  end

  #Get etable, dropping rows where geom threw an error
  vars = setdiff(names, [gcol])
  etable = isempty(vars) ? nothing : (; (v => Tables.getcolumn(cols, v)[valid_mask] for v in vars)...)

  #Provide missing row warning
  missing_count = rows - sum(valid_mask)
  if missing_count > 0
    @warn "$missing_count rows dropped from GeoTable because of empty or otherwise unsupported geometries."
  end

  georef(etable, domain[valid_mask])
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
  spref = spatialref(code)
  wktptr = Ref{Cstring}()
  options = ["MULTILINE=$(multiline ? "YES" : "NO")"]
  GDAL.osrexporttoprojjson(spref, wktptr, options)
  unsafe_string(wktptr[])
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
