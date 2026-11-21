import Foundation
/// `E68Studio --backup <file>`: connects without a window, reads the keyboard and writes the same
/// backup file as Backup › Export. Used before risky experiments.
enum BackupCLI {
    static func run(path: String) -> Never {
        Task { @MainActor in
            let store = KeyboardStore()
            store.start()
            for _ in 0..<150 {
                try? await Task.sleep(for: .milliseconds(100))
                if store.isReady { break }
            }
            guard store.isReady else {
                print("FAIL  keyboard not ready over USB/2.4 GHz")
                exit(1)
            }
            // Give macro and lighting reads a moment to land after the keymap.
            try? await Task.sleep(for: .seconds(2))
            do {
                let url = URL(fileURLWithPath: path)
                try KeyboardStore.encode(store.makeBackup()).write(to: url, options: .atomic)
                print("OK    backup written to \(url.path) (\(store.keymap.count) layers, \(store.macros.filter { !$0.isEmpty }.count) macros)")
                exit(0)
            } catch {
                print("FAIL  \(error.localizedDescription)")
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(0)
    }
}
