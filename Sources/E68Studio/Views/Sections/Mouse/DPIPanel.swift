import SwiftUI

// MARK: - DPI

struct DPIPanel: View {
    @ObservedObject private var mouse = MouseStore.shared

    private static let storedChoices = [400, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000, 6400, 8000, 12000]

    var body: some View {
        FittedScroll(maxHeight: SidePanel.maxHeight) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $mouse.customEnabled.animation(.smooth(duration: 0.25))) {
                    Text("Custom DPI").font(.studioTitle)
                }
                .toggleStyle(AccentSwitchStyle())

                if mouse.info == nil {
                    Caption("Mouse not connected — changes apply automatically when your G7 reconnects.")
                }

                if !mouse.customEnabled {
                    Caption("Off: the mouse follows the macOS pointer speed.")
                }

                if mouse.customEnabled {
                    Group {
                        stages
                        sniper
                        movement
                        stored
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if mouse.lastApplyFailed {
                    Label("That change didn’t apply. Reconnect the mouse and try again.", systemImage: "exclamationmark.triangle.fill")
                        .font(.studioMeta)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.panel)
        }
    }

    private var stages: some View {
        let enabledCount = mouse.stages.filter(\.enabled).count
        return VStack(alignment: .leading, spacing: 6) {
            FieldHeader(title: "Stages", value: mouse.sniperActive ? "Sniper \(mouse.appliedDPI) DPI" : "\(String(mouse.appliedDPI)) DPI")
            VStack(spacing: 2) {
                ForEach(Array(mouse.stages.enumerated()), id: \.element.id) { index, stage in
                    StageRow(
                        displayIndex: index,
                        stage: stage,
                        active: isActive(stage),
                        canTurnOff: enabledCount > 1,
                        canRemove: mouse.stages.count > 1
                    )
                }
            }
            if mouse.appliedDPI != mouse.effectiveDPI {
                Caption("Target \(mouse.effectiveDPI) DPI is clamped to \(mouse.appliedDPI) DPI (macOS supports 0.05×–8× of \(mouse.hardwareDPI) Hardware DPI).")
            }
            HStack(spacing: Space.s) {
                Button {
                    addStage()
                } label: {
                    Label("Add Stage", systemImage: "plus")
                }
                .buttonStyle(.glassCapsule(size: .small))
                .disabled(mouse.stages.count >= 8)
                Spacer()
                Button("Reset") { mouse.resetStages() }
                    .buttonStyle(.glassCapsule(size: .small))
            }
        }
    }

    private func isActive(_ stage: DPIStage) -> Bool {
        !mouse.sniperActive && mouse.currentStage?.id == stage.id
    }

    private var sniper: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldHeader(title: "Sniper (while held)", value: "\(mouse.sniperDPI) DPI")
            StepSlider(
                value: Binding(
                    get: { min(max(mouse.sniperDPI / 100, 1), 16) },
                    set: { mouse.sniperDPI = $0 * 100 }
                ),
                range: 1...16,
                label: "Sniper DPI",
                accessibilityValueText: "\(mouse.sniperDPI) DPI"
            )
        }
    }

    private var movement: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SwitchRow(title: "Raw movement", detail: "No acceleration", isOn: $mouse.accelerationOff)
            if !mouse.accelerationOff {
                VStack(alignment: .leading, spacing: 4) {
                    let accelText = "\(Int((mouse.speed * 100).rounded()))%"
                    FieldHeader(title: "Acceleration", value: accelText)
                    StepSlider(
                        value: Binding(
                            get: { min(max(Int((mouse.speed * 40).rounded()), 0), 40) },
                            set: { mouse.speed = Double($0) / 40 }
                        ),
                        range: 0...40,
                        label: "Acceleration",
                        accessibilityValueText: "\(Int((mouse.speed * 100).rounded())) percent"
                    )
                }
                .transition(.opacity)
            }
        }
    }

    private var stored: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Mouse Hardware DPI").font(.studioHeading)
                Spacer()
                Menu {
                    Picker("Mouse Hardware DPI", selection: $mouse.hardwareDPI) {
                        ForEach(Self.storedChoices, id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: String(mouse.hardwareDPI)).monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Ink.secondary)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.glassCapsule(size: .small))
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Match the hardware DPI set in your mouse so stages scale accurately")
                .accessibilityLabel("Mouse Hardware DPI")
            }
            SwitchRow(title: "Show DPI on screen", isOn: $mouse.showStageHUD)
            Caption("DPI and acceleration stay active in macOS after quitting until the mouse reconnects.")
        }
    }

    private func addStage() {
        let top = mouse.stages.map(\.dpi).max() ?? 1600
        let used = Set(mouse.stages.map(\.colorIndex))
        let color = (0..<DPIStage.palette.count).first { !used.contains($0) } ?? (mouse.stages.count % DPIStage.palette.count)
        mouse.stages.append(DPIStage(dpi: min(top * 2, 12000), colorIndex: color))
    }
}

private struct StageRow: View {
    let displayIndex: Int
    let stage: DPIStage
    let active: Bool
    let canTurnOff: Bool
    let canRemove: Bool
    @ObservedObject private var mouse = MouseStore.shared
    @ViewState private var hovering = false

    private var currentIndex: Int? {
        mouse.stages.firstIndex(where: { $0.id == stage.id })
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                guard let idx = currentIndex else { return }
                mouse.stages[idx].colorIndex = (mouse.stages[idx].colorIndex + 1) % DPIStage.palette.count
            } label: {
                Circle()
                    .fill(stageColor(stage.colorIndex).gradient)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 14, height: 14)
                    .shadow(color: stageColor(stage.colorIndex).opacity(active ? 0.9 : 0), radius: 4)
                    .frame(width: Hit.compact, height: Hit.compact)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .help("Change this stage's colour")
            .accessibilityLabel("Stage \(displayIndex + 1) colour")

            Button {
                guard stage.enabled, let i = mouse.stages.filter(\.enabled).firstIndex(where: { $0.id == stage.id }) else { return }
                mouse.selectStage(i)
            } label: {
                Text("Stage \(displayIndex + 1)")
                    .font(.studioBody.weight(active ? .semibold : .regular))
                    .foregroundStyle(stage.enabled ? Color.primary : Ink.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Hit.small)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!stage.enabled)
            .accessibilityHint(active ? "In use" : "Use this stage")

            DPIStepper(value: Binding(
                get: { currentIndex.map { mouse.stages[$0].dpi } ?? stage.dpi },
                set: { newValue in
                    guard let idx = currentIndex else { return }
                    mouse.stages[idx].dpi = newValue
                }
            ))
            .disabled(!stage.enabled)

            Toggle("Stage \(displayIndex + 1) on", isOn: Binding(
                get: { stage.enabled },
                set: { on in
                    guard let idx = currentIndex, on || canTurnOff else { return }
                    mouse.stages[idx].enabled = on
                }
            ))
            .labelsHidden()
            .toggleStyle(AccentSwitchStyle())
            .disabled(stage.enabled && !canTurnOff)
            .accessibilityLabel("Stage \(displayIndex + 1)")
        }
        // The colour dot sits in a 28 pt hit area, so its visible edge lines up with other rows.
        .padding(.leading, Space.row - 7)
        .padding(.trailing, Space.row)
        .padding(.vertical, 1)
        .frame(minHeight: 32)
        .glassSelectable(RoundedRectangle(cornerRadius: Corner.control, style: .continuous), selected: active, hovering: hovering)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: active)
        .contextMenu {
            Button("Remove Stage \(displayIndex + 1)", role: .destructive) {
                guard canRemove, let idx = currentIndex else { return }
                mouse.stages.remove(at: idx)
            }
            .disabled(!canRemove)
        }
    }
}

/// DPI value with − and + (50 DPI steps, 100 above 2000). Hold a button to keep stepping.
private struct DPIStepper: View {
    @Binding var value: Int
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            step(-1, "minus")
                .disabled(value <= 50)
            Text(verbatim: String(value))
                .font(.studioBody.monospacedDigit().weight(.medium))
                .foregroundStyle(isEnabled ? Color.primary : Ink.secondary)
                .lineLimit(1)
                .frame(minWidth: 48)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.15), value: value)
            step(1, "plus")
                .disabled(value >= 12000)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("DPI")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: bump(1)
            case .decrement: bump(-1)
            @unknown default: break
            }
        }
    }

    private func step(_ dir: Int, _ symbol: String) -> some View {
        IconButton(symbol: symbol, label: dir > 0 ? "Raise DPI" : "Lower DPI",
                   size: Hit.compact, repeats: true) { bump(dir) }
    }

    private func bump(_ dir: Int) {
        let size = (dir > 0 ? value >= 2000 : value > 2000) ? 100 : 50
        value = min(max(value + dir * size, 50), 12000)
    }
}
