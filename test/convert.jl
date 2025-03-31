@testset "convert" begin
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

  # ArchGDAL.jl
  ps = [(0, 0), (2.2, 2.2), (0.5, 2)]
  outer = [(0, 0), (2.2, 2.2), (0.5, 2), (0, 0)]
  point = AG.createpoint(1.0, 1.0)
  chain = AG.createlinestring(ps)
  poly = AG.createpolygon(outer)
  multipoint = AG.createmultipoint(ps)
  multichain = AG.createmultilinestring([ps, ps])
  multipoly = AG.createmultipolygon([[outer], [outer]])
  polyarea = PolyArea(outer[begin:(end - 1)])
  @test GeoIO.geom2meshes(point) == Point(1.0, 1.0)
  @test GeoIO.geom2meshes(chain) == Rope(points)
  @test GeoIO.geom2meshes(poly) == polyarea
  @test GeoIO.geom2meshes(multipoint) == Multi(points)
  @test GeoIO.geom2meshes(multichain) == Multi([Rope(points), Rope(points)])
  @test GeoIO.geom2meshes(multipoly) == Multi([polyarea, polyarea])
  # degenerate chain with 2 equal points
  chain = AG.createlinestring([(2.2, 2.2), (2.2, 2.2)])
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

@testset "Data conversion" begin
  # test WKT2 to PROJJSON conversion
  # ---------------------------------------------------
  @testset "WKT2 to PROJJSON" begin
    # Test simple geographic CRS
    wkt2_str = """
    GEOGCRS["WGS 84",
      DATUM["World Geodetic System 1984",
        ELLIPSOID["WGS 84",6378137,298.257223563]],
      CS[ellipsoidal,2],
        AXIS["latitude",north,ORDER[1]],
        AXIS["longitude",east,ORDER[2]],
        ANGLEUNIT["degree",0.0174532925199433]]
    """
    
    projjson_str = wkt2_to_projjson(wkt2_str)
    projjson = JSON3.read(projjson_str)
    
    @test projjson["type"] == "GeographicCRS"
    @test projjson["name"] == "WGS 84"
    @test projjson["datum"]["name"] == "World Geodetic System 1984"
    @test projjson["datum"]["ellipsoid"]["name"] == "WGS 84"
    @test projjson["datum"]["ellipsoid"]["semi_major_axis"] == 6378137
    @test projjson["datum"]["ellipsoid"]["inverse_flattening"] == 298.257223563
    @test projjson["coordinate_system"]["subtype"] == "ellipsoidal"
    @test length(projjson["coordinate_system"]["axis"]) == 2
    
    # Test projected CRS
    wkt2_str = """
    PROJCRS["WGS 84 / UTM zone 31N",
      BASEGEOGCRS["WGS 84",
        DATUM["World Geodetic System 1984",
          ELLIPSOID["WGS 84",6378137,298.257223563]],
        PRIMEM["Greenwich",0]],
      CONVERSION["UTM zone 31N",
        METHOD["Transverse Mercator",
          ID["EPSG",9807]],
        PARAMETER["Latitude of natural origin",0,
          ANGLEUNIT["degree",0.0174532925199433],
          ID["EPSG",8801]],
        PARAMETER["Longitude of natural origin",3,
          ANGLEUNIT["degree",0.0174532925199433],
          ID["EPSG",8802]],
        PARAMETER["Scale factor at natural origin",0.9996,
          SCALEUNIT["unity",1],
          ID["EPSG",8805]],
        PARAMETER["False easting",500000,
          LENGTHUNIT["metre",1],
          ID["EPSG",8806]],
        PARAMETER["False northing",0,
          LENGTHUNIT["metre",1],
          ID["EPSG",8807]]],
      CS[Cartesian,2],
        AXIS["(E)",east,
          ORDER[1],
          LENGTHUNIT["metre",1]],
        AXIS["(N)",north,
          ORDER[2],
          LENGTHUNIT["metre",1]],
      ID["EPSG",32631]]
    """
    
    projjson_str = wkt2_to_projjson(wkt2_str)
    projjson = JSON3.read(projjson_str)
    
    @test projjson["type"] == "ProjectedCRS"
    @test projjson["name"] == "WGS 84 / UTM zone 31N"
    @test projjson["base_crs"]["name"] == "WGS 84"
    @test projjson["conversion"]["name"] == "UTM zone 31N"
    @test projjson["conversion"]["method"]["name"] == "Transverse Mercator"
    @test projjson["id"]["authority"] == "EPSG"
    @test projjson["id"]["code"] == 32631
  end

end
