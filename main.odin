package redef

import "core:log"
import "base:runtime"
import win "core:sys/windows"

import rd "core"


main :: proc() {
    context.logger = log.create_console_logger()
    window := rd.create_window("Big pp window", 640, 480); assert(window != nil)
    defer rd.destroy_window(window)
    msg: win.MSG
    result: win.INT
    defer log.info("Program exited with code:", result == -1 ? result : i32(msg.wParam))
    for {
        result = win.GetMessageW(&msg, nil, 0, 0)
        if result <= 0 do break
        win.TranslateMessage(&msg)
        win.DispatchMessageW(&msg)
        free_all(context.temp_allocator)
    }
}

