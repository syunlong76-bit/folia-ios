import UIKit

/// (82) 新台字形工厂＋布局常量＋点按见证（单一出处）。
///
/// Miller 19:20 新令：上一曲/下一曲/播放/暂停/播放列表/队列
/// 图标另做 J/K/L/M 四套样板待挑——本工厂即替换位：台面与
/// 控制台的全部字形只经此处取图，布局代码不焊字形；定版后
/// 只改本文件的核心四字形绘制（prev/next/play/pause＋list），
/// 其余调用点零改动。次级字形走 SF Symbols（苹果风、与控
/// 制台极简口径一致）。
/// (88) 图标集定版 M（几何融合）：Miller 2026-11-25 在页面
/// 工坊亲试定案（port88 icon=M），核心五字形按样板
/// design-samples-82/icons2 的 M 定义（build_icons2.py M()
/// 的 SVG 路径，24×24 画布）逐字形移植：prev/next＝三角与
/// 竖条共边熔成的旗形剪影（prev 尖朝左、next 镜像朝右）、
/// play＝实心圆负空间切三角、pause＝圆角方负空间切双槽、
/// list＝半圆点头＋圆角行块三行。J/K/L 三套就此退役。
enum DeckGlyph82 {

    enum Kind {
        case prev, next, play, pause
        case list, console, modeRepeat, modeRepeatOne, modeSequence, shuffle
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
            case .console: name = "slider.horizontal.3"
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
            case .sliders: name = "slider.horizontal.3"
            default: name = "circle"
            }
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            return UIImage(systemName: name, withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        }
    }

    /// 核心五字形手绘（24×24 画布，模板图、白色由 tint 决定）。
    /// (88) M 几何融合定版：路径逐条照样板 build_icons2.py 的
    /// M() SVG（数值即 24 画布坐标）。prev/next 的 SVG 带
    /// stroke-width 1 同色描边柔边，这里以 1pt 同色描边＋圆
    /// 角接合等价还原；play/pause 的负空间用 evenOdd 填充规
    /// 则切形。朝向：prev 尖朝左、next 尖朝右（逐字形回读
    /// 核对，见 (88) 交付报告）。
    private static var loggedIconM88 = false

    private static func coreGlyph(_ kind: Kind, pointSize: CGFloat) -> UIImage? {
        if !loggedIconM88 {
            loggedIconM88 = true
            Breadcrumbs.log("port88 icon=M")
        }
        let canvas: CGFloat = 24
        let scale = pointSize / canvas
        let size = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIColor.white.setStroke()
            func poly(_ points: [(CGFloat, CGFloat)], softEdge: Bool = false) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: points[0].0 * scale, y: points[0].1 * scale))
                for p in points.dropFirst() {
                    path.addLine(to: CGPoint(x: p.0 * scale, y: p.1 * scale))
                }
                path.close()
                path.fill()
                if softEdge {
                    path.lineWidth = 1 * scale
                    path.lineJoinStyle = .round
                    path.stroke()
                }
            }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 0) {
                let path = UIBezierPath(roundedRect: CGRect(
                    x: x * scale, y: y * scale, width: w * scale, height: h * scale),
                    cornerRadius: r * scale)
                path.fill()
            }
            switch kind {
            case .prev:
                // M prev：M5 5 H8.4 V7 L19 12 L8.4 17 V19 H5Z
                poly([(5, 5), (8.4, 5), (8.4, 7), (19, 12),
                      (8.4, 17), (8.4, 19), (5, 19)], softEdge: true)
            case .next:
                // M next：M19 5 H15.6 V7 L5 12 L15.6 17 V19 H19Z
                poly([(19, 5), (15.6, 5), (15.6, 7), (5, 12),
                      (15.6, 17), (15.6, 19), (19, 19)], softEdge: true)
            case .play:
                // M play：圆 (12,12) r8.6 负空间切三角
                // (10.4,8.8) (15.6,12) (10.4,15.2)。
                let path = UIBezierPath(arcCenter: CGPoint(x: 12 * scale, y: 12 * scale),
                                        radius: 8.6 * scale,
                                        startAngle: 0, endAngle: .pi * 2, clockwise: true)
                let tri = UIBezierPath()
                tri.move(to: CGPoint(x: 10.4 * scale, y: 8.8 * scale))
                tri.addLine(to: CGPoint(x: 15.6 * scale, y: 12 * scale))
                tri.addLine(to: CGPoint(x: 10.4 * scale, y: 15.2 * scale))
                tri.close()
                path.append(tri)
                path.usesEvenOddFillRule = true
                path.fill()
            case .pause:
                // M pause：圆角方 (4.6,4.6,14.8×14.8) r2.5 负空
                // 间切双槽 (9.1,8.6,1.9×6.8) 与 (13,8.6,1.9×6.8)。
                let path = UIBezierPath(roundedRect: CGRect(
                    x: 4.6 * scale, y: 4.6 * scale,
                    width: 14.8 * scale, height: 14.8 * scale),
                    cornerRadius: 2.5 * scale)
                path.append(UIBezierPath(rect: CGRect(
                    x: 9.1 * scale, y: 8.6 * scale, width: 1.9 * scale, height: 6.8 * scale)))
                path.append(UIBezierPath(rect: CGRect(
                    x: 13 * scale, y: 8.6 * scale, width: 1.9 * scale, height: 6.8 * scale)))
                path.usesEvenOddFillRule = true
                path.fill()
            case .list:
                // M list：三行半圆点头（圆心 (7.1, y+1.95)、
                // r1.95 的右半圆）＋圆角行块 rx0.7；行 y＝
                // 5.3/10.05/14.8，第三行行块短（宽 6.8）。
                for (i, row) in [(5.3, 5.5), (10.05, 10.3), (14.8, 15.1)].enumerated() {
                    let head = UIBezierPath(arcCenter: CGPoint(x: 7.1 * scale, y: (row.0 + 1.95) * scale),
                                            radius: 1.95 * scale,
                                            startAngle: -.pi / 2, endAngle: .pi / 2,
                                            clockwise: true)
                    head.close()
                    head.fill()
                    rect(9.8, row.1, i == 2 ? 6.8 : 9.8, 3.4, r: 0.7)
                }
            default:
                break
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
            func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, w: CGFloat = 1.7) {
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
                body.lineWidth = 1.7 * scale
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
    /// 展开高：(82) E 定版三行 132 → (83) 紧凑台 106 →
    /// (84) 第 1 条改回 (80) 版台为底，复原 70（与
    /// MiniBarQuickRowView.expandedBarHeight 同值）。
    static let expandedHeight: CGFloat = 70
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
    /// 四圆点对应的油画主题（与 MiniPlayerTheme 四套画作
    /// 一一对应；.none 仍由长按循环/设置到达，点位只管四
    /// 套画作）。圆点底色取各主题画作的代表色。
    static let dotThemes: [MiniPlayerTheme] = [.meadow, .snow, .star, .ocean]
    static let dotColors: [UIColor] = [
        UIColor(red: 0.48, green: 0.54, blue: 0.29, alpha: 1),  // 花海·绿
        UIColor(red: 0.75, green: 0.85, blue: 0.91, alpha: 1),  // 雪景·雪蓝白
        UIColor(red: 0.17, green: 0.23, blue: 0.45, alpha: 1),  // 星空·深蓝
        UIColor(red: 0.17, green: 0.48, blue: 0.45, alpha: 1),  // 海洋·青
    ]

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
