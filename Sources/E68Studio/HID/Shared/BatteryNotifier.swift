import Foundation
@preconcurrency import UserNotifications

/// Sends a native macOS notification once per discharge cycle when keyboard or mouse battery drops to 15% or lower.
@MainActor
final class BatteryNotifier {
    static let shared = BatteryNotifier()

    static let lowThreshold = 15
    private static let resetThreshold = 20

    private(set) var notifiedKeyboardLow = false
    private(set) var notifiedMouseLow = false

    func check(deviceName: String, level: Int?, isMouse: Bool) {
        guard let level else { return }
        let enabled = (UserDefaults.standard.object(forKey: AmbienceKeys.notifyLowBattery) as? Bool) ?? true

        if level >= Self.resetThreshold {
            if isMouse {
                notifiedMouseLow = false
            } else {
                notifiedKeyboardLow = false
            }
            return
        }

        guard enabled, level <= Self.lowThreshold else { return }
        let alreadyNotified = isMouse ? notifiedMouseLow : notifiedKeyboardLow
        guard !alreadyNotified else { return }

        // UNUserNotificationCenter requires a bundled .app process; skip safely in CLI / --selftest runs.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                if isMouse {
                    guard !self.notifiedMouseLow else { return }
                    self.notifiedMouseLow = true
                } else {
                    guard !self.notifiedKeyboardLow else { return }
                    self.notifiedKeyboardLow = true
                }
                let content = UNMutableNotificationContent()
                content.title = "\(deviceName) Battery Low"
                content.body = "\(deviceName) is at \(level)% battery. Connect via USB to recharge."
                content.sound = .default
                let req = UNNotificationRequest(
                    identifier: "e68.lowBattery.\(isMouse ? "mouse" : "keyboard")",
                    content: content,
                    trigger: nil
                )
                try? await UNUserNotificationCenter.current().add(req)
            }
        }
    }
}
