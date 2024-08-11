struct VertexInput {
    @location(0) vertex: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) color: vec4<f32>,
}

@group(0) @binding(0) var<uniform> _ScreenParams: vec2<f32>;
@group(0) @binding(1) var tex: texture_2d<f32>;
@group(0) @binding(2) var textureSampler: sampler;

@vertex
fn vs_main(in: VertexInput) -> VertexOutput
{
    var out: VertexOutput;
    out.clip_pos = vec4f((in.vertex.xy/_ScreenParams)*2-1,0,1);
    out.clip_pos.y = -out.clip_pos.y;
    out.uv = in.uv;
    // out.uv.y = 1-out.uv.y;
    out.color = in.color;
    return out;
}

struct VertexOutput {
    @builtin(position) clip_pos: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
};

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    var diffuse = textureSample(tex, textureSampler, in.uv);
    //var diffuse = textureLoad(tex, vec2i(in.uv*vec2f(textureDimensions(tex))), 0);
    return vec4<f32>(diffuse.rgb*in.color.rgb, diffuse.a*in.color.a);
    // return vec4f(1,1,1,1);
}