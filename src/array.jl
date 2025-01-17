__precompile__(false) # due to the usage of @eval
module array

import Base: convert, copy, eltype, hypot, maximum, minimum, ndims,
             show, size, sqrt, exp, log, log10, sin, cos, tan,
             expm1, log2, log1p, sinh, cosh, tanh, csc, sec, cot, csch,
             sinh, coth, sinpi, cospi, abs, abs2, asin, acos, atan, sum,
             cumsum, diff, display, print, showerror, ones, zeros, summary,
             fill, broadcast, accumulate,
             +, -, *, /, \, ==, >=, <=, ≥, ≤, >, <, ^,
             getindex, setindex!, isequal, length
import Statistics: mean, std, stdm, var, varm, median, middle, quantile
import PyCall: pyimport_conda, PyObject, pycall, pybuiltin, PyAny, PyNULL, pystring

#IntOrRange = Union{Integer,AbstractRange,Colon}
#Indexes = Union{IntOrRange,Array{Int,1}}

# Grab the classes for creating YTArrays and YTQuantities

const ytunits = PyNULL()
const ytdims = PyNULL()
const bare_array = PyNULL()
const bare_quan = PyNULL()

function __init__()
    copy!(ytunits, pyimport_conda("yt.units", "yt"))
    copy!(ytdims, pyimport_conda("yt.units.dimensions", "yt"))
    copy!(bare_array, ytunits["yt_array"]["YTArray"])
    copy!(bare_quan, ytunits["yt_array"]["YTQuantity"])
end

struct YTUnit
    yt_unit::PyObject
    unit_string::String
    dimensions::PyObject
    function YTUnit(yt_unit::PyObject, unit_string::String, dimensions::PyObject)
        unit_string = replace(unit_string, "**" => "^")
        new(yt_unit, unit_string, dimensions)
    end
end

function *(u::YTUnit, v::YTUnit)
    yt_unit = pycall(u.yt_unit["__mul__"], PyObject, v.yt_unit)
    YTUnit(yt_unit, pystring(yt_unit[:units]), yt_unit["units"][:dimensions])
end

function /(u::YTUnit, v::YTUnit)
    yt_unit = pycall(u.yt_unit["__truediv__"], PyObject, v.yt_unit)
    YTUnit(yt_unit, pystring(yt_unit[:units]), yt_unit["units"][:dimensions])
end

\(u::YTUnit, v::YTUnit) = /(v,u)

function /(u::Real, v::YTUnit)
    yt_unit = pycall(v.yt_unit["__rtruediv__"], PyObject, u)
    YTUnit(yt_unit, pystring(yt_unit[:units]), yt_unit["units"][:dimensions])
end

function ^(u::YTUnit, v::Integer)
    yt_unit = pycall(u.yt_unit["__pow__"], PyObject, v)
    YTUnit(yt_unit, pystring(yt_unit[:units]), yt_unit["units"][:dimensions])
end

function ^(u::YTUnit, v::Rational)
    yt_unit = pycall(u.yt_unit["__pow__"], PyObject, v)
    YTUnit(yt_unit, pystring(yt_unit[:units]), yt_unit["units"][:dimensions])
end

function ^(u::YTUnit, v::AbstractFloat)
    yt_unit = pycall(u.yt_unit["__pow__"], PyObject, v)
    YTUnit(yt_unit, pystring(yt_unit[:units]), yt_unit["units"][:dimensions])
end

function ==(u::YTUnit, v::YTUnit)
    pycall(u.yt_unit["units"]["__eq__"], PyAny, v.yt_unit["units"])
end

sqrt(u::YTUnit) = u^(1//2)
abs(u::YTUnit) = u
abs2(u::YTUnit) = u*u

show(io::IO, u::YTUnit) = print(io, u.unit_string)

# YTQuantity definition

struct YTQuantity{T<:Real}
    value::T
    units::YTUnit
end

function YTQuantity(value::T, units::String; registry=nothing) where T<:Real
    units = replace(units, "^" => "**")
    unitary_quan = pycall(bare_quan, PyObject, 1.0, units, registry)
    yt_units = YTUnit(unitary_quan,
                      pystring(unitary_quan[:units]),
                      unitary_quan["units"][:dimensions])
    YTQuantity{T}(value, yt_units)
end

function YTQuantity(ds, value::T, units::String) where T<:Real
    YTQuantity(value, units, registry=ds.ds["unit_registry"])
end

YTQuantity(value::Bool, units::String) = value
YTQuantity(value::Bool, units::YTUnit) = value
YTQuantity(value::Bool) = value
YTQuantity(value::T) where T<:Real = YTQuantity(value, "dimensionless")

function YTQuantity(yt_quantity::PyObject)
    yt_units = YTUnit(yt_quantity["unit_quantity"],
                      pystring(yt_quantity[:units]),
                      yt_quantity["units"][:dimensions])
    value = yt_quantity[:d][1]
    YTQuantity{typeof(value)}(value, yt_units)
end

# YTArray definition

struct YTArray{T, N} <: AbstractArray{T, N}
    value::Array{T, N}
    units::YTUnit
end

function YTArray(value::Array{T,N}, units::String; registry=nothing) where {T<:Real, N}
    units = replace(units, "^" => "**")
    unitary_quan = pycall(bare_quan, PyObject, 1.0, units, registry)
    yt_units = YTUnit(unitary_quan,
                      pystring(unitary_quan[:units]),
                      unitary_quan["units"][:dimensions])
    YTArray{T,N}(value, yt_units)
end

function YTArray(yt_array::PyObject)
    yt_units = YTUnit(yt_array["unit_quantity"],
                      pystring(yt_array[:units]),
                      yt_array["units"][:dimensions])
    value = Array(yt_array[:d])
    YTArray{eltype(value),ndims(value)}(value, yt_units)
end

function YTArray(ds, value::Array{T}, units::String) where T<:Real
    YTArray(value, units, registry=ds.ds["unit_registry"])
end
function YTArray(value::Real, units::String; registry=nothing)
    YTQuantity(value, units; registry=registry)
end
function YTArray(ds, value::Real, units::String)
    YTQuantity(value, units, registry=ds.ds["unit_registry"])
end
YTArray(value::Real, units::YTUnit) = YTQuantity(value, units)

YTArray(value::BitArray, units::String) = value
YTArray(value::BitArray, units::YTUnit) = value

YTArray(value::Array{T}) where T<:Real = YTArray(value, "dimensionless")
YTArray(value::Real) = YTQuantity(value, "dimensionless")

function YTArray(a::Array{YTQuantity})
    YTArray{typeof(a[1].value)}(convert(Array{typeof(a[1].value)}, a),
                                a[1].units)
end

eltype(a::YTArray) = eltype(a.value)

YTObject = Union{YTArray,YTQuantity}

function array_or_quan(a::PyObject)
    x = YTArray(a)
    if length(x) == 1
        return x[1]
    else
        return x
    end
end

struct YTUnitOperationError <: Exception
    a::YTObject
    b::YTObject
    op::Function
end

function showerror(io::IO, e::YTUnitOperationError)
    println(io,"The $(e.op) operator for YTArrays with units ")
    print(io,"($(e.a.units)) and ($(e.b.units)) is not well defined.")
end

# Macros

macro array_same_units(a,b,op)
    quote
        aa = $(esc(a))
        bb = $(esc(b))
        if (aa.units.dimensions)==(bb.units.dimensions)
            new_array = ($op)((aa.value),in_units(bb,(aa.units)).value)
            return YTArray(new_array, (aa.units))
        else
            throw(YTUnitOperationError(aa,bb,$op))
        end
    end
end

macro array_mult_op(a,b,op1,op2)
    quote
        aa = $(esc(a))
        bb = $(esc(b))
        units = ($op2)((aa.units), (bb.units))
        if units.dimensions == ytdims[:dimensionless]
            c = ($op1)((in_cgs(aa).value), (in_cgs(bb).value))
            return YTArray(c, "dimensionless")
        else
            c = ($op1)((aa.value), (bb.value))
            return YTArray(c, units)
        end
    end
end

# Copy

copy(q::YTQuantity) = YTQuantity(q.value, q.units)
copy(a::YTArray) = YTArray(copy(a.value), a.units)

# Conversions

convert(::Type{YTArray}, o::PyObject) = YTArray(o)
convert(::Type{YTQuantity}, o::PyObject) = YTQuantity(o)
convert(::Type{Array}, a::YTArray) = a.value
convert(::Type{Float64}, q::YTQuantity) = q.value
function convert(::Type{PyObject}, a::YTArray)
    units = replace(a.units.unit_string, "^" => "**")
    pycall(bare_array, PyObject, a.value, units,
           a.units.yt_unit["units"]["registry"],
           dtype=lowercase(string(typeof(a[1].value))))
end
function convert(::Type{PyObject}, a::YTQuantity)
    units = replace(a.units.unit_string, "^" => "**")
    pycall(bare_quan, PyObject, a.value, units,
           a.units.yt_unit["units"]["registry"],
           dtype=lowercase(string(typeof(a.value))))
end
convert(::Type{YTArray}, q::YTQuantity) = YTArray([q.value], q.units)
PyObject(a::YTObject) = convert(PyObject, a)

# Indexing, ranges (slicing)

getindex(a::YTArray, i::Int) = YTArray(getindex(a.value, i), a.units)
getindex(a::YTArray, idxs...) = YTArray(getindex(a.value, idxs...), a.units)

setindex!(a::YTArray, x::Array, idxs...) = setindex!(a.value, convert(typeof(a.value), x), idxs...)
setindex!(a::YTArray, x::Real, i::Int) = setindex!(a.value, convert(eltype(a), x), i)
setindex!(a::YTArray, x::Real, idxs...) = setindex!(a.value, convert(eltype(a), x), idxs...)

# Unit conversions

"""
    in_units(a::YTObject, units::String)

Return a new `YTObject` in these units.
"""
function in_units(a::YTObject, units::String)
    units = replace(units, "^" => "**")
    a.value*pycall(a.units.yt_unit["in_units"], YTQuantity, units)
end

"""
    in_cgs(a::YTObject)

Return a new `YTObject` in cgs units.
"""
function in_cgs(a::YTObject)
    a.value*pycall(a.units.yt_unit["in_cgs"], YTQuantity)
end

"""
    in_mks(a::YTObject)

Return a new `YTObject` in mks units.
"""
function in_mks(a::YTObject)
    a.value*pycall(a.units.yt_unit["in_mks"], YTQuantity)
end

"""
    in_base(a::YTObject; unit_system="cgs")

Return a new `YTObject` in the requested unit system.
"""
function in_base(a::YTObject; unit_system="cgs")
    a.value*pycall(a.units.yt_unit["in_base"], YTQuantity, unit_system)
end

"""
    convert_to_units(a::YTObject, units::String)

Convert the `YTObject` to these units.
"""
function convert_to_units(a::YTObject, units::String)
    units = replace(units, "^" => "**")
    new_unit = pycall(a.units.yt_unit["in_units"], YTQuantity, units)
    a.value *= new_unit.value
    a.units = new_unit.units
    return
end

"""
    convert_to_cgs(a::YTObject)

Convert the `YTObject` to cgs units.
"""
function convert_to_cgs(a::YTObject)
    new_unit = pycall(a.units.yt_unit["in_cgs"], YTQuantity)
    a.value *= new_unit.value
    a.units = new_unit.units
    return
end

"""
    convert_to_mks(a::YTObject)

Convert the `YTObject` to mks units.
"""
function convert_to_mks(a::YTObject)
    new_unit = pycall(a.units.yt_unit["in_mks"], YTQuantity)
    a.value *= new_unit.value
    a.units = new_unit.units
    return
end

convert_to_units(a::YTObject, units::YTUnit) = convert_to_units(a, units.unit_string)
convert_to_units(a::YTObject, b::YTObject) = convert_to_units(a, b.units)

in_units(a::YTObject, units::YTUnit) = in_units(a, units.unit_string)
in_units(a::YTObject, b::YTObject) = in_units(a, b.units)

# Broadcasting

broadcast(f, a::YTArray) = YTArray(broadcast(f, a.value), f(a.units))

# Arithmetic and comparisons

-(a::YTObject) = YTArray(-a.value, a.units)

# YTQuantity

for op = (:+, :-, :hypot, :(==), :(>=), :(<=), :≥, :≤, :<, :>)
    @eval ($op)(a::YTQuantity,b::YTQuantity) = @array_same_units(a,b,($op))
end

for op = (:*, :/, :\)
    @eval ($op)(a::YTQuantity,b::YTQuantity) = @array_mult_op(a,b,($op),($op))
end

*(a::YTQuantity, b::Real) = YTQuantity(b*a.value, a.units)
*(a::Real, b::YTQuantity) = *(b, a)

/(a::YTQuantity, b::Real) = *(a, 1.0/b)
\(a::YTQuantity, b::Real) = /(b,a)
/(a::Real, b::YTQuantity) = YTQuantity(a/b.value, 1/b.units)
\(a::Real, b::YTQuantity) = /(b,a)

^(a::YTQuantity, b::Integer) = YTQuantity(a.value^b, a.units^b)
^(a::YTQuantity, b::Real) = YTQuantity(a.value^b, a.units^b)

# YTQuantities and Arrays

*(a::YTQuantity, b::Array) = YTArray(b*a.value, a.units)
*(a::Array, b::YTQuantity) = *(b, a)
/(a::Array, b::YTQuantity) = *(a, 1.0/b)
\(a::YTQuantity, b::Array) = /(b,a)

# YTArray next

for op = (:+, :-, :hypot, :(==), :>=, :<=, :≥, :≤, :<, :>)
    @eval ($op)(a::YTArray,b::YTArray) = @array_same_units(a,b,($op))
end

for (op1, op2) in zip((:*, :/, :\), (:*, :/, :\))
    @eval ($op1)(a::YTArray,b::YTArray) = @array_mult_op(a,b,($op1),($op2))
end

==(a::YTArray, b::YTArray) = a.value == b.value && a.units == b.units
isequal(a::YTArray, b::YTArray) = ==(a, b)

# YTArrays and Reals

*(a::YTArray, b::Real) = YTArray(b*a.value, a.units)
*(a::Real, b::YTArray) = *(b, a)
/(a::YTArray, b::Real) = *(a, 1.0/b)
\(a::YTArray, b::Real) = /(b,a)

/(a::Real, b::YTArray) = YTArray(a./b.value, 1.0/b.units)
\(a::Real, b::YTArray) = /(b,a)

# YTArrays and Arrays

*(a::YTArray, b::Array) = YTArray(b.*a.value, a.units)
*(a::Array, b::YTArray) = *(b, a)
/(a::YTArray, b::Array) = *(a, 1.0./b)
/(a::Array, b::YTArray) = *(a, 1.0./b)
\(a::YTArray, b::Array) = /(b, a)
\(a::Array, b::YTArray) = /(b, a)

^(a::YTArray, b::Real) = YTArray(a.value.^b, a.units^b)

# YTArrays and YTQuantities

for op = (:+, :-, :hypot, :(==), :>=, :<=, :≥, :≤, :<, :>)
    @eval ($op)(a::YTQuantity,b::YTArray) = @array_same_units(a,b,($op))
    @eval ($op)(a::YTArray,b::YTQuantity) = @array_same_units(a,b,($op))
end

for op = (:*, :/)
    @eval ($op)(a::YTArray,b::YTQuantity) = @array_mult_op(a,b,($op),($op))
end

\(a::YTQuantity, b::YTArray) = /(b,a)
*(a::YTQuantity, b::YTArray) = *(b,a)

for op = (:+, :-, :hypot)
    @eval ($op)(a::YTObject,b::Real) = @array_same_units(a,YTQuantity(b,"dimensionless"),($op))
    @eval ($op)(a::Real,b::YTObject) = ($op)(b,a)
    @eval ($op)(a::YTObject,b::Array) = @array_same_units(a,YTArray(b,"dimensionless"),($op))
    @eval ($op)(a::Array,b::YTObject) = ($op)(b,a)
end

# Mathematical functions

sqrt(a::YTQuantity) = YTQuantity(sqrt(a.value), (a.units)^(1//2))

maximum(a::YTArray) = YTQuantity(maximum(a.value), a.units)
minimum(a::YTArray) = YTQuantity(minimum(a.value), a.units)

hypot(a::YTObject, b::YTObject, c::YTObject) = hypot(hypot(a,b), c)

abs(a::YTQuantity) = YTQuantity(abs(a.value), a.units)
abs2(a::YTQuantity) = YTQuantity(abs2(a.value), a.units*a.units)

for op = (:exp, :log, :log2, :log10, :log1p, :expm1,
          :sin, :cos, :tan, :sec, :csc, :cot, :sinh,
          :cosh, :tanh, :coth, :sech, :csch, :sinpi,
          :cospi, :asin, :acos, :atan)
    @eval ($op)(a::YTQuantity) = ($op)(a.value)
    @eval ($op)(a::YTUnit) = "dimensionless"
end

# Show

summary(a::YTArray) = string(size(a), " YTArray ($(a.units.unit_string))")

function print(io::IO, a::YTArray)
    print(io, "$(a.value) $(a.units)")
end

function print(a::YTArray)
    print(STDOUT,a)
end

function print(io::IO, q::YTQuantity)
    print(io, "$(q.value) $(q.units)")
end

function print(q::YTQuantity)
    print(STDOUT,q)
end

show(io::IO, q::YTQuantity) = print(io, "$(q.value) $(q.units)")

# Array methods

size(a::YTArray) = size(a.value)
size(a::YTArray, n::Integer) = size(a.value, n)

ndims(a::YTArray) = ndims(a.value)

sum(a::YTArray) = YTQuantity(sum(a.value), a.units)
sum(a::YTArray, dims) = YTArray(sum(a.value, dims), a.units)

cumsum(a::YTArray) = YTArray(cumsum(a.value), a.units)
cumsum(a::YTArray, dim::Integer) = YTArray(cumsum(a.value, dim), a.units)

accumulate(op, a::YTArray) = YTArray(accumulate(op, a.value), a.units)
accumulate(op, a::YTArray, axis::Integer) = YTArray(accumulate(op, a.value, axis), a.units)

diff(a::YTArray) = YTArray(diff(a.value), a.units)
diff(a::YTArray, dim::Integer) = YTArray(diff(a.value, dim), a.units)

mean(a::YTArray) = YTQuantity(mean(a.value), a.units)
mean(a::YTArray, region) = YTArray(mean(a.value, region), a.units)

std(a::YTArray) = YTQuantity(std(a.value), a.units)
std(a::YTArray, region) = YTArray(std(a.value, region), a.units)

stdm(a::YTArray, m::YTQuantity) = YTQuantity(stdm(a.value, in_units(m,a.units).value),
                                             a.units)

var(a::YTArray) = YTQuantity(var(a.value), a.units*a.units)
var(a::YTArray, region) = YTArray(var(a.value, region), a.units*a.units)

varm(a::YTArray, m::YTQuantity) = YTQuantity(varm(a.value, in_units(m,a.units).value),
                                             a.units*a.units)

median(a::YTArray) = YTQuantity(median(a.value), a.units)
middle(a::YTArray) = YTQuantity(middle(a.value), a.units)

middle(a::YTQuantity) = YTQuantity(middle(a.value), a.units)
middle(a::YTQuantity, b::YTQuantity) = YTQuantity(middle(a.value, in_units(b,
                                                  a.units).value), a.units)

quantile(a::YTArray,q::AbstractArray) = YTArray(quantile(a.value, q), a.units)
quantile(a::YTArray,q::Number) = YTArray(quantile(a.value, q), a.units)

# To/from HDF5

"""
    write_hdf5(a::YTArray, filename::String; dataset_name=nothing,
               info=nothing)

Write a `YTArray` to an HDF5 file.

# Parameters

* `a::YTArray`: The `YTArray` to write to the file.
* `filename::String`: The file to write to.
* `dataset_name::String=nothing`: The name of the HDF5 dataset to write the data
  into.
* `dataset_name::String=nothing`: The name of the HDF5 group to write the data
  into.
* `info::Dict{String,Any}=nothing`: A dictionary of keys and values to write to
  the file, associated with this array, that will be stored in the dataset
  attributes.

# Examples
```julia
julia> using YT
julia> a = YTArray(rand(10), "cm/s")
juila> write_hdf5(a, "my_file.h5", dataset_name="velocity")
```
"""
function write_hdf5(a::YTArray, filename::String; dataset_name=nothing,
                    info=nothing)
    arr = PyObject(a)
    arr[:write_hdf5](filename; dataset_name=dataset_name, info=info)
end

"""
    from_hdf5(filename::String; dataset_name=nothing, group_name=nothing)

Read a `YTArray` from an HDF5 file.

# Parameters

* `filename::String`: The file to read from.
* `dataset_name::String=nothing`: The name of the HDF5 dataset to read the data
  from.
* `group_name::String=nothing`: The name of the HDF5 group to read the data
  from.

# Examples
```julia
julia> using YT
juila> v = from_hdf5("my_file.h5", dataset_name="velocity", group_name="fields")
```
"""
function from_hdf5(filename::String; dataset_name=nothing, group_name=nothing)
    YTArray(pycall(bare_array["from_hdf5"], PyObject, filename;
                   dataset_name=dataset_name, group_name=group_name))
end

# Unit equivalencies

"""
    to_equivalent(a::YTObject, unit::String, equiv::String; args...)

Convert a `YTArray` or a `YTQuantity` to an equivalent quantity. For example,
one may wish to convert a temperature to an equivalent energy kT, or a
wavelength to a frequency, etc. For more information see the YT documentation.

# Arguments

* `a::YTObject`: A `YTArray` or `YTQuantity` to convert.
* `unit::String`: The unit to convert to.
* `equiv::String`: The equivalence to use.

# Examples
```julia
julia> using YT
julia> a = YTArray(rand(10), "keV")
julia> to_equivalent(a, "K", "thermal")
```
"""
function to_equivalent(a::YTObject, unit::String, equiv::String; args...)
    arr = PyObject(a)
    unit = replace(unit, "^" => "**")
    equ = pycall(arr["to_equivalent"], PyObject, unit, equiv; args...)
    array_or_quan(equ)
end

"""
    list_equivalencies(a::YTObject)

List the possible equivalencies for a given YTObject.
"""
function list_equivalencies(a::YTObject)
    arr = PyObject(a)
    arr[:list_equivalencies]()
end

"""
    has_equivalent(a::YTObject, equiv::String)

Check if a given `YTObject` has a given equivalence.
"""

function has_equivalent(a::YTObject, equiv::String)
    arr = PyObject(a)
    arr[:has_equivalent](equiv)
end

# Ones, Zeros, etc.

ones(a::YTArray) = YTArray(ones(a.value), a.units)
zeros(a::YTArray) = YTArray(zeros(a.value), a.units)
eye(a::YTArray) = YTArray(eye(a.value), a.units)

fill(a::YTQuantity, dims::Tuple{Vararg{Int64}}) = YTArray(fill(a.value,dims), a.units)
fill(a::YTQuantity, dims::Integer...) = YTArray(fill(a.value,dims), a.units)

length(a::YTQuantity) = length(a.value)

end
