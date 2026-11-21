import SceneKit
import AppKit
import simd

extension TechProps {
    // MARK: - OnePlus 6 Phone

    static func buildOnePlus6(into root: SCNNode) {
        let phone = SCNNode()
        phone.position = SCNVector3(22.2, DeskRoomAndMat.matTopY, 6.45)
        phone.eulerAngles.y = 0.46
        root.addChildNode(phone)

        // Contact shadow underneath phone
        DeskRoomAndMat.addContactShadow(
            at: SIMD3(22.2, DeskRoomAndMat.matTopY + 0.004, 6.45),
            radiusX: 2.15,
            radiusZ: 4.15,
            opacity: 0.42,
            yaw: 0.46,
            into: root
        )

        let bodyMat = SCNMaterial()
        bodyMat.lightingModel = .physicallyBased
        bodyMat.diffuse.contents = NSColor(srgbRed: 0.04, green: 0.042, blue: 0.048, alpha: 1)
        bodyMat.metalness.contents = 0.75
        bodyMat.roughness.contents = 0.22

        let bodyGeo = MeshBuilder.roundedSlab(width: 3.96, height: 0.41, depth: 8.17, cornerRadius: 0.48, bevel: 0.08, cornerSegments: 10)
        bodyGeo.materials = [bodyMat]
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.castsShadow = true
        phone.addChildNode(bodyNode)

        // Glossy 2.5D curved Gorilla Glass top bezel frame around the display
        let glassMat = SCNMaterial()
        glassMat.lightingModel = .physicallyBased
        glassMat.diffuse.contents = NSColor(srgbRed: 0.015, green: 0.016, blue: 0.020, alpha: 1)
        glassMat.roughness.contents = 0.04
        glassMat.metalness.contents = 0.04
        glassMat.clearCoat.contents = 1.0
        glassMat.clearCoatRoughness.contents = 0.03

        let glassGeo = MeshBuilder.roundedSlab(width: 3.90, height: 0.045, depth: 8.09, cornerRadius: 0.44, bevel: 0.022, cornerSegments: 10)
        glassGeo.materials = [glassMat]
        let glassNode = SCNNode(geometry: glassGeo)
        glassNode.position = SCNVector3(0, 0.392, 0)
        glassNode.castsShadow = false
        phone.addChildNode(glassNode)

        // Off/sleeping obsidian OLED display glass matching physical reference (IMG_1867)
        let scrMat = SCNMaterial()
        scrMat.lightingModel = .physicallyBased
        scrMat.diffuse.contents = NSColor(srgbRed: 0.010, green: 0.011, blue: 0.014, alpha: 1)
        scrMat.emission.contents = NSColor.black
        scrMat.emission.intensity = 0.0
        scrMat.roughness.contents = 0.03
        scrMat.metalness.contents = 0.02
        scrMat.clearCoat.contents = 0.96
        scrMat.clearCoatRoughness.contents = 0.03

        let scrPlane = SCNPlane(width: 3.68, height: 7.56)
        scrPlane.cornerRadius = 0.34
        scrPlane.materials = [scrMat]
        let scrNode = SCNNode(geometry: scrPlane)
        scrNode.eulerAngles.x = -.pi / 2
        scrNode.position = SCNVector3(0, 0.440, -0.06)
        scrNode.castsShadow = false
        phone.addChildNode(scrNode)

        // Top bezel details: metallic earpiece mesh, front camera lens, and glowing white notification LED
        let meshMat = SCNMaterial()
        meshMat.lightingModel = .physicallyBased
        meshMat.diffuse.contents = NSColor(srgbRed: 0.20, green: 0.21, blue: 0.23, alpha: 1)
        meshMat.metalness.contents = 0.72
        meshMat.roughness.contents = 0.35
        let earpiece = SCNBox(width: 0.72, height: 0.012, length: 0.065, chamferRadius: 0.03)
        earpiece.materials = [meshMat]
        let earNode = SCNNode(geometry: earpiece)
        earNode.position = SCNVector3(0, 0.440, -3.95)
        earNode.castsShadow = false
        phone.addChildNode(earNode)

        let camRingMat = SCNMaterial()
        camRingMat.lightingModel = .physicallyBased
        camRingMat.diffuse.contents = NSColor(white: 0.08, alpha: 1)
        camRingMat.metalness.contents = 0.6
        camRingMat.roughness.contents = 0.25
        let camRing = SCNCylinder(radius: 0.075, height: 0.008)
        camRing.materials = [camRingMat]
        let camRingNode = SCNNode(geometry: camRing)
        camRingNode.position = SCNVector3(0.52, 0.440, -3.90)
        camRingNode.castsShadow = false
        phone.addChildNode(camRingNode)

        let camLensMat = SCNMaterial()
        camLensMat.lightingModel = .physicallyBased
        camLensMat.diffuse.contents = NSColor(srgbRed: 0.06, green: 0.13, blue: 0.30, alpha: 1)
        camLensMat.metalness.contents = 0.88
        camLensMat.roughness.contents = 0.08
        camLensMat.clearCoat.contents = 1.0
        let camLens = SCNCylinder(radius: 0.046, height: 0.010)
        camLens.materials = [camLensMat]
        let camLensNode = SCNNode(geometry: camLens)
        camLensNode.position = SCNVector3(0.52, 0.441, -3.90)
        camLensNode.castsShadow = false
        phone.addChildNode(camLensNode)

        let notifMat = SCNMaterial()
        notifMat.lightingModel = .constant
        notifMat.diffuse.contents = NSColor(srgbRed: 0.84, green: 0.85, blue: 0.86, alpha: 1)
        let notifLed = SCNCylinder(radius: 0.028, height: 0.010)
        notifLed.materials = [notifMat]
        let notifNode = SCNNode(geometry: notifLed)
        notifNode.position = SCNVector3(-0.54, 0.441, -3.90)
        notifNode.castsShadow = false
        phone.addChildNode(notifNode)

        // Left flank: volume rocker
        let btnGeo = SCNBox(width: 0.08, height: 0.10, length: 0.95, chamferRadius: 0.03)
        btnGeo.materials = [bodyMat]
        let vol = SCNNode(geometry: btnGeo)
        vol.position = SCNVector3(-1.99, 0.21, -1.1)
        phone.addChildNode(vol)

        // Right flank: power button + textured OnePlus Alert Slider
        let pwrGeo = SCNBox(width: 0.08, height: 0.10, length: 0.55, chamferRadius: 0.03)
        pwrGeo.materials = [bodyMat]
        let pwr = SCNNode(geometry: pwrGeo)
        pwr.position = SCNVector3(1.99, 0.21, -0.8)
        phone.addChildNode(pwr)

        let sliderMat = SCNMaterial()
        sliderMat.lightingModel = .physicallyBased
        sliderMat.diffuse.contents = NSColor(srgbRed: 0.08, green: 0.085, blue: 0.095, alpha: 1)
        sliderMat.metalness.contents = 0.85
        sliderMat.roughness.contents = 0.28
        let slider = SCNNode(geometry: SCNBox(width: 0.075, height: 0.088, length: 0.38, chamferRadius: 0.025))
        slider.geometry?.materials = [sliderMat]
        slider.position = SCNVector3(1.985, 0.21, -1.7)
        phone.addChildNode(slider)

        let ridgeGeo = SCNBox(width: 0.092, height: 0.072, length: 0.024, chamferRadius: 0.008)
        ridgeGeo.materials = [sliderMat]
        for i in -2...2 {
            let ridge = SCNNode(geometry: ridgeGeo)
            ridge.position = SCNVector3(1.99, 0.21, -1.7 + Float(i) * 0.065)
            phone.addChildNode(ridge)
        }

        // Bottom edge: USB-C port + speaker grille perforations
        func bottomPill(_ w: CGFloat, _ h: CGFloat, depth: CGFloat, mat: SCNMaterial, z: Float) {
            let path = NSBezierPath(roundedRect: NSRect(x: -w / 2, y: -h / 2, width: w, height: h), xRadius: h / 2, yRadius: h / 2)
            path.flatness = 0.002
            let shape = SCNShape(path: path, extrusionDepth: depth)
            shape.materials = [mat]
            let node = SCNNode(geometry: shape)
            node.position = SCNVector3(0, 0.205, z)
            phone.addChildNode(node)
        }
        let portDark = SCNMaterial()
        portDark.lightingModel = .physicallyBased
        portDark.diffuse.contents = NSColor(white: 0.015, alpha: 1)
        portDark.roughness.contents = 0.7

        bottomPill(0.46, 0.16, depth: 0.012, mat: camRingMat, z: 4.082)
        bottomPill(0.38, 0.11, depth: 0.014, mat: portDark, z: 4.085)
        bottomPill(0.24, 0.032, depth: 0.016, mat: meshMat, z: 4.086)

        let holeGeo = SCNCylinder(radius: 0.026, height: 0.012)
        holeGeo.materials = [portDark]
        for xOff: Float in [-0.75, -0.63, -0.51, 0.51, 0.63, 0.75] {
            let hole = SCNNode(geometry: holeGeo)
            hole.eulerAngles.x = .pi / 2
            hole.position = SCNVector3(xOff, 0.205, 4.085)
            phone.addChildNode(hole)
        }
    }

    // MARK: - iPad (11th Gen, Silver)

    static func buildIPad11Gen(into root: SCNNode) {
        let iPadPos = SIMD3<Float>(-29.0, 0, 1.6)
        let iPadYaw: Float = -0.04

        let iPad = SCNNode()
        iPad.position = SCNVector3(iPadPos.x, iPadPos.y, iPadPos.z)
        iPad.eulerAngles.y = CGFloat(iPadYaw)
        root.addChildNode(iPad)

        // Landscape chassis container (+90 deg yaw places the Center Stage camera on the top -Z edge).
        let chassis = SCNNode()
        chassis.eulerAngles.y = .pi / 2
        iPad.addChildNode(chassis)

        // Contact shadow underneath the aluminum chassis on the walnut desk
        DeskRoomAndMat.addContactShadow(
            at: SIMD3(iPadPos.x, 0.005, iPadPos.z),
            radiusX: 6.75,
            radiusZ: 4.95,
            opacity: 0.44,
            yaw: iPadYaw,
            into: root
        )

        // Real iPad 11th gen (11-inch): 179.5 x 248.6 x 7.0 mm in keycap pitches (1 u = 19.05 mm)
        let bodyW: Float = 9.42
        let bodyH: Float = 0.37
        let bodyD: Float = 13.05
        let bodyR: Float = 0.88

        // Bead-blasted silver anodized aluminum unibody material
        let aluTex = DeskTextures.macMiniAluminum()
        let aluMat = SCNMaterial()
        aluMat.lightingModel = .physicallyBased
        aluMat.diffuse.contents = aluTex.diffuse
        aluMat.diffuse.wrapS = .repeat
        aluMat.diffuse.wrapT = .repeat
        aluMat.diffuse.contentsTransform = SCNMatrix4MakeScale(2.4, 2.4, 1)
        aluMat.diffuse.mipFilter = .linear
        aluMat.diffuse.maxAnisotropy = 8
        aluMat.roughness.contents = aluTex.roughness
        aluMat.roughness.wrapS = .repeat
        aluMat.roughness.wrapT = .repeat
        aluMat.roughness.contentsTransform = SCNMatrix4MakeScale(2.4, 2.4, 1)
        aluMat.normal.contents = aluTex.normal
        aluMat.normal.wrapS = .repeat
        aluMat.normal.wrapT = .repeat
        aluMat.normal.contentsTransform = SCNMatrix4MakeScale(2.4, 2.4, 1)
        aluMat.normal.intensity = 0.14
        aluMat.metalness.contents = 0.88
        aluMat.clearCoat.contents = 0.08
        aluMat.clearCoatRoughness.contents = 0.25

        let bodyGeo = MeshBuilder.roundedSlab(
            width: bodyW,
            height: bodyH,
            depth: bodyD,
            cornerRadius: bodyR,
            bevel: 0.040,
            cornerSegments: 14,
            planarUVs: true
        )
        bodyGeo.materials = [aluMat]
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.castsShadow = true
        chassis.addChildNode(bodyNode)

        // Dark polycarbonate display gasket & mirror-glossy 2.5D oleophobic cover glass
        let gasketMat = SCNMaterial()
        gasketMat.lightingModel = .physicallyBased
        gasketMat.diffuse.contents = NSColor(srgbRed: 0.032, green: 0.034, blue: 0.038, alpha: 1)
        gasketMat.metalness.contents = 0.06
        gasketMat.roughness.contents = 0.52

        let gasketGeo = MeshBuilder.roundedSlab(
            width: 9.18,
            height: 0.024,
            depth: 12.81,
            cornerRadius: 0.80,
            bevel: 0.012,
            cornerSegments: 14
        )
        gasketGeo.materials = [gasketMat]
        let gasketNode = SCNNode(geometry: gasketGeo)
        gasketNode.position = SCNVector3(0, 0.358, 0)
        gasketNode.castsShadow = false
        chassis.addChildNode(gasketNode)

        let glassMat = SCNMaterial()
        glassMat.lightingModel = .physicallyBased
        glassMat.diffuse.contents = NSColor(srgbRed: 0.012, green: 0.013, blue: 0.017, alpha: 1)
        glassMat.roughness.contents = 0.03
        glassMat.metalness.contents = 0.04
        glassMat.clearCoat.contents = 1.0
        glassMat.clearCoatRoughness.contents = 0.03

        let glassGeo = MeshBuilder.roundedSlab(
            width: 9.10,
            height: 0.022,
            depth: 12.73,
            cornerRadius: 0.78,
            bevel: 0.010,
            cornerSegments: 14
        )
        glassGeo.materials = [glassMat]
        let glassNode = SCNNode(geometry: glassGeo)
        glassNode.position = SCNVector3(0, 0.368, 0)
        glassNode.castsShadow = false
        chassis.addChildNode(glassNode)

        // Uniform-bezel 11-inch Liquid Retina display in landscape orientation (11.85 u W x 8.22 u H)
        let scrImg = DeskTextures.iPadScreen()
        let scrMat = SCNMaterial()
        scrMat.lightingModel = .physicallyBased
        scrMat.diffuse.contents = scrImg
        scrMat.diffuse.mipFilter = .linear
        scrMat.diffuse.minificationFilter = .linear
        scrMat.diffuse.magnificationFilter = .linear
        scrMat.diffuse.maxAnisotropy = 16
        scrMat.emission.contents = scrImg
        scrMat.emission.intensity = 0.72
        scrMat.emission.mipFilter = .linear
        scrMat.emission.minificationFilter = .linear
        scrMat.emission.magnificationFilter = .linear
        scrMat.emission.maxAnisotropy = 16
        scrMat.roughness.contents = 0.04
        scrMat.metalness.contents = 0.02
        scrMat.clearCoat.contents = 0.96
        scrMat.clearCoatRoughness.contents = 0.03

        let scrPlane = SCNPlane(width: 11.85, height: 8.22)
        scrPlane.cornerRadius = 0.36
        scrPlane.materials = [scrMat]
        let scrNode = SCNNode(geometry: scrPlane)
        scrNode.eulerAngles.x = -.pi / 2
        scrNode.position = SCNVector3(0, 0.393, 0)
        scrNode.castsShadow = false
        iPad.addChildNode(scrNode)

        // Signature landscape-edge 12MP Center Stage camera + mic + top ambient light sensor
        let metalTrimMat = SCNMaterial()
        metalTrimMat.lightingModel = .physicallyBased
        metalTrimMat.diffuse.contents = NSColor(srgbRed: 0.12, green: 0.125, blue: 0.135, alpha: 1)
        metalTrimMat.metalness.contents = 0.78
        metalTrimMat.roughness.contents = 0.24

        let sapphireLensMat = SCNMaterial()
        sapphireLensMat.lightingModel = .physicallyBased
        sapphireLensMat.diffuse.contents = NSColor(srgbRed: 0.04, green: 0.12, blue: 0.32, alpha: 1)
        sapphireLensMat.metalness.contents = 0.88
        sapphireLensMat.roughness.contents = 0.06
        sapphireLensMat.clearCoat.contents = 1.0
        sapphireLensMat.clearCoatRoughness.contents = 0.02

        let glintMat = SCNMaterial()
        glintMat.lightingModel = .physicallyBased
        glintMat.diffuse.contents = NSColor(srgbRed: 0.42, green: 0.62, blue: 0.92, alpha: 1)
        glintMat.metalness.contents = 0.60
        glintMat.roughness.contents = 0.04

        let darkRecessMat = SCNMaterial()
        darkRecessMat.lightingModel = .physicallyBased
        darkRecessMat.diffuse.contents = NSColor(white: 0.015, alpha: 1)
        darkRecessMat.roughness.contents = 0.75

        func addBezelCircle(radius: Float, height: Float, x: Float, y: Float, z: Float, mat: SCNMaterial) {
            let cyl = SCNCylinder(radius: CGFloat(radius), height: CGFloat(height))
            cyl.radialSegmentCount = 24
            cyl.materials = [mat]
            let node = SCNNode(geometry: cyl)
            node.position = SCNVector3(x, y, z)
            node.castsShadow = false
            chassis.addChildNode(node)
        }

        addBezelCircle(radius: 0.088, height: 0.008, x: 4.32, y: 0.390, z: 0.0, mat: metalTrimMat)
        addBezelCircle(radius: 0.052, height: 0.010, x: 4.32, y: 0.391, z: 0.0, mat: sapphireLensMat)
        addBezelCircle(radius: 0.016, height: 0.011, x: 4.336, y: 0.3915, z: -0.016, mat: glintMat)
        addBezelCircle(radius: 0.022, height: 0.008, x: 4.32, y: 0.390, z: -0.42, mat: darkRecessMat)
        addBezelCircle(radius: 0.030, height: 0.008, x: 0.0, y: 0.390, z: -6.14, mat: darkRecessMat)

        // Subtle matte antenna lines near top/bottom side rails
        let antennaMat = SCNMaterial()
        antennaMat.lightingModel = .physicallyBased
        antennaMat.diffuse.contents = NSColor(srgbRed: 0.68, green: 0.69, blue: 0.71, alpha: 1)
        antennaMat.metalness.contents = 0.14
        antennaMat.roughness.contents = 0.46
        let bandGeo = SCNBox(width: 0.014, height: 0.28, length: 0.065, chamferRadius: 0.005)
        bandGeo.materials = [antennaMat]
        for xSide: Float in [-4.706, 4.706] {
            for zBand: Float in [-5.58, 5.58] {
                let band = SCNNode(geometry: bandGeo)
                band.position = SCNVector3(xSide, 0.185, zBand)
                band.castsShadow = false
                chassis.addChildNode(band)
            }
        }

        // Top edge (z = -6.525 in chassis -> -X left edge in landscape): Touch ID power button, stereo speaker grilles, and dual mic pinholes
        let touchBezel = SCNBox(width: 0.92, height: 0.11, length: 0.06, chamferRadius: 0.028)
        touchBezel.materials = [aluMat]
        let touchBezelNode = SCNNode(geometry: touchBezel)
        touchBezelNode.position = SCNVector3(3.32, 0.185, -6.525)
        chassis.addChildNode(touchBezelNode)

        let touchInsertMat = SCNMaterial()
        touchInsertMat.lightingModel = .physicallyBased
        touchInsertMat.diffuse.contents = NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1)
        touchInsertMat.metalness.contents = 0.65
        touchInsertMat.roughness.contents = 0.14
        touchInsertMat.clearCoat.contents = 0.90
        touchInsertMat.clearCoatRoughness.contents = 0.05
        let touchInsert = SCNBox(width: 0.82, height: 0.08, length: 0.066, chamferRadius: 0.020)
        touchInsert.materials = [touchInsertMat]
        let touchInsertNode = SCNNode(geometry: touchInsert)
        touchInsertNode.position = SCNVector3(3.32, 0.185, -6.527)
        chassis.addChildNode(touchInsertNode)

        let spkHoleGeo = SCNCylinder(radius: 0.024, height: 0.016)
        spkHoleGeo.radialSegmentCount = 14
        spkHoleGeo.materials = [darkRecessMat]
        let speakerXOffsets: [Float] = [
            -2.45, -2.20, -1.95, -1.70, -1.45,
             1.45,  1.70,  1.95,  2.20,  2.45,
        ]
        for zEdge: Float in [-6.522, 6.522] {
            for xOff in speakerXOffsets {
                let hole = SCNNode(geometry: spkHoleGeo)
                hole.eulerAngles.x = .pi / 2
                hole.position = SCNVector3(xOff, 0.185, zEdge)
                hole.castsShadow = false
                chassis.addChildNode(hole)
            }
        }
        let micHoleGeo = SCNCylinder(radius: 0.019, height: 0.016)
        micHoleGeo.radialSegmentCount = 12
        micHoleGeo.materials = [darkRecessMat]
        for xMic: Float in [-0.42, 0.42] {
            let mic = SCNNode(geometry: micHoleGeo)
            mic.eulerAngles.x = .pi / 2
            mic.position = SCNVector3(xMic, 0.185, -6.522)
            mic.castsShadow = false
            chassis.addChildNode(mic)
        }

        // Right edge (x = +4.71 in chassis -> -Z top edge in landscape): Volume Up/Down pill buttons & magnetic accessory connector strip
        let volGeo = SCNBox(width: 0.065, height: 0.10, length: 0.78, chamferRadius: 0.032)
        volGeo.materials = [aluMat]
        for zVol: Float in [-4.75, -3.72] {
            let vol = SCNNode(geometry: volGeo)
            vol.position = SCNVector3(4.715, 0.185, zVol)
            vol.castsShadow = false
            chassis.addChildNode(vol)
        }

        let magConnectorMat = SCNMaterial()
        magConnectorMat.lightingModel = .physicallyBased
        magConnectorMat.diffuse.contents = NSColor(srgbRed: 0.46, green: 0.47, blue: 0.50, alpha: 1)
        magConnectorMat.metalness.contents = 0.25
        magConnectorMat.roughness.contents = 0.42
        let magGeo = SCNBox(width: 0.016, height: 0.09, length: 1.05, chamferRadius: 0.035)
        magGeo.materials = [magConnectorMat]
        let magNode = SCNNode(geometry: magGeo)
        magNode.position = SCNVector3(4.712, 0.185, 0.0)
        magNode.castsShadow = false
        chassis.addChildNode(magNode)

        // Bottom edge (z = +6.525 in chassis -> +X right edge in landscape): centered USB-C port
        func addBottomPill(_ w: CGFloat, _ h: CGFloat, depth: CGFloat, mat: SCNMaterial, z: Float) {
            let path = NSBezierPath(roundedRect: NSRect(x: -w / 2, y: -h / 2, width: w, height: h), xRadius: h / 2, yRadius: h / 2)
            path.flatness = 0.002
            let shape = SCNShape(path: path, extrusionDepth: depth)
            shape.materials = [mat]
            let node = SCNNode(geometry: shape)
            node.position = SCNVector3(0, 0.185, z)
            node.castsShadow = false
            chassis.addChildNode(node)
        }
        addBottomPill(0.54, 0.18, depth: 0.020, mat: metalTrimMat, z: 6.522)
        addBottomPill(0.46, 0.12, depth: 0.024, mat: darkRecessMat, z: 6.523)
        addBottomPill(0.32, 0.035, depth: 0.028, mat: aluMat, z: 6.524)
    }

}
