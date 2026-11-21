import SwiftUI
import AppKit

@main
enum Main {
    static func main() {
        if E68Perf.enabled {
            E68Perf.processStartTime = CACurrentMediaTime()
        }
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            SelfTest.run()
        } else if let i = args.firstIndex(of: "--backup"), i + 1 < args.count {
            BackupCLI.run(path: args[i + 1])
        } else if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            SceneRender.run(directory: args[i + 1])
        } else if let i = args.firstIndex(of: "--render-scenarios"), i + 1 < args.count {
            SceneRender.runScenarios(directory: args[i + 1])
        } else if let i = args.firstIndex(of: "--render-closeups"), i + 1 < args.count {
            SceneRender.runCloseups(directory: args[i + 1])
        } else if let i = args.firstIndex(of: "--render-switch"), i + 1 < args.count {
            SceneRender.runSwitch(directory: args[i + 1])
        } else if let i = args.firstIndex(of: "--render-motion"), i + 1 < args.count {
            SceneRender.runMotion(directory: args[i + 1])
        } else {
            warmTextSystem()
            E68StudioApp.main()
        }
    }

    /// The first string drawn in a process initialises AppKit's text system, which registers
    /// user defaults. If that first draw happens while SwiftUI is building the window (the 3D
    /// scene paints text into its textures there), SwiftUI's `@AppStorage` observer waits on the
    /// lock SwiftUI already holds and the main thread deadlocks. Drawing once up front avoids it.
    private static func warmTextSystem() {
        guard let ctx = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        ("E68" as NSString).draw(in: CGRect(x: 0, y: 0, width: 4, height: 4), withAttributes: [.font: NSFont.systemFont(ofSize: 4)])
        NSGraphicsContext.restoreGraphicsState()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = KeyboardStore()
    private var closeObserver: NSObjectProtocol?
    var openMainWindowAction: (() -> Void)?

    override init() {
        super.init()
        MenuBarSettings.registerDefaults()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MouseStore.shared.start()
        store.start()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let closingWindow = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                self?.handleWindowDidClose(closingWindow)
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.reconcileInitialWindowPolicy()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        store.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MenuBarSettings.shouldKeepAliveInMenuBar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            reopenMainWindow()
        }
        return true
    }

    func reopenMainWindow() {
        if let existing = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "e68-main-window" && ($0.isVisible || $0.isMiniaturized)
        }) {
            NSApp.setActivationPolicy(.regular)
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else if let openMainWindowAction {
            NSApp.setActivationPolicy(.regular)
            openMainWindowAction()
            NSApp.activate(ignoringOtherApps: true)
        } else if let fallback = NSApp.windows.first(where: { $0.identifier?.rawValue == "e68-main-window" }) {
            NSApp.setActivationPolicy(.regular)
            fallback.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func reconcileInitialWindowPolicy() {
        guard !hasVisibleMainWindow else { return }
        if MenuBarSettings.shouldKeepAliveInMenuBar {
            LiveMirror.shared.setWindowVisible(false)
            NSApp.setActivationPolicy(.accessory)
        } else {
            reopenMainWindow()
        }
    }

    var hasVisibleMainWindow: Bool {
        NSApp.windows.contains { window in
            guard window.isVisible, window.level == .normal else { return false }
            let className = NSStringFromClass(type(of: window))
            if className.contains("StatusBar") || className.contains("MenuBarExtra") {
                return false
            }
            return window.canBecomeMain || window.identifier?.rawValue == "e68-main-window"
        }
    }

    private func handleWindowDidClose(_ closingWindow: NSWindow) {
        let closingClass = NSStringFromClass(type(of: closingWindow))
        if closingClass.contains("StatusBar") || closingClass.contains("MenuBarExtra") {
            return
        }
        DispatchQueue.main.async {
            guard MenuBarSettings.shouldKeepAliveInMenuBar else { return }
            let hasOtherVisibleWindow = NSApp.windows.contains { window in
                guard window !== closingWindow, window.isVisible, window.level == .normal else { return false }
                let className = NSStringFromClass(type(of: window))
                if className.contains("StatusBar") || className.contains("MenuBarExtra") {
                    return false
                }
                return window.canBecomeMain || window.identifier?.rawValue == "e68-main-window"
            }
            if !hasOtherVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

struct E68StudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(MenuBarKeys.showInMenuBar) private var showInMenuBar = true
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        let _ = wireDelegate()
        Window("E68 Studio", id: "main") {
            ContentView()
                .environmentObject(delegate.store)
                .studioAppearance()
                .frame(minWidth: 780, maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
                .onAppear {
                    wireDelegate()
                    delegate.store.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1180, height: 740)
        // `-e68.startIn` (screenshots, jumping straight to a section) always shows the window.
        .defaultLaunchBehavior(
            (UserDefaults.standard.string(forKey: "e68.startIn") != nil || !MenuBarSettings.shouldKeepAliveInMenuBar)
            ? .presented
            : .automatic
        )
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            GlassSettingsView(onEnsureMainWindow: {
                delegate.reopenMainWindow()
            })
        }

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarView(onOpenMainWindow: {
                delegate.reopenMainWindow()
            })
            .environmentObject(delegate.store)
            .studioAppearance()
            .onAppear {
                wireDelegate()
                delegate.store.start()
            }
        } label: {
            Image(nsImage: E68Logo.statusBarImage)
                .renderingMode(.original)
                .accessibilityLabel("E68 Studio")
        }
        .menuBarExtraStyle(.window)
    }

    private func wireDelegate() {
        delegate.openMainWindowAction = { openWindow(id: "main") }
    }
}
