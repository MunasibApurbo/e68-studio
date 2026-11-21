import Foundation
import SceneKit
import Metal
import AppKit
import simd

/// Extracts SceneKit's node hierarchy, geometries, materials, textures, and lighting rigs
/// into unified GPU buffers and Metal hardware ray-tracing acceleration structures (`MTLAccelerationStructure`).
final class RTSceneExtractor {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    // Unified geometry buffers uploaded cleanly to unified GPU memory.
    private(set) var vertexBuffer: MTLBuffer!
    private(set) var indexBuffer: MTLBuffer!
    private(set) var submeshBuffer: MTLBuffer!
    var materialBuffer: MTLBuffer!
    private(set) var instanceBuffer: MTLBuffer!
    private(set) var primitiveBLASes: [MTLAccelerationStructure] = []
    private(set) var instanceAS: MTLAccelerationStructure?

    var textures: [MTLTexture] = []
    var textureArgumentBuffer: MTLBuffer!
    var hdrEnvTextureIndex: Int32 = -1
    var plateGlowTextureIndex: Int32 = -1
    var monitorTextureIndex: Int32 = -1
    var bgCubemapTexture: MTLTexture!

    struct StaticMaterialSnapshot {
        let data: RTMaterialData
        let diffTex: MTLTexture?
        let diffKey: TextureCacheKey?
        let normTex: MTLTexture?
        let normKey: TextureCacheKey?
        let roughTex: MTLTexture?
        let roughKey: TextureCacheKey?
        let emTex: MTLTexture?
        let emKey: TextureCacheKey?
        let metalTex: MTLTexture?
        let metalKey: TextureCacheKey?
        let aoTex: MTLTexture?
        let aoKey: TextureCacheKey?
    }

    // Scene metadata for fast dirty updates and O(1) GPU hit picking.
    var geometryCache: [ObjectIdentifier: CachedGeometry] = [:]
    var materialCache: [ObjectIdentifier: Int] = [:]
    var staticMaterialSnapshots: [ObjectIdentifier: StaticMaterialSnapshot] = [:]
    var seenSnapshotMaterialIDs: Set<ObjectIdentifier> = []
    var rebuiltTextureByMetalID: [ObjectIdentifier: Int32] = [:]
    var propsToReleaseAfterRebuild: [SCNMaterialProperty] = []
    var textureCache: [TextureCacheKey: Int32] = [:]
    var fallbackBlackTexIndex: Int32 = 0
    var fallbackWhiteTexIndex: Int32 = 1

    var vertices: [RTVertex] = []
    var indices: [UInt32] = []
    var submeshes: [RTSubmesh] = []
    var materials: [RTMaterialData] = []
    var instanceInfos: [RTInstanceInfo] = []
    var trackedInstances: [TrackedInstance] = []
    var trackedMaterials: [TrackedMaterial] = []
    private var pickedNodes: [SCNNode?] = [nil] // index 0 = miss

    private var instanceBufferRing: [MTLBuffer?] = [nil, nil, nil]
    private var instanceRingSlot = 0
    var materialBufferRing: [MTLBuffer?] = [nil, nil, nil]
    var materialDirtyRanges: [(Int, Int)?] = [nil, nil, nil]
    var materialRingSlot = 0
    private var tlasDescriptorRing: [MTLBuffer?] = [nil, nil, nil]
    private var tlasDescriptorSlot = 0
    private var pendingTLASDescriptor: MTLInstanceAccelerationStructureDescriptor?
    var textureArgumentRing: [MTLBuffer?] = [nil, nil, nil]
    var textureArgumentSlot = 0
    var pendingMipmapTextures: [MTLTexture] = []
    var dynamicEnvTexIndex: Int32 = -1
    var lastEnvContentID: ObjectIdentifier?

    // Baked light cache (live renderer): see `buildLightCacheTables()`.
    var lightCacheInstGeomBuffer: MTLBuffer?
    var lightCacheTriBuffer: MTLBuffer?
    var lightCacheSampleTriBuffer: MTLBuffer?
    var lightCacheSampleBuffer: MTLBuffer?
    var lightCacheSampleCountBuffer: MTLBuffer?
    var lightCacheDirectionBuffer: MTLBuffer?
    var lightCacheDeskSampleBuffer: MTLBuffer?
    /// Fingerprint of the sky image that lights the scene. Stored light saved under one sky must not be
    /// loaded under another, even when every lamp setting is the same.
    var environmentHash: UInt64 = 0
    /// Fingerprint of the monitor screen texture, so wallpaper swaps refresh stored monitor spill.
    var monitorTextureHash: UInt64 = 0
    var lightCacheSampleCount = 0
    var lightCacheLayoutHash: UInt64 = 0
    /// Bumped whenever the tables are rebuilt, so the renderer knows the stored lighting is gone.
    var lightCacheGeneration = 0

    private var blasScratchBuffer: MTLBuffer?
    private var tlasScratchBuffer: MTLBuffer?
    private var hasDirtyPrevTransforms = false

    // Cached dynamic light & plate node references.
    weak var plateNodeRef: SCNNode?
    weak var deskBulbNodeRef: SCNNode?
    weak var monitorScreenNodeRef: SCNNode?
    weak var underDeskStripNodeRef: SCNNode?
    var plateGlowTexture: MTLTexture?
    var lastBgCubemapRef: AnyObject?

    private var builtTopologyRevision: UInt64 = 0
    private var hasLoggedFirstRebuild = false
    private var syncedMaterialRevision: UInt64 = 0
    private var syncedTransformRevision: UInt64 = 0
    private var syncedBacklightRevision: UInt64 = 0
    var lastPhoneEmissionToken: ObjectIdentifier?
    weak var lastPhoneMaterial: SCNMaterial?
    lazy var prepRenderer: SCNRenderer = SCNRenderer(device: device, options: nil)

    struct CachedGeometry {
        let blasIndex: Int
        let blas: MTLAccelerationStructure
        let submeshBase: UInt32
        let submeshCount: UInt32
        let submeshBaseMaterials: [SCNMaterial]
        let isKeyPlate: Bool
    }

    struct TrackedInstance {
        let node: SCNNode
        let flags: UInt32
        let submeshBase: UInt32
        let nodeTag: UInt32
        let blasIndex: Int
        let isWallGlowOrConditional: Bool
        let isNoShadowOpaque: Bool
    }

    struct TrackedMaterial {
        let material: SCNMaterial
        weak var node: SCNNode?
        let index: Int
        let isKeyTop: Bool
        let isKeySide: Bool
        let isMouseButtonOverlay: Bool
        let isMonitorScreen: Bool
        let isPhoneScreen: Bool
        let isDeskLampEmitter: Bool
        let isUnderDeskEmitter: Bool
        let isKnob: Bool
        var lastDiffuseID: ObjectIdentifier?
        var lastEmissionID: ObjectIdentifier?
        var lastButtonOverlayHidden: Bool
    }

    struct TextureCacheKey: Hashable {
        let objID: ObjectIdentifier
        let isSRGB: Bool
    }

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
        createDefaultTextures()
    }

    // MARK: - Scene Sync Entrypoint

    struct SyncResult {
        var geometryChanged = false
        var dynamicLightingChanged = false
        var motionResetNeeded = false
    }

    @discardableResult
    func sync(with world: KeyboardScene) -> SyncResult {
        var result = SyncResult()

        if builtTopologyRevision != world.topologyRevision || instanceAS == nil {
            rebuildScene(world: world)
            builtTopologyRevision = world.topologyRevision
            syncedMaterialRevision = world.materialRevision
            syncedTransformRevision = world.transformRevision
            syncedBacklightRevision = world.backlightRevision
            result.geometryChanged = true
            result.dynamicLightingChanged = true
            result.motionResetNeeded = true
            return result
        }

        var needsTLASRebuild = false

        if syncedTransformRevision != world.transformRevision {
            updateInstanceTransforms(resetPrev: false)
            syncedTransformRevision = world.transformRevision
            hasDirtyPrevTransforms = true
            needsTLASRebuild = true
            result.dynamicLightingChanged = true
        } else if hasDirtyPrevTransforms {
            // Keep prevModelToWorld equal to modelToWorld once objects stop moving so motion vectors settle to zero.
            var clearedMotion = false
            for i in instanceInfos.indices {
                if instanceInfos[i].prevModelToWorld != instanceInfos[i].modelToWorld {
                    instanceInfos[i].prevModelToWorld = instanceInfos[i].modelToWorld
                    clearedMotion = true
                }
            }
            hasDirtyPrevTransforms = false
            if clearedMotion {
                uploadInstanceBuffer()
            }
        }

        // Catch autonomous updates (such as PhoneClock ticking every 15s-60s).
        var clockTicked = false
        if let pm = lastPhoneMaterial, let em = pm.emission.contents {
            let curID = ObjectIdentifier(em as AnyObject)
            if curID != lastPhoneEmissionToken {
                lastPhoneEmissionToken = curID
                clockTicked = true
            }
        }

        if syncedMaterialRevision != world.materialRevision || clockTicked {
            let visibilityChanged = syncDirtyMaterials(world: world)
            syncedMaterialRevision = world.materialRevision
            if visibilityChanged {
                needsTLASRebuild = true
            }
            result.dynamicLightingChanged = true
        }

        if syncedBacklightRevision != world.backlightRevision {
            syncBacklightOnly(world: world)
            syncedBacklightRevision = world.backlightRevision
            result.dynamicLightingChanged = true
        }

        if needsTLASRebuild {
            rebuildTLAS()
            result.geometryChanged = true
        }

        return result
    }

    func hasAutonomousChange() -> Bool {
        guard let pm = lastPhoneMaterial, let em = pm.emission.contents else { return false }
        return ObjectIdentifier(em as AnyObject) != lastPhoneEmissionToken
    }

    /// Encodes queued mipmap generation and TLAS rebuild onto the frame's command buffer without stalling the CPU.
    func encodePendingWork(onto cmd: MTLCommandBuffer) {
        if !pendingMipmapTextures.isEmpty, let blit = cmd.makeBlitCommandEncoder() {
            for tex in pendingMipmapTextures where tex.mipmapLevelCount > 1 {
                blit.generateMipmaps(for: tex)
            }
            blit.endEncoding()
            pendingMipmapTextures.removeAll(keepingCapacity: true)
        }
        if let pending = pendingTLASDescriptor, let tlas = instanceAS, let scratch = tlasScratchBuffer,
           let enc = cmd.makeAccelerationStructureCommandEncoder() {
            enc.build(accelerationStructure: tlas, descriptor: pending, scratchBuffer: scratch, scratchBufferOffset: 0)
            enc.endEncoding()
            pendingTLASDescriptor = nil
        }
    }

    /// Snapshots `prevModelToWorld = modelToWorld` cleanly for synchronous offline renders.
    func commitPreviousTransforms() {
        guard hasDirtyPrevTransforms else { return }
        for i in instanceInfos.indices {
            instanceInfos[i].prevModelToWorld = instanceInfos[i].modelToWorld
        }
        hasDirtyPrevTransforms = false
        uploadInstanceBuffer()
    }

    func node(forTag tag: UInt32) -> SCNNode? {
        let idx = Int(tag)
        guard idx > 0 && idx < pickedNodes.count else { return nil }
        return pickedNodes[idx]
    }

    // MARK: - Full Topology & BLAS Build

    private func createDefaultTextures() {
        textures.removeAll()
        textureCache.removeAll()

        let black = makeSolidTexture(r: 0, g: 0, b: 0, a: 255, srgb: false)
        let white = makeSolidTexture(r: 255, g: 255, b: 255, a: 255, srgb: false)
        fallbackBlackTexIndex = Int32(textures.count); textures.append(black)
        fallbackWhiteTexIndex = Int32(textures.count); textures.append(white)

        // 256x80 RGBA8 sRGB live texture for keywell plate glow (mipmapped for live RGB spill blur).
        let glowDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: KeyboardScene.plateGlowWidth,
            height: KeyboardScene.plateGlowHeight,
            mipmapped: true
        )
        glowDesc.usage = [.shaderRead]
        glowDesc.storageMode = .shared
        plateGlowTexture = device.makeTexture(descriptor: glowDesc)!
        plateGlowTextureIndex = Int32(textures.count)
        textures.append(plateGlowTexture!)

        // Dummy 1x1x6 cubemap texture for room scenario fallback.
        let cubeDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba8Unorm_srgb, size: 1, mipmapped: false)
        cubeDesc.usage = [.shaderRead]
        bgCubemapTexture = device.makeTexture(descriptor: cubeDesc)!
    }

    private func rebuildScene(world: KeyboardScene) {
        let perfFirst = E68Perf.enabled && !hasLoggedFirstRebuild
        let perfT0 = perfFirst ? CACurrentMediaTime() : 0
        vertices.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        submeshes.removeAll(keepingCapacity: true)
        materials.removeAll(keepingCapacity: true)
        instanceInfos.removeAll(keepingCapacity: true)
        trackedInstances.removeAll(keepingCapacity: true)
        trackedMaterials.removeAll(keepingCapacity: true)
        geometryCache.removeAll(keepingCapacity: true)
        materialCache.removeAll(keepingCapacity: true)
        primitiveBLASes.removeAll(keepingCapacity: true)
        pickedNodes = [nil]

        // Preserve base textures (black, white, plateGlow) and clear dynamic textures.
        let persistentCount = Int(plateGlowTextureIndex) + 1
        if textures.count > persistentCount {
            textures.removeSubrange(persistentCount...)
        }
        textureCache.removeAll()
        seenSnapshotMaterialIDs.removeAll(keepingCapacity: true)
        rebuiltTextureByMetalID.removeAll(keepingCapacity: true)
        for i in textures.indices {
            rebuiltTextureByMetalID[ObjectIdentifier(textures[i])] = Int32(i)
        }
        propsToReleaseAfterRebuild.removeAll(keepingCapacity: true)
        hdrEnvTextureIndex = -1
        dynamicEnvTexIndex = -1
        lastEnvContentID = nil
        monitorTextureIndex = -1
        monitorTextureHash = 0
        pendingMipmapTextures.removeAll(keepingCapacity: true)
        pendingTLASDescriptor = nil
        hasDirtyPrevTransforms = false

        plateNodeRef = nil
        deskBulbNodeRef = nil
        monitorScreenNodeRef = nil
        underDeskStripNodeRef = nil
        lastPhoneMaterial = nil

        autoreleasepool {
            collectNodes(world.scene.rootNode, world: world, parentHidden: false)
        }

        // Keep cached material snapshots across scenario switches (e.g., hidden roomRootNode)
        // and preserve SceneKit material property contents so reopened windows / shared materials never lose textures.
        seenSnapshotMaterialIDs.removeAll(keepingCapacity: true)
        rebuiltTextureByMetalID.removeAll(keepingCapacity: true)
        propsToReleaseAfterRebuild.removeAll(keepingCapacity: true)
        if world.usesHardwareRayTracer {
            DeskTextures.releaseStaticCaches()
        }

        if vertices.isEmpty {
            vertices.append(RTVertex(px: 0, py: 0, pz: 0, nx: 0, ny: 1, nz: 0, u: 0, v: 0, cr: 1, cg: 1, cb: 1, ca: 1))
            indices.append(contentsOf: [0, 0, 0])
        }
        if materials.isEmpty {
            materials.append(makeDefaultMaterial())
        }

        // Upload static buffers into unified GPU memory and reset dynamic ring buffers.
        vertexBuffer = makeBuffer(from: vertices)
        indexBuffer = makeBuffer(from: indices)
        submeshBuffer = makeBuffer(from: submeshes)
        materialBufferRing = [nil, nil, nil]
        materialDirtyRanges = [nil, nil, nil]
        materialRingSlot = 0
        if !materials.isEmpty {
            markMaterialsDirty(range: 0...(materials.count - 1))
        }
        uploadMaterials()

        instanceBufferRing = [nil, nil, nil]
        instanceRingSlot = 0
        tlasDescriptorRing = [nil, nil, nil]
        tlasDescriptorSlot = 0
        textureArgumentRing = [nil, nil, nil]
        textureArgumentSlot = 0

        buildPrimitiveBLASes(world: world)

        // Bindless texture upload for HDR env, wallpaper, and plate glow.
        _ = syncEnvironmentAndBackground(world: world)
        syncPlateGlowTexture(world: world)
        rebuildTextureArgumentBuffer()

        updateInstanceTransforms(resetPrev: true)
        if PathTracerRenderer.liveMode {
            buildLightCacheTables()
            uploadInstanceBuffer()
        }
        rebuildTLAS()
        let vertexCount = vertices.count
        vertices.removeAll(keepingCapacity: false)
        indices.removeAll(keepingCapacity: false)
        if perfFirst {
            hasLoggedFirstRebuild = true
            E68Perf.logLine(String(format: "first rebuildScene: %.1f ms (instances=%d, blas=%d, textures=%d, verts=%d)",
                                   (CACurrentMediaTime() - perfT0) * 1000.0,
                                   instanceInfos.count, primitiveBLASes.count, textures.count, vertexCount))
        }
    }

    private func collectNodes(_ node: SCNNode, world: KeyboardScene, parentHidden: Bool) {
        let isHidden = parentHidden || node.isHidden
        // Record physical emitter locator nodes regardless of geometry skipping.
        switch node.name {
        case "prop.deskLamp.bulb": deskBulbNodeRef = node
        case "prop.monitor.screen": monitorScreenNodeRef = node
        case "prop.underDeskGlow": underDeskStripNodeRef = node
        default: break
        }

        if let geom = node.geometry, !isHidden, !shouldSkipGeometryNode(node, geometry: geom, world: world) {
            let geomID = ObjectIdentifier(geom)
            let isKeyboard = isDescendant(node, of: world.keyboard)
            let cachedGeom: CachedGeometry
            if let existing = geometryCache[geomID] {
                cachedGeom = existing
            } else if let built = extractGeometry(geom, node: node, world: world) {
                geometryCache[geomID] = built
                cachedGeom = built
            } else {
                for child in node.childNodes { collectNodes(child, world: world, parentHidden: isHidden) }
                return
            }

            if cachedGeom.isKeyPlate { plateNodeRef = node }

            let nodeTag = UInt32(pickedNodes.count)
            pickedNodes.append(node)

            var flags: UInt32 = 0
            if isKeyboard { flags |= RTInstanceFlags.isKeyboard }
            if hasGlassOrWaterMaterial(geom) { flags |= RTInstanceFlags.isGlassWater }
            if !node.castsShadow { flags |= RTInstanceFlags.noCastShadow }
            if geom.materials.contains(where: { $0.isDoubleSided }) { flags |= RTInstanceFlags.doubleSided }

            let worldMat = node.simdWorldTransform
            let m3 = upperLeft3x3(worldMat)
            if simd_determinant(m3) < 0 { flags |= RTInstanceFlags.mirroredDet }

            var hasRefractiveGlassSubmesh = false
            for s in 0..<Int(cachedGeom.submeshCount) {
                let matIdx = Int(submeshes[Int(cachedGeom.submeshBase) + s].materialIndex)
                if matIdx < materials.count {
                    let mc = materials[matIdx].extraTex.z
                    if mc == RTMatClass.thinGlass.rawValue
                        || mc == RTMatClass.solidGlass.rawValue
                        || mc == RTMatClass.water.rawValue
                        || mc == RTMatClass.indigoResin.rawValue {
                        hasRefractiveGlassSubmesh = true
                        break
                    }
                }
            }

            let tracked = TrackedInstance(
                node: node,
                flags: flags,
                submeshBase: cachedGeom.submeshBase,
                nodeTag: nodeTag,
                blasIndex: cachedGeom.blasIndex,
                isWallGlowOrConditional: (node.name ?? "").hasPrefix("env.wallGlow."),
                isNoShadowOpaque: (!node.castsShadow) && !hasRefractiveGlassSubmesh
            )
            trackedInstances.append(tracked)
            instanceInfos.append(RTInstanceInfo(
                modelToWorld: worldMat,
                prevModelToWorld: worldMat,
                normalToWorld: computeNormalMatrix4(worldMat),
                submeshBase: cachedGeom.submeshBase,
                nodeTag: nodeTag,
                flags: flags,
                reserved: 0
            ))
        }

        for child in node.childNodes {
            collectNodes(child, world: world, parentHidden: isHidden)
        }
    }

    private func shouldSkipGeometryNode(_ node: SCNNode, geometry: SCNGeometry, world: KeyboardScene) -> Bool {
        if let name = node.name {
            if name == "wallShadowPlane" || name.hasPrefix("env.wallGlow.") || name == "keyboardShadow" {
                return true
            }
        }
        // Skip rasterizer-only shadow decals, caustics, back-shell pass, and alpha glow cards.
        let mats = geometry.materials
        if mats.isEmpty { return false }
        let inScenario = world.isScenarioNode(node)
        for m in mats {
            if m === PlantProps.backGlassMat || m === PlantProps.greenBackGlassMat
                || m === PlantProps.causticMat
                || m === world.plateGlowMaterial || m === world.knobGlowMaterial {
                return true
            }
            if m.lightingModel == .constant && !m.writesToDepthBuffer && m.blendMode != .replace {
                let isMouseButton = (node.name == TechProps.MouseParts.left || node.name == TechProps.MouseParts.right)
                if isMouseButton { continue }
                if inScenario && (m.blendMode == .add || m.blendMode == .alpha) {
                    continue
                }
                // Skip shaderModifier-driven particles/rays and planar contact shadows on non-scenario props.
                if !(m.shaderModifiers?.isEmpty ?? true) {
                    return true
                }
                // Skip planar contact shadows (`addContactShadow`, `ringShadowMat`).
                if resolveCGImageOptional(m.diffuse.contents) != nil {
                    return true
                }
                if m.transparency < 0.99 || m.blendMode == .alpha || m.blendMode == .multiply || (m.blendMode == .add && geometry.sources(for: .color).isEmpty) {
                    return true
                }
            }
        }
        return false
    }

    private func hasGlassOrWaterMaterial(_ geom: SCNGeometry) -> Bool {
        for m in geom.materials {
            if m === PlantProps.frontGlassMat || m === PlantProps.glassBaseMat
                || m === PlantProps.glassThreadMat || m === PlantProps.waterBodyMat
                || m === PlantProps.waterSurfaceMat
                || m === PlantProps.greenFrontGlassMat || m === PlantProps.greenGlassBaseMat {
                return true
            }
        }
        return false
    }

    /// SceneKit's built-in shapes (SCNSphere, SCNBox, SCNShape...) hold a unit-sized proxy mesh until a
    /// renderer prepares them. Preparing a material-less copy builds the real mesh without making SceneKit
    /// compile the scene's shaders and upload its textures a second time (about 420 MB and a second at launch).
    private func tessellatedGeometry(_ geom: SCNGeometry) -> SCNGeometry {
        guard type(of: geom) != SCNGeometry.self, let mesh = geom.copy() as? SCNGeometry else { return geom }
        mesh.materials = []
        _ = prepRenderer.prepare(mesh, shouldAbortBlock: nil)
        return mesh
    }

    private func extractGeometry(_ geom: SCNGeometry, node: SCNNode, world: KeyboardScene) -> CachedGeometry? {
        let mesh = tessellatedGeometry(geom)
        guard let vSrc = mesh.sources(for: .vertex).first else { return nil }
        let nSrc = mesh.sources(for: .normal).first
        let uvSrc = mesh.sources(for: .texcoord).first
        let cSrc = mesh.sources(for: .color).first

        let vertCount = vSrc.vectorCount
        guard vertCount > 0, mesh.elementCount > 0 else { return nil }

        let baseVertexOffset = UInt32(vertices.count)
        let positions = readFloat3Source(vSrc)
        let normals = nSrc.map { readFloat3Source($0) }
        let uvs = uvSrc.map { readFloat2Source($0) }
        let colors = cSrc.map { readFloat4Source($0) }

        for i in 0..<vertCount {
            let p = positions[i]
            let n = (normals != nil && i < normals!.count) ? normals![i] : SIMD3<Float>(0, 1, 0)
            let t = (uvs != nil && i < uvs!.count) ? uvs![i] : SIMD2<Float>(0, 0)
            let c = (colors != nil && i < colors!.count) ? colors![i] : SIMD4<Float>(1, 1, 1, 1)
            vertices.append(RTVertex(
                px: p.x, py: p.y, pz: p.z,
                nx: n.x, ny: n.y, nz: n.z,
                u: t.x, v: t.y,
                cr: c.x, cg: c.y, cb: c.z, ca: c.w
            ))
        }

        let mats = geom.materials.isEmpty ? [SCNMaterial()] : geom.materials
        let submeshBase = UInt32(submeshes.count)
        var addedSubmeshes: UInt32 = 0
        var isKeyPlate = false

        let nodeName = node.name ?? ""
        let isKeyCap = nodeName.hasPrefix("k") && Int(nodeName.dropFirst()) != nil

        let elements = mesh.elements
        for elemIdx in 0..<elements.count {
            let elem = elements[elemIdx]
            let mat = mats[elemIdx % mats.count]
            let matIndex = registerMaterial(mat, node: node, world: world, isKeyCap: isKeyCap)
            let triIndices = readTriangleIndices(elem)
            guard !triIndices.isEmpty else { continue }

            // Compute flat normals only if vertex source omitted normals.
            if nSrc == nil {
                var accumNormals = [SIMD3<Float>](repeating: .zero, count: vertCount)
                var t = 0
                while t + 2 < triIndices.count {
                    let i0 = Int(triIndices[t]), i1 = Int(triIndices[t + 1]), i2 = Int(triIndices[t + 2])
                    if i0 < vertCount && i1 < vertCount && i2 < vertCount {
                        let e1 = positions[i1] - positions[i0]
                        let e2 = positions[i2] - positions[i0]
                        let fn = simd_cross(e1, e2)
                        accumNormals[i0] += fn; accumNormals[i1] += fn; accumNormals[i2] += fn
                    }
                    t += 3
                }
                for v in 0..<vertCount {
                    let len = simd_length(accumNormals[v])
                    let n = len > 1e-6 ? accumNormals[v] / len : SIMD3<Float>(0, 1, 0)
                    let vi = Int(baseVertexOffset) + v
                    vertices[vi].nx = n.x; vertices[vi].ny = n.y; vertices[vi].nz = n.z
                }
            }

            let elemIndexOffset = UInt32(indices.count)
            indices.append(contentsOf: triIndices)

            var subFlags: UInt32 = 0
            if materials[matIndex].extraTex.z == RTMatClass.keySkirt.rawValue {
                subFlags |= RTSubmeshFlags.isKeySide
            }
            if materials[matIndex].extraTex.z == RTMatClass.keyPlate.rawValue {
                subFlags |= RTSubmeshFlags.isKeyPlate
                isKeyPlate = true
            }

            submeshes.append(RTSubmesh(
                vertexOffset: baseVertexOffset,
                indexOffset: elemIndexOffset,
                materialIndex: UInt32(matIndex),
                flags: subFlags
            ))
            addedSubmeshes += 1
        }

        guard addedSubmeshes > 0 else { return nil }
        let blasIndex = primitiveBLASes.count // populated in buildPrimitiveBLASes
        // Store placeholder entry; actual BLAS built right after vertex/index buffers are finalized.
        return CachedGeometry(
            blasIndex: blasIndex,
            blas: dummyBLASPlaceholder,
            submeshBase: submeshBase,
            submeshCount: addedSubmeshes,
            submeshBaseMaterials: mats,
            isKeyPlate: isKeyPlate
        )
    }

    private lazy var dummyBLASPlaceholder: MTLAccelerationStructure = {
        let desc = MTLPrimitiveAccelerationStructureDescriptor()
        let empty = MTLAccelerationStructureTriangleGeometryDescriptor()
        empty.vertexBuffer = device.makeBuffer(length: 48, options: .storageModeShared)
        empty.triangleCount = 0
        desc.geometryDescriptors = [empty]
        let sizes = device.accelerationStructureSizes(descriptor: desc)
        let accel = device.makeAccelerationStructure(size: max(sizes.accelerationStructureSize, 256))!
        return accel
    }()

    private func buildPrimitiveBLASes(world: KeyboardScene) {
        // Order cached geometries stably by submeshBase so indices match.
        let ordered = geometryCache.values.sorted { $0.submeshBase < $1.submeshBase }
        var mapOldToNew = [UInt32: Int]()

        var descriptors = [MTLPrimitiveAccelerationStructureDescriptor]()
        descriptors.reserveCapacity(ordered.count)

        for entry in ordered {
            var triGeoms = [MTLAccelerationStructureTriangleGeometryDescriptor]()
            for s in 0..<Int(entry.submeshCount) {
                let subIdx = Int(entry.submeshBase) + s
                let sub = submeshes[subIdx]
                let nextOffset = (subIdx + 1 < submeshes.count && s + 1 < Int(entry.submeshCount))
                    ? submeshes[subIdx + 1].indexOffset
                    : nextIndexOffsetForSubmesh(subIdx)
                let triCount = Int(nextOffset - sub.indexOffset) / 3
                guard triCount > 0 else { continue }

                let triDesc = MTLAccelerationStructureTriangleGeometryDescriptor()
                triDesc.vertexBuffer = vertexBuffer
                triDesc.vertexBufferOffset = Int(sub.vertexOffset) * MemoryLayout<RTVertex>.stride
                triDesc.vertexFormat = .float3
                triDesc.vertexStride = MemoryLayout<RTVertex>.stride
                triDesc.indexBuffer = indexBuffer
                triDesc.indexBufferOffset = Int(sub.indexOffset) * MemoryLayout<UInt32>.stride
                triDesc.indexType = .uint32
                triDesc.triangleCount = triCount
                // Keep all triangles hardware-opaque; glass/water BSDFs & multi-hop shadow rays handle dielectric transmission cleanly.
                triDesc.opaque = true
                triDesc.allowDuplicateIntersectionFunctionInvocation = false
                triGeoms.append(triDesc)
            }
            let blasDesc = MTLPrimitiveAccelerationStructureDescriptor()
            blasDesc.geometryDescriptors = triGeoms
            descriptors.append(blasDesc)
            mapOldToNew[entry.submeshBase] = descriptors.count - 1
        }

        // Update tracked instances to point to compact BLAS list.
        for i in trackedInstances.indices {
            let subBase = trackedInstances[i].submeshBase
            let newIdx = mapOldToNew[subBase] ?? 0
            trackedInstances[i] = TrackedInstance(
                node: trackedInstances[i].node,
                flags: trackedInstances[i].flags,
                submeshBase: subBase,
                nodeTag: trackedInstances[i].nodeTag,
                blasIndex: newIdx,
                isWallGlowOrConditional: trackedInstances[i].isWallGlowOrConditional,
                isNoShadowOpaque: trackedInstances[i].isNoShadowOpaque
            )
        }

        var totalScratch = 0
        var scratchOffsets = [Int]()
        scratchOffsets.reserveCapacity(descriptors.count)
        var builtBLASes = [MTLAccelerationStructure]()
        builtBLASes.reserveCapacity(descriptors.count)
        for d in descriptors {
            let sizes = device.accelerationStructureSizes(descriptor: d)
            let alignedOffset = (totalScratch + 255) & ~255
            let scratchNeed = max(sizes.buildScratchBufferSize, 256)
            scratchOffsets.append(alignedOffset)
            totalScratch = alignedOffset + scratchNeed
            builtBLASes.append(device.makeAccelerationStructure(size: max(sizes.accelerationStructureSize, 256))!)
        }
        primitiveBLASes = builtBLASes

        if blasScratchBuffer == nil || blasScratchBuffer!.length < totalScratch {
            blasScratchBuffer = device.makeBuffer(length: max(totalScratch, 4096), options: .storageModePrivate)
        }

        guard let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeAccelerationStructureCommandEncoder() else { return }
        for (i, d) in descriptors.enumerated() {
            enc.build(accelerationStructure: primitiveBLASes[i], descriptor: d, scratchBuffer: blasScratchBuffer!, scratchBufferOffset: scratchOffsets[i])
        }
        enc.endEncoding()
        cmd.commit()
        // The build keeps the scratch memory alive until it finishes; holding on to it afterwards
        // cost about 50 MB for a buffer that is only needed again if the scene is rebuilt.
        blasScratchBuffer = nil
    }

    func nextIndexOffsetForSubmesh(_ subIdx: Int) -> UInt32 {
        if subIdx + 1 < submeshes.count {
            return submeshes[subIdx + 1].indexOffset
        }
        return UInt32(indices.count)
    }

    // MARK: - TLAS Update

    private func updateInstanceTransforms(resetPrev: Bool) {
        for i in trackedInstances.indices {
            let tr = trackedInstances[i]
            let m = tr.node.simdWorldTransform
            instanceInfos[i].prevModelToWorld = resetPrev ? m : instanceInfos[i].modelToWorld
            instanceInfos[i].modelToWorld = m
            instanceInfos[i].normalToWorld = computeNormalMatrix4(m)
        }
        uploadInstanceBuffer()
    }

    private func uploadInstanceBuffer() {
        guard !instanceInfos.isEmpty else { return }
        let byteCount = MemoryLayout<RTInstanceInfo>.stride * instanceInfos.count
        instanceRingSlot = (instanceRingSlot + 1) % instanceBufferRing.count
        var buf = instanceBufferRing[instanceRingSlot]
        if buf == nil || buf!.length < byteCount {
            buf = device.makeBuffer(length: byteCount, options: .storageModeShared)
            instanceBufferRing[instanceRingSlot] = buf
        }
        if let buf {
            memcpy(buf.contents(), &instanceInfos, byteCount)
            instanceBuffer = buf
        }
    }

    private func rebuildTLAS() {
        var descs = [MTLAccelerationStructureInstanceDescriptor]()
        descs.reserveCapacity(trackedInstances.count)

        for i in trackedInstances.indices {
            let tr = trackedInstances[i]
            var d = MTLAccelerationStructureInstanceDescriptor()
            d.accelerationStructureIndex = UInt32(tr.blasIndex)
            d.options = [.disableTriangleCulling, .opaque]
            let matIdx = Int(submeshes[Int(tr.submeshBase)].materialIndex)
            let isEmissiveCard = matIdx < materials.count && materials[matIdx].extraTex.z == RTMatClass.emissiveCard.rawValue
            let isButtonOverlayHidden = isHiddenButtonOverlay(tr.node)
            d.mask = isButtonOverlayHidden ? 0 : (isEmissiveCard ? 0x02 : (tr.isNoShadowOpaque ? 0x04 : 0xFF))
            d.intersectionFunctionTableOffset = 0
            d.transformationMatrix = packedFloat4x3(from: instanceInfos[i].modelToWorld)
            descs.append(d)
        }

        let descBytes = max(1, descs.count) * MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride
        tlasDescriptorSlot = (tlasDescriptorSlot + 1) % tlasDescriptorRing.count
        var descBuf = tlasDescriptorRing[tlasDescriptorSlot]
        if descBuf == nil || descBuf!.length < descBytes {
            descBuf = device.makeBuffer(length: descBytes, options: .storageModeShared)
            tlasDescriptorRing[tlasDescriptorSlot] = descBuf
        }
        if !descs.isEmpty, let descBuf {
            _ = descs.withUnsafeBytes { memcpy(descBuf.contents(), $0.baseAddress!, descBytes) }
        }

        let tlasDesc = MTLInstanceAccelerationStructureDescriptor()
        tlasDesc.instancedAccelerationStructures = primitiveBLASes
        tlasDesc.instanceCount = descs.count
        tlasDesc.instanceDescriptorBuffer = descBuf

        let sizes = device.accelerationStructureSizes(descriptor: tlasDesc)
        if instanceAS == nil || instanceAS!.size < sizes.accelerationStructureSize {
            instanceAS = device.makeAccelerationStructure(size: max(sizes.accelerationStructureSize, 1024))
        }
        if tlasScratchBuffer == nil || tlasScratchBuffer!.length < sizes.buildScratchBufferSize {
            tlasScratchBuffer = device.makeBuffer(length: max(sizes.buildScratchBufferSize, 4096), options: .storageModePrivate)
        }

        // Encode the TLAS build onto the frame's own command buffer instead of stalling the main thread.
        pendingTLASDescriptor = tlasDesc
    }

    func isHiddenButtonOverlay(_ node: SCNNode) -> Bool {
        if node.opacity <= 0.01 { return true }
        return false
    }

}
