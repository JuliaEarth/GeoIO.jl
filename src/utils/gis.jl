# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# helper function to extract Tables.jl table from GIS formats
function gistable(fname; layer=0, numbertype=Float64, kwargs...)
  if endswith(fname, ".shp")
    return SHP.Table(fname; kwargs...)
  elseif endswith(fname, ".geojson")
    return GJS.read(fname; numbertype, kwargs...) 
  elseif endswith(fname, ".parquet")
    return GPQ.read(fname; kwargs...)
  else # fallback to GDAL
    data = AG.read(fname; kwargs...)
    return AG.getlayer(data, layer)
  end
end

# helper function to convert Tables.jl table to GeoTable
function asgeotable(table)
  crs = GI.crs(table)
  cols = Tables.columns(table)
  names = Tables.columnnames(cols)
  gcol = geomcolumn(names)
  vars = setdiff(names, [gcol])
  etable = isempty(vars) ? nothing : (; (v => Tables.getcolumn(cols, v) for v in vars)...)
  geoms = Tables.getcolumn(cols, gcol)
  # subset for missing geoms
  miss = findall(g -> ismissing(g) || isnothing(g), geoms)
  if !isempty(miss)
    @warn """$(length(miss)) rows dropped from GeoTable because of missing geometries. 
    Please use GeoIO.loadvalues(; rows=:invalid) to load values without geometries.
    """
  end
  valid = setdiff(1:length(geoms), miss)
  domain = geom2meshes.(geoms[valid], Ref(crs))
  etable = isnothing(etable) || isempty(miss) ? etable : Tables.subset(etable, valid)
  georef(etable, domain)
end

# helper function to find the geometry column of a table
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
