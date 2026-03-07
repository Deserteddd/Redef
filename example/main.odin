package redef_example

import "core:fmt"
import "core:log"
import "core:time"
import "core:math"
import rng "core:math/rand"
import "base:runtime"
import "core:math/linalg"
import rd "../src"

BACKROUND :: [4]f32 {0.13, 0.13, 0.13, 1.0}


shader_src := #load("shaders/shaders.hlsl")

main :: proc() {
    context.logger = log.create_console_logger()
    // Create a window. Debug mode is enabled when compiled with -debug
    window := rd.create_window("rd window", 1280, 720, ODIN_DEBUG)
    rd.set_window_mode(.MAXIMIZED)

    // Make sure window gets destroyed
    defer rd.destroy_window()

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
    
    // Create entities: Sun + planets
    cubes := entities_from_mesh(mesh)

    camera := create_orbital_camera()

    // Set variables
    running := true
    frame: u32

    // ------ Main loop -------
    for running {
        // ------ End of Frame -------
        defer {
            free_all(context.temp_allocator)
            frame += 1
            // fmt.println(rd.get_dt())
        }
        // ------- User Input --------
        for event in rd.pump_event_iter() {
            #partial switch ev in event {
                // Quit message from OS
                case rd.Quit: 
                    fmt.println("Received exit code:", ev)
                    running = false

                case rd.WindowResized:
                    fmt.println("Window resized to:", ev)

                case rd.MouseEvent:
                    if ev.type == .MWheel do camera.distance -= f32(ev.position.x) * 7

                // Ctrl+C pressed
                case rd.KeyboardEvent:
                    if ev.type == .KeyDown || ev.type == .Repeat {
                        #partial switch ev.key {
                            case .C:
                                if .CONTROL in ev.mod do running = false
                            case .ESCAPE:
                                running = false
                            case .LEFT, .A:
                                camera.yaw -= camera.rotate_speed
                            case .RIGHT, .D:
                                camera.yaw += camera.rotate_speed
                            case .UP, .W:
                                camera.pitch += camera.rotate_speed
                            case .DOWN, .S:
                                camera.pitch -= camera.rotate_speed
                            case .Q, .SUBTRACT, .OEM_MINUS:
                                camera.distance += camera.zoom_speed
                            case .E, .ADD, .OEM_PLUS:
                                camera.distance -= camera.zoom_speed
                        }
                    }
            }
        }
        clamp_camera(&camera)
        if rd.is_lmb_down() do update_camera_from_relative_mouse_stub(&camera) 
        update(&cubes, frame)
        draw(cubes, camera)
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

draw :: proc(entities: #soa[]Entity, camera: Camera) {
    rd.clear(BACKROUND)
    ok: bool
    proj := create_proj_matrix()
    view := camera_view_matrix(camera)
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

Camera :: struct {
    target:         vec3,
    distance:       f32,
    min_distance:   f32,
    max_distance:   f32,
    yaw:            f32,
    pitch:          f32,
    min_pitch:      f32,
    max_pitch:      f32,
    rotate_speed:   f32,
    zoom_speed:     f32,
    mouse_sense:    f32,
}

create_orbital_camera :: proc() -> Camera {
    return Camera {
        target = {0, 0, -120},
        distance = 180,
        min_distance = 10,
        max_distance = 600,
        yaw = 0,
        pitch = 15,
        min_pitch = -85,
        max_pitch = 85,
        rotate_speed = 4.5,
        zoom_speed = 5.0,
        mouse_sense = 0.6,
    }
}

clamp_camera :: proc(camera: ^Camera) {
    camera.distance = math.clamp(camera.distance, camera.min_distance, camera.max_distance)
    camera.pitch = math.clamp(camera.pitch, camera.min_pitch, camera.max_pitch)
}

camera_position :: proc(camera: Camera) -> vec3 {
    yaw := linalg.to_radians(camera.yaw)
    pitch := linalg.to_radians(camera.pitch)

    radius_xz := camera.distance * math.cos(pitch)
    offset := vec3 {
        radius_xz * math.sin(yaw),
        camera.distance * math.sin(pitch),
        radius_xz * math.cos(yaw),
    }
    return camera.target + offset
}

camera_view_matrix :: proc(camera: Camera) -> linalg.Matrix4f32 {
    using linalg
    distance_matrix := matrix4_translate_f32(vec3{0, 0, -camera.distance})
    pitch_matrix := matrix4_rotate_f32(to_radians(camera.pitch), vec3{1, 0, 0})
    yaw_matrix := matrix4_rotate_f32(to_radians(camera.yaw), vec3{0, 1, 0})
    target_matrix := matrix4_translate_f32(-camera.target)
    return distance_matrix * pitch_matrix * yaw_matrix * target_matrix
}

update_camera_from_relative_mouse_stub :: proc(camera: ^Camera) {
    mouse_delta := rd.get_relative_mouse_movement()
    camera.yaw -= f32(mouse_delta.x) * camera.mouse_sense
    camera.pitch -= f32(mouse_delta.y) * camera.mouse_sense
    clamp_camera(camera)
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
    window_size := rd.get_window_size()
    aspect := window_size.x / window_size.y
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
}

entities_from_mesh :: proc(mesh: Mesh, allocator := context.allocator) -> #soa[]Entity {
    PlanetDef :: struct {
        orbital_radius_au: f32,
        radius_earth:      f32,
    }

    // Sun + 8 planets
    bodies := [9]PlanetDef {
        {0.0,   109.0}, // Sun
        {0.387,   0.383}, // Mercury
        {0.723,   0.949}, // Venus
        {1.000,   1.000}, // Earth
        {1.524,   0.532}, // Mars
        {3.203,  11.21 }, // Jupiter
        {7.537,   9.45 }, // Saturn
        {17.191,  4.01 }, // Uranus
        {28.07,   3.88 }, // Neptune
    }

    total := len(bodies)
    vbo := rd.create_vertex_buffer(mesh.vertices)
    ibo := rd.create_index_buffer(mesh.indices)
    entities := make_soa(#soa[]Entity, total, allocator = allocator)

    // World-space mapping tuned for readability:
    // - Orbit radius uses sqrt(AU) so outer planets are much closer together
    // - Planet radii are strongly remapped so rocky planets read closer to giants
    // - Sun is intentionally reduced (still much larger than planets)
    earth_scale: f32 = 0.30
    au_to_world: f32 = 22.0
    center_z: f32 = -120.0
    sun_radius_earth_visual: f32 = 18.0
    planet_radius_boost: f32 = 2.2
    rocky_radius_lift: f32 = 1.6
    giant_radius_compress: f32 = 0.75
    min_planet_radius_earth_visual: f32 = 1.8
    max_planet_radius_earth_visual: f32 = 6.5

    for &e, index in entities {
        body := bodies[index]
        initial_angle := rng.float32_range(0, 360)
        e.physics.rotation = linalg.quaternion_angle_axis_f32(linalg.to_radians(initial_angle), vec3{0, 1, 0})

        visual_radius_earth := body.radius_earth
        if index == 0 {
            visual_radius_earth = sun_radius_earth_visual
        } else {
            visual_radius_earth = body.radius_earth * planet_radius_boost
            if body.radius_earth <= 1.1 {
                visual_radius_earth += rocky_radius_lift
            }
            if body.radius_earth >= 8.0 {
                visual_radius_earth *= giant_radius_compress
            }
            visual_radius_earth = math.clamp(
                visual_radius_earth,
                min_planet_radius_earth_visual,
                max_planet_radius_earth_visual,
            )
        }

        uniform_scale := earth_scale * visual_radius_earth
        e.physics.scale = vec3{uniform_scale, uniform_scale, uniform_scale}
        orbit_radius := math.sqrt(body.orbital_radius_au) * au_to_world
        e.physics.position = vec3{orbit_radius, 0, center_z}
        e.ibo = ibo
        e.vbo = vbo
    }
    return entities
}