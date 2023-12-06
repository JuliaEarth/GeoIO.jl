# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

csvread(fname; coords, kwargs...) = georef(CSV.File(fname; kwargs...), coords)

function csvwrite(fname, geotable; coords=nothing, kwargs...)
  dom = domain(geotable)
  tab = values(geotable)
  cols = Tables.columns(tab)
  names = Tables.columnnames(tab)
  Dim = embeddim(dom)

  cnames = if isnothing(coords)
    _cnames(Dim, names)
  else
    if length(coords) ≠ Dim
      throw(ArgumentError("the number of coordinates names must be equal to $Dim (embedding dimension)"))
    end
    Symbol.(coords)
  end

  points = [centroid(dom, i) for i in 1:nelements(dom)]
  cpairs = map(cnames, 1:Dim) do name, d
    name => [coordinates(p)[d] for p in points]
  end

  pairs = (nm => Tables.getcolumn(cols, nm) for nm in names)
  newtab = (; cpairs..., pairs...)

  CSV.write(fname, newtab; kwargs...)
end

function _cnames(Dim, names)
  map(1:Dim) do d
    name = Symbol(:X, d)
    # make unique
    while name ∈ names
      name = Symbol(name, :_)
    end
    name
  end
end
