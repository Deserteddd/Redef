package redef_example

import "core:log"
import "base:runtime"
import rd "../src"

Vertex :: struct {
    pos: [2]f32,
    col: [4]f32
}

shaders_hlsl := #load("shaders/shaders.hlsl")

main :: proc() {
    when !ODIN_DEBUG do context.logger = log.create_console_logger()

    window := rd.create_window("Big pp window", 640, 480, ODIN_DEBUG); assert(window != nil)
    defer rd.destroy_window(window)
    vs := rd.load_vertex_shader(shaders_hlsl, "vs_main", Vertex)
    assert(vs != nil)
    ps1 := rd.load_pixel_shader(shaders_hlsl, "ps_main")
    assert(ps1 != nil)
    ps2 := rd.load_pixel_shader(shaders_hlsl, "ps_main2")
    assert(ps2 != nil)

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
                    log.debug("Received exit code:", ev)
                    running = false
                
                case rd.TextInput:
                    log.debug("Text input:", ev.key)
                case rd.KeyboardEvent:
                    log.debug(ev.type, ev.key)
                    if ev.key == .C && .CONTROL in ev.mod {
                        running = false
                    }
                case rd.MouseEvent:
                    log.debugf("Mouse event %v at position %v. mod: %v", ev.type, ev.position, ev.mod)
            }
        }
        rd.clear_buffer({0.2, 0.2, 0.2, 1})
        rd.draw_triangle(vs, ps_switch ? ps1 : ps2)
        rd.frame_end()
    }

}

