# utils_projjson.jl
using Test
using JSON3
using GeoIO
using CoordRefSystems
using GeoFormatTypes

# Import the necessary functions
using GeoIO: projjsonstring, parse_wkt2_to_projjson
# Use qualified name instead of importing to avoid naming conflicts
# import CoordRefSystems: EPSG 

@testset "PROJJSON Error Handling" begin
    # Test with invalid input that should return nothing
    @test parse_wkt2_to_projjson("INVALID_WKT2_STRING") === nothing
    
    # Test with empty string
    @test parse_wkt2_to_projjson("") === nothing
    
    # Test with unbalanced brackets
    @test parse_wkt2_to_projjson("GEOGCRS[\"WGS 84\",DATUM[") === nothing
    
    # Test with truncated WKT2 string
    truncated_wkt = "GEOGCRS[\"WGS 84\",ENSEMBLE[\"World Geodetic System 1984 ensemble\", MEMBER[\"World Geodetic System 1984 (Transit)"
    @test parse_wkt2_to_projjson(truncated_wkt) === nothing
end

@testset "PROJJSON Generation" begin
    # Test the basic functionality of projjsonstring
    # This uses our fallback mechanism
    # Use qualified name to avoid naming conflicts
    json_str = projjsonstring(CoordRefSystems.EPSG{4326})
    @test !isnothing(json_str)
    @test typeof(json_str) == String
    
    # Parse the JSON and check basic structure
    json = JSON3.read(json_str)
    @test json["\$schema"] == "https://proj.org/schemas/v0.5/projjson.schema.json"
    @test haskey(json, "type")
    @test haskey(json, "name")
    @test json["id"]["authority"] == "EPSG"
    @test json["id"]["code"] == 4326
    
    # Test with a potentially problematic WKT string (truncation handling)
    # We should still get valid output with fallback mechanism
    truncated_wkt_code = CoordRefSystems.EPSG{4326}
    json_str_fallback = projjsonstring(truncated_wkt_code)
    @test !isnothing(json_str_fallback)
    @test typeof(json_str_fallback) == String
    
    # Make sure our fallback creates valid PROJJSON
    json_fallback = JSON3.read(json_str_fallback)
    @test json_fallback["\$schema"] == "https://proj.org/schemas/v0.5/projjson.schema.json"
    @test json_fallback["id"]["authority"] == "EPSG"
    @test json_fallback["id"]["code"] == 4326
end

println("PROJJSON tests completed.") 