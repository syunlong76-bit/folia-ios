import Foundation
import simd
import CoreGraphics

// (103) 圣诞场景烘焙：12 个 GLB 按样板 place* 语义摆位、按材
// 质类合并为静态顶点/索引缓冲（逐组 GGX 参数），外加程序化
// 几何（地面/雪帽/雪人/栅栏外的一切实体补充）、接地阴影与暖
// 光池盘、雪落点登记表（flats/benches）、动态灯与烟锚点。
// 口径来源：样板主 JS（sheng-dan-guang-li-zi-yang-ban 过审
// 版）逐函数对照；坐标/角度/高度均为样板原值。颜色纪律：JS
// 十六进制色经 sRGB→线性转换；glTF factor 本为线性、原样用。

// MARK: - 小工具

/// 确定性伪随机（mulberry32；样板 srand 同族，仅求分布等价，
/// 不求逐值一致——样板种子未公开，Miller 已接受此口径偏差）。
final class XmasRNG103 {
    var a: UInt32
    init(seed: UInt32) { a = seed }
    func next() -> Float {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
    }
}

func xmasSRGB(_ hex: UInt32) -> SIMD3<Float> {
    func lin(_ v: Float) -> Float {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return SIMD3<Float>(
        lin(Float((hex >> 16) & 0xFF) / 255),
        lin(Float((hex >> 8) & 0xFF) / 255),
        lin(Float(hex & 0xFF) / 255))
}

func xmasM(_ tx: Float, _ ty: Float, _ tz: Float) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4<Float>(tx, ty, tz, 1)
    return m
}
func xmasRy(_ a: Float) -> simd_float4x4 {
    simd_float4x4(simd_quatf(angle: a, axis: SIMD3<Float>(0, 1, 0)))
}
func xmasRx(_ a: Float) -> simd_float4x4 {
    simd_float4x4(simd_quatf(angle: a, axis: SIMD3<Float>(1, 0, 0)))
}
func xmasRz(_ a: Float) -> simd_float4x4 {
    simd_float4x4(simd_quatf(angle: a, axis: SIMD3<Float>(0, 0, 1)))
}
func xmasS(_ sx: Float, _ sy: Float, _ sz: Float) -> simd_float4x4 {
    simd_float4x4(diagonal: SIMD4<Float>(sx, sy, sz, 1))
}
/// 样板 localToWorld(cx, cz, ry, lx, lz) 同式。
func xmasLocalToWorld(_ cx: Float, _ cz: Float, _ ry: Float, _ lx: Float, _ lz: Float) -> (Float, Float) {
    let cs = cos(ry), sn = sin(ry)
    return (cx + lx * cs + lz * sn, cz - lx * sn + lz * cs)
}

// MARK: - 烘焙数据结构

struct XmasMatParams103 {
    var baseColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var emissiveColor: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var emissiveIntensity: Float = 0
    var roughness: Float = 1
    var metallic: Float = 0
    var texSlot: Int = -1            // BakedScene.glbTextures 下标；-1 无贴图
    var blend: Bool = false
    var breathSp: Float = 0          // >0 时 emissive 呼吸（样板 dynMats）
    var breathPh: Float = 0
    var cueLamp: Int = -1            // >=0 时该组为第 i 盏路灯灯芯（cue boost）
}

struct XmasGroup103 {
    var params: XmasMatParams103
    var indexStart: Int = 0
    var indexCount: Int = 0
}

enum XmasDiscKind103 { case shadow, poolWarm, treePool }
struct XmasDiscRec103 {
    var center: SIMD3<Float>
    var size: SIMD2<Float>
    var rotY: Float
    var color: SIMD4<Float>          // rgb tint（线性），a=opacity
    var kind: XmasDiscKind103
}

struct XmasGlowRec103 {
    var center: SIMD3<Float>
    var scale: Float
    var color: SIMD3<Float>          // 线性，可 >1（HDR 光晕）
    var opacity: Float
}

struct XmasFlat103 { var x: Float; var z: Float; var y: Float; var r: Float }
struct XmasBenchReg103 { var x: Float; var z: Float; var ry: Float }

struct XmasBakedScene103 {
    var positions: [Float] = []
    var normals: [Float] = []
    var uvs: [Float] = []
    var colors: [Float] = []
    var indices: [UInt32] = []
    var groups: [XmasGroup103] = []
    var glbTextures: [CGImage] = []
    var discs: [XmasDiscRec103] = []
    var glows: [XmasGlowRec103] = []
    var smokeAnchors: [SIMD3<Float>] = []
    var lampTops: [SIMD3<Float>] = []
    var lampDynPos: [SIMD3<Float>] = []     // 2 盏带 PointLight 的路灯
    var lampDynPh: [Float] = []
    var porchPos: [SIMD3<Float>] = []       // 2 盏门廊灯
    var flats: [XmasFlat103] = []
    var benches: [XmasBenchReg103] = []
    var triangleCount: Int = 0
    var vertexCount: Int = 0
}

// MARK: - 构建器

final class XmasBakeBuilder103 {
    private var groupIds: [String: Int] = [:]
    private var groupVerts: [[(SIMD3<Float>, SIMD3<Float>, SIMD2<Float>, SIMD4<Float>)]] = []
    private var groupIdx: [[UInt32]] = []
    private(set) var groupParams: [XmasMatParams103] = []

    func group(_ id: String, _ params: XmasMatParams103) -> Int {
        if let g = groupIds[id] { return g }
        let g = groupParams.count
        groupIds[id] = g
        groupParams.append(params)
        groupVerts.append([])
        groupIdx.append([])
        return g
    }

    func addPrim(positions: [SIMD3<Float>], normals: [SIMD3<Float>]?,
                 uvs: [SIMD2<Float>]?, colors: [SIMD4<Float>]?,
                 indices: [UInt32], world: simd_float4x4, group: Int) {
        let base = UInt32(groupVerts[group].count)
        let nm = (world.inverse.transpose)
        func xformN(_ n: SIMD3<Float>) -> SIMD3<Float> {
            let v = nm * SIMD4<Float>(n.x, n.y, n.z, 0)
            let l = simd_length(SIMD3<Float>(v.x, v.y, v.z))
            return l > 0 ? SIMD3<Float>(v.x, v.y, v.z) / l : SIMD3<Float>(0, 1, 0)
        }
        var flatNormals: [SIMD3<Float>]? = nil
        if normals == nil {
            // 缺 NORMAL（lamp）：按面法线补（变换后计算、平坦着色）
            var fn = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: positions.count)
            let wp = positions.map { p -> SIMD3<Float> in
                let w = world * SIMD4<Float>(p.x, p.y, p.z, 1)
                return SIMD3<Float>(w.x, w.y, w.z)
            }
            var i = 0
            while i + 2 < indices.count {
                let a = wp[Int(indices[i])], b = wp[Int(indices[i + 1])], c = wp[Int(indices[i + 2])]
                var n = simd_cross(b - a, c - a)
                let l = simd_length(n)
                if l > 0 { n /= l }
                fn[Int(indices[i])] = n; fn[Int(indices[i + 1])] = n; fn[Int(indices[i + 2])] = n
                i += 3
            }
            flatNormals = fn
        }
        for (vi, p) in positions.enumerated() {
            let w = world * SIMD4<Float>(p.x, p.y, p.z, 1)
            let wp = SIMD3<Float>(w.x, w.y, w.z)
            let n: SIMD3<Float>
            if let normals { n = xformN(normals[vi]) }
            else if let fn = flatNormals { n = fn[vi] }
            else { n = SIMD3<Float>(0, 1, 0) }
            let uv = uvs?[vi] ?? SIMD2<Float>(0, 0)
            let col = colors?[vi] ?? SIMD4<Float>(1, 1, 1, 1)
            groupVerts[group].append((wp, n, uv, col))
        }
        groupIdx[group].append(contentsOf: indices.map { $0 + base })
    }

    func addModel(_ model: XmasGLBModel103, world: simd_float4x4, prefix: String,
                  texBase: Int,
                  override: (String, XmasMatParams103) -> XmasMatParams103) {
        for inst in model.instances {
            let mat = inst.prim.material >= 0 && model.materials.indices.contains(inst.prim.material)
                ? model.materials[inst.prim.material]
                : XmasGLBMaterial103()
            var params = XmasMatParams103()
            params.baseColor = mat.baseColorFactor
            params.emissiveColor = mat.emissiveFactor
            params.emissiveIntensity = mat.emissiveFactor == SIMD3<Float>(0, 0, 0) ? 0 : 1
            params.roughness = mat.roughness
            params.metallic = mat.metallic
            params.blend = mat.alphaBlend
            if let ti = mat.baseColorTexture { params.texSlot = texBase + ti }
            params = override(mat.name, params)
            let gid = group("\(prefix)|\(mat.name)|\(params.texSlot)|\(params.blend ? 1 : 0)|\(params.cueLamp)|\(params.baseColor.x),\(params.baseColor.y),\(params.baseColor.z)",
                            params)
            addPrim(positions: inst.prim.positions, normals: inst.prim.normals,
                    uvs: inst.prim.uvs, colors: inst.prim.colors,
                    indices: inst.prim.indices, world: world * inst.world, group: gid)
        }
    }

    func addGeo(_ geo: XmasGeo103, world: simd_float4x4, group: Int) {
        addPrim(positions: geo.pos, normals: geo.nrm, uvs: geo.uv,
                colors: nil, indices: geo.idx, world: world, group: group)
    }

    func finish() -> (positions: [Float], normals: [Float], uvs: [Float], colors: [Float],
                      indices: [UInt32], groups: [XmasGroup103]) {
        var pos: [Float] = [], nor: [Float] = [], uv: [Float] = [], col: [Float] = []
        var idx: [UInt32] = []
        var groups: [XmasGroup103] = []
        for g in groupParams.indices {
            var grp = XmasGroup103(params: groupParams[g])
            grp.indexStart = idx.count
            grp.indexCount = groupIdx[g].count
            for v in groupVerts[g] {
                pos.append(contentsOf: [v.0.x, v.0.y, v.0.z])
                nor.append(contentsOf: [v.1.x, v.1.y, v.1.z])
                uv.append(contentsOf: [v.2.x, v.2.y])
                col.append(contentsOf: [v.3.x, v.3.y, v.3.z, v.3.w])
            }
            idx.append(contentsOf: groupIdx[g])
            groups.append(grp)
        }
        return (pos, nor, uv, col, idx, groups)
    }
}

// MARK: - 程序化几何（pos/nrm/uv/idx，单位尺寸、原点基准）

struct XmasGeo103 {
    var pos: [SIMD3<Float>] = []
    var nrm: [SIMD3<Float>] = []
    var uv: [SIMD2<Float>] = []
    var idx: [UInt32] = []

    static func sphere(seg: Int = 14, rings: Int = 10) -> XmasGeo103 {
        var g = XmasGeo103()
        for r in 0...rings {
            let phi = Float.pi * Float(r) / Float(rings)
            for s in 0...seg {
                let th = 2 * Float.pi * Float(s) / Float(seg)
                let p = SIMD3<Float>(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
                g.pos.append(p); g.nrm.append(p)
                g.uv.append(SIMD2<Float>(Float(s) / Float(seg), Float(r) / Float(rings)))
            }
        }
        for r in 0..<rings {
            for s in 0..<seg {
                let a = UInt32(r * (seg + 1) + s), b = a + 1, c = a + UInt32(seg + 1), d = c + 1
                g.idx.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return g
    }

    static func box() -> XmasGeo103 {
        var g = XmasGeo103()
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)),
            (SIMD3<Float>(0, 0, -1), SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 1, 0)),
            (SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, -1), SIMD3<Float>(0, 1, 0)),
            (SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 0, 1), SIMD3<Float>(0, 1, 0)),
            (SIMD3<Float>(0, 1, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, -1)),
            (SIMD3<Float>(0, -1, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)),
        ]
        for (n, tu, tv) in faces {
            let base = UInt32(g.pos.count)
            for (su, sv) in [(Float(-0.5), Float(-0.5)), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)] {
                g.pos.append(n * 0.5 + tu * su + tv * sv)
                g.nrm.append(n)
                g.uv.append(SIMD2<Float>(su + 0.5, sv + 0.5))
            }
            g.idx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        return g
    }

    /// 圆柱/锥（rTop=0 即锥）：高 1、底在 -0.5、顶在 +0.5。
    static func cylinder(rTop: Float, rBottom: Float, seg: Int = 12, capped: Bool = true) -> XmasGeo103 {
        var g = XmasGeo103()
        for (y, r) in [(Float(-0.5), rBottom), (Float(0.5), rTop)] {
            for s in 0...seg {
                let th = 2 * Float.pi * Float(s) / Float(seg)
                let dir = SIMD3<Float>(cos(th), 0, sin(th))
                g.pos.append(SIMD3<Float>(dir.x * r, y, dir.z * r))
                let slope = (rBottom - rTop)
                var n = SIMD3<Float>(dir.x, slope, dir.z)
                n = simd_normalize(n)
                g.nrm.append(n)
                g.uv.append(SIMD2<Float>(Float(s) / Float(seg), y + 0.5))
            }
        }
        for s in 0..<seg {
            let a = UInt32(s), b = a + 1, c = a + UInt32(seg + 1), d = c + 1
            g.idx.append(contentsOf: [a, b, c, b, d, c])
        }
        if capped {
            for (y, r, ny) in [(Float(-0.5), rBottom, Float(-1)), (Float(0.5), rTop, Float(1))] where r > 0.001 {
                let center = UInt32(g.pos.count)
                g.pos.append(SIMD3<Float>(0, y, 0)); g.nrm.append(SIMD3<Float>(0, ny, 0)); g.uv.append(SIMD2<Float>(0.5, 0.5))
                for s in 0...seg {
                    let th = 2 * Float.pi * Float(s) / Float(seg)
                    g.pos.append(SIMD3<Float>(cos(th) * r, y, sin(th) * r))
                    g.nrm.append(SIMD3<Float>(0, ny, 0))
                    g.uv.append(SIMD2<Float>(cos(th) * 0.5 + 0.5, sin(th) * 0.5 + 0.5))
                }
                for s in 0..<seg {
                    let a = center + 1 + UInt32(s), b = a + 1
                    if ny > 0 { g.idx.append(contentsOf: [center, a, b]) } else { g.idx.append(contentsOf: [center, b, a]) }
                }
            }
        }
        return g
    }

    static func torus(R: Float, tube: Float, radSeg: Int = 8, tubSeg: Int = 18) -> XmasGeo103 {
        var g = XmasGeo103()
        for i in 0...tubSeg {
            let u = 2 * Float.pi * Float(i) / Float(tubSeg)
            for j in 0...radSeg {
                let v = 2 * Float.pi * Float(j) / Float(radSeg)
                let c = SIMD3<Float>(cos(u) * (R + tube * cos(v)), tube * sin(v), sin(u) * (R + tube * cos(v)))
                var n = c - SIMD3<Float>(cos(u) * R, 0, sin(u) * R)
                n = simd_normalize(n)
                g.pos.append(c); g.nrm.append(n)
                g.uv.append(SIMD2<Float>(Float(i) / Float(tubSeg), Float(j) / Float(radSeg)))
            }
        }
        for i in 0..<tubSeg {
            for j in 0..<radSeg {
                let a = UInt32(i * (radSeg + 1) + j), b = a + 1, c = a + UInt32(radSeg + 1), d = c + 1
                g.idx.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return g
    }

    /// 平面 disc（半径 1、法线 +Y、XZ 面）。
    static func disc(seg: Int = 48) -> XmasGeo103 {
        var g = XmasGeo103()
        g.pos.append(SIMD3<Float>(0, 0, 0)); g.nrm.append(SIMD3<Float>(0, 1, 0)); g.uv.append(SIMD2<Float>(0.5, 0.5))
        for s in 0...seg {
            let th = 2 * Float.pi * Float(s) / Float(seg)
            g.pos.append(SIMD3<Float>(cos(th), 0, sin(th)))
            g.nrm.append(SIMD3<Float>(0, 1, 0))
            g.uv.append(SIMD2<Float>(cos(th) * 0.5 + 0.5, sin(th) * 0.5 + 0.5))
        }
        for s in 0..<seg { g.idx.append(contentsOf: [0, UInt32(s + 2), UInt32(s + 1)]) }
        return g
    }

    /// 地面大圆盘：径向网格＋样板位移公式（buildGround 同式）。
    static func ground(radius: Float = 72, rings: Int = 26, seg: Int = 56) -> XmasGeo103 {
        var g = XmasGeo103()
        func height(_ x: Float, _ z: Float) -> Float {
            let r = sqrt(x * x + z * z)
            func ss(_ v: Float, _ a: Float, _ b: Float) -> Float {
                let t = min(max((v - a) / (b - a), 0), 1)
                return t * t * (3 - 2 * t)
            }
            var h = (sin(x * 0.16 + 1.7) * cos(z * 0.13 + 0.4) * 0.55 + sin(x * 0.05) * cos(z * 0.07) * 0.8)
                * ss(r, 12, 30) * 0.85
            h += sin(x * 1.4) * cos(z * 1.2) * 0.03 * ss(r, 3, 9)
            return h
        }
        for r in 0...rings {
            let fr = Float(r) / Float(rings)
            let rad = fr * radius
            for s in 0...seg {
                let th = 2 * Float.pi * Float(s) / Float(seg)
                let x = cos(th) * rad, z = sin(th) * rad
                g.pos.append(SIMD3<Float>(x, height(x, z), z))
                g.nrm.append(SIMD3<Float>(0, 1, 0))
                g.uv.append(SIMD2<Float>(x / radius * 0.5 + 0.5, z / radius * 0.5 + 0.5))
            }
        }
        for r in 0..<rings {
            for s in 0..<seg {
                let a = UInt32(r * (seg + 1) + s), b = a + 1, c = a + UInt32(seg + 1), d = c + 1
                g.idx.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        // computeVertexNormals 等价：面法线累加后归一。
        var acc = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: g.pos.count)
        var i = 0
        while i + 2 < g.idx.count {
            let a = g.pos[Int(g.idx[i])], b = g.pos[Int(g.idx[i + 1])], c = g.pos[Int(g.idx[i + 2])]
            let n = simd_cross(b - a, c - a)
            acc[Int(g.idx[i])] += n; acc[Int(g.idx[i + 1])] += n; acc[Int(g.idx[i + 2])] += n
            i += 3
        }
        for vi in g.nrm.indices {
            let l = simd_length(acc[vi])
            if l > 0 { g.nrm[vi] = acc[vi] / l }
        }
        return g
    }
}
