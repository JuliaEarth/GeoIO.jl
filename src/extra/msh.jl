# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function mshread(fname)
  P3 = typeof(rand(Point{3}))
  nodetags = Int[]
  vertices = P3[]
  nodedata = Dict{Int,Any}()

  elemtags = Int[]
  elemtypes = Int[]
  elemnodes = Vector{Int}[]
  elemdata = Dict{Int,Any}()

  open(fname) do io
    while !eof(io)
      line = strip(readline(io))
      if !isempty(line)
        if line == "\$MeshFormat"
          _checkversion(io)
        elseif line == "\$Nodes"
          _parsenodes!(io, nodetags, vertices)
        elseif line == "\$Elements"
          _parseelements!(io, elemtags, elemtypes, elemnodes)
        elseif line == "\$NodeData"
          _parsedata!(io, nodedata)
        elseif line == "\$ElementData"
          _parsedata!(io, elemdata)
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
    connect(Tuple(inds), ELEMTYPE2GEOM[elemtype])
  end
  mesh = SimpleMesh(vertices, connec)

  vtable = _datatable(nodetags, nodedata)
  etable = _datatable(elemtags, elemdata)

  GeoTable(mesh; vtable, etable)
end

function mshwrite(fname, geotable; vcolumn=nothing, ecolumn=nothing)
  mesh = domain(geotable)
  if !(mesh isa Mesh{3})
    throw(ArgumentError("MSH format only supports 3D meshes"))
  end

  etable = values(geotable)
  vtable = values(geotable, 0)
  edata = !isnothing(ecolumn) ? _datacolumn(etable, Symbol(ecolumn)) : nothing
  vdata = !isnothing(vcolumn) ? _datacolumn(vtable, Symbol(vcolumn)) : nothing

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
      coords = ustrip.(to(point))
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

    if !isnothing(vdata)
      write(io, "\$NodeData\n")
      _writecolumn(io, vdata)
      write(io, "\$EndNodeData\n")
    end

    if !isnothing(edata)
      write(io, "\$ElementData\n")
      _writecolumn(io, edata)
      write(io, "\$EndElementData\n")
    end
  end
end

# -----------------
# HELPER FUNCTIONS
# -----------------

const ELEMTYPE2GEOM =
  Dict(1 => Segment, 2 => Triangle, 3 => Quadrangle, 4 => Tetrahedron, 5 => Hexahedron, 7 => Pyramid)

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

function _parseelements!(io, elemtags, elemtypes, elemnodes)
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
        tag = parse(Int, strs[1])
        push!(elemtags, tag)
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

function _parsedata!(io, data)
  # skip string tags
  nstrtags = parse(Int, readline(io))
  for _ in 1:nstrtags
    readline(io)
  end

  # skip real tags
  nrealtags = parse(Int, readline(io))
  for _ in 1:nrealtags
    readline(io)
  end

  # integer tags
  ninttags = parse(Int, readline(io))
  if ninttags < 3
    error("missing one or more of the required tags: number of field components, number of entities")
  end

  inttags = [parse(Int, readline(io)) for _ in 1:ninttags]
  ncomp = inttags[2] # number of field components (dimensions)
  nvals = inttags[3] # number of entities
  for _ in 1:nvals
    strs = split(readline(io))
    tag = parse(Int, strs[1])
    value = if ncomp == 9
      SMatrix{3,3}(ntuple(i -> parse(Float64, strs[i + 1]), 9))
    elseif ncomp == 3
      SVector{3}(ntuple(i -> parse(Float64, strs[i + 1]), 3))
    elseif ncomp == 1
      parse(Float64, strs[2])
    else
      error("invalid number of field components")
    end
    push!(data, tag => value)
  end
  readline(io) # $End[Node or Element]Data
end

function _datatable(tags, data)
  if !isempty(data)
    column = [get(data, tag, missing) for tag in tags]
    (; DATA=column)
  else
    nothing
  end
end

function _skipblock(io)
  while !eof(io)
    line = readline(io)
    if startswith(line, "\$End")
      break
    end
  end
end

function _datacolumn(table, name)
  if !isnothing(table)
    cols = Tables.columns(table)
    column = Tables.getcolumn(cols, name)
    T = nonmissingtype(eltype(column))
    if T <: AbstractMatrix
      if !all(size(v) == (3, 3) for v in skipmissing(column))
        error("matrix data must have size equal to 3x3")
      end
    elseif T <: AbstractVector
      if !all(length(v) == 3 for v in skipmissing(column))
        error("vector data must have size equal to 3")
      end
    end
    float.(column)
  else
    nothing
  end
end

function _writecolumn(io, column)
  # string tags
  write(io, "1\n")
  write(io, "\"data\"\n") # view name
  # real tags
  write(io, "1\n")
  write(io, "0.0\n") # time value
  # integer tags
  write(io, "3\n")
  write(io, "0\n") # time step
  write(io, "$(_ncomps(column))\n") # number of field components
  write(io, "$(count(!ismissing, column))\n") # number of entities
  for (i, v) in enumerate(column)
    if !ismissing(v)
      write(io, "$i $(join(v, " "))\n")
    end
  end
end

function _ncomps(column)
  T = nonmissingtype(eltype(column))
  if T <: AbstractMatrix
    9
  elseif T <: AbstractVector
    3
  else
    1
  end
end
