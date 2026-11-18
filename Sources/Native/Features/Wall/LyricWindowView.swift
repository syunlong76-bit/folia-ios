import QuartzCore
import UIKit

/// 当前行扫光视图（3.7 (12)）：暗字打底 + 亮字被 mask 按进度裁切，
/// 唱到哪亮到哪。mask 按文本实际宽度居中起算（居中文本不能从
/// label 左缘扫起）；进度由 cell 的 CADisplayLink 按引擎时钟推进。
private final class SweepLyricLineView: UIView {
    private let dimLabel = UILabel()
    private let brightLabel = UILabel()
    private let maskLayer = CALayer()
    var progress: Double = 0 {
        didSet { if progress != oldValue { updateMask() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for label in [dimLabel, brightLabel] {
            label.textAlignment = .center
            label.textColor = .white
            addSubview(label)
        }
        dimLabel.alpha = 0.38
        maskLayer.backgroundColor = UIColor.black.cgColor
        brightLabel.layer.mask = maskLayer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setText(_ attributed: NSAttributedString) {
        dimLabel.attributedText = attributed
        brightLabel.attributedText = attributed
        updateMask()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimLabel.frame = bounds
        brightLabel.frame = bounds
        updateMask()
    }

    private func updateMask() {
        guard bounds.width > 0,
              let text = dimLabel.attributedText, text.length > 0 else {
            maskLayer.frame = .zero
            return
        }
        let attrs = text.attributes(at: 0, effectiveRange: nil)
        let textWidth = ceil((text.string as NSString).size(withAttributes: attrs).width)
        let span = min(textWidth, bounds.width)
        let startX = textWidth >= bounds.width ? 0 : (bounds.width - textWidth) / 2
        maskLayer.frame = CGRect(x: startX, y: 0,
                                 width: span * CGFloat(progress),
                                 height: bounds.height)
    }
}

/// CADisplayLink 弱代理：link 强持 target，直连视图会钉住视图无法
/// 释放；代理弱持 LyricWindowView，视图已释放时自停表。逻辑同旧
/// SweepLinkProxy（owner 换为 LyricWindowView）。
private final class LyricSweepLinkProxy: NSObject {
    weak var owner: LyricWindowView?
    weak var link: CADisplayLink?

    @objc func tick() {
        guard let owner else {
            link?.invalidate()
            return
        }
        owner.sweepTick()
    }
}

/// 展开卡滚动歌词窗口（包一 P2/P3：自 WallPosterCell 搬家）：独立
/// overlay 视图，不随 cell 复用生灭；渲染栈与视觉参数（字号公式、
/// 6 行窗、alpha 梯度、扫光、呼吸、时长夹取）与旧 cell 实现逐字
/// 一致，只换宿主与扫光时钟来源（VC 注入的插值时钟）。
final class LyricWindowView: UIView {

    /// 扫光时钟（VC 注入 = 插值时钟）：扫光据此推进，暂停即冻结。
    var clock: (() -> Double)?

    private let lyricScrimView = UIView()
    private let lyricGradient = CAGradientLayer()
    private let lyricClipView = UIView()
    private let lyricLinesContainer = UIView()
    private var lyricPlainLabels: [Int: UILabel] = [:]
    private let lyricSweepView = SweepLyricLineView()
    private var lyricTexts: [String] = []
    private var lyricLineHeight: CGFloat = 27
    private var lyricCurrentFontSize: CGFloat = 16
    private var lyricNeighborFontSize: CGFloat = 13
    private var lastLyricClipWidth: CGFloat = -1
    private var sweepDisplayLink: CADisplayLink?
    private var sweepProxy: LyricSweepLinkProxy?
    private var sweepLineStart: Double = 0
    private var sweepLineDuration: Double = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        // 柔光罩（歌词区可读性垫层）+ 裁剪窗 + 6 行容器（行 2 = 扫光行）。
        lyricScrimView.isHidden = true
        lyricScrimView.layer.cornerRadius = 10
        lyricScrimView.clipsToBounds = true
        lyricGradient.colors = [
            UIColor.black.withAlphaComponent(0.30).cgColor,
            UIColor.black.withAlphaComponent(0.08).cgColor
        ]
        lyricScrimView.layer.addSublayer(lyricGradient)
        addSubview(lyricScrimView)

        lyricClipView.clipsToBounds = true
        lyricClipView.isHidden = true
        addSubview(lyricClipView)
        lyricClipView.addSubview(lyricLinesContainer)
        for row in 0..<6 {
            if row == 2 {
                lyricLinesContainer.addSubview(lyricSweepView)
            } else {
                let label = UILabel()
                label.textAlignment = .center
                label.textColor = .white
                label.layer.shadowColor = UIColor.black.cgColor
                label.layer.shadowOpacity = 0.85
                label.layer.shadowRadius = 2
                label.layer.shadowOffset = .zero
                lyricPlainLabels[row] = label
                lyricLinesContainer.addSubview(label)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        sweepDisplayLink?.invalidate()
    }

    /// 等价旧 cell 的空窗口下发：整组收起并停扫光。
    func clear() {
        setWindow(texts: [], lineStart: 0, lineDuration: 0, slide: false)
        lyricLinesContainer.layer.removeAllAnimations()
        lyricLinesContainer.transform = .identity
        lyricSweepView.layer.removeAllAnimations()
        lyricSweepView.transform = .identity
        lyricSweepView.progress = 0
    }

    /// 滚动歌词窗口（6 行：当前行居行 2、行 5 为滑入预备行）：
    /// slide 为真且 cell 现渲染的中心行与新窗口行 1 对得上时，整列
    /// 上滑一行再落位重渲染；其余情况直接落位。空窗口 = 整组收起。
    func setWindow(texts: [String], lineStart: Double,
                        lineDuration: Double, slide: Bool,
                        lineActive: Bool = true) {
        let hasContent = texts.contains { !$0.isEmpty }
        lyricScrimView.isHidden = !hasContent
        lyricClipView.isHidden = !hasContent
        guard hasContent else {
            lyricTexts = []
            stopSweep()
            return
        }
        let canSlide = slide && lyricTexts.count == 6 && texts.count == 6
            && !lyricTexts[2].isEmpty && lyricTexts[2] == texts[1]
        lyricTexts = texts
        if canSlide {
            // 现渲染的行 1...5 恰好是新窗口的可见行，整列上滑一行。
            UIView.animate(withDuration: 0.18, delay: 0,
                           options: [.curveEaseOut]) {
                self.lyricLinesContainer.transform =
                    CGAffineTransform(translationX: 0, y: -self.lyricLineHeight)
            } completion: { _ in
                self.lyricLinesContainer.transform = .identity
                self.renderLyricWindow()
                if lineActive {
                    self.beginSweep(lineStart: lineStart, lineDuration: lineDuration)
                    self.playLyricBreathing()
                } else {
                    // 前奏预告：扫光停在 0（只剩暗字），不呼吸。
                    self.stopSweep()
                    self.lyricSweepView.progress = 0
                }
            }
        } else {
            lyricLinesContainer.layer.removeAllAnimations()
            lyricLinesContainer.transform = .identity
            renderLyricWindow()
            if lineActive {
                beginSweep(lineStart: lineStart, lineDuration: lineDuration)
                playLyricBreathing()
            } else {
                stopSweep()
                lyricSweepView.progress = 0
            }
        }
        setNeedsLayout()
    }

    private func renderLyricWindow() {
        let alphas: [CGFloat] = [0.28, 0.45, 1, 0.45, 0.28, 0.28]
        for row in 0..<6 {
            let text = row < lyricTexts.count ? lyricTexts[row] : ""
            if row == 2 {
                lyricSweepView.setText(lyricAttributed(text, center: true))
            } else if let label = lyricPlainLabels[row] {
                label.attributedText = lyricAttributed(text, center: false)
                label.alpha = alphas[row]
            }
        }
    }

    /// Songti 排版（唱片内页感）：当前行粗体 + 字距 1.2，邻行细体
    /// + 字距 0.6；字体名取不到时回系统粗/细体（DS27 定版）。
    private func lyricAttributed(_ text: String, center: Bool) -> NSAttributedString {
        let font: UIFont = center
            ? (UIFont(name: "STSongti-SC-Bold", size: lyricCurrentFontSize)
               ?? .systemFont(ofSize: lyricCurrentFontSize, weight: .bold))
            : (UIFont(name: "STSongti-SC-Light", size: lyricNeighborFontSize)
               ?? .systemFont(ofSize: lyricNeighborFontSize, weight: .light))
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: center ? 1.2 : 0.6
        ])
    }

    /// 扫光起跑：CADisplayLink 每帧按引擎时钟算进度（0.3 秒心跳
    /// 只够换行、不够驱动扫光，DS27 定版）。link 经弱代理转发
    /// （3.7 (13) #1）：直连 cell 会被 link 强持无法释放。
    private func beginSweep(lineStart: Double, lineDuration: Double) {
        sweepLineStart = lineStart
        sweepLineDuration = max(lineDuration, 0.1)
        lyricSweepView.progress = 0
        sweepDisplayLink?.invalidate()
        let proxy = LyricSweepLinkProxy()
        proxy.owner = self
        let link = CADisplayLink(target: proxy, selector: #selector(LyricSweepLinkProxy.tick))
        proxy.link = link
        sweepProxy = proxy
        link.add(to: .main, forMode: .common)
        sweepDisplayLink = link
        sweepTick()
    }

    func sweepTick() {
        guard window != nil, let clock = self.clock else { stopSweep(); return }
        let p = (clock() - sweepLineStart) / sweepLineDuration
        lyricSweepView.progress = min(max(p, 0), 1)
        if p >= 1 { stopSweep() }
    }

    private func stopSweep() {
        sweepDisplayLink?.invalidate()
        sweepDisplayLink = nil
        sweepProxy = nil
    }

    /// 呼吸缩放：只作用当前行视图，滑入落位后 1.04 弹簧落回。
    private func playLyricBreathing() {
        lyricSweepView.layer.removeAllAnimations()
        lyricSweepView.transform = .identity
        UIView.animate(withDuration: 0.10, delay: 0, options: [.curveEaseOut]) {
            self.lyricSweepView.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
        } completion: { _ in
            UIView.animate(withDuration: 0.22, delay: 0,
                           usingSpringWithDamping: 0.6, initialSpringVelocity: 0.3,
                           options: []) {
                self.lyricSweepView.transform = .identity
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        // 滚动歌词：字号随歌词区宽度自适应（DS27 公式），宽度变化
        // 超 1pt 才重算并重渲染；窗口居卡片中上部（避开底部控件行）。
        let clipWidth = max(bounds.width - 20, 0)
        if clipWidth > 0, abs(clipWidth - lastLyricClipWidth) > 1 {
            lastLyricClipWidth = clipWidth
            lyricCurrentFontSize = min(max(clipWidth * 0.048, 13), 22)
            lyricNeighborFontSize = max(lyricCurrentFontSize * 0.78, 11)
            lyricLineHeight = (lyricCurrentFontSize * 1.65).rounded()
            if !lyricTexts.isEmpty { renderLyricWindow() }
        }
        let lyricTop = bounds.height * 0.40 - lyricLineHeight * 2.5
        let clipFrame = CGRect(x: 10, y: lyricTop, width: clipWidth,
                               height: lyricLineHeight * 5)
        lyricScrimView.frame = clipFrame
        lyricGradient.frame = lyricScrimView.bounds
        lyricClipView.frame = clipFrame
        lyricLinesContainer.frame = CGRect(x: 0, y: 0, width: clipWidth,
                                           height: lyricLineHeight * 6)
        for row in 0..<6 {
            let frame = CGRect(x: 0, y: CGFloat(row) * lyricLineHeight,
                               width: clipWidth, height: lyricLineHeight)
            if row == 2 { lyricSweepView.frame = frame }
            else { lyricPlainLabels[row]?.frame = frame }
        }
    }

}

/// 歌词逐帧插值时钟（包一 P2）：仿 StageProgressDriver 结构——以
/// 引擎时间为锚、按显示刷新逐帧外推（播放速率恒 1）；引擎时间
/// 与外推偏差超过 0.3 秒（seek、切歌、漂移）即重锚。逐帧回调
/// 驱动歌词行判定，替代旧 0.3s 心跳 + 200ms 步进时钟的量化滞后。
final class LyricClockDriver {
    var onTick: ((Double) -> Void)?

    private var displayLink: CADisplayLink?
    private var anchorTime: Double = 0
    private var anchorWall: CFTimeInterval = 0
    private var anchorTrackId: String?

    func start() {
        guard displayLink == nil else { return }
        reanchor()
        let link = CADisplayLink(target: LinkProxy(owner: self),
                                 selector: #selector(LinkProxy.step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit { stop() }

    private func reanchor() {
        let engine = PlaybackEngine.shared
        anchorTime = engine.currentTime
        anchorWall = CACurrentMediaTime()
        anchorTrackId = engine.currentTrack?.id
    }

    /// 当前锚的插值时刻：暂停取 anchorTime；无锚/无当前曲返回
    /// 引擎 currentTime。
    func interpolatedNow() -> Double {
        let engine = PlaybackEngine.shared
        guard anchorTrackId != nil, engine.currentTrack != nil else {
            return engine.currentTime
        }
        return engine.isPlaying
            ? anchorTime + (CACurrentMediaTime() - anchorWall)
            : anchorTime
    }

    fileprivate func stepFrame() {
        let engine = PlaybackEngine.shared
        // 无曲/零时长时也要补发一帧：VC 的 hide 守卫靠 onTick 驱动，
        // 不补发则旧歌词会冻在 overlay 上无法收起。
        guard let track = engine.currentTrack, engine.duration > 0 else {
            onTick?(engine.currentTime)
            return
        }
        if track.id != anchorTrackId { reanchor() }
        let playing = engine.isPlaying
        let predicted = playing
            ? anchorTime + (CACurrentMediaTime() - anchorWall)
            : anchorTime
        if abs(engine.currentTime - predicted) > 0.3 { reanchor() }
        let now = playing
            ? anchorTime + (CACurrentMediaTime() - anchorWall)
            : anchorTime
        onTick?(now)
    }

    /// CADisplayLink 强持有 target：弱代理断环，driver 释放后
    /// 代理收不到回调，link 在 driver deinit 时失效。
    private final class LinkProxy: NSObject {
        weak var owner: LyricClockDriver?
        init(owner: LyricClockDriver) { self.owner = owner }
        @objc func step() { owner?.stepFrame() }
    }
}
