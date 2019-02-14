using Test
using ChartParsers
using ChartParsers: ActiveArc, PassiveArc, rule, start, stop, constituents, Chart, combine, head, AbstractGrammar

@testset "arc in chart detection" begin
    R = Pair{Symbol, Vector{Symbol}}
    chart = Chart{R, Symbol}(2)
    a1 = PassiveArc(Arc(0, 1, :NP => Symbol[], [], 1))
    a2 = ActiveArc(Arc(0, 0, :S => [:NP, :VP], [], 1))
    a3 = combine(a2, a1)

    @test a1 ∉ chart
    @test a2 ∉ chart
    @test a3 ∉ chart
    push!(chart, a1)
    @test a1 ∈ chart
    @test a2 ∉ chart
    @test a3 ∉ chart
    push!(chart, a2)
    @test a1 ∈ chart
    @test a2 ∈ chart
    @test a3 ∉ chart
    push!(chart, a3)
    @test a1 ∈ chart
    @test a2 ∈ chart
    @test a3 ∈ chart
end

@testset "Example from nlp-with-prolog" begin
    # example taken from http://cs.union.edu/~striegnk/courses/nlp-with-prolog/html/node71.html#l9.sec.bottomup

    grammar = SimpleGrammar([
            :S => [:NP, :VP, :PP],
            :S => [:NP, :VP],
            :NP => [:PN],
            :VP => [:IV],
            :PP => [:P, :NP],
        ], Dict(
            "mia" => [:PN],
            "danced" => [:IV]
        ), :S)

    tokens = split("mia danced")

    @testset "BottomUp" begin
        parser = ChartParser(tokens, grammar, BottomUp())
        parses = collect(parser)
        @test length(parses) == 5

        complete_parses = collect(Iterators.filter(is_complete(parser), parser))
        @test length(complete_parses) == 1
        p = first(complete_parses)
        @test head(p) == :S
        @test rule(p) == (:S => [:NP, :VP])
        @test rule(constituents(p)[1]) == (:NP => [:PN])
        @test rule(constituents(p)[2]) == (:VP => [:IV])
    end

    @testset "TopDown" begin
        parser = ChartParser(tokens, grammar, TopDown())
        parses = collect(parser)

        # The top down parser currently doesn't yield the terminal productions,
        # but the bottom up parser does. Should we change that?
        @test length(parses) == 3

        complete_parses = collect(Iterators.filter(is_complete(parser), parser))
        @test length(complete_parses) == 1
        p = first(complete_parses)
        @test head(p) == :S
        @test rule(p) == (:S => [:NP, :VP])
        @test rule(constituents(p)[1]) == (:NP => [:PN])
        @test rule(constituents(p)[2]) == (:VP => [:IV])
    end
end

@testset "longer example" begin
    tokens = split("mary sat on the table yesterday")
    grammar = SimpleGrammar([
            :S => [:NP, :VP],
            :NP => [:PN],
            :VP => [:V, :NP],
            :VP => [:V, :PP],
            :VP => [:VP, :AV],
            :PP => [:P, :NP],
            :NP => [:D, :N]
        ], Dict(
        "mary" => [:PN],
        "sat" => [:V],
        "on" => [:P],
        "the" => [:D],
        "table" => [:N],
        "yesterday" => [:AV]
        ), :S)
    parser = ChartParser(tokens, grammar)
    complete_parses = @inferred collect(Iterators.filter(is_complete(parser), parser))
    @test length(complete_parses) == 1

    p = first(complete_parses)
    @test head(p) == :S
    @test rule(p) == (:S => [:NP, :VP])
    @test rule(constituents(p)[1]) == (:NP => [:PN])
    @test rule(constituents(p)[2]) == (:VP => [:VP, :AV])
    @test rule(constituents(constituents(p)[2])[1]) == (:VP => [:V, :PP])
end

abstract type GrammaticalSymbol end
struct S <: GrammaticalSymbol end
struct VP <: GrammaticalSymbol end
struct NP <: GrammaticalSymbol end

struct TypedGrammar <: AbstractGrammar{Pair{GrammaticalSymbol, NTuple{N, GrammaticalSymbol} where N}}
    productions::Vector{Pair{GrammaticalSymbol, NTuple{N, GrammaticalSymbol} where N}}
    labels::Dict{String, Vector{GrammaticalSymbol}}
end

ChartParsers.productions(g::TypedGrammar) = g.productions

function ChartParsers.terminal_productions(g::TypedGrammar, tokens)
    R = ChartParsers.rule_type(g)
    result = Arc{R}[]
    for (i, token) in enumerate(tokens)
        for label in get(g.labels, token, GrammaticalSymbol[])
            push!(result, Arc{R}(i - 1, i, label => (), [], 1))
        end
    end
    result
end

ChartParsers.start_symbol(g::TypedGrammar) = S()

@testset "typed rules" begin
    tokens = split("mia danced")
    grammar = TypedGrammar([
            S() => (VP(), NP()),
            S() => (NP(), VP())
        ],
        Dict("mia" => [NP()], "danced" => [VP()]))
    parser = ChartParser(tokens, grammar)
    complete_parses = @inferred collect(Iterators.filter(is_complete(parser), parser))
    @test length(complete_parses) == 1
    @test rule(first(complete_parses)) == (S() => (NP(), VP()))
end

@testset "Weighted terminal productions" begin
    grammar = TerminalWeightedGrammar([
        :A => [:B, :C],
        :B => [:E],
        :C => [:F],
        :C => [:G]],
        Dict("a" => [:D => 0.6, :E => 0.4],
             "b" => [:F => 0.9, :G => 0.1]),
        :A)
    tokens = split("a b")
    parser = ChartParser(tokens, grammar)
    parses = collect(parser)
    @test rule.(parses) == [
        :F => Symbol[],
        :C => [:F],
        :D => Symbol[],
        :E => Symbol[],
        :B => [:E],
        :A => [:B, :C],
        :G => Symbol[],
        :C => [:G],
        :A => [:B, :C]
    ]

    p = first(filter(is_complete(parser), parses))
    @test rule.(constituents(p)) == [:B => [:E], :C => [:F]]
end
