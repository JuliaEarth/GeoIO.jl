# Old GDAL implementation of projjsonstring for testing
function gdalprojjsonstring(code::Type{EPSG{Code}}; multiline=false) where {Code}
  spref = AG.importUserInput("EPSG:$Code")
  wktptr = Ref{Cstring}()
  options = ["MULTILINE=$(multiline ? "YES" : "NO")"]
  AG.GDAL.osrexporttoprojjson(spref, wktptr, options)
  unsafe_string(wktptr[])
end
gdalprojjsondict(code) = JSON3.read(gdalprojjsonstring(code), Dict)

# Validate generated json against PROJJSON schema
function isvalidprojjson(json::Union{Dict,JSON3.Object})
  schema_path = joinpath(@__DIR__, "artifacts", "projjson.schema.json")
  schema = Schema(JSON3.parsefile(schema_path))
  return isvalid(schema, json)
end

# I can not figure out why tests fail without this!
json_round_trip(j) = JSON3.read(JSON3.write(j), Dict)

# Use DeepDiffs package to compare the different items between GDAL's projjson (j1) and our's (j2).
# Diffrences are shown red/green color. Few insignificant keys are filtered from (j1),
# though there are still more false-negatives than delta_paths filtering
function projjson_deepdiff(j1::J, j2::J) where {J<:Union{Dict}}
  nonsig_keys = ["bbox", "area", "scope", "usages", "\$schema"]
  [delete!(j1, k) for k in nonsig_keys]
  try
    delete!(j1["base_crs"], "coordinate_system")
  catch
    nothing
  end
  diff = deepdiff(j1, j2)
  return diff
end

# Return the json "paths" to the different objects between the two json inputs
# By default, we clean the results from some optional projjson entries or minor
# discrepancies with GDAL output. Set ignore_insig = true to disable that behavior.
function delta_paths(j1, j2; ignore_insig::Bool=true)::Vector
  diff_paths = find_diff_paths(j1, j2)
  ignore_insig == false && return diff_paths

  insig_keys = ["bbox", "area", "scope", "usages", "\$schema"]
  # Occasionally GDAL's json doesn't have inverse_flattening and instead has semi_minor_axis
  #that is calculated from semi_major_axis * (1 - 1/inverse_flattening). Both cases are valid.
  push!(insig_keys, "datum.ellipsoid.semi_minor_axis")
  push!(insig_keys, "datum.ellipsoid.inverse_flattening")
  # We don't get the optional node projcrs.base_crs.coordinate_system in our WKT, in contrast with GDAL
  push!(insig_keys, "base_crs.coordinate_system")

  # delete insignificant json entries that are problematic for comparison
  for k in insig_keys
    ind = findfirst(endswith(k), diff_paths)
    if !isnothing(ind)
      deleteat!(diff_paths, ind)
    end
  end

  return diff_paths
end

_isapprox(x::Number, y::Number) = isapprox(x, y)
_isapprox(x, y) = isequal(x, y)

function find_diff_paths(d1::Dict, d2::Dict, path="")
  paths = String[]
  all_keys = union(keys(d1), keys(d2))
  for key in all_keys
    new_path = isempty(path) ? string(key) : string(path, ".", key)
    if haskey(d1, key) && haskey(d2, key)
      if !_isapprox(d1[key], d2[key])
        append!(paths, find_diff_paths(d1[key], d2[key], new_path))
      end
    else
      push!(paths, new_path)
    end
  end

  return paths
end

function find_diff_paths(v1::Vector, v2::Vector, path)
  paths = String[]
  min_length = min(length(v1), length(v2))
  max_length = max(length(v1), length(v2))

  for i in 1:min_length
    if !_isapprox(v1[i], v2[i])
      append!(paths, find_diff_paths(v1[i], v2[i], "$(path)[$(i)]"))
    end
  end

  for i in (min_length + 1):max_length
    push!(paths, "$(path)[$(i)]")
  end
  return paths
end

function find_diff_paths(v1, v2, path)
  _isapprox(v1, v2) ? String[] : [path]
end

# For live development.
# run debug_json(4275); to see differences between current and expected json output
# If there is no red/green colored output, then all is good
function debug_json(crs::Int; verbose=true, gdalprint::Bool=false)
  if !isdefined(Main, :PrettyPrinting)
    verbose = false
    @warn "Verbose printing of WKT or JSON is unavailable because PrettyPrinting is not loaded"
  end
  gdaljson = gdalprojjsondict(EPSG{crs})
  verbose && gdalprint && (@info "ArchGDAL JSON"; gdaljson |> pprintln)
  wktdict = GeoIO.epsg2wktdict(crs)
  verbose && (@info "Parsed WKT"; wktdict |> pprintln)

  jsondict = GeoIO.wkt2json(wktdict)

  if !isdefined(Main, :DeepDiffs)
    @warn "Detailed colored output is unavailable because DeepDiffs is not loaded."
  else
    d = projjson_deepdiff(gdaljson, jsondict)
    verbose && (@info "DeepDiff"; d |> display)
  end

  diffkeys = delta_paths(gdaljson, jsondict)
  @info "JSON keys with a potentially significant difference from expected output"
  display(diffkeys)
  return (wkt=wktdict, diffkeys=diffkeys)
end
