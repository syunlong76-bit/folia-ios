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
    /// 翻行时刻源开关（3.7 (20)，DS R45 对账 + onset 实测拍板）：
    /// 默认 LRC——问题歌 529319768 全曲起音实测 onset−LRC 中位
    /// +2ms（无系统偏差），YRC 系统性偏晚约 90ms 且逐行散布
    /// 更大（绝对偏差中位 152 vs 97ms）；YRC 逐字戳只做行内
    /// 扫光（按 LRC 行窗重标定，见 WallPrototype 的双表合并）。
    /// 改回 .yrc 即恢复 (19) 口径（YRC 翻行 + 原戳扫光）。
    /// 3.7 (21) 起本开关只决定「注册哪套行界给 boundary 锚定」
    /// （及降级时钟比对的表），翻行触发本身改由事件驱动
    /// （LyricBoundaryFlipDriver）。3.7 (23) 起翻行改由呈现钟
    /// judge 直驱（与扫光同钟逐帧判行），本开关决定 judge 与
    /// boundary 校准源共同使用的合并行表来源，语义不变。
    enum FlipSource { case lrc, yrc }
    static let flipSource: FlipSource = .lrc
    /// settle 稳态重锚开关（3.7 (21)，DS R46 对账）：保留但严格
    /// 隔离为只作用扫光呈现时钟（LyricClockDriver），翻行路径
    /// （boundary 事件 + 媒体时钟兜底）完全不读。真机实测
    /// drift=-0.097 与 (20) 定案吻合、纠正后二次读数 -0.003 不
    /// 复发；去留待三基准埋点（settle 面包屑同记 engine
    /// currentTime / rawPlayhead / 外推 now）攒够数据后再定，
    /// 关此开关即 A/B 对照。
    static let settleReanchorEnabled = true
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
        for row in 0..<6 where row != 2 {
            lyricPlainLabels[row]?.layer.removeAllAnimations()
            lyricPlainLabels[row]?.transform = .identity
        }
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
            // 同帧渲染（3.7 (20)，audit-3720 选项 C）：新行 render
            // + 扫光与滑行同帧启动，不再等 0.18s 滑行 completion
            // ——旧实现把点亮/扫光推迟整段滑行时长，(17) 时被
            // +150ms lead 抵掉大半、(19) 摘 lead 后全额裸露。
            // 做法：先渲染新窗并起扫光，邻行预置 +1 行偏移（新
            // 行 1 恰落在旧行 2 的视觉位、与旧路径轨迹一致），
            // 再动画收回 identity——动画只动 transform。唯一与
            // 旧轨迹的差别：滑行期间最上一行（alpha 0.28 的最远
            // 邻行）暂缺，到位时随新窗行 0 一并落定。（3.7 (41)
            // 组3 起偏移与动画改由邻行标签各自承担、扫光行不
            // 再参与，见下方解耦注。）
            renderLyricWindow()
            if lineActive {
                beginSweep(lineStart: lineStart, lineDuration: lineDuration)
                playLyricBreathing()
            } else {
                // 前奏预告：扫光停在 0（只剩暗字），不呼吸。
                stopSweep()
                lyricSweepView.progress = 0
            }
            // 滑行与高亮解耦（3.7 (41) 组3，审计 lyric-sync
            // 候选 2）：扫光行（行 2）不再随容器滑行——翻行
            // 同帧新行已在行 2 定格位置点亮扫光（上文同帧渲
            // 染+起扫光不变）；仅邻行标签各自预置 +1 行偏移、
            // 0.18s 滑回落位，逐行轨迹与旧容器滑行一致。旧
            // 容器滑行里扫光行要等 0.18s 走完才停稳在行 2，
            // 人眼判「换行完成」恒晚约 0.1s 级，与翻行面包
            // 屑的准点并存——本版把这段拖尾从当前行身上摘掉。
            for row in 0..<6 where row != 2 {
                lyricPlainLabels[row]?.transform =
                    CGAffineTransform(translationX: 0, y: lyricLineHeight)
            }
            UIView.animate(withDuration: 0.18, delay: 0,
                           options: [.curveEaseOut]) {
                for row in 0..<6 where row != 2 {
                    self.lyricPlainLabels[row]?.transform = .identity
                }
            } completion: { finished in
                // 被打断（finished=false）时打断方已接管 transform
                // 与内容（非滑行路径/removeAllAnimations），此处
                // 不再触碰任何状态——保留防行窗双写的守卫语义。
                guard finished else { return }
                for row in 0..<6 where row != 2 {
                    self.lyricPlainLabels[row]?.transform = .identity
                }
            }
        } else {
            lyricLinesContainer.layer.removeAllAnimations()
            lyricLinesContainer.transform = .identity
            for row in 0..<6 where row != 2 {
                lyricPlainLabels[row]?.layer.removeAllAnimations()
                lyricPlainLabels[row]?.transform = .identity
            }
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
/// (19) 输出延迟补偿（已撤销）：曾在呈现出口减
/// AVAudioSession.outputLatency。(22) 定案撤销（audit-3722 +
/// DS R48 首选 A）：真机实测该扣减本会话 ≈0.149（(19)/(20)
/// 会话仅 ≈0.008–0.010），使扫光恒慢 149ms；且扣减位于漂移
/// 检查/settle 的下游，任何在位机制看不见、纠不了。Web cue
/// 链从不做此扣减而被确认对得上——呈现钟改与媒体时刻同尺，
/// outputLatency 只保留读数埋点（outLat=/route= 与 refresh
/// 面包屑），续查 0.149 的锁存来源，不再影响时钟。
///
/// (21) 职责收窄：翻行改由 LyricBoundaryFlipDriver 的 boundary
/// 事件驱动，本 driver 只驱动扫光/进度呈现；settle 重锚严格
/// 隔离在本时钟内（LyricTiming.settleReanchorEnabled 开关），
/// 翻行路径不读本时钟。
///
/// (23) 翻行回归本时钟（DS R49 改主推荐）：audit-3723 实测
/// boundary 翻行落到屏幕晚行界 +0.27~0.37s 且与扫光同卡两
/// 钟不一致——翻行改由本 driver 的 judge（即 onTick 下发的
/// now）在 VC tick 内逐帧直驱判行，与扫光严格同钟；boundary
/// 驱动降为校准/对账源。settle 的隔离对象随之变为扫光与翻
/// 行共用的呈现钟本身（两者同读 judge，settle 校正同时利
/// 两边，不再有第二条翻行路径可被隔离）。
final class LyricClockDriver {
    var onTick: ((Double) -> Void)?

    private var displayLink: CADisplayLink?
    private var anchorTime: Double = 0
    private var anchorWall: CFTimeInterval = 0
    private var anchorTrackId: String?
    /// 采锚时的播放态：外推只在锚为播放态时走单调时钟；与引擎
    /// 当前播放态不一致（暂停/恢复翻转）即重锚，不靠漂移阈值兜底。
    private var anchorWasPlaying = false
    /// 输出延迟缓存（秒）：(22) 起只作埋点记录、不再参与
    /// 时钟计算（见类注释的定案）；刷新点不变（start/路由
    /// 变化/重锚），每次刷新落面包屑供续查读数来源。
    private var outputLatency: Double = AVAudioSession.sharedInstance().outputLatency
    private var routeObserver: NSObjectProtocol?
    /// 稳态重锚时刻（3.7 (20)）：播放态锚定后 +settleWindow
    /// 触发一次无条件重锚（见 reanchor(armSettle:) 的定案注释）。
    private var settleReanchorAt: CFTimeInterval?
    /// settle 窗口时长与窗口内漂移重锚的重新武装上限（3.7
    /// (22)，DS R48）：窗口内重锚重置窗口重新武装、不再一
    /// 发即哑；超限才永久解除武装，防瞬态抖动下无限重锚。
    private static let settleWindow: CFTimeInterval = 0.35
    private static let settleRearmLimit = 3
    /// 本次武装周期内已重新武装次数（armSettle 重锚时清零）。
    private var settleRearmCount = 0

    /// 埋点原始读数（3.7 (22)）：outputLatency 原始值与当前
    /// 输出路由端口名，供 VC 的 lrc line 面包屑同帧对账；
    /// 两者都只记录、不参与任何时钟计算。
    var rawOutputLatency: Double { outputLatency }
    var currentRouteName: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "none"
    }

    func start() {
        guard displayLink == nil else { return }
        refreshOutputLatency(reason: "start")
        if routeObserver == nil {
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main) { [weak self] _ in
                self?.refreshOutputLatency(reason: "route")
            }
        }
        reanchor(armSettle: true)
        let link = CADisplayLink(target: LinkProxy(owner: self),
                                 selector: #selector(LinkProxy.step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        if settleReanchorAt != nil {
            settleReanchorAt = nil
            Breadcrumbs.log("lrc clock settle disarm reason=stop")
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
    }

    deinit { stop() }

    /// 刷新 outputLatency 读数（3.7 (22)）：值只记录、不再
    /// 影响时钟；每次刷新落面包屑（触发原因 + 旧值→新值），
    /// 供续查异常读数（如 0.149）是在哪个时机锁存的。
    private func refreshOutputLatency(reason: String) {
        let old = outputLatency
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        Breadcrumbs.log("lrc clock outlat refresh reason=\(reason) \(String(format: "%.3f", old))->\(String(format: "%.3f", outputLatency))")
    }

    /// 重锚：锚对 = (rawPlayhead 真值, 单调时钟)。
    ///
    /// armSettle（3.7 (20)，judge−raw +89ms 定案）：锚若在播放
    /// 启动瞬态被捕获——timeControlStatus 收敛为 .playing、锚
    /// 采到冻结位 playhead 后，player 时钟实际起步比锚捕获晚
    /// 约 0.1s——此后外推与 rawPlayhead 同速行进、恒超前约
    /// +99ms（judge 再减 outputLatency 约 10ms 即日志里的
    /// +89ms），且 0.099 < 0.12 漂移阈值、整首不被纠正（真机
    /// 日志恒定、不增长、亚阈值三特征全合）。修法：切歌/播停
    /// 翻转这类「瞬态锚」在 +0.35s 后做一次稳态重锚（此时
    /// playhead 已稳定行进、锚对齐真值），纠正量落面包屑
    /// `lrc clock settle drift=` 供真机对账；漂移重锚采的是
    /// 行进中真值、不 arm，避免链式重锚。
    private func reanchor(armSettle: Bool = false) {
        let engine = PlaybackEngine.shared
        refreshOutputLatency(reason: "reanchor")
        anchorTime = engine.rawPlayhead()
        anchorWall = CACurrentMediaTime()
        anchorTrackId = engine.currentTrack?.id
        anchorWasPlaying = engine.isPlaying
        settleReanchorAt = (armSettle && anchorWasPlaying)
            ? anchorWall + Self.settleWindow : nil
        if armSettle { settleRearmCount = 0 }
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

    /// 当前呈现时刻（3.7 (22) 定案）：与媒体时刻同尺，不再
    /// 扣 outputLatency（见类注释）——扫光与 Web cue 链同
    /// 口径。outputLatency 读数只经 rawOutputLatency 落埋点。
    func interpolatedNow() -> Double {
        mediaNow()
    }

    fileprivate func stepFrame() {
        let engine = PlaybackEngine.shared
        // 无曲/零时长时也要补发一帧：VC 的 hide 守卫靠 onTick 驱动，
        // 不补发则旧歌词会冻在 overlay 上无法收起。
        guard let track = engine.currentTrack, engine.duration > 0 else {
            onTick?(engine.rawPlayhead())
            return
        }
        if track.id != anchorTrackId {
            let settleWasArmed = settleReanchorAt != nil
            reanchor(armSettle: true)
            // 解除武装必落面包屑（3.7 (22)，DS R48）：切歌重锚
            // 若没能重新武装（如新曲锚为暂停态），把解除记下来，
            // 不再像 (21) 前那样静默覆写 nil 无从对账。
            if settleWasArmed, settleReanchorAt == nil {
                Breadcrumbs.log("lrc clock settle disarm reason=track-change")
            }
        }
        // 播放/暂停翻转：立即以真实 playhead 重锚（暂停冻结在
        // 真位置、恢复从真位置起跑），不留整段暂停时长的外推误差。
        if engine.isPlaying != anchorWasPlaying {
            let settleWasArmed = settleReanchorAt != nil
            reanchor(armSettle: true)
            if settleWasArmed, settleReanchorAt == nil {
                Breadcrumbs.log("lrc clock settle disarm reason=playflip")
            }
        }
        // 稳态重锚（3.7 (20) 定案、(21) 隔离保留）：瞬态锚
        // +0.35s 落定后无条件对齐一次真值，纠正量落面包屑；
        // 已暂停/已切歌则直接作废。只作用本呈现时钟（扫光），
        // 翻行路径不读（(21) 起翻行走 boundary 事件）。面包屑
        // 同记三基准（engine currentTime 台阶缓存 / rawPlayhead
        // 真值 / 外推 mediaNow），供后续判定 +99ms 超前的镜像
        // 解释（audit-3721 B2）——三者同帧一读，差在哪一侧可
        // 对账。开关关闭时 settle 整体停用（A/B 对照）。
        if !LyricTiming.settleReanchorEnabled {
            if settleReanchorAt != nil {
                settleReanchorAt = nil
                Breadcrumbs.log("lrc clock settle disarm reason=disabled")
            }
        } else if let settleAt = settleReanchorAt {
            if !engine.isPlaying {
                settleReanchorAt = nil
                Breadcrumbs.log("lrc clock settle disarm reason=paused")
            } else if track.id != anchorTrackId {
                settleReanchorAt = nil
                Breadcrumbs.log("lrc clock settle disarm reason=track-changed")
            } else if CACurrentMediaTime() >= settleAt {
                settleReanchorAt = nil
                let extrapolated = mediaNow()
                let raw = engine.rawPlayhead()
                let drift = raw - extrapolated
                reanchor()
                Breadcrumbs.log("lrc clock settle drift=\(String(format: "%.3f", drift)) engine=\(String(format: "%.3f", engine.currentTime)) raw=\(String(format: "%.3f", raw)) extrapolated=\(String(format: "%.3f", extrapolated))")
            }
        }
        let predicted = anchorWasPlaying
            ? anchorTime + (CACurrentMediaTime() - anchorWall)
            : anchorTime
        // seek 在途时落点由 seek 完成回调回正，期间不重锚。
        // 漂移检查比的是媒体时刻同口径（(22) 起呈现出口同尺，
        // 不再有扣减项混在两边）。
        if !engine.isSeekPending {
            let drift = engine.rawPlayhead() - predicted
            if abs(drift) > LyricTiming.reanchorThreshold {
                let settleWasArmed = settleReanchorAt != nil
                reanchor()
                Breadcrumbs.log("lrc clock reanchor reason=drift drift=\(String(format: "%.3f", drift))")
                // settle 重新武装（3.7 (22)，DS R48）：(21) 前
                // 任一漂移重锚都覆写 settleReanchorAt=nil——起播
                // 窗口内一次重锚即永久解除武装且无面包屑（一发
                // 即哑，audit-3722 §7）。改：武装中的漂移重锚
                // 只重置窗口、重新计时；超重新武装上限才永久
                // 解除并落面包屑。窗口外（未武装）重锚维持原
                // 语义，不凭空武装。
                if settleWasArmed, LyricTiming.settleReanchorEnabled,
                   engine.isPlaying {
                    if settleRearmCount < Self.settleRearmLimit {
                        settleRearmCount += 1
                        settleReanchorAt = anchorWall + Self.settleWindow
                        Breadcrumbs.log("lrc clock settle rearm n=\(settleRearmCount) reason=drift")
                    } else {
                        Breadcrumbs.log("lrc clock settle disarm reason=drift-cap n=\(settleRearmCount)")
                    }
                }
            }
        }
        let now = anchorWasPlaying
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
