# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# --------------------------------------
# Minimum GeoInterface.jl to perform IO
# --------------------------------------

GI.isgeometry(::Geometry) = true

GI.geomtrait(::Point) = GI.PointTrait()
GI.geomtrait(::Segment) = GI.LineTrait()
GI.geomtrait(::Chain) = GI.LineStringTrait()
GI.geomtrait(::Polygon) = GI.PolygonTrait()
GI.geomtrait(::MultiPoint) = GI.MultiPointTrait()
GI.geomtrait(::MultiRope) = GI.MultiLineStringTrait()
GI.geomtrait(::MultiRing) = GI.MultiLineStringTrait()
GI.geomtrait(::MultiPolygon) = GI.MultiPolygonTrait()

GI.ncoord(::GI.PointTrait, p::Point) = CoordRefSystems.ncoords(Meshes.crs(p))
GI.getcoord(::GI.PointTrait, p::Point) = ustrip.(to(p))
GI.getcoord(::GI.PointTrait, p::Point, i) = ustrip(to(p)[i])
GI.getcoord(::GI.PointTrait, p::Point{3,<:LatLon}) = reverse(CoordRefSystems.rawvalues(coords(p)))
GI.getcoord(trait::GI.PointTrait, p::Point{3,<:LatLon}, i) = GI.getcoord(trait, p)[i]

GI.ncoord(::GI.LineTrait, s::Segment) = CoordRefSystems.ncoords(Meshes.crs(s))
GI.ngeom(::GI.LineTrait, s::Segment) = nvertices(s)
GI.getgeom(::GI.LineTrait, s::Segment, i) = vertex(s, i)

GI.ncoord(::GI.LineStringTrait, c::Chain) = CoordRefSystems.ncoords(Meshes.crs(c))
GI.ngeom(::GI.LineStringTrait, c::Chain) = nvertices(c) + isclosed(c)
GI.getgeom(::GI.LineStringTrait, c::Chain, i) = vertex(c, i)

GI.ncoord(::GI.PolygonTrait, p::Polygon) = CoordRefSystems.ncoords(Meshes.crs(p))
GI.ngeom(::GI.PolygonTrait, p::Polygon) = length(rings(p))
GI.getgeom(::GI.PolygonTrait, p::Polygon, i) = rings(p)[i]

GI.ncoord(::GI.AbstractGeometryTrait, m::Multi) = CoordRefSystems.ncoords(Meshes.crs(m))
GI.ngeom(::GI.AbstractGeometryTrait, m::Multi) = length(parent(m))
GI.getgeom(::GI.AbstractGeometryTrait, m::Multi, i) = parent(m)[i]

GI.isfeaturecollection(::Type{<:AbstractGeoTable}) = true
GI.trait(::AbstractGeoTable) = GI.FeatureCollectionTrait()
GI.nfeature(::Any, gtb::AbstractGeoTable) = nrow(gtb)
GI.getfeature(::Any, gtb::AbstractGeoTable, i) = gtb[i, :]

# --------------------------------------
# Convert geometries to Meshes.jl types
# --------------------------------------

getcrs(geom) = getcrs(GI.crs(geom), GI.is3d(geom) ? 3 : 2)
getcrs(code::GFT.EPSG, _) = CoordRefSystems.get(EPSG{GFT.val(code)})
getcrs(_, Dim) = Cartesian{NoDatum,Dim}

topoint(geom, ::Type{<:Cartesian{Datum,2}}) where {Datum} = Point(Cartesian{Datum}(GI.x(geom), GI.y(geom)))

topoint(geom, ::Type{<:Cartesian{Datum,3}}) where {Datum} = Point(Cartesian{Datum}(GI.x(geom), GI.y(geom), GI.z(geom)))

# swap xy to construct LatLon
topoint(geom, ::Type{<:LatLon{Datum}}) where {Datum} = Point(LatLon{Datum}(GI.y(geom), GI.x(geom)))

topoints(geom, CRS) = [topoint(p, CRS) for p in GI.getpoint(geom)]

function tochain(geom, CRS)
  points = topoints(geom, CRS)
  if first(points) == last(points)
    # fix backend issues: https://github.com/JuliaEarth/GeoTables.jl/issues/32
    while first(points) == last(points) && length(points) ≥ 2
      pop!(points)
    end
    Ring(points)
  else
    Rope(points)
  end
end

function topolygon(geom, CRS, fix::Bool)
  # fix backend issues: https://github.com/JuliaEarth/GeoTables.jl/issues/32
  toring(g) = close(tochain(g, CRS))
  outer = toring(GI.getexterior(geom))
  if GI.nhole(geom) == 0
    PolyArea(outer; fix)
  else
    inners = map(toring, GI.gethole(geom))
    PolyArea([outer, inners...]; fix)
  end
end

GI.convert(::Type{Point}, ::GI.PointTrait, geom) = topoint(geom, getcrs(geom))

GI.convert(::Type{Segment}, ::GI.LineTrait, geom) = Segment(topoints(geom, getcrs(geom))...)

GI.convert(::Type{Chain}, ::GI.LineStringTrait, geom) = tochain(geom, getcrs(geom))

GI.convert(::Type{Polygon}, trait::GI.PolygonTrait, geom) = _convert_with_fix(trait, geom, true)

GI.convert(::Type{Multi}, ::GI.MultiPointTrait, geom) = Multi(topoints(geom, getcrs(geom)))

function GI.convert(::Type{Multi}, ::GI.MultiLineStringTrait, geom)
  CRS = getcrs(geom)
  Multi([tochain(g, CRS) for g in GI.getgeom(geom)])
end

GI.convert(::Type{Multi}, trait::GI.MultiPolygonTrait, geom) = _convert_with_fix(trait, geom, true)

_convert_with_fix(::GI.PolygonTrait, geom, fix) = topolygon(geom, getcrs(geom), fix)

function _convert_with_fix(::GI.MultiPolygonTrait, geom, fix)
  CRS = getcrs(geom)
  Multi([topolygon(g, CRS, fix) for g in GI.getgeom(geom)])
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

geom2meshes(geom, fix=true) = geom2meshes(GI.geomtrait(geom), geom, fix)
geom2meshes(trait, geom, fix) = GI.convert(geointerface_geomtype(trait), trait, geom)
geom2meshes(trait::Union{GI.MultiPolygonTrait,GI.PolygonTrait}, geom, fix) = _convert_with_fix(trait, geom, fix)
