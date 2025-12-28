package redef_example

import "core:log"
import "base:runtime"
import "core:time"
import "core:math"
import rd "../src"

main :: proc() {
    when !ODIN_DEBUG do context.logger = log.create_console_logger()

    window := rd.create_window("Big pp window", 640, 480, ODIN_DEBUG); assert(window != nil)
    defer rd.destroy_window(window)

    running := true
    frame: u32
    for running {
        now := time.now()
        defer {
            free_all(context.temp_allocator)
            frame += 1
            if frame%120 == 0 do log.debugf("Frame time: %v", rd.get_dt()/120)
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
        t := math.sin(time.duration_milliseconds(rd.time_since_start())/225) / 6 + 0.35
        rd.clear_buffer({f32(t), 0.2, f32(t), 1})
        rd.draw_triangle()
        rd.frame_end()
    }

}

