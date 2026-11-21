import SwiftUI

// MARK: - More

struct MouseMorePanel: View {
    @ViewState private var tab = 0
    private let tabs = ["Device", "Reset"]

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
                case 0: MouseDeviceView()
                default: MouseResetView()
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct MouseDeviceView: View {
    @ObservedObject private var mouse = MouseStore.shared
    @ObservedObject private var remapper = MouseRemapper.shared

    var body: some View {
        PanelScroll {
            GroupedSection(title: "Connection") {
                if let info = mouse.info {
                    GroupedRow("Mouse", value: info.product)
                    GroupedRow("Connected by", value: info.link)
                    if let battery = info.battery {
                        GroupedRow("Battery", value: "\(battery)%")
                    }
                    GroupedRow("Firmware", value: info.firmware)
                    GroupedRow("USB ID", value: info.usbID)
                    if info.serial != "Not reported" {
                        GroupedRow("Serial", value: info.serial)
                    }
                } else {
                    GroupedRow("Mouse", value: "Not connected")
                }
            }

            GroupedSection(title: "Storage") {
                GroupedRow("DPI & acceleration", value: "macOS (until reconnect)")
                GroupedRow("Buttons, gestures, wheel", value: "Active while app runs")
                GroupedRow("Hardware DPI, polling, lift-off", value: "In the mouse (M HUB)")
                GroupedRow("Accessibility access", value: remapper.trusted ? "Allowed" : "Not allowed")
            }

            GroupedSection(title: "MCHOSE G7") {
                GroupedRow("Shape", value: "Right-handed, 129.4 × 74.6 × 41.1 mm")
                GroupedRow("Weight", value: "About 59 g")
                GroupedRow("Sensor", value: "PixArt PAW3311, up to 12,000 DPI")
                GroupedRow("Report rate", value: "1000 Hz")
                GroupedRow("Buttons", value: "Left, right, wheel, forward, back")
                GroupedRow("Connections", value: "USB-C, 2.4 GHz, Bluetooth")
            }
        }
    }
}

private struct MouseResetView: View {
    @ObservedObject private var mouse = MouseStore.shared
    @ViewState private var confirmAll = false

    var body: some View {
        PanelScroll {
            GroupedSection(title: "Reset") {
                GroupedRow(label: "DPI stages") {
                    Button("Reset") { mouse.resetStages() }.buttonStyle(.glassCapsule(size: .small))
                }
                GroupedRow(label: "Buttons") {
                    Button("Reset") {
                        mouse.batchUpdate {
                            mouse.bindings = [:]
                            mouse.gestures = [:]
                            mouse.gestureDistance = 50
                        }
                    }
                    .buttonStyle(.glassCapsule(size: .small))
                    .disabled(mouse.bindings.isEmpty && mouse.gestures.isEmpty && mouse.gestureDistance == 50)
                }
                GroupedRow(label: "Wheel and clicks") {
                    Button("Reset") {
                        mouse.batchUpdate {
                            mouse.reverseScroll = false
                            mouse.scrollQuarterSteps = 4
                            mouse.debounceMS = 0
                        }
                    }
                    .buttonStyle(.glassCapsule(size: .small))
                    .disabled(!mouse.reverseScroll && mouse.scrollQuarterSteps == 4 && mouse.debounceMS == 0)
                }
                GroupedRow(label: "Everything") {
                    Button("Reset All…") { confirmAll = true }
                        .buttonStyle(.glassCapsule(.destructive, size: .small))
                }
            }
        }
        .confirmationDialog("Reset all mouse settings?", isPresented: $confirmAll) {
            Button("Reset All", role: .destructive) {
                mouse.restoreDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("DPI stages, buttons, and wheel settings go back to defaults. Hardware DPI and settings stored in the mouse stay as they are.")
        }
    }
}
