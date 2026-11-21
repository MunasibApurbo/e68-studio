import SceneKit
import AppKit
import simd

/// Geometry for the MCHOSE G7 (129.4 × 74.6 × 41.1 mm, right-handed), modelled from the product
/// photos: a low split-prong nose with diagonal front paddle bevels, the hump at 55 % of the
/// length, a straight right flank, and on the left a broad flared thumb wing below a concave thumb
/// scoop. The two click paddles are separate molded pieces flanking a parallel center wheel
/// channel, with real seam grooves showing a dark inner shell.
///
/// Coordinates: x right, y up, z toward the tail. The shell is a ring swept along the length:
/// `t` runs nose (0) to tail (1) and `a` round the ring (0 right flank, π/2 top, π left, 3π/2 base).
enum G7Model {
    static let length: Float = 6.78

    // MARK: Shape

    static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let u = min(max((x - e0) / (e1 - e0), 0), 1)
        return u * u * (3 - 2 * u)
    }

    private static func softMax(_ a: Float, _ b: Float, k: Float) -> Float {
        let d = a - b
        return 0.5 * (a + b + sqrt(d * d + k * k))
    }

    /// Crest height along the length: 0.66 at the paddle tips, 2.16 at the 55 % hump, down to 0.42 at the tail.
    static func height(_ t: Float) -> Float {
        let peak: Float = 0.55
        if t < peak { return 0.66 + 1.50 * pow(sin(t / peak * .pi / 2), 0.80) }
        return 0.42 + 1.74 * pow(cos((t - peak) / (1 - peak) * .pi / 2), 0.80)
    }

    private static func lipY(_ t: Float) -> Float {
        0.07 + 0.54 * (1 - smooth(0, 0.17, t)) + 0.34 * smooth(0.86, 1.0, t)
    }

    private static func tailEnd(_ t: Float, start: Float = 0.70) -> Float {
        guard t > start else { return 1 }
        let u = min((t - start) / (1 - start), 1)
        return pow(max(0, 1 - pow(u, 1.95)), 0.52) * 0.985 + 0.015
    }

    private static func rightWidth(_ t: Float) -> Float {
        let noseTaper: Float = 1 - 0.05 * (1 - smooth(0.0, 0.12, t))
        let base = (1.36 + 0.15 * smooth(0.10, 0.34, t) + 0.155 * smooth(0.42, 0.70, t)) * noseTaper
        return base * tailEnd(t, start: 0.71)
    }

    private static func upperLeftWidth(_ t: Float) -> Float {
        let noseTaper: Float = 1 - 0.05 * (1 - smooth(0.0, 0.12, t))
        let base = (1.38 + 0.15 * smooth(0.10, 0.32, t) + 0.11 * smooth(0.45, 0.68, t)) * noseTaper
        return base * tailEnd(t, start: 0.70)
    }

    /// Broad ergonomic thumb shelf flaring out along the lower-left flank (`t = 0.34..0.91`).
    private static func wingFlare(_ t: Float) -> Float {
        let rise = smooth(0.34, 0.50, t)
        let hold = 1.0 + 0.08 * smooth(0.50, 0.67, t)
        let fall = 1.0 - smooth(0.67, 0.91, t)
        return 0.58 * rise * hold * fall * tailEnd(t, start: 0.72)
    }

    /// Concave thumb scoop above the thumb wing on the left flank.
    private static func scoop(_ t: Float) -> Float {
        0.15 * exp(-pow((t - 0.53) / 0.16, 2))
    }

    static let channelHalfX: Float = 0.242
    static let islandHalfX: Float = 0.232
    static let frontNotchT: Float = 0.046

    /// Transverse rear seam of the click paddles: straight at `t = 0.450`, rounding at the outer rear corners.
    static func seam(_ uOuter: Float) -> Float {
        let corner = max(0, (uOuter - 0.80) / 0.20)
        return 0.450 - 0.018 * corner * corner
    }

    /// Outer longitudinal seam angle of each click paddle, leaving a crisp ~0.10 u outer shoulder rim.
    static func outerPaddleAngle(left: Bool, t: Float) -> Float {
        let base: Float = left ? 0.815 * .pi : 0.185 * .pi
        let noseFlare: Float = (left ? 0.018 : -0.018) * .pi * (1 - smooth(0.0, 0.16, t))
        return base + noseFlare
    }

    static func surface(_ t: Float, _ a: Float) -> SIMD3<Float> {
        let ca = cos(a), sa = sin(a)
        let h = height(t)
        let lip = lipY(t)

        // Smooth C1 vertical crown/flank transition across sa = 0 (eliminates flank & tail creases).
        let c0: Float = 0.240 // 0.045^0.46
        let crownNorm = 1.0 / (1.0 - c0)
        let yUpper = lip + (h - lip) * ((pow(max(sa, 0) * 0.955 + 0.045, 0.46) - c0) * crownNorm)
        let yLower = softMax(0.005, lip * (1 + sa), k: 0.018)
        let topMix = smooth(-0.14, 0.14, sa)
        let y = yLower * (1 - topMix) + yUpper * topMix

        let r = min(max((y - 0.07) / max(h - 0.07, 0.01), 0), 1)

        let w: Float
        if ca < 0 {
            let scoopBand = sin(min(max((r - 0.18) / 0.68, 0), 1) * .pi)
            let upperWing = pow(max(0, 1 - r / 0.48), 1.75)
            let lowerWing = 1 + min(sa, 0) * 0.32
            let wingFactor = lowerWing * (1 - topMix) + upperWing * topMix
            w = upperLeftWidth(t) + wingFlare(t) * wingFactor - scoop(t) * scoopBand
        } else {
            w = rightWidth(t) * (1 - 0.05 * r)
        }

        // Smooth lateral curve with finite linear derivative at ca = 0 (no top-centerline pinching).
        let xCurve = abs(ca) * (1.28 - 0.28 * ca * ca)
        let x = (ca < 0 ? -1 : 1) * xCurve * max(w, 0.02)

        // Smooth rounded paddle nose silhouette with a subtle ergonomic front bumper tuck (no overhanging beak).
        let ax = abs(x)
        let innerRound = 0.09 * (1 - smooth(0.24, 0.58, ax))
        let outerSweep = 0.34 * pow(smooth(0.36, 1.34, ax), 1.48)
        let upperCut = (innerRound + outerSweep) * (1 - smooth(0.0, 0.24, t))

        let underMix = smooth(0.20, -0.85, sa)
        let chinTuck = 0.24 * (1 - smooth(0.0, 0.18, t))
        let chinTarget = softMax(upperCut + 0.08 * (1 - smooth(0.0, 0.18, t)), chinTuck, k: 0.08)
        let centerU = 0.14 * (1 - smooth(0.18, 0.30, ax)) * (1 - smooth(0.0, 0.12, t)) * (1 - underMix * 0.65)
        let frontCut = upperCut * (1 - underMix) + chinTarget * underMix + centerU

        let rearUnder: Float = -0.22 * pow(smooth(0.05, -1.0, sa), 0.90) * smooth(0.86, 1.0, t)

        let z = -3.39 + t * length + frontCut + rearUnder
        return SIMD3(x, y, z)
    }

    static func uv(_ t: Float, _ a: Float) -> SIMD2<Float> { SIMD2(a / (2 * .pi), t) }

    /// Exact ring angle `a ∈ [0, π]` whose top surface crosses Cartesian `targetX` at longitudinal parameter `t`.
    static func angleForTopX(_ targetX: Float, at t: Float) -> Float {
        var lo: Float = 0.02
        var hi: Float = .pi - 0.02
        // surface(t, a).x decreases monotonically from +width (a=0) to -width (a=π).
        for _ in 0..<18 {
            let mid = 0.5 * (lo + hi)
            if surface(t, mid).x > targetX {
                lo = mid
            } else {
                hi = mid
            }
        }
        return 0.5 * (lo + hi)
    }

    // MARK: Mesh helpers

    /// A grid patch: `point(u, v)` gives (t, a) for u across and v along; rows run along v.
    private static func patch(rows: Int, cols: Int, lift: Float = 0,
                              _ param: (Float, Float) -> (t: Float, a: Float),
                              into pts: inout [SIMD3<Float>], _ uvs: inout [SIMD2<Float>], _ idx: inout [Int32]) {
        let base = Int32(pts.count)
        for r in 0...rows {
            for c in 0...cols {
                let (t, a) = param(Float(c) / Float(cols), Float(r) / Float(rows))
                var p = surface(t, a)
                if lift != 0 {
                    p += normal(t, a) * lift
                }
                pts.append(p)
                uvs.append(uv(t, a))
            }
        }
        let w = Int32(cols + 1)
        for r in 0..<Int32(rows) {
            for c in 0..<Int32(cols) {
                let a0 = base + r * w + c, b0 = a0 + 1, d0 = a0 + w, c0 = d0 + 1
                idx += [a0, b0, d0, b0, c0, d0]
            }
        }
    }

    /// Outward surface normal by finite differences.
    static func normal(_ t: Float, _ a: Float) -> SIMD3<Float> {
        let e: Float = 0.002
        let dt = surface(min(t + e, 1), a) - surface(max(t - e, 0), a)
        let da = surface(t, a + e) - surface(t, a - e)
        var n = simd_normalize(simd_cross(da, dt))
        let centre = SIMD3<Float>(0, height(t) * 0.45, -3.39 + t * length)
        if simd_dot(n, surface(t, a) - centre) < 0 { n = -n }
        return n
    }

    private static let gapX: Float = 0.009
    private static let gapA: Float = 0.0030 * .pi
    private static let gapT: Float = 0.0022

    /// One click paddle; `lift` raises it off the shell (used for the press highlight).
    /// When `lift == 0`, includes molded seam bevels and a solid underside lip on the protruding front prong.
    static func paddle(left: Bool, lift: Float = 0) -> SCNGeometry {
        var pts = [SIMD3<Float>](), uvs = [SIMD2<Float>](), idx = [Int32]()
        let rows = 36, cols = 24
        let base = Int32(pts.count)

        func paddleParams(_ u: Float, _ v: Float) -> (t: Float, a: Float, uOuter: Float) {
            let uOuter = left ? u : (1 - u)
            let tEnd = seam(uOuter) - gapT
            // Mild clustering near the front tip (v = 0) keeps nose curves smooth.
            let ve = v * (0.65 + 0.35 * v)
            let t = tEnd * ve
            let aInner = angleForTopX(left ? -(channelHalfX + gapX) : (channelHalfX + gapX), at: t)
            let aOuter = outerPaddleAngle(left: left, t: t) + (left ? -gapA : gapA)
            let a = left ? (aInner + (aOuter - aInner) * u) : (aOuter + (aInner - aOuter) * u)
            return (t, a, uOuter)
        }

        for r in 0...rows {
            let v = Float(r) / Float(rows)
            for c in 0...cols {
                let u = Float(c) / Float(cols)
                let (t, a, uOuter) = paddleParams(u, v)
                let n = normal(t, a)
                var p = surface(t, a)
                if lift != 0 {
                    p += n * lift
                } else {
                    let innerDrop = 0.009 * (1 - smooth(0.0, 0.06, uOuter))
                    let outerDrop = 0.009 * (1 - smooth(0.94, 1.0, uOuter))
                    let rearDrop  = 0.009 * smooth(0.96, 1.0, v)
                    let frontDrop = 0.012 * (1 - smooth(0.0, 0.05, v))
                    p -= n * (innerDrop + outerDrop + rearDrop + frontDrop)
                }
                pts.append(p)
                uvs.append(uv(t, a))
            }
        }
        let stride = Int32(cols + 1)
        for r in 0..<Int32(rows) {
            for c in 0..<Int32(cols) {
                let a0 = base + r * stride + c, b0 = a0 + 1, d0 = a0 + stride, c0 = d0 + 1
                idx += [a0, b0, d0, b0, c0, d0]
            }
        }

        // Solid underside skirt on the protruding front & inner prong walls (seen from front / bottom).
        if lift == 0 {
            let lipThick: Float = 0.045
            // Front edge (v = 0)
            let frontBase = Int32(pts.count)
            for c in 0...cols {
                let u = Float(c) / Float(cols)
                let (t, a, uOuter) = paddleParams(u, 0)
                let n = normal(t, a)
                let frontDrop = 0.010 + 0.006 * (1 - smooth(0.0, 0.06, uOuter)) + 0.006 * (1 - smooth(0.94, 1.0, uOuter))
                let topP = surface(t, a) - n * frontDrop
                let botP = topP - SIMD3<Float>(0, lipThick, -0.018)
                pts.append(topP); uvs.append(uv(t, a))
                pts.append(botP); uvs.append(uv(t, a))
            }
            for c in 0..<Int32(cols) {
                let t0 = frontBase + c * 2
                let b0 = t0 + 1
                let t1 = t0 + 2
                let b1 = t0 + 3
                idx += [t0, b0, t1, b0, b1, t1]
            }

            // Inner channel wall (uInner: u = 0 when left, u = 1 when right)
            let uInner: Float = left ? 0 : 1
            let wallBase = Int32(pts.count)
            for r in 0...rows {
                let v = Float(r) / Float(rows)
                let (t, a, _) = paddleParams(uInner, v)
                let n = normal(t, a)
                let topP = surface(t, a) - n * (0.009 + 0.012 * (1 - smooth(0.0, 0.05, v)))
                let botP = topP - SIMD3<Float>(0, lipThick, 0)
                pts.append(topP); uvs.append(uv(t, a))
                pts.append(botP); uvs.append(uv(t, a))
            }
            for r in 0..<Int32(rows) {
                let t0 = wallBase + r * 2
                let b0 = t0 + 1
                let t1 = t0 + 2
                let b1 = t0 + 3
                if left {
                    idx += [t0, t1, b0, t1, b1, b0]
                } else {
                    idx += [t0, b0, t1, b0, b1, t1]
                }
            }
        }

        return CapMesh.assemble(pts, uvs, [idx])
    }

    // MARK: Build

    static func build(into mouse: SCNNode, shell: SCNMaterial, dark: SCNMaterial) {
        shell.diffuse.wrapS = .repeat

        // Body: rear palm top behind paddles, plus flanks and base all the way round.
        var pts = [SIMD3<Float>](), uvs = [SIMD2<Float>](), idx = [Int32]()

        // 1. Rear palm top between the outer paddle seams (v = 0..1 clustered near tail).
        patch(rows: 48, cols: 48, { u, v in
            let s: Float
            if u < 0.25 {
                let uOuter = 1 - 0.20 * (u / 0.25)
                s = seam(uOuter) + gapT
            } else if u > 0.75 {
                let uOuter = 1 - 0.20 * ((1 - u) / 0.25)
                s = seam(uOuter) + gapT
            } else {
                s = 0.450 + gapT
            }
            let ve = 1 - pow(1 - v, 1.45)
            let t = s + (1 - s) * ve
            let aR = outerPaddleAngle(left: false, t: t)
            let aL = outerPaddleAngle(left: true, t: t)
            let a = aR + (aL - aR) * u
            return (t, a)
        }, into: &pts, &uvs, &idx)

        // 2. Left flank, underside, and right flank (`t = 0..1`, cosine-clustered at nose & tail).
        patch(rows: 84, cols: 64, { u, v in
            let t = 0.5 - 0.5 * cos(v * .pi)
            let aL = outerPaddleAngle(left: true, t: t)
            let aR = outerPaddleAngle(left: false, t: t) + 2 * .pi
            return (t, aL + (aR - aL) * u)
        }, into: &pts, &uvs, &idx)

        // 3. Smooth closed front bumper & recessed USB-C notch bulkhead bridging `t = 0` lower nose
        //    to the upper arch underneath the click paddles and behind the center island wall.
        let noseRingCols = 64
        let noseRows = 4
        let noseBase = Int32(pts.count)
        let aL0 = outerPaddleAngle(left: true, t: 0)
        let aR0 = outerPaddleAngle(left: false, t: 0) + 2 * .pi
        let aRTop = outerPaddleAngle(left: false, t: 0)
        for r in 0...noseRows {
            let v = Float(r) / Float(noseRows)
            let zBulge = -0.022 * sin(v * .pi)
            for c in 0...noseRingCols {
                let u = Float(c) / Float(noseRingCols)
                let aLow = aL0 + (aR0 - aL0) * u
                let aTop = aL0 + (aRTop - aL0) * u
                let pBot = surface(0, aLow)
                let topSurf = surface(0, aTop)
                let cornerTaper = sin(u * .pi)

                let inNotch = 1 - smooth(channelHalfX * 0.90, channelHalfX + 0.16, abs(topSurf.x))
                let targetX = min(max(topSurf.x, -(channelHalfX + 0.04)), channelHalfX + 0.04)
                let bridgeTop = surface(frontNotchT, angleForTopX(targetX, at: frontNotchT))
                let notchTop = SIMD3<Float>(targetX, bridgeTop.y - 0.075, bridgeTop.z + 0.010)
                let sideTop = SIMD3<Float>(
                    topSurf.x * (1 - 0.02 * cornerTaper),
                    topSurf.y - 0.055 * cornerTaper,
                    topSurf.z + 0.085 * cornerTaper
                )
                let pTop = sideTop * (1 - inNotch) + notchTop * inNotch

                var p = pBot + (pTop - pBot) * v
                p.z += zBulge * cornerTaper * (1 - inNotch * 0.65)
                pts.append(p)
                uvs.append(uv(frontNotchT * v, aLow * (1 - v) + aTop * v))
            }
        }
        let noseStride = Int32(noseRingCols + 1)
        for r in 0..<Int32(noseRows) {
            for c in 0..<Int32(noseRingCols) {
                let b0 = noseBase + r * noseStride + c
                let b1 = b0 + 1
                let t0 = b0 + noseStride
                let t1 = t0 + 1
                idx += [b0, t0, b1, t0, t1, b1]
            }
        }

        // 4. Smooth tail cap at t = 1.
        let ring = 72
        var tailSum = SIMD3<Float>.zero
        var tailRing = [SIMD3<Float>]()
        var tailUVs = [SIMD2<Float>]()
        tailRing.reserveCapacity(ring + 1)
        tailUVs.reserveCapacity(ring + 1)
        for i in 0...ring {
            let a = Float(i) / Float(ring) * 2 * .pi
            let p = surface(1, a)
            tailRing.append(p)
            tailUVs.append(uv(1, a))
            if i < ring { tailSum += p }
        }
        let tailCenter = tailSum / Float(ring) + SIMD3<Float>(0, 0, 0.012)
        let tc = Int32(pts.count)
        pts.append(tailCenter); uvs.append(SIMD2(0.25, 1))
        let tailFirst = Int32(pts.count)
        pts.append(contentsOf: tailRing)
        uvs.append(contentsOf: tailUVs)
        for i in 0..<Int32(ring) {
            idx += [tc, tailFirst + i, tailFirst + i + 1]
        }

        let body = CapMesh.assemble(pts, uvs, [idx])
        body.materials = [shell]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.castsShadow = true
        mouse.addChildNode(bodyNode)

        // Satin dark top seam liner recessed strictly under the paddle & center island grooves.
        var ip = [SIMD3<Float>](), iu = [SIMD2<Float>](), ii = [Int32]()
        let aMinInner: Float = 0.145 * .pi
        let aMaxInner: Float = 0.855 * .pi
        patch(rows: 32, cols: 48, lift: -0.022, { u, v in
            let a = aMinInner + (aMaxInner - aMinInner) * u
            let xApprox = cos(a) * 1.35
            let inCenterNotch = 1 - smooth(channelHalfX * 0.9, channelHalfX + 0.14, abs(xApprox))
            let tStart: Float = 0.018 * (1 - inCenterNotch) + (frontNotchT + 0.016) * inCenterNotch
            let t = tStart + (0.485 - tStart) * v
            return (t, a)
        }, into: &ip, &iu, &ii)
        let inner = CapMesh.assemble(ip, iu, [ii])
        let seamMat = SCNMaterial()
        seamMat.lightingModel = .physicallyBased
        seamMat.diffuse.contents = NSColor(srgbRed: 0.15, green: 0.15, blue: 0.16, alpha: 1)
        seamMat.roughness.contents = 0.62
        inner.materials = [seamMat]
        let innerNode = SCNNode(geometry: inner)
        innerNode.castsShadow = false
        mouse.addChildNode(innerNode)

        // Dedicated sculpted satin-white center wheel island between the parallel paddles (no top DPI button).
        let islandMat = SCNMaterial()
        islandMat.lightingModel = .physicallyBased
        islandMat.diffuse.contents = NSColor(srgbRed: 0.865, green: 0.860, blue: 0.852, alpha: 1)
        islandMat.roughness.contents = 0.44
        islandMat.metalness.contents = 0.0
        islandMat.clearCoat.contents = 0.10
        islandMat.clearCoatRoughness.contents = 0.36
        buildCenterIsland(into: mouse, material: islandMat)

        // Click paddles.
        for left in [true, false] {
            let geo = paddle(left: left)
            geo.materials = [shell]
            let node = SCNNode(geometry: geo)
            node.castsShadow = true
            mouse.addChildNode(node)
        }

        buildWheel(into: mouse)
        buildLED(into: mouse)
        buildUSBC(into: mouse, dark: dark)
        buildSideButtons(into: mouse, dark: dark)
    }
}
