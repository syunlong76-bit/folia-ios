import UIKit

/// 迷你播放台主题（3.7 (13.5)，Miller 2026-11-18 定版）。
/// 13.4 的台上方 104pt 主题带形态被否：画与动画全部收进播放台
/// 内部、台体圆角裁切、零溢出、无额外动物，只留点名的进度
/// 动画；进度圆点尽量小且与背景融为一体。长按台身循环切换
/// 无→花海→雪景→星空→海洋→无，UserDefaults 持久化（两台
/// 共用一份），缺省花海。
enum MiniPlayerTheme: Int, CaseIterable {
    case none, meadow, snow, star, ocean

    var next: MiniPlayerTheme {
        MiniPlayerTheme(rawValue: (rawValue + 1) % 5) ?? .none
    }

    static var stored: MiniPlayerTheme {
        get {
            guard UserDefaults.standard.object(forKey: key) != nil else { return .meadow }
            return MiniPlayerTheme(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .meadow
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    private static let key = "folia.miniPlayerTheme"

    /// 特效总开关（13.5，Miller 追加）：设置页可一键全关——
    /// 关掉后两台一律素面、长按切换停用；选中的主题保留，
    /// 重新打开即恢复。缺省开。
    static var effectsEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private static let enabledKey = "folia.miniPlayerThemeEnabled"

    /// 实际生效主题：总开关关 = 无主题。
    static var effective: MiniPlayerTheme {
        effectsEnabled ? stored : .none
    }
}

extension Notification.Name {
    /// 播放台主题或特效总开关变更：设置页开关、长按切换后
    /// 发出，墙面听见即按 effective 重新应用。
    static let foliaMiniPlayerThemeChanged = Notification.Name("foliaMiniPlayerThemeChanged")
}

/// 台内主题层：宿主把本层垫在台体玻璃材质（blur）之上、 rim
/// 高光/文字/按钮之下，全幅约束、圆角 35 与台体一致、
/// clipsToBounds 零溢出；自带与玻璃同款的 1pt 亮边（不透明
/// 画作会盖住 blur 自身的边框，这里补回）。整层
/// isUserInteractionEnabled = false，点按/拖动/长按全部穿透
/// 给台身既有手势分发，本层零拦截。
///
/// 图层自下而上：背景画作（cover 裁切）→ 暗色 scrim（文字
/// 可读性保底，歌名永远压在最上方由宿主层序保证）→ 各主题
/// 专属元素（积雪丘/飘雪 emitter/流星/鲨鳍，分属不同主题、
/// 永不同屏，彼此叠序无视觉影响）。
///
/// 进度 fraction 由宿主从 setMiniProgress 转喂（源头是
/// StageProgressDriver 逐帧插值），本层不新开进度计时源；
/// 内部 CADisplayLink 只跑流星划行与鲨鳍浮动的装饰动画，
/// 宿主不可见（host/bar 任一隐藏）即停，雪景 emitter 同门控。
final class MiniPlayerThemeLayer: UIView {

    private(set) var theme: MiniPlayerTheme = .none
    private var fraction: Double = 0

    private let bgImageView = UIImageView()
    private let scrimView = UIView()
    private var snowBankClip: UIView!
    private var snowBankHeight: NSLayoutConstraint?
    private var snowEmitter: CAEmitterLayer?
    private let meteorGlow = CAShapeLayer()
    private let meteorCore = CAShapeLayer()
    private let finView = UIImageView()

    private var hostVisible = false
    private var barVisible = false
    private var displayLink: CADisplayLink?
    private var animTime: Double = 0
    private var lastLinkTime: CFTimeInterval = 0

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = 35
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.30).cgColor
        clipsToBounds = true

        bgImageView.contentMode = .scaleAspectFill
        bgImageView.clipsToBounds = true
        bgImageView.isUserInteractionEnabled = false
        bgImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bgImageView)

        scrimView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        scrimView.isUserInteractionEnabled = false
        scrimView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrimView)

        // 积雪：外层裁切容器贴底，高度随进度 3→17pt；内层雪丘
        // 固定 17pt 高贴底，露出多少由容器高度决定（雪层只长
        // 不回退的观感靠 fraction 本身单调，seek 回退时变薄是
        // 进度语义的如实反映）。
        let clip = UIView()
        clip.clipsToBounds = true
        clip.isUserInteractionEnabled = false
        clip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clip)
        snowBankClip = clip
        let bank = SnowBankView()
        bank.isUserInteractionEnabled = false
        bank.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(bank)

        finView.image = Self.themeImage(named: "sharkfin", ext: "png")
        finView.contentMode = .scaleAspectFit
        finView.isUserInteractionEnabled = false
        finView.frame = CGRect(x: 0, y: 0, width: 50, height: 31)
        finView.isHidden = true
        addSubview(finView)

        meteorGlow.fillColor = UIColor.clear.cgColor
        meteorGlow.lineCap = .round
        meteorGlow.strokeColor = UIColor(red: 1, green: 0.85, blue: 0.45, alpha: 0.22).cgColor
        meteorGlow.lineWidth = 5
        meteorGlow.opacity = 0
        layer.addSublayer(meteorGlow)
        meteorCore.fillColor = UIColor.clear.cgColor
        meteorCore.lineCap = .round
        meteorCore.strokeColor = UIColor(red: 1, green: 0.96, blue: 0.85, alpha: 0.85).cgColor
        meteorCore.lineWidth = 1.5
        meteorCore.opacity = 0
        layer.addSublayer(meteorCore)

        let emitter = Self.makeSnowEmitter()
        snowEmitter = emitter
        layer.addSublayer(emitter)

        NSLayoutConstraint.activate([
            bgImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bgImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bgImageView.topAnchor.constraint(equalTo: topAnchor),
            bgImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrimView.topAnchor.constraint(equalTo: topAnchor),
            scrimView.bottomAnchor.constraint(equalTo: bottomAnchor),
            clip.leadingAnchor.constraint(equalTo: leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: trailingAnchor),
            clip.bottomAnchor.constraint(equalTo: bottomAnchor),
            bank.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            bank.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            bank.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            bank.heightAnchor.constraint(equalToConstant: 17),
        ])
        snowBankHeight = clip.heightAnchor.constraint(equalToConstant: 3)
        snowBankHeight?.isActive = true

        apply(theme: .none)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { displayLink?.invalidate() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let emitter = snowEmitter {
            emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: -4)
            emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        }
        positionFin()
    }

    // MARK: 宿主接口

    func apply(theme newTheme: MiniPlayerTheme) {
        theme = newTheme
        bgImageView.image = Self.backgroundImage(for: newTheme)
        let hasTheme = newTheme != .none
        bgImageView.isHidden = !hasTheme
        scrimView.isHidden = !hasTheme
        snowBankClip.isHidden = newTheme != .snow
        finView.isHidden = newTheme != .ocean
        if newTheme == .snow {
            snowBankHeight?.constant = 3 + CGFloat(fraction) * 14
        }
        if newTheme != .star {
            meteorGlow.opacity = 0
            meteorCore.opacity = 0
        }
        updateActivity()
        positionFin()
    }

    /// 进度唯一入口（宿主 setMiniProgress 转喂）：驱动积雪
    /// 厚度与鲨鳍/流星的头位，严格跟随既有数据源。
    func setFraction(_ newFraction: Double) {
        fraction = min(max(newFraction, 0), 1)
        if theme == .snow {
            snowBankHeight?.constant = 3 + CGFloat(fraction) * 14
        }
        positionFin()
    }

    func setHostVisible(_ visible: Bool) {
        hostVisible = visible
        updateActivity()
    }

    func setBarVisible(_ visible: Bool) {
        barVisible = visible
        updateActivity()
    }

    // MARK: 装饰动画门控（台不可见即停）

    private var decoratingActive: Bool {
        hostVisible && barVisible && theme != .none
    }

    private func updateActivity() {
        snowEmitter?.birthRate = (decoratingActive && theme == .snow) ? 1 : 0
        let linkNeeded = decoratingActive && (theme == .star || theme == .ocean)
        if linkNeeded, displayLink == nil {
            lastLinkTime = 0
            let link = CADisplayLink(target: LinkProxy(owner: self),
                                     selector: #selector(LinkProxy.step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !linkNeeded, let link = displayLink {
            link.invalidate()
            displayLink = nil
            meteorGlow.opacity = 0
            meteorCore.opacity = 0
        }
    }

    fileprivate func stepFrame() {
        guard let link = displayLink else { return }
        if lastLinkTime == 0 { lastLinkTime = link.timestamp; return }
        let dt = min(link.timestamp - lastLinkTime, 0.05)
        lastLinkTime = link.timestamp
        animTime += dt
        if theme == .ocean { positionFin() }
        if theme == .star { updateMeteor() }
    }

    /// CADisplayLink 强持有 target：弱代理断环（与
    /// StageProgressDriver 同模式）。
    private final class LinkProxy: NSObject {
        weak var owner: MiniPlayerThemeLayer?
        init(owner: MiniPlayerThemeLayer) { self.owner = owner }
        @objc func step() { owner?.stepFrame() }
    }

    // MARK: 海洋鲨鳍

    /// 鳍随进度头滑行：鳍心对齐轨道头位（轨道左右内缩 20），
    /// 鳍身骑在进度线上方，轻微上下浮动由装饰时钟驱动。
    private func positionFin() {
        guard theme == .ocean, bounds.width > 40 else { return }
        let headX = 20 + CGFloat(fraction) * (bounds.width - 40)
        let bob = CGFloat(sin(animTime * 1.7)) * 1.5
        // 轨道中心 = 台高 − 9（底距 7 + 轨道半高 2）：(54) H
        // 台高 70→118 后改按 bounds 推导（旧写死 61 仅合 70 台）；
        // 鳍高 31，鳍心上提让鳍底浪花压住轨道上方一点。
        finView.center = CGPoint(x: headX, y: bounds.height - 9 - 13 + bob)
    }

    // MARK: 星空流星

    /// 流星跟随进度头：周期 3.2s、划行 0.6s，从进度头左上方
    /// 斜划过头顶（柔光两段描边：宽笔低透明光晕 + 细笔芯，
    /// 金白色），透明度正弦包络；静止期整组隐形。
    private func updateMeteor() {
        let cycle = 3.2, flight = 0.6
        let phase = animTime.truncatingRemainder(dividingBy: cycle)
        guard bounds.width > 40, phase < flight else {
            meteorGlow.opacity = 0
            meteorCore.opacity = 0
            return
        }
        let t = phase / flight
        let headX = 20 + CGFloat(fraction) * (bounds.width - 40)
        let cx = headX - 26 + CGFloat(t) * 44
        // 划行带相对轨道定位（(54) H 台高 118 后改推导：旧
        // 24..46 是 70 台的上中段；现按「轨道上方 37→15pt」
        // 同距换算，落点仍在进度头上方、不压上排按键区）。
        let cy = (bounds.height - 46) + CGFloat(t) * 22
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cx - 15, y: cy - 8))
        path.addLine(to: CGPoint(x: cx, y: cy))
        meteorGlow.path = path.cgPath
        meteorCore.path = path.cgPath
        let envelope = Float(sin(t * .pi))
        meteorGlow.opacity = envelope
        meteorCore.opacity = envelope
    }

    // MARK: 素材

    static func themeImage(named name: String, ext: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext,
                                        subdirectory: "ThemeArt") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private static func backgroundImage(for theme: MiniPlayerTheme) -> UIImage? {
        switch theme {
        case .none: return nil
        case .meadow: return themeImage(named: "monet-meadow", ext: "jpg")
        case .snow: return themeImage(named: "monet-snow", ext: "jpg")
        case .star: return themeImage(named: "star-ref", ext: "jpg")
        case .ocean: return themeImage(named: "ukiyo-ocean", ext: "jpg")
        }
    }

    private static func makeSnowEmitter() -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.renderMode = .oldestLast
        emitter.birthRate = 0
        let cell = CAEmitterCell()
        cell.contents = snowDotImage().cgImage
        cell.birthRate = 7
        cell.lifetime = 4.2
        cell.lifetimeRange = 1.2
        cell.velocity = 13
        cell.velocityRange = 6
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = 0.25
        cell.xAcceleration = 2.5
        cell.scale = 0.55
        cell.scaleRange = 0.4
        cell.alphaSpeed = -0.12
        emitter.emitterCells = [cell]
        return emitter
    }

    private static func snowDotImage() -> UIImage {
        drawRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            let colors = [UIColor.white.withAlphaComponent(0.95).cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0.55, 1]) {
                ctx.cgContext.drawRadialGradient(
                    gradient, startCenter: CGPoint(x: 5, y: 5), startRadius: 0,
                    endCenter: CGPoint(x: 5, y: 5), endRadius: 5, options: [])
            } else {
                UIColor.white.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 1.5, y: 1.5, width: 7, height: 7))
            }
        }
    }

    // MARK: 圆点皮肤（宿主 knob 复用，程序绘制）

    /// 圆点皮肤视图（13pt）：宿主把它居中压在既有 9pt knob
    /// 框上——knob 不裁剪，贴图溢出显示，中心与轨道头位仍
    /// 对齐，原 leading 公式不变。无主题返回 nil（宿主恢复
    /// 默认白色发光圆点）。
    static func knobSkinView(for theme: MiniPlayerTheme) -> UIView? {
        let image: UIImage?
        switch theme {
        case .none: return nil
        case .meadow: image = daisyImage()
        case .snow: image = snowflakeImage()
        case .star: image = orbImage()
        case .ocean: image = themeImage(named: "wavechip2", ext: "png")
        }
        guard let image else { return nil }
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        return view
    }

    private static func drawRenderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        // 按屏幕 scale 渲染（3.7 (23)）：此前写死 3，非 3x 屏
        // 上皮肤图会发虚；跟随设备 scale 与系统贴图口径一致。
        format.scale = UIScreen.main.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// 小雏菊：六片白瓣 + 黄心。
    private static func daisyImage() -> UIImage {
        drawRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            let c = ctx.cgContext
            UIColor.white.setFill()
            for i in 0..<6 {
                let a = Double(i) * .pi / 3
                let cx = 8 + CGFloat(cos(a)) * 3.6
                let cy = 8 + CGFloat(sin(a)) * 3.6
                c.fillEllipse(in: CGRect(x: cx - 2.7, y: cy - 2.7, width: 5.4, height: 5.4))
            }
            UIColor(red: 1, green: 0.78, blue: 0.20, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 8 - 2.6, y: 8 - 2.6, width: 5.2, height: 5.2))
        }
    }

    /// 雪花：六臂线条 + 臂中段分叉（路径绘制，非 emoji 文本）。
    private static func snowflakeImage() -> UIImage {
        drawRenderer(size: CGSize(width: 16, height: 16)).image { _ in
            let center = CGPoint(x: 8, y: 8)
            let path = UIBezierPath()
            for i in 0..<6 {
                let a = Double(i) * .pi / 3
                let dir = CGPoint(x: CGFloat(cos(a)), y: CGFloat(sin(a)))
                path.move(to: center)
                path.addLine(to: CGPoint(x: center.x + dir.x * 6.4,
                                         y: center.y + dir.y * 6.4))
                let mid = CGPoint(x: center.x + dir.x * 3.6,
                                  y: center.y + dir.y * 3.6)
                for s in [-1.0, 1.0] {
                    let fa = a + s * 0.7
                    let fdir = CGPoint(x: CGFloat(cos(fa)), y: CGFloat(sin(fa)))
                    path.move(to: mid)
                    path.addLine(to: CGPoint(x: mid.x + fdir.x * 2.4,
                                             y: mid.y + fdir.y * 2.4))
                }
            }
            path.lineWidth = 1.1
            path.lineCapStyle = .round
            UIColor.white.setStroke()
            path.stroke()
        }
    }

    /// 发光金星点：径向渐变（亮芯→金晕→透明），与星空背景
    /// 的星点同款。
    private static func orbImage() -> UIImage {
        drawRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            let colors = [UIColor(red: 1, green: 0.98, blue: 0.88, alpha: 1).cgColor,
                          UIColor(red: 1, green: 0.83, blue: 0.38, alpha: 0.55).cgColor,
                          UIColor(red: 1, green: 0.72, blue: 0.25, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 0.35, 1]) {
                ctx.cgContext.drawRadialGradient(
                    gradient, startCenter: CGPoint(x: 8, y: 8), startRadius: 0,
                    endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
            }
        }
    }
}

/// 积雪丘：白→淡蓝竖直渐变 + 顶部波浪丘形 mask；丘形按当前
/// 宽度在 layout 时重算（峰位相对宽度排布，换机型不走形）。
private final class SnowBankView: UIView {
    private let gradient = CAGradientLayer()
    private let maskLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        gradient.colors = [UIColor.white.cgColor,
                           UIColor(red: 0.84, green: 0.90, blue: 0.99, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)
        layer.mask = maskLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: h - 6))
        path.addQuadCurve(to: CGPoint(x: w * 0.30, y: h - 7),
                          controlPoint: CGPoint(x: w * 0.15, y: h - 11))
        path.addQuadCurve(to: CGPoint(x: w * 0.58, y: h - 5),
                          controlPoint: CGPoint(x: w * 0.44, y: h - 3))
        path.addQuadCurve(to: CGPoint(x: w * 0.84, y: h - 8),
                          controlPoint: CGPoint(x: w * 0.71, y: h - 12))
        path.addQuadCurve(to: CGPoint(x: w, y: h - 6),
                          controlPoint: CGPoint(x: w * 0.93, y: h - 4))
        path.addLine(to: CGPoint(x: w, y: h))
        path.close()
        maskLayer.path = path.cgPath
    }
}
