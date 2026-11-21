import AppKit
import CoreGraphics
import ImageIO

/// Samples the user's macOS desktop wallpaper image (`NSWorkspace.shared.desktopImageURL`)
/// and extracts primary + secondary accent colours without requiring Screen Recording permissions.
/// `currentPalette()` is always lock-safe and non-blocking so 60 Hz callers never hit disk or AppKit.
final class WallpaperColorSampler: @unchecked Sendable {
    static let shared = WallpaperColorSampler()

    typealias Palette = (hue: Float, saturation: Float, secondaryHue: Float, secondarySaturation: Float)

    private let lock = NSLock()
    private let refreshQueue = DispatchQueue(label: "e68.wallpaper-sampler", qos: .utility)
    private var lastCheck: TimeInterval = 0
    private var isRefreshing = false
    private var lastURL: URL?
    private var lastModDate: Date?
    private var cachedPalette: Palette = (0.58, 0.82, 0.78, 0.75)
    private var spaceObserver: NSObjectProtocol?

    private init() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleRefresh(force: true)
        }
        scheduleRefresh(force: true)
    }

    deinit {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
    }

    func currentPalette() -> Palette {
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock()
        let shouldRefresh = !isRefreshing && (now - lastCheck >= 5.0)
        if shouldRefresh {
            isRefreshing = true
            lastCheck = now
        }
        let palette = cachedPalette
        lock.unlock()

        if shouldRefresh {
            DispatchQueue.main.async { [weak self] in
                self?.readURLAndExtract()
            }
        }
        return palette
    }

    @MainActor
    func refreshAndFetch() async -> Palette {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return lock.withLock { cachedPalette }
        }
        let now = Date().timeIntervalSinceReferenceDate
        lock.withLock { lastCheck = now }
        return await withCheckedContinuation { continuation in
            refreshQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: (0.58, 0.82, 0.78, 0.75))
                    return
                }
                continuation.resume(returning: self.resolveAndExtract(for: url))
            }
        }
    }

    private func scheduleRefresh(force: Bool) {
        lock.lock()
        guard !isRefreshing else {
            lock.unlock()
            return
        }
        if force || Date().timeIntervalSinceReferenceDate - lastCheck >= 5.0 {
            isRefreshing = true
            lastCheck = Date().timeIntervalSinceReferenceDate
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.readURLAndExtract()
            }
            return
        }
        lock.unlock()
    }

    private func readURLAndExtract() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            lock.withLock { isRefreshing = false }
            return
        }
        refreshQueue.async { [weak self] in
            guard let self else { return }
            defer { self.lock.withLock { self.isRefreshing = false } }
            _ = self.resolveAndExtract(for: url)
        }
    }

    private func resolveAndExtract(for url: URL) -> Palette {
        let modDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        let unchangedPalette: Palette? = lock.withLock {
            if url == lastURL && modDate == lastModDate {
                return cachedPalette
            }
            return nil
        }
        if let unchangedPalette { return unchangedPalette }

        let imageURL: URL = {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
               let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
               let firstImage = files
                   .filter({ ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) })
                   .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                   .first {
                return firstImage
            }
            return url
        }()

        let parsed = Self.extractPalette(from: imageURL)
        return lock.withLock {
            lastURL = url
            lastModDate = modDate
            if let parsed {
                cachedPalette = parsed
            }
            return cachedPalette
        }
    }

    static func extractPalette(from url: URL) -> Palette? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let size = 48
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        let binCount = 36
        var binWeights = [Float](repeating: 0, count: binCount)
        var binSinH = [Float](repeating: 0, count: binCount)
        var binCosH = [Float](repeating: 0, count: binCount)
        var binSat = [Float](repeating: 0, count: binCount)

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Float(pixels[i]) / 255.0
            let g = Float(pixels[i + 1]) / 255.0
            let b = Float(pixels[i + 2]) / 255.0
            let (h, sat, bri) = ColorMath.rgbToHSV(r, g, b)
            guard bri > 0.10, bri < 0.98, sat > 0.14 else { continue }

            let weight = powf(sat, 1.35) * powf(bri, 0.75)
            let bin = min(binCount - 1, max(0, Int(h * Float(binCount))))
            let angle = h * 2.0 * .pi
            binWeights[bin] += weight
            binSinH[bin] += sin(angle) * weight
            binCosH[bin] += cos(angle) * weight
            binSat[bin] += sat * weight
        }

        func cluster(around center: Int) -> (hue: Float, sat: Float, weight: Float) {
            var wSum: Float = 0, sinSum: Float = 0, cosSum: Float = 0, satSum: Float = 0
            for offset in -1...1 {
                let idx = (center + offset + binCount) % binCount
                wSum += binWeights[idx]
                sinSum += binSinH[idx]
                cosSum += binCosH[idx]
                satSum += binSat[idx]
            }
            guard wSum > 0.001 else { return (0.58, 0.78, 0) }
            var hue = atan2(sinSum, cosSum) / (2.0 * .pi)
            if hue < 0 { hue += 1.0 }
            let boostedSat = min(1.0, max(0.55, (satSum / wSum) * 1.2))
            return (hue, boostedSat, wSum)
        }

        var primaryBin = 0
        var primaryBest: Float = -1
        for b in 0..<binCount {
            let c = cluster(around: b)
            if c.weight > primaryBest {
                primaryBest = c.weight
                primaryBin = b
            }
        }
        guard primaryBest > 0.01 else { return (0.58, 0.78, 0.75, 0.72) }
        let primary = cluster(around: primaryBin)

        var secondaryBin = primaryBin
        var secondaryBest: Float = -1
        for b in 0..<binCount {
            let dist = min(abs(b - primaryBin), binCount - abs(b - primaryBin))
            guard dist >= 4 else { continue }
            let c = cluster(around: b)
            if c.weight > secondaryBest {
                secondaryBest = c.weight
                secondaryBin = b
            }
        }
        let secondary: (hue: Float, sat: Float)
        if secondaryBest > primaryBest * 0.15 {
            let s = cluster(around: secondaryBin)
            secondary = (s.hue, s.sat)
        } else {
            secondary = (ColorMath.wrapHue(primary.hue + 0.14), max(0.55, primary.sat * 0.9))
        }

        return (primary.hue, primary.sat, secondary.hue, secondary.sat)
    }
}
