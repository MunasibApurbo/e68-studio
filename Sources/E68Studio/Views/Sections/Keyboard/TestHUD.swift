import SwiftUI

/// Key test & live typing telemetry HUD: shows tested switches, rolling WPM, total presses, and 3D thermal heatmap toggle.
struct TestHUD: View {
    @EnvironmentObject private var store: KeyboardStore

    var body: some View {
        let total = Layout.all.count
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.tested.count)")
                        .font(.studioTitle.monospacedDigit())
                        .contentTransition(.numericText())
                    Text(store.pressed.isEmpty ? "/ \(total) tested" : "/ \(total) · \(store.pressed.count) held")
                        .font(.studioDetail.monospacedDigit())
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                CapacityBar(fraction: Double(store.tested.count) / Double(max(total, 1)))
            }
            .frame(width: 190, alignment: .leading)

            Divider().frame(height: 32)

            metric("\(store.currentWPM)", "WPM")
            metric("\(store.totalKeystrokes)", "Keys")

            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    store.showHeatmap.toggle()
                }
            } label: {
                Label("Heatmap", systemImage: store.showHeatmap ? "flame.fill" : "flame")
            }
            .buttonStyle(.glassCapsule(store.showHeatmap ? .prominent : .standard, size: .small))
            .fixedSize()

            Button("Reset") {
                store.tested = []
                store.resetTelemetry()
            }
            .buttonStyle(.glassCapsule(size: .small))
            .fixedSize()
            .disabled(store.tested.isEmpty && store.totalKeystrokes == 0)
        }
        .animation(.snappy(duration: 0.2), value: store.tested.count)
        .environment(\.insideGlassPanel, true)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s + 2)
        .fixedSize()
        .hudSurface()
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.studioHeading.monospacedDigit())
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: value)
            Text(label)
                .font(.studioMeta)
                .foregroundStyle(Ink.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .frame(minWidth: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
