import SceneKit
import AppKit
import simd

extension DeskScenarios {

    struct ScenarioLightingProfile {
        let keyIntensityScale: Float
        let keyColor: NSColor
        let fillIntensityScale: Float
        let roomIntensityScale: Float
        let envIntensity: CGFloat
        let exposureOffset: CGFloat
        let fogColor: NSColor
        let fogStart: CGFloat
        let fogEnd: CGFloat
        let underDeskGlowMultiplier: Float
    }

    /// Studio lights and exposure for a scenario and mood. Outdoors the photograph supplies the light, so
    /// this mostly sets the moonlight used when a night photo has no source strong enough to shape the
    /// desk, and how strongly the under-desk glow reads.
    static func lightingProfile(scenario: DeskScenario, mood: DeskMood) -> ScenarioLightingProfile {
        let night = mood == .midnight
        let keyColor: NSColor = night
            ? NSColor(srgbRed: 0.76, green: 0.84, blue: 1.0, alpha: 1)
            : NSColor(srgbRed: 1.0, green: 0.97, blue: 0.93, alpha: 1)
        return ScenarioLightingProfile(
            keyIntensityScale: night ? 0.55 : 1.05,
            keyColor: keyColor,
            fillIntensityScale: night ? 0.62 : 0.94,
            roomIntensityScale: night ? 0.62 : 0.94,
            envIntensity: night ? 0.76 : 1.02,
            exposureOffset: night ? -0.10 : 0.01,
            fogColor: .black,
            fogStart: 0,
            fogEnd: 0,
            underDeskGlowMultiplier: night ? 1.28 : 0.88
        )
    }

    private static var fallbackSky: [DeskMood: CGImage] = [:]

    /// A plain graded sky, used only if a scenario's photograph is missing from the app.
    static func hdrEnvironmentImage(mood: DeskMood) -> CGImage {
        if let cached = fallbackSky[mood] { return cached }
        let w = 64, h = 32
        let night = mood == .midnight
        let zenith = night ? SIMD3<Float>(0.010, 0.014, 0.030) : SIMD3<Float>(0.30, 0.52, 0.95)
        let horizon = night ? SIMD3<Float>(0.030, 0.036, 0.055) : SIMD3<Float>(0.95, 1.00, 1.08)
        let ground = night ? SIMD3<Float>(0.010, 0.010, 0.012) : SIMD3<Float>(0.22, 0.21, 0.20)
        var pixels = [Float](repeating: 1, count: w * h * 4)
        for row in 0..<h {
            let elevation = (0.5 - (Float(row) + 0.5) / Float(h)) * Float.pi
            let t = abs(sin(elevation))
            let rgb = elevation >= 0 ? simd_mix(horizon, zenith, SIMD3(repeating: pow(t, 0.6))) : simd_mix(horizon * 0.6, ground, SIMD3(repeating: pow(t, 0.4)))
            for col in 0..<w {
                let i = (row * w + col) * 4
                pixels[i] = rgb.x; pixels[i + 1] = rgb.y; pixels[i + 2] = rgb.z
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.floatComponents.rawValue | CGImageByteOrderInfo.order32Host.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        let image = CGImage(width: w, height: h, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: w * 16,
                            space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, bitmapInfo: info,
                            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        fallbackSky[mood] = image
        return image
    }
}
