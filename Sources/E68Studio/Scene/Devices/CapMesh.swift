import SceneKit
import simd

enum CapMesh {
    private struct CapShapeKey: Hashable {
        let w: Int
        let h: Int
        let tilt: Int
        let convex: Bool
    }

    private static let cacheLock = NSLock()
    private static var geometryCache: [CapShapeKey: (geometry: SCNGeometry, top: SIMD2<Float>)] = [:]

    private static func instantiate(_ cached: SCNGeometry) -> SCNGeometry {
        SCNGeometry(sources: cached.sources, elements: cached.elements)
    }

    /// Top-face size of a cap, shared with the legend painter so textures match the mesh.
    static func topSize(width: Float) -> SIMD2<Float> {
        SIMD2((width - 0.055) - 0.25, 0.945 - 0.235)
    }

    /// A sculpted Cherry-profile keycap: tapered sides, filleted shoulder and gently dished top.
    /// Element 0 is the body, element 1 the top face (mapped 0…1 for the legend).
    static func make(width: Float, height: Float, tilt: Float, convex: Bool) -> (geometry: SCNGeometry, top: SIMD2<Float>) {
        let key = CapShapeKey(
            w: Int((width * 1000).rounded()),
            h: Int((height * 1000).rounded()),
            tilt: Int((tilt * 1000).rounded()),
            convex: convex
        )
        cacheLock.lock()
        if let cached = geometryCache[key] {
            cacheLock.unlock()
            return (instantiate(cached.geometry), cached.top)
        }
        cacheLock.unlock()
        let hwB = (width - 0.055) / 2, hdB: Float = 0.4725
        let top = topSize(width: width)
        let hwT = top.x / 2, hdT = top.y / 2
        let zT: Float = -0.032
        let corner = 6
        let edgeSteps = 3
        let count = 4 * (corner + edgeSteps)

        func outline(_ f: Float) -> [SIMD2<Float>] {
            let hw = hwB + (hwT - hwB) * f, hd = hdB + (hdT - hdB) * f
            let r = 0.048 + (0.095 - 0.048) * f, cz = zT * f
            var pts = [SIMD2<Float>]()
            let signs: [(Float, Float)] = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
            let cornerPts: [[SIMD2<Float>]] = signs.enumerated().map { c, sign in
                (0...corner).map { i in
                    let a = (Float(c) + Float(i) / Float(corner)) * .pi / 2
                    return SIMD2(sign.0 * (hw - r) + r * cos(a), cz + sign.1 * (hd - r) + r * sin(a))
                }
            }
            for c in 0..<4 {
                let cur = cornerPts[c]
                let nxt = cornerPts[(c + 1) % 4]
                for i in 0..<corner { pts.append(cur[i]) }
                let endA = cur[corner], startB = nxt[0]
                for s in 0..<edgeSteps {
                    let t = Float(s) / Float(edgeSteps)
                    pts.append(endA + (startB - endA) * t)
                }
            }
            return pts
        }
        func lift(_ p: SIMD2<Float>, _ y: Float, _ f: Float) -> SIMD3<Float> {
            let across = max(0, 1 - (p.x / hwT) * (p.x / hwT))
            let along = max(0, 1 - ((p.y - zT) / hdT) * ((p.y - zT) / hdT))
            let dish: Float = convex ? -0.025 * along : 0.036 * across
            return SIMD3(p.x, y + f * tilt * (p.y - zT * f) * -1 - dish * pow(f, 6), p.y)
        }

        var positions = [SIMD3<Float>](), uvs = [SIMD2<Float>]()
        var body = [Int32](), face = [Int32]()
        let rings: [(Float, Float)] = [
            (0, 0), (0.035, 0.05), (0.80, height - 0.095), (0.91, height - 0.042), (0.975, height - 0.011), (1.0, height),
        ]
        for (f, y) in rings {
            for (i, p) in outline(f).enumerated() {
                positions.append(lift(p, y, f))
                uvs.append(SIMD2(Float(i) / Float(count) * 4.0, f))
            }
        }
        func bridge(_ lower: Int, _ upper: Int, into indices: inout [Int32]) {
            for i in 0..<count {
                let a = Int32(lower + i), b = Int32(lower + (i + 1) % count)
                let d = Int32(upper + i), c = Int32(upper + (i + 1) % count)
                indices += [a, d, b, b, d, c]
            }
        }
        for k in 0..<(rings.count - 1) { bridge(k * count, (k + 1) * count, into: &body) }

        // Top face: concentric rings closing on the centre (welded normals share the body rim seamlessly).
        let topRing = outline(1)
        let faceStart = positions.count
        let shrink: [Float] = [1, 0.72, 0.44, 0.18]
        for s in shrink {
            for p in topRing {
                let q = SIMD2(p.x * s, zT + (p.y - zT) * s)
                positions.append(lift(q, height, 1))
                uvs.append(SIMD2((q.x + hwT) / (2 * hwT), (q.y - zT + hdT) / (2 * hdT)))
            }
        }
        for k in 0..<(shrink.count - 1) { bridge(faceStart + k * count, faceStart + (k + 1) * count, into: &face) }
        let centre = Int32(positions.count)
        positions.append(lift(SIMD2(0, zT), height, 1)); uvs.append(SIMD2(0.5, 0.5))
        let last = faceStart + (shrink.count - 1) * count
        for i in 0..<count { face += [Int32(last + i), centre, Int32(last + (i + 1) % count)] }

        let geo = assemble(positions, uvs, [body, face])
        cacheLock.lock()
        geometryCache[key] = (geo, top)
        cacheLock.unlock()
        return (instantiate(geo), top)
    }

    /// The rotary knob: smooth CNC satin cylinder with a chamfered outer rim and shallow center dish.
    static func knob(radius: Float, height: Float) -> SCNGeometry {
        let segments = 96
        let profile: [(Float, Float)] = [
            (radius * 0.985, 0),
            (radius, 0.014),
            (radius, height - 0.022),
            (radius * 0.985, height - 0.008),
            (radius * 0.955, height),
            (radius * 0.84, height),
            (radius * 0.80, height - 0.004),
            (radius * 0.65, height - 0.008),
            (0.001, height - 0.010),
        ]
        var positions = [SIMD3<Float>](), uvs = [SIMD2<Float>](), indices = [Int32]()
        for (r, y) in profile {
            for i in 0..<segments {
                let a = Float(i) / Float(segments) * 2 * .pi
                positions.append(SIMD3(r * cos(a), y, r * sin(a)))
                uvs.append(SIMD2(0.5 + 0.5 * (r / radius) * cos(a), 0.5 + 0.5 * (r / radius) * sin(a)))
            }
        }
        for k in 0..<(profile.count - 1) {
            for i in 0..<segments {
                let a = Int32(k * segments + i), b = Int32(k * segments + (i + 1) % segments)
                let d = Int32((k + 1) * segments + i), c = Int32((k + 1) * segments + (i + 1) % segments)
                indices += [a, d, b, b, d, c]
            }
        }
        return assemble(positions, uvs, [indices])
    }

    /// Builds a geometry with smooth normals (vertices at the same position share one normal).
    static func assemble(_ positions: [SIMD3<Float>], _ uvs: [SIMD2<Float>], _ elements: [[Int32]]) -> SCNGeometry {
        var welded = [SIMD3<Int32>: SIMD3<Float>]()
        welded.reserveCapacity(positions.count / 2)
        func key(_ p: SIMD3<Float>) -> SIMD3<Int32> { SIMD3(Int32((p.x * 4000).rounded()), Int32((p.y * 4000).rounded()), Int32((p.z * 4000).rounded())) }
        for indices in elements {
            for t in stride(from: 0, to: indices.count, by: 3) {
                let a = positions[Int(indices[t])], b = positions[Int(indices[t + 1])], c = positions[Int(indices[t + 2])]
                let n = simd_cross(b - a, c - a)
                welded[key(a), default: .zero] += n
                welded[key(b), default: .zero] += n
                welded[key(c), default: .zero] += n
            }
        }
        var normals = [SIMD3<Float>]()
        normals.reserveCapacity(positions.count)
        for p in positions {
            let n = welded[key(p)] ?? SIMD3(0, 1, 0)
            normals.append(simd_length(n) > 0 ? simd_normalize(n) : SIMD3(0, 1, 0))
        }
        let vData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let vSrc = SCNGeometrySource(
            data: vData,
            semantic: .vertex,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let nData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let nSrc = SCNGeometrySource(
            data: nData,
            semantic: .normal,
            vectorCount: normals.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let tData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let tSrc = SCNGeometrySource(
            data: tData,
            semantic: .texcoord,
            vectorCount: uvs.count,
            usesFloatComponents: true,
            componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD2<Float>>.stride
        )
        return SCNGeometry(sources: [vSrc, nSrc, tSrc], elements: elements.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
    }
}
