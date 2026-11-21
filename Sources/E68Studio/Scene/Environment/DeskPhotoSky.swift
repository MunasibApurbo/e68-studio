import AppKit
import ImageIO
import simd

/// Photographed skies. A scenario that has one is lit and backed by a real 360-degree HDR photograph
/// instead of a generated sky and generated terrain: the photo is what the camera sees behind the desk,
/// what glossy surfaces reflect, and where all the daylight comes from.
enum DeskPhotoSky {

    struct Photo {
        /// Equirectangular linear HDR image (u = azimuth, v = elevation), scaled to scene exposure,
        /// with the sun's disc taken out when the sun is handled as the key light.
        let environment: CGImage
        /// Unit vector toward the sun, when the photo has one bright enough to cast shadows.
        let sunDirection: SIMD3<Float>?
        /// Linear RGB light on a surface facing the sun, in scene exposure.
        let sunIrradiance: SIMD3<Float>
        /// Brightness of a level white surface under this sky with nothing in the way (scene exposure).
        /// The ground is drawn from the photo and darkened by how far the stored light falls below this.
        let whiteLevel: Float
        /// Average colour of the photographed ground as a surface colour, for the light it bounces upward.
        let groundAlbedo: SIMD3<Float>
    }

    private struct Asset {
        let file: String
        /// Brightness a white surface facing straight up should have under this sky (scene exposure).
        let whiteLevel: Float
        /// Night panoramas contain lamps, not a sun; those stay in the picture and are not turned into a key light.
        let findSun: Bool
        /// Turns the panorama about the vertical axis (fraction of a full turn) so its best view sits
        /// behind the monitor and the sun falls across the desk instead of straight into the camera.
        var turn: Float = 0
    }

    private static func asset(scenario: DeskScenario, mood: DeskMood) -> Asset? {
        let night = mood == .midnight
        switch scenario {
        case .swissAlps:
            return night ? Asset(file: "moonlit_golf_2k.hdr", whiteLevel: 0.38, findSun: true, turn: 0.30)
                         : Asset(file: "alps_field_2k.hdr", whiteLevel: 1.55, findSun: true, turn: 0.38)
        case .winter:
            return night ? Asset(file: "winter_evening_2k.hdr", whiteLevel: 0.11, findSun: false, turn: -0.05)
                         : Asset(file: "snowy_park_01_2k.hdr", whiteLevel: 1.25, findSun: true, turn: -0.35)
        case .nature:
            return night ? Asset(file: "dikhololo_night_2k.hdr", whiteLevel: 0.19, findSun: false)
                         : Asset(file: "meadow_2_2k.hdr", whiteLevel: 1.60, findSun: true, turn: 0.30)
        case .blossom:
            return night ? Asset(file: "moonless_golf_2k.hdr", whiteLevel: 0.26, findSun: false)
                         : Asset(file: "symmetrical_garden_02_2k.hdr", whiteLevel: 1.55, findSun: true, turn: -0.32)
        case .ocean:
            return night ? Asset(file: "umhlanga_sunrise_2k.hdr", whiteLevel: 0.24, findSun: false, turn: -0.32)
                         : Asset(file: "spiaggia_di_mondello_2k.hdr", whiteLevel: 1.60, findSun: true, turn: 0.54)
        case .canyon:
            return night ? Asset(file: "rogland_clear_night_2k.hdr", whiteLevel: 0.20, findSun: false)
                         : Asset(file: "goegap_2k.hdr", whiteLevel: 1.78, findSun: true, turn: 0.30)
        case .cyberpunk:
            return night ? Asset(file: "shanghai_bund_2k.hdr", whiteLevel: 0.20, findSun: false, turn: -0.08)
                         : Asset(file: "the_sky_is_on_fire_2k.hdr", whiteLevel: 1.05, findSun: true, turn: 0.12)
        case .room:
            return nil
        }
    }

    // Only the photo in use is kept: each is a multi-megabyte float image.
    private static var cached: (file: String, photo: Photo)?

    static func clearCache() {
        cached = nil
    }

    static func photo(scenario: DeskScenario, mood: DeskMood) -> Photo? {
        guard let asset = asset(scenario: scenario, mood: mood) else {
            cached = nil
            return nil
        }
        if let cached, cached.file == asset.file { return cached.photo }
        // Free the previous world's panorama pixels before decoding the next multi-megabyte HDR image.
        cached = nil
        guard let url = url(for: asset.file),
              let built = autoreleasepool(invoking: { load(url, asset: asset) }) else { return nil }
        cached = (asset.file, built)
        return built
    }

    private static func url(for file: String) -> URL? {
        let relative = "Environments/\(file)"
        if let base = Bundle.main.resourceURL {
            let candidate = base.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        // Running straight from `swift build`: walk up from the executable to the project's Resources folder.
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/\(relative)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    private static func load(_ url: URL, asset: Asset) -> Photo? {
        let noCacheOpts = [kCGImageSourceShouldAllowFloat: true, kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, noCacheOpts) else { return nil }
        let w = image.width, h = image.height
        var px = [Float](repeating: 0, count: w * h * 4)
        let info = CGBitmapInfo.floatComponents.rawValue | CGImageByteOrderInfo.order32Host.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16, space: space, bitmapInfo: info) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let shift = ((Int((asset.turn * Float(w)).rounded()) % w) + w) % w
        if shift != 0 {
            var row = [Float](repeating: 0, count: w * 4)
            for y in 0..<h {
                let base = y * w * 4
                for x in 0..<w {
                    let from = base + ((x - shift + w) % w) * 4
                    row[x * 4] = px[from]; row[x * 4 + 1] = px[from + 1]; row[x * 4 + 2] = px[from + 2]; row[x * 4 + 3] = px[from + 3]
                }
                px.replaceSubrange(base..<(base + w * 4), with: row)
            }
        }

        func luminance(_ i: Int) -> Float { 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2] }
        // Row 0 is the zenith. Each pixel covers a patch of sky that shrinks toward the poles.
        func elevation(_ row: Int) -> Float { (0.5 - (Float(row) + 0.5) / Float(h)) * .pi }
        let pixelAngle = (Float.pi / Float(h)) * (2 * Float.pi / Float(w))

        // Average brightness of the sky dome, to tell the sun apart from bright cloud.
        var skySum: Float = 0, skyWeight: Float = 0
        for row in 0..<(h / 2) {
            let weight = cos(elevation(row))
            var rowSum: Float = 0
            for col in 0..<w { rowSum += min(luminance((row * w + col) * 4), 50) }
            skySum += rowSum * weight
            skyWeight += Float(w) * weight
        }
        let skyMean = skySum / max(skyWeight, 1)

        // The sun: everything far brighter than the sky around it. Its light is moved out of the image and
        // into a key light, which gives sharp shadows the blurred image could not.
        let cap = max(skyMean * 24, 4)
        var sunVector = SIMD3<Float>(repeating: 0)
        var sunLight = SIMD3<Float>(repeating: 0)
        if asset.findSun {
            for row in 0..<(h / 2) {
                let el = elevation(row)
                let dOmega = pixelAngle * cos(el)
                for col in 0..<w {
                    let i = (row * w + col) * 4
                    let lum = luminance(i)
                    guard lum > cap else { continue }
                    let keep = cap / lum
                    let excess = SIMD3<Float>(px[i], px[i + 1], px[i + 2]) * (1 - keep) * dOmega
                    let az = ((Float(col) + 0.5) / Float(w) - 0.5) * 2 * .pi
                    sunVector += SIMD3<Float>(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * (0.2126 * excess.x + 0.7152 * excess.y + 0.0722 * excess.z)
                    sunLight += excess
                    px[i] *= keep; px[i + 1] *= keep; px[i + 2] *= keep
                }
            }
        }

        // Light a level white surface receives from the (sun-less) sky, as the brightness it would show.
        var skyWhite: Float = 0
        for row in 0..<(h / 2) {
            let el = elevation(row)
            var rowSum: Float = 0
            for col in 0..<w { rowSum += min(luminance((row * w + col) * 4), cap) }
            skyWhite += rowSum * sin(el) * cos(el) * pixelAngle
        }
        skyWhite /= .pi
        let sunWhite = (0.2126 * sunLight.x + 0.7152 * sunLight.y + 0.0722 * sunLight.z) * max(simd_normalize(sunVector + SIMD3<Float>(0, 1e-6, 0)).y, 0) / .pi
        let hasSun = asset.findSun && sunWhite > skyWhite * 0.25
        let scale = asset.whiteLevel / max(skyWhite + (hasSun ? sunWhite : 0), 1e-4)

        let limit: Float = 60
        for i in stride(from: 0, to: px.count, by: 4) {
            px[i] = min(max(px[i] * scale, 0), limit)
            px[i + 1] = min(max(px[i + 1] * scale, 0), limit)
            px[i + 2] = min(max(px[i + 2] * scale, 0), limit)
            px[i + 3] = 1
        }

        // The ground's own colour: the band of the photo looking down at the ground around the tripod,
        // divided by the light that fell on it.
        var groundSum = SIMD3<Float>(repeating: 0)
        var groundCount: Float = 0
        for row in stride(from: Int(Float(h) * 0.62), to: Int(Float(h) * 0.86), by: 4) {
            for col in stride(from: 0, to: w, by: 8) {
                let i = (row * w + col) * 4
                groundSum += SIMD3<Float>(px[i], px[i + 1], px[i + 2])
                groundCount += 1
            }
        }
        let groundAlbedo = simd_clamp(groundSum / max(groundCount, 1) / max(asset.whiteLevel, 1e-3),
                                      SIMD3<Float>(repeating: 0.03), SIMD3<Float>(repeating: 0.85))

        let data = px.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let environment = CGImage(width: w, height: h, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: w * 16,
                                        space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                                        decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        if E68Perf.enabled {
            E68Perf.logLine(String(format: "photo sky %@: %dx%d, sky white %.3f, sun white %.3f (%@), scale %.3f",
                                   asset.file, w, h, skyWhite, sunWhite, hasSun ? "key light" : "left in the image", scale))
        }
        return Photo(environment: environment,
                     sunDirection: hasSun ? simd_normalize(sunVector) : nil,
                     sunIrradiance: hasSun ? sunLight * scale : .zero,
                     whiteLevel: asset.whiteLevel,
                     groundAlbedo: groundAlbedo)
    }
}
