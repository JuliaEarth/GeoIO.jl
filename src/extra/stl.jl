# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# ---------
# STL READ
# ---------

function stlraed(fname; lenunit,numbertype)
  normals, vertices = if _isstlbin(fname)
    stlbinread(fname)
  else
    stlasciiread(fname;numbertype)
  end

  uverts = unique(Iterators.flatten(vertices))
  index = Dict(zip(uverts, eachindex(uverts)))
  connec = map(vertices) do verts
    inds = ntuple(i -> index[verts[i]], 3)
    connect(inds, Triangle)
  end

  u = lengthunit(lenunit)

  norms = map(n -> Vec(n .* u), normals)
  table = (; normal=norms)

  points = map(v -> Point(v[1]u, v[2]u, v[3]u), uverts)
  mesh = SimpleMesh(points, connec)

  georef(table, mesh)
end

function stlasciiread(fname;numbertype)
  normals = NTuple{3,numbertype}[]
  vertices = NTuple{3,NTuple{3,numbertype}}[]

  open(fname) do io
    readline(io) # skip header

    while !eof(io)
      line = _splitline(io)
      if !isempty(line) && line[1] == "facet"
        normal = _parsecoords(line[3:end];numbertype)
        push!(normals, normal)

        readline(io) # skip outer loop
        points = ntuple(_ -> _parsecoords(_splitline(io)[2:end];numbertype), 3)
        push!(vertices, points)

        readline(io) # skip endloop
        readline(io) # skip endfacet
      end
    end
  end

  normals, vertices
end

function stlbinread(fname)
  normals = NTuple{3,Float32}[]
  vertices = NTuple{3,NTuple{3,Float32}}[]

  open(fname) do io
    skip(io, 80) # skip header
    ntriangles = read(io, UInt32)
    for _ in 1:ntriangles
      normal = ntuple(_ -> read(io, Float32), 3)
      push!(normals, normal)
      points = ntuple(_ -> ntuple(_ -> read(io, Float32), 3), 3)
      push!(vertices, points)
      skip(io, 2) # skip attribute byte count
    end
  end

  normals, vertices
end

# ----------
# STL WRITE
# ----------

function stlwrite(fname, geotable; ascii=false)
  mesh = domain(geotable)

  if !(embeddim(mesh) == 3 && eltype(mesh) <: Triangle)
    throw(ArgumentError("STL format only supports 3D triangle meshes"))
  end

  if ascii
    stlasciiwrite(fname, mesh)
  else
    stlbinwrite(fname, mesh)
  end
end

function stlasciiwrite(fname, mesh)
  # file name for header
  name = first(splitext(basename(fname)))

  # number formatter
  frmtfloat = generate_formatter("%e")
  frmtcoords(coords) = join((frmtfloat(c) for c in coords), " ")

  open(fname, write=true) do io
    write(io, "solid $name\n")

    for triangle in elements(mesh)
      n = ustrip.(normal(triangle))
      write(io, "facet normal $(frmtcoords(n))\n")
      write(io, "    outer loop\n")

      for point in eachvertex(triangle)
        c = ustrip.(to(point))
        write(io, "        vertex $(frmtcoords(c))\n")
      end

      write(io, "    endloop\n")
      write(io, "endfacet\n")
    end

    write(io, "endsolid $name\n")
  end
end

function stlbinwrite(fname, mesh)
  if Unitful.numtype(Meshes.lentype(mesh)) <: Float64
    @warn """
    The STL Binary format stores data with 32-bit precision.
    Use STL ASCII format, with `ascii=true`, to store data with full precision.
    """
  end

  open(fname, write=true) do io
    foreach(i -> write(io, 0x00), 1:80) # empty header

    write(io, UInt32(nelements(mesh))) # number of triangles

    for triangle in elements(mesh)
      n = ustrip.(normal(triangle))
      foreach(c -> write(io, Float32(c)), n)
      for point in eachvertex(triangle)
        foreach(c -> write(io, Float32(c)), ustrip.(to(point)))
      end
      write(io, 0x0000) # empty attribute byte count
    end
  end
end

# -----------------
# HELPER FUNCTIONS
# -----------------

function _isstlbin(fname)
  io = open(fname)
  filelen = position(seekend(io))
  seekstart(io)

  # header size + "number of triangles" size
  headersize = 80 + sizeof(UInt32)
  if filelen < headersize
    close(io)
    return false
  end

  skip(io, 80) # skip header
  ntriangles = read(io, UInt32)
  # "normal vertices + 3 triangles vertices" size + "attribute byte count" size
  triblocksize = 4 * 3 * sizeof(Float32) + sizeof(UInt16)
  trianglessize = ntriangles * triblocksize
  if filelen ≠ headersize + trianglessize
    close(io)
    return false
  end

  skip(io, trianglessize) # skip all triangle blocks
  result = eof(io) # if eof, it's a STL Binary file
  close(io)

  return result
end

_splitline(io) = split(lowercase(readline(io)))

_parsecoords(coords;numbertype) = ntuple(i -> parse(numbertype, coords[i]), 3)
