import SceneKit
import AppKit
import simd

extension PlantProps {

    // MARK: - Tall Glass Bottle with Lucky Bamboo

    static func buildTallBottlePlant(at pos: SIMD3<Float>, into root: SCNNode) {
        let group = SCNNode()
        group.simdPosition = pos
        root.addChildNode(group)

        DeskRoomAndMat.addContactShadow(
            at: SIMD3(pos.x, 0.005, pos.z),
            radiusX: 2.1,
            radiusZ: 2.1,
            opacity: 0.58,
            into: root
        )

        // Outer glass bottle shell + thick base puck + smooth curved-shoulder optical water volume
        let bottleOuterProfile: [(r: Float, y: Float)] = [
            (0.01, 0.0), (1.95, 0.0), (2.15, 0.35), (2.15, 6.6),
            (1.98, 7.25), (1.52, 7.85), (1.06, 8.45), (0.82, 8.95), (0.82, 10.9),
            (0.95, 11.15), (0.84, 11.24), (0.68, 11.14)
        ]
        let bottleBaseProfile: [(r: Float, y: Float)] = [
            (0.01, 0.02), (1.94, 0.02), (2.10, 0.32), (1.96, 0.48), (0.01, 0.48)
        ]
        let bottleWaterProfile: [(r: Float, y: Float)] = [
            (0.01, 0.49), (1.92, 0.50), (1.97, 1.40), (1.97, 5.20),
            (1.96, 6.20), (1.91, 6.60), (1.84, 6.82), (1.76, 6.96)
        ]
        addGlassVesselAndWater(
            outerProfile: bottleOuterProfile,
            basePuckProfile: bottleBaseProfile,
            waterProfile: bottleWaterProfile,
            waterTopRadius: 1.76,
            waterTopY: 6.96,
            segments: 48,
            causticPos: pos,
            causticRadius: 2.6,
            into: group,
            causticRoot: root
        )

        // Subtle ROPP screw-thread ridges around bottle neck
        var bottleThreadPts = [SIMD3<Float>]()
        let bottleTurns: Float = 2.2
        let bottleThreadSteps = 44
        for i in 0...bottleThreadSteps {
            let t = Float(i) / Float(bottleThreadSteps)
            let a = t * bottleTurns * 2 * .pi
            let r: Float = 0.835 + 0.018 * sin(min(1, t * 8) * .pi * 0.5) * sin(min(1, (1 - t) * 8) * .pi * 0.5)
            let y: Float = 10.35 + t * 0.60
            bottleThreadPts.append(SIMD3(r * cos(a), y, r * sin(a)))
        }
        let bThreadGeo = MeshBuilder.tube(points: bottleThreadPts, radius: 0.022, segments: 5)
        bThreadGeo.materials = [glassThreadMat]
        let bThreadNode = SCNNode(geometry: bThreadGeo)
        bThreadNode.renderingOrder = 4
        bThreadNode.castsShadow = false
        group.addChildNode(bThreadNode)

        // Lush suspended fibrous root mass in lower third of clear bottle (up to y ~ 2.6)
        for rIdx in 0..<28 {
            var state = UInt64(rIdx * 6133 + 4219)
            func nextF() -> Float {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Float((state >> 33) & 0xFFFF) / 65535.0
            }
            let baseA = nextF() * 2 * .pi
            let spinDir: Float = nextF() > 0.48 ? 1.0 : -1.0
            let twist = spinDir * (1.8 + nextF() * 3.1)
            let startY: Float = 0.68 + nextF() * (rIdx < 10 ? 1.85 : 0.72)
            let peakY: Float = 0.82 + nextF() * (rIdx < 10 ? 1.45 : 0.78)
            let spread: Float = 0.62 + nextF() * 1.15
            var rPts = [SIMD3<Float>]()
            for s in 0...11 {
                let t = Float(s) / 11.0
                let a = baseA + t * twist + 0.35 * sin(t * 7.5 + Float(rIdx))
                let rr = 0.08 + spread * pow(t, 0.72) * (0.85 + 0.22 * sin(t * 6.0))
                let arch = sin(t * .pi) * (peakY - 0.56)
                let y = max(0.50, startY * (1.0 - t) + (0.52 + nextF() * 0.22) * t + arch * 0.48)
                rPts.append(SIMD3(-0.24 + min(1.80, rr) * cos(a), min(2.65, y), 0.04 + min(1.80, rr) * sin(a)))
            }
            let smoothPts = MeshBuilder.catmullRom(rPts, samplesPerSegment: 3)
            let radii = linearRadii(count: smoothPts.count, from: 0.025, to: 0.008)
            let rGeo = MeshBuilder.tube(points: smoothPts, radius: 0.025, radii: radii, segments: 5)
            rGeo.materials = [rIdx % 3 == 0 ? copperRootMat : rootMat]
            let rNode = SCNNode(geometry: rGeo)
            rNode.renderingOrder = 2
            rNode.castsShadow = false
            group.addChildNode(rNode)

            if rIdx % 2 == 0 {
                let anchor = smoothPts[max(2, smoothPts.count / 2)]
                let tip = anchor + SIMD3((nextF() - 0.5) * 0.75, -0.25 - nextF() * 0.40, (nextF() - 0.5) * 0.75)
                let subPts = MeshBuilder.catmullRom([
                    anchor,
                    SIMD3(max(-1.75, min(1.75, tip.x)), max(0.50, tip.y), max(-1.75, min(1.75, tip.z)))
                ], samplesPerSegment: 3)
                let subGeo = MeshBuilder.tube(
                    points: subPts,
                    radius: 0.012,
                    radii: linearRadii(count: subPts.count, from: 0.012, to: 0.006),
                    segments: 4
                )
                subGeo.materials = [rIdx % 4 == 0 ? copperRootMat : rootMat]
                let subNode = SCNNode(geometry: subGeo)
                subNode.renderingOrder = 2
                subNode.castsShadow = false
                group.addChildNode(subNode)
            }
        }

        // Main curved segmented lucky bamboo cane emerging through the narrow bottle neck (IMG_1862/1863)
        let caneCtrl: [SIMD3<Float>] = [
            SIMD3(-0.36, 0.48, 0.06),
            SIMD3(-0.22, 4.80, 0.04),
            SIMD3(0.06, 11.10, 0.02),
            SIMD3(0.10, 13.80, 0.00),
            SIMD3(0.04, 16.40, -0.02),
        ]
        let bambooNodes: [Float] = [0.13, 0.27, 0.42, 0.56, 0.70, 0.83, 0.94]
        let canePts = MeshBuilder.catmullRom(caneCtrl, samplesPerSegment: 10)
        let caneRadii = caneRadii(count: canePts.count, from: 0.17, to: 0.10, nodeFractions: bambooNodes, swell: 0.11)
        let caneGeo = MeshBuilder.uvTube(
            points: canePts,
            radius: 0.17,
            radii: caneRadii,
            segments: 14,
            uvLengthScale: 1.0 / arcLength(of: canePts)
        )
        caneGeo.materials = [bambooCaneMat]
        let caneNode = SCNNode(geometry: caneGeo)
        caneNode.castsShadow = true
        group.addChildNode(caneNode)

        // Secondary slender green bamboo stalk tucked beside main cane inside neck (IMG_1862/1863)
        let stalk2Pts = MeshBuilder.catmullRom([
            SIMD3(0.18, 0.52, -0.08),
            SIMD3(0.12, 4.90, -0.05),
            SIMD3(-0.08, 10.90, -0.02),
            SIMD3(-0.34, 12.90, 0.06),
            SIMD3(-0.56, 14.35, 0.12),
        ], samplesPerSegment: 8)
        let stalk2Geo = MeshBuilder.uvTube(
            points: stalk2Pts,
            radius: 0.105,
            radii: Self.caneRadii(count: stalk2Pts.count, from: 0.105, to: 0.052, nodeFractions: [0.18, 0.40, 0.62, 0.84], swell: 0.09),
            segments: 10,
            uvLengthScale: 1.0 / arcLength(of: stalk2Pts)
        )
        stalk2Geo.materials = [bambooCaneMat]
        let stalk2Node = SCNNode(geometry: stalk2Geo)
        stalk2Node.castsShadow = true
        group.addChildNode(stalk2Node)

        // Lower right leafy offshoot branching just above the bottle rim (y ~ 11.4 -> 13.8)
        let rightShootPts = MeshBuilder.catmullRom([
            SIMD3(0.08, 11.40, 0.03),
            SIMD3(0.34, 12.40, 0.16),
            SIMD3(0.64, 13.40, 0.28),
        ], samplesPerSegment: 5)
        let rsGeo = MeshBuilder.tube(
            points: rightShootPts,
            radius: 0.070,
            radii: linearRadii(count: rightShootPts.count, from: 0.070, to: 0.034),
            segments: 7
        )
        rsGeo.materials = [paleStemMat]
        let rsNode = SCNNode(geometry: rsGeo)
        rsNode.castsShadow = true
        group.addChildNode(rsNode)

        // Left sheathing petiole branch splitting from main cane at bottle mouth (y = 10.8 -> 14.2)
        let leftBranchPts = MeshBuilder.catmullRom([
            SIMD3(0.02, 10.75, 0.02),
            SIMD3(-0.20, 12.00, 0.05),
            SIMD3(-0.46, 13.15, 0.06),
            SIMD3(-0.66, 14.15, 0.07),
        ], samplesPerSegment: 6)
        let lbGeo = MeshBuilder.tube(points: leftBranchPts, radius: 0.075, radii: linearRadii(count: leftBranchPts.count, from: 0.075, to: 0.045), segments: 8)
        lbGeo.materials = [paleStemMat]
        let lbNode = SCNNode(geometry: lbGeo)
        lbNode.castsShadow = true
        group.addChildNode(lbNode)

        // 12 sculpted narrow Dracaena ribbon blades matching graceful multi-tiered sweeps in IMG_1862/1864
        let leafSpecs: [(ctrl: [SIMD3<Float>], width: Float, roll: Float)] = [
            // 1. Lower-left blade emerging from left petiole branch
            ([SIMD3(-0.62, 13.05, 0.06), SIMD3(-1.20, 14.35, 0.14), SIMD3(-2.65, 15.25, 0.28), SIMD3(-3.95, 15.10, 0.40), SIMD3(-4.65, 14.25, 0.52)], 0.62, 0.16),
            // 2. Lower-left secondary shoot blade reaching forward/left just above bottle lip
            ([SIMD3(-0.48, 12.60, 0.10), SIMD3(-1.24, 13.35, 0.52), SIMD3(-2.15, 13.25, 0.94), SIMD3(-2.85, 12.30, 1.32)], 0.56, -0.10),
            // 3. Lower-right shoot blade #1 fanning right from neck shoot
            ([SIMD3(0.60, 12.65, 0.26), SIMD3(1.38, 13.55, 0.52), SIMD3(2.30, 13.55, 0.76), SIMD3(3.05, 12.65, 0.96)], 0.58, 0.12),
            // 4. Lower-right shoot blade #2 rising gently near main stem
            ([SIMD3(0.50, 12.30, 0.20), SIMD3(1.00, 13.65, 0.12), SIMD3(1.66, 14.75, 0.02), SIMD3(2.28, 15.20, -0.06)], 0.50, -0.16),
            // 5. Mid-right drooping blade
            ([SIMD3(0.08, 14.40, 0.02), SIMD3(0.98, 14.95, 0.18), SIMD3(2.05, 14.20, 0.40), SIMD3(2.70, 12.90, 0.56), SIMD3(2.96, 11.95, 0.66)], 0.64, -0.18),
            // 6. Dominant tall upper-right blade sweeping high up-right
            ([SIMD3(0.05, 16.00, -0.02), SIMD3(0.52, 17.95, -0.06), SIMD3(1.72, 20.10, -0.12), SIMD3(3.02, 21.55, -0.14), SIMD3(4.08, 22.15, -0.16)], 0.68, 0.24),
            // 7. Upper-left high arching blade
            ([SIMD3(-0.04, 16.05, -0.02), SIMD3(-0.80, 18.35, -0.08), SIMD3(-2.40, 20.15, -0.12), SIMD3(-4.08, 20.60, -0.04), SIMD3(-5.20, 20.10, 0.10)], 0.66, -0.16),
            // 8. Secondary upper-left arching blade
            ([SIMD3(-0.10, 15.65, 0.03), SIMD3(-1.05, 17.70, 0.14), SIMD3(-2.62, 18.85, 0.22), SIMD3(-4.00, 18.95, 0.24), SIMD3(-4.88, 18.30, 0.28)], 0.62, 0.12),
            // 9. Slender front-drooping ribbon blade curving toward viewer (+Z)
            ([SIMD3(0.02, 15.60, 0.05), SIMD3(-0.14, 16.40, 0.98), SIMD3(-0.28, 15.70, 2.02), SIMD3(-0.36, 14.10, 2.75), SIMD3(-0.38, 12.65, 3.05)], 0.68, 0.06),
            // 10. Right-horizontal sweeping blade
            ([SIMD3(0.08, 15.85, 0.00), SIMD3(1.25, 17.25, 0.08), SIMD3(2.72, 17.75, 0.10), SIMD3(4.05, 17.60, 0.08), SIMD3(4.95, 17.00, 0.04)], 0.62, -0.14),
            // 11. Back-left slender canopy blade adding radial silhouette depth
            ([SIMD3(-0.02, 16.10, -0.04), SIMD3(-0.60, 18.10, -0.60), SIMD3(-1.58, 19.50, -1.32), SIMD3(-2.55, 19.75, -1.92)], 0.56, 0.20),
            // 12. Secondary lower stalk crown spray
            ([SIMD3(-0.54, 13.60, 0.12), SIMD3(-1.42, 14.35, -0.18), SIMD3(-2.40, 14.35, -0.48), SIMD3(-3.18, 13.70, -0.68)], 0.52, -0.12),
        ]

        for spec in leafSpecs {
            let spine = MeshBuilder.catmullRom(spec.ctrl, samplesPerSegment: 7)
            let leafGeo = MeshBuilder.curvedLeaf(
                spine: spine,
                width: spec.width,
                sheathLengthFraction: 0.10,
                baseWidthFraction: 0.16,
                midribFold: 0.16,
                edgeCurl: 0.07,
                waveAmp: 0.022,
                roll: spec.roll,
                cols: 10
            )
            leafGeo.materials = [bambooLeafMat]
            let lNode = SCNNode(geometry: leafGeo)
            lNode.castsShadow = true
            group.addChildNode(lNode)
        }

        // Slender rolled apical shoot at the crown concealing the cane apex
        let apicalSpine = MeshBuilder.catmullRom([
            SIMD3(0.04, 15.45, 0.00),
            SIMD3(0.10, 16.30, -0.02),
            SIMD3(0.24, 17.40, -0.05),
        ], samplesPerSegment: 5)
        let apicalLeafGeo = MeshBuilder.curvedLeaf(
            spine: apicalSpine,
            width: 0.38,
            sheathLengthFraction: 0.18,
            baseWidthFraction: 0.24,
            midribFold: 0.42,
            edgeCurl: 0.03,
            waveAmp: 0.01,
            lateralHint: SIMD3(0.9, 0, 0.4),
            cols: 8
        )
        apicalLeafGeo.materials = [bambooLeafMat]
        let apicalNode = SCNNode(geometry: apicalLeafGeo)
        apicalNode.castsShadow = true
        group.addChildNode(apicalNode)

        let shootCoreGeo = MeshBuilder.tube(
            points: apicalSpine,
            radius: 0.05,
            radii: linearRadii(count: apicalSpine.count, from: 0.05, to: 0.014),
            segments: 6
        )
        shootCoreGeo.materials = [paleStemMat]
        group.addChildNode(SCNNode(geometry: shootCoreGeo))
    }

    // MARK: - Rounded-Square Wide-Mouth Mason Jar with Dieffenbachia

    static func buildMasonJarPlant(at pos: SIMD3<Float>, into root: SCNNode) {
        let group = SCNNode()
        group.simdPosition = pos
        root.addChildNode(group)

        DeskRoomAndMat.addContactShadow(
            at: SIMD3(pos.x, 0.005, pos.z),
            radiusX: 2.6,
            radiusZ: 2.6,
            opacity: 0.60,
            into: root
        )

        // Continuous superellipse chunky greenish-tint ribbed pickle/mason jar (IMG_1862/1863/1867)
        let jarExponent: Float = 3.25
        let jarSegments = 56
        let jarOuterProfile: [(r: Float, y: Float, squareness: Float)] = [
            (0.01, 0.00, 0.0),
            (2.22, 0.00, 0.15),
            (2.44, 0.28, 0.65),
            (2.48, 0.72, 1.00),
            (2.38, 1.10, 1.00), // Molded lower horizontal grip rib
            (2.48, 1.50, 1.00),
            (2.38, 1.92, 1.00),
            (2.48, 2.34, 1.00),
            (2.38, 2.76, 1.00),
            (2.48, 3.20, 1.00),
            (2.46, 4.18, 0.96),
            (2.26, 4.70, 0.58),
            (2.08, 5.18, 0.12),
            (2.08, 5.95, 0.0),
            (1.94, 6.02, 0.0),
            (1.88, 5.92, 0.0),
        ]
        let jarBaseProfile: [(r: Float, y: Float, squareness: Float)] = [
            (0.01, 0.02, 0.0),
            (2.20, 0.02, 0.15),
            (2.40, 0.28, 0.65),
            (2.30, 0.44, 0.90),
            (0.01, 0.44, 0.0),
        ]
        let jarWaterProfile: [(r: Float, y: Float, squareness: Float)] = [
            (0.01, 0.45, 0.0),
            (2.18, 0.45, 0.88),
            (2.28, 0.78, 1.00),
            (2.28, 4.08, 0.98),
            (2.14, 4.55, 0.65),
            (2.00, 4.92, 0.35),
        ]

        addGlassVesselAndWater(
            outerGeometry: roundedVesselGeometry(profile: jarOuterProfile, exponent: jarExponent, segments: jarSegments),
            baseGeometry: roundedVesselGeometry(profile: jarBaseProfile, exponent: jarExponent, segments: jarSegments),
            waterGeometry: roundedVesselGeometry(profile: jarWaterProfile, exponent: jarExponent, segments: jarSegments),
            waterTopProfileRadius: 2.00,
            waterTopSquareness: 0.35,
            squareExponent: jarExponent,
            waterTopY: 4.92,
            segments: jarSegments,
            greenTinted: true,
            causticPos: pos,
            causticRadius: 3.3,
            into: group,
            causticRoot: root
        )

        // Helical raised glass screw-thread ridges wrapping around the wide jar neck
        var threadPts = [SIMD3<Float>]()
        let turns: Float = 2.15
        let steps = 56
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let a = t * turns * 2 * .pi
            let r: Float = 2.11 + 0.045 * sin(min(1, t * 8) * .pi * 0.5) * sin(min(1, (1 - t) * 8) * .pi * 0.5)
            let y: Float = 5.38 + t * 0.52
            threadPts.append(SIMD3(r * cos(a), y, r * sin(a)))
        }
        let threadGeo = MeshBuilder.tube(points: threadPts, radius: 0.046, segments: 6)
        threadGeo.materials = [greenFrontGlassMat]
        let threadNode = SCNNode(geometry: threadGeo)
        threadNode.renderingOrder = 4
        threadNode.castsShadow = false
        group.addChildNode(threadNode)

        // Chunky diagonal submerged dieffenbachia cane leaning bottom-right -> upper-left through jar rim
        let caneCtrl: [SIMD3<Float>] = [
            SIMD3(1.18, 0.52, 0.14),
            SIMD3(0.74, 2.05, 0.11),
            SIMD3(0.18, 3.80, 0.08),
            SIMD3(-0.56, 6.20, 0.05),
        ]
        let dieffNodes: [Float] = [0.12, 0.28, 0.44, 0.60, 0.76, 0.90]
        let canePts = MeshBuilder.catmullRom(caneCtrl, samplesPerSegment: 10)
        let caneRadii = caneRadii(count: canePts.count, from: 0.34, to: 0.24, nodeFractions: dieffNodes, swell: 0.09)
        let caneGeo = MeshBuilder.uvTube(
            points: canePts,
            radius: 0.26,
            radii: caneRadii,
            segments: 14,
            uvLengthScale: 1.0 / arcLength(of: canePts)
        )
        caneGeo.materials = [dieffCaneMat]
        let caneNode = SCNNode(geometry: caneGeo)
        caneNode.renderingOrder = 2
        caneNode.castsShadow = false
        group.addChildNode(caneNode)

        // Lush aquatic root tangle sprouting from submerged cane nodes through jar water
        for rIdx in 0..<26 {
            var state = UInt64(rIdx * 11003 + 9187)
            func nextF() -> Float {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Float((state >> 33) & 0xFFFF) / 65535.0
            }
            let nodeFrac = 0.06 + nextF() * 0.58
            let anchorIdx = min(canePts.count - 1, max(0, Int(nodeFrac * Float(canePts.count - 1))))
            let anchor = canePts[anchorIdx]
            let angle = nextF() * 2 * .pi
            let reach = 0.72 + nextF() * 1.32
            let target = SIMD3<Float>(
                max(-1.82, min(1.82, anchor.x + reach * cos(angle) - 0.30)),
                0.50 + nextF() * (rIdx < 8 ? 1.05 : 0.38),
                max(-1.82, min(1.82, anchor.z + reach * sin(angle)))
            )
            let mid1 = SIMD3<Float>(
                max(-1.82, min(1.82, anchor.x + (target.x - anchor.x) * 0.38 + (nextF() - 0.5) * 0.45)),
                max(0.55, anchor.y * 0.62 + target.y * 0.38),
                max(-1.82, min(1.82, anchor.z + (target.z - anchor.z) * 0.38 + (nextF() - 0.5) * 0.45))
            )
            let mid2 = SIMD3<Float>(
                max(-1.82, min(1.82, anchor.x + (target.x - anchor.x) * 0.75 + (nextF() - 0.5) * 0.52)),
                max(0.51, target.y + 0.20 * nextF()),
                max(-1.82, min(1.82, anchor.z + (target.z - anchor.z) * 0.75 + (nextF() - 0.5) * 0.52))
            )
            let rPts = MeshBuilder.catmullRom([anchor, mid1, mid2, target], samplesPerSegment: 4)
            let rRadii = linearRadii(count: rPts.count, from: 0.024, to: 0.008)
            let rGeo = MeshBuilder.tube(points: rPts, radius: 0.024, radii: rRadii, segments: 5)
            rGeo.materials = [rIdx % 3 == 0 ? copperRootMat : rootMat]
            let rNode = SCNNode(geometry: rGeo)
            rNode.renderingOrder = 2
            rNode.castsShadow = false
            group.addChildNode(rNode)

            if rIdx % 2 == 0 {
                let brAnchor = rPts[rPts.count / 2]
                let brEnd = SIMD3<Float>(
                    max(-1.82, min(1.82, brAnchor.x + (nextF() - 0.5) * 0.85)),
                    0.50 + nextF() * 0.28,
                    max(-1.82, min(1.82, brAnchor.z + (nextF() - 0.5) * 0.85))
                )
                let brPts = MeshBuilder.catmullRom([brAnchor, brEnd], samplesPerSegment: 3)
                let brGeo = MeshBuilder.tube(points: brPts, radius: 0.013, radii: linearRadii(count: brPts.count, from: 0.013, to: 0.006), segments: 5)
                brGeo.materials = [rootMat]
                let brNode = SCNNode(geometry: brGeo)
                brNode.renderingOrder = 2
                brNode.castsShadow = false
                group.addChildNode(brNode)
            }
        }

        // Emerged curved petiole rising continuously from cane apex into broad spotted blade midrib
        let petioleCtrl: [SIMD3<Float>] = [
            SIMD3(-0.56, 6.08, 0.05),
            SIMD3(-0.84, 7.10, 0.12),
            SIMD3(-1.12, 8.20, 0.22),
            SIMD3(-1.42, 9.45, 0.37),
            SIMD3(-1.74, 10.65, 0.56),
            SIMD3(-2.06, 11.75, 0.72),
            SIMD3(-2.34, 12.60, 0.81),
            SIMD3(-2.58, 13.25, 0.85),
        ]
        let petiolePts = MeshBuilder.catmullRom(petioleCtrl, samplesPerSegment: 8)
        let petioleRadii = linearRadii(count: petiolePts.count, from: 0.165, to: 0.020)
        let petioleGeo = MeshBuilder.tube(points: petiolePts, radius: 0.165, radii: petioleRadii, segments: 10)
        petioleGeo.materials = [paleStemMat]
        let petioleNode = SCNNode(geometry: petioleGeo)
        petioleNode.castsShadow = true
        group.addChildNode(petioleNode)

        // Tightly rolled upright new spear shoot protruding vertically out the apex (IMG_1862/1863)
        let spearCtrl: [SIMD3<Float>] = [
            SIMD3(-0.56, 6.10, 0.05),
            SIMD3(-0.50, 7.75, 0.02),
            SIMD3(-0.42, 9.60, -0.02),
            SIMD3(-0.34, 11.35, -0.05),
        ]
        let spearPts = MeshBuilder.catmullRom(spearCtrl, samplesPerSegment: 7)
        let spearGeo = MeshBuilder.curvedLeaf(
            spine: spearPts,
            width: 0.42,
            sheathLengthFraction: 0.20,
            baseWidthFraction: 0.32,
            midribFold: 0.48,
            edgeCurl: 0.05,
            waveAmp: 0.008,
            lateralHint: SIMD3(0.85, 0, 0.52),
            cols: 8
        )
        spearGeo.materials = [dieffLeafMat]
        let spearNode = SCNNode(geometry: spearGeo)
        spearNode.castsShadow = true
        group.addChildNode(spearNode)

        let spearStemGeo = MeshBuilder.tube(
            points: spearPts,
            radius: 0.085,
            radii: linearRadii(count: spearPts.count, from: 0.085, to: 0.016),
            segments: 7
        )
        spearStemGeo.materials = [paleStemMat]
        let spearStemNode = SCNNode(geometry: spearStemGeo)
        spearStemNode.castsShadow = true
        group.addChildNode(spearStemNode)

        // Broad arching white-speckled cutting leaf angling forward-left so its upper blade reads clearly (IMG_1862/1864)
        let leafSpine = MeshBuilder.catmullRom([
            SIMD3(-1.26, 8.85, 0.26),
            SIMD3(-1.60, 10.10, 0.48),
            SIMD3(-1.98, 11.35, 0.68),
            SIMD3(-2.32, 12.45, 0.80),
            SIMD3(-2.62, 13.35, 0.86),
        ], samplesPerSegment: 8)
        let leafGeo = MeshBuilder.curvedLeaf(
            spine: leafSpine,
            width: 2.55,
            sheathLengthFraction: 0.10,
            baseWidthFraction: 0.22,
            midribFold: 0.14,
            edgeCurl: 0.05,
            waveAmp: 0.022,
            lateralHint: SIMD3(0.62, 0, 0.78),
            cols: 12
        )
        leafGeo.materials = [dieffLeafMat]
        let leafNode = SCNNode(geometry: leafGeo)
        leafNode.castsShadow = true
        group.addChildNode(leafNode)

        // Smaller secondary unfurling blade sprouting low beside jar lip
        let youngSpine = MeshBuilder.catmullRom([
            SIMD3(-0.78, 7.05, 0.14),
            SIMD3(-1.22, 8.05, 0.38),
            SIMD3(-1.68, 9.05, 0.58),
            SIMD3(-2.05, 9.85, 0.72),
        ], samplesPerSegment: 6)
        let youngLeafGeo = MeshBuilder.curvedLeaf(
            spine: youngSpine,
            width: 1.24,
            sheathLengthFraction: 0.12,
            baseWidthFraction: 0.20,
            midribFold: 0.22,
            edgeCurl: 0.04,
            waveAmp: 0.018,
            lateralHint: SIMD3(0.94, 0, 0.34),
            cols: 10
        )
        youngLeafGeo.materials = [dieffLeafMat]
        let youngLeafNode = SCNNode(geometry: youngLeafGeo)
        youngLeafNode.castsShadow = true
        group.addChildNode(youngLeafNode)
    }
}
