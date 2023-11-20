# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function cdmread(fname; x=nothing, y=nothing, z=nothing)
  ds = if endswith(fname, ".grib")
    GRIBDatasets.GRIBDataset(fname)
  elseif endswith(fname, ".nc")
    NCDatasets.NCDataset(fname, "r")
  else
    error("unsupported Common Data Model file format")
  end

  xcoord = _coord(ds, _xnames(x))
  ycoord = _coord(ds, _ynames(y))
  zcoord = _coord(ds, _znames(z))
  coords = filter(!isnothing, [xcoord, ycoord, zcoord])

  if isempty(coords)
    error("coordinates not found")
  end

  grid = if all(ndims(a) == 1 for a in coords)
    RectilinearGrid(coords...)
  elseif allequal(ndims(a) for a in coords)
    StructuredGrid(coords...)
  else
    error("invalid grid arrays")
  end
  
  esize = size(grid)
  vsize = esize .+ 1
  names = setdiff(keys(ds), CDM.dimnames(ds))
  enames = filter(nm -> size(ds[nm]) == esize, names)
  vnames = filter(nm -> size(ds[nm]) == vsize, names)
  etable = isempty(enames) ? nothing : (; (Symbol(nm) => ds[nm][:] for nm in enames)...)
  vtable = isempty(vnames) ? nothing : (; (Symbol(nm) => ds[nm][:] for nm in vnames)...)

  close(ds)

  GeoTable(grid; etable, vtable)
end

const XNAMES = ["x", "X", "lon", "longitude"]
const YNAMES = ["y", "Y", "lat", "latitude"]
const ZNAMES = ["z", "Z", "depth", "height"]

_xnames(x) = isnothing(x) ? XNAMES : [x]
_ynames(y) = isnothing(y) ? YNAMES : [y]
_znames(z) = isnothing(z) ? ZNAMES : [z]

function _coord(ds, cnames)
  dnames = CDM.dimnames(ds)
  for name in cnames
    if name ∈ dnames
      return ds[name]
    end
  end
  nothing
end
