import SwiftUI
import AppKit

// MARK: - Tokens

/// One corner language for every surface: panels, controls, and what sits inside controls.
enum Corner {
    static let panel: CGFloat = 22
    static let control: CGFloat = 14
    static let inner: CGFloat = 10
}

/// Spacing scale shared by every panel so gaps line up across sections.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    /// Inner padding of floating panels.
    static let panel: CGFloat = 14
    /// Gap between the window edge and floating chrome.
    static let edge: CGFloat = 20
    /// Horizontal inset of selectable rows (macro slots, DPI stages, mouse buttons).
    static let row: CGFloat = 10
}

/// Control heights. The Mac is now touch-capable, so nothing tappable goes below 28 pt and
/// rows that hold controls are at least 40 pt tall. Every control in a row shares one height.
enum Hit {
    /// Chips and segments inside a bar (the bar itself is `bar` tall).
    static let compact: CGFloat = 28
    /// Small buttons, text fields, keycode tiles.
    static let small: CGFloat = 30
    /// Regular buttons and everything in the top bar.
    static let regular: CGFloat = 34
    /// Height of every floating pill in the top bar.
    static let bar: CGFloat = 34
    /// Minimum height of a list or grouped row.
    static let row: CGFloat = 40
}

/// Text colours over glass. The system `.secondary` is too faint on a busy 3D scene,
/// so secondary text everywhere uses this slightly stronger tone.
enum Ink {
    static let secondary = Color.primary.opacity(0.72)
}

/// Motion shared by everything that moves a selection (dock, segmented controls).
enum Motion {
    /// Selection pill sliding to a new item: quick, settles without visible bounce.
    static let select = Animation.spring(duration: 0.32, bounce: 0.1)
    /// Content swapping when the section changes.
    static let swap = Animation.smooth(duration: 0.26)
}

extension View {
    /// Marks this item as a place the sliding selection pill can sit (see `slidingSelection`).
    func selectionAnchor<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        matchedGeometryEffect(id: id, in: namespace, isSource: true)
    }

    /// Draws one selection pill behind a row and moves it to the item tagged `selection`.
    /// A single pill slides cleanly; a pill per item cross-fades and shows two pills mid-move.
    func slidingSelection<ID: Hashable>(_ selection: ID, in namespace: Namespace.ID) -> some View {
        background {
            GlassSelectionIndicator(shape: Capsule())
                .matchedGeometryEffect(id: selection, in: namespace, isSource: false)
                .allowsHitTesting(false)
        }
    }
}

/// Type scale. Nothing over glass goes below 11 pt so text stays readable on a busy scene.
extension Font {
    /// Panel and editor titles.
    static let studioTitle = Font.title3.weight(.semibold)
    /// Section and field headings ("Brightness", "Backup").
    static let studioHeading = Font.headline
    /// Row labels and list items.
    static let studioBody = Font.body
    /// Descriptions and secondary values.
    static let studioDetail = Font.callout
    /// The smallest text allowed: summaries and metadata.
    static let studioMeta = Font.subheadline
}

// MARK: - Buttons

/// Capsule glass button used for every action in the app, so all buttons share one shape,
/// height, and press feel. `.prominent` marks the single primary action of a group.
struct GlassButtonStyle: ButtonStyle {
    enum Prominence { case standard, prominent, destructive }
    enum Size { case small, regular, large }

    var prominence: Prominence = .standard
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, prominence: prominence, size: size)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glassCapsule: GlassButtonStyle { GlassButtonStyle() }
    static func glassCapsule(
        _ prominence: GlassButtonStyle.Prominence = .standard,
        size: GlassButtonStyle.Size = .regular
    ) -> GlassButtonStyle {
        GlassButtonStyle(prominence: prominence, size: size)
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominence: GlassButtonStyle.Prominence
    let size: GlassButtonStyle.Size
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.insideGlassPanel) private var insidePanel

    private var effectiveProminence: GlassButtonStyle.Prominence {
        if prominence == .standard && configuration.role == .destructive {
            return .destructive
        }
        return prominence
    }

    private var font: Font {
        switch size {
        case .small: return .callout.weight(.medium)
        case .regular: return .body.weight(effectiveProminence == .prominent ? .semibold : .medium)
        case .large: return .title3.weight(.semibold)
        }
    }

    private var metrics: (h: CGFloat, height: CGFloat) {
        switch size {
        case .small: return (12, Hit.small)
        case .regular: return (16, Hit.regular)
        case .large: return (24, 46)
        }
    }

    var body: some View {
        configuration.label
            .font(font)
            .lineLimit(1)
            .foregroundStyle(effectiveProminence == .destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
            .padding(.horizontal, metrics.h)
            .frame(minHeight: metrics.height)
            .opacity(isEnabled ? 1 : Dim.disabled)
            .glassSurface(
                interactive: isEnabled,
                elevation: insidePanel ? .none : .low,
                scrim: !insidePanel,
                prominent: effectiveProminence == .prominent && isEnabled
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.14, extraBounce: 0), value: configuration.isPressed)
    }
}

/// Press-only feedback for custom tappable content (dock items, segments).
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.snappy(duration: 0.14, extraBounce: 0), value: configuration.isPressed)
    }
}

// MARK: - Segmented control

/// The one segmented control: tabs, camera presets, and mode pickers.
/// `.floating` sits on the 3D scene as its own glass pill; `.inset` sits inside a glass panel
/// on a recessed track, so glass is never stacked on glass.
struct GlassSegmented<Value: Hashable>: View {
    enum Placement { case floating, inset }
    enum Size { case small, regular }

    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var placement: Placement = .inset
    var size: Size = .regular
    /// Stretch segments to equal widths across the available space.
    var fill = false
    /// Segments that get a small accent dot (for example, layers with changed keys).
    var marked: Set<Value> = []

    @Namespace private var namespace

    var body: some View {
        let hPad: CGFloat = size == .small ? (fill ? 6 : 12) : (fill ? 8 : 16)
        let track = HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                segment(option.value, option.title, horizontalPadding: hPad)
            }
        }
        .slidingSelection(selection, in: namespace)
        .environment(\.insideGlassPanel, true)
        .padding(3)

        switch placement {
        case .floating:
            track
                .glassSurface(elevation: .low, scrim: true)
                .environment(\.insideGlassPanel, false)
        case .inset:
            track
                .nestedSurface(Capsule(), role: .track)
        }
    }

    private func segment(_ value: Value, _ title: String, horizontalPadding: CGFloat) -> some View {
        let selected = selection == value
        return Button {
            guard selection != value else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            withAnimation(Motion.select) { selection = value }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(size == .small ? .callout.weight(.medium) : .body.weight(.medium))
                    .foregroundStyle(selected ? Color.primary : Ink.secondary)
                    .animation(Motion.select, value: selected)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if marked.contains(value) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .accessibilityLabel("Changed")
                }
            }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: fill ? .infinity : nil)
                .frame(height: size == .small ? Hit.compact : 32)
                .selectionAnchor(value, in: namespace)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
