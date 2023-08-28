# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# --------------------------------------
# Minimum GeoInterface.jl to perform IO
# --------------------------------------

GI.isgeometry(::Point) = true
GI.isgeometry(::Geometry) = true

GI.geomtrait(::Point) = GI.PointTrait()
GI.geomtrait(::Segment) = GI.LineTrait()
GI.geomtrait(::Chain) = GI.LineStringTrait()
GI.geomtrait(::Polygon) = GI.PolygonTrait()
GI.geomtrait(::Multi{<:Any,<:Any,<:Point}) = GI.MultiPointTrait()
GI.geomtrait(::Multi{<:Any,<:Any,<:Chain}) = GI.MultiLineStringTrait()
GI.geomtrait(::Multi{<:Any,<:Any,<:Polygon}) = GI.MultiPolygonTrait()

GI.ncoord(::GI.PointTrait, p::Point) = embeddim(p)
GI.getcoord(::GI.PointTrait, p::Point) = coordinates(p)
GI.getcoord(::GI.PointTrait, p::Point, i) = coordinates(p)[i]

GI.ncoord(::GI.LineTrait, s::Segment) = embeddim(s)
GI.ngeom(::GI.LineTrait, s::Segment) = nvertices(s)
GI.getgeom(::GI.LineTrait, s::Segment, i) = vertex(s, i)

GI.ncoord(::GI.LineStringTrait, c::Chain) = embeddim(c)
GI.ngeom(::GI.LineStringTrait, c::Chain) = nvertices(c) + isclosed(c)
GI.getgeom(::GI.LineStringTrait, c::Chain, i) = vertex(c, i)

GI.ncoord(::GI.PolygonTrait, p::Polygon) = embeddim(p)
GI.ngeom(::GI.PolygonTrait, p::Polygon) = length(rings(p))
GI.getgeom(::GI.PolygonTrait, p::Polygon, i) = rings(p)[i]

GI.ncoord(::GI.AbstractGeometryTrait, m::Multi) = embeddim(m)
GI.ngeom(::GI.AbstractGeometryTrait, m::Multi) = length(collect(m))
GI.getgeom(::GI.AbstractGeometryTrait, m::Multi, i) = collect(m)[i]

GI.isfeaturecollection(::Data) = true
GI.trait(::Data) = GI.FeatureCollectionTrait()
GI.nfeature(::Any, d::Data) = nitems(d)
GI.getfeature(::Any, d::Data, i) = d[i, :]

# --------------------------------------
# Convert geometries to Meshes.jl types
# --------------------------------------

function topoints(geom, is3d::Bool)
  if is3d
    [Point(GI.x(p), GI.y(p), GI.z(p)) for p in GI.getpoint(geom)]
  else
    [Point(GI.x(p), GI.y(p)) for p in GI.getpoint(geom)]
  end
end

function tochain(geom, is3d::Bool)
  points = topoints(geom, is3d)
  if GI.isclosed(geom)
    # fix backend issues: https://github.com/JuliaEarth/GeoTables.jl/issues/32
    while first(points) == last(points) && length(points) ≥ 2
      pop!(points)
    end
    Ring(points)
  else
    Rope(points)
  end
end

function topolygon(geom, is3d::Bool)
  # fix backend issues: https://github.com/JuliaEarth/GeoTables.jl/issues/32
  toring(g) = close(tochain(g, is3d))
  outer = toring(GI.getexterior(geom))
  if GI.nhole(geom) == 0
    PolyArea(outer)
  else
    inners = map(toring, GI.gethole(geom))
    PolyArea(outer, inners)
  end
end

function GI.convert(::Type{Point}, ::GI.PointTrait, geom)
  if GI.is3d(geom)
    Point(GI.x(geom), GI.y(geom), GI.z(geom))
  else
    Point(GI.x(geom), GI.y(geom))
  end
end

GI.convert(::Type{Segment}, ::GI.LineTrait, geom) = Segment(topoints(geom, GI.is3d(geom))...)

GI.convert(::Type{Chain}, ::GI.LineStringTrait, geom) = tochain(geom, GI.is3d(geom))

GI.convert(::Type{Polygon}, ::GI.PolygonTrait, geom) = topolygon(geom, GI.is3d(geom))

function GI.convert(::Type{Multi}, ::GI.MultiPointTrait, geom)
  Multi(topoints(geom, GI.is3d(geom)))
end

function GI.convert(::Type{Multi}, ::GI.MultiLineStringTrait, geom)
  is3d = GI.is3d(geom)
  Multi([tochain(g, is3d) for g in GI.getgeom(geom)])
end

function GI.convert(::Type{Multi}, ::GI.MultiPolygonTrait, geom)
  is3d = GI.is3d(geom)
  Multi([topolygon(g, is3d) for g in GI.getgeom(geom)])
end

# -----------------------------------------
# GeoInterface.jl approach to call convert
# -----------------------------------------

geointerface_geomtype(::GI.PointTrait) = Point
geointerface_geomtype(::GI.LineTrait) = Segment
geointerface_geomtype(::GI.LineStringTrait) = Chain
geointerface_geomtype(::GI.PolygonTrait) = Polygon
geointerface_geomtype(::GI.MultiPointTrait) = Multi
geointerface_geomtype(::GI.MultiLineStringTrait) = Multi
geointerface_geomtype(::GI.MultiPolygonTrait) = Multi

geom2meshes(geom) = geom2meshes(GI.geomtrait(geom), geom)
geom2meshes(trait, geom) = GI.convert(geointerface_geomtype(trait), trait, geom)
