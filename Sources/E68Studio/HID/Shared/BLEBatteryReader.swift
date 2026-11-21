import Foundation
import CoreBluetooth

/// Reads and subscribes to the standard BLE Battery Service (`0x180F` / `0x2A19`)
/// for a connected keyboard or mouse peripheral.
final class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryLevelUUID = CBUUID(string: "2A19")

    private let peripheralUUID: UUID?
    private let productMatch: @Sendable (String) -> Bool
    private let fallbackMatch: (@Sendable (String) -> Bool)?
    private let onUpdate: @Sendable (Int?) -> Void
    private let cbQueue: DispatchQueue

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var batteryCharacteristic: CBCharacteristic?
    private var pollTimer: DispatchSourceTimer?
    private var stopped = false

    init(
        peripheralUUID: String,
        queueLabel: String,
        productMatch: @escaping @Sendable (String) -> Bool,
        fallbackMatch: (@Sendable (String) -> Bool)? = nil,
        onUpdate: @escaping @Sendable (Int?) -> Void
    ) {
        self.peripheralUUID = UUID(uuidString: peripheralUUID)
        self.cbQueue = DispatchQueue(label: queueLabel, qos: .utility)
        self.productMatch = productMatch
        self.fallbackMatch = fallbackMatch
        self.onUpdate = onUpdate
    }

    deinit {
        pollTimer?.cancel()
    }

    func start() {
        cbQueue.async { [weak self] in
            guard let self, !self.stopped, self.central == nil else { return }
            self.central = CBCentralManager(
                delegate: self,
                queue: self.cbQueue,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        }
    }

    func refresh() {
        cbQueue.async { [weak self] in
            guard let self, !self.stopped else { return }
            if let peripheral = self.peripheral, peripheral.state == .connected {
                if let char = self.batteryCharacteristic, char.properties.contains(.read) {
                    peripheral.readValue(for: char)
                } else {
                    peripheral.discoverServices([Self.batteryServiceUUID])
                }
            } else if let central = self.central, central.state == .poweredOn, self.peripheral == nil {
                self.connectTarget(on: central)
            }
        }
    }

    func stop() {
        cbQueue.async {
            self.stopped = true
            self.stopPolling()
            self.batteryCharacteristic = nil
            if let peripheral = self.peripheral {
                peripheral.delegate = nil
                self.central?.cancelPeripheralConnection(peripheral)
            }
            self.peripheral = nil
            self.central?.delegate = nil
            self.central = nil
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !stopped else { return }
        switch central.state {
        case .poweredOn:
            connectTarget(on: central)
        case .unknown, .resetting:
            break
        case .poweredOff, .unauthorized, .unsupported:
            onUpdate(nil)
        @unknown default:
            break
        }
    }

    private func connectTarget(on central: CBCentralManager) {
        var target: CBPeripheral?
        if let peripheralUUID {
            target = central.retrievePeripherals(withIdentifiers: [peripheralUUID]).first
        }
        if target == nil {
            let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryServiceUUID])
            target = connected.first { productMatch($0.name ?? "") }
                ?? fallbackMatch.flatMap { fallback in connected.first { fallback($0.name ?? "") } }
        }
        guard let target else { return }
        peripheral = target
        target.delegate = self
        central.connect(target, options: nil)
    }

    private func startPolling() {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: cbQueue)
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            guard let self, !self.stopped,
                  let peripheral = self.peripheral,
                  peripheral.state == .connected,
                  let char = self.batteryCharacteristic,
                  char.properties.contains(.read) else { return }
            peripheral.readValue(for: char)
        }
        pollTimer = timer
        timer.resume()
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !stopped else { return }
        peripheral.discoverServices([Self.batteryServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard !stopped, peripheral.identifier == self.peripheral?.identifier else { return }
        stopPolling()
        batteryCharacteristic = nil
        onUpdate(nil)
        central.connect(peripheral, options: nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard !stopped, error == nil else { return }
        for service in peripheral.services ?? [] where service.uuid == Self.batteryServiceUUID {
            peripheral.discoverCharacteristics([Self.batteryLevelUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard !stopped, error == nil else { return }
        for char in service.characteristics ?? [] where char.uuid == Self.batteryLevelUUID {
            batteryCharacteristic = char
            if char.properties.contains(.read) {
                peripheral.readValue(for: char)
                startPolling()
            }
            if char.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !stopped, error == nil, characteristic.uuid == Self.batteryLevelUUID,
              let byte = characteristic.value?.first else { return }
        onUpdate(min(100, Int(byte)))
    }
}
