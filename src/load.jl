# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    load(fname, repair=true, layer=0, lenunit=m, kwargs...)

Load geospatial table from file `fname` stored in any format.

Various `repair`s are performed on the stored geometries by
default, including fixes of orientation in rings of polygons,
removal of zero-area triangles, etc.

Some of the repairs can be expensive on large data sets.
In that case, we recommend setting `repair=false`. Custom
repairs can be performed with the `Repair` transform from
Meshes.jl.

Optionally, specify the `layer` to read within the file, and
the length unit `lenunit` of the coordinates when the format
does not include units in its specification. Other `kwargs`
are forwarded to the backend packages.

Please use the [`formats`](@ref) function to list
all supported file formats.

## Options

### OFF

* `defaultcolor`: default color of the geometries if the file does not have this data
  (default to `RGBA(0.666, 0.666, 0.666, 0.666)`);

### CSV

* `coords`: names of the columns with point coordinates (required option);
* Other options are passed to `CSV.File`, see the CSV.jl documentation for more details;

### VTK formats (`.vtu`, `.vtp`, `.vtr`, `.vts`, `.vti`)

* mask: name of the boolean column that encodes the indices of a grid view (default to `:MASK`).
  If the column does not exist in the file, the full grid is returned;

### Common Data Model formats (`.nc`, `.grib`)

* `x`: name of the column with x coordinates (default to `"x"`, `"X"`, `"lon"`, or `"longitude"`);
* `y`: name of the column with y coordinates (default to `"y"`, `"Y"`, `"lat"`, or `"latitude"`);
* `z`: name of the column with z coordinates (default to `"z"`, `"Z"`, `"depth"`, or `"height"`);
* `t`: name of the column with time measurements (default to `"t"`, `"time"`, or `"TIME"`);

### GSLIB

* Other options are passed to `GslibIO.load`, see the GslibIO.jl documentation for more details;

### Shapefile

* Other options are passed to `Shapefile.read`, see the Shapefile.jl documentation for more details;

### GeoJSON

* Other options are passed to `GeoJSON.read`, see the GeoJSON.jl documentation for more details;

### GeoParquet

* Other options are passed to `GeoParquet.read`, see the GeoParquet.jl documentation for more details;

### GeoTIFF, GeoPackage, KML

* Other options are passed to `ArchGDAL.read`, see the ArchGDAL.jl documentation for more details;

## Examples

```julia
# load coordinates of geojson file as Float64
GeoIO.load("file.geojson", numbertype = Float64)
```
"""
function load(fname; repair=true, layer=0, lenunit=m, kwargs...)
  # VTK formats
  if any(ext -> endswith(fname, ext), VTKEXTS)
    return vtkread(fname; lenunit, kwargs...)
  end

  # STL format
  if endswith(fname, ".stl")
    return stlraed(fname; lenunit, kwargs...)
  end

  # OBJ format
  if endswith(fname, ".obj")
    return objread(fname; lenunit, kwargs...)
  end

  # OFF format
  if endswith(fname, ".off")
    return offread(fname; lenunit, kwargs...)
  end

  # MSH format
  if endswith(fname, ".msh")
    return mshread(fname; lenunit, kwargs...)
  end

  # PLY format
  if endswith(fname, ".ply")
    return plyread(fname; lenunit, kwargs...)
  end

  # CSV format
  if endswith(fname, ".csv")
    return csvread(fname; lenunit, kwargs...)
  end

  # IMG formats
  if any(ext -> endswith(fname, ext), IMGEXTS)
    return imgread(fname; lenunit, kwargs...)
  end

  # GSLIB format
  if endswith(fname, ".gslib")
    return GslibIO.load(fname; kwargs...)
  end

  # Common Data Model formats
  if any(ext -> endswith(fname, ext), CDMEXTS)
    return cdmread(fname; kwargs...)
  end

  # GeoTiff formats
  if any(ext -> endswith(fname, ext), GEOTIFFEXTS)
    return geotiffread(fname; kwargs...)
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
