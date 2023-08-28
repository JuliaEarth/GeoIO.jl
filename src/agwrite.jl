# adapted from https://github.com/evetion/GeoDataFrames.jl/blob/master/src/io.jl
# and from https://github.com/yeesian/ArchGDAL.jl/blob/master/test/test_tables.jl#L264

const DRIVER = AG.extensions()

asstrings(options::Dict{<:AbstractString,<:AbstractString}) =
  [uppercase(String(k)) * "=" * String(v) for (k, v) in options]

function agwrite(fname, geotable; layername="data", options=Dict("geometry_name" => "geometry"))
  geoms = domain(geotable)
  table = values(geotable)
  rows = Tables.rows(table)
  schema = Tables.schema(table)

  # Set geometry name in options
  if !haskey(options, "geometry_name")
    options["geometry_name"] = "geometry"
  end

  ext = last(splitext(fname))
  driver = AG.getdriver(DRIVER[ext])
  optionlist = asstrings(options)
  agtypes = map(schema.types) do type
    try
      T = nonmissingtype(type)
      convert(AG.OGRFieldType, T)
    catch
      error("type $type not supported")
    end
  end

  AG.create(fname; driver) do dataset
    AG.createlayer(; dataset, name=layername, options=optionlist) do layer
      for (name, type) in zip(schema.names, agtypes)
        AG.addfielddefn!(layer, String(name), type)
      end

      for (row, geom) in zip(rows, geoms)
        AG.addfeature(layer) do feature
          for name in schema.names
            x = Tables.getcolumn(row, name)
            i = AG.findfieldindex(feature, name)
            if ismissing(x)
              AG.setfieldnull!(feature, i)
            else
              AG.setfield!(feature, i, x)
            end
          end

          AG.setgeom!(feature, GI.convert(AG.IGeometry, geom))
        end
      end
    end
  end

  fname
end
