import AppKit
import ApplicationServices

/// One listen-only session tap for system-wide keyboard and click events. It feeds the text
/// expander and the live desk mirror. It needs Accessibility (or Input Monitoring) permission;
/// until that is granted it keeps retrying quietly and nothing arrives.
@MainActor
final class GlobalKeyTap {
    static let shared = GlobalKeyTap()

    enum Kind { case keyDown, keyUp, flagsChanged, click }

    struct Event {
        let kind: Kind
        let keyCode: UInt16
        let isRepeat: Bool
        let flags: CGEventFlags
        /// The characters this key produced, already shifted and keyboard-layout aware.
        let characters: String
        /// Posted by E68 Studio itself (expansions, mouse actions).
        let isSynthetic: Bool
    }

    private var subscribers: [String: (Event) -> Void] = [:]
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?
    private var activeObserver: NSObjectProtocol?

    var isRunning: Bool { tap != nil }

    private static let mask: CGEventMask = [
        CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ].reduce(0) { $0 | (1 << $1.rawValue) }

    func subscribe(_ id: String, _ handler: @escaping (Event) -> Void) {
        subscribers[id] = handler
        install()
        guard tap == nil else { return }
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.tap == nil else { return }
                    self.install()
                }
            }
        }
        guard retry == nil else { return }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.install() }
        }
        RunLoop.main.add(t, forMode: .common)
        retry = t
    }

    func unsubscribe(_ id: String) {
        subscribers[id] = nil
        guard subscribers.isEmpty else { return }
        stopRetryAndObserver()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
    }

    private func stopRetryAndObserver() {
        retry?.invalidate()
        retry = nil
        if let obs = activeObserver {
            NotificationCenter.default.removeObserver(obs)
            activeObserver = nil
        }
    }

    private func install() {
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            stopRetryAndObserver()
            return
        }
        guard !subscribers.isEmpty else { return }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        stopRetryAndObserver()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<GlobalKeyTap>.fromOpaque(info).takeUnretainedValue()
        MainActor.assumeIsolated { me.handle(type, event) }
        return Unmanaged.passUnretained(event)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        let kind: Kind
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: kind = .click
        default: return
        }
        var characters = ""
        if kind == .keyDown {
            var length = 0
            var buffer = [UniChar](repeating: 0, count: 8)
            event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
            if length > 0 { characters = String(utf16CodeUnits: buffer, count: length) }
        }
        let e = Event(
            kind: kind,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            flags: event.flags,
            characters: characters,
            isSynthetic: event.getIntegerValueField(.eventSourceUserData) == ActionPerformer.marker
        )
        for handler in subscribers.values { handler(e) }
    }
}
