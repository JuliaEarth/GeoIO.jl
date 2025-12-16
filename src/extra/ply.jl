# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# helper function to read PlyIO properties
function plyread(fname; lenunit, kwargs...)
  # load dictionary
  ply = PlyIO.load_ply(fname; kwargs...)

  # load domain
  v = ply["vertex"]
  e = ply["face"]
  u = lengthunit(lenunit)
  points = Point.(v["x"]u, v["y"]u, v["z"]u)
  connec = [connect(Tuple(c .+ 1)) for c in e["vertex_indices"]]
  domain = SimpleMesh(points, connec)

  # load tables
  vnames = [PlyIO.plyname(p) for p in v.properties]
  enames = [PlyIO.plyname(p) for p in e.properties]
  vnames = setdiff(vnames, ["x", "y", "z"])
  enames = setdiff(enames, ["vertex_indices"])
  vpairs = [Symbol(n) => v[n] for n in vnames]
  epairs = [Symbol(n) => e[n] for n in enames]
  vtable = isempty(vpairs) ? nothing : (; vpairs...)
  etable = isempty(epairs) ? nothing : (; epairs...)

  # return geospatial data
  GeoTable(domain; vtable, etable)
end

function plywrite(fname, geotable; kwargs...)
  mesh = domain(geotable)
  if !(mesh isa Mesh && embeddim(mesh) == 3)
    error("the ply format only supports 3D meshes")
  end

  # retrive data
  etable = values(geotable)
  vtable = values(geotable, 0)

  # retrive vertices and connectivity
  verts = eachvertex(mesh)
  connec = elements(topology(mesh))

  # create ply dictionary
  ply = PlyIO.Ply()

  # push vertices
  plyverts = PlyIO.PlyElement(
    "vertex",
    PlyIO.ArrayProperty("x", _getcoord(verts, 1)),
    PlyIO.ArrayProperty("y", _getcoord(verts, 2)),
    PlyIO.ArrayProperty("z", _getcoord(verts, 3)),
    _tableprops(vtable)...
  )
  push!(ply, plyverts)

  # push connectivity
  plyinds = PlyIO.ListProperty("vertex_indices", [collect(indices(c) .- 1) for c in connec])
  plyconnec = PlyIO.PlyElement("face", plyinds, _tableprops(etable)...)
  push!(ply, plyconnec)

  # save file
  PlyIO.save_ply(ply, fname; kwargs...)
end

_getcoord(verts, i) = map(p -> ustrip(to(p)[i]), verts)

function _tableprops(table)
  if !isnothing(table)
    cols = Tables.columns(table)
    names = Tables.columnnames(cols)
    map(names) do name
      column = Tables.getcolumn(cols, name)
      PlyIO.ArrayProperty(string(name), column)
    end
  else
    ()
  end
end
