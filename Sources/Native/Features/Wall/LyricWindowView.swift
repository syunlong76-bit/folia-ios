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
    /// 3.7 (55) 工作流 G：基线仍为 0，lead 改计算属性 = 基线
    /// + 用户全局歌词时间轴偏移（SettingsStore
    /// .lyricTimelineOffsetSeconds，设置页「歌词」页签，±2s
    /// 钳制）——墙链翻行判定（WallPrototype judge 的
    /// now + LyricTiming.lead）与本文件扫光起点（lineStart
    /// - LyricTiming.lead）同吃此值，偏移对墙链真实生效；
    /// 正值歌词提前、负值延后。舞台链不经本常量（其汇聚点
    /// 在 StageViewController.positionNow，另行接入）。
    static var lead: Double {
        0.0 + SettingsStore.lyricTimelineOffsetSeconds
    }
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
/// (97) 第 10 条（封面歌词新样式，样板 cover-lyric-apple-style
/// 定版）：三段呈现——已唱填充段（brightLabel＋mask）／前锋亮
/// 边段（frontLabel＋mask，宽 = 行宽 13%，居前锋位）／未唱底
/// 段（dimLabel）；左对齐（样板口径，行首留白由宿主帧内缩）；
/// 配色由 applyStyle97 按封面明暗模式下发；字形阴影退役、
/// 当前行光晕改由容器层 drop-shadow 承担（见 LyricWindowView）。
private final class SweepLyricLineView: UIView {
    private let dimLabel = UILabel()
    private let brightLabel = UILabel()
    private let frontLabel = UILabel()
    private let maskLayer = CALayer()
    private let frontMaskLayer = CALayer()
    /// 整行文本宽缓存（(62) 尾波第 4 组）：setText 时一次量
    /// 好，updateMask 与逐字进度逐帧只读——旧实现每帧约 4 次
    /// 整行 NSString shaping/量宽，是歌词条拖动卡帧主因之一。
    private(set) var cachedTextWidth: CGFloat = 0
    var progress: Double = 0 {
        didSet { if progress != oldValue { updateMask() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for label in [dimLabel, brightLabel, frontLabel] {
            label.textAlignment = .left
            label.textColor = .white
            // (97) 第 10 条：当前行无字形阴影（样板 .cur
            // text-shadow:none），光晕走容器 drop-shadow。
            label.layer.shadowOpacity = 0
            addSubview(label)
        }
        dimLabel.alpha = 1
        maskLayer.backgroundColor = UIColor.black.cgColor
        frontMaskLayer.backgroundColor = UIColor.black.cgColor
        // 扫光迟滞摘除（3.7 (44) 呈现层审计）：progress 每帧改
        // mask frame，未禁隐式动画时被 CALayer 默认 0.25s 隐式
        // 动画低通——扫光边恒定拖尾约 250ms（位置量本身逐帧
        // 精确、纯呈现层叠加）。禁 bounds/position 动作后 mask
        // 与 progress 同帧到位，拖尾 250ms → 0。
        maskLayer.actions = ["bounds": NSNull(), "position": NSNull(),
                             "anchorPoint": NSNull()]
        frontMaskLayer.actions = maskLayer.actions
        brightLabel.layer.mask = maskLayer
        frontLabel.layer.mask = frontMaskLayer
        applyStyle97(light: false)
    }

    /// (97) 第 10 条配色（样板渐变三段）：深封面＝已唱纯白／
    /// 前锋暖金 #FFE9AD／未唱白 48%；浅封面＝已唱深红
    /// #C8102E／前锋暖橙 #FF7847／未唱深炭 42%。
    func applyStyle97(light: Bool) {
        if light {
            dimLabel.textColor = UIColor(red: 35 / 255, green: 33 / 255,
                blue: 38 / 255, alpha: 0.42)
            brightLabel.textColor = UIColor(red: 200 / 255, green: 16 / 255,
                blue: 46 / 255, alpha: 1)
            frontLabel.textColor = UIColor(red: 1, green: 120 / 255,
                blue: 71 / 255, alpha: 1)
        } else {
            dimLabel.textColor = UIColor.white.withAlphaComponent(0.48)
            brightLabel.textColor = .white
            frontLabel.textColor = UIColor(red: 1, green: 233 / 255,
                blue: 173 / 255, alpha: 1)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setText(_ attributed: NSAttributedString) {
        dimLabel.attributedText = attributed
        brightLabel.attributedText = attributed
        frontLabel.attributedText = attributed
        // 整行宽一次量好缓存（量宽口径与旧 updateMask 逐帧量
        // 宽逐字一致：同一属性集、ceil 取整）。
        if attributed.length > 0 {
            let attrs = attributed.attributes(at: 0, effectiveRange: nil)
            cachedTextWidth = ceil((attributed.string as NSString)
                .size(withAttributes: attrs).width)
        } else {
            cachedTextWidth = 0
        }
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
        frontLabel.frame = bounds
        updateMask()
    }

    private func updateMask() {
        guard bounds.width > 0,
              let text = dimLabel.attributedText, text.length > 0 else {
            maskLayer.frame = .zero
            frontMaskLayer.frame = .zero
            return
        }
        // (97) 第 10 条：左对齐口径——文本自帧左缘起（行首
        // 留白由宿主给行帧内缩），扫光起点恒 0。
        let textWidth = cachedTextWidth
        let span = min(textWidth, bounds.width)
        let frontier = span * CGFloat(progress)
        // 前锋带：样板渐变的前锋色段约当前锋位 −9%～+4%
        // （占行宽 13%）；已唱段止于带左缘。
        let band = span * 0.13
        let fillEnd = max(0, frontier - band * (9.0 / 13.0))
        maskLayer.frame = CGRect(x: 0, y: 0,
                                 width: fillEnd,
                                 height: bounds.height)
        if progress > 0, progress < 0.999 {
            frontMaskLayer.frame = CGRect(x: fillEnd, y: 0,
                                          width: min(band, span - fillEnd),
                                          height: bounds.height)
        } else {
            frontMaskLayer.frame = .zero
        }
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

/// (97) 第 10 条：邻行景深行——文本离屏渲染成图后按距施
/// 高斯模糊（样板 TrueFocus 式衰减：|d|=1 模糊 0.7、|d|=2
/// 1.8、|d|≥3 3pt）。UILabel 本体无模糊通道，故走图化：
/// 行内容只在翻行/宽度/模式变化时重渲（非逐帧），成本可控；
/// 阴影随图一并烘焙（模式决定：深封面黑影、浅封面白晕）。
private final class LyricBlurRow97: UIView {
    private let imageView = UIImageView()
    private var attributed: NSAttributedString?
    private var blur: CGFloat = 0
    private var shadowColor: UIColor = .black
    private var shadowOpacity: Float = 0
    private var shadowRadius: CGFloat = 0
    private var renderKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setText97(_ attributed: NSAttributedString, blur: CGFloat,
                   shadowColor: UIColor, shadowOpacity: Float,
                   shadowRadius: CGFloat) {
        self.attributed = attributed
        self.blur = blur
        self.shadowColor = shadowColor
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        renderIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderIfNeeded()
    }

    private func renderIfNeeded() {
        guard bounds.width > 0, bounds.height > 0,
              let attributed else { imageView.image = nil; return }
        let key = "\(attributed.hash)|\(blur)|\(Int(bounds.width))x\(Int(bounds.height))|\(shadowOpacity)|\(shadowColor.hashValue)"
        guard key != renderKey else { return }
        renderKey = key
        if attributed.length == 0 { imageView.image = nil; return }
        let pad = blur * 3 + shadowRadius * 2 + 4
        let size = CGSize(width: bounds.width + pad * 2,
                          height: bounds.height + pad * 2)
        let label = UILabel()
        label.attributedText = attributed
        label.textAlignment = .left
        label.layer.shadowColor = shadowColor.cgColor
        label.layer.shadowOpacity = shadowOpacity
        label.layer.shadowRadius = shadowRadius
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.frame = CGRect(x: pad, y: pad,
                             width: bounds.width, height: bounds.height)
        let holder = UIView(frame: CGRect(origin: .zero, size: size))
        holder.addSubview(label)
        var image = UIGraphicsImageRenderer(size: size).image { ctx in
            holder.layer.render(in: ctx.cgContext)
        }
        if blur > 0,
           let ci = CIImage(image: image),
           let filter = CIFilter(name: "CIGaussianBlur", parameters: [
               kCIInputImageKey: ci, kCIInputRadiusKey: blur]),
           let out = filter.outputImage {
            let ctx = CIContext(options: nil)
            if let cg = ctx.createCGImage(out, from: ci.extent) {
                image = UIImage(cgImage: cg, scale: image.scale,
                                orientation: .up)
            }
        }
        imageView.image = image
        imageView.frame = CGRect(x: -pad, y: -pad,
                                 width: size.width, height: size.height)
    }
}

/// 展开卡滚动歌词窗口（包一 P2/P3：自 WallPosterCell 搬家）：独立
/// overlay 视图，不随 cell 复用生灭；渲染栈与视觉参数（字号公式、
/// 6 行窗、alpha 梯度、扫光、呼吸、时长夹取）与旧 cell 实现逐字
/// 一致，只换宿主与扫光时钟来源（VC 注入的插值时钟）。
/// (97) 第 10 条视觉换代（样板 cover-lyric-apple-style 定版，
/// 旧 Songti/居中/黑影口径退役）：封面在场、仅横带羽化轻罩
/// （罩色随封面明暗）、左对齐、当前行 800 字重＋三段填充
/// （已唱/前锋/未唱）＋容器光晕、邻行按距衰减（透明＋模糊
/// ＋缩放）、行迁移 0.62s 样板贝塞尔曲线。窗口/滑行/扫光时
/// 钟机制不动（(41) 解耦口径保留：当前行同帧落位、邻行滑行）。
final class LyricWindowView: UIView {

    /// 扫光时钟（VC 注入 = 插值时钟）：扫光据此推进，暂停即冻结。
    var clock: (() -> Double)?

    // port90：clip 覆盖（clipTopOverride89）随展开卡动作排撤除退役，
    // 歌词 clip 恒走默认 0.40 起点。

    private let lyricScrimView = UIView()
    private let lyricGradient = CAGradientLayer()
    private let lyricClipView = UIView()
    private let lyricLinesContainer = UIView()
    private var lyricPlainLabels: [Int: LyricBlurRow97] = [:]
    private let lyricSweepView = SweepLyricLineView()
    /// (97) 第 10 条：封面明暗模式（宿主采样歌词横带亮度后
    /// 经 applyCoverMode97 下发；默认深封面口径）。
    private(set) var coverLight97 = false
    /// (97) 第 10 条：当前行字阶缩放（样板 cur scale 1.12，
    /// 与呼吸动画共用 transform，故收口为基准值）。
    private let sweepScale97: CGFloat = 1.12
    /// (97) 第 10 条：邻行按距缩放表（行号 → scale）。
    private var rowScales97: [Int: CGFloat] = [:]
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
    /// 逐字前缀宽表（(62) 尾波第 4 组）：renderLyricWindow 时
    /// 按当前逐字戳一次算好——sweepPrefixWidths[i] = 前 i 个
    /// 词拼串的宽（[0]=0、共 words.count+1 项），sweepWord-
    /// Widths[i] = 第 i 词自身宽。逐帧进度只查表做乘法，量
    /// 宽次数从每帧约 3 次降到每行渲染 1 轮。
    private var sweepPrefixWidths: [CGFloat] = []
    private var sweepWordWidths: [CGFloat] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        // (97) 第 10 条：横带羽化轻罩（整卡幅、罩在文字之
        // 下、上下羽化为 0）+ 裁剪窗 + 6 行容器（行 2 = 扫光
        // 行）。罩的 6 档渐变与配色在 applyCoverMode97 收口。
        lyricScrimView.isHidden = true
        lyricScrimView.clipsToBounds = true
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
                let label = LyricBlurRow97()
                lyricPlainLabels[row] = label
                lyricLinesContainer.addSubview(label)
            }
        }
        applyCoverMode97(light: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        sweepDisplayLink?.invalidate()
    }

    /// (97) 第 10 条：封面明暗模式下发（宿主按样板规则采样
    /// 歌词横带亮度：L≥0.35 判浅）。收口三处：横带罩渐变
    /// （深＝黑罩 0/.34/.44/.38/.16/0、浅＝白罩
    /// 0/.36/.50/.42/.18/0，档位 20/34/50/66/76/86%）、扫
    /// 光行三段配色、当前行容器光晕（深＝暖金光、浅＝暖橙
    /// 光，radius 7）；邻行配色/阴影在 renderLyricWindow 按
    /// 本模式烘焙进图。模式变更即重渲现窗。
    func applyCoverMode97(light: Bool) {
        coverLight97 = light
        let veil: UIColor = light ? .white : .black
        let alphas: [CGFloat] = light
            ? [0, 0, 0.36, 0.50, 0.42, 0.18, 0, 0]
            : [0, 0, 0.34, 0.44, 0.38, 0.16, 0, 0]
        lyricGradient.colors = alphas.map {
            veil.withAlphaComponent($0).cgColor
        }
        lyricGradient.locations = [0, 0.20, 0.34, 0.50, 0.66, 0.76, 0.86, 1]
        lyricGradient.startPoint = CGPoint(x: 0.5, y: 0)
        lyricGradient.endPoint = CGPoint(x: 0.5, y: 1)
        lyricSweepView.applyStyle97(light: light)
        // 当前行 drop-shadow 光晕（样板 .cur filter）：跟随
        // 文本 alpha 轮廓，非矩形投影。
        lyricSweepView.layer.shadowColor = light
            ? UIColor(red: 1, green: 110 / 255, blue: 64 / 255, alpha: 1).cgColor
            : UIColor(red: 1, green: 238 / 255, blue: 190 / 255, alpha: 1).cgColor
        lyricSweepView.layer.shadowOpacity = light ? 0.45 : 0.5
        lyricSweepView.layer.shadowRadius = 7
        lyricSweepView.layer.shadowOffset = .zero
        if !lyricTexts.isEmpty { renderLyricWindow() }
    }

    /// (97) 第 10 条：行 transform 收口 = 距衰减缩放 ∘ 滑行
    /// 位移（滑行时 slideY=行高、落位 0）。
    private func rowTransform97(row: Int, slideY: CGFloat) -> CGAffineTransform {
        let s = rowScales97[row] ?? 1
        return CGAffineTransform(translationX: 0, y: slideY)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
    }

    /// 等价旧 cell 的空窗口下发：整组收起并停扫光。
    func clear() {
        sweepWords = nil
        setWindow(texts: [], lineStart: 0, lineDuration: 0, slide: false)
        lyricLinesContainer.layer.removeAllAnimations()
        lyricLinesContainer.transform = .identity
        for row in 0..<6 where row != 2 {
            lyricPlainLabels[row]?.layer.removeAllAnimations()
            lyricPlainLabels[row]?.transform = rowTransform97(row: row, slideY: 0)
        }
        lyricSweepView.layer.removeAllAnimations()
        lyricSweepView.transform = CGAffineTransform(
            scaleX: sweepScale97, y: sweepScale97)
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
            // (97) 第 10 条：行迁移曲线换样板定版 0.62s
            // cubic-bezier(.32,.72,.24,1)（系统弹簧感），经
            // UIViewPropertyAnimator 的 UICubicTimingParameters
            // 精确落曲线；位移与距衰减缩放经 rowTransform97
            // 复合，落位值非 identity 而是各行衰减缩放。
            for row in 0..<6 where row != 2 {
                lyricPlainLabels[row]?.transform =
                    rowTransform97(row: row, slideY: lyricLineHeight)
            }
            let slideAnimator97 = UIViewPropertyAnimator(
                duration: 0.62,
                timingParameters: UICubicTimingParameters(
                    controlPoint1: CGPoint(x: 0.32, y: 0.72),
                    controlPoint2: CGPoint(x: 0.24, y: 1)))
            slideAnimator97.addAnimations {
                for row in 0..<6 where row != 2 {
                    self.lyricPlainLabels[row]?.transform =
                        self.rowTransform97(row: row, slideY: 0)
                }
            }
            slideAnimator97.addCompletion { position in
                // 被打断（position 非 .end）时打断方已接管
                // transform 与内容，此处不触碰任何状态——保
                // 留防行窗双写的守卫语义（旧 completion 同款）。
                guard position == .end else { return }
                for row in 0..<6 where row != 2 {
                    self.lyricPlainLabels[row]?.transform =
                        self.rowTransform97(row: row, slideY: 0)
                }
            }
            slideAnimator97.startAnimation()
        } else {
            lyricLinesContainer.layer.removeAllAnimations()
            lyricLinesContainer.transform = .identity
            for row in 0..<6 where row != 2 {
                lyricPlainLabels[row]?.layer.removeAllAnimations()
                lyricPlainLabels[row]?.transform =
                    rowTransform97(row: row, slideY: 0)
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
        // (97) 第 10 条：距衰减表（样板 TrueFocus 口径）——
        // |d|=1: op .66/blur .7/scale 1；|d|=2: .40/1.8/.97；
        // |d|≥3: .26/3/.95；已唱行（d<0）op +0.08。
        // 行序：0,1 为已唱侧（d=-2,-1），3,4,5 为未唱（+1,+2,+3）。
        let decay97: [Int: (op: CGFloat, blur: CGFloat, scale: CGFloat)] = [
            0: (0.48, 1.8, 0.97),
            1: (0.74, 0.7, 1.0),
            3: (0.66, 0.7, 1.0),
            4: (0.40, 1.8, 0.97),
            5: (0.26, 3.0, 0.95),
        ]
        for row in 0..<6 {
            let text = row < lyricTexts.count ? lyricTexts[row] : ""
            if row == 2 {
                lyricSweepView.setText(lyricAttributed(text, center: true))
                lyricSweepView.transform = CGAffineTransform(
                    scaleX: sweepScale97, y: sweepScale97)
            } else if let label = lyricPlainLabels[row] {
                let d = decay97[row] ?? (0.45, 0, 1)
                rowScales97[row] = d.scale
                label.setText97(lyricAttributed(text, center: false),
                                blur: d.blur,
                                shadowColor: coverLight97 ? .white : .black,
                                shadowOpacity: coverLight97 ? 0.8 : 0.45,
                                shadowRadius: coverLight97 ? 5 : 4)
                label.alpha = d.op
                label.transform = rowTransform97(row: row, slideY: 0)
            }
        }
        // 逐字前缀宽表随本次渲染一并算好（量宽口径与旧逐帧
        // 路径一致：前缀整体量宽而非逐字累加，避免字距重复
        // 计入）。字号随宽度变化重渲染时表自动重建。
        if let words = sweepWords, !words.isEmpty {
            var prefix: [CGFloat] = [0]
            var widths: [CGFloat] = []
            var acc = ""
            for word in words {
                widths.append(lyricSweepView.measuredWidth(of: word.text))
                acc += word.text
                prefix.append(lyricSweepView.measuredWidth(of: acc))
            }
            sweepPrefixWidths = prefix
            sweepWordWidths = widths
        } else {
            sweepPrefixWidths = []
            sweepWordWidths = []
        }
    }

    /// (97) 第 10 条排版（样板口径）：系统字重——当前行
    /// 800（.heavy）、邻行 600（.semibold）同字号（大小差
    /// 距由距衰减缩放承担）；字距 .02em。当前行不带
    /// .foregroundColor 属性（三段配色由 SweepLyricLineView
    /// 的 label textColor 决定，属性会盖掉它）；邻行配色
    /// 烘焙进属性串（深封面白 .9／浅封面深炭 .88）。
    private func lyricAttributed(_ text: String, center: Bool) -> NSAttributedString {
        let font = center
            ? UIFont.systemFont(ofSize: lyricCurrentFontSize, weight: .heavy)
            : UIFont.systemFont(ofSize: lyricCurrentFontSize, weight: .semibold)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: lyricCurrentFontSize * 0.02
        ]
        if !center {
            attributes[.foregroundColor] = coverLight97
                ? UIColor(red: 35 / 255, green: 33 / 255,
                          blue: 38 / 255, alpha: 0.88)
                : UIColor.white.withAlphaComponent(0.9)
        }
        return NSAttributedString(string: text, attributes: attributes)
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

    /// 逐字进度：已唱前缀宽＋当前字按时长比例折算，占整行
    /// 文本宽的比例即 mask 进度（分母与 mask 的 span 口径一
    /// 致）。(62) 尾波第 4 组：分子分母全走缓存表（整行宽在
    /// SweepLyricLineView.setText 量好、前缀/词宽在 render-
    /// LyricWindow 量好），逐帧零量宽；表与当前戳不齐（极端
    /// 时序下表未建）时回落旧逐帧量宽路径，口径不变。
    private func wordSweepProgress(words: [LyricWordStamp], now: Double) -> Double {
        let total = lyricSweepView.cachedTextWidth
        guard total > 0 else { return 0 }
        guard sweepPrefixWidths.count == words.count + 1,
              sweepWordWidths.count == words.count else {
            return wordSweepProgressMeasured(words: words, now: now, total: total)
        }
        for (i, word) in words.enumerated() {
            if now >= word.start + word.duration { continue }
            if now >= word.start {
                let frac = (now - word.start) / word.duration
                let width = sweepPrefixWidths[i]
                    + sweepWordWidths[i] * CGFloat(frac)
                return min(max(Double(width / total), 0), 1)
            }
            // now 还没到本词：已唱即前 i 词前缀。
            return min(max(Double(sweepPrefixWidths[i] / total), 0), 1)
        }
        // 全部唱完：分子＝全词拼串宽（表中末项）。
        return min(max(Double(sweepPrefixWidths[words.count] / total), 0), 1)
    }

    /// 逐字进度的逐帧量宽回落路径（旧实现，口径基准）：只在
    /// 前缀宽表未建时用。
    private func wordSweepProgressMeasured(words: [LyricWordStamp], now: Double,
                                           total: CGFloat) -> Double {
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
    /// (97) 第 10 条：基准缩放改样板字阶 1.12（呼吸在其上叠
    /// ±4%），不再以 identity 为落点。
    private func playLyricBreathing() {
        lyricSweepView.layer.removeAllAnimations()
        lyricSweepView.transform = CGAffineTransform(
            scaleX: sweepScale97, y: sweepScale97)
        UIView.animate(withDuration: 0.10, delay: 0, options: [.curveEaseOut]) {
            self.lyricSweepView.transform = CGAffineTransform(
                scaleX: self.sweepScale97 * 1.04, y: self.sweepScale97 * 1.04)
        } completion: { _ in
            UIView.animate(withDuration: 0.22, delay: 0,
                           usingSpringWithDamping: 0.6, initialSpringVelocity: 0.3,
                           options: []) {
                self.lyricSweepView.transform = CGAffineTransform(
                    scaleX: self.sweepScale97, y: self.sweepScale97)
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
        // (97) 第 10 条：轻罩改整卡幅（羽化带相对卡高定位，
        // 样板档位 20–86%），不再只罩 clip 帧。
        lyricScrimView.frame = bounds
        lyricGradient.frame = lyricScrimView.bounds
        lyricClipView.frame = clipFrame
        lyricLinesContainer.frame = CGRect(x: 0, y: 0, width: clipWidth,
                                           height: lyricLineHeight * 6)
        // (97) 第 10 条：行帧左对齐内缩 8%（样板 padding-left
        // 8cqw），文本自左缘起、扫光同口径。
        let rowInset97 = clipWidth * 0.08
        for row in 0..<6 {
            let frame = CGRect(x: rowInset97, y: CGFloat(row) * lyricLineHeight,
                               width: clipWidth - rowInset97,
                               height: lyricLineHeight)
            if row == 2 { lyricSweepView.frame = frame }
            else if let label = lyricPlainLabels[row] {
                label.frame = frame
            }
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
