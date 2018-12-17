using Test
using ChartParsers
using ChartParsers: Arc, parse, head

@testset "arc in chart detection" begin
    chart = Chart(2)
    a1 = Arc(0, 1, :NP => [:PN], ["Mary"])
    a2 = Arc(0, 0, :S => [:NP, :VP], [])
    a3 = a2 * a1

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

    grammar = Grammar([
            :S => [:NP, :VP, :PP],
            :S => [:NP, :VP],
            :NP => [:PN],
            :VP => [:IV],
            :PP => [:P, :NP],
        ], Dict(
            "mia" => [:PN],
            "danced" => [:IV]
        ))

    chart = parse(split("mia danced"), grammar)
    @test length(complete_parses(chart)) == 1
    p = first(complete_parses(chart))
    @test head(p) == :S
    @test p.rule == (:S => [:NP, :VP])
    @test !ChartParsers.isactive(p)
    @test p.constituents[1].rule == (:NP => [:PN])
    @test p.constituents[2].rule == (:VP => [:IV])
end

@testset "longer example" begin
    tokens = split("mary sat on the table yesterday")
    grammar = [
        :S => [:NP, :VP],
        :NP => [:PN],
        :VP => [:V, :NP],
        :VP => [:V, :PP],
        :VP => [:VP, :AV],
        :PP => [:P, :NP],
        :NP => [:D, :N]
    ]
    labels = Dict(
        "mary" => [:PN],
        "sat" => [:V],
        "on" => [:P],
        "the" => [:D],
        "table" => [:N],
        "yesterday" => [:AV]
    )
    chart = parse(tokens, Grammar(grammar, labels))
    parses = complete_parses(chart)

    @test length(parses) == 1
    io = IOBuffer()
    expand(io, first(parses))
    @test String(take!(io)) == """
(S
  (NP (PN "mary"))
  (VP
    (VP
      (V "sat")
      (PP
        (P "on")
        (NP
          (D "the")
          (N "table"))))
    (AV "yesterday")))"""
end


