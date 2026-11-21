import Foundation

/// What is printed on a keycap: a main legend, an optional small line above it,
/// and optionally an SF Symbol that replaces the main text.
struct Legend: Hashable {
    var main: String
    var top: String? = nil
    var symbol: String? = nil
}

struct KeyDef: Identifiable, Hashable {
    let code: UInt16
    let legend: Legend
    let name: String
    var id: UInt16 { code }
}

struct KeyGroup: Identifiable {
    let title: String
    let keys: [KeyDef]
    var id: String { title }
}

struct KeyCategory: Identifiable {
    let id: String
    let title: String
    var note: String? = nil
    let groups: [KeyGroup]
}

/// Keycode values as this firmware understands them. It reports VIA protocol 9, which
/// uses the pre-2022 QMK numbering (MO = 0x51xx, lighting = 0x5CC2…, custom = 0x5F80…),
/// confirmed against the factory keymap.
enum Keycodes {
    static let none: UInt16 = 0x0000
    static let transparent: UInt16 = 0x0001
    static let macroBase: UInt16 = 0x5F12
    static let customBase: UInt16 = 0x5F80

    private static func k(_ code: UInt16, _ main: String, _ name: String, top: String? = nil, symbol: String? = nil) -> KeyDef {
        KeyDef(code: code, legend: Legend(main: main, top: top, symbol: symbol), name: name)
    }

    // MARK: Basic

    static let letters: [KeyDef] = (0..<26).map { i in
        let ch = String(UnicodeScalar(UInt8(65 + i)))
        return k(UInt16(0x04 + i), ch, ch)
    }

    static let digits: [KeyDef] = {
        let shifted = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"]
        return (0..<10).map { i in
            let d = String((i + 1) % 10)
            return k(UInt16(0x1E + i), d, "\(d) and \(shifted[i])", top: shifted[i])
        }
    }()

    static let punctuation: [KeyDef] = [
        k(0x2D, "-", "Minus and underscore", top: "_"),
        k(0x2E, "=", "Equals and plus", top: "+"),
        k(0x2F, "[", "Left bracket and brace", top: "{"),
        k(0x30, "]", "Right bracket and brace", top: "}"),
        k(0x31, "\\", "Backslash and pipe", top: "|"),
        k(0x33, ";", "Semicolon and colon", top: ":"),
        k(0x34, "'", "Quote and double quote", top: "\""),
        k(0x35, "`", "Grave and tilde", top: "~"),
        k(0x36, ",", "Comma and less-than", top: "<"),
        k(0x37, ".", "Period and greater-than", top: ">"),
        k(0x38, "/", "Slash and question mark", top: "?"),
        k(0x32, "#", "Non-US hash and tilde (ISO)", top: "~"),
        k(0x64, "\\", "Non-US backslash (ISO)", top: "|"),
    ]

    static let editing: [KeyDef] = [
        k(0x29, "Esc", "Escape"),
        k(0x2B, "Tab", "Tab"),
        k(0x39, "Caps", "Caps Lock"),
        k(0x2A, "Backspace", "Backspace"),
        k(0x28, "Enter", "Return / Enter"),
        k(0x2C, "Space", "Space"),
    ]

    static let special: [KeyDef] = [
        k(none, "None", "None: the key does nothing"),
        k(transparent, "▽", "Transparent: use the key from the layer below"),
    ]

    // MARK: Function and navigation

    static let functionRow: [KeyDef] = (1...12).map { k(UInt16(0x39 + $0), "F\($0)", "F\($0)") }
    static let extendedFunction: [KeyDef] = (13...24).map { k(UInt16(0x68 + $0 - 13), "F\($0)", "F\($0)") }

    static let navigation: [KeyDef] = [
        k(0x49, "Ins", "Insert"),
        k(0x4C, "Del", "Forward Delete"),
        k(0x4A, "Home", "Home"),
        k(0x4D, "End", "End"),
        k(0x4B, "PgUp", "Page Up"),
        k(0x4E, "PgDn", "Page Down"),
        k(0x52, "↑", "Up Arrow"),
        k(0x51, "↓", "Down Arrow"),
        k(0x50, "←", "Left Arrow"),
        k(0x4F, "→", "Right Arrow"),
    ]

    static let systemKeys: [KeyDef] = [
        k(0x46, "PrtSc", "Print Screen"),
        k(0x47, "ScrLk", "Scroll Lock"),
        k(0x48, "Pause", "Pause / Break"),
        k(0x65, "Menu", "Application (context menu)"),
        k(0x87, "Ro", "International 1 (JIS Ro)"),
        k(0x90, "Lang1", "Language 1 (Kana / Hangul)"),
        k(0x91, "Lang2", "Language 2 (Eisu / Hanja)"),
    ]

    // MARK: Modifiers

    static let leftModifiers: [KeyDef] = [
        k(0xE0, "Ctrl", "Left Control", top: "⌃"),
        k(0xE1, "Shift", "Left Shift", top: "⇧"),
        k(0xE2, "Opt", "Left Option (Alt on Windows)", top: "⌥"),
        k(0xE3, "Cmd", "Left Command (Win on Windows)", top: "⌘"),
    ]

    static let rightModifiers: [KeyDef] = [
        k(0xE4, "Ctrl", "Right Control", top: "⌃"),
        k(0xE5, "Shift", "Right Shift", top: "⇧"),
        k(0xE6, "Opt", "Right Option (AltGr on Windows)", top: "⌥"),
        k(0xE7, "Cmd", "Right Command (Win on Windows)", top: "⌘"),
    ]

    // MARK: Media

    static let media: [KeyDef] = [
        k(0xA8, "Mute", "Mute", symbol: "speaker.slash.fill"),
        k(0xAA, "Vol −", "Volume Down", symbol: "speaker.wave.1.fill"),
        k(0xA9, "Vol +", "Volume Up", symbol: "speaker.wave.3.fill"),
        k(0xAC, "Prev", "Previous Track", symbol: "backward.end.fill"),
        k(0xAE, "Play", "Play / Pause", symbol: "playpause.fill"),
        k(0xAB, "Next", "Next Track", symbol: "forward.end.fill"),
        k(0xAD, "Stop", "Stop", symbol: "stop.fill"),
        k(0xBC, "Rewind", "Rewind", symbol: "backward.fill"),
        k(0xBB, "Fwd", "Fast Forward", symbol: "forward.fill"),
        k(0xB0, "Eject", "Eject", symbol: "eject.fill"),
        k(0xBE, "Dim", "Screen Brightness Down", symbol: "sun.min.fill"),
        k(0xBD, "Bright", "Screen Brightness Up", symbol: "sun.max.fill"),
    ]

    static let apps: [KeyDef] = [
        k(0xB2, "Calc", "Calculator"),
        k(0xB1, "Mail", "Mail"),
        k(0xB3, "Files", "My Computer / Files"),
        k(0xAF, "Player", "Media Player"),
        k(0xB5, "Home", "Browser Home", top: "Web"),
        k(0xB6, "Back", "Browser Back", top: "Web"),
        k(0xB7, "Fwd", "Browser Forward", top: "Web"),
        k(0xB4, "Search", "Browser Search", top: "Web"),
        k(0xB9, "Reload", "Browser Refresh", top: "Web"),
        k(0xA5, "Power", "System Power"),
        k(0xA6, "Sleep", "System Sleep"),
        k(0xA7, "Wake", "System Wake"),
    ]

    // MARK: Numpad

    static let numpad: [KeyDef] = {
        var keys = (1...9).map { k(UInt16(0x58 + $0), "\($0)", "Keypad \($0)", top: "Pad") }
        keys += [
            k(0x62, "0", "Keypad 0", top: "Pad"),
            k(0x63, ".", "Keypad Decimal", top: "Pad"),
            k(0x54, "/", "Keypad Divide", top: "Pad"),
            k(0x55, "*", "Keypad Multiply", top: "Pad"),
            k(0x56, "−", "Keypad Minus", top: "Pad"),
            k(0x57, "+", "Keypad Plus", top: "Pad"),
            k(0x58, "Enter", "Keypad Enter", top: "Pad"),
            k(0x67, "=", "Keypad Equals", top: "Pad"),
            k(0x53, "Num", "Num Lock (Clear on Mac)"),
        ]
        return keys
    }()

    // MARK: Mouse

    static let mouse: [KeyDef] = [
        k(0xF4, "Left", "Mouse Left Button", top: "Click"),
        k(0xF5, "Right", "Mouse Right Button", top: "Click"),
        k(0xF6, "Middle", "Mouse Middle Button", top: "Click"),
        k(0xF7, "Btn 4", "Mouse Button 4", top: "Click"),
        k(0xF8, "Btn 5", "Mouse Button 5", top: "Click"),
        k(0xF0, "↑", "Move Pointer Up", top: "Ptr"),
        k(0xF1, "↓", "Move Pointer Down", top: "Ptr"),
        k(0xF2, "←", "Move Pointer Left", top: "Ptr"),
        k(0xF3, "→", "Move Pointer Right", top: "Ptr"),
        k(0xF9, "↑", "Scroll Up", top: "Scroll"),
        k(0xFA, "↓", "Scroll Down", top: "Scroll"),
        k(0xFB, "←", "Scroll Left", top: "Scroll"),
        k(0xFC, "→", "Scroll Right", top: "Scroll"),
    ]

    // MARK: Layers

    static func layerKeys(count: Int) -> [KeyGroup] {
        func make(_ base: UInt16, _ short: String, _ top: String, _ what: String) -> [KeyDef] {
            (0..<count).map { n in
                let main = (base == 0x5100 && n == 1) ? "Fn" : "\(short) \(n)"
                return k(base + UInt16(n), main, "\(what) \(LayerInfo.title(n)) (layer \(n))", top: top)
            }
        }
        return [
            KeyGroup(title: "Hold", keys: make(0x5100, "MO", "Hold", "While held, switch to")),
            KeyGroup(title: "Toggle", keys: make(0x5300, "TG", "Toggle", "Toggle")),
            KeyGroup(title: "Switch to", keys: make(0x5010, "TO", "Go to", "Switch to")),
            KeyGroup(title: "Set as base", keys: make(0x5200, "DF", "Base", "Make the base layer")),
            KeyGroup(title: "Next key only", keys: make(0x5400, "OSL", "Once", "For the next key only, use")),
        ]
    }

    // MARK: Lighting

    static let lighting: [KeyDef] = [
        k(0x5CC2, "On/Off", "Backlight on / off", top: "RGB"),
        k(0x5CC3, "Next", "Next lighting effect", top: "Effect"),
        k(0x5CC4, "Prev", "Previous lighting effect", top: "Effect"),
        k(0x5CC9, "Bright +", "Backlight brighter", top: "RGB"),
        k(0x5CCA, "Bright −", "Backlight dimmer", top: "RGB"),
        k(0x5CCB, "Speed +", "Effect faster", top: "RGB"),
        k(0x5CCC, "Speed −", "Effect slower", top: "RGB"),
        k(0x5CC5, "Hue +", "Next backlight colour", top: "RGB"),
        k(0x5CC6, "Hue −", "Previous backlight colour", top: "RGB"),
        k(0x5CC7, "Sat +", "More colour saturation", top: "RGB"),
        k(0x5CC8, "Sat −", "Less colour saturation", top: "RGB"),
    ]

    // MARK: Device

    static let wireless: [KeyDef] = [
        k(customBase + 1, "1", "Bluetooth channel 1", top: "BT"),
        k(customBase + 2, "2", "Bluetooth channel 2", top: "BT"),
        k(customBase + 3, "3", "Bluetooth channel 3", top: "BT"),
        k(customBase + 0, "2.4G", "2.4 GHz receiver", top: "Radio"),
    ]

    static let deviceKeys: [KeyDef] = [
        k(customBase + 6, "Battery", "Show battery level on the LEDs", symbol: "battery.75percent"),
        k(customBase + 4, "Win Lock", "Lock the Win / Command key", symbol: "lock.fill"),
        k(customBase + 5, "Delay", "Cycle key scan delay (debounce)", top: "Scan"),
        k(0x5C00, "Reset", "Reset. Factory-mapped to Fn + right Command; its exact behaviour is defined by the firmware."),
    ]

    static func macroKey(slot n: Int, names: [String]) -> KeyDef {
        let custom = n < names.count ? names[n].trimmingCharacters(in: .whitespaces) : ""
        return k(macroBase + UInt16(n), "M\(n)", custom.isEmpty ? "Macro \(n)" : "Macro \(n): \(custom)", top: "Macro")
    }

    static func macroKeys(count: Int, names: [String]) -> [KeyDef] {
        (0..<count).map { macroKey(slot: $0, names: names) }
    }

    // MARK: Categories

    static func categories(layerCount: Int, macroCount: Int, macroNames: [String]) -> [KeyCategory] {
        [
            KeyCategory(id: "basic", title: "Basic", groups: [
                KeyGroup(title: "Letters", keys: letters),
                KeyGroup(title: "Numbers", keys: digits),
                KeyGroup(title: "Punctuation", keys: punctuation),
                KeyGroup(title: "Editing", keys: editing),
                KeyGroup(title: "Empty", keys: special),
            ]),
            KeyCategory(id: "function", title: "Function", groups: [
                KeyGroup(title: "Function row", keys: functionRow),
                KeyGroup(title: "Navigation", keys: navigation),
                KeyGroup(title: "System", keys: systemKeys),
                KeyGroup(title: "F13 to F24", keys: extendedFunction),
            ]),
            KeyCategory(id: "modifiers", title: "Modifiers", groups: [
                KeyGroup(title: "Left side", keys: leftModifiers),
                KeyGroup(title: "Right side", keys: rightModifiers),
            ]),
            KeyCategory(id: "media", title: "Media", groups: [
                KeyGroup(title: "Playback and display", keys: media),
                KeyGroup(title: "Apps and system", keys: apps),
            ]),
            KeyCategory(id: "numpad", title: "Numpad", groups: [
                KeyGroup(title: "Keypad", keys: numpad),
            ]),
            KeyCategory(id: "mouse", title: "Mouse",
                        note: "The keyboard exposes a mouse interface, but the factory keymap does not use these keys. Try one before relying on it.",
                        groups: [KeyGroup(title: "Buttons, pointer and scroll", keys: mouse)]),
            KeyCategory(id: "layers", title: "Layers",
                        note: "The factory keymap only uses Fn (hold layer 1). The other layer actions follow the QMK convention the firmware imitates; test them after assigning.",
                        groups: layerKeys(count: layerCount)),
            KeyCategory(id: "macros", title: "Macros",
                        note: "Record or write macros in the Macros section, then place them on keys here.",
                        groups: [KeyGroup(title: "Macro slots", keys: macroKeys(count: macroCount, names: macroNames))]),
            KeyCategory(id: "lighting", title: "Lighting", groups: [
                KeyGroup(title: "Backlight controls", keys: lighting),
            ]),
            KeyCategory(id: "device", title: "Device", groups: [
                KeyGroup(title: "Connection", keys: wireless),
                KeyGroup(title: "Keyboard functions", keys: deviceKeys),
            ]),
        ]
    }

    // MARK: Lookup

    private static let known: [UInt16: KeyDef] = {
        let all = letters + digits + punctuation + editing + special + functionRow + extendedFunction
            + navigation + systemKeys + leftModifiers + rightModifiers + media + apps + numpad + mouse
            + lighting + wireless + deviceKeys + layerKeys(count: 16).flatMap(\.keys)
        return Dictionary(all.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// 8-bit keys that can appear inside a macro.
    static let macroCandidates: [KeyGroup] = [
        KeyGroup(title: "Modifiers", keys: leftModifiers + rightModifiers),
        KeyGroup(title: "Editing", keys: editing),
        KeyGroup(title: "Navigation", keys: navigation),
        KeyGroup(title: "Letters", keys: letters),
        KeyGroup(title: "Numbers", keys: digits),
        KeyGroup(title: "Punctuation", keys: punctuation),
        KeyGroup(title: "Function row", keys: functionRow),
        KeyGroup(title: "Media", keys: media),
    ]

    static func hex(_ code: UInt16) -> String {
        String(format: "0x%04X", code)
    }

    static func modifierGlyphs(_ bits: UInt16) -> String {
        var s = ""
        if bits & 0x01 != 0 { s += "⌃" }
        if bits & 0x04 != 0 { s += "⌥" }
        if bits & 0x02 != 0 { s += "⇧" }
        if bits & 0x08 != 0 { s += "⌘" }
        return s
    }

    static func modifierWords(_ bits: UInt16) -> String {
        var parts = [String]()
        if bits & 0x10 != 0 { parts.append("Right") }
        if bits & 0x01 != 0 { parts.append("Control") }
        if bits & 0x04 != 0 { parts.append("Option") }
        if bits & 0x02 != 0 { parts.append("Shift") }
        if bits & 0x08 != 0 { parts.append("Command") }
        return parts.joined(separator: " + ")
    }

    /// Describes any 16-bit keycode, including ones the pickers do not list.
    static func def(for code: UInt16, macroNames: [String] = []) -> KeyDef {
        if code >= macroBase, code < macroBase + 16 {
            return macroKey(slot: Int(code - macroBase), names: macroNames)
        }
        if let hit = known[code] { return hit }
        switch code {
        case 0x0100...0x1FFF:
            let base = def(for: code & 0xff)
            let bits = code >> 8
            return k(code, base.legend.main, "\(modifierWords(bits)) + \(base.name)", top: modifierGlyphs(bits))
        case 0x4000...0x4FFF:
            let base = def(for: code & 0xff)
            let layer = (code >> 8) & 0x0f
            return k(code, base.legend.main, "Tap for \(base.name), hold for layer \(layer)", top: "LT \(layer)")
        case 0x5800...0x581F:
            let layer = code & 0x1f
            return k(code, "TT \(layer)", "Hold for layer \(layer), tap repeatedly to toggle it", top: "Tap")
        case 0x6000...0x7FFF:
            let base = def(for: code & 0xff)
            let bits = (code >> 8) & 0x1f
            return k(code, base.legend.main, "Tap for \(base.name), hold for \(modifierWords(bits))", top: modifierGlyphs(bits) + " hold")
        case customBase...(customBase + 0x7f):
            return k(code, "Fn \(code - customBase)", "Firmware function \(code - customBase) (\(hex(code)))", top: "Device")
        default:
            return k(code, String(format: "%04X", code), "Unlisted keycode \(hex(code))", top: "Code")
        }
    }
}
