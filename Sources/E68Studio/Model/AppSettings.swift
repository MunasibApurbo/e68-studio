import AppKit
import ImageIO
import SwiftUI
import simd
import UniformTypeIdentifiers

// MARK: - Appearance & Glass Preferences

/// How glass surfaces render. `.automatic` follows macOS: regular Liquid Glass that adapts
/// to Light/Dark, and solid panels when Reduce Transparency is on.
enum GlassPreference: String, CaseIterable, Identifiable {
    case automatic, clear, frosted, solid
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .clear: return "Clear"
        case .frosted: return "Frosted"
        case .solid: return "Solid"
        }
    }

    var detail: String {
        switch self {
        case .automatic: return "Same Liquid Glass as macOS. Follows System Settings › Appearance."
        case .clear: return "Most transparent."
        case .frosted: return "More blur, easier to read."
        case .solid: return "No transparency."
        }
    }
}

/// App appearance; `.system` follows System Settings › Appearance.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum GlassKeys {
    static let style = "glassStyle"
    static let appearance = "appearance"
}

// MARK: - Menu Bar Preferences

enum MenuBarKeys {
    static let showInMenuBar = "showInMenuBar"
    static let keepRunningInMenuBar = "keepRunningInMenuBar"
}

// MARK: - Desk Ambience & Notification Preferences

enum DeskMood: String, CaseIterable, Identifiable {
    case daylight, midnight
    var id: String { rawValue }

    var title: String {
        switch self {
        case .daylight: return "Day"
        case .midnight: return "Night"
        }
    }

    var symbol: String {
        switch self {
        case .daylight: return "sun.max.fill"
        case .midnight: return "moon.stars.fill"
        }
    }

    var next: DeskMood {
        switch self {
        case .daylight: return .midnight
        case .midnight: return .daylight
        }
    }
}

enum DeskScenario: String, CaseIterable, Identifiable {
    case swissAlps
    case winter
    case nature
    case blossom
    case ocean
    case canyon
    case cyberpunk
    case room

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swissAlps: return "Swiss Alps"
        case .winter: return "Winter Park"
        case .nature: return "Meadow"
        case .blossom: return "Garden"
        case .ocean: return "Ocean Cove"
        case .canyon: return "Red Desert"
        case .cyberpunk: return "City Lights"
        case .room: return "Studio Room"
        }
    }

    var subtitle: String {
        switch self {
        case .swissAlps: return "Alpine valley"
        case .winter: return "Fresh snow"
        case .nature: return "Sunlit grass"
        case .blossom: return "Formal garden"
        case .ocean: return "Sandy beach"
        case .canyon: return "Arid plain"
        case .cyberpunk: return "Waterfront skyline"
        case .room: return "Minimal plaster"
        }
    }

    var symbol: String {
        switch self {
        case .swissAlps: return "mountain.2.fill"
        case .winter: return "snowflake"
        case .nature: return "tree.fill"
        case .blossom: return "camera.macro"
        case .ocean: return "water.waves"
        case .canyon: return "sun.horizon.fill"
        case .cyberpunk: return "building.2.fill"
        case .room: return "lamp.desk.fill"
        }
    }

    var next: DeskScenario {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }

    var previous: DeskScenario {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx - 1 + all.count) % all.count]
    }
}

enum AmbienceKeys {
    static let deskLampOn = "deskLampOn"
    static let deskMood = "deskMood"
    static let deskScenario = "deskScenario"
    /// Desk lamp light: brightness (0.3...2.5, 1 = normal) and colour (`DeskLampColor` raw value).
    static let deskLampBrightness = "deskLampBrightness"
    static let deskLampColor = "deskLampColor"
    static let notifyLowBattery = "notifyLowBattery"
}

/// Colours the desk lamp's bulb can be set to.
enum DeskLampColor: String, CaseIterable, Identifiable {
    case warm, neutral, cool, amber, rose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: return "Warm white"
        case .neutral: return "Neutral white"
        case .cool: return "Cool white"
        case .amber: return "Amber"
        case .rose: return "Rose"
        }
    }

    /// Linear RGB of the light, brightest channel at 1.
    var tint: SIMD3<Float> {
        switch self {
        case .warm: return SIMD3(1.0, 0.72, 0.44)
        case .neutral: return SIMD3(1.0, 0.92, 0.84)
        case .cool: return SIMD3(0.78, 0.89, 1.0)
        case .amber: return SIMD3(1.0, 0.52, 0.16)
        case .rose: return SIMD3(1.0, 0.24, 0.42)
        }
    }

    var swatch: Color {
        func encoded(_ v: Float) -> Double { Double(v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055) }
        return Color(red: encoded(tint.x), green: encoded(tint.y), blue: encoded(tint.z))
    }
}

enum DeskWallpaperKeys {
    static let token = "desk.monitorWallpaperToken"
    /// Position in the click-to-cycle list (0 is the built-in ASUS screen).
    static let cycleIndex = "desk.monitorWallpaperCycleIndex"
}

/// Manages custom user-uploaded wallpapers for the 3D desk monitor screen.
enum MonitorWallpaperStore {
    struct Entry {
        let image: CGImage
        let tint: NSColor
    }

    private static let lock = NSLock()
    private static var cached: Entry?
    private static var loadedFromDisk = false

    static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("E68 Studio", isDirectory: true)
            .appendingPathComponent("monitor-wallpaper.png")
    }

    static func currentImage() -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        if loadedFromDisk { return cached }
        loadedFromDisk = true
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            cached = nil
            return nil
        }
        let entry = Entry(image: cgImage, tint: averageTint(of: cgImage))
        cached = entry
        return entry
    }

    @MainActor
    static func pickWallpaper() {
        let panel = NSOpenPanel()
        panel.title = "Choose Monitor Wallpaper"
        panel.prompt = "Apply"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = setWallpaper(from: url)
        }
    }

    @discardableResult
    static func setWallpaper(from url: URL) -> Bool {
        guard let processed = renderScreenImage(from: url) else {
            return false
        }
        let rep = NSBitmapImageRep(cgImage: processed)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return false }
        let dest = fileURL
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try pngData.write(to: dest, options: .atomic)
        } catch {
            return false
        }
        let entry = Entry(image: processed, tint: averageTint(of: processed))
        lock.lock()
        cached = entry
        loadedFromDisk = true
        lock.unlock()
        let updateMain = {
            UserDefaults.standard.set(UUID().uuidString, forKey: DeskWallpaperKeys.token)
            NotificationCenter.default.post(name: Notification.Name("E68SceneNeedsRender"), object: nil)
        }
        if Thread.isMainThread {
            updateMain()
        } else {
            DispatchQueue.main.async(execute: updateMain)
        }
        return true
    }

    /// Full-resolution still wallpapers that ship with macOS, used when the monitor is clicked.
    static let systemWallpapers: [URL] = {
        let dir = URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }()

    private static var cycling = false

    /// Steps the monitor to the next wallpaper: built-in screen, then each macOS wallpaper in turn.
    /// Decoding runs off the main thread; `completion` runs on the main thread once it is applied.
    @MainActor
    static func cycleWallpaper(completion: @escaping @MainActor () -> Void) {
        guard !cycling else { return }
        let list = systemWallpapers
        let count = list.count + 1
        let next = (UserDefaults.standard.integer(forKey: DeskWallpaperKeys.cycleIndex) + 1) % count
        UserDefaults.standard.set(next, forKey: DeskWallpaperKeys.cycleIndex)
        if next == 0 || list.isEmpty {
            resetWallpaper()
            completion()
            return
        }
        cycling = true
        let url = list[next - 1]
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = setWallpaper(from: url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    cycling = false
                    if ok { completion() }
                }
            }
        }
    }

    static func resetWallpaper() {
        try? FileManager.default.removeItem(at: fileURL)
        lock.lock()
        cached = nil
        loadedFromDisk = true
        lock.unlock()
        UserDefaults.standard.set("", forKey: DeskWallpaperKeys.token)
        NotificationCenter.default.post(name: Notification.Name("E68SceneNeedsRender"), object: nil)
    }

    /// Aspect-fills any uploaded image into a sharp 16:9 sRGB texture matching the 21.5" monitor panel.
    private static func renderScreenImage(from url: URL) -> CGImage? {
        let srcImage: CGImage
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4600,
        ]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) {
            srcImage = cg
        } else if let nsImg = NSImage(contentsOf: url),
                  let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            srcImage = cg
        } else {
            return nil
        }
        let srcW = CGFloat(srcImage.width)
        let srcH = CGFloat(srcImage.height)
        guard srcW > 1, srcH > 1 else { return nil }

        let targetW = 2560
        let targetH = 1440
        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: targetW * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        let scale = max(CGFloat(targetW) / srcW, CGFloat(targetH) / srcH)
        let drawW = srcW * scale
        let drawH = srcH * scale
        let drawRect = CGRect(
            x: (CGFloat(targetW) - drawW) * 0.5,
            y: (CGFloat(targetH) - drawH) * 0.5,
            width: drawW,
            height: drawH
        )
        ctx.draw(srcImage, in: drawRect)
        return ctx.makeImage()
    }

    /// Samples an average ambient tint so the monitor spill light reflects the custom wallpaper.
    private static func averageTint(of image: CGImage) -> NSColor {
        let sw = 16, sh = 9
        var pixels = [UInt8](repeating: 0, count: sw * sh * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: sw,
            height: sh,
            bitsPerComponent: 8,
            bytesPerRow: sw * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSColor(srgbRed: 0.84, green: 0.90, blue: 0.98, alpha: 1)
        }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        var rSum = 0, gSum = 0, bSum = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            rSum += Int(pixels[i])
            gSum += Int(pixels[i + 1])
            bSum += Int(pixels[i + 2])
        }
        let count = CGFloat(sw * sh)
        // Lift dark wallpapers into a soft neutral-tinted light so the desk stays well-lit.
        let r = 0.45 + 0.55 * (CGFloat(rSum) / (count * 255.0))
        let g = 0.45 + 0.55 * (CGFloat(gSum) / (count * 255.0))
        let b = 0.45 + 0.55 * (CGFloat(bSum) / (count * 255.0))
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

enum MenuBarSettings {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            MenuBarKeys.showInMenuBar: true,
            MenuBarKeys.keepRunningInMenuBar: true,
            AmbienceKeys.deskLampOn: true,
            AmbienceKeys.deskLampBrightness: 1.0,
            AmbienceKeys.deskLampColor: DeskLampColor.warm.rawValue,
            AmbienceKeys.deskMood: DeskMood.daylight.rawValue,
            AmbienceKeys.deskScenario: DeskScenario.swissAlps.rawValue,
            AmbienceKeys.notifyLowBattery: true,
            DeskWallpaperKeys.token: "",
        ])
    }

    static var showInMenuBar: Bool {
        (UserDefaults.standard.object(forKey: MenuBarKeys.showInMenuBar) as? Bool) ?? true
    }

    static var keepRunningInMenuBar: Bool {
        (UserDefaults.standard.object(forKey: MenuBarKeys.keepRunningInMenuBar) as? Bool) ?? true
    }

    static var shouldKeepAliveInMenuBar: Bool {
        showInMenuBar && keepRunningInMenuBar
    }
}
