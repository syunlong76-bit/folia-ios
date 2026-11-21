import UIKit

/// (62) WB §4.4：播放页触摸光效。舞台触摸点泛光层——径向
/// 渐变光晕 + 少量粒子，系统弹簧式消散（UIView spring 驱动
/// alpha/scale，禁线性匀速）。密度键（touchGlowDensity）控
/// 制并发光晕上限与每晕粒子数，守内存硬线（光晕为短命图层，
/// 消散即摘）。
///
/// 挂载符号（WA 接线）：StageVC 在舞台根视图装配后调
/// `TouchGlow62.attach(to: stageRootView)` 一行即可；未启用
/// （touchGlowEnabled=false）时 attach 只装手势、不出光。
enum TouchGlow62 {

    /// 挂载到宿主视图：装一层穿透 overlay + 一个不取消触摸
    /// 的点按手势（cancelsTouchesInView=false，舞台原有手势
    /// 与点按语义不受影响）。重复 attach 幂等。
    static func attach(to hostView: UIView) {
        if hostView.subviews.contains(where: { $0 is TouchGlowOverlayView }) { return }
        let overlay = TouchGlowOverlayView()
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        overlay.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: hostView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: hostView.trailingAnchor)
        ])
        let tap = UITapGestureRecognizer(target: overlay,
                                         action: #selector(TouchGlowOverlayView.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        hostView.addGestureRecognizer(tap)
        Breadcrumbs.log("touchGlow62.attach host=\(type(of: hostView)) enabled=\(SettingsStore.touchGlowEnabled)")
    }
}

final class TouchGlowOverlayView: UIView {

    private var liveGlows = 0

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard SettingsStore.touchGlowEnabled,
              !FoliaMotion62.reduced(.microEffects),
              !SettingsStore.staticModeEnabled else { return }
        let density = SettingsStore.touchGlowDensity
        let maxConcurrent = 3 + Int(density * 9)          // 3...12
        guard liveGlows < maxConcurrent else { return }
        let point = recognizer.location(in: self)
        spawnGlow(at: point, density: density)
    }

    private func spawnGlow(at point: CGPoint, density: Double) {
        liveGlows += 1
        let radius: CGFloat = 44 + CGFloat(density) * 40
        let glow = UIView(frame: CGRect(x: point.x - radius, y: point.y - radius,
                                        width: radius * 2, height: radius * 2))
        glow.isUserInteractionEnabled = false
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.frame = glow.bounds
        gradient.colors = [
            UIColor(red: 0.62, green: 0.55, blue: 1.0, alpha: 0.55).cgColor,
            UIColor(red: 0.62, green: 0.55, blue: 1.0, alpha: 0.18).cgColor,
            UIColor(red: 0.62, green: 0.55, blue: 1.0, alpha: 0).cgColor
        ]
        gradient.locations = [0, 0.45, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        glow.layer.addSublayer(gradient)
        // 粒子：密度决定数量（2...8），小圆点沿随机方向弹簧飘散。
        let particleCount = 2 + Int(density * 6)
        for index in 0..<particleCount {
            let size: CGFloat = 3 + CGFloat(index % 3)
            let dot = UIView(frame: CGRect(x: radius - size / 2, y: radius - size / 2,
                                           width: size, height: size))
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.75)
            dot.layer.cornerRadius = size / 2
            dot.isUserInteractionEnabled = false
            glow.addSubview(dot)
            let angle = CGFloat(index) / CGFloat(max(particleCount, 1)) * .pi * 2
            let distance = radius * (0.35 + 0.1 * CGFloat(index % 4))
            UIView.animate(withDuration: 0.7, delay: 0,
                           usingSpringWithDamping: 0.72, initialSpringVelocity: 0.3,
                           options: [.curveEaseOut]) {
                dot.center = CGPoint(x: radius + cos(angle) * distance,
                                     y: radius + sin(angle) * distance)
                dot.alpha = 0
            }
        }
        glow.alpha = 0
        glow.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
        addSubview(glow)
        UIView.animate(withDuration: 0.65, delay: 0,
                       usingSpringWithDamping: 0.68, initialSpringVelocity: 0.25,
                       options: [.curveEaseOut]) {
            glow.alpha = 1
            glow.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
        } completion: { [weak self, weak glow] _ in
            UIView.animate(withDuration: 0.35, animations: { glow?.alpha = 0 }) { _ in
                glow?.removeFromSuperview()
                self?.liveGlows = max((self?.liveGlows ?? 1) - 1, 0)
            }
        }
    }
}

/// (62) WB §4.5：过渡动画层（智能过渡的视觉分量）。挂舞台
/// 顶层呈现：ring = CAShapeLayer 扩散圆环；cardStroke = 卡
/// 片轮廓描边。由 PlaybackEngine 在 crossfade 开始时调
/// `TransitionAnim62.play(in:)`——舞台根视图经
/// `TransitionAnim62.hostViewProvider` 注入（WA 在 StageVC
/// 装配时赋值一次）；未注入时静默跳过（音频过渡不受影响）。
enum TransitionAnim62 {

    /// WA 接线点：StageVC 把舞台根视图给本 provider。
    static var hostViewProvider: (() -> UIView?)?

    static func playCurrent() {
        // (66) 双开关口径：容器动画（圆环）与卡片描边各读
        // 一键、可同时触发（网页为两个独立 bool）；旧三值键
        // 只作导出镜像，不再是读取面。
        let ring = SettingsStore.transitionAnimRing62
        let card = SettingsStore.transitionAnimCard62
        guard ring || card, let host = hostViewProvider?() else { return }
        if ring { play(kind: "ring", in: host) }
        if card { play(kind: "cardStroke", in: host) }
    }

    static func play(kind: String, in host: UIView) {
        switch kind {
        case "ring": playRing(in: host)
        case "cardStroke": playCardStroke(in: host)
        default: break
        }
    }

    private static func playRing(in host: UIView) {
        let center = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
        let startRadius: CGFloat = 24
        let endRadius = max(host.bounds.width, host.bounds.height) * 0.75
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor(red: 0.545, green: 0.486, blue: 0.941, alpha: 0.9).cgColor
        layer.lineWidth = 2.5
        layer.path = UIBezierPath(arcCenter: center, radius: startRadius,
                                  startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        host.layer.addSublayer(layer)
        let expand = CABasicAnimation(keyPath: "path")
        expand.toValue = UIBezierPath(arcCenter: center, radius: endRadius,
                                      startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        expand.duration = 0.9
        expand.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.25, 1)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.9
        layer.add(expand, forKey: "expand62")
        layer.add(fade, forKey: "fade62")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { layer.removeFromSuperlayer() }
        Breadcrumbs.log("transition62.anim kind=ring")
    }

    private static func playCardStroke(in host: UIView) {
        // 卡片轮廓 = 宿主中央 68% 宽高的圆角矩形（封面卡近似
        // 轮廓），描边自 0 扫到全周后淡出。
        let rect = host.bounds.insetBy(dx: host.bounds.width * 0.16,
                                       dy: host.bounds.height * 0.16)
        let layer = CAShapeLayer()
        layer.path = UIBezierPath(roundedRect: rect, cornerRadius: 18).cgPath
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor(red: 0.545, green: 0.486, blue: 0.941, alpha: 0.95).cgColor
        layer.lineWidth = 2
        layer.strokeStart = 0
        layer.strokeEnd = 0
        host.layer.addSublayer(layer)
        let sweep = CABasicAnimation(keyPath: "strokeEnd")
        sweep.fromValue = 0
        sweep.toValue = 1
        sweep.duration = 0.8
        sweep.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.25, 1)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + 0.75
        fade.duration = 0.35
        fade.fillMode = .forwards
        layer.add(sweep, forKey: "sweep62")
        layer.add(fade, forKey: "fade62")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { layer.removeFromSuperlayer() }
        Breadcrumbs.log("transition62.anim kind=cardStroke")
    }
}
