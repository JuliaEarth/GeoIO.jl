# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

abstract type WKBCode end
abstract type WKBFlav{Code} <: WKBCode end
abstract type WKB{Code} <: WKBFlav{Code} end

# "Well-Known" Binary scheme for simple feature geometry.
# The base Geometry class has subclasses for Point, Line, Polygon, and GeometryCollection
# and Support for 3D coordinates
# https://libgeos.org/specifications/wkb/
# https://www.ogc.org/standards/sfa/
abstract type WKBGeometry end
abstract type WKBPoint <: WKBGeometry end
abstract type WKBLineString <: WKBGeometry end
abstract type WKBPolygon <: WKBGeometry end
abstract type WKBMulti <: WKBGeometry end
abstract type WKBMultiPoint <: WKBMulti end
abstract type WKBMultiLineString <: WKBMulti end
abstract type WKBMultiPolygon <: WKBMulti end
abstract type WKBGeometryCollection <: WKBGeometry end
# ISO SQL/MM Part 3: Spatial
# Z-aware types, also representative of the 2.5D extension as per 99-402
# https://lists.osgeo.org/pipermail/postgis-devel/2004-December/000702.html
abstract type WKBGeometryZ <: WKBGeometry end
abstract type WKBPointZ <: WKBGeometryZ end
abstract type WKBLineStringZ <: WKBGeometryZ end
abstract type WKBPolygonZ <: WKBGeometryZ end
abstract type WKBMultiZ <: WKBMulti end
abstract type WKBMultiPointZ <: WKBMultiZ end
abstract type WKBMultiLineStringZ <: WKBMultiZ end
abstract type WKBMultiPolygonZ <: WKBMultiZ end
abstract type WKBGeometryCollectionZ <: WKBGeometryCollection end
# ISO SQL/MM Part 3.
# M-aware types
abstract type WKBPointM <: WKBPointZ end
abstract type WKBLineStringM <: WKBLineStringZ end
abstract type WKBPolygonM <: WKBPolygonZ end
abstract type WKBMultiM <: WKBMultiZ end
abstract type WKBMultiPointM <: WKBMultiM end
abstract type WKBMultiLineStringM <: WKBMultiM end
abstract type WKBMultiPolygonM <: WKBMultiM end
abstract type WKBGeometryCollectionM <: WKBGeometryCollectionZ end
# ISO SQL/MM Part 3.
# ZM-aware types
abstract type WKBPointZM <: WKBPointZ end
abstract type WKBLineStringZM <: WKBLineStringZ end
abstract type WKBPolygonZM <: WKBPolygonZ end
abstract type WKBMultiZM <: WKBMultiZ end
abstract type WKBMultiPointZM <: WKBMultiZM end
abstract type WKBMultiLineStringZM <: WKBMultiZM end
abstract type WKBMultiPolygonZM <: WKBMultiZM end
abstract type WKBGeometryCollectionZM <: WKBGeometryCollectionZ end

function wkbtomeshes(::Type{T}, n, io, crs, wkbbswap) where {T<:WKBPoint}
  if T <: WKBPointZM
    p =
      wkbbswap(read(io, Float64)), wkbbswap(read(io, Float64)), wkbbswap(read(io, Float64)), wkbbswap(read(io, Float64))
  elseif T <: WKBPointM
    p = wkbbswap(read(io, Float64)), wkbbswap(read(io, Float64))
    wkbbswap(read(io, Float64)) # skip aspatial axis, M (Optional Measurement)
  elseif T <: WKBPointZ
    p = wkbbswap(read(io, Float64)), wkbbswap(read(io, Float64)), wkbbswap(read(io, Float64))
  else
    p = wkbbswap(read(io, Float64)), wkbbswap(read(io, Float64))
  end
  Meshes.Point(crs(p...))
end

function wkbtomeshes(::Type{T}, n, io, crs, wkbbswap) where {T<:WKBLineString}
  if T <: WKBLineStringZM
    wkbpoint = WKBPointZM
  elseif T <: WKBLineStringM
    wkbpoint = WKBPointM
  elseif T <: WKBLineStringZ
    wkbpoint = WKBPointZ
  else
    wkbpoint = WKBPoint
  end
  points = map(1:n) do _
    wkbtomeshes(wkbpoint, 1, io, crs, wkbbswap)
  end
  if first(points) != points[n] && length(points) > 2
    return Meshes.Rope(points)
  end
  Meshes.Ring(points[1:(end - 1)])
end

function wkbtomeshes(::Type{WKBPolygon}, n, io, crs, wkbbswap)
  rings = map(1:n) do _
    k = wkbbswap(read(io, UInt32))
    wkbtomeshes(WKBLineString, k, io, crs, wkbbswap)
  end
  outtering = first(rings)
  holes = isone(length(rings)) ? rings[2:end] : Meshes.Ring[]
  Meshes.PolyArea(outtering, holes...)
end

function wkbtomeshes(::Type{T}, n, io, crs, wkbbswap) where {T<:WKBMulti}
  geoms = map(1:n) do _
    wkbbswap = isone(read(io, UInt8)) ? ltoh : ntoh
    wkbtype = meshwkb(WKB{wkbbswap(read(io, UInt32))})
    k = wkbbswap(read(io, UInt32))
    wkbtomeshes(wkbtype, k, io, crs, wkbbswap)
  end
  Meshes.Multi(geoms)
end

function meshestowkb(::Type{T}, io, geom) where {T<:WKBPoint}
  coordvec = CoordRefSystems.raw(coords(geom))
  write(io, htol(coordvec[2]))
  write(io, htol(coordvec[1]))
  if T <: WKBPointZ
    write(io, htol(coordvec[3]))
  end
end

function meshestowkb(::Type{T}, io, geom) where {T<:WKBLineString}
  points = vertices(geom)
  if typeof(geom) <: Meshes.Ring
    write(io, htol(UInt32(length(points) + 1)))
  else
    write(io, UInt32(length(points)))
  end
  if T <: WKBLineStringZ
    wkbpoint = WKBPointZ
  else
    wkbpoint = WKBPoint
  end
  for c in points
    meshestowkb(wkbpoint, io, c)
  end
  if typeof(geom) <: Meshes.Ring
    meshestowkb(wkbpoint, io, first(points))
  end
end

function meshestowkb(::Type{T}, io, geom) where {T<:WKBPolygon}
  rings = [boundary(geom::PolyArea)]
  write(io, htol(UInt32(length(rings))))
  if T <: WKBPolygonZ
    wkbchain = WKBLineStringZ
  else
    wkbchain = WKBLineString
  end
  for ring in rings
    meshestowkb(wkbchain, io, ring)
  end
end

function meshestowkb(::Type{T}, io, geom) where {T<:WKBMulti}
  write(io, htol(UInt32(length(geom |> parent))))
  for g in geom |> parent
    write(io, one(UInt8))
    wkbn = parse(UInt32, ((wkbmesh(T) |> string)[5:(end - 1)]) |> htol)
    write(io, wkbn)
    meshestowkb(meshwkb(WKB{UInt32(wkbn - 3)}), io, g)
  end
end

function meshestowkb(geom::T, io) where {T<:Meshes.Geometry}
  write(io, htol(one(UInt8)))
  meshdims = (paramdim(geom) >= 3)
  if T <: Meshes.PolyArea
    wkbtype = meshdims ? WKBPolygonZ : WKBPolygon
    write(io, parse(UInt32, ((wkbmesh(wkbtype) |> string)[11:(end - 1)]) |> htol))
    meshestowkb(wkbtype, io, geom)
  elseif T <: Meshes.Rope
    wkbtype = meshdims ? WKBLineStringZ : WKBLineString
    write(io, parse(UInt32, ((wkbmesh(wkbtype) |> string)[11:(end - 1)]) |> htol))
    meshestowkb(wkbtype, io, geom)
  elseif T <: Meshes.Ring
    wkbtype = meshdims ? WKBLineStringZ : WKBLineString
    write(io, parse(UInt32, ((wkbmesh(wkbtype) |> string)[11:(end - 1)]) |> htol))
    meshestowkb(wkbtype, io, geom)
  elseif T <: Meshes.Point
    wkbtype = meshdims ? WKBPointZ : WKBPoint
    write(io, parse(UInt32, ((wkbmesh(wkbtype) |> string)[11:(end - 1)]) |> htol))
    meshestowkb(wkbtype, io, geom)
  elseif T <: Meshes.Multi
    wkbtype = multiwkbmesh(typeof(parent(geom)[1]), meshdims)
    write(io, parse(UInt32, ((wkbmesh(wkbtype) |> string)[11:(end - 1)]) |> htol))
    meshestowkb(wkbtype, io, geom)
  else
    throw(ArgumentError("""
            The provided mesh $T is not supported by available WKB Geometry types.
            """))
  end
end

function multiwkbmesh(multi, zextent)
  if multi <: PolyArea
    wkbtype = zextent ? WKBMultiPolygonZ : WKBMultiPolygon
  elseif multi <: Ring
    wkbtype = zextent ? WKBMultiLineStringZ : WKBMultiLineString
  elseif multi <: Rope
    wkbtype = zextent ? WKBMultiLineStringZ : WKBMultiLineString
  elseif multi <: Point
    wkbtype = zextent ? WKBMultiPointZ : WKBMultiPoint
  end
  return wkbtype
end

function meshwkb(code::Type{WKBCode})
  throw(ArgumentError("""
  The provided code $code is not mapped to a WKB Geometry type yet.
  """))
end

function wkbmesh(wkbgeom::Type{WKBGeometry})
  throw(ArgumentError("""
  The provided type $wkbgeom is not mapped to a WKB implementation.
  """))
end

macro wkbcode(Code, WKBArray)
  expr = quote
    meshwkb(::Type{$Code}) = $WKBArray
    wkbmesh(::Type{$WKBArray}) = $Code
  end
  esc(expr)
end

@wkbcode WKB{UInt32(1)} WKBPoint
@wkbcode WKB{UInt32(2)} WKBLineString
@wkbcode WKB{UInt32(3)} WKBPolygon
@wkbcode WKB{UInt32(4)} WKBMultiPoint
@wkbcode WKB{UInt32(5)} WKBMultiLineString
@wkbcode WKB{UInt32(6)} WKBMultiPolygon
@wkbcode WKB{UInt32(7)} WKBGeometryCollection
# @wkbcode WKB{0x80000001} WKBPointZ
# @wkbcode WKB{0x80000002} WKBLineStringZ
# @wkbcode WKB{0x80000003} WKBPolygonZ
# @wkbcode WKB{0x80000004} WKBMultiPointZ
# @wkbcode WKB{0x80000005} WKBMultiLineStringZ
# @wkbcode WKB{0x80000006} WKBMultiPolygonZ
# @wkbcode WKB{0x80000007} WKBGeometryCollectionZ
@wkbcode WKB{UInt32(1001)} WKBPointZ
@wkbcode WKB{UInt32(1002)} WKBLineStringZ
@wkbcode WKB{UInt32(1003)} WKBPolygonZ
@wkbcode WKB{UInt32(1004)} WKBMultiPointZ
@wkbcode WKB{UInt32(1005)} WKBMultiLineStringZ
@wkbcode WKB{UInt32(1006)} WKBMultiPolygonZ
@wkbcode WKB{UInt32(1007)} WKBGeometryCollectionZ
@wkbcode WKB{UInt32(2001)} WKBPointM
@wkbcode WKB{UInt32(2002)} WKBLineStringM
@wkbcode WKB{UInt32(2003)} WKBPolygonM
@wkbcode WKB{UInt32(2004)} WKBMultiPointM
@wkbcode WKB{UInt32(2005)} WKBMultiLineStringM
@wkbcode WKB{UInt32(2006)} WKBMultiPolygonM
@wkbcode WKB{UInt32(2007)} WKBGeometryCollectionM
@wkbcode WKB{UInt32(3001)} WKBPointZM
@wkbcode WKB{UInt32(3002)} WKBLineStringZM
@wkbcode WKB{UInt32(3003)} WKBPolygonZM
@wkbcode WKB{UInt32(3004)} WKBMultiPointZM
@wkbcode WKB{UInt32(3005)} WKBMultiLineStringZM
@wkbcode WKB{UInt32(3006)} WKBMultiPolygonZM
@wkbcode WKB{UInt32(3007)} WKBGeometryCollectionZM