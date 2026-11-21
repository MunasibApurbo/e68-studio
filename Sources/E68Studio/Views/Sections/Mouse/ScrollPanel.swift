import SwiftUI

// MARK: - Scroll

struct ScrollPanel: View {
    @ObservedObject private var mouse = MouseStore.shared

    var body: some View {
        SidePanelScroll {
            PanelTitle(title: "Wheel & Clicks")

            AccessBanner()

            SwitchRow(title: "Reverse scrolling", isOn: $mouse.reverseScroll)

            VStack(alignment: .leading, spacing: Space.s) {
                FieldHeader(title: "Scroll speed", value: speedLabel)
                StepSlider(
                    value: $mouse.scrollQuarterSteps,
                    range: 1...16,
                    label: "Scroll speed",
                    accessibilityValueText: speedLabel
                )
            }

            VStack(alignment: .leading, spacing: Space.s) {
                let debounceLabel = mouse.debounceMS == 0 ? "Off" : "\(mouse.debounceMS) ms"
                FieldHeader(title: "Double-click fix", value: debounceLabel)
                StepSlider(
                    value: Binding(get: { mouse.debounceMS / 5 }, set: { mouse.debounceMS = $0 * 5 }),
                    range: 0...20,
                    label: "Double-click fix",
                    accessibilityValueText: mouse.debounceMS == 0 ? "Off" : "\(mouse.debounceMS) milliseconds"
                )
            }

            Caption("Saved on this Mac. Active while E68 Studio is running.")
        }
    }

    private var speedLabel: String {
        let m = mouse.scrollMultiplier
        return m == m.rounded() ? "\(Int(m))×" : String(format: "%.3g×", m)
    }
}
