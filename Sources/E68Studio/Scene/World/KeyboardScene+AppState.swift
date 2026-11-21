import SceneKit
import AppKit
import simd

extension KeyboardScene {
    // MARK: State from the app

    func setLegends(_ next: [Int: Legend]) {
        var updated = false
        for (index, legend) in next where legends[index] != legend {
            legends[index] = legend
            guard let material = topMaterials[index], let slot = Layout.slot(at: index) else { continue }
            let dark = Self.darkKeys.contains(index)
            material.diffuse.contents = LegendPainter.texture(legend, width: slot.w, dark: dark,
                                                              background: dark ? Self.capBlack : Self.capWhite)
            updated = true
        }
        if updated {
            materialRevision &+= 1
            bumpTransientRender(seconds: 0.1)
        }
    }

    func setSelection(_ index: Int?) {
        guard index != selected else { return }
        let old = selected
        selected = index
        if let old {
            updateKeyEmission(old)
            settle(old)
        }
        if let index {
            updateKeyEmission(index)
            settle(index)
        }
        updateKnobEmission()
        materialRevision &+= 1
        bumpTransientRender(seconds: 0.2)
    }

    /// Keys that have registered in the key test glow green.
    func setMarked(_ next: Set<Int>) {
        guard next != marked else { return }
        let diff = next.symmetricDifference(marked)
        marked = next
        for index in diff {
            updateKeyEmission(index)
        }
        updateKnobEmission()
        materialRevision &+= 1
        bumpTransientRender(seconds: 0.15)
    }

    func setHeatmap(_ weights: [Int: Float], active: Bool) {
        guard active != heatmapActive || (active && weights != heatmapWeights) else { return }
        heatmapActive = active
        heatmapWeights = weights
        for slot in Layout.keys {
            updateKeyEmission(slot.index)
        }
        updateKnobEmission()
        materialRevision &+= 1
        bumpTransientRender(seconds: 0.2)
    }

    private func updateKeyEmission(_ index: Int) {
        if index == selected {
            topMaterials[index]?.emission.contents = NSColor.controlAccentColor.withAlphaComponent(1).blended(withFraction: 0.45, of: .black)
        } else if heatmapActive {
            let w = heatmapWeights[index] ?? 0
            topMaterials[index]?.emission.contents = KeyboardStore.heatmapColor(intensity: w)
        } else {
            let shouldGlow = marked.contains(index) || (isKnob(index) && hasAnyKnobMarked(marked))
            topMaterials[index]?.emission.contents = shouldGlow ? NSColor(srgbRed: 0.0, green: 0.32, blue: 0.14, alpha: 1) : NSColor.black
        }
    }

    func cacheAmbienceNodes() {
        deskLampLights.removeAll()
        deskLampEmitters.removeAll()
        deskLampWallNodes.removeAll()
        underDeskGlowAccents.removeAll()
        monitorScreenGlowAccents.removeAll()

        let fallbackBulbPink = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.60, alpha: 1)

        func emitter(for node: SCNNode, fallbackColor: NSColor, forceColorFallback: Bool = false) -> CachedEmitterMaterial? {
            guard let mat = node.geometry?.firstMaterial else { return nil }
            let rawEmission = mat.emission.contents
            let onColor: Any
            if forceColorFallback, rawEmission is NSColor {
                onColor = fallbackColor
            } else if let color = rawEmission as? NSColor, color == NSColor.black || color.alphaComponent <= 0.01 {
                onColor = fallbackColor
            } else if let existing = rawEmission {
                onColor = existing
            } else {
                onColor = fallbackColor
            }
            let baseIntensity = mat.emission.intensity > 0 ? mat.emission.intensity : 1.0
            return CachedEmitterMaterial(material: mat, onColor: onColor, baseIntensity: baseIntensity)
        }

        modelWorld.enumerateChildNodes { node, _ in
            guard let name = node.name else { return }
            switch name {
            case "prop.deskLamp.spot", "prop.deskLamp.wallSpot", "prop.deskLamp.wallGlow":
                if let light = node.light {
                    deskLampLights.append(CachedLightNode(light: light, baseIntensity: light.intensity))
                }
            case "prop.deskLamp.bulb", "prop.deskLamp.reflector":
                if let e = emitter(for: node, fallbackColor: fallbackBulbPink) {
                    deskLampEmitters.append(e)
                }
            case "env.room.root":
                roomRootNode = node
            case "env.wallGlow.deskLamp":
                let cachedLight = node.light.map { CachedLightNode(light: $0, baseIntensity: $0.intensity) }
                deskLampWallNodes.append(CachedWallGlowNode(node: node, light: cachedLight))
            case "prop.underDeskGlow":
                let cachedLight = node.light.map { CachedLightNode(light: $0, baseIntensity: $0.intensity) }
                let cachedEm = node.geometry?.firstMaterial.map {
                    CachedEmitterMaterial(material: $0, onColor: $0.emission.contents ?? NSColor.black, baseIntensity: $0.emission.intensity)
                }
                underDeskGlowAccents.append(CachedAccentNode(light: cachedLight, emitter: cachedEm))
            case "prop.monitor.screen":
                monitorScreenMaterial = node.geometry?.firstMaterial
            case "prop.monitor.screenGlow":
                monitorGlowLight = node.light
                let cachedLight = node.light.map { CachedLightNode(light: $0, baseIntensity: $0.intensity) }
                let cachedEm = node.geometry?.firstMaterial.map {
                    CachedEmitterMaterial(material: $0, onColor: $0.emission.contents ?? NSColor.black, baseIntensity: $0.emission.intensity)
                }
                monitorScreenGlowAccents.append(CachedAccentNode(light: cachedLight, emitter: cachedEm))
            default:
                break
            }
        }
    }

    func applyMonitorWallpaper(token: String) {
        guard token != appliedWallpaperToken else { return }
        appliedWallpaperToken = token
        if let custom = MonitorWallpaperStore.currentImage() {
            monitorScreenMaterial?.diffuse.contents = NSColor(white: 0.03, alpha: 1)
            monitorScreenMaterial?.emission.contents = custom.image
            monitorScreenMaterial?.emission.intensity = 0.88
            monitorGlowLight?.color = custom.tint
        } else {
            monitorScreenMaterial?.diffuse.contents = NSColor(white: 0.02, alpha: 1)
            monitorScreenMaterial?.emission.contents = DeskTextures.asusScreen()
            monitorScreenMaterial?.emission.intensity = 0.86
            monitorGlowLight?.color = NSColor(srgbRed: 0.84, green: 0.90, blue: 0.98, alpha: 1)
        }
        materialRevision &+= 1
        bumpTransientRender(seconds: 0.25)
    }

    func setAmbience(deskLampOn: Bool, mood: DeskMood, scenario: DeskScenario = .swissAlps) {
        guard lastDeskLampOn != deskLampOn
            || lastDeskMood != mood
            || lastDeskScenario != scenario else { return }

        let scenarioChanged = lastDeskScenario != scenario
        lastDeskLampOn = deskLampOn
        lastDeskMood = mood
        lastDeskScenario = scenario

        let isRoom = (scenario == .room)
        if scenarioChanged {
            roomRootNode?.isHidden = !isRoom
            for child in scenarioRoot.childNodes {
                child.removeFromParentNode()
            }
            if !isRoom {
                let built: SCNNode
                if let cached = scenarioNodes[scenario] {
                    built = cached
                } else {
                    scenarioNodes.removeAll()
                    built = DeskScenarios.build(scenario)
                    scenarioNodes[scenario] = built
                }
                scenarioRoot.addChildNode(built)
            }
            topologyRevision &+= 1
        }

        let lampIntensityScale = CGFloat(deskLampBrightness)
        for item in deskLampLights {
            item.light.color = deskLampGlow
            item.light.intensity = deskLampOn ? item.baseIntensity * lampIntensityScale : 0
        }
        for item in deskLampEmitters {
            item.material.emission.contents = deskLampOn ? deskLampGlow : NSColor.black
            item.material.emission.intensity = deskLampOn ? item.baseIntensity * lampIntensityScale : 0
        }
        for wall in deskLampWallNodes {
            let show = isRoom && deskLampOn
            wall.node.isHidden = !show
            wall.light?.light.intensity = show ? (wall.light?.baseIntensity ?? 0) : 0
        }

        let underDeskScale = CGFloat(Self.underDeskGlowBase(for: mood))
        let monitorScale = CGFloat(Self.monitorGlowScale(for: mood))

        if isRoom {
            let keyScale: CGFloat
            let fillScale: CGFloat
            let roomScale: CGFloat
            let keyColor: NSColor
            let envIntensity: CGFloat
            let bgColor: NSColor
            let exposure: CGFloat
            switch mood {
            case .daylight:
                keyScale = 1.08
                fillScale = 0.92
                roomScale = 0.96
                keyColor = NSColor(srgbRed: 1.0, green: 0.986, blue: 0.962, alpha: 1)
                envIntensity = 0.76
                bgColor = NSColor(srgbRed: 0.73, green: 0.75, blue: 0.78, alpha: 1)
                exposure = 0.01
            case .midnight:
                keyScale = 0.16
                fillScale = 0.24
                roomScale = 0.18
                keyColor = NSColor(srgbRed: 0.72, green: 0.80, blue: 0.98, alpha: 1)
                envIntensity = 0.44
                bgColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.15, alpha: 1)
                exposure = -0.02
            }

            for accent in underDeskGlowAccents {
                accent.light.map { $0.light.intensity = $0.baseIntensity * underDeskScale }
                accent.emitter.map { $0.material.emission.intensity = $0.baseIntensity * underDeskScale }
            }
            for accent in monitorScreenGlowAccents {
                accent.light.map { $0.light.intensity = $0.baseIntensity * monitorScale }
                accent.emitter.map { $0.material.emission.intensity = $0.baseIntensity * monitorScale }
            }

            keyLightNode?.light?.intensity = keyLightBaseIntensity * keyScale
            keyLightNode?.light?.color = keyColor
            fillLightNode?.light?.intensity = fillLightBaseIntensity * fillScale
            roomLightNode?.light?.intensity = roomLightBaseIntensity * roomScale
            cameraNode.camera?.exposureOffset = exposure
            scene.fogEndDistance = 0
            DeskPhotoSky.clearCache()
            scene.lightingEnvironment.contents = hdrEnvironmentImage(mood: mood, deskLampOn: deskLampOn)
            scene.lightingEnvironment.intensity = envIntensity
            scene.background.contents = bgColor
            photoGround = .zero
        } else {
            hdrEnvironmentCache.removeAll()
            let profile = DeskScenarios.lightingProfile(scenario: scenario, mood: mood)
            let glowBoost = CGFloat(profile.underDeskGlowMultiplier)
            for accent in underDeskGlowAccents {
                accent.light.map { $0.light.intensity = $0.baseIntensity * underDeskScale * glowBoost }
                accent.emitter.map { $0.material.emission.intensity = $0.baseIntensity * underDeskScale * glowBoost }
            }
            for accent in monitorScreenGlowAccents {
                accent.light.map { $0.light.intensity = $0.baseIntensity * monitorScale }
                accent.emitter.map { $0.material.emission.intensity = $0.baseIntensity * monitorScale }
            }

            keyLightNode?.light?.intensity = keyLightBaseIntensity * CGFloat(profile.keyIntensityScale)
            keyLightNode?.light?.color = profile.keyColor
            fillLightNode?.light?.intensity = fillLightBaseIntensity * CGFloat(profile.fillIntensityScale)
            roomLightNode?.light?.intensity = roomLightBaseIntensity * CGFloat(profile.roomIntensityScale)
            cameraNode.camera?.exposureOffset = profile.exposureOffset
            scene.fogColor = profile.fogColor
            scene.fogStartDistance = profile.fogStart
            scene.fogEndDistance = profile.fogEnd
            // A photographed sky replaces the generated one and the studio fill rig: the photo is the light.
            // The generated cubemap must not be assigned first; SceneKit keeps it even when a colour follows.
            let photo = DeskPhotoSky.photo(scenario: scenario, mood: mood)
            if photo == nil {
                scene.lightingEnvironment.contents = DeskScenarios.hdrEnvironmentImage(mood: mood)
                scene.lightingEnvironment.intensity = profile.envIntensity
                scene.background.contents = NSColor.black
            }
            photoGround = photo.map { SIMD4<Float>(DeskScenarios.photoCaptureOrigin, $0.whiteLevel) } ?? .zero
            if let photo {
                DeskScenarios.updatePhotoGroundAlbedo(in: scenarioRoot, albedo: photo.groundAlbedo)
                scene.lightingEnvironment.contents = photo.environment
                scene.lightingEnvironment.intensity = 1.0
                scene.background.contents = NSColor.black   // no cubemap: the camera looks at the photo itself
                fillLightNode?.light?.intensity = 0
                roomLightNode?.light?.intensity = 0
                if let sun = photo.sunDirection {
                    let peak = max(photo.sunIrradiance.x, max(photo.sunIrradiance.y, photo.sunIrradiance.z), 1e-4)
                    let tint = photo.sunIrradiance / peak
                    func encoded(_ v: Float) -> CGFloat { CGFloat(v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055) }
                    keyLightNode?.simdPosition = sun * 57
                    keyLightNode?.light?.color = NSColor(srgbRed: encoded(tint.x), green: encoded(tint.y), blue: encoded(tint.z), alpha: 1)
                    // The ray tracer multiplies the key light by 1.35 * 1.45 outdoors; divide it back out.
                    keyLightNode?.light?.intensity = keyLightBaseIntensity * CGFloat(peak / (1.35 * 1.45))
                } else {
                    keyLightNode?.light?.intensity = 0
                }
            } else {
                keyLightNode?.position = SCNVector3(-8, 52, 22)
            }
        }

        materialRevision &+= 1
        bumpTransientRender(seconds: 0.35)
    }

    private func isKnob(_ index: Int) -> Bool {
        index == Layout.knobPress.index || index == Layout.knobCCW.index || index == Layout.knobCW.index
    }

    private func hasAnyKnobMarked(_ set: Set<Int>) -> Bool {
        set.contains(Layout.knobPress.index) || set.contains(Layout.knobCCW.index) || set.contains(Layout.knobCW.index)
    }

    private func updateKnobEmission() {
        let isKnobSelected = selected.map { isKnob($0) } ?? false
        if isKnobSelected {
            knobMaterial.emission.contents = NSColor.controlAccentColor.withAlphaComponent(1).blended(withFraction: 0.45, of: .black)
        } else if heatmapActive {
            let w = max(heatmapWeights[Layout.knobPress.index] ?? 0,
                        max(heatmapWeights[Layout.knobCCW.index] ?? 0, heatmapWeights[Layout.knobCW.index] ?? 0))
            knobMaterial.emission.contents = KeyboardStore.heatmapColor(intensity: w)
        } else {
            knobMaterial.emission.contents = hasAnyKnobMarked(marked) ? NSColor(srgbRed: 0.0, green: 0.32, blue: 0.14, alpha: 1) : NSColor.black
        }
    }

    func setPressed(_ next: Set<Int>) {
        lock.lock()
        guard next != pressed else {
            lock.unlock()
            return
        }
        let newlyPressed = next.subtracting(pressed)
        let changed = next.symmetricDifference(pressed)
        pressed = next
        let reactive = isReactiveLightingLocked
        if reactive {
            let now = currentSceneTime()
            for index in newlyPressed {
                addReactiveEventLocked(key: index, at: now)
            }
        }
        if lighting.brightness > 0 && lighting.effect != 0 {
            staticBacklightClean = false
        }
        lock.unlock()
        for index in changed { settle(index) }
        bumpTransientRender(seconds: (reactive && !newlyPressed.isEmpty) ? 2.2 : 0.18)
    }

    func triggerReactive(key: Int) {
        let now = currentSceneTime()
        lock.lock()
        addReactiveEventLocked(key: key, at: now)
        staticBacklightClean = false
        lock.unlock()
        bumpTransientRender(seconds: 2.2)
    }

    func addReactiveEventLocked(key: Int, at now: Float) {
        let x: Float
        let z: Float
        if let kx = keyX[key], let kz = keyZ[key] {
            x = kx
            z = kz
        } else if isKnob(key) {
            x = CaseMesh.knobCenterX
            z = CaseMesh.knobCenterZ
        } else {
            return
        }
        let hue = Float.random(in: 0...1)
        ripples.append(ReactiveRipple(x: x, z: z, time: now, hue: hue))
        lasers.append(ReactiveLaser(z: z, originX: x, time: now, hue: hue))
        fades[key] = ReactiveFade(time: now, hue: hue)
        if ripples.count > 12 { ripples.removeFirst(ripples.count - 12) }
        if lasers.count > 12 { lasers.removeFirst(lasers.count - 12) }
    }

    func pressKey(_ index: Int) {
        setPressed(pressed.union([index]))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.setPressed(self.pressed.subtracting([index]))
            self.onRenderIdleChanged?(true)
        }
    }

    private func settle(_ index: Int) {
        guard capNodes[index] != nil, let rest = restY[index] else { return }
        var y = rest
        if pressed.contains(index) { y -= 0.17 } else if selected == index { y += 0.07 }
        lock.lock()
        keyTargetY[index] = y
        let wake = markRenderActiveIfNeededLocked()
        lock.unlock()
        if let wake { DispatchQueue.main.async { wake(true) } }
    }

    // MARK: Mouse

    /// Lights the 3D G7's buttons while they are held (0 left, 1 right, 2 wheel, 3 back, 4 forward)
    /// and shows the DPI stage colour on its LED (nil is the stock cyan).
    func setMouseVisual(pressed: Set<Int>, led: NSColor?) {
        if hasInitializedMouseVisual, pressed == lastMousePressed, led == lastMouseLED {
            return
        }
        hasInitializedMouseVisual = true
        lastMousePressed = pressed
        lastMouseLED = led

        let accent = NSColor.controlAccentColor
        mouseParts[TechProps.MouseParts.left]?.opacity = pressed.contains(0) ? 0.55 : 0
        mouseParts[TechProps.MouseParts.right]?.opacity = pressed.contains(1) ? 0.55 : 0
        for (name, button) in [(TechProps.MouseParts.back, 3), (TechProps.MouseParts.forward, 4)] {
            mouseParts[name]?.geometry?.firstMaterial?.emission.contents = pressed.contains(button) ? accent : NSColor.black
        }
        if let wheel = mouseParts[TechProps.MouseParts.wheel] {
            if mouseWheelRestY == nil {
                mouseWheelRestY = wheel.position.y
                wheelCurrentY = Float(wheel.position.y)
                wheelHasRestY = true
            }
            let targetY = Float(mouseWheelRestY ?? 0) - (pressed.contains(2) ? 0.08 : 0)
            lock.lock()
            wheelTargetY = targetY
            lock.unlock()
            for child in wheel.childNodes where child.geometry is SCNCylinder {
                child.geometry?.firstMaterial?.emission.contents = pressed.contains(2) ? accent : NSColor.black
            }
        }
        if let ledNode = mouseParts[TechProps.MouseParts.dpiLED] {
            // The real G7's light is cyan unless a DPI stage colour is in use.
            ledNode.geometry?.firstMaterial?.diffuse.contents = led ?? NSColor(srgbRed: 0.30, green: 0.85, blue: 1.0, alpha: 1)
        }
        materialRevision &+= 1
        transformRevision &+= 1
        bumpTransientRender(seconds: 0.2)
    }

    func spinMouseWheel(up: Bool) {
        lock.lock()
        wheelTargetX += (up ? -0.45 : 0.45)
        let wake = markRenderActiveIfNeededLocked()
        lock.unlock()
        if let wake { DispatchQueue.main.async { wake(true) } }
        bumpTransientRender(seconds: 0.2)
    }

    func turnKnob(clockwise: Bool) {
        lock.lock()
        knobTargetYaw += (clockwise ? -0.5 : 0.5)
        let wake = markRenderActiveIfNeededLocked()
        lock.unlock()
        if let wake { DispatchQueue.main.async { wake(true) } }
        bumpTransientRender(seconds: 0.2)
    }

    func flushAnimations() {
        lock.lock()
        let keyTargets = keyTargetY
        keyTargetY.removeAll()
        knobCurrentYaw = knobTargetYaw
        wheelCurrentX = wheelTargetX
        if wheelHasRestY { wheelCurrentY = wheelTargetY }
        lock.unlock()

        for (idx, y) in keyTargets {
            capNodes[idx]?.position.y = CGFloat(y)
        }
        knob.simdEulerAngles.y = knobCurrentYaw
        if let wheel = mouseParts[TechProps.MouseParts.wheel] {
            wheel.simdEulerAngles.x = wheelCurrentX
            if wheelHasRestY { wheel.position.y = CGFloat(wheelCurrentY) }
        }
        transformRevision &+= 1
    }

    func setLighting(_ state: LightingState) {
        lock.lock()
        guard lighting != state else {
            lock.unlock()
            return
        }
        let wasReactive = (lighting.effect == 7 || lighting.effect == 8 || lighting.effect == 9 || lighting.effect == 17)
        let isReactive = (state.effect == 7 || state.effect == 8 || state.effect == 9 || state.effect == 17)
        lighting = state
        staticBacklightClean = false
        if isReactive && !wasReactive && !state.musicSync && state.brightness > 0 {
            pendingReactiveDemo = true
        }
        let wake = markRenderActiveIfNeededLocked()
        lock.unlock()
        if let wake { DispatchQueue.main.async { wake(true) } }
        bumpTransientRender(seconds: 0.15)
    }

    func setAudioSnapshot(_ snapshot: AudioSnapshot) {
        lock.lock()
        audioSnapshot = snapshot
        lock.unlock()
    }

    /// Matrix index of the key under a hit-test result, if any.
    static func keyIndex(of node: SCNNode?) -> Int? {
        guard let name = node?.name, name.hasPrefix("k") else { return nil }
        return Int(name.dropFirst())
    }

    var isMouse: (SCNNode) -> Bool {
        { [weak self] node in
            guard let mouseRoot = self?.mouseRootNode else { return false }
            var n: SCNNode? = node
            while let current = n { if current === mouseRoot { return true }; n = current.parent }
            return false
        }
    }

    /// Clickable desk props: the monitor cycles its wallpaper, the desk lamp toggles its light.
    enum DeskProp: String {
        case monitor = "prop.monitor"
        case deskLamp = "prop.deskLamp"
    }

    /// The desk prop a hit-test node belongs to, if any.
    static func deskProp(of node: SCNNode?) -> DeskProp? {
        var n = node
        while let current = n {
            if let name = current.name, let prop = DeskProp(rawValue: name) { return prop }
            n = current.parent
        }
        return nil
    }

    var isKeyboard: (SCNNode) -> Bool {
        { [keyboard] node in
            var n: SCNNode? = node
            while let current = n { if current === keyboard { return true }; n = current.parent }
            return false
        }
    }

    var isScenarioNode: (SCNNode) -> Bool {
        { [scenarioRoot] node in
            var n: SCNNode? = node
            while let current = n { if current === scenarioRoot { return true }; n = current.parent }
            return false
        }
    }
}
