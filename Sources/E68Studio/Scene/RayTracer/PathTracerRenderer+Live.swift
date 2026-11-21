import Foundation
import Metal
import MetalKit
import SceneKit
import AppKit
import MetalFX
import Darwin
import simd

extension PathTracerRenderer {
    // MARK: - Live Renderer Frame

    func renderLiveFrame(
        world: KeyboardScene, target: MTLTexture, drawable: MTLDrawable?, sync: RTSceneExtractor.SyncResult,
        bakePipeline: MTLComputePipelineState, framePipeline: MTLComputePipelineState, stepMs: Double, syncMs: Double
    ) -> MTLCommandBuffer? {
        guard let accel = extractor.instanceAS,
              let instGeom = extractor.lightCacheInstGeomBuffer, let cacheTris = extractor.lightCacheTriBuffer,
              let sampleTri = extractor.lightCacheSampleTriBuffer, let samples = extractor.lightCacheSampleBuffer,
              let sampleCounts = extractor.lightCacheSampleCountBuffer,
              let directions = extractor.lightCacheDirectionBuffer,
              let deskSamples = extractor.lightCacheDeskSampleBuffer,
              let color = liveColorTex, let depth = liveDepthTex, let motion = liveMotionTex,
              let cmd = commandQueue.makeCommandBuffer() else { return nil }
        extractor.encodePendingWork(onto: cmd)

        let goal = world.currentGoal
        let cameraMoving = !world.isCameraSettled
        let historyBroken = sync.geometryChanged || sync.motionResetNeeded
            || lastSceneTopology != world.topologyRevision
            || (lastMood != nil && lastMood != world.activeMood)
        let changed = historyBroken || cameraMoving || world.needsContinuousRender
            || lastSceneMaterials != world.materialRevision
            || lastSceneTransforms != world.transformRevision
            || lastSceneBacklight != world.backlightRevision
            || lastCameraGoal != goal
            || sync.dynamicLightingChanged
        lastSceneTopology = world.topologyRevision
        lastSceneMaterials = world.materialRevision
        lastSceneTransforms = world.transformRevision
        lastSceneBacklight = world.backlightRevision
        lastMood = world.activeMood
        lastCameraGoal = goal
        if historyBroken { pendingHistoryReset = true }

        let jitter = haltonJitter(index: frameIndex)
        var (uniforms, curVP) = extractor.buildFrameUniforms(
            world: world, renderSize: outputSize, outputSize: outputSize, jitter: jitter, prevJitter: prevJitter,
            prevViewProj: hasPrevFrame ? prevViewProj : matrix_identity_float4x4,
            frameIndex: frameIndex, sampleIndex: 0, maxBounces: RTSharedTypes.maxBouncesProgressive, isProgressive: false
        )
        // Live rendering relies on static 8-bit dither only so animated RGB never shimmers with film grain.
        uniforms.fogParams.w = 0.0
        // Bit 3: read surface detail at a steady, pixel-sized level (see `evalSurfaceHit`).
        // Bit 4: a directional sun or moon is lit per pixel in the frame and left out of the stored light.
        uniforms.renderFlags |= 8 | 16
        if !hasPrevFrame { uniforms.prevViewProj = curVP }

        // A new world, a new time of day or the first frame: hold what was on screen (or black) and
        // dissolve the new light in once enough of it is stored.
        let firstLiveFrame = dissolveScenario == nil
        if firstLiveFrame || dissolveScenario != world.activeScenario || dissolveMood != world.activeMood {
            dissolveScenario = world.activeScenario
            dissolveMood = world.activeMood
            if let held = liveHeldTex {
                if !firstLiveFrame, !lightDissolveActive, let last = liveLastPresented,
                   last.width == held.width, last.height == held.height, let blit = cmd.makeBlitCommandEncoder() {
                    blit.copy(from: last, to: held)
                    blit.endEncoding()
                } else if firstLiveFrame || liveLastPresented == nil {
                    let pass = MTLRenderPassDescriptor()
                    pass.colorAttachments[0].texture = held
                    pass.colorAttachments[0].loadAction = .clear
                    pass.colorAttachments[0].storeAction = .store
                    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                    cmd.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
                }
                lightDissolveActive = true
                lightDissolveAwaitingReset = true
                lightDissolveFrames = 0
                lightDissolveMovingFrames = 0
            }
        }

        // Stored light belongs to one lighting setup: disk-cached when seen before, atomically refreshed
        // on lamp/mood toggles (no partial-desk wipe), or blended smoothly for gentle clock/sky drift.
        let sampleCount = extractor.lightCacheSampleCount
        let dKey = discreteKey(uniforms, world: world, layoutHash: extractor.lightCacheLayoutHash)
        // The trailing constant is the stored-light format: bump it when what is stored changes meaning
        // (6 = half4 RGB samples + uint16 sampleCounts), so older files on disk are not loaded.
        let cacheKey = Self.lightCacheKey64(uniforms, discreteKey: dKey)
            ^ (extractor.environmentHash &* 0x9E3779B97F4A7C15)
            ^ (extractor.monitorTextureHash &* 0xBF58476D1CE4E5B9)
            ^ 0x0000_0000_5EED_0006
        var warmPasses = 0
        let topologyReset = bakedCacheGeneration != extractor.lightCacheGeneration
        let scenarioOrMoodChanged = bakedScenario != world.activeScenario || bakedMood != world.activeMood
        let discreteChange = topologyReset || bakedDiscreteKey != dKey
        let continuousDrift = !discreteChange && bakedLightHash != cacheKey

        if discreteChange || continuousDrift {
            bakedCacheGeneration = extractor.lightCacheGeneration
            bakedDiscreteKey = dKey
            bakedLightHash = cacheKey
            bakedScenario = world.activeScenario
            bakedMood = world.activeMood
            bakeCursor = 0
            pendingSaveKey = 0
            if lightDissolveActive && lightDissolveAwaitingReset {
                lightDissolveAwaitingReset = false
                lightDissolveFrames = 0
            }
            let loaded = sampleCount > 0 && loadLightCacheIfAvailable(
                key: cacheKey, sampleCount: sampleCount, samples: samples, sampleCounts: sampleCounts, directions: directions, deskSamples: deskSamples, into: cmd
            )
            if loaded {
                gradualBakeRefresh = false
                fastBakeRefresh = false
                bakePassesSinceChange = Self.bakePassesToConverge
                savedCacheKeys.insert(cacheKey)
            } else if topologyReset || scenarioOrMoodChanged {
                // Nothing is stored yet (or new world / mood): fill it from scratch.
                gradualBakeRefresh = false
                fastBakeRefresh = false
                bakePassesSinceChange = 0
                warmPasses = cameraMoving ? 4 : 8
            } else {
                // Material hash, monitor colour/wallpaper, or other light drift: keep existing stored light
                // and blend the new lighting in gradually without wiping to noisy 1-sample passes.
                gradualBakeRefresh = true
                fastBakeRefresh = true
                warmPasses = 0
                bakePassesSinceChange = 0
                if E68Perf.enabled {
                    E68Perf.logLine("stored light: gradual refresh at frame \(frameIndex) (keeping existing samples)")
                }
            }
        }

        let targetConvergePasses = gradualBakeRefresh ? Self.gradualBakePassesToConverge : Self.bakePassesToConverge
        let baking = bakePassesSinceChange < targetConvergePasses && sampleCount > 0
        var didConvergeThisFrame = false
        if baking {
            var budget: Int
            if warmPasses > 0 {
                budget = sampleCount * warmPasses
            } else if gradualBakeRefresh {
                budget = fastBakeRefresh ? (cameraMoving ? 300_000 : 1_400_000) : (cameraMoving ? 150_000 : 360_000)
            } else if cameraMoving {
                budget = 220_000
            } else if lightDissolveActive {
                // The old frame is still on screen: spend the time on the new light, not on frame rate.
                budget = sampleCount * 2
            } else {
                budget = bakePassesSinceChange < 32 ? 1_600_000 : 960_000
            }
            while budget > 0 {
                let count = min(budget, sampleCount - bakeCursor)
                let maxSampleCount: UInt32
                if gradualBakeRefresh {
                    maxSampleCount = bakePassesSinceChange < 96
                        ? 24
                        : UInt32(min(24 + (bakePassesSinceChange - 95), 192))
                } else {
                    maxSampleCount = UInt32(bakePassesSinceChange == 0 ? 1 : min(bakePassesSinceChange + 1, 192))
                }
                var params = LightCacheBakeParams(
                    sampleOffset: UInt32(bakeCursor), sampleCount: UInt32(count), passIndex: bakeDispatches,
                    maxCount: maxSampleCount, passNumber: UInt32(bakePassesSinceChange), pad0: 0
                )
                bakeDispatches &+= 1
                if let enc = cmd.makeComputeCommandEncoder() {
                    enc.setComputePipelineState(bakePipeline)
                    enc.setBytes(&uniforms, length: MemoryLayout<RTFrameUniforms>.stride, index: 0)
                    bindSceneBuffers(enc: enc, accel: accel)
                    enc.setBytes(&params, length: MemoryLayout<LightCacheBakeParams>.stride, index: 8)
                    enc.setBuffer(instGeom, offset: 0, index: 9)
                    enc.setBuffer(cacheTris, offset: 0, index: 10)
                    enc.setBuffer(sampleTri, offset: 0, index: 11)
                    enc.setBuffer(samples, offset: 0, index: 12)
                    enc.setBuffer(directions, offset: 0, index: 13)
                    enc.setBuffer(deskSamples, offset: 0, index: 14)
                    enc.setBuffer(sampleCounts, offset: 0, index: 15)
                    enc.dispatchThreads(MTLSize(width: 4096, height: (count + 4095) / 4096, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
                    enc.endEncoding()
                }
                budget -= count
                bakeCursor += count
                if bakeCursor >= sampleCount {
                    bakeCursor = 0
                    bakePassesSinceChange += 1
                    if bakePassesSinceChange >= targetConvergePasses {
                        gradualBakeRefresh = false
                        fastBakeRefresh = false
                        didConvergeThisFrame = true
                        break
                    }
                }
            }
            if didConvergeThisFrame {
                scheduleLightCacheSave(key: cacheKey, sampleCount: sampleCount, samples: samples, sampleCounts: sampleCounts, directions: directions, deskSamples: deskSamples, on: cmd)
            }
        }

        // The frame itself: no randomness, so it is final as drawn.
        if let enc = cmd.makeComputeCommandEncoder() {
            enc.setComputePipelineState(framePipeline)
            enc.setBytes(&uniforms, length: MemoryLayout<RTFrameUniforms>.stride, index: 0)
            bindSceneBuffers(enc: enc, accel: accel)
            enc.setBuffer(instGeom, offset: 0, index: 9)
            enc.setBuffer(cacheTris, offset: 0, index: 10)
            enc.setBuffer(samples, offset: 0, index: 12)
            enc.setBuffer(directions, offset: 0, index: 13)
            enc.setBuffer(deskSamples, offset: 0, index: 14)
            enc.setTexture(extractor.bgCubemapTexture, index: 0)
            enc.setTexture(color, index: 1)
            enc.setTexture(depth, index: 2)
            enc.setTexture(motion, index: 3)
            enc.dispatchThreads(MTLSize(width: Int(outputSize.x), height: Int(outputSize.y), depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            enc.endEncoding()
        }

        // Edge anti-aliasing from the sub-pixel jitter. Its input has no noise, so it only smooths edges.
        var presented = color
        if let antialiaser = liveAntialiaser, let resolved = liveResolvedTex {
            antialiaser.colorTexture = color
            antialiaser.depthTexture = depth
            antialiaser.motionTexture = motion
            antialiaser.outputTexture = resolved
            antialiaser.jitterOffsetX = -jitter.x
            antialiaser.jitterOffsetY = -jitter.y
            antialiaser.motionVectorScaleX = 1.0
            antialiaser.motionVectorScaleY = 1.0
            antialiaser.isDepthReversed = false
            antialiaser.preExposure = 1.0
            antialiaser.reset = pendingHistoryReset || !hasPrevFrame
            antialiaser.encode(commandBuffer: cmd)
            presented = resolved
        }
        pendingHistoryReset = false
        prevViewProj = curVP
        prevJitter = jitter
        hasPrevFrame = true

        // Lens: sharp where the camera looks, softer in front of and behind it.
        if Self.lensBlurEnabled, let blurPipeline = lensBlurPipeline, let blurred = liveBlurredTex,
           let enc = cmd.makeComputeCommandEncoder() {
            // A slightly wider aperture than the path tracer's for close views, where blur reads as a
            // camera; wide views keep nearly everything in focus, as a real lens would.
            let aperture: Float = (uniforms.focusDistance < 40 ? 0.036 : 0.018) * 2.4
            var params = LensBlurParams(
                focusDistance: uniforms.focusDistance,
                cocScale: aperture * Float(outputSize.y) / (2 * max(uniforms.tanHalfFov, 1e-3)),
                nearZ: 0.25, farZ: 1500.0, maxRadius: 9.0,
                width: outputSize.x, height: outputSize.y, pad: 0
            )
            enc.setComputePipelineState(blurPipeline)
            enc.setBytes(&params, length: MemoryLayout<LensBlurParams>.stride, index: 0)
            enc.setTexture(presented, index: 0)
            enc.setTexture(depth, index: 1)
            enc.setTexture(blurred, index: 2)
            enc.dispatchThreads(MTLSize(width: Int(outputSize.x), height: Int(outputSize.y), depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            enc.endEncoding()
            presented = blurred
        }

        // How much of the new frame shows through the held one.
        var heldBlend: Float = 0
        if lightDissolveActive, liveHeldTex != nil {
            lightDissolveFrames += 1
            if cameraMoving { lightDissolveMovingFrames += 1 }
            var shown: Float = 0
            if lightDissolveAwaitingReset {
                // The scene has not been rebuilt for the new world yet; give up waiting after half a second.
                if lightDissolveFrames > 30 { lightDissolveAwaitingReset = false; lightDissolveFrames = 0 }
            } else {
                let byLight = simd_smoothstep(Float(40), Float(80), Float(bakePassesSinceChange))
                let byTime = min(Float(lightDissolveFrames) / 14, 1)
                // Never hold a frame for long against a moving camera.
                let byMotion = min(Float(lightDissolveMovingFrames) / 12, 1)
                shown = max(min(byLight, byTime), byMotion)
            }
            heldBlend = 1 - shown
            if shown >= 0.999 { lightDissolveActive = false; heldBlend = 0 }
        }
        liveLastPresented = presented
        encodeComposite(cmd: cmd, srcTex: presented, blendTex: heldBlend > 0 ? liveHeldTex : nil, outTexture: target,
                        progressBlend: heldBlend, isProgressiveOnly: false, uniforms: uniforms)

        // Nothing left to do once the light has converged and the edges have resolved: stop drawing.
        liveStillFrames = changed ? 0 : liveStillFrames + 1
        let currentTargetPasses = gradualBakeRefresh ? Self.gradualBakePassesToConverge : Self.bakePassesToConverge
        let stillBaking = bakePassesSinceChange < currentTargetPasses && sampleCount > 0
        sampleIndex = UInt32(min(bakePassesSinceChange, currentTargetPasses))
        if changed || stillBaking || lightDissolveActive || liveStillFrames < 10 {
            isSettledForSleep = false
        } else if !isSettledForSleep {
            isSettledForSleep = true
            DispatchQueue.main.async { [weak self] in self?.onProgressiveSettled?(true) }
        }

        let gear = stillBaking ? "live-baking" : (isSettledForSleep ? "live-idle" : "live")
        inFlightLock.lock()
        inFlightFrames += 1
        inFlightLock.unlock()
        let perfOn = E68Perf.enabled
        if perfOn {
            E68Perf.recordCPUFrame(gear: gear, internalSize: outputSize, outputSize: outputSize, sampleIndex: sampleIndex,
                                   maxProgressiveSamples: UInt32(currentTargetPasses), stepMs: stepMs, syncMs: syncMs,
                                   texCount: extractor.textures.count)
        }
        cmd.addCompletedHandler { [weak self] cb in
            if let self {
                self.inFlightLock.lock()
                self.inFlightFrames = max(0, self.inFlightFrames - 1)
                self.inFlightLock.unlock()
            }
            guard perfOn else { return }
            if let error = cb.error { E68Perf.logLine("command buffer failed: \(error.localizedDescription)") }
            E68Perf.recordCompletedGPU(gpuMs: cb.gpuEndTime > cb.gpuStartTime ? (cb.gpuEndTime - cb.gpuStartTime) * 1000.0 : 0.0, gear: gear)
        }
        if let captureDirectory {
            encodeFrameCapture(cmd: cmd, source: target, directory: captureDirectory, gear: gear)
        }
        lastGear = gear
        if let drawable { cmd.present(drawable) }
        cmd.commit()
        frameIndex &+= 1
        return cmd
    }

    private struct LensBlurParams {
        var focusDistance: Float
        var cocScale: Float
        var nearZ: Float
        var farZ: Float
        var maxRadius: Float
        var width: UInt32
        var height: UInt32
        var pad: UInt32
    }

    private struct LightCacheBakeParams {
        var sampleOffset: UInt32
        var sampleCount: UInt32
        var passIndex: UInt32
        var maxCount: UInt32
        var passNumber: UInt32
        var pad0: UInt32
    }

    private static let lightCacheFileMagic: UInt64 = 0x4536384C_43303035

    private func discreteKey(_ u: RTFrameUniforms, world: KeyboardScene, layoutHash: UInt64) -> UInt64 {
        if cachedMaterialsRev != world.materialRevision {
            cachedMaterialsRev = world.materialRevision
            cachedMaterialsHash = extractor.computeMaterialCacheHash()
        }
        var h: UInt64 = layoutHash ^ cachedMaterialsHash
        for byte in world.activeScenario.rawValue.utf8 { RTSceneExtractor.fnvMix(&h, UInt64(byte)) }
        RTSceneExtractor.fnvMix(&h, 0xFF)
        for byte in world.activeMood.rawValue.utf8 { RTSceneExtractor.fnvMix(&h, UInt64(byte)) }
        let roomFlag: UInt64 = u.isRoomScenario != 0 ? 4 : 0
        RTSceneExtractor.fnvMix(&h, roomFlag)
        return h
    }

    private static func lightCacheKey64(_ u: RTFrameUniforms, discreteKey: UInt64) -> UInt64 {
        var h = discreteKey
        for v in [u.keyLightPosRadius, u.keyLightColor, u.fillLightPosRadius, u.fillLightColor,
                  u.deskBulbPosRadius,
                  u.monitorPos, SIMD4<Float>(u.monitorColor.x, u.monitorColor.y, u.monitorColor.z, 0),
                  u.underDeskPosB, SIMD4<Float>(u.underDeskColor.x, u.underDeskColor.y, u.underDeskColor.z, 0),
                  u.roomLightPosRadius, u.roomLightColor, u.bgColor, u.windowOrigin] {
            RTSceneExtractor.fnvMixVec4(&h, v)
        }
        return h
    }

    private static func lightCacheDirectory() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appendingPathComponent("E68Studio/LightCache", isDirectory: true)
    }

    private func loadLightCacheIfAvailable(
        key: UInt64, sampleCount: Int, samples: MTLBuffer, sampleCounts: MTLBuffer, directions: MTLBuffer, deskSamples: MTLBuffer, into cmd: MTLCommandBuffer
    ) -> Bool {
        guard Self.useDiskLightCache, sampleCount > 0, let dir = Self.lightCacheDirectory() else { return false }
        let hex = String(format: "%016llx", key)
        let url = dir.appendingPathComponent("\(hex).lc4")
        guard let fileData = try? Data(contentsOf: url, options: .mappedIfSafe), fileData.count > 24 else { return false }

        var magic: UInt64 = 0, storedKey: UInt64 = 0, storedCount: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &magic) { fileData.copyBytes(to: $0, from: 0..<8) }
        _ = withUnsafeMutableBytes(of: &storedKey) { fileData.copyBytes(to: $0, from: 8..<16) }
        _ = withUnsafeMutableBytes(of: &storedCount) { fileData.copyBytes(to: $0, from: 16..<24) }
        guard magic == Self.lightCacheFileMagic, storedKey == key, Int(storedCount) == sampleCount else { return false }

        let decompressed: Data? = autoreleasepool {
            let compressed = fileData.subdata(in: 24..<fileData.count)
            return try? (compressed as NSData).decompressed(using: .lz4) as Data
        }
        guard let rawData = decompressed else { return false }
        let sampleBytes = sampleCount * 8
        let countBytes = sampleCount * MemoryLayout<UInt16>.stride
        let dirBytes = sampleCount * 8
        let deskBytes = sampleCount * 8
        guard rawData.count == sampleBytes + countBytes + dirBytes + deskBytes,
              let stageSamples = device.makeBuffer(length: sampleBytes, options: .storageModeShared),
              let stageCounts = device.makeBuffer(length: countBytes, options: .storageModeShared),
              let stageDirs = device.makeBuffer(length: dirBytes, options: .storageModeShared),
              let stageDesk = device.makeBuffer(length: deskBytes, options: .storageModeShared),
              let blit = cmd.makeBlitCommandEncoder() else { return false }

        rawData.withUnsafeBytes { rawPtr in
            guard let base = rawPtr.baseAddress else { return }
            memcpy(stageSamples.contents(), base, sampleBytes)
            memcpy(stageCounts.contents(), base.advanced(by: sampleBytes), countBytes)
            memcpy(stageDirs.contents(), base.advanced(by: sampleBytes + countBytes), dirBytes)
            memcpy(stageDesk.contents(), base.advanced(by: sampleBytes + countBytes + dirBytes), deskBytes)
        }
        blit.copy(from: stageSamples, sourceOffset: 0, to: samples, destinationOffset: 0, size: sampleBytes)
        blit.copy(from: stageCounts, sourceOffset: 0, to: sampleCounts, destinationOffset: 0, size: countBytes)
        blit.copy(from: stageDirs, sourceOffset: 0, to: directions, destinationOffset: 0, size: dirBytes)
        blit.copy(from: stageDesk, sourceOffset: 0, to: deskSamples, destinationOffset: 0, size: deskBytes)
        blit.endEncoding()
        // Keep staging buffers alive until the GPU copy completes.
        cmd.addCompletedHandler { _ in _ = (stageSamples, stageCounts, stageDirs, stageDesk) }
        E68Perf.logLine("light cache disk hit: \(hex) (\(sampleCount) pts)")
        return true
    }

    private func scheduleLightCacheSave(
        key: UInt64, sampleCount: Int, samples: MTLBuffer, sampleCounts: MTLBuffer, directions: MTLBuffer, deskSamples: MTLBuffer, on cmd: MTLCommandBuffer
    ) {
        guard Self.useDiskLightCache, !savedCacheKeys.contains(key), pendingSaveKey != key, sampleCount > 0,
              let dir = Self.lightCacheDirectory() else { return }
        pendingSaveKey = key
        savedCacheKeys.insert(key)

        let sampleBytes = sampleCount * 8
        let countBytes = sampleCount * MemoryLayout<UInt16>.stride
        let dirBytes = sampleCount * 8
        let deskBytes = sampleCount * 8
        guard let stageSamples = device.makeBuffer(length: sampleBytes, options: .storageModeShared),
              let stageCounts = device.makeBuffer(length: countBytes, options: .storageModeShared),
              let stageDirs = device.makeBuffer(length: dirBytes, options: .storageModeShared),
              let stageDesk = device.makeBuffer(length: deskBytes, options: .storageModeShared),
              let blit = cmd.makeBlitCommandEncoder() else { return }

        blit.copy(from: samples, sourceOffset: 0, to: stageSamples, destinationOffset: 0, size: sampleBytes)
        blit.copy(from: sampleCounts, sourceOffset: 0, to: stageCounts, destinationOffset: 0, size: countBytes)
        blit.copy(from: directions, sourceOffset: 0, to: stageDirs, destinationOffset: 0, size: dirBytes)
        blit.copy(from: deskSamples, sourceOffset: 0, to: stageDesk, destinationOffset: 0, size: deskBytes)
        blit.endEncoding()

        let hex = String(format: "%016llx", key)
        let url = dir.appendingPathComponent("\(hex).lc4")
        cmd.addCompletedHandler { _ in
            Self.cacheIOQueue.async {
                autoreleasepool {
                    var raw = Data(count: sampleBytes + countBytes + dirBytes + deskBytes)
                    raw.withUnsafeMutableBytes { dst in
                        guard let base = dst.baseAddress else { return }
                        memcpy(base, stageSamples.contents(), sampleBytes)
                        memcpy(base.advanced(by: sampleBytes), stageCounts.contents(), countBytes)
                        memcpy(base.advanced(by: sampleBytes + countBytes), stageDirs.contents(), dirBytes)
                        memcpy(base.advanced(by: sampleBytes + countBytes + dirBytes), stageDesk.contents(), deskBytes)
                    }
                    guard let compressed = try? (raw as NSData).compressed(using: .lz4) as Data else { return }
                    var out = Data(capacity: 24 + compressed.count)
                    var m = Self.lightCacheFileMagic
                    var k = key
                    var c = UInt64(sampleCount)
                    withUnsafeBytes(of: &m) { out.append(contentsOf: $0) }
                    withUnsafeBytes(of: &k) { out.append(contentsOf: $0) }
                    withUnsafeBytes(of: &c) { out.append(contentsOf: $0) }
                    out.append(compressed)
                    let fm = FileManager.default
                    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? out.write(to: url, options: .atomic)
                    Self.pruneCacheDirectory(dir, maxFiles: 20)
                    E68Perf.logLine(String(format: "light cache saved: %@ (%.1f MB)", hex, Double(out.count) / 1_048_576.0))
                }
            }
        }
    }

    private static func pruneCacheDirectory(_ dir: URL, maxFiles: Int) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { return }
        let caches = urls.filter { $0.pathExtension == "lc4" || $0.pathExtension == "lc3" || $0.pathExtension == "lc2" }
        guard caches.count > maxFiles else { return }
        let sorted = caches.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for stale in sorted.dropFirst(maxFiles) {
            try? fm.removeItem(at: stale)
        }
    }

    func bindSceneBuffers(enc: MTLComputeCommandEncoder, accel: MTLAccelerationStructure) {
        enc.setAccelerationStructure(accel, bufferIndex: 1)
        enc.setBuffer(extractor.vertexBuffer, offset: 0, index: 2)
        enc.setBuffer(extractor.indexBuffer, offset: 0, index: 3)
        enc.setBuffer(extractor.submeshBuffer, offset: 0, index: 4)
        enc.setBuffer(extractor.instanceBuffer, offset: 0, index: 5)
        enc.setBuffer(extractor.materialBuffer, offset: 0, index: 6)
        enc.setBuffer(extractor.textureArgumentBuffer, offset: 0, index: 7)
        if !extractor.primitiveBLASes.isEmpty { enc.useResources(extractor.primitiveBLASes, usage: .read) }
        if !extractor.textures.isEmpty { enc.useResources(extractor.textures, usage: .read) }
    }


    func encodeFrameCapture(cmd: MTLCommandBuffer, source: MTLTexture, directory: String, gear: String) {
        // Every 10th frame, plus each of the first frames after a gear change where pops would show.
        let gearChanged = gear != lastCapturedGear
        if gearChanged { framesSinceGearChange = 0 } else { framesSinceGearChange += 1 }
        lastCapturedGear = gear
        guard capturedFrames < 400, frameIndex % 10 == 0 || framesSinceGearChange < 4 || framesSinceGearChange == 12 else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: source.pixelFormat, width: source.width, height: source.height, mipmapped: false)
        desc.storageMode = .shared
        guard let copy = device.makeTexture(descriptor: desc), let blit = cmd.makeBlitCommandEncoder() else { return }
        blit.copy(from: source, to: copy)
        blit.endEncoding()
        capturedFrames += 1
        let name = String(format: "%@/f%05u-%@-s%03u.png", directory, frameIndex, gear, sampleIndex)
        cmd.addCompletedHandler { _ in
            let w = copy.width, h = copy.height
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            copy.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: info),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: name))
        }
    }
    /// Reads a rendered frame back for the command-line render tools.
    func snapshot(of texture: MTLTexture) -> NSImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width, height: texture.height, mipmapped: false)
        desc.storageMode = .shared
        guard let copy = device.makeTexture(descriptor: desc), let cmd = commandQueue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, to: copy)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        let w = copy.width, h = copy.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        copy.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: info),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: w, height: h))
    }
}
