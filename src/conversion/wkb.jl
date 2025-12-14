# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function meshes2wkb(io, geom)
  wkbtype = _wkbtype(geom)
  write(io, htol(one(UInt8)))
  write(io, htol(UInt32(wkbtype)))
  geom2wkb(io, wkbtype, geom)
end


function _wkbtype(geometry)
  if geometry isa Point
    # wkbPoint 
    return 1
  elseif geometry isa Rope || geometry isa Ring
    # wkbLineString
    return 2
  elseif geometry isa PolyArea
    # wkbPolygon
    return 3
  elseif geometry isa Multi
    # wkbMulti
    fg = first(parent(geometry))
    return _wkbtype(fg) + 3
  end
end

function geom2wkb(io, wkbtype, geom)
  if wkbtype > 3
    multi2wkb(io, wkbtype, geom)
  else
    single2wkb(io, wkbtype, geom)
  end
end


function single2wkb(io, wkbtype, geom)
  # wkbPolygon
  if wkbtype == 3
    poly2wkb(io, [boundary(geom::PolyArea)])
  elseif wkbtype == 2
    coordlist = vertices(geom)
    if typeof(geom) <: Ring
      # wkbLineString[length+1]
      return chainring2wkb(io, coordlist)
    end
    # wkbLineString
    chainrope2wkb(io, coordlist)
  elseif wkbtype == 1
    # wkbPoint
    point2wkb(io, geom)
  else
    throw(ErrorException("Well-Known Binary Geometry unknown: $wkbtype"))
  end
end

function point2wkb(io, geom)
  coordinates = CoordRefSystems.raw(coords(geom))
  if typeof(geom) <: LatLon
    write(io, htol(coordinates[2]))
    write(io, htol(coordinates[1]))
  elseif typeof(geom) <: LatLonAlt
    write(io, htol(coordinates[2]))
    write(io, htol(coordinates[1]))
    write(io, htol(coordinates[3]))
  else
    write(io, htol(coordinates[1]))
    write(io, htol(coordinates[2]))
    if length(coordinates) == 3
      write(io, htol(coordinates[3]))
    end
  end
end

function chainrope2wkb(io, rope)
  write(io, htol(UInt32(length(rope))))
  for point in rope
    point2wkb(io, point)
  end
end

function chainring2wkb(io, ring)
  # add a point to close linestring
  write(io, htol(UInt32(length(ring) + 1)))
  for point in ring
    point2wkb(io, point)
  end
  # write a point to close linestring
  point2wkb(io, first(ring))
end

function poly2wkb(io, rings)
  write(io, htol(UInt32(length(rings))))
  for ring in rings
    points = vertices(ring)
    chainrope2wkb(io, points)
  end
end

function multi2wkb(io, multiwkbtype, geoms)
  # `geoms` is treated as a single [`Geometry`]
  # `parent(geoms)` returns the collection of geometries with the same types
  write(io, htol(UInt32(length(parent(geoms)))))
  for geom in parent(geoms)
    write(io, one(UInt8))
    # wkbGeometryType + 3 = Multi-wkbGeometryType
    write(io, multiwkbtype - 3)
    single2wkb(io, multiwkbtype - 3, geom)
  end
end