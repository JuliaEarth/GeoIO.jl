# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

vtktype(::Type{<:Segment}) = VTKCellTypes.VTK_LINE
vtktype(::Type{<:Triangle}) = VTKCellTypes.VTK_TRIANGLE
vtktype(::Type{<:Quadrangle}) = VTKCellTypes.VTK_QUAD
vtktype(::Type{<:Ngon}) = VTKCellTypes.VTK_POLYGON
vtktype(::Type{<:Tetrahedron}) = VTKCellTypes.VTK_TETRA
vtktype(::Type{<:Hexahedron}) = VTKCellTypes.VTK_HEXAHEDRON
vtktype(::Type{<:Pyramid}) = VTKCellTypes.VTK_PYRAMID

function vtkwrite(fname, geotable)
  dom = domain(geotable)
  edata = values(geotable)
  pdata = values(geotable, 0)
  
  if endswith(fname, ".vtu")
    vtuwrite(fname, dom, edata, pdata)
  elseif endswith(fname, ".vtp")
    vtpwrite(fname, dom, edata, pdata)
  else
    error("unsupported VTK file format")
  end
end

function vtuwrite(fname, mesh::SimpleMesh, edata, pdata)
  verts = vertices(mesh)
  connec = elements(topology(mesh))
  points = stack(coordinates, verts)
  cells = map(c -> (vtktype(pltype(c)), indices(c)), connec)

  WriteVTK.vtk_grid(fname, points, cells) do vtk
    _writetable(vtk, WriteVTK.VTKCellData(), edata)
    _writetable(vtk, WriteVTK.VTKPointData(), pdata)
  end
end

function vtpwrite(fname, mesh::SimpleMesh, edata, pdata)
  verts = vertices(mesh)
  connec = elements(topology(mesh))
  points = stack(coordinates, verts)
  cells = map(c -> (WriteVTK.PolyData.Polys(), indices(c)), connec)

  WriteVTK.vtk_grid(fname, points, cells) do vtk
    _writetable(vtk, WriteVTK.VTKCellData(), edata)
    _writetable(vtk, WriteVTK.VTKPointData(), pdata)
  end
end

#-------
# UTILS
#-------

function _writetable(vtk, datatype, table)
  if !isnothing(table)
    cols = Tables.columns(table)
    names = Tables.columnnames(cols)
    for name in names
      column = Tables.getcolumn(cols, name)
      vtk[string(name), datatype] = column
    end
  end
end
