package redef

MouseButton :: enum {
    LEFT,
    RIGHT,
    MIDDLE
}

Mouse :: struct {
    button_state: bit_set[MouseButton],
    raw_input_buffer: [dynamic; 48]u8
}

is_lmb_down :: proc() -> bool {
    return .LEFT in g.mouse.button_state
}