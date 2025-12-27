package redef

import "core:log"
import "core:strings"
import "base:runtime"
import d3d "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import win "core:sys/windows"

@(private = "package")
Graphics :: struct {
    device:         ^d3d.IDevice,
    swapchain:      ^dxgi.ISwapChain,
    ctx:            ^d3d.IDeviceContext,
    target:         ^d3d.IRenderTargetView,
    info_manager:   DXGIInfoManager
}

Vertex :: [2]f32

draw_triangle :: proc() {
    context.logger = log.create_console_logger()
    using g.graphics

    vertices := [?]Vertex {
        {0, 0.5},
        {0.5, -0.5},
        {-0.5, -0.5}
    }


	vbo_desc := d3d.BUFFER_DESC{
		BindFlags = {.VERTEX_BUFFER},
		Usage     = .DEFAULT,
		ByteWidth = size_of(vertices),
        StructureByteStride = size_of(Vertex)
	}

    sd := d3d.SUBRESOURCE_DATA {}
    sd.pSysMem = &vertices

    vbo: ^d3d.IBuffer
    ok := device->CreateBuffer(&vbo_desc, &sd, &vbo)
    gfx_check(ok)

    info_manager_set()
    stride: u32 = size_of(Vertex)
    offset: u32 = 0
    ctx->IASetVertexBuffers(0, 1, &vbo, &stride, &offset)
    
    ctx->Draw(3, 0)
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



@(private = "package")
init_graphics :: proc(window: ^Window) {
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
    creation_flags: d3d.CREATE_DEVICE_FLAGS = ODIN_DEBUG ? {.DEBUG} : {}

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

    log.info("Initialized graphics")
}

@(private = "package")
destroy_graphics :: proc() {
    using g.graphics
    if ODIN_DEBUG do context.logger = log.create_console_logger()
    log.info("Destroying graphics subsystem")

    assert(device != nil)
    assert(swapchain != nil)
    assert(ctx != nil)
    device->Release()
    swapchain->Release()
    ctx->Release()

    info_manager.info_queue->Release()


    log.info("Destroyed graphics subsystem")
}

@(private = "file")
gfx_check :: proc(hresult: dxgi.HRESULT, loc := #caller_location) {
    when !ODIN_DEBUG {
        ensure(hresult == 0, loc = loc)
    } else {
        context.logger = log.create_console_logger()
        if hresult != 0 {
            log.errorf("DXGI Error 0x%x: %v", u32(hresult), DXGIError(hresult), location = loc)
            // runtime.trap()
        }
    }
}

@(private = "file")
DXGIInfoManager :: struct {
    next: u64,
    info_queue: ^dxgi.IInfoQueue,
}

import "core:mem"

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