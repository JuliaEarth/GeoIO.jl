@testset "NetCDF" begin
  @testset "load" begin
    # the "test.nc" file is a slice of the "gistemp250_GHCNv4.nc" file from NASA
    # link: https://data.giss.nasa.gov/pub/gistemp/gistemp250_GHCNv4.nc.gz
    file = joinpath(datadir, "test.nc")
    gtb = GeoIO.load(file)
    @test gtb.geometry isa RectilinearGrid
    @test isnothing(values(gtb))
    vtable = values(gtb, 0)
    @test length(vtable.tempanomaly) == nvertices(gtb.geometry)
    @test length(first(vtable.tempanomaly)) == 100

    # the "test_kw.nc" file is a slice of the "gistemp250_GHCNv4.nc" file from NASA
    # link: https://data.giss.nasa.gov/pub/gistemp/gistemp250_GHCNv4.nc.gz
    file = joinpath(datadir, "test_kw.nc")
    gtb = GeoIO.load(file, x="lon_x", y="lat_y", t="time_t")
    @test gtb.geometry isa RectilinearGrid
    @test isnothing(values(gtb))
    vtable = values(gtb, 0)
    @test length(vtable.tempanomaly) == nvertices(gtb.geometry)
    @test length(first(vtable.tempanomaly)) == 100

    # timeless vertex data
    file = joinpath(datadir, "test_data.nc")
    gtb = GeoIO.load(file)
    @test gtb.geometry isa RectilinearGrid
    @test isnothing(values(gtb))
    vtable = values(gtb, 0)
    @test length(vtable.tempanomaly) == nvertices(gtb.geometry)
    @test length(first(vtable.tempanomaly)) == 100
    @test length(vtable.data) == nvertices(gtb.geometry)
    @test eltype(vtable.data) <: Float64

    # CRS
    file = joinpath(datadir, "test_latlon.nc")
    gtb = GeoIO.load(file)
    @test gtb.geometry isa RectilinearGrid
    @test crs(gtb.geometry) <: LatLon
    @test datum(crs(gtb.geometry)) === WGS84Latest

    file = joinpath(datadir, "test_latlon_itrf.nc")
    gtb = GeoIO.load(file)
    @test gtb.geometry isa RectilinearGrid
    @test crs(gtb.geometry) <: LatLon
    @test datum(crs(gtb.geometry)) === ITRFLatest

    file = joinpath(datadir, "test_utm_north_32.nc")
    gtb = GeoIO.load(file)
    @test gtb.geometry isa RectilinearGrid
    @test crs(gtb.geometry) <: TransverseMercator
    @test datum(crs(gtb.geometry)) === WGS84Latest
  end

  @testset "save" begin
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
    gtb = georef((; a=rand(10)), rand(Point, 10))
    @test_throws ArgumentError GeoIO.save(file, gtb)
  end
end
