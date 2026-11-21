import Foundation

/// Kernels of the live renderer, compiled together with `RTShaders.source` (which they build on).
///
/// The path tracer estimates all lighting from random rays every frame, which is why its picture has to be
/// denoised while moving and refined when still. The live renderer splits the work the way games do:
///
/// - `lightCacheBakeKernel` works out the soft, view-independent light (area-light shadows and light bounced
///   between surfaces) at fixed points on every surface, a little each frame until it has converged.
/// - `liveKernel` draws the frame with no randomness at all: one camera ray per pixel, stored light looked
///   up at the hit, and exact mirror/refraction rays for glass and glossy surfaces.
///
/// A frame is therefore finished the moment it is drawn, moving or still.
enum RTLiveShaders {
    static let source: String = #"""

// MARK: - Baked Light Cache

struct RTLightCacheTri {
    uint sampleBase;
    uint res;
    uint instance;
    uint geomPrim;
};

struct LightCacheBakeParams {
    uint sampleOffset;
    uint sampleCount;
    uint passIndex;
    uint maxCount;
    uint passNumber;
    uint pad0;
};

// Row-major index of grid point (i, j) on a triangle split `res` times; row j holds res + 1 - j points.
inline uint lightCacheIndex(uint res, uint i, uint j) {
    return j * (res + 1u) - (j * (j + 0xFFFFFFFFu)) / 2u + i;
}

// The three stored points around a surface position and how much each counts.
struct LightCacheTap {
    uint index[3];
    float weight[3];
    bool valid;
};

inline uint lightCacheGridIndex(RTLightCacheTri tr, uint i, uint j) {
    uint jc = min(j, tr.res);
    uint ic = min(i, tr.res - jc);
    return tr.sampleBase + lightCacheIndex(tr.res, ic, jc);
}

inline LightCacheTap lightCacheTap(
    uint instID, uint geomID, uint primID, float2 bary,
    constant RTInstanceInfo* instances,
    constant RTSubmesh* submeshes,
    constant uint* indices,
    const device uint* instGeom,
    const device RTLightCacheTri* tris
) {
    LightCacheTap tap;
    RTLightCacheTri tr = tris[instGeom[instances[instID].reserved + geomID] + primID];
    tap.valid = (tr.res != 0u);
    tap.index[0] = 0u; tap.index[1] = 0u; tap.index[2] = 0u;
    tap.weight[0] = 0.0f; tap.weight[1] = 0.0f; tap.weight[2] = 0.0f;
    if (!tap.valid) return tap;
    float2 b = saturate(bary);
    if ((tr.res & 0x80000000u) != 0u) {
        // Small triangle: light is kept at its vertices and shared with the triangles around it.
        RTSubmesh sub = submeshes[instances[instID].submeshBase + geomID];
        uint o = sub.indexOffset + primID * 3u;
        tap.index[0] = tr.sampleBase + indices[o];
        tap.index[1] = tr.sampleBase + indices[o + 1u];
        tap.index[2] = tr.sampleBase + indices[o + 2u];
        tap.weight[0] = max(1.0f - b.x - b.y, 0.0f);
        tap.weight[1] = b.x;
        tap.weight[2] = b.y;
        return tap;
    }
    float x = b.x * float(tr.res);
    float y = b.y * float(tr.res);
    uint i = min(uint(x), tr.res);
    uint j = min(uint(y), tr.res);
    float fx = x - float(i);
    float fy = y - float(j);
    if (fx + fy <= 1.0f) {
        tap.index[0] = lightCacheGridIndex(tr, i, j);           tap.weight[0] = 1.0f - fx - fy;
        tap.index[1] = lightCacheGridIndex(tr, i + 1u, j);      tap.weight[1] = fx;
        tap.index[2] = lightCacheGridIndex(tr, i, j + 1u);      tap.weight[2] = fy;
    } else {
        tap.index[0] = lightCacheGridIndex(tr, i + 1u, j + 1u); tap.weight[0] = fx + fy - 1.0f;
        tap.index[1] = lightCacheGridIndex(tr, i, j + 1u);      tap.weight[1] = 1.0f - fx;
        tap.index[2] = lightCacheGridIndex(tr, i + 1u, j);      tap.weight[2] = 1.0f - fy;
    }
    return tap;
}

/// Stored light at a surface point, as the radiance a white matte surface would send back.
template <typename SampleT>
inline float3 lightCacheLookup(
    uint instID, uint geomID, uint primID, float2 bary,
    constant RTInstanceInfo* instances,
    constant RTSubmesh* submeshes,
    constant uint* indices,
    const device uint* instGeom,
    const device RTLightCacheTri* tris,
    const device SampleT* samples
) {
    LightCacheTap tap = lightCacheTap(instID, geomID, primID, bary, instances, submeshes, indices, instGeom, tris);
    if (!tap.valid) return float3(0.0f);
    return float3(samples[tap.index[0]].rgb) * tap.weight[0]
         + float3(samples[tap.index[1]].rgb) * tap.weight[1]
         + float3(samples[tap.index[2]].rgb) * tap.weight[2];
}

inline bool isDielectricClass(int matClass) {
    return matClass == MAT_THIN_GLASS || matClass == MAT_SOLID_GLASS || matClass == MAT_WATER || matClass == MAT_INDIGO_RESIN;
}

/// Direct sun or moon light on a surface a secondary ray landed on (a bounce or a reflection), as the
/// radiance a white matte surface would return. One shadow ray toward the centre of the disc.
inline float3 sunWhiteAt(
    SurfaceHit h,
    constant RTFrameUniforms& u,
    instance_acceleration_structure accel,
    constant RTVertex* vertices,
    constant uint* indices,
    constant RTSubmesh* submeshes,
    constant RTInstanceInfo* instances,
    constant RTMaterialData* materials
) {
    if (u.keyLightColor.w <= 0.5f || !any(u.keyLightColor.rgb > 1e-5f)) return float3(0.0f);
    float3 L = normalize(u.keyLightPosRadius.xyz);
    float NdotL = dot(h.N, L);
    if (NdotL <= 0.0f) return float3(0.0f);
    float3 P = h.worldPos + h.Ng * ((h.frontFace ? 0.005f : -0.005f) * h.offsetEps);
    float3 vis = evaluateShadowTransmission(P, L, 3.0e6f, u, accel, vertices, indices, submeshes, instances, materials);
    return u.keyLightColor.rgb * vis * (NdotL * INV_PI);
}

inline SurfaceHit evalBakeSurfaceHit(
    uint instID,
    uint geomID,
    uint primID,
    float2 bary,
    constant RTVertex* vertices,
    constant uint* indices,
    constant RTSubmesh* submeshes,
    constant RTInstanceInfo* instances,
    constant RTMaterialData* materials
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

    float3 wp0 = (inst.modelToWorld * float4(p0, 1.0f)).xyz;
    float3 wp1 = (inst.modelToWorld * float4(p1, 1.0f)).xyz;
    float3 wp2 = (inst.modelToWorld * float4(p2, 1.0f)).xyz;

    float3 crossG = cross(wp1 - wp0, wp2 - wp0);
    float crossLen = length(crossG);
    float3 ngRaw = (crossLen > 1e-10f) ? (crossG / crossLen) : float3(0, 1, 0);
    if ((inst.flags & 1u) != 0u) ngRaw = -ngRaw;

    float3x3 normM = float3x3(inst.normalToWorld[0].xyz, inst.normalToWorld[1].xyz, inst.normalToWorld[2].xyz);
    float3 nsWorld = normalize(normM * localNs);
    if (dot(nsWorld, ngRaw) < 0.0f) nsWorld = -nsWorld;

    bool isFoliage = (mat.extraTex.z == MAT_FOLIAGE);

    SurfaceHit sh;
    sh.worldPos = (inst.modelToWorld * float4(localPos, 1.0f)).xyz;
    sh.prevWorldPos = sh.worldPos;
    sh.Ng = ngRaw;
    sh.Ns = nsWorld;
    sh.N = nsWorld;
    sh.uv = float2(0.0f);
    sh.baseColor = float3(1.0f);
    sh.emissive = float3(0.0f);
    sh.roughness = 1.0f;
    sh.metalness = 0.0f;
    sh.clearCoat = 0.0f;
    sh.clearCoatRough = 0.85f;
    sh.ior = mat.optics.x;
    sh.subsurface = isFoliage ? 0.42f : 0.0f;
    sh.sheen = 0.0f;
    sh.opacity = 1.0f;
    sh.absorbColor = float3(0.0f);
    sh.thickness = 0.0f;
    sh.matClass = isFoliage ? MAT_FOLIAGE : MAT_STANDARD;
    sh.matFlags = isFoliage ? 1 : 0;
    sh.frontFace = true;
    sh.f0 = 0.0f;
    sh.offsetEps = 1.0f + length(sh.worldPos) * 0.004f;
    return sh;
}

kernel void lightCacheBakeKernel(
    uint2 gid [[thread_position_in_grid]],
    constant RTFrameUniforms& u [[buffer(0)]],
    instance_acceleration_structure accel [[buffer(1)]],
    constant RTVertex* vertices [[buffer(2)]],
    constant uint* indices [[buffer(3)]],
    constant RTSubmesh* submeshes [[buffer(4)]],
    constant RTInstanceInfo* instances [[buffer(5)]],
    constant RTMaterialData* materials [[buffer(6)]],
    constant RTTextureSlot* texSlots [[buffer(7)]],
    constant LightCacheBakeParams& p [[buffer(8)]],
    const device uint* instGeom [[buffer(9)]],
    const device RTLightCacheTri* tris [[buffer(10)]],
    const device uint* sampleTri [[buffer(11)]],
    device half4* samples [[buffer(12)]],
    device half4* directions [[buffer(13)]],
    device half4* deskSamples [[buffer(14)]],
    device ushort* sampleCounts [[buffer(15)]]
) {
    uint local = gid.y * 4096u + gid.x;
    if (local >= p.sampleCount) return;
    uint s = p.sampleOffset + local;

    uint owner = sampleTri[s];
    if (owner == 0xFFFFFFFFu) return;
    RTLightCacheTri tr = tris[owner & 0x3FFFFFFFu];
    if (tr.res == 0u) return;

    float2 bary;
    if ((tr.res & 0x80000000u) != 0u) {
        // A vertex point: the corner of its triangle named in the top two bits.
        uint corner = owner >> 30;
        bary = float2(corner == 1u ? 1.0f : 0.0f, corner == 2u ? 1.0f : 0.0f);
    } else {
        // Which grid point of the triangle this is.
        uint k = s - tr.sampleBase;
        float a = float(2u * tr.res + 3u);
        uint j = uint(max(0.0f, (a - sqrt(max(a * a - 8.0f * float(k), 0.0f))) * 0.5f));
        j = min(j, tr.res);
        while (j > 0u && lightCacheIndex(tr.res, 0u, j) > k) j -= 1u;
        while (j < tr.res && lightCacheIndex(tr.res, 0u, j + 1u) <= k) j += 1u;
        uint i = k - lightCacheIndex(tr.res, 0u, j);
        bary = float2(float(i), float(j)) / float(tr.res);
    }
    // Pulled a hair toward the centre so points on edges and corners do not start inside the neighbour.
    bary = mix(bary, float2(1.0f / 3.0f), 0.012f);

    // A white, fully matte stand-in: what the lights return for it is the stored quantity itself.
    // Foliage keeps MAT_FOLIAGE + subsurface so thin leaves gather both direct front/back light wrap.
    SurfaceHit sh = evalBakeSurfaceHit(
        tr.instance, tr.geomPrim >> 24, tr.geomPrim & 0xFFFFFFu, bary,
        vertices, indices, submeshes, instances, materials
    );
    float3 N = sh.Ns;

    uint prevCount = (p.maxCount > 1u) ? uint(sampleCounts[s]) : 0u;
    float3 prevRGB = (prevCount > 0u) ? float3(samples[s].rgb) : float3(0.0f);
    uint qmcStep = p.passNumber;
    uint rng = pcgHash(s * 9781u + p.passIndex * 26699u + 17u);

    // Direct light from the sun or key light and the lamps (except the desk lamp, which is baked into
    // `deskSamples` as unit white so colour, brightness and power toggle immediately at render time).
    // Alongside the amount of light, keep where it mostly comes from (brightness-weighted direction), so
    // bumps and weave in a surface's normal map can be shaded by it later.
    float3 direction = float3(0.0f);
    float3 value = evaluateAllAreaLights(sh, N, 0u, rng, u, accel, vertices, indices, submeshes, instances, materials, texSlots, direction, true);
    float3 valueDesk = evaluateDeskLampUnit(sh, N, rng, u, accel, vertices, indices, submeshes, instances, materials);

    // One bounce of everything else. Stratified per-point R2 progression reduces blotchiness in fewer passes.
    uint bounceSeed = pcgHash(s * 2654435761u + 374761393u);
    float u1 = fract(float(bounceSeed & 0xFFFFu) / 65536.0f + float(qmcStep) * 0.7548776662f);
    float u2 = fract(float(bounceSeed >> 16) / 65536.0f + float(qmcStep) * 0.5698402910f);
    float3 rd = sampleCosineHemisphere(N, u1, u2);
    float3 ro = sh.worldPos + sh.Ng * (0.006f * sh.offsetEps);
    float3 throughput = float3(1.0f);
    intersector<triangle_data, instancing> inter;
    inter.assume_geometry_type(geometry_type::triangle);
    for (int hop = 0; hop < 4; ++hop) {
        ray r(ro, rd, 0.0015f, 4.0e6f);
        auto res = inter.intersect(r, accel, 0xFDu);
        if (res.type == intersection_type::none) {
            float3 sky = throughput * min(sampleEnvEquirect(rd, 5.0f, u, texSlots), float3(18.0f));
            value += sky;
            direction += rd * luminance(sky);
            break;
        }
        SurfaceHit h = evalSurfaceHit(
            res.instance_id, res.geometry_id, res.primitive_id, res.triangle_barycentric_coord,
            rd, res.distance, false, u, vertices, indices, submeshes, instances, materials, texSlots
        );
        bool hiddenOverlay = ((h.matFlags & 4) != 0 && h.opacity < 0.05f);
        if (hiddenOverlay || isDielectricClass(h.matClass)) {
            // Glass lets bounced light through, tinted; it is not a matte surface to gather from.
            if (!hiddenOverlay) throughput *= exp(-h.absorbColor * 0.35f) * 0.96f;
            ro = h.worldPos + rd * 0.003f;
            continue;
        }
        if (h.matClass == MAT_FOLIAGE && hop < 3 && (pcgHash(rng + uint(hop) * 7919u) & 3u) == 0u) {
            // Thin canopy transmission keeps overlapping Pothos/Bamboo clusters softly backlit in live view.
            throughput *= h.baseColor * float3(0.95f, 1.15f, 0.55f);
            ro = h.worldPos + rd * 0.003f;
            continue;
        }
        // Lamps, monitor, window and live keyboard RGB are shaded dynamically rather than baked into static light.
        bool dynamicLight = ((h.matFlags & 256) != 0) || h.matClass == MAT_KEY_SKIRT || h.matClass == MAT_KEY_PLATE;
        float3 leaving = dynamicLight ? float3(0.0f) : min(h.emissive, float3(8.0f));
        if ((h.matFlags & 64) == 0) {
            leaving += h.baseColor * lightCacheLookup(res.instance_id, res.geometry_id, res.primitive_id,
                                                      res.triangle_barycentric_coord, instances, submeshes, indices, instGeom, tris, samples);
            leaving += h.baseColor * sunWhiteAt(h, u, accel, vertices, indices, submeshes, instances, materials);
            // The lamp's own head sits a hand's width from the bulb and is many times brighter than anything
            // else it lights. A bounce ray only finds it now and then, which leaves isolated bright dots on
            // the wall and mat, so the head is left out and any one bounce is held to desk-surface levels.
            float3 fromBulb = h.worldPos - u.deskBulbPosRadius.xyz;
            if (dot(fromBulb, fromBulb) > 36.0f) {
                valueDesk += min(throughput * h.baseColor * lightCacheLookup(
                    res.instance_id, res.geometry_id, res.primitive_id,
                    res.triangle_barycentric_coord, instances, submeshes, indices, instGeom, tris, deskSamples
                ), float3(0.05f));
            }
        }
        value += throughput * leaving;
        direction += rd * luminance(throughput * leaving);
        break;
    }

    float peak = max(value.r, max(value.g, value.b));
    if (peak > 48.0f) {
        value *= 48.0f / peak;
        direction *= 48.0f / peak;
    }
    valueDesk = min(valueDesk, float3(48.0f));
    uint clampedN = min(prevCount, p.maxCount - 1u);
    float n = float(clampedN);
    float3 avgRGB = (prevRGB * n + value) / (n + 1.0f);
    samples[s] = half4(half3(min(avgRGB, float3(65000.0f))), half(0.0f));
    sampleCounts[s] = ushort(min(clampedN + 1u, 65535u));
    float3 prevDirection = (p.maxCount > 1u) ? float3(directions[s].xyz) : float3(0.0f);
    directions[s] = half4(float4((prevDirection * n + direction) / (n + 1.0f), 0.0f));
    float3 prevDesk = (p.maxCount > 1u) ? float3(deskSamples[s].rgb) : float3(0.0f);
    deskSamples[s] = half4(float4((prevDesk * n + valueDesk) / (n + 1.0f), 0.0f));
}

// MARK: - Live Shading Helpers

// Smooth 3D value noise in 0...1: a random value per lattice cell, blended between neighbours.
inline float smoothNoise3(float3 p) {
    float3 cell = floor(p);
    float3 f = p - cell;
    f = f * f * (3.0f - 2.0f * f);
    float n000 = hash33(cell).x;
    float n100 = hash33(cell + float3(1, 0, 0)).x;
    float n010 = hash33(cell + float3(0, 1, 0)).x;
    float n110 = hash33(cell + float3(1, 1, 0)).x;
    float n001 = hash33(cell + float3(0, 0, 1)).x;
    float n101 = hash33(cell + float3(1, 0, 1)).x;
    float n011 = hash33(cell + float3(0, 1, 1)).x;
    float n111 = hash33(cell + float3(1, 1, 1)).x;
    return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
               mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

/// Nothing handled every day is evenly glossy: glass, lacquer and polished plastic carry faint smears and
/// patches where the sheen is duller. This varies the roughness of glossy surfaces slowly across them,
/// which breaks up reflections the way fingerprints and dust do. The pattern is fixed to the surface and
/// far larger than a pixel, so it does not shimmer when the camera moves.
inline void applySurfaceWear(thread SurfaceHit& sh) {
    bool glossy = sh.roughness < 0.34f || sh.clearCoat > 0.3f;
    if (!glossy || isDielectricClass(sh.matClass) || sh.matClass == MAT_FOLIAGE) return;
    float broad = smoothNoise3(sh.worldPos * 0.55f + 11.3f);
    float streak = smoothNoise3(sh.worldPos * float3(2.6f, 2.6f, 0.9f) + 4.1f);
    float wear = saturate(broad * 0.65f + streak * 0.55f - 0.42f);
    sh.roughness = min(sh.roughness + wear * 0.12f, 0.99f);
    sh.clearCoatRough = min(sh.clearCoatRough + wear * 0.16f, 0.85f);
}


inline float3 evaluateSpecularBSDF(
    float3 V, float3 L, float3 N, float3 albedo,
    float roughness, float metalness, float clearCoat, float clearCoatRough, float dielectricF0
) {
    float NdotL = max(dot(N, L), 0.0f);
    float NdotV = max(dot(N, V), 1e-4f);
    if (NdotL <= 0.0f) return float3(0.0f);
    float3 hSum = V + L;
    float3 H = (dot(hSum, hSum) > 1e-8f) ? normalize(hSum) : N;
    float NdotH = max(dot(N, H), 0.0f);
    float VdotH = max(dot(V, H), 0.0f);
    float3 F0 = mix(float3(dielectricF0), albedo, metalness);
    float3 F = fresnelSchlick(VdotH, F0);
    float alpha = max(roughness * roughness, 0.002f);
    float3 spec = F * (D_GGX(NdotH, alpha) * V_SmithGGX(NdotV, NdotL, alpha));
    if (clearCoat > 0.01f) {
        float ccAlpha = max(clearCoatRough * clearCoatRough, 0.001f);
        float Fc = fresnelSchlick(VdotH, float3(0.04f)).x * clearCoat;
        spec = spec * (1.0f - Fc * 0.65f) + float3(Fc * D_GGX(NdotH, ccAlpha) * V_SmithGGX(NdotV, NdotL, ccAlpha));
    }
    return spec * NdotL;
}

inline float3 evalDielectricHighlight(float3 V, float3 L, SurfaceHit sh, float3 rad) {
    float NdotL = max(dot(sh.N, L), 0.0f);
    float NdotV = max(dot(sh.N, V), 1e-4f);
    if (NdotL <= 0.0f) return float3(0.0f);
    float3 hSum = V + L;
    float3 H = (dot(hSum, hSum) > 1e-8f) ? normalize(hSum) : sh.N;
    float NdotH = max(dot(sh.N, H), 0.0f);
    float VdotH = max(dot(V, H), 0.0f);
    float F0 = pow((1.0f - sh.ior) / (1.0f + sh.ior), 2.0f);
    float3 F = fresnelSchlick(VdotH, float3(F0));
    float a = max(sh.roughness * sh.roughness, 0.0005f);
    return rad * F * (D_GGX(NdotH, a) * V_SmithGGX(NdotV, NdotL, a) * NdotL);
}

inline float3 evalKeyAndLampSpecular(
    SurfaceHit sh, float3 V, float storedLum, bool isDielectric, thread float3& sunWhite,
    constant RTFrameUniforms& u,
    instance_acceleration_structure accel,
    constant RTVertex* vertices,
    constant uint* indices,
    constant RTSubmesh* submeshes,
    constant RTInstanceInfo* instances,
    constant RTMaterialData* materials
) {
    float3 out = float3(0.0f);

    // Key light highlight: exact position, single shared shadow ray toward its centre.
    {
        float3 L = float3(0.0f, 1.0f, 0.0f);
        float3 rad = float3(0.0f);
        float maxDist = 0.0f;
        float3 P = sh.worldPos + sh.Ng * ((sh.frontFace ? 0.005f : -0.005f) * sh.offsetEps);
        if (u.keyLightColor.w > 0.5f) {
            L = normalize(u.keyLightPosRadius.xyz);
            rad = u.keyLightColor.rgb;
            maxDist = 3.0e6f;
            if (u.windowOrigin.w > 0.5f) {
                float3 winN = cross(u.windowU.xyz, u.windowV.xyz);
                float denom = dot(L, winN);
                float tHit = (abs(denom) > 1e-4f) ? dot(u.windowOrigin.xyz - P, winN) / denom : -1.0f;
                if (tHit <= 0.05f) {
                    rad = float3(0.0f);
                } else {
                    float3 q = P + L * tHit - u.windowOrigin.xyz;
                    rad *= windowPaneMask(dot(q, u.windowU.xyz), dot(q, u.windowV.xyz), u.windowU.w, u.windowV.w);
                    maxDist = tHit - 0.05f;
                }
            }
        } else if (any(u.keyLightColor.rgb > 1e-4f)) {
            float3 toLight = u.keyLightPosRadius.xyz - P;
            float dist = length(toLight);
            L = toLight / max(dist, 1e-4f);
            rad = u.keyLightColor.rgb * 1.45f;
            maxDist = min(dist, 420.0f);
        }
        // A directional sun or moon is not in the stored light: its matte light is added here from the same
        // shadow ray as its highlight, which is what keeps cast shadows crisp instead of smeared.
        bool liveSun = (u.keyLightColor.w > 0.5f);
        float NdotL = dot(sh.N, L);
        // A leaf lit from behind glows: part of the sun passes through, picking up the leaf's yellow-green.
        if (liveSun && sh.matClass == MAT_FOLIAGE && NdotL <= 0.0f && any(rad > 1e-5f)) {
            float3 behind = sh.worldPos - sh.N * (0.006f * sh.offsetEps);
            float3 vis = evaluateShadowTransmission(behind, L, maxDist, u, accel, vertices, indices, submeshes, instances, materials);
            sunWhite = rad * vis * (-NdotL * INV_PI) * float3(0.30f, 0.36f, 0.13f);
        }
        if (any(rad > 1e-5f) && NdotL > 0.0f) {
            float3 spec = isDielectric
                ? evalDielectricHighlight(V, L, sh, rad)
                : evaluateSpecularBSDF(V, L, sh.N, sh.baseColor, max(sh.roughness, sh.matClass == MAT_FOLIAGE ? 0.46f : 0.06f), sh.metalness,
                                       sh.clearCoat, sh.clearCoatRough, sh.f0) * rad;
            if (liveSun || any(spec > 1e-4f)) {
                float3 vis = evaluateShadowTransmission(P, L, maxDist, u, accel, vertices, indices, submeshes, instances, materials);
                out += min(spec * vis, float3(16.0f));
                if (liveSun) sunWhite = rad * vis * (NdotL * INV_PI);
            }
        }
    }

    // Desk lamp highlight without extra shadow rays.
    if (u.deskBulbColor.w > 0.01f) {
        float3 lampPos = u.deskBulbPosRadius.xyz;
        float lampRadius = u.deskBulbPosRadius.w;
        float3 toL = lampPos - sh.worldPos;
        float dist = length(toL);
        if (dist < 42.0f) {
            float3 L = toL / max(dist, 1e-3f);
            float NdotL = dot(sh.N, L);
            if (NdotL > 0.0f) {
                float3 rad = u.deskBulbColor.rgb * (saturate(L.y * 1.35f + 0.45f) / (1.0f + dist * dist * 0.032f));
                float radLum = luminance(rad);
                if (radLum >= 1e-4f) {
                    float alpha = max(sh.roughness * sh.roughness, 0.004f);
                    float wide = saturate(alpha + lampRadius / max(2.0f * dist, 1e-3f));
                    float3 spec = isDielectric
                        ? evalDielectricHighlight(V, L, sh, rad)
                        : evaluateSpecularBSDF(V, L, sh.N, sh.baseColor, sqrt(wide), sh.metalness,
                                               sh.clearCoat, max(sh.clearCoatRough, sqrt(saturate(lampRadius / max(2.0f * dist, 1e-3f)))), sh.f0) * rad;
                    float reach = isDielectric ? 0.90f : saturate(storedLum / max(radLum * max(NdotL, 0.05f) * INV_PI * 0.6f, 1e-4f));
                    out += min(spec * reach, float3(12.0f));
                }
            }
        }
    }

    return out;
}

inline float3 traceReflectionRay(
    float3 reflOrigin, float3 reflDir, float reflLod,
    constant RTFrameUniforms& u,
    thread intersector<triangle_data, instancing>& reflInter,
    instance_acceleration_structure accel,
    constant RTVertex* vertices,
    constant uint* indices,
    constant RTSubmesh* submeshes,
    constant RTInstanceInfo* instances,
    constant RTMaterialData* materials,
    constant RTTextureSlot* texSlots,
    const device uint* instGeom,
    const device RTLightCacheTri* tris,
    const device half4* samples,
    const device half4* deskSamples
) {
    float3 seen = float3(0.0f);
    float3 through = float3(1.0f);
    float3 o = reflOrigin;
    for (int hop = 0; hop < 3; ++hop) {
        ray r(o, reflDir, 0.0015f, 4.0e6f);
        auto res = reflInter.intersect(r, accel, 0xFDu);
        if (res.type == intersection_type::none) {
            seen += through * min(sampleEnvEquirect(reflDir, reflLod, u, texSlots), float3(18.0f));
            break;
        }
        SurfaceHit h = evalSurfaceHit(
            res.instance_id, res.geometry_id, res.primitive_id, res.triangle_barycentric_coord,
            reflDir, res.distance, false, u, vertices, indices, submeshes, instances, materials, texSlots
        );
        bool hiddenOverlay = ((h.matFlags & 4) != 0 && h.opacity < 0.05f);
        if (hiddenOverlay || isDielectricClass(h.matClass)) {
            if (!hiddenOverlay) through *= exp(-h.absorbColor * 0.35f) * 0.96f;
            o = h.worldPos + reflDir * 0.003f;
            continue;
        }
        float3 leaving = h.emissive;
        if ((h.matFlags & 64) == 0) {
            float3 cacheLight = lightCacheLookup(res.instance_id, res.geometry_id, res.primitive_id,
                                                 res.triangle_barycentric_coord, instances, submeshes, indices, instGeom, tris, samples);
            if (u.deskBulbColor.w > 0.01f) {
                cacheLight += u.deskBulbColor.rgb * lightCacheLookup(
                    res.instance_id, res.geometry_id, res.primitive_id,
                    res.triangle_barycentric_coord, instances, submeshes, indices, instGeom, tris, deskSamples
                );
            }
            leaving += h.baseColor * cacheLight;
            leaving += h.baseColor * sunWhiteAt(h, u, accel, vertices, indices, submeshes, instances, materials);
        }
        seen += through * leaving;
        break;
    }
    return min(seen, float3(24.0f));
}

// MARK: - Live Frame

kernel void liveKernel(
    uint2 gid [[thread_position_in_grid]],
    constant RTFrameUniforms& u [[buffer(0)]],
    instance_acceleration_structure accel [[buffer(1)]],
    constant RTVertex* vertices [[buffer(2)]],
    constant uint* indices [[buffer(3)]],
    constant RTSubmesh* submeshes [[buffer(4)]],
    constant RTInstanceInfo* instances [[buffer(5)]],
    constant RTMaterialData* materials [[buffer(6)]],
    constant RTTextureSlot* texSlots [[buffer(7)]],
    const device uint* instGeom [[buffer(9)]],
    const device RTLightCacheTri* tris [[buffer(10)]],
    const device half4* samples [[buffer(12)]],
    const device half4* directions [[buffer(13)]],
    const device half4* deskSamples [[buffer(14)]],
    texturecube<float> bgCubemap [[texture(0)]],
    texture2d<float, access::write> outColor [[texture(1)]],
    texture2d<float, access::write> outDepth [[texture(2)]],
    texture2d<float, access::write> outMotion [[texture(3)]]
) {
    if (gid.x >= u.renderSize.x || gid.y >= u.renderSize.y) return;

    float2 resF = float2(u.renderSize);
    float2 pix = float2(gid) + 0.5f + u.jitter;
    float2 ndc = float2((pix.x / resF.x) * 2.0f - 1.0f, 1.0f - (pix.y / resF.y) * 2.0f);
    float3 ro = u.camPos.xyz;
    float3 rd = normalize(u.camForward.xyz
                          + u.camRight.xyz * (ndc.x * u.aspect * u.tanHalfFov)
                          + u.camUp.xyz * (ndc.y * u.tanHalfFov));

    float3 radiance = float3(0.0f);
    float3 throughput = float3(1.0f);
    bool wroteGBuffer = false;
    bool straight = true;       // nothing has bent the view yet, so a miss shows the real backdrop
    bool inWater = false;
    bool inSolidGlass = false;
    bool inIndigo = false;
    float3 waterAbsorb = float3(0.0f);
    float3 glassAbsorb = float3(0.0f);
    float3 indigoAbsorb = float3(0.0f);
    bool outdoor = (u.isRoomScenario == 0u);

    // The first glossy surface or pane of glass the view meets gets reflection rays, traced after the loop.
    bool hasReflection = false;
    float3 reflOrigin = float3(0.0f);
    float3 reflDir = float3(0.0f, 1.0f, 0.0f);
    float3 reflNormal = float3(0.0f, 1.0f, 0.0f);
    float3 reflWeight = float3(0.0f);
    float reflLod = 0.0f;
    float reflSatin = 0.0f;

    intersector<triangle_data, instancing> inter;
    inter.assume_geometry_type(geometry_type::triangle);

    uint passes = 0u;
    for (uint seg = 0u; seg < 9u; ) {
        ray r(ro, rd, 0.0015f, 4.0e6f);
        auto res = inter.intersect(r, accel, 0xFFu);

        if (res.type == intersection_type::none) {
            float3 env = straight ? samplePrimaryMiss(rd, u, texSlots, bgCubemap) : sampleEnvEquirect(rd, 0.0f, u, texSlots);
            if (!straight && seg >= 8u) env *= 0.65f;
            radiance += throughput * env;
            if (!wroteGBuffer) {
                wroteGBuffer = true;
                // The sky still turns with the camera: reproject a far point so anti-aliasing can follow it.
                float4 prevClip = u.prevViewProj * float4(u.camPos.xyz + rd * 1.0e5f, 1.0f);
                float2 prevNDC = prevClip.xy / max(prevClip.w, 1e-4f);
                float2 prevPix = float2(prevNDC.x * 0.5f + 0.5f, 0.5f - prevNDC.y * 0.5f) * resF;
                outDepth.write(float4(1.0f, 0.0f, 0.0f, 1.0f), gid);
                outMotion.write(float4(prevPix - pix, 0.0f, 1.0f), gid);
            }
            break;
        }

        if (inWater || inSolidGlass || inIndigo) {
            float3 activeAbsorb = inSolidGlass ? glassAbsorb : (inWater ? waterAbsorb : indigoAbsorb);
            throughput *= exp(-activeAbsorb * min(res.distance, 8.0f));
        }

        SurfaceHit sh = evalSurfaceHit(
            res.instance_id, res.geometry_id, res.primitive_id, res.triangle_barycentric_coord,
            rd, res.distance, straight, u, vertices, indices, submeshes, instances, materials, texSlots
        );
        if (straight) applySurfaceWear(sh);

        // Hidden button overlays: pass straight through.
        if ((sh.matFlags & 4) != 0 && sh.opacity < 0.05f) {
            ro = sh.worldPos + rd * 0.002f;
            if (++passes < 16u) continue;
            break;
        }

        // Glow cards (particles, subtle sky accents): blended in without stopping the view.
        if (sh.matClass == MAT_EMISSIVE_CARD) {
            float effA = saturate(sh.opacity);
            if ((sh.matFlags & 32) != 0) {
                radiance += throughput * sh.emissive * effA;
            } else {
                float3 keyDir = normalize(u.keyLightPosRadius.xyz - sh.worldPos);
                float keyTerm = 0.35f + 0.55f * abs(dot(sh.N, keyDir));
                radiance += throughput * (sh.baseColor * keyTerm + sh.emissive * 0.65f) * effA;
                throughput *= (1.0f - effA);
            }
            ro = sh.worldPos + rd * 0.0025f;
            if (max(throughput.x, max(throughput.y, throughput.z)) < 0.002f || ++passes >= 16u) break;
            continue;
        }

        if (!wroteGBuffer) {
            wroteGBuffer = true;
            float4 clipPos = u.viewToClip * (u.worldToView * float4(sh.worldPos, 1.0f));
            float4 prevClip = u.prevViewProj * float4(sh.prevWorldPos, 1.0f);
            float2 prevNDC = prevClip.xy / max(prevClip.w, 1e-4f);
            float2 prevPix = float2(prevNDC.x * 0.5f + 0.5f, 0.5f - prevNDC.y * 0.5f) * resF;
            outDepth.write(float4(saturate(clipPos.z / max(clipPos.w, 1e-4f)), 0.0f, 0.0f, 1.0f), gid);
            outMotion.write(float4(prevPix - pix, 0.0f, 1.0f), gid);
        }

        // Aerial perspective, as in the path tracer.
        if (outdoor && u.fogParams.x > 0.0f && res.distance > 400.0f) {
            float transmit = exp(-u.fogParams.x * res.distance);
            float3 hazeDir = normalize(float3(rd.x, 0.035f + max(rd.y, 0.0f) * 0.25f, rd.z));
            radiance += throughput * sampleEnvEquirect(hazeDir, 5.0f, u, texSlots) * (1.0f - transmit);
            throughput *= transmit;
        }

        float3 V = -rd;
        bool isDiel = isDielectricClass(sh.matClass);

        // Opaque surface: the view ends here if unlit constant emitter.
        if (!isDiel && (sh.matFlags & 64) != 0) {
            radiance += throughput * sh.emissive;
            break;
        }

        float3 stored = float3(0.0f);
        float3 storedDir = float3(0.0f);
        if (!isDiel) {
            LightCacheTap tap = lightCacheTap(res.instance_id, res.geometry_id, res.primitive_id,
                                              res.triangle_barycentric_coord, instances, submeshes, indices, instGeom, tris);
            if (tap.valid) {
                float3 deskIrrad = float3(0.0f);
                for (int k = 0; k < 3; ++k) {
                    stored += float3(samples[tap.index[k]].rgb) * tap.weight[k];
                    storedDir += float3(directions[tap.index[k]].xyz) * tap.weight[k];
                    deskIrrad += float3(deskSamples[tap.index[k]].rgb) * tap.weight[k];
                }
                if (u.deskBulbColor.w > 0.01f) {
                    float3 deskContrib = deskIrrad * u.deskBulbColor.rgb;
                    stored += deskContrib;
                    float3 toDesk = u.deskBulbPosRadius.xyz - sh.worldPos;
                    float toDeskLen = length(toDesk);
                    if (toDeskLen > 1e-4f) {
                        storedDir += (toDesk / toDeskLen) * luminance(deskContrib);
                    }
                }
            }
        }
        if (!straight && seg >= 8u) stored *= 0.80f;
        float storedLum = luminance(stored);

        // Single shared key-light + lamp specular block for outer dielectrics and opaque surfaces.
        float3 sunWhite = float3(0.0f);
        float3 directSpec = (isDiel && seg > 1u)
            ? float3(0.0f)
            : evalKeyAndLampSpecular(sh, V, storedLum, isDiel, sunWhite, u, accel, vertices, indices, submeshes, instances, materials);

        // Photographed ground: this disc shows the panorama as seen from where it was taken, so the grass,
        // sand or snow in the photo carries on right up to the desk legs. Stored sky light plus the live sun
        // say how much of the photo's own light reaches each point, which lays the desk's shadows onto it.
        if ((sh.matFlags & 512) != 0 && u.groundProjection.w > 0.0f) {
            float3 fromCapture = normalize(sh.worldPos - u.groundProjection.xyz);
            float distXZ = length(sh.worldPos.xz - u.groundProjection.xz);
            float3 groundDir = normalize(mix(fromCapture, rd, smoothstep(140.0f, 1200.0f, distXZ)));
            float3 photo = sampleEnvEquirect(groundDir, 0.0f, u, texSlots);
            float open = clamp((storedLum + luminance(sunWhite)) / u.groundProjection.w, 0.0f, 1.12f);
            // The photo already holds the ground's own shading, and real shade outdoors is never black:
            // light from the open sky and from sunlit ground around it fills in. A shadow that falls all
            // the way to black on a photograph is what makes it look pasted on.
            float shade = mix(0.20f + 0.80f * open, 1.0f, smoothstep(110.0f, 520.0f, distXZ));
            // Close to the camera the panorama is enlarged many times and turns smooth. A little fixed
            // fine-grained variation, fading out with distance before it could get smaller than a pixel,
            // gives grass, sand and snow back some of the bite the enlargement took away.
            float nearFade = saturate(1.0f - res.distance / 150.0f);
            float grainSize = res.distance * (2.0f * u.tanHalfFov / float(max(u.renderSize.y, 1u)));
            float fineFade = saturate(1.0f - grainSize * 9.0f);
            float coarseFade = saturate(1.0f - grainSize * 2.5f);
            float grain = (smoothNoise3(sh.worldPos * 5.3f) - 0.5f) * 0.17f * fineFade
                        + (smoothNoise3(sh.worldPos * 1.4f + 7.7f) - 0.5f) * 0.14f * coarseFade;
            radiance += throughput * photo * shade * (1.0f + grain * nearFade);
            break;
        }

        // Glass, water, resin: the view carries on through, refracted and tinted.
        if (isDiel) {
            radiance += throughput * min(directSpec, float3(22.0f));
            if (sh.matClass == MAT_THIN_GLASS) {
                float cosI = clamp(dot(V, sh.N), 0.0f, 1.0f);
                float F = fresnelDielectric(cosI, 1.0f / sh.ior);
                if (!hasReflection) {
                    hasReflection = true;
                    reflOrigin = sh.worldPos + sh.Ng * ((sh.frontFace ? 0.0025f : -0.0025f) * sh.offsetEps);
                    reflDir = reflect(rd, sh.N);
                    reflNormal = sh.N;
                    reflWeight = throughput * F;
                    reflLod = clamp(sh.roughness * 9.0f, 0.0f, 5.0f);
                }
                float effThick = sh.thickness / max(cosI, 0.16f);
                float3 refr = refract(rd, sh.N, 1.0f / sh.ior);
                rd = normalize(mix(rd, length(refr) > 0.01f ? refr : rd, 0.22f));
                ro = sh.worldPos + rd * 0.0025f;
                throughput *= exp(-sh.absorbColor * (effThick * 2.2f)) * (1.0f - F);
            } else {
                bool entering = sh.frontFace;
                float eta = entering ? (1.0f / sh.ior) : sh.ior;
                float cosI = clamp(abs(dot(V, sh.N)), 0.0f, 1.0f);
                float F = fresnelDielectric(cosI, eta);
                float3 refrDir = refract(rd, sh.N, eta);
                if (length(refrDir) < 0.01f) {
                    rd = reflect(rd, sh.N);
                    ro = sh.worldPos + sh.N * 0.0025f;
                } else {
                    if (!hasReflection && (entering || F > 0.04f)) {
                        hasReflection = true;
                        reflOrigin = sh.worldPos + sh.N * 0.0025f;
                        reflDir = reflect(rd, sh.N);
                        reflNormal = sh.N;
                        reflWeight = throughput * F;
                        reflLod = clamp(sh.roughness * 9.0f, 0.0f, 5.0f);
                    }
                    throughput *= (1.0f - F);
                    rd = normalize(refrDir);
                    ro = sh.worldPos - sh.N * 0.0025f;
                    if (sh.matClass == MAT_WATER) {
                        inWater = entering;
                        if (entering) waterAbsorb = sh.absorbColor;
                    } else if (sh.matClass == MAT_SOLID_GLASS) {
                        inSolidGlass = entering;
                        if (entering) glassAbsorb = sh.absorbColor;
                    } else {
                        inIndigo = entering;
                        if (entering) indigoAbsorb = sh.absorbColor;
                    }
                }
            }
            straight = false;
            ++seg;
            continue;
        }

        // Surface relief. The light was stored for the smooth surface; the normal map tilts each texel toward
        // or away from where that light mostly comes from, which is what makes grain, weave and pores read
        // as depth instead of a flat print. The more one-directional the light, the stronger the effect.
        float3 smoothN = sh.frontFace ? sh.Ns : -sh.Ns;
        float dirLen = length(storedDir);
        float relief = 1.0f;
        if (dirLen > 1e-5f && storedLum > 1e-5f) {
            float3 D = storedDir / dirLen;
            float directionality = saturate(dirLen / storedLum);
            float base = max(dot(smoothN, D), 0.55f);
            // Kept gentle. With the lamp skimming low across the mat this term was doubling and halving
            // the light texel by texel, which turned a fine cloth weave into coarse sandpaper grain.
            relief = clamp(1.0f + 0.45f * directionality * (dot(sh.N, D) - dot(smoothN, D)) / base, 0.82f, 1.18f);
            if (sh.matClass == MAT_FOLIAGE) relief = clamp(relief, 0.76f, 1.32f);
        }
        float NdotV = max(dot(sh.N, V), 1e-4f);
        float3 F0 = mix(float3(sh.f0), sh.baseColor, sh.metalness);
        float3 Fr = F0 + (max(float3(1.0f - sh.roughness), F0) - F0) * pow(1.0f - NdotV, 5.0f);
        bool hasCoat = (sh.clearCoat > 0.01f);
        float coatF = hasCoat ? (0.04f + 0.96f * pow(1.0f - NdotV, 5.0f)) * sh.clearCoat : 0.0f;
        float3 kD = (1.0f - Fr) * (1.0f - sh.metalness) * (1.0f - coatF * 0.65f);

        // Live animated RGB spill from mipmapped plateGlowTexture so static and animated effects reflect on keycaps, bezel and desk mat.
        float3 liveSpill = float3(0.0f);
        if (u.plateGlowTexIndex >= 0 && sh.matClass != MAT_KEY_SKIRT && sh.matClass != MAT_KEY_PLATE) {
            float3 kPos = (u.worldToKeyboard * float4(sh.worldPos, 1.0f)).xyz;
            float halfW = u.plateBounds.x * 0.5f;
            float halfH = u.plateBounds.y * 0.5f;
            float outX = max(0.0f, fabs(kPos.x) - halfW);
            float outZ = max(0.0f, fabs(kPos.z) - halfH);
            float outDist = sqrt(outX * outX + outZ * outZ);
            bool underCase = (outDist < 0.50f && kPos.y < 0.55f);
            if (!underCase && outDist < 4.5f && kPos.y > -0.60f && kPos.y < 3.4f) {
                float3 kN = normalize((u.worldToKeyboard * float4(sh.Ng, 0.0f)).xyz);
                float3 sampleP = kPos + float3(kN.x, 0.0f, kN.z) * (outDist < 0.35f ? 0.32f : 0.0f);
                float2 gp = float2(sampleP.x * u.plateBounds.z + 0.5f, sampleP.z * u.plateBounds.w + 0.5f);
                float height = max(0.0f, kPos.y - 0.65f);
                float lod = clamp(1.6f + height * 1.4f + outDist * 1.15f, 1.6f, 5.5f);
                float3 pg = texSlots[u.plateGlowTexIndex].tex.sample(kClampSamp, clamp(gp, 0.01f, 0.99f), level(lod)).rgb;
                if (outDist < 0.35f) {
                    float wellMask = 1.0f - smoothstep(0.05f, 0.35f, outDist);
                    float edge = clamp(gp.x * (1.0f - gp.x) * gp.y * (1.0f - gp.y) * 14.0f, 0.35f, 1.0f);
                    float sideFace = smoothstep(0.86f, 0.25f, kN.y);
                    float2 toCenter = normalize(float2(-kPos.x, -kPos.z) + 1e-5f);
                    float rimOut = smoothstep(0.0f, 0.28f, outDist);
                    float inwardMask = mix(1.0f, smoothstep(-0.15f, 0.45f, dot(kN.xz, toCenter)), rimOut);
                    float vAtten = 1.0f / (1.0f + height * height * 2.2f);
                    float weight = 0.88f * sideFace * inwardMask * vAtten * mix(1.0f, edge, 0.45f);
                    liveSpill = pg * (weight * wellMask + 0.05f * (1.0f - wellMask));
                } else {
                    float2 toCenter = normalize(float2(-kPos.x, -kPos.z) + 1e-5f);
                    float faceToward = saturate(0.35f + 0.65f * max(0.0f, dot(kN.xz, toCenter)));
                    float upFace = smoothstep(-0.3f, 0.45f, kN.y);
                    float d = max(0.0f, outDist - 0.35f);
                    float distAtten = (1.0f - smoothstep(0.35f, 4.2f, outDist)) / (1.0f + d * d * 0.9f);
                    liveSpill = pg * (0.048f * faceToward * upFace * distAtten);
                }
                liveSpill *= u.monitorColor.w;
            }
        }
        // The real plants (golden pothos, lucky bamboo) are a fresh yellow-green, not a pure green:
        // take a little saturation out and most of the blue.
        if (sh.matClass == MAT_FOLIAGE) {
            float grey = luminance(sh.baseColor);
            sh.baseColor = mix(float3(grey), sh.baseColor, 0.88f) * float3(1.0f, 0.98f, 0.80f);
        }
        float3 color = sh.emissive + kD * sh.baseColor * (stored * relief + sunWhite + liveSpill * mix(1.0f, relief, 0.4f)) + directSpec;
        // Satin metal (bead-blasted aluminium) scatters light so broadly that it reads almost matte: it is
        // lit by the whole sky and the sun, not only by what sits in its mirror direction. Without this a
        // Mac mini standing on grass turns the dark green of the grass it reflects.
        if (sh.metalness > 0.5f) {
            color += F0 * (stored * relief + sunWhite) * (saturate(sh.roughness * 1.7f) * sh.metalness);
        }

        // Smooth, cliff-free transition between traced reflections and soft indirect environment sheen.
        float coatDom = hasCoat ? saturate(coatF / max(coatF + luminance(Fr), 1e-4f)) : 0.0f;
        float specRough = hasCoat ? mix(sh.roughness, sh.clearCoatRough, coatDom) : sh.roughness;
        float3 specWeight = hasCoat ? (Fr * (1.0f - coatF * 0.65f) + float3(coatF)) : Fr;

        float maxTraceRough = (sh.metalness > 0.35f || sh.clearCoat > 0.20f) ? 0.42f : 0.28f;
        float traceFrac = smoothstep(maxTraceRough, 0.04f, specRough);
        float3 R = reflect(rd, sh.N);
        float3 mirrorWeight = specWeight * traceFrac * (1.0f - 0.12f * specRough);

        bool tracedRefl = false;
        if (!hasReflection && max(mirrorWeight.x, max(mirrorWeight.y, mirrorWeight.z)) > 0.012f) {
            hasReflection = true;
            tracedRefl = true;
            reflOrigin = sh.worldPos + sh.Ng * ((sh.frontFace ? 0.003f : -0.003f) * sh.offsetEps);
            reflDir = R;
            reflNormal = sh.N;
            reflWeight = throughput * mirrorWeight;
            reflLod = clamp(specRough * 13.5f, 0.0f, 5.0f);
            reflSatin = (specRough > 0.08f && (sh.metalness > 0.35f || sh.clearCoat > 0.20f))
                ? clamp(specRough * 0.82f, 0.0f, 0.34f)
                : 0.0f;
        }

        // Remaining indirect sheen uses filtered environment scaled by local occlusion (never raw sunlight wash).
        float remFrac = tracedRefl ? (1.0f - traceFrac) : 1.0f;
        if (remFrac > 0.01f && max(specWeight.x, max(specWeight.y, specWeight.z)) > 0.003f) {
            float3 envRough = min(sampleEnvEquirect(R, clamp(max(specRough, 0.35f) * 10.5f, 3.0f, 5.0f), u, texSlots), float3(6.0f));
            // Sunlit surfaces count as open to the sky too, now that the sun is not part of the stored light.
            float envOcc = clamp((storedLum + luminance(sunWhite)) * 0.38f, 0.04f, 0.72f);
            color += specWeight * remFrac * envRough * envOcc * (1.0f - 0.35f * specRough);
        }

        radiance += throughput * color;
        break;
    }

    if (hasReflection && max(reflWeight.x, max(reflWeight.y, reflWeight.z)) > 0.003f) {
        intersector<triangle_data, instancing> reflInter;
        reflInter.assume_geometry_type(geometry_type::triangle);
        float3 seen = float3(0.0f);
        float maxW = max(reflWeight.x, max(reflWeight.y, reflWeight.z));
        if (reflSatin > 0.012f && maxW > 0.025f) {
            float3 T, B;
            makeONB(reflDir, T, B);
            const float3 taps[9] = {
                float3( 0.0000f,  0.0000f, 0.20f),
                float3( 0.4600f,  0.0000f, 0.12f),
                float3(-0.4600f,  0.0000f, 0.12f),
                float3( 0.0000f,  0.4600f, 0.12f),
                float3( 0.0000f, -0.4600f, 0.12f),
                float3( 0.6500f,  0.6500f, 0.08f),
                float3(-0.6500f,  0.6500f, 0.08f),
                float3( 0.6500f, -0.6500f, 0.08f),
                float3(-0.6500f, -0.6500f, 0.08f)
            };
            float spread = reflSatin * 0.95f;
            for (int tap = 0; tap < 9; ++tap) {
                float3 tapDir = normalize(reflDir + (T * taps[tap].x + B * taps[tap].y) * spread);
                float nd = dot(tapDir, reflNormal);
                if (nd < 0.02f) tapDir = normalize(tapDir - reflNormal * (nd - 0.02f));
                seen += taps[tap].z * traceReflectionRay(reflOrigin, tapDir, reflLod, u, reflInter, accel, vertices, indices, submeshes, instances, materials, texSlots, instGeom, tris, samples, deskSamples);
            }
        } else {
            seen = traceReflectionRay(reflOrigin, reflDir, reflLod, u, reflInter, accel, vertices, indices, submeshes, instances, materials, texSlots, instGeom, tris, samples, deskSamples);
        }
        radiance += reflWeight * seen;
    }

    outColor.write(float4(clamp(radiance, 0.0f, 32.0f), 1.0f), gid);
}

// MARK: - Lens Blur

struct LensBlurParams {
    float focusDistance;   // scene units from the camera to what it is looking at
    float cocScale;        // aperture radius * image height / (2 * tan(half field of view))
    float nearZ;
    float farZ;
    float maxRadius;       // pixels
    uint width;
    uint height;
    uint pad;
};

// Distance from the camera plane for a stored depth value (standard projection, depth in 0...1).
inline float lensViewDistance(float depth, LensBlurParams p) {
    return (p.farZ * p.nearZ) / max(p.farZ - depth * (p.farZ - p.nearZ), 1e-4f);
}

// How wide a point at this distance is smeared by the lens, in pixels: nothing at the focus distance,
// growing in front of and behind it.
inline float lensBlurRadius(float distance, LensBlurParams p) {
    return min(p.cocScale * abs(distance - p.focusDistance) / max(p.focusDistance * distance, 1e-4f), p.maxRadius);
}

/// Depth of field as a real lens gives it: what the camera looks at stays sharp, the rest softens with
/// distance from that plane. It runs on the finished, anti-aliased frame with a fixed tap pattern, so it
/// adds no noise and costs the same whether the camera moves or not.
kernel void lensBlurKernel(
    uint2 gid [[thread_position_in_grid]],
    constant LensBlurParams& p [[buffer(0)]],
    texture2d<float, access::sample> colorTex [[texture(0)]],
    texture2d<float, access::read> depthTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]]
) {
    if (gid.x >= p.width || gid.y >= p.height) return;
    float3 center = colorTex.read(gid).rgb;
    float centerDistance = lensViewDistance(depthTex.read(gid).r, p);
    float radius = lensBlurRadius(centerDistance, p);
    if (radius < 0.6f) {
        outTex.write(float4(center, 1.0f), gid);
        return;
    }

    float2 texel = 1.0f / float2(float(p.width), float(p.height));
    float2 uv = (float2(gid) + 0.5f) * texel;
    int2 limit = int2(int(p.width) - 1, int(p.height) - 1);
    float3 sum = center;
    float weightSum = 1.0f;
    // 28 taps on a sunflower spiral: even coverage of the disc with no visible pattern.
    for (int i = 0; i < 28; ++i) {
        float t = (float(i) + 0.5f) / 28.0f;
        float r = sqrt(t) * radius;
        float a = float(i) * 2.39996323f;
        float2 offset = float2(cos(a), sin(a)) * r;
        int2 tapPixel = clamp(int2(float2(gid) + offset), int2(0), limit);
        float tapDistance = lensViewDistance(depthTex.read(uint2(tapPixel)).r, p);
        float tapRadius = lensBlurRadius(tapDistance, p);
        // A sharp object in front must not smear into the blurred scene behind it: a tap only counts
        // if it is itself blurred enough to reach this pixel, or lies behind it.
        float reaches = saturate(tapRadius - r + 1.0f);
        float behind = tapDistance >= centerDistance * 0.98f ? 1.0f : 0.0f;
        float w = max(reaches, behind * saturate(tapRadius / max(radius, 1e-3f) + 0.15f));
        sum += colorTex.sample(kClampSamp, uv + offset * texel, level(0.0f)).rgb * w;
        weightSum += w;
    }
    outTex.write(float4(sum / weightSum, 1.0f), gid);
}
"""#
}
