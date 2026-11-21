import AppKit
import CoreGraphics
import ImageIO
import simd

extension DeskTextures {
    // MARK: - ASUS VZ229E Display, Chin & OnePlus 6 Lock Screen

    /// Crisp dark-mode macOS + Arc/Chrome workspace screen for the matte IPS monitor:
    /// named studio tabs (no placeholder grey bars), dark-slate E68 Pro cards (no blooming white boxes),
    /// and zero keychain modal popup.
    static func asusScreen() -> CGImage { cachedAsusScreen }
    static func makeAsusScreen() -> CGImage {
        let w = 2560, h = 1440
        let logicalW: CGFloat = 1600, logicalH: CGFloat = 900
        return makeImage(w, h) { ctx, pxW, pxH in
            let W = logicalW, H = logicalH
            ctx.saveGState()
            ctx.translateBy(x: 0, y: pxH)
            ctx.scaleBy(x: pxW / logicalW, y: -(pxH / logicalH))

            // Deep neutral dark-slate window canvas
            let canvasGrad = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [
                    NSColor(srgbRed: 0.098, green: 0.106, blue: 0.122, alpha: 1).cgColor,
                    NSColor(srgbRed: 0.078, green: 0.084, blue: 0.098, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )!
            ctx.drawLinearGradient(canvasGrad, start: .zero, end: CGPoint(x: W, y: H), options: [])

            // Top macOS menu bar
            ctx.setFillColor(NSColor(srgbRed: 0.12, green: 0.045, blue: 0.065, alpha: 0.94).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: 28))

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let menuAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor(white: 0.84, alpha: 0.92),
            ]
            "Arc   File   Edit   View   History   Bookmarks   Spaces   Window   Help".draw(at: NSPoint(x: 34, y: 6), withAttributes: menuAttrs)
            "Thu Nov 12   9:18 PM".draw(at: NSPoint(x: W - 160, y: 6), withAttributes: menuAttrs)
            NSGraphicsContext.restoreGraphicsState()

            // Dark emerald-teal Arc left sidebar (matching the desk's left-pane aesthetic without blank bars)
            let sideGrad = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [
                    NSColor(srgbRed: 0.085, green: 0.285, blue: 0.165, alpha: 1).cgColor,
                    NSColor(srgbRed: 0.055, green: 0.205, blue: 0.120, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )!
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 28, width: 224, height: H - 28))
            ctx.drawLinearGradient(sideGrad, start: CGPoint(x: 0, y: 28), end: CGPoint(x: 0, y: H), options: [])
            ctx.restoreGState()

            for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                ctx.setFillColor(c.withAlphaComponent(0.85).cgColor)
                ctx.fillEllipse(in: CGRect(x: 18 + CGFloat(i) * 18, y: 44, width: 11, height: 11))
            }

            // Address bar inside sidebar
            ctx.setFillColor(NSColor(white: 0.0, alpha: 0.24).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 14, y: 70, width: 196, height: 30), cornerWidth: 8, cornerHeight: 8, transform: nil))
            ctx.fillPath()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            "e68-studio.local".draw(at: NSPoint(x: 26, y: 77), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                .foregroundColor: NSColor(white: 0.80, alpha: 0.88),
            ])
            NSGraphicsContext.restoreGraphicsState()

            // Pinned quick icons
            let pinnedColors: [NSColor] = [.systemBlue, .systemTeal, .systemIndigo, .systemOrange]
            for idx in 0..<4 {
                let rx = CGFloat(14 + idx * 50)
                ctx.setFillColor(NSColor(white: 1, alpha: 0.12).cgColor)
                ctx.addPath(CGPath(roundedRect: CGRect(x: rx, y: 112, width: 44, height: 34), cornerWidth: 8, cornerHeight: 8, transform: nil))
                ctx.fillPath()
                ctx.setFillColor(pinnedColors[idx].withAlphaComponent(0.82).cgColor)
                ctx.fillEllipse(in: CGRect(x: rx + 14, y: 121, width: 16, height: 16))
            }

            // Named workspace tabs (crisp text, no skeleton bars)
            let tabs: [(title: String, dot: NSColor, active: Bool)] = [
                ("Furycube E68 Pro", .systemBlue, true),
                ("VIA Keymap · Layer 0", .systemTeal, false),
                ("MCHOSE G7 Setup", .systemGray, false),
                ("Screen & Audio Sync", .systemPurple, false),
                ("Zero:2 EQ Profile", .systemCyan, false),
                ("Desk Ambience Notes", .systemPink, false),
                ("Macro Library", .systemOrange, false),
                ("Switch & Gasket Spec", .systemGreen, false),
                ("Firmware 1.02 Notes", .systemYellow, false),
            ]
            for (row, tab) in tabs.enumerated() {
                let y = CGFloat(168 + row * 46)
                if tab.active {
                    ctx.setFillColor(NSColor(white: 1, alpha: 0.16).cgColor)
                    ctx.addPath(CGPath(roundedRect: CGRect(x: 12, y: y - 4, width: 200, height: 36), cornerWidth: 9, cornerHeight: 9, transform: nil))
                    ctx.fillPath()
                }
                ctx.setFillColor(tab.dot.withAlphaComponent(0.84).cgColor)
                ctx.fillEllipse(in: CGRect(x: 22, y: y + 6, width: 16, height: 16))

                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                tab.title.draw(at: NSPoint(x: 46, y: y + 6), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12.5, weight: tab.active ? .semibold : .regular),
                    .foregroundColor: NSColor(white: tab.active ? 0.90 : 0.78, alpha: tab.active ? 1.0 : 0.85),
                ])
                NSGraphicsContext.restoreGraphicsState()
            }

            // Top workspace header & search bar
            ctx.setFillColor(NSColor(srgbRed: 0.135, green: 0.145, blue: 0.165, alpha: 1).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 264, y: 54, width: 1280, height: 60), cornerWidth: 14, cornerHeight: 14, transform: nil))
            ctx.fillPath()

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            "Furycube E68 Pro — Desk Studio Workspace".draw(at: NSPoint(x: 288, y: 71), withAttributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: NSColor(white: 0.86, alpha: 1),
            ])
            "USB Connected · 320F:5055 · fw 1.02 · South-Facing RGB".draw(at: NSPoint(x: 1090, y: 76), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .medium),
                .foregroundColor: NSColor(srgbRed: 0.45, green: 0.78, blue: 0.62, alpha: 1),
            ])
            NSGraphicsContext.restoreGraphicsState()

            // Miniature Furycube E68 product vector helper (dark backdrop only, zero bloom)
            func drawKeyboardPreview(in card: CGRect, glowColor: NSColor, angled: Bool) {
                let cardPath = CGPath(roundedRect: card, cornerWidth: 12, cornerHeight: 12, transform: nil)
                ctx.saveGState()
                ctx.addPath(cardPath)
                ctx.clip()

                let bgGrad = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [
                        NSColor(srgbRed: 0.085, green: 0.098, blue: 0.125, alpha: 1).cgColor,
                        NSColor(srgbRed: 0.055, green: 0.062, blue: 0.082, alpha: 1).cgColor,
                    ] as CFArray,
                    locations: [0, 1]
                )!
                ctx.drawLinearGradient(bgGrad, start: card.origin, end: CGPoint(x: card.maxX, y: card.maxY), options: [])

                ctx.translateBy(x: card.midX, y: card.midY)
                if angled {
                    ctx.concatenate(CGAffineTransform(a: 0.96, b: -0.10, c: 0.20, d: 0.82, tx: 0, ty: 0))
                }

                let kb = CGRect(x: -115, y: -44, width: 230, height: 88)
                ctx.setFillColor(NSColor(white: 0, alpha: 0.50).cgColor)
                ctx.addPath(CGPath(roundedRect: kb.offsetBy(dx: 0, dy: 7), cornerWidth: 8, cornerHeight: 8, transform: nil))
                ctx.fillPath()

                ctx.setFillColor(NSColor(srgbRed: 0.76, green: 0.77, blue: 0.78, alpha: 1).cgColor)
                ctx.addPath(CGPath(roundedRect: kb, cornerWidth: 7, cornerHeight: 7, transform: nil))
                ctx.fillPath()

                let inner = kb.insetBy(dx: 7, dy: 7)
                ctx.setFillColor(NSColor(srgbRed: 0.05, green: 0.08, blue: 0.14, alpha: 1).cgColor)
                ctx.fill(inner)
                ctx.setFillColor(glowColor.withAlphaComponent(0.70).cgColor)
                ctx.fill(inner.insetBy(dx: 1, dy: 1))

                let cols = 15, rows = 5
                let cellW = inner.width / CGFloat(cols)
                let cellH = inner.height / CGFloat(rows)
                for r in 0..<rows {
                    for c in 0..<cols {
                        if r == 0 && c == cols - 1 {
                            let kr = min(cellW, cellH) * 0.42
                            let kcx = inner.minX + (CGFloat(c) + 0.5) * cellW
                            let kcy = inner.minY + (CGFloat(r) + 0.5) * cellH
                            ctx.setFillColor(NSColor(srgbRed: 0.72, green: 0.74, blue: 0.78, alpha: 1).cgColor)
                            ctx.fillEllipse(in: CGRect(x: kcx - kr, y: kcy - kr, width: kr * 2, height: kr * 2))
                            continue
                        }
                        let isDark = (r == 0 && (c == 0 || c == 12 || c == 13))
                            || (r == 2 && (c >= 12 && c <= 13))
                            || (r == 4 && (c >= 3 && c <= 8))
                            || (r == 3 && c == 13) || (r == 4 && c >= 12)
                        let keyRect = CGRect(
                            x: inner.minX + CGFloat(c) * cellW + 1.0,
                            y: inner.minY + CGFloat(r) * cellH + 1.0,
                            width: cellW - 2.0,
                            height: cellH - 2.0
                        )
                        ctx.setFillColor((isDark
                            ? NSColor(srgbRed: 0.10, green: 0.12, blue: 0.16, alpha: 1)
                            : NSColor(srgbRed: 0.78, green: 0.79, blue: 0.80, alpha: 1)).cgColor)
                        ctx.addPath(CGPath(roundedRect: keyRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                        ctx.fillPath()
                    }
                }
                ctx.restoreGState()

                ctx.setStrokeColor(NSColor(white: 1, alpha: 0.08).cgColor)
                ctx.setLineWidth(1.0)
                ctx.addPath(cardPath)
                ctx.strokePath()
            }

            // Left column: Keyboard studio card + lighting spectrum strip
            ctx.setFillColor(NSColor(srgbRed: 0.125, green: 0.135, blue: 0.155, alpha: 1).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 264, y: 136, width: 760, height: 340), cornerWidth: 14, cornerHeight: 14, transform: nil))
            ctx.fillPath()
            drawKeyboardPreview(in: CGRect(x: 288, y: 160, width: 420, height: 220),
                                glowColor: NSColor(srgbRed: 0.22, green: 0.58, blue: 0.96, alpha: 1),
                                angled: true)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            "Active Layout — Layer 0 (macOS Base)".draw(at: NSPoint(x: 732, y: 170), withAttributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor(white: 0.85, alpha: 1),
            ])
            let specs = [
                "• 65% CNC 6063 Anodized Aluminum",
                "• Flex-Cut PC Plate · Silicone Gasket",
                "• 67 Keys + Stepped Rotary Encoder",
                "• 1000 Hz Polling · Low Latency",
                "• Tri-Mode USB-C / 2.4 GHz / BT 5.0",
            ]
            for (idx, line) in specs.enumerated() {
                line.draw(at: NSPoint(x: 732, y: CGFloat(208 + idx * 30)), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
                    .foregroundColor: NSColor(white: 0.68, alpha: 1),
                ])
            }
            "South-Facing Per-Key LEDs · 22 Effects · Screen & Audio Sync Enabled".draw(at: NSPoint(x: 288, y: 416), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(srgbRed: 0.56, green: 0.74, blue: 0.94, alpha: 1),
            ])
            NSGraphicsContext.restoreGraphicsState()

            // Right column: Device & Environment telemetry card
            ctx.setFillColor(NSColor(srgbRed: 0.125, green: 0.135, blue: 0.155, alpha: 1).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 1046, y: 136, width: 498, height: 340), cornerWidth: 14, cornerHeight: 14, transform: nil))
            ctx.fillPath()
            drawKeyboardPreview(in: CGRect(x: 1070, y: 160, width: 450, height: 180),
                                glowColor: NSColor(srgbRed: 0.94, green: 0.36, blue: 0.58, alpha: 1),
                                angled: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            "MCHOSE G7 · Wireless Optical".draw(at: NSPoint(x: 1070, y: 362), withAttributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor(white: 0.84, alpha: 1),
            ])
            "Stage 2 · 1600 DPI · PAW3395 · fw 6.1.2 · Motion Sync".draw(at: NSPoint(x: 1070, y: 392), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(white: 0.65, alpha: 1),
            ])
            "7Hz × Crinacle Zero:2 · 3.5mm Direct Monitor".draw(at: NSPoint(x: 1070, y: 426), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(srgbRed: 0.56, green: 0.74, blue: 0.94, alpha: 1),
            ])
            NSGraphicsContext.restoreGraphicsState()

            // Bottom cards: clean documentation & lighting spectrum previews
            let cards: [(title: String, subtitle: String, url: String, accent: NSColor)] = [
                ("QMK / VIA Keymap Inspector", "Live bidirectional EEPROM keycode sync over raw HID (usagePage 0xFF60)", "via.furycube.local/layers", .systemBlue),
                ("Desk Ambience & Sunset Gobo", "Dual-lamp warm coral + optical rainbow projection calibrated for evening focus", "studio/ambience/evening", .systemPink),
                ("Audio-Reactive FFT Beat Engine", "150 Hz low-latency kick transient detector synced across keyboard & IEMs", "studio/audio/equalizer", .systemTeal),
            ]
            for (idx, card) in cards.enumerated() {
                let x = CGFloat(264 + idx * 434)
                let rect = CGRect(x: x, y: 498, width: 412, height: 290)
                ctx.setFillColor(NSColor(srgbRed: 0.120, green: 0.128, blue: 0.148, alpha: 1).cgColor)
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil))
                ctx.fillPath()

                ctx.setFillColor(card.accent.withAlphaComponent(0.75).cgColor)
                ctx.addPath(CGPath(roundedRect: CGRect(x: x + 22, y: 522, width: 36, height: 5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
                ctx.fillPath()

                // Mini spectrum bars / waveform graph inside bottom card
                for bar in 0..<18 {
                    let bx = x + 24 + CGFloat(bar) * 20
                    let norm = 0.25 + 0.65 * abs(sin(CGFloat(bar + idx * 3) * 0.62))
                    let bh = 95 * norm
                    ctx.setFillColor(card.accent.withAlphaComponent(0.28 + 0.42 * norm).cgColor)
                    ctx.addPath(CGPath(roundedRect: CGRect(x: bx, y: 745 - bh, width: 12, height: bh), cornerWidth: 4, cornerHeight: 4, transform: nil))
                    ctx.fillPath()
                }

                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                card.url.draw(at: NSPoint(x: x + 22, y: 540), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor(white: 0.56, alpha: 1),
                ])
                card.title.draw(at: NSPoint(x: x + 22, y: 566), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 16.5, weight: .semibold),
                    .foregroundColor: NSColor(white: 0.85, alpha: 1),
                ])
                card.subtitle.draw(in: CGRect(x: x + 22, y: 598, width: 368, height: 48), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: NSColor(white: 0.68, alpha: 1),
                ])
                NSGraphicsContext.restoreGraphicsState()
            }

            // Subtle macOS Dock at bottom center
            let dockRect = CGRect(x: 690, y: 822, width: 420, height: 56)
            ctx.setFillColor(NSColor(white: 0.22, alpha: 0.48).cgColor)
            ctx.addPath(CGPath(roundedRect: dockRect, cornerWidth: 16, cornerHeight: 16, transform: nil))
            ctx.fillPath()
            let dockApps: [NSColor] = [.systemBlue, .systemTeal, .systemGreen, .systemIndigo, .systemOrange, .systemPink, .systemGray, .systemYellow]
            for (i, c) in dockApps.enumerated() {
                let ix = dockRect.minX + 16 + CGFloat(i) * 49
                ctx.setFillColor(c.withAlphaComponent(0.76).cgColor)
                ctx.addPath(CGPath(roundedRect: CGRect(x: ix, y: dockRect.minY + 10, width: 36, height: 36), cornerWidth: 9, cornerHeight: 9, transform: nil))
                ctx.fillPath()
            }

            ctx.restoreGState()
        }
    }

    /// ASUS monitor chin plate texture with fine brushed dark gunmetal striations, silver ASUS emblem, and right OSD icons.
    static func asusChin() -> CGImage { cachedAsusChin }
    static func makeAsusChin() -> CGImage {
        // Drawn at four times its old size: the logo is small on screen and was visibly pixelated up close.
        let w = 4096, h = 256
        return makeImage(w, h) { ctx, fullW, fullH in
            ctx.scaleBy(x: 4, y: 4)
            let W = fullW / 4, H = fullH / 4
            ctx.setFillColor(NSColor(srgbRed: 0.078, green: 0.081, blue: 0.090, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

            for y in 0..<Int(H) {
                let s = hash2D(0, y, 0xA505)
                let lum = 0.058 + CGFloat(s) * 0.048 + ((y & 1) == 0 ? 0.012 : 0.0)
                ctx.setFillColor(NSColor(white: lum, alpha: 0.85).cgColor)
                ctx.fill(CGRect(x: 0, y: CGFloat(y), width: W, height: 1))
            }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "AvenirNext-HeavyItalic", size: 22) ?? NSFont.boldSystemFont(ofSize: 22),
                .foregroundColor: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1),
                .kern: 3.2,
            ]
            let txt = NSAttributedString(string: "ASUS", attributes: attrs)
            txt.draw(at: NSPoint(x: (W - txt.size().width) / 2, y: (H - txt.size().height) / 2))
            NSGraphicsContext.restoreGraphicsState()

            // Six subtle silver-grey OSD indicator icons along the right chin (5 tiny squares + power icon).
            let iconY: CGFloat = 17.0
            let iconColor = NSColor(white: 0.74, alpha: 0.92).cgColor
            ctx.setFillColor(iconColor)
            ctx.setStrokeColor(iconColor)
            ctx.setLineWidth(1.5)
            for idx in 0..<5 {
                let ix = W * 0.715 + CGFloat(idx) * 34.0
                let dotRect = CGRect(x: ix - 2.6, y: iconY - 2.6, width: 5.2, height: 5.2)
                ctx.addPath(CGPath(roundedRect: dotRect, cornerWidth: 1.0, cornerHeight: 1.0, transform: nil))
                ctx.fillPath()
            }
            let pwrX = W * 0.715 + 5.0 * 34.0
            let pwrPath = CGMutablePath()
            pwrPath.addArc(center: CGPoint(x: pwrX, y: iconY), radius: 5.2, startAngle: .pi * 0.72, endAngle: .pi * 0.28, clockwise: true)
            ctx.addPath(pwrPath)
            ctx.strokePath()
            ctx.move(to: CGPoint(x: pwrX, y: iconY + 1.0))
            ctx.addLine(to: CGPoint(x: pwrX, y: iconY + 6.4))
            ctx.strokePath()
        }
    }

    // MARK: - iPad (11th Gen) Liquid Retina Screen

    /// Procedural original E68 Studio "Now Playing" landscape screen texture for the 11-inch iPad.
    static func iPadScreen() -> CGImage { cachedIPadScreen }
    static func makeIPadScreen() -> CGImage {
        let w = 1536, h = 1066
        let logicalW: CGFloat = 1024, logicalH: CGFloat = 711
        return makeImage(w, h) { ctx, pxW, pxH in
            let W = logicalW, H = logicalH
            ctx.saveGState()
            ctx.translateBy(x: 0, y: pxH)
            ctx.scaleBy(x: pxW / logicalW, y: -(pxH / logicalH))

            // Frosted warm charcoal-slate Now Playing backdrop (balanced luminance so it never blooms on the desk)
            let bgGrad = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [
                    NSColor(srgbRed: 0.255, green: 0.250, blue: 0.258, alpha: 1).cgColor,
                    NSColor(srgbRed: 0.195, green: 0.192, blue: 0.200, alpha: 1).cgColor,
                    NSColor(srgbRed: 0.155, green: 0.152, blue: 0.160, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0.0, 0.55, 1.0]
            )!
            ctx.drawLinearGradient(bgGrad, start: .zero, end: CGPoint(x: W, y: H), options: [])

            // Top iPadOS status bar (subtle clock/date on left, Wi-Fi + battery pill on right)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let statusAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: NSColor(white: 0.90, alpha: 0.92),
            ]
            "9:18 PM  Thu Nov 12".draw(at: NSPoint(x: 22, y: 12), withAttributes: statusAttrs)
            "74".draw(at: NSPoint(x: W - 50, y: 12), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
                .foregroundColor: NSColor(white: 0.92, alpha: 0.95),
            ])
            NSGraphicsContext.restoreGraphicsState()

            // Minimal Wi-Fi arcs + battery glyph on top-right
            ctx.setStrokeColor(NSColor(white: 0.90, alpha: 0.88).cgColor)
            ctx.setLineWidth(1.6)
            for (i, r) in [CGFloat(4), 7.5, 11].enumerated() {
                let p = CGMutablePath()
                p.addArc(center: CGPoint(x: W - 72, y: 24), radius: r, startAngle: -.pi * 0.78, endAngle: -.pi * 0.22, clockwise: false)
                ctx.addPath(p)
                ctx.setLineWidth(i == 0 ? 2.0 : 1.5)
                ctx.strokePath()
            }
            let batRect = CGRect(x: W - 54, y: 11, width: 26, height: 14)
            ctx.setStrokeColor(NSColor(white: 0.84, alpha: 0.70).cgColor)
            ctx.setLineWidth(1.3)
            ctx.addPath(CGPath(roundedRect: batRect, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
            ctx.strokePath()
            ctx.setFillColor(NSColor(white: 0.90, alpha: 0.82).cgColor)
            ctx.fill(CGRect(x: batRect.maxX + 1.5, y: batRect.midY - 2.5, width: 2, height: 5))

            // Left: Album artwork card with soft drop shadow & original Twilight Ridge + Vinyl Rings design
            let artRect = CGRect(x: 78, y: 170, width: 374, height: 374)
            let artRadius: CGFloat = 14
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: NSColor(white: 0, alpha: 0.42).cgColor)
            ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).cgColor)
            ctx.addPath(CGPath(roundedRect: artRect, cornerWidth: artRadius, cornerHeight: artRadius, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: artRect, cornerWidth: artRadius, cornerHeight: artRadius, transform: nil))
            ctx.clip()

            let skyGrad = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [
                    NSColor(srgbRed: 0.84, green: 0.83, blue: 0.80, alpha: 1).cgColor,
                    NSColor(srgbRed: 0.54, green: 0.56, blue: 0.59, alpha: 1).cgColor,
                    NSColor(srgbRed: 0.14, green: 0.16, blue: 0.20, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0.0, 0.56, 1.0]
            )!
            ctx.drawLinearGradient(skyGrad, start: CGPoint(x: artRect.midX, y: artRect.minY),
                                   end: CGPoint(x: artRect.midX, y: artRect.maxY), options: [])

            // Soft horizon sun disc + concentric acoustic grooves
            ctx.setFillColor(NSColor(srgbRed: 0.96, green: 0.89, blue: 0.74, alpha: 0.78).cgColor)
            ctx.fillEllipse(in: CGRect(x: artRect.midX - 58, y: artRect.minY + 128, width: 116, height: 116))
            for rIdx in 0..<7 {
                let rad = CGFloat(68 + rIdx * 18)
                ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.14 - CGFloat(rIdx) * 0.015).cgColor)
                ctx.setLineWidth(1.2)
                ctx.strokeEllipse(in: CGRect(x: artRect.midX - rad, y: artRect.minY + 186 - rad, width: rad * 2, height: rad * 2))
            }

            // Layered dusk mountain ridge silhouette across lower third of artwork
            let ridge1 = CGMutablePath()
            ridge1.move(to: CGPoint(x: artRect.minX, y: artRect.maxY))
            ridge1.addLine(to: CGPoint(x: artRect.minX, y: artRect.minY + 242))
            ridge1.addCurve(to: CGPoint(x: artRect.minX + 180, y: artRect.minY + 216),
                            control1: CGPoint(x: artRect.minX + 64, y: artRect.minY + 218),
                            control2: CGPoint(x: artRect.minX + 122, y: artRect.minY + 240))
            ridge1.addCurve(to: CGPoint(x: artRect.maxX, y: artRect.minY + 234),
                            control1: CGPoint(x: artRect.minX + 248, y: artRect.minY + 190),
                            control2: CGPoint(x: artRect.minX + 314, y: artRect.minY + 244))
            ridge1.addLine(to: CGPoint(x: artRect.maxX, y: artRect.maxY))
            ridge1.closeSubpath()
            ctx.setFillColor(NSColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 0.92).cgColor)
            ctx.addPath(ridge1)
            ctx.fillPath()

            let ridge2 = CGMutablePath()
            ridge2.move(to: CGPoint(x: artRect.minX, y: artRect.maxY))
            ridge2.addLine(to: CGPoint(x: artRect.minX, y: artRect.minY + 286))
            ridge2.addCurve(to: CGPoint(x: artRect.maxX, y: artRect.minY + 276),
                            control1: CGPoint(x: artRect.minX + 128, y: artRect.minY + 260),
                            control2: CGPoint(x: artRect.minX + 260, y: artRect.minY + 306))
            ridge2.addLine(to: CGPoint(x: artRect.maxX, y: artRect.maxY))
            ridge2.closeSubpath()
            ctx.setFillColor(NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1.0).cgColor)
            ctx.addPath(ridge2)
            ctx.fillPath()

            // Minimal original album typography inside upper sky of artwork
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let coverStyle = NSMutableParagraphStyle()
            coverStyle.alignment = .center
            "QUIET".draw(in: CGRect(x: artRect.minX + 20, y: artRect.minY + 38, width: artRect.width - 40, height: 40), withAttributes: [
                .font: NSFont.systemFont(ofSize: 28, weight: .light),
                .foregroundColor: NSColor(srgbRed: 0.72, green: 0.58, blue: 0.24, alpha: 0.92),
                .kern: 9.0,
                .paragraphStyle: coverStyle,
            ])
            "HOURS".draw(in: CGRect(x: artRect.minX + 20, y: artRect.minY + 72, width: artRect.width - 40, height: 42), withAttributes: [
                .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
                .foregroundColor: NSColor(srgbRed: 0.68, green: 0.54, blue: 0.20, alpha: 0.95),
                .kern: 10.0,
                .paragraphStyle: coverStyle,
            ])
            "E68 STUDIO  ·  SESSIONS".draw(in: CGRect(x: artRect.minX + 20, y: artRect.maxY - 36, width: artRect.width - 40, height: 20), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor(white: 0.78, alpha: 0.76),
                .kern: 3.2,
                .paragraphStyle: coverStyle,
            ])
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()

            // Right half: Track metadata, action icons, and synced lyric lines
            let textX: CGFloat = 532
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            "Afterglow on Walnut".draw(at: NSPoint(x: textX, y: 74), withAttributes: [
                .font: NSFont.systemFont(ofSize: 19, weight: .semibold),
                .foregroundColor: NSColor(white: 0.94, alpha: 1.0),
            ])
            "E68 Acoustic Collective".draw(at: NSPoint(x: textX, y: 100), withAttributes: [
                .font: NSFont.systemFont(ofSize: 17.5, weight: .regular),
                .foregroundColor: NSColor(white: 0.74, alpha: 0.92),
            ])

            let lyrics: [(text: String, alpha: CGFloat)] = [
                ("Late evening amber light", 0.96),
                ("Spills across the walnut desk", 0.50),
                ("Quiet keys keep steady time", 0.36),
                ("While the copper rain winds down", 0.28),
                ("Until the dawn horizon clears", 0.20),
            ]
            for (idx, line) in lyrics.enumerated() {
                let y = CGFloat(152 + idx * 82)
                line.text.draw(in: CGRect(x: textX, y: y, width: 410, height: 74), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 31, weight: .bold),
                    .foregroundColor: NSColor(white: 0.96, alpha: line.alpha),
                ])
            }
            NSGraphicsContext.restoreGraphicsState()

            // Top-right favorite star + more menu dots
            ctx.setStrokeColor(NSColor(white: 0.88, alpha: 0.84).cgColor)
            ctx.setLineWidth(1.6)
            let starCenter = CGPoint(x: W - 114, y: 92)
            let star = CGMutablePath()
            for k in 0..<10 {
                let a = -.pi / 2 + CGFloat(k) * .pi / 5
                let r: CGFloat = (k % 2 == 0) ? 11.5 : 4.8
                let pt = CGPoint(x: starCenter.x + cos(a) * r, y: starCenter.y + sin(a) * r)
                if k == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
            }
            star.closeSubpath()
            ctx.addPath(star)
            ctx.strokePath()

            ctx.setFillColor(NSColor(white: 0.88, alpha: 0.84).cgColor)
            for d in 0..<3 {
                ctx.fillEllipse(in: CGRect(x: W - 76 + CGFloat(d) * 9, y: 90, width: 4, height: 4))
            }

            // Bottom frosted player icons: lyrics pill, AirPlay arcs, queue lines
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.16).cgColor)
            ctx.fillEllipse(in: CGRect(x: 540 - 20, y: 634 - 20, width: 40, height: 40))
            ctx.setStrokeColor(NSColor(white: 0.94, alpha: 0.90).cgColor)
            ctx.setLineWidth(1.6)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 530, y: 625, width: 20, height: 15), cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.strokePath()

            for r in [CGFloat(5), 9, 13] {
                let p = CGMutablePath()
                p.addArc(center: CGPoint(x: 750, y: 636), radius: r, startAngle: -.pi * 1.15, endAngle: .pi * 0.15, clockwise: false)
                ctx.addPath(p)
                ctx.strokePath()
            }
            for lineIdx in 0..<3 {
                let ly = 626 + CGFloat(lineIdx) * 6
                ctx.move(to: CGPoint(x: 942, y: ly))
                ctx.addLine(to: CGPoint(x: 964, y: ly))
                ctx.strokePath()
            }

            ctx.restoreGState()
        }
    }
}
