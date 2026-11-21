import SceneKit
import AppKit
import simd

/// Photorealistic procedural 3D models for the Tripowin C8 braided cable + 7Hz Zero:2 IEMs,
/// architect desk lamp, folded boom mic arm, coiled USB-C/Lightning cable,
/// and keyboard USB-C cable.
enum AudioAndLightProps {

    static func build(into root: SCNNode) {
        buildTripowinC8AndZero2(into: root)
        buildDeskLamp(into: root)
        buildBoomMicArm(into: root)
        buildUSBCtoLightningCable(into: root)
        buildKeyboardCable(into: root)
    }

    // MARK: - Shared Mechanical Helpers

    /// Builds a smooth helical tension spring (>= 24 pts/coil) whose end hooks wrap cleanly around
    /// physical cylindrical anchor pins spanning between brackets.
    static func addAnchoredSpring(
        from startPin: SIMD3<Float>,
        to endPin: SIMD3<Float>,
        pinAxis: SIMD3<Float>,
        pinLength: Float,
        pinRadius: Float = 0.052,
        coils: Int = 18,
        coilRadius: Float = 0.135,
        wireRadius: Float = 0.026,
        pointsPerCoil: Int = 24,
        leadFrac: Float = 0.16,
        springMaterial: SCNMaterial,
        pinMaterial: SCNMaterial,
        into parent: SCNNode
    ) {
        let span = endPin - startPin
        let totalLen = simd_length(span)
        guard totalLen > 1e-3 else { return }
        let axis = span / totalLen
        let pAxis = simd_normalize(pinAxis)

        var side1 = simd_cross(axis, pAxis)
        if simd_length(side1) < 1e-4 {
            side1 = simd_cross(axis, abs(axis.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0))
        }
        side1 = simd_normalize(side1)
        let side2 = simd_normalize(simd_cross(side1, axis))

        let hookR = pinRadius + wireRadius * 1.15
        let coilStart = startPin + axis * (totalLen * leadFrac)
        let coilEnd = endPin - axis * (totalLen * leadFrac)
        let coilLen = simd_length(coilEnd - coilStart)

        var pts = [SIMD3<Float>]()
        pts.reserveCapacity(coils * pointsPerCoil + 28)

        // Start hook loop wrapping 270° around startPin in the (axis, side1) plane
        for k in 0...6 {
            let a = -Float.pi * 0.35 + Float(k) / 6.0 * (Float.pi * 1.35)
            pts.append(startPin + (side1 * cos(a) + axis * sin(a)) * hookR)
        }
        pts.append(startPin + axis * (hookR + 0.12) + side1 * (coilRadius * 0.45))

        // Smooth cylindrical helix
        let totalCoilPts = coils * pointsPerCoil
        for i in 0...totalCoilPts {
            let frac = Float(i) / Float(totalCoilPts)
            let ang = frac * Float(coils) * 2 * .pi
            let pos = coilStart + axis * (frac * coilLen) + (side1 * cos(ang) + side2 * sin(ang)) * coilRadius
            pts.append(pos)
        }

        // End hook loop wrapping around endPin
        let endAng = Float(coils) * 2 * .pi
        pts.append(endPin - axis * (hookR + 0.12) + (side1 * cos(endAng) + side2 * sin(endAng)) * (coilRadius * 0.45))
        for k in 0...6 {
            let a = Float.pi + Float(k) / 6.0 * (Float.pi * 1.35)
            pts.append(endPin + (side1 * cos(a) + axis * sin(a)) * hookR)
        }

        let springGeo = MeshBuilder.tube(points: pts, radius: wireRadius, segments: 8)
        springGeo.materials = [springMaterial]
        let springNode = SCNNode(geometry: springGeo)
        springNode.castsShadow = true
        parent.addChildNode(springNode)

        // Physical anchor pins bridging the cheek plates / bracket tabs
        let pinGeo = SCNCylinder(radius: CGFloat(pinRadius), height: CGFloat(pinLength))
        pinGeo.radialSegmentCount = 12
        pinGeo.materials = [pinMaterial]
        let pinOrient = simd_quatf(from: SIMD3(0, 1, 0), to: pAxis)
        for anchor in [startPin, endPin] {
            let pin = SCNNode(geometry: pinGeo)
            pin.simdPosition = anchor
            pin.simdOrientation = pinOrient
            pin.castsShadow = true
            parent.addChildNode(pin)
        }
    }

    /// Routes a power or audio cord smoothly across the walnut desk (`world z >= -25.52`), clamps
    /// out Catmull-Rom vertical overshoot, and drapes it down a 90° quarter-arc at `world z = -25.72`.
    static func addRearEdgeCord(
        worldControl: [SIMD3<Float>],
        radius: Float,
        maxStartY: Float? = nil,
        dropDepth: Float = -2.35,
        material: SCNMaterial,
        into root: SCNNode
    ) {
        var pts = MeshBuilder.catmullRom(worldControl, samplesPerSegment: 7)
        for i in 0..<pts.count {
            var y = max(pts[i].y, radius)
            if let maxY = maxStartY {
                y = min(y, maxY)
            }
            pts[i].y = y
        }

        if let tail = pts.last {
            // Quarter-circle drape from (tail.x, radius, tail.z) down into rear corridor z = -25.72
            let edgeZ: Float = -25.52
            let corridorZ: Float = -25.72
            let arcR = max(0.14, abs(corridorZ - min(tail.z, edgeZ)))
            let startZ = corridorZ + arcR
            if tail.z > startZ + 0.02 {
                pts.append(SIMD3(tail.x, radius, startZ))
            }
            let arcSteps = 5
            for s in 1...arcSteps {
                let theta = Float.pi * 0.5 * (1.0 - Float(s) / Float(arcSteps))
                let az = startZ - arcR * cos(theta)
                let ay = radius - arcR * (1.0 - sin(theta))
                pts.append(SIMD3(tail.x, ay, az))
            }
            pts.append(SIMD3(tail.x, -1.8, corridorZ))
            pts.append(SIMD3(tail.x, dropDepth, corridorZ + 1.15))
        }

        let cordGeo = MeshBuilder.tube(points: pts, radius: radius, segments: 8)
        cordGeo.materials = [material]
        let cordNode = SCNNode(geometry: cordGeo)
        cordNode.castsShadow = true
        root.addChildNode(cordNode)
    }

    // MARK: - Tripowin C8 Braided Cable + 7Hz x Crinacle Zero:2 IEMs

    private static func buildTripowinC8AndZero2(into root: SCNNode) {
        let silverWire = SCNMaterial()
        silverWire.lightingModel = .physicallyBased
        silverWire.diffuse.contents = NSColor(srgbRed: 0.84, green: 0.85, blue: 0.88, alpha: 1)
        silverWire.metalness.contents = 0.94
        silverWire.roughness.contents = 0.16
        silverWire.clearCoat.contents = 0.85
        silverWire.clearCoatRoughness.contents = 0.05

        let copperWire = SCNMaterial()
        copperWire.lightingModel = .physicallyBased
        copperWire.diffuse.contents = NSColor(srgbRed: 0.70, green: 0.41, blue: 0.20, alpha: 1)
        copperWire.metalness.contents = 0.90
        copperWire.roughness.contents = 0.21
        copperWire.clearCoat.contents = 0.70
        copperWire.clearCoatRoughness.contents = 0.08

        let carbonTex = DeskTextures.tripowinCarbon()
        let carbonMat = SCNMaterial()
        carbonMat.lightingModel = .physicallyBased
        carbonMat.diffuse.contents = carbonTex.diffuse
        carbonMat.diffuse.mipFilter = .linear
        carbonMat.diffuse.maxAnisotropy = 8
        carbonMat.normal.contents = carbonTex.normal
        carbonMat.normal.intensity = 0.55
        carbonMat.roughness.contents = 0.20
        carbonMat.metalness.contents = 0.25
        carbonMat.clearCoat.contents = 0.90
        carbonMat.clearCoatRoughness.contents = 0.04

        let gunmetalMat = SCNMaterial()
        gunmetalMat.lightingModel = .physicallyBased
        gunmetalMat.diffuse.contents = NSColor(srgbRed: 0.18, green: 0.19, blue: 0.22, alpha: 1)
        gunmetalMat.metalness.contents = 0.92
        gunmetalMat.roughness.contents = 0.20

        let chromeTrimMat = SCNMaterial()
        chromeTrimMat.lightingModel = .physicallyBased
        chromeTrimMat.diffuse.contents = NSColor(white: 0.84, alpha: 1)
        chromeTrimMat.metalness.contents = 0.96
        chromeTrimMat.roughness.contents = 0.14

        let goldMat = SCNMaterial()
        goldMat.lightingModel = .physicallyBased
        goldMat.diffuse.contents = NSColor(srgbRed: 0.86, green: 0.68, blue: 0.28, alpha: 1)
        goldMat.metalness.contents = 0.96
        goldMat.roughness.contents = 0.16

        let cx: Float = 20.6, cz: Float = -3.6
        let matY = DeskRoomAndMat.matTopY + 0.004
        DeskRoomAndMat.addContactShadow(at: SIMD3(cx, matY, cz), radiusX: 2.8, radiusZ: 2.4, opacity: 0.52, into: root)

        // 1. 3.5 mm stereo plug
        // The 3.5 mm plug is seated in the Mac mini's front headphone jack: the shaft sits inside the port,
        // the collar just clear of the face, and the housing points straight out toward the mat.
        let jack = TechProps.MacMini.jack
        let plugOrigin = jack.position + jack.outward * 0.03
        let plugDir = jack.outward
        let plugYaw = atan2(plugDir.x, plugDir.z)
        func along(_ d: Float) -> SIMD3<Float> { plugOrigin + plugDir * d }

        // Exposed gold-plated 3.5mm TRS shaft + black insulator bands
        let tipPinGeo = SCNCylinder(radius: 0.048, height: 0.48)
        tipPinGeo.materials = [goldMat]
        let tipPin = SCNNode(geometry: tipPinGeo)
        tipPin.simdPosition = along(-0.24)
        tipPin.eulerAngles = SCNVector3(Float.pi / 2, plugYaw, 0)
        tipPin.castsShadow = true
        root.addChildNode(tipPin)

        let trsBandGeo = SCNCylinder(radius: 0.050, height: 0.032)
        trsBandGeo.materials = [carbonMat]
        for td: Float in [-0.36, -0.22] {
            let band = SCNNode(geometry: trsBandGeo)
            band.simdPosition = along(td)
            band.eulerAngles = SCNVector3(Float.pi / 2, plugYaw, 0)
            root.addChildNode(band)
        }

        let collarGeo = SCNCylinder(radius: 0.088, height: 0.10)
        collarGeo.materials = [goldMat]
        let collar = SCNNode(geometry: collarGeo)
        collar.simdPosition = along(0.05)
        collar.eulerAngles = SCNVector3(Float.pi / 2, plugYaw, 0)
        root.addChildNode(collar)

        let frontRingGeo = SCNCylinder(radius: 0.155, height: 0.045)
        frontRingGeo.materials = [chromeTrimMat]
        let frontRing = SCNNode(geometry: frontRingGeo)
        frontRing.simdPosition = along(0.115)
        frontRing.eulerAngles = SCNVector3(Float.pi / 2, plugYaw, 0)
        root.addChildNode(frontRing)

        let housingGeo = SCNCylinder(radius: 0.15, height: 0.65)
        housingGeo.materials = [carbonMat]
        let housing = SCNNode(geometry: housingGeo)
        housing.simdPosition = along(0.46)
        housing.eulerAngles = SCNVector3(Float.pi / 2, plugYaw, 0)
        housing.castsShadow = true
        root.addChildNode(housing)

        let rearRingGeo = SCNCylinder(radius: 0.155, height: 0.045)
        rearRingGeo.materials = [chromeTrimMat]
        let rearRing = SCNNode(geometry: rearRingGeo)
        rearRing.simdPosition = along(0.805)
        rearRing.eulerAngles = SCNVector3(Float.pi / 2, plugYaw, 0)
        root.addChildNode(rearRing)

        let reliefGeo = SCNCone(topRadius: 0.13, bottomRadius: 0.072, height: 0.28)
        reliefGeo.materials = [gunmetalMat]
        let relief = SCNNode(geometry: reliefGeo)
        relief.simdPosition = along(0.96)
        relief.eulerAngles = SCNVector3(Float.pi / 2, plugYaw, 0)
        root.addChildNode(relief)

        // 2. Main 4-core warm copper-bronze braided IEM cable loosely coiled on the right-middle mat (IMG_1867/1868)
        let cableRestY = DeskRoomAndMat.matTopY + 0.065
        // From the plug the cable leaves level, sags under its own weight onto the mat, then runs to the coil.
        let landing = along(3.1)
        var coilCtrl: [SIMD3<Float>] = [
            along(0.92),
            along(1.45) + SIMD3(0, -0.06, 0),
            along(2.2) + SIMD3(0.10, -(plugOrigin.y - cableRestY) * 0.72, 0),
            SIMD3(landing.x + 0.35, cableRestY, landing.z),
            SIMD3(21.45, cableRestY, -5.85),
            SIMD3(22.10, cableRestY, -4.75),
        ]
        let totalSteps = 16
        let turns: Float = 1.25
        for i in 0...totalSteps {
            let t = Float(i) / Float(totalSteps)
            let a = -.pi * 0.35 + t * 2 * .pi * turns
            let rx: Float = 2.15 - 0.38 * t
            let rz: Float = 1.72 - 0.32 * t
            let yLift = cableRestY + 0.008 * max(0, sin(a * 2.0))
            coilCtrl.append(SIMD3(cx + rx * cos(a), yLift, cz + rz * sin(a)))
        }

        // Compute Y-splitter tangent & seat splitter flat on the mat with cable tucked inside rear collar
        let splitTail = coilCtrl[coilCtrl.count - 1]
        let splitPrev = coilCtrl[coilCtrl.count - 2]
        let splitDir = simd_normalize(SIMD3<Float>(splitTail.x - splitPrev.x, 0, splitTail.z - splitPrev.z))
        let splitCenter = SIMD3<Float>(splitTail.x + splitDir.x * 0.30, DeskRoomAndMat.matTopY + 0.145, splitTail.z + splitDir.z * 0.30)
        coilCtrl.append(SIMD3<Float>(splitCenter.x - splitDir.x * 0.14, splitCenter.y, splitCenter.z - splitDir.z * 0.14))

        let mainPts = MeshBuilder.catmullRom(coilCtrl, samplesPerSegment: 5)
        let mainCable = MeshBuilder.braidedCable(
            points: mainPts,
            bundleRadius: 0.052,
            strandRadius: 0.021,
            strands: 4,
            turnsPerUnit: 2.6,
            segments: 5
        )
        mainCable.materials = [copperWire, copperWire]
        let mainNode = SCNNode(geometry: mainCable)
        mainNode.castsShadow = true
        root.addChildNode(mainNode)

        // 3. Y-splitter carbon-fiber barrel with polished silver end rings + inline chin slider
        let splitYaw = atan2(splitDir.x, splitDir.z)
        let splitGroup = SCNNode()
        splitGroup.simdPosition = splitCenter
        splitGroup.eulerAngles.y = CGFloat(splitYaw)
        root.addChildNode(splitGroup)

        let splitter = SCNCylinder(radius: 0.145, height: 0.48)
        splitter.materials = [carbonMat]
        let splitNode = SCNNode(geometry: splitter)
        splitNode.eulerAngles.x = .pi / 2
        splitNode.castsShadow = true
        splitGroup.addChildNode(splitNode)

        let splitRingGeo = SCNCylinder(radius: 0.152, height: 0.04)
        splitRingGeo.materials = [chromeTrimMat]
        for sz: Float in [-0.255, 0.255] {
            let ring = SCNNode(geometry: splitRingGeo)
            ring.eulerAngles.x = .pi / 2
            ring.position = SCNVector3(0, 0, sz)
            splitGroup.addChildNode(ring)
        }

        // Chin slider resting right in front of the splitter so both leads pass cleanly through it
        let sliderPos = splitCenter + splitDir * 0.46
        let slider = SCNCylinder(radius: 0.112, height: 0.18)
        slider.materials = [gunmetalMat]
        let sliderNode = SCNNode(geometry: slider)
        sliderNode.eulerAngles = SCNVector3(Float.pi / 2, splitYaw, 0)
        sliderNode.simdPosition = SIMD3(sliderPos.x, DeskRoomAndMat.matTopY + 0.112, sliderPos.z)
        sliderNode.castsShadow = true
        root.addChildNode(sliderNode)

        // 4. Left and right translucent-cyan 7Hz Salnotes Zero earpieces grounded cleanly beside/below mouse (IMG_1867/1868)
        let leftPin = buildZero2Earphone(at: SIMD3(19.25, DeskRoomAndMat.matTopY, 0.95), yaw: 0.65, mirror: false, into: root)
        let rightPin = buildZero2Earphone(at: SIMD3(21.25, DeskRoomAndMat.matTopY, 0.55), yaw: -1.45, mirror: true, into: root)

        // Thinner 2-core copper braided leads emerging from splitter, threading slider, and curving naturally to earpieces
        let leadStart = SIMD3<Float>(splitCenter.x + splitDir.x * 0.16, DeskRoomAndMat.matTopY + 0.11, splitCenter.z + splitDir.z * 0.16)
        let sliderExit = SIMD3<Float>(sliderPos.x + splitDir.x * 0.10, DeskRoomAndMat.matTopY + 0.08, sliderPos.z + splitDir.z * 0.10)

        // Smooth braided leads exiting slider, curving gently into clear-silver molded ear-hook tubing (no sharp kinks)
        func buildLead(braidVia: [SIMD3<Float>], hookCtrl: [SIMD3<Float>], to pin: (position: SIMD3<Float>, dir: SIMD3<Float>)) -> (braid: [SIMD3<Float>], hook: [SIMD3<Float>]) {
            let hookJoin = hookCtrl[0]
            let fullBraid = MeshBuilder.catmullRom([leadStart, sliderExit] + braidVia + [hookJoin], samplesPerSegment: 6)
            let hookPts = MeshBuilder.catmullRom(hookCtrl + [pin.position - pin.dir * 0.22 + SIMD3(0, 0.03, 0), pin.position], samplesPerSegment: 8)
            return (fullBraid, hookPts)
        }

        let micPrev = SIMD3<Float>(21.92, cableRestY + 0.01, -1.25)
        let micPos = SIMD3<Float>(22.06, cableRestY + 0.03, -0.78)
        let leftLead = buildLead(
            braidVia: [SIMD3(20.15, cableRestY + 0.01, -1.18), SIMD3(19.10, cableRestY + 0.01, -0.60)],
            hookCtrl: [
                SIMD3(18.62, cableRestY + 0.02, -0.05),
                leftPin.position - leftPin.dir * 0.85 + SIMD3(-0.08, 0.06, 0.02),
                leftPin.position - leftPin.dir * 0.48 + SIMD3(0, 0.07, 0),
            ],
            to: leftPin
        )
        let rightLead = buildLead(
            braidVia: [micPrev, micPos],
            hookCtrl: [
                SIMD3(22.24, cableRestY + 0.02, -0.02),
                SIMD3(22.14, cableRestY + 0.06, 0.46),
                rightPin.position - rightPin.dir * 0.52 + SIMD3(0, 0.06, 0),
            ],
            to: rightPin
        )

        let earHookMat = SCNMaterial()
        earHookMat.lightingModel = .physicallyBased
        earHookMat.diffuse.contents = NSColor(srgbRed: 0.86, green: 0.89, blue: 0.92, alpha: 1)
        earHookMat.roughness.contents = 0.18
        earHookMat.metalness.contents = 0.08
        earHookMat.transparency = 0.52
        earHookMat.clearCoat.contents = 0.88
        earHookMat.clearCoatRoughness.contents = 0.08
        earHookMat.transparencyMode = .dualLayer

        let hookCoreMat = SCNMaterial()
        hookCoreMat.lightingModel = .physicallyBased
        hookCoreMat.diffuse.contents = NSColor(srgbRed: 0.80, green: 0.62, blue: 0.44, alpha: 1)
        hookCoreMat.metalness.contents = 0.90
        hookCoreMat.roughness.contents = 0.22

        for pair in [leftLead, rightLead] {
            let cable = MeshBuilder.braidedCable(
                points: pair.braid,
                bundleRadius: 0.036,
                strandRadius: 0.020,
                strands: 4,
                turnsPerUnit: 3.2,
                segments: 5
            )
            cable.materials = [copperWire, copperWire]
            let node = SCNNode(geometry: cable)
            node.castsShadow = true
            root.addChildNode(node)

            let innerCoreGeo = MeshBuilder.tube(points: pair.hook, radius: 0.024, segments: 8)
            innerCoreGeo.materials = [hookCoreMat]
            let innerCoreNode = SCNNode(geometry: innerCoreGeo)
            innerCoreNode.renderingOrder = 2
            root.addChildNode(innerCoreNode)

            let hookGeo = MeshBuilder.tube(points: pair.hook, radius: 0.064, segments: 12)
            hookGeo.materials = [earHookMat]
            let hookNode = SCNNode(geometry: hookGeo)
            hookNode.castsShadow = true
            hookNode.renderingOrder = 5
            root.addChildNode(hookNode)
        }

        // Matte-black cylindrical inline microphone/remote module (matching stock 7Hz Salnotes Zero cable in IMG_1868)
        let micBodyMat = SCNMaterial()
        micBodyMat.lightingModel = .physicallyBased
        micBodyMat.diffuse.contents = NSColor(srgbRed: 0.045, green: 0.047, blue: 0.052, alpha: 1)
        micBodyMat.roughness.contents = 0.56

        let micGroup = SCNNode()
        micGroup.simdPosition = SIMD3(micPos.x, DeskRoomAndMat.matTopY + 0.09, micPos.z)
        let micDir = simd_normalize(SIMD3<Float>(22.24, cableRestY + 0.02, -0.02) - micPrev)
        micGroup.eulerAngles.y = CGFloat(atan2(micDir.x, micDir.z))
        root.addChildNode(micGroup)

        let micBody = MeshBuilder.roundedSlab(width: 0.21, height: 0.16, depth: 0.68, cornerRadius: 0.045, bevel: 0.022)
        micBody.materials = [micBodyMat]
        let micNode = SCNNode(geometry: micBody)
        micNode.position = SCNVector3(0, -0.085, 0)
        micNode.castsShadow = true
        micGroup.addChildNode(micNode)

        let buttonGeo = MeshBuilder.roundedSlab(width: 0.12, height: 0.032, depth: 0.28, cornerRadius: 0.035, bevel: 0.008)
        buttonGeo.materials = [micBodyMat]
        let buttonNode = SCNNode(geometry: buttonGeo)
        buttonNode.position = SCNVector3(0, 0.072, 0)
        micGroup.addChildNode(buttonNode)
    }

    /// 7Hz × Crinacle Zero:2 earpiece lying faceplate-up: deep translucent indigo-sapphire resin shell,
    /// stepped brushed metallic faceplate, recessed copper/gold center vent, visible 10mm dynamic driver,
    /// 0.78 mm 2-pin connector, and grounded angled nozzle + eartip.
    @discardableResult
    private static func buildZero2Earphone(at pos: SIMD3<Float>, yaw: Float, mirror: Bool, into root: SCNNode) -> (position: SIMD3<Float>, dir: SIMD3<Float>) {
        let iem = SCNNode()
        iem.simdPosition = pos
        iem.eulerAngles.y = CGFloat(yaw)
        if mirror { iem.scale.x = -1 }
        root.addChildNode(iem)

        // Child body holds tilted/inverted pose for the right earpiece (IMG_1868: aqua belly, eartip & red-ring plug visible).
        let body = SCNNode()
        if mirror {
            body.position = SCNVector3(0, 0.52, 0)
            body.eulerAngles = SCNVector3(0.18, 0, 2.38)
        }
        iem.addChildNode(body)

        // Translucent bright cyan-turquoise Zero:2 resin shell (IMG_1868)
        let shellMat = SCNMaterial()
        shellMat.lightingModel = .physicallyBased
        shellMat.diffuse.contents = NSColor(srgbRed: 0.04, green: 0.78, blue: 0.92, alpha: 1)
        shellMat.roughness.contents = 0.06
        shellMat.transparency = 0.62
        shellMat.clearCoat.contents = 1.0
        shellMat.clearCoatRoughness.contents = 0.025
        shellMat.fresnelExponent = 2.2
        shellMat.transparencyMode = .dualLayer
        shellMat.isDoubleSided = false

        let fpTex = DeskTextures.zero2Faceplate()
        let plateMat = SCNMaterial()
        plateMat.lightingModel = .physicallyBased
        plateMat.diffuse.contents = fpTex.diffuse
        plateMat.diffuse.mipFilter = .linear
        plateMat.normal.contents = fpTex.normal
        plateMat.normal.intensity = 0.65
        plateMat.metalness.contents = fpTex.metalness
        plateMat.roughness.contents = 0.28
        plateMat.clearCoat.contents = 0.75
        plateMat.clearCoatRoughness.contents = 0.06

        let steel = SCNMaterial()
        steel.lightingModel = .physicallyBased
        steel.diffuse.contents = NSColor(white: 0.80, alpha: 1)
        steel.metalness.contents = 0.96
        steel.roughness.contents = 0.20

        let brassRingMat = SCNMaterial()
        brassRingMat.lightingModel = .physicallyBased
        brassRingMat.diffuse.contents = NSColor(srgbRed: 0.82, green: 0.55, blue: 0.24, alpha: 1)
        brassRingMat.metalness.contents = 0.95
        brassRingMat.roughness.contents = 0.20

        let leadWireMat = SCNMaterial()
        leadWireMat.lightingModel = .physicallyBased
        leadWireMat.diffuse.contents = NSColor(srgbRed: 0.80, green: 0.42, blue: 0.20, alpha: 1)
        leadWireMat.metalness.contents = 0.92
        leadWireMat.roughness.contents = 0.24

        let tipMat = SCNMaterial()
        tipMat.lightingModel = .physicallyBased
        tipMat.diffuse.contents = NSColor(srgbRed: 0.05, green: 0.055, blue: 0.06, alpha: 1)
        tipMat.roughness.contents = 0.62

        let darkMat = SCNMaterial()
        darkMat.lightingModel = .physicallyBased
        darkMat.diffuse.contents = NSColor(white: 0.055, alpha: 1)
        darkMat.roughness.contents = 0.48

        let meshCenterMat = SCNMaterial()
        meshCenterMat.lightingModel = .physicallyBased
        meshCenterMat.diffuse.contents = NSColor(white: 0.04, alpha: 1)
        meshCenterMat.metalness.contents = 0.35
        meshCenterMat.roughness.contents = 0.68

        let outline: [CGPoint] = [
            CGPoint(x: -0.48, y: -0.06),
            CGPoint(x: -0.26, y: -0.44),
            CGPoint(x:  0.22, y: -0.46),
            CGPoint(x:  0.52, y: -0.14),
            CGPoint(x:  0.44, y:  0.24),
            CGPoint(x:  0.04, y:  0.46),
            CGPoint(x: -0.42, y:  0.34),
        ]

        func facetedPath(_ scale: CGFloat, cornerFillet: CGFloat) -> NSBezierPath {
            let p = outline.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
            let n = p.count
            let path = NSBezierPath()
            let start = CGPoint(x: (p[n - 1].x + p[0].x) * 0.5, y: (p[n - 1].y + p[0].y) * 0.5)
            path.move(to: start)
            for i in 0..<n {
                path.appendArc(from: p[i], to: p[(i + 1) % n], radius: cornerFillet * scale)
            }
            path.close()
            path.flatness = 0.004
            return path
        }

        let roundEdge: NSBezierPath = {
            let e = NSBezierPath()
            e.move(to: NSPoint(x: 0, y: 1))
            e.curve(to: NSPoint(x: 1, y: 0), controlPoint1: NSPoint(x: 0.55, y: 1), controlPoint2: NSPoint(x: 1, y: 0.55))
            return e
        }()

        func facetedSlab(_ scale: CGFloat, depth: CGFloat, chamfer: CGFloat, fillet: CGFloat) -> SCNShape {
            let shape = SCNShape(path: facetedPath(scale, cornerFillet: fillet), extrusionDepth: depth)
            shape.chamferRadius = chamfer
            shape.chamferProfile = roundEdge
            shape.chamferMode = .both
            return shape
        }

        // Translucent aqua-cyan resin cavity shell (y = 0..0.50)
        let shell = facetedSlab(1.0, depth: 0.50, chamfer: 0.14, fillet: 0.055)
        shell.materials = [shellMat]
        let shellNode = SCNNode(geometry: shell)
        shellNode.eulerAngles.x = -.pi / 2
        shellNode.position = SCNVector3(0, 0.25, 0)
        shellNode.castsShadow = true
        shellNode.renderingOrder = 5
        body.addChildNode(shellNode)

        // Internal cyan-turquoise acoustic chamber reflector so refracted light glows bright turquoise inside the shell
        let cyanCoreMat = SCNMaterial()
        cyanCoreMat.lightingModel = .physicallyBased
        cyanCoreMat.diffuse.contents = NSColor(srgbRed: 0.05, green: 0.72, blue: 0.88, alpha: 1)
        cyanCoreMat.roughness.contents = 0.34
        let cyanBaffle = SCNCylinder(radius: 0.34, height: 0.06)
        cyanBaffle.materials = [cyanCoreMat]
        let baffleNode = SCNNode(geometry: cyanBaffle)
        baffleNode.simdPosition = SIMD3(0.02, 0.11, 0.01)
        baffleNode.renderingOrder = 1
        body.addChildNode(baffleNode)

        // Visible 10mm dynamic driver inside cavity
        let driverCenter = SIMD3<Float>(0.04, 0.22, 0.02)
        let driverBody = SCNCylinder(radius: 0.22, height: 0.10)
        driverBody.materials = [steel]
        let driverNode = SCNNode(geometry: driverBody)
        driverNode.simdPosition = driverCenter
        driverNode.renderingOrder = 2
        body.addChildNode(driverNode)

        let driverBrassRing = SCNTorus(ringRadius: 0.23, pipeRadius: 0.022)
        driverBrassRing.materials = [brassRingMat]
        let ringNode = SCNNode(geometry: driverBrassRing)
        ringNode.simdPosition = driverCenter + SIMD3(0, 0.02, 0)
        ringNode.renderingOrder = 2
        body.addChildNode(ringNode)

        let driverMagnet = SCNCylinder(radius: 0.13, height: 0.04)
        driverMagnet.materials = [steel]
        let magNode = SCNNode(geometry: driverMagnet)
        magNode.simdPosition = driverCenter + SIMD3(0, -0.06, 0)
        magNode.renderingOrder = 2
        body.addChildNode(magNode)

        let socketLocal = SIMD3<Float>(-0.20, 0.38, -0.36)
        for (idx, dx) in [Float(-0.04), Float(0.04)].enumerated() {
            let wPts = MeshBuilder.catmullRom([
                socketLocal + SIMD3(dx, -0.04, 0.06),
                SIMD3(socketLocal.x + dx * 1.4, 0.30, -0.18),
                driverCenter + SIMD3(dx * 1.8 - 0.03, 0.03, -0.08),
            ], samplesPerSegment: 4)
            let wGeo = MeshBuilder.tube(points: wPts, radius: 0.012, segments: 5)
            wGeo.materials = [idx == 0 ? leadWireMat : steel]
            let wNode = SCNNode(geometry: wGeo)
            wNode.renderingOrder = 2
            body.addChildNode(wNode)
        }

        // Inset brushed-silver faceplate sitting cleanly inside thick glowing aqua resin perimeter rim (IMG_1868)
        let basePlate = facetedSlab(0.78, depth: 0.042, chamfer: 0.015, fillet: 0.045)
        basePlate.materials = [plateMat]
        let basePlateNode = SCNNode(geometry: basePlate)
        basePlateNode.eulerAngles.x = -.pi / 2
        basePlateNode.position = SCNVector3(0, 0.520, 0)
        body.addChildNode(basePlateNode)

        let topPlate = facetedSlab(0.66, depth: 0.044, chamfer: 0.016, fillet: 0.035)
        topPlate.materials = [plateMat]
        let topPlateNode = SCNNode(geometry: topPlate)
        topPlateNode.eulerAngles.x = -.pi / 2
        topPlateNode.position = SCNVector3(0.01, 0.556, -0.005)
        body.addChildNode(topPlateNode)

        // Small stainless center pinhole vent accent (no brass ring on real stainless Zero faceplate)
        let ventCenter = SIMD3<Float>(0.02, 0.580, -0.01)
        let ventMesh = SCNCylinder(radius: 0.055, height: 0.014)
        ventMesh.materials = [steel]
        let ventMeshNode = SCNNode(geometry: ventMesh)
        ventMeshNode.simdPosition = ventCenter + SIMD3(0, -0.002, 0)
        body.addChildNode(ventMeshNode)

        // 0.78mm 2-pin brushed silver connector barrel + bright crimson-red right collar band (IMG_1868)
        let socket = SCNBox(width: 0.22, height: 0.13, length: 0.13, chamferRadius: 0.025)
        socket.materials = [shellMat]
        let sockNode = SCNNode(geometry: socket)
        sockNode.simdPosition = socketLocal
        sockNode.renderingOrder = 5
        body.addChildNode(sockNode)

        let pinGeo = SCNCylinder(radius: 0.016, height: 0.09)
        pinGeo.materials = [steel]
        for px: Float in [-0.038, 0.038] {
            let pNode = SCNNode(geometry: pinGeo)
            pNode.eulerAngles.x = .pi / 2
            pNode.simdPosition = socketLocal + SIMD3(px, 0.01, -0.08)
            body.addChildNode(pNode)
        }

        if mirror {
            let redRingMat = SCNMaterial()
            redRingMat.lightingModel = .physicallyBased
            redRingMat.diffuse.contents = NSColor(srgbRed: 0.90, green: 0.07, blue: 0.08, alpha: 1)
            redRingMat.metalness.contents = 0.72
            redRingMat.roughness.contents = 0.22
            let redCollar = SCNBox(width: 0.19, height: 0.14, length: 0.085, chamferRadius: 0.030)
            redCollar.materials = [redRingMat]
            let rcNode = SCNNode(geometry: redCollar)
            rcNode.simdPosition = socketLocal + SIMD3(0, 0.015, -0.115)
            body.addChildNode(rcNode)
        }

        let plug = SCNBox(width: 0.16, height: 0.11, length: 0.24, chamferRadius: 0.035)
        plug.materials = [steel]
        let plugNode = SCNNode(geometry: plug)
        plugNode.simdPosition = socketLocal + SIMD3(0, 0.015, -0.21)
        body.addChildNode(plugNode)

        // Angled stainless-steel acoustic nozzle & silicone eartip seated cleanly above y = 0.01
        let nozzleProfile: [(r: Float, y: Float)] = [
            (0.125, 0.0), (0.105, 0.08), (0.095, 0.26), (0.112, 0.30), (0.105, 0.34), (0.075, 0.34), (0.075, 0.26)
        ]
        let nozzle = MeshBuilder.lathe(profile: nozzleProfile, segments: 20)
        nozzle.materials = [steel]
        let nNode = SCNNode(geometry: nozzle)
        nNode.position = SCNVector3(0.45, 0.27, 0.20)
        nNode.eulerAngles = SCNVector3(0.28, 0, -0.92)
        body.addChildNode(nNode)

        let nozzleMesh = SCNCylinder(radius: 0.074, height: 0.012)
        nozzleMesh.materials = [meshCenterMat]
        let nmNode = SCNNode(geometry: nozzleMesh)
        nmNode.position = SCNVector3(0.71, 0.14, 0.28)
        nmNode.eulerAngles = SCNVector3(0.28, 0, -0.92)
        body.addChildNode(nmNode)

        let tipProfile: [(r: Float, y: Float)] = [
            (0.09, 0.0), (0.24, 0.05), (0.25, 0.18), (0.17, 0.28), (0.09, 0.28), (0.09, 0.03),
        ]
        let tipGeo = MeshBuilder.lathe(profile: tipProfile, segments: 24)
        tipGeo.materials = [tipMat]
        let tipNode = SCNNode(geometry: tipGeo)
        tipNode.position = SCNVector3(0.61, 0.19, 0.26)
        tipNode.eulerAngles = SCNVector3(0.28, 0, -0.92)
        tipNode.castsShadow = true
        body.addChildNode(tipNode)

        // Tuck lead entry slightly inside the 2-pin plug housing so open strand ends are sealed
        let entryLocal = socketLocal + SIMD3(0, 0.015, -0.26)
        let m = body.simdWorldTransform
        let world = m * SIMD4(entryLocal, 1)
        let d4 = m * SIMD4<Float>(0, 0, 1, 0)
        let inward = simd_normalize(SIMD3(d4.x, d4.y, d4.z))
        return (SIMD3(world.x, world.y, world.z), inward)
    }

}
