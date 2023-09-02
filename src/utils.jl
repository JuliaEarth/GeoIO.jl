# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function asgeotable(table, fix)
  cols = Tables.columns(table)
  names = Tables.columnnames(cols)
  gcol = geomcolumn(names)
  vars = setdiff(names, [gcol])
  geoms = Tables.getcolumn(cols, gcol)
  etable = (; (v => Tables.getcolumn(cols, v) for v in vars)...)
  domain = GeometrySet(geom2meshes.(geoms, fix))
  geotable(domain; etable)
end

# helper function to find the
# geometry column of a table
function geomcolumn(names)
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
