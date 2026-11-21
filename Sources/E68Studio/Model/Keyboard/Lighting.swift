import SwiftUI

struct LightingEffect: Identifiable, Hashable {
    let id: Int
    let name: String
    /// The firmware's own name for the mode, from FuryCube's VIA definition.
    let firmwareName: String
}

enum LightingCatalog {
    static let effects: [LightingEffect] = [
        .init(id: 0, name: "Off", firmwareName: "OFF_MODE"),
        .init(id: 6, name: "Static", firmwareName: "LIGHT_MODE"),
        .init(id: 5, name: "Breathe", firmwareName: "BREATHE_MODE"),
        .init(id: 1, name: "Wave", firmwareName: "WAVE_MODE"),
        .init(id: 2, name: "Colour Cloud", firmwareName: "COLOUR_CLOUD_MODE"),
        .init(id: 3, name: "Vortex", firmwareName: "VORTEX_MODE"),
        .init(id: 4, name: "Colour Mix", firmwareName: "MIX_COLOUR_MODE"),
        .init(id: 13, name: "Wave Bar", firmwareName: "WAVE_BAR_MODE"),
        .init(id: 12, name: "Traverse", firmwareName: "TRAVERSE_MODE"),
        .init(id: 16, name: "Scan", firmwareName: "SCAN_MODE"),
        .init(id: 10, name: "Starry", firmwareName: "STARRY_MODE"),
        .init(id: 14, name: "Meteor", firmwareName: "METEOR_MODE"),
        .init(id: 15, name: "Rain", firmwareName: "RAIN_MODE"),
        .init(id: 11, name: "Flowers Open", firmwareName: "FLOWERS_OPEN_MODE"),
        .init(id: 7, name: "Slow Fade", firmwareName: "SLOWLY_OFF_MODE"),
        .init(id: 8, name: "Stone", firmwareName: "STONE_MODE"),
        .init(id: 9, name: "Laser", firmwareName: "LASER_MODE"),
        .init(id: 17, name: "Trigger Colour", firmwareName: "TRIGGER_COLOUR_MODE"),
        .init(id: 18, name: "Centre Spread", firmwareName: "CENTER_SPREAD_MODE"),
    ]

    static let selectableEffects: [LightingEffect] = effects.filter { $0.id != 0 }

    static let maxBrightness = 9
    static let minSpeed = 1
    static let maxSpeed = 3

    struct Swatch: Identifiable, Hashable {
        let name: String
        let hue: UInt8
        let saturation: UInt8
        var id: String { name }
    }

    static let swatches: [Swatch] = [
        .init(name: "White", hue: 0, saturation: 0),
        .init(name: "Red", hue: 0, saturation: 255),
        .init(name: "Orange", hue: 21, saturation: 255),
        .init(name: "Yellow", hue: 43, saturation: 255),
        .init(name: "Green", hue: 85, saturation: 255),
        .init(name: "Cyan", hue: 128, saturation: 255),
        .init(name: "Blue", hue: 170, saturation: 255),
        .init(name: "Violet", hue: 191, saturation: 255),
        .init(name: "Pink", hue: 234, saturation: 255),
    ]

    static func name(of effect: Int) -> String {
        effects.first { $0.id == effect }?.name ?? "Custom Effect"
    }
}

enum MusicLightingMode: String, CaseIterable, Identifiable, Codable {
    case equalizer = "equalizer"
    case pulse = "pulse"
    case wave = "wave"
    case vuMeter = "vuMeter"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equalizer: return "Bars"
        case .pulse: return "Pulse"
        case .wave: return "Wave"
        case .vuMeter: return "Meter"
        }
    }

    var symbol: String {
        switch self {
        case .equalizer: return "chart.bar.fill"
        case .pulse: return "waveform.path.ecg"
        case .wave: return "water.waves"
        case .vuMeter: return "gauge.with.needle"
        }
    }

    var detail: String {
        switch self {
        case .equalizer: return "Frequency bars across the keyboard"
        case .pulse: return "Flashes out from the centre on the beat"
        case .wave: return "Colour waves that follow the volume"
        case .vuMeter: return "Left and right volume, row by row"
        }
    }
}

enum MusicColorMode: String, CaseIterable, Identifiable, Codable {
    case dynamic = "dynamic"
    case wallpaper = "wallpaper"
    case custom = "custom"
    case fire = "fire"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dynamic: return "Spectrum"
        case .wallpaper: return "Wallpaper"
        case .custom: return "Custom"
        case .fire: return "Fire"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "dynamic"
        self = MusicColorMode(rawValue: raw) ?? .dynamic
    }
}

/// Lighting as shown in the app. Brightness is a level 0–9 and speed a level 1–3.
struct LightingState: Codable, Equatable {
    var effect = 6
    var brightness = 6
    var speed = 2 {
        didSet {
            speed = max(LightingCatalog.minSpeed, min(speed, LightingCatalog.maxSpeed))
        }
    }
    var hue: UInt8 = 128
    var saturation: UInt8 = 255
    /// Effect to return to when the lights are switched back on.
    var lastEffect = 6

    /// Whether lighting adjusts dynamically with music.
    var musicSync = false
    var musicMode: MusicLightingMode = .equalizer
    var musicSensitivity: Double = 1.0
    var musicColorMode: MusicColorMode = .dynamic
    /// User trim on top of automatic output-latency compensation, in ms (+ fires lights later).
    var musicSyncOffsetMs: Int = 0
    /// Whether live typing triggers expanding reactive ripples across the 3D scene and physical backlight.
    var reactiveTypingRipple = false

    var isOn: Bool { effect != 0 || musicSync }

    var color: Color {
        Color(hue: Double(hue) / 255, saturation: Double(saturation) / 255, brightness: 1)
    }

    init(effect: Int = 6, brightness: Int = 6, speed: Int = 2, hue: UInt8 = 128, saturation: UInt8 = 255, lastEffect: Int = 6,
         musicSync: Bool = false, musicMode: MusicLightingMode = .equalizer, musicSensitivity: Double = 1.0,
         musicColorMode: MusicColorMode = .dynamic, reactiveTypingRipple: Bool = false) {
        self.effect = effect
        self.brightness = brightness
        self.speed = max(LightingCatalog.minSpeed, min(speed, LightingCatalog.maxSpeed))
        self.hue = hue
        self.saturation = saturation
        self.lastEffect = lastEffect
        self.musicSync = musicSync
        self.musicMode = musicMode
        self.musicSensitivity = musicSensitivity
        self.musicColorMode = musicColorMode
        self.reactiveTypingRipple = reactiveTypingRipple
    }

    private enum CodingKeys: String, CodingKey {
        case effect, brightness, speed, hue, saturation, lastEffect
        case musicSync, musicMode, musicSensitivity, musicColorMode, musicSyncOffsetMs, reactiveTypingRipple
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedEffect = try c.decodeIfPresent(Int.self, forKey: .effect) ?? 6
        effect = max(0, min(decodedEffect, 255))
        let decodedBrightness = try c.decodeIfPresent(Int.self, forKey: .brightness) ?? 6
        brightness = max(0, min(decodedBrightness, LightingCatalog.maxBrightness))
        let decodedSpeed = try c.decodeIfPresent(Int.self, forKey: .speed) ?? 2
        speed = max(LightingCatalog.minSpeed, min(decodedSpeed, LightingCatalog.maxSpeed))
        hue = try c.decodeIfPresent(UInt8.self, forKey: .hue) ?? 128
        saturation = try c.decodeIfPresent(UInt8.self, forKey: .saturation) ?? 255
        let decodedLastEffect = try c.decodeIfPresent(Int.self, forKey: .lastEffect) ?? 6
        lastEffect = max(0, min(decodedLastEffect, 255))
        musicSync = try c.decodeIfPresent(Bool.self, forKey: .musicSync) ?? false
        musicMode = try c.decodeIfPresent(MusicLightingMode.self, forKey: .musicMode) ?? .equalizer
        let decodedSensitivity = try c.decodeIfPresent(Double.self, forKey: .musicSensitivity) ?? 1.0
        musicSensitivity = decodedSensitivity.isFinite ? max(0.2, min(decodedSensitivity, 3.0)) : 1.0
        musicColorMode = try c.decodeIfPresent(MusicColorMode.self, forKey: .musicColorMode) ?? .dynamic
        let decodedOffset = try c.decodeIfPresent(Int.self, forKey: .musicSyncOffsetMs) ?? 0
        musicSyncOffsetMs = max(-150, min(decodedOffset, 300))
        reactiveTypingRipple = try c.decodeIfPresent(Bool.self, forKey: .reactiveTypingRipple) ?? false
    }

    /// The firmware keeps brightness in steps of 26 (level 9 reads back as 235).
    static func rawBrightness(level: Int) -> UInt8 {
        UInt8(max(0, min(level, LightingCatalog.maxBrightness)) * 26)
    }

    static func brightnessLevel(raw: UInt8) -> Int {
        min(LightingCatalog.maxBrightness, Int((Double(raw) / 26).rounded()))
    }

    /// Speed levels 1...3 map to firmware values 0...2.
    static func rawSpeed(level: Int) -> UInt8 {
        UInt8(max(0, min(level - LightingCatalog.minSpeed, LightingCatalog.maxSpeed - LightingCatalog.minSpeed)))
    }

    /// Firmware raw speed reads back as written + 1 (1 for 0, 2 for 1, 3 for 2).
    static func speedLevel(raw: UInt8, current: Int = 2) -> Int {
        max(LightingCatalog.minSpeed, min(Int(raw), LightingCatalog.maxSpeed))
    }

    /// Folds a reading from the keyboard into this state.
    mutating func apply(_ raw: VIA.RawLighting) {
        effect = Int(raw.effect)
        if effect != 0 { lastEffect = effect }
        brightness = Self.brightnessLevel(raw: raw.brightness)
        speed = Self.speedLevel(raw: raw.speed, current: speed)
        hue = raw.hue
        saturation = raw.saturation
    }
}

/// Shortest-path interpolation helpers on the circular `[0, 1)` hue wheel.
enum HueMath {
    static func wrap(_ hue: Float) -> Float { ColorMath.wrapHue(hue) }
    static func shortestDelta(from a: Float, to b: Float) -> Float { ColorMath.shortestHueDelta(from: a, to: b) }
}
