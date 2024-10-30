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
  if :color ∉ names
    throw(ArgumentError("color column not found"))
  end
  colors = Tables.getcolumn(cols, :color)
  tiff = TiffImages.DenseTaggedImage(reshape(colors, dims))

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

  # GeoKeyDirectoryTag
  geokeys = GeoKey[]
  if (isproj || islatlon) && isepsg
    # GTRasterTypeGeoKey: 1 = Raster type is PixelIsArea
    push!(geokeys, GeoKey(GTRasterTypeGeoKey, 0, 1, 1))
    # GTModelTypeGeoKey: 1 = Projected 2D, 2 = Geographic 2D
    modeltype = isproj ? 1 : 2
    push!(geokeys, GeoKey(GTModelTypeGeoKey, 0, 1, modeltype))
    # ProjectedCRSGeoKey or GeodeticCRSGeoKey
    codenum = _codenum(code)
    if isproj
      push!(geokeys, GeoKey(ProjectedCRSGeoKey, 0, 1, codenum))
    else
      push!(geokeys, GeoKey(GeodeticCRSGeoKey, 0, 1, codenum))
    end
  end

  geokeydir = GeoKeyDirectory(1, 1, 1, length(geokeys), geokeys)
  _settag!(tiff, GeoKeyDirectoryTag, _geokeydir2vec(geokeydir))

  # ModelTransformationTag
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
  # GeoTIFF Transformation Matrix:
  # | a b c d |
  # | e f g h |
  # | i j k l |
  # | m n o p |
  # where:
  # m = n = o = 0, p = 1
  # A = [a b c; e f g]
  # b = [d, h, l]
  # and, for 2D, c = g = k = i = j = k = l = 0
  transmat = Float64[A₁[1], A₂[1], 0, b[1], A₁[2], A₂[2], 0, b[2], 0, 0, 0, 0, 0, 0, 0, 1]
  _settag!(tiff, ModelTransformationTag, transmat)

  TiffImages.save(fname, tiff)
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

  model = _getgeokey(geokeydir, GTModelTypeGeoKey)
  isnothing(model) && return nothing

  if model.value == 1 # Projected 2D
    proj = _getgeokey(geokeydir, ProjectedCRSGeoKey)
    EPSG{Int(proj.value)}
  elseif model.value == 2 # Geographic 2D
    geod = _getgeokey(geokeydir, GeodeticCRSGeoKey)
    EPSG{Int(geod.value)}
  else
    # value 3 - geocentric Cartesian 3D is not supported yet
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
      0 -sy
    ]
    b = SA[tx, ty]
    Affine(A, b)
  else
    Identity()
  end
end

function _settag!(tiff, tag, value)
  ifd = TiffImages.ifds(tiff)
  ifd[UInt16(tag)] = value
end

function _geokeydir2vec(geokeydir)
  vec = [geokeydir.version, geokeydir.revision, geokeydir.minor, geokeydir.nkeys]
  for geokey in geokeydir.geokeys
    append!(vec, [UInt16(geokey.id), geokey.tag, geokey.count, geokey.value])
  end
  vec
end

_codenum(::Type{EPSG{Code}}) where {Code} = Code
