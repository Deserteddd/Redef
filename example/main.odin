package redef_example

import "core:fmt"
import "base:runtime"
import "core:math/linalg"
import rd "../src"

SCREENW :: 640
SCREENH :: 480

BACKROUND :: [4]f32 {0.2, 0.2, 0.2, 1.0}

shaders_hlsl := #load("shaders/shaders.hlsl")

main :: proc() {
    // Create a window. ODIN_DEBUG is true when compiled with -debug
    window := rd.create_window("Big pp window", SCREENW, SCREENH, ODIN_DEBUG); assert(window != nil)

    // Make sure window gets destroyed
    defer rd.destroy_window(window)

    // Create Vertex shader
    ok: bool
    vs: rd.VertexShader
    vs, ok = rd.load_vertex_shader(shaders_hlsl, "vs_main", Vertex); assert(ok)

    // Create a pixel shader
    ps: rd.PixelShader
    ps, ok = rd.load_pixel_shader(shaders_hlsl, "ps_main"); assert(ok)

    // Load a mesh
    cube: Mesh
    cube, ok = load_mesh("example/cube.obj"); assert(ok)

    // Create vertex buffer from it
    vbo := rd.create_vertex_buffer(cube.vertices)
    ibo := rd.create_index_buffer(cube.indices)

    // Main loop setup
    running := true
    frame: u32

    // Main loop
    for running {

        // Things to do before a new frame
        defer {
            free_all(context.temp_allocator)
            frame += 1
        }

        // Get user input
        for event in rd.pump_event_iter(window) {
            #partial switch ev in event {
                // Quit message from OS
                case rd.Quit: 
                    fmt.println("Received exit code:", ev)
                    running = false

                // Ctrl+C pressed
                case rd.KeyboardEvent:
                    if ev.key == .C && .CONTROL in ev.mod {
                        running = false
                    }
            }
        }

        // Clear the screen
        rd.clear_buffer(BACKROUND)


        // Drawing
        proj := create_proj_matrix()
        view := create_view_matrix(0, 0, 0)
        vp := proj * view
        ubo := [2]matrix[4,4]f32 {vp, {}}

        // First cube
        r := linalg.quaternion_angle_axis_f32(linalg.to_radians(f32(frame))/5, {1, 1, 0})
        ubo.y = linalg.matrix4_from_trs_f32(
            t = {0, 0, -3}, 
            r = r,
            s = 1
        )
        cb := rd.create_constant_buffer(&ubo)
        rd.draw_indexed(vs, ps, vbo, ibo, &cb)

        // Second cube
        r = linalg.quaternion_angle_axis_f32(linalg.to_radians(f32(frame))/5, {-1, -1, 0})
        ubo.y = linalg.matrix4_from_trs_f32(
            t = {0, 0, -10}, 
            r = -r,
            s = 4
        )
        cb = rd.create_constant_buffer(&ubo)
        rd.draw_indexed(vs, ps, vbo, ibo, &cb)

        rd.frame_end()
    }
}

create_view_matrix :: proc(pitch, yaw: f32, camera_pos: vec3) -> linalg.Matrix4f32 {
    using linalg
    pitch_matrix := matrix4_rotate_f32(to_radians(pitch), {1, 0, 0})
    yaw_matrix := matrix4_rotate_f32(to_radians(yaw), {0, 1, 0})
    position_matrix := matrix4_translate_f32(camera_pos)
    return pitch_matrix * yaw_matrix * position_matrix
}

create_proj_matrix :: proc() -> linalg.Matrix4f32 {
    using linalg
    aspect := f32(SCREENW) / f32(SCREENH)
    return matrix4_perspective_f32(
        to_radians(f32(90)), 
        aspect, 
        0.01, 
        1000
    )
}