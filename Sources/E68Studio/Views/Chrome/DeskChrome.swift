import SwiftUI

/// Root window chrome for the 3D desk overview: device pills, room ambience controls,
/// camera angle selector, and the floating Keyboard / Mouse studio switcher.
struct DeskChrome: View {
    @EnvironmentObject private var store: KeyboardStore
    @Binding var deskPreset: DeskCameraPreset
    @AppStorage(AmbienceKeys.deskLampOn) private var deskLampOn = true
    @AppStorage(AmbienceKeys.deskLampBrightness) private var deskLampBrightness = 1.0
    @AppStorage(AmbienceKeys.deskLampColor) private var deskLampColor: DeskLampColor = .warm
    @AppStorage(AmbienceKeys.deskMood) private var deskMood: DeskMood = .daylight
    @AppStorage(AmbienceKeys.deskScenario) private var deskScenario: DeskScenario = .swissAlps

    var body: some View {
        VStack {
            GlassContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        devicePills(compact: false)
                        devicePills(compact: true)
                    }

                    Spacer(minLength: Space.s)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            ambienceBar
                            GlassSegmented(
                                selection: $deskPreset,
                                options: DeskCameraPreset.allCases.map { ($0, $0.rawValue) },
                                placement: .floating,
                                size: .small
                            )
                            .fixedSize()
                            .accessibilityLabel("Camera angle")
                        }
                        HStack(spacing: 10) {
                            ambienceBar
                            cameraMenu
                        }
                    }
                    .layoutPriority(1)
                }
            }
            .topChromeInsets()

            Spacer()

            HStack(spacing: Space.xs) {
                Button {
                    store.enterStudio()
                } label: {
                    Label("Keyboard", systemImage: "keyboard")
                }
                .keyboardShortcut(.defaultAction)
                Button {
                    store.enterMouseStudio()
                } label: {
                    Label("Mouse", systemImage: "computermouse")
                }
            }
            .buttonStyle(.glassCapsule)
            .environment(\.insideGlassPanel, true)
            .padding(4)
            .glassSurface(elevation: .medium, scrim: true)
            .help("Or click the keyboard or mouse on the desk")
            .padding(.bottom, Space.l)
        }
    }

    /// Narrow-window stand-in for the camera segmented control.
    private var cameraMenu: some View {
        Menu {
            Picker("Camera", selection: $deskPreset) {
                ForEach(DeskCameraPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(deskPreset.rawValue, systemImage: "camera")
        }
        .menuStyle(.button)
        .buttonStyle(.glassCapsule(size: .small))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Camera angle")
    }

    /// World, day or night, lamp: one icon each, names in the tooltips.
    private var ambienceBar: some View {
        HStack(spacing: 1) {
            ScenarioPickerControl(scenario: $deskScenario)
            AmbienceToggle(symbol: deskMood.symbol, label: "Night lighting", isOn: Binding(
                get: { deskMood == .midnight },
                set: { night in withAnimation(Motion.swap) { deskMood = night ? .midnight : .daylight } }
            ))
            DeskLampControl(isOn: $deskLampOn, brightness: $deskLampBrightness, color: $deskLampColor)
        }
        .environment(\.insideGlassPanel, true)
        .padding(3)
        .glassSurface(elevation: .low, scrim: true)
    }

    /// Both devices in one capsule: a status light and a name each, split by a hairline.
    private func devicePills(compact: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                store.enterStudio()
            } label: {
                StatusPill(compact: compact, bare: true)
            }
            .buttonStyle(PressScaleButtonStyle())
            .help("Open Keyboard Studio")

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 14)

            Button {
                store.enterMouseStudio()
            } label: {
                MouseStatusPill(compact: compact, bare: true)
            }
            .buttonStyle(PressScaleButtonStyle())
            .help("Open Mouse Studio")
        }
        .glassSurface(elevation: .low, scrim: true)
        .fixedSize()
    }
}

/// Icon toggle inside the desk's ambience bar.
private struct AmbienceToggle: View {
    let symbol: String
    let label: String
    @Binding var isOn: Bool
    @ViewState private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.studioMeta.weight(.semibold))
                .foregroundStyle(isOn ? Color.primary : Ink.secondary)
                .frame(width: 32, height: Hit.compact)
                .glassSelectable(Capsule(), selected: isOn, hovering: hovering)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The desk lamp: click to open its switch, brightness and colour.
private struct DeskLampControl: View {
    @Binding var isOn: Bool
    @Binding var brightness: Double
    @Binding var color: DeskLampColor
    @ViewState private var showPanel = false
    @ViewState private var hovering = false

    var body: some View {
        Button {
            showPanel.toggle()
        } label: {
            Image(systemName: isOn ? "lamp.desk.fill" : "lamp.desk")
                .font(.studioMeta.weight(.semibold))
                .foregroundStyle(isOn ? Color.primary : Ink.secondary)
                .frame(width: 32, height: Hit.compact)
                .glassSelectable(Capsule(), selected: isOn, hovering: hovering)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hovering = $0 }
        .help("Desk lamp")
        .accessibilityLabel("Desk lamp")
        .accessibilityValue(isOn ? "On" : "Off")
        .popover(isPresented: $showPanel, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Desk lamp", isOn: $isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.studioMeta.weight(.medium))

                HStack(spacing: 8) {
                    Image(systemName: "sun.min")
                        .accessibilityHidden(true)
                    Slider(value: $brightness, in: 0.3...2.5)
                        .controlSize(.small)
                        .accessibilityLabel("Desk lamp brightness")
                    Image(systemName: "sun.max.fill")
                        .accessibilityHidden(true)
                }
                .font(.studioMeta)
                .foregroundStyle(Ink.secondary)
                .disabled(!isOn)

                HStack(spacing: 4) {
                    ForEach(DeskLampColor.allCases) { option in
                        Button {
                            color = option
                        } label: {
                            Circle()
                                .fill(option.swatch)
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(option == color ? 0.9 : 0.18), lineWidth: option == color ? 2 : 1))
                                .frame(width: Hit.compact, height: Hit.compact)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(option == color ? .isSelected : [])
                    }
                }
                .disabled(!isOn)
                .opacity(isOn ? 1 : 0.45)
            }
            .padding(14)
            .frame(width: 190)
            .environment(\.insideGlassPanel, true)
            .studioAppearance()
        }
    }
}

/// The current world as an icon and name; opens a small grid of all of them.
private struct ScenarioPickerControl: View {
    @Binding var scenario: DeskScenario
    @ViewState private var showPicker = false
    @ViewState private var hovering = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scenario.symbol)
                    .font(.studioMeta.weight(.semibold))
                ViewThatFits(in: .horizontal) {
                    Text(scenario.title)
                        .font(.studioMeta.weight(.medium))
                        .lineLimit(1)
                    EmptyView()
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: Hit.compact)
            .glassSelectable(Capsule(), selected: showPicker, hovering: hovering)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hovering = $0 }
        .help("World: \(scenario.title)")
        .accessibilityLabel("World")
        .accessibilityValue(scenario.title)
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            ScenarioPickerPopover(selection: $scenario)
        }
    }
}

private struct ScenarioPickerPopover: View {
    @Binding var selection: DeskScenario
    private let columns = Array(repeating: GridItem(.fixed(132), spacing: 4), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(DeskScenario.allCases) { item in
                ScenarioRow(item: item, selected: item == selection) {
                    selection = item
                }
            }
        }
        .padding(8)
        .environment(\.insideGlassPanel, true)
        .studioAppearance()
    }
}

private struct ScenarioRow: View {
    let item: DeskScenario
    let selected: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.studioMeta.weight(.semibold))
                    .foregroundStyle(selected ? Color.primary : Ink.secondary)
                    .frame(width: 18)
                Text(item.title)
                    .font(.studioMeta.weight(selected ? .semibold : .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: Hit.compact)
            .glassSelectable(RoundedRectangle(cornerRadius: Corner.inner, style: .continuous), selected: selected, hovering: hovering)
            .contentShape(RoundedRectangle(cornerRadius: Corner.inner, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
