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
  npoints = read(buff, UInt32)
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
  nrings = read(buff, UInt32)
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

# ------------------------------------------------------------------
# WKB Writer: converts Meshes.jl geometries to WKB binary format
# ------------------------------------------------------------------

# Z dimension offset for ISO WKB geometry types
_wkbzoffset(CRS) = CoordRefSystems.ncoords(CRS) ≥ 3 ? UInt32(1000) : UInt32(0)

function meshes2wkb(geom)
  buff = IOBuffer()
  meshes2wkb!(buff, geom)
  take!(buff)
end

function meshes2wkb!(buff, geom::Point)
  write(buff, UInt8(1)) # little endian
  wkbtype = UInt32(1) + _wkbzoffset(crs(geom))
  write(buff, htol(wkbtype))
  coords2wkb!(buff, geom)
end

function meshes2wkb!(buff, geom::Ring)
  write(buff, UInt8(1))
  wkbtype = UInt32(2) + _wkbzoffset(crs(geom))
  write(buff, htol(wkbtype))
  n = nvertices(geom)
  write(buff, htol(UInt32(n + 1))) # +1 for closing point
  for p in vertices(geom)
    coords2wkb!(buff, p)
  end
  coords2wkb!(buff, vertex(geom, 1)) # close ring
end

function meshes2wkb!(buff, geom::Rope)
  write(buff, UInt8(1))
  wkbtype = UInt32(2) + _wkbzoffset(crs(geom))
  write(buff, htol(wkbtype))
  n = nvertices(geom)
  write(buff, htol(UInt32(n)))
  for p in vertices(geom)
    coords2wkb!(buff, p)
  end
end

function meshes2wkb!(buff, geom::Polygon)
  write(buff, UInt8(1))
  wkbtype = UInt32(3) + _wkbzoffset(crs(geom))
  write(buff, htol(wkbtype))
  rs = rings(geom)
  write(buff, htol(UInt32(length(rs))))
  for r in rs
    _ring2wkb!(buff, r)
  end
end

function meshes2wkb!(buff, geom::Multi)
  write(buff, UInt8(1))
  gs = parent(geom)
  g1 = first(gs)
  basetype = if g1 isa Point
    UInt32(4)
  elseif g1 isa Chain
    UInt32(5)
  elseif g1 isa Polygon
    UInt32(6)
  else
    error("unsupported Multi geometry type: $(typeof(g1))")
  end
  wkbtype = basetype + _wkbzoffset(crs(geom))
  write(buff, htol(wkbtype))
  write(buff, htol(UInt32(length(gs))))
  for g in gs
    meshes2wkb!(buff, g)
  end
end

# write a ring as part of a polygon (no WKB header, just point count + coords)
function _ring2wkb!(buff, ring)
  n = nvertices(ring)
  write(buff, htol(UInt32(n + 1))) # +1 for closing point
  for p in vertices(ring)
    coords2wkb!(buff, p)
  end
  coords2wkb!(buff, vertex(ring, 1)) # close ring
end

function coords2wkb!(buff, point)
  c = coords(point)
  if c isa LatLon
    write(buff, htol(Float64(ustrip(c.lon))))
    write(buff, htol(Float64(ustrip(c.lat))))
  elseif c isa LatLonAlt
    write(buff, htol(Float64(ustrip(c.lon))))
    write(buff, htol(Float64(ustrip(c.lat))))
    write(buff, htol(Float64(ustrip(c.alt))))
  else
    write(buff, htol(Float64(ustrip(c.x))))
    write(buff, htol(Float64(ustrip(c.y))))
    CoordRefSystems.ncoords(typeof(c)) ≥ 3 && write(buff, htol(Float64(ustrip(c.z))))
  end
end
