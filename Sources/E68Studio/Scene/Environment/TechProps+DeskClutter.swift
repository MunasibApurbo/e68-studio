import SceneKit
import AppKit
import CoreGraphics
import simd

extension TechProps {

    // MARK: - Apple Pencil & Stitched Terracotta Leather Sleeve (Front-Left Mat)

    static func buildApplePencilAndSleeve(into root: SCNNode) {
        let group = SCNNode()
        group.name = "prop.applePencilSet"
        root.addChildNode(group)

        // Pebbled terracotta/burnt-orange leather sleeve texture with dark perimeter saddle stitching.
        let sleeveMat = SCNMaterial()
        sleeveMat.lightingModel = .physicallyBased
        let sleeveTex = makeOrangeLeatherTexture()
        sleeveMat.diffuse.contents = sleeveTex.diffuse
        sleeveMat.normal.contents = sleeveTex.normal
        sleeveMat.normal.intensity = 0.42
        sleeveMat.roughness.contents = 0.54
        sleeveMat.metalness.contents = 0.0

        let sleevePos = SIMD3<Float>(-17.8, DeskRoomAndMat.matTopY, 4.95)
        let sleeveYaw: Float = 0.98
        let sleeveW: Float = 1.24
        let sleeveH: Float = 0.24
        let sleeveL: Float = 8.10

        DeskRoomAndMat.addContactShadow(
            at: SIMD3(sleevePos.x, DeskRoomAndMat.matTopY + 0.004, sleevePos.z),
            radiusX: 1.05,
            radiusZ: 4.35,
            opacity: 0.46,
            yaw: sleeveYaw,
            into: group
        )

        let sleeveNode = SCNNode()
        sleeveNode.simdPosition = sleevePos
        sleeveNode.eulerAngles.y = CGFloat(sleeveYaw)
        group.addChildNode(sleeveNode)

        let bodyGeo = MeshBuilder.roundedSlab(
            width: sleeveW,
            height: sleeveH,
            depth: sleeveL,
            cornerRadius: 0.56,
            bevel: 0.075,
            cornerSegments: 10,
            planarUVs: true
        )
        bodyGeo.materials = [sleeveMat]
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.castsShadow = true
        sleeveNode.addChildNode(bodyNode)

        // Raised stitched pocket collar & dark recessed opening at upper-left end (-Z local).
        let collarGeo = MeshBuilder.roundedSlab(
            width: sleeveW * 0.94,
            height: 0.085,
            depth: sleeveL * 0.88,
            cornerRadius: 0.46,
            bevel: 0.032,
            cornerSegments: 8,
            planarUVs: true
        )
        collarGeo.materials = [sleeveMat]
        let collarNode = SCNNode(geometry: collarGeo)
        collarNode.position = SCNVector3(0, sleeveH - 0.015, 0.28)
        collarNode.castsShadow = true
        sleeveNode.addChildNode(collarNode)

        let innerMat = SCNMaterial()
        innerMat.lightingModel = .physicallyBased
        innerMat.diffuse.contents = NSColor(srgbRed: 0.16, green: 0.08, blue: 0.05, alpha: 1)
        innerMat.roughness.contents = 0.88
        let slotGeo = MeshBuilder.roundedSlab(
            width: 0.72,
            height: 0.12,
            depth: 0.34,
            cornerRadius: 0.12,
            bevel: 0.015
        )
        slotGeo.materials = [innerMat]
        let slotNode = SCNNode(geometry: slotGeo)
        slotNode.position = SCNVector3(0, sleeveH - 0.035, -sleeveL * 0.425)
        sleeveNode.addChildNode(slotNode)

        // Apple Pencil (1st Gen) resting flat & parallel beside the upper-right side of the sleeve (IMG_1848).
        let pPos = SIMD3<Float>(-16.5, DeskRoomAndMat.matTopY + 0.228, 3.70)
        let pYaw: Float = 0.95
        DeskRoomAndMat.addContactShadow(
            at: SIMD3(pPos.x, DeskRoomAndMat.matTopY + 0.004, pPos.z),
            radiusX: 0.38,
            radiusZ: 4.70,
            opacity: 0.44,
            yaw: pYaw,
            into: group
        )

        let pencil = SCNNode()
        pencil.simdPosition = pPos
        pencil.eulerAngles.y = CGFloat(pYaw)
        group.addChildNode(pencil)

        let whiteGloss = SCNMaterial()
        whiteGloss.lightingModel = .physicallyBased
        whiteGloss.diffuse.contents = NSColor(srgbRed: 0.85, green: 0.855, blue: 0.86, alpha: 1)
        whiteGloss.roughness.contents = 0.14
        whiteGloss.clearCoat.contents = 0.65
        whiteGloss.clearCoatRoughness.contents = 0.06

        let chromeMat = SCNMaterial()
        chromeMat.lightingModel = .physicallyBased
        chromeMat.diffuse.contents = NSColor(white: 0.80, alpha: 1)
        chromeMat.metalness.contents = 0.94
        chromeMat.roughness.contents = 0.14

        let nibMat = SCNMaterial()
        nibMat.lightingModel = .physicallyBased
        nibMat.diffuse.contents = NSColor(srgbRed: 0.72, green: 0.73, blue: 0.74, alpha: 1)
        nibMat.roughness.contents = 0.42

        // Total length ~ 9.22 u (175.7 mm), radius 0.228 u (8.7 mm OD), oriented along Z.
        let r: Float = 0.228
        let shaftLen: Float = 7.45
        let shaftGeo = SCNCylinder(radius: CGFloat(r), height: CGFloat(shaftLen))
        shaftGeo.radialSegmentCount = 28
        shaftGeo.materials = [whiteGloss]
        let shaftNode = SCNNode(geometry: shaftGeo)
        shaftNode.eulerAngles.x = .pi / 2
        shaftNode.castsShadow = true
        pencil.addChildNode(shaftNode)

        // Chrome band + rounded rear magnetic cap (-Z end)
        let ringGeo = SCNCylinder(radius: CGFloat(r + 0.004), height: 0.09)
        ringGeo.radialSegmentCount = 28
        ringGeo.materials = [chromeMat]
        let ringNode = SCNNode(geometry: ringGeo)
        ringNode.eulerAngles.x = .pi / 2
        ringNode.position = SCNVector3(0, 0, -shaftLen * 0.5 - 0.045)
        pencil.addChildNode(ringNode)

        let capGeo = SCNCapsule(capRadius: CGFloat(r), height: 0.86)
        capGeo.radialSegmentCount = 24
        capGeo.materials = [whiteGloss]
        let capNode = SCNNode(geometry: capGeo)
        capNode.eulerAngles.x = .pi / 2
        capNode.position = SCNVector3(0, 0, -shaftLen * 0.5 - 0.36)
        capNode.castsShadow = true
        pencil.addChildNode(capNode)

        // Tapered white cone + POM writing tip (+Z front-right end)
        let coneH: Float = 0.82
        let coneGeo = SCNCone(topRadius: 0.072, bottomRadius: CGFloat(r), height: CGFloat(coneH))
        coneGeo.radialSegmentCount = 28
        coneGeo.materials = [whiteGloss]
        let coneNode = SCNNode(geometry: coneGeo)
        coneNode.eulerAngles.x = .pi / 2
        coneNode.position = SCNVector3(0, 0, shaftLen * 0.5 + coneH * 0.5)
        coneNode.castsShadow = true
        pencil.addChildNode(coneNode)

        let tipH: Float = 0.24
        let tipGeo = SCNCone(topRadius: 0.022, bottomRadius: 0.072, height: CGFloat(tipH))
        tipGeo.radialSegmentCount = 20
        tipGeo.materials = [nibMat]
        let tipNode = SCNNode(geometry: tipGeo)
        tipNode.eulerAngles.x = .pi / 2
        tipNode.position = SCNVector3(0, 0, shaftLen * 0.5 + coneH + tipH * 0.5)
        pencil.addChildNode(tipNode)
    }

    // MARK: - Carved Coconut-Shell / Dark Wood Footed Goblet (Front-Right Desk)

    static func buildCoconutGoblet(into root: SCNNode) {
        let pos = SIMD3<Float>(30.8, 0.0, 5.4)
        DeskRoomAndMat.addContactShadow(
            at: SIMD3(pos.x, 0.006, pos.z),
            radiusX: 2.05,
            radiusZ: 2.05,
            opacity: 0.56,
            into: root
        )

        let group = SCNNode()
        group.name = "prop.coconutGoblet"
        group.simdPosition = pos
        root.addChildNode(group)

        let tex = makeCoconutShellTexture()
        let shellMat = SCNMaterial()
        shellMat.lightingModel = .physicallyBased
        shellMat.diffuse.contents = tex.diffuse
        shellMat.normal.contents = tex.normal
        shellMat.normal.intensity = 0.36
        shellMat.roughness.contents = 0.34
        shellMat.clearCoat.contents = 0.28
        shellMat.clearCoatRoughness.contents = 0.22

        // Turned wooden foot + stemmed chalice profile with slightly wider hollow thick-walled coconut bowl.
        let profile: [(r: Float, y: Float)] = [
            (0.01, 0.00),
            (1.46, 0.00),
            (1.50, 0.14),
            (1.40, 0.26),
            (0.95, 0.44),
            (0.64, 0.72),
            (0.58, 1.05),
            (0.92, 1.28),
            (1.66, 1.72),
            (2.26, 2.38),
            (2.48, 3.06),
            (2.50, 3.60),
            (2.40, 3.72),
            (2.28, 3.68),
            (2.20, 3.08),
            (1.96, 2.46),
            (1.42, 1.94),
            (0.74, 1.62),
            (0.01, 1.54),
        ]
        let geo = MeshBuilder.lathe(profile: profile, segments: 48)
        geo.materials = [shellMat]
        let node = SCNNode(geometry: geo)
        node.castsShadow = true
        group.addChildNode(node)
    }

    // MARK: - Loose White USB-C Cable Tip (Back-Left of Mat Beside AirPods)

    static func buildLooseWhiteUSBCTip(into root: SCNNode) {
        let whiteCable = SCNMaterial()
        whiteCable.lightingModel = .physicallyBased
        whiteCable.diffuse.contents = NSColor(srgbRed: 0.82, green: 0.82, blue: 0.815, alpha: 1)
        whiteCable.roughness.contents = 0.46

        let chromeMat = SCNMaterial()
        chromeMat.lightingModel = .physicallyBased
        chromeMat.diffuse.contents = NSColor(white: 0.78, alpha: 1)
        chromeMat.metalness.contents = 0.92
        chromeMat.roughness.contents = 0.16

        let matY = DeskRoomAndMat.matTopY + 0.072
        let path = MeshBuilder.catmullRom([
            SIMD3(-18.2, 0.08, -24.5),
            SIMD3(-18.8, 0.08, -16.2),
            SIMD3(-18.4, matY + 0.06, -10.8),
            SIMD3(-17.4, matY, -9.1),
            SIMD3(-15.5, matY, -8.5),
        ], samplesPerSegment: 8)
        let cordGeo = MeshBuilder.tube(points: path, radius: 0.072, segments: 10)
        cordGeo.materials = [whiteCable]
        let cordNode = SCNNode(geometry: cordGeo)
        cordNode.castsShadow = true
        root.addChildNode(cordNode)

        let endPt = path.last ?? SIMD3(-15.5, matY, -8.5)
        let boot = SCNNode()
        boot.simdPosition = endPt
        boot.eulerAngles.y = 0.34
        root.addChildNode(boot)

        // USB-C plug, to scale (1 unit = 19.05 mm): a rounded white overmold about 11 x 6 x 19 mm, then the
        // 8.4 x 2.6 mm metal shell with fully rounded sides and the dark opening at its tip.
        let sleeveGeo = MeshBuilder.roundedSlab(width: 0.58, height: 0.30, depth: 1.00, cornerRadius: 0.14, bevel: 0.05)
        sleeveGeo.materials = [whiteCable]
        let sleeve = SCNNode(geometry: sleeveGeo)
        sleeve.position = SCNVector3(0, 0.078, 0.46)
        sleeve.castsShadow = true
        boot.addChildNode(sleeve)

        let shellGeo = MeshBuilder.roundedSlab(width: 0.44, height: 0.136, depth: 0.36, cornerRadius: 0.066, bevel: 0.012)
        shellGeo.materials = [chromeMat]
        let shell = SCNNode(geometry: shellGeo)
        shell.position = SCNVector3(0, 0.078, 1.13)
        boot.addChildNode(shell)

        let openingMat = SCNMaterial()
        openingMat.lightingModel = .physicallyBased
        openingMat.diffuse.contents = NSColor(white: 0.02, alpha: 1)
        openingMat.roughness.contents = 0.6
        let openingGeo = MeshBuilder.roundedSlab(width: 0.36, height: 0.066, depth: 0.02, cornerRadius: 0.03, bevel: 0.004)
        openingGeo.materials = [openingMat]
        let opening = SCNNode(geometry: openingGeo)
        opening.position = SCNVector3(0, 0.078, 1.312)
        boot.addChildNode(opening)
    }

    // MARK: - Procedural Textures for Desk Clutter

    private static func makeOrangeLeatherTexture() -> (diffuse: CGImage, normal: CGImage) {
        let w = 256, h = 256
        var hf = [Float](repeating: 0, count: w * h)
        let diffuse = DeskTextures.makePixelImage(w, h) { ptr, _, _, _ in
            for row in 0..<h {
                let fy = Float(row) / Float(h - 1)
                let rowOff = row * w
                for col in 0..<w {
                    let fx = Float(col) / Float(w - 1)
                    let pebble = DeskTextures.tileableNoise2D(fx * 28, fy * 28, periodX: 28, periodY: 28, 0xA91E)
                    let micro = DeskTextures.hash2D(col, row, 0xA91F)
                    let grain = pebble * 0.72 + micro * 0.28
                    let idx = rowOff + col
                    hf[idx] = grain

                    // Saddle stitch margin border inset around leather perimeter.
                    let mx = min(fx, 1.0 - fx)
                    let my = min(fy, 1.0 - fy)
                    let mMin = min(mx, my)
                    let onMargin = abs(mMin - 0.048) < 0.009
                    let dashPhase = ((abs(mx - 0.048) < 0.009) ? (fy * 34.0) : (fx * 34.0))
                    let stitchDash = onMargin && (sin(dashPhase * .pi * 2.0) > 0.15)

                    let shade = 0.82 + grain * 0.28
                    var r = 0.78 * shade
                    var g = 0.30 * shade
                    var b = 0.13 * shade
                    if stitchDash {
                        r *= 0.36; g *= 0.36; b *= 0.36
                        hf[idx] += 0.35
                    }
                    let p = idx * 4
                    ptr[p]     = DeskTextures.clampByte(r)
                    ptr[p + 1] = DeskTextures.clampByte(g)
                    ptr[p + 2] = DeskTextures.clampByte(b)
                    ptr[p + 3] = 255
                }
            }
        }
        let normal = DeskTextures.normalFromHeight(hf, width: w, height: h, strength: 1.45)
        return (diffuse, normal)
    }

    private static func makeCoconutShellTexture() -> (diffuse: CGImage, normal: CGImage) {
        let w = 512, h = 512
        var hf = [Float](repeating: 0, count: w * h)
        let diffuse = DeskTextures.makePixelImage(w, h) { ptr, _, _, _ in
            for row in 0..<h {
                let v = Float(row) / Float(h - 1)
                let rowOff = row * w
                // Interior profile runs along the inner wall (v > 0.62 in lathe UV v): dark coconut brown with radial fibrous streaks.
                let isInterior = DeskTextures.smoothstep(0.60, 0.66, v)
                let latheGroove = sin(v * 76.0) * 0.5 + 0.5
                let rimFade = DeskTextures.smoothstep(0.64, 0.74, v)
                let bottomShade = 1.0 - 0.28 * DeskTextures.smoothstep(0.84, 1.0, v)
                for col in 0..<w {
                    let u = Float(col) / Float(w - 1)
                    let mottle = DeskTextures.tileableNoise2D(u * 10, v * 14, periodX: 10, periodY: 14, 0xC0C0)
                    let fiberCoarse = DeskTextures.tileableNoise2D(u * 68, v * 5, periodX: 68, periodY: 5, 0xC0C1)
                    let fiberMed = DeskTextures.tileableNoise2D(u * 140, v * 10, periodX: 140, periodY: 10, 0xC0C2)
                    let fiberFine = DeskTextures.tileableNoise2D(u * 230, v * 22, periodX: 230, periodY: 22, 0xC0C3)
                    let fiberMix = fiberCoarse * 0.52 + fiberMed * 0.33 + fiberFine * 0.15
                    let streak = DeskTextures.smoothstep(0.55, 0.82, fiberMix) * rimFade

                    let outR: Float = 0.088 + mottle * 0.042 + latheGroove * 0.015
                    let outG: Float = 0.048 + mottle * 0.024 + latheGroove * 0.008
                    let outB: Float = 0.025 + mottle * 0.013 + latheGroove * 0.004

                    let inBase = (0.125 + mottle * 0.045) * bottomShade
                    let inR: Float = inBase + streak * 0.30
                    let inG: Float = inBase * 0.56 + streak * 0.19
                    let inB: Float = inBase * 0.30 + streak * 0.108

                    let r = outR * (1 - isInterior) + inR * isInterior
                    let g = outG * (1 - isInterior) + inG * isInterior
                    let b = outB * (1 - isInterior) + inB * isInterior

                    let idx = rowOff + col
                    let outerH = mottle * 0.35 + latheGroove * 0.20
                    let innerH = fiberMix * 0.65 + mottle * 0.20
                    hf[idx] = outerH * (1 - isInterior) + innerH * isInterior
                    let p = idx * 4
                    ptr[p]     = DeskTextures.clampByte(r)
                    ptr[p + 1] = DeskTextures.clampByte(g)
                    ptr[p + 2] = DeskTextures.clampByte(b)
                    ptr[p + 3] = 255
                }
            }
        }
        let normal = DeskTextures.normalFromHeight(hf, width: w, height: h, strength: 1.05)
        return (diffuse, normal)
    }
}
