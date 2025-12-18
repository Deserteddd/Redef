package redef_core

import "base:runtime"
import "core:log"
import "core:fmt"
import win "core:sys/windows"

Window :: struct {
    handle: rawptr,
    window_class: WindowClass,
    size: [2]i32
}

@(private = "file")
WindowClass :: win.WNDCLASSEXW

@(private = "file")
create_window_class :: proc(name: cstring16) -> (window_class: WindowClass, ok: bool) {
    log.info("create window class")
    hinst: win.HANDLE = auto_cast win.GetModuleHandleW(nil)
    if hinst == nil {
        log_win_err()
        return {}, false
    }
    wc: win.WNDCLASSEXW
    {   using win, wc
        cbSize = size_of(wc)
        style = CS_OWNDC
        lpfnWndProc = handle_msg_setup
        hInstance = hinst
        lpszClassName = name
    }
    if error := win.RegisterClassExW(&wc); error == 0 {
        log_win_err()
        return {}, false
    }
    return wc, true
}

log_win_err :: proc(loc := #caller_location) -> (was_error: bool = true) {
    err := win.GetLastError()
    if err == 0 do return false
    pMsgBuf: [^]u16
    ok := win.FormatMessageW(
        win.FORMAT_MESSAGE_ALLOCATE_BUFFER |
        win.FORMAT_MESSAGE_FROM_SYSTEM | win.FORMAT_MESSAGE_IGNORE_INSERTS,
        nil, err, win.MAKELANGID(win.LANG_NEUTRAL, win.SUBLANG_DEFAULT),
        transmute(win.LPWSTR)&pMsgBuf, 0, nil
    )
    if ok == 0 do panic("Unable to log error")
    win_error_string16 := cstring16(pMsgBuf)

    error := fmt.aprintf("%v\n%v: %v", loc, err, win_error_string16)
    error_16 := win.utf8_to_wstring(error)
    log.errorf("Windows error [%v]: %v", err, error)
    win.MessageBoxW(nil, error_16, "Error", win.MB_ICONERROR)
    win.LocalFree(pMsgBuf)
    return
}

create_window :: proc(name: string, width, height: i32) -> ^Window {
    log.info("create window")
    window := new(Window)
    name_16 := win.utf8_to_wstring(name)
    wc, ok := create_window_class(name_16)
    if !ok do return nil
    wr: win.RECT
    wr.left = 100;
    wr.right = width + wr.left;
    wr.top = 100;
    wr.bottom = height + wr.top;
    ok = auto_cast win.AdjustWindowRect(&wr, win.WS_CAPTION | win.WS_MINIMIZEBOX | win.WS_SYSMENU, win.FALSE)
    if !ok {
        log_win_err()
        return nil
    }
    hwnd := win.CreateWindowW( 
        wc.lpszClassName,
        name_16,
        win.WS_CAPTION | win.WS_MINIMIZEBOX | win.WS_SYSMENU,
        win.CW_USEDEFAULT, win.CW_USEDEFAULT, wr.right - wr.left, wr.bottom - wr.top,
        nil, nil, wc.hInstance, &window
    )
    if hwnd == nil {
        log_win_err()
        return nil
    }
    win.ShowWindow(hwnd, win.SW_SHOW)

    window.handle = hwnd
    window.window_class = wc
    window.size = {wr.right - wr.left, wr.bottom - wr.top}
    
    return window
}

@(private = "file")
handle_msg_setup :: proc "stdcall" (
    hwnd: win.HWND,
    msg: win.UINT,
    wparam: win.WPARAM,
    lparam: win.LPARAM
) -> win.LRESULT {
    context = runtime.default_context()
    log.info("handle message setup")
    if msg == win.WM_NCCREATE {
        pCreate: ^win.CREATESTRUCTW = transmute(^win.CREATESTRUCTW)lparam
        pWnd: ^Window = auto_cast pCreate.lpCreateParams
        log.info(pCreate.lpszName)
        win.SetLastError(0)
        ok := win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, transmute(win.LONG_PTR)pWnd)
        if ok == 0 do if log_win_err() do return 0
        win.SetLastError(0)
        ok = win.SetWindowLongPtrW(hwnd, win.GWLP_WNDPROC, transmute(win.LONG_PTR)WndProc)
        if ok == 0 do if log_win_err() do return 0
        pWnd.window_class.lpfnWndProc = WndProc
        return pWnd.window_class.lpfnWndProc(hwnd, msg, wparam, lparam)
    }
    return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}



@(private = "file")
WndProc :: proc "stdcall" (
    hwnd: win.HWND,
    msg: win.UINT,
    wparam: win.WPARAM,
    lparam: win.LPARAM
) -> win.LRESULT {
    context = runtime.default_context()
    context.logger = log.create_console_logger()
    // log_windows_message(msg, wparam, lparam)
    switch msg {
        case win.WM_CLOSE:
            win.PostQuitMessage(69)
            return 0
        case win.WM_KEYDOWN:
            log.debug(Key(wparam), wparam)
        case win.WM_LBUTTONDOWN:
            x := win.GET_X_LPARAM(lparam)
            y := win.GET_Y_LPARAM(lparam)
        case win.WM_MOUSEMOVE:
            x := win.GET_X_LPARAM(lparam)
            y := win.GET_Y_LPARAM(lparam)
    }
    return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

destroy_window :: proc(w: ^Window) {
    win.UnregisterClassW(w.window_class.lpszClassName, w.window_class.hInstance)
    win.DestroyWindow(auto_cast w.handle)
}

get_window_size :: proc(w: ^Window) -> [2]i32 {
    return w.size
}

get_window_name :: proc(w: ^Window) -> cstring16 {
    return w.window_class.lpszClassName
}