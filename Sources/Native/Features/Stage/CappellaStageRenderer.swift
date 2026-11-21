import UIKit
import QuartzCore

// 群唱 cappella（M2' 照搬对齐版）：按 folia-major 网页版 cappella
// 的展示行为逐项实现，把带时间戳的歌词行编排成左右交替的聊天
// 消息流。对齐要点（依据文件均为 folia-major/src/components/
// visualizer/cappella/ 下同名文件）：
//  - 消息编排（cappellaMessages.ts）：标题消息恒在首位（右侧、
//    avatarIndex 8）；歌词行按 normal 强度档 sequencing 确定性
//    分配发送者——sideSequence [left,right,left,right,right]
//    轮换、每 5 行强制右侧、短行（去空白 ≤12 字）以 0.68 概率
//    沿用上一发送者、0.18 概率翻转侧别；随机种子为 FNV-1a
//    hash(parts.join('|')) / 0xffffffff（与网页 seededUnit 同
//    公式、同入参 'carry'/'flip' + startTime + lineIndex）。
//  - 气泡 metrics（VisualizerCappella.tsx / CappellaMessageRow
//    .tsx / cappellaBubbleMetrics.ts）：baseFontSize 18（clamp
//    15–26）、行高 ×1.45、active/inactive 字号倍率 1.34/0.94、
//    内边距 active 20×16 / inactive 16×12、最小高 64/44、边框
//    1pt、圆角 24（靠发送者侧的底角 6）、最大文本宽公式与
//    68%/78% 群组宽比、头像 40×40 圆形 + 间隔 12。
//  - 揭示时序（cappellaReveal.ts）：逐字 reveal 时刻由共享
//    StageLyricUnits 的单元时序按字素均分导出（协议 words 恒
//    nil 时即网页 buildLineGraphemeTimeline 的 even 口径）；
//    气泡尺寸用提前 0.2s 的目标字数（WIDTH_LOOKAHEAD），逐字
//    淡入时长 = 字素时长（下限 40ms），时间戳在末字淡入完成
//    后出现（formatTimestamp(endTime)，11pt，alpha 0.62）。
//  - 强度（cappellaIntensity.ts）：原生无主题 animationIntensity
//    数据源，恒取 normal 档（与 classic/partita 的 normal 口径
//    一致）：行入场 y+22/scale 0.98/0.32s、出场 y−18/scale
//    0.965/0.24s、active scale 1.12、passed scale 0.92 /
//    opacity 0.82、头像弹簧 stiffness 340 / damping 28 /
//    mass 0.72（换算阻尼比 ≈0.895）、active 阴影 alpha 0.34、
//    气泡 glow（白，右 alpha 0.34 / 左 0.18，opacity 0.4，
//    1.8s 线性横扫）。
//  - 配色（cappellaMessageLayout.ts getBubbleColors +
//    colorMix.ts mixColors 通道线性混合）：右侧 bg =
//    mix(accent, primary, 0.18, α0.94)、border = mix(accent,
//    primary, 0.34, α0.30)、text = background；左侧按
//    avatarTone = (avatarIndex % 9)/8 取 accentMix = 0.18 +
//    tone×0.62，bg = mix(secondary, accent, accentMix, α1)、
//    border = mix(secondary, accent, min(accentMix+0.18,1),
//    α0.26)、text = primary。主题色经协议 PaletteTokens 落地。
//  - 可见窗口（cappellaMessageLayout.ts getVisibleMessages）：
//    只保留 lineIndex ≤ 当前行 的消息，自最新起按估算高度回填
//    至可用高 max(200, 视口高 − 240)，至少 2 条、上限
//    MAX_VISIBLE_MESSAGES = 20 条视图。
// 数据源缺口（明确标注，不假装有图）：
//  - 头像（(57) C2 对齐）：avatarSource 经 CappellaTuning-
//    Store 可调（缺省 cover）。cover 档已接线——封面位图经
//    宿主 NativeCoverLoader 取（与 Monet 同一取图管线），
//    按网页 CappellaAvatar 的宫格裁切呈现（图放大至 300%
//    后取 resolvedAvatarIndex 所在格，右 8 / 左经
//    LEFT_AVATAR_INDICES 映射）；color 档与无封面时的回退
//    为网页同式的宫格渐变（linear-gradient 135° primary→
//    accent、300% 尺寸、同格偏移）。builtin/custom 图片包
//    （avatarImages.ts / customPacks.ts）不在原生包内且
//    协议无图片下发通道，两档只存不用、呈现回退宫格渐变。
//  - 表情（emo）消息依赖图片池（emoImages.ts / custom-
//    Packs.ts），池不在原生包内；池为空时网页本身即
//    showEmoMessages=false，故原生不生成 emo 消息，间奏行
//    "......" 按网页无池分支落为普通歌词气泡。调参
//    showEmoMessages / emojiPackSource 已存（Cappella-
//    Tuning.swift），待图包通道接入后生效。
//  - 协议 LyricLine 无 agentId 字段：cappellaMessageSenders
//    的 TTML agent 解析分支永不触发，发送者恒走 sequencing。
// 时钟纪律不变：只消费宿主 frameTick 的锚点位置，不自建时钟
// 源；歌词区不响应点按（supportsLineSeek=false）。

// MARK: - 常量（normal 强度档，cappellaIntensity.ts）

private enum CappellaConst {
    // cappellaConstants.ts
    static let shortLineCharLimit = 12
    static let maxVisibleMessages = 20
    static let avatarGridSize = 3
    static let leftAvatarIndices = [0, 3, 6, 1, 4]
    static let rightAvatarIndex = 8
    static let layoutCacheLimit = 32
    static let widthLookahead: TimeInterval = 0.2
    static let bubbleFontWeightNote = 400 // CAPPELLA_BUBBLE_FONT_WEIGHT
    static let interludeText = "......"
    static let defaultCharFadeMs: Double = 220
    static let minCharFadeMs: Double = 40
    static let preheatMaxLead: TimeInterval = 1.1 // CAPPELLA_PREHEAT_WINDOW.maxLead

    // cappellaIntensity.ts（normal 档 sequencing）
    static let forceRightEveryLines = 5
    static let shortLineCarryChance = 0.68
    static let sideSequence: [Bool] = [true, false, true, false, false] // true = left
    static let sideFlipChance = 0.18
    // randomEmoChance 0.1 / minLinesBetweenRandomEmos 3 /
    // maxRandomEmoRatio 1/8：依赖表情图片池，原生无数据源不落。

    // cappellaIntensity.ts（normal 档 motion）
    static let rowEnterY: CGFloat = 22
    static let rowEnterScale: CGFloat = 0.98
    static let rowEnterDuration: TimeInterval = 0.32
    static let rowExitY: CGFloat = -18
    static let rowExitScale: CGFloat = 0.965
    static let rowExitDuration: TimeInterval = 0.24
    // avatarSpring stiffness 340 / damping 28 / mass 0.72 →
    // 阻尼比 ζ = 28 / (2×√(340×0.72)) ≈ 0.895。
    static let groupSpringDamping: CGFloat = 0.895
    static let groupSpringDuration: TimeInterval = 0.5
    static let activeScale: CGFloat = 1.12
    static let passedScale: CGFloat = 0.92
    static let passedOpacity: CGFloat = 0.82
    static let activeFontMultiplier: CGFloat = 1.34
    static let inactiveFontMultiplier: CGFloat = 0.94
    static let activePaddingX: CGFloat = 20
    static let activePaddingY: CGFloat = 16
    static let inactivePaddingX: CGFloat = 16
    static let inactivePaddingY: CGFloat = 12
    static let activeMinHeight: CGFloat = 64
    static let inactiveMinHeight: CGFloat = 44
    static let glowOpacity: CGFloat = 0.4
    static let glowDuration: TimeInterval = 1.8
    static let glowRightAlpha: CGFloat = 0.34
    static let glowLeftAlpha: CGFloat = 0.18
    static let activeShadowAlpha: CGFloat = 0.34
    // emoActiveSize 160 / emoInactiveSize 110 / emoEnterScale
    // 0.6 / emoSizeTransitionDuration 0.25：emo 无数据源不落。

    // 几何（VisualizerCappella.tsx / CappellaMessageRow.tsx /
    // CappellaBubbleParts.tsx 的 Tailwind 量值，1rem = 16px）
    static let avatarSize: CGFloat = 40
    static let rowGap: CGFloat = 12 // gap-3
    static let bubbleRadius: CGFloat = 24 // rounded-3xl
    static let bubbleTailRadius: CGFloat = 6 // rounded-br/bl-md
    static let bubbleBorderWidth: CGFloat = 1
    static let activeMinWidth: CGFloat = 72
    static let timestampFontSize: CGFloat = 11
    static let timestampOpacity: CGFloat = 0.62
}

// MARK: - 种子（cappellaMessages.ts 的 hashString / seededUnit）

/// JS 数值转字符串口径：整数不带小数点（JS String(12) = "12"，
/// Swift 默认 "12.0"），其余用最短往返表示（与 JS 一致）。
private func cappellaJSNumber(_ value: Double) -> String {
    if value == value.rounded() && abs(value) < 1e15 {
        return String(Int64(value))
    }
    return String(value)
}

/// FNV-1a（hash ^= charCode; hash = imul(hash, 16777619)），
/// charCode 按 UTF-16 码元取，与 JS charCodeAt 同口径。
private func cappellaSeededUnit(_ parts: [String]) -> Double {
    var hash: UInt32 = 2166136261
    for unit in parts.joined(separator: "|").utf16 {
        hash ^= UInt32(unit)
        hash = hash &* 16777619
    }
    return Double(hash) / 4294967295.0
}

private func cappellaSeededUnit(tag: String, start: TimeInterval, index: Int) -> Double {
    cappellaSeededUnit([tag, cappellaJSNumber(start), String(index)])
}

// MARK: - 颜色混合（colorMix.ts mixColors：通道线性混合）

private func cappellaMix(_ from: UIColor, _ to: UIColor,
                         amount: CGFloat, alpha: CGFloat) -> UIColor {
    var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
    var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
    from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
    to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
    let t = max(0, min(1, amount))
    return UIColor(red: fr + (tr - fr) * t,
                   green: fg + (tg - fg) * t,
                   blue: fb + (tb - fb) * t,
                   alpha: max(0, min(1, alpha)))
}

// MARK: - 消息模型与编排（cappellaMessages.ts）

private enum CappellaMessageKind { case title, lyric }

private struct CappellaMessageModel {
    var id: String
    var kind: CappellaMessageKind
    var line: LyricLine? // title 为 nil
    var lineIndex: Int // title 为 -1
    var titleText: String
    var isRight: Bool
    var avatarIndex: Int // 原始序号（左侧为递增游标、右侧 8）
    var resolvedAvatarIndex: Int // 头像落位序号（左侧经 LEFT_AVATAR_INDICES 映射）
}

/// 确定性编排：同一曲目每次结果一致。agent 分支因协议无
/// agentId 恒不触发；emo 分支因图片池缺失恒不生成（见头部）。
private func buildCappellaMessages(lines: [LyricLine],
                                   titleText: String) -> [CappellaMessageModel] {
    var messages: [CappellaMessageModel] = [CappellaMessageModel(
        id: "title", kind: .title, line: nil, lineIndex: -1,
        titleText: titleText, isRight: true,
        avatarIndex: CappellaConst.avatarGridSize * CappellaConst.avatarGridSize - 1,
        resolvedAvatarIndex: CappellaConst.rightAvatarIndex)]

    var sideSequenceCursor = 0
    var nextLeftAvatarCursor = 0
    var lastSender: (isRight: Bool, avatarIndex: Int)? = nil

    for (lineIndex, line) in lines.enumerated() {
        let compactCount = line.text.filter { !$0.isWhitespace }.count
        let isShortLine = compactCount <= CappellaConst.shortLineCharLimit
        let shouldForceRight = (lineIndex + 1) % CappellaConst.forceRightEveryLines == 0
        let shouldCarry = isShortLine && lastSender != nil
            && cappellaSeededUnit(tag: "carry", start: line.start, index: lineIndex)
                <= CappellaConst.shortLineCarryChance
        let baseIsLeft = CappellaConst.sideSequence[
            sideSequenceCursor % CappellaConst.sideSequence.count]
        let shouldFlip = !shouldForceRight
            && cappellaSeededUnit(tag: "flip", start: line.start, index: lineIndex)
                < CappellaConst.sideFlipChance
        let resolvedIsLeft = shouldFlip ? !baseIsLeft : baseIsLeft

        let sender: (isRight: Bool, avatarIndex: Int)
        if shouldForceRight {
            sender = (true, CappellaConst.rightAvatarIndex)
        } else if shouldCarry, let last = lastSender {
            sender = last
        } else {
            sender = (!resolvedIsLeft, resolvedIsLeft
                ? nextLeftAvatarCursor : CappellaConst.rightAvatarIndex)
        }

        let resolvedAvatar: Int
        if sender.isRight {
            resolvedAvatar = CappellaConst.rightAvatarIndex
        } else {
            let pool = CappellaConst.leftAvatarIndices
            resolvedAvatar = pool[((sender.avatarIndex % pool.count) + pool.count) % pool.count]
        }
        messages.append(CappellaMessageModel(
            id: "line-\(line.id)", kind: .lyric, line: line,
            lineIndex: lineIndex, titleText: "", isRight: sender.isRight,
            avatarIndex: sender.avatarIndex, resolvedAvatarIndex: resolvedAvatar))

        if shouldForceRight {
            sideSequenceCursor = 0
            lastSender = nil
        } else if !shouldCarry {
            if !sender.isRight { nextLeftAvatarCursor += 1 }
            sideSequenceCursor += 1
            lastSender = sender
        } else {
            lastSender = sender
        }
    }
    return messages
}

// MARK: - 揭示计划（cappellaReveal.ts + cappellaBubbleMetrics.ts）

private struct CappellaRevealPlan {
    var characters: [String]
    var revealTimes: [TimeInterval]
    var fadeDurationsMs: [Double]
    /// sizes[n] = 显示前 n 字时的气泡尺寸（已含内边距与边框）。
    var sizes: [CGSize]
    var timestampReadyTime: TimeInterval
}

/// 二分计数（getCharacterCountAtTime）：revealTimes 单调，
/// 返回 ≤ currentTime 的个数。
private func cappellaCountAtTime(_ times: [TimeInterval], _ t: TimeInterval) -> Int {
    var low = 0
    var high = times.count
    while low < high {
        let mid = (low + high) / 2
        if times[mid] <= t { low = mid + 1 } else { high = mid }
    }
    return low
}

// MARK: - 单条消息行视图

private final class CappellaRowView: UIView {
    let model: CappellaMessageModel
    let groupView = UIView()
    let avatarView = UIView()
    /// 宫格渐变层（网页 CappellaAvatar 无图时的 linear-
    /// gradient(135deg, primary, accent)：尺寸 300%、按格
    /// 偏移，getAvatarPosition 口径）。
    let avatarGradient = CAGradientLayer()
    /// 封面宫格裁切图（cover 档；格图由渲染器裁好下发）。
    let coverImageView = UIImageView()
    let shadowView = UIView()
    let bubbleView = UIView()
    let bubbleLabel = UILabel()
    let glowView = UIView()
    let glowLayer = CAGradientLayer()
    let timestampLabel = UILabel()
    private let bubbleMask = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    var bubbleSize: CGSize = .zero
    var bubblePaddingX: CGFloat = CappellaConst.inactivePaddingX
    var bubblePaddingY: CGFloat = CappellaConst.inactivePaddingY
    var scaleOverflow: CGFloat = 0
    var isTimestampShown = false
    var lastRevealKey = ""
    var lastGlowWidth: CGFloat = 0
    var appliedState: Int = -1

    init(model: CappellaMessageModel) {
        self.model = model
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        groupView.isUserInteractionEnabled = false
        // 缩放原点 = 底部发送者侧（网页 transformOrigin
        // 右 100% 100% / 左 0% 100%）。
        groupView.layer.anchorPoint = CGPoint(x: model.isRight ? 1 : 0, y: 1)
        addSubview(groupView)

        avatarView.layer.cornerRadius = CappellaConst.avatarSize / 2
        avatarView.layer.borderWidth = 1
        avatarView.layer.borderColor =
            UIColor.white.withAlphaComponent(0.24).cgColor
        avatarView.clipsToBounds = true
        // 宫格几何（getAvatarPosition）：backgroundSize 300%
        // → 层尺寸 120×120；backgroundPosition col×50% /
        // row×50% 的 CSS 百分比公式 offset = (容器 − 图) × p
        // = −40×col / −40×row。
        let gridIndex = ((model.resolvedAvatarIndex % 9) + 9) % 9
        let gridCol = gridIndex % CappellaConst.avatarGridSize
        let gridRow = gridIndex / CappellaConst.avatarGridSize
        avatarGradient.frame = CGRect(
            x: CGFloat(-gridCol * 40), y: CGFloat(-gridRow * 40),
            width: CappellaConst.avatarSize * 3,
            height: CappellaConst.avatarSize * 3)
        avatarGradient.startPoint = CGPoint(x: 0, y: 0)
        avatarGradient.endPoint = CGPoint(x: 1, y: 1) // 135deg
        avatarView.layer.addSublayer(avatarGradient)
        coverImageView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: CappellaConst.avatarSize,
                         height: CappellaConst.avatarSize))
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.isHidden = true
        avatarView.addSubview(coverImageView)
        groupView.addSubview(avatarView)

        shadowView.isUserInteractionEnabled = false
        groupView.addSubview(shadowView)
        bubbleView.layer.mask = bubbleMask
        bubbleLabel.numberOfLines = 0
        bubbleLabel.lineBreakMode = .byWordWrapping
        glowView.isUserInteractionEnabled = false
        glowView.layer.addSublayer(glowLayer)
        // 105deg 宽扫光以水平渐近似：两段相同的扫光带并排，
        // 平移 −50% 无缝循环（网页 gradient 停靠点照搬）。
        glowLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            UIColor.white.cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
        ]
        glowLayer.locations = [0, 0.23, 0.34, 0.5, 0.73, 0.84, 1]
        glowLayer.startPoint = CGPoint(x: 0, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 0.5)
        bubbleView.addSubview(glowView)
        bubbleView.addSubview(bubbleLabel)
        groupView.addSubview(bubbleView)
        groupView.layer.addSublayer(borderLayer)
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = CappellaConst.bubbleBorderWidth

        timestampLabel.font = .systemFont(
            ofSize: CappellaConst.timestampFontSize, weight: .medium)
        timestampLabel.alpha = 0
        groupView.addSubview(timestampLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var contentHeight: CGFloat { max(bubbleSize.height, CappellaConst.avatarSize) }
    var rowHeight: CGFloat { scaleOverflow + contentHeight }

    /// 按当前气泡尺寸刷新遮罩/描边/子视图几何（气泡圆角 24，
    /// 靠发送者侧底角 6）。
    func refreshBubbleGeometry() {
        let rect = CGRect(origin: .zero, size: bubbleSize)
        let r = CappellaConst.bubbleRadius
        let tail = CappellaConst.bubbleTailRadius
        let path = Self.roundedPath(
            rect: rect,
            topLeft: r, topRight: r,
            bottomRight: model.isRight ? tail : r,
            bottomLeft: model.isRight ? r : tail)
        bubbleMask.path = path.cgPath
        bubbleMask.frame = rect
        borderLayer.path = path.cgPath
        shadowView.layer.shadowPath = path.cgPath
    }

    /// 边框层挂在组层上，帧须与气泡帧对齐（由渲染器布局时调用）。
    func layoutBorderAndShadow(bubbleFrame: CGRect) {
        borderLayer.frame = bubbleFrame
        shadowView.frame = bubbleFrame
    }

    private static func roundedPath(rect: CGRect, topLeft: CGFloat,
                                    topRight: CGFloat, bottomRight: CGFloat,
                                    bottomLeft: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        path.move(to: CGPoint(x: minX + topLeft, y: minY))
        path.addLine(to: CGPoint(x: maxX - topRight, y: minY))
        path.addArc(withCenter: CGPoint(x: maxX - topRight, y: minY + topRight),
                    radius: topRight, startAngle: -.pi / 2, endAngle: 0,
                    clockwise: true)
        path.addLine(to: CGPoint(x: maxX, y: maxY - bottomRight))
        path.addArc(withCenter: CGPoint(x: maxX - bottomRight, y: maxY - bottomRight),
                    radius: bottomRight, startAngle: 0, endAngle: .pi / 2,
                    clockwise: true)
        path.addLine(to: CGPoint(x: minX + bottomLeft, y: maxY))
        path.addArc(withCenter: CGPoint(x: minX + bottomLeft, y: maxY - bottomLeft),
                    radius: bottomLeft, startAngle: .pi / 2, endAngle: .pi,
                    clockwise: true)
        path.addLine(to: CGPoint(x: minX, y: minY + topLeft))
        path.addArc(withCenter: CGPoint(x: minX + topLeft, y: minY + topLeft),
                    radius: topLeft, startAngle: .pi, endAngle: .pi * 1.5,
                    clockwise: true)
        path.close()
        return path
    }

    func setColors(background: UIColor, border: UIColor, text: UIColor,
                   secondary: UIColor, gradientStart: UIColor,
                   gradientEnd: UIColor) {
        bubbleView.backgroundColor = background
        borderLayer.strokeColor = border.cgColor
        bubbleLabel.textColor = text
        // 网页 CappellaAvatar 底色 = theme.secondaryColor，
        // 其上叠宫格渐变（primary → accent）。
        avatarView.backgroundColor = secondary
        avatarGradient.colors = [gradientStart.cgColor, gradientEnd.cgColor]
        timestampLabel.textColor = secondary
    }

    /// 封面宫格格图（cover 档且封面已到货时非 nil）：显示
    /// 格图、藏渐变；nil 回退宫格渐变（网页无图分支同形）。
    func setCoverImage(_ image: UIImage?) {
        coverImageView.image = image
        coverImageView.isHidden = image == nil
        avatarGradient.isHidden = image != nil
    }

    func setGlowAlpha(_ alpha: CGFloat) {
        let color = UIColor.white.withAlphaComponent(alpha).cgColor
        glowLayer.colors = [
            UIColor.clear.cgColor, color, UIColor.clear.cgColor,
            UIColor.clear.cgColor, color, UIColor.clear.cgColor,
            UIColor.clear.cgColor,
        ]
    }

    func startGlow() {
        guard glowView.layer.animation(forKey: "cappella.glowPan") == nil
        else { return }
        let width = max(bubbleSize.width, 1)
        lastGlowWidth = width
        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = 0
        anim.toValue = -width
        anim.duration = CappellaConst.glowDuration
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isRemovedOnCompletion = false
        glowView.layer.add(anim, forKey: "cappella.glowPan")
    }

    func stopGlow() {
        glowView.layer.removeAnimation(forKey: "cappella.glowPan")
    }

    func setTimestampVisible(_ visible: Bool, animated: Bool) {
        guard visible != isTimestampShown else { return }
        isTimestampShown = visible
        let target: CGFloat = visible ? CappellaConst.timestampOpacity : 0
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0,
                           options: [.curveEaseOut]) {
                self.timestampLabel.alpha = target
            }
        } else {
            timestampLabel.alpha = target
        }
    }
}

// MARK: - 渲染器

final class CappellaStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    private let contentView = UIView()
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false
    /// chrome 占用（3.7 (60) 第 4 条）：宿主 layoutStage 下发；
    /// 消息面板构图重心在下部，面板按 bottom inset 的一半上移
    /// 避让点播台浮压。变更时重跑 performLayout。
    private var chromeInsets: UIEdgeInsets = .zero

    private var messages: [CappellaMessageModel] = []
    private var rows: [String: CappellaRowView] = [:]
    private var orderedRowIds: [String] = []
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var builtTitle: String? = nil

    /// 调参指纹与封面头像状态（(57) C2）：封面经宿主
    /// NativeCoverLoader 取图（与 Monet 同管线），按宫格
    /// 裁切后下发各行；裁切缓存按 resolvedAvatarIndex 存。
    private var appliedTuning: CappellaTuningValues? = nil
    private var coverTask: Task<Void, Never>? = nil
    private var coverImage: UIImage? = nil
    private var coverTrackId: String? = nil
    private var coverCrops: [Int: UIImage] = [:]

    /// 揭示计划缓存（键 = 行 id；LRU 上限 CAPPELLA_LAYOUT_CACHE_LIMIT 32）。
    private var planCache: [Int: CappellaRevealPlan] = [:]
    private var planCacheOrder: [Int] = []
    private var preheatedLineId: Int? = nil

    private var lastPosition: TimeInterval? = nil
    private var lastVisibleKey = ""
    private var lastActiveLineIndex: Int? = nil
    /// 可见窗口备忘：窗口只随当前行/视口变化，避免逐帧重测全部行。
    private var windowMemoKey = ""
    private var windowMemo: [CappellaMessageModel] = []

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        rootView.addSubview(contentView)
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    /// chrome 内缩（3.7 (60) 第 4 条）：bottom inset 变化即重排
    /// 面板（performLayout 按 bottom/2 上移 contentView）。
    func applyChromeInsets(_ insets: UIEdgeInsets) {
        guard insets != chromeInsets else { return }
        chromeInsets = insets
        performLayout()
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        // (61) WC：入口统一过对比钳制——下游 palette.* 全走保护副本。
        var snapshot = snapshot
        snapshot.palette = snapshot.palette.contrastProtected()
        self.snapshot = snapshot
        let title = snapshot.track?.title ?? ""
        if snapshot.track?.id != builtTrackId
            || snapshot.lines.count != builtLineCount
            || title != builtTitle {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            builtTitle = title
            messages = buildCappellaMessages(
                lines: snapshot.lines,
                titleText: title.isEmpty ? "No Track" : title)
            planCache.removeAll()
            planCacheOrder.removeAll()
            preheatedLineId = nil
            lastVisibleKey = ""
            windowMemoKey = ""
            windowMemo = []
            lastActiveLineIndex = nil
        }
        // 调色板变化时重着色（行对象保留，仅换色）。
        for row in rows.values { applyColors(to: row) }
        syncTuningAndCover()
        rootView.setNeedsLayout()
    }

    // MARK: 调参与封面头像（(57) C2）

    private func currentTuning() -> CappellaTuningValues {
        CappellaTuningStore.valuesCached(now: CACurrentMediaTime())
    }

    /// 调参同步：avatarSource 为 cover 时确保封面在途/已
    /// 到货；调参变化时全体行重贴头像形态。showEmoMessages
    /// 在此只读不消费——表情池为空时网页同样压掉表情消息
    ///（见文件头注），开关待图包通道接入后生效。
    private func syncTuningAndCover() {
        let tuning = currentTuning()
        let changed = appliedTuning != tuning
        appliedTuning = tuning
        _ = tuning.showEmoMessages // 门已读：池空恒无 emo（头注）
        if tuning.avatarSource == .cover {
            loadCoverIfNeeded()
        }
        if changed {
            for row in rows.values { applyAvatar(to: row) }
        }
    }

    private func applyAvatar(to row: CappellaRowView) {
        if currentTuning().avatarSource == .cover,
           let cell = coverCellImage(for: row.model.resolvedAvatarIndex) {
            row.setCoverImage(cell)
        } else {
            row.setCoverImage(nil)
        }
    }

    private func loadCoverIfNeeded() {
        guard let raw = snapshot?.track?.artworkURL, !raw.isEmpty else {
            coverTask?.cancel()
            coverImage = nil
            coverTrackId = nil
            coverCrops.removeAll()
            return
        }
        let tid = snapshot?.track?.id
        if coverTrackId == tid && coverImage != nil { return }
        coverTask?.cancel()
        coverTrackId = tid
        coverImage = nil
        coverCrops.removeAll()
        if let cached = NativeCoverLoader.shared.cachedImageAnyTier(
            raw: raw, excludingTier: 512) {
            storeCoverImage(cached)
        }
        let urlString = NativeCoverLoader.shared.proxiedURLString(
            raw, tier: 512) ?? raw
        coverTask = Task { [weak self] in
            let image = await NativeCoverLoader.shared.image(
                for: urlString, tier: 512)
            await MainActor.run { [weak self] in
                guard let self, self.coverTrackId == tid,
                      let image else { return }
                self.storeCoverImage(image)
            }
        }
    }

    private func storeCoverImage(_ image: UIImage) {
        coverImage = image
        coverCrops.removeAll()
        for row in rows.values { applyAvatar(to: row) }
    }

    /// 宫格格图：封面 aspect-fill 到 120×120 画布（网页
    /// backgroundSize 300%）后裁出 index 所在 40×40 格。
    private func coverCellImage(for index: Int) -> UIImage? {
        if let cached = coverCrops[index] { return cached }
        guard let image = coverImage else { return nil }
        let grid = ((index % 9) + 9) % 9
        let col = grid % CappellaConst.avatarGridSize
        let rowIdx = grid / CappellaConst.avatarGridSize
        let canvas = CGSize(width: 120, height: 120)
        let filled = UIGraphicsImageRenderer(size: canvas).image { _ in
            let scale = max(canvas.width / image.size.width,
                            canvas.height / image.size.height)
            let w = image.size.width * scale
            let h = image.size.height * scale
            image.draw(in: CGRect(x: (canvas.width - w) / 2,
                                  y: (canvas.height - h) / 2,
                                  width: w, height: h))
        }
        guard let cg = filled.cgImage else { return nil }
        let s = filled.scale
        let cell: CGFloat = 40
        let rect = CGRect(x: CGFloat(col) * cell * s,
                          y: CGFloat(rowIdx) * cell * s,
                          width: cell * s, height: cell * s)
        guard let cropped = cg.cropping(to: rect) else { return nil }
        let result = UIImage(cgImage: cropped, scale: s, orientation: .up)
        coverCrops[index] = result
        return result
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if !isActive {
            for row in rows.values { row.stopGlow() }
        } else {
            // 恢复 active 时重启当前行扫光（glowView.alpha > 0 仅 active 行）。
            for row in rows.values where row.glowView.alpha > 0 {
                row.startGlow()
            }
        }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let snapped = lastPosition.map { abs(position - $0) > 2.0 } ?? false
        lastPosition = position

        let lines = snapshot.lines
        // 当前行 / 可见行（getVisibleLineIndexAtTime）：最后一个
        // start ≤ position 的行，无则 −1。
        var currentLineIndex = -1
        for (index, line) in lines.enumerated() {
            if line.start <= position { currentLineIndex = index } else { break }
        }

        preheatIfNeeded(lines: lines, currentLineIndex: currentLineIndex,
                        position: position)

        let visible = visibleMessages(currentLineIndex: currentLineIndex,
                                      viewportHeight: viewportSize().height)
        let visibleIds = visible.map { $0.id }
        let activeChanged = currentLineIndex != lastActiveLineIndex

        // 揭示进度键：active 行的目标/可见字数变化也要触发刷新。
        var revealKey = ""
        if currentLineIndex >= 0, lines.indices.contains(currentLineIndex) {
            let line = lines[currentLineIndex]
            let plan = revealPlan(for: line)
            let target = cappellaCountAtTime(
                plan.revealTimes.map { $0 - CappellaConst.widthLookahead }, position)
            let shown = cappellaCountAtTime(plan.revealTimes, position)
            // 淡入进度键：末字淡入未完时字数不变也要继续刷新。
            var fadeBucket = 0
            if shown > 0 {
                let i = shown - 1
                let fade = max(plan.fadeDurationsMs[i] / 1000, 0.001)
                let raw = (position - plan.revealTimes[i]) / fade
                fadeBucket = Int(max(0, min(1, raw)) * 20)
            }
            revealKey = "\(target)/\(shown)/\(fadeBucket)"
        }
        let windowKey = visibleIds.joined(separator: ",")
            + "|\(currentLineIndex)|\(revealKey)"
        let windowChanged = windowKey != lastVisibleKey
        guard windowChanged || activeChanged else {
            updateTimestamps(position: position)
            return
        }
        lastVisibleKey = windowKey
        lastActiveLineIndex = currentLineIndex

        syncRows(visible: visible, currentLineIndex: currentLineIndex,
                 position: position, snapped: snapped)
        updateActiveReveal(position: position)
        updateTimestamps(position: position)
        relayout(animated: !snapped)
    }

    func unmount() {
        isActive = false
        coverTask?.cancel()
        coverTask = nil
        for row in rows.values {
            row.stopGlow()
            row.removeFromSuperview()
        }
        rows.removeAll()
        orderedRowIds.removeAll()
        planCache.removeAll()
        planCacheOrder.removeAll()
        context = nil
        snapshot = nil
        lastPosition = nil
    }

    // MARK: 几何参数（VisualizerCappella.tsx）

    private func viewportSize() -> CGSize {
        snapshot?.viewport.size ?? rootView.bounds.size
    }

    /// baseFontSize = clamp(15, 26, 18 × lyricsFontScale)；
    /// 原生 fontScale 取快照 dynamicTypeScale（本期恒 1）。
    private func baseFontSize() -> CGFloat {
        let scale = snapshot?.viewport.dynamicTypeScale ?? 1
        return max(15, min(26, 18 * scale))
    }

    private func sidePadding() -> CGFloat {
        let w = viewportSize().width
        if w >= 1024 { return 56 } // lg:px-14
        if w >= 640 { return 32 } // sm:px-8
        return 16 // px-4
    }

    private func topPadding() -> CGFloat {
        let w = viewportSize().width
        if w >= 1024 { return 80 } // lg:pt-20
        if w >= 640 { return 64 } // sm:pt-16
        return 48 // pt-12
    }

    private func panelWidth() -> CGFloat {
        let w = viewportSize().width
        return max(min(w - sidePadding() * 2, 896), 0) // max-w-4xl
    }

    /// maxTextWidth = max(96, floor(min(max(vw−32,1),896) × ratio − 56))，
    /// ratio = vw ≥ 640 ? 0.68 : 0.78。
    private func maxTextWidth() -> CGFloat {
        let vw = viewportSize().width
        let maxPanelWidth = min(max(vw - 32, 1), 896)
        let ratio: CGFloat = vw >= 640 ? 0.68 : 0.78
        return max(96, floor(maxPanelWidth * ratio - 56))
    }

    private func groupMaxWidth() -> CGFloat {
        let vw = viewportSize().width
        let ratio: CGFloat = vw >= 640 ? 0.68 : 0.78
        return panelWidth() * ratio
    }

    private func textFont(size: CGFloat) -> UIFont {
        // 网页主题 serif 栈 + 字重 400（CAPPELLA_BUBBLE_FONT_WEIGHT）。
        UIFont(name: "STSongti-SC-Regular", size: size)
            ?? .systemFont(ofSize: size, weight: .regular)
    }

    // MARK: 文本测量（cappellaBubbleMetrics.ts measureBubbleText 的
    // TextKit 近似：pretext 的逐行宽/行数由 boundingRect 给出）

    private func measureText(text: String, fontSize: CGFloat,
                             lineHeight: CGFloat)
        -> (width: CGFloat, height: CGFloat) {
        let font = textFont(size: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .paragraphStyle: paragraph,
        ]
        let safe = text.isEmpty ? " " : text
        let rect = (safe as NSString).boundingRect(
            with: CGSize(width: maxTextWidth(),
                         height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes, context: nil)
        let lineCount = max(1, Int((rect.height / lineHeight).rounded()))
        let width = max(ceil(rect.width), fontSize)
        return (width, CGFloat(lineCount) * lineHeight)
    }

    /// 气泡尺寸：宽 = ceil(min(文本宽, maxTextWidth)) + padX×2 + 2，
    /// 高 = ceil(文本高 + padY×2 + 2)，再套 minHeight/minWidth 与
    /// 群组宽上限（头像 40 + 间隔 12 之外）。
    private func bubbleSize(text: String, fontSize: CGFloat,
                            paddingX: CGFloat, paddingY: CGFloat,
                            isActiveState: Bool) -> CGSize {
        let lineHeight = fontSize * 1.45
        let measured = measureText(text: text, fontSize: fontSize,
                                   lineHeight: lineHeight)
        var width = ceil(min(measured.width, maxTextWidth()))
            + paddingX * 2 + CappellaConst.bubbleBorderWidth * 2
        var height = ceil(measured.height + paddingY * 2
            + CappellaConst.bubbleBorderWidth * 2)
        let minHeight = max(
            isActiveState ? CappellaConst.activeMinHeight
                : CappellaConst.inactiveMinHeight,
            lineHeight + paddingY * 2)
        height = max(height, minHeight)
        if isActiveState { width = max(width, CappellaConst.activeMinWidth) }
        let cap = groupMaxWidth() - CappellaConst.avatarSize - CappellaConst.rowGap
        width = min(width, max(cap, CappellaConst.activeMinWidth))
        return CGSize(width: width, height: height)
    }

    // MARK: 揭示计划构建与缓存

    private func revealPlan(for line: LyricLine) -> CappellaRevealPlan {
        if let cached = planCache[line.id] {
            planCacheOrder.removeAll { $0 == line.id }
            planCacheOrder.append(line.id)
            return cached
        }
        let plan = buildRevealPlan(for: line)
        planCache[line.id] = plan
        planCacheOrder.append(line.id)
        while planCacheOrder.count > CappellaConst.layoutCacheLimit {
            let evicted = planCacheOrder.removeFirst()
            planCache.removeValue(forKey: evicted)
        }
        return plan
    }

    /// 逐字时刻：以 StageLyricUnits 单元时序为桥（协议 words 恒
    /// nil 时单元即整行字素均分，与网页 even 口径一致）；单元间
    /// 空白随下一单元时刻出现、淡入 40ms；尾部残字挂最后时刻。
    private func buildRevealPlan(for line: LyricLine) -> CappellaRevealPlan {
        let characters = line.text.map { String($0) }
        let count = characters.count
        var revealTimes = [TimeInterval](repeating: line.end, count: count)
        var fadeMs = [Double](repeating: CappellaConst.defaultCharFadeMs,
                              count: count)
        if count > 0 {
            let units = StageLyricUnits.units(for: line)
            var cursor = 0
            var lastResolved = line.start
            for unit in units {
                let unitChars = Array(unit.text)
                guard !unitChars.isEmpty else { continue }
                var startIndex = cursor
                while startIndex < count
                        && (characters[startIndex] == " "
                            || characters[startIndex] == "\t"
                            || characters[startIndex] == "　") {
                    revealTimes[startIndex] = unit.start
                    // 淡入 40ms 与网页一致（已复核：
                    // buildCharacterFadeDurationsMs 走
                    // buildLineGraphemeTimeline 路径，间隙字
                    // 素时刻为零时长 → 淡入取下限 MIN 40ms；
                    // 缺省 220 只出现在该路径不成立的兜底
                    // 分支，本数据形态下不触发）。
                    fadeMs[startIndex] = CappellaConst.minCharFadeMs
                    startIndex += 1
                }
                let segment = (unit.end - unit.start) / Double(unitChars.count)
                for k in unitChars.indices {
                    let idx = startIndex + k
                    guard idx < count else { break }
                    revealTimes[idx] = unit.start + segment * Double(k)
                    fadeMs[idx] = max(segment * 1000, CappellaConst.minCharFadeMs)
                    lastResolved = max(lastResolved, revealTimes[idx])
                }
                cursor = startIndex + unitChars.count
            }
            if cursor < count {
                for idx in cursor..<count {
                    revealTimes[idx] = lastResolved
                    // 尾部字素同间隙字素：零时长 → 淡入下限
                    // 40ms（网页 lineTimeline 路径同值）。
                    fadeMs[idx] = CappellaConst.minCharFadeMs
                }
            }
        }

        // 气泡尺寸表：每个前缀各测一次（active 字号/内边距）。
        let fontSize = baseFontSize() * CappellaConst.activeFontMultiplier
        var sizes: [CGSize] = []
        sizes.reserveCapacity(count + 1)
        for visibleCount in 0...count {
            let prefix = characters.prefix(visibleCount).joined()
            sizes.append(bubbleSize(
                text: prefix, fontSize: fontSize,
                paddingX: CappellaConst.activePaddingX,
                paddingY: CappellaConst.activePaddingY,
                isActiveState: true))
        }

        var ready = line.start
        for idx in characters.indices where revealTimes[idx].isFinite {
            ready = max(ready, revealTimes[idx] + fadeMs[idx] / 1000)
        }
        if characters.isEmpty { ready = line.end }
        return CappellaRevealPlan(characters: characters,
                                  revealTimes: revealTimes,
                                  fadeDurationsMs: fadeMs,
                                  sizes: sizes,
                                  timestampReadyTime: ready)
    }

    /// 预热（CAPPELLA_PREHEAT_WINDOW：minLead 0.18 / maxLead
    /// 1.1）：下一行进入窗口时提前建其揭示计划，播放只查表。
    private func preheatIfNeeded(lines: [LyricLine], currentLineIndex: Int,
                                 position: TimeInterval) {
        let nextIndex = currentLineIndex + 1
        guard lines.indices.contains(nextIndex) else { return }
        let next = lines[nextIndex]
        let lead = next.start - position
        guard lead > 0.18 && lead <= CappellaConst.preheatMaxLead else { return }
        guard preheatedLineId != next.id else { return }
        preheatedLineId = next.id
        _ = revealPlan(for: next)
    }

    // MARK: 可见窗口（getVisibleMessages）

    private func visibleMessages(currentLineIndex: Int,
                                 viewportHeight: CGFloat) -> [CappellaMessageModel] {
        let memoKey = "\(currentLineIndex)|\(Int(viewportHeight))|\(Int(panelWidth()))"
        if memoKey == windowMemoKey { return windowMemo }
        let result = computeVisibleMessages(currentLineIndex: currentLineIndex,
                                            viewportHeight: viewportHeight)
        windowMemoKey = memoKey
        windowMemo = result
        return result
    }

    private func computeVisibleMessages(currentLineIndex: Int,
                                        viewportHeight: CGFloat) -> [CappellaMessageModel] {
        let filtered = messages.filter {
            $0.kind == .title || $0.lineIndex <= currentLineIndex
        }
        let usableHeight = max(200, viewportHeight - 240)
        var accumulated: CGFloat = 0
        var result: [CappellaMessageModel] = []
        for model in filtered.reversed() {
            let isActiveMsg = model.kind == .lyric
                && model.lineIndex == currentLineIndex
            let est = estimatedHeight(of: model, isActive: isActiveMsg)
            if accumulated + est > usableHeight && result.count >= 2 { break }
            accumulated += est
            result.insert(model, at: 0)
            if result.count >= CappellaConst.maxVisibleMessages { break }
        }
        return result
    }

    private func estimatedHeight(of model: CappellaMessageModel,
                                 isActive: Bool) -> CGFloat {
        let text = model.kind == .title ? model.titleText : (model.line?.text ?? "")
        let fontSize: CGFloat
        if model.kind == .title {
            fontSize = baseFontSize()
        } else {
            fontSize = baseFontSize() * (isActive
                ? CappellaConst.activeFontMultiplier
                : CappellaConst.inactiveFontMultiplier)
        }
        let size = bubbleSize(
            text: text, fontSize: fontSize,
            paddingX: isActive ? CappellaConst.activePaddingX
                : CappellaConst.inactivePaddingX,
            paddingY: isActive ? CappellaConst.activePaddingY
                : CappellaConst.inactivePaddingY,
            isActiveState: isActive)
        var overflow: CGFloat = 0
        if isActive && CappellaConst.activeScale > 1 {
            overflow = ceil(size.height * (CappellaConst.activeScale - 1))
        }
        return size.height + overflow + CappellaConst.rowGap
    }

    // MARK: 行同步与状态

    private func rowState(of model: CappellaMessageModel,
                          currentLineIndex: Int) -> Int {
        // 0 = 普通（标题/未唱）, 1 = active, 2 = passed
        guard model.kind == .lyric else { return 0 }
        if model.lineIndex == currentLineIndex { return 1 }
        if model.lineIndex < currentLineIndex { return 2 }
        return 0
    }

    private func syncRows(visible: [CappellaMessageModel],
                          currentLineIndex: Int,
                          position: TimeInterval, snapped: Bool) {
        let visibleIdSet = Set(visible.map { $0.id })
        // 离窗行：出场动画（y −18 / scale 0.965 / 0.24s easeIn）
        // 后移除；布局立即按新窗口计算（popLayout 口径）。
        for id in Array(rows.keys) where !visibleIdSet.contains(id) {
            guard let row = rows.removeValue(forKey: id) else { continue }
            row.stopGlow()
            if snapped {
                row.removeFromSuperview()
            } else {
                UIView.animate(withDuration: CappellaConst.rowExitDuration,
                               delay: 0, options: [.curveEaseIn]) {
                    row.alpha = 0
                    row.transform = CGAffineTransform(
                        translationX: 0, y: CappellaConst.rowExitY)
                        .scaledBy(x: CappellaConst.rowExitScale,
                                  y: CappellaConst.rowExitScale)
                } completion: { _ in row.removeFromSuperview() }
            }
        }
        orderedRowIds = visible.map { $0.id }
        for model in visible {
            let state = rowState(of: model, currentLineIndex: currentLineIndex)
            if let row = rows[model.id] {
                // 状态未变不重复迁移（揭示步进只走 updateActiveReveal）。
                if row.appliedState != state {
                    applyState(to: row, state: state, animated: !snapped)
                    row.appliedState = state
                }
            } else {
                let row = CappellaRowView(model: model)
                applyColors(to: row)
                applyAvatar(to: row)
                applyState(to: row, state: state, animated: false)
                row.appliedState = state
                rows[model.id] = row
                contentView.addSubview(row)
                if !snapped {
                    row.alpha = 0
                    row.transform = CGAffineTransform(
                        translationX: 0, y: CappellaConst.rowEnterY)
                        .scaledBy(x: CappellaConst.rowEnterScale,
                                  y: CappellaConst.rowEnterScale)
                    UIView.animate(withDuration: CappellaConst.rowEnterDuration,
                                   delay: 0, options: [.curveEaseOut]) {
                        row.alpha = 1
                        row.transform = .identity
                    }
                }
                // 中途进台落位：active 行直接摆到当前揭示进度。
                if state == 1 { updateActiveReveal(position: position) }
            }
        }
    }

    /// 状态迁移：字号/内边距/最小高随 active 切换；组缩放与
    /// 不透明度走头像弹簧（阻尼比 0.895 近似）。
    private func applyState(to row: CappellaRowView, state: Int,
                            animated: Bool) {
        let model = row.model
        let isActiveState = state == 1
        let isPassed = state == 2
        let fontSize: CGFloat
        if model.kind == .title {
            fontSize = baseFontSize()
        } else {
            fontSize = baseFontSize() * (isActiveState
                ? CappellaConst.activeFontMultiplier
                : CappellaConst.inactiveFontMultiplier)
        }
        let paddingX = isActiveState ? CappellaConst.activePaddingX
            : CappellaConst.inactivePaddingX
        let paddingY = isActiveState ? CappellaConst.activePaddingY
            : CappellaConst.inactivePaddingY
        row.bubbleLabel.font = textFont(size: fontSize)
        row.bubblePaddingX = paddingX
        row.bubblePaddingY = paddingY
        let text = model.kind == .title ? model.titleText : (model.line?.text ?? "")
        if isActiveState, let line = model.line {
            let plan = revealPlan(for: line)
            row.bubbleSize = plan.sizes.last ?? bubbleSize(
                text: text, fontSize: fontSize, paddingX: paddingX,
                paddingY: paddingY, isActiveState: true)
        } else {
            row.bubbleSize = bubbleSize(
                text: text, fontSize: fontSize, paddingX: paddingX,
                paddingY: paddingY, isActiveState: isActiveState)
        }
        row.scaleOverflow = isActiveState
            ? ceil(max(row.bubbleSize.height, 40)
                * (CappellaConst.activeScale - 1)) : 0

        let scale: CGFloat = isActiveState ? CappellaConst.activeScale
            : (isPassed ? CappellaConst.passedScale : 1)
        let opacity: CGFloat = isPassed ? CappellaConst.passedOpacity : 1
        let apply = {
            row.groupView.transform = CGAffineTransform(scaleX: scale, y: scale)
            row.groupView.alpha = opacity
        }
        if animated {
            UIView.animate(withDuration: CappellaConst.groupSpringDuration,
                           delay: 0,
                           usingSpringWithDamping: CappellaConst.groupSpringDamping,
                           initialSpringVelocity: 0,
                           options: [.beginFromCurrentState], animations: apply)
        } else { apply() }

        // 阴影与 glow 只属 active（网页 boxShadow / CappellaBubbleGlow）。
        // 阴影挂独立影视图：气泡本体的 mask 会裁掉自身阴影。
        if isActiveState, let palette = snapshot?.palette {
            row.shadowView.layer.shadowColor = cappellaMix(
                palette.background, palette.accent, amount: 0.2,
                alpha: CappellaConst.activeShadowAlpha).cgColor
            row.shadowView.layer.shadowOffset = CGSize(width: 0, height: 18)
            row.shadowView.layer.shadowRadius = 24 // CSS blur 48 的近似
            row.shadowView.layer.shadowOpacity = 1
            row.setGlowAlpha(model.isRight ? CappellaConst.glowRightAlpha
                : CappellaConst.glowLeftAlpha)
            row.glowView.alpha = CappellaConst.glowOpacity
            if isActive { row.startGlow() }
        } else {
            row.shadowView.layer.shadowOpacity = 0
            row.glowView.alpha = 0
            row.stopGlow()
        }
        if !isActiveState {
            // 非 active 行显示全文（网页 CappellaText），段落行高
            // 与测量口径同为字号 ×1.45。
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.minimumLineHeight = fontSize * 1.45
            paragraph.maximumLineHeight = fontSize * 1.45
            row.bubbleLabel.attributedText = NSAttributedString(
                string: text,
                attributes: [.font: textFont(size: fontSize),
                             .paragraphStyle: paragraph])
            row.lastRevealKey = ""
        }
    }

    private func applyColors(to row: CappellaRowView) {
        guard let palette = snapshot?.palette else { return }
        let model = row.model
        let background: UIColor
        let border: UIColor
        let text: UIColor
        if model.isRight {
            background = cappellaMix(palette.accent, palette.primary, amount: 0.18,
                                     alpha: 0.94)
            border = cappellaMix(palette.accent, palette.primary, amount: 0.34,
                                 alpha: 0.30)
            text = palette.background
        } else {
            let tone = CGFloat(((model.avatarIndex % 9) + 9) % 9) / 8
            let accentMix = 0.18 + tone * 0.62
            background = cappellaMix(palette.secondary, palette.accent,
                                     amount: accentMix, alpha: 1)
            border = cappellaMix(palette.secondary, palette.accent,
                                 amount: min(accentMix + 0.18, 1), alpha: 0.26)
            text = palette.primary
        }
        row.setColors(background: background, border: border, text: text,
                      secondary: palette.secondary,
                      gradientStart: palette.primary,
                      gradientEnd: palette.accent)
    }

    // MARK: 揭示与时间戳

    private func updateActiveReveal(position: TimeInterval) {
        guard let idx = lastActiveLineIndex, idx >= 0 else { return }
        let id = "line-\(idx)"
        guard let row = rows[id], let line = row.model.line else { return }
        let plan = revealPlan(for: line)
        let targetCount = cappellaCountAtTime(
            plan.revealTimes.map { $0 - CappellaConst.widthLookahead }, position)
        let visibleCount = cappellaCountAtTime(plan.revealTimes, position)
        if targetCount >= 0 && targetCount < plan.sizes.count {
            let target = plan.sizes[targetCount]
            if target != row.bubbleSize {
                row.bubbleSize = target
                row.scaleOverflow = ceil(max(target.height, 40)
                    * (CappellaConst.activeScale - 1))
            }
        }
        // 逐字淡入：每字 alpha 按 (position − reveal) / fade 线性
        // 爬升（CSS cappella-char-fade ease-out 的逐帧等价），
        // alpha 量化到 0.05 步进以限制重建频率。
        var keyParts: [String] = ["\(visibleCount)"]
        var alphas: [CGFloat] = []
        for i in 0..<visibleCount {
            let fade = max(plan.fadeDurationsMs[i] / 1000, 0.001)
            let raw = (position - plan.revealTimes[i]) / fade
            let clamped = CGFloat(max(0, min(1, raw)))
            let quantized = (clamped * 20).rounded() / 20
            alphas.append(quantized)
            keyParts.append(String(Int(quantized * 20)))
        }
        let key = keyParts.joined(separator: ".")
        guard key != row.lastRevealKey else { return }
        row.lastRevealKey = key
        guard let palette = snapshot?.palette else { return }
        let textColor = row.model.isRight ? palette.background : palette.primary
        let font = row.bubbleLabel.font ?? textFont(size: baseFontSize())
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = font.pointSize * 1.45
        paragraph.maximumLineHeight = font.pointSize * 1.45
        let attributed = NSMutableAttributedString()
        for i in 0..<visibleCount {
            let alpha = i < alphas.count ? alphas[i] : 1
            attributed.append(NSAttributedString(
                string: plan.characters[i],
                attributes: [
                    .font: font,
                    .paragraphStyle: paragraph,
                    .foregroundColor: textColor.withAlphaComponent(alpha),
                ]))
        }
        row.bubbleLabel.attributedText = attributed
    }

    private func updateTimestamps(position: TimeInterval) {
        for id in orderedRowIds {
            guard let row = rows[id], let line = row.model.line else { continue }
            let state = rowState(of: row.model,
                                 currentLineIndex: lastActiveLineIndex ?? -1)
            let ready: TimeInterval
            if state == 1 {
                ready = revealPlan(for: line).timestampReadyTime
            } else {
                ready = line.end
            }
            row.setTimestampVisible(state == 2 || position >= ready,
                                    animated: true)
        }
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        let panelW = panelWidth()
        // (60) 第 4 条：面板上移 bottom chrome inset 的一半避让
        // 点播台浮压（全幅容器下 chrome 不再靠宿主带状容器避让）。
        contentView.frame = CGRect(
            x: (bounds.width - panelW) / 2, y: -chromeInsets.bottom / 2,
            width: panelW, height: bounds.height)
        lastVisibleKey = "" // 视口变化后下一帧按新几何重算窗口
        windowMemoKey = ""
        for row in rows.values { row.appliedState = -1 } // 几何变 → 状态重迁移重测尺寸
        relayout(animated: false)
    }

    private func relayout(animated: Bool) {
        let panelW = panelWidth()
        guard panelW > 0 else { return }
        var cursor = topPadding()
        for id in orderedRowIds {
            guard let row = rows[id] else { continue }
            let rowH = row.rowHeight
            let target = CGRect(x: 0, y: cursor, width: panelW, height: rowH)
            // 已落位行走 0.2s 帧动画（网页帧宽高动画口径）；入场
            // 变换进行中的行直接落帧，避免 frame/transform 冲突。
            if animated && row.transform == .identity {
                UIView.animate(withDuration: 0.2, delay: 0,
                               options: [.curveEaseOut, .beginFromCurrentState]) {
                    row.frame = target
                    self.layoutRow(row, panelWidth: panelW)
                }
            } else {
                row.frame = target
                layoutRow(row, panelWidth: panelW)
            }
            cursor += rowH + CappellaConst.rowGap
        }
    }

    private func layoutRow(_ row: CappellaRowView, panelWidth: CGFloat) {
        let model = row.model
        let groupW = CappellaConst.avatarSize + CappellaConst.rowGap
            + row.bubbleSize.width
        let groupH = row.contentHeight
        row.groupView.bounds = CGRect(x: 0, y: 0, width: groupW, height: groupH)
        row.groupView.layer.position = CGPoint(
            x: model.isRight ? panelWidth : 0,
            y: row.scaleOverflow + groupH)
        // 组内：头像与气泡底对齐（items-end），右侧行镜像。
        let bubbleX: CGFloat = model.isRight ? 0
            : CappellaConst.avatarSize + CappellaConst.rowGap
        let avatarX: CGFloat = model.isRight
            ? row.bubbleSize.width + CappellaConst.rowGap : 0
        row.avatarView.frame = CGRect(
            x: avatarX, y: groupH - CappellaConst.avatarSize,
            width: CappellaConst.avatarSize, height: CappellaConst.avatarSize)
        row.bubbleView.frame = CGRect(
            x: bubbleX, y: groupH - row.bubbleSize.height,
            width: row.bubbleSize.width, height: row.bubbleSize.height)
        row.refreshBubbleGeometry()
        row.layoutBorderAndShadow(bubbleFrame: row.bubbleView.frame)
        let paddingX = row.bubblePaddingX
        let paddingY = row.bubblePaddingY
        row.bubbleLabel.frame = CGRect(
            x: paddingX, y: paddingY,
            width: max(row.bubbleSize.width - paddingX * 2, 0),
            height: max(row.bubbleSize.height - paddingY * 2, 0))
        row.glowView.frame = CGRect(
            x: 0, y: 0, width: row.bubbleSize.width * 2,
            height: row.bubbleSize.height)
        row.glowLayer.frame = row.glowView.bounds
        // 气泡宽度变化时才重启扫光（平移距离 = 气泡宽），避免
        // 逐字增长时反复重置相位。
        if row.glowView.layer.animation(forKey: "cappella.glowPan") != nil
            && abs(row.bubbleSize.width - row.lastGlowWidth) > 0.5 {
            row.stopGlow()
            if isActive { row.startGlow() }
        }
        // 时间戳（CappellaTimestamp）：气泡外侧、底边上 4pt，
        // 文本为 formatTimestamp(line.end)。
        if let line = model.line {
            row.timestampLabel.text = Self.formatTimestamp(line.end)
            row.timestampLabel.sizeToFit()
            let labelW = row.timestampLabel.bounds.width
            let labelH = row.timestampLabel.bounds.height
            let bubbleFrame = row.bubbleView.frame
            let labelX = model.isRight
                ? bubbleFrame.minX - 8 - labelW
                : bubbleFrame.maxX + 8
            row.timestampLabel.frame = CGRect(
                x: labelX, y: bubbleFrame.maxY - 4 - labelH,
                width: labelW, height: labelH)
        }
    }

    /// formatTimestamp（cappellaMessageLayout.ts）：m:ss。
    private static func formatTimestamp(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let minutes = total / 60
        let rest = total % 60
        return "\(minutes):\(rest < 10 ? "0" : "")\(rest)"
    }
}
