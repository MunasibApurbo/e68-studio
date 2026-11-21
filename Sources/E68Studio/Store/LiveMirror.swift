import AppKit
import Carbon.HIToolbox

/// Mirrors real typing and clicking onto the 3D desk while you use other apps: keys go down on
/// the model keyboard as you press them, and the model mouse clicks and scrolls along.
@MainActor
final class LiveMirror: ObservableObject {
    static let shared = LiveMirror()

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "liveMirror.enabled")
            sync()
        }
    }
    /// Keyboard slot indices held down right now.
    @Published private(set) var pressed: Set<Int> = []

    weak var store: KeyboardStore?

    private var windowVisible = true
    private var heldModifierCodes: Set<UInt16> = []
    private var capsTask: Task<Void, Never>?
    private var releaseTasks: [Int: Task<Void, Never>] = [:]

    private init() {
        enabled = UserDefaults.standard.object(forKey: "liveMirror.enabled") as? Bool ?? true
    }

    func start() { sync() }

    func setWindowVisible(_ visible: Bool) {
        guard windowVisible != visible else { return }
        windowVisible = visible
        sync()
    }

    func stop() {
        clearSubscriptionAndState()
    }

    private func sync() {
        if enabled && windowVisible {
            GlobalKeyTap.shared.subscribe("mirror") { [weak self] in self?.handle($0) }
        } else {
            clearSubscriptionAndState()
        }
    }

    private func clearSubscriptionAndState() {
        GlobalKeyTap.shared.unsubscribe("mirror")
        capsTask?.cancel()
        capsTask = nil
        for task in releaseTasks.values { task.cancel() }
        releaseTasks = [:]
        pressed = []
        heldModifierCodes = []
    }

    /// Where a macOS key code sits on the E-68 base layer.
    private func slotIndex(for keyCode: UInt16) -> Int? {
        guard let usage = MacKeyMap.usage[keyCode] else { return nil }
        let layer = store?.keymap.first ?? FactoryKeymap.layers[0]
        return Layout.keys.first { $0.index < layer.count && layer[$0.index] == UInt16(usage) }?.index
    }

    private func handle(_ event: GlobalKeyTap.Event) {
        guard !event.isSynthetic else { return }
        switch event.kind {
        case .keyDown:
            guard !event.isRepeat, let index = slotIndex(for: event.keyCode) else { return }
            press(index)
        case .keyUp:
            guard let index = slotIndex(for: event.keyCode) else { return }
            release(index)
        case .flagsChanged:
            let code = event.keyCode
            if code == UInt16(kVK_CapsLock) {
                guard let index = slotIndex(for: code) else { return }
                // Caps Lock reports a toggle, not press and release, so tap it briefly.
                press(index)
                capsTask?.cancel()
                capsTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    self?.release(index)
                }
                return
            }

            let rawFlags = event.flags.rawValue
            for spec in KeyEventTap.modifiers where spec.keyCode == code {
                guard let index = slotIndex(for: code) else { continue }
                let isDown = spec.isDown(rawFlags: rawFlags, genericMatch: event.flags.contains(spec.cgGenericFlag))
                if isDown {
                    heldModifierCodes.insert(code)
                    press(index, autoRelease: false)
                } else {
                    heldModifierCodes.remove(code)
                    release(index)
                }
            }

            // Reconcile any modifier whose generic flag is cleared (for instance, released during secure input).
            for spec in KeyEventTap.modifiers where heldModifierCodes.contains(spec.keyCode) && !event.flags.contains(spec.cgGenericFlag) {
                heldModifierCodes.remove(spec.keyCode)
                if let index = slotIndex(for: spec.keyCode) {
                    release(index)
                }
            }
        case .click:
            break
        }
    }

    private func press(_ index: Int, autoRelease: Bool = true) {
        pressed.insert(index)
        releaseTasks[index]?.cancel()
        guard autoRelease else { return }
        // A key-up can be lost (secure input, app switch); never leave a cap stuck down.
        releaseTasks[index] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.release(index)
        }
    }

    private func release(_ index: Int) {
        releaseTasks.removeValue(forKey: index)?.cancel()
        pressed.remove(index)
    }
}
