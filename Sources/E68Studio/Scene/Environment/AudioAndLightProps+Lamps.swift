import SceneKit
import AppKit
import simd

extension AudioAndLightProps {
    // MARK: - High-Gloss Architect Swing-Arm Desk Lamp

    static func buildDeskLamp(into root: SCNNode) {
        let lamp = SCNNode()
        lamp.name = KeyboardScene.DeskProp.deskLamp.rawValue
        lamp.position = SCNVector3(-27.8, 0, -11.5)
        root.addChildNode(lamp)

        let glossBlackMetal = SCNMaterial()
        glossBlackMetal.lightingModel = .physicallyBased
        glossBlackMetal.diffuse.contents = NSColor(srgbRed: 0.024, green: 0.026, blue: 0.030, alpha: 1)
        glossBlackMetal.metalness.contents = 0.25
        glossBlackMetal.roughness.contents = 0.20
        glossBlackMetal.clearCoat.contents = 0.85
        glossBlackMetal.clearCoatRoughness.contents = 0.06

        let darkHardware = SCNMaterial()
        darkHardware.lightingModel = .physicallyBased
        darkHardware.diffuse.contents = NSColor(srgbRed: 0.045, green: 0.047, blue: 0.052, alpha: 1)
        darkHardware.metalness.contents = 0.18
        darkHardware.roughness.contents = 0.38

        let darkSpringSteel = SCNMaterial()
        darkSpringSteel.lightingModel = .physicallyBased
        darkSpringSteel.diffuse.contents = NSColor(srgbRed: 0.075, green: 0.080, blue: 0.088, alpha: 1)
        darkSpringSteel.metalness.contents = 0.78
        darkSpringSteel.roughness.contents = 0.32

        let brushedSteel = SCNMaterial()
        brushedSteel.lightingModel = .physicallyBased
        brushedSteel.diffuse.contents = NSColor(white: 0.70, alpha: 1)
        brushedSteel.metalness.contents = 0.90
        brushedSteel.roughness.contents = 0.24

        let cordMat = SCNMaterial()
        cordMat.lightingModel = .physicallyBased
        cordMat.diffuse.contents = NSColor(srgbRed: 0.035, green: 0.036, blue: 0.040, alpha: 1)
        cordMat.roughness.contents = 0.60
        cordMat.metalness.contents = 0.02

        DeskRoomAndMat.addContactShadow(at: SIMD3(-27.8, 0.005, -11.5), radiusX: 3.65, radiusZ: 3.65, opacity: 0.42, into: root)

        // 1. Spun-metal black dome base (IMG_1852/1853): stepped outer skirt, broad slightly-domed
        // tray plateau, shallow circular concave saucer dish front-right, and off-center back-left
        // turret post with rear knurled locking thumbscrew & forward spring-hook lugs (no switch box on base).
        let baseProfile: [(r: Float, y: Float)] = [
            (0.01, 0.0), (3.58, 0.0), (3.68, 0.08), (3.66, 0.24),
            (3.48, 0.36), (3.24, 0.42), (3.10, 0.35), (0.01, 0.35),
        ]
        let baseGeo = MeshBuilder.lathe(profile: baseProfile, segments: 52)
        baseGeo.materials = [glossBlackMetal]
        let baseNode = SCNNode(geometry: baseGeo)
        baseNode.castsShadow = true
        lamp.addChildNode(baseNode)

        // Raised circular spun saucer dish inset toward front-right inside the base plateau.
        let saucerPos = SIMD3<Float>(0.68, 0.0, 0.56)
        let saucerProfile: [(r: Float, y: Float)] = [
            (0.01, 0.27), (0.95, 0.30), (1.38, 0.38), (1.58, 0.46),
            (1.66, 0.45), (1.68, 0.34), (1.52, 0.34),
        ]
        let saucerGeo = MeshBuilder.lathe(profile: saucerProfile, segments: 40)
        saucerGeo.materials = [glossBlackMetal]
        let saucerNode = SCNNode(geometry: saucerGeo)
        saucerNode.simdPosition = saucerPos
        saucerNode.castsShadow = true
        lamp.addChildNode(saucerNode)

        // Off-center cast turret mound + cylindrical post rising back-left (-X, -Z) with rear knurled thumbscrew.
        let postPos = SIMD3<Float>(-0.92, 0.0, -0.62)
        let turretProfile: [(r: Float, y: Float)] = [
            (1.10, 0.34), (0.86, 0.54), (0.62, 0.74), (0.50, 0.94),
            (0.47, 2.38), (0.52, 2.44), (0.52, 2.58), (0.01, 2.58),
        ]
        let turretGeo = MeshBuilder.lathe(profile: turretProfile, segments: 32)
        turretGeo.materials = [glossBlackMetal]
        let turretNode = SCNNode(geometry: turretGeo)
        turretNode.simdPosition = postPos
        turretNode.castsShadow = true
        lamp.addChildNode(turretNode)

        // Rear knurled cylindrical black locking thumbscrew protruding out the back of the turret post.
        let thumbAxis = simd_normalize(SIMD3<Float>(-0.95, 0, 0.18))
        let screwStemGeo = SCNCylinder(radius: 0.12, height: 0.56)
        screwStemGeo.materials = [darkHardware]
        let screwStem = SCNNode(geometry: screwStemGeo)
        screwStem.simdPosition = postPos + SIMD3(0, 1.56, 0) + thumbAxis * 0.42
        screwStem.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: thumbAxis)
        lamp.addChildNode(screwStem)

        let knobCapGeo = SCNCylinder(radius: 0.28, height: 0.34)
        knobCapGeo.radialSegmentCount = 20
        knobCapGeo.materials = [darkHardware]
        let knobCap = SCNNode(geometry: knobCapGeo)
        knobCap.simdPosition = postPos + SIMD3(0, 1.56, 0) + thumbAxis * 0.74
        knobCap.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: thumbAxis)
        knobCap.castsShadow = true
        lamp.addChildNode(knobCap)
        for rIdx in 0..<4 {
            let rib = SCNCylinder(radius: 0.295, height: 0.032)
            rib.radialSegmentCount = 20
            rib.materials = [glossBlackMetal]
            let rn = SCNNode(geometry: rib)
            rn.position = SCNVector3(0, -0.10 + Float(rIdx) * 0.068, 0)
            knobCap.addChildNode(rn)
        }

        // 2. Planar scissor arm coordinate frame matching IMG_1850/1852/1853 posture
        let armYaw: Float = -0.18
        let armRight = SIMD3<Float>(cos(armYaw), 0, -sin(armYaw))
        let viewerNormal = simd_normalize(simd_cross(armRight, SIMD3(0, 1, 0))) // faces front (+Z)

        let p0 = postPos + SIMD3<Float>(0, 2.52, 0)
        let p1 = p0 - armRight * 3.85 + SIMD3(0, 8.65, 0) // elbow just past left rim of base
        let p2 = p1 + armRight * 7.80 + SIMD3(0, 6.45, 0) // rear head knuckle behind shade

        func armBasis(from a: SIMD3<Float>, to b: SIMD3<Float>) -> (dir: SIMD3<Float>, len: Float, upPerp: SIMD3<Float>, orient: simd_quatf) {
            let span = b - a
            let len = simd_length(span)
            let dir = span / len
            let upPerp = simd_normalize(simd_cross(dir, viewerNormal))
            let zAxis = simd_normalize(simd_cross(upPerp, dir))
            let orient = simd_quatf(simd_float3x3(upPerp, dir, zAxis))
            return (dir, len, upPerp, orient)
        }

        func addScissorBars(from a: SIMD3<Float>, to b: SIMD3<Float>, offset: Float, thickness: Float, width: Float) {
            let basis = armBasis(from: a, to: b)
            let mid = (a + b) * 0.5
            let barGeo = SCNBox(width: CGFloat(thickness), height: CGFloat(basis.len), length: CGFloat(width), chamferRadius: 0.025)
            barGeo.materials = [glossBlackMetal]
            for s: Float in [-offset, offset] {
                let bar = SCNNode(geometry: barGeo)
                bar.simdPosition = mid + basis.upPerp * s
                bar.simdOrientation = basis.orient
                bar.castsShadow = true
                lamp.addChildNode(bar)
            }
        }

        let b01 = armBasis(from: p0, to: p1)
        let b12 = armBasis(from: p1, to: p2)

        // Open XY-plane parallel bars so both scissor bars & daylight gap read clearly from front view
        addScissorBars(from: p0, to: p1, offset: 0.28, thickness: 0.16, width: 0.26)
        addScissorBars(from: p1, to: p2, offset: 0.24, thickness: 0.15, width: 0.24)

        // Stamped twin cheek-plate brackets aligned with the arm plane
        let planeOrient = simd_quatf(simd_float3x3(armRight, SIMD3(0, 1, 0), viewerNormal))

        func addCheekBracket(at center: SIMD3<Float>, width: Float, height: Float, spread: Float) {
            let plateGeo = MeshBuilder.roundedSlab(
                width: width, height: height, depth: 0.075,
                cornerRadius: min(width, height) * 0.26, bevel: 0.015
            )
            plateGeo.materials = [glossBlackMetal]
            for s: Float in [-spread, spread] {
                let plate = SCNNode(geometry: plateGeo)
                plate.simdPosition = center + viewerNormal * s - SIMD3(0, height * 0.5, 0)
                plate.simdOrientation = planeOrient
                plate.castsShadow = true
                lamp.addChildNode(plate)
            }
        }

        addCheekBracket(at: p0, width: 0.92, height: 1.06, spread: 0.185)
        addCheekBracket(at: p1 + SIMD3(0, 0.24, 0), width: 1.24, height: 1.48, spread: 0.185)
        addCheekBracket(at: p2, width: 0.96, height: 0.92, spread: 0.175)

        // Compact dark tension knobs / wingnuts at base, elbow, and head knuckle
        func addCompactWingNut(at pos: SIMD3<Float>, scale: Float) {
            let group = SCNNode()
            group.simdPosition = pos
            group.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: viewerNormal)
            lamp.addChildNode(group)

            let bolt = SCNCylinder(radius: CGFloat(0.095 * scale), height: CGFloat(0.68 * scale))
            bolt.materials = [brushedSteel]
            group.addChildNode(SCNNode(geometry: bolt))

            let washerGeo = SCNCylinder(radius: CGFloat(0.22 * scale), height: CGFloat(0.055 * scale))
            washerGeo.materials = [brushedSteel]
            for wy: Float in [-0.25 * scale, 0.25 * scale] {
                let w = SCNNode(geometry: washerGeo)
                w.position = SCNVector3(0, wy, 0)
                group.addChildNode(w)
            }

            let hubCap = SCNCylinder(radius: CGFloat(0.19 * scale), height: CGFloat(0.22 * scale))
            hubCap.materials = [darkHardware]
            let hubNode = SCNNode(geometry: hubCap)
            hubNode.position = SCNVector3(0, 0.34 * scale, 0)
            group.addChildNode(hubNode)

            let wingGeo = MeshBuilder.roundedSlab(
                width: 0.28 * scale, height: 0.10 * scale, depth: 0.18 * scale,
                cornerRadius: 0.04 * scale, bevel: 0.016 * scale
            )
            wingGeo.materials = [darkHardware]
            for side: Float in [-1, 1] {
                let wing = SCNNode(geometry: wingGeo)
                wing.position = SCNVector3(side * 0.20 * scale, 0.35 * scale, 0)
                wing.eulerAngles.z = CGFloat(side * 0.32)
                wing.castsShadow = true
                group.addChildNode(wing)
            }
        }

        let hubGeo = SCNCylinder(radius: 0.38, height: 0.44)
        hubGeo.materials = [glossBlackMetal]
        for hubPos in [p0, p1, p2] {
            let hub = SCNNode(geometry: hubGeo)
            hub.simdPosition = hubPos
            hub.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: viewerNormal)
            lamp.addChildNode(hub)
        }
        addCompactWingNut(at: p0, scale: 0.72)
        addCompactWingNut(at: p1, scale: 0.80)
        addCompactWingNut(at: p2, scale: 0.70)

        // Lower springs: DUAL external coil springs (front + back flanks) hooked between forward turret lugs and mid-arm lugs (IMG_1852/1853)
        let lowerPinA = p0 + armRight * 0.42 - SIMD3(0, 0.36, 0)
        let lowerPinB = p0 + b01.dir * (b01.len * 0.56)
        for side: Float in [-1, 1] {
            let sideVec = viewerNormal * side
            let hookA = lowerPinA + sideVec * 0.44
            let hookB = lowerPinB + sideVec * 0.44
            // Grooved external aluminum mounting lug sticking out the outer side of each bar
            let lug = SCNCylinder(radius: 0.085, height: 0.32)
            lug.materials = [glossBlackMetal]
            let lugNode = SCNNode(geometry: lug)
            lugNode.simdPosition = lowerPinB + sideVec * 0.34
            lugNode.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: viewerNormal)
            lamp.addChildNode(lugNode)

            let anchorEar = SCNCylinder(radius: 0.075, height: 0.28)
            anchorEar.materials = [glossBlackMetal]
            let earNode = SCNNode(geometry: anchorEar)
            earNode.simdPosition = lowerPinA + sideVec * 0.34
            earNode.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: viewerNormal)
            lamp.addChildNode(earNode)

            AudioAndLightProps.addAnchoredSpring(
                from: hookA,
                to: hookB,
                pinAxis: viewerNormal,
                pinLength: 0.16,
                coils: 28,
                coilRadius: 0.118,
                wireRadius: 0.025,
                pointsPerCoil: 20,
                leadFrac: 0.10,
                springMaterial: darkSpringSteel,
                pinMaterial: brushedSteel,
                into: lamp
            )
        }

        // Upper springs: DUAL external coil springs (front + back flanks) between elbow gusset ears and upper arm lugs
        let upperStartPin = p1 + SIMD3(0, 0.64, 0) - armRight * 0.18
        let upperEndPin = p1 + b12.dir * (b12.len * 0.38) + b12.upPerp * 0.10
        for side: Float in [-1, 1] {
            let sideVec = viewerNormal * side
            let uLug = SCNCylinder(radius: 0.082, height: 0.30)
            uLug.materials = [glossBlackMetal]
            let uLugNode = SCNNode(geometry: uLug)
            uLugNode.simdPosition = upperEndPin + sideVec * 0.34
            uLugNode.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: viewerNormal)
            lamp.addChildNode(uLugNode)

            AudioAndLightProps.addAnchoredSpring(
                from: upperStartPin + sideVec * 0.44,
                to: upperEndPin + sideVec * 0.44,
                pinAxis: viewerNormal,
                pinLength: 0.16,
                coils: 24,
                coilRadius: 0.115,
                wireRadius: 0.024,
                pointsPerCoil: 20,
                leadFrac: 0.10,
                springMaterial: darkSpringSteel,
                pinMaterial: brushedSteel,
                into: lamp
            )
        }

        // 3. Lamp head, riveted brushed-silver cast Y-fork yoke, 8-hole perforated dome cap & curved neck wire loop
        let headOrigin = p2 + armRight * 2.05 + SIMD3(0, 0.34, 0)
        let aimDir = simd_normalize(SIMD3<Float>(0.32, -0.92, -0.22))
        let headY = -aimDir
        let headZ = simd_normalize(viewerNormal - simd_dot(viewerNormal, headY) * headY)
        let headX = simd_normalize(simd_cross(headY, headZ))
        let headOrient = simd_quatf(simd_float3x3(headX, headY, headZ))

        let head = SCNNode()
        head.simdPosition = headOrigin
        head.simdOrientation = headOrient
        lamp.addChildNode(head)

        // Brushed cast-aluminum silver Y-fork yoke hinged at p2 and riveted to flanks of cylindrical socket cap (IMG_1849/1851)
        let yokeSteel = SCNMaterial()
        yokeSteel.lightingModel = .physicallyBased
        yokeSteel.diffuse.contents = NSColor(white: 0.86, alpha: 1)
        yokeSteel.metalness.contents = 0.88
        yokeSteel.roughness.contents = 0.18

        let neckJoin = p2 + (headOrigin - p2) * 0.32
        let yokeStemPts = MeshBuilder.catmullRom([p2, (p2 + neckJoin) * 0.5, neckJoin], samplesPerSegment: 4)
        let yokeStemGeo = MeshBuilder.tube(points: yokeStemPts, radius: 0.19, segments: 10)
        yokeStemGeo.materials = [yokeSteel]
        let yokeStemNode = SCNNode(geometry: yokeStemGeo)
        yokeStemNode.castsShadow = true
        lamp.addChildNode(yokeStemNode)

        for forkSide: Float in [-1, 1] {
            let tineTarget = headOrigin + headOrient.act(SIMD3(-0.18, 1.42, forkSide * 1.36))
            let tineMid = headOrigin + headOrient.act(SIMD3(-1.42, 1.15, forkSide * 1.24))
            let tinePts = MeshBuilder.catmullRom([neckJoin, tineMid, tineTarget], samplesPerSegment: 6)
            let tineGeo = MeshBuilder.tube(points: tinePts, radius: 0.13, segments: 8)
            tineGeo.materials = [yokeSteel]
            let tineNode = SCNNode(geometry: tineGeo)
            tineNode.castsShadow = true
            lamp.addChildNode(tineNode)

            let padGeo = SCNCylinder(radius: 0.21, height: 0.12)
            padGeo.materials = [yokeSteel]
            let padNode = SCNNode(geometry: padGeo)
            padNode.simdPosition = tineTarget
            padNode.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: headZ * forkSide)
            lamp.addChildNode(padNode)

            // Domed stainless rivet securing yoke tine cleanly to center flank of socket cap (IMG_1848/1851)
            let rivetGeo = SCNSphere(radius: 0.115)
            rivetGeo.materials = [yokeSteel]
            let rivetNode = SCNNode(geometry: rivetGeo)
            rivetNode.simdPosition = tineTarget + headZ * (forkSide * 0.06)
            lamp.addChildNode(rivetNode)
        }

        // Bell shade + stepped cylindrical socket cap up to shoulder seam (top dome is real 8-hole perforated cap above)
        let shadeProfile: [(r: Float, y: Float)] = [
            (0.00,  0.12), (1.48,  0.12), (2.10, -0.08), (2.70, -0.46),
            (3.16, -1.02), (3.44, -1.66), (3.54, -2.36), (3.64, -2.44),
            (3.71, -2.38), (3.65, -2.22), (3.52, -1.62), (3.24, -0.96),
            (2.78, -0.40), (2.18, -0.02), (1.58,  0.18), (1.36,  0.32),
            (1.45,  0.38), (1.45,  0.54), (1.35,  0.62), (1.35,  2.14),
            (1.30,  2.18), (0.00,  2.18),
        ]
        let shadeGeo = MeshBuilder.lathe(profile: shadeProfile, segments: 48)
        shadeGeo.materials = [glossBlackMetal]
        let shadeNode = SCNNode(geometry: shadeGeo)
        shadeNode.castsShadow = true
        head.addChildNode(shadeNode)

        // Real 8-hole perforated domed cap (IMG_1849/1851) + dark interior socket ceiling behind vents
        let baffleGeo = SCNCylinder(radius: 1.24, height: 0.16)
        baffleGeo.materials = [darkHardware]
        let baffleNode = SCNNode(geometry: baffleGeo)
        baffleNode.position = SCNVector3(0, 2.22, 0)
        head.addChildNode(baffleNode)

        // Builds a smooth dome shoulder cap with 8 genuine circular ventilation cutouts + inner metal wall lips.
        func buildPerforatedLampDome(sectors: Int) -> SCNGeometry {
            let r0: Float = 1.35, rTop: Float = 0.56
            let y0: Float = 2.16, yTop: Float = 2.74
            func domePoint(sector: Int, su: Float, sv: Float, inset: Float = 0) -> SIMD3<Float> {
                let dTheta = 2.0 * Float.pi / Float(sectors)
                let theta = (Float(sector) + 0.5 + su * 0.5) * dTheta
                let t = max(0, min(1, (sv + 1.0) * 0.5))
                let ang = pow(t, 0.85) * Float.pi * 0.5
                let r = rTop + (r0 - rTop) * cos(ang)
                let y = y0 + (yTop - y0) * sin(ang)
                let p = SIMD3<Float>(r * cos(theta), y, r * sin(theta))
                if inset == 0 { return p }
                let nApprox = simd_normalize(SIMD3<Float>(cos(theta) * max(0.15, cos(ang)), max(0.15, sin(ang)), sin(theta) * max(0.15, cos(ang))))
                return p - nApprox * inset
            }
            var verts = [SIMD3<Float>]()
            var tris = [Int32]()
            let refCenter = SIMD3<Float>(0, y0 - 0.15, 0)
            func appendTri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
                let i0 = Int32(verts.count)
                let center = (a + b + c) / 3.0
                let n = simd_cross(b - a, c - a)
                verts.append(a)
                if simd_dot(n, center - refCenter) >= 0 {
                    verts.append(b); verts.append(c)
                } else {
                    verts.append(c); verts.append(b)
                }
                tris.append(contentsOf: [i0, i0 + 1, i0 + 2])
            }
            // 16 perimeter points around square [-1, 1]^2 matched radially to circular hole points
            let ringN = 16
            var perim = [(Float, Float)]()
            for i in 0..<ringN {
                let ang = (Float(i) / Float(ringN)) * 2.0 * Float.pi
                let c = cos(ang), s = sin(ang)
                let scale = 1.0 / max(abs(c), abs(s))
                perim.append((c * scale, s * scale))
            }
            let holeR: Float = 0.44
            for sec in 0..<sectors {
                for i in 0..<ringN {
                    let j = (i + 1) % ringN
                    let (bu0, bv0) = perim[i]
                    let (bu1, bv1) = perim[j]
                    let a0 = (Float(i) / Float(ringN)) * 2.0 * Float.pi
                    let a1 = (Float(j) / Float(ringN)) * 2.0 * Float.pi
                    let (hu0, hv0) = (holeR * cos(a0), holeR * sin(a0))
                    let (hu1, hv1) = (holeR * cos(a1), holeR * sin(a1))

                    let pB0 = domePoint(sector: sec, su: bu0, sv: bv0)
                    let pB1 = domePoint(sector: sec, su: bu1, sv: bv1)
                    let pH0 = domePoint(sector: sec, su: hu0, sv: hv0)
                    let pH1 = domePoint(sector: sec, su: hu1, sv: hv1)
                    appendTri(pB0, pB1, pH1)
                    appendTri(pB0, pH1, pH0)

                    // Inner wall thickness lip around cutout
                    let pI0 = domePoint(sector: sec, su: hu0, sv: hv0, inset: 0.065)
                    let pI1 = domePoint(sector: sec, su: hu1, sv: hv1, inset: 0.065)
                    appendTri(pH0, pH1, pI1)
                    appendTri(pH0, pI1, pI0)
                }
            }
            // Top closed crown disc above holes
            let crownSegs = 32
            let crownApex = SIMD3<Float>(0, yTop + 0.04, 0)
            for i in 0..<crownSegs {
                let t0 = Float(i) / Float(crownSegs) * 2.0 * Float.pi
                let t1 = Float(i + 1) / Float(crownSegs) * 2.0 * Float.pi
                let c0 = SIMD3<Float>(rTop * cos(t0), yTop, rTop * sin(t0))
                let c1 = SIMD3<Float>(rTop * cos(t1), yTop, rTop * sin(t1))
                appendTri(crownApex, c1, c0)
            }
            var normals = [SIMD3<Float>](repeating: .zero, count: verts.count)
            for idx in stride(from: 0, to: tris.count, by: 3) {
                let a = Int(tris[idx]), b = Int(tris[idx + 1]), c = Int(tris[idx + 2])
                let fn = simd_normalize(simd_cross(verts[b] - verts[a], verts[c] - verts[a]))
                normals[a] = fn; normals[b] = fn; normals[c] = fn
            }
            let vSrc = SCNGeometrySource(vertices: verts.map { SCNVector3($0.x, $0.y, $0.z) })
            let nSrc = SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
            let elem = SCNGeometryElement(indices: tris, primitiveType: .triangles)
            return SCNGeometry(sources: [vSrc, nSrc], elements: [elem])
        }

        let capGeo = buildPerforatedLampDome(sectors: 8)
        capGeo.materials = [glossBlackMetal]
        let capNode = SCNNode(geometry: capGeo)
        capNode.castsShadow = true
        head.addChildNode(capNode)

        // Signature curved black wire loop exiting rear rubber strain-relief grommet of cylindrical cap
        let wireExit = headOrigin + headOrient.act(SIMD3(-1.12, 1.88, -0.22))
        let wireEnter = p2 - b12.dir * 1.15 + b12.upPerp * 0.14
        let grommet = SCNCylinder(radius: 0.14, height: 0.28)
        grommet.materials = [cordMat]
        let grommetNode = SCNNode(geometry: grommet)
        grommetNode.simdPosition = wireExit
        grommetNode.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: headOrient.act(SIMD3(-0.85, 0.45, -0.20)))
        lamp.addChildNode(grommetNode)

        let neckWireCtrl: [SIMD3<Float>] = [
            wireExit,
            wireExit + SIMD3(-0.55, 0.48, -0.10),
            p2 + SIMD3(-0.32, 1.16, -0.14),
            p2 - b12.dir * 0.42 + b12.upPerp * 0.38,
            wireEnter,
        ]
        let neckWirePts = MeshBuilder.catmullRom(neckWireCtrl, samplesPerSegment: 8)
        let neckWireGeo = MeshBuilder.tube(points: neckWirePts, radius: 0.064, segments: 8)
        neckWireGeo.materials = [cordMat]
        let neckWireNode = SCNNode(geometry: neckWireGeo)
        neckWireNode.castsShadow = true
        lamp.addChildNode(neckWireNode)

        // 4. Power cord exiting left from base turret, draping off left desk rim (x = -41.0) to hanging inline rocker switch (IMG_1847/1852)
        let lampPos = SIMD3<Float>(-27.8, 0, -11.5)
        let worldPost = lampPos + postPos
        let deskLeftRimX: Float = -41.0
        let dropZ: Float = -5.6
        let leftCordCtrl: [SIMD3<Float>] = [
            worldPost + SIMD3(-0.45, 0.90, 0.18),
            worldPost + SIMD3(-2.10, 0.08, 1.65),
            SIMD3(-33.4, 0.075, -8.2),
            SIMD3(-37.8, 0.075, -6.6),
            SIMD3(-40.82, 0.075, dropZ),
            SIMD3(deskLeftRimX - 0.18, -0.18, dropZ),
            SIMD3(deskLeftRimX - 0.24, -1.45, dropZ),
        ]
        let leftCordPts = MeshBuilder.catmullRom(leftCordCtrl, samplesPerSegment: 6)
        let leftCordGeo = MeshBuilder.tube(points: leftCordPts, radius: 0.075, segments: 8)
        leftCordGeo.materials = [cordMat]
        let leftCordNode = SCNNode(geometry: leftCordGeo)
        leftCordNode.castsShadow = true
        root.addChildNode(leftCordNode)

        // Matte black rectangular inline rocker switch hanging vertically off the left side of the desk
        let switchPos = SIMD3<Float>(deskLeftRimX - 0.25, -2.05, dropZ)
        let swBody = MeshBuilder.roundedSlab(width: 0.44, height: 1.24, depth: 0.56, cornerRadius: 0.08, bevel: 0.025)
        swBody.materials = [darkHardware]
        let swNode = SCNNode(geometry: swBody)
        swNode.simdPosition = switchPos - SIMD3(0, 0.62, 0)
        swNode.castsShadow = true
        root.addChildNode(swNode)

        let paddleGeo = SCNBox(width: 0.10, height: 0.54, length: 0.30, chamferRadius: 0.015)
        paddleGeo.materials = [glossBlackMetal]
        let paddleNode = SCNNode(geometry: paddleGeo)
        paddleNode.position = SCNVector3(-0.20, 0.62, 0)
        paddleNode.eulerAngles.z = 0.16
        swNode.addChildNode(paddleNode)

        let dropCordPts = MeshBuilder.catmullRom([
            switchPos + SIMD3(0, -0.58, 0),
            switchPos + SIMD3(0.05, -4.50, -0.35),
            switchPos + SIMD3(0.35, -14.0, -1.20),
        ], samplesPerSegment: 5)
        let dropCordGeo = MeshBuilder.tube(points: dropCordPts, radius: 0.075, segments: 8)
        dropCordGeo.materials = [cordMat]
        root.addChildNode(SCNNode(geometry: dropCordGeo))

        // 5. Glossy white enamel inner dome reflector (matches real lamp interior) & frosted bulb
        let reflectorMat = SCNMaterial()
        reflectorMat.lightingModel = .physicallyBased
        reflectorMat.diffuse.contents = NSColor(white: 0.94, alpha: 1)
        reflectorMat.emission.contents = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.58, alpha: 1)
        reflectorMat.emission.intensity = 0.14
        reflectorMat.metalness.contents = 0.04
        reflectorMat.roughness.contents = 0.16
        reflectorMat.clearCoat.contents = 0.60
        reflectorMat.clearCoatRoughness.contents = 0.10
        let reflectorProfile: [(r: Float, y: Float)] = [
            (0.00, 0.08), (1.44, 0.08), (2.06, -0.12), (2.64, -0.50),
            (3.06, -1.06), (3.28, -1.66), (3.36, -2.14),
        ]
        let reflectorGeo = MeshBuilder.lathe(profile: reflectorProfile, segments: 48)
        reflectorGeo.materials = [reflectorMat]
        let reflectorNode = SCNNode(geometry: reflectorGeo)
        reflectorNode.name = "prop.deskLamp.reflector"
        // The bulb and its reflector are the light source; they must not shadow their own light.
        reflectorNode.castsShadow = false
        head.addChildNode(reflectorNode)

        let bulbMat = SCNMaterial()
        bulbMat.lightingModel = .physicallyBased
        bulbMat.diffuse.contents = NSColor(srgbRed: 0.86, green: 0.80, blue: 0.82, alpha: 1)
        bulbMat.roughness.contents = 0.36
        bulbMat.emission.contents = NSColor(srgbRed: 1.0, green: 0.38, blue: 0.56, alpha: 1)
        bulbMat.emission.intensity = 1.40
        let bulb = SCNSphere(radius: 0.68)
        bulb.materials = [bulbMat]
        let bulbNode = SCNNode(geometry: bulb)
        bulbNode.name = "prop.deskLamp.bulb"
        bulbNode.castsShadow = false
        bulbNode.scale = SCNVector3(1.0, 1.12, 1.0)
        bulbNode.position = SCNVector3(0, -0.62, 0)
        head.addChildNode(bulbNode)

        // Downward shadowed spotlight onto pothos bowls and walnut desk
        let spot = SCNLight()
        spot.type = .spot
        spot.intensity = 740
        spot.color = NSColor(srgbRed: 1.0, green: 0.46, blue: 0.46, alpha: 1)
        spot.spotInnerAngle = 20
        spot.spotOuterAngle = 82
        spot.attenuationStartDistance = 4
        spot.attenuationEndDistance = 34
        spot.castsShadow = true
        spot.shadowMapSize = CGSize(width: 1024, height: 1024)
        spot.shadowRadius = 4.6
        spot.shadowSampleCount = 16
        spot.shadowColor = NSColor(white: 0, alpha: 0.90)
        spot.shadowBias = 0.006
        spot.zNear = 3.0
        spot.zFar = 45.0
        let spotNode = SCNNode()
        spotNode.name = "prop.deskLamp.spot"
        spotNode.light = spot
        spotNode.position = SCNVector3(0, -1.1, 0)
        spotNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        head.addChildNode(spotNode)

        // Feathered shadow-casting wall hotspot aimed behind the pothos bowls
        let wallSpot = SCNLight()
        wallSpot.type = .spot
        wallSpot.intensity = 760
        wallSpot.color = NSColor(srgbRed: 1.0, green: 0.28, blue: 0.48, alpha: 1)
        wallSpot.spotInnerAngle = 14
        wallSpot.spotOuterAngle = 92
        wallSpot.attenuationStartDistance = 2
        wallSpot.attenuationEndDistance = 30
        wallSpot.castsShadow = true
        wallSpot.shadowMapSize = CGSize(width: 1024, height: 1024)
        wallSpot.shadowRadius = 6.2
        wallSpot.shadowSampleCount = 16
        wallSpot.shadowColor = NSColor(white: 0, alpha: 0.88)
        wallSpot.shadowBias = 0.008
        wallSpot.zNear = 2.5
        wallSpot.zFar = 36.0
        let wsNode = SCNNode()
        wsNode.name = "prop.deskLamp.wallSpot"
        wsNode.light = wallSpot
        wsNode.position = SCNVector3(4.2, 13.8, -0.8)
        wsNode.look(at: SCNVector3(4.8, 7.6, -14.38))
        lamp.addChildNode(wsNode)

        let wallGlow = SCNLight()
        wallGlow.type = .omni
        wallGlow.intensity = 120
        wallGlow.color = NSColor(srgbRed: 1.0, green: 0.30, blue: 0.48, alpha: 1)
        wallGlow.attenuationStartDistance = 2
        wallGlow.attenuationEndDistance = 24
        let wgNode = SCNNode()
        wgNode.name = "prop.deskLamp.wallGlow"
        wgNode.light = wallGlow
        wgNode.position = SCNVector3(5.4, 10.2, -7.8)
        lamp.addChildNode(wgNode)
    }

}
