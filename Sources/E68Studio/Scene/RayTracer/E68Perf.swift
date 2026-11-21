import Foundation
import Metal
import MetalKit
import SceneKit
import AppKit
import MetalFX
import Darwin
import simd

/// Launch-flag (`-e68.perf YES`) telemetry; compiles to an inline static boolean check when off.
enum E68Perf {
    static let enabled: Bool = UserDefaults.standard.bool(forKey: "e68.perf")
    static var processStartTime: CFTimeInterval = CACurrentMediaTime()

    private static let lock = NSLock()
    private static var loggedFirstFrame = false
    private static var windowStart: CFTimeInterval = 0
    private static var framesDrawn: Int = 0
    private static var gpuSumMs: Double = 0
    private static var gpuCount: Int = 0
    private static var gpuWorstMs: Double = 0
    private static var stepSumMs: Double = 0
    private static var syncSumMs: Double = 0
    private static var lastGear: String = "init"
    private static var lastInternalSize: SIMD2<UInt32> = .zero
    private static var lastOutputSize: SIMD2<UInt32> = .zero
    private static var lastSampleIndex: UInt32 = 0
    private static var maxSamples: UInt32 = PathTracerRenderer.maxProgressiveSamples
    private static var lastTexCount: Int = 0
    private static var settleStartTime: CFTimeInterval = 0
    private static var settleTimingActive = false

    static func logLine(_ message: String) {
        guard enabled else { return }
        let tMs = (CACurrentMediaTime() - processStartTime) * 1000.0
        fputs(String(format: "[E68Perf +%7.1fms] %@\n", tMs, message), stderr)
        fflush(stderr)
    }

    static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }

    static func recordCPUFrame(
        gear: String,
        internalSize: SIMD2<UInt32>,
        outputSize: SIMD2<UInt32>,
        sampleIndex: UInt32,
        maxProgressiveSamples: UInt32,
        stepMs: Double,
        syncMs: Double,
        texCount: Int
    ) {
        let now = CACurrentMediaTime()
        lock.lock()
        if windowStart == 0 { windowStart = now }
        framesDrawn += 1
        stepSumMs += stepMs
        syncSumMs += syncMs
        lastGear = gear
        lastInternalSize = internalSize
        lastOutputSize = outputSize
        lastSampleIndex = sampleIndex
        maxSamples = maxProgressiveSamples
        lastTexCount = texCount
        if gear == "gear2-prog" && sampleIndex == 1 {
            settleStartTime = now
            settleTimingActive = true
        } else if gear.hasPrefix("gear1") {
            settleTimingActive = false
        }
        lock.unlock()
    }

    static func markSettled(sampleIndex: UInt32, texCount: Int) {
        let now = CACurrentMediaTime()
        lock.lock()
        let elapsedMs = settleTimingActive ? (now - settleStartTime) * 1000.0 : -1.0
        settleTimingActive = false
        lock.unlock()
        let rss = residentMemoryMB()
        if elapsedMs >= 0 {
            logLine(String(format: "settled (%u samples) in %.1f ms (%.2f s) | texCount=%d rss=%.1f MB",
                           sampleIndex, elapsedMs, elapsedMs / 1000.0, texCount, rss))
        } else {
            logLine(String(format: "settled (%u samples) | texCount=%d rss=%.1f MB",
                           sampleIndex, texCount, rss))
        }
    }

    static func flushWindow(label: String) {
        guard enabled else { return }
        lock.lock()
        let now = CACurrentMediaTime()
        let elapsed = windowStart > 0 ? max(0.001, now - windowStart) : 1.0
        let msg: String
        if framesDrawn > 0 {
            let fps = Double(framesDrawn) / elapsed
            let avgGpu = gpuCount > 0 ? gpuSumMs / Double(gpuCount) : 0.0
            let avgStep = stepSumMs / Double(framesDrawn)
            let avgSync = syncSumMs / Double(framesDrawn)
            msg = String(
                format: "[%@] fps=%.1f (%d frames/%.2fs) gear=%@ internal=%ux%u output=%ux%u sample=%u/%u gpuAvg=%.2fms gpuWorst=%.2fms cpuStep=%.2fms cpuSync=%.2fms texCount=%d rss=%.1fMB",
                label, fps, framesDrawn, elapsed, lastGear,
                lastInternalSize.x, lastInternalSize.y,
                lastOutputSize.x, lastOutputSize.y,
                lastSampleIndex, maxSamples,
                avgGpu, gpuWorstMs, avgStep, avgSync,
                lastTexCount, residentMemoryMB()
            )
        } else {
            msg = String(format: "[%@] fps=0.0 (0 frames/%.2fs) texCount=%d rss=%.1fMB",
                         label, elapsed, lastTexCount, residentMemoryMB())
        }
        windowStart = now
        framesDrawn = 0
        gpuSumMs = 0
        gpuCount = 0
        gpuWorstMs = 0
        stepSumMs = 0
        syncSumMs = 0
        lock.unlock()
        logLine(msg)
    }

    static func recordCompletedGPU(gpuMs: Double, gear: String) {
        let now = CACurrentMediaTime()
        var pendingLog: String?
        var firstFrameMsg: String?

        lock.lock()
        if !loggedFirstFrame {
            loggedFirstFrame = true
            let launchMs = (now - processStartTime) * 1000.0
            firstFrameMsg = String(format: "first presented frame: %.1f ms since launch (gear=%@, gpu=%.2f ms, rss=%.1f MB)",
                                   launchMs, gear, gpuMs, residentMemoryMB())
        }
        if gpuMs > 0 {
            gpuSumMs += gpuMs
            gpuCount += 1
            if gpuMs > gpuWorstMs { gpuWorstMs = gpuMs }
        }
        if windowStart > 0 && (now - windowStart) >= 1.0 && framesDrawn > 0 {
            let elapsed = now - windowStart
            let fps = Double(framesDrawn) / elapsed
            let avgGpu = gpuCount > 0 ? gpuSumMs / Double(gpuCount) : 0.0
            let avgStep = stepSumMs / Double(framesDrawn)
            let avgSync = syncSumMs / Double(framesDrawn)
            let rss = residentMemoryMB()
            pendingLog = String(
                format: "fps=%.1f (%d frames/%.2fs) gear=%@ internal=%ux%u output=%ux%u sample=%u/%u gpuAvg=%.2fms gpuWorst=%.2fms cpuStep=%.2fms cpuSync=%.2fms texCount=%d rss=%.1fMB",
                fps, framesDrawn, elapsed, lastGear,
                lastInternalSize.x, lastInternalSize.y,
                lastOutputSize.x, lastOutputSize.y,
                lastSampleIndex, maxSamples,
                avgGpu, gpuWorstMs, avgStep, avgSync,
                lastTexCount, rss
            )
            windowStart = now
            framesDrawn = 0
            gpuSumMs = 0
            gpuCount = 0
            gpuWorstMs = 0
            stepSumMs = 0
            syncSumMs = 0
        }
        lock.unlock()

        if let firstFrameMsg { logLine(firstFrameMsg) }
        if let pendingLog { logLine(pendingLog) }
    }
}

struct RTCompositeParams {
    var progressBlend: Float
    var exposureScale: Float
    var bloomStrength: Float
    var vignetteStrength: Float
    var grainStrength: Float
    var frameIndex: UInt32
    var isProgressiveOnly: UInt32
    var pad0: UInt32
}
