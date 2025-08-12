@testset "Geometry conversion" begin
  points = Point.([(0, 0), (2.2, 2.2), (0.5, 2)])
  outer = Point.([(0, 0), (2.2, 2.2), (0.5, 2), (0, 0)])

  # GI functions
  @test GI.ngeom(Segment(points[1], points[2])) == 2
  @test GI.ngeom(Rope(points)) == 3
  @test GI.ngeom(Ring(points)) == 4
  @test GI.ngeom(PolyArea(points)) == 1
  @test GI.ngeom(Multi(points)) == 3
  @test GI.ngeom(Multi([Rope(points), Rope(points)])) == 2
  @test GI.ngeom(Multi([PolyArea(points), PolyArea(points)])) == 2

  # Shapefile.jl
  ps = [SHP.Point(0, 0), SHP.Point(2.2, 2.2), SHP.Point(0.5, 2)]
  exterior = [SHP.Point(0, 0), SHP.Point(2.2, 2.2), SHP.Point(0.5, 2), SHP.Point(0, 0)]
  box = SHP.Rect(0.0, 0.0, 2.2, 2.2)
  point = SHP.Point(1.0, 1.0)
  chain = SHP.LineString{SHP.Point}(view(ps, 1:3))
  poly = SHP.SubPolygon([SHP.LinearRing{SHP.Point}(view(exterior, 1:4))])
  multipoint = SHP.MultiPoint(box, ps)
  multichain = SHP.Polyline(box, [0, 3], repeat(ps, 2))
  multipoly = SHP.Polygon(box, [0, 4], repeat(exterior, 2))
  @test GeoIO.geom2meshes(point) == Point(1.0, 1.0)
  @test GeoIO.geom2meshes(chain) == Rope(points)
  @test GeoIO.geom2meshes(poly) == PolyArea(points)
  @test GeoIO.geom2meshes(multipoint) == Multi(points)
  @test GeoIO.geom2meshes(multichain) == Multi([Rope(points), Rope(points)])
  @test GeoIO.geom2meshes(multipoly) == Multi([PolyArea(points), PolyArea(points)])
  # degenerate chain with 2 equal points
  ps = [SHP.Point(2.2, 2.2), SHP.Point(2.2, 2.2)]
  chain = SHP.LineString{SHP.Point}(view(ps, 1:2))
  @test GeoIO.geom2meshes(chain) == Ring((2.2, 2.2))


  # GeoJSON.jl
  points = Point.([LatLon(0.0f0, 0.0f0), LatLon(2.2f0, 2.2f0), LatLon(2.0f0, 0.5f0)])
  outer = Point.([LatLon(0.0f0, 0.0f0), LatLon(2.2f0, 2.2f0), LatLon(2.0f0, 0.5f0)])
  point = GJS.read("""{"type":"Point","coordinates":[1,1]}""")
  chain = GJS.read("""{"type":"LineString","coordinates":[[0,0],[2.2,2.2],[0.5,2]]}""")
  poly = GJS.read("""{"type":"Polygon","coordinates":[[[0,0],[2.2,2.2],[0.5,2],[0,0]]]}""")
  multipoint = GJS.read("""{"type":"MultiPoint","coordinates":[[0,0],[2.2,2.2],[0.5,2]]}""")
  multichain =
    GJS.read("""{"type":"MultiLineString","coordinates":[[[0,0],[2.2,2.2],[0.5,2]],[[0,0],[2.2,2.2],[0.5,2]]]}""")
  multipoly = GJS.read(
    """{"type":"MultiPolygon","coordinates":[[[[0,0],[2.2,2.2],[0.5,2],[0,0]]],[[[0,0],[2.2,2.2],[0.5,2],[0,0]]]]}"""
  )
  @test GeoIO.geom2meshes(point) == Point(LatLon(1.0f0, 1.0f0))
  @test GeoIO.geom2meshes(chain) == Rope(points)
  @test GeoIO.geom2meshes(poly) == PolyArea(outer)
  @test GeoIO.geom2meshes(multipoint) == Multi(points)
  @test GeoIO.geom2meshes(multichain) == Multi([Rope(points), Rope(points)])
  @test GeoIO.geom2meshes(multipoly) == Multi([PolyArea(outer), PolyArea(outer)])
  # degenerate chain with 2 equal points
  chain = GJS.read("""{"type":"LineString","coordinates":[[2.2,2.2],[2.2,2.2]]}""")
  @test GeoIO.geom2meshes(chain) == Ring(Point(LatLon(2.2f0, 2.2f0)))
end
