# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

function imgread(fname; lenunit)
  data = FileIO.load(fname)
  dims = size(data)
  values = (; color=vec(data))
  # translation followed by rotation is faster
  transform = Translate(-dims[1], 0) → Rotate(-π / 2)
  domain = CartesianGrid(dims) |> transform
  georef(values, domain)
end
