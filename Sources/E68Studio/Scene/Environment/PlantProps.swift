import SceneKit
import SceneKit.ModelIO
import ModelIO
import AppKit
import simd

/// Photorealistic 3D models for all hydroponic desk plants:
/// two lush pothos fishbowls, tall lucky bamboo bottle, and segmented dieffenbachia mason jar.
enum PlantProps {

    // MARK: - Botanical Materials

    private static let leafTranslucencyShader = """
        // backlit foliage
        vec3 N = normalize(_surface.normal);
        vec3 V = normalize(_surface.view);
        float rim = pow(clamp(1.0 - abs(dot(N, V)), 0.0, 1.0), 1.8);
        vec3 bounce = _surface.diffuse.rgb * vec3(0.11, 0.17, 0.03);
        _output.color.rgb += bounce * (0.18 + 0.55 * rim);
    """

    private static func makeLeafMaterial(
        name: String,
        maps: DeskTextures.PlantPBRMaps,
        normalIntensity: CGFloat,
        roughnessFallback: CGFloat,
        clearCoat: CGFloat,
        clearCoatRoughness: CGFloat
    ) -> SCNMaterial {
        let m = SCNMaterial()
        m.name = name
        m.lightingModel = .physicallyBased
        m.diffuse.contents = maps.diffuse
        m.normal.contents = maps.normal
        m.normal.intensity = normalIntensity
        m.roughness.contents = maps.roughness ?? roughnessFallback
        m.clearCoat.contents = clearCoat
        m.clearCoatRoughness.contents = clearCoatRoughness
        m.metalness.contents = 0.0
        m.isDoubleSided = true
        m.shaderModifiers = [.fragment: leafTranslucencyShader]
        return m
    }

    /// Three Golden Pothos blade textures with varied golden-chartreuse marbling.
    static let pothosLeafShades: [SCNMaterial] = {
        DeskTextures.makeProceduralPothosVariants().enumerated().map { idx, maps in
            makeLeafMaterial(
                name: "foliage_pothos_card_\(idx + 1)",
                maps: maps,
                normalIntensity: 0.42,
                roughnessFallback: 0.25,
                clearCoat: 0.34,
                clearCoatRoughness: 0.12
            )
        }
    }()

    /// Five normalized sculpted broad cordate heart variants crossed with three shades.
    private static let pothosLeafPool: [[SCNGeometry]] = {
        let variants: [(width: Float, droop: Float, fold: Float)] = [
            (0.96, 0.16, 0.16), // Upright broad cupped heart
            (1.02, 0.26, 0.15), // Broad mid-mound heart
            (0.98, 0.36, 0.14), // Natural arched cascade heart
            (1.06, 0.42, 0.13), // Lush wide bowl-draping heart
            (0.94, 0.30, 0.18), // Deep-V trailing runner leaf
        ]
        return variants.map { v in
            let base = MeshBuilder.leaf(
                length: 1.0,
                width: v.width,
                heartShaped: true,
                droop: v.droop,
                midribFold: v.fold
            )
            return pothosLeafShades.map { mat in
                let shared = SCNGeometry(sources: base.sources, elements: base.elements)
                shared.materials = [mat]
                return shared
            }
        }
    }()

    static let bambooLeafMat: SCNMaterial = makeLeafMaterial(
        name: "foliage_bamboo",
        maps: DeskTextures.leafPBRTexture(kind: .bamboo),
        normalIntensity: 0.42,
        roughnessFallback: 0.28,
        clearCoat: 0.26,
        clearCoatRoughness: 0.18
    )

    static let dieffLeafMat: SCNMaterial = makeLeafMaterial(
        name: "foliage_dieffenbachia",
        maps: DeskTextures.leafPBRTexture(kind: .dieffenbachia),
        normalIntensity: 0.44,
        roughnessFallback: 0.28,
        clearCoat: 0.28,
        clearCoatRoughness: 0.18
    )

    static let stemMat: SCNMaterial = {
        let m = SCNMaterial()
        m.name = "pothos_stem"
        m.lightingModel = .physicallyBased
        if let tex = DeskTextures.plantStemTexture() {
            m.diffuse.contents = tex
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
        } else {
            m.diffuse.contents = NSColor(srgbRed: 0.22, green: 0.44, blue: 0.13, alpha: 1)
        }
        m.roughness.contents = 0.34
        m.clearCoat.contents = 0.14
        m.clearCoatRoughness.contents = 0.22
        return m
    }()

    private static func makeCaneMat(nodeFractions: [Float], isDieffenbachia: Bool) -> SCNMaterial {
        let tex = DeskTextures.canePBRTexture(isDieffenbachia: isDieffenbachia)
        let m = SCNMaterial()
        m.name = isDieffenbachia ? "dieff_cane" : "bamboo_cane"
        m.lightingModel = .physicallyBased
        m.diffuse.contents = tex.diffuse
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .clamp
        m.normal.contents = tex.normal
        m.normal.wrapS = .repeat
        m.normal.wrapT = .clamp
        m.normal.intensity = 0.46
        m.roughness.contents = tex.roughness ?? 0.32
        if tex.roughness != nil {
            m.roughness.wrapS = .repeat
            m.roughness.wrapT = .clamp
        }
        m.clearCoat.contents = 0.16
        m.clearCoatRoughness.contents = 0.24
        return m
    }

    static let bambooCaneMat = makeCaneMat(
        nodeFractions: [0.14, 0.28, 0.43, 0.58, 0.72, 0.85, 0.94],
        isDieffenbachia: false
    )

    static let dieffCaneMat = makeCaneMat(
        nodeFractions: [0.12, 0.28, 0.44, 0.60, 0.76, 0.90],
        isDieffenbachia: true
    )

    static let paleStemMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.36, green: 0.58, blue: 0.19, alpha: 1)
        m.roughness.contents = 0.34
        return m
    }()

    static let rootMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        if let tex = DeskTextures.plantRootTexture() {
            m.diffuse.contents = tex
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
        } else {
            m.diffuse.contents = NSColor(srgbRed: 0.72, green: 0.66, blue: 0.48, alpha: 1)
        }
        m.roughness.contents = 0.42
        return m
    }()

    static let copperRootMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.60, green: 0.42, blue: 0.25, alpha: 1)
        m.roughness.contents = 0.44
        return m
    }()

    // MARK: - Curve Helpers

    static func linearRadii(count: Int, from r0: Float, to r1: Float) -> [Float] {
        guard count > 1 else { return [r0] }
        return (0..<count).map { i in
            let t = Float(i) / Float(count - 1)
            return r0 + (r1 - r0) * t
        }
    }

    static func caneRadii(
        count: Int,
        from r0: Float,
        to r1: Float,
        nodeFractions: [Float],
        swell: Float = 0.075
    ) -> [Float] {
        guard count > 1 else { return [r0] }
        return (0..<count).map { i in
            let t = Float(i) / Float(count - 1)
            let base = r0 + (r1 - r0) * t
            var bump: Float = 0
            for nf in nodeFractions {
                let d = t - nf
                bump += exp(-(d * d) / 0.00018) * swell
            }
            return base * (1.0 + bump)
        }
    }

    static func arcLength(of points: [SIMD3<Float>]) -> Float {
        var len: Float = 0
        for i in 1..<points.count {
            len += simd_length(points[i] - points[i - 1])
        }
        return max(len, 1e-4)
    }

    // MARK: - Build Entrypoint

    static func build(into root: SCNNode) {
        // Left fishbowl #1 (larger, lush pothos under desk lamp)
        buildFishbowlPlant(
            at: SIMD3(-21.0, 0, -14.8),
            bowlRadius: 3.10,
            bowlHeight: 4.6,
            leafCount: 14,
            seed: 1,
            into: root
        )
        // Left fishbowl #2 (next to monitor)
        buildFishbowlPlant(
            at: SIMD3(-14.0, 0, -15.2),
            bowlRadius: 2.75,
            bowlHeight: 4.2,
            leafCount: 11,
            seed: 2,
            into: root
        )
        // Right tall clear glass bottle with lucky bamboo
        buildTallBottlePlant(at: SIMD3(24.8, 0, -15.5), into: root)
        // Far-right wide-mouth square mason jar with dieffenbachia
        buildMasonJarPlant(at: SIMD3(31.8, 0, -15.0), into: root)
    }

    // MARK: - Fishbowl Golden Pothos

    private static func buildFishbowlPlant(
        at pos: SIMD3<Float>,
        bowlRadius R: Float,
        bowlHeight H: Float,
        leafCount: Int,
        seed: Int,
        into root: SCNNode
    ) {
        let group = SCNNode()
        group.simdPosition = pos
        root.addChildNode(group)

        DeskRoomAndMat.addContactShadow(
            at: SIMD3(pos.x, 0.005, pos.z),
            radiusX: R * 0.92,
            radiusZ: R * 0.92,
            opacity: 0.56,
            into: root
        )

        // Outer glass fishbowl profile + thick base puck + optical water volume & concave meniscus
        let outerSteps = 16
        var outerProfile: [(r: Float, y: Float)] = [
            (0.01, 0.0), (R * 0.62, 0.0), (R * 0.72, 0.28)
        ]
        for i in 0...outerSteps {
            let t = Float(i) / Float(outerSteps)
            let a = -Float.pi * 0.32 + t * (Float.pi * 0.64)
            let rr = R * cos(a)
            let yy = H * 0.44 + R * 0.74 * sin(a)
            outerProfile.append((max(rr, R * 0.65), max(0.28, yy)))
        }
        let rimR = outerProfile.last!.r
        let rimY = outerProfile.last!.y
        outerProfile.append((rimR + 0.14, rimY + 0.15))
        outerProfile.append((rimR + 0.04, rimY + 0.24))
        outerProfile.append((rimR - 0.14, rimY + 0.16))

        let basePuckProfile: [(r: Float, y: Float)] = [
            (0.01, 0.02), (R * 0.60, 0.02), (R * 0.68, 0.26), (R * 0.50, 0.42), (0.01, 0.42)
        ]

        let waterMaxY = H * 0.75
        var waterProfile: [(r: Float, y: Float)] = [(0.01, 0.43), (R * 0.48, 0.43)]
        for pt in outerProfile where pt.y > 0.43 && pt.y <= waterMaxY && pt.r > R * 0.60 {
            waterProfile.append((pt.r - 0.16, pt.y))
        }
        let topWR = waterProfile.last?.r ?? R * 0.82
        waterProfile.append((topWR, waterMaxY))

        addGlassVesselAndWater(
            outerProfile: outerProfile,
            basePuckProfile: basePuckProfile,
            waterProfile: waterProfile,
            waterTopRadius: topWR,
            waterTopY: waterMaxY,
            segments: 48,
            causticPos: pos,
            causticRadius: R * 1.15,
            into: group,
            causticRoot: root
        )

        // Dense network of 26 suspended aquatic root tendrils + fine branching rootlets coiled inside lower water
        for rIdx in 0..<26 {
            var state = UInt64(rIdx * 7919 + seed * 104729 + 31)
            func nextF() -> Float {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Float((state >> 33) & 0xFFFF) / 65535.0
            }
            let baseA = nextF() * 2 * .pi
            let spinDir: Float = nextF() > 0.45 ? 1.0 : -1.0
            let twist = spinDir * (1.5 + nextF() * 3.2)
            let startY = H * (0.44 + nextF() * 0.28)
            let endY = 0.45 + nextF() * 0.58
            let maxR = R * (0.45 + nextF() * 0.36)

            var rPts = [SIMD3<Float>]()
            for s in 0...15 {
                let t = Float(s) / 15.0
                let a = baseA + t * twist + 0.38 * sin(t * 9.5 + Float(rIdx))
                let rr = maxR * (0.12 + 0.88 * pow(t, 0.70)) * (0.86 + 0.22 * sin(t * 7.5 + Float(rIdx)))
                let y = startY - pow(t, 1.10) * (startY - endY) + 0.09 * cos(t * 10.5 + Float(rIdx))
                rPts.append(SIMD3(rr * cos(a), max(0.45, y), rr * sin(a)))
            }
            let thick: Float = 0.020 + nextF() * 0.024
            let smoothRoot = MeshBuilder.catmullRom(rPts, samplesPerSegment: 3)
            let rGeo = MeshBuilder.uvTube(
                points: smoothRoot,
                radius: thick,
                radii: linearRadii(count: smoothRoot.count, from: thick, to: thick * 0.45),
                segments: 6,
                uvLengthScale: 1.0 / max(arcLength(of: smoothRoot), 0.1)
            )
            rGeo.materials = [rIdx % 3 == 0 ? copperRootMat : rootMat]
            let rNode = SCNNode(geometry: rGeo)
            rNode.renderingOrder = 2
            rNode.castsShadow = false
            group.addChildNode(rNode)

            if rIdx % 3 != 2 {
                let anchor = rPts[5 + (rIdx % 4)]
                let brMid = anchor + SIMD3((nextF() - 0.5) * 0.85, -0.28 - nextF() * 0.42, (nextF() - 0.5) * 0.85)
                let brEnd = brMid + SIMD3((nextF() - 0.5) * 0.75, -0.32 - nextF() * 0.45, (nextF() - 0.5) * 0.75)
                let brPts = MeshBuilder.catmullRom([
                    anchor,
                    SIMD3(brMid.x, max(0.45, brMid.y), brMid.z),
                    SIMD3(brEnd.x, max(0.45, brEnd.y), brEnd.z),
                ], samplesPerSegment: 3)
                let brGeo = MeshBuilder.tube(points: brPts, radius: 0.014, segments: 5)
                brGeo.materials = [rootMat]
                let brNode = SCNNode(geometry: brGeo)
                brNode.renderingOrder = 2
                brNode.castsShadow = false
                group.addChildNode(brNode)

                if rIdx % 2 == 0 {
                    let subAnchor = rPts[10]
                    let subEnd = subAnchor + SIMD3((nextF() - 0.5) * 0.65, -0.22 - nextF() * 0.30, (nextF() - 0.5) * 0.65)
                    let subPts = MeshBuilder.catmullRom([subAnchor, SIMD3(subEnd.x, max(0.45, subEnd.y), subEnd.z)], samplesPerSegment: 3)
                    let subGeo = MeshBuilder.tube(points: subPts, radius: 0.010, segments: 5)
                    subGeo.materials = [copperRootMat]
                    let subNode = SCNNode(geometry: subGeo)
                    subNode.renderingOrder = 2
                    subNode.castsShadow = false
                    group.addChildNode(subNode)
                }
            }
        }

        // Submerged green nodal stems coiling through water toward bowl rim
        for sIdx in 0..<8 {
            let a = Float(sIdx) * (2 * .pi / 8.0) + Float(seed) * 0.6
            let rMid = R * (0.44 + 0.16 * sin(Float(sIdx) * 1.9))
            let ctrl = [
                SIMD3<Float>(0.24 * cos(a - 0.4), 0.52, 0.24 * sin(a - 0.4)),
                SIMD3<Float>(rMid * cos(a + 0.4), H * 0.35, rMid * sin(a + 0.4)),
                SIMD3<Float>(rMid * 0.85 * cos(a + 1.0), H * 0.64, rMid * 0.85 * sin(a + 1.0)),
                SIMD3<Float>(0.85 * cos(a + 0.7), rimY + 0.08, 0.85 * sin(a + 0.7)),
            ]
            let sPts = MeshBuilder.catmullRom(ctrl, samplesPerSegment: 6)
            let sRadii = caneRadii(count: sPts.count, from: 0.072, to: 0.068, nodeFractions: [0.24, 0.52, 0.78], swell: 0.12)
            let sGeo = MeshBuilder.uvTube(
                points: sPts,
                radius: 0.072,
                radii: sRadii,
                segments: 8,
                uvLengthScale: 1.0 / max(arcLength(of: sPts), 0.1)
            )
            sGeo.materials = [stemMat]
            let sNode = SCNNode(geometry: sGeo)
            sNode.renderingOrder = 2
            sNode.castsShadow = false
            group.addChildNode(sNode)
        }

        // Hand-built golden pothos stems & broad waxy heart-shaped leaves arching cleanly over the rim
        var rng = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 77
        func rnd() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFF) / 65535.0
        }
        for i in 0..<leafCount {
            let t = (Float(i) + 0.5) / Float(leafCount)
            let az = Float(i) * 2.39996 + (seed == 1 ? 0.55 : 1.10) + (rnd() - 0.5) * 0.34
            let dir = SIMD3<Float>(cos(az), 0, sin(az))
            let isInner = t < 0.28
            let reach = isInner
                ? R * (0.34 + 1.15 * t) + (rnd() - 0.5) * 0.25
                : R * (0.94 + 0.46 * (t - 0.28) / 0.72) + (rnd() - 0.5) * 0.32
            let lift = isInner
                ? 2.85 - 2.10 * t + (rnd() - 0.5) * 0.50
                : 1.55 - 1.75 * ((t - 0.28) / 0.72) + (rnd() - 0.5) * 0.45
            let base = dir * (0.18 + rnd() * 0.38) + SIMD3(0, H * 0.46, 0)
            let lipClear = SIMD3<Float>(dir.x * min(reach * 0.72, R * 0.90), rimY + max(0.55, lift * 0.65 + 0.60), dir.z * min(reach * 0.72, R * 0.90))
            let tip = dir * reach + SIMD3(0, rimY + lift, 0)
            let mid = SIMD3<Float>(dir.x * reach * 0.62, max(lipClear.y, rimY + lift) + 0.42, dir.z * reach * 0.62)
            let stemPts = MeshBuilder.catmullRom([base, lipClear, mid, tip], samplesPerSegment: 6)
            let stemRadii = linearRadii(count: stemPts.count, from: 0.068, to: 0.042)
            let stemGeo = MeshBuilder.tube(points: stemPts, radius: 0.068, radii: stemRadii, segments: 7)
            stemGeo.materials = [stemMat]
            let stemNode = SCNNode(geometry: stemGeo)
            stemNode.castsShadow = true
            group.addChildNode(stemNode)

            let bowlScale: Float = (seed == 1) ? 0.96 : 0.86
            let leafLen = (2.85 + 0.90 * sin(t * .pi * 0.85) + (rnd() - 0.4) * 0.38) * bowlScale
            let variantIdx = (i + seed * 2) % pothosLeafPool.count
            let shadeIdx = t < 0.30 ? 2 : (t > 0.72 ? 0 : (Int(rnd() * 3.0) % 3))
            let yaw = atan2(dir.x, dir.z) + (rnd() - 0.5) * 0.48
            let pitch = isInner ? (-0.24 + 0.52 * t) : (0.20 + 0.46 * ((t - 0.28) / 0.72)) + (rnd() - 0.5) * 0.18
            let bladeFwd = SIMD3<Float>(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
            let leafNode = SCNNode(geometry: pothosLeafPool[variantIdx][shadeIdx])
            // Tuck the leaf sinus cleanly around the petiole tip so stems flow seamlessly into the midrib
            leafNode.simdPosition = tip - bladeFwd * 0.12
            leafNode.simdScale = SIMD3(repeating: leafLen)
            leafNode.eulerAngles = SCNVector3(CGFloat(pitch), CGFloat(yaw), CGFloat((rnd() - 0.5) * 0.44))
            leafNode.castsShadow = true
            group.addChildNode(leafNode)
        }
    }
}
