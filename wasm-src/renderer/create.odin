package renderer;

import "vendor:wgpu"
import "core:strings"
import "core:fmt"
import rt "base:runtime"

createDefaultMaterialTemplate :: proc(device: wgpu.Device) -> MaterialTemplate(Vertex, UniformData) {
    shader :: #load("triangle.wgsl");
    return createMaterialTemplate(device, strings.unsafe_string_to_cstring(strings.clone_from_bytes(shader)), Vertex, UniformData);
}

createMaterialTemplate :: proc(device: wgpu.Device, shaderCode: cstring, $TVert, $TUniform: typeid) -> MaterialTemplate(TVert, TUniform) {
    result := MaterialTemplate(TVert, TUniform){};
    result.shader = wgpu.DeviceCreateShaderModule(device, &{
        nextInChain = &wgpu.ShaderModuleWGSLDescriptor{
            sType = .ShaderModuleWGSLDescriptor,
            code  = shaderCode,
        },
    })

    // Create bind group layout
    result.bindGroupLayout = wgpu.DeviceCreateBindGroupLayout(device, &wgpu.BindGroupLayoutDescriptor{
        label = "Material Bind Group Layout",
        entries = &wgpu.BindGroupLayoutEntry{
            binding = 0,
            visibility = {.Vertex},
            buffer = wgpu.BufferBindingLayout{
                type = .Uniform,
                hasDynamicOffset = true,
                minBindingSize = size_of(TUniform),
            }
        },
        entryCount = 1,
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
        },
    })
    
    return result;
}

createMesh :: proc(device: wgpu.Device, verts: []Vertex, indices: []u32, material: ^MaterialTemplate($TVert, $TUniform)) -> Mesh(TVert, TUniform) {
    result := Mesh(TVert, TUniform){};

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

    result.material = material;
    result.vertices = verts;
    result.indices = indices;

    return result;
}

releaseMesh :: proc(mesh: ^Mesh($TVert, $TUniform)) {
    wgpu.BufferRelease(mesh.vertBuffer);
    wgpu.BufferRelease(mesh.indexBuffer);
}

releaseMaterialTemplate :: proc(material: ^MaterialTemplate($TVert, $TUniform)) {
    wgpu.ShaderModuleRelease(material.shader);
    wgpu.RenderPipelineRelease(material.pipeline);
    wgpu.BindGroupLayoutRelease(material.bindGroupLayout);
}