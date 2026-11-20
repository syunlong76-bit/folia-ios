import UIKit

// SketchbookHandleSettings.swift
//
// 速记簿把手三项设置的消费端（(55) 工作流 H；设置行本体在工作流
// G 的设置页，这里只读 UserDefaults 键，键名两边定死）：
// - sketchbook.handle.show（Bool，缺省 true）：把手显不显示。
//   藏起来后抽屉本体不受影响——别的入口（宿主编程式 setOpen）
//   照常能开，本文件只管把手三件套的在场与否。
// - sketchbook.handle.position（Double 0–1，缺省 0）：把手在左缘
//   的高度锚点，照网页版 scratchpad.css 的公式在 72pt 与
//   「屏高 − 24 − 热区高」之间挪；缺省 0 = 现行为（top 72），
//   设置没写过时样子一点不变。
// - sketchbook.handle.style（Int，缺省 0）：常驻形态三档——
//   0 线（现米白小条 6×56、顶端 2pt 红、opacity 0.4）、
//   1 点（14×14 圆点、纸上红、骑在左缘上、opacity 0.55）、
//   2 图形（圆/三角/双尖括号三颗小记号竖排、opacity 0.45）。
//   三档几何与透明度照网页版 ScratchpadHandleRest.tsx +
//   scratchpad.css 的 --scratchpad-rest-* 变量；网页版另有独立的
//   「line 细竖线」档，原生三档口径里 0 档即现小条（见 H 报告）。
//
// 变更即时生效：抽屉侧监听 UserDefaults.didChangeNotification，
// 每次布局也现读（见 SketchbookDrawerView.applyHandleSettings）。

enum SketchbookHandleSettings {

    static let showKey = "sketchbook.handle.show"
    static let positionKey = "sketchbook.handle.position"
    static let styleKey = "sketchbook.handle.style"

    enum Style: Int {
        case strip = 0
        case dot = 1
        case shapes = 2
    }

    struct Values: Equatable {
        var show: Bool
        var position: Double
        var style: Style
    }

    static func read(from defaults: UserDefaults = .standard) -> Values {
        let show = defaults.object(forKey: showKey) == nil
            ? true : defaults.bool(forKey: showKey)
        let rawPosition = defaults.object(forKey: positionKey) == nil
            ? 0.0 : defaults.double(forKey: positionKey)
        let position = rawPosition.isFinite
            ? min(1, max(0, rawPosition)) : 0.0
        let style = Style(rawValue: defaults.integer(forKey: styleKey)) ?? .strip
        return Values(show: show, position: position, style: style)
    }

    /// 把手热区顶边（照网页版 css 公式）：
    /// top = 72 + position × (屏高 − 72 − 24 − 热区高)。
    static func edgeTop(
        position: Double, containerHeight: CGFloat, edgeHeight: CGFloat
    ) -> CGFloat {
        let travel = max(0, containerHeight - 72 - 24 - edgeHeight)
        return 72 + CGFloat(position) * travel
    }
}

// MARK: - 图形档的三颗小记号（圆 / 三角 / 双尖括号）

/// 照网页版 ScratchpadShape 的 kind 画法：circle 实心圆、tri
/// 上指三角、chev 是「》」形（两段折线描边）。只画常驻把手的
/// 图形档用，8pt 见方。
final class SketchbookRestShapeView: UIView {

    enum Kind {
        case circle
        case triangle
        case chevron
    }

    var kind: Kind = .circle {
        didSet { setNeedsDisplay() }
    }
    var fillColor: UIColor = .white {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let size = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.minX + (rect.width - size) / 2,
            y: rect.minY + (rect.height - size) / 2)
        switch kind {
        case .circle:
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: CGRect(
                x: origin.x, y: origin.y, width: size, height: size))
        case .triangle:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: origin.x + size / 2, y: origin.y))
            path.addLine(to: CGPoint(
                x: origin.x + size, y: origin.y + size))
            path.addLine(to: CGPoint(x: origin.x, y: origin.y + size))
            path.close()
            fillColor.setFill()
            path.fill()
        case .chevron:
            let path = UIBezierPath()
            let inset = size * 0.18
            path.move(to: CGPoint(
                x: origin.x + inset, y: origin.y + inset))
            path.addLine(to: CGPoint(
                x: origin.x + size - inset, y: origin.y + size / 2))
            path.addLine(to: CGPoint(
                x: origin.x + inset, y: origin.y + size - inset))
            path.lineWidth = max(1.5, size * 0.22)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            fillColor.setStroke()
            path.stroke()
        }
    }
}
