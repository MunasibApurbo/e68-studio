import SceneKit
import AppKit
import simd

/// Photorealistic 3D models for all desk props:
/// ASUS VZ229E monitor, Mac mini M4, MCHOSE G7 mouse, OnePlus 6 phone, iPad 11th gen, and AirPods 3 case.
enum TechProps {

    static func build(into root: SCNNode) {
        buildASUSVZ229E(into: root)
        buildMacMiniM4(into: root)
        buildMchoseG7(into: root)
        buildOnePlus6(into: root)
        buildIPad11Gen(into: root)
        buildApplePencilAndSleeve(into: root)
        buildCoconutGoblet(into: root)
        buildLooseWhiteUSBCTip(into: root)
        buildAirPods3(into: root)
    }

    // MARK: - ASUS VZ229E Monitor

    private static func buildASUSVZ229E(into root: SCNNode) {
        let monitor = SCNNode()
        monitor.name = KeyboardScene.DeskProp.monitor.rawValue
        monitor.position = SCNVector3(2.8, 0, -16.25)
        root.addChildNode(monitor)

        let darkMetal = SCNMaterial()
        darkMetal.lightingModel = .physicallyBased
        darkMetal.diffuse.contents = NSColor(srgbRed: 0.095, green: 0.098, blue: 0.108, alpha: 1)
        darkMetal.roughness.contents = 0.28
        darkMetal.metalness.contents = 0.72
        darkMetal.normal.contents = DeskTextures.brushedNormal()
        darkMetal.normal.intensity = 0.14

        let glossyBevelMat = SCNMaterial()
        glossyBevelMat.lightingModel = .physicallyBased
        glossyBevelMat.diffuse.contents = NSColor(srgbRed: 0.11, green: 0.115, blue: 0.128, alpha: 1)
        glossyBevelMat.roughness.contents = 0.07
        glossyBevelMat.metalness.contents = 0.74
        glossyBevelMat.clearCoat.contents = 0.94
        glossyBevelMat.clearCoatRoughness.contents = 0.05

        let mattePlastic = SCNMaterial()
        mattePlastic.lightingModel = .physicallyBased
        mattePlastic.diffuse.contents = NSColor(srgbRed: 0.058, green: 0.060, blue: 0.066, alpha: 1)
        mattePlastic.roughness.contents = 0.62
        mattePlastic.metalness.contents = 0.08
        mattePlastic.normal.contents = DeskTextures.pbtMicroNormal()
        mattePlastic.normal.wrapS = .repeat
        mattePlastic.normal.wrapT = .repeat
        mattePlastic.normal.contentsTransform = SCNMatrix4MakeScale(10, 10, 1)
        mattePlastic.normal.intensity = 0.035

        // 1. Circular ring stand (outer radius 5.15u, inner hole radius 3.45u) with glossy outer chamfer bevel
        let ringProfile: [(r: Float, y: Float)] = [
            (3.45, 0.0), (5.15, 0.0), (5.15, 0.14), (4.95, 0.36),
            (3.68, 0.36), (3.45, 0.16), (3.45, 0.0),
        ]
        let ringGeo = MeshBuilder.lathe(profile: ringProfile, segments: 64)
        ringGeo.materials = [darkMetal]
        let ringNode = SCNNode(geometry: ringGeo)
        ringNode.castsShadow = true
        monitor.addChildNode(ringNode)

        let outerBevelProfile: [(r: Float, y: Float)] = [
            (5.154, 0.136), (5.156, 0.152), (4.956, 0.365),
            (4.88, 0.365), (4.88, 0.352), (5.154, 0.136),
        ]
        let outerBevelGeo = MeshBuilder.lathe(profile: outerBevelProfile, segments: 64)
        outerBevelGeo.materials = [glossyBevelMat]
        let outerBevelNode = SCNNode(geometry: outerBevelGeo)
        outerBevelNode.castsShadow = false
        monitor.addChildNode(outerBevelNode)

        // Annular contact shadow strictly underneath the hollow ring stand (clear interior wood grain)
        let ringShadowTex = makeAnnularShadowTexture()
        let ringShadowMat = SCNMaterial()
        ringShadowMat.lightingModel = .constant
        ringShadowMat.diffuse.contents = ringShadowTex
        ringShadowMat.transparency = 0.34
        ringShadowMat.blendMode = .alpha
        ringShadowMat.writesToDepthBuffer = false
        let ringShadowPlane = SCNPlane(width: 11.4, height: 11.4)
        ringShadowPlane.materials = [ringShadowMat]
        let ringShadowNode = SCNNode(geometry: ringShadowPlane)
        ringShadowNode.position = SCNVector3(2.8, 0.005, -16.25)
        ringShadowNode.eulerAngles.x = -.pi / 2
        ringShadowNode.castsShadow = false
        ringShadowNode.renderingOrder = 1
        root.addChildNode(ringShadowNode)

        // 2. Curved neck rising from rear of ring to monitor rear hump
        let neckCtrl: [SIMD3<Float>] = [
            SIMD3(0, 0.18, -4.3),
            SIMD3(0, 2.2, -4.45),
            SIMD3(0, 4.9, -4.15),
            SIMD3(0, 7.6, -2.55),
        ]
        let neckPts = MeshBuilder.catmullRom(neckCtrl, samplesPerSegment: 10)
        let neckNode = SCNNode(geometry: MeshBuilder.tube(points: neckPts, radius: 0.55, segments: 20))
        neckNode.scale = SCNVector3(1.45, 1.0, 0.55)
        neckNode.geometry?.materials = [darkMetal]
        neckNode.castsShadow = true
        monitor.addChildNode(neckNode)

        // Hinge bracket
        let bracket = SCNBox(width: 2.2, height: 1.5, length: 0.9, chamferRadius: 0.15)
        bracket.materials = [mattePlastic]
        let bracketNode = SCNNode(geometry: bracket)
        bracketNode.position = SCNVector3(0, 7.6, -1.2)
        monitor.addChildNode(bracketNode)

        // 3. Display assembly (21.5" panel: 26.14u W x 15.85u H, tilted slightly back 2 deg)
        let panelPivot = SCNNode()
        panelPivot.position = SCNVector3(0, 12.1, -0.35)
        panelPivot.eulerAngles.x = 2.0 * .pi / 180.0
        monitor.addChildNode(panelPivot)

        let pw: Float = 26.14, ph: Float = 15.85, chinH: Float = 1.05
        let bezel: Float = 0.15

        // Ultra-slim upper backplate (7 mm = 0.37u thin!)
        let upperBack = MeshBuilder.roundedSlab(width: pw, height: ph, depth: 0.36, cornerRadius: 0.16, bevel: 0.05)
        upperBack.materials = [mattePlastic]
        let upperNode = SCNNode(geometry: upperBack)
        upperNode.position = SCNVector3(0, -ph / 2, -0.18)
        upperNode.castsShadow = true
        panelPivot.addChildNode(upperNode)

        // Stepped lower electronics housing at the rear
        let rearBulge = MeshBuilder.roundedSlab(width: pw - 0.8, height: 6.2, depth: 1.15, cornerRadius: 0.35, bevel: 0.25)
        rearBulge.materials = [mattePlastic]
        let bulgeNode = SCNNode(geometry: rearBulge)
        bulgeNode.position = SCNVector3(0, -ph / 2 + 0.35, -0.78)
        bulgeNode.castsShadow = true
        panelPivot.addChildNode(bulgeNode)

        // Front dark chin bar with brushed gunmetal + silver ASUS logo
        let chinMat = SCNMaterial()
        chinMat.lightingModel = .physicallyBased
        chinMat.diffuse.contents = DeskTextures.asusChin()
        chinMat.roughness.contents = 0.27
        chinMat.metalness.contents = 0.65
        chinMat.normal.contents = DeskTextures.brushedNormal()
        chinMat.normal.wrapS = .repeat
        chinMat.normal.wrapT = .repeat
        chinMat.normal.contentsTransform = SCNMatrix4MakeScale(4, 1, 1)
        chinMat.normal.intensity = 0.15

        let chinPlane = SCNPlane(width: CGFloat(pw - 0.08), height: CGFloat(chinH))
        chinPlane.materials = [chinMat]
        let chinNode = SCNNode(geometry: chinPlane)
        chinNode.position = SCNVector3(0, -ph / 2 + chinH / 2 + 0.02, 0.185)
        panelPivot.addChildNode(chinNode)

        // Tiny amber/white power LED on bottom right of chin
        let ledMat = SCNMaterial()
        ledMat.lightingModel = .constant
        ledMat.diffuse.contents = NSColor(srgbRed: 0.9, green: 0.95, blue: 1.0, alpha: 1)
        let led = SCNSphere(radius: 0.055)
        led.materials = [ledMat]
        let ledNode = SCNNode(geometry: led)
        ledNode.position = SCNVector3(pw / 2 - 1.35, -ph / 2 + 0.18, 0.20)
        panelPivot.addChildNode(ledNode)

        // Underside tactile OSD buttons along the right chin
        let osdMat = SCNMaterial()
        osdMat.lightingModel = .physicallyBased
        osdMat.diffuse.contents = NSColor(srgbRed: 0.11, green: 0.115, blue: 0.125, alpha: 1)
        osdMat.roughness.contents = 0.45
        osdMat.metalness.contents = 0.15
        for (idx, xOff) in [Float(pw / 2 - 1.35), pw / 2 - 2.25, pw / 2 - 3.05, pw / 2 - 3.85, pw / 2 - 4.65, pw / 2 - 5.45].enumerated() {
            let btn = SCNBox(width: idx == 0 ? 0.42 : 0.34, height: 0.07, length: 0.16, chamferRadius: 0.025)
            btn.materials = [osdMat]
            let bNode = SCNNode(geometry: btn)
            bNode.position = SCNVector3(xOff, -ph / 2 - 0.02, 0.05)
            panelPivot.addChildNode(bNode)
        }

        // Micro-thin bezel border around screen
        let screenW = pw - bezel * 2
        let screenH = ph - chinH - bezel
        let screenCenterY = (chinH - bezel) / 2

        let bezelFrame = SCNBox(width: CGFloat(pw - 0.04), height: CGFloat(ph - chinH + 0.04), length: 0.06, chamferRadius: 0.02)
        bezelFrame.materials = [mattePlastic]
        let bezelNode = SCNNode(geometry: bezelFrame)
        bezelNode.position = SCNVector3(0, screenCenterY, 0.165)
        panelPivot.addChildNode(bezelNode)

        // Matte anti-glare IPS LCD screen with backlit emission (no mirror clearcoat)
        let screenImg = DeskTextures.asusScreen()
        let screenMat = SCNMaterial()
        screenMat.lightingModel = .physicallyBased
        screenMat.diffuse.contents = NSColor(white: 0.02, alpha: 1)
        screenMat.diffuse.mipFilter = .linear
        screenMat.diffuse.minificationFilter = .linear
        screenMat.diffuse.magnificationFilter = .linear
        screenMat.diffuse.maxAnisotropy = 16
        screenMat.emission.contents = screenImg
        screenMat.emission.intensity = 0.86
        screenMat.emission.mipFilter = .linear
        screenMat.emission.minificationFilter = .linear
        screenMat.emission.magnificationFilter = .linear
        screenMat.emission.maxAnisotropy = 16
        screenMat.roughness.contents = 0.72
        screenMat.metalness.contents = 0.0
        screenMat.clearCoat.contents = 0.0
        screenMat.clearCoatRoughness.contents = 0.72
        screenMat.isDoubleSided = false

        let screenPlane = SCNPlane(width: CGFloat(screenW), height: CGFloat(screenH))
        screenPlane.materials = [screenMat]
        let screenNode = SCNNode(geometry: screenPlane)
        screenNode.name = "prop.monitor.screen"
        screenNode.position = SCNVector3(0, screenCenterY, 0.205)
        screenNode.castsShadow = false
        panelPivot.addChildNode(screenNode)

        // Rear DC power & HDMI plugs tucked tightly high behind the bezel & stand neck into rear cable corridor
        let cableMat = SCNMaterial()
        cableMat.lightingModel = .physicallyBased
        cableMat.diffuse.contents = NSColor(white: 0.045, alpha: 1)
        cableMat.roughness.contents = 0.72

        for (xOff, rPlug, rWire) in [(Float(0.18), Float(0.085), Float(0.064)), (Float(-0.18), Float(0.095), Float(0.070))] {
            let plug = SCNCylinder(radius: CGFloat(rPlug), height: 0.34)
            plug.materials = [mattePlastic]
            let plugNode = SCNNode(geometry: plug)
            plugNode.eulerAngles.x = .pi / 2
            plugNode.position = SCNVector3(xOff, 5.40, -1.92)
            monitor.addChildNode(plugNode)

            let cableCtrl: [SIMD3<Float>] = [
                SIMD3(xOff, 5.40, -2.02),
                SIMD3(xOff, 3.85, -3.55),
                SIMD3(xOff, 1.45, -4.40),
                SIMD3(xOff, 0.14, -5.05),
                SIMD3(xOff, 0.08, -10.18),
                SIMD3(xOff, -0.35, -10.30),
                SIMD3(xOff, -2.15, -10.10),
                SIMD3(xOff, -2.35, -8.90),
            ]
            let cablePts = MeshBuilder.catmullRom(cableCtrl, samplesPerSegment: 10)
            let cableGeo = MeshBuilder.tube(points: cablePts, radius: rWire, segments: 12)
            cableGeo.materials = [cableMat]
            let cableNode = SCNNode(geometry: cableGeo)
            cableNode.castsShadow = true
            monitor.addChildNode(cableNode)
        }

        // Cool-neutral monitor illumination onto desk mat & keyboard (mood-modulated by KeyboardScene)
        let screenGlow = SCNLight()
        screenGlow.type = .omni
        screenGlow.intensity = 210
        screenGlow.color = NSColor(srgbRed: 0.84, green: 0.90, blue: 0.98, alpha: 1)
        screenGlow.attenuationStartDistance = 4
        screenGlow.attenuationEndDistance = 28
        let glowNode = SCNNode()
        glowNode.name = "prop.monitor.screenGlow"
        glowNode.light = screenGlow
        glowNode.position = SCNVector3(0, 0, 3.0)
        panelPivot.addChildNode(glowNode)
    }

    private static func makeAnnularShadowTexture() -> CGImage {
        let size = 128
        return DeskTextures.makePixelImage(size, size) { ptr, _, _, _ in
            let invHalf = 2.0 / Float(size)
            for y in 0..<size {
                let ny = (Float(y) + 0.5) * invHalf - 1.0
                for x in 0..<size {
                    let nx = (Float(x) + 0.5) * invHalf - 1.0
                    let r = hypot(nx, ny)
                    // Ring stand covers normalized u ∈ [0.605, 0.904]; zero inside hollow interior u <= 0.52
                    let inner = max(0, min(1, (r - 0.52) / 0.14))
                    let outer = max(0, min(1, (0.99 - r) / 0.12))
                    let a = inner * inner * outer * outer
                    let idx = (y * size + x) * 4
                    ptr[idx + 0] = 0
                    ptr[idx + 1] = 0
                    ptr[idx + 2] = 0
                    ptr[idx + 3] = UInt8(max(0, min(255, a * 255.0)))
                }
            }
        }
    }

    // MARK: - Mac mini M4

    private static func buildMacMiniM4(into root: SCNNode) {
        let mini = SCNNode()
        mini.position = SCNVector3(MacMini.position.x, MacMini.position.y, MacMini.position.z)
        mini.eulerAngles.y = CGFloat(MacMini.yaw)
        root.addChildNode(mini)

        // Contact shadow underneath the floating aluminum under-belly & thermal pedestal
        DeskRoomAndMat.addContactShadow(
            at: SIMD3(MacMini.position.x, 0.005, MacMini.position.z),
            radiusX: 3.45, radiusZ: 3.45, opacity: 0.42, into: root
        )

        MacMiniModel.build(into: mini)

        // Rear C8 AC power + HDMI plugs and cables routing neatly behind the desk edge
        let bootMat = SCNMaterial()
        bootMat.lightingModel = .physicallyBased
        bootMat.diffuse.contents = NSColor(white: 0.06, alpha: 1)
        bootMat.roughness.contents = 0.56

        let cordMat = SCNMaterial()
        cordMat.lightingModel = .physicallyBased
        cordMat.diffuse.contents = NSColor(white: 0.045, alpha: 1)
        cordMat.roughness.contents = 0.72

        let acBoot = SCNBox(width: 0.56, height: 0.34, length: 0.90, chamferRadius: 0.08)
        acBoot.materials = [bootMat]
        let acBootNode = SCNNode(geometry: acBoot)
        acBootNode.position = SCNVector3(1.42, 0.99, -3.72)
        acBootNode.castsShadow = true
        mini.addChildNode(acBootNode)

        let hdmiBoot = SCNBox(width: 0.46, height: 0.21, length: 0.82, chamferRadius: 0.04)
        hdmiBoot.materials = [bootMat]
        let hdmiBootNode = SCNNode(geometry: hdmiBoot)
        hdmiBootNode.position = SCNVector3(-0.22, 0.99, -3.68)
        hdmiBootNode.castsShadow = true
        mini.addChildNode(hdmiBootNode)

        func addRearCable(radius: Float, control: [SIMD3<Float>]) {
            let pts = MeshBuilder.catmullRom(control, samplesPerSegment: 10)
            let geo = MeshBuilder.tube(points: pts, radius: radius, segments: 10)
            geo.materials = [cordMat]
            let node = SCNNode(geometry: geo)
            node.castsShadow = true
            mini.addChildNode(node)
        }

        addRearCable(radius: 0.095, control: [
            SIMD3(1.42, 0.99, -4.12),
            SIMD3(1.42, 0.84, -4.90),
            SIMD3(1.12, 0.28, -6.15),
            SIMD3(0.45, 0.10, -8.15),
            SIMD3(-0.35, 0.10, -11.05),
            SIMD3(-0.45, -0.35, -11.50),
            SIMD3(-0.48, -2.10, -11.20),
            SIMD3(-0.50, -2.35, -10.10),
        ])

        addRearCable(radius: 0.082, control: [
            SIMD3(-0.22, 0.99, -4.04),
            SIMD3(-0.25, 0.82, -4.78),
            SIMD3(-0.68, 0.25, -6.05),
            SIMD3(-1.45, 0.09, -8.25),
            SIMD3(-2.35, 0.09, -11.05),
            SIMD3(-2.42, -0.35, -11.50),
            SIMD3(-2.45, -2.10, -11.20),
            SIMD3(-2.48, -2.35, -10.10),
        ])
    }

    /// Mac mini placement and front-panel layout, shared with the earphone plug in AudioAndLightProps.
    enum MacMini {
        static let position = SIMD3<Float>(18.2, 0, -14.2)
        static let yaw: Float = 0.08
        static let halfDepth: Float = MacMiniModel.halfD
        static let portY: Float = MacMiniModel.portY
        static let usbX: [Float] = MacMiniModel.usbX
        static let jackX: Float = MacMiniModel.jackX

        /// World position of the headphone jack opening, and the direction pointing out of it.
        static var jack: (position: SIMD3<Float>, outward: SIMD3<Float>) {
            let c = cos(yaw), s = sin(yaw)
            func world(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
                position + SIMD3(x * c + z * s, y, -x * s + z * c)
            }
            return (world(jackX, portY, halfDepth - 0.012), SIMD3(s, 0, c))
        }
    }

    // MARK: - MCHOSE G7 Ergonomic Mouse

    /// Node names the scene uses to light the mouse's buttons and DPI LED.
    enum MouseParts {
        static let root = "g7"
        static let wheel = "g7-wheel"
        static let left = "g7-left"
        static let right = "g7-right"
        static let back = "g7-back"
        static let forward = "g7-forward"
        static let dpiLED = "g7-dpi-led"
    }

    private static func buildMchoseG7(into root: SCNNode) {
        let mouse = SCNNode()
        mouse.name = MouseParts.root
        mouse.position = SCNVector3(12.6, DeskRoomAndMat.matTopY, -0.6)
        mouse.eulerAngles.y = -0.08
        root.addChildNode(mouse)

        // Contact shadow underneath mouse on the Ukiru mat
        DeskRoomAndMat.addContactShadow(at: SIMD3(12.6, DeskRoomAndMat.matTopY + 0.004, -0.6), radiusX: 1.95, radiusZ: 3.25, opacity: 0.28, into: root)

        let whiteShell = SCNMaterial()
        whiteShell.lightingModel = .physicallyBased
        whiteShell.diffuse.contents = DeskTextures.mchoseTopShell()
        whiteShell.diffuse.mipFilter = .linear
        whiteShell.diffuse.maxAnisotropy = 8
        whiteShell.roughness.contents = DeskTextures.mchoseRoughness()
        whiteShell.normal.contents = DeskTextures.pbtMicroNormal()
        whiteShell.normal.wrapS = .repeat
        whiteShell.normal.wrapT = .repeat
        whiteShell.normal.contentsTransform = SCNMatrix4MakeScale(7, 7, 1)
        whiteShell.normal.intensity = 0.025
        whiteShell.metalness.contents = 0.0
        whiteShell.clearCoat.contents = 0.15
        whiteShell.clearCoatRoughness.contents = 0.34


        let seamDark = SCNMaterial()
        seamDark.lightingModel = .physicallyBased
        seamDark.diffuse.contents = NSColor(white: 0.06, alpha: 1)
        seamDark.roughness.contents = 0.6

        G7Model.build(into: mouse, shell: whiteShell, dark: seamDark)

        // Press highlights for the click paddles: glowing copies lifted just off them, hidden until held.
        for (left, name) in [(true, MouseParts.left), (false, MouseParts.right)] {
            let geo = G7Model.paddle(left: left, lift: 0.02)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = NSColor.controlAccentColor
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            m.blendMode = .add
            geo.materials = [m]
            let node = SCNNode(geometry: geo)
            node.name = name
            node.opacity = 0
            node.renderingOrder = 10
            mouse.addChildNode(node)
        }
    }

}
