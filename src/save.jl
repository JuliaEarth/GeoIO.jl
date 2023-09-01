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

## Supported formats

- `.gslib` via GslibIO.jl
- `.shp` via Shapefile.jl
- `.geojson` via GeoJSON.jl
- `.parquet` via GeoParquet.jl
- Other formats via ArchGDAL.jl
"""
function save(fname, geotable; kwargs...)
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
