# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    GeoIO.load(fname; repair=true, layer=1, lenunit=nothing, numtype=Float64, warn=true, kwargs...)

Load geospatial table from file `fname` stored in any format.

Please use the [`formats`](@ref) function to list all supported
file formats. GIS formats with missing geometries are considered
bad practice.  In this case, we provide the auxiliary function
[`loadvalues`](@ref) with similar options.

Various `repair`s are performed on the stored geometries by
default, including fixes of orientation in rings of polygons,
removal of zero-area triangles, etc. Some of the repairs can
be expensive on large data sets. In this case, we recommend
setting `repair=false`. Custom repairs can be performed with
the `Repair` transform from Meshes.jl.

It is also possible to specify the `layer` to read within the
file, the length unit `lenunit` of the coordinates when the
format does not include units in its specification, and the
number type `numtype` of the coordinate values. The function
displays a warning whenever a multi-layer file is loaded with
only the first layer. The warning can be disabled with `warn=false`.

Other `kwargs` options are forwarded to the backend packages
and are documented below.

## Options

### CSV

* `coords`: names of the columns with point coordinates (required option);
* Other options are passed to `CSV.File`, see the CSV.jl documentation for more details;

### GSLIB

* Other options are passed to `GslibIO.load`, see the GslibIO.jl documentation for more details;

### GeoJSON

* Other options are passed to `GeoJSON.read`, see the GeoJSON.jl documentation for more details;

### GeoParquet

* Other options are passed to `GeoParquet.read`, see the GeoParquet.jl documentation for more details;

### Shapefile

* Other options are passed to `Shapefile.read`, see the Shapefile.jl documentation for more details;

### OFF

* `defaultcolor`: default color of the geometries if the file does not have this data
  (default to `RGBA(0.666, 0.666, 0.666, 0.666)`);

### VTK formats (`.vtu`, `.vtp`, `.vtr`, `.vts`, `.vti`)

* mask: name of the boolean column that encodes the indices of a grid view (default to `:mask`).
  If the column does not exist in the file, the full grid is returned;

### Common Data Model formats (NetCDF, GRIB)

* `x`: name of the column with x coordinates (default to `"x"`, `"X"`, `"lon"`, or `"longitude"`);
* `y`: name of the column with y coordinates (default to `"y"`, `"Y"`, `"lat"`, or `"latitude"`);
* `z`: name of the column with z coordinates (default to `"z"`, `"Z"`, `"depth"`, or `"height"`);
* `t`: name of the column with time measurements (default to `"t"`, `"time"`, or `"TIME"`);

## Examples

```julia
# load GeoJSON file
GeoIO.load("file.geojson")

# load GeoPackage file
GeoIO.load("file.gpkg")

# load GeoTIFF file
GeoIO.load("file.tiff")

# load NetCDF file
GeoIO.load("file.nc")
```
"""
function load(fname; repair=true, layer=1, lenunit=nothing, numtype=Float64, warn=true, kwargs...)
  multilayer = endswith(fname, ".gpkg") || any(ext -> endswith(fname, ext), GEOTIFFEXTS)
  if multilayer && warn && layer == 1
    n = nlayers(fname; kwargs...)
    if n > 1
      @warn """
      File has $n layers; loading only layer 1. Use layer=i to load a specific layer,
      or iterate over all layers with a for loop:

        for i in 1:GeoIO.nlayers(fname)
          geotable = GeoIO.load(fname; layer=i)
          ...
        end

      The warning can be disabled with warn=false.
      """
    end
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

  # GSLIB format
  if endswith(fname, ".gslib")
    return GslibIO.load(fname; kwargs...)
  end

  # MSH format
  if endswith(fname, ".msh")
    return mshread(fname; lenunit, kwargs...)
  end

  # OBJ format
  if endswith(fname, ".obj")
    return objread(fname, numtype; lenunit, kwargs...)
  end

  # OFF format
  if endswith(fname, ".off")
    return offread(fname; lenunit, kwargs...)
  end

  # PLY format
  if endswith(fname, ".ply")
    return plyread(fname; lenunit, kwargs...)
  end

  # STL format
  if endswith(fname, ".stl")
    return stlread(fname; lenunit, kwargs...)
  end

  # VTK formats
  if any(ext -> endswith(fname, ext), VTKEXTS)
    return vtkread(fname; lenunit, kwargs...)
  end

  # IMG formats
  if any(ext -> endswith(fname, ext), IMGEXTS)
    return imgread(fname; lenunit, kwargs...)
  end

  # GeoTiff formats
  if any(ext -> endswith(fname, ext), GEOTIFFEXTS)
    return geotiffread(fname; layer, kwargs...)
  end

  # CDM formats
  if any(ext -> endswith(fname, ext), CDMEXTS)
    return cdmread(fname; kwargs...)
  end

  # GIS formats
  geotable = gisread(fname; layer, numtype, kwargs...)

  # repair geometries
  if repair
    geotable |> Repair(11) |> Repair(12)
  else
    geotable
  end
end

"""
    GeoIO.loadvalues(fname; rows=:all, layer=1, numtype=Float64, kwargs...)

Load `values` of geospatial table from file `fname` stored in any GIS format,
skipping the steps to build the `domain` (i.e., geometry column).

The function is particularly useful when geometries are missing. In this case,
the option `rows=:invalid` can be used to retrieve the values of the rows that
were dropped by [`load`](@ref). All other `kwargs` options documented therein
for GIS formats are supported, including the `layer` and the `numtype` options.

## Examples

```julia
# load all values of shapefile, ignoring geometries
GeoIO.loadvalues("file.shp")

# load values of shapefile where geometries are missing
GeoIO.loadvalues("file.shp"; rows=:invalid)
```
"""
function loadvalues(fname; rows=:all, layer=1, numtype=Float64, kwargs...)
  # extract Tables.jl table from GIS format
  table = gistable(fname; layer, numtype, kwargs...)

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

"""
    GeoIO.nlayers(fname; kwargs...)

Returns the number of layers in the file.
For single-layer formats, returns 1.
"""
function nlayers(fname; kwargs...)
  if endswith(fname, ".gpkg")
    return gpkgnlayers(fname)
  elseif any(ext -> endswith(fname, ext), GEOTIFFEXTS)
    return geotiffnlayers(fname; kwargs...)
  else
    return 1
  end
end
