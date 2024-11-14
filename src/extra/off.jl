# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function offread(fname; lenunit, defaultcolor=RGBA(0.666, 0.666, 0.666, 0.666))
  vertices = NTuple{3,Float64}[]
  faceinds = Vector{Int}[]
  facecolors = RGBA{Float64}[]
  default = convert(RGBA{Float64}, defaultcolor)

  open(fname) do io
    line = _readline(io)
    # skip header or comment lines
    while isempty(line) || occursin("OFF", line)
      line = _readline(io)
    end

    # number of vertices and number of faces (ignonring number of edges)
    strs = split(line)
    nverts, nfaces, _ = ntuple(i -> parse(Int, strs[i]), 3)

    for _ in 1:nverts
      strs = split(_readline(io))
      point = ntuple(i -> parse(Float64, strs[i]), 3)
      push!(vertices, point)
    end

    for _ in 1:nfaces
      strs = split(_readline(io))
      # number of face vertices
      nv = parse(Int, first(strs))
      # face vertices use 0-based indexing
      inds = map(i -> parse(Int, strs[i]) + 1, 2:(nv + 1))
      push!(faceinds, inds)
      # parse facet color
      offset = nv + 1
      color = if length(strs) == offset + 3
        r, g, b = ntuple(i -> _parsechannel(strs[i + offset]), 3)
        RGBA(r, g, b, 0)
      elseif length(strs) == offset + 4
        r, g, b, a = ntuple(i -> _parsechannel(strs[i + offset]), 4)
        RGBA(r, g, b, a)
      else
        default
      end
      push!(facecolors, color)
    end
  end

  table = (; color=facecolors)

  u = lengthunit(lenunit)
  points = map(v -> Point(v[1]u, v[2]u, v[3]u), vertices)
  connec = map(inds -> connect(Tuple(inds), Ngon), faceinds)
  mesh = SimpleMesh(points, connec)

  georef(table, mesh)
end

function offwrite(fname, geotable; color=nothing)
  mesh = domain(geotable)
  if !(mesh isa Mesh && embeddim(mesh) == 3 && paramdim(mesh) == 2)
    throw(ArgumentError("OFF format only supports 3D Ngon meshes"))
  end

  colors = if !isnothing(color)
    table = values(geotable)
    if !isnothing(table)
      cols = Tables.columns(table)
      column = Tables.getcolumn(cols, Symbol(color))
      if !(eltype(column) <: Colorant)
        throw(ArgumentError("The color column must be a iterable of colors"))
      end
      convert.(RGBA{Float64}, column)
    else
      nothing
    end
  else
    nothing
  end

  open(fname, write=true) do io
    write(io, "OFF\n")
    nverts = nvertices(mesh)
    nfaces = nelements(mesh)
    # number of edges must be ignored by passing 0
    write(io, "$nverts $nfaces 0\n")

    for point in vertices(mesh)
      coords = ustrip.(to(point))
      write(io, "$(join(coords, " "))\n")
    end

    for (i, connec) in enumerate(elements(topology(mesh)))
      # 1-based indexing to 0-based indexing
      inds = indices(connec) .- 1
      nv = length(inds)
      rgba = !isnothing(colors) ? _rgba(colors[i]) : ""
      write(io, "$nv $(join(inds, " ")) $rgba\n")
    end
  end
end

# -----------------
# HELPER FUNCTIONS
# -----------------

_rmcomment(line) = replace(line, r"#.*" => "")
_readline(io) = _rmcomment(readline(io))

_parsechannel(str) = occursin(".", str) ? parse(Float64, str) : parse(Int, str) / 255

_rgba(color) = "$(red(color)) $(green(color)) $(blue(color)) $(alpha(color))"
