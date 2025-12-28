package redef_example

import "core:fmt"
import "base:runtime"
import rd "../src"

Vertex :: struct {
    pos: [2]f32,
    col: [4]f32
}

shaders_hlsl := #load("shaders/shaders.hlsl")

main :: proc() {

    window := rd.create_window("Big pp window", 640, 480, ODIN_DEBUG); assert(window != nil)
    defer rd.destroy_window(window)
    ok: bool
    vs: rd.VertexShader
    vs, ok = rd.load_vertex_shader(shaders_hlsl, "vs_main", Vertex); assert(ok)
    ps1, ps2: rd.PixelShader
    ps1, ok = rd.load_pixel_shader(shaders_hlsl, "ps_main");         assert(ok)
    ps2, ok = rd.load_pixel_shader(shaders_hlsl, "ps_main2");        assert(ok)
    tri := []Vertex {
        {{   0,  0.5}, {1, 0, 0, 1}},
        {{ 0.5, -0.5}, {0, 1, 0, 1}},
        {{-0.5, -0.5}, {0, 0, 1, 1}},
    }

    vbo := rd.create_vertex_buffer(&tri)

    running := true
    frame: u32
    ps_switch: bool
    for running {
        defer {
            free_all(context.temp_allocator)
            frame += 1
            if frame%60 == 0 {
                ps_switch = !ps_switch
            }
        }
        for event in rd.pump_event_iter(window) {
            #partial switch ev in event {
                case rd.Quit:
                    fmt.println("Received exit code:", ev)
                    running = false
                
                case rd.TextInput:
                    fmt.println("Text input:", ev.key)
                case rd.KeyboardEvent:
                    fmt.println(ev.type, ev.key)
                    if ev.key == .C && .CONTROL in ev.mod {
                        running = false
                    }
                case rd.MouseEvent:
                    fmt.println("Mouse event %v at position %v. mod: %v", ev.type, ev.position, ev.mod)
            }
        }
        rd.clear_buffer({0.2, 0.2, 0.2, 1})
        rd.draw(vs, ps_switch ? ps1 : ps2, vbo)
        rd.frame_end()
    }

}