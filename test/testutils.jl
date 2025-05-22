# note: Shapefile.jl saves Chains and Polygons as Multi
# this function is used to work around this problem
_isequal(d1::Domain, d2::Domain) = all(_isequal(g1, g2) for (g1, g2) in zip(d1, d2))
_isequal(g1, g2) = g1 == g2
_isequal(m1::Multi, m2::Multi) = m1 == m2
_isequal(g, m::Multi) = _isequal(m, g)
function _isequal(m::Multi, g)
  gs = parent(m)
  length(gs) == 1 && first(gs) == g
end

# old GDAL implementation of projjsonstring for testing
function gdalprojjsonstring(::Type{EPSG{Code}}; multiline=false) where {Code}
  spref = AG.importUserInput("EPSG:$Code")
  wktptr = Ref{Cstring}()
  options = ["MULTILINE=$(multiline ? "YES" : "NO")"]
  AG.GDAL.osrexporttoprojjson(spref, wktptr, options)
  unsafe_string(wktptr[])
end
gdalprojjsondict(code) = JSON3.read(gdalprojjsonstring(code), Dict)

# validate generated json against PROJJSON schema
function isvalidprojjson(json)
  path = joinpath(@__DIR__, "artifacts", "projjson.schema.json")
  schema = Schema(JSON3.parsefile(path))
  return isvalid(schema, json)
end

# I can not figure out why the validation test fails without this!
jsonroundtrip(json) = JSON3.read(JSON3.write(json), Dict)

# Return the "paths" of objects that exhibit differences between the two json inputs.
# By default, we clean the results from some optional projjson objects and minor
# discrepancies with GDAL's output. Set `exact = true` to disable that behavior.
# Note: diffpaths uses isapprox to compare numbers to avoid false negatives
function deltaprojjson(j1, j2; exact=false)
  diffpaths = finddiffpaths(j1, j2)

  # return full diff in case of exact comparison
  exact && return diffpaths

  # paths to ignore in approximate comparison
  # bbox, area, scope, ... are not required to
  # fully describe the coordinate reference system
  pathstoignore = ["bbox", "area", "scope", "usages", "\$schema"]

  # occasionally GDAL's ellipsoid doesn't have inverse_flattening and instead has semi_minor_axis
  # that is calculated from semi_major_axis * (1 - 1/inverse_flattening)
  push!(pathstoignore, "datum.ellipsoid.semi_minor_axis")
  push!(pathstoignore, "datum.ellipsoid.inverse_flattening")

  # we don't have the optional node base_crs.coordinate_system in our WKT, in contrast with GDAL
  push!(pathstoignore, "base_crs.coordinate_system")

  # delete insignificant json objects that are problematic for comparison testing
  for p in pathstoignore
    index = findfirst(endswith(p), diffpaths)
    if !isnothing(index)
      deleteat!(diffpaths, index)
    end
  end

  return diffpaths
end

# Find differences between two dictionaries and return the paths to those differences as json dot-notation strings.
# This function recursively compares two dictionaries and returns a vector of string paths pointing to the differences found.
# For numerical values, uses `isapprox` for comparison to avoid false negatives.
#
# Example:
#
#    julia> d1 = Dict(:A=>[0,20], :B=>3, :C=>4)
#    julia> d2 =  Dict(:A=>[10,20], :C=>4)
#    julia> finddiffpaths(d1, d2)
#    2-element Vector{String}:
#     ".A[1]"
#     ".B"
function finddiffpaths(d1::Dict, d2::Dict, path="")
  paths = String[]
  allkeys = union(keys(d1), keys(d2))
  for key in allkeys
    newpath = string(path, ".", key)
    if haskey(d1, key) && haskey(d2, key)
      if !isequalfield(d1[key], d2[key])
        append!(paths, finddiffpaths(d1[key], d2[key], newpath))
      end
    else
      push!(paths, newpath)
    end
  end

  return paths
end

function finddiffpaths(v1::Vector, v2::Vector, path)
  paths = String[]
  minlen = min(length(v1), length(v2))
  maxlen = max(length(v1), length(v2))

  for i in 1:minlen
    if !isequalfield(v1[i], v2[i])
      append!(paths, finddiffpaths(v1[i], v2[i], "$(path)[$(i)]"))
    end
  end
  # extra elements, doesn't matter which vector
  for i in (minlen + 1):maxlen
    push!(paths, "$(path)[$(i)]")
  end
  return paths
end

function finddiffpaths(v1, v2, path)
  isequalfield(v1, v2) ? nothing : [path]
end

# helper function to compare fields in JSON objects
isequalfield(x::Number, y::Number) = isapprox(x, y)
isequalfield(x, y) = isequal(x, y)

# -----------------------------------------
# Tools for live development and debugging
# -----------------------------------------

# Use DeepDiffs package to view any differences between GDAL's projjson (j1) and our's (j2).
# Differences are shown red/green color. Few insignificant keys are filtered from (j1),
# though there are still more false-negatives than deltapaths filtering
function deepdiffprojjson(j1::J, j2::J) where {J<:Union{Dict}}
  j1 = deepcopy(j1)
  keystodelete = ["bbox", "area", "scope", "usages", "\$schema"]
  for k in keystodelete
    delete!(j1, k)
  end
  try
    delete!(j1["base_crs"], "coordinate_system")
  catch
    nothing
  end
  diff = deepdiff(j1, j2)
  return diff
end

# For live development or debugging.
# run checkprojjson(4275) to see differences between current and expected json output
# The presence of red/green colored output does not neccesarly mean that there is a bug to be fixed.
# If the last printed line is an empty vector, it means the colored diff is likely a superfluous difference.
function checkprojjson(crs::Int; verbose=true)
  gdaljson = gdalprojjsondict(EPSG{crs})
  wktdict = GeoIO.epsg2wktdict(crs)
  jsondict = GeoIO.wkt2json(wktdict)

  # Show pretty-printed WKT if possible
  if verbose && isdefined(Main, :PrettyPrinting)
    @info "Parsed WKT"
    pprintln(wktdict)
  elseif verbose
    @warn "Formatted printing of WKT or JSON is unavailable because PrettyPrinting is not loaded"
  end

  # Show deep diff if possible
  if verbose && isdefined(Main, :DeepDiffs)
    @info "DeepDiff"
    display(deepdiffprojjson(gdaljson, jsondict))
  elseif verbose
    @warn "Detailed colored output is unavailable because DeepDiffs is not loaded."
  end

  diffkeys = deltaprojjson(gdaljson, jsondict)
  @info "JSON keys with a potentially significant difference from expected output:"
  display(diffkeys)
end
