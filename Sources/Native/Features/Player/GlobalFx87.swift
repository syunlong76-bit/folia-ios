import UIKit
import QuartzCore

// ============================================================================
// GlobalFx87 — (87) 四特效全局引擎
//
// 把已定版网页样片（控制台改版＋烟花钮样片 index.html 的 FULL-SCREEN
// EFFECTS 段）1:1 移植成原生：烟花花火大会 / 孔明灯 / 下雪 / 刮风。
//
// 架构：
// - 单例 GlobalFx87.shared，install(in:) 建独立 UIWindow
//   （level 1500：低于 alert 2000、高于普通 modal），根视图
//   Fx87RootView 全透明，CADisplayLink 驱动、draw(_:) 里 CGContext
//   绘制。特效只是叠加层：绝不画任何压暗/染色填充，hitTest 默认
//   放行（仅孔明灯命中区与卡片/钮自身区域拦截）。
// - JS 按 60fps 帧单位写参数；iPhone 14 Pro 为 120Hz，故帧步进按
//   dt*60 归一（factor f），位置/衰减/概率均按 f 缩放。
// - fw / lantern / snow 三者互斥（开一个硬停另两个）；wind 独立叠加。
// - 烟雾 smokes / droops 在样片中无生成源，按定版口径不实现。
// ============================================================================

// MARK: - HSL 颜色（JS hsla 是 HSL 色彩空间，与 UIColor 的 HSB 不同，手转 RGB）

private struct FxHSL {
    var h: Double   // 0..<360
    var s: Double   // 0..<100
    var l: Double   // 0..<100
}

private func fxCGColor(_ hsl: FxHSL, alpha: Double) -> CGColor {
    let h = (hsl.h.truncatingRemainder(dividingBy: 360) + 360)
        .truncatingRemainder(dividingBy: 360) / 360
    let s = max(0, min(1, hsl.s / 100))
    let l = max(0, min(1, hsl.l / 100))
    let c = (1 - abs(2 * l - 1)) * s
    let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
    let m = l - c / 2
    var r: Double = 0, g: Double = 0, b: Double = 0
    switch h * 6 {
    case 0..<1: r = c; g = x
    case 1..<2: r = x; g = c
    case 2..<3: g = c; b = x
    case 3..<4: g = x; b = c
    case 4..<5: r = x; b = c
    default:    r = c; b = x
    }
    return UIColor(red: CGFloat(r + m), green: CGFloat(g + m),
                   blue: CGFloat(b + m), alpha: CGFloat(max(0, min(1, alpha)))).cgColor
}

private func fxRGB(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> CGColor {
    UIColor(red: CGFloat(r / 255), green: CGFloat(g / 255),
            blue: CGFloat(b / 255), alpha: CGFloat(max(0, min(1, a)))).cgColor
}

/// (92) 任务 8：渐变对象缓存——旧实现每帧为每颗光晕/每盏
/// 灯新建 CGGradient，是烟花卡的主因之一。按 stops 签名
/// （位置与颜色分量量化到 1/64，alpha 台阶差不可见）缓存
/// 复用；签名集有界（调色板×alpha 台阶），容量 96 满即清。
private var fxGradientCache92: [String: CGGradient] = [:]

private func fxGradient92(stops: [(CGFloat, CGColor)]) -> CGGradient? {
    var key = ""
    for (loc, col) in stops {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(cgColor: col).getRed(&r, green: &g, blue: &b, alpha: &a)
        key += "\(Int((loc * 64).rounded()))/"
            + "\(Int((r * 64).rounded())),\(Int((g * 64).rounded())),"
            + "\(Int((b * 64).rounded())),\(Int((a * 64).rounded()));"
    }
    if let cached = fxGradientCache92[key] { return cached }
    let colors = stops.map { $0.1 } as CFArray
    let locs = stops.map { $0.0 }
    guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: colors, locations: locs) else { return nil }
    if fxGradientCache92.count > 96 { fxGradientCache92.removeAll() }
    fxGradientCache92[key] = grad
    return grad
}

/// (92) 任务 8：火箭辉光精灵（预渲染一次、全程复用）——旧
/// 实现逐火箭逐帧 setShadow(blur:16) 触发离屏渲染，同为
/// 烟花卡主因。径向对称图，翻转绘制无碍。
private let fxRocketGlow92: CGImage? = {
    let side: CGFloat = 56
    let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: side, height: side))
    let image = renderer.image { ctx in
        let colors = [fxRGB(255, 190, 90, 0.55),
                      fxRGB(255, 190, 90, 0)] as CFArray
        if let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors, locations: [0, 1]) {
            let center = CGPoint(x: side / 2, y: side / 2)
            ctx.cgContext.drawRadialGradient(
                grad, startCenter: center, startRadius: 1,
                endCenter: center, endRadius: side / 2, options: [])
        }
    }
    return image.cgImage
}()

/// (93) A4：雪粒共享精灵图（预渲染一次、全程复用）——旧
/// 实现 mid/far 雪粒逐粒逐帧走 fxFillRadial 径向渐变填
/// 充（每帧百余次渐变绘制＋签名计算），是雪开启窗内存/
/// CPU 增量的主构成。改：淡蓝雪色径向软点精灵一张，
/// draw 时按粒径贴图＋setAlpha 控透明，零逐帧分配。
private let fxSnowDot93: CGImage? = {
    let side: CGFloat = 36
    let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: side, height: side))
    let image = renderer.image { ctx in
        let st = (198.0, 226.0, 255.0)   // FxTuning88.snowTint 同值
        let colors = [fxRGB(st.0, st.1, st.2, 0.95),
                      fxRGB(st.0, st.1, st.2, 0.95),
                      fxRGB(st.0, st.1, st.2, 0)] as CFArray
        if let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors, locations: [0, 0.62, 1]) {
            let center = CGPoint(x: side / 2, y: side / 2)
            ctx.cgContext.drawRadialGradient(
                grad, startCenter: center, startRadius: 0,
                endCenter: center, endRadius: side / 2, options: [])
        }
    }
    return image.cgImage
}()

/// (93) E：烟花星粒精灵图集（按花色烘焙、懒加载缓存）——
/// 旧实现逐粒走 hist 轨迹逐段 stroke（≤16 段/粒）＋双
/// stroke 拖尾＋逐帧路径构建，1400 粒上限下是烟花卡的
/// 结构主因。改：每种花色烘焙一张径向精灵（中心提亮同
/// 旧 headPal 口径 s−30/l＋18、边缘归透明），draw 时在
/// plusLighter 下贴图，前一帧位置补一张低 alpha 小精灵
/// 作运动残影——零 stroke、零逐帧路径。签名集有界（调
/// 色板＋花心色），容量 64 满即清。
private var fxSparkSprites93: [String: CGImage] = [:]

private func fxSparkSprite93(_ pal: FxHSL) -> CGImage? {
    let key = "\(Int(pal.h))|\(Int(pal.s))|\(Int(pal.l))"
    if let cached = fxSparkSprites93[key] { return cached }
    var head = pal
    head.s = max(30, head.s - 30)
    head.l = min(92, head.l + 18)
    let side: CGFloat = 36
    let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: side, height: side))
    let image = renderer.image { ctx in
        let colors = [fxCGColor(head, alpha: 1),
                      fxCGColor(pal, alpha: 0.85),
                      fxCGColor(pal, alpha: 0)] as CFArray
        if let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors, locations: [0, 0.4, 1]) {
            let center = CGPoint(x: side / 2, y: side / 2)
            ctx.cgContext.drawRadialGradient(
                grad, startCenter: center, startRadius: 0,
                endCenter: center, endRadius: side / 2, options: [])
        }
    }
    guard let cg = image.cgImage else { return nil }
    if fxSparkSprites93.count > 64 { fxSparkSprites93.removeAll() }
    fxSparkSprites93[key] = cg
    return cg
}

/// 径向渐变填充矩形区（stops 为 (location, color)；调用方按需先设 clip）。
private func fxFillRadial(_ ctx: CGContext, center: CGPoint, r0: CGFloat, r1: CGFloat,
                          stops: [(CGFloat, CGColor)], rect: CGRect) {
    guard let grad = fxGradient92(stops: stops) else { return }
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawRadialGradient(grad, startCenter: center, startRadius: r0,
                           endCenter: center, endRadius: r1, options: [])
    ctx.restoreGState()
}

/// 竖直线性渐变填充当前路径（须先 addPath，再 clip 后调用本函数填 bounds）。
private func fxFillLinearV(_ ctx: CGContext, top: CGPoint, bottom: CGPoint,
                           stops: [(CGFloat, CGColor)], rect: CGRect) {
    guard let grad = fxGradient92(stops: stops) else { return }
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawLinearGradient(grad, start: top, end: bottom, options: [])
    ctx.restoreGState()
}

private func fxRand(_ lo: Double, _ hi: Double) -> Double {
    Double.random(in: lo..<hi)
}

// MARK: - 烟花调色板与预设（照样片）

private let FX_GOLD: [FxHSL] = [FxHSL(h: 42, s: 100, l: 65), FxHSL(h: 40, s: 100, l: 71),
                                FxHSL(h: 44, s: 98, l: 68), FxHSL(h: 43, s: 100, l: 74)]
private let FX_ORNG: [FxHSL] = [FxHSL(h: 27, s: 100, l: 58), FxHSL(h: 30, s: 100, l: 64),
                                FxHSL(h: 24, s: 100, l: 56), FxHSL(h: 33, s: 100, l: 66)]
private let FX_CRIM: [FxHSL] = [FxHSL(h: 338, s: 92, l: 66), FxHSL(h: 348, s: 90, l: 61),
                                FxHSL(h: 330, s: 86, l: 70), FxHSL(h: 343, s: 94, l: 72)]
private let FX_AZUR: [FxHSL] = [FxHSL(h: 205, s: 92, l: 68), FxHSL(h: 213, s: 86, l: 63),
                                FxHSL(h: 198, s: 90, l: 72), FxHSL(h: 218, s: 82, l: 66)]
private let FX_VIOL: [FxHSL] = [FxHSL(h: 272, s: 82, l: 70), FxHSL(h: 262, s: 76, l: 64),
                                FxHSL(h: 282, s: 80, l: 74), FxHSL(h: 268, s: 86, l: 68)]
private let FX_RAIN_PALS: [FxHSL] = [FxHSL(h: 42, s: 100, l: 66), FxHSL(h: 40, s: 100, l: 72),
                                     FxHSL(h: 44, s: 96, l: 62), FxHSL(h: 38, s: 100, l: 70)]

private struct FwPreset {
    var n: Int
    var sp: Double
    var drag: Double
    var decay: Double
    var rain: Int
    var pals: [FxHSL]
    var shell: Double? = nil
    var shellPals: [FxHSL]? = nil
    var halo: (Double, Double, Double) = (255, 186, 92)
    var amp: Double = 1
    var size: Double = 0.8
    var flash: Bool = false
    var crisp: Bool = false

    /// 样片 fwVar(base, pals, halo, shellPals)：换调色板/光晕/内壳色。
    func variant(pals: [FxHSL]? = nil, halo: (Double, Double, Double)? = nil,
                 shellPals: [FxHSL]? = nil) -> FwPreset {
        var o = self
        if let pals = pals { o.pals = pals }
        if let halo = halo { o.halo = halo }
        if let shellPals = shellPals { o.shellPals = shellPals }
        return o
    }
}

private let FW_GIANT = FwPreset(n: 148, sp: 6.6, drag: 0.962, decay: 0.0038, rain: 26,
                                pals: FX_GOLD, shell: 0.55, shellPals: FX_CRIM,
                                amp: 1.6, size: 0.95, flash: true)
private let FW_MAIN = FwPreset(n: 108, sp: 5.6, drag: 0.958, decay: 0.0040, rain: 20,
                               pals: FX_GOLD, shell: 0.52,
                               amp: 1.3, size: 0.9, flash: true)
private let FW_MED = FwPreset(n: 74, sp: 4.4, drag: 0.952, decay: 0.0044, rain: 14,
                              pals: FX_GOLD, shell: 0.5,
                              amp: 1.0, size: 0.85)
private let FW_CRISP = FwPreset(n: 92, sp: 5.2, drag: 0.955, decay: 0.0032, rain: 16,
                                pals: FX_GOLD,
                                amp: 1.2, size: 0.9, crisp: true)

/// (88) 工坊定案默认（Miller 2026-11-25 在页面工坊亲试存值，
/// port88）：工坊 fx 存值是样片基线之上的倍率/定值，换算口径
/// 如下——烟花：大小×0.85＝爆点速度 sp 与星粒 size 同乘；密
/// 度×1.1＝壳星数 n 乘后取整（内壳/花心/金雨由 n 派生同涨）；
/// 辉光×1.7＝光晕 amp 乘子；颜色金＝默认调色板 FX_GOLD 覆盖
/// 演出脚本的逐发轮换色、晕色回预设默认金晕 (255,186,92)。
/// 孔明灯：密度×1.25＝三层配额 [2,7,6]→[3,9,7]、初始盏数
/// 13→16、在场上限 15→19；颜色暖红＝纸面竖直渐变与热核向红
/// 橙移（见 drawLantern）。下雪：颜色淡蓝＝雪色改
/// (198,226,255)；默认开＝装机后由 SceneDelegate 调
/// applyDefaultSnow88（12 秒自融仍为样片既定行为）。
private enum FxTuning88 {
    static let fwSizeMul: Double = 0.85
    static let fwDensityMul: Double = 1.1
    static let fwGlowMul: Double = 1.7
    static let fwGoldDefault = true
    static let lnCap = 19
    static let lnInitial = 16
    static let lnQuota = [3, 9, 7]
    static let snowTint: (Double, Double, Double) = (198, 226, 255)
}

// MARK: - 粒子（类实例，逐帧原地改值）

private final class FxRocket {
    var x: Double, y: Double, vx: Double, vy: Double, ty: Double
    var g: Double = 0.09
    var opts: FwPreset
    init(x: Double, y: Double, vx: Double, vy: Double, ty: Double, opts: FwPreset) {
        self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.ty = ty; self.opts = opts
    }
}

private final class FxSpark {
    var x: Double, y: Double, px: Double, py: Double, vx: Double, vy: Double
    var life: Double = 1, decay: Double
    var pal: FxHSL
    var size: Double
    var willow: Bool
    var drag: Double? = nil
    var histN: Int = 16
    var hist: [CGPoint] = []
    var tw: Double
    var cr: Bool
    var noStrobe: Bool
    var split: Bool = false
    var trail: Bool = false
    var seed: Double
    init(x: Double, y: Double, vx: Double, vy: Double, decay: Double, pal: FxHSL,
         size: Double, willow: Bool, tw: Double, cr: Bool, noStrobe: Bool) {
        self.x = x; self.y = y; self.px = x; self.py = y
        self.vx = vx; self.vy = vy; self.decay = decay; self.pal = pal
        self.size = size; self.willow = willow; self.tw = tw
        self.cr = cr; self.noStrobe = noStrobe
        self.seed = fxRand(0, 100)
    }
}

private final class FxHalo {
    var x: Double, y: Double, r: Double, vr: Double, life: Double = 0.8
    var col: (Double, Double, Double)
    var amp: Double
    init(x: Double, y: Double, vr: Double, col: (Double, Double, Double), amp: Double) {
        self.x = x; self.y = y; self.r = 7; self.vr = vr; self.col = col; self.amp = amp
    }
}

private final class FxCrackle {
    var x: Double, y: Double, life: Double = 1
    init(x: Double, y: Double) { self.x = x; self.y = y }
}

private final class FxRain {
    var x: Double, y: Double, vx: Double, vy: Double
    var life: Double = 1, decay: Double
    var hist: [CGPoint] = []
    var pal: FxHSL
    var size: Double
    init(x: Double, y: Double, vx: Double, vy: Double, decay: Double, pal: FxHSL, size: Double) {
        self.x = x; self.y = y; self.vx = vx; self.vy = vy
        self.decay = decay; self.pal = pal; self.size = size
    }
}

private final class FxLantern {
    var x: Double, y: Double, s: Double, tier: Int
    var vy: Double, vx: Double
    var ph: Double, sway: Double, drift: Double = 0
    var alpha: Double? = nil
    var wish: String? = nil
    var bless: String
    init(x: Double, y: Double, s: Double, tier: Int, vy: Double, vx: Double,
         ph: Double, sway: Double, bless: String) {
        self.x = x; self.y = y; self.s = s; self.tier = tier
        self.vy = vy; self.vx = vx; self.ph = ph; self.sway = sway; self.bless = bless
    }
}

private final class FxFlake {
    var x: Double, y: Double, r: Double, vy: Double
    var ph: Double, sway: Double, o: Double
    var near: Bool
    var rot: Double, vr: Double, tumble: Double, vt: Double
    init(x: Double, y: Double, r: Double, vy: Double, ph: Double, sway: Double,
         o: Double, near: Bool, rot: Double, vr: Double, tumble: Double, vt: Double) {
        self.x = x; self.y = y; self.r = r; self.vy = vy; self.ph = ph
        self.sway = sway; self.o = o; self.near = near; self.rot = rot
        self.vr = vr; self.tumble = tumble; self.vt = vt
    }
}

private final class FxStreak {
    var x: Double, y: Double, vx: Double, vy: Double = 0
    var hist: [CGPoint] = []
    var o: Double, seed: Double
    init(x: Double, y: Double, vx: Double, o: Double, seed: Double) {
        self.x = x; self.y = y; self.vx = vx; self.o = o; self.seed = seed
    }
}

private final class FxLeaf {
    var x: Double, y: Double, vx: Double, vy: Double
    var rot: Double, vr: Double, tumble: Double, vt: Double
    var s: Double, pink: Bool, ph: Double
    init(x: Double, y: Double, vx: Double, vy: Double, rot: Double, vr: Double,
         tumble: Double, vt: Double, s: Double, pink: Bool, ph: Double) {
        self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.rot = rot
        self.vr = vr; self.tumble = tumble; self.vt = vt; self.s = s
        self.pink = pink; self.ph = ph
    }
}

// MARK: - 祝福语池（照样片 BLESSINGS 原样）

private let FX_BLESSINGS: [String] = [
    "愿你所念皆如愿，所行皆坦途", "山高路远，看世界，也找自己", "愿岁岁平安，年年有今朝",
    "心之所向，素履以往", "愿你眼里有光，活成想要的模样", "所求皆所愿，所行化坦途",
    "愿所有的美好，都如期而至", "慢慢来，好运都在路上", "愿你成为自己的太阳，无需借谁的光",
    "日子清净，抬头皆是温柔", "愿有人陪你颠沛流离", "平安喜乐，万事胜意",
    "愿你历尽千帆，归来仍是少年", "星光不问赶路人，时光不负有心人", "愿今夜的灯，替你把愿望送上天",
    "前路浩浩荡荡，万事尽可期待", "愿你一生被爱，一生可爱", "把烦恼放飞，把好运留下"
]

// MARK: - 根视图（透明、纯显示层）

/// (96) 96-1：特效绘制窗透传——UIWindow 自身默认可交互；
/// 只把根视图 isUserInteractionEnabled=false 并不能让窗透传：
/// window.hitTest 会先问子视图（根视图已禁交互→nil），再
/// 回落到 window 自身（在界内且可交互→返回 window 本体），
/// level 1500 又在主窗之上，于是特效一开整窗吞点按——主窗
/// 探针 raw、控制台钮、dim 全收不到触摸（(93)(94)(95) 三包
/// 同型故障的根因候选）。本类对触摸一律返回 nil，点按落
/// 到下层主窗；绘制本身不受影响。
final class FxPassthroughWindow96: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}

/// (96) 96-2：独立退出路——特效开启期间挂一个高于特效窗
/// （level 1600）的小窗，只露一个 × 关闭钮；除钮帧外
/// hitTest 一律 nil 透传，不挡控制台与墙面点按。钮直接调
/// 幂等 forceStopAllFx96，不经控制台 handler 链、不走
/// toggle 翻转（超时与 handler 晚到并发会双翻转）。
final class FxPanicWindow96: UIWindow {
    weak var engine: GlobalFx87?
    private let closeButton = UIButton(type: .system)

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = UIWindow.Level(rawValue: 1600)
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        rootViewController = vc
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeButton.layer.cornerRadius = 22
        closeButton.clipsToBounds = true
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = "关闭特效"
        closeButton.addTarget(self, action: #selector(panicClose96), for: .touchUpInside)
        vc.view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            closeButton.topAnchor.constraint(
                equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(
                equalTo: vc.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    @objc private func panicClose96() {
        engine?.forceStopAllFx96(src: "panic96")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden else { return nil }
        let p = convert(point, to: closeButton)
        return closeButton.bounds.contains(p) ? closeButton : nil
    }
}

final class Fx87RootView: UIView {
    weak var engine: GlobalFx87?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        engine?.render(in: ctx, size: bounds.size)
    }

    // port91（任务 1）：根视图 isUserInteractionEnabled=false
    // （install 时置），整窗不接点按——旧 hitTest/touchesEnded
    // 纸面放行已被 (90) 真机日志证伪、随交互关闭一并退役；
    // 孔明灯点按改走主窗旁路（见 handlePassiveTap），卡片/写
    // 灯钮迁主窗浮层（FxOverlayHost91）。
}

/// port91（任务 1）：主窗浮层宿主——承载自 Fx 窗迁来的祝福
/// 卡/写灯钮/推荐卡。hitTest 纪律：仅当点落在可见子视图
/// （卡/钮）帧内才交回系统命中，其余整屏穿透回主窗。
final class FxOverlayHost91: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // (94) 94-7 白名单制（Miller 10:58 定案：(93) 特效开
        // 启后全屏点不动、只能杀 App）：只交回明确可点控件
        // 本体——命中视图本身是 UIControl，或其祖先链（止于
        // 本宿主）含 UIControl（钮内标签/图标子视图归其钮）。
        // 现网控件全集：祝福卡「收起」钮、写灯钮、推荐卡
        // 「播放」/「下次吧」钮。命中宿主自身、祝福卡/推荐
        // 卡背景、标签、封面图等任何普通容器一律 nil 穿
        // 透回主窗，控制台开/关与点外关台通路恒可达。
        guard let hit = super.hitTest(point, with: event), hit !== self else {
            return nil
        }
        var node: UIView? = hit
        while let v = node, v !== self {
            if v is UIControl { return hit }
            node = v.superview
        }
        return nil
    }
}

private final class Fx87ViewController: UIViewController {
    override func loadView() {
        let v = Fx87RootView(frame: UIScreen.main.bounds)
        v.backgroundColor = .clear
        v.isOpaque = false
        view = v
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}

// MARK: - 引擎

public final class GlobalFx87: NSObject, UIGestureRecognizerDelegate {

    public static let shared = GlobalFx87()

    // 公开回调（集成方接线）
    /// 任一特效状态变化时回调（集成方刷新控制台钮）。
    public var onStateChanged: (() -> Void)?
    /// 烟花收尾出推荐卡时取今日推荐；返回 nil 则不出卡。
    public var recommendationProvider: (() -> (title: String, artist: String, cover: UIImage?)?)?
    /// 推荐卡点「播放」时回调。
    public var onPlayRecommendation: (() -> Void)?
    /// port91（任务 2）：烟花爆点回调（爆点＋晕色），FxLinkage91
    /// 据此给附近封面提亮一拍＋宠物跳跃。
    public var onFwBurst91: ((CGPoint, UIColor) -> Void)?

    public private(set) var isFireworks = false
    public private(set) var isLanterns = false
    public private(set) var isSnow = false
    public private(set) var isWind = false

    // 窗口与视图
    private var window: UIWindow?
    private var rootView: Fx87RootView?
    private weak var mainWindow: UIWindow?
    /// (96) 96-2：独立退出窗（level 1600，平时隐藏）。
    private var panicWindow96: FxPanicWindow96?
    /// port91（任务 1）：主窗浮层宿主（祝福卡/写灯钮/推荐卡的新家）。
    private var overlayHost91: FxOverlayHost91?
    /// (92) 任务 1：被动点按识别器（随宿主迁窗，见 attachOverlay92）。
    private var passiveTap91: UITapGestureRecognizer?
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    // 卡片与钮（根视图子视图）
    private var flashView: UIView?
    private var blessCard: UIView?
    private var blessLabel: UILabel?
    private var blessHideWork: DispatchWorkItem?
    /// (94) 94-7：showBless 防重入计数（展示中再触发落痕）。
    private var blessDup94 = 0
    private var wishButton: UIButton?
    private var recCard: UIView?
    private var recCover: UIImageView?
    private var recTitle: UILabel?
    private var recArtist: UILabel?
    /// (93) C4：推荐卡默认落位约束（底部 −46/宽 ≤340/居中，
    /// 控制台不在场时用）与控制台对齐动态约束（在场时用，
    /// show 时按 presentedCardFrame 现建、hide/换态时拆）。
    private var recDefaultPos93: [NSLayoutConstraint] = []
    private var recDynPos93: [NSLayoutConstraint] = []
    /// (93) C4：推荐卡 12 秒自动轮换计时器（卡可见＋任一
    /// 特效开启时才转，关卡即停）。
    private var recRotateTimer93: Timer?

    // 帧状态（now 为毫秒，与样片 performance.now() 同口径）
    private var nowMs: Double = 0
    private var W: Double = 0
    private var H: Double = 0
    private var windPow: Double = 0

    // 烟花
    private var rockets: [FxRocket] = []
    private var sparks: [FxSpark] = []
    private var crackles: [FxCrackle] = []
    private var halos: [FxHalo] = []
    private var rains: [FxRain] = []
    private var splitQueue: [FxSpark] = []
    private var fwStart: Double = 0
    private var fwStep: Int = 0
    private var recShown = false

    // 孔明灯
    private var lanterns: [FxLantern] = []
    private var lnLastSpawn: Double = 0
    private var lnStopping = false

    // 下雪
    private var flakes: [FxFlake] = []
    private var snStart: Double = 0
    private var snMelt: Double = 1

    // 刮风
    private var streaks: [FxStreak] = []
    private var leaves: [FxLeaf] = []
    private var wdStart: Double = 0

    private override init() { super.init() }

    // MARK: 安装

    /// 由集成方在 scene 激活后调用：建独立特效窗口并在主 window 上
    /// 挂被动点按识别器（烟花在场时点任意处补放一发）。可重复调用。
    public func install(in scene: UIWindowScene) {
        if window != nil { return }
        W = Double(scene.screen.bounds.width)
        H = Double(scene.screen.bounds.height)
        let win = FxPassthroughWindow96(windowScene: scene)
        win.windowLevel = UIWindow.Level(rawValue: 1500)
        win.backgroundColor = .clear
        win.isOpaque = false
        // (96) 96-1：窗级再关一道交互——hitTest override 已
        // 保证透传；isUserInteractionEnabled=false 作双保险，
        // 任一层失效仍不吞点按。
        win.isUserInteractionEnabled = false
        let vc = Fx87ViewController()
        vc.view.backgroundColor = .clear
        win.rootViewController = vc
        window = win
        if let rv = vc.view as? Fx87RootView {
            rv.engine = self
            rv.contentScaleFactor = scene.screen.scale
            // port91（任务 1）：Fx 窗改纯显示层——根视图关交互、
            // 整窗不接点按；闪光层是纯视觉件、仍留 Fx 窗内。
            rv.isUserInteractionEnabled = false
            rootView = rv
            buildFlash91(in: rv)
        }
        win.isHidden = true

        // (96) 96-2：独立退出窗与特效窗同 scene 建，平时隐藏，
        // 任一特效开启边沿才现身（见 refreshTapProbe92）。
        let panic = FxPanicWindow96(windowScene: scene)
        panic.engine = self
        panicWindow96 = panic

        // (88) 工坊 fx 定案落值见证（FxTuning88）。
        Breadcrumbs.log("port88 fx=fw.85/1.1/1.7g ln1.25r snPale")
        // port91（任务 1）：纯显示层架构落位见证。
        Breadcrumbs.log("p91 fxwin=pure")

        // (92) 任务 1：宿主与被动识别器只许挂真主窗。install
        // 由 SceneDelegate 在主窗建成前调用，此时 scene 里
        // 只有刚建的 Fx 窗自身——(91) 正是把两者挂到了 Fx
        // 窗上（审计 Q4 定案：旁路永不触发、祝福卡截点按）。
        // 此处排除 Fx 窗自身：已有真主窗（scene 重连）即挂，
        // 否则等 SceneDelegate 建窗后调 attachOverlay92。
        if let main = scene.windows.first(where: { $0 !== win }) {
            attachOverlay92(to: main)
        }
    }

    /// (92) 任务 1：把浮层宿主（祝福卡/写灯钮/推荐卡）与被
    /// 动点按识别器挂到真主窗。同一宿主实例迁挂（卡片随迁
    /// 不重建），识别器随迁；落 p92 自证记宿主所在窗类名
    /// 与 level，真机日志可直接对账宿主落点。
    public func attachOverlay92(to main: UIWindow) {
        mainWindow = main
        let host: FxOverlayHost91
        if let existing = overlayHost91 {
            host = existing
            host.removeFromSuperview()
        } else {
            host = FxOverlayHost91()
            host.backgroundColor = .clear
            host.translatesAutoresizingMaskIntoConstraints = false
            overlayHost91 = host
            buildCards91(in: host)
        }
        main.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            host.topAnchor.constraint(equalTo: main.topAnchor),
            host.bottomAnchor.constraint(equalTo: main.bottomAnchor),
        ])
        if passiveTap91 == nil {
            let tap = UITapGestureRecognizer(
                target: self, action: #selector(handlePassiveTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            passiveTap91 = tap
        }
        if let tap = passiveTap91 {
            tap.view?.removeGestureRecognizer(tap)
            main.addGestureRecognizer(tap)
        }
        if let probe = tapProbe92, probe.view !== main {
            probe.view?.removeGestureRecognizer(probe)
            main.addGestureRecognizer(probe)
        }
        Breadcrumbs.log("p92 fxhost win=\(String(describing: type(of: main)))"
            + " level=\(Int(main.windowLevel.rawValue))")
        installTapProbe92IfNeeded()
    }

    // MARK: (92) 加码 1：点按到达探针

    /// 特效开启期间装在主窗的被动识别器：每次点按落一条节
    /// 流面包屑（每秒至多 2 条、粗粒度九宫格区域），使日志
    /// 能自证「特效开着时点按到达主窗」——(91)「特效开着全
    /// 屏点死」在代码里无对应结构（审计 Q10 未定案），本探
    /// 针即为下次定案而设。特效全关时识别器停用、零落痕。
    private var tapProbe92: UITapGestureRecognizer?
    private var tapProbeCount92 = 0
    private var tapProbeWindowStart92: CFTimeInterval = 0
    /// (95) 任务 1：识别器级原始落痕状态——should 落痕同
    /// 秒合并节流（probeRawLastSec95＝已落行的整秒桶）；
    /// probeFirstPending95＝arm 后第一笔 shouldReceive 必
    /// 落 `p95 probe first`（强在岗证明，不受节流吞没）。
    private var probeRawLastSec95: Int = -1
    private var probeFirstPending95 = false
    /// (95) 任务 1：结构兜底看门狗在途标记（350ms 窗内只
    /// 挂一笔，防同窗多点重复兜底）。
    private var probeGuardPending95 = false
    /// (96) 96-2/96-3：特效状态代次——每次 forceStopAllFx96
    /// ＋1；旧 start 回调/旧看门狗超时凭代次过期失效，不许
    /// 把已关的状态翻回开。只在主线程读写。
    private var fxGeneration96 = 0
    /// (96) 96-3：独立看门狗——专用串行队列定时器（不走主
    /// 队列），主线程 heartbeat 由 CADisplayLink tick 喂。
    private let wdQueue96 = DispatchQueue(label: "fx.wd96", qos: .utility)
    private var wdTimer96: DispatchSourceTimer?
    private var wdLastBeat96 = 0
    private var wdLastBeatAt96: CFTimeInterval = 0
    private let beatLock96 = NSLock()
    private var mainBeat96 = 0
    /// (96) 96-3：待确认的关闭请求（generation＋发起时间）；
    /// 超时未确认即在主线程重发一次幂等 forceStop。
    private var closeReq96: (gen: Int, at: CFTimeInterval)?
    private var closeReqReissued96 = -1

    private func installTapProbe92IfNeeded() {
        guard tapProbe92 == nil, let main = mainWindow else { return }
        let probe = UITapGestureRecognizer(
            target: self, action: #selector(handleTapProbe92(_:)))
        probe.cancelsTouchesInView = false
        probe.delegate = self
        probe.isEnabled = isFireworks || isLanterns || isSnow || isWind
        main.addGestureRecognizer(probe)
        tapProbe92 = probe
        refreshTapProbe92()   // (93) A5：装配即对齐 arm 自证状态
        // (95) 任务 1：装配时已在 arm 态（特效先于探针装配
        // 开启）时 arm 边沿已过，补置 first 待落标记，装后
        // 首点仍必落 `p95 probe first`。
        if probeArmed93 { probeFirstPending95 = true }
    }

    /// (93) A5：探针 arm 自证状态——(92) 日志判读定案：探
    /// 针无 arm/disarm 面包屑时，其沉默无法自证在岗。
    private var probeArmed93 = false

    private func refreshTapProbe92() {
        let armed = isFireworks || isLanterns || isSnow || isWind
        tapProbe92?.isEnabled = armed
        // (93) A5：arm/off 边沿各落一条（fx 名取当前开启集）。
        if armed != probeArmed93 {
            probeArmed93 = armed
            if armed {
                var names: [String] = []
                if isFireworks { names.append("fw") }
                if isLanterns { names.append("ln") }
                if isSnow { names.append("sn") }
                if isWind { names.append("wd") }
                Breadcrumbs.log("p93 probe arm fx=\(names.joined(separator: "+"))")
                // (94) 94-7：p94 arm 在岗自证＋浮层层级账（任一
                // 特效开启边沿各落一次，供定性覆层构成）。
                Breadcrumbs.log("p94 fx arm fx=\(names.joined(separator: "+"))")
                logFxLayers94()
                // (95) 任务 1：arm 边沿自检——识别器所在视图
                // 类名＋同窗共存识别器类名清单同行落盘，下份
                // 日志可对账探针到底挂在哪一层、与谁共存。
                probeFirstPending95 = true
                if let probe = tapProbe92, let hostView = probe.view {
                    let peers = (hostView.gestureRecognizers ?? [])
                        .filter { $0 !== probe }
                        .map { String(describing: type(of: $0)) }
                    Breadcrumbs.log("p95 probe arm view="
                        + "\(String(describing: type(of: hostView)))"
                        + " peers=\(peers.isEmpty ? "none" : peers.joined(separator: ","))")
                } else {
                    Breadcrumbs.log("p95 probe arm view=nil peers=none")
                }
                // (96) 96-1/96-2/96-3：arm 边沿三件套——panic
                // 窗现身、独立看门狗武装、孤儿 active 标记同
                // 步写盘；另做一次 hitTest 快照（特效窗应对控
                // 制台钮中心返回 nil、主窗应返回 UIControl）。
                panicWindow96?.isHidden = false
                startWd96()
                let activeNames = names.joined(separator: "+")
                FxEventLog96.markActive(code: activeNames, gen: fxGeneration96)
                FxEventLog96.record("arm fx=\(activeNames) gen=\(fxGeneration96)")
                fxArmHitAudit96()
                // (95) 任务 3：推荐卡触发统一到开启边沿——与
                // p94 fx arm 同点调用呈现判断（会话内只呈一
                // 次，recShown 在全关时复位，见 disarm 边沿）。
                maybeShowRec95()
            } else {
                Breadcrumbs.log("p93 probe off")
                // (95) 任务 3：fx 会话结束（任一特效开→全关）
                // ——推荐卡呈现额度复位，下一会话可再呈一次。
                recShown = false
                // (96) 96-2/96-3：全关收口——panic 窗藏起、
                // 看门狗停表、孤儿标记清除。
                panicWindow96?.isHidden = true
                stopWd96()
                FxEventLog96.markCleared()
                FxEventLog96.record("off gen=\(fxGeneration96)")
            }
        }
    }

    /// (93) A5：点按归属——card＝落在覆层可见卡片/钮帧内；
    /// host＝在覆层宿主范围内但卡外（宿主全窗铺满、该区
    /// hitTest 恒穿透，归属记 host 以别于无宿主时）；none
    /// ＝宿主不在场/点在宿主外。坐标以窗口系为准（宿主钉
    /// 满主窗，宿主系＝窗口系）。
    private func tapOwn93(at p: CGPoint) -> String {
        guard let host = overlayHost91, host.window != nil else { return "none" }
        for sub in [recCard, blessCard, wishButton] {
            guard let sub = sub, !sub.isHidden, sub.alpha > 0.01 else { continue }
            if sub.frame.contains(p) { return "card" }
        }
        return host.bounds.contains(p) ? "host" : "none"
    }

    /// (94) 94-7：浮层层级账——宿主子视图类名/帧/alpha 同
    /// 行落盘（黄面/吞点按定性靠此行对账实际在场层）。
    private func logFxLayers94() {
        func desc(_ v: UIView) -> String {
            let f = v.frame
            return "\(String(describing: type(of: v)))"
                + "[\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height))"
                + " a=\(String(format: "%.2f", v.alpha)) hid=\(v.isHidden ? 1 : 0)]"
        }
        let hostSubs = (overlayHost91?.subviews ?? []).map(desc).joined(separator: ",")
        let fxSubs = (rootView?.subviews ?? []).map(desc).joined(separator: ",")
        Breadcrumbs.log("p94 fx layers host={\(hostSubs)} fxwin={\(fxSubs)}")
    }

    /// (94) 94-7：点按归属（p94 口径）——card＝落在可见卡/
    /// 钮帧内；ctrl＝主窗 hitTest 命中 UIControl 本体（或其
    /// 子视图）；host＝宿主在场但点在卡外非控件区（hitTest
    /// 恒穿透）；nil＝宿主不在场。
    private func tapOwn94(at p: CGPoint, hit: UIView?) -> String {
        for sub in [recCard, blessCard, wishButton] {
            guard let sub = sub, !sub.isHidden, sub.alpha > 0.01 else { continue }
            if sub.frame.contains(p) { return "card" }
        }
        var node = hit
        while let v = node {
            if v is UIControl { return "ctrl" }
            node = v.superview
        }
        return overlayHost91?.window != nil ? "host" : "nil"
    }

    @objc private func handleTapProbe92(_ gr: UITapGestureRecognizer) {
        guard let view = gr.view else { return }
        let p = gr.location(in: view)
        // (95) 任务 1：识别成功原始落痕——不受下方 p92 节流
        // 计数吞没（识别器每点只回调一次，无连发刷屏面）。
        Breadcrumbs.log("p95 probe raw fired pt=\(Int(p.x.rounded())),\(Int(p.y.rounded()))")
        let now = CACurrentMediaTime()
        if now - tapProbeWindowStart92 >= 1 {
            tapProbeWindowStart92 = now
            tapProbeCount92 = 0
        }
        guard tapProbeCount92 < 2 else { return }
        tapProbeCount92 += 1
        let w = max(1, view.bounds.width), h = max(1, view.bounds.height)
        let zx = p.x < w / 3 ? "l" : (p.x < w * 2 / 3 ? "c" : "r")
        let zy = p.y < h / 3 ? "t" : (p.y < h * 2 / 3 ? "m" : "b")
        Breadcrumbs.log("p92 tap ok zone=\(zx)\(zy)")
        // (93) A5：归属行（节流与 p92 行共用计数，每秒≤2 条）。
        Breadcrumbs.log("p93 tap own=\(tapOwn93(at: p)) zone=\(zx)\(zy)")
        // (94) 94-7：p94 点按自证——归属/命中类名/祝福卡态同行。
        let hit94 = view.hitTest(p, with: nil)
        let hitName94 = hit94.map { String(describing: type(of: $0)) } ?? "nil"
        let bless94 = (blessCard?.isHidden == false) ? 1 : 0
        Breadcrumbs.log("p94 fx tap own=\(tapOwn94(at: p, hit: hit94))"
            + " hit=\(hitName94) bless=\(bless94)")
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    /// (94) 94-7：祝福卡展示期，被动识别器（passiveTap91）
    /// 由 delegate 过滤——触摸命中任何可交互控件时不收，
    /// 不许旁路抢在控件之前 showBless/补放烟花。
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldReceive touch: UITouch) -> Bool {
        // (95) 任务 1：探针识别器原始落痕＋结构兜底看门狗。
        // 只观察不拦截：恒 return true、cancelsTouchesInView
        // 维持 false，穿透语义零改动。
        if gestureRecognizer === tapProbe92 {
            probeRawShould95(touch)
            return true
        }
        if gestureRecognizer === passiveTap91,
           let card = blessCard, !card.isHidden,
           let main = mainWindow {
            if tapHitsInteractive91(at: touch.location(in: main)) { return false }
        }
        return true
    }

    /// (95) 任务 1：shouldReceive 原始落痕——touch-down 到
    /// 达识别器层即落行（同秒合并节流）；arm 后第一笔额外
    /// 落 `p95 probe first` 强在岗证明（不受节流吞没）。
    /// 坐标取窗口系（与 ConsolePanel82 登记的钮帧/dim 帧
    /// 同系，供看门狗命中判定）。
    private func probeRawShould95(_ touch: UITouch) {
        let armed = isFireworks || isLanterns || isSnow || isWind
        let p = touch.location(in: mainWindow)
        if probeFirstPending95 {
            probeFirstPending95 = false
            Breadcrumbs.log("p95 probe first pt=\(Int(p.x.rounded())),\(Int(p.y.rounded()))")
        }
        let sec = Int(CACurrentMediaTime())
        if sec != probeRawLastSec95 {
            probeRawLastSec95 = sec
            Breadcrumbs.log("p95 probe raw should pt=\(Int(p.x.rounded())),\(Int(p.y.rounded()))"
                + " armed=\(armed ? 1 : 0)")
        }
        probeGuardCheck95(at: p, armed: armed)
    }

    /// (95) 任务 1：结构兜底看门狗——fx 开启期点按命中控
    /// 制台登记的特效钮帧或 dim 帧时挂 350ms 看门狗：期内
    /// ConsolePanel82.handlerTrace95（console85 tap／
    /// dismissConsole93 落痕同点递增）有新值＝handler 链
    /// 活着，落 fired=0 不介入；无新值＝handler 链断裂，
    /// probe 直接执行关闭动作（特效钮→经既有 setX 通路
    /// toggle、src=probe95 落 p94 fx sw；dim→发
    /// foliaConsoleDismiss95 请控制台 dismiss）。
    private func probeGuardCheck95(at p: CGPoint, armed: Bool) {
        guard armed, !probeGuardPending95 else { return }
        var hitFx: String?
        for (key, frame) in ConsolePanel82.fxFrames95 where frame.contains(p) {
            hitFx = key
            break
        }
        var hitDim = false
        if hitFx == nil, let dim = ConsolePanel82.dimFrame95, dim.contains(p) {
            hitDim = !(ConsolePanel82.presentedCardFrame?.contains(p) ?? false)
        }
        guard hitFx != nil || hitDim else { return }
        probeGuardPending95 = true
        let trace0 = ConsolePanel82.handlerTrace95
        let gen0 = fxGeneration96
        let hit = hitFx != nil ? "fx" : "dim"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.probeGuardPending95 = false
            if ConsolePanel82.handlerTrace95 != trace0 {
                Breadcrumbs.log("p95 probe guard hit=\(hit) fired=0")
                return
            }
            guard gen0 == self.fxGeneration96 else {
                Breadcrumbs.log("p96 probe guard hit=\(hit) fired=skip-gen")
                return
            }
            if hitFx != nil {
                // (96) 96-2：兜底只做幂等 forceStop，禁用旧
                // toggle（超时与 handler 晚到并发会双翻转回开）。
                self.forceStopAllFx96(src: "probe96")
            } else {
                NotificationCenter.default.post(
                    name: .foliaConsoleDismiss95, object: nil)
            }
            Breadcrumbs.log("p95 probe guard hit=\(hit) fired=1")
        }
    }

    @objc private func handlePassiveTap(_ gr: UITapGestureRecognizer) {
        guard let rv = rootView else { return }
        let p = gr.location(in: rv)
        // (94) 94-7：祝福卡展示期卡外点——关卡（点按本身经
        // 宿主白名单 hitTest 已穿透回主窗，本路只收卡）。
        if let card = blessCard, !card.isHidden,
           !card.frame.contains(p), !tapHitsInteractive91(at: p) {
            hideBless()
            Breadcrumbs.log("p94 fx bless outclose")
        }
        // port91（任务 1）：孔明灯点按看祝福走主窗旁路——点中
        // 灯体、且该点未命中任何可交互控件/自有浮层卡时才
        // showBless 并落 p91 lamp hit 自证；灯命中区不补放
        // 烟花（旧口径保留）。
        if let lantern = lantern(at: p) {
            if !tapHitsInteractive91(at: p) {
                Breadcrumbs.log("p91 lamp hit")
                showBless(lantern.bless)
            }
            return
        }
        guard isFireworks else { return }
        launch(x: Double(p.x), ty: max(60, Double(p.y) - 40), opts: FW_MAIN)
        ensureLoop()
    }

    /// port91（任务 1）：点是否命中主窗内的可交互目标——沿
    /// 命中视图祖先链查 UIControl／集合格／表格式／Fx 自有
    /// 三张浮层卡，任一命中即视为「点在控件上」，旁路不抢。
    private func tapHitsInteractive91(at p: CGPoint) -> Bool {
        guard let main = mainWindow,
              let hit = main.hitTest(p, with: nil) else { return false }
        var node: UIView? = hit
        while let v = node {
            if v is UIControl || v is UICollectionViewCell
                || v is UITableViewCell { return true }
            if v === blessCard || v === wishButton || v === recCard { return true }
            node = v.superview
        }
        return false
    }

    /// (96) 96-2：幂等强制全关——panic 钮/看门狗/超时重发的
    /// 唯一出口。各 stop 内部 setX 有 guard，重复调无副作
    /// 用；代次＋1 使旧 start 回调/旧看门狗超时过期失效。
    /// 只在主线程调用。随后发通知请控制台 dismiss。
    public func forceStopAllFx96(src: String) {
        fxGeneration96 += 1
        let gen = fxGeneration96
        closeReq96 = (gen: gen, at: CACurrentMediaTime())
        stopFw(src: src)
        stopLantern(hard: true, src: src)
        stopSnow(hard: true, src: src)
        stopWind(src: src)
        hideBless()
        hideRecCard()
        let still = isFireworks || isLanterns || isSnow || isWind
        Breadcrumbs.logSync("p96 forceStop gen=\(gen) src=\(src) still=\(still ? 1 : 0)")
        FxEventLog96.record("forceStop gen=\(gen) src=\(src) still=\(still ? 1 : 0)")
        FxEventLog96.markCleared()
        NotificationCenter.default.post(name: .foliaConsoleDismiss95, object: nil)
    }

    /// (96) 96-3：独立看门狗——专用队列每 1s 检查主线程
    /// heartbeat。heartbeat 停 2s 以上＝主线程卡死：只落
    /// 盘，不尝试跨线程动 UIKit（无合法姿势）。heartbeat
    /// 正常则在主线程跑一次关闭通路审计；有待确认的关闭
    /// 请求超时未确认时，重发一次幂等 forceStop。
    private func startWd96() {
        guard wdTimer96 == nil else { return }
        wdLastBeatAt96 = CACurrentMediaTime()
        let t = DispatchSource.makeTimerSource(queue: wdQueue96)
        t.schedule(deadline: .now() + 1, repeating: 1.0)
        t.setEventHandler { [weak self] in self?.wdTick96() }
        t.resume()
        wdTimer96 = t
    }

    private func stopWd96() {
        wdTimer96?.cancel()
        wdTimer96 = nil
        closeReq96 = nil
    }

    private func wdTick96() {
        beatLock96.lock()
        let beat = mainBeat96
        beatLock96.unlock()
        let now = CACurrentMediaTime()
        if beat == wdLastBeat96 {
            if now - wdLastBeatAt96 >= 2 {
                FxEventLog96.record("wd main-stalled beat=\(beat)")
                Breadcrumbs.log("p96 wd main-stalled beat=\(beat)")
                wdLastBeatAt96 = now
            }
            return
        }
        wdLastBeat96 = beat
        wdLastBeatAt96 = now
        DispatchQueue.main.async { [weak self] in self?.wdCloseAudit96() }
    }

    /// (96) 96-1：arm 边沿 hitTest 快照——取控制台登记的
    /// 特效钮中心：特效窗必须返回 nil（透传），主窗必须返
    /// 回 UIControl。只在主线程跑（非主线程时派发）。
    private func fxArmHitAudit96() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.fxArmHitAudit96() }
            return
        }
        guard let first = ConsolePanel82.fxFrames95.values.first else { return }
        let center = CGPoint(x: first.midX, y: first.midY)
        let fxHit = window?.hitTest(center, with: nil)
        let fxName = fxHit.map { String(describing: type(of: $0)) } ?? "nil"
        let mainHit = mainWindow?.hitTest(center, with: nil)
        let mainName = mainHit.map { String(describing: type(of: $0)) } ?? "nil"
        Breadcrumbs.log("p96 fx audit fxWinHit=\(fxName) mainHit=\(mainName)")
        FxEventLog96.record("arm audit fxWinHit=\(fxName) mainHit=\(mainName)")
    }

    /// (96) 96-3：主线程关闭通路审计——控制台钮中心与 dim
    /// 中心分别问特效窗与主窗 hitTest：特效窗必须返回 nil，
    /// 主窗必须返回 UIControl。异常只落一行（首见/变化时）。
    private func wdCloseAudit96() {
        guard isFireworks || isLanterns || isSnow || isWind else { return }
        var points: [CGPoint] = ConsolePanel82.fxFrames95.values.map {
            CGPoint(x: $0.midX, y: $0.midY)
        }
        if let dim = ConsolePanel82.dimFrame95 {
            points.append(CGPoint(x: dim.midX, y: dim.midY))
        }
        guard let first = points.first else { return }
        let fxHit = window?.hitTest(first, with: nil)
        let fxName = fxHit.map { String(describing: type(of: $0)) } ?? "nil"
        let mainHit = mainWindow?.hitTest(first, with: nil)
        let mainName = mainHit.map { String(describing: type(of: $0)) } ?? "nil"
        let fxOK = fxHit == nil
        let mainOK = mainHit is UIControl
        if !fxOK || !mainOK {
            Breadcrumbs.log("p96 wd audit fxWinHit=\(fxName) mainHit=\(mainName)")
            FxEventLog96.record("wd audit fxWinHit=\(fxName) mainHit=\(mainName)")
        }
        // 待确认的关闭请求：超时 0.5s 仍有特效在，重发一次。
        if let req = closeReq96, req.gen != closeReqReissued96,
           nowMsNow() / 1000 - req.at >= 0.5,
           isFireworks || isLanterns || isSnow || isWind {
            closeReqReissued96 = req.gen
            forceStopAllFx96(src: "wd96")
        }
    }

    // MARK: 公开开关（返回新状态）

    @discardableResult
    public func toggleFireworks() -> Bool {
        if isFireworks { stopFw(src: "consolebtn") } else { startFw(src: "consolebtn") }
        return isFireworks
    }

    @discardableResult
    public func toggleLanterns() -> Bool {
        // port90: 用户点关须当帧清场。旧 soft-stop 淡出 2–4 秒，按钮已灭、
        // 画面还在，用户确认性再点把状态翻回开，表象「关不掉」。
        if isLanterns { stopLantern(hard: true, src: "consolebtn"); Breadcrumbs.log("port90 fx ln off hard") } else { startLantern(src: "consolebtn") }
        return isLanterns
    }

    @discardableResult
    public func toggleSnow() -> Bool {
        // port90: 同 toggleLanterns，点关硬清（自融只留给 12 秒自动停）。
        if isSnow { stopSnow(hard: true, src: "consolebtn"); Breadcrumbs.log("port90 fx sn off hard") } else { startSnow(src: "consolebtn") }
        return isSnow
    }

    @discardableResult
    public func toggleWind() -> Bool {
        if isWind { stopWind(src: "consolebtn") } else { startWind(src: "consolebtn") }
        return isWind
    }

    /// (92) 任务 2：冷启默认关（推翻 (88) 默认开，审计 Q2
    /// 定案：工坊「下雪 开」存值被误落成冷启无条件开雪）。
    /// 方法名保留供 SceneDelegate 冷启调用点不动，职责改为
    /// 「确保冷启无雪」＋落 p92 自证；四特效冷启默认全关，
    /// 雪样式值（淡蓝）保留、手动开仍走 startSnow、12 秒
    /// 自融保留。
    public func applyDefaultSnow88() {
        if isSnow { stopSnow(hard: true, src: "auto") }
        Breadcrumbs.log("p92 snow=default-off")
    }

    // MARK: 状态切换（互斥规则照样片 start/stop 函数）

    /// (93) C4：特效开启次序（最近开启者在尾），推荐卡入
    /// 场动画按最近开启的活跃特效选形态时读。
    private var fxOnOrder93: [String] = []

    private func noteFxOrder93(_ fx: String, _ on: Bool) {
        fxOnOrder93.removeAll { $0 == fx }
        if on { fxOnOrder93.append(fx) }
    }

    /// (93) A4：四特效各自启/停落内存对账行——MB 走仓内既
    /// 有 footprint 口径（StyleOpenTrace.physFootprintMB，
    /// 与 Breadcrumbs 尾巴 footprintMB 同源同值，双写互证）。
    private func memLog93(_ fx: String, _ on: Bool) {
        Breadcrumbs.log("p93 mem fx=\(fx) on=\(on ? 1 : 0)"
            + " mb=\(StyleOpenTrace.physFootprintMB())")
    }

    private func setFw(_ on: Bool, src: String = "auto") {
        // (96) 96-4：setX 入口落痕在 guard 前——区分「没进
        // setX」与「进了但 guard 跳过」；guard 跳过另落原因。
        Breadcrumbs.log("p96 setx enter fx=fw on=\(on ? 1 : 0) src=\(src) stateBefore=\(isFireworks ? 1 : 0)")
        guard isFireworks != on else {
            Breadcrumbs.log("p96 setx guard-skip fx=fw on=\(on ? 1 : 0) src=\(src) state=\(isFireworks ? 1 : 0)")
            return
        }
        isFireworks = on
        Breadcrumbs.log(on ? "fx87 fw=1" : "fx87 fw=0")
        Breadcrumbs.log("p94 fx sw fx=fw on=\(on ? 1 : 0) src=\(src) state=\(isFireworks ? 1 : 0)")
        noteFxOrder93("fw", on)
        memLog93("fw", on)
        onStateChanged?()
        refreshTapProbe92()
        // (95) 任务 2：1→0 收尾自证——stopFw 的清场（粒子
        // 数组清空）在本函数调用前已执行完，此行落＝清场完。
        if !on { Breadcrumbs.log("p95 fx clear fx=fw src=\(src)") }
    }
    private func setLantern(_ on: Bool, src: String = "auto") {
        Breadcrumbs.log("p96 setx enter fx=ln on=\(on ? 1 : 0) src=\(src) stateBefore=\(isLanterns ? 1 : 0)")
        guard isLanterns != on else {
            Breadcrumbs.log("p96 setx guard-skip fx=ln on=\(on ? 1 : 0) src=\(src) state=\(isLanterns ? 1 : 0)")
            return
        }
        isLanterns = on
        Breadcrumbs.log(on ? "fx87 ln=1" : "fx87 ln=0")
        Breadcrumbs.log("p94 fx sw fx=ln on=\(on ? 1 : 0) src=\(src) state=\(isLanterns ? 1 : 0)")
        noteFxOrder93("ln", on)
        memLog93("ln", on)
        onStateChanged?()
        refreshTapProbe92()
        refreshWishButton()
        // (95) 任务 2：1→0 收尾自证（硬清时灯数组已在本函
        // 数调用前清空；软停为渐隐语义、状态收尾在此落行）。
        if !on { Breadcrumbs.log("p95 fx clear fx=ln src=\(src)") }
    }
    private func setSnow(_ on: Bool, src: String = "auto") {
        Breadcrumbs.log("p96 setx enter fx=sn on=\(on ? 1 : 0) src=\(src) stateBefore=\(isSnow ? 1 : 0)")
        guard isSnow != on else {
            Breadcrumbs.log("p96 setx guard-skip fx=sn on=\(on ? 1 : 0) src=\(src) state=\(isSnow ? 1 : 0)")
            return
        }
        isSnow = on
        Breadcrumbs.log(on ? "fx87 sn=1" : "fx87 sn=0")
        Breadcrumbs.log("p94 fx sw fx=sn on=\(on ? 1 : 0) src=\(src) state=\(isSnow ? 1 : 0)")
        noteFxOrder93("sn", on)
        memLog93("sn", on)
        onStateChanged?()
        refreshTapProbe92()
        // (95) 任务 2：1→0 收尾自证（硬清时雪片数组已在本
        // 函数调用前清空；自融软停状态收尾在此落行）。
        if !on { Breadcrumbs.log("p95 fx clear fx=sn src=\(src)") }
    }
    private func setWind(_ on: Bool, src: String = "auto") {
        Breadcrumbs.log("p96 setx enter fx=wd on=\(on ? 1 : 0) src=\(src) stateBefore=\(isWind ? 1 : 0)")
        guard isWind != on else {
            Breadcrumbs.log("p96 setx guard-skip fx=wd on=\(on ? 1 : 0) src=\(src) state=\(isWind ? 1 : 0)")
            return
        }
        isWind = on
        Breadcrumbs.log(on ? "fx87 wd=1" : "fx87 wd=0")
        Breadcrumbs.log("p94 fx sw fx=wd on=\(on ? 1 : 0) src=\(src) state=\(isWind ? 1 : 0)")
        noteFxOrder93("wd", on)
        memLog93("wd", on)
        onStateChanged?()
        refreshTapProbe92()
        // (95) 任务 2：1→0 收尾自证——stopWind 的清场
        // （streaks/leaves 清空）在本函数调用前已执行完。
        if !on { Breadcrumbs.log("p95 fx clear fx=wd src=\(src)") }
    }

    /// 首帧 render 前 W/H 可能未刷新：生成粒子前先按根视图 bounds 兜底。
    private func refreshSizeFromRootView() {
        if let rv = rootView, rv.bounds.width > 0, rv.bounds.height > 0 {
            W = Double(rv.bounds.width)
            H = Double(rv.bounds.height)
        }
    }

    private func startFw(src: String = "auto") {
        refreshSizeFromRootView()
        stopLantern(hard: true, src: "mutex"); stopSnow(hard: true, src: "mutex"); stopWind(src: "mutex")
        recShown = false; fwStep = 0; rains = []
        fwStart = nowMsNow()
        // (93) E：dt 采样窗自本场烟花起算。
        fwDtSum93 = 0; fwDtN93 = 0; fwDtLogAt93 = fwStart
        hideRecCard()
        setFw(true, src: src)
        ensureLoop()
    }

    private func stopFw(src: String = "auto") {
        rockets = []; sparks = []; crackles = []; halos = []; rains = []; splitQueue = []
        setFw(false, src: src)
        settleAfterStop90()
    }

    private func startLantern(src: String = "auto") {
        refreshSizeFromRootView()
        stopFw(src: "mutex"); stopSnow(hard: true, src: "mutex")
        lnStopping = false
        lnLastSpawn = 0
        for _ in 0..<FxTuning88.lnInitial { spawnLantern(init: true) }
        setLantern(true, src: src)
        ensureLoop()
    }

    private func stopLantern(hard: Bool, src: String = "auto") {
        if hard { lanterns = []; lnStopping = false } else { lnStopping = true }
        setLantern(false, src: src)
        if hard || lanterns.isEmpty { hideBless() }
        if hard { settleAfterStop90() }
    }

    private func startSnow(src: String = "auto") {
        refreshSizeFromRootView()
        stopFw(src: "mutex"); stopLantern(hard: true, src: "mutex")
        snMelt = 1; snStart = nowMsNow()
        let target = max(90, min(175, Int((W * H / 8500).rounded())))
        for _ in 0..<target { spawnFlake(init: true) }
        setSnow(true, src: src)
        ensureLoop()
    }

    private func stopSnow(hard: Bool, src: String = "auto") {
        if hard { flakes = []; snMelt = 1 }
        setSnow(false, src: src)
        if hard { settleAfterStop90() }
    }

    private func startWind(src: String = "auto") {
        wdStart = nowMsNow()
        setWind(true, src: src)
        ensureLoop()
    }

    /// (93) A2／(94) 94-9：风的关闭来源入参化——consolebtn
    /// ＝控制台钮手动关（toggleWind）；mutex＝开烟花时的
    /// 互斥清场（既有行为不动）；其余任何来源（未来新增
    /// 的自动关）一律以非 consolebtn 落 p93 fxauto 自证，
    /// 且全部来源统一经 setWind 落 p94 fx sw 同行自证，不
    /// 许再出现无来源的静默自关（(92) 日志实锤：旧 5 秒
    /// 自关无点按无落痕）。风无定时自关路径（(93) 已删）。
    private func stopWind(src: String = "auto") {
        // (94) 94-9：p94 fx sw 同行口径由 setWind 落（src 与
        // 变更后引擎态同行）；p93 fxauto 保留作非手动来源旁证。
        if isWind && src != "consolebtn" {
            Breadcrumbs.log("p93 fxauto fx=wd src=\(src)")
        }
        windPow = 0
        // port90: 旧实现只归零风力，streaks/leaves 残留继续渲染、anyFx 恒真、窗不隐。
        streaks = []; leaves = []
        setWind(false, src: src)
        settleAfterStop90()
    }

    /// port90: 硬停后收口——重绘清末帧；无任何特效存活时停链并隐藏 Fx 窗，
    /// 杜绝关后隐形窗继续吞触摸。start* 互斥路径调用后随即 ensureLoop 重新亮窗，次序安全。
    private func settleAfterStop90() {
        rootView?.setNeedsDisplay()
        stopLoopIfIdle()
    }

    private func nowMsNow() -> Double { CACurrentMediaTime() * 1000 }

    // MARK: 显示循环

    private func anyFx() -> Bool {
        isFireworks || isLanterns || isSnow || isWind
            || !sparks.isEmpty || !rockets.isEmpty || !lanterns.isEmpty
            || !flakes.isEmpty || !streaks.isEmpty || !leaves.isEmpty
            || !halos.isEmpty || !rains.isEmpty || !crackles.isEmpty
    }

    private func ensureLoop() {
        guard let rv = rootView else { return }
        window?.isHidden = false
        if displayLink == nil {
            lastTick = 0
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            // (92) 任务 8：帧率上限 60——旧实现在 120Hz 机型
            // 上以 120fps 全屏软件光栅，是烟花卡的主因之一；
            // 帧步进本就按 dt*60 归一，60 上限不改动画时序。
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        rv.setNeedsDisplay()
    }

    private func stopLoopIfIdle() {
        guard !anyFx() else { return }
        let wasRunning = displayLink != nil
        displayLink?.invalidate()
        displayLink = nil
        if wasRunning { rootView?.setNeedsDisplay() }   // 最后一帧清屏
        window?.isHidden = true
        refreshWishButton()
    }

    @objc private func tick(_ link: CADisplayLink) {
        // (96) 96-3：主线程 heartbeat——看门狗凭此判断主线程
        // 是否还在转（卡死则 heartbeat 停）。
        beatLock96.lock()
        mainBeat96 += 1
        beatLock96.unlock()
        if lastTick == 0 { lastTick = link.timestamp }
        rootView?.setNeedsDisplay()
    }

    /// (93) E：最近一帧真实 dt（ms），frameFactor 顺手记
    /// 录，供烟花 dt 面包屑取平均（不另开计时）。
    private var lastDtMs93: Double = 0
    /// (93) E：烟花 dt 采样累加器（约 2 秒落一条）。
    private var fwDtSum93: Double = 0
    private var fwDtN93 = 0
    private var fwDtLogAt93: Double = 0

    /// 按 dt*60 归一的帧系数（120Hz 下约 0.5、60Hz 下约 1）。
    private func frameFactor() -> Double {
        let now = CACurrentMediaTime()
        defer { lastTick = now }
        if lastTick == 0 { return 1 }
        let dt = now - lastTick
        if dt <= 0 { return 1 }
        lastDtMs93 = dt * 1000
        return min(3, max(0.1, dt * 60))
    }

    /// 概率按帧系数缩放：p' = 1-(1-p)^f。
    private func chance(_ p: Double, _ f: Double) -> Bool {
        Double.random(in: 0..<1) < 1 - pow(1 - p, f)
    }

    // MARK: 渲染主入口（Fx87RootView.draw 调用）

    func render(in ctx: CGContext, size: CGSize) {
        W = Double(size.width); H = Double(size.height)
        guard W > 0, H > 0 else { return }
        nowMs = nowMsNow()
        let f = frameFactor()
        ctx.setBlendMode(.normal)
        ctx.clear(CGRect(x: 0, y: 0, width: W, height: H))

        // 阵风呼吸（照样片 frame 开头）
        var gust: Double = 0
        if isWind {
            gust = 0.62 + 0.38 * (0.6 * sin(nowMs * 0.0011) + 0.4 * sin(nowMs * 0.0027 + 1.7))
        }
        gust = max(0.12, gust)
        windPow += ((isWind ? gust : 0) - windPow) * (1 - pow(0.96, f))

        stepFireworks(ctx, f: f)
        stepLanterns(ctx, f: f)
        stepSnow(ctx, f: f)
        stepWind(ctx, f: f)

        stopLoopIfIdle()
    }

    // MARK: - 烟花

    /// 定时上升：58 帧走完距离（g=0.09，初速由距离反推），照样片 launch。
    private func launch(x: Double, ty: Double, opts: FwPreset) {
        let T: Double = 58, g: Double = 0.09
        let D = (H + 6) - ty
        rockets.append(FxRocket(x: x, y: H + 6, vx: fxRand(-0.2, 0.2),
                                vy: -((D + 0.5 * g * T * T) / T), ty: ty, opts: opts))
        rockets.last?.g = g
    }

    private func pushSpark(_ s: FxSpark) {
        guard sparks.count < 1400 else { return }   // 上限纪律：超限丢新
        sparks.append(s)
    }

    private func burstStar(x: Double, y: Double, o: FwPreset) {
        var K = min(W, H) / 380
        K = max(0.7, min(1.6, K))
        // (88) 工坊倍率落值：大小×0.85 入 sp、密度×1.1 入星数、
        // 辉光×1.7 入 amp、颜色金覆盖轮换调色板（FxTuning88）。
        let sp0 = o.sp * K * FxTuning88.fwSizeMul
        let nEff = Int((Double(o.n) * FxTuning88.fwDensityMul).rounded())
        let outerPals = FxTuning88.fwGoldDefault ? FX_GOLD : o.pals
        let innerPals = FxTuning88.fwGoldDefault ? FX_GOLD : (o.shellPals ?? o.pals)
        let haloCol = FxTuning88.fwGoldDefault ? (255.0, 186.0, 92.0) : o.halo
        if halos.count < 12 {
            halos.append(FxHalo(x: x, y: y, vr: 1.1 + sp0 * 0.26, col: haloCol,
                                amp: o.amp * FxTuning88.fwGlowMul))
        }
        if o.flash { flashWall() }
        // port91（任务 2）：爆点外送联动协调器（附近封面按花
        // 色提亮一拍＋宠物跳跃）；晕色与本发光晕同源。
        onFwBurst91?(CGPoint(x: x, y: y),
                     UIColor(red: CGFloat(haloCol.0 / 255),
                             green: CGFloat(haloCol.1 / 255),
                             blue: CGFloat(haloCol.2 / 255), alpha: 1))

        func shell(_ n: Int, _ spBase: Double, _ pals: [FxHSL], _ inner: Bool) {
            for i in 0..<n {
                let ang = Double(i) / Double(n) * Double.pi * 2
                    + (o.crisp ? fxRand(-0.025, 0.025) : fxRand(-0.12, 0.12))
                let sp = spBase * (1 + fxRand(-0.5, 0.5) * (o.crisp ? 0.05 : 0.22))
                    * (0.92 + 0.16 * abs(sin(Double(i) * 1.71)))
                let s = FxSpark(x: x, y: y, vx: cos(ang) * sp, vy: sin(ang) * sp,
                                decay: o.decay + fxRand(0, 0.0016),
                                pal: pals[i % pals.count],
                                size: o.size * FxTuning88.fwSizeMul + fxRand(0, 0.45),
                                willow: true, tw: fxRand(0, 6.3),
                                cr: !o.crisp && !inner && i % 3 == 0,
                                noStrobe: i % 3 != 0)
                s.drag = o.drag
                s.histN = inner ? 10 : 16
                s.split = !inner && !o.crisp && i % 8 == 3
                pushSpark(s)
            }
        }
        shell(nEff, sp0, outerPals, false)
        if let shellK = o.shell {
            shell(Int((Double(nEff) * 0.45).rounded()), sp0 * shellK, innerPals, true)
        }
        // 花心：白金 HSL(45,100,86)，速散
        let heart = max(7, Int((Double(nEff) / 9).rounded()))
        for _ in 0..<heart {
            let ca = fxRand(0, Double.pi * 2), cs = fxRand(0, 0.5)
            let s = FxSpark(x: x, y: y, vx: cos(ca) * cs, vy: sin(ca) * cs - 0.1,
                            decay: 0.007, pal: FxHSL(h: 45, s: 100, l: 86),
                            size: 1.05, willow: false, tw: fxRand(0, 6.3),
                            cr: false, noStrobe: true)
            pushSpark(s)
        }
        for _ in 0..<Int((Double(o.rain) * FxTuning88.fwDensityMul).rounded()) {
            spawnRain(x: x + fxRand(-0.5, 0.5) * sp0 * 13, y: y + fxRand(-4, 4))
        }
    }

    private func spawnRain(x: Double, y: Double, riser: Bool = false) {
        guard rains.count < 220 else { return }
        rains.append(FxRain(x: x, y: y, vx: fxRand(-0.125, 0.125),
                            vy: riser ? -(1.5 + fxRand(0, 1.3)) : (0.3 + fxRand(0, 0.8)),
                            decay: 0.0026 + fxRand(0, 0.002),
                            pal: FX_RAIN_PALS[Int.random(in: 0..<FX_RAIN_PALS.count)],
                            size: 0.6 + fxRand(0, 0.5)))
    }

    private func flashWall() {
        guard let fv = flashView else { return }
        fv.layer.removeAllAnimations()
        fv.alpha = 0.12
        UIView.animate(withDuration: 0.17, delay: 0, options: [.curveEaseOut]) {
            fv.alpha = 0
        }
    }

    private func stepFireworks(_ ctx: CGContext, f: Double) {
        // (93) E：烟花活跃期 dt 自证——约每 2 秒落一条平均
        // dt（ms）＋当前粒子总量（星粒＋火箭＋金雨），供下
        // 包判烟花卡是否收敛（(92) 日志因烟花未开无从判）。
        if isFireworks && lastDtMs93 > 0 {
            fwDtSum93 += lastDtMs93
            fwDtN93 += 1
            if nowMs - fwDtLogAt93 >= 2000 && fwDtN93 > 0 {
                Breadcrumbs.log("p93 fw dt=\(Int((fwDtSum93 / Double(fwDtN93)).rounded()))"
                    + " n=\(sparks.count + rockets.count + rains.count)")
                fwDtSum93 = 0; fwDtN93 = 0; fwDtLogAt93 = nowMs
            }
        }
        // 时间轴（ms，照样片；launch 在爆点前约 1s 由火箭上升耗时形成）
        if isFireworks {
            let t = nowMs - fwStart
            if fwStep == 0 && t > 900 {
                fwStep = 1; launch(x: W * 0.50, ty: H * 0.30, opts: FW_MAIN)
            } else if fwStep == 1 && t > 2000 {
                fwStep = 2
                launch(x: W * 0.22, ty: H * 0.26, opts: FW_MED.variant(pals: FX_CRIM, halo: (255, 110, 150)))
                launch(x: W * 0.78, ty: H * 0.22, opts: FW_MED.variant(pals: FX_AZUR, halo: (120, 180, 255)))
            } else if fwStep == 2 && t > 3200 {
                fwStep = 3; launch(x: W * 0.50, ty: H * 0.26, opts: FW_GIANT)
            } else if fwStep == 3 && t > 4600 {
                fwStep = 4
                launch(x: W * 0.30, ty: H * 0.36, opts: FW_MED.variant(pals: FX_VIOL, halo: (190, 140, 255)))
                launch(x: W * 0.70, ty: H * 0.30, opts: FW_MED.variant(pals: FX_ORNG, halo: (255, 150, 80)))
            } else if fwStep == 4 && t > 5800 {
                fwStep = 5
                launch(x: W * 0.50, ty: H * 0.30,
                       opts: FW_MAIN.variant(pals: FX_CRIM, halo: (255, 110, 150), shellPals: FX_GOLD))
            } else if fwStep == 5 && t > 7200 {
                fwStep = 6
                launch(x: W * 0.18, ty: H * 0.30, opts: FW_MED)
                launch(x: W * 0.82, ty: H * 0.28, opts: FW_MED.variant(pals: FX_AZUR, halo: (120, 180, 255)))
            } else if fwStep == 6 && t > 7700 {
                fwStep = 7; launch(x: W * 0.50, ty: H * 0.27, opts: FW_GIANT)
            } else if fwStep == 7 && t > 9600 {
                fwStep = 8; launch(x: W * 0.50, ty: H * 0.30, opts: FW_CRISP)
            }
            // 金雨贯穿全场
            let rainRate: Double = t < 3000 ? 0.5 : t < 10500 ? 0.3 : t < 13000 ? 0.45 : 0
            if rainRate > 0 && chance(rainRate, f) {
                spawnRain(x: fxRand(0, W), y: -12)
            }
            if t < 3000 && chance(0.10, f) {
                spawnRain(x: fxRand(0, W), y: H * (0.7 + fxRand(0, 0.2)), riser: true)
            }
            // (95) 任务 3：推荐卡触发已摘除本时间轴——改由任
            // 一特效开启边沿统一调用（refreshTapProbe92 的
            // arm 点 → maybeShowRec95），此处不再呈现。
            if t > 15500 { setFw(false, src: "auto") }
        }

        // 光晕（source-over，爆点彩色晕，alpha 上限 0.22×amp 量级照样片式）
        halos = halos.filter { hl in
            hl.r += hl.vr * f
            hl.vr *= pow(0.96, f)
            hl.life -= 0.03 * f
            if hl.life <= 0 { return false }
            let a = min(0.22, 0.10 * hl.life * hl.amp)
            fxFillRadial(ctx, center: CGPoint(x: hl.x, y: hl.y), r0: CGFloat(hl.r * 0.2),
                         r1: CGFloat(hl.r),
                         stops: [(0, fxRGB(hl.col.0, hl.col.1, hl.col.2, 0)),
                                 (0.75, fxRGB(hl.col.0, hl.col.1, hl.col.2, a)),
                                 (1, fxRGB(hl.col.0, hl.col.1, hl.col.2, 0))],
                         rect: CGRect(x: hl.x - hl.r, y: hl.y - hl.r,
                                      width: hl.r * 2, height: hl.r * 2))
            return true
        }

        // 以下烟花光全部 additive
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)

        rockets = rockets.filter { r in
            let px = r.x, py = r.y
            r.x += r.vx + windPow * 0.7 * f
            r.y += r.vy * f
            r.vy += r.g * f
            // 上升掉火星：每帧 2 颗 trail spark
            let trailN = max(1, Int((2 * f).rounded()))
            for _ in 0..<trailN {
                let s = FxSpark(x: r.x + fxRand(-1, 1), y: r.y + 4,
                                vx: fxRand(-0.3, 0.3) - r.vx * 0.2, vy: fxRand(0, 0.9) + 0.3,
                                decay: 0.045, pal: FxHSL(h: 42, s: 100, l: 70),
                                size: 0.85, willow: false, tw: 0, cr: false, noStrobe: true)
                s.life = 0.5 + fxRand(0, 0.3)
                s.trail = true
                pushSpark(s)
            }
            _ = px; _ = py
            // (92) 任务 8：辉光改预渲染精灵绘制——旧实现逐火
            // 箭逐帧 setShadow(blur:16) 触发离屏渲染，同为烟
            // 花卡主因；核心亮点保留原填充。
            if let glow = fxRocketGlow92 {
                ctx.draw(glow, in: CGRect(x: r.x - 14, y: r.y - 14,
                                          width: 28, height: 28))
            }
            ctx.setFillColor(fxRGB(255, 246, 214, 0.98))
            ctx.fillEllipse(in: CGRect(x: r.x - 2.2, y: r.y - 2.2, width: 4.4, height: 4.4))
            if r.y <= r.ty || r.vy >= -0.4 {
                burstStar(x: r.x, y: r.y, o: r.opts)
                return false
            }
            return true
        }

        sparks = sparks.filter { p in
            p.px = p.x; p.py = p.y
            p.x += (p.vx + windPow * 0.9) * f
            p.y += p.vy * f
            let dragBase = p.drag ?? (p.willow ? 0.988 : 0.982)
            let dragF = pow(dragBase, f)
            p.vx *= dragF
            p.vy = p.vy * dragF + (p.willow ? 0.052 : 0.033) * f
            p.life -= p.decay * f
            p.tw += 0.3 * f
            if p.life <= 0 { return false }
            // (93) E：星粒 hist 轨迹数组退役（精灵残影替代，
            // 见下方绘制段）——逐帧 append/裁剪一并省掉。
            if p.cr && p.life < 0.5 && chance(0.18, f) {
                if crackles.count < 120 { crackles.append(FxCrackle(x: p.x, y: p.y)) }
                p.cr = false
            }
            if p.split && p.life < 0.62 {
                p.split = false
                for _ in 0..<3 {
                    let sa = fxRand(0, 6.283), ss = 0.7 + fxRand(0, 0.7)
                    let s = FxSpark(x: p.x, y: p.y,
                                    vx: p.vx * 0.25 + cos(sa) * ss, vy: p.vy * 0.25 + sin(sa) * ss,
                                    decay: 0.011, pal: p.pal, size: 0.55,
                                    willow: false, tw: fxRand(0, 6.3), cr: false, noStrobe: true)
                    s.life = 0.85
                    s.drag = 0.97
                    s.histN = 9
                    splitQueue.append(s)
                }
            }
            // 频闪：seed%3<1 的星按 sin 闪烁
            var strobe: Double = 1
            if !p.noStrobe && p.seed.truncatingRemainder(dividingBy: 3) < 1 {
                strobe = sin(p.tw * 2.4 + p.seed) > 0.25 ? 1 : 0.12
            }
            let tw = p.trail ? 1 : (0.72 + 0.28 * sin(p.tw + p.seed)) * strobe
            let a = max(0, p.life * tw)
            // (93) E 结构修：星粒改预渲染精灵贴图（fxSpark-
            // Sprite93 按花色烘焙，本段已在 plusLighter 下）
            // ——旧 hist 逐段 stroke 长曝光光轨＋px→x 双
            // stroke 拖尾＋逐帧椭圆路径全数退役。残影由前
            // 一帧位置一张小精灵（alpha×0.35）承担，视觉
            // 拖尾保留、逐粒路径构建归零。粒径口径：精灵
            // 边长＝size×6.5（涵盖旧辉光 stroke 宽 size×
            // 3.6 的光晕范围），下限 7pt 防小粒消失。
            if let img = fxSparkSprite93(p.pal) {
                let side = CGFloat(max(7, p.size * 6.5))
                let moved = hypot(p.x - p.px, p.y - p.py)
                if moved > 1 {
                    let s2 = side * 0.62
                    ctx.setAlpha(CGFloat(min(1, a * 0.35)))
                    ctx.draw(img, in: CGRect(x: p.px - s2 / 2, y: p.py - s2 / 2,
                                             width: s2, height: s2))
                }
                ctx.setAlpha(CGFloat(min(1, a)))
                ctx.draw(img, in: CGRect(x: p.x - side / 2, y: p.y - side / 2,
                                         width: side, height: side))
                ctx.setAlpha(1)
            }
            return true
        }
        if !splitQueue.isEmpty {
            for s in splitQueue { pushSpark(s) }
            splitQueue = []
        }

        // 金雨：细丝 hist 64 点、终速 3.3、拖尾可达屏高 1/3
        rains = rains.filter { rn in
            rn.vy = min(3.3, rn.vy + 0.03 * f)
            rn.x += (rn.vx + windPow * 0.8) * f
            rn.y += rn.vy * f
            rn.life -= rn.decay * f
            if rn.life <= 0 || rn.y > H + 30 { return false }
            rn.hist.append(CGPoint(x: rn.x, y: rn.y))
            if rn.hist.count > 64 { rn.hist.removeFirst(rn.hist.count - 64) }
            if rn.hist.count > 4 {
                ctx.setLineCap(.round)
                var ri = 2
                while ri < rn.hist.count {
                    let rf = Double(ri) / Double(rn.hist.count)
                    ctx.beginPath()
                    ctx.move(to: rn.hist[ri - 2])
                    ctx.addLine(to: rn.hist[ri])
                    ctx.setStrokeColor(fxCGColor(rn.pal, alpha: rn.life * rf * rf * 0.55))
                    ctx.setLineWidth(CGFloat(0.35 + rn.size * rf))
                    ctx.strokePath()
                    ri += 2
                }
                var headPal = rn.pal
                headPal.s = max(40, headPal.s - 20)
                headPal.l = min(88, headPal.l + 14)
                ctx.setFillColor(fxCGColor(headPal, alpha: rn.life * 0.9))
                ctx.fillEllipse(in: CGRect(x: rn.x - rn.size * 0.7, y: rn.y - rn.size * 0.7,
                                           width: rn.size * 1.4, height: rn.size * 1.4))
            }
            return true
        }
        ctx.restoreGState()

        // 噼啪点（source-over）
        crackles = crackles.filter { c in
            c.life -= 0.14 * f
            if c.life <= 0 { return false }
            if Double.random(in: 0..<1) < 0.75 {
                ctx.setFillColor(fxRGB(255, 246, 200, c.life * 0.9))
                ctx.fillEllipse(in: CGRect(x: c.x + fxRand(-1.5, 1.5) - 0.9,
                                           y: c.y + fxRand(-1.5, 1.5) - 0.9,
                                           width: 1.8, height: 1.8))
            }
            return true
        }
    }

    // MARK: - 孔明灯

    private func spawnLantern(init initial: Bool, wish: String? = nil) {
        guard lanterns.count < FxTuning88.lnCap, W > 0, H > 0 else { return }
        var tier: Int
        var s: Double
        if let wish = wish {
            _ = wish
            tier = 0; s = H * 0.088
        } else {
            // 三层配额（(88) 密度×1.25：[2,7,6]→[3,9,7]）：取
            // 剩余配额最大的一层
            let quota = FxTuning88.lnQuota
            var counts = [0, 0, 0]
            for o in lanterns { counts[o.tier] += 1 }
            tier = 2
            var best = -1
            for ti in 0..<3 {
                let room = quota[ti] - counts[ti]
                if room > best { best = room; tier = ti }
            }
            if tier == 0 { s = H * (0.068 + fxRand(0, 0.024)) }
            else if tier == 1 { s = H * (0.036 + fxRand(0, 0.016)) }
            else { s = 7 + fxRand(0, 6) }
        }
        let lantern = FxLantern(
            x: wish != nil ? W / 2 : fxRand(0, W),
            y: initial ? H * (-0.05 + pow(Double.random(in: 0..<1), 1.5) * 1.08) : H + 50,
            s: s, tier: tier,
            vy: -(tier == 0 ? 1.0 : tier == 1 ? 0.8 : 0.55) * (H / 800),
            vx: fxRand(-0.03, 0.03),
            ph: fxRand(0, 6.3), sway: 0.6 + fxRand(0, 0.7),
            bless: wish ?? FX_BLESSINGS[Int.random(in: 0..<FX_BLESSINGS.count)])
        lantern.wish = wish
        lanterns.append(lantern)
        refreshWishButton()
    }

    private func stepLanterns(_ ctx: CGContext, f: Double) {
        if isLanterns && nowMs - lnLastSpawn > 1600 && lanterns.count < FxTuning88.lnCap {
            lnLastSpawn = nowMs
            spawnLantern(init: false)
        }
        lanterns = lanterns.filter { L in
            L.drift += windPow * 0.028 * f
            L.x += (L.drift + windPow * 1.15 + L.vx) * f
            L.y += L.vy * (lnStopping ? 1.5 : 1) * f
            if lnStopping {
                L.alpha = max(0, (L.alpha ?? 1) - 0.008 * f)
            }
            drawLantern(ctx, L)
            return L.y > -L.s * 1.7 && L.x < W + 90 && (L.alpha ?? 1) > 0
        }
        if lanterns.isEmpty {
            lnStopping = false
            refreshWishButton()
            hideBless()
        }
    }

    /// port91（任务 2）：当前灯体帧（根视图坐标：中心＋灯高
    /// s），供 FxLinkage91 按距离给附近封面砖加暖色提亮。
    func lanternFrames91() -> [(center: CGPoint, radius: CGFloat)] {
        lanterns.map { (CGPoint(x: $0.x, y: $0.y), CGFloat($0.s)) }
    }

    /// 灯体命中（供主窗旁路点按）：半宽 s*0.66+12、半高 s*0.88+12。
    fileprivate func lantern(at p: CGPoint) -> FxLantern? {
        for L in lanterns.reversed() {
            if abs(Double(p.x) - L.x) <= L.s * 0.66 + 12
                && abs(Double(p.y) - L.y) <= L.s * 0.88 + 12 {
                return L
            }
        }
        return nil
    }

    private func drawLantern(_ ctx: CGContext, _ L: FxLantern) {
        let swayX = sin(nowMs * 0.00035 * L.sway + L.ph) * (4 + L.s * 0.05)
            + sin(nowMs * 0.0009 * L.sway + L.ph * 2.3) * 1.6
        let tilt = sin(nowMs * 0.0004 * L.sway + L.ph) * 0.045 + windPow * 0.1
        let alpha = max(0, min(1, L.alpha ?? 1))
        if L.tier == 2 {
            drawFarLantern(ctx, L, swayX: swayX, tilt: tilt, alpha: alpha)
            return
        }
        let s = L.s, w = s, h = s * 1.4
        let wt = w * 0.37, wb = w * 0.30
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(L.x + swayX), y: CGFloat(L.y))
        ctx.rotate(by: CGFloat(tilt))
        ctx.setAlpha(CGFloat(alpha))

        // 光晕：additive 径向，半径 s*1.9，中心 h*0.26
        // （(88) 暖红：晕色随纸面同向红移）
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        fxFillRadial(ctx, center: CGPoint(x: 0, y: h * 0.26), r0: 1, r1: CGFloat(s * 1.9),
                     stops: [(0, fxRGB(255, 146, 74, 0.20)),
                             (0.5, fxRGB(255, 124, 60, 0.06)),
                             (1, fxRGB(255, 110, 48, 0))],
                     rect: CGRect(x: -s * 2.1, y: -s * 2.0, width: s * 4.2, height: s * 4.2))
        ctx.restoreGState()

        func bodyPath() -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -wt, y: -h / 2 + s * 0.02))
            path.addQuadCurve(to: CGPoint(x: wt, y: -h / 2 + s * 0.02),
                              control: CGPoint(x: 0, y: -h / 2 - s * 0.045))
            path.addCurve(to: CGPoint(x: wb, y: h / 2),
                          control1: CGPoint(x: w * 0.50, y: -h * 0.20),
                          control2: CGPoint(x: w * 0.50, y: h * 0.18))
            path.addLine(to: CGPoint(x: -wb, y: h / 2))
            path.addCurve(to: CGPoint(x: -wt, y: -h / 2 + s * 0.02),
                          control1: CGPoint(x: -w * 0.50, y: h * 0.18),
                          control2: CGPoint(x: -w * 0.50, y: -h * 0.20))
            path.closeSubpath()
            return path
        }
        let bodyRect = CGRect(x: -w, y: -h, width: w * 2, height: h * 2)

        // 纸面竖直渐变（(88) 工坊定案暖红：自蜜金向红橙移，
        // 亮度骨架不变、只移色相）
        ctx.saveGState()
        ctx.addPath(bodyPath())
        ctx.clip()
        fxFillLinearV(ctx, top: CGPoint(x: 0, y: -h / 2), bottom: CGPoint(x: 0, y: h / 2),
                      stops: [(0, fxRGB(255, 190, 132, 0.96)),
                              (0.38, fxRGB(255, 150, 94, 0.97)),
                              (0.75, fxRGB(248, 116, 74, 0.98)),
                              (1, fxRGB(255, 164, 102, 0.99))],
                      rect: bodyRect)
        // 横向 limb 暗角
        let limbColors: [(CGFloat, CGColor)] = [
            (0, fxRGB(150, 70, 16, 0.15)), (0.22, fxRGB(150, 70, 16, 0.05)),
            (0.5, fxRGB(255, 255, 240, 0.06)), (0.78, fxRGB(150, 70, 16, 0.05)),
            (1, fxRGB(150, 70, 16, 0.15))
        ]
        if let limb = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: limbColors.map { $0.1 } as CFArray,
                                 locations: limbColors.map { $0.0 }) {
            ctx.drawLinearGradient(limb, start: CGPoint(x: -w / 2, y: 0),
                                   end: CGPoint(x: w / 2, y: 0), options: [])
        }
        // 竖向 shade
        fxFillLinearV(ctx, top: CGPoint(x: 0, y: -h / 2), bottom: CGPoint(x: 0, y: h / 2),
                      stops: [(0, fxRGB(150, 70, 16, 0.10)),
                              (0.3, fxRGB(150, 70, 16, 0)),
                              (0.8, fxRGB(255, 200, 110, 0.10)),
                              (1, fxRGB(120, 50, 10, 0.07))],
                      rect: bodyRect)
        // 低位热核径向（(88) 暖红同移）
        fxFillRadial(ctx, center: CGPoint(x: 0, y: h * 0.30), r0: 1, r1: CGFloat(s * 0.95),
                     stops: [(0, fxRGB(255, 232, 170, 0.50)),
                             (0.5, fxRGB(255, 186, 94, 0.15)),
                             (1, fxRGB(255, 156, 84, 0))],
                     rect: bodyRect)
        // 灯纸上的字（wish 灯）：深棕、每行 6 字最多 2 行
        if let wish = L.wish {
            let fs = max(7, s * 0.21)
            let chars = Array(wish)
            let shown = chars.count > 12 ? String(chars.prefix(12)) + "…" : wish
            let shownChars = Array(shown)
            var lines: [String] = []
            var idx = 0
            while idx < shownChars.count && lines.count < 2 {
                lines.append(String(shownChars[idx..<min(idx + 6, shownChars.count)]))
                idx += 6
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: CGFloat(fs), weight: .semibold),
                .foregroundColor: UIColor(red: 74 / 255, green: 26 / 255, blue: 4 / 255, alpha: 0.82),
            ]
            for (li, line) in lines.enumerated() {
                let str = line as NSString
                let sz = str.size(withAttributes: attrs)
                str.draw(at: CGPoint(x: -sz.width / 2,
                                     y: CGFloat(-h * 0.08) + CGFloat(li) * CGFloat(fs) * 1.5 - sz.height / 2),
                         withAttributes: attrs)
            }
        }
        // 纸内 vignette
        fxFillRadial(ctx, center: CGPoint(x: 0, y: h * 0.1), r0: CGFloat(s * 0.2),
                     r1: CGFloat(s * 0.95),
                     stops: [(0, fxRGB(140, 60, 10, 0)), (1, fxRGB(140, 60, 10, 0.08))],
                     rect: bodyRect)
        ctx.restoreGState()

        // 底部开口亮椭圆
        ctx.saveGState()
        let mouthRect = CGRect(x: -wb, y: h / 2 - wb * 0.30, width: wb * 2, height: wb * 0.60)
        ctx.addEllipse(in: mouthRect)
        ctx.clip()
        fxFillRadial(ctx, center: CGPoint(x: 0, y: h / 2), r0: 0.5, r1: CGFloat(wb * 0.9),
                     stops: [(0, fxRGB(255, 252, 230, 0.99)),
                             (0.55, fxRGB(255, 214, 110, 0.97)),
                             (1, fxRGB(226, 120, 36, 0.95))],
                     rect: mouthRect)
        ctx.restoreGState()

        // 火焰：仅开口中央一条短竖条
        let fh = s * 0.13, fw2 = s * 0.045
        let flame = CGMutablePath()
        flame.move(to: CGPoint(x: -fw2, y: h / 2 + wb * 0.06))
        flame.addQuadCurve(to: CGPoint(x: 0, y: h / 2 - fh),
                           control: CGPoint(x: -fw2, y: h / 2 - fh * 0.6))
        flame.addQuadCurve(to: CGPoint(x: fw2, y: h / 2 + wb * 0.06),
                           control: CGPoint(x: fw2, y: h / 2 - fh * 0.6))
        flame.closeSubpath()
        ctx.saveGState()
        ctx.addPath(flame)
        ctx.clip()
        fxFillLinearV(ctx, top: CGPoint(x: 0, y: h / 2), bottom: CGPoint(x: 0, y: h / 2 - fh),
                      stops: [(0, fxRGB(255, 190, 80, 0.95)), (1, fxRGB(255, 252, 235, 0.99))],
                      rect: CGRect(x: -fw2, y: h / 2 - fh, width: fw2 * 2, height: fh + wb * 0.06))
        ctx.restoreGState()

        ctx.restoreGState()
    }

    private func drawFarLantern(_ ctx: CGContext, _ L: FxLantern, swayX: Double,
                                tilt: Double, alpha: Double) {
        let s = L.s
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(L.x + swayX), y: CGFloat(L.y))
        ctx.rotate(by: CGFloat(tilt))
        ctx.setAlpha(CGFloat(alpha))
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        fxFillRadial(ctx, center: .zero, r0: 0.5, r1: CGFloat(s * 1.6),
                     stops: [(0, fxRGB(255, 182, 100, 0.8)),
                             (0.35, fxRGB(255, 140, 62, 0.30)),
                             (1, fxRGB(255, 120, 52, 0))],
                     rect: CGRect(x: -s * 1.6, y: -s * 1.6, width: s * 3.2, height: s * 3.2))
        ctx.restoreGState()
        let bodyRect = CGRect(x: -s * 0.30, y: -s * 0.42, width: s * 0.60, height: s * 0.84)
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        fxFillLinearV(ctx, top: CGPoint(x: 0, y: -s * 0.42), bottom: CGPoint(x: 0, y: s * 0.42),
                      stops: [(0, fxRGB(214, 96, 46, 0.95)), (1, fxRGB(255, 186, 100, 0.98))],
                      rect: bodyRect)
        ctx.restoreGState()
        ctx.restoreGState()
    }

    // MARK: - 下雪

    private func spawnFlake(init initial: Bool) {
        guard flakes.count < 185, W > 0, H > 0 else { return }
        let layer = Double.random(in: 0..<1)
        let near = layer > 0.86
        let mid = layer > 0.45 && !near
        flakes.append(FxFlake(
            x: fxRand(0, W), y: initial ? fxRand(0, H) : -10,
            r: near ? 3 + fxRand(0, 2.6) : mid ? 1.5 + fxRand(0, 1.4) : 0.6 + fxRand(0, 0.9),
            vy: near ? 0.85 + fxRand(0, 0.7) : mid ? 0.55 + fxRand(0, 0.6) : 0.3 + fxRand(0, 0.35),
            ph: fxRand(0, 6.3), sway: 0.35 + fxRand(0, 1.0),
            o: near ? 0.95 : mid ? 0.7 : 0.42,
            near: near, rot: fxRand(0, 6.3), vr: fxRand(-0.006, 0.006),
            tumble: fxRand(0, 6.3), vt: 0.008 + fxRand(0, 0.02)))
    }

    private func stepSnow(_ ctx: CGContext, f: Double) {
        if isSnow {
            if nowMs - snStart > 12000 {
                setSnow(false, src: "auto")   // 12 秒自动停，之后 snMelt 渐隐
            } else if flakes.count < 185 && chance(0.65, f) {
                spawnFlake(init: false)
            }
        } else if !flakes.isEmpty {
            snMelt = max(0, snMelt - 0.006 * f)
        }
        guard !flakes.isEmpty else { return }
        flakes = flakes.filter { fl in
            fl.y += fl.vy * (1 + 0.16 * sin(nowMs * 0.0011 + fl.ph * 2)) * f
            fl.x += (sin(nowMs * 0.0009 * fl.sway + fl.ph) * 0.55
                + sin(nowMs * 0.0023 + fl.ph * 3.1) * 0.22
                + windPow * (fl.near ? 3.1 : 1.9)) * f
            fl.rot += (fl.vr + windPow * 0.01) * f
            fl.tumble += fl.vt * f
            if fl.y > H + 10 || fl.x > W + 12 { return false }
            if fl.near {
                drawCrystal(ctx, fl)
            } else {
                // mid/far：失焦圆。(93) A4 改共享精灵贴图
                // （fxSnowDot93，雪色淡蓝同 FxTuning88.
                // snowTint）——旧逐粒径向渐变填充退役，粒
                // 径/透明口径与旧式一致（半径 r×1.6、alpha
                // ＝o×snMelt），零逐帧渐变分配。
                if let dot = fxSnowDot93 {
                    let d = CGFloat(fl.r * 3.2)
                    ctx.saveGState()
                    ctx.setAlpha(CGFloat(max(0, min(1, fl.o * snMelt))))
                    ctx.draw(dot, in: CGRect(x: fl.x - d / 2, y: fl.y - d / 2,
                                             width: d, height: d))
                    ctx.restoreGState()
                }
            }
            return true
        }
        if !isSnow && snMelt <= 0 { flakes = [] }
    }

    private func drawCrystal(_ ctx: CGContext, _ fl: FxFlake) {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(fl.x), y: CGFloat(fl.y))
        ctx.rotate(by: CGFloat(fl.rot))
        ctx.scaleBy(x: 1, y: CGFloat(0.35 + 0.65 * abs(cos(fl.tumble))))
        let st = FxTuning88.snowTint   // (88) 雪色淡蓝
        ctx.setStrokeColor(fxRGB(st.0, st.1, st.2, fl.o * snMelt))
        ctx.setLineWidth(0.9)
        ctx.setLineCap(.round)
        let r = fl.r
        for arm in 0..<6 {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(Double(arm) * Double.pi / 3))
            ctx.beginPath()
            ctx.move(to: .zero); ctx.addLine(to: CGPoint(x: 0, y: -r))
            ctx.move(to: CGPoint(x: 0, y: -r * 0.55)); ctx.addLine(to: CGPoint(x: -r * 0.3, y: -r * 0.82))
            ctx.move(to: CGPoint(x: 0, y: -r * 0.55)); ctx.addLine(to: CGPoint(x: r * 0.3, y: -r * 0.82))
            ctx.move(to: CGPoint(x: 0, y: -r * 0.3)); ctx.addLine(to: CGPoint(x: -r * 0.2, y: -r * 0.5))
            ctx.move(to: CGPoint(x: 0, y: -r * 0.3)); ctx.addLine(to: CGPoint(x: r * 0.2, y: -r * 0.5))
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    // MARK: - 刮风

    private func flowAngle(x: Double, y: Double, now: Double) -> Double {
        sin(x * 0.004 + now * 0.0004) * 0.32
            + sin(y * 0.006 - now * 0.0006) * 0.26
            + sin((x + y) * 0.002 + now * 0.0002) * 0.18
    }

    private func spawnStreak() {
        guard streaks.count < 60 else { return }
        streaks.append(FxStreak(x: -30 - fxRand(0, 80), y: fxRand(0, H * 0.94),
                                vx: 5.5 + fxRand(0, 4), o: 0.1 + fxRand(0, 0.22),
                                seed: fxRand(0, 100)))
    }

    private func spawnLeaf() {
        guard leaves.count < 40 else { return }
        leaves.append(FxLeaf(x: -24, y: fxRand(0, H * 0.95),
                             vx: 3 + fxRand(0, 3.4), vy: fxRand(-0.55, 0.55),
                             rot: fxRand(0, 6.3), vr: fxRand(-0.1, 0.1),
                             tumble: fxRand(0, 6.3), vt: 0.05 + fxRand(0, 0.09),
                             s: 4 + fxRand(0, 5), pink: Double.random(in: 0..<1) < 0.6,
                             ph: fxRand(0, 6.3)))
    }

    private func stepWind(_ ctx: CGContext, f: Double) {
        if isWind {
            // (93) A2：5 秒自动停退役——(92) 日志实锤风开启
            // 后 +5.002s/+5.008s 两次无点按自关（来源即此
            // 硬编码超时，与雪 12 秒自融不同、风无自融语
            // 义）。风只许手动关（toggleWind）或互斥清场
            // （startFw）才关，与烟花/孔明灯同口径；生成
            // 节奏（streak/leaf 概率）一字不动。
            if chance(0.55, f) { spawnStreak() }
            if chance(0.30, f) { spawnLeaf() }
        }
        streaks = streaks.filter { s in
            let ang = flowAngle(x: s.x, y: s.y, now: nowMs + s.seed * 40)
            s.vy += (sin(ang) * 2.4 - s.vy) * (1 - pow(0.92, f))
            s.x += s.vx * (0.7 + windPow * 0.6) * f
            s.y += (s.vy + cos(ang) * 0.7) * f
            s.hist.append(CGPoint(x: s.x, y: s.y))
            if s.hist.count > 16 { s.hist.removeFirst(s.hist.count - 16) }
            if s.x > W + 30 { return false }
            if s.hist.count > 3 {
                ctx.setLineCap(.round)
                for hi in 1..<s.hist.count {
                    let f2 = Double(hi) / Double(s.hist.count)
                    ctx.beginPath()
                    ctx.move(to: s.hist[hi - 1])
                    ctx.addLine(to: s.hist[hi])
                    ctx.setStrokeColor(fxRGB(216, 246, 238, s.o * f2 * f2))
                    ctx.setLineWidth(CGFloat(0.6 + f2 * 1.3))
                    ctx.strokePath()
                }
                ctx.setFillColor(fxRGB(235, 255, 250, s.o + 0.12))
                ctx.fillEllipse(in: CGRect(x: s.x - 1.1, y: s.y - 1.1, width: 2.2, height: 2.2))
            }
            return true
        }
        leaves = leaves.filter { lf in
            let ang = flowAngle(x: lf.x, y: lf.y, now: nowMs)
            lf.x += (lf.vx + windPow * 2.4) * f
            lf.y += (lf.vy + sin(nowMs * 0.004 + lf.ph) * 0.75 + sin(ang) * 1.1) * f
            lf.rot += lf.vr * (0.6 + windPow) * f
            lf.tumble += lf.vt * f
            if lf.x > W + 26 { return false }
            drawPetal(ctx, lf)
            return true
        }
    }

    private func drawPetal(_ ctx: CGContext, _ lf: FxLeaf) {
        let s = lf.s
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(lf.x), y: CGFloat(lf.y))
        ctx.rotate(by: CGFloat(lf.rot))
        ctx.scaleBy(x: 1, y: CGFloat(0.3 + 0.7 * abs(cos(lf.tumble))))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -s, y: 0))
        path.addCurve(to: CGPoint(x: s, y: -s * 0.08),
                      control1: CGPoint(x: -s * 0.4, y: -s * 0.62),
                      control2: CGPoint(x: s * 0.45, y: -s * 0.55))
        path.addCurve(to: CGPoint(x: s * 0.82, y: s * 0.3),
                      control1: CGPoint(x: s * 0.55, y: s * 0.1),
                      control2: CGPoint(x: s * 0.6, y: s * 0.28))
        path.addCurve(to: CGPoint(x: -s, y: 0),
                      control1: CGPoint(x: s * 0.3, y: s * 0.62),
                      control2: CGPoint(x: -s * 0.45, y: s * 0.6))
        path.closeSubpath()
        ctx.addPath(path)
        let stops: [(CGFloat, CGColor)] = lf.pink
            ? [(0, fxRGB(255, 205, 222, 0.92)), (0.55, fxRGB(255, 158, 190, 0.94)), (1, fxRGB(238, 120, 164, 0.92))]
            : [(0, fxRGB(214, 238, 180, 0.92)), (0.55, fxRGB(158, 210, 120, 0.94)), (1, fxRGB(110, 178, 84, 0.92))]
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: stops.map { $0.1 } as CFArray,
                                 locations: stops.map { $0.0 }) {
            ctx.saveGState()
            ctx.clip()
            ctx.drawLinearGradient(grad, start: CGPoint(x: -s, y: 0), end: CGPoint(x: s, y: 0), options: [])
            ctx.restoreGState()
        }
        ctx.beginPath()
        ctx.move(to: CGPoint(x: -s * 0.85, y: 0))
        ctx.addQuadCurve(to: CGPoint(x: s * 0.8, y: -s * 0.04),
                         control: CGPoint(x: 0, y: -s * 0.08))
        ctx.setStrokeColor(lf.pink ? fxRGB(190, 70, 120, 0.4) : fxRGB(70, 130, 50, 0.4))
        ctx.setLineWidth(0.7)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - 叠加 UI（闪光层 / 祝福卡 / 写灯钮 / 推荐卡，照样片样式）

    /// port91（任务 1）：闪光层是纯视觉件，留在 Fx 窗内（随
    /// 纯显示层一并渲染）；其余可交互件迁主窗浮层（下）。
    private func buildFlash91(in rv: Fx87RootView) {
        // 白色闪光层（flashWall）：不拦截触摸
        let fv = UIView()
        fv.backgroundColor = .white
        fv.alpha = 0
        fv.isUserInteractionEnabled = false
        fv.translatesAutoresizingMaskIntoConstraints = false
        rv.addSubview(fv)
        NSLayoutConstraint.activate([
            fv.leadingAnchor.constraint(equalTo: rv.leadingAnchor),
            fv.trailingAnchor.constraint(equalTo: rv.trailingAnchor),
            fv.topAnchor.constraint(equalTo: rv.topAnchor),
            fv.bottomAnchor.constraint(equalTo: rv.bottomAnchor),
        ])
        flashView = fv
    }

    /// port91（任务 1）：祝福卡/写灯钮/推荐卡建在主窗浮层宿
    /// 主上（约束锚宿主＝主窗全幅，几何与旧 Fx 窗内一致）。
    private func buildCards91(in rv: UIView) {
        // 祝福卡：居中偏下、深棕渐变＋灯图标＋16.5pt 文案＋「收起」钮
        let card = UIView()
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = fxRGB(255, 190, 100, 0.45)
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.6
        card.layer.shadowRadius = 25
        card.layer.shadowOffset = CGSize(width: 0, height: 22)
        card.isHidden = true
        card.translatesAutoresizingMaskIntoConstraints = false
        let grad = CAGradientLayer()
        grad.colors = [fxRGB(58, 32, 14, 0.92), fxRGB(34, 20, 10, 0.94)]
        grad.startPoint = CGPoint(x: 0.5, y: 0)
        grad.endPoint = CGPoint(x: 0.5, y: 1)
        grad.cornerRadius = 18
        grad.frame = CGRect(x: 0, y: 0, width: 262, height: 160)
        card.layer.insertSublayer(grad, at: 0)
        let lamp = UIImageView(image: GlobalFx87.lanternIconImage())
        lamp.contentMode = .scaleAspectFit
        lamp.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(lamp)
        let label = UILabel()
        label.font = .systemFont(ofSize: 16.5, weight: .semibold)
        label.textColor = UIColor(red: 1, green: 233 / 255, blue: 196 / 255, alpha: 1)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        blessLabel = label
        let close = UIButton(type: .system)
        close.setTitle("收起", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 13)
        close.setTitleColor(UIColor(red: 1, green: 233 / 255, blue: 196 / 255, alpha: 1), for: .normal)
        close.layer.borderWidth = 1
        close.layer.borderColor = fxRGB(255, 205, 130, 0.5)
        close.layer.cornerRadius = 17
        close.backgroundColor = UIColor(red: 1, green: 180 / 255, blue: 90 / 255, alpha: 0.14)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(hideBless), for: .touchUpInside)
        card.addSubview(close)
        rv.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: rv.centerXAnchor),
            card.bottomAnchor.constraint(equalTo: rv.bottomAnchor, constant: -118),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 262),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: rv.leadingAnchor, constant: 28),
            card.trailingAnchor.constraint(lessThanOrEqualTo: rv.trailingAnchor, constant: -28),
            lamp.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            lamp.topAnchor.constraint(equalTo: card.topAnchor, constant: -15),
            lamp.widthAnchor.constraint(equalToConstant: 30),
            lamp.heightAnchor.constraint(equalToConstant: 30),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            close.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 13),
            close.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            close.widthAnchor.constraint(equalToConstant: 76),
            close.heightAnchor.constraint(equalToConstant: 34),
            close.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15),
        ])
        blessCard = card

        // 写灯钮：灯在场时右下角 46pt 圆钮
        let wish = UIButton(type: .custom)
        wish.setImage(GlobalFx87.lanternIconImage(), for: .normal)
        wish.backgroundColor = UIColor(red: 40 / 255, green: 24 / 255, blue: 10 / 255, alpha: 0.55)
        wish.layer.cornerRadius = 23
        wish.layer.borderWidth = 0.5
        wish.layer.borderColor = fxRGB(255, 200, 120, 0.55)
        wish.layer.shadowColor = UIColor.black.cgColor
        wish.layer.shadowOpacity = 0.45
        wish.layer.shadowRadius = 11
        wish.layer.shadowOffset = CGSize(width: 0, height: 8)
        wish.imageEdgeInsets = UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11)
        wish.isHidden = true
        wish.translatesAutoresizingMaskIntoConstraints = false
        wish.addTarget(self, action: #selector(wishButtonTapped), for: .touchUpInside)
        rv.addSubview(wish)
        NSLayoutConstraint.activate([
            wish.trailingAnchor.constraint(equalTo: rv.trailingAnchor, constant: -14),
            wish.bottomAnchor.constraint(equalTo: rv.bottomAnchor, constant: -14),
            wish.widthAnchor.constraint(equalToConstant: 46),
            wish.heightAnchor.constraint(equalToConstant: 46),
        ])
        wishButton = wish

        // 推荐卡：底部、封面＋标题/歌手＋播放/下次吧
        let rec = UIView()
        rec.backgroundColor = UIColor(red: 24 / 255, green: 23 / 255, blue: 30 / 255, alpha: 0.88)
        rec.layer.cornerRadius = 20
        rec.layer.borderWidth = 1
        rec.layer.borderColor = fxRGB(255, 205, 120, 0.4)
        rec.layer.shadowColor = UIColor.black.cgColor
        rec.layer.shadowOpacity = 0.55
        rec.layer.shadowRadius = 30
        rec.layer.shadowOffset = CGSize(width: 0, height: 24)
        rec.isHidden = true
        rec.translatesAutoresizingMaskIntoConstraints = false
        let cover = UIImageView()
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 13
        cover.backgroundColor = UIColor(white: 1, alpha: 0.12)
        cover.translatesAutoresizingMaskIntoConstraints = false
        rec.addSubview(cover)
        recCover = cover
        let title = UILabel()
        title.font = .systemFont(ofSize: 17.5, weight: .heavy)
        title.textColor = UIColor(red: 246 / 255, green: 243 / 255, blue: 236 / 255, alpha: 1)
        title.numberOfLines = 2
        title.translatesAutoresizingMaskIntoConstraints = false
        rec.addSubview(title)
        recTitle = title
        let artist = UILabel()
        artist.font = .systemFont(ofSize: 13)
        artist.textColor = UIColor(red: 246 / 255, green: 243 / 255, blue: 236 / 255, alpha: 0.65)
        artist.translatesAutoresizingMaskIntoConstraints = false
        rec.addSubview(artist)
        recArtist = artist
        let play = UIButton(type: .system)
        play.setTitle("播放", for: .normal)
        play.titleLabel?.font = .systemFont(ofSize: 14.5, weight: .bold)
        play.setTitleColor(UIColor(red: 36 / 255, green: 19 / 255, blue: 0, alpha: 1), for: .normal)
        play.layer.cornerRadius = 12
        play.translatesAutoresizingMaskIntoConstraints = false
        let playGrad = CAGradientLayer()
        playGrad.colors = [UIColor(red: 1, green: 176 / 255, blue: 46 / 255, alpha: 1).cgColor,
                           UIColor(red: 1, green: 125 / 255, blue: 84 / 255, alpha: 1).cgColor]
        playGrad.startPoint = CGPoint(x: 0, y: 0)
        playGrad.endPoint = CGPoint(x: 1, y: 1)
        playGrad.frame = CGRect(x: 0, y: 0, width: 200, height: 44)
        playGrad.cornerRadius = 12
        play.layer.insertSublayer(playGrad, at: 0)
        play.addTarget(self, action: #selector(recPlayTapped), for: .touchUpInside)
        rec.addSubview(play)
        let later = UIButton(type: .system)
        later.setTitle("下次吧", for: .normal)
        later.titleLabel?.font = .systemFont(ofSize: 14)
        later.setTitleColor(UIColor(red: 246 / 255, green: 243 / 255, blue: 236 / 255, alpha: 1), for: .normal)
        later.layer.borderWidth = 1
        later.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        later.layer.cornerRadius = 12
        later.translatesAutoresizingMaskIntoConstraints = false
        later.addTarget(self, action: #selector(hideRecCard), for: .touchUpInside)
        rec.addSubview(later)
        rv.addSubview(rec)
        // (93) C4：定位三约束单独持有（默认落位），show 时
        // 可整组停用换动态对齐约束；边距守卫约束恒在。
        let recCenterX93 = rec.centerXAnchor.constraint(equalTo: rv.centerXAnchor)
        let recBottom93 = rec.bottomAnchor.constraint(equalTo: rv.bottomAnchor, constant: -46)
        let recWidth93 = rec.widthAnchor.constraint(lessThanOrEqualToConstant: 340)
        recDefaultPos93 = [recCenterX93, recBottom93, recWidth93]
        NSLayoutConstraint.activate([
            recCenterX93, recBottom93, recWidth93,
            rec.leadingAnchor.constraint(greaterThanOrEqualTo: rv.leadingAnchor, constant: 20),
            rec.trailingAnchor.constraint(lessThanOrEqualTo: rv.trailingAnchor, constant: -20),
            cover.leadingAnchor.constraint(equalTo: rec.leadingAnchor, constant: 15),
            cover.topAnchor.constraint(equalTo: rec.topAnchor, constant: 15),
            cover.widthAnchor.constraint(equalToConstant: 74),
            cover.heightAnchor.constraint(equalToConstant: 74),
            title.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 13),
            title.trailingAnchor.constraint(equalTo: rec.trailingAnchor, constant: -15),
            title.topAnchor.constraint(equalTo: rec.topAnchor, constant: 24),
            artist.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            artist.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            artist.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            play.leadingAnchor.constraint(equalTo: rec.leadingAnchor, constant: 15),
            play.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 13),
            play.heightAnchor.constraint(equalToConstant: 44),
            later.leadingAnchor.constraint(equalTo: play.trailingAnchor, constant: 9),
            later.trailingAnchor.constraint(equalTo: rec.trailingAnchor, constant: -15),
            later.topAnchor.constraint(equalTo: play.topAnchor),
            later.widthAnchor.constraint(equalToConstant: 84),
            later.heightAnchor.constraint(equalToConstant: 44),
            play.bottomAnchor.constraint(equalTo: rec.bottomAnchor, constant: -15),
        ])
        recCard = rec
    }

    /// 孔明灯图标（按样片 SVG 路径近似描画，程序生成、无外部素材）。
    private static func lanternIconImage() -> UIImage {
        let size = CGSize(width: 24, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let stroke = UIColor(red: 1, green: 207 / 255, blue: 138 / 255, alpha: 1)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 8.4, y: 3.8))
            path.addLine(to: CGPoint(x: 15.6, y: 3.8))
            path.move(to: CGPoint(x: 8.7, y: 3.8))
            path.addCurve(to: CGPoint(x: 6.5, y: 11.9),
                          controlPoint1: CGPoint(x: 7.2, y: 6.4), controlPoint2: CGPoint(x: 6.3, y: 9.1))
            path.addCurve(to: CGPoint(x: 9.5, y: 17.1),
                          controlPoint1: CGPoint(x: 6.7, y: 14.3), controlPoint2: CGPoint(x: 7.9, y: 16.4))
            path.addLine(to: CGPoint(x: 14.5, y: 17.1))
            path.addCurve(to: CGPoint(x: 17.5, y: 11.9),
                          controlPoint1: CGPoint(x: 16.1, y: 16.4), controlPoint2: CGPoint(x: 17.3, y: 14.3))
            path.addCurve(to: CGPoint(x: 15.3, y: 3.8),
                          controlPoint1: CGPoint(x: 17.7, y: 9.1), controlPoint2: CGPoint(x: 16.8, y: 6.4))
            path.move(to: CGPoint(x: 9.5, y: 17.1))
            path.addLine(to: CGPoint(x: 14.5, y: 17.1))
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            stroke.setStroke()
            path.stroke()
            let flame = UIBezierPath()
            flame.move(to: CGPoint(x: 12, y: 13.6))
            flame.addCurve(to: CGPoint(x: 12, y: 16.5),
                           controlPoint1: CGPoint(x: 12.9, y: 14.6), controlPoint2: CGPoint(x: 12.9, y: 15.5))
            flame.addCurve(to: CGPoint(x: 12, y: 13.6),
                           controlPoint1: CGPoint(x: 11.1, y: 15.5), controlPoint2: CGPoint(x: 11.1, y: 14.6))
            flame.close()
            stroke.setFill()
            flame.fill()
        }
    }

    // MARK: 卡片显隐与命中

    /// 点是否落在可见的卡片/写灯钮上（port91 前为 Fx 窗
    /// hitTest 用；纯显示层后保留备查，点按判定走主窗旁路）。
    func interactiveSubviewHit(at point: CGPoint, in view: UIView) -> Bool {
        for sub in [recCard, blessCard, wishButton] {
            guard let sub = sub, !sub.isHidden, sub.alpha > 0 else { continue }
            if sub.frame.contains(point) { return true }
        }
        return false
    }

    private func refreshWishButton() {
        wishButton?.isHidden = !(isLanterns || !lanterns.isEmpty)
    }

    func showBless(_ text: String) {
        guard let card = blessCard, let label = blessLabel else { return }
        // (94) 94-7：防重入——展示中再触发不重弹、不重置计
        // 时，只落计数面包屑（黄面嫌疑的反复弹起在此收口）。
        if !card.isHidden {
            blessDup94 += 1
            Breadcrumbs.log("p94 fx bless dup n=\(blessDup94)")
            return
        }
        label.text = text
        Breadcrumbs.log("fx87 bless")
        blessHideWork?.cancel()
        card.isHidden = false
        card.transform = CGAffineTransform(scaleX: 0.82, y: 0.82).translatedBy(x: 0, y: 10)
        card.alpha = 0
        UIView.animate(withDuration: 0.38, delay: 0,
                       usingSpringWithDamping: 0.62, initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction]) {
            card.transform = .identity
            card.alpha = 1
        }
        let work = DispatchWorkItem { [weak self] in self?.hideBless() }
        blessHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2, execute: work)
    }

    @objc func hideBless() {
        blessHideWork?.cancel()
        blessHideWork = nil
        blessCard?.isHidden = true
    }

    /// (93) C4：推荐卡落位——控制台在场（ConsolePanel82.
    /// presentedCardFrame 非 nil，窗口坐标；宿主钉满主窗
    /// 故宿主系＝窗口系）时：卡宽＝该帧宽、x 与该帧对齐、
    /// y＝该帧 maxY＋8；算出卡底超出宿主高则改贴底收口。
    /// 控制台不在场：恢复默认落位（底部 −46/宽 ≤340）。
    private func layoutRecCard93(_ card: UIView) {
        NSLayoutConstraint.deactivate(recDynPos93)
        recDynPos93 = []
        guard let host = overlayHost91,
              let frame = ConsolePanel82.presentedCardFrame else {
            NSLayoutConstraint.activate(recDefaultPos93)
            return
        }
        NSLayoutConstraint.deactivate(recDefaultPos93)
        let top = card.topAnchor.constraint(
            equalTo: host.topAnchor, constant: frame.maxY + 8)
        recDynPos93 = [
            card.leadingAnchor.constraint(
                equalTo: host.leadingAnchor, constant: frame.minX),
            card.widthAnchor.constraint(equalToConstant: frame.width),
            top,
        ]
        NSLayoutConstraint.activate(recDynPos93)
        host.layoutIfNeeded()
        if card.frame.maxY > host.bounds.height {
            // 贴底收口：拆 top 换底锚（宿主底 −8）。
            NSLayoutConstraint.deactivate([top])
            let bottom = card.bottomAnchor.constraint(
                equalTo: host.bottomAnchor, constant: -8)
            recDynPos93[2] = bottom
            NSLayoutConstraint.activate([bottom])
            host.layoutIfNeeded()
        }
    }

    /// (95) 任务 3：推荐卡统一开启边沿呈现判断——本 fx 会
    /// 话（任一特效开→全关）内只呈一次；recShown 在全部特
    /// 效关闭时于 refreshTapProbe92 的 disarm 边沿复位，
    /// startFw 内原有的 recShown 复位保留（新一轮烟花秀
    /// 语义与新口径一致：互斥清场先全关、复位已在彼处发
    /// 生，此处再置 false 无副作用）。
    private func maybeShowRec95() {
        guard !recShown else { return }
        recShown = true
        showRecCard()
    }

    private func showRecCard() {
        // (95) 任务 3：provider 缺失不再静默——落 miss 自证。
        guard let provider = recommendationProvider else {
            Breadcrumbs.log("fx87 rec miss why=noprovider")
            return
        }
        guard let rec = provider() else {
            Breadcrumbs.log("fx87 rec miss why=norec")
            return
        }
        guard let card = recCard else { return }
        recTitle?.text = rec.title
        recArtist?.text = rec.artist
        recCover?.image = rec.cover
        Breadcrumbs.log("fx87 rec")
        card.isHidden = false
        layoutRecCard93(card)
        // (95) 任务 3：几何对账——卡实际落位 minX/宽与控制
        // 台 presentedCardFrame 宽同行（无控制台时 -1）。
        let consoleW95 = ConsolePanel82.presentedCardFrame
            .map { Int($0.width.rounded()) } ?? -1
        Breadcrumbs.log("p95 rec geo x=\(Int(card.frame.minX.rounded()))"
            + " w=\(Int(card.frame.width.rounded())) console=\(consoleW95)")
        startRecRotate93()
        // (93) C4：入场按当前活跃特效区分（多特效同开取最
        // 近开启者 fxOnOrder93 尾元且仍活跃者）；无特效/
        // 无记录走旧通用入场（上移 30 淡入）。
        let fx = fxOnOrder93.last(where: {
            ($0 == "fw" && isFireworks) || ($0 == "ln" && isLanterns)
                || ($0 == "sn" && isSnow) || ($0 == "wd" && isWind)
        })
        card.alpha = 0
        var damping: CGFloat = 0.7
        switch fx {
        case "fw":   // 烟花：0.7 缩放绽开
            card.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        case "ln":   // 孔明灯：自下方 26pt 升起
            card.transform = CGAffineTransform(translationX: 0, y: 26)
        case "sn":   // 下雪：自上方 14pt 落定（回弹弹簧）
            card.transform = CGAffineTransform(translationX: 0, y: -14)
            damping = 0.55
        case "wd":   // 风：自侧方 30pt 掠入
            card.transform = CGAffineTransform(translationX: 30, y: 0)
        default:
            card.transform = CGAffineTransform(translationX: 0, y: 30)
        }
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: damping, initialSpringVelocity: 0.3,
                       options: [.allowUserInteraction]) {
            card.transform = .identity
            card.alpha = 1
        }
    }

    /// (93) C4：12 秒轮换——卡可见且任一特效开启时换下一
    /// 首推荐（走既有 recommendationProvider 通路，播放
    /// 仍走 onPlayRecommendation，点卡切歌通路不动）。
    private func startRecRotate93() {
        recRotateTimer93?.invalidate()
        recRotateTimer93 = Timer.scheduledTimer(
            withTimeInterval: 12, repeats: true) { [weak self] _ in
            guard let self,
                  self.isFireworks || self.isLanterns || self.isSnow || self.isWind,
                  let card = self.recCard, !card.isHidden,
                  let provider = self.recommendationProvider,
                  let rec = provider() else { return }
            self.recTitle?.text = rec.title
            self.recArtist?.text = rec.artist
            self.recCover?.image = rec.cover
        }
    }

    @objc private func hideRecCard() {
        recRotateTimer93?.invalidate()
        recRotateTimer93 = nil
        recCard?.isHidden = true
    }

    @objc private func recPlayTapped() {
        hideRecCard()
        onPlayRecommendation?()
    }

    // MARK: 写灯放飞（port91 任务 6：许愿灯整页，替换系统弹窗）

    /// 孔明灯图标外送（许愿页大灯造型复用同一字形源）。
    static func wishIcon91() -> UIImage { lanternIconImage() }

    @objc private func wishButtonTapped() {
        hideBless()
        // port91（任务 6）：UIAlertController 退役——改样板许
        // 愿灯整页（大灯居中＋文字实时落灯纸＋放飞升空），自
        // 主窗顶层 VC 呈现；入口仍是原写灯钮。
        guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
        let wish = WishLanternViewController91()
        wish.onRelease = { [weak self] text in
            self?.releaseWishLantern(text)
        }
        wish.modalPresentationStyle = .overFullScreen
        wish.modalTransitionStyle = .crossDissolve
        top.present(wish, animated: true)
        Breadcrumbs.log("p91 wish open")
    }

    func releaseWishLantern(_ text: String) {
        if !isLanterns { setLantern(true, src: "link") }
        lnStopping = false
        spawnLantern(init: false, wish: text)
        if let mine = lanterns.last {
            mine.y = H - 120
            mine.x = W / 2
        }
        Breadcrumbs.log("fx87 wish")
        ensureLoop()
        refreshWishButton()
        showBless(text)
    }
}
