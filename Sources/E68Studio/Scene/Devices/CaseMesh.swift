import SceneKit
import AppKit
import simd

/// Procedural CNC aluminum two-piece wedge chassis, stepped top bezel, circular knob pocket,
/// rear hardware bay (USB-C, tri-mode/OS sliders, 2.4G dongle), rubber feet and bottom screws
/// for the Furycube E-68 PRO.
enum CaseMesh {
    // MARK: - Dimensions (1u = 19.05 mm, keyboard local frame centered at layout center)

    static let xMin: Float = -Float(Layout.width) / 2 - 0.56   // -8.685 (left bezel 0.56u)
    static let xMax: Float =  Float(Layout.width) / 2 + 0.54   // +8.665 (right bezel 0.54u)
    static let zMin: Float = -2.5625 - 0.49                    // -3.0525 (top bezel 0.49u)
    static let zMax: Float =  2.5625 + 0.50                    // +3.0625 (front chin 0.50u)

    static let cornerRadius: Float = 0.34
    static let outerLipY: Float = 1.055
    static let innerDeckY: Float = 1.008
    static let seamY: Float = 0.32

    // Rear recessed hardware bay bounds (in keyboard local space; right side when viewed from behind)
    static let rearBayXMin: Float = 1.98 - Float(Layout.width) / 2
    static let rearBayXMax: Float = 5.96 - Float(Layout.width) / 2
    static let rearBayYMin: Float = 0.215
    static let rearBayYMax: Float = 0.485
    static let rearBayCenterY: Float = (rearBayYMin + rearBayYMax) * 0.5
    static let rearBayDepth: Float = 0.085
    static let usbcPortLocalX: Float = 5.50 - Float(Layout.width) / 2

    // World-space tilt compensation so the lower tray rests level on rubber feet atop the desk mat.
    static let tiltRad: Float = 6.0 * .pi / 180.0
    static let kbPosYOffset: Float = 0.34       // above DeskRoomAndMat.matTopY
    static let footHeight: Float = 0.065        // ~1.25 mm silicone feet above matTopY

    /// Local Y of the flat bottom aluminum surface at a given local Z so world Y stays level.
    static func bottomY(atZ z: Float) -> Float {
        let dyWorld = footHeight - kbPosYOffset
        return (dyWorld + z * sin(tiltRad)) / cos(tiltRad)
    }

    // Center of knob cutout in keyboard local coords (aligned with Delete/PgUp/PgDn column 15.25..16.25)
    static let knobCenterX: Float = 15.75 - Float(Layout.width) / 2
    static let knobCenterZ: Float = 0.46 - 2.5625
    static let knobPocketRadius: Float = 0.462
    static let knobPocketFloorY: Float = 0.76

    // MARK: - Perimeter Helpers

    /// CCW rounded-rect points in `(x, z)` when viewed from `+Y`:
    /// front (`+Z`) moves `+X`, right (`+X`) moves `-Z`, back (`-Z`) moves `-X`, left (`-X`) moves `+Z`.
    private static func roundedRectRing(
        x0: Float, x1: Float, z0: Float, z1: Float, radius: Float, cornerSegs: Int = 8
    ) -> [SIMD2<Float>] {
        let r = min(radius, (x1 - x0) * 0.48, (z1 - z0) * 0.48)
        // Corner centers in CCW order starting bottom-right (+X, +Z) -> top-right (+X, -Z) -> top-left (-X, -Z) -> bottom-left (-X, +Z)
        // Angle in (x, z) plane: +Z is a = pi/2, +X is a = 0, -Z is a = -pi/2 (or 3pi/2), -X is a = pi.
        let corners: [(cx: Float, cz: Float, startA: Float, endA: Float)] = [
            (x1 - r, z1 - r, Float.pi * 0.5, 0),                 // front-right (+Z -> +X)
            (x1 - r, z0 + r, 0, -Float.pi * 0.5),                // back-right (+X -> -Z)
            (x0 + r, z0 + r, -Float.pi * 0.5, -Float.pi),        // back-left (-Z -> -X)
            (x0 + r, z1 - r, Float.pi, Float.pi * 0.5),          // front-left (-X -> +Z)
        ]
        var pts = [SIMD2<Float>]()
        pts.reserveCapacity(4 * (cornerSegs + 1))
        for c in corners {
            for i in 0...cornerSegs {
                let t = Float(i) / Float(cornerSegs)
                let a = c.startA + (c.endA - c.startA) * t
                pts.append(SIMD2(c.cx + r * cos(a), c.cz + r * sin(a)))
            }
        }
        return pts
    }

    private struct RingSpec {
        let inset: Float
        let yOffset: Float?      // nil => compute from bottomY(z) + bottomBias
        let bottomBias: Float
        let sharpBefore: Bool    // break normal smoothing before this ring
    }

    /// Lofts a perimeter of `RingSpec`s with clean outward CCW winding.
    /// When `openAcrossRearBay` is true, the `-Z` segment between `rearBayXMax` and `rearBayXMin` is left open
    /// so the recessed rear hardware bay can sit cleanly inside without outer-wall occlusion.
    private static func buildPerimeterLoft(
        rings: [RingSpec],
        bottomCap: Bool = false,
        openAcrossRearBay: Bool = false
    ) -> SCNGeometry {
        var ringPts = [[SIMD3<Float>]]()
        var ringCumLen = [[Float]]()
        for spec in rings {
            let x0 = xMin + spec.inset
            let x1 = xMax - spec.inset
            let z0 = zMin + spec.inset
            let z1 = zMax - spec.inset
            let pts2 = roundedRectRing(
                x0: x0,
                x1: x1,
                z0: z0,
                z1: z1,
                radius: max(0.05, cornerRadius - spec.inset),
                cornerSegs: 8
            )
            let ordered2D: [SIMD2<Float>]
            if openAcrossRearBay {
                // Start at rearBayXMin on the back (-Z) edge, walk CCW around -X, +Z, +X, and end at rearBayXMax.
                ordered2D = [SIMD2(rearBayXMin, z0)] + Array(pts2[18..<36]) + Array(pts2[0..<18]) + [SIMD2(rearBayXMax, z0)]
            } else {
                ordered2D = pts2
            }
            var cum = [Float](repeating: 0, count: ordered2D.count)
            for k in 1..<ordered2D.count {
                cum[k] = cum[k - 1] + simd_length(ordered2D[k] - ordered2D[k - 1])
            }
            ringCumLen.append(cum)
            ringPts.append(ordered2D.map { p in
                let y = spec.yOffset ?? (bottomY(atZ: p.y) + spec.bottomBias)
                return SIMD3(p.x, y, p.y)
            })
        }

        let count = ringPts.first?.count ?? 0
        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [Int32]()

        let cx = (xMin + xMax) * 0.5
        let cz = (zMin + zMax) * 0.5

        func bandNormals(_ lo: [SIMD3<Float>], _ hi: [SIMD3<Float>]) -> ([SIMD3<Float>], [SIMD3<Float>]) {
            var loN = [SIMD3<Float>]()
            var hiN = [SIMD3<Float>]()
            loN.reserveCapacity(count)
            hiN.reserveCapacity(count)
            for k in 0..<count {
                let kn = openAcrossRearBay ? min(k + 1, count - 1) : (k + 1) % count
                let kp = openAcrossRearBay ? max(k - 1, 0) : (k + count - 1) % count
                let upVecRaw = hi[k] - lo[k]
                let upVec = simd_length(upVecRaw) > 1e-6 ? simd_normalize(upVecRaw) : SIMD3<Float>(0, 1, 0)

                let tLoRaw = lo[kn] - lo[kp]
                let tLo = simd_length(tLoRaw) > 1e-6 ? simd_normalize(tLoRaw) : SIMD3<Float>(1, 0, 0)
                var nLo = simd_cross(tLo, upVec)
                nLo = simd_length(nLo) > 1e-5 ? simd_normalize(nLo) : SIMD3(0, 1, 0)
                loN.append(nLo)

                let tHiRaw = hi[kn] - hi[kp]
                let tHi = simd_length(tHiRaw) > 1e-6 ? simd_normalize(tHiRaw) : tLo
                var nHi = simd_cross(tHi, upVec)
                nHi = simd_length(nHi) > 1e-5 ? simd_normalize(nHi) : SIMD3(0, 1, 0)
                hiN.append(nHi)
            }
            return (loN, hiN)
        }

        let bands = max(0, rings.count - 1)
        var allLoN = [[SIMD3<Float>]]()
        var allHiN = [[SIMD3<Float>]]()
        for r in 0..<bands {
            let (ln, hn) = bandNormals(ringPts[r], ringPts[r + 1])
            allLoN.append(ln)
            allHiN.append(hn)
        }

        func appendRingVertices(_ pts: [SIMD3<Float>], cumLen: [Float], normals ringNormals: [SIMD3<Float>]) -> Int32 {
            let base = Int32(positions.count)
            for k in 0..<count {
                positions.append(pts[k])
                normals.append(ringNormals[k])
                // Arc-length + combined (z + y) V prevents vertical normal-map stretching on vertical walls.
                uvs.append(SIMD2(cumLen[k] / 12.0, ((pts[k].z - zMin) + pts[k].y) / 4.0))
            }
            return base
        }

        func blendedNormal(between upper: [SIMD3<Float>], and lower: [SIMD3<Float>]) -> [SIMD3<Float>] {
            (0..<count).map { k in
                let sum = upper[k] + lower[k]
                return simd_length(sum) > 1e-5 ? simd_normalize(sum) : upper[k]
            }
        }

        var prevUpperBase: Int32?
        for r in 0..<bands {
            let loBase: Int32
            if r > 0, !rings[r].sharpBefore, let shared = prevUpperBase {
                loBase = shared
            } else {
                let loNormals = (r > 0 && !rings[r].sharpBefore)
                    ? blendedNormal(between: allHiN[r - 1], and: allLoN[r])
                    : allLoN[r]
                loBase = appendRingVertices(ringPts[r], cumLen: ringCumLen[r], normals: loNormals)
            }

            let smoothUpper = (r + 1 < bands) && !rings[r + 1].sharpBefore
            let hiNormals = smoothUpper
                ? blendedNormal(between: allHiN[r], and: allLoN[r + 1])
                : allHiN[r]
            let hiBase = appendRingVertices(ringPts[r + 1], cumLen: ringCumLen[r + 1], normals: hiNormals)
            prevUpperBase = smoothUpper ? hiBase : nil

            let segCount = openAcrossRearBay ? (count - 1) : count
            for k in 0..<segCount {
                let kn = (k + 1) % count
                let a = loBase + Int32(k), b = loBase + Int32(kn)
                let c = hiBase + Int32(kn), d = hiBase + Int32(k)
                indices += [a, b, c, a, c, d]
            }
        }

        if bottomCap, let bot = ringPts.first {
            let centerIdx = Int32(positions.count)
            let botCenter = SIMD3<Float>(cx, bottomY(atZ: cz), cz)
            // Downward normal rotated into local space (perpendicular to wedge floor)
            let floorN = simd_normalize(SIMD3<Float>(0, -cos(tiltRad), -sin(tiltRad)))
            positions.append(botCenter)
            normals.append(floorN)
            uvs.append(SIMD2(0.5, 0.5))
            let start = Int32(positions.count)
            for p in bot {
                positions.append(p)
                normals.append(floorN)
                uvs.append(SIMD2((p.x - xMin) / (xMax - xMin), (p.z - zMin) / (zMax - zMin)))
            }
            // Facing downward (-Y): reverse triangle winding from top cap
            for k in 0..<count {
                let kn = (k + 1) % count
                indices += [centerIdx, start + Int32(kn), start + Int32(k)]
            }
        }

        let vSrc = SCNGeometrySource(
            data: positions.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .vertex,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let nSrc = SCNGeometrySource(
            data: normals.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .normal,
            vectorCount: normals.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let tSrc = SCNGeometrySource(
            data: uvs.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .texcoord,
            vectorCount: uvs.count,
            usesFloatComponents: true,
            componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD2<Float>>.stride
        )
        return SCNGeometry(sources: [vSrc, nSrc, tSrc], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    // MARK: - Complete Case Assembly

    static func build(
        into parent: SCNNode,
        caseMaterial: SCNMaterial,
        plateY: Float
    ) {
        let cx = Float(Layout.width) / 2
        let cz: Float = 2.5625
        let caseRoot = SCNNode()
        parent.addChildNode(caseRoot)

        // 1. Lower CNC Tray (angled bottom wedge + recessed bottom perimeter seam + bottom chamfer up to bay sill)
        let lowerGeo = buildPerimeterLoft(rings: [
            RingSpec(inset: 0.135, yOffset: nil, bottomBias: 0.008, sharpBefore: true),
            RingSpec(inset: 0.120, yOffset: nil, bottomBias: 0.018, sharpBefore: true),
            RingSpec(inset: 0.105, yOffset: nil, bottomBias: 0.000, sharpBefore: true),
            RingSpec(inset: 0.048, yOffset: nil, bottomBias: 0.000, sharpBefore: true),
            RingSpec(inset: 0.014, yOffset: nil, bottomBias: 0.036, sharpBefore: true),
            RingSpec(inset: 0.014, yOffset: rearBayYMin, bottomBias: 0, sharpBefore: true),
        ], bottomCap: true)
        lowerGeo.materials = [caseMaterial]
        let lowerNode = SCNNode(geometry: lowerGeo)
        lowerNode.castsShadow = true
        caseRoot.addChildNode(lowerNode)

        // 2a. Mid-height waist band with parting groove (open across the rear hardware bay span)
        let waistGeo = buildPerimeterLoft(rings: [
            RingSpec(inset: 0.014, yOffset: rearBayYMin, bottomBias: 0, sharpBefore: true),
            RingSpec(inset: 0.014, yOffset: seamY - 0.018, bottomBias: 0, sharpBefore: false),
            RingSpec(inset: 0.042, yOffset: seamY - 0.004, bottomBias: 0, sharpBefore: true),
            RingSpec(inset: 0.042, yOffset: seamY + 0.008, bottomBias: 0, sharpBefore: true),
            RingSpec(inset: 0.000, yOffset: seamY + 0.022, bottomBias: 0, sharpBefore: true),
            RingSpec(inset: 0.002, yOffset: rearBayYMax, bottomBias: 0, sharpBefore: false),
        ], bottomCap: false, openAcrossRearBay: true)
        waistGeo.materials = [caseMaterial]
        let waistNode = SCNNode(geometry: waistGeo)
        waistNode.castsShadow = true
        caseRoot.addChildNode(waistNode)

        // 2b. Upper CNC Cover Outer Shell (above bay ceiling -> top fillet -> outer flat rim -> inner chamfer step-down)
        let innerStepInset: Float = 0.125
        let innerDeckInset: Float = 0.160
        let upperShellGeo = buildPerimeterLoft(rings: [
            RingSpec(inset: 0.002, yOffset: rearBayYMax, bottomBias: 0, sharpBefore: true),
            RingSpec(inset: 0.005, yOffset: outerLipY - 0.030, bottomBias: 0, sharpBefore: false),
            RingSpec(inset: 0.026, yOffset: outerLipY - 0.006, bottomBias: 0, sharpBefore: false),
            RingSpec(inset: 0.048, yOffset: outerLipY, bottomBias: 0, sharpBefore: false),
            RingSpec(inset: innerStepInset, yOffset: outerLipY, bottomBias: 0, sharpBefore: true),
            RingSpec(inset: innerDeckInset, yOffset: innerDeckY, bottomBias: 0, sharpBefore: true),
        ], bottomCap: false)
        upperShellGeo.materials = [caseMaterial]
        let upperShellNode = SCNNode(geometry: upperShellGeo)
        upperShellNode.castsShadow = true
        caseRoot.addChildNode(upperShellNode)

        // Subtle stepped side-wall rail on front half of left & right flanks (matches IMG_1848 & bottom profile)
        let sideRailLen = CGFloat(zMax - 0.20 - (-0.25))
        let sideRailZ = (-0.25 + (zMax - 0.20)) * 0.5
        let sideRailGeo = MeshBuilder.roundedSlab(width: 0.024, height: 0.22, depth: Float(sideRailLen), cornerRadius: 0.010, bevel: 0.006)
        sideRailGeo.materials = [caseMaterial]
        for sideSign: Float in [-1, 1] {
            let rail = SCNNode(geometry: sideRailGeo)
            let sideX = (sideSign < 0 ? xMin : xMax) - sideSign * 0.004
            rail.position = SCNVector3(sideX, 0.05, sideRailZ)
            rail.castsShadow = true
            caseRoot.addChildNode(rail)
        }

        // 3. Stepped Inner Deck + Well + Circular Knob Pocket.
        // Outer rect extends underneath the raised outer rim (inset 0.07) so SCNShape's outer chamfer
        // stays concealed inside the outer shell, avoiding any seam trench on the top bezel.
        func localPt(_ layoutX: Double, _ layoutY: Double) -> CGPoint {
            CGPoint(x: layoutX - Double(cx), y: -(layoutY - Double(cz)))
        }

        let deckHiddenInset: Float = 0.07
        let deckRect = CGRect(
            x: CGFloat(xMin + deckHiddenInset),
            y: CGFloat(-(zMax - deckHiddenInset)),
            width: CGFloat((xMax - xMin) - deckHiddenInset * 2),
            height: CGFloat((zMax - zMin) - deckHiddenInset * 2)
        )
        let deckPath = NSBezierPath(roundedRect: deckRect, xRadius: CGFloat(cornerRadius - deckHiddenInset), yRadius: CGFloat(cornerRadius - deckHiddenInset))

        // Keywell openings: three separate cutouts (main 60% block, Delete/PgUp/PgDn column, and T-arrow cluster)
        // preserving the CNC case dividers between the knob, nav column, main block, and arrows.
        func appendRoundedHole(_ pts: [CGPoint], radius: CGFloat) {
            let path = NSBezierPath()
            let n = pts.count
            path.move(to: CGPoint(x: (pts[n - 1].x + pts[0].x) * 0.5, y: (pts[n - 1].y + pts[0].y) * 0.5))
            for i in 0..<n {
                path.appendArc(from: pts[i], to: pts[(i + 1) % n], radius: radius)
            }
            path.close()
            deckPath.append(path)
        }

        let m = 0.020
        let holeRadius: CGFloat = 0.032

        // 1. Main 60% keywell (Esc..Backspace down to Ctrl row)
        appendRoundedHole([
            localPt(-m, -m),
            localPt(15.0 + m, -m),
            localPt(15.0 + m, 3.0 + m),
            localPt(14.0 + m, 3.0 + m),
            localPt(14.0 + m, 4.0 + m),
            localPt(13.0 + m, 4.0 + m),
            localPt(13.0 + m, 5.0 + m),
            localPt(-m, 5.0 + m),
        ], radius: holeRadius)

        // 2. Right navigation column (Delete, PgUp, PgDn) below the rotary knob
        appendRoundedHole([
            localPt(15.25 - m, 1.0 - m),
            localPt(16.25 + m, 1.0 - m),
            localPt(16.25 + m, 4.0 + m),
            localPt(15.25 - m, 4.0 + m),
        ], radius: holeRadius)

        // 3. Inverted-T arrow cluster (Up, Left, Down, Right)
        appendRoundedHole([
            localPt(14.125 - m, 3.125 - m),
            localPt(15.125 + m, 3.125 - m),
            localPt(15.125 + m, 4.125 - m),
            localPt(16.125 + m, 4.125 - m),
            localPt(16.125 + m, 5.125 + m),
            localPt(13.125 - m, 5.125 + m),
            localPt(13.125 - m, 4.125 - m),
            localPt(14.125 - m, 4.125 - m),
        ], radius: holeRadius)

        // Circular recessed pocket for the rotary knob at top-right corner
        let knobRect = CGRect(
            x: CGFloat(knobCenterX - knobPocketRadius),
            y: CGFloat(-knobCenterZ - knobPocketRadius),
            width: CGFloat(knobPocketRadius * 2),
            height: CGFloat(knobPocketRadius * 2)
        )
        deckPath.append(NSBezierPath(ovalIn: knobRect))
        deckPath.windingRule = .evenOdd
        deckPath.flatness = 0.0020

        let deckDepth: CGFloat = CGFloat(innerDeckY - (plateY - 0.03))
        let deckGeo = SCNShape(path: deckPath, extrusionDepth: deckDepth)
        deckGeo.chamferRadius = 0.015
        deckGeo.chamferMode = .front
        deckGeo.materials = [caseMaterial]
        let deckNode = SCNNode(geometry: deckGeo)
        deckNode.eulerAngles.x = -.pi / 2
        deckNode.position = SCNVector3(0, CGFloat(plateY - 0.03) + deckDepth * 0.5, 0)
        deckNode.castsShadow = true
        caseRoot.addChildNode(deckNode)

        // Subtle satin white circular floor inside the knob pocket
        let floorMat = SCNMaterial()
        floorMat.lightingModel = .physicallyBased
        floorMat.diffuse.contents = NSColor(srgbRed: 0.78, green: 0.78, blue: 0.78, alpha: 1)
        floorMat.metalness.contents = 0.05
        floorMat.roughness.contents = 0.45
        let pocketFloor = SCNCylinder(radius: CGFloat(knobPocketRadius + 0.04), height: 0.04)
        pocketFloor.radialSegmentCount = 48
        pocketFloor.materials = [floorMat]
        let pocketFloorNode = SCNNode(geometry: pocketFloor)
        pocketFloorNode.position = SCNVector3(knobCenterX, knobPocketFloorY - 0.02, knobCenterZ)
        pocketFloorNode.castsShadow = false
        caseRoot.addChildNode(pocketFloorNode)

        // 4. Light-Grey Silicone Rubber Feet (with recessed rings) & 6 Recessed Bottom Screws
        let footRingMat = SCNMaterial()
        footRingMat.lightingModel = .physicallyBased
        footRingMat.diffuse.contents = NSColor(srgbRed: 0.68, green: 0.685, blue: 0.69, alpha: 1)
        footRingMat.roughness.contents = 0.55

        let rubberMat = SCNMaterial()
        rubberMat.lightingModel = .physicallyBased
        rubberMat.diffuse.contents = NSColor(srgbRed: 0.80, green: 0.80, blue: 0.79, alpha: 1)
        rubberMat.roughness.contents = 0.80

        let footRingGeo = SCNCylinder(radius: 0.325, height: 0.008)
        footRingGeo.radialSegmentCount = 32
        footRingGeo.materials = [footRingMat]

        let footGeo = SCNCylinder(radius: 0.285, height: CGFloat(footHeight + 0.015))
        footGeo.radialSegmentCount = 32
        footGeo.materials = [rubberMat]

        let footOffsets: [(Float, Float)] = [
            (xMin + 0.76, zMin + 0.68), (xMax - 0.76, zMin + 0.68),
            (xMin + 0.76, zMax - 0.68), (xMax - 0.76, zMax - 0.68),
        ]
        for (fx, fz) in footOffsets {
            let yb = bottomY(atZ: fz) + 0.008
            let ring = SCNNode(geometry: footRingGeo)
            ring.position = SCNVector3(fx, yb - 0.003, fz)
            ring.eulerAngles.x = CGFloat(-tiltRad)
            ring.castsShadow = false
            caseRoot.addChildNode(ring)

            let fn = SCNNode(geometry: footGeo)
            fn.position = SCNVector3(fx, yb - footHeight * 0.5 - 0.002, fz)
            fn.eulerAngles.x = CGFloat(-tiltRad)
            fn.castsShadow = false
            caseRoot.addChildNode(fn)
        }

        let boreMat = SCNMaterial()
        boreMat.lightingModel = .physicallyBased
        boreMat.diffuse.contents = NSColor(srgbRed: 0.42, green: 0.43, blue: 0.45, alpha: 1)
        boreMat.roughness.contents = 0.52

        let screwMat = SCNMaterial()
        screwMat.lightingModel = .physicallyBased
        screwMat.diffuse.contents = NSColor(srgbRed: 0.68, green: 0.69, blue: 0.71, alpha: 1)
        screwMat.metalness.contents = 0.88
        screwMat.roughness.contents = 0.25

        let socketMat = SCNMaterial()
        socketMat.lightingModel = .physicallyBased
        socketMat.diffuse.contents = NSColor(srgbRed: 0.14, green: 0.15, blue: 0.16, alpha: 1)
        socketMat.metalness.contents = 0.40
        socketMat.roughness.contents = 0.60

        let boreGeo = SCNCylinder(radius: 0.095, height: 0.008)
        boreGeo.radialSegmentCount = 20
        boreGeo.materials = [boreMat]

        let screwGeo = SCNCylinder(radius: 0.068, height: 0.010)
        screwGeo.radialSegmentCount = 16
        screwGeo.materials = [screwMat]

        let socketGeo = SCNCylinder(radius: 0.028, height: 0.012)
        socketGeo.radialSegmentCount = 6
        socketGeo.materials = [socketMat]

        let screwCoords: [(Float, Float)] = [
            (xMin + 0.36, zMin + 0.34), (0, zMin + 0.28), (xMax - 0.36, zMin + 0.34),
            (xMin + 0.36, zMax - 0.34), (0, zMax - 0.28), (xMax - 0.36, zMax - 0.34),
        ]
        for (sx, sz) in screwCoords {
            let yb = bottomY(atZ: sz) + 0.008
            let bn = SCNNode(geometry: boreGeo)
            bn.position = SCNVector3(sx, yb - 0.003, sz)
            bn.eulerAngles.x = CGFloat(-tiltRad)
            bn.castsShadow = false
            caseRoot.addChildNode(bn)

            let sn = SCNNode(geometry: screwGeo)
            sn.position = SCNVector3(sx, yb - 0.004, sz)
            sn.eulerAngles.x = CGFloat(-tiltRad)
            sn.castsShadow = false
            caseRoot.addChildNode(sn)

            let hn = SCNNode(geometry: socketGeo)
            hn.position = SCNVector3(sx, yb - 0.005, sz)
            hn.eulerAngles.x = CGFloat(-tiltRad)
            hn.castsShadow = false
            caseRoot.addChildNode(hn)
        }

        // 5. Rear Hardware Cluster (USB-C port, 2.4G/USB/BT slider, Mac/Win slider, 2.4G dongle cap)
        buildRearPorts(into: caseRoot, cx: cx, caseMaterial: caseMaterial)
    }

    private static func buildRearPorts(into parent: SCNNode, cx: Float, caseMaterial: SCNMaterial) {
        let lowerWallZ = zMin + 0.014
        let bayCenterX = (rearBayXMin + rearBayXMax) * 0.5
        let bayWidth = rearBayXMax - rearBayXMin
        let bayHeight = rearBayYMax - rearBayYMin
        let floorZ = zMin + rearBayDepth

        // Shadowed recessed pocket floor & slot track materials
        let recessMat = SCNMaterial()
        recessMat.lightingModel = .physicallyBased
        recessMat.diffuse.contents = NSColor(srgbRed: 0.77, green: 0.77, blue: 0.765, alpha: 1)
        recessMat.metalness.contents = 0.04
        recessMat.roughness.contents = 0.46

        let slotTrackMat = SCNMaterial()
        slotTrackMat.lightingModel = .physicallyBased
        slotTrackMat.diffuse.contents = NSColor(srgbRed: 0.36, green: 0.37, blue: 0.38, alpha: 1)
        slotTrackMat.roughness.contents = 0.62

        let cavityMat = SCNMaterial()
        cavityMat.lightingModel = .physicallyBased
        cavityMat.diffuse.contents = NSColor(srgbRed: 0.03, green: 0.032, blue: 0.036, alpha: 1)
        cavityMat.roughness.contents = 0.72

        let sliderMat = SCNMaterial()
        sliderMat.lightingModel = .physicallyBased
        sliderMat.diffuse.contents = NSColor(srgbRed: 0.89, green: 0.89, blue: 0.885, alpha: 1)
        sliderMat.roughness.contents = 0.38

        let gripMat = SCNMaterial()
        gripMat.lightingModel = .physicallyBased
        gripMat.diffuse.contents = NSColor(srgbRed: 0.60, green: 0.61, blue: 0.62, alpha: 1)
        gripMat.roughness.contents = 0.50

        let tongueMat = SCNMaterial()
        tongueMat.lightingModel = .physicallyBased
        tongueMat.diffuse.contents = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1)
        tongueMat.roughness.contents = 0.45

        // Opaque silkscreen material matching caseMaterial white so edges vanish seamlessly in the ray tracer
        let labelMat = SCNMaterial()
        labelMat.lightingModel = .physicallyBased
        labelMat.diffuse.contents = cachedRearSilkscreen
        labelMat.diffuse.minificationFilter = .linear
        labelMat.diffuse.magnificationFilter = .linear
        labelMat.diffuse.mipFilter = .linear
        labelMat.diffuse.maxAnisotropy = 16
        labelMat.metalness.contents = 0.05
        labelMat.roughness.contents = 0.30
        labelMat.clearCoat.contents = 0.24
        labelMat.clearCoatRoughness.contents = 0.22

        // 1. Pill-shaped recessed bay bezel (SCNShape with evenOdd cutout sealing seamlessly into the open waist band)
        let framePath = NSBezierPath(rect: NSRect(
            x: CGFloat(rearBayXMin - 0.01),
            y: CGFloat(rearBayYMin - 0.005),
            width: CGFloat(bayWidth + 0.02),
            height: CGFloat(bayHeight + 0.01)
        ))
        let pillRect = NSRect(
            x: CGFloat(rearBayXMin + 0.04),
            y: CGFloat(rearBayYMin + 0.020),
            width: CGFloat(bayWidth - 0.08),
            height: CGFloat(bayHeight - 0.040)
        )
        framePath.append(NSBezierPath(roundedRect: pillRect, xRadius: 0.085, yRadius: 0.085))
        framePath.windingRule = .evenOdd
        framePath.flatness = 0.002

        let frameGeo = SCNShape(path: framePath, extrusionDepth: CGFloat(rearBayDepth))
        frameGeo.chamferRadius = 0.008
        frameGeo.chamferMode = .back
        frameGeo.materials = [caseMaterial]
        let frameNode = SCNNode(geometry: frameGeo)
        frameNode.position = SCNVector3(0, 0, zMin + 0.002 + rearBayDepth * 0.5)
        frameNode.castsShadow = true
        parent.addChildNode(frameNode)

        // Recessed bay floor backing wall
        let bayFloor = SCNBox(width: CGFloat(bayWidth + 0.02), height: CGFloat(bayHeight + 0.01), length: 0.02, chamferRadius: 0)
        bayFloor.materials = [recessMat]
        let bayFloorNode = SCNNode(geometry: bayFloor)
        bayFloorNode.position = SCNVector3(bayCenterX, rearBayCenterY, floorZ + 0.006)
        bayFloorNode.castsShadow = false
        parent.addChildNode(bayFloorNode)

        // 2. Printed silkscreen labels on the lower rear wall directly below the switches
        let modeSlotX = 4.62 - cx
        let osSlotX = 3.52 - cx
        let labelCenterX = (modeSlotX + osSlotX) * 0.5
        let labelPlane = SCNPlane(width: 2.20, height: 0.095)
        labelPlane.materials = [labelMat]
        let labelNode = SCNNode(geometry: labelPlane)
        labelNode.position = SCNVector3(labelCenterX, 0.135, lowerWallZ - 0.0015)
        labelNode.eulerAngles.y = .pi
        labelNode.castsShadow = false
        parent.addChildNode(labelNode)

        // 3a. USB-C port cavity at layoutU = 5.50 (leftmost inside rear bay)
        let usbcX = usbcPortLocalX
        let usbcRim = SCNBox(width: 0.44, height: 0.145, length: 0.036, chamferRadius: 0.062)
        usbcRim.materials = [cavityMat]
        let usbcNode = SCNNode(geometry: usbcRim)
        usbcNode.position = SCNVector3(usbcX, rearBayCenterY, floorZ - 0.014)
        usbcNode.castsShadow = false
        parent.addChildNode(usbcNode)

        let usbcTongue = SCNBox(width: 0.25, height: 0.022, length: 0.034, chamferRadius: 0.004)
        usbcTongue.materials = [tongueMat]
        let usbcTongueNode = SCNNode(geometry: usbcTongue)
        usbcTongueNode.position = SCNVector3(usbcX, rearBayCenterY, floorZ - 0.020)
        usbcTongueNode.castsShadow = false
        parent.addChildNode(usbcTongueNode)

        // Helper for ridged slide switches inside the recessed bay
        func addSlideSwitch(slotX: Float, slotW: CGFloat, thumbOffsetX: Float) {
            let slotGeo = SCNBox(width: slotW, height: 0.135, length: 0.024, chamferRadius: 0.018)
            slotGeo.materials = [slotTrackMat]
            let slotNode = SCNNode(geometry: slotGeo)
            slotNode.position = SCNVector3(slotX, rearBayCenterY, floorZ - 0.008)
            slotNode.castsShadow = false
            parent.addChildNode(slotNode)

            let thumbGeo = SCNBox(width: 0.165, height: 0.125, length: 0.036, chamferRadius: 0.010)
            thumbGeo.materials = [sliderMat]
            let thumbNode = SCNNode(geometry: thumbGeo)
            thumbNode.position = SCNVector3(slotX + thumbOffsetX, rearBayCenterY, floorZ - 0.024)
            thumbNode.castsShadow = true
            parent.addChildNode(thumbNode)

            let ribGeo = SCNBox(width: 0.014, height: 0.095, length: 0.008, chamferRadius: 0.002)
            ribGeo.materials = [gripMat]
            for rx: Float in [-0.042, 0, 0.042] {
                let rib = SCNNode(geometry: ribGeo)
                rib.position = SCNVector3(slotX + thumbOffsetX + rx, rearBayCenterY, floorZ - 0.042)
                rib.castsShadow = false
                parent.addChildNode(rib)
            }
        }

        // 3b. Tri-mode 2.4G / USB / BT slide switch at layoutU = 4.62 (center position = USB)
        addSlideSwitch(slotX: modeSlotX, slotW: 0.52, thumbOffsetX: 0)

        // 3c. OS Mac / Win slide switch at layoutU = 3.52
        addSlideSwitch(slotX: osSlotX, slotW: 0.40, thumbOffsetX: 0.075)

        // 3d. Flush rectangular white 2.4G USB receiver dongle cap at layoutU = 2.60 (right end of rear bay)
        let dongleX = 2.60 - cx
        let dongleWell = SCNBox(width: 0.70, height: 0.195, length: 0.024, chamferRadius: 0.022)
        dongleWell.materials = [slotTrackMat]
        let dongleWellNode = SCNNode(geometry: dongleWell)
        dongleWellNode.position = SCNVector3(dongleX, rearBayCenterY, floorZ - 0.008)
        dongleWellNode.castsShadow = false
        parent.addChildNode(dongleWellNode)

        let dongleCap = SCNBox(width: 0.64, height: 0.170, length: 0.068, chamferRadius: 0.014)
        dongleCap.materials = [caseMaterial]
        let dongleCapNode = SCNNode(geometry: dongleCap)
        dongleCapNode.position = SCNVector3(dongleX, rearBayCenterY, floorZ - 0.036)
        dongleCapNode.castsShadow = true
        parent.addChildNode(dongleCapNode)
    }

    private static let cachedRearSilkscreen: CGImage = rearSilkscreenTexture()

    private static func rearSilkscreenTexture() -> CGImage {
        let w = 1024, h = 96
        let cgCtx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        cgCtx.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cgCtx, flipped: false)

        // Match caseMaterial white so the decal plane blends invisibly into the lower rear wall
        NSColor(srgbRed: 0.872, green: 0.872, blue: 0.868, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()

        let font = NSFont(name: "AvenirNext-DemiBold", size: 44) ?? .systemFont(ofSize: 44, weight: .semibold)
        let color = NSColor(white: 0.18, alpha: 1.0)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]

        // Center each label group under its switch center (u = 0.25 -> x = 256, u = 0.75 -> x = 768)
        let modeStr = NSAttributedString(string: "2.4G  USB  BT", attributes: attrs)
        modeStr.draw(at: NSPoint(x: 256 - modeStr.size().width * 0.5, y: (CGFloat(h) - modeStr.size().height) * 0.5))

        let osStr = NSAttributedString(string: "Mac   Win", attributes: attrs)
        osStr.draw(at: NSPoint(x: 768 - osStr.size().width * 0.5, y: (CGFloat(h) - osStr.size().height) * 0.5))

        NSGraphicsContext.restoreGraphicsState()
        return cgCtx.makeImage()!
    }
}
