import ImageIO
import AppKit
import CoreGraphics
import simd

extension DeskTextures {
    // MARK: - Wall, Mat Weave, Walnut Desk & Rattan Basket

    /// Matte painted interior eggshell plaster (tileable diffuse + subtle roller-stipple normal).
    static func plasterWall() -> (diffuse: CGImage, normal: CGImage) { cachedPlasterWall }
    static func makePlasterWall() -> (diffuse: CGImage, normal: CGImage) {
        let w = 512, h = 512
        var hf = [Float](repeating: 0, count: w * h)

        let diffuse = makePixelImage(w, h) { ptr, _, _, _ in
            for row in 0..<h {
                let fy = Float(row) / Float(h)
                let rowOff = row * w
                for col in 0..<w {
                    let fx = Float(col) / Float(w)
                    let macro = tileableNoise2D(fx * 8, fy * 8, periodX: 8, periodY: 8, 0x9E37_01)
                    let med = tileableNoise2D(fx * 32, fy * 32, periodX: 32, periodY: 32, 0x9E37_02)
                    let stipple = tileableNoise2D(fx * 128, fy * 128, periodX: 128, periodY: 128, 0x9E37_03)
                    let grain = hash2D(col, row, 0x9E37_04)

                    let hDiffuse = macro * 0.30 + med * 0.38 + stipple * 0.24 + grain * 0.08
                    // Normal map carries smooth band-limited roller stipple without single-texel pixel noise that aliases at grazing angles.
                    hf[rowOff + col] = med * 0.24 + stipple * 0.76

                    // Natural painted interior warm-cream eggshell plaster (~0.79..0.82 sRGB)
                    let v = 0.792 + (hDiffuse - 0.5) * 0.044
                    let i = (rowOff + col) * 4
                    ptr[i]     = clampByte(v * 1.006)
                    ptr[i + 1] = clampByte(v * 0.996)
                    ptr[i + 2] = clampByte(v * 0.980)
                    ptr[i + 3] = 255
                }
            }
        }
        let normal = normalFromHeight(hf, width: w, height: h, strength: 0.75)
        return (diffuse, normal)
    }

    /// Seamless microfiber twill weave normal map (`8x8` fine thread crowns per tile).
    static func matWeaveNormal() -> CGImage { cachedMatWeaveNormal }
    static func makeMatWeaveNormal() -> CGImage {
        let w = 32, h = 32
        let cells = 8
        let step = w / cells
        var hf = [Float](repeating: 0, count: w * h)

        for row in 0..<h {
            let cy = row / step
            let ly = (Float(row % step) + 0.5) / Float(step)
            for col in 0..<w {
                let cx = col / step
                let lx = (Float(col % step) + 0.5) / Float(step)
                let warpOver = ((cx + cy) & 1) == 0
                let crown = warpOver
                    ? sin(ly * .pi) * (0.35 + 0.65 * sin(lx * .pi))
                    : sin(lx * .pi) * (0.35 + 0.65 * sin(ly * .pi))
                hf[row * w + col] = crown * 0.52 + (hash2D(col, row, 0x517C) - 0.5) * 0.05
            }
        }
        return normalFromHeight(hf, width: w, height: h, strength: 0.72)
    }

    /// Scanned wood veneer (colour, roughness, normal; CC0, polyhaven.com `dark_wood`). The scan is a
    /// red-brown; it is toned to the warm dark brown of the real desk in `Docs/Reference/desk-model`, keeping
    /// the grain, pores and sheen variation of real wood.
    static func loadScannedWood() -> (diffuse: CGImage, roughness: CGImage, normal: CGImage)? {
        func url(_ file: String) -> URL? {
            let relative = "Materials/\(file)"
            if let base = Bundle.main.resourceURL {
                let candidate = base.appendingPathComponent(relative)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
            var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
            for _ in 0..<6 {
                let candidate = dir.appendingPathComponent("Resources/\(relative)")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                dir.deleteLastPathComponent()
            }
            return nil
        }
        func load(_ file: String) -> CGImage? {
            let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let url = url(file), let source = CGImageSourceCreateWithURL(url as CFURL, noCache) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, noCache)
        }
        guard let colour = load("dark_wood_diff_2k.jpg"), let roughness = load("dark_wood_rough_2k.jpg"),
              let normal = load("dark_wood_nor_gl_2k.jpg") else { return nil }

        // Tone: take half the red out and darken to a walnut brown, keeping the grain's own contrast.
        let w = colour.width, h = colour.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(colour, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Float(px[i]), g = Float(px[i + 1]), b = Float(px[i + 2])
            let grey = 0.30 * r + 0.59 * g + 0.11 * b
            px[i] = UInt8(min(255, (grey + (r - grey) * 0.50) * 0.66))
            px[i + 1] = UInt8(min(255, (grey + (g - grey) * 0.50) * 0.66))
            px[i + 2] = UInt8(min(255, (grey + (b - grey) * 0.50) * 0.62))
            px[i + 3] = 255
        }
        guard let stained = ctx.makeImage() else { return nil }
        return (stained, roughness, normal)
    }

    /// Deep satin-lacquered espresso walnut wood grain (shared wavy heightfield drives aligned diffuse, roughness & pore normal).
    static func walnutWood() -> (diffuse: CGImage, roughness: CGImage, normal: CGImage) { cachedWalnutWood }
    static func makeWalnutWood() -> (diffuse: CGImage, roughness: CGImage, normal: CGImage) {
        let w = 1024, h = 512
        var hf = [Float](repeating: 0, count: w * h)
        var roughField = [Float](repeating: 0.38, count: w * h)

        let diffuse = makePixelImage(w, h) { ptr, _, _, _ in
            for row in 0..<h {
                let fy = Float(row) / Float(h)
                let rowOff = row * w
                for col in 0..<w {
                    let fx = Float(col) / Float(w)
                    // Tileable low-frequency warp so wood fibers undulate cleanly along X and wrap seamlessly
                    let warp = (tileableNoise2D(fx * 6, fy * 10, periodX: 6, periodY: 10, 0xD410) - 0.5) * 2.6
                        + (tileableNoise2D(fx * 18, fy * 24, periodX: 18, periodY: 24, 0xD411) - 0.5) * 0.65
                    let coordY = fy * 28.0 + warp

                    // Cathedral-to-straight grain bands + darker walnut latewood streaks
                    let ringWave = 0.5 + 0.5 * sin(coordY * .pi * 2.0)
                    let fineFiber = tileableNoise2D(fx * 14, fy * 160 + warp * 5.0, periodX: 14, periodY: 160, 0xD412)
                    let macroTone = tileableNoise2D(fx * 4, fy * 8, periodX: 4, periodY: 8, 0xD413)

                    // Tiny open wood pores etched along grain lines
                    let poreRaw = tileableNoise2D(fx * 28, fy * 256 + warp * 8.0, periodX: 28, periodY: 256, 0xD414)
                    let poreMask = smoothstep(0.76, 0.94, poreRaw) * (0.45 + 0.55 * (1.0 - ringWave))

                    let grainVal = ringWave * 0.56 + fineFiber * 0.28 + macroTone * 0.16
                    let idx = rowOff + col
                    hf[idx] = grainVal * 0.45 - poreMask * 0.65

                    // Warm dark espresso-ash wood grain (deep charcoal-chocolate timber with crisp open pores)
                    let shade = 0.68 + grainVal * 0.54 - poreMask * 0.44
                    let r = 0.088 * shade + macroTone * 0.012
                    let g = 0.050 * shade + macroTone * 0.006
                    let b = 0.032 * shade + macroTone * 0.003

                    let pIdx = idx * 4
                    ptr[pIdx]     = clampByte(r)
                    ptr[pIdx + 1] = clampByte(g)
                    ptr[pIdx + 2] = clampByte(b)
                    ptr[pIdx + 3] = 255

                    // Satin polyurethane finish: smooth sheen across closed grain (~0.32), matte open pores (~0.54)
                    roughField[idx] = min(0.58, max(0.28, 0.40 - grainVal * 0.09 + poreMask * 0.16))
                }
            }
        }

        let roughness = makePixelImage(w, h) { ptr, _, _, _ in
            for i in 0..<(w * h) {
                let b = clampByte(roughField[i])
                let p = i * 4
                ptr[p] = b; ptr[p + 1] = b; ptr[p + 2] = b; ptr[p + 3] = 255
            }
        }
        let normal = normalFromHeight(hf, width: w, height: h, strength: 1.75)
        return (diffuse, roughness, normal)
    }

    /// Woven natural rattan/wicker reeds for the under-desk wastebasket (diffuse + curved-reed normal).
    static func rattanBasket() -> (diffuse: CGImage, normal: CGImage) { cachedRattanBasket }
    static func makeRattanBasket() -> (diffuse: CGImage, normal: CGImage) {
        let w = 256, h = 256
        let cols = 12, rows = 12
        let cellW = w / cols
        let cellH = h / rows
        var hf = [Float](repeating: 0, count: w * h)

        let diffuse = makePixelImage(w, h) { ptr, _, _, _ in
            for row in 0..<h {
                let rCell = min(rows - 1, row / cellH)
                let ly = (Float(row % cellH) + 0.5) / Float(cellH)
                let rowOff = row * w
                for col in 0..<w {
                    let cCell = min(cols - 1, col / cellW)
                    let lx = (Float(col % cellW) + 0.5) / Float(cellW)

                    // 1-over-1 woven cane strips with slight reed width & rounded gap crevices
                    let horiz = ((rCell + cCell) & 1) == 0
                    let across = horiz ? ly : lx
                    let along = horiz ? lx : ly
                    let edgeMask = sin(min(max((across - 0.06) / 0.88, 0), 1) * .pi)
                    let arch = 0.25 + 0.75 * sin(along * .pi)
                    let reedHeight = pow(edgeMask, 0.65) * arch

                    // Longitudinal bamboo/reed fiber streaks along each strand
                    let fiber = tileableNoise2D(
                        (horiz ? Float(col) / 8 : Float(col) / 2),
                        (horiz ? Float(row) / 2 : Float(row) / 8),
                        periodX: 64, periodY: 64, 0xBA5E
                    )
                    let cellVar = hash2D(cCell, rCell, 0xBA5F) * 0.16

                    let idx = rowOff + col
                    hf[idx] = reedHeight + (fiber - 0.5) * 0.08

                    // Natural honey-walnut rattan tones darkened deeply in crevices
                    let shade = 0.22 + reedHeight * (0.58 + cellVar) + (fiber - 0.5) * 0.07
                    let pIdx = idx * 4
                    ptr[pIdx]     = clampByte(shade * 0.52)
                    ptr[pIdx + 1] = clampByte(shade * 0.36)
                    ptr[pIdx + 2] = clampByte(shade * 0.21)
                    ptr[pIdx + 3] = 255
                }
            }
        }
        let normal = normalFromHeight(hf, width: w, height: h, strength: 3.4)
        return (diffuse, normal)
    }
}
