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

To check supported formats, see the [`formats`](@ref) function.
"""
function save(fname, geotable; kwargs...)
  # image formats
  if any(ext -> endswith(fname, ext), IMGEXT)
    grid = domain(geotable)
    @assert grid isa Grid "grid not found"
    table = values(geotable)
    cols = Tables.columns(table)
    names = Tables.columnnames(cols)
    @assert :color ∈ names "colors not found"
    colors = Tables.getcolumn(cols, :color)
    img = reshape(colors, size(grid)) |> rotl90
    return FileIO.save(fname, img)
  end

  # geostats formats
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
