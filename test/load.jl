@testset "load" begin
  @testset "Images" begin
    table = GeoIO.load(joinpath(datadir, "image.jpg"))
    @test table.geometry isa TransformedGrid
    @test length(table.color) == length(table.geometry)
  end

  @testset "STL" begin
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron_ascii.stl"))
    @test eltype(gtb.NORMAL) <: Vec{3}
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float64}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4

    gtb = GeoIO.load(joinpath(datadir, "tetrahedron_bin.stl"))
    @test eltype(gtb.NORMAL) <: Vec{3}
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float32}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4
  end

  @testset "OBJ" begin
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron.obj"))
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float64}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4
  end

  @testset "OFF" begin
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron.off"))
    @test eltype(gtb.COLOR) <: RGBA{Float64}
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float64}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4
  end

  @testset "MSH" begin
    gtb = GeoIO.load(joinpath(datadir, "tetrahedron1.msh"))
    @test eltype(gtb.DATA) <: AbstractVector
    @test length(first(gtb.DATA)) == 3
    vtable = values(gtb, 0)
    @test eltype(vtable.DATA) <: Float64
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float64}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4

    gtb = GeoIO.load(joinpath(datadir, "tetrahedron2.msh"))
    @test nonmissingtype(eltype(gtb.DATA)) <: AbstractMatrix
    @test size(first(skipmissing(gtb.DATA))) == (3, 3)
    vtable = values(gtb, 0)
    @test nonmissingtype(eltype(vtable.DATA)) <: AbstractVector
    @test length(first(skipmissing(vtable.DATA))) == 3
    @test gtb.geometry isa SimpleMesh
    @test embeddim(gtb.geometry) == 3
    @test Meshes.lentype(gtb.geometry) <: Meshes.Met{Float64}
    @test eltype(gtb.geometry) <: Triangle
    @test length(gtb.geometry) == 4
  end

  @testset "PLY" begin
    table = GeoIO.load(joinpath(datadir, "beethoven.ply"))
    @test table.geometry isa SimpleMesh
    @test isnothing(values(table, 0))
    @test isnothing(values(table, 1))
    @test isnothing(values(table, 2))
  end

  @testset "CSV" begin
    gtb1 = GeoIO.load(joinpath(datadir, "points.csv"), coords=["x", "y"])
    @test eltype(gtb1.code) <: Integer
    @test eltype(gtb1.name) <: AbstractString
    @test eltype(gtb1.variable) <: Real
    @test gtb1.geometry isa PointSet
    @test length(gtb1.geometry) == 5

    # coordinates with missing values
    gtb2 = GeoIO.load(joinpath(datadir, "missingcoords.csv"), coords=[:x, :y])
    @test eltype(gtb2.code) <: Integer
    @test eltype(gtb2.name) <: AbstractString
    @test eltype(gtb2.variable) <: Real
    @test gtb2.geometry isa PointSet
    @test length(gtb2.geometry) == 3
    @test gtb2[1, :] == gtb1[1, :]
    @test gtb2[2, :] == gtb1[3, :]
    @test gtb2[3, :] == gtb1[5, :]
  end

  @testset "GSLIB" begin
    table = GeoIO.load(joinpath(datadir, "grid.gslib"))
    @test table.geometry isa CartesianGrid
    @test table."Porosity"[1] isa Float64
    @test table."Lithology"[1] isa Float64
    @test table."Water Saturation"[1] isa Float64
    @test isnan(table."Water Saturation"[end])
  end

  @testset "VTK" begin
    file = ReadVTK.get_example_file("celldata_appended_binary_compressed.vtu", output_directory=savedir)
    table = GeoIO.load(file)
    @test table.geometry isa SimpleMesh
    @test eltype(table.cell_ids) <: Int
    @test eltype(table.element_ids) <: Int
    @test eltype(table.levels) <: Int
    @test eltype(table.indicator_amr) <: Float64
    @test eltype(table.indicator_shock_capturing) <: Float64

    # the "spiral.vtp" file was generated from the ReadVTK.jl test code
    # link: https://github.com/JuliaVTK/ReadVTK.jl/blob/main/test/runtests.jl#L309
    file = joinpath(datadir, "spiral.vtp")
    table = GeoIO.load(file)
    @test table.geometry isa SimpleMesh
    @test eltype(table.h) <: Float64
    vtable = values(table, 0)
    @test eltype(vtable.theta) <: Float64

    # the "rectilinear.vtr" file was generated from the WriteVTR.jl test code
    # link: https://github.com/JuliaVTK/WriteVTK.jl/blob/master/test/rectilinear.jl
    file = joinpath(datadir, "rectilinear.vtr")
    table = GeoIO.load(file)
    @test table.geometry isa RectilinearGrid
    @test eltype(table.myCellData) <: Float32
    vtable = values(table, 0)
    @test eltype(vtable.p_values) <: Float32
    @test eltype(vtable.q_values) <: Float32
    @test size(eltype(vtable.myVector)) == (3,)
    @test eltype(eltype(vtable.myVector)) <: Float32
    @test size(eltype(vtable.tensor)) == (3, 3)
    @test eltype(eltype(vtable.tensor)) <: Float32

    # the "structured.vts" file was generated from the WriteVTR.jl test code
    # link: https://github.com/JuliaVTK/WriteVTK.jl/blob/master/test/structured.jl
    file = joinpath(datadir, "structured.vts")
    table = GeoIO.load(file)
    @test table.geometry isa StructuredGrid
    @test eltype(table.myCellData) <: Float32
    vtable = values(table, 0)
    @test eltype(vtable.p_values) <: Float32
    @test eltype(vtable.q_values) <: Float32
    @test size(eltype(vtable.myVector)) == (3,)
    @test eltype(eltype(vtable.myVector)) <: Float32

    # the "imagedata.vti" file was generated from the WriteVTR.jl test code
    # link: https://github.com/JuliaVTK/WriteVTK.jl/blob/master/test/imagedata.jl
    file = joinpath(datadir, "imagedata.vti")
    table = GeoIO.load(file)
    @test table.geometry isa CartesianGrid
    @test eltype(table.myCellData) <: Float32
    vtable = values(table, 0)
    @test size(eltype(vtable.myVector)) == (2,)
    @test eltype(eltype(vtable.myVector)) <: Float32
  end

  @testset "NetCDF" begin
    # the "test.nc" file is a slice of the "gistemp250_GHCNv4.nc" file from NASA
    # link: https://data.giss.nasa.gov/pub/gistemp/gistemp250_GHCNv4.nc.gz
    file = joinpath(datadir, "test.nc")
    table = GeoIO.load(file)
    @test table.geometry isa RectilinearGrid
    @test isnothing(values(table))
    vtable = values(table, 0)
    @test length(vtable.tempanomaly) == nvertices(table.geometry)
    @test length(first(vtable.tempanomaly)) == 100

    # the "test_kw.nc" file is a slice of the "gistemp250_GHCNv4.nc" file from NASA
    # link: https://data.giss.nasa.gov/pub/gistemp/gistemp250_GHCNv4.nc.gz
    file = joinpath(datadir, "test_kw.nc")
    table = GeoIO.load(file, x="lon_x", y="lat_y", t="time_t")
    @test table.geometry isa RectilinearGrid
    @test isnothing(values(table))
    vtable = values(table, 0)
    @test length(vtable.tempanomaly) == nvertices(table.geometry)
    @test length(first(vtable.tempanomaly)) == 100

    # timeless vertex data
    file = joinpath(datadir, "test_data.nc")
    table = GeoIO.load(file)
    @test table.geometry isa RectilinearGrid
    @test isnothing(values(table))
    vtable = values(table, 0)
    @test length(vtable.tempanomaly) == nvertices(table.geometry)
    @test length(first(vtable.tempanomaly)) == 100
    @test length(vtable.data) == nvertices(table.geometry)
    @test eltype(vtable.data) <: Float64
  end

  @testset "GRIB" begin
    # the "regular_gg_ml.grib" file is a test file from the GRIBDatasets.jl package
    # link: https://github.com/JuliaGeo/GRIBDatasets.jl/blob/main/test/sample-data/regular_gg_ml.grib
    file = joinpath(datadir, "regular_gg_ml.grib")
    if Sys.iswindows()
      @test_throws ErrorException GeoIO.load(file)
    else
      table = GeoIO.load(file)
      @test table.geometry isa RectilinearGrid
      @test isnothing(values(table))
      @test isnothing(values(table, 0))
    end
  end

  @testset "GeoTiff" begin
    file = joinpath(datadir, "test.tif")
    gtb = GeoIO.load(file)
    @test propertynames(gtb) == [:BAND1, :BAND2, :BAND3, :geometry]
    @test eltype(gtb.BAND1) <: UInt8
    @test eltype(gtb.BAND2) <: UInt8
    @test eltype(gtb.BAND3) <: UInt8
    @test gtb.geometry isa TransformedGrid
    @test size(gtb.geometry) == (100, 100)
  end

  @testset "Shapefile" begin
    table = GeoIO.load(joinpath(datadir, "points.shp"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa PointSet
    @test table.geometry[1] isa Point

    table = GeoIO.load(joinpath(datadir, "lines.shp"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa Multi
    @test parent(table.geometry[1])[1] isa Chain

    table = GeoIO.load(joinpath(datadir, "polygons.shp"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa Multi
    @test parent(table.geometry[1])[1] isa PolyArea

    table = GeoIO.load(joinpath(datadir, "path.shp"))
    @test Tables.schema(table).names == (:ZONA, :geometry)
    @test length(table.geometry) == 6
    @test table.ZONA == ["PA 150", "BR 364", "BR 163", "BR 230", "BR 010", "Estuarina PA"]
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa Multi

    table = GeoIO.load(joinpath(datadir, "zone.shp"))
    @test Tables.schema(table).names == (:PERIMETER, :ACRES, :MACROZONA, :Hectares, :area_m2, :geometry)
    @test length(table.geometry) == 4
    @test table.PERIMETER == [5.850803650776888e6, 9.539471535859613e6, 1.01743436941e7, 7.096124186552936e6]
    @test table.ACRES == [3.23144676827e7, 2.50593712407e8, 2.75528426573e8, 1.61293042687e8]
    @test table.MACROZONA == ["Estuario", "Fronteiras Antigas", "Fronteiras Intermediarias", "Fronteiras Novas"]
    @test table.Hectares == [1.30772011078e7, 1.01411677447e8, 1.11502398263e8, 6.52729785685e7]
    @test table.area_m2 == [1.30772011078e11, 1.01411677447e12, 1.11502398263e12, 6.52729785685e11]
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa Multi

    table = GeoIO.load(joinpath(datadir, "land.shp"))
    @test Tables.schema(table).names == (:featurecla, :scalerank, :min_zoom, :geometry)
    @test length(table.geometry) == 127
    @test all(==("Land"), table.featurecla)
    @test all(∈([0, 1]), table.scalerank)
    @test all(∈([0.0, 0.5, 1.0, 1.5]), table.min_zoom)
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa Multi

    # https://github.com/JuliaEarth/GeoIO.jl/issues/32
    @test GeoIO.load(joinpath(datadir, "issue32.shp")) isa AbstractGeoTable
    @test GeoIO.load(joinpath(datadir, "lines.shp")) isa AbstractGeoTable
  end

  @testset "GeoJSON" begin
    table = GeoIO.load(joinpath(datadir, "points.geojson"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa PointSet
    @test table.geometry[1] isa Point

    table = GeoIO.load(joinpath(datadir, "lines.geojson"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa Chain

    table = GeoIO.load(joinpath(datadir, "polygons.geojson"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa PolyArea

    @test GeoIO.load(joinpath(datadir, "lines.geojson")) isa AbstractGeoTable
  end

  @testset "KML" begin
    table = GeoIO.load(joinpath(datadir, "field.kml"))
    @test length(table.geometry) == 4
    @test table.Name[1] isa String
    @test table.Description[1] isa String
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa PolyArea
  end

  @testset "GeoPackage" begin
    table = GeoIO.load(joinpath(datadir, "points.gpkg"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa PointSet
    @test table.geometry[1] isa Point

    table = GeoIO.load(joinpath(datadir, "lines.gpkg"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa Chain

    table = GeoIO.load(joinpath(datadir, "polygons.gpkg"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa PolyArea

    @test GeoIO.load(joinpath(datadir, "lines.gpkg")) isa AbstractGeoTable
  end

  @testset "GeoParquet" begin
    table = GeoIO.load(joinpath(datadir, "points.parquet"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa PointSet
    @test table.geometry[1] isa Point

    table = GeoIO.load(joinpath(datadir, "lines.parquet"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa Chain

    table = GeoIO.load(joinpath(datadir, "polygons.parquet"))
    @test length(table.geometry) == 5
    @test table.code[1] isa Integer
    @test table.name[1] isa String
    @test table.variable[1] isa Real
    @test table.geometry isa GeometrySet
    @test table.geometry[1] isa PolyArea

    @test GeoIO.load(joinpath(datadir, "lines.parquet")) isa AbstractGeoTable
  end
end
