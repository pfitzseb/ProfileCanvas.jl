module SnoopCompileProfileCanvasExt

using SnoopCompile
using SnoopCompile: FlameGraphs
using ProfileCanvas
using ProfileCanvas: Node, NodeData, ProfileData, ProfileFrame, ProfileFrameFlag, append_suffix
import ProfileCanvas: @snoop_view


"Frame that is destined to be invisible in the frontend, simulating the type not spent on type inference."
function emptyframe(count::Int)
    ProfileFrame("", "", "", 0, count, missing, ProfileFrameFlag.Invisible, missing, ProfileFrame[])
end

function Base.convert(::Type{ProfileFrame}, node::Node{NodeData})
    # Fetch information 
    data_args = nodedata_to_frame_attributes(node.data)
    # Span is the starting and end count of the node.
    span = node.data.span
    i = first(span)
    # We build recursively build the collection of children.
    children = ProfileFrame[]
    for child in node
        frame = convert(ProfileFrame, child)
        child_span = child.data.span
        # If the end time of a child does not match the start of the next,
        # we add an empty frame with the right span difference.
        if first(child_span) > i
            push!(children, emptyframe(first(child_span) - i))
        end
        push!(children, frame)
        i = last(child_span)
    end
    ProfileFrame(data_args..., children)
end

const time_suffixes = ["ns", "μs", "ms", "s"]
human_time(t_ns) = append_suffix(t_ns, time_suffixes)

"Convert the information of the current node into data that fits `ProfileFrame`."
function nodedata_to_frame_attributes((; sf, status, span)::NodeData)
    func = string(sf.func)
    file = string(sf.file)
    path = ""
    line = sf.line
    count = length(span)
    countLabel = human_time(length(span))
    flags = status | ProfileFrameFlag.SnoopCompile
    tasksID = missing
    (func, file, path, line, count, countLabel, flags, tasksID)
end

function view_compile(tinf::SnoopCompile.InferenceTimingNode)
    fg = flamegraph(tinf)
    ProfileData(
        Dict("inference" => convert(ProfileCanvas.ProfileFrame, fg)),
        "Type inference",
    )
end

"""
Execute `@snoopi_deep` from `SnoopCompile` on the expressionand show the inference tree as 
an HTML flamegraph. 
"""
macro snoop_view(expr)
    quote
        let tinf = @snoopi_deep $(esc(expr))
            view_compile(tinf)
        end
    end
end

end