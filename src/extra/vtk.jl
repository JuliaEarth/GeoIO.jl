# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

const GEOMTYPE = Dict(
  VTKCellTypes.VTK_LINE => Segment,
  VTKCellTypes.VTK_TRIANGLE => Triangle,
  VTKCellTypes.VTK_PIXEL => Quadrangle,
  VTKCellTypes.VTK_QUAD => Quadrangle,
  VTKCellTypes.VTK_POLYGON => Ngon,
  VTKCellTypes.VTK_TETRA => Tetrahedron,
  VTKCellTypes.VTK_VOXEL => Hexahedron,
  VTKCellTypes.VTK_HEXAHEDRON => Hexahedron,
  VTKCellTypes.VTK_PYRAMID => Pyramid
)

function vtkread(fname)
  if endswith(fname, ".vtu")
    vturead(fname)
  else
    error("unsupported VTK file format")
  end
end

function vturead(fname)
  vtk = ReadVTK.VTKFile(fname)

  # get points
  coords = ReadVTK.get_points(vtk)
  points = [Point(Tuple(c)) for c in eachcol(coords)]

  # get connectivity info
  cells = ReadVTK.get_cells(vtk)
  offsets = cells.offsets
  connectivity = cells.connectivity
  vtktypes = [VTKCellTypes.VTKCellType(id) for id in cells.types]

  # list of connectivity indices
  inds = map(eachindex(offsets), vtktypes) do i, vtktype
    start = i == 1 ? 1 : (offsets[i - 1] + 1)
    connec = Tuple(connectivity[start:offsets[i]])
    _adjustconnec(connec, vtktype)
  end

  # list of mapped geometry types
  types = [GEOMTYPE[vtktype] for vtktype in vtktypes]

  # construct connectivity elements
  connec = [connect(ind, G) for (ind, G) in zip(inds, types)]

  # construct mesh
  mesh = SimpleMesh(points, connec)

  # extract columns with measurements
  cols = ReadVTK.get_cell_data(vtk)
  pairs = map(keys(cols)) do name
    column = ReadVTK.get_data(cols[name])
    Symbol(name) => column
  end
  table = (; pairs...)

  # georeference
  georef(table, mesh)
end

# in the case of VTK_PIXEL and VTK_VOXEL
# we need to flip vertices in the connectivity list 
function _adjustconnec(connec, vtktype)
  if vtktype == VTKCellTypes.VTK_PIXEL
    (connec[1], connec[2], connec[4], connec[3])
  elseif vtktype == VTKCellTypes.VTK_VOXEL
    (connec[1], connec[2], connec[4], connec[3], connec[5], connec[6], connec[8], connec[7])
  else
    connec
  end
end
