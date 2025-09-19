//
//  PointCloudShaders.metal
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/9/25.
//

#include <metal_stdlib>
using namespace metal;

// Must match Swift's PCUniforms layout (PointCloudRenderer.PCUniforms).
struct PCUniforms {
    float4x4 viewProj;       // proj * view  (world → clip)
    float4x4 model;          // model        (camera → world at capture)
    float    basePointSize;  // pixel size at reference distance
    float    attenuateFlag;  // 1.0 => shrink with distance, 0.0 => constant size
    float2   _pad;
};

// VS output payload
struct VSOut {
    float4 position [[position]];  // clip-space position
    float4 color;
    float  pointSize [[point_size]]; // in pixels
    float  eyeZ;                      // camera-space depth (for attenuation)
};

// Vertex shader
vertex VSOut pcVertex(
    const device float3* positions   [[buffer(0)]],
    const device uchar4* colors      [[buffer(1)]],
    constant PCUniforms& uniforms    [[buffer(2)]],
    uint vid                         [[vertex_id]]
) {
    VSOut out;

    // Fetch attributes
    float3 pCam = positions[vid];           // CAMERA-relative position (Xc,Yc,Zc)
    uchar4 c    = colors[vid];              // RGBA8 color

    // Transform to world, then to clip: clip = viewProj * (model * cam)
    float4 pWorld = uniforms.model * float4(pCam, 1.0);
    float4 pClip  = uniforms.viewProj * pWorld;

    out.position = pClip;

    // Convert color to float4 [0,1]
    out.color = float4(float(c.r) / 255.0,
                       float(c.g) / 255.0,
                       float(c.b) / 255.0,
                       float(c.a) / 255.0);

    // Compute camera-space Z for size attenuation (positive forward).
    // Note: view matrix maps world→camera; since we don't have it here directly,
    // we approximate using clip.w (perspective divide) for a cheap attenuation.
    // Better: pass view matrix or eyeZ as a varying. Here we emulate via pWorld.z in view space:
    // Derivation shortcut: if you want true eye-space Z, supply (view * model) from Swift.
    // For simplicity, we use |pClip.w| as a proxy; works well enough for sprite sizing.
    float depthProxy = max(abs(pClip.w), 1e-4);

    // Base size → optionally scale with distance.
    // Tune k to taste: larger k keeps points bigger at distance.
    const float k = 1.0; // feel constant
    float sizePx = uniforms.basePointSize *
                   mix(1.0, k / depthProxy, uniforms.attenuateFlag);

    out.pointSize = max(sizePx, 1.0);
    out.eyeZ = depthProxy;
    return out;
}

// Fragment shader with circular mask
fragment float4 pcFragment(
    VSOut in [[stage_in]],
    float2 ptCoord [[point_coord]]   // (0..1) across the sprite
) {
    // Make point sprites circular: discard outside unit circle centered at (0.5,0.5).
    float2 uv = ptCoord * 2.0 - 1.0;   // map to [-1,1]
    float r2 = dot(uv, uv);
    if (r2 > 1.0) discard_fragment;

    return in.color; // unlit color
}
