module ProfileCanvas

using FlameGraphs, Profile, JSON, REPL, Pkg.Artifacts

export @profview

struct ProfileData
    data
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

function Base.show(io::IO, ::MIME"text/html", canvas::ProfileData)
    id = "profiler-container-$(round(Int, rand()*100000))"

    rootpath = artifact"jlprofilecanvas"
    path = joinpath(rootpath, "jl-profile.js-0.3.1", "dist", "profile-viewer.js")

    println(io, """
    <div id="$(id)" style="height: 400px; position: relative;"></div>
    <script type="text/javascript">
        $(replace(read(path, String), "export class" => "class"))
        const viewer = new ProfileViewer("#$(id)", $(JSON.json(canvas.data)))
    </script>
    """)
end

function Base.display(_::ProfileDisplay, canvas::ProfileData)
    rootpath = artifact"jlprofilecanvas"
    path = joinpath(rootpath, "jl-profile.js-0.3.1", "dist", "profile-viewer.js")

    file = string(tempname(), ".html")
    open(file, "w") do io
        id = "profiler-container-$(round(Int, rand()*100000))"

        println(io, """
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
            <script type="text/javascript">
                $(replace(read(path, String), "export class" => "class"))
                const viewer = new ProfileViewer("#$(id)", $(JSON.json(canvas.data)))
            </script>
        </body>
        </html>
        """)
    end
    url = "file://$file"

    if Sys.iswindows()
        run(`cmd /c "start $url"`)
    elseif Sys.isapple()
        run(`open $url`)
    elseif Sys.islinux() || Sys.isbsd()
        run(`xdg-open $url`)
    end
end

"""
    view(data = Profile.fetch(), lidict = Profile.getdict(unique(data)); C = false)

View profiling results in `data`/`lidict`. Simply call `ProfileCanvas.view()` to show the
current trace.
"""
function view(data = Profile.fetch(), lidict = Profile.getdict(unique(data)); C = false, kwargs...)
    d = Dict()

    data_u64 = convert(Vector{UInt64}, data)

    if VERSION >= v"1.8.0-DEV.460"
        for thread in ["all", 1:Threads.nthreads()...]
            d[thread] = tojson(FlameGraphs.flamegraph(data_u64; lidict=lidict, C=C, threads = thread == "all" ? (1:Threads.nthreads()) : thread))
        end
    else
        d["all"] = tojson(FlameGraphs.flamegraph(data_u64; lidict=lidict, C=C))
    end

    return ProfileData(d)
end

function tojson(node, root = false)
    name = string(node.data.sf.file)

    return Dict(
        :func => node.data.sf.func,
        :file => basename(name),
        :path => name,
        :line => node.data.sf.line,
        :count => root ? sum(length(c.data.span) for c in node) : length(node.data.span),
        :flags => node.data.status,
        :children => [tojson(c) for c in node]
    )
end

"""
    @profview f(args...) [C = false]

Clear the Profile buffer, profile `f(args...)`, and view the collected profiling data.

The optional `C` keyword argument controls whether functions in C code are displayed.
"""
macro profview(ex, args...)
    return quote
        Profile.clear()
        Profile.@profile $(esc(ex))
        view(; $(esc.(args)...))
    end
end

end
