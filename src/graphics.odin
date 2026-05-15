package redef

import "core:log"
import "core:strings"
import "base:runtime"
import "core:reflect"
import "core:fmt"
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
    dsv:            ^d3d.IDepthStencilView,
    depth_opaque:   ^d3d.IDepthStencilState,
    depth_blended:  ^d3d.IDepthStencilState,
    rasterizer:     ^d3d.IRasterizerState,
    info_manager:   DXGIInfoManager,
    blend_mode:     BlendMode,
    blend_states:   [BlendMode]^d3d.IBlendState, //TODO: release on cleanup
    cb_size_warned: bool
}



Texture :: struct {
    width:      u32,
    height:     u32,
    tex:        ^d3d.ITexture2D,
    view:       ^d3d.IShaderResourceView,
    sampler:    ^d3d.ISamplerState,
}

ShaderStage :: enum {
    Vertex,
    Pixel
}

VertexShader :: struct {
    shader: ^d3d.IVertexShader,
    layout: ^d3d.IInputLayout,
}

PixelShader :: ^d3d.IPixelShader

VertexBuffer :: struct {
    buf: ^d3d.IBuffer,
    num_vertices: u32,
    stride: u32,
    offset: u32, // Not used
}

IndexBuffer :: struct {
    buf: ^d3d.IBuffer,
    length: u32,
}

StructuredBuffer :: struct {
    buf: ^d3d.IBuffer,
    view: ^d3d.IShaderResourceView,
    stages: bit_set[ShaderStage],
}

BlendMode :: enum {
    Alpha,
    Opaque,
    Additive
}

destroy :: proc{
    destroy_index_buffer,
    destroy_vertex_buffer,
    destroy_texture,
    destroy_pixel_shader,
    destroy_vertex_shader,
}

// Return: ok
set_blend_mode :: proc(mode: BlendMode) -> bool {
    context.logger = g.logger

    if g.graphics.ctx == nil {
        log.error("Graphics context is not initialized")
        return false
    }

    if g.graphics.blend_mode == mode && g.graphics_init {
        return true
    }

    state := g.graphics.blend_states[mode]
    if state == nil {
        log.errorf("Blend state for mode %v is not initialized", mode)
        return false
    }

    blend_factor := [4]f32{1, 1, 1, 1}
    info_manager_set()
    g.graphics.ctx->OMSetBlendState(state, &blend_factor, 0xFFFFFFFF)

    switch mode {
        case .Opaque:
            g.graphics.ctx->OMSetDepthStencilState(g.graphics.depth_opaque, 1)
        case .Alpha, .Additive:
            g.graphics.ctx->OMSetDepthStencilState(g.graphics.depth_blended, 1)
    }

    g.graphics.blend_mode = mode
    info_manager_log()
    return true
}

// Assumes Texture format 
load_texture :: proc(pixels: []byte, width, height: u32, loc := #caller_location) -> Texture {
    context.logger = g.logger
    log.infof("Loading texture: [%v, %v]", width, height, location = loc)
    ensure(pixels != nil)
    tex_desc: d3d.TEXTURE2D_DESC = {
        Width  = width,
        Height = height,
        MipLevels = 1,
        ArraySize = 1,
        Format = .R8G8B8A8_UNORM,
        SampleDesc = {
            Count = 1
        },
        Usage = .DEFAULT,
        BindFlags = {.SHADER_RESOURCE}
    }
    sd := d3d.SUBRESOURCE_DATA {
        pSysMem = raw_data(pixels),
        SysMemPitch = width*size_of(byte)*4
    }
    tex: ^d3d.ITexture2D
    result := g.graphics.device->CreateTexture2D(&tex_desc, &sd, &tex)
    gfx_check(result)

    view_desc: d3d.SHADER_RESOURCE_VIEW_DESC = {
        Format = tex_desc.Format,
        ViewDimension = d3d.SRV_DIMENSION.TEXTURE2D,
        Texture2D = {
            MipLevels = 1
        },
    }

    view: ^d3d.IShaderResourceView
    result = g.graphics.device->CreateShaderResourceView(tex, &view_desc, &view)
    gfx_check(result)

    sampler_desc: d3d.SAMPLER_DESC = {
        Filter   = .MIN_MAG_MIP_LINEAR,
        AddressU = .WRAP,
        AddressV = .WRAP,
        AddressW = .WRAP,
    }
    sampler: ^d3d.ISamplerState
    result = g.graphics.device->CreateSamplerState(&sampler_desc, &sampler)
    gfx_check(result)
    return Texture {
        width, height, tex, view, sampler
    }
}

destroy_texture :: proc(t: Texture) {
    t.view->Release()
    t.sampler->Release()
    t.tex->Release()
}

create_index_buffer :: proc(indices: []u16) -> IndexBuffer {
    context.logger = g.logger
    ensure(indices != nil)

    len_bytes := u32(len(indices) * size_of(u16))
    ibo_desc := d3d.BUFFER_DESC{
		BindFlags = {.INDEX_BUFFER},
		Usage     = .DEFAULT,
		ByteWidth = len_bytes,
        StructureByteStride = size_of(u16),
	}

    sd := d3d.SUBRESOURCE_DATA {
        pSysMem = raw_data(indices)
    }

    ibo: ^d3d.IBuffer

    info_manager_set()
    ok := g.graphics.device->CreateBuffer(&ibo_desc, &sd, &ibo)
    gfx_check(ok, "Index buffer creation failed")
    return IndexBuffer {
        buf = ibo,
        length = u32(len(indices))
    }
}

destroy_index_buffer :: proc(ib: IndexBuffer) {ib.buf->Release()}

create_vertex_buffer :: proc(vertices: []$T) -> VertexBuffer {
    context.logger = g.logger
    ensure(vertices != nil)
    len_bytes := u32(len(vertices) * size_of(T))
	vbo_desc := d3d.BUFFER_DESC{
		BindFlags = {.VERTEX_BUFFER},
		Usage     = .DEFAULT,
		ByteWidth = len_bytes,
        StructureByteStride = size_of(T),
	}

    sd := d3d.SUBRESOURCE_DATA {
        pSysMem = raw_data(vertices)
    }

    vbo: ^d3d.IBuffer
    info_manager_set()
    ok := g.graphics.device->CreateBuffer(&vbo_desc, &sd, &vbo)
    gfx_check(ok, "Vertex buffer creation failed")

    return VertexBuffer {
        vbo,
        u32(len(vertices)),
        size_of(T),
        0
    }
}
destroy_vertex_buffer :: proc(vb: VertexBuffer) { vb.buf->Release() }

create_structured_buffer :: proc(data: []$T, stages: bit_set[ShaderStage]) -> StructuredBuffer {
    len_bytes := u32(len(data) * size_of(T))
    sb_desc := d3d.BUFFER_DESC {
        ByteWidth = len_bytes,
        Usage = .DEFAULT,
        BindFlags = {.SHADER_RESOURCE},
        MiscFlags = {.BUFFER_STRUCTURED},
        StructureByteStride = size_of(T)
    }
    sd := d3d.SUBRESOURCE_DATA {
        pSysMem = raw_data(data)
    }
    sb: ^d3d.IBuffer
    info_manager_set()
    ok := g.graphics.device->CreateBuffer(&sb_desc, &sd, &sb)
    gfx_check(ok, "Structured buffer creation failed")

    buf_desc: d3d.SHADER_RESOURCE_VIEW_DESC = {
        ViewDimension = .BUFFER,
        Buffer = {
            NumElements = u32(len(data)),
        }

    }

    view: ^d3d.IShaderResourceView
    ok = g.graphics.device->CreateShaderResourceView(sb, &buf_desc, &view)
    gfx_check(ok, "Structured buffer view creation failed")
    return StructuredBuffer {
        buf = sb,
        view = view,
        stages = stages
    }
}

destroy_structured_buffer :: proc(cb: StructuredBuffer) { 
    cb.view->Release()
    cb.buf->Release() 
}

/*
Binds a generic resource to the active pipeline
    currently supported resource types:
        VertexBuffer,
        IndexBuffer,
        VertexShader,
        PixelShader,
        Texture
*/
bind :: proc(resource: ^$T, slot: u32 = 0, loc := #caller_location) -> (ok: bool) {
    if resource == nil do return
    context.logger = g.logger
    info_manager_set()
    ok = true
    switch typeid_of(T) {
        case typeid_of(VertexBuffer):
            vbo := cast(^VertexBuffer)resource
            g.graphics.ctx->IASetVertexBuffers(0, 1, &vbo.buf, &vbo.stride, &vbo.offset)

        case typeid_of(IndexBuffer):
            ibo := cast(^IndexBuffer)resource
            g.graphics.ctx->IASetIndexBuffer(ibo.buf, .R16_UINT, 0)

        case typeid_of(VertexShader):
            vs := cast(^VertexShader)resource
            g.graphics.ctx->IASetPrimitiveTopology(.TRIANGLELIST)
            g.graphics.ctx->IASetInputLayout(vs.layout)
            g.graphics.ctx->VSSetShader(vs.shader, nil, 0)

        case typeid_of(PixelShader):
            ps := cast(^PixelShader)resource
            g.graphics.ctx->PSSetShader(ps^, nil, 0)
       
        case typeid_of(Texture):
            tex := cast(^Texture)resource
            g.graphics.ctx->PSSetShaderResources(slot, 1, &tex.view)
            g.graphics.ctx->PSSetSamplers(slot, 1, &tex.sampler)
        case typeid_of(StructuredBuffer):
            sb := cast(^StructuredBuffer)resource
            if .Vertex in sb.stages {
                g.graphics.ctx->VSSetShaderResources(
                    slot, 1, 
                    raw_data([]^d3d.IShaderResourceView{sb.view})
                )
            }
            if .Pixel in sb.stages {
                g.graphics.ctx->PSSetShaderResources(
                    slot, 1, 
                    raw_data([]^d3d.IShaderResourceView{sb.view})
                )
            }
        
        // Invalid binds
        case typeid_of(d3d.IPixelShader):
            log.errorf("Type: %v is not bindable", typeid_of(T), location = loc)
            log.error("Pass pixel shader by reference: bind(&pixel_shader)", location = loc)
            ok = false

        case:
            log.errorf("Type: %v is not bindable", typeid_of(T), location = loc)
            ok = false

    }
    info_manager_log()
    return
}

// This is slow due to always creating/destroying a buffer. Consider a better design
push_constant_data :: proc(stage: ShaderStage, data: ^$T, slot: u32, loc := #caller_location) { 
    context.logger = g.logger
    ensure(data != nil)

    size: u32 = (size_of(data^) + 15) & ~u32(15)
    assert(size%16 == 0)
    cb_desc := d3d.BUFFER_DESC{
		BindFlags = {.CONSTANT_BUFFER},
		Usage     = .DYNAMIC,
        CPUAccessFlags = {.WRITE},
		ByteWidth = u32(size)
	}

    sd := d3d.SUBRESOURCE_DATA {
        pSysMem = data
    }
    
    cb: ^d3d.IBuffer
    info_manager_set()
    err := g.graphics.device->CreateBuffer(&cb_desc, &sd, &cb)
    gfx_check(err, "Constant buffer creation failed")

    info_manager_log()
    switch stage {
        case .Vertex: g.graphics.ctx->VSSetConstantBuffers(slot, 1, &cb)
        case .Pixel: g.graphics.ctx->PSSetConstantBuffers(slot, 1, &cb)
    }
    rc := cb->Release()
    assert(rc == 0)
    info_manager_log()
}

draw_indexed :: proc(indices: u32, loc := #caller_location) {
    context.logger = g.logger

    info_manager_set()
    g.graphics.ctx->DrawIndexed(indices, 0, 0)
    info_manager_log(loc = loc)
}

draw :: proc(vertex_count: u32, loc := #caller_location) {
    context.logger = g.logger

    info_manager_set()
    g.graphics.ctx->Draw(vertex_count, 0)
    info_manager_log(loc = loc)
}


clear :: proc(color: [4]f32) {
    context.logger = g.logger

    info_manager_set()
    color := color
    g.graphics.ctx->ClearRenderTargetView(g.graphics.target, &color)
    g.graphics.ctx->ClearDepthStencilView(g.graphics.dsv, {.DEPTH}, 1, 0)
    info_manager_log()
}

frame_end :: proc() {
    context.logger = g.logger

    info_manager_set()
    g.graphics.swapchain->Present(1, {})
    info_manager_log()
}

// Entry point must be null terminated
load_vertex_shader :: proc(code: []byte, entry_point: string, $vertex_type: typeid, loc := #caller_location) -> (vs: VertexShader, ok: bool) {
    context.logger = g.logger

    entry_point_cstr := strings.unsafe_string_to_cstring(entry_point)
    vs_blob:  ^d3d.IBlob
    err_blob: ^d3d.IBlob

    err := d3dc.Compile(
        raw_data(code), 
        len(code), "<Shader input file>", nil, nil,
        entry_point_cstr, 
        "vs_5_0", 0, 0, 
        &vs_blob, 
        &err_blob
    )
    if err != 0 {
        print_shader_compilation_message(err_blob, .Error, loc = loc)
        return
    }
    assert(vs_blob != nil)

    vert_shader: ^d3d.IVertexShader
    err = g.graphics.device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &vert_shader)
    gfx_check(err)
    assert(vert_shader != nil)
    
    input_element_desc := get_vb_layout(vertex_type)
    input_layout: ^d3d.IInputLayout
    err = g.graphics.device->CreateInputLayout(
        &input_element_desc[0], 
        u32(len(input_element_desc)), 
        vs_blob->GetBufferPointer(),
        vs_blob->GetBufferSize(), 
        &input_layout
    )

    if err != 0 {
        err_builder := strings.builder_make(context.temp_allocator)
        strings.write_string(&err_builder, "Error creating input layout:\n")
        strings.write_string(&err_builder, "Make sure shader semantic names match the names of the vertex struct:\n")
        input_names := reflect.struct_field_names(vertex_type)
        
        for name in input_names {
            strings.write_string(
                &err_builder, 
                fmt.aprintfln("\t%v", name, allocator = context.temp_allocator)
            )
        }
        strings.pop_rune(&err_builder)
        log.error(strings.to_string(err_builder), location = loc)
            return
    }
    assert(input_layout != nil)
    return {
        vert_shader,
        input_layout
    }, true
}

destroy_vertex_shader :: proc(vs: VertexShader) {
    vs.layout->Release()
    vs.shader->Release()
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

destroy_pixel_shader :: proc(ps: PixelShader) { ps->Release() }

@(private = "package")
init_graphics :: proc(debug: bool, loc := #caller_location) {
sd: dxgi.SWAP_CHAIN_DESC
    {
        sd.BufferDesc.Format = .B8G8R8A8_UNORM
        sd.SampleDesc.Count = 1
        sd.BufferUsage = {.RENDER_TARGET_OUTPUT}
        sd.BufferCount = 1
        sd.OutputWindow = cast(dxgi.HWND)g.window.handle
        sd.Windowed = true
        sd.SwapEffect = .DISCARD
    }

    // Initilaize graphics
    creation_flags: d3d.CREATE_DEVICE_FLAGS = debug ? {.DEBUG} : {}

    result := d3d.CreateDeviceAndSwapChain(
        nil,
        d3d.DRIVER_TYPE.HARDWARE,
        nil, creation_flags, nil, 0,
        d3d.SDK_VERSION,
        &sd,
        &g.graphics.swapchain,
        &g.graphics.device,
        nil,
        &g.graphics.ctx
    ); gfx_check(result)

    backbuffer: ^d3d.IResource
    result = g.graphics.swapchain->GetBuffer(0, d3d.IResource_UUID, cast(^rawptr)&backbuffer)
    gfx_check(result)
    result = g.graphics.device->CreateRenderTargetView(backbuffer, nil, &g.graphics.target)
    gfx_check(result)
    backbuffer->Release()

    create_info_manager()

    info_manager_set()
    viewport := d3d.VIEWPORT{
        0, 0,
        f32(g.window.width), f32(g.window.height),
        0, 1,
    }
    
    g.graphics.ctx->RSSetViewports(1, &viewport) 

    ds_desc: d3d.DEPTH_STENCIL_DESC = {
        DepthEnable    = true,
        DepthWriteMask = .ALL,
        DepthFunc      = .LESS
    }

    result = g.graphics.device->CreateDepthStencilState(&ds_desc, &g.graphics.depth_opaque)
    gfx_check(result)

    ds_desc_blended := ds_desc
    ds_desc_blended.DepthWriteMask = .ZERO
    result = g.graphics.device->CreateDepthStencilState(&ds_desc_blended, &g.graphics.depth_blended)
    gfx_check(result)

    g.graphics.ctx->OMSetDepthStencilState(g.graphics.depth_opaque, 1)

    depth_stencil_desc: d3d.TEXTURE2D_DESC = {
        Width  = u32(g.window.width),
        Height = u32(g.window.height),
        MipLevels = 1,
        ArraySize = 1,
        Format = .D32_FLOAT,
        SampleDesc = {
            Count = 1
        },
        Usage = .DEFAULT,
        BindFlags = {.DEPTH_STENCIL}
    }
    depth_stencil: ^d3d.ITexture2D
    result = g.graphics.device->CreateTexture2D(&depth_stencil_desc, nil, &depth_stencil)
    gfx_check(result)

    dsv_desc: d3d.DEPTH_STENCIL_VIEW_DESC = {
        Format = .D32_FLOAT,
        ViewDimension = .TEXTURE2D,
    }
    result = g.graphics.device->CreateDepthStencilView(depth_stencil, &dsv_desc, &g.graphics.dsv)
    gfx_check(result)

    g.graphics.ctx->OMSetRenderTargets(1, &g.graphics.target, g.graphics.dsv)
    info_manager_log()

    rasterizer_desc: d3d.RASTERIZER_DESC = {
        FillMode = .SOLID,
        CullMode = .NONE
    }

    result = g.graphics.device->CreateRasterizerState(&rasterizer_desc, &g.graphics.rasterizer)
    gfx_check(result)

    g.graphics.ctx->RSSetState(g.graphics.rasterizer)

    render_targets: [8]d3d.RENDER_TARGET_BLEND_DESC

    // Alpha blend (default)
    render_targets[0] = {
        BlendEnable     = true,
        SrcBlend        = .SRC_ALPHA,
        DestBlend       = .INV_SRC_ALPHA, 
        BlendOp         = .ADD,
        SrcBlendAlpha   = .ONE,
        DestBlendAlpha  = .ZERO,
        BlendOpAlpha    = .ADD,
        RenderTargetWriteMask = 0x0F,
    }
    blend_desc: d3d.BLEND_DESC = {
        AlphaToCoverageEnable = false,
        IndependentBlendEnable = false,
        RenderTarget = render_targets
    }
    result = g.graphics.device->CreateBlendState(&blend_desc, &g.graphics.blend_states[.Alpha])
    gfx_check(result)

    // Opaque
    render_targets[0] = {
        BlendEnable     = false,
        SrcBlend        = .ONE,
        DestBlend       = .ZERO,
        BlendOp         = .ADD,
        SrcBlendAlpha   = .ONE,
        DestBlendAlpha  = .ZERO,
        BlendOpAlpha    = .ADD,
        RenderTargetWriteMask = 0x0F,
    }
    blend_desc = d3d.BLEND_DESC {
        AlphaToCoverageEnable = false,
        IndependentBlendEnable = false,
        RenderTarget = render_targets
    }
    result = g.graphics.device->CreateBlendState(&blend_desc, &g.graphics.blend_states[.Opaque])
    gfx_check(result)

    // Additive
    render_targets[0] = {
        BlendEnable     = true,
        SrcBlend        = .ONE,
        DestBlend       = .ONE,
        BlendOp         = .ADD,
        SrcBlendAlpha   = .ONE,
        DestBlendAlpha  = .ZERO,
        BlendOpAlpha    = .ADD,
        RenderTargetWriteMask = 0x0F,
    }
    blend_desc = d3d.BLEND_DESC {
        AlphaToCoverageEnable = false,
        IndependentBlendEnable = false,
        RenderTarget = render_targets
    }
    result = g.graphics.device->CreateBlendState(&blend_desc, &g.graphics.blend_states[.Additive])
    gfx_check(result)

    ok := set_blend_mode(.Opaque)
    g.graphics_init = true
    assert(ok)
    log.info("Initialized graphics", location = loc)
}

@(private = "package")
resize_graphics :: proc() {
    context.logger = g.logger

    width := g.window.width
    height := g.window.height

    if width <= 0 || height <= 0 do return

    info_manager_set()

    g.graphics.ctx->OMSetRenderTargets(0, nil, nil)
    info_manager_log()

    if g.graphics.target != nil {
        rc := g.graphics.target->Release()
        assert(rc == 0)
        g.graphics.target = nil
    }

    if g.graphics.dsv != nil {
        rc := g.graphics.dsv->Release()
        assert(rc == 0)
        g.graphics.dsv = nil
    }

    result := g.graphics.swapchain->ResizeBuffers(
        0,
        u32(width),
        u32(height),
        .UNKNOWN,
        {}
    )
    gfx_check(result)

    backbuffer: ^d3d.IResource
    result = g.graphics.swapchain->GetBuffer(0, d3d.IResource_UUID, transmute(^rawptr)&backbuffer)
    gfx_check(result)

    result = g.graphics.device->CreateRenderTargetView(backbuffer, nil, &g.graphics.target)

    gfx_check(result)
    rc := backbuffer->Release()
    assert(rc == 0)

    depth_stencil_desc: d3d.TEXTURE2D_DESC = {
        Width  = u32(width),
        Height = u32(height),
        MipLevels = 1,
        ArraySize = 1,
        Format = .D32_FLOAT,
        SampleDesc = {
            Count = 1
        },
        Usage = .DEFAULT,
        BindFlags = {.DEPTH_STENCIL}
    }

    depth_stencil: ^d3d.ITexture2D
    result = g.graphics.device->CreateTexture2D(&depth_stencil_desc, nil, &depth_stencil)
    gfx_check(result)

    dsv_desc: d3d.DEPTH_STENCIL_VIEW_DESC = {
        Format = .D32_FLOAT,
        ViewDimension = .TEXTURE2D,
    }
    result = g.graphics.device->CreateDepthStencilView(depth_stencil, &dsv_desc, &g.graphics.dsv)
    gfx_check(result)

    rc = depth_stencil->Release()
    assert(rc == 0)

    g.graphics.ctx->OMSetRenderTargets(1, &g.graphics.target, g.graphics.dsv)

    viewport := d3d.VIEWPORT{
        0, 0,
        f32(width), f32(height),
        0, 1,
    }
    g.graphics.ctx->RSSetViewports(1, &viewport)
    info_manager_log()
}

@(private = "file")
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

@(private = "package")
destroy_graphics :: proc(loc := #caller_location) {

    assert(g.graphics.device != nil)
    assert(g.graphics.swapchain != nil)
    assert(g.graphics.ctx != nil)
    g.graphics.device->Release()
    g.graphics.swapchain->Release()
    g.graphics.ctx->Release()

    g.graphics.info_manager.info_queue->Release()

    log.info("Destroyed graphics subsystem", location = loc)
}

@(private = "file")
gfx_check :: proc(hresult: dxgi.HRESULT, error: string = "None", loc := #caller_location) {
    if hresult != 0 {
        if _, ok := fmt.enum_value_to_string(DXGIError(hresult)); !ok {
            log.errorf("Generic Error 0x%x: %v", u32(hresult), error, location = loc)
        } else {
            log.errorf("DXGI Error 0x%x: %v", u32(hresult), DXGIError(hresult), location = loc)
        }
        info_manager_log(loc = loc)
        runtime.trap()
    }
}

@(private = "file")
DXGIInfoManager :: struct {
    next: u64,
    info_queue: ^dxgi.IInfoQueue,
}


@(private = "file")
info_manager_log :: proc(loc := #caller_location) {
    im := g.graphics.info_manager
    end := im.info_queue->GetNumStoredMessages(dxgi.DEBUG_ALL)
    ok: dxgi.HRESULT
    for i: u64  = im.next; i < end; i+=1 {
        message_length: uint
        ok = im.info_queue->GetMessage(dxgi.DEBUG_ALL, i, nil, &message_length)

        message := new(dxgi.INFO_QUEUE_MESSAGE) 
        defer free(message)
        ok = im.info_queue->GetMessage(dxgi.DEBUG_ALL, i, message, &message_length)
        gfx_check(ok)
        message_string := strings.string_from_null_terminated_ptr(message.pDescription, int(message_length))
        log.errorf("%v", message_string, location = loc)
    }
}

@(private = "file")
info_manager_set :: proc() {
    g.graphics.info_manager.next = g.graphics.info_manager.info_queue->GetNumStoredMessages(dxgi.DEBUG_ALL)
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