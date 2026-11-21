import SwiftUI

/// Interactive 3D Keymap & Rotary Encoder remapper side panel.
/// Selecting any keycap or the rotary knob on the 3D keyboard binds VIA v9 keycodes, media actions, layers, or macros.
struct KeymapView: View {
    @EnvironmentObject private var store: KeyboardStore
    @ViewState private var selectedCategoryID = "basic"
    @ViewState private var search = ""
    @ViewState private var confirmResetLayer = false

    private var selectedSlot: Slot? {
        store.selection
    }

    private var categories: [KeyCategory] {
        Keycodes.categories(
            layerCount: store.layerCount,
            macroCount: store.macroCount,
            macroNames: store.macroNames
        )
    }

    private func filteredGroups(_ categories: [KeyCategory], active: KeyCategory) -> [KeyGroup] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return active.groups }
        return categories.flatMap { cat in
            cat.groups.compactMap { group in
                let matches = group.keys.filter {
                    $0.name.lowercased().contains(q)
                        || $0.legend.main.lowercased().contains(q)
                        || Keycodes.hex($0.code).lowercased().contains(q)
                }
                return matches.isEmpty ? nil : KeyGroup(title: "\(cat.title) · \(group.title)", keys: matches)
            }
        }
    }

    var body: some View {
        let cats = categories
        let active = cats.first { $0.id == selectedCategoryID } ?? cats[0]
        VStack(alignment: .leading, spacing: Space.s) {
            headerSection
            slotInspectorCard
            knobQuickStrip
            searchAndCategoryBar(cats, active: active)
            keycodeGrid(filteredGroups(cats, active: active))
        }
        .padding(Space.panel)
        .frame(maxHeight: SidePanel.maxHeight)
        .onAppear {
            if store.selection == nil {
                store.selection = Layout.keys.first
            }
        }
    }

    private var headerSection: some View {
        let modCount = store.modifiedCount(layer: store.activeLayer)
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text("Keymap")
                    .font(.studioTitle)
                Spacer()
                if modCount > 0 {
                    Button("Reset Layer (\(modCount))") {
                        confirmResetLayer = true
                    }
                    .buttonStyle(.glassCapsule(size: .small))
                    .disabled(!store.isReady || store.busy != nil)
                }
            }
            .confirmationDialog(
                "Reset \(LayerInfo.title(store.activeLayer)) to factory defaults?",
                isPresented: $confirmResetLayer,
                titleVisibility: .visible
            ) {
                Button("Reset \(modCount) Changed Key\(modCount == 1 ? "" : "s")", role: .destructive) {
                    Task { await store.restoreFactoryKeymap(layers: [store.activeLayer]) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Changed keys on this layer go back to their factory defaults.")
            }

            GlassSegmented(
                selection: Binding(
                    get: { store.activeLayer },
                    set: { store.activeLayer = $0 }
                ),
                options: (0..<store.layerCount).map { ($0, LayerInfo.title($0)) },
                size: .small,
                fill: true,
                marked: Set((0..<store.layerCount).filter { store.modifiedCount(layer: $0) > 0 })
            )
            .accessibilityLabel("Layer")
        }
    }

    @ViewBuilder
    private var slotInspectorCard: some View {
        if let slot = selectedSlot {
            let currentCode = store.code(layer: store.activeLayer, slot)
            let def = store.describe(currentCode)
            let modified = store.isModified(layer: store.activeLayer, slot)

            HStack(spacing: Space.m) {
                KeyCap(
                    legend: store.legend(layer: store.activeLayer, slot),
                    tone: slot.tone,
                    state: .selected,
                    modified: modified,
                    unit: 44,
                    interactive: false
                )
                .frame(width: 46, height: 44)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Layout.positionName(slot))
                        .font(.studioMeta)
                        .foregroundStyle(Ink.secondary)
                    Text(def.name)
                        .font(.studioHeading)
                        .lineLimit(1)
                    Text(Keycodes.hex(currentCode))
                        .font(.studioMeta.monospaced())
                        .foregroundStyle(Ink.secondary)
                }

                Spacer(minLength: 4)

                if modified, let factory = store.factoryCode(layer: store.activeLayer, slot) {
                    Button("Reset") {
                        store.assign(factory, layer: store.activeLayer, slot: slot)
                    }
                    .buttonStyle(.glassCapsule(size: .small))
                    .disabled(!store.isReady)
                }
            }
            .insetCard(padding: 10)
        } else {
            HStack(spacing: Space.m) {
                Image(systemName: "hand.tap")
                    .font(.title3)
                    .foregroundStyle(Ink.secondary)
                    .frame(width: 46, height: 44)
                Text("Click a key on the keyboard")
                    .font(.studioDetail)
                    .foregroundStyle(Ink.secondary)
                Spacer(minLength: 0)
            }
            .insetCard(padding: 10)
        }
    }

    private var knobQuickStrip: some View {
        let knobOptions: [(Slot, String, String)] = [
            (Layout.knobCCW, "Knob Left", "arrow.counterclockwise"),
            (Layout.knobPress, "Knob Press", "arrow.down.circle"),
            (Layout.knobCW, "Knob Right", "arrow.clockwise"),
        ]
        return HStack(spacing: 4) {
            ForEach(knobOptions, id: \.0.id) { slot, title, symbol in
                let active = selectedSlot == slot
                ChipButton(selected: active) {
                    store.selection = slot
                } label: {
                    Label(title, systemImage: symbol)
                        .font(.studioMeta.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: Hit.small)
                }
            }
        }
    }

    private func searchAndCategoryBar(_ categories: [KeyCategory], active: KeyCategory) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SearchField(prompt: "Search keys, media, layers…", text: $search)

            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(categories) { cat in
                            let selected = cat.id == active.id
                            ChipButton(selected: selected) {
                                selectedCategoryID = cat.id
                            } label: {
                                Text(cat.title)
                                    .font(.studioMeta.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .frame(height: Hit.compact)
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func keycodeGrid(_ groups: [KeyGroup]) -> some View {
        let slot = selectedSlot
        let currentCode = slot.map { store.code(layer: store.activeLayer, $0) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.s) {
                if groups.isEmpty {
                    Text("No keys match “\(search)”.")
                        .font(.studioDetail)
                        .foregroundStyle(Ink.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.xl)
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.studioMeta.weight(.semibold))
                            .foregroundStyle(Ink.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 5)], spacing: 5) {
                            ForEach(group.keys) { item in
                                let assigned = currentCode == item.code
                                ChipButton(
                                    shape: RoundedRectangle(cornerRadius: Corner.inner, style: .continuous),
                                    selected: assigned
                                ) {
                                    guard let slot else { return }
                                    store.selection = slot
                                    store.assign(item.code, layer: store.activeLayer, slot: slot)
                                } label: {
                                    VStack(spacing: 1) {
                                        if let top = item.legend.top {
                                            Text(top)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(Ink.secondary)
                                                .lineLimit(1)
                                        }
                                        if let symbol = item.legend.symbol {
                                            Image(systemName: symbol)
                                                .font(.system(size: 13, weight: .semibold))
                                        } else {
                                            Text(item.legend.main)
                                                .font(.studioDetail.weight(.medium))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .foregroundStyle(Color.primary)
                                }
                                .accessibilityLabel(item.name)
                                .help("\(item.name) (\(Keycodes.hex(item.code)))")
                                .disabled(!store.isReady || slot == nil)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .glassScrollbars(top: 4, bottom: 4, trailing: 2)
    }
}
