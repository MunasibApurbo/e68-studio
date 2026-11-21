import SwiftUI

/// Minimal lighting controls with beat-reactive sync to Mac audio output and Screen Glow.
struct LightPanel: View {
    @EnvironmentObject private var store: KeyboardStore

    private static let hueGradientColors: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        Color(hue: $0, saturation: 1, brightness: 1)
    }

    private var lighting: LightingState { store.lighting }
    private var lightingActive: Bool { lighting.isOn || store.screenSync }

    var body: some View {
        FittedScroll(maxHeight: SidePanel.maxHeight) {
            panelContent
        }
        .disabled(!store.isReady)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Toggle(isOn: Binding(
                get: { lightingActive },
                set: { on in
                    withAnimation(.smooth(duration: 0.25)) {
                        store.setBacklightOn(on)
                    }
                }
            )) {
                Text("Backlight").font(.studioTitle)
            }
            .toggleStyle(AccentSwitchStyle())

            SoundWaveSyncCard(store: store, lighting: lighting)

            ScreenGlowCard(store: store)

            if !lighting.musicSync && !store.screenSync {
                VStack(alignment: .leading, spacing: Space.s) {
                    FieldHeader(
                        title: "Effect",
                        value: lighting.isOn ? nil : "Off"
                    )
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.xs), GridItem(.flexible())], spacing: Space.xs) {
                        ForEach(LightingCatalog.selectableEffects) { effect in
                            EffectButton(effect: effect, selected: lighting.isOn && lighting.effect == effect.id) {
                                store.updateLighting([.effect]) { $0.effect = effect.id }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    FieldHeader(title: "Speed", value: "\(lighting.speed)")
                    StepSlider(
                        value: Binding(
                            get: { lighting.speed },
                            set: { v in store.updateLighting([.speed]) { $0.speed = v } }
                        ),
                        range: LightingCatalog.minSpeed...LightingCatalog.maxSpeed,
                        label: "Speed",
                        accessibilityValueText: "\(lighting.speed) of \(LightingCatalog.maxSpeed)"
                    )
                }
                .disabled(!lightingActive)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                let title = (lighting.musicSync || store.screenSync) ? "Max Brightness" : "Brightness"
                FieldHeader(title: title, value: "\(lighting.brightness)")
                StepSlider(
                    value: Binding(
                        get: { lighting.brightness },
                        set: { v in store.updateLighting([.brightness]) { $0.brightness = v } }
                    ),
                    range: 0...LightingCatalog.maxBrightness,
                    label: title,
                    accessibilityValueText: "\(lighting.brightness) of \(LightingCatalog.maxBrightness)"
                )
            }
            .disabled(!lightingActive)

            if !lighting.musicSync && !store.screenSync {
                Toggle(isOn: Binding(
                    get: { lighting.reactiveTypingRipple },
                    set: { on in
                        withAnimation(.smooth(duration: 0.2)) {
                            store.lighting.reactiveTypingRipple = on
                        }
                    }
                )) {
                    Text("Key Ripples")
                        .font(.studioHeading)
                }
                .toggleStyle(AccentSwitchStyle())
                .disabled(!lightingActive)
            }

            // Colour is available offline or in custom music colour mode.
            if !store.screenSync && (!lighting.musicSync || lighting.musicColorMode == .custom) {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack {
                        Text("Colour")
                            .font(.studioHeading)
                            .dimsWhenDisabled()
                        Spacer()
                        Button {
                            store.applyWallpaperColor()
                        } label: {
                            Label("From Wallpaper", systemImage: "photo")
                        }
                        .buttonStyle(.glassCapsule(size: .small))
                        .help("Use the main colour of your desktop picture")
                    }
                    GradientSlider(
                        value: Binding(
                            get: { Double(lighting.hue) / 255 },
                            set: { v in store.updateLighting([.color]) { $0.hue = UInt8((v * 255).rounded()) } }
                        ),
                        colors: Self.hueGradientColors,
                        knobColor: Color(hue: Double(lighting.hue) / 255, saturation: 1, brightness: 1)
                    )
                    .accessibilityLabel("Hue")
                    GradientSlider(
                        value: Binding(
                            get: { Double(lighting.saturation) / 255 },
                            set: { v in store.updateLighting([.color]) { $0.saturation = UInt8((v * 255).rounded()) } }
                        ),
                        colors: [.white, Color(hue: Double(lighting.hue) / 255, saturation: 1, brightness: 1)],
                        knobColor: Color(hue: Double(lighting.hue) / 255, saturation: Double(lighting.saturation) / 255, brightness: 1)
                    )
                    .accessibilityLabel("Saturation")
                    LightingSwatchesView(swatchSize: 20)
                        .padding(.top, 2)
                }
                .disabled(!lightingActive)
            }
        }
        .padding(Space.panel)
    }
}

/// Row of preset colour swatches shared between the Studio lighting panel and the menu bar popover.
struct LightingSwatchesView: View {
    @EnvironmentObject private var store: KeyboardStore
    var swatchSize: CGFloat = 20

    var body: some View {
        let lighting = store.lighting
        HStack(spacing: 0) {
            ForEach(Array(LightingCatalog.swatches.enumerated()), id: \.element.id) { index, swatch in
                let isCurrent = lighting.hue == swatch.hue && lighting.saturation == swatch.saturation
                if index > 0 { Spacer(minLength: 4) }
                Button {
                    store.updateLighting([.color]) {
                        $0.hue = swatch.hue
                        $0.saturation = swatch.saturation
                    }
                } label: {
                    Circle()
                        .fill(Color(hue: Double(swatch.hue) / 255, saturation: Double(swatch.saturation) / 255, brightness: 1).gradient)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.16), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                        .frame(width: swatchSize, height: swatchSize)
                        .padding(3)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(isCurrent ? 0.85 : 0), lineWidth: 2))
                        .scaleEffect(isCurrent ? 1 : 0.92)
                        .animation(.snappy(duration: 0.18), value: isCurrent)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                .help(swatch.name)
                .accessibilityLabel(swatch.name)
            }
        }
        .dimsWhenDisabled()
    }
}

private struct EffectButton: View {
    let effect: LightingEffect
    let selected: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(effect.name)
                .font(.studioBody.weight(selected ? .semibold : .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: Hit.small)
                .chip(selected: selected, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: selected)

        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
