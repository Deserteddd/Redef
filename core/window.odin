package redef_core

import "base:runtime"
import "core:log"
import "core:fmt"
import win "core:sys/windows"
import que "core:container/queue"

EventQueue :: que.Queue(Event)

KeyboardState :: #sparse[Keycode]bool

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

ModKey :: enum u8 {
    CONTROL = u8(Keycode.CONTROL),
    SHIFT   = u8(Keycode.SHIFT),
}

ModKeys :: bit_set[ModKey]

TextInput :: struct {
    key: rune
}

KeyboardEvent :: struct {
    type: KeyboardEventType,
    key: Keycode,
    mod: ModKeys
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
kb_state: KeyboardState

@(private = "file")
event_queue: EventQueue

@(private = "file")
mouse_position: [2]i32

@(private = "file")
add_event :: proc(event: Event) { que.enqueue(&event_queue, event) }

@(private = "file")
create_window_class :: proc(name: cstring16) -> (window_class: WindowClass, ok: bool) {
    hinst: win.HMODULE = win.GetModuleHandleW(nil)
    if hinst == nil {
        log_win_err()
        return {}, false
    }
    wc: win.WNDCLASSEXW
    {   using win, wc
        cbSize = size_of(wc)
        style = CS_OWNDC
        lpfnWndProc = handle_msg_setup
        hInstance = auto_cast hinst
        lpszClassName = name
    }
    if error := win.RegisterClassExW(&wc); error == 0 {
        log_win_err()
        return {}, false
    }
    log.infof("Window class '%v' created", wc.lpszClassName)
    return wc, true
}

@(private = "file")
// Returns: true if a valid windows error exited
log_win_err :: proc(loc := #caller_location) -> bool {
    err := win.GetLastError()
    if err == 0 {
        log.warnf("return value of log_win_err() should not be relied upon", location = loc)
        return false
    } 
    pMsgBuf: [^]u16
    ok := win.FormatMessageW(
        win.FORMAT_MESSAGE_ALLOCATE_BUFFER |
        win.FORMAT_MESSAGE_FROM_SYSTEM | win.FORMAT_MESSAGE_IGNORE_INSERTS,
        nil, err, win.MAKELANGID(win.LANG_NEUTRAL, win.SUBLANG_DEFAULT),
        transmute(win.LPWSTR)&pMsgBuf, 0, nil
    )
    if ok == 0 do panic("Unable to log error")
    win_error_string16 := cstring16(pMsgBuf)

    error_string := fmt.aprintf("%v: %v", err, win_error_string16, allocator = context.temp_allocator)
    error_string_16 := win.utf8_to_wstring(error_string)
    log.errorf("Windows error %v", error_string, location = loc)
    win.MessageBoxW(nil, error_string_16, "Error", win.MB_ICONERROR)
    win.LocalFree(pMsgBuf)
    return true
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
    if msg == win.WM_NCCREATE {
        pCreate: ^win.CREATESTRUCTW = transmute(^win.CREATESTRUCTW)lparam
        pWnd: ^Window = auto_cast pCreate.lpCreateParams
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
    switch msg {
        case win.WM_CLOSE:       win.PostQuitMessage(69)
        
        // -- Keyboard events --
        case win.WM_KEYDOWN:     create_kb_event( kb_state[Keycode(wparam)] ? .Repeat : .KeyDown, wparam)
        case win.WM_KEYUP:       create_kb_event(.KeyUp, wparam)
        case win.WM_CHAR:        add_event(TextInput { key = rune(wparam)})

        // -- Mouse events --
        // Left
        case win.WM_LBUTTONDOWN: create_mouse_event(.LPress, lparam)
        case win.WM_LBUTTONUP:   create_mouse_event(.LRelease, lparam)

        // Right
        case win.WM_RBUTTONDOWN: create_mouse_event(.RPress, lparam)
        case win.WM_RBUTTONUP:   create_mouse_event(.RRelease, lparam)

        // Middle
        case win.WM_MBUTTONDOWN: create_mouse_event(.MPress, lparam)
        case win.WM_MBUTTONUP:   create_mouse_event(.MRelease, lparam)
    }
    return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@(private = "file")
create_kb_event :: proc(event_type: KeyboardEventType, wparam: win.WPARAM) {
    keycode := Keycode(wparam)
    mod: ModKeys
    mod += kb_state[.CONTROL] ? {.CONTROL} : {}
    mod += kb_state[.SHIFT] ? {.SHIFT} : {}
    event: Event = KeyboardEvent {type = event_type, key = keycode, mod = mod}
    switch event_type {
        case .KeyDown:
            kb_state[keycode] = true
        case .KeyUp:
            kb_state[keycode] = false
        case .Repeat:
            assert(kb_state[keycode])
    }
    que.enqueue(&event_queue, event)
}

@(private = "file")
create_mouse_event :: proc(event_type: MouseEventType, lparam: win.LPARAM) {
    x := win.GET_X_LPARAM(lparam)
    y := win.GET_Y_LPARAM(lparam)
    mouse_position = {x, y}
    add_event(MouseEvent {
        type = event_type,
        position = {x, y}
    })
}

create_window :: proc(name: string, width, height: i32) -> ^Window {
    defer free_all(context.temp_allocator)
    context.logger = log.create_console_logger(allocator = context.temp_allocator)
    window := new(Window)
    name_16 := win.utf8_to_wstring(name, context.allocator)
    wc, ok := create_window_class(name_16)
    if !ok do return nil

    // Adjust the rect so the canvas area of the window matches width and height parameters
    wr: win.RECT = {100, 100, width + 100, height + 100}
    ok = auto_cast win.AdjustWindowRect(&wr, win.WS_CAPTION | win.WS_MINIMIZEBOX | win.WS_SYSMENU, win.FALSE)
    if !ok {
        log_win_err()
        free(window)
        return nil
    }
    // window dimensions are meant to be user accessible and so they should match the canvas size
    window.size = {width, height}
    window.window_class = wc

    window.handle = win.CreateWindowW( 
        wc.lpszClassName,
        name_16,
        win.WS_CAPTION | win.WS_MINIMIZEBOX | win.WS_SYSMENU | win.WS_VISIBLE,
        win.CW_USEDEFAULT, 
        win.CW_USEDEFAULT,
        wr.right - wr.left,
        wr.bottom - wr.top,
        nil, nil, 
        wc.hInstance, 
        &window
    )
    if window.handle == nil {
        log_win_err()
        free(window)
        return nil
    }


    alloc_err := que.init(&event_queue, capacity = 32)
    if alloc_err != nil {
        destroy_window(window)
        log.errorf("Failed to init event queue. Allocation error: %v", alloc_err)
        return nil
    }
    log.debug("Window handle:", window.handle)
    log.infof("Window '%v' created", window.window_class.lpszClassName)
    return window
}

pump_event_iter :: proc(window: ^Window) -> (event: Event, ok: bool = true) {
    msg: win.MSG
    result := win.GetMessageW(&msg, nil, 0, 0)
    if result == -1 {
        ensure(log_win_err())
        event = Quit(-1)
        return
    } 
    if result == 0 {
        event = Quit(msg.wParam)
        return
    }
    win.TranslateMessage(&msg)
    win.DispatchMessageW(&msg)

    if que.len(event_queue) > 0 {
        event = que.dequeue(&event_queue)
        return
    }
    ok = false
    return
}

destroy_window :: proc(w: ^Window) {
    success := win.UnregisterClassW(w.window_class.lpszClassName, w.window_class.hInstance)
    if !success do log_win_err()
    
    log.debug("Window handle:", w.handle)
    success = win.DestroyWindow(w.handle)
    if !success do log_win_err()

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