import Foundation
import Accelerate
import os

extension AudioMonitor {
    // MARK: - DSP & 16-Band FFT

    func rebuildBandBinRanges(sampleRate: Float) {
        let n = Self.fftSize
        let half = n / 2
        let binHz = sampleRate / Float(n)
        let minFreq: Float = 42.0
        let maxFreq: Float = min(14500.0, sampleRate * 0.45)

        var ranges: [(Int, Int)] = []
        ranges.reserveCapacity(16)

        for band in 0..<16 {
            let t0 = Float(band) / 16.0
            let t1 = Float(band + 1) / 16.0
            let f0 = minFreq * powf(maxFreq / minFreq, t0)
            let f1 = minFreq * powf(maxFreq / minFreq, t1)

            let b0 = max(1, min(half - 1, Int(floorf(f0 / binHz))))
            let b1 = max(b0, min(half - 1, Int(ceilf(f1 / binHz))))
            ranges.append((b0, b1))
        }
        bandBinRanges = ranges

        // Butterworth low-pass at 150 Hz for the time-domain kick detector (RBJ cookbook).
        let w0 = 2 * Float.pi * 150 / sampleRate
        let alpha = sinf(w0) / (2 * 0.7071)
        let cosw = cosf(w0)
        let a0 = 1 + alpha
        lpB = ((1 - cosw) / 2 / a0, (1 - cosw) / a0, (1 - cosw) / 2 / a0)
        lpA = (-2 * cosw / a0, (1 - alpha) / a0)

        let subB0 = max(1, min(half - 1, Int(ceilf(32.0 / binHz))))
        let subB1 = max(subB0, min(half - 1, Int(floorf(135.0 / binHz))))
        subBassBinRange = (subB0, subB1)

        let vocB0 = max(subB1 + 1, min(half - 1, Int(ceilf(220.0 / binHz))))
        let vocB1 = max(vocB0, min(half - 1, Int(floorf(2600.0 / binHz))))
        voiceBinRange = (vocB0, vocB1)
    }

    func resetDSPState() {
        ringLock.lock()
        for i in ringBuffer.indices { ringBuffer[i] = 0 }
        ringWriteIndex = 0
        lastSampleTimestamp = 0
        lastActiveAudioTimestamp = 0
        dspIdleSleeping = false
        ringLock.unlock()

        stateLock.lock()
        history.removeAll()
        historyIndex = 0
        stateLock.unlock()

        dspQueue.async { [weak self] in
            guard let self else { return }
            self.smoothedBands = [Float](repeating: 0, count: 16)
            self.prevBands = [Float](repeating: 0, count: 16)
            self.smoothedWaveform = [Float](repeating: 0, count: 32)
            self.agcPeak = 0.03
            self.loudnessRef = 0.02
            self.waveformPeak = 0.05
            self.smoothWaveAmp = 0
            self.smoothColorShift = 0
            self.bassPeak = 0.03
            self.kickHistory = 0.008
            self.fluxHistory = 0.06
            self.smoothBass = 0
            self.beatEnergy = 0
            self.lastBeatTime = 0
            self.lastFrameTime = 0
            self.lastProcessedWrite = 0
            self.lpX = (0, 0)
            self.lpY = (0, 0)
            self.lowFast = 0
            self.lowSlow = 0.00001
            self.prevLowFast = 0
            self.lastLatencyQuery = 0
            self.hasSettledIdle = false
            self.lastIdleCover = CoverColorPalette()
        }
    }

    func startDSPTimer() {
        let timer = DispatchSource.makeTimerSource(queue: dspQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2)) // ~60 FPS matched to SceneKit
        timer.setEventHandler { [weak self] in
            self?.processFFTFrame()
        }
        stateLock.lock()
        guard isRunning else {
            stateLock.unlock()
            timer.setEventHandler {}
            timer.resume()
            timer.cancel()
            return
        }
        let oldTimer = dspTimer
        dspTimer = timer
        stateLock.unlock()
        oldTimer?.cancel()
        timer.resume()
    }

    func wakeDSPFromIdle() {
        stateLock.lock()
        let running = isRunning
        let timer = dspTimer
        stateLock.unlock()
        guard running, let timer else { return }
        hasSettledIdle = false
        timer.schedule(deadline: .now() + .milliseconds(16), repeating: .milliseconds(16), leeway: .milliseconds(2))
        processFFTFrame()
    }

    private func processFFTFrame() {
        stateLock.lock()
        let running = isRunning
        let timer = dspTimer
        stateLock.unlock()
        guard running, let fftSetup else { return }

        if hasSettledIdle {
            ringLock.lock()
            let sleeping = dspIdleSleeping
            ringLock.unlock()
            if sleeping {
                let cover = coverWatcher.currentPalette()
                if cover != lastIdleCover {
                    lastIdleCover = cover
                    publishSnapshot(amplitude: 0, peak: 0, bass: 0, mid: 0, treble: 0, beatDetected: false, cover: cover, isPlaying: false)
                }
                return
            }
            hasSettledIdle = false
            timer?.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        }

        let n = Self.fftSize
        let cap = Self.ringCapacity
        let mask = cap - 1

        ringLock.lock()
        let writeIdx = ringWriteIndex
        let nowRef = Date().timeIntervalSinceReferenceDate
        let sampleAge = nowRef - lastSampleTimestamp
        let activeAge = nowRef - lastActiveAudioTimestamp
        let tailStart = (writeIdx - n + cap) & mask
        if tailStart + n <= cap {
            dspSamples.replaceSubrange(0..<n, with: ringBuffer[tailStart..<(tailStart + n)])
        } else {
            let firstPart = cap - tailStart
            dspSamples.replaceSubrange(0..<firstPart, with: ringBuffer[tailStart..<cap])
            dspSamples.replaceSubrange(firstPart..<n, with: ringBuffer[0..<(n - firstPart)])
        }
        // Samples that arrived since the previous tick (newest half of the ring at most).
        let newCount = min(cap / 2, (writeIdx - lastProcessedWrite + cap) & mask)
        for i in 0..<newCount {
            dspFresh[i] = ringBuffer[(writeIdx - newCount + i + cap) & mask]
        }
        lastProcessedWrite = writeIdx
        ringLock.unlock()

        refreshOutputLatencyIfNeeded()
        let kickNow = runKickFilter(count: newCount)

        let now = Date().timeIntervalSinceReferenceDate
        let dt = lastFrameTime > 0 ? Float(min(0.08, max(0.004, now - lastFrameTime))) : 0.016
        lastFrameTime = now

        var rms: Float = 0
        vDSP_rmsqv(dspSamples, 1, &rms, vDSP_Length(n))

        let cover = coverWatcher.currentPalette()

        if sampleAge > 0.25 || rms < 0.00012 {
            let decay = expf(-dt / 0.08)
            for i in 0..<16 {
                smoothedBands[i] *= decay
                if smoothedBands[i] < 0.003 { smoothedBands[i] = 0 }
                prevBands[i] *= decay
            }
            for i in 0..<32 {
                smoothedWaveform[i] *= decay
                if abs(smoothedWaveform[i]) < 0.003 { smoothedWaveform[i] = 0 }
            }
            smoothWaveAmp *= decay
            if smoothWaveAmp < 0.003 { smoothWaveAmp = 0 }
            smoothColorShift *= expf(-dt / 0.12)
            if smoothColorShift < 0.003 { smoothColorShift = 0 }
            smoothBass *= decay
            if smoothBass < 0.003 { smoothBass = 0 }
            beatEnergy *= expf(-dt / 0.07)
            if beatEnergy < 0.003 { beatEnergy = 0 }
            agcPeak = max(0.008, agcPeak * expf(-dt / 1.5))
            loudnessRef = max(0.005, loudnessRef * expf(-dt / 2.0))
            waveformPeak = max(0.01, waveformPeak * expf(-dt / 1.5))
            bassPeak = max(0.006, bassPeak * expf(-dt / 1.8))

            publishSnapshot(
                amplitude: smoothWaveAmp,
                peak: smoothedBands.max() ?? 0,
                bass: smoothBass,
                mid: (smoothedBands[4] + smoothedBands[5] + smoothedBands[6] + smoothedBands[7] + smoothedBands[8] + smoothedBands[9]) / 6.0,
                treble: (smoothedBands[10] + smoothedBands[11] + smoothedBands[12] + smoothedBands[13] + smoothedBands[14] + smoothedBands[15]) / 6.0,
                beatDetected: false,
                cover: cover,
                isPlaying: false
            )

            let fullyQuiet = smoothWaveAmp == 0 && smoothBass == 0 && smoothColorShift == 0 && beatEnergy == 0
                && smoothedBands.allSatisfy { $0 == 0 } && smoothedWaveform.allSatisfy { $0 == 0 }
            if fullyQuiet && activeAge > 0.45 {
                let checkTime = Date().timeIntervalSinceReferenceDate
                ringLock.lock()
                let stillSilent = checkTime - lastActiveAudioTimestamp > 0.45
                if stillSilent {
                    dspIdleSleeping = true
                }
                ringLock.unlock()
                if stillSilent {
                    hasSettledIdle = true
                    lastIdleCover = cover
                    timer?.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500), leeway: .milliseconds(100))
                }
            }
            return
        }

        // Extract real zero-crossing-aligned 32-point waveform from the latest PCM window before windowing
        let waveWindow = min(n, 1024)
        let searchStart = n - waveWindow
        var alignedStart = searchStart
        let searchEnd = min(n - 32, searchStart + 192)
        if searchEnd > searchStart + 1 {
            for idx in (searchStart + 1)..<searchEnd {
                if dspSamples[idx - 1] <= 0 && dspSamples[idx] > 0 {
                    alignedStart = idx
                    break
                }
            }
        }
        let span = max(32, n - alignedStart)
        let bucketSize = max(1, span / 32)
        var frameWavePeak: Float = 0.001
        for b in 0..<32 {
            let s0 = alignedStart + (b * span) / 32
            let s1 = min(n, s0 + bucketSize)
            var maxSigned: Float = 0
            for idx in s0..<s1 {
                let v = dspSamples[idx]
                if abs(v) > abs(maxSigned) { maxSigned = v }
            }
            dspRawWave[b] = maxSigned
            let mag = abs(maxSigned)
            if mag > frameWavePeak { frameWavePeak = mag }
        }
        if frameWavePeak > waveformPeak {
            waveformPeak = waveformPeak * 0.40 + frameWavePeak * 0.60
        } else {
            waveformPeak = max(0.008, waveformPeak * expf(-dt / 0.85))
        }
        let waveNorm = max(0.008, waveformPeak * 1.1)
        let waveAttack = 1.0 - expf(-dt / 0.022)
        for b in 0..<32 {
            let target = max(-1.0, min(1.0, dspRawWave[b] / waveNorm))
            smoothedWaveform[b] += (target - smoothedWaveform[b]) * waveAttack
        }

        // Apply Hann window and run real FFT
        dspSamples.withUnsafeMutableBufferPointer { buf in
            vDSP_vmul(buf.baseAddress!, 1, hannWindow, 1, buf.baseAddress!, 1, vDSP_Length(n))
        }

        let half = n / 2
        realBuffer.withUnsafeMutableBufferPointer { rBuf in
            imagBuffer.withUnsafeMutableBufferPointer { iBuf in
                var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                dspSamples.withUnsafeBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // Convert raw power into 16 perceptual logarithmic bands with pink-noise / Fletcher-Munson tilt
        var frameMax: Float = 0.0001
        let normScale = Float(n) * 0.5

        for i in 0..<16 {
            let (b0, b1) = bandBinRanges[i]
            var sumSq: Float = 0
            for b in b0...b1 {
                sumSq += magnitudes[b]
            }
            let avgPower = sumSq / Float(b1 - b0 + 1)
            let tilt: Float = 1.0 + log2f(1.0 + Float(i)) * 0.55
            let mag = (sqrtf(max(0, avgPower)) / normScale) * tilt
            dspRawBands[i] = mag
            if mag > frameMax { frameMax = mag }
        }

        if frameMax > agcPeak {
            agcPeak = agcPeak * 0.42 + frameMax * 0.58
        } else {
            agcPeak = max(0.006, agcPeak * expf(-dt / 0.85))
        }
        let normDiv = max(0.006, agcPeak * 1.08)
        let bandAttack = 1.0 - expf(-dt / 0.014)
        let bandRelease = 1.0 - expf(-dt / 0.075)

        for i in 0..<16 {
            let normalized = min(1.0, powf(dspRawBands[i] / normDiv, 0.72))
            let coeff = normalized > smoothedBands[i] ? bandAttack : bandRelease
            smoothedBands[i] += (normalized - smoothedBands[i]) * coeff
        }

        let mid = (smoothedBands[4] + smoothedBands[5] + smoothedBands[6] + smoothedBands[7] + smoothedBands[8] + smoothedBands[9]) / 6.0
        let treble = (smoothedBands[10] + smoothedBands[11] + smoothedBands[12] + smoothedBands[13] + smoothedBands[14] + smoothedBands[15]) / 6.0

        // Volume-independent kick (32–135 Hz) & multi-band spectral flux transient detection
        var subSumSq: Float = 0
        for b in subBassBinRange.start...subBassBinRange.end { subSumSq += magnitudes[b] }
        var vocSumSq: Float = 0
        for b in voiceBinRange.start...voiceBinRange.end { vocSumSq += magnitudes[b] }

        let subBassAmp = sqrtf(max(0, subSumSq)) / normScale
        let voiceAmp = sqrtf(max(0, vocSumSq)) / normScale

        @inline(__always)
        func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
            let t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
            return t * t * (3.0 - 2.0 * t)
        }

        let bassToVoiceRatio = subBassAmp / (voiceAmp + 0.002)
        let bassGate = smoothstep(0.0015, 0.006, subBassAmp) * smoothstep(0.10, 0.28, bassToVoiceRatio)

        let gatedBass = subBassAmp * bassGate
        if gatedBass > bassPeak {
            bassPeak = bassPeak * 0.35 + gatedBass * 0.65
        } else {
            bassPeak = max(0.004, bassPeak * expf(-dt / 1.1))
        }

        let rawBassNormalized = min(1.0, gatedBass / max(0.004, bassPeak))
        let bassDecay = expf(-dt / 0.095)
        smoothBass = max(rawBassNormalized, smoothBass * bassDecay)

        // Spectral balance & onset flux across all 16 bands
        let lowEnergy = (smoothedBands[0] + smoothedBands[1] + smoothedBands[2] + smoothedBands[3]) / 4.0
        var weightedIdx: Float = 0
        var totalEnergy: Float = 0.0001
        var fluxSum: Float = 0
        var transientFlux: Float = 0
        for i in 0..<16 {
            weightedIdx += Float(i) * smoothedBands[i]
            totalEnergy += smoothedBands[i]
            let delta = max(0, smoothedBands[i] - prevBands[i])
            fluxSum += delta
            if i <= 9 { transientFlux += delta * (i <= 3 ? 1.2 : 0.9) }
            prevBands[i] = smoothedBands[i]
        }
        let centroid = (weightedIdx / totalEnergy) / 15.0
        let spectralFlux = min(1.0, fluxSum * 0.95)
        let onsetFlux = min(1.0, transientFlux * 0.75)

        let cooldownPassed = (now - lastBeatTime) > 0.12
        let kickOnset = bassGate > 0.25
            && rawBassNormalized > 0.22
            && subBassAmp > max(0.0025, kickHistory * 1.24)
        // The time-domain detector fires ~20 ms earlier than the FFT one; require some low-end
        // dominance so vocals and hats can't trip it.
        let fastKickOnset = kickNow && bassGate > 0.12
        let snareTransientOnset = onsetFlux > max(0.16, fluxHistory * 1.65)
            && rms > 0.0005
        let isBeat = cooldownPassed && (fastKickOnset || kickOnset || snareTransientOnset)

        kickHistory = kickHistory * 0.87 + subBassAmp * 0.13
        fluxHistory = fluxHistory * 0.88 + onsetFlux * 0.12

        if isBeat {
            let kickRatio = lowFast / max(0.00001, lowSlow)
            let hitStrength: Float
            if fastKickOnset || kickOnset {
                hitStrength = max(0.76, max(rawBassNormalized, min(1.0, (kickRatio - 1.0) * 0.45)))
            } else {
                hitStrength = max(0.62, min(1.0, onsetFlux * 1.35))
            }
            beatEnergy = min(1.0, hitStrength)
            lastBeatTime = now
            beatCount &+= 1
            lastBeatStrength = beatEnergy
        } else {
            beatEnergy = max(0, beatEnergy * expf(-dt / 0.09))
        }

        // Dynamic amplitude envelope preserving contrast on loud sections while scaling quiet playback
        if rms > loudnessRef {
            loudnessRef = loudnessRef * 0.88 + rms * 0.12
        } else {
            loudnessRef = max(0.0035, loudnessRef * expf(-dt / 1.4))
        }
        let rmsNormalized = tanhf((rms / max(0.0035, loudnessRef * 0.92)) * 0.85)
        let combinedWave = min(1.0, max(0, rmsNormalized * 0.68 + spectralFlux * 0.34 + beatEnergy * 0.22))
        let expandedWave = powf(combinedWave, 1.22)
        let ampAttack = 1.0 - expf(-dt / 0.016)
        let ampRelease = 1.0 - expf(-dt / 0.075)
        let ampCoeff = expandedWave > smoothWaveAmp ? ampAttack : ampRelease
        smoothWaveAmp += (expandedWave - smoothWaveAmp) * ampCoeff

        let tonalBright = (treble * 1.25 + mid * 0.55) / max(0.06, lowEnergy + mid + treble)
        let targetColorShift = min(1.0, max(0, tonalBright * 0.68 + spectralFlux * 0.45 + beatEnergy * 0.25))
        smoothColorShift += (targetColorShift - smoothColorShift) * (1.0 - expf(-dt / 0.065))

        let targetHue = (0.04 + centroid * 0.78).truncatingRemainder(dividingBy: 1.0)
        let hueDiff = HueMath.shortestDelta(from: smoothHue, to: targetHue)
        smoothHue = HueMath.wrap(smoothHue + hueDiff * (1.0 - expf(-dt / 0.11)))

        publishSnapshot(
            amplitude: smoothWaveAmp,
            peak: smoothedBands.max() ?? smoothWaveAmp,
            bass: smoothBass,
            mid: mid,
            treble: treble,
            beatDetected: isBeat,
            cover: cover,
            isPlaying: true
        )
    }

    private func publishSnapshot(
        amplitude: Float,
        peak: Float,
        bass: Float,
        mid: Float,
        treble: Float,
        beatDetected: Bool,
        cover: CoverColorPalette,
        isPlaying: Bool
    ) {
        let snap = AudioSnapshot(
            amplitude: amplitude,
            peak: peak,
            bass: bass,
            mid: mid,
            treble: treble,
            bands: smoothedBands,
            waveform: smoothedWaveform,
            beat: beatEnergy,
            beatDetected: beatDetected,
            beatCount: beatCount,
            beatStrength: lastBeatStrength,
            dominantHue: smoothHue,
            coverHue: cover.primaryHue,
            coverSaturation: cover.primarySaturation,
            secondaryCoverHue: cover.secondaryHue,
            secondaryCoverSaturation: cover.secondarySaturation,
            hasCoverColor: cover.isAvailable,
            colorShift: smoothColorShift,
            isPlaying: isPlaying
        )
        let stamp = Date().timeIntervalSinceReferenceDate
        stateLock.lock()
        currentSnapshot = snap
        if history.count < Self.historyCapacity {
            history.append((stamp, snap))
        } else {
            history[historyIndex] = (stamp, snap)
        }
        historyIndex = (historyIndex + 1) % Self.historyCapacity
        stateLock.unlock()
    }

    // MARK: - Time-domain kick detector

    /// Low-passes the fresh samples and returns whether a kick onset began during them.
    private func runKickFilter(count: Int) -> Bool {
        guard count > 0 else { return false }
        let (b0, b1, b2) = lpB
        let (a1, a2) = lpA
        var (x1, x2) = lpX
        var (y1, y2) = lpY
        // Energy of the newest ~5 ms of low-passed signal.
        let windowCount = max(1, min(count, Int(sampleRate * 0.005)))
        let windowStart = count - windowCount
        var energy: Float = 0
        for i in 0..<count {
            let x = dspFresh[i]
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            if i >= windowStart { energy += y * y }
        }
        if !y1.isFinite || !y2.isFinite { y1 = 0; y2 = 0 }
        lpX = (x1, x2)
        lpY = (y1, y2)

        prevLowFast = lowFast
        lowFast = energy / Float(windowCount)
        let frameSeconds = Float(count) / sampleRate
        // Slow reference follows the low-end level over ~300 ms.
        lowSlow += (lowFast - lowSlow) * (1 - expf(-frameSeconds / 0.30))
        lowSlow = max(lowSlow, 0.0000004)

        return lowFast > lowSlow * 1.9
            && lowFast > prevLowFast * 1.25
            && lowFast > 0.0000012
    }

}
