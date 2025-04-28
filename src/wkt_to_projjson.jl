# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

module SafeIterate
export safe_iterate
function safe_iterate(iterator, optional_state::Union{Tuple{},Tuple{Any}})
  if optional_state === ()
    iterate(iterator)
  else
    iterate(iterator, only(optional_state))
  end
end
end

module ParseTrees
export ParseTreeNodeIdentity,
  ParseTreeRootless,
  ParseTreeRooted,
  parse_node_symbol_kind,
  parse_node_is_terminal,
  parse_node_is_childless,
  parse_node_to_token,
  parse_node_children,
  terminal_symbol_given_token!,
  unparse,
  parse_strong_ll_1,
  parse_strong_ll_1_with_appended_eof,
  parse_tree_validate
mutable struct ParseTreeNodeIdentity end
const empty_vector = ParseTreeNodeIdentity[]  # used for allocation-free tree traversal and other optimizations
struct ParseTreeRootless{GrammarSymbolKind,Token}
  node_to_grammar_symbol_kind::Dict{ParseTreeNodeIdentity,GrammarSymbolKind}
  nonterminal_node_to_children::Dict{ParseTreeNodeIdentity,Vector{ParseTreeNodeIdentity}}
  terminal_node_to_token::Dict{ParseTreeNodeIdentity,Token}
  function ParseTreeRootless{GrammarSymbolKind,Token}() where {GrammarSymbolKind,Token}
    kinds = Dict{ParseTreeNodeIdentity,GrammarSymbolKind}()
    rules = Dict{ParseTreeNodeIdentity,Vector{ParseTreeNodeIdentity}}()
    tokens = Dict{ParseTreeNodeIdentity,Token}()
    new{GrammarSymbolKind,Token}(kinds, rules, tokens)
  end
end
struct ParseTreeRooted{GrammarSymbolKind,Token}
  root::ParseTreeNodeIdentity
  graph::ParseTreeRootless{GrammarSymbolKind,Token}
  function ParseTreeRooted(
    root::ParseTreeNodeIdentity,
    graph::ParseTreeRootless{GrammarSymbolKind,Token}
  ) where {GrammarSymbolKind,Token}
    new{GrammarSymbolKind,Token}(root, graph)
  end
end
"""
    parse_node_symbol_kind(::ParseTreeRooted)

Returns the kind of the root node as a grammar symbol.
"""
function parse_node_symbol_kind(tree::ParseTreeRooted)
  tree.graph.node_to_grammar_symbol_kind[tree.root]
end
"""
    parse_node_is_terminal(::ParseTreeRooted)::Bool

Predicate, tells if the (root) node of the parse tree is a terminal symbol.
"""
function parse_node_is_terminal(tree::ParseTreeRooted)
  yes = haskey(tree.graph.terminal_node_to_token, tree.root)::Bool
  no = haskey(tree.graph.nonterminal_node_to_children, tree.root)::Bool
  if yes == no
    throw(ArgumentError("unexpected, debug"))
  end
  yes
end
"""
    parse_node_is_childless(::ParseTreeRooted)::Bool

Predicate, tells if the (root) node of the parse tree is a leaf node/childless.
"""
function parse_node_is_childless(tree::ParseTreeRooted)
  parse_node_is_terminal(tree) || isempty(tree.graph.nonterminal_node_to_children[tree.root])
end
"""
    parse_node_to_token(::ParseTreeRooted)

Returns the token of a terminal symbol.
"""
function parse_node_to_token(tree::ParseTreeRooted)
  if !parse_node_is_terminal(tree)
    throw(ArgumentError("root node is not a terminal"))
  end
  tree.graph.terminal_node_to_token[tree.root]
end
"""
    parse_node_children(::ParseTreeRooted)

Returns an iterator of `ParseTreeRooted` elements.
"""
function parse_node_children(tree::ParseTreeRooted)
  graph = tree.graph
  grammar_rules = graph.nonterminal_node_to_children
  function f(root::ParseTreeNodeIdentity)
    ParseTreeRooted(root, graph)
  end
  children = if parse_node_is_childless(tree)
    if !isempty(empty_vector)
      throw(ArgumentError("`empty_vector` not empty"))
    end
    empty_vector
  else
    grammar_rules[tree.root]
  end
  Iterators.map(f, children)
end
function terminal_symbol_given_token!(
  kinds::Dict{ParseTreeNodeIdentity},
  tokens::Dict{ParseTreeNodeIdentity,Token},
  token::Token
) where {Token}
  terminal_symbol = ParseTreeNodeIdentity()
  kinds[terminal_symbol] = token.kind
  tokens[terminal_symbol] = token
  terminal_symbol
end
"""
    unparse(print_token, tree::ParseTreeRooted)::Nothing

Unparse `tree`, calling `print_token(token)` for each token.
"""
function unparse(print_token::PrTok, tree::ParseTreeRooted) where {PrTok}
  if parse_node_is_terminal(tree)
    print_token(parse_node_to_token(tree))
  else
    foreach(Base.Fix1(unparse, print_token), parse_node_children(tree))
  end
  nothing
end
"""
    parse_strong_ll_1(::Any, ::Any, ::Any, ::Any, ::Any)::ParseTreeRooted
"""
function parse_strong_ll_1(
  ::Type{Token},
  parsing_table::AbstractDict{Tuple{Vararg{GrammarSymbolKind,2}},<:AbstractVector{GrammarSymbolKind}},
  start_symbol_kind::GrammarSymbolKind,
  tokens
) where {GrammarSymbolKind,Token}
  graph = ParseTreeRootless{GrammarSymbolKind,Token}()
  start_symbol = ParseTreeNodeIdentity()
  parse_tree_kinds = graph.node_to_grammar_symbol_kind
  parse_tree_tokens = graph.terminal_node_to_token
  parse_tree_grammar_rules = graph.nonterminal_node_to_children
  stack = [start_symbol]
  parse_tree_kinds[start_symbol] = start_symbol_kind
  (lookahead, iter_state) = iterate(tokens)
  while !isempty(stack)
    stack_top_symbol = pop!(stack)
    stack_top_symbol_kind = parse_tree_kinds[stack_top_symbol]
    lookahead_kind = lookahead.kind
    if lookahead_kind == stack_top_symbol_kind
      # invariant: `!haskey(parse_tree_tokens, stack_top_symbol)`
      if haskey(parse_tree_tokens, stack_top_symbol)
        error("unexpected: debug")
      end
      parse_tree_tokens[stack_top_symbol] = lookahead
      (lookahead, iter_state) = iterate(tokens, iter_state)
    else
      let parsing_table_key = (stack_top_symbol_kind, lookahead_kind)
        if !haskey(parsing_table, parsing_table_key)
          throw(ArgumentError("parsing error"))
        end
        rule = parsing_table[parsing_table_key]
        for nt in Iterators.reverse(rule)
          id = ParseTreeNodeIdentity()
          parse_tree_kinds[id] = nt
          push!(stack, id)
        end
        # invariant: `!haskey(parse_tree_grammar_rules, stack_top_symbol)`
        if haskey(parse_tree_grammar_rules, stack_top_symbol)
          error("unexpected: debug")
        end
        vec_rever = Iterators.reverse(@view stack[(end - length(rule) + 1):end])
        vec = collect(ParseTreeNodeIdentity, vec_rever)
        parse_tree_grammar_rules[stack_top_symbol] = vec
      end
    end
  end
  # TODO: add another error check here?
  parse_tree_validate(ParseTreeRooted(start_symbol, graph))
end
function parse_strong_ll_1_with_appended_eof(eof_token, parsing_table, start_symbol_kind, tokens)
  tokens_with_appended_eof = Iterators.flatten((tokens, (eof_token,)))
  parse_strong_ll_1(typeof(eof_token), parsing_table, start_symbol_kind, tokens_with_appended_eof)
end
function parse_tree_validate(tree::ParseTreeRootless)
  kinds = tree.node_to_grammar_symbol_kind
  grammar_rules = tree.nonterminal_node_to_children
  tokens = tree.terminal_node_to_token
  symbols = keys(kinds)
  terminal_symbols = keys(tokens)
  nonterminal_symbols = keys(grammar_rules)
  if !isdisjoint(terminal_symbols, nonterminal_symbols)
    throw(ArgumentError("the set of terminal symbols and the set of nonterminal symbols should be disjoint"))
  end
  if symbols != union(terminal_symbols, nonterminal_symbols)
    throw(
      ArgumentError(
        "the union of the set of terminal symbols and the set of nonterminal symbols should be equal to the set of all symbols"
      )
    )
  end
  # TODO: check that the symbol graph is weakly connected
  # TODO: check that the symbol graph is a tree, or at least acyclic
  tree
end
function parse_tree_validate(tree::ParseTreeRooted)
  parse_tree_validate(tree.graph)
  # TODO: check that each symbol graph node (symbol) is reachable from the root
  tree
end
end

module KindConstruction
export construct_kind
function construct_kind(
  new::New,
  kind_to_name::AbstractDict{<:Any,<:AbstractString},
  name_to_kind::AbstractDict{<:AbstractString},
  name::AbstractString
) where {New}
  if isempty(name)
    throw(ArgumentError("name is empty"))
  end
  if haskey(name_to_kind, name)
    throw(ArgumentError("name already exists"))
  end
  kind = new()
  kind_to_name[kind] = name
  name_to_kind[name] = kind
  kind
end
end

module QualifiedPrinting
export print_qualified
function print_qualified(io::IO, s::AbstractString, m::Module)
  show(io, m)
  print(io, '.')
  print(io, s)
end
end

module JSONGrammarSymbolKinds
export JSONGrammarSymbolKind
using ..KindConstruction, ..QualifiedPrinting
mutable struct JSONGrammarSymbolKind
  const global kind_to_name = Dict{JSONGrammarSymbolKind,String}()
  const global name_to_kind = Dict{String,JSONGrammarSymbolKind}()
  function JSONGrammarSymbolKind(name::String)
    construct_kind((() -> new()), kind_to_name, name_to_kind, name)
  end
end
function Base.show(io::IO, kind::JSONGrammarSymbolKind)
  print_qualified(io, kind_to_name[kind], @__MODULE__)
end
const number = JSONGrammarSymbolKind("number")
const keyword = JSONGrammarSymbolKind("keyword")  # either `null`, `false` or `true`
const quoted_text = JSONGrammarSymbolKind("quoted_text")  # "string"
const dictionary_delimiter_left = JSONGrammarSymbolKind("dictionary_delimiter_left")
const dictionary_delimiter_right = JSONGrammarSymbolKind("dictionary_delimiter_right")
const list_delimiter_left = JSONGrammarSymbolKind("list_delimiter_left")
const list_delimiter_right = JSONGrammarSymbolKind("list_delimiter_right")
const list_element_separator = JSONGrammarSymbolKind("list_element_separator")
const pair_element_separator = JSONGrammarSymbolKind("pair_element_separator")
const pair = JSONGrammarSymbolKind("pair")  # "member"
const incomplete_dictionary = JSONGrammarSymbolKind("incomplete_dictionary")
const optional_incomplete_dictionary = JSONGrammarSymbolKind("optional_incomplete_dictionary")
const nonempty_dictionary = JSONGrammarSymbolKind("nonempty_dictionary")
const dictionary = JSONGrammarSymbolKind("dictionary")  # "members"
const delimited_dictionary = JSONGrammarSymbolKind("delimited_dictionary")  # "object"
const incomplete_list = JSONGrammarSymbolKind("incomplete_list")
const optional_incomplete_list = JSONGrammarSymbolKind("optional_incomplete_list")
const nonempty_list = JSONGrammarSymbolKind("nonempty_list")
const list = JSONGrammarSymbolKind("list")  # "elements"
const delimited_list = JSONGrammarSymbolKind("delimited_list")  # "array"
const value = JSONGrammarSymbolKind("value")
end

module JSONTokens
export JSONToken
using ..JSONGrammarSymbolKinds
struct JSONToken
  kind::JSONGrammarSymbolKind
  payload::String
  global function new_number(payload::String)
    new(JSONGrammarSymbolKinds.number, payload)
  end
  global function new_keyword(payload::String)
    new(JSONGrammarSymbolKinds.keyword, payload)
  end
  global function new_quoted_text(payload::String)
    new(JSONGrammarSymbolKinds.quoted_text, payload)
  end
  global function new_dictionary_delimiter_left()
    new(JSONGrammarSymbolKinds.dictionary_delimiter_left)
  end
  global function new_dictionary_delimiter_right()
    new(JSONGrammarSymbolKinds.dictionary_delimiter_right)
  end
  global function new_list_delimiter_left()
    new(JSONGrammarSymbolKinds.list_delimiter_left)
  end
  global function new_list_delimiter_right()
    new(JSONGrammarSymbolKinds.list_delimiter_right)
  end
  global function new_list_element_separator()
    new(JSONGrammarSymbolKinds.list_element_separator)
  end
  global function new_pair_element_separator()
    new(JSONGrammarSymbolKinds.pair_element_separator)
  end
end
end

module WKTGrammarSymbolKinds
export WKTGrammarSymbolKind
using ..KindConstruction, ..QualifiedPrinting
mutable struct WKTGrammarSymbolKind
  const global kind_to_name = Dict{WKTGrammarSymbolKind,String}()
  const global name_to_kind = Dict{String,WKTGrammarSymbolKind}()
  function WKTGrammarSymbolKind(name::String)
    construct_kind((() -> new()), kind_to_name, name_to_kind, name)
  end
end
function Base.show(io::IO, kind::WKTGrammarSymbolKind)
  print_qualified(io, kind_to_name[kind], @__MODULE__)
end
const eof = WKTGrammarSymbolKind("eof")
const number = WKTGrammarSymbolKind("number")
const keyword = WKTGrammarSymbolKind("keyword")
const quoted_text = WKTGrammarSymbolKind("quoted_text")
const list_delimiter_left = WKTGrammarSymbolKind("list_delimiter_left")
const list_delimiter_right = WKTGrammarSymbolKind("list_delimiter_right")
const list_element_separator = WKTGrammarSymbolKind("list_element_separator")
const incomplete_list = WKTGrammarSymbolKind("incomplete_list")
const optional_incomplete_list = WKTGrammarSymbolKind("optional_incomplete_list")
const list_element = WKTGrammarSymbolKind("list_element")
const nonempty_list = WKTGrammarSymbolKind("nonempty_list")
const delimited_list = WKTGrammarSymbolKind("delimited_list")
const optional_delimited_list = WKTGrammarSymbolKind("optional_delimited_list")
const keyword_with_optional_delimited_list = WKTGrammarSymbolKind("keyword_with_optional_delimited_list")
end

module WKTTokens
export WKTToken
using ..WKTGrammarSymbolKinds
struct WKTToken
  kind::WKTGrammarSymbolKind
  payload::String
  global function new_eof()
    new(WKTGrammarSymbolKinds.eof)
  end
  global function new_number(payload::String)
    new(WKTGrammarSymbolKinds.number, payload)
  end
  global function new_keyword(payload::String)
    new(WKTGrammarSymbolKinds.keyword, lowercase(payload))
  end
  global function new_quoted_text(payload::String)
    new(WKTGrammarSymbolKinds.quoted_text, payload)
  end
  global function new_list_delimiter_left()
    new(WKTGrammarSymbolKinds.list_delimiter_left)
  end
  global function new_list_delimiter_right()
    new(WKTGrammarSymbolKinds.list_delimiter_right)
  end
  global function new_list_element_separator()
    new(WKTGrammarSymbolKinds.list_element_separator)
  end
end
end

module PROJJSONTypeKinds
export PROJJSONTypeKind
using ..KindConstruction, ..QualifiedPrinting
mutable struct PROJJSONTypeKind
  const global kind_to_name = Dict{PROJJSONTypeKind,String}()
  const global name_to_kind = Dict{String,PROJJSONTypeKind}()
  function PROJJSONTypeKind(name::String)
    construct_kind((() -> new()), kind_to_name, name_to_kind, name)
  end
end
function Base.show(io::IO, kind::PROJJSONTypeKind)
  print_qualified(io, kind_to_name[kind], @__MODULE__)
end
function Base.print(io::IO, kind::PROJJSONTypeKind)
  print(io, kind_to_name[kind])
end
const Ellipsoid = PROJJSONTypeKind("Ellipsoid")  # added manually because the script doesn't support some Schema features
# generated from the PROJJSON JSON schema v0.7
const AbridgedTransformation = PROJJSONTypeKind("AbridgedTransformation")
const Axis = PROJJSONTypeKind("Axis")
const BoundCRS = PROJJSONTypeKind("BoundCRS")
const CompoundCRS = PROJJSONTypeKind("CompoundCRS")
const ConcatenatedOperation = PROJJSONTypeKind("ConcatenatedOperation")
const Conversion = PROJJSONTypeKind("Conversion")
const CoordinateMetadata = PROJJSONTypeKind("CoordinateMetadata")
const CoordinateSystem = PROJJSONTypeKind("CoordinateSystem")
const DatumEnsemble = PROJJSONTypeKind("DatumEnsemble")
const DerivedEngineeringCRS = PROJJSONTypeKind("DerivedEngineeringCRS")
const DerivedGeodeticCRS = PROJJSONTypeKind("DerivedGeodeticCRS")
const DerivedGeographicCRS = PROJJSONTypeKind("DerivedGeographicCRS")
const DerivedParametricCRS = PROJJSONTypeKind("DerivedParametricCRS")
const DerivedProjectedCRS = PROJJSONTypeKind("DerivedProjectedCRS")
const DerivedTemporalCRS = PROJJSONTypeKind("DerivedTemporalCRS")
const DerivedVerticalCRS = PROJJSONTypeKind("DerivedVerticalCRS")
const DynamicGeodeticReferenceFrame = PROJJSONTypeKind("DynamicGeodeticReferenceFrame")
const DynamicVerticalReferenceFrame = PROJJSONTypeKind("DynamicVerticalReferenceFrame")
const EngineeringCRS = PROJJSONTypeKind("EngineeringCRS")
const EngineeringDatum = PROJJSONTypeKind("EngineeringDatum")
const GeodeticCRS = PROJJSONTypeKind("GeodeticCRS")
const GeodeticReferenceFrame = PROJJSONTypeKind("GeodeticReferenceFrame")
const GeographicCRS = PROJJSONTypeKind("GeographicCRS")
const Meridian = PROJJSONTypeKind("Meridian")
const OperationMethod = PROJJSONTypeKind("OperationMethod")
const ParameterValue = PROJJSONTypeKind("ParameterValue")
const ParametricCRS = PROJJSONTypeKind("ParametricCRS")
const ParametricDatum = PROJJSONTypeKind("ParametricDatum")
const PointMotionOperation = PROJJSONTypeKind("PointMotionOperation")
const PrimeMeridian = PROJJSONTypeKind("PrimeMeridian")
const ProjectedCRS = PROJJSONTypeKind("ProjectedCRS")
const TemporalCRS = PROJJSONTypeKind("TemporalCRS")
const TemporalDatum = PROJJSONTypeKind("TemporalDatum")
const Transformation = PROJJSONTypeKind("Transformation")
const VerticalCRS = PROJJSONTypeKind("VerticalCRS")
const VerticalReferenceFrame = PROJJSONTypeKind("VerticalReferenceFrame")
end

module WKTKeywordKinds
export WKTKeywordKind
using ..QualifiedPrinting
mutable struct WKTKeywordKind
  const global kind_to_names = Dict{WKTKeywordKind,Set{String}}()
  const global name_to_kind = Dict{String,WKTKeywordKind}()
  const global kind_to_internal_name = Dict{WKTKeywordKind,String}()
  const global internal_name_to_kind = Dict{String,WKTKeywordKind}()
  function WKTKeywordKind(internal_name::String, names_vec::Vector{String})
    if !allunique(names_vec)
      throw(ArgumentError("duplicate names detected"))
    end
    names = Set(names_vec)
    if isempty(names)
      throw(ArgumentError("names is empty"))
    end
    if any(isempty, names) || isempty(internal_name)
      throw(ArgumentError("a name is empty"))
    end
    if any(Base.Fix1(haskey, name_to_kind), names) || haskey(internal_name_to_kind, internal_name)
      throw(ArgumentError("a name already exists"))
    end
    if any(Base.Fix1(any, !islowercase), names)
      throw(ArgumentError("WKT keyword not normalized to lowercase"))
    end
    kind = new()
    kind_to_names[kind] = names
    function f(name::String)
      name_to_kind[name] = kind
    end
    foreach(f, names)
    kind_to_internal_name[kind] = internal_name
    internal_name_to_kind[internal_name] = kind
    kind
  end
end
function Base.show(io::IO, kind::WKTKeywordKind)
  print_qualified(io, kind_to_internal_name[kind], @__MODULE__)
end
# * Source:
#     * Open Geospatial Consortium standard: "Geographic information": "Well-known text representation of coordinate reference systems": "6.6 Reserved keywords"
#         * version: 2.1.11
#         * reference number: 18-010r11
# * Note: the commented-out entries are merged into another, almost-equivalent, keyword kind. E.g., `derivingconversion` into `conversion`.
const abridged_transformation = WKTKeywordKind("abridged_transformation", ["abridgedtransformation"])
const datum_anchor = WKTKeywordKind("datum_anchor", ["anchor"])
const datum_anchor_epoch = WKTKeywordKind("datum_anchor_epoch", ["anchorepoch"])  # not in PROJJSON, see Markdown notes and https://github.com/OSGeo/PROJ/issues/4469
const angle_unit = WKTKeywordKind("angle_unit", ["angleunit"])
const area_description = WKTKeywordKind("area_description", ["area"])
const axis = WKTKeywordKind("axis", ["axis"])
const axis_maximum_value = WKTKeywordKind("axis_maximum_value", ["axismaxvalue"])
const axim_minimum_value = WKTKeywordKind("axim_minimum_value", ["axisminvalue"])
# const base_engineering_crs = WKTKeywordKind("base_engineering_crs", ["baseengcrs"])
# const base_geodetic_crs = WKTKeywordKind("base_geodetic_crs", ["basegeodcrs"])
# const base_geographic_crs = WKTKeywordKind("base_geographic_crs", ["basegeogcrs"])
# const base_parametric_crs = WKTKeywordKind("base_parametric_crs", ["baseparamcrs"])
# const base_projected_crs = WKTKeywordKind("base_projected_crs", ["baseprojcrs"])
# const base_temporal_crs = WKTKeywordKind("base_temporal_crs", ["basetimecrs"])
# const base_vertical_crs = WKTKeywordKind("base_vertical_crs", ["basevertcrs"])
const geographic_bounding_box = WKTKeywordKind("geographic_bounding_box", ["bbox"])
const bearing = WKTKeywordKind("bearing", ["bearing"])
const bound_crs = WKTKeywordKind("bound_crs", ["boundcrs"])
const calendar = WKTKeywordKind("calendar", ["calendar"])
const citation = WKTKeywordKind("citation", ["citation"])
const compound_crs = WKTKeywordKind("compound_crs", ["compoundcrs"])
const concatenated_operation = WKTKeywordKind("concatenated_operation", ["concatenatedoperation"])
const concatenated_operation_step = WKTKeywordKind("concatenated_operation_step", ["step"])
const map_projection = WKTKeywordKind("map_projection", ["conversion", "derivingconversion"])
const coordinate_epoch = WKTKeywordKind("coordinate_epoch", ["coordepoch", "epoch"])
const coordinate_metadata = WKTKeywordKind("coordinate_metadata", ["coordinatemetadata"])
const coordinate_operation = WKTKeywordKind("coordinate_operation", ["coordinateoperation"])
const coordinate_system = WKTKeywordKind("coordinate_system", ["cs"])
const geodetic_reference_frame = WKTKeywordKind("geodetic_reference_frame", ["datum", "geodeticdatum", "trf"])
const defining_transformation = WKTKeywordKind("defining_transformation", ["definingtransformation"])  # not in PROJJSON, see Markdown notes and https://github.com/OSGeo/PROJ/issues/4469
const derived_projected_crs = WKTKeywordKind("derived_projected_crs", ["derivedprojcrs", "derivedprojected"])  # TODO: `derivedprojected` is not in the OGC spec, but it appears in the EPSG database! Discuss? Report to epsg.org?
# const deriving_conversion = WKTKeywordKind("deriving_conversion", ["derivingconversion"])
const dynamic_crs = WKTKeywordKind("dynamic_crs", ["dynamic"])
const engineering_datum = WKTKeywordKind("engineering_datum", ["edatum", "engineeringdatum"])
const ellipsoid = WKTKeywordKind("ellipsoid", ["ellipsoid", "spheroid"])
const engineering_crs = WKTKeywordKind("engineering_crs", ["engcrs", "engineeringcrs", "baseengcrs"])
const datum_ensemble = WKTKeywordKind("datum_ensemble", ["ensemble"])
const datum_ensemble_accuracy = WKTKeywordKind("datum_ensemble_accuracy", ["ensembleaccuracy"])
const frame_reference_epoch = WKTKeywordKind("frame_reference_epoch", ["frameepoch"])
const geodetic_crs = WKTKeywordKind("geodetic_crs", ["geodcrs", "geodeticcrs", "basegeodcrs"])
const geographic_crs = WKTKeywordKind("geographic_crs", ["geogcrs", "geographiccrs", "basegeogcrs"])
const geoid_model_id = WKTKeywordKind("geoid_model_id", ["geoidmodel"])
const identifier = WKTKeywordKind("identifier", ["id"])
const interpolation_crs = WKTKeywordKind("interpolation_crs", ["interpolationcrs"])
const length_unit = WKTKeywordKind("length_unit", ["lengthunit"])
const datum_ensemble_member = WKTKeywordKind("datum_ensemble_member", ["member"])
const meridian = WKTKeywordKind("meridian", ["meridian"])
const method = WKTKeywordKind("method", ["method"])  # may mean the same as `map_projection_method`, depending on context
const deformation_model_id = WKTKeywordKind("deformation_model_id", ["model", "velocitygrid"])
const operation_accuracy = WKTKeywordKind("operation_accuracy", ["operationaccuracy"])
const axis_order = WKTKeywordKind("axis_order", ["order"])
const parameter = WKTKeywordKind("parameter", ["parameter"])
const parameter_file = WKTKeywordKind("parameter_file", ["parameterfile"])
const parametric_crs = WKTKeywordKind("parametric_crs", ["parametriccrs", "baseparamcrs"])
const parametric_datum = WKTKeywordKind("parametric_datum", ["parametricdatum", "pdatum"])
const parametric_unit = WKTKeywordKind("parametric_unit", ["parametricunit"])
const point_motion_operation = WKTKeywordKind("point_motion_operation", ["pointmotionoperation"])
const prime_meridian = WKTKeywordKind("prime_meridian", ["primemeridian", "primem"])
const projected_crs = WKTKeywordKind("projected_crs", ["projectedcrs", "projcrs", "baseprojcrs"])
const map_projection_method = WKTKeywordKind("map_projection_method", ["projection"])
const remark = WKTKeywordKind("remark", ["remark"])
const scale_unit = WKTKeywordKind("scale_unit", ["scaleunit"])
const scope = WKTKeywordKind("scope", ["scope"])
const source_crs = WKTKeywordKind("source_crs", ["sourcecrs"])
const target_crs = WKTKeywordKind("target_crs", ["targetcrs"])
const temporal_datum = WKTKeywordKind("temporal_datum", ["timedatum", "tdatum"])
const temporal_quantity = WKTKeywordKind("temporal_quantity", ["temporalquantity", "timeunit"])
const temporal_extent = WKTKeywordKind("temporal_extent", ["timeextent"])
const temporal_origin = WKTKeywordKind("temporal_origin", ["timeorigin"])
const time_crs = WKTKeywordKind("time_crs", ["timecrs", "basetimecrs"])
const triaxial_ellipsoid = WKTKeywordKind("triaxial_ellipsoid", ["triaxial"])
const unit = WKTKeywordKind("unit", ["unit"])
const uri = WKTKeywordKind("uri", ["uri"])
const usage = WKTKeywordKind("usage", ["usage"])
const vertical_reference_frame = WKTKeywordKind("vertical_reference_frame", ["verticaldatum", "vdatum", "vrf"])
const operation_version = WKTKeywordKind("operation_version", ["version"])
const vertical_crs = WKTKeywordKind("vertical_crs", ["verticalcrs", "vertcrs", "basevertcrs"])
const vertical_extent = WKTKeywordKind("vertical_extent", ["verticalextent"])
end

module WKTParseTreeRootedListIterators
export WKTParseTreeRootedListIterator
using ..ParseTrees, ..WKTGrammarSymbolKinds, ..WKTTokens
struct WKTParseTreeRootedListIterator <: AbstractVector{ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}}
  tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
  function WKTParseTreeRootedListIterator(tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
    new(check_nonempty_list(tree))
  end
end
function check_nonempty_list(tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  if parse_node_is_childless(tree)
    throw(ArgumentError("leaf node"))
  end
  if parse_node_symbol_kind(tree)::WKTGrammarSymbolKind != WKTGrammarSymbolKinds.nonempty_list
    throw(ArgumentError("expected nonempty_list, got other nonterminal"))
  end
  tree
end
function nonempty_list_first_element(tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  tree = check_nonempty_list(tree)
  (list_element, _) = parse_node_children(tree)
  only(parse_node_children(list_element))::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
end
function nonempty_list_has_just_one_element(tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  tree = check_nonempty_list(tree)
  (_, optional_incomplete_list) = parse_node_children(tree)
  parse_node_is_childless(optional_incomplete_list)
end
function nonempty_list_tail(tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  if nonempty_list_has_just_one_element(tree)
    throw(ArgumentError("the list has just one element, no tail"))
  end
  (_, optional_incomplete_list) = parse_node_children(tree)
  incomplete_list = only(parse_node_children(optional_incomplete_list))
  (_, ret) = parse_node_children(incomplete_list)
  check_nonempty_list(ret)
end
function nonempty_list_length(tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  tree = check_nonempty_list(tree)
  ret = 1
  while !nonempty_list_has_just_one_element(tree)
    ret += 1
    tree = nonempty_list_tail(tree)
  end
  ret
end
function Base.length(list_iterator::WKTParseTreeRootedListIterator)
  nonempty_list_length(list_iterator.tree)
end
function Base.size(list_iterator::WKTParseTreeRootedListIterator)
  len = length(list_iterator)
  (len,)
end
function Base.IndexStyle(::Type{WKTParseTreeRootedListIterator})
  IndexLinear()
end
function Base.getindex(list_iterator::WKTParseTreeRootedListIterator, i::Int)
  checkbounds(list_iterator, i)
  tree = list_iterator.tree
  while !isone(i)
    i -= 1
    tree = nonempty_list_tail(tree)
  end
  nonempty_list_first_element(tree)
end
# TODO: implement `Base.iterate` as a performance optimization
end

module WKTParseTreeUtil
export get_wkt_keyword,
  get_wkt_number, get_wkt_quoted_text, destructure_wkt_parse_tree, parse_tree_is_wkt_keyword_with_delimited_list
using ..ParseTrees, ..WKTGrammarSymbolKinds, ..WKTKeywordKinds, ..WKTTokens, ..WKTParseTreeRootedListIterators
function get_wkt_keyword(tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  if parse_node_is_childless(tree)
    throw(ArgumentError("the WKT tree is childless"))
  end
  if parse_node_symbol_kind(tree)::WKTGrammarSymbolKind != WKTGrammarSymbolKinds.keyword_with_optional_delimited_list
    throw(ArgumentError("expected a symbol of keyword_with_optional_delimited_list kind"))
  end
  (terminal, _) = parse_node_children(tree)
  if !parse_node_is_terminal(terminal)
    throw(ArgumentError("expected a terminal symbol"))
  end
  if parse_node_symbol_kind(terminal)::WKTGrammarSymbolKind != WKTGrammarSymbolKinds.keyword
    throw(ArgumentError("expected a symbol of keyword kind"))
  end
  parse_node_to_token(terminal).payload
end
function get_wkt_number(tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  if !parse_node_is_terminal(tree)
    throw(ArgumentError("expected a terminal symbol"))
  end
  if parse_node_symbol_kind(tree)::WKTGrammarSymbolKind != WKTGrammarSymbolKinds.number
    throw(ArgumentError("expected symbol of number kind"))
  end
  parse_node_to_token(tree).payload
end
function get_wkt_quoted_text(terminal::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  if !parse_node_is_terminal(terminal)
    throw(ArgumentError("expected a terminal symbol"))
  end
  if parse_node_symbol_kind(terminal)::WKTGrammarSymbolKind != WKTGrammarSymbolKinds.quoted_text
    throw(ArgumentError("expected a symbol of quoted text kind"))
  end
  parse_node_to_token(terminal).payload
end
function destructure_wkt_parse_tree(tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  if parse_node_is_childless(tree)
    throw(ArgumentError("the WKT tree is childless"))
  end
  if parse_node_symbol_kind(tree)::WKTGrammarSymbolKind != WKTGrammarSymbolKinds.keyword_with_optional_delimited_list
    throw(ArgumentError("expected a symbol of keyword_with_optional_delimited_list kind"))
  end
  (_, tree_optional_delimited_list) = parse_node_children(tree)
  if parse_node_is_childless(tree_optional_delimited_list)
    throw(ArgumentError("no list"))
  end
  tree_delimited_list = only(parse_node_children(tree_optional_delimited_list))
  (_, tree_list, _) = parse_node_children(tree_delimited_list)
  name = WKTKeywordKinds.name_to_kind[get_wkt_keyword(tree)]
  list_iterator = WKTParseTreeRootedListIterator(tree_list)
  (name, list_iterator)
end
function parse_tree_is_wkt_keyword_with_delimited_list(tree::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  (!parse_node_is_childless(tree)) &&
    (
      parse_node_symbol_kind(tree)::WKTGrammarSymbolKind == WKTGrammarSymbolKinds.keyword_with_optional_delimited_list
    ) &&
    let (_, tree_optional_delimited_list) = parse_node_children(tree)
      !parse_node_is_childless(tree_optional_delimited_list)
    end
end
end

module WKTLexing
export lex_wkt
using ..SafeIterate, ..WKTGrammarSymbolKinds, ..WKTTokens
struct WKTTokenIterator{T}
  wkt_string::T
end
function Base.IteratorSize(::Type{<:WKTTokenIterator})
  Base.SizeUnknown()
end
function Base.eltype(::Type{<:WKTTokenIterator})
  WKTToken
end
const char_list_delimiter_left = '['
const char_list_delimiter_right = ']'
const char_list_element_separator = ','
const char_quoted_text_quote = '"'
const char_number_decimal_separator = '.'
const char_number_plus = '+'
const char_number_minus = '-'
const char_number_exponent_separator = 'E'
function most_recently_read_character_with_status_init()
  (;
    most_recently_read_character='🤫',  # just an obviously invalid and recognizable character
    most_recently_read_character_exists=false
  )
end
function validated(c::Char)
  if !isvalid(c)
    throw(ArgumentError("lexer: invalid character encoding"))
  end
  c
end
"""
    Poison()

Invalid value, should throw when used in any way.

Internal to this module, observing `Poison` outside may point to a `WKTLexing` bug.
"""
struct Poison end
function Base.iterate(
  token_iterator::WKTTokenIterator,
  token_iterator_state::NamedTuple=(;
    optional_state=(),
    most_recently_read_character_with_status=most_recently_read_character_with_status_init()
  )
)
  iter = token_iterator.wkt_string
  (; optional_state, most_recently_read_character_with_status) = token_iterator_state
  (; most_recently_read_character, most_recently_read_character_exists) = most_recently_read_character_with_status
  most_recently_read_character_exists = most_recently_read_character_exists::Bool
  most_recently_read_character = most_recently_read_character::Char
  local token
  if optional_state === Poison()
    return nothing
  end
  while true
    elem_state = if most_recently_read_character_exists
      (most_recently_read_character, Poison())
    else
      let t = safe_iterate(iter, optional_state)
        optional_state = Poison()
        t
      end
    end
    most_recently_read_character = Poison()
    most_recently_read_character_exists = false
    if elem_state === nothing
      break
    else
      let s = elem_state[2]
        if s !== Poison()
          optional_state = (s,)
        end
      end
      let char = validated(elem_state[1])
        if !isspace(char)  # drop white space
          if char ∈ (char_list_delimiter_left, char_list_delimiter_right, char_list_element_separator)  # character is an entire token
            token = if char == char_list_delimiter_left
              WKTTokens.new_list_delimiter_left()
            elseif char == char_list_delimiter_right
              WKTTokens.new_list_delimiter_right()
            else
              WKTTokens.new_list_element_separator()
            end
          else
            let
              token_is_quoted_text = char == char_quoted_text_quote
              token_is_keyword = isascii(char) && isletter(char)
              token_is_number_special = char ∈ (char_number_decimal_separator, char_number_minus, char_number_plus)
              token_is_number = token_is_number_special || isdigit(char)
              if token_is_quoted_text || token_is_keyword || token_is_number
                if token_is_quoted_text
                  char = Poison()
                  let payload = ""
                    while true
                      el_st = safe_iterate(iter, optional_state)
                      optional_state = Poison()
                      if el_st === nothing
                        throw(ArgumentError("lexer: EOF in quoted text token"))
                      else
                        optional_state = (el_st[2],)
                        let c = validated(el_st[1])
                          if c == char_quoted_text_quote
                            let es = safe_iterate(iter, optional_state)
                              optional_state = Poison()
                              if es === nothing
                                break
                              else
                                optional_state = (es[2],)
                                let d = validated(es[1])
                                  if d != char_quoted_text_quote
                                    most_recently_read_character = d
                                    most_recently_read_character_exists = true
                                    break
                                  end
                                end
                              end
                            end
                          end
                          payload *= c
                        end
                      end
                    end
                    token = WKTTokens.new_quoted_text(payload)
                  end
                elseif token_is_keyword
                  let payload = string(char)
                    char = Poison()
                    while true
                      el_st = safe_iterate(iter, optional_state)
                      optional_state = Poison()
                      if el_st === nothing
                        break
                      else
                        optional_state = (el_st[2],)
                        let c = validated(el_st[1])
                          if isletter(c)
                            payload *= c
                          else
                            most_recently_read_character = c
                            most_recently_read_character_exists = true
                            break
                          end
                        end
                      end
                    end
                    token = WKTTokens.new_keyword(payload)
                  end
                else
                  let payload = "", ini = true
                    while true
                      el_st = if ini
                        (char, Poison())
                      elseif optional_state === Poison()
                        nothing
                      else
                        let t = safe_iterate(iter, optional_state)
                          optional_state = Poison()
                          t
                        end
                      end
                      ini = false
                      char = Poison()
                      if el_st === nothing
                        break
                      else
                        let s = el_st[2]
                          if s !== Poison()
                            optional_state = (s,)
                          end
                        end
                        let c = validated(el_st[1])
                          is_special =
                            c ∈ (
                              char_number_decimal_separator,
                              char_number_minus,
                              char_number_plus,
                              char_number_exponent_separator
                            )
                          if is_special || isdigit(c)
                            payload *= c
                          else
                            most_recently_read_character = c
                            most_recently_read_character_exists = true
                            break
                          end
                        end
                      end
                    end
                    token = WKTTokens.new_number(payload)
                  end
                end
              else
                throw(ArgumentError("lexer: unrecognized character"))
              end
            end
          end
          break
        end
      end
    end
  end
  most_recently_read_character_exists = most_recently_read_character_exists::Bool
  if !most_recently_read_character_exists
    most_recently_read_character = '🫡'  # just an obviously invalid and recognizable character
  end
  most_recently_read_character = most_recently_read_character::Char
  if @isdefined token
    token = token::WKTToken
    let state,
      most_recently_read_character_with_status = (; most_recently_read_character, most_recently_read_character_exists)

      state = (; optional_state, most_recently_read_character_with_status)
      (token, state)
    end
  else
    nothing
  end
end
"""
    lex_wkt(::Any)

The only argument is expected to be an iterator of `Char` elements. The
contents are expected to be a WKT string, with square brackets for list
delimiters.

Returns an iterator of [`WKTToken`](@ref) elements.
"""
function lex_wkt(wkt_string)
  WKTTokenIterator(wkt_string)
end
end

module WKTParsing
using ..ParseTrees, ..WKTGrammarSymbolKinds, ..WKTTokens
export parse_wkt
const wkt_parsing_table = Dict{Tuple{WKTGrammarSymbolKind,WKTGrammarSymbolKind},Vector{WKTGrammarSymbolKind}}(
  (
    (WKTGrammarSymbolKinds.keyword_with_optional_delimited_list, WKTGrammarSymbolKinds.keyword) =>
      [WKTGrammarSymbolKinds.keyword, WKTGrammarSymbolKinds.optional_delimited_list]
  ),
  (
    (WKTGrammarSymbolKinds.optional_delimited_list, WKTGrammarSymbolKinds.list_delimiter_left) =>
      [WKTGrammarSymbolKinds.delimited_list]
  ),
  (
    (WKTGrammarSymbolKinds.optional_delimited_list, WKTGrammarSymbolKinds.list_delimiter_right) =>
      WKTGrammarSymbolKind[]
  ),
  (
    (WKTGrammarSymbolKinds.optional_delimited_list, WKTGrammarSymbolKinds.list_element_separator) =>
      WKTGrammarSymbolKind[]
  ),
  ((WKTGrammarSymbolKinds.optional_delimited_list, WKTGrammarSymbolKinds.eof) => WKTGrammarSymbolKind[]),
  (
    (WKTGrammarSymbolKinds.delimited_list, WKTGrammarSymbolKinds.list_delimiter_left) => [
      WKTGrammarSymbolKinds.list_delimiter_left,
      WKTGrammarSymbolKinds.nonempty_list,
      WKTGrammarSymbolKinds.list_delimiter_right
    ]
  ),
  (
    (WKTGrammarSymbolKinds.nonempty_list, WKTGrammarSymbolKinds.keyword) =>
      [WKTGrammarSymbolKinds.list_element, WKTGrammarSymbolKinds.optional_incomplete_list]
  ),
  (
    (WKTGrammarSymbolKinds.nonempty_list, WKTGrammarSymbolKinds.number) =>
      [WKTGrammarSymbolKinds.list_element, WKTGrammarSymbolKinds.optional_incomplete_list]
  ),
  (
    (WKTGrammarSymbolKinds.nonempty_list, WKTGrammarSymbolKinds.quoted_text) =>
      [WKTGrammarSymbolKinds.list_element, WKTGrammarSymbolKinds.optional_incomplete_list]
  ),
  (
    (WKTGrammarSymbolKinds.list_element, WKTGrammarSymbolKinds.keyword) =>
      [WKTGrammarSymbolKinds.keyword_with_optional_delimited_list]
  ),
  ((WKTGrammarSymbolKinds.list_element, WKTGrammarSymbolKinds.number) => [WKTGrammarSymbolKinds.number]),
  ((WKTGrammarSymbolKinds.list_element, WKTGrammarSymbolKinds.quoted_text) => [WKTGrammarSymbolKinds.quoted_text]),
  (
    (WKTGrammarSymbolKinds.optional_incomplete_list, WKTGrammarSymbolKinds.list_delimiter_right) =>
      WKTGrammarSymbolKind[]
  ),
  (
    (WKTGrammarSymbolKinds.optional_incomplete_list, WKTGrammarSymbolKinds.list_element_separator) =>
      [WKTGrammarSymbolKinds.incomplete_list]
  ),
  (
    (WKTGrammarSymbolKinds.incomplete_list, WKTGrammarSymbolKinds.list_element_separator) =>
      [WKTGrammarSymbolKinds.list_element_separator, WKTGrammarSymbolKinds.nonempty_list]
  )
)
const eof_token = WKTTokens.new_eof()
function parse_wkt(tokens)
  parse_strong_ll_1_with_appended_eof(
    eof_token,
    wkt_parsing_table,
    WKTGrammarSymbolKinds.keyword_with_optional_delimited_list,
    tokens
  )::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
end
end

module WKTTreeToPROJJSONTree
export wkt_tree_to_projjson_tree
using ..ParseTrees,
  ..JSONGrammarSymbolKinds,
  ..JSONTokens,
  ..PROJJSONTypeKinds,
  ..WKTGrammarSymbolKinds,
  ..WKTTokens,
  ..WKTKeywordKinds,
  ..WKTParseTreeUtil
const json_terminal_symbols = (
  JSONGrammarSymbolKinds.number,
  JSONGrammarSymbolKinds.keyword,
  JSONGrammarSymbolKinds.quoted_text,
  JSONGrammarSymbolKinds.dictionary_delimiter_left,
  JSONGrammarSymbolKinds.dictionary_delimiter_right,
  JSONGrammarSymbolKinds.list_delimiter_left,
  JSONGrammarSymbolKinds.list_delimiter_right,
  JSONGrammarSymbolKinds.list_element_separator,
  JSONGrammarSymbolKinds.pair_element_separator
)
const json_nonterminal_symbols = (
  JSONGrammarSymbolKinds.pair,
  JSONGrammarSymbolKinds.incomplete_dictionary,
  JSONGrammarSymbolKinds.optional_incomplete_dictionary,
  JSONGrammarSymbolKinds.nonempty_dictionary,
  JSONGrammarSymbolKinds.dictionary,
  JSONGrammarSymbolKinds.delimited_dictionary,
  JSONGrammarSymbolKinds.incomplete_list,
  JSONGrammarSymbolKinds.optional_incomplete_list,
  JSONGrammarSymbolKinds.nonempty_list,
  JSONGrammarSymbolKinds.list,
  JSONGrammarSymbolKinds.delimited_list,
  JSONGrammarSymbolKinds.value
)
const projjson_schema_keyword = raw"$schema"
const projjson_schema_url = "https://proj.org/en/latest/schemas/v0.7/projjson.schema.json"
function named_list_has_keyword_kind(tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}, kind::WKTKeywordKind)
  (kw, _) = destructure_wkt_parse_tree(tree_wkt)
  kw::WKTKeywordKind == kind
end
function named_list_has_keyword_kind_geod_or_geog(tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  named_list_has_keyword_kind(tree_wkt, WKTKeywordKinds.geographic_crs) ||
    named_list_has_keyword_kind(tree_wkt, WKTKeywordKinds.geodetic_crs)
end
function named_list_has_keyword_kind_map_projection_method(tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  named_list_has_keyword_kind(tree_wkt, WKTKeywordKinds.method) ||
    named_list_has_keyword_kind(tree_wkt, WKTKeywordKinds.map_projection_method)
end
function named_list_has_keyword_kind_unit(tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  named_list_has_keyword_kind(tree_wkt, WKTKeywordKinds.angle_unit) ||
    named_list_has_keyword_kind(tree_wkt, WKTKeywordKinds.length_unit) ||
    named_list_has_keyword_kind(tree_wkt, WKTKeywordKinds.parametric_unit) ||
    named_list_has_keyword_kind(tree_wkt, WKTKeywordKinds.scale_unit) ||
    named_list_has_keyword_kind(tree_wkt, WKTKeywordKinds.temporal_quantity) ||
    named_list_has_keyword_kind(tree_wkt, WKTKeywordKinds.unit)
end
function partition_by_predicate(predicate, iterator)
  yes = Iterators.filter(predicate, iterator)
  no = Iterators.filter(!predicate, iterator)
  (yes, no)
end
function partition(list)
  (kw_with_list_nodes, simple_nodes) = partition_by_predicate(parse_tree_is_wkt_keyword_with_delimited_list, list)
  (simple_nodes, kw_with_list_nodes)
end
function nonterminal_symbol_value!(
  kinds::Dict{ParseTreeNodeIdentity,JSONGrammarSymbolKind},
  grammar_rules::Dict{ParseTreeNodeIdentity,Vector{ParseTreeNodeIdentity}},
  child::ParseTreeNodeIdentity
)
  if kinds[child] ∉ (
    JSONGrammarSymbolKinds.number,
    JSONGrammarSymbolKinds.quoted_text,
    JSONGrammarSymbolKinds.delimited_list,
    JSONGrammarSymbolKinds.delimited_dictionary
  )
    throw(ArgumentError("expected child kind to be among (number, quoted_text, delimited_list, delimited_dictionary)"))
  end
  value = ParseTreeNodeIdentity()
  kinds[value] = JSONGrammarSymbolKinds.value
  grammar_rules[value] = [child]
  value
end
function nonterminal_symbol_delimited!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  child::ParseTreeNodeIdentity
)
  kinds = graph.node_to_grammar_symbol_kind
  grammar_rules = graph.nonterminal_node_to_children
  tokens = graph.terminal_node_to_token
  child_kind = kinds[child]
  (parent_kind, (left_delimiter_token, right_delimiter_token)) = if child_kind == JSONGrammarSymbolKinds.list
    (JSONGrammarSymbolKinds.delimited_list, (JSONTokens.new_list_delimiter_left(), JSONTokens.new_list_delimiter_right()))
  elseif child_kind == JSONGrammarSymbolKinds.dictionary
    (
      JSONGrammarSymbolKinds.delimited_dictionary,
      (JSONTokens.new_dictionary_delimiter_left(), JSONTokens.new_dictionary_delimiter_right())
    )
  else
    throw(ArgumentError("expected list or dictionary symbol kind"))
  end
  left_delimiter = terminal_symbol_given_token!(kinds, tokens, left_delimiter_token)
  right_delimiter = terminal_symbol_given_token!(kinds, tokens, right_delimiter_token)
  parent = ParseTreeNodeIdentity()
  kinds[parent] = parent_kind
  grammar_rules[parent] = [left_delimiter, child, right_delimiter]
  parent
end
function nonterminal_symbol_pair!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  (quoted_text, value)::Pair{ParseTreeNodeIdentity,ParseTreeNodeIdentity}
)
  kinds = graph.node_to_grammar_symbol_kind
  grammar_rules = graph.nonterminal_node_to_children
  tokens = graph.terminal_node_to_token
  if kinds[quoted_text] != JSONGrammarSymbolKinds.quoted_text
    throw(ArgumentError("expected terminal symbol of quoted_text kind"))
  end
  pair_element_separator = terminal_symbol_given_token!(kinds, tokens, JSONTokens.new_pair_element_separator())
  pair = ParseTreeNodeIdentity()
  kinds[pair] = JSONGrammarSymbolKinds.pair
  grammar_rules[pair] = [quoted_text, pair_element_separator, value]
  pair
end
function nonterminal_symbol_pair!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  (quoted_text_token_payload, value)::Pair{String,ParseTreeNodeIdentity}
)
  kinds = graph.node_to_grammar_symbol_kind
  tokens = graph.terminal_node_to_token
  quoted_text_token = JSONTokens.new_quoted_text(quoted_text_token_payload)
  quoted_text = terminal_symbol_given_token!(kinds, tokens, quoted_text_token)
  nonterminal_symbol_pair!(graph, (quoted_text => value))
end
function assemble!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  collection,
  dictionary_instead_of_list::Bool=false
)
  kinds = graph.node_to_grammar_symbol_kind
  grammar_rules = graph.nonterminal_node_to_children
  tokens = graph.terminal_node_to_token
  list = ParseTreeNodeIdentity()
  kinds[list] = if dictionary_instead_of_list
    JSONGrammarSymbolKinds.dictionary
  else
    JSONGrammarSymbolKinds.list
  end
  grammar_rules[list] = let nonempty_list, once = false
    for value in Iterators.reverse(collect(ParseTreeNodeIdentity, collection))
      value = value::ParseTreeNodeIdentity
      optional_incomplete_list = ParseTreeNodeIdentity()
      kinds[optional_incomplete_list] = if dictionary_instead_of_list
        JSONGrammarSymbolKinds.optional_incomplete_dictionary
      else
        JSONGrammarSymbolKinds.optional_incomplete_list
      end
      grammar_rules[optional_incomplete_list] = if once
        nonempty_list = nonempty_list::ParseTreeNodeIdentity
        let incomplete_list = ParseTreeNodeIdentity()
          kinds[incomplete_list] = if dictionary_instead_of_list
            JSONGrammarSymbolKinds.incomplete_dictionary
          else
            JSONGrammarSymbolKinds.incomplete_list
          end
          list_element_separator_token = JSONTokens.new_list_element_separator()
          list_element_separator = terminal_symbol_given_token!(kinds, tokens, list_element_separator_token)
          grammar_rules[incomplete_list] = [list_element_separator, nonempty_list]
          [incomplete_list]
        end
      else
        ParseTrees.empty_vector
      end
      once = true
      nonempty_list = ParseTreeNodeIdentity()
      kinds[nonempty_list] = if dictionary_instead_of_list
        JSONGrammarSymbolKinds.nonempty_dictionary
      else
        JSONGrammarSymbolKinds.nonempty_list
      end
      grammar_rules[nonempty_list] = [value, optional_incomplete_list]
    end
    if once
      [nonempty_list::ParseTreeNodeIdentity]
    else
      ParseTrees.empty_vector
    end
  end
  nonterminal_symbol_value!(kinds, grammar_rules, nonterminal_symbol_delimited!(graph, list))
end
function assemble!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  dic::AbstractDict{String,ParseTreeNodeIdentity}
)
  function f(pair::Pair{String,ParseTreeNodeIdentity})
    nonterminal_symbol_pair!(graph, pair)
  end
  assemble!(graph, Iterators.map(f, dic), true)
end
function assemble!(graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken}, wkt_token::WKTToken)
  kinds = graph.node_to_grammar_symbol_kind
  grammar_rules = graph.nonterminal_node_to_children
  tokens = graph.terminal_node_to_token
  wkt_token_kind = wkt_token.kind
  wkt_token_payload = wkt_token.payload
  json_token = if wkt_token_kind == WKTGrammarSymbolKinds.number
    JSONTokens.new_number(wkt_token_payload)
  elseif wkt_token_kind == WKTGrammarSymbolKinds.quoted_text
    JSONTokens.new_quoted_text(wkt_token_payload)
  else
    throw(ArgumentError("unrecognized token grammar symbol kind"))
  end::JSONToken
  terminal_symbol = terminal_symbol_given_token!(kinds, tokens, json_token)
  nonterminal_symbol_value!(kinds, grammar_rules, terminal_symbol)
end
function add_token_to_graph!(graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken}, val::JSONToken)
  kinds = graph.node_to_grammar_symbol_kind
  grammar_rules = graph.nonterminal_node_to_children
  tokens = graph.terminal_node_to_token
  value_child = terminal_symbol_given_token!(kinds, tokens, val)
  nonterminal_symbol_value!(kinds, grammar_rules, value_child)
end
function add_number_to_graph!(graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken}, val::String)
  parse(Float64, val)  # throw if not parsable as number
  add_token_to_graph!(graph, JSONTokens.new_number(val))
end
function add_quoted_text_to_graph!(graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken}, val::String)
  add_token_to_graph!(graph, JSONTokens.new_quoted_text(val))
end
function add_value_and_unit_to_graph!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  number_value::String,
  unit::ParseTreeNodeIdentity
)
  kinds = graph.node_to_grammar_symbol_kind
  grammar_rules = graph.nonterminal_node_to_children
  tokens = graph.terminal_node_to_token
  if kinds[unit] != JSONGrammarSymbolKinds.value
    throw(ArgumentError("expected unit symbol to be of value kind"))
  end
  list_element_separator = terminal_symbol_given_token!(kinds, tokens, JSONTokens.new_list_element_separator())
  pair1 = nonterminal_symbol_pair!(
    graph,
    ("value" => terminal_symbol_given_token!(kinds, tokens, JSONTokens.new_number(number_value)))
  )
  pair2 = nonterminal_symbol_pair!(graph, ("unit" => unit))
  incomplete_dictionary = ParseTreeNodeIdentity()
  optional_incomplete_dictionary1 = ParseTreeNodeIdentity()
  optional_incomplete_dictionary2 = ParseTreeNodeIdentity()
  nonempty_dictionary1 = ParseTreeNodeIdentity()
  nonempty_dictionary2 = ParseTreeNodeIdentity()
  dictionary = ParseTreeNodeIdentity()
  kinds[incomplete_dictionary] = JSONGrammarSymbolKinds.incomplete_dictionary
  kinds[optional_incomplete_dictionary1] = JSONGrammarSymbolKinds.optional_incomplete_dictionary
  kinds[optional_incomplete_dictionary2] = JSONGrammarSymbolKinds.optional_incomplete_dictionary
  kinds[nonempty_dictionary1] = JSONGrammarSymbolKinds.nonempty_dictionary
  kinds[nonempty_dictionary2] = JSONGrammarSymbolKinds.nonempty_dictionary
  kinds[dictionary] = JSONGrammarSymbolKinds.dictionary
  grammar_rules[incomplete_dictionary] = [list_element_separator, nonempty_dictionary1]
  grammar_rules[optional_incomplete_dictionary1] = []
  grammar_rules[optional_incomplete_dictionary2] = [incomplete_dictionary]
  grammar_rules[nonempty_dictionary1] = [pair1, optional_incomplete_dictionary1]
  grammar_rules[nonempty_dictionary2] = [pair2, optional_incomplete_dictionary2]
  grammar_rules[dictionary] = [nonempty_dictionary2]
  nonterminal_symbol_value!(kinds, grammar_rules, nonterminal_symbol_delimited!(graph, dictionary))
end
function add_string_value_to_graph!(graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken}, string::String)
  kinds = graph.node_to_grammar_symbol_kind
  grammar_rules = graph.nonterminal_node_to_children
  tokens = graph.terminal_node_to_token
  token = JSONTokens.new_quoted_text(string)
  terminal = terminal_symbol_given_token!(kinds, tokens, token)
  nonterminal_symbol_value!(kinds, grammar_rules, terminal)
end
"""
    number_is_one(::String)

Predicate, return `true` iff the argument represents the multiplicative constant.
"""
function number_is_one(number::String)
  (n1, number_1) = Iterators.peel(number)
  if n1::Char == '1'
    let number_1_iter = Iterators.peel(number_1)
      if number_1_iter === nothing
        true
      else
        let (n2, number_2) = number_1_iter
          if n2::Char == '.'
            all(==('0'), number_2)
          else
            false
          end
        end
      end
    end
  else
    false
  end::Bool
end
function wkt_to_projjson_unit_type(t::WKTKeywordKind)
  if t == WKTKeywordKinds.length_unit
    "LinearUnit"
  elseif t == WKTKeywordKinds.angle_unit
    "AngularUnit"
  elseif t == WKTKeywordKinds.scale_unit
    "ScaleUnit"
  elseif t == WKTKeywordKinds.temporal_quantity
    "TimeUnit"
  elseif t == WKTKeywordKinds.parametric_unit
    "ParametricUnit"
  elseif t == WKTKeywordKinds.unit
    "Unit"
  else
    throw(ArgumentError("unrecognized unit type"))
  end::String
end
function wkt_tree_to_projjson_tree_unit!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if !named_list_has_keyword_kind_unit(tree_wkt)
    throw(ArgumentError("expected unit"))
  end
  (simple_nodes, _) = partition(list)
  (tree_wkt_name, simple_nodes_1) = Iterators.peel(simple_nodes)
  unit_name = get_wkt_quoted_text(tree_wkt_name)
  simple_nodes_rest = Iterators.peel(simple_nodes_1)
  projjson_unit_type = wkt_to_projjson_unit_type(kw)
  if simple_nodes_rest === nothing
    let dictionary = Dict{String,ParseTreeNodeIdentity}()
      dictionary["type"] = add_quoted_text_to_graph!(graph, projjson_unit_type)
      dictionary["name"] = add_quoted_text_to_graph!(graph, unit_name)
      assemble!(graph, dictionary)
    end
  else
    let (tree_wkt_conversion_factor, _) = simple_nodes_rest
      is_special_case = false
      unit_conversion_factor = get_wkt_number(tree_wkt_conversion_factor)
      ret = if number_is_one(unit_conversion_factor)
        if unit_name ∈ ("metre", "meter")
          is_special_case = true
          add_string_value_to_graph!(graph, "metre")
        elseif unit_name ∈ ("degree", "unity")
          is_special_case = true
          add_string_value_to_graph!(graph, unit_name)
        end
      end
      if is_special_case
        ret
      else
        let dictionary = Dict{String,ParseTreeNodeIdentity}()
          dictionary["type"] = add_quoted_text_to_graph!(graph, projjson_unit_type)
          dictionary["name"] = add_quoted_text_to_graph!(graph, unit_name)
          dictionary["conversion_factor"] = add_number_to_graph!(graph, unit_conversion_factor)
          assemble!(graph, dictionary)
        end
      end
    end
  end::ParseTreeNodeIdentity
end
function wkt_tree_to_projjson_tree_id!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if kw != WKTKeywordKinds.identifier
    throw(ArgumentError("expected identifier"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  (simple_nodes, _) = partition(list)
  (tree_wkt_name, simple_nodes_1) = Iterators.peel(simple_nodes)
  dictionary["authority"] = add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_name))
  (tree_wkt_code, _) = Iterators.peel(simple_nodes_1)
  tree_wkt_code_kind = parse_node_symbol_kind(tree_wkt_code)
  dictionary["code"] = if tree_wkt_code_kind == WKTGrammarSymbolKinds.number
    add_number_to_graph!(graph, get_wkt_number(tree_wkt_code))
  elseif tree_wkt_code_kind == WKTGrammarSymbolKinds.quoted_text
    add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_code))
  else
    throw(ArgumentError("expected number or quoted text"))
  end
  assemble!(graph, dictionary)
end
function add_ids_filtered_to_dictionary!(
  dictionary::AbstractDict{String,ParseTreeNodeIdentity},
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  trees_wkt
)
  trees_wkt_iter = Iterators.peel(trees_wkt)
  if trees_wkt_iter !== nothing
    let (tree_wkt_1, rest) = trees_wkt_iter
      rest_iter = Iterators.peel(rest)
      if rest_iter === nothing
        dictionary["id"] = wkt_tree_to_projjson_tree_id!(graph, tree_wkt_1)
      else
        dictionary["ids"] = wkt_trees_to_projjson_tree!(wkt_tree_to_projjson_tree_id!, graph, trees_wkt)
      end
    end
  end
  nothing
end
function add_ids_to_dictionary!(
  dictionary::AbstractDict{String,ParseTreeNodeIdentity},
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  list
)
  trees = Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.identifier), list)
  add_ids_filtered_to_dictionary!(dictionary, graph, trees)
end
function wkt_tree_to_projjson_tree_map_projection_method!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (_, list) = destructure_wkt_parse_tree(tree_wkt)
  if !named_list_has_keyword_kind_map_projection_method(tree_wkt)
    throw(ArgumentError("expected method"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  projjson_type_kind = PROJJSONTypeKinds.OperationMethod
  dictionary["type"] = add_quoted_text_to_graph!(graph, sprint(print, projjson_type_kind))
  (simple_nodes, _) = partition(list)
  (tree_wkt_name, _) = Iterators.peel(simple_nodes)
  dictionary["name"] = add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_name))
  assemble!(graph, dictionary)
end
function wkt_tree_to_projjson_tree_parameter!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if kw != WKTKeywordKinds.parameter
    throw(ArgumentError("expected parameter"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  projjson_type_kind = PROJJSONTypeKinds.ParameterValue
  dictionary["type"] = add_quoted_text_to_graph!(graph, sprint(print, projjson_type_kind))
  (simple_nodes, kw_with_list_nodes) = partition(list)
  (tree_wkt_name, simple_nodes_1) = Iterators.peel(simple_nodes)
  dictionary["name"] = add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_name))
  (tree_wkt_parameter_value, _) = Iterators.peel(simple_nodes_1)
  dictionary["value"] = add_number_to_graph!(graph, get_wkt_number(tree_wkt_parameter_value))
  wkt_units = Iterators.filter(named_list_has_keyword_kind_unit, kw_with_list_nodes)
  wkt_units_iter = Iterators.peel(wkt_units)
  if wkt_units_iter !== nothing
    let (wkt_unit, _) = wkt_units_iter
      dictionary["unit"] = wkt_tree_to_projjson_tree_unit!(graph, wkt_unit)
    end
  end
  assemble!(graph, dictionary)
end
function wkt_tree_to_projjson_tree_datum_ensemble_member!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if kw != WKTKeywordKinds.datum_ensemble_member
    throw(ArgumentError("expected datum ensemble member"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  (simple_nodes, _) = partition(list)
  (tree_wkt_name, _) = Iterators.peel(simple_nodes)
  dictionary["name"] = add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_name))
  assemble!(graph, dictionary)
end
function wkt_trees_to_projjson_tree!(
  func!::Func,
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  trees_wkt
) where {Func}
  function f(tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
    func!(graph, tree_wkt)
  end
  assemble!(graph, Iterators.map(f, trees_wkt))
end
function wkt_tree_to_projjson_tree_conversion!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if kw != WKTKeywordKinds.map_projection
    throw(ArgumentError("expected conversion"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  projjson_type_kind = PROJJSONTypeKinds.Conversion
  dictionary["type"] = add_quoted_text_to_graph!(graph, sprint(print, projjson_type_kind))
  (simple_nodes, kw_with_list_nodes) = partition(list)
  (tree_wkt_name, _) = Iterators.peel(simple_nodes)
  dictionary["name"] = add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_name))
  wkt_map_projection_method =
    only(Iterators.filter(named_list_has_keyword_kind_map_projection_method, kw_with_list_nodes))
  node_map_projection_method = wkt_tree_to_projjson_tree_map_projection_method!(graph, wkt_map_projection_method)
  dictionary["method"] = node_map_projection_method
  wkt_parameters =
    Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.parameter), kw_with_list_nodes)
  if !isempty(wkt_parameters)
    dictionary["parameters"] = wkt_trees_to_projjson_tree!(wkt_tree_to_projjson_tree_parameter!, graph, wkt_parameters)
  end
  assemble!(graph, dictionary)
end
function parse_axis_name_and_abbreviation(name_and_abbreviation::String)
  if last(name_and_abbreviation) == ')'
    # there's an abbreviation at the end
    let sep = findlast(==('('), name_and_abbreviation)
      if sep === nothing
        throw(ArgumentError("malformed"))
      end
      sep = sep::Int
      name = name_and_abbreviation[begin:(sep - 2)]
      abbreviation = name_and_abbreviation[(sep + 1):(end - 1)]
      (name, abbreviation)
    end
  else
    # there's no abbreviation
    (name_and_abbreviation, "")
  end
end
const projjson_allowed_axis_directions = (
  "north",
  "northNorthEast",
  "northEast",
  "eastNorthEast",
  "east",
  "eastSouthEast",
  "southEast",
  "southSouthEast",
  "south",
  "southSouthWest",
  "southWest",
  "westSouthWest",
  "west",
  "westNorthWest",
  "northWest",
  "northNorthWest",
  "up",
  "down",
  "geocentricX",
  "geocentricY",
  "geocentricZ",
  "columnPositive",
  "columnNegative",
  "rowPositive",
  "rowNegative",
  "displayRight",
  "displayLeft",
  "displayUp",
  "displayDown",
  "forward",
  "aft",
  "port",
  "starboard",
  "clockwise",
  "counterClockwise",
  "towards",
  "awayFrom",
  "future",
  "past",
  "unspecified"
)::Tuple{Vararg{String}}
function axis_direction_casing(direc::String)
  for d in projjson_allowed_axis_directions
    if direc == lowercase(d)
      direc = d
      break
    end
  end
  direc
end
function wkt_tree_to_projjson_tree_axis!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if kw != WKTKeywordKinds.axis
    throw(ArgumentError("expected axis"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  projjson_type_kind = PROJJSONTypeKinds.Axis
  dictionary["type"] = add_quoted_text_to_graph!(graph, sprint(print, projjson_type_kind))
  (simple_nodes, kw_with_list_nodes) = partition(list)
  (tree_wkt_name_and_abbreviation, simple_nodes_1) = Iterators.peel(simple_nodes)
  (axis_name, axis_abbreviation) = parse_axis_name_and_abbreviation(get_wkt_quoted_text(tree_wkt_name_and_abbreviation))
  if isempty(axis_name)
    throw(ArgumentError("axis without full name, unsupported"))
  end
  if isempty(axis_abbreviation)
    throw(ArgumentError("axis without abbreviation, unsupported"))
  end
  dictionary["name"] = add_quoted_text_to_graph!(graph, axis_name)
  dictionary["abbreviation"] = add_quoted_text_to_graph!(graph, axis_abbreviation)
  (tree_wkt_direction, _) = Iterators.peel(simple_nodes_1)
  axis_direction = axis_direction_casing(get_wkt_keyword(tree_wkt_direction))
  dictionary["direction"] = add_quoted_text_to_graph!(graph, axis_direction)
  # XXX: meridian, etc.
  assemble!(graph, dictionary)
end
function wkt_tree_to_projjson_tree_coordinate_system!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken},
  trees_wkt_axis
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if kw != WKTKeywordKinds.coordinate_system
    throw(ArgumentError("expected coordinate system"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  projjson_type_kind = PROJJSONTypeKinds.CoordinateSystem
  dictionary["type"] = add_quoted_text_to_graph!(graph, sprint(print, projjson_type_kind))
  (simple_nodes, kw_with_list_nodes) = partition(list)
  (tree_wkt_subtype, simple_nodes_1) = Iterators.peel(simple_nodes)
  cs_subtype = get_wkt_keyword(tree_wkt_subtype)
  if cs_subtype == "cartesian"
    cs_subtype = "Cartesian"
  end
  dictionary["subtype"] = add_quoted_text_to_graph!(graph, cs_subtype)
  dictionary["axis"] = wkt_trees_to_projjson_tree!(wkt_tree_to_projjson_tree_axis!, graph, trees_wkt_axis)
  assemble!(graph, dictionary)
end
function wkt_tree_to_projjson_tree_ellipsoid!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if kw != WKTKeywordKinds.ellipsoid
    throw(ArgumentError("expected ellipsoid"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  projjson_type_kind = PROJJSONTypeKinds.Ellipsoid
  dictionary["type"] = add_quoted_text_to_graph!(graph, sprint(print, projjson_type_kind))
  (simple_nodes, kw_with_list_nodes) = partition(list)
  (tree_wkt_name, simple_nodes_1) = Iterators.peel(simple_nodes)
  dictionary["name"] = add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_name))
  (tree_wkt_semimajor_axis, simple_nodes_2) = Iterators.peel(simple_nodes_1)
  tree_wkt_unit = only(Iterators.filter(named_list_has_keyword_kind_unit, kw_with_list_nodes))
  semimajor_axis_unit = wkt_tree_to_projjson_tree_unit!(graph, tree_wkt_unit)
  dictionary["semi_major_axis"] =
    add_value_and_unit_to_graph!(graph, get_wkt_number(tree_wkt_semimajor_axis), semimajor_axis_unit)
  (tree_wkt_inverse_flattening, _) = Iterators.peel(simple_nodes_2)
  dictionary["inverse_flattening"] = add_number_to_graph!(graph, get_wkt_number(tree_wkt_inverse_flattening))
  assemble!(graph, dictionary)
end
function wkt_tree_to_projjson_tree_datum!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if kw != WKTKeywordKinds.geodetic_reference_frame
    throw(ArgumentError("expected datum"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  (simple_nodes, kw_with_list_nodes) = partition(list)
  (tree_wkt_name, _) = Iterators.peel(simple_nodes)
  dictionary["name"] = add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_name))
  wkt_ellipsoid =
    only(Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.ellipsoid), kw_with_list_nodes))
  dictionary["ellipsoid"] = wkt_tree_to_projjson_tree_ellipsoid!(graph, wkt_ellipsoid)
  assemble!(graph, dictionary)
end
function wkt_tree_to_projjson_tree_datum_ensemble!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if kw != WKTKeywordKinds.datum_ensemble
    throw(ArgumentError("expected datum ensemble"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  projjson_type_kind = PROJJSONTypeKinds.DatumEnsemble
  dictionary["type"] = add_quoted_text_to_graph!(graph, sprint(print, projjson_type_kind))
  (simple_nodes, kw_with_list_nodes) = partition(list)
  (tree_wkt_name, _) = Iterators.peel(simple_nodes)
  dictionary["name"] = add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_name))
  wkt_members =
    Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.datum_ensemble_member), kw_with_list_nodes)
  dictionary["members"] =
    wkt_trees_to_projjson_tree!(wkt_tree_to_projjson_tree_datum_ensemble_member!, graph, wkt_members)
  wkt_ellipsoid =
    only(Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.ellipsoid), kw_with_list_nodes))
  dictionary["ellipsoid"] = wkt_tree_to_projjson_tree_ellipsoid!(graph, wkt_ellipsoid)
  wkt_accuracy = only(
    Iterators.filter(
      Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.datum_ensemble_accuracy),
      kw_with_list_nodes
    )
  )
  (kw_accuracy, list_accuracy) = destructure_wkt_parse_tree(wkt_accuracy)
  if kw_accuracy != WKTKeywordKinds.datum_ensemble_accuracy
    throw(ArgumentError("expected datum ensemble accuracy"))
  end
  accuracy_string = get_wkt_number(only(list_accuracy))
  dictionary["accuracy"] = add_quoted_text_to_graph!(graph, accuracy_string)
  assemble!(graph, dictionary)
end
function wkt_tree_to_projjson_tree_crs_geodetic!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  projjson_type_kind = if kw == WKTKeywordKinds.geodetic_crs
    PROJJSONTypeKinds.GeodeticCRS
  elseif kw == WKTKeywordKinds.geographic_crs
    PROJJSONTypeKinds.GeographicCRS
  else
    throw(ArgumentError("expected geodetic or geographic CRS"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  dictionary[projjson_schema_keyword] = add_quoted_text_to_graph!(graph, projjson_schema_url)
  dictionary["type"] = add_quoted_text_to_graph!(graph, sprint(print, projjson_type_kind))
  (simple_nodes, kw_with_list_nodes) = partition(list)
  (tree_wkt_name, _) = Iterators.peel(simple_nodes)
  dictionary["name"] = add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_name))
  wkt_datum_optional = Iterators.filter(
    Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.geodetic_reference_frame),
    kw_with_list_nodes
  )
  wkt_datum_optional_iterated = Iterators.peel(wkt_datum_optional)
  if wkt_datum_optional_iterated === nothing
    wkt_datum_ensemble =
      only(Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.datum_ensemble), kw_with_list_nodes))
    dictionary["datum_ensemble"] = wkt_tree_to_projjson_tree_datum_ensemble!(graph, wkt_datum_ensemble)
  else
    let (wkt_datum, _) = wkt_datum_optional_iterated
      dictionary["datum"] = wkt_tree_to_projjson_tree_datum!(graph, wkt_datum)
    end
  end
  wkt_cs_optional =
    Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.coordinate_system), kw_with_list_nodes)
  wkt_cs_optional_iterated = Iterators.peel(wkt_cs_optional)
  if wkt_cs_optional_iterated !== nothing
    let (wkt_cs, _) = wkt_cs_optional_iterated
      wkt_axes = Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.axis), kw_with_list_nodes)
      dictionary["coordinate_system"] = wkt_tree_to_projjson_tree_coordinate_system!(graph, wkt_cs, wkt_axes)
    end
  end
  add_ids_to_dictionary!(dictionary, graph, kw_with_list_nodes)
  assemble!(graph, dictionary)
end
function wkt_tree_to_projjson_tree_crs_projected!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, list) = destructure_wkt_parse_tree(tree_wkt)
  if kw != WKTKeywordKinds.projected_crs
    throw(ArgumentError("expected projected CRS"))
  end
  dictionary = Dict{String,ParseTreeNodeIdentity}()
  dictionary[projjson_schema_keyword] = add_quoted_text_to_graph!(graph, projjson_schema_url)
  projjson_type_kind = PROJJSONTypeKinds.ProjectedCRS
  dictionary["type"] = add_quoted_text_to_graph!(graph, sprint(print, projjson_type_kind))
  (simple_nodes, kw_with_list_nodes) = partition(list)
  (tree_wkt_name, simple_nodes_1) = Iterators.peel(simple_nodes)
  dictionary["name"] = add_quoted_text_to_graph!(graph, get_wkt_quoted_text(tree_wkt_name))
  wkt_base_crs = only(Iterators.filter(named_list_has_keyword_kind_geod_or_geog, kw_with_list_nodes))
  dictionary["base_crs"] = wkt_tree_to_projjson_tree_crs_geodetic!(graph, wkt_base_crs)
  wkt_conversion =
    only(Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.map_projection), kw_with_list_nodes))
  dictionary["conversion"] = wkt_tree_to_projjson_tree_conversion!(graph, wkt_conversion)
  wkt_cs = only(
    Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.coordinate_system), kw_with_list_nodes)
  )
  wkt_axes = Iterators.filter(Base.Fix2(named_list_has_keyword_kind, WKTKeywordKinds.axis), kw_with_list_nodes)
  dictionary["coordinate_system"] = wkt_tree_to_projjson_tree_coordinate_system!(graph, wkt_cs, wkt_axes)
  add_ids_to_dictionary!(dictionary, graph, kw_with_list_nodes)
  assemble!(graph, dictionary)
end
function wkt_tree_to_projjson_tree_crs!(
  graph::ParseTreeRootless{JSONGrammarSymbolKind,JSONToken},
  tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken}
)
  (kw, _) = destructure_wkt_parse_tree(tree_wkt)
  if kw ∈ (WKTKeywordKinds.geodetic_crs, WKTKeywordKinds.geographic_crs)
    wkt_tree_to_projjson_tree_crs_geodetic!(graph, tree_wkt)
  elseif kw == WKTKeywordKinds.projected_crs
    wkt_tree_to_projjson_tree_crs_projected!(graph, tree_wkt)
  else
    throw(ArgumentError("not supported"))
  end
end
function wkt_tree_to_projjson_tree(tree_wkt::ParseTreeRooted{WKTGrammarSymbolKind,WKTToken})
  graph = ParseTreeRootless{JSONGrammarSymbolKind,JSONToken}()
  root = wkt_tree_to_projjson_tree_crs!(graph, tree_wkt)
  parse_tree_validate(ParseTreeRooted(root, graph))
end
end

module WKTStringToPROJJSONString
export wkt_string_to_projjson_string
using ..ParseTrees, ..JSONGrammarSymbolKinds, ..JSONTokens, ..WKTLexing, ..WKTParsing, ..WKTTreeToPROJJSONTree
function print_json_token(io::IO, token::JSONToken)
  k = token.kind
  if k == JSONGrammarSymbolKinds.quoted_text
    print(io, '"')  # TODO: implement JSON string escaping properly instead
    print(io, token.payload)
    print(io, '"')
  elseif k ∈ (JSONGrammarSymbolKinds.number, JSONGrammarSymbolKinds.keyword)
    print(io, token.payload)
  else
    let
      c = if k == JSONGrammarSymbolKinds.dictionary_delimiter_left
        '{'
      elseif k == JSONGrammarSymbolKinds.dictionary_delimiter_right
        '}'
      elseif k == JSONGrammarSymbolKinds.list_delimiter_left
        '['
      elseif k == JSONGrammarSymbolKinds.list_delimiter_right
        ']'
      elseif k == JSONGrammarSymbolKinds.list_element_separator
        ','
      elseif k == JSONGrammarSymbolKinds.pair_element_separator
        ':'
      else
        throw(ArgumentError("unrecognized grammar symbol kind"))
      end::Char
      print(io, c)
    end
  end
end
function unparse_json(io::IO, tree::ParseTreeRooted{JSONGrammarSymbolKind,JSONToken})
  unparse(Base.Fix1(print_json_token, io), tree)
end
function wkt_string_to_projjson_string(wkt::String)
  tokens = lex_wkt(wkt)
  wkt_tree = parse_wkt(tokens)
  json_tree = wkt_tree_to_projjson_tree(wkt_tree)
  sprint(unparse_json, json_tree)
end
end
