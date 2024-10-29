# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# this transform is used internally to reinterpret the CRS of points using raw coordinate values
# it also flips the coordinates into a "xy" order as this is assumed by geotiff and other formats
struct Reinterpret{CRS} <: CoordinateTransform end

Reinterpret(CRS) = Reinterpret{CRS}()

Meshes.applycoord(::Reinterpret{CRS}, p::Point) where {CRS} = Point(_reinterpret(CRS, CoordRefSystems.raw(coords(p))))

_reinterpret(::Type{CRS}, (x, y)) where {CRS} = CRS(x, y)
_reinterpret(::Type{CRS}, (x, y)) where {CRS<:LatLon} = CRS(y, x)

function geotiffread(fname; kwargs...)
  tiff = TiffImages.load(fname; kwargs...)
  ifd = TiffImages.ifds(tiff)
  geokeys = _geokeys(ifd)
  code = _crscode(geokeys)
  CRS = isnothing(code) ? Cartesian : CoordRefSystems.get(code)
  trans = _transform(ifd)
  pipe = trans → Reinterpret(CRS) 
  dims = size(tiff)
  domain = CartesianGrid(dims) |> pipe
  table = (; color=vec(tiff))
  georef(table, domain)
end

function geotiffwrite(fname, geotable; kwargs...)
  grid = domain(geotable)
  if !(grid isa Grid && paramdim(grid) == 2)
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

  crsstr = try
    wktstring(CoordRefSystems.code(crs(grid)))
  catch
    nothing
  end

  # geotransform
  # let's define:
  # grid[i, j] = vertex(grid, (i, j))
  # gridₒ = Grid((0, 0), (nx, ny))
  # A₁, A₂ = A[:, 1], A[:, 2]
  # A*x = A₁*x₁ + A₂*x₂
  # y = A*x + b
  # with:
  # x ∈ vertices(gridₒ)
  # y ∈ vertices(grid)
  # 1st step: find b
  # x = gridₒ[1, 1] = (0, 0)
  # y = grid[1, 1]
  # y = A*x + b
  # A*x = A₁ * 0 + A₂ * 0 = (0, 0)
  # y = b
  # b = grid[1, 1]
  g₁₁ = coords(vertex(grid, (1, 1)))
  b = CoordRefSystems.raw(g₁₁)
  # 2nd step: find A₁
  # x = gridₒ[2, 1] = (1, 0)
  # y = grid[2, 1]
  # y = A*x + b
  # A*x = A₁ * 1 + A₂ * 0
  # y = A₁ + b
  # A₁ = y - b
  # A₁ = grid[2, 1] - grid[1, 1]
  g₂₁ = coords(vertex(grid, (2, 1)))
  A₁ = CoordRefSystems.raw(g₂₁) .- b
  # 3rd step: find A₂
  # x = gridₒ[1, 2] = (0, 1)
  # y = grid[1, 2]
  # y = A*x + b
  # A*x = A₁ * 0 + A₂ * 1
  # y = A₂ + b
  # A₂ = y - b
  # A₂ = grid[1, 2] - grid[1, 1]
  g₁₂ = coords(vertex(grid, (1, 2)))
  A₂ = CoordRefSystems.raw(g₁₂) .- b
  # GDAL transform:
  # [b₁, A₁₁, A₁₂, b₂, A₂₁, A₂₂]
  # b₁, b₂ = b[1], b[2]
  # A₁₁, A₂₁ = A₁[1], A₁[2]
  # A₁₂, A₂₂ = A₂[1], A₂[2]
  gt = [b[1], A₁[1], A₂[1], b[2], A₁[2], A₂[2]]

  AG.create(fname; driver, width, height, nbands, dtype, kwargs...) do dataset
    if iscolor
      column = Tables.getcolumn(cols, first(names))
      C = channelview(reshape(column, dims))
      if ndims(C) == 3
        B = permutedims(C, (2, 3, 1))
        AG.write!(dataset, B, 1:nbands)
      else # single channel colors
        B = Array(C)
        AG.write!(dataset, B, 1)
      end
    else
      for (i, name) in enumerate(names)
        column = Tables.getcolumn(cols, name)
        band = reshape(column, dims)
        AG.write!(dataset, band, i)
      end
    end

    AG.setgeotransform!(dataset, gt)
    if !isnothing(crsstr)
      AG.setproj!(dataset, crsstr)
    end
  end
end

struct GeoKey
  id::UInt16
  tag::UInt16
  count::UInt16
  value::UInt16
end

function _geokeys(ifd)
  # The first 4 elements of the GeoKeyDirectory contains:
  # 1 - KeyDirectoryVersion
  # 2 - KeyRevision
  # 3 - MinorRevision
  # 4 - NumberOfKeys
  geokeydir = TiffImages.getdata(ifd, UInt16(34735), nothing)
  isnothing(geokeydir) && return nothing

  nkeys = geokeydir[4]
  map(1:nkeys) do i
    k = i * 4
    id = geokeydir[1 + k]
    tag = geokeydir[2 + k]
    count = geokeydir[3 + k]
    value = geokeydir[4 + k]
    GeoKey(id, tag, count, value)
  end
end

function _getgeokey(geokeys, id)
  i = findfirst(gk -> gk.id == id, geokeys)
  isnothing(i) ? nothing : geokeys[i]
end

function _crscode(geokeys)
  proj = _getgeokey(geokeys, 3072)
  geod = _getgeokey(geokeys, 2048)
  if !isnothing(proj)
    EPSG{Int(proj.value)}
  elseif !isnothing(geod)
    EPSG{Int(geod.value)}
  else
    nothing
  end
end

function _transform(ifd)
  tmatrix = TiffImages.getdata(ifd, UInt16(34264), nothing)
  tiepoint = TiffImages.getdata(ifd, UInt16(33922), nothing)
  scale = TiffImages.getdata(ifd, UInt16(33550), nothing)

  if !isnothing(tmatrix)
    A = SA[
      tmatrix[1] tmatrix[2]
      tmatrix[5] tmatrix[6]
    ]
    b = SA[tmatrix[4], tmatrix[8]]
    Affine(A, b)
  elseif !isnothing(tiepoint) && !isnothing(scale)
    sx, sy = scale[1], scale[2]
    i, j = tiepoint[1], tiepoint[2]
    x, y = tiepoint[4], tiepoint[5]
    tx = x - i / sx
    ty = y + j / sy
    A = SA[
      sx 0
      0 sy
    ]
    b = SA[tx, ty]
    Affine(A, b)
  else
    Identity()
  end
end
