import Foundation
import SceneKit
import Metal
import AppKit
import simd

extension RTSceneExtractor {
    // MARK: - Frame Uniforms Packing

    func buildFrameUniforms(
        world: KeyboardScene,
        renderSize: SIMD2<UInt32>,
        outputSize: SIMD2<UInt32>,
        jitter: SIMD2<Float>,
        prevJitter: SIMD2<Float>,
        prevViewProj: simd_float4x4,
        frameIndex: UInt32,
        sampleIndex: UInt32,
        maxBounces: UInt32,
        isProgressive: Bool
    ) -> (RTFrameUniforms, simd_float4x4) {
        let camTransform = world.cameraNode.simdWorldTransform
        let camPos = SIMD3<Float>(camTransform.columns.3.x, camTransform.columns.3.y, camTransform.columns.3.z)
        let camRight = simd_normalize(SIMD3<Float>(camTransform.columns.0.x, camTransform.columns.0.y, camTransform.columns.0.z))
        let camUp = simd_normalize(SIMD3<Float>(camTransform.columns.1.x, camTransform.columns.1.y, camTransform.columns.1.z))
        let camForward = -simd_normalize(SIMD3<Float>(camTransform.columns.2.x, camTransform.columns.2.y, camTransform.columns.2.z))

        let fovDeg = Float(world.cameraNode.camera?.fieldOfView ?? 56)
        let tanHalfFov = tan((fovDeg * .pi / 180.0) * 0.5)
        let aspect = Float(outputSize.x) / Float(max(1, outputSize.y))

        let worldToView = simd_inverse(camTransform)
        let nearZ: Float = 0.25
        let farZ: Float = 1500.0
        let f = 1.0 / tanHalfFov
        // Standard RH projection into Metal clip [0, 1] depth range.
        let viewToClip = simd_float4x4(
            SIMD4<Float>(f / aspect, 0, 0, 0),
            SIMD4<Float>(0, f, 0, 0),
            SIMD4<Float>(0, 0, farZ / (nearZ - farZ), -1),
            SIMD4<Float>(0, 0, (nearZ * farZ) / (nearZ - farZ), 0)
        )
        let curViewProj = viewToClip * worldToView

        // Subtle photographic lens depth-of-field focused on camera target.
        let focusDist = max(4.0, simd_length(world.pose.target - camPos))
        let aperture: Float = (isProgressive && focusDist < 40.0) ? 0.036 : (isProgressive ? 0.018 : 0.0)

        let mood = world.activeMood
        let scenario = world.activeScenario
        let isRoom = scenario == .room
        let exposureOffset = Float(world.cameraNode.camera?.exposureOffset ?? 0)
        let exposureScale = exp2(exposureOffset) * (isRoom ? 1.06 : 1.05)

        // Room & scenario NEE lights matched closely to artistic lighting rig.
        let deskOn = world.isDeskLampEnabled

        let keyLightW = (world.keyLightNode?.simdWorldPosition ?? SIMD3<Float>(-22, 46, 30))
        let keyInt = Float(world.keyLightNode?.light?.intensity ?? 760) / 760.0
        let keyColor = extractNSColorLinear(world.keyLightNode?.light?.color) * keyInt * (isRoom ? 0.85 : 1.35)

        let fillPos = world.fillLightNode?.simdWorldPosition ?? SIMD3<Float>(30, 26, 26)
        let fillInt = Float(world.fillLightNode?.light?.intensity ?? 175) / 175.0
        let fillColor = extractNSColorLinear(world.fillLightNode?.light?.color) * fillInt * 0.40

        let roomPos = world.roomLightNode?.simdWorldPosition ?? SIMD3<Float>(-6, 46, 52)
        let roomInt = Float(world.roomLightNode?.light?.intensity ?? 155) / 155.0
        let roomColor = extractNSColorLinear(world.roomLightNode?.light?.color) * roomInt * (isRoom ? 0.32 : 0.12)

        // Desk lamp bulb world coordinates (positioned cleanly inside shade dome).
        let bulbWorld = deskBulbNodeRef?.simdWorldPosition ?? SIMD3<Float>(-26.2, 8.9, -12.0)
        let bulbScale: Float = deskOn ? (mood == .midnight ? 1.25 : 0.85) : 0.0
        let bulbColor = world.deskLampTint * (26.0 * bulbScale * world.deskLampBrightness)

        // Monitor textured screen rectangle.
        let monTransform = monitorScreenNodeRef?.simdWorldTransform ?? matrix_identity_float4x4
        let monCenter = SIMD3<Float>(monTransform.columns.3.x, monTransform.columns.3.y, monTransform.columns.3.z)
        let monRight = simd_normalize(SIMD3<Float>(monTransform.columns.0.x, monTransform.columns.0.y, monTransform.columns.0.z))
        let monUp = simd_normalize(SIMD3<Float>(monTransform.columns.1.x, monTransform.columns.1.y, monTransform.columns.1.z))
        let monPlane = monitorScreenNodeRef?.geometry as? SCNPlane
        let monW = Float(monPlane?.width ?? 47.0)
        let monH = Float(monPlane?.height ?? 26.5)
        let monTint = extractNSColorLinear(world.monitorScreenMaterial?.emission.contents ?? NSColor.white)
        // A screen lights the desk in front of it at a fraction of its own brightness. At the old strength
        // the mat was as bright as the screen at night, which looked like studio fill rather than a monitor.
        let monGain = world.monitorGlowScale * (mood == .midnight ? 0.42 : 0.30)

        // Under-desk violet strip endpoints.
        let underPos = underDeskStripNodeRef?.simdWorldPosition ?? SIMD3<Float>(2.4, -1.5, -19.0)
        let underScale = world.underDeskGlowScale * 1.1

        let fogEnd = Float(world.scene.fogEndDistance)
        let envInt = Float(world.scene.lightingEnvironment.intensity)
        let bgCol = extractNSColorLinear(world.scene.background.contents)

        let uniforms = RTFrameUniforms(
            camPos: SIMD4<Float>(camPos, 1),
            camRight: SIMD4<Float>(camRight, 0),
            camUp: SIMD4<Float>(camUp, 0),
            camForward: SIMD4<Float>(camForward, 0),
            viewToClip: viewToClip,
            worldToView: worldToView,
            prevViewProj: prevViewProj,
            worldToKeyboard: simd_inverse(world.keyboard.simdWorldTransform),
            renderSize: renderSize,
            outputSize: outputSize,
            jitter: jitter,
            prevJitter: prevJitter,
            frameIndex: frameIndex,
            sampleIndex: sampleIndex,
            accumulationBlend: sampleIndex == 0 ? 1.0 : 1.0 / Float(sampleIndex + 1),
            maxBounces: maxBounces,
            tanHalfFov: tanHalfFov,
            aspect: aspect,
            apertureRadius: aperture,
            focusDistance: focusDist,
            exposureScale: exposureScale,
            renderFlags: isProgressive ? 1 : 0,
            isRoomScenario: isRoom ? 1 : 0,
            hdrEnvTexIndex: hdrEnvTextureIndex,
            plateGlowTexIndex: world.plateGlowAllBlack ? -1 : plateGlowTextureIndex,
            monitorTexIndex: monitorTextureIndex,
            hasBgCubemap: lastBgCubemapRef != nil ? 1 : 0,
            bgColor: SIMD4<Float>(bgCol.x, bgCol.y, bgCol.z, envInt),
            // fogColor = sun disc radiance + star strength, fogParams.x = haze extinction per unit (see RTShaders).
            fogColor: SIMD4<Float>(0, 0, 0, 0),
            fogParams: SIMD4<Float>(!isRoom && fogEnd > 1 ? 2.5 / fogEnd : 0, mood == .midnight ? 0.14 : 0.08, 0.11, isProgressive ? 0.004 : 0.002),
            plateBounds: SIMD4<Float>(KeyboardScene.plateGlowPlaneW, KeyboardScene.plateGlowPlaneH,
                                      1.0 / KeyboardScene.plateGlowPlaneW, 1.0 / KeyboardScene.plateGlowPlaneH),
            // Outdoors the key is directional: xyz = unit direction to the sun, w = tan(angular radius).
            keyLightPosRadius: isRoom
                ? SIMD4<Float>(keyLightW.x, keyLightW.y, keyLightW.z, 8.5)
                : SIMD4<Float>(simd_normalize(keyLightW), 1.6 / max(simd_length(keyLightW), 1)),
            keyLightColor: isRoom
                ? SIMD4<Float>(keyColor.x, keyColor.y, keyColor.z, 0.0)
                : SIMD4<Float>(keyColor.x * 1.45, keyColor.y * 1.45, keyColor.z * 1.45, 1.0),
            fillLightPosRadius: SIMD4<Float>(fillPos.x, fillPos.y, fillPos.z, 11.0),
            fillLightColor: SIMD4<Float>(fillColor.x, fillColor.y, fillColor.z, fillInt > 0.01 ? 1.0 : 0.0),
            deskBulbPosRadius: SIMD4<Float>(bulbWorld.x, bulbWorld.y, bulbWorld.z, 0.65),
            deskBulbColor: SIMD4<Float>(bulbColor.x, bulbColor.y, bulbColor.z, deskOn ? 1.0 : 0.0),
            monitorPos: SIMD4<Float>(monCenter.x, monCenter.y, monCenter.z, monGain),
            monitorU: SIMD4<Float>(monRight.x, monRight.y, monRight.z, monW * 0.5),
            monitorV: SIMD4<Float>(monUp.x, monUp.y, monUp.z, monH * 0.5),
            monitorColor: SIMD4<Float>(monTint.x, monTint.y, monTint.z, mood == .midnight ? 1.0 : 0.28),
            underDeskPosA: SIMD4<Float>(underPos.x - 18.0, underPos.y, underPos.z, 0.45),
            underDeskPosB: SIMD4<Float>(underPos.x + 18.0, underPos.y, underPos.z, underScale),
            underDeskColor: SIMD4<Float>(0.42, 0.14, 0.95, isProgressive ? 1.0 : 0.0),
            roomLightPosRadius: SIMD4<Float>(roomPos.x, roomPos.y, roomPos.z, isRoom ? 14.0 : 10.0),
            roomLightColor: SIMD4<Float>(roomColor.x, roomColor.y, roomColor.z, roomInt > 0.01 ? 1.0 : 0.0),
            windowOrigin: .zero,
            windowU: SIMD4<Float>(0, 0, 1, 0),
            windowV: SIMD4<Float>(0, 1, 0, 0),
            groundProjection: world.photoGround
        )
        return (uniforms, curViewProj)
    }

    // MARK: - Low-level SCNGeometry / Property Readers

    func extractColorAndTexture(_ contents: Any?, isSRGB: Bool) -> (SIMD3<Float>, Int32) {
        guard let contents else { return (.zero, -1) }
        if let ns = contents as? NSColor {
            let lin = srgbNSColorToLinear(ns)
            return (lin, -1)
        }
        let tex = registerTexture(contents, isSRGB: isSRGB)
        if tex >= 0 {
            return (SIMD3<Float>(1, 1, 1), tex)
        }
        if let num = contents as? NSNumber {
            let v = num.floatValue
            let lin = isSRGB ? srgbToLinear(v) : v
            return (SIMD3<Float>(lin, lin, lin), -1)
        }
        return (.zero, -1)
    }

    func extractScalarAndTexture(_ contents: Any?, defaultVal: Float) -> (Float, Int32) {
        guard let contents else { return (defaultVal, -1) }
        if let num = contents as? NSNumber {
            return (num.floatValue, -1)
        }
        if let ns = contents as? NSColor, let c = ns.usingColorSpace(.sRGB) {
            return (Float(c.redComponent), -1)
        }
        let tex = registerTexture(contents, isSRGB: false)
        if tex >= 0 {
            return (1.0, tex)
        }
        return (defaultVal, -1)
    }

    func scalarValue(_ contents: Any?, defaultVal: Float) -> Float {
        if let n = contents as? NSNumber { return n.floatValue }
        return defaultVal
    }

    func extractNSColorLinear(_ contents: Any?) -> SIMD3<Float> {
        guard let contents else { return SIMD3<Float>(0.5, 0.5, 0.5) }
        if let ns = contents as? NSColor {
            return srgbNSColorToLinear(ns)
        }
        let cf = contents as CFTypeRef
        if CFGetTypeID(cf) == CGColor.typeID, let ns = NSColor(cgColor: contents as! CGColor) {
            return srgbNSColorToLinear(ns)
        }
        return SIMD3<Float>(0.85, 0.88, 0.94)
    }

    func srgbNSColorToLinear(_ ns: NSColor) -> SIMD3<Float> {
        let c = ns.usingColorSpace(.sRGB) ?? NSColor.white
        return SIMD3<Float>(
            srgbToLinear(Float(c.redComponent)),
            srgbToLinear(Float(c.greenComponent)),
            srgbToLinear(Float(c.blueComponent))
        )
    }

    private func srgbToLinear(_ x: Float) -> Float {
        let c = max(0, x)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    func uvTransformVec(_ m: SCNMatrix4) -> SIMD4<Float> {
        SIMD4<Float>(Float(m.m11), Float(m.m22), Float(m.m41), Float(m.m42))
    }

    func readFloat3Source(_ source: SCNGeometrySource) -> [SIMD3<Float>] {
        let count = source.vectorCount
        var out = [SIMD3<Float>](repeating: .zero, count: count)
        let stride = source.dataStride
        let offset = source.dataOffset
        let comps = source.componentsPerVector
        let bytesPerComp = source.bytesPerComponent
        source.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<count {
                let ptr = base.advanced(by: i * stride + offset)
                if bytesPerComp == 4 {
                    let f = ptr.assumingMemoryBound(to: Float.self)
                    out[i] = SIMD3<Float>(comps > 0 ? f[0] : 0, comps > 1 ? f[1] : 0, comps > 2 ? f[2] : 0)
                } else if bytesPerComp == 2 {
                    let h = ptr.assumingMemoryBound(to: UInt16.self)
                    out[i] = SIMD3<Float>(
                        comps > 0 ? Float(Float16(bitPattern: h[0])) : 0,
                        comps > 1 ? Float(Float16(bitPattern: h[1])) : 0,
                        comps > 2 ? Float(Float16(bitPattern: h[2])) : 0
                    )
                }
            }
        }
        return out
    }

    func readFloat4Source(_ source: SCNGeometrySource) -> [SIMD4<Float>] {
        let count = source.vectorCount
        var out = [SIMD4<Float>](repeating: SIMD4<Float>(1, 1, 1, 1), count: count)
        let stride = source.dataStride
        let offset = source.dataOffset
        let comps = source.componentsPerVector
        let bytesPerComp = source.bytesPerComponent
        source.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<count {
                let ptr = base.advanced(by: i * stride + offset)
                if bytesPerComp == 4 {
                    let f = ptr.assumingMemoryBound(to: Float.self)
                    out[i] = SIMD4<Float>(
                        comps > 0 ? f[0] : 1,
                        comps > 1 ? f[1] : 1,
                        comps > 2 ? f[2] : 1,
                        comps > 3 ? f[3] : 1
                    )
                } else if bytesPerComp == 2 {
                    let h = ptr.assumingMemoryBound(to: UInt16.self)
                    out[i] = SIMD4<Float>(
                        comps > 0 ? Float(Float16(bitPattern: h[0])) : 1,
                        comps > 1 ? Float(Float16(bitPattern: h[1])) : 1,
                        comps > 2 ? Float(Float16(bitPattern: h[2])) : 1,
                        comps > 3 ? Float(Float16(bitPattern: h[3])) : 1
                    )
                } else if bytesPerComp == 1 {
                    let b = ptr.assumingMemoryBound(to: UInt8.self)
                    out[i] = SIMD4<Float>(
                        comps > 0 ? Float(b[0]) / 255.0 : 1,
                        comps > 1 ? Float(b[1]) / 255.0 : 1,
                        comps > 2 ? Float(b[2]) / 255.0 : 1,
                        comps > 3 ? Float(b[3]) / 255.0 : 1
                    )
                }
            }
        }
        return out
    }

    func readFloat2Source(_ source: SCNGeometrySource) -> [SIMD2<Float>] {
        let count = source.vectorCount
        var out = [SIMD2<Float>](repeating: .zero, count: count)
        let stride = source.dataStride
        let offset = source.dataOffset
        let comps = source.componentsPerVector
        let bytesPerComp = source.bytesPerComponent
        source.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<count {
                let ptr = base.advanced(by: i * stride + offset)
                if bytesPerComp == 4 {
                    let f = ptr.assumingMemoryBound(to: Float.self)
                    out[i] = SIMD2<Float>(comps > 0 ? f[0] : 0, comps > 1 ? f[1] : 0)
                } else if bytesPerComp == 2 {
                    let h = ptr.assumingMemoryBound(to: UInt16.self)
                    out[i] = SIMD2<Float>(
                        comps > 0 ? Float(Float16(bitPattern: h[0])) : 0,
                        comps > 1 ? Float(Float16(bitPattern: h[1])) : 0
                    )
                }
            }
        }
        return out
    }

    func readTriangleIndices(_ elem: SCNGeometryElement) -> [UInt32] {
        let primCount = elem.primitiveCount
        guard primCount > 0 else { return [] }
        let bpi = elem.bytesPerIndex
        var rawIndices = [UInt32]()

        elem.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let count = elem.data.count / max(1, bpi)
            rawIndices.reserveCapacity(count)
            switch bpi {
            case 2:
                let p = base.assumingMemoryBound(to: UInt16.self)
                for i in 0..<count { rawIndices.append(UInt32(p[i])) }
            case 4:
                let p = base.assumingMemoryBound(to: UInt32.self)
                for i in 0..<count { rawIndices.append(p[i]) }
            case 1:
                let p = base.assumingMemoryBound(to: UInt8.self)
                for i in 0..<count { rawIndices.append(UInt32(p[i])) }
            default:
                break
            }
        }

        switch elem.primitiveType {
        case .triangles:
            let need = primCount * 3
            if rawIndices.count >= need {
                return Array(rawIndices.prefix(need))
            }
            return rawIndices
        case .triangleStrip:
            guard rawIndices.count >= primCount + 2 else { return [] }
            var out = [UInt32]()
            out.reserveCapacity(primCount * 3)
            for t in 0..<primCount {
                let a = rawIndices[t], b = rawIndices[t + 1], c = rawIndices[t + 2]
                if (t & 1) == 0 {
                    out.append(contentsOf: [a, b, c])
                } else {
                    out.append(contentsOf: [b, a, c])
                }
            }
            return out
        default:
            return []
        }
    }

    func makeBuffer<T>(from array: [T]) -> MTLBuffer {
        let len = max(16, array.count * MemoryLayout<T>.stride)
        let buf = device.makeBuffer(length: len, options: .storageModeShared)!
        if !array.isEmpty {
            _ = array.withUnsafeBytes { memcpy(buf.contents(), $0.baseAddress!, array.count * MemoryLayout<T>.stride) }
        }
        return buf
    }

    func makeDefaultMaterial() -> RTMaterialData {
        RTMaterialData(
            baseColor: SIMD4<Float>(0.5, 0.5, 0.5, 1),
            emissionColor: SIMD4<Float>(0, 0, 0, 0.45),
            params: SIMD4<Float>(0, 0, 0.06, 0.4),
            optics: SIMD4<Float>(1.49, 0, 0, 0),
            absorbColor: .zero,
            diffuseUV: SIMD4<Float>(1, 1, 0, 0),
            detailUV: SIMD4<Float>(1, 1, 0, 0),
            roughnessUV: SIMD4<Float>(1, 1, 0, 0),
            texIndices: SIMD4<Int32>(-1, -1, -1, -1),
            extraTex: SIMD4<Int32>(-1, -1, 0, 0)
        )
    }

    func packedFloat4x3(from m: simd_float4x4) -> MTLPackedFloat4x3 {
        MTLPackedFloat4x3(columns: (
            MTLPackedFloat3Make(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            MTLPackedFloat3Make(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            MTLPackedFloat3Make(m.columns.2.x, m.columns.2.y, m.columns.2.z),
            MTLPackedFloat3Make(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        ))
    }

    func upperLeft3x3(_ m: simd_float4x4) -> simd_float3x3 {
        simd_float3x3(
            SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        )
    }

    func computeNormalMatrix4(_ m: simd_float4x4) -> simd_float4x4 {
        let m3 = upperLeft3x3(m)
        let det = simd_determinant(m3)
        let n3 = abs(det) > 1e-8 ? simd_transpose(simd_inverse(m3)) : matrix_identity_float3x3
        return simd_float4x4(
            SIMD4<Float>(n3.columns.0, 0),
            SIMD4<Float>(n3.columns.1, 0),
            SIMD4<Float>(n3.columns.2, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    func isDescendant(_ node: SCNNode, of ancestor: SCNNode) -> Bool {
        var cur: SCNNode? = node
        while let n = cur {
            if n === ancestor { return true }
            cur = n.parent
        }
        return false
    }
}
