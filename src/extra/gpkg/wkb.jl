# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function wkb2geom(buff, crs)
  # Note: the coordinates are subject to byte order rules specified here
  wkbbyteswap = isone(read(buff, UInt8)) ? ltoh : ntoh
  wkbtypebits = read(buff, UInt32)
  # reader supports wkbGeometryType using the SFSQL 1.2 use offset of 1000 (Z) and SFSQL 1.1 that used a high-bit flag 0x80000000 (Z)
  if !iszero(wkbtypebits & 0x80000000) || wkbtypebits > 1000
    wkbtype = iszero(wkbtypebits & 0x80000000) ? wkbtypebits - 1000 : wkbtypebits & 0x7FFFFFFF
    zextent = true
  else
    wkbtype = wkbtypebits
    zextent = false
  end

  if wkbtype > 3
    # 4 - 7 [MultiPoint, MultiLinestring, MultiPolygon, GeometryCollection]
    wkb2multi(buff, crs, zextent, wkbbyteswap)
  else
    # 0 - 3 [Geometry, Point, Linestring, Polygon]
    wkb2single(buff, crs, wkbtype, zextent, wkbbyteswap)
  end
end

# read single features from Well-Known Binary IO Buffer and return Concrete Geometry
function wkb2single(buff, crs, wkbtype, zextent, bswap)
  if wkbtype == 1
    wkb2point(buff, crs, zextent, bswap)
  elseif wkbtype == 2
    wkb2chain(buff, crs, zextent, bswap)
  elseif wkbtype == 3
    wkb2poly(buff, crs, zextent, bswap)
  end
end

function wkb2point(buff, crs, zextent, bswap)
  y, x = bswap(read(buff, Float64)), bswap(read(buff, Float64))
  if zextent
    z = bswap(read(buff, Float64))
    return x, y, z
  end
  Point(crs(x, y))
end

function wkb2chain(buff, crs, zextent, bswap)
  npoints = bswap(read(buff, UInt32))
  chain = map(1:npoints) do _
    wkb2point(buff, crs, zextent, bswap)
  end
  if length(chain) >= 2 && first(chain) != last(chain)
    Rope(chain)
  else
    Ring(chain)
  end
end

function wkb2poly(buff, crs, zextent, bswap)
  nrings = bswap(read(buff, UInt32))
  rings = map(1:nrings) do _
    wkb2chain(buff, crs, zextent, bswap)
  end
  PolyArea(rings)
end

function wkb2multi(buff, crs, zextent, bswap)
  ngeoms = bswap(read(buff, UInt32))
  geoms = map(1:ngeoms) do _
    wkbbswap = isone(read(buff, UInt8)) ? ltoh : ntoh
    wkbtypebits = read(buff, UInt32)
    # if 2D+Z the dimensionality flag is present
    if zextent
      wkbtype = iszero(wkbtypebits & 0x80000000) ? wkbtypebits - 1000 : wkbtypebits & 0x7FFFFFFF
      wkb2single(buff, crs, wkbtype, true, wkbbswap)
    else
      wkb2single(buff, crs, wkbtypebits, false, wkbbswap)
    end
  end
  Multi(geoms)
end