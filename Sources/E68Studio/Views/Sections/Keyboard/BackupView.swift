import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject private var store: KeyboardStore
    @ViewState private var pending: Backup?
    @ViewState private var confirmFactory = false
    @ViewState private var confirmErase = false

    var body: some View {
        PanelScroll {
            if !store.isReady {
                Label("Connect by USB or the 2.4 GHz receiver to back up or reset.", systemImage: "cable.connector")
                    .font(.studioDetail)
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetCard()
            }

            GroupedSection(title: "Backup") {
                GroupedRow(label: "Save backup") {
                    Button("Export…", action: export)
                        .buttonStyle(.glassCapsule(size: .small))
                        .disabled(!store.isReady)
                }
                GroupedRow(label: "Restore backup") {
                    Button("Import…", action: importFile)
                        .buttonStyle(.glassCapsule(size: .small))
                        .disabled(!store.isReady)
                }
            }

            GroupedSection(title: "Reset") {
                GroupedRow(label: "Factory keymap", detail: changedSummary) {
                    Button("Restore…") { confirmFactory = true }
                        .buttonStyle(.glassCapsule(.destructive, size: .small))
                        .disabled(!store.isReady || changedSummary == nil)
                }
                GroupedRow(label: "Macros") {
                    Button("Erase…") { confirmErase = true }
                        .buttonStyle(.glassCapsule(.destructive, size: .small))
                        .disabled(!store.isReady || (store.storedMacroImage.allSatisfy { $0 == 0 } && !store.macrosDirty))
                }
            }
        }
        .confirmationDialog("Restore the factory keymap on every layer?", isPresented: $confirmFactory) {
            Button("Restore Factory Keys", role: .destructive) {
                Task { await store.restoreFactoryKeymap() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Erase all macros from the keyboard?", isPresented: $confirmErase) {
            Button("Erase Macros", role: .destructive) {
                Task { await store.clearMacros() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Restore this backup to the keyboard?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { backup in
            Button("Restore Backup") {
                Task { await store.restore(backup) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { backup in
            Text(differenceSummary(backup))
        }
    }

    private var changedSummary: String? {
        let n = (0..<store.layerCount).reduce(0) { $0 + store.modifiedCount(layer: $1) }
        return n == 0 ? nil : "\(n) key\(n == 1 ? " differs" : "s differ")"
    }

    func differenceSummary(_ backup: Backup) -> String {
        var keyChanges = 0
        for layer in 0..<min(store.layerCount, backup.keymap.count, store.keymap.count) {
            keyChanges += Layout.all.filter { backup.keymap[layer][$0.index] != store.keymap[layer][$0.index] }.count
        }
        let restored = (0..<store.macroCount).map { $0 < backup.macros.count ? MacroCodec.decode(backup.macros[$0]) : [] }
        let macrosChanged = MacroCodec.image(restored) != store.storedMacroImage
        let lightingChanged = backup.lighting != store.lighting

        var parts = [String]()
        if keyChanges > 0 { parts.append("\(keyChanges) key\(keyChanges == 1 ? "" : "s")") }
        if macrosChanged { parts.append("macros") }
        if lightingChanged { parts.append("lighting") }
        if parts.isEmpty { return "The backup already matches your current settings." }
        return "This will update \(parts.formatted(.list(type: .and)))."
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "E68 backup \(Date().formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try KeyboardStore.encode(store.makeBackup()).write(to: url, options: .atomic)
            store.notify("Backup saved to \(url.lastPathComponent).")
        } catch {
            store.notify("The backup could not be saved. \(error.localizedDescription)", isError: true)
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pending = try KeyboardStore.decodeBackup(Data(contentsOf: url))
        } catch {
            store.notify("That file is not an E68 Studio backup.", isError: true)
        }
    }
}
