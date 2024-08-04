package main

import "vendor:wgpu"
import "core:fmt"
import "base:runtime"
import "core:strings"
import "core:math"
import "core:strconv"
import "renderer"
import "core:math/linalg"
import "importer_model"
import gltf2 "glTF2"

DefaultMesh :: renderer.Mesh(renderer.Vertex, renderer.UniformData);
DefaultMeshGroup :: renderer.MeshGroup(renderer.Vertex, renderer.UniformData);
DefaultMaterial :: renderer.MaterialTemplate(renderer.Vertex, renderer.UniformData);

State :: struct {
    ctx: runtime.Context,
    os:  OS,
    
    clicked: f64,
    clickedSmoothed: f64,
    touchHeld: bool,

    timer: f64,

    pos: [3]f32,
    cam_pos: [3]f32,
    
    // duck_data_load: ^js_ext.fetch_promise_raw,

    render_manager:        renderer.RenderManagerState,
}

//@(private="file")
state: State

main :: proc() {
    state.ctx = context
    using state;

    os_init(&state.os)

    // state.duck_data_load = js_ext.fetch("https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/2.0/Duck/glTF-Binary/Duck.glb")

    render_manager.instance = wgpu.CreateInstance(nil)
    if render_manager.instance == nil {
        panic("WebGPU is not supported")
    }
    render_manager.surface = os_get_surface(&state.os, render_manager.instance)

    wgpu.InstanceRequestAdapter(render_manager.instance, &{ compatibleSurface = render_manager.surface }, on_adapter, nil)

    on_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: cstring, userdata: rawptr) {
        context = state.ctx
        if status != .Success || adapter == nil {
            fmt.panicf("request adapter failure: [%v] %s", status, message)
        }
        render_manager.adapter = adapter
        wgpu.AdapterRequestDevice(adapter, nil, on_device)
    }

    on_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: cstring, userdata: rawptr) {
        context = state.ctx

        // Setup device
        if status != .Success || device == nil {
            fmt.panicf("request device failure: [%v] %s", status, message)
        }
        render_manager.device = device
        found_limits := false
        limits: wgpu.SupportedLimits
        if limits, found_limits = wgpu.DeviceGetLimits(device); !found_limits {
            fmt.panicf("failed to get device limits")
        }

        // Setup surface
        render_manager.config = wgpu.SurfaceConfiguration {
            device      = render_manager.device,
            usage       = { .RenderAttachment },
            format      = .BGRA8Unorm,
            presentMode = .Fifo,
            alphaMode   = .Opaque,
        }
        resize();
        
        // Setup queue
        render_manager.queue = wgpu.DeviceGetQueue(render_manager.device)

        // Setup mesh and material arrays
        render_manager.meshes = make([dynamic]DefaultMesh)
        render_manager.material = make([dynamic]DefaultMaterial)
        render_manager.materialToMeshes = make(map[^DefaultMaterial]DefaultMeshGroup)

        // Load meshes and materials
        append(&render_manager.material, renderer.createDefaultMaterialTemplate(render_manager.device));

        // Load model
        importer_model.load_model(#load("../resources/models/duck.glb"), &state.render_manager)

        // Group meshes by material
        for &mesh in render_manager.meshes {
            if !(mesh.material in render_manager.materialToMeshes) {
                render_manager.materialToMeshes[mesh.material] = {make([dynamic]^DefaultMesh), nil, nil, 0}
            }
            group := &render_manager.materialToMeshes[mesh.material];
            append(&group.meshes, &mesh);
        }

        for material, &group in render_manager.materialToMeshes {
            fmt.println("Creating bind group for material", material)
            fmt.println("Group has", len(group.meshes), "meshes")
            group.uniformStride = ceil_to_next_multiple(size_of(renderer.UniformData), limits.limits.minUniformBufferOffsetAlignment)
            group.uniformBuffer = wgpu.DeviceCreateBuffer(render_manager.device, &wgpu.BufferDescriptor{
                label = "Uniform Buffer",
                size = u64(group.uniformStride * u32(len(group.meshes))),
                usage = {.Uniform, .CopyDst},
                mappedAtCreation = false
            });
            
            texture, texture_ok := material.texture.?
            assert(texture_ok, "Material does not have a texture")
            texture_view := wgpu.TextureCreateView(texture.texture, &wgpu.TextureViewDescriptor{
                label = "Material Texture View",
                format = .RGBA8Unorm,
                dimension = ._2D,
                aspect = .All,
                baseMipLevel = 0,
                mipLevelCount = 1,
                baseArrayLayer = 0,
                arrayLayerCount = 1,
            });

            group_entries := [?]wgpu.BindGroupEntry{
                {
                    binding = 0,
                    size = u64(group.uniformStride),
                    buffer = group.uniformBuffer,
                },
                {
                    binding = 1,
                    textureView = texture_view
                }
            };
            group.bindGroup = wgpu.DeviceCreateBindGroup(render_manager.device, &wgpu.BindGroupDescriptor{
                label = "Default Material Bind Group",
                layout = material.bindGroupLayout,
                entries = transmute([^]wgpu.BindGroupEntry)&group_entries,
                entryCount = len(group_entries),
            });

            for &mesh, i in group.meshes {
                wgpu.QueueWriteBuffer(render_manager.queue, group.uniformBuffer, u64(u32(i)*group.uniformStride), &renderer.UniformData{
                    0.0,
                    {},
                }, size_of(renderer.UniformData))
            }
        }

        os_run(&state.os)
    }
}

ceil_to_next_multiple :: proc(value, multiple: u32) -> u32 {
    return (value + multiple - 1) / multiple * multiple
}


resize :: proc "c" () {
    context = state.ctx
    using state

    render_manager.config.width, render_manager.config.height = os_get_render_bounds(&state.os)
    wgpu.SurfaceConfigure(render_manager.surface, &render_manager.config)
    if render_manager.depthTexture != nil {
        // Destroy the old depth texture
        wgpu.TextureViewRelease(render_manager.depthView)
        wgpu.TextureDestroy(render_manager.depthTexture)
        wgpu.TextureRelease(render_manager.depthTexture)
    }
    
    // Create Depth Texture
    depthFormat := wgpu.TextureFormat.Depth24Plus
    render_manager.depthTexture = wgpu.DeviceCreateTexture(render_manager.device, &wgpu.TextureDescriptor{
        label = "Depth Texture",
        size = {render_manager.config.width, render_manager.config.height, 1},
        mipLevelCount = 1,
        sampleCount = 1,
        dimension = ._2D,
        format = .Depth24Plus,
        usage = {.RenderAttachment},
        viewFormatCount = 1,
        viewFormats = &depthFormat,
    });
    render_manager.depthView = wgpu.TextureCreateView(render_manager.depthTexture, &wgpu.TextureViewDescriptor{
        label = "Depth Texture View",
        format = .Depth24Plus,
        dimension = ._2D,
        aspect = .DepthOnly,
        baseMipLevel = 0,
        mipLevelCount = 1,
        baseArrayLayer = 0,
        arrayLayerCount = 1,
    });
}

trigger_once: b8
frame :: proc "c" (dt: f32) {
    context = state.ctx
    using state
    
    // if state.duck_data_load.is_done == 1 {
    //     if !trigger_once {
    //         trigger_once = true
    //         duck_data := state.duck_data_load.buffer[:state.duck_data_load.buffer_length]
    //         fmt.println("Duck data is done", len(duck_data))
    //     }
    // } else {
    //     fmt.println("Duck data is not done")
    // }
    
    surface_texture := wgpu.SurfaceGetCurrentTexture(render_manager.surface)
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

    command_encoder := wgpu.DeviceCreateCommandEncoder(render_manager.device, nil)
    defer wgpu.CommandEncoderRelease(command_encoder)

    from := wgpu.Color{0.05, 0.05, 0.1, 1.}
    to := wgpu.Color{0.6, 0.2, 0.7, 1.}
    state.clickedSmoothed = math.lerp(state.clickedSmoothed, state.clicked, f64(2*dt))

    render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
    command_encoder, &{
        colorAttachmentCount = 1,
        colorAttachments     = &wgpu.RenderPassColorAttachment{
            view       = frame,
            loadOp     = .Clear,
            storeOp    = .Store,
            clearValue = math.lerp(wgpu.Color(state.clickedSmoothed), from, to),
        },
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = render_manager.depthView,
            
            depthClearValue = 1.0,
            depthLoadOp = .Clear,
            depthStoreOp = .Store,
            depthReadOnly = false,

            stencilClearValue = 0,
            stencilLoadOp = {},
            stencilStoreOp = {},
            stencilReadOnly = true,
        }
    },
    )
    defer wgpu.RenderPassEncoderRelease(render_pass_encoder)
    wgpu.RenderPassEncoderEnd(render_pass_encoder)


    for material, meshGroup in render_manager.materialToMeshes {
        render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
        command_encoder, &{
            colorAttachmentCount = 1,
            colorAttachments     = &wgpu.RenderPassColorAttachment{
                view       = frame,
                loadOp     = .Load,
                storeOp    = .Store,
                clearValue = wgpu.Color{0.0, 0.0, 0.0, 1.0},
            },
            depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                view = render_manager.depthView,
                
                depthClearValue = 1.0,
                depthLoadOp = .Clear,
                depthStoreOp = .Store,
                depthReadOnly = false,
    
                stencilClearValue = 0,
                stencilLoadOp = {},
                stencilStoreOp = {},
                stencilReadOnly = true,
            }
        })
        defer wgpu.RenderPassEncoderRelease(render_pass_encoder)

        for &mesh, i in meshGroup.meshes {
            projection := linalg.matrix4_perspective((90.0/360.0)*6.28318530718, f32(render_manager.config.width)/f32(render_manager.config.height), 0.00001, 1000, false)
            view := linalg.matrix4_look_at(linalg.Vector3f32{
                state.cam_pos.x, state.cam_pos.y, state.cam_pos.z
                // 0, 0, 0
            }, linalg.Vector3f32{
                // state.cam_pos.x, state.cam_pos.y, state.cam_pos.z,
                math.cos(f32(0.25)*6.28)*20,
                0,
                math.sin(f32(0.25)*6.28)*20
            }, linalg.Vector3f32{
                0.0, 1.0, 0.0
            })

            // fmt.println("Drawing mesh", mesh, "with material", mesh.material)
            wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, material.pipeline)
            wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, meshGroup.bindGroup, []u32{u32(i)*meshGroup.uniformStride});
            wgpu.RenderPassEncoderSetVertexBuffer(render_pass_encoder, 0, mesh.vertBuffer, 0, u64(len(mesh.vertices)*size_of(renderer.Vertex)))
            wgpu.RenderPassEncoderSetIndexBuffer(render_pass_encoder, mesh.indexBuffer, wgpu.IndexFormat.Uint32, 0, u64(len(mesh.indices)*size_of(u32)))
            wgpu.RenderPassEncoderDrawIndexed(render_pass_encoder, u32(len(mesh.indices)), 1, 0, 0, 0)
            wgpu.QueueWriteBuffer(render_manager.queue, meshGroup.uniformBuffer, u64(u32(i)*meshGroup.uniformStride), &renderer.UniformData{
                f32(state.clickedSmoothed),
                projection * view * linalg.matrix4_from_trs(
                    linalg.Vector3f32{state.pos.x, state.pos.y, state.pos.z},
                    linalg.quaternion_from_euler_angle_y(f32(state.timer)), //
                    linalg.Vector3f32(1)
                ),
            }, size_of(renderer.UniformData))
        }
        wgpu.RenderPassEncoderEnd(render_pass_encoder)
    }
    // fmt.println("Finished drawing meshes")
    state.timer += f64(dt)


    command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
    defer wgpu.CommandBufferRelease(command_buffer)
    wgpu.QueueSubmit(render_manager.queue, { command_buffer })
    wgpu.SurfacePresent(render_manager.surface)
}


finish :: proc() {
    using state
    for &mesh in render_manager.meshes {
        renderer.releaseMesh(&mesh)
    }
    for &material in render_manager.material {
        renderer.releaseMaterialTemplate(&material)
    }
    wgpu.QueueRelease(render_manager.queue)
    wgpu.DeviceRelease(render_manager.device)
    wgpu.AdapterRelease(render_manager.adapter)
    wgpu.SurfaceRelease(render_manager.surface)
    wgpu.InstanceRelease(render_manager.instance)
}