module ChartParsers

using Base.Iterators: Iterators

export SimpleGrammar, ArcData, ChartParser, is_complete, BottomUp, TopDown

abstract type AbstractStrategy end
struct BottomUp <: AbstractStrategy end
struct TopDown <: AbstractStrategy end

function push(x::AbstractVector{T}, y::T) where {T}
    result = copy(x)
    push!(result, y)
    result
end

function push(x::NTuple{N, T}, y::T) where {N, T}
    tuple(x..., y)
end

abstract type AbstractArc{Rule} end

struct ArcData{Rule}
    start::Int
    stop::Int
    rule::Rule
end

start(arc::ArcData) = arc.start
stop(arc::ArcData) = arc.stop
rule(arc::ArcData) = arc.rule

struct PassiveArc{Rule} <: AbstractArc{Rule}
    data::ArcData{Rule}
    constituents::Vector{PassiveArc{Rule}}
end

struct ActiveArc{Rule} <: AbstractArc{Rule}
    data::ArcData{Rule}
    constituents::Vector{PassiveArc{Rule}}
end

PassiveArc(data::ArcData{R}) where {R} = PassiveArc{R}(data, Vector{PassiveArc{R}}())
ActiveArc(data::ArcData{R}) where {R} = ActiveArc{R}(data, Vector{PassiveArc{R}}())

data(arc::AbstractArc) = arc.data
start(arc::AbstractArc) = start(data(arc))
stop(arc::AbstractArc) = stop(data(arc))
rule(arc::AbstractArc) = rule(data(arc))

num_constituents(arc::AbstractArc) = length(arc.constituents)
constituents(arc::AbstractArc) = arc.constituents
is_finished(arc::ActiveArc) = num_constituents(arc) == length(rhs(rule(arc)))

chart_key(::Type{<:Pair{T}}) where {T} = T
rhs(p::Pair) = last(p)
lhs(p::Pair) = first(p)

head(arc::AbstractArc) = lhs(rule(arc))
next_needed(arc::ActiveArc) = rhs(rule(arc))[num_constituents(arc) + 1]

passive(arc::ActiveArc) = PassiveArc(data(arc), constituents(arc))

function Base.show(io::IO, arc::AbstractArc)
    constituents = Vector{Any}(collect(rhs(rule(arc))))
    insert!(constituents, num_constituents(arc) + 1, :.)
    print(io, "<$(start(arc)), $(stop(arc)), $(lhs(rule(arc))) -> $(join(constituents, ' '))>")
end

combine(a1::ActiveArc, a2::PassiveArc) = ActiveArc(ArcData(start(a1), stop(a2), rule(a1)), push(constituents(a1), a2))
combine(a1::PassiveArc, a2::ActiveArc) = combine(a2, a1)

struct Chart{R, T}
    num_tokens::Int
    active::Dict{T, Vector{Vector{ActiveArc{R}}}} # organized by next needed constituent then by stop
    passive::Dict{T, Vector{Vector{PassiveArc{R}}}} # organized by head then by start
end

Chart{R, T}(num_tokens::Integer) where {R, T} =
    Chart(num_tokens, Dict{T, Vector{Vector{ActiveArc{R}}}}(),
                Dict{T, Vector{Vector{PassiveArc{R}}}}())

num_tokens(chart::Chart) = chart.num_tokens

function _active_storage(chart::Chart{R, T}, next_needed::T, stop::Integer) where {R, T}
    v = get!(chart.active, next_needed) do
        [Vector{ActiveArc{R}}() for _ in 0:num_tokens(chart)]
    end
    v[stop + 1]
end

function _passive_storage(chart::Chart{R, T}, head::T, start::Integer) where {R, T}
    v = get!(chart.passive, head) do
        [Vector{PassiveArc{R}}() for _ in 0:num_tokens(chart)]
    end
    v[start + 1]
end

storage(chart::Chart, arc::ActiveArc) = _active_storage(chart, next_needed(arc), stop(arc))
storage(chart::Chart, arc::PassiveArc) = _passive_storage(chart, head(arc), start(arc))

mates(chart::Chart, candidate::ActiveArc) = _passive_storage(chart, next_needed(candidate), stop(candidate))
mates(chart::Chart, candidate::PassiveArc) = _active_storage(chart, head(candidate), start(candidate))

function Base.push!(chart::Chart, arc::AbstractArc)
    push!(storage(chart, arc), arc)
end

Base.in(arc::AbstractArc, chart::Chart) = arc ∈ storage(chart, arc)


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

function initial_chart(tokens, grammar::AbstractGrammar, ::BottomUp)
    chart = Chart{rule_type(grammar), chart_key(grammar)}(length(tokens))
end

function initial_chart(tokens, grammar::AbstractGrammar{R}, ::TopDown) where {R}
    chart = Chart{R, chart_key(grammar)}(length(tokens))
    for arc_data in terminal_productions(grammar, tokens)
        push!(chart, PassiveArc(arc_data))
    end
    chart
end

const Agenda{R} = Vector{ActiveArc{R}}

function initial_agenda(tokens, grammar::AbstractGrammar{R}, ::BottomUp) where {R}
    agenda = Agenda{R}()
    for arc_data in terminal_productions(grammar, tokens)
        push!(agenda, ActiveArc(arc_data))
    end
    agenda
end

function initial_agenda(tokens, grammar::AbstractGrammar{R}, ::TopDown) where {R}
    agenda = Agenda{R}()
    for rule in productions(grammar)
        if lhs(rule) == start_symbol(grammar)
            push!(agenda, ActiveArc(ArcData(0, 0, rule)))
        end
    end
    agenda
end

struct PredictionCache{T}
    predictions::Set{Tuple{T, Int}}
end

PredictionCache{T}() where {T} = PredictionCache(Set{Tuple{T, Int}}())

"""
Returns `true` if the key was added, `false` otherwise.
"""
function maybe_push!(p::PredictionCache{T}, key::Tuple{T, Int}) where {T}
    # TODO: this can probably be done without two Set lookup operations
    if key in p.predictions
        return false
    else
        push!(p.predictions, key)
        return true
    end
end

struct ChartParser{R, G <: AbstractGrammar{R}, S <: AbstractStrategy}
    tokens::Vector{String}
    grammar::G
    strategy::S
end

ChartParser(tokens::AbstractVector{<:AbstractString}, grammar::G, strategy::S=BottomUp()) where {R, G <: AbstractGrammar{R}, S <: AbstractStrategy} = ChartParser{R, G, S}(tokens, grammar, strategy)

struct ChartParserState{R, T}
    chart::Chart{R, T}
    agenda::Agenda{R}
    prediction_cache::PredictionCache{T}
end

# function find_parses(chart::Chart, start::Integer, stop::Integer, head)
#     filter(_passive_storage(chart, head, start)) do arc
#         stop(arc) == stop
#     end
# end

function initial_state(parser::ChartParser{R}) where R
    chart = initial_chart(parser.tokens, parser.grammar, parser.strategy)
    agenda = initial_agenda(parser.tokens, parser.grammar, parser.strategy)
    prediction_cache = PredictionCache{chart_key(R)}()
    ChartParserState(chart, agenda, prediction_cache)
end

function Base.iterate(parser::ChartParser{R, T}, state=initial_state(parser)) where {R, T}
    while !isempty(state.agenda)
        @show state.agenda
        candidate = pop!(state.agenda)
        if is_finished(candidate)
            arc = passive(candidate)
            update!(state, parser, arc)
            return (arc, state)
        else
            update!(state, parser, candidate)
        end
    end
    return nothing
end

Base.IteratorSize(::Type{<:ChartParser}) = Base.SizeUnknown()
Base.eltype(::Type{<:ChartParser{R}}) where {R} = PassiveArc{R}

function is_complete(arc::PassiveArc, parser::ChartParser)
    start(arc) == 0 && stop(arc) == length(parser.tokens) && head(arc) == start_symbol(parser.grammar)
end

is_complete(parser::ChartParser) = arc -> is_complete(arc, parser)

function update!(state::ChartParserState, parser::ChartParser, candidate::AbstractArc)
    push!(state.chart, candidate)
    for mate in mates(state.chart, candidate)
        push!(state.agenda, combine(candidate, mate))
    end
    predict!(state.agenda, state.chart, candidate, parser.grammar, state.prediction_cache, parser.strategy)
end

function predict!(agenda::Agenda, chart::Chart, candidate::ActiveArc,
                  grammar::AbstractGrammar{R}, prediction_cache::PredictionCache,
                  ::TopDown) where {R}
    is_new = maybe_push!(prediction_cache, (next_needed(candidate), stop(candidate)))
    if is_new
        for rule in productions(grammar)
            if lhs(rule) === next_needed(candidate)
                push!(agenda, ActiveArc(ArcData(stop(candidate), stop(candidate), rule)))
            end
        end
    end
end

function predict!(agenda::Agenda, chart::Chart, candidate::PassiveArc,
                  grammar::AbstractGrammar{R}, prediction_cache::PredictionCache,
                  ::TopDown) where {R}
    # Nothing to do here
end

function predict!(agenda::Agenda, chart::Chart, candidate::PassiveArc,
                  grammar::AbstractGrammar{R}, prediction_cache::PredictionCache,
                  ::BottomUp) where {R}
    is_new = maybe_push!(prediction_cache, (head(candidate), start(candidate)))
    if is_new
        for rule in productions(grammar)
            if first(rhs(rule)) === head(candidate)
                push!(agenda, ActiveArc(ArcData(start(candidate), start(candidate), rule)))
            end
        end
    end
end

function predict!(agenda::Agenda, chart::Chart, candidate::ActiveArc,
                  grammar::AbstractGrammar, prediction_cache::PredictionCache,
                  ::BottomUp)
    # Nothing to do here
end

end # module
