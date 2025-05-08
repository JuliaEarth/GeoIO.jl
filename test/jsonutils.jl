# Helper function to create a spatial reference
spatialref(code) = AG.importUserInput(codestring(code))
codestring(::Type{EPSG{Code}}) where {Code} = "EPSG:$Code"
codestring(::Type{ESRI{Code}}) where {Code} = "ESRI:$Code"

# Old GDAL implementation of projjsonstring for testing
function gdalprojjsonstring(code; multiline=false)::String
  spref = spatialref(code)
  wktptr = Ref{Cstring}()
  options = ["MULTILINE=$(multiline ? "YES" : "NO")"]
  AG.GDAL.osrexporttoprojjson(spref, wktptr, options)
  unsafe_string(wktptr[])
end
gdalprojjsondict(code) = JSON3.read(gdalprojjsonstring(code), Dict)

# Helper function to validate PROJJSON against schema
function isvalidprojjson(json::Union{Dict,JSON3.Object})
  schema_path = joinpath(@__DIR__, "projjson.schema.json")
  schema = Schema(JSON3.parsefile(schema_path))
  return isvalid(schema, json)
end

json_round_trip(j) = JSON3.read(j |> JSON3.write, Dict)

# Use DeepDiffs package to compare the different items between ArchGDAL's projjson (j1) and our's (j2).
# Diffrences are shown red/green color. Few insignificant keys are filters from (j1),
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

function delta_keys(j1, j2)
  diff = projjson_deepdiff(j1, j2)
  all_changed_keys = [union(diff.removed, diff.added, keys(diff.changed))...]
  return all_changed_keys
end

# For live development.
# run debug_json(4275); to see differences between current and expected json output
# If there is no red/green colored output, then all is good
function debug_json(crs::Int; verbose=true, gdalprint::Bool=false)
  gdaljson = gdalprojjsondict(EPSG{crs})
  gdalprint && (@info "ArchGDAL JSON"; gdaljson |> pprintln)

  wktdict = GeoIO.epsg2wktdict(crs)
  verbose && (@info "Parsed WKT"; wktdict |> pprintln)

  jsondict = GeoIO.wkt2json(wktdict)
  d = projjson_deepdiff(gdaljson, jsondict)
  verbose && d |> display
  return (wkt=wktdict, gdaljson=gdaljson, diff=d, test_diff=delta_keys(gdaljson, jsondict))
end
