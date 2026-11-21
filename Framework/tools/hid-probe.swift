// hid-probe.swift: lists every HID device macOS can see, with the interfaces each one exposes.
// Read-only: it opens nothing and sends nothing.
//
//   swift Framework/tools/hid-probe.swift            # all devices
//   swift Framework/tools/hid-probe.swift keyboard   # filter by product or manufacturer name
//
// Usage pages to look for:
//   0x0001  Generic Desktop (0x06 keyboard, 0x02 mouse)   0x000C  Consumer (media keys)
//   0xFF60  QMK/VIA raw HID (usage 0x61), the configuration channel for VIA keyboards
//   0xFF00–0xFFFF  vendor-defined; usually the vendor's own configuration protocol
import Foundation
import IOKit.hid

let filter = CommandLine.arguments.dropFirst().first?.lowercased()
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, nil)
guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
    print("No HID devices visible. (Is Input Monitoring blocked for this terminal?)")
    exit(0)
}

func prop<T>(_ d: IOHIDDevice, _ key: String) -> T? { IOHIDDeviceGetProperty(d, key as CFString) as? T }
func hex(_ v: Int?, _ width: Int = 4) -> String { v.map { String(format: "%0\(width)X", $0) } ?? "----" }

struct Row { let name: String; let vid: Int; let pid: Int; let lines: [String] }
var groups: [String: Row] = [:]

for d in set {
    let name: String = prop(d, kIOHIDProductKey) ?? "(unnamed)"
    let maker: String = prop(d, kIOHIDManufacturerKey) ?? ""
    if let filter, !"\(name) \(maker)".lowercased().contains(filter) { continue }
    let vid: Int = prop(d, kIOHIDVendorIDKey) ?? 0
    let pid: Int = prop(d, kIOHIDProductIDKey) ?? 0
    let transport: String = prop(d, kIOHIDTransportKey) ?? "?"
    let page: Int? = prop(d, kIOHIDPrimaryUsagePageKey)
    let usage: Int? = prop(d, kIOHIDPrimaryUsageKey)
    let inSize: Int? = prop(d, kIOHIDMaxInputReportSizeKey)
    let outSize: Int? = prop(d, kIOHIDMaxOutputReportSizeKey)
    let featSize: Int? = prop(d, kIOHIDMaxFeatureReportSizeKey)
    let version: Int? = prop(d, kIOHIDVersionNumberKey)
    let pairs = (prop(d, kIOHIDDeviceUsagePairsKey) as [[String: Int]]?) ?? []
    let pairText = pairs.compactMap { p -> String? in
        guard let pg = p[kIOHIDDeviceUsagePageKey], let u = p[kIOHIDDeviceUsageKey] else { return nil }
        return "\(hex(pg)):\(hex(u, 2))"
    }.joined(separator: " ")
    var tag = ""
    if page == 0xFF60 { tag = "  <- VIA raw HID" } else if let page, page >= 0xFF00 { tag = "  <- vendor channel" }
    let line = "  \(transport.padding(toLength: 10, withPad: " ", startingAt: 0)) page \(hex(page)):\(hex(usage, 2))"
        + "  in/out/feature \(inSize ?? 0)/\(outSize ?? 0)/\(featSize ?? 0)"
        + (pairText.isEmpty ? "" : "  usages [\(pairText)]") + tag
    let key = "\(vid)-\(pid)-\(name)"
    let header = "\(name)\(maker.isEmpty ? "" : " — \(maker)")  \(hex(vid)):\(hex(pid))  fw \(hex(version))"
    let old = groups[key]
    groups[key] = Row(name: header, vid: vid, pid: pid, lines: (old?.lines ?? []) + [line])
}

for row in groups.values.sorted(by: { $0.name < $1.name }) {
    print(row.name)
    row.lines.sorted().forEach { print($0) }
    print()
}
print("\(groups.count) device(s). Record what you find in device-profile.yaml before writing anything to a device.")
