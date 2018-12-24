module ChartParsers

export Chart, parse, Grammar, expand, complete_parses

abstract type Strategy end
struct BottomUp <: Strategy end
struct TopDown <: Strategy end

# include("FixedCapacityVectors.jl")
# using .FixedCapacityVectors

const Rule = Pair{Symbol, Vector{Symbol}}
lhs(r::Rule) = first(r)
rhs(r::Rule) = last(r)

struct Arc
    start::Int
    stop::Int
    rule::Rule
    constituents::Vector{Union{Arc, String}}
end

rule(arc::Arc) = arc.rule
head(arc::Arc) = lhs(rule(arc))
completions(arc::Arc) = length(arc.constituents)
constituents(arc::Arc) = arc.constituents
isactive(arc::Arc) = completions(arc) < length(rhs(rule(arc)))
function next_needed(arc::Arc)
    @assert isactive(arc)
    rhs(rule(arc))[completions(arc) + 1]
end

function Base.show(io::IO, arc::Arc)
    constituents = copy(rhs(rule(arc)))
    insert!(constituents, completions(arc) + 1, :.)
    print(io, "<$(arc.start), $(arc.stop), $(head(arc)) -> $(join(constituents, ' '))>")
end


function Base.hash(arc::Arc, h::UInt)
    h = hash(arc.start, h)
    h = hash(arc.stop, h)
    h = hash(objectid(arc.rule), h)
    for c in arc.constituents
        h = hash(objectid(c), h)
    end
    h
end

function Base.:(==)(a1::Arc, a2::Arc)
    a1.start == a2.start || return false
    a1.stop == a2.stop || return false
    a1.rule === a2.rule || return false
    length(a1.constituents) == length(a2.constituents) || return false
    for i in eachindex(a1.constituents)
        a1.constituents[i] === a2.constituents[i] || return false
    end
    true
end

function Base.:*(a1::Arc, a2::Arc)
    @assert isactive(a1) && !isactive(a2)
    @assert next_needed(a1) == head(a2)
    Arc(a1.start, a2.stop, a1.rule, vcat(a1.constituents, a2))
end

function Base.:+(a1::Arc, a2::Arc)
    if isactive(a1) && !isactive(a2)
        a1 * a2
    elseif !isactive(a1) && isactive(a2)
        a2 * a1
    else
        throw(ArgumentError("Can only combine an active and an inactive edge"))
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


struct Chart
    num_tokens::Int
    active::Dict{Symbol, Vector{Set{Arc}}} # organized by next needed constituent then by stop
    inactive::Dict{Symbol, Vector{Set{Arc}}} # organized by head then by start
end

num_tokens(chart::Chart) = chart.num_tokens

Chart(num_tokens) = Chart(num_tokens,
                          Dict{Symbol, Vector{Set{Arc}}}(),
                          Dict{Symbol, Vector{Set{Arc}}}())

function storage(chart::Chart, active::Bool, symbol::Symbol, node::Integer)
    if active
        d = chart.active
    else
        d = chart.inactive
    end
    v = get!(d, symbol) do
        [Set{Arc}() for _ in 0:num_tokens(chart)]
    end
    v[node + 1]
end


function storage(chart::Chart, arc::Arc)
    if isactive(arc)
        i = arc.stop
        s = next_needed(arc)
        return storage(chart, true, s, i)
    else
        i = arc.start
        s = head(arc)
        return storage(chart, false, s, i)
    end
end

function mates(chart::Chart, candidate::Arc)
    if isactive(candidate)
        i = candidate.stop
        s = next_needed(candidate)
        return storage(chart, false, s, i)
    else
        i = candidate.start
        s = head(candidate)
        return storage(chart, true, s, i)
    end
end

function Base.push!(chart::Chart, arc::Arc)
    push!(storage(chart, arc), arc)
end

function Base.in(arc::Arc, chart::Chart)
    arc ∈ storage(chart, arc)
end

complete_parses(chart::Chart) = filter(storage(chart, false, :S, 0)) do arc
    arc.stop == num_tokens(chart)
end

struct Grammar
    productions::Vector{Rule}
    words::Dict{String, Vector{Symbol}}
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

function predict!(agenda::Agenda, chart::Chart, candidate::Arc, grammar::Grammar, ::BottomUp)
    if !isactive(candidate)
        for rule in grammar.productions
            if first(rhs(rule)) == head(candidate)
                hypothesis = Arc(candidate.start,
                                 candidate.start,
                                 rule,
                                 [])
                if hypothesis ∉ chart
                    pushfirst!(agenda, hypothesis)
                end
            end
        end
    end
end

function predict!(agenda::Agenda, chart::Chart, candidate::Arc, grammar::Grammar, ::TopDown)
    if isactive(candidate)
        for rule in grammar.productions
            if lhs(rule) == next_needed(candidate)
                hypothesis = Arc(candidate.stop, candidate.stop, rule, [])
                if hypothesis ∉ chart
                    pushfirst!(agenda, hypothesis)
                end
            end
        end
    end
end

function parse(tokens, grammar, strategy=BottomUp())
    chart = initial_chart(tokens, grammar, strategy)
    agenda = initial_agenda(tokens, grammar, strategy)

    while !isempty(agenda)
        candidate = popfirst!(agenda)
        push!(chart, candidate)

        for mate in mates(chart, candidate)
            combined = candidate + mate
            if combined ∉ chart
                pushfirst!(agenda, combined)
            end
        end
        predict!(agenda, chart, candidate, grammar, strategy)
        @show agenda
    end
    chart
end


end # module
