struct VertexInput {
    @builtin(vertex_index) in_vertex_index: u32,
    @location(0) worldPos: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>
}

struct Uniform {
    time: f32,
    objectTransform: mat4x4<f32>
}

@group(0) @binding(0) var<uniform> uniformData: Uniform;
@group(0) @binding(1) var tex: texture_2d<f32>;

@vertex
fn vs_main(in: VertexInput) -> VertexOutput
{
    var out: VertexOutput;
    let fullTransform = uniformData.objectTransform;
    let val = mix(vec3f(in.uv, 0), in.worldPos, uniformData.time);

    out.clip_pos = vec4<f32>((fullTransform*vec4f(val, 1)).xyz, 1.0);
    out.clip_pos.z = out.clip_pos.z * 0.5 + 0.5;
    out.normal = in.normal;
    out.uv = in.uv.xy;
    return out;
}

struct VertexOutput {
    @builtin(position) clip_pos: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) uv: vec2<f32>,
};

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    var diffuse = textureLoad(tex, vec2i(in.uv*vec2f(textureDimensions(tex))), 0);
    let lightDir = normalize(vec3f(0.5, 0.5, 1));
    let normal = normalize(in.normal);
    let NdotL = max(dot(normal, lightDir), 0.2);
    let color = diffuse * NdotL;
    return vec4<f32>(color.rgb, 1.0);
}