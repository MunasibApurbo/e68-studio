import Foundation

/// The subset of the VIA protocol (version 9) that the E-68 PRO firmware implements,
/// including the places where it deviates from stock QMK. Every behaviour noted here was
/// measured on the real keyboard (firmware 1.02).
struct VIA {
    let hid: HIDTransport

    static let rows = 8
    static let cols = 16
    static let cellsPerLayer = rows * cols
    /// Payload bytes that fit in one 32-byte packet after the 4-byte header.
    static let chunk = 28
    private enum Command: UInt8 {
        case protocolVersion = 0x01
        case keyboardValue = 0x02
        case setKeycode = 0x05
        case lightingSet = 0x07
        case lightingGet = 0x08
        case lightingSave = 0x09
        case macroCount = 0x0C
        case macroBufferSize = 0x0D
        case macroGetBuffer = 0x0E
        case macroSetBuffer = 0x0F
        case macroReset = 0x10
        case layerCount = 0x11
        case keymapGetBuffer = 0x12
    }

    // MARK: Identity

    func protocolVersion() throws -> Int {
        let r = try hid.request([Command.protocolVersion.rawValue])
        return Int(r[1]) << 8 | Int(r[2])
    }

    func layerCount() throws -> Int {
        Int(try hid.request([Command.layerCount.rawValue])[1])
    }

    func macroCount() throws -> Int {
        Int(try hid.request([Command.macroCount.rawValue])[1])
    }

    func macroBufferSize() throws -> Int {
        let r = try hid.request([Command.macroBufferSize.rawValue])
        return Int(r[1]) << 8 | Int(r[2])
    }

    // MARK: Keymap

    private func readKeymapBytes(offset: Int, count: Int) throws -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(count)
        var position = offset
        while out.count < count {
            let n = min(Self.chunk, count - out.count)
            let r = try hid.request([Command.keymapGetBuffer.rawValue, UInt8(position >> 8), UInt8(position & 0xff), UInt8(n)])
            out += r[4..<(4 + n)]
            position += n
        }
        return out
    }

    func readKeymap(layers: Int) throws -> [[UInt16]] {
        let bytes = try readKeymapBytes(offset: 0, count: layers * Self.cellsPerLayer * 2)
        return (0..<layers).map { layer in
            (0..<Self.cellsPerLayer).map { cell in
                let i = (layer * Self.cellsPerLayer + cell) * 2
                return UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
            }
        }
    }

    func readKey(layer: Int, index: Int) throws -> UInt16 {
        let b = try readKeymapBytes(offset: (layer * Self.cellsPerLayer + index) * 2, count: 2)
        return UInt16(b[0]) << 8 | UInt16(b[1])
    }

    /// Writes one key and reads it back. The firmware ignores bulk keymap writes (0x13)
    /// and its single-key read (0x04) returns junk, so writes go through 0x05 and
    /// verification goes through the buffer read.
    func setKey(layer: Int, index: Int, code: UInt16) throws {
        let row = UInt8(index / Self.cols), col = UInt8(index % Self.cols)
        _ = try hid.request([Command.setKeycode.rawValue, UInt8(layer), row, col, UInt8(code >> 8), UInt8(code & 0xff)])
        let stored = try readKey(layer: layer, index: index)
        guard stored == code else {
            throw HIDError.verifyFailed(String(format: "layer %d row %d col %d holds 0x%04X", layer, row, col, stored))
        }
    }

    // MARK: Macros

    /// The last few bytes of the buffer cannot be reached with full-size chunks, so they stay unused.
    static func usableMacroBytes(bufferSize: Int) -> Int {
        guard bufferSize > 0 else { return 0 }
        return (bufferSize / chunk) * chunk
    }

    func readMacroBuffer(size: Int) throws -> [UInt8] {
        guard size > 0 else { return [] }
        var out = [UInt8]()
        out.reserveCapacity(size)
        while out.count < size {
            let n = min(Self.chunk, size - out.count)
            let r = try hid.request([Command.macroGetBuffer.rawValue, UInt8(out.count >> 8), UInt8(out.count & 0xff), UInt8(n)])
            out += r[4..<(4 + n)]
        }
        return out
    }

    /// Replaces the whole macro buffer.
    ///
    /// The firmware stages writes in RAM and commits them when the final buffer byte is
    /// written as zero. It also drops the last 14 bytes of any chunk declared as 14–27
    /// bytes long, so every chunk is sent zero-padded at the full 28 bytes.
    func writeMacroBuffer(_ data: [UInt8], bufferSize: Int) throws {
        guard bufferSize > 0 else {
            throw HIDError.verifyFailed("macro buffer size is zero")
        }
        let usable = Self.usableMacroBytes(bufferSize: bufferSize)
        precondition(data.count <= usable)
        let last = bufferSize - 1
        let lastHi = UInt8(last >> 8), lastLo = UInt8(last & 0xff)
        let set = Command.macroSetBuffer.rawValue

        _ = try hid.request([Command.macroReset.rawValue])
        _ = try hid.request([set, lastHi, lastLo, 1, 0xff])
        var failure: Error?
        do {
            var offset = 0
            while offset < data.count {
                var piece = Array(data[offset..<min(offset + Self.chunk, data.count)])
                piece += [UInt8](repeating: 0, count: Self.chunk - piece.count)
                _ = try hid.request([set, UInt8(offset >> 8), UInt8(offset & 0xff), UInt8(Self.chunk)] + piece)
                offset += Self.chunk
            }
        } catch {
            failure = error
        }
        // Always close the transaction, otherwise the buffer keeps reading back as 0xFF.
        if failure != nil {
            _ = try? hid.request([set, lastHi, lastLo, 1, 0x00], attempts: 1)
        } else {
            _ = try hid.request([set, lastHi, lastLo, 1, 0x00])
        }
        if let failure { throw failure }

        Thread.sleep(forTimeInterval: 0.2)
        let stored = try readMacroBuffer(size: bufferSize)
        let expected = data + [UInt8](repeating: 0, count: bufferSize - data.count)
        guard stored == expected else { throw HIDError.verifyFailed("macro memory differs after writing") }
    }

    // MARK: Lighting

    /// Lighting value IDs. FuryCube's published VIA definition addresses lighting as
    /// "channel 3, values 1–4", but firmware 1.02 only acknowledges those without acting.
    /// The values that really drive the LEDs are VIA's older 0x80-series IDs.
    /// Speed (0x82) is the exception: the firmware stores it but the animation ignores it,
    /// and the keyboard's own Fn + ←/→ speed keys do not show up in it. The app never writes it.
    enum LightingValue: UInt8 {
        case brightness = 0x80, effect = 0x81, speed = 0x82, color = 0x83
    }

    struct RawLighting: Equatable {
        var brightness: UInt8
        var effect: UInt8
        var speed: UInt8
        var hue: UInt8
        var saturation: UInt8
    }

    func setLighting(_ value: LightingValue, _ bytes: [UInt8], timeout: TimeInterval = 0.4, attempts: Int = 3) throws {
        _ = try hid.request([Command.lightingSet.rawValue, value.rawValue] + bytes, timeout: timeout, attempts: attempts)
    }

    func readLighting() throws -> RawLighting {
        func get(_ value: LightingValue) throws -> [UInt8] {
            let r = try hid.request([Command.lightingGet.rawValue, value.rawValue])
            return [r[2], r[3]]
        }
        let color = try get(.color)
        return RawLighting(
            brightness: try get(.brightness)[0],
            effect: try get(.effect)[0],
            speed: try get(.speed)[0],
            hue: color[0],
            saturation: color[1]
        )
    }

    /// Asks the keyboard to keep the current lighting across power cycles.
    func saveLighting() throws {
        _ = try hid.request([Command.lightingSave.rawValue])
    }

    // MARK: Live switch state

    /// One bitmask per matrix row; bit `col` is set while that switch is held.
    /// The firmware replies with [0x02, 0x03, offset, row0_hi, row0_lo, row1_hi, ...].
    /// Matrix data begins at index 3 (offset byte is at index 2).
    func matrixState() throws -> [UInt16] {
        let r = try hid.request([Command.keyboardValue.rawValue, 0x03], timeout: 0.15, attempts: 1)
        return (0..<Self.rows).map { row in
            UInt16(r[3 + row * 2]) << 8 | UInt16(r[4 + row * 2])
        }
    }
}
