import AppKit
import Foundation

extension KeyboardStore {
    private static let telemetryCountsKey = "telemetry.keyCounts"
    private static let telemetryPeakWPMKey = "telemetry.peakWPM"

    var totalKeystrokes: Int {
        internalKeyCounts.values.reduce(0, +)
    }

    /// Per-slot intensity in `0...1` normalized to the most frequently pressed switch.
    var normalizedHeatmap: [Int: Float] {
        guard let maxCount = internalKeyCounts.values.max(), maxCount > 0 else { return [:] }
        let denom = Float(maxCount)
        var out = [Int: Float]()
        out.reserveCapacity(internalKeyCounts.count)
        for (idx, count) in internalKeyCounts where count > 0 {
            out[idx] = min(1, max(0.08, Float(count) / denom))
        }
        return out
    }

    func loadSavedTelemetry() {
        if let raw = defaults.dictionary(forKey: Self.telemetryCountsKey) as? [String: Int] {
            var restored = [Int: Int]()
            for (k, v) in raw {
                if let idx = Int(k), v > 0 { restored[idx] = v }
            }
            internalKeyCounts = restored
            keyCounts = restored
        }
        let savedPeak = defaults.integer(forKey: Self.telemetryPeakWPMKey)
        internalPeakWPM = savedPeak
        peakWPM = savedPeak
    }

    func handleViewContextChanged() {
        if inKeyboardStudio && section == .test {
            recomputeWPM()
            publishTelemetryNow()
        }
        syncPressed()
    }

    func recordKeystroke(slotIndex: Int, countsForWPM: Bool = true) {
        internalKeyCounts[slotIndex, default: 0] += 1

        if countsForWPM {
            let now = ContinuousClock.now
            keystrokeTimestamps.append(now)
            recomputeWPM(at: now)
            ensureWPMDecayTask()
        }

        telemetryDirty = true
        scheduleTelemetrySave()

        if inKeyboardStudio && section == .test && isMainWindowVisible {
            scheduleTelemetryPublish()
        }
    }

    func recomputeWPM(at now: ContinuousClock.Instant = .now) {
        keystrokeTimestamps.removeAll { $0.duration(to: now) > .seconds(15) }
        guard let first = keystrokeTimestamps.first else {
            internalCurrentWPM = 0
            return
        }
        let d = first.duration(to: now)
        let elapsed = max(2.5, Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
        let words = Double(keystrokeTimestamps.count) / 5.0
        let wpm = Int(((words / elapsed) * 60.0).rounded())
        internalCurrentWPM = max(0, min(320, wpm))
        if internalCurrentWPM > internalPeakWPM {
            internalPeakWPM = internalCurrentWPM
        }
    }

    private func ensureWPMDecayTask() {
        guard wpmDecayTask == nil else { return }
        wpmDecayTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self.recomputeWPM()
                if self.inKeyboardStudio && self.section == .test && self.isMainWindowVisible && self.currentWPM != self.internalCurrentWPM {
                    self.publishTelemetryNow()
                }
                if self.keystrokeTimestamps.isEmpty { break }
            }
            if !Task.isCancelled {
                self?.wpmDecayTask = nil
            }
        }
    }

    func publishTelemetryNow() {
        telemetryPublishTask?.cancel()
        telemetryPublishTask = nil
        lastTelemetryPublish = ContinuousClock.now
        if keyCounts != internalKeyCounts { keyCounts = internalKeyCounts }
        if currentWPM != internalCurrentWPM { currentWPM = internalCurrentWPM }
        if peakWPM != internalPeakWPM { peakWPM = internalPeakWPM }
    }

    private func scheduleTelemetryPublish() {
        let now = ContinuousClock.now
        if let lastTelemetryPublish, lastTelemetryPublish.duration(to: now) < .milliseconds(250) {
            guard telemetryPublishTask == nil else { return }
            telemetryPublishTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.publishTelemetryNow()
            }
            return
        }
        publishTelemetryNow()
    }

    private func scheduleTelemetrySave() {
        guard telemetrySaveTask == nil else { return }
        telemetrySaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.telemetrySaveTask = nil
            self.flushTelemetryToDefaults()
        }
    }

    func flushTelemetryToDefaults() {
        telemetrySaveTask?.cancel()
        telemetrySaveTask = nil
        guard telemetryDirty else { return }
        telemetryDirty = false

        var serialized = [String: Int]()
        serialized.reserveCapacity(internalKeyCounts.count)
        for (idx, count) in internalKeyCounts {
            serialized[String(idx)] = count
        }
        defaults.set(serialized, forKey: Self.telemetryCountsKey)
        defaults.set(internalPeakWPM, forKey: Self.telemetryPeakWPMKey)
    }

    func resetTelemetry() {
        telemetryPublishTask?.cancel()
        telemetryPublishTask = nil
        telemetrySaveTask?.cancel()
        telemetrySaveTask = nil
        wpmDecayTask?.cancel()
        wpmDecayTask = nil
        telemetryDirty = false
        internalKeyCounts = [:]
        internalCurrentWPM = 0
        internalPeakWPM = 0
        keyCounts = [:]
        keystrokeTimestamps = []
        currentWPM = 0
        peakWPM = 0
        knobCWCount = 0
        knobCCWCount = 0
        learnedFnRawBit = nil
        learnedOSRawBits = []
        defaults.removeObject(forKey: Self.telemetryCountsKey)
        defaults.removeObject(forKey: Self.telemetryPeakWPMKey)
    }

    /// Thermal emission ramp for 3D keycaps: cool ocean blue -> cyan -> emerald -> amber -> hot coral.
    nonisolated static func heatmapColor(intensity t: Float) -> NSColor {
        let clamped = min(1, max(0, t))
        guard clamped > 0.001 else { return .black }
        let stops: [(Float, (CGFloat, CGFloat, CGFloat))] = [
            (0.0,  (0.06, 0.18, 0.45)),
            (0.30, (0.04, 0.42, 0.56)),
            (0.55, (0.08, 0.52, 0.24)),
            (0.80, (0.66, 0.42, 0.05)),
            (1.0,  (0.75, 0.14, 0.18)),
        ]
        for i in 0..<(stops.count - 1) {
            let (t0, c0) = stops[i]
            let (t1, c1) = stops[i + 1]
            if clamped <= t1 {
                let f = CGFloat((clamped - t0) / max(1e-4, t1 - t0))
                return NSColor(
                    srgbRed: c0.0 + (c1.0 - c0.0) * f,
                    green: c0.1 + (c1.1 - c0.1) * f,
                    blue: c0.2 + (c1.2 - c0.2) * f,
                    alpha: 1
                )
            }
        }
        return NSColor(srgbRed: 0.75, green: 0.14, blue: 0.18, alpha: 1)
    }
}
