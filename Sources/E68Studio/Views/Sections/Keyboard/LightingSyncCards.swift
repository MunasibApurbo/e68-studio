import SwiftUI
import AppKit

/// Screen Glow: the backlight takes the colours at the edges of your screen.
struct ScreenGlowCard: View {
    @ObservedObject var store: KeyboardStore
    @ViewState private var hasScreenPermission = CGPreflightScreenCaptureAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Toggle(isOn: Binding(
                get: { store.screenSync },
                set: { on in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.setScreenSync(on)
                    }
                }
            )) {
                HStack(spacing: 10) {
                    Image(systemName: "tv.and.mediabox")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(store.screenSync ? Color.accentColor : Ink.secondary)
                        .frame(width: 20)
                    Text("Screen Glow")
                        .font(.studioHeading)
                }
            }
            .toggleStyle(AccentSwitchStyle())

            if !hasScreenPermission {
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Screen Recording access is needed. Relaunch E68 Studio after enabling it.")
                        .font(.studioMeta)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Open Settings") {
                        ScreenColorSampler.requestPermission()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.glassCapsule(size: .small))
                    .fixedSize()
                }
                .padding(.top, 2)
            }

            if store.screenSync {
                VStack(alignment: .leading, spacing: Space.s) {
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        let sample = store.screenSampler.current
                        let colour = Color(hue: Double(sample.hue), saturation: Double(sample.saturation), brightness: 1)
                        HStack(spacing: Space.s) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(colour)
                                .frame(height: 22)
                                .shadow(color: colour.opacity(0.55), radius: 8)
                            Text("\(Int((sample.brightness * 100).rounded()))%")
                                .font(.studioMeta.monospacedDigit())
                                .foregroundStyle(Ink.secondary)
                                .frame(width: 36, alignment: .trailing)
                                .help("Screen brightness")
                        }
                    }
                    Toggle(isOn: Binding(
                        get: { store.screenSyncFollowsBrightness },
                        set: { store.screenSyncFollowsBrightness = $0 }
                    )) {
                        Text("Dim with dark scenes")
                            .font(.studioMeta.weight(.medium))
                    }
                    .toggleStyle(AccentSwitchStyle())
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .insetCard()
        .onAppear {
            hasScreenPermission = CGPreflightScreenCaptureAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasScreenPermission = CGPreflightScreenCaptureAccess()
        }
    }
}

/// Sound Wave sync card driven by macOS system audio output (no microphone).
struct SoundWaveSyncCard: View {
    let store: KeyboardStore
    let lighting: LightingState

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Toggle(isOn: Binding(
                get: { lighting.musicSync },
                set: { on in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.setMusicSync(on)
                    }
                }
            )) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(lighting.musicSync ? Color.accentColor : Ink.secondary)
                        .frame(width: 20)
                    Text("Sound Wave")
                        .font(.studioHeading)
                }
            }
            .toggleStyle(AccentSwitchStyle())

            if lighting.musicSync {
                let trim = lighting.musicSyncOffsetMs
                let timingValueText = trim == 0
                    ? "Auto"
                    : "Auto \(trim > 0 ? "+" : "-") \(abs(trim)) milliseconds"
                VStack(alignment: .leading, spacing: Space.m) {
                    SoundWaveStrip(
                        audio: store.audioMonitor,
                        color: lighting.color,
                        colorMode: lighting.musicColorMode,
                        musicSync: lighting.musicSync
                    )

                    GlassSegmented(
                        selection: Binding(get: { lighting.musicMode }, set: { store.setMusicMode($0) }),
                        options: MusicLightingMode.allCases.map { ($0, $0.title) },
                        size: .small,
                        fill: true
                    )
                    .help(lighting.musicMode.detail)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Colour")
                            .font(.studioMeta.weight(.medium))
                            .foregroundStyle(Ink.secondary)
                        GlassSegmented(
                            selection: Binding(get: { lighting.musicColorMode }, set: { store.setMusicColorMode($0) }),
                            options: MusicColorMode.allCases.map { ($0, $0.title) },
                            size: .small,
                            fill: true
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Sensitivity")
                                .font(.studioMeta.weight(.medium))
                                .foregroundStyle(Ink.secondary)
                            Spacer()
                            Text(String(format: "%.1f×", lighting.musicSensitivity))
                                .font(.studioMeta.monospacedDigit())
                                .foregroundStyle(Ink.secondary)
                        }
                        StepSlider(
                            value: Binding(
                                get: { Int((lighting.musicSensitivity * 10).rounded()) },
                                set: { store.setMusicSensitivity(Double($0) / 10) }
                            ),
                            range: 4...25,
                            label: "Sensitivity",
                            accessibilityValueText: String(format: "%.1f times", lighting.musicSensitivity)
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Light timing")
                                .font(.studioMeta.weight(.medium))
                                .foregroundStyle(Ink.secondary)
                            Spacer()
                            TimelineView(.periodic(from: .now, by: 2)) { _ in
                                let auto = Int((store.audioMonitor.outputLatency() * 1000).rounded())
                                Text(trim == 0 ? "Auto · \(auto) ms" : "Auto \(auto) \(trim > 0 ? "+" : "−") \(abs(trim)) ms")
                                    .font(.studioMeta.monospacedDigit())
                                    .foregroundStyle(Ink.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        StepSlider(
                            value: Binding(
                                get: { lighting.musicSyncOffsetMs / 10 },
                                set: { store.setMusicSyncOffset($0 * 10) }
                            ),
                            range: -15...30,
                            label: "Light timing",
                            accessibilityValueText: timingValueText
                        )
                        .help("Set automatically for your speakers or headphones. Drag right if the lights run early, left if they lag.")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .insetCard()
    }
}

/// Minimal real-time sound wave visualizer tinted to the playing track's cover color.
struct SoundWaveStrip: View {
    let audio: AudioMonitor
    let color: Color
    var colorMode: MusicColorMode = .dynamic
    var musicSync: Bool = true

    @ViewState private var isPlaying = false
    @ViewState private var isUnavailable = false
    @ViewState private var wallpaperPalette = WallpaperColorSampler.shared.currentPalette()

    var body: some View {
        Group {
            if isUnavailable {
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Sound Wave needs System Audio Recording access.")
                        .font(.studioMeta)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Open") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.glassCapsule(size: .small))
                }
                .padding(.top, 2)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { _ in
                    let snap = audio.snapshot()
                    let colors = resolvedColors(for: snap)
                    let amp = CGFloat(min(1.0, max(0.0, snap.amplitude)))
                    let beat = CGFloat(min(1.0, max(0.0, snap.beat)))
                    let wave = snap.waveform
                    let bands = snap.bands
                    HStack(spacing: 8) {
                        Circle()
                            .fill(snap.isPlaying ? (beat > 0.55 ? colors.secondary : colors.primary) : colors.primary.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .scaleEffect(snap.isPlaying ? (1.0 + max(amp * 0.35, beat * 0.55)) : 1.0)

                        HStack(spacing: 2.5) {
                            ForEach(0..<24, id: \.self) { i in
                                let wIdx = min(wave.count - 1, (i * max(1, wave.count)) / 24)
                                let bIdx = min(bands.count - 1, (i * max(1, bands.count)) / 24)
                                let sample = wave.isEmpty ? Float(0) : abs(wave[wIdx])
                                let band = bands.isEmpty ? Float(0) : bands[bIdx]
                                let combined = max(sample * 0.72 + band * 0.45, Float(amp) * 0.25)
                                let mag = snap.isPlaying
                                    ? CGFloat(min(1.0, max(0.12, combined)))
                                    : CGFloat(0.12)
                                let barColor = (snap.isPlaying && Double(mag) > 0.58) ? colors.secondary : colors.primary
                                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                                    .fill(barColor.opacity(snap.isPlaying ? (0.45 + 0.55 * Double(mag)) : 0.3))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 2 + mag * 14)
                            }
                        }
                        .frame(height: 16)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .task(id: colorMode) {
            if colorMode == .wallpaper {
                wallpaperPalette = WallpaperColorSampler.shared.currentPalette()
            }
            var ticks = 0
            while !Task.isCancelled {
                let snap = audio.snapshot()
                if isPlaying != snap.isPlaying { isPlaying = snap.isPlaying }
                let unavailable: Bool = {
                    if case .unavailable = audio.status() { return true }
                    return false
                }()
                if isUnavailable != unavailable { isUnavailable = unavailable }
                if colorMode == .wallpaper && ticks % 6 == 0 {
                    wallpaperPalette = WallpaperColorSampler.shared.currentPalette()
                }
                ticks += 1
                try? await Task.sleep(for: .milliseconds(160))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard musicSync, case .unavailable = audio.status() else { return }
            audio.start()
            if case .unavailable = audio.status() {
                isUnavailable = true
            } else {
                isUnavailable = false
            }
        }
    }

    private func resolvedColors(for snap: AudioSnapshot) -> (primary: Color, secondary: Color) {
        switch colorMode {
        case .custom:
            return (color, color.opacity(0.95))
        case .wallpaper:
            let primary = Color(hue: Double(wallpaperPalette.hue), saturation: Double(wallpaperPalette.saturation), brightness: 1)
            let secondary = Color(hue: Double(wallpaperPalette.secondaryHue), saturation: Double(wallpaperPalette.secondarySaturation), brightness: 1)
            return (primary, secondary)
        case .fire:
            return (
                Color(hue: 0.03, saturation: 0.96, brightness: 1),
                Color(hue: 0.12, saturation: 0.9, brightness: 1)
            )
        case .dynamic:
            let primary: Color = if snap.hasCoverColor {
                Color(hue: Double(snap.coverHue), saturation: Double(snap.coverSaturation), brightness: 1)
            } else if snap.isPlaying {
                Color(hue: Double(snap.dominantHue), saturation: 0.9, brightness: 1)
            } else {
                color
            }
            let secondary = snap.hasCoverColor
                ? Color(hue: Double(snap.secondaryCoverHue), saturation: Double(snap.secondaryCoverSaturation), brightness: 1)
                : primary
            return (primary, secondary)
        }
    }
}
