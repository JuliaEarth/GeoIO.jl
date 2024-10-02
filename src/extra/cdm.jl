# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function cdmread(fname; x=nothing, y=nothing, z=nothing, t=nothing, lazy=false)
  ds = if endswith(fname, ".grib")
    _gribdataset(fname)
  elseif endswith(fname, ".nc")
    _ncdataset(fname)
  else
    error("unsupported Common Data Model file format")
  end

  xname = _dimname(ds, _xnames(x))
  yname = _dimname(ds, _ynames(y))
  zname = _dimname(ds, _znames(z))
  tname = _dimname(ds, _tnames(t))

  cnames = filter(!isnothing, [xname, yname, zname])
  isempty(cnames) && error("coordinates not found")
  coords = map(nm -> _var2array(ds[nm], lazy), cnames)
  N = length(cnames)

  if !all(ndims(a) == 1 for a in coords)
    error("invalid grid arrays")
  end

  names = setdiff(keys(ds), CDM.dimnames(ds))
  # all dimension names
  dnames = isnothing(tname) ? cnames : [tname, cnames...]
  # variables with vertex data
  vnames = filter(names) do name
    vdims = CDM.dimnames(ds[name])
    issetequal(vdims, cnames) || issetequal(vdims, dnames)
  end

  # get grid mapping (CRS)
  gridmappings = map(vnames) do name
    var = ds[name]
    attribs = CDM.attribnames(var)
    if "grid_mapping" ∈ attribs
      CDM.attrib(var, "grid_mapping")
    else
      nothing
    end
  end

  # convert grid mapping to CRS
  crs = if all(isnothing, gridmappings)
    nothing
  else
    if !allequal(gridmappings)
      error("all variables must have the same CRS")
    end

    gridmapping = first(gridmappings)
    _gm2crs(ds[gridmapping])
  end

  # construct grid with CRS and Manifold
  C = isnothing(crs) ? Cartesian{NoDatum,N,Met{Float64}} : crs
  grid = if C <: LatLon
    lons, lats = coords
    RectilinearGrid{🌐,C}(lats, lons)
  else
    RectilinearGrid{𝔼{N},C}(coords...)
  end

  vtable = if isempty(vnames)
    nothing
  else
    pairs = map(vnames) do name
      var = ds[name]
      data = if _hastime(var, tname)
        arr = _var2array(var, lazy)
        dims = _slicedims(var, tname)
        vec(eachslice(arr; dims))
      else
        _var2vec(var, lazy)
      end
      Symbol(name) => data
    end
    (; pairs...)
  end

  lazy || close(ds)

  GeoTable(grid; vtable)
end

function cdmwrite(fname, geotable; x=nothing, y=nothing, z=nothing, t="t")
  if endswith(fname, ".grib")
    error("saving GRIB files is currently not supported")
  end

  grid = domain(geotable)
  vtable = values(geotable, 0)
  CRS = crs(grid)

  if !(grid isa Union{RectilinearGrid,RegularGrid})
    throw(ArgumentError("NetCDF format only supports rectilinear or regular grids"))
  end

  if paramdim(grid) > 3
    throw(ArgumentError("parametric dimensions greater than 3 are not supported"))
  end

  xyz = map(x -> ustrip.(x), Meshes.xyz(grid))
  # swap x and y for geografic coordinates
  customnames = if CRS <: CoordRefSystems.Geographic
    (y, x, z)
  else
    (x, y, z)
  end
  cnames = if !isnothing(vtable)
    names = Tables.schema(vtable).names
    _coordnames(CRS, customnames, string.(names))
  else
    _coordnames(CRS, customnames, String[])
  end
  dnames = (cnames..., string(t))

  crsattribs = _crsattribs(crs(grid))
  varattribs = isnothing(crsattribs) ? [] : ["grid_mapping" => "crs"]

  sz = Meshes.vsize(grid)
  NCDatasets.Dataset(fname, "c") do ds
    for (d, x) in zip(dnames, xyz)
      NCDatasets.defVar(ds, d, x, [d])
    end

    if !isnothing(crsattribs)
      NCDatasets.defVar(ds, "crs", Int, (), attrib=crsattribs)
    end

    if !isnothing(vtable)
      cols = Tables.columns(vtable)
      names = Tables.columnnames(cols)
      for name in names
        x = Tables.getcolumn(cols, name)
        nmstr = string(name)
        if eltype(x) <: AbstractArray
          y = reshape(transpose(stack(x)), sz..., :)
          NCDatasets.defVar(ds, nmstr, y, dnames, attrib=varattribs)
        else
          y = reshape(x, sz...)
          NCDatasets.defVar(ds, nmstr, y, cnames, attrib=varattribs)
        end
      end
    end
  end
end

# reference of ellipsoid names: https://raw.githubusercontent.com/wiki/cf-convention/cf-conventions/csv/ellipsoid.csv
const ELLIP2DATUM = Dict(
  "WGS 84" => WGS84Latest,
  "GRS 1980" => ITRFLatest,
  "Airy 1830" => OSGB36,
  "Airy Modified 1849" => Ire65,
  "Bessel 1841" => Hermannskogel,
  "International 1924" => NZGD1949,
  "Clarke 1880 (IGN)" => Carthage,
  "GRS 1967 Modified" => SAD69
)

const DATUM2ELLIP = Dict(v => k for (k, v) in ELLIP2DATUM)

function _gribdataset(fname)
  if Sys.iswindows()
    error("loading GRIB files is currently not supported on Windows")
  else
    GRIBDatasets.GRIBDataset(fname)
  end
end

_ncdataset(fname) = NCDatasets.NCDataset(fname, "r")

const XNAMES = ["x", "X", "lon", "longitude"]
const YNAMES = ["y", "Y", "lat", "latitude"]
const ZNAMES = ["z", "Z", "alt", "altitude", "depth", "height"]
const TNAMES = ["t", "time", "TIME"]

_xnames(x) = isnothing(x) ? XNAMES : [string(x)]
_ynames(y) = isnothing(y) ? YNAMES : [string(y)]
_znames(z) = isnothing(z) ? ZNAMES : [string(z)]
_tnames(t) = isnothing(t) ? TNAMES : [string(t)]

function _dimname(ds, names)
  dnames = CDM.dimnames(ds)
  for name in names
    if name ∈ dnames
      return name
    end
  end
  nothing
end

_hastime(var, tname) = !isnothing(tname) && tname ∈ CDM.dimnames(var)

function _slicedims(var, tname)
  dnames = CDM.dimnames(var)
  Tuple(findall(≠(tname), dnames))
end

_var2vec(var, lazy) = lazy ? reshape(var, :) : var[:]
_var2array(var, lazy) = lazy ? var : Array(var)

function _coordnames(CRS, customnames, tablenames)
  defaultnames = CoordRefSystems.names(CRS)
  names = map((cnm, dnm) -> string(isnothing(cnm) ? dnm : cnm), customnames, defaultnames)
  # make unique
  map(names) do name
    while name ∈ tablenames
      name = name * "_"
    end
    name
  end
end

function _gm2crs(gridmapping)
  attribs = CDM.attribnames(gridmapping)

  # get datum from reference ellipsoid
  D = if "reference_ellipsoid_name" ∈ attribs
    ellip = CDM.attrib(gridmapping, "reference_ellipsoid_name")
    ELLIP2DATUM[ellip]
  else
    WGS84Latest
  end

  # shift parameters
  function shift()
    lonₒ = "longitude_of_central_meridian" ∈ attribs ? CDM.attrib(gridmapping, "longitude_of_central_meridian") : 0.0
    xₒ = "false_easting" ∈ attribs ? CDM.attrib(gridmapping, "false_easting") : 0.0
    yₒ = "false_northing" ∈ attribs ? CDM.attrib(gridmapping, "false_northing") : 0.0
    CoordRefSystems.Shift(lonₒ=lonₒ * u"°", xₒ=xₒ * u"m", yₒ=yₒ * u"m")
  end

  # parse CRS type and parameters
  # reference: https://cfconventions.org/cf-conventions/cf-conventions.html#appendix-grid-mappings
  gmname = CDM.attrib(gridmapping, "grid_mapping_name")
  if gmname == "latitude_longitude"
    LatLon{D,Deg{Float64}}
  elseif gmname == "lambert_cylindrical_equal_area"
    latₜₛ = if "standard_parallel" ∈ attribs
      CDM.attrib(gridmapping, "standard_parallel")
    elseif "scale_factor_at_projection_origin" ∈ attribs
      CDM.attrib(gridmapping, "scale_factor_at_projection_origin")
    end
    CoordRefSystems.EqualAreaCylindrical{latₜₛ * u"°",D,shift(),Met{Float64}}
  elseif gmname == "mercator"
    Mercator{D,shift(),Met{Float64}}
  elseif gmname == "orthographic"
    latₒ = CDM.attrib(gridmapping, "latitude_of_projection_origin")
    Mode = CoordRefSystems.EllipticalMode
    CoordRefSystems.Orthographic{Mode,latₒ * u"°",D,shift(),Met{Float64}}
  elseif gmname == "transverse_mercator"
    k₀ = CDM.attrib(gridmapping, "scale_factor_at_central_meridian")
    latₒ = CDM.attrib(gridmapping, "latitude_of_projection_origin")
    TransverseMercator{k₀,latₒ * u"°",D,shift(),Met{Float64}}
  else
    nothing
  end
end

function _crsattribs(CRS)
  D = datum(CRS)

  function shift()
    (; lonₒ, xₒ, yₒ) = CoordRefSystems.projshift(CRS)
    ["longitude_of_central_meridian" => ustrip(lonₒ), "false_easting" => ustrip(xₒ), "false_northing" => ustrip(yₒ)]
  end

  if CRS <: LatLon
    ["grid_mapping_name" => "latitude_longitude", "reference_ellipsoid_name" => DATUM2ELLIP[D]]
  elseif CRS <: CoordRefSystems.EqualAreaCylindrical
    latₜₛ = first(_params(CRS))
    [
      "grid_mapping_name" => "lambert_cylindrical_equal_area",
      "reference_ellipsoid_name" => DATUM2ELLIP[D],
      "standard_parallel" => ustrip(latₜₛ),
      shift()...
    ]
  elseif CRS <: Mercator
    ["grid_mapping_name" => "mercator", "reference_ellipsoid_name" => DATUM2ELLIP[D], shift()...]
  elseif CRS <: CoordRefSystems.Orthographic
    latₒ = first(_params(CRS))
    [
      "grid_mapping_name" => "orthographic",
      "reference_ellipsoid_name" => DATUM2ELLIP[D],
      "latitude_of_projection_origin" => ustrip(latₒ),
      shift()...
    ]
  elseif CRS <: TransverseMercator
    k₀, latₒ = _params(CRS)
    [
      "grid_mapping_name" => "transverse_mercator",
      "reference_ellipsoid_name" => DATUM2ELLIP[D],
      "scale_factor_at_central_meridian" => ustrip(k₀),
      "latitude_of_projection_origin" => ustrip(latₒ),
      shift()...
    ]
  else
    nothing
  end
end

_params(::Type{<:CoordRefSystems.EqualAreaCylindrical{latₜₛ}}) where {latₜₛ} = (latₜₛ,)
_params(::Type{<:CoordRefSystems.Orthographic{Mode,latₒ}}) where {Mode,latₒ} = (latₒ,)
_params(::Type{<:TransverseMercator{k₀,latₒ}}) where {k₀,latₒ} = (k₀, latₒ)
