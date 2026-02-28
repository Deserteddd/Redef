package redef_example

import "core:fmt"
import "core:log"
import "core:time"
import rng "core:math/rand"
import "base:runtime"
import "core:math/linalg"
import rd "../src"

BACKROUND :: [4]f32 {0.13, 0.13, 0.13, 1.0}


shader_src := #load("shaders/shaders.hlsl")

main :: proc() {
    context.logger = log.create_console_logger()
    // Create a window. Debug mode is enabled when compiled with -debug
    window := rd.create_window("rd window", 1280, 720, ODIN_DEBUG); assert(window != nil)
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
    mesh: Mesh
    mesh, ok = load_mesh_gltf("example/assets/earth.glb"); assert(ok)
    
    // Load and bind a texture
    image: Image
    base_tex := rd.load_texture(mesh.texture.pixels, u32(mesh.texture.size.x), u32(mesh.texture.size.y))
    rd.bind(&base_tex)
    
    // Create instance
    grid_n := 4
    grid_spacing: f32 = 6
    cubes := entities_from_mesh(mesh, grid_n, grid_spacing)

    // Create a view-projection matrix
    proj := create_proj_matrix(window)
    view := create_view_matrix(0, 0, 0)
    vp := proj * view
    rd.push_constant_data(.Vertex, &vp, 0)

    // Set variables
    running := true
    frame: u32

    // ------ Main loop -------
    for running {
        // ------ End of Frame -------
        defer {
            free_all(context.temp_allocator)
            frame += 1
            // fmt.println(window.width, window.height)
        }
        // ------- User Input --------
        for event in rd.pump_event_iter(window) {
            #partial switch ev in event {
                // Quit message from OS
                case rd.Quit: 
                    fmt.println("Received exit code:", ev)
                    running = false

                case rd.WindowResized:
                    // fmt.println("Window resized to:", ev)

                // Ctrl+C pressed
                case rd.KeyboardEvent:
                    if ev.type == .KeyDown || ev.type == .Repeat {
                        #partial switch ev.key {
                            case .C:
                                if .CONTROL in ev.mod do running = false
                            case .ESCAPE:
                                running = false
                            case .OEM_PLUS, .ADD, .W:
                                grid_spacing += 0.25
                                layout_entities_in_grid(cubes, grid_n, grid_spacing)
                                fmt.println("grid spacing:", grid_spacing)
                            case .OEM_MINUS, .SUBTRACT, .S:
                                grid_spacing -= 0.25
                                if grid_spacing < 0.25 do grid_spacing = 0.25
                                layout_entities_in_grid(cubes, grid_n, grid_spacing)
                                fmt.println("grid spacing:", grid_spacing)
                        }
                    }
            }
        }
        update(&cubes, frame)
        draw(window, cubes)
    }
}

update :: proc(entitites: ^#soa[]Entity, frame: u32) {
    delta_rotation := linalg.quaternion_angle_axis_f32(
        linalg.to_radians(f32(0.2)),
        vec3{0, 1, 0},
    )
    for &e, i in entitites {
        _ = i
        e.physics.rotation = delta_rotation * e.physics.rotation
    }
}

draw :: proc(window: ^rd.Window, entities: #soa[]Entity) {
    rd.clear(BACKROUND)
    ok: bool

    proj := create_proj_matrix(window)
    view := create_view_matrix(0, 0, 0)
    vp := proj * view
    rd.push_constant_data(.Vertex, &vp, 0)

    for &e, i in entities {
        ok = rd.bind(&e.vbo)
        ok = rd.bind(&e.ibo)
        model_matrix := linalg.matrix4_from_trs_f32(
            t = e.physics.position, 
            r = e.physics.rotation,
            s = e.physics.scale
        )
        rd.push_constant_data(.Vertex, &model_matrix, 1)
        rd.draw_indexed(e.ibo.length)
    }

    rd.frame_end()
}

create_view_matrix :: proc(pitch, yaw: f32, camera_pos: vec3) -> linalg.Matrix4f32 {
    using linalg
    pitch_matrix := matrix4_rotate_f32(to_radians(pitch), {1, 0, 0})
    yaw_matrix := matrix4_rotate_f32(to_radians(yaw), {0, 1, 0})
    position_matrix := matrix4_translate_f32(camera_pos)
    return pitch_matrix * yaw_matrix * position_matrix
}

create_proj_matrix :: proc(window: ^rd.Window) -> linalg.Matrix4f32 {
    using linalg
    aspect := f32(window.width) / f32(window.height)
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

entities_from_mesh :: proc(mesh: Mesh, n: int, spacing: f32 = 1, allocator := context.allocator) -> #soa[]Entity {
    if n <= 0 {
        return make_soa(#soa[]Entity, 0, allocator = allocator)
    }

    total := n * n * n
    vbo := rd.create_vertex_buffer(mesh.vertices)
    ibo := rd.create_index_buffer(mesh.indices)
    entities := make_soa(#soa[]Entity, total, allocator = allocator)
    for &e, index in entities {
        _ = index
        initial_angle := rng.float32_range(0, 360)
        e.physics.rotation = linalg.quaternion_angle_axis_f32(linalg.to_radians(initial_angle), vec3{0, 1, 0})
        e.physics.scale = 1
        e.ibo = ibo
        e.vbo = vbo
    }

    layout_entities_in_grid(entities, n, spacing)
    return entities
}

layout_entities_in_grid :: proc(entities: #soa[]Entity, n: int, spacing: f32) {
    if n <= 0 do return
    center := f32(n - 1) * 0.5
    for &e, index in entities {
        x := index % n
        y := (index / n) % n
        z := index / (n * n)

        e.physics.position = {
            (f32(x) - center) * spacing,
            (f32(y) - center) * spacing,
            (f32(z) - center) * spacing - 10,
        }
    }
}