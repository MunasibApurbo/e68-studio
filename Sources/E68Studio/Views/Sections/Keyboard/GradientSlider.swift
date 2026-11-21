import SwiftUI
import AppKit

/// A slider whose track is a gradient, for hue and saturation.
struct GradientSlider: View {
    @Binding var value: Double
    let colors: [Color]
    var knobColor: Color? = nil

    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var dragging = false
    @FocusState private var focused: Bool

    private let knob: CGFloat = 22
    private let height: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - knob, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                    .frame(height: 10)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
                ControlKnob(size: knob, active: dragging, swatch: knobColor)
                    .offset(x: min(max(value, 0), 1) * travel)
            }
            .frame(height: height)
            .animation(.snappy(duration: 0.15), value: dragging)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard isEnabled else { return }
                        dragging = true
                        set((g.location.x - knob / 2) / travel)
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: height)
        .opacity(isEnabled ? 1 : Dim.disabled)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .overlay {
            if focused && isEnabled {
                Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2).padding(-3)
            }
        }
        .onKeyPress(.leftArrow) { step(-0.05); return .handled }
        .onKeyPress(.rightArrow) { step(0.05); return .handled }
        .accessibilityElement()
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(0.05)
            case .decrement: step(-0.05)
            @unknown default: break
            }
        }
    }

    private func set(_ new: Double) {
        guard isEnabled else { return }
        value = min(max(new, 0), 1)
    }

    private func step(_ delta: Double) {
        guard isEnabled else { return }
        let next = min(max(value + delta, 0), 1)
        guard abs(next - value) > 0.0001 else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        value = next
    }
}
