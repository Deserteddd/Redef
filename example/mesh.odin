package redef_example

import os "core:os/os2"
import gltf "shared:glTF2"
import stbi "vendor:stb/image"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:log"
import "core:slice"

Vertex :: struct {
    pos: vec3,
    uv: vec2,
}

Mesh :: struct {
    vertices: []Vertex,
    indices:  []u16,
    texture:  Image,
}

Image :: struct {
    pixels: []byte,
    size: [2]i32
}

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32

load_mesh_gltf :: proc(path: string, allocator := context.allocator, loc := #caller_location) -> (mesh: Mesh, ok: bool) {
    context.logger = log.create_console_logger()
    context.allocator = allocator

    data, err := gltf.load_from_file(path, allocator)
    defer gltf.unload(data)

    if err != nil {
        switch e in err {
            case gltf.JSON_Error: log.errorf("JSON error: %v", e.type)
            case gltf.GLTF_Error: log.errorf("GLTF error: %v", e.type)
        }
        return
    }

    assert(len(data.scenes) == 1)
    assert(len(data.meshes) == 1)
    assert(data.extensions == nil)

    gltf_mesh: gltf.Mesh = data.meshes[0]
    assert(len(gltf_mesh.primitives) == 1)

    // Load vertex buffer
    positions: []vec3
    uvs:       []vec2
    primitive := gltf_mesh.primitives[0]
    for key, val in primitive.attributes {
        accessor := data.accessors[val]
        stride := &data.buffer_views[accessor.buffer_view.?].byte_stride
        switch key {
            case "POSITION":
                stride^ = nil
                positions = gltf.buffer_slice(data, val).([]vec3)
            case "TEXCOORD_0":
                stride^ = nil
                uvs = gltf.buffer_slice(data, val).([]vec2)

        }
        
    }

    mesh.vertices = make([]Vertex, len(positions))
    for i in 0..<len(mesh.vertices) {
        mesh.vertices[i] = {
            positions[i], 
            uvs == nil ? 0 : uvs[i]
        }
    }

    material := data.materials[primitive.material.?]
    tex := data.textures[material.metallic_roughness.?.base_color_texture.?.index]
    img := data.images[tex.source.?]
    img_view := data.buffer_views[img.buffer_view.?]
    pixels := data.buffers[img_view.buffer].uri.([]byte)[img_view.byte_offset:img_view.byte_offset+img_view.byte_length]
    x, y: i32
    
    pixels_multiptr := stbi.load_from_memory(
        raw_data(pixels), 
        i32(len(pixels)), 
        &mesh.texture.size.x, 
        &mesh.texture.size.y, 
        nil, 4
    ); if pixels_multiptr == nil do return
    mesh.texture.pixels = slice.from_ptr(pixels_multiptr, int(x*y))


    ibo_index  := gltf_mesh.primitives[0].indices.?
    mesh.indices = slice.clone(gltf.buffer_slice(data, ibo_index).([]u16))

    ok = true
    return
}

load_mesh_obj :: proc(path: string, allocator := context.allocator) -> (mesh: Mesh, ok: bool) {
    context.allocator = allocator
    context.logger = log.create_console_logger()
    log.info("Loading:", path)
    file_data, err := os.read_entire_file_from_path(path, allocator)
    if err != nil {
        fmt.printfln("Error reading %v: %v", path, err)
        return
    }

    
    file_str := string(file_data)

    vertices:  [dynamic]Vertex
    indices:   [dynamic]u16

    i: int
    for line in strings.split_lines_iterator(&file_str) {
        if len(line) < 2 do continue
        defer i += 1
        switch line[0:2] {
            case "v ":
                append(&vertices, Vertex {
                    pos = parse_vec3(line, 2),
                    // uv  = {rng.float32_range(0, 1), rng.float32_range(0, 1)},
                })
            case "f ":
                line_ptr := line
                for s in strings.split_after_iterator(&line_ptr, " ") {
                    clean, allocs := strings.remove_all(s, " ", context.temp_allocator)
                    if val, ok := strconv.parse_uint(clean); ok {
                        append(&indices, u16(val-1))
                    }
                }
                // Correct face orientation
                slice.swap(indices[:], len(indices)-2, len(indices)-3)
        }
    }
    mesh.vertices = vertices[:]
    mesh.indices  = indices[:]
    ok = true
    return
}

@(private = "file")
parse_vec3 :: proc(line: string, start: int) -> vec3 {
    data: vec3
    start := start
    n := 0
    ok: bool 
    for i in start..<len(line) {
        if line[i] == 32 {
            data[n], ok = strconv.parse_f32(line[start:i]); assert(ok)
            n += 1
            start = i+1
        }
    }
    data[n], ok = strconv.parse_f32(line[start:]); assert(ok)
    return data
}