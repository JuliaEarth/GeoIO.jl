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
  geokeydir = _geokeydir(ifd)
  code = _crscode(geokeydir)
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

@enum GeoTIFFTag::UInt16 begin
  GeoKeyDirectoryTag = 34735
  GeoDoubleParamsTag = 34736
  GeoAsciiParamsTag = 34737
  ModelPixelScaleTag = 33550
  ModelTiepointTag = 33922
  ModelTransformationTag = 34264
end

@enum GeoKeyID::UInt16 begin
  GTRasterTypeGeoKey = 1025
  GTModelTypeGeoKey = 1024
  ProjectedCRSGeoKey = 3072
  GeodeticCRSGeoKey = 2048
  VerticalGeoKey = 4096
  GTCitationGeoKey = 1026
  GeodeticCitationGeoKey = 2049
  ProjectedCitationGeoKey = 3073
  VerticalCitationGeoKey = 4097
  GeogAngularUnitsGeoKey = 2054
  GeogAzimuthUnitsGeoKey = 2060
  GeogLinearUnitsGeoKey = 2052
  ProjLinearUnitsGeoKey = 3076
  VerticalUnitsGeoKey = 4099
  GeogAngularUnitSizeGeoKey = 2055
  GeogLinearUnitSizeGeoKey = 2053
  ProjLinearUnitSizeGeoKey = 3077
  GeodeticDatumGeoKey = 2050
  PrimeMeridianGeoKey = 2051
  PrimeMeridianLongitudeGeoKey = 2061
  EllipsoidGeoKey = 2056
  EllipsoidSemiMajorAxisGeoKey = 2057
  EllipsoidSemiMinorAxisGeoKey = 2058
  EllipsoidInvFlatteningGeoKey = 2059
  VerticalDatumGeoKey = 4098
  ProjectionGeoKey = 3074
  ProjMethodGeoKey = 3075
  ProjStdParallel1GeoKey = 3078
  ProjStdParallel2GeoKey = 3079
  ProjNatOriginLongGeoKey = 3080
  ProjNatOriginLatGeoKey = 3081
  ProjFalseOriginLongGeoKey = 3084
  ProjFalseOriginLatGeoKey = 3085
  ProjCenterLongGeoKey = 3088
  ProjCenterLatGeoKey = 3089
  ProjStraightVertPoleLongGeoKey = 3095
  ProjAzimuthAngleGeoKey = 3094
  ProjFalseEastingGeoKey = 3082
  ProjFalseNorthingGeoKey = 3083
  ProjFalseOriginEastingGeoKey = 3086
  ProjFalseOriginNorthingGeoKey = 3087
  ProjCenterEastingGeoKey = 3090
  ProjCenterNorthingGeoKey = 3091
  ProjScaleAtNatOriginGeoKey = 3092
  ProjScaleAtCenterGeoKey = 3093
end

# Corresponding names in the GeoTIFF specification:
# id - KeyID
# tag - TIFFTagLocation
# count - Count
# value - ValueOffset
struct GeoKey
  id::GeoKeyID
  tag::UInt16
  count::UInt16
  value::UInt16
end

# Corresponding names in the GeoTIFF specification:
# version - KeyDirectoryVersion
# revision - KeyRevision
# minor - MinorRevision
# nkeys - NumberOfKeys
# geokeys - Key Entry Set
struct GeoKeyDirectory
  version::UInt16
  revision::UInt16
  minor::UInt16
  nkeys::UInt16
  geokeys::Vector{GeoKey}
end

_gettag(ifd, tag) = TiffImages.getdata(ifd, UInt16(tag), nothing)

function _getgeokey(geokeydir, id)
  geokeys = geokeydir.geokeys
  i = findfirst(gk -> gk.id == id, geokeys)
  isnothing(i) ? nothing : geokeys[i]
end

function _geokeydir(ifd)
  geokeydir = _gettag(ifd, GeoKeyDirectoryTag)
  isnothing(geokeydir) && return nothing

  geokeyview = @view geokeydir[5:end]
  geokeys = map(Iterators.partition(geokeyview, 4)) do geokey
    id = GeoKeyID(geokey[1])
    tag = geokey[2]
    count = geokey[3]
    value = geokey[4]
    GeoKey(id, tag, count, value)
  end

  version = geokeydir[1]
  revision = geokeydir[2]
  minor = geokeydir[3]
  nkeys = geokeydir[4]
  GeoKeyDirectory(version, revision, minor, nkeys, geokeys)
end

function _crscode(geokeydir)
  isnothing(geokeydir) && return nothing
  proj = _getgeokey(geokeydir, ProjectedCRSGeoKey)
  geod = _getgeokey(geokeydir, GeodeticCRSGeoKey)
  if !isnothing(proj)
    EPSG{Int(proj.value)}
  elseif !isnothing(geod)
    EPSG{Int(geod.value)}
  else
    nothing
  end
end

function _transform(ifd)
  transmat = _gettag(ifd, ModelTransformationTag)
  tiepoint = _gettag(ifd, ModelTiepointTag)
  scale = _gettag(ifd, ModelPixelScaleTag)

  if !isnothing(transmat)
    A = SA[
      transmat[1] transmat[2]
      transmat[5] transmat[6]
    ]
    b = SA[transmat[4], transmat[8]]
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
