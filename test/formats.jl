@testset "Supported formats" begin
  io = IOBuffer()

  GeoIO.formats(io)
  iostr = String(take!(io))
  @test !isempty(iostr)

  GeoIO.formats(io, sortby=:load)
  iostr = String(take!(io))
  @test !isempty(iostr)

  GeoIO.formats(io, sortby=:save)
  iostr = String(take!(io))
  @test !isempty(iostr)

  # throws
  @test_throws ArgumentError GeoIO.formats(sortby=:invalid)
end
