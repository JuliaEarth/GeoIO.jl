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

GI.crs(geom::Geometry) = gicrs(crs(geom))

GI.ncoord(::GI.PointTrait, p::Point) = CoordRefSystems.ncoords(crs(p))
GI.getcoord(::GI.PointTrait, p::Point) = ustrip.(raw(coords(p)))
GI.getcoord(trait::GI.PointTrait, p::Point, i) = GI.getcoord(trait, p)[i]

raw(coords::CRS) = coords.x, coords.y
raw(coords::LatLon) = coords.lon, coords.lat

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
GI.crs(gtb::AbstractGeoTable) = gicrs(crs(domain(gtb)))
GI.nfeature(::Any, gtb::AbstractGeoTable) = nrow(gtb)
GI.getfeature(::Any, gtb::AbstractGeoTable, i) = gtb[i, :]

function gicrs(CRS)
  try
    GFT.WellKnownText2(GFT.CRS(), wktstring(CoordRefSystems.code(CRS)))
  catch
    nothing
  end
end

# --------------------------------------
# Convert geometries to Meshes.jl types
# --------------------------------------

crstype(crs::GFT.EPSG, _) = CoordRefSystems.get(EPSG{GFT.val(crs)})
crstype(crs::GFT.WellKnownText, _) = CoordRefSystems.get(GFT.val(crs))
crstype(crs::GFT.WellKnownText2, _) = CoordRefSystems.get(GFT.val(crs))
crstype(crs::GFT.ESRIWellKnownText, _) = CoordRefSystems.get(GFT.val(crs))
crstype(_, geom) = Cartesian{NoDatum,GI.is3d(geom) ? 3 : 2}

function topoint(geom, CRS)
  if CoordRefSystems.ncoords(CRS) == 2
    Point(CRS(GI.x(geom), GI.y(geom)))
  elseif CoordRefSystems.ncoords(CRS) == 3
    Point(CRS(GI.x(geom), GI.y(geom), GI.z(geom)))
  else
    throw(ExceptionError("invalid number of coordinates found in GIS file format"))
  end
end

# flip coordinates in case of LatLon
# clamp latitude to [-90,90] to fix floating-point errors
topoint(geom, ::Type{<:LatLon{Datum}}) where {Datum} = Point(LatLon{Datum}(clamp(GI.y(geom), -90, 90), GI.x(geom)))

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

function topolygon(geom, CRS)
  # fix backend issues: https://github.com/JuliaEarth/GeoTables.jl/issues/32
  toring(g) = close(tochain(g, CRS))
  outer = toring(GI.getexterior(geom))
  if GI.nhole(geom) == 0
    PolyArea(outer)
  else
    inners = map(toring, GI.gethole(geom))
    PolyArea([outer, inners...])
  end
end

togeometry(::GI.PointTrait, geom, crs) = topoint(geom, crstype(crs, geom))

togeometry(::GI.LineTrait, geom, crs) = Segment(topoints(geom, crstype(crs, geom))...)

togeometry(::GI.LineStringTrait, geom, crs) = tochain(geom, crstype(crs, geom))

togeometry(::GI.PolygonTrait, geom, crs) = topolygon(geom, crstype(crs, geom))

togeometry(::GI.MultiPointTrait, geom, crs) = Multi(topoints(geom, crstype(crs, geom)))

function togeometry(::GI.MultiLineStringTrait, geom, crs)
  CRS = crstype(crs, geom)
  Multi([tochain(g, CRS) for g in GI.getgeom(geom)])
end

function togeometry(::GI.MultiPolygonTrait, geom, crs)
  CRS = crstype(crs, geom)
  Multi([topolygon(g, CRS) for g in GI.getgeom(geom)])
end

geom2meshes(geom, crs=GI.crs(geom)) = geom2meshes(GI.geomtrait(geom), geom, crs)
geom2meshes(trait, geom, crs) = togeometry(trait, geom, crs)
