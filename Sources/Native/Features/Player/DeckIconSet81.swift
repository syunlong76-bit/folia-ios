import UIKit

/// (81) 第 8 条：四套手绘图标随主题切换。样板源稿在
/// design-samples-81/icons（A 圆润粗线/B 圆角实心/C 奶油
/// 圆托/D 圆点极简），Miller 02:45 定案四套全用、一主题
/// 一套：花海 meadow→C 奶油圆托（暖）、雪景 snow→A 圆润
/// 粗线（轻）、星空 star→B 圆角实心（暗底要实）、海洋
/// ocean→D 圆点极简（泡点）；无主题 none→A 缺省。
/// 进 App 用原生 CoreGraphics 逐个对形绘制（24 单位坐标
/// 系，与样板 SVG viewBox 同构），不引位图资产。A/B/D 出
/// 模板图（宿主 tint 决定颜色，与现行白钮口径一致）；C
/// 自带奶油盘＋深棕字形，出原色图。
enum DeckGlyph81: Hashable {
    case play, pause, prev, next
    case modeSequence, modeRepeat, modeRepeatOne, modeShuffle
    case list, heart, heartFill, star, starFill, sliders, command, paw
}

enum DeckIconSet81 {

    enum Style: Hashable { case outline, solid, cream, dots }

    static func style(for theme: MiniPlayerTheme) -> Style {
        switch theme {
        case .meadow: return .cream
        case .snow: return .outline
        case .star: return .solid
        case .ocean: return .dots
        case .none: return .outline
        }
    }

    private static var cache: [String: UIImage] = [:]

    /// pointSize＝字形框边长（宿主按钮 44 框内字形约
    /// 20–24）。渲染画布取 pointSize 的 1.9 倍留边（C 的
    /// 圆托盘需要盘缘），contentMode 由宿主 center 定心。
    static func image(_ glyph: DeckGlyph81,
                      theme: MiniPlayerTheme,
                      pointSize: CGFloat) -> UIImage {
        let style = self.style(for: theme)
        let key = "\(glyph)-\(style)-\(Int(pointSize))"
        if let hit = cache[key] { return hit }
        let canvas = pointSize * 1.9
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: canvas, height: canvas), format: format
        ).image { ctx in
            draw(glyph, style: style, canvas: canvas, in: ctx.cgContext)
        }
        let result = style == .cream
            ? image.withRenderingMode(.alwaysOriginal)
            : image.withRenderingMode(.alwaysTemplate)
        cache[key] = result
        return result
    }

    // MARK: - 绘制（24 单位坐标系 → 画布）

    private static func draw(_ glyph: DeckGlyph81, style: Style,
                             canvas: CGFloat, in c: CGContext) {
        // 字形框：画布中心、边长 canvas/1.9（与 pointSize 同步）。
        let box = canvas / 1.9
        let origin = (canvas - box) / 2
        let s = box / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin + x * s, y: origin + y * s)
        }
        if style == .cream {
            // 奶油圆托：整盘奶油色圆 + 深棕实心字形（0.78 缩）。
            let disc = CGRect(x: canvas * 0.03, y: canvas * 0.03,
                              width: canvas * 0.94, height: canvas * 0.94)
            c.setFillColor(UIColor(red: 0.976, green: 0.914, blue: 0.796, alpha: 1).cgColor)
            c.fillEllipse(in: disc)
            c.setStrokeColor(UIColor(red: 0.85, green: 0.72, blue: 0.50, alpha: 0.6).cgColor)
            c.setLineWidth(canvas * 0.012)
            c.strokeEllipse(in: disc)
            let inner = box * 0.78
            let io = (canvas - inner) / 2
            let iscale = inner / 24
            drawGlyph(glyph, mode: .solid,
                      pt: { CGPoint(x: io + $0 * iscale, y: io + $1 * iscale) },
                      unit: iscale,
                      color: UIColor(red: 0.314, green: 0.227, blue: 0.149, alpha: 1),
                      in: c)
            return
        }
        let mode: GlyphMode = style == .outline ? .stroke
            : style == .solid ? .solid : .dots
        drawGlyph(glyph, mode: mode, pt: pt, unit: s,
                  color: UIColor.black, in: c)
    }

    private enum GlyphMode { case stroke, solid, dots }

    /// 线宽/虚线按模式统一：A 粗线 2.0、B 实心以填充为
    /// 主描边 1.2 圆角、D 圆点链（线宽 2.7、dash 0.01/4.6
    /// 圆头＝点串）。
    private static func configure(_ c: CGContext, mode: GlyphMode,
                                  color: UIColor, unit: CGFloat) {
        c.setStrokeColor(color.cgColor)
        c.setFillColor(color.cgColor)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        switch mode {
        case .stroke:
            c.setLineWidth(2.0 * unit)
            c.setLineDash(phase: 0, lengths: [])
        case .solid:
            c.setLineWidth(1.2 * unit)
            c.setLineDash(phase: 0, lengths: [])
        case .dots:
            c.setLineWidth(2.7 * unit)
            c.setLineDash(phase: 0, lengths: [0.01, 4.6 * unit])
        }
    }

    private static func strokePath(_ c: CGContext, mode: GlyphMode,
                                   _ build: () -> CGPath) {
        let path = build()
        if mode == .solid {
            c.addPath(path)
            c.fillPath()
            c.addPath(path)
            c.strokePath()
        } else {
            c.addPath(path)
            c.strokePath()
        }
    }

    private static func drawGlyph(_ glyph: DeckGlyph81, mode: GlyphMode,
                                  pt: (CGFloat, CGFloat) -> CGPoint,
                                  unit: CGFloat, color: UIColor,
                                  in c: CGContext) {
        configure(c, mode: mode, color: color, unit: unit)
        switch glyph {
        case .play:
            strokePath(c, mode: mode) {
                let p = CGMutablePath()
                p.move(to: pt(9, 5.6))
                p.addLine(to: pt(9, 18.4))
                p.addLine(to: pt(19.2, 12))
                p.closeSubpath()
                return p
            }
        case .pause:
            for x in [7.4, 13.9] {
                let rect = CGRect(x: pt(x, 0).x, y: pt(0, 5.6).y,
                                  width: 3.4 * unit, height: 12.8 * unit)
                let p = CGPath(roundedRect: rect, cornerWidth: 1.7 * unit,
                               cornerHeight: 1.7 * unit, transform: nil)
                if mode == .stroke {
                    c.addPath(p); c.strokePath()
                } else if mode == .solid {
                    c.addPath(p); c.fillPath()
                } else {
                    c.addPath(p); c.strokePath()
                }
            }
        case .prev, .next:
            let flip = glyph == .next
            func fx(_ x: CGFloat) -> CGFloat { flip ? 24 - x : x }
            strokePath(c, mode: mode) {
                let p = CGMutablePath()
                p.move(to: pt(fx(9.2), 6))
                p.addLine(to: pt(fx(9.2), 18))
                p.addLine(to: pt(fx(18.6), 12))
                p.closeSubpath()
                return p
            }
            let barX = flip ? 17.6 : 4.4
            let rect = CGRect(x: pt(barX, 0).x, y: pt(0, 6).y,
                              width: 2.4 * unit, height: 12 * unit)
            let bp = CGPath(roundedRect: rect, cornerWidth: 1.2 * unit,
                            cornerHeight: 1.2 * unit, transform: nil)
            if mode == .stroke { c.addPath(bp); c.strokePath() }
            else if mode == .solid { c.addPath(bp); c.fillPath() }
            else { c.addPath(bp); c.strokePath() }
        case .modeSequence:
            // 顺序：三行队列 + 右侧播放三角（与循环的回环
            // 双箭绝不同形——(55) 图标语义撞车口径）。
            strokePath(c, mode: mode) {
                let p = CGMutablePath()
                for y in [6.4, 12.0, 17.6] {
                    p.move(to: pt(3.8, y))
                    p.addLine(to: pt(12.6, y))
                }
                p.move(to: pt(15.6, 8.6))
                p.addLine(to: pt(15.6, 15.4))
                p.addLine(to: pt(20.6, 12))
                p.closeSubpath()
                return p
            }
        case .modeRepeat, .modeRepeatOne:
            // 循环：交换双箭（回环）；单曲在中心加一竖。
            strokePath(c, mode: mode) {
                let p = CGMutablePath()
                p.move(to: pt(4, 8.6))
                p.addLine(to: pt(18.4, 8.6))
                p.move(to: pt(15, 5.2))
                p.addLine(to: pt(18.8, 8.6))
                p.addLine(to: pt(15, 12))
                p.move(to: pt(20, 15.4))
                p.addLine(to: pt(5.6, 15.4))
                p.move(to: pt(9, 12))
                p.addLine(to: pt(5.2, 15.4))
                p.addLine(to: pt(9, 18.8))
                return p
            }
            if glyph == .modeRepeatOne {
                strokePath(c, mode: mode) {
                    let p = CGMutablePath()
                    p.move(to: pt(12, 9.8))
                    p.addLine(to: pt(12, 14.2))
                    return p
                }
            }
        case .modeShuffle:
            strokePath(c, mode: mode) {
                let p = CGMutablePath()
                p.move(to: pt(3.6, 6.8))
                p.addCurve(to: pt(20.4, 17.2),
                           control1: pt(10, 6.8), control2: pt(14, 17.2))
                p.move(to: pt(16.8, 13.6))
                p.addLine(to: pt(20.4, 17.2))
                p.addLine(to: pt(16.8, 20.8))
                p.move(to: pt(3.6, 17.2))
                p.addCurve(to: pt(10.6, 10.4),
                           control1: pt(7, 17.2), control2: pt(8.6, 13.2))
                p.move(to: pt(13.4, 3.2))
                p.addCurve(to: pt(20.4, 6.8),
                           control1: pt(16, 4.6), control2: pt(17.6, 6.8))
                p.move(to: pt(16.8, 3.2))
                p.addLine(to: pt(20.4, 6.8))
                p.addLine(to: pt(16.8, 10.4))
                return p
            }
        case .list:
            strokePath(c, mode: mode) {
                let p = CGMutablePath()
                for y in [7.0, 12.0, 17.0] {
                    p.move(to: pt(9, y))
                    p.addLine(to: pt(20, y))
                }
                return p
            }
            for y in [7.0, 12.0, 17.0] {
                let center = pt(5.2, y)
                let r = (mode == .stroke ? 1.1 : 1.5) * unit
                let rect = CGRect(x: center.x - r, y: center.y - r,
                                  width: r * 2, height: r * 2)
                if mode == .stroke { c.strokeEllipse(in: rect) }
                else { c.fillEllipse(in: rect) }
            }
        case .heart, .heartFill:
            let fill = glyph == .heartFill || mode == .solid
            strokePath(c, mode: mode) {
                let p = CGMutablePath()
                p.move(to: pt(12, 20))
                p.addCurve(to: pt(4.2, 11.4),
                           control1: pt(6.4, 15.6), control2: pt(4.2, 13.4))
                p.addCurve(to: pt(8.6, 5.4),
                           control1: pt(4.2, 8.6), control2: pt(6.2, 5.4))
                p.addCurve(to: pt(12, 8.6),
                           control1: pt(10.2, 5.4), control2: pt(11.2, 6.8))
                p.addCurve(to: pt(15.4, 5.4),
                           control1: pt(12.8, 6.8), control2: pt(13.8, 5.4))
                p.addCurve(to: pt(19.8, 11.4),
                           control1: pt(17.8, 5.4), control2: pt(19.8, 8.6))
                p.addCurve(to: pt(12, 20),
                           control1: pt(19.8, 13.4), control2: pt(17.6, 15.6))
                return p
            }
            _ = fill
        case .star, .starFill:
            strokePath(c, mode: mode) {
                let p = CGMutablePath()
                let cx = 12.0, cy = 12.0, ro = 8.6, ri = 3.6
                for i in 0..<10 {
                    let r = i % 2 == 0 ? ro : ri
                    let a = -Double.pi / 2 + Double(i) * Double.pi / 5
                    let x = cx + r * CGFloat(cos(a))
                    let y = cy + r * CGFloat(sin(a))
                    if i == 0 { p.move(to: pt(x, y)) }
                    else { p.addLine(to: pt(x, y)) }
                }
                p.closeSubpath()
                return p
            }
        case .sliders:
            strokePath(c, mode: mode) {
                let p = CGMutablePath()
                for x in [6.6, 12.0, 17.4] {
                    p.move(to: pt(x, 4.6))
                    p.addLine(to: pt(x, 19.4))
                }
                return p
            }
            for (x, y) in [(6.6, 15.6), (12.0, 8.8), (17.4, 13.2)] {
                let center = pt(x, y)
                let r = 2.3 * unit
                let rect = CGRect(x: center.x - r, y: center.y - r,
                                  width: r * 2, height: r * 2)
                if mode == .solid { c.fillEllipse(in: rect) }
                else { c.strokeEllipse(in: rect) }
            }
        case .command:
            // ⌘：四角圆环 + 十字连线（小尺寸近似）。
            for (x, y) in [(7.6, 7.6), (16.4, 7.6), (7.6, 16.4), (16.4, 16.4)] {
                let center = pt(x, y)
                let r = 2.5 * unit
                c.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                           width: r * 2, height: r * 2))
            }
            strokePath(c, mode: mode) {
                let p = CGMutablePath()
                p.move(to: pt(7.6, 10.1))
                p.addLine(to: pt(7.6, 16.4))
                p.move(to: pt(16.4, 10.1))
                p.addLine(to: pt(16.4, 16.4))
                p.move(to: pt(10.1, 7.6))
                p.addLine(to: pt(16.4, 7.6))
                p.move(to: pt(10.1, 16.4))
                p.addLine(to: pt(16.4, 16.4))
                return p
            }
        case .paw:
            // 与 PawGlyphView 同几何（24 系）：主垫 + 四趾。
            let pad = pt(12, 15.4)
            let padRect = CGRect(x: pad.x - 4.4 * unit, y: pad.y - 3.6 * unit,
                                 width: 8.8 * unit, height: 7.2 * unit)
            let toes: [(CGFloat, CGFloat, CGFloat)] = [
                (5.4, 10.6, 1.9), (9.2, 7.7, 2.0),
                (14.8, 7.7, 2.0), (18.6, 10.6, 1.9),
            ]
            if mode == .solid {
                c.fillEllipse(in: padRect)
                for (x, y, r) in toes {
                    let c0 = pt(x, y)
                    c.fillEllipse(in: CGRect(x: c0.x - r * unit, y: c0.y - r * unit,
                                             width: r * 2 * unit, height: r * 2 * unit))
                }
            } else {
                c.strokeEllipse(in: padRect)
                for (x, y, r) in toes {
                    let c0 = pt(x, y)
                    c.strokeEllipse(in: CGRect(x: c0.x - r * unit, y: c0.y - r * unit,
                                               width: r * 2 * unit, height: r * 2 * unit))
                }
            }
        }
    }
}
