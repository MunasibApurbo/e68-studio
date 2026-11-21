import AppKit
import SwiftUI

// MARK: - Test

/// Mouse test bar. The 3D mouse lights its buttons as you press them, so like Key Test this is
/// the score, the report rate and a reset.
struct MouseTestHUD: View {
    @ObservedObject private var remapper = MouseRemapper.shared
    @ObservedObject private var test = MouseRemapper.shared.test
    @ViewState private var isVisible = false
    @ViewState private var isMiniaturized = false

    private static let buttons: [(Int, String)] = [(0, "Left"), (1, "Right"), (2, "Wheel"), (3, "Back"), (4, "Forward")]

    var body: some View {
        VStack(spacing: Space.s) {
            if !remapper.trusted {
                AccessBanner(floating: true)
            }
            ViewThatFits(in: .horizontal) {
                wideBar
                compactBar
            }
            .animation(.snappy(duration: 0.2), value: tested)
            .environment(\.insideGlassPanel, true)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s + 2)
            .hudSurface()
        }
        .background(
            HostWindowObserver(
                onMiniaturizeChange: { miniaturized in
                    isMiniaturized = miniaturized
                    if miniaturized {
                        remapper.testing = false
                    } else if isVisible {
                        remapper.testing = true
                    }
                },
                onClose: {
                    remapper.testing = false
                }
            )
            .allowsHitTesting(false)
        )
        .onAppear {
            isVisible = true
            remapper.testing = !isMiniaturized
        }
        .onDisappear {
            isVisible = false
            remapper.testing = false
        }
    }

    private var wideBar: some View {
        HStack(spacing: Space.m) {
            chipsBlock
            Divider().frame(height: 32)
            metricsRow
            resetButton
        }
    }

    private var compactBar: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                chipsBlock
                Spacer(minLength: Space.s)
                resetButton
            }
            Divider()
            metricsRow
        }
    }

    private var chipsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(tested)")
                    .font(.studioTitle.monospacedDigit())
                    .contentTransition(.numericText())
                Text("/ 5 buttons")
                    .font(.studioDetail)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            .fixedSize()
            HStack(spacing: 4) {
                ForEach(Self.buttons, id: \.0) { n, name in
                    chip(name, n)
                }
            }
        }
        .fixedSize()
    }

    private var metricsRow: some View {
        HStack(spacing: Space.m) {
            metric(test.reportRate > 0 ? "\(test.reportRate) Hz" : "–", "Polling", minWidth: 68)
            metric(test.peakRate > 0 ? "\(test.peakRate) Hz" : "–", "Peak", minWidth: 64)
            metric("\(test.wheelUp) ↑  \(test.wheelDown) ↓", "Wheel", minWidth: 80)
            metric(test.lastDoubleClickMS.map { "\($0) ms" } ?? "–", "Click gap", minWidth: 64)
            metric("\(test.chatterCount)", "Chatter", minWidth: 52)
        }
    }

    private var hasStats: Bool {
        tested > 0 || test.wheelUp > 0 || test.wheelDown > 0 || test.reportRate > 0 || test.peakRate > 0 || test.lastDoubleClickMS != nil || test.chatterCount > 0
    }

    private var resetButton: some View {
        Button("Reset") { remapper.resetTest() }
            .buttonStyle(.glassCapsule(size: .small))
            .fixedSize()
            .disabled(!hasStats)
    }

    private var tested: Int { Self.buttons.filter { (test.counts[$0.0] ?? 0) > 0 }.count }

    private func chip(_ name: String, _ n: Int) -> some View {
        let held = test.pressed.contains(n)
        let done = (test.counts[n] ?? 0) > 0
        return Text(name)
            .font(.studioMeta.weight(.medium))
            .foregroundStyle(held ? Color.white : done ? Color.primary : Ink.secondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background {
                if held {
                    Capsule().fill(Color.accentColor)
                } else {
                    Color.clear.nestedSurface(Capsule(), role: done ? .control : .track, hovering: done)
                }
            }
            .overlay(alignment: .topTrailing) {
                if done && !held {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .offset(x: 3, y: -3)
                }
            }
            .animation(.snappy(duration: 0.08), value: held)
            .accessibilityValue(held ? "Held" : done ? "Tested" : "Not tested")
    }

    private func metric(_ value: String, _ label: String, minWidth: CGFloat = 64) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.studioHeading.monospacedDigit())
                .transaction { $0.animation = nil }
            Text(label)
                .font(.studioMeta)
                .foregroundStyle(Ink.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .frame(minWidth: minWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct HostWindowObserver: NSViewRepresentable {
    var onMiniaturizeChange: (Bool) -> Void
    var onClose: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onMiniaturizeChange = onMiniaturizeChange
        view.onClose = onClose
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onMiniaturizeChange = onMiniaturizeChange
        nsView.onClose = onClose
    }

    static func dismantleNSView(_ nsView: ObserverView, coordinator: ()) {
        nsView.removeObservers()
    }

    final class ObserverView: NSView {
        var onMiniaturizeChange: ((Bool) -> Void)?
        var onClose: (() -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else { return }
            if window.isMiniaturized {
                onMiniaturizeChange?(true)
            }
            let nc = NotificationCenter.default
            observers = [
                nc.addObserver(forName: NSWindow.willMiniaturizeNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onMiniaturizeChange?(true) }
                },
                nc.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onMiniaturizeChange?(false) }
                },
                nc.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onClose?() }
                },
            ]
        }

        func removeObservers() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
        }
    }
}
