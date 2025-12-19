package redef

import "core:log"
import "base:runtime"
import rd "core"

main :: proc() {
    when !ODIN_DEBUG {
        context.logger = log.create_console_logger()
    }
    window := rd.create_window("Big pp window", 640, 480); assert(window != nil)
    defer rd.destroy_window(window)
    running := true
    for running {
        // log.debug(rd.get_mouse_position())
        for event in rd.pump_event_iter(window) {
            #partial switch ev in event {
                case rd.Quit:
                    log.debug("Received exit code:", ev)
                    running = false
                case rd.KeyboardEvent:
                    #partial switch ev.type {
                        case .KeyDown:
                            log.debugf("Key %v pressed", ev.key)
                        case .KeyUp:
                            log.debugf("Key %v released", ev.key)
                    }
                case rd.TextInput:
                    log.debug("Text input:", ev.key)
                case rd.MouseEvent:
                    #partial switch ev.type {
                        case .LPress:
                            log.debug("LMB pressed at", ev.position)
                        case .LRelease:
                            log.debug("LMB released at", ev.position)
                    }

            }
        }

    }

}

