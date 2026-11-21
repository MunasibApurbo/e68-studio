import SceneKit
import AppKit
import simd

extension AudioAndLightProps {
    // MARK: - Folded Articulated Boom Mic Arm

    static func buildBoomMicArm(into root: SCNNode) {
        // Rear-edge C-clamp anchored flush onto desk rear lip (world z = -25.60, wall at -25.88)
        let clampOrigin = SIMD3<Float>(35.6, 0.0, -25.60)
        let clampNode = SCNNode()
        clampNode.simdPosition = clampOrigin
        root.addChildNode(clampNode)

        let swivelOffset = SIMD3<Float>(0, 0, 0.70)
        // Yaw +0.98 rad aims local -X diagonally forward-left over the corner toward front-left of the green jar.
        let swivelYaw: Float = 0.98
        let swivelOrigin = clampOrigin + swivelOffset
        let swivelOrient = simd_quatf(angle: swivelYaw, axis: SIMD3<Float>(0, 1, 0))
        func toWorld(_ local: SIMD3<Float>) -> SIMD3<Float> {
            swivelOrigin + simd_act(swivelOrient, local)
        }

        let swivel = SCNNode()
        swivel.simdPosition = swivelOffset
        swivel.eulerAngles.y = CGFloat(swivelYaw)
        clampNode.addChildNode(swivel)

        let powderBlack = SCNMaterial()
        powderBlack.lightingModel = .physicallyBased
        powderBlack.diffuse.contents = NSColor(srgbRed: 0.045, green: 0.047, blue: 0.052, alpha: 1)
        powderBlack.metalness.contents = 0.28
        powderBlack.roughness.contents = 0.46

        let darkSpringSteel = SCNMaterial()
        darkSpringSteel.lightingModel = .physicallyBased
        darkSpringSteel.diffuse.contents = NSColor(srgbRed: 0.075, green: 0.080, blue: 0.088, alpha: 1)
        darkSpringSteel.metalness.contents = 0.78
        darkSpringSteel.roughness.contents = 0.32

        let brushedSteel = SCNMaterial()
        brushedSteel.lightingModel = .physicallyBased
        brushedSteel.diffuse.contents = NSColor(white: 0.72, alpha: 1)
        brushedSteel.metalness.contents = 0.90
        brushedSteel.roughness.contents = 0.24

        let brassThread = SCNMaterial()
        brassThread.lightingModel = .physicallyBased
        brassThread.diffuse.contents = NSColor(srgbRed: 0.74, green: 0.60, blue: 0.30, alpha: 1)
        brassThread.metalness.contents = 0.90
        brassThread.roughness.contents = 0.26

        let rubberMat = SCNMaterial()
        rubberMat.lightingModel = .physicallyBased
        rubberMat.diffuse.contents = NSColor(srgbRed: 0.036, green: 0.038, blue: 0.042, alpha: 1)
        rubberMat.roughness.contents = 0.68
        rubberMat.metalness.contents = 0.02

        DeskRoomAndMat.addContactShadow(at: SIMD3(swivelOrigin.x, 0.005, swivelOrigin.z), radiusX: 1.5, radiusZ: 1.4, opacity: 0.62, into: root)

        // 1. Rear-edge C-clamp gripping top (y = 0), rear edge (z = -25.60), and desk underside (y = -1.40)
        // Rear spine fits inside [-25.82, -25.60], keeping clear of wall face (-25.88)
        let padGeo = MeshBuilder.roundedSlab(width: 1.66, height: 0.03, depth: 1.88, cornerRadius: 0.14, bevel: 0.008)
        padGeo.materials = [rubberMat]
        let padNode = SCNNode(geometry: padGeo)
        padNode.position = SCNVector3(0, 0.0, 0.72)
        clampNode.addChildNode(padNode)

        let topJawGeo = MeshBuilder.roundedSlab(width: 1.62, height: 0.28, depth: 1.84, cornerRadius: 0.14, bevel: 0.03)
        topJawGeo.materials = [powderBlack]
        let topJawNode = SCNNode(geometry: topJawGeo)
        topJawNode.position = SCNVector3(0, 0.03, 0.70)
        topJawNode.castsShadow = true
        clampNode.addChildNode(topJawNode)

        let spineGeo = MeshBuilder.roundedSlab(width: 1.62, height: 2.40, depth: 0.22, cornerRadius: 0.06, bevel: 0.025)
        spineGeo.materials = [powderBlack]
        let spineNode = SCNNode(geometry: spineGeo)
        spineNode.position = SCNVector3(0, -2.09, -0.11)
        spineNode.castsShadow = true
        clampNode.addChildNode(spineNode)

        let botJawGeo = MeshBuilder.roundedSlab(width: 1.62, height: 0.24, depth: 1.72, cornerRadius: 0.12, bevel: 0.03)
        botJawGeo.materials = [powderBlack]
        let botJawNode = SCNNode(geometry: botJawGeo)
        botJawNode.position = SCNVector3(0, -2.09, 0.64)
        botJawNode.castsShadow = true
        clampNode.addChildNode(botJawNode)

        let clampScrew = SCNCylinder(radius: 0.10, height: 1.04)
        clampScrew.materials = [brushedSteel]
        let csNode = SCNNode(geometry: clampScrew)
        csNode.position = SCNVector3(0, -1.96, 0.86)
        clampNode.addChildNode(csNode)

        let puckGeo = SCNCylinder(radius: 0.34, height: 0.09)
        puckGeo.materials = [rubberMat]
        let puckNode = SCNNode(geometry: puckGeo)
        puckNode.position = SCNVector3(0, -1.445, 0.86)
        clampNode.addChildNode(puckNode)

        let tBarGeo = SCNBox(width: 0.90, height: 0.11, length: 0.11, chamferRadius: 0.04)
        tBarGeo.materials = [powderBlack]
        let tBarNode = SCNNode(geometry: tBarGeo)
        tBarNode.position = SCNVector3(0, -2.48, 0.86)
        clampNode.addChildNode(tBarNode)

        // Swivel turret & locking thumbscrew positioned cleanly on top jaw
        let collarGeo = SCNCylinder(radius: 0.58, height: 0.12)
        collarGeo.materials = [powderBlack]
        let collarNode = SCNNode(geometry: collarGeo)
        collarNode.position = SCNVector3(0.22, 0.35, 0)
        collarNode.castsShadow = true
        swivel.addChildNode(collarNode)

        let turretGeo = SCNCylinder(radius: 0.46, height: 0.88)
        turretGeo.materials = [powderBlack]
        let turretNode = SCNNode(geometry: turretGeo)
        turretNode.position = SCNVector3(0.22, 0.79, 0)
        turretNode.castsShadow = true
        swivel.addChildNode(turretNode)

        let lockShaft = SCNCylinder(radius: 0.085, height: 0.44)
        lockShaft.materials = [brushedSteel]
        let lockShaftNode = SCNNode(geometry: lockShaft)
        lockShaftNode.eulerAngles.z = .pi / 2
        lockShaftNode.position = SCNVector3(0.84, 0.86, 0)
        swivel.addChildNode(lockShaftNode)

        let lockKnob = SCNCylinder(radius: 0.20, height: 0.20)
        lockKnob.materials = [powderBlack]
        let lockKnobNode = SCNNode(geometry: lockKnob)
        lockKnobNode.eulerAngles.z = .pi / 2
        lockKnobNode.position = SCNVector3(1.08, 0.86, 0)
        lockKnobNode.castsShadow = true
        swivel.addChildNode(lockKnobNode)

        func segmentFrame(from a: SIMD3<Float>, to b: SIMD3<Float>) -> (mid: SIMD3<Float>, len: Float, xAxis: SIMD3<Float>, yAxis: SIMD3<Float>, zAxis: SIMD3<Float>, orient: simd_quatf) {
            let v = b - a
            let len = simd_length(v)
            let yAxis = v / max(len, 1e-5)
            var xAxis = simd_cross(yAxis, SIMD3<Float>(0, 0, 1))
            if simd_length(xAxis) < 1e-4 {
                xAxis = SIMD3<Float>(1, 0, 0)
            } else {
                xAxis = simd_normalize(xAxis)
            }
            let zAxis = simd_normalize(simd_cross(xAxis, yAxis))
            let orient = simd_quatf(simd_float3x3(xAxis, yAxis, zAxis))
            return ((a + b) * 0.5, len, xAxis, yAxis, zAxis, orient)
        }

        // 2. Angled scissor geometry matching IMG_1867: lower twin-bar rises steeply from corner clamp,
        // upper twin-bar section angles sharply down in front-left of the green pickle jar.
        let pBase = SIMD3<Float>(0.22, 1.58, 0)
        let pElbow = SIMD3<Float>(-3.80, 16.60, 0)
        let pFoldStart = SIMD3<Float>(-4.20, 16.60, 0)
        let pFoldEnd = SIMD3<Float>(-14.20, 5.65, 0)
        let lowerFrame = segmentFrame(from: pBase, to: pElbow)

        let basePlate = MeshBuilder.roundedSlab(width: 0.82, height: 1.05, depth: 0.06, cornerRadius: 0.14, bevel: 0.015)
        basePlate.materials = [powderBlack]
        for bz: Float in [-0.13, 0.13] {
            let plate = SCNNode(geometry: basePlate)
            plate.simdPosition = pBase + SIMD3(0, -0.54, bz)
            plate.castsShadow = true
            swivel.addChildNode(plate)
        }

        // Top folding hinge clevis bridging lower scissor to collapsed upper boom cleanly
        let hingeCenter = (pElbow + pFoldStart) * 0.5
        let hingePlate = MeshBuilder.roundedSlab(width: 1.12, height: 0.82, depth: 0.065, cornerRadius: 0.16, bevel: 0.016)
        hingePlate.materials = [powderBlack]
        for bz: Float in [-0.15, 0.15] {
            let plate = SCNNode(geometry: hingePlate)
            plate.simdPosition = hingeCenter + SIMD3(0, -0.40, bz)
            plate.castsShadow = true
            swivel.addChildNode(plate)
        }

        let elbowKnob = SCNCylinder(radius: 0.22, height: 0.16)
        elbowKnob.materials = [powderBlack]
        let ekNode = SCNNode(geometry: elbowKnob)
        ekNode.eulerAngles.x = .pi / 2
        ekNode.simdPosition = pFoldStart + SIMD3(0, 0, 0.26)
        swivel.addChildNode(ekNode)

        let rivetGeo = SCNCylinder(radius: 0.12, height: 0.36)
        rivetGeo.materials = [brushedSteel]
        for pivot in [pBase, pElbow, pFoldStart] {
            let rivet = SCNNode(geometry: rivetGeo)
            rivet.eulerAngles.x = .pi / 2
            rivet.simdPosition = pivot
            swivel.addChildNode(rivet)
        }

        let lowerBarGeo = SCNBox(width: 0.14, height: CGFloat(lowerFrame.len), length: 0.16, chamferRadius: 0.025)
        lowerBarGeo.materials = [powderBlack]
        for side: Float in [-1, 1] {
            let bar = SCNNode(geometry: lowerBarGeo)
            bar.simdPosition = lowerFrame.mid + lowerFrame.xAxis * (side * 0.22)
            bar.simdOrientation = lowerFrame.orient
            bar.castsShadow = true
            swivel.addChildNode(bar)
        }

        let tieGeo = SCNCylinder(radius: 0.072, height: 0.52)
        tieGeo.materials = [powderBlack]
        let tieOrient = simd_quatf(from: SIMD3(0, 1, 0), to: lowerFrame.xAxis)
        for frac: Float in [0.10, 0.90] {
            let tie = SCNNode(geometry: tieGeo)
            tie.simdPosition = pBase + lowerFrame.yAxis * (lowerFrame.len * frac)
            tie.simdOrientation = tieOrient
            swivel.addChildNode(tie)
        }

        // 3. Smooth helical springs on front & back bridging lower scissor bars
        let springLowBase = pBase + lowerFrame.yAxis * (lowerFrame.len * 0.18)
        let springHighBase = pBase + lowerFrame.yAxis * (lowerFrame.len * 0.78)
        let lugGeo = MeshBuilder.roundedSlab(width: 0.09, height: 0.22, depth: 0.22, cornerRadius: 0.03, bevel: 0.01)
        lugGeo.materials = [powderBlack]
        for sz: Float in [-0.24, 0.24] {
            let sLow = springLowBase + lowerFrame.zAxis * sz
            let sHigh = springHighBase + lowerFrame.zAxis * sz
            for anchor in [sLow, sHigh] {
                for side: Float in [-1, 1] {
                    let lug = SCNNode(geometry: lugGeo)
                    lug.simdPosition = anchor + lowerFrame.xAxis * (side * 0.22) - lowerFrame.zAxis * (sz * 0.42) - lowerFrame.yAxis * 0.11
                    lug.simdOrientation = lowerFrame.orient
                    swivel.addChildNode(lug)
                }
            }
            addAnchoredSpring(
                from: sLow,
                to: sHigh,
                pinAxis: lowerFrame.xAxis,
                pinLength: 0.52,
                pinRadius: 0.046,
                coils: 26,
                coilRadius: 0.105,
                wireRadius: 0.025,
                pointsPerCoil: 24,
                leadFrac: 0.08,
                springMaterial: darkSpringSteel,
                pinMaterial: brushedSteel,
                into: swivel
            )
        }

        // 4. Angled twin-bar upper scissor section + dual external springs + open-cage shock mount & foam mic (IMG_1865/1866)
        let upperFrame = segmentFrame(from: pFoldStart, to: pFoldEnd)
        let upperBarGeo = SCNBox(width: 0.12, height: CGFloat(upperFrame.len), length: 0.22, chamferRadius: 0.025)
        upperBarGeo.materials = [powderBlack]
        for s: Float in [-0.20, 0.20] {
            let ubNode = SCNNode(geometry: upperBarGeo)
            ubNode.simdPosition = upperFrame.mid + upperFrame.xAxis * s
            ubNode.simdOrientation = upperFrame.orient
            ubNode.castsShadow = true
            swivel.addChildNode(ubNode)
        }

        // Dual external front & back coil springs on the upper scissor arm (mirroring real arm flanks)
        let upperPinA = pFoldStart + upperFrame.yAxis * 0.52 + upperFrame.xAxis * 0.04
        let upperPinB = pFoldStart + upperFrame.yAxis * (upperFrame.len * 0.48) + upperFrame.xAxis * 0.04
        for sz: Float in [-0.24, 0.24] {
            let sA = upperPinA + upperFrame.zAxis * sz
            let sB = upperPinB + upperFrame.zAxis * sz
            for anchor in [sA, sB] {
                for side: Float in [-1, 1] {
                    let uLug = SCNNode(geometry: lugGeo)
                    uLug.simdPosition = anchor + upperFrame.xAxis * (side * 0.20) - upperFrame.zAxis * (sz * 0.42)
                    uLug.simdOrientation = upperFrame.orient
                    swivel.addChildNode(uLug)
                }
            }
            addAnchoredSpring(
                from: sA,
                to: sB,
                pinAxis: upperFrame.xAxis,
                pinLength: 0.50,
                pinRadius: 0.044,
                coils: 22,
                coilRadius: 0.102,
                wireRadius: 0.023,
                pointsPerCoil: 20,
                leadFrac: 0.08,
                springMaterial: darkSpringSteel,
                pinMaterial: brushedSteel,
                into: swivel
            )
        }

        // Knuckle clamp, knurled black ring & silver 5/8" mounting stud hanging open-cage mic holder
        let micKnuckle = SCNCylinder(radius: 0.20, height: 0.34)
        micKnuckle.materials = [powderBlack]
        let mkNode = SCNNode(geometry: micKnuckle)
        mkNode.eulerAngles.x = .pi / 2
        mkNode.simdPosition = pFoldEnd
        mkNode.castsShadow = true
        swivel.addChildNode(mkNode)

        let lockCollar = SCNCylinder(radius: 0.20, height: 0.11)
        lockCollar.materials = [powderBlack]
        let lcNode = SCNNode(geometry: lockCollar)
        lcNode.simdPosition = pFoldEnd + SIMD3(0, -0.24, 0)
        swivel.addChildNode(lcNode)

        let micStud = SCNCylinder(radius: 0.11, height: 0.42)
        micStud.materials = [brushedSteel]
        let msNode = SCNNode(geometry: micStud)
        msNode.simdPosition = pFoldEnd + SIMD3(0, -0.44, 0)
        swivel.addChildNode(msNode)

        // Open-cage cylindrical shock mount holder + black foam-windscreen lavalier/capsule mic (IMG_1865/1866)
        // 5. Silver chrome threaded spindle + empty hollow matte-black open-cage mic clip holder (IMG_1867)
        let holderOffset = SIMD3<Float>(-0.52, -1.15, 0)
        let holderMount = SCNNode()
        holderMount.simdPosition = pFoldEnd + holderOffset
        holderMount.eulerAngles = SCNVector3(0, 0, 0.36)
        swivel.addChildNode(holderMount)

        let spindlePts = [
            pFoldEnd + SIMD3(-0.04, -0.08, 0),
            pFoldEnd + holderOffset * 0.56,
        ]
        let spindleGeo = MeshBuilder.tube(points: spindlePts, radius: 0.145, segments: 12)
        spindleGeo.materials = [brushedSteel]
        let spindleNode = SCNNode(geometry: spindleGeo)
        spindleNode.castsShadow = true
        swivel.addChildNode(spindleNode)

        let cageR: Float = 0.54
        let cageH: Float = 1.38
        let topCollar = SCNTorus(ringRadius: CGFloat(cageR), pipeRadius: 0.075)
        topCollar.materials = [powderBlack]
        let topCollarNode = SCNNode(geometry: topCollar)
        topCollarNode.position = SCNVector3(0, cageH * 0.5, 0)
        topCollarNode.castsShadow = true
        holderMount.addChildNode(topCollarNode)

        let botCollar = SCNTorus(ringRadius: CGFloat(cageR), pipeRadius: 0.075)
        botCollar.materials = [powderBlack]
        let botCollarNode = SCNNode(geometry: botCollar)
        botCollarNode.position = SCNVector3(0, -cageH * 0.5, 0)
        botCollarNode.castsShadow = true
        holderMount.addChildNode(botCollarNode)

        let stemCollar = SCNCylinder(radius: 0.21, height: 0.34)
        stemCollar.materials = [powderBlack]
        let stemCollarNode = SCNNode(geometry: stemCollar)
        stemCollarNode.position = SCNVector3(0, cageH * 0.5 + 0.16, 0)
        holderMount.addChildNode(stemCollarNode)

        // Four narrow curved vertical ribs leaving wide see-through open clip cage
        let ribGeo = SCNBox(width: 0.14, height: CGFloat(cageH), length: 0.10, chamferRadius: 0.03)
        ribGeo.materials = [powderBlack]
        for angleDeg: Float in [-55, 55, 130, 230] {
            let rad = angleDeg * .pi / 180
            let rib = SCNNode(geometry: ribGeo)
            rib.position = SCNVector3(cos(rad) * cageR, 0, sin(rad) * cageR)
            rib.eulerAngles.y = CGFloat(-rad)
            rib.castsShadow = true
            holderMount.addChildNode(rib)
        }

        let micCordOrigin = pFoldEnd + SIMD3<Float>(-0.08, -0.25, 0.10)
        let xlrPlugPos = micCordOrigin

        let clipGeo = SCNBox(width: 0.40, height: 0.17, length: 0.26, chamferRadius: 0.04)
        clipGeo.materials = [rubberMat]
        for frac: Float in [0.32, 0.70] {
            let uClip = SCNNode(geometry: clipGeo)
            uClip.simdPosition = pFoldStart + upperFrame.yAxis * (upperFrame.len * frac) + upperFrame.xAxis * 0.11
            uClip.simdOrientation = upperFrame.orient
            swivel.addChildNode(uClip)

            let lClip = SCNNode(geometry: clipGeo)
            lClip.simdPosition = pBase + lowerFrame.yAxis * (lowerFrame.len * frac) + lowerFrame.xAxis * 0.28
            lClip.simdOrientation = lowerFrame.orient
            swivel.addChildNode(lClip)
        }

        let xlrR: Float = 0.065
        let xlrLocalCtrl: [SIMD3<Float>] = [
            xlrPlugPos - upperFrame.yAxis * 0.28,
            pFoldStart + upperFrame.yAxis * (upperFrame.len * 0.70) + upperFrame.xAxis * 0.26,
            pFoldStart + upperFrame.yAxis * (upperFrame.len * 0.32) + upperFrame.xAxis * 0.26,
            pFoldStart + SIMD3(-0.22, 0.36, 0.06),
            hingeCenter + SIMD3(0, 0.62, 0.04),
            pElbow + SIMD3(0.42, 0.34, 0.02),
            pBase + lowerFrame.yAxis * (lowerFrame.len * 0.70) + lowerFrame.xAxis * 0.42,
            pBase + lowerFrame.yAxis * (lowerFrame.len * 0.32) + lowerFrame.xAxis * 0.42,
            SIMD3(0.68, 1.35, -0.06),
        ]
        var xlrWorldCtrl = xlrLocalCtrl.map(toWorld)
        // Route cleanly around right side of rear C-clamp top jaw (max x = 36.41) before draping off edge
        xlrWorldCtrl.append(contentsOf: [
            SIMD3<Float>(36.58, 0.48, -24.98),
            SIMD3<Float>(36.62, xlrR, -25.26),
            SIMD3<Float>(36.62, xlrR, -25.52),
        ])
        addRearEdgeCord(
            worldControl: xlrWorldCtrl,
            radius: xlrR,
            material: rubberMat,
            into: root
        )
    }

    // MARK: - Coiled Braided USB-C to Lightning Cable

    private enum CablePlugKind { case usbC, lightning }

    static func buildUSBCtoLightningCable(into root: SCNNode) {
        // Coiled matte-black BOROFONE braided USB-C cable resting cleanly right of desk mat (IMG_1864-1867)
        let center = SIMD3<Float>(33.0, 0.0, -9.8)
        let cableRadius: Float = 0.092
        let coilTilt: Float = -0.16

        DeskRoomAndMat.addContactShadow(at: SIMD3(center.x, 0.005, center.z), radiusX: 3.10, radiusZ: 2.75, opacity: 0.48, into: root)

        let braidTex = DeskTextures.braidedNylonCable()
        let braidMat = SCNMaterial()
        braidMat.lightingModel = .physicallyBased
        braidMat.diffuse.contents = braidTex.diffuse
        braidMat.diffuse.wrapS = .repeat
        braidMat.diffuse.wrapT = .repeat
        braidMat.diffuse.mipFilter = .linear
        braidMat.diffuse.maxAnisotropy = 8
        braidMat.normal.contents = braidTex.normal
        braidMat.normal.wrapS = .repeat
        braidMat.normal.wrapT = .repeat
        braidMat.normal.intensity = 1.15
        braidMat.roughness.contents = braidTex.roughness
        braidMat.roughness.wrapS = .repeat
        braidMat.roughness.wrapT = .repeat
        braidMat.metalness.contents = 0.02

        func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
            let u = min(max((x - edge0) / (edge1 - edge0), 0), 1)
            return u * u * (3 - 2 * u)
        }

        func coilPoint(angle a: Float, radialScale: Float, drift: SIMD2<Float>) -> SIMD3<Float> {
            let warp = 1.0 + 0.022 * cos(2 * a + 0.7) + 0.012 * sin(3 * a - 0.5)
            let lx = 2.38 * radialScale * warp * cos(a)
            let lz = 2.08 * radialScale * warp * sin(a)
            let wx = center.x + drift.x + lx * cos(coilTilt) - lz * sin(coilTilt)
            let wz = center.z + drift.y + lx * sin(coilTilt) + lz * cos(coilTilt)
            return SIMD3(wx, cableRadius, wz)
        }

        // Continuous spiral (~2.90 turns) whose radial pitch (0.273u > 0.184u diameter) keeps every loop physically distinct
        let aEntry: Float = 7.56 * .pi
        let aCoilStart: Float = 7.26 * .pi
        let aCoilEnd: Float = 1.46 * .pi
        let aExit: Float = 1.02 * .pi
        let steps = 68

        var pathCtrl = [SIMD3<Float>]()
        pathCtrl.reserveCapacity(steps + 6)
        for i in 0...steps {
            let s = Float(i) / Float(steps)
            let a = aEntry - s * (aEntry - aExit)

            let tCoil = min(max((aCoilStart - a) / (aCoilStart - aCoilEnd), 0), 1)
            let baseScale: Float = 1.10 - 0.38 * tCoil

            let entryFlare = smoothstep(aCoilStart, aEntry, a) * 0.24
            let exitFlare = smoothstep(aCoilEnd, aExit, a) * 0.44
            let rScale = baseScale + entryFlare + exitFlare

            let drift = SIMD2<Float>(0.11 * sin(tCoil * .pi * 1.35), -0.08 * cos(tCoil * .pi * 1.15))
            pathCtrl.append(coilPoint(angle: a, radialScale: rScale, drift: drift))
        }

        // Coaxial lead-ins straight into both connector boots
        let pFirst = pathCtrl[0], pSecond = pathCtrl[1]
        let outC = simd_normalize(SIMD3<Float>(pFirst.x - pSecond.x, 0, pFirst.z - pSecond.z))
        let usbCBoot = pFirst + outC * 0.72
        pathCtrl.insert(pFirst + outC * 0.36, at: 0)
        pathCtrl.insert(usbCBoot, at: 0)

        let pLast = pathCtrl[pathCtrl.count - 1], pPrev = pathCtrl[pathCtrl.count - 2]
        let outL = simd_normalize(SIMD3<Float>(pLast.x - pPrev.x, 0, pLast.z - pPrev.z))
        let lBoot = pLast + outL * 0.72
        pathCtrl.append(pLast + outL * 0.36)
        pathCtrl.append(lBoot)

        var smoothPts = MeshBuilder.catmullRom(pathCtrl, samplesPerSegment: 2)

        // Smooth non-intersecting vertical clearance over crossing tails
        let minSep = cableRadius * 2.12
        var reqY = smoothPts.map { max(cableRadius, $0.y) }
        for i in 0..<smoothPts.count {
            for j in 0..<max(0, i - 6) {
                let dx = smoothPts[i].x - smoothPts[j].x
                let dz = smoothPts[i].z - smoothPts[j].z
                let dXZ = sqrt(dx * dx + dz * dz)
                if dXZ < minSep {
                    let lift = reqY[j] + sqrt(max(0, minSep * minSep - dXZ * dXZ))
                    reqY[i] = max(reqY[i], lift)
                }
            }
        }
        let endLock = 4
        for _ in 0..<6 {
            var nextY = reqY
            for i in endLock..<(smoothPts.count - endLock) {
                let avg = (reqY[i - 2] + reqY[i - 1] * 2 + reqY[i] * 2 + reqY[i + 1] * 2 + reqY[i + 2]) * 0.125
                nextY[i] = max(reqY[i], avg)
            }
            reqY = nextY
        }
        for i in 0..<smoothPts.count {
            smoothPts[i].y = (i < endLock || i >= smoothPts.count - endLock) ? cableRadius : reqY[i]
        }

        let cableGeo = MeshBuilder.uvTube(points: smoothPts, radius: cableRadius, segments: 10, capEnds: true)
        cableGeo.materials = [braidMat]
        let cableNode = SCNNode(geometry: cableGeo)
        cableNode.castsShadow = true
        root.addChildNode(cableNode)

        buildCableConnector(kind: .usbC, at: usbCBoot, direction: outC, cableRadius: cableRadius, into: root)
        buildCableConnector(kind: .usbC, at: lBoot, direction: outL, cableRadius: cableRadius, into: root)
    }

    private static func buildCableConnector(
        kind: CablePlugKind,
        at bootStart: SIMD3<Float>,
        direction: SIMD3<Float>,
        cableRadius: Float,
        into root: SCNNode
    ) {
        let dir = simd_normalize(SIMD3<Float>(direction.x, 0, direction.z))
        let yaw = atan2(dir.x, dir.z)

        let conn = SCNNode()
        conn.simdPosition = SIMD3(bootStart.x, 0, bootStart.z)
        conn.eulerAngles.y = CGFloat(yaw)
        root.addChildNode(conn)

        let shellW: Float = (kind == .usbC) ? 0.54 : 0.48
        let shellH: Float = (kind == .usbC) ? 0.26 : 0.24
        let shellLen: Float = (kind == .usbC) ? 0.96 : 0.90
        let cy = shellH * 0.5

        DeskRoomAndMat.addContactShadow(
            at: SIMD3(bootStart.x + dir.x * 0.95, 0.005, bootStart.z + dir.z * 0.95),
            radiusX: 0.52,
            radiusZ: 1.20,
            opacity: 0.44,
            yaw: yaw,
            into: root
        )

        let rubberMat = SCNMaterial()
        rubberMat.lightingModel = .physicallyBased
        rubberMat.diffuse.contents = NSColor(srgbRed: 0.048, green: 0.050, blue: 0.055, alpha: 1)
        rubberMat.roughness.contents = 0.78
        rubberMat.metalness.contents = 0.0

        // Softened anodized metalness/roughness avoids harsh specular clipping under HDR
        let shellMat = SCNMaterial()
        shellMat.lightingModel = .physicallyBased
        shellMat.diffuse.contents = NSColor(srgbRed: 0.125, green: 0.112, blue: 0.114, alpha: 1)
        shellMat.metalness.contents = 0.60
        shellMat.roughness.contents = 0.38
        shellMat.clearCoat.contents = 0.08
        shellMat.clearCoatRoughness.contents = 0.36
        shellMat.normal.contents = DeskTextures.brushedNormal()
        shellMat.normal.intensity = 0.14

        let trimMat = SCNMaterial()
        trimMat.lightingModel = .physicallyBased
        trimMat.diffuse.contents = NSColor(srgbRed: 0.46, green: 0.47, blue: 0.50, alpha: 1)
        trimMat.metalness.contents = 0.88
        trimMat.roughness.contents = 0.24

        let chromeMat = SCNMaterial()
        chromeMat.lightingModel = .physicallyBased
        chromeMat.diffuse.contents = NSColor(white: 0.82, alpha: 1)
        chromeMat.metalness.contents = 0.92
        chromeMat.roughness.contents = 0.18

        // 1. Ribbed flexible TPE strain-relief boot bridging cable end into housing
        let bootStations: [(z: Float, hw: Float, hh: Float)] = [
            (-0.04, cableRadius * 0.96, cableRadius * 0.96),
            (0.00,  cableRadius * 1.12, cableRadius * 1.12),
            (0.06,  cableRadius * 1.24, cableRadius * 1.20),
            (0.11,  cableRadius * 1.12, cableRadius * 1.10),
            (0.16,  cableRadius * 1.32, cableRadius * 1.24),
            (0.21,  cableRadius * 1.16, cableRadius * 1.12),
            (0.26,  cableRadius * 1.40, cableRadius * 1.28),
            (0.31,  cableRadius * 1.24, cableRadius * 1.18),
            (0.41,  shellW * 0.27,      shellH * 0.38),
        ]
        var bootRings = [[SIMD3<Float>]]()
        let ringSegs = 16
        for st in bootStations {
            let t = min(max((st.z + 0.04) / 0.45, 0), 1)
            let yMid = cableRadius + (cy - cableRadius) * t
            let pExp: Float = 1.0 - 0.15 * t
            var ring = [SIMD3<Float>]()
            for s in 0..<ringSegs {
                let a = Float(s) / Float(ringSegs) * 2 * .pi
                let ca = cos(a), sa = sin(a)
                let x = (ca < 0 ? -1 : 1) * pow(abs(ca), pExp) * st.hw
                let y = yMid + (sa < 0 ? -1 : 1) * pow(abs(sa), pExp) * st.hh
                ring.append(SIMD3(x, max(0.002, y), st.z))
            }
            bootRings.append(ring)
        }
        let bootGeo = MeshBuilder.loft(rings: bootRings, capBottom: true, capTop: true, flipWinding: true)
        bootGeo.materials = [rubberMat]
        let bootNode = SCNNode(geometry: bootGeo)
        bootNode.castsShadow = true
        conn.addChildNode(bootNode)

        // 2. Anodized aluminum housing + machined rear/front trim collars + top emblem stripe
        let rearCollarZ: Float = 0.40
        let frontZ = rearCollarZ + shellLen

        let rearRing = MeshBuilder.roundedSlab(width: shellW * 0.62, height: shellH * 0.82, depth: 0.05, cornerRadius: shellH * 0.38, bevel: 0.01)
        rearRing.materials = [trimMat]
        let rrNode = SCNNode(geometry: rearRing)
        rrNode.position = SCNVector3(0, cy - shellH * 0.41, rearCollarZ)
        conn.addChildNode(rrNode)

        let shellGeo = MeshBuilder.roundedSlab(
            width: shellW,
            height: shellH,
            depth: shellLen,
            cornerRadius: shellH * 0.46,
            bevel: 0.032,
            cornerSegments: 8
        )
        shellGeo.materials = [shellMat]
        let shellNode = SCNNode(geometry: shellGeo)
        shellNode.position = SCNVector3(0, 0, rearCollarZ + shellLen * 0.5)
        shellNode.castsShadow = true
        conn.addChildNode(shellNode)

        let frontCollar = MeshBuilder.roundedSlab(width: shellW * 0.78, height: shellH * 0.68, depth: 0.036, cornerRadius: shellH * 0.32, bevel: 0.008)
        frontCollar.materials = [trimMat]
        let fcNode = SCNNode(geometry: frontCollar)
        fcNode.position = SCNVector3(0, cy - shellH * 0.34, frontZ + 0.004)
        conn.addChildNode(fcNode)

        let stripeMat = SCNMaterial()
        stripeMat.lightingModel = .physicallyBased
        stripeMat.diffuse.contents = NSColor(srgbRed: 0.44, green: 0.45, blue: 0.48, alpha: 1)
        stripeMat.roughness.contents = 0.36
        stripeMat.metalness.contents = 0.55
        let stripeGeo = MeshBuilder.roundedSlab(width: 0.024, height: 0.003, depth: shellLen * 0.38, cornerRadius: 0.01, bevel: 0.001)
        stripeGeo.materials = [stripeMat]
        let stripeNode = SCNNode(geometry: stripeGeo)
        stripeNode.position = SCNVector3(0, shellH - 0.001, rearCollarZ + shellLen * 0.50)
        conn.addChildNode(stripeNode)

        // 3. Detailed metallic plug tip
        let tipStart = frontZ + 0.028
        switch kind {
        case .usbC:
            let sleeveW: CGFloat = 0.438, sleeveH: CGFloat = 0.134, sleeveLen: CGFloat = 0.35
            let innerW: CGFloat = 0.382, innerH: CGFloat = 0.082
            let path = NSBezierPath(
                roundedRect: NSRect(x: -sleeveW / 2, y: -sleeveH / 2, width: sleeveW, height: sleeveH),
                xRadius: sleeveH / 2, yRadius: sleeveH / 2
            )
            path.append(NSBezierPath(
                roundedRect: NSRect(x: -innerW / 2, y: -innerH / 2, width: innerW, height: innerH),
                xRadius: innerH / 2, yRadius: innerH / 2
            ))
            path.windingRule = .evenOdd
            path.flatness = 0.002

            let sleeveGeo = SCNShape(path: path, extrusionDepth: sleeveLen)
            sleeveGeo.chamferRadius = 0.008
            sleeveGeo.chamferMode = .both
            sleeveGeo.materials = [chromeMat]
            let sleeveNode = SCNNode(geometry: sleeveGeo)
            sleeveNode.position = SCNVector3(0, cy, tipStart + Float(sleeveLen) * 0.5)
            sleeveNode.castsShadow = true
            conn.addChildNode(sleeveNode)

            let cavityMat = SCNMaterial()
            cavityMat.lightingModel = .physicallyBased
            cavityMat.diffuse.contents = NSColor(white: 0.02, alpha: 1)
            cavityMat.roughness.contents = 0.78
            let backPath = NSBezierPath(
                roundedRect: NSRect(x: -innerW / 2, y: -innerH / 2, width: innerW, height: innerH),
                xRadius: innerH / 2, yRadius: innerH / 2
            )
            backPath.flatness = 0.003
            let backGeo = SCNShape(path: backPath, extrusionDepth: 0.06)
            backGeo.materials = [cavityMat]
            let backNode = SCNNode(geometry: backGeo)
            backNode.position = SCNVector3(0, cy, tipStart + 0.04)
            conn.addChildNode(backNode)

            let tongueGeo = MeshBuilder.roundedSlab(width: 0.28, height: 0.024, depth: 0.24, cornerRadius: 0.008, bevel: 0.003)
            tongueGeo.materials = [cavityMat]
            let tongueNode = SCNNode(geometry: tongueGeo)
            tongueNode.position = SCNVector3(0, cy - 0.012, tipStart + 0.17)
            conn.addChildNode(tongueNode)

            let goldMat = SCNMaterial()
            goldMat.lightingModel = .physicallyBased
            goldMat.diffuse.contents = NSColor(srgbRed: 0.84, green: 0.64, blue: 0.24, alpha: 1)
            goldMat.metalness.contents = 0.94
            goldMat.roughness.contents = 0.16
            let pinBar = SCNBox(width: 0.22, height: 0.028, length: 0.07, chamferRadius: 0.002)
            pinBar.materials = [goldMat]
            let pbNode = SCNNode(geometry: pinBar)
            pbNode.position = SCNVector3(0, cy, tipStart + 0.18)
            conn.addChildNode(pbNode)

        case .lightning:
            let shoulder = MeshBuilder.roundedSlab(width: 0.39, height: 0.125, depth: 0.055, cornerRadius: 0.055, bevel: 0.012)
            shoulder.materials = [chromeMat]
            let shNode = SCNNode(geometry: shoulder)
            shNode.position = SCNVector3(0, cy - 0.0625, tipStart + 0.025)
            conn.addChildNode(shNode)

            let bladeStart = tipStart + 0.048
            let bladeLen: Float = 0.35
            let blade = MeshBuilder.roundedSlab(width: 0.345, height: 0.078, depth: bladeLen, cornerRadius: 0.11, bevel: 0.015, cornerSegments: 8)
            blade.materials = [chromeMat]
            let bladeNode = SCNNode(geometry: blade)
            bladeNode.position = SCNVector3(0, cy - 0.039, bladeStart + bladeLen * 0.5)
            bladeNode.castsShadow = true
            conn.addChildNode(bladeNode)

            let delrinMat = SCNMaterial()
            delrinMat.lightingModel = .physicallyBased
            delrinMat.diffuse.contents = NSColor(srgbRed: 0.84, green: 0.83, blue: 0.80, alpha: 1)
            delrinMat.roughness.contents = 0.38

            let goldMat = SCNMaterial()
            goldMat.lightingModel = .physicallyBased
            goldMat.diffuse.contents = NSColor(srgbRed: 0.84, green: 0.62, blue: 0.22, alpha: 1)
            goldMat.metalness.contents = 0.94
            goldMat.roughness.contents = 0.16

            let padGeo = MeshBuilder.roundedSlab(width: 0.278, height: 0.008, depth: 0.22, cornerRadius: 0.045, bevel: 0.002)
            padGeo.materials = [delrinMat]
            let pinGeo = SCNBox(width: 0.020, height: 0.004, length: 0.135, chamferRadius: 0.001)
            pinGeo.materials = [goldMat]

            for side: Float in [-1, 1] {
                let pad = SCNNode(geometry: padGeo)
                pad.position = SCNVector3(0, cy + side * 0.037 - 0.004, bladeStart + 0.17)
                conn.addChildNode(pad)
                for p in 0..<8 {
                    let pin = SCNNode(geometry: pinGeo)
                    pin.position = SCNVector3((Float(p) - 3.5) * 0.031, cy + side * 0.0415, bladeStart + 0.185)
                    conn.addChildNode(pin)
                }
            }
        }
    }

    // MARK: - Keyboard USB-C Cable (Keyboard Port -> Mac mini Rear Thunderbolt)

    static func buildKeyboardCable(into root: SCNNode) {
        // Satin off-white PVC/TPE (<= 0.85 HDR ceiling) so white cable holds contour under desk key light
        let cableMat = SCNMaterial()
        cableMat.lightingModel = .physicallyBased
        cableMat.diffuse.contents = NSColor(srgbRed: 0.82, green: 0.82, blue: 0.80, alpha: 1)
        cableMat.roughness.contents = 0.44
        cableMat.metalness.contents = 0.01

        let sleeveMat = SCNMaterial()
        sleeveMat.lightingModel = .physicallyBased
        sleeveMat.diffuse.contents = NSColor(white: 0.78, alpha: 1)
        sleeveMat.metalness.contents = 0.88
        sleeveMat.roughness.contents = 0.22

        let cableR: Float = 0.085
        let matY = DeskRoomAndMat.matTopY

        // 1. Keyboard rear USB-C plug + strain relief seated coaxially into CaseMesh rear cutout
        let portLocalZ = CaseMesh.zMin + CaseMesh.rearBayDepth * 0.65
        let portLocalY = CaseMesh.rearBayCenterY
        let plugWorldX = CaseMesh.usbcPortLocalX
        let plugWorldY = matY + CaseMesh.kbPosYOffset + portLocalY * cos(CaseMesh.tiltRad) - portLocalZ * sin(CaseMesh.tiltRad)
        let plugWorldZ = portLocalY * sin(CaseMesh.tiltRad) + portLocalZ * cos(CaseMesh.tiltRad)
        let kbPortPos = SIMD3<Float>(plugWorldX, plugWorldY, plugWorldZ)
        let kbBackDir = SIMD3<Float>(0, sin(CaseMesh.tiltRad), -cos(CaseMesh.tiltRad))

        func addMoldedUSBCPlug(
            at portPos: SIMD3<Float>,
            outward: SIMD3<Float>,
            pitchX: Float,
            yawY: Float,
            plugWidth: Float,
            plugHeight: Float,
            plugDepth: Float
        ) {
            let sleeveGeo = MeshBuilder.roundedSlab(width: plugWidth * 0.84, height: plugHeight * 0.54, depth: 0.08, cornerRadius: plugHeight * 0.24, bevel: 0.008)
            sleeveGeo.materials = [sleeveMat]
            let sleeveNode = SCNNode(geometry: sleeveGeo)
            sleeveNode.pivot = SCNMatrix4MakeTranslation(0, CGFloat(plugHeight * 0.27), 0)
            sleeveNode.simdPosition = portPos + outward * 0.005
            sleeveNode.eulerAngles = SCNVector3(pitchX, yawY, 0)
            root.addChildNode(sleeveNode)

            let plugGeo = MeshBuilder.roundedSlab(width: plugWidth, height: plugHeight, depth: plugDepth, cornerRadius: plugHeight * 0.40, bevel: 0.032, cornerSegments: 6)
            plugGeo.materials = [cableMat]
            let plugNode = SCNNode(geometry: plugGeo)
            plugNode.pivot = SCNMatrix4MakeTranslation(0, CGFloat(plugHeight * 0.5), 0)
            plugNode.simdPosition = portPos + outward * (plugDepth * 0.5 + 0.015)
            plugNode.eulerAngles = SCNVector3(pitchX, yawY, 0)
            plugNode.castsShadow = true
            root.addChildNode(plugNode)

            let bootDists: [Float] = [plugDepth - 0.02, plugDepth + 0.06, plugDepth + 0.14, plugDepth + 0.24]
            let bootRadii: [Float] = [cableR * 1.32, cableR * 1.28, cableR * 1.14, cableR * 0.98]
            let bootGeo = MeshBuilder.tube(
                points: bootDists.map { portPos + outward * $0 },
                radius: cableR,
                radii: bootRadii,
                segments: 14,
                capEnds: false
            )
            bootGeo.materials = [cableMat]
            let bootNode = SCNNode(geometry: bootGeo)
            bootNode.castsShadow = true
            root.addChildNode(bootNode)
        }

        addMoldedUSBCPlug(
            at: kbPortPos,
            outward: kbBackDir,
            pitchX: CaseMesh.tiltRad,
            yawY: 0,
            plugWidth: 0.42,
            plugHeight: 0.19,
            plugDepth: 0.64
        )

        // 2. Mac mini rear Thunderbolt 4 port (leftmost port tx = -1.70, clear of HDMI at -0.22 and AC at +1.42)
        let miniPos = TechProps.MacMini.position
        let miniYaw = TechProps.MacMini.yaw
        let c = cos(miniYaw), s = sin(miniYaw)
        let tbLocalX: Float = -1.70
        let tbLocalY: Float = 0.99
        let tbLocalZ: Float = -TechProps.MacMini.halfDepth + 0.033
        let miniPortPos = miniPos + SIMD3<Float>(tbLocalX * c + tbLocalZ * s, tbLocalY, -tbLocalX * s + tbLocalZ * c)
        let miniRearOut = SIMD3<Float>(-s, 0, -c)

        addMoldedUSBCPlug(
            at: miniPortPos,
            outward: miniRearOut,
            pitchX: 0,
            yawY: miniYaw,
            plugWidth: 0.44,
            plugHeight: 0.23,
            plugDepth: 0.60
        )

        // 3. Continuous spline dropping onto the Ukiru mat, stepping cleanly off rim z = -11.0 onto walnut desk,
        // clearing pothos bowl #2 (-14.0, -15.2, R=2.75) and monitor ring (2.8, -15.4, R=5.15), and rising into Mac mini
        let matCableY = matY + cableR
        let ctrl: [SIMD3<Float>] = [
            kbPortPos + kbBackDir * 0.60,
            kbPortPos + kbBackDir * 0.84,
            kbPortPos + kbBackDir * 1.15,
            SIMD3<Float>(kbPortPos.x - 0.14, 1.02, -4.50),
            SIMD3<Float>(-3.25, 0.40, -5.75),
            SIMD3<Float>(-5.20, matCableY, -7.85),
            SIMD3<Float>(-8.35, matCableY, -10.28),
            SIMD3<Float>(-9.35, matCableY, -10.82), // on mat right before rear edge (-11.00)
            SIMD3<Float>(-9.82, 0.18, -11.24),      // gentle step down over mat rim
            SIMD3<Float>(-10.12, cableR, -12.18),   // resting flush on walnut desk
            SIMD3<Float>(-9.45, cableR, -15.15),    // 4.55u clear of pothos #2 center (-14.0, -15.2)
            SIMD3<Float>(-5.05, cableR, -16.95),
            SIMD3<Float>(-2.75, cableR, -19.30),
            SIMD3<Float>(2.80, cableR, -21.22),     // 5.82u behind monitor ring (R = 5.15)
            SIMD3<Float>(10.65, cableR, -20.20),
            SIMD3<Float>(14.20, cableR, -19.55),
            SIMD3<Float>(15.55, 0.62, -18.55),
            miniPortPos + miniRearOut * 0.92,
            miniPortPos + miniRearOut * 0.72,
            miniPortPos + miniRearOut * 0.56,
        ]
        var path = MeshBuilder.catmullRom(ctrl, samplesPerSegment: 6)
        for i in 0..<path.count {
            path[i].y = max(cableR, path[i].y)
        }
        let cableGeo = MeshBuilder.tube(points: path, radius: cableR, segments: 10)
        cableGeo.materials = [cableMat]
        let cableNode = SCNNode(geometry: cableGeo)
        cableNode.castsShadow = true
        root.addChildNode(cableNode)
    }
}
