package renderer;

import "vendor:wgpu"
import "core:math/linalg"

// Template for a material
MaterialTemplate :: struct($TVert, $TUniform: typeid) {
    shader: wgpu.ShaderModule,
    pipeline: wgpu.RenderPipeline,
    bindGroupLayout: wgpu.BindGroupLayout,
}

// Instance of a material
RenderInstance :: struct($TVert: typeid, $TUniform: typeid) {
    materialTemplate: MaterialTemplate(TVert, TUniform),
    textures: [4]TextureIndex,
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

// Template for a mesh
MeshTemplate :: struct($TVert: typeid, $TUniform: typeid) {
    vertices: []TVert,
    indices: []u32,
    vertBuffer: wgpu.Buffer,
    indexBuffer: wgpu.Buffer,
}

// Instance of a mesh
MeshInstance :: struct($TVert: typeid, $TUniform: typeid) {
    mesh: MeshTemplateIndex,
    renderInstanceIndex: RenderInstanceIndex,
    transform: linalg.Matrix4x4f32,
}

// MeshGroup is a collection of meshes instances that share the same material
MeshGroup :: struct($TVert: typeid, $TUniform: typeid) {
    meshes: [dynamic]MeshInstanceIndex,
    bindGroup: wgpu.BindGroup,
    uniformBuffer: wgpu.Buffer,
    uniformStride: u32,
}

// Texture
Texture :: struct {
    texture: wgpu.Texture,
    view: wgpu.TextureView,
    sampler: wgpu.Sampler,
}

TextureIndex :: distinct i16
MeshInstanceIndex :: distinct u32
MeshTemplateIndex :: distinct u16
RenderInstanceIndex :: distinct u16

// RendererSet is a collection of meshes and materials that can be rendered together
RendererSet :: struct($TVert: typeid, $TUniform: typeid) {
    textures:           [dynamic]Texture,
    meshInstances:      [dynamic]MeshInstance(TVert, TUniform),
    meshTemplates:      [dynamic]MeshTemplate(TVert, TUniform),
    renderInstances:    [dynamic]RenderInstance(TVert, TUniform),
    materialToMeshes:   map[RenderInstanceIndex]MeshGroup(TVert, TUniform),
    owningState:        ^RenderManagerState,
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
    rendererSet : [dynamic]RendererSet(Vertex, UniformData), // Later render sets can be merged 
}

CommandBuffer :: struct {
    encoder: wgpu.CommandEncoder,
    surfaceTexture: wgpu.SurfaceTexture,
    frame: wgpu.TextureView,
}