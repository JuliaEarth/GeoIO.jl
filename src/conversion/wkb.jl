# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# supports standard, extended, and ISO WKB geometry with Z dimensions (M/ZM not supported)
function wkb2meshes(buff, crs)
  # swap bytes of coordinates if necessary
  swapbytes = isone(read(buff, UInt8)) ? ltoh : ntoh

  # retrieve WKB geometry type
  wkbtype = read(buff, UInt32)

  # SQL/MM Part 3 and SFSQL 1.2 use offsets to
  # indicate the presence of higher dimensional
  # coordinates in a WKB geometry
  if wkbtype ≥ 1001 && wkbtype ≤ 1007
    # 1000 (Z)
    wkbtype -= UInt32(1000)
  elseif wkbtype ≥ 2001 && wkbtype ≤ 2007
    # 2000 (M)
    wkbtype -= UInt32(2000)
  elseif wkbtype ≥ 3001 && wkbtype ≤ 3007
    # 3000 (ZM)
    wkbtype -= UInt32(3000)
  elseif wkbtype > 0x80000000
    # 99-402 was a short-lived extension to SFSQL 1.1
    # that used a high-bit flag to indicate the presence
    # of Z coordinates in a WKB geometry
    wkbtype -= 0x80000000
  elseif wkbtype > 0x40000000
    # The M coordinate value allows the application environment
    # to associate some measure with the point values
    # this high-bit flag indicates the presence of M dimension
    wkbtype -= 0x40000000
  end

  # convert WKB geometry type to Meshes.jl type
  if wkbtype == 1
    wkb2point(buff, crs, swapbytes)
  elseif wkbtype == 2
    wkb2chain(buff, crs, swapbytes)
  elseif wkbtype == 3
    wkb2poly(buff, crs, swapbytes)
  elseif 4 ≤ wkbtype ≤ 6 # multi-geometries
    # do a recursive call to read inner geometries
    ngeoms = read(buff, UInt32)
    geoms = [wkb2meshes(buff, crs) for _ in 1:ngeoms]
    Multi(geoms)
  else
    error("Unsupported WKB Geometry Type: $wkbtype")
  end
end

wkb2point(buff, crs, swapbytes) = Point(wkb2coords(buff, crs, swapbytes))

wkb2points(buff, npoints, crs, swapbytes) = [wkb2point(buff, crs, swapbytes) for _ in 1:npoints]

function wkb2chain(buff, crs, swapbytes)
  npoints = swapbytes(read(buff, UInt32))
  points = wkb2points(buff, npoints, crs, swapbytes)
  if first(points) == last(points)
    while first(points) == last(points) && length(points) ≥ 2
      pop!(points)
    end
    Ring(points)
  else
    Rope(points)
  end
end

function wkb2poly(buff, crs, swapbytes)
  nrings = swapbytes(read(buff, UInt32))
  rings = [wkb2chain(buff, crs, swapbytes) for _ in 1:nrings]
  PolyArea(rings)
end

function wkb2coords(buff, crs, swapbytes)
  xyz = ntuple(CoordRefSystems.ncoords(crs)) do _
    swapbytes(read(buff, Float64))
  end
  if crs <: LatLon
    crs(xyz[2], xyz[1])
  elseif crs <: LatLonAlt
    crs(xyz[2], xyz[1], xyz[3])
  else
    crs(xyz...)
  end
end
