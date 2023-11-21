# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function cdmread(fname; x=nothing, y=nothing, z=nothing, t=nothing, lazy=false)
  ds = if endswith(fname, ".grib")
    GRIBDatasets.GRIBDataset(fname)
  elseif endswith(fname, ".nc")
    NCDatasets.NCDataset(fname, "r")
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
  dnames = isnothing(tname) ? cnames : [tname, cnames...]
  vnames = filter(nm -> issetequal(CDM.dimnames(ds[nm]), dnames), names)
  vtable = if isempty(vnames)
    nothing
  else
    pairs = map(vnames) do name
      var = ds[name]
      arr = _var2array(var, lazy)
      data = if isnothing(tname)
        arr
      else
        dims = _slicedims(var, tname)
        vec(eachslice(arr; dims))
      end
      Symbol(name) => data
    end
    (; pairs...)
  end

  lazy || close(ds)

  GeoTable(grid; vtable)
end

const XNAMES = ["x", "X", "lon", "longitude"]
const YNAMES = ["y", "Y", "lat", "latitude"]
const ZNAMES = ["z", "Z", "depth", "height"]
const TNAMES = ["t", "time", "TIME"]

_xnames(x) = isnothing(x) ? XNAMES : [x]
_ynames(y) = isnothing(y) ? YNAMES : [y]
_znames(z) = isnothing(z) ? ZNAMES : [z]
_tnames(t) = isnothing(t) ? TNAMES : [t]

function _dimname(ds, names)
  dnames = CDM.dimnames(ds)
  for name in names
    if name ∈ dnames
      return name
    end
  end
  nothing
end

function _slicedims(var, tname)
  dnames = CDM.dimnames(var)
  Tuple(findall(≠(tname), dnames))
end

_var2array(var, lazy) = lazy ? var : var[ntuple(i -> :, ndims(var))...]
