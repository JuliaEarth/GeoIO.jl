# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gisread(fname; layer, numbertype, repair, kwargs...)
  # extract Tables.jl table from GIS format
  table = gistable(fname; layer, numbertype, kwargs...)

  # convert Tables.jl table to GeoTable
  geotable = asgeotable(table)

  # repair pipeline
  pipeline = if repair
    Repair(11) → Repair(12)
  else
    Identity()
  end

  # perform repairs
  geotable |> pipeline
end

function giswrite(fname, geotable; warn, kwargs...)
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
