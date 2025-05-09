# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    GeoIO.save(fname, geotable; warn=true, kwargs...)

Save `geotable` to file `fname` of given format
based on the file extension.

Please use the [`formats`](@ref) function to list
all supported file formats.

The function displays a warning whenever the format
is obsolete (e.g. Shapefile). The warning can be
disabled with the `warn` keyword argument.

Other `kwargs` options are forwarded to the backend packages
and are documented below.

## Options

### CSV

* `coords`: names of the columns where the point coordinates will be saved (default to `"x"`, `"y"`, `"z"`);
* `floatformat`: C-style format string for float values (default to no formatting);
* Other options are passed to `CSV.write`, see the CSV.jl documentation for more details;

### GSLIB

* Other options are passed to `GslibIO.save`, see the GslibIO.jl documentation for more details;

### GeoJSON

* Other options are passed to `GeoJSON.write`, see the GeoJSON.jl documentation for more details;

### GeoPackage

* `layername`: name of the layer where the data will be saved (default to `"data"`);
* `options`: dictionary with options that will be passed to GDAL;

### GeoParquet

* Other options are passed to `GeoParquet.write`, see the GeoParquet.jl documentation for more details;

### Shapefile

* Other options are passed to `Shapefile.write`, see the Shapefile.jl documentation for more details;

### MSH

* `vcolumn`: name of the column in vertex table with node data, if `nothing` 
  the geometries will be saved without node data (default to `nothing`);
* `ecolumn`: name of the column in element table with element data, if `nothing` 
  the geometries will be saved without element data (default to `nothing`);

### OFF

* `color`: name of the column with geometry colors, if `nothing` 
  the geometries will be saved without colors (default to `nothing`);

### STL

* `ascii`: defines whether the file will be saved in ASCII format,
  otherwise Binary format will be used (default to `false`);

### Common Data Model formats (NetCDF, GRIB)

* `x`: name of the column where the coordinate x will be saved (default to CRS coordinate name);
* `y`: name of the column where the coordinate y will be saved (default to CRS coordinate name);
* `z`: name of the column where the coordinate z will be saved (default to CRS coordinate name);
* `t`: name of the column where the time measurements will be saved (default to `"t"`);

## Examples

```julia
# set layer name in GeoPackage
GeoIO.save("file.gpkg", layername = "mylayer")
```
"""
function save(fname, geotable; warn=true, kwargs...)
  # CSV format
  if endswith(fname, ".csv")
    return csvwrite(fname, geotable; kwargs...)
  end

  # GSLIB format
  if endswith(fname, ".gslib")
    return GslibIO.save(fname, geotable; kwargs...)
  end

  # MSH format
  if endswith(fname, ".msh")
    return mshwrite(fname, geotable; kwargs...)
  end

  # OBJ format
  if endswith(fname, ".obj")
    return objwrite(fname, geotable; kwargs...)
  end

  # OFF format
  if endswith(fname, ".off")
    return offwrite(fname, geotable; kwargs...)
  end

  # PLY format
  if endswith(fname, ".ply")
    return plywrite(fname, geotable; kwargs...)
  end

  # STL format
  if endswith(fname, ".stl")
    return stlwrite(fname, geotable; kwargs...)
  end

  # IMG formats
  if any(ext -> endswith(fname, ext), IMGEXTS)
    grid = domain(geotable)
    if !(grid isa Grid)
      throw(ArgumentError("image formats only support grids"))
    end
    table = values(geotable)
    if isnothing(table)
      throw(ArgumentError("image formats need data to save"))
    end
    cols = Tables.columns(table)
    names = Tables.columnnames(cols)
    if :color ∉ names
      throw(ArgumentError("color column not found"))
    end
    colors = Tables.getcolumn(cols, :color)
    img = reshape(colors, size(grid))
    return FileIO.save(fname, img)
  end

  # GeoTiff formats
  if any(ext -> endswith(fname, ext), GEOTIFFEXTS)
    return geotiffwrite(fname, geotable; kwargs...)
  end

  # CDM formats
  if any(ext -> endswith(fname, ext), CDMEXTS)
    return cdmwrite(fname, geotable; kwargs...)
  end

  # VTK formats
  if any(ext -> endswith(fname, ext), VTKEXTS)
    return vtkwrite(fname, geotable)
  end

  # GIS formats
  giswrite(fname, geotable; warn, kwargs...)
end

save(fname, ::Domain; kwargs...) =
  throw(ArgumentError("`GeoIO.save` can only save `GeoTable`s. Please save `georef(nothing, domain)` instead"))
