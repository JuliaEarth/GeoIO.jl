# Prefer a json structure that is more inline with GDAL's or our WKT input
const GDALcompat = true

rootkey(d) = nothing
function rootkey(d::Dict)
  length(keys(d)) == 1 || error("Dictionary must have exactly one key.")
  return first(keys(d))
end

# From a vector of WKT nodes, find ones that start with `key`
function finditems(key::Symbol, list::Vector)::Vector{Dict}
  filter(x -> rootkey(x) == key, list)
end

function finditem(key::Symbol, list::Vector)::Union{Dict,Nothing}
  found = filter(x -> rootkey(x) == key, list)
  return isempty(found) ? nothing : found[1]
end

function finditem(keys::Vector{Symbol}, list::Vector)::Union{Dict,Nothing}
  found = []
  for key in keys
    i = finditem(key, list)
    !isnothing(i) && push!(found, i)
  end

  if length(found) == 1
    return found[1]
  elseif length(found) == 0
    return nothing
  elseif length(found) > 1
    error("Multiple items found for keys: $keys. Only one was expected")
  end
end

# --------------------------------------
# Convert From WKT dict to projjson dict
# --------------------------------------

function wkt2json(wkt::Dict)
  type = rootkey(wkt)
  if type == :GEOGCRS
    return wkt2json_geog(wkt)
  elseif type == :GEODCRS
    return wkt2json_geog(wkt)
  elseif type == :PROJCRS
    return wkt2json_proj(wkt)
  else
    error("WKT to PROJJSON conversion for CRS type: $type is not supported yet.")
  end
end

# Returns geodetic_crs projjson object.
# Can be either GEOGCRS or GEODCRS WKT nodes. Either as top-level crs or under PROJCRS
function wkt2json_geog(wkt::Dict)
  @assert wkt |> keys |> collect |> first in [:GEOGCRS, :GEODCRS]
  jsondict = Dict{String,Any}()
  geosubtype = rootkey(wkt)
  jsondict["type"] = if geosubtype == :GEOGCRS
    "GeographicCRS"
  elseif geosubtype == :GEODCRS
    "GeodeticCRS"
  else
    error("Should be unreachable")
  end

  jsondict["name"] = wkt[geosubtype][1]

  datum = wkt2json_general_datum(wkt)
  jsondict[datum.name] = datum.json

  # in our WKT there is no CS node in PROJCRS.BASEGEOGCRS
  if !isnothing(finditem(:CS, wkt[geosubtype]))
    jsondict["coordinate_system"] = wkt2json_cs(wkt)
  end

  jsondict["id"] = wkt2json_id(wkt[geosubtype][end])
  return jsondict
end

# Schema requires keys: "name", "base_crs", "conversion", and "coordinate_system"
function wkt2json_proj(wkt::Dict)
  @assert wkt |> keys |> collect == [:PROJCRS]
  jsondict = Dict{String,Any}()
  jsondict["type"] = "ProjectedCRS"
  jsondict["name"] = wkt[:PROJCRS][1]

  basecrs = Dict(:GEOGCRS => wkt[:PROJCRS][2][:BASEGEOGCRS])
  jsondict["base_crs"] = wkt2json_geog(basecrs)

  jsondict["conversion"] = wkt2json_conversion(wkt[:PROJCRS][3])
  jsondict["coordinate_system"] = wkt2json_cs(wkt)

  jsondict["id"] = wkt2json_id(wkt[:PROJCRS][end])
  return jsondict
end

# Schema requires keys: "name" and "method"
function wkt2json_conversion(wkt::Dict)
  @assert wkt |> keys |> collect == [:CONVERSION]
  jsondict = Dict{String,Any}()
  jsondict["name"] = wkt[:CONVERSION][1]

  jsondict["parameters"] = []
  params = finditems(:PARAMETER, wkt[:CONVERSION])
  for param in params
    paramdict = Dict{String,Any}()
    paramdict["name"] = param[:PARAMETER][1]
    paramdict["value"] = param[:PARAMETER][2]

    unit = wkt2json_unit(param[:PARAMETER])
    if !isnothing(unit)
      paramdict["unit"] = unit
    end
    paramdict["id"] = wkt2json_id(param[:PARAMETER][4])
    push!(jsondict["parameters"], paramdict)
  end

  if !GDALcompat && rootkey(wkt[:CONVERSION][end]) == :ID
    jsondict["id"] = wkt2json_id(wkt[:CONVERSION][end])
  end

  method = Dict{String,Any}()
  method["name"] = wkt[:CONVERSION][2][:METHOD][1]
  method["id"] = wkt2json_id(wkt[:CONVERSION][2][:METHOD][end])
  jsondict["method"] = method
  return jsondict
end

# This function breaks the convention by taking the parent CRS node instead of the CS node,
# because projjson coordinate_system requires information from sibling AXIS and UNIT nodes.
# Schema requires keys: "subtype" and "axis"
function wkt2json_cs(wkt::Dict)
  @assert wkt |> keys |> collect |> first in [:GEOGCRS, :GEODCRS, :PROJCRS]
  csdict = Dict{String,Any}()
  geosubtype = rootkey(wkt)

  cstype = finditem(:CS, wkt[geosubtype])[:CS][1]
  csdict["subtype"] = string(cstype)

  csdict["axis"] = []
  axes = finditems(:AXIS, wkt[geosubtype])
  length(axes) > 0 || error("Axis entries are required, none are found")
  for axis in axes
    axisdict = Dict{String,Any}()

    # parse axis name and abbreviation
    name = split(axis[:AXIS][1], " (")
    axisdict["name"] = name[1]
    axisdict["abbreviation"] = name[2][1:(end - 1)]

    dir = string(axis[:AXIS][2])
    if dir in ("North", "South", "East", "West")
      dir = lowercase(dir)
    end
    axisdict["direction"] = dir

    # if no unit is found in AXIS node, get it from parent CS node
    unit = wkt2json_unit(axis[:AXIS])
    if isnothing(unit)
      unit = wkt2json_unit(wkt[geosubtype])
    end
    axisdict["unit"] = unit

    meridian = finditem(:MERIDIAN, axis[:AXIS])
    if !isnothing(meridian)
      axisdict["meridian"] = Dict{String,Any}()
      axisdict["meridian"]["longitude"] = valueunit(meridian[:MERIDIAN][1], meridian[:MERIDIAN])
    end

    push!(csdict["axis"], axisdict)
  end

  return csdict
end

function wkt2json_unit(axis::Vector)
  unit = finditem([:ANGLEUNIT, :LENGTHUNIT, :SCALEUNIT], axis)
  isnothing(unit) && return nothing
  unittype = rootkey(unit)
  name = unit[unittype][1]

  # "unit" projjson object can be a simple string if it's one of the following
  if name in ("metre", "degree", "unity")
    return name
  else
    unitdict = Dict{String,Any}()
    unitdict["name"] = name
    unitdict["conversion_factor"] = unit[unittype][2]
    unitdict["type"] = if unittype == :LENGTHUNIT
      "LinearUnit"
    elseif unittype == :ANGLEUNIT
      "AngularUnit"
    elseif unittype == :SCALEUNIT
      "ScaleUnit"
    else
      error("Unit type $unittype is not yet supported")
    end
    return unitdict
  end
  return nothing
end

# See value_in_metre_or_value_and_unit in schema
function valueunit(value::Number, context::Vector)
  unit = wkt2json_unit(context)
  if unit isa String
    return value
  else
    return Dict("unit" => unit, "value" => value)
  end
end

# geodetic_crs requires either datum or datum_ensemble objects, depending on which is present in WKT
# See one_and_only_one_of_datum_or_datum_ensemble in schema
function wkt2json_general_datum(wkt::Dict)
  name = ""
  jsondict = Dict{String,Any}()
  geosubtype = rootkey(wkt)

  datum = finditem([:ENSEMBLE, :DATUM], wkt[geosubtype])
  if rootkey(datum) == :ENSEMBLE
    name = "datum_ensemble"
    jsondict = wkt2json_datumensemble(datum)
  elseif rootkey(datum) == :DATUM
    name = "datum"
    jsondict = wkt2json_datum(datum)

    # dynamic and meridian ought to be in wkt2json_short_datum but is here now in order not to break encapsulation
    dynamic = finditem(:DYNAMIC, wkt[geosubtype])
    if !isnothing(dynamic)
      jsondict["frame_reference_epoch"] = dynamic[:DYNAMIC][1][:FRAMEEPOCH][1]
      jsondict["type"] = "DynamicGeodeticReferenceFrame"
    else
      jsondict["type"] = "GeodeticReferenceFrame"
    end
    prime = finditem(:PRIMEM, wkt[geosubtype])
    if !isnothing(prime)
      jsondict["prime_meridian"] = Dict{String,Any}()
      jsondict["prime_meridian"]["name"] = prime[:PRIMEM][1]
      longitude = valueunit(prime[:PRIMEM][2], prime[:PRIMEM])
      jsondict["prime_meridian"]["longitude"] = longitude
    end
  else
    error("An ENSEMBLE or DATUM node is required, none is found.")
  end

  return (name=name, json=jsondict)
end

# Returns geodetic_reference_frame projjson object.
# Schema requires keys: "name" and "ellipsoid", optionally "type", "anchor_epoch", "prime_meridian"
function wkt2json_datum(wkt::Dict)
  @assert wkt |> keys |> collect == [:DATUM]
  jsondict = Dict{String,Any}()
  jsondict["name"] = wkt[:DATUM][1]

  ellipsoid = finditem(:ELLIPSOID, wkt[:DATUM])
  jsondict["ellipsoid"] = wkt2json_ellipsoid(ellipsoid)

  anchorepoch = finditem(:ANCHOREPOCH, wkt[:DATUM])
  if !isnothing(anchorepoch)
    jsondict["anchor_epoch"] = anchorepoch[:ANCHOREPOCH][1]
  end
  return jsondict
end

# Returns datum_ensemble projjson object.
# Schema requires keys: "name", "members", "accuracy", and optionally "ellipsoid"
function wkt2json_datumensemble(wkt::Dict)
  @assert wkt |> keys |> collect == [:ENSEMBLE]
  jsondict = Dict{String,Any}()
  jsondict["name"] = wkt[:ENSEMBLE][1]

  jsondict["members"] = []
  members = finditems(:MEMBER, wkt[:ENSEMBLE])
  for m in members
    mdict = Dict{String,Any}()
    mdict["name"] = m[:MEMBER][1]
    mdict["id"] = wkt2json_id(m[:MEMBER][2])
    push!(jsondict["members"], mdict)
  end

  accuracy = finditem(:ENSEMBLEACCURACY, wkt[:ENSEMBLE])
  jsondict["accuracy"] = string(float(accuracy[:ENSEMBLEACCURACY][1]))

  ellipsoid = finditem(:ELLIPSOID, wkt[:ENSEMBLE])
  if !isnothing(ellipsoid)
    jsondict["ellipsoid"] = wkt2json_ellipsoid(ellipsoid)
  end

  jsondict["id"] = wkt2json_id(wkt[:ENSEMBLE][end])
  return jsondict
end

function wkt2json_ellipsoid(wkt::Dict)
  @assert wkt |> keys |> collect == [:ELLIPSOID]
  jsondict = Dict{String,Any}()
  jsondict["name"] = wkt[:ELLIPSOID][1]
  semimajor = valueunit(wkt[:ELLIPSOID][2], wkt[:ELLIPSOID])
  jsondict["semi_major_axis"] = semimajor
  jsondict["inverse_flattening"] = wkt[:ELLIPSOID][3]
  return jsondict
end

function wkt2json_id(iddict::Dict)::Dict
  @assert iddict |> keys |> collect == [:ID]
  jsondict = Dict{String,Any}()
  jsondict["authority"] = iddict[:ID][1]
  jsondict["code"] = iddict[:ID][2]
  return jsondict
end

# --------------------------------------
# Convert from WKT string to WKT dict
# --------------------------------------

function epsg2wktdict(epsg::Int)::Union{Dict,Nothing}
  str = CoordRefSystems.wkt2(EPSG{epsg})
  # TODO upstream to CoordRefSystems
  if startswith(str, "WKT is not supported")
    @warn "EPSG:$epsg is not WKT supported"
    return nothing
  end
  expr = Meta.parse(str)
  dict = Dict(:root => [])
  process_expr(expr, dict)
  return dict[:root][1]
end
epsg2wktdict(::Type{EPSG{I}}) where {I} = epsg2wktdict(I)

function process_expr(elem, dict::Dict)
  k = first(collect(keys(dict)))
  if elem isa Expr
    expr_name = elem.args[1]
    child_dict = Dict(expr_name => [])
    push!(dict[k], child_dict)
    for child_elem in elem.args[2:end]
      process_expr(child_elem, child_dict)
    end
  elseif elem isa Union{String,Number,Symbol}
    push!(dict[k], elem)
  else
    error("The AST representation of the WKT file contains an unexpected node.")
  end
  return dict
end
