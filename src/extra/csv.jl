# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

csvread(fname; coords, kwargs...) = georef(CSV.File(fname; kwargs...), coords)

function csvwrite(fname, geotable; coords=nothing, kwargs...)
  dom = domain(geotable)
  tab = values(geotable)
  cols = Tables.columns(tab)
  names = Tables.columnnames(tab)
  D = embeddim(dom)

  cnames = if isnothing(coords)
    _cnames(D, names)
  else
    if length(coords) ≠ D
      throw(ArgumentError("the number of coordinates names must be equal to $D (domain dimension)"))
    end
    Symbol.(coords)
  end

  points = [centroid(dom, i) for i in 1:nelements(dom)]
  cpairs = map(cnames, 1:D) do name, dim
    name => [coordinates(p)[dim] for p in points]
  end

  pairs = (nm => Tables.getcolumn(cols, nm) for nm in names)
  newtab = (; pairs..., cpairs...)

  CSV.write(fname, newtab; kwargs...)
end

function _cnames(D, names)
  map(1:D) do dim
    name = Symbol(:X, dim)
    # make unique
    while name ∈ names
      name = Symbol(name, :_)
    end
    name
  end
end
