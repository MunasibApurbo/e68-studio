import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var store: KeyboardStore

    var body: some View {
        PanelScroll {
            GroupedSection(title: "Connection") {
                if let d = store.device {
                    GroupedRow("Keyboard", value: d.product)
                    GroupedRow("Maker ID", value: d.manufacturer.isEmpty ? "Not reported" : d.manufacturer)
                    GroupedRow("Connected by", value: d.link)
                    GroupedRow("Firmware", value: d.firmware)
                    GroupedRow("USB ID", value: d.usbID)
                    if let bt = store.bluetoothDevice, let battery = bt.batteryLevel {
                        GroupedRow("Bluetooth battery", value: "\(battery)%")
                    }
                } else if let bt = store.bluetoothDevice {
                    GroupedRow("Keyboard", value: bt.product)
                    GroupedRow("Connected by", value: bt.link)
                    GroupedRow("Transport", value: bt.transport)
                    GroupedRow("Battery", value: bt.batteryLevel.map { "\($0)%" } ?? "Not reported")
                    GroupedRow("Bluetooth ID", value: bt.hardwareID)
                    if !bt.formattedAddress.isEmpty {
                        GroupedRow("Address", value: bt.formattedAddress)
                    }
                } else {
                    switch store.connection {
                    case .loading:
                        GroupedRow("Keyboard", value: "Reading…")
                    case .failed(let message):
                        GroupedRow(label: "Keyboard", detail: message) {
                            GroupedValue(text: "Not responding")
                        }
                    default:
                        GroupedRow("Keyboard", value: "Not connected")
                    }
                }
            }

            if store.isReady {
                GroupedSection(title: "Configuration") {
                    GroupedRow("Protocol", value: "VIA version \(store.protocolVersion)")
                    GroupedRow("Layers", value: "\(store.layerCount)")
                    GroupedRow("Remappable positions", value: "\(Layout.keys.count) keys and 3 knob actions")
                    GroupedRow("Macro slots", value: "\(store.macroCount)")
                    GroupedRow("Macro memory", value: "\(store.macroCapacity) bytes usable of \(store.macroBufferSize)")
                    GroupedRow("Report rate over USB", value: "1000 Hz")
                }
            } else if store.isBluetooth {
                GroupedSection(title: "Configuration") {
                    GroupedRow("Over Bluetooth", value: "Key Test only")
                    GroupedRow("Keys, lighting, macros", value: "USB or 2.4 GHz")
                }
            }

            GroupedSection(title: "Specifications") {
                GroupedRow("Layout", value: "65%, 67 keys and a rotary knob")
                GroupedRow("Case", value: "CNC aluminium alloy")
                GroupedRow("Plate", value: "Slotted polycarbonate")
                GroupedRow("Circuit board", value: "1.2 mm with per-key flex cuts, hot-swap for 3- and 5-pin switches")
                GroupedRow("Switches as shipped", value: "Lemon Grape")
                GroupedRow("Keycaps", value: "Double-shot PBT")
                GroupedRow("Stabilisers", value: "POM")
                GroupedRow("Sound dampening", value: "PO foam, IXPE switch pad, PET pad, bottom foam")
                GroupedRow("Backlight", value: "RGB, 16.8 million colours, 18 effects")
                GroupedRow("Connections", value: "USB-C, 2.4 GHz receiver, Bluetooth with 3 channels")
                GroupedRow("Battery", value: "4000 mAh")
                GroupedRow("Weight", value: "About 0.8 kg")
            }
        }
    }
}
