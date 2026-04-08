# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function imgread(fname; lenunit)
  # load raw image data
  data = FileIO.load(fname)

  # retrieve length unit
  u = lengthunit(lenunit)

  # construct table of values
  values = (; color=vec(data))

  # construct reference grid
  dims = size(data)
  cmin = ntuple(i -> 0.0u, length(dims))
  cmax = float.(dims) .* u
  grid = CartesianGrid(cmin, cmax; dims)

  # translate and rotate grid
  trans = Translate(-dims[1] * u, 0 * u) → Rotate(-π / 2)
  tgrid = trans(grid)

  georef(values, tgrid)
end

function imgwrite(fname, geotable; kwargs...)
  grid = domain(geotable)
  if !(grid isa Grid)
    throw(ArgumentError("image formats only support grids"))
  end
  table = values(geotable)
  if isnothing(table)
    throw(ArgumentError("image formats need data to save"))
  end
  cols = Tables.columns(table)
  names = Tables.columnnames(cols)
  if :color ∉ names
    throw(ArgumentError("color column not found"))
  end
  colors = Tables.getcolumn(cols, :color)
  img = reshape(colors, size(grid))
  FileIO.save(fname, img, kwargs...)
end
