import SwiftUI

// MARK: - Fields, cards, headers

extension View {
    /// Text field on a glass capsule, sized to match regular buttons.
    func glassField(width: CGFloat? = nil) -> some View {
        self
            .textFieldStyle(.plain)
            .font(.studioBody)
            .padding(.horizontal, 12)
            .frame(width: width)
            .frame(height: Hit.small)
            .glassSurface(interactive: true)
    }

    /// Recessed group inside a glass panel. Uses a tint, not more glass.
    func insetCard(padding: CGFloat = Space.m) -> some View {
        let shape = RoundedRectangle(cornerRadius: Corner.control, style: .continuous)
        return self
            .padding(padding)
            .nestedSurface(shape, role: .card)
    }
}

/// Heading with an optional trailing value, used above every slider and group.
struct FieldHeader: View {
    let title: String
    var value: String? = nil
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.studioHeading)
            Spacer(minLength: Space.s)
            if let value {
                Text(value)
                    .font(.studioDetail.monospacedDigit())
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .opacity(isEnabled ? 1 : Dim.disabled)
        .accessibilityElement(children: .combine)
    }
}

/// Centered placeholder for empty or waiting states.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(tint)
                .padding(.bottom, 2)
            Text(title)
                .font(.studioHeading)
            if let message {
                Text(message)
                    .font(.studioDetail)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }
}

/// Capsule meter in the same style as slider tracks.
struct CapacityBar: View {
    let fraction: Double
    var warning = false

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(warning ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Color.accentColor.gradient))
                    .frame(width: clamped <= 0 ? 0 : max(6, geo.size.width * clamped))
            }
        }
        .frame(height: 6)
        .animation(.smooth(duration: 0.25), value: fraction)
    }
}

// MARK: - Grouped rows

/// A titled group of rows on an inset card, the glass-panel version of a grouped Form section.
struct GroupedSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .font(.studioHeading)
                .padding(.leading, Space.xs)
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                        if index > 0 {
                            Divider().opacity(0.6)
                        }
                        subview
                    }
                }
            }
            .padding(.horizontal, Space.m)
            .nestedSurface(RoundedRectangle(cornerRadius: Corner.control, style: .continuous), role: .card)
            if let footer {
                Text(footer)
                    .font(.studioDetail)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xs)
            }
        }
    }
}

/// One row in a `GroupedSection`: label (and optional detail) on the left, value or control on the right.
struct GroupedRow<Trailing: View>: View {
    let label: String
    var detail: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.studioBody)
                if let detail {
                    Text(detail)
                        .font(.studioMeta)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: Space.m)
            trailing
        }
        .frame(minHeight: Hit.row)
        .padding(.vertical, 4)
    }
}

extension GroupedRow where Trailing == GroupedValue {
    init(_ label: String, value: String) {
        self.label = label
        self.trailing = GroupedValue(text: value)
    }
}

struct GroupedValue: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.studioBody)
            .foregroundStyle(Ink.secondary)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Scrolling body for a tab inside a glass panel.
struct PanelScroll<Content: View>: View {
    var maxWidth: CGFloat = 640
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                content
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .frame(maxWidth: .infinity)
        }
        .glassScrollbars(top: 8, bottom: 16, trailing: 6)
    }
}

/// Round icon-only button (delete, steppers, lamp toggles). Always at least `Hit.compact` square,
/// so it stays easy to hit with a finger even when the glyph is small.
struct IconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = Hit.small
    var tint: Color? = nil
    var selected = false
    var repeats = false
    let action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint ?? (selected || hovering ? Color.primary : Ink.secondary))
                .frame(width: size, height: size)
                .chip(Circle(), selected: selected, hovering: hovering)
        }
        .buttonStyle(PressScaleButtonStyle())
        .buttonRepeatBehavior(repeats ? .enabled : .disabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Button drawn as a chip, with its own hover state: category filters, knob actions, keycode tiles.
struct ChipButton<Label: View, S: InsettableShape>: View {
    let shape: S
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var label: Label
    @ViewState private var hovering = false

    init(shape: S, selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.shape = shape
        self.selected = selected
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(selected || hovering ? Color.primary : Ink.secondary)
                .chip(shape, selected: selected, hovering: hovering)
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension ChipButton where S == Capsule {
    init(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.init(shape: Capsule(), selected: selected, action: action, label: label)
    }
}

/// Search field on a recessed capsule, matching `glassField` height.
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.studioMeta.weight(.medium))
                .foregroundStyle(Ink.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.studioDetail)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.studioDetail)
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, text.isEmpty ? 12 : 4)
        .frame(height: Hit.small)
        .glassSurface(interactive: true)
    }
}
