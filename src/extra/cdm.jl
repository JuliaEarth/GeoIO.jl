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

  grid = if all(ndims(a) == 1 for a in coords)
    RectilinearGrid(coords...)
  elseif allequal(ndims(a) for a in coords)
    StructuredGrid(coords...)
  else
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
const ZNAMES = ["z", "Z", "depth", "height"]
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
