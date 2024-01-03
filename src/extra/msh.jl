# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function mshread(fname)
  nodetags = Int[]
  vertices = Point3[]
  elemtypes = Int[]
  elemnodes = Vector{Int}[]

  open(fname) do io
    while !eof(io)
      line = readline(io)
      if !isempty(line)
        if line == "\$MeshFormat"
          _checkversion(io)
        elseif line == "\$Nodes"
          _parsenodes!(io, nodetags, vertices)  
        elseif line == "\$Elements"
          _parseelements!(io, elemtypes, elemnodes)
        else
          _skipblock(io)
        end
      end
    end
  end

  # convert nodetags to indices
  nodeind = Dict(zip(nodetags, eachindex(nodetags)))
  eleminds = map(elemnodes) do tags
    [nodeind[tag] for tag in tags]
  end

  connec = map(elemtypes, eleminds) do elemtype, inds
    PL = ELEMTYPE2GEOM[elemtype]
    connect(ntuple(i -> inds[i], nvertices(PL)), PL)
  end
  mesh = SimpleMesh(vertices, connec)

  GeoTable(mesh)
end

function mshwrite(fname, geotable)
  mesh = domain(geotable)
  if !(mesh isa Mesh{3})
    throw(ArgumentError("MSH format only supports 3D meshes"))
  end

  geom = eltype(mesh)
  pdim = paramdim(geom)
  elemtype = _elemtype(geom)
  open(fname, write=true) do io
    write(io, "\$MeshFormat\n")
    # version fileType dataSize
    write(io, "4.1 0 $(sizeof(UInt))\n")
    write(io, "\$EndMeshFormat\n")

    nverts = nvertices(mesh)
    write(io, "\$Nodes\n")
    # only one entity with tag 1
    # numEntityBlocks numNodes minNodeTag maxNodeTag
    write(io, "1 $nverts 1 $nverts\n")
    # entityDim entityTag parametric numNodesInBlock
    write(io, "$pdim 1 0 $nverts\n")
    # node tags
    for i in 1:nverts
      write(io, "$i\n")
    end
    # node coordinates
    for point in vertices(mesh)
      coords = coordinates(point)
      write(io, "$(join(coords, " "))\n")
    end
    write(io, "\$EndNodes\n")

    nelems = nelements(mesh)
    write(io, "\$Elements\n")
    # only one entity with tag 1
    # numEntityBlocks numElements minElementTag maxElementTag
    write(io, "1 $nelems 1 $nelems\n")
    # entityDim entityTag elementType numElementsInBlock
    write(io, "$pdim 1 $elemtype $nelems\n")
    for (i, connec) in enumerate(elements(topology(mesh)))
      inds = indices(connec)
      write(io, "$i $(join(inds, " "))\n")
    end
    write(io, "\$EndElements\n")
  end
end

# -----------------
# HELPER FUNCTIONS
# -----------------

const ELEMTYPE2GEOM = Dict(
  1 => Segment,
  2 => Triangle,
  3 => Quadrangle,
  4 => Tetrahedron,
  5 => Hexahedron,
  7 => Pyramid
)

_elemtype(::Type{<:Segment}) = 1
_elemtype(::Type{<:Triangle}) = 2
_elemtype(::Type{<:Quadrangle}) = 3
_elemtype(::Type{<:Tetrahedron}) = 4
_elemtype(::Type{<:Hexahedron}) = 5
_elemtype(::Type{<:Pyramid}) = 7
_elemtype(::Type{G}) where {G<:Geometry} = error("`$G` is not supported by MSH format")

function _checkversion(io)
  strs = split(readline(io))
  version = parse(Float64, first(strs))
  if version < 4.1
    error("the minimum supported version of the MSH format is 4.1")
  end
  readline(io) # $EndMeshFormat
end

function _parsenodes!(io, nodetags, vertices)
  strs = split(readline(io))
  # number of entity blocks
  # ignoring numNodes, minNodeTag, maxNodeTag
  nblocks = parse(Int, first(strs))
  for _ in 1:nblocks
    strs = split(readline(io))
    # number of nodes in entity block
    # ignoring entityDim, entityTag, parametric
    nnodes = parse(Int, last(strs))
    for _ in 1:nnodes
      nodetag = parse(Int, readline(io))
      push!(nodetags, nodetag)
    end

    for _ in 1:nnodes
      strs = split(readline(io))
      point = Point(ntuple(i -> parse(Float64, strs[i]), 3))
      push!(vertices, point)
    end
  end
  readline(io) # $EndNodes
end

function _parseelements!(io, elemtypes, elemnodes)
  strs = split(readline(io))
  # number of entity blocks
  # ignoring numElements, minElementTag, maxElementTag
  nblocks = parse(Int, first(strs))
  for _ in 1:nblocks
    strs = split(readline(io))
    # element type and number of elements entity in block
    # ignoring entityDim, entityTag
    elemtype, nelems = parse.(Int, strs[3:4])
    for _ in 1:nelems
      strs = split(readline(io))
      if haskey(ELEMTYPE2GEOM, elemtype)
        push!(elemtypes, elemtype)
        # node tags for current element
        nodes = parse.(Int, strs[2:end])
        push!(elemnodes, nodes)
      else
        error("element type $elemtype is not currently supported")
      end
    end
  end
  readline(io) # $EndElements
end

function _skipblock(io)
  while !eof(io)
    line = readline(io)
    if startswith(line, "\$End")
      break
    end
  end
end
