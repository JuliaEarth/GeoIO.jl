# Prefer a json structure that is more inline with GDAL's or our WKT input
const GDALcompat = true

get_main_key(d) = nothing
function get_main_key(d::Dict)
  @assert d |> keys |> length == 1
  return d |> keys |> first
end

# From a Vector{Dict}, get Dict items that all has a particular key  
function get_items_with_key(key::Symbol, list::Vector)
  filter(x->get_main_key(x)==key, list)
end

function get_item_with_key(key::Symbol, list::Vector)
  found = filter(x->get_main_key(x)==key, list)
  return isempty(found) ? nothing : found
end

function get_item_with_keys(keys::Vector{Symbol}, list::Vector)
  found = []
  for key in keys
    f = get_item_with_key(key, list)
    !isnothing(f) && push!(found, f)
  end

  if length(found) == 1
    return found[1]
  elseif length(found) == 0
    return nothing
  elseif length(found) > 1
    error("Multiple items found for keys: $keys")
  end
end

wktdict_crs_type(wkt::Dict) = get_main_key(wkt)

###
# Construct projjson compliant Dict from From WKT2 Dict 
###

function wktdict2jsondict(wkt::Dict)
  type = get_main_key(wkt)
  if type == :GEOGCRS
    return wktdict2jsondict_geog(wkt, :GEOGCRS)
  elseif type == :GEODCRS
    return wktdict2jsondict_geog(wkt, :GEODCRS)
  elseif type == :PROJCRS
    return wktdict2jsondict_proj(wkt)
  else
    error("Unimplemented CRS type: $type")
  end
end

function wktdict2jsondict_proj(wkt::Dict)
    @assert wkt |> keys |> collect == [:PROJCRS]
    jsondict = Dict{String, Any}()
    jsondict["type"] = "ProjectedCRS"
    jsondict["name"] = wkt[:PROJCRS][1]
    
    base_crs_dict = Dict(:GEOGCRS => wkt[:PROJCRS][2][:BASEGEOGCRS])
    base_crs_type = get_main_key(base_crs_dict)
    jsondict["base_crs"] = wktdict2jsondict_geog(base_crs_dict, base_crs_type)
    
    jsondict["conversion"] = wktdict2jsondict_conversion(wkt[:PROJCRS][3])
    jsondict["coordinate_system"] = wktdict2jsondict_cs(wkt, :PROJCRS)
    
    jsondict["id"] = wktdict2jsondict_id(wkt[:PROJCRS][end])
    
    return jsondict
end

function wktdict2jsondict_conversion(wkt::Dict)
  @assert wkt |> keys |> collect == [:CONVERSION]
  jsondict = Dict{String, Any}()
  jsondict["name"] = wkt[:CONVERSION][1]
  
  method_dict = Dict{String, Any}()
  method_dict["name"] = wkt[:CONVERSION][2][:METHOD][1]
  method_dict["id"] = wktdict2jsondict_id(wkt[:CONVERSION][2][:METHOD][end])
  jsondict["method"] = method_dict
  
  jsondict["parameters"] = []
  param_entries = get_items_with_key(:PARAMETER, wkt[:CONVERSION])
  for param in param_entries
    param_dict = Dict{String, Any}()
    param_dict["name"] = param[:PARAMETER][1]
    # There few rounding discrepancies between GDAL and our WKT. Which is problematic when testing by comparing with GDAL.
    # This is properly avoided if we use Omar's fork of DeepDiffs or find_diff_path in test/jsonutils.jl as they use isapprox for comparison.
    # param_dict["value"] = GDALcompat ? round(param[:PARAMETER][2], digits=9) : param[:PARAMETER][2]
    param_dict["value"] = param[:PARAMETER][2]
    
    unit = wktdict2jsondict_get_unit(param[:PARAMETER])
    if !isnothing(unit)
      # TODO: process full UNIT nodes, in addition to simple UNIT=>string ones
      # makes 2/700 error, UNIT direct string shouldn't be other than ["metre", "degree", "unity"] 
      param_dict["unit"] = unit[1]
    end
    param_dict["id"] = wktdict2jsondict_id(param[:PARAMETER][4])
    push!(jsondict["parameters"], param_dict)
  end
  
  if !GDALcompat && get_main_key(wkt[:CONVERSION][end]) == :ID
    jsondict["id"] = wktdict2jsondict_id(wkt[:CONVERSION][end])
  end
  return jsondict
end

# Process GEOGCRS or GEODCRS nodes, either if they're at WKT top level or under PROJCRS
function wktdict2jsondict_geog(wkt::Dict, geo_sub_type::Symbol)
  @assert wkt |> keys |> collect |> first in [:GEOGCRS, :GEODCRS]
  jsondict = Dict{String, Any}()
  
  jsondict["type"] = 
    if geo_sub_type == :GEOGCRS
      "GeographicCRS"
    elseif geo_sub_type == :GEODCRS
      "GeodeticCRS"
    else
      error("Should be unreachable")
    end
  
  jsondict["name"] = wkt[geo_sub_type][1]

  ## DESIGN, there are two types of datum entries
  gen_datum = wktdict2jsondict_general_datum(wkt)
  jsondict[gen_datum[1]] = gen_datum[2]
  # design: bit of redundancy between the [2] and [:ENSEMBLE] inside the function

  # DESIGN: either pass specifically the CS and AXIS arr elements or all the dict. Caveate, for later projected there is cs nested inside
  # coordinate_system is optional. In our WKT, there is not CS node in PROJCRS.BASEGEOGCRS 
  if !isnothing(get_item_with_key(:CS, wkt[geo_sub_type]))
    jsondict["coordinate_system"] = wktdict2jsondict_cs(wkt, geo_sub_type)
  end

  jsondict["id"] = wktdict2jsondict_id(wkt[geo_sub_type][end])
  return jsondict 
end

function wktdict2jsondict_cs(wkt::Dict, geo_sub_type)
  # "required" : [ "subtype", "axis" ],
  # pass base_crs because for coordinate_system: AXIS and potentially UNIT are both on base_crs level
    cs_dict = Dict{String, Any}()

    # get_items_with_key Because with DYNAMIC, CS is not at the same location
    cs_type = get_items_with_key(:CS, wkt[geo_sub_type])[1][:CS][1]
    # cs_type::Symbol = wkt[geo_sub_type][3][:CS][1]
    cs_dict["subtype"] = string(cs_type)

    cs_dict["axis"] = []
    axis_entries = get_items_with_key(:AXIS, wkt[geo_sub_type])
    length(axis_entries) > 0 || error("Axis entries are required, non are found")
    for axis in axis_entries
        axis_dict = Dict{String, Any}()

        # Parse axis name and abbreviation
        name_parts = split(axis[:AXIS][1], " (")
        axis_dict["name"] = name_parts[1]
        axis_dict["abbreviation"] = strip(name_parts[2], ')')

        axis_dict["direction"] = string(axis[:AXIS][2])

        # Get unit from the CS node, then try the AXIS node if not found
        unit = wktdict2jsondict_get_unit(wkt[geo_sub_type])
        if isnothing(unit)
          unit = wktdict2jsondict_get_unit(axis[:AXIS])
        end
        if isnothing(unit)
          # TODO: is unit required? enumrate possible types of units
          error("Could not find a UNIT node")
        end
        axis_dict["unit"] = unit[1]
        push!(cs_dict["axis"], axis_dict)
    end

    return cs_dict
end

# DESIGN: for now, print @error and return nothing, so we get both...
## DESIGN, maybe its better to always return nothing, and be exhastive at call site, because often things are optional and we don't want to throw from child-functions
#######

# takes a parent node and returns the ANGLEUNIT or LENGTHUNIT child node
function wktdict2jsondict_get_unit(axis)
  # One-and-only-one
  unit_entry = get_item_with_key(:ANGLEUNIT, axis)
  !isnothing(unit_entry) && return unit_entry[1][:ANGLEUNIT]
  unit_entry = get_item_with_key(:LENGTHUNIT, axis)
  !isnothing(unit_entry) && return unit_entry[1][:LENGTHUNIT]
  unit_entry = get_item_with_key(:SCALEUNIT, axis)
  !isnothing(unit_entry) && return unit_entry[1][:SCALEUNIT]
  return nothing
end

function wktdict2jsondict_general_datum(datum::Dict)#::(String, Dict)
  name = ""
  jsondict = Dict{String,Any}()
  
  dynamic = get_item_with_key(:DYNAMIC, datum[get_main_key(datum)])
  datum = get_item_with_keys([:ENSEMBLE, :DATUM], datum[get_main_key(datum)])[1]
  
  if get_main_key(datum) == :ENSEMBLE
    name = "datum_ensemble"
    jsondict = wktdict2jsondict_long_datum(datum)
  elseif get_main_key(datum) == :DATUM
    name = "datum"
    jsondict = wktdict2jsondict_short_datum(datum)

    # this is here as not to ruin the encapsulation of _short_datum
    if !isnothing(dynamic)
      jsondict["frame_reference_epoch"] = dynamic[1][:DYNAMIC][1][:FRAMEEPOCH][1]
      jsondict["type"] = "DynamicGeodeticReferenceFrame"
    else
      jsondict["type"] = "GeodeticReferenceFrame"
    end
  # was indeed needed for few niche entries, should be exhastive
  #... its ENSEMBLE location, not [1] as expected
  else
    error("Didn't find a datum node that is either ENSEMBLE or DATUM.")
  end

  return (name, jsondict)
end

function wktdict2jsondict_short_datum(wkt::Dict)
  @assert wkt |> keys |> collect == [:DATUM]
  # "required":["name", "ellipsoid"], optionally have "type", "anchor_epoch", "prime_meridian" 
  
  jsondict = Dict{String, Any}()
  jsondict["name"] = wkt[:DATUM][1]

  ell_elems = get_items_with_key(:ELLIPSOID, wkt[:DATUM])
  jsondict["ellipsoid"] = wktdict2jsondict_ellipsoid(ell_elems[1])["ellipsoid"] 
  
  # Optional, not always present
  anchor_epoch = get_items_with_key(:ANCHOREPOCH, wkt[:DATUM])
  if !isempty(anchor_epoch) 
    ## TODO: get_items_with_key single usage if we ever refactor
    jsondict["anchor_epoch"] = anchor_epoch[1][:ANCHOREPOCH][1]
  end
  return jsondict
end

function wktdict2jsondict_long_datum(wkt::Dict)
  # "required" : [ "name", "members", "accuracy" ],
  
  @assert wkt |> keys |> collect == [:ENSEMBLE]
  jsondict = Dict{String, Any}()
  jsondict["name"] = wkt[:ENSEMBLE][1]
  
  jsondict["members"] = []
  members = get_items_with_key(:MEMBER, wkt[:ENSEMBLE])
  for m in members
    mdict = Dict{String, Any}()
    mdict["name"] = m[:MEMBER][1]
    mdict["id"] = wktdict2jsondict_id(m[:MEMBER][2])
    push!(jsondict["members"], mdict)
  end
  
  ## TODO: potentially another version of get_items_with_key to avoid redundancy 
  acc_elems = get_items_with_key(:ENSEMBLEACCURACY, wkt[:ENSEMBLE])[1]
  jsondict["accuracy"] = string(float(acc_elems[:ENSEMBLEACCURACY][1]))
  
  ell_elems = get_items_with_key(:ELLIPSOID, wkt[:ENSEMBLE])
  if !isempty(ell_elems) 
    jsondict["ellipsoid"] = wktdict2jsondict_ellipsoid(ell_elems[1])["ellipsoid"]
  end
  jsondict["id"] = wktdict2jsondict_id(wkt[:ENSEMBLE][end])
  
  return jsondict
end

function wktdict2jsondict_ellipsoid(wkt::Dict)
  @assert wkt |> keys |> collect == [:ELLIPSOID]
  jsondict = Dict()
  jsondict["ellipsoid"] = Dict()
  jsondict["ellipsoid"]["name"] = wkt[:ELLIPSOID][1]
  jsondict["ellipsoid"]["semi_major_axis"] = wkt[:ELLIPSOID][2]
  jsondict["ellipsoid"]["inverse_flattening"] = wkt[:ELLIPSOID][3]
  return jsondict
end

function wktdict2jsondict_id(id_dict::Dict)::Dict
  @assert id_dict  |> keys |> collect == [:ID]
  jsondict = Dict{String, Any}() # "list" of key value pairs
  jsondict["authority"] = id_dict[:ID][1]
  jsondict["code"] = id_dict[:ID][2]
  return jsondict
end


###
# From WKT2 string to Julia Dict conversion
###

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
