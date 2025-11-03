# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    GeoIO.meshfromwkb(io, crs, wkbtype, haszextent, wkbbyteswap);

Flavors of WKB supported:

- Standard WKB supports two-dimensional geometry, and is a proper subset of both extended WKB and ISO WKB.

## Reading WKB Geometry BLOB

``` julia
    io = IOBuffer(WKBGeometryBLOB)
    # load byte order in order to transport geometry 
    # easily between systems of different endianness
    wkbByteOrder = read(io, UInt8)
    # load simple feature wkb geometry types supported
    wkbGeometryType = read(io, UInt32)
    # wkb points do not have a `numPoints` field 
    if wkbGeometryType != 1
      # load number of geometries in geometry set
      numWkbGeometries = read(io, UInt32)
    end
    # load in WKBGeometry that contain geometry values
    # w/ double precision numbers in the coordinates
    # that are also subject to byte order rules.
    wkbEndianness = isone(wkbByteOrder) ? ltoh : ntoh
    # Note that Julia does not convert the endianness for you.
    wkbGeometryBlob = wkbEndianness(read(io, Vector{UInt8}))
```

- Extended WKB allows applications to optionally add extra dimensions, and optionally embed an SRID
 99-402 was a short-lived extension to SFSQL 1.1 that used a high-bit flag
to indicate the presence of Z coordinates in a WKB geometry.
 When the optional wkbSRID is added to the wkbType, an SRID number is inserted after the wkbType number.
⚠ This optional behaviour is not supported and will likely fail loading this variant

- ISO WKB allows for higher dimensional geometries.
SQL/MM Part 3 and SFSQL 1.2 use offsets of 1000 (Z), 2000 (M) and 3000 (ZM)
⚠ only offsets of 1000 are recognized and supported and will likely fali loading this variant

Other systems like GDAL supports three wkbVariants deviated from the wkbStandard
- wkbVariantOldOgc:: Old-style 99-402
- wkbVariantIso:: SFSQL 1.2 and ISO SQL/MM Part 3 
- wkbVariantPostGIS1::PostGIS 1.X
PostGIS supports a wider range of types (for example, CircularString, CurvePolygon)

GeoIO GeoPackage reader supports wkbGeometryType using the SFSQL 1.2 use offset of 1000 (Z) and SFSQL 1.1 that used a high-bit flag, restricting some optional features

GeoIO GeoPackage writer supports X,Y,Z coordinate offset of 1000 (Z) for wkbGeometryType

## Example

``` julia
    geoms = []
    io = IOBuffer
    for row in wkbGeometryColumn
      wkbbyteswap = isone(read(io, UInt8)) ? ltoh : ntoh
      wkbtype = read(io, UInt32)
      crs = LatLon{WGS84Latest}
      haszextent = false
      push!(geoms, gpkgwkbgeom(io, crs, wkbtype, haszextent, wkbbyteswap))
    end
``` 

"""

# According to https://www.geopackage.org/spec/#r20
# GeoPackage SHALL store feature table geometries with the basic simple feature geometry types.
# Geometry Types (Normative): https://www.geopackage.org/spec140/index.html#geometry_types
# Note: this implementation supports (Core) Geometry Type Codes
function gpkgwkbgeom(io, crs, wkbtype, zextent, bswap)
  if wkbtype > 3
    # 4 - 7 [MultiPoint, MultiLinestring, MultiPolygon, GeometryCollection]
    elems = wkbmulti(io, crs, zextent, bswap)
    Multi(elems)
  else
    # 0 - 3 [Geometry, Point, Linestring, Polygon]
    elem = wkbsimple(io, crs, wkbtype, zextent, bswap)
    elem
  end
end

#-------
# WKB GEOMETRY READER UTILS
#-------

# read simple features from Well-Known Binary IO Buffer and return Concrete Geometry
function wkbsimple(io, crs, wkbtype, zextent, bswap)
  if isequal(wkbtype, 1)
    geom = wkbcoordinate(io, zextent, bswap)
    # return point given coordinates with respect to CRS
    Point(crs(geom...))
  elseif isequal(wkbtype, 2)
    geom = wkblinestring(io, zextent, bswap)
    if length(geom) >= 2 && first(geom) != last(geom)
      # return open polygonal chain from sequence of points w.r.t CRS
      Rope([Point(crs(points...)) for points in geom]...)
    else
      # return closed polygonal chain from sequence of points w.r.t CRS
      Ring([Point(crs(points...)) for points in geom[1:(end - 1)]]...)
    end
  elseif isequal(wkbtype, 3)
    geom = wkbpolygon(io, zextent, bswap)
    rings = map(geom) do ring
      coords = map(ring) do point
        Point(crs(point...))
      end
      Ring(coords)
    end
    outerring = first(rings)
    holes = isone(length(rings)) ? rings[2:end] : Ring[]
    # return polygonal area with outer ring, and optional inner rings
    PolyArea(outerring, holes...)
  end
end

function wkbcoordinate(io, zextent, bswap)
  x, y = bswap(read(io, Float64)), bswap(read(io, Float64))
  if zextent
    z = bswap(read(io, Float64))
    return x, y, z
  end
  x, y
end

function wkblinestring(io, zextent, bswap)
  npoints = bswap(read(io, UInt32))
  points = map(1:npoints) do _
    wkbcoordinate(io, zextent, bswap)
  end
  points
end

function wkbpolygon(io, zextent, bswap)
  nrings = bswap(read(io, UInt32))
  rings = map(1:nrings) do _
    wkblinestring(io, zextent, bswap)
  end
  rings
end

function wkbmulti(io, crs, zextent, bswap)
  ngeoms = bswap(read(io, UInt32))
  geoms = map(1:ngeoms) do _
    wkbbswap = isone(read(io, UInt8)) ? ltoh : ntoh
    wkbtypebits = read(io, UInt32)
    # if 2D+Z the dimensionality flag is present
    if zextent
      if iszero(wkbtypebits & 0x80000000)
        # Extended WKB: wkbtype + 0x80000000 = wkbTypeZ
        wkbtypebits = wkbtypebits & 0x000000F
      elseif wkbtypebits > 1000
        # ISO WKB: wkbType + 1000 = wkbTypeZ
        wkbtypebits = wkbtypebits - 1000
      end
    end
    wkbsimple(io, crs, wkbtypebits, zextent, wkbbswap)
  end
  geoms
end

#-------
# WKB GEOMETRY WRITER UTILS
#-------

function writewkbgeom(io, geom)
  wkbtype = _wkbtype(geom)
  write(io, htol(one(UInt8)))
  write(io, htol(UInt32(wkbtype)))
  _wkbgeom(io, wkbtype, geom)
end


function _wkbtype(geometry)
  if geometry isa Point
    # wkbPoint 
    return 1
  elseif geometry isa Rope || geometry isa Ring
    # wkbLineString
    return 2
  elseif geometry isa PolyArea
    # wkbPolygon
    return 3
  elseif geometry isa Multi
    # wkbMulti
    fg = first(parent(geometry))
    return _wkbtype(fg) + 3
  end
end

function _writewkbsimple(io, wkbtype, geom)
  # wkbPolygon
  if isequal(wkbtype, 3)
    _wkbpolyarea(io, [boundary(geom::PolyArea)])
  elseif isequal(wkbtype, 2)
    coordlist = vertices(geom)
    if typeof(geom) <: Ring
      # wkbLineString[length+1]
      return _wkbchainring(io, coordlist)
    end
    # wkbLineString
    _wkbchainrope(io, coordlist)
  elseif isequal(wkbtype, 1)
    coordinates = CoordRefSystems.raw(coords(geom))
    # wkbPoint
    _wkbpoint(io, coordinates)
  else
    throw(ErrorException("Well-Known Binary Geometry unknown: $wkbtype"))
  end
end

function _wkbgeom(io, wkbtype, geom)
  if wkbtype > 3
    _wkbmulti(io, wkbtype, geom)
  else
    _writewkbsimple(io, wkbtype, geom)
  end
end

function _wkbpoint(io, coordinates)
  write(io, htol(coordinates[2]))
  write(io, htol(coordinates[1]))
  if length(coordinates) == 3
    write(io, htol(coordinates[3]))
  end
end

function _wkbchainrope(io, points)
  write(io, htol(UInt32(length(points))))
  for coordinates in points
    point = CoordRefSystems.raw(coords(coordinates))
    _wkbpoint(io, point)
  end
end

function _wkbchainring(io, points)
  # add a point to close linestring
  write(io, htol(UInt32(length(points) + 1)))
  for point in points
    point = CoordRefSystems.raw(coords(point))
    _wkbpoint(io, point)
  end
  # write a point to close linestring
  _wkbpoint(io, CoordRefSystems.raw(first(points) |> coords))
end

function _wkbpolyarea(io, rings)
  write(io, htol(UInt32(length(rings))))
  for ring in rings
    points = vertices(ring)
    _wkbchainrope(io, points)
  end
end

function _wkbmulti(io, multiwkbtype, geoms)
  # `geoms` is treated as a single [`Geometry`]
  # `parent(geoms)` returns the collection of geometries with the same types
  write(io, htol(UInt32(length(parent(geoms)))))
  for geom in parent(geoms)
    write(io, one(UInt8))
    # wkbGeometryType + 3 = Multi-wkbGeometryType
    write(io, multiwkbtype - 3)
    _writewkbsimple(io, multiwkbtype - 3, geom)
  end
end