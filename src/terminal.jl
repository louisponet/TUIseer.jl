using REPL.TerminalMenus

#--------------------------------------------------
# Utilities
function rawmode(f, term)
    REPL.Terminals.raw!(term, true)
    try
        print(term.out_stream, "\x1b[?25l") # hide the cursor
        f()
    finally
        print(term.out_stream, "\x1b[?25h") # unhide cursor
        REPL.Terminals.raw!(term, false)
    end
end

#--------------------------------------------------
# Keyboard input

struct Key
    keyboard::UInt32  # Id for the connected keyboard (may be remote)
    keycode::UInt32
end

# Import TerminalMenus.Key codes, but converted to UInt32 constants so that all
# keys can be of the same type (the numerical values of these don't represent
# unicode code points)
for k in (:ARROW_UP, :ARROW_DOWN, :ARROW_LEFT, :ARROW_RIGHT, :DEL_KEY,
          :HOME_KEY, :END_KEY, :PAGE_UP, :PAGE_DOWN)
    @eval const $k = UInt32(REPL.TerminalMenus.$k)
end

# Some additional keys constants represented as type Char
const CTRL_C = 0x3
const CTRL_R = 0x12
const ESC = 0x0000001b

# Read a UInt32 terminal key code
function read_key(io=stdin)
    keycode = REPL.TerminalMenus.readkey(io)
    c = Char(keycode)
    # Ignore caps lock - make case-insensitive
    return isascii(c) && isletter(c) ? UInt32(lowercase(c)) : keycode
end

function make_keymap(keyboard_id, mapping_pairs)
    Dict(Key(keyboard_id, UInt32(k))=>v for (k,v) in mapping_pairs)
end

function home_pos(io)
    print(io, "\e[1;1H")
end

function clear_screen(io)
    print(io, "\e[1;1H", "\e[J")
              #homepos   #clear
end

# Get terminal size as width,height
function term_size(io)
    h,w = displaysize(io)
    SA[w,h]
end
