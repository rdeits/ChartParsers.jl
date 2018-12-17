module FixedCapacityVectors

export FixedCapacityVector

struct FixedCapacityVector{N, T} <: AbstractVector{T}
    data::NTuple{N, T}
    length::Int
end

Base.size(f::FixedCapacityVector) = (f.length,)
@inline function Base.getindex(f::FixedCapacityVector, i::Integer)
    @boundscheck i >= 0 && i <= f.length || throw(BoundsError())
    f.data[i]
end

@generated function Base.convert(::Type{FixedCapacityVector{N, T}}, v::AbstractVector) where {N, T}
    quote
        firstindex(v) == 1 || throw(ArgumentError("Vector v must use 1-based inexing"))
        length(v) <= N || throw(ArgumentError("Vector v is too long ($(length(v))) for fixed-capacity vector with capatcity $N"))
        len = length(v)
        data = $(Expr(:tuple, [:(convert(T, v[($i <= len ? $i : len)])) for i in 1:N]...))
        FixedCapacityVector(data, length(v))
    end
end

end
