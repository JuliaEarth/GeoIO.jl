# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# helper type alias
const Met{T} = Quantity{T,u"𝐋",typeof(u"m")}
const Deg{T} = Quantity{T,NoDims,typeof(u"°")}

function asgeotable(table, crs=GI.crs(table))
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

function wktstring(code; format="WKT2", multiline=false)
  spref = spatialref(code)
  wktptr = Ref{Cstring}()
  options = ["FORMAT=$format", "MULTILINE=$(multiline ? "YES" : "NO")"]
  GDAL.osrexporttowktex(spref, wktptr, options)
  unsafe_string(wktptr[])
end

spatialref(code) = AG.importUserInput(codestring(code))

codestring(::Type{EPSG{Code}}) where {Code} = "EPSG:$Code"
codestring(::Type{ESRI{Code}}) where {Code} = "ESRI:$Code"

function projjson(code)
  spref = spatialref(code)
  wktptr = Ref{Cstring}()
  options = ["MULTILINE=NO"]
  GDAL.osrexporttoprojjson(spref, wktptr, options)
  str = unsafe_string(wktptr[])
  JSON3.read(str, Dict)
end

projsoncode(crs::String) = projsoncode(JSON3.read(crs, Dict))

function projsoncode(crs::Dict)
  code = parse(Int, crs["id"]["code"])
  type = crs["id"]["authority"]
  type == "EPSG" ? EPSG{code} : ESRI{code}
end

function gpqcrs(fname)
  ds = Parquet2.Dataset(fname)
  meta = Parquet2.metadata(ds)["geo"]
  json = JSON3.read(meta, Dict)
  crs = json["columns"]["geometry"]["crs"]
  isnothing(crs) ? nothing : GFT.ProjJSON(crs)
end
