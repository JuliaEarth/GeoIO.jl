# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function vtkwrite(fname, geotable)
  dom, etable, vtable = _extractvals(geotable)

  if endswith(fname, ".vtu")
    vtuwrite(fname, dom, etable, vtable)
  elseif endswith(fname, ".vtp")
    vtpwrite(fname, dom, etable, vtable)
  elseif endswith(fname, ".vtr")
    vtrwrite(fname, dom, etable, vtable)
  elseif endswith(fname, ".vts")
    vtswrite(fname, dom, etable, vtable)
  elseif endswith(fname, ".vti")
    vtiwrite(fname, dom, etable, vtable)
  else
    error("unsupported VTK file format")
  end
end

function vtuwrite(fname, mesh::Mesh, etable, vtable)
  verts = vertices(mesh)
  connec = elements(topology(mesh))
  points = stack(coordinates, verts)
  cells = [VTKBase.MeshCell(_vtktype(pltype(c)), indices(c)) for c in connec]

  WriteVTK.vtk_grid(fname, points, cells) do vtk
    _writetables(vtk, etable, vtable)
  end
end

function vtpwrite(fname, mesh::Mesh, etable, vtable)
  verts = vertices(mesh)
  connec = elements(topology(mesh))
  points = stack(coordinates, verts)
  cells = [VTKBase.MeshCell(PolyData.Polys(), indices(c)) for c in connec]

  WriteVTK.vtk_grid(fname, points, cells) do vtk
    _writetables(vtk, etable, vtable)
  end
end

function vtrwrite(fname, grid::Grid, etable, vtable)
  if !(grid isa Union{RectilinearGrid,CartesianGrid})
    error("the vtr format only supports rectilinear or cartesian grids")
  end

  xyz = map(collect, Meshes.xyz(grid))
  WriteVTK.vtk_grid(fname, xyz...) do vtk
    _writetables(vtk, etable, vtable)
  end
end

function vtswrite(fname, grid::Grid, etable, vtable)
  WriteVTK.vtk_grid(fname, Meshes.XYZ(grid)...) do vtk
    _writetables(vtk, etable, vtable)
  end
end

function vtiwrite(fname, grid::CartesianGrid, etable, vtable)
  orig = coordinates(minimum(grid))
  spac = spacing(grid)
  dims = size(grid)
  xyz = map(orig, spac, dims) do o, s, d
    range(start=o, step=s, length=(d + 1))
  end

  WriteVTK.vtk_grid(fname, xyz...) do vtk
    _writetables(vtk, etable, vtable)
  end
end

#-------
# UTILS
#-------

function _extractvals(geotable) 
  dom = domain(geotable)
  etable = values(geotable)
  vtable = values(geotable, 0)
  if dom isa Meshes.SubDomain
    _subdomvals(dom, etable)
  else
    dom, etable, vtable
  end
end

function _subdomvals(subdom, table)
  dom = parent(subdom)
  inds = parentindices(subdom)

  cols = Tables.columns(table)
  names = Tables.columnnames(cols)
  pairs = map(names) do name
    x = Tables.getcolumn(cols, name)
    y = fill(NaN, nelements(dom))
    y[inds] .= x
    name => y
  end

  mask = :MASK
  # make unique
  while mask ∈ names
    mask = Symbol(mask, :_)
  end
  maskcol = zeros(UInt8, nelements(dom))
  maskcol[inds] .= 1

  newtable = (; pairs..., mask => maskcol)
  dom, newtable, nothing
end

_vtktype(::Type{<:Segment}) = VTKCellTypes.VTK_LINE
_vtktype(::Type{<:Triangle}) = VTKCellTypes.VTK_TRIANGLE
_vtktype(::Type{<:Quadrangle}) = VTKCellTypes.VTK_QUAD
_vtktype(::Type{<:Ngon}) = VTKCellTypes.VTK_POLYGON
_vtktype(::Type{<:Tetrahedron}) = VTKCellTypes.VTK_TETRA
_vtktype(::Type{<:Hexahedron}) = VTKCellTypes.VTK_HEXAHEDRON
_vtktype(::Type{<:Pyramid}) = VTKCellTypes.VTK_PYRAMID

function _writetables(vtk, etable, vtable)
  _writetable(vtk, VTKBase.VTKCellData(), etable)
  _writetable(vtk, VTKBase.VTKPointData(), vtable)
end

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
