# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function objread(fname, numtype::Type{T}; lenunit=nothing) where T
  vertices = NTuple{3,T}[]
  faceinds = Vector{Int}[]

  open(fname) do io
    while !eof(io)
      line = readline(io)
      if !isempty(line)
        strs = Iterators.Stateful(eachsplit(line, ' '))
        isempty(strs) && continue
        prefix = first(strs)
        if prefix == "v"
          point = (parse(T, first(strs)), parse(T, first(strs)), parse(T, first(strs)))
          push!(vertices, point)
        elseif prefix == "f"
          inds = map(strs) do s
            slash = findfirst('/', s)
            ind = @view(s[1:(slash-1)])
            parse(Int, ind)
          end
          push!(faceinds, inds)
        end
      end
    end
  end

  # treat negative indices
  # -1 is equivalet to last index
  nverts = length(vertices)
  for inds in faceinds
    for (i, ind) in enumerate(inds)
      if ind < 0
        inds[i] = nverts + ind + 1
      end
    end
  end

  u = lengthunit(lenunit)
  points = map(v -> Point(v[1]u, v[2]u, v[3]u), vertices)
  connec = map(inds -> connect(Tuple(inds), Ngon), faceinds)
  mesh = SimpleMesh(points, connec)

  georef(nothing, mesh)
end

function objwrite(fname, geotable)
  mesh = domain(geotable)

  if !(mesh isa Mesh && embeddim(mesh) == 3 && paramdim(mesh) == 2)
    throw(ArgumentError("OBJ format only supports 3D Ngon meshes"))
  end

  open(fname, write=true) do io
    for point in eachvertex(mesh)
      coords = ustrip.(to(point))
      write(io, "v ")
      join(io, coords, " ")
      println(io)
    end

    for connec in elements(topology(mesh))
      inds = indices(connec)
      write(io, "f ")
      join(io, inds, " ")
      println(io)
    end
  end
end
