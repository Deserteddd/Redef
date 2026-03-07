package redef

MouseButton :: enum {
    LEFT,
    RIGHT,
    MIDDLE
}

Mouse :: struct {
    button_state: bit_set[MouseButton]
}

is_lmb_down :: proc() -> bool {
    return .LEFT in g.mouse.button_state
}