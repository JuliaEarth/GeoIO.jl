# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function gpkgwkbgeom(io, crs)
  # Note: the coordinates are subject to byte order rules specified here
  wkbbyteswap = isone(read(io, UInt8)) ? ltoh : ntoh
  wkbtypebits = read(io, UInt32)
  # reader supports wkbGeometryType using the SFSQL 1.2 use offset of 1000 (Z) and SFSQL 1.1 that used a high-bit flag 0x80000000 (Z)
  if _haszextent(wkbtypebits)
    wkbtype = iszero(wkbtypebits & 0x80000000) ? wkbtypebits - 1000 : wkbtypebits & 0x7FFFFFFF
    zextent = true
  else
    wkbtype = wkbtypebits
    zextent = false
  end

  if wkbtype > 3
    # 4 - 7 [MultiPoint, MultiLinestring, MultiPolygon, GeometryCollection]
    geoms = wkbmulti(io, crs, zextent, wkbbyteswap)
    Multi(geoms)
  else
    # 0 - 3 [Geometry, Point, Linestring, Polygon]
    wkbsingle(io, crs, wkbtype, zextent, wkbbyteswap)
  end
end

# read single features from Well-Known Binary IO Buffer and return Concrete Geometry
function wkbsingle(io, crs, wkbtype, zextent, bswap)
  if wkbtype == 1
    geom = wkbcoordinate(io, zextent, bswap)

    # return point given coordinates
    Point(crs(geom...))
  elseif wkbtype == 2
    geom = wkblinestring(io, zextent, bswap)
    if length(geom) >= 2 && first(geom) != last(geom)

      # return open polygonal chain from sequence of points
      Rope([Point(crs(points...)) for points in geom]...)
    else

      # return closed polygonal chain from sequence of points
      Ring([Point(crs(points...)) for points in geom[1:(end - 1)]]...)
    end
  elseif wkbtype == 3
    geom = wkbpolygon(io, zextent, bswap)
    rings = map(geom) do ring
      coords = map(ring) do point
        Point(crs(point...))
      end
      Ring(coords)
    end

    # return a polygonal area from rings
    PolyArea(rings)
  end
end

function wkbcoordinate(io, zextent, bswap)
  y, x = bswap(read(io, Float64)), bswap(read(io, Float64))
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
    if _haszextent(wkbtypebits)
      wkbtype = iszero(wkbtypebits & 0x80000000) ? wkbtypebits - 1000 : wkbtypebits & 0x7FFFFFFF
      zextent = true
    else
      zextent = false
    end
    # read single geometry from Well-Known Binary IO Buffer
    wkbsingle(io, crs, wkbtype, zextent, wkbbswap)
  end
  geoms
end

function _haszextent(wkbtypebits)
  if !iszero(wkbtypebits & 0x80000000) || wkbtypebits > 1000
    return true
  end
  return false
end