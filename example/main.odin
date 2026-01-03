package redef_example

import "core:fmt"
import "base:runtime"
import "core:math/linalg"
import rd "../src"

SCREENW :: 840
SCREENH :: 580

BACKROUND :: [4]f32 {0.2, 0.2, 0.2, 1.0}

shader_src := #load("shaders/shaders.hlsl")

main :: proc() {
    // Create a window. Debug mode is enabled when compiled with -debug
    window := rd.create_window("Big pp window", SCREENW, SCREENH, ODIN_DEBUG); assert(window != nil)

    // Make sure window gets destroyed
    defer rd.destroy_window(window)

    // Create vertex shader
    // load_vertex_shader() takes as input the Vertex struct which must match the vertex input structure in your shader
    ok: bool
    vertex_shader: rd.VertexShader
    vertex_shader, ok = rd.load_vertex_shader(shader_src, "vs_main", Vertex); assert(ok)

    // Create pixel shader
    pixel_shader: rd.PixelShader
    pixel_shader, ok = rd.load_pixel_shader(shader_src, "ps_main"); assert(ok)

    // Load a mesh
    cube: Mesh
    cube, ok = load_mesh("example/cube.obj"); assert(ok)

    // Create vertex and index buffer from it
    vertex_buffer := rd.create_vertex_buffer(cube.vertices)
    index_buffer  := rd.create_index_buffer(cube.indices)

    // Bind resources
    ok = rd.bind(&vertex_buffer); assert(ok)
    ok = rd.bind(&index_buffer);  assert(ok)
    ok = rd.bind(&vertex_shader); assert(ok)
    ok = rd.bind(&pixel_shader);  assert(ok)

    // Create a view-projection matrix
    proj := create_proj_matrix()
    view := create_view_matrix(0, 0, 0)
    vp := proj * view
    rd.push_constant_data(.Vertex, &vp, 0)

    // Create colors to be used in pixel shader
    colors: [6]vec4 = {
        {1, 0, 0, 1},
        {0, 1, 0, 1},
        {0, 0, 1, 1},
        {1, 1, 0, 1},
        {1, 0, 1, 1},
        {0, 1, 1, 1}
    }

    rd.push_constant_data(.Pixel, &colors, 0)

    // Set variables
    running := true
    frame: u32

    // ------ Main loop -------
    for running {

        // ------ End of Frame -------
        defer {
            free_all(context.temp_allocator)
            frame += 1
        }

        // ------- User Input --------
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

        // -------- Render ----------
        // Clear the screen
        rd.clear(BACKROUND)

        // First cube
        model_matrix := linalg.matrix4_from_trs_f32(
            t = {1.5, 0, -3}, 
            r = linalg.quaternion_angle_axis_f32(linalg.to_radians(f32(frame)/2.25), {0.4, 0.9, -0.5}),
            s = 1
        )
        rd.push_constant_data(.Vertex, &model_matrix, 1)
        rd.draw_indexed(index_buffer.length)

        // Second cube
        model_matrix = linalg.matrix4_from_trs_f32(
            t = {-1.5, 0, -3}, 
            r = linalg.quaternion_angle_axis_f32(linalg.to_radians(f32(frame)/3), {-0.5, -0.2, 0.5}),
            s = 1
        )
        rd.push_constant_data(.Vertex, &model_matrix, 1)
        rd.draw_indexed(index_buffer.length)

        // Finish the frame
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