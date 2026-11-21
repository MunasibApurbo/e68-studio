import Foundation
import SceneKit
import Metal
import simd

// MARK: - Baked Light Cache Tables

/// One entry per triangle of every instance. `res` splits the triangle into a res x res barycentric grid
/// whose (res+1)(res+2)/2 corner points each store the soft light arriving there; triangles smaller than
/// a grid cell store it at their vertices instead.
struct RTLightCacheTri {
    var sampleBase: UInt32
    var res: UInt32
    var instance: UInt32
    var geomPrim: UInt32   // geometry index in the top 8 bits, primitive index in the low 24

    /// Set in `res` when the triangle's three points live in its instance's shared per-vertex block.
    static let perVertex: UInt32 = 0x8000_0000
}

extension RTSceneExtractor {
    /// Lays out where baked lighting is stored. The desk never changes shape, so the soft part of its
    /// lighting (shadows from area lights, light bounced between surfaces) can be worked out once per
    /// lighting setup and looked up every frame, instead of being re-estimated from noisy rays.
    /// Storage follows the triangles themselves, so no mesh needs lightmap UVs: fine grids near the
    /// desk, coarser ones on distant terrain.
    func buildLightCacheTables() {
        var submeshCountByBase = [UInt32: UInt32]()
        for entry in geometryCache.values { submeshCountByBase[entry.submeshBase] = entry.submeshCount }

        struct PendingTri {
            var instance: UInt32
            var geomPrim: UInt32
            var longestEdge: Float
            var distance: Float
            var cached: Bool
            var indexStart: Int
            var vertexOffset: UInt32
            var ng: SIMD3<Float>
            var nearDesk: Bool
            var nearMouseBase: Bool
            var underDesk: Bool
        }
        let deskCenter = SIMD3<Float>(2.4, 0, -4)
        let isRoomOrGround: [Bool] = trackedInstances.map { inst in
            var cur: SCNNode? = inst.node
            while let n = cur {
                if n.name == "env.room.root" || n.name == DeskScenarios.photoGroundName { return true }
                cur = n.parent
            }
            return false
        }
        var pending = [PendingTri]()
        pending.reserveCapacity(indices.count / 3 + 1024)
        var instGeom = [UInt32]()
        // How many vertices each instance's mesh spans, for the per-vertex storage small triangles share.
        var vertexSpan = [Int](repeating: 0, count: instanceInfos.count)
        var maxEdgeByInst = [Float](repeating: 0, count: instanceInfos.count)
        var triCountByInst = [Int](repeating: 0, count: instanceInfos.count)

        for i in instanceInfos.indices {
            let base = instanceInfos[i].submeshBase
            let count = submeshCountByBase[base] ?? 1
            instanceInfos[i].reserved = UInt32(instGeom.count)
            let m = instanceInfos[i].modelToWorld
            let mirrored = (instanceInfos[i].flags & RTInstanceFlags.mirroredDet) != 0
            for g in 0..<count {
                let subIdx = Int(base + g)
                instGeom.append(UInt32(pending.count))
                guard subIdx < submeshes.count else { continue }
                let sub = submeshes[subIdx]
                let triCount = Int(nextIndexOffsetForSubmesh(subIdx) - sub.indexOffset) / 3
                let mat = Int(sub.materialIndex) < materials.count ? materials[Int(sub.materialIndex)] : makeDefaultMaterial()
                // Glow cards and unlit emitters are drawn from their own colour; they need no stored light.
                let cached = mat.extraTex.z != RTMatClass.emissiveCard.rawValue && (mat.extraTex.w & RTMatFlags.isUnlitConstant) == 0
                for t in 0..<triCount {
                    let o = Int(sub.indexOffset) + t * 3
                    func worldPos(_ k: Int) -> SIMD3<Float> {
                        vertexSpan[i] = max(vertexSpan[i], Int(indices[o + k]) + 1)
                        let v = vertices[Int(indices[o + k] + sub.vertexOffset)]
                        let w = m * SIMD4<Float>(v.px, v.py, v.pz, 1)
                        return SIMD3<Float>(w.x, w.y, w.z)
                    }
                    let a = worldPos(0), b = worldPos(1), c = worldPos(2)
                    let cross = simd_cross(b - a, c - a)
                    let crossLen = simd_length(cross)
                    var ng = crossLen > 1e-8 ? (cross / crossLen) : SIMD3<Float>(0, 1, 0)
                    if mirrored { ng = -ng }
                    // Side of the square with the triangle's area: sizes the grid by surface covered, so long
                    // thin slivers (cables, lamp arms, bezels) do not claim a point budget their area never needs.
                    let edge = crossLen.squareRoot()
                    maxEdgeByInst[i] = max(maxEdgeByInst[i], edge)
                    triCountByInst[i] += 1
                    let center = (a + b + c) / 3
                    let dist = simd_length(center - deskCenter)
                    let nearDesk = abs(center.x - 2.4) < 26 && center.z > -16 && center.z < 11 && center.y > 0.0 && center.y < 10
                    let nearMouseBase = center.y > 0.0 && center.y < 0.70 && abs(center.x - 12.6) < 2.6 && abs(center.z + 0.6) < 4.2
                    let underDesk = center.y < -0.25
                    pending.append(PendingTri(instance: UInt32(i), geomPrim: (g << 24) | UInt32(t & 0xFFFFFF),
                                              longestEdge: edge, distance: dist, cached: cached,
                                              indexStart: o, vertexOffset: sub.vertexOffset, ng: ng, nearDesk: nearDesk, nearMouseBase: nearMouseBase, underDesk: underDesk))
                }
            }
        }

        // Dense curved shells (e.g. mouse body) keep uniform per-vertex storage so adjacent triangles never
        // straddle the res=1 / res=2 boundary into sawtooth seams along lower silhouette edges.
        let forcePerVertex = instanceInfos.indices.map {
            triCountByInst[$0] >= 200 && maxEdgeByInst[$0] < 0.35
        }

        // Grid spacing: finer (~2 mm) near the desk surface for crisp contact shadows and curved shells,
        // ~4 mm mid-ground, and coarser on distant terrain. Triangles smaller than one cell keep light at their
        // vertices, shared with their neighbours. If the scene would overshoot the budget, coarsen and retry.
        let sampleBudget = 3_000_000
        var cell: Float = 0.2
        var resolutions = [UInt32](repeating: 0, count: pending.count)
        var usesVertices = [Bool](repeating: false, count: instanceInfos.count)
        var total = 0
        while true {
            total = 0
            for k in usesVertices.indices { usesVertices[k] = false }
            for (n, tri) in pending.enumerated() {
                guard tri.cached else { resolutions[n] = 0; continue }
                let instIdx = Int(tri.instance)
                let res: UInt32
                if forcePerVertex[instIdx] {
                    res = 1
                } else {
                    // Distant terrain and room shell/floor use coarser base spacing (0.5), keeping 0.2 within ~30u of desk centre.
                    let spacing: Float
                    if tri.nearMouseBase {
                        spacing = cell * 0.25
                    } else if tri.nearDesk {
                        spacing = cell * 1.05
                    } else if isRoomOrGround[instIdx] {
                        spacing = tri.distance <= 30.0
                            ? cell
                            : (cell * 2.5) * pow(max(1, tri.distance / 36.0), 1.65)
                    } else if tri.underDesk {
                        spacing = (cell * 2.75) * pow(max(1, tri.distance / 30.0), 1.65)
                    } else {
                        spacing = (cell * 2.0) * pow(max(1, tri.distance / 30.0), 1.65)
                    }
                    res = UInt32(min(max((tri.longestEdge / spacing).rounded(.up), 1), 420))
                }
                resolutions[n] = res
                if res == 1 {
                    usesVertices[instIdx] = true
                } else {
                    total += Int((res + 1) * (res + 2) / 2)
                }
            }
            for k in usesVertices.indices where usesVertices[k] { total += vertexSpan[k] }
            if total <= sampleBudget { break }
            cell *= 1.2
        }

        // Per-vertex blocks first, then the per-triangle grids.
        var vertexBlock = [Int](repeating: 0, count: instanceInfos.count)
        var cursor = 0
        for k in usesVertices.indices where usesVertices[k] {
            vertexBlock[k] = cursor
            cursor += vertexSpan[k]
        }
        // Each stored point records a triangle it lies on (and, for vertex points, which corner in the top
        // two bits) so the bake can find its position and normal. Vertex slots nothing uses stay unbaked.
        // Prefer upward/outward triangles aligned with the vertex normal so underside caps do not poison seams.
        var sampleTri = [UInt32](repeating: 0xFFFF_FFFF, count: max(total, 1))
        var bestVertexScore = [Float](repeating: -Float.greatestFiniteMagnitude, count: max(cursor, 1))
        var tris = [RTLightCacheTri]()
        tris.reserveCapacity(pending.count)
        for (n, tri) in pending.enumerated() {
            let res = resolutions[n]
            if res == 1 {
                let instIdx = Int(tri.instance)
                let block = vertexBlock[instIdx]
                let nm4 = instanceInfos[instIdx].normalToWorld
                let nm = simd_float3x3(
                    SIMD3(nm4.columns.0.x, nm4.columns.0.y, nm4.columns.0.z),
                    SIMD3(nm4.columns.1.x, nm4.columns.1.y, nm4.columns.1.z),
                    SIMD3(nm4.columns.2.x, nm4.columns.2.y, nm4.columns.2.z)
                )
                tris.append(RTLightCacheTri(sampleBase: UInt32(block), res: RTLightCacheTri.perVertex | 1, instance: tri.instance, geomPrim: tri.geomPrim))
                for corner in 0..<3 {
                    let localIdx = Int(indices[tri.indexStart + corner])
                    let slot = block + localIdx
                    let v = vertices[localIdx + Int(tri.vertexOffset)]
                    let vwRaw = nm * SIMD3<Float>(v.nx, v.ny, v.nz)
                    let vwLen = simd_length(vwRaw)
                    let vwN = vwLen > 1e-6 ? vwRaw / vwLen : tri.ng
                    let score = simd_dot(tri.ng, vwN) + (tri.ng.y >= -0.35 ? 2.0 : 0.0)
                    if score > bestVertexScore[slot] {
                        bestVertexScore[slot] = score
                        sampleTri[slot] = UInt32(n) | (UInt32(corner) << 30)
                    }
                }
                continue
            }
            tris.append(RTLightCacheTri(sampleBase: UInt32(cursor), res: res, instance: tri.instance, geomPrim: tri.geomPrim))
            guard res > 0 else { continue }
            let count = Int((res + 1) * (res + 2) / 2)
            for k in cursor..<(cursor + count) { sampleTri[k] = UInt32(n) }
            cursor += count
        }
        if tris.isEmpty { tris.append(RTLightCacheTri(sampleBase: 0, res: 0, instance: 0, geomPrim: 0)) }
        if instGeom.isEmpty { instGeom.append(0) }

        var layoutHash: UInt64 = 0xE68C_AC4E_0002_0001
        Self.fnvMix(&layoutHash, UInt64(total))
        Self.fnvMix(&layoutHash, UInt64(tris.count))
        Self.fnvMix(&layoutHash, UInt64(instGeom.count))
        Self.fnvMix(&layoutHash, UInt64(pending.count))
        for t in tris {
            Self.fnvMix(&layoutHash, UInt64(t.sampleBase))
            Self.fnvMix(&layoutHash, UInt64(t.res) | (UInt64(t.instance) << 16))
            Self.fnvMix(&layoutHash, UInt64(t.geomPrim))
        }

        let sameLayout = lightCacheGeneration > 0
            && layoutHash == lightCacheLayoutHash
            && lightCacheSampleCount == total
            && lightCacheSampleBuffer != nil
            && lightCacheSampleCountBuffer != nil
            && lightCacheDirectionBuffer != nil
            && lightCacheDeskSampleBuffer != nil

        lightCacheInstGeomBuffer = makeBuffer(from: instGeom)
        lightCacheTriBuffer = makeBuffer(from: tris)
        lightCacheSampleTriBuffer = makeBuffer(from: sampleTri)

        if !sameLayout {
            // rgb = mean light for a white surface, stored as half floats; counts live in `lightCacheSampleCountBuffer`.
            lightCacheSampleBuffer = device.makeBuffer(length: max(total, 1) * 8, options: .storageModePrivate)
            // Per-sample estimate count (`ushort`), kept separate from half4 RGB so counts don't overflow FP16 or waste 8 B/pt.
            lightCacheSampleCountBuffer = device.makeBuffer(length: max(total, 1) * MemoryLayout<UInt16>.stride, options: .storageModePrivate)
            // xyz = brightness-weighted mean direction the light arrives from, as half floats.
            lightCacheDirectionBuffer = device.makeBuffer(length: max(total, 1) * 8, options: .storageModePrivate)
            // rgb = unit-white desk lamp irradiance (direct + 1-bounce), tinted & scaled at render time.
            lightCacheDeskSampleBuffer = device.makeBuffer(length: max(total, 1) * 8, options: .storageModePrivate)
            lightCacheSampleCount = total
            lightCacheLayoutHash = layoutHash
            lightCacheGeneration += 1
        }
        if E68Perf.enabled {
            var roomPts = 0, nearPts = 0, farPts = 0, vertPts = 0
            var vertByInst = [Int](repeating: 0, count: instanceInfos.count)
            var ptsByInst = [Int](repeating: 0, count: instanceInfos.count)
            for (n, tri) in pending.enumerated() {
                let res = resolutions[n]
                let instIdx = Int(tri.instance)
                if res > 1 {
                    let c = Int((res + 1) * (res + 2) / 2)
                    ptsByInst[instIdx] += c
                    if isRoomOrGround[instIdx] { roomPts += c }
                    else if tri.nearDesk { nearPts += c }
                    else { farPts += c }
                }
            }
            for k in usesVertices.indices where usesVertices[k] {
                ptsByInst[k] += vertexSpan[k]
                vertByInst[k] = vertexSpan[k]
                vertPts += vertexSpan[k]
            }
            E68Perf.logLine(String(format: "light cache: %d points on %d triangles, %.2f unit spacing, %.0f MB%@ [room=%d near=%d far=%d vert=%d]",
                                   total, pending.count, cell, Double(total * 30 + pending.count * 16) / 1_048_576.0,
                                   sameLayout ? " (layout unchanged, keeping samples)" : "",
                                   roomPts, nearPts, farPts, vertPts))
            let top = ptsByInst.enumerated()
                .filter { $0.element >= 5000 }
                .sorted { $0.element > $1.element }
                .prefix(20)
            for (idx, pts) in top {
                let node = trackedInstances[idx].node
                let parentName = node.parent?.name ?? "-"
                let name = node.name ?? "<unnamed:\(type(of: node.geometry as Any))>"
                let p = node.simdWorldPosition
                E68Perf.logLine(String(format: "  light cache node[%d] %@ (parent=%@ pos=%.1f,%.1f,%.1f tris=%d vert=%d): %d pts (%.1f%%)",
                                       idx, name, parentName, p.x, p.y, p.z, triCountByInst[idx], vertByInst[idx], pts, 100.0 * Double(pts) / Double(max(total, 1))))
            }
        }
    }

    static func fnvMix(_ hash: inout UInt64, _ value: UInt64) {
        hash ^= value
        hash &*= 1099511628211
    }

    static func fnvMixFloat(_ hash: inout UInt64, _ value: Float) {
        let bits = value == 0 ? 0 : value.bitPattern
        fnvMix(&hash, UInt64(bits))
    }

    static func fnvMixVec4(_ hash: inout UInt64, _ v: SIMD4<Float>) {
        fnvMixFloat(&hash, v.x)
        fnvMixFloat(&hash, v.y)
        fnvMixFloat(&hash, v.z)
        fnvMixFloat(&hash, v.w)
    }

    func computeMaterialCacheHash() -> UInt64 {
        // Only what changes how surfaces bounce light: colour, metalness, clear coat. Dynamic tracked
        // indicators (LEDs, keycap selection/overlays, screens, lamps) are excluded so toggling a
        // DPI stage or selecting a key never triggers a full light-cache re-bake.
        let dynamicIndices = Set(trackedMaterials.map(\.index))
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        Self.fnvMix(&h, UInt64(materials.count))
        for (idx, m) in materials.enumerated() where !dynamicIndices.contains(idx) {
            Self.fnvMixFloat(&h, m.baseColor.x)
            Self.fnvMixFloat(&h, m.baseColor.y)
            Self.fnvMixFloat(&h, m.baseColor.z)
            Self.fnvMixFloat(&h, m.params.x)
            Self.fnvMixFloat(&h, m.params.y)
        }
        return h
    }
}
