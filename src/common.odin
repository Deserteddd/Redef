package redef
import "core:time"
import "core:log"
import win "core:sys/windows"

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32
mat4 :: matrix[4,4]f32

@(private = "package")
Global :: struct {
    kb_state:       KeyboardState,
    event_queue:    EventQueue,
    mouse_position: [2]i32,
    window_count:   u32,
    graphics:       Graphics,
    dt:             time.Time,
    elapsed:        time.Time,
    logger:         log.Logger,
}

@(private = "package")
g: Global

@(private = "package")
string_to_cstring16 :: proc(s: string, allocator := context.temp_allocator) -> cstring16 {
    return cstring16(raw_data(win.utf8_to_utf16(s, allocator)))
}