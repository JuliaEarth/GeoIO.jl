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

function cdmwrite(fname, geotable; x=nothing, y=nothing, z=nothing, t=nothing)
  if endswith(fname, ".grib")
    error("saving GRIB files is currently not supported")
  end

  grid = domain(geotable)
  vtable = values(geotable, 0)
  Dim = embeddim(grid)

  if !(grid isa Union{RectilinearGrid,CartesianGrid})
    throw(ArgumentError("NC format only supports rectilinear or cartesian grids"))
  end

  if Dim > 3
    throw(ArgumentError("embedding dimensions greater than 3 are not supported"))
  end

  xyz = Meshes.xyz(grid)
  dnames = if !isnothing(vtable)
    names = Tables.schema(vtable).names
    _dimnames(Dim, x, y, z, t, string.(names))
  else
    _dimnames(Dim, x, y, z, t, String[])
  end
  cnames = dnames[1:(end - 1)]

  sz = size(grid) .+ 1
  NCDatasets.Dataset(fname, "c") do ds
    for (d, x) in zip(dnames, xyz)
      NCDatasets.defVar(ds, d, x, [d])
    end

    if !isnothing(vtable)
      cols = Tables.columns(vtable)
      names = Tables.columnnames(cols)
      for name in names
        x = Tables.getcolumn(cols, name)
        nmstr = string(name)
        if eltype(x) <: AbstractArray
          y = reshape(transpose(stack(x)), sz..., :)
          NCDatasets.defVar(ds, nmstr, y, dnames)
        else
          y = reshape(x, sz...)
          NCDatasets.defVar(ds, nmstr, y, cnames)
        end
      end
    end
  end
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

function _dimnames(Dim, xnm, ynm, znm, tnm, names)
  xstr = isnothing(xnm) ? "x" : string(xnm)
  ystr = isnothing(ynm) ? "y" : string(ynm)
  zstr = isnothing(znm) ? "z" : string(znm)
  tstr = isnothing(tnm) ? "t" : string(tnm)

  dnames = if Dim == 1
    [xstr, tstr]
  elseif Dim == 2
    [xstr, ystr, tstr]
  else
    [xstr, ystr, zstr, tstr]
  end

  # make unique
  map(dnames) do name
    while name ∈ names
      name = name * "_"
    end
    name
  end
end
