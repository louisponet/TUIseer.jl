@pooled_component Base.@kwdef mutable struct Mode
    name::Symbol
    key::UInt32 
    stage::Symbol # will run every update
    active::Bool = false
    description::String = ""
    # The String will be shown, the symbol corresponds to a stage that will be ran only when it is pressed
    actions::Dict{UInt32, Pair{String, Symbol}} = Dict{UInt32, Pair{String,Symbol}}()
end

@component struct Visible end

struct MainMode <: System end

Overseer.requested_components(::MainMode) = (Text, Panel)

function Overseer.update(::MainMode, tui::AbstractLedger)
    m = mode_entity(tui, :main)
    empty!(m.actions)
    for e in @entities_in(tui[Mode])
        if e == m
            continue
        end
        m.actions[e.key] = e.description => :modeselection
    end
end    
    
struct ModeSelector <: System end

Overseer.requested_components(::ModeSelector) = (Mode,Visible)
function Overseer.update(::ModeSelector, tui::AbstractLedger)
    key = currentkey(tui)
    if key == 0
        return
    end
    modec = tui[Mode]

    for (m, es) in pools(modec)
        if m.key == key
            empty!(tui[Visible])
            m.active = true
            for e in es
                tui[Visible][e] = Visible()
            end
        else
            m.active = false
        end
    end
end

struct ModeRunner <: System end

function Overseer.update(::ModeRunner, tui::AbstractLedger)
    active_mode = getfirst(x -> x.active, tui[Mode])
    if active_mode === nothing
        return
    end

    key = currentkey(tui)
    
    tui[Panel][Entity(1)].options[:title] = "Mode: $(active_mode.description)"
    tui[Visible][Entity(1)] = Visible()
    action_str = ""
    for (k, a) in active_mode.actions
        action_str *= "$(Char(k)) => $(a[1])\n"
    end
    tui[Text][Entity(1)] = Text(action_str)

    update(stage(tui, active_mode.stage), tui)
    if haskey(active_mode.actions, key)
        update(stage(tui,active_mode.actions[key][2]), tui)
    end
end

@component struct Renderable
    r
end

@component struct Text
    text::String
end

@component struct Color
    color::String
end

@pooled_component struct Panel
    options::Dict
end
Panel(; kwargs...) = Panel(Dict(kwargs))

@pooled_component mutable struct Grid
    options::Dict
end
Grid(; kwargs...) = Grid(Dict(kwargs))

struct SceneDrawer <: System end
Overseer.requested_components(::SceneDrawer) = (Grid, Panel, Color, Text, Renderable)

function Overseer.update(::SceneDrawer, l::AbstractLedger)
    tsize = term_size(stdout)
    l[Panel][Entity(1)].options[:width] = tsize[1] 
    l[Panel][Entity(1)].options[:height] = tsize[2] - 3

    rends = []
    for e in @entities_in(l[Renderable] && l[Visible])
        push!(rends, e.r)
    end
    if !isempty(rends)
        print(l, string(Term.Panel(RenderableText(l[Text][Entity(1)].text),Term.grid(rends); l[Panel][Entity(1)].options...)))
    else
        print(l, string(Term.Panel(RenderableText(l[Text][Entity(1)].text); l[Panel][Entity(1)].options...)))
    end
        
end


