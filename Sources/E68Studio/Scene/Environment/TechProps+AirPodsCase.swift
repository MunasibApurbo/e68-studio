import SceneKit
import AppKit
import simd

extension TechProps {
    // MARK: - AirPods 3rd Gen Case

    static func buildAirPods3(into root: SCNNode) {
        // Real setup keeps the closed AirPods case tucked on the back-left corner of the desk mat below the lamp overhang.
        let casePos = SIMD3<Float>(-16.6, DeskRoomAndMat.matTopY, -7.2)
        let airpods = SCNNode()
        airpods.position = SCNVector3(casePos.x, casePos.y, casePos.z)
        airpods.eulerAngles.y = -0.22
        root.addChildNode(airpods)

        // Contact shadow underneath AirPods case
        DeskRoomAndMat.addContactShadow(at: SIMD3(casePos.x, casePos.y + 0.004, casePos.z), radiusX: 1.50, radiusZ: 1.30, opacity: 0.22, yaw: -0.22, into: root)

        // AirPods (3rd gen) case: single watertight glossy ceramic-polymer shell with antialiased hairline parting texture
        // (avoids 1px subpixel shadow-map stippling along a physical bevel gap)
        let halfW: Float = 1.428     // 54.4 mm width
        let halfH: Float = 0.561     // 21.38 mm thickness
        let halfL: Float = 1.218     // 46.4 mm height
        let rCorner: Float = 0.567   // ~10.8 mm corner & dome roll radius
        let crown: Float = 0.014     // gentle organic dome across wide front/back faces
        let seamZ: Float = -0.37     // lid is top ~35% of case height
        let seamV = CGFloat((seamZ + halfL) / (2 * halfL)) // 0 (-Z) -> 1 (+Z)

        let caseDiffuseTex = DeskTextures.makeImage(512, 1024) { ctx, W, H in
            ctx.setFillColor(NSColor(srgbRed: 0.87, green: 0.87, blue: 0.864, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            // Metal/SceneKit CGImage flips V vs CGContext bottom-left origin
            let seamCY = H * (1.0 - seamV)
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            let grooveHalfPx: CGFloat = 4.2
            let grooveGrad = CGGradient(
                colorsSpace: srgb,
                colors: [
                    NSColor(srgbRed: 0.87, green: 0.87, blue: 0.864, alpha: 0.0).cgColor,
                    NSColor(srgbRed: 0.58, green: 0.58, blue: 0.575, alpha: 0.72).cgColor,
                    NSColor(srgbRed: 0.34, green: 0.34, blue: 0.335, alpha: 0.96).cgColor,
                    NSColor(srgbRed: 0.58, green: 0.58, blue: 0.575, alpha: 0.72).cgColor,
                    NSColor(srgbRed: 0.87, green: 0.87, blue: 0.864, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.28, 0.50, 0.72, 1.0]
            )!
            ctx.drawLinearGradient(
                grooveGrad,
                start: CGPoint(x: 0, y: seamCY - grooveHalfPx),
                end: CGPoint(x: 0, y: seamCY + grooveHalfPx),
                options: []
            )
        }

        let caseRoughnessTex = DeskTextures.makeImage(128, 1024) { ctx, W, H in
            ctx.setFillColor(NSColor(white: 0.10, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let seamCY = H * (1.0 - seamV)
            ctx.setFillColor(NSColor(white: 0.58, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: seamCY - 2.5, width: W, height: 5.0))
        }

        let caseShellMat = SCNMaterial()
        caseShellMat.lightingModel = .physicallyBased
        caseShellMat.diffuse.contents = caseDiffuseTex
        caseShellMat.roughness.contents = caseRoughnessTex
        caseShellMat.metalness.contents = 0.0
        caseShellMat.clearCoat.contents = 0.96
        caseShellMat.clearCoatRoughness.contents = 0.035

        let whiteGloss = SCNMaterial()
        whiteGloss.lightingModel = .physicallyBased
        whiteGloss.diffuse.contents = NSColor(srgbRed: 0.87, green: 0.87, blue: 0.864, alpha: 1)
        whiteGloss.roughness.contents = 0.10
        whiteGloss.metalness.contents = 0.0
        whiteGloss.clearCoat.contents = 0.96
        whiteGloss.clearCoatRoughness.contents = 0.035

        let seamMat = SCNMaterial()
        seamMat.lightingModel = .physicallyBased
        seamMat.diffuse.contents = NSColor(white: 0.42, alpha: 1)
        seamMat.roughness.contents = 0.45

        let caseGeo = airPodsCaseShell(
            halfW: halfW, halfH: halfH, centerY: halfH,
            zMin: -halfL, zMax: halfL, outerHalfL: halfL,
            roundNegZ: true, roundPosZ: true,
            rCorner: rCorner, crown: crown, seamChamfer: 0
        )
        caseGeo.materials = [caseShellMat]
        let caseNode = SCNNode(geometry: caseGeo)
        caseNode.castsShadow = true
        airpods.addChildNode(caseNode)

        // Flush diffused status LED pinhole on the front (+Y) face just below the lid parting line
        let ledTex = DeskTextures.makeImage(64, 64) { ctx, W, H in
            ctx.clear(CGRect(x: 0, y: 0, width: W, height: H))
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            let grad = CGGradient(
                colorsSpace: srgb,
                colors: [
                    NSColor(srgbRed: 0.72, green: 0.96, blue: 0.62, alpha: 1.0).cgColor,
                    NSColor(srgbRed: 0.42, green: 0.88, blue: 0.34, alpha: 0.88).cgColor,
                    NSColor(srgbRed: 0.56, green: 0.80, blue: 0.52, alpha: 0.28).cgColor,
                    NSColor(srgbRed: 0.84, green: 0.84, blue: 0.832, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.36, 0.68, 1.0]
            )!
            ctx.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: W * 0.5, y: H * 0.5),
                startRadius: 0,
                endCenter: CGPoint(x: W * 0.5, y: H * 0.5),
                endRadius: W * 0.48,
                options: []
            )
        }
        let ledMat = SCNMaterial()
        ledMat.lightingModel = .physicallyBased
        ledMat.diffuse.contents = ledTex
        ledMat.emission.contents = ledTex
        ledMat.emission.intensity = 0.42
        ledMat.roughness.contents = 0.16
        ledMat.clearCoat.contents = 0.88
        ledMat.blendMode = .alpha
        ledMat.writesToDepthBuffer = false
        let ledPlane = SCNPlane(width: 0.088, height: 0.088)
        ledPlane.materials = [ledMat]
        let ledNode = SCNNode(geometry: ledPlane)
        ledNode.eulerAngles.x = -.pi / 2
        ledNode.position = SCNVector3(0, halfH * 2 + 0.0015, seamZ + 0.20)
        ledNode.castsShadow = false
        ledNode.renderingOrder = 2
        airpods.addChildNode(ledNode)

        // Flush metallic rear hinge and subtle circular pairing button on the back (-Y) face
        let chromeMat = SCNMaterial()
        chromeMat.lightingModel = .physicallyBased
        chromeMat.diffuse.contents = NSColor(white: 0.78, alpha: 1)
        chromeMat.metalness.contents = 0.94
        chromeMat.roughness.contents = 0.18

        let hingePath = NSBezierPath(roundedRect: NSRect(x: -0.45, y: -0.105, width: 0.90, height: 0.21), xRadius: 0.09, yRadius: 0.09)
        hingePath.flatness = 0.002
        let hingeGeo = SCNShape(path: hingePath, extrusionDepth: 0.010)
        hingeGeo.materials = [chromeMat]
        let hingeNode = SCNNode(geometry: hingeGeo)
        hingeNode.eulerAngles.x = .pi / 2
        hingeNode.position = SCNVector3(0, 0.002, seamZ)
        hingeNode.castsShadow = false
        airpods.addChildNode(hingeNode)

        let pairingBtnMat = SCNMaterial()
        pairingBtnMat.lightingModel = .physicallyBased
        pairingBtnMat.diffuse.contents = NSColor(srgbRed: 0.78, green: 0.78, blue: 0.77, alpha: 1)
        pairingBtnMat.roughness.contents = 0.24
        let pairingRing = SCNTorus(ringRadius: 0.20, pipeRadius: 0.008)
        pairingRing.materials = [seamMat]
        let pairingRingNode = SCNNode(geometry: pairingRing)
        pairingRingNode.position = SCNVector3(0, 0.002, seamZ + 0.44)
        airpods.addChildNode(pairingRingNode)
        let pairingCap = SCNCylinder(radius: 0.194, height: 0.006)
        pairingCap.materials = [pairingBtnMat]
        let pairingCapNode = SCNNode(geometry: pairingCap)
        pairingCapNode.position = SCNVector3(0, 0.003, seamZ + 0.44)
        airpods.addChildNode(pairingCapNode)

        // Conformal Lightning port on the curved +Z nose (zero z-fighting)
        buildAirPodsLightningPort(
            halfH: halfH,
            cZ: halfL - rCorner,
            rCorner: rCorner,
            chromeMat: chromeMat,
            into: airpods
        )

        // Closed AirPods 3rd-gen charging case resting on back-left of Ukiru mat (both earbuds inside case).
    }

    private static func buildAirPodsLightningPort(
        halfH: Float,
        cZ: Float,
        rCorner: Float,
        chromeMat: SCNMaterial,
        into parent: SCNNode
    ) {
        let portDark = SCNMaterial()
        portDark.lightingModel = .physicallyBased
        portDark.diffuse.contents = NSColor(white: 0.02, alpha: 1)
        portDark.roughness.contents = 0.75

        let tongueMat = SCNMaterial()
        tongueMat.lightingModel = .physicallyBased
        tongueMat.diffuse.contents = NSColor(srgbRed: 0.72, green: 0.64, blue: 0.44, alpha: 1)
        tongueMat.metalness.contents = 0.72
        tongueMat.roughness.contents = 0.28

        @inline(__always)
        func noseZ(atLocalY dy: Float) -> Float {
            let ny = min(max(dy / halfH, -0.99), 0.99)
            return cZ + rCorner * sqrt(max(0, 1 - ny * ny))
        }

        // Conformal stadium bezel ring wrapping smoothly onto the curved +Z nose
        let outerHW: Float = 0.220, outerHH: Float = 0.076
        let innerHW: Float = 0.180, innerHH: Float = 0.050
        let segs = 40

        func pillPoint(hw: Float, hh: Float, angle a: Float) -> (x: Float, y: Float) {
            let r = hh
            let straight = max(0, hw - r)
            let ca = cos(a), sa = sin(a)
            let px = (ca >= 0 ? straight : -straight) + r * ca
            let py = r * sa
            return (px, py)
        }

        var bezelPos = [SIMD3<Float>]()
        var bezelUV = [SIMD2<Float>]()
        var bezelIdx = [Int32]()

        // 3 rings: outer embedded (-0.0015), outer crest (+0.0045), inner cavity rim (+0.0015)
        let ringSpecs: [(hw: Float, hh: Float, zOff: Float)] = [
            (outerHW + 0.012, outerHH + 0.010, -0.002),
            (outerHW, outerHH, +0.0045),
            (innerHW, innerHH, +0.0018),
        ]
        for spec in ringSpecs {
            for i in 0..<segs {
                let a = Float(i) / Float(segs) * 2 * .pi
                let p = pillPoint(hw: spec.hw, hh: spec.hh, angle: a)
                let z = noseZ(atLocalY: p.y) + spec.zOff
                bezelPos.append(SIMD3(p.x, halfH + p.y, z))
                bezelUV.append(SIMD2(Float(i) / Float(segs), 0.5))
            }
        }
        for r in 0..<2 {
            for i in 0..<segs {
                let next = (i + 1) % segs
                let a = Int32(r * segs + i)
                let b = Int32(r * segs + next)
                let d = Int32((r + 1) * segs + i)
                let c = Int32((r + 1) * segs + next)
                bezelIdx += [a, b, d, b, c, d]
            }
        }
        let bezelGeo = CapMesh.assemble(bezelPos, bezelUV, [bezelIdx])
        bezelGeo.materials = [chromeMat]
        let bezelNode = SCNNode(geometry: bezelGeo)
        bezelNode.castsShadow = false
        parent.addChildNode(bezelNode)

        // Conformal dark interior cavity patch
        var cavPos = [SIMD3<Float>]()
        var cavUV = [SIMD2<Float>]()
        var cavIdx = [Int32]()
        cavPos.append(SIMD3(0, halfH, noseZ(atLocalY: 0) + 0.0016))
        cavUV.append(SIMD2(0.5, 0.5))
        for i in 0..<segs {
            let a = Float(i) / Float(segs) * 2 * .pi
            let p = pillPoint(hw: innerHW + 0.004, hh: innerHH + 0.003, angle: a)
            cavPos.append(SIMD3(p.x, halfH + p.y, noseZ(atLocalY: p.y) + 0.0016))
            cavUV.append(SIMD2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)))
        }
        for i in 0..<segs {
            let next = (i + 1) % segs
            cavIdx += [0, Int32(1 + i), Int32(1 + next)]
        }
        let cavGeo = CapMesh.assemble(cavPos, cavUV, [cavIdx])
        cavGeo.materials = [portDark]
        let cavNode = SCNNode(geometry: cavGeo)
        cavNode.castsShadow = false
        parent.addChildNode(cavNode)

        // Tiny recessed internal Lightning contact pin bar
        let pinBar = SCNBox(width: 0.22, height: 0.022, length: 0.003, chamferRadius: 0.001)
        pinBar.materials = [tongueMat]
        let pinNode = SCNNode(geometry: pinBar)
        pinNode.position = SCNVector3(0, halfH, noseZ(atLocalY: 0) + 0.0022)
        pinNode.castsShadow = false
        parent.addChildNode(pinNode)
    }

    /// Generates an outward-wound, watertight Z-ring stadium-squircle shell half (lid, body, or inner seam lip)
    /// with exact analytical surface normals on the outer shell and an unwelded flat cap at the parting plane.
    private static func airPodsCaseShell(
        halfW: Float, halfH: Float, centerY: Float,
        zMin: Float, zMax: Float, outerHalfL: Float,
        roundNegZ: Bool, roundPosZ: Bool,
        rCorner: Float, crown: Float, seamChamfer: Float
    ) -> SCNGeometry {
        let flatW = max(0.02, halfW - rCorner)
        let cZ = max(0.02, outerHalfL - rCorner)
        let rFlankY = max(0.02, halfH - crown)

        // 96-point closed 2D cross-section loop: 16 per corner quarter-arc + 16 top + 16 bottom
        let arcSegs = 16
        let flatSegs = 16
        var baseXY = [SIMD2<Float>]()
        var baseN = [SIMD2<Float>]()
        baseXY.reserveCapacity(arcSegs * 4 + flatSegs * 2)
        baseN.reserveCapacity(arcSegs * 4 + flatSegs * 2)

        func appendFlankArc(cx: Float, startA: Float, endA: Float) {
            for i in 0..<arcSegs {
                let a = startA + Float(i) / Float(arcSegs) * (endA - startA)
                let ca = cos(a), sa = sin(a)
                baseXY.append(SIMD2(cx + rCorner * ca, rFlankY * sa))
                baseN.append(simd_normalize(SIMD2(ca / rCorner, sa / rFlankY)))
            }
        }

        // Right-top flank (0 .. pi/2)
        appendFlankArc(cx: flatW, startA: 0, endA: .pi / 2)
        // Top plateau (+flatW -> -flatW)
        for i in 0..<flatSegs {
            let t = Float(i) / Float(flatSegs)
            let x = flatW * (1 - 2 * t)
            let y = rFlankY + crown * 0.5 * (1 + cos(.pi * x / flatW))
            let dydx = -crown * 0.5 * (.pi / flatW) * sin(.pi * x / flatW)
            baseXY.append(SIMD2(x, y))
            baseN.append(simd_normalize(SIMD2(-dydx, 1)))
        }
        // Left-top flank (pi/2 .. pi)
        appendFlankArc(cx: -flatW, startA: .pi / 2, endA: .pi)
        // Left-bottom flank (pi .. 3pi/2)
        appendFlankArc(cx: -flatW, startA: .pi, endA: 1.5 * .pi)
        // Bottom plateau (-flatW -> +flatW)
        for i in 0..<flatSegs {
            let t = Float(i) / Float(flatSegs)
            let x = flatW * (-1 + 2 * t)
            let y = -(rFlankY + crown * 0.5 * (1 + cos(.pi * x / flatW)))
            let dydx = crown * 0.5 * (.pi / flatW) * sin(.pi * x / flatW)
            baseXY.append(SIMD2(x, y))
            baseN.append(simd_normalize(SIMD2(dydx, -1)))
        }
        // Right-bottom flank (3pi/2 .. 2pi)
        appendFlankArc(cx: flatW, startA: 1.5 * .pi, endA: 2 * .pi)

        let ringSegs = baseXY.count

        struct SliceSpec {
            let z: Float
            let isDome: Bool
            let zSign: Float
            let cosB: Float
            let sinB: Float
            let chamferInset: Float
            let chamferSin: Float
            let chamferCos: Float
        }

        var slices = [SliceSpec]()
        let domeSteps = 18
        let straightSteps = 12
        let chamferAngles: [Float] = [0, .pi / 6, .pi / 3, .pi / 2]

        func appendStraight(_ z0: Float, _ z1: Float, count: Int) {
            for i in 0..<count {
                let z = z0 + (z1 - z0) * Float(i) / Float(count)
                slices.append(SliceSpec(z: z, isDome: false, zSign: 0, cosB: 1, sinB: 0, chamferInset: 0, chamferSin: 0, chamferCos: 1))
            }
        }

        if roundNegZ {
            // -Z dome from pole (beta = pi/2) down to -cZ (beta = 0, excluded so straight section joins cleanly)
            for i in 0..<domeSteps {
                let beta = (1 - Float(i) / Float(domeSteps)) * (.pi / 2)
                let sb = sin(beta), cb = cos(beta)
                slices.append(SliceSpec(z: -cZ - rCorner * sb, isDome: true, zSign: -1, cosB: cb, sinB: sb, chamferInset: 0, chamferSin: 0, chamferCos: 1))
            }
        } else if seamChamfer > 0 {
            for phi in chamferAngles.reversed() {
                slices.append(SliceSpec(
                    z: zMin + seamChamfer * (1 - sin(phi)),
                    isDome: false, zSign: 0, cosB: 1, sinB: 0,
                    chamferInset: seamChamfer * (1 - cos(phi)),
                    chamferSin: -sin(phi),
                    chamferCos: cos(phi)
                ))
            }
        }

        let flatStart = roundNegZ ? -cZ : (zMin + seamChamfer)
        let flatEnd = roundPosZ ? cZ : (zMax - seamChamfer)
        appendStraight(flatStart, flatEnd, count: straightSteps)

        if roundPosZ {
            // +Z dome from cZ (beta = 0) up to pole (beta = pi/2)
            for i in 0...domeSteps {
                let beta = Float(i) / Float(domeSteps) * (.pi / 2)
                let sb = sin(beta), cb = cos(beta)
                slices.append(SliceSpec(z: cZ + rCorner * sb, isDome: true, zSign: 1, cosB: cb, sinB: sb, chamferInset: 0, chamferSin: 0, chamferCos: 1))
            }
        } else if seamChamfer > 0 {
            for phi in chamferAngles {
                slices.append(SliceSpec(
                    z: zMax - seamChamfer * (1 - sin(phi)),
                    isDome: false, zSign: 0, cosB: 1, sinB: 0,
                    chamferInset: seamChamfer * (1 - cos(phi)),
                    chamferSin: sin(phi),
                    chamferCos: cos(phi)
                ))
            }
        } else {
            slices.append(SliceSpec(z: zMax, isDome: false, zSign: 0, cosB: 1, sinB: 0, chamferInset: 0, chamferSin: 0, chamferCos: 1))
        }

        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [Int32]()

        positions.reserveCapacity(slices.count * ringSegs + ringSegs + 2)
        normals.reserveCapacity(slices.count * ringSegs + ringSegs + 2)
        uvs.reserveCapacity(slices.count * ringSegs + ringSegs + 2)

        for s in slices {
            let v = (s.z + outerHalfL) / (2 * outerHalfL)
            for i in 0..<ringSegs {
                let p0 = baseXY[i]
                let n0 = baseN[i]
                let x: Float
                let y: Float
                let n3: SIMD3<Float>

                if s.isDome {
                    if abs(p0.x) <= flatW {
                        x = p0.x
                        y = p0.y * s.cosB
                        let nr = SIMD3<Float>(n0.x * rCorner * s.cosB, n0.y * rCorner * s.cosB, s.zSign * abs(p0.y) * s.sinB)
                        n3 = simd_length(nr) > 1e-6 ? simd_normalize(nr) : SIMD3(0, 0, s.zSign)
                    } else {
                        let cx: Float = p0.x > 0 ? flatW : -flatW
                        x = cx + (p0.x - cx) * s.cosB
                        y = p0.y * s.cosB
                        let nr = SIMD3<Float>((p0.x - cx) / (rCorner * rCorner) * s.cosB,
                                              p0.y / (rFlankY * rFlankY) * s.cosB,
                                              s.zSign * s.sinB / rCorner)
                        n3 = simd_length(nr) > 1e-6 ? simd_normalize(nr) : SIMD3(0, 0, s.zSign)
                    }
                } else {
                    x = p0.x - n0.x * s.chamferInset
                    y = p0.y - n0.y * s.chamferInset
                    n3 = simd_normalize(SIMD3<Float>(n0.x * s.chamferCos, n0.y * s.chamferCos, s.chamferSin))
                }

                positions.append(SIMD3(x, y + centerY, s.z))
                normals.append(n3)
                uvs.append(SIMD2(Float(i) / Float(ringSegs), v))
            }
        }

        for r in 0..<(slices.count - 1) {
            for i in 0..<ringSegs {
                let next = (i + 1) % ringSegs
                let a = Int32(r * ringSegs + i)
                let b = Int32(r * ringSegs + next)
                let d = Int32((r + 1) * ringSegs + i)
                let c = Int32((r + 1) * ringSegs + next)
                indices += [a, b, d, b, c, d]
            }
        }

        // Unwelded flat seam caps with pure (0, 0, ±1) normals so cap edges never bleed into outer bevels
        func appendFlatCap(sliceIndex: Int, z: Float, zNormal: Float) {
            let capNormal = SIMD3<Float>(0, 0, zNormal)
            let centerIdx = Int32(positions.count)
            positions.append(SIMD3(0, centerY, z))
            normals.append(capNormal)
            uvs.append(SIMD2(0.5, 0.5))

            let ringBase = Int32(positions.count)
            let srcStart = sliceIndex * ringSegs
            for i in 0..<ringSegs {
                positions.append(positions[srcStart + i])
                normals.append(capNormal)
                uvs.append(SIMD2(Float(i) / Float(ringSegs), 0))
            }
            for i in 0..<ringSegs {
                let next = (i + 1) % ringSegs
                if zNormal > 0 {
                    indices += [centerIdx, ringBase + Int32(i), ringBase + Int32(next)]
                } else {
                    indices += [centerIdx, ringBase + Int32(next), ringBase + Int32(i)]
                }
            }
        }

        if !roundNegZ {
            appendFlatCap(sliceIndex: 0, z: zMin, zNormal: -1)
        }
        if !roundPosZ {
            appendFlatCap(sliceIndex: slices.count - 1, z: zMax, zNormal: 1)
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

}
