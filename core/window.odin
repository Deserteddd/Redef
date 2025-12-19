package redef_core

import "base:runtime"
import "core:log"
import "core:fmt"
import win "core:sys/windows"
import que "core:container/queue"

EventQueue :: que.Queue(Event)
KeyboardState :: #sparse[Keycode]bool

@(private = "file")
add_event :: proc(event: Event) {
    que.enqueue(&event_queue, event)
}

@(private = "file")
kb_state: KeyboardState

@(private = "file")
event_queue: EventQueue

@(private = "file")
mouse_position: [2]i32

WindowHandle :: win.HWND

Window :: struct {
    handle: WindowHandle,
    window_class: WindowClass,
    size: [2]i32
}

KeyboardEventType :: enum {
    KeyDown,
    KeyUp,
    Repeat,
}

TextInput :: struct {
    key: rune
}

KeyboardEvent :: struct {
    type: KeyboardEventType,
    key: Keycode,
    text: rune
}

MouseEvent :: struct {
    type: MouseEventType,

    // Relative mouse position at the time of the event
    position: [2]i32
}

MouseEventType :: enum {
    LPress,
    LRelease,
    RPress,
    RRelease,
    MPress,
    MRelease,

    // For wheel events, MouseEvent.position corresponds to scroll direction
    // e.g. move wheel up -> event.mouse == {-1, 0}
    MWheel,
    Move,
}


Quit :: distinct i32

Event :: union {
    Quit,
    KeyboardEvent,
    MouseEvent,
    TextInput
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
    context.logger = log.create_console_logger(allocator = context.temp_allocator)
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
        win.WS_CAPTION | win.WS_MINIMIZEBOX | win.WS_SYSMENU | win.WS_VISIBLE,
        win.CW_USEDEFAULT, win.CW_USEDEFAULT, wr.right - wr.left, wr.bottom - wr.top,
        nil, nil, wc.hInstance, &window
    )
    if hwnd == nil {
        log_win_err()
        return nil
    }

    window.handle = hwnd
    window.window_class = wc
    window.size = {wr.right - wr.left, wr.bottom - wr.top}
    
    que.init(&event_queue, capacity = 32)
    win.GetKeyboardState(auto_cast &kb_state)
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
    context.logger = log.create_console_logger()

    log.info("handle message setup")
    log_windows_message(msg, wparam, lparam)
    if msg == win.WM_NCCREATE {
        log.info("Msg was WM_NCCREATE")
        pCreate: ^win.CREATESTRUCTW = transmute(^win.CREATESTRUCTW)lparam
        log.info(pCreate.lpszName)
        pWnd: ^Window = auto_cast pCreate.lpCreateParams
        log.info(pWnd.size)
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
    context.logger = log.create_console_logger(allocator = context.temp_allocator)

    // log_windows_message(msg, wparam, lparam)
    switch msg {
        case win.WM_CLOSE:
            win.PostQuitMessage(69)
        case win.WM_DESTROY:
            win.PostQuitMessage(420)
        
        // -- Keyboard events --
        case win.WM_KEYDOWN:
            create_kb_event( kb_state[Keycode(wparam)] ? .Repeat : .KeyDown, wparam)
        case win.WM_KEYUP:
            create_kb_event(.KeyUp, wparam)

        case win.WM_CHAR:
            event: Event = TextInput { key = rune(wparam) }
            add_event(event)
        // -- Mouse events --
        // Left
        case win.WM_LBUTTONDOWN:
            event := create_mb_event(.LPress, lparam)
            add_event(event)
        case win.WM_LBUTTONUP:
            event := create_mb_event(.LRelease, lparam)
            add_event(event)

        // Right
        case win.WM_RBUTTONDOWN:
            event := create_mb_event(.RPress, lparam)
            add_event(event)
        case win.WM_RBUTTONUP:
            event := create_mb_event(.RRelease, lparam)
            add_event(event)

        // Middle
        case win.WM_MBUTTONDOWN:
            event := create_mb_event(.MRelease, lparam)
            add_event(event)
        case win.WM_MBUTTONUP:
            event := create_mb_event(.MRelease, lparam)
            add_event(event)
        
        // Move
        case win.WM_MOUSEMOVE:
            event := create_mb_event(.Move, lparam)
            add_event(event)
    }
    return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

create_kb_event :: proc(event_type: KeyboardEventType, wparam: win.WPARAM) {
    keycode := Keycode(wparam)
    event: Event = KeyboardEvent {type = event_type, key = keycode}
    switch event_type {
        case .KeyDown:
            assert(kb_state[keycode] == false)
            kb_state[keycode] = true
        case .KeyUp:
            assert(kb_state[keycode] == true)
            kb_state[keycode] = false
        case .Repeat:
            assert(kb_state[keycode])
    }
    que.enqueue(&event_queue, event)
}

create_mb_event :: proc(event_type: MouseEventType, lparam: win.LPARAM) -> MouseEvent {
    x := win.GET_X_LPARAM(lparam)
    y := win.GET_Y_LPARAM(lparam)
    return MouseEvent {
        type = event_type,
        position = {x, y}
    }
}

pump_event_iter :: proc(window: ^Window) -> (Event, bool) {
    msg: win.MSG
    result := win.GetMessageW(&msg, nil, 0, 0)
    if result <= 0 do return Quit(result == -1 ? -1 : i32(msg.wParam)), true
    win.TranslateMessage(&msg)
    win.DispatchMessageW(&msg)

    if que.len(event_queue) > 0 {
        return que.pop_front(&event_queue), true
    }
    return {}, false
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

get_mouse_position :: proc() -> [2]i32 {
    return mouse_position
}