import SwiftUI

// The mouse studio's panels. They follow the keyboard studio exactly: side panels sit
// on the right (like Light), the test bar floats at the bottom (like Key Test) and More is
// the same wide tabbed panel. One title per panel, FieldHeader + control pairs, plain-language
// captions, glass only on the panel itself and on selected rows.

/// Scroll container used by every mouse side panel; identical to the Light panel's.
struct SidePanelScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        FittedScroll(maxHeight: SidePanel.maxHeight) {
            VStack(alignment: .leading, spacing: Space.m) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.panel)
        }
    }
}

/// Panel title with optional subtitle.
struct PanelTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.studioTitle)
            if let detail {
                Text(detail)
                    .font(.studioDetail)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Secondary text under a control.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.studioMeta)
            .foregroundStyle(Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .dimsWhenDisabled()
    }
}

/// Switch row: label and optional detail on the left, accent switch on the right.
struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn.animation(.smooth(duration: 0.2))) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.studioHeading)
                if let detail { Caption(detail) }
            }
        }
        .toggleStyle(AccentSwitchStyle())
    }
}

/// Shown where a feature needs Accessibility access and it has not been granted yet.
struct AccessBanner: View {
    var floating = false
    @ObservedObject private var remapper = MouseRemapper.shared

    var body: some View {
        if !remapper.trusted {
            let content = VStack(alignment: .leading, spacing: Space.s) {
                Label("Accessibility access needed", systemImage: "hand.raised.fill")
                    .font(.studioHeading)
                Caption("Needed to read and remap mouse buttons and scrolling.")
                Button("Open Settings") { remapper.requestAccess() }
                    .buttonStyle(.glassCapsule(.prominent, size: .small))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if floating {
                content
                    .padding(Space.m)
                    .frame(maxWidth: 520)
                    .glassPanel(elevation: .medium)
            } else {
                content
                    .insetCard()
            }
        }
    }
}

func stageColor(_ index: Int) -> Color {
    let count = DPIStage.palette.count
    let safe = ((index % count) + count) % count
    return Color(nsColor: DPIStage.palette[safe])
}
