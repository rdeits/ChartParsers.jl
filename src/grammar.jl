abstract type AbstractGrammar{R} end

chart_key(g::AbstractGrammar{R}) where {R} = chart_key(R)
rule_type(g::AbstractGrammar{R}) where {R} = R

function productions end
function terminal_productions end
function start_symbol end

const SimpleRule = Pair{Symbol, Vector{Symbol}}

struct SimpleGrammar <: AbstractGrammar{SimpleRule}
    productions::Vector{SimpleRule}
    categories::Dict{String, Vector{Symbol}}
    start::Symbol
end

productions(g::SimpleGrammar) = g.productions
start_symbol(g::SimpleGrammar) = g.start

function terminal_productions(g::SimpleGrammar, tokens::AbstractVector{<:AbstractString})
    R = rule_type(g)
    result = Arc{R}[]
    for (i, token) in enumerate(tokens)
        for category in get(g.categories, token, Symbol[])
            push!(result, Arc{R}(i - 1, i, category => Symbol[], Arc{R}[], 1.0))
        end
    end
    result
end

struct TerminalWeightedGrammar <: AbstractGrammar{SimpleRule}
    productions::Vector{SimpleRule}
    categories::Dict{String, Vector{Pair{Symbol, Float64}}}
    start::Symbol
end

productions(g::TerminalWeightedGrammar) = g.productions
start_symbol(g::TerminalWeightedGrammar) = g.start

function terminal_productions(g::TerminalWeightedGrammar, tokens::AbstractVector{<:AbstractString})
    R = rule_type(g)
    result = Arc{R}[]
    for (i, token) in enumerate(tokens)
        for (category, weight) in get(g.categories, token, Symbol[])
            push!(result, Arc{R}(i - 1, i, category => Symbol[], Arc{R}[], weight))
        end
    end
    result
end

