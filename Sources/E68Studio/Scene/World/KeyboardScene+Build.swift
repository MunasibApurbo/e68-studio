import SceneKit
import AppKit
import simd

extension KeyboardScene {
    // MARK: Environment

    func buildEnvironment() {
        var backlightSync = [SCNNode]()
        let matTexture = Self.resource("ukiru-mat.jpg")
        scene.background.contents = NSColor(srgbRed: 0.72, green: 0.73, blue: 0.74, alpha: 1)
        scene.rootNode.addChildNode(modelWorld)
        scenarioRoot.name = "env.scenario.root"
        scene.rootNode.addChildNode(scenarioRoot)
        DeskRoomAndMat.build(into: modelWorld, matTexture: matTexture, keyboardBacklightSync: &backlightSync)
        TechProps.build(into: modelWorld)
        AudioAndLightProps.build(into: modelWorld)
        PlantProps.build(into: modelWorld)

        // Contact shadow under the keyboard on top of the Ukiru mat (subtle AO base; 4K key shadow + SSAO carry main grounding).
        let shadow = SCNPlane(width: 18.4, height: 6.8)
        let shade = SCNMaterial()
        shade.lightingModel = .constant
        shade.diffuse.contents = Self.image(256, 128) { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: 256, height: 128))
            ctx.setShadow(offset: .zero, blur: 10, color: NSColor(white: 0, alpha: 0.34).cgColor)
            ctx.setFillColor(NSColor(white: 0, alpha: 0.28).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 34, y: 26, width: 188, height: 76), cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.fillPath()
        }
        shade.blendMode = .alpha
        shade.writesToDepthBuffer = false
        shadow.materials = [shade]
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles.x = -.pi / 2
        shadowNode.position = SCNVector3(0.0, DeskRoomAndMat.matTopY + 0.003, 0.04)
        shadowNode.castsShadow = false
        shadowNode.renderingOrder = 1
        scene.rootNode.addChildNode(shadowNode)
        keyboardShadow = shadowNode

        // Avoid building the 1024x512 room HDR environment during startup when another scenario is active.
        let initialScenario = UserDefaults.standard.string(forKey: AmbienceKeys.deskScenario)
            .flatMap(DeskScenario.init(rawValue:)) ?? .swissAlps
        if initialScenario == .room {
            let initialMood = UserDefaults.standard.string(forKey: AmbienceKeys.deskMood)
                .flatMap(DeskMood.init(rawValue:)) ?? .daylight
            scene.lightingEnvironment.contents = hdrEnvironmentImage(mood: initialMood, deskLampOn: true)
            scene.lightingEnvironment.intensity = initialMood == .midnight ? 0.44 : 0.76
        }

        // Primary overhead/front-left room key light (steeper overhead ceiling pitch keeps monitor/lamp shadows
        // grounded behind/beneath objects rather than projecting hard cutout shadows onto the upper back wall).
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 760
        keyLight.color = NSColor(srgbRed: 1.0, green: 0.982, blue: 0.955, alpha: 1)
        keyLight.castsShadow = true
        keyLight.automaticallyAdjustsShadowProjection = true
        keyLight.maximumShadowDistance = 95
        keyLight.shadowCascadeCount = 3
        keyLight.shadowCascadeSplittingFactor = 0.25
        keyLight.sampleDistributedShadowMaps = false
        keyLight.shadowRadius = 2.4
        keyLight.shadowSampleCount = 32
        keyLight.shadowColor = NSColor(white: 0, alpha: 0.92)
        keyLight.shadowBias = 0.0075
        keyLight.shadowMapSize = CGSize(width: 4096, height: 4096)
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.position = SCNVector3(-8, 52, 22)
        keyNode.look(at: SCNVector3(2, 1, -8))
        scene.rootNode.addChildNode(keyNode)
        keyLightNode = keyNode
        keyLightBaseIntensity = 760

        // Gentle cool-neutral room bounce fill from upper-right (lifts deep shadow flanks with subtle sky coolness
        // without washing out directional shadow contrast or wall shadows).
        let fill = SCNLight()
        fill.type = .omni
        fill.intensity = 175
        fill.color = NSColor(srgbRed: 0.85, green: 0.90, blue: 1.0, alpha: 1)
        fill.attenuationStartDistance = 28
        fill.attenuationEndDistance = 125
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(38, 26, 36)
        scene.rootNode.addChildNode(fillNode)
        fillLightNode = fillNode
        fillLightBaseIntensity = 175

        // Soft upper-ceiling room bounce keeping the plaster back wall bright cream while preserving cast shadows.
        let room = SCNLight()
        room.type = .directional
        room.intensity = 155
        room.color = NSColor(srgbRed: 0.99, green: 0.982, blue: 0.972, alpha: 1)
        room.castsShadow = false
        let roomNode = SCNNode()
        roomNode.light = room
        roomNode.position = SCNVector3(-6, 46, 52)
        roomNode.look(at: SCNVector3(2, 4, -22))
        scene.rootNode.addChildNode(roomNode)
        roomLightNode = roomNode
        roomLightBaseIntensity = 155

        cacheAmbienceNodes()
        applyMonitorWallpaper(token: UserDefaults.standard.string(forKey: DeskWallpaperKeys.token) ?? "")
    }

    // MARK: Keyboard

    private static func plastic(_ color: NSColor, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        return m
    }

    static let capWhite = NSColor(srgbRed: 0.855, green: 0.850, blue: 0.836, alpha: 1)
    static let capBlack = NSColor(srgbRed: 0.042, green: 0.044, blue: 0.050, alpha: 1)

    func buildKeyboard() {
        keyboard.eulerAngles.x = CGFloat(CaseMesh.tiltRad)
        keyboard.position = SCNVector3(0, CGFloat(DeskRoomAndMat.matTopY + CaseMesh.kbPosYOffset), 0)
        scene.rootNode.addChildNode(keyboard)

        let cx: Float = Float(Layout.width) / 2, cz: Float = 2.5625

        // Two-piece electrophoresis-white CNC aluminum wedge chassis with stepped bezel rim,
        // recessed circular knob pocket, rear ports/switches, rubber feet and hex screws.
        let pbtNormal = DeskTextures.pbtMicroNormal()
        let caseMaterial = SCNMaterial()
        caseMaterial.lightingModel = .physicallyBased
        caseMaterial.diffuse.contents = NSColor(srgbRed: 0.872, green: 0.872, blue: 0.868, alpha: 1)
        caseMaterial.metalness.contents = 0.05
        caseMaterial.roughness.contents = 0.30
        caseMaterial.clearCoat.contents = 0.24
        caseMaterial.clearCoatRoughness.contents = 0.22
        caseMaterial.normal.contents = pbtNormal
        caseMaterial.normal.wrapS = .repeat
        caseMaterial.normal.wrapT = .repeat
        caseMaterial.normal.contentsTransform = SCNMatrix4MakeScale(10, 5, 1)
        caseMaterial.normal.intensity = 0.035
        caseMaterial.isDoubleSided = true
        CaseMesh.build(into: keyboard, caseMaterial: caseMaterial, plateY: Self.plateY)

        // Frosted light-grey slotted polycarbonate plate inside the keywell.
        let plate = SCNBox(width: CGFloat(Layout.width) - 0.04, height: 0.02, length: 5.08, chamferRadius: 0)
        plate.materials = [Self.plastic(NSColor(srgbRed: 0.78, green: 0.79, blue: 0.81, alpha: 1), roughness: 0.44)]
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(0, Self.plateY + 0.008, 0)
        plateNode.castsShadow = false
        keyboard.addChildNode(plateNode)

        // Single unified dynamic backlight glow plane spanning the keywell.
        let platePlane = SCNPlane(width: CGFloat(Self.plateGlowPlaneW), height: CGFloat(Self.plateGlowPlaneH))
        plateGlowMaterial.lightingModel = .constant
        plateGlowMaterial.diffuse.contents = NSColor.black
        plateGlowMaterial.emission.contents = NSColor.black
        plateGlowMaterial.emission.intensity = 2.85
        plateGlowMaterial.blendMode = .add
        plateGlowMaterial.writesToDepthBuffer = false
        plateGlowMaterial.isDoubleSided = true
        platePlane.materials = [plateGlowMaterial]
        let plateGlowNode = SCNNode(geometry: platePlane)
        plateGlowNode.eulerAngles.x = -.pi / 2
        plateGlowNode.position = SCNVector3(0, Self.plateY + 0.032, 0)
        plateGlowNode.castsShadow = false
        plateGlowNode.renderingOrder = 5
        keyboard.addChildNode(plateGlowNode)

        // Keywell perimeter halo texture for the circular rotary knob pocket.
        let glowSprite = Self.image(128, 128) { ctx in
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            let g = CGGradient(
                colorsSpace: srgb,
                colors: [
                    NSColor(white: 0.90, alpha: 1).cgColor,
                    NSColor(white: 1.0, alpha: 1).cgColor,
                    NSColor(white: 0.58, alpha: 1).cgColor,
                    NSColor.black.cgColor,
                ] as CFArray,
                locations: [0.0, 0.50, 0.76, 0.95]
            )!
            ctx.drawRadialGradient(
                g,
                startCenter: CGPoint(x: 64, y: 64),
                startRadius: 0,
                endCenter: CGPoint(x: 64, y: 64),
                endRadius: 61,
                options: []
            )
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 10, color: NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(12)
            let inset: CGFloat = 20
            let rect = CGRect(x: inset, y: inset, width: 128 - inset * 2, height: 128 - inset * 2)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil))
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Keycaps: matte double-shot PBT + merged static Lemon Grapes switches (lavender housing & gold stem).
        var housingCenters = [SIMD3<Float>]()
        var stemCenters = [SIMD3<Float>]()
        housingCenters.reserveCapacity(Layout.keys.count)
        stemCenters.reserveCapacity(Layout.keys.count)
        glowSlots.reserveCapacity(Layout.keys.count)

        let gw = Self.plateGlowWidth
        let gh = Self.plateGlowHeight
        let halfGlowW = Self.plateGlowPlaneW * 0.5
        let halfGlowH = Self.plateGlowPlaneH * 0.5
        let knobCutX: Float = 15.0 - cx - 0.04
        let knobCutZ: Float = 1.0 - cz + 0.04

        func smoothstep(_ e0: Float, _ e1: Float, _ v: Float) -> Float {
            let u = min(max((v - e0) / (e1 - e0), 0), 1)
            return u * u * (3 - 2 * u)
        }

        for slot in Layout.keys {
            let index = slot.index
            let dark = Self.darkKeys.contains(index)
            let rowTilt: [Float] = [0.09, 0.05, -0.01, -0.07, -0.08]
            let rowHeight: [Float] = [0.50, 0.44, 0.41, 0.44, 0.46]
            let r = min(max(Int(slot.y.rounded(.down)), 0), 4)
            let cap = CapMesh.make(width: Float(slot.w), height: rowHeight[r], tilt: rowTilt[r], convex: slot.w > 3)

            let side = Self.plastic(dark ? Self.capBlack : Self.capWhite, roughness: dark ? 0.56 : 0.60)
            side.normal.contents = pbtNormal
            side.normal.wrapS = .repeat
            side.normal.wrapT = .repeat
            side.normal.contentsTransform = SCNMatrix4MakeScale(2.5, 1.4, 1.0)
            side.normal.intensity = 0.052
            side.shaderModifiers = [.surface: """
                float skirt = pow(clamp(1.0 - _surface.normalTexcoord.y, 0.0, 1.0), 2.10);
                _surface.emission.rgb *= skirt;
            """]
            let top = Self.plastic(dark ? Self.capBlack : Self.capWhite, roughness: dark ? 0.56 : 0.60)
            top.diffuse.minificationFilter = .linear
            top.diffuse.magnificationFilter = .linear
            top.diffuse.mipFilter = .linear
            top.diffuse.maxAnisotropy = 16
            top.normal.contents = pbtNormal
            top.normal.wrapS = .repeat
            top.normal.wrapT = .repeat
            top.normal.contentsTransform = SCNMatrix4MakeScale(2.0, 2.0, 1)
            top.normal.intensity = 0.045
            cap.geometry.materials = [side, top]
            topMaterials[index] = top

            let node = SCNNode(geometry: cap.geometry)
            node.name = "k\(index)"
            let x = Float(slot.x + slot.w / 2) - cx, z = Float(slot.y) + 0.5 - cz
            node.position = SCNVector3(x, Self.capBaseY, z)
            keyboard.addChildNode(node)
            capNodes[index] = node
            restY[index] = Self.capBaseY
            keyX[index] = x
            keyZ[index] = z
            let col = min(15, max(0, Int((slot.x / Layout.width) * 16.0)))
            let vLevel = Float(4 - min(4, max(0, Int(slot.y.rounded(.down)))))

            housingCenters.append(SIMD3(x, Self.plateY + 0.095, z))
            stemCenters.append(SIMD3(x, Self.plateY + 0.19, z))

            // Precompute sparse pixel weights for the unified plate glow texture.
            let innerX = max(0, Float(slot.w) * 0.5 - 0.14)
            let outerX = Float(slot.w) * 0.5 + 0.14
            let innerZ: Float = 0.36
            let outerZ: Float = 0.64
            let pxMin = max(0, Int(floor(((x - outerX + halfGlowW) / Self.plateGlowPlaneW) * Float(gw))))
            let pxMax = min(gw - 1, Int(ceil(((x + outerX + halfGlowW) / Self.plateGlowPlaneW) * Float(gw))))
            let pyMin = max(0, Int(floor(((z - outerZ + halfGlowH) / Self.plateGlowPlaneH) * Float(gh))))
            let pyMax = min(gh - 1, Int(ceil(((z + outerZ + halfGlowH) / Self.plateGlowPlaneH) * Float(gh))))

            var pixelMask = [PlatePixelWeight]()
            pixelMask.reserveCapacity((pxMax - pxMin + 1) * (pyMax - pyMin + 1))
            for py in pyMin...pyMax {
                let kz = ((Float(py) + 0.5) / Float(gh) - 0.5) * Self.plateGlowPlaneH
                let wz = 1.0 - smoothstep(innerZ, outerZ, abs(kz - z))
                if wz <= 0.005 { continue }
                let edgeZ = smoothstep(0.0, 0.12, 2.52 - abs(kz))
                for px in pxMin...pxMax {
                    let kx = ((Float(px) + 0.5) / Float(gw) - 0.5) * Self.plateGlowPlaneW
                    let wx = 1.0 - smoothstep(innerX, outerX, abs(kx - x))
                    if wx <= 0.005 { continue }
                    let edgeX = smoothstep(0.0, 0.12, 8.10 - abs(kx))
                    let knobMask = max(smoothstep(knobCutX + 0.08, knobCutX - 0.08, kx),
                                       smoothstep(knobCutZ - 0.08, knobCutZ + 0.08, kz))
                    let w = wx * wz * edgeX * edgeZ * knobMask
                    if w > 0.01 {
                        pixelMask.append(PlatePixelWeight(offset: py * gw + px, weight: w))
                    }
                }
            }

            glowSlots.append(
                GlowSlot(
                    index: index,
                    x: x,
                    z: z,
                    col: col,
                    vLevel: vLevel,
                    sideMaterial: side,
                    isDark: dark,
                    pixelMask: pixelMask
                )
            )
        }

        let housingGeo = Self.mergedBoxesGeometry(centers: housingCenters, halfExtents: SIMD3(0.34, 0.08, 0.34))
        housingGeo.materials = [Self.plastic(NSColor(srgbRed: 0.46, green: 0.36, blue: 0.66, alpha: 1), roughness: 0.38)]
        let housingNode = SCNNode(geometry: housingGeo)
        housingNode.castsShadow = false
        keyboard.addChildNode(housingNode)

        let stemGeo = Self.mergedBoxesGeometry(centers: stemCenters, halfExtents: SIMD3(0.12, 0.035, 0.12))
        stemGeo.materials = [Self.plastic(NSColor(srgbRed: 0.84, green: 0.70, blue: 0.30, alpha: 1), roughness: 0.42)]
        let stemNode = SCNNode(geometry: stemGeo)
        stemNode.castsShadow = false
        keyboard.addChildNode(stemNode)

        // Subtle circular backlight ring inside the rotary knob pocket.
        let knobHalo = SCNPlane(width: 1.04, height: 1.04)
        knobGlowMaterial.lightingModel = .constant
        knobGlowMaterial.diffuse.contents = NSColor.black
        knobGlowMaterial.emission.contents = glowSprite
        knobGlowMaterial.emission.intensity = 1.45
        knobGlowMaterial.multiply.contents = NSColor.black
        knobGlowMaterial.blendMode = .add
        knobGlowMaterial.writesToDepthBuffer = false
        knobGlowMaterial.isDoubleSided = true
        knobHalo.materials = [knobGlowMaterial]
        let knobHaloNode = SCNNode(geometry: knobHalo)
        knobHaloNode.eulerAngles.x = -.pi / 2
        knobHaloNode.position = SCNVector3(CaseMesh.knobCenterX, CaseMesh.knobPocketFloorY + 0.015, CaseMesh.knobCenterZ)
        knobHaloNode.castsShadow = false
        knobHaloNode.renderingOrder = 5
        keyboard.addChildNode(knobHaloNode)

        // Rotary knob: matte/satin white matching the white chassis.
        knobMaterial.lightingModel = .physicallyBased
        knobMaterial.diffuse.contents = NSColor(srgbRed: 0.872, green: 0.872, blue: 0.868, alpha: 1)
        knobMaterial.metalness.contents = 0.05
        knobMaterial.roughness.contents = 0.30
        knobMaterial.normal.contents = pbtNormal
        knobMaterial.normal.wrapS = .repeat
        knobMaterial.normal.wrapT = .repeat
        knobMaterial.normal.contentsTransform = SCNMatrix4MakeScale(2, 2, 1)
        knobMaterial.normal.intensity = 0.035
        knobMaterial.clearCoat.contents = 0.24
        knobMaterial.clearCoatRoughness.contents = 0.22
        let knobHeight: Float = 0.49
        let knobBaseY = CaseMesh.knobPocketFloorY + 0.055
        let barrel = CapMesh.knob(radius: 0.436, height: knobHeight)
        barrel.materials = [knobMaterial]
        knob.geometry = barrel

        knob.name = "k\(Layout.knobPress.index)"
        knob.position = SCNVector3(CaseMesh.knobCenterX, knobBaseY, CaseMesh.knobCenterZ)
        keyboard.addChildNode(knob)
        capNodes[Layout.knobPress.index] = knob
        restY[Layout.knobPress.index] = knobBaseY

        topMaterials[Layout.knobPress.index] = knobMaterial
        topMaterials[Layout.knobCCW.index] = knobMaterial
        topMaterials[Layout.knobCW.index] = knobMaterial
    }

    private static func mergedBoxesGeometry(centers: [SIMD3<Float>], halfExtents e: SIMD3<Float>) -> SCNGeometry {
        let localVerts: [SIMD3<Float>] = [
            SIMD3(-e.x, -e.y, -e.z), SIMD3( e.x, -e.y, -e.z), SIMD3( e.x,  e.y, -e.z), SIMD3(-e.x,  e.y, -e.z),
            SIMD3(-e.x, -e.y,  e.z), SIMD3( e.x, -e.y,  e.z), SIMD3( e.x,  e.y,  e.z), SIMD3(-e.x,  e.y,  e.z),
        ]
        // 5 visible faces (+Y, -X, +X, -Z, +Z); bottom -Y sits flush on the plate.
        let faces: [(v: (Int, Int, Int, Int), n: SIMD3<Float>)] = [
            ((3, 7, 6, 2), SIMD3(0, 1, 0)),
            ((0, 4, 7, 3), SIMD3(-1, 0, 0)),
            ((1, 2, 6, 5), SIMD3(1, 0, 0)),
            ((0, 3, 2, 1), SIMD3(0, 0, -1)),
            ((4, 5, 6, 7), SIMD3(0, 0, 1)),
        ]
        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [Int32]()
        positions.reserveCapacity(centers.count * 20)
        normals.reserveCapacity(centers.count * 20)
        uvs.reserveCapacity(centers.count * 20)
        indices.reserveCapacity(centers.count * 30)

        for c in centers {
            for f in faces {
                let base = Int32(positions.count)
                for vi in [f.v.0, f.v.1, f.v.2, f.v.3] {
                    positions.append(c + localVerts[vi])
                    normals.append(f.n)
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

    func hdrEnvironmentImage(mood: DeskMood, deskLampOn: Bool) -> CGImage {
        let key = HDREnvKey(mood: mood, deskLampOn: deskLampOn)
        if let cached = hdrEnvironmentCache[key] { return cached }

        let w = 1024, h = 512
        var pixels = [Float](repeating: 0, count: w * h * 4)

        let ambientScale: Float
        let skyGain: Float
        let warmBounce: Float
        let groundColor: SIMD3<Float>
        let wallColor: SIMD3<Float>
        let ceilColor: SIMD3<Float>

        switch mood {
        case .daylight:
            ambientScale = 0.98
            skyGain = 1.12
            warmBounce = 0.88
            groundColor = SIMD3(0.024, 0.017, 0.011)
            wallColor = SIMD3(0.18, 0.175, 0.172)
            ceilColor = SIMD3(0.30, 0.31, 0.33)
        case .midnight:
            ambientScale = 0.42
            skyGain = 0.14
            warmBounce = 1.38
            groundColor = SIMD3(0.008, 0.006, 0.006)
            wallColor = SIMD3(0.020, 0.022, 0.030)
            ceilColor = SIMD3(0.028, 0.032, 0.048)
        }

        @inline(__always)
        func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
            let t = min(max((x - e0) / (e1 - e0), 0), 1)
            return t * t * (3 - 2 * t)
        }

        // Crisp diffused panel in unit-direction space using an orthonormal tangent frame
        @inline(__always)
        func panel(_ dir: SIMD3<Float>, center: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>, halfW: Float, halfH: Float, edge: Float) -> Float {
            let d = simd_dot(dir, center)
            guard d > 0.05 else { return 0 }
            let u = simd_dot(dir, right) / d
            let v = simd_dot(dir, up) / d
            let mx = 1.0 - smooth(halfW - edge, halfW + edge, abs(u))
            let my = 1.0 - smooth(halfH - edge, halfH + edge, abs(v))
            return mx * my
        }

        let mainLightCenter = simd_normalize(SIMD3<Float>(-0.34, 0.72, 0.60))
        let mainRight = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), mainLightCenter))
        let mainUp = simd_cross(mainLightCenter, mainRight)

        let windowCenter = simd_normalize(SIMD3<Float>(0.68, 0.36, 0.63))
        let winRight = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), windowCenter))
        let winUp = simd_cross(windowCenter, winRight)

        let overheadCenter = simd_normalize(SIMD3<Float>(0.06, 0.94, 0.32))
        let ovRight = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), overheadCenter))
        let ovUp = simd_cross(overheadCenter, ovRight)

        let deskLampLobe = simd_normalize(SIMD3<Float>(-0.56, 0.14, -0.82))
        let monitorLobe = simd_normalize(SIMD3<Float>(0.04, 0.06, -0.996))
        let frontBounce = simd_normalize(SIMD3<Float>(0.0, 0.10, 0.995))

        pixels.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            DispatchQueue.concurrentPerform(iterations: h) { row in
                let v = (Float(row) + 0.5) / Float(h)
                let elev = (0.5 - v) * .pi
                let ny = sin(elev)
                let cosE = cos(elev)

                for col in 0..<w {
                    let u = (Float(col) + 0.5) / Float(w)
                    let az = (u - 0.5) * 2.0 * .pi
                    let nx = sin(az) * cosE
                    let nz = -cos(az) * cosE
                    let dir = SIMD3<Float>(nx, ny, nz)

                    var rgb: SIMD3<Float>
                    if ny < 0 {
                        let t = smooth(-0.35, 0.02, ny)
                        let floorGr = 0.85 + 0.15 * sin(az * 6.0)
                        rgb = groundColor * floorGr * (1.0 - t) + wallColor * 0.42 * t
                    } else {
                        let t = smooth(0.0, 0.48, ny)
                        // Subtle room corner/studio bookshelf shadow contrast so glossy glass & phone catch crisp architectural lines
                        let wallPanel = 0.82 + 0.18 * smooth(0.05, 0.25, cos(az * 2.0 + 0.6))
                        rgb = wallColor * wallPanel * (1.0 - t) + ceilColor * t
                    }

                    // Overhead room ceiling softbox & front-left key fixture (creates natural metal/glass/clearcoat catchlights)
                    let keyBox = panel(dir, center: mainLightCenter, right: mainRight, up: mainUp, halfW: 0.44, halfH: 0.24, edge: 0.04)
                    rgb += SIMD3<Float>(5.8, 5.5, 5.05) * keyBox * skyGain

                    // Multi-pane daylight window with crisp architectural mullions (real catchlights in phone/OLED/glass bottles)
                    let wd = simd_dot(dir, windowCenter)
                    var windowMask: Float = 0
                    if wd > 0.08 {
                        let wu = simd_dot(dir, winRight) / wd
                        let wv = simd_dot(dir, winUp) / wd
                        let paneOuter = (1.0 - smooth(0.24, 0.28, abs(wu))) * (1.0 - smooth(0.56, 0.60, abs(wv)))
                        let mullionV = smooth(0.018, 0.032, abs(wu))
                        let mullionH = smooth(0.018, 0.032, abs(wv - 0.14)) * smooth(0.018, 0.032, abs(wv + 0.24))
                        windowMask = paneOuter * mullionV * mullionH
                        // Subtle window frame trim highlight/shadow
                        let skyGrad = 0.85 + 0.30 * max(0, wv + 0.4)
                        rgb += SIMD3<Float>(4.4, 4.9, 5.8) * windowMask * skyGrad * skyGain
                    }

                    // Diffused ceiling strip overhead with clean housing rim
                    let ceilStrip = panel(dir, center: overheadCenter, right: ovRight, up: ovUp, halfW: 0.62, halfH: 0.12, edge: 0.035)
                    rgb += SIMD3<Float>(3.4, 3.45, 3.55) * ceilStrip * skyGain

                    // Viewer-side secondary fill strip (crisp horizontal edge catchlight on phone glass & Mac mini top bevel)
                    let frontStrip = panel(dir, center: frontBounce, right: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0), halfW: 0.55, halfH: 0.16, edge: 0.06)
                    rgb += SIMD3<Float>(0.55, 0.58, 0.64) * frontStrip * max(0.22, skyGain)

                    // Monitor screen cool-white reflection lobe toward desk/glass front
                    let monGlow = pow(max(0, simd_dot(dir, monitorLobe)), 14)
                    rgb += SIMD3<Float>(0.55, 0.62, 0.78) * monGlow * (mood == .midnight ? 0.95 : 0.45)

                    // Soft viewer-side room wall fill so front glass faces keep gentle depth without harsh flash
                    let frontFill = pow(max(0, simd_dot(dir, frontBounce)), 3)
                    rgb += SIMD3<Float>(0.08, 0.085, 0.10) * frontFill * ambientScale

                    // Physical wall bounce reflections when desk lamp is switched on
                    if deskLampOn {
                        let dDot = max(0, simd_dot(dir, deskLampLobe))
                        rgb += SIMD3<Float>(1.65, 0.42, 0.55) * pow(dDot, 12) * warmBounce
                        rgb += SIMD3<Float>(0.22, 0.08, 0.11) * pow(dDot, 3) * warmBounce
                    }

                    let idx = (row * w + col) * 4
                    base[idx]     = rgb.x
                    base[idx + 1] = rgb.y
                    base[idx + 2] = rgb.z
                    base[idx + 3] = 1.0
                }
            }
        }

        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.floatComponents.rawValue
            | CGImageByteOrderInfo.order32Host.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 32,
            bitsPerPixel: 128,
            bytesPerRow: w * 16,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
        hdrEnvironmentCache.removeAll()
        hdrEnvironmentCache[key] = image
        return image
    }

    func buildCamera() {
        let camera = SCNCamera()
        camera.projectionDirection = .vertical
        camera.zNear = 1.0
        camera.zFar = 1600
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0.0
        camera.whitePoint = 1.12
        camera.bloomIntensity = 0.075
        camera.bloomThreshold = 1.38
        camera.bloomBlurRadius = 7.0
        camera.screenSpaceAmbientOcclusionIntensity = 0.44
        camera.screenSpaceAmbientOcclusionRadius = 0.88
        camera.screenSpaceAmbientOcclusionBias = 0.085
        camera.screenSpaceAmbientOcclusionDepthThreshold = 1.80
        camera.screenSpaceAmbientOcclusionNormalThreshold = 0.50
        camera.vignettingIntensity = 0.18
        camera.vignettingPower = 1.18
        camera.contrast = 0.08
        camera.saturation = 1.04
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }
}
