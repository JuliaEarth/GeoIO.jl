* Some notes on lexing and parsing WKT
    * language description:
        * The WKT string contains (up to?) one keyword-list pair (named list)
        * Keywords are not case sensitive
        * List delimiter character:
            * left: `[`
            * right: `]`
            * the standard says that `(`, `)` should be supported, too: don't implement
        * List element separator character: `,`
        * A list element may be:
            * floating-point number
            * quoted text/string
                * quoted between double quote symbols
                * within text a double quote is written twice
            * keyword
            * keyword-list pair (named list)
            * date-time thing, don't implement
    * parsing implementation idea:
        * passes:
            * lexing/tokenization
                * input: a stream of Unicode characters
                * output: a stream of tokens (terminal symbols from the perspective of the parser)
            * parsing
                * input: a stream of terminal symbols (tokens from the perspective of the lexer)
                * output: a syntax tree, made of nonterminal and terminal symbols
        * data kinds:
            * syntax tree terminals:
                * list delimiter left
                * list delimiter right
                * list element separator
                * keyword
                * number
                * text
                * end of file
            * syntax tree nonterminals
    * parser implementation: via a strong-LL(1) grammar
        * the grammar:
          ```none
          keyword_with_optional_delimited_list:
              keyword optional_delimited_list
          ;
          optional_delimited_list:
              delimited_list |
          ;
          delimited_list:
              list_delimiter_left nonempty_list list_delimiter_right
          ;
          nonempty_list:
              list_element optional_incomplete_list
          ;
          list_element:
              number |
              quoted_text |
              keyword_with_optional_delimited_list
          ;
          optional_incomplete_list:
              incomplete_list |
          ;
          incomplete_list:
              list_element_separator nonempty_list
          ;
          ```
    * the parsing table is constructed from the grammar given above using this Web app:
        * https://mdaines.github.io/grammophone/?s=a2V5d29yZF93aXRoX29wdGlvbmFsX2RlbGltaXRlZF9saXN0OgogICAga2V5d29yZCBvcHRpb25hbF9kZWxpbWl0ZWRfbGlzdAo7Cm9wdGlvbmFsX2RlbGltaXRlZF9saXN0OgogICAgZGVsaW1pdGVkX2xpc3QgfAo7CmRlbGltaXRlZF9saXN0OgogICAgbGlzdF9kZWxpbWl0ZXJfbGVmdCBub25lbXB0eV9saXN0IGxpc3RfZGVsaW1pdGVyX3JpZ2h0CjsKbm9uZW1wdHlfbGlzdDoKICAgIGxpc3RfZWxlbWVudCBvcHRpb25hbF9pbmNvbXBsZXRlX2xpc3QKOwpsaXN0X2VsZW1lbnQ6CiAgICBudW1iZXIgfAogICAgcXVvdGVkX3RleHQgfAogICAga2V5d29yZF93aXRoX29wdGlvbmFsX2RlbGltaXRlZF9saXN0CjsKb3B0aW9uYWxfaW5jb21wbGV0ZV9saXN0OgogICAgaW5jb21wbGV0ZV9saXN0IHwKOwppbmNvbXBsZXRlX2xpc3Q6CiAgICBsaXN0X2VsZW1lbnRfc2VwYXJhdG9yIG5vbmVtcHR5X2xpc3QKOw==#/
* Translating WKT to PROJJSON JSON
    * WKT peculiarities
        * Keywords are case-insensitive.
        * A WKT keyword may appear with semantic significance multiple times among the sibling elements of a single list.
            * This sometimes needs to be translated to the PROJJSON *plural* forms, see below in "PROJJSON peculiarities"
            * for example:
                * `axis`
                * `definingtransformation`
                * `geoidmodel`
                * `member`
                * `parameter`
                * `parameterfile`
                * `step`
        * A WKT keyword may have multiple alternative names. Specification search term: "alternative keyword".
            * for example: `engcrs` and `engineeringcrs`
            * An peculiar case is the `unit` keyword, which may be used in place of any more specific unit keyword, for backwards compatibility, according to the specification. This seems unworkable, so it's not supported.
        * The standard specifies that `(` and `)` may be used as list delimiter characters instead of `[` and `]`. Not supported here.
    * PROJJSON peculiarities
        * PROJJSON types are often, but not always, optional, due to the fact that software like PROJ may be able to infer the correct type from keyword and the parent object type.
            * I propose just always emitting the type for PROJJSON. That makes testing the PROJJSON output here against the PROJJSON JSON Schema more strict, which is good for a test suite.
            * Omitting inferrable types could still be implemented as an additionall pass over the tree.
        * PROJJSON has special keywords for *plural* forms.
            * for example: `id` and `ids`
    * Relation between the two formats
        * Some WKT keywords have no PROJJSON equivalent, so drop them.
            * for example: `definingtransformation`
                * seems like both epsg.io and spatialreference.org drop this, too
                * https://github.com/OSGeo/PROJ/issues/4469
                * alternative: record them in a `remark` instead of dropping?
        * The relation between WKT keywords and PROJJSON types is not one-to-one.
            * for example: the WKT `engcrs` keyword may translate to either of the `EngineeringCRS` or `DerivedEngineeringCRS` PROJJSON types
        * The relation between WKT keywords and PROJJSON names (types and keywords) is complicated.
            * for example: the WKT keyword `engcrs` corresponds to the PROJJSON type `EngineeringCRS` and/or the PROJJSON keyword `engineering_crs`
        * Unit nodes may appear directly in a CRS definition in WKT, but not in PROJJSON
* Formal grammar for JSON, used implicitly for representing JSON and printing it:
  ```none
  value:
      number |
      quoted_text |
      keyword |
      delimited_list |
      delimited_dictionary
  ;
  delimited_list:
      list_delimiter_left list list_delimiter_right
  ;
  list:
      nonempty_list |
  ;
  nonempty_list:
      value optional_incomplete_list
  ;
  optional_incomplete_list:
      incomplete_list |
  ;
  incomplete_list:
      list_element_separator nonempty_list
  ;
  delimited_dictionary:
      dictionary_delimiter_left dictionary dictionary_delimiter_right
  ;
  dictionary:
      nonempty_dictionary |
  ;
  nonempty_dictionary:
      pair optional_incomplete_dictionary
  ;
  optional_incomplete_dictionary:
      incomplete_dictionary |
  ;
  incomplete_dictionary:
      list_element_separator nonempty_dictionary
  ;
  pair:
      quoted_text pair_element_separator value
  ;
  ```
* Some automatic processing of the PROJJSON JSON schema:
    * For generating the `PROJJSONTypeKind` values:
      ```julia
      using JSON: parsefile
      function getindex_recursive(obj, ::Tuple{})
          obj
      end
      function getindex_recursive(obj, keys::Tuple{Any, Vararg})
          key = keys[1]
          getindex_recursive(obj[key], Base.tail(keys))
      end
      function haskey_recursive(::Any, ::Tuple{})
          true
      end
      function haskey_recursive(obj, keys::Tuple{Any, Vararg})
          key = keys[1]
          haskey(obj, key) && haskey_recursive(obj[key], Base.tail(keys))
      end
      function types_from_definitions(definitions)
          keys = ("properties", "type", "enum")
          definitions_with_keys = Iterators.filter(Base.Fix2(haskey_recursive, keys), values(definitions))
          nested = Iterators.map(Base.Fix2(getindex_recursive, keys), definitions_with_keys)
          Iterators.flatten(nested)
      end
      function print_single(io::IO, type::String, name::String)
          print(io, "const ")
          print(io, type)
          print(io, " = ")
          print(io, name)
          print(io, '(')
          show(io, type)
          print(io, ")\n")
      end
      function to_sorted_string_vector(iterator)
          sort!(collect(String, iterator))
      end
      function do_printing_for_types(io::IO, json_schema)
          types = to_sorted_string_vector(types_from_definitions(json_schema["definitions"]))
          foreach((t -> print_single(io, t, "PROJJSONTypeKind")), types)
      end
      function do_printing(io::IO, json_schema_file_name::String)
          do_printing_for_types(io, parsefile(json_schema_file_name))
      end
      do_printing(stdout, "projjson.schema.json")
      ```
* AbstractTrees.jl implementations for the parse trees:
    * Nice for visualizing a parse tree in interactive usage/debugging using AbstractTrees.jl:
      ```julia
      function AbstractTrees.nodevalue(tree::ParseTreeRooted)
          if parse_node_is_terminal(tree)
              parse_node_to_token(tree)
          else
              parse_node_symbol_kind(tree)
          end
      end
      function AbstractTrees.children(tree::ParseTreeRooted)
          parse_node_children(tree)
      end
      ```
    * Nice for WKT tree visualization, in addition to the above:
      ```julia
      function AbstractTrees.children(tree::ParseTreeRooted{WKTGrammarSymbolKind, WKTToken})
          if (
              (parse_node_symbol_kind(tree)::WKTGrammarSymbolKind == WKTGrammarSymbolKinds.optional_delimited_list) &&
              !parse_node_is_childless(tree)
          )
              # Nicety specific to the WKT grammar: display a list as a flat container, instead of recursively.  
              let delimited_list = only(parse_node_children(tree))
                  (_, list, _) = parse_node_children(delimited_list)
                  WKTParseTreeRootedListIterator(list)
              end
          else
              parse_node_children(tree)
          end
      end
      ```
