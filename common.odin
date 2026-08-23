package redef
import "base:runtime"
import "core:time"
import "core:log"
import win "core:sys/windows"
import que "core:container/queue"

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32
mat4 :: matrix[4,4]f32

Rect :: struct { x, y, w, h: f32 }

EventQueue :: que.Queue(Event)


Global :: struct {
    kb_state:       KeyboardState,
    event_queue:    EventQueue,
    mouse_position: [2]i32,
    mouse_delta:    [2]i32,
    window:         Window,
    graphics:       Graphics,
    dt:             time.Time,
    elapsed:        time.Time,
    logger:         log.Logger,
    window_mode:    WindowMode,
    mouse:          Mouse,
    vsync,
    debug,
    raw_input,
    graphics_init:  bool,
}

g: Global

@(private = "package")
add_event :: proc(event: Event, loc := #caller_location) { 
    ok, err := que.enqueue(&g.event_queue, event)
    if !ok do log.errorf("Error: %v", err, location = loc)
}

@(private = "package")
string_to_cstring16 :: proc(s: string, allocator := context.temp_allocator) -> cstring16 {
    return cstring16(raw_data(win.utf8_to_utf16(s, allocator)))
}