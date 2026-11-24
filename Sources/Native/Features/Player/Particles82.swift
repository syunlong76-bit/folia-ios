import UIKit

/// (82) 像素粒子特效助手：控制台灯钮切换、爪印类点按反馈等
/// 一发即散的小特效共用。粒子是 2–4pt 的小方块 UIView（像素
/// 风，与 Folia 像素月/日图形同语言），不用圆形粒子图。
///
/// 纪律：全部方法须在主线程调用（内部直接建视图/挂动画）；
/// 粒子一律 isUserInteractionEnabled=false、不挡宿主触摸；
/// 动画只用 .curveEaseOut 自然减速，禁线性匀速；每颗粒子
/// 播完自移除，宿主不需做任何回收。坐标系即 host 自身坐标
/// 系，调用方传的点须已换算到 host 内。
enum Particles82 {

    /// 径向迸发：粒子自 point 向四周散开，初速随机、自然
    /// 减速（.curveEaseOut），同时渐隐，总时长 ≤0.9s。
    static func burst(in host: UIView, at point: CGPoint,
                      colors: [UIColor], count: Int = 24,
                      power: CGFloat = 90) {
        guard !colors.isEmpty, count > 0 else { return }
        for _ in 0..<count {
            let particle = makeParticle(colors: colors)
            particle.center = point
            host.addSubview(particle)
            // 随机方向＋随机射程（0.35–1.15 倍 power，近密远疏）。
            let angle = CGFloat.random(in: 0..<(CGFloat.pi * 2))
            let distance = power * CGFloat.random(in: 0.35...1.15)
            let target = CGPoint(
                x: point.x + cos(angle) * distance,
                y: point.y + sin(angle) * distance
                    + distance * 0.12) // 轻微下坠感，非匀速直线感
            let duration = TimeInterval.random(in: 0.5...0.9)
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.curveEaseOut,
                                     .beginFromCurrentState]) {
                particle.center = target
                particle.alpha = 0
                // 末段轻微缩小，收尾不留硬方块感。
                particle.transform = CGAffineTransform(
                    scaleX: 0.5, y: 0.5)
            } completion: { _ in
                particle.removeFromSuperview()
            }
        }
    }

    /// 扩散光环：一圈 CAShapeLayer 圆环 stroke 自 r=6 扩到
    /// r=46、alpha 1→0（约 0.55s），同时约 14 颗同色粒子沿
    /// 环向外迸出（走 burst 的同款减速/渐隐，射程贴环半径）。
    static func ring(in host: UIView, center: CGPoint,
                     color: UIColor) {
        let ringLayer = CAShapeLayer()
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = color.cgColor
        ringLayer.lineWidth = 2
        ringLayer.path = circlePath(center: center, radius: 6)
        host.layer.addSublayer(ringLayer)

        let expand = CABasicAnimation(keyPath: "path")
        expand.fromValue = circlePath(center: center, radius: 6)
        expand.toValue = circlePath(center: center, radius: 46)
        expand.duration = 0.55
        expand.timingFunction = CAMediaTimingFunction(
            name: .easeOut)
        expand.fillMode = .forwards
        expand.isRemovedOnCompletion = false
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.55
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        ringLayer.add(expand, forKey: "ring.expand82")
        ringLayer.add(fade, forKey: "ring.fade82")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            ringLayer.removeFromSuperlayer()
        }

        // 沿环迸出的粒子：方向按等分角＋小抖动，射程略超环
        // 的终点半径，与光环扩散同拍到达外围。
        for index in 0..<14 {
            let particle = makeParticle(colors: [color])
            particle.center = center
            host.addSubview(particle)
            let angle = CGFloat(index) / 14 * CGFloat.pi * 2
                + CGFloat.random(in: -0.12...0.12)
            let distance = CGFloat.random(in: 44...58)
            let target = CGPoint(
                x: center.x + cos(angle) * distance,
                y: center.y + sin(angle) * distance)
            UIView.animate(withDuration: TimeInterval.random(
                in: 0.45...0.6), delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState]) {
                particle.center = target
                particle.alpha = 0
            } completion: { _ in
                particle.removeFromSuperview()
            }
        }
    }

    /// 弧线拖尾：约 16 颗粒子沿 from→to 的轻弧线依次飞过
    /// 去——后发粒子延迟递增（每颗 +0.028s），各自落点沿弧
    /// 线依次推进，整体呈一道扫过去的拖尾，渐隐自移除。
    /// 弧线弯向由连线方向决定：取中点沿法线偏移连线长
    /// 18% 作二次贝塞尔控制点。
    static func trail(in host: UIView, from: CGPoint, to: CGPoint,
                      color: UIColor) {
        let count = 16
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 1)
        // 法线（连线逆时针 90°）方向的弧顶控制点。
        let control = CGPoint(
            x: (from.x + to.x) / 2 - dy / length * length * 0.18,
            y: (from.y + to.y) / 2 + dx / length * length * 0.18)
        for index in 0..<count {
            let particle = makeParticle(colors: [color])
            particle.center = from
            host.addSubview(particle)
            // 第 index 颗的落点：弧线上 t=(index+1)/count 处。
            let t = CGFloat(index + 1) / CGFloat(count)
            let target = quadBezier(from: from, control: control,
                                    to: to, t: t)
            UIView.animate(withDuration: 0.38,
                           delay: TimeInterval(index) * 0.028,
                           options: [.curveEaseOut,
                                     .beginFromCurrentState]) {
                particle.center = target
                particle.alpha = 0
            } completion: { _ in
                particle.removeFromSuperview()
            }
        }
    }

    // MARK: - 内部

    /// 单颗像素粒子：2–4pt 方块、随机取色、初始不透明。
    private static func makeParticle(colors: [UIColor]) -> UIView {
        let size = CGFloat.random(in: 2...4)
        let particle = UIView(frame: CGRect(
            x: 0, y: 0, width: size, height: size))
        particle.backgroundColor = colors.randomElement()
        particle.isUserInteractionEnabled = false
        return particle
    }

    private static func circlePath(center: CGPoint,
                                   radius: CGFloat) -> CGPath {
        UIBezierPath(arcCenter: center, radius: radius,
                     startAngle: 0, endAngle: CGFloat.pi * 2,
                     clockwise: true).cgPath
    }

    /// 二次贝塞尔取点（trail 弧线落点计算）。
    private static func quadBezier(from: CGPoint, control: CGPoint,
                                   to: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * from.x + 2 * mt * t * control.x
                + t * t * to.x,
            y: mt * mt * from.y + 2 * mt * t * control.y
                + t * t * to.y)
    }
}
