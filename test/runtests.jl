using ProfileCanvas
using Test

function profile_test(n)
    for i = 1:n
        A = randn(100,100,20)
        m = maximum(A)
        Am = mapslices(sum, A; dims=2)
        B = A[:,:,5]
        Bsort = mapslices(sort, B; dims=1)
        b = rand(100)
        C = B.*b
    end
end

@testset "ProfileCanvas.jl" begin
    trace = @profview profile_test(10)
    html = sprint(show, "text/html", trace)
    @test occursin("const viewer = new ProfileViewer(", html)
end

@testset "html file" begin
    @profview profile_test(10)
    ProfileCanvas.html_file(joinpath(@__DIR__, "flame.html"))
    @test isfile(joinpath(@__DIR__, "flame.html"))
end
