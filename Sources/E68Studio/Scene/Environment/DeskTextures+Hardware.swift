import AppKit
import CoreGraphics
import simd

extension DeskTextures {
    // MARK: - MCHOSE G7 Mouse, Brushed Metal & Mac mini Aluminum

    /// Satin warm-white micro-matte shell texture (calibrated <= 0.85 albedo) + crisp MCHOSE 'K' emblem + PTFE skates.
    static func mchoseTopShell() -> CGImage { cachedMchoseTopShell }
    static func makeMchoseTopShell() -> CGImage {
        let w = 1024, h = 768
        return makePixelImage(w, h) { ptr, ctx, W, H in
            var seed: UInt64 = 0x7A4B_91C3
            for row in 0..<h {
                let v = Float(row) / Float(h - 1)
                for col in 0..<w {
                    let u = Float(col) / Float(w - 1)
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let grain = (Float((seed >> 16) & 0xFF) / 255.0 - 0.5) * 0.014
                    let underMask = max(0, min(1, (abs(u - 0.75) < 0.22 ? 1.0 - abs(u - 0.75) / 0.22 : 0)))
                    let bellyShade: Float = underMask * 0.045 + 0.008 * sin(v * .pi)
                    let idx = (row * w + col) * 4
                    ptr[idx]     = clampByte(0.848 + grain - bellyShade)
                    ptr[idx + 1] = clampByte(0.843 + grain - bellyShade)
                    ptr[idx + 2] = clampByte(0.832 + grain - bellyShade * 0.92)
                    ptr[idx + 3] = 255
                }
            }
            func px(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: u * W, y: (1 - v) * H) }

            // Subtle "MCHOSE" wordmark along the front-right flank below the right click paddle, reading toward the nose.
            ctx.saveGState()
            let mark = px(0.044, 0.295)
            ctx.translateBy(x: mark.x, y: mark.y)
            ctx.rotate(by: .pi / 2)
            ctx.scaleBy(x: 1, y: -1)
            let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 9.5, nil)
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor(srgbRed: 0.54, green: 0.55, blue: 0.565, alpha: 0.85).cgColor,
                NSAttributedString.Key(kCTKernAttributeName as String): 2.6,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "MCHOSE", attributes: attrs))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.textPosition = CGPoint(x: -width / 2, y: -4)
            CTLineDraw(line, ctx)
            ctx.restoreGState()

            // Crisp grey MCHOSE two-piece geometric ribbon "K" emblem on the palm hump, mirrored for the u direction.
            let s: CGFloat = 56
            let c = px(0.25, 0.725)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.scaleBy(x: -0.70, y: 1.0)
            ctx.setShouldAntialias(true)
            ctx.setAllowsAntialiasing(true)
            func poly(_ p: [CGPoint]) -> CGPath {
                let path = CGMutablePath()
                path.addLines(between: p.map { CGPoint(x: $0.x * s, y: $0.y * s) })
                path.closeSubpath()
                return path
            }
            let mainRibbon = poly([
                CGPoint(x: -0.50, y:  0.44),
                CGPoint(x: -0.44, y:  0.44),
                CGPoint(x: -0.17, y:  0.17),
                CGPoint(x:  0.16, y:  0.50),
                CGPoint(x:  0.48, y:  0.50),
                CGPoint(x:  0.00, y:  0.02),
                CGPoint(x:  0.50, y: -0.48),
                CGPoint(x:  0.18, y: -0.48),
                CGPoint(x: -0.50, y:  0.20),
            ])
            let cornerTri = poly([
                CGPoint(x: -0.50, y:  0.01),
                CGPoint(x: -0.50, y: -0.48),
                CGPoint(x: -0.01, y: -0.48),
            ])
            let logoGrad = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [
                    NSColor(srgbRed: 0.60, green: 0.61, blue: 0.63, alpha: 0.92).cgColor,
                    NSColor(srgbRed: 0.42, green: 0.43, blue: 0.45, alpha: 0.92).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )!
            ctx.saveGState()
            ctx.addPath(mainRibbon)
            ctx.addPath(cornerTri)
            ctx.clip()
            ctx.drawLinearGradient(logoGrad, start: CGPoint(x: 0, y: 0.5 * s), end: CGPoint(x: 0, y: -0.5 * s), options: [])
            ctx.restoreGState()
            ctx.restoreGState()

            // Underside PTFE skates, sensor aperture, DPI & mode switches
            func drawPTFEPath(_ path: CGPath, bounds: CGRect, recessWidth: CGFloat = 4.5) {
                ctx.saveGState()
                ctx.setStrokeColor(NSColor(srgbRed: 0.42, green: 0.42, blue: 0.43, alpha: 0.85).cgColor)
                ctx.setLineWidth(recessWidth)
                ctx.setLineJoin(.round)
                ctx.addPath(path)
                ctx.strokePath()
                ctx.restoreGState()

                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                let ptfeGrad = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [
                        NSColor(srgbRed: 0.82, green: 0.83, blue: 0.84, alpha: 1).cgColor,
                        NSColor(srgbRed: 0.74, green: 0.75, blue: 0.77, alpha: 1).cgColor,
                    ] as CFArray,
                    locations: [0, 1]
                )!
                ctx.drawLinearGradient(ptfeGrad, start: bounds.origin, end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [])
                ctx.restoreGState()

                ctx.setStrokeColor(NSColor(white: 0.88, alpha: 0.55).cgColor)
                ctx.setLineWidth(1.0)
                ctx.addPath(path)
                ctx.strokePath()
            }

            func drawPTFERoundRect(_ rect: CGRect, radius: CGFloat) {
                drawPTFEPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil), bounds: rect)
            }

            let frontPts = [
                px(0.75, 0.12), px(0.84, 0.19), px(0.84, 0.27), px(0.66, 0.27), px(0.66, 0.19),
            ]
            let frontPath = CGMutablePath()
            frontPath.addLines(between: frontPts)
            frontPath.closeSubpath()
            drawPTFEPath(frontPath, bounds: frontPath.boundingBox, recessWidth: 5.0)

            ctx.saveGState()
            let g7Pos = px(0.75, 0.34)
            ctx.translateBy(x: g7Pos.x, y: g7Pos.y)
            ctx.scaleBy(x: -0.70, y: 1.0)
            let g7Font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 12, nil)
            let g7Line = CTLineCreateWithAttributedString(NSAttributedString(string: "G7", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): g7Font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor(srgbRed: 0.58, green: 0.59, blue: 0.60, alpha: 0.80).cgColor,
            ]))
            let g7W = CTLineGetTypographicBounds(g7Line, nil, nil, nil)
            ctx.textPosition = CGPoint(x: -g7W / 2, y: -4)
            CTLineDraw(g7Line, ctx)
            ctx.restoreGState()

            let sensorCenter = px(0.75, 0.49)
            let sensorRing = CGRect(x: sensorCenter.x - 22, y: sensorCenter.y - 26, width: 44, height: 52)
            drawPTFERoundRect(sensorRing, radius: 22)
            ctx.setFillColor(NSColor(white: 0.14, alpha: 1).cgColor)
            ctx.addPath(CGPath(roundedRect: sensorRing.insetBy(dx: 12, dy: 12), cornerWidth: 10, cornerHeight: 14, transform: nil))
            ctx.fillPath()

            let dpiCenter = px(0.835, 0.49)
            let dpiRect = CGRect(x: dpiCenter.x - 8, y: dpiCenter.y - 16, width: 16, height: 32)
            ctx.setFillColor(NSColor(white: 0.42, alpha: 0.9).cgColor)
            ctx.addPath(CGPath(roundedRect: dpiRect.insetBy(dx: -2, dy: -2), cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(NSColor(srgbRed: 0.80, green: 0.80, blue: 0.81, alpha: 1).cgColor)
            ctx.addPath(CGPath(roundedRect: dpiRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
            ctx.fillPath()

            let swCenter = px(0.665, 0.49)
            let swRect = CGRect(x: swCenter.x - 8, y: swCenter.y - 16, width: 16, height: 32)
            ctx.setFillColor(NSColor(white: 0.42, alpha: 0.9).cgColor)
            ctx.addPath(CGPath(roundedRect: swRect.insetBy(dx: -2, dy: -2), cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(NSColor(srgbRed: 0.72, green: 0.73, blue: 0.74, alpha: 1).cgColor)
            ctx.addPath(CGPath(roundedRect: swRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: swCenter.x - 6, y: swCenter.y - 6, width: 12, height: 12))

            let thumbSkateTop = px(0.60, 0.48)
            let thumbSkateBot = px(0.56, 0.76)
            drawPTFERoundRect(CGRect(x: min(thumbSkateTop.x, thumbSkateBot.x) - 10, y: thumbSkateBot.y,
                                     width: 24, height: thumbSkateTop.y - thumbSkateBot.y), radius: 10)
            let rightSkateTop = px(0.90, 0.58)
            let rightSkateBot = px(0.90, 0.77)
            drawPTFERoundRect(CGRect(x: rightSkateTop.x - 10, y: rightSkateBot.y,
                                     width: 20, height: rightSkateTop.y - rightSkateBot.y), radius: 9)

            let bayTop = px(0.70, 0.69)
            let bayBot = px(0.80, 0.81)
            let bayRect = CGRect(x: bayTop.x, y: bayBot.y, width: bayBot.x - bayTop.x, height: bayTop.y - bayBot.y)
            ctx.setStrokeColor(NSColor(white: 0.45, alpha: 0.75).cgColor)
            ctx.setLineWidth(1.8)
            ctx.addPath(CGPath(roundedRect: bayRect, cornerWidth: 5, cornerHeight: 5, transform: nil))
            ctx.strokePath()
            ctx.setFillColor(NSColor(white: 0.16, alpha: 0.92).cgColor)
            ctx.fill(CGRect(x: bayRect.minX + 10, y: bayRect.maxY - 12, width: bayRect.width - 20, height: 3.5))

            let rearTop = px(0.65, 0.85)
            let rearBot = px(0.85, 0.93)
            drawPTFERoundRect(CGRect(x: rearTop.x, y: rearBot.y, width: rearBot.x - rearTop.x, height: rearTop.y - rearBot.y), radius: 18)
        }
    }

    static func mchoseRoughness() -> CGImage { cachedMchoseRoughness }
    static func makeMchoseRoughness() -> CGImage {
        let w = 512, h = 512
        return makePixelImage(w, h) { ptr, _, _, _ in
            var seed: UInt64 = 0x1234_5678_9ABC
            for row in 0..<h {
                for col in 0..<w {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let n1 = Float((seed >> 16) & 0xFF) / 255.0
                    let n2 = Float((seed >> 32) & 0xFF) / 255.0
                    let b = clampByte(0.42 + (n1 * 0.65 + n2 * 0.35) * 0.09)
                    let idx = (row * w + col) * 4
                    ptr[idx] = b; ptr[idx + 1] = b; ptr[idx + 2] = b; ptr[idx + 3] = 255
                }
            }
        }
    }

    /// Fine horizontal brushing for bead-blasted / brushed aluminium.
    static func brushedNormal() -> CGImage { cachedBrushedNormal }
    static func makeBrushedNormal() -> CGImage {
        let w = 256, h = 256
        return makePixelImage(w, h) { ptr, _, _, _ in
            for row in 0..<h {
                let rowShift = (hash2D(0, row, 0xA1A1) - 0.5) * 0.14
                for col in 0..<w {
                    let fine = (hash2D(col >> 2, row, 0xA1A2) - 0.5) * 0.04
                    let ny = min(max(0.5 + rowShift + fine, 0.35), 0.65)
                    let idx = (row * w + col) * 4
                    ptr[idx]     = 128
                    ptr[idx + 1] = clampByte(ny)
                    ptr[idx + 2] = 254
                    ptr[idx + 3] = 255
                }
            }
        }
    }

    /// Seamless tileable micro-textured injection-molded PBT / satin powdercoat normal map.
    static func pbtMicroNormal() -> CGImage { cachedPbtMicroNormal }
    static func makePbtMicroNormal() -> CGImage {
        let w = 256, h = 256
        var hf = [Float](repeating: 0, count: w * h)
        for row in 0..<h {
            let fy = Float(row) / Float(h)
            let rowOff = row * w
            for col in 0..<w {
                let fx = Float(col) / Float(w)
                let wx = col & 511, wy = row & 511
                let fine = hash2D(wx, wy, 0x5042_01)
                let med = hash2D(wx >> 1, wy >> 1, 0x5042_02)
                let micro = tileableNoise2D(fx * 192, fy * 192, periodX: 192, periodY: 192, 0x5042_03)
                hf[rowOff + col] = fine * 0.56 + med * 0.26 + micro * 0.18
            }
        }
        return normalFromHeight(hf, width: w, height: h, strength: 0.36, invertY: false)
    }

    /// Seamless, tileable isotropic bead-blasted anodized aluminum (diffuse, roughness, micro-grain normal).
    static func macMiniAluminum() -> (diffuse: CGImage, roughness: CGImage, normal: CGImage) { cachedMacMiniAluminum }
    static func makeMacMiniAluminum() -> (diffuse: CGImage, roughness: CGImage, normal: CGImage) {
        let w = 512, h = 512
        var heightField = [Float](repeating: 0, count: w * h)

        for row in 0..<h {
            let rowOff = row * w
            for col in 0..<w {
                let wx = col & 511, wy = row & 511
                let fine = hash2D(wx, wy, 0x4D41_01)
                let med = hash2D(wx >> 1, wy >> 1, 0x4D41_02)
                let coarse = hash2D(wx >> 3, wy >> 3, 0x4D41_03)
                heightField[rowOff + col] = fine * 0.48 + med * 0.34 + coarse * 0.18
            }
        }

        let diffuse = makePixelImage(w, h) { ptr, _, _, _ in
            for i in 0..<(w * h) {
                let hf = heightField[i] - 0.5
                let p = i * 4
                ptr[p]     = clampByte(0.842 + hf * 0.024)
                ptr[p + 1] = clampByte(0.848 + hf * 0.024)
                ptr[p + 2] = clampByte(0.858 + hf * 0.025)
                ptr[p + 3] = 255
            }
        }

        let roughness = makePixelImage(w, h) { ptr, _, _, _ in
            for i in 0..<(w * h) {
                let hf = heightField[i] - 0.5
                let b = clampByte(0.285 + hf * 0.065)
                let p = i * 4
                ptr[p] = b; ptr[p + 1] = b; ptr[p + 2] = b; ptr[p + 3] = 255
            }
        }

        let normal = normalFromHeight(heightField, width: w, height: h, strength: 0.22, invertY: false)
        return (diffuse, roughness, normal)
    }
}
