package renderer;

import "vendor:wgpu"
import "core:math/linalg"

MaterialTemplate :: struct($TVert, $TUniform: typeid) {
    shader: wgpu.ShaderModule,
    pipeline: wgpu.RenderPipeline,
    bindGroupLayout: wgpu.BindGroupLayout,
    texture: Maybe(Texture),
}

Vertex :: struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
}

UniformData :: struct #align(16) {
    time: f32,
    objectTransform: linalg.Matrix4x4f32,
}

Mesh :: struct($TVert: typeid, $TUniform: typeid) {
    vertices: []TVert,
    indices: []u32,
    vertBuffer: wgpu.Buffer,
    indexBuffer: wgpu.Buffer,
    
    material: ^RenderInstance(TVert, TUniform),
}

RenderInstance :: struct($TVert: typeid, $TUniform: typeid) {
    materialTemplate: MaterialTemplate(TVert, TUniform),
    textures: [4]Texture,
}

MeshGroup :: struct($TVert: typeid, $TUniform: typeid) {
    meshes: [dynamic]^Mesh(TVert, TUniform),
    bindGroup: wgpu.BindGroup,
    uniformBuffer: wgpu.Buffer,
    uniformStride: u32,
}

RendererSet :: struct($TVert: typeid, $TUniform: typeid) {
    meshes:          [dynamic]Mesh(TVert, TUniform),
    material:        [dynamic]RenderInstance(TVert, TUniform),
    materialToMeshes: map[^RenderInstance(TVert, TUniform)]MeshGroup(TVert, TUniform),
}


RenderManagerState :: struct {
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
    
    // Meshes and materials
    using rendererSet : RendererSet(Vertex, UniformData), // Later render sets can be merged 
}


Texture :: struct {
    texture: wgpu.Texture,
    view: wgpu.TextureView,
    sampler: wgpu.Sampler,
}