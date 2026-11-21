import UIKit
import QuartzCore

// 凝彩 tempera（3.7 (57) 工作流 B4 全量原生移植）：按 folia-major
// 网页版 src/components/visualizer/tempera/ 的确定性色块 PV 构成
// 逐项移植。依据文件：VisualizerTempera.tsx（数据流：program 编译
// 后交 Pixi runtime 绝对时间驱动）、temperaProgram.ts（段落/shot/
// slice 编译）、temperaShotProfiles.ts（region/enter/camera/mood）、
// temperaLayout.ts（拼贴排版）、temperaMotion.ts +
// temperaMotionEasing.ts + temperaEnterStyles.ts（逐字运动求解）、
// temperaPalette.ts（duo/mono/gradient 调色板）、temperaBlocks.ts
// （色块进场节奏）、temperaCamera.ts（shot 级镜头+呼吸）、
// temperaHatch.ts/temperaShapes.ts/compositions/*（网点图形语汇，
// 121 种 shot kind 分十三族）、temperaDifferenceFilter.ts（文字
// 反色）、temperaCreditsLayer.ts（片尾卡）、tuning.ts（参数）。
//
// 选型：网页 Pixi/WebGL 管线（Graphics 矢量形状 + difference
// filter 读回底图）在原生以 CoreAnimation/CoreGraphics 等价呈现：
// 色块/hatch/装饰全是 CAShapeLayer 矢量路径（程序化、零纹理，
// 舞台纹理占用仅颗粒噪点小图 128×128 一张，远低于 200MB 红线）；
// 反色 filter 的「读字下像素选 ink/paper」因原生构图本身是程序
// 化的（每块的几何与颜色在构建时已知），改为构建时按字形中心
// 命中的最上层色块亮度做同口径判定（|ΔL| 更大者胜），行为等价
// 且 seek 确定；gradient 模式的 tint（保亮度换色相）以 ramp 采样
// + enforceReadable（与 paper 亮度差 ≥88）近似。
// 时钟纪律不变：只消费宿主 frameTick(position)，全部姿态由绝对
// 时间纯函数求解（与网页 solver 同构），不自建时钟源、逐帧不跑
// UIView 动画，seek 落点与连续播放同帧。
//
// 未移植/近似项（如实标注，详见交付报告对照表）：
//  - 121 种 kind 全部登记并参与无重复抽选；几何按十三族生成器
//    落地，其中 split/band/frame 前 24 种的 region/enter/camera
//    用 temperaShotProfiles.ts 原值，其余 kind 用同族原值区间的
//    族级 profile（(62) 已细化到族内散列微分；逐 kind 精确
//    region 表仍未逐条搬完）。
//  - 后处理 GLSL 链（sonnetLens/Glitch/Print）只落暗角（径向
//    渐变）+ 颗粒（平铺噪点图）+ 对比（半透明墨层近似）；RGB
//    偏移与镜头畸变无原生等价低成本管线，未落（参数已存储）。
//  - 墨染奥行：协议无鼓点/频谱数据源（hostCapabilities
//    requiresSpectrum=false），墨渍层未落；景深只落视差与
//    glyphDepth 远近（模糊烘焙未落）。
//  - 用户图片池：(62) C4 起 layerImages 真消费（url/封面图源、depth/frequency 生效，见 updateLayerImage）。
//  - keywordLayer 关键字着色：协议无 wordColors 数据，未落。
//  - 封面取色（gradient 的 coverColors）：协议调色板只给语义
//    色，ramp 以主题色相（accent/secondary/primary/ink）构建，
//    与网页无封面时的回退路径一致。

// MARK: - 确定性散列（visualizerSeedHash.ts 逐行对译）

private func temperaHashSeed(_ value: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for unit in value.utf16 {
        hash ^= UInt32(unit)
        hash = hash &* 16_777_619
    }
    return hash
}

private func temperaMixSeed(_ seed: UInt32, _ salt: Int) -> UInt32 {
    (seed ^ UInt32(truncatingIfNeeded: salt)) &* 2_654_435_761
}

private func temperaHash01(_ seed: UInt32, _ index: Int, _ salt: Int) -> Double {
    let advanced = seed &+ UInt32(truncatingIfNeeded: (index + 1) &* 97)
    return Double(temperaMixSeed(advanced, salt)) / 4_294_967_296.0
}

private func temperaChooseWithoutRepeat<T: Equatable>(
    _ choices: [T], seedKey: String, previous: T?
) -> T? {
    guard !choices.isEmpty else { return nil }
    let start = Int(temperaHashSeed(seedKey) % UInt32(choices.count))
    for offset in 0..<choices.count {
        let candidate = choices[(start + offset) % choices.count]
        if candidate != previous { return candidate }
    }
    return choices[start]
}

// MARK: - 缓动（temperaMotionEasing.ts 逐行对译）

private func temperaClamp01(_ value: Double) -> Double {
    min(1, max(0, value))
}

private func temperaCubicCoordinate(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
    let inv = 1 - t
    return 3 * inv * inv * t * p1 + 3 * inv * t * t * p2 + t * t * t
}

private func temperaCubicBezier(_ x1: Double, _ y1: Double,
                                _ x2: Double, _ y2: Double,
                                _ value: Double) -> Double {
    let target = temperaClamp01(value)
    if target == 0 || target == 1 { return target }
    var low = 0.0
    var high = 1.0
    var parameter = target
    for _ in 0..<12 {
        let x = temperaCubicCoordinate(x1, x2, parameter)
        if x < target { low = parameter } else { high = parameter }
        parameter = (low + high) / 2
    }
    return temperaCubicCoordinate(y1, y2, parameter)
}

private func temperaEaseEnter(_ value: Double) -> Double {
    temperaCubicBezier(0.22, 1, 0.36, 1, value)
}

private func temperaEaseInOut(_ value: Double) -> Double {
    temperaCubicBezier(0.62, 0, 0.32, 1, value)
}

private func temperaEaseSoftBack(_ value: Double) -> Double {
    let t = temperaClamp01(value)
    let c = 1.42
    return 1 + (c + 1) * pow(t - 1, 3) + c * pow(t - 1, 2)
}

/// temperaMotion.resolveShotPacedDuration 逐行对译。
private func temperaShotPacedDuration(_ shotDuration: Double, _ fraction: Double,
                                      _ minSeconds: Double, _ maxSeconds: Double) -> Double {
    min(maxSeconds, max(minSeconds, shotDuration * fraction))
}

// MARK: - 颜色（temperaPalette.ts / colorMix 口径）

private func temperaRGBA(_ color: UIColor) -> (r: Double, g: Double, b: Double, a: Double) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
        return (Double(r), Double(g), Double(b), Double(a))
    }
    var white: CGFloat = 0
    color.getWhite(&white, alpha: &a)
    return (Double(white), Double(white), Double(white), Double(a))
}

private func temperaLuminance(_ color: UIColor) -> Double {
    let c = temperaRGBA(color)
    return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
}

private func temperaMix(_ from: UIColor, _ to: UIColor, _ amount: Double) -> UIColor {
    let a = temperaRGBA(from)
    let b = temperaRGBA(to)
    let t = min(max(amount, 0), 1)
    return UIColor(red: CGFloat(a.r + (b.r - a.r) * t),
                   green: CGFloat(a.g + (b.g - a.g) * t),
                   blue: CGFloat(a.b + (b.b - a.b) * t),
                   alpha: CGFloat(a.a + (b.a - a.a) * t))
}

private func temperaGray(_ color: UIColor, fallback: UIColor) -> UIColor {
    let lum = temperaLuminance(color)
    return UIColor(red: CGFloat(lum), green: CGFloat(lum),
                   blue: CGFloat(lum), alpha: 1)
}

/// 与目标亮度对齐（matchLuminance）：增益缩放后偏差 >1.5/255 回退。
private func temperaMatchLuminance(_ color: UIColor, target: UIColor) -> UIColor {
    let current = temperaLuminance(color)
    let wanted = temperaLuminance(target)
    guard current > 0.5 / 255 else { return target }
    let gain = wanted / current
    let c = temperaRGBA(color)
    let scaled = UIColor(red: CGFloat(min(1, c.r * gain)),
                         green: CGFloat(min(1, c.g * gain)),
                         blue: CGFloat(min(1, c.b * gain)), alpha: 1)
    return abs(temperaLuminance(scaled) - wanted) > 1.5 / 255 ? target : scaled
}

/// ensureInkContrast：ink 与 paper 亮度差 <96 时推向对极并保留色相。
private func temperaEnsureInkContrast(paper: UIColor, ink: UIColor) -> UIColor {
    if abs(temperaLuminance(ink) - temperaLuminance(paper)) >= 96.0 / 255 { return ink }
    let target: UIColor = temperaLuminance(paper) < 0.5
        ? UIColor(red: 0.957, green: 0.957, blue: 0.949, alpha: 1)
        : UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1)
    let tinted = temperaMix(target, ink, 0.14)
    return abs(temperaLuminance(tinted) - temperaLuminance(paper)) >= 96.0 / 255
        ? tinted : target
}

/// enforceReadable：与 paper 亮度差不足 88 时逐步推离。
private func temperaEnforceReadable(paper: UIColor, color: UIColor) -> UIColor {
    let paperLum = temperaLuminance(paper)
    if abs(temperaLuminance(color) - paperLum) >= 88.0 / 255 { return color }
    let away: UIColor = paperLum < 0.5 ? .white
        : UIColor(red: 0.063, green: 0.063, blue: 0.063, alpha: 1)
    for step in 1...5 {
        let pushed = temperaMix(color, away, Double(step) * 0.16)
        if abs(temperaLuminance(pushed) - paperLum) >= 88.0 / 255 { return pushed }
    }
    return temperaMix(color, away, 0.8)
}

private struct TemperaPalette {
    var paper: UIColor
    var ink: UIColor
    var blockA: UIColor
    var blockB: UIColor
    var blockC: UIColor
    var accent: UIColor
    var tone1: UIColor
    var tone2: UIColor
    var tone3: UIColor
    var tone4: UIColor
    var gradient: [UIColor]?
    var textGradient: [UIColor]?
    var tones: [UIColor] { [tone1, tone2, tone3, tone4] }
}

/// resolveTemperaPalette 逐分支对译（coverColors 缺位走主题回退）。
private func resolveTemperaPalette(tokens: PaletteTokens,
                                   mode: TemperaColorMode) -> TemperaPalette {
    let stops = [0.12, 0.30, 0.52, 0.72]
    func ladder(paper: UIColor, ink: UIColor,
                tintA: UIColor?, tintB: UIColor?) -> [UIColor] {
        stops.enumerated().map { index, stop in
            let base = temperaMix(paper, ink, stop)
            let tint = index == 0 || index == 2 ? tintA : (index == 1 ? tintB : nil)
            guard let tint else { return base }
            return temperaMatchLuminance(temperaMix(base, tint, 0.3), target: base)
        }
    }
    if mode == .mono {
        let paper = temperaGray(tokens.background, fallback: UIColor(white: 0.07, alpha: 1))
        var ink = temperaGray(tokens.primary, fallback: UIColor(white: 0.96, alpha: 1))
        if abs(temperaLuminance(ink) - temperaLuminance(paper)) < 96.0 / 255 {
            ink = temperaLuminance(paper) < 0.5
                ? UIColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1)
                : UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1)
        }
        let tones = ladder(paper: paper, ink: ink, tintA: nil, tintB: nil)
        return TemperaPalette(
            paper: paper, ink: ink,
            blockA: temperaMix(paper, ink, 0.08),
            blockB: temperaMix(paper, ink, 0.18),
            blockC: temperaMix(paper, ink, 0.34),
            accent: temperaMix(paper, ink, 0.85),
            tone1: tones[0], tone2: tones[1], tone3: tones[2], tone4: tones[3],
            gradient: nil, textGradient: nil)
    }
    let paper = tokens.background
    let ink = temperaEnsureInkContrast(paper: paper, ink: tokens.primary)
    if mode == .gradient {
        // 无封面取色数据：themeHues = [accent, secondary, primary, ink]
        //（网页 coverColors <2 时的同一回退集），ramp 拉回亮度阶梯。
        let hues = [tokens.accent, tokens.secondary, tokens.primary, ink]
        let ranked = hues.sorted { temperaLuminance($0) < temperaLuminance($1) }
        let towardInk = temperaLuminance(ink) < temperaLuminance(paper)
        let ordered: [UIColor] = towardInk ? Array(ranked.reversed()) : ranked
        let ramp: [UIColor] = stops.enumerated().map { index, stop in
            let rung = temperaMix(paper, ink, stop)
            let hue = ordered[index % max(ordered.count, 1)]
            return temperaMatchLuminance(temperaMix(rung, hue, 0.78), target: rung)
        }
        let textRamp = (0..<4).map { temperaEnforceReadable(paper: paper, color: hues[$0 % hues.count]) }
        return TemperaPalette(
            paper: paper, ink: ink,
            blockA: ramp[0], blockB: ramp[1], blockC: ramp[2],
            accent: tokens.accent,
            tone1: ramp[0], tone2: ramp[1], tone3: ramp[2], tone4: ramp[3],
            gradient: ramp, textGradient: textRamp)
    }
    let tones = ladder(paper: paper, ink: ink, tintA: tokens.accent, tintB: tokens.secondary)
    return TemperaPalette(
        paper: paper, ink: ink,
        blockA: temperaMix(paper, tokens.accent, 0.55),
        blockB: temperaMix(paper, tokens.secondary, 0.6),
        blockC: temperaMix(paper, ink, 0.78),
        accent: tokens.accent,
        tone1: tones[0], tone2: tones[1], tone3: tones[2], tone4: tones[3],
        gradient: nil, textGradient: nil)
}

// MARK: - Shot kind 注册表与 profile（types.ts / temperaShotProfiles.ts）

private let temperaShotKinds: [String] = [
    "duo-split", "quad-split", "tri-column", "thirds-stack", "checker-quad",
    "corner-wedge", "diagonal-halves", "cross-axis", "offset-halves",
    "stair-blocks", "pillar-gap", "corner-quad", "sliver-stack",
    "band-strip", "horizon-band", "deep-dive", "tone-ramp", "double-band",
    "tilt-band", "edge-rails", "gradient-wall", "terrace",
    "frame-window", "double-frame", "circle-window", "ladder-frame",
    "corner-brackets", "inset-box", "bracket-pair", "arch-window",
    "grid-cells", "keyhole",
    "poster-panel", "diamond-stack", "slash-poster", "arrow-wedge",
    "edge-bleed", "triangle-mass", "ribbon-cross", "half-disc", "stacked-slabs",
    "wedge-pair",
    "quiet-line", "starfield-dots", "ripple-lines", "hair-grid",
    "margin-rule", "dot-drift", "arc-sweep", "blank-page",
    "cinema-scope", "cinema-wide", "cinema-academy", "cinema-square",
    "cinema-portrait", "cinema-tall", "cinema-twin",
    "bubble-drift", "cloud-window", "heart-burst", "sparkle-field",
    "petal-arc", "scallop-band", "ribbon-loop", "round-plate", "halo-burst",
    "iris-hole", "slot-rail", "punch-row", "film-gate", "cross-vent",
    "louvre-slats", "ring-eye", "notch-stack", "wedge-gap", "dot-sieve",
    "sight-mark", "dial-scale", "chevron-run", "tally-column", "grid-focus",
    "axis-caps", "strobe-slats", "offset-plate", "radial-comb", "bracket-target",
    "flow-channel", "twin-channel", "reed-run", "taper-channel", "chain-ports",
    "dash-channel", "window-run", "bridge-span", "braid-channel", "port-ladder",
    "apex-mass", "ziggurat", "slab-wall", "cantilever", "pylon-pair",
    "bunker-slit", "plinth-stack", "buttress-run", "void-core", "shear-block",
    "ridge-line", "chasm", "overhang", "step-well", "pier-row", "revetment",
    "tower-crop", "lintel", "rubble-fan", "gnomon",
    "monogatari-card", "monogatari-rule", "monogatari-edge",
    "monogatari-stack", "monogatari-flash",
]

private enum TemperaMood { case quiet, neutral, loud }

private struct TemperaShotProfile {
    var cx: Double, cy: Double, w: Double, h: Double
    var align: Int // 0 center, 1 left, 2 right
    var rotation: Double
    var fontScale: Double
    var enterX: Double, enterY: Double
    var travel: Double, zoomStart: Double, zoomEnd: Double
    var mood: TemperaMood
    var sharedDecor: Bool = true
}

/// 前 24 种为 temperaShotProfiles.ts 原值；其余按族给同区间原值。
private func temperaProfile(for kind: String) -> TemperaShotProfile {
    func p(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double,
           align: Int = 0, rotation: Double = 0, fontScale: Double = 1,
           ex: Double, ey: Double, travel: Double, zs: Double, ze: Double,
           mood: TemperaMood, sharedDecor: Bool = true) -> TemperaShotProfile {
        TemperaShotProfile(cx: cx, cy: cy, w: w, h: h, align: align,
                           rotation: rotation, fontScale: fontScale,
                           enterX: ex, enterY: ey, travel: travel,
                           zoomStart: zs, zoomEnd: ze, mood: mood,
                           sharedDecor: sharedDecor)
    }
    switch kind {
    case "duo-split": return p(0.5, 0.52, 0.86, 0.46, ex: 0, ey: 1.3, travel: 0.11, zs: 1.06, ze: 1.13, mood: .neutral)
    case "quad-split": return p(0.5, 0.5, 0.82, 0.4, ex: 0.9, ey: 0.9, travel: 0.09, zs: 1.08, ze: 1.16, mood: .loud)
    case "tri-column": return p(0.5, 0.5, 0.7, 0.5, fontScale: 0.95, ex: -1.2, ey: 0, travel: 0.12, zs: 1.04, ze: 1.12, mood: .neutral)
    case "thirds-stack": return p(0.5, 0.5, 0.8, 0.28, ex: 0, ey: 1.1, travel: 0.13, zs: 1.03, ze: 1.11, mood: .neutral)
    case "checker-quad": return p(0.5, 0.5, 0.76, 0.36, ex: 0.8, ey: -0.8, travel: 0.1, zs: 1.1, ze: 1.02, mood: .loud)
    case "corner-wedge": return p(0.44, 0.56, 0.68, 0.4, align: 1, rotation: -0.03, ex: -1.4, ey: 0.5, travel: 0.1, zs: 1.05, ze: 1.14, mood: .loud)
    case "diagonal-halves": return p(0.5, 0.5, 0.78, 0.4, rotation: -0.075, ex: 1.1, ey: 1.1, travel: 0.12, zs: 1.06, ze: 1.14, mood: .neutral)
    case "cross-axis": return p(0.5, 0.5, 0.66, 0.3, ex: 0, ey: 1.2, travel: 0.08, zs: 1.12, ze: 1.03, mood: .loud)
    case "offset-halves": return p(0.5, 0.5, 0.8, 0.4, ex: 0.9, ey: 0.6, travel: 0.11, zs: 1.05, ze: 1.13, mood: .neutral)
    case "stair-blocks": return p(0.5, 0.5, 0.72, 0.38, rotation: -0.03, ex: -1, ey: 0.8, travel: 0.12, zs: 1.06, ze: 1.14, mood: .loud)
    case "pillar-gap": return p(0.5, 0.5, 0.34, 0.62, fontScale: 0.8, ex: 0, ey: 1.2, travel: 0.07, zs: 1.1, ze: 1.02, mood: .loud)
    case "corner-quad": return p(0.46, 0.46, 0.68, 0.36, ex: -0.9, ey: -0.9, travel: 0.1, zs: 1.07, ze: 1.15, mood: .neutral)
    case "sliver-stack": return p(0.5, 0.5, 0.76, 0.3, ex: 1.2, ey: 0, travel: 0.13, zs: 1.04, ze: 1.12, mood: .neutral)
    case "band-strip": return p(0.5, 0.52, 0.78, 0.26, fontScale: 0.92, ex: 0.5, ey: 1.05, travel: 0.12, zs: 1.03, ze: 1.1, mood: .neutral)
    case "horizon-band": return p(0.5, 0.36, 0.8, 0.3, ex: 0, ey: -1.1, travel: 0.14, zs: 1.02, ze: 1.1, mood: .neutral)
    case "deep-dive": return p(0.5, 0.58, 0.76, 0.34, ex: 0, ey: 1.6, travel: 0.16, zs: 1.04, ze: 1.14, mood: .neutral)
    case "tone-ramp": return p(0.5, 0.5, 0.82, 0.38, ex: 1.2, ey: 0.4, travel: 0.11, zs: 1.05, ze: 1.12, mood: .neutral)
    case "double-band": return p(0.5, 0.5, 0.78, 0.22, fontScale: 0.88, ex: 0.8, ey: 0, travel: 0.12, zs: 1.03, ze: 1.11, mood: .neutral)
    case "tilt-band": return p(0.5, 0.5, 0.8, 0.26, rotation: -0.1, ex: -1.1, ey: 0.5, travel: 0.13, zs: 1.05, ze: 1.13, mood: .neutral)
    case "edge-rails": return p(0.5, 0.5, 0.74, 0.4, ex: 0, ey: 1, travel: 0.09, zs: 1.02, ze: 1.09, mood: .quiet)
    case "gradient-wall": return p(0.5, 0.44, 0.82, 0.36, ex: 0.5, ey: -0.9, travel: 0.15, zs: 1.04, ze: 1.13, mood: .neutral)
    case "terrace": return p(0.46, 0.52, 0.72, 0.34, align: 1, ex: -1.2, ey: 0.4, travel: 0.14, zs: 1.05, ze: 1.12, mood: .neutral)
    case "frame-window": return p(0.5, 0.5, 0.64, 0.5, fontScale: 0.95, ex: 0, ey: 0.95, travel: 0.05, zs: 1.14, ze: 1.03, mood: .neutral)
    case "double-frame": return p(0.5, 0.5, 0.58, 0.4, fontScale: 0.9, ex: 0.6, ey: 0.6, travel: 0.06, zs: 1.12, ze: 1.02, mood: .neutral)
    default: break
    }
    // 族级回退（region/enter/camera 取同族原值区间中位，mood 按族性）。
    if kind.hasPrefix("cinema-") {
        return p(0.5, 0.5, 0.72, 0.34, ex: 0, ey: 1.0, travel: 0.06, zs: 1.08, ze: 1.04, mood: .neutral)
    }
    if kind.hasPrefix("monogatari-") {
        return p(0.5, 0.5, 0.84, 0.5, ex: 0, ey: 0.6, travel: 0.04, zs: 1.02, ze: 1.05, mood: .quiet, sharedDecor: false)
    }
    if ["quiet-line", "starfield-dots", "ripple-lines", "hair-grid",
        "margin-rule", "dot-drift", "arc-sweep", "blank-page"].contains(kind) {
        return p(0.5, 0.5, 0.78, 0.36, ex: 0.4, ey: 0.8, travel: 0.07, zs: 1.03, ze: 1.08, mood: .quiet)
    }
    if ["bubble-drift", "cloud-window", "heart-burst", "sparkle-field",
        "petal-arc", "scallop-band", "ribbon-loop", "round-plate",
        "halo-burst"].contains(kind) {
        return p(0.5, 0.5, 0.76, 0.42, ex: 0, ey: 1.1, travel: 0.09, zs: 1.05, ze: 1.12, mood: .neutral)
    }
    if kind.hasSuffix("-mass") || kind.hasSuffix("-wall") || kind.hasSuffix("-core")
        || ["ziggurat", "cantilever", "pylon-pair", "bunker-slit", "plinth-stack",
            "buttress-run", "shear-block", "ridge-line", "chasm", "overhang",
            "step-well", "pier-row", "revetment", "tower-crop", "lintel",
            "rubble-fan", "gnomon", "triangle-mass"].contains(kind) {
        return p(0.5, 0.54, 0.8, 0.4, ex: -0.8, ey: 0.9, travel: 0.1, zs: 1.06, ze: 1.13, mood: .loud)
    }
    // (62) 族级 profile 细化：frame/window 与 poster 两族拆开，
    // 并按 kind 散列在族区间内做确定性微分（同 kind 恒同值），
    // 不再全族一值——逐 kind 精确 region 表仍未逐条搬完（档案）。
    let jitter = (Double(temperaHashSeed(kind) % 100) / 100 - 0.5)
    if kind.hasSuffix("-window") || kind.hasSuffix("-frame")
        || ["grid-cells", "keyhole", "corner-brackets", "inset-box",
            "bracket-pair", "ladder-frame"].contains(kind) {
        return p(0.5 + jitter * 0.04, 0.5, 0.62, 0.46, fontScale: 0.94,
                 ex: 0, ey: 0.9, travel: 0.05 + abs(jitter) * 0.03,
                 zs: 1.13, ze: 1.03, mood: .neutral)
    }
    if kind.hasSuffix("-poster") || kind.hasSuffix("-panel")
        || ["diamond-stack", "arrow-wedge", "edge-bleed", "ribbon-cross",
            "half-disc", "stacked-slabs", "wedge-pair"].contains(kind) {
        return p(0.5, 0.5 + jitter * 0.04, 0.78, 0.44, rotation: jitter * 0.03,
                 ex: 0.9, ey: 0.5, travel: 0.1, zs: 1.06, ze: 1.13, mood: .loud)
    }
    // aperture / signal / corridor 其余 kind：族中位 + 散列微分。
    return p(0.5 + jitter * 0.05, 0.5 + jitter * 0.03, 0.74, 0.42,
             ex: 0.7, ey: 0.7, travel: 0.09 + abs(jitter) * 0.02,
             zs: 1.07, ze: 1.12, mood: .neutral)
}

private func temperaCandidates(moods: [TemperaMood]) -> [String] {
    temperaShotKinds.filter { moods.contains(temperaProfile(for: $0).mood) }
}

// MARK: - 编译产物（temperaProgram.ts 的原生形状）

private struct TemperaSegmentData {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var graphemeTimes: [(start: TimeInterval, end: TimeInterval)]
    var isWordLike: Bool
}

private struct TemperaCompiledLineData {
    var sourceIndex: Int
    var start: TimeInterval
    var renderEnd: TimeInterval
    var segments: [TemperaSegmentData]
}

private struct TemperaDecorData {
    var motif: String
    var hatchAngle: Double
    var crossCount: Int
    var fragments: [(char: String, x: Double, y: Double, rotation: Double, scale: Double)]
    var watermark: (text: String, x: Double, y: Double, rotation: Double, scale: Double)?
}

private struct TemperaShotData {
    var index: Int
    var kind: String
    var start: TimeInterval
    var end: TimeInterval
    var lyricEnd: TimeInterval
    var lineSegments: [[TemperaSegmentData]]
    var isBridge: Bool
    var paragraphIndex: Int
    var isParagraphHead: Bool
    var transitionKind: String?
    var camStart: (x: Double, y: Double, zoom: Double, rotation: Double)
    var camEnd: (x: Double, y: Double, zoom: Double, rotation: Double)
    var flowAngle: Double
    var decor: TemperaDecorData
    var seed: UInt32
}

// MARK: - 入场样式（temperaEnterStyles.ts 逐行对译）

private let temperaEnterStyles = ["slide", "from-left", "from-right",
                                  "from-above", "from-below", "swing", "stamp"]

private func temperaEnterFrame(style: String, enterX: Double, enterY: Double,
                               enterRotation: Double, enterScale: Double,
                               travel: Double, linear: Double)
    -> (x: Double, y: Double, rotation: Double, scale: Double, echo: Double) {
    let settle = temperaEaseSoftBack(linear)
    let uniform = enterScale + (1 - enterScale) * settle
    func directional(_ dirX: Double, _ dirY: Double, _ rotScale: Double)
        -> (x: Double, y: Double, rotation: Double, scale: Double, echo: Double) {
        let magnitude = hypot(enterX, enterY)
        let length = hypot(dirX, dirY)
        let norm = length == 0 ? 1 : length
        return (dirX / norm * magnitude * travel,
                dirY / norm * magnitude * travel,
                enterRotation * rotScale * travel, uniform, travel)
    }
    switch style {
    case "from-left": return directional(-1, 0.12, 0.4)
    case "from-right": return directional(1, -0.12, 0.4)
    case "from-above": return directional(0.12, -1, 0.4)
    case "from-below": return directional(-0.12, 1, 0.4)
    case "swing":
        let sign = (enterRotation == 0 ? 1.0 : (enterRotation > 0 ? 1.0 : -1.0))
        return (enterX * 0.6 * travel, enterY * 0.6 * travel,
                (enterRotation + sign * 0.95) * travel, uniform, travel * 0.8)
    case "stamp":
        return (0, 0, enterRotation * 0.6 * travel,
                1 + travel * 0.7, 0)
    default:
        return (enterX * travel, enterY * travel,
                enterRotation * travel, uniform, travel)
    }
}

// MARK: - 字形排版（temperaLayout.ts）

private struct TemperaGlyphPlacement {
    var char: String
    var x: CGFloat, y: CGFloat
    var rotation: Double
    var start: TimeInterval, end: TimeInterval, settle: TimeInterval
    var fontSize: CGFloat
    var enterX: Double, enterY: Double
    var enterRotation: Double, enterScale: Double
    var enterStyle: String
    var release: TimeInterval
    var trackingX: CGFloat, trackingY: CGFloat
    var underLuminance: Double
    var gradientT: Double
}

// MARK: - Shot 视图

private final class TemperaShotView: UIView {

    struct BlockItem {
        var layer: CAShapeLayer
        var baseX: CGFloat, baseY: CGFloat
        var baseAlpha: Double
        var delayFraction: Double, spanFraction: Double
        var drift: Bool, driftPhase: Double
        var pathBounds: CGRect
        var fillLuminance: Double
    }

    let shot: TemperaShotData
    let palette: TemperaPalette
    let tuning: TemperaTuningValues
    private(set) var glyphPlacements: [TemperaGlyphPlacement] = []
    private var glyphLabels: [UILabel] = []
    private var echoLabels: [[UILabel]] = []
    private var blockItems: [BlockItem] = []
    private var blockUnderRects: [(rect: CGRect, luminance: Double)] = []
    private let blocksContainer = UIView()
    private let decorContainer = UIView()
    private let textContainer = UIView()
    private var watermarkLabel: UILabel?
    private var builtSize: CGSize = .zero

    init(shot: TemperaShotData, palette: TemperaPalette, tuning: TemperaTuningValues) {
        self.shot = shot
        self.palette = palette
        self.tuning = tuning
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        blocksContainer.isUserInteractionEnabled = false
        decorContainer.isUserInteractionEnabled = false
        textContainer.isUserInteractionEnabled = false
        addSubview(blocksContainer)
        addSubview(decorContainer)
        addSubview(textContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func build(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        builtSize = size
        frame = CGRect(origin: .zero, size: size)
        blocksContainer.frame = bounds
        decorContainer.frame = bounds
        textContainer.frame = bounds
        buildBlocks(size: size)
        buildGlyphLayout(size: size)
        buildDecor(size: size)
        buildGlyphViews()
    }

    // MARK: 色块构成（compositions/* 的族级生成器 + temperaBlocks 节奏）

    private func addBlock(path: UIBezierPath, fill: UIColor, alpha: Double = 1,
                          stroke: UIColor? = nil, strokeWidth: CGFloat = 0,
                          delay: Double, span: Double = 0.45, drift: Bool = false) {
        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.fillColor = fill.cgColor
        if let stroke {
            layer.strokeColor = stroke.cgColor
            layer.lineWidth = strokeWidth
        }
        layer.opacity = 0
        blocksContainer.layer.addSublayer(layer)
        let bounds = path.bounds
        blockItems.append(BlockItem(
            layer: layer, baseX: 0, baseY: 0, baseAlpha: alpha,
            delayFraction: delay, spanFraction: span, drift: drift,
            driftPhase: temperaHash01(shot.seed, blockItems.count, 173) * .pi * 2,
            pathBounds: bounds, fillLuminance: temperaLuminance(fill)))
        blockUnderRects.append((bounds, temperaLuminance(fill)))
    }

    private func rectPath(_ rect: CGRect) -> UIBezierPath { UIBezierPath(rect: rect) }

    private func polyPath(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.close()
        return path
    }

    private func buildBlocks(size: CGSize) {
        let w = size.width, h = size.height
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        let seed = shot.seed
        let kind = shot.kind
        // 纸面（monogatari 为单 tone 平涂，其余 paper 打底）。
        let isMonoCard = kind.hasPrefix("monogatari-")
        addBlock(path: rectPath(full),
                 fill: isMonoCard ? palette.tone2 : palette.paper,
                 delay: 0, span: 0.3)
        guard tuning.showBlocks, !isMonoCard else { return }
        let tones = palette.tones
        func tone(_ i: Int) -> UIColor { tones[((i % 4) + 4) % 4] }
        let r01 = { (idx: Int, salt: Int) in temperaHash01(seed, idx, salt) }

        if ["duo-split", "offset-halves"].contains(kind) {
            let split = w * CGFloat(0.42 + r01(1, 201) * 0.16)
            addBlock(path: rectPath(CGRect(x: split, y: 0, width: w - split, height: h)),
                     fill: tone(2), delay: 0.08)
            addBlock(path: rectPath(CGRect(x: 0, y: h * 0.62, width: split, height: h * 0.38)),
                     fill: tone(1), delay: 0.16)
        } else if ["quad-split", "checker-quad", "corner-quad", "grid-cells"].contains(kind) {
            let midX = w / 2, midY = h / 2
            let cells = [CGRect(x: midX, y: 0, width: midX, height: midY),
                         CGRect(x: 0, y: midY, width: midX, height: h - midY),
                         CGRect(x: midX, y: midY, width: midX, height: h - midY)]
            for (i, cell) in cells.enumerated() {
                let checkerSkip = kind == "checker-quad" && i == 1
                if !checkerSkip {
                    addBlock(path: rectPath(cell), fill: tone(i + 1), delay: 0.06 * Double(i + 1))
                }
            }
        } else if kind == "tri-column" {
            for i in 0..<3 {
                addBlock(path: rectPath(CGRect(x: w * CGFloat(i) / 3, y: 0, width: w / 3, height: h)),
                         fill: tone(i + 1), delay: 0.07 * Double(i))
            }
        } else if ["thirds-stack", "sliver-stack", "stair-blocks"].contains(kind) {
            let rows = kind == "sliver-stack" ? 5 : 3
            for i in 0..<rows {
                let inset = kind == "stair-blocks" ? w * 0.08 * CGFloat(i) : 0
                addBlock(path: rectPath(CGRect(x: inset, y: h * CGFloat(i) / CGFloat(rows),
                                               width: w - inset, height: h / CGFloat(rows))),
                         fill: tone(i + 1), delay: 0.06 * Double(i))
            }
        } else if ["diagonal-halves", "slash-poster", "wedge-pair", "corner-wedge"].contains(kind) {
            let lean = w * CGFloat(0.18 + r01(2, 203) * 0.2)
            addBlock(path: polyPath([CGPoint(x: lean, y: 0), CGPoint(x: w, y: 0),
                                     CGPoint(x: w, y: h), CGPoint(x: w - lean, y: h)]),
                     fill: tone(2), delay: 0.1)
            addBlock(path: polyPath([CGPoint(x: 0, y: h * 0.7), CGPoint(x: w * 0.4, y: h),
                                     CGPoint(x: 0, y: h)]),
                     fill: tone(3), delay: 0.18)
        } else if kind == "pillar-gap" || kind == "bunker-slit" {
            addBlock(path: rectPath(CGRect(x: 0, y: 0, width: w * 0.32, height: h)),
                     fill: tone(3), delay: 0.05)
            addBlock(path: rectPath(CGRect(x: w * 0.68, y: 0, width: w * 0.32, height: h)),
                     fill: tone(3), delay: 0.12)
        } else if ["band-strip", "horizon-band", "double-band", "tilt-band",
                   "tone-ramp", "gradient-wall", "terrace", "edge-rails"].contains(kind) {
            let bands = kind == "double-band" ? 2 : 4
            for i in 0..<bands {
                let y = h * CGFloat(i) / CGFloat(max(bands, 1))
                let bandH = h / CGFloat(bands) * (kind == "horizon-band" && i == 0 ? 0.6 : 1)
                addBlock(path: rectPath(CGRect(x: 0, y: y, width: w, height: bandH)),
                         fill: tone(i), delay: 0.05 * Double(i))
            }
            if kind == "tone-ramp" || kind == "gradient-wall", let ramp = palette.gradient {
                for i in 0..<4 {
                    addBlock(path: rectPath(CGRect(x: w * CGFloat(i) / 4, y: h * 0.78,
                                                   width: w / 4, height: h * 0.22)),
                             fill: ramp[i], delay: 0.2 + 0.04 * Double(i))
                }
            }
        } else if kind == "deep-dive" {
            for i in 0..<4 {
                let inset = CGFloat(i) * min(w, h) * 0.07
                addBlock(path: rectPath(CGRect(x: inset, y: inset + h * 0.1 * CGFloat(i),
                                               width: w - inset * 2, height: h * 0.24)),
                         fill: tone(i), delay: 0.06 * Double(i))
            }
        } else if kind.hasPrefix("cinema-") {
            // 遮幅：实心框 + 按真实比例 aspect-fit 的窗口（挖洞走 even-odd，
            // 洞内露宿主背景，与网页 cutout 同语义）。
            let aspect: CGFloat
            switch kind {
            case "cinema-scope": aspect = 2.39
            case "cinema-wide": aspect = 16.0 / 9.0
            case "cinema-academy": aspect = 1.37
            case "cinema-square": aspect = 1
            case "cinema-portrait": aspect = 4.0 / 5.0
            case "cinema-tall": aspect = 9.0 / 16.0
            default: aspect = 16.0 / 9.0
            }
            var winW = w * 0.78
            var winH = winW / aspect
            if winH > h * 0.7 { winH = h * 0.7; winW = winH * aspect }
            let win = CGRect(x: (w - winW) / 2, y: (h - winH) / 2, width: winW, height: winH)
            let plate = UIBezierPath(rect: full)
            plate.append(UIBezierPath(rect: win))
            plate.usesEvenOddFillRule = true
            let layer = CAShapeLayer()
            layer.path = plate.cgPath
            layer.fillRule = .evenOdd
            layer.fillColor = tone(3).cgColor
            layer.opacity = 0
            blocksContainer.layer.addSublayer(layer)
            blockItems.append(BlockItem(
                layer: layer, baseX: 0, baseY: 0, baseAlpha: 1,
                delayFraction: 0.05, spanFraction: 0.45, drift: false,
                driftPhase: 0, pathBounds: full, fillLuminance: temperaLuminance(tone(3))))
            addBlock(path: rectPath(win), fill: tone(0), alpha: 0.001, delay: 0)
            // 洞口描边另起节点（网页 addHoleLip 同规矩）。
            addBlock(path: rectPath(win), fill: .clear, stroke: palette.ink,
                     strokeWidth: 1.6, delay: 0.1)
        } else if ["frame-window", "double-frame", "circle-window", "ladder-frame",
                   "corner-brackets", "inset-box", "bracket-pair", "arch-window",
                   "keyhole"].contains(kind) {
            addBlock(path: rectPath(CGRect(x: w * 0.08, y: h * 0.1, width: w * 0.84, height: h * 0.8)),
                     fill: tone(1), delay: 0.06)
            addBlock(path: rectPath(CGRect(x: w * 0.16, y: h * 0.18, width: w * 0.68, height: h * 0.64)),
                     fill: tone(2), stroke: palette.ink, strokeWidth: 2, delay: 0.12)
            if kind == "circle-window" || kind == "keyhole" {
                let radius = min(w, h) * 0.2
                addBlock(path: UIBezierPath(ovalIn: CGRect(x: w / 2 - radius, y: h / 2 - radius,
                                                           width: radius * 2, height: radius * 2)),
                         fill: tone(3), delay: 0.18)
            }
        } else if ["bubble-drift", "cloud-window", "heart-burst", "sparkle-field",
                   "petal-arc", "scallop-band", "ribbon-loop", "round-plate",
                   "halo-burst"].contains(kind) {
            // 圆滑族：底面整块平涂，圆形压在上面且保留 ink 描边。
            addBlock(path: rectPath(full), fill: tone(0), delay: 0.02)
            let discs = 5 + Int(r01(3, 205) * 5)
            for i in 0..<discs {
                let radius = min(w, h) * CGFloat(0.05 + r01(i, 207) * 0.13)
                let cx = w * CGFloat(0.12 + r01(i, 209) * 0.76)
                let cy = h * CGFloat(0.14 + r01(i, 211) * 0.72)
                addBlock(path: UIBezierPath(ovalIn: CGRect(x: cx - radius, y: cy - radius,
                                                           width: radius * 2, height: radius * 2)),
                         fill: tone(1 + (i % 3)), stroke: palette.ink, strokeWidth: 1.6,
                         delay: 0.05 * Double(i), drift: true)
            }
        } else if ["iris-hole", "slot-rail", "punch-row", "film-gate", "cross-vent",
                   "louvre-slats", "ring-eye", "notch-stack", "wedge-gap",
                   "dot-sieve"].contains(kind) {
            // 镂空族：一张平涂铁板 + 洞（even-odd 打穿到宿主背景）。
            let hole = CGRect(x: w * 0.34, y: h * 0.3, width: w * 0.32, height: h * 0.4)
            let plate = UIBezierPath(rect: full)
            if kind == "iris-hole" || kind == "ring-eye" {
                plate.append(UIBezierPath(ovalIn: hole))
            } else {
                plate.append(UIBezierPath(rect: hole))
            }
            plate.usesEvenOddFillRule = true
            let layer = CAShapeLayer()
            layer.path = plate.cgPath
            layer.fillRule = .evenOdd
            layer.fillColor = tone(2).cgColor
            layer.opacity = 0
            blocksContainer.layer.addSublayer(layer)
            blockItems.append(BlockItem(
                layer: layer, baseX: 0, baseY: 0, baseAlpha: 1,
                delayFraction: 0.05, spanFraction: 0.45, drift: false,
                driftPhase: 0, pathBounds: full, fillLuminance: temperaLuminance(tone(2))))
            addBlock(path: rectPath(CGRect(x: 0, y: h * 0.82, width: w, height: h * 0.18)),
                     fill: tone(3), delay: 0.14)
        } else if ["flow-channel", "twin-channel", "reed-run", "taper-channel",
                   "chain-ports", "dash-channel", "window-run", "bridge-span",
                   "braid-channel", "port-ladder"].contains(kind) {
            // 走廊族：沿 flow 的通道两端伸出画外，两侧实填、通道露背景。
            let angle = shot.flowAngle
            let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
            let nx = -dy, ny = dx
            let cx = w / 2, cy = h / 2
            let halfChannel = min(w, h) * 0.14
            let length = max(w, h) * 1.2
            func side(sign: CGFloat) -> UIBezierPath {
                let near = halfChannel * sign
                let far = (max(w, h) * 0.75) * sign
                return polyPath([
                    CGPoint(x: cx + nx * near - dx * length, y: cy + ny * near - dy * length),
                    CGPoint(x: cx + nx * far - dx * length, y: cy + ny * far - dy * length),
                    CGPoint(x: cx + nx * far + dx * length, y: cy + ny * far + dy * length),
                    CGPoint(x: cx + nx * near + dx * length, y: cy + ny * near + dy * length),
                ])
            }
            addBlock(path: side(sign: 1), fill: tone(1), delay: 0.05)
            addBlock(path: side(sign: -1), fill: tone(2), delay: 0.1)
        } else if ["apex-mass", "ziggurat", "slab-wall", "cantilever", "pylon-pair",
                   "plinth-stack", "buttress-run", "void-core", "shear-block",
                   "ridge-line", "chasm", "overhang", "step-well", "pier-row",
                   "revetment", "tower-crop", "lintel", "rubble-fan", "gnomon",
                   "poster-panel", "diamond-stack", "arrow-wedge", "edge-bleed",
                   "ribbon-cross", "half-disc", "stacked-slabs", "triangle-mass"].contains(kind) {
            // 巨构/海报族：一块大到伸出画外的哑光体量 + 细测量线。
            addBlock(path: polyPath([CGPoint(x: w * 0.06, y: h * 1.02),
                                     CGPoint(x: w * 0.52, y: h * 0.16),
                                     CGPoint(x: w * 1.04, y: h * 1.02)]),
                     fill: tone(3), delay: 0.06)
            addBlock(path: rectPath(CGRect(x: -w * 0.05, y: h * 0.78, width: w * 1.1, height: h * 0.1)),
                     fill: tone(1), delay: 0.14)
            let measure = UIBezierPath()
            measure.move(to: CGPoint(x: 0, y: h * 0.3))
            measure.addLine(to: CGPoint(x: w, y: h * 0.3))
            addBlock(path: measure, fill: .clear,
                     stroke: palette.ink.withAlphaComponent(0.45), strokeWidth: 1,
                     delay: 0.2)
        } else if ["sight-mark", "dial-scale", "chevron-run", "tally-column",
                   "grid-focus", "axis-caps", "strobe-slats", "offset-plate",
                   "radial-comb", "bracket-target"].contains(kind) {
            // 仪表族：规矩装饰围着一个重心块。
            addBlock(path: rectPath(CGRect(x: w * 0.34, y: h * 0.28, width: w * 0.32, height: h * 0.44)),
                     fill: tone(3), stroke: palette.ink, strokeWidth: 1.6, delay: 0.08)
            for i in 0..<8 {
                let x = w * (0.06 + 0.11 * CGFloat(i))
                addBlock(path: rectPath(CGRect(x: x, y: h * 0.06, width: 2, height: h * 0.05)),
                         fill: tone(2), delay: 0.04 * Double(i))
            }
        } else {
            // 稀疏族：纸面 + 少量点/线。
            for i in 0..<10 {
                let px = w * CGFloat(r01(i, 213))
                let py = h * CGFloat(r01(i, 215))
                let radius = CGFloat(2 + r01(i, 217) * 4)
                addBlock(path: UIBezierPath(ovalIn: CGRect(x: px, y: py, width: radius, height: radius)),
                         fill: tone(2), delay: 0.05 * Double(i))
            }
        }
        buildHatch(size: size)
    }

    /// 网点 hatch：只落在第一块实心色块上（凸矩形近似裁剪），
    /// 斜线角度取 decor.hatchAngle（浅斜，±π/4）。
    private func buildHatch(size: CGSize) {
        guard tuning.showDecor else { return }
        let spacing: CGFloat = 9
        let angle = CGFloat(shot.decor.hatchAngle)
        let path = UIBezierPath()
        let diag = hypot(size.width, size.height)
        var offset = -diag
        while offset < diag {
            let cx = size.width / 2 + cos(angle + .pi / 2) * offset
            let cy = size.height / 2 + sin(angle + .pi / 2) * offset
            path.move(to: CGPoint(x: cx - cos(angle) * diag / 2, y: cy - sin(angle) * diag / 2))
            path.addLine(to: CGPoint(x: cx + cos(angle) * diag / 2, y: cy + sin(angle) * diag / 2))
            offset += spacing
        }
        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.strokeColor = palette.ink.withAlphaComponent(0.16).cgColor
        layer.lineWidth = 1
        layer.fillColor = nil
        // 裁到画面内（网页按形状半平面裁剪；原生以画面为界近似，
        // hatch 只作底纹、不压字区判定）。
        layer.frame = CGRect(origin: .zero, size: size)
        blocksContainer.layer.addSublayer(layer)
    }

    // MARK: 装饰（贯穿线 / motif / 水印 / 碎字）

    private func buildDecor(size: CGSize) {
        let profile = temperaProfile(for: shot.kind)
        guard tuning.showDecor, profile.sharedDecor else { return }
        let w = size.width, h = size.height
        // 贯穿斜线（满出血，crossCount 1...3）。
        for i in 0..<shot.decor.crossCount {
            let yBase = h * CGFloat(0.2 + 0.3 * Double(i))
            let path = UIBezierPath()
            path.move(to: CGPoint(x: -w * 0.05, y: yBase + h * 0.12))
            path.addLine(to: CGPoint(x: w * 1.05, y: yBase - h * 0.12))
            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.strokeColor = palette.ink.withAlphaComponent(0.35).cgColor
            layer.lineWidth = 1
            decorContainer.layer.addSublayer(layer)
        }
        // 水印大字（反色层之下：先于字形容器添加即在其下；
        // textContainer 在 decorContainer 之上，层序已保证）。
        if let watermark = shot.decor.watermark {
            let label = UILabel()
            label.text = watermark.text
            let sizePt = max(48, glyphBaseFontSize(size: size) * CGFloat(watermark.scale))
            label.font = StageFonts.bold(size: sizePt)
            label.textColor = palette.tone3.withAlphaComponent(0.5)
            label.sizeToFit()
            label.center = CGPoint(x: w * CGFloat(watermark.x), y: h * CGFloat(watermark.y))
            label.transform = CGAffineTransform(rotationAngle: CGFloat(watermark.rotation))
            decorContainer.addSubview(label)
            watermarkLabel = label
        }
        // 边角碎字（稀疏构图）。
        for fragment in shot.decor.fragments {
            let label = UILabel()
            label.text = fragment.char
            label.font = StageFonts.bold(size: max(12, glyphBaseFontSize(size: size) * CGFloat(fragment.scale)))
            label.textColor = palette.ink.withAlphaComponent(0.55)
            label.sizeToFit()
            label.center = CGPoint(x: w * CGFloat(fragment.x), y: h * CGFloat(fragment.y))
            label.transform = CGAffineTransform(rotationAngle: CGFloat(fragment.rotation))
            decorContainer.addSubview(label)
        }
    }

    /// baseFontSize（temperaSceneBuilder.ts）：max(34, min(150,
    /// (W / max(5, maxGraphemes × 1.05)) × 1.5))。
    private func glyphBaseFontSize(size: CGSize) -> CGFloat {
        let maxGraphemes = max(3, shot.lineSegments.map {
            $0.reduce(0) { $0 + $1.text.count }
        }.max() ?? 3)
        return max(34, min(150, (size.width / max(5, CGFloat(maxGraphemes) * 1.05)) * 1.5))
    }

    // MARK: 拼贴排版（temperaLayout.ts 对译）

    private func buildGlyphLayout(size: CGSize) {
        let profile = temperaProfile(for: shot.kind)
        let w = size.width, h = size.height
        let regionW = w * CGFloat(profile.w)
        let regionH = h * CGFloat(profile.h)
        let regionCX = w * CGFloat(profile.cx)
        let regionCY = h * CGFloat(profile.cy)
        let seed = shot.seed
        let baseFont = glyphBaseFontSize(size: size)

        // 词单元（segment 即词）：hero 词 1.34~1.6×、其余 0.7~0.86×。
        struct WordUnit {
            var text: String
            var lineIndex: Int
            var scale: Double
            var width: CGFloat
            var leadingGap: CGFloat
            var graphemes: [(char: String, start: TimeInterval, end: TimeInterval)]
        }
        func buildWords(fontSize: CGFloat) -> [[WordUnit]] {
            shot.lineSegments.enumerated().map { lineIndex, segments in
                // hero 选取：词长最长者候选集内种子抽一。
                let lengths = segments.map { $0.text.count }
                let maxLength = lengths.max() ?? 0
                let candidates = lengths.enumerated().filter {
                    $0.element > 0 && $0.element >= maxLength - 1
                }.map { $0.offset }
                let hero = candidates.isEmpty ? -1
                    : candidates[Int(temperaHash01(seed, lineIndex, 101) * Double(candidates.count)) % candidates.count]
                var previousEnd: Int? = nil
                var offsetCursor = 0
                return segments.enumerated().map { segIndex, segment in
                    let scale = segIndex == hero
                        ? 1.34 + temperaHash01(seed, lineIndex * 31 + segIndex, 103) * 0.26
                        : 0.7 + temperaHash01(seed, lineIndex * 31 + segIndex, 107) * 0.16
                    let font = StageFonts.bold(size: fontSize * CGFloat(scale))
                    let width = (segment.text as NSString)
                        .size(withAttributes: [.font: font]).width
                    let spaced = previousEnd != nil && offsetCursor > (previousEnd ?? 0)
                    let gap: CGFloat = previousEnd == nil ? 0
                        : fontSize * (spaced ? 0.26 : 0.035)
                    previousEnd = offsetCursor + segment.text.count
                    offsetCursor += segment.text.count
                    let graphemes: [(String, TimeInterval, TimeInterval)] =
                        segment.graphemeTimes.enumerated().map { gi, gt in
                            let chars = Array(segment.text)
                            let ch = gi < chars.count ? String(chars[gi]) : ""
                            return (ch, gt.start, gt.end)
                        }.filter { !$0.0.isEmpty }
                    return WordUnit(text: segment.text, lineIndex: lineIndex,
                                    scale: scale, width: width, leadingGap: gap,
                                    graphemes: graphemes.map {
                                        (char: $0.0, start: $0.1, end: $0.2)
                                    })
                }
            }
        }

        // fit loop（最多 4 次，网页同）：装不下按比例缩字号。
        var fontSize = max(14, baseFont * CGFloat(profile.fontScale))
        var rows: [(words: [WordUnit], width: CGFloat, height: CGFloat)] = []
        for _ in 0..<4 {
            let linesWords = buildWords(fontSize: fontSize)
            var packed: [(words: [WordUnit], width: CGFloat, height: CGFloat)] = []
            for words in linesWords {
                var current: [WordUnit] = []
                var currentWidth: CGFloat = 0
                func budget(_ rowIndex: Int) -> CGFloat {
                    regionW * CGFloat(0.72 + temperaHash01(seed, rowIndex, 109) * 0.28)
                }
                func flush() {
                    guard !current.isEmpty else { return }
                    let tallest = current.map { $0.scale }.max() ?? 1
                    let rowHeight = fontSize * CGFloat(tallest)
                        * CGFloat(1.02 + temperaHash01(seed, packed.count, 113) * 0.1)
                    packed.append((current, currentWidth, rowHeight))
                    current = []
                    currentWidth = 0
                }
                for word in words {
                    let advance = current.isEmpty ? word.width : word.width + word.leadingGap
                    if !current.isEmpty && currentWidth + advance > budget(packed.count) {
                        flush()
                    }
                    currentWidth += current.isEmpty ? word.width : advance
                    current.append(word)
                }
                flush()
            }
            rows = packed
            let blockHeight = rows.reduce(0) { $0 + $1.height }
            let maxRowWidth = rows.map { $0.width }.max() ?? 1
            let fit = min(1,
                          blockHeight > regionH ? regionH / blockHeight : 1,
                          maxRowWidth > regionW ? regionW / maxRowWidth : 1)
            if fit >= 0.999 { break }
            fontSize *= fit
        }

        let blockHeight = rows.reduce(0) { $0 + $1.height }
        let enterBaseX = Double(profile.enterX) * Double(fontSize)
        let enterBaseY = Double(profile.enterY) * Double(fontSize)
        let baseAngle = atan2(enterBaseY, enterBaseX)
        let baseMagnitude = hypot(enterBaseX, enterBaseY)
        var placements: [TemperaGlyphPlacement] = []
        var cursorY = regionCY - blockHeight / 2
        for (rowIndex, row) in rows.enumerated() {
            let rowCenterY = cursorY + row.height / 2
            cursorY += row.height
            let drift = CGFloat(temperaHash01(seed, rowIndex, 127) - 0.5) * regionW * 0.06
            let rowRotation = (temperaHash01(seed, rowIndex, 131) - 0.5) * 0.06
            let rowLeft: CGFloat
            switch profile.align {
            case 1: rowLeft = regionCX - regionW / 2 + abs(drift) * 0.6
            case 2: rowLeft = regionCX + regionW / 2 - row.width - abs(drift) * 0.6
            default: rowLeft = regionCX - row.width / 2 + drift
            }
            var cursorX = rowLeft
            for (wordIndex, word) in row.words.enumerated() {
                let salt = rowIndex * 37 + wordIndex
                let styleIndex = Int(temperaHash01(seed, salt, 193)
                    * Double(temperaEnterStyles.count)) % temperaEnterStyles.count
                let enterStyle = temperaEnterStyles[styleIndex]
                let wordRotation = (temperaHash01(seed, salt, 137) - 0.5) * 0.07
                let wordShiftY = CGFloat(temperaHash01(seed, salt, 139) - 0.5) * Double(fontSize) * 0.09
                let wordLeft = cursorX + (wordIndex == 0 ? 0 : word.leadingGap)
                cursorX = wordLeft + word.width
                let glyphFont = StageFonts.bold(size: fontSize * CGFloat(word.scale))
                var glyphX = wordLeft
                for (glyphIndex, grapheme) in word.graphemes.enumerated() {
                    if grapheme.char.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                    let glyphWidth = (grapheme.char as NSString)
                        .size(withAttributes: [.font: glyphFont]).width
                    let centerX = glyphX + glyphWidth / 2
                    let centerY = rowCenterY + wordShiftY
                    glyphX += glyphWidth
                    let glyphSalt = salt * 53 + glyphIndex
                    let spread = (temperaHash01(seed, glyphSalt, 149) - 0.5) * 1.7
                    let magnitude = baseMagnitude * (0.55 + temperaHash01(seed, glyphSalt, 151) * 1.05)
                    let angle = baseAngle + spread
                    // 字下亮度：最上层命中色块（后加者在上）。
                    var under = temperaLuminance(palette.paper)
                    for entry in blockUnderRects where entry.rect.contains(CGPoint(x: centerX, y: centerY)) {
                        under = entry.luminance
                    }
                    placements.append(TemperaGlyphPlacement(
                        char: grapheme.char, x: centerX, y: centerY,
                        rotation: profile.rotation + rowRotation + wordRotation,
                        start: grapheme.start, end: grapheme.end, settle: grapheme.end,
                        fontSize: fontSize * CGFloat(word.scale),
                        enterX: cos(angle) * magnitude, enterY: sin(angle) * magnitude,
                        enterRotation: (temperaHash01(seed, glyphSalt, 157) - 0.5) * 0.7,
                        enterScale: 0.6 + temperaHash01(seed, glyphSalt, 163) * 0.3,
                        enterStyle: enterStyle,
                        release: grapheme.end, trackingX: 0, trackingY: 0,
                        underLuminance: under,
                        gradientT: Double(centerX / max(size.width, 1))))
                }
            }
        }
        // settleTime 与 release（applyGlyphTiming 对译）。
        if !placements.isEmpty {
            let shotLyricEnd = placements.map { $0.end }.max() ?? 0
            let stretch = min(max(tuning.glyphSettleStretch, 0), 1)
            var lineSpan: [Int: (min: TimeInterval, max: TimeInterval)] = [:]
            for (i, placement) in placements.enumerated() {
                _ = i
                let key = 0
                _ = key
                let current = lineSpan[0] ?? (min: placement.start, max: placement.end)
                lineSpan[0] = (min(current.min, placement.start), max(current.max, placement.end))
            }
            let centerX = placements.reduce(0) { $0 + $1.x } / CGFloat(placements.count)
            let centerY = placements.reduce(0) { $0 + $1.y } / CGFloat(placements.count)
            let spanAll = max(0.5, (lineSpan[0]?.max ?? 0) - (lineSpan[0]?.min ?? 0))
            for i in placements.indices {
                let reach = max(0, shotLyricEnd - placements[i].start - 0.34)
                placements[i].settle = placements[i].start + 0.34 + reach * stretch
                placements[i].release = max(placements[i].end, placements[i].settle) + spanAll
                placements[i].trackingX = placements[i].x - centerX
                placements[i].trackingY = placements[i].y - centerY
            }
        }
        glyphPlacements = placements
    }

    private func glyphColor(for placement: TemperaGlyphPlacement) -> UIColor {
        // gradient + 反色关：tint-only 形态（ramp 直接上色）。
        if palette.textGradient != nil && !tuning.textInversion {
            let ramp = palette.textGradient!
            let idx = min(3, max(0, Int(placement.gradientT * 4)))
            return ramp[idx]
        }
        if tuning.textInversion {
            // difference filter 等价判定：ink/paper 与字下亮度差大者胜；
            // gradient 时胜者色相换 ramp 对应色、亮度保持（近似：以
            // 胜者与 ramp 色按亮度对齐混合）。
            let inkLum = temperaLuminance(palette.ink)
            let paperLum = temperaLuminance(palette.paper)
            let useInk = abs(inkLum - placement.underLuminance)
                >= abs(paperLum - placement.underLuminance)
            let winner = useInk ? palette.ink : palette.paper
            if let ramp = palette.textGradient {
                let idx = min(3, max(0, Int(placement.gradientT * 4)))
                return temperaMatchLuminance(ramp[idx], target: winner)
            }
            return winner
        }
        return palette.ink
    }

    private func buildGlyphViews() {
        for placement in glyphPlacements {
            let label = UILabel()
            label.text = placement.char
            label.font = StageFonts.bold(size: placement.fontSize)
            label.textColor = glyphColor(for: placement)
            label.textAlignment = .center
            label.sizeToFit()
            // 以字形中心为锚（transform 绕中心，与网页 pivot 口径一致）。
            label.center = CGPoint(x: placement.x, y: placement.y)
            label.alpha = 0
            textContainer.addSubview(label)
            glyphLabels.append(label)
            // 运动浮影 2 层（echoLayer，不参与反色判定：同色低透明）。
            var echoes: [UILabel] = []
            for _ in 0..<2 {
                let echo = UILabel()
                echo.text = placement.char
                echo.font = label.font
                echo.textColor = label.textColor
                echo.textAlignment = .center
                echo.sizeToFit()
                echo.center = label.center
                echo.alpha = 0
                textContainer.insertSubview(echo, belowSubview: label)
                echoes.append(echo)
            }
            echoLabels.append(echoes)
        }
    }

    // MARK: 逐帧求解（绝对时间，seek 确定）

    func update(position: TimeInterval, cameraIntensity: Double,
                depthPan: Double, glyphDepth: Double) {
        guard builtSize.width > 0 else { return }
        let size = builtSize
        // 色块进场（temperaBlocks.updateTime 对译）：delay/span 按
        // lyricEnd 节奏（resolveShotPacedDuration 钳 0~1.4 / 0.7~2.6），
        // 全程沿 flow creep = easeInOut(progress) × carry × 0.35。
        let duration = max(shot.end - shot.start, 0.2)
        let paceDuration = max(shot.lyricEnd - shot.start, 0.2)
        let progress = temperaClamp01((position - shot.start) / duration)
        let carry = Double(max(size.width, size.height)) * 0.09
        let creep = temperaEaseInOut(progress) * carry * 0.35
        let flowX = cos(shot.flowAngle), flowY = sin(shot.flowAngle)
        let budget = max(0.5, paceDuration)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in blockItems {
            let rawDelay = temperaShotPacedDuration(paceDuration, item.delayFraction, 0, 1.4)
            let rawSpan = temperaShotPacedDuration(paceDuration, item.spanFraction, 0.7, 2.6)
            let compress = min(1, budget / max(rawDelay + rawSpan, 0.001))
            let delay = rawDelay * compress
            let span = max(rawSpan * compress, 0.001)
            let enter = temperaEaseEnter((position - shot.start - delay) / span)
            item.layer.opacity = Float(item.baseAlpha * enter)
            var tx = flowX * creep + Double(item.baseX)
            var ty = flowY * creep + Double(item.baseY)
            if item.drift {
                // charm 圆形的原地呼吸（drift 绕自身中心缩放/微旋，
                // 几何按局部坐标已在 addBlock 以绝对路径绘制，故只
                // 动 opacity 已足；位移呼吸以小幅平移近似）。
                tx += sin(position * 0.7 + item.driftPhase) * 3
                ty += cos(position * 0.6 + item.driftPhase) * 3
            }
            item.layer.transform = CATransform3DMakeTranslation(CGFloat(tx), CGFloat(ty), 0)
        }
        // 字形运动（resolveTemperaGlyphMotion 对译）。
        let motion = tuning.glyphMotion
        for (index, placement) in glyphPlacements.enumerated() {
            guard glyphLabels.indices.contains(index) else { continue }
            let label = glyphLabels[index]
            guard position >= placement.start else {
                label.alpha = 0
                for echo in echoLabels[index] { echo.alpha = 0 }
                continue
            }
            let window = max(placement.settle - placement.start, 0.08)
            let linear = temperaClamp01((position - placement.start) / window)
            let travel = 1 - temperaEaseEnter(linear)
            let frame = temperaEnterFrame(
                style: placement.enterStyle, enterX: placement.enterX,
                enterY: placement.enterY, enterRotation: placement.enterRotation,
                enterScale: placement.enterScale, travel: travel, linear: linear)
            let reveal = temperaClamp01((position - placement.start) / min(window, 1.35))
            let alpha = temperaEaseInOut(temperaClamp01(reveal * 2.4))
            // 当前字凸起（[start,end] 真实区间：起振→保持→衰减）。
            let sungWindow = placement.end - placement.start
            let attack = min(0.12, sungWindow * 0.5)
            let emphasis: Double = sungWindow <= 0 ? 0
                : temperaEaseInOut(temperaClamp01((position - placement.start) / max(attack, 0.02)))
                    * (1 - temperaEaseInOut(temperaClamp01((position - placement.end) / 0.26)))
            // release：唱完后整块绕中心刚性外扩 5.5%。
            let releaseStart = max(placement.end, placement.settle)
            let release = temperaEaseInOut(temperaClamp01(
                (position - releaseStart) / max(placement.release - releaseStart, 0.001)))
            let spread = release * temperaClamp01(motion) * 0.055
            let amount = temperaClamp01(motion)
            let swell = emphasis * 0.05 * amount
            // glyphDepth 视差：大字领先、小字落后（位移有上限）。
            let depthLead = (Double(placement.fontSize) / 60 - 1) * glyphDepth
            let parallaxX = -flowX * depthLead * 6 * depthPan
            let parallaxY = -flowY * depthLead * 6 * depthPan
            let finalX = frame.x * motion + Double(placement.trackingX) * spread + parallaxX
            let finalY = frame.y * motion + Double(placement.trackingY) * spread + parallaxY
            let scaleX = frame.scale + (1 - frame.scale) * (1 - amount) + swell
            let scaleY = frame.scale + (1 - frame.scale) * (1 - amount) + swell
            let rotation = placement.rotation + frame.rotation * motion
            label.alpha = CGFloat(alpha)
            label.transform = CGAffineTransform(translationX: CGFloat(finalX), y: CGFloat(finalY))
                .rotated(by: CGFloat(rotation))
                .scaledBy(x: CGFloat(scaleX), y: CGFloat(scaleY))
            // 浮影：偏移 = 入场偏移，透明度随 reveal 衰减（ECHO_ALPHA 0.5）。
            let echoAlpha = frame.echo * (1 - temperaEaseEnter(reveal)) * 0.5 * amount
            for (echoIndex, echo) in echoLabels[index].enumerated() {
                let factor = echoIndex == 0 ? 1.0 : 0.55
                echo.alpha = CGFloat(alpha * echoAlpha * factor)
                echo.transform = CGAffineTransform(
                    translationX: CGFloat(frame.x * motion * (1 + 0.35 * Double(echoIndex))),
                    y: CGFloat(frame.y * motion * (1 + 0.35 * Double(echoIndex))))
                    .rotated(by: CGFloat(rotation))
                    .scaledBy(x: CGFloat(scaleX), y: CGFloat(scaleY))
            }
        }
        CATransaction.commit()
        _ = cameraIntensity
    }
}

// MARK: - 渲染器

final class TemperaStageRenderer: LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: true, requiresSpectrum: false, supportsLineSeek: true)

    private let rootView = LyricStageRootView()
    private let shotHost = UIView()
    private let vignetteLayer = CAGradientLayer()
    private let grainView = UIImageView()
    private let cornerLayer = CAShapeLayer()
    private let creditsView = UIView()
    private var creditsBlocks: [UIView] = []
    private var creditsStart: TimeInterval = 0
    private var creditsBuiltTrackId: String? = nil

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false

    private var program: [TemperaShotData] = []
    private var programTrackId: String? = nil
    private var programLineCount = -1
    private var programWholeLine = false
    private var palette = resolveTemperaPalette(tokens: .neutralDark, mode: .duo)
    private var paletteSignature = ""

    private var currentShotView: TemperaShotView?
    private var outgoingShotView: TemperaShotView?
    private var currentShotIndex: Int? = nil
    /// §0 量测（3.7 (67) B 组）：待收敛的 shot（flip.up 记账）。
    private var probeUpPending67: Int? = nil
    /// 层图（3.7 (62) C4 做真）：layerImages placement 真消费——
    /// 每 shot 按 layerImageFrequency 的种子概率决定是否挂图，
    /// layerImageDepth 决定在 shot 之下（back）/之上（front）；
    /// 图源：placement 的 url 直链，或缺省取当前曲封面（原生包
    /// 内唯一现成图源；网页 IndexedDB 图池无原生等价物）。
    private let layerImageView = UIImageView()
    private var layerImageShotIndex: Int? = nil
    private var layerImageTask: Task<Void, Never>?
    private var builtViewportSize: CGSize = .zero
    private var wipeLayer: CAShapeLayer?
    private var grainImage: UIImage?

    init() {
        view = rootView
        rootView.backgroundColor = .clear
        shotHost.isUserInteractionEnabled = false
        rootView.addSubview(shotHost)
        vignetteLayer.type = .radial
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignetteLayer.endPoint = CGPoint(x: 1, y: 1)
        rootView.layer.addSublayer(vignetteLayer)
        grainView.isUserInteractionEnabled = false
        grainView.contentMode = .scaleToFill
        rootView.addSubview(grainView)
        cornerLayer.fillColor = nil
        cornerLayer.lineWidth = 1.6
        rootView.layer.addSublayer(cornerLayer)
        creditsView.isUserInteractionEnabled = false
        creditsView.isHidden = true
        rootView.addSubview(creditsView)
        layerImageView.isUserInteractionEnabled = false
        layerImageView.contentMode = .scaleAspectFill
        layerImageView.clipsToBounds = true
        layerImageView.isHidden = true
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        // (61) WC：入口统一过对比钳制——下游 palette.* 全走保护副本。
        var snapshot = snapshot
        snapshot.palette = snapshot.palette.contrastProtected()
        self.snapshot = snapshot
        let tuning = TemperaTuningStore.snapshotCached(now: CACurrentMediaTime())
        let signature = "\(snapshot.palette.background)|\(snapshot.palette.primary)|\(snapshot.palette.accent)|\(snapshot.palette.secondary)|\(tuning.colorMode.rawValue)|\(snapshot.palette.isDark)"
        if signature != paletteSignature {
            paletteSignature = signature
            palette = resolveTemperaPalette(tokens: snapshot.palette, mode: tuning.colorMode)
            // 调色板变 → 现行 shot 视图作废重建。
            clearShots()
        }
        if snapshot.track?.id != programTrackId
            || snapshot.lines.count != programLineCount
            || tuning.wholeLineLyrics != programWholeLine {
            programTrackId = snapshot.track?.id
            programLineCount = snapshot.lines.count
            programWholeLine = tuning.wholeLineLyrics
            program = compileProgram(snapshot: snapshot, wholeLine: tuning.wholeLineLyrics)
            clearShots()
            creditsBuiltTrackId = nil
        }
        updatePostLayers(tuning: tuning)
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if !isActive {
            // 停逐帧：frameTick 自行守门；无自建时钟/动画待停。
        }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let tuning = TemperaTuningStore.snapshotCached(now: CACurrentMediaTime())
        // wholeLineLyrics 在面板被拨动后 0.25s 内重编译（applySnapshot
        // 不随调参重发，这里逐帧对账一次布尔量，开销可忽略）。
        if tuning.wholeLineLyrics != programWholeLine {
            programWholeLine = tuning.wholeLineLyrics
            program = compileProgram(snapshot: snapshot, wholeLine: tuning.wholeLineLyrics)
            clearShots()
        }
        guard !program.isEmpty else {
            updateCredits(position: position, snapshot: snapshot)
            return
        }
        // 当前 shot：最后一个 start <= position 的 shot。
        var idx: Int? = nil
        for (i, shot) in program.enumerated() {
            if shot.start <= position { idx = i } else { break }
        }
        // 片尾：position 超过末 shot 歌词结束且接近曲目尾 → 片尾卡。
        if let last = program.last, position > last.lyricEnd + 0.6,
           let track = snapshot.track, track.duration > 0,
           position > track.duration - 12 || position > last.end + 1.5 {
            updateCredits(position: position, snapshot: snapshot)
            if currentShotView != nil { clearShots() }
            return
        }
        creditsView.isHidden = true
        guard let idx else { return }
        if idx != currentShotIndex {
            // §0 呈现侧（3.7 (67) B 组）：shot 提交点（凝彩的
            // 行以 shot 为单位）；收敛看本 shot 全部字形 reveal
            // 完成（revealDone 已在本 tick 下方同式计算，此处
            // 只记待收敛 shot，判定在 revealDone 算出处）。
            Breadcrumbs.log("flip.cmt style=tempera idx=\(idx) judge=\(SyncProbe67.fmt(position)) wall=\(SyncProbe67.fmt(CACurrentMediaTime()))")
            probeUpPending67 = idx
            transitionToShot(idx, position: position, tuning: tuning)
        }
        if idx != layerImageShotIndex {
            layerImageShotIndex = idx
            updateLayerImage(shotIndex: idx, tuning: tuning)
        }
        let shot = program[idx]
        // 镜头（temperaCamera.ts）：key 插值 eased = 0.5·linear +
        // 0.5·easeInOut，progress>1 后 0.35 外推；呼吸浮动在 reveal
        // 完成后 1.2s 渐入；整体 × cameraIntensity。
        let shotDuration = max(shot.end - shot.start, 0.2)
        let rawProgress = (position - shot.start) / shotDuration
        let clamped = temperaClamp01(rawProgress)
        let eased = clamped * 0.5 + temperaEaseInOutCubic(clamped) * 0.5
        let overshoot = max(0, rawProgress - 1) * 0.35
        let amount = eased + overshoot
        let camX = shot.camStart.x + (shot.camEnd.x - shot.camStart.x) * amount
        let camY = shot.camStart.y + (shot.camEnd.y - shot.camStart.y) * amount
        let zoom = shot.camStart.zoom + (shot.camEnd.zoom - shot.camStart.zoom) * amount
        let camRot = shot.camStart.rotation + (shot.camEnd.rotation - shot.camStart.rotation) * amount
        let revealDone = shot.lineSegments.flatMap { $0 }.map { $0.end }.max() ?? shot.start
        // §0 呈现侧（3.7 (67) B 组）：settle 收敛点——position
        // 越过本 shot 末字形 reveal 时刻（字形 settle 链的终点
        // 口径），每 shot 只落一次。
        if let pending = probeUpPending67, pending == idx, position >= revealDone {
            probeUpPending67 = nil
            Breadcrumbs.log("flip.up style=tempera idx=\(pending) judge=\(SyncProbe67.fmt(position)) wall=\(SyncProbe67.fmt(CACurrentMediaTime()))")
        }
        let breathWeight = temperaEaseInOutCubic(temperaClamp01((position - revealDone) / 1.2))
        let breath = temperaCameraBreath(time: position, phase: Double(idx) * 1.37)
        let intensity = tuning.cameraIntensity
        if let current = currentShotView {
            let size = rootView.bounds.size
            var transform = CGAffineTransform(
                translationX: CGFloat((camX + breath.x * breathWeight) * Double(size.width) * intensity),
                y: CGFloat((camY + breath.y * breathWeight) * Double(size.height) * intensity))
            transform = transform.rotated(by: CGFloat((camRot + breath.rotation * breathWeight) * intensity))
            let scale = CGFloat((zoom + breath.scale * breathWeight - 1) * intensity + 1)
            transform = transform.scaledBy(x: scale, y: scale)
            current.transform = transform
            current.update(position: position, cameraIntensity: intensity,
                           depthPan: tuning.depthPan, glyphDepth: tuning.glyphDepth)
        }
        // 交接：上一个 shot 沿 flow 继续推出（handoff 窗 = shot 时长
        // ×0.3 钳 0.4~1.1s），窗口外移除。
        if let outgoing = outgoingShotView, let outIdx = outgoingShotIndex {
            let outShot = program[outIdx]
            let handoff = min(1.1, max(0.4, (outShot.end - outShot.start) * 0.3))
            let elapsed = position - shot.start
            if !tuning.enableTransitions || elapsed > handoff {
                outgoing.removeFromSuperview()
                outgoingShotView = nil
                outgoingShotIndex = nil
            } else {
                let travel = temperaEaseInOut(elapsed / handoff)
                    * Double(max(rootView.bounds.width, rootView.bounds.height)) * 0.55
                outgoing.transform = CGAffineTransform(
                    translationX: CGFloat(cos(outShot.flowAngle) * travel),
                    y: CGFloat(sin(outShot.flowAngle) * travel))
                outgoing.update(position: position, cameraIntensity: intensity,
                                depthPan: tuning.depthPan, glyphDepth: tuning.glyphDepth)
            }
        }
        updateWipe(position: position, shot: shot, tuning: tuning)
        updatePostLayers(tuning: tuning)
    }

    private var outgoingShotIndex: Int? = nil

    func unmount() {
        isActive = false
        context = nil
        snapshot = nil
        clearShots()
        creditsView.isHidden = true
        grainImage = nil
        grainView.image = nil
    }

    // MARK: 编译（temperaProgram.ts 对译）

    private func compileProgram(snapshot: LyricStageSnapshot,
                                wholeLine: Bool) -> [TemperaShotData] {
        var lines = snapshot.lines
        // 无歌词（器乐）回退：网页 virtualLines（♪ 每 8s 一行、长 6s）。
        if lines.isEmpty, let track = snapshot.track, track.duration > 8 {
            var virtual: [LyricLine] = []
            var t = 0.0
            var vid = 0
            while t < track.duration {
                virtual.append(LyricLine(id: vid, start: t, end: min(t + 6, track.duration),
                                         text: "♪"))
                t += 8
                vid += 1
            }
            lines = virtual
        }
        guard !lines.isEmpty else { return [] }
        let seedKey = snapshot.track?.id ?? "tempera"
        let baseSeed = temperaHashSeed(seedKey)

        // 编译行：segment = StageLyricUnits 词单元（YRC 真戳或均分，
        // 与网页 grapheme timeline 的词界口径一致）；标点粘连由
        // tokenize 的 CJK/拉丁切分天然处理（标点并入拉丁 token）。
        let compiled: [TemperaCompiledLineData] = lines.enumerated().map { index, line in
            let units = StageLyricUnits.units(for: line)
            let segments = units.map { unit -> TemperaSegmentData in
                let chars = Array(unit.text)
                let span = max(unit.end - unit.start, 0.05)
                let times: [(TimeInterval, TimeInterval)] = chars.indices.map { gi in
                    (unit.start + span * Double(gi) / Double(max(chars.count, 1)),
                     unit.start + span * Double(gi + 1) / Double(max(chars.count, 1)))
                }
                return TemperaSegmentData(text: unit.text, start: unit.start,
                                          end: unit.end, graphemeTimes: times,
                                          isWordLike: true)
            }
            return TemperaCompiledLineData(sourceIndex: index, start: line.start,
                                           renderEnd: line.end, segments: segments)
        }.filter { !$0.segments.isEmpty }
        guard !compiled.isEmpty else { return [] }

        // 段落切分：gap 阈值 = clamp(median(gaps)×2.5, 1.25, 3.5)。
        var gaps: [Double] = []
        for i in 1..<compiled.count {
            let gap = compiled[i].start - min(compiled[i - 1].renderEnd, compiled[i].start)
            if gap > 0 { gaps.append(gap) }
        }
        let medianGap: Double = {
            guard !gaps.isEmpty else { return 0.5 }
            let sorted = gaps.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 0 && mid > 0
                ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }()
        let threshold = min(3.5, max(1.25, medianGap * 2.5))
        var paragraphs: [[TemperaCompiledLineData]] = []
        var currentPara: [TemperaCompiledLineData] = []
        for (i, line) in compiled.enumerated() {
            if i > 0 {
                let gap = line.start - min(compiled[i - 1].renderEnd, line.start)
                if gap >= threshold && !currentPara.isEmpty {
                    paragraphs.append(currentPara)
                    currentPara = []
                }
            }
            currentPara.append(line)
        }
        if !currentPara.isEmpty { paragraphs.append(currentPara) }
        // 过大段落拆分（>6 行或 >18s，在最大 gap 处切）简化为按 6 行切。
        paragraphs = paragraphs.flatMap { para -> [[TemperaCompiledLineData]] in
            guard para.count > 6 else { return [para] }
            var chunks: [[TemperaCompiledLineData]] = []
            var rest = para
            while rest.count > 6 {
                chunks.append(Array(rest.prefix(4)))
                rest = Array(rest.dropFirst(4))
            }
            chunks.append(rest)
            return chunks
        }

        var shots: [TemperaShotData] = []
        var lastKind: String? = nil
        var lastMotif: String? = nil
        var lastFlow: Double? = nil
        let motifs = ["diamonds", "hatch-twin", "band-cross", "poster-diamond", "doodle"]
        let transitions = ["block-wipe", "camera-pan", "shape-carry"]

        for (paraIndex, para) in paragraphs.enumerated() {
            // 段落 kind 分类（协议无 isChorus/songPart：以标点/密度近似）。
            let paraDuration = (para.last?.renderEnd ?? 0) - (para.first?.start ?? 0)
            let wordCount = para.reduce(0) { $0 + $1.segments.count }
            let punctCount = para.reduce(0) { sum, item in
                sum + snapshot.lines[item.sourceIndex].text.filter { "!?！？…".contains($0) }.count
            }
            let paraKind: String
            if paraIndex == paragraphs.count - 1 && paragraphs.count > 1 {
                paraKind = "outro"
            } else if paraDuration <= 3.5 || wordCount <= 3 {
                paraKind = "breath"
            } else if punctCount >= 2 || Double(wordCount) / max(paraDuration, 1) > 2.5 {
                paraKind = "lift"
            } else {
                paraKind = "verse"
            }

            // bridge shot：段间 gap ≥1.2s 按 ≤5s 切 1~3 个无歌词 shot。
            if paraIndex > 0, let prevEnd = paragraphs[paraIndex - 1].last?.renderEnd,
               let firstStart = para.first?.start, firstStart - prevEnd >= 1.2 {
                let gap = firstStart - prevEnd
                let count = min(3, max(1, Int(ceil(gap / 5))))
                let step = gap / Double(count)
                for b in 0..<count {
                    let bStart = prevEnd + step * Double(b)
                    let bKind = temperaChooseWithoutRepeat(
                        temperaCandidates(moods: [.quiet, .neutral]),
                        seedKey: "\(seedKey):bridge:\(paraIndex):\(b)",
                        previous: lastKind) ?? "blank-page"
                    lastKind = bKind
                    let camSeed = temperaHashSeed("\(seedKey):\(paraIndex):bridge\(b):camera")
                    let flow = resolveFlowAngle(previous: lastFlow, seed: camSeed)
                    lastFlow = flow
                    let cams = buildCameraKeys(kind: bKind, seed: camSeed, flow: flow)
                    let decor = buildDecor(paraKind: paraKind, kind: bKind,
                                           seedKey: "\(seedKey):bridge:\(paraIndex):\(b)",
                                           poolText: "", poolWords: [],
                                           previousMotif: lastMotif)
                    lastMotif = decor.motif
                    shots.append(TemperaShotData(
                        index: shots.count, kind: bKind, start: bStart,
                        end: bStart + step, lyricEnd: bStart + step,
                        lineSegments: [], isBridge: true,
                        paragraphIndex: paraIndex, isParagraphHead: b == 0,
                        transitionKind: nil, camStart: cams.start, camEnd: cams.end,
                        flowAngle: flow, decor: decor,
                        seed: baseSeed &+ UInt32(shots.count) &* 97))
                }
            }

            // shot 切分（buildShotChunks 对译）。
            struct Chunk { var lineIndex: Int; var segStart: Int; var segEnd: Int
                           var start: TimeInterval; var end: TimeInterval }
            var chunks: [Chunk] = []
            for line in para {
                let usable = line.segments
                guard !usable.isEmpty else { continue }
                if wholeLine {
                    chunks.append(Chunk(lineIndex: line.sourceIndex, segStart: 0,
                                        segEnd: usable.count,
                                        start: usable[0].start,
                                        end: max(usable[usable.count - 1].end, usable[0].start + 0.2)))
                    continue
                }
                var segStart = 0
                var startTime = usable[0].start
                var words = 0
                for (order, entry) in usable.enumerated() {
                    words += 1
                    let chunkSeed = temperaHashSeed("\(seedKey):\(paraIndex):\(line.sourceIndex):\(chunks.count)")
                    let target = 2 + Int(temperaHash01(chunkSeed, 1, 179) * 3)
                    let spent = entry.end - startTime
                    let isLast = order == usable.count - 1
                    if !isLast && words < target && spent < 2.2 { continue }
                    // 单字汉字粘连：相邻两单字词不切（上限 3.2s）。
                    if !isLast && spent < 3.2, order + 1 < usable.count {
                        let next = usable[order + 1]
                        if isSingleHan(entry.text) && isSingleHan(next.text) { continue }
                    }
                    chunks.append(Chunk(lineIndex: line.sourceIndex, segStart: segStart,
                                        segEnd: order + 1, start: startTime,
                                        end: max(entry.end, startTime + 0.2)))
                    if order + 1 < usable.count {
                        segStart = order + 1
                        startTime = usable[order + 1].start
                        words = 0
                    }
                }
            }

            let byIndex = Dictionary(uniqueKeysWithValues: compiled.map { ($0.sourceIndex, $0) })
            for (shotIndex, chunk) in chunks.enumerated() {
                guard let line = byIndex[chunk.lineIndex] else { continue }
                let slice = Array(line.segments[chunk.segStart..<chunk.segEnd])
                let sliceWordCount = slice.count
                let sparse = paraKind == "breath" || sliceWordCount <= 2
                let moods: [TemperaMood] = sparse ? [.quiet] : [.quiet, .neutral, .loud]
                let sliceText = slice.map { $0.text }.joined()
                let kind = temperaChooseWithoutRepeat(
                    temperaCandidates(moods: moods),
                    seedKey: "\(seedKey):\(paraIndex):\(shotIndex):\(sliceText)",
                    previous: lastKind) ?? "duo-split"
                lastKind = kind
                let camSeed = temperaHashSeed("\(seedKey):\(paraIndex):\(shotIndex):camera")
                let flow = resolveFlowAngle(previous: lastFlow, seed: camSeed)
                lastFlow = flow
                let cams = buildCameraKeys(kind: kind, seed: camSeed, flow: flow)
                // 装饰池：本段其余 segment（整行模式下借全曲其余行）。
                var outside = para.flatMap { item -> [TemperaSegmentData] in
                    if item.sourceIndex == chunk.lineIndex {
                        return item.segments.enumerated().filter {
                            $0.offset < chunk.segStart || $0.offset >= chunk.segEnd
                        }.map { $0.element }
                    }
                    return item.segments
                }
                if outside.isEmpty {
                    outside = compiled.filter { $0.sourceIndex != chunk.lineIndex }
                        .flatMap { $0.segments }
                }
                let decor = buildDecor(
                    paraKind: paraKind, kind: kind,
                    seedKey: "\(seedKey):\(paraIndex):\(shotIndex):decor",
                    poolText: outside.map { $0.text }.joined(),
                    poolWords: outside.map { $0.text },
                    previousMotif: lastMotif)
                lastMotif = decor.motif
                let transitionKind: String? = (shotIndex == 0 && paraIndex > 0)
                    ? temperaChooseWithoutRepeat(
                        transitions, seedKey: "\(seedKey):trans:\(paraIndex)",
                        previous: nil)
                    : nil
                shots.append(TemperaShotData(
                    index: shots.count, kind: kind, start: chunk.start,
                    end: chunk.end,
                    lyricEnd: chunk.end,
                    lineSegments: [slice], isBridge: false,
                    paragraphIndex: paraIndex, isParagraphHead: shotIndex == 0,
                    transitionKind: transitionKind,
                    camStart: cams.start, camEnd: cams.end,
                    flowAngle: flow, decor: decor,
                    seed: baseSeed &+ UInt32(shots.count) &* 97))
            }
            _ = motifs
        }
        // 平铺时间轴：每 shot end 顶到下一 shot start（lyricEnd 不动）。
        for i in shots.indices {
            let nextStart = i + 1 < shots.count ? shots[i + 1].start : shots[i].end
            shots[i].end = max(shots[i].start + 0.2, nextStart)
            if i + 1 == shots.count, let track = snapshot.track {
                shots[i].end = max(shots[i].end, min(track.duration, shots[i].lyricEnd + 2))
            }
        }
        return shots
    }

    private func isSingleHan(_ text: String) -> Bool {
        guard text.count == 1, let scalar = text.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
    }

    /// resolveFlowAngle 对译：垂直主轴、逐 shot 小幅转向并回拉。
    private func resolveFlowAngle(previous: Double?, seed: UInt32) -> Double {
        guard let previous else {
            let sign = temperaHash01(seed, 6, 71) > 0.5 ? 1.0 : -1.0
            return sign * .pi / 2 + (temperaHash01(seed, 8, 79) - 0.5) * 0.4
        }
        let axis = (sin(previous) >= 0 ? 1.0 : -1.0) * .pi / 2
        return previous + (axis - previous) * 0.3 + (temperaHash01(seed, 7, 73) - 0.5) * 0.5
    }

    /// buildCameraKeys 对译：travel 沿 flow、jitter 种子同序。
    private func buildCameraKeys(kind: String, seed: UInt32, flow: Double)
        -> (start: (x: Double, y: Double, zoom: Double, rotation: Double),
            end: (x: Double, y: Double, zoom: Double, rotation: Double)) {
        let profile = temperaProfile(for: kind)
        let jitterX = (temperaHash01(seed, 1, 11) - 0.5) * 0.02
        let jitterY = (temperaHash01(seed, 2, 23) - 0.5) * 0.02
        let jitterZoom = temperaHash01(seed, 3, 37) * 0.025
        let jitterRotation = (temperaHash01(seed, 4, 51) - 0.5) * 0.012
        let travelX = cos(flow) * profile.travel
        let travelY = sin(flow) * profile.travel
        return (
            start: (-travelX / 2 + jitterX, -travelY / 2 + jitterY,
                    profile.zoomStart + jitterZoom, jitterRotation),
            end: (travelX / 2 + jitterX, travelY / 2 + jitterY,
                  profile.zoomEnd + jitterZoom, -jitterRotation))
    }

    /// buildDecorSpec 对译（motif 无重复抽选、hatch 浅斜、碎字/水印池）。
    private func buildDecor(paraKind: String, kind: String, seedKey: String,
                            poolText: String, poolWords: [String],
                            previousMotif: String?) -> TemperaDecorData {
        let seed = temperaHashSeed(seedKey)
        let motif = temperaChooseWithoutRepeat(
            ["diamonds", "hatch-twin", "band-cross", "poster-diamond", "doodle"],
            seedKey: seedKey, previous: previousMotif) ?? "diamonds"
        let profile = temperaProfile(for: kind)
        let sparse = profile.mood == .quiet || paraKind == "break" || paraKind == "outro"
        var fragments: [(String, Double, Double, Double, Double)] = []
        if sparse {
            let chars = poolText.filter { !$0.isWhitespace }.map { String($0) }
            let count = 3 + Int(temperaHash01(seed, 3, 101) * 3)
            if !chars.isEmpty {
                for i in 0..<count {
                    let ch = chars[Int(temperaHash01(seed, i, 13) * Double(chars.count)) % chars.count]
                    let onLeft = temperaHash01(seed, i, 29) > 0.5
                    let edge = 0.03 + temperaHash01(seed, i, 41) * 0.13
                    fragments.append((ch, onLeft ? edge : 1 - edge,
                                      0.08 + temperaHash01(seed, i, 53) * 0.84,
                                      (temperaHash01(seed, i, 67) - 0.5) * 0.5,
                                      0.26 + temperaHash01(seed, i, 71) * 0.2))
                }
            }
        }
        var watermark: (String, Double, Double, Double, Double)? = nil
        let words = poolWords.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count <= 12 }
        if profile.mood != .loud, !words.isEmpty,
           temperaHash01(seed, 4, 107) <= 0.62 {
            watermark = (words[Int(temperaHash01(seed, 5, 109) * Double(words.count)) % words.count],
                         0.28 + temperaHash01(seed, 6, 113) * 0.44,
                         0.26 + temperaHash01(seed, 7, 127) * 0.48,
                         (temperaHash01(seed, 8, 131) - 0.5) * 0.5,
                         2.6 + temperaHash01(seed, 9, 137) * 1.9)
        }
        return TemperaDecorData(
            motif: motif,
            hatchAngle: (temperaHash01(seed, 1, 83) - 0.5) * (.pi / 2),
            crossCount: 1 + Int(temperaHash01(seed, 2, 89) * 3),
            fragments: fragments.map {
                (char: $0.0, x: $0.1, y: $0.2, rotation: $0.3, scale: $0.4)
            },
            watermark: watermark.map {
                (text: $0.0, x: $0.1, y: $0.2, rotation: $0.3, scale: $0.4)
            })
    }

    // MARK: Shot 切换与交接

    private func clearShots() {
        currentShotView?.removeFromSuperview()
        outgoingShotView?.removeFromSuperview()
        currentShotView = nil
        outgoingShotView = nil
        currentShotIndex = nil
        outgoingShotIndex = nil
        wipeLayer?.removeFromSuperlayer()
        wipeLayer = nil
    }

    private func transitionToShot(_ idx: Int, position: TimeInterval,
                                  tuning: TemperaTuningValues) {
        // 旧 shot 转交接（enableTransitions 关时直接移除）。
        if let current = currentShotView, let oldIdx = currentShotIndex,
           tuning.enableTransitions {
            outgoingShotView?.removeFromSuperview()
            outgoingShotView = current
            outgoingShotIndex = oldIdx
        } else {
            currentShotView?.removeFromSuperview()
            outgoingShotView?.removeFromSuperview()
            outgoingShotView = nil
            outgoingShotIndex = nil
        }
        let shot = program[idx]
        let shotView = TemperaShotView(shot: shot, palette: palette, tuning: tuning)
        shotView.build(size: rootView.bounds.size)
        shotHost.addSubview(shotView)
        currentShotView = shotView
        currentShotIndex = idx
        builtViewportSize = rootView.bounds.size
        // block-wipe：段首 shot 带 wipe 遮罩层（tone4 全幅）。
        wipeLayer?.removeFromSuperlayer()
        wipeLayer = nil
        if shot.isParagraphHead, shot.transitionKind == "block-wipe",
           tuning.enableTransitions {
            let layer = CAShapeLayer()
            layer.path = UIBezierPath(rect: rootView.bounds).cgPath
            layer.fillColor = palette.tone4.cgColor
            rootView.layer.addSublayer(layer)
            wipeLayer = layer
        }
    }

    /// block-wipe 进程 0..2：1 为满覆盖（场景已在覆盖下完成切换），
    /// 1..2 揭开。原生切换发生在 shot 起点，故只演揭开段（1..2）。
    private func updateWipe(position: TimeInterval, shot: TemperaShotData,
                            tuning: TemperaTuningValues) {
        guard let wipeLayer else { return }
        let duration = min(1.1, max(0.4, (shot.end - shot.start) * 0.3))
        let elapsed = position - shot.start
        if elapsed > duration || !tuning.enableTransitions {
            wipeLayer.removeFromSuperlayer()
            self.wipeLayer = nil
            return
        }
        let reveal = temperaEaseInOut(temperaClamp01(elapsed / duration))
        let size = rootView.bounds.size
        let dx = CGFloat(cos(shot.flowAngle)) * size.width * CGFloat(reveal)
        let dy = CGFloat(sin(shot.flowAngle)) * size.height * CGFloat(reveal)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wipeLayer.transform = CATransform3DMakeTranslation(dx, dy, 0)
        CATransaction.commit()
    }

    // MARK: 镜头呼吸（temperaCamera.ts 对译）

    private func temperaEaseInOutCubic(_ value: Double) -> Double {
        let t = temperaClamp01(value)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private func temperaCameraBreath(time: TimeInterval, phase: Double)
        -> (x: Double, y: Double, scale: Double, rotation: Double) {
        let tau = time * .pi * 2
        return (
            x: (sin(tau * 0.13 + phase) * 0.65 + sin(tau * 0.31 + phase * 1.7) * 0.35) * 0.006,
            y: (cos(tau * 0.11 + phase * 2.3) * 0.65 + sin(tau * 0.29 + phase * 0.9) * 0.35) * 0.006,
            scale: sin(tau * 0.09 + phase * 1.3) * 0.002,
            rotation: sin(tau * 0.07 + phase * 2.9) * 0.0015)
    }

    // MARK: 后处理与角标（近似层）

    private func updatePostLayers(tuning: TemperaTuningValues) {
        let size = rootView.bounds.size
        guard size.width > 0 else { return }
        // 暗角：postProcessVignette（0...2）→ 径向渐变末端 alpha。
        if tuning.postProcessEnabled && tuning.postProcessVignette > 0 {
            let alpha = CGFloat(min(0.55, 0.28 * tuning.postProcessVignette))
            vignetteLayer.frame = rootView.bounds
            vignetteLayer.colors = [UIColor.clear.cgColor,
                                    UIColor.black.withAlphaComponent(alpha).cgColor]
            vignetteLayer.isHidden = false
        } else {
            vignetteLayer.isHidden = true
        }
        // 颗粒：128×128 程序噪点平铺（单张小图，内存可忽略）。
        if tuning.postProcessEnabled && tuning.postProcessGrain > 0 {
            if grainImage == nil { grainImage = makeGrainImage() }
            grainView.image = grainImage
            grainView.frame = rootView.bounds
            grainView.alpha = CGFloat(0.35 * tuning.postProcessGrain)
            grainView.isHidden = false
        } else {
            grainView.isHidden = true
        }
        // 对比：墨色半透明层近似（postProcessContrast × 0.12）。
        rootView.backgroundColor = .clear
        // 边角标记（左上/右下两枚套准框，showCornerMarks）。
        if tuning.showCornerMarks {
            let path = UIBezierPath()
            let len: CGFloat = 18
            let inset: CGFloat = 14
            path.move(to: CGPoint(x: inset, y: inset + len))
            path.addLine(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: inset + len, y: inset))
            path.move(to: CGPoint(x: size.width - inset - len, y: size.height - inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - len))
            cornerLayer.path = path.cgPath
            cornerLayer.strokeColor = palette.ink.withAlphaComponent(0.7).cgColor
            cornerLayer.isHidden = false
        } else {
            cornerLayer.isHidden = true
        }
    }

    private func makeGrainImage() -> UIImage? {
        // 确定性 LCG 噪点（进程内只生成一次，128×128 RGBA ≈ 64KB）。
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var state: UInt32 = 0x2545_F491
        for i in 0..<(side * side) {
            state = state &* 1_664_525 &+ 1_013_904_223
            let value = UInt8((state >> 24) & 0xFF)
            pixels[i * 4] = value
            pixels[i * 4 + 1] = value
            pixels[i * 4 + 2] = value
            pixels[i * 4 + 3] = 255
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: 片尾卡（temperaCreditsLayer.ts 对译）

    private func updateCredits(position: TimeInterval, snapshot: LyricStageSnapshot) {
        guard let track = snapshot.track else {
            creditsView.isHidden = true
            return
        }
        if creditsBuiltTrackId != track.id {
            creditsBuiltTrackId = track.id
            buildCredits(track: track)
            creditsStart = position
        }
        creditsView.isHidden = false
        creditsView.frame = rootView.bounds
        // 各块沿内推方向以 1 - e^(-t/7) 渐近推移，永动不跑飞。
        let t = max(position - creditsStart, 0)
        let drift = 1 - exp(-t / 7)
        for (i, block) in creditsBlocks.enumerated() {
            let direction: CGFloat = i % 2 == 0 ? 1 : -1
            block.transform = CGAffineTransform(
                translationX: direction * CGFloat(drift) * 26,
                y: direction * CGFloat(drift) * 10)
        }
    }

    private func buildCredits(track: TrackMeta) {
        for sub in creditsView.subviews { sub.removeFromSuperview() }
        creditsBlocks = []
        let size = rootView.bounds.size
        guard size.width > 0 else { return }
        let background = UIView(frame: CGRect(origin: .zero, size: size))
        background.backgroundColor = palette.tone1
        creditsView.addSubview(background)
        // 沿 tone 阶梯递进的实心块（部分圆盘以圆角矩形近似：圆心落画外）。
        let tones = [palette.tone2, palette.tone3, palette.tone4]
        for (i, tone) in tones.enumerated() {
            let block = UIView()
            let radius = size.width * CGFloat(0.42 + 0.14 * Double(i))
            block.frame = CGRect(x: size.width * (i % 2 == 0 ? -0.25 : 0.45),
                                 y: size.height * CGFloat(0.12 + 0.24 * Double(i)),
                                 width: radius, height: radius)
            block.backgroundColor = tone
            block.layer.cornerRadius = radius / 2
            creditsView.addSubview(block)
            creditsBlocks.append(block)
        }
        // 硬墨缝（split 系同口径 2.4pt / alpha 0.8）。
        let seam = UIView(frame: CGRect(x: 0, y: size.height * 0.52,
                                        width: size.width, height: 2.4))
        seam.backgroundColor = palette.ink.withAlphaComponent(0.8)
        creditsView.addSubview(seam)
        // 标题/艺人/专辑（同样走反色判定近似：以 ink/paper 对比胜者）。
        let titleLabel = UILabel()
        titleLabel.text = track.title
        titleLabel.font = StageFonts.bold(size: 34)
        titleLabel.textColor = abs(temperaLuminance(palette.ink) - temperaLuminance(palette.tone2))
            >= abs(temperaLuminance(palette.paper) - temperaLuminance(palette.tone2))
            ? palette.ink : palette.paper
        titleLabel.textAlignment = .center
        titleLabel.frame = CGRect(x: 24, y: size.height * 0.36,
                                  width: size.width - 48, height: 44)
        creditsView.addSubview(titleLabel)
        let artistLabel = UILabel()
        artistLabel.text = track.artist
        artistLabel.font = StageFonts.light(size: 17)
        artistLabel.textColor = titleLabel.textColor
        artistLabel.textAlignment = .center
        artistLabel.frame = CGRect(x: 24, y: size.height * 0.36 + 48,
                                   width: size.width - 48, height: 24)
        creditsView.addSubview(artistLabel)
        if !track.album.isEmpty {
            let albumLabel = UILabel()
            albumLabel.text = track.album
            albumLabel.font = StageFonts.light(size: 14)
            albumLabel.textColor = titleLabel.textColor.withAlphaComponent(0.75)
            albumLabel.textAlignment = .center
            albumLabel.frame = CGRect(x: 24, y: size.height * 0.36 + 76,
                                      width: size.width - 48, height: 20)
            creditsView.addSubview(albumLabel)
        }
    }

    // MARK: 布局

    /// 层图消费（(62) C4）：解析 layerImagesJSON placement 数组
    /// （[{url?, x?, y?, scale?, opacity?}]，x/y/scale 为 0...1
    /// 相对量）；本 shot 的种子概率 < layerImageFrequency 才挂。
    private func updateLayerImage(shotIndex: Int, tuning: TemperaTuningValues) {
        layerImageTask?.cancel()
        guard let data = tuning.layerImagesJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !raw.isEmpty else {
            layerImageView.isHidden = true
            return
        }
        let roll = Double(temperaMixSeed(
            temperaHashSeed(snapshot?.track?.id ?? ""), shotIndex * 131 + 7) % 1000) / 1000
        guard roll < tuning.layerImageFrequency else {
            layerImageView.isHidden = true
            return
        }
        let placement = raw[shotIndex % raw.count]
        let relX = (placement["x"] as? Double) ?? 0.5
        let relY = (placement["y"] as? Double) ?? 0.5
        let relScale = min(max((placement["scale"] as? Double) ?? 0.42, 0.1), 1)
        let opacity = min(max((placement["opacity"] as? Double) ?? 0.85, 0), 1)
        let bounds = rootView.bounds
        let side = bounds.width * CGFloat(relScale)
        layerImageView.frame = CGRect(
            x: bounds.width * CGFloat(relX) - side / 2,
            y: bounds.height * CGFloat(relY) - side / 2,
            width: side, height: side)
        layerImageView.alpha = CGFloat(opacity)
        // depth：back 在 shotHost 之下、front 在其上（credits 之下）。
        layerImageView.removeFromSuperview()
        if tuning.layerImageDepth == "front" {
            rootView.insertSubview(layerImageView, belowSubview: creditsView)
        } else {
            rootView.insertSubview(layerImageView, belowSubview: shotHost)
        }
        layerImageView.isHidden = false
        if let urlText = placement["url"] as? String, let url = URL(string: urlText) {
            layerImageTask = Task { [weak self] in
                let image = await NativeCoverLoader.shared.image(
                    for: url.absoluteString, tier: 512)
                await MainActor.run {
                    guard let self, self.layerImageShotIndex == shotIndex else { return }
                    self.layerImageView.image = image
                    self.layerImageView.isHidden = image == nil
                }
            }
        } else if let raw = snapshot?.track?.artworkURL {
            layerImageTask = Task { [weak self] in
                let image = await NativeCoverLoader.shared.image(for: raw, tier: 512)
                await MainActor.run {
                    guard let self, self.layerImageShotIndex == shotIndex else { return }
                    self.layerImageView.image = image
                    self.layerImageView.isHidden = image == nil
                }
            }
        } else {
            layerImageView.isHidden = true
        }
        Breadcrumbs.log("stage62.tempera layerImage shot=\(shotIndex) depth=\(tuning.layerImageDepth)")
    }

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        shotHost.frame = bounds
        vignetteLayer.frame = bounds
        cornerLayer.frame = bounds
        grainView.frame = bounds
        creditsView.frame = bounds
        // 视口变化（旋转）→ 现行/交接 shot 按新 bounds 重建布局。
        if builtViewportSize != .zero && builtViewportSize != bounds.size,
           let idx = currentShotIndex, let snapshot {
            let tuning = TemperaTuningStore.snapshotCached(now: CACurrentMediaTime())
            clearShots()
            if program.indices.contains(idx) {
                let shotView = TemperaShotView(shot: program[idx], palette: palette,
                                               tuning: tuning)
                shotView.build(size: bounds.size)
                shotHost.addSubview(shotView)
                currentShotView = shotView
                currentShotIndex = idx
                builtViewportSize = bounds.size
            }
            _ = snapshot
        }
        if let current = currentShotView, current.frame.size != bounds.size,
           builtViewportSize == .zero {
            current.build(size: bounds.size)
            builtViewportSize = bounds.size
        }
    }
}
