package redef

import "core:log"
import "core:fmt"
import "base:runtime"
import win "core:sys/windows"

ctrl_down: bool

CLASSNAME :: "BigPPClass"
APPNAME :: "BigPPWindow"

main :: proc() {
    context.logger = log.create_console_logger()
    hinst: win.HANDLE = auto_cast win.GetModuleHandleW(nil)

    wc: win.WNDCLASSEXW
    {   using win, wc
        cbSize = size_of(wc)
        style = CS_OWNDC
        lpfnWndProc = WndProc
        hInstance = hinst
        lpszClassName = CLASSNAME
    }

    if error := win.RegisterClassExW(&wc); error == 0 {
        win.MessageBoxW(nil, "Unable to Register Window Class", "Error", win.MB_ICONERROR)
        return
    }

    handle := win.CreateWindowExW(0, 
        CLASSNAME,
        APPNAME,
        win.WS_CAPTION | win.WS_MINIMIZEBOX | win.WS_SYSMENU,
        200, 200, 640, 480,
        nil, nil,
        hinst,
        nil
    )
    win.ShowWindow(handle, win.SW_SHOW)

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

WndProc :: proc "stdcall" (
    hwnd: win.HWND,
    msg: win.UINT,
    wparam: win.WPARAM,
    lparam: win.LPARAM
) -> win.LRESULT {
    context = runtime.default_context()
    // log_windows_message(msg, wparam, lparam)
    switch msg {
        case win.WM_CLOSE:
            win.PostQuitMessage(69)
        case win.WM_KEYDOWN:
            switch wparam {
                case 17: ctrl_down = true
                case 67: if ctrl_down do win.PostQuitMessage(420)
            }
        case win.WM_KEYUP: 
            switch wparam {
                case 17: ctrl_down = false
            }
        
    }
    return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

