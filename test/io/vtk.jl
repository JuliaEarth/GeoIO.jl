@testset "VTK" begin
  @testset "load" begin
    file = ReadVTK.get_example_file("celldata_appended_binary_compressed.vtu", output_directory=savedir)
    gtb = GeoIO.load(file)
    @test gtb.geometry isa SimpleMesh
    @test eltype(gtb.cell_ids) <: Int
    @test eltype(gtb.element_ids) <: Int
    @test eltype(gtb.levels) <: Int
    @test eltype(gtb.indicator_amr) <: Float64
    @test eltype(gtb.indicator_shock_capturing) <: Float64

    # the "spiral.vtp" file was generated from the ReadVTK.jl test code
    # link: https://github.com/JuliaVTK/ReadVTK.jl/blob/main/test/runtests.jl#L309
    file = joinpath(datadir, "spiral.vtp")
    gtb = GeoIO.load(file)
    @test gtb.geometry isa SimpleMesh
    @test eltype(gtb.h) <: Float64
    vtable = values(gtb, 0)
    @test eltype(vtable.theta) <: Float64

    # the "rectilinear.vtr" file was generated from the WriteVTR.jl test code
    # link: https://github.com/JuliaVTK/WriteVTK.jl/blob/master/test/rectilinear.jl
    file = joinpath(datadir, "rectilinear.vtr")
    gtb = GeoIO.load(file)
    @test gtb.geometry isa RectilinearGrid
    @test eltype(gtb.myCellData) <: Float32
    vtable = values(gtb, 0)
    @test eltype(vtable.p_values) <: Float32
    @test eltype(vtable.q_values) <: Float32
    @test size(eltype(vtable.myVector)) == (3,)
    @test eltype(eltype(vtable.myVector)) <: Float32
    @test size(eltype(vtable.tensor)) == (3, 3)
    @test eltype(eltype(vtable.tensor)) <: Float32

    # the "structured.vts" file was generated from the WriteVTR.jl test code
    # link: https://github.com/JuliaVTK/WriteVTK.jl/blob/master/test/structured.jl
    file = joinpath(datadir, "structured.vts")
    gtb = GeoIO.load(file)
    @test gtb.geometry isa StructuredGrid
    @test eltype(gtb.myCellData) <: Float32
    vtable = values(gtb, 0)
    @test eltype(vtable.p_values) <: Float32
    @test eltype(vtable.q_values) <: Float32
    @test size(eltype(vtable.myVector)) == (3,)
    @test eltype(eltype(vtable.myVector)) <: Float32

    # the "imagedata.vti" file was generated from the WriteVTR.jl test code
    # link: https://github.com/JuliaVTK/WriteVTK.jl/blob/master/test/imagedata.jl
    file = joinpath(datadir, "imagedata.vti")
    gtb = GeoIO.load(file)
    @test gtb.geometry isa CartesianGrid
    @test eltype(gtb.myCellData) <: Float32
    vtable = values(gtb, 0)
    @test size(eltype(vtable.myVector)) == (2,)
    @test eltype(eltype(vtable.myVector)) <: Float32

    # custom lenunit
    file = ReadVTK.get_example_file("celldata_appended_binary_compressed.vtu", output_directory=savedir)
    gtb = GeoIO.load(file, lenunit=cm)
    @test unit(Meshes.lentype(crs(gtb.geometry))) == cm
    file = joinpath(datadir, "spiral.vtp")
    gtb = GeoIO.load(file, lenunit=cm)
    @test unit(Meshes.lentype(crs(gtb.geometry))) == cm
    file = joinpath(datadir, "rectilinear.vtr")
    gtb = GeoIO.load(file, lenunit=cm)
    @test unit(Meshes.lentype(crs(gtb.geometry))) == cm
    file = joinpath(datadir, "structured.vts")
    gtb = GeoIO.load(file, lenunit=cm)
    @test unit(Meshes.lentype(crs(gtb.geometry))) == cm
    file = joinpath(datadir, "imagedata.vti")
    gtb = GeoIO.load(file, lenunit=cm)
    @test unit(Meshes.lentype(crs(gtb.geometry))) == cm
  end

  @testset "save" begin
    file1 = ReadVTK.get_example_file("celldata_appended_binary_compressed.vtu", output_directory=savedir)
    file2 = joinpath(savedir, "unstructured.vtu")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "spiral.vtp")
    file2 = joinpath(savedir, "spiral.vtp")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "rectilinear.vtr")
    file2 = joinpath(savedir, "rectilinear.vtr")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "structured.vts")
    file2 = joinpath(savedir, "structured.vts")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    file1 = joinpath(datadir, "imagedata.vti")
    file2 = joinpath(savedir, "imagedata.vti")
    gtb1 = GeoIO.load(file1)
    GeoIO.save(file2, gtb1)
    gtb2 = GeoIO.load(file2)
    @test gtb1 == gtb2
    @test values(gtb1, 0) == values(gtb2, 0)

    # save cartesian grid in vtr file
    file = joinpath(savedir, "cartesian.vtr")
    gtb1 = georef((; a=rand(100)), CartesianGrid(10, 10))
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test gtb2.geometry isa RectilinearGrid
    @test nvertices(gtb2.geometry) == nvertices(gtb1.geometry)
    @test vertices(gtb2.geometry) == vertices(gtb1.geometry)
    @test values(gtb2) == values(gtb1)

    # save cartesian grid in vts file
    file = joinpath(savedir, "cartesian.vts")
    gtb1 = georef((; a=rand(100)), CartesianGrid(10, 10))
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test gtb2.geometry isa StructuredGrid
    @test nvertices(gtb2.geometry) == nvertices(gtb1.geometry)
    @test vertices(gtb2.geometry) == vertices(gtb1.geometry)
    @test values(gtb2) == values(gtb1)

    # save rectilinear grid in vts file
    file = joinpath(savedir, "rectilinear.vts")
    gtb1 = georef((; a=rand(100)), RectilinearGrid(0:10, 0:10))
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file)
    @test gtb2.geometry isa StructuredGrid
    @test nvertices(gtb2.geometry) == nvertices(gtb1.geometry)
    @test vertices(gtb2.geometry) == vertices(gtb1.geometry)
    @test values(gtb2) == values(gtb1)

    # save views
    grid = CartesianGrid(10, 10)
    mesh = convert(SimpleMesh, grid)
    rgrid = convert(RectilinearGrid, grid)
    sgrid = convert(StructuredGrid, grid)
    table = (; a=rand(100))

    gtb = georef(table, mesh)
    file = joinpath(savedir, "unstructured_view.vtu")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file)
    @test vgtb.a == view(gtb.a, 1:25)
    @test parent(vgtb.geometry) isa SimpleMesh
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    gtb = georef(table, mesh)
    file = joinpath(savedir, "polydata_view.vtp")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file)
    @test vgtb.a == view(gtb.a, 1:25)
    @test parent(vgtb.geometry) isa SimpleMesh
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    gtb = georef(table, rgrid)
    file = joinpath(savedir, "rectilinear_view.vtr")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file)
    @test vgtb.a == view(gtb.a, 1:25)
    @test parent(vgtb.geometry) isa RectilinearGrid
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    gtb = georef(table, sgrid)
    file = joinpath(savedir, "structured_view.vts")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file)
    @test vgtb.a == view(gtb.a, 1:25)
    @test parent(vgtb.geometry) isa StructuredGrid
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    gtb = georef(table, grid)
    file = joinpath(savedir, "imagedata_view.vti")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file)
    @test vgtb.a == view(gtb.a, 1:25)
    @test parent(vgtb.geometry) isa CartesianGrid
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    # mask column with different name
    gtb = georef((; mask=rand(100)), grid)
    file = joinpath(savedir, "imagedata_view.vti")
    GeoIO.save(file, view(gtb, 1:25))
    vgtb = GeoIO.load(file, mask=:mask_)
    @test vgtb == GeoIO.load(file, mask="mask_") # mask as string
    @test vgtb.mask == view(gtb.mask, 1:25)
    @test parent(vgtb.geometry) isa CartesianGrid
    @test vgtb.geometry == view(gtb.geometry, 1:25)

    # throw: the vtr format does not support structured grids
    gtb = GeoIO.load(joinpath(datadir, "structured.vts"))
    @test_throws ErrorException GeoIO.save(joinpath(savedir, "structured.vtr"), gtb)
  end
end
