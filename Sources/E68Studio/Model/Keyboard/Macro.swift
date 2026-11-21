import Foundation

struct MacroStep: Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case text, tap, down, up, delay

        var title: String {
            switch self {
            case .text: return "Type text"
            case .tap: return "Tap key"
            case .down: return "Hold key down"
            case .up: return "Release key"
            case .delay: return "Wait"
            }
        }

        var symbol: String {
            switch self {
            case .text: return "character.cursor.ibeam"
            case .tap: return "arrow.down.to.line.compact"
            case .down: return "arrow.down"
            case .up: return "arrow.up"
            case .delay: return "clock"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var text: String = ""
    var key: UInt8 = 0x04
    /// Pause length for `.delay`, in milliseconds.
    var milliseconds: Int = 100
}

/// Macro encoding, as verified on the keyboard: plain ASCII is typed as text, and the
/// byte 1 introduces an action — 1 tap, 2 press, 3 release (each followed by a keycode),
/// or 4 for a pause written as decimal milliseconds ending in "|". Each macro ends with 0.
/// (The firmware reports VIA protocol 9 but ignores that version's shorter action form.)
enum MacroCodec {
    private static let prefix: UInt8 = 1
    private static let tap: UInt8 = 1, down: UInt8 = 2, up: UInt8 = 3, delay: UInt8 = 4
    private static let delayEnd: UInt8 = 0x7C
    static let maxDelay = 60_000

    /// Characters the firmware can type from a text step.
    static func isTypeable(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 0x20 && scalar.value <= 0x7E
    }

    static func sanitize(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { isTypeable($0) || $0 == "\n" || $0 == "\t" }))
    }

    static func encode(_ steps: [MacroStep]) -> [UInt8] {
        var out = [UInt8]()
        for step in steps {
            switch step.kind {
            case .text:
                for scalar in step.text.unicodeScalars {
                    if scalar == "\n" {
                        out += [prefix, tap, 0x28]
                    } else if scalar == "\t" {
                        out += [prefix, tap, 0x2B]
                    } else if isTypeable(scalar) {
                        out.append(UInt8(scalar.value))
                    }
                }
            case .tap:
                if step.key != 0 { out += [prefix, tap, step.key] }
            case .down:
                if step.key != 0 { out += [prefix, down, step.key] }
            case .up:
                if step.key != 0 { out += [prefix, up, step.key] }
            case .delay:
                let ms = max(1, min(step.milliseconds, maxDelay))
                out += [prefix, delay] + Array(String(ms).utf8) + [delayEnd]
            }
        }
        return out
    }

    static func decode(_ bytes: [UInt8]) -> [MacroStep] {
        var steps = [MacroStep]()
        var text = ""
        func flush() {
            if !text.isEmpty {
                steps.append(MacroStep(kind: .text, text: text))
                text = ""
            }
        }
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == prefix, i + 1 < bytes.count {
                let action = bytes[i + 1]
                if action == tap || action == down || action == up, i + 2 < bytes.count {
                    flush()
                    let kind: MacroStep.Kind = action == tap ? .tap : (action == down ? .down : .up)
                    steps.append(MacroStep(kind: kind, key: bytes[i + 2]))
                    i += 3
                    continue
                }
                if action == delay {
                    var j = i + 2
                    var digits = ""
                    while j < bytes.count, bytes[j] >= 0x30, bytes[j] <= 0x39 {
                        digits.unicodeScalars.append(UnicodeScalar(bytes[j]))
                        j += 1
                    }
                    if j < bytes.count, bytes[j] == delayEnd, let ms = Int(digits) {
                        flush()
                        steps.append(MacroStep(kind: .delay, milliseconds: max(1, min(ms, maxDelay))))
                        i = j + 1
                        continue
                    }
                    i = max(i + 2, j)
                    continue
                }
                i += 1
            } else {
                if b >= 0x20, b <= 0x7E { text.unicodeScalars.append(UnicodeScalar(b)) }
                i += 1
            }
        }
        flush()
        return steps
    }

    /// All slots joined into the keyboard's macro buffer image (each slot zero-terminated).
    static func image(_ slots: [[MacroStep]]) -> [UInt8] {
        slots.flatMap { encode($0) + [0] }
    }

    static func split(_ buffer: [UInt8], count: Int) -> [[MacroStep]] {
        var slots = [[MacroStep]]()
        var current = [UInt8]()
        for byte in buffer {
            if slots.count == count { break }
            if byte == 0 {
                slots.append(decode(current))
                current = []
            } else {
                current.append(byte)
            }
        }
        while slots.count < count { slots.append([]) }
        return slots
    }

    /// Collapses an immediate press-and-release of the same key into a single tap.
    static func simplify(_ steps: [MacroStep]) -> [MacroStep] {
        var out = [MacroStep]()
        var i = 0
        while i < steps.count {
            let s = steps[i]
            if s.kind == .down, i + 1 < steps.count, steps[i + 1].kind == .up, steps[i + 1].key == s.key {
                out.append(MacroStep(kind: .tap, key: s.key))
                i += 2
            } else {
                out.append(s)
                i += 1
            }
        }
        return out
    }

    static func summary(_ steps: [MacroStep]) -> String {
        if steps.isEmpty { return "Empty" }
        func short(_ key: UInt8) -> String {
            let def = Keycodes.def(for: UInt16(key))
            return def.legend.symbol == nil ? def.legend.main : def.name
        }
        return steps.map { step -> String in
            switch step.kind {
            case .text: return "“\(step.text)”"
            case .tap: return short(step.key)
            case .down: return "↓\(short(step.key))"
            case .up: return "↑\(short(step.key))"
            case .delay: return "wait \(step.milliseconds) ms"
            }
        }.joined(separator: " ")
    }
}

/// macOS virtual key codes → USB HID usages, for recording macros and the key-test fallback.
enum MacKeyMap {
    static let usage: [UInt16: UInt8] = [
        0x00: 0x04, 0x01: 0x16, 0x02: 0x07, 0x03: 0x09, 0x04: 0x0B, 0x05: 0x0A, 0x06: 0x1D, 0x07: 0x1B,
        0x08: 0x06, 0x09: 0x19, 0x0A: 0x64, 0x0B: 0x05, 0x0C: 0x14, 0x0D: 0x1A, 0x0E: 0x08, 0x0F: 0x15,
        0x10: 0x1C, 0x11: 0x17, 0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x16: 0x23, 0x17: 0x22,
        0x18: 0x2E, 0x19: 0x26, 0x1A: 0x24, 0x1B: 0x2D, 0x1C: 0x25, 0x1D: 0x27, 0x1E: 0x30, 0x1F: 0x12,
        0x20: 0x18, 0x21: 0x2F, 0x22: 0x0C, 0x23: 0x13, 0x24: 0x28, 0x25: 0x0F, 0x26: 0x0D, 0x27: 0x34,
        0x28: 0x0E, 0x29: 0x33, 0x2A: 0x31, 0x2B: 0x36, 0x2C: 0x38, 0x2D: 0x11, 0x2E: 0x10, 0x2F: 0x37,
        0x30: 0x2B, 0x31: 0x2C, 0x32: 0x35, 0x33: 0x2A, 0x35: 0x29, 0x36: 0xE7, 0x37: 0xE3, 0x38: 0xE1,
        0x39: 0x39, 0x3A: 0xE2, 0x3B: 0xE0, 0x3C: 0xE5, 0x3D: 0xE6, 0x3E: 0xE4,
        0x40: 0x6C, 0x41: 0x63, 0x43: 0x55, 0x45: 0x57, 0x47: 0x53, 0x4B: 0x54, 0x4C: 0x58, 0x4E: 0x56,
        0x4F: 0x6D, 0x50: 0x6E, 0x51: 0x67, 0x52: 0x62, 0x53: 0x59, 0x54: 0x5A, 0x55: 0x5B, 0x56: 0x5C,
        0x57: 0x5D, 0x58: 0x5E, 0x59: 0x5F, 0x5A: 0x6F, 0x5B: 0x60, 0x5C: 0x61, 0x5E: 0x87,
        0x60: 0x3E, 0x61: 0x3F, 0x62: 0x40, 0x63: 0x3C, 0x64: 0x41, 0x65: 0x42, 0x66: 0x91, 0x67: 0x44, 0x68: 0x90, 0x69: 0x68,
        0x6A: 0x6B, 0x6B: 0x69, 0x6D: 0x43, 0x6E: 0x65, 0x6F: 0x45, 0x71: 0x6A, 0x72: 0x49, 0x73: 0x4A, 0x74: 0x4B,
        0x75: 0x4C, 0x76: 0x3D, 0x77: 0x4D, 0x78: 0x3B, 0x79: 0x4E, 0x7A: 0x3A, 0x7B: 0x50, 0x7C: 0x4F,
        0x7D: 0x51, 0x7E: 0x52,
    ]
}
