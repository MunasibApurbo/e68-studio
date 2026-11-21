import Foundation

/// Runtime-compiled Metal Shading Language (MSL) source for hardware ray tracing,
/// Next Event Estimation with soft area lights & caustics, progressive accumulation,
/// ACES Filmic post-processing, and 1-ray BVH mouse/key click picking.
enum RTShaders {
    static let source: String = #"""
#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace metal::raytracing;

struct RTVertex {
    float px, py, pz;
    float nx, ny, nz;
    float u, v;
    float cr, cg, cb, ca;
};

struct RTSubmesh {
    uint vertexOffset;
    uint indexOffset;
    uint materialIndex;
    uint flags;
};

struct RTInstanceInfo {
    float4x4 modelToWorld;
    float4x4 prevModelToWorld;
    float4x4 normalToWorld;
    uint submeshBase;
    uint nodeTag;
    uint flags;
    uint reserved;
};

struct RTMaterialData {
    float4 baseColor;      // rgb linear albedo, w = opacity
    float4 emissionColor;  // rgb linear emission, w = scalar roughness
    float4 params;         // x = metalness, y = clearCoat, z = clearCoatRough, w = normalIntensity
    float4 optics;         // x = ior, y = subsurface, z = sheen, w = emissiveBoost
    float4 absorbColor;    // xyz = sigma_t, w = thickness
    float4 diffuseUV;      // sx, sy, tx, ty
    float4 detailUV;       // sx, sy, tx, ty
    float4 roughnessUV;    // sx, sy, tx, ty
    int4   texIndices;     // x = diffuse, y = normal, z = roughness, w = emission
    int4   extraTex;       // x = metalness, y = ao, z = matClass, w = flags
};

struct RTFrameUniforms {
    float4 camPos;
    float4 camRight;
    float4 camUp;
    float4 camForward;

    float4x4 viewToClip;
    float4x4 worldToView;
    float4x4 prevViewProj;
    float4x4 worldToKeyboard;

    uint2 renderSize;
    uint2 outputSize;
    float2 jitter;
    float2 prevJitter;

    uint frameIndex;
    uint sampleIndex;
    float accumulationBlend;
    uint maxBounces;

    float tanHalfFov;
    float aspect;
    float apertureRadius;
    float focusDistance;

    float exposureScale;
    uint renderFlags;      // bit 0 = progressive pass (skip denoiser G-buffer writes), bit 3 = live frame (steady detail), bit 4 = sun lit live, not stored
    uint isRoomScenario;
    int hdrEnvTexIndex;

    int plateGlowTexIndex;
    int monitorTexIndex;
    uint hasBgCubemap;
    uint uniformPad0;

    float4 bgColor;
    float4 fogColor;
    float4 fogParams;
    float4 plateBounds;

    float4 keyLightPosRadius;
    float4 keyLightColor;
    float4 fillLightPosRadius;
    float4 fillLightColor;

    float4 deskBulbPosRadius;
    float4 deskBulbColor;

    float4 monitorPos;
    float4 monitorU;
    float4 monitorV;
    float4 monitorColor;

    float4 underDeskPosA;
    float4 underDeskPosB;
    float4 underDeskColor;

    float4 roomLightPosRadius;
    float4 roomLightColor;

    float4 windowOrigin;   // xyz = lower corner of the window opening, w = sun-through-window mask enabled
    float4 windowU;        // xyz = unit axis along the wall, w = width
    float4 windowV;        // xyz = unit axis up the wall, w = height
    float4 groundProjection; // xyz = panorama capture point, w = its white level (0 = none)
};

struct RTTextureSlot {
    texture2d<float> tex;
};

struct PickResult {
    uint nodeTag;
    float distance;
    uint pad0;
    uint pad1;
};

struct CompositeParams {
    float progressBlend;
    float exposureScale;
    float bloomStrength;
    float vignetteStrength;
    float grainStrength;
    uint frameIndex;
    uint isProgressiveOnly;
    uint pad0;
};

// Material Class IDs matching RTMatClass
constant int MAT_STANDARD     = 0;
constant int MAT_THIN_GLASS   = 1;
constant int MAT_SOLID_GLASS  = 2;
constant int MAT_WATER        = 3;
constant int MAT_INDIGO_RESIN = 4;
constant int MAT_FOLIAGE      = 5;
constant int MAT_SCREEN       = 6;
constant int MAT_WOVEN_CLOTH  = 7;
constant int MAT_SSS_POLYMER  = 8;
constant int MAT_KEY_SKIRT    = 9;
constant int MAT_KEY_PLATE    = 10;
constant int MAT_EMISSIVE_CARD = 11;

// Samplers
constexpr sampler kRepeatSamp(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
constexpr sampler kClampSamp(filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(8));
constexpr sampler kEnvSamp(filter::linear, mip_filter::linear, s_address::repeat, t_address::clamp_to_edge);
constexpr sampler kScreenSamp(filter::linear, mip_filter::linear, address::clamp_to_edge);

constant float PI = 3.14159265359f;
constant float INV_PI = 0.31830988618f;

// MARK: - RNG & Low-Discrepancy Sampling

inline uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

inline float rand01(thread uint& state) {
    state = state * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return float((word >> 22u) ^ word) * 2.3283064365386963e-10f;
}

inline float3 hash33(float3 p3) {
    p3 = fract(p3 * float3(0.1031f, 0.1030f, 0.0973f));
    p3 += dot(p3, p3.yxz + 33.33f);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

inline float luminance(float3 c) {
    return dot(c, float3(0.2126f, 0.7152f, 0.0722f));
}

inline void makeONB(float3 n, thread float3& t, thread float3& b) {
    float signZ = (n.z >= 0.0f) ? 1.0f : -1.0f;
    float a = -1.0f / (signZ + n.z);
    float bb = n.x * n.y * a;
    t = float3(1.0f + signZ * n.x * n.x * a, signZ * bb, -signZ * n.x);
    b = float3(bb, signZ + n.y * n.y * a, -n.y);
}

inline float2 sampleDisk(float u1, float u2) {
    float r = sqrt(max(u1, 0.0f));
    float theta = 2.0f * PI * u2;
    return float2(r * cos(theta), r * sin(theta));
}

inline float3 sampleCosineHemisphere(float3 N, float u1, float u2) {
    float2 d = sampleDisk(u1, u2);
    float z = sqrt(max(0.0f, 1.0f - dot(d, d)));
    float3 T, B;
    makeONB(N, T, B);
    return normalize(T * d.x + B * d.y + N * z);
}

inline float3 sampleUniformSphere(float u1, float u2) {
    float z = 1.0f - 2.0f * u1;
    float r = sqrt(max(0.0f, 1.0f - z * z));
    float phi = 2.0f * PI * u2;
    return float3(r * cos(phi), r * sin(phi), z);
}

// MARK: - GGX Microfacet PBR & Sheen

inline float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0f - F0) * pow(saturate(1.0f - cosTheta), 5.0f);
}

inline float fresnelDielectric(float cosI, float eta) {
    float sinT2 = eta * eta * max(0.0f, 1.0f - cosI * cosI);
    if (sinT2 >= 1.0f) return 1.0f;
    float cosT = sqrt(max(0.0f, 1.0f - sinT2));
    float r0 = (1.0f - eta) / (1.0f + eta);
    r0 *= r0;
    float x = 1.0f - (eta < 1.0f ? cosI : cosT);
    return r0 + (1.0f - r0) * (x * x * x * x * x);
}

inline float D_GGX(float NdotH, float alpha) {
    float a2 = alpha * alpha;
    float denom = NdotH * NdotH * (a2 - 1.0f) + 1.0f;
    return a2 / max(PI * denom * denom, 1e-6f);
}

inline float V_SmithGGX(float NdotV, float NdotL, float alpha) {
    float a2 = alpha * alpha;
    float ggxv = NdotL * sqrt(NdotV * NdotV * (1.0f - a2) + a2);
    float ggxl = NdotV * sqrt(NdotL * NdotL * (1.0f - a2) + a2);
    return 0.5f / max(ggxv + ggxl, 1e-5f);
}

// Charlie velvet sheen NDF for woven desk mat & fabric
inline float D_Charlie(float NdotH, float roughness) {
    float invR = 1.0f / max(roughness, 0.08f);
    float cos2h = NdotH * NdotH;
    float sin2h = max(1.0f - cos2h, 1e-4f);
    return (2.0f + invR) * pow(sin2h, invR * 0.5f) / (2.0f * PI);
}

inline float3 sampleGGX_VNDF(float3 V, float3 N, float alpha, float u1, float u2) {
    float3 T, B;
    makeONB(N, T, B);
    float3 Ve = float3(dot(V, T), dot(V, B), dot(V, N));
    float3 Vh = normalize(float3(alpha * Ve.x, alpha * Ve.y, max(Ve.z, 1e-4f)));
    float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
    float3 T1 = lensq > 1e-7f ? float3(-Vh.y, Vh.x, 0.0f) * rsqrt(lensq) : float3(1, 0, 0);
    float3 T2 = cross(Vh, T1);
    float r = sqrt(max(u1, 0.0f));
    float phi = 2.0f * PI * u2;
    float t1 = r * cos(phi);
    float t2 = r * sin(phi);
    float s = 0.5f * (1.0f + Vh.z);
    t2 = (1.0f - s) * sqrt(max(0.0f, 1.0f - t1 * t1)) + s * t2;
    float3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0f, 1.0f - t1 * t1 - t2 * t2)) * Vh;
    float3 Ne = normalize(float3(alpha * Nh.x, alpha * Nh.y, max(0.0f, Nh.z)));
    return normalize(T * Ne.x + B * Ne.y + N * Ne.z);
}

inline float3 evaluateBSDF(
    float3 V,
    float3 L,
    float3 N,
    float3 albedo,
    float roughness,
    float metalness,
    float clearCoat,
    float clearCoatRough,
    float sheen,
    float subsurface,
    float dielectricF0
) {
    float NdotL = max(dot(N, L), 0.0f);
    float NdotV = max(dot(N, V), 1e-4f);
    if (NdotL <= 0.0f) {
        // Wrap subsurface bleed cleanly around keycaps / mouse / AirPods
        if (subsurface > 0.01f) {
            float wrap = saturate((dot(N, L) + subsurface) / (1.0f + subsurface));
            return albedo * (INV_PI * wrap * subsurface * 0.45f);
        }
        return float3(0.0f);
    }

    float3 hSum = V + L;
    float3 H = (dot(hSum, hSum) > 1e-8f) ? normalize(hSum) : N;
    float NdotH = max(dot(N, H), 0.0f);
    float VdotH = max(dot(V, H), 0.0f);

    float3 F0 = mix(float3(dielectricF0), albedo, metalness);
    float3 F = fresnelSchlick(VdotH, F0);
    float alpha = max(roughness * roughness, 0.002f);
    float D = D_GGX(NdotH, alpha);
    float Vis = V_SmithGGX(NdotV, NdotL, alpha);
    float3 spec = F * (D * Vis);

    float3 kD = (1.0f - F) * (1.0f - metalness);
    float wrapDiffuse = (subsurface > 0.01f)
        ? saturate((NdotL + 0.32f * subsurface) / (1.0f + 0.32f * subsurface))
        : NdotL;
    float3 diff = kD * albedo * INV_PI * (wrapDiffuse / max(NdotL, 1e-4f));

    if (clearCoat > 0.01f) {
        float ccAlpha = max(clearCoatRough * clearCoatRough, 0.001f);
        float Fc = fresnelSchlick(VdotH, float3(0.04f)).x * clearCoat;
        float Dc = D_GGX(NdotH, ccAlpha);
        float Vc = V_SmithGGX(NdotV, NdotL, ccAlpha);
        diff *= (1.0f - Fc * 0.65f);
        spec += float3(Fc * Dc * Vc);
    }

    if (sheen > 0.01f) {
        float Ds = D_Charlie(NdotH, max(roughness * 0.85f, 0.25f));
        float vs = 0.25f / max(NdotL + NdotV - NdotL * NdotV, 0.1f);
        diff += mix(albedo, float3(1.0f), 0.35f) * (sheen * Ds * vs * 0.35f);
    }

    return (diff + spec) * NdotL;
}

// MARK: - Environment & Sky Sampling

inline float3 sampleEnvEquirect(float3 dir, float lod, constant RTFrameUniforms& u, constant RTTextureSlot* texSlots) {
    if (u.hdrEnvTexIndex < 0) return u.bgColor.rgb * u.bgColor.w;
    float az = atan2(dir.x, -dir.z); // matching SceneKit HDR builder convention
    float elev = asin(clamp(dir.y, -1.0f, 1.0f));
    float2 uv = float2(az / (2.0f * PI) + 0.5f, 0.5f - elev / PI);
    float3 env = texSlots[u.hdrEnvTexIndex].tex.sample(kEnvSamp, uv, level(lod)).rgb;
    return max(env * u.bgColor.w, float3(0.0f));
}

// Crisp point stars for camera rays only (the sky map itself stays low-frequency so it lights the scene without noise).
inline float3 starField(float3 dir, float strength) {
    if (strength <= 0.001f || dir.y < -0.02f) return float3(0.0f);
    float3 p = dir * 190.0f;
    float3 cell = floor(p);
    float3 h = hash33(cell + 17.0f);
    if (h.z < 0.86f) return float3(0.0f);
    float3 starPos = cell + 0.2f + 0.6f * hash33(cell * 1.7f + 3.1f);
    float d = length(p - starPos);
    float mag = pow((h.z - 0.86f) / 0.14f, 3.0f);
    float core = smoothstep(0.16f, 0.0f, d);
    float3 tint = mix(float3(1.0f, 0.86f, 0.72f), float3(0.74f, 0.86f, 1.0f), h.x);
    float horizonFade = smoothstep(-0.02f, 0.18f, dir.y);
    return tint * (core * core * (0.4f + 5.5f * mag) * strength * horizonFade);
}

inline float3 samplePrimaryMiss(float3 dir, constant RTFrameUniforms& u, constant RTTextureSlot* texSlots, texturecube<float> bgCubemap) {
    if (u.hasBgCubemap != 0) {
        return bgCubemap.sample(kClampSamp, float3(dir.x, dir.y, -dir.z)).rgb;
    }
    if (u.isRoomScenario != 0) {
        return u.bgColor.rgb;
    }
    float3 sky = sampleEnvEquirect(dir, 0.0f, u, texSlots);
    sky += starField(dir, u.fogColor.w);
    if (u.keyLightColor.w > 0.5f) {
        // Visible sun / moon disc with a soft limb; its light reaches surfaces through next-event estimation.
        float cosR = 1.0f / sqrt(1.0f + u.keyLightPosRadius.w * u.keyLightPosRadius.w);
        float c = dot(dir, u.keyLightPosRadius.xyz);
        float disc = smoothstep(cosR - 0.000035f, cosR + 0.000010f, c);
        sky += u.fogColor.rgb * disc;
    }
    return sky;
}

// MARK: - Surface Evaluation & Triangle Tangent Frame

struct SurfaceHit {
    float3 worldPos;
    float3 prevWorldPos;
    float3 Ns; // smooth interpolated world normal
    float3 Ng; // true outward geometric normal
    float3 N;  // normal-mapped world normal facing incoming ray
    float2 uv;
    float3 baseColor;
    float3 emissive;
    float roughness;
    float metalness;
    float clearCoat;
    float clearCoatRough;
    float ior;
    float subsurface;
    float sheen;
    float opacity;
    float3 absorbColor;
    float thickness;
    int matClass;
    int matFlags;
    bool frontFace;
    float f0;       // dielectric normal-incidence reflectance
    float offsetEps; // self-intersection offset, grows with distance from the origin
};

inline SurfaceHit evalSurfaceHit(
    uint instID,
    uint geomID,
    uint primID,
    float2 bary,
    float3 rayDir,
    float hitDist,
    bool isPrimary,
    constant RTFrameUniforms& u,
    constant RTVertex* vertices,
    constant uint* indices,
    constant RTSubmesh* submeshes,
    constant RTInstanceInfo* instances,
    constant RTMaterialData* materials,
    constant RTTextureSlot* texSlots
) {
    RTInstanceInfo inst = instances[instID];
    RTSubmesh sub = submeshes[inst.submeshBase + geomID];
    RTMaterialData mat = materials[sub.materialIndex];

    uint i0 = indices[sub.indexOffset + primID * 3u + 0u] + sub.vertexOffset;
    uint i1 = indices[sub.indexOffset + primID * 3u + 1u] + sub.vertexOffset;
    uint i2 = indices[sub.indexOffset + primID * 3u + 2u] + sub.vertexOffset;

    RTVertex v0 = vertices[i0];
    RTVertex v1 = vertices[i1];
    RTVertex v2 = vertices[i2];

    float w0 = 1.0f - bary.x - bary.y;
    float3 p0 = float3(v0.px, v0.py, v0.pz);
    float3 p1 = float3(v1.px, v1.py, v1.pz);
    float3 p2 = float3(v2.px, v2.py, v2.pz);

    float3 localPos = p0 * w0 + p1 * bary.x + p2 * bary.y;
    float3 localNs = normalize(float3(v0.nx, v0.ny, v0.nz) * w0
                             + float3(v1.nx, v1.ny, v1.nz) * bary.x
                             + float3(v2.nx, v2.ny, v2.nz) * bary.y);
    float2 uv0 = float2(v0.u, v0.v);
    float2 uv1 = float2(v1.u, v1.v);
    float2 uv2 = float2(v2.u, v2.v);
    float2 uv = uv0 * w0 + uv1 * bary.x + uv2 * bary.y;
    float4 vertCol = float4(v0.cr, v0.cg, v0.cb, v0.ca) * w0
                   + float4(v1.cr, v1.cg, v1.cb, v1.ca) * bary.x
                   + float4(v2.cr, v2.cg, v2.cb, v2.ca) * bary.y;

    float3 wp0 = (inst.modelToWorld * float4(p0, 1.0f)).xyz;
    float3 wp1 = (inst.modelToWorld * float4(p1, 1.0f)).xyz;
    float3 wp2 = (inst.modelToWorld * float4(p2, 1.0f)).xyz;

    SurfaceHit sh;
    sh.worldPos = (inst.modelToWorld * float4(localPos, 1.0f)).xyz;
    sh.prevWorldPos = (inst.prevModelToWorld * float4(localPos, 1.0f)).xyz;

    float3 e1 = wp1 - wp0;
    float3 e2 = wp2 - wp0;
    float3 crossG = cross(e1, e2);
    float crossLen = length(crossG);
    float3 ngRaw = (crossLen > 1e-10f) ? (crossG / crossLen) : float3(0, 1, 0);
    if ((inst.flags & 1u) != 0u) ngRaw = -ngRaw; // Fix winding flip on mirrored (-scale) transforms.

    float3x3 normM = float3x3(inst.normalToWorld[0].xyz, inst.normalToWorld[1].xyz, inst.normalToWorld[2].xyz);
    float3 nsWorld = normalize(normM * localNs);
    if (dot(nsWorld, ngRaw) < 0.0f) nsWorld = -nsWorld;

    sh.Ng = ngRaw;
    sh.Ns = nsWorld;
    sh.frontFace = (dot(rayDir, sh.Ng) < 0.0f);
    sh.uv = uv;
    sh.matClass = mat.extraTex.z;
    sh.matFlags = mat.extraTex.w;
    sh.f0 = 0.04f;
    sh.offsetEps = 1.0f + length(sh.worldPos) * 0.004f;

    // Ray-cone texture filtering: pick the mip whose texel matches the pixel footprint on the surface.
    // Camera rays use the real pixel angle; scattered rays use a wide cone so they read smooth, noise-free texels.
    // The pixel angle is the output pixel's, not the internal one: denoised motion frames are traced at a
    // lower resolution and rebuilt at full size from jittered samples, so they need full-size texture detail.
    float coneSpread = isPrimary ? (2.0f * u.tanHalfFov / float(max(max(u.renderSize.y, u.outputSize.y), 1u))) : 0.03f;
    float footprint = hitDist * coneSpread / sqrt(max(abs(dot(rayDir, ngRaw)), 0.06f));
    float2 duvA = uv1 - uv0;
    float2 duvB = uv2 - uv0;
    float uvPerWorld = sqrt(abs(duvA.x * duvB.y - duvA.y * duvB.x) / max(crossLen, 1e-12f));
    float texelSpan = footprint * uvPerWorld;
    // The live renderer shows one unaveraged sample per pixel whenever the camera moves, so detail finer
    // than a pixel shows up as crawling grain there. It reads textures at the pixel's own size, and the maps
    // that drive highlights (normal, roughness, metalness, occlusion) a little coarser still. The path tracer
    // averages many samples, so it keeps the sharper setting.
    bool steadyDetail = ((u.renderFlags & 8u) != 0u);
    float lodBias = steadyDetail ? -0.5f : -0.6f;
    float detailLodBias = steadyDetail ? 0.7f : 0.0f;
    auto lodFor = [&](texture2d<float> t, float2 uvScale) -> float {
        float texels = texelSpan * max(abs(uvScale.x), abs(uvScale.y)) * float(t.get_width());
        return max(0.0f, log2(max(texels, 1e-6f)) + lodBias);
    };

    // Select wrap vs clamp sampler safely.
    bool shouldClamp = (sh.matClass == MAT_SCREEN || sh.matClass == MAT_SSS_POLYMER || sh.matClass == MAT_KEY_SKIRT || sh.matClass == MAT_EMISSIVE_CARD);
    float2 uvDiff = uv * mat.diffuseUV.xy + mat.diffuseUV.zw;
    float2 uvDet  = uv * mat.detailUV.xy + mat.detailUV.zw;
    float2 uvRough = uv * mat.roughnessUV.xy + mat.roughnessUV.zw;

    // Diffuse Albedo (including per-vertex color modulation from exterior terrains/foliage)
    sh.baseColor = mat.baseColor.rgb * vertCol.rgb;
    sh.opacity = mat.baseColor.w * vertCol.a;
    if (mat.texIndices.x >= 0) {
        float lodD = lodFor(texSlots[mat.texIndices.x].tex, mat.diffuseUV.xy);
        float4 ts = shouldClamp
            ? texSlots[mat.texIndices.x].tex.sample(kClampSamp, uvDiff, level(lodD))
            : texSlots[mat.texIndices.x].tex.sample(kRepeatSamp, uvDiff, level(lodD));
        sh.baseColor *= ts.rgb;
        if (sh.matClass != MAT_STANDARD && sh.matClass != MAT_SSS_POLYMER) {
            sh.opacity *= ts.a;
        }
    }

    // Ambient Occlusion map
    if (mat.extraTex.y >= 0) {
        float aoVal = texSlots[mat.extraTex.y].tex.sample(kRepeatSamp, uvDet, level(lodFor(texSlots[mat.extraTex.y].tex, mat.detailUV.xy) + detailLodBias)).r;
        sh.baseColor *= mix(1.0f, aoVal, 0.72f);
    }

    // Normal perturbation
    float3 shadedN = sh.Ns;
    bool isOpenWater = ((sh.matFlags & 128) != 0);
    float waterDetailLost = 0.0f;
    if (isOpenWater && mat.texIndices.y >= 0) {
        // Open water: three wave bands in world space (chop, wind waves, swell). Each band fades through its
        // mip chain with distance, and what the mips average away comes back as roughness, so the far sea
        // turns into a soft sheen instead of a mirror or a field of sparkling noise.
        texture2d<float> wt = texSlots[mat.texIndices.y].tex;
        float tw = float(wt.get_width());
        float2 wp = sh.worldPos.xz;
        float s1 = 1.0f / 46.0f, s2 = 1.0f / 330.0f, s3 = 1.0f / 2400.0f;
        float l1 = max(0.0f, log2(max(footprint * s1 * tw, 1e-6f)));
        float l2 = max(0.0f, log2(max(footprint * s2 * tw, 1e-6f)));
        float l3 = max(0.0f, log2(max(footprint * s3 * tw, 1e-6f)));
        float3 n1 = wt.sample(kRepeatSamp, wp * s1, level(l1)).xyz * 2.0f - 1.0f;
        float3 n2 = wt.sample(kRepeatSamp, float2(wp.y, -wp.x) * s2 + 0.37f, level(l2)).xyz * 2.0f - 1.0f;
        float3 n3 = wt.sample(kRepeatSamp, (wp + wp.yx * 0.31f) * s3 + 0.71f, level(l3)).xyz * 2.0f - 1.0f;
        float2 slope = (n1.xy * 0.50f + n2.xy * 0.85f + n3.xy * 0.65f) * mat.params.w;
        shadedN = normalize(float3(slope.x, 1.0f, slope.y));
        waterDetailLost = saturate(l1 / 6.0f) * 0.50f + saturate(l2 / 6.0f) * 0.32f + saturate(l3 / 6.0f) * 0.18f;
        sh.f0 = 0.02f;
    } else if (mat.texIndices.y >= 0 && mat.params.w > 1e-4f) {
        float2 d1 = uv1 * mat.detailUV.xy - uv0 * mat.detailUV.xy;
        float2 d2 = uv2 * mat.detailUV.xy - uv0 * mat.detailUV.xy;
        float det = d1.x * d2.y - d1.y * d2.x;
        if (abs(det) > 1e-9f) {
            float invDet = 1.0f / det;
            float3 T_raw = (e1 * d2.y - e2 * d1.y) * invDet;
            float3 B_raw = (e2 * d1.x - e1 * d2.x) * invDet;
            float3 T = normalize(T_raw - sh.Ns * dot(sh.Ns, T_raw));
            float3 B = normalize(cross(sh.Ns, T)) * ((dot(cross(sh.Ns, T), B_raw) < 0.0f) ? -1.0f : 1.0f);
            float3 tn = texSlots[mat.texIndices.y].tex.sample(kRepeatSamp, uvDet, level(lodFor(texSlots[mat.texIndices.y].tex, mat.detailUV.xy) + detailLodBias)).xyz * 2.0f - 1.0f;
            float normScale = mat.params.w * (isPrimary ? 1.0f : 0.65f);
            tn.xy *= normScale;
            shadedN = normalize(T * tn.x + B * tn.y + sh.Ns * max(tn.z, 0.1f));
        }
    }

    // Flip normal to face incoming ray cleanly on front-facing/double-sided surfaces.
    sh.N = sh.frontFace ? shadedN : -shadedN;

    // Roughness & Metalness + Micro-Surface Detail
    sh.roughness = mat.emissionColor.w;
    if (mat.texIndices.z >= 0) {
        float rSamp = texSlots[mat.texIndices.z].tex.sample(kRepeatSamp, uvRough, level(lodFor(texSlots[mat.texIndices.z].tex, mat.roughnessUV.xy) + detailLodBias)).r;
        sh.roughness = saturate(rSamp * mat.emissionColor.w);
    }
    sh.metalness = mat.params.x;
    if (mat.extraTex.x >= 0) {
        sh.metalness *= texSlots[mat.extraTex.x].tex.sample(kRepeatSamp, uvDet, level(lodFor(texSlots[mat.extraTex.x].tex, mat.detailUV.xy) + detailLodBias)).r;
    }

    // Subtle physical micro-grain so macro closeups never look flat
    // Per-point random roughness is noise by construction: fine for an averaged image, grain in a live one.
    if (isPrimary && !steadyDetail) {
        float3 micro = hash33(floor(sh.worldPos * 260.0f));
        if ((sh.matFlags & 8) != 0) { // Anodized aluminum Mac mini & keyboard chassis
            sh.roughness = clamp(sh.roughness + (micro.x - 0.5f) * 0.045f, 0.06f, 0.92f);
        } else if ((sh.matFlags & 16) != 0) { // Satin walnut desk
            float poreVar = 1.0f - luminance(sh.baseColor) * 1.4f;
            sh.roughness = clamp(sh.roughness + poreVar * 0.08f + (micro.y - 0.5f) * 0.025f, 0.16f, 0.85f);
        } else if (sh.matClass == MAT_SSS_POLYMER) {
            sh.roughness = clamp(sh.roughness + (micro.x - 0.5f) * 0.025f, 0.08f, 0.90f);
        }
    }
    if (isOpenWater) {
        sh.roughness = mix(sh.roughness, 0.24f, waterDetailLost);
    }
    sh.roughness = clamp(sh.roughness, 0.008f, 0.99f);

    sh.clearCoat = mat.params.y;
    sh.clearCoatRough = clamp(mat.params.z, 0.006f, 0.85f);
    sh.ior = mat.optics.x;
    sh.subsurface = mat.optics.y;
    sh.sheen = mat.optics.z;
    sh.absorbColor = mat.absorbColor.xyz;
    sh.thickness = mat.absorbColor.w;

    // Emission
    sh.emissive = mat.emissionColor.rgb * vertCol.rgb;
    if (mat.texIndices.w >= 0) {
        float lodE = lodFor(texSlots[mat.texIndices.w].tex, mat.diffuseUV.xy) + (isPrimary ? 0.0f : 1.0f);
        float3 et = (shouldClamp
            ? texSlots[mat.texIndices.w].tex.sample(kClampSamp, uvDiff, level(lodE))
            : texSlots[mat.texIndices.w].tex.sample(kRepeatSamp, uvDiff, level(lodE))).rgb;
        sh.emissive *= et;
    }
    float glowBoost = u.monitorColor.w;
    if (sh.matClass == MAT_KEY_SKIRT) {
        float skirt = pow(saturate(1.0f - uvDet.y), 2.10f);
        sh.emissive *= skirt * glowBoost;
    } else if (sh.matClass == MAT_KEY_PLATE && u.plateGlowTexIndex >= 0) {
        float3 kPos = (u.worldToKeyboard * float4(sh.worldPos, 1.0f)).xyz;
        float3 kN = normalize((u.worldToKeyboard * float4(sh.Ng, 0.0f)).xyz);
        if (kN.y > 0.25f) {
            float2 gp = float2(kPos.x * u.plateBounds.z + 0.5f, kPos.z * u.plateBounds.w + 0.5f);
            if (gp.x >= 0.0f && gp.x <= 1.0f && gp.y >= 0.0f && gp.y <= 1.0f) {
                float3 pg = texSlots[u.plateGlowTexIndex].tex.sample(kClampSamp, gp).rgb;
                sh.emissive += pg * (2.85f * glowBoost);
            }
        }
    }

    return sh;
}

// MARK: - Shadow & Refractive Glass Caustic Ray

inline float3 evaluateShadowTransmission(
    float3 origin,
    float3 lightDir,
    float maxDist,
    constant RTFrameUniforms& u,
    instance_acceleration_structure accel,
    constant RTVertex* vertices,
    constant uint* indices,
    constant RTSubmesh* submeshes,
    constant RTInstanceInfo* instances,
    constant RTMaterialData* materials
) {
    float3 tr = float3(1.0f);
    float3 ro = origin;
    float remaining = maxDist - 0.008f;
    intersector<triangle_data, instancing> sInter;
    sInter.assume_geometry_type(geometry_type::triangle);

    for (int hop = 0; hop < 4; ++hop) {
        if (remaining <= 0.004f) break;
        ray r(ro, lightDir, 0.003f, remaining);
        auto res = sInter.intersect(r, accel, 0xF9u);
        if (res.type == intersection_type::none) {
            return tr;
        }
        RTInstanceInfo inst = instances[res.instance_id];
        if ((inst.flags & 16u) != 0u) {
            // Skip meshes flagged castsShadow = false (except refractive glass still adds caustics)
            RTSubmesh sub = submeshes[inst.submeshBase + res.geometry_id];
            RTMaterialData mat = materials[sub.materialIndex];
            int mc = mat.extraTex.z;
            if (mc == MAT_EMISSIVE_CARD) {
                ro += lightDir * (res.distance + 0.004f);
                remaining -= (res.distance + 0.004f);
                continue;
            }
            if (mc == MAT_THIN_GLASS || mc == MAT_SOLID_GLASS || mc == MAT_WATER || mc == MAT_INDIGO_RESIN) {
                // Dielectric refractive attenuation + focused lens caustic boost
                uint i0 = indices[sub.indexOffset + res.primitive_id * 3u + 0u] + sub.vertexOffset;
                uint i1 = indices[sub.indexOffset + res.primitive_id * 3u + 1u] + sub.vertexOffset;
                uint i2 = indices[sub.indexOffset + res.primitive_id * 3u + 2u] + sub.vertexOffset;
                float3 wp0 = (inst.modelToWorld * float4(vertices[i0].px, vertices[i0].py, vertices[i0].pz, 1.0f)).xyz;
                float3 wp1 = (inst.modelToWorld * float4(vertices[i1].px, vertices[i1].py, vertices[i1].pz, 1.0f)).xyz;
                float3 wp2 = (inst.modelToWorld * float4(vertices[i2].px, vertices[i2].py, vertices[i2].pz, 1.0f)).xyz;
                float3 gn = normalize(cross(wp1 - wp0, wp2 - wp0));
                float ndotl = abs(dot(gn, lightDir));
                if (mc == MAT_WATER) {
                    float3 tint = exp(-mat.absorbColor.xyz * 0.35f);
                    tr *= tint * mix(0.84f, 1.12f, smoothstep(0.05f, 0.55f, ndotl));
                } else {
                    float rimShadow = smoothstep(0.08f, 0.55f, ndotl);
                    float caustic = mix(0.68f, 1.38f, pow(ndotl, 3.0f));
                    float3 tint = exp(-mat.absorbColor.xyz * (mc == MAT_THIN_GLASS ? 0.25f : 0.65f));
                    tr *= tint * mix(0.44f, caustic, rimShadow);
                }
            } else if ((mat.extraTex.w & 4) != 0 && mat.baseColor.w < 0.05f) {
                // Hidden mouse overlay
            } else {
                // Other non-shadow-casting detail parts pass cleanly
            }
            ro += lightDir * (res.distance + 0.004f);
            remaining -= (res.distance + 0.004f);
            continue;
        }
        return float3(0.0f);
    }
    return tr;
}

// MARK: - Next Event Estimation (sun or key softbox every hit, plus one sampled local light)

// Glazing-bar layout shared with the visible window in the Studio Room.
inline float windowPaneMask(float a, float b, float w, float h) {
    const float frame = 1.1f;
    const float bar = 0.55f;
    if (a < frame || a > w - frame || b < frame || b > h - frame) return 0.0f;
    if (abs(a - w * 0.5f) < bar) return 0.0f;
    if (abs(b - h * 0.58f) < bar) return 0.0f;
    return 1.0f;
}

inline float3 evaluateSurfaceDirectBSDF(SurfaceHit sh, float3 V, float3 L, float3 rad) {
    bool isThinGlassHighlight = (sh.matClass == MAT_THIN_GLASS || sh.matClass == MAT_SOLID_GLASS || sh.matClass == MAT_WATER || sh.matClass == MAT_INDIGO_RESIN);
    if (isThinGlassHighlight) {
        float3 hSum = V + L;
        float3 H = (dot(hSum, hSum) > 1e-8f) ? normalize(hSum) : sh.N;
        float NdotL = max(dot(sh.N, L), 0.0f);
        float NdotV = max(dot(sh.N, V), 1e-4f);
        float NdotH = max(dot(sh.N, H), 0.0f);
        float VdotH = max(dot(V, H), 0.0f);
        if (NdotL <= 0.0f) return float3(0.0f);
        float F0 = pow((1.0f - sh.ior) / (1.0f + sh.ior), 2.0f);
        float3 F = fresnelSchlick(VdotH, float3(F0));
        float a = max(sh.roughness * sh.roughness, 0.0005f);
        float D = D_GGX(NdotH, a);
        float Vis = V_SmithGGX(NdotV, NdotL, a);
        return rad * F * (D * Vis * NdotL);
    }
    float3 bsdf = evaluateBSDF(V, L, sh.N, sh.baseColor, sh.roughness, sh.metalness,
                               sh.clearCoat, sh.clearCoatRough, sh.sheen, sh.subsurface, sh.f0);
    // Backlit leaf chlorophyll transmission
    if (sh.matClass == MAT_FOLIAGE) {
        float backNdotL = max(dot(-sh.N, L), 0.0f);
        if (backNdotL > 0.0f) {
            bsdf += sh.baseColor * float3(1.08f, 1.24f, 0.66f) * (INV_PI * 0.38f * backNdotL);
        }
    }
    return bsdf * rad;
}

/// Direct unit-white desk lamp irradiance on a surface point so live rendering can tint and dim
/// the desk lamp dynamically without re-baking the stored light cache.
inline float3 evaluateDeskLampUnit(
    SurfaceHit sh,
    float3 V,
    thread uint& rng,
    constant RTFrameUniforms& u,
    instance_acceleration_structure accel,
    constant RTVertex* vertices,
    constant uint* indices,
    constant RTSubmesh* submeshes,
    constant RTInstanceInfo* instances,
    constant RTMaterialData* materials
) {
    float3 P = sh.worldPos + sh.Ng * ((sh.frontFace ? 0.005f : -0.005f) * sh.offsetEps);
    float3 bPos = u.deskBulbPosRadius.xyz + sampleUniformSphere(rand01(rng), rand01(rng)) * u.deskBulbPosRadius.w;
    float3 toL = bPos - P;
    float dist = length(toL);
    if (dist >= 42.0f) return float3(0.0f);
    float3 L = toL / max(dist, 1e-4f);
    if (dot(sh.N, L) <= -0.1f) return float3(0.0f);
    float maxDist = max(dist - 4.2f, 0.05f);
    float3 vis = evaluateShadowTransmission(P, L, maxDist, u, accel, vertices, indices, submeshes, instances, materials);
    if (!any(vis > 1e-4f)) return float3(0.0f);
    float atten = 1.0f / (1.0f + dist * dist * 0.032f);
    float cone = saturate(L.y * 1.35f + 0.45f);
    return min(evaluateSurfaceDirectBSDF(sh, V, L, vis * (atten * cone)), float3(24.0f));
}

inline float3 evaluateAllAreaLights(
    SurfaceHit sh,
    float3 V,
    uint bounceIndex,
    thread uint& rng,
    constant RTFrameUniforms& u,
    instance_acceleration_structure accel,
    constant RTVertex* vertices,
    constant uint* indices,
    constant RTSubmesh* submeshes,
    constant RTInstanceInfo* instances,
    constant RTMaterialData* materials,
    constant RTTextureSlot* texSlots,
    thread float3& lightDirection, // += each light's direction weighted by the brightness it contributed
    bool skipDeskLamp = false
) {
    float3 direct = float3(0.0f);
    float3 shadowOrigin = sh.worldPos + sh.Ng * ((sh.frontFace ? 0.005f : -0.005f) * sh.offsetEps);
    bool wrapsLight = (sh.subsurface > 0.01f || sh.matClass == MAT_FOLIAGE);

    // Every light on this hit goes through ONE shadow-ray call site: step 0 is the key light, the
    // following steps are local lights picked in proportion to their unshadowed strength. Each step only
    // decides a direction, a distance and the radiance that would arrive unshadowed; the ray and the BSDF
    // are then evaluated once below. The hardware pays for every separate intersect site in a kernel, so
    // one shared site makes the same rays far cheaper than nine inlined copies.
    float3 P = shadowOrigin;
    float w[5] = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f };
    float cosFloor = wrapsLight ? 0.25f : 0.03f;
    float3 winN = cross(u.windowU.xyz, u.windowV.xyz);
    float3 winC = u.windowOrigin.xyz + u.windowU.xyz * (u.windowU.w * 0.5f) + u.windowV.xyz * (u.windowV.w * 0.5f);
    float winArea = u.windowU.w * u.windowV.w;

    // Denoised motion frames and capped interactive frames light secondary bounces with the key light only.
    bool localLights = !(((u.renderFlags & 1u) == 0u || (u.renderFlags & 2u) != 0u) && bounceIndex > 0u);
    float wSum = 0.0f;
    if (localLights) {
        if (u.fillLightColor.w > 1.5f) {
            float3 toL = winC - P;
            float dist = max(length(toL), 1e-3f);
            float3 Ldir = toL / dist;
            float d2 = max(dot(toL, toL), winArea * 0.25f);
            float cosL = max(dot(winN, -Ldir), 0.0f);
            float cosR = max(dot(sh.N, Ldir), cosFloor);
            w[0] = luminance(u.fillLightColor.rgb) * winArea * (cosL + 0.04f) * cosR / d2;
        } else if (u.fillLightColor.w > 0.5f) {
            float cosR = wrapsLight ? 1.0f : (0.35f + 0.65f * saturate(sh.N.y * 0.4f + 0.6f));
            w[0] = luminance(u.fillLightColor.rgb) * 1.15f * cosR;
        }
        if (u.roomLightColor.w > 0.01f) {
            float cosR = wrapsLight ? 1.0f : (0.15f + 0.85f * saturate(sh.N.y * 0.5f + 0.5f));
            w[1] = luminance(u.roomLightColor.rgb) * cosR;
        }
        if (!skipDeskLamp && u.deskBulbColor.w > 0.01f) {
            float3 toL = u.deskBulbPosRadius.xyz - P;
            float dist = length(toL);
            if (dist < 42.0f) {
                float3 Ldir = toL / max(dist, 1e-3f);
                // The shade opens downward: full strength below the bulb, fading to nothing a little above level.
                float cone = saturate(Ldir.y * 1.35f + 0.45f);
                float cosR = max(dot(sh.N, Ldir), cosFloor);
                w[2] = luminance(u.deskBulbColor.rgb) * (cone + 0.02f) * cosR / (1.0f + dist * dist * 0.032f);
            }
        }
        if (u.monitorPos.w > 0.01f) {
            float3 toL = u.monitorPos.xyz - P;
            float dist = length(toL);
            if (dist < 72.0f) {
                float3 Ldir = toL / max(dist, 1e-3f);
                float3 mNorm = normalize(cross(u.monitorU.xyz, u.monitorV.xyz));
                float emitCos = max(dot(mNorm, -Ldir), 0.0f);
                float cosR = max(dot(sh.N, Ldir), cosFloor);
                w[3] = u.monitorPos.w * (emitCos + 0.05f) * 2.6f * cosR / (1.0f + dist * dist * 0.018f);
            }
        }
        if (u.underDeskPosB.w > 0.01f && !(P.y > -0.25f && P.z > -16.5f && abs(P.x) < 36.0f)) {
            float3 toL = (u.underDeskPosA.xyz + u.underDeskPosB.xyz) * 0.5f - P;
            float dist = length(toL);
            if (dist < 48.0f) {
                float3 Ldir = toL / max(dist, 1e-3f);
                float cosR = max(dot(sh.N, Ldir), cosFloor);
                w[4] = luminance(u.underDeskColor.rgb) * 2.6f * u.underDeskPosB.w * cosR / (1.0f + dist * dist * 0.038f);
            }
        }
        wSum = w[0] + w[1] + w[2] + w[3] + w[4];
    }
    // Camera-visible surfaces get two picks so penumbrae from the lamps resolve quickly.
    uint picks = (wSum > 1e-6f) ? ((bounceIndex == 0u) ? 2u : 1u) : 0u;

    for (uint step = 0u; step <= picks; ++step) {
        float3 L = float3(0.0f, 1.0f, 0.0f);
        float maxDist = 0.0f;
        float3 rad = float3(0.0f); // unshadowed radiance along L, already divided by the pick probability

        if (step == 0u) {
            // Key light: the sun (or moon) as a small-angle directional source, or the legacy softbox.
            if (u.keyLightColor.w > 0.5f && (u.renderFlags & 16u) != 0u) {
                // Live renderer: the sun or moon is lit and shadowed exactly at every pixel, every frame,
                // so it is left out of the stored light. Stored at a few millimetres' spacing its shadows
                // could only ever be soft smears.
            } else if (u.keyLightColor.w > 0.5f) {
                float3 sunDir = u.keyLightPosRadius.xyz;
                float3 T, B;
                makeONB(sunDir, T, B);
                float2 d = sampleDisk(rand01(rng), rand01(rng)) * u.keyLightPosRadius.w;
                L = normalize(sunDir + T * d.x + B * d.y);
                if (any(u.keyLightColor.rgb > 1e-5f) && (dot(sh.N, L) > 0.0f || wrapsLight)) {
                    maxDist = 3.0e6f;
                    float mask = 1.0f;
                    if (u.windowOrigin.w > 0.5f) {
                        // Indoors the sun only arrives through the window opening: trace back to the wall plane,
                        // keep the light if that point is glass, and stop the shadow ray just short of the wall.
                        float denom = dot(L, winN);
                        float tHit = (abs(denom) > 1e-4f) ? dot(u.windowOrigin.xyz - P, winN) / denom : -1.0f;
                        if (tHit <= 0.05f) {
                            mask = 0.0f;
                        } else {
                            float3 q = P + L * tHit - u.windowOrigin.xyz;
                            mask = windowPaneMask(dot(q, u.windowU.xyz), dot(q, u.windowV.xyz), u.windowU.w, u.windowV.w);
                            maxDist = tHit - 0.05f;
                        }
                    }
                    rad = u.keyLightColor.rgb * mask;
                }
            } else if (any(u.keyLightColor.rgb > 1e-4f)) {
                float3 samplePos = u.keyLightPosRadius.xyz + sampleUniformSphere(rand01(rng), rand01(rng)) * u.keyLightPosRadius.w;
                float3 toLight = samplePos - P;
                float dist = length(toLight);
                L = toLight / max(dist, 1e-4f);
                if (dot(sh.N, L) > 0.0f || wrapsLight) {
                    maxDist = min(dist, 420.0f);
                    rad = u.keyLightColor.rgb * 1.45f;
                }
            }
        } else {
            float xi = rand01(rng) * wSum;
            int pick = 4;
            float acc = 0.0f;
            for (int i = 0; i < 5; ++i) {
                acc += w[i];
                if (xi < acc) { pick = i; break; }
            }
            if (w[pick] <= 0.0f) continue;

            if (pick == 0 && u.fillLightColor.w > 1.5f) {
                // Daylight window: a rectangular sky-lit area light on the wall.
                float3 sp = u.windowOrigin.xyz + u.windowU.xyz * (rand01(rng) * u.windowU.w) + u.windowV.xyz * (rand01(rng) * u.windowV.w);
                float3 toL = sp - P;
                float dist = length(toL);
                L = toL / max(dist, 1e-4f);
                float cosL = max(dot(winN, -L), 0.0f);
                if (cosL > 0.0f && (dot(sh.N, L) > 0.0f || wrapsLight)) {
                    maxDist = dist - 0.12f;
                    rad = u.fillLightColor.rgb * (cosL * winArea / max(dist * dist, 16.0f));
                }
            } else if (pick == 0) {
                float3 fPos = u.fillLightPosRadius.xyz + sampleUniformSphere(rand01(rng), rand01(rng)) * u.fillLightPosRadius.w;
                float3 toL = fPos - P;
                float dist = length(toL);
                L = toL / max(dist, 1e-4f);
                if (dot(sh.N, L) > 0.0f || wrapsLight) {
                    maxDist = min(dist, 280.0f);
                    rad = u.fillLightColor.rgb * 1.15f;
                }
            } else if (pick == 1) {
                float3 rPos = u.roomLightPosRadius.xyz + sampleUniformSphere(rand01(rng), rand01(rng)) * u.roomLightPosRadius.w;
                float3 toL = rPos - P;
                float dist = length(toL);
                L = toL / max(dist, 1e-4f);
                if (dot(sh.N, L) > 0.0f || wrapsLight) {
                    maxDist = min(dist, 420.0f);
                    rad = u.roomLightColor.rgb;
                }
            } else if (pick == 2) {
                float3 bPos = u.deskBulbPosRadius.xyz + sampleUniformSphere(rand01(rng), rand01(rng)) * u.deskBulbPosRadius.w;
                float3 toL = bPos - P;
                float dist = length(toL);
                L = toL / max(dist, 1e-4f);
                if (dist < 42.0f && dot(sh.N, L) > -0.1f) {
                    // Stop the shadow ray short of the lamp head: the shade, diffuser and bulb glass around
                    // the source are part of the lamp, and were blocking most of its own light.
                    maxDist = max(dist - 4.2f, 0.05f);
                    float atten = 1.0f / (1.0f + dist * dist * 0.032f);
                    float cone = saturate(L.y * 1.35f + 0.45f);
                    rad = u.deskBulbColor.rgb * (atten * cone);
                }
            } else if (pick == 3) {
                float2 mRnd = float2(rand01(rng) * 2.0f - 1.0f, rand01(rng) * 2.0f - 1.0f);
                float3 mSample = u.monitorPos.xyz + u.monitorU.xyz * (mRnd.x * u.monitorU.w) + u.monitorV.xyz * (mRnd.y * u.monitorV.w);
                float3 toL = mSample - P;
                float dist = length(toL);
                L = toL / max(dist, 1e-4f);
                float3 mNorm = normalize(cross(u.monitorU.xyz, u.monitorV.xyz));
                float mEmitCos = max(dot(mNorm, -L), 0.0f);
                if (dist < 72.0f && mEmitCos > 0.05f && dot(sh.N, L) > 0.0f) {
                    maxDist = dist - 0.15f;
                    float3 screenCol = u.monitorColor.rgb;
                    if (u.monitorTexIndex >= 0) {
                        float2 suv = float2(mRnd.x * 0.5f + 0.5f, 0.5f - mRnd.y * 0.5f);
                        screenCol = texSlots[u.monitorTexIndex].tex.sample(kScreenSamp, suv, level(4.0f)).rgb;
                    }
                    float atten = (mEmitCos * 5.2f) / (1.0f + dist * dist * 0.018f);
                    rad = screenCol * (atten * u.monitorPos.w);
                }
            } else {
                float3 segPos = mix(u.underDeskPosA.xyz, u.underDeskPosB.xyz, rand01(rng));
                float3 toL = segPos - P;
                float dist = length(toL);
                L = toL / max(dist, 1e-4f);
                if (dist < 48.0f && dot(sh.N, L) > 0.0f) {
                    maxDist = dist - 0.25f;
                    float atten = 1.0f / (1.0f + dist * dist * 0.038f);
                    rad = u.underDeskColor.rgb * (2.6f * u.underDeskPosB.w * atten);
                }
            }
            rad *= wSum / (w[pick] * float(picks));
        }

        if (!any(rad > 0.0f)) continue;
        float3 vis = evaluateShadowTransmission(P, L, maxDist, u, accel, vertices, indices, submeshes, instances, materials);
        if (!any(vis > 1e-4f)) continue;
        float3 lit = evaluateSurfaceDirectBSDF(sh, V, L, rad * vis);
        // A rare pick of a weak light can carry a large weight; bound it so it cannot become a firefly.
        lit = (step == 0u) ? lit : min(lit, float3(24.0f));
        direct += lit;
        lightDirection += L * luminance(lit);
    }

    return direct;
}

// MARK: - Main Path Tracing Compute Kernel

kernel void pathTraceKernel(
    uint2 gid [[thread_position_in_grid]],
    constant RTFrameUniforms& u [[buffer(0)]],
    instance_acceleration_structure accel [[buffer(1)]],
    constant RTVertex* vertices [[buffer(2)]],
    constant uint* indices [[buffer(3)]],
    constant RTSubmesh* submeshes [[buffer(4)]],
    constant RTInstanceInfo* instances [[buffer(5)]],
    constant RTMaterialData* materials [[buffer(6)]],
    constant RTTextureSlot* texSlots [[buffer(7)]],
    texturecube<float> bgCubemap [[texture(0)]],
    texture2d<float, access::write> outColor [[texture(1)]],
    texture2d<float, access::write> outDepth [[texture(2)]],
    texture2d<float, access::write> outMotion [[texture(3)]],
    texture2d<float, access::write> outDiffAlbedo [[texture(4)]],
    texture2d<float, access::write> outSpecAlbedo [[texture(5)]],
    texture2d<float, access::write> outNormal [[texture(6)]],
    texture2d<float, access::write> outRoughness [[texture(7)]],
    texture2d<float, access::write> outSpecHitDist [[texture(8)]],
    texture2d<float, access::write> outReactive [[texture(9)]]
) {
    if (gid.x >= u.renderSize.x || gid.y >= u.renderSize.y) return;

    uint rng = pcgHash(gid.x + gid.y * 8192u + u.frameIndex * 16777619u + u.sampleIndex * 2654435761u);

    float2 resF = float2(u.renderSize);
    float2 pix = float2(gid) + 0.5f + u.jitter;
    float2 ndc = float2((pix.x / resF.x) * 2.0f - 1.0f, 1.0f - (pix.y / resF.y) * 2.0f);

    float3 rayDirPinhole = normalize(
        u.camForward.xyz
        + u.camRight.xyz * (ndc.x * u.aspect * u.tanHalfFov)
        + u.camUp.xyz * (ndc.y * u.tanHalfFov)
    );

    float3 ro = u.camPos.xyz;
    float3 rd = rayDirPinhole;
    if (u.apertureRadius > 1e-5f) {
        float2 lens = sampleDisk(rand01(rng), rand01(rng)) * u.apertureRadius;
        float focalT = u.focusDistance / max(dot(rayDirPinhole, u.camForward.xyz), 0.1f);
        float3 focalPt = ro + rayDirPinhole * focalT;
        ro += u.camRight.xyz * lens.x + u.camUp.xyz * lens.y;
        rd = normalize(focalPt - ro);
    }

    float3 radiance = float3(0.0f);
    float3 throughput = float3(1.0f);
    bool inWater = false;
    bool inSolidGlass = false;
    bool inIndigo = false;
    float3 curAbsorb = float3(0.0f);
    bool primarySpecularPath = false;
    float specularHitDistance = 0.0f;
    bool recordedGBuffer = false;
    bool writeGBuffer = ((u.renderFlags & 1u) == 0u);
    bool outdoor = (u.isRoomScenario == 0u);
    bool prevDiffuse = false; // last scatter was a diffuse bounce (its light sources are already counted by NEE)
    float envLod = 0.0f;      // sky-map blur for the current ray: sharp for camera/mirror rays, soft for diffuse

    intersector<triangle_data, instancing> inter;
    inter.assume_geometry_type(geometry_type::triangle);

    uint maxB = max(1u, u.maxBounces);
    uint cardPasses = 0u;
    for (uint bounce = 0; bounce < maxB; ) {
        ray r(ro, rd, 0.0015f, 4.0e6f);
        auto res = inter.intersect(r, accel, prevDiffuse ? 0xFDu : 0xFFu);

        if (res.type == intersection_type::none) {
            float3 envCol = (bounce == 0)
                ? samplePrimaryMiss(rd, u, texSlots, bgCubemap)
                : sampleEnvEquirect(rd, envLod, u, texSlots);
            if (bounce > 0) envCol = min(envCol, float3(18.0f));
            radiance += throughput * envCol;

            if (!recordedGBuffer && writeGBuffer) {
                recordedGBuffer = true;
                outDepth.write(float4(1.0f, 0.0f, 0.0f, 1.0f), gid);
                outMotion.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
                outDiffAlbedo.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
                outSpecAlbedo.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
                outNormal.write(float4(0.0f, 1.0f, 0.0f, 1.0f), gid);
                outRoughness.write(float4(1.0f, 0.0f, 0.0f, 1.0f), gid);
                outSpecHitDist.write(float4(0.0f), gid);
                outReactive.write(float4(0.0f), gid);
            }
            break;
        }

        // Apply Beer-Lambert attenuation if currently propagating inside water/glass/resin.
        if (inWater || inSolidGlass || inIndigo) {
            throughput *= exp(-curAbsorb * min(res.distance, 8.0f));
        }

        SurfaceHit sh = evalSurfaceHit(
            res.instance_id, res.geometry_id, res.primitive_id, res.triangle_barycentric_coord,
            rd, res.distance, (bounce == 0), u, vertices, indices, submeshes, instances, materials, texSlots
        );

        // Transparent invisible button overlays (idle state): pass cleanly through without consuming bounce.
        if ((sh.matFlags & 4) != 0 && sh.opacity < 0.05f) {
            ro = sh.worldPos + rd * 0.002f;
            if (++cardPasses < 16u) continue;
            break;
        }

        // Translucent scenario cards (god rays, glowing particles/stars):
        // accumulate contribution without terminating the ray or dirtying foreground G-buffers.
        if (sh.matClass == MAT_EMISSIVE_CARD) {
            float effA = saturate(sh.opacity);
            bool isAdd = ((sh.matFlags & 32) != 0);
            float3 cardRad = sh.emissive;
            if (isAdd) {
                radiance += throughput * cardRad * effA;
            } else {
                float3 keyDir = normalize(u.keyLightPosRadius.xyz - sh.worldPos);
                float keyTerm = 0.35f + 0.55f * abs(dot(sh.N, keyDir));
                float3 litCard = sh.baseColor * keyTerm + cardRad * 0.65f;
                radiance += throughput * litCard * effA;
                throughput *= (1.0f - effA);
            }
            ro = sh.worldPos + rd * 0.0025f;
            if (max(throughput.x, max(throughput.y, throughput.z)) < 0.002f || ++cardPasses >= 16u) break;
            continue;
        }

        // Path-space glossy regularization on secondary bounces suppresses indirect caustic speckles.
        if (bounce > 0u) {
            if (sh.matClass != MAT_THIN_GLASS && sh.matClass != MAT_SOLID_GLASS && sh.matClass != MAT_WATER && sh.matClass != MAT_INDIGO_RESIN) {
                sh.roughness = max(sh.roughness, 0.24f);
                sh.clearCoatRough = max(sh.clearCoatRough, 0.18f);
            }
        }

        if (primarySpecularPath && specularHitDistance == 0.0f) {
            specularHitDistance = res.distance;
        }

        // Write primary G-buffers once on first surface contact.
        if (!recordedGBuffer && writeGBuffer) {
            recordedGBuffer = true;
            float4 clipPos = u.viewToClip * (u.worldToView * float4(sh.worldPos, 1.0f));
            float ndcDepth = saturate(clipPos.z / max(clipPos.w, 1e-4f));

            float4 prevClip = u.prevViewProj * float4(sh.prevWorldPos, 1.0f);
            float2 prevNDC = prevClip.xy / max(prevClip.w, 1e-4f);
            float2 prevUV = float2(prevNDC.x * 0.5f + 0.5f, 0.5f - prevNDC.y * 0.5f);
            float2 prevPix = prevUV * resF;
            // Where this sample really is: the pixel centre plus this frame's jitter. Leaving the jitter out
            // told the denoiser that a perfectly still scene was shifting by up to half a pixel every frame.
            float2 curPix = pix;
            float2 motion = prevPix - curPix;

            bool isDielectric = (sh.matClass == MAT_THIN_GLASS || sh.matClass == MAT_SOLID_GLASS || sh.matClass == MAT_WATER || sh.matClass == MAT_INDIGO_RESIN);
            float3 f0 = isDielectric ? float3(0.04f) : mix(float3(0.04f), sh.baseColor, sh.metalness);
            float3 diffAlb = isDielectric ? float3(0.0f) : sh.baseColor * (1.0f - sh.metalness);
            // Screens, legends and LEDs carry their detail in emission. Guiding the denoiser with that
            // colour keeps the wallpaper and glowing legends crisp instead of being smoothed as noise.
            float emPeak = max(sh.emissive.r, max(sh.emissive.g, sh.emissive.b));
            if (emPeak > 0.02f) {
                diffAlb = mix(diffAlb, sh.emissive / emPeak, saturate(emPeak * 4.0f));
            }
            float react = isDielectric ? 0.32f : ((sh.matClass == MAT_SCREEN || sh.matClass == MAT_KEY_SKIRT) ? 0.20f : 0.0f);

            outDepth.write(float4(ndcDepth, 0, 0, 1), gid);
            outMotion.write(float4(motion.x, motion.y, 0, 1), gid);
            outDiffAlbedo.write(float4(diffAlb, 1.0f), gid);
            outSpecAlbedo.write(float4(f0, 1.0f), gid);
            outNormal.write(float4(sh.N, 1.0f), gid);
            outRoughness.write(float4(sh.roughness, 0, 0, 1), gid);
            outReactive.write(float4(react, 0, 0, 1), gid);
        }

        // Aerial perspective: light is lost exponentially with distance and replaced by the sky's own
        // horizon colour in that direction, so far terrain dissolves into the sky it sits under.
        if (outdoor && u.fogParams.x > 0.0f && res.distance > 400.0f) {
            float transmit = exp(-u.fogParams.x * res.distance);
            float3 hazeDir = normalize(float3(rd.x, 0.035f + max(rd.y, 0.0f) * 0.25f, rd.z));
            float3 hazeCol = sampleEnvEquirect(hazeDir, 5.0f, u, texSlots);
            radiance += throughput * hazeCol * (1.0f - transmit);
            throughput *= transmit;
        }

        float3 V = -rd;

        // Next Event Estimation (area lights), evaluated at a single call site for every material so the
        // kernel carries one copy of the light loop and its shadow ray. Unlit emitters skip it.
        bool isDielectricHit = (sh.matClass == MAT_THIN_GLASS || sh.matClass == MAT_SOLID_GLASS || sh.matClass == MAT_WATER || sh.matClass == MAT_INDIGO_RESIN);
        float3 direct = float3(0.0f);
        if (isDielectricHit || (sh.matFlags & 64) == 0) {
            float3 unusedDirection = float3(0.0f);
            direct = evaluateAllAreaLights(sh, V, bounce, rng, u, accel, vertices, indices, submeshes, instances, materials, texSlots, unusedDirection);
        }

        // 1. Dielectric Glass, Water & Translucent Indigo Resin
        if (isDielectricHit) {
            // Crisp studio light highlights right on the specular surface.
            radiance += throughput * min(direct, float3(22.0f));
            prevDiffuse = false;
            envLod = 0.0f;

            if (sh.matClass == MAT_THIN_GLASS) {
                float cosI = clamp(dot(V, sh.N), 0.0f, 1.0f);
                float F = fresnelDielectric(cosI, 1.0f / sh.ior);
                // Smooth Fresnel reflection boost for subtle double-wall glass cylinder clarity.
                float probReflect = clamp(F * 1.15f, 0.04f, 0.94f);
                if (rand01(rng) < probReflect) {
                    float3 H = sh.roughness > 0.02f ? sampleGGX_VNDF(V, sh.N, sh.roughness * sh.roughness, rand01(rng), rand01(rng)) : sh.N;
                    rd = reflect(rd, H);
                    ro = sh.worldPos + sh.Ng * ((sh.frontFace ? 0.0025f : -0.0025f) * sh.offsetEps);
                    throughput *= (F / probReflect);
                    if (bounce == 0) primarySpecularPath = true;
                } else {
                    // Thin curved soda-lime wall: edge-grazing emerald Beer-Lambert tint + mild lens refraction deflection
                    float cosTheta = max(cosI, 0.16f);
                    float effThick = sh.thickness / cosTheta;
                    float3 glassTint = exp(-sh.absorbColor * (effThick * 2.2f));
                    float3 refr = refract(rd, sh.N, 1.0f / sh.ior);
                    float3 newDir = normalize(mix(rd, length(refr) > 0.01f ? refr : rd, 0.22f));
                    rd = newDir;
                    ro = sh.worldPos + rd * 0.0025f;
                    throughput *= glassTint * ((1.0f - F) / (1.0f - probReflect));
                }
            } else {
                // Closed volumetric dielectrics (`water`, `solidGlass`, `indigoResin`)
                bool entering = sh.frontFace;
                float eta = entering ? (1.0f / sh.ior) : sh.ior;
                float cosI = clamp(abs(dot(V, sh.N)), 0.0f, 1.0f);
                float F = fresnelDielectric(cosI, eta);
                float3 refrDir = refract(rd, sh.N, eta);
                bool tir = (length(refrDir) < 0.01f);

                if (tir || rand01(rng) < F) {
                    float3 H = sh.roughness > 0.025f ? sampleGGX_VNDF(V, sh.N, sh.roughness * sh.roughness, rand01(rng), rand01(rng)) : sh.N;
                    rd = reflect(rd, H);
                    ro = sh.worldPos + sh.N * 0.0025f;
                    if (bounce == 0) primarySpecularPath = true;
                } else {
                    rd = normalize(refrDir);
                    ro = sh.worldPos - sh.N * 0.0025f;
                    if (sh.matClass == MAT_WATER) {
                        inWater = entering;
                        curAbsorb = inWater ? sh.absorbColor : float3(0.0f);
                    } else if (sh.matClass == MAT_SOLID_GLASS) {
                        inSolidGlass = entering;
                        curAbsorb = inSolidGlass ? sh.absorbColor : float3(0.0f);
                    } else {
                        inIndigo = entering;
                        curAbsorb = inIndigo ? sh.absorbColor : float3(0.0f);
                    }
                }
            }
            ++bounce;
            continue;
        }

        // 2. Opaque / Emissive / Cloth / Metal / Polymer / Screen / Keycap / Plate
        float3 em = sh.emissive;
        if (bounce > 0u) em = min(em, float3(8.0f));
        // Lamps, the monitor and the window are sampled directly as lights; a diffuse bounce that happens to
        // land on one must not add it a second time (that double count is also the main source of fireflies).
        if (!(prevDiffuse && (sh.matFlags & 256) != 0)) {
            radiance += throughput * em;
        }
        if ((sh.matFlags & 64) != 0) break;

        if (bounce > 0u) direct = min(direct, float3(writeGBuffer ? 5.0f : 9.0f));
        radiance += throughput * direct;

        // In MetalFX Gear 1 (writeGBuffer) or bit 1 interactive flag, 1 diffuse bounce captures real color bleeding; skip 2nd diffuse bounce while keeping specular/glass chains up to maxBounces.
        if ((writeGBuffer || ((u.renderFlags & 2u) != 0u)) && bounce >= 1u && prevDiffuse) break;

        // Russian Roulette after bounce 1 for fast clean convergence
        if (bounce >= 2u || (bounce >= 1u && prevDiffuse)) {
            float pSurvive = clamp(max(throughput.x, max(throughput.y, throughput.z)), 0.08f, 0.94f);
            if (rand01(rng) > pSurvive) break;
            throughput /= pSurvive;
        }

        // Importance-sample indirect bounce (VNDF GGX Specular / Cosine Diffuse / Foliage BTDF)
        float3 F0 = mix(float3(sh.f0), sh.baseColor, sh.metalness);
        float specLum = luminance(fresnelSchlick(max(dot(sh.N, V), 0.0f), F0)) + sh.clearCoat * 0.35f;
        float diffLum = luminance(sh.baseColor) * (1.0f - sh.metalness);
        float pSpec = clamp(specLum / max(specLum + diffLum, 1e-4f), 0.10f, 0.92f);

        ro = sh.worldPos + sh.Ng * ((sh.frontFace ? 0.003f : -0.003f) * sh.offsetEps);
        if (rand01(rng) < pSpec) {
            prevDiffuse = false;
            envLod = clamp(sh.roughness * 9.0f, 0.0f, 5.0f);
            float alpha = max(sh.roughness * sh.roughness, 0.002f);
            if (sh.clearCoat > 0.35f && rand01(rng) < 0.5f) {
                alpha = max(sh.clearCoatRough * sh.clearCoatRough, 0.001f);
            }
            float3 H = sampleGGX_VNDF(V, sh.N, alpha, rand01(rng), rand01(rng));
            float3 L = reflect(-V, H);
            if (dot(sh.N, L) <= 0.0f) break;
            float NdotV = max(dot(sh.N, V), 1e-4f);
            float NdotL = max(dot(sh.N, L), 1e-4f);
            float VdotH = max(dot(V, H), 1e-4f);
            float NdotH = max(dot(sh.N, H), 1e-4f);
            float3 F = fresnelSchlick(VdotH, F0);
            float Vis = V_SmithGGX(NdotV, NdotL, alpha);
            // Weight for VNDF sampling: F * (G2 / G1) approx F * (4 * VdotH * NdotL * Vis / NdotV_denom)
            float3 wSpec = F * (4.0f * Vis * VdotH * NdotL / max(NdotH, 1e-3f)) / pSpec;
            throughput *= clamp(wSpec, 0.0f, 3.5f);
            rd = L;
            if (bounce == 0) primarySpecularPath = true;
        } else if (sh.matClass == MAT_FOLIAGE && rand01(rng) < 0.28f) {
            // Translucent backlit leaf bounce
            prevDiffuse = true;
            envLod = 5.0f;
            ro = sh.worldPos - sh.Ng * 0.004f;
            rd = sampleCosineHemisphere(-sh.N, rand01(rng), rand01(rng));
            throughput *= sh.baseColor * float3(1.1f, 1.3f, 0.65f) / max(1.0f - pSpec, 0.1f);
        } else {
            prevDiffuse = true;
            envLod = 5.0f;
            float3 L = sampleCosineHemisphere(sh.N, rand01(rng), rand01(rng));
            float NdotV = max(dot(sh.N, V), 1e-4f);
            float3 kD = (1.0f - fresnelSchlick(NdotV, F0)) * (1.0f - sh.metalness);
            throughput *= clamp((kD * sh.baseColor) / max(1.0f - pSpec, 0.08f), 0.0f, 2.5f);
            rd = L;
        }
        ++bounce;
    }

    if (recordedGBuffer && writeGBuffer) {
        outSpecHitDist.write(float4(specularHitDistance, 0, 0, 1), gid);
    }
    radiance = clamp(radiance, 0.0f, 32.0f);
    outColor.write(float4(radiance, 1.0f), gid);
}

// MARK: - Progressive Linear HDR Accumulation Kernel

// The denoised frame the refinement starts from counts as this many samples. High enough that the first
// raw samples blended in never show as grain, low enough that the true samples own the final image.
constant float kSeedWeight = 24.0f;

kernel void accumulateKernel(
    uint2 gid [[thread_position_in_grid]],
    constant RTFrameUniforms& u [[buffer(0)]],
    texture2d<float, access::read> curTrace [[texture(0)]],
    texture2d<float, access::read_write> accumTex [[texture(1)]],
    texture2d<float, access::sample> mfxSeed [[texture(2)]]
) {
    if (gid.x >= u.outputSize.x || gid.y >= u.outputSize.y) return;
    float4 sampleCol = curTrace.read(gid);
    bool seededFromMFX = ((u.renderFlags & 4u) != 0u);
    if (u.sampleIndex == 0u) {
        if (seededFromMFX) {
            float2 uv = (float2(gid) + 0.5f) / max(float2(u.outputSize), float2(1.0f));
            float4 seedCol = mfxSeed.sample(kClampSamp, uv);
            float3 safeSeed = all(isfinite(seedCol.rgb)) ? max(seedCol.rgb, 0.0f) : sampleCol.rgb;
            accumTex.write(mix(float4(safeSeed, sampleCol.a), sampleCol, 1.0f / (kSeedWeight + 1.0f)), gid);
        } else {
            accumTex.write(sampleCol, gid);
        }
    } else {
        float4 prev = accumTex.read(gid);
        // Firefly guard: one stray path can be hundreds of times brighter than the pixel it lands on and
        // would sit there as a white speck for the rest of the accumulation. Bound each new sample by what
        // the pixel already holds; real highlights are bright in every sample, so they pass untouched.
        if (seededFromMFX || u.sampleIndex >= 6u) {
            float lim = luminance(prev.rgb) * 6.0f + 0.05f;
            float lum = luminance(sampleCol.rgb);
            if (lum > lim) sampleCol.rgb *= lim / lum;
        }
        float blend = seededFromMFX ? (1.0f / (kSeedWeight + float(u.sampleIndex) + 1.0f)) : u.accumulationBlend;
        float4 blended = mix(prev, sampleCol, blend);
        accumTex.write(blended, gid);
    }
}

// MARK: - Optical Bloom + ACES Filmic Tone Mapping + sRGB Composite Kernel

inline float3 acesFilmic(float3 x) {
    // Narkowicz / Hill fitted ACES curve preserving rich saturated highlights
    x *= 0.88f;
    float3 a = x * (x + 0.0245786f) - 0.000090537f;
    float3 b = x * (0.983729f * x + 0.4329510f) + 0.238081f;
    return saturate(a / b);
}

inline float3 linearToSRGB(float3 lin) {
    float3 lo = lin * 12.92f;
    float3 hi = 1.055f * pow(max(lin, float3(0.0f)), float3(1.0f / 2.4f)) - 0.055f;
    return select(hi, lo, lin <= float3(0.0031308f));
}

kernel void compositeKernel(
    uint2 gid [[thread_position_in_grid]],
    constant CompositeParams& p [[buffer(0)]],
    texture2d<float, access::sample> mfxTex [[texture(0)]],
    texture2d<float, access::read> accumTex [[texture(1)]],
    texture2d<float, access::write> outDisplay [[texture(2)]]
) {
    uint w = outDisplay.get_width();
    uint h = outDisplay.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float2 uv = (float2(gid) + 0.5f) / float2(w, h);
    float3 mfx = mfxTex.sample(kClampSamp, uv).rgb;
    float3 hdr = (p.isProgressiveOnly != 0u)
        ? accumTex.read(gid).rgb
        : ((p.progressBlend <= 0.0001f) ? mfx : mix(mfx, accumTex.read(gid).rgb, p.progressBlend));

    // Subtle soft tent bloom on bright specular highlights, bulb rim & RGB glow
    if (p.bloomStrength > 1e-4f) {
        float3 avg;
        if (p.isProgressiveOnly != 0u) {
            int2 maxC = int2(w - 1u, h - 1u);
            int2 g = int2(gid);
            float3 b0 = accumTex.read(uint2(clamp(g + int2(-3, -3), int2(0), maxC))).rgb;
            float3 b1 = accumTex.read(uint2(clamp(g + int2( 3, -3), int2(0), maxC))).rgb;
            float3 b2 = accumTex.read(uint2(clamp(g + int2(-3,  3), int2(0), maxC))).rgb;
            float3 b3 = accumTex.read(uint2(clamp(g + int2( 3,  3), int2(0), maxC))).rgb;
            float3 b4 = accumTex.read(uint2(clamp(g + int2( 0,  5), int2(0), maxC))).rgb;
            float3 b5 = accumTex.read(uint2(clamp(g + int2( 0, -5), int2(0), maxC))).rgb;
            float3 b6 = accumTex.read(uint2(clamp(g + int2( 5,  0), int2(0), maxC))).rgb;
            float3 b7 = accumTex.read(uint2(clamp(g + int2(-5,  0), int2(0), maxC))).rgb;
            avg = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + b7) * 0.125f;
        } else {
            float2 px = float2(1.0f / float(w), 1.0f / float(h)) * 3.5f;
            float3 b0 = mfxTex.sample(kClampSamp, uv + float2(-px.x, -px.y)).rgb;
            float3 b1 = mfxTex.sample(kClampSamp, uv + float2( px.x, -px.y)).rgb;
            float3 b2 = mfxTex.sample(kClampSamp, uv + float2(-px.x,  px.y)).rgb;
            float3 b3 = mfxTex.sample(kClampSamp, uv + float2( px.x,  px.y)).rgb;
            float3 b4 = mfxTex.sample(kClampSamp, uv + float2(0.0f,  px.y * 1.8f)).rgb;
            float3 b5 = mfxTex.sample(kClampSamp, uv + float2(0.0f, -px.y * 1.8f)).rgb;
            float3 b6 = mfxTex.sample(kClampSamp, uv + float2( px.x * 1.8f, 0.0f)).rgb;
            float3 b7 = mfxTex.sample(kClampSamp, uv + float2(-px.x * 1.8f, 0.0f)).rgb;
            avg = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + b7) * 0.125f;
            if (p.progressBlend > 0.0001f) {
                int2 maxC = int2(w - 1u, h - 1u);
                int2 g = int2(gid);
                float3 a0 = accumTex.read(uint2(clamp(g + int2(-3, -3), int2(0), maxC))).rgb;
                float3 a1 = accumTex.read(uint2(clamp(g + int2( 3, -3), int2(0), maxC))).rgb;
                float3 a2 = accumTex.read(uint2(clamp(g + int2(-3,  3), int2(0), maxC))).rgb;
                float3 a3 = accumTex.read(uint2(clamp(g + int2( 3,  3), int2(0), maxC))).rgb;
                float3 a4 = accumTex.read(uint2(clamp(g + int2( 0,  5), int2(0), maxC))).rgb;
                float3 a5 = accumTex.read(uint2(clamp(g + int2( 0, -5), int2(0), maxC))).rgb;
                float3 a6 = accumTex.read(uint2(clamp(g + int2( 5,  0), int2(0), maxC))).rgb;
                float3 a7 = accumTex.read(uint2(clamp(g + int2(-5,  0), int2(0), maxC))).rgb;
                float3 avgBlend = (a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7) * 0.125f;
                avg = mix(avg, avgBlend, p.progressBlend);
            }
        }
        float lum = luminance(avg);
        float softKnee = saturate((lum - 1.05f) / max(lum + 0.45f, 1e-4f));
        hdr += avg * (softKnee * p.bloomStrength);
    }

    hdr *= p.exposureScale;

    // Subtle edge vignette matching real 35mm / 50mm prime lens falloff
    float2 vUV = uv - 0.5f;
    float vig = 1.0f - dot(vUV, vUV) * p.vignetteStrength;
    hdr *= vig;

    float3 mapped = acesFilmic(hdr);
    float3 srgb = linearToSRGB(mapped);

    // Subtle sensor dither to prevent 8-bit gradient banding without temporal grain shimmer in live frames
    uint nSeed = gid.x + gid.y * 4096u + ((p.grainStrength > 1e-5f) ? p.frameIndex * 747796405u : 0u);
    uint nHash = pcgHash(nSeed);
    float n01 = float(nHash & 0xFFFFu) / 65535.0f - 0.5f;
    srgb = saturate(srgb + n01 * (1.0f / 255.0f + p.grainStrength));

    outDisplay.write(float4(srgb, 1.0f), gid);
}

// MARK: - Sub-Pixel 1-Ray Hardware BVH Node Picker

kernel void pickInstanceKernel(
    constant RTFrameUniforms& u [[buffer(0)]],
    constant float2& normPoint [[buffer(1)]], // x in [0,1] left->right, y in [0,1] top->bottom
    instance_acceleration_structure accel [[buffer(2)]],
    constant RTInstanceInfo* instances [[buffer(3)]],
    constant RTSubmesh* submeshes [[buffer(4)]],
    constant RTMaterialData* materials [[buffer(5)]],
    device PickResult* result [[buffer(6)]]
) {
    float2 ndc = float2(normPoint.x * 2.0f - 1.0f, 1.0f - normPoint.y * 2.0f);
    float3 rd = normalize(
        u.camForward.xyz
        + u.camRight.xyz * (ndc.x * u.aspect * u.tanHalfFov)
        + u.camUp.xyz * (ndc.y * u.tanHalfFov)
    );

    float3 ro = u.camPos.xyz;
    intersector<triangle_data, instancing> inter;
    inter.assume_geometry_type(geometry_type::triangle);

    uint pickedTag = 0u;
    float pickedDist = 0.0f;

    for (int hop = 0; hop < 8; ++hop) {
        ray r(ro, rd, 0.001f, 500.0f);
        auto res = inter.intersect(r, accel);
        if (res.type == intersection_type::none) break;

        RTInstanceInfo inst = instances[res.instance_id];
        RTSubmesh sub = submeshes[inst.submeshBase + res.geometry_id];
        RTMaterialData mat = materials[sub.materialIndex];
        // Skip hidden button overlays & translucent scenario sprites so interactive clicks pass through cleanly.
        if (((mat.extraTex.w & 4) != 0 && mat.baseColor.w < 0.05f) || mat.extraTex.z == MAT_EMISSIVE_CARD) {
            ro += rd * (res.distance + 0.002f);
            continue;
        }
        pickedTag = inst.nodeTag;
        pickedDist = res.distance;
        break;
    }

    result[0].nodeTag = pickedTag;
    result[0].distance = pickedDist;
}
"""#
}
