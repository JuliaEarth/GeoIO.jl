# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    GeoTable{𝒯}

A geospatial table where the underlying table of type `𝒯`
is converted lazily row-by-row to contain geometries from
Meshes.jl for computational geometry in pure Julia.

This table type implements the `Meshes.Data` trait and is
therefore compatible with the GeoStats.jl ecosystem.
"""
struct GeoTable{𝒯} <: Meshes.Data
  table::𝒯
end

function Meshes.domain(t::GeoTable)
  table = getfield(t, :table)
  cols = Tables.columns(table)
  gcol = geomcolumn(cols)
  geoms = Tables.getcolumn(cols, gcol)
  items = geom2meshes.(geoms)
  Meshes.GeometrySet(items)
end

function Meshes.values(t::GeoTable, rank=nothing)
  # find ranks of all geometries
  table = getfield(t, :table)
  cols = Tables.columns(table)
  gcol = geomcolumn(cols)
  geoms = Tables.getcolumn(cols, gcol)
  items = geom2meshes.(geoms)
  ranks = paramdim.(items)

  # select geometries with given rank
  rmax = maximum(ranks)
  rsel = isnothing(rank) ? rmax : rank
  rind = findall(==(rsel), ranks)

  # check if rank exists in data
  if isempty(rind)
    nothing
  else
    # if rank exists, load other columns
    names = Tables.columnnames(cols)
    vars = setdiff(names, [gcol])
    cols = map(vars) do var
      col = Tables.getcolumn(cols, var)
      var => col[rind]
    end
    (; cols...)
  end
end

# helper function to find the
# geometry column of a table
function geomcolumn(cols)
  names = Tables.columnnames(cols)
  if :geometry ∈ names
    :geometry
  elseif :geom ∈ names
    :geom
  elseif Symbol("") ∈ names
    Symbol("")
  else
    throw(ErrorException("geometry column not found"))
  end
end
