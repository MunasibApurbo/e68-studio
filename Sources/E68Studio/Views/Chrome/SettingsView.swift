import SwiftUI
import ServiceManagement

struct GlassSettingsView: View {
    @ObservedObject private var mirror = LiveMirror.shared
    @ObservedObject private var remapper = MouseRemapper.shared
    var onEnsureMainWindow: (() -> Void)? = nil

    @AppStorage(GlassKeys.style) private var style: GlassPreference = .automatic
    @AppStorage(GlassKeys.appearance) private var appearance: AppearancePreference = .system
    @AppStorage(MenuBarKeys.showInMenuBar) private var showInMenuBar = true
    @AppStorage(MenuBarKeys.keepRunningInMenuBar) private var keepRunningInMenuBar = true
    @AppStorage(AmbienceKeys.deskLampOn) private var deskLampOn = true
    @AppStorage(AmbienceKeys.deskMood) private var deskMood: DeskMood = .daylight
    @AppStorage(AmbienceKeys.deskScenario) private var deskScenario: DeskScenario = .swissAlps
    @AppStorage(AmbienceKeys.notifyLowBattery) private var notifyLowBattery = true
    @AppStorage(DeskWallpaperKeys.token) private var wallpaperToken = ""
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var requiresApproval = SMAppService.mainApp.status == .requiresApproval
    @ViewState private var loginItemNote: String?

    var body: some View {
        Form {
            Section("Menu Bar & Startup") {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                    .onChange(of: showInMenuBar) { _, shown in
                        if !shown {
                            NSApp.setActivationPolicy(.regular)
                            onEnsureMainWindow?()
                        }
                    }

                Toggle("Keep running when window closes", isOn: $keepRunningInMenuBar)
                    .disabled(!showInMenuBar)

                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in updateLaunchAtLogin(enabled) }
                ))

                if let loginItemNote {
                    Text(loginItemNote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if requiresApproval {
                    HStack {
                        Text("Allow E68 Studio in Login Items")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Glass", selection: $style) {
                        ForEach(GlassPreference.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text(style.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if reduceTransparency {
                    Label("Reduce Transparency is active", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if contrast == .increased {
                    Label("Increase Contrast is active", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button("Appearance Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Appearance-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)

                Button("Accessibility Display Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }

            Section("Desk & Notifications") {
                Picker("World scenario", selection: $deskScenario) {
                    ForEach(DeskScenario.allCases) { scenario in
                        Label(scenario.title, systemImage: scenario.symbol).tag(scenario)
                    }
                }

                Toggle("Desk lamp", isOn: $deskLampOn)

                Picker("Lighting", selection: $deskMood) {
                    ForEach(DeskMood.allCases) { mood in
                        Text(mood.title).tag(mood)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Monitor wallpaper")
                    Spacer()
                    if !wallpaperToken.isEmpty {
                        Button("Reset") {
                            MonitorWallpaperStore.resetWallpaper()
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Choose Image…") {
                        MonitorWallpaperStore.pickWallpaper()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Toggle("Low battery alerts (< 15%)", isOn: $notifyLowBattery)

                Toggle("Live Mirror", isOn: $mirror.enabled)

                if !remapper.trusted {
                    HStack(spacing: 8) {
                        Label("Accessibility permission required for Live Mirror", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button("Allow…") {
                            remapper.requestAccess()
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .frame(minHeight: 420, idealHeight: 470, maxHeight: 580)
        .studioAppearance()
        .onAppear {
            refreshLoginItemStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItemStatus()
        }
    }

    private func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        loginItemNote = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItemStatus()
        } catch {
            refreshLoginItemStatus()
            if Bundle.main.bundleURL.pathExtension != "app" {
                loginItemNote = "Launch at login is available when running E68 Studio.app."
            } else {
                loginItemNote = "Could not update login item: \(error.localizedDescription)"
            }
        }
    }
}
