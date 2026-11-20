import UIKit
import QuartzCore
import CoreImage

// 莫奈（monet）全原生移植（3.7 (42)，特效移植第 1 稿）：
// 网页 VisualizerMonet + MonetRail + monet-gl helpers 的逐项
// 对译，数值以 monet-web-spec-extract-2026-11-20.md 为准。
// 组成：wash 背景成图（封面裁切 + 高斯模糊 + 逐像素灰度/
// 饱和/wash 三段映射 + overlay 烘焙，CPU 逐像素与网页
// worker 同算法同 round/clamp 语义，模糊走 CoreImage）、
// CALayer 人像层栈（离屏解码成功才入栈、900ms 交叉淡入、
// settle 砍下层）、5 行（滚动 ±4）弹簧轨道（y 弹簧
// 142/28/0.82、scale 弹簧 150/30/0.78，与网页 framer 弹簧
// 同名同值，CASpringAnimation 原生承载）、逐词字素扫字
// （StageTextKit 基建）、背景漂移（Fbm 157 帧闭环关键帧，
// 网页在 iOS WebKit 恒禁用、原生无此约束故保留）。
// 数据缺口（无数据源、分支保留恒不触发，与 cadenza 等
// 既定先例同口径）：副歌 isChorus（LyricLine 无此字段）、
// 副字幕轨（宿主无译文数据）、wordColors 关键字着色。
// 时钟纪律：只消费宿主 frameTick，不自建时钟源。
// 成图纪律（3.7 (44) 异步化）：一切栅格成图（静态行绘制＋
// 高斯模糊、扫字逐词三图）只在后台 bakeQueue 备好后贴入，
// 主线程零栅格化——折行测量（CTFramesetter，无渲染）保留
// 主线程使盒高首帧即准；未就绪先以空图/空扫字占位（底色
// 为调色板 wash/fallback），就绪后淡入换入；成品进 LRU
// 缓存。逐帧路径（frameTick/update）本就不栅格化。此项与
// (43) 冷启 route 死循环互不依赖，是渲染层纵深防御。

// MARK: - 颜色小工具

private func monetRGBA(_ color: UIColor)
    -> (r: Double, g: Double, b: Double, a: Double) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (Double(r), Double(g), Double(b), Double(a))
}

private func monetMix(_ c1: UIColor, _ c2: UIColor, _ t: Double) -> UIColor {
    let a = monetRGBA(c1), b = monetRGBA(c2)
    return UIColor(
        red: CGFloat(a.r + (b.r - a.r) * t),
        green: CGFloat(a.g + (b.g - a.g) * t),
        blue: CGFloat(a.b + (b.b - a.b) * t),
        alpha: CGFloat(a.a + (b.a - a.a) * t))
}

private func monetHex(_ color: UIColor) -> String {
    let c = monetRGBA(color)
    return String(format: "%02x%02x%02x",
                  Int((c.r * 255).rounded()), Int((c.g * 255).rounded()),
                  Int((c.b * 255).rounded()))
}

// MARK: - Wash 成图管线

enum MonetWashPipeline {
    /// 缺省画布（调用方没给尺寸时的兜底，旧版固定值）。
    static let canvasW = 1920
    static let canvasH = 1080
    // 网页烘焙 tuning 缺省值（原生无设置面，恒缺省）。
    static let blurRadius = 6.0
    static let grayMixAmount = 0.0
    static let saturationAmount = 1.05
    static let washAmount = 0.34
    static let overlayAmount = 0.74

    /// 共享 CIContext（3.7 (46)，DS 清单）：CIContext 创建昂贵
    /// 且线程安全，逐次 build 新建既浪费又多一份不确定性；与
    /// 渲染器侧 blurredImage 的 sharedCIContext 同口径收敛为
    /// 进程级单例。
    private static let sharedCIContext = CIContext(options: nil)

    /// 一次成图：主题实色垫底 → 封面 cover 裁切
    /// → 模糊 → 逐像素后处理 → overlay 烘焙。逐像素段与
    /// 网页 worker 逐行同序（灰度混合 → 饱和（亮度重算）
    /// → wash（wash 色由原始亮度决定）→ round/clamp 写回）。
    /// 画布尺寸（3.7 (47) 清晰度修复）：旧版恒 1920×1080
    /// 横版画布，拉满竖屏显示时纵向放大近 2 倍；改由调用
    /// 方按当前视图实际像素尺寸（×漂移缩放余量、带总像素
    /// 上限）传入，横竖屏都贴合显示尺寸。canvasSize 为零
    /// 时退回缺省 1920×1080。
    static func build(cover: UIImage, palette: PaletteTokens,
                      canvasSize: CGSize = .zero) -> UIImage? {
        guard let coverCG = cover.cgImage else { return nil }
        let W = canvasSize.width > 0 ? Int(canvasSize.width.rounded()) : canvasW
        let H = canvasSize.height > 0 ? Int(canvasSize.height.rounded()) : canvasH
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let base = CGContext(
            data: nil, width: W, height: H, bitsPerComponent: 8,
            bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)
        else { return nil }
        base.setFillColor(palette.background.cgColor)
        base.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let scale = max(Double(W) / Double(coverCG.width),
                        Double(H) / Double(coverCG.height))
        let dw = Double(coverCG.width) * scale
        let dh = Double(coverCG.height) * scale
        base.draw(coverCG, in: CGRect(x: (Double(W) - dw) / 2,
                                      y: (Double(H) - dh) / 2,
                                      width: dw, height: dh))
        guard let composed = base.makeImage() else { return nil }
        // 模糊：边缘以 clamp 延展（网页 Canvas 绘制时模糊的
        // 边缘行为是向背景色淡出，此处为已知微差，见回报）。
        let ci = CIImage(cgImage: composed)
        let blurred = ci.clampedToExtent().applyingFilter(
            "CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
        guard let blurredCG = sharedCIContext.createCGImage(
            blurred, from: CGRect(x: 0, y: 0, width: W, height: H))
        else { return nil }

        // 逐像素后处理 + overlay 烘焙（同一缓冲上下文）。
        let bytesPerRow = W * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * H)
        let result: UIImage? = buffer.withUnsafeMutableBytes { raw in
            guard let ptr = raw.baseAddress,
                  let post = CGContext(
                    data: ptr, width: W, height: H, bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow, space: space,
                    bitmapInfo: bitmapInfo)
            else { return nil }
            post.draw(blurredCG, in: CGRect(x: 0, y: 0, width: W, height: H))
            applyPixelPost(bytes: ptr, count: bytesPerRow * H, palette: palette)
            bakeOverlay(context: post, palette: palette,
                        canvasW: W, canvasH: H)
            guard let image = post.makeImage() else { return nil }
            return UIImage(cgImage: image, scale: 1, orientation: .up)
        }
        return result
    }

    private static func applyPixelPost(bytes: UnsafeMutableRawPointer,
                                       count: Int, palette: PaletteTokens) {
        let buffer = bytes.assumingMemoryBound(to: UInt8.self)
        let bg = monetRGBA(palette.background)
        let pri = monetRGBA(palette.primary)
        let acc = monetRGBA(palette.accent)
        func luminance(_ c: (r: Double, g: Double, b: Double, a: Double)) -> Double {
            0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        }
        // shadow/highlight = 背景与主色中较暗/较亮者；
        // accent 恒为主题强调色。
        let bgDarker = luminance(bg) <= luminance(pri)
        let shadow = bgDarker ? bg : pri
        let highlight = bgDarker ? pri : bg
        let gray = grayMixAmount, sat = saturationAmount, wash = washAmount
        var i = 0
        while i < count {
            if buffer[i + 3] != 0 {
                var r = Double(buffer[i]) / 255
                var g = Double(buffer[i + 1]) / 255
                var b = Double(buffer[i + 2]) / 255
                // ① 原始亮度（wash 色由此决定，Rec.601 式
                // 系数与网页一致）。
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                // ② 灰度混合（缺省 0，公式保留）。
                if gray != 0 {
                    r += (lum - r) * gray
                    g += (lum - g) * gray
                    b += (lum - b) * gray
                }
                // ③ 饱和：绕（灰度步后重算的）亮度缩放。
                let lum2 = 0.2126 * r + 0.7152 * g + 0.0722 * b
                r = lum2 + (r - lum2) * sat
                g = lum2 + (g - lum2) * sat
                b = lum2 + (b - lum2) * sat
                // ④ wash 三段映射。
                let wc: (Double, Double, Double)
                if lum <= 0.55 {
                    let t = lum / 0.55
                    wc = (shadow.r + (acc.r - shadow.r) * t,
                          shadow.g + (acc.g - shadow.g) * t,
                          shadow.b + (acc.b - shadow.b) * t)
                } else {
                    let t = (lum - 0.55) / 0.45
                    wc = (acc.r + (highlight.r - acc.r) * t,
                          acc.g + (highlight.g - acc.g) * t,
                          acc.b + (highlight.b - acc.b) * t)
                }
                r += (wc.0 - r) * wash
                g += (wc.1 - g) * wash
                b += (wc.2 - b) * wash
                buffer[i] = UInt8(min(max((r * 255).rounded(), 0), 255))
                buffer[i + 1] = UInt8(min(max((g * 255).rounded(), 0), 255))
                buffer[i + 2] = UInt8(min(max((b * 255).rounded(), 0), 255))
            }
            i += 4
        }
    }

    /// overlay 烘焙（网页 paintMonetOverlay 逐项对译；
    /// CG 坐标 y 向上，画布坐标逐项换算）。几何全部按传入
    /// 画布尺寸的比例式计算（对角/光晕/veil/竖纹均为相对
    /// 坐标），尺寸变更不改变视觉编排。
    private static func bakeOverlay(context post: CGContext,
                                    palette: PaletteTokens,
                                    canvasW: Int, canvasH: Int) {
        let W = Double(canvasW), H = Double(canvasH)
        let overlay = overlayAmount
        let space = CGColorSpaceCreateDeviceRGB()
        // ① 对角渐变（画布 (0,0)→(W,H) ≡ CG (0,H)→(W,0)）。
        let diagColors = [
            palette.accent.withAlphaComponent(CGFloat(0.08 + 0.62 * overlay)).cgColor,
            palette.background.withAlphaComponent(CGFloat(0.16 + 0.58 * overlay)).cgColor,
            palette.primary.withAlphaComponent(CGFloat(0.06 + 0.36 * overlay)).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: diagColors,
                                     locations: [0, 0.44, 1]) {
            post.drawLinearGradient(
                gradient, start: CGPoint(x: 0, y: H),
                end: CGPoint(x: W, y: 0), options: [])
        }
        // ② 左上径向光晕（画布圆心 (0.18W, 0.34H)）。
        let haloColors = [
            palette.accent.withAlphaComponent(CGFloat(0.42 * overlay)).cgColor,
            palette.accent.withAlphaComponent(0).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: haloColors,
                                     locations: [0, 1]) {
            let center = CGPoint(x: 0.18 * W, y: H - 0.34 * H)
            post.drawRadialGradient(
                gradient, startCenter: center, startRadius: 0,
                endCenter: center, endRadius: CGFloat(0.55 * W), options: [])
        }
        // ③ 右侧 veil（水平渐变，两坐标系同向）。
        let veilColors = [
            palette.background.withAlphaComponent(0).cgColor,
            palette.background.withAlphaComponent(CGFloat(0.18 + 0.38 * overlay)).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: veilColors,
                                     locations: [0, 1]) {
            post.drawLinearGradient(
                gradient, start: CGPoint(x: 0.45 * W, y: 0),
                end: CGPoint(x: W, y: 0), options: [])
        }
        // ④ 18 条竖纹（1px、0.28H，画布 y 自顶换算）。
        post.setFillColor(palette.background
            .withAlphaComponent(CGFloat(0.1 + 0.08 * overlay)).cgColor)
        let streakHeight = 0.28 * H
        for i in 0..<18 {
            let x = Double((i * 127) % canvasW)
            let yTop = Double((i * 211) % canvasH) - 40
            post.fill(CGRect(x: x, y: H - yTop - streakHeight,
                             width: 1, height: streakHeight))
        }
    }
}

// MARK: - 背景漂移轨（网页 buildMonetDriftTrack 逐行对译）

enum MonetDriftTrack {
    static let latticePoints = 76.0
    static let samples = 156
    static let duration: TimeInterval = 240

    private static func hash(_ lattice: Double, _ seed: Double) -> Double {
        let v = sin(lattice * 127.1 + seed * 311.7) * 43758.5453
        return v - floor(v)
    }

    private static func periodicNoise(_ t: Double, _ points: Double,
                                      _ seed: Double) -> Double {
        let cell = floor(t)
        let local = t - cell
        let s = local * local * (3 - 2 * local)
        let count = Int(points)
        func wrap(_ v: Int) -> Double { Double(((v % count) + count) % count) }
        let a = hash(wrap(Int(cell)), seed)
        let b = hash(wrap(Int(cell) + 1), seed)
        return a + (b - a) * s
    }

    private static func fbm(_ t: Double, _ seed: Double) -> Double {
        (periodicNoise(t, 76, seed) * 0.68
            + periodicNoise(t * 2, 152, seed + 17.31) * 0.32) * 2 - 1
    }

    private static func channel(seed: Double) -> [Double] {
        var values: [Double] = []
        var peak = 0.0
        for i in 0...samples {
            let v = fbm(latticePoints * Double(i) / Double(samples), seed)
            values.append(v)
            peak = max(peak, abs(v))
        }
        let norm = peak > 0.0001 ? peak : 1
        return values.map { $0 / norm }
    }

    /// 157 帧闭环 transform 轨（平移以容器尺寸百分比计，
    /// 与 CSS translate % 同义）。
    static func keyframeValues(size: CGSize, strength: Double = 0.5) -> [NSValue] {
        let travel = 3.4 * strength
        let minScale = 1 + travel * 2 / 100 + 0.01
        let breath = 0.035 * strength
        let xs = channel(seed: 12.9898)
        let ys = channel(seed: 78.233)
        let ss = channel(seed: 39.425)
        return (0...samples).map { i in
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(
                transform,
                CGFloat(xs[i] * travel / 100 * Double(size.width)),
                CGFloat(ys[i] * travel / 100 * Double(size.height)), 0)
            let scale = minScale + breath * (ss[i] + 1) / 2
            transform = CATransform3DScale(
                transform, CGFloat(scale), CGFloat(scale), 1)
            return NSValue(caTransform3D: transform)
        }
    }
}

// MARK: - 轨道行视图

final class MonetRailLineView: UIView {
    let lineIndex: Int
    /// 内容签名（签名不变不重烘焙）。
    var contentKey = ""
    var boxHeight: CGFloat = 0
    private(set) var isSweep = false

    private let staticView = UIImageView()
    private var sweepView: StageSweepLineView?
    private let chorusGlowView = UIView()
    private let chorusGradient = CAGradientLayer()

    init(lineIndex: Int) {
        self.lineIndex = lineIndex
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        staticView.isUserInteractionEnabled = false
        addSubview(chorusGlowView)
        addSubview(staticView)
        chorusGlowView.isUserInteractionEnabled = false
        chorusGlowView.alpha = 0
        chorusGradient.type = .radial
        chorusGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        chorusGradient.endPoint = CGPoint(x: 1, y: 0.5)
        chorusGradient.colors = [0.14, 0.12, 0.085, 0.05, 0.022, 0.007, 0].map {
            UIColor.white.withAlphaComponent(CGFloat($0)).cgColor
        }
        chorusGradient.locations = [0, 0.15, 0.35, 0.55, 0.72, 0.87, 1]
        chorusGlowView.layer.addSublayer(chorusGradient)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func showStatic(image: UIImage?, textFrame: CGRect, boxHeight: CGFloat,
                    clipped: Bool, fadeHeight: CGFloat, key: String) {
        contentKey = key
        isSweep = false
        sweepView?.removeFromSuperview()
        sweepView = nil
        self.boxHeight = boxHeight
        bounds = CGRect(x: 0, y: 0, width: bounds.width, height: boxHeight)
        staticView.isHidden = false
        staticView.image = image
        staticView.frame = textFrame
        if clipped, textFrame.height > 0 {
            let mask = CAGradientLayer()
            mask.frame = CGRect(origin: .zero, size: textFrame.size)
            mask.colors = [UIColor.black.cgColor, UIColor.black.cgColor,
                           UIColor.clear.cgColor]
            let stop = NSNumber(value: Double(max(0, (textFrame.height - fadeHeight) / textFrame.height)))
            mask.locations = [0, stop, 1]
            staticView.layer.mask = mask
        } else {
            staticView.layer.mask = nil
        }
        layoutChorusGlow(boxHeight: boxHeight)
    }

    /// 后台成图落地（3.7 (44)）：占位（image=nil）先行时，
    /// 成图备好后只换图＋0.3s 交叉淡入，盒高/mask 已由
    /// showStatic 按同一参数落好，不重排。
    func applyBakedStaticImage(_ image: UIImage) {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.3
        staticView.layer.add(transition, forKey: "monet.bakeFade")
        staticView.image = image
    }

    func showSweep(_ sweep: StageSweepLineView, textFrame: CGRect,
                   boxHeight: CGFloat, key: String) {
        contentKey = key
        isSweep = true
        staticView.isHidden = true
        staticView.image = nil
        staticView.layer.mask = nil
        sweepView?.removeFromSuperview()
        sweepView = sweep
        sweep.frame = textFrame
        addSubview(sweep)
        self.boxHeight = boxHeight
        bounds = CGRect(x: 0, y: 0, width: bounds.width, height: boxHeight)
        layoutChorusGlow(boxHeight: boxHeight)
    }

    func updateSweep(position: TimeInterval, lineEnd: TimeInterval) {
        sweepView?.update(position: position, lineEnd: lineEnd)
    }

    /// 副歌辉光（数据源缺失、恒不触发，分支保留）：accent
    /// 径向光晕，active 时 0.45s easeOut 至 opacity 1/scale 1.02。
    func setChorusGlow(active: Bool, accent: UIColor, boxHeight: CGFloat) {
        chorusGradient.colors = [0.14, 0.12, 0.085, 0.05, 0.022, 0.007, 0].map {
            accent.withAlphaComponent(CGFloat($0)).cgColor
        }
        layoutChorusGlow(boxHeight: boxHeight)
        UIView.animate(withDuration: 0.45, delay: 0,
                       options: [.curveEaseOut]) {
            self.chorusGlowView.alpha = active ? 1 : 0
            self.chorusGlowView.transform = active
                ? CGAffineTransform(scaleX: 1.02, y: 1.02) : .identity
        }
    }

    private func layoutChorusGlow(boxHeight: CGFloat) {
        chorusGlowView.frame = CGRect(x: 0, y: -56, width: bounds.width,
                                      height: boxHeight + 112)
        chorusGradient.frame = chorusGlowView.bounds
    }
}

// MARK: - 渲染器

final class MonetStageRenderer: NSObject, LyricStageRenderer {
    let view: UIView
    var onSeekRequest: ((TimeInterval) -> Void)?
    var onUserScrubbingChanged: ((Bool) -> Void)?

    private let rootView = LyricStageRootView()
    private let bgContainer = UIView()
    private let tempCoverView = UIImageView()
    private let fallbackView = UIView()
    private let fallbackGradient = CAGradientLayer()
    private var washViews: [UIImageView] = []
    private let readabilityView = UIView()
    private let readabilityGradient = CAGradientLayer()
    private let portraitShadowView = UIView()
    private let portraitClipView = UIView()
    private var portraitLayers: [UIImageView] = []
    private let railView = UIView()

    private var snapshot: LyricStageSnapshot?
    private var context: LyricStageContext?
    private var isActive = false
    private var lines: [LyricLine] = []
    private var trackID: String?
    private var coverImage: UIImage?
    private var lastPortraitKey: String?
    private var coverTask: Task<Void, Never>?
    private var washTask: Task<Void, Never>?
    // 莫奈护栏（3.7 (53)，DS 对账）：cover/wash 各自代际
    // token——每次启动递增，await 恢复后 token 不符即陈旧
    // 提交、整段放弃。分开计数：cover 完成后才启 wash，
    // 共用一枚会让 wash 启动误杀 cover 的收尾校验；反之
    // wash 重成图（主题色更新）也不该作废在途 cover。
    private var coverGeneration = 0
    private var washGeneration = 0
    private var washKey: String?
    private var washCache: [(key: String, image: UIImage)] = []
    // 成图烘焙（3.7 (44)）：后台串行队列＋LRU 缓存＋在途去
    // 重。缓存键 = trackID|contentKey（contentKey 本身不含
    // 曲目，跨曲必须隔离）。bakeGeneration 在切歌/unmount
    // 时 +1，陈旧成图落地即弃。
    private let bakeQueue = DispatchQueue(label: "folia.monet.bake",
                                          qos: .utility)
    private var staticBakeCache: [(key: String, image: UIImage)] = []
    private var sweepBakeCache: [(key: String, images: [Int: StageSweepWordImages])] = []
    private var pendingBakeKeys: Set<String> = []
    private var bakeGeneration = 0
    /// 高斯模糊共享 CIContext（3.7 (44)）：CIContext 创建昂
    /// 贵，此前 blurred() 逐行新建；全渲染器共用一台，且只
    /// 在后台 bakeQueue 上使用。
    private static let sharedCIContext = CIContext(options: nil)
    private var lineViews: [Int: MonetRailLineView] = [:]
    private var exitingViews: [MonetRailLineView] = []
    /// 粒子换行层（3.7 (49)）：盖在轨道之上，纯叠加——
    /// 莫奈轨道滚动连续，真实行不隐藏，粒子只做焦点推进
    /// 时的散开/聚拢仪式（与流光的藏行衔接不同，见回报）。
    private let particleView = ParticleTransitionView()
    private var prevTickPosition: TimeInterval = -1
    private var focusIndex = 0
    private var activeIndex: Int?
    private var manualFocus: Int?
    private var appliedPanSteps = 0
    private var lastInteractionAt: CFTimeInterval = 0
    private var didPortraitIntro = false
    private var driftSize: CGSize = .zero
    private var lastPosition: TimeInterval = 0

    private enum LineStatus { case active, waiting, passed }
    private struct Tone {
        var opacity: CGFloat
        var scale: CGFloat
        var blur: CGFloat
        var baseAlpha: CGFloat
    }
    private struct Metrics {
        var fontPx: CGFloat
        var inactiveScale: CGFloat
        var glowBuffer: CGFloat
        var contentWidth: CGFloat
    }

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        bgContainer.isUserInteractionEnabled = false
        rootView.addSubview(bgContainer)
        tempCoverView.contentMode = .scaleAspectFill
        tempCoverView.clipsToBounds = true
        tempCoverView.isUserInteractionEnabled = false
        bgContainer.addSubview(tempCoverView)
        fallbackView.isUserInteractionEnabled = false
        fallbackView.layer.addSublayer(fallbackGradient)
        bgContainer.addSubview(fallbackView)
        readabilityView.isUserInteractionEnabled = false
        readabilityView.layer.addSublayer(readabilityGradient)
        rootView.addSubview(readabilityView)
        portraitShadowView.layer.cornerRadius = 32
        portraitShadowView.layer.shadowOffset = CGSize(width: 0, height: 36)
        portraitShadowView.layer.shadowRadius = 40
        portraitShadowView.layer.shadowOpacity = 1
        portraitShadowView.isUserInteractionEnabled = false
        rootView.addSubview(portraitShadowView)
        portraitClipView.layer.cornerRadius = 32
        portraitClipView.clipsToBounds = true
        portraitClipView.isUserInteractionEnabled = false
        portraitShadowView.addSubview(portraitClipView)
        rootView.addSubview(railView)
        rootView.addSubview(particleView)
        railView.clipsToBounds = false
        // 轨道上下羽化 mask（网页 mask-image 同 stops）。
        let railMask = CAGradientLayer()
        railMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor,
                           UIColor.black.cgColor, UIColor.clear.cgColor]
        railMask.locations = [0, 0.11, 0.88, 1]
        railView.layer.mask = railMask
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        railView.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        railView.addGestureRecognizer(tap)
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    var capabilities: LyricStageCapabilities {
        LyricStageCapabilities(supportsWordSync: false,
                               requiresSpectrum: false,
                               supportsLineSeek: true)
    }

    // MARK: 协议面

    func mount(context: LyricStageContext) {
        self.context = context
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        self.snapshot = snapshot
        let newTrackID = snapshot.track?.id
        if newTrackID != trackID {
            trackID = newTrackID
            lines = snapshot.lines
            coverImage = nil
            washKey = nil
            // 在途成图作废（3.7 (44)）：代际 +1，陈旧烘焙落地即弃。
            bakeGeneration += 1
            pendingBakeKeys.removeAll()
            lastPosition = snapshot.anchor.position(atWallTime: CACurrentMediaTime())
            for washView in washViews { washView.removeFromSuperview() }
            washViews = []
            tempCoverView.image = nil
            tempCoverView.isHidden = false
            fallbackView.isHidden = false
            for (_, lineView) in lineViews { lineView.removeFromSuperview() }
            lineViews = [:]
            manualFocus = nil
            particleView.cancel()
            prevTickPosition = -1
            let resolved = resolveAnchor(snapshot.anchor.position(atWallTime: CACurrentMediaTime()))
            activeIndex = resolved.active
            focusIndex = resolved.anchor
            loadCoverAndWash(snapshot)
            relayout(animate: false)
            runRailIntro()
        } else {
            let linesChanged = snapshot.lines.count != lines.count
                || snapshot.lines.first?.id != lines.first?.id
                || snapshot.lines.last?.id != lines.last?.id
            if linesChanged {
                lines = snapshot.lines
                for (_, lineView) in lineViews { lineView.removeFromSuperview() }
                lineViews = [:]
                let resolved = resolveAnchor(snapshot.anchor.position(atWallTime: CACurrentMediaTime()))
                activeIndex = resolved.active
                focusIndex = manualFocus ?? resolved.anchor
            }
            // 主题色更新（封面采样到达）→ wash 以新色重成图。
            if let cover = coverImage { startWash(cover) }
            relayout(animate: false)
        }
        applyChromeColors(snapshot.palette)
        applyCustomBackgroundYield()
    }

    /// 自定义背景让位（3.7 (50)，(47) 挂账①）：自定义背景开启
    /// 时藏起自带底——bgContainer 内 wash 成图/封面/回退渐变
    /// 三层与容器外可读性罩（右半 alpha 至 0.82，留着等于没
    /// 让）——宿主最底层 customBgView 随之透出；关闭恢复。只
    /// 动容器显隐：wash 成图管线与文字烘焙链一字不碰（闪退
    /// 未定案面）；bgContainer 内部子视图显隐状态机（切歌复
    /// 显/成图落地藏图）写的是子层，容器级隐藏恒压过之，恢
    /// 复时状态自洽。信号直读 CustomBackgroundStore.current；
    /// 宿主 refreshCustomBackground 在选入/恢复时重推快照，
    /// 本方法随 applySnapshot 即时生效。
    private var customBgYieldApplied = false
    private func applyCustomBackgroundYield() {
        let yield = CustomBackgroundStore.current != nil
        bgContainer.isHidden = yield
        readabilityView.isHidden = yield
        if yield != customBgYieldApplied {
            customBgYieldApplied = yield
            Breadcrumbs.log("monet custombg yield=\(yield ? "on" : "off")")
        }
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        bgContainer.layer.speed = isActive ? 1 : 0
        if isActive { installDriftIfNeeded() }
    }

    func frameTick(position: TimeInterval) {
        lastPosition = position
        guard isActive, snapshot != nil, !lines.isEmpty else { return }
        let resolved = resolveAnchor(position)
        // 粒子换行（3.7 (49)）：自然顺翻（焦点 +1、新焦点
        // 行刚转 active、位置连续推进）时，先在 relayout
        // 前采旧焦点行（仍在焦点几何），relayout 后采新焦
        // 点行。手动平移/seek 跳变/回退一律不触发。
        let continuous = prevTickPosition >= 0
            && position - prevTickPosition >= 0
            && position - prevTickPosition < 0.5
        prevTickPosition = position
        let oldFocus = focusIndex
        var outgoingField: ParticleField?
        let flipCandidate = continuous
            && StageEffectSettings.particleFlipEnabled
            && particleView.isAvailable
            && manualFocus == nil
            && resolved.anchor == oldFocus + 1
            && resolved.active == resolved.anchor
        if flipCandidate, let oldView = lineViews[oldFocus] {
            outgoingField = ParticleFieldSampler.sample(
                view: oldView, in: rootView, maxPoints: 1600)
        }
        var needsLayout = false
        if resolved.active != activeIndex {
            activeIndex = resolved.active
            needsLayout = true
        }
        if manualFocus != nil {
            if CACurrentMediaTime() - lastInteractionAt > 1.8 {
                manualFocus = nil
                if focusIndex != resolved.anchor {
                    focusIndex = resolved.anchor
                    needsLayout = true
                }
            }
        } else if focusIndex != resolved.anchor {
            focusIndex = resolved.anchor
            needsLayout = true
        }
        if needsLayout { relayout(animate: true) }
        if flipCandidate, let outgoingField,
           let newView = lineViews[resolved.anchor],
           let incomingField = ParticleFieldSampler.sample(
               view: newView, in: rootView, maxPoints: 1600) {
            particleView.begin(outgoing: outgoingField,
                               incoming: incomingField, duration: 1.0)
        }
        particleView.tick()
        if let current = activeIndex, let lineView = lineViews[current] {
            lineView.updateSweep(position: position, lineEnd: lines[current].end)
        }
    }

    func unmount() {
        coverTask?.cancel()
        washTask?.cancel()
        coverGeneration += 1
        washGeneration += 1
        bakeGeneration += 1
        pendingBakeKeys.removeAll()
        particleView.cancel()
        rootView.removeFromSuperview()
    }

    // MARK: 锚点与状态

    private func resolveAnchor(_ t: TimeInterval) -> (anchor: Int, active: Int?) {
        guard !lines.isEmpty else { return (0, nil) }
        if let current = LyricParser.currentIndex(in: lines, at: t) {
            if t <= lines[current].end { return (current, current) }
            if current + 1 < lines.count { return (current + 1, nil) }
            return (current, nil)
        }
        return (0, nil)
    }

    /// 行状态由播放时间对行时段判定（与焦点/滚动无关，
    /// 与网页口径一致）：时段内 active、已结束 passed、
    /// 未开始 waiting。
    private func status(of index: Int) -> LineStatus {
        if index == activeIndex { return .active }
        guard index < lines.count else { return .waiting }
        return lines[index].end <= lastPosition ? .passed : .waiting
    }

    private func tone(status: LineStatus, offset: Int, m: Metrics) -> Tone {
        switch status {
        case .active:
            return Tone(opacity: 1, scale: 1, blur: 0, baseAlpha: 0.34)
        case .waiting:
            let d = max(abs(offset), 1)
            return Tone(
                opacity: CGFloat(min(max(0.72 - Double(d - 1) * 0.18, 0.36), 0.72)),
                scale: CGFloat(min(max(Double(m.inactiveScale) * pow(0.9, Double(d - 1)), 0.68), 0.92)),
                blur: d == 1 ? 0.7 : CGFloat(1.8 + Double(d - 2) * 0.8),
                baseAlpha: 0.46)
        case .passed:
            let d = max(abs(offset), 1)
            return Tone(
                opacity: CGFloat(min(max(0.52 - Double(d - 1) * 0.12, 0.28), 0.52)),
                scale: CGFloat(min(max(Double(m.inactiveScale) * pow(0.9, Double(d - 1)), 0.68), 0.92)),
                blur: CGFloat(1.1 + Double(d - 1) * 0.7),
                baseAlpha: 0.36)
        }
    }

    // MARK: 布局

    private func metrics() -> Metrics {
        let width = max(rootView.bounds.width, 1)
        let w = Double(width)
        let lyric = min(max(21.44, 0.0275 * w), 36.48) * 1.2
        let inactive = min(max(17.28, 0.02 * w), 23.68) * 1.2
        let inactiveScale = CGFloat(min(max(inactive / max(lyric, 1), 0.72), 0.92))
        let glowBuffer = (lyric * 1.2).rounded()
        return Metrics(fontPx: CGFloat(lyric), inactiveScale: inactiveScale,
                       glowBuffer: CGFloat(glowBuffer),
                       contentWidth: max(width - CGFloat(glowBuffer) * 2, 40))
    }

    private func performLayout() {
        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        bgContainer.frame = bounds
        tempCoverView.frame = bounds
        fallbackView.frame = bounds
        fallbackGradient.frame = bounds
        for washView in washViews { washView.frame = bounds }
        readabilityView.frame = bounds
        readabilityGradient.frame = bounds
        particleView.frame = bounds
        railView.layer.mask?.frame = railView.bounds
        let portraitWidth = min(0.46 * bounds.width, 300,
                                max(bounds.height * 0.30, 110))
        portraitShadowView.frame = CGRect(
            x: (bounds.width - portraitWidth) / 2, y: 10,
            width: portraitWidth, height: portraitWidth)
        portraitClipView.frame = portraitShadowView.bounds
        for layer in portraitLayers { layer.frame = portraitClipView.bounds }
        let railTop = portraitShadowView.frame.maxY + 10
        railView.frame = CGRect(x: 0, y: railTop, width: bounds.width,
                                height: max(bounds.height - railTop, 60))
        railView.layer.mask?.frame = railView.bounds
        if let palette = snapshot?.palette { applyChromeColors(palette) }
        installDriftIfNeeded()
        relayout(animate: false)
        runPortraitIntroIfNeeded()
    }

    private func applyChromeColors(_ palette: PaletteTokens) {
        // 无成图/成图未就绪时的回退渐变（135deg 对角）。
        fallbackGradient.colors = [
            palette.accent.withAlphaComponent(0.22).cgColor,
            palette.background.withAlphaComponent(0.96).cgColor,
            palette.primary.withAlphaComponent(0.18).cgColor,
        ]
        fallbackGradient.locations = [0, 0.5, 1]
        fallbackGradient.startPoint = CGPoint(x: 0, y: 0)
        fallbackGradient.endPoint = CGPoint(x: 1, y: 1)
        // 可读性渐变罩（水平，背景色自左 0.18 → 0.82）。
        readabilityGradient.colors = [
            palette.background.withAlphaComponent(0.18).cgColor,
            palette.background.withAlphaComponent(0.32).cgColor,
            palette.background.withAlphaComponent(0.66).cgColor,
            palette.background.withAlphaComponent(0.82).cgColor,
        ]
        readabilityGradient.locations = [0, 0.34, 0.70, 1]
        readabilityGradient.startPoint = CGPoint(x: 0, y: 0.5)
        readabilityGradient.endPoint = CGPoint(x: 1, y: 0.5)
        portraitShadowView.backgroundColor = palette.primary.withAlphaComponent(0.08)
        portraitShadowView.layer.shadowColor = palette.background
            .withAlphaComponent(0.45).cgColor
    }

    // MARK: 轨道排布（网页 buildPositionedEntries 对译）

    private func relayout(animate: Bool) {
        guard let snap = snapshot, rootView.bounds.width > 0,
              railView.bounds.height > 0 else { return }
        guard !lines.isEmpty else {
            for (_, lineView) in lineViews { lineView.removeFromSuperview() }
            lineViews = [:]
            return
        }
        let m = metrics()
        let focus = min(max(manualFocus ?? focusIndex, 0), lines.count - 1)
        let lo = max(0, focus - 4), hi = min(lines.count - 1, focus + 4)
        // 1) 内容配置（boxHeight 就此确定）。
        var tones: [Int: Tone] = [:]
        for index in lo...hi {
            let lineStatus = status(of: index)
            let lineTone = tone(status: lineStatus, offset: index - focus, m: m)
            tones[index] = lineTone
            let lineView = lineViews[index] ?? createLineView(index: index)
            configure(lineView, index: index, status: lineStatus,
                      tone: lineTone, m: m, palette: snap.palette)
        }
        // 2) 位置：focus 行 scaled 高的中心落在轨道高 ×0.46，
        //    其余按 scaledHeight + gap 逐行累加。
        let gap = CGFloat(activeIndex != nil
            ? max(18, m.fontPx * 0.49) : max(14, m.fontPx * 0.38))
        var tops: [Int: CGFloat] = [:]
        let focusTone = tones[focus] ?? Tone(opacity: 1, scale: 1, blur: 0, baseAlpha: 0.34)
        let focusView = lineViews[focus]
        let focusScaled = (focusView?.boxHeight ?? 0) * focusTone.scale
        var cursor = railView.bounds.height * 0.46 - focusScaled / 2
        tops[focus] = cursor
        if focus > lo {
            for index in stride(from: focus - 1, through: lo, by: -1) {
                let scaled = (lineViews[index]?.boxHeight ?? 0) * (tones[index]?.scale ?? 1)
                cursor -= scaled + gap
                tops[index] = cursor
            }
        }
        cursor = tops[focus] ?? 0
        if focus < hi {
            for index in (focus + 1)...hi {
                let prevScaled = (lineViews[index - 1]?.boxHeight ?? 0)
                    * (tones[index - 1]?.scale ?? 1)
                cursor += prevScaled + gap
                tops[index] = cursor
            }
        }
        // 3) 应用目标（弹簧/补间与网页口径同值）。
        for index in lo...hi {
            guard let lineView = lineViews[index], let top = tops[index],
                  let lineTone = tones[index] else { continue }
            let targetCenterY = top + lineView.boxHeight / 2
            applyTarget(lineView, centerY: targetCenterY, tone: lineTone,
                        animate: animate)
        }
        // 4) 窗外行出场。
        let exiting = lineViews.filter { $0.key < lo || $0.key > hi }
        for (index, lineView) in exiting {
            lineViews[index] = nil
            exitLineView(lineView, upward: index < focus)
        }
    }

    private func applyTarget(_ lineView: MonetRailLineView, centerY: CGFloat,
                             tone: Tone, animate: Bool) {
        let layer = lineView.layer
        if !animate {
            layer.removeAnimation(forKey: "monet.y")
            layer.removeAnimation(forKey: "monet.scale")
            layer.removeAnimation(forKey: "monet.opacity")
            lineView.center = CGPoint(x: lineView.center.x, y: centerY)
            lineView.transform = CGAffineTransform(scaleX: tone.scale, y: tone.scale)
            lineView.alpha = tone.opacity
            return
        }
        let presentation = layer.presentation()
        let fromY = presentation?.position.y ?? lineView.center.y
        let fromTransform = presentation?.transform ?? layer.transform
        let fromOpacity = presentation?.opacity ?? Float(lineView.alpha)
        lineView.center = CGPoint(x: lineView.center.x, y: centerY)
        lineView.transform = CGAffineTransform(scaleX: tone.scale, y: tone.scale)
        lineView.alpha = tone.opacity
        let springY = CASpringAnimation(keyPath: "position.y")
        springY.fromValue = fromY
        springY.toValue = centerY
        springY.stiffness = 142
        springY.damping = 28
        springY.mass = 0.82
        springY.duration = springY.settlingDuration
        layer.add(springY, forKey: "monet.y")
        let springScale = CASpringAnimation(keyPath: "transform")
        springScale.fromValue = NSValue(caTransform3D: fromTransform)
        springScale.toValue = NSValue(caTransform3D: layer.transform)
        springScale.stiffness = 150
        springScale.damping = 30
        springScale.mass = 0.78
        springScale.duration = springScale.settlingDuration
        layer.add(springScale, forKey: "monet.scale")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = tone.opacity
        fade.duration = 0.28
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
        layer.add(fade, forKey: "monet.opacity")
    }

    private func createLineView(index: Int) -> MonetRailLineView {
        let lineView = MonetRailLineView(lineIndex: index)
        let m = metrics()
        lineView.bounds = CGRect(x: 0, y: 0, width: m.contentWidth, height: 0)
        // 入场初态（网页 entry 口径：opacity 0、y 偏移 ∓34、
        // scale ×0.98），随后由 applyTarget 弹簧归位。
        let focus = manualFocus ?? focusIndex
        lineView.center = CGPoint(
            x: m.glowBuffer + m.contentWidth / 2,
            y: railView.bounds.height * 0.46 + (index >= focus ? 34 : -34))
        lineView.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        lineView.alpha = 0
        railView.addSubview(lineView)
        lineViews[index] = lineView
        return lineView
    }

    private func exitLineView(_ lineView: MonetRailLineView, upward: Bool) {
        lineView.layer.removeAnimation(forKey: "monet.y")
        lineView.layer.removeAnimation(forKey: "monet.scale")
        lineView.layer.removeAnimation(forKey: "monet.opacity")
        exitingViews.append(lineView)
        let animator = UIViewPropertyAnimator(
            duration: 0.2,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.32, y: 0.72),
                controlPoint2: CGPoint(x: 0, y: 1)))
        animator.addAnimations {
            lineView.center = CGPoint(
                x: lineView.center.x,
                y: lineView.center.y + (upward ? -38 : 38))
            lineView.alpha = 0
            let current = lineView.transform
            lineView.transform = current.scaledBy(x: 0.98, y: 0.98)
        }
        animator.addCompletion { [weak self, weak lineView] _ in
            lineView?.removeFromSuperview()
            if let lineView { self?.exitingViews.removeAll { $0 === lineView } }
        }
        animator.startAnimation()
    }

    // MARK: 行内容配置

    private func configure(_ lineView: MonetRailLineView, index: Int,
                           status: LineStatus, tone: Tone, m: Metrics,
                           palette: PaletteTokens) {
        let line = lines[index]
        let font = StageFonts.bold(size: m.fontPx)
        let padTop = max(m.fontPx * 0.16, 8)
        let padBottom = max(m.fontPx * 0.34, 14)
        let paletteSig = monetHex(palette.primary) + monetHex(palette.accent)
        lineView.bounds = CGRect(x: 0, y: 0, width: m.contentWidth,
                                 height: lineView.bounds.height)
        lineView.center = CGPoint(x: m.glowBuffer + m.contentWidth / 2,
                                  y: lineView.center.y)
        if status == .active {
            let key = "sweep|\(line.id)|\(paletteSig)|\(Int(m.contentWidth))"
            if lineView.contentKey != key {
                let tokens = sweepTokens(for: line)
                let wordColor = palette.primary.withAlphaComponent(0.98)
                let baseColor = palette.primary.withAlphaComponent(tone.baseAlpha)
                let lineHeight = StageTextKit.lineHeight(
                    text: line.text, font: font, fontPx: m.fontPx)
                // 高度纯测量先行（与成图后同源同值、不跳高）；
                // 逐词成图后台备好再装配换入（3.7 (44)）。
                let height = StageSweepLineView.measureHeight(
                    tokens: tokens, font: font, maxWidth: m.contentWidth,
                    lineHeight: lineHeight)
                let boxHeight = padTop + height + padBottom
                let textFrame = CGRect(x: 0, y: padTop,
                                       width: m.contentWidth, height: height)
                let cacheKey = "\(trackID ?? "?")|\(key)"
                if let prepared = sweepBakeLookup(cacheKey) {
                    let sweep = StageSweepLineView()
                    sweep.configure(
                        tokens: tokens, font: font, glowColor: wordColor,
                        isChorus: false, maxWidth: m.contentWidth,
                        lineHeight: lineHeight, rtl: false,
                        prepared: prepared)
                    lineView.showSweep(sweep, textFrame: textFrame,
                                       boxHeight: boxHeight, key: key)
                } else {
                    // 占位：空扫字视图先占住行盒，成图落地换入。
                    lineView.showSweep(StageSweepLineView(),
                                       textFrame: textFrame,
                                       boxHeight: boxHeight, key: key)
                    scheduleSweepBake(
                        cacheKey: cacheKey, key: key, index: index,
                        tokens: tokens, font: font, baseColor: baseColor,
                        fillColor: wordColor, glowColor: wordColor,
                        lineHeight: lineHeight, maxWidth: m.contentWidth,
                        textFrame: textFrame, boxHeight: boxHeight,
                        lineEnd: line.end)
                }
            }
            lineView.updateSweep(position: lastPosition, lineEnd: line.end)
        } else {
            let maxLines = 2
            let color = status == .passed
                ? palette.primary.withAlphaComponent(0.98)
                : palette.primary.withAlphaComponent(tone.baseAlpha)
            let blurBucket = Int((tone.blur * 10).rounded())
            let key = "static|\(line.id)|\(status == .passed ? "p" : "w")|\(blurBucket)|\(paletteSig)|\(Int(m.contentWidth))"
            if lineView.contentKey != key {
                // 折行测量主线程先行（无渲染、盒高首帧即准）；
                // 栅格成图＋模糊走后台 bakeQueue（3.7 (44)）。
                let wrapped = StageTextKit.wrap(
                    text: line.text, font: font, maxWidth: m.contentWidth,
                    maxLines: maxLines, fontPx: m.fontPx)
                let rows = max(wrapped.rows.count, 1)
                let clipped = wrapped.clipped
                let lineHeight = wrapped.lineHeight
                let textHeight = CGFloat(rows) * lineHeight
                let boxHeight = padTop + textHeight + padBottom
                let textFrame = CGRect(x: 0, y: padTop,
                                       width: m.contentWidth,
                                       height: textHeight)
                let fadeHeight = max(m.fontPx * 0.55, 12)
                let cacheKey = "\(trackID ?? "?")|\(key)"
                if let cached = staticBakeLookup(cacheKey) {
                    lineView.showStatic(
                        image: cached, textFrame: textFrame,
                        boxHeight: boxHeight, clipped: clipped,
                        fadeHeight: fadeHeight, key: key)
                } else {
                    // 占位：底色（wash/fallback）先行，成图淡入。
                    lineView.showStatic(
                        image: nil, textFrame: textFrame,
                        boxHeight: boxHeight, clipped: clipped,
                        fadeHeight: fadeHeight, key: key)
                    scheduleStaticBake(
                        cacheKey: cacheKey, key: key, index: index,
                        text: line.text, font: font, color: color,
                        maxWidth: m.contentWidth, maxLines: maxLines,
                        fontPx: m.fontPx, blur: tone.blur)
                }
            }
        }
    }

    /// 图的像素字节估算（bake 面包屑与 LRU 字节上限共用）：
    /// CGImage 的 bytesPerRow × height，无 CGImage 时按点尺寸
    /// ×scale² ×4 兜底。
    private static func imageBytes(_ image: UIImage?) -> Int {
        guard let image else { return 0 }
        if let cg = image.cgImage {
            return cg.bytesPerRow * cg.height
        }
        let scale = image.scale
        return Int(image.size.width * scale) * Int(image.size.height * scale) * 4
    }

    /// 高斯模糊（后台专用，3.7 (44)）：共享 CIContext，不再
    /// 逐行新建；只从 bakeQueue 调用。
    private static func blurredImage(_ image: UIImage, radiusPt: CGFloat) -> UIImage {
        guard let ci = CIImage(image: image) else { return image }
        let blurred = ci.clampedToExtent().applyingFilter(
            "CIGaussianBlur",
            parameters: [kCIInputRadiusKey: radiusPt * image.scale])
        guard let cg = sharedCIContext.createCGImage(blurred, from: ci.extent)
        else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }

    // MARK: 成图烘焙调度（3.7 (44)）

    private func staticBakeLookup(_ cacheKey: String) -> UIImage? {
        guard let hit = staticBakeCache.firstIndex(where: { $0.key == cacheKey })
        else { return nil }
        let entry = staticBakeCache.remove(at: hit)
        staticBakeCache.append(entry)
        return entry.image
    }

    private func sweepBakeLookup(_ cacheKey: String) -> [Int: StageSweepWordImages]? {
        guard let hit = sweepBakeCache.firstIndex(where: { $0.key == cacheKey })
        else { return nil }
        let entry = sweepBakeCache.remove(at: hit)
        sweepBakeCache.append(entry)
        return entry.images
    }

    /// 当前屏幕栅格倍率（烘焙出图用）：traitCollection 优先，
    /// 取不到退 UIScreen。烘焙在后台队列执行，倍率必须在主
    /// 线程先捕获再带入（traitCollection 非线程安全）。
    private var currentDisplayScale: CGFloat {
        let s = rootView.traitCollection.displayScale
        return s > 0 ? s : UIScreen.main.scale
    }

    private func scheduleStaticBake(cacheKey: String, key: String, index: Int,
                                    text: String, font: UIFont, color: UIColor,
                                    maxWidth: CGFloat, maxLines: Int,
                                    fontPx: CGFloat, blur: CGFloat) {
        guard !pendingBakeKeys.contains(cacheKey) else { return }
        pendingBakeKeys.insert(cacheKey)
        let generation = bakeGeneration
        let track = trackID
        // 烘焙倍率（3.7 (47) 清晰度修复）：旧版恒 @2x，@3x
        // 屏上静态行恒软 1.5 倍；改按当前屏幕倍率出图，与
        // 显示尺寸 1:1（莫奈行变换 scale ≤1，无需余量）。
        // 3.7 (55) 协调者集成：叠加设置「歌词画布分辨率」档位
        // （SettingsStore.lyricRenderScale，缺省 1.0 不变行为）。
        let bakeScale = currentDisplayScale
            * CGFloat(SettingsStore.lyricRenderScale)
        bakeQueue.async { [weak self] in
            // bake 生命周期面包屑（3.7 (46)，DS 取证清单）：此前
            // 只有落地痕、没有入队/开工/完工痕，崩在栅格化中途
            // 时日志断在半路无从判死。本版 start/done 成对落盘
            // （done 带字节数与耗时），下次闪退一轮对账判死。
            Breadcrumbs.log("monet bake start kind=static gen=\(generation) key=\(key)")
            let startedAt = CACurrentMediaTime()
            var image: UIImage?
            autoreleasepool {
                image = StageTextKit.rasterize(
                    text: text, font: font, color: color, maxWidth: maxWidth,
                    maxLines: maxLines, fontPx: fontPx, scale: bakeScale)?.image
                if blur > 0.05, let sharp = image {
                    image = MonetStageRenderer.blurredImage(sharp, radiusPt: blur)
                }
            }
            let bakeBytes = Self.imageBytes(image)
            let bakeMs = Int((CACurrentMediaTime() - startedAt) * 1000)
            Breadcrumbs.log("monet bake done kind=static gen=\(generation) key=\(key) bytes=\(bakeBytes) ms=\(bakeMs)")
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingBakeKeys.remove(cacheKey)
                // 落地面包屑（3.7 (45) R-5）：成图链此前零埋
                // 点，崩在落地块时日志无从定案；applied /
                // skipped＋原因各落一行。
                guard self.bakeGeneration == generation,
                      self.trackID == track else {
                    Breadcrumbs.log("monet bake skipped kind=static reason=stale key=\(key)")
                    return
                }
                guard let image else {
                    Breadcrumbs.log("monet bake skipped kind=static reason=no-image key=\(key)")
                    return
                }
                self.staticBakeCache.removeAll { $0.key == cacheKey }
                self.staticBakeCache.append((key: cacheKey, image: image))
                // LRU 双上限（3.7 (46)，DS 清单）：张数 24 之外
                // 再加字节上限 64MB——大行图单张可达数 MB，
                // 只按张数封顶时缓存字节可失控（内存硬线：舞台
                // 纹理 ≤200–250MB）。(47) 烘焙升到屏幕倍率后
                // 单图字节 ×2.25（@3x vs @2x），字节上限不变、
                // 实际驻留张数自动收敛。刚入缓存者不淘汰。
                var cacheBytes = self.staticBakeCache.reduce(0) {
                    $0 + Self.imageBytes($1.image)
                }
                while (self.staticBakeCache.count > 24 || cacheBytes > 64 * 1024 * 1024),
                      self.staticBakeCache.count > 1 {
                    cacheBytes -= Self.imageBytes(self.staticBakeCache.removeFirst().image)
                }
                guard let lineView = self.lineViews[index],
                      lineView.contentKey == key else {
                    Breadcrumbs.log("monet bake skipped kind=static reason=key-mismatch key=\(key)")
                    return
                }
                lineView.applyBakedStaticImage(image)
                Breadcrumbs.log("monet bake applied kind=static key=\(key)")
            }
        }
    }

    private func scheduleSweepBake(cacheKey: String, key: String, index: Int,
                                   tokens: [StageSweepToken], font: UIFont,
                                   baseColor: UIColor, fillColor: UIColor,
                                   glowColor: UIColor, lineHeight: CGFloat,
                                   maxWidth: CGFloat, textFrame: CGRect,
                                   boxHeight: CGFloat, lineEnd: TimeInterval) {
        guard !pendingBakeKeys.contains(cacheKey) else { return }
        pendingBakeKeys.insert(cacheKey)
        let generation = bakeGeneration
        let track = trackID
        // 扫字烘焙倍率同 static（3.7 (47)）：按当前屏幕倍率。
        // 3.7 (55) 协调者集成：同 static 叠加歌词画布分辨率档位。
        let bakeScale = currentDisplayScale
            * CGFloat(SettingsStore.lyricRenderScale)
        bakeQueue.async { [weak self] in
            // bake 生命周期面包屑（3.7 (46)）：同 static bake。
            Breadcrumbs.log("monet bake start kind=sweep gen=\(generation) key=\(key)")
            let startedAt = CACurrentMediaTime()
            var prepared: [Int: StageSweepWordImages] = [:]
            autoreleasepool {
                prepared = StageTextKit.prepareSweepImages(
                    tokens: tokens, font: font, baseColor: baseColor,
                    fillColor: fillColor, glowColor: glowColor,
                    lineHeight: lineHeight, rtl: false, scale: bakeScale)
            }
            let bakeBytes = prepared.values.reduce(0) { sum, word in
                sum + Self.imageBytes(word.glow) + Self.imageBytes(word.base)
                    + Self.imageBytes(word.fill)
            }
            let bakeMs = Int((CACurrentMediaTime() - startedAt) * 1000)
            Breadcrumbs.log("monet bake done kind=sweep gen=\(generation) key=\(key) bytes=\(bakeBytes) ms=\(bakeMs)")
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingBakeKeys.remove(cacheKey)
                // 落地面包屑（3.7 (45) R-5）：同 static bake。
                guard self.bakeGeneration == generation,
                      self.trackID == track else {
                    Breadcrumbs.log("monet bake skipped kind=sweep reason=stale key=\(key)")
                    return
                }
                self.sweepBakeCache.removeAll { $0.key == cacheKey }
                self.sweepBakeCache.append((key: cacheKey, images: prepared))
                // LRU 双上限（3.7 (46)）：张数 8 之外加字节上限
                // 32MB（扫字三图/词，单条可达数 MB）；刚入者不淘汰。
                func entryBytes(_ entry: (key: String, images: [Int: StageSweepWordImages])) -> Int {
                    entry.images.values.reduce(0) { sum, word in
                        sum + Self.imageBytes(word.glow) + Self.imageBytes(word.base)
                            + Self.imageBytes(word.fill)
                    }
                }
                var cacheBytes = self.sweepBakeCache.reduce(0) { $0 + entryBytes($1) }
                while (self.sweepBakeCache.count > 8 || cacheBytes > 32 * 1024 * 1024),
                      self.sweepBakeCache.count > 1 {
                    cacheBytes -= entryBytes(self.sweepBakeCache.removeFirst())
                }
                guard let lineView = self.lineViews[index],
                      lineView.contentKey == key else {
                    Breadcrumbs.log("monet bake skipped kind=sweep reason=key-mismatch key=\(key)")
                    return
                }
                let sweep = StageSweepLineView()
                sweep.configure(
                    tokens: tokens, font: font, glowColor: glowColor,
                    isChorus: false, maxWidth: maxWidth,
                    lineHeight: lineHeight, rtl: false, prepared: prepared)
                lineView.showSweep(sweep, textFrame: textFrame,
                                   boxHeight: boxHeight, key: key)
                lineView.updateSweep(position: self.lastPosition,
                                     lineEnd: lineEnd)
                Breadcrumbs.log("monet bake applied kind=sweep key=\(key)")
            }
        }
    }

    // MARK: 扫字 token（网页 resolveMonetSweepWords 对译）

    private struct ResolvedWord {
        var text: String
        var start: TimeInterval
        var end: TimeInterval
        var graphemeRange: Range<Int>
    }

    private func sweepTokens(for line: LyricLine) -> [StageSweepToken] {
        let graphemes = line.text.map { String($0) }
        var words: [ResolvedWord] = []
        if let lineWords = line.words, !lineWords.isEmpty {
            let units = lineWords.map {
                StageWordUnit(text: $0.text, start: $0.start, end: $0.end)
            }
            if units.count == 1, units[0].text == line.text {
                // 单词即整行：先估算再线性拉伸回该词时段。
                let unit = units[0]
                let estimated = buildEstimatedWords(
                    text: line.text, start: unit.start,
                    duration: max(unit.end - unit.start, 0.05))
                if estimated.count > 1,
                   let first = estimated.first, let last = estimated.last {
                    let span = max(last.end - first.start, 0.001)
                    let target = max(unit.end - unit.start, 0.001)
                    words = estimated.map { word in
                        ResolvedWord(
                            text: word.text,
                            start: unit.start + (word.start - first.start) / span * target,
                            end: unit.start + (word.end - first.start) / span * target,
                            graphemeRange: word.graphemeRange)
                    }
                } else if let only = estimated.first {
                    words = [ResolvedWord(text: only.text, start: unit.start,
                                          end: unit.end,
                                          graphemeRange: only.graphemeRange)]
                }
            } else {
                var cursor = 0
                for unit in units {
                    if let range = findRange(of: unit.text, in: graphemes,
                                             from: cursor) {
                        words.append(ResolvedWord(
                            text: unit.text, start: unit.start, end: unit.end,
                            graphemeRange: range))
                        cursor = range.upperBound
                    }
                }
            }
        }
        if words.isEmpty {
            words = buildEstimatedWords(
                text: line.text, start: line.start,
                duration: max(line.end - line.start, 0.05))
        }
        let units = words.map {
            StageWordUnit(text: $0.text, start: $0.start, end: $0.end)
        }
        let allTimes = StageTextKit.graphemeTimes(line: line, words: units)
        var tokens: [StageSweepToken] = []
        var cursor = 0
        for word in words {
            if word.graphemeRange.lowerBound > cursor {
                tokens.append(StageSweepToken(
                    text: graphemes[cursor..<word.graphemeRange.lowerBound].joined(),
                    graphemeRange: cursor..<word.graphemeRange.lowerBound,
                    timed: false))
            }
            let times = (word.graphemeRange.lowerBound..<word.graphemeRange.upperBound)
                .map { allTimes[$0] }
            tokens.append(StageSweepToken(
                text: word.text, graphemeRange: word.graphemeRange,
                timed: true, start: word.start, end: word.end,
                graphemeTimes: times))
            cursor = word.graphemeRange.upperBound
        }
        if cursor < graphemes.count {
            tokens.append(StageSweepToken(
                text: graphemes[cursor..<graphemes.count].joined(),
                graphemeRange: cursor..<graphemes.count, timed: false))
        }
        return tokens
    }

    private func findRange(of wordText: String, in graphemes: [String],
                           from cursor: Int) -> Range<Int>? {
        let wordGraphemes = wordText.map { String($0) }
        guard !wordGraphemes.isEmpty else { return nil }
        var start = cursor
        while start + wordGraphemes.count <= graphemes.count {
            var matches = true
            for j in wordGraphemes.indices where graphemes[start + j] != wordGraphemes[j] {
                matches = false
                break
            }
            if matches { return start..<(start + wordGraphemes.count) }
            start += 1
        }
        return nil
    }

    /// 网页 buildTimedWords 对译：空白切块，含 CJK 块逐字
    /// 素成词（标点权重 0），非 CJK 块整块成词（权重
    /// 1 + 0.15×长）；有效时长 = 行时长 ×0.9，单字下限
    /// 0.05s，末词超界全表等比缩放。
    private func buildEstimatedWords(text: String, start: TimeInterval,
                                     duration: TimeInterval) -> [ResolvedWord] {
        let graphemes = text.map { String($0) }
        var blocks: [(range: Range<Int>, text: String)] = []
        var i = 0
        while i < graphemes.count {
            if graphemes[i] == " " || graphemes[i] == "\t" || graphemes[i] == "\n" {
                i += 1
                continue
            }
            var j = i
            while j < graphemes.count, graphemes[j] != " ", graphemes[j] != "\t",
                  graphemes[j] != "\n" { j += 1 }
            blocks.append((i..<j, graphemes[i..<j].joined()))
            i = j
        }
        let punctuation: Set<String> = ["，", "。", "！", "？", "、", "：", "；",
                                        "\"", "'", "）", "】", "》", "”", "’",
                                        "…", "—", "·", ",", ".", "!", "?",
                                        ":", ";", ")", "]"]
        var raw: [(text: String, range: Range<Int>, weight: Double)] = []
        for block in blocks {
            let containsCJK = block.text.unicodeScalars.contains { scalar in
                (0x3040...0x30FF).contains(scalar.value)
                    || (0x3400...0x4DBF).contains(scalar.value)
                    || (0x4E00...0x9FFF).contains(scalar.value)
                    || (0xF900...0xFAFF).contains(scalar.value)
                    || (0xFF66...0xFF9F).contains(scalar.value)
            }
            if containsCJK {
                for g in block.range {
                    raw.append((graphemes[g], g..<(g + 1),
                                punctuation.contains(graphemes[g]) ? 0 : 1))
                }
            } else {
                raw.append((block.text, block.range,
                            1 + Double(block.range.count) * 0.15))
            }
        }
        let activeDuration = duration * 0.9
        let totalWeight = raw.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0, !raw.isEmpty else { return [] }
        let timePerWeight = activeDuration / totalWeight
        var durations = raw.map { max($0.weight * timePerWeight, 0.05) }
        let totalDuration = durations.reduce(0, +)
        if totalDuration > activeDuration {
            let factor = activeDuration / totalDuration
            durations = durations.map { $0 * factor }
        }
        var cursor = start
        return zip(raw, durations).map { item, wordDuration in
            let wordStart = cursor
            cursor += wordDuration
            return ResolvedWord(text: item.text, start: wordStart, end: cursor,
                                graphemeRange: item.range)
        }
    }

    // MARK: 封面 / 人像 / 成图

    private func loadCoverAndWash(_ snapshot: LyricStageSnapshot) {
        coverTask?.cancel()
        washTask?.cancel()
        coverGeneration += 1
        washGeneration += 1
        guard let raw = snapshot.track?.artworkURL, !raw.isEmpty else {
            fadeOutPortrait()
            return
        }
        let urlString = NativeCoverLoader.shared.proxiedURLString(raw, tier: 1024) ?? raw
        if let temp = NativeCoverLoader.shared.cachedImageAnyTier(raw: raw, excludingTier: 1024) {
            tempCoverView.image = temp
            tempCoverView.isHidden = false
        }
        let taskTrack = trackID
        let myCoverGen = coverGeneration
        coverTask = Task { [weak self] in
            let image = await NativeCoverLoader.shared.image(for: urlString,
                                                             tier: 1024)
            guard let self else { return }
            // 护栏采样（切换前）：恢复线程不保证主线程，
            // isMainThread 必须在切 MainActor 之前取。
            let wasMain = Thread.isMainThread
            Breadcrumbs.log("monet.guard.cover isMainThread=\(wasMain) gen=\(myCoverGen)")
            if Task.isCancelled || self.coverGeneration != myCoverGen {
                Breadcrumbs.log("monet.guard.drop kind=cover reason=\(Task.isCancelled ? "cancelled" : "stale") gen=\(myCoverGen) current=\(self.coverGeneration)")
                return
            }
            guard self.trackID == taskTrack else {
                Breadcrumbs.log("monet.guard.drop kind=cover reason=stale gen=\(myCoverGen) current=\(self.coverGeneration)")
                return
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                // MainActor 落地前复检：排队等待主线程期间
                // 新一代可能已启动，陈旧提交（含 fade）整段
                // 放弃，绝不许旧任务收尾误伤新状态。
                guard !Task.isCancelled,
                      self.coverGeneration == myCoverGen,
                      self.trackID == taskTrack else {
                    Breadcrumbs.log("monet.guard.drop kind=cover reason=\(Task.isCancelled ? "cancelled" : "stale") gen=\(myCoverGen) current=\(self.coverGeneration)")
                    return
                }
                guard let image else {
                    self.fadeOutPortrait()
                    return
                }
                self.coverImage = image
                self.pushPortrait(image, key: urlString)
                self.startWash(image)
            }
        }
    }

    private func pushPortrait(_ image: UIImage, key: String) {
        // 主线程护栏（3.7 (53)）：直操 UIKit，非主线程整段
        // 跳转主线程重入；已在主线程直接走、时序不变。
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.pushPortrait(image, key: key)
            }
            return
        }
        guard key != lastPortraitKey else { return }
        lastPortraitKey = key
        let layer = UIImageView(image: image)
        layer.contentMode = .scaleAspectFill
        layer.clipsToBounds = true
        layer.frame = portraitClipView.bounds
        layer.alpha = 0
        portraitClipView.addSubview(layer)
        portraitLayers.append(layer)
        if portraitLayers.count > 4 {
            let extras = portraitLayers.dropLast(4)
            for extra in extras { extra.removeFromSuperview() }
            portraitLayers.removeFirst(extras.count)
        }
        UIView.animate(withDuration: 0.9, delay: 0,
                       options: [.curveEaseInOut]) {
            layer.alpha = 1
        } completion: { [weak self, weak layer] _ in
            guard let self, let layer,
                  self.portraitLayers.last === layer else { return }
            // settle：顶层不透明后砍其下各层。
            for lower in self.portraitLayers.dropLast() {
                lower.removeFromSuperview()
            }
            self.portraitLayers = [layer]
        }
    }

    private func fadeOutPortrait() {
        // 主线程护栏（3.7 (53)）：同 pushPortrait。调用方
        // 归属见 (53) 报告——同步无图路径与 coverTask 的
        // MainActor 提交段是仅有的两个合法入口，陈旧任务
        // 的 fade 已在提交段代际校验处被拦下、到不了这里。
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.fadeOutPortrait()
            }
            return
        }
        lastPortraitKey = nil
        let layers = portraitLayers
        portraitLayers = []
        UIView.animate(withDuration: 0.9, delay: 0,
                       options: [.curveEaseInOut]) {
            for layer in layers { layer.alpha = 0 }
        } completion: { _ in
            for layer in layers { layer.removeFromSuperview() }
        }
    }

    private func washCacheKey(palette: PaletteTokens) -> String {
        "\(trackID ?? "none")|\(monetHex(palette.background))|"
            + "\(monetHex(palette.primary))|\(monetHex(palette.accent))|monet-v1"
    }

    /// wash 目标画布（像素，3.7 (47)）：当前 bgContainer
    /// 尺寸 × 屏幕倍率 × 漂移余量 1.07（MonetDriftTrack 在
    /// strength 0.5 下对 bgContainer 的最大缩放约 1.062，
    /// 留余量后显示放大恒 ≤1）。上限：长边 2600、总像素
    /// 3.4MP——14 Pro 竖屏约 1179×2250（2.65MP、单图约
    /// 10.6MB），LRU 3 张约 32MB，在舞台纹理预算内。
    /// bounds 未定时退回 .zero（管线内缺省 1920×1080）。
    private func washCanvasSize() -> CGSize {
        let bounds = bgContainer.bounds.size
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = currentDisplayScale
        var pw = bounds.width * scale * 1.07
        var ph = bounds.height * scale * 1.07
        let maxDim: CGFloat = 2600
        let maxPixels: CGFloat = 3_400_000
        var factor = min(1, maxDim / max(pw, ph))
        if pw * ph > maxPixels {
            factor = min(factor, sqrt(maxPixels / (pw * ph)))
        }
        pw *= factor
        ph *= factor
        return CGSize(width: pw.rounded(), height: ph.rounded())
    }

    private func startWash(_ cover: UIImage) {
        guard let snap = snapshot else { return }
        let canvasSize = washCanvasSize()
        let key = washCacheKey(palette: snap.palette)
            + "|\(Int(canvasSize.width))x\(Int(canvasSize.height))"
        if key == washKey { return }
        if let cached = washCache.first(where: { $0.key == key })?.image {
            // 缓存命中同步提交：先作废在途 wash，防其落地
            // 覆盖本次命中图（护栏补强，视觉路径不变）。
            washTask?.cancel()
            washGeneration += 1
            washKey = key
            setWash(cached)
            return
        }
        washTask?.cancel()
        washGeneration += 1
        let myWashGen = washGeneration
        let palette = snap.palette
        washTask = Task { [weak self] in
            let image = await Task.detached(priority: .utility) {
                MonetWashPipeline.build(cover: cover, palette: palette,
                                        canvasSize: canvasSize)
            }.value
            guard let self else { return }
            // 护栏采样（切换前）：detached 成图恢复线程恒
            // 非主线程的概率最高，此值即取证点。
            let wasMain = Thread.isMainThread
            Breadcrumbs.log("monet.guard.wash isMainThread=\(wasMain) gen=\(myWashGen)")
            if Task.isCancelled || self.washGeneration != myWashGen {
                Breadcrumbs.log("monet.guard.drop kind=wash reason=\(Task.isCancelled ? "cancelled" : "stale") gen=\(myWashGen) current=\(self.washGeneration)")
                return
            }
            guard let image else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                // 落地前复检（同 cover）：等待主线程期间被
                // 新一代取代则整段放弃，不写 washKey/缓存、
                // 不调 setWash。
                guard !Task.isCancelled,
                      self.washGeneration == myWashGen else {
                    Breadcrumbs.log("monet.guard.drop kind=wash reason=\(Task.isCancelled ? "cancelled" : "stale") gen=\(myWashGen) current=\(self.washGeneration)")
                    return
                }
                self.washKey = key
                self.washCache.append((key: key, image: image))
                if self.washCache.count > 3 { self.washCache.removeFirst() }
                self.setWash(image)
                Breadcrumbs.log("stage monet wash built")
            }
        }
    }

    private func setWash(_ image: UIImage) {
        // 主线程护栏（3.7 (53)）：同 pushPortrait。
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setWash(image)
            }
            return
        }
        let washView = UIImageView(image: image)
        washView.contentMode = .scaleAspectFill
        washView.clipsToBounds = true
        washView.frame = bgContainer.bounds
        washView.alpha = 0
        bgContainer.addSubview(washView)
        washViews.append(washView)
        let washTrack = trackID
        UIView.animate(withDuration: 0.8, delay: 0,
                       options: [.curveEaseInOut]) {
            washView.alpha = 1
        } completion: { [weak self, weak washView] _ in
            guard let self, let washView, self.trackID == washTrack,
                  self.washViews.contains(where: { $0 === washView })
            else { return }
            for old in self.washViews where old !== washView {
                old.removeFromSuperview()
            }
            self.washViews = [washView]
            self.tempCoverView.isHidden = true
            self.fallbackView.isHidden = true
        }
    }

    // MARK: 漂移与入场

    private func installDriftIfNeeded() {
        let size = bgContainer.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if abs(size.width - driftSize.width) > 1
            || abs(size.height - driftSize.height) > 1 {
            driftSize = size
            let animation = CAKeyframeAnimation(keyPath: "transform")
            animation.values = MonetDriftTrack.keyframeValues(size: size)
            animation.duration = MonetDriftTrack.duration
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            bgContainer.layer.add(animation, forKey: "monet.drift")
        }
    }

    private func runRailIntro() {
        railView.alpha = 0
        railView.transform = CGAffineTransform(translationX: 0, y: 20)
        let animator = UIViewPropertyAnimator(
            duration: 1.2,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.25, y: 1),
                controlPoint2: CGPoint(x: 0.5, y: 1)))
        animator.addAnimations {
            self.railView.alpha = 1
            self.railView.transform = .identity
        }
        animator.startAnimation(afterDelay: 0.65)
    }

    private func runPortraitIntroIfNeeded() {
        guard !didPortraitIntro else { return }
        didPortraitIntro = true
        portraitShadowView.alpha = 0
        var transform = CGAffineTransform(translationX: 50, y: 0)
        transform = transform.scaledBy(x: 0.95, y: 0.95)
        transform = transform.rotated(by: .pi / 180)
        portraitShadowView.transform = transform
        let animator = UIViewPropertyAnimator(
            duration: 1.6,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.25, y: 1),
                controlPoint2: CGPoint(x: 0.5, y: 1)))
        animator.addAnimations {
            self.portraitShadowView.alpha = 1
            self.portraitShadowView.transform = .identity
        }
        animator.startAnimation(afterDelay: 0.25)
    }

    // MARK: 手势（轨道手动滚动 / 点行 seek）

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            appliedPanSteps = 0
            manualFocus = min(max(focusIndex, 0), max(lines.count - 1, 0))
            lastInteractionAt = CACurrentMediaTime()
        case .changed:
            lastInteractionAt = CACurrentMediaTime()
            let translation = gesture.translation(in: railView)
            let steps = Int((-translation.y / 52).rounded(.towardZero))
            let delta = steps - appliedPanSteps
            if delta != 0 {
                appliedPanSteps = steps
                let base = manualFocus ?? focusIndex
                manualFocus = min(max(base + delta, 0), max(lines.count - 1, 0))
                relayout(animate: true)
            }
        case .ended, .cancelled:
            lastInteractionAt = CACurrentMediaTime()
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: railView)
        for (index, lineView) in lineViews where lineView.frame.contains(point) {
            manualFocus = nil
            onSeekRequest?(lines[index].start + 0.01)
            return
        }
    }
}
