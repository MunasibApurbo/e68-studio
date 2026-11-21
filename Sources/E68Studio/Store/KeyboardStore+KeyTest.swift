import Foundation

extension KeyboardStore {
    /// Active layer including any momentary `MO(n)` (`Fn`) switch currently held on the keyboard.
    var effectiveLayer: Int {
        activeLayers(for: pressed).first ?? activeLayer
    }

    func setKeyTestActive(_ active: Bool) {
        pollTask?.cancel()
        pollTask = nil
        resetKeyTestTracking()
        guard active else {
            learnedOSRawBits = []
            learnedFnRawBit = nil
            return
        }
        guard isReady else { return }
        let via = self.via
        pollTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                let windowVisible = self.isMainWindowVisible
                guard windowVisible else {
                    try? await Task.sleep(for: .milliseconds(500))
                    continue
                }
                let inTest = self.inKeyboardStudio && self.section == .test
                if (self.lighting.musicSync || self.screenSync) && !inTest {
                    try? await Task.sleep(for: .milliseconds(350))
                    continue
                }
                if !inTest && !self.inKeyboardStudio {
                    try? await Task.sleep(for: .milliseconds(300))
                    continue
                }
                if let lastOS = self.lastOSKeyEventAt,
                   self.firmwarePressed.isEmpty,
                   lastOS.duration(to: ContinuousClock.now) < .milliseconds(110) {
                    try? await Task.sleep(for: .milliseconds(85))
                    continue
                }
                if self.isReady, let rows = try? await self.hid.run({ try via.matrixState() }) {
                    var rawDown = Set<Int>()
                    for (row, mask) in rows.enumerated() where mask != 0 {
                        for col in 0..<VIA.cols where mask & (1 << col) != 0 {
                            rawDown.insert(row * VIA.cols + col)
                        }
                    }
                    self.processRawMatrix(rawDown)
                }
                let interval = inTest ? 55 : 140
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    private func resetKeyTestTracking() {
        for task in rawMatrixTasks.values { task.cancel() }
        rawMatrixTasks = [:]
        eventPressed = []
        firmwarePressed = [:]
        lastRawMatrixDown = []
        pendingOSKeyDowns = []
        flashGeneration = [:]
        pressed = []
        flashing = []
    }

    /// Processes macOS key and media events from `KeyEventTap`.
    ///
    /// On the E-68 PRO, `VIA.matrixState()` reports raw PCB scan coordinates that do not
    /// match VIA keymap coordinates for every switch (for example, D and Delete sit at
    /// different matrix positions than their keymap cells). OS events carry the exact
    /// mapped keycodes for all switches and knob actions, while the raw matrix is used
    /// only to detect firmware-only keys like `Fn` (`MO(n)`) that emit no HID report.
    func keyEvent(code: UInt16, down: Bool) {
        let now = ContinuousClock.now
        lastOSKeyEventAt = now
        if !down {
            let toRelease = eventPressed.filter { index in
                keymap.contains { $0[index] == code }
            }
            if !toRelease.isEmpty {
                eventPressed.subtract(toRelease)
                syncPressed()
            }
            return
        }

        let layers = activeLayers(for: pressed)
        guard let slot = resolveSlot(for: code, layers: layers) else { return }

        if slot.index == Layout.knobCCW.index || slot.index == Layout.knobCW.index {
            recordKeystroke(slotIndex: slot.index, countsForWPM: false)
            flash(slot.index)
            return
        }

        pendingOSKeyDowns.removeAll { $0.duration(to: now) > .milliseconds(250) }
        pendingOSKeyDowns.append(now)

        if slot.index == Layout.knobPress.index {
            // Knob mute pulses down/up immediately in NX_SYSDEFINED, so flash it visibly.
            recordKeystroke(slotIndex: slot.index, countsForWPM: false)
            flash(slot.index)
            return
        }

        eventPressed.insert(slot.index)
        if inKeyboardStudio && section == .test {
            tested.insert(slot.index)
        }
        recordKeystroke(slotIndex: slot.index)
        pulseReactiveKeyOnHardware(slotIndex: slot.index)
        syncPressed()
    }

    /// Correlates raw PCB matrix transitions with OS key events so `Fn` (`MO(n)`) can be
    /// tracked without letting raw PCB coordinates highlight the wrong switch.
    private func processRawMatrix(_ rawDown: Set<Int>) {
        let newlyDown = rawDown.subtracting(lastRawMatrixDown)
        let newlyUp = lastRawMatrixDown.subtracting(rawDown)
        lastRawMatrixDown = rawDown

        if !newlyUp.isEmpty {
            var changed = false
            for rawBit in newlyUp {
                if firmwarePressed.removeValue(forKey: rawBit) != nil {
                    changed = true
                }
            }
            if changed { syncPressed() }
        }

        if !newlyDown.isEmpty && !firmwarePressed.isEmpty {
            checkHardwareLightingNow()
        }

        for rawBit in newlyDown {
            if learnedOSRawBits.contains(rawBit) { continue }

            if rawBit == learnedFnRawBit, let fnIndex = fnSlotIndex() {
                firmwarePressed[rawBit] = fnIndex
                if inKeyboardStudio && section == .test {
                    tested.insert(fnIndex)
                }
                syncPressed()
                continue
            }

            let detectedAt = ContinuousClock.now
            rawMatrixTasks[rawBit]?.cancel()
            rawMatrixTasks[rawBit] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(55))
                guard !Task.isCancelled, let self else { return }
                self.rawMatrixTasks.removeValue(forKey: rawBit)

                let windowStart = detectedAt.advanced(by: .milliseconds(-90))
                let windowEnd = ContinuousClock.now
                self.pendingOSKeyDowns.removeAll { $0 < windowStart }
                if let match = self.pendingOSKeyDowns.firstIndex(where: { $0 >= windowStart && $0 <= windowEnd }) {
                    self.pendingOSKeyDowns.remove(at: match)
                    self.learnedOSRawBits.insert(rawBit)
                    return
                }

                guard self.learnedFnRawBit == nil, let fnIndex = self.fnSlotIndex() else { return }
                self.learnedFnRawBit = rawBit
                if self.lastRawMatrixDown.contains(rawBit) {
                    self.firmwarePressed[rawBit] = fnIndex
                    if self.inKeyboardStudio && self.section == .test {
                        self.tested.insert(fnIndex)
                    }
                    self.syncPressed()
                } else {
                    self.flash(fnIndex)
                }
            }
        }
    }

    func syncPressed() {
        let liveMirrorActive = LiveMirror.shared.enabled && GlobalKeyTap.shared.isRunning
        let shouldShowOSPresses = isMainWindowVisible && (inKeyboardStudio || (!inStudio && !liveMirrorActive))
        let next = shouldShowOSPresses ? eventPressed.union(firmwarePressed.values) : Set(firmwarePressed.values)
        if next != pressed { pressed = next }
    }

    private func fnSlotIndex() -> Int? {
        for layer in [activeLayer, 0, 2] where layer < keymap.count {
            if let slot = Layout.keys.first(where: { keymap[layer][$0.index] >= 0x5100 && keymap[layer][$0.index] <= 0x510F }) {
                return slot.index
            }
        }
        return nil
    }

    /// Base layers plus any `MO(n)` (`0x5100...0x510F`) layers held on currently active switches.
    private func activeLayers(for activeSwitches: Set<Int>) -> [Int] {
        var base: [Int] = []
        for layer in [activeLayer, 0, 2] where layer < keymap.count && !base.contains(layer) {
            base.append(layer)
        }
        var momentary: [Int] = []
        for index in activeSwitches {
            for layer in base {
                let kc = keymap[layer][index]
                if kc >= 0x5100 && kc <= 0x510F {
                    let target = Int(kc - 0x5100)
                    if target < keymap.count && !momentary.contains(target) {
                        momentary.append(target)
                    }
                }
            }
        }
        return momentary + base
    }

    /// Resolves a keycode to a layout slot, checking switches (and active `MO` layers) before
    /// knob turns so `Fn+Z`/`Fn+X`/`Fn+C` (`Vol-`/`Vol+`/`Mute` on Layer 1) don't jump to the knob.
    private func resolveSlot(for code: UInt16, layers: [Int]) -> Slot? {
        let switchSlots = Layout.keys + [Layout.knobPress]
        for layer in layers {
            if let slot = switchSlots.first(where: { keymap[layer][$0.index] == code }) {
                return slot
            }
        }
        let turnSlots = [Layout.knobCCW, Layout.knobCW]
        for layer in layers {
            if let slot = turnSlots.first(where: { keymap[layer][$0.index] == code }) {
                return slot
            }
        }
        for layer in 0..<keymap.count where !layers.contains(layer) {
            if let slot = Layout.all.first(where: { keymap[layer][$0.index] == code }) {
                return slot
            }
        }
        return nil
    }

    func flash(_ index: Int) {
        if inKeyboardStudio && section == .test {
            tested.insert(index)
        }
        guard isMainWindowVisible else { return }
        let generation = (flashGeneration[index] ?? 0) + 1
        flashGeneration[index] = generation
        flashing.insert(index)
        if index == Layout.knobCW.index {
            knobCWCount += 1
        } else if index == Layout.knobCCW.index {
            knobCCWCount += 1
        }
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            if flashGeneration[index] == generation {
                flashing.remove(index)
            }
        }
    }
}
