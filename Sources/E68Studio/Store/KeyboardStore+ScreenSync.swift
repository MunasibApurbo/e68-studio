import AppKit
import Foundation

/// Screen Glow: the backlight takes the colour of what is on screen, edges first.
extension KeyboardStore {
    func setupScreenSamplerCallbacks() {
        screenSampler.onUnexpectedStop = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.screenSync else { return }
                self.disableScreenSyncWithoutRestoring()
                self.restoreStandardLighting()
                self.notify("Screen Glow stopped")
            }
        }
    }

    var screenSyncFollowsBrightness: Bool {
        get { defaults.object(forKey: "screenSync.followBrightness") as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "screenSync.followBrightness")
        }
    }

    func disableScreenSyncWithoutRestoring() {
        screenSyncStartGeneration &+= 1
        screenSync = false
        screenSyncTask?.cancel()
        screenSyncTask = nil
        screenSampler.stop()
    }

    func setScreenSync(_ active: Bool) {
        guard active != screenSync else { return }
        guard active else {
            disableScreenSyncWithoutRestoring()
            restoreStandardLighting()
            notify("Screen Glow off")
            return
        }
        guard ScreenColorSampler.hasPermission else {
            ScreenColorSampler.requestPermission()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            notify("Allow E68 Studio under Screen & System Audio Recording, then turn Screen Glow on again.", isError: true)
            return
        }
        if lighting.musicSync {
            cancelMusicSyncAndAudioWithoutRestoring()
            lighting.musicSync = false
        }
        screenSyncStartGeneration &+= 1
        let gen = screenSyncStartGeneration
        screenSync = true
        Task {
            do {
                try await screenSampler.start()
                guard gen == self.screenSyncStartGeneration, self.screenSync else {
                    screenSampler.stop()
                    return
                }
                var next = lighting
                if next.effect == 0 {
                    next.effect = next.lastEffect == 0 ? 6 : next.lastEffect
                }
                if next.brightness == 0 {
                    next.brightness = 6
                }
                if next != lighting { lighting = next }
                startScreenSyncLoop()
                notify("Screen Glow on")
            } catch {
                guard gen == self.screenSyncStartGeneration else { return }
                screenSync = false
                notify("Screen Glow could not start. \(error.localizedDescription)", isError: true)
            }
        }
    }

    func startScreenSyncLoop() {
        screenSyncTask?.cancel()
        screenSyncTask = nil
        guard isReady, screenSync else { return }
        let via = self.via
        let sampler = self.screenSampler
        screenSyncTask = Task { [weak self] in
            guard let self else { return }
            _ = try? await self.hid.run { try via.setLighting(.effect, [6]) }

            var hue = sampler.current.hue
            var sat = sampler.current.saturation
            var level = sampler.current.brightness
            var lastHue = -1, lastSat = -1, lastRaw = -1
            var lastKeepAlive = Date.distantPast

            while !Task.isCancelled {
                guard self.screenSync else { break }
                guard self.isReady, self.lightingPump == nil else {
                    try? await Task.sleep(for: .milliseconds(120))
                    continue
                }
                let s = sampler.current
                // Ease toward the target so scene cuts glide instead of strobing; hue goes the short way round.
                var dh = s.hue - hue
                if dh > 0.5 { dh -= 1 } else if dh < -0.5 { dh += 1 }
                hue = (hue + dh * 0.22).truncatingRemainder(dividingBy: 1)
                if hue < 0 { hue += 1 }
                sat += (s.saturation - sat) * 0.22
                level += (s.brightness - level) * 0.18

                let maxRaw = Float(LightingState.rawBrightness(level: max(1, self.lighting.brightness)))
                let scale: Float = self.screenSyncFollowsBrightness ? min(1, 0.12 + level * 1.4) : 1
                let raw = Int((maxRaw * scale).rounded())
                let hueByte = Int((hue * 255).rounded()) & 0xFF
                let satByte = min(255, max(0, Int((sat * 255).rounded())))

                let now = Date()
                let keepAlive = now.timeIntervalSince(lastKeepAlive) > 1.5
                let hueDelta = lastHue < 0 ? 255 : min(abs(hueByte - lastHue), 256 - abs(hueByte - lastHue))
                let sendColor = keepAlive || hueDelta >= 2 || abs(satByte - lastSat) >= 3
                let sendBright = keepAlive || abs(raw - lastRaw) >= 3

                if sendColor || sendBright {
                    let h = UInt8(hueByte), sa = UInt8(satByte), b = UInt8(max(0, min(255, raw)))
                    let ok = (try? await self.hid.run { () throws -> Void in
                        if sendColor { try via.setLighting(.color, [h, sa], timeout: 0.05, attempts: 1) }
                        if sendBright { try via.setLighting(.brightness, [b], timeout: 0.05, attempts: 1) }
                    }) != nil
                    if ok {
                        if sendColor {
                            lastHue = hueByte
                            lastSat = satByte
                        }
                        if sendBright { lastRaw = raw }
                        if keepAlive { lastKeepAlive = now }
                    }
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
            if !Task.isCancelled {
                self.screenSyncTask = nil
            }
        }
    }

    /// Puts the board back on the user's own effect, brightness, speed and colour,
    /// and commits to EEPROM so the restored lighting persists across power cycles.
    func restoreStandardLighting(synchronous: Bool = false, saveToEEPROM: Bool = true) {
        guard isReady else { return }
        let via = self.via
        let state = self.lighting
        let shouldSave = saveToEEPROM || lightingNeedsSave
        if synchronous {
            lightingNeedsSave = false
            hid.runSynchronously({
                try via.setLighting(.effect, [UInt8(state.effect)])
                try via.setLighting(.brightness, [LightingState.rawBrightness(level: state.brightness)])
                try via.setLighting(.speed, [LightingState.rawSpeed(level: state.speed)])
                try via.setLighting(.color, [state.hue, state.saturation])
                if shouldSave {
                    try via.saveLighting()
                }
            }, timeout: 1.2)
            return
        }
        isRestoringLighting = true
        Task { [weak self] in
            defer { self?.isRestoringLighting = false }
            guard let self else { return }
            do {
                try await self.hid.run {
                    try via.setLighting(.effect, [UInt8(state.effect)])
                    try via.setLighting(.brightness, [LightingState.rawBrightness(level: state.brightness)])
                    try via.setLighting(.speed, [LightingState.rawSpeed(level: state.speed)])
                    try via.setLighting(.color, [state.hue, state.saturation])
                    if shouldSave {
                        try via.saveLighting()
                    }
                }
                if shouldSave && self.lightingPending.isEmpty {
                    self.lightingNeedsSave = false
                }
            } catch {
                if shouldSave {
                    self.lightingNeedsSave = true
                }
            }
        }
    }
}
