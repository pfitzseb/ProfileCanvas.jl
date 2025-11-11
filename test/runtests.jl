TestEnv.activate()
using ProfileCanvas
using Test
using SnoopCompile

function profile_test(n)
    for i = 1:n
        A = randn(100, 100, 20)
        m = maximum(A)
        Am = mapslices(sum, A; dims=2)
        B = A[:, :, 5]
        Bsort = mapslices(sort, B; dims=1)
        b = rand(100)
        C = B .* b
    end
end

@testset "ProfileCanvas.jl" begin
    trace = ProfileCanvas.@profview profile_test(10)
    html = sprint(show, "text/html", trace)
    @test occursin("const viewer = new ProfileCanvas.ProfileViewer(", html)
end

@testset "html file" begin
    ProfileCanvas.@profview profile_test(10)
    path = joinpath(@__DIR__, "flame.html")
    try
        ProfileCanvas.html_file(path)
        @test isfile(joinpath(@__DIR__, "flame.html"))
    finally
        isfile(path) && rm(path)
    end
end


@testset "Snoop view" begin
    @snoop_view profile_test(10)
end