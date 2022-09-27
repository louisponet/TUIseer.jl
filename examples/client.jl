using RemoteREPL
connect_repl(27754)
using TUIseer
using Term
using Overseer
struct TestMode <: System end

@remote function Overseer.prepare(::TestMode, tui::AbstractLedger)
    m = mode_entity(tui, :testmode)
    e = Entity(tui, Color("green"), Renderable(Term.Panel(RenderableText("testtext",style="green"))))
    tui[Mode][e] = m
end
@remote function Overseer.update(::TestMode, tui::AbstractLedger)
    m = mode_entity(tui, :testmode)
    for e in entity_pool(tui[Mode], m)
        if e in tui[Color]
            if tui[Color][e].color == "green"
                tui[Color][e] = Color("red")
            else
                tui[Color][e] = Color("green")
            end
            tui[Renderable][e] = Renderable(Term.Panel(RenderableText("testtext",style=tui[Color][e].color)))
        end
    end
end

@remote add_mode!(MAIN_TUI[], :testmode, 'k', Stage(:testmodestage, [TestMode()]), description="TestMode") 
