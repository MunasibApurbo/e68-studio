import AppKit

enum LegendPainter {
    private struct CacheKey: Hashable {
        let legend: Legend
        let widthPx: Int
        let heightPx: Int
        let dark: Bool
        let bgKey: UInt32
    }

    private static let cacheLock = NSLock()
    private static var imageCache: [CacheKey: CGImage] = [:]
    private static let darkInk = NSColor(white: 0.92, alpha: 1)
    private static let lightInk = NSColor(white: 0.14, alpha: 1)

    private static func quantizeColor(_ c: NSColor) -> UInt32 {
        let rgb = c.usingColorSpace(.sRGB) ?? c
        let r = UInt32(min(max(Int((rgb.redComponent * 255).rounded()), 0), 255))
        let g = UInt32(min(max(Int((rgb.greenComponent * 255).rounded()), 0), 255))
        let b = UInt32(min(max(Int((rgb.blueComponent * 255).rounded()), 0), 255))
        let a = UInt32(min(max(Int((rgb.alphaComponent * 255).rounded()), 0), 255))
        return (r << 24) | (g << 16) | (b << 8) | a
    }

    /// Draws a cap's top face with its legend, in the style printed on the real caps:
    /// letters large and upper-left, words small in the top-left corner.
    static func texture(_ legend: Legend, width: Double, dark: Bool, background: NSColor) -> CGImage {
        let main = (legend.main == "None" || (width >= 4.0 && legend.main == "Space" && legend.top == nil)) ? "" : legend.main
        let isBlank = main.isEmpty && legend.top == nil && legend.symbol == nil
        let top = CapMesh.topSize(width: Float(width))
        let scale: CGFloat = 320
        let w = isBlank ? 16 : max(16, Int(CGFloat(top.x) * scale))
        let h = isBlank ? 16 : max(16, Int(CGFloat(top.y) * scale))
        let key = CacheKey(legend: legend, widthPx: w, heightPx: h, dark: dark, bgKey: quantizeColor(background))
        cacheLock.lock()
        if let cached = imageCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let cgCtx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        cgCtx.interpolationQuality = .high
        cgCtx.setAllowsAntialiasing(true)
        cgCtx.setShouldAntialias(true)
        cgCtx.setAllowsFontSmoothing(true)
        cgCtx.setShouldSmoothFonts(true)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        background.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        let ink = dark ? darkInk : lightInk
        let H = CGFloat(h), W = CGFloat(w)

        func font(_ size: CGFloat) -> NSFont {
            NSFont(name: "AvenirNext-DemiBold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
        }
        /// `y` is measured down from the top edge to the top of the text.
        func draw(_ text: String, size: CGFloat, x: CGFloat, y: CGFloat, color: NSColor = ink, centered: Bool = false) {
            var f = font(size)
            var attributed = NSAttributedString(string: text, attributes: [.font: f, .foregroundColor: color])
            let room = W - (centered ? W * 0.12 : x + W * 0.07)
            if attributed.size().width > room, room > 0 {
                f = font(size * room / attributed.size().width)
                attributed = NSAttributedString(string: text, attributes: [.font: f, .foregroundColor: color])
            }
            let drawX = centered ? (W - attributed.size().width) * 0.5 : x
            let drawY = centered ? (H - attributed.size().height) * 0.5 : (H - y - attributed.size().height)
            attributed.draw(at: NSPoint(x: drawX, y: drawY))
        }

        if isBlank {
            // Solid cap colour only (e.g. blank spacebar).
        } else if let symbol = legend.symbol,
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: H * 0.24, weight: .semibold).applying(.init(paletteColors: [ink]))) {
            let size = image.size
            image.draw(in: NSRect(x: (W - size.width) * 0.5, y: (H - size.height) * 0.5, width: size.width, height: size.height))
        } else if legend.top == nil, width <= 1.05, ["↑", "↓", "←", "→"].contains(main) {
            drawArrowKey(main, w: W, h: H, color: ink)
        } else if main.count <= 2, let top = legend.top, top.count <= 2 {
            draw(top, size: H * 0.23, x: W * 0.17, y: H * 0.09)
            draw(main, size: H * 0.23, x: W * 0.17, y: H * 0.50)
        } else if main.count == 1 {
            draw(main, size: H * 0.35, x: W * 0.16, y: H * 0.09)
        } else if width <= 1.05 && (main == "Delete" || main == "PgUp" || main == "PgDn" || main == "Del") {
            draw(main, size: H * 0.21, x: 0, y: 0, centered: true)
        } else if main == "Tab", legend.top != nil {
            drawTabArrow(x: H * 0.14, yTop: H * 0.13, w: H * 0.24, h: H * 0.11, totalH: H, pointLeft: true, color: ink)
            draw("Tab", size: H * 0.20, x: H * 0.13, y: H * 0.36)
            drawTabArrow(x: H * 0.14, yTop: H * 0.67, w: H * 0.24, h: H * 0.11, totalH: H, pointLeft: false, color: ink)
        } else if main == "↵Enter" {
            drawReturnArrow(x: H * 0.14, yTop: H * 0.42, w: H * 0.28, h: H * 0.14, totalH: H, color: ink)
            draw("Enter", size: H * 0.21, x: H * 0.45, y: H * 0.36)
        } else if main == "←Backspace" {
            drawBackspaceArrow(x: H * 0.14, yTop: H * 0.44, w: H * 0.20, h: H * 0.10, totalH: H, color: ink)
            draw("Backspace", size: H * 0.20, x: H * 0.38, y: H * 0.36)
        } else if main == "⇧Shift" {
            drawShiftArrow(x: H * 0.15, yTop: H * 0.37, size: H * 0.22, totalH: H, color: ink)
            draw("Shift", size: H * 0.20, x: H * 0.42, y: H * 0.36)
        } else if main == "Esc" {
            draw(main, size: H * 0.22, x: H * 0.14, y: H * 0.15)
        } else {
            if let top = legend.top { draw(top, size: H * 0.19, x: H * 0.14, y: H * 0.15) }
            draw(main, size: H * 0.22, x: H * 0.14, y: legend.top == nil ? H * 0.36 : H * 0.45)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = cgCtx.makeImage()!
        cacheLock.lock()
        imageCache[key] = image
        cacheLock.unlock()
        return image
    }

    private static func drawArrowKey(_ direction: String, w: CGFloat, h: CGFloat, color: NSColor) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let cx = w * 0.5, cy = h * 0.5
        let arm = min(w, h) * 0.17
        let head = arm * 0.62
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(max(2.0, min(w, h) * 0.045))
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        switch direction {
        case "↑":
            cg.move(to: CGPoint(x: cx, y: cy - arm))
            cg.addLine(to: CGPoint(x: cx, y: cy + arm))
            cg.move(to: CGPoint(x: cx - head, y: cy + arm - head))
            cg.addLine(to: CGPoint(x: cx, y: cy + arm))
            cg.addLine(to: CGPoint(x: cx + head, y: cy + arm - head))
        case "↓":
            cg.move(to: CGPoint(x: cx, y: cy + arm))
            cg.addLine(to: CGPoint(x: cx, y: cy - arm))
            cg.move(to: CGPoint(x: cx - head, y: cy - arm + head))
            cg.addLine(to: CGPoint(x: cx, y: cy - arm))
            cg.addLine(to: CGPoint(x: cx + head, y: cy - arm + head))
        case "←":
            cg.move(to: CGPoint(x: cx + arm, y: cy))
            cg.addLine(to: CGPoint(x: cx - arm, y: cy))
            cg.move(to: CGPoint(x: cx - arm + head, y: cy + head))
            cg.addLine(to: CGPoint(x: cx - arm, y: cy))
            cg.addLine(to: CGPoint(x: cx - arm + head, y: cy - head))
        default:
            cg.move(to: CGPoint(x: cx - arm, y: cy))
            cg.addLine(to: CGPoint(x: cx + arm, y: cy))
            cg.move(to: CGPoint(x: cx + arm - head, y: cy + head))
            cg.addLine(to: CGPoint(x: cx + arm, y: cy))
            cg.addLine(to: CGPoint(x: cx + arm - head, y: cy - head))
        }
        cg.strokePath()
    }

    private static func drawBackspaceArrow(x: CGFloat, yTop: CGFloat, w: CGFloat, h: CGFloat, totalH: CGFloat, color: NSColor) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let yc = totalH - (yTop + h * 0.5)
        let tip = h * 0.65
        let strokeW = max(1.8, h * 0.34)
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(strokeW)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.move(to: CGPoint(x: x + w, y: yc))
        cg.addLine(to: CGPoint(x: x, y: yc))
        cg.move(to: CGPoint(x: x + tip, y: yc + tip * 0.8))
        cg.addLine(to: CGPoint(x: x, y: yc))
        cg.addLine(to: CGPoint(x: x + tip, y: yc - tip * 0.8))
        cg.strokePath()
    }

    private static func drawShiftArrow(x: CGFloat, yTop: CGFloat, size: CGFloat, totalH: CGFloat, color: NSColor) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let yBot = totalH - (yTop + size)
        let cx = x + size * 0.5
        let stemW = size * 0.36
        let midY = yBot + size * 0.44
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(max(2.0, size * 0.14))
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.move(to: CGPoint(x: cx - stemW * 0.5, y: yBot))
        cg.addLine(to: CGPoint(x: cx + stemW * 0.5, y: yBot))
        cg.addLine(to: CGPoint(x: cx + stemW * 0.5, y: midY))
        cg.addLine(to: CGPoint(x: cx + size * 0.48, y: midY))
        cg.addLine(to: CGPoint(x: cx, y: yBot + size))
        cg.addLine(to: CGPoint(x: cx - size * 0.48, y: midY))
        cg.addLine(to: CGPoint(x: cx - stemW * 0.5, y: midY))
        cg.closePath()
        cg.strokePath()
    }

    private static func drawTabArrow(x: CGFloat, yTop: CGFloat, w: CGFloat, h: CGFloat, totalH: CGFloat, pointLeft: Bool, color: NSColor) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let yc = totalH - (yTop + h * 0.5)
        let x0 = x, x1 = x + w
        let tip = h * 0.48
        let strokeW = max(1.6, h * 0.15)
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(strokeW)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        // Vertical stop bar
        let barX = pointLeft ? x0 : x1
        cg.move(to: CGPoint(x: barX, y: yc - h * 0.45))
        cg.addLine(to: CGPoint(x: barX, y: yc + h * 0.45))
        // Horizontal shaft + arrowhead
        cg.move(to: CGPoint(x: x0 + (pointLeft ? strokeW : 0), y: yc))
        cg.addLine(to: CGPoint(x: x1 - (pointLeft ? 0 : strokeW), y: yc))
        if pointLeft {
            cg.move(to: CGPoint(x: x0 + tip, y: yc + tip * 0.72))
            cg.addLine(to: CGPoint(x: x0 + strokeW * 0.8, y: yc))
            cg.addLine(to: CGPoint(x: x0 + tip, y: yc - tip * 0.72))
        } else {
            cg.move(to: CGPoint(x: x1 - tip, y: yc + tip * 0.72))
            cg.addLine(to: CGPoint(x: x1 - strokeW * 0.8, y: yc))
            cg.addLine(to: CGPoint(x: x1 - tip, y: yc - tip * 0.72))
        }
        cg.strokePath()
    }

    private static func drawReturnArrow(x: CGFloat, yTop: CGFloat, w: CGFloat, h: CGFloat, totalH: CGFloat, color: NSColor) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let yBase = totalH - (yTop + h)
        let yMid = yBase + h * 0.35
        let strokeW = max(1.8, h * 0.13)
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(strokeW)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        // Bent tail starting high right -> down -> left -> arrowhead
        cg.move(to: CGPoint(x: x + w, y: yBase + h))
        cg.addLine(to: CGPoint(x: x + w, y: yMid))
        cg.addLine(to: CGPoint(x: x + strokeW * 0.5, y: yMid))
        let tip = h * 0.42
        cg.move(to: CGPoint(x: x + tip, y: yMid + tip * 0.75))
        cg.addLine(to: CGPoint(x: x + strokeW * 0.5, y: yMid))
        cg.addLine(to: CGPoint(x: x + tip, y: yMid - tip * 0.75))
        cg.strokePath()
    }

    /// What is physically printed on the user's caps (the Windows legends the board ships with).
    static func printed(_ code: UInt16) -> Legend {
        switch code {
        case 0xE3, 0xE7: return Legend(main: "Win")
        case 0xE2, 0xE6: return Legend(main: "Alt")
        case 0xE0, 0xE4: return Legend(main: "Ctrl")
        case 0xE1, 0xE5: return Legend(main: "⇧Shift")
        case 0x2A: return Legend(main: "←Backspace")
        case 0x28: return Legend(main: "↵Enter")
        case 0x2B: return Legend(main: "Tab", top: "⇤")
        case 0x29: return Legend(main: "Esc")
        case 0x4B: return Legend(main: "PgUp")
        case 0x4E: return Legend(main: "PgDn")
        case 0x4C: return Legend(main: "Delete")
        case 0x39: return Legend(main: "Caps Lock")
        case 0x2C: return Legend(main: "")
        case 0x5100...0x511F: return Legend(main: "Fn")
        default: return Keycodes.def(for: code).legend
        }
    }
}
