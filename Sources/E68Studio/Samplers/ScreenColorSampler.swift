import AppKit
import CoreMedia
import ScreenCaptureKit

/// Watches the main display at a tiny resolution and boils each frame down to one colour, with
/// the screen edges counting more than the middle (like a TV's ambient backlight). E68 Studio's
/// own windows are left out. Needs Screen Recording permission.
final class ScreenColorSampler: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Sample: Equatable {
        var hue: Float = 0.58
        var saturation: Float = 0
        /// 0…1, how bright the screen is overall.
        var brightness: Float = 0
    }

    enum SamplerError: LocalizedError {
        case noDisplay
        var errorDescription: String? { "No display to watch." }
    }

    private let lock = NSLock()
    private var latest = Sample()
    private var stream: SCStream?
    private var generation: UInt64 = 0
    private let queue = DispatchQueue(label: "e68.screen-colour", qos: .userInitiated)
    var onUnexpectedStop: (@Sendable () -> Void)?

    var current: Sample {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return stream != nil
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    func start() async throws {
        let expectedGen: UInt64 = lock.withLock {
            if stream != nil { return 0 }
            generation &+= 1
            return generation
        }
        guard expectedGen != 0 else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard lock.withLock({ generation == expectedGen }) else { return }
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw SamplerError.noDisplay
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = 64
        config.height = 36
        config.minimumFrameInterval = CMTime(value: 1, timescale: 24)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 3
        config.capturesAudio = false

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()

        let installed = lock.withLock { () -> Bool in
            guard generation == expectedGen else { return false }
            stream = s
            return true
        }
        if !installed {
            try? await s.stopCapture()
        }
    }

    func stop() {
        lock.lock()
        generation &+= 1
        let s = stream
        stream = nil
        latest = Sample()
        lock.unlock()
        guard let s else { return }
        Task { try? await s.stopCapture() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let shouldNotify: Bool = lock.withLock {
            guard self.stream === stream else { return false }
            self.stream = nil
            self.latest = Sample()
            return true
        }
        if shouldNotify {
            onUnexpectedStop?()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let pixels = sampleBuffer.imageBuffer else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           SCFrameStatus(rawValue: raw) != .complete {
            return
        }
        guard let sample = Self.analyze(pixels) else { return }
        lock.lock()
        if self.stream === stream {
            latest = sample
        }
        lock.unlock()
    }

    /// Edge-weighted, saturation-weighted average colour of a BGRA frame.
    static func analyze(_ buffer: CVPixelBuffer) -> Sample? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard w > 2, h > 2 else { return nil }
        let p = base.assumingMemoryBound(to: UInt8.self)

        var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0, wSum: Float = 0
        var luma: Float = 0, lumaWeight: Float = 0
        let edgeX = max(1, w / 5), edgeY = max(1, h / 5)
        for y in 0..<h {
            let row = p + y * rowBytes
            let nearEdgeY = y < edgeY || y >= h - edgeY
            for x in 0..<w {
                let px = row + x * 4
                let b = Float(px[0]) / 255, g = Float(px[1]) / 255, r = Float(px[2]) / 255
                let maxC = max(r, g, b), minC = min(r, g, b)
                let sat = maxC > 0.001 ? (maxC - minC) / maxC : 0
                let position: Float = (nearEdgeY || x < edgeX || x >= w - edgeX) ? 1 : 0.35
                luma += (0.2126 * r + 0.7152 * g + 0.0722 * b) * position
                lumaWeight += position
                // Vivid, lit pixels steer the colour; greys and black barely count.
                let weight = position * (0.04 + sat * sat * 2) * (0.1 + maxC)
                rSum += r * weight; gSum += g * weight; bSum += b * weight; wSum += weight
            }
        }
        guard wSum > 0, lumaWeight > 0 else { return nil }
        let (hue, sat, _) = rgbToHSV(rSum / wSum, gSum / wSum, bSum / wSum)
        return Sample(hue: hue, saturation: min(1, sat * 1.45), brightness: luma / lumaWeight)
    }

    static func rgbToHSV(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let (h, s, v) = ColorMath.rgbToHSV(r, g, b)
        return (h, s, v)
    }
}
