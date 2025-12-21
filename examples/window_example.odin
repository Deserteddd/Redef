package redef_example

import "core:log"
import "base:runtime"
import "core:math"
import rd "../src"

main :: proc() {
    when !ODIN_DEBUG do context.logger = log.create_console_logger()

    window := rd.create_window("Big pp window", 640, 480, ODIN_DEBUG); assert(window != nil)
    defer rd.destroy_window(window)

    running := true
    frame: u32
    for running {
        defer {
            free_all(context.temp_allocator)
            frame += 1
        }
        for event in rd.pump_event_iter(window) {
            #partial switch ev in event {
                case rd.Quit:
                    log.debug("Received exit code:", ev)
                    running = false
                
                case rd.TextInput:
                    log.debug("Text input:", ev.key)
                case rd.KeyboardEvent:
                    if ev.key == .C && .CONTROL in ev.mod {
                        running = false
                    }
                case rd.MouseEvent:
                    log.debugf("Mouse event %v at position %v. mod: %v", ev.type, ev.position, ev.mod)
            }
        }

        // Rendering
        b := 1/f32(frame % 255)
        rd.clear_buffer({0 , 0, b, 1})
        rd.frame_end()
    }

}

