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

GI.ncoord(::GI.PointTrait, p::Point) = CoordRefSystems.ncoords(crs(p))
GI.getcoord(::GI.PointTrait, p::Point) = _getcoord(coords(p))
GI.getcoord(trait::GI.PointTrait, p::Point, i) = GI.getcoord(trait, p)[i]

_getcoord(coords::CRS) = ustrip(coords.x), ustrip(coords.y)
_getcoord(coords::LatLon) = ustrip(coords.lon), ustrip(coords.lat)

GI.ncoord(::GI.LineTrait, s::Segment) = CoordRefSystems.ncoords(crs(s))
GI.ngeom(::GI.LineTrait, s::Segment) = nvertices(s)
GI.getgeom(::GI.LineTrait, s::Segment, i) = vertex(s, i)

GI.ncoord(::GI.LineStringTrait, c::Chain) = CoordRefSystems.ncoords(crs(c))
GI.ngeom(::GI.LineStringTrait, c::Chain) = nvertices(c) + isclosed(c)
GI.getgeom(::GI.LineStringTrait, c::Chain, i) = vertex(c, i)

GI.ncoord(::GI.PolygonTrait, p::Polygon) = CoordRefSystems.ncoords(crs(p))
GI.ngeom(::GI.PolygonTrait, p::Polygon) = length(rings(p))
GI.getgeom(::GI.PolygonTrait, p::Polygon, i) = rings(p)[i]

GI.ncoord(::GI.AbstractGeometryTrait, m::Multi) = CoordRefSystems.ncoords(crs(m))
GI.ngeom(::GI.AbstractGeometryTrait, m::Multi) = length(parent(m))
GI.getgeom(::GI.AbstractGeometryTrait, m::Multi, i) = parent(m)[i]

GI.isfeaturecollection(::Type{<:AbstractGeoTable}) = true
GI.trait(::AbstractGeoTable) = GI.FeatureCollectionTrait()
GI.nfeature(::Any, gtb::AbstractGeoTable) = nrow(gtb)
GI.getfeature(::Any, gtb::AbstractGeoTable, i) = gtb[i, :]

# --------------------------------------
# Convert geometries to Meshes.jl types
# --------------------------------------

crstype(crs::GFT.EPSG, _) = CoordRefSystems.get(EPSG{GFT.val(crs)})
crstype(crs::GFT.WellKnownText2, _) = CoordRefSystems.get(GFT.val(crs))
crstype(crs::GFT.ESRIWellKnownText, _) = CoordRefSystems.get(GFT.val(crs))
crstype(_, geom) = Cartesian{NoDatum,GI.is3d(geom) ? 3 : 2}

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

function topolygon(geom, CRS, fix)
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

togeometry(::GI.PointTrait, geom, crs, fix) = topoint(geom, crstype(crs, geom))

togeometry(::GI.LineTrait, geom, crs, fix) = Segment(topoints(geom, crstype(crs, geom))...)

togeometry(::GI.LineStringTrait, geom, crs, fix) = tochain(geom, crstype(crs, geom))

togeometry(::GI.PolygonTrait, geom, crs, fix) = topolygon(geom, crstype(crs, geom), fix)

togeometry(::GI.MultiPointTrait, geom, crs, fix) = Multi(topoints(geom, crstype(crs, geom)))

function togeometry(::GI.MultiLineStringTrait, geom, crs, fix)
  CRS = crstype(crs, geom)
  Multi([tochain(g, CRS) for g in GI.getgeom(geom)])
end

function togeometry(::GI.MultiPolygonTrait, geom, crs, fix)
  CRS = crstype(crs, geom)
  Multi([topolygon(g, CRS, fix) for g in GI.getgeom(geom)])
end

geom2meshes(geom, crs=GI.crs(geom), fix=true) = geom2meshes(GI.geomtrait(geom), geom, crs, fix)
geom2meshes(trait, geom, crs, fix) = togeometry(trait, geom, crs, fix)
