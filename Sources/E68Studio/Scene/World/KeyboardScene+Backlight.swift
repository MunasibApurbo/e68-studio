import SceneKit
import AppKit
import simd

extension KeyboardScene {
    // MARK: Per-frame work

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        stepFrame(atTime: time)
    }

    func stepFrame(atTime time: TimeInterval) {
        lock.lock()
        let dt = Float(min(max(time - lastTime, 0), 0.1))
        lastTime = time

        var shouldApplyPose = false
        if !isCameraSettled {
            let converged = abs(pose.distance - goal.distance) < 1e-4
                && abs(pose.pitch - goal.pitch) < 1e-4
                && abs(pose.yaw - goal.yaw) < 1e-4
                && abs(pose.fov - goal.fov) < 1e-4
                && simd_length_squared(pose.target - goal.target) < 1e-8
            if converged {
                pose = goal
                isCameraSettled = true
            } else {
                pose = pose.mixed(toward: goal, 1 - exp(-dt * 4.2))
            }
            shouldApplyPose = true
        }

        // Step mechanical springs (keycaps, rotary knob, mouse scroll wheel) cleanly on CPU
        // so both SceneKit and our Metal path tracer stay smoothly animated.
        let blendFast = dt > 0 ? (1 - exp(-dt * 28.0)) : 1.0
        var keyUpdates = [(Int, Float)]()
        var removedKeys = [Int]()
        for (idx, target) in keyTargetY {
            let cur = Float(capNodes[idx]?.position.y ?? CGFloat(target))
            if abs(cur - target) < 5e-4 || dt <= 0 {
                keyUpdates.append((idx, target))
                removedKeys.append(idx)
            } else {
                keyUpdates.append((idx, cur + (target - cur) * blendFast))
            }
        }
        for idx in removedKeys { keyTargetY.removeValue(forKey: idx) }

        var newKnobYaw: Float?
        if abs(knobCurrentYaw - knobTargetYaw) > 1e-4 {
            knobCurrentYaw = abs(knobTargetYaw - knobCurrentYaw) < 5e-4 || dt <= 0
                ? knobTargetYaw
                : knobCurrentYaw + (knobTargetYaw - knobCurrentYaw) * blendFast
            newKnobYaw = knobCurrentYaw
        }
        var newWheelX: Float?
        if abs(wheelCurrentX - wheelTargetX) > 1e-4 {
            wheelCurrentX = abs(wheelTargetX - wheelCurrentX) < 5e-4 || dt <= 0
                ? wheelTargetX
                : wheelCurrentX + (wheelTargetX - wheelCurrentX) * blendFast
            newWheelX = wheelCurrentX
        }
        var newWheelY: Float?
        if wheelHasRestY && abs(wheelCurrentY - wheelTargetY) > 1e-4 {
            wheelCurrentY = abs(wheelTargetY - wheelCurrentY) < 5e-4 || dt <= 0
                ? wheelTargetY
                : wheelCurrentY + (wheelTargetY - wheelCurrentY) * blendFast
            newWheelY = wheelCurrentY
        }

        let state = lighting
        let tNow = currentSceneTime(time)
        var activeRipples: [ReactiveRipple] = []
        var activeLasers: [ReactiveLaser] = []
        var activeFades: [Int: ReactiveFade] = [:]
        if !state.musicSync {
            if isReactiveLightingLocked {
                if !ripples.isEmpty { ripples.removeAll { tNow - $0.time > 3.5 || $0.time > tNow + 0.1 } }
                if !lasers.isEmpty { lasers.removeAll { tNow - $0.time > 2.5 || $0.time > tNow + 0.1 } }
                if !fades.isEmpty { fades = fades.filter { tNow - $0.value.time < 3.0 && $0.value.time <= tNow + 0.1 } }
                if pendingReactiveDemo {
                    pendingReactiveDemo = false
                    let demoKeys = [2 * 16 + 5, 2 * 16 + 7, 3 * 16 + 6, 2 * 16 + 4, 1 * 16 + 6]
                    let demoKey = demoKeys[Int(max(0, tNow) * 0.45) % demoKeys.count]
                    addReactiveEventLocked(key: demoKey, at: tNow)
                }
                activeRipples = ripples
                activeLasers = lasers
                activeFades = fades
            } else {
                pendingReactiveDemo = false
                if !ripples.isEmpty { ripples.removeAll() }
                if !lasers.isEmpty { lasers.removeAll() }
                if !fades.isEmpty { fades.removeAll() }
            }
        }
        let isReactiveRest = (state.effect == 7 || state.effect == 8 || state.effect == 9 || state.effect == 17)
        let isStaticEffect = !state.musicSync && (state.brightness == 0 || state.effect == 0 || state.effect == 6 || isReactiveRest)
            && activeRipples.isEmpty && activeLasers.isEmpty && activeFades.isEmpty && pressed.isEmpty
        let needsBacklightUpdate = !isStaticEffect || !staticBacklightClean
        let monitor = state.musicSync ? audioMonitor : nil
        let pressedSnapshot = pressed
        lock.unlock()

        if shouldApplyPose {
            applyPose()
        }
        if !keyUpdates.isEmpty || newKnobYaw != nil || newWheelX != nil || newWheelY != nil {
            for (idx, y) in keyUpdates { capNodes[idx]?.position.y = CGFloat(y) }
            if let y = newKnobYaw { knob.simdEulerAngles.y = y }
            if newWheelX != nil || newWheelY != nil, let wheel = wheelNodeCached {
                if let x = newWheelX { wheel.simdEulerAngles.x = x }
                if let y = newWheelY { wheel.position.y = CGFloat(y) }
            }
            transformRevision &+= 1
        }

        if needsBacklightUpdate {
            let audio: AudioSnapshot
            if let monitor {
                // Hold the preview back by the output device's latency (minus one display frame) so the keys
                // light when the sound is heard, not when it is captured.
                let audioDelay = MusicLightEngine.delay(
                    outputLatency: monitor.outputLatency(),
                    userOffsetMs: state.musicSyncOffsetMs,
                    consumerLatency: 0.025
                )
                audio = monitor.snapshot(delay: audioDelay)
            } else {
                audio = audioSnapshot
            }
            updateBacklight(state, time: tNow, audio: audio, pressed: pressedSnapshot,
                            ripples: activeRipples, lasers: activeLasers, fades: activeFades)
            if isStaticEffect {
                lock.lock()
                if lighting == state { staticBacklightClean = true }
                lock.unlock()
            }
        }

        lock.lock()
        let cb = consumeIdleTransitionLocked(now: CACurrentMediaTime())
        lock.unlock()
        if let cb {
            DispatchQueue.main.async { cb(false) }
        }
    }

    /// Real-time visualization of firmware lighting effects plus live music-reactive audio visualizer.
    private func updateBacklight(
        _ s: LightingState,
        time: Float,
        audio: AudioSnapshot,
        pressed pressedSnapshot: Set<Int>,
        ripples activeRipples: [ReactiveRipple],
        lasers activeLasers: [ReactiveLaser],
        fades activeFades: [Int: ReactiveFade]
    ) {
        let level = (s.effect == 0 && !s.musicSync) ? 0 : Float(s.brightness) / Float(LightingCatalog.maxBrightness)
        let hueNorm = Float(s.hue) / 255
        let satNorm = Float(s.saturation) / 255
        let base = SIMD3<Float>(Self.rgb(hue: hueNorm, saturation: satNorm))
        var slotRGBs = [SIMD3<Float>](repeating: .zero, count: glowSlots.count)
        var anySlotChanged = false
        var knobColor = SIMD3<Float>.zero

        if s.musicSync {
            // Same engine as the HID pump: the board's single colour + level is the truth, and the
            // per-key pattern below only shades around it, so screen and keyboard pulse together.
            let f = musicEngine.step(audio, settings: .init(s), now: Date().timeIntervalSinceReferenceDate)
            let primary = f.rgb
            let accent = f.accentRGB
            let sens = Float(s.musicSensitivity)
            let depth: Float = f.isPlaying ? 0.92 : 0.0
            // Pulse ring: launched by each beat, expands outward as the flash decays.
            let ringRadius = (1 - f.flash) * 9.0
            let meterFill = min(16, f.energy * 16.5)

            for i in glowSlots.indices {
                let slot = glowSlots[i]
                let x = slot.x, z = slot.z
                let col = slot.col
                let vLevel = slot.vLevel
                var pattern: Float = 1
                var accentMix: Float = 0

                switch s.musicMode {
                case .equalizer:
                    let height = min(1, audio.bands[col] * sens) * 4.9
                    let diff = height - vLevel
                    pattern = diff >= 1 ? 1 : (diff > 0 ? 0.15 + 0.85 * diff : 0.02)
                    accentMix = diff > 0 ? min(1, (vLevel / 4) * 0.55 + (Float(col) / 15) * 0.45) : 0

                case .pulse:
                    let d = sqrt(x * x + z * z)
                    let ring = expf(-(d - ringRadius) * (d - ringRadius) * 0.45) * f.flash
                    let core = max(0, 1 - d / 8) * f.energy
                    pattern = min(1, 0.12 + ring * 1.25 + core * 0.65)
                    accentMix = min(1, ring * 0.9)

                case .wave:
                    let n = audio.waveform.count
                    let w0 = n > 0 ? audio.waveform[min(n - 1, col * 2)] : 0
                    let w1 = n > 1 ? audio.waveform[min(n - 1, col * 2 + 1)] : w0
                    let center = 2.0 + 0.5 * (w0 + w1) * 2.25 * min(1, f.energy * 1.4 + 0.2)
                    let dist = abs(vLevel - center)
                    let spine = expf(-dist * dist * 1.15)
                    pattern = 0.06 + 0.94 * spine
                    accentMix = spine * max(0.35, f.flash * 0.85)

                case .vuMeter:
                    let c = Float(col)
                    pattern = c < meterFill - 1 ? 1 : (c < meterFill ? 0.15 + 0.85 * (meterFill - c) : 0.02)
                    accentMix = c >= 12 ? 0.85 : (c >= 9 ? 0.45 : 0)
                }

                var c = primary + (accent - primary) * accentMix
                if s.musicColorMode == .fire && s.musicMode == .equalizer {
                    c = SIMD3(Self.rgb(hue: min(0.16, f.hue + vLevel * 0.028), saturation: f.saturation))
                } else if s.musicColorMode == .dynamic && s.musicMode == .equalizer && !audio.hasCoverColor {
                    let eqHue = (f.hue + Float(col) * 0.032 + vLevel * 0.04).truncatingRemainder(dividingBy: 1.0)
                    c = SIMD3(Self.rgb(hue: eqHue < 0 ? eqHue + 1 : eqHue, saturation: 0.95))
                }
                let gain = f.level * ((1 - depth) + depth * pattern * 1.45)
                let out = c * level * gain * 1.45
                if slot.index == 1 * 16 + 13 { knobColor = out }
                if updateSlotColor(at: i, rgb: out, into: &slotRGBs[i]) { anySlotChanged = true }
            }
        } else {
            let speedFactor = max(0.25, Float(s.speed) * 0.5)
            let t = time * speedFactor

            for i in glowSlots.indices {
                let slot = glowSlots[i]
                let index = slot.index
                let x = slot.x, z = slot.z
                let isDown = pressedSnapshot.contains(index)
                var c = base
                var gain: Float = 1.0

                switch s.effect {
                case 0: // Off
                    gain = 0.0

                case 6: // Static
                    c = base
                    gain = isDown ? 1.30 : 1.0

                case 5: // Breathe
                    c = base
                    let phase = sin(t * 1.8)
                    gain = 0.08 + 0.92 * pow(0.5 + 0.5 * phase, 1.6)
                    if isDown { gain = max(gain, 1.25) }

                case 1: // Wave (Smooth rainbow wave left-to-right)
                    let hue = (x / 14.0 - t * 0.7).truncatingRemainder(dividingBy: 1.0) + 1.0
                    c = SIMD3(Self.rgb(hue: hue, saturation: 1.0))
                    gain = isDown ? 1.28 : 1.05

                case 2: // Colour Cloud (Organic 2D shifting cloud colors)
                    let n1 = sin(x * 0.35 + t * 0.6)
                    let n2 = cos(z * 0.75 - t * 0.45)
                    let hue = (n1 * 0.3 + n2 * 0.3 + t * 0.15 + 2.0)
                    c = SIMD3(Self.rgb(hue: hue, saturation: 0.96))
                    gain = isDown ? 1.28 : 1.05

                case 3: // Vortex (Swirling rainbow around center)
                    let angle = atan2(z, x)
                    let dist = sqrt(x * x + z * z)
                    let hue = (angle / (2 * .pi) - dist * 0.06 + t * 0.8 + 2.0)
                    c = SIMD3(Self.rgb(hue: hue, saturation: 1.0))
                    gain = isDown ? 1.28 : 1.05

                case 4: // Colour Mix (Diagonal blended rainbow waves)
                    let diag = (x * 0.8 + z * 1.4)
                    let hue = (diag / 14.0 - t * 0.5 + 2.0)
                    c = SIMD3(Self.rgb(hue: hue, saturation: 1.0))
                    gain = isDown ? 1.28 : 1.05

                case 13: // Wave Bar (Vertical gradient bars sweeping horizontally)
                    let bar = sin(x * 0.8 - t * 2.2)
                    gain = 0.18 + 0.90 * pow(max(0, bar), 2.0)
                    let hue = (x / 16.0 + t * 0.25 + hueNorm + 2.0)
                    c = SIMD3(Self.rgb(hue: hue, saturation: max(0.75, satNorm)))

                case 12: // Traverse (Chaser travelling along keys)
                    let pathPos = Float(index % 16) + Float(index / 16) * 16.0
                    let chaser = (t * 22.0).truncatingRemainder(dividingBy: 80.0)
                    let chaserPos = chaser < 0 ? chaser + 80.0 : chaser
                    let dist = min(abs(pathPos - chaserPos), 80.0 - abs(pathPos - chaserPos))
                    gain = max(0.14, exp(-dist * 0.32))
                    c = SIMD3(Self.rgb(hue: pathPos / 80.0 + t * 0.2 + hueNorm + 2.0, saturation: max(0.75, satNorm)))

                case 16: // Scan (Back-and-forth scanner bar)
                    let scanX = sin(t * 1.8) * 7.2
                    let dist = abs(x - scanX)
                    gain = max(0.10, exp(-dist * dist * 0.55))
                    c = base

                case 10: // Starry (Individual twinkling stars)
                    let p = Float((index * 197) % 314) / 50.0
                    let twinkle = sin(t * 2.8 + p)
                    gain = max(0.10, pow(max(0, twinkle), 3.6))
                    c = SIMD3(Self.rgb(hue: Float((index * 47) % 100) / 100.0 + t * 0.05 + hueNorm + 2.0, saturation: max(0.75, satNorm)))

                case 14: // Meteor (Diagonal falling streaks)
                    let pos = ((x * 0.7 + z * 1.5) - t * 7.0).truncatingRemainder(dividingBy: 10.0)
                    let streak = (pos < 0 ? pos + 10.0 : pos)
                    gain = max(0.10, exp(-streak * 0.75))
                    c = SIMD3(Self.rgb(hue: x * 0.04 - t * 0.15 + hueNorm + 2.0, saturation: max(0.75, satNorm)))

                case 15: // Rain (Falling raindrops along columns)
                    let colOffset = Float((index * 73) % 16) * 0.8
                    let drop = ((z + 2.5) - (t * 4.5 + colOffset).truncatingRemainder(dividingBy: 6.0))
                    let trail = (drop < 0 ? drop + 6.0 : drop)
                    gain = max(0.10, exp(-trail * 1.5))
                    c = SIMD3(Self.rgb(hue: Float(index % 16) / 16.0 + hueNorm + 0.58, saturation: max(0.75, satNorm)))

                case 11: // Flowers Open (Blooming flower petals expanding)
                    let r = sqrt(x * x + z * z)
                    let theta = atan2(z, x)
                    let petals = sin(theta * 5.0 + t * 1.2)
                    let wave = sin(r * 1.4 - t * 2.4 + petals * 0.7)
                    gain = 0.20 + 0.88 * (0.5 + 0.5 * wave)
                    c = SIMD3(Self.rgb(hue: r * 0.08 - t * 0.25 + hueNorm + 2.0, saturation: max(0.75, satNorm)))

                case 18: // Centre Spread (Concentric rings spreading from center)
                    let r = sqrt(x * x + z * z)
                    let ring = sin(r * 1.3 - t * 3.0)
                    gain = 0.16 + 0.90 * pow(max(0, ring), 2.0)
                    c = SIMD3(Self.rgb(hue: r * 0.08 - t * 0.2 + hueNorm + 2.0, saturation: max(0.75, satNorm)))

                case 8: // Stone (Ripple expanding outwards from pressed or demo keys)
                    var rippleSum: Float = 0
                    for rip in activeRipples {
                        let elapsed = max(0, time - rip.time)
                        let radius = elapsed * speedFactor * 10.0
                        let d = sqrt((x - rip.x) * (x - rip.x) + (z - rip.z) * (z - rip.z))
                        let ringDist = abs(d - radius)
                        let ring = exp(-ringDist * ringDist * 1.5) * exp(-elapsed * 0.85)
                        rippleSum += ring
                    }
                    gain = max(0.12, min(1.3, rippleSum + (isDown ? 1.15 : 0.0)))
                    c = base

                case 9: // Laser (Horizontal laser beam shooting across row)
                    var laserSum: Float = 0
                    for las in activeLasers {
                        let elapsed = max(0, time - las.time)
                        let rowDist = abs(z - las.z)
                        if rowDist < 0.65 {
                            let beamFront = elapsed * speedFactor * 18.0
                            let distFromOrigin = abs(x - las.originX)
                            let onBeam = abs(distFromOrigin - beamFront)
                            let laserIntensity = exp(-onBeam * 0.7) * exp(-elapsed * 1.2)
                            laserSum += laserIntensity
                        }
                    }
                    gain = max(0.12, min(1.3, laserSum + (isDown ? 1.15 : 0.0)))
                    c = base

                case 7: // Slow Fade (Key lights up on press, slowly fades out)
                    var fadeVal: Float = 0
                    if let fade = activeFades[index] {
                        let elapsed = max(0, time - fade.time)
                        fadeVal = max(0, 1.0 - elapsed / 1.6)
                    }
                    gain = max(0.10, isDown ? 1.2 : fadeVal)
                    c = base

                case 17: // Trigger Colour (Key lights up with a vibrant cycling color on press)
                    var fadeVal: Float = 0
                    var triggerHue = hueNorm
                    if let fade = activeFades[index] {
                        let elapsed = max(0, time - fade.time)
                        fadeVal = max(0, 1.0 - elapsed / 1.6)
                        triggerHue = fade.hue
                    }
                    gain = max(0.14, isDown ? 1.2 : fadeVal)
                    c = (fadeVal > 0.05 || isDown) ? SIMD3(Self.rgb(hue: triggerHue, saturation: 1.0)) : base

                default:
                    c = base
                    gain = 1.0
                }

                if s.reactiveTypingRipple && !activeRipples.isEmpty {
                    var rippleBoost: Float = 0
                    var rippleRGB = base
                    for rip in activeRipples {
                        let elapsed = max(0, time - rip.time)
                        let radius = elapsed * speedFactor * 11.5
                        let d = sqrt((x - rip.x) * (x - rip.x) + (z - rip.z) * (z - rip.z))
                        let ringDist = abs(d - radius)
                        let ring = exp(-ringDist * ringDist * 1.7) * exp(-elapsed * 1.0)
                        if ring > rippleBoost {
                            rippleBoost = ring
                            rippleRGB = SIMD3(Self.rgb(hue: rip.hue, saturation: 0.95))
                        }
                    }
                    if rippleBoost > 0.02 {
                        c = c * (1 - min(1, rippleBoost)) + rippleRGB * min(1, rippleBoost * 1.25)
                        gain = max(gain, min(1.38, gain + rippleBoost * 0.9))
                    }
                }

                let out = c * level * gain * 1.30
                if index == 1 * 16 + 13 { knobColor = out }
                if updateSlotColor(at: i, rgb: out, into: &slotRGBs[i]) { anySlotChanged = true }
            }
        }

        if anySlotChanged {
            flushPlateGlowTexture(slotRGBs: slotRGBs)
        }

        // Update rotary knob halo only when quantized RGB changes.
        let kr = min(max(knobColor.x, 0), 1), kg = min(max(knobColor.y, 0), 1), kb = min(max(knobColor.z, 0), 1)
        let kqr = Int16((kr * 255).rounded()), kqg = Int16((kg * 255).rounded()), kqb = Int16((kb * 255).rounded())
        let knobChanged = kqr != lastKnobR || kqg != lastKnobG || kqb != lastKnobB
        if knobChanged {
            lastKnobR = kqr
            lastKnobG = kqg
            lastKnobB = kqb
            knobGlowMaterial.multiply.contents = (kqr == 0 && kqg == 0 && kqb == 0)
                ? NSColor.black
                : NSColor(srgbRed: CGFloat(kr), green: CGFloat(kg), blue: CGFloat(kb), alpha: 1)
        }
        if anySlotChanged || knobChanged {
            backlightRevision &+= 1
        }
    }

    private static let plateGlowColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private func updateSlotColor(at i: Int, rgb out: SIMD3<Float>, into clampedOut: inout SIMD3<Float>) -> Bool {
        let cr = min(max(out.x, 0), 1), cg = min(max(out.y, 0), 1), cb = min(max(out.z, 0), 1)
        clampedOut = SIMD3<Float>(cr, cg, cb)
        let qr = Int16((cr * 255).rounded()), qg = Int16((cg * 255).rounded()), qb = Int16((cb * 255).rounded())
        let slot = glowSlots[i]
        guard qr != slot.lastR || qg != slot.lastG || qb != slot.lastB else { return false }
        glowSlots[i].lastR = qr
        glowSlots[i].lastG = qg
        glowSlots[i].lastB = qb

        if qr == 0 && qg == 0 && qb == 0 {
            if !slot.lastSideZero {
                glowSlots[i].lastSideZero = true
                slot.sideMaterial.emission.contents = NSColor.black
            }
        } else {
            glowSlots[i].lastSideZero = false
            // Inverse-height shader fades skirt scatter smoothly above the bottom lip, so strong base scatter never washes out caps.
            let sideGain: Float = slot.isDark ? 0.20 : 0.72
            slot.sideMaterial.emission.contents = NSColor(
                srgbRed: CGFloat(cr * sideGain),
                green: CGFloat(cg * sideGain),
                blue: CGFloat(cb * sideGain),
                alpha: 1
            )
        }
        return true
    }

    private func flushPlateGlowTexture(slotRGBs: [SIMD3<Float>]) {
        let allBlack = !glowSlots.contains { $0.lastR > 0 || $0.lastG > 0 || $0.lastB > 0 }
        if allBlack {
            if !plateGlowAllBlack {
                plateGlowAllBlack = true
                if !usesHardwareRayTracer {
                    plateGlowMaterial.emission.contents = NSColor.black
                }
            }
            return
        }

        plateGlowAllBlack = false
        for p in plateGlowAccum.indices {
            plateGlowAccum[p] = .zero
        }
        for i in glowSlots.indices {
            let rgb = slotRGBs[i]
            if rgb.x <= 0.0005 && rgb.y <= 0.0005 && rgb.z <= 0.0005 { continue }
            for pw in glowSlots[i].pixelMask {
                plateGlowAccum[pw.offset] += rgb * pw.weight
            }
        }
        for p in plateGlowAccum.indices {
            let c = plateGlowAccum[p]
            let b = p * 4
            plateGlowBytes[b]     = UInt8(min(max(c.x, 0), 1) * 255 + 0.5)
            plateGlowBytes[b + 1] = UInt8(min(max(c.y, 0), 1) * 255 + 0.5)
            plateGlowBytes[b + 2] = UInt8(min(max(c.z, 0), 1) * 255 + 0.5)
            plateGlowBytes[b + 3] = 255
        }
        // The Metal path tracer reads plateGlowBytes directly, avoiding per-frame CGImage allocations.
        guard !usesHardwareRayTracer else { return }
        let data = Data(plateGlowBytes)
        if let provider = CGDataProvider(data: data as CFData),
           let img = CGImage(
               width: Self.plateGlowWidth,
               height: Self.plateGlowHeight,
               bitsPerComponent: 8,
               bitsPerPixel: 32,
               bytesPerRow: Self.plateGlowWidth * 4,
               space: Self.plateGlowColorSpace,
               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
               provider: provider,
               decode: nil,
               shouldInterpolate: true,
               intent: .defaultIntent
           ) {
            plateGlowMaterial.emission.contents = img
        }
    }

    private static func rgb(hue: Float, saturation: Float) -> SIMD3<Float> {
        let h = (hue - hue.rounded(.down)) * 6
        let f = h - h.rounded(.down)
        let p = 1 - saturation, q = 1 - saturation * f, t = 1 - saturation * (1 - f)
        switch Int(h) % 6 {
        case 0: return SIMD3(1, t, p)
        case 1: return SIMD3(q, 1, p)
        case 2: return SIMD3(p, 1, t)
        case 3: return SIMD3(p, q, 1)
        case 4: return SIMD3(t, p, 1)
        default: return SIMD3(1, p, q)
        }
    }
}
