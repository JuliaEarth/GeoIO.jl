# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gisread(fname; layer, numbertype, repair, kwargs...)
  # extract Tables.jl table from GIS format
  table = gistable(fname; layer, numbertype, kwargs...)

  # convert Tables.jl table to GeoTable
  geotable = asgeotable(table)

  # repair pipeline
  pipeline = if repair
    Repair(11) → Repair(12)
  else
    Identity()
  end

  # perform repairs
  geotable |> pipeline
end
