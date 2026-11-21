import SwiftUI

/// The whole app is one 3D scene with glass controls floating over it:
/// the desk overview first, then the studio close-up for configuring.
struct ContentView: View {
    @EnvironmentObject private var store: KeyboardStore
    @ViewState private var deskPreset: DeskCameraPreset = .front
    private static var didOpenStartupStudio = false

    var body: some View {
        ZStack {
            SceneView(store: store, deskPreset: deskPreset)
                .ignoresSafeArea()

            Group {
                if store.inMouseStudio {
                    MouseChrome()
                        .transition(.opacity)
                } else if store.inStudio {
                    StudioChrome()
                        .transition(.opacity)
                } else {
                    DeskChrome(deskPreset: $deskPreset)
                        .transition(.opacity)
                }

                if let toast = store.toast {
                    ToastView(toast: toast)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 56)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let busy = store.busy {
                    ZStack {
                        Color.black.opacity(0.06)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(busy).font(.studioBody.weight(.medium))
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .glassSurface(elevation: .medium, scrim: true)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.4), value: store.inStudio)
            .animation(.smooth(duration: 0.4), value: store.studioDevice)
            .animation(Motion.select, value: store.section)
            .animation(Motion.select, value: store.mouseSection)
            .animation(.snappy(duration: 0.22), value: store.toast)
            .animation(.snappy(duration: 0.18), value: store.busy)
        }
        .onExitCommand {
            if store.selection != nil { store.selection = nil } else if store.inStudio { store.leaveStudio() }
        }
        .buttonBorderShape(.capsule)
        .background(MainWindowChrome().allowsHitTesting(false))
        .ignoresSafeArea()
        .onAppear {
            store.start()
            openStartupStudio()
            LiveMirror.shared.setWindowVisible(true)
            if store.isReady {
                store.setKeyTestActive(true)
                store.setLightingWatch(true)
            }
        }
        .onDisappear {
            LiveMirror.shared.setWindowVisible(false)
            store.setKeyTestActive(false)
            store.setLightingWatch(false)
        }
    }
}

extension View {
    /// Top row placement: clear of the traffic lights, vertically centred on them.
    func topChromeInsets() -> some View {
        padding(.leading, 92)
            .padding(.trailing, Space.edge)
            .padding(.top, 26 - Hit.bar / 2)
    }
}

extension ContentView {
    /// `-e68.startIn mouse.buttons` (or `keyboard.light`) on the command line opens straight into
    /// a studio section; handy for screenshots and for jumping back to where you were working.
    fileprivate func openStartupStudio() {
        guard !Self.didOpenStartupStudio else { return }
        Self.didOpenStartupStudio = true
        guard let target = UserDefaults.standard.string(forKey: "e68.startIn") else { return }
        let parts = target.split(separator: ".").map(String.init)
        if parts.first == "mouse" {
            store.enterMouseStudio()
            if let raw = parts.dropFirst().first, let section = MouseSection(rawValue: raw) { store.mouseSection = section }
        } else if parts.first == "keyboard" {
            store.enterStudio()
            if let raw = parts.dropFirst().first, let section = StudioSection(rawValue: raw) { store.section = section }
        }
    }
}

/// Configures the main window's unified transparent toolbar so macOS places the
/// traffic light buttons at their standard concentric inset (centered at y = 26 pt)
/// rather than cramped into the 32 pt hidden-titlebar corner.
private struct MainWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ nsView: ChromeView, context: Context) {}

    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("e68-main-window")
            window.styleMask.insert([.resizable, .fullSizeContentView])
            window.minSize = NSSize(width: 780, height: 540)
            if window.toolbar == nil {
                let toolbar = NSToolbar(identifier: "main")
                toolbar.allowsUserCustomization = false
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
        }
    }
}

// MARK: - Toast

private struct ToastView: View {
    let toast: KeyboardStore.Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.body)
            Text(toast.text)
                .font(.studioBody.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .hudSurface()
        .frame(maxWidth: 480)
    }
}
