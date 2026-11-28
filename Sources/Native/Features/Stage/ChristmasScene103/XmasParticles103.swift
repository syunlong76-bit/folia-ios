import Foundation
import simd
import UIKit

// (103) 粒子系统：共享池（树=粒子本体、歌词借粒共用一池）、
// 树生成器、灯串 canopy、地面闪光、天空星、远景氛围雪、CPU
// 落雪模拟（着陆/积存/搅动/雪沫）、CoreText 字形采样、纯
// position 驱动的歌词状态机与六锚点洗牌袋。
// 移植纪律：生成器/采样/时序公式逐式对照样板 JS；随机源为
// 本地种子 RNG（样板用未播种 Math.random，无静态数据可导
// 出——DS 对账第 15 条顶回后的定案：复刻算法与分布参数）。

// MARK: - 池数据（静态属性包）

struct XmasPoolData103 {
    var positions: [Float] = []   // ×3
    var colors: [Float] = []      // ×3
    var misc1: [Float] = []       // ×4: size, phase, speed, orbit
    var dirs: [Float] = []        // ×3（已归一）
    var count: Int = 0
    var opacity: Float = 1
    var snowMode: Bool = false
}

struct Ptump {
    var p: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var c: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    var s: Float = 1
    var sp: Float = 1
    var d: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    var orb: Float = 0
}

/// buildPoints 等价：filler 逐粒填性状，phase 随机、dir 归一。
private func buildPoints103(count: Int, opacity: Float, snowMode: Bool = false,
                            rng: XmasRNG103,
                            filler: (Int, inout Ptump) -> Void) -> XmasPoolData103 {
    var out = XmasPoolData103()
    out.count = count
    out.opacity = opacity
    out.snowMode = snowMode
    out.positions.reserveCapacity(count * 3)
    out.colors.reserveCapacity(count * 3)
    out.misc1.reserveCapacity(count * 4)
    out.dirs.reserveCapacity(count * 3)
    var t = Ptump()
    for i in 0..<count {
        t.orb = 0
        filler(i, &t)
        out.positions.append(contentsOf: [t.p.x, t.p.y, t.p.z])
        out.colors.append(contentsOf: [t.c.x, t.c.y, t.c.z])
        let phase = rng.next() * 2 * Float.pi
        out.misc1.append(contentsOf: [t.s, phase, t.sp, t.orb])
        let dl = simd_length(t.d)
        let d = dl > 0 ? t.d / dl : SIMD3<Float>(0, 1, 0)
        out.dirs.append(contentsOf: [d.x, d.y, d.z])
    }
    return out
}

// MARK: - 树生成器（buildPoints filler 逐式移植）

enum XmasTreeGen103 {
    static let treeH: Float = 8.8
    static let treeR: Float = 3.15
    static let golden: Float = 2.39996

    struct TreePt { var p: SIMD3<Float>; var outer: Float; var orb: Float; var dir: SIMD3<Float>? }

    static func treePoints(rng: XmasRNG103) -> [TreePt] {
        var pts: [TreePt] = []
        let NB = 34
        for b in 0..<NB {
            let fb = Float(b) / Float(NB - 1)
            let baseY = 0.35 + pow(fb, 1.12) * (treeH - 0.9)
            let maxLen = treeR * pow(max(0.02, 1 - baseY / treeH), 0.82) * (0.8 + rng.next() * 0.5)
            let bang = Float(b) * golden + (rng.next() - 0.5) * 0.7
            let droop = 0.30 + rng.next() * 0.22
            let dead = rng.next() * 2 * Float.pi
            let n = Int(round(70 + (1 - fb) * 170))
            for _ in 0..<n {
                let s = pow(rng.next(), 0.78)
                let la = bang + (rng.next() - 0.5) * 0.55 * (1 - s * 0.4)
                let dAng = atan2(sin(la - dead), cos(la - dead))
                if abs(dAng) < 0.5 && rng.next() < 0.8 { continue }
                let lr = s * maxLen
                var px = cos(bang) * lr, pz = sin(bang) * lr
                var py = baseY - sin(s * Float.pi * 0.5) * droop * maxLen * 0.42 + (rng.next() - 0.5) * 0.1
                let jr = (0.10 + 0.30 * (1 - s * 0.5)) * sqrt(rng.next())
                let ja = rng.next() * 2 * Float.pi
                px += cos(ja) * jr; pz += sin(ja) * jr
                py += sin(ja) * jr * 0.5
                pts.append(TreePt(p: SIMD3<Float>(px, py, pz), outer: s > 0.55 ? 1 : 0.4, orb: 0.045, dir: nil))
            }
        }
        for _ in 0..<900 {
            let iy = pow(rng.next(), 0.95) * treeH * 0.96
            let iprof = treeR * pow(max(0, 1 - iy / treeH), 0.9)
            let ir = iprof * sqrt(rng.next()) * 0.62
            let ia = rng.next() * 2 * Float.pi
            pts.append(TreePt(p: SIMD3<Float>(cos(ia) * ir, iy, sin(ia) * ir), outer: 0.3, orb: 0.045, dir: nil))
        }
        for _ in 0..<900 {
            let hy = pow(rng.next(), 1.1) * 10.2
            let hprof = treeR * pow(max(0, 1 - hy / treeH), 0.85) + 0.12
            let hrr = hprof + 0.9 + rng.next() * 2.4
            let hang = rng.next() * 2 * Float.pi
            pts.append(TreePt(p: SIMD3<Float>(cos(hang) * hrr, hy + (rng.next() - 0.5) * 0.4, sin(hang) * hrr),
                              outer: 1, orb: 0.03 + rng.next() * 0.04,
                              dir: SIMD3<Float>(cos(hang), 0.25, sin(hang))))
        }
        // Fisher-Yates 洗牌（借粒时任一子集都铺满全树）
        if pts.count > 1 {
            for m in stride(from: pts.count - 1, through: 1, by: -1) {
                let q = Int(rng.next() * Float(m + 1)) % (m + 1)
                pts.swapAt(m, q)
            }
        }
        return pts
    }

    /// 主池（orbit 6800）＋树干 90。
    static func orbitPool(rng: XmasRNG103) -> XmasPoolData103 {
        let treePts = treePoints(rng: rng)
        let orbit = buildPoints103(count: 6800, opacity: 1, rng: rng) { i, t in
            let P = treePts[i % treePts.count]
            t.p = P.p
            t.d = P.dir ?? SIMD3<Float>(P.p.x, 0.2, P.p.z)
            t.orb = P.orb
            let pick = rng.next()
            if pick < 0.34 { t.c = SIMD3<Float>(1.0, 0.76 + rng.next() * 0.14, 0.32 + rng.next() * 0.14) }
            else if pick < 0.5 { t.c = SIMD3<Float>(1.0, 0.93, 0.74) }
            else if pick < 0.63 { t.c = SIMD3<Float>(1.0, 0.3, 0.24) }
            else if pick < 0.76 { t.c = SIMD3<Float>(0.42, 1.0, 0.56) }
            else if pick < 0.86 { t.c = SIMD3<Float>(1.0, 0.52, 0.7) }
            else if pick < 0.95 { t.c = SIMD3<Float>(0.52, 0.74, 1.0) }
            else { t.c = SIMD3<Float>(0.62, 0.98, 0.95) }
            let sr = rng.next()
            t.s = sr < 0.62 ? 0.22 + rng.next() * 0.18 : (sr < 0.92 ? 0.42 + rng.next() * 0.24 : 0.68 + rng.next() * 0.34)
            if P.outer < 0.5 { t.s *= 0.8 }
            t.sp = 0.8 + rng.next() * 1.9
        }
        return orbit
    }

    static func trunkPool(rng: XmasRNG103) -> XmasPoolData103 {
        buildPoints103(count: 90, opacity: 0.9, rng: rng) { _, t in
            let a = rng.next() * 2 * Float.pi, r = rng.next() * 0.16
            t.p = SIMD3<Float>(cos(a) * r, rng.next() * 0.55, sin(a) * r)
            t.d = SIMD3<Float>(0, 1, 0)
            t.c = SIMD3<Float>(1.0, 0.62, 0.3)
            t.s = 0.18 + rng.next() * 0.14
            t.sp = 0.6 + rng.next()
        }
    }

    static func sparklePool(rng: XmasRNG103) -> XmasPoolData103 {
        buildPoints103(count: 950, opacity: 0.95, rng: rng) { _, t in
            let ang = rng.next() * 2 * Float.pi
            let rr = sqrt(rng.next()) * 15
            t.p = SIMD3<Float>(cos(ang) * rr, 0.03, sin(ang) * rr)
            t.d = SIMD3<Float>(0, 1, 0)
            let pick = rng.next()
            t.c = pick < 0.5 ? SIMD3<Float>(0.9, 0.96, 1.0) : (pick < 0.8 ? SIMD3<Float>(1.0, 0.93, 0.7) : SIMD3<Float>(0.72, 0.86, 1.0))
            t.s = 0.15 + rng.next() * 0.22
            t.sp = 1.5 + rng.next() * 3.0
        }
    }

    static func skyPool(rng: XmasRNG103) -> XmasPoolData103 {
        buildPoints103(count: 560, opacity: 0.85, rng: rng) { _, t in
            let ang = rng.next() * 2 * Float.pi
            let el = 0.25 + rng.next() * 1.2
            let rr: Float = 55
            t.p = SIMD3<Float>(cos(ang) * cos(el) * rr, sin(el) * rr, sin(ang) * cos(el) * rr)
            t.d = SIMD3<Float>(0, 1, 0)
            let bb = 0.55 + rng.next() * 0.45
            t.c = SIMD3<Float>(bb, bb, bb * 1.05)
            t.s = 0.3 + rng.next() * 0.34
            t.sp = 0.4 + rng.next() * 1.0
        }
    }

    static func farSnowPool(rng: XmasRNG103) -> XmasPoolData103 {
        buildPoints103(count: 1500, opacity: 0.92, snowMode: true, rng: rng) { _, t in
            t.p = SIMD3<Float>((rng.next() - 0.5) * 34, rng.next() * 20, (rng.next() - 0.5) * 34)
            t.d = SIMD3<Float>(0, 1, 0)
            let bb = 0.8 + rng.next() * 0.2
            t.c = SIMD3<Float>(bb * 0.92, bb * 0.96, bb)
            t.s = 0.19 + rng.next() * 0.38
            t.sp = 0.45 + rng.next() * 0.95
        }
    }

    /// 灯串 canopy：每盏灯→树顶（sag 0.5）＋相邻环（sag 0.65），各 15 段。
    static func canopyPool(lampTops: [SIMD3<Float>], rng: XmasRNG103) -> XmasPoolData103 {
        let bulbCols: [SIMD3<Float>] = [
            SIMD3<Float>(1.0, 0.32, 0.28), SIMD3<Float>(1.0, 0.77, 0.3), SIMD3<Float>(0.37, 0.6, 1.0),
            SIMD3<Float>(1.0, 0.55, 0.78), SIMD3<Float>(0.49, 1.0, 0.72),
        ]
        var pts: [(SIMD3<Float>, SIMD3<Float>)] = []
        func swag(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ sag: Float, _ n: Int) {
            for i in 0...n {
                let f = Float(i) / Float(n)
                var p = p1 + (p2 - p1) * f
                p.y -= sin(f * Float.pi) * sag
                pts.append((p, bulbCols[pts.count % bulbCols.count]))
            }
        }
        let treeTop = SIMD3<Float>(0, 7.4, 0)
        for L in lampTops { swag(L, treeTop, 0.5, 15) }
        let sorted = lampTops.sorted { atan2($0.z, $0.x) < atan2($1.z, $1.x) }
        if sorted.count > 1 {
            for si in sorted.indices { swag(sorted[si], sorted[(si + 1) % sorted.count], 0.65, 15) }
        }
        return buildPoints103(count: pts.count, opacity: 0.95, rng: rng) { i, t in
            t.p = pts[i].0
            t.d = SIMD3<Float>(0, 1, 0)
            t.c = pts[i].1
            t.s = 0.3 + Float(i % 5) * 0.035
            t.sp = 0.7 + Float(i % 7) * 0.31
        }
    }
}

// MARK: - 歌词锚点（六处、洗牌袋不连重复）

struct XmasAnchor103 {
    var name: String
    var p: SIMD3<Float>
    var radius: Float
    var phi: Float
    var scale: Float
    var cue: String?
    var wind: SIMD3<Float>
    var windAmt: Float
    var ribbonAmp: Float
    // resolved（按画幅拉过）
    var pos: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var theta: Float = 0
    var rRadius: Float = 0

    static let all: [XmasAnchor103] = [
        XmasAnchor103(name: "star", p: SIMD3<Float>(2.0, 9.3, 0.8), radius: 13, phi: 1.05, scale: 0.95,
                      cue: "star", wind: SIMD3<Float>(0.85, 0.2, 0.3), windAmt: 0.9, ribbonAmp: 0.16),
        XmasAnchor103(name: "crown", p: SIMD3<Float>(-3.4, 6.4, 2.2), radius: 11.5, phi: 1.10, scale: 0.90,
                      cue: nil, wind: SIMD3<Float>(0.85, 0.2, 0.3), windAmt: 0.9, ribbonAmp: 0.06),
        XmasAnchor103(name: "plaza", p: SIMD3<Float>(0.6, 3.1, 4.6), radius: 11, phi: 1.16, scale: 0.90,
                      cue: nil, wind: SIMD3<Float>(0.85, 0.2, 0.3), windAmt: 0.9, ribbonAmp: 0.05),
        XmasAnchor103(name: "lamp", p: SIMD3<Float>(4.6, 3.6, 3.4), radius: 10.5, phi: 1.14, scale: 0.90,
                      cue: "lamp", wind: SIMD3<Float>(0.85, 0.2, 0.3), windAmt: 0.9, ribbonAmp: 0.06),
        XmasAnchor103(name: "west", p: SIMD3<Float>(-4.8, 5.4, -1.2), radius: 12, phi: 1.12, scale: 1.0,
                      cue: nil, wind: SIMD3<Float>(0.85, 0.2, 0.3), windAmt: 1.25, ribbonAmp: 0.07),
        XmasAnchor103(name: "field", p: SIMD3<Float>(3.4, 7.6, -3.0), radius: 12.5, phi: 1.08, scale: 1.0,
                      cue: nil, wind: SIMD3<Float>(0.85, 0.2, 0.3), windAmt: 0.9, ribbonAmp: 0.10),
    ]

    func resolved(aspect: Float) -> XmasAnchor103 {
        var a = self
        var px = p.x, pz = p.z
        var radius = self.radius
        if aspect < 1 { px *= 0.82; pz *= 0.9; radius *= 1.22 }
        else if aspect < 1.4 { radius *= 1.08 }
        a.pos = SIMD3<Float>(px, p.y, pz)
        a.theta = atan2(px, pz) + 0.3
        a.rRadius = radius
        return a
    }
}

// MARK: - 字形采样（sampleGlyph 等价：1400×200 离屏、步长 3、alpha>110）

struct XmasGlyph103 {
    var pts: [(x: Float, y: Float, z: Float, ch: Int)] = []
    var worldW: Float = 0
    var worldH: Float = 0
}

enum XmasGlyphSampler103 {
    static let lyrMax = 2300

    static func sample(text: String, scale gScale: Float, aspect: Float, rng: XmasRNG103) -> XmasGlyph103 {
        let W = 1400, H = 200
        let fs: CGFloat = text.count > 8 ? 108 : 128
        let font = UIFont.systemFont(ofSize: fs, weight: .semibold)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1; fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { _ in
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let ts = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (CGFloat(W) - ts.width) / 2,
                                                y: (CGFloat(H) - ts.height) / 2 + 6), withAttributes: attrs)
        }
        var out = XmasGlyph103()
        guard let cg = img.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return out }
        let bpr = cg.bytesPerRow
        let pw = cg.width, ph = cg.height
        var raw: [(Int, Int)] = []
        let step = 3
        var yy = 0
        while yy < ph {
            var xx = 0
            while xx < pw {
                if bytes[yy * bpr + xx * 4 + 3] > 110 { raw.append((xx, yy)) }
                xx += step
            }
            yy += step
        }
        if raw.count > lyrMax {
            var keep: [(Int, Int)] = []
            let strideF = Float(raw.count) / Float(lyrMax)
            for i in 0..<lyrMax { keep.append(raw[Int(Float(i) * strideF)]) }
            raw = keep
        }
        var worldW = min(Float(9.2), 4.4 + Float(text.count) * 0.62) * gScale
        if aspect < 1 { worldW *= (0.7 + 0.3 * aspect) }
        let worldH = worldW * (Float(H) / Float(W))
        let charW = Float(W) / Float(max(text.count, 1))
        out.worldW = worldW
        out.worldH = worldH
        let fW = Float(W), fH = Float(H)
        let charCount = text.count
        out.pts = raw.map { (xx, yy) -> (x: Float, y: Float, z: Float, ch: Int) in
            let gx: Float = (Float(xx) / fW - 0.5) * worldW
            let gy: Float = (0.5 - Float(yy) / fH) * worldH
            let gz: Float = (rng.next() - 0.5) * 0.06
            let gch: Int = min(charCount - 1, Int(Float(xx) / charW))
            return (x: gx, y: gy, z: gz, ch: gch)
        }
        return out
    }
}

// MARK: - 歌词状态机（纯 position 驱动；不连续即按 position 重算＝settle）

struct XmasLyricFrame103 {
    var active: Bool = false
    var fly: Float = 0
    var ret: Float = 0
    var charLit: Float = 99
    var breath: Float = 0
    var env: Float = 0            // lyricEnv（cue/衬底共用包络）
    var shade: Float = 0          // 衬底椭圆 opacity
    var anchor: XmasAnchor103? = nil
    var glyphW: Float = 0
    var glyphH: Float = 0
    var followGoal: Float = 0
    var lineIndex: Int = -1
    var justAssigned: Bool = false
}

final class XmasLyricMachine103 {
    static let poolCount = 6800
    // 借粒动态属性（引擎据 borrowDirty 上传 GPU）
    var aLyr: [Float] = [Float](repeating: 0, count: poolCount * 3)
    var aMisc2: [Float] = [Float](repeating: 0, count: poolCount * 3)  // lyrOn, delay, char
    var borrowDirty = false

    private var rng = XmasRNG103(seed: 31415)
    private var bag: [Int] = []
    private var lastAnchorIdx: Int = -1
    private var curLine: Int = -1
    private var curAnchor: XmasAnchor103? = nil
    private var glyphW: Float = 0
    private var glyphH: Float = 0
    private var aspect: Float = 1

    func setAspect(_ a: Float) { aspect = a }

    func reset() {
        curLine = -1
        bag = []
        lastAnchorIdx = -1
        for i in aMisc2.indices where i % 3 == 0 { aMisc2[i] = 0 }
        borrowDirty = true
    }

    private func nextAnchor() -> XmasAnchor103 {
        if bag.isEmpty {
            bag = Array(0..<XmasAnchor103.all.count)
            for m in stride(from: bag.count - 1, through: 1, by: -1) {
                let q = Int(rng.next() * Float(m + 1)) % (m + 1)
                bag.swapAt(m, q)
            }
            if bag.first == lastAnchorIdx && bag.count > 1 { bag.swapAt(0, 1) }
        }
        let idx = bag.removeFirst()
        lastAnchorIdx = idx
        return XmasAnchor103.all[idx].resolved(aspect: aspect)
    }

    /// assignLine 等价：采样字形＋写借粒属性（全池 aLyrOn 先清零）。
    private func assignLine(text: String) {
        let anchor = nextAnchor()
        curAnchor = anchor
        let glyph = XmasGlyphSampler103.sample(text: text, scale: anchor.scale, aspect: aspect, rng: rng)
        glyphW = glyph.worldW
        glyphH = glyph.worldH
        for i in 0..<Self.poolCount { aMisc2[i * 3] = 0 }
        // 洗牌下标（借粒铺满全树）
        var oi = Array(0..<Self.poolCount)
        for m in stride(from: oi.count - 1, through: 1, by: -1) {
            let q = Int(rng.next() * Float(m + 1)) % (m + 1)
            oi.swapAt(m, q)
        }
        let len = max(text.count, 1)
        let n = min(glyph.pts.count, Self.poolCount)
        for k in 0..<n {
            let idx = oi[k]
            let gp = glyph.pts[k]
            aLyr[idx * 3] = gp.x; aLyr[idx * 3 + 1] = gp.y; aLyr[idx * 3 + 2] = gp.z
            aMisc2[idx * 3] = 1
            aMisc2[idx * 3 + 1] = (len > 1 ? Float(gp.ch) / Float(len - 1) : 0) * 0.75 + rng.next() * 0.25
            aMisc2[idx * 3 + 2] = Float(gp.ch)
        }
        let ribN = min(150, Self.poolCount - n)
        for rk in 0..<ribN {
            let idx = oi[n + rk]
            let rTop = rk % 2 == 0
            aLyr[idx * 3] = (Float(rk) / Float(max(ribN, 1)) - 0.5) * glyphW * 1.16
            aLyr[idx * 3 + 1] = (rTop ? 1 : -1) * (glyphH * 0.85 + 0.12) + (rng.next() - 0.5) * 0.14
            aLyr[idx * 3 + 2] = (rng.next() - 0.5) * 0.1
            aMisc2[idx * 3] = 1
            aMisc2[idx * 3 + 1] = rng.next() * 0.4
            aMisc2[idx * 3 + 2] = -1
        }
        borrowDirty = true
    }

    /// 逐帧：position 驱动。行号由宿主口径 LyricParser 判定后传入。
    func update(lines: [LyricLine], lineIndex: Int, position: TimeInterval) -> XmasLyricFrame103 {
        var f = XmasLyricFrame103()
        f.lineIndex = lineIndex
        guard lineIndex >= 0, lines.indices.contains(lineIndex) else {
            curLine = -1
            return f
        }
        let line = lines[lineIndex]
        if lineIndex != curLine {
            curLine = lineIndex
            assignLine(text: line.text)
            f.justAssigned = true
        }
        guard let anchor = curAnchor else { return f }
        let dur = max(line.end - line.start, 0.1)
        let t = position - line.start
        // 样板窗口 GATHER 2.3 / RETURN 1.7 按行长等比收放（短行不
        // 出现负停留）；长行与样板演示行（7.5s）同值。
        let gather = min(2.3, dur * 0.4)
        let retT = min(1.7, dur * 0.25)
        let len = Float(max(line.text.count, 1))
        f.active = true
        f.anchor = anchor
        f.glyphW = glyphW
        f.glyphH = glyphH
        if t < 0 {
            f.fly = 0; f.charLit = 0; f.env = 0
        } else if t < gather {
            let u = Float(t / gather)
            f.fly = u
            f.charLit = u * (len + 0.6)
            f.env = u
            f.followGoal = 1
        } else if t < dur - retT {
            f.fly = 1
            f.charLit = len + 1
            f.env = 1
            f.followGoal = 1
        } else if t < dur {
            let u = Float((t - (dur - retT)) / retT)
            f.fly = 1
            f.ret = u
            f.charLit = len + 1
            f.env = 1 - u
            f.followGoal = 0
        } else {
            f.fly = 0; f.ret = 0; f.charLit = 0; f.env = 0
        }
        f.shade = 0.52 * f.env
        f.breath = f.env
        return f
    }
}

// MARK: - 落雪模拟（CPU：风场/搅动/雪沫/着陆/积存）

final class XmasSnowSim103 {
    static let fallN = 900
    static let accN = 2400

    // 落雪状态
    var fx: [Float] = [], fy: [Float] = [], fz: [Float] = []
    var fvx: [Float] = [], fvz: [Float] = [], fvy: [Float] = []
    var fSize: [Float] = [], fSpeed: [Float] = [], fPhase: [Float] = []
    var fallPositions: [Float] = [Float](repeating: 0, count: fallN * 3)
    var fallMisc: [Float] = [Float](repeating: 0, count: fallN * 3)  // size, phase, birth(unused=0)
    // 积存池（环形）
    var accPositions: [Float] = [Float](repeating: 0, count: accN * 3)
    var accMisc: [Float] = [Float](repeating: 0, count: accN * 3)   // size, phase, birth
    var accLife: [Float] = [Float](repeating: 0, count: accN)
    private var accHead = 0
    var accDirty = true   // 引擎据此重传积存 buffer（addAccum 时置位）

    // 风场（updateWind 同式，引擎逐帧写 time 后读）
    private(set) var gust: Float = 0
    private(set) var windX: Float = 0
    private(set) var windZ: Float = 0
    var pinchSnow: Float = 0
    // 搅动（拖动雪幕）
    var stir = SIMD3<Float>(0, 4.5, 0)
    var stirVel = SIMD3<Float>(0, 0, 0)
    var stirPower: Float = 0
    var stirT: Float = -10

    private var rng = XmasRNG103(seed: 99991)
    private var flats: [XmasFlat103] = []
    private var benches: [XmasBenchReg103] = []

    init(flats: [XmasFlat103], benches: [XmasBenchReg103]) {
        self.flats = flats
        self.benches = benches
        fx = [Float](repeating: 0, count: Self.fallN)
        fy = fx; fz = fx; fvx = fx; fvz = fx; fvy = fx
        fSize = fx; fSpeed = fx; fPhase = fx
        for i in 0..<Self.fallN { respawn(i, randomY: true) }
        for i in 0..<Self.accN {
            accMisc[i * 3] = 0.24 + rng.next() * 0.24
            accMisc[i * 3 + 1] = rng.next() * 2 * Float.pi
            accMisc[i * 3 + 2] = -1000   // 未出生
            accLife[i] = 24
        }
    }

    private func respawn(_ i: Int, randomY: Bool = false) {
        let near = rng.next() < 0.42
        let ang = rng.next() * 2 * Float.pi
        if near {
            let r = sqrt(rng.next()) * 9.5
            fx[i] = cos(ang) * r; fz[i] = sin(ang) * r
            fSize[i] = 0.42 + rng.next() * 0.5
            fSpeed[i] = 0.95 + rng.next() * 0.75
        } else {
            let r = 8 + sqrt(rng.next()) * 7.5
            fx[i] = cos(ang) * r; fz[i] = sin(ang) * r
            fSize[i] = 0.16 + rng.next() * 0.2
            fSpeed[i] = 0.55 + rng.next() * 0.5
        }
        fy[i] = randomY ? 2 + rng.next() * 12 : 11 + rng.next() * 3
        fvx[i] = 0; fvz[i] = 0; fvy[i] = 0
        fPhase[i] = rng.next() * 2 * Float.pi
    }

    static func treeSurfaceY(_ r: Float) -> Float {
        if r > 3.35 { return -1 }
        let f = 1 - pow(max(0, r - 0.1) / 3.25, 1.25)
        return f * 8.8 + 0.1
    }

    private func addAccum(_ x: Float, _ y: Float, _ z: Float, _ now: Float) {
        accDirty = true
        let i = accHead
        accHead = (accHead + 1) % Self.accN
        accPositions[i * 3] = x; accPositions[i * 3 + 1] = y; accPositions[i * 3 + 2] = z
        accMisc[i * 3 + 2] = now
        accLife[i] = 24 + rng.next() * 18
    }

    /// 点按雪沫：半径 2.6 内雪片跃起外推。
    func puff(_ x: Float, _ y: Float, _ z: Float) {
        for i in 0..<Self.fallN {
            let dx = fx[i] - x, dy = fy[i] - y, dz = fz[i] - z
            let d2 = dx * dx + dy * dy + dz * dz
            if d2 < 2.6 * 2.6 {
                let d = sqrt(d2)
                let f = 1 - d / 2.6
                fvy[i] += (1.9 + rng.next() * 1.5) * f
                let hl = max(sqrt(dx * dx + dz * dz), 0.01)
                fvx[i] += dx / hl * 1.1 * f
                fvz[i] += dz / hl * 1.1 * f
            }
        }
    }

    func update(dt: Float, now: Float) {
        // updateWind 同式
        let ang = sin(now * 0.07) * 0.9 + sin(now * 0.023 + 1.7) * 0.7
        let g = sin(now * 0.21 + 1.3) * 0.6 + sin(now * 0.083) * 0.55
        gust = pow(max(0, g), 2)
        let mag = 0.22 + gust * 1.35 + pinchSnow * 0.7
        windX = cos(ang) * mag
        windZ = sin(ang) * mag
        let speedMul = 1 + gust * 0.18 + pinchSnow * 0.35
        // 搅动冲量衰减
        let stirDecay = pow(Float(0.22), dt)
        stirVel *= stirDecay
        let stirAge = now - stirT
        let stirOn = stirAge < 0.15 && stirPower > 0.01

        for i in 0..<Self.fallN {
            var vx = windX + fvx[i]
            var vz = windZ + fvz[i]
            var vy = -fSpeed[i] * speedMul + fvy[i]
            if stirOn {
                let dx = fx[i] - stir.x, dy = fy[i] - stir.y, dz = fz[i] - stir.z
                let d2 = dx * dx + dy * dy + dz * dz
                if d2 < 20 {
                    // 涡流＋拖拽（样板 stir 口径的等价实现）
                    vx += (-dz * 2.2 + stirVel.x) * stirPower
                    vz += (dx * 2.2 + stirVel.z) * stirPower
                    vy += stirVel.y * stirPower * 0.4
                }
            }
            fx[i] += vx * dt
            fz[i] += vz * dt
            fy[i] += vy * dt
            // 额外速度衰减（雪沫跃起后回落）
            fvx[i] *= pow(Float(0.1), dt)
            fvz[i] *= pow(Float(0.1), dt)
            if fvy[i] > 0 { fvy[i] -= 2.8 * dt; if fvy[i] < 0 { fvy[i] = 0 } }
            else { fvy[i] = 0 }

            // 着陆判定序：树冠 → flats → benches → 地面
            var landed = false
            var landY: Float = 0
            if vy < 0 {
                let r = sqrt(fx[i] * fx[i] + fz[i] * fz[i])
                if r < 3.55 {
                    let sy = Self.treeSurfaceY(r)
                    if sy >= 0 && fy[i] <= sy { landed = true; landY = sy }
                }
                if !landed {
                    for ft in flats {
                        let dx = fx[i] - ft.x, dz = fz[i] - ft.z
                        if dx * dx + dz * dz < ft.r * ft.r && fy[i] <= ft.y { landed = true; landY = ft.y; break }
                    }
                }
                if !landed {
                    for bn in benches {
                        let dx = fx[i] - bn.x, dz = fz[i] - bn.z
                        let cs = cos(bn.ry), sn = sin(bn.ry)
                        let lx = cs * dx - sn * dz
                        let lz = sn * dx + cs * dz
                        if abs(lx) < 1.32 {
                            if abs(lz - 0.05) < 0.34 && fy[i] <= 0.7 { landed = true; landY = 0.7; break }
                            if abs(lz + 0.3) < 0.12 && fy[i] <= 1.34 { landed = true; landY = 1.34; break }
                        }
                    }
                }
                if !landed && fy[i] <= 0.03 {
                    if rng.next() < 0.4 { addAccum(fx[i], 0.045, fz[i], now) }
                    landed = true; landY = -1   // 地面着陆不另记（已按概率记账）
                }
            }
            if landed {
                if landY >= 0 { addAccum(fx[i], landY + 0.02, fz[i], now) }
                respawn(i)
            } else if fx[i] * fx[i] + fz[i] * fz[i] > 460 || fy[i] < -1 {
                respawn(i)
            }
            fallPositions[i * 3] = fx[i]; fallPositions[i * 3 + 1] = fy[i]; fallPositions[i * 3 + 2] = fz[i]
            fallMisc[i * 3] = fSize[i]; fallMisc[i * 3 + 1] = fPhase[i]; fallMisc[i * 3 + 2] = 0
        }
    }
}
