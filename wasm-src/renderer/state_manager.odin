package renderer

import "core:fmt"
import "vendor:wgpu"
import "core:math/linalg"

resize_screen :: proc(render_manager: ^RenderManagerState) {
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

CreateRenderSet :: proc(state: ^RenderManagerState, $TVert: typeid, $TUniform: typeid) -> ^RendererSet(TVert, TUniform) {
    result := RendererSet(TVert, TUniform){
        textures = make([dynamic]Texture),
        meshInstances = make([dynamic]MeshInstance(TVert, TUniform)),
        meshTemplates = make([dynamic]MeshTemplate(TVert, TUniform)),
        renderInstances = make([dynamic]RenderInstance(TVert, TUniform)),
        materialToMeshes = make(map[RenderInstanceIndex]MeshGroup(TVert, TUniform)),
        owningState = state,
    };
    append(&state.rendererSet, result);
    return &state.rendererSet[len(state.rendererSet) - 1];
}

// note when free set is implemented, this will need to be updated so it removes the set first
ReleaseRenderSet :: proc(render_set: ^RendererSet($TVert, $TUniform))
{
    for _, meshTemplateIndex in render_set.meshTemplates {
        ReleaseMeshTemplate(render_set, MeshTemplateIndex(meshTemplateIndex))
    }
    for _, renderInstanceIndex in render_set.renderInstances {
        ReleaseRenderInstance(render_set, RenderInstanceIndex(renderInstanceIndex))
    }
    for texture in render_set.textures {
        wgpu.TextureRelease(texture.texture)
    }
    for _, meshGroup in render_set.materialToMeshes {
        wgpu.BufferRelease(meshGroup.uniformBuffer)
        wgpu.BindGroupRelease(meshGroup.bindGroup)
    }
    delete(render_set.meshInstances)
    delete(render_set.meshTemplates)
    delete(render_set.renderInstances)
    delete(render_set.textures)
    delete(render_set.materialToMeshes)
}

ReleaseRenderManager :: proc(render_manager: ^RenderManagerState) {
    for &renderSet in render_manager.rendererSet {
        ReleaseRenderSet(&renderSet)
    }

    wgpu.QueueRelease(render_manager.queue)
    wgpu.DeviceRelease(render_manager.device)
    wgpu.AdapterRelease(render_manager.adapter)
    wgpu.SurfaceRelease(render_manager.surface)
    wgpu.InstanceRelease(render_manager.instance)
}

StartFrameCommandBuffer :: proc(render_manager: ^RenderManagerState, resize: proc "c" ()) -> (CommandBuffer, b8) {
    result := CommandBuffer{}
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
            return result, false
        case .OutOfMemory, .DeviceLost:
            // Fatal error
            fmt.panicf("[triangle] get_current_texture status=%v", surface_texture.status)
    }    
    frame := wgpu.TextureCreateView(surface_texture.texture, nil)
    command_encoder := wgpu.DeviceCreateCommandEncoder(render_manager.device, nil)
    return CommandBuffer{command_encoder, surface_texture, frame}, true
}

EndFrameCommandBuffer :: proc(render_manager: ^RenderManagerState, command_buffer: ^CommandBuffer) {
    commands := wgpu.CommandEncoderFinish(command_buffer.encoder, nil)
    wgpu.QueueSubmit(render_manager.queue, { commands })
    wgpu.SurfacePresent(render_manager.surface)
    
    wgpu.CommandBufferRelease(commands)
    wgpu.CommandEncoderRelease(command_buffer.encoder)
    wgpu.TextureRelease(command_buffer.surfaceTexture.texture)
    wgpu.TextureViewRelease(command_buffer.frame)
}

CommandBufferEncodeRenderPassSolidColor :: proc(render_manager: ^RenderManagerState, command_buffer: ^CommandBuffer, color: wgpu.Color) {
    render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
        command_buffer.encoder, &{
            colorAttachmentCount = 1,
            colorAttachments     = &wgpu.RenderPassColorAttachment{
                view       = command_buffer.frame,
                loadOp     = .Clear,
                storeOp    = .Store,
                clearValue = color,
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
}

DrawMeshes :: proc(set: ^RendererSet($TVert, $TUniformData), command_buffer: ^CommandBuffer, viewProjection: linalg.Matrix4f32, time: f32) {
    for renderInstanceIndex, meshGroup in set.materialToMeshes {
        render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
        command_buffer.encoder, &{
            colorAttachmentCount = 1,
            colorAttachments     = &wgpu.RenderPassColorAttachment{
                view       = command_buffer.frame,
                loadOp     = .Load,
                storeOp    = .Store,
                clearValue = wgpu.Color{0.0, 0.0, 0.0, 1.0},
            },
            depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                view = set.owningState.depthView,
                
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
        material := set.renderInstances[renderInstanceIndex]
        wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, material.materialTemplate.pipeline)
        for meshInstanceIndex, i in meshGroup.meshes {
            meshInstance := set.meshInstances[meshInstanceIndex]
            meshTemplate := set.meshTemplates[meshInstance.mesh]
            // fmt.println("Drawing mesh", mesh, "with material", mesh.material)
            wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, meshGroup.bindGroup, []u32{u32(i)*meshGroup.uniformStride});
            wgpu.RenderPassEncoderSetVertexBuffer(render_pass_encoder, 0, meshTemplate.vertBuffer, 0, u64(len(meshTemplate.vertices)*size_of(Vertex)))
            wgpu.RenderPassEncoderSetIndexBuffer(render_pass_encoder, meshTemplate.indexBuffer, wgpu.IndexFormat.Uint32, 0, u64(len(meshTemplate.indices)*size_of(u32)))
            wgpu.RenderPassEncoderDrawIndexed(render_pass_encoder, u32(len(meshTemplate.indices)), 1, 0, 0, 0)

            // Writinng the updated uniform data is likely frame(s) behind
            wgpu.QueueWriteBuffer(set.owningState.queue, meshGroup.uniformBuffer, u64(u32(i)*meshGroup.uniformStride), &UniformData{
                time,
                viewProjection * meshInstance.transform,
            }, size_of(UniformData))
        }
        wgpu.RenderPassEncoderEnd(render_pass_encoder)
    }
}