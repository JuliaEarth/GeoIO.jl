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
const ewkbmaskbits = 0x40000000 | 0x80000000

# Requirement 20: GeoPackage SHALL store feature table geometries
#  with the basic simple feature geometry types
# https://www.geopackage.org/spec140/index.html#geometry_types
function gpkgwkbgeom(io, crs, wkbtype, zextent, bswap)
  if wkbtype > 3
    elems = wkbmulti(io, crs, zextent, bswap)
    Multi(elems)
  else
    elem = wkbsimple(io, crs, wkbtype, zextent, bswap)
    elem
  end
end

function wkbsimple(io, crs, wkbtype, zextent, bswap)
  if isequal(wkbtype, 1)
    elem = wkbcoordinate(io, zextent, bswap)
    Point(crs(elem...))
  elseif isequal(wkbtype, 2)
    elem = wkblinestring(io, zextent, bswap)
    if length(elem) >= 2 && first(elem) != last(elem)
      Rope([Point(crs(coords...)) for coords in elem]...)
    else
      Ring([Point(crs(coords...)) for coords in elem[1:(end - 1)]]...)
    end
  elseif isequal(wkbtype, 3)
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

function wkbmulti(io, crs, z, bswap)
  ngeoms = bswap(read(io, UInt32))

  geomcollection = map(1:ngeoms) do _
    wkbbswap = isone(read(io, UInt8)) ? ltoh : ntoh
    wkbtypebits = read(io, UInt32)
    if z
      if iszero(wkbtypebits & ewkbmaskbits)
        wkbtypebits = wkbtypebits & 0x000000F # extended WKB
      else
        wkbtypebits = wkbtypebits - 1000 # ISO WKB
      end
    end
    wkbsimple(io, crs, wkbtypebits, z, wkbbswap)
  end
  geomcollection
end

function _wkbtype(geometry)
  if geometry isa Point
    return 1 # wkbPoint 
  elseif geometry isa Rope || geometry isa Ring
    return 2 # wkbLineString
  elseif geometry isa PolyArea
    return 3 # wkbPolygon
  elseif geometry isa Multi
    fg = first(parent(geometry))
    return _wkbtype(fg) + 3 # wkbMulti
  end
end

function writewkbgeom(io, geom)
  wkbtype = _wkbtype(geom)
  write(io, htol(one(UInt8)))
  write(io, htol(UInt32(wkbtype)))
  _wkbgeom(io, wkbtype, geom)
end

#-------
# WKB GEOMETRY WRITER UTILS
#-------

function _writewkbsimple(io, wkbtype, geom)
  if isequal(wkbtype, 3) # wkbPolygon
    _wkbpolygon(io, [boundary(geom::PolyArea)])
  elseif isequal(wkbtype, 2) # wkbLineString
    coordlist = vertices(geom)
    if typeof(geom) <: Ring
      return _wkbchainring(io, coordlist)
    end
    _wkbchainrope(io, coordlist)
  elseif isequal(wkbtype, 1) # wkbPoint
    coordinates = CoordRefSystems.raw(coords(geom))
    _wkbcoordinates(io, coordinates)
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

function _wkbcoordinates(io, coords)
  write(io, htol(coords[2]))
  write(io, htol(coords[1]))
  if length(coords) == 3
    write(io, htol(coords[3]))
  end
end

function _wkbchainrope(io, coord_list)
  write(io, htol(UInt32(length(coord_list))))
  for n_coords in coord_list
    coordinates = CoordRefSystems.raw(coords(n_coords))
    _wkbcoordinates(io, coordinates)
  end
end

function _wkbchainring(io, coord_list)
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
    _wkbchainring(io, coord_list)
  end
end

function _wkbmulti(io, multiwkbtype, geoms)
  write(io, htol(UInt32(length(parent(geoms)))))
  for sf in parent(geoms)
    write(io, one(UInt8))
    write(io, multiwkbtype - 3)
    _writewkbsimple(io, multiwkbtype - 3, sf)
  end
end