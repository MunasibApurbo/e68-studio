import SceneKit
import AppKit
import CoreText
import simd

/// Procedural CNC-machined 3D model for the Apple Mac mini M4 (127 × 127 × 50 mm):
/// seamless bead-blasted unibody shell with micro-filleted top edge and tucked under-belly,
/// recessed dark thermal pedestal base, flush obsidian Apple logo inlay, true recessed front
/// I/O (2× vertical USB-C ports, flush status LED, 3.5 mm headphone jack), and rear I/O bay.
enum MacMiniModel {

    // MARK: - Dimensions (1 u = 19.05 mm)

    static let width: Float = 6.67        // 127.0 mm
    static let depth: Float = 6.67        // 127.0 mm
    static let totalH: Float = 2.625      // 50.0 mm
    static let cornerR: Float = 1.18      // 22.5 mm plan corner radius

    static let footLift: Float = 0.14     // 2.7 mm floating shadow undercut
    static let wallBotY: Float = 0.44     // top of tucked aluminum under-belly
    static let wallTopY: Float = 2.56     // start of top 1.24 mm CNC micro-fillet
    static let topFilletR: Float = 0.065
    static let bellyInset: Float = 0.40

    static let halfW: Float = width / 2
    static let halfD: Float = depth / 2
    static let xFlat: Float = halfW - cornerR
    static let zFlat: Float = halfD - cornerR

    // Front I/O layout (verified against user hardware photos: vertical USB-C pair on left,
    // tiny flush white LED + 3.5 mm headphone jack on right, at ~31.5% up the aluminum fascia).
    static let portY: Float = 0.92
    static let usbX: [Float] = [-1.88, -1.10]
    static let ledX: Float = 1.22
    static let jackX: Float = 1.88

    private static let uvScale: Float = 2.6

    // MARK: - Build Entry

    static func build(into mini: SCNNode) {
        let tex = DeskTextures.macMiniAluminum()

        let aluMat = SCNMaterial()
        aluMat.lightingModel = .physicallyBased
        aluMat.diffuse.contents = tex.diffuse
        aluMat.diffuse.wrapS = .repeat
        aluMat.diffuse.wrapT = .repeat
        aluMat.diffuse.mipFilter = .linear
        aluMat.diffuse.maxAnisotropy = 8
        aluMat.roughness.contents = tex.roughness
        aluMat.roughness.wrapS = .repeat
        aluMat.roughness.wrapT = .repeat
        aluMat.normal.contents = tex.normal
        aluMat.normal.wrapS = .repeat
        aluMat.normal.wrapT = .repeat
        aluMat.normal.intensity = 0.16
        aluMat.metalness.contents = 0.88

        let bodyGeo = buildUnibodyGeometry()
        bodyGeo.materials = [aluMat]
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.castsShadow = true
        mini.addChildNode(bodyNode)

        buildThermalBase(into: mini)
        buildTopAppleLogo(into: mini)
        buildFrontPortHardware(into: mini)
        buildRearIOHardware(into: mini)
    }

    // MARK: - Front & Rear Cutout Specs

    struct CutoutTile {
        let cx: Float
        let cy: Float
        let xMin: Float
        let xMax: Float
        let yMin: Float
        let yMax: Float
        let outerHW: Float
        let outerHH: Float
        let outerR: Float
        let innerHW: Float
        let innerHH: Float
        let innerR: Float
        let chamferDepth: Float
    }

    private static let frontYMin: Float = 0.62
    private static let frontYMax: Float = 1.22

    private static let frontTiles: [CutoutTile] = [
        // Left vertical USB-C #1
        CutoutTile(cx: usbX[0], cy: portY, xMin: -2.04, xMax: -1.72, yMin: frontYMin, yMax: frontYMax,
                   outerHW: 0.088, outerHH: 0.242, outerR: 0.088,
                   innerHW: 0.070, innerHH: 0.224, innerR: 0.070, chamferDepth: 0.022),
        // Left vertical USB-C #2
        CutoutTile(cx: usbX[1], cy: portY, xMin: -1.26, xMax: -0.94, yMin: frontYMin, yMax: frontYMax,
                   outerHW: 0.088, outerHH: 0.242, outerR: 0.088,
                   innerHW: 0.070, innerHH: 0.224, innerR: 0.070, chamferDepth: 0.022),
        // Flush white status LED pinhole
        CutoutTile(cx: ledX, cy: portY, xMin: 1.12, xMax: 1.32, yMin: frontYMin, yMax: frontYMax,
                   outerHW: 0.022, outerHH: 0.022, outerR: 0.022,
                   innerHW: 0.018, innerHH: 0.018, innerR: 0.018, chamferDepth: 0.004),
        // Right 3.5 mm headphone jack
        CutoutTile(cx: jackX, cy: portY, xMin: 1.70, xMax: 2.06, yMin: frontYMin, yMax: frontYMax,
                   outerHW: 0.114, outerHH: 0.114, outerR: 0.114,
                   innerHW: 0.094, innerHH: 0.094, innerR: 0.094, chamferDepth: 0.020),
    ]

    private static let rearYMin: Float = 0.56
    private static let rearYMax: Float = 1.42
    static let rearBayTile = CutoutTile(
        cx: 0, cy: 0.99, xMin: -2.06, xMax: 2.06, yMin: rearYMin, yMax: rearYMax,
        outerHW: 2.02, outerHH: 0.40, outerR: 0.12,
        innerHW: 1.98, innerHH: 0.36, innerR: 0.10, chamferDepth: 0.040
    )

    // MARK: - Seamless Unibody Mesh

    private struct VertexBuilder {
        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [Int32]()

        mutating func add(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>) -> Int32 {
            let idx = Int32(positions.count)
            positions.append(p)
            normals.append(n)
            uvs.append(uv)
            return idx
        }

        mutating func quad(_ a: Int32, _ b: Int32, _ c: Int32, _ d: Int32) {
            indices += [a, d, b, b, d, c]
        }

        func buildGeometry() -> SCNGeometry {
            let vSrc = SCNGeometrySource(
                data: positions.withUnsafeBufferPointer { Data(buffer: $0) },
                semantic: .vertex,
                vectorCount: positions.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD3<Float>>.stride
            )
            let nSrc = SCNGeometrySource(
                data: normals.withUnsafeBufferPointer { Data(buffer: $0) },
                semantic: .normal,
                vectorCount: normals.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD3<Float>>.stride
            )
            let tSrc = SCNGeometrySource(
                data: uvs.withUnsafeBufferPointer { Data(buffer: $0) },
                semantic: .texcoord,
                vectorCount: uvs.count,
                usesFloatComponents: true,
                componentsPerVector: 2,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD2<Float>>.stride
            )
            let elem = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            return SCNGeometry(sources: [vSrc, nSrc, tSrc], elements: [elem])
        }
    }

    private struct PerimeterPoint {
        let x: Float
        let z: Float
        let nx: Float
        let nz: Float
        let arc: Float
    }

    private static func buildUnibodyGeometry() -> SCNGeometry {
        var mesh = VertexBuilder()
        let cornerSegs = 20
        let tileSegs = 10

        // Shared X stops along the front (+Z, descending +xFlat -> -xFlat) and rear (-Z, ascending -xFlat -> +xFlat)
        // so the top fillet, bottom belly, and holed fascia connect with zero T-junctions.
        var frontXStops: [Float] = [xFlat]
        for tile in frontTiles.reversed() {
            for s in 0...tileSegs {
                frontXStops.append(tile.xMax - Float(s) / Float(tileSegs) * (tile.xMax - tile.xMin))
            }
        }
        frontXStops.append(-xFlat)

        var rearXStops: [Float] = [-xFlat]
        for s in 0...tileSegs {
            rearXStops.append(rearBayTile.xMin + Float(s) / Float(tileSegs) * (rearBayTile.xMax - rearBayTile.xMin))
        }
        rearXStops.append(xFlat)

        // Generates one horizontal closed perimeter loop at the given wall inset.
        func perimeterLoop(inset: Float) -> [PerimeterPoint] {
            let r = max(0.01, cornerR - inset)
            let hw = halfW - inset
            let hd = halfD - inset
            var raw = [(x: Float, z: Float, nx: Float, nz: Float)]()

            // Interior arc points only (1 ..< cornerSegs); adjacent straight walls supply exact tangent endpoints.
            func arc(cx: Float, cz: Float, startAngle: Float, endAngle: Float) {
                for i in 1..<cornerSegs {
                    let a = startAngle + Float(i) / Float(cornerSegs) * (endAngle - startAngle)
                    let ca = cos(a), sa = sin(a)
                    raw.append((cx + r * ca, cz + r * sa, ca, sa))
                }
            }

            // c=0: Right-front corner (0 .. π/2)
            arc(cx: xFlat, cz: zFlat, startAngle: 0, endAngle: .pi / 2)
            // Front straight wall (+xFlat -> -xFlat at z = +hd)
            for x in frontXStops { raw.append((x, hd, 0, 1)) }
            // c=1: Left-front corner (π/2 .. π)
            arc(cx: -xFlat, cz: zFlat, startAngle: .pi / 2, endAngle: .pi)
            // Left straight wall (+zFlat -> -zFlat at x = -hw)
            for z in [zFlat, 0, -zFlat] { raw.append((-hw, z, -1, 0)) }
            // c=2: Left-back corner (π .. 3π/2)
            arc(cx: -xFlat, cz: -zFlat, startAngle: .pi, endAngle: 1.5 * .pi)
            // Rear straight wall (-xFlat -> +xFlat at z = -hd)
            for x in rearXStops { raw.append((x, -hd, 0, -1)) }
            // c=3: Right-back corner (3π/2 .. 2π)
            arc(cx: xFlat, cz: -zFlat, startAngle: 1.5 * .pi, endAngle: 2 * .pi)
            // Right straight wall (-zFlat -> +zFlat at x = +hw)
            for z in [-zFlat, 0, zFlat] { raw.append((hw, z, 1, 0)) }

            var out = [PerimeterPoint]()
            var arcLen: Float = 0
            for (idx, p) in raw.enumerated() {
                if idx > 0 {
                    let prev = raw[idx - 1]
                    arcLen += hypot(p.x - prev.x, p.z - prev.z)
                }
                out.append(PerimeterPoint(x: p.x, z: p.z, nx: p.nx, nz: p.nz, arc: arcLen))
            }
            return out
        }

        // Emits a ring of vertices for a profile slice (inset, y, nr, ny).
        func emitRing(inset: Float, y: Float, nr: Float, ny: Float, vCoord: Float? = nil) -> [Int32] {
            let pts = perimeterLoop(inset: inset)
            let v = vCoord ?? (y / uvScale)
            return pts.map { p in
                let n = simd_normalize(SIMD3<Float>(p.nx * nr, ny, p.nz * nr))
                return mesh.add(SIMD3(p.x, y, p.z), n, SIMD2(p.arc / uvScale, v))
            }
        }

        func bridgeRings(_ lower: [Int32], _ upper: [Int32]) {
            let n = lower.count
            for i in 0..<n {
                let next = (i + 1) % n
                mesh.quad(lower[i], lower[next], upper[next], upper[i])
            }
        }

        // 1. Underside lip (y = footLift) -> tucked bottom belly (y = 0.14 .. 0.44)
        let innerBottomLip = emitRing(inset: 1.02, y: footLift, nr: 0, ny: -1)
        let bellySteps = 7
        var bellyRings = [[Int32]]()
        for s in 0...bellySteps {
            let theta = Float(s) / Float(bellySteps) * (.pi / 2)
            let inset = bellyInset * (1 - sin(theta))
            let y = footLift + (wallBotY - footLift) * (1 - cos(theta))
            let nr = (wallBotY - footLift) * sin(theta)
            let ny = -bellyInset * cos(theta)
            let len = max(hypot(nr, ny), 1e-5)
            bellyRings.append(emitRing(inset: inset, y: y, nr: nr / len, ny: ny / len))
        }
        bridgeRings(innerBottomLip, bellyRings[0])
        for k in 0..<bellySteps { bridgeRings(bellyRings[k], bellyRings[k + 1]) }

        // 2. Vertical side walls & 4 rounded corners between wallBotY and wallTopY
        //    (The flat front and rear spans are skipped here and filled with holed CNC fascias.)
        let wallBotRing = bellyRings.last!
        let wallTopRing = emitRing(inset: 0, y: wallTopY, nr: 1, ny: 0)
        let nPerim = wallBotRing.count

        // Identify exact index spans of the flat front (+xFlat -> -xFlat) and rear (-xFlat -> +xFlat) walls.
        let cornerInterior = cornerSegs - 1
        let frontStartIdx = cornerInterior
        let frontEndIdx = frontStartIdx + frontXStops.count - 1
        let rearStartIdx = frontEndIdx + 1 + cornerInterior + 3 + cornerInterior
        let rearEndIdx = rearStartIdx + rearXStops.count - 1

        for i in 0..<nPerim {
            let next = (i + 1) % nPerim
            let inFront = (i >= frontStartIdx && i < frontEndIdx)
            let inRear = (i >= rearStartIdx && i < rearEndIdx)
            if !inFront && !inRear {
                mesh.quad(wallBotRing[i], wallBotRing[next], wallTopRing[next], wallTopRing[i])
            }
        }

        // 3. Top CNC micro-fillet (y = wallTopY .. totalH)
        let filletSteps = 5
        var filletRings = [wallTopRing]
        for s in 1...filletSteps {
            let phi = Float(s) / Float(filletSteps) * (.pi / 2)
            let inset = topFilletR * (1 - cos(phi))
            let y = wallTopY + topFilletR * sin(phi)
            filletRings.append(emitRing(inset: inset, y: y, nr: cos(phi), ny: sin(phi)))
        }
        for k in 0..<filletSteps { bridgeRings(filletRings[k], filletRings[k + 1]) }

        // 4. Seamless flat top deck (exact (0, 1, 0) normal, planar UVs at identical physical scale)
        let topEdgePts = perimeterLoop(inset: topFilletR)
        var topDeckOuter = [Int32]()
        var topDeckInner = [Int32]()
        for p in topEdgePts {
            topDeckOuter.append(mesh.add(
                SIMD3(p.x, totalH, p.z),
                SIMD3(0, 1, 0),
                SIMD2(p.x / uvScale + 0.5, p.z / uvScale + 0.5)
            ))
            topDeckInner.append(mesh.add(
                SIMD3(p.x * 0.45, totalH, p.z * 0.45),
                SIMD3(0, 1, 0),
                SIMD2(p.x * 0.45 / uvScale + 0.5, p.z * 0.45 / uvScale + 0.5)
            ))
        }
        let topCenter = mesh.add(SIMD3(0, totalH, 0), SIMD3(0, 1, 0), SIMD2(0.5, 0.5))
        for i in 0..<nPerim {
            let next = (i + 1) % nPerim
            mesh.quad(topDeckOuter[i], topDeckOuter[next], topDeckInner[next], topDeckInner[i])
            mesh.indices += [topCenter, topDeckInner[next], topDeckInner[i]]
        }

        // 5. Front & rear holed CNC fascias
        addHoledFascia(
            tiles: frontTiles, yBot: wallBotY, yTop: wallTopY,
            yTileMin: frontYMin, yTileMax: frontYMax,
            zFace: halfD, zSign: 1, tileSegs: tileSegs, into: &mesh
        )
        addHoledFascia(
            tiles: [rearBayTile], yBot: wallBotY, yTop: wallTopY,
            yTileMin: rearYMin, yTileMax: rearYMax,
            zFace: -halfD, zSign: -1, tileSegs: tileSegs, into: &mesh
        )

        return mesh.buildGeometry()
    }

    // MARK: - Holed Fascia Generator (Zero T-Junctions, Real Inward Chamfers)

    private static func addHoledFascia(
        tiles: [CutoutTile],
        yBot: Float, yTop: Float,
        yTileMin: Float, yTileMax: Float,
        zFace: Float, zSign: Float,
        tileSegs: Int,
        into mesh: inout VertexBuilder
    ) {
        let faceNormal = SIMD3<Float>(0, 0, zSign)
        func uv(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(x / uvScale + 0.5, y / uvScale) }
        func emitFlatQuad(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float) {
            let a = mesh.add(SIMD3(x0, y0, zFace), faceNormal, uv(x0, y0))
            let b = mesh.add(SIMD3(x1, y0, zFace), faceNormal, uv(x1, y0))
            let c = mesh.add(SIMD3(x1, y1, zFace), faceNormal, uv(x1, y1))
            let d = mesh.add(SIMD3(x0, y1, zFace), faceNormal, uv(x0, y1))
            if zSign > 0 {
                // +Z outward winding: (c - b) x (a - b) = +Y x (-X) = +Z
                mesh.quad(b, a, d, c)
            } else {
                // -Z outward winding: (d - a) x (b - a) = +Y x +X = -Z
                mesh.quad(a, b, c, d)
            }
        }

        // Top and bottom full-width bands partitioned at exact tile boundaries (subdivided across tile spans)
        var xBounds: [Float] = [-xFlat]
        for tile in tiles {
            xBounds.append(tile.xMin)
            xBounds.append(tile.xMax)
        }
        xBounds.append(xFlat)

        for idx in 0..<(xBounds.count - 1) {
            let xl = xBounds[idx], xr = xBounds[idx + 1]
            let isTileSpan = tiles.contains { abs($0.xMin - xl) < 1e-4 && abs($0.xMax - xr) < 1e-4 }
            let cols = isTileSpan ? tileSegs : 1
            for s in 0..<cols {
                let x0 = xl + Float(s) / Float(cols) * (xr - xl)
                let x1 = xl + Float(s + 1) / Float(cols) * (xr - xl)
                emitFlatQuad(x0, x1, yBot, yTileMin)
                emitFlatQuad(x0, x1, yTileMax, yTop)
            }
        }

        // Vertical filler strips between tiles across [yTileMin, yTileMax] (matched to tileSegs rows)
        var gapSpans: [(Float, Float)] = [(-xFlat, tiles.first!.xMin)]
        for i in 0..<(tiles.count - 1) {
            gapSpans.append((tiles[i].xMax, tiles[i + 1].xMin))
        }
        gapSpans.append((tiles.last!.xMax, xFlat))

        for (xl, xr) in gapSpans where xr - xl > 1e-5 {
            for r in 0..<tileSegs {
                let y0 = yTileMin + Float(r) / Float(tileSegs) * (yTileMax - yTileMin)
                let y1 = yTileMin + Float(r + 1) / Float(tileSegs) * (yTileMax - yTileMin)
                emitFlatQuad(xl, xr, y0, y1)
            }
        }

        // Tile rings + inward CNC chamfers
        for tile in tiles {
            addCutoutTile(tile, zFace: zFace, zSign: zSign, segs: tileSegs, into: &mesh)
        }
    }

    private static func addCutoutTile(
        _ tile: CutoutTile,
        zFace: Float, zSign: Float,
        segs: Int,
        into mesh: inout VertexBuilder
    ) {
        let faceNormal = SIMD3<Float>(0, 0, zSign)
        func uv(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(x / uvScale + 0.5, y / uvScale) }

        // Counter-clockwise boundary loop in (x, y) around the tile rectangle
        var rectPts = [(Float, Float)]()
        for i in 0..<segs {
            rectPts.append((tile.xMax, tile.yMin + Float(i) / Float(segs) * (tile.yMax - tile.yMin)))
        }
        for i in 0..<segs {
            rectPts.append((tile.xMax - Float(i) / Float(segs) * (tile.xMax - tile.xMin), tile.yMax))
        }
        for i in 0..<segs {
            rectPts.append((tile.xMin, tile.yMax - Float(i) / Float(segs) * (tile.yMax - tile.yMin)))
        }
        for i in 0..<segs {
            rectPts.append((tile.xMin + Float(i) / Float(segs) * (tile.xMax - tile.xMin), tile.yMin))
        }

        let n = rectPts.count
        var rectIdx = [Int32]()
        var mouthIdx = [Int32]()
        var chamferOuterIdx = [Int32]()
        var chamferInnerIdx = [Int32]()

        let zDeep = zFace - zSign * tile.chamferDepth
        let bevelW = max(tile.outerHW - tile.innerHW, 1e-4)

        for (px, py) in rectPts {
            let dir = simd_normalize(SIMD2<Float>(px - tile.cx, py - tile.cy))
            let (ox, oy, n2d) = intersectRoundedRect(cx: tile.cx, cy: tile.cy, dir: dir,
                                                     hw: tile.outerHW, hh: tile.outerHH, cr: tile.outerR)
            let (ix, iy, _) = intersectRoundedRect(cx: tile.cx, cy: tile.cy, dir: dir,
                                                   hw: tile.innerHW, hh: tile.innerHH, cr: tile.innerR)

            rectIdx.append(mesh.add(SIMD3(px, py, zFace), faceNormal, uv(px, py)))
            mouthIdx.append(mesh.add(SIMD3(ox, oy, zFace), faceNormal, uv(ox, oy)))

            let chamferN = simd_normalize(SIMD3<Float>(-n2d.x * tile.chamferDepth, -n2d.y * tile.chamferDepth, zSign * bevelW))
            chamferOuterIdx.append(mesh.add(SIMD3(ox, oy, zFace), chamferN, uv(ox, oy)))
            chamferInnerIdx.append(mesh.add(SIMD3(ix, iy, zDeep), chamferN, uv(ix, iy)))
        }

        for i in 0..<n {
            let next = (i + 1) % n
            if zSign > 0 {
                // +Z face: CCW rectIdx -> mouthIdx outward
                mesh.indices += [rectIdx[i], rectIdx[next], mouthIdx[i], mouthIdx[i], rectIdx[next], mouthIdx[next]]
                mesh.indices += [chamferOuterIdx[i], chamferOuterIdx[next], chamferInnerIdx[i],
                                 chamferInnerIdx[i], chamferOuterIdx[next], chamferInnerIdx[next]]
            } else {
                // -Z face: reverse winding
                mesh.indices += [rectIdx[i], mouthIdx[i], rectIdx[next], mouthIdx[i], mouthIdx[next], rectIdx[next]]
                mesh.indices += [chamferOuterIdx[i], chamferInnerIdx[i], chamferOuterIdx[next],
                                 chamferInnerIdx[i], chamferInnerIdx[next], chamferOuterIdx[next]]
            }
        }
    }

    /// Ray-intersects a centered rounded rectangle (`2*hw × 2*hh`, corner radius `cr`) along unit vector `dir`.
    private static func intersectRoundedRect(
        cx: Float, cy: Float, dir: SIMD2<Float>,
        hw: Float, hh: Float, cr: Float
    ) -> (x: Float, y: Float, normal: SIMD2<Float>) {
        let ax = abs(dir.x), ay = abs(dir.y)
        let ix = max(0, hw - cr), iy = max(0, hh - cr)
        let sx: Float = dir.x >= 0 ? 1 : -1
        let sy: Float = dir.y >= 0 ? 1 : -1

        if ax > 1e-6 {
            let tx = hw / ax
            if tx * ay <= iy {
                return (cx + dir.x * tx, cy + dir.y * tx, SIMD2(sx, 0))
            }
        }
        if ay > 1e-6 {
            let ty = hh / ay
            if ty * ax <= ix {
                return (cx + dir.x * ty, cy + dir.y * ty, SIMD2(0, sy))
            }
        }
        let b = ax * ix + ay * iy
        let c = ix * ix + iy * iy - cr * cr
        let t = b + sqrt(max(0, b * b - c))
        let lx = ax * t - ix
        let ly = ay * t - iy
        let n2 = simd_normalize(SIMD2<Float>(lx * sx, ly * sy))
        return (cx + dir.x * t, cy + dir.y * t, n2)
    }
}
