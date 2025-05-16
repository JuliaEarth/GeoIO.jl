# Prefer a json structure that is more inline with GDAL's or our WKT input
const GDALcompat = true

rootkey(d) = nothing
function rootkey(d::Dict)
  length(keys(d)) == 1 || error("Dictionary must have exactly one key")
  return first(keys(d))
end

# From a vector of WKT items, find ones that start with `key`
function finditems(key::Symbol, list::Vector)::Vector{Dict}
  filter(x->rootkey(x)==key, list)
end

function finditem(key::Symbol, list::Vector)::Union{Dict, Nothing}
  found = filter(x->rootkey(x)==key, list)
  return isempty(found) ? nothing : found[1]
end

function finditem(keys::Vector{Symbol}, list::Vector)::Union{Dict, Nothing}
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
    error("Multiple items found for keys: $keys")
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
    error("Unimplemented CRS type: $type")
  end
end

# process GEOGCRS or GEODCRS nodes, either if they're at top-level or under PROJCRS
function wkt2json_geog(wkt::Dict)
  @assert wkt |> keys |> collect |> first in [:GEOGCRS, :GEODCRS]
  jsondict = Dict{String, Any}()
  geosubtype = rootkey(wkt)
  jsondict["type"] =
    if geosubtype == :GEOGCRS
      "GeographicCRS"
    elseif geosubtype == :GEODCRS
      "GeodeticCRS"
    else
      error("Should be unreachable")
    end
  
  jsondict["name"] = wkt[geosubtype][1]

  ## DESIGN, there are two types of datum entries
  gendatum = wkt2json_general_datum(wkt)
  jsondict[gendatum[1]] = gendatum[2]
  # design: bit of redundancy between the [2] and [:ENSEMBLE] inside the function

  # DESIGN: either pass specifically the CS and AXIS arr elements or all the dict. Caveate, for later projected there is cs nested inside
  # coordinate_system is optional. In our WKT, there is not CS node in PROJCRS.BASEGEOGCRS 
  if !isnothing(finditem(:CS, wkt[geosubtype]))
    jsondict["coordinate_system"] = wkt2json_cs(wkt)
  end

  jsondict["id"] = wkt2json_id(wkt[geosubtype][end])
  return jsondict 
end

# Schema requires keys: "name", "base_crs", "conversion", and "coordinate_system"
function wkt2json_proj(wkt::Dict)
    @assert wkt |> keys |> collect == [:PROJCRS]
    jsondict = Dict{String, Any}()
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
  jsondict = Dict{String, Any}()
  jsondict["name"] = wkt[:CONVERSION][1]
  
  method = Dict{String, Any}()
  method["name"] = wkt[:CONVERSION][2][:METHOD][1]
  jsondict["method"] = method
  
  jsondict["parameters"] = []
  params = finditems(:PARAMETER, wkt[:CONVERSION])
  for param in params
    paramdict = Dict{String, Any}()
    paramdict["name"] = param[:PARAMETER][1]
    # Sometimes there are rounding discrepancies between GDAL's WKT and our WKT. 
    # This becomes problematic when testing is done by comparing our projjson with GDAL's.
    # This is mitigated if we can use Omar's fork of DeepDiffs or find_diff_path in test/jsonutils.jl as they use isapprox for comparison.
    # paramdict["value"] = GDALcompat ? round(param[:PARAMETER][2], digits=9) : param[:PARAMETER][2]
    paramdict["value"] = param[:PARAMETER][2]
    
    unit = wkt2json_get_unit(param[:PARAMETER])
    if !isnothing(unit)
      paramdict["unit"] = unit
    end
    paramdict["id"] = wkt2json_id(param[:PARAMETER][4])
    push!(jsondict["parameters"], paramdict)
  end

  if !GDALcompat && rootkey(wkt[:CONVERSION][end]) == :ID
    jsondict["id"] = wkt2json_id(wkt[:CONVERSION][end])
  end
  
  method["id"] = wkt2json_id(wkt[:CONVERSION][2][:METHOD][end])
  return jsondict
end

# takes top-level node because for json "coordinate_system" requires information from AXIS and UNIT WKT nodes, that are outside the CS node.
# Schema requires keys: "subtype" and "axis"
function wkt2json_cs(wkt::Dict)
  @assert wkt |> keys |> collect |> first in [:GEOGCRS, :GEODCRS, :PROJCRS]
    csdict = Dict{String, Any}()
    geosubtype = rootkey(wkt)

    cstype = finditem(:CS, wkt[geosubtype])[:CS][1]
    # cstype::Symbol = wkt[geosubtype][3][:CS][1]
    csdict["subtype"] = string(cstype)

    csdict["axis"] = []
    axes = finditems(:AXIS, wkt[geosubtype])
    length(axes) > 0 || error("Axis entries are required, none are found")
    for axis in axes
        axisdict = Dict{String, Any}()

        # Parse axis name and abbreviation
        name = split(axis[:AXIS][1], " (")
        axisdict["name"] = name[1]
        axisdict["abbreviation"] = name[2][1:end-1]
        
        dir = string(axis[:AXIS][2])
        if dir in ("North", "South", "East", "West")
          dir = lowercase(dir)
        end
        axisdict["direction"] = dir

        # Get unit from the CS node, then try the AXIS node if not found
        unit = wkt2json_get_unit(wkt[geosubtype])
        if isnothing(unit)
          unit = wkt2json_get_unit(axis[:AXIS])
        end
        axisdict["unit"] = unit
        
        meridian = finditem(:MERIDIAN, axis[:AXIS])
        if !isnothing(meridian)
          axisdict["meridian"] = Dict{String, Any}()
          axisdict["meridian"]["longitude"] = meridian[:MERIDIAN][1]
        end
        
        push!(csdict["axis"], axisdict)
    end

    return csdict
end

function wkt2json_get_unit(axis::Vector)
  unit = finditem([:ANGLEUNIT, :LENGTHUNIT, :SCALEUNIT], axis)
  isnothing(unit) && return nothing
  unittype = rootkey(unit)
  name = unit[unittype][1]

  # json unit object can be a simple string if its one of the following, or a full object otherwise
  if name in ("metre", "degree", "unity")
    return name
  else
    unitdict = Dict{String, Any}()
    unitdict["name"] = name
    unitdict["conversion_factor"] = unit[unittype][2]
    unitdict["type"] =
      if unittype == :LENGTHUNIT
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

function value_or_unit_value(value::Number, context::Vector)
  unit = wkt2json_get_unit(context)
  if unit isa String
    return value
  end
  uvdict = Dict("unit" => unit, "value" => value)
  return uvdict
end

function wkt2json_general_datum(wkt::Dict)
  name = ""
  jsondict = Dict{String,Any}()
  geosubtype = rootkey(wkt)

  datum = finditem([:ENSEMBLE, :DATUM], wkt[geosubtype])
  if rootkey(datum) == :ENSEMBLE
    name = "datum_ensemble"
    jsondict = wkt2json_long_datum(datum)
  elseif rootkey(datum) == :DATUM
    name = "datum"
    jsondict = wkt2json_short_datum(datum)

    # dynamic and meridian ought to be in wkt2json_short_datum but is here now in order not to break encapsulation
    dynamic = finditem(:DYNAMIC, wkt[geosubtype])
    if !isnothing(dynamic)
      jsondict["frame_reference_epoch"] = dynamic[:DYNAMIC][1][:FRAMEEPOCH][1]
      jsondict["type"] = "DynamicGeodeticReferenceFrame"
    else
      jsondict["type"] = "GeodeticReferenceFrame"
    end
    meridian = finditem(:PRIMEM, wkt[geosubtype])
    if !isnothing(meridian)
      jsondict["prime_meridian"] = Dict{String, Any}()
      jsondict["prime_meridian"]["name"] = meridian[:PRIMEM][1]
      longitude = value_or_unit_value(meridian[:PRIMEM][2], meridian[:PRIMEM])
      jsondict["prime_meridian"]["longitude"] = longitude
    end
  else
    error("Didn't find a datum node that is either ENSEMBLE or DATUM.")
  end

  return (name, jsondict)
end

# Schema requires keys: "name" and "ellipsoid", optionally have "type", "anchor_epoch", "prime_meridian"
# this function should produce object that matches geodetic_reference_frame in the schema. 
function wkt2json_short_datum(wkt::Dict)
  @assert wkt |> keys |> collect == [:DATUM]

  jsondict = Dict{String, Any}()
  jsondict["name"] = wkt[:DATUM][1]

  ellipsoid = finditem(:ELLIPSOID, wkt[:DATUM])
  jsondict["ellipsoid"] = wkt2json_ellipsoid(ellipsoid)

  anchorepoch = finditem(:ANCHOREPOCH, wkt[:DATUM])
  if !isnothing(anchorepoch)
    jsondict["anchor_epoch"] = anchorepoch[:ANCHOREPOCH][1]
  end
  return jsondict
end

# Schema requires keys: "name", "members", "accuracy", and optionally "ellipsoid"
function wkt2json_long_datum(wkt::Dict)
  @assert wkt |> keys |> collect == [:ENSEMBLE]
  jsondict = Dict{String, Any}()
  jsondict["name"] = wkt[:ENSEMBLE][1]
  
  jsondict["members"] = []
  members = finditems(:MEMBER, wkt[:ENSEMBLE])
  for m in members
    mdict = Dict{String, Any}()
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
  jsondict = Dict{String, Any}()
  jsondict["name"] = wkt[:ELLIPSOID][1]
  semimajor = value_or_unit_value(wkt[:ELLIPSOID][2], wkt[:ELLIPSOID])
  jsondict["semi_major_axis"] = semimajor
  jsondict["inverse_flattening"] = wkt[:ELLIPSOID][3]
  return jsondict
end

function wkt2json_id(iddict::Dict)::Dict
  @assert iddict  |> keys |> collect == [:ID]
  jsondict = Dict{String, Any}()
  jsondict["authority"] = iddict[:ID][1]
  jsondict["code"] = iddict[:ID][2]
  return jsondict
end

# --------------------------------------
# Convert from WKT string to WKT dict
# --------------------------------------

function epsg2wktdict(epsg::Int)::Union{Dict, Nothing}
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
epsg2wktdict(::Type{EPSG{I}}) where I = epsg2wktdict(I)


function process_expr(elem, dict::Dict)
  k = dict |> keys |> collect |> first
  if elem isa Expr
    expr_name = elem.args[1]
    child_dict = Dict(expr_name => [])
    push!(dict[k], child_dict)
    for child_elem in elem.args[2:end]
      process_expr(child_elem, child_dict)
    end
  elseif elem isa Union{String, Number, Symbol}
    push!(dict[k], elem)
  else
    error("The AST representation of the WKT file contains an unexpected node")
  end
  return dict
end
