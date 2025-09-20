# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# According to https://www.geopackage.org/spec/#r2
# a GeoPackage should contain "GPKG" in ASCII in 
# "application_id" field of SQLite db header
const GPKG_APPLICATION_ID = Int(0x47504B47)
const GPKG_1_4_VERSION = 10400

function _geomtype(geoms::AbstractVector{<:Geometry})
  if isempty(geoms)
    return "GEOMETRY"
  end
  T = eltype(geoms)

  if T <: Point
    "POINT"
  elseif T <: Rope
    "LINESTRING"
  elseif T <: Ring
    "LINESTRING"
  elseif T <: PolyArea
    "POLYGON"
  elseif T <: Multi
    element_type = eltype(parent(first(geoms)))
    if element_type <: Point
      "MULTIPOINT"
    elseif element_type <: Rope
      "MULTILINESTRING"
    elseif element_type <: PolyArea
      "MULTIPOLYGON"
    end
  else
    "GEOMETRY"
  end
end

include("wkb.jl")

function _sqlitetype(geomtype::AbstractString)
  if geomtype == "POINT"
    WKBPoint
  elseif geomtype == "LINESTRING"
    WKBLineString
  elseif geomtype == "POLYGON"
    WKBPolygon
  elseif geomtype == "MULTIPOINT"
    WKBMultiPoint
  elseif geomtype == "MULTILINESTRING"
    WKBMultiLineString
  elseif geomtype == "MULTIPOLYGON"
    WKBMultiPolygon
  else
    WKBGeometry
  end
end

function SQLite.sqlitetype_(::Type{WKBPoint})
  return "POINT"
end

function SQLite.sqlitetype_(::Type{WKBLineString})
  return "LINESTRING"
end

function SQLite.sqlitetype_(::Type{WKBPolygon})
  return "POLYGON"
end

function SQLite.sqlitetype_(::Type{WKBMultiPoint})
  return "MULTIPOINT"
end

function SQLite.sqlitetype_(::Type{WKBMultiLineString})
  return "MULTILINESTRING"
end

function SQLite.sqlitetype_(::Type{WKBMultiPolygon})
  return "MULTIPOLYGON"
end

function SQLite.sqlitetype_(::Type{WKBGeometry})
  return "GEOMETRY"
end
include("gpkg/read.jl")
include("gpkg/write.jl")
