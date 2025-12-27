package redef

import "base:runtime"
import "core:log"
import "core:time"
import que "core:container/queue"

// Todo: Remove Windows import
import win "core:sys/windows"

EventQueue :: que.Queue(Event)

KeyboardState :: #sparse[Keycode]bool

WindowHandle :: distinct rawptr

Window :: struct {
    name: string,
    handle: WindowHandle,
    window_class: WindowClass,
    size: [2]i32
}

KeyboardEventType :: enum {
    KeyDown,
    KeyUp,
    Repeat,
}


ModKey :: enum u8 {
    CONTROL = u8(Keycode.CONTROL),
    SHIFT   = u8(Keycode.SHIFT),
}

ModKeys :: bit_set[ModKey]

TextInput :: struct {
    key: rune
}

KeyboardEvent :: struct {
    type: KeyboardEventType,
    key: Keycode,
    mod: ModKeys
}

MouseEvent :: struct {
    type: MouseEventType,

    // Relative mouse position at the time of the event
    position: [2]i32,
    mod: ModKeys
}

MouseEventType :: enum {
    LPress,
    LRelease,
    RPress,
    RRelease,
    MPress,
    MRelease,

    // For wheel events, MouseEvent.position corresponds to scroll direction
    // e.g. move wheel up -> event.mouse == {120, 0}
    // 120 is the wheel delta defined by Windows. 
    MWheel,
}

Quit :: distinct i32

Event :: union {
    Quit,
    KeyboardEvent,
    MouseEvent,
    TextInput
}

@(private = "package")
Global :: struct {
    kb_state:       KeyboardState,
    event_queue:    EventQueue,
    mouse_position: [2]i32,
    window_count:   u32,
    graphics:       Graphics,
    dt:             time.Time,
    elapsed:        time.Time,
}

@(private = "package")
g: Global


@(private = "package")
add_event :: proc(event: Event) { que.enqueue(&g.event_queue, event) }

time_since_start :: proc() -> time.Duration {
    return time.since(g.elapsed)
}

get_dt :: proc() -> time.Duration {
    elapsed := time.since(g.dt)
    g.dt = time.now()
    return elapsed
}

create_window :: proc (name: string, width, height: i32, debug: bool) -> ^Window {
    when ODIN_DEBUG {
        context.logger = log.create_console_logger(allocator = context.temp_allocator)
    } else {
        context.logger = log.nil_logger()
    }
    window := new(Window)
    
    window.size = {width, height}
    window.name = name
    init_windows_window(window)
    if g.window_count == 0 {
        init_graphics(window)
        g.elapsed = time.now()
    }

    alloc_err := que.init(&g.event_queue, capacity = 32)
    if alloc_err != nil {
        destroy_window(window)
        log.errorf("Failed to init event queue. Allocation error: %v", alloc_err)
        return nil
    }
    log.infof("Window '%v' created [handle: %v]", string_to_cstring16(window.name), window.handle)
    g.window_count += 1
    return window
}

string_to_cstring16 :: proc(s: string, allocator := context.temp_allocator) -> cstring16 {
    return cstring16(raw_data(win.utf8_to_utf16(s, allocator)))
}

pump_event_iter :: proc(window: ^Window) -> (event: Event, ok: bool = true) {
    msg: win.MSG

    for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE){
        if msg.message == win.WM_QUIT {
            event = Quit(msg.wParam)
            return
        }
        win.TranslateMessage(&msg)
        win.DispatchMessageW(&msg)
    }

    if que.len(g.event_queue) > 0 {
        event = que.dequeue(&g.event_queue)
        return
    }
    ok = false
    return
}

destroy_window :: proc (w: ^Window, loc := #caller_location){
    when ODIN_DEBUG {
        context = runtime.default_context()
        context.logger = log.create_console_logger(allocator = context.temp_allocator)
    } else {
        context.logger = log.nil_logger()
    }

    // If a window was destroyed the window count can be decremented
    destroy_window_raw(w.handle, loc)
    if g.window_count == 0 {
        destroy_graphics(g.graphics)
    }
    unregister_window_class(w)
    free(w)
}

get_window_size :: proc(w: ^Window) -> [2]i32 {
    return w.size
}

get_window_name :: proc(w: ^Window) -> string {
    return w.name
}

get_mouse_position :: proc() -> [2]i32 {
    return g.mouse_position
}