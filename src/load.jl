# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    load(fname, repair=true, layer=0, kwargs...)

Load geospatial table from file `fname` stored in any format.

Various `repair`s are performed on the stored geometries by
default, including fixes of orientation in rings of polygons,
removal of zero-area triangles, etc.

Some of the repairs can be expensive on large data sets.
In that case, we recommend setting `repair=false`. Custom
repairs can be performed with the `Repair` transform from
Meshes.jl.

Optionally, specify the `layer` to read within the file and
forward `kwargs` to backend packages.

Please use the [`formats`](@ref) function to list
all supported file formats.

## Examples

```julia
# load coordinates of geojson file as Float64
GeoIO.load("file.geojson", numbertype = Float64)
```
"""
function load(fname; repair=true, layer=0, kwargs...)
  # IMG formats
  if any(ext -> endswith(fname, ext), IMGEXTS)
    data = FileIO.load(fname)
    dims = size(data)
    values = (; color=vec(data))
    # translation followed by rotation is faster
    transform = Translate(-dims[1], 0) → Rotate(-π / 2)
    domain = CartesianGrid(dims) |> transform
    return georef(values, domain)
  end

  # VTK formats
  if any(ext -> endswith(fname, ext), VTKEXTS)
    return vtkread(fname; kwargs...)
  end

  # Common Data Model formats
  if any(ext -> endswith(fname, ext), CDMEXTS)
    return cdmread(fname; kwargs...)
  end

  # GeoTiff formats
  if any(ext -> endswith(fname, ext), GEOTIFFEXTS)
    return geotiffread(fname; kwargs...)
  end

  # STL format
  if endswith(fname, ".stl")
    return stlraed(fname; kwargs...)
  end

  # OBJ format
  if endswith(fname, ".obj")
    return objread(fname; kwargs...)
  end

  # OFF format
  if endswith(fname, ".off")
    return offread(fname; kwargs...)
  end

  # MSH format
  if endswith(fname, ".msh")
    return mshread(fname; kwargs...)
  end

  # PLY format
  if endswith(fname, ".ply")
    return plyread(fname; kwargs...)
  end

  # CSV format
  if endswith(fname, ".csv")
    return csvread(fname; kwargs...)
  end

  # GSLIB format
  if endswith(fname, ".gslib")
    return GslibIO.load(fname; kwargs...)
  end

  # GIS formats
  table = if endswith(fname, ".shp")
    SHP.Table(fname; kwargs...)
  elseif endswith(fname, ".geojson")
    GJS.read(fname; kwargs...)
  elseif endswith(fname, ".parquet")
    GPQ.read(fname; kwargs...)
  else # fallback to GDAL
    data = AG.read(fname; kwargs...)
    AG.getlayer(data, layer)
  end

  # construct geotable
  geotable = asgeotable(table)

  # repair pipeline
  pipeline = if repair
    Repair(11) → Repair(12)
  else
    Identity()
  end

  # perform repairs
  geotable |> pipeline
end
