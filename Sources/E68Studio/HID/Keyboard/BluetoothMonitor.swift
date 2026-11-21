import Foundation
import IOKit
import IOKit.hid

/// Metadata for an E-68 PRO connected over Bluetooth Low Energy.
struct BluetoothDeviceInfo: Equatable {
    var registryEntryID: UInt64
    var product: String
    var vendorID: Int
    var productID: Int
    var versionBCD: Int
    var transport: String
    var address: String
    var peripheralUUID: String
    var batteryLevel: Int?

    var hardwareID: String {
        String(format: "%04X:%04X", vendorID, productID)
    }

    var channel: String? {
        for suffix in ["BT1", "BT2", "BT3"] where product.localizedCaseInsensitiveContains(suffix) {
            return suffix
        }
        return nil
    }

    var link: String {
        if let channel { return "Bluetooth (\(channel))" }
        return "Bluetooth"
    }

    var formattedAddress: String {
        address.replacingOccurrences(of: "-", with: ":").uppercased()
    }
}

/// Detects E-68 PRO keyboards over Bluetooth using IORegistry metadata (no HID open,
/// so Input Monitoring permission is never requested) and optionally reads the standard
/// BLE Battery Service (0x180F / 0x2A19) via CoreBluetooth when bundled with usage info.
final class BluetoothMonitor: @unchecked Sendable {
    static let bleVendorID = 0x245A
    static let bleProductID = 0x8276

    var onConnect: ((BluetoothDeviceInfo) -> Void)?
    var onDisconnect: (() -> Void)?
    var onBatteryUpdate: ((Int?) -> Void)?

    private let queue = DispatchQueue(label: "e68.bluetooth.monitor", qos: .utility)
    private var notificationPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var devicesByID: [UInt64: BluetoothDeviceInfo] = [:]
    private var activeEntryID: UInt64?
    private var started = false

    private var batteryReader: BLEBatteryReader?

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.batteryReader?.stop()
            self.batteryReader = nil
            if self.matchedIterator != 0 {
                IOObjectRelease(self.matchedIterator)
                self.matchedIterator = 0
            }
            if self.terminatedIterator != 0 {
                IOObjectRelease(self.terminatedIterator)
                self.terminatedIterator = 0
            }
            if let port = self.notificationPort {
                IONotificationPortDestroy(port)
                self.notificationPort = nil
            }
            self.devicesByID.removeAll()
            self.activeEntryID = nil
            self.started = false
        }
    }

    private func startOnQueue() {
        guard !started else { return }
        started = true

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, queue)

        let ctx = Unmanaged.passUnretained(self).toOpaque()

        if let matchDict = IOServiceMatching("IOHIDDevice") {
            let kr = IOServiceAddMatchingNotification(
                port,
                kIOMatchedNotification,
                matchDict,
                { ctx, iterator in
                    guard let ctx else { return }
                    Unmanaged<BluetoothMonitor>.fromOpaque(ctx).takeUnretainedValue().handleMatched(iterator)
                },
                ctx,
                &matchedIterator
            )
            if kr == KERN_SUCCESS {
                handleMatched(matchedIterator)
            }
        }

        if let termDict = IOServiceMatching("IOHIDDevice") {
            let kr = IOServiceAddMatchingNotification(
                port,
                kIOTerminatedNotification,
                termDict,
                { ctx, iterator in
                    guard let ctx else { return }
                    Unmanaged<BluetoothMonitor>.fromOpaque(ctx).takeUnretainedValue().handleTerminated(iterator)
                },
                ctx,
                &terminatedIterator
            )
            if kr == KERN_SUCCESS {
                handleTerminated(terminatedIterator)
            }
        }
    }

    private func handleMatched(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let info = Self.parseDevice(service) else { continue }
            devicesByID[info.registryEntryID] = info
            if activeEntryID != info.registryEntryID {
                activeEntryID = info.registryEntryID
                DispatchQueue.main.async { [weak self] in
                    self?.onConnect?(info)
                }
                startBatteryReader(for: info)
            }
        }
    }

    private func handleTerminated(_ iterator: io_iterator_t) {
        var removedActive = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { continue }
            if devicesByID.removeValue(forKey: entryID) != nil, activeEntryID == entryID {
                removedActive = true
            }
        }

        guard removedActive else { return }
        if let fallback = devicesByID.values.first {
            activeEntryID = fallback.registryEntryID
            DispatchQueue.main.async { [weak self] in
                self?.onConnect?(fallback)
            }
            startBatteryReader(for: fallback)
        } else {
            activeEntryID = nil
            batteryReader?.stop()
            batteryReader = nil
            DispatchQueue.main.async { [weak self] in
                self?.onDisconnect?()
            }
        }
    }

    private func startBatteryReader(for info: BluetoothDeviceInfo) {
        // CoreBluetooth requires NSBluetoothAlwaysUsageDescription in Info.plist; skip in unbundled CLI runs.
        guard Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil else { return }
        batteryReader?.stop()
        let productName = info.product.trimmingCharacters(in: .whitespacesAndNewlines)
        let reader = BLEBatteryReader(
            peripheralUUID: info.peripheralUUID,
            queueLabel: "e68.bluetooth.battery",
            productMatch: { name in
                name.localizedCaseInsensitiveContains("E-68")
                    || name.localizedCaseInsensitiveContains("E68")
                    || (!productName.isEmpty && name.caseInsensitiveCompare(productName) == .orderedSame)
            },
            fallbackMatch: { name in
                name.localizedCaseInsensitiveContains("Furycube")
                    || name.localizedCaseInsensitiveContains("E-68")
                    || name.localizedCaseInsensitiveContains("E68")
            }
        ) { [weak self] level in
            guard let self else { return }
            self.queue.async {
                guard let activeID = self.activeEntryID, var current = self.devicesByID[activeID] else { return }
                current.batteryLevel = level
                self.devicesByID[activeID] = current
                DispatchQueue.main.async {
                    self.onBatteryUpdate?(level)
                }
            }
        }
        batteryReader = reader
        reader.start()
    }

    private static func parseDevice(_ service: io_service_t) -> BluetoothDeviceInfo? {
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let transport = props[kIOHIDTransportKey] as? String ?? ""
        let isBluetooth = transport.localizedCaseInsensitiveContains("Bluetooth")
        guard isBluetooth else { return nil }

        let product = props[kIOHIDProductKey] as? String ?? ""
        let vendorID = props[kIOHIDVendorIDKey] as? Int ?? 0
        let productID = props[kIOHIDProductIDKey] as? Int ?? 0

        let matchesE68IDs = (vendorID == bleVendorID && productID == bleProductID)
        let matchesName = product.localizedCaseInsensitiveContains("E-68") || product.localizedCaseInsensitiveContains("E68")
        guard matchesE68IDs || matchesName else { return nil }

        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }

        return BluetoothDeviceInfo(
            registryEntryID: entryID,
            product: product.isEmpty ? "E-68 PRO" : product,
            vendorID: vendorID,
            productID: productID,
            versionBCD: props[kIOHIDVersionNumberKey] as? Int ?? 0,
            transport: transport,
            address: props["DeviceAddress"] as? String ?? "",
            peripheralUUID: props[kIOHIDPhysicalDeviceUniqueIDKey] as? String ?? "",
            batteryLevel: nil
        )
    }
}
