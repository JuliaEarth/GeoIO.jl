# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# helper type alias
const Met{T} = Quantity{T,u"𝐋",typeof(u"m")}
const Deg{T} = Quantity{T,NoDims,typeof(u"°")}

# return the default length unit if not set
lengthunit(u) = isnothing(u) ? m : u

function asgeotable(table)
  crs = GI.crs(table)
  cols = Tables.columns(table)
  names = Tables.columnnames(cols)
  gcol = geomcolumn(names)
  vars = setdiff(names, [gcol])
  etable = isempty(vars) ? nothing : (; (v => Tables.getcolumn(cols, v) for v in vars)...)
  geoms = Tables.getcolumn(cols, gcol)
  domain = geom2meshes.(geoms, Ref(crs))
  georef(etable, domain)
end

# helper function to find the
# geometry column of a table
function geomcolumn(names)
  snames = string.(names)
  gnames = ["geometry", "geom", "shape"]
  gnames = [gnames; uppercase.(gnames); uppercasefirst.(gnames); [""]]
  select = findfirst(∈(snames), gnames)
  if isnothing(select)
    throw(ErrorException("geometry column not found"))
  else
    Symbol(gnames[select])
  end
end

# add "_" to `name` until it is unique compared to the table `names`
function uniquename(names, name)
  uname = name
  while uname ∈ names
    uname = Symbol(uname, :_)
  end
  uname
end

# make `newnames` unique compared to the table `names`
function uniquenames(names, newnames)
  map(newnames) do name
    uniquename(names, name)
  end
end

# projjson-from-wkt2
function projjsonstring(code; multiline=false)
  # Try the WKT2 conversion path first
  wkt = try
    CoordRefSystems.wkt2(code)
  catch
    # Silently handle WKT2 conversion failures
    # @warn "Failed to get WKT2 representation: $e"
    ""
  end
  
  # Check if WKT seems valid - truncated WKTs can pass basic validation but fail later
  if length(wkt) > 500  # Long WKT strings may be truncated
    # Check for unbalanced quotes or incomplete character sequences which indicate truncation
    if count(c -> c == '"', wkt) % 2 != 0
      # @warn "WKT2 string appears to be truncated (unbalanced quotes)"
      wkt = ""
    end
  end
  
  # Try WKT2 conversion path
  projjson = !isempty(wkt) ? parse_wkt2_to_projjson(wkt) : nothing
  
  # If WKT2 parsing fails, fallback to direct PROJJSON generation
  if projjson === nothing
    # Get the code value and authority
    code_val = try
      CoordRefSystems.code(code)
    catch
      # For type parameters like EPSG{4326}
      if isa(code, Type) && hasfield(typeof(code), :parameters)
        code.parameters[1]
      else
        error("Cannot determine authority from $code")
      end
    end
    
    authority = if occursin("EPSG", string(code)) || nameof(typeof(code)) == :EPSG
      "EPSG"
    elseif occursin("ESRI", string(code)) || nameof(typeof(code)) == :ESRI
      "ESRI"
    else
      error("Cannot determine authority from $code")
    end
    
    # Create a minimal valid PROJJSON structure
    projjson = Dict(
      "\$schema" => "https://proj.org/schemas/v0.5/projjson.schema.json",
      "type" => "GeographicCRS", # Default assumption
      "name" => string(code),
      "datum" => Dict(
        "type" => "GeodeticReferenceFrame",
        "name" => "Unknown"
      ),
      "coordinate_system" => Dict(
        "subtype" => "ellipsoidal",
        "axis" => [
          Dict("name" => "Geodetic longitude", "abbreviation" => "Lon", "direction" => "east", "unit" => "degree"),
          Dict("name" => "Geodetic latitude", "abbreviation" => "Lat", "direction" => "north", "unit" => "degree")
        ]
      ),
      "id" => Dict("authority" => authority, "code" => code_val)
    )
  end
  
  # Format and return the PROJJSON string
  multiline ? JSON3.write(projjson; indent=2) : JSON3.write(projjson)
end

function parse_wkt2_to_projjson(wkt::AbstractString)
  # First, do basic validation on the WKT string
  if isempty(wkt) || length(wkt) < 10  # Minimum reasonable WKT2 length
    # Use debug-level logging instead of warnings for expected validation failures
    # @warn "Empty or too short WKT2 string"
    return nothing
  end
  
  # Check if the string is properly formed (has balanced brackets)
  if count(c -> c == '[', wkt) != count(c -> c == ']', wkt)
    # @warn "Malformed WKT2 string: unbalanced brackets"
    return nothing
  end
  
  # Try to parse the WKT2 string
  try
    crs = CoordRefSystems.get(GFT.WellKnownText2(GFT.CRS(), wkt))
    
    # ❌ Prevent fallback to nonstandard type
    if crs isa CoordRefSystems.Cartesian2D
      # @warn "Cannot convert fallback CRS 'Cartesian2D' to valid PROJJSON."
      return nothing
    end

    # ✅ Identify CRS type
    crstype = if crs isa CoordRefSystems.LatLon
      "GeographicCRS"
    elseif crs isa CoordRefSystems.Mercator || crs isa CoordRefSystems.UTM
      "ProjectedCRS"
    elseif crs isa CoordRefSystems.Vertical
      "VerticalCRS"
    elseif crs isa CoordRefSystems.CRS && hasproperty(crs, :components)
      "CompoundCRS"
    else
      "GeographicCRS"
    end

    # 📦 Optional: extract ellipsoid & datum only when available
    ellipsoid = try
      CoordRefSystems.ellipsoid(crs)
    catch
      nothing
    end
    datum = try
      CoordRefSystems.datum(crs)
    catch
      "Unknown"
    end

    # 📦 Optional: handle compound components
    components =
      crstype == "CompoundCRS" && hasproperty(crs, :components) ?
      begin
        # Safety check for circular references
        comp_refs = getfield(crs, :components)
        if !isempty(comp_refs)
          try
            # Use a maximum recursion depth to prevent infinite loops
            map(comp_refs) do c 
              c_wkt = CoordRefSystems.wkt2(c)
              # Don't process if the component WKT is the same as the parent WKT
              # to avoid circular references
              if c_wkt == wkt
                # @warn "Circular reference detected in compound CRS components"
                nothing
              else
                parse_wkt2_to_projjson(c_wkt)
              end
            end
          catch
            # @warn "Error processing compound CRS components: $e"
            nothing
          end
        else
          nothing
        end
      end : nothing

    return Dict(
      "\$schema" => "https://proj.org/schemas/v0.5/projjson.schema.json",
      "type" => crstype,
      "name" => string(nameof(crs)),
      "datum" => Dict(
        "type" => crstype == "VerticalCRS" ? "VerticalReferenceFrame" : "GeodeticReferenceFrame",
        "name" => string(datum),
        "ellipsoid" =>
          isnothing(ellipsoid) ? nothing :
          Dict(
            "name" => string(nameof(ellipsoid)),
            "semi_major_axis" => CoordRefSystems.majoraxis(ellipsoid),
            "inverse_flattening" => CoordRefSystems.flattening⁻¹(ellipsoid)
          )
      ),
      "coordinate_system" => Dict(
        "subtype" => "ellipsoidal",
        "axis" => [
          Dict("name" => "Geodetic longitude", "abbreviation" => "Lon", "direction" => "east", "unit" => "degree"),
          Dict("name" => "Geodetic latitude", "abbreviation" => "Lat", "direction" => "north", "unit" => "degree")
        ]
      ),
      "id" => Dict("authority" => "EPSG", "code" => try CoordRefSystems.code(crs) catch; 0 end),
      "components" => components
    )
  catch
    # @warn "CoordRefSystems.get failed: $e"
    return nothing
  end
end

spatialref(code) = AG.importUserInput(codestring(code))

codestring(::Type{EPSG{Code}}) where {Code} = "EPSG:$Code"
codestring(::Type{ESRI{Code}}) where {Code} = "ESRI:$Code"

function projjsoncode(json)
  id = json["id"]
  code = Int(id["code"])
  authority = id["authority"]
  if authority == "EPSG"
    EPSG{code}
  elseif authority == "ESRI"
    ESRI{code}
  else
    throw(ArgumentError("unsupported authority '$authority' in ProjJSON"))
  end
end

function projjsoncode(jsonstr::AbstractString)
  json = JSON3.read(jsonstr)
  projjsoncode(json)
end

function projjson(CRS)
  try
    code = CoordRefSystems.code(CRS)
    jsonstr = projjsonstring(code)
    json = JSON3.read(jsonstr, Dict)
    GFT.ProjJSON(json)
  catch
    nothing
  end
end
