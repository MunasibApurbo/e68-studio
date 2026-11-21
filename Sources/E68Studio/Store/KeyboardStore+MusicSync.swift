import Foundation

extension KeyboardStore {
    func cancelMusicSyncAndAudioWithoutRestoring() {
        musicSyncTask?.cancel()
        musicSyncTask = nil
        audioMonitor.stop()
    }

    /// Toggles or updates adjusting the keyboard lighting to system audio output.
    func setMusicSync(_ active: Bool) {
        guard lighting.musicSync != active else { return }
        lighting.musicSync = active
        if active {
            if screenSync {
                disableScreenSyncWithoutRestoring()
            }
            if lighting.effect == 0 {
                lighting.effect = lighting.lastEffect == 0 ? 6 : lighting.lastEffect
            }
            if lighting.brightness == 0 {
                lighting.brightness = 6
            }
            audioMonitor.start()
            startHardwareMusicSync()
            notify("Sound Wave on")
        } else {
            stopHardwareMusicSync()
            audioMonitor.stop()
            notify("Sound Wave off")
        }
    }

    func setMusicMode(_ mode: MusicLightingMode) {
        lighting.musicMode = mode
    }

    func setMusicSensitivity(_ sensitivity: Double) {
        lighting.musicSensitivity = max(0.2, min(sensitivity, 3.0))
    }

    func setMusicColorMode(_ mode: MusicColorMode) {
        lighting.musicColorMode = mode
        if mode == .custom && lighting.musicSync && isReady {
            let via = self.via
            let h = lighting.hue, s = lighting.saturation
            Task {
                _ = try? await self.hid.run {
                    try via.setLighting(.color, [h, s], timeout: 0.12, attempts: 1)
                }
            }
        }
    }

    /// Trims when the lights fire relative to the sound (milliseconds, + = later).
    func setMusicSyncOffset(_ ms: Int) {
        lighting.musicSyncOffsetMs = max(-150, min(ms, 300))
    }

    func startHardwareMusicSync() {
        musicSyncTask?.cancel()
        musicSyncTask = nil
        guard isReady else { return }
        let via = self.via
        musicSyncTask = Task { [weak self] in
            guard let self else { return }
            let initHue = self.lighting.hue
            let initSat = self.lighting.saturation
            // Static mode (effect 6) so the board shows exactly the colour/brightness we stream.
            _ = try? await self.hid.run {
                try via.setLighting(.effect, [6])
                try via.setLighting(.color, [initHue, initSat])
            }
            var engine = MusicLightEngine()
            var lastRaw = -1
            var lastHue = -1
            var lastSat = -1
            var lastKeepAlive = Date.distantPast
            // Round-trip time of one HID write, learnt live; it decides how far ahead of the
            // screen the board must be fed.
            var hidLatency: Double = 0.012
            let clock = ContinuousClock()

            while !Task.isCancelled {
                let frameStart = clock.now
                guard self.lighting.musicSync else { break }
                guard self.isReady, self.lightingPump == nil else {
                    try? await Task.sleep(for: .milliseconds(90))
                    continue
                }
                let state = self.lighting
                let delay = MusicLightEngine.delay(
                    outputLatency: self.audioMonitor.outputLatency(),
                    userOffsetMs: state.musicSyncOffsetMs,
                    consumerLatency: hidLatency
                )
                let snap = self.audioMonitor.snapshot(delay: delay)
                let now = Date()
                let frame = engine.step(snap, settings: .init(state), now: now.timeIntervalSinceReferenceDate)

                let maxRaw = Int(LightingState.rawBrightness(level: max(1, state.brightness)))
                let raw = Int((frame.level * Float(maxRaw)).rounded())
                let hueByte = Int((frame.hue * 255).rounded()) & 0xFF
                let satByte = min(255, max(0, Int((frame.saturation * 255).rounded())))

                // Hue wraps, so compare on the circle.
                let hueDelta = lastHue < 0 ? 255 : min(abs(hueByte - lastHue), 256 - abs(hueByte - lastHue))
                let keepAlive = now.timeIntervalSince(lastKeepAlive) > 1.0
                let sendBright = keepAlive || abs(raw - lastRaw) >= 2 || (raw == 0) != (lastRaw == 0)
                let sendColor = keepAlive || hueDelta >= 2 || abs(satByte - lastSat) >= 3

                if sendBright || sendColor {
                    let b = UInt8(max(0, min(255, raw)))
                    let h = UInt8(hueByte), sa = UInt8(satByte)
                    // Brightness first: it carries the beat, colour can trail by a few ms.
                    let t0 = clock.now
                    let ok = (try? await self.hid.run { () throws -> Void in
                        if sendBright { try via.setLighting(.brightness, [b], timeout: 0.05, attempts: 1) }
                        if sendColor { try via.setLighting(.color, [h, sa], timeout: 0.05, attempts: 1) }
                    }) != nil
                    if ok {
                        let writes = Double((sendBright ? 1 : 0) + (sendColor ? 1 : 0))
                        let took = t0.duration(to: clock.now)
                        let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
                        hidLatency = hidLatency * 0.9 + min(0.08, seconds / max(1, writes)) * 0.1
                        if sendBright { lastRaw = raw }
                        if sendColor { lastHue = hueByte; lastSat = satByte }
                        if keepAlive { lastKeepAlive = now }
                    }
                }

                let elapsed = frameStart.duration(to: clock.now)
                let idle = !snap.isPlaying && frame.energy < 0.005 && frame.flash == 0
                let targetFrame = Duration.milliseconds(idle ? 80 : 16)
                if elapsed < targetFrame {
                    try? await Task.sleep(for: targetFrame - elapsed)
                } else {
                    try? await Task.sleep(for: .milliseconds(3))
                }
            }
            if !Task.isCancelled {
                self.musicSyncTask = nil
            }
        }
    }

    /// Stops audio capture, Bluetooth monitoring, flushes telemetry, and commits any pending
    /// keyboard lighting or macro changes to EEPROM before the app exits.
    func shutdown() {
        let connectedReady = isReady
        let hadLiveSync = screenSync || lighting.musicSync
        let pendingLighting = lightingPending
        let needsLightingSave = lightingNeedsSave || lightingPump != nil || hadLiveSync
        let wasPulsingReactive = isPulsingReactiveHardware
        let currentLighting = lighting
        let dirtyMacroImage: [UInt8]? = (connectedReady && macrosDirty && macrosFit) ? macroImage : nil
        let macroBufSize = macroBufferSize

        telemetryPublishTask?.cancel()
        telemetryPublishTask = nil
        telemetrySaveTask?.cancel()
        telemetrySaveTask = nil
        wpmDecayTask?.cancel()
        wpmDecayTask = nil
        flushTelemetryToDefaults()
        if let observer = telemetryResignObserver {
            NotificationCenter.default.removeObserver(observer)
            telemetryResignObserver = nil
        }
        setKeyTestActive(false)
        setLightingWatch(false)
        lightingPump?.cancel()
        lightingPump = nil
        lightingPending = []
        lightingNeedsSave = false
        reactiveHardwareTask?.cancel()
        reactiveHardwareTask = nil
        reactiveHardwareGeneration &+= 1
        isPulsingReactiveHardware = false
        for task in rawMatrixTasks.values { task.cancel() }
        rawMatrixTasks = [:]
        LiveMirror.shared.stop()
        TextExpander.shared.stop()
        MouseRemapper.shared.stop()
        MouseStore.shared.stop()
        keyTap.stop()
        bluetooth.stop()

        if screenSync {
            disableScreenSyncWithoutRestoring()
        }
        if lighting.musicSync {
            lighting.musicSync = false
            musicSyncTask?.cancel()
            musicSyncTask = nil
        }
        audioMonitor.stop()

        guard connectedReady else { return }

        let valuesToWrite: Set<VIA.LightingValue> = {
            var set: Set<VIA.LightingValue> = hadLiveSync ? [.effect, .brightness, .speed, .color] : pendingLighting
            if wasPulsingReactive {
                set.insert(.color)
            }
            return set
        }()
        guard !valuesToWrite.isEmpty || needsLightingSave || dirtyMacroImage != nil else { return }
        let via = self.via
        let timeout: TimeInterval = dirtyMacroImage != nil ? 2.0 : 0.8
        // Runs synchronously on the serial HID I/O queue, so any in-flight keymap/macro writes
        // also finish before this barrier returns.
        hid.runSynchronously({
            if !valuesToWrite.isEmpty {
                if valuesToWrite.contains(.effect) {
                    try via.setLighting(.effect, [UInt8(currentLighting.effect)], timeout: 0.15, attempts: 1)
                }
                if valuesToWrite.contains(.brightness) {
                    try via.setLighting(.brightness, [LightingState.rawBrightness(level: currentLighting.brightness)], timeout: 0.15, attempts: 1)
                }
                if valuesToWrite.contains(.speed) {
                    try via.setLighting(.speed, [LightingState.rawSpeed(level: currentLighting.speed)], timeout: 0.15, attempts: 1)
                }
                if valuesToWrite.contains(.color) {
                    try via.setLighting(.color, [currentLighting.hue, currentLighting.saturation], timeout: 0.15, attempts: 1)
                }
            }
            if needsLightingSave {
                try via.saveLighting()
            }
            if let image = dirtyMacroImage {
                try via.writeMacroBuffer(image, bufferSize: macroBufSize)
            }
        }, timeout: timeout)
    }

    func stopHardwareMusicSync() {
        musicSyncTask?.cancel()
        musicSyncTask = nil
        restoreStandardLighting()
    }
}
