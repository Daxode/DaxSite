package renderer;

import "vendor:wgpu"
import "core:strings"
import "core:fmt"
import rt "base:runtime"


// Todo: replace with a addRenderInstance function that returns a MaterialTemplateIndex
createDefaultMaterialTemplate :: proc(device: wgpu.Device) -> MaterialTemplate(Vertex, UniformData) {
    shader :: #load("triangle.wgsl");
    return createMaterialTemplate(device, strings.unsafe_string_to_cstring(strings.clone_from_bytes(shader)), Vertex, UniformData);
}

// Todo: replace with a addMaterialTemplate function that returns a MaterialTemplateIndex
createMaterialTemplate :: proc(device: wgpu.Device, shaderCode: cstring, $TVert, $TUniform: typeid) -> MaterialTemplate(TVert, TUniform) {
    result := MaterialTemplate(TVert, TUniform){};
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
                hasDynamicOffset = true,
                minBindingSize = size_of(TUniform),
            }
        },
        {
            binding = 1,
            visibility = {.Fragment},
            texture = wgpu.TextureBindingLayout{
                sampleType = .Float,
                viewDimension = ._2D,
            }
        }
    }

    result.bindGroupLayout = wgpu.DeviceCreateBindGroupLayout(device, &wgpu.BindGroupLayoutDescriptor{
        label = "Material Bind Group Layout",
        entries = transmute([^]wgpu.BindGroupLayoutEntry)&binding_group_entries,
        entryCount = len(binding_group_entries),
    })

    // Create attribute layout from the vertex type
    assert(TVert == Vertex, "Only Vertex type is supported for now");
    attribs := [dynamic]wgpu.VertexAttribute{
        {
            format = .Float32x3,
            offset = 0,
            shaderLocation = 0,
        },
        {
            format = .Float32x3,
            offset = 3 * size_of(f32),
            shaderLocation = 1,
        },
        {
            format = .Float32x2,
            offset = 6 * size_of(f32),
            shaderLocation = 2,
        }
    }

    vertexBufferLayout := wgpu.VertexBufferLayout {
        arrayStride = size_of(TVert),
        stepMode = .Vertex,
        attributes = raw_data(attribs),
        attributeCount = len(attribs),
    }
    
    pipelineLayout := wgpu.DeviceCreatePipelineLayout(device, &wgpu.PipelineLayoutDescriptor{
        bindGroupLayouts = &result.bindGroupLayout,
        bindGroupLayoutCount = 1,
    })
    defer wgpu.PipelineLayoutRelease(pipelineLayout);

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
            },
        },
        primitive = wgpu.PrimitiveState{
            topology = .TriangleList,
            cullMode = .Back,
            frontFace = .CW,
        },
        multisample = {
            count = 1,
            mask  = 0xFFFFFFFF,
        },
        depthStencil = &wgpu.DepthStencilState{
            format = .Depth24Plus,
            depthWriteEnabled = true,
            depthCompare = .Less,
            stencilReadMask = 0,
            stencilWriteMask = 0,
            stencilFront = wgpu.StencilFaceState{
                compare = .Always,
            },
            stencilBack = wgpu.StencilFaceState{
                compare = .Always,
            }
        },
    })
    
    return result;
}

// Todo: replace with a addMeshTemplate function that returns an index
createMeshTemplate :: proc(device: wgpu.Device, verts: []Vertex, indices: []u32, $TVert, $TUniform: typeid) -> MeshTemplate(TVert, TUniform) {
    result := MeshTemplate(TVert, TUniform){};

    result.vertBuffer = wgpu.DeviceCreateBuffer(device, &{
        label            = "Vertex Buffer",
        usage            = {.Vertex, .CopyDst},
        size             = u64(len(verts) * size_of(TVert)),
        mappedAtCreation = true,
    })
    destVerts := wgpu.BufferGetMappedRangeSlice(result.vertBuffer, 0, Vertex, len(verts))
    copy(destVerts, verts)
    wgpu.BufferUnmap(result.vertBuffer)

    result.indexBuffer = wgpu.DeviceCreateBuffer(device, &{
        label            = "Index Buffer",
        usage            = {.Index, .CopyDst},
        size             = u64(len(indices) * size_of(u32)),
        mappedAtCreation = true,
    })
    destIndices := wgpu.BufferGetMappedRangeSlice(result.indexBuffer, 0, u32, len(indices))
    copy(destIndices, indices)
    wgpu.BufferUnmap(result.indexBuffer)

    result.vertices = verts;
    result.indices = indices;

    return result;
}

ReleaseMeshTemplate :: proc(set: ^RendererSet($TVert, $TUniformData), meshTemplateIndex: MeshTemplateIndex) {
    meshTemplate := set.meshTemplates[meshTemplateIndex];
    wgpu.BufferRelease(meshTemplate.vertBuffer);
    wgpu.BufferRelease(meshTemplate.indexBuffer);
    // should probably create a meshTemplateFreeList
}

ReleaseRenderInstance :: proc(set: ^RendererSet($TVert, $TUniformData), renderInstanceIndex: RenderInstanceIndex) {
    renderInstance := set.renderInstances[renderInstanceIndex];
    wgpu.ShaderModuleRelease(renderInstance.materialTemplate.shader);
    wgpu.RenderPipelineRelease(renderInstance.materialTemplate.pipeline);
    wgpu.BindGroupLayoutRelease(renderInstance.materialTemplate.bindGroupLayout);
    // should probably create a materialTemplateFreeList
}