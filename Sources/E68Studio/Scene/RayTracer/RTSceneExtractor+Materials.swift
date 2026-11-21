import Foundation
import SceneKit
import Metal
import AppKit
import simd

extension RTSceneExtractor {
    // MARK: - Material Extraction & Dirty Sync

    func registerMaterial(_ mat: SCNMaterial, node: SCNNode, world: KeyboardScene, isKeyCap: Bool) -> Int {
        let key = ObjectIdentifier(mat)
        if let existing = materialCache[key] { return existing }

        let idx = materials.count
        materialCache[key] = idx

        let isKeySide = isKeyCap && (node.geometry?.materials.first === mat)
        let isKeyTop = isKeyCap && !isKeySide
        let isMouseOverlay = (node.name == TechProps.MouseParts.left || node.name == TechProps.MouseParts.right)
        let isMonitor = (node.name == "prop.monitor.screen")
        let isPhone = isPhoneScreenNode(node, mat: mat)
        let isDeskLampEmit = (node.name == "prop.deskLamp.bulb" || node.name == "prop.deskLamp.reflector")
        let isUnderDeskEmit = (node.name == "prop.underDeskGlow")
        let isMonitorGlowEmit = (node.name == "prop.monitor.screenGlow")
        let isMouseDynamic = (node.name == TechProps.MouseParts.back
                              || node.name == TechProps.MouseParts.forward
                              || node.name == TechProps.MouseParts.dpiLED
                              || (node.geometry is SCNCylinder && node.parent?.name == TechProps.MouseParts.wheel))
        let isKnob = isDescendant(node, of: world.knob) && (node.geometry?.firstMaterial === world.knobMaterial)
        let isPhotoGround = (node.name == DeskScenarios.photoGroundName)

        if isPhone { lastPhoneMaterial = mat }

        let isSampledEmitter = isMonitor || isDeskLampEmit || isUnderDeskEmit
        let isStaticMat = !isKeyTop && !isKeySide && !isMonitor && !isPhone && !isMouseOverlay
            && !isDeskLampEmit && !isUnderDeskEmit && !isMonitorGlowEmit
            && !isMouseDynamic && !isKnob && !isSampledEmitter && !isPhotoGround
        let converted: RTMaterialData
        if isStaticMat, let snap = staticMaterialSnapshots[key] {
            var remapped = snap.data
            func reuse(_ tex: MTLTexture?, _ key: TextureCacheKey?) -> Int32 {
                guard let tex else { return -1 }
                let slot = registerOrReuseMetalTexture(tex)
                if let key { textureCache[key] = slot }
                return slot
            }
            remapped.texIndices.x = reuse(snap.diffTex, snap.diffKey)
            remapped.texIndices.y = reuse(snap.normTex, snap.normKey)
            remapped.texIndices.z = reuse(snap.roughTex, snap.roughKey)
            remapped.texIndices.w = reuse(snap.emTex, snap.emKey)
            remapped.extraTex.x = reuse(snap.metalTex, snap.metalKey)
            remapped.extraTex.y = reuse(snap.aoTex, snap.aoKey)
            converted = remapped
            seenSnapshotMaterialIDs.insert(key)
        } else {
            let built = convertMaterial(
                mat, node: node, world: world,
                isKeySide: isKeySide, isKeyTop: isKeyTop, isMonitor: isMonitor,
                isMouseOverlay: isMouseOverlay, isSampledEmitter: isSampledEmitter
            )
            converted = built
            if isStaticMat && world.usesHardwareRayTracer {
                func texAt(_ slot: Int32) -> MTLTexture? {
                    (slot >= 0 && Int(slot) < textures.count) ? textures[Int(slot)] : nil
                }
                func cacheKey(_ contents: Any?, isSRGB: Bool) -> TextureCacheKey? {
                    contents.map { TextureCacheKey(objID: ObjectIdentifier($0 as AnyObject), isSRGB: isSRGB) }
                }
                staticMaterialSnapshots[key] = StaticMaterialSnapshot(
                    data: built,
                    diffTex: texAt(built.texIndices.x),
                    diffKey: cacheKey(mat.diffuse.contents, isSRGB: true),
                    normTex: texAt(built.texIndices.y),
                    normKey: cacheKey(mat.normal.contents, isSRGB: false),
                    roughTex: texAt(built.texIndices.z),
                    roughKey: cacheKey(mat.roughness.contents, isSRGB: false),
                    emTex: texAt(built.texIndices.w),
                    emKey: cacheKey(mat.emission.contents, isSRGB: true),
                    metalTex: texAt(built.extraTex.x),
                    metalKey: cacheKey(mat.metalness.contents, isSRGB: false),
                    aoTex: texAt(built.extraTex.y),
                    aoKey: cacheKey(mat.ambientOcclusion.contents, isSRGB: false)
                )
                seenSnapshotMaterialIDs.insert(key)
                for prop in [mat.diffuse, mat.normal, mat.roughness, mat.metalness, mat.ambientOcclusion, mat.emission] {
                    if resolveCGImageOptional(prop.contents) != nil {
                        propsToReleaseAfterRebuild.append(prop)
                    }
                }
            }
        }
        materials.append(converted)

        if !isStaticMat {
            let tracked = TrackedMaterial(
                material: mat,
                node: node,
                index: idx,
                isKeyTop: isKeyTop,
                isKeySide: isKeySide,
                isMouseButtonOverlay: isMouseOverlay,
                isMonitorScreen: isMonitor,
                isPhoneScreen: isPhone,
                isDeskLampEmitter: isDeskLampEmit,
                isUnderDeskEmitter: isUnderDeskEmit,
                isKnob: isKnob,
                lastDiffuseID: mat.diffuse.contents.map { ObjectIdentifier($0 as AnyObject) },
                lastEmissionID: mat.emission.contents.map { ObjectIdentifier($0 as AnyObject) },
                lastButtonOverlayHidden: isMouseOverlay ? (node.opacity <= 0.01) : false
            )
            trackedMaterials.append(tracked)
        }
        return idx
    }

    private func isPhoneScreenNode(_ node: SCNNode, mat: SCNMaterial) -> Bool {
        if let plane = node.geometry as? SCNPlane, abs(Float(plane.width) - 3.68) < 0.15,
           mat.emission.intensity > 0.5, (mat.clearCoat.contents as? Double ?? 0) > 0.8 {
            return true
        }
        return false
    }

    private func convertMaterial(
        _ mat: SCNMaterial,
        node: SCNNode,
        world: KeyboardScene,
        isKeySide: Bool,
        isKeyTop: Bool,
        isMonitor: Bool,
        isMouseOverlay: Bool,
        isSampledEmitter: Bool
    ) -> RTMaterialData {
        var data = makeDefaultMaterial()

        // Determine physical material class first.
        var matClass: RTMatClass = .standard
        var flags: Int32 = mat.isDoubleSided ? RTMatFlags.doubleSided : 0
        if isSampledEmitter {
            flags |= RTMatFlags.isSampledEmitter
        }
        var ior: Float = 1.49
        var subsurface: Float = 0.0
        var sheen: Float = 0.0
        var absorb = SIMD4<Float>(0, 0, 0, 0.12)

        if mat === PlantProps.frontGlassMat || mat === PlantProps.glassThreadMat {
            matClass = .thinGlass
            ior = 1.50
            absorb = SIMD4<Float>(0.008, 0.005, 0.006, 0.12)
        } else if mat === PlantProps.greenFrontGlassMat {
            matClass = .thinGlass
            ior = 1.51
            absorb = SIMD4<Float>(0.022, 0.004, 0.015, 0.10)
        } else if mat === PlantProps.glassBaseMat {
            matClass = .solidGlass
            ior = 1.50
            absorb = SIMD4<Float>(0.012, 0.006, 0.008, 0.24)
        } else if mat === PlantProps.greenGlassBaseMat {
            matClass = .solidGlass
            ior = 1.51
            absorb = SIMD4<Float>(0.020, 0.004, 0.014, 0.22)
        } else if mat === PlantProps.waterBodyMat || mat === PlantProps.waterSurfaceMat {
            matClass = .water
            ior = 1.333
            absorb = SIMD4<Float>(0.003, 0.001, 0.001, 0.45)
        } else if world.isScenarioNode(node) && mat.lightingModel == .constant && !mat.writesToDepthBuffer && (mat.blendMode == .add || mat.blendMode == .alpha) {
            matClass = .emissiveCard
            flags |= RTMatFlags.doubleSided
            if mat.blendMode == .add {
                flags |= RTMatFlags.isAdditiveSprite
            }
        } else if mat.transparency < 0.88 && mat.lightingModel == .physicallyBased {
            // Translucent cyan/aqua IEM resin shell (Salnotes Zero), or fallback indigo resin.
            matClass = .indigoResin
            ior = 1.52
            if let col = (mat.diffuse.contents as? NSColor)?.usingColorSpace(.sRGB) {
                if col.redComponent > 0.65 && col.greenComponent > 0.65 && col.blueComponent > 0.65 {
                    ior = 1.15
                    absorb = SIMD4<Float>(0.12, 0.10, 0.08, 0.12)
                } else if col.greenComponent > col.redComponent * 1.8 && col.blueComponent > col.redComponent * 1.8 {
                    absorb = SIMD4<Float>(1.15, 0.04, 0.015, 0.16)
                } else {
                    absorb = SIMD4<Float>(1.45, 0.72, 0.10, 0.25)
                }
            } else {
                absorb = SIMD4<Float>(1.45, 0.72, 0.10, 0.25)
            }
        } else if isKeySide {
            matClass = .keySkirt
            subsurface = 0.28
        } else if isKeyTop {
            matClass = .sssPolymer
            subsurface = 0.22
        } else if isMonitor || isPhoneScreenNode(node, mat: mat) || (mat.emission.intensity > 0.35 && mat.clearCoat.contents as? Double ?? 0 > 0.6) {
            matClass = .screen
            if isMonitor { flags |= RTMatFlags.isMonitorScreen }
        } else if isPlateMaterial(mat, node: node, world: world) {
            matClass = .keyPlate
            flags |= RTMatFlags.isAnodizedMetal
        } else if isMouseOverlay {
            flags |= RTMatFlags.isButtonOverlay
            flags |= RTMatFlags.doubleSided
        } else if mat.name?.hasPrefix("foliage") == true
                    || mat.shaderModifiers?[.surface]?.contains("backlit foliage") == true
                    || mat.shaderModifiers?[.surface]?.contains("leaf") == true
                    || mat.shaderModifiers?[.fragment]?.contains("backlit foliage") == true {
            matClass = .foliage
            subsurface = 0.46
            absorb = SIMD4<Float>(0.55, 0.18, 0.90, 0.08)
            flags |= RTMatFlags.doubleSided
        } else if let name = node.name, name.contains("ukiru") || (mat.roughness.contents as? Double ?? 0) > 0.88 && mat.normal.contents != nil {
            matClass = .wovenCloth
            sheen = 0.42
        } else if isMatOrClothNode(node, mat: mat) {
            matClass = .wovenCloth
            sheen = 0.44
        } else if isPolymerDeviceNode(node, mat: mat) {
            matClass = .sssPolymer
            subsurface = 0.18
        }

        // Diffuse albedo / texture.
        let (diffCol, diffTex) = extractColorAndTexture(mat.diffuse.contents, isSRGB: true)
        let (normCol, normTex) = extractColorAndTexture(mat.normal.contents, isSRGB: false)
        _ = normCol
        let (roughVal, roughTex) = extractScalarAndTexture(mat.roughness.contents, defaultVal: 0.5)
        let (metalVal, metalTex) = extractScalarAndTexture(mat.metalness.contents, defaultVal: 0.0)
        let (_, aoTex) = extractScalarAndTexture(mat.ambientOcclusion.contents, defaultVal: 1.0)
        let (emCol, emTex) = extractColorAndTexture(mat.emission.contents, isSRGB: true)

        if isMonitor {
            monitorTextureIndex = emTex >= 0 ? emTex : diffTex
            let monImg = mat.emission.contents.flatMap { resolveCGImage($0) }
                ?? mat.diffuse.contents.flatMap { resolveCGImage($0) }
            monitorTextureHash = monImg.map(Self.imageFingerprint) ?? 0
        }

        // Anodized metal & walnut surface flags.
        if metalVal > 0.70 && roughVal < 0.38 && matClass == .standard {
            flags |= RTMatFlags.isAnodizedMetal
        }
        if let n = node.name, n.contains("desk") || n.contains("Slab") || n.contains("slab") || (roughTex >= 0 && metalVal < 0.05 && diffCol.x > diffCol.z * 1.4 && diffCol.x < 0.35) {
            flags |= RTMatFlags.isWalnutWood
        }
        if node.name == DeskScenarios.photoGroundName { flags |= RTMatFlags.isGroundProjection }

        let clearCoat = scalarValue(mat.clearCoat.contents, defaultVal: 0.0)
        let clearCoatRough = scalarValue(mat.clearCoatRoughness.contents, defaultVal: 0.06)
        let normInt = Float(mat.normal.intensity)

        var effectiveEmTex = emTex
        var linearEm = emCol * Float(mat.emission.intensity)
        var effectiveRough = max(0.012, roughVal)

        // Constant lighting model handling: unlit fixed emission with zero diffuse sky/area reflectance.
        var outDiff = diffCol
        if mat.lightingModel == .constant {
            if emTex >= 0 {
                linearEm = emCol * max(0.05, Float(mat.emission.intensity))
            } else {
                if matClass == .emissiveCard && diffTex >= 0 {
                    effectiveEmTex = diffTex
                }
                if mat.emission.contents != nil && dot(emCol, emCol) > 1e-4 {
                    linearEm = emCol * max(0.05, Float(mat.emission.intensity))
                } else {
                    let luma = dot(diffCol, SIMD3<Float>(0.2126, 0.7152, 0.0722))
                    if luma > 0.06 {
                        linearEm = diffCol * (mat.blendMode == .add ? 1.8 : 1.35)
                        if isMouseOverlay {
                            linearEm = SIMD3<Float>(0.28, 0.58, 1.0) * Float(node.opacity * 2.2)
                        }
                    } else if world.isScenarioNode(node) {
                        linearEm = diffCol
                    }
                }
            }
            if matClass != .emissiveCard {
                outDiff = .zero
                flags |= RTMatFlags.isUnlitConstant
            }
            effectiveRough = 0.35
        }

        let diffTransform = (diffTex < 0 && emTex >= 0 && !SCNMatrix4IsIdentity(mat.emission.contentsTransform))
            ? mat.emission.contentsTransform
            : mat.diffuse.contentsTransform

        data.baseColor = SIMD4<Float>(outDiff.x, outDiff.y, outDiff.z, Float(mat.transparency * node.opacity))
        data.emissionColor = SIMD4<Float>(linearEm.x, linearEm.y, linearEm.z, effectiveRough)
        data.params = SIMD4<Float>(metalVal, clearCoat, clearCoatRough, normInt)
        data.optics = SIMD4<Float>(ior, subsurface, sheen, isKeyTop ? 1.0 : 0.0)
        data.absorbColor = absorb
        data.diffuseUV = uvTransformVec(diffTransform)
        data.detailUV = uvTransformVec(mat.normal.contentsTransform)
        data.roughnessUV = uvTransformVec(mat.roughness.contents != nil ? mat.roughness.contentsTransform : mat.normal.contentsTransform)
        data.texIndices = SIMD4<Int32>(diffTex, normTex, roughTex, effectiveEmTex)
        data.extraTex = SIMD4<Int32>(metalTex, aoTex, matClass.rawValue, flags)
        return data
    }

    private func isPlateMaterial(_ mat: SCNMaterial, node: SCNNode, world: KeyboardScene) -> Bool {
        if let b = node.geometry as? SCNBox, isDescendant(node, of: world.keyboard) {
            if abs(Float(b.width) - Float(Layout.width - 0.04)) < 0.25 && abs(Float(b.length) - 5.08) < 0.25 {
                return true
            }
        }
        return false
    }

    private func isMatOrClothNode(_ node: SCNNode, mat: SCNMaterial) -> Bool {
        if let g = node.geometry as? SCNBox, abs(g.width - 42.0) < 3.0 && abs(g.length - 18.0) < 3.0 {
            return true
        }
        if let r = mat.roughness.contents as? Double, r > 0.88 && mat.normal.contents != nil && (mat.metalness.contents as? Double ?? 0) < 0.05 {
            return true
        }
        return false
    }

    private func isPolymerDeviceNode(_ node: SCNNode, mat: SCNMaterial) -> Bool {
        if (mat.metalness.contents as? Double ?? 0) < 0.06 && mat.clearCoat.contents as? Double ?? 0 < 0.3 {
            let rough = scalarValue(mat.roughness.contents, defaultVal: 0.5)
            if rough > 0.20 && rough < 0.65 && mat.diffuse.contents is NSColor {
                return true
            }
        }
        return false
    }

    func syncDirtyMaterials(world: KeyboardScene) -> Bool {
        var texChanged = false
        var visibilityChanged = false
        var minChanged = Int.max
        var maxChanged = -1

        for i in trackedMaterials.indices {
            let tm = trackedMaterials[i]
            let m = tm.material
            let idx = tm.index

            if tm.isKeyTop {
                // Legend texture or selection/heatmap emission update.
                let newDiffID = m.diffuse.contents.map { ObjectIdentifier($0 as AnyObject) }
                if newDiffID != tm.lastDiffuseID {
                    let newTex = replaceOrRegisterTexture(
                        m.diffuse.contents,
                        isSRGB: true,
                        oldTexIndex: materials[idx].texIndices.x,
                        excludingMaterialIndex: idx
                    )
                    if newTex >= 0 {
                        materials[idx].texIndices.x = newTex
                        materials[idx].baseColor = SIMD4<Float>(1, 1, 1, materials[idx].baseColor.w)
                        texChanged = true
                    } else {
                        let (diffCol, _) = extractColorAndTexture(m.diffuse.contents, isSRGB: true)
                        materials[idx].texIndices.x = -1
                        materials[idx].baseColor.x = diffCol.x
                        materials[idx].baseColor.y = diffCol.y
                        materials[idx].baseColor.z = diffCol.z
                    }
                    trackedMaterials[i].lastDiffuseID = newDiffID
                }
                let (emCol, _) = extractColorAndTexture(m.emission.contents, isSRGB: true)
                let em = emCol * Float(m.emission.intensity)
                materials[idx].emissionColor.x = em.x
                materials[idx].emissionColor.y = em.y
                materials[idx].emissionColor.z = em.z
                if idx < minChanged { minChanged = idx }
                if idx > maxChanged { maxChanged = idx }
            } else if tm.isKnob {
                let (emCol, _) = extractColorAndTexture(m.emission.contents, isSRGB: true)
                let em = emCol * Float(m.emission.intensity)
                materials[idx].emissionColor.x = em.x
                materials[idx].emissionColor.y = em.y
                materials[idx].emissionColor.z = em.z
                if idx < minChanged { minChanged = idx }
                if idx > maxChanged { maxChanged = idx }
            } else if tm.isMouseButtonOverlay {
                let opacity = tm.node?.opacity ?? 0
                let hiddenNow = opacity <= 0.01
                if hiddenNow != tm.lastButtonOverlayHidden {
                    trackedMaterials[i].lastButtonOverlayHidden = hiddenNow
                    visibilityChanged = true
                }
                let active = opacity > 0.05
                materials[idx].baseColor.w = active ? 0.55 : 0.0
                materials[idx].emissionColor.x = active ? 0.22 : 0
                materials[idx].emissionColor.y = active ? 0.52 : 0
                materials[idx].emissionColor.z = active ? 1.0 : 0
                if idx < minChanged { minChanged = idx }
                if idx > maxChanged { maxChanged = idx }
            } else if tm.isMonitorScreen || tm.isPhoneScreen {
                let newEmID = m.emission.contents.map { ObjectIdentifier($0 as AnyObject) }
                if newEmID != tm.lastEmissionID {
                    let newTex = replaceOrRegisterTexture(
                        m.emission.contents,
                        isSRGB: true,
                        oldTexIndex: materials[idx].texIndices.w,
                        excludingMaterialIndex: idx
                    )
                    if newTex >= 0 {
                        materials[idx].texIndices.w = newTex
                        materials[idx].texIndices.x = newTex
                        if tm.isMonitorScreen {
                            monitorTextureIndex = newTex
                            monitorTextureHash = resolveCGImageOptional(m.emission.contents).map(Self.imageFingerprint) ?? 0
                        }
                        texChanged = true
                    } else {
                        materials[idx].texIndices.w = -1
                        materials[idx].texIndices.x = -1
                        if tm.isMonitorScreen {
                            monitorTextureIndex = -1
                            monitorTextureHash = 0
                        }
                    }
                    trackedMaterials[i].lastEmissionID = newEmID
                }
                let (emCol, _) = extractColorAndTexture(m.emission.contents, isSRGB: true)
                let emRGB = materials[idx].texIndices.w >= 0 ? SIMD3<Float>(1, 1, 1) : emCol
                let emScaled = emRGB * Float(m.emission.intensity)
                materials[idx].emissionColor = SIMD4<Float>(
                    emScaled.x, emScaled.y, emScaled.z,
                    max(0.015, scalarValue(m.roughness.contents, defaultVal: 0.04))
                )
                if idx < minChanged { minChanged = idx }
                if idx > maxChanged { maxChanged = idx }
            } else {
                // Mouse DPI LED / side buttons / desk lamp bulb / underDesk strip.
                let (diffCol, _) = extractColorAndTexture(m.diffuse.contents, isSRGB: true)
                let (emCol, _) = extractColorAndTexture(m.emission.contents, isSRGB: true)
                let em = emCol * Float(m.emission.intensity)
                materials[idx].baseColor.x = diffCol.x
                materials[idx].baseColor.y = diffCol.y
                materials[idx].baseColor.z = diffCol.z
                materials[idx].emissionColor.x = em.x
                materials[idx].emissionColor.y = em.y
                materials[idx].emissionColor.z = em.z
                if idx < minChanged { minChanged = idx }
                if idx > maxChanged { maxChanged = idx }
            }
        }

        let envTexChanged = syncEnvironmentAndBackground(world: world)
        if texChanged || envTexChanged {
            rebuildTextureArgumentBuffer()
        }
        if minChanged <= maxChanged {
            markMaterialsDirty(range: minChanged...maxChanged)
            uploadMaterials()
        }
        return visibilityChanged
    }

    func syncBacklightOnly(world: KeyboardScene) {
        syncPlateGlowTexture(world: world)
        var minChanged = Int.max
        var maxChanged = -1
        for tm in trackedMaterials where tm.isKeySide {
            let (emCol, _) = extractColorAndTexture(tm.material.emission.contents, isSRGB: true)
            let em = emCol * Float(tm.material.emission.intensity)
            let idx = tm.index
            let cur = materials[idx].emissionColor
            if abs(cur.x - em.x) + abs(cur.y - em.y) + abs(cur.z - em.z) > 1e-4 {
                materials[idx].emissionColor.x = em.x
                materials[idx].emissionColor.y = em.y
                materials[idx].emissionColor.z = em.z
                if idx < minChanged { minChanged = idx }
                if idx > maxChanged { maxChanged = idx }
            }
        }
        if minChanged <= maxChanged {
            markMaterialsDirty(range: minChanged...maxChanged)
            uploadMaterials()
        }
    }

    func syncPlateGlowTexture(world: KeyboardScene) {
        guard !world.plateGlowAllBlack, let tex = plateGlowTexture else {
            return
        }
        let region = MTLRegionMake2D(0, 0, KeyboardScene.plateGlowWidth, KeyboardScene.plateGlowHeight)
        world.plateGlowBytes.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                tex.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: KeyboardScene.plateGlowWidth * 4)
            }
        }
        if tex.mipmapLevelCount > 1 && !pendingMipmapTextures.contains(where: { $0 === tex }) {
            pendingMipmapTextures.append(tex)
        }
    }

    func syncEnvironmentAndBackground(world: KeyboardScene) -> Bool {
        var envTexChanged = false
        if let envContents = world.scene.lightingEnvironment.contents {
            let envID = ObjectIdentifier(envContents as AnyObject)
            if envID != lastEnvContentID, let cgImg = resolveCGImage(envContents) {
                let idx = uploadFloatHDRTexture(
                    cgImg,
                    intoSlot: dynamicEnvTexIndex >= 0 ? Int(dynamicEnvTexIndex) : nil
                )
                dynamicEnvTexIndex = idx
                hdrEnvTextureIndex = idx
                environmentHash = Self.imageFingerprint(cgImg)
                if E68Perf.enabled { E68Perf.logLine("environment texture: \(cgImg.width)x\(cgImg.height) in slot \(idx)") }
                lastEnvContentID = envID
                envTexChanged = true
            }
        }

        if let faces = world.scene.background.contents as? [Any], faces.count == 6 {
            let token = faces.first.map { $0 as AnyObject }
            if lastBgCubemapRef !== token {
                lastBgCubemapRef = token
                uploadBackgroundCubemap(faces)
            }
        } else {
            lastBgCubemapRef = nil
        }
        return envTexChanged
    }

    func markMaterialsDirty(range: ClosedRange<Int>) {
        guard !materials.isEmpty else { return }
        let lo = max(0, range.lowerBound)
        let hi = min(materials.count - 1, range.upperBound)
        guard lo <= hi else { return }
        for s in materialDirtyRanges.indices {
            if let cur = materialDirtyRanges[s] {
                materialDirtyRanges[s] = (min(cur.0, lo), max(cur.1, hi))
            } else {
                materialDirtyRanges[s] = (lo, hi)
            }
        }
    }

    func uploadMaterials() {
        guard !materials.isEmpty else { return }
        let stride = MemoryLayout<RTMaterialData>.stride
        let totalBytes = stride * materials.count
        materialRingSlot = (materialRingSlot + 1) % materialBufferRing.count

        if materialBufferRing[materialRingSlot] == nil || materialBufferRing[materialRingSlot]!.length < totalBytes {
            let buf = device.makeBuffer(length: totalBytes, options: .storageModeShared)!
            memcpy(buf.contents(), &materials, totalBytes)
            materialBufferRing[materialRingSlot] = buf
            materialDirtyRanges[materialRingSlot] = nil
            materialBuffer = buf
            return
        }

        let buf = materialBufferRing[materialRingSlot]!
        if let (rawLo, rawHi) = materialDirtyRanges[materialRingSlot] {
            let lo = max(0, rawLo)
            let hi = min(materials.count - 1, rawHi)
            if lo <= hi {
                materials.withUnsafeBytes { src in
                    if let base = src.baseAddress {
                        memcpy(buf.contents().advanced(by: lo * stride), base.advanced(by: lo * stride), (hi - lo + 1) * stride)
                    }
                }
            }
            materialDirtyRanges[materialRingSlot] = nil
        }
        materialBuffer = buf
    }

    func rebuildTextureArgumentBuffer() {
        let resourceIDs = textures.map { $0.gpuResourceID }
        let count = resourceIDs.count
        let stride = MemoryLayout<MTLResourceID>.stride
        let byteLen = max(stride, count * stride)
        textureArgumentSlot = (textureArgumentSlot + 1) % textureArgumentRing.count
        var buf = textureArgumentRing[textureArgumentSlot]
        if buf == nil || buf!.length < byteLen {
            buf = device.makeBuffer(length: byteLen, options: .storageModeShared)
            textureArgumentRing[textureArgumentSlot] = buf
        }
        if count > 0, let buf {
            let bytesToCopy = count * stride
            _ = resourceIDs.withUnsafeBytes { ptr in
                memcpy(buf.contents(), ptr.baseAddress!, bytesToCopy)
            }
        }
        if let buf {
            textureArgumentBuffer = buf
        }
    }

    // MARK: - Texture Helpers

    private func isTextureShared(_ texIdx: Int32, excludingMaterialIndex: Int) -> Bool {
        if texIdx <= plateGlowTextureIndex || texIdx == hdrEnvTextureIndex {
            return true
        }
        for (i, m) in materials.enumerated() where i != excludingMaterialIndex {
            if m.texIndices.x == texIdx || m.texIndices.y == texIdx || m.texIndices.z == texIdx || m.texIndices.w == texIdx
                || m.extraTex.x == texIdx || m.extraTex.y == texIdx {
                return true
            }
        }
        return false
    }

    private func replaceOrRegisterTexture(_ contents: Any?, isSRGB: Bool, oldTexIndex: Int32, excludingMaterialIndex: Int) -> Int32 {
        guard let contents else { return -1 }
        let id = ObjectIdentifier(contents as AnyObject)
        let key = TextureCacheKey(objID: id, isSRGB: isSRGB)
        if let cached = textureCache[key] { return cached }
        guard let cgImg = resolveCGImage(contents) else { return -1 }
        let canReuse = oldTexIndex > plateGlowTextureIndex
            && Int(oldTexIndex) < textures.count
            && !isTextureShared(oldTexIndex, excludingMaterialIndex: excludingMaterialIndex)
        let idx = uploadImageTexture(cgImg, isSRGB: isSRGB, intoSlot: canReuse ? Int(oldTexIndex) : nil)
        if canReuse {
            textureCache = textureCache.filter { $0.value != idx }
        }
        textureCache[key] = idx
        return idx
    }

    private func registerOrReuseMetalTexture(_ tex: MTLTexture) -> Int32 {
        let id = ObjectIdentifier(tex)
        if let existing = rebuiltTextureByMetalID[id] { return existing }
        let idx = Int32(textures.count)
        textures.append(tex)
        rebuiltTextureByMetalID[id] = idx
        return idx
    }

    func registerTexture(_ contents: Any?, isSRGB: Bool) -> Int32 {
        guard let contents else { return -1 }
        let id = ObjectIdentifier(contents as AnyObject)
        let key = TextureCacheKey(objID: id, isSRGB: isSRGB)
        if let cached = textureCache[key] { return cached }
        guard let cgImg = resolveCGImage(contents) else { return -1 }
        let idx = uploadImageTexture(cgImg, isSRGB: isSRGB, intoSlot: nil)
        textureCache[key] = idx
        rebuiltTextureByMetalID[ObjectIdentifier(textures[Int(idx)])] = idx
        return idx
    }

    func resolveCGImageOptional(_ contents: Any?) -> CGImage? {
        guard let contents else { return nil }
        return resolveCGImage(contents)
    }

    private func resolveCGImage(_ contents: Any) -> CGImage? {
        if let ns = contents as? NSImage {
            return ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        let cf = contents as CFTypeRef
        if CFGetTypeID(cf) == CGImage.typeID {
            return (contents as! CGImage)
        }
        return nil
    }

    private func uploadImageTexture(_ img: CGImage, isSRGB: Bool, intoSlot: Int? = nil) -> Int32 {
        let w = max(1, img.width)
        let h = max(1, img.height)
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        // Preserve exact linear bytes for data maps (normal, roughness, metalness, AO) by matching
        // the CGImage RGB space during staging instead of applying a sRGB-to-linear gamma curve.
        let cs: CGColorSpace
        if isSRGB {
            cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        } else if let imgSpace = img.colorSpace, imgSpace.model == .rgb {
            cs = imgSpace
        } else {
            cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        if let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: bitmapInfo.rawValue) {
            // Note: CGContext draws image origin at bottom-left, SceneKit UVs match top-left image sampling cleanly with CGBitmap flip.
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            // Unpremultiply so straight RGB values are preserved when an alpha channel exists.
            let alphaInfo = img.alphaInfo
            let hasAlpha = !(alphaInfo == .none || alphaInfo == .noneSkipLast || alphaInfo == .noneSkipFirst)
            if hasAlpha {
                var p = 0
                while p < rgba.count {
                    let a = rgba[p + 3]
                    if a > 0 && a < 255 {
                        let inv = 255.0 / Float(a)
                        rgba[p]     = UInt8(min(255, Float(rgba[p]) * inv))
                        rgba[p + 1] = UInt8(min(255, Float(rgba[p + 1]) * inv))
                        rgba[p + 2] = UInt8(min(255, Float(rgba[p + 2]) * inv))
                    }
                    p += 4
                }
            }
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: isSRGB ? .rgba8Unorm_srgb : .rgba8Unorm,
            width: w, height: h, mipmapped: w > 1 && h > 1
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return fallbackBlackTexIndex }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: &rgba, bytesPerRow: w * 4)
        if desc.mipmapLevelCount > 1 {
            pendingMipmapTextures.append(tex)
        }
        if let slot = intoSlot, slot < textures.count {
            textures[slot] = tex
            return Int32(slot)
        }
        let idx = Int32(textures.count)
        textures.append(tex)
        return idx
    }

    /// A cheap content hash: the image drawn small, so any change of sky or of its brightness shows up.
    private static func imageFingerprint(_ image: CGImage) -> UInt64 {
        let w = 32, h = 16
        var px = [Float](repeating: 0, count: w * h * 4)
        let info = CGBitmapInfo.floatComponents.rawValue | CGImageByteOrderInfo.order32Host.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16,
                               space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, bitmapInfo: info) {
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var hash: UInt64 = 0xcbf29ce484222325 ^ UInt64(image.width) ^ (UInt64(image.height) << 20)
        for v in px {
            hash = (hash ^ UInt64((v * 512).rounded().bitPattern)) &* 0x100000001b3
        }
        return hash
    }

    private func uploadFloatHDRTexture(_ img: CGImage, intoSlot: Int? = nil) -> Int32 {
        let w = max(1, img.width), h = max(1, img.height)
        var floats = [Float](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let info = CGBitmapInfo.floatComponents.rawValue | CGImageByteOrderInfo.order32Host.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &floats, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16, space: cs, bitmapInfo: info) {
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        // Convert to IEEE 754 float16 (`Float16`) for fast GPU sampling & compact memory.
        var halves = [UInt16](repeating: 0, count: w * h * 4)
        for i in floats.indices {
            halves[i] = Float16(min(max(floats[i], 0), 65000)).bitPattern
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: true)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return fallbackBlackTexIndex }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: &halves, bytesPerRow: w * 8)
        if desc.mipmapLevelCount > 1 {
            pendingMipmapTextures.append(tex)
        }
        if let slot = intoSlot, slot < textures.count {
            textures[slot] = tex
            return Int32(slot)
        }
        let idx = Int32(textures.count)
        textures.append(tex)
        return idx
    }

    private func uploadBackgroundCubemap(_ faces: [Any]) {
        guard let firstImg = resolveCGImage(faces[0]) else { return }
        let size = max(1, firstImg.width)
        let desc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba8Unorm_srgb, size: size, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let cube = device.makeTexture(descriptor: desc) else { return }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        for slice in 0..<6 {
            if let img = resolveCGImage(faces[slice]),
               let ctx = CGContext(data: &rgba, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: cs, bitmapInfo: info) {
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
            }
            cube.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, slice: slice, withBytes: &rgba, bytesPerRow: size * 4, bytesPerImage: size * size * 4)
        }
        bgCubemapTexture = cube
    }

    func makeSolidTexture(r: UInt8, g: UInt8, b: UInt8, a: UInt8, srgb: Bool) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: srgb ? .rgba8Unorm_srgb : .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let tex = device.makeTexture(descriptor: desc)!
        var px: [UInt8] = [r, g, b, a]
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
        return tex
    }

}
