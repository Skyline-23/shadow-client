#include <metal_stdlib>
using namespace metal;

struct ShadowYUVVertex {
    float2 position;
    float2 texCoord;
};

struct ShadowYUVVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct ShadowYUVCSCParameters {
    float3 row0;
    float3 row1;
    float3 row2;
    float3 offsets;
    float2 chromaOffset;
    float bitnessScaleFactor;
};

vertex ShadowYUVVertexOut shadowYUVVertex(
    const device ShadowYUVVertex* vertices [[buffer(0)]],
    uint vertexID [[vertex_id]]
) {
    ShadowYUVVertexOut out;
    out.position = float4(vertices[vertexID].position, 0.0, 1.0);
    out.texCoord = vertices[vertexID].texCoord;
    return out;
}

fragment half4 shadowYUVBiplanarFragment(
    ShadowYUVVertexOut in [[stage_in]],
    texture2d<float, access::sample> lumaTexture [[texture(0)]],
    texture2d<float, access::sample> chromaTexture [[texture(1)]],
    constant ShadowYUVCSCParameters& params [[buffer(0)]]
) {
    constexpr sampler textureSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    const float2 chromaOffset = params.chromaOffset / float2(lumaTexture.get_width(), lumaTexture.get_height());
    float3 yuv = float3(
        lumaTexture.sample(textureSampler, in.texCoord).r,
        chromaTexture.sample(textureSampler, in.texCoord + chromaOffset).rg
    );
    yuv *= params.bitnessScaleFactor;
    yuv -= params.offsets;

    const float3 rgb = float3(
        dot(params.row0, yuv),
        dot(params.row1, yuv),
        dot(params.row2, yuv)
    );

    return half4(half3(rgb), half(1.0));
}
