package main

import "vendor:wgpu"
import js "vendor:wasm/js"
import "core:fmt"
import "base:runtime"
import "core:strings"
import "core:math"

State :: struct {
    ctx: runtime.Context,
    os:  OS,

    instance:        wgpu.Instance,
    surface:         wgpu.Surface,
    adapter:         wgpu.Adapter,
    device:          wgpu.Device,
    config:          wgpu.SurfaceConfiguration,
    queue:           wgpu.Queue,
    module:          wgpu.ShaderModule,
    pipeline_layout: wgpu.PipelineLayout,
    pipeline:        wgpu.RenderPipeline,

    triangleVertexBuffer: wgpu.Buffer,
}

Vertex :: struct {
    worldPos: [3]f32,
}

@(private="file")
state: State

main :: proc() {
    state.ctx = context

    os_init(&state.os)

    state.instance = wgpu.CreateInstance(nil)
    if state.instance == nil {
        panic("WebGPU is not supported")
    }
    state.surface = os_get_surface(&state.os, state.instance)

    wgpu.InstanceRequestAdapter(state.instance, &{ compatibleSurface = state.surface }, on_adapter, nil)

    on_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: cstring, userdata: rawptr) {
        context = state.ctx
        if status != .Success || adapter == nil {
            fmt.panicf("request adapter failure: [%v] %s", status, message)
        }
        state.adapter = adapter
        wgpu.AdapterRequestDevice(adapter, nil, on_device)
    }

    on_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: cstring, userdata: rawptr) {
        context = state.ctx
        if status != .Success || device == nil {
            fmt.panicf("request device failure: [%v] %s", status, message)
        }
        state.device = device

        width, height := os_get_render_bounds(&state.os)

        state.config = wgpu.SurfaceConfiguration {
            device      = state.device,
            usage       = { .RenderAttachment },
            format      = .BGRA8Unorm,
            width       = width,
            height      = height,
            presentMode = .Fifo,
            alphaMode   = .Opaque,
        }
        wgpu.SurfaceConfigure(state.surface, &state.config)

        state.queue = wgpu.DeviceGetQueue(state.device)

        shader :: #load("triangle.wgsl")

        state.module = wgpu.DeviceCreateShaderModule(state.device, &{
            nextInChain = &wgpu.ShaderModuleWGSLDescriptor{
                sType = .ShaderModuleWGSLDescriptor,
                code  = strings.unsafe_string_to_cstring(strings.clone_from_bytes(shader)),
            },
        })

        state.triangleVertexBuffer = wgpu.DeviceCreateBuffer(device, &{
            label            = "Vertex Buffer",
            usage            = {.Vertex, .CopyDst},
            size             = 3 * size_of(Vertex),
            mappedAtCreation = true,
        })
        destVerts := wgpu.BufferGetMappedRangeSlice(state.triangleVertexBuffer, 0, Vertex, 3)
        verts := []Vertex{
            {2*{0.0, 0.5, 0.0}},
            {2*{0.5, -0.5, 0.0}},
            {2*{-0.5, -0.5, 0.0}},
        }
        copy(destVerts, verts)
        wgpu.BufferUnmap(state.triangleVertexBuffer)
        
        vertexBuffer := wgpu.VertexBufferLayout {
            arrayStride = 3 * size_of(f32),
            stepMode = .Vertex,
            attributes = &wgpu.VertexAttribute{
                format = .Float32x3,
                offset = 0,
                shaderLocation = 0,
            },
            attributeCount = 1,
        }
        
        state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(state.device, &wgpu.PipelineLayoutDescriptor{})
        state.pipeline = wgpu.DeviceCreateRenderPipeline(state.device, &wgpu.RenderPipelineDescriptor{
            layout = state.pipeline_layout,
            vertex = wgpu.VertexState {
                module     = state.module,
                entryPoint = "vs_main",
                bufferCount = 1,
                buffers    = &vertexBuffer,
            },
            fragment = &wgpu.FragmentState{
                module      = state.module,
                entryPoint  = "fs_main",
                targetCount = 1,
                targets     = &wgpu.ColorTargetState{
                    format    = .BGRA8Unorm,
                    writeMask = wgpu.ColorWriteMaskFlags_All,
                },
            },
            primitive = wgpu.PrimitiveState{
                topology = .TriangleList,
            },
            multisample = {
                count = 1,
                mask  = 0xFFFFFFFF,
            },
        })

        os_run(&state.os)
    }
}

resize :: proc "c" () {
    context = state.ctx

    state.config.width, state.config.height = os_get_render_bounds(&state.os)
    wgpu.SurfaceConfigure(state.surface, &state.config)
}

frame :: proc "c" (dt: f32) {
    context = state.ctx

    surface_texture := wgpu.SurfaceGetCurrentTexture(state.surface)
    switch surface_texture.status {
    case .Success:
    // All good, could check for `surface_texture.suboptimal` here.
    case .Timeout, .Outdated, .Lost:
    // Skip this frame, and re-configure surface.
        if surface_texture.texture != nil {
            wgpu.TextureRelease(surface_texture.texture)
        }
        resize()
        return
    case .OutOfMemory, .DeviceLost:
    // Fatal error
        fmt.panicf("[triangle] get_current_texture status=%v", surface_texture.status)
    }
    defer wgpu.TextureRelease(surface_texture.texture)

    frame := wgpu.TextureCreateView(surface_texture.texture, nil)
    defer wgpu.TextureViewRelease(frame)

    command_encoder := wgpu.DeviceCreateCommandEncoder(state.device, nil)
    defer wgpu.CommandEncoderRelease(command_encoder)

    from := wgpu.Color{0.05, 0.05, 0.1, 1.}
    to := wgpu.Color{0.6, 0.2, 0.7, 1.}

    render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
    command_encoder, &{
        colorAttachmentCount = 1,
        colorAttachments     = &wgpu.RenderPassColorAttachment{
            view       = frame,
            loadOp     = .Clear,
            storeOp    = .Store,
            clearValue = math.lerp(wgpu.Color(state.os.clicked), from, to),
        },
    },
    )
    defer wgpu.RenderPassEncoderRelease(render_pass_encoder)

    wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.pipeline)
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass_encoder, 0, state.triangleVertexBuffer, 0, 9 * size_of(f32))
    wgpu.RenderPassEncoderDraw(render_pass_encoder, vertexCount=3, instanceCount=1, firstVertex=0, firstInstance=0)
    wgpu.RenderPassEncoderEnd(render_pass_encoder)

    command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
    defer wgpu.CommandBufferRelease(command_buffer)


    verts := []Vertex{
        {2*{f32(state.os.clicked-0.5), 0.5, 0.0}},
        {2*{0.5, -0.5, 0.0}},
        {2*{-0.5, -0.5, 0.0}},
    }
    wgpu.QueueWriteBuffer(state.queue, state.triangleVertexBuffer, 0, raw_data(verts), len(verts)*size_of(Vertex))
    wgpu.QueueSubmit(state.queue, { command_buffer })
    wgpu.SurfacePresent(state.surface)
}

finish :: proc() {
    wgpu.RenderPipelineRelease(state.pipeline)
    wgpu.PipelineLayoutRelease(state.pipeline_layout)
    wgpu.ShaderModuleRelease(state.module)
    wgpu.QueueRelease(state.queue)
    wgpu.DeviceRelease(state.device)
    wgpu.AdapterRelease(state.adapter)
    wgpu.SurfaceRelease(state.surface)
    wgpu.InstanceRelease(state.instance)
}

OS :: struct {
    initialized: bool,
    clicked: f64,
}

@(private="file")
g_os: ^OS

os_init :: proc(os: ^OS) {
    g_os = os
    assert(js.add_window_event_listener(.Resize, nil, size_callback))
    assert(js.add_event_listener("start", .Click, os, start_callback))
    assert(js.add_event_listener("stop", .Click, os, stop_callback))

    js.add_window_event_listener(.Pointer_Move, nil, proc(e: js.Event) {
        if (0 in e.mouse.buttons)
        {            
            state.os.clicked += f64(e.mouse.movement.x)/200
            state.os.clicked = clamp(state.os.clicked, 0, 1)
        }
    })

    js.add_window_event_listener(.Key_Press, nil, proc(e: js.Event) {
        // fmt.println("Key down", e.options)
    })
}

// NOTE: frame loop is done by the runtime.js repeatedly calling `step`.
os_run :: proc(os: ^OS) {
    os.initialized = true
}

os_get_render_bounds :: proc(os: ^OS) -> (width, height: u32) {
    rect := js.get_bounding_client_rect("c")
    return u32(rect.width), u32(rect.height)
}

os_get_surface :: proc(os: ^OS, instance: wgpu.Instance) -> wgpu.Surface {
    return wgpu.InstanceCreateSurface(
    instance,
    &wgpu.SurfaceDescriptor{
        nextInChain = &wgpu.SurfaceDescriptorFromCanvasHTMLSelector{
            sType = .SurfaceDescriptorFromCanvasHTMLSelector,
            selector = "#c",
        },
    },
    )
}

@(private="file", export)
step :: proc(dt: f32) -> bool {
    if !g_os.initialized {
        return true
    }

    frame(dt)
    return true
}

@(private="file", fini)
os_fini :: proc() {
    js.remove_window_event_listener(.Resize, nil, size_callback)
    js.remove_event_listener("start", .Click, g_os, start_callback)
    js.remove_event_listener("stop", .Click, g_os, stop_callback)

    finish()
}

size_callback :: proc(e: js.Event) {
    resize()
}

start_callback :: proc(e: js.Event) {
    data : ^OS = (^OS)(e.user_data);
    fmt.println("Clicked!", data)
    data.clicked += 0.1
}

stop_callback :: proc(e: js.Event) {
    data : ^OS = (^OS)(e.user_data);
    data.clicked = 0
}