using GeoIO
using CoordRefSystems
using Test
using JSON3

@testset "WKT2 to PROJJSON conversion" begin
  # Test different CRS types
  
  # Test LatLon with WGS84
  crs = LatLon{WGS84}
  wkt2_str = CoordRefSystems.wkt2(crs)
  projjson_str = GeoIO.wkt2_to_projjson(wkt2_str)
  projjson = JSON3.read(projjson_str)
  
  @test projjson["type"] == "GeographicCRS"
  @test projjson["datum"]["type"] == "GeodeticReferenceFrame"
  @test projjson["datum"]["ellipsoid"]["name"] == "WGS 84"
  @test projjson["coordinate_system"]["subtype"] == "ellipsoidal"
  
  # Test UTM projection
  crs = UTM{32, WGS84, :north}
  wkt2_str = CoordRefSystems.wkt2(crs)
  projjson_str = GeoIO.wkt2_to_projjson(wkt2_str)
  projjson = JSON3.read(projjson_str)
  
  @test projjson["type"] == "ProjectedCRS"
  @test projjson["base_crs"]["type"] == "GeographicCRS"
  @test projjson["conversion"]["method"]["name"] == "Transverse Mercator"
  @test any(p -> p["name"] == "Longitude of natural origin", projjson["conversion"]["parameters"])
  
  # Test with an EPSG code
  crs = EPSG{4326}
  wkt2_str = CoordRefSystems.wkt2(crs)
  projjson_str = GeoIO.wkt2_to_projjson(wkt2_str)
  projjson = JSON3.read(projjson_str)
  
  @test projjson["type"] == "GeographicCRS"
  @test haskey(projjson, "id")
  @test projjson["id"]["authority"] == "EPSG"
  @test projjson["id"]["code"] == 4326
  
  # Test manually constructed WKT2 string
  wkt2_str = """
  GEOGCRS["WGS 84",
    DATUM["World Geodetic System 1984",
      ELLIPSOID["WGS 84",6378137,298.257223563,
        LENGTHUNIT["metre",1]]],
    PRIMEM["Greenwich",0,
      ANGLEUNIT["degree",0.0174532925199433]],
    CS[ellipsoidal,2],
      AXIS["geodetic latitude (Lat)",north,
        ORDER[1],
        ANGLEUNIT["degree",0.0174532925199433]],
      AXIS["geodetic longitude (Lon)",east,
        ORDER[2],
        ANGLEUNIT["degree",0.0174532925199433]],
    USAGE[
      SCOPE["Horizontal component of 3D system."],
      AREA["World."],
      BBOX[-90,-180,90,180]],
    ID["EPSG",4326]]
  """
  
  projjson_str = GeoIO.wkt2_to_projjson(wkt2_str)
  projjson = JSON3.read(projjson_str)
  
  @test projjson["type"] == "GeographicCRS"
  @test projjson["name"] == "WGS 84"
  @test projjson["datum"]["type"] == "GeodeticReferenceFrame"
  @test projjson["datum"]["name"] == "World Geodetic System 1984"
  @test projjson["datum"]["ellipsoid"]["name"] == "WGS 84"
  @test projjson["datum"]["ellipsoid"]["semi_major_axis"] == 6378137
  @test projjson["datum"]["ellipsoid"]["inverse_flattening"] == 298.257223563
  @test projjson["coordinate_system"]["subtype"] == "ellipsoidal"
  @test length(projjson["coordinate_system"]["axis"]) == 2
  @test projjson["id"]["authority"] == "EPSG"
  @test projjson["id"]["code"] == 4326
  
  # Test with compound CRS
  wkt2_str = """
  COMPOUNDCRS["WGS 84 + EGM96 height",
    GEOGCRS["WGS 84",
      DATUM["World Geodetic System 1984",
        ELLIPSOID["WGS 84",6378137,298.257223563]],
      CS[ellipsoidal,2],
        AXIS["latitude",north],
        AXIS["longitude",east],
        ANGLEUNIT["degree",0.0174532925199433]],
    VERTCRS["EGM96 height",
      VDATUM["EGM96 geoid"],
      CS[vertical,1],
        AXIS["gravity-related height (H)",up],
        LENGTHUNIT["metre",1]]]
  """
  
  projjson_str = GeoIO.wkt2_to_projjson(wkt2_str)
  projjson = JSON3.read(projjson_str)
  
  @test projjson["type"] == "CompoundCRS"
  @test projjson["name"] == "WGS 84 + EGM96 height"
  @test length(projjson["components"]) == 2
  @test projjson["components"][1]["type"] == "GeographicCRS"
  @test projjson["components"][2]["type"] == "VerticalCRS"
  @test projjson["components"][2]["name"] == "EGM96 height"
  
  # Test comparison with GDAL
  @testset "Compare with GDAL output" begin
    # Only run if GDAL is available
    try
      crs = EPSG{4326}
      wkt2_str = CoordRefSystems.wkt2(crs)
      our_projjson = GeoIO.wkt2_to_projjson(wkt2_str)
      gdal_projjson = GeoIO.gdal_projjsonstring(crs)
      
      our_json = JSON3.read(our_projjson)
      gdal_json = JSON3.read(gdal_projjson)
      
      # Basic structure should match
      @test our_json["type"] == gdal_json["type"]
      @test haskey(our_json, "datum") == haskey(gdal_json, "datum")
      @test haskey(our_json, "coordinate_system") == haskey(gdal_json, "coordinate_system")
      
      if haskey(our_json, "id") && haskey(gdal_json, "id")
        @test our_json["id"]["authority"] == gdal_json["id"]["authority"]
        @test our_json["id"]["code"] == gdal_json["id"]["code"]
      end
    catch
      @info "GDAL comparison tests skipped (GDAL not available)"
    end
  end
end 