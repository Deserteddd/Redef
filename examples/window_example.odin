package redef_example

import "core:fmt"
import "base:runtime"
import "core:math/linalg"
import rd "../src"

Vertex :: struct {
    pos: [2]f32,
    col: [4]f32
}

SCREENW :: 720
SCREENH :: 480

BACKROUND :: [4]f32 {0.2, 0.2, 0.2, 1.0}

shaders_hlsl := #load("shaders/shaders.hlsl")

main :: proc() {
    // Create a window. ODIN_DEBUG is true when compiled with -debug
    window := rd.create_window("Big pp window", SCREENW, SCREENH, ODIN_DEBUG); assert(window != nil)

    // Make sure window gets destroyed
    defer rd.destroy_window(window)

    // Create Vertex shader
    ok: bool
    vs: rd.VertexShader
    vs, ok = rd.load_vertex_shader(shaders_hlsl, "vs_main", Vertex); assert(ok)

    // Create a pixel shader
    ps: rd.PixelShader
    ps, ok = rd.load_pixel_shader(shaders_hlsl, "ps_main");         assert(ok)

    // Declare a triangle
    tri := []Vertex {
        {{   0,  0.5}, {1, 0, 0, 1}},
        {{ 0.5, -0.5}, {0, 1, 0, 1}},
        {{-0.5, -0.5}, {0, 0, 1, 1}},
    }

    // Create vertex buffer from it
    vbo  := rd.create_vertex_buffer(&tri)

    // Main loop setup
    running := true
    frame: u32

    // Main loop
    for running {

        // Things to do before a new frame
        defer {
            free_all(context.temp_allocator)
            frame += 1
        }

        // Get user input
        for event in rd.pump_event_iter(window) {
            #partial switch ev in event {
                // Quit message from OS
                case rd.Quit: 
                    fmt.println("Received exit code:", ev)
                    running = false

                // Ctrl+C pressed
                case rd.KeyboardEvent:
                    if ev.key == .C && .CONTROL in ev.mod {
                        running = false
                    }
            }
        }

        // Clear the screen
        rd.clear_buffer(BACKROUND)

        // Construct a model matrix for our triangle
        mpos := rd.get_mouse_position()
        r := linalg.matrix4_rotate_f32(linalg.to_radians(f32(frame)), {0, 0, 1})
        t := linalg.matrix4_translate_f32({f32(mpos.x)/SCREENW * 2 - 1, -f32(mpos.y)/SCREENH * 2 + 1, 0})
        s := linalg.matrix4_scale_f32({f32(SCREENH) / SCREENW, 1, 1})
        mat := linalg.transpose(t * r * s) // HLSL expects column-major matricies

        // Create a constant buffer from it
        cb := rd.create_constant_buffer(&mat)

        // Draw and submit frame
        rd.draw(vs, ps, vbo, &cb)
        rd.frame_end()
    }
}