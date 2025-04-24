get_main_key(d) = nothing
function get_main_key(d::Dict)
  @assert d |> keys |> length == 1
  return d |> keys |> first
end

# From a Vector{Dict}, get Dict items that all has a particular key  
function get_items_with_key(key::Symbol, list::Vector)
  filter(x->get_main_key(x)==key, list)
end

wktdict_crs_type(wkt::Dict) = get_main_key(wkt)

###
# Construct projjson compliant Dict from From WKT2 Dict 
###

function wktdict2jsondict(wkt::Dict)
  type = get_main_key(wkt)
  if type == :GEOGCRS
    return wktdict2jsondict_geog(wkt)
  elseif type == :GEODCRS
    error("Unimplemented CRS type: $type")
  elseif type == :PROJCRS
    error("Unimplemented CRS type: $type")
  else
    error("Unimplemented CRS type: $type")
  end
end

function wktdict2jsondict_geog(wkt::Dict)
  @assert wkt |> keys |> collect == [:GEOGCRS]
  jsondict = Dict{String, Any}()
  jsondict["type"] = "GeographicCRS"
  jsondict["name"] = wkt[:GEOGCRS][1]
  
  # design: bit of redundancy between the [2] and [:ENSEMBLE] inside the function
  jsondict["datum_ensemble"] = wktdict2jsondict_ensemble(wkt[:GEOGCRS][2])
  
  # decision, either pass specifically the CS and AXIS arr elements or all the dict. Caveate, for later projected there is cs nested inside
  # jsondict["coordinate_system"] = wktdict2jsondict_cs(wkt)
    
  jsondict["id"] = wktdict2jsondict_id(wkt[:GEOGCRS][end])
  # return Dict(:root => jsondict)  
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

function wktdict2jsondict_ensemble(wkt::Dict)
  @assert wkt |> keys |> collect == [:ENSEMBLE]
  jsondict = Dict{String, Any}()
  jsondict["name"] = wkt[:ENSEMBLE][1]
  
  members = get_items_with_key(:MEMBER, wkt[:ENSEMBLE])
  jsondict["members"] = []
  for m in members
    mdict = Dict{String, Any}()
    mdict["name"] = m[:MEMBER][1]
    mdict["id"] = wktdict2jsondict_id(m[:MEMBER][2])
    push!(jsondict["members"], mdict)
  end
  
  jsondict["id"] = wktdict2jsondict_id(wkt[:ENSEMBLE][end])
  
  return jsondict
end


###
# From WKT2 string to Julia Dict conversion 
###

function epsg2wktdict(epsg::Int)::Dict
  str = CoordRefSystems.wkt2(EPSG{epsg})
  expr = Meta.parse(str)
  dict = expr2dict(expr)
end
epsg2wktdict(::Type{EPSG{I}}) where I = epsg2wktdict(I)

function expr2dict(e::Expr)
  p = Dict(:root => [])
  process_expr(e, p)
  return p[:root][1]
end

function process_expr(elem, dict::Dict)
  k = dict |> keys |> collect |> first
  if elem isa Expr
    expr_name = elem.args[1]
    child_dict = Dict(expr_name => [])
    push!(dict[k], child_dict)
    # dict[k] = child_dict
    for child_elem in elem.args[2:end]
      process_expr(child_elem, child_dict)
    end
  elseif elem isa Union{String, Number, Symbol}
    push!(dict[k], elem)
  else
    @error "Unhandled case"
  end
  return dict
end
