# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    GeoIO.load(fname; repair=true, layer=0, lenunit=nothing, kwargs...)

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

GIS formats with missing geometries are considered bad practice.
In this case, we provide the auxiliary function [`loadvalues`](@ref)
with similar options.

## Options

### OFF

* `defaultcolor`: default color of the geometries if the file does not have this data
  (default to `RGBA(0.666, 0.666, 0.666, 0.666)`);

### CSV

* `coords`: names of the columns with point coordinates (required option);
* Other options are passed to `CSV.File`, see the CSV.jl documentation for more details;

### VTK formats (`.vtu`, `.vtp`, `.vtr`, `.vts`, `.vti`)

* mask: name of the boolean column that encodes the indices of a grid view (default to `:mask`).
  If the column does not exist in the file, the full grid is returned;

### Common Data Model formats (NetCDF, GRIB)

* `x`: name of the column with x coordinates (default to `"x"`, `"X"`, `"lon"`, or `"longitude"`);
* `y`: name of the column with y coordinates (default to `"y"`, `"Y"`, `"lat"`, or `"latitude"`);
* `z`: name of the column with z coordinates (default to `"z"`, `"Z"`, `"depth"`, or `"height"`);
* `t`: name of the column with time measurements (default to `"t"`, `"time"`, or `"TIME"`);

### GeoJSON

* `numbertype`: number type of geometry coordinates (default to `Float64`)
* Other options are passed to `GeoJSON.read`, see the GeoJSON.jl documentation for more details;

### GSLIB

* Other options are passed to `GslibIO.load`, see the GslibIO.jl documentation for more details;

### Shapefile

* Other options are passed to `Shapefile.read`, see the Shapefile.jl documentation for more details;

### GeoParquet

* Other options are passed to `GeoParquet.read`, see the GeoParquet.jl documentation for more details;

### Formats handled by GDAL (GeoPackage, KML)

* Other options are passed to `ArchGDAL.read`, see the ArchGDAL.jl documentation for more details;

## Examples

```julia
# load coordinates of geojson file as Float64 (default)
GeoIO.load("file.geojson")

# load coordinates of geojson file as Float32
GeoIO.load("file.geojson", numbertype=Float32)
```
"""
function load(fname; repair=true, layer=0, lenunit=nothing, numbertype=Float64, kwargs...)
  # VTK formats
  if any(ext -> endswith(fname, ext), VTKEXTS)
    return vtkread(fname; lenunit, kwargs...)
  end

  # STL format
  if endswith(fname, ".stl")
    return stlread(fname; lenunit, kwargs...)
  end

  # OBJ format
  if endswith(fname, ".obj")
    return objread(fname; lenunit, numbertype, kwargs...)
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
    if :coords ∉ keys(kwargs)
      throw(ArgumentError("""
      the `coords` keyword argument is required in the CSV format.

      Examples:

      # load a CSV file with "x" and "y" coordinates
      GeoIO.load("file.csv", coords = ("x", "y"))

      # load a CSV file with "lat" and "lon" coordinates
      GeoIO.load("file.csv", coords = ("lat", "lon"))
      """))
    end
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
  gisread(fname; layer, numbertype, repair, kwargs...)
end

"""
    GeoIO.loadvalues(fname; rows=:all, kwargs...)

Load `values` of geospatial table from file `fname` stored in any GIS format,
skipping the steps to build the `domain` (i.e., geometry column).

The function is particularly useful when geometries are missing. In this case,
the option `rows=:invalid` can be used to retrieve the values of the rows that
were dropped by [`load`](@ref). All other options documented therein for GIS
formats are supported.

## Examples

```julia
# load all values of shapefile, ignoring geometries
GeoIO.loadvalues("file.shp")

# load values of shapefile where geometries are missing
GeoIO.loadvalues("file.shp"; rows=:invalid)
```
"""
function loadvalues(fname; rows=:all, kwargs...)
  # extract Tables.jl table from GIS format
  table = gistable(fname; kwargs...)

  # retrieve variables and geometry column
  cols = Tables.columns(table)
  names = Tables.columnnames(cols)
  gcol = geomcolumn(names)
  vars = setdiff(names, [gcol])

  # if no variables, return nothing
  isempty(vars) && return nothing

  # build values table
  values = namedtuple(vars, cols)

  # filter rows if necessary
  if rows === :invalid
    geoms = Tables.getcolumn(cols, gcol)
    miss = findall(g -> ismissing(g) || isnothing(g), geoms)
    Tables.subset(values, miss)
  elseif rows === :all
    values
  else
    throw(ArgumentError("argument `rows` must be either `:all` or `:invalid`"))
  end
end
