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
  elseif endswith(fname, ".vtp")
    vtpread(fname)
  elseif endswith(fname, ".vtr")
    vtrread(fname)
  else
    error("unsupported VTK file format")
  end
end

function vturead(fname)
  vtk = ReadVTK.VTKFile(fname)

  # construct mesh
  points = _points(vtk)
  connec = _vtuconnec(vtk)
  mesh = SimpleMesh(points, connec)

  # extract data
  vtable, etable = _datatables(vtk)

  # georeference
  GeoTable(mesh; vtable, etable)
end

function vtpread(fname)
  vtk = ReadVTK.VTKFile(fname)

  # construct mesh
  points = _points(vtk)
  connec = _vtpconnec(vtk)
  mesh = SimpleMesh(points, connec)

  # extract data
  vtable, etable = _datatables(vtk)

  # georeference
  GeoTable(mesh; vtable, etable)
end

function vtrread(fname)
  vtk = ReadVTK.VTKFile(fname)

  # construct grid
  coords = ReadVTK.get_coordinates(vtk)
  inds = map(!allequal, coords) |> collect
  grid = RectilinearGrid(coords[inds]...)

  # extract data
  vtable, etable = _datatables(vtk)

  # georeference
  GeoTable(grid; vtable, etable)
end

function _points(vtk)
  coords = ReadVTK.get_points(vtk)
  inds = map(!allequal, eachrow(coords))
  [Point(Tuple(c)) for c in eachcol(coords[inds, :])]
end

function _vtuconnec(vtk)
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
  [connect(ind, G) for (ind, G) in zip(inds, types)]
end

function _vtpconnec(vtk)
  polys = ReadVTK.get_primitives(vtk, "Polys")
  offsets = polys.offsets
  connectivity = polys.connectivity

  # list of connectivity indices
  inds = map(eachindex(offsets)) do i
    start = i == 1 ? 1 : (offsets[i - 1] + 1)
    Tuple(connectivity[start:offsets[i]])
  end

  # construct connectivity elements
  [connect(ind, Ngon) for ind in inds]
end

function _datatables(vtk)
  # extract point data
  vtable = try
    vtkdata = ReadVTK.get_point_data(vtk)
    _astable(vtkdata)
  catch
    nothing
  end

  # extract element data
  etable = try
    vtkdata = ReadVTK.get_cell_data(vtk)
    _astable(vtkdata)
  catch
    nothing
  end

  vtable, etable
end

function _astable(vtkdata)
  names = keys(vtkdata)
  if !isempty(names)
    pairs = map(names) do name
      column = ReadVTK.get_data(vtkdata[name])
      Symbol(name) => _asvector(column)
    end
    (; pairs...)
  else
    nothing
  end
end

function _asvector(column)
  if ndims(column) == 2
    SA = size(column, 1) == 9 ? SMatrix{3,3} : SVector{3}
    [SA(c) for c in eachcol(column)]
  else
    column
  end
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
