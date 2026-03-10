package redef_example

import gltf "shared:glTF2"
import "core:log"
import "core:slice"

Vertex :: struct {
    pos: vec3,
    uv: vec2,
}

Mesh :: struct {
    vertices: []Vertex,
    indices:  []u16,
}

Image :: struct {
    pixels: []byte,
    size: [2]i32
}

vec2 :: [2]f32
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

    ibo_index  := gltf_mesh.primitives[0].indices.?
    mesh.indices = slice.clone(gltf.buffer_slice(data, ibo_index).([]u16))

    ok = true
    return
}