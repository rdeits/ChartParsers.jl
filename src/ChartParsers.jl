module ChartParsers

export SimpleGrammar, ArcData, ChartParser, is_complete, BottomUp, TopDown

function push(x::AbstractVector{T}, y::T) where {T}
    result = copy(x)
    push!(result, y)
    result
end

function push(x::NTuple{N, T}, y::T) where {N, T}
    tuple(x..., y)
end

include("arc.jl")
include("grammar.jl")
include("chart.jl")
include("parser.jl")

end # module
