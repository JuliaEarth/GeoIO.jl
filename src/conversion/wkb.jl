# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function wkb2meshes(buff, crs)
  byteswap = isone(read(buff, UInt8)) ? ltoh : ntoh
  wkbtype = read(buff, UInt32)
  # Input variants of WKB supported are standard, extended, and ISO WKB geometry with Z dimensions (M/ZM not supported)
  # SQL/MM Part 3 and SFSQL 1.2 use offsets of 1000 (Z), 2000 (M) and 3000 (ZM) 
  # to indicate the present of higher dimensional coordinates in a WKB geometry
  if wkbtype >= 1001 && wkbtype <= 1007
    # the SFSQL 1.2 offset of 1000 (Z) is present and subtracting a round number of 1000 gives the standard WKB type
    wkbtype -= UInt32(1000)
    # 99-402 was a short-lived extension to SFSQL 1.1 that used a high-bit flag to indicate the presence of Z coordinates in a WKB geometry
    # the high-bit flag 0x80000000 for Z (or 0x40000000 for M) is set and masking it off gives the standard WKB type
  elseif wkbtype > 0x80000000
    # the SFSQL 1.1  high-bit flag 0x80000000 (Z) is present and removing the flag reveals the standard WKB type
    wkbtype -= 0x80000000
  end
  if wkbtype <= 3
    # 0 - 3 [Geometry, Point, Linestring, Polygon]
    wkb2single(buff, crs, wkbtype, byteswap)
  else
    # 4 - 6 [MultiPoint, MultiLinestring, MultiPolygon]
    wkb2multi(buff, crs, byteswap)
  end
end

# read single features from Well-Known Binary IO Buffer and return Concrete Geometry
function wkb2single(buff, crs, wkbtype, byteswap)
  if wkbtype == 1
    wkb2point(buff, crs, byteswap)
  elseif wkbtype == 2
    wkb2chain(buff, crs, byteswap)
  elseif wkbtype == 3
    wkb2poly(buff, crs, byteswap)
  else
    error("Unsupported WKB Geometry Type: $wkbtype")
  end
end

function wkb2point(buff, crs, byteswap)
  coordinates = wkb2coords(buff, crs, byteswap)
  Point(referencecoords(coordinates, crs))
end

function wkb2coords(buff, crs, byteswap)
  if CoordRefSystems.ncoords(crs) == 2
    x = byteswap(read(buff, Float64))
    y = byteswap(read(buff, Float64))
    return (x, y)
  elseif CoordRefSystems.ncoords(crs) == 3
    x = byteswap(read(buff, Float64))
    y = byteswap(read(buff, Float64))
    z = byteswap(read(buff, Float64))
    return (x, y, z)
  end
end

function referencecoords(coordinates, crs)
  if crs <: LatLon
    crs(coordinates[2], coordinates[1])
  elseif crs <: LatLonAlt
    crs(coordinates[2], coordinates[1], coordinates[3])
  else
    crs(coordinates...)
  end
end

function wkb2points(buff, npoints, crs, byteswap)
  map(1:npoints) do _
    coordinates = wkb2coords(buff, crs, byteswap)
    Point(referencecoords(coordinates, crs))
  end
end

function wkb2chain(buff, crs, byteswap)
  npoints = byteswap(read(buff, UInt32))
  chain = wkb2points(buff, npoints, crs, byteswap)
  if length(chain) >= 2 && first(chain) == last(chain)
    Ring(chain[1:(end - 1)])
  elseif length(chain) >= 2
    Rope(chain)
  else
    # single point or closed single point
    Ring(chain)
  end
end

function wkb2poly(buff, crs, byteswap)
  nrings = byteswap(read(buff, UInt32))
  rings = map(1:nrings) do _
    wkb2chain(buff, crs, byteswap)
  end
  PolyArea(rings)
end

function wkb2multi(buff, crs, byteswap)
  ngeoms = byteswap(read(buff, UInt32))
  geoms = map(1:ngeoms) do _
    wkbbswap = isone(read(buff, UInt8)) ? ltoh : ntoh
    wkbtype = read(buff, UInt32)
    # normalize WKB type for single geometries
    (wkbtype >= 4) ? wkb2single(buff, crs, wkbtype-3, wkbbswap) : wkb2single(buff, crs, wkbtype, wkbbswap)
  end
  Multi(geoms)
end