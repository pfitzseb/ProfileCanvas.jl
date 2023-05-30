# ProfileCanvas [![CI](https://github.com/pfitzseb/ProfileCanvas.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/pfitzseb/ProfileCanvas.jl/actions/workflows/CI.yml) [![version](https://juliahub.com/docs/ProfileCanvas/version.svg)](https://juliahub.com/ui/Packages/ProfileCanvas/T2dXl)

This package is intended as a drop-in replacement for [ProfileView.jl](https://github.com/timholy/ProfileView.jl) and [ProfileSVG.jl](https://github.com/kimikage/ProfileSVG.jl).

It exposes the HTML canvas based [profile viewer UI](https://github.com/pfitzseb/jl-profile.js) used by the [Julia extension for VS Code](https://www.julia-vscode.org/docs/stable/userguide/profiler/) in the REPL and environments that can display HTML (like Pluto notebooks). Performance should be significantly better than SVG-based solutions, especially for very large traces.

## Usage

```julia
using ProfileCanvas
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

@profview profile_test(1)  # run once to trigger compilation (ignore this one)
@profview profile_test(10)
```

On Julia 1.8 and newer you can also use profiler memory allocations with `@profview_allocs`/`view_allocs`:

```
@profview_allocs profile_test(10)
```

The controls are _mouse wheel_ to scroll, and _click_ on a cell to base the zoom on it.
The end result depends on the julia version, but it might be something like this:

![](assets/flamegraph.png)

when run from the REPL and

![](assets/flamegraph-pluto.png)

in a [Pluto](https://github.com/fonsp/Pluto.jl) notebook.

### Color coding

The profiling data is color-coded to provide insights about the performance of your code:
- Red bars represent function calls resolved at run-time, which often have a significant impact on performance. While some red is unavoidable, excessive red may indicate a performance bottleneck.
- Yellow bars indicate a site of garbage collection, which is often triggered by memory allocation. These sites can often be optimized by reducing the amount of temporary memory allocated by your code.
