import Foundation
import simd

/// What the physical keyboard shows on one music-sync frame. The E68 takes a single colour and
/// brightness over VIA, so this is the whole truth of the board; the 3D preview draws its per-key
/// pattern on top of exactly this colour and level.
struct MusicLightFrame: Sendable {
    /// Hue/saturation sent to the board (0...1).
    var hue: Float = 0
    var saturation: Float = 1
    /// Linear LED level 0...1 (already gamma-shaped and floored).
    var level: Float = 0
    /// Smoothed energy before shaping (0...1), useful for spatial patterns.
    var energy: Float = 0
    /// Decaying beat flash (0...1).
    var flash: Float = 0
    /// Secondary/accent colour for per-key highlights in the preview.
    var accentHue: Float = 0
    var accentSaturation: Float = 1
    var isPlaying = false

    var rgb: SIMD3<Float> { MusicLightEngine.rgb(hue: hue, saturation: saturation) }
    var accentRGB: SIMD3<Float> { MusicLightEngine.rgb(hue: accentHue, saturation: accentSaturation) }
}

/// Turns audio snapshots into board lighting. Each consumer (HID pump, 3D preview) owns its own
/// instance; the algorithm is deterministic over wall time, so both produce the same light —
/// just shifted by their own latency compensation.
struct MusicLightEngine {
    struct Settings: Equatable {
        var mode: MusicLightingMode
        var colorMode: MusicColorMode
        var sensitivity: Float
        var hue: Float
        var saturation: Float

        init(_ s: LightingState) {
            mode = s.musicMode
            colorMode = s.musicColorMode
            sensitivity = Float(s.musicSensitivity)
            hue = Float(s.hue) / 255
            saturation = Float(s.saturation) / 255
        }
    }

    /// Analysis delay of the FFT window plus DSP tick, in seconds.
    static let analysisLatency: Double = 0.022
    /// Idle glow while nothing is playing, and the floor under quiet passages.
    static let idleLevel: Float = 0.10
    static let floorLevel: Float = 0.05

    private var lastTime: TimeInterval = 0
    private var lastBeatCount: Int?
    private var envelope: Float = 0
    private var flash: Float = 0
    private var vuPeak: Float = 0
    private var hue: Float = -1
    private var saturation: Float = 1
    private var accentHue: Float = 0
    private var accentSaturation: Float = 1
    private var playingBlend: Float = 0
    private(set) var frame = MusicLightFrame()

    /// How long the lights should be held back so they land with the sound, given the output
    /// device latency, the user's trim, and how long this consumer takes to show a frame.
    static func delay(outputLatency: Double, userOffsetMs: Int, consumerLatency: Double) -> Double {
        max(0, min(0.6, outputLatency + Double(userOffsetMs) / 1000 - analysisLatency - consumerLatency))
    }

    mutating func step(_ audio: AudioSnapshot, settings: Settings, now: TimeInterval) -> MusicLightFrame {
        let isFirstFrame = lastTime == 0
        let dt = Float(!isFirstFrame ? min(0.1, max(0.0005, now - lastTime)) : 0.016)
        lastTime = now
        let sens = settings.sensitivity

        // Beat flash keyed off the monotonic counter, so a slow consumer never misses an onset.
        if let last = lastBeatCount, audio.beatCount > last, audio.isPlaying {
            flash = max(flash, min(1, audio.beatStrength * (0.85 + 0.3 * sens)))
        } else if isFirstFrame && audio.isPlaying && audio.beat > 0 {
            flash = min(1, audio.beat * sens)
        }
        lastBeatCount = audio.beatCount
        let flashTau: Float = settings.mode == .pulse ? 0.16 : 0.22
        if !isFirstFrame {
            flash *= expf(-dt / flashTau)
        }
        if flash < 0.002 { flash = 0 }

        if isFirstFrame {
            playingBlend = audio.isPlaying ? 1 : 0
        } else {
            playingBlend += ((audio.isPlaying ? 1 : 0) - playingBlend) * (1 - expf(-dt / (audio.isPlaying ? 0.05 : 0.45)))
        }

        // Per-mode target energy and release ballistics.
        let target: Float
        let release: Float
        switch settings.mode {
        case .pulse:
            // Punchy: lights live on the kick, with a little bass body between hits.
            target = max(flash, audio.bass * 0.55 + audio.amplitude * 0.15)
            release = 0.11
        case .wave:
            // Fluid: follows the loudness envelope, beats just add a swell.
            target = audio.amplitude * 0.85 + flash * 0.30
            release = 0.24
        case .equalizer:
            // Whole-spectrum activity: average of the 5 loudest bands without allocating a sorted copy.
            var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0
            for v in audio.bands {
                if v > b0 { b4 = b3; b3 = b2; b2 = b1; b1 = b0; b0 = v }
                else if v > b1 { b4 = b3; b3 = b2; b2 = b1; b1 = v }
                else if v > b2 { b4 = b3; b3 = b2; b2 = v }
                else if v > b3 { b4 = b3; b3 = v }
                else if v > b4 { b4 = v }
            }
            let top = (b0 + b1 + b2 + b3 + b4) * 0.2
            target = top * 0.70 + flash * 0.40
            release = 0.13
        case .vuMeter:
            // VU-style: ~300 ms integration with a held peak.
            vuPeak = max(audio.amplitude, vuPeak * expf(-dt / 0.9))
            target = audio.amplitude * 0.8 + vuPeak * 0.2
            release = 0.30
        }
        let goal = min(1, max(0, target * sens)) * playingBlend
        if isFirstFrame {
            envelope = goal
        } else {
            // Near-instant attack: a kick should hit the LEDs on the very next frame.
            let tau: Float = goal > envelope ? 0.005 : release
            envelope += (goal - envelope) * (1 - expf(-dt / tau))
        }

        // Perceptual shaping: LEDs are linear, eyes are not; gamma keeps troughs dark and peaks crisp.
        let shaped = powf(envelope, 1.5)
        let floor = Self.floorLevel * playingBlend + Self.idleLevel * (1 - playingBlend)
        let level = floor + (1 - floor) * shaped

        // Colour.
        var targetHue: Float
        var targetSat: Float
        var tAccentHue: Float
        var tAccentSat: Float
        var hueTau: Float = 0.12
        switch settings.colorMode {
        case .custom:
            targetHue = settings.hue
            // White-hot peaks on strong hits.
            targetSat = settings.saturation * (1 - max(0, flash - 0.6) * 0.5 * playingBlend)
            tAccentHue = settings.hue
            tAccentSat = settings.saturation * 0.35
        case .wallpaper:
            let wp = WallpaperColorSampler.shared.currentPalette()
            let mix = min(1, audio.colorShift * 0.45 + flash * 0.55) * playingBlend
            targetHue = HueMath.wrap(wp.hue + HueMath.shortestDelta(from: wp.hue, to: wp.secondaryHue) * mix)
            targetSat = wp.saturation + (wp.secondarySaturation - wp.saturation) * mix
            tAccentHue = wp.secondaryHue
            tAccentSat = wp.secondarySaturation
            hueTau = flash > 0.7 ? 0.04 : 0.14
        case .fire:
            let heat = min(1, envelope * 0.7 + flash * 0.4) * playingBlend
            targetHue = heat * 0.125
            targetSat = max(0.72, 1 - max(0, heat - 0.75) * 0.5)
            tAccentHue = 0.13
            tAccentSat = 0.85
            hueTau = 0.05
        case .dynamic:
            if audio.hasCoverColor {
                let mix = min(1, audio.colorShift * 0.55 + flash * 0.55) * playingBlend
                targetHue = HueMath.wrap(audio.coverHue + HueMath.shortestDelta(from: audio.coverHue, to: audio.secondaryCoverHue) * mix)
                targetSat = audio.coverSaturation + (audio.secondaryCoverSaturation - audio.coverSaturation) * mix
                tAccentHue = audio.secondaryCoverHue
                tAccentSat = audio.secondaryCoverSaturation
            } else if audio.isPlaying {
                targetHue = HueMath.wrap(audio.dominantHue + flash * 0.08)
                targetSat = max(0.6, 0.95 - flash * 0.25)
                tAccentHue = HueMath.wrap(audio.dominantHue + 0.33)
                tAccentSat = 0.9
            } else {
                targetHue = settings.hue
                targetSat = settings.saturation
                tAccentHue = HueMath.wrap(settings.hue + 0.33)
                tAccentSat = settings.saturation
            }
            // Snap colour on hits so the change reads as part of the beat.
            hueTau = flash > 0.7 ? 0.03 : 0.14
        }

        let hk = 1 - expf(-dt / hueTau)
        if hue < 0 {
            hue = targetHue; saturation = targetSat; accentHue = tAccentHue; accentSaturation = tAccentSat
        } else {
            hue = HueMath.wrap(hue + HueMath.shortestDelta(from: hue, to: targetHue) * hk)
            saturation += (targetSat - saturation) * hk
            let ak = 1 - expf(-dt / 0.2)
            accentHue = HueMath.wrap(accentHue + HueMath.shortestDelta(from: accentHue, to: tAccentHue) * ak)
            accentSaturation += (tAccentSat - accentSaturation) * ak
        }

        frame = MusicLightFrame(
            hue: hue,
            saturation: min(1, max(0, saturation)),
            level: min(1, max(0, level)),
            energy: envelope,
            flash: flash,
            accentHue: accentHue,
            accentSaturation: min(1, max(0, accentSaturation)),
            isPlaying: audio.isPlaying
        )
        return frame
    }

    static func rgb(hue: Float, saturation: Float) -> SIMD3<Float> {
        ColorMath.hsvToRGB(hue: hue, saturation: saturation)
    }
}
