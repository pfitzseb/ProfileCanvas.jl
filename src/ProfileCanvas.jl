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

function Base.show(io::IO, ::MIME"text/html", canvas::ProfileData; full = false)
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

function Base.display(d::ProfileDisplay, canvas::ProfileData)
    file = tempname()*".html"
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
                $(
                    replace(read(joinpath(@__DIR__, "..", "dist", "jl-profile", "dist", "profile-viewer.js"), String), "export class" => "class")
                )
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


function view_profile(; C = false, kwargs...)
    d = Dict()

    data = Profile.fetch()
    lidict = Profile.getdict(unique(data))
    data_u64 = convert(Vector{UInt64}, data)

    if VERSION >= v"1.8.0-DEV.460"
        threads = ["all", 1:Threads.nthreads()...]
        for thread in ["all", 1:Threads.nthreads()...]
            if thread == "all"
                thread = 1:Threads.nthreads()
            end
            d[thread] = tojson(FlameGraphs.flamegraph(data_u64; lidict=lidict, C=C, threads = thread))
        end
    else
        d["all"] = tojson(FlameGraphs.flamegraph(data_u64; lidict=lidict, C=C))
    end

    ProfileData(d)
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

Clear the Profile buffer, profile `f(args...)`, and view the result graphically.
"""
macro profview(ex, args...)
    return quote
        Profile.clear()
        Profile.@profile $(esc(ex))
        view_profile(; $(esc.(args)...))
    end
end

end
