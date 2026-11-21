import AppKit
import SwiftUI

/// Renders the original E68 Studio logo mark (matching `Scripts/make-icon.swift`):
/// machined aluminium squircle case, dark plate, "68" keycap, rotary knob with blue indicator, and wide bottom keycap.
enum E68Logo {
    private static let cacheLock = NSLock()
    private static var cache: [Int: NSImage] = [:]

    static let statusBarImage: NSImage = image(pointSize: 18)

    static func image(pointSize: CGFloat) -> NSImage {
        let key = Int((pointSize * 10).rounded())
        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let img = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in [1, 2] {
            let px = max(1, Int((pointSize * CGFloat(scale)).rounded()))
            if let rep = renderRep(pixelsWide: px, pixelsHigh: px, pointSize: pointSize) {
                img.addRepresentation(rep)
            }
        }
        img.isTemplate = false
        cacheLock.lock()
        cache[key] = img
        cacheLock.unlock()
        return img
    }

    private static func renderRep(pixelsWide: Int, pixelsHigh: Int, pointSize: CGFloat) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelsWide * 4,
            bitsPerPixel: 32
        ) else { return nil }
        rep.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            // Normalize onto the 1024x1024 coordinate space used by `Scripts/make-icon.swift`.
            let s = CGFloat(pixelsWide) / 1024.0
            ctx.scaleBy(x: s, y: s)
            drawArtwork(in: ctx, showLabel: pixelsWide >= 24)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func drawArtwork(in ctx: CGContext, showLabel: Bool) {
        let rect: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect = { x, y, w, h in
            CGRect(x: x, y: y, width: w, height: h)
        }

        // 1. Aluminium case outer squircle
        let casePath = NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 186, yRadius: 186)
        let caseGrad = NSGradient(colors: [hex(0xEDEEF1), hex(0xC9CBD2)])!
        caseGrad.draw(in: casePath, angle: -90)
        hex(0xB4B7BF).setStroke()
        casePath.lineWidth = 10
        casePath.stroke()

        // 2. Dark recessed plate
        let platePath = NSBezierPath(roundedRect: rect(176, 176, 672, 672), xRadius: 96, yRadius: 96)
        hex(0x23252A).setFill()
        platePath.fill()

        // 3. Top-left sculpted "68" keycap
        hex(0xCFD1D8).setFill()
        NSBezierPath(roundedRect: rect(222, 526, 276, 276), xRadius: 56, yRadius: 56).fill()
        hex(0xFCFCFD).setFill()
        NSBezierPath(roundedRect: rect(244, 558, 232, 232), xRadius: 40, yRadius: 40).fill()

        if showLabel {
            let desc = NSFont.systemFont(ofSize: 132, weight: .bold).fontDescriptor.withDesign(.rounded)!
            let font = NSFont(descriptor: desc, size: 132) ?? NSFont.boldSystemFont(ofSize: 132)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: hex(0x26272B)
            ]
            let label = "68" as NSString
            let textSize = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(x: 360 - textSize.width / 2, y: 674 - textSize.height / 2 - 4),
                withAttributes: attrs
            )
        }

        // 4. Wide bottom keycap
        hex(0xBFC2CA).setFill()
        NSBezierPath(roundedRect: rect(222, 222, 580, 276), xRadius: 56, yRadius: 56).fill()
        hex(0xE9EAEE).setFill()
        NSBezierPath(roundedRect: rect(244, 254, 536, 232), xRadius: 40, yRadius: 40).fill()

        // 5. Top-right rotary encoder knob with signature blue indicator mark
        hex(0xA9ADB6).setFill()
        NSBezierPath(ovalIn: rect(526, 526, 276, 276)).fill()
        let ringGrad = NSGradient(colors: [hex(0xF4F5F7), hex(0xCDD0D7)])!
        ringGrad.draw(in: NSBezierPath(ovalIn: rect(546, 546, 236, 236)), angle: -90)
        hex(0xFCFCFD).setFill()
        NSBezierPath(ovalIn: rect(584, 584, 160, 160)).fill()
        hex(0x0A84FF).setFill()
        NSBezierPath(roundedRect: rect(656, 700, 16, 44), xRadius: 8, yRadius: 8).fill()

        // Clean up unused variable warning when CGContext is only queried implicitly
        _ = ctx
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Crisp SwiftUI view wrapping the original E68 Studio logo mark for popovers and badges.
struct E68LogoBadge: View {
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: E68Logo.image(pointSize: size))
            .interpolation(.high)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
