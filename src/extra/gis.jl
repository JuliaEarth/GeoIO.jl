# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gisread(fname; repair, layer, numtype, kwargs...)
  # extract Tables.jl table from GIS format
  table = gistable(fname; layer, numtype, kwargs...)

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
  elseif endswith(fname, ".gpkg")
    gpkgwrite(fname, geotable; kwargs...)
  end
end

# helper function to extract Tables.jl table from GIS formats
function gistable(fname; layer, numtype, kwargs...)
  if endswith(fname, ".shp")
    return SHP.Table(fname; kwargs...)
  elseif endswith(fname, ".geojson")
    return GJS.read(fname; numbertype=numtype, kwargs...)
  elseif endswith(fname, ".parquet")
    return GPQ.read(fname; kwargs...)
  elseif endswith(fname, ".gpkg")
    return gpkgread(fname; kwargs...)
  end
end

# helper function to convert Tables.jl table to GeoTable
function asgeotable(table)
  crs = GI.crs(table)
  cols = Tables.columns(table)
  names = Tables.columnnames(cols)
  gcol = geomcolumn(names)
  vars = setdiff(names, [gcol])
  etable = isempty(vars) ? nothing : namedtuple(vars, cols)
  geoms = Tables.getcolumn(cols, gcol)
  # subset for missing geoms
  miss = findall(g -> ismissing(g) || isnothing(g), geoms)
  if !isempty(miss)
    @warn "Dropping $(length(miss)) rows with missing geometries. Please use `GeoIO.loadvalues(fname; rows=:invalid)` to load their values."
  end
  valid = setdiff(1:length(geoms), miss)
  domain = geom2meshes.(geoms[valid], Ref(crs))
  etable = isnothing(etable) || isempty(miss) ? etable : Tables.subset(etable, valid)
  georef(etable, domain)
end

# helper function to find the geometry column of a table
function geomcolumn(names)
  snames = string.(names)
  gnames = ["geometry", "geom", "shape"]
  gnames = [gnames; uppercase.(gnames); uppercasefirst.(gnames); [""]]
  select = findfirst(∈(snames), gnames)
  if isnothing(select)
    throw(ErrorException("geometry column not found"))
  else
    Symbol(gnames[select])
  end
end
