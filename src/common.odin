package redef
import "core:time"

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32

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