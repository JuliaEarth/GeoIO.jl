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
  # generate the WKT2 string
  wkt2str = CoordRefSystems.wkt2(code)
  # create a PROJ context
  ctx = ccall((:proj_context_create, PROJ_jll.libproj), Ptr{Cvoid}, ())
  # create the CRS object from WKT2
  crs_ptr = ccall((:proj_create, PROJ_jll.libproj), Ptr{Cvoid}, (Ptr{Cvoid}, Cstring), ctx, wkt2str)
  # export to PROJJSON
  json_ptr = ccall((:proj_as_projjson, PROJ_jll.libproj), Ptr{Cchar}, (Ptr{Cvoid}, Ptr{Cvoid}, Int32), ctx, crs_ptr, 0)
  json_str = unsafe_string(json_ptr)
  # free PROJ-allocated string
  ccall(:free, Cvoid, (Ptr{Cvoid},), json_ptr)
  ccall((:proj_context_destroy, PROJ_jll.libproj), Cvoid, (Ptr{Cvoid},), ctx)
  # parse and reserialize to control multiline formatting
  json_dict = JSON3.read(json_str, Dict)
  multiline ? JSON3.write(json_dict; indent=2) : JSON3.write(json_dict)
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
