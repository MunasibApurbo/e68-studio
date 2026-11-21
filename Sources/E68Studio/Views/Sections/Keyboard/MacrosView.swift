import SwiftUI

struct MacrosView: View {
    @EnvironmentObject private var store: KeyboardStore
    @StateObject private var recorder = MacroRecorder()
    @ViewState private var selected = 0

    private var slotCount: Int { min(store.macroCount, store.macros.count) }
    private var slot: Int { min(selected, max(0, slotCount - 1)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                slotList
                    .frame(width: 210)
                Divider()
                editor
            }
            Divider()
            footer
        }
        .buttonBorderShape(.capsule)
    }

    // MARK: Slot List

    private var slotList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(0..<slotCount, id: \.self) { n in
                    SlotRow(
                        n: n,
                        steps: store.macros[n],
                        isSelected: slot == n,
                        displayName: displayName(n)
                    ) {
                        selected = n
                    }
                }
            }
            .padding(10)
        }
        .glassScrollbars(top: 10, bottom: 10, trailing: 3)
    }

    private func displayName(_ n: Int) -> String {
        guard n < store.macroNames.count else { return "Macro \(n)" }
        let name = store.macroNames[n].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Macro \(n)" : name
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    SlotBadge(n: slot, emphasized: true)
                    TextField("Macro \(slot)", text: Binding(
                        get: { slot < store.macroNames.count ? store.macroNames[slot] : "" },
                        set: { store.setMacroName($0, slot: slot) }
                    ))
                    .glassField(width: 260)
                    .disabled(recorder.isRecording || slot >= store.macros.count)
                    .accessibilityLabel("Macro name")
                }
                usage
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, Space.m)

            Divider()

            if recorder.isRecording {
                recordingPanel
            } else if slot >= store.macros.count || store.macros[slot].isEmpty {
                emptyPanel
            } else {
                List {
                    ForEach($store.macros[slot]) { $step in
                        StepRow(step: $step) {
                            store.macros[slot].removeAll { $0.id == step.id }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { store.macros[slot].move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .glassScrollbars(top: 6, bottom: 6, trailing: 4)
            }

            Divider()

            HStack(spacing: Space.s) {
                Menu {
                    ForEach(MacroStep.Kind.allCases, id: \.self) { kind in
                        Button(kind.title) {
                            guard slot < store.macros.count else { return }
                            store.macros[slot].append(MacroStep(kind: kind))
                        }
                    }
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(.glassCapsule(size: .small))
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(recorder.isRecording || slot >= store.macros.count)

                Button {
                    if recorder.isRecording {
                        let recorded = recorder.stop()
                        if slot < store.macros.count {
                            store.macros[slot].append(contentsOf: recorded)
                        }
                    } else {
                        recorder.start()
                    }
                } label: {
                    Label(recorder.isRecording ? "Stop Recording" : "Record Typing",
                          systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                }
                .buttonStyle(.glassCapsule(recorder.isRecording ? .destructive : .standard, size: .small))
                .disabled(slot >= store.macros.count)

                Spacer()

                Button("Clear Steps", role: .destructive) {
                    guard slot < store.macros.count else { return }
                    store.macros[slot] = []
                }
                .buttonStyle(.glassCapsule(.destructive, size: .small))
                .disabled(slot >= store.macros.count || store.macros[slot].isEmpty || recorder.isRecording)
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.m)
        }
        .onChange(of: selected) { oldValue, _ in
            if recorder.isRecording {
                let recorded = recorder.stop()
                if oldValue < store.macros.count {
                    store.macros[oldValue].append(contentsOf: recorded)
                }
            }
        }
        .onDisappear {
            if recorder.isRecording { _ = recorder.stop() }
        }
    }

    @ViewBuilder
    private var usage: some View {
        let hits = store.keysUsingMacro(slot)
        if hits.isEmpty {
            Text("Not on any key yet")
                .font(.studioMeta)
                .foregroundStyle(Ink.secondary)
        } else {
            let places = hits.prefix(3).map { hit in
                "\(LayerInfo.title(hit.layer)) · \(Layout.positionName(hit.slot).lowercased())"
            }.joined(separator: ", ")
            Text("\(places)\(hits.count > 3 ? " +\(hits.count - 3)" : "")")
                .font(.studioMeta)
                .foregroundStyle(Ink.secondary)
                .lineLimit(1)
        }
    }

    private var emptyPanel: some View {
        EmptyStateView(
            symbol: "list.bullet.rectangle",
            title: "No steps"
        )
    }

    private var recordingPanel: some View {
        EmptyStateView(
            symbol: "record.circle",
            title: "Recording…",
            message: "\(recorder.count) key events. Type, then press Stop.",
            tint: .red
        )
        .symbolEffect(.pulse, isActive: recorder.isRecording)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Space.m) {
            let used = store.macroBytesUsed, capacity = store.macroCapacity
            CapacityBar(fraction: Double(used) / Double(max(capacity, 1)), warning: !store.macrosFit)
                .frame(width: 120)
            Text(store.macrosFit ? "\(used) / \(capacity) B" : "\(used) / \(capacity) B · Over limit")
                .font(.studioDetail.monospacedDigit())
                .foregroundStyle(store.macrosFit ? Ink.secondary : Color.red)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            if store.macrosDirty {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .labelStyle(UnsavedLabelStyle())
                    .font(.studioDetail)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Button("Revert") {
                store.revertMacros()
            }
            .buttonStyle(.glassCapsule)
            .disabled(!store.macrosDirty || recorder.isRecording)

            Button("Save to Keyboard") {
                Task { await store.writeMacros() }
            }
            .buttonStyle(.glassCapsule(.prominent))
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!store.isReady || store.busy != nil || !store.macrosDirty || !store.macrosFit || recorder.isRecording)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.m)
    }
}

private struct SlotRow: View {
    let n: Int
    let steps: [MacroStep]
    let isSelected: Bool
    let displayName: String
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SlotBadge(n: n, emphasized: isSelected || !steps.isEmpty)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.studioBody.weight(.medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(MacroCodec.summary(steps))
                        .font(.studioMeta)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.row)
            .padding(.vertical, 6)
            .frame(minHeight: Hit.row)
            .glassSelectable(RoundedRectangle(cornerRadius: Corner.control, style: .continuous), selected: isSelected, hovering: hovering)
            .contentShape(RoundedRectangle(cornerRadius: Corner.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}

/// Monospaced "M0" tag shared by the slot list and the editor header.
private struct SlotBadge: View {
    let n: Int
    var emphasized = false

    var body: some View {
        Text("M\(n)")
            .font(.system(.callout, design: .monospaced).weight(.semibold))
            .foregroundStyle(emphasized ? Color.primary : Ink.secondary)
            .frame(width: 38, height: 26)
            .nestedSurface(Capsule(), role: emphasized ? .control : .track)
    }
}

/// Small dot before "Unsaved changes".
private struct UnsavedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 6))
                .foregroundStyle(Color.orange)
            configuration.title
        }
    }
}
