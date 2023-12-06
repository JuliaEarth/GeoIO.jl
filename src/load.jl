# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    load(fname, layer=0, fix=true, kwargs...)

Load geospatial table from file `fname` and convert the
`geometry` column to Meshes.jl geometries.

Optionally, specify the `layer` of geometries to read
within the file and keyword arguments `kwargs` accepted
by `Shapefile.Table`, `GeoJSON.read` `GeoParquet.read` and
`ArchGDAL.read`.

The option `fix` can be used to fix orientation and degeneracy
issues with polygons.

To see supported formats, use the [`formats`](@ref) function.
"""
function load(fname; layer=0, fix=true, kwargs...)
  # IMG formats
  if any(ext -> endswith(fname, ext), IMGEXTS)
    data = FileIO.load(fname) |> rotr90
    dims = size(data)
    values = (; color=vec(data))
    domain = CartesianGrid(dims)
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
    data = Base.read(fname)
    GJS.read(data; kwargs...)
  elseif endswith(fname, ".parquet")
    GPQ.read(fname; kwargs...)
  else # fallback to GDAL
    data = AG.read(fname; kwargs...)
    AG.getlayer(data, layer)
  end

  asgeotable(table, fix)
end
