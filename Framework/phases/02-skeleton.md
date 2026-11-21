# Phase 2: App skeleton

Goal: an app that builds, launches, finds the devices, and has a `--selftest` mode from the first day.

## Structure

Use Swift Package Manager (no Xcode project needed; it diffs cleanly and agents handle it well):

```text
Package.swift                      // one executableTarget, platforms: [.macOS("26.0")]
Sources/<App>/
  App/        <App>App.swift (entry; dispatches CLI modes before SwiftUI starts), SelfTest.swift
  HID/        Keyboard/, Mouse/, Shared/   (transport and protocols, no UI)
  Model/      plain value types: layouts, keycodes, lighting state, macros (Codable)
  Store/      @Observable stores that own a device connection and expose state to views
  Views/      Chrome/, Components/, Sections/
Resources/    JSON definitions, images
Scripts/      build-app.sh, entitlements
```

Rules:
- `Model/` has no IOKit; it is what the self-test checks offline.
- `HID/` has no SwiftUI.
- Stores are `@MainActor @Observable`; device I/O runs on a serial queue and publishes back to the main actor.

## The entry point pattern

```swift
@main
struct Launcher {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") { SelfTest.run() }          // prints PASS/FAIL, exits non-zero on failure
        else if let i = args.firstIndex(of: "--backup"), i + 1 < args.count { BackupCLI.run(path: args[i + 1]) }
        else { MyApp.main() }                                      // the SwiftUI app
    }
}
```

`SelfTest` runs offline checks first (codecs, layouts, clamping, Codable round trips) and then, if a device is connected, live checks that write to **unused** storage and restore it. See E68 Studio's `Sources/E68Studio/App/SelfTest.swift`.

## HID transport

Use `IOHIDManager` with a matching dictionary on VID, PID, **usage page and usage**, so you open only the config interface. Register device-matching and removal callbacks so the app handles plug and unplug. Requests are synchronous: send one report, wait (with a timeout) for the reply whose first byte echoes the command. Reference: `Sources/E68Studio/HID/Keyboard/HIDTransport.swift`.

## Build script

Start `Scripts/build-app.sh` now (copy E68 Studio's and rename). It builds release, creates the `.app` with `Info.plist` and usage descriptions, and signs. Having a real `.app` early matters: Accessibility and Bluetooth permissions attach to a bundle, not to `swift run`.

## Done when

- `swift build` has no warnings.
- `.build/debug/<App> --selftest` prints only PASS lines and detects the connected devices.
- The app window opens and shows each device's name and connection.
