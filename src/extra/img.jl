# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function imgread(fname; lenunit)
  data = FileIO.load(fname)
  dims = size(data)
  values = (; color=vec(data))
  # translation followed by rotation is faster
  transform = Translate(-dims[1], 0) → Rotate(-π / 2)
  # construct grid
  u = lengthunit(lenunit)
  min = ntuple(i -> 0.0u, length(dims))
  max = float.(dims) .* u
  grid = CartesianGrid(min, max; dims)
  georef(values, transform(grid))
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
