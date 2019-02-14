abstract type AbstractGrammar{R} end

chart_key(g::AbstractGrammar{R}) where {R} = chart_key(R)
rule_type(g::AbstractGrammar{R}) where {R} = R

function productions end
function terminal_productions end
function start_symbol end

struct SimpleGrammar <: AbstractGrammar{Pair{Symbol, Vector{Symbol}}}
    productions::Vector{Pair{Symbol, Vector{Symbol}}}
    categories::Dict{String, Vector{Symbol}}
    start::Symbol
end

productions(g::SimpleGrammar) = g.productions
start_symbol(g::SimpleGrammar) = g.start

function terminal_productions(g::SimpleGrammar, tokens::AbstractVector{<:AbstractString})
    result = ArcData{rule_type(g)}[]
    for (i, token) in enumerate(tokens)
        for category in get(g.categories, token, Symbol[])
            push!(result, ArcData{rule_type(g)}(i - 1, i, category => Symbol[]))
        end
    end
    result
end
