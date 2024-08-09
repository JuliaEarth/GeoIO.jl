# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    save(fname, geotable; kwargs...)

Save geospatial table to file `fname` using the
appropriate format based on the file extension.
Optionally, forward `kwargs` to backend packages.

Please use the [`formats`](@ref) function to list
all supported file formats.

## Examples

```julia
# overwrite an existing shapefile
GeoIO.save("file.shp", force = true)
```
"""
function save(fname, geotable; kwargs...)
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
    GPQ.write(fname, geotable, (:geometry,); kwargs...)
  else # fallback to GDAL
    agwrite(fname, geotable; kwargs...)
  end
end

save(fname, ::Domain; kwargs...) =
  throw(ArgumentError("`GeoIO.save` can only save `GeoTable`s. Please save `georef(nothing, domain)` instead"))
