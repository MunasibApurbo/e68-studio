import AppKit
import Carbon.HIToolbox

/// The remappable G7 buttons. Left and right stay fixed so a bad mapping can never lock you out.
enum MouseButton: Int, CaseIterable, Identifiable, Codable {
    /// Values are Quartz button numbers.
    case middle = 2, back = 3, forward = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .middle: "Wheel click"
        case .back: "Back (side, rear)"
        case .forward: "Forward (side, front)"
        }
    }

    var symbol: String {
        switch self {
        case .middle: "computermouse"
        case .back: "chevron.backward.circle"
        case .forward: "chevron.forward.circle"
        }
    }

    /// What the button does when left on "Default".
    var defaultAction: MouseAction {
        switch self {
        case .middle: .middleClick
        case .back: .back
        case .forward: .forward
        }
    }
}

/// A recorded key combination, e.g. ⌘⇧4.
struct Keystroke: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64
    var display: String

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    static func from(_ event: NSEvent) -> Keystroke {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var flags: CGEventFlags = []
        var symbols = ""
        if mods.contains(.control) { flags.insert(.maskControl); symbols += "⌃" }
        if mods.contains(.option) { flags.insert(.maskAlternate); symbols += "⌥" }
        if mods.contains(.shift) { flags.insert(.maskShift); symbols += "⇧" }
        if mods.contains(.command) { flags.insert(.maskCommand); symbols += "⌘" }
        let name = keyName(event.keyCode) ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
        return Keystroke(keyCode: event.keyCode, modifiers: flags.rawValue, display: symbols + name)
    }

    static func keyName(_ code: UInt16) -> String? {
        switch Int(code) {
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Space: "Space"
        case kVK_Delete: "⌫"
        case kVK_ForwardDelete: "⌦"
        case kVK_Escape: "⎋"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_Home: "↖"
        case kVK_End: "↘"
        case kVK_PageUp: "⇞"
        case kVK_PageDown: "⇟"
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        default: nil
        }
    }
}

/// Everything a mouse button can be set to do.
enum MouseAction: Codable, Hashable {
    case standard
    case disabled
    case leftClick, rightClick, middleClick, doubleClick
    case back, forward
    case missionControl, appExpose, showDesktop, previousSpace, nextSpace, spotlight
    case copy, paste, undo, redo, screenshot, lockScreen
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute
    case dpiCycle, dpiUp, dpiDown, sniper
    case keystroke(Keystroke)
    case typeText(String)
    /// Hold the button and move the mouse; the direction picks the action (see `GestureMap`).
    case gesture

    struct Group: Identifiable {
        let title: String
        let actions: [MouseAction]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Mouse", actions: [.leftClick, .rightClick, .middleClick, .doubleClick, .disabled]),
        Group(title: "Navigation", actions: [.back, .forward]),
        Group(title: "DPI", actions: [.dpiCycle, .dpiUp, .dpiDown, .sniper]),
        Group(title: "Desktop", actions: [.missionControl, .appExpose, .showDesktop, .previousSpace, .nextSpace, .spotlight]),
        Group(title: "Editing", actions: [.copy, .paste, .undo, .redo, .screenshot, .lockScreen]),
        Group(title: "Media", actions: [.playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute]),
    ]

    var title: String {
        switch self {
        case .standard: "Default"
        case .disabled: "Do nothing"
        case .leftClick: "Left click"
        case .rightClick: "Right click"
        case .middleClick: "Middle click"
        case .doubleClick: "Double click"
        case .back: "Back"
        case .forward: "Forward"
        case .missionControl: "Mission Control"
        case .appExpose: "App windows"
        case .showDesktop: "Show desktop"
        case .previousSpace: "Previous space"
        case .nextSpace: "Next space"
        case .spotlight: "Spotlight"
        case .copy: "Copy"
        case .paste: "Paste"
        case .undo: "Undo"
        case .redo: "Redo"
        case .screenshot: "Screenshot area"
        case .lockScreen: "Lock screen"
        case .playPause: "Play / pause"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        case .dpiCycle: "Cycle DPI stage"
        case .dpiUp: "DPI up"
        case .dpiDown: "DPI down"
        case .sniper: "Sniper (hold)"
        case .keystroke(let k): "Keys \(k.display)"
        case .typeText(let t): "Type “\(t.prefix(14))\(t.count > 14 ? "…" : "")”"
        case .gesture: "Gestures"
        }
    }

}

/// What a gesture button does for each direction you move while holding it, and for a plain press.
struct GestureMap: Codable, Hashable {
    enum Direction: String, CaseIterable, Codable, Identifiable {
        case up, down, left, right
        var id: String { rawValue }
        var arrow: String {
            switch self {
            case .up: "↑"
            case .down: "↓"
            case .left: "←"
            case .right: "→"
            }
        }
        var title: String { rawValue.capitalized }
    }

    var up: MouseAction = .missionControl
    var down: MouseAction = .appExpose
    var left: MouseAction = .previousSpace
    var right: MouseAction = .nextSpace
    /// A press with no movement. `.standard` means the button's own default.
    var tap: MouseAction = .standard

    subscript(direction: Direction) -> MouseAction {
        get {
            switch direction {
            case .up: up
            case .down: down
            case .left: left
            case .right: right
            }
        }
        set {
            switch direction {
            case .up: up = newValue
            case .down: down = newValue
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }

    /// Actions a direction or tap can be set to (no nested gestures, no holds).
    static let choices: [MouseAction.Group] = MouseAction.groups.map { group in
        MouseAction.Group(title: group.title, actions: group.actions.filter { $0 != .sniper })
    }

    var summary: String {
        Direction.allCases.compactMap { d in
            let a = self[d]
            return a == .disabled ? nil : "\(d.arrow) \(a.title)"
        }.joined(separator: "  ")
    }
}

/// One sensitivity stage. `dpi` is the effective DPI the pointer should feel like.
struct DPIStage: Codable, Hashable, Identifiable {
    var id = UUID()
    var dpi: Int
    var enabled = true
    var colorIndex: Int

    static let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple, .systemPink]

    static let defaults: [DPIStage] = [
        DPIStage(dpi: 400, colorIndex: 0),
        DPIStage(dpi: 800, colorIndex: 1),
        DPIStage(dpi: 1600, colorIndex: 3),
        DPIStage(dpi: 3200, colorIndex: 5),
        DPIStage(dpi: 6400, colorIndex: 6),
    ]
}

/// Tracks consecutive synthetic clicks per mouse button to emit native multi-click states (1, 2, 3...).
struct ClickStateTracker {
    private struct Entry {
        var lastTimestamp: TimeInterval
        var lastLocation: CGPoint
        var clickState: Int64
    }

    private var entries: [UInt32: Entry] = [:]

    mutating func nextClickState(
        for button: CGMouseButton,
        down: Bool,
        at location: CGPoint,
        now: TimeInterval,
        doubleClickInterval: TimeInterval = NSEvent.doubleClickInterval,
        maxDistance: CGFloat = 5.0
    ) -> Int64 {
        let key = button.rawValue
        if down {
            let nextState: Int64
            if let prev = entries[key],
               now >= prev.lastTimestamp,
               (now - prev.lastTimestamp) <= doubleClickInterval,
               hypot(location.x - prev.lastLocation.x, location.y - prev.lastLocation.y) <= maxDistance {
                nextState = prev.clickState + 1
            } else {
                nextState = 1
            }
            entries[key] = Entry(lastTimestamp: now, lastLocation: location, clickState: nextState)
            return nextState
        }
        return entries[key]?.clickState ?? 1
    }

    func currentClickState(for button: CGMouseButton) -> Int64 {
        entries[button.rawValue]?.clickState ?? 1
    }

    mutating func reset() {
        entries.removeAll()
    }
}

/// Sends the synthetic events that actions produce. Every event carries `marker` so the
/// remapper's own tap lets it pass untouched.
enum ActionPerformer {
    static let marker: Int64 = 0x4536_384D // "E68M"

    private static let clickLock = NSLock()
    private nonisolated(unsafe) static var clickTracker = ClickStateTracker()

    private static let source: CGEventSource? = {
        let s = CGEventSource(stateID: .hidSystemState)
        s?.userData = marker
        return s
    }()

    private static let arrowKeyCodes: Set<Int> = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
    ]

    private static let secondaryFnKeyCodes: Set<Int> = [
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    ]

    static func effectiveKeyFlags(for code: Int, base: CGEventFlags = []) -> CGEventFlags {
        var flags = base
        if arrowKeyCodes.contains(code) {
            flags.formUnion([.maskNumericPad, .maskSecondaryFn])
        } else if secondaryFnKeyCodes.contains(code) {
            flags.formUnion(.maskSecondaryFn)
        }
        return flags
    }

    static func key(_ code: Int, _ flags: CGEventFlags = []) {
        let flags = effectiveKeyFlags(for: code, base: flags)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cghidEventTap)
        }
    }

    enum TypeSegment: Equatable {
        case returnKey
        case unicode([UniChar])
    }

    /// Splits text into Return keystrokes and UTF-16 chunks of at most 20 code units (CGEvent limit).
    static func typeSegments(for text: String) -> [TypeSegment] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var segments: [TypeSegment] = []
        var batch: [UniChar] = []

        func flush() {
            guard !batch.isEmpty else { return }
            segments.append(.unicode(batch))
            batch.removeAll(keepingCapacity: true)
        }

        for scalar in normalized.unicodeScalars {
            if scalar == "\n" {
                flush()
                segments.append(.returnKey)
                continue
            }
            let units = Array(String(scalar).utf16)
            if batch.count + units.count > 20 {
                flush()
            }
            batch.append(contentsOf: units)
        }
        flush()
        return segments
    }

    private static func postUnicodeBatch(_ utf16: [UniChar]) {
        guard !utf16.isEmpty else { return }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            e.flags = []
            e.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cghidEventTap)
        }
    }

    static func type(_ text: String) {
        for segment in typeSegments(for: text) {
            switch segment {
            case .returnKey:
                key(kVK_Return)
            case .unicode(let utf16):
                postUnicodeBatch(utf16)
            }
        }
    }

    /// Media keys go through NX_SYSDEFINED events, the same path as the keyboard's own media row.
    static func media(_ nxKey: Int) {
        for (flags, state) in [(0xA00, 0xA), (0xB00, 0xB)] {
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: (nxKey << 16) | (state << 8), data2: -1
            )
            if let cg = event?.cgEvent {
                cg.setIntegerValueField(.eventSourceUserData, value: marker)
                cg.post(tap: .cghidEventTap)
            }
        }
    }

    static func click(_ button: CGMouseButton, down: Bool, clickState: Int64? = nil) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let resolvedState: Int64
        if let clickState {
            resolvedState = clickState
        } else {
            clickLock.lock()
            resolvedState = clickTracker.nextClickState(
                for: button,
                down: down,
                at: location,
                now: ProcessInfo.processInfo.systemUptime
            )
            clickLock.unlock()
        }
        let type: CGEventType = switch (button, down) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        case (_, true): .otherMouseDown
        case (_, false): .otherMouseUp
        }
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: resolvedState)
        e.setIntegerValueField(.eventSourceUserData, value: marker)
        e.post(tap: .cghidEventTap)
    }

    /// Emits a synthetic drag event while a button remapped to left/right/middle click is held.
    static func drag(_ button: CGMouseButton, at location: CGPoint, deltaX: Int64 = 0, deltaY: Int64 = 0) {
        let type: CGEventType = switch button {
        case .left: .leftMouseDragged
        case .right: .rightMouseDragged
        default: .otherMouseDragged
        }
        clickLock.lock()
        let state = clickTracker.currentClickState(for: button)
        clickLock.unlock()
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: state)
        e.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
        e.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
        e.setIntegerValueField(.eventSourceUserData, value: marker)
        e.post(tap: .cghidEventTap)
    }

    /// Replays a press and release of an extra mouse button by its Quartz number (2 middle, 3 back, 4 forward).
    static func otherButton(_ number: Int) {
        let location = CGEvent(source: nil)?.location ?? .zero
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location,
                                  mouseButton: CGMouseButton(rawValue: UInt32(number)) ?? .center) else { continue }
            e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cghidEventTap)
        }
    }

    static func openApp(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }
}
