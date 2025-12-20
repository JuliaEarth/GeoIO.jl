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

_wkbtype(::Point) = 0x00000001
_wkbtype(::Chain) = 0x00000002
_wkbtype(::Polygon) = 0x00000003
_wkbtype(m::Multi) = _wkbtype(first(parent(m))) + 0x00000003


function meshes2wkb(buff, geoms)
  wkbtype = _wkbtype(geoms)
  # wkbByteOrder = Little Endian
  write(buff, one(UInt8))
  # wkbGeometryType
  write(buff, UInt32(wkbtype))

  if wkbtype == 1
    point2wkb(buff, geoms)
  elseif wkbtype == 2
    chain2wkb(buff, geoms)
  elseif wkbtype == 3
    poly2wkb(buff, geoms)
  elseif 4 ≤ wkbtype ≤ 6
    # `geoms` is treated as a single [`Geometry`]
    # `parent(geoms)` returns the collection of geometries with the same types
    write(buff, UInt32(length(parent(geoms))))
    foreach(geom -> geom2wkb(buff, geom), parent(geoms))
  else
    throw(ErrorException("Well-Known Binary Geometry unknown: $wkbtype"))
  end
end

function point2wkb(buff, geom)
  crs = typeof(coords(geom))
  xyz = CoordRefSystems.raw(coords(geom))
  if crs <: LatLon
    write(buff, htol(xyz[1]))
    write(buff, htol(xyz[2]))
  elseif crs <: LatLonAlt
    write(buff, htol(xyz[1]))
    write(buff, htol(xyz[2]))
    write(buff, htol(xyz[3]))
  else
    write(buff, htol(xyz[2]))
    write(buff, htol(xyz[1]))
    if length(xyz) == 3
      write(buff, htol(xyz[3]))
    end
  end
end

function chain2wkb(buff, geom)
    npoints = nvertices(geom)
    points = vertices(geom)
    if isclosed(geom)
      write(buff, UInt32(npoints + 1))
      foreach(point -> point2wkb(buff, point), points)
      # close geometry for ring
      point2wkb(buff, first(points))
    else
      write(buff, UInt32(npoints))
      foreach(point -> point2wkb(buff, point), points)
    end
end

function poly2wkb(buff, geom)
    # Linear rings are components of the polygon type, and the byte order
    # and the geometry type are implicit in their location in the polygon structure
    linearrings = rings(geom)
    write(buff, UInt32(length(linearrings)))
    foreach(ring -> chain2wkb(buff, ring), linearrings)
end
