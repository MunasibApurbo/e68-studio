import SwiftUI
import AppKit

// MARK: - Glass Environment & Nesting Guard

private struct InsideGlassPanelKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside floating glass panels, trays, and popovers so nested controls render clean
    /// translucent tints rather than stacking a second `.glassEffect` pass on top of glass.
    var insideGlassPanel: Bool {
        get { self[InsideGlassPanelKey.self] }
        set { self[InsideGlassPanelKey.self] = newValue }
    }
}

// MARK: - Resolved Style

/// Everything a glass surface needs, resolved from the user's choice and the Mac's settings.
struct GlassResolver {
    let preference: GlassPreference
    let scheme: ColorScheme
    let reduceTransparency: Bool
    let highContrast: Bool

    /// Automatic draws plain system Liquid Glass with nothing layered on top, exactly like
    /// macOS's own windows, so it follows System Settings › Appearance › Liquid Glass
    /// (Clear ↔ Tinted) and every accessibility setting by itself.
    var isSystem: Bool { preference == .automatic && !reduceTransparency }

    /// How much tint and readability wash the app's own styles add: 0 (Clear) to 1 (Frosted).
    private var density: Double { preference == .frosted ? 1 : 0 }

    private func mix(_ clear: Double, _ frosted: Double) -> Double {
        clear + (frosted - clear) * density
    }

    var isSolid: Bool { preference == .solid || reduceTransparency }
    var isDark: Bool { scheme == .dark }

    func glass(interactive: Bool, tint: Color? = nil) -> Glass {
        if isSystem {
            let g = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            return interactive ? g.interactive() : g
        }
        let baseTint = (isDark ? Color(white: 0.06) : Color.white)
            .opacity(isDark ? mix(0.16, 0.38) : mix(0.12, 0.34))
        let g: Glass = (preference == .clear ? Glass.clear : Glass.regular).tint(tint ?? baseTint)
        return interactive ? g.interactive() : g
    }

    var prominentGlassTint: Color {
        Color.accentColor.opacity(isDark ? 0.34 : 0.22)
    }

    /// Hairline rim that reads in both light and dark.
    var rim: LinearGradient {
        // System glass draws its own edge highlight; only add one when contrast is increased.
        if isSystem && !highContrast {
            return LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
        }
        let top = highContrast ? 0.92 : (isDark ? 0.36 : 0.74)
        let bottom = highContrast ? 0.64 : (isDark ? 0.11 : 0.24)
        return LinearGradient(colors: [.white.opacity(top), .white.opacity(bottom)], startPoint: .top, endPoint: .bottom)
    }

    var rimWidth: CGFloat { highContrast ? 1.25 : 0.8 }

    var solidFill: Color {
        Color(nsColor: isDark ? .underPageBackgroundColor : .windowBackgroundColor)
    }

    var solidStroke: Color { Color(nsColor: highContrast ? .labelColor : .separatorColor) }

    /// Wash laid between the glass and text so pills, HUDs, and panels remain readable over
    /// both dark walls (#454545 in Light) and bright desk mats (#E8E4DC in Dark).
    var scrim: Color {
        // System glass picks up the scene behind it, so in Dark mode a panel over the white
        // desk mat would turn light grey under white text. A light wash keeps text readable
        // while the glass itself stays exactly what macOS draws.
        if isSystem {
            let boost = highContrast ? 0.18 : 0
            return isDark ? Color.black.opacity(0.28 + boost) : Color.white.opacity(0.22 + boost)
        }
        let boost = highContrast ? 0.18 : 0
        return isDark
            ? Color.black.opacity(mix(0.40, 0.60) + boost)
            : Color.white.opacity(mix(0.34, 0.56) + boost)
    }

    /// Elevated luminous selection pill + accent wash, designed to stay legible even under Graphite accent.
    func selectionTokens(prominent: Bool = false) -> (base: Color, accent: Color, border: LinearGradient, borderWidth: CGFloat, shadowOpacity: Double) {
        let bw: CGFloat = highContrast ? 1.25 : 0.9
        if isDark {
            return (
                // Additive white, so a selected pill is always lighter than idle chips beside it,
                // even with the Graphite accent where the accent tint is grey.
                base: Color.white.opacity(isSolid ? 0.26 : 0.22),
                accent: Color.accentColor.opacity(prominent ? 0.36 : 0.28),
                border: LinearGradient(
                    colors: [Color.white.opacity(highContrast ? 0.75 : 0.46), Color.accentColor.opacity(highContrast ? 0.88 : 0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                borderWidth: bw,
                shadowOpacity: 0.24
            )
        }
        return (
            base: Color.white.opacity(isSolid ? 0.92 : 0.84),
            accent: Color.accentColor.opacity(prominent ? 0.22 : 0.16),
            border: LinearGradient(
                colors: [Color.white.opacity(0.92), Color.accentColor.opacity(highContrast ? 0.88 : 0.48)],
                startPoint: .top,
                endPoint: .bottom
            ),
            borderWidth: bw,
            shadowOpacity: 0.12
        )
    }

    /// Flat fill for something that sits inside a glass panel. Glass is never stacked on glass,
    /// so cards, tracks, and idle controls inside a panel are tints of the label colour.
    func fill(_ role: NestedRole, hovering: Bool = false) -> Color {
        let boost = highContrast ? 0.04 : 0
        let base: Double
        switch role {
        case .card: base = isDark ? 0.06 : 0.045
        case .track: base = isDark ? 0.08 : 0.06
        case .control: base = hovering ? (isDark ? 0.15 : 0.11) : (isDark ? 0.10 : 0.07)
        }
        return Color.primary.opacity(base + boost)
    }

    var nestedStroke: Color {
        Color.primary.opacity(highContrast ? 0.45 : (isDark ? 0.12 : 0.09))
    }
}

/// What a nested (non-glass) surface is for; decides how strong its tint is.
enum NestedRole {
    /// A group of rows or controls.
    case card
    /// A recessed track: segmented controls, search fields.
    case track
    /// An idle button, chip, or field.
    case control
}

/// Opacity used for anything disabled. Controls apply it to themselves, so containers
/// only need `.disabled(_:)` and nothing gets dimmed twice.
enum Dim {
    static let disabled: Double = 0.45
}

struct GlassEnvironment: DynamicProperty {
    @AppStorage(GlassKeys.style) var preference: GlassPreference = .automatic
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast

    var resolver: GlassResolver {
        GlassResolver(
            preference: preference,
            scheme: scheme,
            reduceTransparency: reduceTransparency,
            highContrast: contrast == .increased
        )
    }
}

// MARK: - Modifiers & Containers

enum GlassElevation {
    case none, low, medium, high

    var shadow: (opacity: Double, radius: CGFloat, y: CGFloat) {
        switch self {
        case .none: return (0, 0, 0)
        case .low: return (0.12, 6, 3)
        case .medium: return (0.18, 10, 5)
        case .high: return (0.24, 22, 11)
        }
    }
}

/// Groups sibling floating glass pills/bars into a shared Liquid Glass container on macOS 26.
struct GlassContainer<Content: View>: View {
    var spacing: CGFloat = Space.s
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

private struct SelectionFillLayers<S: InsettableShape>: View {
    let shape: S
    let tokens: (base: Color, accent: Color, border: LinearGradient, borderWidth: CGFloat, shadowOpacity: Double)
    var includeStroke = true

    var body: some View {
        ZStack {
            shape.fill(tokens.base)
            shape.fill(tokens.accent)
        }
        .overlay {
            if includeStroke {
                shape.strokeBorder(tokens.border, lineWidth: tokens.borderWidth).allowsHitTesting(false)
            }
        }
    }
}

/// A floating glass surface: panels, pills, HUDs, or controls when `interactive`.
/// Automatically degrades to a non-glass tinted surface when nested inside `.insideGlassPanel`.
private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let elevation: GlassElevation
    var scrim = false
    var prominent = false
    @Environment(\.insideGlassPanel) private var insidePanel
    private let env = GlassEnvironment()

    func body(content: Content) -> some View {
        let r = env.resolver
        let s = elevation.shadow
        Group {
            if insidePanel || r.isSolid {
                if prominent {
                    content
                        .background(GlassSelectionIndicator(shape: shape, prominent: true))
                } else {
                    // Inside a panel: a flat tint, never more glass. Solid mode outside a panel: opaque.
                    content
                        .background(shape.fill(insidePanel ? r.fill(interactive ? .control : .card) : r.solidFill))
                        .overlay(shape.strokeBorder(insidePanel ? r.nestedStroke : r.solidStroke, lineWidth: r.rimWidth).allowsHitTesting(false))
                }
            } else if prominent {
                let t = r.selectionTokens(prominent: true)
                content
                    .background(SelectionFillLayers(shape: shape, tokens: t, includeStroke: false))
                    .glassEffect(r.glass(interactive: interactive, tint: r.prominentGlassTint), in: shape)
                    .overlay(shape.strokeBorder(t.border, lineWidth: t.borderWidth).allowsHitTesting(false))
            } else {
                content
                    .background {
                        if scrim {
                            shape.fill(r.scrim)
                        }
                    }
                    .glassEffect(r.glass(interactive: interactive), in: shape)
                    .overlay(shape.strokeBorder(r.rim, lineWidth: r.rimWidth).allowsHitTesting(false))
            }
        }
        // System glass casts its own shadow; adding ours on top makes it heavier than macOS.
        .shadow(color: .black.opacity(insidePanel || r.isSystem ? 0 : s.opacity), radius: s.radius, y: s.y)
    }
}

/// A selectable element (tab, list row, effect chip). Selected uses an elevated pill legible under any accent color.
private struct GlassSelectable<S: InsettableShape>: ViewModifier {
    let shape: S
    let selected: Bool
    let hovering: Bool

    func body(content: Content) -> some View {
        content.background {
            if selected {
                GlassSelectionIndicator(shape: shape)
            } else if hovering {
                GlassHoverIndicator(shape: shape)
            }
        }
    }
}

/// Hover highlight fill shared by nested selectable controls and dock items.
struct GlassHoverIndicator<S: InsettableShape>: View {
    let shape: S
    private let env = GlassEnvironment()

    var body: some View {
        shape.fill(env.resolver.fill(.control, hovering: true))
    }
}

/// The selected-state pill on its own, so it can carry a `matchedGeometryEffect`.
struct GlassSelectionIndicator<S: InsettableShape>: View {
    let shape: S
    var prominent = false
    @Environment(\.insideGlassPanel) private var insidePanel
    private let env = GlassEnvironment()

    var body: some View {
        let r = env.resolver
        let t = r.selectionTokens(prominent: prominent)
        let fillView = SelectionFillLayers(shape: shape, tokens: t)
            .shadow(color: .black.opacity(t.shadowOpacity), radius: 3, y: 1.5)

        if insidePanel || r.isSolid {
            fillView
        } else {
            fillView
                .glassEffect(r.glass(interactive: true, tint: r.prominentGlassTint), in: shape)
        }
    }
}

/// Flat tinted surface for things inside a glass panel (see `NestedRole`).
private struct NestedSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let role: NestedRole
    let hovering: Bool
    private let env = GlassEnvironment()

    func body(content: Content) -> some View {
        let r = env.resolver
        content
            .background(shape.fill(r.fill(role, hovering: hovering)))
            .overlay(shape.strokeBorder(r.nestedStroke, lineWidth: r.rimWidth).allowsHitTesting(false))
    }
}

/// A tappable chip inside a panel: tinted when idle, accent glass when selected.
/// Used for effect buttons, keycode tiles, category and knob chips, and icon buttons.
private struct Chip<S: InsettableShape>: ViewModifier {
    let shape: S
    let selected: Bool
    let hovering: Bool
    @Environment(\.isEnabled) private var isEnabled
    private let env = GlassEnvironment()

    func body(content: Content) -> some View {
        let r = env.resolver
        content
            .background {
                if selected {
                    GlassSelectionIndicator(shape: shape)
                } else {
                    shape.fill(r.fill(.control, hovering: hovering && isEnabled))
                        .overlay(shape.strokeBorder(r.nestedStroke, lineWidth: r.rimWidth))
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : Dim.disabled)
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

extension View {
    /// Glass panel or pill. Use `interactive: true` for buttons and fields.
    func glassSurface<S: InsettableShape>(
        _ shape: S,
        interactive: Bool = false,
        elevation: GlassElevation = .none,
        scrim: Bool = false,
        prominent: Bool = false
    ) -> some View {
        modifier(GlassSurface(shape: shape, interactive: interactive, elevation: elevation, scrim: scrim, prominent: prominent))
    }

    func glassSurface(
        interactive: Bool = false,
        elevation: GlassElevation = .none,
        scrim: Bool = false,
        prominent: Bool = false
    ) -> some View {
        glassSurface(Capsule(), interactive: interactive, elevation: elevation, scrim: scrim, prominent: prominent)
    }

    /// Large floating panel: glass plus a readability scrim, clipped to the panel shape,
    /// and marked `.insideGlassPanel` so nested buttons/fields never stack glass on glass.
    func glassPanel(elevation: GlassElevation = .high) -> some View {
        let shape = RoundedRectangle(cornerRadius: Corner.panel, style: .continuous)
        return environment(\.insideGlassPanel, true)
            .clipShape(shape)
            .modifier(GlassSurface(shape: shape, interactive: false, elevation: elevation, scrim: true))
    }

    func glassSelectable<S: InsettableShape>(_ shape: S = Capsule(), selected: Bool, hovering: Bool = false) -> some View {
        modifier(GlassSelectable(shape: shape, selected: selected, hovering: hovering))
    }

    /// Tinted surface inside a glass panel: a card, a recessed track, or an idle control.
    func nestedSurface<S: InsettableShape>(_ shape: S, role: NestedRole, hovering: Bool = false) -> some View {
        modifier(NestedSurface(shape: shape, role: role, hovering: hovering))
    }

    /// Chip inside a panel: tinted when idle, accent glass when selected, dimmed when disabled.
    func chip<S: InsettableShape>(_ shape: S = Capsule(), selected: Bool, hovering: Bool = false) -> some View {
        modifier(Chip(shape: shape, selected: selected, hovering: hovering))
    }

    /// Dims plain content (labels, swatches, menu labels) when its container is disabled.
    /// Controls built on the kit already do this themselves.
    func dimsWhenDisabled() -> some View { modifier(DimWhenDisabled()) }

    /// Floating bar or card over the scene (Test bars, toasts): one radius and elevation for all.
    func hudSurface() -> some View {
        glassSurface(RoundedRectangle(cornerRadius: Corner.panel, style: .continuous), elevation: .medium, scrim: true)
    }

    /// Applies the user's appearance choice; `.system` leaves macOS in charge.
    func studioAppearance() -> some View { modifier(AppearanceModifier()) }
}

private struct DimWhenDisabled: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1 : Dim.disabled)
    }
}

private struct AppearanceModifier: ViewModifier {
    @AppStorage(GlassKeys.appearance) private var appearance: AppearancePreference = .system
    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance.colorScheme)
    }
}

/// Scroll view that is exactly as tall as its content until it runs out of room, then scrolls.
/// Side panels use it so they hug short content instead of stretching into an empty glass slab,
/// and so the content is built once (unlike `ViewThatFits`, which lays out every candidate).
struct FittedScroll<Content: View>: View {
    var maxHeight: CGFloat = .infinity
    var scrollbarInsets: (top: CGFloat, bottom: CGFloat, trailing: CGFloat) = (14, 14, 4)
    @ViewBuilder var content: Content

    @ViewState private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(height - contentHeight) > 0.5 { contentHeight = height }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.automatic)
        .frame(maxHeight: contentHeight > 0 ? min(contentHeight, maxHeight) : maxHeight)
        .glassScrollbars(top: scrollbarInsets.top, bottom: scrollbarInsets.bottom, trailing: scrollbarInsets.trailing)
    }
}
