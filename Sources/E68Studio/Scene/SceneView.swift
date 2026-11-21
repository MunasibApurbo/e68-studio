import SwiftUI
import SceneKit
import MetalKit

enum DeskCameraPreset: String, CaseIterable, Identifiable {
    case front = "Front"
    case angle = "3/4"
    case top = "Top"

    var id: Self { self }

    var pose: KeyboardScene.Pose {
        switch self {
        case .front: return KeyboardScene.homePose
        case .angle: return KeyboardScene.deskAnglePose
        case .top: return KeyboardScene.deskTopPose
        }
    }
}

/// Hosts the 3D desk and keeps it in step with the store.
struct SceneView: NSViewRepresentable {
    @ObservedObject var store: KeyboardStore
    var deskPreset: DeskCameraPreset = .front
    @ObservedObject private var remapper = MouseRemapper.shared
    @ObservedObject private var mouse = MouseStore.shared
    @ObservedObject private var mirror = LiveMirror.shared
    @AppStorage(AmbienceKeys.deskLampOn) private var deskLampOn = true
    @AppStorage(AmbienceKeys.deskMood) private var deskMood: DeskMood = .daylight
    @AppStorage(AmbienceKeys.deskScenario) private var deskScenario: DeskScenario = .swissAlps
    @AppStorage(DeskWallpaperKeys.token) private var monitorWallpaperToken = ""
    @AppStorage(AmbienceKeys.deskLampBrightness) private var deskLampBrightness = 1.0
    @AppStorage(AmbienceKeys.deskLampColor) private var deskLampColor: DeskLampColor = .warm

    func makeCoordinator() -> KeyboardScene { KeyboardScene() }

    func makeNSView(context: Context) -> InteractiveSceneView {
        let view = InteractiveSceneView()
        context.coordinator.audioMonitor = store.audioMonitor
        view.backgroundColor = .black
        view.wantsLayer = true
        view.world = context.coordinator
        view.store = store
        context.coordinator.applyMonitorWallpaper(token: monitorWallpaperToken)
        view.installPathTracerIfSupported()
        if !view.usesPathTracer {
            // SceneKit only gets the scene when it is the renderer. Handing it over and taking it back
            // made SceneKit compile every material and upload every texture a second time at launch.
            view.scene = context.coordinator.scene
            view.pointOfView = context.coordinator.cameraNode
            view.delegate = context.coordinator
            view.antialiasingMode = .multisampling4X
            view.preferredFramesPerSecond = 60
            view.rendersContinuously = true
            view.isPlaying = true
        }
        context.coordinator.onRenderIdleChanged = { [weak view] _ in
            view?.wakeForSceneCheck()
        }
        MouseRemapper.shared.onWheel = { [weak world = context.coordinator, weak store, weak view] up in
            if E68Perf.enabled, UserDefaults.standard.string(forKey: "e68.perfScript") != nil { return }
            let mirroring = LiveMirror.shared.enabled && store?.inStudio == false
            guard store?.inMouseStudio == true || mirroring else { return }
            world?.spinMouseWheel(up: up)
            view?.wakeForSceneCheck()
        }
        return view
    }

    func updateNSView(_ view: InteractiveSceneView, context: Context) {
        let world = context.coordinator
        world.audioMonitor = store.audioMonitor

        let inKeyboard = store.inKeyboardStudio
        let isKeysSection = inKeyboard && store.section == .keys
        let effective = store.effectiveLayer
        let layer = isKeysSection ? store.activeLayer : effective
        let showLiveLegends = inKeyboard || effective != store.activeLayer
        let keymapLayer = showLiveLegends && layer < store.keymap.count ? store.keymap[layer] : []
        if view.lastInKeyboardStudio != showLiveLegends
            || view.lastIsKeysSection != isKeysSection
            || view.lastActiveLayer != layer
            || (showLiveLegends && (view.lastKeymapLayer != keymapLayer || view.lastMacroNames != store.macroNames)) {
            view.lastInKeyboardStudio = showLiveLegends
            view.lastIsKeysSection = isKeysSection
            view.lastActiveLayer = layer
            view.lastKeymapLayer = keymapLayer
            view.lastMacroNames = showLiveLegends ? store.macroNames : []
            world.setLegends(Self.legends(for: store, layer: layer, showLiveLegends: showLiveLegends, isKeysSection: isKeysSection))
        }

        world.applyMonitorWallpaper(token: monitorWallpaperToken)
        world.setDeskLampLight(color: deskLampColor, brightness: Float(deskLampBrightness))
        if !E68Perf.enabled || view.perfScenarioOverride == nil {
            world.setAmbience(deskLampOn: deskLampOn, mood: deskMood, scenario: deskScenario)
        }
        let isScriptedPerf = E68Perf.enabled && UserDefaults.standard.string(forKey: "e68.perfScript") != nil
        world.setSelection(inKeyboard && store.section == .keys ? store.selection?.index : nil)
        // On the desk, Live Mirror presses the model's keys as you type in other apps.
        let mirroring = mirror.enabled && !store.inStudio
        world.setPressed(isScriptedPerf ? [] : store.pressed.union(store.flashing).union(mirroring ? mirror.pressed : []))
        world.setMarked(inKeyboard && store.section == .test && !store.showHeatmap ? store.tested : [])
        let showHeatmap = inKeyboard && store.section == .test && store.showHeatmap
        world.setHeatmap(showHeatmap ? store.normalizedHeatmap : [:], active: showHeatmap)
        if !E68Perf.enabled || view.perfLightingOverride == nil {
            world.setLighting(store.lighting)
        }
        let inMouse = store.inMouseStudio
        let paletteCount = DPIStage.palette.count
        let rawColorIdx = mouse.currentStage?.colorIndex ?? 3
        let colorIdx = ((rawColorIdx % paletteCount) + paletteCount) % paletteCount
        let stageColor = mouse.sniperActive ? NSColor.white : DPIStage.palette[colorIdx]
        world.setMouseVisual(pressed: isScriptedPerf ? [] : (inMouse || mirroring ? remapper.held : []),
                             led: isScriptedPerf ? nil : (inMouse && mouse.customEnabled ? stageColor : nil))

        if store.knobCWCount > view.lastKnobCWCount {
            world.turnKnob(clockwise: true)
            view.lastKnobCWCount = store.knobCWCount
        } else if store.knobCWCount < view.lastKnobCWCount {
            view.lastKnobCWCount = store.knobCWCount
        }
        if store.knobCCWCount > view.lastKnobCCWCount {
            world.turnKnob(clockwise: false)
            view.lastKnobCCWCount = store.knobCCWCount
        } else if store.knobCCWCount < view.lastKnobCCWCount {
            view.lastKnobCCWCount = store.knobCCWCount
        }

        // Only steer the camera when the place or desk preset changes, so the user's own orbiting is kept.
        let place = store.inMouseStudio ? "mouse-\(store.mouseSection.rawValue)"
            : store.inStudio ? store.section.rawValue : "home-\(deskPreset.rawValue)"
        if place != view.lastPlace {
            let first = view.lastPlace == nil
            view.lastPlace = place
            var goal = store.inMouseStudio ? MouseSpot.pose(for: store.mouseSection)
                : store.inStudio ? store.section.studioPose : deskPreset.pose
            // `-e68.view "x y z yaw pitch distance"` aims the camera anywhere, for renders of props.
            if let raw = UserDefaults.standard.string(forKey: "e68.view") {
                let v = raw.split(separator: " ").compactMap { Float($0) }
                if v.count == 6 {
                    goal = KeyboardScene.Pose(target: SIMD3(v[0], v[1], v[2]), distance: v[5],
                                              pitch: v[4] * .pi / 180, yaw: v[3] * .pi / 180, fov: 30)
                }
            }
            world.setGoal(goal, immediately: first)
        }

        view.wakeForSceneCheck()
    }

    /// On the desk the caps show what is printed on them (or the live Fn layer while held); in the studio they show physical Layer 0 caps or live layer mappings.
    static func legends(for store: KeyboardStore, layer: Int? = nil, showLiveLegends: Bool? = nil, isKeysSection: Bool? = nil) -> [Int: Legend] {
        let targetLayer = layer ?? store.activeLayer
        let live = showLiveLegends ?? store.inKeyboardStudio
        let keysStudio = isKeysSection ?? (store.inKeyboardStudio && store.section == .keys)
        var out = [Int: Legend](minimumCapacity: Layout.keys.count)
        let printed = FactoryKeymap.layers[min(2, FactoryKeymap.layers.count - 1)]
        let usePrintedLayer0 = live && keysStudio && targetLayer == 0
        for slot in Layout.keys {
            if !live {
                out[slot.index] = LegendPainter.printed(printed[slot.index])
            } else if usePrintedLayer0 && !store.isModified(layer: 0, slot) {
                out[slot.index] = LegendPainter.printed(store.code(layer: 0, slot))
            } else {
                out[slot.index] = store.legend(layer: targetLayer, slot)
            }
        }
        return out
    }
}

/// Where the MCHOSE G7 sits on the desk (matches the model placed in TechProps), and the
/// close-ups used to configure it. Like the keyboard studio, the camera shifts so the mouse
/// stays clear of each section's panel: side panels sit on the right, wide ones at the bottom.
enum MouseSpot {
    static var center: SIMD3<Float> { SIMD3(12.6, DeskRoomAndMat.matTopY + 1.1, -0.6) }
    /// Rough half-length of the mouse in scene units, for screen-space hit testing.
    static let radius: Float = 3.4

    static func pose(for section: MouseSection) -> KeyboardScene.Pose {
        // `-e68.mouseView "yaw pitch distance"` (degrees, units) frames the mouse for renders.
        if let view = UserDefaults.standard.string(forKey: "e68.mouseView") {
            let v = view.split(separator: " ").compactMap { Float($0) }
            if v.count == 3 {
                return KeyboardScene.Pose(target: center + SIMD3(0, -0.2, 0), distance: v[2],
                                          pitch: v[1] * .pi / 180, yaw: v[0] * .pi / 180, fov: 30)
            }
        }
        switch section {
        case .test:
            // Closer with a subtle side angle so all five buttons (including thumb buttons) are clear above the HUD.
            return KeyboardScene.Pose(target: center + SIMD3(0, -0.3, 1.6), distance: 25,
                                      pitch: 46 * .pi / 180, yaw: -0.32, fov: 36)
        case .dpi, .scroll:
            return KeyboardScene.Pose(target: center + SIMD3(3.1, -0.5, 0.5), distance: 30,
                                      pitch: 46 * .pi / 180, yaw: -0.30, fov: 36)
        case .buttons:
            // Slightly lower and more angled so the Back and Forward side buttons stand out clearly.
            return KeyboardScene.Pose(target: center + SIMD3(3.1, -0.5, 0.5), distance: 29,
                                      pitch: 42 * .pi / 180, yaw: -0.42, fov: 36)
        case .more:
            return KeyboardScene.Pose(target: center + SIMD3(0, -0.4, 8.4), distance: 40,
                                      pitch: 42 * .pi / 180, yaw: -0.26, fov: 40)
        }
    }
}

extension StudioSection {
    /// Camera pose that keeps the full keyboard unobstructed by this section's floating panel.
    var studioPose: KeyboardScene.Pose {
        switch self {
        case .test:
            return KeyboardScene.studioPose(offset: SIMD3(0, 0, 1.2), distance: 33, pitchDegrees: 56, fov: 38)
        case .keys, .light:
            return KeyboardScene.studioPose(offset: SIMD3(4.4, 0, 0.4), distance: 40, pitchDegrees: 54, fov: 40)
        case .macros, .more:
            return KeyboardScene.studioPose(offset: SIMD3(0, 0, 6.5), distance: 40, pitchDegrees: 50, fov: 40)
        }
    }
}

private final class RTCanvasView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class InteractiveSceneView: SCNView, MTKViewDelegate {
    weak var world: KeyboardScene?
    weak var store: KeyboardStore?
    var lastPlace: String?
    var lastKnobCWCount = 0
    var lastKnobCCWCount = 0
    var lastInKeyboardStudio: Bool?
    var lastIsKeysSection = false
    var lastActiveLayer = -1
    var lastKeymapLayer: [UInt16] = []
    var lastMacroNames: [String] = []

    private var rtView: RTCanvasView?
    private var pathTracer: PathTracerRenderer?
    var usesPathTracer: Bool { pathTracer != nil }
    private var downPoint: NSPoint?
    private var dragged = false
    private var visibilityObservers: [NSObjectProtocol] = []
    var perfLightingOverride: LightingState?
    var perfScenarioOverride: (DeskScenario, DeskMood)?
    private var perfScriptStarted = false
    private var perfTimers: [Timer] = []

    deinit {
        for t in perfTimers { t.invalidate() }
        for observer in visibilityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func installPathTracerIfSupported() {
        let installT0 = E68Perf.enabled ? CACurrentMediaTime() : 0
        guard pathTracer == nil,
              let dev = MTLCreateSystemDefaultDevice(),
              PathTracerRenderer.isSupported(device: dev),
              let tracer = PathTracerRenderer(device: dev) else { return }

        let canvas = RTCanvasView(frame: bounds, device: dev)
        canvas.autoresizingMask = [.width, .height]
        canvas.colorPixelFormat = .bgra8Unorm
        canvas.framebufferOnly = false
        canvas.preferredFramesPerSecond = 60
        canvas.enableSetNeedsDisplay = false
        canvas.isPaused = false
        canvas.clearColor = MTLClearColorMake(0.05, 0.05, 0.06, 1.0)
        canvas.delegate = self
        addSubview(canvas)

        // SceneKit stays idle while hardware ray tracing draws the desk.
        isPlaying = false
        rendersContinuously = false

        pathTracer = tracer
        rtView = canvas
        world?.usesHardwareRayTracer = true
        tracer.onProgressiveSettled = { [weak self] _ in
            self?.updateRenderingState()
        }
        if E68Perf.enabled {
            E68Perf.logLine(String(format: "installPathTracerIfSupported: %.1f ms (since launch: %.1f ms)",
                                   (CACurrentMediaTime() - installT0) * 1000.0,
                                   (CACurrentMediaTime() - E68Perf.processStartTime) * 1000.0))
        }
        updateRenderingState()
        startPerfScriptIfNeeded()
    }

    private func startPerfScriptIfNeeded() {
        guard E68Perf.enabled, !perfScriptStarted,
              let script = UserDefaults.standard.string(forKey: "e68.perfScript") else { return }
        perfScriptStarted = true

        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.makeKeyAndOrderFront(nil)
            if self?.window?.frame.size.width ?? 0 < 1200 {
                self?.window?.setContentSize(NSSize(width: 1280, height: 800))
            }
            self?.updateRenderingState()
        }

        var staticLit = LightingState()
        staticLit.effect = 6
        staticLit.brightness = 8
        staticLit.hue = 140
        staticLit.saturation = 255

        if script == "idle" || script == "orbit" {
            perfLightingOverride = staticLit
            perfScenarioOverride = (.swissAlps, .daylight)
            world?.setLighting(staticLit)
            world?.setAmbience(deskLampOn: true, mood: .daylight, scenario: .swissAlps)
            wakeFromSceneChange()
        } else if script == "backlight" {
            var wave = LightingState()
            wave.effect = 1
            wave.brightness = 9
            wave.speed = 2
            perfLightingOverride = wave
            perfScenarioOverride = (.swissAlps, .daylight)
            world?.setLighting(wave)
            world?.setAmbience(deskLampOn: true, mood: .daylight, scenario: .swissAlps)
            wakeFromSceneChange()
        } else if script == "scenarios" {
            perfLightingOverride = staticLit
            world?.setLighting(staticLit)
        }

        // Wait until the first 2 frames have rendered so startup/alloc doesn't skew steady-state windows.
        let waitTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self, let pt = self.pathTracer, pt.frameIndex >= 2 else { return }
            timer.invalidate()
            self.beginPerfScriptPhase(script, staticLit: staticLit)
        }
        perfTimers.append(waitTimer)
    }

    private func beginPerfScriptPhase(_ script: String, staticLit: LightingState) {
        switch script {
        case "idle":
            let checkTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] t in
                guard let self, let pt = self.pathTracer else { t.invalidate(); return }
                if pt.isSettledForSleep && (self.rtView?.isPaused ?? false) {
                    t.invalidate()
                    E68Perf.flushWindow(label: "idle-settled sample=\(pt.sampleIndex) paused=\(self.rtView?.isPaused ?? true)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        E68Perf.flushWindow(label: "before-noop-wake sample=\(self?.pathTracer?.sampleIndex ?? 0) paused=\(self?.rtView?.isPaused ?? true)")
                        NotificationCenter.default.post(name: Notification.Name("E68SceneNeedsRender"), object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                            E68Perf.flushWindow(label: "after-noop-wake sample=\(self?.pathTracer?.sampleIndex ?? 0) paused=\(self?.rtView?.isPaused ?? true)")
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 29.0) { [weak self] in
                        E68Perf.flushWindow(label: "idle-30s sample=\(self?.pathTracer?.sampleIndex ?? 0) paused=\(self?.rtView?.isPaused ?? true)")
                        exit(0)
                    }
                }
            }
            perfTimers.append(checkTimer)

        case "orbit":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                E68Perf.flushWindow(label: "pre-orbit")
                let start = CACurrentMediaTime()
                let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                    guard let self else { timer.invalidate(); return }
                    if CACurrentMediaTime() - start < 5.0 {
                        self.world?.orbit(dx: 3.5, dy: 0.4, deskMode: true)
                        self.updateRenderingState()
                    } else {
                        timer.invalidate()
                        E68Perf.flushWindow(label: "orbit-5s")
                        // Now wait for camera + progressive settle
                        let settlePoll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] st in
                            guard let self, let pt = self.pathTracer else { st.invalidate(); return }
                            if pt.isSettledForSleep && (self.rtView?.isPaused ?? false) {
                                st.invalidate()
                                E68Perf.flushWindow(label: "post-orbit-settled sample=\(pt.sampleIndex) paused=\(self.rtView?.isPaused ?? true)")
                                exit(0)
                            }
                        }
                        self.perfTimers.append(settlePoll)
                    }
                }
                self.perfTimers.append(t)
            }

        case "backlight":
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                E68Perf.flushWindow(label: "backlight-warmup")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    E68Perf.flushWindow(label: "backlight-5s")
                    exit(0)
                }
            }

        case "scenarios":
            let list = DeskScenario.allCases
            var idx = 0
            func stepNext() {
                if idx > 0 {
                    E68Perf.flushWindow(label: "scenario-\(list[idx - 1].rawValue)")
                }
                guard idx < list.count else {
                    self.world?.setAmbience(deskLampOn: true, mood: .midnight, scenario: .room)
                    self.wakeFromSceneChange()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        E68Perf.flushWindow(label: "scenarios-complete")
                        exit(0)
                    }
                    return
                }
                let sc = list[idx]
                self.perfScenarioOverride = (sc, .daylight)
                self.world?.setAmbience(deskLampOn: true, mood: .daylight, scenario: sc)
                self.wakeFromSceneChange()
                idx += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    stepNext()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                stepNext()
            }

        default:
            break
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if size.height > 0 {
            world?.setViewAspect(Float(size.width / size.height))
        }
        pathTracer?.invalidateAccumulation(resetTemporalHistory: true)
        updateRenderingState()
    }

    func draw(in view: MTKView) {
        guard let world, let pathTracer else { return }
        let targetFPS = (PathTracerRenderer.liveMode || world.wantsHighFrameRate) ? 60 : 30
        if view.preferredFramesPerSecond != targetFPS {
            view.preferredFramesPerSecond = targetFPS
        }
        pathTracer.draw(in: view, world: world)
    }

    func wakeFromSceneChange() {
        pathTracer?.invalidateAccumulation(resetTemporalHistory: false)
        updateRenderingState()
    }

    func wakeForSceneCheck() {
        pathTracer?.wakeForCheckOnly(world: world)
        updateRenderingState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncBackingScale()
        for observer in visibilityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        visibilityObservers.removeAll()

        if let window {
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didBecomeMainNotification,
                NSWindow.willCloseNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
            ]
            for name in names {
                visibilityObservers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        self?.updateRenderingState()
                    }
                )
            }
            for appName in [NSApplication.didHideNotification, NSApplication.didUnhideNotification, NSApplication.didBecomeActiveNotification] {
                visibilityObservers.append(
                    NotificationCenter.default.addObserver(forName: appName, object: nil, queue: .main) { [weak self] _ in
                        self?.updateRenderingState()
                    }
                )
            }
            visibilityObservers.append(
                NotificationCenter.default.addObserver(
                    forName: Notification.Name("E68SceneNeedsRender"),
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.wakeForExternalSceneChange()
                }
            )
            if E68Perf.enabled, UserDefaults.standard.string(forKey: "e68.perfScript") != nil {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                if window.frame.size.width < 1200 {
                    window.setContentSize(NSSize(width: 1280, height: 800))
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.updateRenderingState()
            }
        }
        updateRenderingState()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncBackingScale()
    }

    private func syncBackingScale() {
        wantsLayer = true
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        if layer?.contentsScale != scale {
            layer?.contentsScale = scale
        }
    }

    private var isViewVisible: Bool {
        if (pathTracer?.frameIndex ?? 0) < 2 {
            return window != nil
                && window?.isMiniaturized == false
                && !NSApp.isHidden
        }
        return window != nil
            && window?.isVisible == true
            && window?.isMiniaturized == false
            && window?.occlusionState.contains(.visible) == true
            && !NSApp.isHidden
    }

    private func wakeForExternalSceneChange() {
        guard isViewVisible, let world else { return }
        pathTracer?.wakeForCheckOnly(world: world)
        if world.needsContinuousRender || pathTracer != nil {
            updateRenderingState()
        } else {
            setNeedsDisplay(bounds)
        }
    }

    func updateRenderingState() {
        guard isViewVisible, let world else {
            rtView?.isPaused = true
            if rendersContinuously { rendersContinuously = false }
            if isPlaying { isPlaying = false }
            return
        }

        if let rtView, let pathTracer {
            let targetFPS = (PathTracerRenderer.liveMode || world.wantsHighFrameRate) ? 60 : 30
            if rtView.preferredFramesPerSecond != targetFPS {
                rtView.preferredFramesPerSecond = targetFPS
            }
            let active = world.needsContinuousRender || !pathTracer.isSettledForSleep
            if rtView.isPaused == active {
                rtView.isPaused = !active
            }
            return
        }

        if world.needsContinuousRender {
            if !isPlaying { isPlaying = true }
            if !rendersContinuously { rendersContinuously = true }
        } else {
            if rendersContinuously || isPlaying {
                rendersContinuously = false
                isPlaying = false
                setNeedsDisplay(bounds)
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize.height > 0 { world?.setViewAspect(Float(newSize.width / newSize.height)) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, let store else { return }
        let p = convert(event.locationInWindow, from: nil)
        // A finger wobbles more than a pointer, so taps get a wider slop before they become orbits.
        if hypot(p.x - start.x, p.y - start.y) > 7 { dragged = true }
        if dragged {
            world?.orbit(dx: Float(event.deltaX), dy: Float(event.deltaY), deskMode: !store.inStudio)
            updateRenderingState()
        }
    }

    private func pickSceneTarget(at point: CGPoint) -> (firstNode: SCNNode?, resolvedKey: Int?) {
        if let rt = pathTracer, let world {
            guard let picked = rt.pickNode(at: point, in: bounds.size, world: world),
                  world.isScenarioNode(picked) != true else {
                return (nil, nil)
            }
            var n: SCNNode? = picked
            while let cur = n {
                if let idx = KeyboardScene.keyIndex(of: cur) { return (picked, idx) }
                n = cur.parent
            }
            return (picked, nil)
        }
        let hits = hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            .filter { world?.isScenarioNode($0.node) != true }
        let resolvedKey = hits.lazy.compactMap { KeyboardScene.keyIndex(of: $0.node) }.first
        return (hits.first?.node, resolvedKey)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let store, !store.inStudio else { return super.menu(for: event) }
        let point = convert(event.locationInWindow, from: nil)
        let (firstNode, _) = pickSceneTarget(at: point)
        guard KeyboardScene.deskProp(of: firstNode) == .monitor else {
            return super.menu(for: event)
        }
        let hasCustom = !(UserDefaults.standard.string(forKey: DeskWallpaperKeys.token) ?? "").isEmpty
        let menu = NSMenu()
        menu.autoenablesItems = false
        let chooseItem = NSMenuItem(title: "Choose Wallpaper…", action: #selector(chooseMonitorWallpaper), keyEquivalent: "")
        chooseItem.target = self
        menu.addItem(chooseItem)
        let resetItem = NSMenuItem(title: "Reset Wallpaper", action: #selector(resetMonitorWallpaper), keyEquivalent: "")
        resetItem.target = self
        resetItem.isEnabled = hasCustom
        menu.addItem(resetItem)
        return menu
    }

    @objc private func chooseMonitorWallpaper() {
        MonitorWallpaperStore.pickWallpaper()
        refreshMonitorWallpaper()
    }

    @objc private func resetMonitorWallpaper() {
        MonitorWallpaperStore.resetWallpaper()
        refreshMonitorWallpaper()
    }

    private func refreshMonitorWallpaper() {
        let token = UserDefaults.standard.string(forKey: DeskWallpaperKeys.token) ?? ""
        world?.applyMonitorWallpaper(token: token)
        setNeedsDisplay(bounds)
        wakeFromSceneChange()
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        guard !dragged, let store else { return }
        let point = convert(event.locationInWindow, from: nil)
        let (firstNode, resolvedKey) = pickSceneTarget(at: point)

        let onKeyboard = firstNode.map { world?.isKeyboard($0) == true } ?? false
        let onMouse = firstNode.map { world?.isMouse($0) == true } ?? false
        // Tapping an object opens its studio: keyboard or mouse, from the desk or from the other studio.
        if onKeyboard && !store.inKeyboardStudio {
            store.enterStudio()
            return
        }
        if onMouse && !store.inMouseStudio {
            store.enterMouseStudio()
            return
        }
        // Desk props: the monitor cycles its wallpaper, each lamp switches on and off.
        if !store.inStudio, let prop = KeyboardScene.deskProp(of: firstNode) {
            handleDeskProp(prop)
            return
        }
        guard store.inKeyboardStudio else { return }
        if store.section == .keys, let key = resolvedKey {
            if key == Layout.knobPress.index {
                if store.selection == Layout.knobPress {
                    store.selection = Layout.knobCW
                } else if store.selection == Layout.knobCW {
                    store.selection = Layout.knobCCW
                } else {
                    store.selection = Layout.knobPress
                }
            } else if let slot = Layout.slot(at: key) {
                store.selection = slot
            }
            world?.pressKey(key)
            wakeFromSceneChange()
        } else if store.section == .light, let key = resolvedKey {
            world?.pressKey(key)
            world?.triggerReactive(key: key)
            wakeFromSceneChange()
        }
    }

    private func handleDeskProp(_ prop: KeyboardScene.DeskProp) {
        let defaults = UserDefaults.standard
        let lampOn: Bool
        switch prop {
        case .monitor:
            MonitorWallpaperStore.cycleWallpaper { [weak self] in
                self?.refreshMonitorWallpaper()
            }
            return
        case .deskLamp:
            let current = (defaults.object(forKey: AmbienceKeys.deskLampOn) as? Bool) ?? true
            lampOn = !current
            defaults.set(lampOn, forKey: AmbienceKeys.deskLampOn)
        }
        let mood = defaults.string(forKey: AmbienceKeys.deskMood).flatMap(DeskMood.init(rawValue:)) ?? .daylight
        let scenario = defaults.string(forKey: AmbienceKeys.deskScenario).flatMap(DeskScenario.init(rawValue:)) ?? .swissAlps
        world?.setAmbience(deskLampOn: lampOn,
                           mood: mood,
                           scenario: scenario)
        setNeedsDisplay(bounds)
        wakeFromSceneChange()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let store else { return }
        if event.hasPreciseScrollingDeltas {
            // Trackpad / touch: sideways swipes orbit, vertical swipes zoom.
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5 {
                world?.orbit(dx: Float(-event.scrollingDeltaX * 0.5), dy: 0, deskMode: !store.inStudio)
            } else {
                world?.zoom(by: Float(min(max(1 + event.scrollingDeltaY * -0.004, 0.6), 1.4)), deskMode: !store.inStudio)
            }
        } else {
            // Mouse wheels report whole lines, not pixels; scale up so a notch does something visible.
            world?.zoom(by: Float(min(max(1 + event.scrollingDeltaY * -0.04, 0.6), 1.4)), deskMode: !store.inStudio)
        }
        updateRenderingState()
    }

    override func rotate(with event: NSEvent) {
        guard let store else { return }
        world?.orbit(dx: Float(-event.rotation * 2), dy: 0, deskMode: !store.inStudio)
        updateRenderingState()
    }

    override func magnify(with event: NSEvent) {
        guard let store else { return }
        world?.zoom(by: Float(1 - event.magnification), deskMode: !store.inStudio)
        updateRenderingState()
    }
}
