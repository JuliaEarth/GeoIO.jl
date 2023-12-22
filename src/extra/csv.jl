# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function csvread(fname; coords, kwargs...)
  csv = CSV.File(fname; kwargs...)
  rows = Tables.rows(csv)
  cnames = Symbol.(coords)
  # select only rows where coordinates don't have missing values
  pred(row) = all(!ismissing(Tables.getcolumn(row, nm)) for nm in cnames)

  sinds = Int[]
  for (i, row) in enumerate(rows)
    pred(row) && push!(sinds, i)
  end

  srows = Tables.subset(rows, sinds)
  georef(srows, cnames)
end

function csvwrite(fname, geotable; coords=nothing, floatformat=nothing, kwargs...)
  dom = domain(geotable)
  tab = values(geotable)
  cols = Tables.columns(tab)
  names = Tables.columnnames(tab)
  Dim = embeddim(dom)

  if Dim > 3
    throw(ArgumentError("embedding dimensions greater than 3 are not supported"))
  end

  cnames = if isnothing(coords)
    _cnames(Dim, names)
  else
    if length(coords) ≠ Dim
      throw(ArgumentError("the number of coordinate names must be equal to $Dim (embedding dimension)"))
    end
    Symbol.(coords)
  end

  points = [centroid(dom, i) for i in 1:nelements(dom)]
  cpairs = map(cnames, 1:Dim) do name, d
    name => [coordinates(p)[d] for p in points]
  end

  pairs = (nm => Tables.getcolumn(cols, nm) for nm in names)
  newtab = (; cpairs..., pairs...)

  transform(col, val) = _floatformat(val, floatformat)
  CSV.write(fname, newtab; transform, kwargs...)
end

_floatformat(val, format) = val
_floatformat(val::AbstractFloat, format) = isnothing(format) ? val : generate_formatter(format)(val)

function _cnames(Dim, names)
  cnames = if Dim == 1
    [:x]
  elseif Dim == 2
    [:x, :y]
  else
    [:x, :y, :z]
  end

  # make unique
  map(cnames) do name
    while name ∈ names
      name = Symbol(name, :_)
    end
    name
  end
end
