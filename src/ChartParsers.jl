module ChartParsers

export Chart, parse, Grammar, expand, complete_parses

abstract type Strategy end
struct BottomUp <: Strategy end
struct TopDown <: Strategy end

# include("FixedCapacityVectors.jl")
# using .FixedCapacityVectors
function push(x::AbstractVector{T}, y::T)
    result = copy(x)
    push!(result, y)
    result
end

head(r::Pair) = first(r)
arguments(r::Pair) = last(r)

const SymbolID = Int
const RuleID = Pair{SymbolID, Vector{SymbolID}}

struct Arc
    start::Int
    stop::Int
    rule::Any
    rule_id::RuleID
    constituents::Vector{Arc{R}}
end

rule(arc::Arc) = arc.rule
rule_id(arc::Arc) = arc.rule_id
head(arc::Arc) = lhs(rule_id(arc))
completions(arc::Arc) = length(arc.constituents)
constituents(arc::Arc) = arc.constituents
isactive(arc::Arc) = completions(arc) < length(rhs(rule_id(arc)))
function next_needed(arc::Arc)
    @assert isactive(arc)
    rhs(rule_id(arc))[completions(arc) + 1]
end

function Base.show(io::IO, arc::Arc)
    constituents = copy(rhs(rule(arc)))
    insert!(constituents, completions(arc) + 1, :.)
    print(io, "<$(arc.start), $(arc.stop), $(lhs(rule(arc))) -> $(join(constituents, ' '))>")
end


function Base.hash(arc::Arc, h::UInt)
    h = hash(arc.start, h)
    h = hash(arc.stop, h)
    h = hash(rule_id(arc), h)
    for c in arc.constituents
        h = hash(objectid(c), h)
    end
    h
end

function Base.:(==)(a1::Arc, a2::Arc)
    a1.start == a2.start || return false
    a1.stop == a2.stop || return false
    a1.rule_id === a2.rule_id || return false
    length(a1.constituents) == length(a2.constituents) || return false
    for i in eachindex(a1.constituents)
        a1.constituents[i] === a2.constituents[i] || return false
    end
    true
end

function Base.:*(a1::Arc, a2::Arc)
    @assert isactive(a1) && !isactive(a2)
    @assert next_needed(a1) == head(a2)
    Arc(a1.start, a2.stop, a1.rule, a1.rule_id, push(constituents(a1), a2))
end

function Base.:+(a1::Arc, a2::Arc)
    if isactive(a1) && !isactive(a2)
        a1 * a2
    elseif !isactive(a1) && isactive(a2)
        a2 * a1
    else
        throw(ArgumentError("Can only combine an active and an inactive arc"))
    end
end

expand(arc::Arc) = expand(stdout, arc)

function expand(io::IO, arc::Arc, indentation=0)
    # print(io, repeat(" ", indentation))
    print(io, "(", head(arc))
    arguments = rhs(rule(arc))
    for i in eachindex(arguments)
        if length(arguments) > 1
            print(io, "\n", repeat(" ", indentation + 2))
        else
            print(io, " ")
        end
        if i > completions(arc)
            print(io, "(", arguments[i], ")")
        else
            constituent = constituents(arc)[i]
            if constituent isa String
                print(io, "\"$constituent\"")
            else
                expand(io, constituent, indentation + 2)
            end
        end
    end
    print(io, ")")
end

const ChartElement = Vector{Arc}

struct Chart
    num_tokens::Int
    active::Matrix{ChartElement} # organized by next needed constituent then by stop
    inactive::Matrix{ChartElement} # organized by head then by start
end



num_tokens(chart::Chart) = chart.num_tokens

Chart(num_tokens) = Chart(num_tokens,
                          Matrix{ChartElement}(),
                          Matrix{ChartElement}())

function storage(chart::Chart, arc::Arc)
    if isactive(arc)
        chart.active[next_needed(arc), arc.stop + 1]
    else
        chart.inactive[head(arc), arc.start + 1]
    end
end

function mates(chart::Chart, candidate::Arc)
    if isactive(candidate)
        chart.inactive[next_needed(candidate), candidate.stop + 1]
    else
        chart.active[head(candidate), candidate.start + 1]
    end
end

function Base.push!(chart::Chart, arc::Arc)
    @assert arc ∉ storage(chart, arc)
    push!(storage(chart, arc), arc)
end

function Base.in(arc::Arc, chart::Chart)
    arc ∈ storage(chart, arc)
end

function inactive_arcs(symbol::SymbolID, start::Integer, stop::Integer)
    filter(chart.inactive[symbol, start + 1]) do arc
        arc.stop == stop
    end
end



complete_parses(chart::Chart) = filter(storage(chart, false, :S, 0)) do arc
    arc.stop == num_tokens(chart)
end

struct Grammar
    productions::Vector{Rule}
    start_symbol
end

const Agenda = Vector{Arc}

function initial_chart(tokens, grammar, ::BottomUp)
    Chart(length(tokens))
end

function initial_chart(tokens, grammar, ::TopDown)
    chart = Chart(length(tokens))
    for (i, token) in enumerate(tokens)
        for head in grammar.words[token]
            push!(chart, Arc(i - 1, i, head => [Symbol("#token")], [string(token)]))
        end
    end
    chart
end

function initial_agenda(tokens, grammar, ::BottomUp)
    agenda = Arc[]

    for (i, token) in enumerate(tokens)
        for head in grammar.words[token]
            push!(agenda, Arc(i - 1, i, head => [Symbol("#token")], [string(token)]))
        end
    end
    agenda
end

function initial_agenda(tokens, grammar, ::TopDown)
    agenda = Arc[]

    for rule in grammar.productions
        if lhs(rule) == :S  # TODO get start symbol from grammar
            push!(agenda, Arc(0, 0, rule, []))
        end
    end
    agenda
end

function predict!(agenda::Agenda, chart::Chart, candidate::Arc, grammar::Grammar, predictions::Set{Tuple{Symbol, Int}}, ::BottomUp)
    key = (head(candidate), candidate.start)
    if !isactive(candidate) && key ∉ predictions
        push!(predictions, key)
        for rule in grammar.productions
            if first(rhs(rule)) == head(candidate)
                hypothesis = Arc(candidate.start,
                                 candidate.start,
                                 rule,
                                 [])
                if hypothesis in agenda || hypothesis in chart
                    @show hypothesis
                    error("duplicate hypothesis")
                end
                pushfirst!(agenda, hypothesis)
            end
        end
    end
end

function predict!(agenda::Agenda, chart::Chart, candidate::Arc, grammar::Grammar, predictions::Set{Tuple{Symbol, Int}}, ::TopDown)
    if isactive(candidate)
        key = (next_needed(candidate), candidate.stop)
        if key ∉ predictions
            push!(predictions, key)
            for rule in grammar.productions
                if lhs(rule) == next_needed(candidate)
                    hypothesis = Arc(candidate.stop, candidate.stop, rule, [])
                    if hypothesis in agenda || hypothesis in chart
                        @show hypothesis
                        error("duplicate hypothesis")
                    end
                    pushfirst!(agenda, hypothesis)
                end
            end
        end
    end
end

function parse(tokens, grammar, strategy=BottomUp())
    chart = initial_chart(tokens, grammar, strategy)
    agenda = initial_agenda(tokens, grammar, strategy)
    predictions = Set{Tuple{Symbol, Int}}()

    while !isempty(agenda)
        candidate = popfirst!(agenda)
        if candidate ∈ chart
            @show candidate
            error("duplicate candidate")
        end
        push!(chart, candidate)

        for mate in mates(chart, candidate)
            combined = candidate + mate
            if combined in chart || combined in agenda
                @show combined
                error("duplicate from fundamental rule")
            end
            # if combined ∉ chart
                pushfirst!(agenda, combined)
            # end
        end
        predict!(agenda, chart, candidate, grammar, predictions, strategy)
        @show agenda
    end
    chart
end


end # module
