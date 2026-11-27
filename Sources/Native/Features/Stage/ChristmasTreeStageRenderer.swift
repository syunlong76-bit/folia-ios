import UIKit
import QuartzCore
import MetalKit

// 圣诞树 christmas（(93) 新增原生歌词样式）：粒子圣诞树＋无人机
// 环绕镜头，当前行歌词由雪粒汇聚成形、唱完碎散成雪。参数口径
// 对齐网页样片（sheng-dan-ge-ci-te-xiao-yang-pian）：
//  - 粒子分账（(94) 94-8 按样片拆账，不再 7100 混编）：歌词
//    粒子池 3000 独立成账；树粒子 3000（金链螺旋 340 为树
//    装饰子账）；雪/星尘余量另账＝远雪 650＋近雪 110＝760。
//    三账合计仍 7100（粒子总数不变、只拆账）。
//  - 聚字时序：汇聚 1.0s（easeOutBack、逐粒延迟 ≤0.55s）→ 停留
//    → 行末 0.8s 碎散成雪；5s 行时停留恰至 4.2s，与样片一致
//    （长行停留随行长延长，汇聚/碎散时长不随行长变）。
//  - 歌词采样：离屏 1200×300 渲染当前行、步长 2 采样 alpha，
//    字宽约屏宽 97%（fitW = min(7.4, 可见宽×0.97)），行位在树
//    前偏下暗区（LYRIC_CENTER y=1.45、向镜头拉近 3.6）。
//  - 镜头：40s 一圈环绕＋13s 周期升降呼吸（幅 0.38）＋半径
//    20s 周期微摆（幅 0.25）；竖屏半径 11.9、横屏 8.6。
// 时钟纪律：只消费宿主 frameTick（内部仅以相邻 tick 的墙钟差
// 累计动画相位），不自建 CADisplayLink。绘制纪律：全部粒子走
// 预烘焙精灵贴图在 draw 里批量贴，不逐粒建视图、不逐帧建路
// 径、无全屏 CPU 滤镜。

// MARK: - 确定性伪随机（样片 mulberry32 / hash01 同义实现）

private func p93Mulberry32(seed: UInt32) -> () -> Double {
    var a = seed
    return {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
    }
}

private func p93Hash01(_ n: Double) -> Double {
    let x = sin(n * 127.1 + 311.7) * 43758.5453
    return x - floor(x)
}

// MARK: - 画布视图（(97) 第 2 条起为 Metal 画布，见
// ChristmasMetal97.swift；layout 转发保留旧语义）

// MARK: - 渲染方

final class ChristmasTreeStageRenderer: LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    // (97) 第 2 条：GPU 画布＋批量绘制器（旧 CG 逐帧全量重画退役）。
    private let canvas = XmasMetalCanvas97()
    private let metal97 = XmasMetalRenderer97()
    private var frameSprites97: [XmasSpriteInstance97] = []
    private var guardLogged98a = false
    private var guardLogged98b = false
    private var frameTris97: [XmasSolidTri97] = []
    private var atlasReady97 = false
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    private var isActive = false

    // 粒子分账常量（(94) 94-8，样片口径）：歌词池独立 3000；
    // 树池 3000（金链 340 为其装饰子账）；雪/星尘余量另账
    // 760（远 650＋近 110）。mount 面包屑逐账落数。
    private static let lyricCount = 3000
    private static let treeCount = 3000
    private static let garlandCount = 340
    private static let snowFarCount = 650
    private static let snowNearCount = 110
    static var snowAccount: Int { snowFarCount + snowNearCount }
    static var totalParticles: Int {
        lyricCount + treeCount + garlandCount + snowAccount
    }

    // 树体/金链：静态 3D 点 + 精灵档下标（烘焙时定版）
    private var treePos: [Float] = []
    private var treeSprite: [UInt8] = []
    private var garlandPos: [Float] = []
    // 环境雪：种子（x0/速度/相位）+ 初始 y 由相位推
    private var snowFarSeed: [Float] = []
    private var snowNearSeed: [Float] = []
    // 歌词粒：逐粒性状（样片 initTraits）
    private var pDelay: [Float] = []
    private var pTwinkle: [Float] = []
    private var pTint: [Float] = []
    private var pDrift: [Float] = []

    // 精灵贴图（预烘焙）：0…3 树绿四档、4 金灯、5 红灯、6 冰晶、
    // 7 金链、8 歌词金白芯、9 红 spark、10 绿 spark、11 雪点、
    // 12 深色描边晕、13 金星、14 地面暖光池、15 歌词带暗椭圆衬底
    private var sprites: [CGImage?] = []
    private var spritesReady = false
    /// (94) 94-8：精灵烘焙时的屏幕 scale（渲染时动态读
    /// UIScreen.main.scale、不写死不封顶）；scale 变化（换
    /// 机/旋转不改 scale，此为兜底）时整表重烘。
    private var bakedScale94: CGFloat = 0

    // 相机/动画相位（frameTick 累计，宿主驱动）
    private var elapsed: TimeInterval = 0
    private var lastTickWall: TimeInterval? = nil
    // 当前行与采样目标
    private var currentLineIndex: Int = -1
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var linePoints: [CGPoint] = []   // 归一化采样点 x∈[-.5,.5] y∈[-.5,.5]
    private var targets: [Float] = []        // 歌词粒目标（歌词平面局部坐标 ×3）
    private var targetsDirty = true
    private var sizeDirty = true
    // fps 面包屑统计（约 5s 一行）
    private var fpsAccum: TimeInterval = 0
    private var fpsFrames = 0
    private var fpsWindow: TimeInterval = 0

    init() {
        view = canvas
        // (97) 第 2 条：Metal 画布口径——手动驱动（isPaused，
        // 与宿主 frameTick 同拍）、drawable 原生分辨率（默认
        // 跟随屏幕 scale、不降清不封顶）、清屏色＝旧画布底色。
        canvas.device = MTLCreateSystemDefaultDevice()
        canvas.colorPixelFormat = .bgra8Unorm
        canvas.clearColor = MTLClearColor(red: 0.016, green: 0.086, blue: 0.051, alpha: 1) // #04160d 样片底
        canvas.isPaused = true
        canvas.enableSetNeedsDisplay = false
        canvas.framebufferOnly = true
        canvas.delegate = metal97
        metal97.configure(view: canvas)
        canvas.backgroundColor = UIColor(red: 0.016, green: 0.086, blue: 0.051, alpha: 1)
        canvas.isUserInteractionEnabled = false
        buildPools()
        canvas.onLayout97 = { [weak self] in
            // 横竖屏/尺寸变化：标脏，下一帧重算投影与目标（样片 layout() 同义）
            self?.sizeDirty = true
            self?.targetsDirty = true
        }
        Breadcrumbs.log("p97 xmas gpu=\(metal97.isReady ? 1 : 0)")
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
        bakeSpritesIfNeeded()
        // (97) 第 2 条：精灵表→GPU 图集（装配期一次建好，首帧
        // 不再付 CG 全量绘制的钱——(96) 进入冻结 1056ms 的主项）。
        atlasReady97 = metal97.buildAtlas(sprites: sprites)
        Breadcrumbs.log("p97 xmas atlas=\(atlasReady97 ? 1 : 0)")
        Breadcrumbs.log("p93 xmas on n=\(Self.totalParticles)")
        // (94) 94-8：分账/scale/纹理账同行自证（纹理对 ≤250MB 口径）。
        Breadcrumbs.log("p94 xmas pools lyric=\(Self.lyricCount) tree=\(Self.treeCount)"
            + " garland=\(Self.garlandCount) snow=\(Self.snowAccount) total=\(Self.totalParticles)")
        Breadcrumbs.log("p94 xmas scale=\(String(format: "%.1f", UIScreen.main.scale))"
            + " tex=\(String(format: "%.1f", textureMB94()))MB")
    }

    /// (94) 94-8：精灵纹理账（CGImage 像素×4B 求和，MB）。
    private func textureMB94() -> Double {
        var bytes = 0
        for img in sprites {
            if let img { bytes += img.width * img.height * 4 }
        }
        return Double(bytes) / 1_000_000.0
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        self.snapshot = snapshot
        if snapshot.track?.id != builtTrackId || snapshot.lines.count != builtLineCount {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            currentLineIndex = -1
            linePoints = []
            targetsDirty = true
        }
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if !isActive { lastTickWall = nil }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let now = CACurrentMediaTime()
        if let last = lastTickWall {
            let dt = now - last
            if dt > 0 && dt < 0.5 { elapsed += dt }
            noteFrameInterval(dt)
        }
        lastTickWall = now

        // 行推进判定（参照 corridor：LyricParser.currentIndex 对照 position）
        let idx = LyricParser.currentIndex(in: snapshot.lines, at: position) ?? -1
        if idx != currentLineIndex {
            currentLineIndex = idx
            if idx >= 0 && snapshot.lines.indices.contains(idx) {
                sampleLine(snapshot.lines[idx].text)
            } else {
                linePoints = []
            }
            targetsDirty = true
        }
        if targetsDirty { rebuildTargets() }
        // (97) 第 2 条：逐帧只算实例数组，GPU 一次提交（旧
        // setNeedsDisplay→CG draw 全量重画退役）。
        if atlasReady97, metal97.isReady, canvas.bounds.width > 0 {
            buildFrame97(rect: canvas.bounds)
            metal97.submit(sprites: frameSprites97, tris: frameTris97,
                            viewSize: canvas.bounds.size)
            canvas.draw()
        }
    }

    func unmount() {
        // (94) 94-8：样式切出释放全部精灵纹理并落释放账。
        if spritesReady { Breadcrumbs.log("p94 xmas tex=0.0MB off") }
        isActive = false
        sprites = []
        spritesReady = false
        atlasReady97 = false
        metal97.clearAtlas()
        bakedScale94 = 0
        treePos = []; treeSprite = []; garlandPos = []
        snowFarSeed = []; snowNearSeed = []
        pDelay = []; pTwinkle = []; pTint = []; pDrift = []
        linePoints = []; targets = []
        context = nil
        snapshot = nil
    }

    // MARK: fps 面包屑（约 5s 一行：帧间隔均值对账）

    private func noteFrameInterval(_ dt: TimeInterval) {
        guard dt > 0 && dt < 0.5 else { return }
        fpsAccum += dt
        fpsFrames += 1
        fpsWindow += dt
        if fpsWindow >= 5.0 && fpsFrames > 0 {
            let avg = fpsAccum / Double(fpsFrames)
            // (97) 第 2 条：帧采样加记 footprint——(96) 两会话
            // 卡/流畅的差异点在内存（311–345MB vs 155–197MB），
            // 往后判读须有同行协变量。
            Breadcrumbs.log("p94 xmas fps=\(String(format: "%.1f", 1.0 / avg)) avgMs=\(String(format: "%.2f", avg * 1000)) fp=\(Breadcrumbs.footprintMB97())")
            Breadcrumbs.log("p98 xmas spr n=\(metal97.lastSprCount98) tri=\(metal97.lastTriCount98 * 3)")
            fpsAccum = 0; fpsFrames = 0; fpsWindow = 0
        }
    }

    // MARK: 粒子池构建（种子与样片一致）

    private func treeRadius(_ y: Double) -> Double {
        2.3 * pow(1 - y / 4.6, 0.92) + 0.04
    }

    private func buildPools() {
        // 树体：rng 种子 20261225、y 分布 pow(r,0.82)、色板同
        // 样片（金灯 10%、红灯 3.5%、冰晶 2%、余绿四档）
        let rng = p93Mulberry32(seed: 20261225)
        let greens: [[Double]] = [[0.05, 0.36, 0.18], [0.07, 0.48, 0.25], [0.04, 0.29, 0.15], [0.1, 0.55, 0.28]]
        treePos = [Float](repeating: 0, count: Self.treeCount * 3)
        treeSprite = [UInt8](repeating: 0, count: Self.treeCount)
        for i in 0..<Self.treeCount {
            let y = pow(rng(), 0.82) * 4.6
            let r = treeRadius(y) * sqrt(rng())
            let th = rng() * .pi * 2
            treePos[i * 3] = Float(cos(th) * r)
            treePos[i * 3 + 1] = Float(0.35 + y)
            treePos[i * 3 + 2] = Float(sin(th) * r)
            let pick = rng()
            if pick > 0.9 { treeSprite[i] = 4 }        // 暖金灯（精灵档 4）
            else if pick > 0.865 { treeSprite[i] = 5 } // 红灯（档 5）
            else if pick > 0.845 { treeSprite[i] = 6 } // 冰晶（档 6）
            else {
                let gv = greens[Int(rng() * Double(greens.count)) % greens.count]
                _ = gv
                treeSprite[i] = UInt8(Int(rng() * 4) % 4) // 绿四档 0…3（明暗烘进精灵）
            }
        }
        // 金链螺旋：5 圈、半径贴树面 +0.07（样片 buildTree 后段）
        garlandPos = [Float](repeating: 0, count: Self.garlandCount * 3)
        for j in 0..<Self.garlandCount {
            let t = Double(j) / Double(Self.garlandCount)
            let gy = t * (4.6 - 0.25) + 0.12
            let gr = treeRadius(gy) + 0.07
            let ga = t * .pi * 2 * 5.0
            garlandPos[j * 3] = Float(cos(ga) * gr)
            garlandPos[j * 3 + 1] = Float(0.35 + gy)
            garlandPos[j * 3 + 2] = Float(sin(ga) * gr)
        }
        // 环境雪种子：远 650（spread 30 / 高 13）、近 110（22 / 11）
        func snowSeeds(_ count: Int) -> [Float] {
            let r = p93Mulberry32(seed: UInt32(count * 31 + 7))
            var s = [Float](repeating: 0, count: count * 3)
            for i in 0..<count {
                s[i * 3] = Float((r() - 0.5))
                s[i * 3 + 1] = Float(0.25 + r() * 0.55)
                s[i * 3 + 2] = Float(r() * .pi * 2)
            }
            return s
        }
        snowFarSeed = snowSeeds(Self.snowFarCount)
        snowNearSeed = snowSeeds(Self.snowNearCount)
        // 歌词粒性状：种子 4242（延迟/闪烁相位/色 tint/碎散漂移）
        let tr = p93Mulberry32(seed: 4242)
        pDelay = [Float](repeating: 0, count: Self.lyricCount)
        pTwinkle = [Float](repeating: 0, count: Self.lyricCount)
        pTint = [Float](repeating: 0, count: Self.lyricCount * 3)
        pDrift = [Float](repeating: 0, count: Self.lyricCount * 3)
        for i in 0..<Self.lyricCount {
            pDelay[i] = Float(tr() * 0.55)
            pTwinkle[i] = Float(tr() * .pi * 2)
            let pick = tr()
            var rgb: (Double, Double, Double)
            if pick > 0.93 { rgb = (1.0, 0.45, 0.34) }
            else if pick > 0.86 { rgb = (0.5, 1.0, 0.55) }
            else { rgb = (1.0, 0.9, 0.62) }
            pTint[i * 3] = Float(rgb.0); pTint[i * 3 + 1] = Float(rgb.1); pTint[i * 3 + 2] = Float(rgb.2)
            let a = tr() * .pi * 2, rad = 0.5 + tr() * 1.5
            pDrift[i * 3] = Float(cos(a) * rad)
            pDrift[i * 3 + 1] = Float(-(0.5 + tr() * 1.3))
            pDrift[i * 3 + 2] = Float((tr() - 0.5) * 0.9)
        }
    }

    // MARK: 精灵烘焙（径向点/金星/暖光池/带衬底，一次性）

    private func bakeSpritesIfNeeded() {
        // (94) 94-8：scale 渲染时动态取 UIScreen.main.scale
        // （Miller 10:55 铁令：不写死、不封顶）；已烘且 scale
        // 未变直接复用缓存，scale 变则整表重烘。
        let dynScale = UIScreen.main.scale
        if spritesReady && bakedScale94 == dynScale { return }
        spritesReady = true
        bakedScale94 = dynScale
        func dot(size: Int, stops: [(CGFloat, UIColor)]) -> CGImage? {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = UIScreen.main.scale; fmt.opaque = false
            let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt).image { c in
                let ctx = c.cgContext
                let colors = stops.map { $0.1.cgColor } as CFArray
                let locs = stops.map { $0.0 }
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locs) {
                    let center = CGPoint(x: size / 2, y: size / 2)
                    ctx.drawRadialGradient(g, startCenter: center, startRadius: 1,
                                           endCenter: center, endRadius: CGFloat(size) / 2, options: [])
                }
            }
            return img.cgImage
        }
        func tintedDot(_ rgb: (CGFloat, CGFloat, CGFloat), _ shade: CGFloat) -> CGImage? {
            dot(size: 64, stops: [
                (0, UIColor(red: rgb.0 * shade, green: rgb.1 * shade, blue: rgb.2 * shade, alpha: 1)),
                (0.35, UIColor(red: rgb.0 * shade, green: rgb.1 * shade, blue: rgb.2 * shade, alpha: 0.45)),
                (1, UIColor(white: 0, alpha: 0)),
            ])
        }
        var list: [CGImage?] = []
        // 0…3 绿四档（明暗 0.75…1.3 烘进精灵）、4 金、5 红、6 冰晶
        let greens: [(CGFloat, CGFloat, CGFloat)] = [(0.05, 0.36, 0.18), (0.07, 0.48, 0.25), (0.04, 0.29, 0.15), (0.1, 0.55, 0.28)]
        for (i, g) in greens.enumerated() { list.append(tintedDot(g, 0.8 + CGFloat(i) * 0.17)) }
        list.append(tintedDot((1.0, 0.8, 0.42), 1.0))
        list.append(tintedDot((1.0, 0.36, 0.28), 1.0))
        list.append(tintedDot((0.85, 0.95, 1.0), 1.0))
        // 7 金链点
        list.append(tintedDot((1.0, 0.76, 0.36), 1.0))
        // 8 歌词亮金白芯、9 红 spark、10 绿 spark（tint 稀有色）
        list.append(dot(size: 64, stops: [(0, UIColor(red: 1, green: 0.96, blue: 0.8, alpha: 1)),
                                          (0.35, UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 0.5)),
                                          (1, UIColor(white: 0, alpha: 0))]))
        list.append(tintedDot((1.0, 0.45, 0.34), 1.0))
        list.append(tintedDot((0.5, 1.0, 0.55), 1.0))
        // 11 雪点（蓝白）
        list.append(dot(size: 64, stops: [(0, UIColor(red: 0.86, green: 0.93, blue: 1, alpha: 1)),
                                          (0.35, UIColor(red: 0.86, green: 0.93, blue: 1, alpha: 0.45)),
                                          (1, UIColor(white: 0, alpha: 0))]))
        // 12 深色描边晕（近黑绿，样片 halo 0x010d05）
        list.append(dot(size: 64, stops: [(0, UIColor(red: 0.004, green: 0.05, blue: 0.02, alpha: 0.55)),
                                          (0.55, UIColor(red: 0.004, green: 0.05, blue: 0.02, alpha: 0.3)),
                                          (1, UIColor(white: 0, alpha: 0))]))
        // 13 金星（五角 + 光晕，样片 makeStarTexture 256）
        list.append(bakeStar())
        // 14 地面暖光池（样片 makeGroundGlowTexture）
        list.append(dot(size: 128, stops: [(0, UIColor(red: 1, green: 0.77, blue: 0.38, alpha: 0.5)),
                                           (0.45, UIColor(red: 0.75, green: 0.51, blue: 0.2, alpha: 0.16)),
                                           (1, UIColor(white: 0, alpha: 0))]))
        // 15 歌词带暗椭圆衬底（样片 makeBandShadowTexture，只盖歌词带）
        list.append(bakeBandShadow())
        sprites = list
    }

    private func bakeStar() -> CGImage? {
        let size = 256
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = UIScreen.main.scale; fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt).image { c in
            let ctx = c.cgContext
            ctx.translateBy(x: 128, y: 128)
            ctx.setShadow(offset: .zero, blur: 34, color: UIColor(red: 1, green: 0.77, blue: 0.31, alpha: 0.95).cgColor)
            let path = CGMutablePath()
            let spikes = 5, outerR: CGFloat = 58, innerR: CGFloat = 24
            for i in 0..<(spikes * 2) {
                let r = i % 2 == 0 ? outerR : innerR
                let a = CGFloat.pi / CGFloat(spikes) * CGFloat(i) - .pi / 2
                let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(UIColor(red: 1, green: 0.85, blue: 0.47, alpha: 1).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.fillPath()
        }
        return img.cgImage
    }

    private func bakeBandShadow() -> CGImage? {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = UIScreen.main.scale; fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256), format: fmt).image { c in
            let ctx = c.cgContext
            ctx.translateBy(x: 256, y: 128)
            ctx.scaleBy(x: 1, y: 0.5)
            let colors = [UIColor(red: 0.004, green: 0.027, blue: 0.012, alpha: 0.88).cgColor,
                          UIColor(red: 0.004, green: 0.027, blue: 0.012, alpha: 0.62).cgColor,
                          UIColor(white: 0, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 10,
                                       endCenter: .zero, endRadius: 250, options: [])
            }
        }
        return img.cgImage
    }

    // MARK: 歌词采样（离屏渲染当前行 → alpha 采样，样片 sampleLine）

    private func sampleLine(_ text: String) {
        let CW = 1200, CH = 300
        let fmt = UIGraphicsImageRendererFormat()
        // (94) 94-8：离屏采样图同走动态 scale（不封顶）；下方
        // 采样步长按位图实际像素/逻辑尺寸比缩放，归一化坐标
        // 口径与 scale=1 时逐点等价。
        fmt.scale = UIScreen.main.scale; fmt.opaque = false
        let size = CGSize(width: CW, height: CH)
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            var font = UIFont.systemFont(ofSize: 168, weight: .black)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let w = (text as NSString).size(withAttributes: attrs).width
            if w > CGFloat(CW - 60) {
                font = UIFont.systemFont(ofSize: floor(168 * CGFloat(CW - 60) / w), weight: .black)
            }
            let a2: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let ts = (text as NSString).size(withAttributes: a2)
            (text as NSString).draw(at: CGPoint(x: (CGFloat(CW) - ts.width) / 2,
                                                y: (CGFloat(CH) - ts.height) / 2 + 6), withAttributes: a2)
        }
        guard let cg = img.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { linePoints = []; return }
        let bpr = cg.bytesPerRow
        let pw = cg.width, ph = cg.height
        let step = max(1, Int((Double(pw) / Double(CW) * 2).rounded()))
        var pts: [CGPoint] = []
        var y = 0
        while y < ph {
            var x = 0
            while x < pw {
                // alpha 通道偏移按位图 alphaInfo 取（RGBA/BGRA 均为 +3）
                if bytes[y * bpr + x * 4 + 3] > 120 {
                    pts.append(CGPoint(x: Double(x) / Double(pw) - 0.5,
                                       y: 0.5 - Double(y) / Double(ph)))
                }
                x += step
            }
            y += step
        }
        // 确定性洗牌（样片：种子 = 字数×977+13）
        let rng = p93Mulberry32(seed: UInt32(text.count * 977 + 13))
        if pts.count > 1 {
            for i in stride(from: pts.count - 1, through: 1, by: -1) {
                let j = Int(rng() * Double(i + 1)) % (i + 1)
                pts.swapAt(i, j)
            }
        }
        linePoints = pts
        targetsDirty = true
    }

    /// 歌词平面拟合宽（样片 layout()）：可见宽×0.97、上限 7.4。
    private func fitWidth(radius: Double, aspect: Double) -> Double {
        let dist = radius - 3.6
        let visW = 2 * dist * tan(25 * .pi / 180) * aspect
        return min(7.4, visW * 0.97)
    }

    private func currentRadius(aspect: Double) -> Double { aspect < 1 ? 11.9 : 8.6 }

    private func rebuildTargets() {
        targetsDirty = false
        let bounds = canvas.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let aspect = Double(bounds.width / bounds.height)
        let fitW = fitWidth(radius: currentRadius(aspect: aspect), aspect: aspect)
        let h = fitW * 0.25
        targets = [Float](repeating: 0, count: Self.lyricCount * 3)
        for i in 0..<Self.lyricCount {
            let p = linePoints.isEmpty ? CGPoint.zero : linePoints[i % linePoints.count]
            let jx = (p93Hash01(Double(i * 13 + 5)) - 0.5) * 0.02
            let jy = (p93Hash01(Double(i * 17 + 9)) - 0.5) * 0.02
            targets[i * 3] = Float(Double(p.x) * fitW + jx)
            targets[i * 3 + 1] = Float(Double(p.y) * h + jy)
            targets[i * 3 + 2] = Float((p93Hash01(Double(i * 19 + 3)) - 0.5) * 0.05)
        }
    }

    // MARK: 逐帧绘制（投影 + 精灵贴图）

    private struct P93Cam {
        var pos: (Double, Double, Double)
        var right: (Double, Double, Double)
        var up: (Double, Double, Double)
        var fwd: (Double, Double, Double)
        var focal: Double
        var cx: Double
        var cy: Double
    }

    private func makeCamera(t: TimeInterval, rect: CGRect) -> P93Cam {
        let aspect = Double(rect.width / max(rect.height, 1))
        let radius = currentRadius(aspect: aspect) + sin(t * .pi * 2 / 20) * 0.25
        let ang = t * .pi * 2 / 40 + 0.6
        let camH = 2.75 + sin(t * .pi * 2 / 13) * 0.38
        let pos = (cos(ang) * radius, camH, sin(ang) * radius)
        let center = (0.0, 2.35, 0.0)
        var f = (center.0 - pos.0, center.1 - pos.1, center.2 - pos.2)
        let fl = sqrt(f.0 * f.0 + f.1 * f.1 + f.2 * f.2)
        f = (f.0 / fl, f.1 / fl, f.2 / fl)
        // right = normalize(cross(fwd, worldUp)) = (-f.z, 0, f.x)；up = cross(right, fwd)
        var r = (-f.2, 0.0, f.0)
        let rl = sqrt(r.0 * r.0 + r.2 * r.2)
        r = (r.0 / rl, 0, r.2 / rl)
        let u = (r.1 * f.2 - r.2 * f.1, r.2 * f.0 - r.0 * f.2, r.0 * f.1 - r.1 * f.0)
        let focal = Double(rect.height) / 2 / tan(25 * .pi / 180)
        return P93Cam(pos: pos, right: r, up: u, fwd: f, focal: focal,
                      cx: Double(rect.width) / 2, cy: Double(rect.height) / 2)
    }

    @inline(__always)
    private func project(_ cam: P93Cam, _ x: Double, _ y: Double, _ z: Double)
        -> (sx: Double, sy: Double, scale: Double)? {
        let rx = x - cam.pos.0, ry = y - cam.pos.1, rz = z - cam.pos.2
        let xc = rx * cam.right.0 + ry * cam.right.1 + rz * cam.right.2
        let yc = rx * cam.up.0 + ry * cam.up.1 + rz * cam.up.2
        let zc = rx * cam.fwd.0 + ry * cam.fwd.1 + rz * cam.fwd.2
        guard zc > 0.15 else { return nil }
        let s = cam.focal / zc
        return (cam.cx + xc * s, cam.cy - yc * s, s)
    }

    // (97) 第 2 条：旧 drawSprite（CG 逐粒贴图）→ 实例追加。
    // 径向精灵无方向性；金星靠图集内烘焙朝向（位图行序已在
    // 图集构建时对齐屏幕朝向），不再需要旧 draw 的 y 翻转。
    private func appendSprite97(_ spriteIndex: Int, center: (Double, Double),
                                sizePx: Double, alpha: CGFloat) {
        guard sizePx > 0.5, alpha > 0.01,
              let uv = metal97.uvRect(forSprite: spriteIndex) else { return }
        frameSprites97.append(XmasSpriteInstance97(
            cx: Float(center.0), cy: Float(center.1),
            w: Float(sizePx), h: Float(sizePx),
            u0: Float(uv.minX), v0: Float(uv.minY),
            u1: Float(uv.maxX), v1: Float(uv.maxY),
            alpha: Float(alpha)))
    }

    /// 非方形贴图（地面暖光池/歌词带衬底，旧 ctx.draw 直贴）。
    private func appendSpriteRect97(_ spriteIndex: Int, center: (Double, Double),
                                    wPx: Double, hPx: Double, alpha: CGFloat) {
        guard wPx > 0.5, hPx > 0.5, alpha > 0.01,
              let uv = metal97.uvRect(forSprite: spriteIndex) else { return }
        frameSprites97.append(XmasSpriteInstance97(
            cx: Float(center.0), cy: Float(center.1),
            w: Float(wPx), h: Float(hPx),
            u0: Float(uv.minX), v0: Float(uv.minY),
            u1: Float(uv.maxX), v1: Float(uv.maxY),
            alpha: Float(alpha)))
    }

    private func appendTri97(_ p0: (Double, Double), _ p1: (Double, Double),
                             _ p2: (Double, Double), color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        frameTris97.append(XmasSolidTri97(
            x0: Float(p0.0), y0: Float(p0.1),
            x1: Float(p1.0), y1: Float(p1.1),
            x2: Float(p2.0), y2: Float(p2.1),
            r: Float(r), g: Float(g), b: Float(b), a: Float(a)))
    }

    private func buildFrame97(rect: CGRect) {
        // (94) 94-8：scale 漂移兜底重烘（同机旋转不触发）。
        if spritesReady && bakedScale94 != UIScreen.main.scale {
            sprites = []; spritesReady = false; bakeSpritesIfNeeded()
            atlasReady97 = metal97.buildAtlas(sprites: sprites)
            Breadcrumbs.log("p94 xmas scale=\(String(format: "%.1f", UIScreen.main.scale))"
                + " tex=\(String(format: "%.1f", textureMB94()))MB rebake=1")
        }
        guard sprites.count > 15 else {
            if !guardLogged98a { guardLogged98a = true; Breadcrumbs.log("p98 xmas guard sprites=\(sprites.count)") }
            frameSprites97 = []; frameTris97 = []; return
        }
        guard !treePos.isEmpty else {
            if !guardLogged98b { guardLogged98b = true; Breadcrumbs.log("p98 xmas guard treePos=0") }
            frameSprites97 = []; frameTris97 = []; return
        }
        frameSprites97.removeAll(keepingCapacity: true)
        frameTris97.removeAll(keepingCapacity: true)
        let t = elapsed
        let cam = makeCamera(t: t, rect: rect)
        let aspect = Double(rect.width / max(rect.height, 1))
        let radius = currentRadius(aspect: aspect)
        let fitW = fitWidth(radius: radius, aspect: aspect)

        // 远景剪影（样片 buildBackdrop：9 棵暗锥，纯色填充非滤镜）
        let silhouette = UIColor(red: 0.027, green: 0.153, blue: 0.102, alpha: 1)
        let brng = p93Mulberry32(seed: 777)
        for i in 0..<9 {
            let a = Double(i) / 9 * .pi * 2 + brng() * 0.4
            let dist = 15 + brng() * 7
            let h = 5 + brng() * 4.5
            let bx = cos(a) * dist, bz = sin(a) * dist
            guard let base = project(cam, bx, h / 2 - 0.2, bz) else { continue }
            let wPx = h * 0.32 * base.scale, hPx = h * base.scale
            appendTri97((base.sx, base.sy - hPx / 2),
                        (base.sx - wPx, base.sy + hPx / 2),
                        (base.sx + wPx, base.sy + hPx / 2),
                        color: silhouette)
        }

        // 地面暖光池（扁椭圆近似地面圆，样片半径 4.4）
        if let g = project(cam, 0, 0.02, 0) {
            let wPx = 8.8 * g.scale
            appendSpriteRect97(14, center: (g.sx, g.sy), wPx: wPx,
                               hPx: wPx * 0.32, alpha: 0.9)
        }

        // 树干（样片圆柱 #2e1c10 的屏幕近似：投影梯形填充）
        if let tb = project(cam, 0, 0.1, 0), let tt = project(cam, 0, 0.5, 0) {
            let wb = 0.4 * tb.scale / 2, wt = 0.26 * tt.scale / 2
            let trunk = UIColor(red: 0.18, green: 0.11, blue: 0.063, alpha: 1)
            appendTri97((tb.sx - wb, tb.sy), (tb.sx + wb, tb.sy),
                        (tt.sx + wt, tt.sy), color: trunk)
            appendTri97((tb.sx - wb, tb.sy), (tt.sx + wt, tt.sy),
                        (tt.sx - wt, tt.sy), color: trunk)
        }

        // 树体 + 金链（树组微摆 sin(t*0.05)*0.04，样片同式）
        let sway = sin(t * 0.05) * 0.04
        let cs = cos(sway), sn = sin(sway)
        for i in 0..<Self.treeCount {
            let x = Double(treePos[i * 3]), y = Double(treePos[i * 3 + 1]), z = Double(treePos[i * 3 + 2])
            guard let p = project(cam, x * cs - z * sn, y, x * sn + z * cs) else { continue }
            appendSprite97(Int(treeSprite[i]), center: (p.sx, p.sy),
                           sizePx: 0.085 * p.scale, alpha: 0.95)
        }
        for j in 0..<Self.garlandCount {
            let x = Double(garlandPos[j * 3]), y = Double(garlandPos[j * 3 + 1]), z = Double(garlandPos[j * 3 + 2])
            guard let p = project(cam, x * cs - z * sn, y, x * sn + z * cs) else { continue }
            let tw = 0.8 + 0.35 * sin(Double(j) * 1.7)
            appendSprite97(7, center: (p.sx, p.sy),
                           sizePx: 0.11 * p.scale, alpha: CGFloat(min(tw, 1)))
        }

        // 树顶金星 + 光晕（样片：星 1.05 脉动 ±0.07、晕 2.6）
        let starY = 0.35 + 4.6 + 0.42
        if let sp = project(cam, 0, starY, 0) {
            let pulse = 1.02 + sin(t * 2.2) * 0.07
            appendSprite97(4, center: (sp.sx, sp.sy),
                           sizePx: 2.6 * sp.scale, alpha: 0.28) // 暖晕：金点精灵放大低 alpha 近似样片 glowTex 晕
            appendSprite97(13, center: (sp.sx, sp.sy),
                           sizePx: 1.05 * pulse * sp.scale, alpha: 1)
        }

        drawSnow97(cam: cam, seeds: snowFarSeed, count: Self.snowFarCount,
                   spread: 30, height: 13, size: 0.13, alpha: 0.75, t: t)
        drawSnow97(cam: cam, seeds: snowNearSeed, count: Self.snowNearCount,
                   spread: 22, height: 11, size: 0.46, alpha: 0.30, t: t * 0.6)

        drawLyrics97(cam: cam, t: t, fitW: fitW)
    }

    private func drawSnow97(cam: P93Cam, seeds: [Float], count: Int,
                            spread: Double, height: Double, size: Double,
                            alpha: CGFloat, t: TimeInterval) {
        guard seeds.count >= count * 3 else { return }
        for i in 0..<count {
            let x0 = Double(seeds[i * 3]) * spread
            let speed = Double(seeds[i * 3 + 1])
            let phase = Double(seeds[i * 3 + 2])
            let yy = (speed * t + phase * 3.7).truncatingRemainder(dividingBy: height)
            let x = x0 + sin(t * 0.55 + phase) * 0.55
            guard let p = project(cam, x, height - yy, (p93Hash01(Double(i * 7 + 1)) - 0.5) * spread) else { continue }
            appendSprite97(11, center: (p.sx, p.sy), sizePx: size * p.scale, alpha: alpha)
        }
    }

    // MARK: 歌词聚字（三态时序，样片 updateLyrics）

    private func drawLyrics97(cam: P93Cam, t: TimeInterval, fitW: Double) {
        guard let snapshot, currentLineIndex >= 0,
              snapshot.lines.indices.contains(currentLineIndex),
              targets.count >= Self.lyricCount * 3 else { return }
        let line = snapshot.lines[currentLineIndex]
        guard let pos = context?.positionNow() else { return }
        let local = pos - line.start
        let dur = max(line.end - line.start, 0.1)
        let gatherT = min(1.0, dur * 0.55)
        let scatterT = min(0.8, dur * 0.45)
        let holdEnd = dur - scatterT

        // 歌词平面：LYRIC_CENTER 向镜头拉近 3.6、法向对镜头（样片 billboard）
        let lc = (0.0, 1.45, 0.0)
        var dir = (cam.pos.0 - lc.0, cam.pos.1 - lc.1, cam.pos.2 - lc.2)
        let dl = sqrt(dir.0 * dir.0 + dir.1 * dir.1 + dir.2 * dir.2)
        dir = (dir.0 / dl, dir.1 / dl, dir.2 / dl)
        let center = (lc.0 + dir.0 * 3.6, lc.1 + dir.1 * 3.6, lc.2 + dir.2 * 3.6)
        // 平面基 = 相机基（billboard 与样片 quaternion 对齐同义）
        let r = cam.right, u = cam.up

        // 歌词带暗椭圆衬底（只盖歌词带，样片 bandMesh 尺寸口径）
        if let bp = project(cam, center.0, center.1, center.2) {
            let wPx = fitW * 1.22 * bp.scale
            let hPx = fitW * 0.25 * 2.3 * bp.scale
            appendSpriteRect97(15, center: (bp.sx, bp.sy), wPx: wPx, hPx: hPx, alpha: 1)
        }

        let coreSize = max(0.06, fitW * 0.016)
        for i in 0..<Self.lyricCount {
            let tx = Double(targets[i * 3]), ty = Double(targets[i * 3 + 1]), tz = Double(targets[i * 3 + 2])
            var lx: Double, ly: Double, lz: Double, bright: Double
            var spriteIdx = 8
            let tintR = Double(pTint[i * 3]), tintG = Double(pTint[i * 3 + 1])
            if tintR > 0.99 && tintG < 0.6 { spriteIdx = 9 }       // 红 spark 稀有粒
            else if tintG > 0.99 && tintR < 0.6 { spriteIdx = 10 }  // 绿 spark 稀有粒
            if local < gatherT {
                // 汇聚：散点（样片 scatterPos）→ easeOutBack 到目标
                let li = Double(currentLineIndex)
                let r1 = p93Hash01(Double(i * 3) + li * 131 + 11)
                let r2 = p93Hash01(Double(i * 5) + li * 197 + 29)
                let r3 = p93Hash01(Double(i * 7) + li * 251 + 47)
                let ang = r1 * .pi * 2, rad = 1.2 + r2 * 4.6
                let sx = cos(ang) * rad, sy = (r3 - 0.42) * 3.4, sz = (r2 - 0.5) * 1.6 + 0.4
                let delay = Double(pDelay[i]) * 0.55
                let denom = max(gatherT - delay, 0.05)
                var p = (local - delay) / denom
                p = min(max(p, 0), 1)
                let s = 1.35, uu = p - 1
                let e = 1 + (s + 1) * uu * uu * uu + s * uu * uu
                lx = sx + (tx - sx) * e; ly = sy + (ty - sy) * e; lz = sz + (tz - sz) * e
                bright = 0.3 + 0.75 * p
                if p < 0.5 { spriteIdx = 11 } // 凝聚前半程呈雪色（样片雪→金混色近似）
            } else if local < holdEnd {
                let tw = Double(pTwinkle[i])
                lx = tx; ly = ty + sin(t * 1.7 + tw) * 0.02; lz = tz + cos(t * 1.3 + tw) * 0.012
                bright = 1.12 + 0.24 * sin(t * 2.6 + tw * 3.1)
            } else {
                var q = (local - holdEnd) / max(scatterT, 0.05)
                q = min(max(q, 0), 1)
                let qe = q * q * (3 - 2 * q)
                lx = tx + Double(pDrift[i * 3]) * qe + sin(t * 2.0 + Double(pTwinkle[i])) * 0.1 * q
                ly = ty + Double(pDrift[i * 3 + 1]) * qe
                lz = tz + Double(pDrift[i * 3 + 2]) * qe
                bright = (1 - q) * 0.95
                if q > 0.5 { spriteIdx = 11 } // 碎散后半程转雪色
            }
            let wx = center.0 + r.0 * lx + u.0 * ly + dir.0 * lz
            let wy = center.1 + r.1 * lx + u.1 * ly + dir.1 * lz
            let wz = center.2 + r.2 * lx + u.2 * ly + dir.2 * lz
            guard let p = project(cam, wx, wy, wz) else { continue }
            // 深色描边晕先行（大 2.1×、在芯后方），再亮芯
            appendSprite97(12, center: (p.sx, p.sy),
                           sizePx: coreSize * 2.1 * p.scale, alpha: CGFloat(min(bright, 1)) * 0.55)
            appendSprite97(spriteIdx, center: (p.sx, p.sy),
                           sizePx: coreSize * p.scale, alpha: CGFloat(min(max(bright, 0), 1)))
        }
    }
}
