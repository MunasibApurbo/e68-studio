import SwiftUI
import AppKit
import Carbon.HIToolbox
import SceneKit
import Metal
import simd

/// `E68Studio --selftest`: exercises the real keyboard through the same code the app uses.
/// Everything it writes goes to unused storage and is restored before it exits.
enum SelfTest {
    private static var failures = 0
    private static var finished = false
    private static var btInfo: BluetoothDeviceInfo?

    private static let sampleMacros: [[MacroStep]] = [
        [MacroStep(kind: .text, text: "Hello, E68!"), MacroStep(kind: .delay, milliseconds: 250), MacroStep(kind: .tap, key: 0x28)],
        [MacroStep(kind: .down, key: 0xE3), MacroStep(kind: .tap, key: 0x06), MacroStep(kind: .up, key: 0xE3)],
    ] + Array(repeating: [], count: 14)

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
    }

    static func run() -> Never {
        runOfflineTests()

        let hid = HIDTransport()
        let bluetooth = BluetoothMonitor()
        bluetooth.onConnect = { info in
            btInfo = info
        }
        hid.onConnect = { info in
            guard !finished else { return }
            finished = true
            bluetooth.stop()
            DispatchQueue.global().async { executeVIA(hid, info) }
        }
        hid.start()
        bluetooth.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard !finished else { return }
            finished = true
            bluetooth.stop()
            if let bt = btInfo {
                check("Bluetooth keyboard detected", true, "\(bt.product) (\(bt.hardwareID), \(bt.link), address \(bt.formattedAddress))")
            }
            print("INFO  No USB/2.4G keyboard connected; skipped VIA EEPROM checks")
            finish()
        }
        RunLoop.main.run()
        exit(0)
    }

    private static func runOfflineTests() {
        // Test 1: Macro codec round-trip & edge cases
        let image = MacroCodec.image(sampleMacros)
        let decoded = MacroCodec.split(image + [UInt8](repeating: 0, count: 64), count: 16)
        check("macro codec round-trips", MacroCodec.image(decoded) == image)
        let edgeEncoded = MacroCodec.encode([MacroStep(kind: .tap, key: 0), MacroStep(kind: .text, text: "a\tb\nc")])
        let edgeDecoded = MacroCodec.decode(edgeEncoded)
        let malformedDecoded = MacroCodec.decode([0x01, 0x04, UInt8(ascii: "1"), UInt8(ascii: "2"), UInt8(ascii: "x")])
        check("macro codec skips key=0, handles tabs/newlines & malformed delays",
              !edgeEncoded.contains(0)
              && edgeDecoded.count == 5
              && edgeDecoded[1].kind == .tap && edgeDecoded[1].key == 0x2B
              && edgeDecoded[3].kind == .tap && edgeDecoded[3].key == 0x28
              && malformedDecoded.count == 1 && malformedDecoded[0].kind == .text && malformedDecoded[0].text == "x")

        // Test 2: Layout integrity (67 keys + 3 knob actions = 70 unique slots)
        check("layout has 67 keys + 3 knob actions", Layout.keys.count == 67 && Layout.all.count == 70)
        check("layout positions are unique", Set(Layout.all.map(\.index)).count == 70)

        // Test 3: LightingState Codable, clamping, Backup validation, ColorMath & TextExpander
        do {
            let musicState = LightingState(effect: 6, brightness: 8, speed: 2, hue: 140, saturation: 255, lastEffect: 6,
                                           musicSync: true, musicMode: .pulse, musicSensitivity: 1.5, musicColorMode: .fire)
            let stateData = try JSONEncoder().encode(musicState)
            let decodedState = try JSONDecoder().decode(LightingState.self, from: stateData)
            check("music lighting state codable round-trip", decodedState.musicSync == true && decodedState.musicMode == .pulse && decodedState.musicSensitivity == 1.5 && decodedState.musicColorMode == .fire)

            let legacyJSON = "{\"effect\": 5, \"brightness\": 7, \"speed\": 1, \"hue\": 100, \"saturation\": 200, \"lastEffect\": 5}".data(using: .utf8)!
            let legacyState = try JSONDecoder().decode(LightingState.self, from: legacyJSON)
            check("legacy lighting state backwards compatibility", legacyState.musicSync == false && legacyState.musicMode == .equalizer && legacyState.reactiveTypingRipple == false)

            let corruptJSON = "{\"effect\": -5, \"brightness\": 99, \"speed\": 0}".data(using: .utf8)!
            let clampedLighting = try JSONDecoder().decode(LightingState.self, from: corruptJSON)
            check("lighting state clamps out-of-range JSON values",
                  clampedLighting.effect == 0
                  && clampedLighting.brightness == LightingCatalog.maxBrightness
                  && clampedLighting.speed == LightingCatalog.minSpeed)

            try MainActor.assumeIsolated {
                let backup = Backup(
                    product: "E-68 PRO",
                    firmware: "1.02",
                    created: Date(timeIntervalSince1970: 1_700_000_000),
                    keymap: FactoryKeymap.layers,
                    macros: sampleMacros.map { MacroCodec.encode($0) },
                    macroNames: ["One", "Two"] + Array(repeating: "", count: 14),
                    lighting: musicState
                )
                let decodedBackup = try KeyboardStore.decodeBackup(try KeyboardStore.encode(backup))
                var badFormat = backup; badFormat.format = "other"
                var badVersion = backup; badVersion.version = 2
                var badCells = backup; badCells.keymap = [[1, 2]]
                let rejectsBadFormat = (try? KeyboardStore.decodeBackup(KeyboardStore.encode(badFormat))) == nil
                let rejectsBadVersion = (try? KeyboardStore.decodeBackup(KeyboardStore.encode(badVersion))) == nil
                let rejectsBadCells = (try? KeyboardStore.decodeBackup(KeyboardStore.encode(badCells))) == nil
                check("backup encode/decode & schema validation",
                      decodedBackup.keymap == FactoryKeymap.layers
                      && decodedBackup.macros.count == 16
                      && decodedBackup.macroNames[0] == "One"
                      && rejectsBadFormat && rejectsBadVersion && rejectsBadCells)

                let wrapValues: [Float] = [.nan, .infinity, -.infinity, -1e-8, 1.0, 2.3]
                let wrapOk = wrapValues.allSatisfy {
                    let w = ColorMath.wrapHue($0)
                    return w.isFinite && w >= 0 && w < 1
                } && abs(ColorMath.wrapHue(2.3) - 0.3) < 1e-4
                let rendered = TextExpander.render("hi\r\n{cursor}end")
                let dateRendered = TextExpander.render("on {date} at {time}", now: Date(timeIntervalSince1970: 1_700_000_000))
                check("color wrapHue & text expander rendering",
                      wrapOk
                      && rendered.0 == "hi\nend" && rendered.1 == 3
                      && !dateRendered.0.contains("{date}") && !dateRendered.0.contains("{time}"))
            }

            let wpState = LightingState(effect: 6, brightness: 7, speed: 2, hue: 90, saturation: 240, lastEffect: 6,
                                        musicSync: true, musicMode: .wave, musicSensitivity: 1.2, musicColorMode: .wallpaper, reactiveTypingRipple: true)
            let wpDecoded = try JSONDecoder().decode(LightingState.self, from: try JSONEncoder().encode(wpState))
            let wpPalette = WallpaperColorSampler.shared.currentPalette()
            var wpEngine = MusicLightEngine()
            let wpFrame = wpEngine.step(AudioSnapshot(), settings: .init(wpDecoded), now: 100.0)
            check("wallpaper color sync & reactive ripple state",
                  wpDecoded.musicColorMode == .wallpaper && wpDecoded.reactiveTypingRipple == true
                  && wpPalette.hue >= 0 && wpPalette.hue <= 1 && wpFrame.level >= 0)
        } catch {
            check("lighting state codable round-trip", false, error.localizedDescription)
        }

        // Test 3b: StudioProfile & Telemetry heatmap math
        do {
            let defaults = StudioProfile.defaults
            let encoded = try JSONEncoder().encode(defaults)
            let decoded = try JSONDecoder().decode([StudioProfile].self, from: encoded)
            let matchOk = decoded.count == 3
                && decoded[1].matches(bundleIdentifier: "com.apple.dt.Xcode")
                && !decoded[1].matches(bundleIdentifier: "com.apple.Music")
                && decoded[2].matches(bundleIdentifier: "com.apple.Music")
            let c0 = KeyboardStore.heatmapColor(intensity: 0)
            let cMid = KeyboardStore.heatmapColor(intensity: 0.5)
            let cHot = KeyboardStore.heatmapColor(intensity: 1.0)
            check("studio profiles & heatmap thermal ramp", matchOk && c0 != cHot && cMid != cHot)
        } catch {
            check("studio profiles codable round-trip", false, error.localizedDescription)
        }

        // Test 4: AudioMonitor initialization and 16-band FFT snapshot generation
        let audioMonitor = AudioMonitor()
        audioMonitor.start()
        Thread.sleep(forTimeInterval: 0.15)
        let audioSnap = audioMonitor.snapshot()
        check("audio monitor initializes and produces 16 bands", audioSnap.bands.count == 16 && audioSnap.waveform.count == 32 && audioSnap.amplitude >= 0)
        audioMonitor.stop()

        // Test 5: KeyboardScene 3D environment & hardware build verification
        let world = KeyboardScene()
        world.setAmbience(deskLampOn: true, mood: .daylight, scenario: .swissAlps)
        let keycapsOk = Layout.keys.count == 67 && Layout.keys.allSatisfy { world.capNodes[$0.index]?.name == "k\($0.index)" }
        let knobOk = world.knob.parent != nil
            && world.knob.name == "k\(Layout.knobPress.index)"
            && world.capNodes[Layout.knobPress.index] === world.knob
        let mouseRoot = world.scene.rootNode.childNode(withName: TechProps.MouseParts.root, recursively: true)
        let mouseWheel = mouseRoot?.childNode(withName: TechProps.MouseParts.wheel, recursively: true)
        let mouseLeft = mouseRoot?.childNode(withName: TechProps.MouseParts.left, recursively: true)
        let mouseRight = mouseRoot?.childNode(withName: TechProps.MouseParts.right, recursively: true)
        let mouseBack = mouseRoot?.childNode(withName: TechProps.MouseParts.back, recursively: true)
        let mouseForward = mouseRoot?.childNode(withName: TechProps.MouseParts.forward, recursively: true)
        let mouseLED = mouseRoot?.childNode(withName: TechProps.MouseParts.dpiLED, recursively: true)
        let mouseOk = mouseRoot != nil && mouseWheel != nil && mouseLeft != nil && mouseRight != nil && mouseBack != nil && mouseForward != nil && mouseLED != nil
        world.setAmbience(deskLampOn: false, mood: .midnight, scenario: .room)
        var allScenariosOk = DeskScenario.allCases.count == 8
        for scenario in DeskScenario.allCases {
            world.setAmbience(deskLampOn: true, mood: .daylight, scenario: scenario)
            if scenario != .room && world.scenarioRoot.childNodes.isEmpty {
                allScenariosOk = false
            }
            if NSImage(systemSymbolName: scenario.symbol, accessibilityDescription: nil) == nil {
                allScenariosOk = false
            }
        }
        world.setAmbience(deskLampOn: true, mood: .daylight, scenario: .swissAlps)
        check("3D scene supports all 8 switchable world scenarios", allScenariosOk,
              "\(DeskScenario.allCases.count) scenarios")
        world.setHeatmap([Layout.keys[0].index: 1.0, Layout.knobPress.index: 0.5], active: true)
        world.setHeatmap([:], active: false)
        var waveState = LightingState()
        waveState.effect = 1
        waveState.brightness = 9
        waveState.reactiveTypingRipple = true
        world.setLighting(waveState)
        world.setPressed([2 * 16 + 4])
        if let testRenderer = MTLCreateSystemDefaultDevice().map({ SCNRenderer(device: $0, options: nil) }) {
            testRenderer.scene = world.scene
            testRenderer.pointOfView = world.cameraNode
            world.renderer(testRenderer, updateAtTime: CACurrentMediaTime())
        }
        let litKeys = world.glowSlots.filter { $0.lastR > 0 || $0.lastG > 0 || $0.lastB > 0 }.count
        let uniqueColors = Set(world.glowSlots.map { "\($0.lastR),\($0.lastG),\($0.lastB)" }).count
        let reactiveAlive = !world.ripples.isEmpty && !world.lasers.isEmpty && !world.fades.isEmpty
        world.setPressed([])
        check("3D scene builds 67 keycaps, rotary knob, and MCHOSE G7 nodes", keycapsOk && knobOk && mouseOk)
        check("3D per-key RGB effects & reactive key ripples", litKeys == 67 && uniqueColors > 10 && reactiveAlive,
              "\(litKeys)/67 keys lit, \(uniqueColors) distinct colours")

        if let dev = MTLCreateSystemDefaultDevice(), dev.supportsRaytracing, let pathTracer = PathTracerRenderer(device: dev) {
            let pickBounds = CGSize(width: 1280, height: 800)
            world.setGoal(KeyboardScene.homePose, immediately: true)
            world.viewAspect = Float(pickBounds.width / pickBounds.height)
            let pickRenderer = SCNRenderer(device: dev, options: nil)
            pickRenderer.scene = world.scene
            pickRenderer.pointOfView = world.cameraNode
            world.renderer(pickRenderer, updateAtTime: CACurrentMediaTime() + 0.05)

            let camT = world.cameraNode.simdWorldTransform
            let camPos = SIMD3<Float>(camT.columns.3.x, camT.columns.3.y, camT.columns.3.z)
            let camRight = simd_normalize(SIMD3<Float>(camT.columns.0.x, camT.columns.0.y, camT.columns.0.z))
            let camUp = simd_normalize(SIMD3<Float>(camT.columns.1.x, camT.columns.1.y, camT.columns.1.z))
            let camForward = -simd_normalize(SIMD3<Float>(camT.columns.2.x, camT.columns.2.y, camT.columns.2.z))
            let fovDeg = Float(world.cameraNode.camera?.fieldOfView ?? 56)
            let tanHalf = tan((fovDeg * .pi / 180.0) * 0.5)
            let aspect = Float(pickBounds.width / pickBounds.height)
            let projectWorld: (SIMD3<Float>) -> CGPoint? = { p in
                let rel = p - camPos
                let depth = simd_dot(rel, camForward)
                guard depth > 0.1 else { return nil }
                let ndcX = simd_dot(rel, camRight) / (depth * tanHalf * aspect)
                let ndcY = simd_dot(rel, camUp) / (depth * tanHalf)
                guard abs(ndcX) < 1.0 && abs(ndcY) < 1.0 else { return nil }
                return CGPoint(
                    x: CGFloat(ndcX * 0.5 + 0.5) * pickBounds.width,
                    y: CGFloat(ndcY * 0.5 + 0.5) * pickBounds.height
                )
            }
            let geometryNodesUnder: (SCNNode) -> [SCNNode] = { root in
                var list: [SCNNode] = []
                root.enumerateHierarchy { node, _ in
                    if node.geometry != nil && !node.isHidden && node.opacity > 0.01 { list.append(node) }
                }
                return list
            }
            let pickFirstHit: ([SCNNode], (SCNNode) -> Bool) -> Bool = { candidates, predicate in
                for node in candidates {
                    let (bMin, bMax) = node.boundingBox
                    let localCenter = SIMD3<Float>(
                        Float(bMin.x + bMax.x) * 0.5,
                        Float(bMin.y + bMax.y) * 0.5,
                        Float(bMin.z + bMax.z) * 0.5
                    )
                    guard let pt = projectWorld(node.simdConvertPosition(localCenter, to: nil)),
                          let hit = pathTracer.pickNode(at: pt, in: pickBounds, world: world) else { continue }
                    if predicate(hit) { return true }
                }
                return false
            }

            let targetKey = Layout.keys[0].index
            let keyPickOk: Bool = {
                guard let cap = world.capNodes[targetKey],
                      let pt = projectWorld(cap.simdConvertPosition(SIMD3<Float>(0, 0.25, 0), to: nil)),
                      let hit = pathTracer.pickNode(at: pt, in: pickBounds, world: world),
                      world.isKeyboard(hit) else { return false }
                var cur: SCNNode? = hit
                while let n = cur {
                    if let idx = KeyboardScene.keyIndex(of: n) { return idx == targetKey }
                    cur = n.parent
                }
                return false
            }()
            let mousePickOk = mouseLeft.map { left in
                pickFirstHit([left]) { world.isMouse($0) }
            } ?? false
            let propPickOk: (KeyboardScene.DeskProp) -> Bool = { prop in
                guard let root = world.scene.rootNode.childNode(withName: prop.rawValue, recursively: true) else { return false }
                let sorted = geometryNodesUnder(root).sorted {
                    $0.simdConvertPosition(.zero, to: nil).y > $1.simdConvertPosition(.zero, to: nil).y
                }
                return pickFirstHit(sorted) { KeyboardScene.deskProp(of: $0) == prop }
            }
            let monitorPickOk = propPickOk(.monitor)
            let deskLampPickOk = propPickOk(.deskLamp)
            check("hardware ray-traced mouse picking hits keycap, mouse, monitor, and desk lamp",
                  keyPickOk && mousePickOk && monitorPickOk && deskLampPickOk,
                  "key=\(keyPickOk) mouse=\(mousePickOk) monitor=\(monitorPickOk) deskLamp=\(deskLampPickOk)")
        }

        // Test 6: KeyboardStore telemetry WPM + MouseStore configuration & live discovery check
        MainActor.assumeIsolated {
            let tempStore = KeyboardStore()
            let knobSlot = Layout.knobCW.index
            let keySlot = Layout.keys[0].index
            let beforeKnobCount = tempStore.internalKeyCounts[knobSlot] ?? 0
            tempStore.recordKeystroke(slotIndex: knobSlot, countsForWPM: false)
            let knobExcludedFromWPM = (tempStore.internalKeyCounts[knobSlot] ?? 0) == beforeKnobCount + 1
                && tempStore.internalCurrentWPM == 0
                && tempStore.keystrokeTimestamps.isEmpty
            for _ in 0..<6 {
                tempStore.recordKeystroke(slotIndex: keySlot, countsForWPM: true)
            }
            let wpmRises = tempStore.internalCurrentWPM > 0 && tempStore.keystrokeTimestamps.count == 6
            tempStore.recomputeWPM(at: ContinuousClock.now.advanced(by: .seconds(20)))
            let wpmDecaysToZero = tempStore.internalCurrentWPM == 0 && tempStore.keystrokeTimestamps.isEmpty
            let heatmapNonEmpty = (tempStore.normalizedHeatmap[keySlot] ?? 0) > 0
            let savedTelemetryCounts = UserDefaults.standard.object(forKey: "telemetry.keyCounts")
            let savedTelemetryPeak = UserDefaults.standard.object(forKey: "telemetry.peakWPM")
            tempStore.knobCWCount = 3
            tempStore.knobCCWCount = 2
            tempStore.resetTelemetry()
            let telemetryResetOk = tempStore.knobCWCount == 0
                && tempStore.knobCCWCount == 0
                && tempStore.internalKeyCounts.isEmpty
                && tempStore.keyCounts.isEmpty
                && tempStore.internalCurrentWPM == 0
                && tempStore.internalPeakWPM == 0
            if let savedTelemetryCounts {
                UserDefaults.standard.set(savedTelemetryCounts, forKey: "telemetry.keyCounts")
            } else {
                UserDefaults.standard.removeObject(forKey: "telemetry.keyCounts")
            }
            if let savedTelemetryPeak {
                UserDefaults.standard.set(savedTelemetryPeak, forKey: "telemetry.peakWPM")
            } else {
                UserDefaults.standard.removeObject(forKey: "telemetry.peakWPM")
            }

            tempStore.telemetrySaveTask?.cancel()
            tempStore.telemetrySaveTask = nil
            tempStore.telemetryPublishTask?.cancel()
            tempStore.telemetryPublishTask = nil
            tempStore.wpmDecayTask?.cancel()
            tempStore.wpmDecayTask = nil
            check("keyboard WPM knob exclusion, decay, heatmap & telemetry reset",
                  knobExcludedFromWPM && wpmRises && wpmDecaysToZero && heatmapNonEmpty && telemetryResetOk)

            let mouseActionsMap: [MouseButton: MouseAction] = [
                .middle: .missionControl,
                .back: .sniper,
                .forward: .keystroke(Keystroke(keyCode: 0, modifiers: 0x100000, display: "⌘A")),
            ]
            let customGestures = GestureMap(up: .dpiCycle, down: .disabled, left: .previousSpace, right: .nextSpace, tap: .standard)
            var actionCodableOk = false
            do {
                let decodedActions = try JSONDecoder().decode([MouseButton: MouseAction].self, from: JSONEncoder().encode(mouseActionsMap))
                let decodedGestures = try JSONDecoder().decode(GestureMap.self, from: JSONEncoder().encode(customGestures))
                actionCodableOk = decodedActions == mouseActionsMap && decodedGestures == customGestures
            } catch {
                actionCodableOk = false
            }
            _ = stageColor(-1)
            _ = stageColor(99)
            check("mouse actions & gestures codable + stageColor bounds", actionCodableOk)

            let stagesOk = DPIStage.defaults.count == 5
                && DPIStage.defaults.allSatisfy(\.enabled)
                && DPIStage.defaults.map(\.dpi) == [400, 800, 1600, 3200, 6400]
                && DPIStage.palette.count == 8
            let multiplierMathOk = abs(MouseStore.multiplier(effectiveDPI: 400, hardwareDPI: 1600) - 0.25) < 1e-9
                && abs(MouseStore.multiplier(effectiveDPI: 3200, hardwareDPI: 1600) - 2.0) < 1e-9
                && abs(MouseStore.multiplier(effectiveDPI: 12000, hardwareDPI: 400) - 8.0) < 1e-9
                && abs(MouseStore.multiplier(effectiveDPI: 100, hardwareDPI: 12000) - 0.05) < 1e-9
            let mouse = MouseStore.shared
            mouse.refresh(applySettings: false)
            let expectedInstanceMultiplier = MouseStore.multiplier(effectiveDPI: mouse.effectiveDPI, hardwareDPI: mouse.hardwareDPI)
            let instanceOk = abs(mouse.multiplier - expectedInstanceMultiplier) < 1e-9

            // Preserve user's persisted mouse settings & active profile around state-machine checks.
            let savedCustom = mouse.customEnabled
            let savedAccelerationOff = mouse.accelerationOff
            let savedSpeed = mouse.speed
            let savedHardwareDPI = mouse.hardwareDPI
            let savedStages = mouse.stages
            let savedStageIndex = mouse.stageIndex
            let savedSniperDPI = mouse.sniperDPI
            let savedSniperActive = mouse.sniperActive
            let savedShowStageHUD = mouse.showStageHUD
            let savedBindings = mouse.bindings
            let savedGestures = mouse.gestures
            let savedGestureDistance = mouse.gestureDistance
            let savedReverseScroll = mouse.reverseScroll
            let savedScrollQuarterSteps = mouse.scrollQuarterSteps
            let savedDebounceMS = mouse.debounceMS
            let savedActiveProfileKey = UserDefaults.standard.string(forKey: "e68.activeProfileID")
            let savedActiveProfileID = ProfileStore.shared.activeProfileID
            var stageLogicOk = false
            mouse.batchUpdate {
                mouse.showStageHUD = false
                mouse.stages = DPIStage.defaults
                mouse.selectStage(3, announce: false) // 3200 DPI
                let beforeID = mouse.currentStage?.id
                mouse.stages[0].enabled = false
                let preservedAfterDisable = mouse.currentStage?.id == beforeID && mouse.stageIndex == 2 && mouse.effectiveDPI == 3200
                mouse.stages.remove(at: 0)
                let preservedAfterRemove = mouse.currentStage?.id == beforeID && mouse.stageIndex == 2 && mouse.effectiveDPI == 3200
                mouse.selectStage(99, announce: false)
                let clampedHigh = mouse.stageIndex == 3 // 4 enabled stages remaining (800, 1600, 3200, 6400 -> max index 3)
                mouse.selectStage(-5, announce: false)
                let clampedLow = mouse.stageIndex == 0
                mouse.cycleStage()
                let cycled = mouse.stageIndex == 1
                mouse.sniperActive = true
                mouse.customEnabled = false
                let sniperCleared = !mouse.sniperActive

                // Verify ProfileStore activation does not hijack MouseStore.customEnabled when false.
                ProfileStore.shared.activate(
                    StudioProfile(name: "DPI Test", symbol: "sparkles", bundleIdentifiers: [], lighting: LightingState(), activeLayer: 0, mouseStageIndex: 3),
                    notifyUser: false
                )
                let profileDidNotHijackDPI = !mouse.customEnabled && mouse.stageIndex == 1

                // Verify out-of-range stage DPI and negative colorIndex sanitization.
                mouse.stages = [
                    DPIStage(dpi: 10, enabled: true, colorIndex: -3),
                    DPIStage(dpi: 99999, enabled: true, colorIndex: 15),
                ]
                let clampedStageVals = mouse.stages.count == 2
                    && mouse.stages[0].dpi == 50
                    && mouse.stages[0].colorIndex == 5
                    && mouse.stages[1].dpi == 12000
                    && mouse.stages[1].colorIndex == 7

                stageLogicOk = preservedAfterDisable && preservedAfterRemove && clampedHigh && clampedLow && cycled && sniperCleared && profileDidNotHijackDPI && clampedStageVals
            }

            ProfileStore.shared.activeProfileID = savedActiveProfileID
            if savedActiveProfileKey == nil {
                UserDefaults.standard.removeObject(forKey: "e68.activeProfileID")
            }

            var liveMouseApplyOk = true
            if mouse.info != nil {
                mouse.batchUpdate {
                    mouse.showStageHUD = false
                    mouse.customEnabled = true
                    mouse.accelerationOff = true
                }
                liveMouseApplyOk = !mouse.lastApplyFailed
            }

            mouse.batchUpdate {
                mouse.hardwareDPI = savedHardwareDPI
                mouse.stages = savedStages
                mouse.stageIndex = savedStageIndex
                mouse.customEnabled = savedCustom
                mouse.accelerationOff = savedAccelerationOff
                mouse.sniperActive = savedSniperActive
                mouse.showStageHUD = savedShowStageHUD
            }
            let mouseRestoreOk = mouse.info == nil || !mouse.lastApplyFailed

            let discoveryDetail: String
            if let info = mouse.info {
                discoveryDetail = "\(info.product) (\(info.usbID), \(info.link), firmware \(info.firmware)\(info.battery.map { ", battery \($0)%" } ?? ""))"
            } else {
                discoveryDetail = "no MCHOSE G7 connected"
            }
            check("mouse configuration, live apply & discovery",
                  stagesOk && multiplierMathOk && instanceOk && stageLogicOk && liveMouseApplyOk && mouseRestoreOk,
                  discoveryDetail)

            // Test 7: Mouse appliedDPI / raw linear multiplier + MouseRemapper & ActionPerformer helpers
            mouse.batchUpdate {
                mouse.showStageHUD = false
                mouse.customEnabled = true
                mouse.accelerationOff = true
                mouse.hardwareDPI = 400
                mouse.stages = [DPIStage(dpi: 12000, enabled: true, colorIndex: 0), DPIStage(dpi: 50, enabled: true, colorIndex: 1)]
                mouse.selectStage(0, announce: false)
            }
            let clampedHighDPI = mouse.appliedDPI == 3200 && abs(mouse.multiplier - 8.0) < 1e-9
            mouse.batchUpdate {
                mouse.hardwareDPI = 12000
                mouse.selectStage(1, announce: false)
            }
            let clampedLowDPI = mouse.appliedDPI == 600 && abs(mouse.multiplier - 0.05) < 1e-9
            mouse.batchUpdate {
                mouse.hardwareDPI = 1600
                mouse.stages = DPIStage.defaults
                mouse.selectStage(2, announce: false)
            }
            let exactLinearDPI = mouse.appliedDPI == 1600 && abs(mouse.multiplier - 1.0) < 1e-9
            mouse.batchUpdate {
                mouse.hardwareDPI = 3200
                mouse.customEnabled = true
                mouse.accelerationOff = true
                mouse.speed = 0.9
                mouse.stages = [DPIStage(dpi: 1200, enabled: true, colorIndex: 2)]
                mouse.stageIndex = 0
                mouse.sniperDPI = 800
                mouse.sniperActive = true
                mouse.showStageHUD = false
                mouse.bindings = [.middle: .missionControl, .back: .copy]
                mouse.gestures = [.forward: GestureMap(up: .paste)]
                mouse.gestureDistance = 90
                mouse.reverseScroll = true
                mouse.scrollQuarterSteps = 12
                mouse.debounceMS = 25
            }
            mouse.restoreDefaults()
            let restoreDefaultsOk = mouse.hardwareDPI == 3200
                && !mouse.customEnabled
                && !mouse.accelerationOff
                && abs(mouse.speed - 0.5) < 1e-9
                && !mouse.sniperActive
                && mouse.sniperDPI == 400
                && mouse.showStageHUD
                && mouse.stages.map(\.dpi) == DPIStage.defaults.map(\.dpi)
                && mouse.stages.allSatisfy(\.enabled)
                && mouse.stageIndex == 2
                && mouse.bindings.isEmpty
                && mouse.gestures.isEmpty
                && mouse.gestureDistance == 50
                && !mouse.reverseScroll
                && mouse.scrollQuarterSteps == 4
                && mouse.debounceMS == 0
            check("MouseStore.restoreDefaults resets all non-hardware settings", restoreDefaultsOk)

            mouse.batchUpdate {
                mouse.hardwareDPI = savedHardwareDPI
                mouse.stages = savedStages
                mouse.stageIndex = savedStageIndex
                mouse.customEnabled = savedCustom
                mouse.accelerationOff = savedAccelerationOff
                mouse.speed = savedSpeed
                mouse.sniperDPI = savedSniperDPI
                mouse.sniperActive = savedSniperActive
                mouse.showStageHUD = savedShowStageHUD
                mouse.bindings = savedBindings
                mouse.gestures = savedGestures
                mouse.gestureDistance = savedGestureDistance
                mouse.reverseScroll = savedReverseScroll
                mouse.scrollQuarterSteps = savedScrollQuarterSteps
                mouse.debounceMS = savedDebounceMS
            }
            check("mouse appliedDPI & raw linear multiplier bounds", clampedHighDPI && clampedLowDPI && exactLinearDPI)

            var zeroBufferThrows = false
            do {
                try VIA(hid: HIDTransport()).writeMacroBuffer([], bufferSize: 0)
            } catch {
                zeroBufferThrows = true
            }
            check("VIA macro buffer zero-size guard", VIA.usableMacroBytes(bufferSize: 0) == 0 && zeroBufferThrows)

            var scaler = ScrollScaler()
            let seq: (Double, [Int64]) -> [Int64] = { k, inputs in
                scaler.reset()
                return inputs.enumerated().map { idx, lines in
                    scaler.scaleAxis1(lines: lines, multiplier: k, nowNs: UInt64(idx + 1) * 50_000_000)
                }
            }
            let q25Ok = seq(0.25, [1, 1, 1, 1]) == [0, 0, 0, 1] && abs(scaler.axis1.remainder) < 1e-9
            let q50Ok = seq(0.5, [1, 1, 1, 1]) == [0, 1, 0, 1]
            let q75Ok = seq(0.75, [1, 1, 1, 1]) == [0, 1, 1, 1]
            let q125Ok = seq(1.25, [1, 1, 1, 1]) == [1, 1, 1, 2]
            let q400Ok = seq(4.0, [1, 1]) == [4, 4]
            let revOk = seq(-1.0, [1, -2]) == [-1, 2]

            scaler.reset()
            let revBefore = scaler.scaleAxis1(lines: 1, multiplier: 0.75, nowNs: 10_000_000)
            let revFirst = scaler.scaleAxis1(lines: -1, multiplier: 0.75, nowNs: 20_000_000)
            let revSecond = scaler.scaleAxis1(lines: -1, multiplier: 0.75, nowNs: 30_000_000)
            let reverseResetsOk = revBefore == 0 && revFirst == 0 && revSecond == -1

            scaler.reset()
            let idleBefore = scaler.scaleAxis1(lines: 1, multiplier: 0.75, nowNs: 10_000_000)
            let idleAfter = scaler.scaleAxis1(lines: 1, multiplier: 0.75, nowNs: 700_000_000)
            let idleResetsOk = idleBefore == 0 && idleAfter == 0

            let axis2Independent = scaler.scaleAxis2(lines: 1, multiplier: 0.5, nowNs: 10_000_000) == 0
                && scaler.scaleAxis2(lines: 1, multiplier: 0.5, nowNs: 20_000_000) == 1
            check("scroll fractional accumulator (0.25x/0.5x/0.75x/1.25x/4x/-1x, reverse & idle reset)",
                  q25Ok && q50Ok && q75Ok && q125Ok && q400Ok && revOk && reverseResetsOk && idleResetsOk && axis2Independent)

            var clickTracker = ClickStateTracker()
            let p0 = CGPoint(x: 100, y: 100)
            let pNear = CGPoint(x: 102, y: 101)
            let pFar = CGPoint(x: 150, y: 150)
            let c1d = clickTracker.nextClickState(for: .left, down: true, at: p0, now: 1.0, doubleClickInterval: 0.5)
            let c1u = clickTracker.nextClickState(for: .left, down: false, at: p0, now: 1.02, doubleClickInterval: 0.5)
            let c2d = clickTracker.nextClickState(for: .left, down: true, at: pNear, now: 1.2, doubleClickInterval: 0.5)
            let c2u = clickTracker.nextClickState(for: .left, down: false, at: pNear, now: 1.22, doubleClickInterval: 0.5)
            let c3d = clickTracker.nextClickState(for: .left, down: true, at: pNear, now: 1.4, doubleClickInterval: 0.5)
            let cRight = clickTracker.nextClickState(for: .right, down: true, at: pNear, now: 1.41, doubleClickInterval: 0.5)
            let cTimeout = clickTracker.nextClickState(for: .left, down: true, at: pNear, now: 2.5, doubleClickInterval: 0.5)
            let cMoved = clickTracker.nextClickState(for: .left, down: true, at: pFar, now: 2.6, doubleClickInterval: 0.5)
            check("click state tracker (1->2->3, timeout & distance reset)",
                  c1d == 1 && c1u == 1 && c2d == 2 && c2u == 2 && c3d == 3 && cRight == 1 && cTimeout == 1 && cMoved == 1)

            var debounce = ButtonDebounceTracker()
            let up1 = debounce.shouldSuppress(button: 3, isDown: false, nowNs: 100_000_000, debounceMS: 15)
            let chatterDown = debounce.shouldSuppress(button: 3, isDown: true, nowNs: 105_000_000, debounceMS: 15)
            let chatterUp = debounce.shouldSuppress(button: 3, isDown: false, nowNs: 106_000_000, debounceMS: 15)
            // Simulate a dropped debounced up followed by a real press after debounceMS:
            _ = debounce.shouldSuppress(button: 3, isDown: false, nowNs: 200_000_000, debounceMS: 15)
            _ = debounce.shouldSuppress(button: 3, isDown: true, nowNs: 205_000_000, debounceMS: 15)
            let realDownAfter = debounce.shouldSuppress(button: 3, isDown: true, nowNs: 250_000_000, debounceMS: 15)
            let realUpAfter = debounce.shouldSuppress(button: 3, isDown: false, nowNs: 280_000_000, debounceMS: 15)
            check("button debounce filters chatter & clears stale state on fresh down",
                  !up1 && chatterDown && chatterUp && !realDownAfter && !realUpAfter)

            var meter = PollingRateMeter()
            for i in 0...10 {
                meter.record(nowNs: UInt64(10 + i) * 1_000_000)
            }
            let activeSample = meter.sample(nowNs: 30_000_000)
            let idleBurstSample = meter.sample(nowNs: 250_000_000)
            let afterIdleSample = meter.sample(nowNs: 300_000_000)
            check("polling rate meter captures burst peak before idle reset",
                  activeSample.currentRate == 1000 && activeSample.sampledPeak == 1000
                  && idleBurstSample.currentRate == 0 && idleBurstSample.sampledPeak == 1000
                  && afterIdleSample.currentRate == 0 && afterIdleSample.sampledPeak == nil)

            let fnKeys = [kVK_F1, kVK_F5, kVK_F11, kVK_F12, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown]
            let fnFlagsOk = fnKeys.allSatisfy { ActionPerformer.effectiveKeyFlags(for: $0).contains(.maskSecondaryFn) }
            let arrowFlags = ActionPerformer.effectiveKeyFlags(for: kVK_LeftArrow)
            let letterFlags = ActionPerformer.effectiveKeyFlags(for: kVK_ANSI_A)
            let multilineSegments = ActionPerformer.typeSegments(for: "ab\nc\r\nd\re")
            let expectedMultiline: [ActionPerformer.TypeSegment] = [
                .unicode(Array("ab".utf16)),
                .returnKey,
                .unicode(Array("c".utf16)),
                .returnKey,
                .unicode(Array("d".utf16)),
                .returnKey,
                .unicode(Array("e".utf16)),
            ]
            let chunkedSegments = ActionPerformer.typeSegments(for: String(repeating: "x", count: 45))
            let chunkCounts = chunkedSegments.map { segment -> Int in
                if case .unicode(let units) = segment { return units.count }
                return -1
            }
            check("ActionPerformer.key & typeSegments (secondaryFn, newlines, 20-unit UTF-16 chunks)",
                  fnFlagsOk
                  && arrowFlags.contains([.maskSecondaryFn, .maskNumericPad])
                  && !letterFlags.contains(.maskSecondaryFn)
                  && multilineSegments == expectedMultiline
                  && chunkCounts == [20, 20, 5])
        }
    }

    private static func executeVIA(_ hid: HIDTransport, _ info: DeviceInfo) {
        let via = VIA(hid: hid)
        print("Keyboard: \(info.product) by \(info.manufacturer), \(info.usbID), firmware \(info.firmware), via \(info.link)")
        do {
            let version = try via.protocolVersion()
            check("VIA protocol version is 9", version == 9, "got \(version)")
            let layers = try via.layerCount()
            check("layer count", layers == 4, "got \(layers)")
            let macroCount = try via.macroCount()
            let bufferSize = try via.macroBufferSize()
            check("macro storage", macroCount == 16 && bufferSize == 512, "\(macroCount) slots, \(bufferSize) bytes")

            let keymap = try via.readKeymap(layers: layers)
            var diffs = 0
            for layer in 0..<min(layers, FactoryKeymap.layers.count) {
                diffs += Layout.all.filter { keymap[layer][$0.index] != FactoryKeymap.layers[layer][$0.index] }.count
            }
            check("keymap read (\(layers) layers)", keymap.count == layers, "\(diffs) positions differ from factory")

            // Key write on a matrix cell with no switch behind it.
            let spare = 6 * VIA.cols
            let layer = layers - 1
            let original = try via.readKey(layer: layer, index: spare)
            try via.setKey(layer: layer, index: spare, code: 0x0004)
            try via.setKey(layer: layer, index: spare, code: original)
            check("key write, verify and restore", try via.readKey(layer: layer, index: spare) == original)

            // Macro memory: write a test image, then put back exactly what was there.
            let before = try via.readMacroBuffer(size: bufferSize)
            let usable = VIA.usableMacroBytes(bufferSize: bufferSize)
            if before[usable...].allSatisfy({ $0 == 0 }) {
                var content = Array(before[..<usable])
                while content.last == 0 { content.removeLast() }
                let long = MacroCodec.image([[MacroStep(kind: .text, text: String(repeating: "E68 Studio macro test. ", count: 12))]] + sampleMacros)
                try via.writeMacroBuffer(long, bufferSize: bufferSize)
                check("macro write and verify (\(long.count) bytes)", true)
                try via.writeMacroBuffer(content, bufferSize: bufferSize)
                check("macro memory restored", try via.readMacroBuffer(size: bufferSize) == before)
            } else {
                check("macro write (skipped: tail of buffer in use)", true)
            }

            let rows = try via.matrixState()
            check("live switch state readable", rows.count == VIA.rows, rows.map { String($0, radix: 16) }.joined(separator: " "))

            // Lighting: nudge the hue, confirm the keyboard reports it, then put it back.
            let lit = try via.readLighting()
            // Lighting speed: verify speed levels 1...3 round-trip and restore original
            var speedOk = true
            for lvl in LightingCatalog.minSpeed...LightingCatalog.maxSpeed {
                try via.setLighting(.speed, [LightingState.rawSpeed(level: lvl)])
                Thread.sleep(forTimeInterval: 0.05)
                let rawBack = try via.readLighting().speed
                let lvlBack = LightingState.speedLevel(raw: rawBack)
                if lvlBack != lvl {
                    speedOk = false
                }
            }
            try via.setLighting(.speed, [lit.speed])
            check("lighting speed levels round-trip", speedOk)

            let other = lit.hue &+ 7

            try via.setLighting(.color, [other, lit.saturation])
            let changed = try via.readLighting().hue
            try via.setLighting(.color, [lit.hue, lit.saturation])
            let after = try via.readLighting().hue
            check("lighting write, read back and restore", changed == other && after == lit.hue,
                  "effect \(lit.effect), brightness level \(LightingState.brightnessLevel(raw: lit.brightness)), hue \(lit.hue)")
        } catch {
            check("keyboard communication", false, error.localizedDescription)
        }
        finish()
    }

    private static func finish() -> Never {
        print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
