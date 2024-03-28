# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function asgeotable(table, fix)
  cols = Tables.columns(table)
  names = Tables.columnnames(cols)
  gcol = geomcolumn(names)
  vars = setdiff(names, [gcol])
  table = isempty(vars) ? nothing : (; (v => Tables.getcolumn(cols, v) for v in vars)...)
  geoms = Tables.getcolumn(cols, gcol)
  domain = GeometrySet(geom2meshes.(geoms, fix))
  georef(table, domain)
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
    error("geometry column not found")
  end
end

# add "_" to `name` until it is unique compared to the table `names`
function uniquename(names, name)
  uname = name
  while uname ∈ names
    uname = Symbol(uname, :_)
  end
  uname
end

# make `newnames` unique compared to the table `names`
function uniquenames(names, newnames)
  map(newnames) do name
    uniquename(names, name)
  end
end
