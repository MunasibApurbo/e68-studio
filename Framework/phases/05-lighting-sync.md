# Phase 5: Reactive lighting

Goal: lighting that follows music, the screen or the wallpaper, without flooding the keyboard or wearing out its EEPROM.

## Sources

| Mode | macOS API | Permission |
|---|---|---|
| Music | CoreAudio process tap: `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` + `AudioHardwareCreateProcessTap` + an aggregate device (macOS 14.2+) | System Audio Recording (`NSAudioCaptureUsageDescription`) |
| Screen | ScreenCaptureKit `SCStream` at a tiny resolution (e.g. 32×18) and low frame rate | Screen Recording |
| Wallpaper | `NSWorkspace.shared.desktopImageURL(for:)`, average the image once per change | none |
| Album art | Now Playing artwork, dominant colours | none (private MediaRemote; optional) |

Reference: `Sources/E68Studio/Audio/AudioMonitor.swift` (+DSP), `Samplers/ScreenColorSampler.swift`, `Samplers/WallpaperColorSampler.swift`.

## Turning audio into light

FFT with Accelerate (`vDSP_fft_zrip`), fold into about 16 log-spaced bands, track a slow-moving peak per band for auto gain, detect beats as band-energy onsets. A small engine maps bands and beats to hue, brightness and effect each frame. Keep the engine a pure `struct` with a `step(audio, settings, now)` method so it can be self-tested without audio. Reference: `Audio/MusicLightEngine.swift`.

## Talking to the keyboard at frame rate

- Send **only values that changed** since the last frame.
- Use a short timeout and a single attempt for live frames; a dropped frame is fine, a queue of stale ones is not.
- Never send more than one frame in flight; skip frames while the device is busy.
- Send a keep-alive about once a second so a static colour is reasserted.
- **Never save to EEPROM per frame.** Save once when the mode stops or the app quits, and restore the owner's previous lighting.
- Compensate for audio output latency (`kAudioDevicePropertyLatency` plus safety offset) so light lands on the beat.

Reference: `Store/KeyboardStore+MusicSync.swift`, `Store/KeyboardStore+ScreenSync.swift`.

## Done when

Each mode runs for ten minutes with no growing latency or errors, stopping a mode restores the previous lighting, and the engine's self-test passes.
