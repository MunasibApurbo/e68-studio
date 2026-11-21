import Foundation
import Metal
import MetalKit
import SceneKit
import AppKit
import MetalFX
import Darwin
import simd


/// Hardware-accelerated Metal ray-traced path tracer with scaled interactive orbit rendering
/// and progressive full-resolution accumulation + idle sleep (`0%` GPU when converged).
final class PathTracerRenderer: NSObject {
    /// Full-resolution samples refined on top of the denoised image once everything is still.
    static let maxProgressiveSamples: UInt32 = 64
    /// Denoised frames shown after a change before refinement starts (history kept / history rebuilt).
    private static let denoisedFramesAfterChange = 6
    private static let denoisedFramesAfterReset = 16

    /// The live renderer (stored soft light + exact rays, nothing to denoise or refine) draws the desk.
    /// `-e68.live NO` switches back to the path tracer, which stays as the reference it is checked against.
    static let liveMode = UserDefaults.standard.object(forKey: "e68.live") == nil || UserDefaults.standard.bool(forKey: "e68.live")

    static func isSupported(device: MTLDevice) -> Bool {
        device.supportsRaytracing
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let extractor: RTSceneExtractor

    private let shaderLib: MTLLibrary
    private var pathTracePipeline: MTLComputePipelineState?
    private var accumulatePipeline: MTLComputePipelineState?
    let compositePipeline: MTLComputePipelineState
    private let pickPipeline: MTLComputePipelineState

    private let pickResultBuffer: MTLBuffer

    // Live renderer: bake + frame kernels, full-resolution targets and temporal anti-aliasing.
    private let lightCacheBakePipeline: MTLComputePipelineState?
    private let liveFramePipeline: MTLComputePipelineState?
    let lensBlurPipeline: MTLComputePipelineState?
    var liveBlurredTex: MTLTexture?
    /// `-e68.lensBlur YES` turns on the depth-of-field pass. Off by default: it softened close views.
    static let lensBlurEnabled = UserDefaults.standard.bool(forKey: "e68.lensBlur")
    var liveAntialiaser: MTLFXTemporalScaler?
    var liveColorTex: MTLTexture?
    var liveDepthTex: MTLTexture?
    var liveMotionTex: MTLTexture?
    var liveResolvedTex: MTLTexture?
    // Switching world or time of day rebuilds the stored light, which takes a few seconds to settle and
    // looks speckled until it has. The last finished frame is held and the new one dissolved in over it,
    // so the fill-in is never on screen. A launch dissolves in from black the same way.
    var liveHeldTex: MTLTexture?
    var liveLastPresented: MTLTexture?
    var lightDissolveActive = false
    var lightDissolveAwaitingReset = false
    var lightDissolveFrames = 0
    var lightDissolveMovingFrames = 0
    var dissolveScenario: DeskScenario?
    var dissolveMood: DeskMood?
    var bakedScenario: DeskScenario?
    var bakedMood: DeskMood?
    var bakedCacheGeneration = -1
    var bakedDiscreteKey: UInt64 = 0
    var bakedLightHash: UInt64 = 0
    var bakePassesSinceChange = 0
    var bakeCursor = 0
    var bakeDispatches: UInt32 = 0
    var gradualBakeRefresh = false
    var fastBakeRefresh = false
    var cachedMaterialsRev: UInt64 = UInt64.max
    var cachedMaterialsHash: UInt64 = 0
    var savedCacheKeys: Set<UInt64> = []
    var pendingSaveKey: UInt64 = 0
    var liveStillFrames = 0
    var targetsAreLive = false
    /// Full passes over the cache after which the stored light is treated as converged.
    static let bakePassesToConverge = 112
    /// Full passes over the cache for a gradual refresh so old lighting decays completely before saving.
    static let gradualBakePassesToConverge = 200
    static let useDiskLightCache = !UserDefaults.standard.bool(forKey: "e68.noLightCache")
    static let cacheIOQueue = DispatchQueue(label: "E68Studio.LightCacheIO", qos: .utility)

    // MetalFX temporal denoised upscaler & G-buffer targets (Gear 1)
    private var scaler: MTLFXTemporalDenoisedScaler?
    private var interactiveSize: SIMD2<UInt32> = .zero
    var outputSize: SIMD2<UInt32> = .zero

    private var traceColorTex: MTLTexture?
    private var traceDepthTex: MTLTexture?
    private var traceMotionTex: MTLTexture?
    private var traceDiffTex: MTLTexture?
    private var traceSpecTex: MTLTexture?
    private var traceNormTex: MTLTexture?
    private var traceRoughTex: MTLTexture?
    private var traceHitTex: MTLTexture?
    private var traceReactTex: MTLTexture?
    private var metalFXOutputTex: MTLTexture?

    // Full-resolution progressive targets (1x1 dummy G-buffers since Gear 2 skips G-buffer writes).
    private var progColorTex: MTLTexture?
    private var dummyDepthTex: MTLTexture?
    private var dummyMotionTex: MTLTexture?
    private var dummyDiffTex: MTLTexture?
    private var dummySpecTex: MTLTexture?
    private var dummyNormTex: MTLTexture?
    private var dummyRoughTex: MTLTexture?
    private var dummyHitTex: MTLTexture?
    private var dummyReactTex: MTLTexture?
    private var accumTex: MTLTexture?

    // Frame state
    var frameIndex: UInt32 = 0
    var sampleIndex: UInt32 = 0
    var isSettledForSleep: Bool = false

    var prevViewProj: simd_float4x4 = matrix_identity_float4x4
    var prevJitter: SIMD2<Float> = .zero
    var hasPrevFrame = false
    var pendingHistoryReset = true
    private var hasValidMetalFXFrame = false
    private var accumWasSeededFromMFX = false
    private var denoisedFramesOwed = 0

    var lastSceneTopology: UInt64 = 0
    var lastSceneMaterials: UInt64 = 0
    var lastSceneTransforms: UInt64 = 0
    var lastSceneBacklight: UInt64 = 0
    var lastMood: DeskMood?
    var lastCameraGoal: KeyboardScene.Pose?

    let inFlightLock = NSLock()
    var inFlightFrames: Int = 0

    /// Callback invoked whenever progressive accumulation completes so the host `MTKView` can pause cleanly.
    var onProgressiveSettled: ((Bool) -> Void)?

    init?(device: MTLDevice) {
        let perfT0 = E68Perf.enabled ? CACurrentMediaTime() : 0
        guard device.supportsRaytracing, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        self.extractor = RTSceneExtractor(device: device, commandQueue: queue)

        do {
            let shaderT0 = E68Perf.enabled ? CACurrentMediaTime() : 0
            let opts = MTLCompileOptions()
            opts.mathMode = .fast
            let source = Self.liveMode ? RTShaders.source + RTLiveShaders.source : RTShaders.source
            let lib = try device.makeLibrary(source: source, options: opts)
            self.shaderLib = lib
            guard let compFn = lib.makeFunction(name: "compositeKernel"),
                  let pickFn = lib.makeFunction(name: "pickInstanceKernel") else {
                return nil
            }
            self.compositePipeline = try device.makeComputePipelineState(function: compFn)
            self.pickPipeline = try device.makeComputePipelineState(function: pickFn)
            if Self.liveMode, let bakeFn = lib.makeFunction(name: "lightCacheBakeKernel"),
               let liveFn = lib.makeFunction(name: "liveKernel") {
                self.lightCacheBakePipeline = try device.makeComputePipelineState(function: bakeFn)
                self.liveFramePipeline = try device.makeComputePipelineState(function: liveFn)
                self.lensBlurPipeline = try lib.makeFunction(name: "lensBlurKernel").map { try device.makeComputePipelineState(function: $0) }
            } else {
                self.lightCacheBakePipeline = nil
                self.liveFramePipeline = nil
                self.lensBlurPipeline = nil
            }
            if !Self.liveMode || self.liveFramePipeline == nil {
                guard let ptFn = lib.makeFunction(name: "pathTraceKernel"),
                      let accFn = lib.makeFunction(name: "accumulateKernel") else {
                    return nil
                }
                self.pathTracePipeline = try device.makeComputePipelineState(function: ptFn)
                self.accumulatePipeline = try device.makeComputePipelineState(function: accFn)
            }
            if E68Perf.enabled {
                E68Perf.logLine(String(format: "shader+pipeline compile: %.1f ms (total PathTracerRenderer.init so far: %.1f ms)",
                                       (CACurrentMediaTime() - shaderT0) * 1000.0,
                                       (CACurrentMediaTime() - perfT0) * 1000.0))
            }
        } catch {
            NSLog("PathTracerRenderer shader compilation error: \(error)")
            return nil
        }

        self.pickResultBuffer = device.makeBuffer(length: 16, options: .storageModeShared)!
        super.init()
        if !Self.liveMode || self.liveFramePipeline == nil {
            _ = ensurePathTracerResources()
        }
    }

    @discardableResult
    private func ensurePathTracerResources() -> Bool {
        if pathTracePipeline == nil {
            guard let ptFn = shaderLib.makeFunction(name: "pathTraceKernel"),
                  let pt = try? device.makeComputePipelineState(function: ptFn) else { return false }
            pathTracePipeline = pt
        }
        if accumulatePipeline == nil {
            guard let accFn = shaderLib.makeFunction(name: "accumulateKernel"),
                  let acc = try? device.makeComputePipelineState(function: accFn) else { return false }
            accumulatePipeline = acc
        }
        if dummyDepthTex == nil {
            let rw: MTLTextureUsage = [.shaderRead, .shaderWrite]
            dummyDepthTex = Self.makePrivateTex(device: device, format: .r32Float, w: 1, h: 1, usage: rw)
            dummyMotionTex = Self.makePrivateTex(device: device, format: .rg16Float, w: 1, h: 1, usage: rw)
            dummyDiffTex = Self.makePrivateTex(device: device, format: .rgba16Float, w: 1, h: 1, usage: rw)
            dummySpecTex = Self.makePrivateTex(device: device, format: .rgba16Float, w: 1, h: 1, usage: rw)
            dummyNormTex = Self.makePrivateTex(device: device, format: .rgba16Float, w: 1, h: 1, usage: rw)
            dummyRoughTex = Self.makePrivateTex(device: device, format: .r16Float, w: 1, h: 1, usage: rw)
            dummyHitTex = Self.makePrivateTex(device: device, format: .r16Float, w: 1, h: 1, usage: rw)
            dummyReactTex = Self.makePrivateTex(device: device, format: .r8Unorm, w: 1, h: 1, usage: rw)
        }
        return true
    }

    /// Wakes progressive accumulation cleanly when the scene or window changes.
    func invalidateAccumulation(resetTemporalHistory: Bool = false) {
        sampleIndex = 0
        isSettledForSleep = false
        accumWasSeededFromMFX = false
        if resetTemporalHistory {
            pendingHistoryReset = true
            hasValidMetalFXFrame = false
        }
        if scaler != nil {
            denoisedFramesOwed = max(denoisedFramesOwed, resetTemporalHistory ? Self.denoisedFramesAfterReset : Self.denoisedFramesAfterChange)
        }
    }

    /// Wakes a settled view to check whether anything actually changed without resetting accumulation.
    func wakeForCheckOnly(world: KeyboardScene? = nil) {
        guard isSettledForSleep else { return }
        if let world {
            let dirty = world.needsContinuousRender
                || !world.isCameraSettled
                || lastSceneTopology != world.topologyRevision
                || lastSceneMaterials != world.materialRevision
                || lastSceneTransforms != world.transformRevision
                || lastSceneBacklight != world.backlightRevision
                || lastMood != world.activeMood
                || lastCameraGoal != world.currentGoal
                || extractor.hasAutonomousChange()
            if !dirty {
                return
            }
        }
        isSettledForSleep = false
    }

    // MARK: - Live Interactive + Progressive Render Loop

    func draw(in view: MTKView, world: KeyboardScene) {
        inFlightLock.lock()
        let currentInFlight = inFlightFrames
        inFlightLock.unlock()
        let interactiveHint = world.needsContinuousRender || !world.isCameraSettled || (scaler != nil && !hasValidMetalFXFrame)
        if currentInFlight >= (interactiveHint ? 2 : 1) {
            return
        }

        guard let drawable = view.currentDrawable else { return }
        renderFrame(world: world, target: drawable.texture, drawable: drawable, time: CACurrentMediaTime())
    }

    /// Encodes and commits one live frame into `target`, presenting `drawable` when there is one.
    /// The window passes its drawable; `--render-motion` passes an offscreen texture and no drawable.
    @discardableResult
    func renderFrame(world: KeyboardScene, target: MTLTexture, drawable: MTLDrawable?, time: CFTimeInterval) -> MTLCommandBuffer? {
        let outW = max(16, target.width)
        let outH = max(16, target.height)

        world.viewAspect = Float(outW) / Float(outH)
        let perfOn = E68Perf.enabled
        let stepT0 = perfOn ? CACurrentMediaTime() : 0
        world.stepFrame(atTime: time)
        let stepMs = perfOn ? (CACurrentMediaTime() - stepT0) * 1000.0 : 0

        let syncT0 = perfOn ? CACurrentMediaTime() : 0
        let sync = extractor.sync(with: world)
        let syncMs = perfOn ? (CACurrentMediaTime() - syncT0) * 1000.0 : 0
        ensureTargetsAllocated(outputWidth: outW, outputHeight: outH)

        if let bake = lightCacheBakePipeline, let live = liveFramePipeline {
            return renderLiveFrame(world: world, target: target, drawable: drawable, sync: sync,
                                   bakePipeline: bake, framePipeline: live, stepMs: stepMs, syncMs: syncMs)
        }

        let goal = world.currentGoal
        let cameraMoving = !world.isCameraSettled
        // The denoiser's history only becomes useless when the picture itself is replaced: rebuilt geometry,
        // another scenario or mood. Camera motion is not such a change. Motion vectors carry the history
        // along with the camera, and throwing it away on every drag event left each frame denoised from a
        // single sample, which is what made moving frames blotchy.
        let historyBroken = sync.geometryChanged || sync.motionResetNeeded
            || lastSceneTopology != world.topologyRevision
            || (lastMood != nil && lastMood != world.activeMood)
        let viewChanged = historyBroken || cameraMoving
            || lastSceneMaterials != world.materialRevision
            || lastCameraGoal != goal
        let lightingOrKeysChanged = lastSceneTransforms != world.transformRevision
            || lastSceneBacklight != world.backlightRevision
            || sync.dynamicLightingChanged
        let animating = world.needsContinuousRender || cameraMoving

        if historyBroken { pendingHistoryReset = true }
        if viewChanged || lightingOrKeysChanged || animating {
            lastSceneTopology = world.topologyRevision
            lastSceneMaterials = world.materialRevision
            lastSceneTransforms = world.transformRevision
            lastSceneBacklight = world.backlightRevision
            lastMood = world.activeMood
            lastCameraGoal = goal
            isSettledForSleep = false
            if scaler != nil {
                // Every change is shown through the denoiser first, so nothing ever restarts from raw noise.
                // A fresh history needs a few more frames before it is clean enough to refine from.
                sampleIndex = 0
                denoisedFramesOwed = max(denoisedFramesOwed, pendingHistoryReset ? Self.denoisedFramesAfterReset : Self.denoisedFramesAfterChange)
            } else {
                // No denoiser on this GPU: restart on a new view, blend quickly into lighting-only changes.
                sampleIndex = viewChanged ? 0 : min(sampleIndex, 2)
            }
        }

        let useMetalFXOnly = scaler != nil && (animating || denoisedFramesOwed > 0 || !hasValidMetalFXFrame)

        guard let cmd = commandQueue.makeCommandBuffer() else { return nil }
        extractor.encodePendingWork(onto: cmd)

        if useMetalFXOnly, let fxScaler = scaler, let mfxOut = metalFXOutputTex {
            sampleIndex = 0
            isSettledForSleep = false
            denoisedFramesOwed = max(0, denoisedFramesOwed - 1)
            // Full sub-pixel jitter, moving or still: the upscaler rebuilds full-resolution detail from where
            // each frame's samples landed, so shrinking the jitter leaves a blocky enlarged image instead.
            let jitter = haltonJitter(index: frameIndex)
            let renderSz = interactiveSize
            let (uniforms, curVP) = extractor.buildFrameUniforms(
                world: world,
                renderSize: renderSz,
                outputSize: outputSize,
                jitter: jitter,
                prevJitter: prevJitter,
                prevViewProj: hasPrevFrame ? prevViewProj : matrix_identity_float4x4,
                frameIndex: frameIndex,
                sampleIndex: 0,
                maxBounces: RTSharedTypes.maxBouncesInteractive,
                isProgressive: false
            )
            var frameUniforms = uniforms
            if !hasPrevFrame {
                frameUniforms.prevViewProj = curVP
            }

            encodePathTraceWithBytes(
                cmd: cmd,
                size: renderSz,
                uniforms: &frameUniforms,
                colorTex: traceColorTex!,
                depthTex: traceDepthTex!,
                motionTex: traceMotionTex!,
                diffTex: traceDiffTex!,
                specTex: traceSpecTex!,
                normTex: traceNormTex!,
                roughTex: traceRoughTex!,
                hitTex: traceHitTex!,
                reactTex: traceReactTex!
            )

            fxScaler.colorTexture = traceColorTex
            fxScaler.depthTexture = traceDepthTex
            fxScaler.motionTexture = traceMotionTex
            fxScaler.diffuseAlbedoTexture = traceDiffTex
            fxScaler.specularAlbedoTexture = traceSpecTex
            fxScaler.normalTexture = traceNormTex
            fxScaler.roughnessTexture = traceRoughTex
            fxScaler.specularHitDistanceTexture = traceHitTex
            fxScaler.reactiveMaskTexture = traceReactTex
            fxScaler.outputTexture = mfxOut
            // MetalFX wants the offset that brings the jittered sample back to the pixel centre.
            fxScaler.jitterOffsetX = -jitter.x
            fxScaler.jitterOffsetY = -jitter.y
            fxScaler.motionVectorScaleX = 1.0
            fxScaler.motionVectorScaleY = 1.0
            fxScaler.isDepthReversed = false
            fxScaler.preExposure = 1.0
            fxScaler.shouldResetHistory = pendingHistoryReset || !hasPrevFrame
            fxScaler.worldToViewMatrix = frameUniforms.worldToView
            fxScaler.viewToClipMatrix = frameUniforms.viewToClip
            fxScaler.encode(commandBuffer: cmd)

            pendingHistoryReset = false
            hasValidMetalFXFrame = true
            prevViewProj = curVP
            prevJitter = jitter
            hasPrevFrame = true

            encodeComposite(
                cmd: cmd,
                srcTex: mfxOut,
                outTexture: target,
                progressBlend: 0.0,
                isProgressiveOnly: false,
                uniforms: frameUniforms
            )
        } else {
            // Stationary Gear 2: Full-resolution progressive path tracing seeded directly from MetalFX to prevent any noise burst.
            if sampleIndex < Self.maxProgressiveSamples {
                let jitter = r2Jitter(index: sampleIndex)
                var (frameUniforms, curVP) = extractor.buildFrameUniforms(
                    world: world,
                    renderSize: outputSize,
                    outputSize: outputSize,
                    jitter: jitter,
                    prevJitter: prevJitter,
                    prevViewProj: hasPrevFrame ? prevViewProj : curVPIdentity(world: world, outW: outW, outH: outH),
                    frameIndex: frameIndex,
                    sampleIndex: sampleIndex,
                    maxBounces: RTSharedTypes.maxBouncesProgressive,
                    isProgressive: true
                )
                if sampleIndex == 0 {
                    accumWasSeededFromMFX = hasValidMetalFXFrame && (scaler != nil) && (metalFXOutputTex != nil)
                }
                frameUniforms.renderFlags = accumWasSeededFromMFX ? 5 : 1

                encodePathTraceWithBytes(
                    cmd: cmd,
                    size: outputSize,
                    uniforms: &frameUniforms,
                    colorTex: progColorTex!,
                    depthTex: dummyDepthTex!,
                    motionTex: dummyMotionTex!,
                    diffTex: dummyDiffTex!,
                    specTex: dummySpecTex!,
                    normTex: dummyNormTex!,
                    roughTex: dummyRoughTex!,
                    hitTex: dummyHitTex!,
                    reactTex: dummyReactTex!
                )
                encodeAccumulateWithBytes(
                    cmd: cmd,
                    size: outputSize,
                    uniforms: &frameUniforms,
                    traceTex: progColorTex!,
                    accumTex: accumTex!,
                    mfxSeed: metalFXOutputTex ?? progColorTex!
                )

                encodeComposite(
                    cmd: cmd,
                    srcTex: nil,
                    outTexture: target,
                    progressBlend: 1.0,
                    isProgressiveOnly: true,
                    uniforms: frameUniforms
                )

                prevViewProj = curVP
                prevJitter = jitter
                hasPrevFrame = true
                sampleIndex &+= 1
            } else {
                // Reached converged spp -> composite crisp final buffer & signal idle sleep (0% GPU!)
                let (uniforms, _) = extractor.buildFrameUniforms(
                    world: world,
                    renderSize: outputSize,
                    outputSize: outputSize,
                    jitter: .zero,
                    prevJitter: .zero,
                    prevViewProj: prevViewProj,
                    frameIndex: frameIndex,
                    sampleIndex: sampleIndex,
                    maxBounces: RTSharedTypes.maxBouncesProgressive,
                    isProgressive: true
                )
                encodeComposite(
                    cmd: cmd,
                    srcTex: nil,
                    outTexture: target,
                    progressBlend: 1.0,
                    isProgressiveOnly: true,
                    uniforms: uniforms
                )
                if !isSettledForSleep {
                    isSettledForSleep = true
                    if perfOn {
                        E68Perf.markSettled(sampleIndex: sampleIndex, texCount: extractor.textures.count)
                        logGPUMemory()
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.onProgressiveSettled?(true)
                    }
                }
            }
        }

        let activeGear: String
        let activeInternalSize: SIMD2<UInt32>
        if useMetalFXOnly {
            activeGear = "gear1-mfx"
            activeInternalSize = interactiveSize
        } else if sampleIndex <= Self.maxProgressiveSamples && !isSettledForSleep {
            activeGear = "gear2-prog"
            activeInternalSize = outputSize
        } else {
            activeGear = "gear2-idle"
            activeInternalSize = outputSize
        }

        inFlightLock.lock()
        inFlightFrames += 1
        inFlightLock.unlock()

        if perfOn {
            let capturedGear = activeGear
            E68Perf.recordCPUFrame(
                gear: activeGear,
                internalSize: activeInternalSize,
                outputSize: outputSize,
                sampleIndex: sampleIndex,
                maxProgressiveSamples: Self.maxProgressiveSamples,
                stepMs: stepMs,
                syncMs: syncMs,
                texCount: extractor.textures.count
            )
            cmd.addCompletedHandler { [weak self] cb in
                if let self {
                    self.inFlightLock.lock()
                    self.inFlightFrames = max(0, self.inFlightFrames - 1)
                    self.inFlightLock.unlock()
                }
                if let error = cb.error { E68Perf.logLine("command buffer failed: \(error.localizedDescription)") }
                let gpuMs = cb.gpuEndTime > cb.gpuStartTime ? (cb.gpuEndTime - cb.gpuStartTime) * 1000.0 : 0.0
                E68Perf.recordCompletedGPU(gpuMs: gpuMs, gear: capturedGear)
            }
        } else {
            cmd.addCompletedHandler { [weak self] _ in
                guard let self else { return }
                self.inFlightLock.lock()
                self.inFlightFrames = max(0, self.inFlightFrames - 1)
                self.inFlightLock.unlock()
            }
        }

        if let captureDirectory {
            encodeFrameCapture(cmd: cmd, source: target, directory: captureDirectory, gear: activeGear)
        }

        lastGear = activeGear
        if let drawable { cmd.present(drawable) }
        cmd.commit()
        frameIndex &+= 1
        return cmd
    }


    // MARK: - Frame Capture (`-e68.perf YES -e68.perfCapture <dir>`, or `--render-motion <dir>`)

    /// Saves what was actually presented, so motion and settle quality can be reviewed frame by frame.
    var captureDirectory: String? = E68Perf.enabled ? UserDefaults.standard.string(forKey: "e68.perfCapture") : nil
    /// Which path drew the last frame: denoised motion, progressive refinement, or the settled image.
    var lastGear = ""
    var capturedFrames = 0

    var lastCapturedGear = ""
    var framesSinceGearChange = 0


    // MARK: - Offline High-Quality Render (`--render`)

    func renderOfflineShot(world: KeyboardScene, width: Int, height: Int, samples: UInt32 = 48) -> NSImage? {
        world.viewAspect = Float(width) / Float(max(1, height))
        world.flushAnimations()
        world.stepFrame(atTime: world.lastTime > 0 ? world.lastTime : 1.0)
        extractor.sync(with: world)
        extractor.commitPreviousTransforms()

        ensureTargetsAllocated(outputWidth: width, outputHeight: height, forPathTracer: true)

        let finalDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
        )
        finalDesc.usage = [.shaderWrite, .shaderRead]
        finalDesc.storageMode = .shared
        guard let outTex = device.makeTexture(descriptor: finalDesc) else { return nil }

        // Encode in small 8-sample command batches so macOS GPU watchdog never triggers.
        let batchSize: UInt32 = 8
        var s: UInt32 = 0
        var flushedPending = false
        while s < samples {
            guard let cmd = commandQueue.makeCommandBuffer() else { return nil }
            if !flushedPending {
                extractor.encodePendingWork(onto: cmd)
                flushedPending = true
            }
            let endS = min(samples, s + batchSize)
            var lastUniforms: RTFrameUniforms?
            while s < endS {
                let jitter = r2Jitter(index: s)
                let (u, curVP) = extractor.buildFrameUniforms(
                    world: world,
                    renderSize: outputSize,
                    outputSize: outputSize,
                    jitter: jitter,
                    prevJitter: jitter,
                    prevViewProj: matrix_identity_float4x4,
                    frameIndex: s + 17,
                    sampleIndex: s,
                    maxBounces: RTSharedTypes.maxBouncesProgressive,
                    isProgressive: true
                )
                var patched = u
                patched.prevViewProj = curVP
                lastUniforms = patched

                encodePathTraceWithBytes(
                    cmd: cmd,
                    size: outputSize,
                    uniforms: &patched,
                    colorTex: progColorTex!,
                    depthTex: dummyDepthTex!,
                    motionTex: dummyMotionTex!,
                    diffTex: dummyDiffTex!,
                    specTex: dummySpecTex!,
                    normTex: dummyNormTex!,
                    roughTex: dummyRoughTex!,
                    hitTex: dummyHitTex!,
                    reactTex: dummyReactTex!
                )
                encodeAccumulateWithBytes(cmd: cmd, size: outputSize, uniforms: &patched, traceTex: progColorTex!, accumTex: accumTex!)
                s &+= 1
            }
            if s == samples, let u = lastUniforms {
                encodeComposite(
                    cmd: cmd,
                    outTexture: outTex,
                    progressBlend: 1.0,
                    isProgressiveOnly: true,
                    uniforms: u
                )
            }
            cmd.commit()
            cmd.waitUntilCompleted()
        }

        // Convert RGBA8 GPU texture -> CGImage -> NSImage cleanly
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        outTex.getBytes(&rgba, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: cs, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    // MARK: - Instant 1-Ray Hardware BVH Node Picking

    func pickNode(at viewPoint: CGPoint, in boundsSize: CGSize, world: KeyboardScene) -> SCNNode? {
        guard boundsSize.width > 1 && boundsSize.height > 1 else { return nil }
        world.viewAspect = Float(boundsSize.width / boundsSize.height)
        extractor.sync(with: world)

        guard let accel = extractor.instanceAS, let cmd = commandQueue.makeCommandBuffer() else { return nil }
        extractor.encodePendingWork(onto: cmd)
        guard let enc = cmd.makeComputeCommandEncoder() else { return nil }

        let sz = SIMD2<UInt32>(UInt32(max(1, Int(boundsSize.width))), UInt32(max(1, Int(boundsSize.height))))
        var (u, _) = extractor.buildFrameUniforms(
            world: world, renderSize: sz, outputSize: sz, jitter: .zero, prevJitter: .zero,
            prevViewProj: matrix_identity_float4x4, frameIndex: 0, sampleIndex: 0, maxBounces: 1, isProgressive: false
        )
        // AppKit view y=0 is bottom; normalize top-down y in [0,1]
        var normPt = SIMD2<Float>(
            Float(viewPoint.x / boundsSize.width),
            Float(1.0 - viewPoint.y / boundsSize.height)
        )

        enc.setComputePipelineState(pickPipeline)
        enc.setBytes(&u, length: MemoryLayout<RTFrameUniforms>.stride, index: 0)
        enc.setBytes(&normPt, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        enc.setAccelerationStructure(accel, bufferIndex: 2)
        enc.setBuffer(extractor.instanceBuffer, offset: 0, index: 3)
        enc.setBuffer(extractor.submeshBuffer, offset: 0, index: 4)
        enc.setBuffer(extractor.materialBuffer, offset: 0, index: 5)
        enc.setBuffer(pickResultBuffer, offset: 0, index: 6)
        enc.useResources(extractor.primitiveBLASes, usage: .read)
        enc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        let tag = pickResultBuffer.contents().assumingMemoryBound(to: UInt32.self).pointee
        return extractor.node(forTag: tag)
    }

    /// `-e68.perf YES`: where the GPU memory goes, largest textures first.
    func logGPUMemory(label: String = "") {
        func mb(_ bytes: Int) -> Double { Double(bytes) / 1_048_576.0 }
        let texBytes = extractor.textures.map(\.allocatedSize)
        let blasBytes = extractor.primitiveBLASes.reduce(0) { $0 + $1.size }
        let prefix = label.isEmpty ? "" : "[\(label)] "
        E68Perf.logLine(String(format: "%@gpu memory: device=%.0f MB | scene textures=%.0f MB (%d) | blas=%.0f MB (%d) | rss=%.1f MB",
                               prefix, mb(device.currentAllocatedSize), mb(texBytes.reduce(0, +)), texBytes.count,
                               mb(blasBytes), extractor.primitiveBLASes.count, E68Perf.residentMemoryMB()))
        let top = extractor.textures.sorted { $0.allocatedSize > $1.allocatedSize }.prefix(14)
        E68Perf.logLine("largest textures: " + top.map {
            String(format: "%dx%d %.0fMB", $0.width, $0.height, mb($0.allocatedSize))
        }.joined(separator: ", "))
    }

    // MARK: - Render Target Allocation

    func ensureTargetsAllocated(outputWidth: Int, outputHeight: Int, forPathTracer: Bool = false) {
        let newOut = SIMD2<UInt32>(UInt32(outputWidth), UInt32(outputHeight))
        let wantsLive = liveFramePipeline != nil && !forPathTracer
        guard newOut != outputSize || wantsLive != targetsAreLive else { return }
        targetsAreLive = wantsLive
        outputSize = newOut
        hasPrevFrame = false
        pendingHistoryReset = true
        hasValidMetalFXFrame = false
        accumWasSeededFromMFX = false
        sampleIndex = 0
        isSettledForSleep = false

        if wantsLive {
            let rw: MTLTextureUsage = [.shaderRead, .shaderWrite]
            liveAntialiaser = nil
            if MTLFXTemporalScalerDescriptor.supportsDevice(device) {
                let aa = MTLFXTemporalScalerDescriptor()
                aa.colorTextureFormat = .rgba16Float
                aa.depthTextureFormat = .r32Float
                aa.motionTextureFormat = .rg16Float
                aa.outputTextureFormat = .rgba16Float
                aa.inputWidth = outputWidth
                aa.inputHeight = outputHeight
                aa.outputWidth = outputWidth
                aa.outputHeight = outputHeight
                aa.isAutoExposureEnabled = false
                aa.requiresSynchronousInitialization = true
                liveAntialiaser = aa.makeTemporalScaler(device: device)
            }
            liveColorTex = makePrivateTex(.rgba16Float, w: outputWidth, h: outputHeight, usage: rw.union(liveAntialiaser?.colorTextureUsage ?? []))
            liveDepthTex = makePrivateTex(.r32Float, w: outputWidth, h: outputHeight, usage: rw.union(liveAntialiaser?.depthTextureUsage ?? []))
            liveMotionTex = makePrivateTex(.rg16Float, w: outputWidth, h: outputHeight, usage: rw.union(liveAntialiaser?.motionTextureUsage ?? []))
            liveResolvedTex = makePrivateTex(.rgba16Float, w: outputWidth, h: outputHeight, usage: rw.union(liveAntialiaser?.outputTextureUsage ?? []))
            liveHeldTex = makePrivateTex(.rgba16Float, w: outputWidth, h: outputHeight, usage: rw.union(.renderTarget))
            liveLastPresented = nil
            lightDissolveActive = false
            liveBlurredTex = lensBlurPipeline != nil && Self.lensBlurEnabled ? makePrivateTex(.rgba16Float, w: outputWidth, h: outputHeight, usage: rw) : nil
            // Release any path-tracer / denoiser targets when running in live mode; `accumTex` stays 1x1 for composite's slot.
            scaler = nil
            traceColorTex = nil; traceDepthTex = nil; traceMotionTex = nil; traceDiffTex = nil; traceSpecTex = nil
            traceNormTex = nil; traceRoughTex = nil; traceHitTex = nil; traceReactTex = nil
            metalFXOutputTex = nil; progColorTex = nil
            accumTex = makePrivateTex(.rgba16Float, w: 1, h: 1, usage: rw)
            if E68Perf.enabled {
                E68Perf.logLine("live targets: \(outputWidth)x\(outputHeight) antialiasing=\(liveAntialiaser != nil ? "on" : "off")")
            }
            return
        }

        _ = ensurePathTracerResources()
        liveAntialiaser = nil
        liveColorTex = nil; liveDepthTex = nil; liveMotionTex = nil; liveResolvedTex = nil; liveBlurredTex = nil
        liveHeldTex = nil; liveLastPresented = nil; lightDissolveActive = false

        let supportsFX = MTLFXTemporalDenoisedScalerDescriptor.supportsDevice(device)
        let desiredScale: Float
        if supportsFX {
            let minScale = MTLFXTemporalDenoisedScalerDescriptor.supportedInputContentMinScale(device: device)
            let maxScale = MTLFXTemporalDenoisedScalerDescriptor.supportedInputContentMaxScale(device: device)
            let minDownscale = minScale < 1.0 ? minScale : (1.0 / max(1.0, maxScale))
            let maxDownscale = maxScale <= 1.0 ? maxScale : (1.0 / max(1.0, minScale))
            // Half resolution per axis while things move: with history kept across camera motion the rebuilt
            // image is as sharp as at 0.62, and the frame fits a 60 fps budget (12 ms against 25 ms on an M4).
            desiredScale = min(max(0.5, max(0.35, minDownscale)), min(1.0, maxDownscale))
        } else {
            desiredScale = 0.75
        }
        let inW = max(16, Int((Float(outputWidth) * desiredScale).rounded()))
        let inH = max(16, Int((Float(outputHeight) * desiredScale).rounded()))
        interactiveSize = SIMD2<UInt32>(UInt32(inW), UInt32(inH))

        let allocT0 = E68Perf.enabled ? CACurrentMediaTime() : 0
        if supportsFX {
            let fxDesc = MTLFXTemporalDenoisedScalerDescriptor()
            fxDesc.colorTextureFormat = .rgba16Float
            fxDesc.depthTextureFormat = .r32Float
            fxDesc.motionTextureFormat = .rg16Float
            fxDesc.diffuseAlbedoTextureFormat = .rgba16Float
            fxDesc.specularAlbedoTextureFormat = .rgba16Float
            fxDesc.normalTextureFormat = .rgba16Float
            fxDesc.roughnessTextureFormat = .r16Float
            fxDesc.specularHitDistanceTextureFormat = .r16Float
            fxDesc.reactiveMaskTextureFormat = .r8Unorm
            fxDesc.outputTextureFormat = .rgba16Float
            fxDesc.isSpecularHitDistanceTextureEnabled = true
            fxDesc.isReactiveMaskTextureEnabled = true
            fxDesc.isAutoExposureEnabled = false
            fxDesc.requiresSynchronousInitialization = true
            fxDesc.inputWidth = inW
            fxDesc.inputHeight = inH
            fxDesc.outputWidth = outputWidth
            fxDesc.outputHeight = outputHeight
            scaler = fxDesc.makeTemporalDenoisedScaler(device: device)
        } else {
            scaler = nil
        }

        let rw: MTLTextureUsage = [.shaderRead, .shaderWrite]
        let reactScalerUsage: MTLTextureUsage
        if #available(macOS 27.0, *) {
            reactScalerUsage = scaler?.reactiveMaskTextureUsage ?? []
        } else {
            reactScalerUsage = scaler?.reactiveTextureUsage ?? []
        }
        traceColorTex = makePrivateTex(.rgba16Float, w: inW, h: inH, usage: rw.union(scaler?.colorTextureUsage ?? []))
        traceDepthTex = makePrivateTex(.r32Float, w: inW, h: inH, usage: rw.union(scaler?.depthTextureUsage ?? []))
        traceMotionTex = makePrivateTex(.rg16Float, w: inW, h: inH, usage: rw.union(scaler?.motionTextureUsage ?? []))
        traceDiffTex = makePrivateTex(.rgba16Float, w: inW, h: inH, usage: rw.union(scaler?.diffuseAlbedoTextureUsage ?? []))
        traceSpecTex = makePrivateTex(.rgba16Float, w: inW, h: inH, usage: rw.union(scaler?.specularAlbedoTextureUsage ?? []))
        traceNormTex = makePrivateTex(.rgba16Float, w: inW, h: inH, usage: rw.union(scaler?.normalTextureUsage ?? []))
        traceRoughTex = makePrivateTex(.r16Float, w: inW, h: inH, usage: rw.union(scaler?.roughnessTextureUsage ?? []))
        traceHitTex = makePrivateTex(.r16Float, w: inW, h: inH, usage: rw.union(scaler?.specularHitDistanceTextureUsage ?? []))
        traceReactTex = makePrivateTex(.r8Unorm, w: inW, h: inH, usage: rw.union(reactScalerUsage))
        metalFXOutputTex = makePrivateTex(.rgba16Float, w: outputWidth, h: outputHeight, usage: rw.union(scaler?.outputTextureUsage ?? []))

        progColorTex = makePrivateTex(.rgba16Float, w: outputWidth, h: outputHeight, usage: rw)
        accumTex = makePrivateTex(.rgba32Float, w: outputWidth, h: outputHeight, usage: rw)
        if E68Perf.enabled {
            E68Perf.logLine(String(format: "targets alloc: %.1f ms (in=%dx%d out=%dx%d scale=%.2f fx=%@)",
                                   (CACurrentMediaTime() - allocT0) * 1000.0, inW, inH, outputWidth, outputHeight, desiredScale, scaler != nil ? "on" : "off"))
        }
    }

    private static func makePrivateTex(device: MTLDevice, format: MTLPixelFormat, w: Int, h: Int, usage: MTLTextureUsage) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
        d.usage = usage
        d.storageMode = .private
        return device.makeTexture(descriptor: d)!
    }

    private func makePrivateTex(_ format: MTLPixelFormat, w: Int, h: Int, usage: MTLTextureUsage) -> MTLTexture {
        Self.makePrivateTex(device: device, format: format, w: w, h: h, usage: usage)
    }

    // MARK: - Compute Encoders

    private func encodePathTraceWithBytes(
        cmd: MTLCommandBuffer,
        size: SIMD2<UInt32>,
        uniforms: inout RTFrameUniforms,
        colorTex: MTLTexture,
        depthTex: MTLTexture,
        motionTex: MTLTexture,
        diffTex: MTLTexture,
        specTex: MTLTexture,
        normTex: MTLTexture,
        roughTex: MTLTexture,
        hitTex: MTLTexture,
        reactTex: MTLTexture
    ) {
        guard let ptPipe = pathTracePipeline, let enc = cmd.makeComputeCommandEncoder(), let accel = extractor.instanceAS else { return }
        enc.setComputePipelineState(ptPipe)
        enc.setBytes(&uniforms, length: MemoryLayout<RTFrameUniforms>.stride, index: 0)
        bindTraceResources(enc: enc, accel: accel, colorTex: colorTex, depthTex: depthTex, motionTex: motionTex,
                           diffTex: diffTex, specTex: specTex, normTex: normTex, roughTex: roughTex, hitTex: hitTex, reactTex: reactTex)
        let tg = MTLSize(width: 8, height: 8, depth: 1)
        let grid = MTLSize(width: Int(size.x), height: Int(size.y), depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
    }

    private func bindTraceResources(
        enc: MTLComputeCommandEncoder,
        accel: MTLAccelerationStructure,
        colorTex: MTLTexture,
        depthTex: MTLTexture,
        motionTex: MTLTexture,
        diffTex: MTLTexture,
        specTex: MTLTexture,
        normTex: MTLTexture,
        roughTex: MTLTexture,
        hitTex: MTLTexture,
        reactTex: MTLTexture
    ) {
        enc.setAccelerationStructure(accel, bufferIndex: 1)
        enc.setBuffer(extractor.vertexBuffer, offset: 0, index: 2)
        enc.setBuffer(extractor.indexBuffer, offset: 0, index: 3)
        enc.setBuffer(extractor.submeshBuffer, offset: 0, index: 4)
        enc.setBuffer(extractor.instanceBuffer, offset: 0, index: 5)
        enc.setBuffer(extractor.materialBuffer, offset: 0, index: 6)
        enc.setBuffer(extractor.textureArgumentBuffer, offset: 0, index: 7)

        enc.setTexture(extractor.bgCubemapTexture, index: 0)
        enc.setTexture(colorTex, index: 1)
        enc.setTexture(depthTex, index: 2)
        enc.setTexture(motionTex, index: 3)
        enc.setTexture(diffTex, index: 4)
        enc.setTexture(specTex, index: 5)
        enc.setTexture(normTex, index: 6)
        enc.setTexture(roughTex, index: 7)
        enc.setTexture(hitTex, index: 8)
        enc.setTexture(reactTex, index: 9)

        if !extractor.primitiveBLASes.isEmpty {
            enc.useResources(extractor.primitiveBLASes, usage: .read)
        }
        if !extractor.textures.isEmpty {
            enc.useResources(extractor.textures, usage: .read)
        }
    }

    private func encodeAccumulateWithBytes(cmd: MTLCommandBuffer, size: SIMD2<UInt32>, uniforms: inout RTFrameUniforms, traceTex: MTLTexture, accumTex: MTLTexture, mfxSeed: MTLTexture? = nil) {
        guard let accPipe = accumulatePipeline, let enc = cmd.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(accPipe)
        enc.setBytes(&uniforms, length: MemoryLayout<RTFrameUniforms>.stride, index: 0)
        enc.setTexture(traceTex, index: 0)
        enc.setTexture(accumTex, index: 1)
        enc.setTexture(mfxSeed ?? traceTex, index: 2)
        enc.dispatchThreads(MTLSize(width: Int(size.x), height: Int(size.y), depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        enc.endEncoding()
    }

    func encodeComposite(
        cmd: MTLCommandBuffer,
        srcTex: MTLTexture? = nil,
        blendTex: MTLTexture? = nil,
        outTexture: MTLTexture,
        progressBlend: Float,
        isProgressiveOnly: Bool,
        uniforms: RTFrameUniforms
    ) {
        guard let enc = cmd.makeComputeCommandEncoder() else { return }
        var comp = RTCompositeParams(
            progressBlend: progressBlend,
            exposureScale: uniforms.exposureScale,
            bloomStrength: uniforms.fogParams.y,
            vignetteStrength: uniforms.fogParams.z,
            grainStrength: uniforms.fogParams.w,
            frameIndex: uniforms.frameIndex,
            isProgressiveOnly: isProgressiveOnly ? 1 : 0,
            pad0: 0
        )
        enc.setComputePipelineState(compositePipeline)
        enc.setBytes(&comp, length: MemoryLayout<RTCompositeParams>.stride, index: 0)
        enc.setTexture(srcTex ?? accumTex, index: 0)
        enc.setTexture(blendTex ?? accumTex, index: 1)
        enc.setTexture(outTexture, index: 2)
        enc.dispatchThreads(MTLSize(width: outTexture.width, height: outTexture.height, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        enc.endEncoding()
    }

    // MARK: - Low-Discrepancy Subpixel Jitter Sequences

    func haltonJitter(index: UInt32) -> SIMD2<Float> {
        let i = (index % 8) + 1
        return SIMD2<Float>(halton(i, base: 2) - 0.5, halton(i, base: 3) - 0.5)
    }

    private func r2Jitter(index: UInt32) -> SIMD2<Float> {
        // Golden-ratio 2D low-discrepancy R2 sequence (Roberts 2018)
        let n = Float(index + 1)
        let fx = (n * 0.7548776662).truncatingRemainder(dividingBy: 1.0)
        let fy = (n * 0.5698402910).truncatingRemainder(dividingBy: 1.0)
        return SIMD2<Float>(fx - 0.5, fy - 0.5)
    }

    private func halton(_ idx: UInt32, base: UInt32) -> Float {
        var f: Float = 1.0
        var r: Float = 0.0
        var i = idx
        while i > 0 {
            f /= Float(base)
            r += f * Float(i % base)
            i /= base
        }
        return r
    }

    private func curVPIdentity(world: KeyboardScene, outW: Int, outH: Int) -> simd_float4x4 {
        let sz = SIMD2<UInt32>(UInt32(outW), UInt32(outH))
        return extractor.buildFrameUniforms(
            world: world, renderSize: sz, outputSize: sz, jitter: .zero, prevJitter: .zero,
            prevViewProj: matrix_identity_float4x4, frameIndex: 0, sampleIndex: 0, maxBounces: 1, isProgressive: false
        ).1
    }
}
