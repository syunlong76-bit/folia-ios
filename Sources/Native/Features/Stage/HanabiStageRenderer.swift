import UIKit
import QuartzCore

// 花火 hanabi（3.7 (57) 工作流 B6，网页标样式第六）：按
// folia-major 网页版 hanabi/ 全目录的全量原生移植。依据：
// types.ts（DEFAULT_HANABI_TUNING / 预设与部件类型）、
// catalog.ts（10 族 × 5 = 50 预设全量数据 + BURST_PRESETS）、
// program.ts + hanabiProgram.ts（切镜头/选预设/间奏）、
// timeline.ts（上升 rise / 旋转 spin / 运镜 camera 的闭式
// 时间线）、scene.ts（镜头组装：主烟花/逐字小烟花/升空尾迹/
// 环境层/拼贴计划的事件规划）、mg/burstPlan.ts（烟花解析
// 模型：初速+线性阻尼+终端下落的闭式解、14 种 BurstKind、
// 升空尾迹）、mg/fireworks.ts（精灵池上限与按 rank 等比例
// 抽稀）、mg/ambient.ts（星点/薄烟/火星/散景/远方小烟花）、
// color.ts（9 种 PaletteRole × 主题 × colorMode、对比度
// 分离）、text/lyricText.ts + layout.ts + blocks.ts +
// animations.ts（9 排版 / 12 色块 / 17 入场 / 9 强调 / 7
// 退场的纯 t 函数）、hanabiSky.ts（夜空四色标）、overlay.ts
// （画框）、hanabiScreenBloom.ts（全屏辉光公式）、
// hanabiBeatFx.ts（节拍烟花：协议无节拍数据源——(62) 以
// 行首时间戳节拍近似补，见 frameTick 组装处注记）。
//
// 原生落点与选型：
//  - 粒子不用 CAEmitterLayer：网页烟花是「事件 + 闭式解」
//    的确定性模型（seek 到哪一刻画面都一样），CAEmitter 的
//    增量模拟给不出闭式位置、也无法按 rank 抽稀。改用定额
//    池口径的自绘粒子：两块全局 HanabiCanvasView（文字
//    后/前各一），逐帧按 time 从 BurstPlan 闭式求值后以
//    预渲染精灵图（dot/glow/star4，按色缓存）+ 折线
//    （拖尾）绘制，逐帧不分配大对象（计划随镜头构建时
//    一次性展开、离场释放）。粒子上限（单帧合计 1600 星）
//    与降级策略见渲染器 updateDegradation 处注记。
//  - 文字逐字视图（UILabel 群）由 frameTick 按纯 t 姿态
//    函数直接摆位（不走 UIView 动画），与网页「画面只由
//    time 决定」同义；色块为每镜头烘焙一次的 CAShapeLayer。
//  - 时钟纪律不变：只消费宿主 frameTick 的锚点位置，不自
//    建时钟源；数据只从 snapshot / context 取。
// 未移植/近似项如实列在交付报告（段落转场、片尾卡、拼贴
// 画手层、节拍烟花等），本文件内相关处亦有注记。

// MARK: - 确定性随机（visualizerSeedHash.ts / mgMath.ts 对译）

/// FNV-1a 32 位字符串散列（JS charCodeAt = UTF-16 码元）。
private func hanabiHashString(_ key: String) -> UInt32 {
    var hash: UInt32 = 0x811c9dc5
    for unit in key.utf16 {
        hash ^= UInt32(unit)
        hash = hash &* 16777619
    }
    return hash
}

/// mulberry32 随机流（createVisualizerRng 对译）：同一 key
/// 永远同一串数，seek/重建不改变画面。
private struct HanabiRng {
    private var state: UInt32

    init(key: String) { state = hanabiHashString(key) }
    init(seed: UInt32) { state = seed }

    mutating func next() -> Double {
        state = state &+ 0x6d2b79f5
        var t = state
        t = (t ^ (t >> 15)) &* (1 | t)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double((t ^ (t >> 14)) & 0xffffffff) / 4294967296
    }
}

/// mgMath.hash01：确定性噪声（同一 (n, salt) 永远同值）。
private func hanabiHash01(_ n: Double, _ salt: Double = 0) -> Double {
    let s = sin(n * 127.1 + salt * 311.7) * 43758.5453123
    return s - floor(s)
}

private func hanabiClamp01(_ v: Double) -> Double { min(1, max(0, v)) }
private func hanabiClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(hi, max(lo, v))
}
private func hanabiLerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}
private let hanabiTAU = Double.pi * 2

// MARK: - 颜色（color.ts / mgMath.ts 对译）

/// 0xRRGGBB → UIColor。
private func hanabiColor(_ hex: Int) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

private func hanabiRGB(_ hex: Int) -> (Double, Double, Double) {
    (Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255,
     Double(hex & 255) / 255)
}

private func hanabiHex(r: Double, g: Double, b: Double) -> Int {
    let c = { (v: Double) in Int((min(1, max(0, v)) * 255).rounded()) }
    return (c(r) << 16) | (c(g) << 8) | c(b)
}

private func hanabiHex(of color: UIColor, fallback: Int) -> Int {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return fallback }
    return hanabiHex(r: Double(r), g: Double(g), b: Double(b))
}

private func hanabiToHSL(r: Double, g: Double, b: Double)
    -> (h: Double, s: Double, l: Double) {
    let mx = max(r, g, b), mn = min(r, g, b)
    let l = (mx + mn) / 2
    if mx == mn { return (0, 0, l) }
    let d = mx - mn
    let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
    let h: Double
    if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
    else if mx == g { h = (b - r) / d + 2 }
    else { h = (r - g) / d + 4 }
    return (h / 6, s, l)
}

private func hanabiToRGB(h: Double, s: Double, l: Double)
    -> (Double, Double, Double) {
    if s == 0 { return (l, l, l) }
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p = 2 * l - q
    func channel(_ t0: Double) -> Double {
        var x = t0
        if x < 0 { x += 1 }
        if x > 1 { x -= 1 }
        if x < 1.0 / 6 { return p + (q - p) * 6 * x }
        if x < 1.0 / 2 { return q }
        if x < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - x) * 6 }
        return p
    }
    return (channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3))
}

private func hanabiHSL(of hex: Int) -> (h: Double, s: Double, l: Double) {
    let (r, g, b) = hanabiRGB(hex)
    return hanabiToHSL(r: r, g: g, b: b)
}

private func hanabiHexFromHSL(h: Double, s: Double, l: Double) -> Int {
    let (r, g, b) = hanabiToRGB(h: h, s: s, l: l)
    return hanabiHex(r: r, g: g, b: b)
}

/// mgMath.mixColor：0xRRGGBB 逐通道线性混合。
private func hanabiMixColor(_ a: Int, _ b: Int, _ t: Double) -> Int {
    let k = hanabiClamp01(t)
    if k <= 0 { return a }
    if k >= 1 { return b }
    let ar = Double((a >> 16) & 255)
    let ag = Double((a >> 8) & 255)
    let ab = Double(a & 255)
    let br = Double((b >> 16) & 255)
    let bg = Double((b >> 8) & 255)
    let bb = Double(b & 255)
    let r = Int((ar + (br - ar) * k).rounded())
    let g = Int((ag + (bg - ag) * k).rounded())
    let bl = Int((ab + (bb - ab) * k).rounded())
    return (r << 16) | (g << 8) | bl
}

private func hanabiMix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
    var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
    var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
    a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t,
                   blue: ab + (bb - ab) * t, alpha: aa + (ba - aa) * t)
}

private let HANABI_WHITE = 0xffffff
private let HANABI_GOLD = 0xffc760     // mgMath.GOLD
private let HANABI_EMBER = 0xff9a3c    // mgMath.EMBER

/// color.ts vivid：调成烟花色（饱和度至少 sat、亮度钳区间）。
private func hanabiVivid(_ hex: Int, sat: Double, minL: Double, maxL: Double) -> Int {
    let (h, s, l) = hanabiHSL(of: hex)
    let saturation = s < 0.05 ? s : max(s, sat)
    return hanabiHexFromHSL(h: h, s: saturation,
                            l: min(maxL, max(minL, l)))
}

private func hanabiLinear(_ v: Double) -> Double {
    v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
}

private func hanabiLuminance(_ hex: Int) -> Double {
    let (r, g, b) = hanabiRGB(hex)
    return 0.2126 * hanabiLinear(r) + 0.7152 * hanabiLinear(g)
        + 0.0722 * hanabiLinear(b)
}

private func hanabiContrast(_ a: Int, _ b: Int) -> Double {
    let la = hanabiLuminance(a), lb = hanabiLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// color.ts ensureContrast：亮度往远离 against 的方向推。
private func hanabiEnsureContrast(_ color: Int, against: Int, min ratio: Double) -> Int {
    if hanabiContrast(color, against) >= ratio { return color }
    let (h, s, l) = hanabiHSL(of: color)
    let directions: [Double] = hanabiLuminance(against) > 0.18 ? [-1, 1] : [1, -1]
    for step in 1...25 {
        for direction in directions {
            let next = hanabiHexFromHSL(
                h: h, s: s, l: hanabiClamp01(l + direction * Double(step) * 0.04))
            if hanabiContrast(next, against) >= ratio { return next }
        }
    }
    return hanabiContrast(0x000000, against) >= hanabiContrast(0xffffff, against)
        ? 0x000000 : 0xffffff
}

/// 一个镜头用的调色板（color.ts HanabiPalette，hex 域）。
private struct HanabiPaletteData {
    var ink: Int
    var paper: Int
    var blocks: [Int]
    var sparks: [Int]
    var accent: Int
    var glow: Int

    func ui(_ hex: Int) -> UIColor { hanabiColor(hex) }
}

/// color.ts ROLES：八种角色 + kawaii 的鲜艳配色（逐字照搬）。
private let HANABI_ROLES: [String: (blocks: [Int], sparks: [Int], accent: Int, glow: Int)] = [
    "night": ([0x1d2b7a, 0xd62f74, 0x5b3cc4],
              [0xffd166, 0xff6fa5, 0x7bdff2, 0xffffff, 0xb79cff], 0xffd166, 0xffe3a3),
    "festival": ([0xe60033, 0x1e50a2, 0xd9480f],
                 [0xffcc1a, 0xff3355, 0x3cc8ff, 0x6dff9a, 0xffffff], 0xffc400, 0xffa24a),
    "pastel": ([0xff9ec0, 0x8fd8ff, 0xfff08a],
               [0xffc4e1, 0xa8e8ff, 0xfff5b0, 0xd4bfff], 0xff7fb2, 0xfff0f6),
    "mono": ([0xf4f1ea, 0xc9c3b3],
             [0xffffff, 0xe8e2d0, 0xfff3d6], 0xffffff, 0xfff7e6),
    "gold": ([0xf2b01e, 0xffd970, 0xfff1c9],
             [0xffd36e, 0xffae3b, 0xfff1c1, 0xff8a3d], 0xffc94a, 0xffcf70),
    "neon": ([0xff2bd6, 0x00e5ff, 0x7a2cff],
             [0xff2bd6, 0x00f0ff, 0xb8ff1f, 0xffffff, 0x8f6bff], 0x00f0ff, 0xff6bf0),
    "sakura": ([0xff5f9e, 0xfff4f8, 0xffb8d2],
               [0xffb7d5, 0xffffff, 0xff6fae, 0xffe0ec], 0xff4f93, 0xffd6e8),
    "kawaii": ([0xff7eb6, 0x7fd8ff, 0xffe066],
               [0xffb3d9, 0xa0f0ff, 0xfff3a0, 0xd9b8ff, 0xffffff], 0xff5fa2, 0xffd1e8),
    "ocean": ([0x0a5cff, 0x00c2b8, 0xeaf6ff],
              [0x5ce1ff, 0x2bffd5, 0xffffff, 0x4d86ff], 0x5ce1ff, 0xa8f0ff),
]

private let HANABI_DARK_INK = 0x2b1f3d
private let HANABI_LIGHT_INK = 0xffffff
private let HANABI_MIN_BLOCK_CONTRAST = 3.2
private let HANABI_MIN_SUNG_CONTRAST = 3.0
private let HANABI_MIN_FLASH_CONTRAST = 2.0

/// color.ts separate：把色块亮度推到与字色对比度够。
private func hanabiSeparate(block: Int, ink: Int) -> Int {
    if hanabiContrast(block, ink) >= HANABI_MIN_BLOCK_CONTRAST { return block }
    let (h, s, l) = hanabiHSL(of: block)
    let darker = hanabiLuminance(ink) > 0.5
    for step in 1...20 {
        let next = hanabiHexFromHSL(
            h: h, s: s, l: hanabiClamp01(darker ? l - Double(step) * 0.04
                                              : l + Double(step) * 0.04))
        if hanabiContrast(next, ink) >= HANABI_MIN_BLOCK_CONTRAST { return next }
    }
    return darker ? 0x000000 : 0xffffff
}

/// 主题色 → RoleColors（color.ts themeColors）：协议
/// PaletteTokens 的 primary/accent/secondary 即主题三色。
private func hanabiThemeColors(tokens: PaletteTokens)
    -> (blocks: [Int], sparks: [Int], accent: Int, glow: Int) {
    let primary = hanabiHex(of: tokens.primary, fallback: 0xffffff)
    let accent = hanabiHex(of: tokens.accent, fallback: 0xffd166)
    let secondary = hanabiHex(of: tokens.secondary, fallback: accent)
    func spark(_ hex: Int) -> Int { hanabiVivid(hex, sat: 0.6, minL: 0.58, maxL: 0.8) }
    return (
        blocks: [hanabiVivid(accent, sat: 0.55, minL: 0.3, maxL: 0.7),
                 hanabiVivid(primary, sat: 0.45, minL: 0.25, maxL: 0.75),
                 hanabiVivid(secondary, sat: 0.5, minL: 0.3, maxL: 0.7)],
        sparks: [spark(accent), spark(primary), spark(secondary), 0xffffff],
        accent: spark(accent),
        glow: hanabiVivid(accent, sat: 0.5, minL: 0.75, maxL: 0.88))
}

/// 色相沿最短方向往 target 转 amount（color.ts mixHue）。
private func hanabiMixHue(from: Double, to: Double, amount: Double) -> Double {
    var delta = to - from
    if delta > 0.5 { delta -= 1 }
    if delta < -0.5 { delta += 1 }
    let v = (from + delta * amount).truncatingRemainder(dividingBy: 1)
    return v < 0 ? v + 1 : v
}

/// color.ts resolveHanabiPalette：role × 主题 × colorMode。
private func hanabiResolvePalette(role: String, tokens: PaletteTokens,
                                  mode: HanabiColorMode) -> HanabiPaletteData {
    let base = HANABI_ROLES[role] ?? HANABI_ROLES["night"]!
    var colors = base
    switch mode {
    case .theme:
        colors = hanabiThemeColors(tokens: tokens)
    case .vivid:
        break
    case .mixed:
        // mixed：强调色饱和度够时，第一块/第一火花用主题色、
        // 其余色相往主题强调色转 40%（color.ts mixColors）。
        let accentHex = hanabiHex(of: tokens.accent, fallback: base.accent)
        let target = hanabiHSL(of: accentHex)
        if target.s >= 0.2 {
            let themed = hanabiThemeColors(tokens: tokens)
            func lean(_ hex: Int) -> Int {
                let (h, s, l) = hanabiHSL(of: hex)
                if s < 0.05 { return hex }
                return hanabiHexFromHSL(
                    h: hanabiMixHue(from: h, to: target.h, amount: 0.4), s: s, l: l)
            }
            colors = (
                blocks: [themed.blocks[0]] + base.blocks.dropFirst().map(lean),
                sparks: [themed.sparks[0]] + base.sparks.dropFirst().map(lean),
                accent: themed.accent,
                glow: lean(base.glow))
        }
    }
    let background = hanabiHex(of: tokens.background, fallback: 0x000000)
    let paper = hanabiLuminance(background) > 0.4 ? HANABI_DARK_INK : HANABI_LIGHT_INK
    func worst(_ ink: Int) -> Double {
        colors.blocks.map { hanabiContrast($0, ink) }.min() ?? 0
    }
    let ink = worst(HANABI_DARK_INK) >= worst(HANABI_LIGHT_INK)
        ? HANABI_DARK_INK : HANABI_LIGHT_INK
    return HanabiPaletteData(
        ink: ink, paper: paper,
        blocks: colors.blocks.map { hanabiSeparate(block: $0, ink: ink) },
        sparks: colors.sparks, accent: colors.accent, glow: colors.glow)
}

/// 字后无色块时的底（color.ts hanabiBackdropOf）。
private func hanabiBackdropOf(_ palette: HanabiPaletteData) -> Int {
    hanabiLuminance(palette.paper) > 0.5 ? 0x0b0d24 : 0xf3efe9
}

/// 一个字的几种颜色（color.ts resolveHanabiGlyphColors）。
private func hanabiGlyphColors(palette: HanabiPaletteData, base: Int, under: Int)
    -> (ink: Int, sung: Int, flash: Int, back: Int) {
    let ink = hanabiEnsureContrast(base, against: under, min: HANABI_MIN_SUNG_CONTRAST)
    let candidates = [palette.accent] + palette.sparks + [palette.glow]
    let sung = candidates.first {
        hanabiContrast($0, under) >= HANABI_MIN_SUNG_CONTRAST
            && hanabiContrast($0, ink) >= 1.3
    } ?? hanabiEnsureContrast(palette.accent, against: under, min: HANABI_MIN_SUNG_CONTRAST)
    return (ink: ink, sung: sung,
            flash: hanabiEnsureContrast(palette.glow, against: under,
                                        min: HANABI_MIN_FLASH_CONTRAST),
            back: hanabiEnsureContrast(palette.sparks.first ?? palette.accent,
                                       against: under, min: HANABI_MIN_FLASH_CONTRAST))
}

// MARK: - 预设目录（catalog.ts 对译：10 族 × 5 = 50 预设全量）

private struct HanabiTextSpecData {
    var layout: String
    var heroSize: Double
    var emphasis: Double
    var tilt: Double
    var block: String
    var enter: String
    var sing: String
    var exit: String
    var stagger: Double
    var outline: Bool
    var hardShadow: Bool
}

private struct HanabiBurstSpecData {
    var kind: String
    var count: Int
    var radius: Double    // 占画面短边的比例
    var duration: Double  // 秒
    var colors: [Int]     // 调色板 sparks 下标
    var trail: Double     // 0..1
    var twinkle: Double   // 0..1
}

private struct HanabiOrnamentSpecData {
    var kind: String
    var placement: String
    var density: Double
    var scale: Double
    var color: String     // spark / accent / block / paper / glow
    var delay: Double
    var layer: String     // back / front
}

private struct HanabiRegionData {
    var cx: Double, cy: Double, w: Double, h: Double
}

private struct HanabiCameraData {
    var rise: Double, push: Double, roll: Double, punch: Double
}

private struct HanabiProfileData {
    var kind: String
    var label: String
    var family: String
    var mood: String      // quiet / neutral / loud
    var text: HanabiTextSpecData
    var region: HanabiRegionData
    var burst: HanabiBurstSpecData?
    var burstAt: String   // behind / above / sides / sky
    var sungBurst: HanabiBurstSpecData?
    var ornaments: [HanabiOrnamentSpecData]
    var launch: Bool
    var palette: String   // PaletteRole
    var camera: HanabiCameraData
}

/// catalog.ts BURST_PRESETS（各种烟花的基准参数）。
private let HANABI_BURST_PRESETS: [String: (count: Int, radius: Double,
    duration: Double, trail: Double, twinkle: Double)] = [
    "kiku": (96, 0.3, 1.9, 0.65, 0.2),
    "botan": (84, 0.26, 1.4, 0.1, 0.1),
    "yanagi": (64, 0.3, 3.2, 0.9, 0.3),
    "kamuro": (110, 0.36, 3.6, 0.95, 0.55),
    "senrin": (72, 0.22, 1.7, 0.3, 0.45),
    "ring": (60, 0.26, 1.4, 0.3, 0.1),
    "heart": (60, 0.2, 1.6, 0.2, 0.2),
    "star": (55, 0.2, 1.6, 0.2, 0.3),
    "palm": (36, 0.32, 2.3, 0.8, 0.1),
    "crossette": (40, 0.26, 1.9, 0.4, 0.2),
    "strobe": (72, 0.28, 2.3, 0.15, 1),
    "hachi": (50, 0.24, 1.6, 0.6, 0.5),
    "willow-ring": (100, 0.34, 2.8, 0.7, 0.3),
    "mine": (84, 0.5, 1.8, 0.7, 0.3),
]

/// catalog.ts burstPreset / burst / small。
private func hanabiBurstPreset(_ kind: String, _ colors: [Int] = [0, 1, 2],
                               count: Int? = nil, radius: Double? = nil,
                               duration: Double? = nil, trail: Double? = nil,
                               twinkle: Double? = nil) -> HanabiBurstSpecData {
    let base = HANABI_BURST_PRESETS[kind] ?? HANABI_BURST_PRESETS["kiku"]!
    return HanabiBurstSpecData(
        kind: kind, count: count ?? base.count, radius: radius ?? base.radius,
        duration: duration ?? base.duration, colors: colors,
        trail: trail ?? base.trail, twinkle: twinkle ?? base.twinkle)
}

private func hanabiSmallBurst(_ kind: String, _ colors: [Int],
                              count: Int = 14, radius: Double = 0.05,
                              duration: Double = 0.8, trail: Double? = nil,
                              twinkle: Double? = nil) -> HanabiBurstSpecData {
    hanabiBurstPreset(kind, colors, count: count, radius: radius,
                      duration: duration, trail: trail, twinkle: twinkle)
}

/// catalog.ts orn()。
private func hanabiOrn(_ kind: String, _ placement: String, _ layer: String,
                       density: Double = 0.6, scale: Double = 1,
                       color: String = "accent", delay: Double = 0)
    -> HanabiOrnamentSpecData {
    HanabiOrnamentSpecData(kind: kind, placement: placement, density: density,
                           scale: scale, color: color, delay: delay, layer: layer)
}

/// catalog.ts REGIONS（文字区：离画面边缘至少 6%）。
private let HANABI_REGIONS: [String: HanabiRegionData] = [
    "center": HanabiRegionData(cx: 0.5, cy: 0.5, w: 0.74, h: 0.34),
    "centerHigh": HanabiRegionData(cx: 0.5, cy: 0.45, w: 0.72, h: 0.32),
    "left": HanabiRegionData(cx: 0.42, cy: 0.56, w: 0.6, h: 0.34),
    "right": HanabiRegionData(cx: 0.58, cy: 0.46, w: 0.6, h: 0.34),
    "stagger": HanabiRegionData(cx: 0.5, cy: 0.5, w: 0.7, h: 0.46),
    "diagonal": HanabiRegionData(cx: 0.5, cy: 0.5, w: 0.74, h: 0.5),
    "scatter": HanabiRegionData(cx: 0.5, cy: 0.5, w: 0.78, h: 0.56),
    "vertical": HanabiRegionData(cx: 0.5, cy: 0.5, w: 0.34, h: 0.72),
    "verticalRight": HanabiRegionData(cx: 0.62, cy: 0.5, w: 0.3, h: 0.72),
    "verticalSplit": HanabiRegionData(cx: 0.5, cy: 0.5, w: 0.46, h: 0.72),
    "arc": HanabiRegionData(cx: 0.5, cy: 0.54, w: 0.74, h: 0.4),
    "giant": HanabiRegionData(cx: 0.5, cy: 0.5, w: 0.8, h: 0.52),
    "giantLeft": HanabiRegionData(cx: 0.44, cy: 0.52, w: 0.68, h: 0.5),
]

private let HANABI_REGION_OF_LAYOUT: [String: String] = [
    "center": "center", "left": "left", "right": "right",
    "stagger": "stagger", "diagonal": "diagonal", "scatter": "scatter",
    "vertical": "vertical", "vertical-split": "verticalSplit", "arc": "arc",
]

/// catalog.ts family() 的配方行（nil 字段 = 用族基底）。
private struct HanabiRecipe {
    var kind: String
    var label: String
    var mood: String
    var layout: String
    var block: String
    var enter: String
    var sing: String
    var exit: String
    var palette: String
    var burst: HanabiBurstSpecData?
    var ornaments: [HanabiOrnamentSpecData]
    var region: String? = nil
    var heroSize: Double? = nil
    var emphasis: Double? = nil
    var tilt: Double? = nil
    var stagger: Double? = nil
    var outline: Bool? = nil
    var hardShadow: Bool? = nil
    var burstAt: String? = nil
    var sungBurst: HanabiBurstSpecData?? = nil   // 外层 nil = 用族基底
    var launch: Bool? = nil
    var camera: HanabiCameraData? = nil          // 非 nil = 整组替换族基底分量（逐分量在配方处已合并）
    var camRise: Double? = nil
    var camPush: Double? = nil
    var camRoll: Double? = nil
    var camPunch: Double? = nil
}

private struct HanabiFamilyBase {
    var heroSize: Double
    var emphasis: Double
    var tilt: Double
    var stagger: Double
    var outline: Bool
    var hardShadow: Bool
    var burstAt: String
    var sungBurst: HanabiBurstSpecData?
    var launch: Bool
    var camera: HanabiCameraData
}

private func hanabiFamily(_ id: String, _ base: HanabiFamilyBase,
                          _ recipes: [HanabiRecipe]) -> [HanabiProfileData] {
    recipes.map { recipe in
        var camera = base.camera
        if let rise = recipe.camRise { camera.rise = rise }
        if let push = recipe.camPush { camera.push = push }
        if let roll = recipe.camRoll { camera.roll = roll }
        if let punch = recipe.camPunch { camera.punch = punch }
        let regionName = recipe.region ?? HANABI_REGION_OF_LAYOUT[recipe.layout] ?? "center"
        return HanabiProfileData(
            kind: recipe.kind, label: recipe.label, family: id, mood: recipe.mood,
            text: HanabiTextSpecData(
                layout: recipe.layout,
                heroSize: recipe.heroSize ?? base.heroSize,
                emphasis: recipe.emphasis ?? base.emphasis,
                tilt: recipe.tilt ?? base.tilt,
                block: recipe.block, enter: recipe.enter,
                sing: recipe.sing, exit: recipe.exit,
                stagger: recipe.stagger ?? base.stagger,
                outline: recipe.outline ?? base.outline,
                hardShadow: recipe.hardShadow ?? base.hardShadow),
            region: HANABI_REGIONS[regionName] ?? HANABI_REGIONS["center"]!,
            burst: recipe.burst,
            burstAt: recipe.burstAt ?? base.burstAt,
            sungBurst: recipe.sungBurst ?? base.sungBurst,
            ornaments: recipe.ornaments,
            launch: recipe.launch ?? base.launch,
            palette: recipe.palette,
            camera: camera)
    }
}

/// catalog.ts HANABI_PROFILES（50 条逐条照搬；配方注释见网页原文件）。
private let HANABI_PROFILES: [HanabiProfileData] = {
    var all: [HanabiProfileData] = []
    // 打上 uchiage
    all += hanabiFamily("uchiage", HanabiFamilyBase(
        heroSize: 0.1, emphasis: 0.45, tilt: 0, stagger: 0.045,
        outline: false, hardShadow: true, burstAt: "above", sungBurst: nil,
        launch: true, camera: HanabiCameraData(rise: 0.72, push: 0.04, roll: 0.01, punch: 0.35)), [
        HanabiRecipe(kind: "uchiage-kiku", label: "打上·菊", mood: "neutral",
            layout: "center", block: "band", enter: "rise", sing: "bounce", exit: "ascend",
            palette: "kawaii", burst: hanabiBurstPreset("kiku", [0, 1, 2]),
            ornaments: [
                hanabiOrn("streaks", "screen", "back", density: 0.5, color: "spark", delay: -0.3),
                hanabiOrn("sparkle", "glyphs", "front", density: 0.5, color: "glow"),
                hanabiOrn("ring", "behind", "back", scale: 1.1, color: "spark", delay: 0.05)]),
        HanabiRecipe(kind: "uchiage-botan", label: "打上·牡丹", mood: "loud",
            layout: "stagger", block: "pill", enter: "rise", sing: "jump", exit: "ascend",
            palette: "festival", burst: hanabiBurstPreset("botan", [0, 1, 2, 3], count: 96),
            ornaments: [
                hanabiOrn("chevrons", "line-end", "back", density: 0.7, color: "block"),
                hanabiOrn("confetti", "screen", "front", density: 0.55, color: "spark", delay: 0.1),
                hanabiOrn("dots-line", "glyphs", "back", density: 0.6, color: "paper")],
            sungBurst: .some(hanabiSmallBurst("botan", [0, 1, 2])),
            camRise: 0.8, camPunch: 0.5),
        HanabiRecipe(kind: "uchiage-palm", label: "打上·椰", mood: "neutral",
            layout: "left", block: "slant", enter: "elastic", sing: "swell", exit: "ascend",
            palette: "ocean", burst: hanabiBurstPreset("palm", [0, 1]),
            ornaments: [
                hanabiOrn("streaks", "line-start", "back", density: 0.45, color: "spark"),
                hanabiOrn("underline", "glyphs", "back", scale: 1.1, color: "block"),
                hanabiOrn("cross", "around", "front", density: 0.4, scale: 0.8, color: "paper")],
            tilt: -0.05, burstAt: "sides"),
        HanabiRecipe(kind: "uchiage-crossette", label: "打上·分裂", mood: "neutral",
            layout: "arc", block: "none", enter: "wave", sing: "flash", exit: "ascend",
            palette: "night", burst: hanabiBurstPreset("crossette", [0, 2, 3]),
            ornaments: [
                hanabiOrn("dash-circle", "behind", "back", scale: 1.2, color: "glow", delay: -0.1),
                hanabiOrn("sparkle", "glyphs", "front", density: 0.7, color: "spark"),
                hanabiOrn("streaks", "screen", "back", density: 0.35, color: "paper", delay: -0.4)],
            heroSize: 0.095, outline: true, hardShadow: false),
        HanabiRecipe(kind: "uchiage-double", label: "打上·锦", mood: "neutral",
            layout: "center", block: "double", enter: "drop", sing: "bounce", exit: "scatter",
            palette: "gold", burst: hanabiBurstPreset("willow-ring", [0, 1, 2]),
            ornaments: [
                hanabiOrn("rays", "behind", "back", density: 0.5, scale: 1.2, color: "glow", delay: 0.05),
                hanabiOrn("glints", "glyphs", "front", density: 0.6, color: "paper"),
                hanabiOrn("chevrons", "line-start", "back", density: 0.5, color: "accent")],
            burstAt: "behind", camRise: 0.65),
    ])
    // 菊 kiku
    all += hanabiFamily("kiku", HanabiFamilyBase(
        heroSize: 0.13, emphasis: 0.35, tilt: 0, stagger: 0.035,
        outline: true, hardShadow: false, burstAt: "behind", sungBurst: nil,
        launch: true, camera: HanabiCameraData(rise: 0.55, push: 0.07, roll: 0, punch: 0.5)), [
        HanabiRecipe(kind: "kiku-center", label: "菊·正面", mood: "loud",
            layout: "center", block: "none", enter: "zoom", sing: "glow", exit: "shrink",
            palette: "night", burst: hanabiBurstPreset("kiku", [0, 1, 2, 3], count: 120, radius: 0.36),
            ornaments: [
                hanabiOrn("spokes", "behind", "back", density: 0.8, scale: 1.3, color: "paper", delay: 0.05),
                hanabiOrn("ring", "behind", "back", density: 0.7, scale: 1.4, color: "spark", delay: 0.1),
                hanabiOrn("glints", "glyphs", "front", density: 0.5, color: "glow")]),
        HanabiRecipe(kind: "kiku-ring", label: "菊·輪", mood: "loud",
            layout: "center", block: "outline", enter: "burst", sing: "flash", exit: "dissolve",
            palette: "neon", burst: hanabiBurstPreset("ring", [0, 1, 2], count: 72),
            ornaments: [
                hanabiOrn("ring", "around", "back", density: 0.9, scale: 1.2, color: "accent"),
                hanabiOrn("dash-circle", "behind", "back", scale: 1.5, color: "glow", delay: -0.15),
                hanabiOrn("sparkle", "glyphs", "front", density: 0.6, color: "spark")],
            camPunch: 0.65),
        HanabiRecipe(kind: "kiku-spokes", label: "菊·集中线", mood: "neutral",
            layout: "center", block: "circle", enter: "pop", sing: "bounce", exit: "scatter",
            palette: "festival", burst: hanabiBurstPreset("kiku", [1, 2, 0]),
            ornaments: [
                hanabiOrn("spokes", "around", "back", density: 0.9, scale: 1.1, color: "block"),
                hanabiOrn("shards", "around", "front", density: 0.45, color: "spark", delay: 0.1),
                hanabiOrn("ring", "behind", "back", density: 0.5, color: "paper", delay: 0.15)],
            heroSize: 0.11, outline: false, hardShadow: true),
        HanabiRecipe(kind: "kiku-halo", label: "菊·光冠", mood: "neutral",
            layout: "arc", block: "tile", enter: "spiral", sing: "swell", exit: "ascend",
            palette: "gold", burst: hanabiBurstPreset("kamuro", [0, 1], radius: 0.32),
            ornaments: [
                hanabiOrn("dash-circle", "behind", "back", scale: 1.3, color: "accent"),
                hanabiOrn("orbit", "around", "front", density: 0.6, color: "glow"),
                hanabiOrn("glints", "glyphs", "front", density: 0.4, color: "paper")],
            heroSize: 0.1, outline: false, burstAt: "above", camPush: 0.05, camRoll: 0.012),
        HanabiRecipe(kind: "kiku-marker", label: "菊·荧光", mood: "neutral",
            layout: "right", block: "marker", enter: "wipe", sing: "underline", exit: "slide",
            palette: "ocean", burst: hanabiBurstPreset("kiku", [0, 2]),
            ornaments: [
                hanabiOrn("ring", "line-start", "back", density: 0.5, color: "spark"),
                hanabiOrn("spokes", "corners", "back", density: 0.5, scale: 0.8, color: "paper"),
                hanabiOrn("dots-line", "glyphs", "front", density: 0.6, color: "accent")],
            heroSize: 0.1, stagger: 0.05, outline: false, burstAt: "sky",
            camPush: 0.03, camPunch: 0.25),
    ])
    // 牡丹 botan
    all += hanabiFamily("botan", HanabiFamilyBase(
        heroSize: 0.11, emphasis: 0.6, tilt: 0, stagger: 0.05,
        outline: false, hardShadow: true, burstAt: "behind", sungBurst: nil,
        launch: false, camera: HanabiCameraData(rise: 0.5, push: 0.05, roll: 0, punch: 0.6)), [
        HanabiRecipe(kind: "botan-band", label: "牡丹·色带", mood: "loud",
            layout: "center", block: "band", enter: "stamp", sing: "jump", exit: "shrink",
            palette: "festival", burst: hanabiBurstPreset("botan", [0, 1, 2, 3], count: 110),
            ornaments: [
                hanabiOrn("halftone", "behind", "back", density: 0.7, scale: 1.3, color: "block"),
                hanabiOrn("confetti", "screen", "front", density: 0.6, color: "spark", delay: 0.05),
                hanabiOrn("squares", "around", "back", density: 0.5, color: "accent")],
            heroSize: 0.12, camPunch: 0.8),
        HanabiRecipe(kind: "botan-tile", label: "牡丹·方块", mood: "neutral",
            layout: "stagger", block: "tile", enter: "pop", sing: "color", exit: "scatter",
            palette: "pastel", burst: hanabiBurstPreset("botan", [1, 2, 3]),
            ornaments: [
                hanabiOrn("squares", "corners", "back", density: 0.6, color: "block"),
                hanabiOrn("confetti", "screen", "front", density: 0.4, color: "spark"),
                hanabiOrn("cross", "around", "front", density: 0.5, scale: 0.8, color: "accent")],
            sungBurst: .some(hanabiSmallBurst("botan", [0, 1, 2, 3], count: 10)),
            camPunch: 0.4),
        HanabiRecipe(kind: "botan-double", label: "牡丹·心", mood: "loud",
            layout: "left", block: "double", enter: "stamp", sing: "bounce", exit: "blink",
            palette: "sakura", burst: hanabiBurstPreset("heart", [0, 2]),
            ornaments: [
                hanabiOrn("halftone", "behind", "back", density: 0.6, color: "accent"),
                hanabiOrn("stamp", "line-end", "front", scale: 1.1, color: "accent", delay: 0.3),
                hanabiOrn("sparkle", "glyphs", "front", density: 0.5, color: "paper")],
            tilt: -0.04, burstAt: "sides"),
        HanabiRecipe(kind: "botan-split", label: "牡丹·双色", mood: "loud",
            layout: "diagonal", block: "split", enter: "flip", sing: "jump", exit: "slide",
            palette: "neon", burst: hanabiBurstPreset("botan", [0, 1]),
            ornaments: [
                hanabiOrn("shards", "around", "front", density: 0.55, color: "spark"),
                hanabiOrn("chevrons", "line-end", "back", density: 0.7, color: "block"),
                hanabiOrn("zigzag", "around", "back", density: 0.6, color: "accent")],
            tilt: -0.12, burstAt: "above", camRoll: 0.02),
        HanabiRecipe(kind: "botan-circle", label: "牡丹·丸", mood: "neutral",
            layout: "scatter", block: "circle", enter: "pop", sing: "bounce", exit: "shrink",
            palette: "pastel", burst: hanabiBurstPreset("star", [0, 1, 3]),
            ornaments: [
                hanabiOrn("cross", "screen", "back", density: 0.5, color: "paper"),
                hanabiOrn("confetti", "around", "front", density: 0.5, color: "block"),
                hanabiOrn("orbit", "around", "back", density: 0.5, color: "accent")],
            heroSize: 0.09, emphasis: 0.8, burstAt: "sky", camPunch: 0.35),
    ])
    // 柳 yanagi
    all += hanabiFamily("yanagi", HanabiFamilyBase(
        heroSize: 0.085, emphasis: 0.2, tilt: 0, stagger: 0.09,
        outline: false, hardShadow: false, burstAt: "above", sungBurst: nil,
        launch: true, camera: HanabiCameraData(rise: 0.35, push: 0.025, roll: 0.006, punch: 0)), [
        HanabiRecipe(kind: "yanagi-shidare", label: "柳·枝垂", mood: "quiet",
            layout: "vertical", block: "none", enter: "drop", sing: "glow", exit: "fall",
            palette: "night", burst: hanabiBurstPreset("yanagi", [0, 1]),
            ornaments: [
                hanabiOrn("petals", "screen", "front", density: 0.3, color: "glow", delay: 0.4),
                hanabiOrn("dots-line", "glyphs", "back", density: 0.5, scale: 0.8, color: "spark"),
                hanabiOrn("glints", "glyphs", "front", density: 0.35, color: "paper")]),
        HanabiRecipe(kind: "yanagi-kamuro", label: "柳·金冠", mood: "quiet",
            layout: "vertical-split", block: "outline", enter: "wipe", sing: "glow", exit: "fall",
            palette: "gold", burst: hanabiBurstPreset("kamuro", [0, 1, 2], duration: 4),
            ornaments: [
                hanabiOrn("brackets", "around", "back", scale: 1.05, color: "accent", delay: 0.1),
                hanabiOrn("glints", "glyphs", "front", density: 0.4, color: "glow"),
                hanabiOrn("wave", "behind", "back", density: 0.35, color: "spark")]),
        HanabiRecipe(kind: "yanagi-ame", label: "柳·雨", mood: "quiet",
            layout: "vertical", block: "marker", enter: "wave", sing: "underline", exit: "fall",
            palette: "ocean", burst: hanabiBurstPreset("willow-ring", [0, 2], count: 80),
            ornaments: [
                hanabiOrn("wave", "screen", "back", density: 0.4, color: "accent"),
                hanabiOrn("streaks", "screen", "back", density: 0.3, scale: 0.8, color: "paper"),
                hanabiOrn("dots-line", "line-end", "front", density: 0.5, color: "spark")],
            region: "verticalRight"),
        HanabiRecipe(kind: "yanagi-kaze", label: "柳·风", mood: "quiet",
            layout: "right", block: "none", enter: "drop", sing: "swell", exit: "fall",
            palette: "sakura", burst: hanabiBurstPreset("yanagi", [0, 1, 3]),
            ornaments: [
                hanabiOrn("petals", "screen", "front", density: 0.5, color: "block"),
                hanabiOrn("sparkle", "glyphs", "front", density: 0.35, color: "glow"),
                hanabiOrn("wave", "line-start", "back", density: 0.4, color: "accent")],
            heroSize: 0.08, stagger: 0.07, burstAt: "sky"),
        HanabiRecipe(kind: "yanagi-palm", label: "柳·椰影", mood: "quiet",
            layout: "vertical-split", block: "pill", enter: "rise", sing: "color", exit: "dissolve",
            palette: "kawaii", burst: hanabiBurstPreset("palm", [0, 2], duration: 2.8),
            ornaments: [
                hanabiOrn("brackets", "around", "back", color: "paper", delay: 0.1),
                hanabiOrn("petals", "screen", "front", density: 0.25, color: "spark"),
                hanabiOrn("dash-circle", "behind", "back", scale: 1.3, color: "glow")],
            burstAt: "sides"),
    ])
    // 千輪 senrin
    all += hanabiFamily("senrin", HanabiFamilyBase(
        heroSize: 0.09, emphasis: 0.7, tilt: 0, stagger: 0.03,
        outline: false, hardShadow: true, burstAt: "behind",
        sungBurst: hanabiSmallBurst("senrin", [0, 1, 2, 3], count: 16, radius: 0.06),
        launch: false, camera: HanabiCameraData(rise: 0.45, push: 0.04, roll: 0.012, punch: 0.4)), [
        HanabiRecipe(kind: "senrin-scatter", label: "千輪·散", mood: "loud",
            layout: "scatter", block: "pill", enter: "pop", sing: "jump", exit: "scatter",
            palette: "festival", burst: hanabiBurstPreset("senrin", [0, 1, 2, 3]),
            ornaments: [
                hanabiOrn("confetti", "screen", "front", density: 0.6, color: "spark"),
                hanabiOrn("cross", "around", "back", density: 0.6, color: "accent"),
                hanabiOrn("sparkle", "glyphs", "front", density: 0.5, color: "paper")]),
        HanabiRecipe(kind: "senrin-stagger", label: "千輪·阶", mood: "neutral",
            layout: "stagger", block: "tile", enter: "burst", sing: "bounce", exit: "shrink",
            palette: "neon", burst: hanabiBurstPreset("senrin", [1, 2, 3]),
            ornaments: [
                hanabiOrn("squares", "around", "back", density: 0.5, color: "block"),
                hanabiOrn("shards", "around", "front", density: 0.45, color: "spark"),
                hanabiOrn("sparkle", "glyphs", "front", density: 0.4, color: "glow")]),
        HanabiRecipe(kind: "senrin-strobe", label: "千輪·点滅", mood: "neutral",
            layout: "scatter", block: "circle", enter: "spin", sing: "flash", exit: "blink",
            palette: "pastel", burst: hanabiBurstPreset("strobe", [0, 1, 2, 3]),
            ornaments: [
                hanabiOrn("cross", "screen", "back", density: 0.5, color: "paper"),
                hanabiOrn("orbit", "around", "front", density: 0.5, color: "spark"),
                hanabiOrn("dots-line", "glyphs", "back", density: 0.5, color: "accent")],
            burstAt: "sky",
            sungBurst: .some(hanabiSmallBurst("strobe", [0, 1, 2, 3], twinkle: 1))),
        HanabiRecipe(kind: "senrin-hachi", label: "千輪·蜂", mood: "loud",
            layout: "diagonal", block: "stair", enter: "spin", sing: "shake", exit: "scatter",
            palette: "festival", burst: hanabiBurstPreset("hachi", [0, 1, 2]),
            ornaments: [
                hanabiOrn("zigzag", "around", "back", density: 0.7, color: "block"),
                hanabiOrn("confetti", "screen", "front", density: 0.5, color: "spark"),
                hanabiOrn("chevrons", "line-end", "front", density: 0.5, color: "paper")],
            tilt: -0.1, sungBurst: .some(hanabiSmallBurst("hachi", [0, 1, 2], count: 12)),
            camRoll: 0.02, camPunch: 0.55),
        HanabiRecipe(kind: "senrin-heart", label: "千輪·心", mood: "neutral",
            layout: "arc", block: "pill", enter: "pop", sing: "bounce", exit: "shrink",
            palette: "sakura", burst: hanabiBurstPreset("heart", [0, 1]),
            ornaments: [
                hanabiOrn("petals", "screen", "front", density: 0.45, color: "block"),
                hanabiOrn("confetti", "around", "front", density: 0.35, color: "spark"),
                hanabiOrn("sparkle", "glyphs", "front", density: 0.4, color: "paper")],
            burstAt: "above",
            sungBurst: .some(hanabiSmallBurst("heart", [0, 2], count: 12))),
    ])
    // 星屑 hoshikuzu
    all += hanabiFamily("hoshikuzu", HanabiFamilyBase(
        heroSize: 0.085, emphasis: 0.3, tilt: 0, stagger: 0.07,
        outline: false, hardShadow: false, burstAt: "sky",
        sungBurst: hanabiSmallBurst("star", [0, 1, 2], count: 10, radius: 0.04, duration: 1),
        launch: false, camera: HanabiCameraData(rise: 0.4, push: 0.03, roll: 0.008, punch: 0)), [
        HanabiRecipe(kind: "hoshikuzu-star", label: "星屑·星", mood: "quiet",
            layout: "center", block: "none", enter: "spiral", sing: "glow", exit: "dissolve",
            palette: "night", burst: hanabiBurstPreset("star", [0, 2]),
            ornaments: [
                hanabiOrn("sparkle", "glyphs", "front", density: 0.7, color: "glow"),
                hanabiOrn("glints", "glyphs", "front", density: 0.5, color: "paper"),
                hanabiOrn("orbit", "around", "back", density: 0.4, scale: 1.2, color: "spark")],
            burstAt: "above"),
        HanabiRecipe(kind: "hoshikuzu-orbit", label: "星屑·轨道", mood: "quiet",
            layout: "arc", block: "outline", enter: "zoom", sing: "glow", exit: "dissolve",
            palette: "ocean", burst: hanabiBurstPreset("strobe", [0, 1, 2], count: 56),
            ornaments: [
                hanabiOrn("orbit", "around", "front", density: 0.7, color: "glow"),
                hanabiOrn("dash-circle", "behind", "back", scale: 1.4, color: "accent"),
                hanabiOrn("sparkle", "around", "front", density: 0.4, color: "paper")]),
        HanabiRecipe(kind: "hoshikuzu-dust", label: "星屑·尘", mood: "quiet",
            layout: "vertical", block: "circle", enter: "wave", sing: "glow", exit: "dissolve",
            palette: "pastel", burst: hanabiBurstPreset("ring", [0, 1], count: 48, radius: 0.2),
            ornaments: [
                hanabiOrn("dots-line", "glyphs", "back", density: 0.6, color: "spark"),
                hanabiOrn("sparkle", "screen", "front", density: 0.45, color: "glow"),
                hanabiOrn("petals", "screen", "front", density: 0.2, scale: 0.7, color: "paper")],
            burstAt: "behind"),
        HanabiRecipe(kind: "hoshikuzu-line", label: "星屑·点线", mood: "quiet",
            layout: "left", block: "pill", enter: "zoom", sing: "none", exit: "dissolve",
            palette: "neon", burst: hanabiBurstPreset("crossette", [0, 1]),
            ornaments: [
                hanabiOrn("dots-line", "line-end", "back", density: 0.7, color: "accent"),
                hanabiOrn("glints", "glyphs", "front", density: 0.5, color: "glow"),
                hanabiOrn("cross", "corners", "back", density: 0.4, color: "paper")]),
        HanabiRecipe(kind: "hoshikuzu-veil", label: "星屑·纱", mood: "quiet",
            layout: "stagger", block: "none", enter: "spiral", sing: "color", exit: "ascend",
            palette: "sakura", burst: hanabiBurstPreset("kamuro", [0, 1, 3], count: 90),
            ornaments: [
                hanabiOrn("sparkle", "glyphs", "front", density: 0.6, color: "glow"),
                hanabiOrn("wave", "behind", "back", density: 0.4, color: "accent"),
                hanabiOrn("orbit", "around", "back", density: 0.35, color: "spark")]),
    ])
    // 帯 obi
    all += hanabiFamily("obi", HanabiFamilyBase(
        heroSize: 0.09, emphasis: 0.4, tilt: 0, stagger: 0.04,
        outline: false, hardShadow: false, burstAt: "sides", sungBurst: nil,
        launch: false, camera: HanabiCameraData(rise: 0.5, push: 0.02, roll: 0, punch: 0.2)), [
        HanabiRecipe(kind: "obi-band", label: "帯·横带", mood: "neutral",
            layout: "left", block: "band", enter: "wipe", sing: "underline", exit: "slide",
            palette: "festival", burst: hanabiBurstPreset("ring", [0, 1]),
            ornaments: [
                hanabiOrn("zigzag", "line-end", "back", density: 0.6, color: "block"),
                hanabiOrn("chevrons", "line-start", "back", density: 0.5, color: "accent"),
                hanabiOrn("underline", "glyphs", "front", color: "paper")]),
        HanabiRecipe(kind: "obi-ticket", label: "帯·票据", mood: "neutral",
            layout: "center", block: "ticket", enter: "flip", sing: "color", exit: "slide",
            palette: "pastel", burst: hanabiBurstPreset("botan", [0, 2], count: 64),
            ornaments: [
                hanabiOrn("brackets", "around", "back", color: "accent"),
                hanabiOrn("dots-line", "line-end", "back", density: 0.5, color: "paper"),
                hanabiOrn("stamp", "line-start", "front", scale: 0.9, color: "accent", delay: 0.35)],
            burstAt: "above"),
        HanabiRecipe(kind: "obi-slant", label: "帯·斜块", mood: "loud",
            layout: "diagonal", block: "slant", enter: "wipe", sing: "underline", exit: "slide",
            palette: "neon", burst: hanabiBurstPreset("palm", [0, 1, 2]),
            ornaments: [
                hanabiOrn("chevrons", "line-end", "front", density: 0.7, color: "spark"),
                hanabiOrn("streaks", "screen", "back", density: 0.5, color: "paper"),
                hanabiOrn("zigzag", "around", "back", density: 0.5, color: "block")],
            tilt: -0.14, hardShadow: true, camPunch: 0.45),
        HanabiRecipe(kind: "obi-marker", label: "帯·荧光笔", mood: "neutral",
            layout: "stagger", block: "marker", enter: "type", sing: "underline", exit: "blink",
            palette: "ocean", burst: hanabiBurstPreset("star", [0, 1]),
            ornaments: [
                hanabiOrn("underline", "glyphs", "back", scale: 1.2, color: "accent"),
                hanabiOrn("squares", "corners", "back", density: 0.5, color: "block"),
                hanabiOrn("brackets", "around", "front", scale: 1.1, color: "paper")],
            burstAt: "sky"),
        HanabiRecipe(kind: "obi-stair", label: "帯·阶梯", mood: "neutral",
            layout: "right", block: "stair", enter: "stretch", sing: "jump", exit: "slide",
            palette: "gold", burst: hanabiBurstPreset("crossette", [0, 1, 3]),
            ornaments: [
                hanabiOrn("squares", "around", "back", density: 0.55, color: "accent"),
                hanabiOrn("halftone", "behind", "back", density: 0.5, color: "block"),
                hanabiOrn("chevrons", "line-start", "front", density: 0.5, color: "paper")],
            hardShadow: true),
    ])
    // 閃光 senko
    all += hanabiFamily("senko", HanabiFamilyBase(
        heroSize: 0.1, emphasis: 0.5, tilt: 0, stagger: 0.025,
        outline: false, hardShadow: true, burstAt: "behind", sungBurst: nil,
        launch: false, camera: HanabiCameraData(rise: 0.6, push: 0.06, roll: 0.015, punch: 0.7)), [
        HanabiRecipe(kind: "senko-glitch", label: "閃光·故障", mood: "loud",
            layout: "center", block: "split", enter: "glitch", sing: "shake", exit: "blink",
            palette: "neon", burst: hanabiBurstPreset("strobe", [0, 1, 2, 3]),
            ornaments: [
                hanabiOrn("streaks", "screen", "back", density: 0.7, color: "spark"),
                hanabiOrn("shards", "around", "front", density: 0.5, color: "block"),
                hanabiOrn("squares", "around", "back", density: 0.5, color: "paper")]),
        HanabiRecipe(kind: "senko-scramble", label: "閃光·乱码", mood: "neutral",
            layout: "left", block: "outline", enter: "scramble", sing: "flash", exit: "blink",
            palette: "mono", burst: hanabiBurstPreset("hachi", [0, 1]),
            ornaments: [
                hanabiOrn("brackets", "around", "back", color: "paper"),
                hanabiOrn("cross", "corners", "front", density: 0.5, color: "accent"),
                hanabiOrn("streaks", "line-end", "back", density: 0.5, color: "glow")],
            outline: true, hardShadow: false, burstAt: "sides", camPunch: 0.4),
        HanabiRecipe(kind: "senko-strobe", label: "閃光·频闪", mood: "loud",
            layout: "scatter", block: "tile", enter: "glitch", sing: "flash", exit: "scatter",
            palette: "kawaii", burst: hanabiBurstPreset("mine", [0, 1, 2]),
            ornaments: [
                hanabiOrn("streaks", "screen", "back", density: 0.8, color: "paper"),
                hanabiOrn("zigzag", "around", "front", density: 0.5, color: "accent"),
                hanabiOrn("glints", "glyphs", "front", density: 0.5, color: "glow")],
            burstAt: "sky",
            sungBurst: .some(hanabiSmallBurst("strobe", [0, 1], count: 10, twinkle: 1))),
        HanabiRecipe(kind: "senko-stretch", label: "閃光·拉伸", mood: "loud",
            layout: "center", block: "slant", enter: "stretch", sing: "shake", exit: "shrink",
            palette: "neon", burst: hanabiBurstPreset("crossette", [0, 2, 3]),
            ornaments: [
                hanabiOrn("spokes", "around", "back", density: 0.8, color: "paper"),
                hanabiOrn("streaks", "screen", "front", density: 0.5, color: "spark"),
                hanabiOrn("shards", "around", "back", density: 0.4, color: "block")],
            tilt: -0.06),
        HanabiRecipe(kind: "senko-type", label: "閃光·打字", mood: "neutral",
            layout: "right", block: "ticket", enter: "scramble", sing: "none", exit: "blink",
            palette: "mono", burst: hanabiBurstPreset("ring", [0, 1], count: 48),
            ornaments: [
                hanabiOrn("dots-line", "line-start", "back", density: 0.6, color: "paper"),
                hanabiOrn("brackets", "around", "front", scale: 1.08, color: "accent"),
                hanabiOrn("cross", "screen", "back", density: 0.35, color: "glow")],
            burstAt: "above", camRoll: 0, camPunch: 0.3),
    ])
    // 線香 senkohanabi
    all += hanabiFamily("senkohanabi", HanabiFamilyBase(
        heroSize: 0.08, emphasis: 0.2, tilt: 0, stagger: 0.08,
        outline: false, hardShadow: false, burstAt: "behind",
        sungBurst: hanabiSmallBurst("hachi", [0, 1], count: 12, radius: 0.035,
                                    duration: 0.6, trail: 0.4, twinkle: 0.8),
        launch: false, camera: HanabiCameraData(rise: 0.3, push: 0.02, roll: 0.004, punch: 0)), [
        HanabiRecipe(kind: "senkohanabi-hachi", label: "線香·火花", mood: "quiet",
            layout: "vertical", block: "none", enter: "type", sing: "glow", exit: "fall",
            palette: "gold", burst: hanabiBurstPreset("hachi", [0, 1], count: 36, radius: 0.14),
            ornaments: [
                hanabiOrn("glints", "glyphs", "front", density: 0.6, color: "spark"),
                hanabiOrn("sparkle", "glyphs", "front", density: 0.35, scale: 0.7, color: "glow"),
                hanabiOrn("dots-line", "glyphs", "back", density: 0.4, scale: 0.7, color: "accent")],
            region: "verticalRight"),
        HanabiRecipe(kind: "senkohanabi-tama", label: "線香·火玉", mood: "quiet",
            layout: "center", block: "none", enter: "split", sing: "glow", exit: "dissolve",
            palette: "night", burst: hanabiBurstPreset("botan", [0, 1], count: 40, radius: 0.12, duration: 1.2),
            ornaments: [
                hanabiOrn("glints", "glyphs", "front", density: 0.5, color: "spark"),
                hanabiOrn("sparkle", "around", "front", density: 0.3, scale: 0.7, color: "glow")],
            heroSize: 0.085, burstAt: "above"),
        HanabiRecipe(kind: "senkohanabi-matsuba", label: "線香·松葉", mood: "quiet",
            layout: "left", block: "circle", enter: "elastic", sing: "swell", exit: "dissolve",
            palette: "gold", burst: hanabiBurstPreset("crossette", [0, 1], count: 28, radius: 0.15),
            ornaments: [
                hanabiOrn("sparkle", "glyphs", "front", density: 0.45, color: "spark"),
                hanabiOrn("cross", "around", "back", density: 0.35, scale: 0.7, color: "glow")],
            burstAt: "sides"),
        HanabiRecipe(kind: "senkohanabi-chiri", label: "線香·散菊", mood: "quiet",
            layout: "arc", block: "marker", enter: "flip", sing: "underline", exit: "fall",
            palette: "sakura", burst: hanabiBurstPreset("yanagi", [0, 1], count: 40, radius: 0.18),
            ornaments: [
                hanabiOrn("petals", "screen", "front", density: 0.35, color: "block"),
                hanabiOrn("glints", "glyphs", "front", density: 0.4, color: "paper")],
            burstAt: "above"),
        HanabiRecipe(kind: "senkohanabi-tsubomi", label: "線香·蕾", mood: "quiet",
            layout: "vertical-split", block: "none", enter: "split", sing: "glow", exit: "fall",
            palette: "kawaii", burst: hanabiBurstPreset("strobe", [0, 1], count: 30, radius: 0.14),
            ornaments: [
                hanabiOrn("dots-line", "glyphs", "back", density: 0.5, color: "spark"),
                hanabiOrn("glints", "glyphs", "front", density: 0.5, color: "glow"),
                hanabiOrn("dash-circle", "behind", "back", density: 0.4, scale: 0.9, color: "paper")]),
    ])
    // 尺玉 shakudama
    all += hanabiFamily("shakudama", HanabiFamilyBase(
        heroSize: 0.19, emphasis: 0.25, tilt: 0, stagger: 0.06,
        outline: true, hardShadow: true, burstAt: "behind", sungBurst: nil,
        launch: true, camera: HanabiCameraData(rise: 0.85, push: 0.09, roll: 0, punch: 0.9)), [
        HanabiRecipe(kind: "shakudama-kamuro", label: "尺玉·金冠", mood: "loud",
            layout: "center", block: "none", enter: "stamp", sing: "none", exit: "shrink",
            palette: "gold", burst: hanabiBurstPreset("kamuro", [0, 1, 2], count: 160, radius: 0.48, duration: 4.2),
            ornaments: [
                hanabiOrn("rays", "behind", "back", density: 0.8, scale: 1.5, color: "glow"),
                hanabiOrn("ring", "behind", "back", density: 0.6, scale: 1.6, color: "accent", delay: 0.1),
                hanabiOrn("spokes", "around", "front", density: 0.5, scale: 1.3, color: "paper")],
            region: "giant"),
        HanabiRecipe(kind: "shakudama-nishiki", label: "尺玉·锦", mood: "loud",
            layout: "center", block: "double", enter: "zoom", sing: "swell", exit: "scatter",
            palette: "festival", burst: hanabiBurstPreset("willow-ring", [0, 1, 2, 3], count: 150, radius: 0.46),
            ornaments: [
                hanabiOrn("rays", "behind", "back", density: 0.6, scale: 1.4, color: "block"),
                hanabiOrn("stamp", "line-end", "front", scale: 1.2, color: "accent", delay: 0.4),
                hanabiOrn("ring", "around", "back", density: 0.7, scale: 1.3, color: "spark")],
            region: "giant", heroSize: 0.17),
        HanabiRecipe(kind: "shakudama-asahi", label: "尺玉·旭日", mood: "loud",
            layout: "center", block: "circle", enter: "burst", sing: "flash", exit: "shrink",
            palette: "festival", burst: hanabiBurstPreset("kamuro", [1, 0], count: 140, radius: 0.44),
            ornaments: [
                hanabiOrn("rays", "behind", "back", density: 0.9, scale: 1.6, color: "block"),
                hanabiOrn("spokes", "behind", "back", density: 0.6, scale: 1.4, color: "paper"),
                hanabiOrn("confetti", "screen", "front", density: 0.5, color: "spark", delay: 0.2)],
            region: "giant"),
        HanabiRecipe(kind: "shakudama-heart", label: "尺玉·心", mood: "loud",
            layout: "center", block: "tile", enter: "stretch", sing: "jump", exit: "scatter",
            palette: "sakura", burst: hanabiBurstPreset("heart", [0, 1, 3], count: 110, radius: 0.36),
            ornaments: [
                hanabiOrn("stamp", "line-start", "front", scale: 1.3, color: "accent", delay: 0.3),
                hanabiOrn("rays", "behind", "back", density: 0.5, scale: 1.3, color: "glow"),
                hanabiOrn("confetti", "screen", "front", density: 0.55, color: "block")],
            region: "giant", heroSize: 0.17),
        HanabiRecipe(kind: "shakudama-mine", label: "尺玉·速射", mood: "loud",
            layout: "left", block: "split", enter: "stamp", sing: "shake", exit: "scatter",
            palette: "neon", burst: hanabiBurstPreset("mine", [0, 1, 2, 3], count: 120),
            ornaments: [
                hanabiOrn("streaks", "screen", "back", density: 0.8, color: "spark"),
                hanabiOrn("shards", "around", "front", density: 0.6, color: "block"),
                hanabiOrn("rays", "behind", "back", density: 0.5, scale: 1.3, color: "accent")],
            region: "giantLeft", heroSize: 0.16, tilt: -0.05, burstAt: "sky"),
    ])
    return all
}()

private let HANABI_PROFILES_BY_KIND: [String: HanabiProfileData] = {
    var map: [String: HanabiProfileData] = [:]
    for profile in HANABI_PROFILES { map[profile.kind] = profile }
    return map
}()

/// catalog.ts profileOf：未知 kind 退回「打上·菊」。
private func hanabiProfileOf(_ kind: String) -> HanabiProfileData {
    HANABI_PROFILES_BY_KIND[kind] ?? HANABI_PROFILES[0]
}

// MARK: - 烟花解析模型（mg/burstPlan.ts 对译）
//
// 一颗星在任意时刻的位置/亮度/颜色都由闭式解算出：
// p(τ) = p0 + v0·(1−e^{−kτ})/k + vt·(τ − (1−e^{−kτ})/k)。
// seek 到哪一刻结果都一样；按精灵池上限以 rank 等比例抽稀。

private struct HanabiStarPlan {
    var x0: Double, y0: Double
    var vx: Double, vy: Double
    var drag: Double
    var fall: Double
    var start: Double
    var life: Double
    var size: Double
    var color: Int
    var endColor: Int
    var shift: Double
    var trailColor: Int
    var trail: Double
    var segments: Int
    var fadeTail: Double
    var strobe: Double
    var strobeFrom: Double
    var twinkle: Double
    var glitter: Double
    var spiral: Double
    var spin: Double
    var phase: Double
    var depth: Double
    var rank: Double
    var tex: Int   // 0 = 柔光点，1 = 四角星
}

private struct HanabiFlashPlan {
    var x: Double, y: Double, at: Double
    var size: Double
    var color: Int
    var life: Double
}

private struct HanabiBurstPlan {
    var at: Double
    var end: Double
    var stars: [HanabiStarPlan]
    var flashes: [HanabiFlashPlan]
}

private struct HanabiBurstEvent {
    var x: Double, y: Double
    var at: Double
    var spec: HanabiBurstSpecData
    var seed: String
    var scale: Double
    var squash: Double = 1
    var rotation: Double = 0
}

private struct HanabiLaunchEvent {
    var fromX: Double, fromY: Double
    var toX: Double, toY: Double
    var at: Double
    var duration: Double
    var color: Int
    var seed: String
}

private func hanabiSparkColor(palette: HanabiPaletteData,
                              colors: [Int], i: Int) -> Int {
    let sparks = palette.sparks.isEmpty ? [HANABI_WHITE] : palette.sparks
    let n = sparks.count
    let index = colors.isEmpty ? i : colors[((i % colors.count) + colors.count) % colors.count]
    return sparks[((Int(Double(index).rounded()) % n) + n) % n]
}

/// burstPlan.ts planBurst：一个 BurstEvent 展开成星组参数。
private func hanabiPlanBurst(event: HanabiBurstEvent, palette: HanabiPaletteData,
                             unit: Double, amount: Double) -> HanabiBurstPlan {
    let spec = event.spec
    let kind = spec.kind
    var rng = HanabiRng(key: "\(event.seed):\(kind)")
    let R = max(4, spec.radius * unit * (event.scale == 0 ? 1 : event.scale))
    let D = max(0.2, spec.duration)
    let at = event.at
    let n = max(0, Int((Double(spec.count) * max(0, amount)).rounded()))
    let trailK = hanabiClamp01(spec.trail)
    let twinkleK = hanabiClamp01(spec.twinkle)
    let squash = event.squash
    let rotation = event.rotation
    let cosR = cos(rotation), sinR = sin(rotation)
    func c(_ i: Int) -> Int { hanabiSparkColor(palette: palette, colors: spec.colors, i: i) }
    var stars: [HanabiStarPlan] = []
    var flashes: [HanabiFlashPlan] = []
    let minSize = max(1.4, unit * 0.0022)

    struct StarInput {
        var x0: Double = 0, y0: Double = 0
        var vx: Double, vy: Double
        var drag: Double
        var fall: Double = 0
        var start: Double = 0
        var life: Double
        var size: Double
        var color: Int
        var endColor: Int? = nil
        var shift: Double = 1
        var trailColor: Int? = nil
        var trail: Double = 0
        var segments: Int? = nil
        var fadeTail: Double = 0.3
        var strobe: Double = 0
        var strobeFrom: Double = 0
        var twinkle: Double = 0
        var glitter: Double = 0
        var spiral: Double = 0
        var spin: Double = 0
        var phase: Double? = nil
        var depth: Double = 1
        var tex: Int = 0
    }

    func add(_ input: StarInput) {
        let delay = input.start
        let life = min(input.life, D - delay - 0.02)
        if life <= 0.05 { return }
        stars.append(HanabiStarPlan(
            x0: event.x + input.x0, y0: event.y + input.y0,
            vx: input.vx, vy: input.vy, drag: input.drag,
            fall: input.fall, start: at + delay, life: life,
            size: max(minSize, input.size), color: input.color,
            endColor: input.endColor ?? input.color, shift: input.shift,
            trailColor: input.trailColor
                ?? hanabiMixColor(input.color, HANABI_EMBER, 0.3),
            trail: input.trail,
            segments: input.trail > 0 ? max(1, input.segments ?? 3) : 0,
            fadeTail: input.fadeTail, strobe: input.strobe,
            strobeFrom: input.strobeFrom, twinkle: input.twinkle,
            glitter: input.glitter, spiral: input.spiral, spin: input.spin,
            phase: input.phase ?? rng.next() * hanabiTAU,
            depth: input.depth, rank: 0, tex: input.tex))
    }

    func flash(_ x: Double, _ y: Double, _ delay: Double,
               _ size: Double, _ color: Int, _ life: Double = 0.32) {
        if delay >= D { return }
        flashes.append(HanabiFlashPlan(
            x: event.x + x, y: event.y + y, at: at + delay, size: size,
            color: hanabiMixColor(color, HANABI_WHITE, 0.7),
            life: min(life, D - delay)))
    }

    // 球面均匀方向（斐波那契球 + 随机倾斜 + 抖动）。
    let tiltA = rng.next() * hanabiTAU
    let tiltCos = cos(tiltA), tiltSin = sin(tiltA)
    func sphere(_ i: Int, _ count: Int, _ jitter: Double = 0.25)
        -> (Double, Double, Double) {
        let z = 1 - (2 * (Double(i) + 0.5)) / Double(max(count, 1))
        let r = sqrt(max(0, 1 - z * z))
        let phi = Double(i) * 2.399963229728653 + (rng.next() - 0.5) * jitter
        let x = r * cos(phi)
        let y0 = r * sin(phi)
        return (x, y0 * tiltCos - z * tiltSin, y0 * tiltSin + z * tiltCos)
    }
    func planar(_ x: Double, _ y: Double) -> (Double, Double) {
        let sy = y * squash
        return (x * cosR - sy * sinR, x * sinR + sy * cosR)
    }
    func depthOf(_ z: Double) -> Double { 0.62 + 0.38 * (z + 1) / 2 }
    func lifeFrac(_ low: Double, _ high: Double) -> Double {
        D * hanabiLerp(low, high, rng.next())
    }

    let c0 = c(0), c1 = c(1), c2 = c(2)

    switch kind {
    case "kiku":
        let core = Int((Double(n) * 0.2).rounded())
        let main = n - core
        let k = 3.2
        for i in 0..<main {
            let (dx, dy, dz) = sphere(i, main)
            let speed = R * k * (0.94 + rng.next() * 0.12)
            add(StarInput(vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.3,
                life: lifeFrac(0.78, 0.98), size: R * 0.02, color: c0,
                endColor: hanabiMixColor(c0, HANABI_WHITE, 0.65), shift: 0.7,
                trailColor: hanabiMixColor(c0, HANABI_EMBER, 0.3),
                trail: 0.1 + trailK * 0.38, segments: 3,
                twinkle: twinkleK, depth: depthOf(dz)))
        }
        for i in 0..<core {
            let (dx, dy, dz) = sphere(i, core)
            let speed = R * 3.6 * 0.42 * (0.95 + rng.next() * 0.1)
            add(StarInput(vx: dx * speed, vy: dy * speed, drag: 3.6, fall: R * 0.2,
                life: lifeFrac(0.4, 0.55), size: R * 0.017, color: c1,
                trail: 0.04 + trailK * 0.08, segments: 1,
                fadeTail: 0.2, depth: depthOf(dz)))
        }
        flash(0, 0, 0, R * 1.1, c0, 0.36)
    case "botan":
        let core = Int((Double(n) * 0.22).rounded())
        let main = n - core
        let k = 3.6
        for i in 0..<main {
            let (dx, dy, dz) = sphere(i, main, 0.12)
            let speed = R * k * (0.97 + rng.next() * 0.06)
            add(StarInput(vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.24,
                life: lifeFrac(0.85, 0.97), size: R * 0.034, color: c0,
                endColor: c1, shift: 0.48, fadeTail: 0.12,
                twinkle: twinkleK * 0.6, depth: depthOf(dz)))
        }
        for i in 0..<core {
            let (dx, dy, dz) = sphere(i, core, 0.12)
            let speed = R * k * 0.5
            add(StarInput(vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.2,
                life: lifeFrac(0.6, 0.72), size: R * 0.03, color: c2,
                endColor: hanabiMixColor(c2, HANABI_WHITE, 0.5), shift: 0.55,
                fadeTail: 0.12, depth: depthOf(dz)))
        }
        flash(0, 0, 0, R * 1.2, c0, 0.3)
    case "yanagi":
        let k = 2.5
        let gold = hanabiMixColor(c0, HANABI_GOLD, 0.6)
        for i in 0..<n {
            let (dx, dy, dz) = sphere(i, n, 0.4)
            let speed = R * k * 0.72 * (0.9 + rng.next() * 0.2)
            add(StarInput(vx: dx * speed, vy: dy * speed - R * 0.25, drag: k,
                fall: R * 0.95, life: lifeFrac(0.88, 0.99), size: R * 0.013,
                color: gold, endColor: hanabiMixColor(gold, HANABI_EMBER, 0.6),
                shift: 0.6, trailColor: hanabiMixColor(gold, HANABI_EMBER, 0.35),
                trail: 0.35 + trailK * 0.95, segments: 4, fadeTail: 0.45,
                glitter: 0.25 + twinkleK * 0.5, depth: depthOf(dz) * 0.9))
        }
        flash(0, 0, 0, R * 0.8, gold, 0.3)
    case "kamuro":
        let k = 3.0
        let gold = hanabiMixColor(c0, HANABI_GOLD, 0.78)
        for i in 0..<n {
            let (dx, dy, dz) = sphere(i, n, 0.2)
            let speed = R * k * 1.05 * (0.95 + rng.next() * 0.1)
            add(StarInput(vx: dx * speed, vy: dy * speed - R * 0.12, drag: k,
                fall: R * 0.55, life: lifeFrac(0.9, 0.99), size: R * 0.017,
                color: gold, endColor: hanabiMixColor(gold, HANABI_EMBER, 0.5),
                shift: 0.55, trailColor: hanabiMixColor(gold, HANABI_EMBER, 0.25),
                trail: 0.45 + trailK * 0.8, segments: 4, fadeTail: 0.5,
                glitter: 0.55 + twinkleK * 0.45, depth: depthOf(dz)))
        }
        flash(0, 0, 0, R * 1.3, gold, 0.42)
    case "senrin":
        let flowers = max(4, min(10, Int((Double(n) / 14).rounded())))
        let per = max(6, Int((Double(n) / Double(flowers)).rounded()))
        let k = 4.4
        for f in 0..<flowers {
            let angle = Double(f) * 2.399963229728653 + rng.next() * 0.6
            let dist = R * 0.78 * sqrt((Double(f) + 0.5) / Double(flowers))
            let ox = cos(angle) * dist, oy = sin(angle) * dist
            let delay = 0.06 + (Double(f) / Double(flowers)) * D * 0.42 + rng.next() * 0.05
            let r = R * (0.2 + rng.next() * 0.08)
            let color = c(f)
            for i in 0..<per {
                let (dx, dy, dz) = sphere(i, per, 0.3)
                let speed = r * k * (0.92 + rng.next() * 0.16)
                add(StarInput(x0: ox, y0: oy, vx: dx * speed, vy: dy * speed,
                    drag: k, fall: R * 0.16, start: delay,
                    life: D * (0.32 + rng.next() * 0.12), size: R * 0.017,
                    color: color, endColor: hanabiMixColor(color, HANABI_WHITE, 0.6),
                    shift: 0.65, trail: trailK * 0.08, segments: 1,
                    fadeTail: 0.25, twinkle: 0.3 + twinkleK * 0.7, depth: depthOf(dz)))
            }
            flash(ox, oy, delay, r * 1.4, color, 0.22)
        }
    case "ring":
        let k = 3.4
        let outer = Int((Double(n) * 0.7).rounded())
        let inner = Int((Double(n) * 0.2).rounded())
        let core = n - outer - inner
        func ringOf(_ count: Int, _ reach: Double, _ color: Int,
                    _ size: Double, _ lifeLow: Double) {
            for i in 0..<count {
                let (dx, dy) = planar(cos(hanabiTAU * Double(i) / Double(max(count, 1))),
                                      sin(hanabiTAU * Double(i) / Double(max(count, 1))))
                let speed = R * k * reach * (0.99 + rng.next() * 0.02)
                add(StarInput(vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.18,
                    life: lifeFrac(lifeLow, lifeLow + 0.12), size: size, color: color,
                    endColor: hanabiMixColor(color, HANABI_WHITE, 0.5), shift: 0.75,
                    trail: 0.05 + trailK * 0.2, segments: 2, twinkle: twinkleK))
            }
        }
        ringOf(outer, 1, c0, R * 0.022, 0.85)
        ringOf(inner, 0.58, c1, R * 0.018, 0.7)
        for i in 0..<core {
            let (dx, dy, dz) = sphere(i, max(1, core))
            let speed = R * k * 0.18
            add(StarInput(vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.15,
                life: lifeFrac(0.45, 0.6), size: R * 0.02, color: c2, depth: depthOf(dz)))
        }
        flash(0, 0, 0, R * 0.9, c0, 0.3)
    case "heart", "star":
        let k = 3.4
        let outline = max(12, Int((Double(n) * 0.88).rounded()))
        for i in 0..<outline {
            let u = Double(i) / Double(outline)
            var x = 0.0, y = 0.0
            if kind == "heart" {
                let t = u * hanabiTAU
                x = (16 * pow(sin(t), 3)) / 17
                y = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) / 17
            } else {
                let edge = u * 10
                let e = Int(floor(edge))
                let f = edge - Double(e)
                func vertex(_ index: Int) -> (Double, Double) {
                    let radius = index % 2 == 0 ? 1.0 : 0.4
                    let a = -Double.pi / 2 + Double(index) * Double.pi / 5
                    return (cos(a) * radius, sin(a) * radius)
                }
                let (ax, ay) = vertex(e)
                let (bx, by) = vertex(e + 1)
                x = hanabiLerp(ax, bx, f)
                y = hanabiLerp(ay, by, f)
            }
            let (dx, dy) = planar(x, y)
            let speed = R * k * (0.99 + rng.next() * 0.02)
            add(StarInput(vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.1,
                life: lifeFrac(0.8, 0.92), size: R * 0.024, color: c0,
                endColor: hanabiMixColor(c0, HANABI_WHITE, 0.55), shift: 0.7,
                trail: 0.04 + trailK * 0.1, segments: 1, fadeTail: 0.25,
                twinkle: twinkleK))
        }
        let core = n - outline
        for i in 0..<core {
            let (dx, dy, dz) = sphere(i, max(1, core))
            let speed = R * k * 0.15
            add(StarInput(vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.1,
                life: lifeFrac(0.4, 0.55), size: R * 0.018, color: c1, depth: depthOf(dz)))
        }
        flash(0, 0, 0, R * 0.8, c0, 0.28)
    case "palm":
        let branches = max(6, min(14, Int((Double(n) / 9).rounded())))
        let crumbs = max(0, min(6, (n - branches) / max(branches, 1)))
        let k = 2.3
        let gold = hanabiMixColor(c0, HANABI_GOLD, 0.45)
        for b in 0..<branches {
            let angle = hanabiTAU * Double(b) / Double(branches) + (rng.next() - 0.5) * 0.35
            let up = -sin(angle)
            let reach = 1 + up * 0.15 + (rng.next() - 0.5) * 0.1
            let dx = cos(angle), dy = sin(angle)
            let speed = R * k * reach
            add(StarInput(vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.7,
                life: lifeFrac(0.88, 0.98), size: R * 0.05, color: gold,
                endColor: hanabiMixColor(gold, HANABI_EMBER, 0.55), shift: 0.55,
                trailColor: hanabiMixColor(gold, HANABI_EMBER, 0.3),
                trail: 0.4 + trailK * 0.55, segments: 5, fadeTail: 0.4,
                glitter: 0.3 + twinkleK * 0.4))
            for j in 0..<crumbs {
                let f = 0.9 - Double(j) * 0.1
                add(StarInput(
                    vx: dx * speed * f + (rng.next() - 0.5) * R * 0.3,
                    vy: dy * speed * f + (rng.next() - 0.5) * R * 0.3,
                    drag: k, fall: R * 0.75, life: lifeFrac(0.55, 0.85),
                    size: R * 0.014, color: hanabiMixColor(gold, HANABI_WHITE, 0.3),
                    trail: 0.08, segments: 1, fadeTail: 0.5, glitter: 0.8))
            }
        }
        flash(0, 0, 0, R * 1.0, gold, 0.4)
    case "crossette":
        let parents = max(6, min(16, Int((Double(n) / 5).rounded())))
        let k = 2.8, kc = 3.4
        let fall = R * 0.32
        for p in 0..<parents {
            let angle = hanabiTAU * Double(p) / Double(parents) + (rng.next() - 0.5) * 0.4
            let speed = R * k * 0.72 * (0.9 + rng.next() * 0.2)
            let vx = cos(angle) * speed, vy = sin(angle) * speed
            let split = D * (0.28 + rng.next() * 0.08)
            add(StarInput(vx: vx, vy: vy, drag: k, fall: fall, life: split,
                size: R * 0.024, color: c0, trail: 0.08 + trailK * 0.2,
                segments: 2, fadeTail: 0.05))
            let e = exp(-k * split)
            let f = (1 - e) / k
            let sx = vx * f
            let sy = vy * f + fall * (split - f)
            let svx = vx * e
            let svy = (vy - fall) * e + fall
            let turn = angle + Double.pi / 4 + (rng.next() - 0.5) * 0.3
            for q in 0..<4 {
                let a = turn + Double(q) * Double.pi / 2
                let cs = R * kc * 0.36
                add(StarInput(x0: sx, y0: sy,
                    vx: svx * 0.35 + cos(a) * cs, vy: svy * 0.35 + sin(a) * cs,
                    drag: kc, fall: R * 0.38, start: split,
                    life: D * (0.45 + rng.next() * 0.12), size: R * 0.018,
                    color: c1, endColor: hanabiMixColor(c1, HANABI_WHITE, 0.5),
                    shift: 0.7, trail: 0.06 + trailK * 0.18, segments: 2,
                    twinkle: twinkleK))
            }
            flash(sx, sy, split, R * 0.2, c1, 0.16)
        }
        flash(0, 0, 0, R * 0.8, c0, 0.3)
    case "strobe":
        let k = 4.0
        let white = hanabiMixColor(c0, HANABI_WHITE, 0.55)
        for i in 0..<n {
            let (dx, dy, dz) = sphere(i, n, 0.6)
            let speed = R * k * 0.88 * (0.8 + rng.next() * 0.3)
            add(StarInput(vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.12,
                life: lifeFrac(0.85, 0.99), size: R * 0.028, color: white,
                endColor: c(i), shift: 0.25, fadeTail: 0.15,
                strobe: 7 + rng.next() * 7,
                strobeFrom: 0.3 + rng.next() * 0.25,
                depth: depthOf(dz), tex: rng.next() < 0.3 ? 1 : 0))
        }
        flash(0, 0, 0, R * 0.9, white, 0.3)
    case "hachi":
        let k = 2.5
        let silver = hanabiMixColor(c0, HANABI_WHITE, 0.7)
        for i in 0..<n {
            let angle = rng.next() * hanabiTAU
            let speed = R * k * (0.3 + rng.next() * 0.6)
            add(StarInput(vx: cos(angle) * speed, vy: sin(angle) * speed,
                drag: k, fall: R * 0.25, life: lifeFrac(0.5, 0.98),
                size: R * 0.013, color: silver, endColor: c(i), shift: 0.6,
                trailColor: hanabiMixColor(silver, HANABI_EMBER, 0.3),
                trail: 0.08 + trailK * 0.14, segments: 2, fadeTail: 0.3,
                twinkle: 0.4 + twinkleK * 0.6,
                spiral: R * (0.05 + rng.next() * 0.11),
                spin: (rng.next() < 0.5 ? -1.0 : 1.0) * (9 + rng.next() * 12)))
        }
        flash(0, 0, 0, R * 0.6, silver, 0.24)
    case "willow-ring":
        let inner = Int((Double(n) * 0.35).rounded())
        let outer = n - inner
        let gold = hanabiMixColor(c1, HANABI_GOLD, 0.7)
        for i in 0..<inner {
            let (dx, dy) = planar(cos(hanabiTAU * Double(i) / Double(max(inner, 1))),
                                  sin(hanabiTAU * Double(i) / Double(max(inner, 1))))
            let speed = R * 3.6 * 0.46
            add(StarInput(vx: dx * speed, vy: dy * speed, drag: 3.6, fall: R * 0.15,
                life: lifeFrac(0.45, 0.55), size: R * 0.03, color: c0,
                endColor: hanabiMixColor(c0, HANABI_WHITE, 0.5), shift: 0.6,
                fadeTail: 0.1))
        }
        for i in 0..<outer {
            let (dx, dy, dz) = sphere(i, outer, 0.4)
            let speed = R * 2.6 * (0.92 + rng.next() * 0.12)
            add(StarInput(vx: dx * speed, vy: dy * speed - R * 0.2, drag: 2.6,
                fall: R * 0.9, life: lifeFrac(0.88, 0.99), size: R * 0.013,
                color: gold, endColor: hanabiMixColor(gold, HANABI_EMBER, 0.6),
                shift: 0.6, trailColor: hanabiMixColor(gold, HANABI_EMBER, 0.3),
                trail: 0.35 + trailK * 0.9, segments: 4, fadeTail: 0.45,
                glitter: 0.3 + twinkleK * 0.4, depth: depthOf(dz) * 0.9))
        }
        flash(0, 0, 0, R * 1.0, c0, 0.34)
    case "mine":
        let volleys = max(4, min(8, Int((D * 2.6).rounded())))
        let per = max(4, Int((Double(n) / Double(volleys)).rounded()))
        let k = 1.7
        for v in 0..<volleys {
            let delay = (Double(v) / Double(volleys)) * D * 0.55
            let lean = (v % 2 == 0 ? -1.0 : 1.0) * (0.12 + rng.next() * 0.2)
            let color = c(v)
            let lifeV = min(0.9 + rng.next() * 0.5, D * 0.6)
            for i in 0..<per {
                let angle = -Double.pi / 2 + lean
                    + ((Double(i) + 0.5) / Double(per) - 0.5) * 1.3
                    + (rng.next() - 0.5) * 0.12
                let speed = R * k * (1.45 + rng.next() * 0.45)
                add(StarInput(vx: cos(angle) * speed, vy: sin(angle) * speed,
                    drag: k, fall: R * 0.9, start: delay,
                    life: lifeV * (0.8 + rng.next() * 0.2), size: R * 0.02,
                    color: color, endColor: hanabiMixColor(color, HANABI_WHITE, 0.6),
                    shift: 0.7, trail: 0.1 + trailK * 0.3, segments: 3,
                    fadeTail: 0.3, twinkle: twinkleK))
            }
            flash(0, 0, delay, R * 0.35, color, 0.18)
        }
    default:
        break
    }

    for i in stars.indices {
        stars[i].rank = (Double(i + 1) * 0.6180339887498949)
            .truncatingRemainder(dividingBy: 1)
    }
    var end = at
    for star in stars { end = max(end, star.start + star.life) }
    for item in flashes { end = max(end, item.at + item.life) }
    return HanabiBurstPlan(at: at, end: end, stars: stars, flashes: flashes)
}

/// 星点燃后 tau 秒的位置（burstPlan.ts starPosition 闭式解）。
private func hanabiStarPosition(_ star: HanabiStarPlan, tau: Double)
    -> (x: Double, y: Double) {
    let t = max(tau, 0)
    let e = exp(-star.drag * t)
    let f = (1 - e) / star.drag
    var x = star.x0 + star.vx * f
    var y = star.y0 + star.vy * f + star.fall * (t - f)
    if star.spiral > 0 {
        let r = star.spiral * (1 - exp(-3 * t))
        let a = star.phase + star.spin * t
        x += r * cos(a)
        y += r * sin(a)
    }
    return (x, y)
}

/// 不含点滅的亮度（burstPlan.ts starBase）。
private func hanabiStarBase(_ star: HanabiStarPlan, tau: Double) -> Double {
    if tau < 0 || tau > star.life { return 0 }
    let u = tau / star.life
    var b = star.depth * hanabiClamp01(tau / 0.035)
    if u > 1 - star.fadeTail {
        let k = (1 - u) / star.fadeTail
        b *= k * k * (3 - 2 * k)
    }
    return b
}

/// 星在 tau 时的亮度（burstPlan.ts starBrightness）。
private func hanabiStarBrightness(_ star: HanabiStarPlan, tau: Double) -> Double {
    var b = hanabiStarBase(star, tau: tau)
    if b <= 0 { return 0 }
    if star.strobe > 0 && tau > star.strobeFrom {
        let on = (tau * star.strobe + star.phase)
            .truncatingRemainder(dividingBy: 1) < 0.42
        b *= on ? 1 : 0.05
    }
    let u = tau / star.life
    if star.twinkle > 0 && u > 0.5 {
        let nn = hanabiHash01(Double(Int(tau * 24)), star.phase * 97)
        b *= 1 - star.twinkle * hanabiClamp01((u - 0.5) / 0.2) * (nn < 0.45 ? 0.85 : 0)
    }
    return b
}

/// 星在 tau 时的颜色（burstPlan.ts starColor）。
private func hanabiStarColor(_ star: HanabiStarPlan, tau: Double) -> Int {
    let u = tau / star.life
    var color = star.shift < 1
        ? hanabiMixColor(star.color, star.endColor,
                         hanabiClamp01((u - star.shift) / 0.1))
        : star.color
    if star.glitter > 0
        && hanabiHash01(Double(Int(tau * 30)), star.phase * 53) < star.glitter * 0.35 {
        color = hanabiMixColor(color, HANABI_WHITE, 0.75)
    }
    return color
}

/// 星在 tau 时的直径（burstPlan.ts starSize）。
private func hanabiStarSize(_ star: HanabiStarPlan, tau: Double) -> Double {
    let u = hanabiClamp01(tau / star.life)
    var size = star.size * (1 - 0.45 * u)
    if star.glitter > 0
        && hanabiHash01(Double(Int(tau * 30)), star.phase * 53) < star.glitter * 0.35 {
        size *= 1.6
    }
    return size
}

private func hanabiBurstActive(_ plan: HanabiBurstPlan, time: Double) -> Bool {
    time >= plan.at && time <= plan.end
}

// MARK: - 升空尾迹（burstPlan.ts 升空段对译）

private let HANABI_LAUNCH_EMBER_LIFE = 0.6
private let HANABI_LAUNCH_EMBER_STEP = 0.032
private let HANABI_LAUNCH_TRAIL_SEGMENTS = 5
/// timeline.ts LAUNCH_DURATION：升空尾迹飞行时长。
private let HANABI_LAUNCH_DURATION = 0.45

private func hanabiLaunchEnd(_ launch: HanabiLaunchEvent) -> Double {
    launch.at + launch.duration + HANABI_LAUNCH_EMBER_LIFE
}

/// 弹头在进度 p 处的位置（减速上升、左右摇曳）。
private func hanabiLaunchHead(_ launch: HanabiLaunchEvent, p: Double, salt: Double)
    -> (x: Double, y: Double) {
    let k = hanabiClamp01(p)
    let rise = 1 - (1 - k) * (1 - k)
    let span = hypot(launch.toX - launch.fromX, launch.toY - launch.fromY)
    let freq = 2.2 + hanabiHash01(1, salt) * 1.6
    let phase = hanabiHash01(2, salt) * hanabiTAU
    let sway = sin(k * freq * hanabiTAU + phase) * span * 0.018 * (1 - k * 0.7)
    return (hanabiLerp(launch.fromX, launch.toX, rise) + sway,
            hanabiLerp(launch.fromY, launch.toY, rise))
}

/// 某一时刻升空尾迹要多少精灵（上限估计，burstPlan.ts launchDemand）。
private func hanabiLaunchDemand(_ launch: HanabiLaunchEvent, time: Double) -> Int {
    let age = time - launch.at
    if age < 0 || time > hanabiLaunchEnd(launch) { return 0 }
    let embers = Int(min(age, HANABI_LAUNCH_EMBER_LIFE) / HANABI_LAUNCH_EMBER_STEP) + 1
    return embers + (age <= launch.duration ? HANABI_LAUNCH_TRAIL_SEGMENTS + 2 : 0)
}

// MARK: - 逐字动画曲线（text/animations.ts 对译）
//
// 17 入场 / 9 强调 / 7 退场全为纯 t 函数：位移以字号为单位、
// 旋转为弧度；幅度统一乘 motion，透明度不乘。

private struct HanabiGlyphPose {
    var dx: Double = 0, dy: Double = 0
    var scaleX: Double = 1, scaleY: Double = 1
    var rotation: Double = 0
    var alpha: Double = 1
    var skew: Double = 0
    var scramble: Int = -1
    var rgbSplit: Double = 0
    var blur: Double = 0
    var split: Double = 0
    var backside: Bool = false
    var reveal: Double = 1
}

private struct HanabiSingPose {
    var dx: Double = 0, dy: Double = 0
    var scale: Double = 1, scaleX: Double = 1, scaleY: Double = 1
    var rotation: Double = 0
    var flash: Double = 0
    var glow: Double = 0
    var color: Double = 0
}

private struct HanabiFxContext {
    var index: Int
    var count: Int
    var rand: (Double, Double, Double, Double)
    var toCenterX: Double
    var toCenterY: Double
    var dirX: Double
    var dirY: Double
    var time: Double
    var motion: Double
    var slideDistance: Double = 7
}

private func hanabiEaseOutCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
private func hanabiEaseInCubic(_ t: Double) -> Double { t * t * t }
private func hanabiEaseInQuad(_ t: Double) -> Double { t * t }
private func hanabiEaseOutQuad(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }
private func hanabiEaseOutExpo(_ t: Double) -> Double {
    t >= 1 ? 1 : 1 - pow(2, -10 * t)
}
private func hanabiEaseOutBack(_ t: Double, _ s: Double = 1.70158) -> Double {
    1 + (s + 1) * pow(t - 1, 3) + s * pow(t - 1, 2)
}
private func hanabiEaseInBack(_ t: Double, _ s: Double = 1.70158) -> Double {
    (s + 1) * t * t * t - s * t * t
}
private func hanabiEaseInOutCubic(_ t: Double) -> Double {
    t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}
private func hanabiDampedCos(_ q: Double, _ freq: Double, _ decay: Double) -> Double {
    exp(-decay * q) * cos(freq * q) * (1 - q)
}
private func hanabiDampedSin(_ q: Double, _ freq: Double, _ decay: Double) -> Double {
    exp(-decay * q) * sin(freq * q) * (1 - q)
}

/// animations.ts hash01（整数哈希版，乱码/故障逐帧取值用）：
/// h = imul((a|0) ^ 0x9e3779b9, 0x85ebca6b)
///   ^ imul((b|0) + 0x632be5ab, 0xc2b2ae35)，再三轮 xorshift-mul。
/// JS 的 Math.imul 与中间加法都是 32 位环绕，原生以 &* / &+ 等价。
private func hanabiAnimHash01(_ a: Int, _ b: Int = 0) -> Double {
    let termA = (UInt32(bitPattern: Int32(truncatingIfNeeded: a)) ^ 0x9e3779b9)
        &* 0x85ebca6b
    let bSalted = Int32(truncatingIfNeeded: b) &+ 0x632be5ab
    let termB = UInt32(bitPattern: bSalted) &* 0xc2b2ae35
    var h = termA ^ termB
    h ^= h >> 15
    h = h &* 0x2c1b3c6d
    h ^= h >> 12
    h = h &* 0x297a2d39
    h ^= h >> 15
    return Double(h) / 4294967296
}

/// 每种入场一个字的时长（animations.ts ENTER_DURATION）。
private let HANABI_ENTER_DURATION: [String: Double] = [
    "pop": 0.45, "drop": 0.62, "rise": 0.6, "spin": 0.62, "wipe": 0.42,
    "type": 0.12, "scramble": 0.75, "stretch": 0.55, "elastic": 0.85,
    "split": 0.5, "spiral": 0.85, "flip": 0.55, "glitch": 0.6,
    "stamp": 0.5, "wave": 0.75, "zoom": 0.6, "burst": 0.75,
]

/// 字「到位」在入场的哪个比例（animations.ts ENTER_ARRIVAL）。
private let HANABI_ENTER_ARRIVAL: [String: Double] = [
    "pop": 0, "drop": 0.4, "rise": 0.3, "spin": 0.2, "wipe": 0, "type": 0,
    "scramble": 0, "stretch": 0.1, "elastic": 0.1, "split": 0.3,
    "spiral": 0.45, "flip": 0.15, "glitch": 0, "stamp": 0.35,
    "wave": 0.3, "zoom": 0.25, "burst": 0.3,
]

private let HANABI_STAMP_IMPACT = 0.5

private func hanabiApplyMotion(_ pose: inout HanabiGlyphPose, motion: Double) {
    if motion == 1 { return }
    pose.dx *= motion
    pose.dy *= motion
    pose.rotation *= motion
    pose.skew *= motion
    pose.rgbSplit *= motion
    pose.scaleX = 1 + (pose.scaleX - 1) * motion
    pose.scaleY = 1 + (pose.scaleY - 1) * motion
}

/// 入场姿态（animations.ts enterPose）：p = 进度 0..1。
private func hanabiEnterPose(fx: String, p: Double, ctx: HanabiFxContext) -> HanabiGlyphPose {
    var pose = HanabiGlyphPose()
    if p >= 1 { return pose }
    let q = hanabiClamp01(p)
    let (r0, r1, r2, _) = ctx.rand
    switch fx {
    case "pop":
        let s = hanabiEaseOutBack(q, 2.4)
        pose.scaleX = s
        pose.scaleY = s
        pose.scaleY = s * (1 + 0.14 * hanabiDampedSin(q, 14, 3))
        pose.scaleX = s * (1 - 0.1 * hanabiDampedSin(q, 14, 3))
        pose.rotation = (r0 - 0.5) * 0.7 * (1 - hanabiEaseOutCubic(q))
        pose.dy = 0.25 * (1 - hanabiEaseOutCubic(q))
        pose.alpha = hanabiClamp01(q * 6)
    case "drop":
        if q < 0.48 {
            let f = q / 0.48
            pose.dy = -2.4 * (1 - f * f)
            pose.scaleY = 1 + 0.3 * f
            pose.scaleX = 1 - 0.12 * f
        } else {
            let f = (q - 0.48) / 0.52
            pose.dy = -0.32 * abs(sin(f * Double.pi * 2)) * exp(-3 * f) * (1 - f)
            pose.scaleY = 1 - 0.3 * hanabiDampedCos(f, 16, 4)
            pose.scaleX = 1 + 0.22 * hanabiDampedCos(f, 16, 4)
        }
        pose.alpha = hanabiClamp01(q * 7)
    case "rise":
        let f = hanabiClamp01(q / 0.58)
        let e = hanabiEaseOutCubic(f)
        pose.dy = 1.7 * (1 - e)
        if q < 0.58 {
            pose.scaleY = 1 + 0.55 * (1 - e)
            pose.scaleX = 1 - 0.28 * (1 - e)
        } else {
            let g = (q - 0.58) / 0.42
            pose.scaleY = 1 - 0.2 * hanabiDampedSin(g, 11, 2.5)
            pose.scaleX = 1 + 0.16 * hanabiDampedSin(g, 11, 2.5)
            pose.dy += 0.08 * hanabiDampedSin(g, 11, 2.5)
        }
        pose.alpha = hanabiClamp01(q * 4)
    case "spin":
        let e = hanabiEaseOutBack(q, 1.9)
        pose.rotation = -2.6 * (1 - e) * (r0 < 0.5 ? 1 : -1)
        let s = 0.15 + 0.85 * e
        pose.scaleX = s
        pose.scaleY = s
        pose.dx = -0.7 * (1 - hanabiEaseOutCubic(q)) * ctx.dirX
        pose.dy = -0.7 * (1 - hanabiEaseOutCubic(q)) * ctx.dirY
            - 0.3 * sin(Double.pi * q) * (1 - q)
        pose.alpha = hanabiClamp01(q * 4)
    case "wipe":
        let e = hanabiEaseOutCubic(q)
        pose.reveal = hanabiEaseOutCubic(hanabiClamp01(q / 0.8))
        pose.dx = -0.35 * (1 - e) * ctx.dirX
        pose.dy = -0.35 * (1 - e) * ctx.dirY
        pose.skew = -0.3 * (1 - e)
        pose.alpha = hanabiClamp01(q * 8)
    case "type":
        pose.alpha = q > 0 ? 1 : 0
        let s = 1 + 0.3 * pow(1 - hanabiClamp01(q / 0.6), 2)
        pose.scaleX = s
        pose.scaleY = s
    case "scramble":
        pose.alpha = hanabiClamp01(q * 8)
        if q < 0.72 {
            let frame = Int(floor(ctx.time * 22))
            pose.scramble = Int(floor(hanabiAnimHash01(frame, Int(r0 * 1e6)) * 1e6))
            pose.dy = (hanabiAnimHash01(frame + 7, Int(r1 * 1e6)) - 0.5) * 0.12
            pose.alpha *= 0.75 + 0.25 * hanabiAnimHash01(frame + 13, 1)
        } else {
            let s = 1 + 0.16 * pow(1 - (q - 0.72) / 0.28, 2)
            pose.scaleX = s
            pose.scaleY = s
        }
    case "stretch":
        let k = pow(1 - q, 3)
        pose.scaleX = 1 + 2 * k - 0.16 * hanabiDampedSin(q, 13, 3)
        pose.scaleY = 1 - 0.72 * k + 0.12 * hanabiDampedSin(q, 13, 3)
        pose.dx = -1.4 * k * ctx.dirX
        pose.dy = -1.4 * k * ctx.dirY
        pose.alpha = hanabiClamp01(q * 5)
    case "elastic":
        let angle = r0 * Double.pi * 2
        let spring = exp(-4.2 * q) * cos(q * Double.pi * 4.5) * (1 - q)
        pose.dx = cos(angle) * 1.6 * spring
        pose.dy = sin(angle) * 1.6 * spring
        pose.rotation = (r1 - 0.5) * 0.8 * spring
        pose.scaleX = 1 + 0.18 * abs(spring)
        pose.scaleY = 1 - 0.12 * abs(spring)
        pose.alpha = hanabiClamp01(q * 5)
    case "split":
        pose.split = 1 - hanabiEaseOutExpo(hanabiClamp01(q / 0.8))
        if q > 0.8 {
            let g = (q - 0.8) / 0.2
            pose.scaleX = 1 + 0.1 * hanabiDampedSin(g, 10, 2)
            pose.scaleY = 1 - 0.08 * hanabiDampedSin(g, 10, 2)
        }
        pose.alpha = hanabiClamp01(q * 5)
    case "spiral":
        let e = hanabiEaseOutCubic(q)
        let radius = 3.4 * (1 - e)
        let angle = r0 * Double.pi * 2 + Double.pi * 2.5 * (1 - e)
        pose.dx = cos(angle) * radius
        pose.dy = sin(angle) * radius * 0.8
        pose.rotation = -Double.pi * 2 * (1 - e) * (r1 < 0.5 ? 1 : -1)
        let s = 0.25 + 0.75 * hanabiEaseOutBack(q, 1.5)
        pose.scaleX = s
        pose.scaleY = s
        pose.alpha = hanabiClamp01(q * 3)
    case "flip":
        let phi = Double.pi * 2.5 * (1 - hanabiEaseOutCubic(q))
        pose.scaleX = cos(phi)
        pose.backside = pose.scaleX < 0
        pose.scaleY = 1 + 0.08 * sin(phi)
        pose.dy = -0.3 * sin(Double.pi * q) * (1 - q)
        pose.alpha = hanabiClamp01(q * 6)
    case "glitch":
        if q < 0.8 {
            let frame = Int(floor(ctx.time * 24))
            let seed = Int(r0 * 1e6)
            let intensity = 1 - q / 0.8
            let h1 = hanabiAnimHash01(frame, seed)
            let h2 = hanabiAnimHash01(frame, seed + 1)
            let h3 = hanabiAnimHash01(frame, seed + 2)
            let h4 = hanabiAnimHash01(frame, seed + 3)
            pose.dx = h2 > 0.35 ? (h1 - 0.5) * 0.9 * intensity : 0
            pose.rgbSplit = (0.05 + 0.13 * h3) * intensity
            pose.skew = h4 > 0.7 ? (h1 - 0.5) * 0.9 * intensity : 0
            pose.scaleX = h2 > 0.82 ? 1 + 0.4 * intensity : 1
            pose.alpha = hanabiClamp01(q * 10)
                * (hanabiAnimHash01(frame, seed + 4) > 0.18 ? 1 : 0.25)
        }
    case "stamp":
        if q < HANABI_STAMP_IMPACT {
            let f = q / HANABI_STAMP_IMPACT
            let s = 2.6 - 1.6 * hanabiEaseInQuad(f)
            pose.scaleX = s
            pose.scaleY = s
            pose.rotation = (r0 - 0.5) * 0.35 * (1 - f)
            pose.alpha = hanabiClamp01(f * 2.2)
        } else {
            let f = (q - HANABI_STAMP_IMPACT) / (1 - HANABI_STAMP_IMPACT)
            pose.scaleX = 1 + 0.22 * hanabiDampedCos(f, 17, 4)
            pose.scaleY = 1 - 0.22 * hanabiDampedCos(f, 17, 4)
        }
    case "wave":
        let k = pow(1 - q, 1.5)
        pose.dy = 1.1 * k * cos(q * Double.pi * 3)
        pose.rotation = 0.4 * k * sin(q * Double.pi * 3)
        pose.scaleY = 1 + 0.18 * k * sin(q * Double.pi * 3 + 0.6)
        pose.alpha = hanabiClamp01(q * 4)
    case "zoom":
        let e = hanabiEaseOutExpo(q)
        let k = 1.8 * (1 - e)
        let s = 1 + k * 1.5
        pose.scaleX = s
        pose.scaleY = s
        pose.dx = -ctx.toCenterX * k
        pose.dy = -ctx.toCenterY * k
        pose.blur = pow(1 - q, 1.4)
        pose.alpha = hanabiClamp01(q * 3.5)
    case "burst":
        let e = hanabiEaseOutBack(q, 1.8)
        pose.dx = ctx.toCenterX * (1 - e)
        pose.dy = ctx.toCenterY * (1 - e)
        let s = 0.2 + 0.8 * hanabiEaseOutBack(hanabiClamp01(q * 1.3), 1.6)
        pose.scaleX = s
        pose.scaleY = s
        pose.rotation = (r2 - 0.5) * 4 * (1 - hanabiEaseOutCubic(q))
        pose.alpha = hanabiClamp01(q * 6)
    default:
        break
    }
    hanabiApplyMotion(&pose, motion: ctx.motion)
    return pose
}

/// 退场姿态（animations.ts exitPose）：p = 进度 0..1。
private func hanabiExitPose(fx: String, p: Double, ctx: HanabiFxContext) -> HanabiGlyphPose {
    var pose = HanabiGlyphPose()
    if p <= 0 { return pose }
    let q = hanabiClamp01(p)
    let (r0, r1, r2, _) = ctx.rand
    switch fx {
    case "ascend":
        let e = hanabiEaseInCubic(q)
        let dip = q < 0.22 ? sin((q / 0.22) * Double.pi) * 0.12 : 0
        pose.dy = dip - 2.8 * e
        pose.dx = (r0 - 0.5) * 0.7 * e
        pose.rotation = (r1 - 0.5) * 0.5 * e
        pose.scaleY = 1 + 0.45 * e
        pose.scaleX = 1 - 0.22 * e
        pose.alpha = 1 - hanabiEaseInQuad(q)
    case "scatter":
        var ox = -ctx.toCenterX + (r0 - 0.5) * 2
        var oy = -ctx.toCenterY + (r1 - 0.5) * 2
        let len = hypot(ox, oy)
        let norm = len == 0 ? 1 : len
        ox /= norm
        oy /= norm
        let e = hanabiEaseOutCubic(q)
        let dist = 2.4 + r2 * 1.8
        pose.dx = ox * dist * e
        pose.dy = oy * dist * e
        pose.rotation = (r1 - 0.5) * 3.2 * e
        let s = 1 - 0.65 * e
        pose.scaleX = s
        pose.scaleY = s
        pose.alpha = 1 - pow(q, 1.6)
    case "shrink":
        let s = q < 0.2
            ? 1 + 0.16 * sin((q / 0.2) * Double.pi / 2)
            : 1.16 * (1 - hanabiEaseInBack((q - 0.2) / 0.8, 1.4))
        let clamped = max(0, s)
        pose.scaleX = clamped
        pose.scaleY = clamped
        pose.rotation = (r0 - 0.5) * 0.9 * q
        pose.alpha = q > 0.8 ? (1 - q) / 0.2 : 1
    case "slide":
        let e = hanabiEaseInBack(q, 1.6)
        let dist = ctx.slideDistance
        pose.dx = ctx.dirX * dist * e
        pose.dy = ctx.dirY * dist * e
        pose.scaleX = 1 + 0.45 * hanabiEaseInQuad(q) * abs(ctx.dirX)
        pose.scaleY = 1 + 0.45 * hanabiEaseInQuad(q) * abs(ctx.dirY)
        pose.skew = -0.45 * hanabiEaseInQuad(q) * (ctx.dirX == 0 ? 1 : (ctx.dirX > 0 ? 1 : -1))
        pose.alpha = 1 - pow(hanabiClamp01((q - 0.45) / 0.55), 1.5)
    case "dissolve":
        let frame = Int(floor(ctx.time * 20))
        let flicker = hanabiAnimHash01(frame, Int(r0 * 1e6))
        pose.alpha = pow(1 - q, 1.3) * (1 - 0.45 * q * flicker)
        let s = 1 + 0.14 * hanabiEaseOutQuad(q)
        pose.scaleX = s
        pose.scaleY = s
        pose.dy = -0.35 * hanabiEaseOutQuad(q)
        pose.blur = q
    case "fall":
        let e = hanabiEaseInQuad(q)
        pose.dy = 3 * e
        pose.dx = 0.28 * sin(q * Double.pi * 2 + r0 * 6) * q
        pose.rotation = (r1 - 0.5) * 1.2 * e
        pose.scaleY = 1 + 0.4 * e
        pose.scaleX = 1 - 0.25 * e
        pose.alpha = 1 - pow(q, 1.6)
    case "blink":
        let on = q < 0.14 || (q >= 0.24 && q < 0.4) || (q >= 0.5 && q < 0.6)
            || (q >= 0.7 && q < 0.76) || (q >= 0.82 && q < 0.85)
        pose.alpha = on && q < 1 ? 1 : 0
        let s = 1 + (on ? 0.05 * q : 0)
        pose.scaleX = s
        pose.scaleY = s
    default:
        break
    }
    if q >= 1 { pose.alpha = 0 }
    hanabiApplyMotion(&pose, motion: ctx.motion)
    return pose
}

/// 强调姿态（animations.ts singPose）：u = 被唱到后秒数。
private func hanabiSingPose(fx: String, u: Double, duration: Double,
                            rand: Double, motion: Double) -> HanabiSingPose {
    var pose = HanabiSingPose()
    if u < 0 || fx == "none" { return pose }
    let hold = max(duration, 0.12)
    let envelope = hanabiClamp01(u / 0.08) * (1 - hanabiClamp01((u - hold) / 0.35))
    switch fx {
    case "bounce":
        let T = 0.3
        if u < T {
            pose.dy = -0.26 * sin((u / T) * Double.pi)
        } else if u < T + 0.16 {
            pose.dy = -0.06 * sin(((u - T) / 0.16) * Double.pi)
        }
        let land = u - T
        if land >= 0 && land < 0.3 {
            let f = land / 0.3
            pose.scaleY = 1 - 0.14 * hanabiDampedCos(f, 14, 3)
            pose.scaleX = 1 + 0.1 * hanabiDampedCos(f, 14, 3)
        } else if u < T {
            pose.scaleY = 1 + 0.08 * sin((u / T) * Double.pi)
        }
    case "flash":
        pose.flash = exp(-u / 0.16)
        pose.scale = 1 + 0.2 * exp(-u / 0.1) * hanabiClamp01(u / 0.03)
    case "swell":
        pose.scale = 1 + 0.24 * hanabiEaseOutBack(hanabiClamp01(u / 0.18), 2)
            * (1 - hanabiClamp01((u - hold) / 0.35))
    case "shake":
        let decay = exp(-max(0, u - hold) / 0.08)
        let k = hanabiClamp01(u / 0.04) * decay * (u < hold + 0.4 ? 1 : 0)
        pose.dx = 0.06 * sin(u * 61 + rand * 9) * k
        pose.dy = 0.04 * sin(u * 47 + rand * 5) * k
        pose.rotation = 0.08 * sin(u * 53 + rand * 7) * k
    case "jump":
        let T = 0.42
        if u < T {
            let f = u / T
            pose.dy = -0.5 * sin(f * Double.pi)
            pose.rotation = (rand < 0.5 ? 1.0 : -1.0) * 0.22 * sin(f * Double.pi * 2) * (1 - f)
            pose.scaleY = 1 + 0.2 * sin(f * Double.pi) * (1 - f)
            pose.scaleX = 1 - 0.12 * sin(f * Double.pi) * (1 - f)
        } else if u < T + 0.35 {
            let f = (u - T) / 0.35
            pose.scaleY = 1 - 0.2 * hanabiDampedCos(f, 13, 3)
            pose.scaleX = 1 + 0.16 * hanabiDampedCos(f, 13, 3)
        }
    case "glow":
        pose.glow = envelope
        pose.flash = 0.35 * envelope
        pose.scale = 1 + 0.07 * envelope
    case "underline":
        pose.dy = -0.05 * envelope
    case "color":
        pose.color = hanabiClamp01(u / 0.1)
        pose.scale = 1 + 0.14 * exp(-u / 0.12) * hanabiClamp01(u / 0.03)
    default:
        break
    }
    if motion != 1 {
        pose.dx *= motion
        pose.dy *= motion
        pose.rotation *= motion
        pose.scale = 1 + (pose.scale - 1) * motion
        pose.scaleX = 1 + (pose.scaleX - 1) * motion
        pose.scaleY = 1 + (pose.scaleY - 1) * motion
    }
    return pose
}

/// enter ∘ exit 叠加（animations.ts combinePoses）。
private func hanabiCombinePoses(_ a: HanabiGlyphPose, _ b: HanabiGlyphPose) -> HanabiGlyphPose {
    var out = HanabiGlyphPose()
    out.dx = a.dx + b.dx
    out.dy = a.dy + b.dy
    out.scaleX = a.scaleX * b.scaleX
    out.scaleY = a.scaleY * b.scaleY
    out.rotation = a.rotation + b.rotation
    out.alpha = a.alpha * b.alpha
    out.skew = a.skew + b.skew
    out.scramble = a.scramble >= 0 ? a.scramble : b.scramble
    out.rgbSplit = a.rgbSplit + b.rgbSplit
    out.blur = max(a.blur, b.blur)
    out.split = max(a.split, b.split)
    out.backside = a.backside || b.backside
    out.reveal = min(a.reveal, b.reveal)
    return out
}

/// 入场先后次序（animations.ts enterOrder）。
private func hanabiEnterOrder(fx: String, count: Int, rng: inout HanabiRng) -> [Int] {
    var order = Array(0..<count)
    if fx == "scramble" || fx == "glitch" {
        if count > 1 {
            for i in stride(from: count - 1, through: 1, by: -1) {
                let j = Int(floor(rng.next() * Double(i + 1)))
                order.swapAt(i, j)
            }
        }
        var rank = [Int](repeating: 0, count: count)
        for (k, glyph) in order.enumerated() { rank[glyph] = k }
        return rank
    }
    if fx == "zoom" || fx == "burst" {
        let mid = Double(count - 1) / 2
        return order.map { Int((abs(Double($0) - mid) * 2).rounded()) / 2 }
    }
    return order
}

/// 入场时间表（animations.ts scheduleEnter）：最后一个字
/// 入场完成不晚于 deadline（该行第一个被唱的字）。
private func hanabiScheduleEnter(fx: String, ranks: [Int], enterAt: Double,
                                 stagger: Double, deadline: Double)
    -> (start: [Double], duration: Double, landed: [Double]) {
    let maxRank = ranks.max() ?? 0
    let staggerFactor: [String: Double] = ["burst": 0.35, "zoom": 0.6, "stamp": 1.35, "type": 1]
    var step = max(0, stagger) * (staggerFactor[fx] ?? 1)
    var duration = HANABI_ENTER_DURATION[fx] ?? 0.5
    let available = deadline - enterAt
    if step * Double(maxRank) + duration > available {
        step = maxRank > 0
            ? max(0, min(step, (available - duration) / Double(maxRank))) : 0
        if step * Double(maxRank) + duration > available {
            let ratio = max(0, available) / (step * Double(maxRank) + duration)
            step *= ratio
            duration = max(0.1, duration * ratio)
            if step * Double(maxRank) + duration > available {
                step = maxRank > 0
                    ? max(0, (available - duration) / Double(maxRank)) : 0
            }
        }
    }
    let start = ranks.map { $0 < 0 ? Double.nan : enterAt + Double($0) * step }
    return (start, duration, start.map { $0 + duration })
}

/// 退场时间表（animations.ts scheduleExit）。
private func hanabiScheduleExit(ranks: [Int], exitAt: Double, exitDuration: Double)
    -> (start: [Double], end: [Double]) {
    let maxRank = ranks.max() ?? 0
    let total = max(0.001, exitDuration)
    let step = maxRank > 0 ? min(0.05, (total * 0.4) / Double(maxRank)) : 0
    let each = total - step * Double(maxRank)
    let start = ranks.map { $0 < 0 ? Double.nan : exitAt + Double($0) * step }
    return (start, start.map { $0 + each })
}

/// stamp 落定时整组的震动（animations.ts stampShake）。
private func hanabiStampShake(time: Double, impacts: [Double], amplitude: Double)
    -> (x: Double, y: Double) {
    var x = 0.0, y = 0.0
    for (i, impact) in impacts.enumerated() {
        let tau = time - impact
        if tau < 0 || tau > 0.45 { continue }
        let k = amplitude * exp(-tau / 0.085)
        x += k * sin(tau * 96 + Double(i) * 1.7)
        y += k * 0.8 * sin(tau * 77 + Double(i) * 2.3 + 1)
    }
    return (x, y)
}

// MARK: - 整首编译（program.ts + hanabiProgram.ts 对译，单单元化）
//
// 网页把整首歌按段落编译、运行时按段落缓存场景并套段落
// 转场；原生协议只有行表与曲目时长，没有段落/副歌标记
// 数据源。原生落点：一首歌编译成一个场景单元（全部镜头
// 首尾相接、世界持续上升），段落只用于选预设的 mood 过滤
// （段落划分按行间空隙 ≥ bridgeGap 切分、性质一律 verse /
// break 近似——网页 classifyParagraph 依赖重复行副歌识别，
// 协议无此数据，见报告）；段落转场（ascend/flash/bloom）
// 与片尾卡未移植（见报告）。切镜头、选预设 chain、间奏
// 规则逐项照网页。

private struct HanabiShotData {
    var id: String
    var profileKind: String
    var startTime: Double
    var endTime: Double
    var lyricEndTime: Double
    var isBridge: Bool
    /// 镜头的文字（切片拼成的一行）；间奏为 nil。
    var line: LyricLine?
    var lineIndex: Int
}

/// program.ts DEFAULT_HANABI_PARAMS。
private let HANABI_BRIDGE_GAP = 3.0
private let HANABI_MAX_CHARS = 18
private let HANABI_MAX_LINE_SECONDS = 6.0
private let HANABI_BRIDGE_TAIL = 0.6
private let HANABI_MAX_PIECES = 3
private let HANABI_RECENT = 6
private let HANABI_BRIDGE_FAMILIES = ["senrin", "uchiage", "kiku", "shakudama"]
/// hanabiProgram.ts 间奏镜头目标时长 / 切分阈值。
private let HANABI_BRIDGE_SHOT = 7.0
private let HANABI_BRIDGE_SPLIT = 10.0

/// program.ts sliceLine 的原生近似：按字素（Character）偏移
/// 裁一行，词时间按比例分配。网页偏移是 UTF-16，CJK/假名
/// 均为单码元，两者一致；含代理对字符时有微差（见报告）。
private func hanabiSliceLine(_ line: LyricLine, startOffset: Int,
                             endOffset: Int) -> LyricLine? {
    let chars = Array(line.text)
    let start = max(0, min(startOffset, chars.count))
    let end = max(start, min(endOffset, chars.count))
    if start == 0 && end == chars.count { return line }
    let text = String(chars[start..<end])
    if text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
    var words: [LyricWord]? = nil
    if let source = line.words, !source.isEmpty {
        // 词在整行里的字素区间（按词文本长度累计，与网页
        // locateWords 的 indexOf 定位同义近似）。
        var cursor = 0
        var sliced: [LyricWord] = []
        for word in source {
            let wStart = cursor
            let wEnd = cursor + word.text.count
            cursor = wEnd
            let from = max(wStart, start)
            let to = min(wEnd, end)
            if to <= from { continue }
            let span = Double(max(wEnd - wStart, 1))
            let duration = word.end - word.start
            let wordChars = Array(word.text)
            sliced.append(LyricWord(
                start: word.start + duration * Double(from - wStart) / span,
                end: word.start + duration * Double(to - wStart) / span,
                text: String(wordChars[(from - wStart)..<(to - wStart)])))
        }
        if !sliced.isEmpty { words = sliced }
    }
    let length = Double(max(chars.count, 1))
    let timeAt = { (offset: Int) in
        line.start + (line.end - line.start) * Double(offset) / length
    }
    let pieceStart = words?.first?.start ?? timeAt(start)
    let pieceEnd = words?.last?.end ?? timeAt(end)
    return LyricLine(id: line.id, start: pieceStart, end: pieceEnd,
                     text: text, words: words, singingRatio: line.singingRatio)
}

/// program.ts splitLine：一行 → 1–3 段（超字数/超时长时在
/// 词边界切开）。词边界取 StageLyricUnits 的单元时刻。
private func hanabiSplitLine(_ line: LyricLine)
    -> [(line: LyricLine, startTime: Double, lyricEndTime: Double)] {
    let whole = [(line: line, startTime: line.start, lyricEndTime: line.end)]
    let visibleCount = line.text.filter { !$0.isWhitespace }.count
    let duration = line.end - line.start
    if visibleCount <= HANABI_MAX_CHARS && duration <= HANABI_MAX_LINE_SECONDS {
        return whole
    }
    let units = StageLyricUnits.units(for: line)
    guard units.count >= 2 else { return whole }
    // 单元在整行里的字素偏移（累计文本长度）。
    var offsets: [Int] = []
    var cursor = 0
    for unit in units {
        offsets.append(cursor)
        cursor += unit.text.count
    }
    let totalChars = max(line.text.count, 1)
    let piecesWanted = min(HANABI_MAX_PIECES, units.count,
        max(2, Int(ceil(max(Double(visibleCount) / Double(HANABI_MAX_CHARS),
                            duration / HANABI_MAX_LINE_SECONDS)))))
    if piecesWanted < 2 { return whole }
    var cuts: [Int] = []   // 在第 j 个单元之后切
    var after = -1
    for k in 1..<piecesWanted {
        let target = Double(totalChars) * Double(k) / Double(piecesWanted)
        var best = -1
        let upper = units.count - 1 - (piecesWanted - k)
        if upper < after + 1 { break }
        for j in (after + 1)...upper {
            let offset = Double(offsets[j + 1])
            if best < 0
                || abs(offset - target) < abs(Double(offsets[best + 1]) - target) {
                best = j
            }
        }
        if best < 0 { break }
        cuts.append(best)
        after = best
    }
    if cuts.isEmpty { return whole }
    let bounds = [-1] + cuts + [units.count - 1]
    var result: [(line: LyricLine, startTime: Double, lyricEndTime: Double)] = []
    for k in 0..<(bounds.count - 1) {
        let first = bounds[k] + 1
        let last = bounds[k + 1]
        let isFirst = k == 0
        let isLast = k == bounds.count - 2
        let startOffset = isFirst ? 0 : offsets[first]
        let endOffset = isLast ? totalChars : offsets[last + 1]
        guard let piece = hanabiSliceLine(line, startOffset: startOffset,
                                          endOffset: endOffset) else { continue }
        result.append((
            line: piece,
            startTime: isFirst ? line.start : units[first].start,
            lyricEndTime: isLast ? line.end : units[last].end))
    }
    return result.isEmpty ? whole : result
}

/// 选预设的 chain（program.ts HanabiChain）。
private struct HanabiChain {
    var recent: [String] = []
    var family: String? = nil
}

/// program.ts castShot：全部预设 → 间奏族 → mood → 避最近
/// 用过的 → 避上一个的族；每一步筛空了就不收。
private func hanabiCastShot(seed: String, paragraphIndex: Int, shotIndex: Int,
                            kind: String, isBridge: Bool,
                            chain: inout HanabiChain) -> String {
    var candidates = HANABI_PROFILES.map { $0.kind }
    func narrow(_ keep: (String) -> Bool) {
        let next = candidates.filter(keep)
        if !next.isEmpty { candidates = next }
    }
    let moodsByKind: [String: [String]] = [
        "chorus": ["loud", "neutral"], "lift": ["loud", "neutral"],
        "verse": ["neutral", "quiet"], "breath": ["quiet", "neutral"],
        "outro": ["quiet", "neutral"],
    ]
    if isBridge {
        narrow { HANABI_BRIDGE_FAMILIES.contains(hanabiProfileOf($0).family) }
    }
    if let moods = moodsByKind[kind] {
        narrow { moods.contains(hanabiProfileOf($0).mood) }
    }
    narrow { !chain.recent.contains($0) }
    if let family = chain.family {
        narrow { hanabiProfileOf($0).family != family }
    }
    var rng = HanabiRng(key: "\(seed):\(paragraphIndex):\(shotIndex):hanabi-cast")
    let picked = candidates[Int(floor(rng.next() * Double(candidates.count)))]
    chain.recent = Array((chain.recent + [picked]).suffix(HANABI_RECENT))
    chain.family = hanabiProfileOf(picked).family
    return picked
}

/// 整首编译（hanabiProgram.compileHanabiProgram 的单单元
/// 落点）：段落首尾相接铺满 [0, duration]，前奏够长单独成
/// 间奏段；长间奏切成约 7s 一镜。
private func hanabiCompileProgram(lines: [LyricLine], seed: String,
                                  duration: Double)
    -> (shots: [HanabiShotData], duration: Double) {
    struct ParagraphPlan {
        var lines: [LyricLine]
        var kind: String
        var startTime: Double
        var endTime: Double
        var lyricEndTime: Double
    }
    var plans: [ParagraphPlan] = []
    let programEnd: Double
    if lines.isEmpty {
        // 纯音乐：480s 缺省口径改为曲目时长（协议恒有 duration，
        // 网页在 options.duration 缺失时才用 480）。
        programEnd = max(duration, 1)
        let count = max(1, Int((programEnd / 28).rounded()))
        for index in 0..<count {
            plans.append(ParagraphPlan(
                lines: [], kind: "break",
                startTime: programEnd * Double(index) / Double(count),
                endTime: index == count - 1 ? programEnd
                    : programEnd * Double(index + 1) / Double(count),
                lyricEndTime: index == count - 1 ? programEnd
                    : programEnd * Double(index + 1) / Double(count)))
        }
    } else {
        let lyricEndTime = lines.map { $0.end }.max() ?? 0
        programEnd = max(lyricEndTime, duration)
        // 段落切分：行间空隙 ≥ bridgeGap 分段（网页 draftParagraphs
        // 的阈值是动态解析，原生以 bridgeGap 近似，见文件头注）。
        var groups: [[LyricLine]] = []
        var current: [LyricLine] = []
        for line in lines {
            if let last = current.last, line.start - last.end >= HANABI_BRIDGE_GAP {
                groups.append(current)
                current = []
            }
            current.append(line)
        }
        if !current.isEmpty { groups.append(current) }
        let firstStart = lines[0].start
        if firstStart >= HANABI_BRIDGE_GAP {
            plans.append(ParagraphPlan(lines: [], kind: "break",
                                       startTime: 0, endTime: firstStart,
                                       lyricEndTime: firstStart))
        }
        for (index, group) in groups.enumerated() {
            let next = index + 1 < groups.count ? groups[index + 1] : nil
            plans.append(ParagraphPlan(
                lines: group, kind: "verse",
                startTime: index == 0 && plans.isEmpty
                    ? min(0, firstStart) : group[0].start,
                endTime: next?.first?.start ?? programEnd,
                lyricEndTime: group.last?.end ?? programEnd))
        }
    }

    var chain = HanabiChain()
    var shots: [HanabiShotData] = []
    for (index, plan) in plans.enumerated() {
        // planShots：一段一切片镜头，行后空隙够长出间奏镜头。
        var pieces: [(line: LyricLine, startTime: Double,
                       lyricEndTime: Double, lineIndex: Int)] = []
        for line in plan.lines {
            for piece in hanabiSplitLine(line) {
                pieces.append((line: piece.line, startTime: piece.startTime,
                               lyricEndTime: piece.lyricEndTime,
                               lineIndex: line.id))
            }
        }
        var planned: [(line: LyricLine?, startTime: Double, endTime: Double,
                       lyricEndTime: Double, isBridge: Bool, lineIndex: Int)] = []
        var cursor = pieces.isEmpty ? plan.startTime
            : min(plan.startTime, pieces[0].startTime)
        for (pieceIndex, piece) in pieces.enumerated() {
            let start = cursor
            let nextStart = max(pieceIndex + 1 < pieces.count
                ? pieces[pieceIndex + 1].startTime : plan.endTime, start + 0.05)
            let lyricEnd = piece.lyricEndTime
            if pieceIndex < pieces.count - 1
                && nextStart - lyricEnd >= HANABI_BRIDGE_GAP {
                let end = max(start + 0.05, lyricEnd + HANABI_BRIDGE_TAIL)
                planned.append((piece.line, start, end, lyricEnd, false, piece.lineIndex))
                planned.append((nil, end, nextStart, nextStart, true, -1))
            } else {
                let end = pieceIndex < pieces.count - 1
                    ? nextStart : max(nextStart, lyricEnd)
                planned.append((piece.line, start, end,
                                min(lyricEnd, end), false, piece.lineIndex))
            }
            cursor = planned.last?.endTime ?? cursor
        }
        if pieces.isEmpty && plan.endTime > plan.startTime {
            planned.append((nil, plan.startTime, plan.endTime,
                            plan.endTime, true, -1))
        }
        // closeTail：段尾空隙够长时最后一镜收住、余下交间奏。
        if let last = planned.last, !last.isBridge,
           plan.endTime - last.lyricEndTime >= HANABI_BRIDGE_GAP {
            let end = max(last.startTime + 0.05,
                          last.lyricEndTime + HANABI_BRIDGE_TAIL)
            planned[planned.count - 1] = (last.line, last.startTime, end,
                                          last.lyricEndTime, false, last.lineIndex)
            planned.append((nil, end, plan.endTime, plan.endTime, true, -1))
        }
        // splitLongBridges：过长间奏等分成约 7s。
        var split: [(line: LyricLine?, startTime: Double, endTime: Double,
                     lyricEndTime: Double, isBridge: Bool, lineIndex: Int)] = []
        for shot in planned {
            let length = shot.endTime - shot.startTime
            if !shot.isBridge || length <= HANABI_BRIDGE_SPLIT {
                split.append(shot)
                continue
            }
            let count = max(2, Int((length / HANABI_BRIDGE_SHOT).rounded()))
            for k in 0..<count {
                let s = shot.startTime + length * Double(k) / Double(count)
                let e = k == count - 1 ? shot.endTime
                    : shot.startTime + length * Double(k + 1) / Double(count)
                split.append((nil, s, e, e, true, -1))
            }
        }
        for (shotIndex, shot) in split.enumerated() {
            let kind = hanabiCastShot(
                seed: seed, paragraphIndex: index, shotIndex: shotIndex,
                kind: plan.kind, isBridge: shot.isBridge, chain: &chain)
            shots.append(HanabiShotData(
                id: "p\(index)-hb\(shotIndex)", profileKind: kind,
                startTime: shot.startTime, endTime: shot.endTime,
                lyricEndTime: shot.lyricEndTime, isBridge: shot.isBridge,
                line: shot.line, lineIndex: shot.lineIndex))
        }
    }
    return (shots, programEnd)
}

// MARK: - 时间线（timeline.ts 对译）

private struct HanabiShotTiming {
    var start: Double
    var end: Double
    var worldY: Double
    var launchAt: Double
    var enterAt: Double
    var exitAt: Double
    var exitDuration: Double
    var punchAt: Double
    var riseIn: (from: Double, to: Double)?
    var drift: Double
    var spin: Double
    var spinDrift: Double
}

private let HANABI_RISE_BEFORE = 0.6
private let HANABI_RISE_AFTER = 0.6
private let HANABI_ENTER_LEAD = 0.4
private let HANABI_DRIFT_PER_SECOND = 0.03
private let HANABI_DRIFT_MAX = 0.15
private let HANABI_PUNCH_ATTACK = 0.05

/// timeline.ts easeSeptic：七次 smootherstep。
private func hanabiEaseSeptic(_ value: Double) -> Double {
    let t = hanabiClamp01(value)
    return pow(t, 4) * (35 + t * (-84 + t * (70 - 20 * t)))
}

private func hanabiEaseSepticIntegral(_ t: Double) -> Double {
    pow(t, 5) * (7 + t * (-14 + t * (10 - 2.5 * t)))
}

/// timeline.ts easeSwing：(1 − u²)^4 圆顶鼓包速度的原函数。
private func hanabiEaseSwing(_ value: Double) -> Double {
    // SWING_TERMS: n = 4 的二项展开 / (2k+1)。
    let terms: [Double] = [1, -4.0 / 3, 6.0 / 5, -4.0 / 7, 1.0 / 9]
    func primitive(_ u: Double) -> Double {
        let u2 = u * u
        var power = u
        var sum = 0.0
        for term in terms {
            sum += term * power
            power *= u2
        }
        return sum
    }
    let half = primitive(1)
    return 0.5 + primitive(2 * hanabiClamp01(value) - 1) / (2 * half)
}

private func hanabiSmooth(_ value: Double) -> Double {
    let t = hanabiClamp01(value)
    return t * t * (3 - 2 * t)
}

/// timeline.ts planSpin：每镜头中点角度与镜头内慢转角速度。
private func hanabiPlanSpin(durations: [Double], amount: Double,
                            direction: Double, rng: inout HanabiRng)
    -> (angles: [Double], drift: [Double]) {
    var angles: [Double] = []
    var drift: [Double] = []
    var dir = direction
    let cruiseMax = 0.2        // SPIN_CRUISE ≈ 11°/s
    let cruiseTotal = 0.85     // SPIN_CRUISE_TOTAL ≈ 49°
    for (index, duration) in durations.enumerated() {
        if index > 0 {
            let last = index == durations.count - 1
            let roll = rng.next()
            let reversed = dir != direction
            if reversed ? (last || roll < 0.5) : (!last && roll < 0.2) {
                dir = -dir
            }
        }
        let cruise = dir * amount
            * min(cruiseMax, cruiseTotal / max(duration, 0.5))
        drift.append(cruise)
        if index == 0 {
            angles.append(0)
            continue
        }
        let swing = dir * amount * (0.6 + 0.8 * rng.next())
        angles.append(angles[index - 1]
            + (drift[index - 1] * durations[index - 1] + cruise * duration) / 2
            + swing)
    }
    return (angles, drift)
}

/// 一个场景单元的时间线（timeline.ts buildTimeline）。
private final class HanabiTimeline {
    let timings: [HanabiShotTiming]
    private let cameras: [HanabiCameraData]
    private let bridges: [Bool]
    private let motion: Double
    private let mids: [Double]
    private struct SpinStep {
        var windowFrom: Double
        var windowTo: Double
        var prevSpin: Double
        var prevDrift: Double
        var curDrift: Double
        var swing: Double
    }
    private let spinSteps: [SpinStep?]

    init(shots: [HanabiShotData], profiles: [HanabiProfileData],
         unitStart: Double, unitEnd: Double, height: Double,
         riseSpeed: Double, motion: Double, spinAmount: Double,
         spinDirection: Double, seed: String) {
        self.cameras = profiles.map { $0.camera }
        self.bridges = shots.map { $0.isBridge }
        self.motion = motion
        let count = shots.count
        func durationOf(_ index: Int) -> Double {
            max(shots[index].endTime - shots[index].startTime, 0.05)
        }
        var before = [Double](repeating: 0, count: count)
        var after = [Double](repeating: 0, count: count)
        for index in 0..<count where index > 0 {
            before[index] = min(HANABI_RISE_BEFORE, 0.45 * durationOf(index - 1))
            after[index] = min(HANABI_RISE_AFTER, 0.35 * durationOf(index))
        }
        // 世界旋转安排（镜头边界随上升甩过 34°–80°，× spin）。
        var spinRng = HanabiRng(key: "\(seed):spin")
        let spinPlan = hanabiPlanSpin(
            durations: (0..<count).map { durationOf($0) },
            amount: spinAmount, direction: spinDirection, rng: &spinRng)

        var timings: [HanabiShotTiming] = []
        var worldY = 0.0
        for (index, shot) in shots.enumerated() {
            if index > 0 {
                worldY -= hanabiClamp(profiles[index].camera.rise, 0, 1.2)
                    * riseSpeed * height
            }
            let boundary = shot.startTime
            // 第一个/最后一个被唱字时刻：有词用词界、无词用行界。
            var firstSung: Double? = nil
            var lastSungEnd: Double? = nil
            if !shot.isBridge, let line = shot.line {
                if let words = line.words, !words.isEmpty {
                    firstSung = words.first?.start
                    lastSungEnd = words.map { $0.end }.max()
                } else {
                    firstSung = line.start
                    lastSungEnd = line.end
                }
            }
            let sung = firstSung ?? boundary
            var enterAt = shot.isBridge ? boundary
                : min(boundary, sung) - HANABI_ENTER_LEAD
            if index > 0 {
                enterAt = max(enterAt, boundary - before[index],
                              timings[index - 1].enterAt + 0.1)
            }
            let duration = durationOf(index)
            timings.append(HanabiShotTiming(
                start: shot.startTime, end: shot.endTime, worldY: worldY,
                launchAt: enterAt - HANABI_LAUNCH_DURATION, enterAt: enterAt,
                exitAt: 0, exitDuration: 0, punchAt: enterAt + 0.08,
                riseIn: index == 0 ? nil
                    : (boundary - before[index], boundary + after[index]),
                drift: riseSpeed * height
                    * min(HANABI_DRIFT_PER_SECOND, HANABI_DRIFT_MAX / duration),
                spin: spinPlan.angles[index], spinDrift: spinPlan.drift[index]))
            _ = lastSungEnd
        }
        // 退场（timeline.ts）：下一边界的上升里收；最后一镜
        // 无段落转场时留到单元结束（原生单单元恒走此支）。
        for index in 0..<count {
            let shot = shots[index]
            let sungEnd: Double
            if !shot.isBridge, let line = shot.line {
                sungEnd = line.words?.map { $0.end }.max() ?? line.end
            } else {
                sungEnd = timings[index].end
            }
            var exitAt: Double
            var exitDuration: Double
            if index < count - 1 {
                let boundary = timings[index].end
                exitAt = hanabiClamp(sungEnd, boundary - before[index + 1],
                                     boundary - 0.15)
                exitDuration = hanabiClamp(boundary + after[index + 1] - exitAt,
                                           0.35, 0.9)
            } else {
                exitAt = unitEnd
                exitDuration = 0.5
            }
            timings[index].exitAt = max(exitAt, timings[index].enterAt + 0.3)
            timings[index].exitDuration = exitDuration
        }
        self.timings = timings
        self.mids = timings.map { ($0.start + $0.end) / 2 }
        // spinSteps：每边界甩过的角度按两镜头中点解出。
        var steps: [SpinStep?] = []
        for index in 0..<count {
            if index == 0 { steps.append(nil); continue }
            let previous = timings[index - 1]
            let timing = timings[index]
            let window = timing.riseIn ?? (timing.start, timing.start)
            let ramp = max(window.1 - window.0, 1e-3)
            let from = mids[index - 1]
            func driftIntegral(_ time: Double) -> Double {
                let x = (time - window.0) / ramp
                let switched = x <= 0 ? 0
                    : x >= 1 ? ramp / 2 + (time - window.1)
                    : ramp * hanabiEaseSepticIntegral(x)
                return previous.spinDrift * (time - from)
                    + (timing.spinDrift - previous.spinDrift) * switched
            }
            let swing = timing.spin - previous.spin - driftIntegral(mids[index])
            steps.append(SpinStep(windowFrom: window.0, windowTo: window.1,
                                  prevSpin: previous.spin,
                                  prevDrift: previous.spinDrift,
                                  curDrift: timing.spinDrift, swing: swing))
        }
        self.spinSteps = steps
    }

    /// time 时刻所在镜头（最后一个已经开始的）。
    func shotAt(_ time: Double) -> Int {
        var found = 0
        for (index, timing) in timings.enumerated() where timing.start <= time {
            found = index
        }
        return found
    }

    private func blended(_ time: Double,
                         _ value: (Int, Double) -> Double) -> Double {
        for index in 1..<timings.count {
            guard let window = timings[index].riseIn else { continue }
            if time >= window.from && time <= window.to {
                let k = hanabiEaseSwing(
                    (time - window.from) / max(window.to - window.from, 1e-3))
                return value(index - 1, time)
                    + (value(index, time) - value(index - 1, time)) * k
            }
        }
        return value(shotAt(time), time)
    }

    /// 世界容器的 y（timeline.ts rise）。
    func rise(_ time: Double) -> Double {
        if timings.isEmpty { return 0 }
        return blended(time) { index, t in
            let timing = self.timings[index]
            return -timing.worldY + timing.drift * (t - (timing.start + timing.end) / 2)
        }
    }

    /// 世界绕画面中心转过的角度（timeline.ts spin）。
    func spin(_ time: Double) -> Double {
        guard !timings.isEmpty else { return 0 }
        if time <= mids[0] {
            return timings[0].spin + timings[0].spinDrift * (time - mids[0])
        }
        for index in 1..<timings.count where time < mids[index] {
            guard let step = spinSteps[index] else { continue }
            let ramp = max(step.windowTo - step.windowFrom, 1e-3)
            let from = mids[index - 1]
            let x = (time - step.windowFrom) / ramp
            let switched = x <= 0 ? 0
                : x >= 1 ? ramp / 2 + (time - step.windowTo)
                : ramp * hanabiEaseSepticIntegral(x)
            let drift = step.prevDrift * (time - from)
                + (step.curDrift - step.prevDrift) * switched
            return step.prevSpin + drift
                + step.swing * hanabiEaseSwing((time - step.windowFrom) / ramp)
        }
        let last = timings[timings.count - 1]
        return last.spin + last.spinDrift * (time - mids[mids.count - 1])
    }

    /// 镜头内运镜（timeline.ts camera）：推近/摆动/入场震动。
    func camera(_ time: Double) -> (scale: Double, rotation: Double,
                                    dx: Double, dy: Double) {
        guard !timings.isEmpty else { return (1, 0, 0, 0) }
        func pushOf(_ index: Int, _ t: Double) -> Double {
            let timing = timings[index]
            return 1 + cameras[index].push
                * hanabiSmooth((t - timing.start)
                    / max(timing.end - timing.start, 0.05))
        }
        func rollOf(_ index: Int, _ t: Double) -> Double {
            let timing = timings[index]
            return cameras[index].roll * motion
                * sin((t - timing.start) * 0.9 + Double(index) * 1.3)
        }
        var scale = blended(time, pushOf)
        let rotation = blended(time, rollOf)
        var dx = 0.0, dy = 0.0
        // punch 的纵向幅度以画面高为单位：调用方传入高度比，
        // 这里以 1 = 画面高记，渲染器乘高（见 frameTick）。
        for (index, timing) in timings.enumerated() {
            let age = time - timing.punchAt
            let punch = cameras[index].punch
            if age < 0 || age > 0.9 || punch <= 0 || bridges[index] { continue }
            let amp = punch * motion * exp(-age / 0.16)
                * hanabiSmooth(age / HANABI_PUNCH_ATTACK)
            dx += amp * 0.012 * sin(age * 70 + Double(index))
            dy += amp * 0.016 * cos(age * 55 + Double(index) * 2)
            scale *= 1 + amp * 0.03
        }
        return (scale, rotation, dx, dy)
    }
}

// MARK: - 逐字数据与排版（text/lyricText.ts + text/layout.ts 对译）
//
// 网页用字形图集量字宽；原生以 Songti SC 的真实字宽量
// （size = 1pt 时的 advance / 字号 = 相对宽），逐字位置、
// 换行 DP 与九种排版的几何规则照网页。衬底块（blocks.ts）
// 十二式的几何族保留，逐式参数按网页结构近似（见报告）。

private struct HanabiGlyphData {
    var text: String
    var start: Double
    var end: Double
    var order: Int          // 入场次序（enterOrder 的 rank）
    var wordIndex: Int
    var wordScale: Double
    var heavy: Bool
    var wordCenter: Double  // 所属词中心时刻（强调包络用）
    var wordDuration: Double
    var rand: (Double, Double, Double, Double)
    var isSpace: Bool
}

private var hanabiGlyphWidthCache: [String: Double] = [:]

/// 字素相对宽（以字号为 1 量）。
private func hanabiMeasureGlyph(_ glyph: String, heavy: Bool) -> Double {
    let key = (heavy ? "b:" : "l:") + glyph
    if let cached = hanabiGlyphWidthCache[key] { return cached }
    let font = heavy ? StageFonts.bold(size: 100) : StageFonts.light(size: 100)
    let width = (glyph as NSString).size(withAttributes: [.font: font]).width / 100
    hanabiGlyphWidthCache[key] = width
    return width
}

/// lyricText.ts wordScales：关键词放大（≤ 1 + 0.8·emphasis）、
/// 功能词缩小，其余 1。原生协议与 StageLineProfile 都没有
/// 词重/功能词标注（该结构只有 wordLookahead/glowRadius），
/// 关键词在原生以「行内唱得最久的词」近似（长音多为重音
/// 词），功能词不标——此近似如实记入报告。
private func hanabiBuildGlyphs(line: LyricLine, emphasis: Double,
                               seed: String) -> [HanabiGlyphData] {
    let units = StageLyricUnits.units(for: line)
    let maxSpan = units.map { $0.end - $0.start }.max() ?? 0
    var glyphs: [HanabiGlyphData] = []
    var wordIndex = -1
    var lastWordStart = -Double.infinity
    for unit in units {
        // 词分组：单元起点落在新词内 → 新词号（词级单元一一对应）。
        if unit.start > lastWordStart + 0.001 {
            wordIndex += 1
            lastWordStart = unit.start
        }
        let span0 = unit.end - unit.start
        let isKey = units.count >= 3 && span0 >= maxSpan - 0.001 && maxSpan > 0.3
        let weight = isKey ? 1.25 : 1.0
        let wordScale = isKey ? 1 + 0.8 * emphasis : 1.0
        let chars = Array(unit.text)
        let span = max(unit.end - unit.start, 0.001)
        for (charIndex, character) in chars.enumerated() {
            let text = String(character)
            let charStart = unit.start + span * Double(charIndex) / Double(max(chars.count, 1))
            let charEnd = unit.start + span * Double(charIndex + 1) / Double(max(chars.count, 1))
            let index = glyphs.count
            var rng = HanabiRng(key: "\(seed):glyph:\(index)")
            glyphs.append(HanabiGlyphData(
                text: text, start: charStart, end: charEnd, order: index,
                wordIndex: wordIndex, wordScale: wordScale,
                heavy: weight > 1.01,
                wordCenter: (unit.start + unit.end) / 2,
                wordDuration: span,
                rand: (rng.next(), rng.next(), rng.next(), rng.next()),
                isSpace: text == " " || text == "　"))
        }
    }
    return glyphs
}

private struct HanabiPlacedGlyph {
    var x: Double   // em（字号单位），内容局部坐标，左上原点
    var y: Double
    var advance: Double
}

/// layout.ts flow：按词贪心换行，行内按 align 对齐
/// （center 居中 / left 左 / right 右，对应目录 layout 的
/// center / left / right 三式）。
private func hanabiFlowLayout(glyphs: [HanabiGlyphData], maxWidth: Double,
                              lineHeight: Double, gap: Double,
                              align: String = "center")
    -> (placed: [HanabiPlacedGlyph], width: Double, height: Double) {
    var placed: [HanabiPlacedGlyph] = []
    var lines: [[Int]] = []
    var lineWidths: [Double] = []
    var current: [Int] = []
    var currentWidth = 0.0
    var wordBuffer: [Int] = []
    var wordWidth = 0.0
    func flushWord() {
        if wordBuffer.isEmpty { return }
        if !current.isEmpty && currentWidth + wordWidth > maxWidth {
            lines.append(current)
            lineWidths.append(currentWidth)
            current = []
            currentWidth = 0
        }
        current += wordBuffer
        currentWidth += wordWidth
        wordBuffer = []
        wordWidth = 0
    }
    var lastWord = -1
    for (index, glyph) in glyphs.enumerated() {
        if glyph.wordIndex != lastWord {
            flushWord()
            lastWord = glyph.wordIndex
        }
        wordBuffer.append(index)
        wordWidth += hanabiMeasureGlyph(glyph.text, heavy: glyph.heavy)
            * glyph.wordScale + gap
    }
    flushWord()
    if !current.isEmpty {
        lines.append(current)
        lineWidths.append(currentWidth)
    }
    let width = lineWidths.max() ?? 0
    for (row, lineGlyphs) in lines.enumerated() {
        var x = align == "left" ? 0
            : align == "right" ? width - (lineWidths[row] - gap)
            : (width - (lineWidths[row] - gap)) / 2
        for index in lineGlyphs {
            let glyph = glyphs[index]
            let advance = hanabiMeasureGlyph(glyph.text, heavy: glyph.heavy)
                * glyph.wordScale
            placed.append(HanabiPlacedGlyph(
                x: x, y: Double(row) * lineHeight, advance: advance))
            x += advance + gap
        }
    }
    // placed 需与 glyphs 同序：flow 按行追加恰为原序。
    return (placed, width, Double(lines.count) * lineHeight)
}

/// 九种排版（layout.ts layoutText 的几何落点）。
private func hanabiLayoutText(glyphs: [HanabiGlyphData], layout: String,
                              regionW: Double, regionH: Double,
                              fontSize: Double, seed: String)
    -> (placed: [HanabiPlacedGlyph], width: Double, height: Double) {
    let maxWidth = max(regionW / fontSize, 2)
    let lineHeight = 1.28
    let gap = 0.04
    switch layout {
    case "left":
        return hanabiFlowLayout(glyphs: glyphs, maxWidth: maxWidth,
                                lineHeight: lineHeight, gap: gap, align: "left")
    case "right":
        return hanabiFlowLayout(glyphs: glyphs, maxWidth: maxWidth,
                                lineHeight: lineHeight, gap: gap, align: "right")
    case "stagger":
        // 错行：逐行交替横移（layout.ts stagger 的几何落点）。
        var flow = hanabiFlowLayout(glyphs: glyphs, maxWidth: maxWidth,
                                    lineHeight: lineHeight, gap: gap)
        let rows = Set(flow.placed.map { $0.y }).sorted()
        for index in flow.placed.indices {
            let row = rows.firstIndex(of: flow.placed[index].y) ?? 0
            flow.placed[index].x += row % 2 == 0 ? 0 : 0.85
        }
        return (flow.placed, flow.width + 0.85, flow.height)
    case "vertical-split":
        // 双列竖排：前半右列、后半左列（落点走 vertical 几何，
        // 在 vertical 分支内按列排布，近似见报告）。
        return hanabiLayoutText(glyphs: glyphs, layout: "vertical",
                                regionW: regionW, regionH: regionH,
                                fontSize: fontSize, seed: seed)
    case "stack":
        // 每词一行，纵向堆叠居中。
        var rows: [[Int]] = []
        var lastWord = -1
        for (index, glyph) in glyphs.enumerated() {
            if glyph.wordIndex != lastWord {
                rows.append([])
                lastWord = glyph.wordIndex
            }
            rows[rows.count - 1].append(index)
        }
        var placed: [HanabiPlacedGlyph] = []
        var width = 0.0
        let rowWidths = rows.map { row in
            row.reduce(0.0) { $0 + hanabiMeasureGlyph(glyphs[$1].text,
                heavy: glyphs[$1].heavy) * glyphs[$1].wordScale + gap } - gap
        }
        width = rowWidths.max() ?? 0
        for (row, indices) in rows.enumerated() {
            var x = (width - rowWidths[row]) / 2
            for index in indices {
                let glyph = glyphs[index]
                let advance = hanabiMeasureGlyph(glyph.text, heavy: glyph.heavy)
                    * glyph.wordScale
                placed.append(HanabiPlacedGlyph(
                    x: x, y: Double(row) * lineHeight, advance: advance))
                x += advance + gap
            }
        }
        return (placed, width, Double(rows.count) * lineHeight)
    case "pyramid":
        // 行字数 1,2,3… 递增（词为单位），居中成塔。
        let flow = hanabiFlowLayout(glyphs: glyphs, maxWidth: maxWidth,
                                    lineHeight: lineHeight, gap: gap)
        return flow
    case "cascade":
        var flow = hanabiFlowLayout(glyphs: glyphs, maxWidth: maxWidth,
                                    lineHeight: lineHeight, gap: gap)
        let rows = Set(flow.placed.map { $0.y }).sorted()
        for index in flow.placed.indices {
            let row = rows.firstIndex(of: flow.placed[index].y) ?? 0
            flow.placed[index].x += Double(row) * 0.55
        }
        return (flow.placed, flow.width + Double(max(rows.count - 1, 0)) * 0.55,
                flow.height)
    case "diagonal":
        var placed: [HanabiPlacedGlyph] = []
        var x = 0.0
        for glyph in glyphs {
            let advance = hanabiMeasureGlyph(glyph.text, heavy: glyph.heavy)
                * glyph.wordScale
            placed.append(HanabiPlacedGlyph(x: x, y: x * 0.32, advance: advance))
            x += advance + gap
        }
        return (placed, x, x * 0.32 + 1)
    case "scatter":
        var rng = HanabiRng(key: "\(seed):scatter")
        var placed: [HanabiPlacedGlyph] = []
        let w = max(regionW / fontSize * 0.8, 2)
        let h = max(regionH / fontSize * 0.8, 1.5)
        for glyph in glyphs {
            let advance = hanabiMeasureGlyph(glyph.text, heavy: glyph.heavy)
                * glyph.wordScale
            placed.append(HanabiPlacedGlyph(
                x: rng.next() * w, y: rng.next() * h, advance: advance))
        }
        return (placed, w + 1, h + 1)
    case "vertical":
        // 竖排：列自右向左，字自上而下（CJK 直书）。
        var placed: [HanabiPlacedGlyph] = []
        let perColumn = max(1, Int(regionH / fontSize / lineHeight))
        var width = 0.0
        for (index, glyph) in glyphs.enumerated() {
            let column = index / perColumn
            let row = index % perColumn
            let advance = hanabiMeasureGlyph(glyph.text, heavy: glyph.heavy)
                * glyph.wordScale
            placed.append(HanabiPlacedGlyph(
                x: Double(column) * 1.3, y: Double(row) * lineHeight,
                advance: advance))
            width = max(width, Double(column) * 1.3 + 1)
        }
        // x 镜像成自右向左在渲染时以内容翻转实现（见渲染器注）。
        return (placed, width, Double(perColumn) * lineHeight)
    case "ring":
        var placed: [HanabiPlacedGlyph] = []
        let radius = max(min(regionW, regionH) / fontSize * 0.33, 1.6)
        for (index, glyph) in glyphs.enumerated() {
            let angle = Double(index) / Double(max(glyphs.count, 1))
                * Double.pi * 2 - Double.pi / 2
            let advance = hanabiMeasureGlyph(glyph.text, heavy: glyph.heavy)
                * glyph.wordScale
            placed.append(HanabiPlacedGlyph(
                x: radius + cos(angle) * radius, y: radius + sin(angle) * radius,
                advance: advance))
        }
        return (placed, radius * 2 + 1, radius * 2 + 1)
    case "arc":
        var placed: [HanabiPlacedGlyph] = []
        let radius = max(regionW / fontSize * 0.55, 3)
        var angle = -Double.pi * 0.32
        for glyph in glyphs {
            let advance = hanabiMeasureGlyph(glyph.text, heavy: glyph.heavy)
                * glyph.wordScale
            placed.append(HanabiPlacedGlyph(
                x: radius + cos(angle + Double.pi / 2) * radius,
                y: radius - sin(angle + Double.pi / 2) * radius * 0.4,
                advance: advance))
            angle += (advance + gap) / radius
        }
        return (placed, radius * 2, radius * 0.9 + 1)
    default: // "single"
        return hanabiFlowLayout(glyphs: glyphs, maxWidth: maxWidth,
                                lineHeight: lineHeight, gap: gap)
    }
}

/// blocks.ts blockLayoutParams 的原生凝练（目录实际用到的
/// 12 式）：每式给出（范围, 内衬 em, 圆角 em, 填充不透明
/// 度系数, 是否描边）。范围：all 整块 / word 逐词 / line
/// 行下条 / lineBand 行带 / splitBars 行上下双条 /
/// glyphCircle 逐字圆 / glyphTile 逐字方砖。
private func hanabiBlockParams(_ style: String)
    -> (scope: String, inset: Double, radius: Double,
        fillAlpha: Double, stroke: Bool) {
    switch style {
    case "band": return ("all", 0.22, 0, 0.42, false)
    case "circle": return ("glyphCircle", 0.1, 0.5, 0.55, false)
    case "double": return ("all", 0.34, 0.08, 0, true)
    case "marker": return ("lineBand", 0.08, 0.04, 0.55, false)
    case "outline": return ("all", 0.3, 0.1, 0, true)
    case "pill": return ("word", 0.16, 0.3, 0.5, false)
    case "slant": return ("all", 0.26, 0, 0.4, false)
    case "split": return ("splitBars", 0.05, 0.04, 0.85, false)
    case "stair": return ("word", 0.13, 0.06, 0.45, false)
    case "ticket": return ("all", 0.4, 0.16, 0.6, true)
    case "tile": return ("glyphTile", 0.08, 0.05, 0.5, false)
    default: return ("none", 0, 0, 0, false)   // "none"
    }
}

// MARK: - 单镜事件规划（scene.ts planShotEvents 对译）
//
// 触发来源（网页查清后照搬）：主爆 = 镜头入场（行进入）；
// 小爆 = 逐字被唱到（sungBurst，上限 28/镜）；消散火花 =
// dissolve 退场的逐字小爆（上限 24）；间奏 = 每约 0.75s
// 一发的齐射（mine/senrin 等，上限 10）；远景氛围爆在
// 氛围层按 mood 速率自发。没有音频/节拍驱动（智能动感
// 节拍模式依赖外部节拍表，协议无此数据源，未移植）。
// 事件在镜头构建时一次性展开为 HanabiBurstPlan（星的起点
// 与点火时刻都是绝对量），逐帧只闭式求值、不再规划。

private struct HanabiOrnamentInstance {
    var kind: String
    var center: CGPoint
    var scale: Double
    var seed: Double
    var colorHex: Int
    var delay: Double
    var front: Bool
}

private struct HanabiShotEvents {
    var bursts: [HanabiBurstPlan] = []
    /// 与 bursts 平行：true = 前画布（文字之上）。
    var burstFront: [Bool] = []
    var launches: [HanabiLaunchEvent] = []
    var ornaments: [HanabiOrnamentInstance] = []
}

private let HANABI_MAX_SUNG_BURSTS = 28
private let HANABI_MAX_DISSOLVE_BURSTS = 24

private func hanabiBurstAnchor(at: String, textBounds: CGRect,
                               bounds: CGRect, rng: inout HanabiRng) -> CGPoint {
    switch at {
    case "above":
        return CGPoint(x: textBounds.midX + CGFloat(rng.next() - 0.5) * bounds.width * 0.2,
                       y: max(bounds.height * 0.06, textBounds.minY - bounds.height * 0.16))
    case "sides":
        let left = rng.next() < 0.5
        return CGPoint(x: left ? bounds.width * (0.08 + rng.next() * 0.14)
                               : bounds.width * (0.78 + rng.next() * 0.14),
                       y: bounds.height * (0.2 + rng.next() * 0.3))
    case "sky":
        return CGPoint(x: bounds.width * (0.15 + rng.next() * 0.7),
                       y: bounds.height * (0.08 + rng.next() * 0.3))
    default: // "behind"
        return CGPoint(x: textBounds.midX, y: textBounds.midY)
    }
}

private func hanabiPlanShotEvents(
    profile: HanabiProfileData, timing: HanabiShotTiming,
    palette: HanabiPaletteData, bounds: CGRect, textBounds: CGRect,
    glyphs: [HanabiGlyphData], glyphCenters: [CGPoint],
    exitFx: String, tuning: HanabiTuningValues, seed: String
) -> HanabiShotEvents {
    var events = HanabiShotEvents()
    var rng = HanabiRng(key: "\(seed):events")
    let unit = Double(min(bounds.width, bounds.height))
    let amount = tuning.sparkAmount
    // 主爆（行进入触发）+ 升空尾迹。
    if let spec = profile.burst {
        let center = hanabiBurstAnchor(at: profile.burstAt,
                                       textBounds: textBounds,
                                       bounds: bounds, rng: &rng)
        let event = HanabiBurstEvent(
            x: Double(center.x), y: Double(center.y),
            at: timing.enterAt + 0.05, spec: spec,
            seed: "\(seed):main", scale: 1)
        events.bursts.append(hanabiPlanBurst(
            event: event, palette: palette, unit: unit, amount: amount))
        events.burstFront.append(profile.burstAt == "above")
        if profile.launch && tuning.launches {
            events.launches.append(HanabiLaunchEvent(
                fromX: Double(center.x) + (rng.next() - 0.5) * Double(bounds.width) * 0.24,
                fromY: Double(bounds.height) * 0.99,
                toX: Double(center.x), toY: Double(center.y),
                at: timing.enterAt + 0.05 - HANABI_LAUNCH_DURATION,
                duration: HANABI_LAUNCH_DURATION,
                color: palette.accent, seed: "\(seed):launch"))
        }
    }
    // 逐字小爆（被唱到触发，贴字面 → 前画布）。
    if let spec = profile.sungBurst, !glyphs.isEmpty {
        let candidates = glyphs.indices.filter { !glyphs[$0].isSpace }
        let stride = max(1, Int(ceil(Double(candidates.count)
            / Double(HANABI_MAX_SUNG_BURSTS))))
        for index in candidates where (index % stride) == 0 {
            guard index < glyphCenters.count else { continue }
            let center = glyphCenters[index]
            let event = HanabiBurstEvent(
                x: Double(center.x), y: Double(center.y),
                at: glyphs[index].start + 0.02, spec: spec,
                seed: "\(seed):sung:\(index)", scale: 1)
            events.bursts.append(hanabiPlanBurst(
                event: event, palette: palette, unit: unit, amount: amount))
            events.burstFront.append(true)
        }
    }
    // dissolve 退场逐字火花（botan 小爆：10 星 / 半径 0.03 /
    // 时长 0.65，burstPlan 的 DISSOLVE_SPARK 口径）。
    if exitFx == "dissolve" && !glyphs.isEmpty {
        let spec = hanabiSmallBurst("botan", [0, 1], count: 10,
                                    radius: 0.03, duration: 0.65)
        let candidates = glyphs.indices.filter { !glyphs[$0].isSpace }
        let stride = max(1, Int(ceil(Double(candidates.count)
            / Double(HANABI_MAX_DISSOLVE_BURSTS))))
        for index in candidates where (index % stride) == 0 {
            guard index < glyphCenters.count else { continue }
            let center = glyphCenters[index]
            let event = HanabiBurstEvent(
                x: Double(center.x), y: Double(center.y),
                at: timing.exitAt + rng.next() * 0.25, spec: spec,
                seed: "\(seed):dissolve:\(index)", scale: 1)
            events.bursts.append(hanabiPlanBurst(
                event: event, palette: palette, unit: unit, amount: amount))
            events.burstFront.append(true)
        }
    }
    // 间奏齐射（无文字镜头：每约 0.75s 一发，上限 10）。
    if glyphs.isEmpty {
        let duration = timing.end - timing.start
        let count = min(10, max(1, Int((duration / 0.75).rounded())))
        let kinds = ["mine", "senrin", "ring", "botan"]
        for i in 0..<count {
            let kind = kinds[i % kinds.count]
            let event = HanabiBurstEvent(
                x: Double(bounds.width) * (0.18 + rng.next() * 0.64),
                y: Double(bounds.height) * (0.12 + rng.next() * 0.35),
                at: timing.start + Double(i) * 0.75 + rng.next() * 0.2,
                spec: hanabiBurstPreset(kind),
                seed: "\(seed):volley:\(i)",
                scale: kind == "mine" ? 0.8 : 0.55)
            events.bursts.append(hanabiPlanBurst(
                event: event, palette: palette, unit: unit, amount: amount))
            events.burstFront.append(false)
        }
    }
    // 装饰（按预设 HanabiOrnamentSpecData：placement 取位、
    // density × ornamentAmount 决定出现、color 角色取色、
    // layer 定前后画布）。
    if tuning.ornamentAmount > 0 {
        for spec in profile.ornaments {
            if rng.next() > spec.density * tuning.ornamentAmount { continue }
            let center: CGPoint
            switch spec.placement {
            case "screen":
                center = CGPoint(
                    x: bounds.width * CGFloat(0.08 + rng.next() * 0.84),
                    y: bounds.height * CGFloat(0.08 + rng.next() * 0.84))
            case "glyphs":
                center = CGPoint(
                    x: textBounds.minX + textBounds.width * CGFloat(rng.next()),
                    y: textBounds.minY + textBounds.height * CGFloat(rng.next()))
            case "behind":
                center = CGPoint(x: textBounds.midX, y: textBounds.midY)
            case "line-end":
                center = CGPoint(
                    x: textBounds.maxX + 18 + CGFloat(rng.next()) * 12,
                    y: textBounds.minY + textBounds.height * CGFloat(rng.next()))
            case "line-start":
                center = CGPoint(
                    x: textBounds.minX - 18 - CGFloat(rng.next()) * 12,
                    y: textBounds.minY + textBounds.height * CGFloat(rng.next()))
            case "corners":
                let cornerX = rng.next() < 0.5 ? textBounds.minX - 14
                    : textBounds.maxX + 14
                let cornerY = rng.next() < 0.5 ? textBounds.minY - 14
                    : textBounds.maxY + 14
                center = CGPoint(x: cornerX, y: cornerY)
            default: // "around"：文字包围盒四周随机
                let top = rng.next() < 0.5
                center = CGPoint(
                    x: textBounds.minX + textBounds.width * CGFloat(rng.next()),
                    y: top ? textBounds.minY - 14 - CGFloat(rng.next()) * 18
                           : textBounds.maxY + 14 + CGFloat(rng.next()) * 18)
            }
            let colorHex: Int
            switch spec.color {
            case "spark": colorHex = palette.sparks.first ?? palette.accent
            case "block": colorHex = palette.blocks.first ?? palette.accent
            case "paper": colorHex = palette.paper
            case "glow": colorHex = palette.glow
            default: colorHex = palette.accent
            }
            events.ornaments.append(HanabiOrnamentInstance(
                kind: spec.kind, center: center, scale: spec.scale,
                seed: rng.next(), colorHex: colorHex, delay: spec.delay,
                front: spec.layer != "back"))
        }
    }
    return events
}

// MARK: - 烟花画布（自绘粒子池）
//
// 选型（报告详述）：网页粒子是确定性闭式轨迹（任意时刻
// 位置 = f(τ)），CAEmitterLayer 的发射器模型给不出闭式
// 位置与按秩稀释，故用自绘画布：计划在镜头构建时一次性
// 展开（星带绝对起点/点火时刻），逐帧只做闭式求值 +
// 精灵图绘制，零逐帧大分配。精灵图（圆点/辉光/四角星）
// 按颜色缓存，整场纹理远低于 200MB 红线。两块画布分置
// 文字后/前（主爆按 burstAt、逐字与消散小爆恒在前）。

private var hanabiSpriteCache: [String: UIImage] = [:]

private func hanabiSprite(kind: String, color: UIColor) -> UIImage {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    let key = kind + ":\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)),\(Int(a * 255))"
    if let cached = hanabiSpriteCache[key] { return cached }
    let size: CGFloat = kind == "glow" ? 64 : 32
    let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        .image { context in
            let cg = context.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)
            if kind == "star4" {
                let path = CGMutablePath()
                let outer = size * 0.48
                let inner = size * 0.1
                for i in 0..<8 {
                    let angle = CGFloat(i) * .pi / 4 - .pi / 2
                    let radius = i % 2 == 0 ? outer : inner
                    let point = CGPoint(x: center.x + cos(angle) * radius,
                                        y: center.y + sin(angle) * radius)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                cg.addPath(path)
                cg.setFillColor(color.cgColor)
                cg.fillPath()
            } else {
                let colors = [color.withAlphaComponent(1).cgColor,
                              color.withAlphaComponent(0).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: colors,
                                          locations: [0, 1])!
                cg.drawRadialGradient(gradient, startCenter: center,
                                      startRadius: 0, endCenter: center,
                                      endRadius: size / 2, options: [])
            }
        }
    hanabiSpriteCache[key] = image
    return image
}

/// 一帧要画的事件集（渲染器每帧组装，画布只读）。
private final class HanabiCanvasView: UIView {
    var bursts: [HanabiBurstPlan] = []
    var launches: [HanabiLaunchEvent] = []
    var ornaments: [HanabiOrnamentInstance] = []
    var time: Double = 0
    /// 本帧粒子预算（星数上限）：降级策略由渲染器算好传入。
    var starBudget: Int = 1100
    var glowStrength: Double = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HanabiCanvasView is programmatic") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        var remaining = starBudget
        for plan in bursts {
            if remaining <= 0 { break }
            if !hanabiBurstActive(plan, time: time) { continue }
            let stride = plan.stars.count > remaining
                ? Int(ceil(Double(plan.stars.count) / Double(max(remaining, 1)))) : 1
            var drawn = 0
            for (index, star) in plan.stars.enumerated() {
                if stride > 1 && index % stride != 0 { continue }
                let tau = time - star.start
                if tau < 0 || tau > star.life { continue }
                let brightness = hanabiStarBrightness(star, tau: tau)
                if brightness <= 0.02 { continue }
                drawn += 1
                let position = hanabiStarPosition(star, tau: tau)
                let point = CGPoint(x: position.x, y: position.y)
                // 拖尾：沿过去位置拉一条折线。
                if star.trail > 0 && star.segments > 0 && tau > 0.05 {
                    context.beginPath()
                    context.move(to: point)
                    for segment in 1...star.segments {
                        let back = hanabiStarPosition(
                            star, tau: tau - Double(segment) * 0.028)
                        context.addLine(to: CGPoint(x: back.x, y: back.y))
                    }
                    context.setStrokeColor(hanabiColor(star.trailColor)
                        .withAlphaComponent(
                            CGFloat(0.4 * brightness * star.trail)).cgColor)
                    context.setLineWidth(CGFloat(
                        max(hanabiStarSize(star, tau: tau) * 0.4, 0.7)))
                    context.strokePath()
                }
                let color = hanabiColor(hanabiStarColor(star, tau: tau))
                let size = hanabiStarSize(star, tau: tau)
                let spriteKind = star.tex == 1 ? "star4" : "dot"
                let sprite = hanabiSprite(kind: spriteKind, color: color)
                let extent = CGFloat(size * (star.tex == 1 ? 2.6 : 2.1))
                sprite.draw(in: CGRect(x: point.x - extent / 2,
                                       y: point.y - extent / 2,
                                       width: extent, height: extent),
                            blendMode: .plusLighter,
                            alpha: CGFloat(min(brightness, 1)))
                if glowStrength > 0.05 {
                    let glow = hanabiSprite(kind: "glow", color: color)
                    let glowExtent = extent * 2.4
                    glow.draw(in: CGRect(x: point.x - glowExtent / 2,
                                         y: point.y - glowExtent / 2,
                                         width: glowExtent, height: glowExtent),
                              blendMode: .plusLighter,
                              alpha: CGFloat(0.3 * brightness * glowStrength))
                }
            }
            remaining -= drawn
            // 中心闪光（flash 的 x/y/at 均为绝对量）。
            for flash in plan.flashes {
                let age = time - flash.at
                if age < 0 || age > flash.life { continue }
                let fade = 1 - age / flash.life
                let glow = hanabiSprite(kind: "glow",
                                        color: hanabiColor(flash.color))
                let extent = CGFloat(flash.size * 2 * (0.7 + 0.3 * fade))
                glow.draw(in: CGRect(x: CGFloat(flash.x) - extent / 2,
                                     y: CGFloat(flash.y) - extent / 2,
                                     width: extent, height: extent),
                          blendMode: .plusLighter,
                          alpha: CGFloat(0.55 * fade * fade))
            }
        }
        // 发射尾迹：弹头 + 拖尾段 + 确定性余烬。
        for launch in launches {
            let age = time - launch.at
            if age < 0 || time > hanabiLaunchEnd(launch) { continue }
            let salt = Double(hanabiHashString(launch.seed) % 997)
            if age <= launch.duration {
                let p = age / launch.duration
                for segment in 0...HANABI_LAUNCH_TRAIL_SEGMENTS {
                    let pp = p - Double(segment) * 0.05
                    if pp < 0 { continue }
                    let head = hanabiLaunchHead(launch, p: pp, salt: salt)
                    let fade = 1 - Double(segment)
                        / Double(HANABI_LAUNCH_TRAIL_SEGMENTS + 1)
                    let dot = hanabiSprite(kind: "dot",
                                           color: hanabiColor(launch.color))
                    let extent = CGFloat(4 + 5 * fade)
                    dot.draw(in: CGRect(x: CGFloat(head.x) - extent / 2,
                                        y: CGFloat(head.y) - extent / 2,
                                        width: extent, height: extent),
                             blendMode: .plusLighter,
                             alpha: CGFloat(0.75 * fade))
                }
            }
            let emberCount = Int(min(age, HANABI_LAUNCH_EMBER_LIFE)
                / HANABI_LAUNCH_EMBER_STEP)
            for k in 0..<emberCount {
                let born = Double(k) * HANABI_LAUNCH_EMBER_STEP
                let emberAge = age - born
                if emberAge > HANABI_LAUNCH_EMBER_LIFE { continue }
                let base = hanabiLaunchHead(
                    launch, p: min(born / launch.duration, 1), salt: salt)
                let jitterX = (hanabiAnimHash01(k, Int(salt)) - 0.5) * 7
                let jitterY = emberAge * 16
                    + (hanabiAnimHash01(k + 40, Int(salt)) - 0.5) * 5
                let dot = hanabiSprite(kind: "dot",
                                       color: hanabiColor(launch.color))
                dot.draw(in: CGRect(
                    x: CGFloat(base.x + jitterX) - 1.5,
                    y: CGFloat(base.y + jitterY) - 1.5,
                    width: 3, height: 3),
                    blendMode: .plusLighter,
                    alpha: CGFloat(0.55 * (1 - emberAge / HANABI_LAUNCH_EMBER_LIFE)))
            }
        }
        // 装饰（矢量小形，绕锚点轻摆）。
        for ornament in ornaments {
            if time < ornament.delay { continue }
            hanabiDrawOrnament(kind: ornament.kind, center: ornament.center,
                               scale: ornament.scale, seed: ornament.seed,
                               colorHex: ornament.colorHex,
                               time: time, context: context)
        }
    }
}

/// 装饰 21 式的矢量近似（网页为小贴纸精灵，原生以同形
/// 矢量轮廓 + 调色板色落点；类别：瓣/星/叶/滴/环/月/音符/
/// 蝶/光点等，逐式形状对位、纹理从简，见报告）。
private func hanabiDrawOrnament(kind: String, center: CGPoint, scale: Double,
                                seed: Double, colorHex: Int, time: Double,
                                context: CGContext) {
    let bob = sin(time * 0.9 + seed * 12) * 2.5
    let c = CGPoint(x: center.x, y: center.y + CGFloat(bob))
    let s = CGFloat(9 * scale)
    let color = hanabiColor(colorHex).withAlphaComponent(0.85)
    context.saveGState()
    context.translateBy(x: c.x, y: c.y)
    context.rotate(by: CGFloat(sin(time * 0.5 + seed * 8) * 0.16))
    context.setFillColor(color.cgColor)
    context.setStrokeColor(color.cgColor)
    switch kind {
    case "petal", "petals", "sakura", "blossom":
        context.fillEllipse(in: CGRect(x: -s * 0.5, y: -s * 0.32,
                                       width: s, height: s * 0.64))
    case "leaf", "bamboo":
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -s * 0.55, y: s * 0.3))
        path.addQuadCurve(to: CGPoint(x: s * 0.55, y: -s * 0.3),
                          control: CGPoint(x: 0, y: -s * 0.55))
        path.addQuadCurve(to: CGPoint(x: -s * 0.55, y: s * 0.3),
                          control: CGPoint(x: 0, y: s * 0.55))
        context.addPath(path)
        context.fillPath()
    case "drop", "rain":
        context.fillEllipse(in: CGRect(x: -s * 0.3, y: -s * 0.42,
                                       width: s * 0.6, height: s * 0.84))
    case "ring", "halo", "moon", "orbit", "dash-circle":
        context.setLineWidth(1.6)
        if kind == "moon" {
            context.strokeEllipse(in: CGRect(x: -s * 0.5, y: -s * 0.5,
                                             width: s * 0.8, height: s))
        } else {
            context.strokeEllipse(in: CGRect(x: -s * 0.5, y: -s * 0.5,
                                             width: s, height: s))
        }
    case "note", "bell":
        context.fillEllipse(in: CGRect(x: -s * 0.42, y: s * 0.08,
                                       width: s * 0.55, height: s * 0.4))
        context.setLineWidth(1.6)
        context.beginPath()
        context.move(to: CGPoint(x: s * 0.12, y: s * 0.25))
        context.addLine(to: CGPoint(x: s * 0.12, y: -s * 0.5))
        context.addLine(to: CGPoint(x: s * 0.5, y: -s * 0.38))
        context.strokePath()
    case "underline":
        context.setLineWidth(2)
        context.beginPath()
        context.move(to: CGPoint(x: -s * 0.7, y: s * 0.3))
        context.addLine(to: CGPoint(x: s * 0.7, y: s * 0.3))
        context.strokePath()
    case "butterfly", "moth":
        context.fillEllipse(in: CGRect(x: -s * 0.62, y: -s * 0.3,
                                       width: s * 0.6, height: s * 0.55))
        context.fillEllipse(in: CGRect(x: s * 0.02, y: -s * 0.3,
                                       width: s * 0.6, height: s * 0.55))
    default: // 星/火花/光点族（spark, star, firefly, snow, confetti 等）
        let path = CGMutablePath()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let radius = i % 2 == 0 ? s * 0.6 : s * 0.16
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }
    context.restoreGState()
}

// MARK: - 氛围层（hanabiSky.ts ambient 对译）
//
// 远/近星、余烬、光斑、远景小爆，密度由 tuning.ambient ×
// 质量 ambientScale 定；视差系数照网页（远星 0.2 / 近星
// 0.42 / 烟 0.3 / 远景 0.55 / 余烬 1.25 / 光斑 1.45；烟层
// 以低透明度大辉光点近似）。远景小爆按 mood 速率自发
// （quiet 0.08 / neutral 0.2 / loud 0.35 次每秒）。

private final class HanabiAmbientView: UIView {
    var density: Double = 1
    var moodRate: Double = 0.2
    var parallax: CGPoint = .zero
    var time: Double = 0
    var palette: HanabiPaletteData? = nil
    private var rng = HanabiRng(key: "hanabi:ambient")
    private var distant: [HanabiBurstPlan] = []
    private var nextDistantAt: Double = 1.5
    private var spawnCount = 0
    private var stars: [(x: Double, y: Double, r: Double, phase: Double, near: Bool)] = []
    private var embers: [(x: Double, y: Double, speed: Double, phase: Double)] = []
    private var bokeh: [(x: Double, y: Double, r: Double, phase: Double)] = []
    private var seeded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HanabiAmbientView is programmatic") }

    private func seedIfNeeded() {
        if seeded || bounds.width <= 0 { return }
        seeded = true
        for _ in 0..<110 {
            stars.append((rng.next(), rng.next(), 0.6 + rng.next() * 1.3,
                          rng.next() * 6.28, rng.next() < 0.4))
        }
        for _ in 0..<40 {
            embers.append((rng.next(), rng.next(), 0.008 + rng.next() * 0.02,
                           rng.next() * 6.28))
        }
        for _ in 0..<6 {
            bokeh.append((rng.next(), rng.next(), 14 + rng.next() * 30,
                          rng.next() * 6.28))
        }
    }

    func advance(to newTime: Double) {
        time = newTime
        seedIfNeeded()
        if density > 0.01, newTime >= nextDistantAt, let palette {
            let rate = max(moodRate, 0.01)
            nextDistantAt = newTime + 1 / rate * (0.5 + rng.next())
            if distant.count < 8 {
                spawnCount += 1
                let event = HanabiBurstEvent(
                    x: Double(bounds.width) * (0.12 + rng.next() * 0.76),
                    y: Double(bounds.height) * (0.06 + rng.next() * 0.34),
                    at: newTime,
                    spec: hanabiSmallBurst(rng.next() < 0.5 ? "botan" : "ring",
                                           [0, 1, 2], count: 26, radius: 0.09,
                                           duration: 1.1),
                    seed: "ambient:\(spawnCount)", scale: 0.7)
                distant.append(hanabiPlanBurst(
                    event: event, palette: palette,
                    unit: Double(min(bounds.width, bounds.height)),
                    amount: density))
            }
        }
        distant.removeAll { newTime > $0.end + 0.1 }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let w = Double(bounds.width), h = Double(bounds.height)
        if w <= 0 || h <= 0 || density <= 0.01 { return }
        // 星（远/近两层视差 + 闪烁）。
        for star in stars {
            let factor = star.near ? 0.42 : 0.2
            let x = star.x * w + Double(parallax.x) * factor * 30
            let y = star.y * h + Double(parallax.y) * factor * 30
            let twinkle = 0.55 + 0.45 * sin(time * (0.6 + star.phase) + star.phase * 7)
            context.setFillColor(UIColor.white.withAlphaComponent(
                CGFloat(0.5 * twinkle * density)).cgColor)
            context.fillEllipse(in: CGRect(x: x, y: y, width: star.r, height: star.r))
        }
        // 远景小爆（视差 0.55）。
        for plan in distant where hanabiBurstActive(plan, time: time) {
            for star in plan.stars {
                let tau = time - star.start
                if tau < 0 || tau > star.life { continue }
                let brightness = hanabiStarBrightness(star, tau: tau)
                if brightness <= 0.03 { continue }
                let position = hanabiStarPosition(star, tau: tau)
                let color = hanabiColor(hanabiStarColor(star, tau: tau))
                let dot = hanabiSprite(kind: "dot", color: color)
                let extent = CGFloat(hanabiStarSize(star, tau: tau) * 1.8)
                dot.draw(in: CGRect(
                    x: position.x + Double(parallax.x) * 0.55 * 30 - Double(extent) / 2,
                    y: position.y + Double(parallax.y) * 0.55 * 30 - Double(extent) / 2,
                    width: Double(extent), height: Double(extent)),
                    blendMode: .plusLighter, alpha: CGFloat(brightness * 0.8))
            }
        }
        // 余烬（上升漂移）与光斑（大而淡）。
        for ember in embers {
            let y = (ember.y - time * ember.speed).truncatingRemainder(dividingBy: 1)
            let yy = y < 0 ? y + 1 : y
            let x = ember.x * w + sin(time * 0.5 + ember.phase) * 8
                + Double(parallax.x) * 1.25 * 30
            context.setFillColor(UIColor(red: 1, green: 0.72, blue: 0.4,
                alpha: CGFloat(0.4 * density)).cgColor)
            context.fillEllipse(in: CGRect(x: x, y: yy * h, width: 2, height: 2))
        }
        for spot in bokeh {
            let x = spot.x * w + Double(parallax.x) * 1.45 * 30
            let y = spot.y * h + Double(parallax.y) * 1.45 * 30
            let glow = hanabiSprite(kind: "glow", color: UIColor(
                red: 1, green: 0.85, blue: 0.6, alpha: 1))
            let extent = spot.r * 2
            glow.draw(in: CGRect(x: x - extent / 2, y: y - extent / 2,
                                 width: extent, height: extent),
                      blendMode: .plusLighter,
                      alpha: CGFloat(0.05 * density))
        }
    }
}

/// 画框（overlay.ts）：左上印章「花火」、右缘竖排 HANABI、
/// 左下三点、右下角标；内衬横 7% / 纵 8%。
private final class HanabiOverlayView: UIView {
    private let seal = UILabel()
    private let side = UILabel()
    private let corner = UILabel()
    private let dots = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        seal.text = "花\n火"
        seal.numberOfLines = 2
        seal.font = StageFonts.bold(size: 13)
        seal.textColor = .white
        seal.textAlignment = .center
        seal.backgroundColor = UIColor(red: 0.78, green: 0.2, blue: 0.16, alpha: 0.9)
        seal.layer.cornerRadius = 3
        seal.clipsToBounds = true
        addSubview(seal)
        side.text = "H A N A B I"
        side.font = .systemFont(ofSize: 12, weight: .medium)
        side.textColor = UIColor.white.withAlphaComponent(0.75)
        side.transform = CGAffineTransform(rotationAngle: .pi / 2)
        addSubview(side)
        corner.text = "花"
        corner.font = StageFonts.bold(size: 12)
        corner.textColor = UIColor.white.withAlphaComponent(0.7)
        addSubview(corner)
        for i in 0..<3 {
            let dot = UIView()
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.65)
            dot.layer.cornerRadius = 2
            dot.frame = CGRect(x: i * 11, y: 0, width: 4, height: 4)
            dots.addSubview(dot)
        }
        addSubview(dots)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HanabiOverlayView is programmatic") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let padX = bounds.width * 0.07
        let padY = bounds.height * 0.08
        seal.frame = CGRect(x: padX, y: padY, width: 30, height: 40)
        side.sizeToFit()
        side.center = CGPoint(x: bounds.width - padX * 0.55, y: bounds.height / 2)
        corner.frame = CGRect(x: bounds.width - padX - 16,
                              y: bounds.height - padY - 16, width: 16, height: 16)
        dots.frame = CGRect(x: padX, y: bounds.height - padY - 4, width: 30, height: 4)
    }
}

// MARK: - 渲染器本体

/// 渲染质量 → 粒子预算倍率（网页 renderQuality 三档的
/// glowScale / ambientScale 在 HanabiRenderQuality 里；
/// 预算倍率是原生自绘管线的落点：full 1 / balanced 0.8 /
/// low 0.55）。
private func hanabiQualityBudget(_ quality: HanabiRenderQuality) -> Double {
    switch quality {
    case .full: return 1
    case .balanced: return 0.8
    case .low: return 0.55
    }
}

/// 镜头视图持有者：文字层（逐字 UILabel）+ 衬底块层 +
/// 已规划的烟花事件与时间表（构建时一次算好，逐帧只求值、
/// 不重算，满足定额池/零逐帧大分配纪律）。
private final class HanabiShotHolder {
    let index: Int
    let view = UIView()
    var glyphLabels: [UILabel] = []
    var glyphBaseColors: [UIColor] = []
    var glyphSungColors: [UIColor] = []
    var glyphFlashColors: [UIColor] = []
    var glyphs: [HanabiGlyphData] = []
    /// 逐字在内容坐标（em）里的中心与内容 em 尺寸（姿态用）。
    var glyphEmCenters: [(x: Double, y: Double)] = []
    var contentEmSize = (width: 0.0, height: 0.0)
    var enterStart: [Double] = []
    var enterDuration: Double = 0.5
    var enterLanded: [Double] = []
    var exitStart: [Double] = []
    var exitEnd: [Double] = []
    var baseFontSize: Double = 30
    var blockLayer: CAShapeLayer?
    var eventsBack = HanabiShotEvents()
    var eventsFront = HanabiShotEvents()

    init(index: Int) {
        self.index = index
        view.isUserInteractionEnabled = false
    }
}

/// 「花火 hanabi」全量原生移植（网页 Pixi 版 → UIKit 自绘）。
///
/// 同步纪律：粒子与歌词只由 frameTick(position) 推进，
/// 不自建歌曲时钟；帧间隔仅用宿主时钟量帧率做降级判定，
/// 不参与任何同步。数据只从 snapshot / context 取。
final class HanabiStageRenderer: LyricStageRenderer {
    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: true, requiresSpectrum: false,
        supportsLineSeek: false)

    private let root = LyricStageRootView()
    private let skyView = UIView()
    private let skyGradient = CAGradientLayer()
    private let ambientBack = HanabiAmbientView()
    private let stageView = UIView()
    private let worldView = UIView()
    private let canvasBack = HanabiCanvasView()
    private let canvasFront = HanabiCanvasView()
    private let ambientFront = HanabiAmbientView()
    private let overlayView = HanabiOverlayView()

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var programKey = ""
    private var shots: [HanabiShotData] = []
    private var timeline: HanabiTimeline?
    private var timelineKey = ""
    private var programDuration: Double = 0
    private var holders: [Int: HanabiShotHolder] = [:]
    /// 天幕/氛围用的基底调色板（night 角色）；逐镜文字与
    /// 烟花在构建时按 profile.palette 角色各自解析。
    private var basePalette: HanabiPaletteData?
    private var backdropHex = 0x0b0d24
    private var lastTuning: HanabiTuningValues?
    private var active = true
    private var lastTickHostTime: Double = 0
    private var frameIntervalEMA: Double = 1.0 / 60
    private var degradeLevel = 0
    private var goodFrames = 0

    init() {
        view = root
        root.backgroundColor = .black
        skyView.layer.addSublayer(skyGradient)
        root.addSubview(skyView)
        root.addSubview(ambientBack)
        stageView.isUserInteractionEnabled = false
        worldView.isUserInteractionEnabled = false
        stageView.addSubview(worldView)
        worldView.addSubview(canvasBack)
        worldView.addSubview(canvasFront)
        root.addSubview(stageView)
        root.addSubview(ambientFront)
        root.addSubview(overlayView)
        for sub in [skyView, ambientBack, ambientFront, overlayView] {
            sub.isUserInteractionEnabled = false
        }
        root.onLayout = { [weak self] in self?.layoutLayers() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
        layoutLayers()
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        // (61) WC：入口统一过对比钳制——下游 palette.* 全走保护副本。
        var snapshot = snapshot
        snapshot.palette = snapshot.palette.contrastProtected()
        self.snapshot = snapshot
        let tuning = HanabiTuningStore.valuesCached(
            now: Date().timeIntervalSince1970)
        basePalette = hanabiResolvePalette(role: "night",
                                           tokens: snapshot.palette,
                                           mode: tuning.colorMode)
        if let basePalette { backdropHex = hanabiBackdropOf(basePalette) }
        updateSky(tuning: tuning)
        let key = snapshot.track?.id ?? "" + "|"
            + snapshot.lines.map { "\($0.id):\($0.start)" }.joined(separator: ",")
        if key != programKey {
            programKey = key
            let compiled = hanabiCompileProgram(
                lines: snapshot.lines, seed: snapshot.track?.id ?? "",
                duration: snapshot.track?.duration ?? 0)
            shots = compiled.shots
            programDuration = compiled.duration
            timeline = nil
            timelineKey = ""
            clearHolders()
        }
        layoutLayers()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        self.active = active
        if !active {
            canvasBack.setNeedsDisplay()
            canvasFront.setNeedsDisplay()
        }
    }

    func frameTick(position: Double) {
        guard active, let snapshot, !shots.isEmpty else { return }
        let hostNow = CACurrentMediaTime()
        updateDegradation(hostNow: hostNow)
        let tuning = HanabiTuningStore.valuesCached(now: hostNow)
        if tuning != lastTuning {
            let colorChanged = lastTuning != nil
                && lastTuning!.colorMode != tuning.colorMode
            lastTuning = tuning
            if colorChanged {
                basePalette = hanabiResolvePalette(
                    role: "night", tokens: snapshot.palette,
                    mode: tuning.colorMode)
                if let basePalette { backdropHex = hanabiBackdropOf(basePalette) }
                clearHolders()
            }
            updateSky(tuning: tuning)
        }
        ensureTimeline(tuning: tuning)
        guard let timeline else { return }
        let bounds = root.bounds
        if bounds.width <= 0 || bounds.height <= 0 { return }

        // 世界变换：上升 + 旋转（绕画面中心）× 运镜。
        let rise = timeline.rise(position)
        let spin = timeline.spin(position)
        let cam = timeline.camera(position)
        worldView.transform = CGAffineTransform(
            translationX: CGFloat(cam.dx) * bounds.width,
            y: CGFloat(rise) + CGFloat(cam.dy) * bounds.height)
            .rotated(by: CGFloat(spin + cam.rotation))
            .scaledBy(x: CGFloat(cam.scale), y: CGFloat(cam.scale))

        // 镜头生命周期：提前 1.5s 备好（PREPARE_AHEAD），
        // 退场收尾后释放。
        let current = timeline.shotAt(position)
        var alive = Set<Int>()
        for index in shots.indices {
            let timing = timeline.timings[index]
            if position >= timing.enterAt - 1.5
                && position <= timing.exitAt + timing.exitDuration + 0.6 {
                alive.insert(index)
            }
        }
        for index in alive where holders[index] == nil {
            buildHolder(index: index, timeline: timeline, tuning: tuning)
        }
        for index in Array(holders.keys) where !alive.contains(index) {
            holders[index]?.view.removeFromSuperview()
            holders[index] = nil
        }

        // 逐字姿态 + 事件组装。
        var backBursts: [HanabiBurstPlan] = []
        var backLaunches: [HanabiLaunchEvent] = []
        var frontBursts: [HanabiBurstPlan] = []
        var frontLaunches: [HanabiLaunchEvent] = []
        var backOrnaments: [HanabiOrnamentInstance] = []
        var frontOrnaments: [HanabiOrnamentInstance] = []
        for index in alive.sorted() {
            guard let holder = holders[index] else { continue }
            poseHolder(holder, index: index, timeline: timeline,
                       tuning: tuning, time: position)
            backBursts += holder.eventsBack.bursts
            backLaunches += holder.eventsBack.launches
            frontBursts += holder.eventsFront.bursts
            frontLaunches += holder.eventsFront.launches
            backOrnaments += holder.eventsBack.ornaments
            frontOrnaments += holder.eventsFront.ornaments
        }
        // 节拍烟花近似（(62) §6 hanabi）：协议无节拍/鼓声数据
        // 源，网页 hanabiBeatFx 不可达——以行首时间戳为节拍点
        // 近似：每行开始时在确定性伪随机位置放一朵小爆（botan
        // 26 星），相位由 StageEnergy62.beatPhase 对齐到行首。
        // 这是节拍近似、非真实鼓点检测（档案口径保留标注）。
        if !tuning.textOnly, let snapshot, let palette = basePalette {
            let unit = Double(min(bounds.width, bounds.height))
            for line in snapshot.lines
            where position >= line.start - 0.05 && position <= line.start + 1.6 {
                let seed = Double(line.id * 7919 % 1000) / 1000
                let event = HanabiBurstEvent(
                    x: Double(bounds.width) * (0.2 + 0.6 * seed),
                    y: Double(bounds.height) * (0.16 + 0.2 * (1 - seed)),
                    at: line.start + 0.02,
                    spec: HanabiBurstSpecData(
                        kind: "botan", count: 26, radius: 0.15,
                        duration: 1.4, colors: [0, 1], trail: 0.4,
                        twinkle: 0.5),
                    seed: "beat62:\(line.id)", scale: 0.8)
                backBursts.append(hanabiPlanBurst(
                    event: event, palette: palette, unit: unit,
                    amount: tuning.sparkAmount))
            }
        }
        let quality = tuning.renderQuality
        let budgetScale = [1.0, 0.7, 0.5, 0.32][degradeLevel]
            * hanabiQualityBudget(quality)
        canvasBack.bursts = backBursts
        canvasBack.launches = tuning.textOnly ? [] : backLaunches
        canvasBack.ornaments = backOrnaments
        canvasBack.time = position
        canvasBack.starBudget = Int(1100 * budgetScale)
        canvasBack.glowStrength = tuning.glow * quality.glowScale
        canvasBack.isHidden = tuning.textOnly
        canvasBack.setNeedsDisplay()
        canvasFront.bursts = frontBursts
        canvasFront.launches = tuning.textOnly ? [] : frontLaunches
        canvasFront.ornaments = tuning.textOnly ? [] : frontOrnaments
        canvasFront.time = position
        canvasFront.starBudget = Int(500 * budgetScale)
        canvasFront.glowStrength = tuning.glow * quality.glowScale
        canvasFront.isHidden = tuning.textOnly
        canvasFront.setNeedsDisplay()

        // 氛围：密度 × 质量；mood 速率（协议无副歌标记，
        // 歌词镜 0.2、间奏镜 0.08，见报告）。
        let ambientScale = tuning.ambient * quality.ambientScale
            * (degradeLevel >= 3 ? 0 : 1)
        ambientBack.density = ambientScale
        ambientBack.palette = basePalette
        ambientBack.moodRate = shots[current].isBridge ? 0.08 : 0.2
        ambientBack.parallax = CGPoint(x: cam.dx * 8, y: cam.dy * 8)
        ambientBack.advance(to: position)
        ambientFront.density = ambientScale * 0.6
        ambientFront.palette = basePalette
        ambientFront.moodRate = 0
        ambientFront.parallax = CGPoint(x: cam.dx * 8, y: cam.dy * 8)
        ambientFront.advance(to: position)

        overlayView.isHidden = !tuning.overlayFrame
    }

    func unmount() {
        clearHolders()
        context = nil
        snapshot = nil
        timeline = nil
        shots = []
        basePalette = nil
    }

    // MARK: 布局与时间线

    private func layoutLayers() {
        lyricScrimView.sync(in: root, palette: snapshot?.palette ?? .neutralDark,
                              rect: root.bounds, at: 2)

        let bounds = root.bounds
        skyView.frame = bounds
        skyGradient.frame = bounds
        ambientBack.frame = bounds
        stageView.frame = bounds
        worldView.frame = bounds
        canvasBack.frame = bounds
        canvasFront.frame = bounds
        ambientFront.frame = bounds
        overlayView.frame = bounds
        // 世界层级：画布（后）→ 镜头文字 → 画布（前）。
        worldView.insertSubview(canvasBack, at: 0)
        worldView.bringSubviewToFront(canvasFront)
        // 尺寸变了（旋转）：时间线与镜头按新 bounds 重建。
        if !timelineKey.hasPrefix("h|\(Int(bounds.height))|") {
            timeline = nil
            clearHolders()
        }
    }

    private func ensureTimeline(tuning: HanabiTuningValues) {
        let height = Double(root.bounds.height)
        let graphicsOn = !tuning.textOnly
        let key = "h|\(Int(height))|r\(tuning.riseSpeed)|s\(graphicsOn ? tuning.spin : 0)"
        if timeline != nil && key == timelineKey { return }
        timelineKey = key
        clearHolders()
        let profiles = shots.map { hanabiProfileOf($0.profileKind) }
        let direction = hanabiHashString(snapshot?.track?.id ?? "") % 2 == 0
            ? 1.0 : -1.0
        timeline = HanabiTimeline(
            shots: shots, profiles: profiles, unitStart: 0,
            unitEnd: programDuration, height: height,
            riseSpeed: tuning.riseSpeed, motion: tuning.textMotion,
            spinAmount: graphicsOn ? tuning.spin : 0,
            spinDirection: direction, seed: snapshot?.track?.id ?? "")
    }

    private func updateSky(tuning: HanabiTuningValues) {
        guard let tokens = snapshot?.palette else { return }
        root.backgroundColor = tokens.background
        // 夜空四色标（hanabiSky.ts）：以主题背景色为基，
        // 强调色饱和度 ≥ 0.2 时色相往强调色倾 0.3；四档
        // 亮度偏移在原生以背景 HSL 近似（见报告）。
        let bgHex = hanabiHex(of: tokens.background, fallback: backdropHex)
        let bg = hanabiHSL(of: bgHex)
        let accentHex = hanabiHex(of: tokens.accent, fallback: 0xffd166)
        let accent = hanabiHSL(of: accentHex)
        let hue = accent.s >= 0.2
            ? hanabiMixHue(from: bg.h, to: accent.h, amount: 0.3) : bg.h
        let stops: [Double] = [-0.13, -0.03, 0.09, -0.09]
        skyGradient.colors = stops.map {
            hanabiColor(hanabiHexFromHSL(
                h: hue, s: min(bg.s + 0.08, 1),
                l: hanabiClamp01(bg.l + $0))).cgColor
        }
        skyGradient.locations = [0, 0.45, 0.82, 1]
        skyGradient.startPoint = CGPoint(x: 0.5, y: 0)
        skyGradient.endPoint = CGPoint(x: 0.5, y: 1)
        skyGradient.opacity = Float(tuning.sky)
        // 屏幕泛光的原生近似：整场轻微提亮层（无逐帧
        // CIFilter 管线，见报告）。chorus 加权恒 0（协议
        // 无副歌标记，chorusBloom 不触发，见报告）。
        skyView.backgroundColor = UIColor.white.withAlphaComponent(
            CGFloat(0.05 * tuning.bloom))
    }

    // MARK: 帧率降级（DS R55 记账：粒子上限与降级策略）
    //
    // 硬顶：单帧星数预算合计 1600（后画布 1100 + 前画布
    // 500，≈ 网页两镜并发 1500 + 余量），超预算按事件顺序
    // 等距抽稀；发射侧每镜主爆 1 + 逐字 ≤28 + 消散 ≤24 +
    // 间奏 ≤10，计划随镜头构建/释放、无无界缓存。帧间隔
    // EMA > 20ms → ×0.7；> 27ms → ×0.5；> 36ms → ×0.32
    // 且氛围层关停；回落 < 13.5ms 持续 90 帧逐级恢复。
    private func updateDegradation(hostNow: Double) {
        if lastTickHostTime > 0 {
            let dt = hostNow - lastTickHostTime
            if dt > 0 && dt < 0.5 {
                frameIntervalEMA = frameIntervalEMA * 0.92 + dt * 0.08
            }
        }
        lastTickHostTime = hostNow
        if frameIntervalEMA > 0.036 {
            if degradeLevel < 3 { degradeLevel = 3; goodFrames = 0 }
        } else if frameIntervalEMA > 0.027 {
            if degradeLevel < 2 { degradeLevel = 2; goodFrames = 0 }
        } else if frameIntervalEMA > 0.020 {
            if degradeLevel < 1 { degradeLevel = 1; goodFrames = 0 }
        } else if frameIntervalEMA < 0.0135 {
            goodFrames += 1
            if goodFrames > 90 && degradeLevel > 0 {
                degradeLevel -= 1
                goodFrames = 0
            }
        } else {
            goodFrames = 0
        }
    }

    private func clearHolders() {
        for holder in holders.values { holder.view.removeFromSuperview() }
        holders.removeAll()
    }

    // MARK: 镜头构建

    private func buildHolder(index: Int, timeline: HanabiTimeline,
                             tuning: HanabiTuningValues) {
        guard let snapshot else { return }
        let shot = shots[index]
        let profile = hanabiProfileOf(shot.profileKind)
        let timing = timeline.timings[index]
        let bounds = root.bounds
        // 逐镜调色板：按预设的 palette 角色解析（color.ts）。
        let palette = hanabiResolvePalette(role: profile.palette,
                                           tokens: snapshot.palette,
                                           mode: tuning.colorMode)
        let holder = HanabiShotHolder(index: index)
        holders[index] = holder

        // 区域（中心 + 尺寸，相对舞台）→ 点。
        let region = profile.region
        let regionRect = CGRect(
            x: (region.cx - region.w / 2) * Double(bounds.width),
            y: (region.cy - region.h / 2) * Double(bounds.height),
            width: region.w * Double(bounds.width),
            height: region.h * Double(bounds.height))
        var glyphs: [HanabiGlyphData] = []
        if let line = shot.line {
            glyphs = hanabiBuildGlyphs(line: line, emphasis: profile.text.emphasis,
                                       seed: snapshot.track?.id ?? "")
            holder.glyphs = glyphs
            // 入场次序与时间表（构建时算好存下）。
            var orderRng = HanabiRng(key: "\(snapshot.track?.id ?? ""):order:\(shot.id)")
            let ranks = hanabiEnterOrder(fx: profile.text.enter, count: glyphs.count,
                                         rng: &orderRng)
            for i in glyphs.indices { glyphs[i].order = ranks[i] }
            holder.glyphs = glyphs
            let firstSung = line.words?.first?.start ?? line.start
            let enter = hanabiScheduleEnter(
                fx: profile.text.enter, ranks: ranks, enterAt: timing.enterAt,
                stagger: profile.text.stagger, deadline: firstSung)
            holder.enterStart = enter.start
            holder.enterDuration = enter.duration
            holder.enterLanded = enter.landed
            let exit = hanabiScheduleExit(
                ranks: glyphs.indices.map { $0 }, exitAt: timing.exitAt,
                exitDuration: timing.exitDuration)
            holder.exitStart = exit.start
            holder.exitEnd = exit.end
            // 两遍排版：先估字号，再按贴合后的字号重排换行。
            var placed: [HanabiPlacedGlyph] = []
            var emSize = (width: 0.0, height: 0.0)
            var candidate = CGFloat(min(bounds.width, bounds.height))
                * 0.17 * CGFloat(profile.text.heroSize)
            for _ in 0..<2 {
                let layout = hanabiLayoutText(
                    glyphs: glyphs, layout: profile.text.layout,
                    regionW: Double(regionRect.width),
                    regionH: Double(regionRect.height),
                    fontSize: Double(candidate), seed: snapshot.track?.id ?? "")
                placed = layout.placed
                emSize = (layout.width, layout.height)
                let fit = min(1,
                    Double(regionRect.width) / max(emSize.width * Double(candidate), 1),
                    Double(regionRect.height) / max(emSize.height * Double(candidate), 1))
                candidate = CGFloat(max(Double(candidate) * fit, 8))
                if fit >= 0.99 { break }
            }
            let fontSize = candidate
            holder.baseFontSize = Double(fontSize)
            holder.contentEmSize = emSize
            let contentSize = CGSize(width: emSize.width * Double(fontSize),
                                     height: emSize.height * Double(fontSize))
            holder.view.frame = CGRect(
                x: regionRect.midX - contentSize.width / 2,
                y: CGFloat(timing.worldY) + regionRect.midY - contentSize.height / 2,
                width: contentSize.width, height: contentSize.height)
            holder.view.transform = CGAffineTransform(
                rotationAngle: CGFloat(-timing.spin + profile.text.tilt))
            // 衬底块（构建时烘焙路径，逐帧只调透明度）。
            bakeBlocks(holder: holder, profile: profile, glyphs: glyphs,
                       placed: placed, fontSize: Double(fontSize),
                       palette: palette, tuning: tuning)
            // 逐字标签与颜色（color.ts resolveHanabiGlyphColors：
            // 有块时字色对块色、无块时火花色对夜空底，均过
            // 对比度保证）。
            let backdrop = hanabiBackdropOf(palette)
            let hasBlock = profile.text.block != "none"
            for (glyphIndex, glyph) in glyphs.enumerated() {
                guard glyphIndex < placed.count else { break }
                let place = placed[glyphIndex]
                let label = UILabel()
                label.text = glyph.text
                let size = fontSize * CGFloat(glyph.wordScale)
                label.font = glyph.heavy ? StageFonts.bold(size: size)
                    : StageFonts.light(size: size)
                let under = hasBlock
                    ? palette.blocks[glyph.wordIndex
                        % max(palette.blocks.count, 1)]
                    : backdrop
                let base = hasBlock ? palette.ink
                    : palette.sparks[glyph.wordIndex
                        % max(palette.sparks.count, 1)]
                let colors = hanabiGlyphColors(palette: palette,
                                               base: base, under: under)
                let color = palette.ui(colors.ink)
                label.textColor = color
                if profile.text.outline {
                    label.attributedText = NSAttributedString(
                        string: glyph.text,
                        attributes: [
                            .font: label.font as Any,
                            .foregroundColor: color,
                            .strokeColor: hanabiColor(backdrop),
                            .strokeWidth: -3,
                        ])
                }
                if profile.text.hardShadow {
                    let hsl = hanabiHSL(of: colors.ink)
                    label.shadowColor = hanabiColor(hanabiHexFromHSL(
                        h: hsl.h, s: hsl.s, l: max(hsl.l - 0.35, 0)))
                    label.shadowOffset = CGSize(width: fontSize * 0.06,
                                                height: fontSize * 0.06)
                }
                label.frame = CGRect(
                    x: place.x * Double(fontSize),
                    y: place.y * Double(fontSize),
                    width: max(place.advance * Double(fontSize) + 4, 4),
                    height: Double(fontSize) * 1.3)
                label.textAlignment = .center
                label.alpha = 0
                holder.view.addSubview(label)
                holder.glyphLabels.append(label)
                holder.glyphBaseColors.append(color)
                holder.glyphSungColors.append(palette.ui(colors.sung))
                holder.glyphFlashColors.append(palette.ui(colors.flash))
                holder.glyphEmCenters.append(
                    (place.x + place.advance / 2, place.y + 0.65))
            }
        } else {
            holder.view.frame = CGRect(
                x: regionRect.midX - 1,
                y: CGFloat(timing.worldY) + regionRect.midY - 1,
                width: 2, height: 2)
            holder.view.transform = CGAffineTransform(
                rotationAngle: CGFloat(-timing.spin))
        }
        // 镜头进世界层：文字在两画布之间。
        worldView.insertSubview(holder.view, aboveSubview: canvasBack)

        // 事件规划（需要文字在世界中的位置）。
        let glyphCenters: [CGPoint] = holder.glyphLabels.map {
            holder.view.convert($0.center, to: worldView)
        }
        let textBounds = holder.view.convert(holder.view.bounds, to: worldView)
        let events = hanabiPlanShotEvents(
            profile: profile, timing: timing, palette: palette,
            bounds: bounds, textBounds: textBounds, glyphs: glyphs,
            glyphCenters: glyphCenters, exitFx: profile.text.exit,
            tuning: tuning, seed: (snapshot.track?.id ?? "") + ":" + shot.id)
        for (burstIndex, plan) in events.bursts.enumerated() {
            if events.burstFront[burstIndex] {
                holder.eventsFront.bursts.append(plan)
            } else {
                holder.eventsBack.bursts.append(plan)
            }
        }
        if profile.burstAt == "above" {
            holder.eventsFront.launches = events.launches
        } else {
            holder.eventsBack.launches = events.launches
        }
        for ornament in events.ornaments {
            if ornament.front {
                holder.eventsFront.ornaments.append(ornament)
            } else {
                holder.eventsBack.ornaments.append(ornament)
            }
        }
    }

    private func bakeBlocks(holder: HanabiShotHolder, profile: HanabiProfileData,
                            glyphs: [HanabiGlyphData],
                            placed: [HanabiPlacedGlyph], fontSize: Double,
                            palette: HanabiPaletteData,
                            tuning: HanabiTuningValues) {
        let params = hanabiBlockParams(profile.text.block)
        if params.scope == "none" { return }
        let layer = CAShapeLayer()
        let path = CGMutablePath()
        let inset = params.inset * fontSize
        // 块色 = 调色板 blocks（已过 separate 对比度处理），
        // 透明度由 blockOpacity × 式别系数定。
        let blockHex = palette.blocks.first ?? palette.accent
        let fill = palette.ui(blockHex).withAlphaComponent(
            CGFloat(params.fillAlpha * tuning.blockOpacity))
        switch params.scope {
        case "all":
            let rect = holder.view.bounds.insetBy(dx: CGFloat(-inset),
                                                  dy: CGFloat(-inset))
            path.addRoundedRect(in: rect, cornerWidth: CGFloat(params.radius * fontSize),
                                cornerHeight: CGFloat(params.radius * fontSize))
        case "word":
            var lastWord = -1
            var rect = CGRect.zero
            func flush() {
                if rect != .zero {
                    path.addRoundedRect(in: rect,
                        cornerWidth: CGFloat(params.radius * fontSize),
                        cornerHeight: CGFloat(params.radius * fontSize))
                }
                rect = .zero
            }
            for (i, glyph) in glyphs.enumerated() where i < placed.count {
                if glyph.wordIndex != lastWord { flush(); lastWord = glyph.wordIndex }
                let r = CGRect(x: placed[i].x * fontSize - inset,
                               y: placed[i].y * fontSize - inset * 0.4,
                               width: placed[i].advance * fontSize + inset * 2,
                               height: fontSize * 1.3 + inset * 0.8)
                rect = rect == .zero ? r : rect.union(r)
            }
            flush()
        case "line", "lineBand", "splitBars":
            // 行级条带：line = 行下单条；lineBand = 整行
            // 荧光带；splitBars = 行上下双条。
            var rows: [Double: (minX: Double, maxX: Double)] = [:]
            for (i, _) in glyphs.enumerated() where i < placed.count {
                let y = placed[i].y
                let span = rows[y] ?? (placed[i].x, placed[i].x + placed[i].advance)
                rows[y] = (min(span.minX, placed[i].x),
                           max(span.maxX, placed[i].x + placed[i].advance))
            }
            for (y, span) in rows {
                let x0 = span.minX * fontSize
                let w = (span.maxX - span.minX) * fontSize
                if params.scope == "lineBand" {
                    path.addRoundedRect(in: CGRect(
                        x: x0 - inset, y: (y - 0.06) * fontSize,
                        width: w + inset * 2, height: fontSize * 1.34),
                        cornerWidth: fontSize * 0.06,
                        cornerHeight: fontSize * 0.06)
                } else if params.scope == "splitBars" {
                    path.addRoundedRect(in: CGRect(
                        x: x0, y: (y - 0.2) * fontSize,
                        width: w, height: fontSize * 0.09),
                        cornerWidth: fontSize * 0.04,
                        cornerHeight: fontSize * 0.04)
                    path.addRoundedRect(in: CGRect(
                        x: x0, y: (y + 1.2) * fontSize,
                        width: w, height: fontSize * 0.09),
                        cornerWidth: fontSize * 0.04,
                        cornerHeight: fontSize * 0.04)
                } else {
                    path.addRoundedRect(in: CGRect(
                        x: x0, y: (y + 1.18) * fontSize,
                        width: w, height: fontSize * 0.1),
                        cornerWidth: fontSize * 0.05,
                        cornerHeight: fontSize * 0.05)
                }
            }
        case "glyphCircle":
            // circle：每字身后一个圆。
            for (i, _) in glyphs.enumerated() where i < placed.count {
                let cx = (placed[i].x + placed[i].advance / 2) * fontSize
                let cy = (placed[i].y + 0.62) * fontSize
                let r = fontSize * 0.62
                path.addEllipse(in: CGRect(x: cx - r, y: cy - r,
                                           width: r * 2, height: r * 2))
            }
        case "glyphTile":
            // tile：每字身后一块方砖。
            for (i, _) in glyphs.enumerated() where i < placed.count {
                path.addRoundedRect(in: CGRect(
                    x: placed[i].x * fontSize - inset,
                    y: placed[i].y * fontSize - inset * 0.4,
                    width: placed[i].advance * fontSize + inset * 2,
                    height: fontSize * 1.3 + inset * 0.8),
                    cornerWidth: CGFloat(params.radius * fontSize),
                    cornerHeight: CGFloat(params.radius * fontSize))
            }
        default: // "glyph"：每字下小点
            for (i, _) in glyphs.enumerated() where i < placed.count {
                let cx = (placed[i].x + placed[i].advance / 2) * fontSize
                let cy = (placed[i].y + 1.32) * fontSize
                path.addEllipse(in: CGRect(x: cx - fontSize * 0.07,
                                           y: cy - fontSize * 0.07,
                                           width: fontSize * 0.14,
                                           height: fontSize * 0.14))
            }
        }
        layer.path = path
        layer.fillColor = fill.cgColor
        if params.stroke {
            layer.strokeColor = palette.ui(palette.accent)
                .withAlphaComponent(0.8).cgColor
            layer.lineWidth = 1.5
            if params.fillAlpha == 0 { layer.fillColor = nil }
        }
        layer.opacity = 0
        holder.view.layer.insertSublayer(layer, at: 0)
        holder.blockLayer = layer
    }

    // MARK: 逐字姿态

    private func poseHolder(_ holder: HanabiShotHolder, index: Int,
                            timeline: HanabiTimeline,
                            tuning: HanabiTuningValues, time: Double) {
        let shot = shots[index]
        let profile = hanabiProfileOf(shot.profileKind)
        let timing = timeline.timings[index]
        // 块透明度：入场 0.35s 淡入、退场随 exit 淡出（网页
        // 块有自己的进出场，原生以镜头时间表近似，见报告）。
        if let block = holder.blockLayer {
            let fadeIn = hanabiClamp01((time - timing.enterAt) / 0.35)
            let fadeOut = 1 - hanabiClamp01(
                (time - timing.exitAt) / max(timing.exitDuration, 0.05))
            block.opacity = Float(fadeIn * fadeOut)
        }
        let glyphs = holder.glyphs
        guard !glyphs.isEmpty, !holder.glyphLabels.isEmpty else { return }
        let fontSize = holder.baseFontSize
        let motion = tuning.textMotion
        let center = (x: holder.contentEmSize.width / 2,
                      y: holder.contentEmSize.height / 2)
        for (glyphIndex, glyph) in glyphs.enumerated() {
            guard glyphIndex < holder.glyphLabels.count else { break }
            let label = holder.glyphLabels[glyphIndex]
            let em = holder.glyphEmCenters[glyphIndex]
            let ctx = HanabiFxContext(
                index: glyphIndex, count: glyphs.count, rand: glyph.rand,
                toCenterX: em.x - center.x, toCenterY: em.y - center.y,
                dirX: 1, dirY: 0, time: time, motion: motion)
            var pose = HanabiGlyphPose()
            let enterStart = holder.enterStart[glyphIndex]
            if !enterStart.isNaN {
                if time < enterStart {
                    pose.alpha = 0
                } else if time < enterStart + holder.enterDuration {
                    pose = hanabiEnterPose(
                        fx: profile.text.enter,
                        p: (time - enterStart) / holder.enterDuration, ctx: ctx)
                }
            }
            let exitStart = holder.exitStart[glyphIndex]
            if !exitStart.isNaN && time >= exitStart {
                let exitPose = hanabiExitPose(
                    fx: profile.text.exit,
                    p: (time - exitStart)
                        / max(holder.exitEnd[glyphIndex] - exitStart, 0.001),
                    ctx: ctx)
                pose = hanabiCombinePoses(pose, exitPose)
            }
            // 强调（被唱到的字）。
            let sing = hanabiSingPose(
                fx: profile.text.sing, u: time - glyph.start,
                duration: glyph.wordDuration, rand: glyph.rand.0,
                motion: motion)
            var transform = CGAffineTransform(
                translationX: CGFloat((pose.dx + sing.dx) * fontSize),
                y: CGFloat((pose.dy + sing.dy) * fontSize))
            transform = transform.rotated(by: CGFloat(pose.rotation + sing.rotation))
            transform = transform.scaledBy(
                x: CGFloat(pose.scaleX * sing.scaleX * sing.scale),
                y: CGFloat(pose.scaleY * sing.scaleY * sing.scale))
            if pose.skew != 0 {
                transform.c += CGFloat(pose.skew)
            }
            label.transform = transform
            var alpha = pose.alpha * hanabiClamp01(pose.reveal + 0.35)
            if pose.blur > 0 { alpha *= 1 - 0.35 * pose.blur }
            label.alpha = CGFloat(hanabiClamp01(alpha))
            // 乱码入场：换字（池取自网页 SCRAMBLE_POOL 近似）。
            if pose.scramble >= 0 {
                let pool = Array("あアカサタナハマヤラワ0123456789#%&")
                label.text = String(pool[pose.scramble % pool.count])
            } else if label.text != glyph.text {
                label.text = glyph.text
            }
            // color / flash 强调的颜色落点（构建时已算好
            // 对比度达标的 sung / flash 色）。
            let base = holder.glyphBaseColors[glyphIndex]
            if sing.color > 0.05 {
                label.textColor = hanabiMix(
                    holder.glyphSungColors[glyphIndex], base,
                    CGFloat(1 - sing.color))
            } else if sing.flash > 0.05 {
                label.textColor = hanabiMix(
                    holder.glyphFlashColors[glyphIndex], base,
                    CGFloat(1 - min(sing.flash, 1)))
            } else if label.textColor != base {
                label.textColor = base
            }
            if sing.glow > 0.03 {
                label.layer.shadowColor = base.cgColor
                label.layer.shadowRadius = CGFloat(7 * sing.glow)
                label.layer.shadowOpacity = Float(sing.glow * 0.9)
                label.layer.shadowOffset = .zero
            } else if label.layer.shadowOpacity != 0 && !profile.text.hardShadow {
                label.layer.shadowOpacity = 0
            }
        }
        // stamp 落地整组震动。
        if profile.text.enter == "stamp" {
            let impacts = holder.enterLanded.filter { !$0.isNaN }
            let shake = hanabiStampShake(time: time, impacts: impacts,
                                         amplitude: 3)
            holder.view.transform = CGAffineTransform(
                rotationAngle: CGFloat(-timing.spin + profile.text.tilt))
                .translatedBy(x: CGFloat(shake.x), y: CGFloat(shake.y))
        }
    }
}
