package redef_example

import "core:fmt"
import "core:time"
import "base:runtime"
import "core:slice"
import "core:strings"
import "core:math/linalg"
import stbi "vendor:stb/image"
import rd "../src"

SCREENW :: 1280
SCREENH :: 720

BACKROUND :: [4]f32 {0.1, 0.1, 0.1, 1.0}

shader_src := #load("shaders/shaders.hlsl")

main :: proc() {
    // Create a window. Debug mode is enabled when compiled with -debug
    window := rd.create_window("Big pp window", SCREENW, SCREENH, ODIN_DEBUG); assert(window != nil)

    // Make sure window gets destroyed
    defer rd.destroy_window(window)

    // Create vertex shader
    ok: bool
    vertex_shader: rd.VertexShader
    vertex_shader, ok = rd.load_vertex_shader(shader_src, "vs_main", Vertex); assert(ok)

    // Create pixel shader
    pixel_shader: rd.PixelShader
    pixel_shader, ok = rd.load_pixel_shader(shader_src, "ps_main"); assert(ok)

    // Bind shaders
    ok = rd.bind(&vertex_shader); assert(ok)
    ok = rd.bind(&pixel_shader);  assert(ok)

    // Load a mesh
    cube: Mesh
    cube, ok = load_mesh("example/cube.obj"); assert(ok)
    
    pixels, size := load_pixels_byte("example/stone.jpg")
    base_tex := rd.load_texture(pixels, u32(size.x), u32(size.y))
    rd.bind(&base_tex)

    cubes := entities_from_mesh(cube, 1000)

    // Create a view-projection matrix
    proj := create_proj_matrix()
    view := create_view_matrix(0, 0, 0)
    vp := proj * view
    rd.push_constant_data(.Vertex, &vp, 0)

    // Procedure to create and upload new color data to GPU
    push_cube_colors :: proc() {
        cube_colors: [6]vec4
        for &c in cube_colors {
            c = {
                rng.float32_range(0, 1),
                rng.float32_range(0, 1),
                rng.float32_range(0, 1), 
                1
            }
        }
        rd.push_constant_data(.Pixel, &cube_colors, 0)
    }

    // Create colors to be used in pixel shader
    push_cube_colors()

    // Set variables
    running := true
    frame: u32
    now := time.now()
    // ------ Main loop -------
    for running {
        // ------ End of Frame -------
        defer {
            if frame % 20 == 0 do push_cube_colors()
            frame_time := time.since(now)
            // fmt.println("Frame time:", frame_time)
            free_all(context.temp_allocator)
            now = time.now()
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
        update(cubes, frame)
        draw(cubes, frame)
        
    }
}

update :: proc(entitites: #soa[]Entity, frame: u32) {
    dt := f32(time.duration_milliseconds(rd.get_dt()))
    from_start := int(time.duration_seconds(rd.time_since_start()))
    toggle: f32 = frame % 60 == 0 ? -1 : 1
    for &e, i in entitites {
        e.physics.rotation = linalg.quaternion_angle_axis_f32(
            linalg.to_radians(f32(frame) * (f32(i)+1) / 1000), 
            vec3{0.4, 0.9, -0.5}
        )
        e.physics.position += e.physics.direction * dt/50 * linalg.pow(f32(frame%20), 2) * 0.01
        e.physics.direction *= toggle
    }
}

draw :: proc(entities: #soa[]Entity, frame: u32) {
    rd.clear(BACKROUND)
    ok: bool

    for &e, i in entities {
        if i == 0 {
            ok = rd.bind(&e.vbo)
            ok = rd.bind(&e.ibo)
        }
        model_matrix := linalg.matrix4_from_trs_f32(
            t = e.physics.position, 
            r = e.physics.rotation,
            s = e.physics.scale
        )
        rd.push_constant_data(.Vertex, &model_matrix, 1)
        rd.draw_indexed(e.ibo.length)
    }

    // Finish the frame
    rd.frame_end()
}

load_pixels_byte :: proc(path: string, loc := #caller_location) -> (pixels: []byte, size: [2]i32) {
    path_cstr := strings.unsafe_string_to_cstring(path);
    fmt.println("Loading:", path_cstr)
    
    pixel_data := stbi.load(path_cstr, &size.x, &size.y, nil, 4)
    assert(pixel_data != nil, loc = loc)
    pixels = slice.bytes_from_ptr(pixel_data, int(size.x * size.y * 4))
    assert(pixels != nil)
    return
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

Entity :: struct {
    physics:    Physics,
    vbo:        rd.VertexBuffer,
    ibo:        rd.IndexBuffer
}

Physics :: struct {
    position:   vec3,
    rotation:   quaternion128,
    scale:      vec3,
    direction:  vec3,
}

import rng "core:math/rand"

entities_from_mesh :: proc(mesh: Mesh, n := 1, allocator := context.allocator) -> #soa[]Entity {
    n := n
    vbo := rd.create_vertex_buffer(mesh.vertices)
    ibo := rd.create_index_buffer(mesh.indices)
    entities := make_soa(#soa[]Entity, n, allocator = allocator)
    for &e in entities {
        e.physics.position = {rng.float32_range(-100, 100), rng.float32_range(-100, 100), rng.float32_range(-100, 100)}
        e.physics.rotation = linalg.QUATERNIONF32_IDENTITY
        e.physics.direction = linalg.vector_normalize([3]f32 {
            rng.float32_range(-1, 1),
            rng.float32_range(-1, 1),
            rng.float32_range(-1, 1),
        })
        e.physics.scale = 1
        e.ibo = ibo
        e.vbo = vbo
    }
    return entities
}