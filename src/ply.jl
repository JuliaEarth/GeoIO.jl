# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# helper function to read PLY properties
function plyread(fname)
  # load dictionary
  ply = PLY.load_ply(fname)

  # load domain
  v = ply["vertex"]
  e = ply["face"]
  points = Point3.(v["x"], v["y"], v["z"])
  connec = [connect(Tuple(c .+ 1)) for c in e["vertex_indices"]]
  domain = SimpleMesh(points, connec)

  # load tables
  vnames = [PLY.plyname(p) for p in v.properties]
  enames = [PLY.plyname(p) for p in e.properties]
  vnames = setdiff(vnames, ["x", "y", "z"])
  enames = setdiff(enames, ["vertex_indices"])
  vcols = [n => v[n] for n in vnames]
  ecols = [n => e[n] for n in enames]
  vtable = isempty(vcols) ? nothing : (; vcols...)
  etable = isempty(ecols) ? nothing : (; ecols...)

  # return geospatial data
  meshdata(domain; vtable, etable)
end
