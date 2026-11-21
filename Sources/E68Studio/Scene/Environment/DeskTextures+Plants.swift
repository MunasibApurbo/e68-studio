import AppKit
import CoreGraphics
import ImageIO
import simd

extension DeskTextures {
    // MARK: - Plants

    enum LeafKind { case pothos, bamboo, dieffenbachia }

    struct PlantPBRMaps: @unchecked Sendable {
        let diffuse: CGImage
        let normal: CGImage
        let roughness: CGImage?
    }

    static func loadPlantImage(_ file: String) -> CGImage? {
        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let url = KeyboardScene.resourceURL("Plants/\(file)"),
              let source = CGImageSourceCreateWithURL(url as CFURL, noCache) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, noCache)
    }

    static func plantStemTexture() -> CGImage? { cachedPlantStem }
    static func plantRootTexture() -> CGImage? { cachedPlantRoot }

    static func leafPBRTexture(kind: LeafKind) -> PlantPBRMaps {
        switch kind {
        case .pothos: return cachedLeafPothos
        case .bamboo: return cachedLeafBamboo
        case .dieffenbachia: return cachedLeafDieffenbachia
        }
    }

    static func makeLeafPBR(kind: LeafKind) -> PlantPBRMaps {
        let proc = makeLeafTexture(kind: kind)
        return PlantPBRMaps(diffuse: proc.diffuse, normal: proc.normal, roughness: nil)
    }

    /// Three procedural Golden Pothos blade textures with varied golden-chartreuse marbling.
    static func makeProceduralPothosVariants() -> [PlantPBRMaps] {
        (0..<3).map { seed in
            let proc = makeLeafTexture(kind: .pothos, variantSeed: seed)
            return PlantPBRMaps(diffuse: proc.diffuse, normal: proc.normal, roughness: nil)
        }
    }

    static func makeLeafTexture(kind: LeafKind, variantSeed: Int = 0) -> (diffuse: CGImage, normal: CGImage) {
        let w = 512, h = 1024
        var heightField = [Float](repeating: 0, count: w * h)

        let diffuse = makePixelImage(w, h) { ptr, ctx, W, H in
            let seedShift = Float(variantSeed) * 19.7
            for row in 0..<h {
                // vLeaf: 0 at petiole base (y_cg = 0), 1 at leaf tip (y_cg = H)
                let vLeaf = 1.0 - Float(row) / Float(h - 1)
                let rowOff = row * w
                for col in 0..<w {
                    let u = Float(col) / Float(w - 1)
                    let side = (u - 0.5) * 2.0
                    let ax = abs(side)
                    let idx = rowOff + col
                    let pIdx = idx * 4

                    // Curved lateral vein coordinate (constant along each lateral vein)
                    let veinV = vLeaf - 0.125 * pow(ax, 1.28)
                    var rgb: (Float, Float, Float)
                    var height: Float = 0

                    switch kind {
                    case .pothos:
                        let sideOffset: Float = (side < 0 ? 5.7 : 17.3) + seedShift
                        let leafTone = fbm2D(ax * 2.8 + sideOffset, veinV * 3.8, 0xA01 + UInt32(variantSeed * 7), octaves: 3)
                        let marginShade = smoothstep(0.50, 0.96, ax)
                        let deepEmerald: (Float, Float, Float) = (0.072, 0.255, 0.052)
                        let richGreen: (Float, Float, Float)   = (0.145, 0.380, 0.085)
                        let limeGreen: (Float, Float, Float)   = (0.310, 0.535, 0.132)
                        rgb = lerp3(deepEmerald, richGreen, smoothstep(0.18, 0.80, leafTone) * (1.0 - 0.28 * marginShade))

                        let sectorField = fbm2D(ax * 1.9 + sideOffset, veinV * 3.2, 0xB02 + UInt32(variantSeed * 11), octaves: 4)
                        let featherWarp = fbm2D(ax * 6.5 + sideOffset * 0.5, veinV * 16.0, 0xC03, octaves: 3)
                        let veinStreaks = fbm2D(ax * 12.0 + featherWarp * 2.0, veinV * 32.0 + featherWarp * 1.1, 0xD04, octaves: 3)
                        let warpedAx = ax + (featherWarp - 0.5) * 0.24
                        let bladeMask = smoothstep(0.02, 0.14, warpedAx) * (1.0 - smoothstep(0.84, 1.02, warpedAx))
                            * smoothstep(0.05, 0.15, vLeaf) * (1.0 - smoothstep(0.84, 0.97, vLeaf))
                        let varBias: Float = variantSeed == 2 ? 0.08 : (variantSeed == 1 ? 0.04 : -0.01)
                        let varieg = (sectorField * 0.62 + veinStreaks * 0.38 + varBias) * (0.42 + 0.58 * bladeMask)

                        // Golden pothos chartreuse & warm cream-gold marbling along lateral veins
                        if varieg > 0.47 {
                            let limeMix = smoothstep(0.47, 0.64, varieg)
                            rgb = lerp3(rgb, limeGreen, limeMix * 0.88)
                        }
                        if varieg > 0.59 {
                            let goldMix = smoothstep(0.59, 0.75, varieg)
                            rgb = lerp3(rgb, (0.54, 0.68, 0.21), goldMix * 0.84)
                        }
                        if varieg > 0.72 {
                            let creamMix = smoothstep(0.72, 0.87, varieg)
                            rgb = lerp3(rgb, (0.76, 0.82, 0.45), creamMix * 0.80)
                        }

                        let midribGroove = -0.52 * exp(-pow(abs(u - 0.5) / 0.014, 2))
                        let veinWave = abs(sin(veinV * .pi * 8.0))
                        let interVeinPillow = 0.20 * pow(veinWave, 0.65) * sin(min(ax / 0.92, 1.0) * .pi)
                        let lateralGroove = -0.15 * exp(-pow((1.0 - veinWave) / 0.085, 2)) * smoothstep(0.02, 0.10, ax)
                        let cellMicro = 0.030 * (fbm2D(u * 22.0, vLeaf * 42.0, 0xE05, octaves: 2) - 0.5)
                        height = midribGroove + interVeinPillow + lateralGroove + cellMicro

                    case .bamboo:
                        let uConv = (u - 0.5) / max(0.35, 1.0 - 0.38 * vLeaf)
                        let warp = fbm2D(uConv * 9.0, vLeaf * 4.5, 0xF01, octaves: 2) * 0.75
                        let fineStriation = 0.5 + 0.5 * sin(uConv * 145.0 + warp)
                        let broadBand = fbm2D(uConv * 14.0, vLeaf * 2.8, 0xF02, octaves: 3)
                        let baseSheathMix = 1.0 - smoothstep(0.0, 0.22, vLeaf)
                        let darkJade: (Float, Float, Float)  = (0.145, 0.340, 0.092)
                        let brightJade: (Float, Float, Float) = (0.245, 0.470, 0.142)
                        rgb = lerp3(darkJade, brightJade, smoothstep(0.20, 0.80, broadBand * 0.70 + fineStriation * 0.30))
                        rgb = lerp3(rgb, (0.31, 0.51, 0.17), baseSheathMix * 0.38)

                        let edgeBand = smoothstep(0.78, 0.93, ax) * (1.0 - smoothstep(0.96, 1.0, ax))
                        rgb = lerp3(rgb, (0.40, 0.58, 0.20), edgeBand * 0.36)

                        let midribGroove = -0.26 * exp(-pow(abs(u - 0.5) / 0.013, 2))
                        let flutes = 0.055 * sin(uConv * 95.0 + warp * 0.5)
                        height = midribGroove + flutes

                    case .dieffenbachia:
                        let sideOffset: Float = side < 0 ? 3.1 : 13.7
                        let baseVar = fbm2D(ax * 3.5 + sideOffset, veinV * 5.0, 0xD10, octaves: 3)
                        let outerOlive: (Float, Float, Float) = (0.165, 0.365, 0.094)
                        let innerChartreuse: (Float, Float, Float) = (0.310, 0.515, 0.155)
                        let centerBlend = (1.0 - smoothstep(0.18, 0.78, ax)) * smoothstep(0.04, 0.16, vLeaf) * (1.0 - smoothstep(0.84, 0.97, vLeaf))
                        rgb = lerp3(outerOlive, innerChartreuse, baseVar * 0.42 + centerBlend * 0.48)

                        // Prominent scattered crisp white/cream speckles & flecks concentrated in inner intercostal blade (IMG_1862/1864)
                        let clusterMask = fbm2D(ax * 4.0 + sideOffset, veinV * 6.0, 0xD20, octaves: 3)
                        let fineDots = fbm2D(ax * 14.5 + sideOffset * 1.7 + clusterMask * 1.1, veinV * 24.0, 0xD31, octaves: 2)
                        let microFlecks = fbm2D(ax * 30.0 + sideOffset * 2.3, veinV * 54.0, 0xD42, octaves: 2)
                        let innerMask = smoothstep(0.03, 0.12, ax) * (1.0 - smoothstep(0.66, 0.88, ax))
                            * smoothstep(0.05, 0.14, vLeaf) * (1.0 - smoothstep(0.82, 0.95, vLeaf))
                        let spotField = (fineDots * 0.62 + microFlecks * 0.38) * (0.50 + 0.50 * smoothstep(0.28, 0.72, clusterMask)) * innerMask

                        if spotField > 0.39 {
                            let chartMix = smoothstep(0.39, 0.49, spotField)
                            rgb = lerp3(rgb, (0.62, 0.76, 0.38), chartMix * 0.80)
                        }
                        if spotField > 0.46 {
                            let whiteMix = smoothstep(0.46, 0.57, spotField)
                            rgb = lerp3(rgb, (0.90, 0.92, 0.76), whiteMix * 0.95)
                        }

                        let midribGroove = -0.38 * exp(-pow(abs(u - 0.5) / 0.018, 2))
                        let veinWave = abs(sin(veinV * .pi * 7.5))
                        let interVeinPillow = 0.16 * pow(veinWave, 0.65) * sin(min(ax / 0.92, 1.0) * .pi)
                        let lateralGroove = -0.14 * exp(-pow((1.0 - veinWave) / 0.085, 2)) * smoothstep(0.02, 0.10, ax)
                        height = midribGroove + interVeinPillow + lateralGroove
                    }

                    ptr[pIdx]     = clampByte(rgb.0)
                    ptr[pIdx + 1] = clampByte(rgb.1)
                    ptr[pIdx + 2] = clampByte(rgb.2)
                    ptr[pIdx + 3] = 255
                    heightField[idx] = height
                }
            }

            // Crisp tapered midrib vein
            let midribColor = (kind == .pothos)
                ? NSColor(srgbRed: 0.70, green: 0.78, blue: 0.44, alpha: 0.68)
                : (kind == .dieffenbachia
                   ? NSColor(srgbRed: 0.68, green: 0.79, blue: 0.46, alpha: 0.82)
                   : NSColor(srgbRed: 0.44, green: 0.62, blue: 0.24, alpha: 0.62))
            ctx.setStrokeColor(midribColor.cgColor)
            ctx.setLineCap(.round)
            let segments = 16
            for s in 0..<segments {
                let t0 = CGFloat(s) / CGFloat(segments)
                let t1 = CGFloat(s + 1) / CGFloat(segments)
                let wBase: CGFloat = (kind == .bamboo ? 3.4 : (kind == .dieffenbachia ? 7.2 : 5.0)) * (1.0 - t0 * 0.70)
                ctx.setLineWidth(wBase)
                ctx.move(to: CGPoint(x: W * 0.5, y: t0 * H))
                ctx.addLine(to: CGPoint(x: W * 0.5, y: t1 * H))
                ctx.strokePath()
            }

            // Curved secondary lateral veins + fine translucent tertiary vein networks
            if kind == .bamboo {
                ctx.setStrokeColor(NSColor(srgbRed: 0.36, green: 0.56, blue: 0.19, alpha: 0.32).cgColor)
                ctx.setLineWidth(1.3)
                for i in 1..<18 {
                    let ox = CGFloat(i) / 18.0 * W * 0.44
                    ctx.move(to: CGPoint(x: W * 0.5 - ox, y: 0))
                    ctx.addLine(to: CGPoint(x: W * 0.5 - ox * 0.26, y: H))
                    ctx.move(to: CGPoint(x: W * 0.5 + ox, y: 0))
                    ctx.addLine(to: CGPoint(x: W * 0.5 + ox * 0.26, y: H))
                    ctx.strokePath()
                }
            } else {
                let count = 9
                for i in 1..<count {
                    let yL = CGFloat(i) / CGFloat(count) * H
                    let yR = yL + (i % 2 == 0 ? 18 : -14)

                    // Primary lateral veins
                    let latAlpha: CGFloat = (kind == .pothos) ? 0.32 : 0.38
                    ctx.setStrokeColor(NSColor(srgbRed: 0.56, green: 0.72, blue: 0.30, alpha: latAlpha).cgColor)
                    ctx.setLineWidth(2.0)
                    ctx.move(to: CGPoint(x: W * 0.5, y: yL))
                    ctx.addQuadCurve(to: CGPoint(x: W * 0.06, y: yL + 115), control: CGPoint(x: W * 0.22, y: yL + 32))
                    ctx.move(to: CGPoint(x: W * 0.5, y: yR))
                    ctx.addQuadCurve(to: CGPoint(x: W * 0.94, y: yR + 115), control: CGPoint(x: W * 0.78, y: yR + 32))
                    ctx.strokePath()

                    // Fine translucent tertiary veinlets branching between lateral veins
                    ctx.setStrokeColor(NSColor(srgbRed: 0.66, green: 0.80, blue: 0.42, alpha: 0.16).cgColor)
                    ctx.setLineWidth(0.9)
                    for b in 1...4 {
                        let frac = CGFloat(b) / 5.0
                        let bxL = W * (0.5 - frac * 0.40)
                        let byL = yL + pow(frac, 1.25) * 95
                        ctx.move(to: CGPoint(x: bxL, y: byL))
                        ctx.addQuadCurve(to: CGPoint(x: bxL - 28, y: byL + 46), control: CGPoint(x: bxL - 8, y: byL + 26))

                        let bxR = W * (0.5 + frac * 0.40)
                        let byR = yR + pow(frac, 1.25) * 95
                        ctx.move(to: CGPoint(x: bxR, y: byR))
                        ctx.addQuadCurve(to: CGPoint(x: bxR + 28, y: byR + 46), control: CGPoint(x: bxR + 8, y: byR + 26))
                    }
                    ctx.strokePath()
                }
            }
        }

        // Convert scalar leaf heightfield to tangent-space normal map via central differences
        let normal = makePixelImage(w, h) { ptr, _, _, _ in
            let strength: Float = (kind == .bamboo) ? 3.2 : 6.0
            for row in 0..<h {
                let rPrev = max(0, row - 1), rNext = min(h - 1, row + 1)
                let rowOff = row * w
                for col in 0..<w {
                    let cPrev = max(0, col - 1), cNext = min(w - 1, col + 1)
                    let dhdx = (heightField[rowOff + cNext] - heightField[rowOff + cPrev]) * strength
                    let dhdy = (heightField[rNext * w + col] - heightField[rPrev * w + col]) * strength
                    let nx = -dhdx
                    let ny = dhdy
                    let nz: Float = 1.0
                    let invLen = 1.0 / sqrt(nx * nx + ny * ny + nz * nz)
                    let pIdx = (rowOff + col) * 4
                    ptr[pIdx]     = clampByte(0.5 + 0.5 * nx * invLen)
                    ptr[pIdx + 1] = clampByte(0.5 + 0.5 * ny * invLen)
                    ptr[pIdx + 2] = clampByte(0.5 + 0.5 * nz * invLen)
                    ptr[pIdx + 3] = 255
                }
            }
        }
        return (diffuse, normal)
    }

    /// Natural segmented cane PBR maps (diffuse, normal, roughness).
    static func canePBRTexture(isDieffenbachia: Bool = false) -> PlantPBRMaps {
        isDieffenbachia ? cachedCaneDieffenbachia : cachedCaneBamboo
    }

    static func makeCanePBR(isDieffenbachia: Bool) -> PlantPBRMaps {
        let prefix = isDieffenbachia ? "dieff_cane" : "bamboo_cane"
        if let diff = loadPlantImage("\(prefix)_diff.jpg"),
           let norm = loadPlantImage("\(prefix)_norm.png") {
            return PlantPBRMaps(
                diffuse: diff,
                normal: norm,
                roughness: loadPlantImage("\(prefix)_rough.png")
            )
        }
        let defaultNodes: [Float] = isDieffenbachia
            ? [0.12, 0.28, 0.44, 0.60, 0.76, 0.90]
            : [0.14, 0.28, 0.43, 0.58, 0.72, 0.85, 0.94]
        let proc = makeProceduralCaneTexture(nodeFractions: defaultNodes, isDieffenbachia: isDieffenbachia)
        return PlantPBRMaps(diffuse: proc.diffuse, normal: proc.normal, roughness: nil)
    }

    private static func makeProceduralCaneTexture(nodeFractions: [Float], isDieffenbachia: Bool = false) -> (diffuse: CGImage, normal: CGImage) {
        let w = 256, h = 512
        var heightField = [Float](repeating: 0, count: w * h)

        let diffuse = makePixelImage(w, h) { ptr, _, _, _ in
            for row in 0..<h {
                let v = Float(row) / Float(h - 1)
                let rowOff = row * w
                var nodeGlow: Float = 0
                var nodeCrease: Float = 0
                for nf in nodeFractions {
                    let dv = v - nf
                    nodeGlow = max(nodeGlow, exp(-pow(dv / 0.014, 2)))
                    nodeCrease = max(nodeCrease, exp(-pow((dv - 0.004) / 0.0035, 2)))
                }

                for col in 0..<w {
                    let u = Float(col) / Float(w - 1)
                    let angle = u * 2.0 * .pi
                    let fiber = 0.5 + 0.5 * sin(angle * 28.0 + fbm2D(cos(angle) * 2.5, v * 8.0, 0xCA1, octaves: 2) * 3.0)
                    let mottle = fbm2D(cos(angle) * 3.2 + 1.5, v * 10.0, 0xCA2, octaves: 3)

                    let baseDark: (Float, Float, Float) = isDieffenbachia ? (0.14, 0.30, 0.085) : (0.13, 0.31, 0.085)
                    let baseLight: (Float, Float, Float) = isDieffenbachia ? (0.28, 0.46, 0.14) : (0.24, 0.44, 0.13)
                    var rgb = lerp3(baseDark, baseLight, smoothstep(0.25, 0.80, mottle * 0.68 + fiber * 0.32))

                    let collarColor: (Float, Float, Float) = isDieffenbachia ? (0.40, 0.52, 0.24) : (0.31, 0.47, 0.18)
                    rgb = lerp3(rgb, collarColor, nodeGlow * 0.55)
                    rgb = lerp3(rgb, (0.09, 0.18, 0.05), nodeCrease * 0.45)

                    let baseTint = 1.0 - smoothstep(0.0, 0.16, v)
                    rgb = lerp3(rgb, (0.22, 0.32, 0.12), baseTint * 0.30)

                    let idx = rowOff + col
                    let pIdx = idx * 4
                    ptr[pIdx]     = clampByte(rgb.0)
                    ptr[pIdx + 1] = clampByte(rgb.1)
                    ptr[pIdx + 2] = clampByte(rgb.2)
                    ptr[pIdx + 3] = 255
                    heightField[idx] = (fiber - 0.5) * 0.12 + nodeGlow * 0.32 - nodeCrease * 0.45
                }
            }
        }

        let normal = makePixelImage(w, h) { ptr, _, _, _ in
            for row in 0..<h {
                let rPrev = max(0, row - 1), rNext = min(h - 1, row + 1)
                let rowOff = row * w
                for col in 0..<w {
                    let cPrev = (col - 1 + w) % w, cNext = (col + 1) % w
                    let dhdx = (heightField[rowOff + cNext] - heightField[rowOff + cPrev]) * 2.8
                    let dhdy = (heightField[rNext * w + col] - heightField[rPrev * w + col]) * 2.8
                    let nx = -dhdx, ny = -dhdy, nz: Float = 1.0
                    let invLen = 1.0 / sqrt(nx * nx + ny * ny + nz * nz)
                    let pIdx = (rowOff + col) * 4
                    ptr[pIdx]     = clampByte(0.5 + 0.5 * nx * invLen)
                    ptr[pIdx + 1] = clampByte(0.5 + 0.5 * ny * invLen)
                    ptr[pIdx + 2] = clampByte(0.5 + 0.5 * nz * invLen)
                    ptr[pIdx + 3] = 255
                }
            }
        }
        return (diffuse, normal)
    }

    /// Soft focused refractive caustic light pattern cast onto the desk beneath water-filled glass vessels.
    static func waterCausticTexture() -> CGImage { cachedWaterCaustic }
    static func makeWaterCausticTexture() -> CGImage {
        let w = 256, h = 256
        return makePixelImage(w, h) { ptr, _, _, _ in
            for row in 0..<h {
                let y = (Float(row) / Float(h - 1)) * 2.0 - 1.0
                for col in 0..<w {
                    let x = (Float(col) / Float(w - 1)) * 2.0 - 1.0
                    let r = sqrt(x * x + y * y)
                    let a = atan2(y, x)
                    // Asymmetric focused crescent caustic (no uniform white halo ring)
                    let focusDist = sqrt(pow(x - 0.14, 2) + pow(y - 0.36, 2))
                    let crescent = exp(-pow((r - 0.56) / 0.11, 2)) * smoothstep(-0.1, 0.85, y * 0.85 + x * 0.35)
                    let core = exp(-pow(focusDist / 0.28, 2)) * 0.65
                    let ripple = 0.76 + 0.24 * sin(a * 4.0 + r * 9.0) * cos(a * 3.0 - r * 6.0)
                    let edgeFade = 1.0 - smoothstep(0.62, 0.96, r)
                    let intensity = (crescent * 0.85 + core) * ripple * edgeFade
                    let pIdx = (row * w + col) * 4
                    ptr[pIdx]     = clampByte(min(1.0, intensity * 0.98))
                    ptr[pIdx + 1] = clampByte(min(1.0, intensity * 0.78))
                    ptr[pIdx + 2] = clampByte(min(1.0, intensity * 0.88))
                    ptr[pIdx + 3] = clampByte(min(1.0, intensity))
                }
            }
        }
    }
}
