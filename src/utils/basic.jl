# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

# type aliases
const Met{T} = Quantity{T,u"𝐋",typeof(u"m")}
const Deg{T} = Quantity{T,NoDims,typeof(u"°")}

# default length unit if not set
lengthunit(u) = isnothing(u) ? m : u

# append '_' to `name` until it is unique compared to `names`
function uniquename(names, name)
  uname = name
  while uname ∈ names
    uname = Symbol(uname, :_)
  end
  uname
end

# make `newnames` unique compared to `names`
function uniquenames(names, newnames)
  map(newnames) do name
    uniquename(names, name)
  end
end

# construct named tuple with static number of variables
function namedtuple(vars, cols)
  tvars = Tuple(vars)
  tvals = ntuple(i -> Tables.getcolumn(cols, tvars[i]), length(tvars))
  NamedTuple{tvars}(tvals)
end
