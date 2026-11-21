import SceneKit
import AppKit
import CoreText
import simd

extension MacMiniModel {
    // MARK: - Thermal Base, Top Apple Logo & Port Hardware

    static func buildThermalBase(into mini: SCNNode) {
        let baseMat = SCNMaterial()
        baseMat.lightingModel = .physicallyBased
        baseMat.diffuse.contents = NSColor(srgbRed: 0.045, green: 0.046, blue: 0.050, alpha: 1)
        baseMat.roughness.contents = 0.68
        baseMat.metalness.contents = 0.08

        let ventMat = SCNMaterial()
        ventMat.lightingModel = .physicallyBased
        ventMat.diffuse.contents = NSColor(srgbRed: 0.020, green: 0.021, blue: 0.024, alpha: 1)
        ventMat.roughness.contents = 0.82
        ventMat.metalness.contents = 0.05

        // Circular dark thermal pedestal supporting the tucked aluminum belly
        let profile: [(r: Float, y: Float)] = [
            (2.34, 0.00),
            (2.44, 0.00),
            (2.49, 0.04),
            (2.50, 0.14),
            (2.42, 0.16),
            (2.42, 0.28),
            (2.26, 0.30),
        ]
        let baseGeo = MeshBuilder.lathe(profile: profile, segments: 64)
        baseGeo.materials = [baseMat]
        let baseNode = SCNNode(geometry: baseGeo)
        baseNode.castsShadow = true
        mini.addChildNode(baseNode)

        // Subtle recessed dark ventilation ring inside the undercut gap
        let collarGeo = SCNCylinder(radius: 2.38, height: 0.14)
        collarGeo.materials = [ventMat]
        let collar = SCNNode(geometry: collarGeo)
        collar.position = SCNVector3(0, footLift + 0.07, 0)
        collar.castsShadow = false
        mini.addChildNode(collar)
    }

    static func buildTopAppleLogo(into mini: SCNNode) {
        let font = CTFontCreateWithName("HelveticaNeue" as CFString, 200, nil)
        var ch: [UniChar] = [0xF8FF]
        var glyph: [CGGlyph] = [0]
        guard CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1),
              let cgPath = CTFontCreatePathForGlyph(font, glyph[0], nil) else { return }

        let box = cgPath.boundingBox
        let targetH: CGFloat = 2.22 // ~33% of 6.67u top deck (matching reference photo)
        let scale = targetH / max(box.height, 1)

        var xform = CGAffineTransform(translationX: -box.midX * scale, y: -box.midY * scale)
            .scaledBy(x: scale, y: scale)
        guard let scaled = cgPath.copy(using: &xform) else { return }

        let bezier = NSBezierPath()
        scaled.applyWithBlock { elemPtr in
            let elem = elemPtr.pointee
            let pts = elem.points
            switch elem.type {
            case .moveToPoint: bezier.move(to: pts[0])
            case .addLineToPoint: bezier.line(to: pts[0])
            case .addQuadCurveToPoint:
                let cur = bezier.currentPoint
                let c1 = CGPoint(x: cur.x + 2.0 / 3.0 * (pts[0].x - cur.x), y: cur.y + 2.0 / 3.0 * (pts[0].y - cur.y))
                let c2 = CGPoint(x: pts[1].x + 2.0 / 3.0 * (pts[0].x - pts[1].x), y: pts[1].y + 2.0 / 3.0 * (pts[0].y - pts[1].y))
                bezier.curve(to: pts[1], controlPoint1: c1, controlPoint2: c2)
            case .addCurveToPoint:
                bezier.curve(to: pts[2], controlPoint1: pts[0], controlPoint2: pts[1])
            case .closeSubpath:
                bezier.close()
            @unknown default: break
            }
        }
        bezier.flatness = 0.001

        // Mirror-black glossy obsidian inlay (low metalness keeps diffuse jet black while clearCoat provides crisp glare).
        let inlayMat = SCNMaterial()
        inlayMat.lightingModel = .physicallyBased
        inlayMat.diffuse.contents = NSColor(srgbRed: 0.004, green: 0.004, blue: 0.005, alpha: 1)
        inlayMat.metalness.contents = 0.04
        inlayMat.roughness.contents = 0.06
        inlayMat.clearCoat.contents = 1.0
        inlayMat.clearCoatRoughness.contents = 0.025
        inlayMat.specular.contents = NSColor(white: 0.92, alpha: 1)

        let shape = SCNShape(path: bezier, extrusionDepth: 0.0018)
        shape.chamferRadius = 0.0005
        shape.materials = [inlayMat]

        let logoNode = SCNNode(geometry: shape)
        logoNode.eulerAngles.x = -.pi / 2
        logoNode.position = SCNVector3(0, totalH + 0.0002, 0)
        logoNode.castsShadow = false
        mini.addChildNode(logoNode)
    }

    static func buildFrontPortHardware(into mini: SCNNode) {
        let sleeveMat = SCNMaterial()
        sleeveMat.lightingModel = .physicallyBased
        sleeveMat.diffuse.contents = NSColor(srgbRed: 0.045, green: 0.047, blue: 0.052, alpha: 1)
        sleeveMat.metalness.contents = 0.65
        sleeveMat.roughness.contents = 0.36

        let cavityBlack = SCNMaterial()
        cavityBlack.lightingModel = .physicallyBased
        cavityBlack.diffuse.contents = NSColor(white: 0.010, alpha: 1)
        cavityBlack.roughness.contents = 0.88

        let tongueMat = SCNMaterial()
        tongueMat.lightingModel = .physicallyBased
        tongueMat.diffuse.contents = NSColor(srgbRed: 0.11, green: 0.115, blue: 0.125, alpha: 1)
        tongueMat.roughness.contents = 0.48

        let contactPinMat = SCNMaterial()
        contactPinMat.lightingModel = .physicallyBased
        contactPinMat.diffuse.contents = NSColor(srgbRed: 0.58, green: 0.46, blue: 0.22, alpha: 1)
        contactPinMat.metalness.contents = 0.85
        contactPinMat.roughness.contents = 0.28

        // 1. Vertical USB-C receptacles (recessed stainless sleeves, dark rear wall, internal vertical tongue + pins)
        for px in usbX {
            let sleeve = stadiumTube(width: 0.120, height: 0.428, wallThickness: 0.010, depth: 0.28, material: sleeveMat)
            sleeve.position = SCNVector3(px, portY, halfD - 0.17)
            sleeve.castsShadow = false
            mini.addChildNode(sleeve)

            let backPath = stadiumPath(width: 0.122, height: 0.430)
            let back = SCNShape(path: backPath, extrusionDepth: 0.02)
            back.materials = [cavityBlack]
            let backNode = SCNNode(geometry: back)
            backNode.position = SCNVector3(px, portY, halfD - 0.32)
            backNode.castsShadow = false
            mini.addChildNode(backNode)

            let tongue = SCNBox(width: 0.028, height: 0.27, length: 0.22, chamferRadius: 0.008)
            tongue.materials = [tongueMat]
            let tNode = SCNNode(geometry: tongue)
            tNode.position = SCNVector3(px, portY, halfD - 0.165)
            tNode.castsShadow = false
            mini.addChildNode(tNode)

            // Subtle contact strips along the vertical tongue faces
            let pinStrip = SCNBox(width: 0.032, height: 0.21, length: 0.14, chamferRadius: 0.002)
            pinStrip.materials = [contactPinMat]
            let pNode = SCNNode(geometry: pinStrip)
            pNode.position = SCNVector3(px, portY, halfD - 0.16)
            pNode.castsShadow = false
            mini.addChildNode(pNode)
        }

        // 2. Flush warm-white power status LED pinhole
        let ledMat = SCNMaterial()
        ledMat.lightingModel = .physicallyBased
        ledMat.diffuse.contents = NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1)
        ledMat.emission.contents = NSColor(srgbRed: 0.98, green: 0.98, blue: 0.95, alpha: 1)
        ledMat.emission.intensity = 0.95
        ledMat.roughness.contents = 0.15

        let ledGeo = SCNCylinder(radius: 0.0185, height: 0.010)
        ledGeo.materials = [ledMat]
        let ledNode = SCNNode(geometry: ledGeo)
        ledNode.eulerAngles.x = .pi / 2
        ledNode.position = SCNVector3(ledX, portY, halfD - 0.008)
        ledNode.castsShadow = false
        mini.addChildNode(ledNode)

        // 3. Recessed 3.5 mm headphone jack bore
        let bore = SCNCylinder(radius: 0.095, height: 0.42)
        bore.materials = [cavityBlack]
        let boreNode = SCNNode(geometry: bore)
        boreNode.eulerAngles.x = .pi / 2
        boreNode.position = SCNVector3(jackX, portY, halfD - 0.225)
        boreNode.castsShadow = false
        mini.addChildNode(boreNode)
    }

    static func buildRearIOHardware(into mini: SCNNode) {
        let bayMat = SCNMaterial()
        bayMat.lightingModel = .physicallyBased
        bayMat.diffuse.contents = NSColor(srgbRed: 0.04, green: 0.042, blue: 0.046, alpha: 1)
        bayMat.roughness.contents = 0.62

        let metalRimMat = SCNMaterial()
        metalRimMat.lightingModel = .physicallyBased
        metalRimMat.diffuse.contents = NSColor(white: 0.38, alpha: 1)
        metalRimMat.metalness.contents = 0.85
        metalRimMat.roughness.contents = 0.28

        let darkInterior = SCNMaterial()
        darkInterior.lightingModel = .physicallyBased
        darkInterior.diffuse.contents = NSColor(white: 0.015, alpha: 1)
        darkInterior.roughness.contents = 0.8

        let brassPinMat = SCNMaterial()
        brassPinMat.lightingModel = .physicallyBased
        brassPinMat.diffuse.contents = NSColor(srgbRed: 0.80, green: 0.66, blue: 0.30, alpha: 1)
        brassPinMat.metalness.contents = 0.95
        brassPinMat.roughness.contents = 0.2

        let bayZ = -halfD + 0.045
        let bayY = rearBayTile.cy

        // Dark rear I/O insert panel backing
        let bayPath = NSBezierPath(
            roundedRect: NSRect(x: -1.99, y: -0.37, width: 3.98, height: 0.74),
            xRadius: 0.10, yRadius: 0.10
        )
        bayPath.flatness = 0.002
        let bayShape = SCNShape(path: bayPath, extrusionDepth: 0.02)
        bayShape.materials = [bayMat]
        let bayNode = SCNNode(geometry: bayShape)
        bayNode.position = SCNVector3(0, bayY, bayZ)
        bayNode.castsShadow = false
        mini.addChildNode(bayNode)

        let portFaceZ = bayZ - 0.012

        // AC C8 figure-8 power socket (rear left when viewed from behind -> +x)
        let acFrame = SCNBox(width: 0.62, height: 0.36, length: 0.025, chamferRadius: 0.08)
        acFrame.materials = [darkInterior]
        let acNode = SCNNode(geometry: acFrame)
        acNode.position = SCNVector3(1.42, bayY, portFaceZ)
        acNode.castsShadow = false
        mini.addChildNode(acNode)

        let pinGeo = SCNCylinder(radius: 0.032, height: 0.035)
        pinGeo.materials = [brassPinMat]
        for dx: Float in [-0.12, 0.12] {
            let p = SCNNode(geometry: pinGeo)
            p.eulerAngles.x = .pi / 2
            p.position = SCNVector3(1.42 + dx, bayY, portFaceZ - 0.002)
            p.castsShadow = false
            mini.addChildNode(p)
        }

        // Gigabit Ethernet RJ-45
        let ethFrame = SCNBox(width: 0.56, height: 0.44, length: 0.015, chamferRadius: 0.02)
        ethFrame.materials = [metalRimMat]
        let ethFrameNode = SCNNode(geometry: ethFrame)
        ethFrameNode.position = SCNVector3(0.58, bayY, portFaceZ + 0.002)
        ethFrameNode.castsShadow = false
        mini.addChildNode(ethFrameNode)

        let ethHole = SCNBox(width: 0.48, height: 0.36, length: 0.020, chamferRadius: 0.015)
        ethHole.materials = [darkInterior]
        let ethHoleNode = SCNNode(geometry: ethHole)
        ethHoleNode.position = SCNVector3(0.58, bayY, portFaceZ - 0.002)
        ethHoleNode.castsShadow = false
        mini.addChildNode(ethHoleNode)

        // HDMI 2.1
        let hdmiFrame = SCNBox(width: 0.54, height: 0.21, length: 0.015, chamferRadius: 0.02)
        hdmiFrame.materials = [metalRimMat]
        let hdmiFrameNode = SCNNode(geometry: hdmiFrame)
        hdmiFrameNode.position = SCNVector3(-0.22, bayY, portFaceZ + 0.002)
        hdmiFrameNode.castsShadow = false
        mini.addChildNode(hdmiFrameNode)

        let hdmiHole = SCNBox(width: 0.47, height: 0.14, length: 0.020, chamferRadius: 0.015)
        hdmiHole.materials = [darkInterior]
        let hdmiHoleNode = SCNNode(geometry: hdmiHole)
        hdmiHoleNode.position = SCNVector3(-0.22, bayY, portFaceZ - 0.002)
        hdmiHoleNode.castsShadow = false
        mini.addChildNode(hdmiHoleNode)

        // 3× Horizontal Thunderbolt 4 (USB-C) ports
        for tx: Float in [-0.78, -1.24, -1.70] {
            let rim = SCNShape(path: stadiumPath(width: 0.38, height: 0.15), extrusionDepth: 0.012)
            rim.materials = [metalRimMat]
            let rNode = SCNNode(geometry: rim)
            rNode.position = SCNVector3(tx, bayY, portFaceZ + 0.001)
            rNode.castsShadow = false
            mini.addChildNode(rNode)

            let hole = SCNShape(path: stadiumPath(width: 0.33, height: 0.105), extrusionDepth: 0.016)
            hole.materials = [darkInterior]
            let hNode = SCNNode(geometry: hole)
            hNode.position = SCNVector3(tx, bayY, portFaceZ - 0.003)
            hNode.castsShadow = false
            mini.addChildNode(hNode)
        }
    }

    static func stadiumPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let r = min(width, height) / 2
        let path = NSBezierPath(
            roundedRect: NSRect(x: -width / 2, y: -height / 2, width: width, height: height),
            xRadius: r, yRadius: r
        )
        path.flatness = 0.002
        return path
    }

    static func stadiumTube(
        width: CGFloat, height: CGFloat, wallThickness: CGFloat, depth: CGFloat, material: SCNMaterial
    ) -> SCNNode {
        let outer = stadiumPath(width: width + wallThickness * 2, height: height + wallThickness * 2)
        let inner = stadiumPath(width: width, height: height)
        outer.append(inner)
        outer.windingRule = .evenOdd
        let shape = SCNShape(path: outer, extrusionDepth: depth)
        shape.materials = [material]
        return SCNNode(geometry: shape)
    }
}
