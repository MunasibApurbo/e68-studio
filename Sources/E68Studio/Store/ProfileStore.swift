import AppKit
import Foundation

/// Manages saved StudioProfiles and automatic profile switching when the frontmost macOS application changes.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    private static let profilesKey = "e68.profiles"
    private static let activeIDKey = "e68.activeProfileID"
    private static let autoSwitchKey = "e68.profileAutoSwitch"

    @Published var profiles: [StudioProfile] {
        didSet { saveProfiles() }
    }
    @Published var activeProfileID: UUID? {
        didSet {
            if let id = activeProfileID {
                defaults.set(id.uuidString, forKey: Self.activeIDKey)
            } else {
                defaults.removeObject(forKey: Self.activeIDKey)
            }
        }
    }
    @Published var autoSwitchEnabled: Bool {
        didSet {
            defaults.set(autoSwitchEnabled, forKey: Self.autoSwitchKey)
            if !autoSwitchEnabled {
                baseProfileID = nil
            }
        }
    }

    weak var keyboardStore: KeyboardStore?
    private let defaults = UserDefaults.standard
    private var appObserver: NSObjectProtocol?
    private var baseProfileID: UUID?

    var activeProfile: StudioProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    init() {
        let initialProfiles: [StudioProfile]
        if let data = defaults.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([StudioProfile].self, from: data),
           !decoded.isEmpty {
            initialProfiles = decoded
        } else {
            initialProfiles = StudioProfile.defaults
        }
        profiles = initialProfiles
        autoSwitchEnabled = (defaults.object(forKey: Self.autoSwitchKey) as? Bool) ?? true

        if let rawID = defaults.string(forKey: Self.activeIDKey),
           let uuid = UUID(uuidString: rawID),
           initialProfiles.contains(where: { $0.id == uuid }) {
            activeProfileID = uuid
        } else {
            activeProfileID = initialProfiles.first?.id
        }

        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.handleActivatedApp(bundleIdentifier: bundleID)
            }
        }
    }

    func handleActivatedApp(bundleIdentifier: String?) {
        guard autoSwitchEnabled, let bundleIdentifier else { return }
        if let match = profiles.first(where: { $0.matches(bundleIdentifier: bundleIdentifier) }) {
            if baseProfileID == nil {
                baseProfileID = activeProfileID
            }
            if match.id != activeProfileID {
                applyProfile(match, notifyUser: false)
            }
        } else if let restoreID = baseProfileID {
            baseProfileID = nil
            if restoreID != activeProfileID,
               let baseProfile = profiles.first(where: { $0.id == restoreID }) {
                applyProfile(baseProfile, notifyUser: false)
            }
        }
    }

    func activate(_ profile: StudioProfile, notifyUser: Bool = true) {
        baseProfileID = nil
        applyProfile(profile, notifyUser: notifyUser)
    }

    private func applyProfile(_ profile: StudioProfile, notifyUser: Bool) {
        activeProfileID = profile.id

        if let store = keyboardStore {
            store.activeLayer = min(max(0, profile.activeLayer), max(0, store.layerCount - 1))
            if store.screenSync {
                store.disableScreenSyncWithoutRestoring()
            }
            let target = profile.lighting
            let wasMusic = store.lighting.musicSync
            store.lighting = target
            if target.musicSync {
                if store.isReady {
                    store.lightingNeedsSave = true
                    store.audioMonitor.start()
                    store.startHardwareMusicSync()
                } else if wasMusic {
                    store.cancelMusicSyncAndAudioWithoutRestoring()
                }
            } else {
                if wasMusic {
                    store.cancelMusicSyncAndAudioWithoutRestoring()
                }
                if store.isReady {
                    store.queueLighting([.effect, .brightness, .speed, .color])
                }
            }
            if notifyUser {
                store.notify("Switched to “\(profile.name)”")
            }
        }

        if let stageIndex = profile.mouseStageIndex, MouseStore.shared.customEnabled {
            MouseStore.shared.selectStage(stageIndex, announce: notifyUser && !MouseStore.shared.sniperActive)
        }
    }

    func createFromCurrent(name: String, symbol: String = "sparkles") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lighting = keyboardStore?.lighting ?? LightingState()
        let layer = keyboardStore?.activeLayer ?? 0
        let stage = MouseStore.shared.customEnabled ? MouseStore.shared.clampedStageIndex : nil
        let profile = StudioProfile(
            name: trimmed,
            symbol: symbol,
            bundleIdentifiers: [],
            lighting: lighting,
            activeLayer: layer,
            mouseStageIndex: stage
        )
        profiles.append(profile)
        baseProfileID = nil
        activeProfileID = profile.id
        keyboardStore?.notify("Saved “\(trimmed)”")
    }

    func captureCurrentState(into id: UUID) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let store = keyboardStore {
            profiles[idx].lighting = store.lighting
            profiles[idx].activeLayer = store.activeLayer
        }
        profiles[idx].mouseStageIndex = MouseStore.shared.customEnabled ? MouseStore.shared.clampedStageIndex : nil
        keyboardStore?.notify("Updated “\(profiles[idx].name)”")
    }

    func toggleAppLink(bundleID: String, for profileID: UUID) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        if let existing = profiles[idx].bundleIdentifiers.firstIndex(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) {
            profiles[idx].bundleIdentifiers.remove(at: existing)
        } else {
            profiles[idx].bundleIdentifiers.append(bundleID)
        }
    }

    func delete(id: UUID) {
        guard profiles.count > 1 else { return }
        let wasActive = (activeProfileID == id)
        if baseProfileID == id {
            baseProfileID = nil
        }
        profiles.removeAll { $0.id == id }
        if wasActive, let fallback = profiles.first {
            activate(fallback, notifyUser: false)
        }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.profilesKey)
        }
    }
}
