# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function cdmread(fname; x=nothing, y=nothing, z=nothing, lazy=false)
  ds = if endswith(fname, ".grib")
    GRIBDatasets.GRIBDataset(fname)
  elseif endswith(fname, ".nc")
    NCDatasets.NCDataset(fname, "r")
  else
    error("unsupported Common Data Model file format")
  end

  xcoord = _coord(ds, _xnames(x), lazy)
  ycoord = _coord(ds, _ynames(y), lazy)
  zcoord = _coord(ds, _znames(z), lazy)
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
  
  vsize = size(grid) .+ 1
  names = setdiff(keys(ds), CDM.dimnames(ds))
  vnames = filter(nm -> size(ds[nm]) == vsize, names)

  getdata(nm) = lazy ? reshape(ds[nm], :) : ds[nm][:]
  vtable = isempty(vnames) ? nothing : (; (Symbol(nm) => getdata(nm) for nm in vnames)...)

  lazy || close(ds)

  GeoTable(grid; vtable)
end

const XNAMES = ["x", "X", "lon", "longitude"]
const YNAMES = ["y", "Y", "lat", "latitude"]
const ZNAMES = ["z", "Z", "depth", "height"]

_xnames(x) = isnothing(x) ? XNAMES : [x]
_ynames(y) = isnothing(y) ? YNAMES : [y]
_znames(z) = isnothing(z) ? ZNAMES : [z]

function _coord(ds, cnames, lazy)
  dnames = CDM.dimnames(ds)
  for name in cnames
    if name ∈ dnames
      cdata = ds[name]
      coord = if lazy
        cdata
      else
        inds = ntuple(i -> :, ndims(cdata))
        cdata[inds...]
      end
      return coord
    end
  end
  nothing
end
