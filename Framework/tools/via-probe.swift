// via-probe.swift: asks a VIA keyboard who it is. Sends only read commands:
//   0x01 protocol version, 0x11 layer count, 0x0C macro count, 0x0D macro buffer size,
//   0x12 keymap buffer read (first key of layer 0).
// It never writes keys, lighting or EEPROM, and never sends 0x06/0x0A/0x0B (reset, EEPROM reset, bootloader).
//
//   swift Framework/tools/via-probe.swift             # first device on usage page 0xFF60
//   swift Framework/tools/via-probe.swift 320F 5055   # a specific vendor/product ID (hex)
import Foundation
import IOKit.hid

let args = CommandLine.arguments.dropFirst().map { Int($0, radix: 16) }
var matching: [String: Any] = [kIOHIDDeviceUsagePageKey: 0xFF60, kIOHIDDeviceUsageKey: 0x61]
if args.count >= 2, let vid = args[0], let pid = args[1] {
    matching[kIOHIDVendorIDKey] = vid
    matching[kIOHIDProductIDKey] = pid
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

guard let device = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first else {
    print("No VIA raw-HID interface (0xFF60:0x61) found. Connect the keyboard by USB or its dongle; Bluetooth links rarely expose it.")
    exit(1)
}
func prop<T>(_ key: String) -> T? { IOHIDDeviceGetProperty(device, key as CFString) as? T }
print("Device: \(prop(kIOHIDProductKey) as String? ?? "?")  \(String(format: "%04X:%04X", prop(kIOHIDVendorIDKey) as Int? ?? 0, prop(kIOHIDProductIDKey) as Int? ?? 0))  via \(prop(kIOHIDTransportKey) as String? ?? "?")")

var reply: [UInt8]?
let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { _, _, _, _, _, report, length in
    reply = Array(UnsafeBufferPointer(start: report, count: length))
}, nil)

func request(_ bytes: [UInt8]) -> [UInt8]? {
    var packet = [UInt8](repeating: 0, count: 32)
    for (i, b) in bytes.enumerated() { packet[i] = b }
    reply = nil
    let status = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, packet, packet.count)
    guard status == kIOReturnSuccess else { print(String(format: "  send failed 0x%08X", UInt32(bitPattern: status))); return nil }
    let deadline = Date().addingTimeInterval(1)
    while Date() < deadline {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
        if let r = reply, r.first == bytes.first { return r }
    }
    print("  no reply to command 0x\(String(format: "%02X", bytes[0]))")
    return nil
}

if let r = request([0x01]) { print("VIA protocol version: \(Int(r[1]) << 8 | Int(r[2]))") }
if let r = request([0x11]) { print("Dynamic keymap layers: \(r[1])") }
if let r = request([0x0C]) { print("Macro slots: \(r[1])") }
if let r = request([0x0D]) { print("Macro buffer: \(Int(r[1]) << 8 | Int(r[2])) bytes") }
if let r = request([0x12, 0x00, 0x00, 0x02]) { print(String(format: "Layer 0, matrix (0,0) keycode: 0x%02X%02X", r[4], r[5])) }
print("Read-only probe finished. Nothing was written.")
