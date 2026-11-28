import Foundation
import simd
import ImageIO
import CoreGraphics

// (103) 圣诞场景 Metal 移植 · 最小 glTF 2.0 加载器。
// 只覆盖样板资产实测用到的子集（任务书审计口径）：GLB 容器
// （JSON+BIN 双 chunk）、节点 TRS/矩阵层级、POSITION/NORMAL/
// TEXCOORD_0（COLOR_0 兼容读）、u16/u32 索引、pbrMetallic-
// Roughness + emissiveFactor + alphaMode、内嵌图片（present/
// mailbox 各一张）经 ImageIO 解码为 RGBA。无 Draco/动画/蒙皮
// （extensionsUsed 全空，已实测）。缺 NORMAL 的图元（lamp）
// 在烘焙期补面法线。颜色纪律：glTF 的 factor 本身即线性空间
// 值，原样传递，不做 sRGB 转换（DS 对账 Q：线性/sRGB 分清）。

struct XmasGLBMaterial103 {
    var name: String = ""
    var baseColorFactor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var metallic: Float = 0
    var roughness: Float = 1
    var emissiveFactor: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var alphaBlend: Bool = false
    var doubleSided: Bool = false
    var baseColorTexture: Int? = nil   // index into model.textures
}

struct XmasGLBPrim103 {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>]? = nil
    var uvs: [SIMD2<Float>]? = nil
    var colors: [SIMD4<Float>]? = nil
    var indices: [UInt32] = []
    var material: Int = -1
}

struct XmasGLBInstance103 {
    var prim: XmasGLBPrim103
    var world: simd_float4x4
}

struct XmasGLBModel103 {
    var materials: [XmasGLBMaterial103] = []
    var textures: [CGImage] = []
    var instances: [XmasGLBInstance103] = []
    var boundsMin: SIMD3<Float> = SIMD3<Float>(repeating: 0)
    var boundsMax: SIMD3<Float> = SIMD3<Float>(repeating: 0)
    var triangleCount: Int = 0
}

enum XmasGLB103 {

    static func load(url: URL) -> XmasGLBModel103? {
        guard let data = try? Data(contentsOf: url), data.count > 20 else { return nil }
        // GLB header: magic 'glTF', version, length; chunk0 JSON, chunk1 BIN.
        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        guard magic == 0x46546C67 else { return nil }
        let jsonLen = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) })
        let jsonData = data.subdata(in: 20..<(20 + jsonLen))
        let binOff = 20 + jsonLen + 8
        guard binOff < data.count,
              let root = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any]
        else { return nil }
        let bin = data.subdata(in: binOff..<data.count)

        let bufferViews = (root["bufferViews"] as? [[String: Any]]) ?? []
        let accessors = (root["accessors"] as? [[String: Any]]) ?? []

        func viewRange(_ vi: Int) -> (offset: Int, length: Int, stride: Int)? {
            guard bufferViews.indices.contains(vi) else { return nil }
            let bv = bufferViews[vi]
            let off = (bv["byteOffset"] as? Int) ?? 0
            let len = (bv["byteLength"] as? Int) ?? 0
            let stride = (bv["byteStride"] as? Int) ?? 0
            return (off, len, stride)
        }

        func accessorInfo(_ ai: Int) -> (view: Int, offset: Int, comp: Int, type: String, count: Int)? {
            guard accessors.indices.contains(ai) else { return nil }
            let a = accessors[ai]
            guard let view = a["bufferView"] as? Int,
                  let comp = a["componentType"] as? Int,
                  let type = a["type"] as? String,
                  let count = a["count"] as? Int else { return nil }
            return (view, (a["byteOffset"] as? Int) ?? 0, comp, type, count)
        }

        func compSize(_ comp: Int) -> Int {
            switch comp { case 5120, 5121: return 1; case 5122, 5123: return 2; case 5125, 5126: return 4; default: return 4 }
        }
        func typeCount(_ type: String) -> Int {
            switch type { case "SCALAR": return 1; case "VEC2": return 2; case "VEC3": return 3; case "VEC4": return 4; case "MAT4": return 16; default: return 1 }
        }

        /// 读一个 accessor 为 Float 数组（整型按 normalized 规则或
        /// 原值转 Float；索引读取走 readIndices）。
        func readFloats(_ ai: Int, normalized: Bool) -> [Float]? {
            guard let info = accessorInfo(ai), let vr = viewRange(info.view) else { return nil }
            let n = typeCount(info.type)
            let cs = compSize(info.comp)
            let stride = vr.stride > 0 ? vr.stride : cs * n
            var out = [Float](repeating: 0, count: info.count * n)
            let base = vr.offset + info.offset
            bin.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let p = raw.baseAddress else { return }
                for i in 0..<(info.count * n) {
                    let elem = i / n, lane = i % n
                    let off = base + elem * stride + lane * cs
                    guard off + cs <= bin.count else { continue }
                    switch info.comp {
                    case 5126: out[i] = p.loadUnaligned(fromByteOffset: off, as: Float.self)
                    case 5125: out[i] = Float(p.loadUnaligned(fromByteOffset: off, as: UInt32.self))
                    case 5123:
                        let v = p.loadUnaligned(fromByteOffset: off, as: UInt16.self)
                        out[i] = normalized ? Float(v) / 65535 : Float(v)
                    case 5121:
                        let v = p.loadUnaligned(fromByteOffset: off, as: UInt8.self)
                        out[i] = normalized ? Float(v) / 255 : Float(v)
                    case 5122:
                        let v = p.loadUnaligned(fromByteOffset: off, as: Int16.self)
                        out[i] = normalized ? max(Float(v) / 32767, -1) : Float(v)
                    case 5120:
                        let v = p.loadUnaligned(fromByteOffset: off, as: Int8.self)
                        out[i] = normalized ? max(Float(v) / 127, -1) : Float(v)
                    default: break
                    }
                }
            }
            return out
        }

        func readIndices(_ ai: Int) -> [UInt32]? {
            guard let info = accessorInfo(ai), let vr = viewRange(info.view) else { return nil }
            let cs = compSize(info.comp)
            let stride = vr.stride > 0 ? vr.stride : cs
            var out = [UInt32](repeating: 0, count: info.count)
            let base = vr.offset + info.offset
            bin.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let p = raw.baseAddress else { return }
                for i in 0..<info.count {
                    let off = base + i * stride
                    guard off + cs <= bin.count else { continue }
                    switch info.comp {
                    case 5125: out[i] = p.loadUnaligned(fromByteOffset: off, as: UInt32.self)
                    case 5123: out[i] = UInt32(p.loadUnaligned(fromByteOffset: off, as: UInt16.self))
                    case 5121: out[i] = UInt32(p.loadUnaligned(fromByteOffset: off, as: UInt8.self))
                    default: break
                    }
                }
            }
            return out
        }

        var model = XmasGLBModel103()

        // Images (embedded in BIN via bufferView).
        let images = (root["images"] as? [[String: Any]]) ?? []
        for img in images {
            var cg: CGImage? = nil
            if let bv = img["bufferView"] as? Int, let vr = viewRange(bv) {
                let sub = bin.subdata(in: vr.offset..<(vr.offset + vr.length))
                if let src = CGImageSourceCreateWithData(sub as CFData, nil),
                   CGImageSourceGetCount(src) > 0 {
                    cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
                }
            }
            if let cg { model.textures.append(cg) }
        }

        // Materials.
        let mats = (root["materials"] as? [[String: Any]]) ?? []
        for m in mats {
            var mat = XmasGLBMaterial103()
            mat.name = (m["name"] as? String) ?? ""
            if let pbr = m["pbrMetallicRoughness"] as? [String: Any] {
                if let bc = pbr["baseColorFactor"] as? [Double], bc.count >= 4 {
                    mat.baseColorFactor = SIMD4<Float>(Float(bc[0]), Float(bc[1]), Float(bc[2]), Float(bc[3]))
                }
                mat.metallic = Float((pbr["metallicFactor"] as? Double) ?? 0)
                mat.roughness = Float((pbr["roughnessFactor"] as? Double) ?? 1)
                if let tex = pbr["baseColorTexture"] as? [String: Any], let ti = tex["index"] as? Int {
                    mat.baseColorTexture = ti
                }
            }
            if let ef = m["emissiveFactor"] as? [Double], ef.count >= 3 {
                mat.emissiveFactor = SIMD3<Float>(Float(ef[0]), Float(ef[1]), Float(ef[2]))
            }
            mat.alphaBlend = ((m["alphaMode"] as? String) ?? "OPAQUE") == "BLEND"
            mat.doubleSided = (m["doubleSided"] as? Bool) ?? false
            model.materials.append(mat)
        }

        // Meshes → prims.
        let meshes = (root["meshes"] as? [[String: Any]]) ?? []
        var meshPrims: [[XmasGLBPrim103]] = []
        for mesh in meshes {
            var prims: [XmasGLBPrim103] = []
            for prim in (mesh["primitives"] as? [[String: Any]]) ?? [] {
                var p = XmasGLBPrim103()
                let attrs = (prim["attributes"] as? [String: Any]) ?? [:]
                if let ai = attrs["POSITION"] as? Int, let f = readFloats(ai, normalized: false) {
                    p.positions = stride(from: 0, to: f.count, by: 3).map { SIMD3<Float>(f[$0], f[$0 + 1], f[$0 + 2]) }
                }
                if let ai = attrs["NORMAL"] as? Int, let f = readFloats(ai, normalized: false) {
                    p.normals = stride(from: 0, to: f.count, by: 3).map { SIMD3<Float>(f[$0], f[$0 + 1], f[$0 + 2]) }
                }
                if let ai = attrs["TEXCOORD_0"] as? Int, let f = readFloats(ai, normalized: false) {
                    p.uvs = stride(from: 0, to: f.count, by: 2).map { SIMD2<Float>(f[$0], f[$0 + 1]) }
                }
                if let ai = attrs["COLOR_0"] as? Int,
                   let info = accessorInfo(ai), let f = readFloats(ai, normalized: true) {
                    let n = typeCount(info.type)
                    p.colors = stride(from: 0, to: f.count, by: n).map { i in
                        n >= 4 ? SIMD4<Float>(f[i], f[i + 1], f[i + 2], f[i + 3])
                               : SIMD4<Float>(f[i], f[i + 1], f[i + 2], 1)
                    }
                }
                if let ii = prim["indices"] as? Int, let idx = readIndices(ii) {
                    p.indices = idx
                } else {
                    p.indices = (0..<p.positions.count).map { UInt32($0) }
                }
                p.material = (prim["material"] as? Int) ?? -1
                prims.append(p)
            }
            meshPrims.append(prims)
        }

        // Nodes: local transform + hierarchy flatten.
        let nodes = (root["nodes"] as? [[String: Any]]) ?? []
        func localMatrix(_ node: [String: Any]) -> simd_float4x4 {
            if let m = node["matrix"] as? [Double], m.count == 16 {
                // glTF matrix is column-major — matches simd layout.
                return simd_float4x4(columns: (
                    SIMD4<Float>(Float(m[0]), Float(m[1]), Float(m[2]), Float(m[3])),
                    SIMD4<Float>(Float(m[4]), Float(m[5]), Float(m[6]), Float(m[7])),
                    SIMD4<Float>(Float(m[8]), Float(m[9]), Float(m[10]), Float(m[11])),
                    SIMD4<Float>(Float(m[12]), Float(m[13]), Float(m[14]), Float(m[15]))))
            }
            let t = (node["translation"] as? [Double]) ?? [0, 0, 0]
            let r = (node["rotation"] as? [Double]) ?? [0, 0, 0, 1]
            let s = (node["scale"] as? [Double]) ?? [1, 1, 1]
            let q = simd_quatf(ix: Float(r[0]), iy: Float(r[1]), iz: Float(r[2]), r: Float(r[3]))
            var mtx = simd_float4x4(q)
            mtx = mtx * simd_float4x4(diagonal: SIMD4<Float>(Float(s[0]), Float(s[1]), Float(s[2]), 1))
            mtx.columns.3 = SIMD4<Float>(Float(t[0]), Float(t[1]), Float(t[2]), 1)
            return mtx
        }
        var bMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var bMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        func walk(_ ni: Int, _ parent: simd_float4x4) {
            guard nodes.indices.contains(ni) else { return }
            let node = nodes[ni]
            let world = parent * localMatrix(node)
            if let mi = node["mesh"] as? Int, meshPrims.indices.contains(mi) {
                for prim in meshPrims[mi] where !prim.positions.isEmpty {
                    model.instances.append(XmasGLBInstance103(prim: prim, world: world))
                    model.triangleCount += prim.indices.count / 3
                    for v in prim.positions {
                        let w = world * SIMD4<Float>(v.x, v.y, v.z, 1)
                        let p = SIMD3<Float>(w.x, w.y, w.z)
                        bMin = simd_min(bMin, p); bMax = simd_max(bMax, p)
                    }
                }
            }
            for child in (node["children"] as? [Int]) ?? [] { walk(child, world) }
        }
        let scenes = (root["scenes"] as? [[String: Any]]) ?? []
        let roots = (scenes.first?["nodes"] as? [Int]) ?? nodes.indices.map { $0 }
        for r in roots { walk(r, matrix_identity_float4x4) }
        if bMin.x <= bMax.x { model.boundsMin = bMin; model.boundsMax = bMax }
        return model
    }
}
