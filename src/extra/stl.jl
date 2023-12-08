# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function stlraed(fname)
  if endswith(fname, ".stl-ascii")
    _asciiread(fname)
  else
    error("unsupported STL file format")
  end
end

function stlwrite(fname, geotable)
  if endswith(fname, ".stl-ascii")
    _asciiwrite(fname, geotable)
  else
    error("unsupported STL file format")
  end
end

function _asciiread(fname)
  normals = Vec3[]
  vertices = Vector{Point3}[]

  open(fname) do io
    readline(io) # skip header

    while !eof(io)
      line = _splitline(io)
      if !isempty(line) && line[1] == "facet"
        normal = Vec(_parsecoords(line[3:end]))
        push!(normals, normal)

        readline(io) # skip outer loop
        points = map(1:3) do _
          coords = _splitline(io)[2:end]
          Point(_parsecoords(coords))
        end
        push!(vertices, points)

        readline(io) # skip endloop
        readline(io) # skip endfacet
      end
    end
  end

  upoints = unique(Iterators.flatten(vertices))
  connec = map(vertices) do points
    inds = indexin(points, upoints)
    connect(Tuple(inds), Triangle)
  end

  mesh = SimpleMesh(upoints, connec)
  table = (; NORMAL=normals)

  georef(table, mesh)
end

function _asciiwrite(fname, geotable)
  mesh = domain(geotable)

  if !(embeddim(mesh) == 3 && eltype(mesh) <: Triangle)
    throw(ArgumentError("STL format only supports 3D triangle meshes"))
  end

  # file name for header
  name = first(splitext(basename(fname)))

  # number formatter
  frmtfloat = generate_formatter("%e")
  frmtcoords(coords) = join((frmtfloat(c) for c in coords), " ")

  open(fname, write=true) do io
    write(io, "solid $name\n")

    for triangle in elements(mesh)
      n = normal(triangle)
      write(io, "facet normal $(frmtcoords(n))\n")

      write(io, "    outer loop\n")

      for point in vertices(triangle)
        c = coordinates(point)
        write(io, "        vertex $(frmtcoords(c))\n")
      end

      write(io, "    endloop\n")
      write(io,"endfacet\n")
    end

    write(io, "endsolid $name\n")
  end
end

_splitline(io) = split(lowercase(readline(io)))

_parsecoords(coords) = ntuple(i -> parse(Float64, coords[i]), 3)
