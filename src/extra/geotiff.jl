# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# this transform is used internally to reinterpret the CRS of points using raw coordinate values
# it also flips the coordinates into a "xy" order as this is assumed by geotiff and other formats
struct Reinterpret{CRS} <: CoordinateTransform end

Reinterpret(CRS) = Proj(CRS)
Reinterpret(CRS::Type{<:LatLon}) = Reinterpret{CRS}()

Meshes.applycoord(::Reinterpret{CRS}, p::Point) where {CRS} = Point(_reinterpret(CRS, CoordRefSystems.raw(coords(p))))

_reinterpret(::Type{CRS}, (x, y)) where {CRS} = CRS(y, x)

function geotiffread(fname; kwargs...)
  dataset = AG.read(fname; kwargs...)
  crs = AG.getproj(dataset)
  CRS = isempty(crs) ? Cartesian2D : CoordRefSystems.get(crs)
  gt = AG.getgeotransform(dataset)
  dims = (Int(AG.width(dataset)), Int(AG.height(dataset)))
  # GDAL transform:
  # xnew = gt[1] + x * gt[2] + y * gt[3]
  # ynew = gt[4] + x * gt[5] + y * gt[6]
  pipe = Affine(SA[gt[2] gt[3]; gt[5] gt[6]], SA[gt[1], gt[4]]) → Reinterpret(CRS)
  domain = CartesianGrid(dims) |> pipe
  pairs = try
    img = AG.imread(dataset)
    [:COLOR => vec(transpose(img))]
  catch
    map(1:AG.nraster(dataset)) do i
      name = Symbol(:BAND, i)
      column = AG.read(dataset, i)
      name => vec(column)
    end
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
  coltype = eltype(Tables.getcolumn(cols, first(names)))
  iscolor = coltype <: Colorant

  if iscolor
    if length(names) > 1
      throw(ArgumentError("only one color column is allowed"))
    end
  else
    for name in names
      column = Tables.getcolumn(cols, name)
      if !(eltype(column) <: coltype)
        throw(ArgumentError("all variables must have the same type"))
      end
    end
  end

  driver = AG.getdriver("GTiff")
  width, height = dims
  nbands = iscolor ? length(coltype) : length(names)
  dtype = iscolor ? eltype(coltype) : coltype

  AG.create(fname; driver, width, height, nbands, dtype, kwargs...) do dataset
    if iscolor
      column = Tables.getcolumn(cols, first(names))
      C = channelview(reshape(column, dims))
      B = permutedims(C, (2, 3, 1))
      AG.write!(dataset, B, 1:nbands)
    else
      for (i, name) in enumerate(names)
        column = Tables.getcolumn(cols, name)
        band = reshape(column, dims)
        AG.write!(dataset, band, i)
      end
    end
  end
end
