package main

import "vendor:wgpu"
import js "vendor:wasm/js"
import "core:fmt"
import "base:runtime"
import "core:strings"
import "core:math"
import "core:strconv"
import "js_ext"
import "renderer"
import "core:math/linalg"
import "gltf2"

DefaultMesh :: renderer.Mesh(renderer.Vertex, renderer.UniformData);
DefaultMeshGroup :: renderer.MeshGroup(renderer.Vertex, renderer.UniformData);
DefaultMaterial :: renderer.MaterialTemplate(renderer.Vertex, renderer.UniformData);

State :: struct {
    ctx: runtime.Context,
    os:  OS,

    // WebGPU
    instance:        wgpu.Instance,
    adapter:         wgpu.Adapter,
    device:          wgpu.Device,
    queue:           wgpu.Queue,

    // Surface
    config:          wgpu.SurfaceConfiguration,
    surface:         wgpu.Surface,
    depthTexture:    wgpu.Texture,
    depthView:       wgpu.TextureView,
    
    model_data: ^gltf2.Data,

    // Meshes and materials
    meshes:          [dynamic]DefaultMesh,
    material:        [dynamic]DefaultMaterial,
    materialToMeshes: map[^DefaultMaterial]DefaultMeshGroup,
}

@(private="file")
state: State

main :: proc() {
    state.ctx = context

    os_init(&state.os)

    container_gltf :: #load("../resources/models/duck.glb")
    model_load_error: gltf2.Error
    state.model_data, model_load_error = gltf2.parse(container_gltf, gltf2.Options{
        is_glb = true,
    })
    if model_load_error != nil {
        fmt.panicf("Failed to load model", model_load_error)
    }

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

        // Setup device
        if status != .Success || device == nil {
            fmt.panicf("request device failure: [%v] %s", status, message)
        }
        state.device = device
        found_limits := false
        limits: wgpu.SupportedLimits
        if limits, found_limits = wgpu.DeviceGetLimits(device); !found_limits {
            fmt.panicf("failed to get device limits")
        }

        // Setup surface
        state.config = wgpu.SurfaceConfiguration {
            device      = state.device,
            usage       = { .RenderAttachment },
            format      = .BGRA8Unorm,
            presentMode = .Fifo,
            alphaMode   = .Opaque,
        }
        resize();
        
        // Setup queue
        state.queue = wgpu.DeviceGetQueue(state.device)

        // Setup mesh and material arrays
        state.meshes = make([dynamic]DefaultMesh)
        state.material = make([dynamic]DefaultMaterial)
        state.materialToMeshes = make(map[^DefaultMaterial]DefaultMeshGroup)

        // Load meshes and materials
        append(&state.material, renderer.createDefaultMaterialTemplate(state.device));
        
        //Create plane under cube
        append(&state.meshes, renderer.createMesh(state.device, [dynamic]renderer.Vertex{
            {{-1.0*5, -0.5, -1.0*5}, {0.0, 0.0, 0.0}, {0.0, 0.0}},
            {{ 1.0*5, -0.5, -1.0*5}, {0.0, 0.0, 0.0}, {0.0, 0.0}},
            {{ 1.0*5, -0.5,  1.0*5}, {0.0, 0.0, 0.0}, {0.0, 0.0}},
            {{-1.0*5, -0.5,  1.0*5}, {0.0, 0.0, 0.0}, {0.0, 0.0}},
        }[:], [dynamic]u32 {
            0, 1, 2, 0, 2, 3
        }[:], &state.material[len(state.material)-1]));

        for mesh in state.model_data.meshes {
            fmt.println("Creating mesh for", mesh.name)
            for primitive in mesh.primitives {
                pos_attr_index, has_pos_attr := primitive.attributes["POSITION"]
                assert(has_pos_attr, "Mesh has no position attribute")
                pos_attr := state.model_data.accessors[pos_attr_index]
                mesh_verts := make([dynamic]renderer.Vertex, pos_attr.count)
                fmt.println("Mesh has", pos_attr.count, "vertices", "with accessor", pos_attr)

                if buffer_view_index, buffer_view_ok := pos_attr.buffer_view.?; buffer_view_ok {
                    buffer_view := state.model_data.buffer_views[buffer_view_index]
                    // fmt.println("Buffer view has", buffer_view)
                    buffer := state.model_data.buffers[buffer_view.buffer]
                    switch buffer_uri in buffer.uri {
                        case string:
                            fmt.panicf("Buffer has URI", buffer_uri, "which is not supported currently.. Might be able to use fetch in future")
                        case []byte:
                            stride, _ := buffer_view.byte_stride.?
                            for &vert, i in mesh_verts {
                                index := u32(i)*stride + buffer_view.byte_offset + pos_attr.byte_offset
                                vert.position = (transmute(^[3]f32)raw_data(buffer_uri[index:]))^
                                // fmt.println("Position", i, "is", vert)
                            }
                    }
                }

                if normal_attr_index, has_normal_attr := primitive.attributes["NORMAL"]; has_normal_attr {
                    normal_attr := state.model_data.accessors[normal_attr_index]
                    if buffer_view_index, buffer_view_ok := normal_attr.buffer_view.?; buffer_view_ok {
                        buffer_view := state.model_data.buffer_views[buffer_view_index]
                        // fmt.println("Buffer view has", buffer_view)
                        buffer := state.model_data.buffers[buffer_view.buffer]
                        switch buffer_uri in buffer.uri {
                            case string:
                                fmt.panicf("Buffer has URI", buffer_uri, "which is not supported currently.. Might be able to use fetch in future")
                            case []byte:
                                stride, _ := buffer_view.byte_stride.?
                                for &vert, i in mesh_verts {
                                    index := u32(i)*stride + buffer_view.byte_offset + normal_attr.byte_offset
                                    vert.normal = (transmute(^[3]f32)raw_data(buffer_uri[index:]))^
                                    // fmt.println("Normal", i, "is", vert)
                                }
                        }
                    }
                }


                index_attr_index, has_index_attr := primitive.indices.?
                assert(has_index_attr, "Mesh has no index attribute")
                index_attr := state.model_data.accessors[index_attr_index]
                mesh_indices := make([dynamic]u32, index_attr.count)
                if buffer_view_index, buffer_view_ok := index_attr.buffer_view.?; buffer_view_ok {
                    buffer_view := state.model_data.buffer_views[buffer_view_index]
                    // fmt.println("Buffer view has", buffer_view)
                    buffer := state.model_data.buffers[buffer_view.buffer]
                    switch buffer_uri in buffer.uri {
                        case string:
                            fmt.panicf("Buffer has URI", buffer_uri, "which is not supported currently.. Might be able to use fetch in future")
                        case []byte:
                            for &mesh_index, i in mesh_indices {
                                index := u32(i)*2 + buffer_view.byte_offset
                                mesh_index = u32((transmute(^u16)raw_data(buffer_uri[index:]))^)
                                // fmt.println("Index", i, "is", mesh_index)
                            }
                    }
                }
                // fmt.println("Creating mesh with", len(mesh_verts), "vertices and", len(mesh_indices), "indices")
                // fmt.println("Vertices", mesh_verts)
                // fmt.println("Indices", mesh_indices)

                append(&state.meshes, renderer.createMesh(state.device, mesh_verts[:], mesh_indices[:], &state.material[0]))
            }
        }


        // Group meshes by material
        for &mesh in state.meshes {
            if !(mesh.material in state.materialToMeshes) {
                state.materialToMeshes[mesh.material] = {make([dynamic]^DefaultMesh), nil, nil, 0}
            }
            group := &state.materialToMeshes[mesh.material];
            append(&group.meshes, &mesh);
        }

        for material, &group in state.materialToMeshes {
            fmt.println("Creating bind group for material", material)
            fmt.println("Group has", len(group.meshes), "meshes")
            group.uniformStride = ceil_to_next_multiple(size_of(renderer.UniformData), limits.limits.minUniformBufferOffsetAlignment)
            group.uniformBuffer = wgpu.DeviceCreateBuffer(state.device, &wgpu.BufferDescriptor{
                label = "Uniform Buffer",
                size = u64(group.uniformStride * u32(len(group.meshes))),
                usage = {.Uniform, .CopyDst},
                mappedAtCreation = false
            });

            group.bindGroup = wgpu.DeviceCreateBindGroup(state.device, &wgpu.BindGroupDescriptor{
                label = "Default Material Bind Group",
                layout = material.bindGroupLayout,
                entries = &wgpu.BindGroupEntry{
                    binding = 0,
                    size = u64(group.uniformStride),
                    buffer = group.uniformBuffer,
                },
                entryCount = 1,
            });

            for &mesh, i in group.meshes {
                wgpu.QueueWriteBuffer(state.queue, group.uniformBuffer, u64(u32(i)*group.uniformStride), &renderer.UniformData{
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

    state.config.width, state.config.height = os_get_render_bounds(&state.os)
    wgpu.SurfaceConfigure(state.surface, &state.config)
    if state.depthTexture != nil {
        // Destroy the old depth texture
        wgpu.TextureViewRelease(state.depthView)
        wgpu.TextureDestroy(state.depthTexture)
        wgpu.TextureRelease(state.depthTexture)
    }

    // Create Depth Texture
    depthFormat := wgpu.TextureFormat.Depth24Plus
    state.depthTexture = wgpu.DeviceCreateTexture(state.device, &wgpu.TextureDescriptor{
        label = "Depth Texture",
        size = {state.config.width, state.config.height, 1},
        mipLevelCount = 1,
        sampleCount = 1,
        dimension = ._2D,
        format = .Depth24Plus,
        usage = {.RenderAttachment},
        viewFormatCount = 1,
        viewFormats = &depthFormat,
    });
    state.depthView = wgpu.TextureCreateView(state.depthTexture, &wgpu.TextureViewDescriptor{
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
    state.os.clickedSmoothed = math.lerp(state.os.clickedSmoothed, state.os.clicked, f64(2*dt))

    render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
    command_encoder, &{
        colorAttachmentCount = 1,
        colorAttachments     = &wgpu.RenderPassColorAttachment{
            view       = frame,
            loadOp     = .Clear,
            storeOp    = .Store,
            clearValue = math.lerp(wgpu.Color(state.os.clickedSmoothed), from, to),
        },
        depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
            view = state.depthView,
            
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


    for material, meshGroup in state.materialToMeshes {
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
                view = state.depthView,
                
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
            projection := linalg.matrix4_perspective((90.0/360.0)*6.28318530718, f32(state.config.width)/f32(state.config.height), 0.0000000001, 100, false)
            view := linalg.matrix4_look_at(linalg.Vector3f32{
                state.os.cam_pos.x, state.os.cam_pos.y, state.os.cam_pos.z
                // 0, 0, 0
            }, linalg.Vector3f32{
                // state.os.cam_pos.x, state.os.cam_pos.y, state.os.cam_pos.z,
                math.cos(f32(state.os.clickedSmoothed)*6.28)*20,
                0,
                math.sin(f32(state.os.clickedSmoothed)*6.28)*20
            }, linalg.Vector3f32{
                0.0, 1.0, 0.0
            })

            // fmt.println("Drawing mesh", mesh, "with material", mesh.material)
            wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, material.pipeline)
            wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, meshGroup.bindGroup, []u32{u32(i)*meshGroup.uniformStride});
            wgpu.RenderPassEncoderSetVertexBuffer(render_pass_encoder, 0, mesh.vertBuffer, 0, u64(len(mesh.vertices)*size_of(renderer.Vertex)))
            wgpu.RenderPassEncoderSetIndexBuffer(render_pass_encoder, mesh.indexBuffer, wgpu.IndexFormat.Uint32, 0, u64(len(mesh.indices)*size_of(u32)))
            wgpu.RenderPassEncoderDrawIndexed(render_pass_encoder, u32(len(mesh.indices)), 1, 0, 0, 0)
            wgpu.QueueWriteBuffer(state.queue, meshGroup.uniformBuffer, u64(u32(i)*meshGroup.uniformStride), &renderer.UniformData{
                f32(state.os.clickedSmoothed),
                projection * view * linalg.matrix4_from_trs(
                    linalg.Vector3f32{state.os.pos.x, state.os.pos.y, state.os.pos.z},
                    linalg.quaternion_from_euler_angle_y(f32(state.os.timer)*f32(i)), //
                    linalg.Vector3f32(0.01)
                ),
            }, size_of(renderer.UniformData))
        }
        wgpu.RenderPassEncoderEnd(render_pass_encoder)
    }
    fmt.println("Finished drawing meshes")
    state.os.timer += f64(dt)


    command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
    defer wgpu.CommandBufferRelease(command_buffer)
    wgpu.QueueSubmit(state.queue, { command_buffer })
    wgpu.SurfacePresent(state.surface)
}


finish :: proc() {
    for &mesh in state.meshes {
        renderer.releaseMesh(&mesh)
    }
    for &material in state.material {
        renderer.releaseMaterialTemplate(&material)
    }
    wgpu.QueueRelease(state.queue)
    wgpu.DeviceRelease(state.device)
    wgpu.AdapterRelease(state.adapter)
    wgpu.SurfaceRelease(state.surface)
    wgpu.InstanceRelease(state.instance)
}

OS :: struct {
    initialized: bool,
    clicked: f64,
    clickedSmoothed: f64,
    touchHeld: bool,

    timer: f64,

    pos: [3]f32,
    cam_pos: [3]f32
}

@(private="file")
g_os: ^OS

os_init :: proc(os: ^OS) {
    g_os = os
    assert(js.add_window_event_listener(.Resize, nil, size_callback))
    assert(js.add_event_listener("start", .Click, os, start_callback))
    assert(js.add_event_listener("stop", .Click, os, stop_callback))

    js.add_window_event_listener(.Touch_Start, nil, proc(e: js.Event) {
        state.os.touchHeld = true
    })

    js.add_window_event_listener(.Touch_Cancel, nil, proc(e: js.Event) {
        state.os.touchHeld = false
    })

    js.add_window_event_listener(.Pointer_Move, nil, proc(e: js.Event) {
        if (0 in e.mouse.buttons || state.os.touchHeld)
        {
            state.os.clicked += f64(e.mouse.movement.x)/200
            state.os.clicked = clamp(state.os.clicked, 0, 1)
            js_ext.set_element_text_string("start", fmt.aprintf("Increment: %.2f", state.os.clicked))
        }
    })

    js.add_window_event_listener(.Key_Press, nil, proc(e: js.Event) {
        // fmt.println("Key down", e.options)
    })

    js.add_custom_event_listener("pos-x", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.os.pos.x = f32(strconv.atof(js.get_element_value_string("pos-x", data[:])))
    })

    js.add_custom_event_listener("pos-y", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.os.pos.y = f32(strconv.atof(js.get_element_value_string("pos-y", data[:])))
    })

    js.add_custom_event_listener("pos-z", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.os.pos.z = f32(strconv.atof(js.get_element_value_string("pos-z", data[:])))
    })

    js.add_custom_event_listener("cam-x", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.os.cam_pos.x = f32(strconv.atof(js.get_element_value_string("cam-x", data[:])))
    })

    js.add_custom_event_listener("cam-y", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.os.cam_pos.y = f32(strconv.atof(js.get_element_value_string("cam-y", data[:])))
    })

    js.add_custom_event_listener("cam-z", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.os.cam_pos.z = f32(strconv.atof(js.get_element_value_string("cam-z", data[:])))
    })


    js.add_window_event_listener(.HashChange, nil, proc(e: js.Event) {
        buf := [256]u8{};
        val := js_ext.get_current_url(buf[:])
        fmt.println("Current URL:", val)
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
    data.clicked = clamp(data.clicked, 0, 1)
    js_ext.set_element_text_string("start", fmt.aprintf("Increment: %.2f", state.os.clicked))
}

stop_callback :: proc(e: js.Event) {
    data : ^OS = (^OS)(e.user_data);
    data.clicked = 0
    js_ext.set_element_text_string("start", fmt.aprintf("Increment: %.2f", state.os.clicked))
}