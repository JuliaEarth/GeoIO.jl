# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function geotiffread(fname; kwargs...)
  geotiff = GeoTIFF.load(fname; kwargs...)

  # georeferenced grid
  pipe = _pipeline(geotiff)
  dims = size(geotiff) |> reverse
  domain = CartesianGrid(dims) |> pipe

  # adjust the image orientation
  column(x) = vec(PermutedDimsArray(x, (2, 1)))
  # table with colors or channels
  table = if eltype(geotiff) <: Colorant
    (; color=column(geotiff))
  else
    nchanels = GeoTIFF.nchannels(geotiff)
    channel(i) = column(GeoTIFF.channel(geotiff, i))
    (; (Symbol(:channel, i) => channel(i) for i in 1:nchanels)...)
  end

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
  ColType = eltype(Tables.getcolumn(cols, first(names)))
  iscolor = ColType <: Colorant

  # basic checks
  if iscolor
    if length(names) > 1
      throw(ArgumentError("only one color column is allowed"))
    end
  else
    for name in names
      column = Tables.getcolumn(cols, name)
      if !(eltype(column) <: ColType)
        throw(ArgumentError("all variables must have the same type"))
      end
    end
  end

  # retrive CRS information
  CRS = crs(grid)
  code = try
    CoordRefSystems.code(CRS)
  catch
    nothing
  end
  isproj = CRS <: CoordRefSystems.Projected
  islatlon = CRS <: LatLon
  # GeoTIFF only supports EPSG codes
  isepsg = !isnothing(code) && code <: EPSG

  # metadata options
  rastertype = nothing
  modeltype = nothing
  projectedcrs = nothing
  geodeticcrs = nothing
  if (isproj || islatlon) && isepsg
    # GTRasterTypeGeoKey
    rastertype = GeoTIFF.PixelIsArea
    # GTModelTypeGeoKey
    modeltype = isproj ? GeoTIFF.Projected2D : GeoTIFF.Geographic2D
    # ProjectedCRSGeoKey or GeodeticCRSGeoKey
    codenum = _codenum(code)
    if isproj
      projectedcrs = codenum
    else
      geodeticcrs = codenum
    end
  end

  # ModelTransformationTag
  A, b = _affineparams(grid)

  # construct the metadata
  metadata = GeoTIFF.metadata(; transformation=(A, b), rastertype, modeltype, projectedcrs, geodeticcrs)

  # reshape back to GeoTIFF orientation
  image(x) = PermutedDimsArray(reshape(x, dims), (2, 1))
  if iscolor
    # the column contains valid colors
    colors = image(Tables.getcolumn(table, first(names)))
    GeoTIFF.save(fname, colors; metadata, kwargs...)
  else
    # the column contains numeric values
    channels = (image(Tables.getcolumn(table, nm)) for nm in names)
    GeoTIFF.save(fname, channels...; metadata, kwargs...)
  end
end

# -----------------
# HELPER FUNCTIONS
# -----------------

function _pipeline(geotiff)
  metadata = GeoTIFF.metadata(geotiff)
  affine = _affine(metadata)
  morpho = _morphological(metadata)
  affine → morpho
end

function _morphological(metadata)
  code = GeoTIFF.epsgcode(metadata)
  if isnothing(code) || code == GeoTIFF.UserDefined || code == GeoTIFF.Undefined
    Identity()
  else
    epsg = EPSG{Int(code)}
    CRS = CoordRefSystems.get(epsg)
    if CRS <: LatLon
      Morphological() do coords
        lon, lat = CoordRefSystems.raw(coords)
        CRS(lat, lon)
      end
    else
      Morphological() do coords
        x, y = CoordRefSystems.raw(coords)
        CRS(x, y)
      end
    end
  end
end

function _affine(metadata)
  params = GeoTIFF.affineparams2D(metadata)
  if isnothing(params)
    Identity()
  else
    A, b = params
    # check if Affine is an Identity
    if A == SA[1 0; 0 1] && b == SA[0, 0]
      Identity()
    else
      Affine(A, b)
    end
  end
end

_codenum(::Type{EPSG{Code}}) where {Code} = Code

function _affineparams(grid)
  # vertex as raw vector of coordinates
  rawvertex(grid, ijk) = SVector(CoordRefSystems.raw(coords(vertex(grid, ijk))))

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
  b = rawvertex(grid, (1, 1))

  # 2nd step: find A₁
  # x = gridₒ[2, 1] = (1, 0)
  # y = grid[2, 1]
  # y = A*x + b
  # A*x = A₁ * 1 + A₂ * 0
  # y = A₁ + b
  # A₁ = y - b
  # A₁ = grid[2, 1] - grid[1, 1]
  A₁ = rawvertex(grid, (2, 1)) - b

  # 3rd step: find A₂
  # x = gridₒ[1, 2] = (0, 1)
  # y = grid[1, 2]
  # y = A*x + b
  # A*x = A₁ * 0 + A₂ * 1
  # y = A₂ + b
  # A₂ = y - b
  # A₂ = grid[1, 2] - grid[1, 1]
  A₂ = rawvertex(grid, (1, 2)) - b

  # A matrix
  A = [A₁ A₂]

  A, b
end
