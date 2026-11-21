import AppKit
import Foundation

/// Forwards key, modifier, and media/knob events in real time across the Desk and Studio views
/// (plus background typing when Input Monitoring is available), while keeping plain keys from
/// beeping when no text field is focused.
@MainActor
final class KeyEventTap {
    nonisolated(unsafe) static var isCapturingShortcut = false
    private var monitor: Any?
    private var globalMonitor: Any?
    private var cgEventTap: CFMachPort?
    private var cgRunLoopSource: CFRunLoopSource?
    private var resignObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var isStarted = false
    private var heldModifiers = Set<UInt8>()
    private var heldKeys = Set<UInt16>()
    private var capsLockTask: Task<Void, Never>?
    private var handler: ((UInt16, Bool) -> Void)?
    var shouldPassThroughEscape: (() -> Bool)?
    var shouldSwallowNavigationKeys: (() -> Bool)?

    /// System media keys (NX_KEYTYPE_*) → the keyboard's keycodes for the same function.
    private static let mediaKeys: [Int: UInt16] = [
        0: 0xA9, 1: 0xAA, 7: 0xA8, 16: 0xAE, 17: 0xAB, 18: 0xAC, 19: 0xBB, 20: 0xBC, 2: 0xBD, 3: 0xBE, 14: 0xB0,
    ]

    /// Direct virtual keycodes for media keys when delivered as regular key events.
    private static let directMediaKeyCodes: [UInt16: UInt16] = [
        0x48: 0xA9, // Volume Up
        0x49: 0xAA, // Volume Down
        0x4A: 0xA8, // Mute
    ]

    struct ModifierSpec {
        let keyCode: UInt16
        let usage: UInt8
        let deviceMask: UInt64
        let familyMask: UInt64
        let nsGenericFlag: NSEvent.ModifierFlags
        let cgGenericFlag: CGEventFlags

        func isDown(rawFlags: UInt64, genericMatch: Bool) -> Bool {
            guard genericMatch else { return false }
            if (rawFlags & familyMask) != 0 {
                return (rawFlags & deviceMask) != 0
            }
            return true
        }
    }

    /// IOKit device-dependent flags from `<IOKit/hidsystem/IOLLEvent.h>` so left/right modifiers track independently.
    static let modifiers: [ModifierSpec] = [
        ModifierSpec(keyCode: 0x3B, usage: 0xE0, deviceMask: 0x0000_0001, familyMask: 0x0000_2001, nsGenericFlag: .control, cgGenericFlag: .maskControl),
        ModifierSpec(keyCode: 0x3E, usage: 0xE4, deviceMask: 0x0000_2000, familyMask: 0x0000_2001, nsGenericFlag: .control, cgGenericFlag: .maskControl),
        ModifierSpec(keyCode: 0x38, usage: 0xE1, deviceMask: 0x0000_0002, familyMask: 0x0000_0006, nsGenericFlag: .shift, cgGenericFlag: .maskShift),
        ModifierSpec(keyCode: 0x3C, usage: 0xE5, deviceMask: 0x0000_0004, familyMask: 0x0000_0006, nsGenericFlag: .shift, cgGenericFlag: .maskShift),
        ModifierSpec(keyCode: 0x3A, usage: 0xE2, deviceMask: 0x0000_0020, familyMask: 0x0000_0060, nsGenericFlag: .option, cgGenericFlag: .maskAlternate),
        ModifierSpec(keyCode: 0x3D, usage: 0xE6, deviceMask: 0x0000_0040, familyMask: 0x0000_0060, nsGenericFlag: .option, cgGenericFlag: .maskAlternate),
        ModifierSpec(keyCode: 0x37, usage: 0xE3, deviceMask: 0x0000_0008, familyMask: 0x0000_0018, nsGenericFlag: .command, cgGenericFlag: .maskCommand),
        ModifierSpec(keyCode: 0x36, usage: 0xE7, deviceMask: 0x0000_0010, familyMask: 0x0000_0018, nsGenericFlag: .command, cgGenericFlag: .maskCommand),
    ]

    private static let cgTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<KeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        MainActor.assumeIsolated {
            tap.handleCGTap(type, event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleCGTap(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = cgEventTap {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return
        }
        if event.getIntegerValueField(.eventSourceUserData) == ActionPerformer.marker {
            return
        }
        if let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined {
            handleSystemDefined(nsEvent)
        }
    }

    private func installCGEventTap() {
        guard isStarted, cgEventTap == nil else {
            if cgEventTap != nil, let obs = activeObserver {
                NotificationCenter.default.removeObserver(obs)
                activeObserver = nil
            }
            return
        }
        // Listen-only CGEventTap receives NX_SYSDEFINED (volume/mute/knob) even when OSDUIHelper consumes it.
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << 14),
            callback: Self.cgTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            return
        }
        cgEventTap = port
        cgRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        if let obs = activeObserver {
            NotificationCenter.default.removeObserver(obs)
            activeObserver = nil
        }
    }

    func start(_ handler: @escaping (UInt16, Bool) -> Void) {
        stop()
        self.handler = handler
        isStarted = true

        installCGEventTap()
        if cgEventTap == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.installCGEventTap()
                }
            }
        }

        // Global monitor tracks typing and media keys even when another app is frontmost.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleGlobalMonitor(event)
            }
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { [weak self] event in
            let shouldPass = MainActor.assumeIsolated {
                self?.handleLocalMonitor(event) ?? true
            }
            return shouldPass ? event : nil
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.releaseHeldEvents()
            }
        }
    }

    private func handleGlobalMonitor(_ event: NSEvent) {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == ActionPerformer.marker { return }
        if event.type == .systemDefined {
            if cgEventTap == nil {
                handleSystemDefined(event)
            }
            return
        }
        if event.type == .flagsChanged {
            handleFlagsChanged(event)
            return
        }
        if let mediaCode = Self.directMediaKeyCodes[event.keyCode] {
            if event.type == .keyDown, !event.isARepeat {
                emitKey(mediaCode, down: true)
            } else if event.type == .keyUp {
                emitKey(mediaCode, down: false)
            }
            return
        }
        guard let usage = MacKeyMap.usage[event.keyCode] else { return }
        let code = UInt16(usage)
        if event.type == .keyDown, !event.isARepeat {
            emitKey(code, down: true)
        } else if event.type == .keyUp {
            emitKey(code, down: false)
        }
    }

    private func handleLocalMonitor(_ event: NSEvent) -> Bool {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == ActionPerformer.marker { return true }
        if event.type == .systemDefined {
            if cgEventTap == nil {
                handleSystemDefined(event)
            }
            return true
        }
        if event.type == .flagsChanged {
            handleFlagsChanged(event)
            return true
        }
        if let mediaCode = Self.directMediaKeyCodes[event.keyCode] {
            if event.type == .keyDown {
                if !event.isARepeat { emitKey(mediaCode, down: true) }
            } else if event.type == .keyUp {
                emitKey(mediaCode, down: false)
            }
            return true
        }
        guard let usage = MacKeyMap.usage[event.keyCode] else { return true }
        let code = UInt16(usage)
        switch event.type {
        case .keyDown:
            if !event.isARepeat { emitKey(code, down: true) }
        case .keyUp:
            emitKey(code, down: false)
        default:
            break
        }
        if event.modifierFlags.contains(.command) || MacroRecorder.isRecordingActive || KeyEventTap.isCapturingShortcut {
            return true
        }
        // Only suppress unhandled keys on the main studio window when no sheet/dialog/text field owns focus.
        guard event.window?.identifier?.rawValue == "e68-main-window",
              event.window?.sheets.isEmpty ?? true else {
            return true
        }
        if NSApp.keyWindow?.firstResponder is NSText {
            return true
        }
        if event.keyCode == 0x35 && (shouldPassThroughEscape?() ?? false) {
            return true
        }
        // Keep standard focus/activation/arrow keys working outside Key Test so sliders,
        // Tab navigation, defaultAction, and popovers remain keyboard-accessible.
        let navKeys: Set<UInt16> = [0x24, 0x30, 0x31, 0x35, 0x4C, 0x7B, 0x7C, 0x7D, 0x7E]
        if navKeys.contains(event.keyCode) && !(shouldSwallowNavigationKeys?() ?? false) {
            return true
        }
        return false
    }

    func stop() {
        isStarted = false
        capsLockTask?.cancel()
        capsLockTask = nil
        if let cgEventTap {
            CGEvent.tapEnable(tap: cgEventTap, enable: false)
            CFMachPortInvalidate(cgEventTap)
        }
        if let cgRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), cgRunLoopSource, .commonModes)
        }
        cgEventTap = nil
        cgRunLoopSource = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
        heldModifiers = []
        heldKeys = []
        handler = nil
    }

    private func handleSystemDefined(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else { return }
        let keyType = (event.data1 & 0xFFFF_0000) >> 16
        guard let code = Self.mediaKeys[keyType] else { return }
        let keyState = (event.data1 & 0xFF00) >> 8
        let isRepeat = (event.data1 & 0x1) != 0
        guard !isRepeat else { return }
        if keyState == 0x0A {
            emitKey(code, down: true)
        } else if keyState == 0x0B {
            emitKey(code, down: false)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        if event.keyCode == 0x39 {
            // macOS only fires flagsChanged once per Caps Lock toggle rather than press/release,
            // so pulse the fallback event rather than latching it stuck on release.
            capsLockTask?.cancel()
            emitKey(0x39, down: true)
            capsLockTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.emitKey(0x39, down: false)
            }
            return
        }

        let rawFlags = UInt64(event.modifierFlags.rawValue)
        for spec in Self.modifiers where spec.keyCode == event.keyCode {
            let isDown = spec.isDown(rawFlags: rawFlags, genericMatch: event.modifierFlags.contains(spec.nsGenericFlag))
            if isDown {
                if heldModifiers.insert(spec.usage).inserted {
                    handler?(UInt16(spec.usage), true)
                }
            } else if heldModifiers.remove(spec.usage) != nil {
                handler?(UInt16(spec.usage), false)
            }
        }

        // Reconcile any modifier whose generic flag is no longer set (e.g. released while unfocused).
        for spec in Self.modifiers where heldModifiers.contains(spec.usage) && !event.modifierFlags.contains(spec.nsGenericFlag) {
            heldModifiers.remove(spec.usage)
            handler?(UInt16(spec.usage), false)
        }
    }

    private func emitKey(_ code: UInt16, down: Bool) {
        if down {
            if heldKeys.insert(code).inserted || code >= 0xA8 {
                handler?(code, true)
            }
        } else {
            if heldKeys.remove(code) != nil || code >= 0xA8 {
                handler?(code, false)
            }
        }
    }

    private func releaseHeldEvents() {
        for code in heldKeys { handler?(code, false) }
        heldKeys.removeAll()
        for usage in heldModifiers { handler?(UInt16(usage), false) }
        heldModifiers.removeAll()
    }
}
