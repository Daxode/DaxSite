package renderer

import "core:fmt"
import "vendor:wgpu"
import "core:strings"
import "vendor:microui"

UIVertex :: struct {
    vertex: [2]f32,
    uv: [2]f32,
    color: [4]f32,
}

ScreenParams:: [2]f32

createUIMaterialTemplate :: proc(device: wgpu.Device) -> MaterialTemplate(UIVertex, ScreenParams) {
    shaderCode : cstring = #load("quad.wgsl")

    result := MaterialTemplate(UIVertex, ScreenParams){};
    result.shader = wgpu.DeviceCreateShaderModule(device, &{
        nextInChain = &wgpu.ShaderModuleWGSLDescriptor{
            sType = .ShaderModuleWGSLDescriptor,
            code  = shaderCode,
        },
    })

    // Create bind group layout
    binding_group_entries := [?]wgpu.BindGroupLayoutEntry{
        {
            binding = 0,
            visibility = {.Vertex},
            buffer = wgpu.BufferBindingLayout{
                type = .Uniform,
                minBindingSize = size_of(ScreenParams),
            }
        },
        {
            binding = 1,
            visibility = {.Fragment},
            texture = wgpu.TextureBindingLayout{
                sampleType = .Float,
                viewDimension = ._2D,
            }
        },
        {
            binding = 2,
            visibility = {.Fragment},
            sampler = wgpu.SamplerBindingLayout{
                type = .Filtering,
            }
        }
    }

    result.bindGroupLayout = wgpu.DeviceCreateBindGroupLayout(device, &wgpu.BindGroupLayoutDescriptor{
        label = "Material Bind Group Layout",
        entries = transmute([^]wgpu.BindGroupLayoutEntry)&binding_group_entries,
        entryCount = len(binding_group_entries),
    })

    attribs := [dynamic]wgpu.VertexAttribute{
        {
            format = .Float32x2,
            offset = 0,
            shaderLocation = 0,
        },
        {
            format = .Float32x2,
            offset = 2 * size_of(f32),
            shaderLocation = 1,
        },
        {
            format = .Float32x4,
            offset = 4 * size_of(f32),
            shaderLocation = 2,
        }
    }

    vertexBufferLayout := wgpu.VertexBufferLayout {
        arrayStride = size_of(UIVertex),
        stepMode = .Vertex,
        attributes = raw_data(attribs),
        attributeCount = len(attribs),
    }
    
    pipelineLayout := wgpu.DeviceCreatePipelineLayout(device, &wgpu.PipelineLayoutDescriptor{
        bindGroupLayouts = &result.bindGroupLayout,
        bindGroupLayoutCount = 1,
    })
    defer wgpu.PipelineLayoutRelease(pipelineLayout);
    blendState := wgpu.BlendState{
        alpha = wgpu.BlendComponent{
            srcFactor = .SrcAlpha,
            dstFactor = .OneMinusSrcAlpha,
            operation = .Add,
        },
        color = wgpu.BlendComponent{
            srcFactor = .SrcAlpha,
            dstFactor = .OneMinusSrcAlpha,
            operation = .Add,
        },
    }

    result.pipeline = wgpu.DeviceCreateRenderPipeline(device, &wgpu.RenderPipelineDescriptor{
        layout = pipelineLayout,
        vertex = wgpu.VertexState {
            module     = result.shader,
            entryPoint = "vs_main",
            bufferCount = 1,
            buffers    = &vertexBufferLayout,
        },
        fragment = &wgpu.FragmentState{
            module      = result.shader,
            entryPoint  = "fs_main",
            targetCount = 1,
            targets     = &wgpu.ColorTargetState{
                format    = .BGRA8Unorm,
                writeMask = wgpu.ColorWriteMaskFlags_All,
                blend = &blendState,
            },
        },
        primitive = wgpu.PrimitiveState{
            topology = .TriangleList,
            cullMode = .None,
            frontFace = .CW,
        },
        multisample = {
            count = 1,
            mask  = 0xFFFFFFFF,
        },
        // depthStencil = &wgpu.DepthStencilState{
        //     format = .Depth24Plus,
        //     depthWriteEnabled = true,
        //     depthCompare = .Less,
        //     stencilReadMask = 0,
        //     stencilWriteMask = 0,
        //     stencilFront = wgpu.StencilFaceState{
        //         compare = .Always,
        //     },
        //     stencilBack = wgpu.StencilFaceState{
        //         compare = .Always,
        //     }
        // },
    })
    
    return result;
}

createUIMeshTemplate :: proc(device: wgpu.Device) -> MeshTemplate(UIVertex, ScreenParams) {
    result := MeshTemplate(UIVertex, ScreenParams){};
    start_size :: 8192;

    result.vertBuffer = wgpu.DeviceCreateBuffer(device, &{
        label            = "Vertex Buffer",
        usage            = {.Vertex, .CopyDst},
        size             = u64(start_size * size_of(UIVertex)),
        mappedAtCreation = false,
    })

    result.indexBuffer = wgpu.DeviceCreateBuffer(device, &{
        label            = "Index Buffer",
        usage            = {.Index, .CopyDst},
        size             = u64(start_size * size_of(u32)),
        mappedAtCreation = false,
    })

    return result;
}

DrawInfo :: struct {
    meshTemplate: MeshTemplate(UIVertex, ScreenParams),
    bindGroup: wgpu.BindGroup,
    uniformBuffer: wgpu.Buffer,
    uniformStride: u32,
    materialTemplate: MaterialTemplate(UIVertex, ScreenParams),
    texture: Texture,

}

DrawUI:: proc(
    device: wgpu.Device, queue: wgpu.Queue, 
    drawInfo: ^DrawInfo, windowSize: [2]f32,
    uiCtx: ^microui.Context, command_buffer: ^CommandBuffer) 
{
    // Set pipeline and buffers
    render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
        command_buffer.encoder, &wgpu.RenderPassDescriptor{
            colorAttachmentCount = 1,
            colorAttachments     = &wgpu.RenderPassColorAttachment{
                view       = command_buffer.frame,
                loadOp     = .Load,
                storeOp    = .Store,
                clearValue = wgpu.Color{0.0, 0.0, 0.0, 1.0},
            },
        })

    defer wgpu.RenderPassEncoderRelease(render_pass_encoder)
    wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, drawInfo.materialTemplate.pipeline)

    if drawInfo.uniformBuffer == nil {
        drawInfo.uniformStride = max(size_of(ScreenParams), 256)
        drawInfo.uniformBuffer = wgpu.DeviceCreateBuffer(device, &wgpu.BufferDescriptor{
            label = "Uniform Buffer",
            size = u64(drawInfo.uniformStride),
            usage = {.Uniform, .CopyDst},
            mappedAtCreation = false
        });
    }

    if drawInfo.texture.texture == nil {
        drawInfo.texture = createAtlasTexture(device, queue)
    }

    if drawInfo.bindGroup == nil {
        group_entries := [?]wgpu.BindGroupEntry{
            {
                binding = 0,
                size = u64(drawInfo.uniformStride),
                buffer = drawInfo.uniformBuffer,
            },
            {
                binding = 1,
                textureView = drawInfo.texture.view,
            },
            {
                binding = 2,
                sampler = drawInfo.texture.sampler,
            }
        };
        
        drawInfo.bindGroup = wgpu.DeviceCreateBindGroup(device, &wgpu.BindGroupDescriptor{
            label = "Default Material Bind Group",
            layout = drawInfo.materialTemplate.bindGroupLayout,
            entries = transmute([^]wgpu.BindGroupEntry)&group_entries,
            entryCount = len(group_entries),
        });
    }
    screenParams := ScreenParams(windowSize)
    wgpu.QueueWriteBuffer(queue, drawInfo.uniformBuffer, 0, &screenParams, size_of(ScreenParams))
    wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, drawInfo.bindGroup);

    // for meshInstanceIndex, i in meshGroup.meshes {
    //     meshInstance := set.meshInstances[meshInstanceIndex]
    //     meshTemplate := set.meshTemplates[meshInstance.mesh]
    //     // fmt.println("Drawing mesh", mesh, "with material", mesh.material)
    //     wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, meshGroup.bindGroup, []u32{u32(i)*meshGroup.uniformStride});
    //     wgpu.RenderPassEncoderSetVertexBuffer(render_pass_encoder, 0, meshTemplate.vertBuffer, 0, u64(len(meshTemplate.vertices)*size_of(Vertex)))
    //     wgpu.RenderPassEncoderSetIndexBuffer(render_pass_encoder, meshTemplate.indexBuffer, wgpu.IndexFormat.Uint32, 0, u64(len(meshTemplate.indices)*size_of(u32)))
    //     wgpu.RenderPassEncoderDrawIndexed(render_pass_encoder, u32(len(meshTemplate.indices)), 1, 0, 0, 0)

    //     // Writinng the updated uniform data is likely frame(s) behind
    //     wgpu.QueueWriteBuffer(set.owningState.queue, meshGroup.uniformBuffer, u64(u32(i)*meshGroup.uniformStride), &UniformData{
    //         time,
    //         viewProjection * meshInstance.transform,
    //     }, size_of(UniformData))
    // }
    
    
    // Fill the vertex buffer
    // fmt.printfln("Draw commands:")
    verts := make([dynamic]UIVertex, 0, 1024)
    indices := make([dynamic]u32, 0, 1024)
    quadsDrawn := make([dynamic]u16)
    cmdIter: ^microui.Command
    for cmd_var in microui.next_command_iterator(uiCtx, &cmdIter) {
        switch cmd in cmd_var {
            case ^microui.Command_Jump:
            case ^microui.Command_Clip:
                
            case ^microui.Command_Rect:
                appendQuadInPixels(&verts, &indices, [4]f32{f32(cmd.rect.x), f32(cmd.rect.y), f32(cmd.rect.w), f32(cmd.rect.h)}, colorToVec4f(cmd.color))
                append(&quadsDrawn, 1)
            case ^microui.Command_Text:
                quadsDrawnCount := 0
                dst := [4]f32{f32(cmd.pos.x), f32(cmd.pos.y), 0, 0}
                for ch in cmd.str {
                    if ch&0xc0 != 0x80 {
                        r := min(int(ch), 127)
                        src := microui.default_atlas[microui.DEFAULT_ATLAS_FONT + r]
                        srcVec4f := [4]f32{f32(src.x), f32(src.y), f32(src.w), f32(src.h)}
                        appendTextureInPixels(&verts, &indices, &dst, srcVec4f, microui.DEFAULT_ATLAS_WIDTH, microui.DEFAULT_ATLAS_HEIGHT, colorToVec4f(cmd.color))
                        dst.x += dst.z
                        // fmt.printfln("Text", ch, src, dst)
                        quadsDrawnCount += 1
                    }
                }
                append(&quadsDrawn, u16(quadsDrawnCount))
            case ^microui.Command_Icon:
                src := microui.default_atlas[cmd.id]
                srcVec4f := [4]f32{f32(src.x), f32(src.y), f32(src.w), f32(src.h)}
                x := f32(cmd.rect.x) + (f32(cmd.rect.w) - f32(src.w))/2
                y := f32(cmd.rect.y) + (f32(cmd.rect.h) - f32(src.h))/2
                appendTextureInPixels(&verts, &indices, &[4]f32{x, y, 0, 0}, srcVec4f, microui.DEFAULT_ATLAS_WIDTH, microui.DEFAULT_ATLAS_HEIGHT, colorToVec4f(cmd.color))
                append(&quadsDrawn, 1)
        }
    }
    if len(verts) == 0 || len(indices) == 0 {
        return
    }

    wgpu.QueueWriteBuffer(queue, drawInfo.meshTemplate.vertBuffer, 0, raw_data(verts), len(verts)*size_of(UIVertex))
    wgpu.QueueWriteBuffer(queue, drawInfo.meshTemplate.indexBuffer, 0, raw_data(indices), len(indices)*size_of(u32))
    wgpu.RenderPassEncoderSetIndexBuffer(render_pass_encoder, drawInfo.meshTemplate.indexBuffer, wgpu.IndexFormat.Uint32, 0, u64(len(indices)*size_of(u32)))
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass_encoder, 0, drawInfo.meshTemplate.vertBuffer, 0, u64(len(verts)*size_of(UIVertex)))
    
    cmdIter = nil
    currentOffset : u16 = 0
    currentIndex := 0
    for cmd_var in microui.next_command_iterator(uiCtx, &cmdIter) {
        switch cmd in cmd_var {
            case ^microui.Command_Jump:
                unreachable()
            case ^microui.Command_Clip:
                width := u32(cmd.rect.w)
                width = clamp(width, 0, u32(windowSize.x))
                height := u32(cmd.rect.h)
                height = clamp(height, 0, u32(windowSize.y))

                x := u32(cmd.rect.x) 
                x = clamp(x, 0, u32(windowSize.x)-width)
                y := u32(cmd.rect.y)
                y = clamp(y, 0, u32(windowSize.y)-height)
                wgpu.RenderPassEncoderSetScissorRect(render_pass_encoder, x, y, width, height)
                // fmt.println("Clip", cmd, x, y, width, height)
            case ^microui.Command_Rect:
                wgpu.RenderPassEncoderDrawIndexed(render_pass_encoder, 6, 1, u32(currentOffset*6), 0, 0)
                currentOffset += quadsDrawn[currentIndex]
                currentIndex += 1
                // fmt.println("Rect", cmd, currentOffset, currentIndex)
            case ^microui.Command_Text:
                // fmt.println("Text", cmd)
                quadsDrawnCount := quadsDrawn[currentIndex]
                wgpu.RenderPassEncoderDrawIndexed(render_pass_encoder, 6*u32(quadsDrawnCount), 1, u32(currentOffset*6), 0, 0)
                currentOffset += quadsDrawnCount
                currentIndex += 1
                // fmt.println("Text", currentIndex, currentOffset, quadsDrawnCount)
            case ^microui.Command_Icon:
                // fmt.println("Icon", cmd)
                wgpu.RenderPassEncoderDrawIndexed(render_pass_encoder, 6, 1, u32(currentOffset*6), 0, 0)
                currentOffset += 1
                currentIndex += 1
        }
    }
    wgpu.RenderPassEncoderEnd(render_pass_encoder)
}


colorToVec4f :: proc(color: microui.Color) -> [4]f32 {
    return [4]f32{f32(color.r)/255.0, f32(color.g)/255.0, f32(color.b)/255.0, f32(color.a)/255.0}
}

ui_text_width :: proc(font: microui.Font, str: string) -> i32 {
    return microui.default_atlas_text_width(font, str)
}
ui_text_height :: proc(font: microui.Font) -> i32 {
    return microui.default_atlas_text_height(font)
}

@private
appendTextureInPixels :: proc(vertices: ^[dynamic]UIVertex, indices: ^[dynamic]u32, dst: ^[4]f32,  src: [4]f32, uvWidth: f32, uvHeight: f32, color: [4]f32 = {1.0, 1.0, 1.0, 1.0}) {
    dst.z = src.z // width
    dst.w = src.w // height

    // Append the vertices
    append(vertices, UIVertex{
        vertex = [2]f32{dst.x, dst.y},
        uv = [2]f32{src.x/uvWidth, src.y/uvHeight},
        color = color,
    })
    append(vertices, UIVertex{
        vertex = [2]f32{dst.x+dst.z, dst.y},
        uv = [2]f32{(src.x+src.z)/uvWidth, src.y/uvHeight},
        color = color,
    })
    append(vertices, UIVertex{
        vertex = [2]f32{dst.x+dst.z, dst.y+dst.w},
        uv = [2]f32{(src.x+src.z)/uvWidth, (src.y+src.w)/uvHeight},
        color = color,
    })
    append(vertices, UIVertex{
        vertex = [2]f32{dst.x, dst.y+dst.w},
        uv = [2]f32{src.x/uvWidth, (src.y+src.w)/uvHeight},
        color = color,
    })

    // Append the indices
    append(indices, u32(len(vertices)-4))
    append(indices, u32(len(vertices)-3))
    append(indices, u32(len(vertices)-2))
    append(indices, u32(len(vertices)-4))
    append(indices, u32(len(vertices)-2))
    append(indices, u32(len(vertices)-1))
}

@private
appendQuadInPixels :: proc(vertices: ^[dynamic]UIVertex, indices: ^[dynamic]u32, dst: [4]f32, color: [4]f32 = {1.0, 1.0, 1.0, 1.0}) {
    uvLocationForWhite :: [2]f32{0.95, 0.95}
    // Append the vertices
    append(vertices, UIVertex{
        vertex = [2]f32{dst.x, dst.y},
        uv = uvLocationForWhite,
        color = color,
    })
    append(vertices, UIVertex{
        vertex = [2]f32{dst.x+dst.z, dst.y},
        uv = uvLocationForWhite,
        color = color,
    })
    append(vertices, UIVertex{
        vertex = [2]f32{dst.x+dst.z, dst.y+dst.w},
        uv = uvLocationForWhite,
        color = color,
    })
    append(vertices, UIVertex{
        vertex = [2]f32{dst.x, dst.y+dst.w},
        uv = uvLocationForWhite,
        color = color,
    })

    // Append the indices
    append(indices, u32(len(vertices)-4))
    append(indices, u32(len(vertices)-3))
    append(indices, u32(len(vertices)-2))
    append(indices, u32(len(vertices)-4))
    append(indices, u32(len(vertices)-2))
    append(indices, u32(len(vertices)-1))
}

@(private)
createAtlasTexture :: proc(device: wgpu.Device, queue: wgpu.Queue) -> Texture {
    result := Texture{}

    // Create the texture
    texture_desc := wgpu.TextureDescriptor{
        label = "Atlas Texture",
        size = wgpu.Extent3D{
            width = microui.DEFAULT_ATLAS_WIDTH,
            height = microui.DEFAULT_ATLAS_HEIGHT,
            depthOrArrayLayers = 1,
        },
        mipLevelCount = 1,
        sampleCount = 1,
        dimension = ._2D,
        format = .RGBA8Unorm,
        usage = {.TextureBinding, .CopyDst},
    }
    result.texture = wgpu.DeviceCreateTexture(device, &texture_desc)

    // Create the view and sampler
    result.view = wgpu.TextureCreateView(result.texture, &wgpu.TextureViewDescriptor{
        label = "Atlas Texture View",
        format = .RGBA8Unorm,
        dimension = ._2D,
        aspect = .All,
        baseMipLevel = 0,
        mipLevelCount = 1,
        baseArrayLayer = 0,
        arrayLayerCount = 1,
    })

    result.sampler = wgpu.DeviceCreateSampler(device, &wgpu.SamplerDescriptor{
        label = "Atlas Sampler",
        addressModeU = .Repeat,
        addressModeV = .Repeat,
        addressModeW = .Repeat,
        magFilter = .Linear,
        minFilter = .Linear,
        mipmapFilter = .Linear,
        lodMinClamp = 0.0,
        lodMaxClamp = 0.0,
        maxAnisotropy = 1,
    })


    // Copy the atlas data
    data := make([dynamic]u8, microui.DEFAULT_ATLAS_WIDTH*microui.DEFAULT_ATLAS_HEIGHT*4)
    for alpha, i in microui.default_atlas_alpha {
        x := i % microui.DEFAULT_ATLAS_WIDTH
        y := i / microui.DEFAULT_ATLAS_WIDTH
        color := [4]u8{255, 255, 255, alpha}
        if x >=120 && y >= 120 {
            color = [4]u8{255, 255, 255, 255}
        }

        (transmute(^[4]u8)&data[i*4])^ = color
    }
    dest := wgpu.ImageCopyTexture{
        texture = result.texture,
        mipLevel = 0,
        origin = wgpu.Origin3D{
            x = 0,
            y = 0,
            z = 0,
        },
        aspect = .All
    }
    source := wgpu.TextureDataLayout{
        offset = 0,
        bytesPerRow = u32(4*microui.DEFAULT_ATLAS_WIDTH),
        rowsPerImage = u32(microui.DEFAULT_ATLAS_HEIGHT),
    }
    wgpu.QueueWriteTexture(queue, &dest, raw_data(data), len(data), &source, &texture_desc.size)

    return result
}