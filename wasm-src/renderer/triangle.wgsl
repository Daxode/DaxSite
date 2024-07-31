struct VertexInput {
    @builtin(vertex_index) in_vertex_index: u32,
    @location(0) worldPos: vec3<f32>,
    @location(1) normal: vec3<f32>
}

struct Uniform {
    time: f32,
    objectTransform: mat4x4<f32>
}

@group(0) @binding(0) var<uniform> uniformData: Uniform;

@vertex
fn vs_main(in: VertexInput) -> VertexOutput
{
    var out: VertexOutput;
    let fullTransform = uniformData.objectTransform;
    out.clip_pos = vec4<f32>((fullTransform*vec4f(in.worldPos, 1)).xyz, 1.0);
    out.color = (fullTransform*vec4f(in.worldPos, 1)).xyz;
    return out;
}

struct VertexOutput {
    @builtin(position) clip_pos: vec4<f32>,
    @location(0) color: vec3<f32>,
};

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(in.color, 1.0);
}