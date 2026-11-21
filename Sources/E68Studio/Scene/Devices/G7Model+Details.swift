import SceneKit
import AppKit
import simd

extension G7Model {
    // MARK: - Center Island, Wheel, LED, USB-C & Side Buttons

    static func buildCenterIsland(into mouse: SCNNode, material: SCNMaterial) {
        var pts = [SIMD3<Float>](), uvs = [SIMD2<Float>](), idx = [Int32]()

        func addStrip(t0: Float, t1: Float, x0: Float, x1: Float, rows: Int, cols: Int, recess: Float, bevelFront: Bool, bevelRear: Bool) {
            let base = Int32(pts.count)
            for r in 0...rows {
                let v = Float(r) / Float(rows)
                let t = t0 + (t1 - t0) * v
                for c in 0...cols {
                    let u = Float(c) / Float(cols)
                    let x = x0 + (x1 - x0) * u
                    let a = angleForTopX(x, at: t)
                    var p = surface(t, a)
                    let sideBevel = smooth(0.0, 0.16, min(u, 1 - u))
                    let frontBevel = bevelFront ? smooth(0.0, 0.08, v) : 1
                    let rearBevel = bevelRear ? (1 - smooth(0.92, 1.0, v)) : 1
                    p.y -= recess + 0.010 * (1 - sideBevel) + 0.007 * (1 - frontBevel * rearBevel)
                    pts.append(p)
                    uvs.append(uv(t, a))
                }
            }
            let w = Int32(cols + 1)
            for r in 0..<Int32(rows) {
                for c in 0..<Int32(cols) {
                    let a0 = base + r * w + c, b0 = a0 + 1, d0 = a0 + w, c0 = d0 + 1
                    idx += [a0, b0, d0, b0, c0, d0]
                }
            }
        }

        // Front island strip (with LED), starting behind the open front U-notch.
        addStrip(t0: frontNotchT, t1: 0.152, x0: islandHalfX, x1: -islandHalfX, rows: 10, cols: 12, recess: 0.014, bevelFront: true, bevelRear: false)
        // Smooth rear island strip behind the scroll wheel (no button on top of the G7).
        addStrip(t0: 0.326, t1: 0.447, x0: islandHalfX, x1: -islandHalfX, rows: 12, cols: 12, recess: 0.012, bevelFront: false, bevelRear: true)
        // Thin white rails flanking the scroll wheel well.
        addStrip(t0: 0.152, t1: 0.326, x0: islandHalfX, x1: 0.194, rows: 14, cols: 3, recess: 0.013, bevelFront: false, bevelRear: false)
        addStrip(t0: 0.152, t1: 0.326, x0: -0.194, x1: -islandHalfX, rows: 14, cols: 3, recess: 0.013, bevelFront: false, bevelRear: false)

        // Front wall of the center island inside the open notch.
        let frontCols = 12
        let fBase = Int32(pts.count)
        for c in 0...frontCols {
            let u = Float(c) / Float(frontCols)
            let x = islandHalfX - 2 * islandHalfX * u
            let a = angleForTopX(x, at: frontNotchT)
            let topP = surface(frontNotchT, a) - SIMD3<Float>(0, 0.020, 0)
            let botP = topP - SIMD3<Float>(0, 0.065, -0.015)
            pts.append(topP); uvs.append(uv(frontNotchT, a))
            pts.append(botP); uvs.append(uv(frontNotchT, a))
        }
        for c in 0..<Int32(frontCols) {
            let t0 = fBase + c * 2
            let b0 = t0 + 1
            let t1 = t0 + 2
            let b1 = t0 + 3
            idx += [t0, b0, t1, b0, b1, t1]
        }

        let islandGeo = CapMesh.assemble(pts, uvs, [idx])
        islandGeo.materials = [material]
        let islandNode = SCNNode(geometry: islandGeo)
        islandNode.castsShadow = true
        mouse.addChildNode(islandNode)
    }

    static func buildWheel(into mouse: SCNNode) {
        let t: Float = 0.240
        let top = surface(t, .pi / 2)
        let radius: Float = 0.440

        // Dark recessed slot for the scroll wheel.
        let ahead = surface(t - 0.08, .pi / 2), behind = surface(t + 0.08, .pi / 2)
        let slope = atan2(behind.y - ahead.y, behind.z - ahead.z)
        let well = SCNBox(width: 0.39, height: 0.28, length: 1.18, chamferRadius: 0.06)
        let wellMat = SCNMaterial()
        wellMat.lightingModel = .physicallyBased
        wellMat.diffuse.contents = NSColor(white: 0.04, alpha: 1)
        wellMat.roughness.contents = 0.78
        well.materials = [wellMat]
        let wellNode = SCNNode(geometry: well)
        wellNode.position = SCNVector3(top.x, top.y - 0.145, top.z)
        wellNode.eulerAngles.x = CGFloat(-slope)
        wellNode.castsShadow = false
        mouse.addChildNode(wellNode)

        let rubber = SCNMaterial()
        rubber.lightingModel = .physicallyBased
        rubber.diffuse.contents = NSColor(white: 0.065, alpha: 1)
        rubber.roughness.contents = 0.72

        let rimMat = SCNMaterial()
        rimMat.lightingModel = .physicallyBased
        rimMat.diffuse.contents = NSColor(srgbRed: 0.88, green: 0.88, blue: 0.89, alpha: 1)
        rimMat.metalness.contents = 0.22
        rimMat.roughness.contents = 0.26

        let hubMat = SCNMaterial()
        hubMat.lightingModel = .physicallyBased
        hubMat.diffuse.contents = NSColor(white: 0.68, alpha: 1)
        hubMat.metalness.contents = 0.35
        hubMat.roughness.contents = 0.35

        let wheel = SCNNode()
        wheel.name = TechProps.MouseParts.wheel
        wheel.position = SCNVector3(top.x, top.y + 0.20 - radius, top.z)
        mouse.addChildNode(wheel)

        let core = SCNCylinder(radius: CGFloat(radius), height: 0.29)
        core.radialSegmentCount = 48
        core.materials = [rubber]
        let coreNode = SCNNode(geometry: core)
        coreNode.eulerAngles.z = .pi / 2
        coreNode.castsShadow = false
        wheel.addChildNode(coreNode)

        // Prominent white/silver wheel side rims flush with the grooved rubber tire.
        for sx: Float in [-0.164, 0.164] {
            let rim = SCNTorus(ringRadius: CGFloat(radius - 0.022), pipeRadius: 0.028)
            rim.ringSegmentCount = 48
            rim.pipeSegmentCount = 16
            rim.materials = [rimMat]
            let rimNode = SCNNode(geometry: rim)
            rimNode.eulerAngles.z = .pi / 2
            rimNode.position = SCNVector3(sx, 0, 0)
            rimNode.castsShadow = false
            wheel.addChildNode(rimNode)

            let innerDisc = SCNCylinder(radius: CGFloat(radius - 0.05), height: 0.018)
            innerDisc.radialSegmentCount = 36
            innerDisc.materials = [hubMat]
            let discNode = SCNNode(geometry: innerDisc)
            discNode.eulerAngles.z = .pi / 2
            discNode.position = SCNVector3(sx * 0.88, 0, 0)
            discNode.castsShadow = false
            wheel.addChildNode(discNode)
        }

        // Single merged geometry for all 36 rubber tread ribs (1 draw call instead of 36).
        let ribsGeo = buildMergedWheelRibs(count: 36, radius: radius, width: 0.286, height: 0.022, length: 0.028)
        ribsGeo.materials = [rubber]
        let ribsNode = SCNNode(geometry: ribsGeo)
        ribsNode.castsShadow = false
        wheel.addChildNode(ribsNode)
    }

    private static func buildMergedWheelRibs(
        count: Int, radius: Float, width: Float, height: Float, length: Float
    ) -> SCNGeometry {
        let hw = width * 0.5
        let hh = height * 0.5
        let hl = length * 0.5

        // Local beveled-profile strip rotated around X for each rib.
        let localVerts: [SIMD3<Float>] = [
            SIMD3(-hw, -hh, -hl), SIMD3(hw, -hh, -hl), SIMD3(hw, hh * 0.85, -hl * 0.65), SIMD3(-hw, hh * 0.85, -hl * 0.65),
            SIMD3(-hw, -hh,  hl), SIMD3(hw, -hh,  hl), SIMD3(hw, hh * 0.85,  hl * 0.65), SIMD3(-hw, hh * 0.85,  hl * 0.65),
        ]
        // 5 exposed outward faces (outer crown + front/back + left/right caps); underside embedded in tire core.
        let faces: [(v: (Int, Int, Int, Int), n: SIMD3<Float>)] = [
            ((3, 2, 6, 7), SIMD3(0, 1, 0)),
            ((0, 3, 7, 4), SIMD3(-1, 0, 0)),
            ((2, 1, 5, 6), SIMD3(1, 0, 0)),
            ((0, 1, 2, 3), SIMD3(0, 0.45, -0.89)),
            ((7, 6, 5, 4), SIMD3(0, 0.45, 0.89)),
        ]

        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [Int32]()
        positions.reserveCapacity(count * faces.count * 4)
        normals.reserveCapacity(count * faces.count * 4)
        uvs.reserveCapacity(count * faces.count * 4)
        indices.reserveCapacity(count * faces.count * 6)

        for i in 0..<count {
            let a = Float(i) / Float(count) * 2 * .pi
            let ca = cos(a), sa = sin(a)
            // Rotate local offset by -a around X axis and translate radially by (0, sa*radius, ca*radius).
            func xform(_ p: SIMD3<Float>) -> SIMD3<Float> {
                let ry = p.y * ca + p.z * sa
                let rz = -p.y * sa + p.z * ca
                return SIMD3(p.x, sa * radius + ry, ca * radius + rz)
            }
            func xformN(_ n: SIMD3<Float>) -> SIMD3<Float> {
                simd_normalize(SIMD3(n.x, n.y * ca + n.z * sa, -n.y * sa + n.z * ca))
            }

            for f in faces {
                let base = Int32(positions.count)
                let rn = xformN(f.n)
                for idxV in [f.v.0, f.v.1, f.v.2, f.v.3] {
                    positions.append(xform(localVerts[idxV]))
                    normals.append(rn)
                }
                uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
                indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            }
        }

        let vSrc = SCNGeometrySource(
            data: positions.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .vertex, vectorCount: positions.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let nSrc = SCNGeometrySource(
            data: normals.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .normal, vectorCount: normals.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let tSrc = SCNGeometrySource(
            data: uvs.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .texcoord, vectorCount: uvs.count,
            usesFloatComponents: true, componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD2<Float>>.stride
        )
        return SCNGeometry(sources: [vSrc, nSrc, tSrc], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    static func buildLED(into mouse: SCNNode) {
        let t: Float = 0.098
        let p = surface(t, .pi / 2)
        let ahead = surface(t - 0.03, .pi / 2), behind = surface(t + 0.03, .pi / 2)
        let slope = atan2(behind.y - ahead.y, behind.z - ahead.z)

        let ledPivot = SCNNode()
        ledPivot.position = SCNVector3(p.x, p.y - 0.014, p.z)
        ledPivot.eulerAngles.x = CGFloat(-slope)
        mouse.addChildNode(ledPivot)

        // Flush cyan pill LED directly in the white front center strip.
        let led = SCNCapsule(capRadius: 0.024, height: 0.175)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor(srgbRed: 0.30, green: 0.85, blue: 1.0, alpha: 1)
        led.materials = [m]
        let node = SCNNode(geometry: led)
        node.name = TechProps.MouseParts.dpiLED
        node.position = SCNVector3(0, 0.001, 0)
        node.eulerAngles.z = .pi / 2
        node.castsShadow = false
        ledPivot.addChildNode(node)
    }

    static func buildUSBC(into mouse: SCNNode, dark: SCNMaterial) {
        // Recessed dark USB-C port opening seated parallel and flush on the front nose bulkhead.
        let pBot = surface(0, -.pi / 2)
        let pTop = surface(frontNotchT, .pi / 2) - SIMD3<Float>(0, 0.075, -0.010)
        let portCenter = pBot + (pTop - pBot) * 0.42
        let portSlope = atan2(pTop.z - pBot.z, pTop.y - pBot.y)
        let noseNormal = SIMD3<Float>(0, sin(portSlope), -cos(portSlope))

        func stadium(_ width: CGFloat, _ height: CGFloat, depth: CGFloat, material: SCNMaterial, outset: Float) {
            let path = NSBezierPath(
                roundedRect: NSRect(x: -width / 2, y: -height / 2, width: width, height: height),
                xRadius: height / 2, yRadius: height / 2
            )
            path.flatness = 0.002
            let shape = SCNShape(path: path, extrusionDepth: depth)
            shape.materials = [material]
            let pos = portCenter + noseNormal * outset
            let node = SCNNode(geometry: shape)
            node.position = SCNVector3(pos.x, pos.y, pos.z)
            node.eulerAngles.x = CGFloat(portSlope)
            node.castsShadow = false
            mouse.addChildNode(node)
        }

        let recessMat = SCNMaterial()
        recessMat.lightingModel = .physicallyBased
        recessMat.diffuse.contents = NSColor(white: 0.02, alpha: 1)
        recessMat.roughness.contents = 0.75

        let tongueMat = SCNMaterial()
        tongueMat.lightingModel = .physicallyBased
        tongueMat.diffuse.contents = NSColor(white: 0.22, alpha: 1)
        tongueMat.metalness.contents = 0.55
        tongueMat.roughness.contents = 0.40

        stadium(0.38, 0.16, depth: 0.04, material: dark, outset: 0.004)
        stadium(0.31, 0.11, depth: 0.03, material: recessMat, outset: 0.014)
        stadium(0.19, 0.030, depth: 0.025, material: tongueMat, outset: 0.018)
    }

    // MARK: Side buttons

    /// Builds a surface-conforming curved button shell along the left flank.
    private static func conformingSideButton(
        tMin: Float, tMax: Float,
        yRangeAt: (Float) -> (low: Float, high: Float),
        raise: Float,
        inset: Float,
        material: SCNMaterial,
        castsShadow: Bool
    ) -> SCNNode {
        let rows = 18
        let cols = 10
        var pts = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var idx = [Int32]()

        func angleForFlankY(_ targetY: Float, at t: Float) -> Float {
            var lo: Float = 0.55 * .pi
            var hi: Float = .pi
            for _ in 0..<16 {
                let mid = 0.5 * (lo + hi)
                if surface(t, mid).y > targetY { lo = mid } else { hi = mid }
            }
            return 0.5 * (lo + hi)
        }

        var outerPts = [[SIMD3<Float>]]()
        var basePts = [[SIMD3<Float>]]()
        var outerUVs = [[SIMD2<Float>]]()

        for r in 0...rows {
            let v = Float(r) / Float(rows)
            let t = tMin + (tMax - tMin) * v
            let (yLowRaw, yHighRaw) = yRangeAt(t)
            let yLow = yLowRaw + inset
            let yHigh = max(yLow + 0.015, yHighRaw - inset)
            var rowOut = [SIMD3<Float>]()
            var rowBase = [SIMD3<Float>]()
            var rowUV = [SIMD2<Float>]()

            let endRound = sin(min(max(v / 0.07, 0), 1) * .pi / 2) * sin(min(max((1 - v) / 0.07, 0), 1) * .pi / 2)
            for c in 0...cols {
                let u = Float(c) / Float(cols)
                let y = yLow + (yHigh - yLow) * u
                let a = angleForFlankY(y, at: t)
                let p = surface(t, a)
                let n = normal(t, a)
                let edgeRound = sin(min(max(u / 0.14, 0), 1) * .pi / 2) * sin(min(max((1 - u) / 0.14, 0), 1) * .pi / 2)
                let h = raise * (0.58 + 0.42 * endRound * edgeRound)
                rowOut.append(p + n * h)
                rowBase.append(p - n * 0.015)
                rowUV.append(SIMD2(u, v))
            }
            outerPts.append(rowOut)
            basePts.append(rowBase)
            outerUVs.append(rowUV)
        }

        let w = Int32(cols + 1)
        let outStart = Int32(pts.count)
        for r in 0...rows {
            pts.append(contentsOf: outerPts[r])
            uvs.append(contentsOf: outerUVs[r])
        }
        for r in 0..<Int32(rows) {
            for c in 0..<Int32(cols) {
                let a0 = outStart + r * w + c, b0 = a0 + 1, d0 = a0 + w, c0 = d0 + 1
                idx += [a0, d0, b0, b0, d0, c0]
            }
        }

        func addSkirt(_ stripOut: [SIMD3<Float>], _ stripBase: [SIMD3<Float>], flip: Bool) {
            let sBase = Int32(pts.count)
            for i in 0..<stripOut.count {
                pts.append(stripOut[i]); uvs.append(SIMD2(Float(i) / Float(max(stripOut.count - 1, 1)), 1))
                pts.append(stripBase[i]); uvs.append(SIMD2(Float(i) / Float(max(stripOut.count - 1, 1)), 0))
            }
            for i in 0..<Int32(stripOut.count - 1) {
                let o0 = sBase + i * 2, i0 = o0 + 1, o1 = o0 + 2, i1 = o0 + 3
                if flip {
                    idx += [o0, o1, i0, o1, i1, i0]
                } else {
                    idx += [o0, i0, o1, i0, i1, o1]
                }
            }
        }
        addSkirt(outerPts[0], basePts[0], flip: false)
        addSkirt(outerPts[rows], basePts[rows], flip: true)
        addSkirt((0...rows).map { outerPts[$0][0] }, (0...rows).map { basePts[$0][0] }, flip: true)
        addSkirt((0...rows).map { outerPts[$0][cols] }, (0...rows).map { basePts[$0][cols] }, flip: false)

        let geo = CapMesh.assemble(pts, uvs, [idx])
        geo.materials = [material]
        let node = SCNNode(geometry: geo)
        node.castsShadow = castsShadow
        return node
    }

    static func buildSideButtons(into mouse: SCNNode, dark: SCNMaterial) {
        let forwardRange: (Float) -> (low: Float, high: Float) = { t in
            let u = min(max((t - 0.365) / (0.496 - 0.365), 0), 1)
            let frontBevel = smooth(0.0, 0.22, u)
            let low = 1.42 * (1 - frontBevel) + (1.16 + 0.08 * u) * frontBevel
            let high = 1.44 + 0.12 * sin(min(u / 0.85, 1) * .pi / 2)
            return (low, high)
        }

        let backRange: (Float) -> (low: Float, high: Float) = { t in
            let u = min(max((t - 0.508) / (0.646 - 0.508), 0), 1)
            let rearTaper = smooth(0.72, 1.0, u)
            let low = (1.24 + 0.02 * sin(u * .pi)) * (1 - rearTaper) + 1.45 * rearTaper
            let high = 1.56 - 0.06 * smooth(0.78, 1.0, u)
            return (low, high)
        }

        let specs: [(Float, Float, (Float) -> (low: Float, high: Float), String)] = [
            (0.365, 0.496, forwardRange, TechProps.MouseParts.forward),
            (0.508, 0.646, backRange, TechProps.MouseParts.back),
        ]

        for (t0, t1, rangeFn, name) in specs {
            let white = SCNMaterial()
            white.lightingModel = .physicallyBased
            white.diffuse.contents = NSColor(srgbRed: 0.86, green: 0.855, blue: 0.848, alpha: 1)
            white.roughness.contents = 0.46

            let seamNode = conformingSideButton(
                tMin: t0 - 0.004, tMax: t1 + 0.004,
                yRangeAt: rangeFn, raise: 0.015, inset: -0.016,
                material: dark, castsShadow: false
            )
            mouse.addChildNode(seamNode)

            let btnNode = conformingSideButton(
                tMin: t0, tMax: t1,
                yRangeAt: rangeFn, raise: 0.068, inset: 0.0,
                material: white, castsShadow: true
            )
            btnNode.name = name
            mouse.addChildNode(btnNode)
        }
    }
}
