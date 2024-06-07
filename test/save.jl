@testset "save" begin
  @testset "Error: saving domains" begin
    @test_throws ArgumentError GeoIO.save("error.vti", CartesianGrid(10, 10))
  end

  @testset "Images" begin
    fname = "image.jpg"
    img1 = joinpath(datadir, fname)
    img2 = joinpath(savedir, fname)
    gtb1 = GeoIO.load(img1)
    GeoIO.save(img2, gtb1)
    gtb2 = GeoIO.load(img2)
    @test gtb1.geometry == gtb2.geometry
    @test psnr_equality()(gtb1.color, gtb2.color)

    # error: image formats only support grids
    file = joinpath(savedir, "error.jpg")
    gtb = georef((; a=rand(10)), rand(Point{2}, 10))
    @test_throws ArgumentError GeoIO.save(file, gtb)
    # error: image formats need data to save
    gtb = georef(nothing, CartesianGrid(2, 2))
    @test_throws ArgumentError GeoIO.save(file, gtb)
    # error: color column not found
    gtb = georef((; a=rand(4)), CartesianGrid(2, 2))
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end

  @testset "STL" begin
    # STL ASCII
    file1 = joinpath(datadir, "tetrahedron_ascii.stl")
    file2 = joinpath(savedir, "tetrahedron_ascii.stl")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1, ascii=true)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    # STL Binary
    file1 = joinpath(datadir, "tetrahedron_bin.stl")
    file2 = joinpath(savedir, "tetrahedron_bin.stl")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    # STL Binary: conversion to Float32
    file1 = joinpath(datadir, "tetrahedron_ascii.stl")
    file2 = joinpath(savedir, "tetrahedron_converted.stl")
    gtb1 = GeoIO.load(file1)
    @test_logs (:warn,) GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test Meshes.lentype(gtb1.geometry) <: Meshes.Met{Float64}
    @test Meshes.lentype(gtb2.geometry) <: Meshes.Met{Float32}

    # error: STL format only supports 3D triangle meshes
    gtb = GeoTable(CartesianGrid(2, 2, 2))
    file = joinpath(savedir, "error.stl")
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end

  @testset "OBJ" begin
    file1 = joinpath(datadir, "tetrahedron.obj")
    file2 = joinpath(savedir, "tetrahedron.obj")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    # error: OBJ format only supports 3D Ngon meshes
    gtb = GeoTable(CartesianGrid(2, 2, 2))
    file = joinpath(savedir, "error.obj")
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end

  @testset "OFF" begin
    file1 = joinpath(datadir, "tetrahedron.off")
    file2 = joinpath(savedir, "tetrahedron.off")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1, color=:COLOR)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    # error: OFF format only supports 3D Ngon meshes
    gtb = GeoTable(CartesianGrid(2, 2, 2))
    file = joinpath(savedir, "error.off")
    @test_throws ArgumentError GeoIO.save(file, gtb)
    # error: color column must be a iterable of colors
    mesh = domain(gtb1)
    gtb = georef((; COLOR=rand(4)), mesh)
    file = joinpath(savedir, "error.off")
    @test_throws ArgumentError GeoIO.save(file, gtb, color="COLOR")
  end

  @testset "MSH" begin
    file1 = joinpath(datadir, "tetrahedron1.msh")
    file2 = joinpath(savedir, "tetrahedron1.msh")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1, vcolumn=:DATA, ecolumn=:DATA)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "tetrahedron2.msh")
    file2 = joinpath(savedir, "tetrahedron2.msh")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1, vcolumn="DATA", ecolumn="DATA")
    gtb2 = GeoIO.load(file2)
    @test isequal(gtb1.DATA, gtb2.DATA)
    @test gtb1.geometry == gtb2.geometry
    vtable1 = values(gtb1, 0)
    vtable2 = values(gtb2, 0)
    @test isequal(vtable1.DATA, vtable2.DATA)

    # error: MSH format only supports 3D meshes
    gtb = GeoTable(CartesianGrid(2, 2))
    file = joinpath(savedir, "error.msh")
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end

  @testset "PLY" begin
    file1 = joinpath(datadir, "beethoven.ply")
    file2 = joinpath(savedir, "beethoven.ply")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    mesh = gtb1.geometry
    gtb1 = georef((; a=rand(nelements(mesh))), mesh)
    file = joinpath(savedir, "plywithdata.ply")
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)
  end

  @testset "CSV" begin
    file1 = joinpath(datadir, "points.csv")
    file2 = joinpath(savedir, "points.csv")
    gtb1 = GeoIO.load(file1, coords=[:x, :y])
    GeoIO.save(file2, gtb1, coords=["x", "y"])
    gtb2 = GeoIO.load(file2, coords=[:x, :y])
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    grid = CartesianGrid(2, 2, 2)
    gtb1 = georef((; a=rand(8)), grid)
    file = joinpath(savedir, "grid.csv")
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file, coords=[:x, :y, :z])
    @test gtb1.a == gtb2.a
    @test nelements(gtb1.geometry) == nelements(gtb2.geometry)
    @test collect(gtb2.geometry) == centroid.(gtb1.geometry)

    # make coordinate names unique
    pset = PointSet(rand(Point{2}, 10))
    gtb1 = georef((x=rand(10), y=rand(10)), pset)
    file = joinpath(savedir, "pset.csv")
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file, coords=[:x_, :y_])
    @test propertynames(gtb1) == propertynames(gtb2)
    @test gtb1.x == gtb2.x
    @test gtb1.y == gtb2.y
    @test gtb1.geometry == gtb2.geometry

    # float format
    x = [0.6895, 0.9878, 0.3654, 0.1813, 0.9138, 0.7121]
    y = [0.3925, 0.4446, 0.6582, 0.3511, 0.1831, 0.8398]
    a = [0.1409, 0.7653, 0.4576, 0.8148, 0.5576, 0.7857]
    pset = PointSet(Point.(x, y))
    gtb1 = georef((; a), pset)
    file = joinpath(savedir, "pset2.csv")
    GeoIO.save(file, gtb1, floatformat="%.2f")
    gtb2 = GeoIO.load(file, coords=[:x, :y])
    xf = [0.69, 0.99, 0.37, 0.18, 0.91, 0.71]
    yf = [0.39, 0.44, 0.66, 0.35, 0.18, 0.84]
    af = [0.14, 0.77, 0.46, 0.81, 0.56, 0.79]
    @test gtb2.a == af
    @test gtb2.geometry == PointSet(Point.(xf, yf))

    # throw: invalid number of coordinate names
    file = joinpath(savedir, "throw.csv")
    gtb = georef((; a=rand(10)), rand(Point{2}, 10))
    @test_throws ArgumentError GeoIO.save(file, gtb, coords=["x", "y", "z"])
    # throw: geometries with more than 3 dimensions
    gtb = georef((; a=rand(10)), rand(Point{4}, 10))
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end

  @testset "VTK" begin
    file1 = ReadVTK.get_example_file("celldata_appended_binary_compressed.vtu", output_directory=savedir)
    file2 = joinpath(savedir, "unstructured.vtu")
    table1 = GeoIO.load(file1)
    GeoIO.save(file2, table1)
    table2 = GeoIO.load(file2)
    @test table1 == table2
    @test values(table1, 0) == values(table2, 0)

    file1 = joinpath(datadir, "spiral.vtp")
    file2 = joinpath(savedir, "spiral.vtp")
    table1 = GeoIO.load(file1)
    GeoIO.save(file2, table1)
    table2 = GeoIO.load(file2)
    @test table1 == table2
    @test values(table1, 0) == values(table2, 0)

    file1 = joinpath(datadir, "rectilinear.vtr")
    file2 = joinpath(savedir, "rectilinear.vtr")
    table1 = GeoIO.load(file1)
    GeoIO.save(file2, table1)
    table2 = GeoIO.load(file2)
    @test table1 == table2
    @test values(table1, 0) == values(table2, 0)

    file1 = joinpath(datadir, "structured.vts")
    file2 = joinpath(savedir, "structured.vts")
    table1 = GeoIO.load(file1)
    GeoIO.save(file2, table1)
    table2 = GeoIO.load(file2)
    @test table1 == table2
    @test values(table1, 0) == values(table2, 0)

    file1 = joinpath(datadir, "imagedata.vti")
    file2 = joinpath(savedir, "imagedata.vti")
    table1 = GeoIO.load(file1)
    GeoIO.save(file2, table1)
    table2 = GeoIO.load(file2)
    @test table1 == table2
    @test values(table1, 0) == values(table2, 0)

    # save cartesian grid in vtr file
    file = joinpath(savedir, "cartesian.vtr")
    table1 = georef((; a=rand(100)), CartesianGrid(10, 10))
    GeoIO.save(file, table1)
    table2 = GeoIO.load(file)
    @test table2.geometry isa RectilinearGrid
    @test nvertices(table2.geometry) == nvertices(table1.geometry)
    @test vertices(table2.geometry) == vertices(table1.geometry)
    @test values(table2) == values(table1)

    # save cartesian grid in vts file
    file = joinpath(savedir, "cartesian.vts")
    table1 = georef((; a=rand(100)), CartesianGrid(10, 10))
    GeoIO.save(file, table1)
    table2 = GeoIO.load(file)
    @test table2.geometry isa StructuredGrid
    @test nvertices(table2.geometry) == nvertices(table1.geometry)
    @test vertices(table2.geometry) == vertices(table1.geometry)
    @test values(table2) == values(table1)

    # save rectilinear grid in vts file
    file = joinpath(savedir, "rectilinear.vts")
    table1 = georef((; a=rand(100)), RectilinearGrid(0:10, 0:10))
    GeoIO.save(file, table1)
    table2 = GeoIO.load(file)
    @test table2.geometry isa StructuredGrid
    @test nvertices(table2.geometry) == nvertices(table1.geometry)
    @test vertices(table2.geometry) == vertices(table1.geometry)
    @test values(table2) == values(table1)

    # save views
    grid = CartesianGrid(10, 10)
    mesh = convert(SimpleMesh, grid)
    rgrid = convert(RectilinearGrid, grid)
    sgrid = convert(StructuredGrid, grid)
    etable = (; a=rand(100))

    gtb = georef(etable, mesh)
    file = joinpath(savedir, "unstructured_view.vtu")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file)
    @test vgtb.a == view(gtb.a, 1:25)
    @test parent(vgtb.geometry) isa SimpleMesh
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    gtb = georef(etable, mesh)
    file = joinpath(savedir, "polydata_view.vtp")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file)
    @test vgtb.a == view(gtb.a, 1:25)
    @test parent(vgtb.geometry) isa SimpleMesh
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    gtb = georef(etable, rgrid)
    file = joinpath(savedir, "rectilinear_view.vtr")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file)
    @test vgtb.a == view(gtb.a, 1:25)
    @test parent(vgtb.geometry) isa RectilinearGrid
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    gtb = georef(etable, sgrid)
    file = joinpath(savedir, "structured_view.vts")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file)
    @test vgtb.a == view(gtb.a, 1:25)
    @test parent(vgtb.geometry) isa StructuredGrid
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    gtb = georef(etable, grid)
    file = joinpath(savedir, "imagedata_view.vti")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file)
    @test vgtb.a == view(gtb.a, 1:25)
    @test parent(vgtb.geometry) isa CartesianGrid
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    # mask column with different name
    gtb = georef((; MASK=rand(100)), grid)
    file = joinpath(savedir, "imagedata_view.vti")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file, mask=:MASK_)
    @test vgtb == GeoIO.load(file, mask="MASK_") # mask as string
    @test vgtb.MASK == view(gtb.MASK, 1:25)
    @test parent(vgtb.geometry) isa CartesianGrid
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    # throw: the vtr format does not support structured grids
    table = GeoIO.load(joinpath(datadir, "structured.vts"))
    @test_throws ErrorException GeoIO.save(joinpath(savedir, "structured.vtr"), table)
  end

  @testset "NetCDF" begin
    file1 = joinpath(datadir, "test.nc")
    file2 = joinpath(savedir, "test.nc")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test isequal(values(gtb1, 0).tempanomaly, values(gtb2, 0).tempanomaly)

    # grids
    grid = CartesianGrid(10, 10)
    rgrid = convert(RectilinearGrid, grid)

    file = joinpath(savedir, "cartesian.nc")
    gtb1 = GeoTable(grid)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test gtb2.geometry isa RectilinearGrid
    @test gtb2.geometry == rgrid

    file = joinpath(savedir, "rectilinear.nc")
    gtb1 = GeoTable(rgrid)
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test gtb2.geometry isa RectilinearGrid
    @test gtb2.geometry == rgrid

    # error: domain is not a grid
    file = joinpath(savedir, "error.nc")
    gtb = georef((; a=rand(10)), rand(Point{2}, 10))
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end

  @testset "GRIB" begin
    # error: saving GRIB files is not supported
    file = joinpath(savedir, "error.grib")
    gtb = georef((; a=rand(4)), CartesianGrid(2, 2))
    @test_throws ErrorException GeoIO.save(file, gtb)
  end

  @testset "GeoTiff" begin
    file1 = joinpath(datadir, "test.tif")
    file2 = joinpath(savedir, "test.tif")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    # error: GeoTiff format only supports 2D grids
    file = joinpath(savedir, "error.tif")
    gtb = georef((; a=rand(8)), CartesianGrid(2, 2, 2))
    @test_throws ArgumentError GeoIO.save(file, gtb)
    # error: GeoTiff format needs data to save
    gtb = georef(nothing, CartesianGrid(2, 2))
    @test_throws ArgumentError GeoIO.save(file, gtb)
    # error: all variables must have the same type
    gtb = georef((a=rand(1:9, 25), b=rand(25)), CartesianGrid(5, 5))
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end
end
