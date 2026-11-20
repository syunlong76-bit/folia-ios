import UIKit
import QuartzCore

// classic / partita 照搬对齐的共享逐词引擎（3.7 (26)，M2'）：
// 把 folia-major 网页版 GlowWord 的三态机（waiting → active →
// passed）、确定性伪随机姿态（种子 = 行 startTime）、逐字辉光
// 扫光与正文颜色迁移逐项落到 UIKit。数据源口径与网页一致：
// 协议行带逐字戳（YRC 派生）时用真戳；只有行级 LRC 时按网页
// buildLineGraphemeTimeline 的兜底——整行字素在行时长内均分。
// 时钟纪律不变：渲染方只消费宿主 frameTick 喂入的位置，本文件
// 不建任何时钟源。

/// 渲染方根视图：把 layoutSubviews 转给持有它的渲染方排版。
final class LyricStageRootView: UIView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// 舞台字体：网页主题 serif 栈在 iOS 上的落点即 Songti SC；
/// 逐词字重恒 700（resolveThemeFontWeight(theme, 700)）。
enum StageFonts {
    static func bold(size: CGFloat) -> UIFont {
        UIFont(name: "STSongti-SC-Bold", size: size)
            ?? .systemFont(ofSize: size, weight: .bold)
    }
    static func light(size: CGFloat) -> UIFont {
        UIFont(name: "STSongti-SC-Light", size: size)
            ?? .systemFont(ofSize: size, weight: .light)
    }
}

/// 网页 fract(sin(x) * 10000) 确定性伪随机（classic/partita
/// 布局共用同一公式，保证同行同位姿与网页一致）。
func stageSeededRandom(_ x: Double) -> Double {
    let s = sin(x) * 10000
    return s - floor(s)
}

/// 一个显示单元（词）。逐字戳缺失时的均分兜底见 units(for:)。
struct StageWordUnit {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

enum StageLyricUnits {

    /// 协议行 → 显示单元：有逐字戳用真戳；无戳时按字素切分
    /// （CJK 逐字成单元、拉丁词按空白分词），整行时长按字素
    /// 数均分（与网页无词行时的 even grapheme timing 同口径）。
    static func units(for line: LyricLine) -> [StageWordUnit] {
        if let words = line.words, !words.isEmpty {
            return words.map {
                StageWordUnit(text: $0.text, start: $0.start,
                              end: max($0.end, $0.start + 0.05))
            }
        }
        let tokens = tokenize(line.text)
        guard !tokens.isEmpty else { return [] }
        // 时间份额按整行字素数（含空白）均分，与网页 even
        // grapheme timing 的分母一致。
        let totalGraphemes = max(line.text.count, 1)
        // 演唱跨度压缩（3.7 (43) 路3）：均分跨度乘 r——人声
        // 唱完早于下行 start，行尾气口若摊进每个字，逐字亮
        // 起恒慢（lag 随行内分位线性增长、行尾最重）。压缩
        // 后逐字时刻落在行首起算的演唱窗内，窗尾留白段不再
        // 点亮任何字（扫光停在全亮，正确）。r 由仓库按同曲
        // 有戳行标定、随行下发（line.singingRatio）。
        let ratio = min(max(line.singingRatio, 0.3), 1)
        let span = max((line.end - line.start) * ratio, 0.1)
        return tokens.map { token in
            let start = line.start + span * Double(token.offset) / Double(totalGraphemes)
            let end = line.start + span * Double(token.offset + token.count) / Double(totalGraphemes)
            return StageWordUnit(text: token.text, start: start, end: end)
        }
    }

    /// 切分：CJK/假名/谚文字素逐字成 token；其余连续非空白
    /// 串成 token；空白不产出 token 但推进字素偏移（占份额）。
    private static func tokenize(_ text: String)
        -> [(text: String, offset: Int, count: Int)] {
        var tokens: [(text: String, offset: Int, count: Int)] = []
        var latin = ""
        var latinStart = 0
        var latinCount = 0
        var offset = 0
        func flushLatin() {
            if !latin.isEmpty {
                tokens.append((latin, latinStart, latinCount))
                latin = ""
                latinCount = 0
            }
        }
        for ch in text {
            let s = String(ch)
            if ch == " " || ch == "\t" || ch == "　" {
                flushLatin()
                offset += 1
                continue
            }
            if isCJK(s) {
                flushLatin()
                tokens.append((s, offset, 1))
            } else {
                if latin.isEmpty { latinStart = offset }
                latin += s
                latinCount += 1
            }
            offset += 1
        }
        flushLatin()
        return tokens
    }

    private static func isCJK(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FA5).contains(v) || (0x3040...0x30FF).contains(v)
            || (0xAC00...0xD7AF).contains(v)
    }
}

/// 词姿态（网页 WordLayoutConfig 的几何子集，单位 pt/度）。
struct StageWordPose {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotate: CGFloat = 0        // 度
    var scale: CGFloat = 1
    var passedRotate: CGFloat = 0  // 度
}

/// 行时序模式（网页 renderHints：按行时长分级，真实歌词行
/// 几乎恒为 normal；fast/instant 只在亚 0.18s 行出现）。
struct StageLineProfile {
    var wordLookahead: TimeInterval
    /// 辉光阴影半径（pt）：网页 text-shadow 半径 [内, 外] 按
    /// drop-shadow 拟合系数 0.4 折算后取双层等效单值。
    var glowRadius: CGFloat

    static func profile(for line: LyricLine) -> StageLineProfile {
        let duration = line.end - line.start
        if duration < 0.10 {   // micro → instant，半径 [14, 24]
            return StageLineProfile(wordLookahead: 0.03, glowRadius: 8)
        }
        if duration < 0.18 {   // short → fast，半径 [18, 32]
            return StageLineProfile(wordLookahead: 0.08, glowRadius: 11)
        }
        // normal，半径 [20, 40]
        return StageLineProfile(wordLookahead: 0.15, glowRadius: 12)
    }
}

/// 逐词视图：正文层（颜色/状态）+ 辉光层（逐字素标签，靠
/// CALayer 阴影出光晕，与网页 drop-shadow 拟合口径同向）。
/// 状态迁移只由 update(position:) 驱动；动画参数对网页
/// framer-motion variants：入场弹簧 stiffness 200 / damping
/// 20（ζ≈0.707）、passed 0.5s、正文回色 0.8s、辉光淡出 0.9s。
final class GlowWordView: UIView {

    enum Status { case waiting, active, passed }

    let unit: StageWordUnit
    var pose: StageWordPose
    private(set) var status: Status = .waiting

    private let font: UIFont
    private let baseColor: UIColor
    private let activeColor: UIColor
    private let profile: StageLineProfile
    private let bodyLabel = UILabel()
    private let glowContainer = UIView()
    private var glowLabels: [UILabel] = []
    private var graphemeSpans: [(start: TimeInterval, end: TimeInterval)] = []

    /// active 段终点（normal 模式 = 词 end）。
    private var activeEnd: TimeInterval { unit.end }
    private var displayDuration: TimeInterval {
        max(activeEnd - unit.start, 0.1)
    }

    init(unit: StageWordUnit, pose: StageWordPose, font: UIFont,
         baseColor: UIColor, activeColor: UIColor, profile: StageLineProfile) {
        self.unit = unit
        self.pose = pose
        self.font = font
        self.baseColor = baseColor
        self.activeColor = activeColor
        self.profile = profile
        super.init(frame: .zero)

        bodyLabel.text = unit.text
        bodyLabel.font = font
        bodyLabel.textColor = baseColor
        bodyLabel.textAlignment = .center
        bodyLabel.layer.shadowColor = UIColor.black.cgColor
        bodyLabel.layer.shadowOpacity = 0.45
        bodyLabel.layer.shadowRadius = 3
        bodyLabel.layer.shadowOffset = .zero
        bodyLabel.sizeToFit()

        // 辉光层：逐字素一标签，与正文同字同宽，靠阴影出晕；
        // 字素时刻按词内均分（网页 buildWordGraphemeTimings
        // 无音节数据时的 even 口径）。
        let graphemes = unit.text.map { String($0) }
        let span = max(unit.end - unit.start, 0.05)
        var gx: CGFloat = 0
        for (index, g) in graphemes.enumerated() {
            let label = UILabel()
            label.text = g
            label.font = font
            label.textColor = activeColor
            label.layer.shadowColor = activeColor.cgColor
            label.layer.shadowOpacity = 1
            label.layer.shadowRadius = profile.glowRadius
            label.layer.shadowOffset = .zero
            label.sizeToFit()
            label.frame.origin = CGPoint(x: gx, y: 0)
            gx += label.bounds.width
            glowLabels.append(label)
            glowContainer.addSubview(label)
            let gStart = unit.start + span * Double(index) / Double(max(graphemes.count, 1))
            let gEnd = unit.start + span * Double(index + 1) / Double(max(graphemes.count, 1))
            graphemeSpans.append((gStart, gEnd))
        }
        glowContainer.frame = CGRect(
            x: 0, y: 0, width: gx, height: bodyLabel.bounds.height)
        glowContainer.alpha = 0
        glowContainer.isUserInteractionEnabled = false

        let width = max(bodyLabel.bounds.width, gx)
        let height = bodyLabel.bounds.height
        bodyLabel.frame = CGRect(
            x: (width - bodyLabel.bounds.width) / 2, y: 0,
            width: bodyLabel.bounds.width, height: height)
        glowContainer.frame.origin = CGPoint(x: (width - gx) / 2, y: 0)
        addSubview(glowContainer)
        addSubview(bodyLabel)
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        isUserInteractionEnabled = false
        applyWaitingPose(animated: false)
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 姿态

    private func transform(for status: Status) -> CGAffineTransform {
        switch status {
        case .waiting:
            // 网页 waiting：scale 0.5、rotate +20°、位置带
            // sin/cos 漂移（入参为姿态 x/y 本值，逐字照搬）。
            let driftX = pose.x + CGFloat(sin(Double(pose.y))) * 100
            let driftY = pose.y + CGFloat(cos(Double(pose.x))) * 50
            return CGAffineTransform(translationX: driftX, y: driftY)
                .rotated(by: (pose.rotate + 20) * .pi / 180)
                .scaledBy(x: 0.5, y: 0.5)
        case .active:
            return CGAffineTransform(translationX: pose.x, y: pose.y)
                .rotated(by: pose.rotate * .pi / 180)
                .scaledBy(x: pose.scale * 1.4, y: pose.scale * 1.4)
        case .passed:
            return CGAffineTransform(translationX: pose.x, y: pose.y)
                .rotated(by: (pose.rotate + pose.passedRotate) * .pi / 180)
                .scaledBy(x: pose.scale, y: pose.scale)
        }
    }

    private func applyWaitingPose(animated: Bool) {
        let apply = { self.transform = self.transform(for: .waiting) }
        if animated {
            UIView.animate(withDuration: 0.4, animations: apply)
        } else { apply() }
    }

    // MARK: 状态驱动

    /// 每帧调用：按位置算目标状态，变化时才跑迁移。
    func update(position: TimeInterval) {
        let target: Status
        if position < unit.start - profile.wordLookahead {
            target = .waiting
        } else if position <= activeEnd {
            target = .active
        } else {
            target = .passed
        }
        guard target != status else { return }
        transition(to: target)
    }

    /// 构建后立即按当前位定格（中途进台/seek 落位）：不跑
    /// 入场动画，直接摆到目标姿态；active 的辉光照常起。
    func snap(position: TimeInterval) {
        let target: Status
        if position < unit.start - profile.wordLookahead {
            target = .waiting
        } else if position <= activeEnd {
            target = .active
        } else {
            target = .passed
        }
        status = target
        layer.removeAllAnimations()
        bodyLabel.layer.removeAllAnimations()
        glowContainer.layer.removeAllAnimations()
        transform = transform(for: target)
        switch target {
        case .waiting:
            alpha = 0
            bodyLabel.textColor = baseColor
            glowContainer.alpha = 0
        case .active:
            alpha = 1
            bodyLabel.textColor = activeColor
            startGlow()
        case .passed:
            alpha = 0.82
            bodyLabel.textColor = baseColor
            glowContainer.alpha = 0
        }
    }

    private func transition(to target: Status) {
        status = target
        switch target {
        case .waiting:
            layer.removeAllAnimations()
            glowContainer.layer.removeAllAnimations()
            UIView.animate(withDuration: 0.4) {
                self.transform = self.transform(for: .waiting)
                self.alpha = 0
            }
            bodyLabel.textColor = baseColor
            glowContainer.alpha = 0
        case .active:
            // 入场弹簧（网页 stiffness 200 / damping 20）；
            // 不透明度单独 0.1s（网页 opacity 子过渡）。
            UIView.animate(withDuration: 0.55, delay: 0,
                           usingSpringWithDamping: 0.707,
                           initialSpringVelocity: 0,
                           options: [.beginFromCurrentState]) {
                self.transform = self.transform(for: .active)
            }
            UIView.animate(withDuration: 0.1) { self.alpha = 1 }
            UIView.transition(with: bodyLabel, duration: 0.2,
                              options: .transitionCrossDissolve) {
                self.bodyLabel.textColor = self.activeColor
            }
            startGlow()
        case .passed:
            UIView.animate(withDuration: 0.5, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) {
                self.transform = self.transform(for: .passed)
                self.alpha = 0.82
            }
            UIView.transition(with: bodyLabel, duration: 0.8,
                              options: .transitionCrossDissolve) {
                self.bodyLabel.textColor = self.baseColor
            }
            if graphemeSpans.count <= 1 {
                UIView.animate(withDuration: 0.9) { self.glowContainer.alpha = 0 }
            }
        }
    }

    /// 辉光起动：单字素 = 持续辉（随词时长爬升到峰值，网页
    /// peaks [0,1,1] / times [0,0.9,1]）；多字素 = 逐字扫光
    /// （每字素辉光时长 = 字素时长 ×6、峰值在 30% 处）。
    private func startGlow() {
        glowContainer.layer.removeAllAnimations()
        if graphemeSpans.count <= 1 {
            glowContainer.alpha = 0
            UIView.animate(withDuration: displayDuration * 0.9,
                           delay: 0, options: [.curveEaseInOut]) {
                self.glowContainer.alpha = 1
            }
            return
        }
        glowContainer.alpha = 1
        for (index, label) in glowLabels.enumerated() {
            let span = graphemeSpans[index]
            let charDuration = max(span.end - span.start, 0.001)
            let delay = max(0, span.start - unit.start)
            label.layer.removeAllAnimations()
            label.alpha = 0
            UIView.animateKeyframes(withDuration: charDuration * 6, delay: delay,
                                    options: [.beginFromCurrentState]) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.3) {
                    label.alpha = 1
                }
                UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.7) {
                    label.alpha = 0
                }
            }
        }
    }
}

/// 整行呼吸浮动（网页 lyricContainerFloat，normal 强度档）：
/// y [0, −14, 0, +6.3, 0]、scale [1, 1.01, 1, 0.995, 1]，
/// 7s easeInOut 无限循环。挂在行容器外层，与行进出场动画
/// 分层互不干扰。
enum StageBreathingFloat {
    private static let key = "stage.breathingFloat"

    static func start(on view: UIView) {
        guard view.layer.animation(forKey: key) == nil else { return }
        let duration: CFTimeInterval = 7
        let ys: [CGFloat] = [0, -14, 0, 6.3, 0]
        let scales: [CGFloat] = [1, 1.01, 1, 0.995, 1]
        var transforms: [CATransform3D] = []
        for i in ys.indices {
            var t = CATransform3DMakeTranslation(0, ys[i], 0)
            t = CATransform3DScale(t, scales[i], scales[i], 1)
            transforms.append(t)
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = transforms.map { NSValue(caTransform3D: $0) }
        animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        animation.isRemovedOnCompletion = false
        view.layer.add(animation, forKey: key)
    }

    static func stop(on view: UIView) {
        view.layer.removeAnimation(forKey: key)
    }
}
