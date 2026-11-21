import AppKit
import CoreGraphics
import simd

extension DeskTextures {
    // MARK: - 7Hz x Crinacle Zero:2 Faceplate, Tripowin C8 Carbon & Ukiru Desk Mat

    /// Authentic 7Hz x Crinacle Zero:2 (Blue) brushed metallic geometric faceplate:
    /// deep cobalt/sapphire anodized facets, crisp lighter-blue/silver chamfered ridges,
    /// central recessed acoustic vent with copper/red-gold mesh ring & dark center aperture, and etched line accents.
    /// Brushed anodized stainless silver polygonal faceplate with single corner screw & subtle etched "ZERO"
    /// matching the authentic original 7Hz Salnotes Zero (IMG_1868).
    static func zero2Faceplate() -> (diffuse: CGImage, normal: CGImage, metalness: CGImage) { cachedZero2Faceplate }
    static func makeZero2Faceplate() -> (diffuse: CGImage, normal: CGImage, metalness: CGImage) {
        let w = 512, h = 512
        let sectorAngles: [Float] = [0.06, 0.94, 1.84, 2.72, 3.60, 4.52, 5.40]
        let facetShades: [Float] = [1.01, 0.97, 1.03, 0.98, 0.96, 1.02, 0.99]

        var metalMask = [UInt8](repeating: 238, count: w * h)
        var normalBuf = [UInt8](repeating: 0, count: w * h * 4)

        let diffuse = makePixelImage(w, h) { ptr, ctx, W, H in
            for row in 0..<h {
                let v = Float(row) / Float(h - 1)
                let dy = v - 0.5
                for col in 0..<w {
                    let u = Float(col) / Float(w - 1)
                    let dx = u - 0.5
                    let r = hypot(dx, dy)
                    var ang = atan2(dy, dx)
                    if ang < 0 { ang += 2 * .pi }

                    var secIdx = sectorAngles.count - 1
                    for k in 0..<sectorAngles.count {
                        let a0 = sectorAngles[k]
                        let a1 = (k + 1 < sectorAngles.count) ? sectorAngles[k + 1] : (sectorAngles[0] + 2 * .pi)
                        let testAng = (ang < sectorAngles[0]) ? (ang + 2 * .pi) : ang
                        if testAng >= a0 && testAng < a1 {
                            secIdx = k
                            break
                        }
                    }

                    let a0 = sectorAngles[secIdx]
                    let a1 = (secIdx + 1 < sectorAngles.count) ? sectorAngles[secIdx + 1] : (sectorAngles[0] + 2 * .pi)
                    let midAng = 0.5 * (a0 + a1)
                    let testAng = (ang < sectorAngles[0]) ? (ang + 2 * .pi) : ang
                    let dEdge0 = abs(testAng - a0) * max(r, 0.05)
                    let dEdge1 = abs(a1 - testAng) * max(r, 0.05)
                    let distToRidge = min(dEdge0, dEdge1)

                    // Uniform vertical-diagonal hairline brushed stainless metal grain across clean flat plate
                    let brushAxis = u * 0.94 + v * 0.34
                    let perpAxis  = -u * 0.34 + v * 0.94
                    let brushNoise = valueNoise2D(brushAxis * 220.0, perpAxis * 28.0, 0x7702)
                    let micro = hash2D(col, row, 0x7705)
                    let streak = (brushNoise - 0.5) * 0.065 + (micro - 0.5) * 0.018

                    let fShade = facetShades[secIdx]
                    var lum = 0.74 * fShade + streak
                    var rgb: (Float, Float, Float) = (lum * 0.985, lum * 0.992, lum * 1.008)

                    var nx = cos(midAng) * 0.04 + (brushNoise - 0.5) * 0.06
                    var ny = sin(midAng) * 0.04 + (brushNoise - 0.5) * 0.06
                    var nz: Float = 0.995

                    // Subtle machined edge bevel around outer polygonal perimeter
                    let secSpan = a1 - a0
                    let secFrac = (testAng - a0) / max(secSpan, 1e-4) - 0.5
                    let polyR = r * cos(secFrac * secSpan * 0.85)
                    let outerChamfer = smoothstep(0.355, 0.365, polyR) * (1.0 - smoothstep(0.378, 0.392, polyR))
                    let ridgeHighlight = (1.0 - smoothstep(0.001, 0.007, distToRidge)) * smoothstep(0.18, 0.35, r) * 0.12
                    let rimFactor = max(outerChamfer * 0.65, ridgeHighlight)
                    if rimFactor > 0.01 {
                        rgb = lerp3(rgb, (0.86, 0.88, 0.90), rimFactor * 0.72)
                    }

                    var mByte: UInt8 = 238

                    // Single small recessed stainless corner screw near upper-back lobe (-0.20, -0.18)
                    let sdx = u - 0.31
                    let sdy = v - 0.32
                    let sr = hypot(sdx, sdy)
                    if sr < 0.048 {
                        if sr > 0.036 {
                            // Dark circular recess ring
                            rgb = (0.28, 0.30, 0.32)
                            nx = -sdx / max(sr, 1e-4) * 0.45
                            ny = -sdy / max(sr, 1e-4) * 0.45
                            nz = 0.88
                        } else {
                            // Brushed silver screw head with subtle slot
                            let onSlot = abs(sdy) < 0.006 && abs(sdx) < 0.022
                            lum = onSlot ? 0.22 : 0.78 - smoothstep(0.0, 0.035, sr) * 0.14
                            rgb = (lum, lum, lum * 1.02)
                            mByte = onSlot ? 120 : 244
                        }
                    }

                    let invLen = 1.0 / max(sqrt(nx * nx + ny * ny + nz * nz), 1e-4)
                    let pIdx = (row * w + col) * 4
                    ptr[pIdx]     = clampByte(rgb.0)
                    ptr[pIdx + 1] = clampByte(rgb.1)
                    ptr[pIdx + 2] = clampByte(rgb.2)
                    ptr[pIdx + 3] = 255

                    normalBuf[pIdx]     = clampByte(0.5 + 0.5 * nx * invLen)
                    normalBuf[pIdx + 1] = clampByte(0.5 + 0.5 * ny * invLen)
                    normalBuf[pIdx + 2] = clampByte(0.5 + 0.5 * nz * invLen)
                    normalBuf[pIdx + 3] = 255

                    metalMask[row * w + col] = mByte
                }
            }

            // Crisp etched dark-silver "ZERO:2" logo along the lower faceplate edge (IMG_1868)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "AvenirNext-DemiBold", size: 28) ?? NSFont.systemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: NSColor(white: 0.08, alpha: 0.94),
                .kern: 2.2,
            ]
            let txt = NSAttributedString(string: "ZERO:2", attributes: attrs)
            let sz = txt.size()
            txt.draw(at: NSPoint(x: (W - sz.width) * 0.52, y: H * 0.27))
            NSGraphicsContext.restoreGraphicsState()
        }

        let normal = makePixelImage(w, h) { ptr, _, _, _ in
            normalBuf.withUnsafeBufferPointer { src in
                ptr.update(from: src.baseAddress!, count: w * h * 4)
            }
        }

        let metalness = makePixelImage(w, h) { ptr, _, _, _ in
            for i in 0..<(w * h) {
                let b = metalMask[i]
                let idx = i * 4
                ptr[idx] = b; ptr[idx + 1] = b; ptr[idx + 2] = b; ptr[idx + 3] = 255
            }
        }
        return (diffuse, normal, metalness)
    }

    /// Signature Tripowin C8 diagonal 2x2 twill carbon-fiber weave with metallic gunmetal end-bands
    /// for the 3.5mm plug barrel and Y-splitter.
    static func tripowinCarbon() -> (diffuse: CGImage, normal: CGImage) { cachedTripowinCarbon }
    static func makeTripowinCarbon() -> (diffuse: CGImage, normal: CGImage) {
        let w = 512, h = 512
        var normalBuf = [UInt8](repeating: 0, count: w * h * 4)

        let diffuse = makePixelImage(w, h) { ptr, _, _, _ in
            let towSize = 8
            for row in 0..<h {
                let v = Float(row) / Float(h - 1)
                let inTopBand = v < 0.135
                let inBotBand = v > 0.865
                let nearSeam = abs(v - 0.135) < 0.012 || abs(v - 0.865) < 0.012

                for col in 0..<w {
                    let pIdx = (row * w + col) * 4
                    var rgb: (Float, Float, Float)
                    var nx: Float = 0, ny: Float = 0, nz: Float = 1

                    if inTopBand || inBotBand {
                        // Metallic gunmetal lathe-turned end-band
                        let lathe = 0.5 + 0.5 * sin(Float(row) * 1.9 + valueNoise2D(Float(col) * 0.06, Float(row) * 0.9, 0xC801) * 2.0)
                        let baseG: Float = 0.21 + lathe * 0.045
                        rgb = (baseG * 0.96, baseG * 0.99, baseG * 1.08)
                        ny = (lathe - 0.5) * 0.12
                        nz = 0.99
                    } else {
                        // Diagonal 2x2 twill carbon-fiber weave (seamless around circumference)
                        let tx = (col / towSize) % (w / towSize)
                        let ty = row / towSize
                        let lx = Float(col % towSize) / Float(towSize)
                        let ly = Float(row % towSize) / Float(towSize)
                        let isWarp = ((tx + ty) & 3) < 2

                        if isWarp {
                            let arch = sin(ly * .pi)
                            let filament = 0.88 + 0.12 * sin(Float(row) * 2.5 + Float(tx) * 0.7)
                            let shade = (0.065 + 0.165 * arch) * filament
                            rgb = (shade * 0.95, shade * 0.98, shade * 1.06)
                            ny = -cos(ly * .pi) * 0.44
                            nx = -cos(lx * .pi) * 0.12
                            nz = 0.89
                        } else {
                            let arch = sin(lx * .pi)
                            let filament = 0.88 + 0.12 * sin(Float(col) * 2.5 + Float(ty) * 0.7)
                            let shade = (0.048 + 0.125 * arch) * filament
                            rgb = (shade * 0.94, shade * 0.97, shade * 1.05)
                            nx = -cos(lx * .pi) * 0.44
                            ny = -cos(ly * .pi) * 0.12
                            nz = 0.89
                        }
                    }

                    if nearSeam {
                        // Crisp dark chamfer groove between gunmetal end-band and carbon barrel
                        let seamFactor = 1.0 - min(abs(v - 0.135), abs(v - 0.865)) / 0.012
                        rgb = lerp3(rgb, (0.05, 0.055, 0.065), seamFactor * 0.85)
                        ny += (v < 0.5 ? 0.35 : -0.35) * seamFactor
                    }

                    let invLen = 1.0 / max(sqrt(nx * nx + ny * ny + nz * nz), 1e-4)
                    ptr[pIdx]     = clampByte(rgb.0)
                    ptr[pIdx + 1] = clampByte(rgb.1)
                    ptr[pIdx + 2] = clampByte(rgb.2)
                    ptr[pIdx + 3] = 255

                    normalBuf[pIdx]     = clampByte(0.5 + 0.5 * nx * invLen)
                    normalBuf[pIdx + 1] = clampByte(0.5 + 0.5 * ny * invLen)
                    normalBuf[pIdx + 2] = clampByte(0.5 + 0.5 * nz * invLen)
                    normalBuf[pIdx + 3] = 255
                }
            }
        }

        let normal = makePixelImage(w, h) { ptr, _, _, _ in
            normalBuf.withUnsafeBufferPointer { src in
                ptr.update(from: src.baseAddress!, count: w * h * 4)
            }
        }
        return (diffuse, normal)
    }

    /// Seamless 512x512 black 2-over-2 biaxial diamond braided nylon cable jacket texture
    /// (diffuse with yarn-crevice AO + fine filament highlights, matching central-difference normal map,
    /// and anisotropic nylon filament roughness map).
    static func braidedNylonCable() -> (diffuse: CGImage, normal: CGImage, roughness: CGImage) { cachedBraidedNylonCable }
    static func makeBraidedNylonCable() -> (diffuse: CGImage, normal: CGImage, roughness: CGImage) {
        let w = 512, h = 512
        let K: Float = 6.0 // even integer for seamless 2x2 diagonal twill wrap across u & v
        var heightField = [Float](repeating: 0, count: w * h)
        var roughField = [Float](repeating: 0.72, count: w * h)

        let diffuse = makePixelImage(w, h) { ptr, _, _, _ in
            for row in 0..<h {
                let v = Float(row) / Float(h)
                let rowOff = row * w
                for col in 0..<w {
                    let u = Float(col) / Float(w)
                    let p = K * (u + v)
                    let q = K * (u - v)
                    let ip = Int(floor(p)), fp = p - Float(ip)
                    let iq = Int(floor(q)), fq = q - Float(iq)

                    let tA = min(max((fp - 0.04) / 0.92, 0), 1)
                    let tB = min(max((fq - 0.04) / 0.92, 0), 1)
                    let profA = pow(sin(tA * .pi), 0.56)
                    let profB = pow(sin(tB * .pi), 0.56)

                    let archA = sin((Float(ip) + q) * (.pi * 0.5))
                    let archB = -sin((p + Float(iq)) * (.pi * 0.5))

                    let filA = 0.5 + 0.5 * sin(tA * 6.0 * 2.0 * .pi)
                    let filB = 0.5 + 0.5 * sin(tB * 6.0 * 2.0 * .pi)

                    let hA = profA * (0.48 + 0.34 * archA) + 0.052 * profA * filA
                    let hB = profB * (0.48 + 0.34 * archB) + 0.052 * profB * filB

                    let hVal = max(hA, hB)
                    let fil = (hA >= hB) ? filA : filB
                    let idx = rowOff + col
                    heightField[idx] = hVal

                    let crown = smoothstep(0.14, 0.80, hVal)
                    let microNoise = (valueNoise2D(u * 48.0, v * 48.0, 0xB8A1) - 0.5) * 0.012
                    let shade = max(0.014, 0.018 + crown * (0.048 + 0.028 * fil) + microNoise)
                    let pIdx = idx * 4
                    ptr[pIdx]     = clampByte(shade * 0.97)
                    ptr[pIdx + 1] = clampByte(shade * 0.99)
                    ptr[pIdx + 2] = clampByte(shade * 1.05)
                    ptr[pIdx + 3] = 255

                    roughField[idx] = 0.84 - crown * (0.38 + 0.09 * fil)
                }
            }
        }

        let normal = normalFromHeight(heightField, width: w, height: h, strength: 5.5)

        let roughness = makePixelImage(w, h) { ptr, _, _, _ in
            for i in 0..<(w * h) {
                let b = clampByte(roughField[i])
                let idx = i * 4
                ptr[idx] = b; ptr[idx + 1] = b; ptr[idx + 2] = b; ptr[idx + 3] = 255
            }
        }

        return (diffuse, normal, roughness)
    }

    /// Returns the pre-baked `ukiru-mat.jpg` enhanced with the upper-right vertical `ただいま` typography
    /// and slate-teal crosshatched cloud wave continuation visible on the real physical Ukiru mat,
    /// falling back to a procedural cotton twill image only when the resource image is missing.
    static func ukiruMatRefined(from base: NSImage?) -> CGImage {
        if let base, let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let w = cg.width, h = cg.height
            let ctx = CGContext(
                data: nil,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

            let W = CGFloat(w), H = CGFloat(h)
            // Crisp vertical Japanese lettering "ただいま" in the clean upper-right cream field below the clouds (IMG_1867).
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            let glyphFont = NSFont(name: "HiraginoSans-W5", size: H * 0.036)
                ?? NSFont(name: "HiraginoMaruGothicProN-W4", size: H * 0.036)
                ?? NSFont.systemFont(ofSize: H * 0.036, weight: .medium)
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: glyphFont,
                .foregroundColor: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 0.90),
            ]
            let chars = ["た", "だ", "い", "ま"]
            let centerX = W * 0.878
            let startY = H * 0.785
            let spacing = H * 0.050
            for (idx, ch) in chars.enumerated() {
                let s = NSAttributedString(string: ch, attributes: textAttrs)
                let sz = s.size()
                s.draw(at: NSPoint(x: centerX - sz.width * 0.5, y: startY - CGFloat(idx) * spacing - sz.height * 0.5))
            }
            NSGraphicsContext.restoreGraphicsState()

            return ctx.makeImage() ?? cg
        }
        return makePixelImage(512, 228) { ptr, _, _, _ in
            var seed: UInt64 = 0x51A0_2314
            for row in 0..<228 {
                for col in 0..<512 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let twill: Float = ((((col / 2) + (row / 2)) & 1) == 0 ? 1 : -1) * 0.006
                    let grain = (Float((seed >> 16) & 0xFF) / 255.0 - 0.5) * 0.012
                    let idx = (row * 512 + col) * 4
                    ptr[idx]     = clampByte(0.848 + twill + grain)
                    ptr[idx + 1] = clampByte(0.830 + twill + grain)
                    ptr[idx + 2] = clampByte(0.800 + twill + grain)
                    ptr[idx + 3] = 255
                }
            }
        }
    }

}
