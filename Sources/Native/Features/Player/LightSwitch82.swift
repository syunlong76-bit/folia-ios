import UIKit

/// (82) 控制台灯钮：开灯/关灯图形开关（定版样板
/// design-samples-82/deck2/light-switch.png）。语义——开灯
/// ＝全部海报封面亮起（整墙亮）；关灯＝整墙暗下、只有点击
/// 的那张封面亮起（聚焦单张）。本控件只负责开关本体与切
/// 换动效，墙面灯光由宿主在 onToggle 里接。
///
/// 外观（固有尺寸 200×46、深色固定不随系统深浅色变）：
/// - 轨道：全圆角胶囊、深黑 #0b0b10，内渐变＋内描边造内
///   阴影感（轨道层 clipsToBounds，闪光带亦裁在轨道内）。
/// - 玻璃方钮：36×36、圆角 11，半透明白渐变（上亮下暗）
///   ＋1pt 半透明白描边＋内高光；关灯停左端 x=5、开灯停
///   右端 x=159，纵向居中 y=5。
/// - 光晕：钮后一层 110×60 径向渐变（钮下方偏置），关灯
///   亮蓝白 rgb(168,204,255)、开灯暖金 rgb(255,190,90)；
///   钮自身 shadow 同色。
/// - 像素图：钮中央约 22pt 见方、18×18 像素格逐格填 rect
///   （PixelIconView82 的 draw 实现），关灯白像素弯月＋三
///   颗十字星、开灯奶白圆盘＋金色短光芒，画法见该类注释。
///
/// 切换动画（setOn animated）：钮位移走系统 spring
/// （0.55s、damping 0.72）；月/日两图 crossfade＋缩放微
/// 弹；转化瞬间在钮（目标位）中心放约 30 颗 Particles82
/// 粒子（颜色随目标态）；再加一道斜向白色渐变闪光带自
/// 左扫到右（0.45s、alpha 峰值 0.35）后移除。非 animated
/// 直接落位。点按（.touchUpInside）翻转状态并回调
/// onToggle；程序式 setOn 不回调（与 UISwitch 口径一致，
/// 宿主回设状态时不许反噬触发墙面灯光）。
final class LightSwitch82: UIControl {

    /// 当前状态（false=关灯/月，true=开灯/日）。
    private(set) var isOn = false
    /// 点按切换回调（仅用户点按触发，参数为切换后状态）。
    var onToggle: ((Bool) -> Void)?

    // MARK: 尺寸常量（定版）

    private static let switchSize = CGSize(width: 200, height: 46)
    private static let knobSide: CGFloat = 36
    private static let knobInset: CGFloat = 5

    // MARK: 配色（定版）

    /// 关灯光晕：亮蓝白。
    private static let offGlow = UIColor(
        red: 168 / 255, green: 204 / 255, blue: 255 / 255, alpha: 1)
    /// 开灯光晕：暖金。
    private static let onGlow = UIColor(
        red: 255 / 255, green: 190 / 255, blue: 90 / 255, alpha: 1)
    /// 粒子色池：开灯暖金系 / 关灯蓝白系（转化瞬间按目标态取）。
    private static let onBurstColors: [UIColor] = [
        UIColor(red: 1, green: 190 / 255, blue: 90 / 255, alpha: 1),
        UIColor(red: 1, green: 207 / 255, blue: 94 / 255, alpha: 1),
        UIColor(red: 1, green: 246 / 255, blue: 216 / 255, alpha: 1),
        .white,
    ]
    private static let offBurstColors: [UIColor] = [
        UIColor(red: 168 / 255, green: 204 / 255, blue: 1, alpha: 1),
        UIColor(red: 0.75, green: 0.85, blue: 1, alpha: 1),
        .white,
    ]

    // MARK: 子视图

    /// 轨道本体（胶囊底＋内阴影渐变＋闪光带的裁剪域）。
    private let trackView = UIView()
    private let trackGradient = CAGradientLayer()
    /// 钮后光晕（径向渐变层住在普通视图上，随钮一起位移）。
    private let glowView = UIView()
    private let glowGradient = CAGradientLayer()
    /// 玻璃方钮（外壳持描边＋同色 shadow；内层玻璃裁圆角）。
    private let knobView = UIView()
    private let knobGlass = UIView()
    private let knobGradient = CAGradientLayer()
    private let moonIcon = PixelIconView82(mode: .moon)
    private let sunIcon = PixelIconView82(mode: .sun)

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
        applyState(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { Self.switchSize }

    // MARK: - 装配

    private func build() {
        // 本体不裁剪：光晕（110×60）须溢出轨道上下缘。
        clipsToBounds = false
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .button

        // 轨道：深黑胶囊＋纵向内渐变（上沿略亮、中段沉底、
        // 下沿回一线微光，造内阴影的凹感）＋半透明白内描边。
        trackView.backgroundColor = UIColor(
            red: 11 / 255, green: 11 / 255, blue: 16 / 255, alpha: 1)
        trackView.layer.cornerRadius = Self.switchSize.height / 2
        trackView.layer.borderWidth = 1
        trackView.layer.borderColor =
            UIColor.white.withAlphaComponent(0.07).cgColor
        trackView.clipsToBounds = true
        trackView.isUserInteractionEnabled = false
        trackGradient.colors = [
            UIColor.white.withAlphaComponent(0.10).cgColor,
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.35).cgColor,
            UIColor.white.withAlphaComponent(0.05).cgColor,
        ]
        trackGradient.locations = [0, 0.25, 0.8, 1]
        trackView.layer.addSublayer(trackGradient)
        addSubview(trackView)

        // 光晕：径向渐变自光晕色 55% 透到全透明。
        glowView.isUserInteractionEnabled = false
        glowGradient.type = .radial
        glowGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowGradient.endPoint = CGPoint(x: 1, y: 1)
        glowView.layer.addSublayer(glowGradient)
        addSubview(glowView)

        // 玻璃方钮：半透明白渐变（上亮下暗）＋1pt 半透明白
        // 描边＋顶部内高光（一条 40% 白的细渐变压在钮内上
        // 沿，随钮走，故住钮内的子层）＋同色 shadow（颜色
        // 随状态在 applyState 里换）。
        knobView.layer.cornerRadius = 11
        knobView.layer.borderWidth = 1
        knobView.layer.borderColor =
            UIColor.white.withAlphaComponent(0.45).cgColor
        knobView.layer.shadowOffset = CGSize(width: 0, height: 2)
        knobView.layer.shadowRadius = 12
        knobView.layer.shadowOpacity = 0.9
        knobView.clipsToBounds = false
        knobView.isUserInteractionEnabled = false
        // 玻璃内层：裁圆角装渐变与高光（钮外壳不裁剪、保
        // shadow 完整，故渐变的方角由此层收口）。
        knobGlass.layer.cornerRadius = 11
        knobGlass.clipsToBounds = true
        knobGlass.isUserInteractionEnabled = false
        knobGradient.colors = [
            UIColor.white.withAlphaComponent(0.42).cgColor,
            UIColor.white.withAlphaComponent(0.16).cgColor,
            UIColor.white.withAlphaComponent(0.07).cgColor,
        ]
        knobGradient.locations = [0, 0.55, 1]
        knobGlass.layer.addSublayer(knobGradient)
        let highlight = CAGradientLayer()
        highlight.name = "knobHighlight82"
        highlight.colors = [
            UIColor.white.withAlphaComponent(0.40).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor,
        ]
        knobGlass.layer.addSublayer(highlight)
        knobView.addSubview(knobGlass)
        addSubview(knobView)

        // 两张像素图同位叠放（钮中央 22pt 见方），显隐由
        // applyState 的 alpha 裁决，切换时 crossfade。
        for icon in [moonIcon, sunIcon] {
            icon.backgroundColor = .clear
            icon.isUserInteractionEnabled = false
            knobGlass.addSubview(icon)
        }

        addTarget(self, action: #selector(tapped),
                  for: .touchUpInside)
    }

    // MARK: - 布局

    /// 钮左端位（关灯）/右端位（开灯）的 x。
    private var knobX: CGFloat {
        isOn ? Self.switchSize.width - Self.knobInset - Self.knobSide
             : Self.knobInset
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 轨道恒撑满本体（宿主未给足尺寸时以固有尺寸为准）。
        let trackFrame = CGRect(origin: .zero, size: Self.switchSize)
        trackView.frame = trackFrame
        trackGradient.frame = trackView.bounds
        positionKnobAndGlow()
        // 钮内各层/图标按钮 bounds 落位（位移动画只改钮
        // frame，本节随之跟随，不与动画打架）。
        knobGlass.frame = knobView.bounds
        knobGradient.frame = knobGlass.bounds
        if let highlight = knobGlass.layer.sublayers?.first(
            where: { $0.name == "knobHighlight82" }) {
            highlight.frame = CGRect(
                x: 1, y: 1, width: Self.knobSide - 2,
                height: Self.knobSide * 0.45)
            highlight.cornerRadius = 10
        }
        let iconSide: CGFloat = 22
        let iconFrame = CGRect(
            x: (Self.knobSide - iconSide) / 2,
            y: (Self.knobSide - iconSide) / 2,
            width: iconSide, height: iconSide)
        moonIcon.frame = iconFrame
        sunIcon.frame = iconFrame
    }

    /// 钮与光晕按当前状态落位（无动画版；动画版在 setOn 里
    /// 以 spring 改同一批 frame，落点口径只此一处）。
    private func positionKnobAndGlow() {
        knobView.frame = CGRect(
            x: knobX, y: Self.knobInset,
            width: Self.knobSide, height: Self.knobSide)
        // 光晕 110×60、以钮中心为心再向下偏 6pt（光自钮下
        // 方透出的样板感）。
        glowView.frame = CGRect(
            x: knobView.frame.midX - 55,
            y: knobView.frame.midY - 30 + 6,
            width: 110, height: 60)
        glowGradient.frame = glowView.bounds
    }

    // MARK: - 状态

    /// 程序式设状态（不触发 onToggle）。animated 时走完整
    /// 切换动效（spring 位移＋图标 crossfade＋粒子＋闪光
    /// 带）；同态重复调用只落位、不重播动效。
    func setOn(_ on: Bool, animated: Bool) {
        let changed = on != isOn
        isOn = on
        guard changed else {
            applyState(animated: false)
            return
        }
        applyState(animated: animated)
    }

    @objc private func tapped() {
        setOn(!isOn, animated: true)
        onToggle?(isOn)
        sendActions(for: .valueChanged)
    }

    /// 状态落位总口：钮/光晕位置、光晕与 shadow 颜色、两图
    /// alpha、accessibility 文案。animated 分支在此一并放
    /// 粒子与闪光带（转化瞬间、以目标位钮中心为心）。
    private func applyState(animated: Bool) {
        let glowColor = isOn ? Self.onGlow : Self.offGlow
        glowGradient.colors = [
            glowColor.withAlphaComponent(0.55).cgColor,
            glowColor.withAlphaComponent(0.0).cgColor,
        ]
        knobView.layer.shadowColor = glowColor.cgColor
        accessibilityLabel = isOn ? "开灯" : "关灯"

        let showIcon = isOn ? sunIcon : moonIcon
        let hideIcon = isOn ? moonIcon : sunIcon

        guard animated else {
            positionKnobAndGlow()
            showIcon.alpha = 1
            showIcon.transform = .identity
            hideIcon.alpha = 0
            return
        }

        // 转化瞬间：粒子在目标位钮中心迸发（宿主存在时放
        // 宿主坐标系，避免被轨道裁剪；无宿主退回本视图）。
        let targetCenter = CGPoint(x: knobX + Self.knobSide / 2,
                                   y: Self.switchSize.height / 2)
        if let host = superview {
            Particles82.burst(
                in: host,
                at: convert(targetCenter, to: host),
                colors: isOn ? Self.onBurstColors
                             : Self.offBurstColors,
                count: 30, power: 70)
        } else {
            Particles82.burst(
                in: self, at: targetCenter,
                colors: isOn ? Self.onBurstColors
                             : Self.offBurstColors,
                count: 30, power: 70)
        }
        playFlashBand()

        // 图标 crossfade＋缩放微弹：入场图自 0.6 倍弹回 1、
        // 出场图缩到 0.6 淡出，与钮位移同 spring 节拍。
        showIcon.alpha = 0
        showIcon.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.55, delay: 0,
                       usingSpringWithDamping: 0.72,
                       initialSpringVelocity: 0.6,
                       options: [.beginFromCurrentState,
                                 .allowUserInteraction]) {
            // 钮与光晕 spring 滑到目标位（frame 口径与
            // positionKnobAndGlow 一致，此处内联目标值以
            // 便动画插值；layoutSubviews 不在此期间触发改
            // frame——宿主尺寸不变时不会重排）。
            self.knobView.frame = CGRect(
                x: self.knobX, y: Self.knobInset,
                width: Self.knobSide, height: Self.knobSide)
            self.glowView.frame = CGRect(
                x: self.knobView.frame.midX - 55,
                y: self.knobView.frame.midY - 30 + 6,
                width: 110, height: 60)
            showIcon.alpha = 1
            showIcon.transform = .identity
            hideIcon.alpha = 0
            hideIcon.transform = CGAffineTransform(
                scaleX: 0.6, y: 0.6)
        } completion: { _ in
            hideIcon.transform = .identity
        }
    }

    /// 闪光带：斜向（旋转约 20°）白色渐变薄层（宽约 26pt、
    /// 高超轨道以便斜扫覆盖），自轨道左外扫到右外，0.45s、
    /// alpha 峰值 0.35，扫完自移除。住轨道层内、受轨道胶
    /// 囊裁剪。
    private func playFlashBand() {
        let band = CAGradientLayer()
        band.colors = [
            UIColor.white.withAlphaComponent(0).cgColor,
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ]
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        let bandHeight = Self.switchSize.height * 2
        band.frame = CGRect(x: -40, y: -Self.switchSize.height / 2,
                            width: 26, height: bandHeight)
        band.transform = CATransform3DMakeRotation(
            CGFloat(20) * CGFloat.pi / 180, 0, 0, 1)
        trackView.layer.addSublayer(band)

        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = band.position.x
        sweep.toValue = band.position.x
            + Self.switchSize.width + 80
        sweep.duration = 0.45
        sweep.timingFunction = CAMediaTimingFunction(name: .easeOut)
        sweep.fillMode = .forwards
        sweep.isRemovedOnCompletion = false
        band.add(sweep, forKey: "flashBand82")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            band.removeFromSuperlayer()
        }
    }
}

/// (82) 像素图（18×18 格、逐格填 rect 的 draw 实现）：
/// - 月亮（关灯）：白色实心圆（圆心格 (8,9)、半径 7）减去
///   偏移切割圆（圆心 (11.5,7)、半径 6.2）成弯月——逐格以
///   格心判定 in 实心圆 && !in 切割圆 才填；右上方三颗白
///   色十字星（plus 形：中心＋上下左右各一格、3×3 缺四
///   角），星心格 (15,2)/(16,5)/(13,5)。
/// - 太阳（开灯）：奶白 #fff6d8 实心圆盘（圆心 (9,9)、半
///   径 5.5，逐格以格心判定）＋金色 #ffcf5e 短光芒：8 方
///   向、自距圆心 7 格起长 2 格的像素段（对角方向按
///   (√2/2) 步进取整落格，自然成 1–2 格点）。
/// 格子之间不留缝（填满整格），像素块面感与样板一致。
private final class PixelIconView82: UIView {

    enum Mode { case moon, sun }
    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let grid: CGFloat = 18
        let cell = min(rect.width, rect.height) / grid
        let origin = CGPoint(
            x: rect.minX + (rect.width - cell * grid) / 2,
            y: rect.minY + (rect.height - cell * grid) / 2)
        func fillCell(_ gx: Int, _ gy: Int, _ color: UIColor) {
            guard (0..<18).contains(gx), (0..<18).contains(gy)
            else { return }
            color.setFill()
            UIRectFill(CGRect(
                x: origin.x + CGFloat(gx) * cell,
                y: origin.y + CGFloat(gy) * cell,
                width: cell, height: cell))
        }
        /// 格心（格坐标浮点）是否落在圆内。
        func inside(_ gx: Int, _ gy: Int, center: CGPoint,
                    radius: CGFloat) -> Bool {
            let dx = CGFloat(gx) + 0.5 - center.x
            let dy = CGFloat(gy) + 0.5 - center.y
            return dx * dx + dy * dy <= radius * radius
        }

        switch mode {
        case .moon:
            let white = UIColor.white
            for gy in 0..<18 {
                for gx in 0..<18 {
                    if inside(gx, gy, center: CGPoint(x: 8, y: 9),
                              radius: 7),
                       !inside(gx, gy,
                               center: CGPoint(x: 11.5, y: 7),
                               radius: 6.2) {
                        fillCell(gx, gy, white)
                    }
                }
            }
            // 三颗十字星（plus 形 5 格）。
            for star in [(15, 2), (16, 5), (13, 5)] {
                for (dx, dy) in [(0, 0), (0, -1), (0, 1),
                                 (-1, 0), (1, 0)] {
                    fillCell(star.0 + dx, star.1 + dy, white)
                }
            }
        case .sun:
            let cream = UIColor(
                red: 1, green: 246 / 255, blue: 216 / 255, alpha: 1)
            let gold = UIColor(
                red: 1, green: 207 / 255, blue: 94 / 255, alpha: 1)
            for gy in 0..<18 {
                for gx in 0..<18 {
                    if inside(gx, gy, center: CGPoint(x: 9, y: 9),
                              radius: 5.5) {
                        fillCell(gx, gy, cream)
                    }
                }
            }
            // 8 向短光芒：距圆心 7 格起、长 2 格。
            let directions: [(CGFloat, CGFloat)] = [
                (1, 0), (-1, 0), (0, 1), (0, -1),
                (0.7071, 0.7071), (-0.7071, 0.7071),
                (0.7071, -0.7071), (-0.7071, -0.7071),
            ]
            for (dx, dy) in directions {
                for step in 0..<2 {
                    let distance: CGFloat = 7 + CGFloat(step)
                    let gx = Int((9 + dx * distance - 0.5).rounded())
                    let gy = Int((9 + dy * distance - 0.5).rounded())
                    fillCell(gx, gy, gold)
                }
            }
        }
    }
}
