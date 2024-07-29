struct VertexInput {
    @builtin(vertex_index) in_vertex_index: u32,
    @location(0) worldPos: vec3<f32>
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput
{
    var out: VertexOutput;
    out.clip_pos = vec4<f32>(in.worldPos.xy, 0.0, 1.0);
    out.color = vec3<f32>(in.worldPos.xy, 0.0);
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