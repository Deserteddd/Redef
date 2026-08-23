package redef

MouseButton :: enum {
    LEFT,
    RIGHT,
    MIDDLE
}

Mouse :: struct {
    button_state: bit_set[MouseButton],
    raw_input_buffer: [dynamic; 48]u8,
    lmb_pressed: bool
}

is_lmb_down :: proc() -> bool {
    return .LEFT in g.mouse.button_state
}

is_lmb_pressed :: proc() -> bool {
    return g.mouse.lmb_pressed
}