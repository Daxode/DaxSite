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
import "vendor:microui"

State :: struct {
    // runtime state
    ctx: runtime.Context,
    os:  OS,
    render_manager:        renderer.RenderManagerState,
    
    uiRender: renderer.DrawInfo,
    uiCtx: microui.Context,

    // game state
    timer: f64,
    clickedSmoothed: f64,
    sliderValue: f32,
    color: [4]f32,
    textbox: [256]u8,
    textboxLength: int,

    // duck_data_load: ^js_ext.fetch_promise_raw,
}
@(private="file")
state: State

InputState :: struct {
    clicked: f64,
    pos: linalg.Vector3f32,
    cam_pos: linalg.Vector3f32,
}

main :: proc() {
    state.ctx = context
    using state;

    os_init(&state.os, &state.ctx)
    impl_microui(&state.os, &state.uiCtx)

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
        set := renderer.CreateRenderSet(&state.render_manager, renderer.Vertex, renderer.UniformData)

        // Load model
        loaded_model := importer_model.load_model(#load("../resources/models/duck.glb"), set)
        for importModelResult in loaded_model {
            // Create mesh instance
            append(&set.meshInstances, renderer.MeshInstance(renderer.Vertex, renderer.UniformData) {
                importModelResult.meshTemplate,
                importModelResult.renderInstance,
                linalg.matrix4_scale_f32(0.01),
            })

            // create 20 more instances
            for i in 0..<20 {
                append(&set.meshInstances, renderer.MeshInstance(renderer.Vertex, renderer.UniformData) {
                    importModelResult.meshTemplate,
                    importModelResult.renderInstance,
                    linalg.matrix4_translate_f32({-1, f32(i), 0}) * linalg.matrix4_scale_f32(0.01),
                })
            }
        }

        // Group meshes by material
        for &meshInstance, meshInstanceIndex in set.meshInstances {
            materialTemplateIndex := meshInstance.renderInstanceIndex
            if !(materialTemplateIndex in set.materialToMeshes) {
                set.materialToMeshes[materialTemplateIndex] = {}
            }
            group := &set.materialToMeshes[materialTemplateIndex];
            append(&group.meshes, renderer.MeshInstanceIndex(meshInstanceIndex));
        }

        // Create bind groups
        for material_index, &group in set.materialToMeshes {
            material := set.renderInstances[material_index]
            fmt.println("Creating bind group for material", material)
            fmt.println("Group has", len(group.meshes), "meshes")
            group.uniformStride = ceil_to_next_multiple(size_of(renderer.UniformData), limits.limits.minUniformBufferOffsetAlignment)
            group.uniformBuffer = wgpu.DeviceCreateBuffer(render_manager.device, &wgpu.BufferDescriptor{
                label = "Uniform Buffer",
                size = u64(group.uniformStride * u32(len(group.meshes))),
                usage = {.Uniform, .CopyDst},
                mappedAtCreation = false
            });
            
            assert(material.textures[0]!=-1, "Material does not have a texture")
            group_entries := [?]wgpu.BindGroupEntry{
                {
                    binding = 0,
                    size = u64(group.uniformStride),
                    buffer = group.uniformBuffer,
                },
                {
                    binding = 1,
                    textureView = set.textures[material.textures[0]].view,
                }
            };
            group.bindGroup = wgpu.DeviceCreateBindGroup(render_manager.device, &wgpu.BindGroupDescriptor{
                label = "Default Material Bind Group",
                layout = material.materialTemplate.bindGroupLayout,
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

        // Implement the ui render
        state.uiRender.materialTemplate = renderer.createUIMaterialTemplate(state.render_manager.device)
        state.uiRender.meshTemplate = renderer.createUIMeshTemplate(state.render_manager.device)
        state.uiCtx.text_width = renderer.ui_text_width
        state.uiCtx.text_height = renderer.ui_text_height

        os_run(&state.os)
    }
}

ceil_to_next_multiple :: proc(value, multiple: u32) -> u32 {
    return (value + multiple - 1) / multiple * multiple
}

resize :: proc "c" () {
    context = state.ctx
    state.render_manager.config.width, state.render_manager.config.height = os_get_render_bounds(&state.os)
    renderer.resize_screen(&state.render_manager)
}

frame :: proc "c" (dt: f32) {
    context = state.ctx
    using state

    // Game Logic
    // ...
    uiCtx.style.footer_height = 10
    uiCtx.style.indent = 2
    uiCtx.style.colors[microui.Color_Type.WINDOW_BG] = microui.Color{30, 25, 35, 150}
    uiCtx.style.colors[microui.Color_Type.TITLE_BG] = microui.Color{5, 0, 10, 100}
    uiCtx.style.colors[microui.Color_Type.BORDER] = microui.Color{100,100,100,50}
    uiCtx.style.colors[microui.Color_Type.BUTTON] = microui.Color{100,100,100,80}

    microui.begin(&uiCtx)
    if microui.window(&uiCtx, "Hello", {0, 0, 512, 512}, {microui.Opt.NO_CLOSE}) {
        uiCtx.style.colors[microui.Color_Type.TEXT] = microui.Color{255, 0, 255, 255}
        microui.label(&uiCtx, "Hello, world!")
        microui.label(&uiCtx, "This is a test.")
        uiCtx.style.colors[microui.Color_Type.TEXT] = microui.Color{0, 255, 255, 255}
        microui.layout_row(&uiCtx, {-1})
        if (.SUBMIT in microui.button(&uiCtx, "Open World Window")) {
            microui.get_container(&uiCtx, "World").open = true
        }

        width := uiCtx.text_width(uiCtx.style.font, "Slider:") + 10
        microui.layout_row(&uiCtx, {width, -1})
        microui.label(&uiCtx, "Slider:")
        microui.slider(&uiCtx, &state.sliderValue, 0, 1, fmt_string="Val:%.2f")

        microui.layout_row(&uiCtx, {-1})
        microui.textbox(&uiCtx, state.textbox[:], &state.textboxLength)

        uiCtx.style.colors[microui.Color_Type.TEXT] = microui.Color{255, 255, 255, 255}
        
        if microui.window(&uiCtx, "World", {0, 0, 512, 512}, {microui.Opt.CLOSED}) {
            microui.label(&uiCtx, "Hello, world!")
            microui.label(&uiCtx, "This is a test.")

            sw := i32(f32(microui.get_current_container(&uiCtx).body.w) * 0.14);
            microui.layout_row(&uiCtx, {18, sw, sw, sw, sw, -1})
            for i in 0..<1 {
                microui.label(&uiCtx, fmt.aprint(i));
                microui.slider(&uiCtx, &state.color.r, 0, 1)
                microui.slider(&uiCtx, &state.color.g, 0, 1)
                microui.slider(&uiCtx, &state.color.b, 0, 1)
                microui.slider(&uiCtx, &state.color.a, 0, 1)
                microui.draw_rect(&uiCtx, microui.layout_next(&uiCtx), microui.Color{u8(state.color.r*255), u8(state.color.g*255), u8(state.color.b*255), u8(state.color.a*255)})
            }

            // mu_layout_row(ctx, 6, (int[]) { 80, sw, sw, sw, sw, -1 }, 0);
            // for (int i = 0; colors[i].label; i++) {
            //     mu_label(ctx, colors[i].label);
            //     uint8_slider(ctx, &ctx->style->colors[i].r, 0, 255);
            //     uint8_slider(ctx, &ctx->style->colors[i].g, 0, 255);
            //     uint8_slider(ctx, &ctx->style->colors[i].b, 0, 255);
            //     uint8_slider(ctx, &ctx->style->colors[i].a, 0, 255);
            //     mu_draw_rect(ctx, mu_layout_next(ctx), ctx->style->colors[i]);
            // }
        }
    }
    microui.end(&uiCtx)

    // Draw Frame
    {
        // Create a new frame command buffer
        command_buffer, ok := renderer.StartFrameCommandBuffer(&state.render_manager, resize)
        defer renderer.EndFrameCommandBuffer(&state.render_manager, &command_buffer)
        if !ok {
            return
        }
    
        // Clear the screen
        from := wgpu.Color{0.05, 0.05, 0.1, 1.}
        to := wgpu.Color{0.6, 0.2, 0.7, 1.}
        state.clickedSmoothed = math.lerp(state.clickedSmoothed, state.os.input.clicked, f64(2*dt))
        renderer.CommandBufferEncodeRenderPassSolidColor(&state.render_manager, &command_buffer, math.lerp(wgpu.Color(state.clickedSmoothed), from, to))
    
        // Draw meshes
        projection := linalg.matrix4_perspective((90.0/360.0)*6.28318530718, f32(render_manager.config.width)/f32(render_manager.config.height), 0.00001, 1000, false)
        view := linalg.matrix4_look_at(linalg.Vector3f32{
            state.os.input.cam_pos.x, state.os.input.cam_pos.y, state.os.input.cam_pos.z
            // 0, 0, 0
        }, linalg.Vector3f32{
            // state.cam_pos.x, state.cam_pos.y, state.cam_pos.z,
            math.cos(f32(0.25)*6.28)*20,
            0,
            math.sin(f32(0.25)*6.28)*20
        }, linalg.Vector3f32{
            0.0, 1.0, 0.0
        })
        viewProjection := projection * view
        for &set in state.render_manager.rendererSet {
            set.meshInstances[0].transform = linalg.matrix4_from_trs(
                linalg.Vector3f32{state.os.input.pos.x, state.os.input.pos.y, state.os.input.pos.z},
                linalg.quaternion_from_euler_angle_y(f32(state.timer)),
                linalg.Vector3f32(1)
            )
            renderer.DrawMeshes(&set, &command_buffer, viewProjection, f32(state.clickedSmoothed))
        }

        // Draw UI
        renderer.DrawUI(
            state.render_manager.device, state.render_manager.queue, &state.uiRender, 
            {f32(state.render_manager.config.width), f32(state.render_manager.config.height)}, &state.uiCtx, &command_buffer)
    }

    state.timer += f64(dt)
}


finish :: proc() {
    using state
    renderer.ReleaseRenderManager(&state.render_manager)
}