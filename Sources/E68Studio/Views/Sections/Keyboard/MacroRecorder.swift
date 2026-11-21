import AppKit
import Foundation

/// Captures typing inside the app window and turns it into macro steps.
final class MacroRecorder: ObservableObject {
    nonisolated(unsafe) static var isRecordingActive = false
    @Published var isRecording = false
    @Published var count = 0

    private var captured = [MacroStep]()
    private var heldModifiers = Set<UInt8>()
    private var monitor: Any?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        Self.isRecordingActive = false
    }

    func start() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        captured = []
        heldModifiers = []
        count = 0
        isRecording = true
        Self.isRecordingActive = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    func stop() -> [MacroStep] {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        Self.isRecordingActive = false
        // Release anything still held so a macro can never leave a modifier stuck.
        for key in heldModifiers.sorted() { captured.append(MacroStep(kind: .up, key: key)) }
        heldModifiers = []
        return MacroCodec.simplify(captured)
    }

    private func handle(_ event: NSEvent) {
        guard let usage = MacKeyMap.usage[event.keyCode] else { return }
        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return }
            captured.append(MacroStep(kind: .down, key: usage))
        case .keyUp:
            captured.append(MacroStep(kind: .up, key: usage))
        case .flagsChanged:
            guard let flag = Self.modifierFlag(for: usage) else { return }
            if !event.modifierFlags.contains(flag) {
                let siblings = heldModifiers.filter { Self.modifierFlag(for: $0) == flag }
                guard !siblings.isEmpty else { return }
                for u in siblings.sorted() {
                    heldModifiers.remove(u)
                    captured.append(MacroStep(kind: .up, key: u))
                }
            } else if heldModifiers.remove(usage) != nil {
                captured.append(MacroStep(kind: .up, key: usage))
            } else {
                heldModifiers.insert(usage)
                captured.append(MacroStep(kind: .down, key: usage))
            }
        default:
            return
        }
        count = captured.count
    }

    private static func modifierFlag(for usage: UInt8) -> NSEvent.ModifierFlags? {
        switch usage {
        case 0xE0, 0xE4: return .control
        case 0xE1, 0xE5: return .shift
        case 0xE2, 0xE6: return .option
        case 0xE3, 0xE7: return .command
        case 0x39: return .capsLock
        default: return nil
        }
    }
}
