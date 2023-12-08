# GeoIO.jl

[![][build-img]][build-url] [![][codecov-img]][codecov-url]

Load/save geospatial data compatible with the
[GeoStats.jl](https://github.com/JuliaEarth/GeoStats.jl)
framework. 

GeoIO.jl uses various backend packages spread across
different Julia organizations to load a universal
representation of geospatial data as discussed in
the book [*Geospatial Data Science with Julia*](https://juliaearth.github.io/geospatial-data-science-with-julia).

## Usage

### Loading/saving data from/to disk

The `load` and `save` functions are self-explanatory:

```julia
using GeoIO

table = GeoIO.load("file.shp")

GeoIO.save("file.geojson", table)
```

Additional keyword arguments are forwarded to the backends:

```julia
# read `.geojson` geometries with Float64 precision
table = GeoIO.load("file.geojson", numbertype = Float64)

# force writing on existing `.shp` file
GeoIO.save("file.shp", table, force = true)
```

### Supported formats

To see the formats supported by GeoIO.jl, use the `formats` function.
Below is the output generated on December 8th, 2023:

```julia
GeoIO.formats()
┌───────────┬─────────────────┬───────────────┐
│ extension │      load       │     save      │
├───────────┼─────────────────┼───────────────┤
│   .csv    │     CSV.jl      │    CSV.jl     │
│ .geojson  │   GeoJSON.jl    │  GeoJSON.jl   │
│   .gpkg   │   ArchGDAL.jl   │  ArchGDAL.jl  │
│   .grib   │ GRIBDatasets.jl │               │
│  .gslib   │   GslibIO.jl    │  GslibIO.jl   │
│   .jpeg   │   ImageIO.jl    │  ImageIO.jl   │
│   .jpg    │   ImageIO.jl    │  ImageIO.jl   │
│   .kml    │   ArchGDAL.jl   │               │
│    .nc    │  NCDatasets.jl  │               │
│ .parquet  │  GeoParquet.jl  │ GeoParquet.jl │
│   .ply    │    PlyIO.jl     │   PlyIO.jl    │
│   .png    │   ImageIO.jl    │  ImageIO.jl   │
│   .shp    │  Shapefile.jl   │ Shapefile.jl  │
│   .stl    │    GeoIO.jl     │   GeoIO.jl    │
│   .tif    │   ImageIO.jl    │  ImageIO.jl   │
│   .tiff   │   ImageIO.jl    │  ImageIO.jl   │
│   .vti    │   ReadVTK.jl    │  WriteVTK.jl  │
│   .vtp    │   ReadVTK.jl    │  WriteVTK.jl  │
│   .vtr    │   ReadVTK.jl    │  WriteVTK.jl  │
│   .vts    │   ReadVTK.jl    │  WriteVTK.jl  │
│   .vtu    │   ReadVTK.jl    │  WriteVTK.jl  │
└───────────┴─────────────────┴───────────────┘
```

Please read the docstrings for more details.

## Asking for help

If you have any questions, please [contact our community](https://juliaearth.github.io/GeoStats.jl/stable/about/community.html).

[build-img]: https://img.shields.io/github/actions/workflow/status/JuliaEarth/GeoIO.jl/CI.yml?branch=master&style=flat-square
[build-url]: https://github.com/JuliaEarth/GeoIO.jl/actions

[codecov-img]: https://img.shields.io/codecov/c/github/JuliaEarth/GeoIO.jl?style=flat-square
[codecov-url]: https://codecov.io/gh/JuliaEarth/GeoIO.jl
