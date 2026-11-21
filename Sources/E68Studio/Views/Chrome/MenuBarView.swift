import SwiftUI
import AppKit

/// Minimal MenuBarExtra popover: device status, keyboard lighting essentials, mouse DPI stage stepper, and window actions.
struct MenuBarView: View {
    var onOpenMainWindow: () -> Void

    @EnvironmentObject private var store: KeyboardStore
    @ObservedObject private var mouse = MouseStore.shared
    @ObservedObject private var profileStore = ProfileStore.shared
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @ViewState private var audioUnavailableReason: String?
    @AppStorage("menuBar.screenGlowNeedsAccess") private var screenGlowNeedsAccess = false

    private var lighting: LightingState { store.lighting }

    private var keyboardStatusColor: Color {
        switch store.connection {
        case .ready: return .green
        case .bluetooth: return .blue
        case .loading: return .yellow
        case .failed: return .orange
        case .searching: return .gray
        }
    }

    private var keyboardStatusText: String {
        switch store.connection {
        case .ready:
            let link = store.device?.link ?? "USB"
            let firmware = store.device?.firmware ?? ""
            return firmware.isEmpty ? link : "\(link) · v\(firmware)"
        case .bluetooth:
            let link = store.bluetoothDevice?.link ?? "Bluetooth"
            if let battery = store.bluetoothDevice?.batteryLevel {
                return "\(link) · \(battery)%"
            }
            return link
        case .loading:
            return "Connecting…"
        case .failed:
            return "Not responding"
        case .searching:
            return "Not connected"
        }
    }

    private var mouseStatusText: String {
        guard let info = mouse.info else { return "Not connected" }
        if let battery = info.battery {
            return "\(info.link) · \(battery)%"
        }
        return info.link
    }

    private var activeStageColor: Color {
        guard mouse.customEnabled, !mouse.sniperActive else { return .secondary }
        if let stage = mouse.currentStage { return stageColor(stage.colorIndex) }
        return .secondary
    }

    private var mouseDPIBadge: String {
        guard mouse.customEnabled else { return "System" }
        return mouse.sniperActive ? "Sniper \(mouse.appliedDPI)" : "\(mouse.appliedDPI) DPI"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header

            Divider()

            keyboardEssentials
                .disabled(!store.isReady)

            if !store.isReady {
                Text("Connect via USB or 2.4G for lighting and layer controls.")
                    .font(.studioMeta)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            syncPermissionNotices

            Divider()

            mouseDPIRow

            Divider()

            profileRow

            Divider()

            footerActions
        }
        .padding(Space.l)
        .frame(width: 300)
        .environment(\.insideGlassPanel, true)
        .onAppear {
            store.start()
            mouse.start()
            refreshAudioStatus()
            if CGPreflightScreenCaptureAccess() {
                screenGlowNeedsAccess = false
            }
        }
        .task {
            while !Task.isCancelled {
                refreshAudioStatus()
                if CGPreflightScreenCaptureAccess() {
                    screenGlowNeedsAccess = false
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if CGPreflightScreenCaptureAccess() {
                screenGlowNeedsAccess = false
            }
            if lighting.musicSync, case .unavailable = store.audioMonitor.status() {
                store.audioMonitor.start()
                refreshAudioStatus()
                if audioUnavailableReason == nil {
                    store.startHardwareMusicSync()
                }
            } else {
                refreshAudioStatus()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                E68LogoBadge(size: 28)

                Text("E68 Studio")
                    .font(.studioTitle)

                Spacer(minLength: 4)

                if case .failed = store.connection {
                    Button("Retry") {
                        Task { await store.reload() }
                    }
                    .buttonStyle(.glassCapsule(size: .small))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                deviceLine(
                    name: store.activeProductName ?? "E68 PRO",
                    status: keyboardStatusText,
                    dot: keyboardStatusColor
                )
                deviceLine(
                    name: mouse.info?.product ?? "MCHOSE G7",
                    status: mouseStatusText,
                    dot: mouse.info == nil ? .gray : .green
                )
            }
        }
    }

    private func deviceLine(name: String, status: String, dot: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dot.gradient)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.studioMeta.weight(.medium))
                .lineLimit(1)
            Text("·")
                .font(.studioMeta)
                .foregroundStyle(.tertiary)
            Text(status)
                .font(.studioMeta)
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(status)")
    }

    private var keyboardEssentials: some View {
        let lightingControlsEnabled = lighting.isOn || store.screenSync
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { lightingControlsEnabled },
                set: { on in
                    withAnimation(.smooth(duration: 0.2)) {
                        store.setBacklightOn(on)
                    }
                }
            )) {
                Text("Backlight")
                    .font(.studioHeading)
            }
            .toggleStyle(AccentSwitchStyle())

            if !lighting.musicSync && !store.screenSync {
                HStack(spacing: 8) {
                    Text("Effect")
                        .font(.studioHeading)
                    Spacer(minLength: 4)
                    Menu {
                        ForEach(LightingCatalog.selectableEffects) { effect in
                            Button {
                                if !lighting.isOn { store.setBacklightOn(true) }
                                store.updateLighting([.effect]) { $0.effect = effect.id }
                            } label: {
                                Label(
                                    effect.name,
                                    systemImage: lighting.effect == effect.id ? "checkmark.circle.fill" : "sparkles"
                                )
                            }
                        }
                    } label: {
                        menuPill {
                            Circle()
                                .fill(lighting.color.gradient)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 0.5))
                                .frame(width: 7, height: 7)
                            Text(LightingCatalog.name(of: lighting.effect))
                                .font(.studioMeta.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 175, alignment: .trailing)
                }
                .opacity(lighting.isOn ? 1 : 0.65)
            }

            VStack(alignment: .leading, spacing: 4) {
                FieldHeader(
                    title: (lighting.musicSync || store.screenSync) ? "Max Brightness" : "Brightness",
                    value: "\(lighting.brightness) of \(LightingCatalog.maxBrightness)"
                )
                StepSlider(
                    value: Binding(
                        get: { lighting.brightness },
                        set: { v in store.updateLighting([.brightness]) { $0.brightness = v } }
                    ),
                    range: 0...LightingCatalog.maxBrightness,
                    label: "Brightness"
                )
            }
            .disabled(!lightingControlsEnabled)

            if !store.screenSync && (!lighting.musicSync || lighting.musicColorMode == .custom) {
                LightingSwatchesView(swatchSize: 18)
                    .disabled(!lightingControlsEnabled)
            }

            Toggle(isOn: Binding(
                get: { lighting.musicSync && audioUnavailableReason == nil },
                set: { on in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        if on && lighting.musicSync {
                            store.audioMonitor.start()
                            refreshAudioStatus()
                            if audioUnavailableReason == nil {
                                store.startHardwareMusicSync()
                            }
                        } else {
                            store.setMusicSync(on)
                            refreshAudioStatus()
                        }
                    }
                }
            )) {
                Label("Sound Wave", systemImage: "waveform")
                    .font(.studioHeading)
            }
            .toggleStyle(AccentSwitchStyle())

            Toggle(isOn: Binding(
                get: { store.screenSync },
                set: { on in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        if on && !CGPreflightScreenCaptureAccess() {
                            screenGlowNeedsAccess = true
                        } else if !on {
                            screenGlowNeedsAccess = false
                        }
                        store.setScreenSync(on)
                    }
                }
            )) {
                Label("Screen Glow", systemImage: "display")
                    .font(.studioHeading)
            }
            .toggleStyle(AccentSwitchStyle())
        }
    }

    @ViewBuilder
    private var syncPermissionNotices: some View {
        let missingScreenPermission = !CGPreflightScreenCaptureAccess()
        if audioUnavailableReason != nil {
            permissionNoticeRow(
                message: "Sound Wave needs System Audio Recording access.",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
            )
        }
        if screenGlowNeedsAccess && missingScreenPermission {
            permissionNoticeRow(
                message: "Screen Glow needs Screen Recording access. Relaunch after enabling.",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
        } else if let toast = store.toast, toast.isError {
            permissionNoticeRow(
                message: toast.text,
                settingsURL: missingScreenPermission && toast.text.localizedCaseInsensitiveContains("Screen")
                    ? "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                    : nil
            )
        }
    }

    private func permissionNoticeRow(message: String, settingsURL: String?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
            Text(message)
                .font(.studioMeta)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let settingsURL {
                Button("Open Settings") {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.glassCapsule(size: .small))
                .fixedSize()
            }
        }
    }

    private func refreshAudioStatus() {
        if case .unavailable(let reason) = store.audioMonitor.status() {
            audioUnavailableReason = reason
        } else {
            audioUnavailableReason = nil
        }
    }

    private var mouseDPIRow: some View {
        let enabledCount = mouse.stages.filter(\.enabled).count
        let hasStages = enabledCount > 0
        let current = mouse.clampedStageIndex
        let canStepDown = hasStages && (!mouse.customEnabled || current > 0)
        let canStepUp = hasStages && (!mouse.customEnabled || current < enabledCount - 1)
        return HStack(spacing: 8) {
            Text("Mouse DPI")
                .font(.studioHeading)

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Circle()
                    .fill(activeStageColor.gradient)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 7, height: 7)
                Text(mouseDPIBadge)
                    .font(.studioMeta.monospacedDigit().weight(.medium))
                    .foregroundStyle(mouse.customEnabled ? Color.primary : Ink.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .nestedSurface(Capsule(), role: .track)

            HStack(spacing: 4) {
                IconButton(symbol: "minus", label: mouse.customEnabled ? "Previous DPI Stage" : "Enable Custom DPI and lower stage", size: Hit.compact) {
                    if mouse.customEnabled {
                        mouse.stepStage(-1)
                    } else {
                        mouse.selectStage(current)
                    }
                }
                .disabled(!canStepDown)
                IconButton(symbol: "plus", label: mouse.customEnabled ? "Next DPI Stage" : "Enable Custom DPI and raise stage", size: Hit.compact) {
                    if mouse.customEnabled {
                        mouse.stepStage(1)
                    } else {
                        mouse.selectStage(current)
                    }
                }
                .disabled(!canStepUp)
            }
        }
    }

    private var profileRow: some View {
        HStack(spacing: 8) {
            Text("Profile")
                .font(.studioHeading)

            Spacer(minLength: 4)

            Menu {
                ForEach(profileStore.profiles) { profile in
                    Button {
                        profileStore.activate(profile, notifyUser: false)
                    } label: {
                        Label(
                            profile.name,
                            systemImage: profileStore.activeProfileID == profile.id ? "checkmark.circle.fill" : profile.symbol
                        )
                    }
                }
                Divider()
                Toggle("Switch by Active App", isOn: $profileStore.autoSwitchEnabled)
            } label: {
                menuPill {
                    Image(systemName: profileStore.activeProfile?.symbol ?? "sparkles")
                        .font(.studioMeta)
                        .foregroundStyle(Color.accentColor)
                    Text(profileStore.activeProfile?.name ?? "Default")
                        .font(.studioMeta.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 175, alignment: .trailing)
        }
    }

    private func menuPill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) {
            content()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Ink.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: Hit.compact)
        .nestedSurface(Capsule(), role: .control)
        .dimsWhenDisabled()
    }

    private var footerActions: some View {
        VStack(spacing: 8) {
            Button {
                dismiss()
                onOpenMainWindow()
            } label: {
                Label("Open E68 Studio", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassCapsule(.prominent))

            HStack {
                Button {
                    openAppSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                        .font(.callout)
                        .frame(minHeight: Hit.compact)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.secondary)
                .keyboardShortcut(",", modifiers: .command)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.callout)
                        .frame(minHeight: Hit.compact)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.secondary)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }

    private func openAppSettings() {
        dismiss()
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
