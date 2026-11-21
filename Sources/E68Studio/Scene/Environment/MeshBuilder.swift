import SceneKit
import simd

/// Procedural 3D mesh builders with welded smooth normals and parallel-transport sweeps.
enum MeshBuilder {

    // MARK: - Catmull-Rom Spline

    /// Samples a smooth Catmull-Rom spline through `controlPoints`.
    static func catmullRom(_ controlPoints: [SIMD3<Float>], samplesPerSegment: Int = 10) -> [SIMD3<Float>] {
        guard controlPoints.count >= 2 else { return controlPoints }
        var pts = [controlPoints.first! + (controlPoints.first! - controlPoints[1])]
        pts.append(contentsOf: controlPoints)
        pts.append(controlPoints.last! + (controlPoints.last! - controlPoints[controlPoints.count - 2]))

        var out = [SIMD3<Float>]()
        for i in 1..<(pts.count - 2) {
            let p0 = pts[i - 1], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2]
            let steps = (i == pts.count - 3) ? samplesPerSegment : samplesPerSegment
            for s in 0..<steps {
                let t = Float(s) / Float(steps)
                let t2 = t * t, t3 = t2 * t
                let p = 0.5 * (
                    (2 * p1) +
                    (-p0 + p2) * t +
                    (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                    (-p0 + 3 * p1 - 3 * p2 + p3) * t3
                )
                out.append(p)
            }
        }
        out.append(controlPoints.last!)
        return out
    }

    // MARK: - Loft & Lathe

    /// Builds a smooth lofted mesh across a sequence of closed rings (each ring must have the same vertex count).
    static func loft(
        rings: [[SIMD3<Float>]],
        capBottom: Bool = false,
        capTop: Bool = false,
        flipWinding: Bool = false,
        uvForPoint: ((SIMD3<Float>, Float, Float) -> SIMD2<Float>)? = nil
    ) -> SCNGeometry {
        precondition(rings.count >= 2)
        let n = rings[0].count
        var positions = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [Int32]()

        for (rIdx, ring) in rings.enumerated() {
            precondition(ring.count == n)
            let v = Float(rIdx) / Float(max(rings.count - 1, 1))
            for (i, p) in ring.enumerated() {
                let u = Float(i) / Float(n)
                positions.append(p)
                uvs.append(uvForPoint?(p, u, v) ?? SIMD2(u, v))
            }
        }

        for r in 0..<(rings.count - 1) {
            for i in 0..<n {
                let next = (i + 1) % n
                let a = Int32(r * n + i)
                let b = Int32(r * n + next)
                let d = Int32((r + 1) * n + i)
                let c = Int32((r + 1) * n + next)
                if flipWinding {
                    indices += [a, b, d, b, c, d]
                } else {
                    indices += [a, d, b, b, d, c]
                }
            }
        }

        if capBottom, let first = rings.first {
            let center = first.reduce(SIMD3<Float>.zero, +) / Float(n)
            let ci = Int32(positions.count)
            positions.append(center)
            uvs.append(uvForPoint?(center, 0.5, 0) ?? SIMD2(0.5, 0))
            for i in 0..<n {
                let a = Int32(i), b = Int32((i + 1) % n)
                indices += flipWinding ? [ci, b, a] : [ci, a, b]
            }
        }

        if capTop, let last = rings.last {
            let center = last.reduce(SIMD3<Float>.zero, +) / Float(n)
            let ci = Int32(positions.count)
            let base = Int32((rings.count - 1) * n)
            positions.append(center)
            uvs.append(uvForPoint?(center, 0.5, 1) ?? SIMD2(0.5, 1))
            for i in 0..<n {
                let a = base + Int32(i), b = base + Int32((i + 1) % n)
                indices += flipWinding ? [ci, a, b] : [ci, b, a]
            }
        }

        return CapMesh.assemble(positions, uvs, [indices])
    }

    /// Revolved mesh from `(radius, y)` profile points around the Y axis.
    static func lathe(
        profile: [(r: Float, y: Float)],
        segments: Int = 48,
        capBottom: Bool = false,
        capTop: Bool = false
    ) -> SCNGeometry {
        let rings: [[SIMD3<Float>]] = profile.map { pt in
            (0..<segments).map { i in
                let a = Float(i) / Float(segments) * 2 * .pi
                return SIMD3(pt.r * cos(a), pt.y, pt.r * sin(a))
            }
        }
        return loft(rings: rings, capBottom: capBottom, capTop: capTop)
    }

    // MARK: - Parallel-Transport Frames & Swept Tubes

    private static func frames(along points: [SIMD3<Float>]) -> [(t: SIMD3<Float>, n: SIMD3<Float>, b: SIMD3<Float>)] {
        guard points.count >= 2 else { return [] }
        var tangents = [SIMD3<Float>]()
        for i in 0..<points.count {
            let prev = points[max(0, i - 1)]
            let next = points[min(points.count - 1, i + 1)]
            let d = next - prev
            tangents.append(simd_length(d) > 1e-6 ? simd_normalize(d) : SIMD3(0, 1, 0))
        }

        let t0 = tangents[0]
        let up = abs(t0.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        var n0 = simd_normalize(simd_cross(up, t0))
        var b0 = simd_normalize(simd_cross(t0, n0))
        var out = [(t0, n0, b0)]

        for i in 1..<tangents.count {
            let prevT = tangents[i - 1]
            let curT = tangents[i]
            let axis = simd_cross(prevT, curT)
            let axisLen = simd_length(axis)
            if axisLen > 1e-5 {
                let angle = atan2(axisLen, simd_dot(prevT, curT))
                let q = simd_quatf(angle: angle, axis: axis / axisLen)
                n0 = simd_normalize(q.act(n0))
            }
            b0 = simd_normalize(simd_cross(curT, n0))
            out.append((curT, n0, b0))
        }
        return out
    }

    /// Sweeps a circular tube with optional variable radii along a 3D point sequence.
    static func tube(
        points: [SIMD3<Float>],
        radius: Float,
        radii: [Float]? = nil,
        segments: Int = 14,
        capEnds: Bool = true
    ) -> SCNGeometry {
        precondition(points.count >= 2)
        let frms = frames(along: points)
        var rings = [[SIMD3<Float>]]()
        for (i, p) in points.enumerated() {
            let r = radii != nil ? radii![min(i, radii!.count - 1)] : radius
            let (_, n, b) = frms[i]
            var ring = [SIMD3<Float>]()
            for s in 0..<segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                ring.append(p + (n * cos(a) + b * sin(a)) * r)
            }
            rings.append(ring)
        }
        return loft(rings: rings, capBottom: capEnds, capTop: capEnds, flipWinding: true)
    }

    /// Sweeps a circular tube with seamless arc-length UVs (`u` in `0...1` with duplicated seam
    /// vertices welded by `CapMesh.assemble`, `v` scaled by cumulative arc length).
    static func uvTube(
        points: [SIMD3<Float>],
        radius: Float,
        radii: [Float]? = nil,
        segments: Int = 18,
        uvLengthScale: Float? = nil,
        capEnds: Bool = true
    ) -> SCNGeometry {
        precondition(points.count >= 2)
        let frms = frames(along: points)
        let vScale = uvLengthScale ?? (1.0 / max(2 * .pi * radius, 1e-4))
        var arc: Float = 0
        let stride = segments + 1
        var positions = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [Int32]()

        for (i, p) in points.enumerated() {
            if i > 0 { arc += simd_length(p - points[i - 1]) }
            let (_, n, b) = frms[i]
            let r = radii != nil ? radii![min(i, radii!.count - 1)] : radius
            let v = arc * vScale
            for s in 0...segments {
                let u = Float(s) / Float(segments)
                let a = u * 2 * .pi
                let pt = (s == segments) ? positions[i * stride] : p + (n * cos(a) + b * sin(a)) * r
                positions.append(pt)
                uvs.append(SIMD2(u, v))
            }
        }

        for r in 0..<(points.count - 1) {
            for s in 0..<segments {
                let a = Int32(r * stride + s)
                let b = Int32(r * stride + s + 1)
                let d = Int32((r + 1) * stride + s)
                let c = Int32((r + 1) * stride + s + 1)
                indices += [a, b, d, b, c, d]
            }
        }

        if capEnds {
            let botC = Int32(positions.count)
            positions.append(points.first!)
            uvs.append(SIMD2(0.5, 0))
            for s in 0..<segments {
                indices += [botC, Int32(s + 1), Int32(s)]
            }

            let topC = Int32(positions.count)
            let base = Int32((points.count - 1) * stride)
            positions.append(points.last!)
            uvs.append(SIMD2(0.5, arc * vScale))
            for s in 0..<segments {
                indices += [topC, base + Int32(s), base + Int32(s + 1)]
            }
        }

        return CapMesh.assemble(positions, uvs, [indices])
    }

    /// Builds a multi-strand helical braided cable along `points`.
    /// Element 0 = silver strands, Element 1 = copper-foil strands.
    static func braidedCable(
        points: [SIMD3<Float>],
        bundleRadius: Float = 0.042,
        strandRadius: Float = 0.022,
        strands: Int = 4,
        turnsPerUnit: Float = 2.6,
        segments: Int = 8
    ) -> SCNGeometry {
        precondition(points.count >= 2)
        let frms = frames(along: points)

        var arc = [Float](repeating: 0, count: points.count)
        for i in 1..<points.count {
            arc[i] = arc[i - 1] + simd_length(points[i] - points[i - 1])
        }

        var positions = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var silverIndices = [Int32]()
        var copperIndices = [Int32]()

        for strand in 0..<strands {
            let basePhase = Float(strand) / Float(strands) * 2 * .pi
            let dir: Float = (strand % 2 == 0) ? 1 : -1
            let startVert = positions.count

            var strandCenters = [SIMD3<Float>]()
            for i in 0..<points.count {
                let angle = basePhase + dir * arc[i] * turnsPerUnit * 2 * .pi
                let (_, n, b) = frms[i]
                let offset = (n * cos(angle) + b * sin(angle)) * bundleRadius
                strandCenters.append(points[i] + offset)
            }
            let sFrames = frames(along: strandCenters)
            for i in 0..<strandCenters.count {
                let (_, n, b) = sFrames[i]
                let v = arc[i]
                for s in 0..<segments {
                    let a = Float(s) / Float(segments) * 2 * .pi
                    positions.append(strandCenters[i] + (n * cos(a) + b * sin(a)) * strandRadius)
                    uvs.append(SIMD2(Float(s) / Float(segments), v))
                }
            }

            let isCopper = (strand % 2 == 1)
            for i in 0..<(strandCenters.count - 1) {
                for s in 0..<segments {
                    let next = (s + 1) % segments
                    let a = Int32(startVert + i * segments + s)
                    let b = Int32(startVert + i * segments + next)
                    let d = Int32(startVert + (i + 1) * segments + s)
                    let c = Int32(startVert + (i + 1) * segments + next)
                    if isCopper {
                        copperIndices += [a, d, b, b, d, c]
                    } else {
                        silverIndices += [a, d, b, b, d, c]
                    }
                }
            }
        }

        return CapMesh.assemble(positions, uvs, [silverIndices, copperIndices])
    }

    // MARK: - Rounded Slab & Leaf

    /// Extruded rounded-rectangle prism with chamfered top and bottom edges.
    static func roundedSlab(
        width: Float,
        height: Float,
        depth: Float,
        cornerRadius: Float,
        bevel: Float = 0.06,
        cornerSegments: Int = 8,
        planarUVs: Bool = false
    ) -> SCNGeometry {
        let hw = width / 2, hd = depth / 2
        let r = min(cornerRadius, hw * 0.95, hd * 0.95)
        let b = min(bevel, height * 0.45, r * 0.6)

        func outline(inset: Float, y: Float) -> [SIMD3<Float>] {
            let hx = max(0.01, hw - inset), hz = max(0.01, hd - inset)
            let cr = max(0.005, r - inset)
            var pts = [SIMD3<Float>]()
            let signs: [(Float, Float)] = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
            for (c, sign) in signs.enumerated() {
                for i in 0...cornerSegments {
                    let a = (Float(c) + Float(i) / Float(cornerSegments)) * .pi / 2
                    let x = sign.0 * (hx - cr) + cr * cos(a)
                    let z = sign.1 * (hz - cr) + cr * sin(a)
                    pts.append(SIMD3(x, y, z))
                }
            }
            return pts
        }

        let rings: [[SIMD3<Float>]] = [
            outline(inset: b, y: 0),
            outline(inset: 0, y: b),
            outline(inset: 0, y: height - b),
            outline(inset: b, y: height),
        ]
        let uvMap: ((SIMD3<Float>, Float, Float) -> SIMD2<Float>)? = planarUVs
            ? { p, _, _ in SIMD2(p.x / max(width, 1e-4) + 0.5, p.z / max(depth, 1e-4) + 0.5) }
            : nil
        return loft(rings: rings, capBottom: true, capTop: true, uvForPoint: uvMap)
    }

    /// Sculpted botanical leaf mesh extending along +Z (from stem base at 0 to tip at `length`),
    /// with organic rounded cordate heart-lobes or lance-shaped bamboo contours, gentle S-camber, and soft margin curl.
    static func leaf(
        length: Float,
        width: Float,
        heartShaped: Bool = true,
        droop: Float = 0.35,
        midribFold: Float = 0.14,
        rows: Int = 20,
        cols: Int = 14
    ) -> SCNGeometry {
        var positions = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [Int32]()

        for r in 0...rows {
            let v = Float(r) / Float(rows)
            let envelope: Float
            if heartShaped {
                // Smooth plump waxy ovate-cordate pothos contour: broad rounded basal lobes near v~0.28, cute soft tip
                let baseSwell = v < 0.28 ? pow(sin(v / 0.28 * .pi * 0.5), 0.48) : 1.0
                let tipTaper = v > 0.28 ? pow(cos((v - 0.28) / 0.72 * .pi * 0.5), 0.56) : 1.0
                envelope = baseSwell * tipTaper
            } else {
                envelope = sin(pow(v, 0.72) * .pi)
            }

            let halfW = (width * 0.5) * envelope
            let archY = sin(v * .pi * 0.74) * (length * 0.10) - (pow(v, 1.85) * length * droop)

            for c in 0...cols {
                let u = Float(c) / Float(cols)
                let side = (u - 0.5) * 2.0
                let x = side * halfW
                let absS = abs(side)
                // Cordate basal heart lobes sweep cleanly behind the petiole sinus near v < 0.34
                let lobeWave = sin(min(absS, 0.90) / 0.90 * .pi)
                let zPull: Float = heartShaped ? -0.22 * length * pow(max(0, 1.0 - v * 2.9), 1.30) * lobeWave : 0
                let z = v * length + zPull
                // Distinct centre V-crease along midrib + gentle outer edge curl
                let y = archY + pow(absS, 1.15) * width * midribFold - pow(absS, 2.7) * width * 0.060
                positions.append(SIMD3(x, y, z))
                uvs.append(SIMD2(u, 1.0 - v))
            }
        }

        let stride = cols + 1
        for r in 0..<rows {
            for c in 0..<cols {
                let a = Int32(r * stride + c)
                let b = Int32(r * stride + c + 1)
                let d = Int32((r + 1) * stride + c)
                let e = Int32((r + 1) * stride + c + 1)
                indices += [a, d, b, b, d, e]
            }
        }
        return CapMesh.assemble(positions, uvs, [indices])
    }

    /// Sweeps a botanical leaf blade along a 3D spine curve using twist-free parallel-transport frames.
    /// The base (`v < sheathLengthFraction`) wraps smoothly into a clasping sheath/petiole before widening into the blade.
    static func curvedLeaf(
        spine: [SIMD3<Float>],
        width: Float,
        sheathLengthFraction: Float = 0.08,
        baseWidthFraction: Float = 0.14,
        midribFold: Float = 0.16,
        edgeCurl: Float = 0.08,
        waveAmp: Float = 0.025,
        roll: Float = 0,
        lateralHint: SIMD3<Float>? = nil,
        cols: Int = 10
    ) -> SCNGeometry {
        precondition(spine.count >= 2)
        let nPts = spine.count

        // Compute smooth tangents along spine
        var tangents = [SIMD3<Float>]()
        tangents.reserveCapacity(nPts)
        for i in 0..<nPts {
            let prev = spine[max(0, i - 1)]
            let next = spine[min(nPts - 1, i + 1)]
            let d = next - prev
            tangents.append(simd_length(d) > 1e-6 ? simd_normalize(d) : SIMD3(0, 1, 0))
        }

        // Choose initial lateral axis so the blade faces upward/outward naturally
        let chord = spine.last! - spine.first!
        let chordXZ = SIMD3<Float>(chord.x, 0, chord.z)
        let preferredLateral: SIMD3<Float>
        if let hint = lateralHint, simd_length(hint) > 1e-4 {
            preferredLateral = simd_normalize(hint)
        } else if simd_length(chordXZ) > 0.12 {
            preferredLateral = simd_normalize(simd_cross(SIMD3(0, 1, 0), chordXZ))
        } else {
            preferredLateral = SIMD3(1, 0, 0)
        }

        let t0 = tangents[0]
        var sideAxis = preferredLateral - simd_dot(preferredLateral, t0) * t0
        if simd_length(sideAxis) < 1e-4 {
            let fallback = abs(t0.x) < 0.8 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 0, 1)
            sideAxis = simd_cross(fallback, t0)
        }
        sideAxis = simd_normalize(sideAxis)
        if abs(roll) > 1e-4 {
            sideAxis = simd_normalize(simd_quatf(angle: roll, axis: t0).act(sideAxis))
        }
        var upAxis = simd_normalize(simd_cross(t0, sideAxis))

        var framesList = [(side: sideAxis, up: upAxis)]
        framesList.reserveCapacity(nPts)
        for i in 1..<nPts {
            let prevT = tangents[i - 1]
            let curT = tangents[i]
            let axis = simd_cross(prevT, curT)
            let axisLen = simd_length(axis)
            if axisLen > 1e-5 {
                let angle = atan2(axisLen, simd_dot(prevT, curT))
                sideAxis = simd_normalize(simd_quatf(angle: angle, axis: axis / axisLen).act(sideAxis))
            }
            upAxis = simd_normalize(simd_cross(curT, sideAxis))
            framesList.append((sideAxis, upAxis))
        }

        // Arc-length parameterization along the 3D spine
        var arc = [Float](repeating: 0, count: nPts)
        for i in 1..<nPts {
            arc[i] = arc[i - 1] + simd_length(spine[i] - spine[i - 1])
        }
        let totalLen = max(arc.last ?? 1, 1e-4)

        var positions = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [Int32]()
        positions.reserveCapacity(nPts * (cols + 1))
        uvs.reserveCapacity(nPts * (cols + 1))

        let sFrac = max(0.01, min(sheathLengthFraction, 0.35))

        for r in 0..<nPts {
            let v = arc[r] / totalLen
            let p = spine[r]
            let (sideVec, upVec) = framesList[r]

            let envelope: Float
            let sheathCup: Float
            if v < sFrac {
                let st = v / sFrac
                let smooth = st * st * (3 - 2 * st)
                envelope = baseWidthFraction + (0.28 - baseWidthFraction) * smooth
                sheathCup = 1.0 - smooth
            } else {
                let vBlade = (v - sFrac) / (1.0 - sFrac)
                let bladeEnv = sin(pow(vBlade, 0.68) * .pi)
                envelope = max(bladeEnv, (1.0 - vBlade) * 0.28)
                sheathCup = 0
            }

            let halfW = (width * 0.5) * envelope
            let wave = sin(v * .pi * 3.5) * waveAmp * width * envelope

            for c in 0...cols {
                let u = Float(c) / Float(cols)
                let side = (u - 0.5) * 2.0
                let absS = abs(side)

                // Clasping sheath curls around stem at base; blade opens into V-cupped midrib + rolled margin
                let x = side * halfW
                let cupLift = pow(absS, 1.35) * width * (midribFold + 0.14 * sheathCup) * max(envelope, 0.2)
                let marginDrop = -pow(absS, 2.8) * width * edgeCurl * max(0, 1.0 - sheathCup) * envelope
                let midribKeel = -0.032 * width * exp(-pow(absS / 0.14, 2)) * (1.0 - v * 0.7)
                let yOff = cupLift + marginDrop + midribKeel + side * wave

                positions.append(p + sideVec * x + upVec * yOff)
                uvs.append(SIMD2(u, 1.0 - v))
            }
        }

        let stride = cols + 1
        for r in 0..<(nPts - 1) {
            for c in 0..<cols {
                let a = Int32(r * stride + c)
                let b = Int32(r * stride + c + 1)
                let d = Int32((r + 1) * stride + c)
                let e = Int32((r + 1) * stride + c + 1)
                indices += [a, d, b, b, d, e]
            }
        }
        return CapMesh.assemble(positions, uvs, [indices])
    }

    // MARK: - Pebble

    /// Soft superellipsoid "pebble": rounded-rectangle cross-sections (exponent `section`) that shrink
    /// toward both ends along Z (exponent `plan`). Bottom sits on y = 0 and is flattened by `flatBottom`
    /// (0 = fully round, 1 = flat). Used for the AirPods earbud heads.
    static func pebble(
        width: Float, height: Float, length: Float,
        plan: Float = 3.0, section: Float = 2.6, flatBottom: Float = 0.35,
        rings: Int = 36, segments: Int = 48
    ) -> SCNGeometry {
        var out = [[SIMD3<Float>]]()
        for r in 0...rings {
            let phi = Float(r) / Float(rings) * .pi
            let t = -cos(phi)
            let s = max(pow(max(0, 1 - pow(abs(t), plan)), 1 / plan), 0.004)
            let sy = pow(s, 0.72)
            var ring = [SIMD3<Float>]()
            for i in 0..<segments {
                let a = Float(i) / Float(segments) * 2 * .pi
                let c = cos(a), sn = sin(a)
                let x = width / 2 * s * (c < 0 ? -1 : 1) * pow(abs(c), 2 / section)
                var y = height / 2 * sy * (sn < 0 ? -1 : 1) * pow(abs(sn), 2 / section)
                let floor = -height / 2 * (1 - 0.5 * flatBottom)
                if y < floor { y = floor + (y - floor) * (1 - flatBottom) }
                ring.append(SIMD3(x, y, t * length / 2))
            }
            out.append(ring)
        }
        let minY = out.flatMap { $0 }.map(\.y).min() ?? 0
        out = out.map { $0.map { SIMD3($0.x, $0.y - minY, $0.z) } }
        return loft(rings: out, capBottom: true, capTop: true, flipWinding: true)
    }
}
