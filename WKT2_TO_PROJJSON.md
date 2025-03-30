# WKT2 to PROJJSON Converter

This document describes the implementation of the WKT2 to PROJJSON converter in GeoIO.jl.

## Background

The GeoParquet specification uses PROJJSON for representing coordinate reference systems, while CoordRefSystems.jl uses OGC WKT2 strings. This implementation provides a way to convert from WKT2 strings to PROJJSON format without relying on external GDAL calls.

## Implementation

The converter is implemented as a combination of:

1. A WKT2 parser that breaks down the WKT2 string into a tree structure
2. A set of conversion functions that transform the WKT2 tree into PROJJSON objects
3. A main entry point `wkt2_to_projjson` that orchestrates the process

### Key Functions

- `parse_wkt_node`: Parses a WKT2 string into a hierarchical structure
- `wkt_node_to_projjson`: Dispatches to specialized conversion functions based on node type
- Specialized converters for different CRS types:
  - `geographic_crs_to_projjson`
  - `projected_crs_to_projjson`
  - `geodetic_crs_to_projjson`
  - `vertical_crs_to_projjson`
  - `compound_crs_to_projjson`
  - `bound_crs_to_projjson`
- Component converters for individual parts:
  - `datum_to_projjson`
  - `datum_ensemble_to_projjson`
  - `ellipsoid_to_projjson`
  - `cs_to_projjson`
  - `axis_to_projjson`
  - `unit_to_projjson`
  - `id_to_projjson`
  - `parameter_to_projjson`
  - `conversion_to_projjson`

### Usage

```julia
using GeoIO
using CoordRefSystems

# Get WKT2 string from CoordRefSystems
crs = EPSG{4326}
wkt2_str = CoordRefSystems.wkt2(crs)

# Convert to PROJJSON
projjson_str = wkt2_to_projjson(wkt2_str)

# You can also use multiline output for better readability
projjson_formatted = wkt2_to_projjson(wkt2_str, true)

# The projjsonstring function now uses this implementation internally
projjson_from_code = projjsonstring(crs)
```

## Examples

### Geographic CRS (WGS 84)

WKT2:
```
GEOGCRS["WGS 84",
  DATUM["World Geodetic System 1984",
    ELLIPSOID["WGS 84",6378137,298.257223563]],
  CS[ellipsoidal,2],
    AXIS["latitude",north],
    AXIS["longitude",east],
    ANGLEUNIT["degree",0.0174532925199433],
  ID["EPSG",4326]]
```

PROJJSON:
```json
{
  "$schema": "https://proj.org/schemas/v0.4/projjson.schema.json",
  "type": "GeographicCRS",
  "name": "WGS 84",
  "datum": {
    "type": "GeodeticReferenceFrame",
    "name": "World Geodetic System 1984",
    "ellipsoid": {
      "name": "WGS 84",
      "semi_major_axis": 6378137,
      "inverse_flattening": 298.257223563
    }
  },
  "coordinate_system": {
    "subtype": "ellipsoidal",
    "axis": [
      {
        "name": "latitude",
        "direction": "north"
      },
      {
        "name": "longitude",
        "direction": "east"
      }
    ]
  },
  "id": {
    "authority": "EPSG",
    "code": 4326
  }
}
```

### Projected CRS (UTM zone 31N)

WKT2:
```
PROJCRS["WGS 84 / UTM zone 31N",
  BASEGEOGCRS["WGS 84",
    DATUM["World Geodetic System 1984",
      ELLIPSOID["WGS 84",6378137,298.257223563]],
    PRIMEM["Greenwich",0]],
  CONVERSION["UTM zone 31N",
    METHOD["Transverse Mercator"],
    PARAMETER["Latitude of natural origin",0],
    PARAMETER["Longitude of natural origin",3],
    PARAMETER["Scale factor at natural origin",0.9996],
    PARAMETER["False easting",500000],
    PARAMETER["False northing",0]],
  CS[Cartesian,2],
    AXIS["(E)",east],
    AXIS["(N)",north],
  ID["EPSG",32631]]
```

PROJJSON:
```json
{
  "$schema": "https://proj.org/schemas/v0.4/projjson.schema.json",
  "type": "ProjectedCRS",
  "name": "WGS 84 / UTM zone 31N",
  "base_crs": {
    "type": "GeographicCRS",
    "name": "WGS 84",
    "datum": {
      "type": "GeodeticReferenceFrame",
      "name": "World Geodetic System 1984",
      "ellipsoid": {
        "name": "WGS 84",
        "semi_major_axis": 6378137,
        "inverse_flattening": 298.257223563
      }
    }
  },
  "conversion": {
    "name": "UTM zone 31N",
    "method": {
      "name": "Transverse Mercator"
    },
    "parameters": [
      {
        "name": "Latitude of natural origin",
        "value": 0
      },
      {
        "name": "Longitude of natural origin",
        "value": 3
      },
      {
        "name": "Scale factor at natural origin",
        "value": 0.9996
      },
      {
        "name": "False easting",
        "value": 500000
      },
      {
        "name": "False northing",
        "value": 0
      }
    ]
  },
  "coordinate_system": {
    "subtype": "cartesian",
    "axis": [
      {
        "name": "(E)",
        "direction": "east"
      },
      {
        "name": "(N)",
        "direction": "north"
      }
    ]
  },
  "id": {
    "authority": "EPSG",
    "code": 32631
  }
}
```

## Limitations and Future Work

- The parser currently supports most common WKT2 elements but may not handle all WKT2 keywords
- Some specialized CRS types (like Engineering CRS, Parametric CRS) are not fully implemented
- Additional validation could be added to ensure the output conforms to the PROJJSON schema
- Performance optimizations could be made for large or complex WKT2 strings 