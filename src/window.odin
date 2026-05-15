package redef

import "base:runtime"
import "core:log"
import "core:time"
import que "core:container/queue"

KeyboardState :: #sparse[Keycode]bool

WindowHandle :: distinct rawptr

Window :: struct {
    name: string,
    handle: WindowHandle,
    window_class: WindowClass,
    width,
    height: i32
}

WindowMode :: enum {
    WINDOW,
    MAXIMIZED,
    BORDERLESS
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

WindowResized :: struct {w, h: i32}

Event :: union {
    Quit,
    KeyboardEvent,
    MouseEvent,
    TextInput,
    WindowResized
}


time_since_start :: proc() -> time.Duration {
    return time.since(g.elapsed)
}

get_dt :: proc() -> f64 {
    elapsed := time.since(g.dt)
    g.dt = time.now()
    return time.duration_milliseconds(elapsed)
}

create_window :: proc (name: string, width, height: i32, debug: bool, loc := #caller_location) -> bool{
    if debug do g.logger = log.create_console_logger()
    context.logger = g.logger
    alloc_err := que.init(&g.event_queue, capacity = 32)
    if alloc_err != nil {
        log.errorf("Failed to init event queue. Allocation error: %v", alloc_err, location = loc)
        return false
    }
    g.window.width = width
    g.window.height = height
    g.window.name = name
    if ok := init_windows_window(); !ok do return false

    log.infof("Window '%v' created [handle: %v]", string_to_cstring16(g.window.name), g.window.handle, location = loc)

    init_graphics(debug, loc = loc)
    g.elapsed = time.now()
    g.dt = time.now()
    return true
    // g.window_count += 1
}


pump_event_iter :: proc() -> (event: Event, ok: bool) {
    context.logger = g.logger
    return pump_event_iter_raw()
}

destroy_window :: proc (loc := #caller_location){
    // If a window was destroyed the window count can be decremented
    context.logger = g.logger
    // defer g.window_count -= 1
    destroy_window_raw(g.window.handle, loc)
    unregister_window_class(loc)

    // Last window deleated -> Should de-init
    // if g.window_count == 0 {
        que.destroy(&g.event_queue)
        destroy_graphics(loc)
        log.destroy_console_logger(g.logger)
        // delete(g.window)
    // }
    // free(w)
}

get_window_size :: proc() -> vec2 {
    return {f32(g.window.width), f32(g.window.height)}
}

set_window_size :: proc(w: ^Window, size: [2]i32) {
    context.logger = g.logger
    w.width = size.x
    w.height = size.y
    resize_window(w.handle)
}

set_window_mode :: proc(wm: WindowMode, loc := #caller_location) {
    context.logger = g.logger
    if g.window_mode == wm do return
    log.debug("Setting window mode:", wm, location = loc)
    g.window_mode = wm
    

}

get_mouse_position :: proc() -> (x, y: f32) {
    return f32(g.mouse_position.x), f32(g.mouse_position.y)
}

get_relative_mouse_movement :: proc() -> (x, y: f32) {
    delta := g.mouse_delta
    g.mouse_delta = 0
    return f32(delta.x), f32(delta.y)
}

is_key_down :: proc(key: Keycode) -> bool {
    return g.kb_state[key]
}
