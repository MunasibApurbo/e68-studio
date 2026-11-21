import Foundation
import simd

/// Structures shared verbatim (identical byte offsets & 16-byte alignment) between Swift and Metal ray-tracing shaders.
enum RTSharedTypes {
    static let maxBouncesInteractive: UInt32 = 5
    static let maxBouncesProgressive: UInt32 = 5
}

struct RTVertex {
    var px: Float
    var py: Float
    var pz: Float
    var nx: Float
    var ny: Float
    var nz: Float
    var u: Float
    var v: Float
    var cr: Float
    var cg: Float
    var cb: Float
    var ca: Float
} // 48 bytes

struct RTSubmesh {
    var vertexOffset: UInt32
    var indexOffset: UInt32
    var materialIndex: UInt32
    var flags: UInt32
} // 16 bytes

enum RTSubmeshFlags {
    static let isKeySide: UInt32  = 1 << 0
    static let isKeyPlate: UInt32 = 1 << 1
}

enum RTInstanceFlags {
    static let mirroredDet: UInt32   = 1 << 0
    static let isKeyboard: UInt32    = 1 << 1
    static let isGlassWater: UInt32  = 1 << 2
    static let doubleSided: UInt32   = 1 << 3
    static let noCastShadow: UInt32  = 1 << 4
}

struct RTInstanceInfo {
    var modelToWorld: simd_float4x4
    var prevModelToWorld: simd_float4x4
    var normalToWorld: simd_float4x4
    var submeshBase: UInt32
    var nodeTag: UInt32
    var flags: UInt32
    var reserved: UInt32
} // 208 bytes

enum RTMatClass: Int32 {
    case standard       = 0
    case thinGlass      = 1
    case solidGlass     = 2
    case water          = 3
    case indigoResin    = 4
    case foliage        = 5
    case screen         = 6
    case wovenCloth     = 7
    case sssPolymer     = 8
    case keySkirt       = 9
    case keyPlate       = 10
    case emissiveCard   = 11
}

enum RTMatFlags {
    static let doubleSided: Int32       = 1 << 0
    static let isMonitorScreen: Int32   = 1 << 1
    static let isButtonOverlay: Int32   = 1 << 2
    static let isAnodizedMetal: Int32   = 1 << 3
    static let isWalnutWood: Int32      = 1 << 4
    static let isAdditiveSprite: Int32  = 1 << 5
    static let isUnlitConstant: Int32   = 1 << 6
    static let isOpenWater: Int32       = 1 << 7
    static let isSampledEmitter: Int32  = 1 << 8
    static let isGroundProjection: Int32 = 1 << 9
}

struct RTMaterialData {
    var baseColor: SIMD4<Float>       // rgb linear albedo, w = opacity (0..1)
    var emissionColor: SIMD4<Float>   // rgb linear emission * intensity, w = scalar roughness
    var params: SIMD4<Float>          // x = metalness, y = clearCoat, z = clearCoatRoughness, w = normalIntensity
    var optics: SIMD4<Float>          // x = ior, y = subsurface/translucency, z = sheen/anisotropy, w = emissiveBoost
    var absorbColor: SIMD4<Float>     // xyz = Beer-Lambert sigma_t absorption, w = shellThickness / leafThickness
    var diffuseUV: SIMD4<Float>       // sx, sy, tx, ty
    var detailUV: SIMD4<Float>        // sx, sy, tx, ty (normal / metalness / ao)
    var roughnessUV: SIMD4<Float>     // sx, sy, tx, ty
    var texIndices: SIMD4<Int32>      // x = diffuse, y = normal, z = roughness, w = emission
    var extraTex: SIMD4<Int32>        // x = metalness, y = ao, z = matClass, w = flags
} // 160 bytes

struct RTFrameUniforms {
    var camPos: SIMD4<Float>
    var camRight: SIMD4<Float>
    var camUp: SIMD4<Float>
    var camForward: SIMD4<Float>

    var viewToClip: simd_float4x4
    var worldToView: simd_float4x4
    var prevViewProj: simd_float4x4
    var worldToKeyboard: simd_float4x4

    var renderSize: SIMD2<UInt32>
    var outputSize: SIMD2<UInt32>
    var jitter: SIMD2<Float>
    var prevJitter: SIMD2<Float>

    var frameIndex: UInt32
    var sampleIndex: UInt32
    var accumulationBlend: Float
    var maxBounces: UInt32

    var tanHalfFov: Float
    var aspect: Float
    var apertureRadius: Float
    var focusDistance: Float

    var exposureScale: Float
    var renderFlags: UInt32           // bit 0 = progressive pass (skip denoiser G-buffer writes)
    var isRoomScenario: UInt32
    var hdrEnvTexIndex: Int32

    var plateGlowTexIndex: Int32
    var monitorTexIndex: Int32
    var hasBgCubemap: UInt32
    var uniformPad0: UInt32 = 0

    var bgColor: SIMD4<Float>         // xyz linear bg, w = envIntensity
    var fogColor: SIMD4<Float>        // xyz linear fog, w = fogStart
    var fogParams: SIMD4<Float>       // x = fogEnd, y = bloomStrength, z = vignette, w = grainStrength
    var plateBounds: SIMD4<Float>     // x = planeW, y = planeH, z = 1/planeW, w = 1/planeH

    // Analytic Soft Area Lights for Next Event Estimation + MIS
    var keyLightPosRadius: SIMD4<Float>
    var keyLightColor: SIMD4<Float>   // w = isSunDirectional (0 room softbox, 1 crisp directional sun disc)
    var fillLightPosRadius: SIMD4<Float>
    var fillLightColor: SIMD4<Float>  // w = fillActive

    var deskBulbPosRadius: SIMD4<Float>
    var deskBulbColor: SIMD4<Float>   // w = bulbActive

    var monitorPos: SIMD4<Float>      // xyz center, w = enabledIntensity
    var monitorU: SIMD4<Float>        // xyz half-right vector, w = width
    var monitorV: SIMD4<Float>        // xyz half-up vector, w = height
    var monitorColor: SIMD4<Float>    // xyz tint, w = plateGlowBoost

    var underDeskPosA: SIMD4<Float>   // xyz endpoint A, w = tubeRadius
    var underDeskPosB: SIMD4<Float>   // xyz endpoint B, w = enabledIntensity
    var underDeskColor: SIMD4<Float>  // xyz linear glow, w = isProgressive (0 or 1)

    var roomLightPosRadius: SIMD4<Float>
    var roomLightColor: SIMD4<Float>  // w = roomActive

    var windowOrigin: SIMD4<Float>    // xyz = lower corner of the room window, w = sun-through-window mask enabled
    var windowU: SIMD4<Float>         // xyz = unit axis along the wall, w = width
    var windowV: SIMD4<Float>         // xyz = unit axis up the wall, w = height

    var groundProjection: SIMD4<Float> // xyz = panorama capture point, w = its white level (0 = no photographed ground)
}
