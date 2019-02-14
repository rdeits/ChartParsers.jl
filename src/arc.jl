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

