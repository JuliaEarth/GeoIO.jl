# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# adapted from https://github.com/evetion/GeoDataFrames.jl/blob/master/src/io.jl
# and from https://github.com/yeesian/ArchGDAL.jl/blob/master/test/test_tables.jl#L264

const DRIVER = AG.extensions()

asstrings(options::Dict{<:AbstractString,<:AbstractString}) =
  [uppercase(String(k)) * "=" * String(v) for (k, v) in options]

spatialref(code) = AG.importUserInput(codestring(code))

codestring(::Type{EPSG{Code}}) where {Code} = "EPSG:$Code"
codestring(::Type{ESRI{Code}}) where {Code} = "ESRI:$Code"

function agwrite(fname, geotable; layername="data", options=Dict("geometry_name" => "geometry"))
  geoms = domain(geotable)
  table = values(geotable)
  rows = isnothing(table) ? nothing : Tables.rows(table)
  schema = isnothing(table) ? nothing : Tables.schema(table)

  # Set geometry name in options
  if !haskey(options, "geometry_name")
    options["geometry_name"] = "geometry"
  end

  ext = last(splitext(fname))
  driver = AG.getdriver(DRIVER[ext])
  optionlist = asstrings(options)
  agtypes = if isnothing(table)
    nothing
  else
    map(schema.types) do type
      try
        T = nonmissingtype(type)
        convert(AG.OGRFieldType, T)
      catch
        error("type $type not supported")
      end
    end
  end

  spref = try
    spatialref(CoordRefSystems.code(crs(geoms)))
  catch
    AG.SpatialRef()
  end

  AG.create(fname; driver) do dataset
    AG.createlayer(; dataset, name=layername, options=optionlist, spatialref=spref) do layer
      if isnothing(table)
        for geom in geoms
          AG.addfeature(layer) do feature
            AG.setgeom!(feature, GI.convert(AG.IGeometry, geom))
          end
        end
      else
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
  end

  fname
end
