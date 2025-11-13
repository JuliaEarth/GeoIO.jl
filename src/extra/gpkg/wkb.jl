# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function wkb2geom(buff, crs)
  byteswap = isone(read(buff, UInt8)) ? ltoh : ntoh
  typebits = read(buff, UInt32)
  # supports wkbGeometryType according to
  # SFSQL 1.1 high-bit flag 0x80000000 (Z)
  # SFSQL 1.2 offset of 1000 (Z)
  sfsql11 = iszero(typebits & 0x80000000)
  sfsql12 = typebits > 1000
  if !sfsql11 || sfsql12
    wkbtype = sfsql11 ? typebits - 1000 : typebits & 0x7FFFFFFF
    zextent = true
  else
    wkbtype = typebits
    zextent = false
  end

  if wkbtype > 3
    # 4 - 7 [MultiPoint, MultiLinestring, MultiPolygon, GeometryCollection]
    wkb2multi(buff, crs, zextent, byteswap)
  else
    # 0 - 3 [Geometry, Point, Linestring, Polygon]
    wkb2single(buff, crs, wkbtype, zextent, byteswap)
  end
end

# read single features from Well-Known Binary IO Buffer and return Concrete Geometry
function wkb2single(buff, crs, wkbtype, zextent, byteswap)
  if wkbtype == 1
    wkb2point(buff, crs, zextent, byteswap)
  elseif wkbtype == 2
    wkb2chain(buff, crs, zextent, byteswap)
  elseif wkbtype == 3
    wkb2poly(buff, crs, zextent, byteswap)
  end
end

function wkb2point(buff, crs, zextent, byteswap)
  y, x = byteswap(read(buff, Float64)), byteswap(read(buff, Float64))
  if zextent
    z = byteswap(read(buff, Float64))
    return x, y, z
  end
  Point(crs(x, y))
end

function wkb2chain(buff, crs, zextent, byteswap)
  npoints = byteswap(read(buff, UInt32))
  chain = map(1:npoints) do _
    wkb2point(buff, crs, zextent, byteswap)
  end
  if length(chain) >= 2 && first(chain) != last(chain)
    Rope(chain)
  else
    Ring(chain)
  end
end

function wkb2poly(buff, crs, zextent, byteswap)
  nrings = byteswap(read(buff, UInt32))
  rings = map(1:nrings) do _
    wkb2chain(buff, crs, zextent, byteswap)
  end
  PolyArea(rings)
end

function wkb2multi(buff, crs, zextent, byteswap)
  ngeoms = byteswap(read(buff, UInt32))
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