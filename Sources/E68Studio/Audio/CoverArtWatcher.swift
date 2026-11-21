import Foundation

/// Extracted primary and secondary accent hues from the currently playing track's cover art.
struct CoverColorPalette: Sendable, Equatable {
    var primaryHue: Float = 0
    var primarySaturation: Float = 1
    var secondaryHue: Float = 0
    var secondarySaturation: Float = 1
    var isAvailable: Bool = false
}

/// Observes macOS Now Playing album artwork through an Apple-signed `/usr/bin/swift`
/// child process (required on macOS 15.4+ for `MediaRemote.framework` access) and
/// extracts a primary + contrasting secondary palette for Sound Wave lighting.
final class CoverArtWatcher: @unchecked Sendable {
    private let lock = NSLock()
    private let launchQueue = DispatchQueue(label: "e68.coverart.launch", qos: .utility)
    private var process: Process?
    private var palette = CoverColorPalette()
    private var generation: UInt64 = 0

    func currentPalette() -> CoverColorPalette {
        lock.lock()
        defer { lock.unlock() }
        return palette
    }

    func start() {
        let expectedGen: UInt64 = lock.withLock {
            generation &+= 1
            return generation
        }
        stopRunningProcess()

        launchQueue.async { [weak self] in
            guard let self, let swiftURL = Self.findSwiftExecutable() else { return }
            let stillCurrent = self.lock.withLock { self.generation == expectedGen }
            guard stillCurrent else { return }

            let proc = Process()
            proc.executableURL = swiftURL
            proc.arguments = ["-e", Self.helperScript]
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = FileHandle.nullDevice

            var lineBuffer = Data()
            outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                lineBuffer.append(data)
                while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
                    let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newlineIndex)
                    lineBuffer.removeSubrange(lineBuffer.startIndex...newlineIndex)
                    if let line = String(data: lineData, encoding: .utf8) {
                        self?.parseLine(line, generation: expectedGen)
                    }
                }
            }
            proc.terminationHandler = { _ in
                outPipe.fileHandleForReading.readabilityHandler = nil
            }

            do {
                try proc.run()
                let installed = self.lock.withLock { () -> Bool in
                    guard self.generation == expectedGen else { return false }
                    self.process = proc
                    return true
                }
                if !installed {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    if proc.isRunning { proc.terminate() }
                }
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
            }
        }
    }

    func stop() {
        lock.lock()
        generation &+= 1
        palette = CoverColorPalette()
        lock.unlock()
        stopRunningProcess()
    }

    private func stopRunningProcess() {
        let proc: Process? = lock.withLock {
            let p = process
            process = nil
            return p
        }
        if let proc {
            (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if proc.isRunning { proc.terminate() }
        }
    }

    private static func findSwiftExecutable() -> URL? {
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift",
            "/Library/Developer/CommandLineTools/usr/bin/swift",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // Check `xcode-select -p` first instead of invoking the `/usr/bin/swift` xcrun shim directly,
        // so Macs without developer tools never see an OS Command Line Tools install popup.
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        probe.arguments = ["-p"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = FileHandle.nullDevice
        guard (try? probe.run()) != nil else { return nil }
        probe.waitUntilExit()
        guard probe.terminationStatus == 0,
              let devDir = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !devDir.isEmpty else {
            return nil
        }
        for rel in ["Toolchains/XcodeDefault.xctoolchain/usr/bin/swift", "usr/bin/swift"] {
            let path = "\(devDir)/\(rel)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func parseLine(_ line: String, generation expectedGen: UInt64) {
        let parts = line.split(separator: " ")
        if parts.count >= 5, parts[0] == "COVER",
           let h1 = Float(parts[1]), let s1 = Float(parts[2]),
           let h2 = Float(parts[3]), let s2 = Float(parts[4]) {
            lock.lock()
            if generation == expectedGen {
                palette = CoverColorPalette(
                    primaryHue: h1,
                    primarySaturation: s1,
                    secondaryHue: h2,
                    secondarySaturation: s2,
                    isAvailable: true
                )
            }
            lock.unlock()
        } else if parts.first == "NONE" {
            lock.lock()
            if generation == expectedGen {
                palette = CoverColorPalette()
            }
            lock.unlock()
        }
    }

    private static let helperScript = """
    import Foundation
    import AppKit

    let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
    typealias InfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    typealias RegFn = @convention(c) (DispatchQueue) -> Void
    guard let infoSym = dlsym(h, "MRMediaRemoteGetNowPlayingInfo") else { exit(1) }
    let getInfo = unsafeBitCast(infoSym, to: InfoFn.self)
    if let regSym = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") {
        unsafeBitCast(regSym, to: RegFn.self)(DispatchQueue.main)
    }

    func rgbToHSB(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC
        let v = maxC
        let s = maxC > 0 ? delta / maxC : 0
        var h: Float = 0
        if delta > 0.0001 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
            } else if maxC == g {
                h = (b - r) / delta + 2.0
            } else {
                h = (r - g) / delta + 4.0
            }
            h /= 6.0
            if h < 0 { h += 1.0 }
        }
        return (h, s, v)
    }

    func dominantCoverPalette(from data: Data) -> (Float, Float, Float, Float)? {
        guard let img = NSImage(data: data),
              let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let size = 40
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: size, height: size))

        var binWeights = [Float](repeating: 0, count: 36)
        var binR = [Float](repeating: 0, count: 36)
        var binG = [Float](repeating: 0, count: 36)
        var binB = [Float](repeating: 0, count: 36)
        var totalWeight: Float = 0

        for y in 0..<size {
            for x in 0..<size {
                let idx = (y * size + x) * 4
                let a = Float(pixels[idx + 3]) / 255.0
                guard a > 0.1 else { continue }
                let r = min(1.0, (Float(pixels[idx]) / 255.0) / a)
                let g = min(1.0, (Float(pixels[idx + 1]) / 255.0) / a)
                let b = min(1.0, (Float(pixels[idx + 2]) / 255.0) / a)
                let (hue, sat, bri) = rgbToHSB(r, g, b)
                if sat < 0.12 || bri < 0.08 { continue }
                let inCenter = x >= 6 && x < size - 6 && y >= 6 && y < size - 6
                let spatial: Float = inCenter ? 1.35 : 0.7
                let w = powf(sat, 1.35) * (0.25 + 0.75 * bri) * spatial
                let bin = min(35, max(0, Int((hue * 36.0).rounded(.down)) % 36))
                binWeights[bin] += w
                binR[bin] += r * w
                binG[bin] += g * w
                binB[bin] += b * w
                totalWeight += w
            }
        }

        guard totalWeight > 0.08 else {
            return nil
        }

        func clusterColor(around centerBin: Int) -> (Float, Float, Float) {
            var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0, wSum: Float = 0
            for offset in [-1, 0, 1] {
                let b = (centerBin + offset + 36) % 36
                rSum += binR[b]
                gSum += binG[b]
                bSum += binB[b]
                wSum += binWeights[b]
            }
            guard wSum > 0.001 else { return (0, 0, 0) }
            let (h, s, _) = rgbToHSB(rSum / wSum, gSum / wSum, bSum / wSum)
            let tunedSat = s < 0.22 ? min(1.0, s * 1.25) : max(0.40, min(1.0, s * 1.12))
            return (h, tunedSat, wSum)
        }

        var bestBin = 0
        var bestScore: Float = -1
        for b in 0..<36 {
            let prev = (b + 35) % 36
            let next = (b + 1) % 36
            let score = binWeights[b] + 0.55 * (binWeights[prev] + binWeights[next])
            if score > bestScore {
                bestScore = score
                bestBin = b
            }
        }

        let (h1, s1, w1) = clusterColor(around: bestBin)

        var secondBin = -1
        var secondScore: Float = -1
        for b in 0..<36 {
            let dist = min(abs(b - bestBin), 36 - abs(b - bestBin))
            guard dist >= 5 else { continue }
            let prev = (b + 35) % 36
            let next = (b + 1) % 36
            let score = binWeights[b] + 0.55 * (binWeights[prev] + binWeights[next])
            if score > secondScore {
                secondScore = score
                secondBin = b
            }
        }

        if secondBin >= 0 && secondScore >= bestScore * 0.14 && w1 > 0.001 {
            let (h2, s2, _) = clusterColor(around: secondBin)
            return (h1, s1, h2, s2)
        } else {
            let h2 = (h1 + 0.14).truncatingRemainder(dividingBy: 1.0)
            let s2 = max(0.32, s1 * 0.78)
            return (h1, s1, h2, s2)
        }
    }

    var lastKey = ""
    func refresh() {
        if getppid() == 1 { exit(0) }
        getInfo(DispatchQueue.main) { info in
            let id = info["kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] as? String
                ?? info["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String
                ?? info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
                ?? ""
            let artData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
            let key = "\\(id):\\(artData?.count ?? 0):\\(artData?.hashValue ?? 0)"
            guard key != lastKey else { return }
            lastKey = key
            if let artData, let (h1, s1, h2, s2) = dominantCoverPalette(from: artData) {
                print(String(format: "COVER %.4f %.4f %.4f %.4f", h1, s1, h2, s2))
            } else {
                print("NONE")
            }
            fflush(stdout)
        }
    }

    NotificationCenter.default.addObserver(forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"), object: nil, queue: .main) { _ in
        refresh()
    }
    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
        refresh()
    }
    refresh()
    RunLoop.main.run()
    """
}
