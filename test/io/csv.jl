@testset "CSV" begin
  @testset "load" begin
    gtb1 = GeoIO.load(joinpath(datadir, "points.csv"), coords=["x", "y"])
    @test eltype(gtb1.code) <: Integer
    @test eltype(gtb1.name) <: AbstractString
    @test eltype(gtb1.variable) <: Real
    @test gtb1.geometry isa PointSet
    @test length(gtb1.geometry) == 5

    # latlon coordinates
    gtb1 = GeoIO.load(joinpath(datadir, "latlon.csv"), coords=("lat", "lon"))
    @test eltype(gtb1.code) <: Integer
    @test eltype(gtb1.name) <: AbstractString
    @test eltype(gtb1.variable) <: Real
    @test gtb1.geometry isa PointSet
    @test crs(gtb1.geometry) <: LatLon
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

    # custom lenunit
    gtb = GeoIO.load(joinpath(datadir, "points.csv"), coords=["x", "y"], lenunit=cm)
    @test unit(Meshes.lentype(crs(gtb.geometry))) == cm
  end

  @testset "save" begin
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
    pset = PointSet(rand(Point, 10))
    gtb1 = georef((x=rand(10), y=rand(10), z=rand(10)), pset)
    file = joinpath(savedir, "pset.csv")
    GeoIO.save(file, gtb1)
    gtb2 = GeoIO.load(file, coords=[:x_, :y_, :z_])
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
    gtb = georef((; a=rand(10)), rand(Point, 10))
    @test_throws ArgumentError GeoIO.save(file, gtb, coords=["x", "y"])
  end
end
