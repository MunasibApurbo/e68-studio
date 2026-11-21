import SwiftUI
import AppKit

private enum ControlMetrics {
    static let knob: CGFloat = 22
    static let track: CGFloat = 6
    /// Touch-friendly hit band around the track.
    static let height: CGFloat = 30
}

/// White pill knob shared by every slider and the switch.
struct ControlKnob: View {
    var size: CGFloat = ControlMetrics.knob
    var active = false
    /// Optional colour shown inside the knob (colour pickers).
    var swatch: Color? = nil

    var body: some View {
        Circle()
            .fill(.white)
            .overlay {
                if let swatch {
                    Circle().fill(swatch).padding(4)
                        .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5).padding(4))
                }
            }
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(active ? 0.28 : 0.2), radius: active ? 4 : 2, y: 1)
            .frame(width: size, height: size)
            .scaleEffect(active ? 1.12 : 1)
    }
}

/// Discrete slider: accent-filled track with a notch per step, snapping knob,
/// drag, click-to-jump, arrow keys and VoiceOver.
struct StepSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: String
    var accessibilityValueText: String? = nil

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme
    @ViewState private var dragging = false
    @FocusState private var focused: Bool

    private var steps: Int { max(range.upperBound - range.lowerBound, 1) }
    private var fraction: CGFloat {
        min(max(CGFloat(value - range.lowerBound) / CGFloat(steps), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let knob = ControlMetrics.knob
            let travel = max(geo.size.width - knob, 1)
            let knobX = fraction * travel

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.primary.opacity(scheme == .dark ? 0.18 : 0.12))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .frame(height: ControlMetrics.track)

                // Filled part
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: knobX + knob / 2, height: ControlMetrics.track)

                // Notches, centred on the track
                if steps <= 12 {
                    ForEach(0...steps, id: \.self) { i in
                        let x = knob / 2 + CGFloat(i) / CGFloat(steps) * travel
                        Circle()
                            .fill(CGFloat(i) <= fraction * CGFloat(steps) ? Color.white.opacity(0.85) : Color.primary.opacity(0.3))
                            .frame(width: 3, height: 3)
                            .position(x: x, y: geo.size.height / 2)
                    }
                }

                ControlKnob(active: dragging)
                    .offset(x: knobX)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard isEnabled else { return }
                        dragging = true
                        set(range.lowerBound + Int(((g.location.x - knob / 2) / travel * CGFloat(steps)).rounded()))
                    }
                    .onEnded { _ in dragging = false }
            )
            .animation(.snappy(duration: 0.18), value: value)
            .animation(.snappy(duration: 0.15), value: dragging)
        }
        .frame(height: ControlMetrics.height)
        .opacity(isEnabled ? 1 : Dim.disabled)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .overlay {
            if focused && isEnabled {
                Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2).padding(-3)
            }
        }
        .onKeyPress(.leftArrow) { set(value - 1); return .handled }
        .onKeyPress(.rightArrow) { set(value + 1); return .handled }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValueText ?? "\(value) of \(range.upperBound)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + 1)
            case .decrement: set(value - 1)
            @unknown default: break
            }
        }
    }

    private func set(_ new: Int) {
        guard isEnabled else { return }
        let clamped = min(max(new, range.lowerBound), range.upperBound)
        guard clamped != value else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        value = clamped
    }
}

/// Switch filled with the Mac's accent color when on, so its state reads over glass.
/// The whole row (label and switch) is the tap target, which matters on a touch screen.
struct AccentSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        AccentSwitch(configuration: configuration)
    }
}

private struct AccentSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.labelsVisibility) private var labelsVisibility

    var body: some View {
        let on = configuration.isOn
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                configuration.isOn.toggle()
            }
        } label: {
            configuration.label
        }
        .buttonStyle(SwitchButtonStyle(on: on, showsLabel: labelsVisibility != .hidden))
        .opacity(isEnabled ? 1 : Dim.disabled)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
        }
    }
}

/// Draws the label and track; reads the press state straight from the button so a tap is
/// never swallowed by a competing gesture.
private struct SwitchButtonStyle: ButtonStyle {
    let on: Bool
    let showsLabel: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            if showsLabel {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: Space.m)
            }
            SwitchTrack(on: on, pressed: configuration.isPressed)
        }
        .frame(minHeight: Hit.small)
        .contentShape(Rectangle())
    }
}

private struct SwitchTrack: View {
    let on: Bool
    let pressed: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule()
                .fill(on ? AnyShapeStyle(Color.accentColor.gradient)
                         : AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.22 : 0.14)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.1), lineWidth: 0.5))
            Capsule()
                .fill(.white)
                .overlay(Capsule().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .frame(width: pressed ? 28 : 22, height: 22)
                .padding(2)
        }
        .frame(width: 46, height: 26)
        .animation(.snappy(duration: 0.15), value: pressed)
    }
}
