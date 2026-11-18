import UIKit

/// 当前行扫光视图：暗字打底 + 亮字被遮罩按 progress 揭开。
/// 视觉语言与展开卡 SweepLyricLineView 同源（暗字 alpha 0.38、
/// 按文本实测宽度居中起算），放大到舞台尺寸。
final class SweepStageLineView: UIView {
    private let dimLabel = UILabel()
    private let brightLabel = UILabel()
    private let maskLayer = CALayer()

    var progress: Double = 0 {
        didSet { if progress != oldValue { updateMask() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        dimLabel.textAlignment = .center
        dimLabel.alpha = 0.38
        brightLabel.textAlignment = .center
        maskLayer.backgroundColor = UIColor.black.cgColor
        brightLabel.layer.mask = maskLayer
        addSubview(dimLabel)
        addSubview(brightLabel)
        for label in [dimLabel, brightLabel] {
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.6
            label.layer.shadowRadius = 3
            label.layer.shadowOffset = .zero
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 最近一次 setText 的富文本，测宽以它为准（与展开卡同口径：
    /// 用富文本属性测，含字体与 kern；用 label.font 会测成默认
    /// 系统字宽，扫光永远扫不满整行）。
    private var measureSource: NSAttributedString?

    func setText(_ text: String, font: UIFont, kern: CGFloat, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .kern: kern, .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        dimLabel.attributedText = attributed
        brightLabel.attributedText = attributed
        measureSource = attributed
        updateMask()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimLabel.frame = bounds
        brightLabel.frame = bounds
        updateMask()
    }

    private func updateMask() {
        guard bounds.width > 0, let attributed = measureSource else { return }
        let textWidth = attributed.size().width
        let span = min(textWidth, bounds.width)
        let startX = (bounds.width - span) / 2
        maskLayer.frame = CGRect(
            x: startX, y: 0,
            width: span * CGFloat(min(max(progress, 0), 1)), height: bounds.height)
    }
}

// 滚动同步型样例（partita 原型，自有风格实现）：
// 沿用展开卡已定版的歌词视觉语言并放大到全屏舞台——5 行窗口、
// 当前行居中扫光（唱过的字亮起）、换行时整窗上滑一格 + 当前行
// 呼吸缩放、邻行宋体细体按梯度变暗。同步靠宿主逐帧喂入的锚点
// 位置：暂停即冻结（位置不变），seek 后按新位置重新定行。
final class PartitaStageRenderer: LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    private let clipView = UIView()
    private let container = UIView()
    private var plainLabels: [Int: UILabel] = [:]
    private let sweepView = SweepStageLineView()
    private let emptyLabel = UILabel()

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    private var isActive = false
    /// 当前行下标（nil = 前奏未开始）；displayedAnchor = 窗口行 2
    /// 正在显示的行下标。
    private var currentIndex: Int? = nil
    private var displayedAnchor: Int? = nil
    private var builtTrackId: String? = nil

    private var currentFontSize: CGFloat = 26
    private var neighborFontSize: CGFloat = 20
    private var lineHeight: CGFloat = 43

    init() {
        view = rootView
        rootView.backgroundColor = .clear
        rootView.onLayout = { [weak self] in self?.performLayout() }
        clipView.clipsToBounds = true
        rootView.addSubview(clipView)
        clipView.addSubview(container)
        for row in 0..<6 where row != 2 {
            let label = UILabel()
            label.textAlignment = .center
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.6
            label.layer.shadowRadius = 3
            label.layer.shadowOffset = .zero
            container.addSubview(label)
            plainLabels[row] = label
        }
        container.addSubview(sweepView)
        emptyLabel.text = "暂无歌词"
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        rootView.addSubview(emptyLabel)
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        self.snapshot = snapshot
        if snapshot.track?.id != builtTrackId {
            builtTrackId = snapshot.track?.id
            currentIndex = nil
            displayedAnchor = nil
        }
        let hasLines = !snapshot.lines.isEmpty
        emptyLabel.isHidden = hasLines
        clipView.isHidden = !hasLines
        emptyLabel.font = ClassicStageRenderer.songtiLight(size: 17)
        emptyLabel.textColor = snapshot.palette.text.withAlphaComponent(0.5)
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot, !snapshot.lines.isEmpty else { return }
        let idx = LyricParser.currentIndex(in: snapshot.lines, at: position)
        if idx != currentIndex {
            let previous = currentIndex
            currentIndex = idx
            advanceWindow(to: idx, animated: previous != nil && idx != nil && idx! == previous! + 1)
        }
        // 扫光：当前行内的唱段比例（前奏期为 0）。
        if let idx, snapshot.lines.indices.contains(idx) {
            let line = snapshot.lines[idx]
            let span = max(line.end - line.start, 0.1)
            sweepView.progress = min(max((position - line.start) / span, 0), 1)
        } else {
            sweepView.progress = 0
        }
    }

    func unmount() {
        isActive = false
        context = nil
    }

    // MARK: 窗口推进

    /// 窗口推进代次：滑窗动画的 completion 回写前校验仍是最新
    /// 一次推进，防 seek/快切后旧 completion 把窗口覆盖回旧行。
    private var windowGeneration = 0

    private func advanceWindow(to idx: Int?, animated: Bool) {
        guard snapshot != nil else { return }
        windowGeneration += 1
        let generation = windowGeneration
        let anchor = idx ?? 0   // 前奏期把首行放在行 2 预告
        if animated && displayedAnchor != nil && !container.isHidden {
            UIView.animate(withDuration: 0.18, options: [.curveEaseOut]) {
                self.container.transform = CGAffineTransform(translationX: 0, y: -self.lineHeight)
            } completion: { _ in
                guard generation == self.windowGeneration else { return }
                self.container.transform = .identity
                self.displayedAnchor = anchor
                self.renderWindow()
                self.playBreathing()
            }
        } else {
            container.layer.removeAllAnimations()
            container.transform = .identity
            displayedAnchor = anchor
            renderWindow()
            if idx != nil { playBreathing() }
        }
    }

    private func renderWindow() {
        guard let snapshot, let anchor = displayedAnchor else { return }
        let alphas: [CGFloat] = [0.28, 0.45, 1, 0.45, 0.28, 0.28]
        for row in 0..<6 {
            let lineIndex = anchor + row - 2
            let text = snapshot.lines.indices.contains(lineIndex)
                ? snapshot.lines[lineIndex].text : ""
            if row == 2 {
                sweepView.setText(
                    text,
                    font: ClassicStageRenderer.songtiBold(size: currentFontSize),
                    kern: 1.2, color: snapshot.palette.text)
                sweepView.alpha = alphas[row]
            } else if let label = plainLabels[row] {
                label.attributedText = NSAttributedString(
                    string: text,
                    attributes: [
                        .font: ClassicStageRenderer.songtiLight(size: neighborFontSize),
                        .kern: 0.6, .foregroundColor: snapshot.palette.text
                    ])
                label.alpha = alphas[row]
            }
        }
    }

    private func playBreathing() {
        sweepView.transform = .identity
        UIView.animate(withDuration: 0.10, delay: 0, options: [.curveEaseOut]) {
            self.sweepView.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
        } completion: { _ in
            UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.6,
                           initialSpringVelocity: 0.3, options: []) {
                self.sweepView.transform = .identity
            }
        }
    }

    // MARK: 布局

    private func performLayout() {
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        let newCurrent = min(max(bounds.width * 0.066, 20), 30)
        if abs(newCurrent - currentFontSize) > 0.5 {
            currentFontSize = newCurrent
            neighborFontSize = max(currentFontSize * 0.78, 13)
            lineHeight = (currentFontSize * 1.65).rounded()
        }
        let windowHeight = lineHeight * 5
        let clipY = (bounds.height - windowHeight) / 2
        clipView.frame = CGRect(x: 0, y: clipY, width: bounds.width, height: windowHeight)
        container.frame = CGRect(x: 0, y: 0, width: bounds.width, height: lineHeight * 6)
        for row in 0..<6 {
            let frame = CGRect(
                x: 16, y: CGFloat(row) * lineHeight,
                width: bounds.width - 32, height: lineHeight)
            if row == 2 { sweepView.frame = frame } else { plainLabels[row]?.frame = frame }
        }
        emptyLabel.frame = bounds
        if displayedAnchor != nil { renderWindow() }
    }
}
