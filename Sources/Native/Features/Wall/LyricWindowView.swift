import AVFoundation
import QuartzCore
import UIKit

/// 歌词时序口径：行判定提前量、扫光补偿与时钟重锚阈值收在
/// 一处，改口径只改这里。
enum LyricTiming {
    /// 行判定提前量（秒），单一可配置常量。3.7 (19) 归零：
    /// +0.15 是 (15) 为补 200ms 台阶缓存锚的滞后中位数加的，
    /// (17) 锚源换成真值直读后滞后已消失、提前量成净误差
    /// （audit-3719 §三实锤：墙链因此比详情页恒早 150ms
    /// 换行）。扫光起点同步吃同一常量，归零后两边自动同口径。
    static let lead = 0.0
    /// 漂移重锚阈值（秒）：锚源改直读真实 playhead 后收紧
    /// （(15) 为 0.3，配台阶缓存时再小会频繁误锚）。
    static let reanchorThreshold = 0.12
}

/// 逐字时间戳（YRC 派生，3.7 (19)）：一行歌词内每个字/词的
/// 起始时刻与时长（秒，绝对时间线）。墙链有 YRC 时扫光按此
/// 推进（替换行级线性插值），与 Web 详情页同源时刻表。
struct LyricWordStamp {
    let start: Double
    let duration: Double
    let text: String
}

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

    /// 按与 mask 相同的字体属性量任意字符串的宽（逐字扫光把
    /// 「已唱前缀宽」换算成进度用，3.7 (19)）。
    func measuredWidth(of text: String) -> CGFloat {
        guard let full = dimLabel.attributedText, full.length > 0, !text.isEmpty else { return 0 }
        let attrs = full.attributes(at: 0, effectiveRange: nil)
        return ceil((text as NSString).size(withAttributes: attrs).width)
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
    /// 当前行逐字戳（YRC 派生，3.7 (19)）：非 nil 时扫光按逐字
    /// 真戳推进；nil = 行级 LRC 路径，维持线性插值。
    private var sweepWords: [LyricWordStamp]?

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
        sweepWords = nil
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
                        lineActive: Bool = true,
                        lineWords: [LyricWordStamp]? = nil) {
        let hasContent = texts.contains { !$0.isEmpty }
        lyricScrimView.isHidden = !hasContent
        lyricClipView.isHidden = !hasContent
        guard hasContent else {
            lyricTexts = []
            sweepWords = nil
            stopSweep()
            return
        }
        sweepWords = lineWords
        let canSlide = slide && lyricTexts.count == 6 && texts.count == 6
            && !lyricTexts[2].isEmpty && lyricTexts[2] == texts[1]
        lyricTexts = texts
        if canSlide {
            // 现渲染的行 1...5 恰好是新窗口的可见行，整列上滑一行。
            UIView.animate(withDuration: 0.18, delay: 0,
                           options: [.curveEaseOut]) {
                self.lyricLinesContainer.transform =
                    CGAffineTransform(translationX: 0, y: -self.lyricLineHeight)
            } completion: { finished in
                // 滑行被 removeAllAnimations 打断时 finished=false：
                // 打断方（非滑行路径）已按新窗口重渲染并重开扫光，
                // 旧回调不得再以旧 lineStart 重写一遍（行窗双写）。
                guard finished else { return }
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
        // 扫光与行判定同口径：行判定带 lead 提前量，扫光起点
        // 同步前移 lead（3.7 (19) 起 lead = 0，两边同为零）。
        // 有逐字戳（sweepWords）时 sweepTick 改走逐字真戳，
        // lineStart/lineDuration 只作行级回落口径。
        sweepLineStart = lineStart - LyricTiming.lead
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
        let now = clock()
        // 逐字扫光（3.7 (19)）：有 YRC 逐字戳时按真戳推进——
        // 已唱完的字计全宽、正在唱的字按其时长比例计宽，合计
        // 占整行文本宽的比例即 mask 进度；人声在一行内的停顿/
        // 抢拍由戳本身承载，不再被行级线性插值抹平。
        if let words = sweepWords, !words.isEmpty {
            lyricSweepView.progress = wordSweepProgress(words: words, now: now)
            if let last = words.last, now >= last.start + last.duration { stopSweep() }
            return
        }
        let p = (now - sweepLineStart) / sweepLineDuration
        lyricSweepView.progress = min(max(p, 0), 1)
        if p >= 1 { stopSweep() }
    }

    /// 逐字进度：已唱前缀按扫光行同一字体属性量宽（前缀整体
    /// 量宽而非逐字累加，避免字距重复计入），当前字按时长
    /// 比例折算；分母为整行文本宽，与 mask 的 span 口径一致。
    private func wordSweepProgress(words: [LyricWordStamp], now: Double) -> Double {
        let fullText = lyricTexts.count > 2 ? lyricTexts[2] : ""
        let total = lyricSweepView.measuredWidth(of: fullText)
        guard total > 0 else { return 0 }
        var sung = ""
        for word in words {
            if now >= word.start + word.duration {
                sung += word.text
            } else if now >= word.start {
                let frac = (now - word.start) / word.duration
                let width = lyricSweepView.measuredWidth(of: sung)
                    + lyricSweepView.measuredWidth(of: word.text) * CGFloat(frac)
                return min(max(Double(width / total), 0), 1)
            } else {
                break
            }
        }
        let width = lyricSweepView.measuredWidth(of: sung)
        return min(max(Double(width / total), 0), 1)
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

/// 歌词逐帧插值时钟（包一 P2；3.7 (17) 换锚源）：仿
/// StageProgressDriver 结构——以引擎时间为锚、按显示刷新逐帧
/// 外推（播放速率恒 1）；外推与真值偏差超过阈值（seek、切歌、
/// 漂移）即重锚。逐帧回调驱动歌词行判定。
///
/// (17) 锚源修正：(15) 时锚取自 PlaybackEngine 的 200ms 周期
/// observer 台阶缓存，采锚瞬间即带 0–200ms 滞后；此后漂移检查
/// 比较的又是同一缓存值，滞后永远够不到 0.3 重锚阈值、被锁死
/// 一整首（逐曲随机、整首恒定）。改直读 activePlayer 真实
/// playhead（rawPlayhead），阈值收紧到 0.12；播放/暂停翻转
/// 即重锚（暂停冻结位置与恢复起跑点都以真值为准）；seek 在途
/// （落点未定）期间暂停漂移重锚，防乐观锚点引发的行判定抖动，
/// seek 完成回调落定后下一帧按真值自动重锚。
///
/// (19) 输出延迟补偿：本 driver 下发的是「呈现 now」——行判定
/// 与扫光共用。听觉时刻 = 媒体时刻 − 输出延迟（声音经输出
/// 通道到达耳朵比 item 时间线晚 AVAudioSession.outputLatency：
/// 外放 ≈0、蓝牙 100–300ms）。补偿只在呈现出口减这一次：
/// 引擎时间线与漂移检查全程用未补偿的媒体时刻，不污染锚源，
/// 也不与 Web 链的 offset 校准钮叠加（那边是另一条呈现链）。
/// 路由变化通知 + 每次重锚时刷新缓存值。
final class LyricClockDriver {
    var onTick: ((Double) -> Void)?

    private var displayLink: CADisplayLink?
    private var anchorTime: Double = 0
    private var anchorWall: CFTimeInterval = 0
    private var anchorTrackId: String?
    /// 采锚时的播放态：外推只在锚为播放态时走单调时钟；与引擎
    /// 当前播放态不一致（暂停/恢复翻转）即重锚，不靠漂移阈值兜底。
    private var anchorWasPlaying = false
    /// 输出延迟缓存（秒）：呈现 now 统一减它；外放时 ≈0 属预期。
    private var outputLatency: Double = AVAudioSession.sharedInstance().outputLatency
    private var routeObserver: NSObjectProtocol?

    func start() {
        guard displayLink == nil else { return }
        refreshOutputLatency()
        if routeObserver == nil {
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main) { [weak self] _ in
                self?.refreshOutputLatency()
            }
        }
        reanchor()
        let link = CADisplayLink(target: LinkProxy(owner: self),
                                 selector: #selector(LinkProxy.step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
    }

    deinit { stop() }

    private func refreshOutputLatency() {
        outputLatency = AVAudioSession.sharedInstance().outputLatency
    }

    private func reanchor() {
        let engine = PlaybackEngine.shared
        refreshOutputLatency()
        anchorTime = engine.rawPlayhead()
        anchorWall = CACurrentMediaTime()
        anchorTrackId = engine.currentTrack?.id
        anchorWasPlaying = engine.isPlaying
    }

    /// 锚的媒体时刻（未补偿）：播放态按单调时钟外推、暂停态
    /// 冻结在锚点；无锚/无当前曲返回真实 playhead。漂移检查与
    /// 呈现出口分工——检查用媒体时刻，出口减输出延迟。
    private func mediaNow() -> Double {
        let engine = PlaybackEngine.shared
        guard anchorTrackId != nil, engine.currentTrack != nil else {
            return engine.rawPlayhead()
        }
        return anchorWasPlaying
            ? anchorTime + (CACurrentMediaTime() - anchorWall)
            : anchorTime
    }

    /// 当前呈现时刻 = 媒体时刻 − 输出延迟（行判定与扫光共用，
    /// 全程只在此处与 stepFrame 出口减一次）。
    func interpolatedNow() -> Double {
        mediaNow() - outputLatency
    }

    fileprivate func stepFrame() {
        let engine = PlaybackEngine.shared
        // 无曲/零时长时也要补发一帧：VC 的 hide 守卫靠 onTick 驱动，
        // 不补发则旧歌词会冻在 overlay 上无法收起。
        guard let track = engine.currentTrack, engine.duration > 0 else {
            onTick?(engine.rawPlayhead() - outputLatency)
            return
        }
        if track.id != anchorTrackId { reanchor() }
        // 播放/暂停翻转：立即以真实 playhead 重锚（暂停冻结在
        // 真位置、恢复从真位置起跑），不留整段暂停时长的外推误差。
        if engine.isPlaying != anchorWasPlaying { reanchor() }
        let predicted = anchorWasPlaying
            ? anchorTime + (CACurrentMediaTime() - anchorWall)
            : anchorTime
        // seek 在途时落点由 seek 完成回调回正，期间不重锚。
        // 漂移检查比的是媒体时刻同口径，不含输出延迟补偿。
        if !engine.isSeekPending,
           abs(engine.rawPlayhead() - predicted) > LyricTiming.reanchorThreshold {
            reanchor()
        }
        let now = anchorWasPlaying
            ? anchorTime + (CACurrentMediaTime() - anchorWall)
            : anchorTime
        onTick?(now - outputLatency)
    }

    /// CADisplayLink 强持有 target：弱代理断环，driver 释放后
    /// 代理收不到回调，link 在 driver deinit 时失效。
    private final class LinkProxy: NSObject {
        weak var owner: LyricClockDriver?
        init(owner: LyricClockDriver) { self.owner = owner }
        @objc func step() { owner?.stepFrame() }
    }
}
