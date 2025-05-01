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
# function isvalidprojjson(json::JSON3.Object)
function isvalidprojjson(json::Union{Dict, JSON3.Object})
  schema_path  = joinpath(@__DIR__, "projjson.schema.json")
  my_schema = Schema(JSON3.parsefile(schema_path))
  return isvalid(my_schema, json)
end

json_round_trip(j) = JSON3.read(j |> JSON3.write, Dict)

# Diff between generated json and ArchGDAL json
function diff_json(j1::J, j2::J) where J<:Union{Dict}
  nonsig_keys = ["bbox", "area", "scope", "usages", "\$schema",]
  [delete!(j1, k) for k in nonsig_keys]
  
  # TODO create a clean_gdal_json function
  try
    # GDAL has projcrs.base_crs.coordinate_system that we don't have in our WKT (and is optional)
    delete!(j1["base_crs"], "coordinate_system")
  catch
    nothing
  end

  diff = deepdiff(j1, j2)
  # remove non-required entries
  # all_changed_keys = [union(diff.removed, diff.added, keys(diff.changed))...]
  # sig_changed_keys = setdiff(all_changed_keys, nonsig_keys)
  return diff
end

function test_diff_json(j1, j2)
  diff = diff_json(j1, j2)
  all_changed_keys = [union(diff.removed, diff.added, keys(diff.changed))...]
  # isempty(all_changed_keys) && return true
  return all_changed_keys
end

# For live development. run debug_json(4275) to see differences between current and expected output
function debug_json(crs::Int; print=true, gdalprint::Bool=false)
  gdaljson = gdalprojjsondict(EPSG{crs})
  gdalprint && (@info "ArchGDAL JSON"; gdaljson |> pprintln)
  
  wktdict = GeoIO.epsg2wktdict(crs)
  print && (@info "Parsed WKT"; wktdict |> pprintln)
  
  jsondict = GeoIO.wktdict2jsondict(wktdict)
  d = diff_json(gdaljson, jsondict)
  print && d |> display
  return (wkt = wktdict, gdaljson = gdaljson, diff = d)
end

