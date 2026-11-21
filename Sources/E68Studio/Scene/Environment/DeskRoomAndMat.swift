import SceneKit
import AppKit
import simd

/// Builds the 3D desk, left room corner & textured plaster back wall, toggleable desk lamp
/// optical wall glow, under-desk purple LED & rattan basket, recessed outlet, contact shadows,
/// and PCB Ukiru desk mat (microfiber twill normal + continuous arc-length overlock stitched rim).
enum DeskRoomAndMat {

    static let matTopY: Float = 0.21
    static let matCenter = SIMD2<Float>(2.4, -0.5)
    static let matSize = SIMD2<Float>(47.24, 21.00) // 900 x 400 mm in 1u = 19.05mm

    /// Shared rear corridor coordinates (contracted with `lamp-artist` and `TechProps`):
    /// desk rear edge = -25.60, wall front face = -25.88 -> 0.28u cable corridor at z = -25.70.
    static let deskRearEdgeZ: Float = -25.60
    static let backWallZ: Float = -25.88
    static let leftCornerX: Float = -38.88

    private static let sharedShadowTex: CGImage = {
        let w = 128, h = 128
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let grad = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [
                NSColor(white: 0, alpha: 0.56).cgColor,
                NSColor(white: 0, alpha: 0.20).cgColor,
                NSColor(white: 0, alpha: 0.0).cgColor,
            ] as CFArray,
            locations: [0.0, 0.45, 1.0]
        )!
        ctx.drawRadialGradient(
            grad,
            startCenter: CGPoint(x: 64, y: 64), startRadius: 4,
            endCenter: CGPoint(x: 64, y: 64), endRadius: 58,
            options: []
        )
        return ctx.makeImage()!
    }()

    /// Places a soft ambient-occlusion contact shadow decal underneath any desk or mat object.
    static func addContactShadow(
        at pos: SIMD3<Float>,
        radiusX: Float,
        radiusZ: Float,
        opacity: Float = 0.55,
        yaw: Float = 0,
        into root: SCNNode
    ) {
        let plane = SCNPlane(width: CGFloat(radiusX * 2), height: CGFloat(radiusZ * 2))
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = sharedShadowTex
        mat.transparency = CGFloat(opacity)
        mat.blendMode = .alpha
        mat.writesToDepthBuffer = false
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        node.eulerAngles = SCNVector3(-Float.pi / 2, yaw, 0)
        node.castsShadow = false
        node.renderingOrder = 1
        root.addChildNode(node)
    }

    static func build(into root: SCNNode, matTexture: Any?, keyboardBacklightSync: inout [SCNNode]) {
        buildRoomAndDesk(into: root)
        buildUkiruMat(into: root, texture: matTexture)
    }

    // MARK: - Desk & Room

    private static func buildRoomAndDesk(into root: SCNNode) {
        let wood = DeskTextures.walnutWood()
        // The scan covers about a metre of veneer: once along the desk's width, grain running lengthwise.
        let woodScale = DeskTextures.usesScannedWood ? SCNMatrix4MakeScale(1.5, 0.75, 1) : SCNMatrix4MakeScale(3.0, 2.2, 1)
        let deskMat = SCNMaterial()
        deskMat.lightingModel = .physicallyBased
        deskMat.diffuse.contents = wood.diffuse
        deskMat.diffuse.wrapS = .repeat
        deskMat.diffuse.wrapT = .repeat
        deskMat.diffuse.contentsTransform = woodScale
        deskMat.diffuse.mipFilter = .linear
        deskMat.diffuse.maxAnisotropy = 8
        deskMat.roughness.contents = wood.roughness
        deskMat.roughness.wrapS = .repeat
        deskMat.roughness.wrapT = .repeat
        deskMat.roughness.contentsTransform = woodScale
        deskMat.roughness.mipFilter = .linear
        deskMat.roughness.maxAnisotropy = 8
        deskMat.normal.contents = wood.normal
        deskMat.normal.wrapS = .repeat
        deskMat.normal.wrapT = .repeat
        deskMat.normal.contentsTransform = woodScale
        deskMat.normal.mipFilter = .linear
        deskMat.normal.maxAnisotropy = 8
        deskMat.normal.intensity = DeskTextures.usesScannedWood ? 0.55 : 0.16
        deskMat.metalness.contents = 0.02
        deskMat.clearCoat.contents = 0.09
        deskMat.clearCoatRoughness.contents = 0.42

        // Dark espresso-walnut desk top (~156 cm wide x 74 cm deep x 2.6 cm thick; rear edge at z = -25.60)
        let deskWidth: Float = 82.0
        let deskDepth: Float = 38.8
        let deskThick: Float = 1.4
        let deskCenterZ: Float = deskRearEdgeZ + deskDepth * 0.5 // -6.2
        let deskGeo = MeshBuilder.roundedSlab(
            width: deskWidth,
            height: deskThick,
            depth: deskDepth,
            cornerRadius: 0.45,
            bevel: 0.08,
            planarUVs: true
        )
        deskGeo.materials = [deskMat]
        let deskNode = SCNNode(geometry: deskGeo)
        deskNode.position = SCNVector3(matCenter.x, -deskThick, deskCenterZ)
        deskNode.castsShadow = true
        root.addChildNode(deskNode)

        // Matte black powder-coated steel under-frame & legs clamped flush to floorNode (y = -26.0)
        let steelMat = SCNMaterial()
        steelMat.lightingModel = .physicallyBased
        steelMat.diffuse.contents = NSColor(white: 0.065, alpha: 1)
        steelMat.roughness.contents = 0.55
        steelMat.metalness.contents = 0.72

        let rail = SCNBox(width: CGFloat(deskWidth - 6), height: 1.5, length: 1.6, chamferRadius: 0.05)
        rail.materials = [steelMat]
        for zOff: Float in [-13.5, 11.5] {
            let rNode = SCNNode(geometry: rail)
            rNode.position = SCNVector3(matCenter.x, -deskThick - 0.75, deskCenterZ + zOff)
            rNode.castsShadow = true
            root.addChildNode(rNode)
        }

        let floorY: Float = -26.0
        let legHeight: Float = (-deskThick) - floorY // 24.6u exact span down to floor
        let legGeo = SCNBox(width: 2.2, height: CGFloat(legHeight), length: 2.2, chamferRadius: 0.06)
        legGeo.materials = [steelMat]
        let padGeo = SCNCylinder(radius: 1.15, height: 0.16)
        padGeo.materials = [steelMat]
        for xOff: Float in [-34.0, 34.0] {
            for zOff: Float in [-14.0, 11.5] {
                let leg = SCNNode(geometry: legGeo)
                leg.position = SCNVector3(matCenter.x + xOff, floorY + legHeight * 0.5, deskCenterZ + zOff)
                leg.castsShadow = true
                root.addChildNode(leg)

                let pad = SCNNode(geometry: padGeo)
                pad.position = SCNVector3(matCenter.x + xOff, floorY + 0.08, deskCenterZ + zOff)
                root.addChildNode(pad)
            }
        }

        // Slim matte-black under-desk cable tray so rear cords tuck cleanly under the desk
        let trayGeo = SCNBox(width: 70.0, height: 0.9, length: 2.4, chamferRadius: 0.12)
        trayGeo.materials = [steelMat]
        let trayNode = SCNNode(geometry: trayGeo)
        trayNode.position = SCNVector3(matCenter.x, -deskThick - 1.0, deskRearEdgeZ + 1.35)
        trayNode.castsShadow = true
        root.addChildNode(trayNode)

        // Room-only geometry (floor tile, plaster walls, outlet, ceiling corner shadow) isolated
        // inside `env.room.root` so switching into outdoor/fantasy scenarios hides only the room shell.
        let roomRoot = SCNNode()
        roomRoot.name = "env.room.root"
        root.addChildNode(roomRoot)

        // Cool grey marbled tile floor visible below desk
        let floorMat = SCNMaterial()
        floorMat.lightingModel = .physicallyBased
        floorMat.diffuse.contents = NSColor(srgbRed: 0.46, green: 0.48, blue: 0.50, alpha: 1)
        floorMat.roughness.contents = 0.48
        let floorPlane = SCNPlane(width: 240, height: 200)
        floorPlane.widthSegmentCount = 12
        floorPlane.heightSegmentCount = 10
        floorPlane.materials = [floorMat]
        let floorNode = SCNNode(geometry: floorPlane)
        floorNode.eulerAngles.x = -.pi / 2
        floorNode.position = SCNVector3(matCenter.x, floorY, 40.0)
        roomRoot.addChildNode(floorNode)

        // Textured matte off-white plaster walls enclosing the room (back wall at z = -25.88 + left corner at x = -38.88)
        let plaster = DeskTextures.plasterWall()
        func makePlasterWallMaterial(scaleX: CGFloat, normalIntensity: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = plaster.diffuse
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(scaleX, 5.2, 1)
            m.diffuse.mipFilter = .linear
            m.diffuse.maxAnisotropy = 4
            m.normal.contents = plaster.normal
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
            m.normal.contentsTransform = SCNMatrix4MakeScale(scaleX, 5.2, 1)
            m.normal.mipFilter = .linear
            m.normal.maxAnisotropy = 4
            m.normal.intensity = normalIntensity
            m.roughness.contents = 0.96
            m.metalness.contents = 0.0
            return m
        }
        let wallMat = makePlasterWallMaterial(scaleX: 11.6, normalIntensity: 0.045)
        let leftWallMat = makePlasterWallMaterial(scaleX: 3.1, normalIntensity: 0.015)

        let wallGeo = SCNPlane(width: 240, height: 120)
        wallGeo.widthSegmentCount = 36
        wallGeo.heightSegmentCount = 24
        wallGeo.materials = [wallMat]
        let wallNode = SCNNode(geometry: wallGeo)
        wallNode.position = SCNVector3(matCenter.x, 22.0, backWallZ)
        wallNode.castsShadow = false
        wallNode.renderingOrder = 0
        roomRoot.addChildNode(wallNode)

        // Left room corner wall visible behind/left of the desk lamp (matches desk-front.jpg);
        // single-sided facing +X so wide left camera orbits backface-cull cleanly.
        let leftWallGeo = SCNPlane(width: 64, height: 120)
        leftWallGeo.widthSegmentCount = 16
        leftWallGeo.heightSegmentCount = 24
        leftWallGeo.materials = [leftWallMat]
        let leftWall = SCNNode(geometry: leftWallGeo)
        leftWall.position = SCNVector3(leftCornerX, 22.0, backWallZ + 32.0)
        leftWall.eulerAngles.y = .pi / 2
        leftWall.castsShadow = false
        leftWall.renderingOrder = 0
        roomRoot.addChildNode(leftWall)

        let rightWallGeo = SCNPlane(width: 200, height: 120)
        rightWallGeo.materials = [makePlasterWallMaterial(scaleX: 9.6, normalIntensity: 0.10)]
        let rightWall = SCNNode(geometry: rightWallGeo)
        rightWall.position = SCNVector3(matCenter.x + 118, 22.0, 74.2)
        rightWall.eulerAngles.y = -.pi / 2
        rightWall.castsShadow = false
        roomRoot.addChildNode(rightWall)

        buildRecessedWallOutlet(into: roomRoot)
        buildUnderDeskGlow(into: root)

        // Subtle diagonal upper-right ceiling shadow + soft left-corner ambient crease on back wall
        let wallShadowPlane = SCNPlane(width: 145, height: 92)
        let wallShadowMat = SCNMaterial()
        wallShadowMat.lightingModel = .constant
        wallShadowMat.diffuse.contents = makeWallArchitecturalShadowImage()
        wallShadowMat.blendMode = .alpha
        wallShadowMat.writesToDepthBuffer = false
        wallShadowPlane.materials = [wallShadowMat]
        let wsNode = SCNNode(geometry: wallShadowPlane)
        wsNode.position = SCNVector3(matCenter.x, 12.0, backWallZ + 0.02)
        wsNode.castsShadow = false
        wsNode.renderingOrder = 1
        roomRoot.addChildNode(wsNode)

        // Ambience-toggleable wall glow nodes (toggled via isHidden by KeyboardScene.setAmbience)
        buildToggleableWallGlows(into: root)
        buildUnderDeskRattanBasket(into: root)
    }

    private static func buildRecessedWallOutlet(into root: SCNNode) {
        let outletMat = SCNMaterial()
        outletMat.lightingModel = .physicallyBased
        outletMat.diffuse.contents = NSColor(srgbRed: 0.84, green: 0.83, blue: 0.80, alpha: 1)
        outletMat.roughness.contents = 0.42
        outletMat.metalness.contents = 0.02

        let recessMat = SCNMaterial()
        recessMat.lightingModel = .physicallyBased
        recessMat.diffuse.contents = NSColor(srgbRed: 0.74, green: 0.73, blue: 0.70, alpha: 1)
        recessMat.roughness.contents = 0.55

        let slotMat = SCNMaterial()
        slotMat.lightingModel = .constant
        slotMat.diffuse.contents = NSColor(white: 0.12, alpha: 1)

        let ox: Float = -12.5
        let oy: Float = -7.8
        let wallFaceZ = backWallZ

        let outlet = SCNNode()
        outlet.position = SCNVector3(ox, oy, wallFaceZ + 0.08)
        root.addChildNode(outlet)

        // Beveled white faceplate
        let frameGeo = SCNBox(width: 4.5, height: 4.5, length: 0.16, chamferRadius: 0.08)
        frameGeo.materials = [outletMat]
        let frameNode = SCNNode(geometry: frameGeo)
        frameNode.castsShadow = false
        outlet.addChildNode(frameNode)

        // Subtle inner switch + universal multi-pin socket face
        let innerPlateGeo = SCNBox(width: 2.9, height: 3.1, length: 0.06, chamferRadius: 0.04)
        innerPlateGeo.materials = [recessMat]
        let innerNode = SCNNode(geometry: innerPlateGeo)
        innerNode.position = SCNVector3(0, 0, 0.065)
        innerNode.castsShadow = false
        outlet.addChildNode(innerNode)

        // Universal 3-pin socket dark apertures (L, N, Earth)
        let pinRects: [(x: Float, y: Float, w: CGFloat, h: CGFloat)] = [
            (-0.62, -0.35, 0.24, 0.65),
            ( 0.62, -0.35, 0.24, 0.65),
            ( 0.00,  0.48, 0.28, 0.58),
        ]
        for p in pinRects {
            let sGeo = SCNBox(width: p.w, height: p.h, length: 0.04, chamferRadius: 0.02)
            sGeo.materials = [slotMat]
            let sNode = SCNNode(geometry: sGeo)
            sNode.position = SCNVector3(p.x, p.y, 0.095)
            outlet.addChildNode(sNode)
        }

        // Subtle power cord dropping vertically into plug below desk
        let plugMat = SCNMaterial()
        plugMat.lightingModel = .physicallyBased
        plugMat.diffuse.contents = NSColor(white: 0.11, alpha: 1)
        plugMat.roughness.contents = 0.45
        let plugGeo = SCNBox(width: 1.35, height: 1.35, length: 0.72, chamferRadius: 0.14)
        plugGeo.materials = [plugMat]
        let plugNode = SCNNode(geometry: plugGeo)
        plugNode.position = SCNVector3(0, -0.25, 0.40)
        outlet.addChildNode(plugNode)

        let cordPts = MeshBuilder.catmullRom([
            SIMD3(ox, oy - 0.85, wallFaceZ + 0.55),
            SIMD3(ox + 0.1, oy - 5.5, wallFaceZ + 0.65),
            SIMD3(ox + 0.6, -24.5, wallFaceZ + 0.85),
        ], samplesPerSegment: 6)
        let cordGeo = MeshBuilder.tube(points: cordPts, radius: 0.095, segments: 8, capEnds: true)
        cordGeo.materials = [plugMat]
        let cordNode = SCNNode(geometry: cordGeo)
        cordNode.castsShadow = false
        root.addChildNode(cordNode)
    }

    private static func buildUnderDeskGlow(into root: SCNNode) {
        // Subtle purple under-desk LED strip recessed beneath the walnut slab, confined below tabletop (desk-front.jpg)
        let purpleLight = SCNLight()
        purpleLight.type = .spot
        purpleLight.intensity = 580
        purpleLight.color = NSColor(srgbRed: 0.56, green: 0.18, blue: 0.96, alpha: 1)
        purpleLight.spotInnerAngle = 52
        purpleLight.spotOuterAngle = 114
        purpleLight.attenuationStartDistance = 2.0
        purpleLight.attenuationEndDistance = 28.0
        purpleLight.castsShadow = true
        purpleLight.shadowMapSize = CGSize(width: 512, height: 512)
        purpleLight.shadowRadius = 4.0
        purpleLight.shadowSampleCount = 12
        purpleLight.shadowColor = NSColor(white: 0, alpha: 0.96)
        purpleLight.zNear = 1.0
        purpleLight.zFar = 34.0

        let glowNode = SCNNode()
        glowNode.name = "prop.underDeskGlow"
        glowNode.light = purpleLight
        glowNode.position = SCNVector3(leftCornerX + 9.2, -2.15, backWallZ + 4.4)
        glowNode.look(at: SCNVector3(leftCornerX + 2.6, -15.5, backWallZ + 1.8))
        root.addChildNode(glowNode)

        // Slim tucked LED strip housing beneath the rear-left desk frame
        let stripMat = SCNMaterial()
        stripMat.lightingModel = .constant
        stripMat.diffuse.contents = NSColor(srgbRed: 0.62, green: 0.24, blue: 0.96, alpha: 1)
        let stripGeo = SCNBox(width: 14.0, height: 0.16, length: 0.28, chamferRadius: 0.05)
        stripGeo.materials = [stripMat]
        let stripNode = SCNNode(geometry: stripGeo)
        stripNode.position = SCNVector3(-30.0, -1.48, deskRearEdgeZ + 1.4)
        stripNode.castsShadow = false
        root.addChildNode(stripNode)
    }

    private static func makeWallArchitecturalShadowImage() -> CGImage {
        let w = 1024, h = 640
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))

        func pt(_ wx: CGFloat, _ wy: CGFloat) -> CGPoint {
            CGPoint(x: (wx - (2.4 - 72.5)) / 145.0 * CGFloat(w), y: (wy - (12.0 - 46.0)) / 92.0 * CGFloat(h))
        }

        // Soft wide ceiling-overhang shading in upper-right corner (smooth gradient, zero hard diagonal edge)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ceilGrad = CGGradient(
            colorsSpace: srgb,
            colors: [
                NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.0).cgColor,
                NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.035).cgColor,
                NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.075).cgColor,
            ] as CFArray,
            locations: [0.0, 0.55, 1.0]
        )!
        ctx.drawLinearGradient(
            ceilGrad,
            start: pt(16.0, 22.0),
            end: pt(58.0, 56.0),
            options: [.drawsAfterEndLocation]
        )

        // Soft vertical corner AO crease where back wall meets left room corner wall (x = -41.5)
        let cPt = pt(CGFloat(leftCornerX), 0)
        let cornerGrad = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [
                NSColor(white: 0.05, alpha: 0.18).cgColor,
                NSColor(white: 0.05, alpha: 0.06).cgColor,
                NSColor(white: 0.05, alpha: 0.0).cgColor,
            ] as CFArray,
            locations: [0.0, 0.35, 1.0]
        )!
        ctx.drawLinearGradient(cornerGrad, start: CGPoint(x: cPt.x, y: 0), end: CGPoint(x: cPt.x + 36, y: 0), options: [])

        return ctx.makeImage()!
    }

    private static func buildToggleableWallGlows(into root: SCNNode) {
        func makeAddPlane(name: String, width: Float, height: Float, pos: SIMD3<Float>, rotY: Float = 0, order: Int, image: CGImage) -> SCNNode {
            let plane = SCNPlane(width: CGFloat(width), height: CGFloat(height))
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = image
            mat.blendMode = .add
            mat.writesToDepthBuffer = false
            plane.materials = [mat]
            let node = SCNNode(geometry: plane)
            node.name = name
            node.position = SCNVector3(pos.x, pos.y, pos.z)
            node.eulerAngles.y = CGFloat(rotY)
            node.castsShadow = false
            node.renderingOrder = order
            return node
        }

        // 1) "env.wallGlow.deskLamp": localized coral-magenta pool behind/below shade toward pothos + left corner blush
        let lampW: Float = 48.0, lampH: Float = 46.0
        let lampCenter = SIMD3<Float>(leftCornerX + lampW * 0.5 + 0.05, 11.5, backWallZ + 0.04)
        let lampImg = makeDeskLampWallGlowImage(width: 512, height: 512, worldCenter: lampCenter, worldW: lampW, worldH: lampH)
        let deskGlowNode = makeAddPlane(name: "env.wallGlow.deskLamp", width: lampW, height: lampH, pos: lampCenter, order: 2, image: lampImg)
        // Wrap subtle pink blush onto the left room corner wall too
        let cornerPlane = SCNPlane(width: 22, height: 34)
        let cornerMat = SCNMaterial()
        cornerMat.lightingModel = .constant
        cornerMat.diffuse.contents = makeLeftCornerBlushImage(w: 256, h: 256)
        cornerMat.blendMode = .add
        cornerMat.writesToDepthBuffer = false
        cornerPlane.materials = [cornerMat]
        let cornerChild = SCNNode(geometry: cornerPlane)
        cornerChild.position = SCNVector3(leftCornerX + 0.05 - lampCenter.x, 8.0 - lampCenter.y, backWallZ + 11.0 - lampCenter.z)
        cornerChild.eulerAngles.y = .pi / 2
        cornerChild.castsShadow = false
        cornerChild.renderingOrder = 2
        deskGlowNode.addChildNode(cornerChild)
        root.addChildNode(deskGlowNode)
    }

    private static func makeDeskLampWallGlowImage(width w: Int, height h: Int, worldCenter: SIMD3<Float>, worldW: Float, worldH: Float) -> CGImage {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))

        func pt(_ wx: CGFloat, _ wy: CGFloat) -> CGPoint {
            CGPoint(
                x: (wx - CGFloat(worldCenter.x - worldW * 0.5)) / CGFloat(worldW) * CGFloat(w),
                y: (wy - CGFloat(worldCenter.y - worldH * 0.5)) / CGFloat(worldH) * CGFloat(h)
            )
        }
        func radial(_ c: CGPoint, _ radius: CGFloat, sx: CGFloat = 1, sy: CGFloat = 1, _ stops: [(CGFloat, NSColor)]) {
            let g = CGGradient(colorsSpace: srgb, colors: stops.map { $0.1.cgColor } as CFArray, locations: stops.map { $0.0 })!
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.scaleBy(x: sx, y: sy)
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: [])
            ctx.restoreGState()
        }
        func coral(_ a: CGFloat) -> NSColor { NSColor(srgbRed: 1.0, green: 0.28, blue: 0.44, alpha: a) }

        // Subtle secondary radiosity blush only (real shadowed spotlight carries the primary lamp pool)
        radial(pt(-20.8, 9.6), 96, sx: 1.24, sy: 0.96, [
            (0.0, coral(0.24)),
            (0.38, coral(0.14)),
            (0.75, coral(0.04)),
            (1.0, coral(0.0)),
        ])
        radial(pt(-31.5, 6.2), 180, sx: 1.0, sy: 1.20, [
            (0.0, coral(0.08)),
            (0.58, coral(0.025)),
            (1.0, coral(0.0)),
        ])
        return ctx.makeImage()!
    }

    private static func makeLeftCornerBlushImage(w: Int, h: Int) -> CGImage {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        let g = CGGradient(
            colorsSpace: srgb,
            colors: [
                NSColor(srgbRed: 1.0, green: 0.28, blue: 0.44, alpha: 0.11).cgColor,
                NSColor(srgbRed: 1.0, green: 0.28, blue: 0.44, alpha: 0.03).cgColor,
                NSColor(srgbRed: 1.0, green: 0.28, blue: 0.44, alpha: 0.0).cgColor,
            ] as CFArray,
            locations: [0.0, 0.55, 1.0]
        )!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: w / 3, y: h / 2), startRadius: 0,
                               endCenter: CGPoint(x: w / 3, y: h / 2), endRadius: CGFloat(w) * 0.55, options: [])
        return ctx.makeImage()!
    }

    private static func buildUnderDeskRattanBasket(into root: SCNNode) {
        let rattanTex = DeskTextures.rattanBasket()
        let rattanMat = SCNMaterial()
        rattanMat.lightingModel = .physicallyBased
        rattanMat.diffuse.contents = rattanTex.diffuse
        rattanMat.diffuse.wrapS = .repeat
        rattanMat.diffuse.wrapT = .repeat
        rattanMat.diffuse.contentsTransform = SCNMatrix4MakeScale(3.5, 2.2, 1)
        rattanMat.normal.contents = rattanTex.normal
        rattanMat.normal.wrapS = .repeat
        rattanMat.normal.wrapT = .repeat
        rattanMat.normal.contentsTransform = SCNMatrix4MakeScale(3.5, 2.2, 1)
        rattanMat.normal.intensity = 0.85
        rattanMat.roughness.contents = 0.82
        rattanMat.isDoubleSided = true

        let bx: Float = 22.2, by: Float = -26.0, bz: Float = -11.5
        addContactShadow(at: SIMD3(bx, by + 0.02, bz), radiusX: 4.9, radiusZ: 4.9, opacity: 0.55, into: root)

        let basket = SCNNode()
        basket.position = SCNVector3(bx, by, bz)
        root.addChildNode(basket)

        let profile: [(r: Float, y: Float)] = [
            (0.01, 0.0), (4.0, 0.0), (4.35, 4.0), (4.75, 11.0), (5.05, 18.0), (5.15, 22.0),
            (4.85, 22.0), (4.72, 18.0), (4.42, 11.0), (4.05, 4.0), (3.75, 0.35), (0.01, 0.35),
        ]
        let bodyGeo = MeshBuilder.lathe(profile: profile, segments: 44)
        bodyGeo.materials = [rattanMat]
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.castsShadow = true
        basket.addChildNode(bodyNode)

        let rimTorus = SCNTorus(ringRadius: 5.02, pipeRadius: 0.34)
        rimTorus.materials = [rattanMat]
        let rimNode = SCNNode(geometry: rimTorus)
        rimNode.position = SCNVector3(0, 22.15, 0)
        rimNode.castsShadow = true
        basket.addChildNode(rimNode)
    }

    // MARK: - PCB Ukiru Desk Mat

    private static func buildUkiruMat(into root: SCNNode, texture: Any?) {
        let w = matSize.x, d = matSize.y, h = matTopY
        let hw = w / 2, hd = d / 2, r: Float = 0.72
        let cornerSegs = 8

        var topRing = [SIMD3<Float>]()
        var midRing = [SIMD3<Float>]()
        var botRing = [SIMD3<Float>]()
        let signs: [(Float, Float)] = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
        for (c, sign) in signs.enumerated() {
            for i in 0...cornerSegs {
                let a = (Float(c) + Float(i) / Float(cornerSegs)) * .pi / 2
                let x = sign.0 * (hw - r) + r * cos(a)
                let z = sign.1 * (hd - r) + r * sin(a)
                botRing.append(SIMD3(x, 0, z))
                midRing.append(SIMD3(x, h * 0.78, z))
                let ix = sign.0 * (hw - 0.08 - (r - 0.08)) + (r - 0.08) * cos(a)
                let iz = sign.1 * (hd - 0.08 - (r - 0.08)) + (r - 0.08) * sin(a)
                topRing.append(SIMD3(ix, h, iz))
            }
        }

        let n = topRing.count
        var positions = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var sideIndices = [Int32]()
        var topIndices = [Int32]()

        for ring in [botRing, midRing, topRing] {
            for p in ring {
                positions.append(p)
                uvs.append(SIMD2((p.x + hw) / w, (p.z + hd) / d))
            }
        }
        for rIdx in 0..<2 {
            for i in 0..<n {
                let next = (i + 1) % n
                let a = Int32(rIdx * n + i), b = Int32(rIdx * n + next)
                let dI = Int32((rIdx + 1) * n + i), c = Int32((rIdx + 1) * n + next)
                sideIndices += [a, dI, b, b, dI, c]
            }
        }

        let gx = 48, gz = 24
        let gridStart = positions.count
        for iz in 0...gz {
            let tz = Float(iz) / Float(gz)
            let z = -hd + tz * d
            for ix in 0...gx {
                let tx = Float(ix) / Float(gx)
                let x = -hw + tx * w
                let cx = min(max(x, -(hw - r)), hw - r)
                let cz = min(max(z, -(hd - r)), hd - r)
                let dx = x - cx, dz = z - cz
                let dist = sqrt(dx * dx + dz * dz)
                let px: Float, pz: Float
                if dist > r - 0.08 {
                    let s = (r - 0.08) / max(dist, 1e-5)
                    px = cx + dx * s; pz = cz + dz * s
                } else {
                    px = x; pz = z
                }
                positions.append(SIMD3(px, h, pz))
                uvs.append(SIMD2((px + hw) / w, (pz + hd) / d))
            }
        }
        for iz in 0..<gz {
            for ix in 0..<gx {
                let stride = gx + 1
                let a = Int32(gridStart + iz * stride + ix)
                let b = Int32(gridStart + iz * stride + ix + 1)
                let dI = Int32(gridStart + (iz + 1) * stride + ix)
                let c = Int32(gridStart + (iz + 1) * stride + ix + 1)
                topIndices += [a, dI, b, b, dI, c]
            }
        }

        let geo = CapMesh.assemble(positions, uvs, [sideIndices, topIndices])

        let skirtMat = SCNMaterial()
        skirtMat.lightingModel = .physicallyBased
        skirtMat.diffuse.contents = NSColor(srgbRed: 0.34, green: 0.33, blue: 0.31, alpha: 1)
        skirtMat.roughness.contents = 0.84
        skirtMat.metalness.contents = 0.0

        let topMat = SCNMaterial()
        topMat.lightingModel = .physicallyBased
        topMat.diffuse.contents = DeskTextures.ukiruMatRefined(from: texture as? NSImage)
        topMat.diffuse.mipFilter = .linear
        topMat.diffuse.maxAnisotropy = 8
        topMat.normal.contents = DeskTextures.matWeaveNormal()
        topMat.normal.wrapS = .repeat
        topMat.normal.wrapT = .repeat
        topMat.normal.contentsTransform = SCNMatrix4MakeScale(130, 58, 1)
        topMat.normal.mipFilter = .linear
        topMat.normal.maxAnisotropy = 8
        topMat.normal.intensity = 0.11
        topMat.roughness.contents = 0.84
        topMat.metalness.contents = 0.0

        geo.materials = [skirtMat, topMat]
        let node = SCNNode(geometry: geo)
        node.position = SCNVector3(matCenter.x, 0, matCenter.y)
        node.castsShadow = false
        root.addChildNode(node)

        // Uniform arc-length overlock stitched rim seated cleanly around mat perimeter
        let rimInset: Float = 0.026
        let rRim = r - rimInset
        let hwRim = hw - rimInset
        let hdRim = hd - rimInset
        let rimY = h - 0.004
        var rimPts = [SIMD3<Float>]()
        for (c, sign) in signs.enumerated() {
            let cornerSteps = 6
            for i in 0...cornerSteps {
                let a = (Float(c) + Float(i) / Float(cornerSteps)) * .pi / 2
                rimPts.append(SIMD3(sign.0 * (hwRim - rRim) + rRim * cos(a), rimY, sign.1 * (hdRim - rRim) + rRim * sin(a)))
            }
            let nextSign = signs[(c + 1) % 4]
            let nextA = Float(c + 1) * .pi / 2
            let startP = rimPts.last!
            let endP = SIMD3<Float>(nextSign.0 * (hwRim - rRim) + rRim * cos(nextA), rimY, nextSign.1 * (hdRim - rRim) + rRim * sin(nextA))
            let edgeSteps = (c % 2 == 0) ? 110 : 50
            for e in 1..<edgeSteps {
                let t = Float(e) / Float(edgeSteps)
                rimPts.append(startP + (endP - startP) * t)
            }
        }
        rimPts.append(rimPts[0])

        let stitchTex = makeOverlockStitchTextures()
        let stitchMat = SCNMaterial()
        stitchMat.lightingModel = .physicallyBased
        stitchMat.diffuse.contents = stitchTex.diffuse
        stitchMat.diffuse.wrapS = .repeat
        stitchMat.diffuse.wrapT = .repeat
        stitchMat.diffuse.mipFilter = .linear
        stitchMat.diffuse.maxAnisotropy = 8
        stitchMat.normal.contents = stitchTex.normal
        stitchMat.normal.wrapS = .repeat
        stitchMat.normal.wrapT = .repeat
        stitchMat.normal.intensity = 0.42
        stitchMat.roughness.contents = 0.84

        // uvTube assigns continuous arc-length V UVs so stitch spacing stays uniform on corners & edges
        let rimGeo = MeshBuilder.uvTube(points: rimPts, radius: 0.056, segments: 12, uvLengthScale: 2.8, capEnds: false)
        rimGeo.materials = [stitchMat]
        let rimNode = SCNNode(geometry: rimGeo)
        rimNode.position = SCNVector3(matCenter.x, 0, matCenter.y)
        rimNode.castsShadow = false
        root.addChildNode(rimNode)
    }

    private static func makeOverlockStitchTextures() -> (diffuse: CGImage, normal: CGImage) {
        let w = 64, h = 64
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        func makeTex(_ draw: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage {
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            draw(ctx, CGFloat(w), CGFloat(h))
            return ctx.makeImage()!
        }
        let diffuse = makeTex { ctx, W, H in
            ctx.setFillColor(NSColor(srgbRed: 0.76, green: 0.75, blue: 0.72, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setStrokeColor(NSColor(srgbRed: 0.86, green: 0.85, blue: 0.82, alpha: 1).cgColor)
            ctx.setLineWidth(6.5)
            for i in -2...5 {
                let y0 = CGFloat(i) * 16.0
                ctx.move(to: CGPoint(x: 0, y: y0))
                ctx.addLine(to: CGPoint(x: W, y: y0 + 20.0))
                ctx.strokePath()
            }
        }
        let normal = makeTex { ctx, W, H in
            ctx.setFillColor(NSColor(srgbRed: 0.5, green: 0.5, blue: 1.0, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setStrokeColor(NSColor(srgbRed: 0.68, green: 0.36, blue: 0.94, alpha: 1).cgColor)
            ctx.setLineWidth(5.5)
            for i in -2...5 {
                let y0 = CGFloat(i) * 16.0
                ctx.move(to: CGPoint(x: 0, y: y0))
                ctx.addLine(to: CGPoint(x: W, y: y0 + 20.0))
                ctx.strokePath()
            }
        }
        return (diffuse, normal)
    }
}
