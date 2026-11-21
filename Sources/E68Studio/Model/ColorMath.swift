import simd

/// Shared HSV/RGB colour conversions and circular `[0, 1)` hue-wheel arithmetic.
enum ColorMath {
    static func wrapHue(_ hue: Float) -> Float {
        guard hue.isFinite else { return 0 }
        let r = hue.truncatingRemainder(dividingBy: 1.0)
        let wrapped = r < 0 ? r + 1.0 : r
        return wrapped >= 1.0 ? 0 : wrapped
    }

    static func shortestHueDelta(from a: Float, to b: Float) -> Float {
        var delta = b - a
        if delta > 0.5 { delta -= 1.0 }
        if delta < -0.5 { delta += 1.0 }
        return delta
    }

    static func rgbToHSV(_ r: Float, _ g: Float, _ b: Float) -> (hue: Float, saturation: Float, value: Float) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC
        var hue: Float = 0
        if delta > 0.0001 {
            if maxC == r {
                hue = (g - b) / delta
                if hue < 0 { hue += 6 }
            } else if maxC == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
        }
        return (hue, maxC > 0.001 ? delta / maxC : 0, maxC)
    }

    static func hsvToRGB(hue: Float, saturation: Float, value: Float = 1) -> SIMD3<Float> {
        let h = wrapHue(hue) * 6
        let s = min(1, max(0, saturation))
        let v = min(1, max(0, value))
        let i = Int(h) % 6
        let f = h - floorf(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return SIMD3(v, t, p)
        case 1: return SIMD3(q, v, p)
        case 2: return SIMD3(p, v, t)
        case 3: return SIMD3(p, q, v)
        case 4: return SIMD3(t, p, v)
        default: return SIMD3(v, p, q)
        }
    }
}
