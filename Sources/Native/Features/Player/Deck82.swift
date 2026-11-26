import UIKit

/// (82) 新台字形工厂＋布局常量＋点按见证（单一出处）。
///
/// Miller 19:20 新令：上一曲/下一曲/播放/暂停/播放列表/队列
/// 图标另做 J/K/L/M 四套样板待挑——本工厂即替换位：台面与
/// 控制台的全部字形只经此处取图，布局代码不焊字形；定版后
/// 只改本文件的核心四字形绘制（prev/next/play/pause＋list），
/// 其余调用点零改动。次级字形走 SF Symbols（苹果风、与控
/// 制台极简口径一致）。
/// (88) 图标集定版 M（几何融合）已于 port91 退役：Miller
/// 2026-11-26 23:16 点选 A4 visionOS 悬浮系定版（样板
/// design-samples-91/icons/icon-set-a4.png，字形源
/// /tmp/iconbuild/gen2.py 的 A4 定义＋gen3.py 双音符），全
/// 仓图标统一换 A4 字形语言：细线条描边字形（play 三角描
/// 边、pause 双圆角矩形、prev/next 竖条＋三角描边、设置＝
/// 三横线＋三圆钮 sliders），钮面走 A4Chrome91 玻璃面
/// （160° 高光渐变＋白 .38 边＋字形柔光晕）。只换字形与
/// 钮面绘制，任何按钮位置/尺寸/布局/功能不动（port91 任务 3）。
enum DeckGlyph82 {

    enum Kind {
        case prev, next, play, pause
        case list, console, consoleNotes, modeRepeat, modeRepeatOne, modeSequence, shuffle
        case sparkles, paw, heart, heartFill, pencil, trash, help
        case layers, speaker, star, starFill, command, sliders
        // (87) 四特效钮字形：烟花/孔明灯 SF 无对应符号，手绘
        // 线条（照样片 SVG 路径简化）；雪/风走 SF。
        case fxFirework, fxLantern, fxSnow, fxWind
    }

    static func image(_ kind: Kind, pointSize: CGFloat) -> UIImage? {
        switch kind {
        case .prev, .next, .play, .pause, .list:
            return coreGlyph(kind, pointSize: pointSize)
        case .fxFirework, .fxLantern:
            return fxGlyph(kind, pointSize: pointSize)
        case .console, .sliders:
            // port91：控制台/设置字形换 A4 sliders（三横线＋三圆钮，
            // gen2 A4 settings 定义），SF slider.horizontal.3 退役。
            return slidersGlyph91(pointSize: pointSize)
        case .consoleNotes:
            return notesGlyph91(pointSize: pointSize)
        case .fxSnow:
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            return UIImage(systemName: "snowflake", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        case .fxWind:
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            return UIImage(systemName: "wind", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        default:
            let name: String
            switch kind {
            case .modeRepeat: name = "repeat"
            case .modeRepeatOne: name = "repeat.1"
            case .modeSequence: name = "list.bullet"
            case .shuffle: name = "shuffle"
            case .sparkles: name = "sparkles"
            case .paw: name = "pawprint.fill"
            case .heart: name = "heart"
            case .heartFill: name = "heart.fill"
            case .pencil: name = "pencil"
            case .trash: name = "trash"
            case .help: name = "questionmark.circle"
            case .layers: name = "square.3.layers.3d"
            case .speaker: name = "speaker.wave.2.fill"
            case .star: name = "star"
            case .starFill: name = "star.fill"
            case .command: name = "command"
            default: name = "circle"
            }
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            return UIImage(systemName: name, withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        }
    }

    /// 核心五字形手绘（24×24 画布，模板图、白色由 tint 决定）。
    /// port91 A4 visionOS 定版：几何逐字形照 gen2.py 的 A4
    /// 定义（原 48 画布坐标 ÷2 落 24 画布）：play＝三角描边
    /// （线宽 1.7、round join、无填充）；pause＝双圆角矩形
    /// 填充（x 8.85/12.65、y 7.8、w 2.5、h 8.4、rx 1.25）；
    /// prev＝左竖条圆角矩形（x 6.8、w 2.2）＋尖朝左三角描
    /// 边（线宽 1.4）；next 镜像。list 无 A4 原定义，按同
    /// 语言补：三横细线（线宽 1.4、round cap）＋三实心圆点。
    private static var loggedIconA4 = false

    private static func coreGlyph(_ kind: Kind, pointSize: CGFloat) -> UIImage? {
        if !loggedIconA4 {
            loggedIconA4 = true
            Breadcrumbs.log("p91 icon=A4")
        }
        let canvas: CGFloat = 24
        let scale = pointSize / canvas
        let size = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIColor.white.setStroke()
            func triStroke(_ points: [(CGFloat, CGFloat)], w: CGFloat) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: points[0].0 * scale, y: points[0].1 * scale))
                for p in points.dropFirst() {
                    path.addLine(to: CGPoint(x: p.0 * scale, y: p.1 * scale))
                }
                path.close()
                path.lineWidth = w * scale
                path.lineJoinStyle = .round
                path.stroke()
            }
            func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat) {
                UIBezierPath(roundedRect: CGRect(
                    x: x * scale, y: y * scale, width: w * scale, height: h * scale),
                    cornerRadius: r * scale).fill()
            }
            switch kind {
            case .play:
                // A4 play（gen2 48 画布 M20,16.2 L34.6,24 L20,31.8 ÷2）。
                triStroke([(10, 8.1), (17.3, 12), (10, 15.9)], w: 1.7)
            case .pause:
                // A4 pause：双圆角矩形填充。
                rrect(8.85, 7.8, 2.5, 8.4, r: 1.25)
                rrect(12.65, 7.8, 2.5, 8.4, r: 1.25)
            case .prev:
                // A4 prev：竖条（x13.6 w4.4 @48 ÷2）＋尖朝左三角描边。
                rrect(6.8, 8.2, 2.2, 7.6, r: 1.1)
                triStroke([(16.9, 8.2), (10.6, 12), (16.9, 15.8)], w: 1.4)
            case .next:
                // A4 next：prev 的水平镜像。
                rrect(15, 8.2, 2.2, 7.6, r: 1.1)
                triStroke([(7.1, 8.2), (13.4, 12), (7.1, 15.8)], w: 1.4)
            case .list:
                // A4 语言补形：三横细线＋三圆点（与 sliders 同族）。
                for y in [7.6, 12, 16.4] as [CGFloat] {
                    let line = UIBezierPath()
                    line.move(to: CGPoint(x: 8.6 * scale, y: y * scale))
                    line.addLine(to: CGPoint(x: 18.5 * scale, y: y * scale))
                    line.lineWidth = 1.4 * scale
                    line.lineCapStyle = .round
                    line.stroke()
                    UIBezierPath(ovalIn: CGRect(
                        x: (5.8 - 1.5) * scale, y: (y - 1.5) * scale,
                        width: 3 * scale, height: 3 * scale)).fill()
                }
            default:
                break
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// port91 A4 设置字形（gen2 A4 settings，48 画布 ÷2）：
    /// 三横线（y 8.75/12/15.25、x 7–17、白 .85、线宽 1.4）
    /// ＋三圆钮（r 2、位于 (13.5,8.75)/(10,12)/(13,15.25)、
    /// 填充白 .30＋描边 1.15）。模板图的 alpha 层次在 tint
    /// 渲染下保留（半透部分以 tint 半透出）。
    private static func slidersGlyph91(pointSize: CGFloat) -> UIImage? {
        let scale = pointSize / 24
        let size = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            for (cy, cx) in [(8.75, 13.5), (12, 10), (15.25, 13)] as [(CGFloat, CGFloat)] {
                let line = UIBezierPath()
                line.move(to: CGPoint(x: 7 * scale, y: cy * scale))
                line.addLine(to: CGPoint(x: 17 * scale, y: cy * scale))
                line.lineWidth = 1.4 * scale
                line.lineCapStyle = .round
                UIColor.white.withAlphaComponent(0.85).setStroke()
                line.stroke()
                let knob = UIBezierPath(ovalIn: CGRect(
                    x: (cx - 2) * scale, y: (cy - 2) * scale,
                    width: 4 * scale, height: 4 * scale))
                UIColor.white.withAlphaComponent(0.30).setFill()
                knob.fill()
                UIColor.white.setStroke()
                knob.lineWidth = 1.15 * scale
                knob.stroke()
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// (87) 特效字形手绘（24×24 画布、描边模板图）：烟花＝
    /// 中心点＋8 条放射线＋底座两脚；孔明灯＝灯体轮廓＋顶
    /// 线＋灯口线＋中央小火芯（填充小水滴）。照样片控制台
    /// 四钮 SVG 的几何简化，线宽 1.7/24 比例。
    private static func fxGlyph(_ kind: Kind, pointSize: CGFloat) -> UIImage? {
        let scale = pointSize / 24
        let size = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIColor.white.setStroke()
            UIColor.white.setFill()
            func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, w: CGFloat = 1.4) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x1 * scale, y: y1 * scale))
                path.addLine(to: CGPoint(x: x2 * scale, y: y2 * scale))
                path.lineWidth = w * scale
                path.lineCapStyle = .round
                path.stroke()
            }
            switch kind {
            case .fxFirework:
                // 放射光丝（样片 fwBtn：上/左上/右上/左/右/左下/右下 7 线＋竖线）。
                line(12, 10.2, 12, 3.4)
                line(12, 10.2, 6.6, 5.6)
                line(12, 10.2, 17.4, 5.6)
                line(12, 10.2, 4.9, 9.7)
                line(12, 10.2, 19.1, 9.7)
                line(12, 10.2, 7.7, 14.9)
                line(12, 10.2, 16.3, 14.9)
                UIBezierPath(ovalIn: CGRect(x: 10.9 * scale, y: 9.1 * scale,
                                             width: 2.2 * scale, height: 2.2 * scale)).fill()
                // 底座。
                line(10.9, 20.8, 12, 16.3, w: 1.5)
                line(13.1, 20.8, 12, 16.3, w: 1.5)
            case .fxLantern:
                // 灯体：顶部横线起、两侧弧线收至灯口。
                line(8.4, 3.8, 15.6, 3.8)
                let body = UIBezierPath()
                body.move(to: CGPoint(x: 8.7 * scale, y: 3.8 * scale))
                body.addCurve(to: CGPoint(x: 9.5 * scale, y: 17.1 * scale),
                              controlPoint1: CGPoint(x: 7.2 * scale, y: 6.4 * scale),
                              controlPoint2: CGPoint(x: 6.3 * scale, y: 12.5 * scale))
                body.move(to: CGPoint(x: 15.3 * scale, y: 3.8 * scale))
                body.addCurve(to: CGPoint(x: 14.5 * scale, y: 17.1 * scale),
                              controlPoint1: CGPoint(x: 16.8 * scale, y: 6.4 * scale),
                              controlPoint2: CGPoint(x: 17.7 * scale, y: 12.5 * scale))
                body.lineWidth = 1.4 * scale
                body.lineCapStyle = .round
                body.stroke()
                line(9.5, 17.1, 14.5, 17.1)
                // 火芯：小水滴填充。
                let flame = UIBezierPath()
                flame.move(to: CGPoint(x: 12 * scale, y: 13.6 * scale))
                flame.addCurve(to: CGPoint(x: 12 * scale, y: 16.5 * scale),
                               controlPoint1: CGPoint(x: 13.1 * scale, y: 14.8 * scale),
                               controlPoint2: CGPoint(x: 13.1 * scale, y: 15.6 * scale))
                flame.addCurve(to: CGPoint(x: 12 * scale, y: 16.5 * scale),
                               controlPoint1: CGPoint(x: 10.9 * scale, y: 15.6 * scale),
                               controlPoint2: CGPoint(x: 10.9 * scale, y: 14.8 * scale))
                flame.close()
                flame.fill()
            default:
                break
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// port91 控制台入口字形（Miller 23:11 定版）：双音符
    /// **上下对称**——单个实心八分音符（gen3.py 的 A4
    /// note_solid，48 画布 ÷2 落 24 画布）＋其绕画布中心
    /// (12,12) 旋转 180° 的副本，构成中心对称。单符几何：
    /// 符头椭圆心 (9.1,10.8)、rx 2.45/ry 1.8、倾 −16°；符
    /// 干 x 10.8、y 5.2–11.1、宽 1.25 圆角；符尾贝塞尔旗
    /// 面 M(12.05,5.2) C(14.3,5.9)(15.3,7.6)(15,10)
    /// C(14.5,8.2)(13.6,7.3)(12.05,6.7) Z。
    private static func notesGlyph91(pointSize: CGFloat) -> UIImage? {
        let scale = pointSize / 24
        let size = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            UIColor.white.setFill()
            func note() {
                // 符头：倾斜椭圆。
                cg.saveGState()
                cg.translateBy(x: 9.1 * scale, y: 10.8 * scale)
                cg.rotate(by: -16 * .pi / 180)
                UIBezierPath(ovalIn: CGRect(
                    x: -2.45 * scale, y: -1.8 * scale,
                    width: 4.9 * scale, height: 3.6 * scale)).fill()
                cg.restoreGState()
                // 符干：圆角矩形。
                UIBezierPath(roundedRect: CGRect(
                    x: 10.8 * scale, y: 5.2 * scale,
                    width: 1.25 * scale, height: 5.9 * scale),
                    cornerRadius: 0.55 * scale).fill()
                // 符尾：贝塞尔旗面。
                let tail = UIBezierPath()
                tail.move(to: CGPoint(x: 12.05 * scale, y: 5.2 * scale))
                tail.addCurve(to: CGPoint(x: 15 * scale, y: 10 * scale),
                              controlPoint1: CGPoint(x: 14.3 * scale, y: 5.9 * scale),
                              controlPoint2: CGPoint(x: 15.3 * scale, y: 7.6 * scale))
                tail.addCurve(to: CGPoint(x: 12.05 * scale, y: 6.7 * scale),
                              controlPoint1: CGPoint(x: 14.5 * scale, y: 8.2 * scale),
                              controlPoint2: CGPoint(x: 13.6 * scale, y: 7.3 * scale))
                tail.close()
                tail.fill()
            }
            note()
            // 180° 中心对称副本（绕 (12,12)）。
            cg.saveGState()
            cg.translateBy(x: 12 * scale, y: 12 * scale)
            cg.rotate(by: .pi)
            cg.translateBy(x: -12 * scale, y: -12 * scale)
            note()
            cg.restoreGState()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// 花朵进度把手（E 定版：白花瓣＋琥珀心），非模板图。
    static func flowerImage(size: CGFloat = 22) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cg = context.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)
            // 六瓣白花瓣（椭圆绕中心 60° 一瓣）。
            UIColor.white.setFill()
            for i in 0..<6 {
                cg.saveGState()
                cg.translateBy(x: center.x, y: center.y)
                cg.rotate(by: CGFloat(i) * .pi / 3)
                let petal = UIBezierPath(ovalIn: CGRect(
                    x: -size * 0.115, y: -size * 0.46,
                    width: size * 0.23, height: size * 0.34))
                petal.fill()
                cg.restoreGState()
            }
            // 琥珀花心。
            UIColor(red: 0.96, green: 0.66, blue: 0.10, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(
                x: center.x - size * 0.13, y: center.y - size * 0.13,
                width: size * 0.26, height: size * 0.26)).fill()
        }
    }
}

/// (82) 台面布局常量（单一出处，四页同值）。
enum DeckLayout82 {
    /// 展开高单一出处在 MiniBarQuickRowView.expandedBarHeight
    /// （现值 84，(87) 换代定版）。(89) 清账：本枚举原有
    /// expandedHeight=70 死常数（(84) 复原值、未跟 (87)
    /// 改版、全仓零引用）已删除，防误读。
    static let collapsedHeight: CGFloat = 16
    /// 收起态小白条：(83) 第 5 条图像量测对齐系统 home
    /// indicator（量测账见 delivery-83-report：图三系统条
    /// 420×15px @3x、底边距屏底 24px、圆角约 7.5px）——
    /// 宽 140、高 5、底边距屏底 8、圆角 2.5（全胶囊）。
    /// (82) 的 134 系文档常数、与实测不符，本版盖过。
    /// (84) 第 2 条：尺寸口径不变（与该方向系统小白线一
    /// 致），变的只是纵向位置——见 DeckLayout84（条贴在
    /// 小白线上方、不重合，复原 (80) 锚法）。
    static let collapsedTrackWidth: CGFloat = 140
    static let collapsedTrackHeight: CGFloat = 5
    static let collapsedBottomGap: CGFloat = 8
    static let collapsedCornerRadius: CGFloat = 2.5
    static let deckCornerRadius: CGFloat = 35
}

/// (84) 第 2 条：收起条改回 (80) 形态——我方条贴在系统
/// 小白线**上方**（条底与线顶相接、不重叠），横竖屏下条
/// 尺寸与该方向小白线一致。纵向账（pt，屏底起算）：
/// 系统小白线带 = 底距 gap(8) + 高(5) → 线顶在 13；我方
/// 轨（高 5）在 16pt 容器内底距 5.5（既有装配），故容器
/// 底须落在 13 + join(2) − 5.5 = 9.5。容器底锚相对安全
/// 区底的常量 C 满足 inset − C = 9.5，即 **C = inset −
/// 9.5**：竖屏 inset 34 → C=24.5，与 (80) 的
/// applyMiniBarBottom77 收起常数逐点吻合（(80) 同账：
/// 轨带 15–20、线带 8–13、相接间隙 2）；横屏 inset 21
/// → C=11.5，同式成立（(83) 的 C=inset−2.5 使轨带落回
/// 8–13 与线重合，系 Miller ⑥点名的实根）。
/// 横屏条宽 218：(84) 的 209 系上一代机型惯例值、被
/// Miller (84)⑤ 点名仍小；(85) 审计五以 (84) 真机横屏
/// 图逐像素量测为准——系统线 ≈218pt（高 5.1、底距
/// 7.9），本版改 218（仅此一处常数，高度/底距/竖屏
/// 140/锚位公式全不动）。
enum DeckLayout84 {
    /// 收起轨宽（按朝向）：竖 140（实测）／横 218（(85) 实测量定）。
    static func collapsedTrackWidth(portrait: Bool) -> CGFloat {
        portrait ? 140 : 218
    }
    /// 收起底锚常量（相对安全区底）：C = inset − 9.5。
    static func collapsedBottomConstant(safeAreaBottom inset: CGFloat) -> CGFloat {
        inset > 0 ? inset - 9.5 : -10
    }
}

/// (84) 第 3 条点按见证（DS 定案配套）：台面四钮逐钮
/// touchDown 与 touchUpInside **分离落痕**，每行带该次点
/// 按的 hitTest 链摘要（自命中视图沿 superview 上溯的类
/// 名链，截断 6 层）——下轮判读口径预登记：真机点任一
/// 台面钮，tap84 须出现对应 down/up 两行；down 有 up 无
/// ＝触摸被取消（识别器/覆盖层）；双无＝命中没到按钮
/// （与台身原始触摸 mb.tch78 对位分环）。链摘要在
/// touchDown 时刻以钮中心点对 window 现做 hitTest 取
/// （与真实触摸同点同链）。
enum Tap84 {
    static func log(host: String, btn: String, ev: String, view: UIView) {
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let point = view.convert(center, to: view.window)
        var chain = "?"
        if let window = view.window, let hit = window.hitTest(point, with: nil) {
            var names: [String] = []
            var node: UIView? = hit
            while let current = node, names.count < 6 {
                names.append(String(describing: type(of: current)))
                node = current.superview
            }
            chain = names.joined(separator: "<")
        }
        Breadcrumbs.log("tap84 host=\(host) btn=\(btn) ev=\(ev)"
            + " x=\(Int(point.x)) y=\(Int(point.y)) hit=\(chain)")
    }
}

/// (83) 第 2 条取证：双击播放台全路径同步落盘见证（只取
/// 证、不改双击逻辑）。双击闪退自 (63) 起无日志定案——本
/// 链把「识别器触发→分域判定→分发→present 守卫→present
/// 完成→舞台露面」每步以 logSync 写盘，崩在哪一步，下一
/// 次启动由 AppDelegate 扫上一会话尾巴（folia-prev-tail）
/// 把最后一步以 crash83 行带回新会话日志头。armed 旗由
/// 分发点置位、舞台露面消费，避免普通开台也冒充双击链。
enum DblTap83 {
    private static var armedHost: String?

    static func step(_ host: String, _ step: String) {
        Breadcrumbs.logSync("dbltap83 host=\(host) step=\(step)")
    }

    static func arm(_ host: String) { armedHost = host }

    /// 舞台露面消费点：仅双击链在飞时落 step=appear 并落旗。
    static func consumeAppear() {
        guard let host = armedHost else { return }
        armedHost = nil
        step(host, "appear")
    }
}

/// (87) 播放台换代共享口径（样片定版 2026-11-25 15:07）：
/// 主题四圆点（台面右上）与模式合并钮循环序的单一出处。
enum Deck87 {
    // port90（任务 13）：主题四圆点撤除后 dotThemes/dotColors 零引用，随之删除；
    // 主题切换仍走长按台面循环（MiniPlayerTheme.stored.next）与设置页。

    /// 模式合并钮单击循环序（87 定版）：随机→顺序→循环→单曲→随机。
    static func nextMode(after mode: QueueManager.PlayMode) -> QueueManager.PlayMode {
        switch mode {
        case .shuffle: return .off
        case .off: return .loopAll
        case .loopAll: return .repeatOne
        case .repeatOne: return .shuffle
        }
    }
}

/// port91 A4 钮面（样板 .t-a4 chrome）：160° 线性渐变
/// （白 .15 → 白 .04）＋边框白 .38/1pt＋内高光，渐变层以
/// 约束钉满钮面、圆角随钮；字形柔光晕由 apply 侧给
/// imageView 加白 .30 光晕（radius 6、offset (0,2)）。
/// 渐变层不接手势、恒在字形之下（insert at 0；调用方原有
/// 的 backgroundColor 状态色仍透过半透渐变可见）。
final class A4GradientView91: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = cornerRadius
        clipsToBounds = true
        let grad = layer as! CAGradientLayer
        grad.colors = [
            UIColor.white.withAlphaComponent(0.15).cgColor,
            UIColor.white.withAlphaComponent(0.04).cgColor,
        ]
        // 160°：自左上向右下。
        grad.startPoint = CGPoint(x: 0.15, y: 0)
        grad.endPoint = CGPoint(x: 0.85, y: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}

enum A4Chrome91 {
    /// 给钮套 A4 玻璃面：渐变层＋边框＋字形光晕。重复调用
    /// 幂等（已套过的钮按 tag 标记跳过）。cornerRadius 应
    /// 与钮既有圆角一致（调用方在设好圆角后调用）。
    static func apply(to button: UIButton, cornerRadius: CGFloat) {
        if button.viewWithTag(910_411) != nil { return }
        let grad = A4GradientView91(cornerRadius: cornerRadius)
        grad.tag = 910_411
        grad.translatesAutoresizingMaskIntoConstraints = false
        button.insertSubview(grad, at: 0)
        NSLayoutConstraint.activate([
            grad.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            grad.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            grad.topAnchor.constraint(equalTo: button.topAnchor),
            grad.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.38).cgColor
        if let imageView = button.imageView {
            imageView.layer.shadowColor = UIColor.white.cgColor
            imageView.layer.shadowOpacity = 0.30
            imageView.layer.shadowRadius = 6
            imageView.layer.shadowOffset = CGSize(width: 0, height: 2)
        }
    }
}

/// (82) 第 2 条点按见证：新台/控制台每个按钮动作入口落一
/// 行，含 zone 与落点坐标（按钮中心，台/面板坐标系）——下
/// 一份日志必须能数出每次点按，与 (81)「接线齐全但落痕 0
/// 次」的断点对位。
enum DeckTap82 {
    static func log(host: String, zone: String, point: CGPoint) {
        Breadcrumbs.log("tap82 host=\(host) zone=\(zone)"
            + " x=\(Int(point.x)) y=\(Int(point.y))")
    }

    static func log(host: String, zone: String, view: UIView) {
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let point = view.convert(center, to: view.window)
        log(host: host, zone: zone, point: point)
    }
}
