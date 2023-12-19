# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function geotiffread(fname; kwargs...)
  dataset = AG.read(fname; kwargs...)
  dims = (Int(AG.width(dataset)), Int(AG.height(dataset)))
  gt = AG.getgeotransform(dataset)
  ps = [AG.applygeotransform(gt, Float64(x), Float64(y)) for x in (0, dims[1]) for y in (0, dims[2])]
  box = boundingbox([Point(p...) for p in ps])
  domain = CartesianGrid(minimum(box), maximum(box); dims)
  pairs = map(1:AG.nraster(dataset)) do i
    name = Symbol(:BAND, i)
    column = AG.read(dataset, i) |> transpose |> rotr90
    name => vec(column)
  end
  table = (; pairs...)
  georef(table, domain)
end

function geotiffwrite(fname, geotable; kwargs...)
  grid = domain(geotable)
  if !(grid isa Grid{2})
    throw(ArgumentError("GeoTiff format only supports 2D grids"))
  end
  dims = size(grid)

  table = values(geotable)
  cols = Tables.columns(table)
  names = Tables.columnnames(cols)

  driver = AG.getdriver("GTiff")
  width, height = dims
  nbands = length(names)
  dtype = eltype(Tables.getcolumn(cols, first(names)))

  for name in names
    column = Tables.getcolumn(cols, name)
    if !(eltype(column) <: dtype)
      throw(ArgumentError("all variables must have the same type"))
    end
  end

  AG.create(fname; driver, width, height, nbands, dtype, kwargs...) do dataset
    for (i, name) in enumerate(names)
      column = Tables.getcolumn(cols, name)
      band = reshape(column, dims) |> rotl90 |> permutedims
      AG.write!(dataset, band, i)
    end
  end
end
