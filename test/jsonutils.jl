# Helper function to validate PROJJSON against schema
# function isvalidprojjson(json::JSON3.Object)
function isvalidprojjson(json)
  schema_path  = joinpath(@__DIR__, "projjson.schema.json")
  my_schema = Schema(JSON3.parsefile(schema_path))
  return isvalid(my_schema, json)
end

json_round_trip(j) = JSON3.read(j |> JSON3.write, Dict)
