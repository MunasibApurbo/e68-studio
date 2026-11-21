import SwiftUI

struct StepRow: View {
    @Binding var step: MacroStep
    var onDelete: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: step.kind.symbol)
                .foregroundStyle(Ink.secondary)
                .frame(width: 18)
            Menu {
                Picker("Step type", selection: $step.kind) {
                    ForEach(MacroStep.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    Text(step.kind.title)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Ink.secondary)
                }
                .frame(width: 118)
            }
            .menuStyle(.button)
            .buttonStyle(.glassCapsule(size: .small))
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Step type")

            if step.kind == .text {
                TextField("Text to type", text: Binding(
                    get: { step.text },
                    set: { step.text = MacroCodec.sanitize($0) }
                ))
                .glassField()
            } else if step.kind == .delay {
                TextField("ms", value: Binding(
                    get: { step.milliseconds },
                    set: { step.milliseconds = max(1, min($0, MacroCodec.maxDelay)) }
                ), format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .glassField(width: 90)
                Text("milliseconds")
                    .font(.studioDetail)
                    .foregroundStyle(Ink.secondary)
                Spacer()
            } else {
                KeyChooser(key: $step.key)
                Spacer()
            }

            IconButton(symbol: "trash", label: "Remove Step", tint: hovering ? .red : nil, action: onDelete)
        }
        .frame(minHeight: Hit.row)
        .onHover { hovering = $0 }
    }
}

/// Button that shows a key and opens a searchable grid to change it.
struct KeyChooser: View {
    @Binding var key: UInt8
    @ViewState private var open = false
    @ViewState private var search = ""

    private var groups: [KeyGroup] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Keycodes.macroCandidates }
        return Keycodes.macroCandidates.compactMap { group in
            let keys = group.keys.filter { $0.name.lowercased().contains(q) || $0.legend.main.lowercased().contains(q) }
            return keys.isEmpty ? nil : KeyGroup(title: group.title, keys: keys)
        }
    }

    var body: some View {
        Button {
            open = true
        } label: {
            HStack(spacing: 6) {
                Text(Keycodes.def(for: UInt16(key)).name)
                    .font(.studioBody)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: Hit.small)
            .glassSurface(interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .onChange(of: open) { _, isOpen in
            if isOpen { search = "" }
        }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                SearchField(prompt: "Search keys", text: $search)
                ScrollView {
                    if groups.isEmpty {
                        Text("No keys match “\(search)”")
                            .font(.studioDetail)
                            .foregroundStyle(Ink.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(group.title)
                                        .font(.studioMeta.weight(.semibold))
                                        .foregroundStyle(Ink.secondary)
                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: 52), spacing: 5)],
                                        spacing: 5
                                    ) {
                                        ForEach(group.keys) { def in
                                            Button {
                                                key = UInt8(def.code & 0xff)
                                                open = false
                                            } label: {
                                                KeyCap(legend: def.legend, state: UInt16(key) == def.code ? .selected : .normal, unit: 44)
                                                    .frame(width: 48, height: 44)
                                                    .frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(.plain)
                                            .help(def.name)
                                            .accessibilityLabel(def.name)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .glassScrollbars(top: 4, bottom: 4, trailing: 0)
            }
            .environment(\.insideGlassPanel, true)
            .padding(14)
            .frame(width: 420, height: 380)
            .studioAppearance()
        }
    }
}
