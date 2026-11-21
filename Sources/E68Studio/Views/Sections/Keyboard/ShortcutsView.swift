import SwiftUI

struct ShortcutsView: View {
    @EnvironmentObject private var store: KeyboardStore

    private struct Entry: Identifiable {
        let slot: Slot
        let base: Legend
        let action: KeyDef
        var id: Int { slot.index }
    }

    private struct Group: Identifiable {
        let title: String
        var entries: [Entry]
        var id: String { title }
    }

    private static let order = [
        "Connection",
        "Backlight",
        "Device",
        "Media",
        "Function row",
        "Navigation and system",
        "Macros",
        "Mouse",
        "Keyboard",
    ]

    private static func groupTitle(for code: UInt16) -> String {
        switch code {
        case Keycodes.customBase...(Keycodes.customBase + 3): return "Connection"
        case (Keycodes.customBase + 4)...(Keycodes.customBase + 0x7f), 0x5C00: return "Device"
        case 0x5CC2...0x5CCC: return "Backlight"
        case 0xA5...0xBE: return "Media"
        case 0x3A...0x45, 0x68...0x73: return "Function row"
        case 0x46...0x52: return "Navigation and system"
        case Keycodes.macroBase...(Keycodes.macroBase + 15): return "Macros"
        case 0xF0...0xFC: return "Mouse"
        default: return "Keyboard"
        }
    }

    private var groups: [Group] {
        guard store.keymap.count > 1 else { return [] }
        var byTitle = [String: [Entry]]()
        for slot in Layout.keys {
            let fn = store.code(layer: 1, slot)
            let base = store.code(layer: 0, slot)
            guard fn != base, fn != Keycodes.none, fn != Keycodes.transparent else { continue }
            let entry = Entry(slot: slot, base: store.describe(base).legend, action: store.describe(fn))
            byTitle[Self.groupTitle(for: fn), default: []].append(entry)
        }
        return Self.order.compactMap { title in
            byTitle[title].map { Group(title: title, entries: $0) }
        }
    }

    var body: some View {
        PanelScroll(maxWidth: 860) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(group.title)
                            .font(.studioHeading)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 28, alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                                  alignment: .leading, spacing: 7) {
                            ForEach(group.entries) { entry in
                                HStack(spacing: 6) {
                                    HStack(spacing: 6) {
                                        KeyCap(legend: Legend(main: "Fn"), tone: .mod, unit: 36, interactive: false)
                                            .frame(width: 40, height: 34)
                                        Text("+").foregroundStyle(Ink.secondary)
                                        KeyCap(legend: entry.base, tone: entry.slot.tone, unit: 36, interactive: false)
                                            .frame(width: max(40, min(CGFloat(entry.slot.w) * 36, 76)), height: 34)
                                    }
                                    .frame(minWidth: 138, alignment: .leading)
                                    Text(entry.action.name)
                                        .font(.studioBody)
                                        .padding(.leading, 6)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Fn plus \(store.describe(store.code(layer: 0, entry.slot)).name): \(entry.action.name)")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Knob")
                        .font(.studioHeading)
                    ForEach(Array(zip(Layout.knob, ["Turn left", "Press", "Turn right"])), id: \.0.id) { slot, gesture in
                        let baseCode = store.code(layer: 0, slot)
                        let fnCode = store.keymap.count > 1 ? store.code(layer: 1, slot) : Keycodes.transparent
                        let fnDistinct = fnCode != Keycodes.transparent && fnCode != Keycodes.none && fnCode != baseCode
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Text(gesture)
                                    .font(.studioBody)
                                    .frame(width: 112, alignment: .leading)
                                    .foregroundStyle(Ink.secondary)
                                Text(store.describe(baseCode).name)
                                    .font(.studioBody)
                            }
                            if fnDistinct {
                                HStack(spacing: 10) {
                                    Text("Fn + \(gesture.lowercased())")
                                        .font(.studioBody)
                                        .frame(width: 112, alignment: .leading)
                                        .foregroundStyle(Ink.secondary)
                                    Text(store.describe(fnCode).name)
                                        .font(.studioBody)
                                }
                            }
                        }
                    }
                }
        }
    }
}
