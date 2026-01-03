package redef_example

import os "core:os/os2"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:slice"

Vertex :: struct {
    pos: [3]f32,
}

Mesh :: struct {
    vertices: []Vertex,
    indices:  []u16,
}

vec3 :: [3]f32
vec4 :: [4]f32

load_mesh :: proc(path: string, allocator := context.allocator) -> (mesh: Mesh, ok: bool) {
    fmt.println("Loading:", path)
    file_data, err := os.read_entire_file_from_path(path, allocator)
    if err != nil {
        fmt.printfln("Error reading %v: %v", path, err)
        return
    }

    file_str := string(file_data)

    vertices:  [dynamic]Vertex
    indices:   [dynamic]u16

    for line in strings.split_lines_iterator(&file_str) {
        if len(line) < 2 do continue
        switch line[0:2] {
            case "v ":
                append(&vertices, Vertex {
                    pos = parse_vec3(line, 2),
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