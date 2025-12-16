# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gisread(fname; layer, numtype, kwargs...)
  # extract Tables.jl table from GIS format
  table = gistable(fname; layer, numtype, kwargs...)

  # convert Tables.jl table to GeoTable
  asgeotable(table)
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

# helper function to extract Tables.jl table from GIS formats
function gistable(fname; layer, numtype, kwargs...)
  if endswith(fname, ".shp")
    return SHP.Table(fname; kwargs...)
  elseif endswith(fname, ".geojson")
    return GJS.read(fname; numbertype=numtype, kwargs...)
  elseif endswith(fname, ".parquet")
    return GPQ.read(fname; kwargs...)
  elseif endswith(fname, ".gpkg")
    return gpkgtable(fname; layer)
  else # fallback to GDAL
    data = AG.read(fname; kwargs...)
    return AG.getlayer(data, layer - 1)
  end
end

# helper function to convert Tables.jl table to GeoTable
function asgeotable(rawtable)
  # table of attributes and column of geometries
  cols = Tables.columns(rawtable)
  names = Tables.columnnames(cols)
  gcol = geomcolumn(names)
  vars = setdiff(names, [gcol])
  table = isempty(vars) ? nothing : namedtuple(vars, cols)
  geoms = Tables.getcolumn(cols, gcol)

  # identify rows with missing geometries
  miss = findall(g -> ismissing(g) || isnothing(g), geoms)
  if !isempty(miss)
    @warn "Dropping $(length(miss)) rows with missing geometries. Please use `GeoIO.loadvalues(fname; rows=:invalid)` to load their values."
  end
  valid = setdiff(1:length(geoms), miss)

  # subset table and geometries
  stable = isnothing(table) || isempty(miss) ? table : Tables.subset(table, valid)
  sgeoms = geoms[valid]

  # convert to Meshes.jl geometries
  mgeoms = if eltype(sgeoms) <: Geometry
    # already a vector of Meshes.jl geometries
    sgeoms
  else
    # convert geometries to Meshes.jl geometries
    crs = GI.crs(rawtable)
    [geom2meshes(geom, crs) for geom in sgeoms]
  end

  georef(stable, mgeoms)
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
