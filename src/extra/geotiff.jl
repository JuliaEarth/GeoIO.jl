# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function geotiffread(fname; kwargs...)
  dataset = AG.read(fname; kwargs...)
  crs = AG.getproj(dataset)
  CRS = isempty(crs) ? Cartesian2D : CoordRefSystems.get(crs)
  gt = AG.getgeotransform(dataset)
  dims = (Int(AG.width(dataset)), Int(AG.height(dataset)))
  # GDAL transform:
  # xnew = gt[1] + x * gt[2] + y * gt[3]
  # ynew = gt[4] + x * gt[5] + y * gt[6]
  pipe = Affine(SA[gt[2] gt[3]; gt[5] gt[6]], SA[gt[1], gt[4]]) → Proj(CRS)
  domain = CartesianGrid(dims) |> pipe
  pairs = map(1:AG.nraster(dataset)) do i
    name = Symbol(:BAND, i)
    column = AG.read(dataset, i)
    name => vec(column)
  end
  table = (; pairs...)
  georef(table, domain)
end

function geotiffwrite(fname, geotable; kwargs...)
  grid = domain(geotable)
  if !(grid isa Grid && embeddim(grid) == 2)
    throw(ArgumentError("GeoTiff format only supports 2D grids"))
  end
  dims = size(grid)

  table = values(geotable)
  if isnothing(table)
    throw(ArgumentError("GeoTiff format needs data to save"))
  end

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
      band = reshape(column, dims)
      AG.write!(dataset, band, i)
    end
  end
end
