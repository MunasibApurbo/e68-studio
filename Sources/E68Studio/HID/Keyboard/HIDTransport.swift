import Foundation
import IOKit
import IOKit.hid

struct DeviceInfo: Equatable {
    var product: String
    var manufacturer: String
    var vendorID: Int
    var productID: Int
    var versionBCD: Int
    var transport: String

    /// USB `bcdDevice`, e.g. 0x0102 → "1.02".
    var firmware: String {
        String(format: "%x.%02x", (versionBCD >> 8) & 0xff, versionBCD & 0xff)
    }

    var usbID: String {
        String(format: "%04X:%04X", vendorID, productID)
    }

    var link: String {
        productID == HIDTransport.donglePID ? "2.4 GHz receiver" : "USB cable"
    }
}

enum HIDError: LocalizedError {
    case notConnected
    case sendFailed(IOReturn)
    case timeout
    case verifyFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "The keyboard is not connected."
        case .sendFailed(let code): return String(format: "The keyboard rejected the request (0x%08X).", UInt32(bitPattern: code))
        case .timeout: return "The keyboard did not answer in time."
        case .verifyFailed(let what): return "The keyboard did not keep the change (\(what))."
        }
    }
}

/// Talks to the keyboard's raw-HID configuration interface (usage page 0xFF60, usage 0x61).
/// Only that vendor interface is opened; the typing interface is never touched,
/// so macOS does not ask for Input Monitoring permission.
final class HIDTransport {
    static let vendorID = 0x320F
    static let wiredPID = 0x5055
    static let donglePID = 0x5088
    static let usagePage = 0xFF60
    static let usage = 0x61
    static let packetSize = 32

    var onConnect: ((DeviceInfo) -> Void)?
    var onDisconnect: (() -> Void)?

    private var manager: IOHIDManager?
    private var attachedDevices: [IOHIDDevice] = []
    private var device: IOHIDDevice?
    private let lock = NSCondition()
    private var inbox: [UInt8]?
    private let io = DispatchQueue(label: "e68.hid.io", qos: .userInitiated)
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let thread = Thread { [weak self] in
            guard let self else { return }
            let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matches: [[String: Any]] = [Self.wiredPID, Self.donglePID].map {
                [
                    kIOHIDVendorIDKey: Self.vendorID,
                    kIOHIDProductIDKey: $0,
                    kIOHIDDeviceUsagePageKey: Self.usagePage,
                    kIOHIDDeviceUsageKey: Self.usage,
                ]
            }
            IOHIDManagerSetDeviceMatchingMultiple(m, matches as CFArray)
            let ctx = Unmanaged.passUnretained(self).toOpaque()

            IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, dev in
                guard let ctx else { return }
                Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue().attached(dev)
            }, ctx)

            IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, dev in
                guard let ctx else { return }
                Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue().detached(dev)
            }, ctx)

            IOHIDManagerRegisterInputReportCallback(m, { ctx, _, sender, _, _, report, length in
                guard let ctx else { return }
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue().received(bytes, from: sender)
            }, ctx)

            IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = m
            CFRunLoopRun()
        }
        thread.name = "e68.hid.runloop"
        thread.start()
    }

    // MARK: Device lifecycle (run-loop thread)

    private static func priority(of dev: IOHIDDevice) -> Int {
        let pid = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
        if pid == Self.wiredPID { return 2 }
        if pid == Self.donglePID { return 1 }
        return 0
    }

    private static func deviceInfo(for dev: IOHIDDevice) -> DeviceInfo {
        func string(_ key: String) -> String { IOHIDDeviceGetProperty(dev, key as CFString) as? String ?? "" }
        func int(_ key: String) -> Int { IOHIDDeviceGetProperty(dev, key as CFString) as? Int ?? 0 }
        return DeviceInfo(
            product: string(kIOHIDProductKey),
            manufacturer: string(kIOHIDManufacturerKey),
            vendorID: int(kIOHIDVendorIDKey),
            productID: int(kIOHIDProductIDKey),
            versionBCD: int(kIOHIDVersionNumberKey),
            transport: string(kIOHIDTransportKey)
        )
    }

    private func attached(_ dev: IOHIDDevice) {
        lock.lock()
        if !attachedDevices.contains(where: { $0 === dev }) {
            attachedDevices.append(dev)
        }
        let shouldActivate: Bool
        if let current = device {
            shouldActivate = Self.priority(of: dev) > Self.priority(of: current)
        } else {
            shouldActivate = true
        }
        if shouldActivate {
            device = dev
            inbox = nil
            lock.broadcast()
        }
        lock.unlock()
        guard shouldActivate else { return }

        let info = Self.deviceInfo(for: dev)
        DispatchQueue.main.async { self.onConnect?(info) }
    }

    private func detached(_ dev: IOHIDDevice) {
        lock.lock()
        attachedDevices.removeAll { $0 === dev }
        let wasOurs = device === dev
        var replacement: IOHIDDevice?
        if wasOurs {
            replacement = attachedDevices.max(by: { Self.priority(of: $0) < Self.priority(of: $1) })
            device = replacement
            inbox = nil
            lock.broadcast()
        }
        lock.unlock()
        guard wasOurs else { return }
        if let replacement {
            let info = Self.deviceInfo(for: replacement)
            DispatchQueue.main.async { self.onConnect?(info) }
        } else {
            DispatchQueue.main.async { self.onDisconnect?() }
        }
    }

    private func received(_ bytes: [UInt8], from sender: UnsafeMutableRawPointer?) {
        lock.lock()
        if let sender, let active = device, Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue() !== active {
            lock.unlock()
            return
        }
        inbox = bytes
        lock.broadcast()
        lock.unlock()
    }

    // MARK: Requests

    /// Runs blocking HID work on the serial I/O queue.
    func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            io.async { continuation.resume(with: Result { try work() }) }
        }
    }

    /// Runs a quick fire-and-forget HID restore synchronously with a tight deadline (used on app quit).
    func runSynchronously(_ work: @escaping @Sendable () throws -> Void, timeout: TimeInterval = 0.4) {
        let sem = DispatchSemaphore(value: 0)
        io.async {
            _ = try? work()
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)
    }

    /// Sends one 32-byte command and waits for the reply that echoes its command byte.
    /// Every command this app sends is idempotent, so a lost reply is simply retried.
    func request(_ payload: [UInt8], timeout: TimeInterval = 0.4, attempts: Int = 3) throws -> [UInt8] {
        var lastError: Error = HIDError.timeout
        for _ in 0..<attempts {
            do {
                return try exchange(payload, timeout: timeout)
            } catch HIDError.notConnected {
                throw HIDError.notConnected
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func exchange(_ payload: [UInt8], timeout: TimeInterval) throws -> [UInt8] {
        precondition(!payload.isEmpty && payload.count <= Self.packetSize)
        lock.lock()
        guard let dev = device else {
            lock.unlock()
            throw HIDError.notConnected
        }
        inbox = nil
        lock.unlock()

        var packet = [UInt8](repeating: 0, count: Self.packetSize)
        packet.replaceSubrange(0..<payload.count, with: payload)
        let status = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, packet, packet.count)
        guard status == kIOReturnSuccess else { throw HIDError.sendFailed(status) }

        let deadline = Date().addingTimeInterval(timeout)
        lock.lock()
        defer { lock.unlock() }
        while true {
            if let reply = inbox {
                inbox = nil
                if Self.matchesReply(reply, to: payload) { return reply }
                continue
            }
            if device == nil { throw HIDError.notConnected }
            if !lock.wait(until: deadline) { throw HIDError.timeout }
        }
    }

    private static func matchesReply(_ reply: [UInt8], to payload: [UInt8]) -> Bool {
        guard reply.count >= Self.packetSize, reply.first == payload.first else { return false }
        let cmd = payload[0]
        if (cmd == 0x02 || cmd == 0x07 || cmd == 0x08 || cmd == 0x0E || cmd == 0x12), payload.count >= 2 {
            guard reply[1] == payload[1] else { return false }
            if (cmd == 0x0E || cmd == 0x12), payload.count >= 3 {
                guard reply[2] == payload[2] else { return false }
            }
        }
        return true
    }
}
