module TUIseer

using Term
using REPL
using REPL: TerminalMenus
using StaticArrays
using Overseer
using Logging
using Sockets
using Revise
using RemoteREPL

include("utils.jl")
include("terminal.jl")
include("systems.jl")

@component Base.@kwdef struct FrameBuffer
    b::IOBuffer = IOBuffer()
end
@component Base.@kwdef mutable struct Keyboard
    key::UInt32 = 0
end

struct TUI <: AbstractLedger
    l::Ledger
end

for fn in (:print, :show, :println)
    @eval Base.$fn(io::TUI, args...) = $fn(io[FrameBuffer][1].b, args...)
end

function TUI()
    l = Ledger(Stage(:main, [ModeRunner(), SceneDrawer()]),
               Stage(:modeselection, [ModeSelector()]))
    tsize = term_size(stdout)
    main_entity = Entity(l,
                         Panel(title="Mode: Main",width = tsize[1], height=tsize[2]),
                         Text(""),
                         FrameBuffer(),
                         Keyboard())

    add_mode!(l, :main, ESC, Stage(:main_mode, [MainMode()]), description = "Main", active=true)
    
    return TUI(l)
end

Overseer.ledger(tui::TUI) = tui.l

currentkey(tui::TUI) = singleton(tui, Keyboard).key

function add_mode!(tui::AbstractLedger, name::Symbol, key::Union{Char, UInt32}, stage::Stage;
                   description::String = "",
                   actions = Dict{UInt32, Pair{String, Stage}}(),
                   active=false)
    acs = Dict{UInt32, Pair{String, Symbol}}()
    @assert mode_entity(tui, name) == nothing "Mode already exists ($(mode_entity(tui, name)))."
    for (key, st) in actions
        acs[key] = Pair(st[1], st[2][1])
    end
    if key != ESC
        acs[ESC] = "Main mode" => :modeselection
    end
    e = Entity(tui, Mode(name=name, key=key, stage=stage[1], description=description, actions=acs, active=active))
    push!(tui, stage)
    for (key, st) in actions
        push!(tui, st[2])
    end
    return e
end

function mode_entity(tui::AbstractLedger, name::Symbol)
    for e in @entities_in(tui[Mode])
        if e.name == name
            return e
        end
    end
    return nothing
end
const dev_mode = true

const MAIN_TUI = Ref{TUI}()

# The main game update loop
function loop(l, event_channel)
    while true
        clear_screen(stdout)
        while isopen(event_channel)
            # Allow live code modification
            Revise.revise()
            Base.invokelatest() do
                # Use our own update loop here so we can add in a try-catch
                # for development mode.
                for system in last(stage(l, :main))
                    try
                        update(system, l)
                    catch exc
                        global dev_mode
                        if dev_mode
                            @error("Exception running system update",
                                   system, exception=current_exceptions())
                        else
                            rethrow()
                        end
                    end
                end
            end
            (event_type,value) = take!(event_channel)
            @debug "Read event" event_type value
            if event_type === :key
                key = value
                if key == CTRL_C
                    # Clear
                    clear_screen(stdout)
                    return
                end
            end
            to_render = take!(l[FrameBuffer][1].b)
            # Terminal rendering is _slow_, so drop frames if there's
            # more events in the buffer. This reduces latency between
            # keyboard input and seeing the results.
            if !isready(event_channel)
                clear_screen(stdout)
                print(String(to_render))
            end
            if event_type === :key
                if key == CTRL_R
                    clear_screen(stdout)
                    break
                end
                l[Keyboard][1].key = key
            else
                l[Keyboard][1].key = 0
            end
        end
    end
end

function run()
    term = TerminalMenus.terminal
    open("log.txt", "w") do logio
        # with_logger(ConsoleLogger(IOContext(logio, :color=>true))) do
        with_logger(ConsoleLogger(IOContext(logio))) do
            @sync begin
                repl_server = nothing
                try
                    # Live code modification via RemoteREPL
                    repl_server = listen(Sockets.localhost, 27754)
                    @async begin
                        serve_repl(repl_server, on_client_connect=sess->sess.in_module=TUIseer)
                    end
                catch exc
                    @error "Failed to set up REPL server" exception=(exc,catch_backtrace())
                end
                # Use global Game object for access from RemoteREPL.jl
                tsize = term_size(term)
                MAIN_TUI[] = TUI()
                event_channel = Channel()
                @info "Initialized game"
                try
                    rawmode(term) do
                        # Main game loop
                        @async try
                            loop(MAIN_TUI[], event_channel)
                        catch exc
                            @error "event loop failed" exception=(exc,catch_backtrace())
                            close(event_channel)
                            # Close stdin to terminate wait on keyboard input
                            close(stdin)
                        end

                        # Frame timer events
                        @async try
                            frame_timer = Timer(0; interval=0.2)
                            while true
                                wait(frame_timer)
                                isopen(event_channel) || break
                                push!(event_channel, (:timer,nothing))
                                # Hack! flush stream
                                flush(logio)
                            end
                        catch exc
                            if isopen(event_channel)
                                @error "Adding key failed" exception=(exc,catch_backtrace())
                            end
                        end

                        # Main keyboard handling.
                        # It seems we need run this in the original task,
                        # otherwise we miss events (??)
                        try
                            while true
                                keycode = read_key(stdin)
                                @debug "Read key" Char(keycode)
                                push!(event_channel, (:key, keycode))
                                if keycode == CTRL_C
                                    break
                                end
                            end
                        catch exc
                            @error "Adding key failed" exception=(exc,catch_backtrace())
                            rethrow()
                        finally
                            close(event_channel)
                        end
                    end
                finally
                    close(event_channel)
                    isnothing(repl_server) || close(repl_server)
                end
            end
        end
    end
    write(stdout, read("log.txt"))
end


end # module TUIseer
