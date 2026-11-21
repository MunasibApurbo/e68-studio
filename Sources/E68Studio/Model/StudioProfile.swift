import Foundation

/// A saved studio profile combining keyboard lighting, active layer, mouse DPI stage,
/// and optional macOS app bundle identifiers for automatic focus-based switching.
struct StudioProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var bundleIdentifiers: [String]
    var lighting: LightingState
    var activeLayer: Int
    var mouseStageIndex: Int?

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "sparkles",
        bundleIdentifiers: [String] = [],
        lighting: LightingState = LightingState(),
        activeLayer: Int = 0,
        mouseStageIndex: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.bundleIdentifiers = bundleIdentifiers
        self.lighting = lighting
        self.activeLayer = activeLayer
        self.mouseStageIndex = mouseStageIndex
    }

    func matches(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return bundleIdentifiers.contains { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
    }

    static let defaults: [StudioProfile] = [
        StudioProfile(
            name: "Studio Default",
            symbol: "sparkles",
            bundleIdentifiers: [],
            lighting: LightingState(effect: 6, brightness: 6, speed: 2, hue: 128, saturation: 255),
            activeLayer: 0,
            mouseStageIndex: 2
        ),
        StudioProfile(
            name: "Coding",
            symbol: "chevron.left.forwardslash.chevron.right",
            bundleIdentifiers: ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.apple.Terminal", "com.googlecode.iterm2"],
            lighting: LightingState(effect: 6, brightness: 4, speed: 2, hue: 0, saturation: 0),
            activeLayer: 0,
            mouseStageIndex: 2
        ),
        StudioProfile(
            name: "Music & Media",
            symbol: "waveform",
            bundleIdentifiers: ["com.apple.Music", "com.spotify.client", "com.apple.QuickTimePlayerX"],
            lighting: LightingState(
                effect: 6,
                brightness: 8,
                speed: 2,
                hue: 191,
                saturation: 255,
                musicSync: true,
                musicMode: .equalizer,
                musicSensitivity: 1.15,
                musicColorMode: .dynamic
            ),
            activeLayer: 0,
            mouseStageIndex: 1
        ),
    ]
}
