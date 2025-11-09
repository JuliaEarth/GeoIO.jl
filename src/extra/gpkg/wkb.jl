# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function wkb2geom(io, crs)
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
    wkb2multi(io, crs, zextent, wkbbyteswap)
  else
    # 0 - 3 [Geometry, Point, Linestring, Polygon]
    wkb2single(io, crs, wkbtype, zextent, wkbbyteswap)
  end
end

# read single features from Well-Known Binary IO Buffer and return Concrete Geometry
function wkb2single(io, crs, wkbtype, zextent, bswap)
  if wkbtype == 1
    wkb2point(io, crs, zextent, bswap)
  elseif wkbtype == 2
    wkb2chain(io, crs, zextent, bswap)
  elseif wkbtype == 3
    wkb2poly(io, crs, zextent, bswap)
  end
end

function wkb2point(io, crs, zextent, bswap)
  y, x = bswap(read(io, Float64)), bswap(read(io, Float64))
  if zextent
    z = bswap(read(io, Float64))
    return x, y, z
  end
  Point(crs(x, y))
end

function wkb2chain(io, crs, zextent, bswap)
  npoints = bswap(read(io, UInt32))
  chain = map(1:npoints) do _
    wkb2point(io, crs, zextent, bswap)
  end
  if length(chain) >= 2 && first(chain) != last(chain)
    Rope(chain)
  else
    Ring(chain)
  end
end

function wkb2poly(io, crs, zextent, bswap)
  nrings = bswap(read(io, UInt32))
  rings = map(1:nrings) do _
    wkb2chain(io, crs, zextent, bswap)
  end
  PolyArea(rings)
end

function wkb2multi(io, crs, zextent, bswap)
  ngeoms = bswap(read(io, UInt32))
  geoms = map(1:ngeoms) do _
    wkbbswap = isone(read(io, UInt8)) ? ltoh : ntoh
    wkbtypebits = read(io, UInt32)
    # if 2D+Z the dimensionality flag is present
    if _haszextent(wkbtypebits)
      wkbtype = iszero(wkbtypebits & 0x80000000) ? wkbtypebits - 1000 : wkbtypebits & 0x7FFFFFFF
      wkb2single(io, crs, wkbtype, true, wkbbswap)
    else
      wkb2single(io, crs, wkbtypebits, false, wkbbswap)
    end
  end
  Multi(geoms)
end

function _haszextent(wkbtypebits)
  !iszero(wkbtypebits & 0x80000000) || wkbtypebits > 1000
end