import Foundation
import CoreAudio
import AudioToolbox
import Accelerate

/// Capture health state for macOS system audio output.
enum AudioCaptureStatus: Sendable, Equatable {
    case idle
    case active
    case unavailable(String)
}

/// A lightweight, immutable snapshot of real-time Mac audio energy and frequency spectrum,
/// safe to read across threads by both the 60 FPS SceneKit renderer and the HID pump.
struct AudioSnapshot: Sendable {
    /// Overall smoothed volume / energy (0.0 to 1.0).
    var amplitude: Float = 0
    /// Peak instantaneous energy (0.0 to 1.0).
    var peak: Float = 0
    /// Bass energy (~45 to 250 Hz, 0.0 to 1.0).
    var bass: Float = 0
    /// Midrange energy (~250 to 2500 Hz, 0.0 to 1.0).
    var mid: Float = 0
    /// Treble energy (~2500 to 14000 Hz, 0.0 to 1.0).
    var treble: Float = 0
    /// 16 logarithmic frequency bands (0.0 to 1.0) mapped across keyboard columns.
    var bands: [Float] = Array(repeating: 0, count: 16)
    /// 32 normalized real-time PCM waveform samples (-1.0 to 1.0) across horizontal axis.
    var waveform: [Float] = Array(repeating: 0, count: 32)
    /// Decaying beat pulse energy (0.0 to 1.0).
    var beat: Float = 0
    /// Whether a beat onset was detected on this frame.
    var beatDetected: Bool = false
    /// Monotonic beat counter. Consumers polling slower than the DSP compare this instead of
    /// `beatDetected`, so a one-frame onset is never missed.
    var beatCount: Int = 0
    /// Strength (0.0 to 1.0) of the most recent beat onset.
    var beatStrength: Float = 0
    /// Dynamic spectral hue (0.0 to 1.0) derived from harmonic balance.
    var dominantHue: Float = 0.62
    /// Dominant color hue (0.0 to 1.0) extracted from the playing track's album cover.
    var coverHue: Float = 0
    /// Dominant color saturation (0.0 to 1.0) extracted from the playing track's album cover.
    var coverSaturation: Float = 1
    /// Secondary contrasting/accent hue (0.0 to 1.0) extracted from the playing track's album cover.
    var secondaryCoverHue: Float = 0
    /// Secondary contrasting/accent saturation (0.0 to 1.0) extracted from the playing track's album cover.
    var secondaryCoverSaturation: Float = 1
    /// Whether an album cover color has been detected for the current track.
    var hasCoverColor: Bool = false
    /// Live musical expression blend (0.0 warm/root -> 1.0 bright/peak) driven by tonal balance & flux.
    var colorShift: Float = 0
    /// Whether live system audio is currently audible.
    var isPlaying: Bool = false
}

/// Captures live macOS system audio output via CoreAudio Process Tap (no microphone required)
/// and performs a 2048-point Accelerate FFT to extract 16 frequency bands, sound-wave envelope,
/// and beat energy.
final class AudioMonitor: @unchecked Sendable {
    let stateLock = NSLock()
    let ringLock = NSLock()

    var isRunning = false
    var currentSnapshot = AudioSnapshot()
    private var captureStatus: AudioCaptureStatus = .idle

    // CoreAudio Process Tap handles
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    var sampleRate: Float = 48000.0

    // Ring buffer for incoming mono PCM samples
    static let fftSize = 2048
    static let ringCapacity = 8192
    var ringBuffer = [Float](repeating: 0, count: ringCapacity)
    var ringWriteIndex = 0
    var lastSampleTimestamp: TimeInterval = 0
    var lastActiveAudioTimestamp: TimeInterval = 0
    var dspIdleSleeping = false
    var hasSettledIdle = false
    var lastIdleCover = CoverColorPalette()

    // Accelerate FFT resources
    let log2n = vDSP_Length(11) // 2^11 = 2048
    let fftSetup: FFTSetup?
    var hannWindow: [Float]
    var realBuffer: [Float]
    var imagBuffer: [Float]
    var magnitudes: [Float]
    var bandBinRanges: [(start: Int, end: Int)] = []
    var subBassBinRange: (start: Int, end: Int) = (2, 4)
    var voiceBinRange: (start: Int, end: Int) = (7, 136)

    // DSP loop
    private static let dspQueueKey = DispatchSpecificKey<UInt8>()
    private let ioQueue = DispatchQueue(label: "e68.audio.ioproc", qos: .userInteractive)
    let dspQueue: DispatchQueue
    var dspTimer: DispatchSourceTimer?

    // Smoothing, AGC, and adaptive beat/waveform state (accessed only on dspQueue)
    var smoothedBands = [Float](repeating: 0, count: 16)
    var prevBands = [Float](repeating: 0, count: 16)
    var smoothedWaveform = [Float](repeating: 0, count: 32)
    var dspSamples = [Float](repeating: 0, count: fftSize)
    var dspFresh = [Float](repeating: 0, count: ringCapacity / 2)
    var dspRawWave = [Float](repeating: 0, count: 32)
    var dspRawBands = [Float](repeating: 0, count: 16)
    var agcPeak: Float = 0.03
    var loudnessRef: Float = 0.02
    var waveformPeak: Float = 0.05
    var smoothWaveAmp: Float = 0
    var smoothColorShift: Float = 0
    var bassPeak: Float = 0.03
    var kickHistory: Float = 0.008
    var fluxHistory: Float = 0.06
    var smoothBass: Float = 0
    var beatEnergy: Float = 0
    var smoothHue: Float = 0.62
    var lastBeatTime: TimeInterval = 0
    var lastFrameTime: TimeInterval = 0

    // Time-domain kick detector: a 2nd-order low-pass run on every new sample, so kicks are
    // caught within one DSP tick instead of waiting for them to fill a 43 ms FFT window.
    var lastProcessedWrite = 0
    var lpB: (Float, Float, Float) = (0, 0, 0)
    var lpA: (Float, Float) = (0, 0)
    var lpX: (Float, Float) = (0, 0)
    var lpY: (Float, Float) = (0, 0)
    var lowFast: Float = 0
    var lowSlow: Float = 0.00001
    var prevLowFast: Float = 0
    var beatCount = 0
    var lastBeatStrength: Float = 0

    // Recent snapshots, so lights can be delayed to line up with what the speakers actually play.
    static let historyCapacity = 64
    var history: [(time: TimeInterval, snap: AudioSnapshot)] = []
    var historyIndex = 0

    // Output device latency (seconds), refreshed periodically on the DSP queue.
    private var cachedOutputLatency: Double = 0
    var lastLatencyQuery: TimeInterval = 0

    let coverWatcher = CoverArtWatcher()

    init() {
        let queue = DispatchQueue(label: "com.e68studio.audiodsp", qos: .userInteractive)
        queue.setSpecific(key: Self.dspQueueKey, value: 1)
        self.dspQueue = queue

        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        hannWindow = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        realBuffer = [Float](repeating: 0, count: Self.fftSize / 2)
        imagBuffer = [Float](repeating: 0, count: Self.fftSize / 2)
        magnitudes = [Float](repeating: 0, count: Self.fftSize / 2)
        rebuildBandBinRanges(sampleRate: sampleRate)
    }

    deinit {
        stop()
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    /// Reads the latest audio snapshot atomically.
    func snapshot() -> AudioSnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentSnapshot
    }

    /// Returns the snapshot published `delay` seconds ago (or the oldest one kept), so the lights can
    /// be held back to match output-device latency. Beat counters stay monotonic across delays.
    func snapshot(delay: TimeInterval) -> AudioSnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard delay > 0.002, !history.isEmpty else { return currentSnapshot }
        let target = Date().timeIntervalSinceReferenceDate - delay
        var best: AudioSnapshot?
        var bestTime: TimeInterval = -.infinity
        var oldest: (time: TimeInterval, snap: AudioSnapshot)?
        for entry in history {
            if entry.time <= target, entry.time > bestTime {
                best = entry.snap
                bestTime = entry.time
            }
            if oldest == nil || entry.time < oldest!.time { oldest = entry }
        }
        return best ?? oldest?.snap ?? currentSnapshot
    }

    /// Latency of the current default output device in seconds (device + safety offset + stream + buffer).
    /// Bluetooth headphones typically report 0.1–0.25 s; built-in speakers 0.01–0.03 s.
    func outputLatency() -> Double {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedOutputLatency
    }

    /// Reads the current capture health status.
    func status() -> AudioCaptureStatus {
        stateLock.lock()
        defer { stateLock.unlock() }
        return captureStatus
    }

    /// Starts capturing Mac system audio output via CoreAudio Process Tap.
    func start() {
        stateLock.lock()
        guard !isRunning else {
            stateLock.unlock()
            return
        }
        isRunning = true
        stateLock.unlock()

        resetDSPState()

        do {
            try setupCoreAudioTap()
            stateLock.lock()
            captureStatus = .active
            stateLock.unlock()
            startDSPTimer()
            coverWatcher.start()
        } catch {
            teardownCoreAudioTap()
            stateLock.lock()
            isRunning = false
            captureStatus = .unavailable(error.localizedDescription)
            stateLock.unlock()
        }
    }

    /// Stops capturing audio and releases CoreAudio resources.
    func stop() {
        coverWatcher.stop()

        stateLock.lock()
        guard isRunning else {
            stateLock.unlock()
            return
        }
        isRunning = false
        captureStatus = .idle
        currentSnapshot = AudioSnapshot()
        history.removeAll()
        historyIndex = 0
        let timer = dspTimer
        dspTimer = nil
        stateLock.unlock()

        timer?.cancel()
        teardownCoreAudioTap()
        // Drain any in-flight DSP frame before releasing FFT buffers or CoreAudio handles.
        if DispatchQueue.getSpecific(key: Self.dspQueueKey) == nil {
            dspQueue.sync {}
        }
    }

    // MARK: - CoreAudio Process Tap (No Microphone)

    private enum TapError: LocalizedError {
        case createTapFailed(OSStatus)
        case readUIDFailed(OSStatus)
        case createAggregateFailed(OSStatus)
        case createIOProcFailed(OSStatus)
        case startDeviceFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .createTapFailed(let s): return "System audio tap unavailable (\(s))."
            case .readUIDFailed(let s): return "Failed to query audio tap UID (\(s))."
            case .createAggregateFailed(let s): return "Failed to create audio aggregate (\(s))."
            case .createIOProcFailed(let s): return "Failed to attach audio processor (\(s))."
            case .startDeviceFailed(let s): return "Failed to start audio capture (\(s))."
            }
        }
    }

    private func setupCoreAudioTap() throws {
        // Capture all system output audio across speakers, headphones, and Bluetooth without touching the mic.
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.name = "E68StudioSystemAudioTap"
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .unmuted

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let tapErr = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard tapErr == noErr, newTapID != kAudioObjectUnknown else {
            throw TapError.createTapFailed(tapErr)
        }
        self.tapID = newTapID

        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapUIDRef: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let uidErr = AudioObjectGetPropertyData(newTapID, &uidAddr, 0, nil, &uidSize, &tapUIDRef)
        guard uidErr == noErr, let tapUID = tapUIDRef?.takeRetainedValue() as String? else {
            throw TapError.readUIDFailed(uidErr)
        }

        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioObjectGetPropertyData(newTapID, &fmtAddr, 0, nil, &asbdSize, &asbd) == noErr, asbd.mSampleRate > 8000 {
            sampleRate = Float(asbd.mSampleRate)
            rebuildBandBinRanges(sampleRate: sampleRate)
        }

        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "E68StudioSystemAudio",
            kAudioAggregateDeviceUIDKey: "local.e68studio.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var newAggID: AudioObjectID = kAudioObjectUnknown
        let aggErr = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAggID)
        guard aggErr == noErr, newAggID != kAudioObjectUnknown else {
            throw TapError.createAggregateFailed(aggErr)
        }
        self.aggregateDeviceID = newAggID

        var devFmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var devASBD = AudioStreamBasicDescription()
        var devASBDSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioObjectGetPropertyData(newAggID, &devFmtAddr, 0, nil, &devASBDSize, &devASBD) == noErr, devASBD.mSampleRate > 8000 {
            sampleRate = Float(devASBD.mSampleRate)
            rebuildBandBinRanges(sampleRate: sampleRate)
        }

        var newIOProcID: AudioDeviceIOProcID?
        let ioErr = AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, newAggID, ioQueue) { [weak self] _, inInputData, _, _, _ in
            self?.handleAudioBufferList(inInputData)
        }
        guard ioErr == noErr, let createdIOProc = newIOProcID else {
            throw TapError.createIOProcFailed(ioErr)
        }
        self.ioProcID = createdIOProc

        let startErr = AudioDeviceStart(newAggID, createdIOProc)
        guard startErr == noErr else {
            throw TapError.startDeviceFailed(startErr)
        }
    }

    private func teardownCoreAudioTap() {
        let aggID = aggregateDeviceID
        let procID = ioProcID
        let tID = tapID

        aggregateDeviceID = kAudioObjectUnknown
        ioProcID = nil
        tapID = kAudioObjectUnknown

        if aggID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggID, procID)
                AudioDeviceDestroyIOProcID(aggID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggID)
        }
        if tID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tID)
        }
    }

    private func handleAudioBufferList(_ bufferListPtr: UnsafePointer<AudioBufferList>) {
        let bufList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferListPtr))
        guard let first = bufList.first, first.mData != nil else { return }

        let cap = Self.ringCapacity
        let mask = cap - 1
        let now = Date().timeIntervalSinceReferenceDate
        var peak: Float = 0

        ringLock.lock()
        if bufList.count > 1 {
            let ch1Buf = bufList[1]
            let minBytes = ch1Buf.mData != nil ? min(first.mDataByteSize, ch1Buf.mDataByteSize) : first.mDataByteSize
            let sampleCount = Int(minBytes) / MemoryLayout<Float>.size
            let ch0 = first.mData!.assumingMemoryBound(to: Float.self)
            let ch1 = ch1Buf.mData?.assumingMemoryBound(to: Float.self)

            for i in 0..<sampleCount {
                let raw = ch1 != nil ? 0.5 * (ch0[i] + ch1![i]) : ch0[i]
                let s: Float = raw.isFinite ? raw : 0
                let mag = abs(s)
                if mag > peak { peak = mag }
                ringBuffer[ringWriteIndex] = s
                ringWriteIndex = (ringWriteIndex + 1) & mask
            }
        } else {
            let channels = max(1, Int(first.mNumberChannels))
            let totalFloats = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let frames = totalFloats / channels
            let ptr = first.mData!.assumingMemoryBound(to: Float.self)

            if channels == 1 {
                for i in 0..<frames {
                    let raw = ptr[i]
                    let s: Float = raw.isFinite ? raw : 0
                    let mag = abs(s)
                    if mag > peak { peak = mag }
                    ringBuffer[ringWriteIndex] = s
                    ringWriteIndex = (ringWriteIndex + 1) & mask
                }
            } else {
                for f in 0..<frames {
                    let base = f * channels
                    var sum: Float = 0
                    for c in 0..<channels { sum += ptr[base + c] }
                    let raw = sum / Float(channels)
                    let s: Float = raw.isFinite ? raw : 0
                    let mag = abs(s)
                    if mag > peak { peak = mag }
                    ringBuffer[ringWriteIndex] = s
                    ringWriteIndex = (ringWriteIndex + 1) & mask
                }
            }
        }
        lastSampleTimestamp = now
        var shouldWakeDSP = false
        if peak >= 0.00012 {
            lastActiveAudioTimestamp = now
            if dspIdleSleeping {
                dspIdleSleeping = false
                shouldWakeDSP = true
            }
        }
        ringLock.unlock()

        if shouldWakeDSP {
            dspQueue.async { [weak self] in
                self?.wakeDSPFromIdle()
            }
        }
    }

    // MARK: - Output latency

    func refreshOutputLatencyIfNeeded() {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastLatencyQuery > 1.5 else { return }
        lastLatencyQuery = now
        let latency = Self.queryDefaultOutputLatency()
        stateLock.lock()
        cachedOutputLatency = latency
        stateLock.unlock()
    }

    private static func queryDefaultOutputLatency() -> Double {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return 0 }

        func u32(_ selector: AudioObjectPropertySelector, _ object: AudioObjectID, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput) -> UInt32 {
            var value: UInt32 = 0
            var sz = UInt32(MemoryLayout<UInt32>.size)
            var a = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            return AudioObjectGetPropertyData(object, &a, 0, nil, &sz, &value) == noErr ? value : 0
        }

        var rate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &rateAddr, 0, nil, &rateSize, &rate) == noErr, rate > 1000 else { return 0 }

        var frames = u32(kAudioDevicePropertyLatency, deviceID)
            + u32(kAudioDevicePropertySafetyOffset, deviceID)
            + u32(kAudioDevicePropertyBufferFrameSize, deviceID)

        var streamsAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        if AudioObjectGetPropertyDataSize(deviceID, &streamsAddr, 0, nil, &streamsSize) == noErr, streamsSize >= UInt32(MemoryLayout<AudioStreamID>.size) {
            var streams = [AudioStreamID](repeating: 0, count: Int(streamsSize) / MemoryLayout<AudioStreamID>.size)
            if AudioObjectGetPropertyData(deviceID, &streamsAddr, 0, nil, &streamsSize, &streams) == noErr, let first = streams.first {
                frames += u32(kAudioStreamPropertyLatency, first, scope: kAudioObjectPropertyScopeGlobal)
            }
        }
        return min(0.5, Double(frames) / rate)
    }
}
