# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

module GeoIO

using Meshes
using Tables

import GADM
import FileIO
import Shapefile as SHP
import GeoJSON as GJS
import ArchGDAL as AG
import GeoInterface as GI

include("conversion.jl")
include("geotable.jl")
include("agwrite.jl")

const IMGEXT = (".png", ".jpg", ".jpeg", ".tif", ".tiff")

"""
    load(fname, layer=0, lazy=false, kwargs...)

Load geospatial table from file `fname` and convert the
`geometry` column to Meshes.jl geometries.

Optionally, specify the `layer` of geometries to read
within the file and keyword arguments `kwargs` accepted
by `Shapefile.Table`, `GeoJSON.read` `GeoParquet.read` and
`ArchGDAL.read`.

The option `lazy` can be used to convert geometries on
the fly instead of converting them immediately.

## Supported formats

- `.shp` via Shapefile.jl
- `.geojson` via GeoJSON.jl
- `.png, .jpg, .jpeg, .tif, .tiff` via ImageIO.jl
- Other formats via ArchGDAL.jl
"""
function load(fname; layer=0, lazy=false, kwargs...)
  # raw image formats
  if any(ext -> endswith(fname, ext), IMGEXT)
    data = FileIO.load(fname)
    dims = size(data)
    etable = (; color=vec(data))
    domain = CartesianGrid(dims)
    return meshdata(domain; etable)
  end

  # GIS file formats
  table = if endswith(fname, ".shp")
    SHP.Table(fname; kwargs...)
  elseif endswith(fname, ".geojson")
    data = Base.read(fname)
    GJS.read(data; kwargs...)
  else # fallback to GDAL
    data = AG.read(fname; kwargs...)
    AG.getlayer(data, layer)
  end

  gtable = GeoTable(table)
  lazy ? gtable : MeshData(gtable)
end

"""
    save(fname, geotable; kwargs...)

Save geospatial table to file `fname` using the
appropriate format based on the file extension.
Optionally, specify keyword arguments accepted by
`Shapefile.write` and `GeoJSON.write`. For example, use
`force = true` to force writing on existing `.shp` file.

## Supported formats

- `.shp` via Shapefile.jl
- `.geojson` via GeoJSON.jl
- Other formats via ArchGDAL.jl
"""
function save(fname, geotable; kwargs...)
  if endswith(fname, ".shp")
    SHP.write(fname, geotable; kwargs...)
  elseif endswith(fname, ".geojson")
    GJS.write(fname, geotable; kwargs...)
  else # fallback to GDAL
    agwrite(fname, geotable; kwargs...)
  end
end

"""
    gadm(country, subregions...; depth=0, ϵ=nothing,
         min=3, max=typemax(Int), maxiter=10)

(Down)load GADM table using `GADM.get` and convert
the `geometry` column to Meshes.jl geometries.

The `depth` option can be used to return tables for subregions
at a given depth starting from the given region specification.

The options `ϵ`, `min`, `max` and `maxiter` are forwarded to the
`decimate` function from Meshes.jl to reduce the number of vertices.
"""
function gadm(country, subregions...; depth=0, ϵ=nothing, min=3, max=typemax(Int), maxiter=10, kwargs...)
  table = GADM.get(country, subregions...; depth=depth, kwargs...)
  gtable = GeoTable(table)
  𝒯 = values(gtable)
  𝒟 = domain(gtable)
  𝒩 = decimate(𝒟, ϵ, min=min, max=max, maxiter=maxiter)
  meshdata(𝒩, etable=𝒯)
end

include("precompile.jl")

end
