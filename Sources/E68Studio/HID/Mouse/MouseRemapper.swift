import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Live mouse-button test results, shown in the Test tab.
@MainActor
final class MouseTestModel: ObservableObject {
    @Published var pressed: Set<Int> = []
    @Published var counts: [Int: Int] = [:]
    @Published var wheelUp = 0
    @Published var wheelDown = 0
    @Published var reportRate = 0
    @Published var peakRate = 0
    @Published var lastDoubleClickMS: Int?
    @Published var chatterCount = 0

    func reset() {
        pressed = []; counts = [:]; wheelUp = 0; wheelDown = 0
        reportRate = 0; peakRate = 0; lastDoubleClickMS = nil; chatterCount = 0
    }
}

/// Accumulates fractional discrete scroll-wheel notches per axis so sub-1× and fractional
/// multipliers (0.25×, 0.5×, 0.75×, 1.25×) scale smoothly across ticks.
struct ScrollScaler {
    struct AxisState {
        var remainder: Double = 0
        var lastTimestampNs: UInt64 = 0
        var lastSign: Int = 0
    }

    static let idleResetNs: UInt64 = 500_000_000

    var axis1 = AxisState()
    var axis2 = AxisState()

    mutating func reset() {
        axis1 = AxisState()
        axis2 = AxisState()
    }

    mutating func scaleAxis1(lines: Int64, multiplier: Double, nowNs: UInt64) -> Int64 {
        Self.scale(lines: lines, multiplier: multiplier, nowNs: nowNs, state: &axis1)
    }

    mutating func scaleAxis2(lines: Int64, multiplier: Double, nowNs: UInt64) -> Int64 {
        Self.scale(lines: lines, multiplier: multiplier, nowNs: nowNs, state: &axis2)
    }

    private static func scale(lines: Int64, multiplier k: Double, nowNs: UInt64, state: inout AxisState) -> Int64 {
        guard lines != 0 else { return 0 }
        if state.lastTimestampNs > 0, nowNs > state.lastTimestampNs, nowNs - state.lastTimestampNs > idleResetNs {
            state.remainder = 0
            state.lastSign = 0
        }
        let scaled = Double(lines) * k
        let sign = scaled > 0 ? 1 : (scaled < 0 ? -1 : 0)
        if state.lastSign != 0, sign != 0, sign != state.lastSign {
            state.remainder = 0
        }
        let total = state.remainder + scaled
        let whole = Int64(trunc(total))
        state.remainder = total - Double(whole)
        state.lastSign = sign
        state.lastTimestampNs = nowNs
        return whole
    }
}

/// Filters switch chatter (a press arriving within N ms of the same button's release)
/// and tracks suppressed buttons so their matching release is also suppressed.
struct ButtonDebounceTracker {
    private(set) var lastUp: [Int: UInt64] = [:]
    private(set) var debounced: Set<Int> = []

    mutating func shouldSuppress(button: Int, isDown: Bool, nowNs: UInt64, debounceMS: Int) -> Bool {
        if isDown {
            if debounceMS > 0, let up = lastUp[button], nowNs > up, nowNs - up < UInt64(debounceMS) * 1_000_000 {
                debounced.insert(button)
                return true
            }
            debounced.remove(button)
            return false
        }
        if debounced.remove(button) != nil {
            return true
        }
        lastUp[button] = nowNs
        return false
    }

    mutating func clearActive() {
        debounced.removeAll()
    }

    mutating func reset() {
        lastUp.removeAll()
        debounced.removeAll()
    }
}

/// Computes mouse report rate (Hz) across a rolling 250ms window, preserving short bursts
/// that finish before the next UI timer tick.
struct PollingRateMeter {
    static let idleTimeoutNs: UInt64 = 150_000_000
    static let windowNs: UInt64 = 250_000_000

    private(set) var stamps: [UInt64] = []

    mutating func record(nowNs: UInt64) {
        stamps.append(nowNs)
    }

    mutating func sample(nowNs: UInt64) -> (currentRate: Int?, sampledPeak: Int?) {
        guard let last = stamps.last else { return (0, nil) }
        let windowStart = last > Self.windowNs ? last - Self.windowNs : 0
        stamps.removeAll { $0 < windowStart }
        var computedRate: Int?
        if stamps.count > 4, let first = stamps.first, last > first {
            computedRate = Int(Double(stamps.count - 1) / (Double(last - first) / 1e9))
        }
        if nowNs > last, nowNs - last > Self.idleTimeoutNs {
            stamps.removeAll()
            return (0, computedRate)
        }
        return (computedRate, computedRate)
    }

    mutating func reset() {
        stamps.removeAll()
    }
}

/// One active event tap that gives the G7 what vendor mouse software usually does on the mouse
/// itself: button remapping, DPI stage switching, wheel direction and speed, click debounce and a
/// report-rate meter. Needs Accessibility permission; without it nothing is intercepted.
@MainActor
final class MouseRemapper: ObservableObject {
    static let shared = MouseRemapper()

    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var running = false
    /// While the Test tab is open, presses are recorded instead of remapped.
    @Published var testing = false {
        didSet {
            if testing {
                test.reset()
                rateMeter.reset()
                endGesture()
                releaseAllActivePresses(announceSniper: false)
                scrollScaler.reset()
            } else {
                test.pressed.removeAll()
                rateMeter.reset()
            }
            guard oldValue != testing else { return }
            syncTapForTestingState()
        }
    }

    var isTestingActive: Bool {
        testing && appActive && (NSApp?.isActive ?? appActive)
    }

    let test = MouseTestModel()

    /// Physical buttons held right now (0 left … 4 forward), before any remapping.
    @Published private(set) var held: Set<Int> = []
    /// The physical button pressed most recently, with a counter so repeats still register.
    @Published private(set) var lastPress: (button: Int, serial: Int) = (-1, 0)
    /// Wheel notches for the 3D model: positive up, negative down. Cleared by the consumer.
    var onWheel: ((Bool) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var poll: Timer?
    private var terminateObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var appActive: Bool = NSApp?.isActive ?? true
    private var hasPromptedAccess = false
    /// Buttons whose press we swallowed, so the matching release is swallowed too.
    private var swallowed: Set<Int> = []
    private var activePressActions: [Int: MouseAction] = [:]
    private var remappedDragButtons: [(button: Int, target: CGMouseButton)] = []
    private var sniperHeldButtons: Set<Int> = []
    private var lastDown: [Int: UInt64] = [:]
    private var previousDown: [Int: UInt64] = [:]
    private var debounceTracker = ButtonDebounceTracker()
    private var rateMeter = PollingRateMeter()
    private var scrollScaler = ScrollScaler()
    private var rateTimer: Timer?
    private var gestureWatchdog: Timer?

    /// A gesture button held right now: how far the mouse has moved since, and whether it fired.
    private struct GestureState {
        let button: MouseButton
        var dx: Double = 0
        var dy: Double = 0
        var fired = false
    }
    private var gesture: GestureState?
    /// The direction the last gesture fired, for the Buttons panel to light up.
    @Published private(set) var lastGesture: (button: MouseButton, direction: GestureMap.Direction, serial: Int)?

    private static let activeMask: CGEventMask = [
        CGEventType.leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp,
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .scrollWheel,
    ].reduce(0) { $0 | (1 << $1.rawValue) }

    private var store: MouseStore { MouseStore.shared }

    func start() {
        guard poll == nil else { return }
        appActive = NSApp?.isActive ?? true
        if terminateObserver == nil {
            terminateObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleDidBecomeActive() }
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleDidResignActive() }
            }
        }
        install()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.install() }
        }
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    func stop() {
        if let obs = terminateObserver {
            NotificationCenter.default.removeObserver(obs)
            terminateObserver = nil
        }
        if let obs = activeObserver {
            NotificationCenter.default.removeObserver(obs)
            activeObserver = nil
        }
        if let obs = resignObserver {
            NotificationCenter.default.removeObserver(obs)
            resignObserver = nil
        }
        poll?.invalidate()
        poll = nil
        stopTap()
    }

    private func handleDidBecomeActive() {
        appActive = true
        install()
        syncTapForTestingState()
    }

    private func handleDidResignActive() {
        appActive = false
        if testing {
            test.pressed.removeAll()
            test.reportRate = 0
            rateMeter.reset()
            held.removeAll()
        }
        stopRateTimer()
    }

    private func stopTap() {
        endGesture()
        releaseAllActivePresses(announceSniper: false)
        scrollScaler.reset()
        stopRateTimer()
        if let src = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            source = nil
        }
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
            tap = nil
        }
        if running { running = false }
    }

    func cancelActiveInputs() {
        endGesture()
        releaseAllActivePresses(announceSniper: false)
    }

    func resetTest() {
        rateMeter.reset()
        test.reset()
    }

    func requestAccess() {
        if AXIsProcessTrusted() {
            install()
            return
        }
        if !hasPromptedAccess {
            hasPromptedAccess = true
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            if AXIsProcessTrustedWithOptions([key: true] as CFDictionary) {
                install()
            }
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startRateTimer() {
        guard rateTimer == nil else { return }
        let r = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateRate() }
        }
        RunLoop.main.add(r, forMode: .common)
        rateTimer = r
    }

    private func stopRateTimer() {
        rateTimer?.invalidate()
        rateTimer = nil
    }

    private func syncTapForTestingState() {
        if isTestingActive {
            if tap != nil { startRateTimer() }
        } else {
            stopRateTimer()
        }
    }

    private func install() {
        let nowTrusted = AXIsProcessTrusted()
        if trusted != nowTrusted { trusted = nowTrusted }
        if !nowTrusted {
            if tap != nil { stopTap() }
            if running { running = false }
            return
        }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        guard tap == nil else {
            if !running { running = true }
            return
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.activeMask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            if running { running = false }
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        if !running { running = true }
        if isTestingActive { startRateTimer() } else { stopRateTimer() }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<MouseRemapper>.fromOpaque(info).takeUnretainedValue()
        return MainActor.assumeIsolated {
            me.handle(type, event).map { Unmanaged.passUnretained($0) }
        }
    }

    // MARK: Event handling

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            endGesture()
            releaseAllActivePresses(announceSniper: false)
            scrollScaler.reset()
            return event
        }
        if event.getIntegerValueField(.eventSourceUserData) == ActionPerformer.marker { return event }

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard isTestingActive || gesture != nil || !remappedDragButtons.isEmpty else { return event }
            if isTestingActive {
                rateMeter.record(nowNs: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
                return event
            }
            if gesture != nil {
                trackGesture(event)
                return nil
            }
            if !remappedDragButtons.isEmpty {
                var seenTargets = Set<UInt32>()
                var uniqueTargets: [CGMouseButton] = []
                for entry in remappedDragButtons where seenTargets.insert(entry.target.rawValue).inserted {
                    uniqueTargets.append(entry.target)
                }
                let loc = event.location
                let dx = event.getIntegerValueField(.mouseEventDeltaX)
                let dy = event.getIntegerValueField(.mouseEventDeltaY)
                let nativeMatchesEvent = (type == .leftMouseDragged && uniqueTargets.contains(.left))
                    || (type == .rightMouseDragged && uniqueTargets.contains(.right))
                for target in uniqueTargets {
                    if (type == .leftMouseDragged && target == .left)
                        || (type == .rightMouseDragged && target == .right) {
                        continue
                    }
                    ActionPerformer.drag(target, at: loc, deltaX: dx, deltaY: dy)
                }
                return nativeMatchesEvent ? event : nil
            }
            return event
        case .scrollWheel:
            return scroll(event)
        default:
            break
        }
        // Our own clock: CGEvent timestamps are not guaranteed to be nanoseconds on every Mac.
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let isDown = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown

        // Debounce: a press arriving within N ms of the same button's release is switch chatter.
        if debounceTracker.shouldSuppress(button: button, isDown: isDown, nowNs: now, debounceMS: store.debounceMS) {
            if isDown && isTestingActive { test.chatterCount += 1 }
            return nil
        }
        if isDown { previousDown[button] = lastDown[button]; lastDown[button] = now }
        if isDown {
            if !held.contains(button) { held.insert(button) }
            lastPress = (button, lastPress.serial + 1)
        } else if held.contains(button) {
            held.remove(button)
        }

        if isTestingActive {
            if isDown {
                if test.pressed.insert(button).inserted { test.counts[button, default: 0] += 1 }
                if event.getIntegerValueField(.mouseEventClickState) == 2, let prev = previousDown[button], now > prev {
                    test.lastDoubleClickMS = Int((now - prev) / 1_000_000)
                }
            } else {
                test.pressed.remove(button)
            }
            // Side buttons would trigger browser navigation while testing; keep left/right working.
            return button >= 2 ? nil : event
        }

        guard let mb = MouseButton(rawValue: button) else { return event }
        if !isDown {
            guard swallowed.remove(button) != nil else { return event }
            let pressedAction = activePressActions.removeValue(forKey: button) ?? store.action(for: mb)
            if let g = gesture, g.button == mb {
                finishGesture()
                return nil
            }
            release(pressedAction, button: mb)
            return nil
        }
        let action = store.action(for: mb)
        if action == .standard || (mb == .middle && action == .middleClick) { return event }
        swallowed.insert(button)
        activePressActions[button] = action
        if action == .gesture {
            beginGesture(mb)
            return nil
        }
        press(action, button: mb)
        return nil
    }

    // MARK: Gestures

    private func beginGesture(_ button: MouseButton) {
        endGesture()
        gesture = GestureState(button: button)
        // Freeze the pointer so the hand movement reads as a gesture, not a drag.
        CGAssociateMouseAndMouseCursorPosition(0)
        // Safety watchdog: never leave the cursor frozen if a button-up event is dropped.
        let t = Timer(timeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.endGesture() }
        }
        RunLoop.main.add(t, forMode: .common)
        gestureWatchdog = t
    }

    private func trackGesture(_ event: CGEvent) {
        guard var g = gesture, !g.fired else { return }
        g.dx += Double(event.getIntegerValueField(.mouseEventDeltaX))
        g.dy += Double(event.getIntegerValueField(.mouseEventDeltaY))
        let threshold = Double(max(store.gestureDistance, 10))
        if max(abs(g.dx), abs(g.dy)) >= threshold {
            let direction: GestureMap.Direction = abs(g.dx) > abs(g.dy)
                ? (g.dx > 0 ? .right : .left)
                : (g.dy > 0 ? .down : .up)
            g.fired = true
            let action = store.gestureMap(for: g.button)[direction]
            lastGesture = (g.button, direction, (lastGesture?.serial ?? 0) + 1)
            perform(action, button: g.button)
        }
        gesture = g
    }

    private func finishGesture() {
        guard let g = gesture else { return }
        endGesture()
        guard !g.fired else { return }
        let tap = store.gestureMap(for: g.button).tap
        if tap == .standard {
            ActionPerformer.otherButton(g.button.rawValue)
        } else {
            perform(tap, button: g.button)
        }
    }

    private func endGesture() {
        gestureWatchdog?.invalidate()
        gestureWatchdog = nil
        guard gesture != nil else { return }
        gesture = nil
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// A full press and release of an action, for gestures that fire once.
    private func perform(_ action: MouseAction, button: MouseButton) {
        switch action {
        case .standard, .gesture, .sniper: return
        default:
            press(action, button: button)
            release(action, button: button)
        }
    }

    private func scroll(_ event: CGEvent) -> CGEvent? {
        // Trackpads and Magic Mice send continuous scrolling; only touch real wheels.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return event }
        let d = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        if d != 0 { onWheel?(d > 0) }
        if isTestingActive {
            if d > 0 { test.wheelUp += 1 } else if d < 0 { test.wheelDown += 1 }
            return event
        }
        let sign: Double = store.reverseScroll ? -1 : 1
        let k = store.scrollMultiplier * sign
        guard k != 1 else {
            scrollScaler.reset()
            return event
        }
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let axes: [(intField: CGEventField, fixed: CGEventField, point: CGEventField, isAxis1: Bool)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1, true),
            (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2, false),
        ]
        var hadNonZeroInput = false
        var emittedAnyOutput = false
        for axis in axes {
            // Read all three representations before mutating any of them: CoreGraphics
            // recalculates fixed-point and point deltas whenever the integer line delta is set.
            let lines = event.getIntegerValueField(axis.intField)
            let origFixed = event.getDoubleValueField(axis.fixed)
            let origPoint = event.getIntegerValueField(axis.point)
            guard lines != 0 || origFixed != 0 || origPoint != 0 else { continue }
            hadNonZeroInput = true

            if lines != 0 {
                let scaledLines = axis.isAxis1
                    ? scrollScaler.scaleAxis1(lines: lines, multiplier: k, nowNs: now)
                    : scrollScaler.scaleAxis2(lines: lines, multiplier: k, nowNs: now)
                if scaledLines == 0 {
                    event.setIntegerValueField(axis.intField, value: 0)
                    event.setDoubleValueField(axis.fixed, value: 0)
                    event.setIntegerValueField(axis.point, value: 0)
                    continue
                }
                emittedAnyOutput = true
                let ratio = Double(scaledLines) / Double(lines)
                let scaledFixed = origFixed != 0 ? origFixed * ratio : Double(scaledLines)
                let scaledPoint = origPoint != 0 ? Int64((Double(origPoint) * ratio).rounded()) : 0
                event.setIntegerValueField(axis.intField, value: scaledLines)
                event.setDoubleValueField(axis.fixed, value: scaledFixed)
                event.setIntegerValueField(axis.point, value: scaledPoint)
            } else {
                let scaledFixed = origFixed * k
                var scaledPoint = Int64((Double(origPoint) * k).rounded())
                if origPoint != 0 && scaledPoint == 0 && abs(k) >= 1 {
                    scaledPoint = (Double(origPoint) * k) > 0 ? 1 : -1
                }
                if scaledFixed != 0 || scaledPoint != 0 {
                    emittedAnyOutput = true
                }
                event.setDoubleValueField(axis.fixed, value: scaledFixed)
                event.setIntegerValueField(axis.point, value: scaledPoint)
            }
        }
        if hadNonZeroInput && !emittedAnyOutput {
            return nil
        }
        return event
    }

    private func updateRate() {
        guard isTestingActive else { return }
        let (rate, peak) = rateMeter.sample(nowNs: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        if let peak, peak > test.peakRate { test.peakRate = peak }
        if let rate, test.reportRate != rate { test.reportRate = rate }
    }

    // MARK: Actions

    private func beginRemappedClick(_ target: CGMouseButton, button: MouseButton) {
        let alreadyHeld = remappedDragButtons.contains { $0.target == target }
        remappedDragButtons.removeAll { $0.button == button.rawValue }
        remappedDragButtons.append((button: button.rawValue, target: target))
        if !alreadyHeld {
            ActionPerformer.click(target, down: true)
        }
    }

    private func endRemappedClick(_ target: CGMouseButton, button: MouseButton) {
        remappedDragButtons.removeAll { $0.button == button.rawValue }
        if !remappedDragButtons.contains(where: { $0.target == target }) {
            ActionPerformer.click(target, down: false)
        }
    }

    private func deactivateSniper(announce: Bool) {
        sniperHeldButtons.removeAll()
        store.endSniper(announce: announce)
    }

    private func releaseAllActivePresses(announceSniper: Bool) {
        let activeTargets = Set(remappedDragButtons.map(\.target))
        remappedDragButtons.removeAll()
        for target in activeTargets {
            ActionPerformer.click(target, down: false)
        }
        if !sniperHeldButtons.isEmpty || store.sniperActive {
            deactivateSniper(announce: announceSniper)
        }
        activePressActions.removeAll()
        swallowed.removeAll()
        held.removeAll()
        debounceTracker.clearActive()
    }

    private func press(_ action: MouseAction, button: MouseButton) {
        switch action {
        case .standard, .disabled: break
        case .leftClick: beginRemappedClick(.left, button: button)
        case .rightClick: beginRemappedClick(.right, button: button)
        case .middleClick: beginRemappedClick(.center, button: button)
        case .doubleClick:
            ActionPerformer.click(.left, down: true, clickState: 1)
            ActionPerformer.click(.left, down: false, clickState: 1)
            ActionPerformer.click(.left, down: true, clickState: 2)
            ActionPerformer.click(.left, down: false, clickState: 2)
        case .back: ActionPerformer.key(kVK_ANSI_LeftBracket, .maskCommand)
        case .forward: ActionPerformer.key(kVK_ANSI_RightBracket, .maskCommand)
        case .missionControl: ActionPerformer.openApp("/System/Applications/Mission Control.app")
        case .appExpose: ActionPerformer.key(kVK_DownArrow, .maskControl)
        case .showDesktop: ActionPerformer.key(kVK_F11)
        case .previousSpace: ActionPerformer.key(kVK_LeftArrow, .maskControl)
        case .nextSpace: ActionPerformer.key(kVK_RightArrow, .maskControl)
        case .spotlight: ActionPerformer.key(kVK_Space, .maskCommand)
        case .copy: ActionPerformer.key(kVK_ANSI_C, .maskCommand)
        case .paste: ActionPerformer.key(kVK_ANSI_V, .maskCommand)
        case .undo: ActionPerformer.key(kVK_ANSI_Z, .maskCommand)
        case .redo: ActionPerformer.key(kVK_ANSI_Z, [.maskCommand, .maskShift])
        case .screenshot: ActionPerformer.key(kVK_ANSI_4, [.maskCommand, .maskShift])
        case .lockScreen: ActionPerformer.key(kVK_ANSI_Q, [.maskCommand, .maskControl])
        case .playPause: ActionPerformer.media(16)
        case .nextTrack: ActionPerformer.media(17)
        case .previousTrack: ActionPerformer.media(18)
        case .volumeUp: ActionPerformer.media(0)
        case .volumeDown: ActionPerformer.media(1)
        case .mute: ActionPerformer.media(7)
        case .dpiCycle: store.cycleStage()
        case .dpiUp: store.stepStage(1)
        case .dpiDown: store.stepStage(-1)
        case .sniper:
            let wasEmpty = sniperHeldButtons.isEmpty
            sniperHeldButtons.insert(button.rawValue)
            if wasEmpty {
                store.beginSniper()
            }
        case .keystroke(let k): ActionPerformer.key(Int(k.keyCode), k.flags)
        case .typeText(let t): ActionPerformer.type(t)
        case .gesture: break
        }
    }

    private func release(_ action: MouseAction, button: MouseButton) {
        switch action {
        case .leftClick: endRemappedClick(.left, button: button)
        case .rightClick: endRemappedClick(.right, button: button)
        case .middleClick: endRemappedClick(.center, button: button)
        case .sniper:
            sniperHeldButtons.remove(button.rawValue)
            if sniperHeldButtons.isEmpty {
                deactivateSniper(announce: true)
            }
        default: break
        }
    }
}
