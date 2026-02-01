package redef

import "base:runtime"
import "core:log"
import "core:time"
import que "core:container/queue"

// Todo: Remove Windows import
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
    Move
}

Quit :: distinct i32

Event :: union {
    Quit,
    KeyboardEvent,
    MouseEvent,
    TextInput
}




time_since_start :: proc() -> time.Duration {
    return time.since(g.elapsed)
}

get_dt :: proc() -> time.Duration {
    elapsed := time.since(g.dt)
    g.dt = time.now()
    return elapsed
}

create_window :: proc (name: string, width, height: i32, debug: bool, loc := #caller_location) -> ^Window {
    if debug && g.window_count == 0 do g.logger = log.create_console_logger()
    context.logger = g.logger
    alloc_err := que.init(&g.event_queue, capacity = 32)
    if alloc_err != nil {
        log.errorf("Failed to init event queue. Allocation error: %v", alloc_err, location = loc)
        return nil
    }

    window := new(Window)
    window.size = {width, height}
    window.name = name
    init_windows_window(window)
    log.infof("Window '%v' created [handle: %v]", string_to_cstring16(window.name), window.handle, location = loc)

    if g.window_count == 0 {
        init_graphics(window, debug, loc = loc)
        g.elapsed = time.now()
        g.dt = time.now()
    } else {
        log.errorf("Not Implemented: multiple windows", location = loc)
        return nil
    }

    g.window_count += 1
    return window
}


pump_event_iter :: proc(window: ^Window) -> (event: Event, ok: bool) {
    context.logger = g.logger
    return pump_event_iter_raw(window)
}

destroy_window :: proc (w: ^Window, loc := #caller_location){
    // If a window was destroyed the window count can be decremented
    context.logger = g.logger
    destroy_window_raw(w.handle, loc)

    unregister_window_class(w, loc)
    free(w)

    // Last window deleated -> Should de-init
    if g.window_count == 0 {
        que.destroy(&g.event_queue)
        destroy_graphics(loc)
        log.destroy_console_logger(g.logger)
    }
}

get_window_size :: proc(w: ^Window) -> [2]i32 {
    return w.size
}

get_window_name :: proc(w: ^Window) -> string {
    return w.name
}

get_mouse_position :: proc() -> (x: f32, y: f32) {
    return f32(g.mouse_position.x), f32(g.mouse_position.y)
}