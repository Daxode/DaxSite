package renderer;

import "vendor:wgpu"
import "core:math/linalg"

MaterialTemplate :: struct($TVert, $TUniform: typeid) {
    shader: wgpu.ShaderModule,
    pipeline: wgpu.RenderPipeline,
    bindGroupLayout: wgpu.BindGroupLayout,
}

Vertex :: struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
}

Mat4x4 :: matrix[4, 4]f32;

UniformData :: struct #align(16) {
    time: f32,
    objectTransform: Mat4x4,
}

Mesh :: struct($TVert: typeid, $TUniform: typeid) {
    vertices: []TVert,
    indices: []u32,
    vertBuffer: wgpu.Buffer,
    indexBuffer: wgpu.Buffer,
    
    material: ^MaterialTemplate(TVert, TUniform),
}

MeshGroup :: struct($TVert: typeid, $TUniform: typeid) {
    meshes: [dynamic]^Mesh(TVert, TUniform),
    bindGroup: wgpu.BindGroup,
    uniformBuffer: wgpu.Buffer,
    uniformStride: u32,
}