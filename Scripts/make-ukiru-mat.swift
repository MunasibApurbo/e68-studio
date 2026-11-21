// Builds Resources/ukiru-mat.jpg (2250x1000, 900x400 mm aspect) from Docs/Reference/desk.jpg:
// rectifies the mat, preserves the Japanese house & teal crosshatched clouds with seamless
// non-mirrored cloud continuation over occluded left/right spans, cleans all stray specks,
// removes any 2D faux-stitch border (handled in 3D by overlock rim), and bakes balanced
// warm heather-cream fabric albedo (<= 0.85 linear/sRGB) so startup requires zero pixel loops.
import AppKit
import CoreGraphics

let srcURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Docs/Reference/desk.jpg")
let outURL = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/ukiru-mat.jpg")

guard let img = NSImage(contentsOf: srcURL),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Cannot open \(srcURL.path)")
}

let SW = cg.width, SH = cg.height
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func makeCtx(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

let srcCtx = makeCtx(SW, SH)
srcCtx.draw(cg, in: CGRect(x: 0, y: 0, width: SW, height: SH))
let sPtr = srcCtx.data!.bindMemory(to: UInt8.self, capacity: SW * SH * 4)

@inline(__always)
func sampleSrc(_ fx: Double, _ fy: Double) -> (Double, Double, Double) {
    let x = min(max(fx, 0), Double(SW - 2))
    let y = min(max(fy, 0), Double(SH - 2))
    let x0 = Int(x), y0 = Int(y)
    let tx = x - Double(x0), ty = y - Double(y0)
    let i00 = (y0 * SW + x0) * 4
    let i10 = i00 + 4
    let i01 = i00 + SW * 4
    let i11 = i01 + 4
    func ch(_ c: Int) -> Double {
        let p00 = Double(sPtr[i00 + c]), p10 = Double(sPtr[i10 + c])
        let p01 = Double(sPtr[i01 + c]), p11 = Double(sPtr[i11 + c])
        return (p00 * (1 - tx) + p10 * tx) * (1 - ty) + (p01 * (1 - tx) + p11 * tx) * ty
    }
    return (ch(0), ch(1), ch(2))
}

let W = 2250, H = 1000
var buf = [Double](repeating: 0, count: W * H * 3)

func matToPhoto(_ u: Double, _ v: Double) -> (Double, Double) {
    let uu = min(u, 0.845)
    let leftX = 200.0 - 44.0 * v + 10.0 * v * v
    let rightX = 4475.0 + 35.0 * v
    let px = leftX + (rightX - leftX) * uu
    let topY = 988.0 + 38.0 * uu
    let botY = 2954.0 - 10.0 * uu
    let py = topY + (botY - topY) * v
    return (px, py)
}

for y in 0..<H {
    let v = (Double(y) + 0.5) / Double(H)
    for x in 0..<W {
        let u = (Double(x) + 0.5) / Double(W)
        let (px, py) = matToPhoto(u, v)
        let (r, g, b) = sampleSrc(px, py)
        let idx = (y * W + x) * 3
        buf[idx] = r; buf[idx + 1] = g; buf[idx + 2] = b
    }
}

// Fit smooth quadratic surface to empty cream fabric illumination across the photo
func solve(_ aIn: [[Double]], _ bIn: [Double]) -> [Double] {
    var a = aIn, b = bIn
    let n = b.count
    for i in 0..<n {
        var pivot = i
        for r in i..<n where abs(a[r][i]) > abs(a[pivot][i]) { pivot = r }
        a.swapAt(i, pivot); b.swapAt(i, pivot)
        let d = abs(a[i][i]) < 1e-9 ? 1e-9 : a[i][i]
        for r in (i + 1)..<n {
            let f = a[r][i] / d
            for c in i..<n { a[r][c] -= f * a[i][c] }
            b[r] -= f * b[i]
        }
    }
    var x = [Double](repeating: 0, count: n)
    for i in stride(from: n - 1, through: 0, by: -1) {
        var s = b[i]
        for c in (i + 1)..<n { s -= a[i][c] * x[c] }
        x[i] = s / (abs(a[i][i]) < 1e-9 ? 1e-9 : a[i][i])
    }
    return x
}

func basis(_ u: Double, _ v: Double) -> [Double] {
    let uu = u * 2 - 1, vv = v * 2 - 1
    return [1, uu, vv, uu * vv, uu * uu, vv * vv]
}

var A = [[Double]](repeating: [Double](repeating: 0, count: 6), count: 6)
var B = [[Double]](repeating: [Double](repeating: 0, count: 6), count: 3)

for y in stride(from: Int(Double(H) * 0.28), to: Int(Double(H) * 0.96), by: 6) {
    let v = (Double(y) + 0.5) / Double(H)
    for x in stride(from: Int(Double(W) * 0.03), to: Int(Double(W) * 0.84), by: 6) {
        let u = (Double(x) + 0.5) / Double(W)
        if u < 0.24 && v < 0.52 { continue }
        if u < 0.25 && v >= 0.47 { continue }
        if u > 0.19 && u < 0.62 && v > 0.42 && v < 0.82 { continue }
        if u > 0.59 && u < 0.82 && v > 0.24 { continue }
        let idx = (y * W + x) * 3
        let r = buf[idx], g = buf[idx + 1], b = buf[idx + 2]
        guard min(r, g, b) > 155, max(r, g, b) - min(r, g, b) < 28 else { continue }
        let f = basis(u, v)
        for i in 0..<6 {
            for j in 0..<6 { A[i][j] += f[i] * f[j] }
            B[0][i] += f[i] * r; B[1][i] += f[i] * g; B[2][i] += f[i] * b
        }
    }
}
let kR = solve(A, B[0]), kG = solve(A, B[1]), kB = solve(A, B[2])
func creamAt(_ u: Double, _ v: Double) -> (Double, Double, Double) {
    let f = basis(u, v)
    return (
        zip(kR, f).reduce(0) { $0 + $1.0 * $1.1 },
        zip(kG, f).reduce(0) { $0 + $1.0 * $1.1 },
        zip(kB, f).reduce(0) { $0 + $1.0 * $1.1 }
    )
}

// Target warm off-white / ivory-cream cloth (~231 sRGB ≈ 0.90 sRGB / ~0.79 linear, crisp without clipping HDR)
let targetCream: (Double, Double, Double) = (232.0, 229.0, 223.0)

// White-balance the raw clean cloud strip [620...1705] first, cleaning white AirPods tips around x in 1380..1710
for y in 132..<225 {
    for x in 1370..<1720 {
        let idx = (y * W + x) * 3
        let r = buf[idx], g = buf[idx + 1], b = buf[idx + 2]
        if min(r, g, b) > 190 || (min(r, g, b) > 144 && y > 150 && (b - r) < 11) {
            let u = (Double(x) + 0.5) / Double(W), v = (Double(y) + 0.5) / Double(H)
            let c = creamAt(u, v)
            buf[idx] = c.0; buf[idx + 1] = c.1; buf[idx + 2] = c.2
        }
    }
}

// Normalize the top cloud strip [0..<235, 0..<W] relative to photo cream lighting before patching,
// so lighting differences vanish smoothly and shifted patches maintain identical 45-deg sky hatching!
let cloudH = 235
var normCloud = [Double](repeating: 0, count: W * cloudH * 3)
for y in 0..<cloudH {
    let v = (Double(y) + 0.5) / Double(H)
    for x in 0..<W {
        let u = (Double(x) + 0.5) / Double(W)
        let localC = creamAt(u, v)
        let si = (y * W + x) * 3
        let di = (y * W + x) * 3
        normCloud[di + 0] = min(255, buf[si + 0] * targetCream.0 / max(localC.0, 1))
        normCloud[di + 1] = min(255, buf[si + 1] * targetCream.1 / max(localC.1, 1))
        normCloud[di + 2] = min(255, buf[si + 2] * targetCream.2 / max(localC.2, 1))
    }
}

// Reconstruct left pothos-occluded span (0..<595) & right Mac mini/cable-occluded span (1695..<W)
// using NON-MIRRORED translated sections of the genuine clean span [595..<1700], joined via a
// minimum-difference DP seam cut (3px edge AA) so ink strokes never ghost/double-expose, and
// keeping all sky hatching uniformly angled `\`.
var patchedCloud = normCloud

func patchWithMinCut(dstStart: Int, dstEnd: Int, srcStart: Int, cutLeftBand: Range<Int>?, cutRightBand: Range<Int>?) {
    let shift = srcStart - dstStart

    func computeSeam(_ xRange: Range<Int>) -> [Int] {
        let rw = xRange.count
        var cost = [Double](repeating: 0, count: rw * cloudH)
        for y in 0..<cloudH {
            for (rx, x) in xRange.enumerated() {
                let sx = x + shift
                let di = (y * W + x) * 3, si = (y * W + sx) * 3
                let dr = patchedCloud[di] - normCloud[si]
                let dg = patchedCloud[di + 1] - normCloud[si + 1]
                let db = patchedCloud[di + 2] - normCloud[si + 2]
                cost[y * rw + rx] = dr * dr + dg * dg + db * db
            }
        }
        var dp = [Double](repeating: 0, count: rw * cloudH)
        var back = [Int](repeating: 0, count: rw * cloudH)
        for rx in 0..<rw { dp[rx] = cost[rx] }
        for y in 1..<cloudH {
            for rx in 0..<rw {
                var best = dp[(y - 1) * rw + rx], bestCol = rx
                if rx > 0 && dp[(y - 1) * rw + rx - 1] < best {
                    best = dp[(y - 1) * rw + rx - 1]; bestCol = rx - 1
                }
                if rx + 1 < rw && dp[(y - 1) * rw + rx + 1] < best {
                    best = dp[(y - 1) * rw + rx + 1]; bestCol = rx + 1
                }
                dp[y * rw + rx] = cost[y * rw + rx] + best
                back[y * rw + rx] = bestCol
            }
        }
        var seam = [Int](repeating: xRange.lowerBound + rw / 2, count: cloudH)
        var col = (0..<rw).min { dp[(cloudH - 1) * rw + $0] < dp[(cloudH - 1) * rw + $1] } ?? (rw / 2)
        for y in stride(from: cloudH - 1, through: 0, by: -1) {
            seam[y] = xRange.lowerBound + col
            col = back[y * rw + col]
        }
        return seam
    }

    let leftSeam = cutLeftBand.map { computeSeam($0) }
    let rightSeam = cutRightBand.map { computeSeam($0) }

    for y in 0..<cloudH {
        let lx0 = cutLeftBand?.lowerBound ?? dstStart
        let lx1 = cutLeftBand?.upperBound ?? dstStart
        let rx0 = cutRightBand?.lowerBound ?? dstEnd
        let rx1 = cutRightBand?.upperBound ?? dstEnd
        let ls = leftSeam?[y] ?? dstStart
        let rs = rightSeam?[y] ?? dstEnd

        for x in max(dstStart, lx0)..<min(dstEnd, rx1) {
            var w = 1.0
            if cutLeftBand != nil && x < lx1 {
                if x < ls - 1 { w = 0.0 }
                else if x <= ls + 1 { w = Double(x - (ls - 1)) / 2.0 }
            }
            if cutRightBand != nil && x >= rx0 {
                if x > rs + 1 { w = 0.0 }
                else if x >= rs - 1 { w = min(w, Double((rs + 1) - x) / 2.0) }
            }
            let sx = x + shift
            let di = (y * W + x) * 3, si = (y * W + sx) * 3
            patchedCloud[di + 0] = patchedCloud[di + 0] * (1 - w) + normCloud[si + 0] * w
            patchedCloud[di + 1] = patchedCloud[di + 1] * (1 - w) + normCloud[si + 1] * w
            patchedCloud[di + 2] = patchedCloud[di + 2] * (1 - w) + normCloud[si + 2] * w
        }
    }
}

// Clean pastel-teal clouds on far left [0..<680], ending in clean `\` sky gap around x~670
patchWithMinCut(dstStart: 0, dstEnd: 155, srcStart: 1415, cutLeftBand: nil, cutRightBand: nil)
patchWithMinCut(dstStart: 95, dstEnd: 565, srcStart: 1185, cutLeftBand: 95..<145, cutRightBand: nil)
patchWithMinCut(dstStart: 515, dstEnd: 680, srcStart: 1275, cutLeftBand: 515..<560, cutRightBand: 635..<680)

// Clean pastel-teal clouds on far right [1655..<W] spliced across matching teal cloud interiors
patchWithMinCut(dstStart: 1655, dstEnd: 2070, srcStart: 1200, cutLeftBand: 1655..<1700, cutRightBand: nil)
patchWithMinCut(dstStart: 2020, dstEnd: W, srcStart: 1315, cutLeftBand: 2020..<2065, cutRightBand: nil)

// Extrapolate diagonal `\` hatched sky cleanly over top 24px border (removes old stitched edge)
for y in 0..<24 {
    let sy = 24
    for x in 0..<W {
        let sx = max(0, min(W - 1, x - (sy - y)))
        let di = (y * W + x) * 3, si = (sy * W + sx) * 3
        patchedCloud[di + 0] = patchedCloud[si + 0]
        patchedCloud[di + 1] = patchedCloud[si + 1]
        patchedCloud[di + 2] = patchedCloud[si + 2]
    }
}

// Write clean normalized cloud strip back into buf[0..<cloudH]
for y in 0..<cloudH {
    for x in 0..<W {
        let i = (y * W + x) * 3
        buf[i + 0] = patchedCloud[i + 0]
        buf[i + 1] = patchedCloud[i + 1]
        buf[i + 2] = patchedCloud[i + 2]
    }
}

// Flood-fill upward from y = cloudH - 1 across empty cream background inside 0..<cloudH
// so exterior pixels flush cleanly right up against the black cloud ink boundary (zero step boxes or stray specks!)
@inline(__always)
func isCloudPixel(_ idx: Int) -> Bool {
    let r = buf[idx], g = buf[idx + 1], b = buf[idx + 2]
    let luma = (r + g + b) / 3.0
    // Reject warm/brownish cable or stem fragments (`r > b + 8` when bright)
    if r > b + 8 && luma > 105 { return false }
    let chroma = max(r, max(g, b)) - min(r, min(g, b))
    return luma < 140 || (g - r) > 10 || (b - r) > 10 || chroma > 24
}

// Remove tiny disconnected dark/color islands below cloud line (e.g. stray speck u=0.71 or edge crumbs)
var cloudConnected = [Bool](repeating: false, count: W * cloudH)
var cQueue = [Int]()
cQueue.reserveCapacity(W * 80)
for y in 0..<55 {
    for x in 0..<W {
        let ci = y * W + x
        if !cloudConnected[ci] && isCloudPixel(ci * 3) {
            cloudConnected[ci] = true
            cQueue.append(ci)
        }
    }
}
var cqHead = 0
while cqHead < cQueue.count {
    let cur = cQueue[cqHead]; cqHead += 1
    let cx = cur % W, cy = cur / W
    for dy in -1...1 {
        for dx in -1...1 where dx != 0 || dy != 0 {
            let nx = cx + dx, ny = cy + dy
            guard nx >= 0, nx < W, ny >= 0, ny < cloudH else { continue }
            let ni = ny * W + nx
            guard !cloudConnected[ni] else { continue }
            if isCloudPixel(ni * 3) {
                cloudConnected[ni] = true
                cQueue.append(ni)
            }
        }
    }
}

// Distance feather around connected clouds so ink edge stays anti-aliased against clean cream weave
var isCloudBg = [Bool](repeating: false, count: W * cloudH)
var bgQueue = [Int]()
bgQueue.reserveCapacity(W * 60)
for x in 0..<W {
    let ci = (cloudH - 1) * W + x
    if !cloudConnected[ci] {
        isCloudBg[ci] = true
        bgQueue.append(ci)
    }
}
var bgHead = 0
while bgHead < bgQueue.count {
    let cur = bgQueue[bgHead]; bgHead += 1
    let cx = cur % W, cy = cur / W
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nx = cx + dx, ny = cy + dy
        guard nx >= 0, nx < W, ny >= 75, ny < cloudH else { continue }
        let ni = ny * W + nx
        guard !isCloudBg[ni], !cloudConnected[ni] else { continue }
        isCloudBg[ni] = true
        bgQueue.append(ni)
    }
}

var cloudBgBlend = [Double](repeating: 0, count: W * cloudH)
for y in 70..<cloudH {
    for x in 0..<W {
        let idx = y * W + x
        if isCloudBg[idx] {
            var nearCloud = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = min(max(x + dx, 0), W - 1), ny = min(max(y + dy, 0), cloudH - 1)
                    if !isCloudBg[ny * W + nx] { nearCloud += 1 }
                }
            }
            cloudBgBlend[idx] = nearCloud == 0 ? 1.0 : max(0.35, 1.0 - Double(nearCloud) * 0.12)
        }
    }
}

// Flood-fill outer paper around the Japanese house (x: 88...446, y: 496...924) -> clean house cutout
let hx0 = 88, hx1 = 446, hy0 = 496, hy1 = 924
let hw = hx1 - hx0 + 1, hh = hy1 - hy0 + 1
var isPaper = [Bool](repeating: false, count: hw * hh)
var visited = [Bool](repeating: false, count: hw * hh)
var queue = [Int]()

@inline(__always)
func isHouseBoundaryPixel(_ px: Int, _ py: Int) -> Bool {
    let idx = (py * W + px) * 3
    let r = buf[idx], g = buf[idx + 1], b = buf[idx + 2]
    let maxC = max(r, max(g, b)), minC = min(r, min(g, b))
    let luma = (r + g + b) / 3.0
    let chroma = maxC - minC
    let warmBias = r - b
    if luma < 118 { return true }
    if (g - r) > 4 { return true }
    if warmBias > 42 && luma < 185 { return true }
    if chroma > 46 && luma < 195 { return true }
    return false
}

for lx in 0..<hw {
    for ly in [0, hh - 1] {
        let px = hx0 + lx, py = hy0 + ly
        if !isHouseBoundaryPixel(px, py) {
            let qi = ly * hw + lx
            visited[qi] = true; isPaper[qi] = true; queue.append(qi)
        }
    }
}
for ly in 0..<hh {
    for lx in [0, hw - 1] {
        let px = hx0 + lx, py = hy0 + ly
        if !isHouseBoundaryPixel(px, py) {
            let qi = ly * hw + lx
            if !visited[qi] { visited[qi] = true; isPaper[qi] = true; queue.append(qi) }
        }
    }
}
var qHead = 0
while qHead < queue.count {
    let cur = queue[qHead]; qHead += 1
    let lx = cur % hw, ly = cur / hw
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nx = lx + dx, ny = ly + dy
        guard nx >= 0, nx < hw, ny >= 0, ny < hh else { continue }
        let ni = ny * hw + nx
        guard !visited[ni] else { continue }
        visited[ni] = true
        if !isHouseBoundaryPixel(hx0 + nx, hy0 + ny) {
            isPaper[ni] = true
            queue.append(ni)
        }
    }
}

// Keep ONLY main connected house region (removes stray bottom-left corner shadow specks)
var houseKeep = [Bool](repeating: false, count: hw * hh)
let seedHx = 175, seedHy = 220 // solidly inside house roof/facade
var hQ = [seedHy * hw + seedHx]
houseKeep[hQ[0]] = true
var hqHead = 0
while hqHead < hQ.count {
    let cur = hQ[hqHead]; hqHead += 1
    let lx = cur % hw, ly = cur / hw
    for dy in -2...2 {
        for dx in -2...2 where dx != 0 || dy != 0 {
            let nx = lx + dx, ny = ly + dy
            guard nx >= 0, nx < hw, ny >= 0, ny < hh else { continue }
            let ni = ny * hw + nx
            guard !houseKeep[ni], !isPaper[ni] else { continue }
            houseKeep[ni] = true
            hQ.append(ni)
        }
    }
}
for i in 0..<(hw * hh) where !houseKeep[i] { isPaper[i] = true }

var paperBlend = [Double](repeating: 0, count: hw * hh)
for ly in 0..<hh {
    for lx in 0..<hw {
        let idx = ly * hw + lx
        if isPaper[idx] {
            var nearEdge = 0
            for dy in -2...2 {
                for dx in -2...2 {
                    let nx = min(max(lx + dx, 0), hw - 1), ny = min(max(ly + dy, 0), hh - 1)
                    if !isPaper[ny * hw + nx] { nearEdge += 1 }
                }
            }
            paperBlend[idx] = nearEdge == 0 ? 1.0 : max(0.55, 1.0 - Double(nearEdge) * 0.03)
        }
    }
}

var seed: UInt64 = 0x51A0_2314_9921
@inline(__always)
func nextGrain() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return (Double((seed >> 40) & 0xFF) / 255.0 - 0.5) * 4.2
}

for y in 0..<H {
    let v = (Double(y) + 0.5) / Double(H)
    for x in 0..<W {
        let u = (Double(x) + 0.5) / Double(W)
        let idx = (y * W + x) * 3
        let r = buf[idx], g = buf[idx + 1], b = buf[idx + 2]
        let twill = Double((((x / 2) + (y / 2)) % 2 == 0) ? 1 : -1) * 1.4
            + sin(Double(x) * 0.14 + Double(y) * 0.05) * 0.8
        let weave = twill + nextGrain()
        let cr = targetCream.0 + weave
        let cgC = targetCream.1 + weave
        let cb = targetCream.2 + weave

        let inCloudZone = (y < cloudH)
        let inHouseRect = (x >= hx0 && x <= hx1 && y >= hy0 && y <= hy1)

        if inCloudZone {
            let bVal = cloudBgBlend[y * W + x]
            if bVal >= 0.999 {
                buf[idx] = cr; buf[idx + 1] = cgC; buf[idx + 2] = cb
            } else {
                // Crisp contrast & rich teal tint on cloud ink/fills
                let luma = (r + g + b) / 3.0
                var nr = r, ng = g, nb = b
                if b > r + 4 && g > r + 4 && luma > 76 {
                    nr = luma + (r - luma) * 1.22
                    ng = luma + (g - luma) * 1.22
                    nb = luma + (b - luma) * 1.22
                } else if luma < 92 {
                    nr *= 0.85; ng *= 0.85; nb *= 0.85
                }
                buf[idx] = nr * (1 - bVal) + cr * bVal
                buf[idx + 1] = ng * (1 - bVal) + cgC * bVal
                buf[idx + 2] = nb * (1 - bVal) + cb * bVal
            }
        } else if inHouseRect {
            let hIdx = (y - hy0) * hw + (x - hx0)
            let pAlpha = paperBlend[hIdx]
            let localC = creamAt(u, v)
            let nr = min(255, r * targetCream.0 / max(localC.0, 1))
            let ng = min(255, g * targetCream.1 / max(localC.1, 1))
            let nb = min(255, b * targetCream.2 / max(localC.2, 1))
            let luma = (nr + ng + nb) / 3.0
            let satR = luma + (nr - luma) * 1.12
            let satG = luma + (ng - luma) * 1.12
            let satB = luma + (nb - luma) * 1.12
            buf[idx] = satR * (1 - pAlpha) + cr * pAlpha
            buf[idx + 1] = satG * (1 - pAlpha) + cgC * pAlpha
            buf[idx + 2] = satB * (1 - pAlpha) + cb * pAlpha
        } else {
            buf[idx] = cr; buf[idx + 1] = cgC; buf[idx + 2] = cb
        }
    }
}

let outCtx = makeCtx(W, H)
let oPtr = outCtx.data!.bindMemory(to: UInt8.self, capacity: W * H * 4)
for i in 0..<(W * H) {
    oPtr[i * 4 + 0] = UInt8(min(max(buf[i * 3 + 0], 0), 255))
    oPtr[i * 4 + 1] = UInt8(min(max(buf[i * 3 + 1], 0), 255))
    oPtr[i * 4 + 2] = UInt8(min(max(buf[i * 3 + 2], 0), 255))
    oPtr[i * 4 + 3] = 255
}

let outImg = outCtx.makeImage()!
let rep = NSBitmapImageRep(cgImage: outImg)
let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.93])!
try! jpg.write(to: outURL)
print("wrote \(outURL.path) (\(W)x\(H), \(jpg.count / 1024) KB)")
