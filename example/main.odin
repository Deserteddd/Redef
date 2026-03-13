package redef_example

import "core:fmt"
import "core:log"
import "core:math"
import "core:time"
import os "core:os/os2"
import "core:slice"
import "base:runtime"
import "core:math/linalg"
import rng "core:math/rand"
import stbi "vendor:stb/image"
import rd "../src"

BACKGROUND :: [4]f32 {0, 0, 0, 0}
ORBIT_CENTER :: vec3 {0, 0, -120}
EARTH_ORBIT_SECONDS :: f32(20.0)
ORBIT_BAND_WIDTH :: f32(0.6)
ORBIT_DISTANCE_LINEAR_SCALE :: f32(14.0)
ORBIT_DISTANCE_ROOT_SCALE :: f32(10.0)
PLANET_RADIUS_LINEAR_SCALE :: f32(0.55)
PLANET_RADIUS_ROOT_SCALE :: f32(1.35)
PLANET_RENDER_SCALE :: f32(0.35)
SUN_RENDER_RADIUS :: f32(24.0)

vec3 :: rd.vec3


shader_src := #load("shaders/shaders.hlsl")

main :: proc() {
    context.logger = log.create_console_logger()
    // Create a window. Debug mode is enabled when compiled with -debug
    ok: bool
    ok = rd.create_window("rd window", 1280, 720, ODIN_DEBUG); assert(ok)
    rd.set_window_mode(.MAXIMIZED)

    // Make sure window gets destroyed
    defer rd.destroy_window()

    // Create vertex shader
    vertex_shader: rd.VertexShader
    vertex_shader, ok = rd.load_vertex_shader(shader_src, "vs_main", Vertex); assert(ok)

    // Create pixel shader
    pixel_shader: rd.PixelShader
    pixel_shader, ok = rd.load_pixel_shader(shader_src, "ps_main"); assert(ok)

    sun_pixel_shader: rd.PixelShader
    sun_pixel_shader, ok = rd.load_pixel_shader(shader_src, "ps_sun"); assert(ok)

    orbit_band_pixel_shader: rd.PixelShader
    orbit_band_pixel_shader, ok = rd.load_pixel_shader(shader_src, "ps_orbit_band"); assert(ok)

    // Bind shaders
    ok = rd.bind(&vertex_shader); assert(ok)
    ok = rd.bind(&pixel_shader);  assert(ok)

    // Load a mesh
    mesh: Mesh
    mesh, ok = load_mesh_gltf("example/assets/sphere.glb"); assert(ok)
    
    // Create entities: Sun + planets
    cubes := entities_from_mesh(mesh)
    assign_planet_textures(&cubes)
    orbit_bands := create_orbit_bands(cubes)

    camera := create_orbital_camera()
    selected_body_index := 0
    camera.target = cubes[selected_body_index].physics.position
    apply_focus_profile(&camera, cubes[selected_body_index], true)

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
                        selected_index, ok := body_index_from_key(ev.key)
                        if ok && selected_index != selected_body_index {
                            selected_body_index = selected_index
                            apply_focus_profile(&camera, cubes[selected_body_index], true)
                        }

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
        if rd.is_lmb_down() do update_camera(&camera) 
        update(&cubes, frame)
        camera.target = cubes[selected_body_index].physics.position
        apply_focus_profile(&camera, cubes[selected_body_index])
        draw(cubes, orbit_bands, camera, &pixel_shader, &sun_pixel_shader, &orbit_band_pixel_shader)
    }
}

body_index_from_key :: proc(key: rd.Keycode) -> (index: int, ok: bool) {
    #partial switch key {
        case .NUM0, .NUMPAD0:
            return 0, true
        case .NUM1, .NUMPAD1:
            return 1, true
        case .NUM2, .NUMPAD2:
            return 2, true
        case .NUM3, .NUMPAD3:
            return 3, true
        case .NUM4, .NUMPAD4:
            return 4, true
        case .NUM5, .NUMPAD5:
            return 5, true
        case .NUM6, .NUMPAD6:
            return 6, true
        case .NUM7, .NUMPAD7:
            return 7, true
        case .NUM8, .NUMPAD8:
            return 8, true
    }
    return 0, false
}

max_f32 :: proc(a, b: f32) -> f32 {
    return a > b ? a : b
}

apply_focus_profile :: proc(camera: ^Camera, entity: Entity, reset_distance := false) {
    body_radius := entity.physics.scale.x
    preferred_distance := max_f32(body_radius * 9.0, 8.0)
    min_distance := max_f32(body_radius * 2.4, 1.75)
    max_distance := max_f32(preferred_distance * 8.0, entity.orbit_radius + 60.0)

    camera.min_distance = min_distance
    camera.max_distance = max_distance
    if reset_distance {
        camera.distance = preferred_distance
    }
    clamp_camera(camera)
}

update :: proc(entitites: ^#soa[]Entity, frame: u32) {
    _ = frame
    dt_seconds := f32(rd.get_dt()) / f32(time.Second)

    delta_rotation := linalg.quaternion_angle_axis_f32(
        linalg.to_radians(f32(50.0) * dt_seconds),
        vec3{0, 1, 0},
    )

    for &e, i in entitites {
        if i > 0 {
            e.orbit_angle_deg += e.orbit_speed_deg * dt_seconds
            if e.orbit_angle_deg >= 360.0 {
                e.orbit_angle_deg -= 360.0
            }

            orbit_radians := linalg.to_radians(e.orbit_angle_deg)
            e.physics.position = ORBIT_CENTER + vec3 {
                e.orbit_radius * math.sin(orbit_radians),
                0,
                e.orbit_radius * math.cos(orbit_radians),
            }
        }
        e.physics.rotation = delta_rotation * e.physics.rotation
    }
}

draw :: proc(
    entities: #soa[]Entity,
    orbit_bands: []OrbitBand,
    camera: Camera, 
    pixel_shader: ^rd.PixelShader,
    sun_pixel_shader: ^rd.PixelShader,
    orbit_band_pixel_shader: ^rd.PixelShader,
) {
    rd.clear(BACKGROUND)
    ok: bool
    proj := create_proj_matrix()
    view := camera_view_matrix(camera)
    vp := proj * view
    rd.push_constant_data(.Vertex, &vp, 0)

    camera_cb := CameraBuffer {
        camera_pos = camera_position(camera),
        _pad0 = 0,
    }
    rd.push_constant_data(.Pixel, &camera_cb, 0)

    lighting_cb := PointLight {
        position = {0, 0, -120},
        intensity = 4.0,
        color = {1.0, 0.98, 0.92},
        range = 400.0,
        attenuation_constant = 1.0,
        attenuation_linear = 0.015,
        attenuation_quadratic = 0.001,
        
    }
    rd.push_constant_data(.Pixel, &lighting_cb, 1)

    ok = rd.set_blend_mode(.Opaque)
    assert(ok)

    for &e, i in entities {
        if i == 0 {
            ok = rd.bind(sun_pixel_shader)
        } else {
            ok = rd.bind(pixel_shader)
        }
        ok = rd.bind(&e.vbo)
        ok = rd.bind(&e.ibo)
        ok = rd.bind(&e.texture)
        model_matrix := linalg.matrix4_from_trs_f32(
            t = e.physics.position, 
            r = e.physics.rotation,
            s = e.physics.scale
        )
        rd.push_constant_data(.Vertex, &model_matrix, 1)
        rd.draw_indexed(e.ibo.length)
    }

    ok = rd.set_blend_mode(.Alpha)
    assert(ok)
    ok = rd.bind(orbit_band_pixel_shader)
    assert(ok)

    for &band in orbit_bands {
        model_matrix := linalg.matrix4_from_trs_f32(
                t = ORBIT_CENTER,
            r = linalg.quaternion_angle_axis_f32(0, vec3{0, 1, 0}),
            s = vec3{1, 1, 1},
        )
        rd.push_constant_data(.Vertex, &model_matrix, 1)

        ok = rd.bind(&band.vbo)
        ok = rd.bind(&band.ibo)
        rd.draw_indexed(band.ibo.length)
    }

    rd.frame_end()
}

create_orbit_bands :: proc(entities: #soa[]Entity, allocator := context.allocator) -> []OrbitBand {
    bands := make([]OrbitBand, len(entities)-1, allocator)
    for i in 1..<len(entities) {
        inner_radius := entities[i].orbit_radius - ORBIT_BAND_WIDTH * 0.5
        outer_radius := entities[i].orbit_radius + ORBIT_BAND_WIDTH * 0.5
        vertices, indices := create_ring_geometry(inner_radius, outer_radius, 192, allocator)
        bands[i-1] = OrbitBand {
            vbo = rd.create_vertex_buffer(vertices),
            ibo = rd.create_index_buffer(indices),
        }
    }
    return bands
}

create_ring_geometry :: proc(inner_radius, outer_radius: f32, segments: int, allocator := context.allocator) -> ([]Vertex, []u16) {
    vertices := make([dynamic]Vertex, allocator)
    indices := make([dynamic]u16, allocator)
    reserve(&vertices, segments * 2)
    reserve(&indices, segments * 6)

    for i in 0..<segments {
        t := f32(i) / f32(segments)
        angle := t * linalg.to_radians(f32(360))
        s := math.sin(angle)
        c := math.cos(angle)

        inner := Vertex {
            pos = {inner_radius * s, 0, inner_radius * c},
            uv = {t, 0},
        }
        outer := Vertex {
            pos = {outer_radius * s, 0, outer_radius * c},
            uv = {t, 1},
        }
        append(&vertices, inner)
        append(&vertices, outer)
    }

    for i in 0..<segments {
        i0 := u16(i * 2)
        i1 := u16(i * 2 + 1)
        next := (i + 1) % segments
        i2 := u16(next * 2)
        i3 := u16(next * 2 + 1)

        append(&indices, i0)
        append(&indices, i3)
        append(&indices, i1)

        append(&indices, i0)
        append(&indices, i2)
        append(&indices, i3)
    }

    return vertices[:], indices[:]
}

assign_planet_textures :: proc(entities: ^#soa[]Entity) {
    texture_paths := [9]string {
        "example/assets/planet_textures/2k_sun.jpg",
        "example/assets/planet_textures/2k_mercury.jpg",
        "example/assets/planet_textures/2k_venus_atmosphere.jpg",
        "example/assets/planet_textures/2k_earth.jpg",
        "example/assets/planet_textures/2k_mars.jpg",
        "example/assets/planet_textures/2k_jupiter.jpg",
        "example/assets/planet_textures/2k_saturn.jpg",
        "example/assets/planet_textures/2k_uranus.jpg",
        "example/assets/planet_textures/2k_neptune.jpg",
    }

    for &entity, index in entities^ {
        path := texture_paths[index]
        if path == "" do continue
        texture, ok := load_texture_from_file(path)
        if !ok {
            log.warnf("Could not load texture override for entity %v: %v", index, path)
            continue
        }
        entity.texture = texture
    }
}

load_texture_from_file :: proc(path: string, allocator := context.temp_allocator) -> (texture: rd.Texture, ok: bool) {
    file_data, read_err := os.read_entire_file_from_path(path, allocator)
    if read_err != nil {
        return
    }

    width, height: i32
    pixels_ptr := stbi.load_from_memory(
        raw_data(file_data),
        i32(len(file_data)),
        &width,
        &height,
        nil,
        4,
    )
    if pixels_ptr == nil {
        return
    }

    pixel_count := int(width * height * 4)
    pixels := slice.from_ptr(pixels_ptr, pixel_count)
    texture = rd.load_texture(pixels, u32(width), u32(height))
    ok = true
    return
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
        min_distance = 6,
        max_distance = 700,
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

update_camera :: proc(camera: ^Camera) {
    mouse_delta := rd.get_relative_mouse_movement()
    camera.yaw -= f32(mouse_delta.x) * camera.mouse_sense
    camera.pitch -= f32(mouse_delta.y) * camera.mouse_sense
    clamp_camera(camera)
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
    physics:          Physics,
    vbo:              rd.VertexBuffer,
    ibo:              rd.IndexBuffer,
    texture:          rd.Texture,
    orbit_radius:     f32,
    orbit_speed_deg:  f32,
    orbit_angle_deg:  f32,
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

    for &e, index in entities {
        body := bodies[index]
        initial_spin_angle := rng.float32_range(0, 360)
        e.physics.rotation = linalg.quaternion_angle_axis_f32(linalg.to_radians(initial_spin_angle), vec3{0, 1, 0})

        visual_radius := body.radius_earth
        if index == 0 {
            visual_radius = SUN_RENDER_RADIUS
        } else {
            visual_radius = body.radius_earth * PLANET_RADIUS_LINEAR_SCALE + math.sqrt(body.radius_earth) * PLANET_RADIUS_ROOT_SCALE
        }

        uniform_scale := PLANET_RENDER_SCALE * visual_radius
        e.physics.scale = vec3{uniform_scale, uniform_scale, uniform_scale}
        e.orbit_radius = body.orbital_radius_au * ORBIT_DISTANCE_LINEAR_SCALE + math.sqrt(body.orbital_radius_au) * ORBIT_DISTANCE_ROOT_SCALE
        e.orbit_angle_deg = index == 0 ? 0 : rng.float32_range(0, 360)

        if index == 0 {
            e.orbit_speed_deg = 0
        } else {
            // Kepler-like scaling: orbital period grows with distance^(3/2).
            // 1 AU (Earth) is mapped to EARTH_ORBIT_SECONDS in simulation time.
            orbital_distance_au := body.orbital_radius_au
            orbital_period_years := orbital_distance_au * math.sqrt(orbital_distance_au)
            orbital_period_seconds := EARTH_ORBIT_SECONDS * orbital_period_years
            e.orbit_speed_deg = 360.0 / orbital_period_seconds
        }

        angle_radians := linalg.to_radians(e.orbit_angle_deg)
        e.physics.position = ORBIT_CENTER + vec3 {
            e.orbit_radius * math.sin(angle_radians),
            0,
            e.orbit_radius * math.cos(angle_radians),
        }
        e.ibo = ibo
        e.vbo = vbo
    }
    return entities
}

PointLight :: struct {
    position:               rd.vec3,
    intensity:              f32,
    color:                  rd.vec3,
    range:                  f32,
    attenuation_constant:   f32,
    attenuation_linear:     f32,
    attenuation_quadratic:  f32,
    _pad0:                  f32,
}

CameraBuffer :: struct {
    camera_pos: rd.vec3,
    _pad0:      f32,
}

OrbitBand :: struct {
    vbo:    rd.VertexBuffer,
    ibo:    rd.IndexBuffer,
}