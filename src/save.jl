# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    GeoIO.save(fname, geotable; warn=true, kwargs...)

Save `geotable` to file `fname` of given format
based on the file extension.

The function displays a warning whenever the format
is obsolete (e.g. Shapefile). The warning can be
disabled with the `warn` keyword argument.

Other `kwargs` are forwarded to the backend packages.

Please use the [`formats`](@ref) function to list
all supported file formats.

## Options

### OFF

* `color`: name of the column with geometry colors, if `nothing` 
  the geometries will be saved without colors (default to `nothing`);

### MSH

* `vcolumn`: name of the column in vertex table with node data, if `nothing` 
  the geometries will be saved without node data (default to `nothing`);
* `ecolumn`: name of the column in element table with element data, if `nothing` 
  the geometries will be saved without element data (default to `nothing`);

### STL

* `ascii`: defines whether the file will be saved in ASCII format,
  otherwise Binary format will be used (default to `false`);

### CSV

* `coords`: names of the columns where the point coordinates will be saved (default to `"x"`, `"y"`, `"z"`);
* `floatformat`: C-style format string for float values (default to no formatting);
* Other options are passed to `CSV.write`, see the CSV.jl documentation for more details;

### NetCDF

* `x`: name of the column where the coordinate x will be saved (default to CRS coordinate name);
* `y`: name of the column where the coordinate y will be saved (default to CRS coordinate name);
* `z`: name of the column where the coordinate z will be saved (default to CRS coordinate name);
* `t`: name of the column where the time measurements will be saved (default to `"t"`);

### GeoTIFF

* `options`: list with options that will be passed to GDAL;

### GeoPackage

* `layername`: name of the layer where the data will be saved (default to `"data"`);
* `options`: dictionary with options that will be passed to GDAL;

### GSLIB

* Other options are passed to `GslibIO.save`, see the GslibIO.jl documentation for more details;

### Shapefile

* Other options are passed to `Shapefile.write`, see the Shapefile.jl documentation for more details;

### GeoJSON

* Other options are passed to `GeoJSON.write`, see the GeoJSON.jl documentation for more details;

### GeoParquet

* Other options are passed to `GeoParquet.write`, see the GeoParquet.jl documentation for more details;

## Examples

```julia
# set layer name in GeoPackage
GeoIO.save("file.gpkg", layername = "mylayer")
```
"""
function save(fname, geotable; warn=true, kwargs...)
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

  # VTK formats
  if any(ext -> endswith(fname, ext), VTKEXTS)
    return vtkwrite(fname, geotable)
  end

  # Common Data Model formats
  if any(ext -> endswith(fname, ext), CDMEXTS)
    return cdmwrite(fname, geotable; kwargs...)
  end

  # GeoTiff formats
  if any(ext -> endswith(fname, ext), GEOTIFFEXTS)
    return geotiffwrite(fname, geotable; kwargs...)
  end

  # STL format
  if endswith(fname, ".stl")
    return stlwrite(fname, geotable; kwargs...)
  end

  # OBJ format
  if endswith(fname, ".obj")
    return objwrite(fname, geotable; kwargs...)
  end

  # OFF format
  if endswith(fname, ".off")
    return offwrite(fname, geotable; kwargs...)
  end

  # MSH format
  if endswith(fname, ".msh")
    return mshwrite(fname, geotable; kwargs...)
  end

  # PLY format
  if endswith(fname, ".ply")
    return plywrite(fname, geotable; kwargs...)
  end

  # CSV format
  if endswith(fname, ".csv")
    return csvwrite(fname, geotable; kwargs...)
  end

  # GSLIB format
  if endswith(fname, ".gslib")
    return GslibIO.save(fname, geotable; kwargs...)
  end

  # GIS formats
  if endswith(fname, ".shp")
    if warn
      @warn """
      The Shapefile format is not recommended for various reasons.
      Please http://switchfromshapefile.org if you have the option.
      We recommend the GeoPackage file format (i.e., .gpkg extension)
      instead.

      If you really need to save your data in Shapefile format due to
      project and/or non-technical constraints, you can disable this
      warning by setting `warn=false`.
      """
    end
    SHP.write(fname, geotable; kwargs...)
  elseif endswith(fname, ".geojson")
    proj = if !(crs(domain(geotable)) <: LatLon{WGS84Latest})
      @warn """
      The GeoJSON file format only supports the `LatLon{WGS84Latest}` CRS.

      Attempting a reprojection with `geotable |> Proj(LatLon{WGS84Latest})`...
      """
      Proj(LatLon{WGS84Latest})
    else
      Identity()
    end
    GJS.write(fname, geotable |> proj; kwargs...)
  elseif endswith(fname, ".parquet")
    CRS = crs(domain(geotable))
    GPQ.write(fname, geotable, (:geometry,), projjson(CRS); kwargs...)
  else # fallback to GDAL
    agwrite(fname, geotable; kwargs...)
  end
end

save(fname, ::Domain; kwargs...) =
  throw(ArgumentError("`GeoIO.save` can only save `GeoTable`s. Please save `georef(nothing, domain)` instead"))
