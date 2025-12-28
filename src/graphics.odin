package redef

import "core:log"
import "core:strings"
import "base:runtime"
import "core:reflect"
import "core:mem"
import d3d "vendor:directx/d3d11"
import d3dc "vendor:directx/d3d_compiler"
import dxgi "vendor:directx/dxgi"
import win "core:sys/windows"

@(private = "package")
Graphics :: struct {
    device:         ^d3d.IDevice,
    swapchain:      ^dxgi.ISwapChain,
    ctx:            ^d3d.IDeviceContext,
    target:         ^d3d.IRenderTargetView,
    viewport:       d3d.VIEWPORT,
    info_manager:   DXGIInfoManager,
}

DEBUG_VERTEX :: struct {
    pos: vec2,
    col: vec4
}

VertexBuffer :: struct {
    buf: ^d3d.IBuffer,
    num_vertices: u32,
    stride: u32
}

create_vertex_buffer :: proc(vertices: ^[]$T) -> VertexBuffer {
    ensure(vertices^ != nil)
    len_bytes := u32(len(vertices) * size_of(T))
	vbo_desc := d3d.BUFFER_DESC{
		BindFlags = {.VERTEX_BUFFER},
		Usage     = .DEFAULT,
		ByteWidth = len_bytes,
        StructureByteStride = size_of(T)
	}

    sd := d3d.SUBRESOURCE_DATA {}
    sd.pSysMem = raw_data(vertices^)

    vbo: ^d3d.IBuffer
    ok := g.graphics.device->CreateBuffer(&vbo_desc, &sd, &vbo)
    gfx_check(ok)

    return VertexBuffer {
        vbo,
        u32(len(vertices)),
        size_of(T)
    }
}

draw :: proc(vs: VertexShader, ps: PixelShader, vbo: VertexBuffer) {
    context.logger = g.logger
    using g.graphics

    ctx->IASetPrimitiveTopology(.TRIANGLELIST)
    ctx->IASetInputLayout(vs.layout)
    stride := vbo.stride
    buffer := vbo.buf
    offset: u32 = 0
    ctx->IASetVertexBuffers(0, 1, &buffer, &stride, &offset)

    ctx->VSSetShader(vs.shader, nil, 0)
    ctx->RSSetViewports(1, &viewport) 
    ctx->PSSetShader(ps, nil, 0)

    ctx->OMSetRenderTargets(1, &target, nil)

    info_manager_set()
    ctx->Draw(vbo.num_vertices, 0)
    info_manager_log()
}

clear_buffer :: proc(color: [4]f32) {
    using g.graphics
    color := color
    ctx->ClearRenderTargetView(target, &color)
}

frame_end :: proc() {
    using g.graphics
    swapchain->Present(1, {})
}


VertexShader :: struct {
    shader: ^d3d.IVertexShader,
    layout: ^d3d.IInputLayout,
}

PixelShader :: ^d3d.IPixelShader

@(private = "file")
print_shader_compilation_message :: proc(blob: ^d3d.IBlob, level: log.Level = .Info, loc := #caller_location) {
    blob_str := strings.clone_from_ptr(
        cast(^u8)blob->GetBufferPointer(), 
        int(blob->GetBufferSize()), 
        context.temp_allocator
    )
    if blob_str == "" {
        log.info("Empty", location = loc)
    } else {
        err_builder := strings.builder_make(context.temp_allocator)
        strings.write_rune(&err_builder, '"')
        for line in strings.split_lines_iterator(&blob_str) {
            strings.write_string(&err_builder, line)
        }
        strings.pop_rune(&err_builder)
        strings.write_rune(&err_builder, '"')
        log.log(level, strings.to_string(err_builder), location = loc)
    }
}

load_vertex_shader :: proc(code: []byte, entry_point: string, $vertex_type: typeid, loc := #caller_location) -> (VertexShader, bool) {
    context.logger = g.logger

    entry_point_cstr := strings.unsafe_string_to_cstring(entry_point)
    vs_blob:  ^d3d.IBlob
    err_blob: ^d3d.IBlob
    ok := d3dc.Compile(
        raw_data(code), 
        len(code), nil, nil, nil, 
        entry_point_cstr, 
        "vs_5_0", 0, 0, 
        &vs_blob, 
        &err_blob
    )
    if ok != 0 {
        print_shader_compilation_message(err_blob, .Error, loc = loc)
        return {}, false
    }
    assert(vs_blob != nil)

    vert_shader: ^d3d.IVertexShader
    ok = g.graphics.device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &vert_shader)
    gfx_check(ok)
    assert(vert_shader != nil)
    
    input_element_desc := get_vb_layout(vertex_type)
    input_layout: ^d3d.IInputLayout
    ok = g.graphics.device->CreateInputLayout(
        &input_element_desc[0], 
        u32(len(input_element_desc)), 
        vs_blob->GetBufferPointer(),
        vs_blob->GetBufferSize(), 
        &input_layout
    )

    if ok != 0 {
        err_builder := strings.builder_make(context.temp_allocator)
        strings.write_string(&err_builder, "Error creating input layout:\n")
        strings.write_string(&err_builder, "Make sure shader semantics match the names of the vertex struct:\n")
        input_names := reflect.struct_field_names(vertex_type)
        
        for name in input_names {
            strings.write_string(
                &err_builder, 
                fmt.aprintfln("\t%v", name, allocator = context.temp_allocator)
            )
        }
        strings.pop_rune(&err_builder)
        log.error(strings.to_string(err_builder), location = loc)
            return {}, false
    }
    assert(input_layout != nil)
    return VertexShader {
        vert_shader,
        input_layout
    }, true
}

load_pixel_shader :: proc(code: []byte, entry_point: string, loc := #caller_location) -> (PixelShader, bool) {
    context.logger = g.logger
    entry_point_cstr := strings.unsafe_string_to_cstring(entry_point)
    ps_blob: ^d3d.IBlob
    err_blob: ^d3d.IBlob
    ok := d3dc.Compile(raw_data(code), len(code), nil, nil, nil, entry_point_cstr, "ps_5_0", 0, 0, &ps_blob, &err_blob)
    if ok != 0 {
        print_shader_compilation_message(err_blob, .Error)
        return {}, false
    }
    assert(ps_blob != nil)

    pixel_shader: ^d3d.IPixelShader
    ok = g.graphics.device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &pixel_shader)
    gfx_check(ok)
    return pixel_shader, true
}

get_vb_layout :: proc($vertex_type: typeid, allocator := context.temp_allocator) -> []d3d.INPUT_ELEMENT_DESC {
    element_info_from_type :: proc(type: ^runtime.Type_Info) -> dxgi.FORMAT {
        switch type {
            case type_info_of(vec2): return .R32G32_FLOAT
            case type_info_of(vec3): return .R32G32B32_FLOAT
            case type_info_of(vec4): return .R32G32B32A32_FLOAT
            case type_info_of(u32):  return .R32_UINT
            case: return .UNKNOWN
        }
    }
    fields := reflect.struct_field_types(vertex_type)
    names  := reflect.struct_field_names(vertex_type)
    data := make([]d3d.INPUT_ELEMENT_DESC, len(fields) > 0 ? len(fields) : 1, context.temp_allocator)

    for field, i in fields {
        data[i].SemanticName = strings.unsafe_string_to_cstring(names[i])
        data[i].AlignedByteOffset = i == 0 ? 0 : d3d.APPEND_ALIGNED_ELEMENT
        data[i].Format = element_info_from_type(field)
        data[i].InputSlotClass = .VERTEX_DATA
    }
    return data
}


@(private = "package")
init_graphics :: proc(window: ^Window, debug: bool) {
sd: dxgi.SWAP_CHAIN_DESC
    {
        using sd
        BufferDesc.Format = .B8G8R8A8_UNORM
        SampleDesc.Count = 1
        BufferUsage = {.RENDER_TARGET_OUTPUT}
        BufferCount = 1
        OutputWindow = cast(dxgi.HWND)window.handle
        Windowed = true
        SwapEffect = .DISCARD
    }

    using g.graphics
    // Initilaize graphics
    creation_flags: d3d.CREATE_DEVICE_FLAGS = debug ? {.DEBUG} : {}

    result := d3d.CreateDeviceAndSwapChain(
        nil,
        d3d.DRIVER_TYPE.HARDWARE,
        nil, creation_flags, nil, 0,
        d3d.SDK_VERSION,
        &sd,
        &swapchain,
        &device,
        nil,
        &ctx
    ); gfx_check(result)

    backbuffer: ^d3d.IResource
    result = swapchain->GetBuffer(0, d3d.IResource_UUID, transmute(^rawptr)&backbuffer)
    gfx_check(result)
    result = device->CreateRenderTargetView(backbuffer, nil, &target)
    gfx_check(result)
    backbuffer->Release()

    create_info_manager()

    viewport = d3d.VIEWPORT{
        0, 0,
        f32(window.size.x), f32(window.size.y),
        0, 1,
    }

    log.info("Initialized graphics")
}

@(private = "package")
destroy_graphics :: proc(loc := #caller_location) {
    using g.graphics
    log.info("Destroying graphics subsystem", location = loc)

    assert(device != nil)
    assert(swapchain != nil)
    assert(ctx != nil)
    device->Release()
    swapchain->Release()
    ctx->Release()

    info_manager.info_queue->Release()

    log.info("Destroyed graphics subsystem", location = loc)
}

import "core:fmt"

@(private = "file")
gfx_check :: proc(hresult: dxgi.HRESULT, error: string = "None",loc := #caller_location) {
    when !ODIN_DEBUG {
        ensure(hresult == 0, loc = loc)
    } else {
        if hresult != 0 {
            if _, ok := fmt.enum_value_to_string(DXGIError(hresult)); !ok {
                log.errorf("Generic Error: %v", error, location = loc)
            } else {
                log.errorf("DXGI Error 0x%x: %v", u32(hresult), DXGIError(hresult), location = loc)
            }
            runtime.trap()
        }
    }
}

@(private = "file")
DXGIInfoManager :: struct {
    next: u64,
    info_queue: ^dxgi.IInfoQueue,
}


@(private = "file")
info_manager_log :: proc(loc := #caller_location) {
    using g.graphics.info_manager
    end := info_queue->GetNumStoredMessages(dxgi.DEBUG_ALL)
    ok: dxgi.HRESULT
    for i: u64  = next; i < end; i+=1 {
        hr: dxgi.HRESULT
        message_length: uint
        ok = info_queue->GetMessage(dxgi.DEBUG_ALL, i, nil, &message_length)

        message := new(dxgi.INFO_QUEUE_MESSAGE) 
        defer free(message)
        ok = info_queue->GetMessage(dxgi.DEBUG_ALL, i, message, &message_length)
        gfx_check(ok)
        message_string := strings.string_from_null_terminated_ptr(message.pDescription, int(message_length))
        log.errorf("D3D11 Error: \"%v\"", message_string, location = loc)
    }
}

@(private = "file")
info_manager_set :: proc() {
    using g.graphics.info_manager
    next = info_queue->GetNumStoredMessages(dxgi.DEBUG_ALL)
}

@(private = "file")
create_info_manager :: proc() {
    assert(g.graphics.info_manager.info_queue == nil)
    ok := dxgi.DXGIGetDebugInterface1(0, dxgi.IInfoQueue_UUID, cast(^rawptr)&g.graphics.info_manager.info_queue)
    gfx_check(ok)
}

@(private = "file")
DXGIError :: enum dxgi.HRESULT{
    ACCESS_DENIED                = dxgi.HRESULT(-2005270485), //0x887A002B
    ACCESS_LOST                  = dxgi.HRESULT(-2005270490), //0x887A0026
    ALREADY_EXISTS               = dxgi.HRESULT(-2005270474), //0x887A0036
    CANNOT_PROTECT_CONTENT       = dxgi.HRESULT(-2005270486), //0x887A002A
    DEVICE_HUNG                  = dxgi.HRESULT(-2005270522), //0x887A0006
    DEVICE_REMOVED               = dxgi.HRESULT(-2005270523), //0x887A0005
    DEVICE_RESET                 = dxgi.HRESULT(-2005270521), //0x887A0007
    DRIVER_INTERNAL_ERROR        = dxgi.HRESULT(-2005270496), //0x887A0020
    FRAME_STATISTICS_DISJOINT    = dxgi.HRESULT(-2005270517), //0x887A000B
    GRAPHICS_VIDPN_SOURCE_IN_USE = dxgi.HRESULT(-2005270516), //0x887A000C
    INVALID_CALL                 = dxgi.HRESULT(-2005270527), //0x887A0001
    MORE_DATA                    = dxgi.HRESULT(-2005270525), //0x887A0003
    NAME_ALREADY_EXISTS          = dxgi.HRESULT(-2005270484), //0x887A002C
    NONEXCLUSIVE                 = dxgi.HRESULT(-2005270495), //0x887A0021
    NOT_CURRENTLY_AVAILABLE      = dxgi.HRESULT(-2005270494), //0x887A0022
    NOT_FOUND                    = dxgi.HRESULT(-2005270526), //0x887A0002
    REMOTE_CLIENT_DISCONNECTED   = dxgi.HRESULT(-2005270493), //0x887A0023
    REMOTE_OUTOFMEMORY           = dxgi.HRESULT(-2005270492), //0x887A0024
    RESTRICT_TO_OUTPUT_STALE     = dxgi.HRESULT(-2005270487), //0x887A0029
    SDK_COMPONENT_MISSING        = dxgi.HRESULT(-2005270483), //0x887A002D
    SESSION_DISCONNECTED         = dxgi.HRESULT(-2005270488), //0x887A0028
    UNSUPPORTED                  = dxgi.HRESULT(-2005270524), //0x887A0004
    WAIT_TIMEOUT                 = dxgi.HRESULT(-2005270489), //0x887A0027
    WAS_STILL_DRAWING            = dxgi.HRESULT(-2005270518), //0x887A000A
}