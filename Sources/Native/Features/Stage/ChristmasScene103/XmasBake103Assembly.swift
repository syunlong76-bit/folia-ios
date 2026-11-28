import Foundation
import simd
import CoreGraphics

// (103) 场景装配：摆位/雪帽/光池/落点登记，逐项对照样板
// place* 函数与场景构建段（坐标均为样板原值）。

enum XmasBake103 {

    private static func loadModel(_ name: String) -> XmasGLBModel103? {
        let url = Bundle.main.url(forResource: name, withExtension: "glb", subdirectory: "ChristmasTown")
            ?? Bundle.main.url(forResource: name, withExtension: "glb")
        guard let url else { return nil }
        return XmasGLB103.load(url: url)
    }

    /// 样板 normalizeHeight 的矩阵等价：缩放 s=H/高，平移使
    /// bbox 中心 x/z 归零、minY 归零。
    private static func normMatrix(_ m: XmasGLBModel103, _ targetH: Float) -> simd_float4x4 {
        let h = max(m.boundsMax.y - m.boundsMin.y, 0.0001)
        let s = targetH / h
        let cx = (m.boundsMin.x + m.boundsMax.x) / 2
        let cz = (m.boundsMin.z + m.boundsMax.z) / 2
        return xmasM(-s * cx, -s * m.boundsMin.y, -s * cz) * xmasS(s, s, s)
    }
    private static func normSize(_ m: XmasGLBModel103, _ targetH: Float) -> SIMD3<Float> {
        let h = max(m.boundsMax.y - m.boundsMin.y, 0.0001)
        let s = targetH / h
        return (m.boundsMax - m.boundsMin) * s
    }

    static func build() -> XmasBakedScene103? {
        let names = ["house-cabin", "house-inn", "house-white", "pine", "lamp", "stall",
                     "fence", "present", "bench", "car", "mailbox", "belltower"]
        var models: [String: XmasGLBModel103] = [:]
        var scene = XmasBakedScene103()
        var texBase: [String: Int] = [:]
        for n in names {
            guard let m = loadModel(n) else { continue }
            models[n] = m
            texBase[n] = scene.glbTextures.count
            scene.glbTextures.append(contentsOf: m.textures)
        }
        guard models["house-cabin"] != nil else { return nil }

        let b = XmasBakeBuilder103()
        var rng = XmasRNG103(seed: 20261225)

        let snowParams = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0xc9d6e8), 1),
                                          roughness: 1, metallic: 0)
        let snowGroup = b.group("snowmat", snowParams)
        let sphereGeo = XmasGeo103.sphere()

        func snowCap(_ groupM: simd_float4x4, _ x: Float, _ y: Float, _ z: Float,
                     _ sx: Float, _ sy: Float, _ sz: Float, _ rx: Float = 0) {
            let m = groupM * xmasM(x, y, z) * xmasRx(rx) * xmasS(sx, sy, sz)
            b.addGeo(sphereGeo, world: m, group: snowGroup)
        }
        func contactShadow(_ x: Float, _ z: Float, _ sx: Float, _ sz: Float, _ op: Float) {
            scene.discs.append(XmasDiscRec103(center: SIMD3<Float>(x, 0.015, z),
                                              size: SIMD2<Float>(sx, sz), rotY: 0,
                                              color: SIMD4<Float>(0, 0, 0, op), kind: .shadow))
        }
        func warmPool(_ x: Float, _ z: Float, _ r: Float, _ op: Float) {
            scene.discs.append(XmasDiscRec103(center: SIMD3<Float>(x, 0.03, z),
                                              size: SIMD2<Float>(r * 2, r * 2), rotY: 0,
                                              color: SIMD4<Float>(xmasSRGB(0xff9a3c), op), kind: .poolWarm))
        }
        func place(_ modelName: String, _ H: Float, _ x: Float, _ y: Float, _ z: Float,
                   _ ry: Float, _ prefix: String,
                   _ override: @escaping (String, XmasMatParams103) -> XmasMatParams103 = { _, p in p })
            -> simd_float4x4 {
            guard let m = models[modelName] else { return matrix_identity_float4x4 }
            let g = xmasM(x, y, z) * xmasRy(ry)
            b.addModel(m, world: g * normMatrix(m, H), prefix: prefix,
                       texBase: texBase[modelName] ?? -1, override: override)
            return g
        }

        // ---------- 地面 ----------
        let groundParams = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x66799c), 1), roughness: 0.96)
        b.addGeo(XmasGeo103.ground(), world: matrix_identity_float4x4, group: b.group("ground", groundParams))
        let plazaParams = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x5f7194), 1), roughness: 1)
        b.addGeo(XmasGeo103.disc(), world: xmasM(0, 0.006, 0) * xmasS(6.4, 1, 6.4), group: b.group("plaza", plazaParams))
        let ringParams = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x46536c), 1), roughness: 1)
        b.addGeo(XmasGeo103.disc(), world: xmasM(0, 0.003, 0) * xmasS(7.4, 1, 7.4), group: b.group("ring", ringParams))
        let pathParams = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x4a5872), 1), roughness: 1)
        b.addGeo(XmasGeo103.box(), world: xmasM(3.1, 0.013, 8.6) * xmasRy(0.35) * xmasS(1.7, 0.02, 6.4),
                 group: b.group("path", pathParams))
        scene.discs.append(XmasDiscRec103(center: SIMD3<Float>(0, 0.01, 0), size: SIMD2<Float>(16.4, 16.4),
                                          rotY: 0, color: SIMD4<Float>(1, 1, 1, 0.85), kind: .treePool))
        // 树裙锥（0x5e1620）
        let skirtParams = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x5e1620), 1), roughness: 0.8)
        b.addGeo(XmasGeo103.cylinder(rTop: 0, rBottom: 1, seg: 20),
                 world: xmasM(0, 0.15, 0) * xmasS(1.05, 0.3, 1.05), group: b.group("skirt", skirtParams))
        // 地面随机雪堆 ×8
        for _ in 0..<8 {
            let ang = rng.next() * 2 * Float.pi
            let rad = 6.5 + rng.next() * 8.5
            snowCap(matrix_identity_float4x4, cos(ang) * rad, 0.02, sin(ang) * rad,
                    0.8 + rng.next() * 0.9, 0.06, 0.8 + rng.next() * 0.9)
        }

        // ---------- 房屋 ----------
        struct HouseProps { let ridge: Float; let eave: Float; let halfD: Float; let halfW: Float }
        let propsCabin = HouseProps(ridge: 0.86, eave: 0.55, halfD: 0.36, halfW: 0.44)
        let propsInn = HouseProps(ridge: 0.95, eave: 0.62, halfD: 0.34, halfW: 0.42)
        let propsWhite = HouseProps(ridge: 0.94, eave: 0.60, halfD: 0.33, halfW: 0.40)

        func placeHouse(_ modelName: String, _ props: HouseProps, _ x: Float, _ z: Float,
                        _ ry: Float, _ H: Float, _ porch: Bool, _ prefix: String,
                        _ override: @escaping (String, XmasMatParams103) -> XmasMatParams103) {
            let g = place(modelName, H, x, 0, z, ry, prefix, override)
            contactShadow(x, z, H * 1.55, H * 1.3, 0.5)
            let ridgeY = H * props.ridge, eaveY = H * props.eave
            let halfD = H * props.halfD, halfW = H * props.halfW
            snowCap(g, 0, ridgeY - 0.06, 0, halfW * 0.8, 0.09, halfD * 0.22)
            snowCap(g, 0, eaveY + 0.02, halfD, halfW * 0.88, 0.05, 0.11)
            snowCap(g, 0, eaveY + 0.02, -halfD, halfW * 0.88, 0.05, 0.11)
            for f in [Float(-0.55), Float(0), Float(0.55)] {
                let w = xmasLocalToWorld(x, z, ry, f * halfW * 1.5, 0)
                scene.flats.append(XmasFlat103(x: w.0, z: w.1, y: ridgeY + 0.05, r: 0.62))
            }
            for f in [Float(-0.5), Float(0.5)] {
                for lz in [halfD, -halfD] {
                    let w = xmasLocalToWorld(x, z, ry, f * halfW * 1.5, lz)
                    scene.flats.append(XmasFlat103(x: w.0, z: w.1, y: eaveY + 0.06, r: 0.5))
                }
            }
            if porch {
                let fw = xmasLocalToWorld(x, z, ry, 2.1, 3.1)
                scene.porchPos.append(SIMD3<Float>(fw.0, 1.6, fw.1))
                warmPool(fw.0, fw.1, 2.1, 0.22)
            }
        }

        let cabinEmissive: (String, XmasMatParams103) -> XmasMatParams103 = { name, p in
            var p = p
            if name == "mat24" {
                p.emissiveColor = SIMD3<Float>(1.0, 0.58, 0.22); p.emissiveIntensity = 2.4
                p.breathSp = 0.9; p.breathPh = 1.7
            }
            return p
        }
        let innEmissive: (String, XmasMatParams103) -> XmasMatParams103 = { name, p in
            var p = p
            if name == "Windows" {
                p.emissiveColor = SIMD3<Float>(1, 0.62, 0.26); p.emissiveIntensity = 2.6
                p.breathSp = 0.7; p.breathPh = 4.2
            }
            return p
        }
        let whiteEmissive: (String, XmasMatParams103) -> XmasMatParams103 = { name, p in
            var p = p
            if name == "DarkGrey" { p.emissiveColor = SIMD3<Float>(1, 0.6, 0.24); p.emissiveIntensity = 1.7 }
            return p
        }
        placeHouse("house-cabin", propsCabin, -8.2, -6.4, 0.62, 5.6, true, "cabin", cabinEmissive)
        placeHouse("house-inn", propsInn, 7.6, -7.4, -0.55, 6.6, true, "inn", innEmissive)
        placeHouse("house-white", propsWhite, 0.8, -13.2, 0.12, 6.2, false, "white", whiteEmissive)
        placeHouse("house-inn", propsInn, -12.8, 1.6, 1.25, 5.6, false, "inn", innEmissive)
        placeHouse("house-white", propsWhite, 13.0, 0.8, -1.15, 5.9, false, "white", whiteEmissive)
        // 烟囱烟锚点（cabin 局部 (1.76,-0.52) → 世界，y 5.95）
        let chim = xmasLocalToWorld(-8.2, -6.4, 0.62, 1.76, -0.52)
        scene.smokeAnchors.append(SIMD3<Float>(chim.0, 5.95, chim.1))

        // ---------- 松树 + 远景剪影 ----------
        func placePine(_ x: Float, _ z: Float, _ h: Float, _ rot: Float) {
            _ = place("pine", h, x, 0, z, rot, "pine")
            contactShadow(x, z, 1.8, 1.8, 0.5)
        }
        placePine(-5.2, -3.0, 4.6, 0.7)
        placePine(4.7, -3.6, 5.5, 2.4)
        placePine(-6.1, 0.8, 3.4, 1.5)
        placePine(10.6, -4.6, 6.8, 0.4)
        placePine(-11.5, -3.4, 5.8, 2.9)
        placePine(3.2, 5.6, 3.1, 1.1)
        placePine(-3.9, 4.9, 2.8, 2.2)
        let silhouette: (String, XmasMatParams103) -> XmasMatParams103 = { _, _ in
            XmasMatParams103(baseColor: SIMD4<Float>(0, 0, 0, 1),
                             emissiveColor: xmasSRGB(0x0a141f), emissiveIntensity: 1, roughness: 1)
        }
        for cfg in [(Float(-12), Float(-15.5), Float(9)), (Float(8.5), Float(-16.5), Float(10.5)), (Float(14), Float(-10.5), Float(8)), (Float(-15.5), Float(-8), Float(7.5))] {
            _ = place("pine", cfg.2, cfg.0, -0.1, cfg.1, 0, "silh", silhouette)
        }
        _ = place("house-white", 7.2, -11, -0.1, -18.5, 0.4, "silh", silhouette)

        // ---------- 钟楼 ----------
        let towerEmissive: (String, XmasMatParams103) -> XmasMatParams103 = { name, p in
            var p = p
            if name == "Windows" {
                p.emissiveColor = SIMD3<Float>(1, 0.66, 0.3); p.emissiveIntensity = 1.9
                p.breathSp = 0.5; p.breathPh = 2.6
            }
            return p
        }
        _ = place("belltower", 11.5, -4.0, -0.15, -19.0, 0.15, "tower", towerEmissive)
        contactShadow(-4.0, -19.0, 7.5, 6.5, 0.4)
        scene.glows.append(XmasGlowRec103(center: SIMD3<Float>(-4.0, 4.6, -18.6), scale: 2.6,
                                          color: SIMD3<Float>(1.3, 0.85, 0.4), opacity: 0.3))

        // ---------- 路灯 ----------
        let lampEmissive: (String, XmasMatParams103) -> XmasMatParams103 = { name, p in
            var p = p
            if name == "lambert4SG" { p.emissiveColor = SIMD3<Float>(1, 0.82, 0.55); p.emissiveIntensity = 5.0 }
            return p
        }
        let lampCapGeo = XmasGeo103.cylinder(rTop: 0.17, rBottom: 0.2, seg: 10)
        func placeLamp(_ x: Float, _ z: Float, _ withLight: Bool) {
            _ = place("lamp", 3.3, x, 0, z, 0, "lamp", lampEmissive)
            scene.lampTops.append(SIMD3<Float>(x, 3.15, z))
            contactShadow(x, z, 1.3, 1.3, 0.55)
            warmPool(x, z, 3.0, 0.30)
            scene.glows.append(XmasGlowRec103(center: SIMD3<Float>(x, 3.05, z), scale: 1.7,
                                              color: SIMD3<Float>(1.6, 1.05, 0.5), opacity: 0.32))
            b.addGeo(lampCapGeo, world: xmasM(x, 3.37, z) * xmasS(1, 0.07, 1), group: snowGroup)
            scene.flats.append(XmasFlat103(x: x, z: z, y: 3.44, r: 0.2))
            if withLight {
                scene.lampDynPos.append(SIMD3<Float>(x, 3.05, z))
                scene.lampDynPh.append(rng.next() * 6)
            }
        }
        placeLamp(6.0, 1.6, true)
        placeLamp(-6.2, 2.2, true)
        placeLamp(3.6, -6.6, false)
        placeLamp(-3.9, -6.9, false)
        placeLamp(9.2, -2.6, false)

        // ---------- 摊位 ----------
        func placeStall(_ x: Float, _ z: Float, _ ry: Float, _ roof: UInt32, _ kind: String) {
            let roofOverride: (String, XmasMatParams103) -> XmasMatParams103 = { name, p in
                var p = p
                if name == "RoofTiles_Red" { p.baseColor = SIMD4<Float>(xmasSRGB(roof), 1) }
                return p
            }
            let g = place("stall", 2.9, x, 0, z, ry, "stall", roofOverride)
            // 货品（group 局部坐标，样板 goods 同值）
            switch kind {
            case "ornaments":
                let cols: [UInt32] = [0xff5148, 0xffc44d, 0x5c99ff, 0xff8cc7, 0x7dffb8]
                for gi in 0..<7 {
                    let c = xmasSRGB(cols[gi % 5])
                    let gp = XmasMatParams103(baseColor: SIMD4<Float>(c, 1), emissiveColor: c,
                                              emissiveIntensity: 0.35, roughness: 0.35)
                    b.addGeo(sphereGeo, world: g * xmasM(-0.75 + Float(gi) * 0.25, 1.12, 0.62) * xmasS(0.11, 0.11, 0.11),
                             group: b.group("goods-orn-\(gi % 5)", gp))
                }
            case "ginger":
                let gp = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x9a6136), 1), roughness: 0.9)
                let gg = b.group("goods-ginger", gp)
                for gi in 0..<5 {
                    b.addGeo(XmasGeo103.box(),
                             world: g * xmasM(-0.6 + Float(gi) * 0.3, 1.1, 0.62) * xmasRy((rng.next() - 0.5) * 0.5) * xmasS(0.3, 0.14, 0.24),
                             group: gg)
                }
            case "chestnuts":
                let gp = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x4a2c17), 1), roughness: 0.7)
                let gg = b.group("goods-nuts", gp)
                for _ in 0..<9 {
                    b.addGeo(sphereGeo,
                             world: g * xmasM(-0.5 + rng.next() * 1.0, 1.08 + rng.next() * 0.08, 0.62 + (rng.next() - 0.5) * 0.2) * xmasS(0.07, 0.07, 0.07),
                             group: gg)
                }
            default: // drinks
                let gp = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0xf3e6cf), 1), roughness: 0.6)
                let gg = b.group("goods-cups", gp)
                for gi in 0..<4 {
                    b.addGeo(XmasGeo103.cylinder(rTop: 0.07, rBottom: 0.055, seg: 10),
                             world: g * xmasM(-0.45 + Float(gi) * 0.3, 1.13, 0.62) * xmasS(1, 0.16, 1),
                             group: gg)
                }
            }
            contactShadow(x, z, 4.2, 3.2, 0.5)
            snowCap(g, 0, 2.98, 0, 1.35, 0.09, 0.95)
            scene.flats.append(XmasFlat103(x: x, z: z, y: 3.06, r: 0.95))
            let fw = xmasLocalToWorld(x, z, ry, 0, 2.2)
            warmPool(fw.0, fw.1, 1.9, 0.2)
            if kind == "drinks" { scene.smokeAnchors.append(SIMD3<Float>(fw.0, 1.5, fw.1)) }
        }
        placeStall(-8.8, -11.2, 0.30, 0xb3402f, "chestnuts")
        placeStall(-5.2, -12.4, 0.15, 0x2f6e4f, "drinks")
        placeStall(-1.6, -13.0, 0.03, 0xb3402f, "ornaments")
        placeStall(2.0, -13.2, -0.05, 0xc9862f, "ginger")

        // ---------- 长椅 ----------
        func placeBench(_ a: Float) {
            let x = cos(a) * 5.7, z = sin(a) * 5.7
            let ry = -a - Float.pi / 2
            let g = place("bench", 1.3, x, 0, z, ry, "bench")
            snowCap(g, 0, 0.66, 0.05, 1.05, 0.06, 0.3)
            snowCap(g, 0, 1.3, -0.3, 1.05, 0.05, 0.1)
            contactShadow(x, z, 2.6, 1.4, 0.45)
            for off in [Float(-0.55), Float(0.55)] {
                let w = xmasLocalToWorld(x, z, ry, off, 0.05)
                scene.flats.append(XmasFlat103(x: w.0, z: w.1, y: 0.7, r: 0.62))
                let w2 = xmasLocalToWorld(x, z, ry, off, -0.3)
                scene.flats.append(XmasFlat103(x: w2.0, z: w2.1, y: 1.34, r: 0.5))
            }
            scene.benches.append(XmasBenchReg103(x: x, z: z, ry: ry))
        }
        for a in [Float(-0.75), Float(0.45), Float(1.65)] { placeBench(a) }

        // ---------- 汽车 ----------
        func placeCar(_ x: Float, _ z: Float, _ ry: Float, _ tint: UInt32?) {
            guard let m = models["car"] else { return }
            let carOverride: (String, XmasMatParams103) -> XmasMatParams103 = { name, p in
                var p = p
                if name == "Headlights" { p.emissiveColor = SIMD3<Float>(1, 0.85, 0.58); p.emissiveIntensity = 3.2 }
                if name == "TailLights" { p.emissiveColor = SIMD3<Float>(1, 0.16, 0.12); p.emissiveIntensity = 2.2 }
                if name == "LightBlue", let tint { p.baseColor = SIMD4<Float>(xmasSRGB(tint), 1) }
                return p
            }
            let size = normSize(m, 1.5)
            let g = xmasM(x, 0, z) * xmasRy(ry)
            var inner = matrix_identity_float4x4
            if size.z > size.x { inner = xmasRy(Float.pi / 2) }
            b.addModel(m, world: g * inner * normMatrix(m, 1.5), prefix: "car",
                       texBase: texBase["car"] ?? -1, override: carOverride)
            let len = max(size.x, size.z), wid = min(size.x, size.z)
            snowCap(g, 0, 1.53, 0, len * 0.3, 0.055, wid * 0.36)
            contactShadow(x, z, len * 1.05, wid * 1.25, 0.5)
            scene.flats.append(XmasFlat103(x: x, z: z, y: 1.6, r: 0.85))
            let f1 = xmasLocalToWorld(x, z, ry, len / 2 + 1.1, wid * 0.28)
            let f2 = xmasLocalToWorld(x, z, ry, len / 2 + 1.1, -wid * 0.28)
            warmPool(f1.0, f1.1, 1.7, 0.3)
            warmPool(f2.0, f2.1, 1.7, 0.3)
            let hg = xmasLocalToWorld(x, z, ry, len / 2 + 0.15, 0)
            scene.glows.append(XmasGlowRec103(center: SIMD3<Float>(hg.0, 0.55, hg.1), scale: 1.5,
                                              color: SIMD3<Float>(1.5, 1.1, 0.6), opacity: 0.3))
            let tg = xmasLocalToWorld(x, z, ry, -len / 2 - 0.1, 0)
            scene.glows.append(XmasGlowRec103(center: SIMD3<Float>(tg.0, 0.6, tg.1), scale: 0.9,
                                              color: SIMD3<Float>(1.4, 0.25, 0.18), opacity: 0.3))
        }
        placeCar(-7.3, 11.3, 0.06, nil)
        placeCar(7.5, 11.5, -0.04, 0xa33327)

        // ---------- 雪人（-6.3, 0, -1.6, ry 0.7） ----------
        do {
            let g = xmasM(-6.3, 0, -1.6) * xmasRy(0.7)
            let snowM = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0xe9eff7), 1), roughness: 0.95)
            let sg = b.group("snowman", snowM)
            for (r, y) in [(Float(0.62), Float(0.55)), (Float(0.45), Float(1.32)), (Float(0.32), Float(1.92))] {
                b.addGeo(sphereGeo, world: g * xmasM(0, y, 0) * xmasS(r, r, r), group: sg)
            }
            let coal = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x14161c), 1), roughness: 0.6)
            let cg = b.group("snowman-coal", coal)
            for c in [(Float(-0.1), Float(2.02), Float(0.27)), (Float(0.1), Float(2.02), Float(0.27)), (Float(0), Float(1.42), Float(0.42)), (Float(0), Float(1.24), Float(0.44)), (Float(0), Float(0.72), Float(0.56))] {
                b.addGeo(sphereGeo, world: g * xmasM(c.0, c.1, c.2) * xmasS(0.035, 0.035, 0.035), group: cg)
            }
            let carrot = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0xe07b2a), 1), roughness: 0.8)
            b.addGeo(XmasGeo103.cylinder(rTop: 0, rBottom: 1, seg: 10),
                     world: g * xmasM(0, 1.94, 0.42) * xmasRx(Float.pi / 2) * xmasS(0.07, 0.36, 0.07),
                     group: b.group("snowman-carrot", carrot))
            let hat = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x1b1e26), 1), roughness: 0.7)
            let hg = b.group("snowman-hat", hat)
            b.addGeo(XmasGeo103.cylinder(rTop: 1, rBottom: 1, seg: 16),
                     world: g * xmasM(0, 2.18, 0) * xmasS(0.4, 0.05, 0.4), group: hg)
            b.addGeo(XmasGeo103.cylinder(rTop: 0.92, rBottom: 1, seg: 16),
                     world: g * xmasM(0, 2.34, 0) * xmasS(0.26, 0.3, 0.26), group: hg)
            let scarf = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x9e2436), 1), roughness: 0.95)
            b.addGeo(XmasGeo103.torus(R: 0.3, tube: 0.09),
                     world: g * xmasM(0, 1.64, 0) * xmasRx(Float.pi / 2), group: b.group("snowman-scarf", scarf))
            let armM = XmasMatParams103(baseColor: SIMD4<Float>(xmasSRGB(0x4c3621), 1), roughness: 0.95)
            let ag = b.group("snowman-arm", armM)
            for sgn in [Float(-1), 1] {
                b.addGeo(XmasGeo103.cylinder(rTop: 0.6, rBottom: 1, seg: 6),
                         world: g * xmasM(sgn * 0.5, 1.42, 0) * xmasRz(sgn * 1.05) * xmasS(0.025, 0.7, 0.025),
                         group: ag)
            }
        }

        // ---------- 信箱 ----------
        _ = place("mailbox", 1.2, 7.7, 0, -3.3, -0.5, "mailbox")
        contactShadow(7.7, -3.3, 1.1, 1.1, 0.5)
        snowCap(xmasM(7.7, 0, -3.3) * xmasRy(-0.5), 0, 1.24, 0, 0.34, 0.06, 0.3)
        scene.flats.append(XmasFlat103(x: 7.7, z: -3.3, y: 1.3, r: 0.3))

        // ---------- 栅栏环（半径 4.05、11 段、朝相机缺口） ----------
        if let fence = models["fence"] {
            let dim: (String, XmasMatParams103) -> XmasMatParams103 = { _, p in
                var p = p
                p.baseColor = SIMD4<Float>(p.baseColor.x * 0.7, p.baseColor.y * 0.7, p.baseColor.z * 0.7, p.baseColor.w)
                return p
            }
            let sz = fence.boundsMax - fence.boundsMin
            let sx = 2.6 / max(sz.x, 0.001), sy = (0.8 / max(sz.y, 0.001)) * 1.18
            let camAng = atan2(cos(Float(0.55)), sin(Float(0.55)))
            for k in 0..<11 {
                let a = Float(k) / 11 * 2 * Float.pi + 0.35
                var diff = abs((a - camAng).truncatingRemainder(dividingBy: 2 * Float.pi))
                if diff > Float.pi { diff = 2 * Float.pi - diff }
                // 样板式：diff 为与 camAng 的最短角距；> π-0.85 时跳过
                // （等价于样板把角距折到 [0,π] 后的同一判定）
                if Float.pi - diff < 0.85 { continue }
                let px = cos(a) * 4.05, pz = sin(a) * 4.05
                let sbMin = SIMD3<Float>(fence.boundsMin.x * sx, fence.boundsMin.y * sy, fence.boundsMin.z * sx)
                let sbMax = SIMD3<Float>(fence.boundsMax.x * sx, fence.boundsMax.y * sy, fence.boundsMax.z * sx)
                let cc = (sbMin + sbMax) / 2
                let world = xmasM(px - cc.x, -sbMin.y, pz - cc.z) * xmasRy(-a + Float.pi / 2) * xmasS(sx, sy, sx)
                b.addModel(fence, world: world, prefix: "fence", texBase: texBase["fence"] ?? -1, override: dim)
            }
        }

        // ---------- 礼物 ×7 ----------
        if models["present"] != nil {
            let tints: [UInt32] = [0xffffff, 0xffe3d0, 0xd8ecff, 0xfff2c8, 0xffd8e2, 0xe6ffd8, 0xffffff]
            var prng = XmasRNG103(seed: 777)
            for pi in 0..<7 {
                let ph = 0.45 + prng.next() * 0.35
                let pa = prng.next() * 2 * Float.pi
                let prad = 1.25 + prng.next() * 0.9
                let px2 = cos(pa) * prad, pz2 = sin(pa) * prad
                let ry = prng.next() * Float.pi
                let tint = xmasSRGB(tints[pi % tints.count])
                let tintOverride: (String, XmasMatParams103) -> XmasMatParams103 = { _, p in
                    var p = p
                    p.baseColor = SIMD4<Float>(tint, p.baseColor.w)
                    return p
                }
                _ = place("present", ph, px2, 0, pz2, ry, "present\(pi)", tintOverride)
                scene.flats.append(XmasFlat103(x: px2, z: pz2, y: ph * 0.98, r: ph * 0.55))
            }
            contactShadow(0, 0, 5.8, 5.8, 0.38)
        }

        // ---------- 收尾 ----------
        let fin = b.finish()
        scene.positions = fin.positions
        scene.normals = fin.normals
        scene.uvs = fin.uvs
        scene.colors = fin.colors
        scene.indices = fin.indices
        scene.groups = fin.groups
        scene.boundsMin = fin.boundsMin
        scene.boundsMax = fin.boundsMax
        scene.vertexCount = fin.positions.count / 3
        scene.triangleCount = fin.indices.count / 3
        return scene
    }
}
