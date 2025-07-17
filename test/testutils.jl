# note: Shapefile.jl saves Chains and Polygons as Multi
# this function is used to work around this problem
isequalshp(d1::Domain, d2::Domain) = all(isequalshp(g1, g2) for (g1, g2) in zip(d1, d2))
isequalshp(g1, g2) = g1 == g2
isequalshp(m1::Multi, m2::Multi) = m1 == m2
isequalshp(g, m::Multi) = isequalshp(m, g)
function isequalshp(m::Multi, g)
  gs = parent(m)
  length(gs) == 1 && first(gs) == g
end

# GeoPackage conversion: Ring → PolyArea
isequalshp(p::PolyArea, r::Ring) = boundary(p) == r
isequalshp(r::Ring, p::PolyArea) = isequalshp(p, r)

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
  isvalid(schema, json)
end

# Return the "paths" of objects that exhibit differences between the two json inputs.
# By default, we clean the results from some optional PROJJSON objects and minor
# discrepancies with GDAL's output. Set `exact = true` to disable that behavior.
# Note: diffpaths uses isapprox to compare numbers to avoid false negatives.
function deltaprojjson(json1, json2; exact=false)
  # EC#0 (example 31288):
  # Sometimes there are floating point discrepancies between our WKT from the
  # EPSG dataset and the GDAL's PROJJSON. This is false-negative noise and is
  # dealt with properly using `isapprox` in `finddiffpaths`. For code 31288,
  # this happens in datum.prime_meridian.longitude (-17.6666666666667 vs -17.666666667)
  diffpaths = finddiffpaths(json1, json2)

  # return full diff in case of exact comparison
  exact && return diffpaths

  # paths to ignore in approximate comparison
  # bbox, area, scope, ... are not required to
  # fully describe the coordinate reference system
  pathstoignore = ["bbox", "area", "scope", "usages", "\$schema"]

  # EC#1 (example 4267):
  # Sometimes GDAL's PROJJSON ellipsoid is specified using semi_minor_axis instead of inverse_flattening.
  # Our PROJJSON ellipsoids are always specified using inverse_flattening because that is the original
  # parameterization of the WKT standard. Any other parameterization introduces conversion errors.
  # (e.g. semi_minor_axis is calculated from semi_major_axis * (1 - 1/inverse_flattening))
  push!(pathstoignore, "datum.ellipsoid.semi_minor_axis")
  push!(pathstoignore, "datum.ellipsoid.inverse_flattening")

  # EC#2 (example 22248):
  # Sometimes GDAL's PROJJSON includes an optional base_crs.coordinate_system that we can't support
  push!(pathstoignore, "base_crs.coordinate_system")

  # delete paths that are irrelevant for our comparison
  for p in pathstoignore
    index = findfirst(endswith(p), diffpaths)
    if !isnothing(index)
      deleteat!(diffpaths, index)
    end
  end

  diffpaths
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
      if !isequalvalue(d1[key], d2[key])
        append!(paths, finddiffpaths(d1[key], d2[key], newpath))
      end
    else
      push!(paths, newpath)
    end
  end

  paths
end

function finddiffpaths(v1::Vector, v2::Vector, path)
  paths = String[]
  minlen = min(length(v1), length(v2))
  maxlen = max(length(v1), length(v2))

  for i in 1:minlen
    if !isequalvalue(v1[i], v2[i])
      append!(paths, finddiffpaths(v1[i], v2[i], "$(path)[$(i)]"))
    end
  end

  # extra elements, doesn't matter which vector
  for i in (minlen + 1):maxlen
    push!(paths, "$(path)[$(i)]")
  end

  paths
end

function finddiffpaths(v1, v2, path)
  isequalvalue(v1, v2) ? nothing : [path]
end

# helper function to compare values in JSON objects
isequalvalue(x::Number, y::Number) = isapprox(x, y)
isequalvalue(x, y) = isequal(x, y)
