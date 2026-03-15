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
    uint transferFunction;
    uint appliesToneMapToSDR;
    uint appliesGamutTransform;
    uint _padding;
    float hlgSystemGamma;
    float toneMapSourceHeadroom;
    float toneMapTargetHeadroom;
    float _padding2;
    float3 gamutRow0;
    float3 gamutRow1;
    float3 gamutRow2;
};

constant float kPQM1 = 0.1593017578125;
constant float kPQM2 = 78.84375;
constant float kPQC1 = 0.8359375;
constant float kPQC2 = 18.8515625;
constant float kPQC3 = 18.6875;
constant float kHLGA = 0.17883277;
constant float kHLGB = 0.28466892;
constant float kHLGC = 0.55991073;

float pqEOTF(float value) {
    const float normalized = max(value, 0.0);
    const float power = pow(normalized, 1.0 / kPQM2);
    const float numerator = max(power - kPQC1, 0.0);
    const float denominator = max(kPQC2 - (kPQC3 * power), 1e-6);
    return pow(numerator / denominator, 1.0 / kPQM1);
}

float hlgInverseOETF(float value) {
    const float normalized = max(value, 0.0);
    if (normalized <= 0.5) {
        return (normalized * normalized) / 3.0;
    }
    return (exp((normalized - kHLGC) / kHLGA) + kHLGB) / 12.0;
}

float3 decodeTransfer(float3 rgb, constant ShadowYUVCSCParameters& params) {
    switch (params.transferFunction) {
    case 1:
        return float3(pqEOTF(rgb.r), pqEOTF(rgb.g), pqEOTF(rgb.b));
    case 2: {
        const float3 sceneLinear = float3(
            hlgInverseOETF(rgb.r),
            hlgInverseOETF(rgb.g),
            hlgInverseOETF(rgb.b)
        );
        return pow(max(sceneLinear, 0.0), float3(params.hlgSystemGamma));
    }
    default:
        return rgb;
    }
}

float3 toneMapToSDR(float3 rgb, constant ShadowYUVCSCParameters& params) {
    const float scale = max(params.toneMapSourceHeadroom / max(params.toneMapTargetHeadroom, 1e-6), 1.0);
    const float3 scaled = max(rgb * scale, 0.0);
    return scaled / (1.0 + scaled);
}

float3 applyGamutTransform(float3 rgb, constant ShadowYUVCSCParameters& params) {
    return float3(
        dot(params.gamutRow0, rgb),
        dot(params.gamutRow1, rgb),
        dot(params.gamutRow2, rgb)
    );
}

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
    float3 processed = max(rgb, 0.0);
    processed = decodeTransfer(processed, params);
    if (params.appliesToneMapToSDR != 0) {
        processed = toneMapToSDR(processed, params);
    }
    if (params.appliesGamutTransform != 0) {
        processed = applyGamutTransform(processed, params);
    }

    return half4(half3(processed), half(1.0));
}
