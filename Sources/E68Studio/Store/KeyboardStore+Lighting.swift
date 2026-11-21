import Foundation

extension KeyboardStore {

    func setBacklightOn(_ on: Bool) {
        if !on {
            var hadLiveSync = false
            if screenSync {
                disableScreenSyncWithoutRestoring()
                hadLiveSync = true
            }
            if lighting.musicSync {
                cancelMusicSyncAndAudioWithoutRestoring()
                lighting.musicSync = false
                hadLiveSync = true
            }
            if lighting.effect == 0 {
                if hadLiveSync {
                    queueLighting([.effect, .brightness, .speed, .color])
                }
                return
            }
        }
        updateLighting([.effect]) { $0.effect = on ? ($0.lastEffect == 0 ? 6 : $0.lastEffect) : 0 }
    }

    func updateLighting(_ changed: Set<VIA.LightingValue>, _ mutate: (inout LightingState) -> Void) {
        var next = lighting
        mutate(&next)
        guard next != lighting else { return }
        if next.effect != 0 { next.lastEffect = next.effect }
        var values = changed
        if changed.contains(.effect) {
            if screenSync {
                disableScreenSyncWithoutRestoring()
                values.formUnion([.brightness, .speed, .color])
            }
            if next.musicSync {
                next.musicSync = false
                cancelMusicSyncAndAudioWithoutRestoring()
                values.formUnion([.brightness, .speed, .color])
            }
        }
        lighting = next
        if (next.musicSync || screenSync) && !changed.contains(.effect) {
            lightingNeedsSave = true
            return
        }
        queueLighting(values)
    }

    /// Samples the current macOS desktop wallpaper and applies its dominant hue & saturation to the keyboard.
    func applyWallpaperColor() {
        Task { @MainActor [weak self] in
            let wp = await WallpaperColorSampler.shared.refreshAndFetch()
            guard let self else { return }
            let h = UInt8(min(255, max(0, Int((wp.hue * 255).rounded()))))
            let s = UInt8(min(255, max(0, Int((wp.saturation * 255).rounded()))))
            self.updateLighting([.color]) {
                $0.hue = h
                $0.saturation = s
            }
            self.notify("Colour set from your wallpaper")
        }
    }

    /// Sends a brief reactive color shift to the hardware backlight when Reactive Key Ripples is enabled.
    func pulseReactiveKeyOnHardware(slotIndex: Int) {
        guard lighting.reactiveTypingRipple, lighting.effect != 0, isReady, !lighting.musicSync, !screenSync, lightingPump == nil else { return }
        reactiveHardwareTask?.cancel()
        reactiveHardwareGeneration &+= 1
        let gen = reactiveHardwareGeneration
        let via = self.via
        let baseHue = Int(lighting.hue)
        let shiftedHue = UInt8((baseHue + (slotIndex * 19) % 64) & 0xFF)
        let baseSat = lighting.saturation
        let restHue = lighting.hue
        isPulsingReactiveHardware = true
        reactiveHardwareTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.reactiveHardwareGeneration == gen {
                    self.isPulsingReactiveHardware = false
                }
            }
            _ = try? await self.hid.run {
                try via.setLighting(.color, [shiftedHue, baseSat], timeout: 0.05, attempts: 1)
            }
            try? await Task.sleep(for: .milliseconds(130))
            guard !Task.isCancelled, self.reactiveHardwareGeneration == gen else { return }
            if self.lighting.effect != 0 && !self.lighting.musicSync && !self.screenSync && self.lightingPump == nil {
                _ = try? await self.hid.run {
                    try via.setLighting(.color, [restHue, baseSat], timeout: 0.05, attempts: 1)
                }
            }
        }
    }

    /// Sends changed values as they settle (sliders fire many updates), then asks the
    /// keyboard to remember them in EEPROM once things have been quiet for a moment.
    func queueLighting(_ values: Set<VIA.LightingValue>) {
        guard isReady else { return }
        lightingPending.formUnion(values)
        lightingNeedsSave = true
        guard lightingPump == nil else { return }
        let via = self.via
        lightingPump = Task { [weak self] in
            var quietRounds = 0
            var saveRetries = 0
            while !Task.isCancelled, let self {
                if self.lightingPending.isEmpty {
                    quietRounds += 1
                    if quietRounds >= 8 {
                        if self.lightingNeedsSave {
                            do {
                                try await self.hid.run { try via.saveLighting() }
                                if self.lightingPending.isEmpty {
                                    self.lightingNeedsSave = false
                                    break
                                }
                                quietRounds = 0
                                saveRetries = 0
                            } catch {
                                saveRetries += 1
                                if saveRetries >= 2 {
                                    // Keep lightingNeedsSave = true so shutdown() can retry before exit.
                                    break
                                }
                                quietRounds = 0
                            }
                        } else {
                            break
                        }
                    }
                } else {
                    quietRounds = 0
                    saveRetries = 0
                    let batch = self.lightingPending
                    self.lightingPending = []
                    let state = self.lighting
                    do {
                        try await self.hid.run {
                            if batch.contains(.effect) { try via.setLighting(.effect, [UInt8(state.effect)]) }
                            if batch.contains(.brightness) { try via.setLighting(.brightness, [LightingState.rawBrightness(level: state.brightness)]) }
                            if batch.contains(.speed) { try via.setLighting(.speed, [LightingState.rawSpeed(level: state.speed)]) }
                            if batch.contains(.color) { try via.setLighting(.color, [state.hue, state.saturation]) }
                        }
                    } catch {
                        self.notify("Lighting was not updated. \(error.localizedDescription)", isError: true)
                        break
                    }
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
            if !Task.isCancelled {
                self?.lightingPump = nil
            }
        }
    }

    /// Follows lighting changes made with the keyboard's own Fn shortcuts in real time across Desk and Studio.
    func setLightingWatch(_ active: Bool) {
        lightingWatch?.cancel()
        lightingWatch = nil
        guard active else { return }
        let via = self.via
        lightingWatch = Task { [weak self] in
            while !Task.isCancelled, let self {
                let windowVisible = self.isMainWindowVisible
                guard windowVisible else {
                    try? await Task.sleep(for: .milliseconds(1500))
                    continue
                }
                if self.isReady,
                   !self.lighting.musicSync,
                   !self.screenSync,
                   self.lightingPump == nil,
                   !self.isPulsingReactiveHardware,
                   !self.isRestoringLighting,
                   let raw = try? await self.hid.run({ try via.readLighting() }),
                   self.lightingPump == nil,
                   self.lightingPending.isEmpty,
                   !self.isPulsingReactiveHardware,
                   !self.isRestoringLighting {
                    self.applyHardwareLightingIfChanged(raw)
                }
                let interval = (self.inKeyboardStudio && self.section == .light) ? 350 : 750
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    /// Triggered immediately when `Fn` + another key is pressed on the matrix so hardware lighting shortcuts sync without waiting for the next poll tick.
    func checkHardwareLightingNow() {
        guard isReady, !lighting.musicSync, !screenSync, lightingPump == nil, !isPulsingReactiveHardware, !isRestoringLighting else { return }
        let via = self.via
        Task { [weak self] in
            guard let self else { return }
            if let raw = try? await self.hid.run({ try via.readLighting() }),
               self.lightingPump == nil,
               self.lightingPending.isEmpty,
               !self.isPulsingReactiveHardware,
               !self.isRestoringLighting {
                self.applyHardwareLightingIfChanged(raw)
            }
        }
    }

    private func applyHardwareLightingIfChanged(_ raw: VIA.RawLighting) {
        let old = lighting
        var next = old
        next.apply(raw)
        guard next != old else { return }

        // Flash the corresponding Layer 1 Fn lighting shortcut key on the 3D keyboard.
        var targetKeycode: UInt16?
        if next.effect != old.effect {
            targetKeycode = (next.effect == 0 || old.effect == 0) ? 0x5CC2 : 0x5CC3
        } else if next.brightness != old.brightness {
            targetKeycode = next.brightness > old.brightness ? 0x5CC9 : 0x5CCA
        } else if next.speed != old.speed {
            targetKeycode = next.speed > old.speed ? 0x5CCB : 0x5CCC
        } else if next.hue != old.hue {
            targetKeycode = 0x5CC5
        } else if next.saturation != old.saturation {
            targetKeycode = next.saturation > old.saturation ? 0x5CC7 : 0x5CC8
        }
        if let code = targetKeycode {
            for layer in 0..<min(layerCount, keymap.count) {
                if let slot = Layout.keys.first(where: { keymap[layer][$0.index] == code }) {
                    flash(slot.index)
                    break
                }
            }
        }
        lighting = next
    }
}
