// Draws the app icon into an .iconset folder.  Usage: swift make-icon.swift <out.iconset>
import AppKit

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
    func rgb(_ v: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1) }

    // Aluminium case
    let body = NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 186 * s, yRadius: 186 * s)
    NSGradient(colors: [rgb(0xEDEEF1), rgb(0xC9CBD2)])!.draw(in: body, angle: -90)
    rgb(0xB4B7BF).setStroke(); body.lineWidth = 3 * s; body.stroke()

    // Plate
    let plate = NSBezierPath(roundedRect: rect(176, 176, 672, 672), xRadius: 96 * s, yRadius: 96 * s)
    rgb(0x23252A).setFill(); plate.fill()

    // Keycaps: a 2 x 2 cluster with the knob in the top-right position
    func cap(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, top: UInt32 = 0xFCFCFD, side: UInt32 = 0xCFD1D8) {
        let outer = NSBezierPath(roundedRect: rect(x, y, w, 276), xRadius: 44 * s, yRadius: 44 * s)
        rgb(side).setFill(); outer.fill()
        let face = NSBezierPath(roundedRect: rect(x + 20, y + 34, w - 40, 226), xRadius: 34 * s, yRadius: 34 * s)
        rgb(top).setFill(); face.fill()
    }
    cap(222, 526, 276)                       // top-left
    cap(222, 222, 580, top: 0xE9EAEE, side: 0xBFC2CA)   // bottom, wide

    // Knob
    let knobOuter = NSBezierPath(ovalIn: rect(526, 526, 276, 276))
    rgb(0xA9ADB6).setFill(); knobOuter.fill()
    let knobRing = NSBezierPath(ovalIn: rect(546, 546, 236, 236))
    NSGradient(colors: [rgb(0xF4F5F7), rgb(0xCDD0D7)])!.draw(in: knobRing, angle: -60)
    let knobTop = NSBezierPath(ovalIn: rect(584, 584, 160, 160))
    rgb(0xFCFCFD).setFill(); knobTop.fill()
    let mark = NSBezierPath(roundedRect: rect(656, 700, 16, 44), xRadius: 8 * s, yRadius: 8 * s)
    rgb(0x0A84FF).setFill(); mark.fill()

    // Legend on the top-left cap
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let text = NSAttributedString(string: "68", attributes: [
        .font: NSFont.systemFont(ofSize: 132 * s, weight: .semibold),
        .foregroundColor: rgb(0x26272B),
        .paragraphStyle: style,
    ])
    text.draw(in: rect(242, 594, 236, 160))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
