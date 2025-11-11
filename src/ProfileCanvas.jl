module ProfileCanvas

using Profile, JSON, REPL, Pkg.Artifacts, Base64

using FlameGraphs: NodeData
using LeftChildRightSiblingTrees
using UUIDs: uuid4

export @profview, @profview_allocs, @snoop_view

macro snoop_view end
mutable struct ProfileFrame
    func::String
    "Human readable file name."
    file::String
    "Absolute path."
    path::String
    "1-based line number."
    line::Int
    "Number of samples in this frame."
    count::Int
    "defaults to count samples"
    countLabel::Union{Missing,String}
    "any or all of [`ProfileFrameFlag`](@ref)."
    flags::UInt8
    taskId::Union{Missing,UInt}
    children::Vector{ProfileFrame}
end

"Wrapper for display, contains data for each thread and a global name."
struct ProfileData
    "Dictionary mapping, threads (e.g. all, 1, 2, etc...) to the profiling data."
    data::Dict{String,Any}
    "Name used for display."
    typ::String
end

struct ProfileDisplay <: Base.Multimedia.AbstractDisplay end

function __init__()
    pushdisplay(ProfileDisplay())

    atreplinit(
        i -> begin
            while ProfileDisplay() in Base.Multimedia.displays
                popdisplay(ProfileDisplay())
            end
            pushdisplay(ProfileDisplay())
        end
    )
end

function jlprofile_data_uri()
    path = joinpath(artifact"jlprofilecanvas", "jl-profile.js-0.5.2", "dist", "profile-viewer.js")
    str = read(path, String)
    return string("data:text/javascript;base64,", base64encode(str))
end

function Base.show(io::IO, ::MIME"text/html", canvas::ProfileData)
    id = "profiler-container-$(round(Int, rand()*100000))"

    println(
        io,
        """
        <div id="$(id)" style="height: 400px; position: relative;"></div>
        <script type="module">
            const ProfileCanvas = await import('$(jlprofile_data_uri())')
            const viewer = new ProfileCanvas.ProfileViewer("#$(id)", $(JSON.json(canvas.data)), "$(canvas.typ)")
        </script>
        """
    )
end

function Base.display(_::ProfileDisplay, canvas::ProfileData)
    file = html_file(string(tempname(), ".html"), canvas)
    url = "file://$file"

    if Sys.iswindows()
        run(`cmd /c "start $url"`)
    elseif Sys.isapple()
        run(`open $url`)
    elseif Sys.islinux() || Sys.isbsd()
        run(`xdg-open $url`)
    end
end

html_file(filename, data=Profile.fetch(); kwargs...) = html_file(filename, view(data; kwargs...))

function html_file(file::AbstractString, canvas::ProfileData)
    @assert endswith(file, ".html")
    open(file, "w") do io
        id = "profiler-container-$(uuid4())"
        println(
            io,
            """
            <html>
            <head>
            <style>
                #$(id) {
                    margin: 0;
                    padding: 0;
                    width: 100vw;
                    height: 100vh;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji";
                    overflow: hidden;
                }
                body {
                    margin: 0;
                    padding: 0;
                }
            </style>
            </head>
            <body>
                <div id="$(id)"></div>
                <script type="module">
                    const ProfileCanvas = await import('$(jlprofile_data_uri())')
                    const viewer = new ProfileCanvas.ProfileViewer("#$(id)", $(JSON.json(canvas.data)), "$(canvas.typ)")
                </script>
            </body>
            </html>
            """
        )
    end
    return file
end

using Profile

# https://github.com/timholy/FlameGraphs.jl/blob/master/src/graph.jl
const ProfileFrameFlag = (
    RuntimeDispatch=UInt8(2^0),
    GCEvent=UInt8(2^1),
    REPL=UInt8(2^2),
    Compilation=UInt8(2^3),
    TaskEvent=UInt8(2^4),
    # See SnoopCompileProfileCanvasExt for use.
    SnoopCompile=UInt8(2^5),
    Invisible=UInt8(2^6),
)

function view(data=Profile.fetch(); C=false, kwargs...)
    d = Dict{String,ProfileFrame}()

    if VERSION >= v"1.8.0-DEV.460"
        threads = ["all", 1:Threads.nthreads()...]
    else
        threads = ["all"]
    end

    if isempty(data)
        Profile.warning_empty()
        return
    end

    lidict = Profile.getdict(unique(data))
    data_u64 = convert(Vector{UInt64}, data)
    for thread in threads
        graph = stackframetree(data_u64, lidict; thread=thread, kwargs...)
        d[string(thread)] = make_tree(
            ProfileFrame(
                "root", "", "", 0, graph.count, missing, 0x0, missing, ProfileFrame[]
            ), graph; C=C, kwargs...)
    end

    return ProfileData(d, "Thread")
end

function stackframetree(data_u64, lidict; thread=nothing, combine=true, recur=:off)
    root = combine ? Profile.StackFrameTree{StackTraces.StackFrame}() : Profile.StackFrameTree{UInt64}()
    if VERSION >= v"1.8.0-DEV.460"
        thread = thread == "all" ? (1:Threads.nthreads()) : thread
        root, _ = Profile.tree!(root, data_u64, lidict, true, recur, thread)
    else
        root = Profile.tree!(root, data_u64, lidict, true, recur)
    end
    if !isempty(root.down)
        root.count = sum(pr -> pr.second.count, root.down)
    end

    return root
end

function status(sf::StackTraces.StackFrame)
    st = UInt8(0)
    if sf.from_c && (sf.func === :jl_invoke || sf.func === :jl_apply_generic || sf.func === :ijl_apply_generic)
        st |= ProfileFrameFlag.RuntimeDispatch
    end
    if sf.from_c && startswith(String(sf.func), "jl_gc_")
        st |= ProfileFrameFlag.GCEvent
    end
    if !sf.from_c && sf.func === :eval_user_input && endswith(String(sf.file), "REPL.jl")
        st |= ProfileFrameFlag.REPL
    end
    if !sf.from_c && occursin("./compiler/", String(sf.file))
        st |= ProfileFrameFlag.Compilation
    end
    if !sf.from_c && occursin("task.jl", String(sf.file))
        st |= ProfileFrameFlag.TaskEvent
    end
    return st
end

function status(node::Profile.StackFrameTree, C::Bool)
    st = status(node.frame)
    C && return st
    # If we're suppressing C frames, check all C-frame children
    for child in values(node.down)
        child.frame.from_c || continue
        st |= status(child, C)
    end
    return st
end

function add_child(graph::ProfileFrame, node, C::Bool)
    name = string(node.frame.file)
    func = String(node.frame.func)

    if func == ""
        func = "unknown"
    end

    frame = ProfileFrame(
        func,
        basename(name),
        name,
        node.frame.line,
        node.count,
        missing,
        status(node, C),
        missing,
        ProfileFrame[]
    )

    push!(graph.children, frame)

    return frame
end

function make_tree(graph, node::Profile.StackFrameTree; C=false)
    for child_node in sort!(collect(values(node.down)); rev=true, by=node -> node.count)
        # child not a hidden frame
        if C || !child_node.frame.from_c
            child = add_child(graph, child_node, C)
            make_tree(child, child_node; C=C)
        else
            make_tree(graph, child_node)
        end
    end

    return graph
end

"""
    @profview f(args...) [C = false]

Clear the Profile buffer, profile the runtime of `f(args...)`, and view the result graphically.

The profiling data is color-coded to provide insights about the performance of your code:
- Red bars represent function calls resolved at run-time, which often have a significant impact on performance. While some red is unavoidable, excessive red may indicate a performance bottleneck.
- Yellow bars indicate a site of garbage collection, which is often triggered by memory allocation. These sites can often be optimized by reducing the amount of temporary memory allocated by your code.

Example:

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

See also:
- [`ProfileCanvas.@profview_allocs`](@ref)

`C = true` will also show frames originating in C code (typically Julia internals),
which can be helpful for advanced users.
"""
macro profview(ex, args...)
    return quote
        Profile.clear()
        Profile.@profile $(esc(ex))
        view(; $(esc.(args)...))
    end
end

## Allocs

"""
    @profview_allocs f(args...) [sample_rate=0.0001] [C=false]

Clear the `Profile.Allocs` buffer, profile allocations during `f(args...)`, and view the result graphically.

A `sample_rate` of 1.0 will record everything; 0.0 will record nothing

See also:
- [`ProfileCanvas.@profview`](@ref)
"""
macro profview_allocs(ex, args...)
    sample_rate_expr = :(sample_rate = 0.0001)
    for arg in args
        if Meta.isexpr(arg, :(=)) && length(arg.args) > 0 && arg.args[1] === :sample_rate
            sample_rate_expr = arg
        end
    end
    if isdefined(Profile, :Allocs)
        return quote
            Profile.Allocs.clear()
            Profile.Allocs.@profile $(esc(sample_rate_expr)) $(esc(ex))
            view_allocs()
        end
    else
        return :(@error "This version of Julia does not support the allocation profiler.")
    end
end

function view_allocs(_results=Profile.Allocs.fetch(); C=false)
    results = _results::Profile.Allocs.AllocResults
    allocs = results.allocs

    allocs_root = ProfileFrame("root", "", "", 0, 0, missing, 0x0, missing, ProfileFrame[])
    counts_root = ProfileFrame("root", "", "", 0, 0, missing, 0x0, missing, ProfileFrame[])
    for alloc in allocs
        this_allocs = allocs_root
        this_counts = counts_root

        for sf in Iterators.reverse(alloc.stacktrace)
            if !C && sf.from_c
                continue
            end
            file = string(sf.file)
            this_counts′ = ProfileFrame(
                string(sf.func), basename(file), file,
                sf.line, 0, missing, 0x0, missing, ProfileFrame[]
            )
            ind = findfirst(c -> (
                    c.func == this_counts′.func &&
                    c.path == this_counts′.path &&
                    c.line == this_counts′.line
                ), this_allocs.children)

            this_counts, this_allocs = if ind === nothing
                push!(this_counts.children, this_counts′)
                this_allocs′ = deepcopy(this_counts′)
                push!(this_allocs.children, this_allocs′)

                (this_counts′, this_allocs′)
            else
                (this_counts.children[ind], this_allocs.children[ind])
            end
            this_allocs.count += alloc.size
            this_allocs.countLabel = memory_size(this_allocs.count)
            this_counts.count += 1
        end

        alloc_type = replace(string(alloc.type), "Profile.Allocs." => "")
        ind = findfirst(c -> (c.func == alloc_type), this_allocs.children)
        if ind === nothing
            push!(this_allocs.children, ProfileFrame(
                alloc_type, "", "",
                0, this_allocs.count, memory_size(this_allocs.count), ProfileFrameFlag.GCEvent, missing, ProfileFrame[]
            ))
            push!(this_counts.children, ProfileFrame(
                alloc_type, "", "",
                0, 1, missing, ProfileFrameFlag.GCEvent, missing, ProfileFrame[]
            ))
        else
            this_counts.children[ind].count += 1
            this_allocs.children[ind].count += alloc.size
            this_allocs.children[ind].countLabel = memory_size(this_allocs.children[ind].count)
        end

        counts_root.count += 1
        allocs_root.count += alloc.size
        allocs_root.countLabel = memory_size(allocs_root.count)
    end

    d = Dict{String,ProfileFrame}(
        "size" => allocs_root,
        "count" => counts_root
    )

    return ProfileData(d, "Allocation")
end

const memory_suffixes = ["bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]
memory_size(size) = append_suffix(size, memory_suffixes)

function append_suffix(value, suffixes)
    i = 1
    while value > 1000 && i + 1 < length(suffixes)
        value /= 1000
        i += 1
    end
    return string(round(Int, value), " ", suffixes[i])
end

end
