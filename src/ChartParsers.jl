module ChartParsers

using DataStructures: SortedSet

export Arc,
       lhs,
       rhs,
       rule,
       constituents,
       ChartParser,
       AbstractGrammar,
       is_complete,
       BottomUp,
       TopDown,
       SimpleRule,
       SimpleGrammar,
       TerminalWeightedGrammar

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
