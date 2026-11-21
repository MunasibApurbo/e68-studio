// swift-tools-version: 5.9
import PackageDescription

// Note: Root-level `Resources/` (`ukiru-mat.jpg` and `VIA/*.json`) stay outside `Sources/E68Studio`
// so offline generators and release packaging (`Scripts/build-app.sh`) share one copy; CLI builds
// locate them via `KeyboardScene.resource(_:)` while `.app` bundles receive them in `Contents/Resources/`.
let package = Package(
    name: "E68Studio",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "E68Studio", path: "Sources/E68Studio")
    ]
)
