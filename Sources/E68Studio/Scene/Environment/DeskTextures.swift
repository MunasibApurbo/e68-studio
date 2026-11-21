import AppKit
import CoreGraphics
import simd

/// High-resolution procedural PBR textures (diffuse, roughness, normal) for every desk surface & product.
/// Heavy textures are pre-warmed concurrently across CPU cores via `warmStaticTextures()` with serial
/// row loops inside each builder to avoid thread-pool oversubscription.
enum DeskTextures {
    private struct CacheStore {
        var plasterWall: (diffuse: CGImage, normal: CGImage)?
        var matWeaveNormal: CGImage?
        var hasScannedWood: Bool?
        var walnutWood: (diffuse: CGImage, roughness: CGImage, normal: CGImage)?
        var rattanBasket: (diffuse: CGImage, normal: CGImage)?
        var mchoseTopShell: CGImage?
        var mchoseRoughness: CGImage?
        var asusScreen: CGImage?
        var asusChin: CGImage?
        var iPadScreen: CGImage?
        var brushedNormal: CGImage?
        var pbtMicroNormal: CGImage?
        var macMiniAluminum: (diffuse: CGImage, roughness: CGImage, normal: CGImage)?
        var zero2Faceplate: (diffuse: CGImage, normal: CGImage, metalness: CGImage)?
        var tripowinCarbon: (diffuse: CGImage, normal: CGImage)?
        var braidedNylonCable: (diffuse: CGImage, normal: CGImage, roughness: CGImage)?
        var leafPothos: PlantPBRMaps?
        var leafBamboo: PlantPBRMaps?
        var leafDieffenbachia: PlantPBRMaps?
        var caneBamboo: PlantPBRMaps?
        var caneDieffenbachia: PlantPBRMaps?
        var plantStemLoaded = false
        var plantStem: CGImage?
        var plantRootLoaded = false
        var plantRoot: CGImage?
        var waterCaustic: CGImage?
    }

    private static let cacheLock = NSLock()
    private static var store = CacheStore()

    private static func cached<T>(_ kp: WritableKeyPath<CacheStore, T?>, make: () -> T) -> T {
        cacheLock.lock()
        if let existing = store[keyPath: kp] {
            cacheLock.unlock()
            return existing
        }
        cacheLock.unlock()
        let built = make()
        cacheLock.lock()
        if let existing = store[keyPath: kp] {
            cacheLock.unlock()
            return existing
        }
        store[keyPath: kp] = built
        cacheLock.unlock()
        return built
    }

    static var cachedPlasterWall: (diffuse: CGImage, normal: CGImage) { cached(\.plasterWall) { makePlasterWall() } }
    static var cachedMatWeaveNormal: CGImage { cached(\.matWeaveNormal) { makeMatWeaveNormal() } }
    /// The desk uses a scanned wood surface when its files are present, and the generated walnut otherwise.
    static var usesScannedWood: Bool {
        cacheLock.lock()
        let known = store.hasScannedWood
        cacheLock.unlock()
        if let known { return known }
        _ = cachedWalnutWood
        cacheLock.lock()
        let resolved = store.hasScannedWood ?? false
        cacheLock.unlock()
        return resolved
    }
    static var cachedWalnutWood: (diffuse: CGImage, roughness: CGImage, normal: CGImage) {
        cacheLock.lock()
        if let existing = store.walnutWood {
            cacheLock.unlock()
            return existing
        }
        cacheLock.unlock()
        let scanned = autoreleasepool { loadScannedWood() }
        let built = scanned ?? autoreleasepool { makeWalnutWood() }
        cacheLock.lock()
        store.hasScannedWood = (scanned != nil)
        if let existing = store.walnutWood {
            cacheLock.unlock()
            return existing
        }
        store.walnutWood = built
        cacheLock.unlock()
        return built
    }
    static var cachedRattanBasket: (diffuse: CGImage, normal: CGImage) { cached(\.rattanBasket) { makeRattanBasket() } }
    static var cachedMchoseTopShell: CGImage { cached(\.mchoseTopShell) { makeMchoseTopShell() } }
    static var cachedMchoseRoughness: CGImage { cached(\.mchoseRoughness) { makeMchoseRoughness() } }
    static var cachedAsusScreen: CGImage { cached(\.asusScreen) { makeAsusScreen() } }
    static var cachedAsusChin: CGImage { cached(\.asusChin) { makeAsusChin() } }
    static var cachedIPadScreen: CGImage { cached(\.iPadScreen) { makeIPadScreen() } }
    static var cachedBrushedNormal: CGImage { cached(\.brushedNormal) { makeBrushedNormal() } }
    static var cachedPbtMicroNormal: CGImage { cached(\.pbtMicroNormal) { makePbtMicroNormal() } }
    static var cachedMacMiniAluminum: (diffuse: CGImage, roughness: CGImage, normal: CGImage) { cached(\.macMiniAluminum) { makeMacMiniAluminum() } }
    static var cachedZero2Faceplate: (diffuse: CGImage, normal: CGImage, metalness: CGImage) { cached(\.zero2Faceplate) { makeZero2Faceplate() } }
    static var cachedTripowinCarbon: (diffuse: CGImage, normal: CGImage) { cached(\.tripowinCarbon) { makeTripowinCarbon() } }
    static var cachedBraidedNylonCable: (diffuse: CGImage, normal: CGImage, roughness: CGImage) { cached(\.braidedNylonCable) { makeBraidedNylonCable() } }
    static var cachedLeafPothos: PlantPBRMaps { cached(\.leafPothos) { makeLeafPBR(kind: .pothos) } }
    static var cachedLeafBamboo: PlantPBRMaps { cached(\.leafBamboo) { makeLeafPBR(kind: .bamboo) } }
    static var cachedLeafDieffenbachia: PlantPBRMaps { cached(\.leafDieffenbachia) { makeLeafPBR(kind: .dieffenbachia) } }
    static var cachedCaneBamboo: PlantPBRMaps { cached(\.caneBamboo) { makeCanePBR(isDieffenbachia: false) } }
    static var cachedCaneDieffenbachia: PlantPBRMaps { cached(\.caneDieffenbachia) { makeCanePBR(isDieffenbachia: true) } }
    static var cachedPlantStem: CGImage? {
        cacheLock.lock()
        if store.plantStemLoaded {
            let v = store.plantStem
            cacheLock.unlock()
            return v
        }
        cacheLock.unlock()
        let img = loadPlantImage("pothos_stem.jpg")
        cacheLock.lock()
        if !store.plantStemLoaded {
            store.plantStem = img
            store.plantStemLoaded = true
        }
        let v = store.plantStem
        cacheLock.unlock()
        return v
    }
    static var cachedPlantRoot: CGImage? {
        cacheLock.lock()
        if store.plantRootLoaded {
            let v = store.plantRoot
            cacheLock.unlock()
            return v
        }
        cacheLock.unlock()
        let img = loadPlantImage("root_diff.jpg")
        cacheLock.lock()
        if !store.plantRootLoaded {
            store.plantRoot = img
            store.plantRootLoaded = true
        }
        let v = store.plantRoot
        cacheLock.unlock()
        return v
    }
    static var cachedWaterCaustic: CGImage { cached(\.waterCaustic) { makeWaterCausticTexture() } }

    /// Drops retained static `CGImage` copies after hardware ray-tracer Metal upload.
    static func releaseStaticCaches() {
        cacheLock.lock()
        let scanned = store.hasScannedWood
        store = CacheStore(hasScannedWood: scanned)
        cacheLock.unlock()
    }

    /// Pre-warms every static procedural texture concurrently across CPU cores during scene construction.
    static func warmStaticTextures() {
        let jobs: [@Sendable () -> Void] = [
            { _ = leafPBRTexture(kind: .bamboo) },
            { _ = leafPBRTexture(kind: .dieffenbachia) },
            { _ = canePBRTexture(isDieffenbachia: false) },
            { _ = canePBRTexture(isDieffenbachia: true) },
            { _ = plantStemTexture() },
            { _ = plantRootTexture() },
            { _ = braidedNylonCable() },
            { _ = macMiniAluminum() },
            { _ = tripowinCarbon() },
            { _ = walnutWood() },
            { _ = mchoseTopShell() },
            { _ = mchoseRoughness() },
            { _ = plasterWall() },
            { _ = rattanBasket() },
            {
                _ = brushedNormal()
                _ = pbtMicroNormal()
                _ = matWeaveNormal()
                _ = waterCausticTexture()
            },
        ]
        DispatchQueue.concurrentPerform(iterations: jobs.count) { idx in
            jobs[idx]()
        }
        // Keep AppKit NSGraphicsContext / NSAttributedString drawing sequential on the calling thread.
        _ = zero2Faceplate()
        _ = asusScreen()
        _ = iPadScreen()
        _ = asusChin()
    }

    static func makeImage(_ w: Int, _ h: Int, _ draw: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage {
        let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(ctx, CGFloat(w), CGFloat(h))
        return ctx.makeImage()!
    }

    /// Creates a `CGImage` backed by direct RGBA8 pixel writes (`row = 0` at top), optionally followed by vector overlays on `ctx`.
    static func makePixelImage(_ w: Int, _ h: Int, _ draw: (UnsafeMutablePointer<UInt8>, CGContext, CGFloat, CGFloat) -> Void) -> CGImage {
        let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
        draw(ptr, ctx, CGFloat(w), CGFloat(h))
        return ctx.makeImage()!
    }

    @inline(__always)
    static func clampByte(_ v: Float) -> UInt8 {
        guard v.isFinite else { return 0 }
        return UInt8(min(max(Int((v * 255.0).rounded()), 0), 255))
    }

    // MARK: - Procedural Noise & Heightfield Helpers

    @inline(__always)
    static func hash2D(_ ix: Int, _ iy: Int, _ seed: UInt32) -> Float {
        let a = UInt32(truncatingIfNeeded: ix) &* 374761393
        let b = UInt32(truncatingIfNeeded: iy) &* 668265263
        var h = (a &+ b) ^ seed
        h = (h ^ (h >> 13)) &* 1274126177
        return Float((h ^ (h >> 16)) & 0xFFFF) / 65535.0
    }

    static func valueNoise2D(_ x: Float, _ y: Float, _ seed: UInt32) -> Float {
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = x - Float(ix), fy = y - Float(iy)
        let ux = fx * fx * (3 - 2 * fx)
        let uy = fy * fy * (3 - 2 * fy)
        let a = hash2D(ix, iy, seed)
        let b = hash2D(ix + 1, iy, seed)
        let c = hash2D(ix, iy + 1, seed)
        let d = hash2D(ix + 1, iy + 1, seed)
        return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
    }

    /// Periodic tileable value noise over integer lattice `[0..<periodX, 0..<periodY]`.
    static func tileableNoise2D(_ x: Float, _ y: Float, periodX: Int, periodY: Int, _ seed: UInt32) -> Float {
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = x - Float(ix), fy = y - Float(iy)
        let ux = fx * fx * (3 - 2 * fx)
        let uy = fy * fy * (3 - 2 * fy)
        let x0 = ((ix % periodX) + periodX) % periodX
        let x1 = (x0 + 1) % periodX
        let y0 = ((iy % periodY) + periodY) % periodY
        let y1 = (y0 + 1) % periodY
        let a = hash2D(x0, y0, seed)
        let b = hash2D(x1, y0, seed)
        let c = hash2D(x0, y1, seed)
        let d = hash2D(x1, y1, seed)
        return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
    }

    static func fbm2D(_ x: Float, _ y: Float, _ seed: UInt32, octaves: Int = 4) -> Float {
        var sum: Float = 0, amp: Float = 0.5, freq: Float = 1, norm: Float = 0
        for i in 0..<octaves {
            sum += amp * valueNoise2D(x * freq, y * freq, seed &+ UInt32(i * 1013))
            norm += amp
            amp *= 0.5
            freq *= 2.03
        }
        return sum / norm
    }

    /// Converts a tileable scalar heightfield into a seamless tangent-space normal `CGImage`.
    static func normalFromHeight(_ height: [Float], width w: Int, height h: Int, strength: Float, invertY: Bool = true) -> CGImage {
        makePixelImage(w, h) { ptr, _, _, _ in
            let ySign: Float = invertY ? 1.0 : -1.0
            for row in 0..<h {
                let rUp = (row + h - 1) % h
                let rDn = (row + 1) % h
                let rowOff = row * w
                for col in 0..<w {
                    let cLt = (col + w - 1) % w
                    let cRt = (col + 1) % w
                    let dx = (height[rowOff + cRt] - height[rowOff + cLt]) * strength
                    let dy = (height[rDn * w + col] - height[rUp * w + col]) * strength
                    let nx = -dx
                    let ny = ySign * dy
                    let invLen = 1.0 / sqrt(nx * nx + ny * ny + 1.0)
                    let i = (rowOff + col) * 4
                    ptr[i]     = clampByte(0.5 + 0.5 * nx * invLen)
                    ptr[i + 1] = clampByte(0.5 + 0.5 * ny * invLen)
                    ptr[i + 2] = clampByte(0.5 + 0.5 * invLen)
                    ptr[i + 3] = 255
                }
            }
        }
    }

    @inline(__always)
    static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / max(e1 - e0, 1e-5), 0), 1)
        return t * t * (3 - 2 * t)
    }

    @inline(__always)
    static func lerp3(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ t: Float) -> (Float, Float, Float) {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }
}
