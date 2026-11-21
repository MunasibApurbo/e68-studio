import AppKit
import SwiftUI

/// Small floating badge shown when the DPI stage changes, like the LED flash on gaming mice.
@MainActor
final class StageHUD {
    static let shared = StageHUD()

    private final class Model: ObservableObject {
        @Published var dpi = 1600
        @Published var label = ""
        @Published var color: NSColor = .systemBlue
    }

    private let model = Model()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var showGeneration = 0

    func show(dpi: Int, label: String, color: NSColor) {
        model.dpi = dpi
        model.label = label
        model.color = color
        let panel = panel ?? makePanel()
        self.panel = panel

        showGeneration += 1
        let gen = showGeneration

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 74))
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel, self.showGeneration == gen else { return }
            NSAnimationContext.runAnimationGroup({
                $0.duration = 0.3
                panel.animator().alphaValue = 0
            }) { [weak self, weak panel] in
                Task { @MainActor in
                    guard let self, let panel, self.showGeneration == gen else { return }
                    panel.orderOut(nil)
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }

    private struct HUDView: View {
        @ObservedObject var model: Model

        var body: some View {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(nsColor: model.color).gradient)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 0.75))
                    .frame(width: 14, height: 14)
                    .shadow(color: Color(nsColor: model.color).opacity(0.75), radius: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "\(model.dpi) DPI")
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(model.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .frame(minWidth: 210, maxWidth: 340)
            .frame(height: 64)
            .fixedSize(horizontal: true, vertical: false)
            .glassSurface(Capsule(), elevation: .medium, scrim: true)
            .frame(width: 380, height: 96)
            .studioAppearance()
            .animation(.snappy(duration: 0.2), value: model.dpi)
        }
    }
}
