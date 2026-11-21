import SwiftUI
import AppKit
import SceneKit
import Metal
import simd

/// `E68Studio --render <dir>`: renders the 3D scene to PNG files for visual review.
enum SceneRender {
    private static func writePNG(_ image: NSImage, to path: String) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    static func run(directory: String) -> Never {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let world = KeyboardScene()
        world.setAmbience(deskLampOn: true, mood: .daylight, scenario: .swissAlps)
        let device = MTLCreateSystemDefaultDevice()
        let pathTracer = device.flatMap { PathTracerRenderer(device: $0) }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = world.scene
        renderer.pointOfView = world.cameraNode
        var lighting = LightingState()
        lighting.effect = 6; lighting.brightness = 9; lighting.hue = 160; lighting.saturation = 255
        world.setLighting(lighting)

        func legends(studio: Bool) -> [Int: Legend] {
            var out = [Int: Legend]()
            for slot in Layout.keys {
                out[slot.index] = studio ? Keycodes.def(for: FactoryKeymap.layers[0][slot.index]).legend
                    : LegendPainter.printed(FactoryKeymap.layers[2][slot.index])
            }
            return out
        }
        var time: TimeInterval = 1
        func shot(_ name: String, _ pose: KeyboardScene.Pose, studio: Bool, samples: UInt32 = 48) {
            world.setLegends(legends(studio: studio))
            world.setGoal(pose, immediately: true)
            time += 1
            world.renderer(renderer, updateAtTime: time)
            let image: NSImage
            if let pathTracer, let rtImg = pathTracer.renderOfflineShot(world: world, width: 1440, height: 900, samples: samples) {
                image = rtImg
            } else {
                image = renderer.snapshot(atTime: time, with: CGSize(width: 1440, height: 900), antialiasingMode: .multisampling4X)
            }
            writePNG(image, to: "\(directory)/\(name).png")
            print("wrote \(name).png")
        }
        shot("home", KeyboardScene.homePose, studio: false)
        shot("desk-angle", KeyboardScene.deskAnglePose, studio: false)
        shot("desk-top", KeyboardScene.deskTopPose, studio: false)
        // Front desk view after gently orbiting and zooming in 3D.
        world.setGoal(KeyboardScene.homePose, immediately: true)
        world.orbit(dx: -36, dy: 28, deskMode: true)
        world.zoom(by: 0.72, deskMode: true)
        shot("home-looked", world.currentGoal, studio: false)
        shot("closeup-mouse-iem", KeyboardScene.Pose(target: SIMD3(17.5, 1.0, -5.5), distance: 17, pitch: 28 * .pi / 180, yaw: -0.18, fov: 46), studio: false)
        shot("closeup-lamp-pothos", KeyboardScene.Pose(target: SIMD3(-20.0, 5.5, -13.5), distance: 26, pitch: 18 * .pi / 180, yaw: 0.20, fov: 50), studio: false)
        shot("closeup-lamp-head", KeyboardScene.Pose(target: SIMD3(-26.2, 10.4, -12.0), distance: 43, pitch: 14 * .pi / 180, yaw: 0.22, fov: 54), studio: false)
        shot("closeup-cables", KeyboardScene.Pose(target: SIMD3(6.5, 1.2, -14.5), distance: 26, pitch: 42 * .pi / 180, yaw: 0.20, fov: 48), studio: false)
        shot("closeup-bottle-phone", KeyboardScene.Pose(target: SIMD3(26.5, 4.0, -10.0), distance: 26, pitch: 22 * .pi / 180, yaw: -0.22, fov: 50), studio: false)
        // Straight-down product shots, framed like IMG_1842 (keyboard) and IMG_1841 (mouse).
        shot("kb-top", KeyboardScene.Pose(target: SIMD3(0, 0.8, 0.2), distance: 26, pitch: .pi / 2, yaw: 0, fov: 42), studio: false)
        shot("mouse-top", KeyboardScene.Pose(target: SIMD3(12.6, 0.8, -0.6), distance: 17, pitch: .pi / 2, yaw: 0, fov: 42), studio: true)
        shot("kb-angle", KeyboardScene.Pose(target: SIMD3(1, 0.8, 0.5), distance: 18, pitch: 22 * .pi / 180, yaw: -0.35, fov: 40), studio: false)
        shot("mouse-side", KeyboardScene.Pose(target: SIMD3(12.6, 1.0, -0.6), distance: 11, pitch: 8 * .pi / 180, yaw: 1.5, fov: 40), studio: true)
        shot("studio-test", StudioSection.test.studioPose, studio: true)
        shot("studio-light", StudioSection.light.studioPose, studio: true)
        shot("studio-macros", StudioSection.macros.studioPose, studio: true)
        shot("mouse-test", MouseSpot.pose(for: .test), studio: false)
        shot("mouse-dpi", MouseSpot.pose(for: .dpi), studio: false)
        shot("mouse-buttons", MouseSpot.pose(for: .buttons), studio: false)
        shot("mouse-more", MouseSpot.pose(for: .more), studio: false)
        var low = KeyboardScene.studioPose(offset: .zero)
        low.pitch = 30 * .pi / 180; low.yaw = 0.5; low.distance = 20
        world.setSelection(2 * 16 + 3)
        shot("studio-low", low, studio: true)

        var musicLit = LightingState()
        musicLit.musicSync = true
        musicLit.musicMode = .equalizer
        musicLit.brightness = 9
        world.setLighting(musicLit)
        world.setAudioSnapshot(AudioSnapshot(
            amplitude: 0.85,
            peak: 0.95,
            bass: 0.9,
            mid: 0.65,
            treble: 0.5,
            bands: [0.95, 0.88, 0.75, 0.60, 0.52, 0.70, 0.85, 0.65, 0.45, 0.55, 0.75, 0.60, 0.40, 0.35, 0.50, 0.30],
            beat: 0.8,
            beatDetected: true,
            beatCount: 1,
            beatStrength: 0.85,
            dominantHue: 0.6,
            isPlaying: true
        ))
        shot("music-equalizer", StudioSection.light.studioPose, studio: true)
        shot("music-eq-center", KeyboardScene.studioPose(offset: .zero), studio: true)

        var waveLit = LightingState()
        waveLit.effect = 1
        waveLit.brightness = 9
        waveLit.speed = 2
        waveLit.reactiveTypingRipple = true
        world.setLighting(waveLit)
        world.setSelection(nil)
        world.setPressed([2 * 16 + 5, 3 * 16 + 7])
        shot("kb-wave", KeyboardScene.Pose(target: SIMD3(0, 0.8, 0.2), distance: 26, pitch: 68 * .pi / 180, yaw: 0, fov: 38), studio: false)
        world.setPressed([])

        // Indoor room closeups & midnight mood check matching user's closeup angle.
        world.setLighting(lighting)
        world.setAmbience(deskLampOn: true, mood: .daylight, scenario: .room)
        shot("room-daylight-home", KeyboardScene.homePose, studio: false, samples: 64)
        shot("room-daylight-closeup", KeyboardScene.Pose(target: SIMD3(17.5, 1.0, -5.5), distance: 20, pitch: 26 * .pi / 180, yaw: -0.22, fov: 46), studio: false, samples: 64)
        world.setAmbience(deskLampOn: true, mood: .midnight, scenario: .room)
        shot("room-midnight-home", KeyboardScene.homePose, studio: false, samples: 64)
        shot("room-midnight-closeup", KeyboardScene.Pose(target: SIMD3(17.5, 1.0, -5.5), distance: 20, pitch: 26 * .pi / 180, yaw: -0.22, fov: 46), studio: false, samples: 64)
        exit(0)
    }

    /// `E68Studio --render-motion <dir>`: drives the live renderer without a window. It orbits the desk,
    /// lets the image settle, then runs an animated backlight, saving the frames exactly as they would be
    /// presented and printing the GPU time each kind of frame costs. Works with the screen locked.
    static func runMotion(directory: String) -> Never {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice(), let tracer = PathTracerRenderer(device: device) else {
            print("Hardware ray tracing is not available on this Mac.")
            exit(1)
        }
        let world = KeyboardScene()
        world.usesHardwareRayTracer = true
        world.setAmbience(deskLampOn: true, mood: .daylight, scenario: .swissAlps)
        var lighting = LightingState()
        lighting.effect = 6; lighting.brightness = 9; lighting.hue = 160; lighting.saturation = 255
        world.setLighting(lighting)
        var legends = [Int: Legend]()
        for slot in Layout.keys { legends[slot.index] = LegendPainter.printed(FactoryKeymap.layers[2][slot.index]) }
        world.setLegends(legends)
        world.setGoal(KeyboardScene.homePose, immediately: true)
        tracer.captureDirectory = directory

        let size = UserDefaults.standard.string(forKey: "e68.motionSize")?.split(separator: "x").compactMap { Int($0) } ?? []
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size.count == 2 ? size[0] : 1280,
                                                            height: size.count == 2 ? size[1] : 800, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        guard let target = device.makeTexture(descriptor: desc) else { exit(1) }

        var time: TimeInterval = 1
        var gpuMs = [String: [Double]]()
        func frame() {
            time += 1.0 / 60.0
            guard let cmd = tracer.renderFrame(world: world, target: target, drawable: nil, time: time) else { return }
            cmd.waitUntilCompleted()
            if let error = cmd.error { print("frame failed: \(error.localizedDescription)") }
            gpuMs[tracer.lastGear, default: []].append((cmd.gpuEndTime - cmd.gpuStartTime) * 1000)
        }
        func report(_ phase: String) {
            for (gear, ms) in gpuMs.sorted(by: { $0.key < $1.key }) {
                let sorted = ms.sorted()
                print(String(format: "%@: %@ x%d  gpu avg %.2f ms  median %.2f  worst %.2f", phase, gear, ms.count,
                             ms.reduce(0, +) / Double(ms.count), sorted[sorted.count / 2], sorted.last ?? 0))
            }
            gpuMs.removeAll()
        }
        func settle() {
            var guardFrames = 0
            while !tracer.isSettledForSleep && guardFrames < 2000 { frame(); guardFrames += 1 }
        }

        settle(); report("first settle")
        for _ in 0..<150 { world.orbit(dx: 3.5, dy: 0.4, deskMode: true); frame() }
        report("orbit")
        settle(); report("settle after orbit")

        // A slow, small drag: the kind of motion where softness or shimmer is easiest to notice.
        for _ in 0..<90 { world.orbit(dx: -0.5, dy: 0.1, deskMode: true); frame() }
        report("slow drag")
        settle(); report("settle after drag")

        var wave = LightingState()
        wave.effect = 1; wave.brightness = 9; wave.speed = 2
        world.setLighting(wave)
        for _ in 0..<90 { frame() }
        report("animated backlight")
        // Dragging the camera while the backlight animates and keys are selected and pressed: the case where
        // stored light must stay steady. Any grain here means something is restarting it.
        world.setLighting(lighting)   // static backlight, so "settle" can actually be reached
        world.setAmbience(deskLampOn: true, mood: .midnight, scenario: .swissAlps)
        settle(); report("settle at night")
        world.setLighting(wave)
        for n in 0..<120 {
            world.orbit(dx: 1.2, dy: 0.15, deskMode: false)
            if n % 20 == 0 { world.setSelection(2 * 16 + (n / 20)) }
            if n % 30 == 5 { world.setPressed([3 * 16 + 4]) } else if n % 30 == 15 { world.setPressed([]) }
            frame()
        }
        report("night drag with animated backlight")
        world.setSelection(nil)
        world.setLighting(lighting)
        settle(); report("settle after backlight")
        // Let the last captures finish writing.
        Thread.sleep(forTimeInterval: 1.0)
        exit(0)
    }

    /// `E68Studio --render-switch <dir>`: settles on one world, switches to another and saves frames from
    /// the transition, to check that the stored light is never seen filling in. Run with
    /// `-e68.noLightCache YES` to force a full rebuild on the switch.
    static func runSwitch(directory: String) -> Never {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice(), let tracer = PathTracerRenderer(device: device) else {
            print("Hardware ray tracing is not available on this Mac.")
            exit(1)
        }
        let world = KeyboardScene()
        world.usesHardwareRayTracer = true
        world.setAmbience(deskLampOn: true, mood: .daylight, scenario: .swissAlps)
        world.setGoal(KeyboardScene.deskAnglePose, immediately: true)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1280, height: 800, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        guard let target = device.makeTexture(descriptor: desc) else { exit(1) }
        var time: TimeInterval = 1
        func frame() {
            time += 1.0 / 60.0
            autoreleasepool {
                tracer.renderFrame(world: world, target: target, drawable: nil, time: time)?.waitUntilCompleted()
            }
        }
        func save(_ name: String) {
            if let image = tracer.snapshot(of: target) { writePNG(image, to: "\(directory)/\(name).png") }
            print("wrote \(name).png")
        }
        if UserDefaults.standard.bool(forKey: "e68.testA1") {
            let a1World = KeyboardScene()
            a1World.usesHardwareRayTracer = true
            a1World.setAmbience(deskLampOn: false, mood: .midnight, scenario: .room)
            a1World.setGoal(KeyboardScene.homePose, immediately: true)
            func a1Frame(_ t: PathTracerRenderer) {
                time += 1.0 / 60.0
                t.renderFrame(world: a1World, target: target, drawable: nil, time: time)?.waitUntilCompleted()
            }
            func a1Save(_ t: PathTracerRenderer, _ name: String) {
                if let image = t.snapshot(of: target) { writePNG(image, to: "\(directory)/\(name).png") }
                print("wrote \(name).png")
            }
            var f = 0
            repeat { a1Frame(tracer); f += 1 } while (!tracer.isSettledForSleep || f < 20) && f < 4000
            a1Save(tracer, "a1-before")
            let genBefore = tracer.extractor.lightCacheGeneration

            // Mid-run monitor colour change (no topology change, keeps existing light cache).
            let pink = NSColor(srgbRed: 1.0, green: 0.14, blue: 0.52, alpha: 1)
            a1World.monitorScreenMaterial?.emission.contents = pink
            a1World.monitorScreenMaterial?.emission.intensity = 0.95
            a1World.materialRevision &+= 1
            print("a1World AFTER set: emission=\(String(describing: a1World.monitorScreenMaterial?.emission.contents))")

            var monFrames = 0
            repeat {
                a1Frame(tracer)
                monFrames += 1
                if [1, 2, 4, 8, 16, 32, 64, 128].contains(monFrames) {
                    a1Save(tracer, String(format: "a1-mon-%03d", monFrames))
                }
            } while (!tracer.isSettledForSleep || monFrames < 20) && monFrames < 4000
            a1Save(tracer, "a1-mon-settled")
            let settledImage = tracer.snapshot(of: target)
            let genAfterMon = tracer.extractor.lightCacheGeneration
            print("A1 monitor change: frames=\(monFrames), lastSample=\(tracer.sampleIndex), lightCacheGen=\(genBefore)->\(genAfterMon)")

            // Mid-run keycap colour change on a few keys.
            for slot in Layout.keys.prefix(12) {
                a1World.topMaterials[slot.index]?.diffuse.contents = NSColor(srgbRed: 0.25, green: 0.65, blue: 0.95, alpha: 1)
            }
            a1World.materialRevision &+= 1
            var keyFrames = 0
            repeat {
                a1Frame(tracer)
                keyFrames += 1
                if [1, 4, 16].contains(keyFrames) {
                    a1Save(tracer, String(format: "a1-key-%03d", keyFrames))
                }
            } while (!tracer.isSettledForSleep || keyFrames < 20) && keyFrames < 4000
            let genAfterKey = tracer.extractor.lightCacheGeneration
            print("A1 keycap change: frames=\(keyFrames), lastSample=\(tracer.sampleIndex), lightCacheGen=\(genAfterMon)->\(genAfterKey)")

            // From-scratch bake of the new monitor state (before keycap tweak) to compare against 200-pass gradual refresh.
            let scratchWorld = KeyboardScene()
            scratchWorld.usesHardwareRayTracer = true
            scratchWorld.setAmbience(deskLampOn: false, mood: .midnight, scenario: .room)
            scratchWorld.setGoal(KeyboardScene.homePose, immediately: true)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            scratchWorld.stepFrame(atTime: time)
            print("scratchWorld BEFORE set: emission=\(String(describing: scratchWorld.monitorScreenMaterial?.emission.contents))")
            scratchWorld.monitorScreenMaterial?.emission.contents = pink
            scratchWorld.monitorScreenMaterial?.emission.intensity = 0.95
            print("scratchWorld AFTER set1: emission=\(String(describing: scratchWorld.monitorScreenMaterial?.emission.contents))")
            SCNTransaction.flush()
            CATransaction.flush()
            print("scratchWorld AFTER flush: emission=\(String(describing: scratchWorld.monitorScreenMaterial?.emission.contents))")
            scratchWorld.materialRevision &+= 1
            guard let scratchTracer = PathTracerRenderer(device: device) else { exit(1) }
            var sf = 0
            repeat {
                time += 1.0 / 60.0
                scratchTracer.renderFrame(world: scratchWorld, target: target, drawable: nil, time: time)?.waitUntilCompleted()
                sf += 1
            } while (!scratchTracer.isSettledForSleep || sf < 20) && sf < 4000
            a1Save(scratchTracer, "a1-mon-scratch")
            print("scratchWorld AFTER render: monitorTexIndex=\(scratchTracer.extractor.monitorTextureIndex), emission=\(String(describing: scratchWorld.monitorScreenMaterial?.emission.contents))")
            func printDiff(_ label: String, _ imgA: NSImage?, _ imgB: NSImage?) {
                guard let imgA, let imgB,
                      let cgA = imgA.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let cgB = imgB.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let dataA = cgA.dataProvider?.data, let dataB = cgB.dataProvider?.data else { return }
                let pA = CFDataGetBytePtr(dataA)!, pB = CFDataGetBytePtr(dataB)!
                let count = min(CFDataGetLength(dataA), CFDataGetLength(dataB))
                var sumAbs: Double = 0
                var sumSq: Double = 0
                var maxDiff = 0
                var channels = 0
                for idx in stride(from: 0, to: count, by: 4) {
                    for c in 0..<3 {
                        let d = abs(Int(pA[idx + c]) - Int(pB[idx + c]))
                        sumAbs += Double(d)
                        sumSq += Double(d * d)
                        if d > maxDiff { maxDiff = d }
                        channels += 1
                    }
                }
                let mae = sumAbs / Double(max(channels, 1))
                let rmse = sqrt(sumSq / Double(max(channels, 1)))
                print(String(format: "%@: MAE=%.3f/255 RMSE=%.3f/255 maxDiff=%d/255", label, mae, rmse, maxDiff))
            }
            printDiff("A1 diff (mon gradual-200 vs from-scratch-112)", settledImage, scratchTracer.snapshot(of: target))

            // Wallpaper image swap check on a1World (CGImage -> different CGImage, verifying monitorTextureHash + zero speckle).
            func makeWallCGImage(r: UInt8, g: UInt8, b: UInt8) -> CGImage {
                let w = 256, h = 144
                var bytes = [UInt8](repeating: 255, count: w * h * 4)
                for y in 0..<h {
                    for x in 0..<w {
                        let i = (y * w + x) * 4
                        let grad = Double(x) / Double(w)
                        bytes[i + 0] = UInt8(Double(r) * (0.4 + 0.6 * grad))
                        bytes[i + 1] = UInt8(Double(g) * (0.4 + 0.6 * (1.0 - grad)))
                        bytes[i + 2] = b
                    }
                }
                let cs = CGColorSpaceCreateDeviceRGB()
                let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                return ctx.makeImage()!
            }
            let wallImg = makeWallCGImage(r: 40, g: 220, b: 255)
            a1World.monitorScreenMaterial?.emission.contents = wallImg
            a1World.monitorScreenMaterial?.emission.intensity = 0.90
            a1World.materialRevision &+= 1
            var wallFrames = 0
            repeat {
                a1Frame(tracer)
                wallFrames += 1
                if [1, 4, 16].contains(wallFrames) {
                    a1Save(tracer, String(format: "a1-wall-%03d", wallFrames))
                }
            } while (!tracer.isSettledForSleep || wallFrames < 20) && wallFrames < 4000
            let genAfterWall = tracer.extractor.lightCacheGeneration
            print("A1 wallpaper image change: frames=\(wallFrames), lastSample=\(tracer.sampleIndex), lightCacheGen=\(genAfterKey)->\(genAfterWall), monTexIdx=\(tracer.extractor.monitorTextureIndex)")
            exit(0)
        }
        if UserDefaults.standard.bool(forKey: "e68.memTest") {
            func settleAndLog(_ label: String) {
                var f = 0
                repeat { frame(); f += 1 } while (!tracer.isSettledForSleep || f < 20) && f < 4000
                print(String(format: "MEM %@: rss=%.1f MB, gpuAllocated=%.1f MB",
                             label, E68Perf.residentMemoryMB(), Double(device.currentAllocatedSize) / 1_048_576.0))
                tracer.logGPUMemory(label: label)
            }
            settleAndLog("launch-swissAlps")
            for scenario in [DeskScenario.nature, .ocean, .canyon, .room] {
                autoreleasepool {
                    world.setAmbience(deskLampOn: true, mood: .daylight, scenario: scenario)
                }
                settleAndLog("visit-\(scenario.rawValue)")
            }
            exit(0)
        }
        for index in 1...6 {
            frame()
            if [1, 3, 6].contains(index) { save(String(format: "launch-%03d", index)) }
        }
        var frames = 6
        repeat { frame(); frames += 1 } while (!tracer.isSettledForSleep || frames < 40) && frames < 4000
        save("before")
        world.setAmbience(deskLampOn: true, mood: .daylight, scenario: .room)
        for index in 1...120 {
            frame()
            if [1, 16, 24, 30, 36, 44, 60].contains(index) { save(String(format: "switch-%03d", index)) }
        }
        exit(0)
    }

    /// `E68Studio --render-closeups <dir>`: the same close views of materials from whichever renderer is
    /// active, named after it, so the live renderer can be checked against the path tracer (`-e68.live NO`).
    /// `-e68.closeupScenario room` and `-e68.closeupMood midnight` pick the setting.
    static func runCloseups(directory: String) -> Never {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice(), let tracer = PathTracerRenderer(device: device) else {
            print("Hardware ray tracing is not available on this Mac.")
            exit(1)
        }
        let defaults = UserDefaults.standard
        let scenario = defaults.string(forKey: "e68.closeupScenario").flatMap(DeskScenario.init(rawValue:)) ?? .swissAlps
        let mood = defaults.string(forKey: "e68.closeupMood").flatMap(DeskMood.init(rawValue:)) ?? .daylight
        let lampColor = defaults.string(forKey: "e68.closeupLampColor").flatMap(DeskLampColor.init(rawValue:)) ?? .warm
        let lampBrightness = defaults.object(forKey: "e68.closeupLampBrightness") != nil
            ? Float(defaults.double(forKey: "e68.closeupLampBrightness"))
            : Float(1.0)
        let world = KeyboardScene()
        world.usesHardwareRayTracer = true
        world.setAmbience(deskLampOn: true, mood: mood, scenario: scenario)
        world.setDeskLampLight(color: lampColor, brightness: lampBrightness)
        var lighting = LightingState()
        lighting.effect = 6; lighting.brightness = 9; lighting.hue = 160; lighting.saturation = 255
        world.setLighting(lighting)
        var legends = [Int: Legend]()
        for slot in Layout.keys { legends[slot.index] = LegendPainter.printed(FactoryKeymap.layers[2][slot.index]) }
        world.setLegends(legends)

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1280, height: 800, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        guard let target = device.makeTexture(descriptor: desc) else { exit(1) }

        let live = PathTracerRenderer.liveMode
        let tag = "\(scenario.rawValue)-\(mood.rawValue)-" + (live ? "live" : "pathtraced")
        let views: [(String, KeyboardScene.Pose)] = [
            ("home", KeyboardScene.homePose),
            ("angle", KeyboardScene.deskAnglePose),
            ("keyboard", KeyboardScene.Pose(target: SIMD3(1, 0.8, 0.5), distance: 18, pitch: 22 * .pi / 180, yaw: -0.35, fov: 40)),
            ("keyboard-top", KeyboardScene.Pose(target: SIMD3(4, 0.8, 0.2), distance: 24, pitch: 78 * .pi / 180, yaw: 0, fov: 40)),
            ("keyboard-back", KeyboardScene.Pose(target: SIMD3(-0.6, 0.80, -3.0), distance: 16.5, pitch: 4 * .pi / 180, yaw: .pi, fov: 38)),
            ("keyboard-bottom", KeyboardScene.Pose(target: SIMD3(0, 0.45, 0), distance: 20.5, pitch: -89 * .pi / 180, yaw: 0, fov: 40)),
            ("mat-and-mouse", KeyboardScene.Pose(target: SIMD3(17.5, 1.0, -5.5), distance: 17, pitch: 28 * .pi / 180, yaw: -0.18, fov: 46)),
            ("wood-and-cables", KeyboardScene.Pose(target: SIMD3(6.5, 1.2, -14.5), distance: 26, pitch: 42 * .pi / 180, yaw: 0.20, fov: 48)),
            ("lamp-and-plant", KeyboardScene.Pose(target: SIMD3(-20.0, 5.5, -13.5), distance: 26, pitch: 18 * .pi / 180, yaw: 0.20, fov: 50)),
            ("glass-and-phone", KeyboardScene.Pose(target: SIMD3(26.5, 4.0, -10.0), distance: 26, pitch: 22 * .pi / 180, yaw: -0.22, fov: 50)),
        ]
        var time: TimeInterval = 1
        // `-e68.closeupOnly home` renders a single view, for sweeping every scenario quickly.
        let only = defaults.string(forKey: "e68.closeupOnly")
        for (name, pose) in views where only == nil || only == name {
            let hideDeskForBottom = (name == "keyboard-bottom")
            let savedFillPos = world.fillLightNode?.simdPosition
            let savedFillIntensity = world.fillLightNode?.light?.intensity
            if hideDeskForBottom {
                world.modelWorld.isHidden = true
                world.keyboardShadow?.isHidden = true
                world.scenarioRoot.isHidden = true
                world.fillLightNode?.simdPosition = SIMD3<Float>(0, -14, 4)
                world.fillLightNode?.light?.intensity = 1800
                world.topologyRevision &+= 1
            }
            world.setGoal(pose, immediately: true)
            let image: NSImage?
            if live {
                var frames = 0
                repeat {
                    time += 1.0 / 60.0
                    autoreleasepool {
                        tracer.renderFrame(world: world, target: target, drawable: nil, time: time)?.waitUntilCompleted()
                    }
                    frames += 1
                } while (!tracer.isSettledForSleep || frames < 40) && frames < 4000
                image = tracer.snapshot(of: target)
            } else {
                time += 1
                world.stepFrame(atTime: time)
                image = tracer.renderOfflineShot(world: world, width: 1280, height: 800, samples: 96)
            }
            if hideDeskForBottom {
                world.modelWorld.isHidden = false
                world.keyboardShadow?.isHidden = false
                world.scenarioRoot.isHidden = false
                if let savedFillPos { world.fillLightNode?.simdPosition = savedFillPos }
                if let savedFillIntensity { world.fillLightNode?.light?.intensity = savedFillIntensity }
                world.topologyRevision &+= 1
            }
            if let image { writePNG(image, to: "\(directory)/\(name)-\(tag).png") }
            print("wrote \(name)-\(tag).png")
        }
        exit(0)
    }

    static func runScenarios(directory: String) -> Never {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let world = KeyboardScene()
        let device = MTLCreateSystemDefaultDevice()
        let pathTracer = device.flatMap { PathTracerRenderer(device: $0) }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = world.scene
        renderer.pointOfView = world.cameraNode

        var lighting = LightingState()
        lighting.effect = 6; lighting.brightness = 9; lighting.hue = 160; lighting.saturation = 255
        world.setLighting(lighting)

        var outLegends = [Int: Legend]()
        for slot in Layout.keys {
            outLegends[slot.index] = LegendPainter.printed(FactoryKeymap.layers[2][slot.index])
        }
        world.setLegends(outLegends)

        var time: TimeInterval = 1
        for scenario in DeskScenario.allCases {
            world.setAmbience(deskLampOn: true, mood: .daylight, scenario: scenario)
            for (suffix, pose) in [("home", KeyboardScene.homePose), ("angle", KeyboardScene.deskAnglePose), ("top", KeyboardScene.deskTopPose)] {
                world.setGoal(pose, immediately: true)
                time += 1
                world.renderer(renderer, updateAtTime: time)
                let image: NSImage
                if let pathTracer, let rtImg = pathTracer.renderOfflineShot(world: world, width: 1280, height: 800, samples: 32) {
                    image = rtImg
                } else {
                    image = renderer.snapshot(atTime: time, with: CGSize(width: 1280, height: 800), antialiasingMode: .multisampling4X)
                }
                let filename = "\(scenario.rawValue)-\(suffix).png"
                writePNG(image, to: "\(directory)/\(filename)")
                print("wrote \(filename)")
            }
        }
        exit(0)
    }
}
