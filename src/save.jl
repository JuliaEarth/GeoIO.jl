# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    save(fname, geotable; kwargs...)

Save geospatial table to file `fname` using the
appropriate format based on the file extension.
Optionally, specify keyword arguments accepted by
`Shapefile.write` and `GeoJSON.write`. For example, use
`force = true` to force writing on existing `.shp` file.

To see supported formats, use the [`formats`](@ref) function.
"""
function save(fname, geotable; kwargs...)
  # IMG formats
  if any(ext -> endswith(fname, ext), IMGEXTS)
    grid = domain(geotable)
    @assert grid isa Grid "grid not found"
    table = values(geotable)
    cols = Tables.columns(table)
    names = Tables.columnnames(cols)
    @assert :color ∈ names "colors not found"
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

  # STL formats
  if endswith(fname, ".stl")
    return stlwrite(fname, geotable; kwargs...)
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
    GJS.write(fname, geotable; kwargs...)
  elseif endswith(fname, ".parquet")
    GPQ.write(fname, geotable, (:geometry,); kwargs...)
  else # fallback to GDAL
    agwrite(fname, geotable; kwargs...)
  end
end
