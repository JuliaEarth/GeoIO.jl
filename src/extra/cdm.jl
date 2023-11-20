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

  xyz = last.(coords)
  grid = if all(ndims(a) == 1 for a in xyz)
    RectilinearGrid(xyz...)
  elseif allequal(ndims(a) for a in xyz)
    StructuredGrid(xyz...)
  else
    error("invalid grid arrays")
  end
  
  cnames = first.(coords)
  vnames = setdiff(keys(ds), [cnames..., CDM.dimnames(ds)...])
  table = (; (Symbol(v) => ds[v] for v in vnames)...)

  close(ds)

  georef(table, grid)
end

const XNAMES = ["x", "X", "lon", "longitude"]
const YNAMES = ["y", "Y", "lat", "latitude"]
const ZNAMES = ["z", "Z", "depth", "height"]

_xnames(x) = isnothing(x) ? XNAMES : [x]
_ynames(y) = isnothing(y) ? YNAMES : [y]
_znames(z) = isnothing(z) ? ZNAMES : [z]

function _coord(ds, cnames)
  for name in cnames
    if haskey(ds, name)
      return name => ds[name]
    end
  end
  nothing
end
