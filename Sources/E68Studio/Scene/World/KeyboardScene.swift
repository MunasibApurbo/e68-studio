import SceneKit
import AppKit
import simd

/// The 3D world: the desk setup with real 3D models of the E68 keyboard, MCHOSE G7 mouse,
/// monitor, Mac mini, plants, lamp, and accessories. Units are keycap pitches (1 u = 19.05 mm);
/// +x right, +y up, +z toward the user.
final class KeyboardScene: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    // MARK: Camera

    struct Pose: Equatable {
        var target: SIMD3<Float>
        var distance: Float
        var pitch: Float
        var yaw: Float
        var fov: Float

        func mixed(toward goal: Pose, _ t: Float) -> Pose {
            Pose(target: target + (goal.target - target) * t, distance: distance + (goal.distance - distance) * t,
                 pitch: pitch + (goal.pitch - pitch) * t, yaw: yaw + (goal.yaw - yaw) * t, fov: fov + (goal.fov - fov) * t)
        }
    }

    /// Wide front-elevated view framing the full 3D desk setup.
    static let homePose = Pose(
        target: SIMD3(2.8, 8.6, -5.0),
        distance: 64,
        pitch: 14 * .pi / 180,
        yaw: 0.01,
        fov: 56
    )

    /// Three-quarter hero view showing the depth of the monitor, Mac mini, lamp, IEMs, and plants.
    static let deskAnglePose = Pose(
        target: SIMD3(3.4, 7.8, -5.5),
        distance: 69,
        pitch: 21 * .pi / 180,
        yaw: 0.33,
        fov: 55
    )

    /// Overhead view looking down at the desk mat, keyboard, mouse, and desk accessories.
    static let deskTopPose = Pose(
        target: SIMD3(2.0, 0.4, -7.8),
        distance: 63,
        pitch: 74 * .pi / 180,
        yaw: 0,
        fov: 59
    )

    static func studioPose(
        offset: SIMD3<Float>,
        distance: Float = 33,
        pitchDegrees: Float = 56,
        fov: Float = 38
    ) -> Pose {
        Pose(
            target: SIMD3(0, 0.9 + DeskRoomAndMat.matTopY, 0.3) + offset,
            distance: distance,
            pitch: pitchDegrees * .pi / 180,
            yaw: 0,
            fov: fov
        )
    }

    let lock = NSLock()
    let sceneStartTime: CFTimeInterval = CACurrentMediaTime()
    var pose = KeyboardScene.homePose
    var goal = KeyboardScene.homePose
    var lastTime: TimeInterval = 0
    var isCameraSettled = true
    var transientRenderUntil: CFTimeInterval = 0
    var staticBacklightClean = false
    var onRenderIdleChanged: ((Bool) -> Void)?
    private var lastReportedContinuous = true

    func currentSceneTime(_ rawTime: TimeInterval? = nil) -> Float {
        if let rawTime, rawTime > 0 {
            return rawTime >= sceneStartTime ? Float(rawTime - sceneStartTime) : Float(rawTime)
        }
        return Float(CACurrentMediaTime() - sceneStartTime)
    }

    // MARK: Keyboard parts

    let keyboard = SCNNode()
    let modelWorld = SCNNode()
    let scenarioRoot = SCNNode()
    var keyboardShadow: SCNNode?
    var keyLightNode: SCNNode?
    /// xyz = where the current panorama was photographed from, w = its white level; zero without a photo.
    /// The ray tracer uses it to draw the photograph's ground on the ground disc.
    var photoGround = SIMD4<Float>(repeating: 0)
    /// The desk lamp's light: colour (linear RGB, brightest channel 1) and brightness (1 = normal).
    var deskLampTint = DeskLampColor.warm.tint
    var deskLampBrightness: Float = 1.0

    func setDeskLampLight(color: DeskLampColor, brightness: Float) {
        let level = min(max(brightness, 0.3), 2.5)
        guard color.tint != deskLampTint || level != deskLampBrightness else { return }
        deskLampTint = color.tint
        deskLampBrightness = level
        // The bulb and reflector glow in the lamp's own colour.
        func encoded(_ v: Float) -> CGFloat { CGFloat(v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055) }
        let glow = NSColor(srgbRed: encoded(color.tint.x), green: encoded(color.tint.y), blue: encoded(color.tint.z), alpha: 1)
        for item in deskLampEmitters where isDeskLampEnabled {
            item.material.emission.contents = glow
            item.material.emission.intensity = item.baseIntensity * CGFloat(level)
        }
        for item in deskLampLights {
            item.light.color = glow
            item.light.intensity = isDeskLampEnabled ? item.baseIntensity * CGFloat(level) : 0
        }
        deskLampGlow = glow
        materialRevision &+= 1
        bumpTransientRender(seconds: 0.35)
    }
    /// Colour the bulb and reflector glow in while the lamp is on (warm white until a colour is chosen).
    var deskLampGlow = NSColor(srgbRed: 1.0, green: 0.87, blue: 0.70, alpha: 1)
    var fillLightNode: SCNNode?
    var roomLightNode: SCNNode?
    var keyLightBaseIntensity: CGFloat = 760
    var fillLightBaseIntensity: CGFloat = 175
    var roomLightBaseIntensity: CGFloat = 155

    struct HDREnvKey: Hashable {
        let mood: DeskMood
        let deskLampOn: Bool
    }
    var hdrEnvironmentCache: [HDREnvKey: CGImage] = [:]

    struct CachedLightNode {
        let light: SCNLight
        let baseIntensity: CGFloat
    }

    struct CachedEmitterMaterial {
        let material: SCNMaterial
        let onColor: Any
        let baseIntensity: CGFloat
    }

    struct CachedWallGlowNode {
        let node: SCNNode
        let light: CachedLightNode?
    }

    struct CachedAccentNode {
        let light: CachedLightNode?
        let emitter: CachedEmitterMaterial?
    }

    var deskLampLights: [CachedLightNode] = []
    var deskLampEmitters: [CachedEmitterMaterial] = []
    var deskLampWallNodes: [CachedWallGlowNode] = []
    var underDeskGlowAccents: [CachedAccentNode] = []
    var monitorScreenGlowAccents: [CachedAccentNode] = []
    var monitorScreenMaterial: SCNMaterial?
    var monitorGlowLight: SCNLight?
    var appliedWallpaperToken: String = "__unset__"

    var roomRootNode: SCNNode?
    var scenarioNodes: [DeskScenario: SCNNode] = [:]

    var lastDeskLampOn: Bool?
    var lastDeskMood: DeskMood?
    var lastDeskScenario: DeskScenario?

    // Coarse & fine revisions so the hardware path tracer knows what changed in O(1).
    var usesHardwareRayTracer = false
    var topologyRevision: UInt64 = 1
    var materialRevision: UInt64 = 1
    var transformRevision: UInt64 = 1
    var backlightRevision: UInt64 = 1

    var activeMood: DeskMood { lastDeskMood ?? .daylight }
    var activeScenario: DeskScenario { lastDeskScenario ?? .swissAlps }
    var isDeskLampEnabled: Bool { lastDeskLampOn ?? true }

    static func underDeskGlowBase(for mood: DeskMood) -> Float {
        switch mood {
        case .daylight: return 0.85
        case .midnight: return 1.45
        }
    }

    static func monitorGlowScale(for mood: DeskMood) -> Float {
        switch mood {
        case .daylight: return 0.95
        case .midnight: return 1.45
        }
    }

    var underDeskGlowScale: Float {
        let base = Self.underDeskGlowBase(for: activeMood)
        if activeScenario == .room { return base }
        return base * DeskScenarios.lightingProfile(scenario: activeScenario, mood: activeMood).underDeskGlowMultiplier
    }
    var monitorGlowScale: Float {
        Self.monitorGlowScale(for: activeMood)
    }

    var keyTargetY = [Int: Float]()
    var knobCurrentYaw: Float = 0
    var knobTargetYaw: Float = 0
    var wheelCurrentX: Float = 0
    var wheelTargetX: Float = 0
    var wheelCurrentY: Float = 0
    var wheelTargetY: Float = 0
    var wheelHasRestY = false
    var wheelNodeCached: SCNNode? { mouseParts[TechProps.MouseParts.wheel] }
    var heatmapWeights: [Int: Float] = [:]
    var heatmapActive = false
    var capNodes = [Int: SCNNode]()
    var topMaterials = [Int: SCNMaterial]()

    static let plateGlowWidth = 256
    static let plateGlowHeight = 80
    static let plateGlowPlaneW: Float = 16.28
    static let plateGlowPlaneH: Float = 5.10

    struct PlatePixelWeight {
        let offset: Int
        let weight: Float
    }

    struct GlowSlot {
        let index: Int
        let x: Float
        let z: Float
        let col: Int
        let vLevel: Float
        let sideMaterial: SCNMaterial
        let isDark: Bool
        let pixelMask: [PlatePixelWeight]
        var lastR: Int16 = -1
        var lastG: Int16 = -1
        var lastB: Int16 = -1
        var lastSideZero = true
    }
    var glowSlots = ContiguousArray<GlowSlot>()
    let plateGlowMaterial = SCNMaterial()
    var plateGlowAccum = [SIMD3<Float>](repeating: .zero, count: plateGlowWidth * plateGlowHeight)
    var plateGlowBytes = [UInt8](repeating: 0, count: plateGlowWidth * plateGlowHeight * 4)
    var plateGlowAllBlack = true
    var lastKnobR: Int16 = -1
    var lastKnobG: Int16 = -1
    var lastKnobB: Int16 = -1

    var restY = [Int: Float]()
    var keyX = [Int: Float]()
    var keyZ = [Int: Float]()
    var lastMousePressed = Set<Int>()
    var lastMouseLED: NSColor?
    var hasInitializedMouseVisual = false
    lazy var mouseParts: [String: SCNNode] = {
        var out = [String: SCNNode]()
        for name in [TechProps.MouseParts.wheel, TechProps.MouseParts.left, TechProps.MouseParts.right,
                     TechProps.MouseParts.back, TechProps.MouseParts.forward, TechProps.MouseParts.dpiLED] {
            if let node = modelWorld.childNode(withName: name, recursively: true) { out[name] = node }
        }
        return out
    }()
    var mouseWheelRestY: CGFloat?
    lazy var mouseRootNode = modelWorld.childNode(withName: TechProps.MouseParts.root, recursively: true)
    let knob = SCNNode()
    let knobMaterial = SCNMaterial()
    let knobGlowMaterial = SCNMaterial()

    weak var audioMonitor: AudioMonitor?
    var audioSnapshot = AudioSnapshot()
    var musicEngine = MusicLightEngine()

    var legends = [Int: Legend]()
    var pressed = Set<Int>()
    var selected: Int?
    var marked = Set<Int>()
    var lighting = LightingState()

    // MARK: Reactive lighting
    struct ReactiveRipple {
        let x: Float
        let z: Float
        let time: Float
        let hue: Float
    }
    struct ReactiveLaser {
        let z: Float
        let originX: Float
        let time: Float
        let hue: Float
    }
    struct ReactiveFade {
        let time: Float
        let hue: Float
    }

    var ripples: [ReactiveRipple] = []
    var lasers: [ReactiveLaser] = []
    var fades: [Int: ReactiveFade] = [:]
    var pendingReactiveDemo = false

    static let darkKeys: Set<Int> = [
        1 * 16 + 0, 3 * 16 + 13, 5 * 16 + 5, 4 * 16 + 14, 5 * 16 + 13, 5 * 16 + 14, 5 * 16 + 15,
    ]
    static let plateY: Float = 0.62
    static let capBaseY: Float = 0.78

    override init() {
        let perfT0 = E68Perf.enabled ? CACurrentMediaTime() : 0
        super.init()
        DeskTextures.warmStaticTextures()
        buildEnvironment()
        buildKeyboard()
        buildCamera()
        applyPose()
        if E68Perf.enabled {
            E68Perf.logLine(String(format: "KeyboardScene.init: %.1f ms", (CACurrentMediaTime() - perfT0) * 1000.0))
        }
    }

    // MARK: Resources

    static func resourceURL(_ relativePath: String) -> URL? {
        let fm = FileManager.default
        if let resURL = Bundle.main.resourceURL {
            let bundled = resURL.appendingPathComponent(relativePath)
            if fm.fileExists(atPath: bundled.path) { return bundled }
        }
        if let url = Bundle.main.url(forResource: relativePath, withExtension: nil),
           fm.fileExists(atPath: url.path) {
            return url
        }
        // Running straight from `swift build`: walk up from the executable to the project's Resources folder.
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/\(relativePath)")
            if fm.fileExists(atPath: candidate.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        let cwdCandidate = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/\(relativePath)")
        if fm.fileExists(atPath: cwdCandidate.path) { return cwdCandidate }
        return nil
    }

    static func resource(_ name: String) -> NSImage? {
        guard let url = resourceURL(name) else { return nil }
        return NSImage(contentsOf: url)
    }

    static func image(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return ctx.makeImage()!
    }

    // MARK: Camera control

    var needsContinuousRender: Bool {
        lock.lock()
        let active = computeNeedsContinuousRenderLocked(now: CACurrentMediaTime())
        lock.unlock()
        return active
    }

    /// 60 fps while the camera, keys, knob, wheel, or transient user edits are moving; 30 fps for ambient backlight waves.
    var wantsHighFrameRate: Bool {
        let now = CACurrentMediaTime()
        lock.lock()
        let hasSprings = !keyTargetY.isEmpty
            || abs(knobCurrentYaw - knobTargetYaw) > 1e-3
            || abs(wheelCurrentX - wheelTargetX) > 1e-3
            || (wheelHasRestY && abs(wheelCurrentY - wheelTargetY) > 1e-3)
        let high = !isCameraSettled || !pressed.isEmpty || now < transientRenderUntil || hasSprings
        lock.unlock()
        return high
    }

    var isReactiveLightingLocked: Bool {
        !lighting.musicSync && lighting.brightness > 0
            && (lighting.reactiveTypingRipple || lighting.effect == 7 || lighting.effect == 8 || lighting.effect == 9 || lighting.effect == 17)
    }

    func computeNeedsContinuousRenderLocked(now: CFTimeInterval) -> Bool {
        let hasSprings = !keyTargetY.isEmpty
            || abs(knobCurrentYaw - knobTargetYaw) > 1e-3
            || abs(wheelCurrentX - wheelTargetX) > 1e-3
            || (wheelHasRestY && abs(wheelCurrentY - wheelTargetY) > 1e-3)
        if !isCameraSettled || !staticBacklightClean || now < transientRenderUntil || !pressed.isEmpty || pendingReactiveDemo || hasSprings {
            return true
        }
        if lighting.musicSync { return true }
        if lighting.brightness > 0 && lighting.effect != 0 && lighting.effect != 6
            && lighting.effect != 7 && lighting.effect != 8 && lighting.effect != 9 && lighting.effect != 17 {
            return true
        }
        return isReactiveLightingLocked && (!ripples.isEmpty || !lasers.isEmpty || !fades.isEmpty)
    }

    func markRenderActiveIfNeededLocked() -> ((Bool) -> Void)? {
        guard !lastReportedContinuous else { return nil }
        lastReportedContinuous = true
        return onRenderIdleChanged
    }

    func consumeIdleTransitionLocked(now: CFTimeInterval) -> ((Bool) -> Void)? {
        let continuous = computeNeedsContinuousRenderLocked(now: now)
        if !continuous && lastReportedContinuous {
            lastReportedContinuous = false
            return onRenderIdleChanged
        }
        return nil
    }

    func bumpTransientRender(seconds: CFTimeInterval = 0.25) {
        let target = CACurrentMediaTime() + seconds
        lock.lock()
        if target > transientRenderUntil { transientRenderUntil = target }
        let wake = markRenderActiveIfNeededLocked()
        lock.unlock()
        if let wake {
            DispatchQueue.main.async { wake(true) }
        }
    }

    func setGoal(_ pose: Pose, immediately: Bool = false) {
        lock.lock()
        goal = pose
        var wake: ((Bool) -> Void)?
        if immediately {
            self.pose = pose
            isCameraSettled = true
        } else {
            isCameraSettled = false
            wake = markRenderActiveIfNeededLocked()
        }
        lock.unlock()
        if immediately { applyPose() }
        if let wake { DispatchQueue.main.async { wake(true) } }
    }

    /// Drag to look around the desk or keyboard; scroll or pinch to move in and out.
    func orbit(dx: Float, dy: Float, deskMode: Bool = false) {
        lock.lock()
        let yawLimit: Float = deskMode ? 1.45 : 1.0
        let minPitch: Float = (deskMode ? 6 : 22) * .pi / 180
        let maxPitch: Float = (deskMode ? 88 : 86) * .pi / 180
        goal.yaw = min(max(goal.yaw - dx * 0.006, -yawLimit), yawLimit)
        goal.pitch = min(max(goal.pitch + dy * 0.005, minPitch), maxPitch)
        isCameraSettled = false
        let wake = markRenderActiveIfNeededLocked()
        lock.unlock()
        if let wake { DispatchQueue.main.async { wake(true) } }
    }

    func zoom(by factor: Float, deskMode: Bool = false) {
        lock.lock()
        let minD: Float = deskMode ? 14 : 13
        let maxD: Float = deskMode ? 90 : 52
        goal.distance = min(max(goal.distance * factor, minD), maxD)
        isCameraSettled = false
        let wake = markRenderActiveIfNeededLocked()
        lock.unlock()
        if let wake { DispatchQueue.main.async { wake(true) } }
    }

    var currentGoal: Pose { lock.lock(); defer { lock.unlock() }; return goal }

    /// Window aspect, kept current by the view.
    var viewAspect: Float = 1.6

    func setViewAspect(_ aspect: Float) {
        guard aspect.isFinite, aspect > 0 else { return }
        lock.lock()
        let changed = abs(aspect - viewAspect) > 1e-4
        viewAspect = aspect
        lock.unlock()
        if changed {
            applyPose()
            transformRevision &+= 1
        }
    }

    func applyPose() {
        lock.lock()
        let p = pose
        let aspect = viewAspect
        lock.unlock()
        // Baseline hero framing is tuned around 16:10 (1.6); widen distance gently when resized very narrow or ultrawide.
        let aspectScale: Float
        if aspect < 1.42 {
            aspectScale = min(1.30, 1.42 / max(aspect, 0.85))
        } else if aspect > 1.72 {
            aspectScale = min(1.22, sqrt(aspect / 1.72))
        } else {
            aspectScale = 1.0
        }
        let rotation = simd_quatf(angle: p.yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -p.pitch, axis: SIMD3(1, 0, 0))
        cameraNode.simdOrientation = rotation
        cameraNode.simdPosition = p.target + rotation.act(SIMD3(0, 0, p.distance * aspectScale))
        cameraNode.camera?.fieldOfView = CGFloat(p.fov)
    }

}
