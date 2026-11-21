import UIKit

// 封面调色板提取（舞台用）：把封面降采样到 12×12 后按简单统计
// 派生 PaletteTokens——只出语义色，不出原始像素（协议冻结面）。
// 规则：平均色压暗为背景；平均色提亮为 primary；采样点里饱和度
// 最高的一簇取均值为 accent；明暗按平均亮度判，文字色随之定。
enum StagePalette {

    static func tokens(from image: UIImage) -> PaletteTokens {
        guard let averages = sample(image) else { return .neutralDark }
        let (avg, accentAvg) = averages
        let luminance = 0.2126 * avg.r + 0.7152 * avg.g + 0.0722 * avg.b
        let isDark = luminance < 0.55
        let background = mix(avg, toward: isDark ? 0 : 1, amount: isDark ? 0.45 : 0.25)
        let primary = mix(avg, toward: 1, amount: 0.35)
        let accent = accentAvg ?? mix(avg, toward: 1, amount: 0.55)
        let text: UIColor = isDark ? .white : UIColor(white: 0.08, alpha: 1)
        let secondary = mix(avg, toward: isDark ? 1 : 0, amount: 0.45)
        return PaletteTokens(
            background: UIColor(red: background.r, green: background.g, blue: background.b, alpha: 1),
            primary: UIColor(red: primary.r, green: primary.g, blue: primary.b, alpha: 1),
            secondary: UIColor(red: secondary.r, green: secondary.g, blue: secondary.b, alpha: 1),
            text: text,
            accent: UIColor(red: accent.r, green: accent.g, blue: accent.b, alpha: 1),
            isDark: isDark)
    }

    private struct RGB { var r: CGFloat; var g: CGFloat; var b: CGFloat }

    private static func mix(_ c: RGB, toward target: CGFloat, amount: CGFloat) -> RGB {
        RGB(r: c.r + (target - c.r) * amount,
            g: c.g + (target - c.g) * amount,
            b: c.b + (target - c.b) * amount)
    }

    /// 返回（全体平均色， 高饱和簇平均色）。
    private static func sample(_ image: UIImage) -> (RGB, RGB?)? {
        let side = 12
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        var sum = RGB(r: 0, g: 0, b: 0)
        var accentSum = RGB(r: 0, g: 0, b: 0)
        var accentCount: CGFloat = 0
        var count: CGFloat = 0
        for i in 0..<(side * side) {
            let r = CGFloat(pixels[i * 4]) / 255
            let g = CGFloat(pixels[i * 4 + 1]) / 255
            let b = CGFloat(pixels[i * 4 + 2]) / 255
            sum.r += r; sum.g += g; sum.b += b
            count += 1
            let maxC = max(r, g, b), minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            if saturation > 0.45 && maxC > 0.25 {
                accentSum.r += r; accentSum.g += g; accentSum.b += b
                accentCount += 1
            }
        }
        guard count > 0 else { return nil }
        let avg = RGB(r: sum.r / count, g: sum.g / count, b: sum.b / count)
        let accent = accentCount >= 3
            ? RGB(r: accentSum.r / accentCount, g: accentSum.g / accentCount, b: accentSum.b / accentCount)
            : nil
        return (avg, accent)
    }
}

// MARK: - 歌词对比保护基础设施（3.7 (61) WC 簇，全样式共用）
//
// 病灶（forensics-2026-11-21-60-feedback §2.3）：字色与底色同源于
// 封面平均色、无对比下限；字压在封面图/wash 本体上逐像素被吃；
// 非当前行 alpha 低至 0.28。三件套：①歌词层下自适应 scrim 衬底；
// ②字色对比钳制（与 background 亮度差 <0.45 时向白/黑端推满）；
// ③非当前行 alpha 下限 0.45（nonCurrentAlphaFloor）。各渲染器在
// applySnapshot 入口对 palette 调 contrastProtected()、在布局时
// 用 LyricContrastScrimView.sync 垫衬底——字色设计本身不动，只在
// 对比不足时兜底推满。

extension StagePalette {

    /// 非当前行 alpha 下限（(61) 定版 0.45）。
    static let nonCurrentAlphaFloor: CGFloat = 0.45

    /// 非当前行 alpha 钳制：低于下限者抬到下限，其余原样。
    static func flooredNonCurrentAlpha(_ alpha: CGFloat) -> CGFloat {
        max(alpha, nonCurrentAlphaFloor)
    }

    /// 相对亮度（WCAG 口径的线性化近似：sRGB 分量先按
    /// 0.2126/0.7152/0.0722 加权——与 StagePalette.tokens 的平均色
    /// 亮度判读同口径，不做 gamma 展开，保证与 isDark 判定一致）。
    static func luminance(of color: UIColor) -> CGFloat {
        color.foliaLuminance
    }

    /// 字色对比钳制：color 与 bg 的亮度差 <0.45 时，把 color 沿
    /// 「远离 bg」方向推满到达标——bg 偏暗（亮度 <0.5）向白端推、
    /// bg 偏亮向黑端推；推满仍差一点时直接落纯白/纯黑。达标或
    /// 已在端点时原样返回。保留原 alpha。
    static func contrastClamped(_ color: UIColor, against bg: UIColor) -> UIColor {
        let bgLum = luminance(of: bg)
        let fgLum = luminance(of: color)
        guard abs(fgLum - bgLum) < 0.45 else { return color }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            // 灰度色域等 getRed 失败时按 bg 方向直接落端点色。
            return bgLum < 0.5 ? UIColor(white: 1, alpha: 1)
                               : UIColor(white: 0, alpha: 1)
        }
        let target: CGFloat = bgLum < 0.5 ? 1 : 0
        // 需要的亮度位移量（向 target 端）。
        let needed = 0.45 - abs(fgLum - bgLum)
        // 沿当前色→端点色直线推进：亮度随 t 线性趋近 target，
        // t = needed / (target - fgLum)（分母为 0 即已在端点）。
        let span = target - fgLum
        guard abs(span) > 0.0001 else {
            return UIColor(white: target, alpha: a)
        }
        let t = min(1, max(0, needed / abs(span)))
        let nr = r + (target - r) * t
        let ng = g + (target - g) * t
        let nb = b + (target - b) * t
        let pushed = UIColor(red: nr, green: ng, blue: nb, alpha: a)
        // 浮点误差兜底：推后仍差 >0.01 则直接端点色。
        if abs(luminance(of: pushed) - bgLum) < 0.44 {
            return UIColor(white: target, alpha: a)
        }
        return pushed
    }
}

extension UIColor {
    /// 相对亮度（与 StagePalette.luminance 同口径）。
    var foliaLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if getRed(&r, green: &g, blue: &b, alpha: &a) {
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        var w: CGFloat = 0
        if getWhite(&w, alpha: &a) { return w }
        return 0
    }
}

extension PaletteTokens {

    /// 自适应 scrim 参数：衬底色按 isDark 取向（暗底给黑衬、亮底
    /// 给白衬——衬底与底同向加深/提亮，把字从中间带里托出来）；
    /// alpha 公式：alpha = clamp(0.52 − 0.64 × |lum − 0.5|, 0.20, 0.52)，
    /// 其中 lum = background 相对亮度。含义：底色亮度越接近中间带
    /// 0.5（字最容易被吃）衬底越强（最高 0.52），越靠两端（底本身
    /// 已深/已浅、字天然有对比）衬底越弱（最低 0.20）。
    func lyricScrim() -> (color: UIColor, alpha: CGFloat) {
        let lum = StagePalette.luminance(of: background)
        let distance = abs(lum - 0.5)
        let alpha = min(0.52, max(0.20, 0.52 - 0.64 * distance))
        return (isDark ? UIColor.black : UIColor.white, alpha)
    }

    /// 单色钳制（以本 palette 的 background 为底）。
    func lyricClamped(_ color: UIColor) -> UIColor {
        StagePalette.contrastClamped(color, against: background)
    }

    /// 整份 palette 的歌词对比保护副本：primary/secondary/accent/
    /// text 逐个过 contrastClamped（against background），background
    /// 与 isDark 不动。各渲染器在 applySnapshot 入口调用一次，下游
    /// 所有 palette.* 消费自动走钳制后的值；已达标的色原样返回，
    /// 故不改变各样式的字色设计，只兜底推满不足者。
    func contrastProtected() -> PaletteTokens {
        var copy = self
        copy.primary = lyricClamped(primary)
        copy.secondary = lyricClamped(secondary)
        copy.accent = lyricClamped(accent)
        copy.text = lyricClamped(text)
        return copy
    }
}

/// 歌词区自适应衬底视图（(61) WC 簇）：渲染器持有一只，在布局
/// 回调里 sync——首次 sync 时插入宿主指定层位（默认最底层、即
/// 背景之上、歌词容器之下），之后只更新 frame 与衬底色/透明度。
/// 只垫歌词区、不参与触摸；frame 由调用方按歌词区给（多为根
/// bounds，歌词满幅的样式即全幅；窄区样式给窄 rect）。
final class LyricContrastScrimView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// 同步衬底：不在宿主内则按 index 插入（index 钳到现有子视图
    /// 数）；已在宿主内不重排层位（避免逐帧层级抖动），只更新
    /// frame 与颜色。
    func sync(in host: UIView, palette: PaletteTokens,
              rect: CGRect, at index: Int = 0) {
        if superview !== host {
            host.insertSubview(self, at: min(max(index, 0), host.subviews.count))
        }
        frame = rect
        let scrim = palette.lyricScrim()
        backgroundColor = scrim.color.withAlphaComponent(scrim.alpha)
    }
}

/// 调参面板的对比保护说明行（(61) WC 簇）：各样式 Tuning 面板
/// 统一挂一行，文案与落点全样式一致。
enum LyricContrastProtectionNote {
    static func makeLabel() -> UILabel {
        let label = UILabel()
        label.text = "歌词对比保护已启用：衬底＋对比钳制＋非当前行下限 0.45"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }
}
