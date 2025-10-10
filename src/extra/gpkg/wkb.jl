# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    GeoIO.meshfromwkb(io, crs, wkbtype, haszextent, wkbbyteswap);

Flavors of WKB supported:

0. Standard WKB supports two-dimensional geometry, and is a proper subset of both extended WKB and ISO WKB.

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
    # that are also subject to byte order rules
    wkbGeometryBlob = read(io, Vector{UInt8})
```

1. Extended WKB allows applications to optionally add extra dimensions, and optionally embed an SRID
 99-402 was a short-lived extension to SFSQL 1.1 that used a high-bit flag
to indicate the presence of Z coordinates in a WKB geometry.
 When the optional wkbSRID is added to the wkbType, an SRID number is inserted after the wkbType number.
⚠ This optional behaviour is not supported and will likely fail loading this variant

2. ISO WKB allows for higher dimensional geometries.
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
    meshes = []
    io = IOBuffer
    for row in wkbGeometryColumn
      wkbbyteswap = isone(read(io, UInt8)) ? ltoh : ntoh
      wkbtype = wkbGeometryType(read(io, UInt32))
      crs = LatLon{WGS84Latest}
      haszextent = false
      push!(meshes, meshfromwkb(io, crs, wkbtype, haszextent, wkbbyteswap))
    end
``` 

"""
const ewkbmaskbits = 0x40000000 | 0x80000000

@enum wkbGeometryType begin
  wkbUnknown = 0
  wkbPoint = 1
  wkbLineString = 2
  wkbPolygon = 3
  wkbMultiPoint = 4
  wkbMultiLineString = 5
  wkbMultiPolygon = 6
  wkbGeometryCollection = 7
end

# Requirement 20: GeoPackage SHALL store feature table geometries
#  with the basic simple feature geometry types
# https://www.geopackage.org/spec140/index.html#geometry_types
function meshfromwkb(io, crs, wkbtype, zextent, bswap)
  if UInt32(wkbtype) > 3
    elems = wkbmultigeometry(io, crs, zextent, bswap)
    Multi(elems)
  else
    elem = meshfromsf(io, crs, wkbtype, zextent, bswap)
    elem
  end
end

function meshfromsf(io, crs, wkbtype, zextent, bswap)
  if isequal(wkbtype, wkbPoint)
    elem = wkbcoordinate(io, zextent, bswap)
    Point(crs(elem...))
  elseif isequal(wkbtype, wkbLineString)
    elem = wkblinestring(io, zextent, bswap)
    if length(elem) >= 2 && first(elem) != last(elem)
      Rope([Point(crs(coords...)) for coords in elem]...)
    else
      Ring([Point(crs(coords...)) for coords in elem[1:(end - 1)]]...)
    end
  elseif isequal(wkbtype, wkbPolygon)
    elem = wkbpolygon(io, zextent, bswap)
    rings = map(elem) do ring
      coords = map(ring) do point
        Point(crs(point...))
      end
      Ring(coords)
    end

    outerring = first(rings)
    holes = isone(length(rings)) ? rings[2:end] : Ring[]
    PolyArea(outerring, holes...)
  end
end

function wkbcoordinate(io, z, bswap)
  x = bswap(read(io, Float64))
  y = bswap(read(io, Float64))

  if z
    z = bswap(read(io, Float64))
    return x, y, z
  end

  x, y
end

function wkblinestring(io, z, bswap)
  npoints = bswap(read(io, UInt32))

  points = map(1:npoints) do _
    wkbcoordinate(io, z, bswap)
  end
  points
end

function wkbpolygon(io, z, bswap)
  nrings = bswap(read(io, UInt32))

  rings = map(1:nrings) do _
    wkblinestring(io, z, bswap)
  end
  rings
end

function wkbmultigeometry(io, crs, z, bswap)
  ngeoms = bswap(read(io, UInt32))

  geomcollection = map(1:ngeoms) do _
    bswap = isone(read(io, UInt8)) ? ltoh : ntoh
    wkbtypebits = read(io, UInt32)
    if z
      if iszero(wkbtypebits & ewkbmaskbits)
        wkbtype = wkbGeometryType(wkbtypebits)
      else
        wkbtype = wkbGeometryType(wkbtypebits - 1000)
      end
    else
      wkbtype = wkbGeometryType(wkbtypebits)
    end
    meshfromsf(io, crs, wkbtype, z, bswap)
  end
  geomcollection
end

function _wkbtype(geometry)
  if geometry isa Point
    return wkbPoint
  elseif geometry isa Rope || geometry isa Ring
    return wkbLineString
  elseif geometry isa PolyArea
    return wkbPolygon
  elseif geometry isa Multi
    fg = first(parent(geometry))
    return wkbGeometryType(Int(_wkbtype(fg)) + 3)
  else
    return wkbGeometryCollection
  end
end

function writewkbgeom(io, geom)
  wkbtype = _wkbtype(geom)
  write(io, htol(one(UInt8)))
  write(io, htol(UInt32(wkbtype)))
  _wkbgeom(io, wkbtype, geom)
end

function writewkbsf(io, wkbtype, geom)
  if isequal(wkbtype, wkbPolygon)
    _wkbpolygon(io, [boundary(geom::PolyArea)])
  elseif isequal(wkbtype, wkbLineString)
    coordlist = vertices(geom)
    if typeof(geom) <: Ring
      return _wkblinearring(io, coordlist)
    end
    _wkblinestring(io, coordlist)
  elseif isequal(wkbtype, wkbPoint)
    coordinates = CoordRefSystems.raw(coords(geom))
    _wkbcoordinates(io, coordinates)
  else
    throw(ErrorException("Well-Known Binary Geometry not supported: $wkbtype"))
  end
end

function _wkbgeom(io, wkbtype, geom)
  if UInt32(wkbtype) > 3
    _wkbmulti(io, wkbtype, geom)
  else
    writewkbsf(io, wkbtype, geom)
  end
end

function _wkbcoordinates(io, coords)
  write(io, htol(coords[2]))
  write(io, htol(coords[1]))
  if length(coords) == 3
    write(io, htol(coords[3]))
  end
end

function _wkblinestring(io, coord_list)
  write(io, htol(UInt32(length(coord_list))))
  for n_coords in coord_list
    coordinates = CoordRefSystems.raw(coords(n_coords))
    _wkbcoordinates(io, coordinates)
  end
end

function _wkblinearring(io, coord_list)
  write(io, htol(UInt32(length(coord_list) + 1)))
  for n_coords in coord_list
    coordinates = CoordRefSystems.raw(coords(n_coords))
    _wkbcoordinates(io, coordinates)
  end
  _wkbcoordinates(io, CoordRefSystems.raw(first(coord_list) |> coords))
end

function _wkbpolygon(io, rings)
  write(io, htol(UInt32(length(rings))))
  for ring in rings
    coord_list = vertices(ring)
    _wkblinestring(io, coord_list)
  end
end

function _wkbmulti(io, multiwkbtype, geoms)
  write(io, htol(UInt32(length(parent(geoms)))))
  for sf in parent(geoms)
    write(io, one(UInt8))
    write(io, UInt32(multiwkbtype) - 3)
    writewkbsf(io, wkbGeometryType(UInt32(multiwkbtype) - 3), sf)
  end
end