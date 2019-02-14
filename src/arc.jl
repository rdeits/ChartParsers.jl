abstract type AbstractArc{Rule} end

struct Arc{Rule} <: AbstractArc{Rule}
    start::Int
    stop::Int
    rule::Rule
    constituents::Vector{Arc{Rule}}
    score::Float64
end

Arc(start, stop, rule::R, constituents, score) where {R} = Arc{R}(start, stop, rule, constituents, score)

start(arc::Arc) = arc.start
stop(arc::Arc) = arc.stop
rule(arc::Arc) = arc.rule
score(arc::Arc) = arc.score
constituents(arc::Arc) = arc.constituents

num_constituents(arc::AbstractArc) = length(constituents(arc))
head(arc::AbstractArc) = lhs(rule(arc))

abstract type WrappedArc{Rule} <: AbstractArc{Rule} end

struct PassiveArc{Rule} <: WrappedArc{Rule}
    inner::Arc{Rule}
end

struct ActiveArc{Rule} <: WrappedArc{Rule}
    inner::Arc{Rule}
end

inner(arc::WrappedArc) = arc.inner

start(arc::WrappedArc) = start(inner(arc))
stop(arc::WrappedArc) = stop(inner(arc))
rule(arc::WrappedArc) = rule(inner(arc))
score(arc::WrappedArc) = score(inner(arc))
constituents(arc::WrappedArc) = constituents(inner(arc))

is_finished(arc::ActiveArc) = num_constituents(arc) == length(rhs(rule(arc)))
next_needed(arc::ActiveArc) = rhs(rule(arc))[num_constituents(arc) + 1]
passive(arc::ActiveArc) = PassiveArc(inner(arc))

function Base.show(io::IO, arc::AbstractArc)
    constituents = Vector{Any}(collect(rhs(rule(arc))))
    insert!(constituents, num_constituents(arc) + 1, :.)
    print(io, "<$(start(arc)), $(stop(arc)), $(lhs(rule(arc))) -> $(join(constituents, ' '))>")
end

"""
    combine(active::ActiveArc, passive::PassiveArc)

Combine two arcs according to the Fundamental Rule.
"""
function combine(a1::ActiveArc, a2::PassiveArc)
    new_constituents = push(constituents(a1), inner(a2))
    # Geometric mean
    new_score = reduce((s, arc) -> s * score(arc), new_constituents, init=1.0) / length(new_constituents)
    ActiveArc(Arc(start(a1), stop(a2), rule(a1), new_constituents, new_score))
end

combine(a1::PassiveArc, a2::ActiveArc) = combine(a2, a1)

