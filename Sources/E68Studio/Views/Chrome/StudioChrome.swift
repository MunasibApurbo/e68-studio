import SwiftUI

// MARK: - Keyboard Studio

struct StudioChrome: View {
    @EnvironmentObject private var store: KeyboardStore

    var body: some View {
        VStack(spacing: Space.m) {
            StudioTopBar(
                otherTitle: "Mouse",
                otherSymbol: "computermouse",
                otherHelp: "Switch to the mouse",
                onBack: { store.leaveStudio() },
                onOther: { store.enterMouseStudio() }
            ) {
                ViewThatFits(in: .horizontal) {
                    StatusPill(compact: false)
                    StatusPill(compact: true)
                }
            }

            panel
                .padding(.horizontal, Space.edge)
                .frame(maxHeight: .infinity, alignment: panelAlignment)

            Dock(selection: $store.section)
                .padding(.bottom, Space.l)
        }
    }

    /// Side panels hang from the top bar like an inspector; wide panels and HUDs sit on the dock.
    private var panelAlignment: Alignment {
        guard store.isReady || store.section == .more || (store.section == .test && store.isConnected) else { return .center }
        return store.section == .keys || store.section == .light ? .topTrailing : .bottom
    }

    @ViewBuilder
    private var panel: some View {
        if store.section == .test && store.isConnected {
            TestHUD()
        } else if !store.isReady && store.section != .more {
            VStack(spacing: 6) {
                Group {
                    if case .loading = store.connection {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: disconnectedSymbol)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(Ink.secondary)
                    }
                }
                .frame(height: 28)
                Text(disconnectedHeadline)
                    .font(.studioHeading)
                if let disconnectedDetail {
                    Text(disconnectedDetail)
                        .font(.studioDetail)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .failed = store.connection {
                    Button("Retry") {
                        Task { await store.reload() }
                    }
                    .buttonStyle(.glassCapsule(.prominent, size: .small))
                    .padding(.top, 4)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.l)
            .glassPanel()
        } else {
            switch store.section {
            case .test:
                TestHUD()
            case .keys:
                KeymapView()
                    .frame(width: SidePanel.width)
                    .glassPanel()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .light:
                LightPanel()
                    .frame(width: SidePanel.width)
                    .glassPanel()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .macros:
                MacrosView()
                    .frame(maxWidth: 900)
                    .frame(minHeight: 260, idealHeight: 380, maxHeight: 410)
                    .glassPanel()
            case .more:
                MorePanel()
                    .frame(maxWidth: 760)
                    .frame(minHeight: 260, idealHeight: 380, maxHeight: 410)
                    .glassPanel()
            }
        }
    }

    private var disconnectedHeadline: String {
        switch store.connection {
        case .loading: return "Reading the keyboard…"
        case .bluetooth: return "Connected over Bluetooth"
        case .failed: return "Keyboard not responding"
        case .searching, .ready: return "Keyboard not connected"
        }
    }

    private var disconnectedSymbol: String {
        switch store.connection {
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .failed: return "exclamationmark.triangle"
        default: return "cable.connector"
        }
    }

    private var disconnectedDetail: String? {
        switch store.connection {
        case .bluetooth:
            return "Key Test works now. To change keys or lighting, connect by USB or the 2.4 GHz receiver."
        case .searching:
            return "Plug in the USB cable or the 2.4 GHz receiver."
        case .failed(let message):
            return message
        case .loading, .ready:
            return nil
        }
    }
}

// MARK: - Mouse Studio

struct MouseChrome: View {
    @EnvironmentObject private var store: KeyboardStore

    var body: some View {
        VStack(spacing: Space.m) {
            StudioTopBar(
                otherTitle: "Keyboard",
                otherSymbol: "keyboard",
                otherHelp: "Switch to the keyboard",
                onBack: { store.leaveStudio() },
                onOther: { store.enterStudio() }
            ) {
                ViewThatFits(in: .horizontal) {
                    MouseStatusPill(compact: false)
                    MouseStatusPill(compact: true)
                }
            }

            panel
                .padding(.horizontal, Space.edge)
                .frame(maxHeight: .infinity, alignment: panelAlignment)

            Dock(selection: $store.mouseSection)
                .padding(.bottom, Space.l)
        }
    }

    private var panelAlignment: Alignment {
        switch store.mouseSection {
        case .dpi, .buttons, .scroll: return .topTrailing
        case .test, .more: return .bottom
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch store.mouseSection {
        case .test:
            MouseTestHUD()
        case .dpi:
            sidePanel { DPIPanel() }
        case .buttons:
            sidePanel { ButtonsPanel() }
        case .scroll:
            sidePanel { ScrollPanel() }
        case .more:
            MouseMorePanel()
                .frame(maxWidth: 760)
                .frame(minHeight: 260, idealHeight: 380, maxHeight: 410)
                .glassPanel()
        }
    }

    /// Same placement as the keyboard's Light panel: on the right, the mouse on the left.
    private func sidePanel<P: View>(@ViewBuilder _ content: () -> P) -> some View {
        content()
            .frame(width: SidePanel.width)
            .glassPanel()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Shared Chrome

enum SidePanel {
    static let width: CGFloat = 296
    /// Never taller than this, even in a very tall window, so the panel stays a panel.
    static let maxHeight: CGFloat = 560
}

/// Back to the desk on the left, the device's status in the middle-left, the other device on the right.
private struct StudioTopBar<Status: View>: View {
    let otherTitle: String
    let otherSymbol: String
    let otherHelp: String
    let onBack: () -> Void
    let onOther: () -> Void
    @ViewBuilder var status: Status

    var body: some View {
        GlassContainer(spacing: Space.s) {
            HStack(spacing: Space.s) {
                Button(action: onBack) {
                    Label("Desk", systemImage: "chevron.left")
                }
                .buttonStyle(.glassCapsule)
                .help("Back to the desk (Esc)")
                .layoutPriority(2)

                status
                    .layoutPriority(1)

                Spacer(minLength: Space.s)

                Button(action: onOther) {
                    Label(otherTitle, systemImage: otherSymbol)
                }
                .buttonStyle(.glassCapsule)
                .help(otherHelp)
                .layoutPriority(2)
            }
        }
        .topChromeInsets()
    }
}

// MARK: - Dock & More

/// A studio's sections, shown as the glass dock at the bottom.
private protocol DockSection: CaseIterable, Identifiable, Hashable where AllCases: RandomAccessCollection {
    var title: String { get }
    var symbol: String { get }
}

extension StudioSection: DockSection {}
extension MouseSection: DockSection {}

private struct Dock<Section: DockSection>: View {
    @Binding var selection: Section
    @Namespace private var dockNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Section.allCases), id: \.self) { section in
                DockItem(
                    title: section.title,
                    symbol: section.symbol,
                    selected: selection == section
                ) {
                    guard selection != section else { return }
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                    withAnimation(Motion.select) {
                        selection = section
                    }
                }
                .selectionAnchor(section, in: dockNamespace)
            }
        }
        .slidingSelection(selection, in: dockNamespace)
        .environment(\.insideGlassPanel, true)
        .padding(5)
        .glassSurface(elevation: .medium, scrim: true)
    }
}

private struct DockItem: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 20)
                Text(title)
                    .font(.studioMeta.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(selected || hovering ? Color.primary : Ink.secondary)
            .animation(Motion.select, value: selected)
            .animation(.smooth(duration: 0.15), value: hovering)
            .frame(width: 68, height: 48)
            .background {
                if hovering && !selected {
                    GlassHoverIndicator(shape: Capsule())
                        .transition(.opacity)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MorePanel: View {
    @ViewState private var tab = 0
    private let tabs = ["Profiles", "Fn Shortcuts", "Snippets", "Backup & Reset", "Device"]

    var body: some View {
        VStack(spacing: 0) {
            GlassSegmented(
                selection: $tab,
                options: tabs.enumerated().map { ($0.offset, $0.element) }
            )
            .padding(.top, Space.l)
            .padding(.bottom, Space.xs)

            Group {
                switch tab {
                case 0: ProfilesView()
                case 1: ShortcutsView()
                case 2: SnippetsView()
                case 3: BackupView()
                default: DeviceView()
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
