import Foundation
import IOKit
import IOKit.hid

// The HID event system is the only place macOS lets an app change pointer behaviour for one
// specific mouse (instead of the system-wide slider). These entry points live in IOKit and are
// what utilities such as LinearMouse use; they are declared here because IOKit ships no Swift header for them.
@_silgen_name("IOHIDEventSystemClientCreate") private func HIDClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventSystemClientCopyServices") private func HIDClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty") private func HIDServiceCopy(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientSetProperty") private func HIDServiceSet(_ service: AnyObject, _ key: CFString, _ value: AnyObject) -> Bool
@_silgen_name("IOHIDServiceClientGetRegistryID") private func HIDServiceGetRegistryID(_ service: AnyObject) -> Unmanaged<AnyObject>?

extension MouseStore {
    private static let hidClient: AnyObject? = HIDClientCreate(kCFAllocatorDefault)?.takeRetainedValue()

    /// USB IDs the G7 uses: cable (A8A4), 2.4 GHz receiver (A8A5), and Bluetooth LE (2717:32B0).
    private static let usbVendors: Set<Int> = [0xA8A4, 0xA8A5]
    private static let bluetoothID = (vendor: 0x2717, product: 0x32B0)
    private static let btFirmwareRevisionKey = "kBTFirmwareRevisionKey"

    func refresh(applySettings: Bool = true) {
        guard let client = Self.hidClient,
              let all = HIDClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else { return }
        func string(_ s: AnyObject, _ key: String) -> String? { HIDServiceCopy(s, key as CFString)?.takeRetainedValue() as? String }
        func int(_ s: AnyObject, _ key: String) -> Int? { (HIDServiceCopy(s, key as CFString)?.takeRetainedValue() as? NSNumber)?.intValue }

        // The pointer interface of the G7 on any link. The receiver may report its own name rather
        // than the mouse's, so it is also recognised by its USB vendor ID.
        struct Link { let service: AnyObject; let name: String; let rank: Int; let id: String; let vid: Int; let pid: Int; let transport: String; let rawProduct: String }
        var links: [Link] = all.compactMap { s in
            guard int(s, "PrimaryUsagePage") == 1, int(s, "PrimaryUsage") == 2 else { return nil }
            let rawProduct = string(s, "Product") ?? ""
            let vid = int(s, "VendorID") ?? 0
            let pid = int(s, "ProductID") ?? 0
            guard rawProduct.localizedCaseInsensitiveContains("MCHOSE")
                || Self.usbVendors.contains(vid)
                || (vid == Self.bluetoothID.vendor && pid == Self.bluetoothID.product)
            else { return nil }
            let transport = string(s, "Transport") ?? "Unknown"
            let (name, rank): (String, Int) = switch transport {
            case "USB": vid == 0xA8A5 ? ("2.4 GHz receiver", 1) : ("USB cable", 0)
            case "Bluetooth Low Energy", "Bluetooth": ("Bluetooth", 2)
            default: (transport, 3)
            }
            let loc = int(s, "LocationID") ?? 0
            let regID = (HIDServiceGetRegistryID(s)?.takeUnretainedValue() as? NSNumber)?.uint64Value ?? 0
            return Link(service: s, name: name, rank: rank, id: "\(regID)-\(loc)-\(vid)-\(pid)-\(transport)", vid: vid, pid: pid, transport: transport, rawProduct: rawProduct)
        }
        guard !links.isEmpty else {
            MouseRemapper.shared.cancelActiveInputs()
            if info != nil { info = nil }
            if !services.isEmpty { services = [] }
            if !serviceIDs.isEmpty { serviceIDs = [] }
            orderedServiceIDs = []
            if lastApplyFailed { lastApplyFailed = false }
            initialResolutions.removeAll()
            linkMetaCache.removeAll()
            lastHIDBattery = nil
            stopBLEBatteryReader()
            endSniper(announce: false)
            return
        }
        links.sort { $0.rank < $1.rank }

        // Only capture the pointer resolution baseline while custom DPI scaling is off,
        // so relaunching with custom DPI active does not treat a modified resolution as factory baseline.
        if !customEnabled {
            for link in links where initialResolutions[link.id] == nil {
                if let raw = HIDServiceCopy(link.service, "HIDPointerResolution" as CFString)?.takeRetainedValue() as? NSNumber,
                   raw.intValue > 0 {
                    initialResolutions[link.id] = raw
                } else {
                    initialResolutions[link.id] = NSNumber(value: 400 * 65536)
                }
            }
        }

        func cachedMeta(for link: Link) -> LinkMeta {
            if let hit = linkMetaCache[link.id] { return hit }
            let version = int(link.service, "VersionNumber") ?? 0
            let meta = LinkMeta(
                product: link.rawProduct.localizedCaseInsensitiveContains("MCHOSE") ? link.rawProduct : "MCHOSE G7",
                firmware: Self.firmwareString(for: link.service, fallbackVersion: version),
                serial: string(link.service, "SerialNumber") ?? "Not reported",
                btUUID: (Self.registryProperty(link.service, key: kIOHIDPhysicalDeviceUniqueIDKey) as? String) ?? ""
            )
            linkMetaCache[link.id] = meta
            return meta
        }

        let primary = links[0]
        let names = links.map(\.name).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let hidBattery = int(primary.service, "BatteryPercent") ?? links.compactMap { int($0.service, "BatteryPercent") }.first
        lastHIDBattery = hidBattery

        let btLink = links.first {
            $0.transport.localizedCaseInsensitiveContains("Bluetooth")
                || ($0.vid == Self.bluetoothID.vendor && $0.pid == Self.bluetoothID.product)
        }
        if hidBattery == nil,
           let btLink,
           Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil {
            let btMeta = cachedMeta(for: btLink)
            let key = "\(btLink.id)|\(btMeta.btUUID)"
            if bleBatteryTargetKey != key {
                bleBatteryReader?.stop()
                bleBatteryLevel = nil
                bleBatteryTargetKey = key
                let specificProduct = btLink.rawProduct.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasSpecificProduct = !specificProduct.isEmpty && specificProduct.caseInsensitiveCompare("MCHOSE") != .orderedSame
                let reader = BLEBatteryReader(
                    peripheralUUID: btMeta.btUUID,
                    queueLabel: "e68.mouse.bluetooth.battery",
                    productMatch: { name in
                        (hasSpecificProduct && name.caseInsensitiveCompare(specificProduct) == .orderedSame)
                            || name.localizedCaseInsensitiveContains("MCHOSE G7")
                    },
                    fallbackMatch: { name in
                        name.localizedCaseInsensitiveContains("MCHOSE")
                    }
                ) { [weak self] level in
                    Task { @MainActor [weak self] in
                        guard let self, self.bleBatteryTargetKey == key else { return }
                        self.bleBatteryLevel = level
                        if self.lastHIDBattery == nil, var current = self.info, current.battery != level {
                            current.battery = level
                            self.info = current
                            BatteryNotifier.shared.check(deviceName: current.product, level: level, isMouse: true)
                        }
                    }
                }
                bleBatteryReader = reader
                reader.start()
            }
        } else {
            stopBLEBatteryReader()
        }

        let primaryMeta = cachedMeta(for: primary)
        let next = Info(
            product: primaryMeta.product,
            link: names.joined(separator: " + "),
            usbID: String(format: "%04X:%04X", primary.vid, primary.pid),
            firmware: primaryMeta.firmware,
            serial: primaryMeta.serial,
            battery: hidBattery ?? bleBatteryLevel
        )
        let ids = Set(links.map(\.id))
        let changed = ids != serviceIDs
        orderedServiceIDs = links.map(\.id)
        services = links.map(\.service)
        if changed {
            serviceIDs = ids
            linkMetaCache = linkMetaCache.filter { ids.contains($0.key) }
            initialResolutions = initialResolutions.filter { ids.contains($0.key) }
        }
        if info != next {
            info = next
            BatteryNotifier.shared.check(deviceName: next.product, level: next.battery, isMouse: true)
        }
        // macOS forgets per-device settings when a link reconnects, so re-apply on any change or failed attempt.
        if applySettings && (changed || lastApplyFailed) { apply() }
    }

    func stopBLEBatteryReader() {
        bleBatteryReader?.stop()
        bleBatteryReader = nil
        bleBatteryTargetKey = nil
        bleBatteryLevel = nil
    }

    private static func registryProperty(_ service: AnyObject, key: String) -> AnyObject? {
        if let direct = HIDServiceCopy(service, key as CFString)?.takeRetainedValue() {
            return direct
        }
        guard let regNum = HIDServiceGetRegistryID(service)?.takeUnretainedValue() as? NSNumber else { return nil }
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(regNum.uint64Value))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return IORegistryEntrySearchCFProperty(
            entry,
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        )
    }

    private static func firmwareString(for service: AnyObject, fallbackVersion: Int) -> String {
        if let raw = registryProperty(service, key: btFirmwareRevisionKey) {
            if let str = raw as? String {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let num = raw as? NSNumber, num.intValue > 0 {
                let v = num.intValue
                return String(format: "%X.%02X", v >> 8, v & 0xFF)
            }
        }
        return fallbackVersion > 0 ? String(format: "%X.%02X", fallbackVersion >> 8, fallbackVersion & 0xFF) : "Not reported"
    }

    func apply() {
        guard !isBatchUpdating, !services.isEmpty else { return }
        let acceleration: Double
        let resolution: Double?
        let linearScaling: Bool
        if !customEnabled {
            acceleration = systemTrackingSpeed
            resolution = nil
            linearScaling = systemLinearScaling
        } else if accelerationOff {
            acceleration = multiplier
            resolution = 400
            linearScaling = true
        } else {
            acceleration = speed * 3
            resolution = 400 / multiplier
            linearScaling = false
        }
        // Both values are 16.16 fixed point. Each link names the acceleration key it reads
        // (Bluetooth and USB mice use HIDMouseAcceleration), so write that one as well as the generic key.
        let accel = NSNumber(value: Int((acceleration * 65536).rounded()))
        let fixedRes = resolution.map { NSNumber(value: Int(($0 * 65536).rounded())) }
        let linear = NSNumber(value: linearScaling ? 1 : 0)
        var anySucceeded = false
        for (index, service) in services.enumerated() {
            let res: NSNumber
            if let fixedRes {
                res = fixedRes
            } else if orderedServiceIDs.indices.contains(index),
                      let captured = initialResolutions[orderedServiceIDs[index]] {
                res = captured
            } else {
                res = NSNumber(value: 400 * 65536)
            }
            let key = (HIDServiceCopy(service, "HIDPointerAccelerationType" as CFString)?.takeRetainedValue() as? String) ?? "HIDMouseAcceleration"
            // Set resolution before acceleration so IOHIDPointerScrollFilter rebuilds its scaling
            // curve using the new resolution when the acceleration property is committed.
            let r = HIDServiceSet(service, "HIDPointerResolution" as CFString, res)
            let linearApplied = HIDServiceSet(service, "HIDUseLinearScalingMouseAcceleration" as CFString, linear)
            let a1 = HIDServiceSet(service, key as CFString, accel)
            let a2 = (key == "HIDPointerAcceleration") ? false : HIDServiceSet(service, "HIDPointerAcceleration" as CFString, accel)
            if (a1 || a2) && r && (linearApplied || !(customEnabled && accelerationOff)) {
                anySucceeded = true
            }
        }
        lastApplyFailed = !anySucceeded
    }
}
