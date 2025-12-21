package redef

import "core:log"
import d3d "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"

Graphics :: struct {
    device:    ^d3d.IDevice,
    swapchain: ^dxgi.ISwapChain,
    ctx:       ^d3d.IDeviceContext,
    target:    ^d3d.IRenderTargetView,
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
    // Swapchain configuration
    sd: dxgi.SWAP_CHAIN_DESC
    {
        using sd
        BufferDesc.Format = .B8G8R8A8_UNORM
        BufferDesc.Scaling = .UNSPECIFIED
        BufferDesc.ScanlineOrdering = .UNSPECIFIED
        SampleDesc.Count = 1
        BufferUsage = {.RENDER_TARGET_OUTPUT}
        BufferCount = 1
        OutputWindow = cast(dxgi.HWND)window.handle
        Windowed = true
        SwapEffect = .DISCARD
    }

    using g.graphics
    // Initilaize graphics
    result := d3d.CreateDeviceAndSwapChain(
        nil,
        d3d.DRIVER_TYPE.HARDWARE,
        nil, {},nil, 0,
        d3d.SDK_VERSION,
        &sd,
        &swapchain,
        &device,
        nil,
        &ctx
    )
    assert(device != nil)
    assert(swapchain != nil)
    assert(ctx != nil)
    if result != 0 {
        log.error("Device creation failed with code:", result)
        return
    }

    backbuffer: ^d3d.IResource
    swapchain->GetBuffer(0, d3d.IResource_UUID, transmute(^rawptr)&backbuffer)
    device->CreateRenderTargetView(backbuffer, nil, &target)
    backbuffer->Release()

    log.info("Initialized graphics")
}

@(private = "package")
destroy_graphics :: proc(graphics: Graphics) {
    using graphics
    assert(device != nil)
    assert(swapchain != nil)
    assert(ctx != nil)
    device->Release()
    swapchain->Release()
    ctx->Release()
    log.info("Destroyed graphics subsystem")
}