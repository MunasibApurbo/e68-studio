import Foundation

struct Backup: Codable {
    var format = "e68-studio-backup"
    var version = 1
    var product: String
    var firmware: String
    var created: Date
    var keymap: [[UInt16]]
    var macros: [[UInt8]]
    var macroNames: [String]
    var lighting: LightingState
}

extension KeyboardStore {
    func makeBackup() -> Backup {
        Backup(
            product: device?.product ?? "E-68 PRO",
            firmware: device?.firmware ?? "",
            created: Date(),
            keymap: keymap,
            macros: macros.map { MacroCodec.encode($0) },
            macroNames: macroNames,
            lighting: lighting
        )
    }

    static func encode(_ backup: Backup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decodeBackup(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        guard backup.format == "e68-studio-backup",
              backup.version == 1,
              !backup.keymap.isEmpty,
              backup.keymap.allSatisfy({ $0.count == VIA.cellsPerLayer }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return backup
    }

    func restore(_ backup: Backup) async {
        guard isReady else { return }
        guard let changed = await applyKeymap(backup.keymap, label: "Restoring keymap…") else { return }

        let restored = (0..<macroCount).map { $0 < backup.macros.count ? MacroCodec.decode(backup.macros[$0]) : [] }
        var macroNote = ""
        if MacroCodec.image(restored) != storedMacroImage {
            macros = restored
            if macrosFit {
                if await writeMacros() {
                    macroNote = ", macros rewritten"
                } else {
                    revertMacros()
                    macroNote = ", macros failed to write"
                }
            } else {
                revertMacros()
                macroNote = ", macros skipped (too large)"
            }
        }
        macroNames = Array(repeating: "", count: 16)
        for (i, name) in backup.macroNames.enumerated() where i < macroNames.count { macroNames[i] = name }
        defaults.set(macroNames, forKey: "macroNames")

        if screenSync {
            disableScreenSyncWithoutRestoring()
        }
        let wasMusic = lighting.musicSync
        var restoredLighting = backup.lighting
        if restoredLighting.musicSync && (restoredLighting.effect == 0 || restoredLighting.brightness == 0) {
            if restoredLighting.effect == 0 {
                restoredLighting.effect = restoredLighting.lastEffect == 0 ? 6 : restoredLighting.lastEffect
            }
            if restoredLighting.brightness == 0 {
                restoredLighting.brightness = 6
            }
        }
        lighting = restoredLighting
        if restoredLighting.musicSync {
            lightingNeedsSave = true
            audioMonitor.start()
            startHardwareMusicSync()
        } else {
            if wasMusic {
                cancelMusicSyncAndAudioWithoutRestoring()
            }
            queueLighting([.effect, .brightness, .speed, .color])
        }
        notify("Backup restored: \(changed) key\(changed == 1 ? "" : "s") changed\(macroNote), lighting applied.")
    }
}
