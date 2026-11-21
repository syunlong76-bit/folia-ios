import UIKit
import QuartzCore
import CoreImage

// 汪汪队开大会 petconcert（3.7 (53) J）：演唱会渲染器。
//
// 中央大歌词隐藏：唱词呈现两代——(55) B 头顶跟随气泡
// 已被 (62) 胶囊歌词版取代（Miller 2026-11-21 验收 v2 样
// 片）：主胶囊固定背景带（当前行逐词扫光 + 下一行预览 +
// 物种爪印徽记），气泡只余仪式口令/闲聊/告别等非歌词言
// 语。(65) A 组按 v3b 定版再进一版：底部提词小胶囊整条
// 摘除（歌词只走主胶囊）、独唱麦改迷你口径（0.55×独唱
// 者身高、麦头胸口高）、前排整排换 cat-live 副本跳舞。
// 53 只全员上台：静帧 atlas（首帧缩到 ≤160px，≈5.4MB）
// + 动图池 ≤8 只 StickerView（解码成本实测准入、合计
// ≤40MB，见 PetConcertConst 红线）；前排副本的 cat-live
// 解码经 StickerStore 按名共享、全排一份、不占池预算。
// 素材优先级：StickersCutout 抠图版 > 原贴纸（本来就透明底）。
//
// 时钟纪律与全舞台一致：只消费宿主 frameTick 的锚点位置；所
// 有位置/相位/气泡都是 plan + position 的函数，seek 后自动
// 重建。降级顺序：先砍氛围（光束/纸屑/闪烁 → 动图池转静帧），
// 永不砍主胶囊与气泡（歌词可读性）。

// MARK: - 缓动（v3 easing 口径）

private func concertEaseOutQuad(_ u: Double) -> Double {
    let u = min(max(u, 0), 1)
    return 1 - (1 - u) * (1 - u)
}
private func concertEaseInOut(_ u: Double) -> Double {
    let u = min(max(u, 0), 1)
    return u * u * (3 - 2 * u)
}
private func concertEaseOutBack(_ u: Double, c1: Double = 1.70158) -> Double {
    let u = min(max(u, 0), 1)
    let c3 = c1 + 1
    return 1 + c3 * pow(u - 1, 3) + c1 * pow(u - 1, 2)
}
private func concertLerp(_ a: CGFloat, _ b: CGFloat, _ u: Double) -> CGFloat {
    a + (b - a) * CGFloat(u)
}
private func concertLerp(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
    CGPoint(x: concertLerp(a.x, b.x, u), y: concertLerp(a.y, b.y, u))
}
/// 二次贝塞尔（控制点 = 中点 + y −lift，v3 bez 口径）。
private func concertBezier(_ p0: CGPoint, _ p1: CGPoint,
                           lift: CGFloat, _ u: Double) -> CGPoint {
    let c = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 - lift)
    let v = 1 - u
    return CGPoint(
        x: CGFloat(v * v) * p0.x + 2 * CGFloat(v * u) * c.x + CGFloat(u * u) * p1.x,
        y: CGFloat(v * v) * p0.y + 2 * CGFloat(v * u) * c.y + CGFloat(u * u) * p1.y)
}

// MARK: - 气泡（奶油底 + 棕轮廓 + 下尾，v3 bubble 口径）

final class PetConcertBubbleView: UIView {
    private let shapeLayer = CAShapeLayer()
    private let label = UILabel()
    private(set) var currentKey = ""
    /// 尾尖相对本视图左缘的 x（随锚点宠物水平位置钳制）。
    private var tailX: CGFloat = 0
    /// 尾尖在舞台坐标（(55) B 前供引导线用；引导线已删，
    /// 字段保留供面包屑/后续调试，不再有绘制消费方）。
    private(set) var tailTipInParent: CGPoint?
    /// 跟随气泡去重（(55) B）：同 key + 同锚点 + 同舞台尺寸
    /// 时跳过重排，避免逐帧调用打断换人弹簧动画（独唱者在
    /// 演唱窗内位置恒定，锚点天然静止，去重不丢跟随）。
    private var lastFollowKey = ""
    private var lastFollowAnchor: CGPoint?
    private var lastFollowStageSize: CGSize = .zero

    // (54) P 整行气泡布局常量（参考 px，1080×1920 参考系）。
    /// 歌词字号下限：44 → 28（与原提词条字号下限同口径，
    /// 再小不可读）；步进 2 逐档试。
    static let lyricMinFontRef: CGFloat = 28
    /// 歌词最多 3 行换行。
    static let lyricMaxLines = 3
    /// 常规最大文本宽（参考 px）；放不下才走 wide 全宽兜底。
    static let lyricNormalMaxTextRefW: CGFloat = 600
    /// 通用气泡（口令/闲聊）字号下限。
    static let genericMinFontRef: CGFloat = 28
    /// 横屏常规最大文本宽（(54) U，1920 参考系）：横屏可用
    /// 宽大，常规档即放宽到 1050 参考 px（852pt 舞台上
    /// 466pt），整行全显更容易达成；字号下限/最多 3 行规则
    /// 与竖屏不变。
    static let lyricNormalMaxTextRefWL: CGFloat = 1050
    /// 跟随气泡与独唱者头顶的间隙（参考 px，(55) B）：气泡
    /// 尾尖落在头顶上方此距离处，尾长另计（apply 内 18sx）。
    static let lyricFollowGapRef: CGFloat = 10

    /// 朝向换算（(54) U）：按容器宽高比选参考系。
    private func scales(_ stageSize: CGSize)
        -> (sx: CGFloat, sy: CGFloat, landscape: Bool) {
        let land = PetConcertConst.isLandscape(stageSize)
        let rw = land ? PetConcertConst.refWL : PetConcertConst.refW
        let rh = land ? PetConcertConst.refHL : PetConcertConst.refH
        return (stageSize.width / rw, stageSize.height / rh, land)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        shapeLayer.fillColor = PetConcertPalette.bubbleFill.cgColor
        shapeLayer.strokeColor = PetConcertPalette.outline.cgColor
        layer.addSublayer(shapeLayer)
        // (61) WC：气泡字色过对比钳制（against 气泡填充色兜底）。
        label.textColor = StagePalette.contrastClamped(
            PetConcertPalette.bubbleText, against: PetConcertPalette.bubbleFill)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// 文本布局求解：自 baseFontRef 起以 2 为步进降字号，
    /// 返回首个行数 ≤ maxLines 的结果；全档用尽则返回下限
    /// 字号的实测结果（行数可超，调用方决定加宽/放行，
    /// 任何路径都不截断、不省略）。
    private func solve(text: String, baseFontRef: CGFloat,
                       minFontRef: CGFloat, maxTextW: CGFloat,
                       sx: CGFloat, maxLines: Int)
        -> (font: UIFont, fontRef: CGFloat, size: CGSize, lines: Int) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.alignment = .center
        var fontRef = baseFontRef
        var result: (UIFont, CGFloat, CGSize, Int)!
        while true {
            let font = UIFont.systemFont(ofSize: fontRef * sx, weight: .bold)
            let measured = (text as NSString).boundingRect(
                with: CGSize(width: maxTextW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: style],
                context: nil)
            let lines = max(1, Int(ceil(measured.height / font.lineHeight - 0.001)))
            result = (font, fontRef, measured.size, lines)
            if lines <= maxLines || fontRef <= minFontRef { break }
            fontRef = max(minFontRef, fontRef - 2)
        }
        return result
    }

    /// 落位与绘制（show/showFollowingSinger 共用）：按实测
    /// 尺寸定 bounds，中心由调用方给（已钳制），尾尖对
    /// anchorX。animateMove（(55) B，仅跟随气泡换 key 时）：
    /// 气泡已可见时中心不瞬移——先回旧中心，再以系统弹簧
    /// （0.5s / damping 0.78）移到新中心，移位与弹入缩放并行。
    private func apply(key: String, text: String,
                       solved: (font: UIFont, fontRef: CGFloat,
                                size: CGSize, lines: Int),
                       center: CGPoint, anchorX: CGFloat,
                       stageSize: CGSize, animateMove: Bool = false) {
        let sx = scales(stageSize).sx
        let padX: CGFloat = 26 * sx, padY: CGFloat = 15 * sx
        let tail: CGFloat = 18 * sx
        label.font = solved.font
        label.lineBreakMode = .byCharWrapping
        let bw = ceil(solved.size.width) + padX * 2 + 8
        let bh = ceil(solved.size.height) + padY * 2
        let totalH = bh + tail + 4
        let sizeChanged = abs(bounds.width - bw) > 0.5
            || abs(bounds.height - totalH) > 0.5
        if sizeChanged {
            bounds = CGRect(x: 0, y: 0, width: bw, height: totalH)
        }
        label.frame = CGRect(x: padX, y: padY,
                             width: bw - padX * 2, height: bh - padY * 2)
        let wasVisible = !isHidden && currentKey != ""
        let oldCenter = self.center
        self.center = center
        let newTailX = min(max(anchorX - (center.x - bw / 2), 30 * sx),
                           bw - 30 * sx)
        if key != currentKey || sizeChanged || abs(newTailX - tailX) > 1 {
            tailX = newTailX
            redrawShape(bubbleRect: CGRect(x: 2, y: 2, width: bw - 4, height: bh - 2),
                        tail: tail, sx: sx)
        }
        tailTipInParent = CGPoint(x: center.x - bw / 2 + tailX,
                                  y: center.y + totalH / 2 - 4)
        if key != currentKey || label.text != text {
            let isNewKey = key != currentKey
            currentKey = key
            label.text = text
            isHidden = false
            if isNewKey {
                // 弹入（v3 pop：0.55 → 1，弹簧等价）。
                transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
                UIView.animate(withDuration: 0.32, delay: 0,
                               usingSpringWithDamping: 0.55,
                               initialSpringVelocity: 1.1, options: []) {
                    self.transform = .identity
                }
                if animateMove && wasVisible {
                    // 换人跟随（(55) B）：弹簧移位到新独唱者头顶。
                    self.center = oldCenter
                    UIView.animate(withDuration: 0.5, delay: 0,
                                   usingSpringWithDamping: 0.78,
                                   initialSpringVelocity: 0.6,
                                   options: [.beginFromCurrentState]) {
                        self.center = center
                    }
                }
            }
        }
    }

    /// 通用气泡（队长口令/闲聊/告别）：尾尖指向 tip、气泡在其
    /// 上方。(54) P 同修：逐字换行 + 字号自适应（≤3 行）+
    /// 整泡钳制在舞台内——原文案短句原先靠 byWordWrapping
    /// 对无空格中文整段不换行有溢出风险，现消除。
    /// - tip: 气泡尾尖应指向的点（舞台坐标）。
    func show(key: String, text: String, fontRefPx: CGFloat,
              tip: CGPoint, stageSize: CGSize) {
        // 通用气泡与跟随气泡共用同一视图：切回通用路径时清
        // 跟随去重，免下一条歌词被误判「未变化」而跳过。
        lastFollowKey = ""
        lastFollowAnchor = nil
        let sc = scales(stageSize)
        let sx = sc.sx
        let padX: CGFloat = 26 * sx
        let maxTextW = min((sc.landscape ? Self.lyricNormalMaxTextRefWL : 600) * sx,
                           stageSize.width - 24 * sx - padX * 2 - 8)
        let solved = solve(text: text, baseFontRef: fontRefPx,
                           minFontRef: Self.genericMinFontRef,
                           maxTextW: max(40, maxTextW), sx: sx,
                           maxLines: Self.lyricMaxLines)
        let tail: CGFloat = 18 * sx
        let bw = ceil(solved.size.width) + padX * 2 + 8
        let totalH = ceil(solved.size.height) + 15 * sx * 2 + tail + 4
        let cx = min(max(tip.x, bw / 2 + 12 * sx),
                     stageSize.width - bw / 2 - 12 * sx)
        var cy = tip.y - totalH / 2
        cy = min(max(cy, totalH / 2 + 6 * sx),
                 stageSize.height - totalH / 2 - 6 * sx)
        apply(key: key, text: text, solved: solved,
              center: CGPoint(x: cx, y: cy), anchorX: tip.x,
              stageSize: stageSize)
        tailTipInParent = nil // 通用气泡尾巴直接贴头顶，无中间线
    }

    /// 歌词气泡（(55) B 第 2 项，覆盖 (54) P+Q 的固定专区＋
    /// 引导线）：整行全文锚定在当前独唱者头顶上方——气泡底
    /// （含尾）距头顶 lyricFollowGapRef，横向以唱者 x 为中
    /// 心；整泡钳制在舞台内（唱者在最左/最右列时气泡向内
    /// 偏移、尾尖在泡内滑动指向唱者，见 apply 的 tailX 钳
    /// 制）；换人（key 变）时以系统弹簧移位跟随（apply 的
    /// animateMove）。整行求解与 (54) P 同口径：常规宽内降
    /// 字号（44→28）至 ≤3 行；仍放不下走 wide——加宽到舞台
    /// 全宽（留 12 边距）再降字号；极端长行 wide+下限仍超
    /// 3 行时按实测行数放行（加高），任何路径不截断、不省
    /// 略。wide 触发落面包屑（按 key 去重）。
    /// - anchor: 独唱者头顶（舞台坐标，= 唱者 frame 左上中点
    ///   的 y 与其中心 x）；合唱行由渲染方给独唱位头顶。
    func showFollowingSinger(key: String, text: String,
                             fontRefPx: CGFloat,
                             stageSize: CGSize, anchor: CGPoint) {
        // 去重：同 key/同锚点（±1pt）/同尺寸直接返回——独唱
        // 者演唱窗内静止，逐帧重排只会打断换人弹簧。
        if key == lastFollowKey, let last = lastFollowAnchor,
           abs(last.x - anchor.x) < 1, abs(last.y - anchor.y) < 1,
           stageSize == lastFollowStageSize, !isHidden {
            return
        }
        lastFollowKey = key
        lastFollowAnchor = anchor
        lastFollowStageSize = stageSize
        let sc = scales(stageSize)
        let sx = sc.sx, sy = sc.sy
        let padX: CGFloat = 26 * sx
        let normalMax = min((sc.landscape ? Self.lyricNormalMaxTextRefWL
                                : Self.lyricNormalMaxTextRefW) * sx,
                            stageSize.width - 24 * sx - padX * 2 - 8)
        var solved = solve(text: text, baseFontRef: fontRefPx,
                           minFontRef: Self.lyricMinFontRef,
                           maxTextW: max(40, normalMax), sx: sx,
                           maxLines: Self.lyricMaxLines)
        if solved.lines > Self.lyricMaxLines {
            let wideMax = stageSize.width - 24 * sx - padX * 2 - 8
            solved = solve(text: text, baseFontRef: fontRefPx,
                           minFontRef: Self.lyricMinFontRef,
                           maxTextW: max(40, wideMax), sx: sx,
                           maxLines: Self.lyricMaxLines)
            if key != currentKey {
                Breadcrumbs.log("concert.bubble.wide key=\(key)"
                    + " chars=\(text.count)"
                    + " fontRef=\(Int(solved.fontRef))"
                    + " lines=\(solved.lines)")
            }
        }
        let tail: CGFloat = 18 * sx
        let bw = ceil(solved.size.width) + padX * 2 + 8
        let totalH = ceil(solved.size.height) + 15 * sx * 2 + tail + 4
        // 横向：以唱者 x 为中心，整泡钳进舞台（左右各留 8sx）。
        let cx = min(max(anchor.x, bw / 2 + 8 * sx),
                     stageSize.width - bw / 2 - 8 * sx)
        // 纵向：泡底（含尾）落在头顶上方 gap 处；钳制上界为
        // 舞台顶 +6sy（后排唱者头顶高、长行气泡向上顶时不
        // 出屏，尾仍指向唱者），下界不越舞台底 -6sy。
        var cy = anchor.y - Self.lyricFollowGapRef * sy - totalH / 2
        cy = min(max(cy, totalH / 2 + 6 * sy),
                 stageSize.height - totalH / 2 - 6 * sy)
        let isNewKey = key != currentKey
        apply(key: key, text: text, solved: solved,
              center: CGPoint(x: cx, y: cy), anchorX: anchor.x,
              stageSize: stageSize, animateMove: true)
        if isNewKey {
            Breadcrumbs.log("concert.bubble.follow key=\(key)"
                + " anchor=\(Int(anchor.x)),\(Int(anchor.y))"
                + " center=\(Int(cx)),\(Int(cy))"
                + " clamped=\(abs(cx - anchor.x) > 1 ? 1 : 0)")
        }
    }

    func hide() {
        lastFollowKey = ""
        lastFollowAnchor = nil
        guard !isHidden else { return }
        isHidden = true
        currentKey = ""
        tailTipInParent = nil
    }

    private func redrawShape(bubbleRect: CGRect, tail: CGFloat, sx: CGFloat) {
        let path = UIBezierPath(
            roundedRect: bubbleRect, cornerRadius: 22 * sx)
        let tailPath = UIBezierPath()
        tailPath.move(to: CGPoint(x: tailX - 13 * sx, y: bubbleRect.maxY - 2))
        tailPath.addLine(to: CGPoint(x: tailX + 13 * sx, y: bubbleRect.maxY - 2))
        tailPath.addLine(to: CGPoint(x: tailX, y: bubbleRect.maxY + tail))
        tailPath.close()
        path.append(tailPath)
        shapeLayer.path = path.cgPath
        shapeLayer.lineWidth = 4 * sx
    }
}

// MARK: - 宠物演员（静帧图 + 可选 APNG 动图）

private final class PetConcertActorView: UIView {
    let asset: String
    let imageView = UIImageView()
    private(set) var stickerView: StickerView?
    /// 解码成本（动图准入核算；静帧为 atlas 估算不计入池预算）。
    var decodedCost = 0

    // MARK: 前排副本呈现（3.7 (65) A 组，胶囊 v3b 定版）
    //
    // 前排（末行）整排换 cat-live 独立副本：副本只是一层
    // 呈现——演员的槽位/跑位/气泡/发光等身份机制一概走本
    // 体 asset（计划层零改动），仅「站在前排格位时」的画
    // 面换成捂脸小猫。副本动图走专用 StickerView 播
    // cat-live（解码经 StickerStore 按名共享、全排只解一
    // 份），每只以 phase×137ms 帧偏移错开（模板口径）；
    // 独唱跑位期间（copySuppressed）恢复本体呈现——独唱
    // 者是它自己，离排即卸妆、归排即换回。氛围降级（内
    // 存警告）摘副本动图后落副本静帧（copyImageView）。

    /// 副本动图层（cat-live，相位偏移由渲染方注入）。
    private(set) var copyStickerView: StickerView?
    /// 副本静帧兜底层（降级/解码未到时）。
    private let copyImageView = UIImageView()
    private var copyStaticImage: UIImage?
    /// 本演员在当前朝向是否居前排（渲染方按 plan 槽位行
    /// 在建团/旋转时刷新）。
    private(set) var frontRowCopy = false
    /// 跑位中抑制副本（渲染方逐帧按 trip 在飞与否置位）。
    var copySuppressed = false {
        didSet { if copySuppressed != oldValue { refreshVisibility() } }
    }
    private var lastCopyPhaseMs: Double = -1

    init(asset: String) {
        self.asset = asset
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        copyImageView.contentMode = .scaleAspectFit
        copyImageView.isUserInteractionEnabled = false
        copyImageView.isHidden = true
        addSubview(copyImageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        stickerView?.frame = bounds
        copyImageView.frame = bounds
        copyStickerView?.frame = bounds
    }

    /// 显隐裁决（唯一出口）：副本在场且未被跑位抑制 →
    /// 副本层（动图优先、静帧兜底）；否则本体层（动图池
    /// 贴纸优先、静帧兜底）。attach/detach/副本开关都只改
    /// 状态、末尾统一走本方法，杜绝多路显隐打架。
    private func refreshVisibility() {
        if frontRowCopy && !copySuppressed {
            stickerView?.isHidden = true
            if let copyStickerView {
                copyStickerView.isHidden = false
                copyImageView.isHidden = true
                imageView.isHidden = true
            } else {
                copyImageView.isHidden = copyStaticImage == nil
                imageView.isHidden = copyStaticImage != nil
            }
        } else {
            copyStickerView?.isHidden = true
            copyImageView.isHidden = true
            if stickerView != nil {
                stickerView?.isHidden = false
                imageView.isHidden = true
            } else {
                imageView.isHidden = false
            }
        }
    }

    func setStaticImage(_ image: UIImage?) {
        imageView.image = image
        refreshVisibility()
    }

    /// 副本静帧（cat-live 首帧，全排共用一份，渲染方注入）。
    func setCopyStaticImage(_ image: UIImage?) {
        copyStaticImage = image
        copyImageView.image = image
        refreshVisibility()
    }

    /// 前排副本开关：开时按需建副本动图层（相位偏移注入
    /// 后再 setSticker，保证解码完成 restart 时读到偏移）；
    /// 相位变了（旋转换列数）重注入并 restart 对齐新相位。
    /// animatedAvailable=false（氛围降级后）只留静帧兜底。
    func setFrontRowCopy(active: Bool, phaseOffsetMs: Double,
                         animatedAvailable: Bool) {
        frontRowCopy = active
        if active {
            if animatedAvailable {
                if let sticker = copyStickerView {
                    if abs(phaseOffsetMs - lastCopyPhaseMs) > 1 {
                        lastCopyPhaseMs = phaseOffsetMs
                        sticker.startPhaseOffset = phaseOffsetMs / 1000
                        sticker.restart()
                    }
                } else {
                    let sticker = StickerView()
                    sticker.crumbScene = "concert-copy"
                    sticker.frame = bounds
                    sticker.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    sticker.startPhaseOffset = phaseOffsetMs / 1000
                    lastCopyPhaseMs = phaseOffsetMs
                    addSubview(sticker)
                    copyStickerView = sticker
                    sticker.setSticker("cat-live", mode: .loop)
                }
            }
        } else {
            copyStickerView?.removeFromSuperview()
            copyStickerView = nil
            lastCopyPhaseMs = -1
        }
        refreshVisibility()
    }

    /// 氛围降级：摘副本动图（副本身份保留、落静帧兜底）。
    func detachCopySticker() {
        copyStickerView?.removeFromSuperview()
        copyStickerView = nil
        lastCopyPhaseMs = -1
        refreshVisibility()
    }

    func attachSticker() {
        guard stickerView == nil else { return }
        let sticker = StickerView()
        sticker.crumbScene = "concert-pet"
        sticker.frame = bounds
        sticker.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(sticker)
        stickerView = sticker
        sticker.setSticker(asset, mode: .loop)
        refreshVisibility()
    }

    func detachSticker() {
        stickerView?.removeFromSuperview()
        stickerView = nil
        refreshVisibility()
    }
}

// MARK: - 前排舞步（3.7 (65) A 组，胶囊 v3b 模板 star_dance 移植）
//
// 模板参数逐项对位（capsule-lyric-v3b-render.py star_dance /
// build_pets）：弹跳节拍 BEAT=2.2 次/秒、偶数列全拍奇数列半
// 拍，幅 12 参考 px；摇摆 x = sin(2π·1.1t + phase2)·9；倾斜
// rot = 7°·sin(2π·1.1t + phase)；旋转一圈 period 4.4s、持续
// 0.7s、逐列偏移 i·0.55s、easeInOut 推进 360°。相位按列错
// 开：phase = i·τ/列数 + 0.35·(i mod 3)（模板 8 列除数取 8，
// 本地按当前朝向实际列数等比），phase2 = i·1.13 + 0.5；帧
// 偏移 = phase×137ms（副本 StickerView 的 startPhaseOffset）。
// 全部是歌曲位置 t 的纯函数，seek 后自动重建（与计划层同
// 纪律）。幅度用参考 px（横屏参考系与模板同为 1920 宽；竖
// 屏沿本文件既有口径同值，如群唱蹦 10、间奏蹦 12）。
private enum PetConcertFrontRow {
    static func phase(column: Int, columns: Int) -> Double {
        let tau = 2 * Double.pi
        let raw = Double(column) * tau / Double(max(1, columns))
            + 0.35 * Double(column % 3)
        return raw.truncatingRemainder(dividingBy: tau)
    }

    static func phase2(column: Int) -> Double {
        (Double(column) * 1.13 + 0.5)
            .truncatingRemainder(dividingBy: 2 * Double.pi)
    }

    /// 帧偏移（毫秒）＝ phase × 137（模板 frame_at 口径）。
    static func frameOffsetMs(column: Int, columns: Int) -> Double {
        phase(column: column, columns: columns) * 137
    }

    static func dance(column: Int, columns: Int, at t: TimeInterval)
        -> (dx: CGFloat, dy: CGFloat, rotation: CGFloat) {
        let p1 = phase(column: column, columns: columns)
        let p2 = phase2(column: column)
        let beat = column % 2 == 0 ? 2.2 : 1.1
        let dy = -abs(sin(Double.pi * beat * t + p1)) * 12
        let dx = sin(2 * Double.pi * 1.1 * t + p2) * 9
        var rotDeg = 7 * sin(2 * Double.pi * 1.1 * t + p1)
        let period = 4.4, dur = 0.7, off = Double(column) * 0.55
        let local = (t + off).truncatingRemainder(dividingBy: period)
        if local < dur {
            rotDeg += 360 * concertEaseInOut(local / dur)
        }
        return (CGFloat(dx), CGFloat(dy), CGFloat(rotDeg * Double.pi / 180))
    }
}

// MARK: - 渲染器

final class PetConcertStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: true, requiresSpectrum: false, supportsLineSeek: true)

    private let rootView = LyricStageRootView()
    private let backdropView = PetConcertBackdropView()
    /// 灯光层（(55) B 第 3 项）：洗光/光束/追光/光池/脚灯辉
    /// 光，挂在 petField 之下——光只落背景/地板/幕布，宠物
    /// 本体零滤色（清单见 PetConcertLightView 头注）。
    private let lightView = PetConcertLightView()
    private let curtainView = PetConcertCurtainView()
    private let petField = UIView()
    private let bubbleView = PetConcertBubbleView()
    /// 独唱发光（(54) S）：贴纸 alpha 轮廓外发光图，贴在独唱
    /// 宠物身后跟随；本体层不挂任何滤镜/混合，像素零改动。
    private let singerGlowView = UIImageView()
    private var glowCache: [String: UIImage] = [:]
    private var glowAsset: String?
    /// 独唱星点（(54) S）：12 颗小星形，绕独唱者确定性生灭。
    private let sparkleView = UIView()
    private var sparkleLayers: [CAShapeLayer] = []
    /// 立式麦克风（(62) 胶囊版立、(65) 改迷你口径）：挂
    /// petField 之上、独唱位。
    private let micView = PetConcertMicView()
    /// 主胶囊歌词板 + 上缘闪光（(62) 胶囊版）。
    private let capsuleView = PetConcertCapsuleView()
    private let capsuleSparkleView = UIView()
    private var capsuleSparkleLayers: [CAShapeLayer] = []
    private var lastCapsuleLineId: Int?
    private var lastCapsuleSpecies = "cat"

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    private var isActive = false
    private var plan: ConcertPlan?
    private var actors: [String: PetConcertActorView] = [:]
    private var actorOrder: [String] = []
    private var builtKey = ""
    private var lastPhase: ConcertPhase?
    private var lastSingerAsset: String?
    private var lastSingerLine: Int?
    /// 前排副本已按此朝向刷新过（(65) A 组）：nil＝未刷新，
    /// 建团/旋转换向时据此重刷副本归属与相位。
    private var copyOrientation: Bool?
    private var admittedAnimated: Set<String> = []
    private var admittedCost = 0
    private var poolSettled = false
    private var interludeSwapped = false
    private var relocationActive = false
    private var atmosphereReduced = false

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        rootView.addSubview(backdropView)
        // z 序（(55) B 第 3 项自证）：backdrop（背景/地板/脚
        // 圈）→ lightView（全部环境光）→ petField（宠物本体；
        // 独唱轮廓发光在其内部贴本体身后）→ curtainView（幕
        // 布本体/点缀/脚灯灯体/纸屑——(55) B 后开口已让开全
        // 部格位，不切宠物）→ bubble（(65) 起底部提词条已
        // 摘除、z 序尾即气泡）。光层无一在宠物之上，宠物像
        // 素不参与任何光层混合。
        rootView.addSubview(lightView)
        petField.isUserInteractionEnabled = false
        rootView.addSubview(petField)
        // (62) 胶囊版：立麦在宠物之上（独唱者站麦后）、幕布
        // 之下（侧幕不切麦）；主胶囊在幕布之上（背景带内、
        // 与幕布无重叠）、气泡之下。
        rootView.addSubview(micView)
        rootView.addSubview(curtainView)
        capsuleView.isHidden = true
        rootView.addSubview(capsuleView)
        capsuleSparkleView.isUserInteractionEnabled = false
        capsuleSparkleView.isHidden = true
        for i in 0..<5 {
            let star = CAShapeLayer()
            star.fillColor = (i % 2 == 0
                ? PetConcertPalette.gold
                : UIColor.white).cgColor
            capsuleSparkleView.layer.addSublayer(star)
            capsuleSparkleLayers.append(star)
        }
        rootView.addSubview(capsuleSparkleView)
        singerGlowView.isUserInteractionEnabled = false
        singerGlowView.contentMode = .scaleAspectFit
        singerGlowView.isHidden = true
        petField.addSubview(singerGlowView)
        sparkleView.isUserInteractionEnabled = false
        sparkleView.isHidden = true
        for i in 0..<12 {
            let star = CAShapeLayer()
            star.fillColor = (i % 3 == 0
                ? UIColor.white
                : PetConcertPalette.gold).cgColor
            star.strokeColor = PetConcertPalette.outline
                .withAlphaComponent(0.55).cgColor
            star.lineWidth = 1
            sparkleView.layer.addSublayer(star)
            sparkleLayers.append(star)
        }
        petField.addSubview(sparkleView)
        // (55) B 第 2 项：引导线（guideView/guideLayer）已删
        // 除——气泡直接落独唱者头顶，归属由位置本身表达。
        rootView.addSubview(bubbleView)
        bubbleView.isHidden = true
        // (65) A 组：底部提词小胶囊（teleBar）已整条摘除——
        // 它就是 v2 样片 TELE（480×72 @ 竖屏 y=1798）的同
        // 物，(62) 给它换了小胶囊材质；v3b 定版模板已删
        // 除下方胶囊条（ Miller 16:19/16:36 两度点名），
        // 歌词呈现自此只走上方主胶囊。连同其材质层与
        // (61) 提词区对比衬底一并摘除（衬底类本体是共享
        // 基础设施、其它渲染器仍在用，不动）。
        rootView.onLayout = { [weak self] in self?.performLayout() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        // (61) WC：入口统一过对比钳制——下游 palette.* 全走保护副本。
        var snapshot = snapshot
        snapshot.palette = snapshot.palette.contrastProtected()
        self.snapshot = snapshot
        let trackId = snapshot.track?.id ?? ""
        let firstStart = snapshot.lines.first?.start ?? -1
        let lastEnd = snapshot.lines.last?.end ?? -1
        let key = "\(trackId)|\(snapshot.lines.count)|\(firstStart)|\(lastEnd)"
        guard key != builtKey else { return }
        builtKey = key
        buildConcert(snapshot: snapshot)
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if isActive, !relocationActive {
            relocationActive = true
            // 样式生效 + 舞台呈现中：台/岛宠物撤下（(53) J §8）。
            PetConcertRelocation.shared.beginConcert()
        }
        if state == .destroyed {
            cancelConcertProbe()
            if relocationActive {
                relocationActive = false
                PetConcertRelocation.shared.endConcert()
            }
        }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let plan, rootView.bounds.width > 0 else { return }
        tickGen += 1
        let size = rootView.bounds.size
        let phase = plan.phase(at: position)
        if phase != lastPhase {
            let span = plan.phaseSpan(phase)
            Breadcrumbs.log("concert.phase track=\(plan.trackId)"
                + " phase=\(phase.rawValue) at=\(String(format: "%.2f", position))"
                + " span=\(String(format: "%.2f", span.start))-\(String(format: "%.2f", span.end))"
                + " dur=\(String(format: "%.2f", max(0, span.end - span.start)))"
                + " intro=\(plan.introKind)")
            handlePhaseEnter(phase, plan: plan)
            lastPhase = phase
        }
        let params = plan.sectionParams(at: position)

        // 独唱者（跑位中也算）：取当前行 trip 的 singer。
        let soloLine = currentLine(at: position, plan: plan)
        let singerAsset = soloLine.flatMap { plan.singerByLine[$0] }
        if singerAsset != lastSingerAsset || soloLine != lastSingerLine {
            if let singerAsset, let soloLine {
                Breadcrumbs.log("concert.singer asset=\(singerAsset) line=\(soloLine)")
            }
            lastSingerAsset = singerAsset
            lastSingerLine = soloLine
        }

        // 演员定位。
        var singerCenter: CGPoint? = nil
        var singerFeetY: CGFloat? = nil
        var singerActor: PetConcertActorView? = nil
        var singerScale: CGFloat = 1
        let landscape = PetConcertConst.isLandscape(size)
        for asset in actorOrder {
            guard let actor = actors[asset] else { continue }
            let state = actorState(asset: asset, at: position, plan: plan,
                                   landscape: landscape)
            let center = refToStage(state.center, size: size, landscape: landscape)
            actor.center = center
            let base = (landscape ? PetConcertConst.petBaseL : PetConcertConst.petBase)
                * (size.width / (landscape ? PetConcertConst.refWL : PetConcertConst.refW))
            actor.bounds = CGRect(x: 0, y: 0, width: base, height: base)
            // (65) A 组：变换 = 旋转∘缩放（前排舞步的倾斜/
            // 旋转；rotation=0 时与旧纯缩放逐值一致）。
            actor.transform = CGAffineTransform(rotationAngle: state.rotation)
                .scaledBy(x: state.scale, y: state.scale)
            // (65) A 组：跑位在飞时副本抑制（独唱者呈本体），
            // 与 actorState 内部 trip 判定同源同窗。
            actor.copySuppressed = state.onTrip
            if asset == singerAsset {
                singerCenter = center
                singerFeetY = center.y + base * state.scale / 2
                singerActor = actor
                singerScale = state.scale
                petField.bringSubviewToFront(actor)
            }
        }

        // 幕布/灯光（氛围层）：灯光层在宠物之下更新落点（追
        // 光弹簧跟随独唱位），幕布层只走幕布/点缀/纸屑路径。
        lightView.update(
            t: position, phase: phase, params: params,
            singerPos: singerCenter, singerFeetY: singerFeetY,
            interludeIntensity: plan.interlude?.intensity ?? 0)
        curtainView.update(
            t: position, phase: phase, params: params,
            singerPos: singerCenter, singerFeetY: singerFeetY,
            interludeIntensity: plan.interlude?.intensity ?? 0)

        // 独唱发光（(54) S：轮廓光晕 + 星点，跟随跑位包络）。
        updateSingerGlow(position: position, plan: plan,
                         singerAsset: singerAsset, singerActor: singerActor,
                         singerCenter: singerCenter, singerScale: singerScale,
                         size: size)

        updateBubble(position: position, phase: phase, plan: plan,
                     singerAsset: singerAsset, soloLine: soloLine, size: size)
        updateCapsule(position: position, plan: plan, size: size)
    }

    func unmount() {
        cancelConcertProbe()
        isActive = false
        if relocationActive {
            relocationActive = false
            PetConcertRelocation.shared.endConcert()
        }
        for actor in actors.values { actor.removeFromSuperview() }
        actors.removeAll()
        actorOrder.removeAll()
        admittedAnimated.removeAll()
        admittedCost = 0
        poolSettled = false
        interludeSwapped = false
        glowCache.removeAll()
        glowAsset = nil
        singerGlowView.isHidden = true
        sparkleView.isHidden = true
        plan = nil
        builtKey = ""
        lastPhase = nil
        context = nil
    }

    // MARK: 构建

    private func buildConcert(snapshot: LyricStageSnapshot) {
        for actor in actors.values { actor.removeFromSuperview() }
        actors.removeAll()
        actorOrder.removeAll()
        admittedAnimated.removeAll()
        admittedCost = 0
        poolSettled = false
        interludeSwapped = false
        lastPhase = nil
        lastSingerAsset = nil
        lastSingerLine = nil
        copyOrientation = nil

        let duration = snapshot.track?.duration ?? 0
        let effectiveDuration = duration > 0 ? duration
            : (snapshot.lines.last?.end ?? 0) + 2
        let built = ConcertPlan.build(
            trackId: snapshot.track?.id ?? "",
            title: snapshot.track?.title ?? "",
            lines: snapshot.lines, duration: effectiveDuration)
        plan = built
        Breadcrumbs.log("concert.plan track=\(built.trackId)"
            + " captain=\(built.captain) lines=\(built.lines.count)"
            + " singers=\(built.singerByLine.count) chorus=\(built.chorusLines.count)"
            + " interlude=\(built.interlude.map { "\(Int($0.start))-\(Int($0.end))" } ?? "none")")
        // (54) T 仪式安排对账：intro=none 表示无前奏歌整段
        // 省去；greeting/whisper 为两段相位窗秒数（恒 ≤ 前奏
        // 可用时间）；farewell 记起点与保底后窗长。
        Breadcrumbs.log("concert.phase.schedule track=\(built.trackId)"
            + " intro=\(built.introKind)"
            + " firstLine=\(String(format: "%.2f", built.firstLineStart))"
            + " settled=\(String(format: "%.2f", built.formationSettledAt))"
            + " greeting=\(String(format: "%.2f", built.greetingDuration))"
            + " whisper=\(String(format: "%.2f", built.whisperDuration))"
            + " greetCues=\(built.greetingCues.count)"
            + " chatCues=\(built.chatCues.count)"
            + " farewellAt=\(built.farewellAt.map { String(format: "%.2f", $0) } ?? "none")"
            + " farewellDur=\(built.farewellAt.map { String(format: "%.2f", built.duration - $0) } ?? "0")"
            + " farewellCues=\(built.farewellCues.count)"
            + " R=\(String(format: "%.2f", built.introBudgetR))"
            + " singEnd=\(built.singEnd.map { String(format: "%.2f", $0) } ?? "none")"
            + " interludeCues=\(built.interludeCues.count)")

        // 演员按槽位行序添加（row 0 后排先加、row 7 前排后加，
        // 前排天然压后排）。
        let sorted = PetConcertConst.allAssets.sorted {
            (built.slotOf[$0] ?? 0) < (built.slotOf[$1] ?? 0)
        }
        for asset in sorted {
            let actor = PetConcertActorView(asset: asset)
            actors[asset] = actor
            actorOrder.append(asset)
            petField.addSubview(actor)
            loadStaticImage(for: asset, into: actor)
        }
        // (65) A 组：副本静帧（cat-live 首帧，与全排共用同
        // 一份 StickerStore 解码）注入每个演员——副本动图
        // 解码未到或氛围降级摘动图时，副本落此静帧、不回
        // 本体图。
        StickerStore.shared.load("cat-live") { [weak self] decoded in
            guard let self, let decoded, let cg = decoded.frames.first
            else { return }
            let image = Self.downscaled(UIImage(cgImage: cg))
            for actor in self.actors.values {
                actor.setCopyStaticImage(image)
            }
        }
        admitAnimatedPool(plan: built)
        performLayout()
    }

    private func loadStaticImage(for asset: String,
                                 into actor: PetConcertActorView) {
        if PetConcertConst.cutoutAssets.contains(asset),
           let url = Bundle.main.url(forResource: asset, withExtension: "png",
                                     subdirectory: "StickersCutout"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            actor.setStaticImage(Self.downscaled(image))
            return
        }
        StickerStore.shared.load(asset) { [weak actor] decoded in
            guard let actor, let decoded,
                  let cg = decoded.frames.first else { return }
            actor.setStaticImage(Self.downscaled(UIImage(cgImage: cg)))
        }
    }

    /// 静帧 atlas 缩放（≤160px 边长，53 只合计 ≈5.4MB）。
    private static func downscaled(_ image: UIImage) -> UIImage {
        let maxPx = PetConcertConst.staticAtlasMaxPx
        let pxW = image.size.width * image.scale
        let pxH = image.size.height * image.scale
        let longest = max(pxW, pxH)
        guard longest > maxPx, let cg = image.cgImage else { return image }
        let ratio = maxPx / longest
        let target = CGSize(width: max(1, (pxW * ratio).rounded()),
                            height: max(1, (pxH * ratio).rounded()))
        guard let ctx = CGContext(
            data: nil, width: Int(target.width), height: Int(target.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(origin: .zero, size: target))
        guard let out = ctx.makeImage() else { return image }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }

    // MARK: 动图池准入（成本实测、预算硬顶）

    private func admitAnimatedPool(plan: ConcertPlan) {
        let candidates = plan.animPriority
        var index = 0
        func admitNext() {
            guard index < candidates.count,
                  admittedAnimated.count < PetConcertConst.animPoolMaxCount
            else {
                poolSettled = true
                Breadcrumbs.log("concert.pool animated=\(admittedAnimated.count)"
                    + " costMB=\(String(format: "%.1f", Double(admittedCost) / 1048576))"
                    + " assets=\(admittedAnimated.sorted().joined(separator: ","))")
                return
            }
            let asset = candidates[index]
            index += 1
            StickerStore.shared.load(asset) { [weak self] decoded in
                guard let self, let decoded else { admitNext(); return }
                let cost = decoded.memoryCost
                if admittedCost + cost <= PetConcertConst.animPoolBudgetBytes,
                   let actor = actors[asset], actor.stickerView == nil {
                    actor.attachSticker()
                    actor.decodedCost = cost
                    admittedAnimated.insert(asset)
                    admittedCost += cost
                }
                admitNext()
            }
        }
        admitNext()
    }

    /// 间奏换入（v3 ANIM_EXTRA2）：池大小不变，换人不加人；
    /// 被换出者选已准入中成本最高且非队长/非当前独唱者。
    private func applyInterludeSwap(plan: ConcertPlan, entering: Bool) {
        guard poolSettled, !atmosphereReduced else { return }
        if entering, !interludeSwapped {
            interludeSwapped = true
            for swapIn in PetConcertConst.interludeSwapIn {
                guard let actor = actors[swapIn], actor.stickerView == nil
                else { continue }
                StickerStore.shared.load(swapIn) { [weak self] decoded in
                    guard let self, let decoded else { return }
                    let cost = decoded.memoryCost
                    // 找可换出者（成本 ≥ 新人或预算有余）。
                    let removable = admittedAnimated
                        .filter { $0 != plan.captain && $0 != self.lastSingerAsset }
                        .max { (self.actors[$0]?.decodedCost ?? 0)
                            < (self.actors[$1]?.decodedCost ?? 0) }
                    if admittedCost + cost <= PetConcertConst.animPoolBudgetBytes {
                        actor.attachSticker()
                        actor.decodedCost = cost
                        admittedAnimated.insert(swapIn)
                        admittedCost += cost
                    } else if let out = removable,
                              admittedCost - (actors[out]?.decodedCost ?? 0) + cost
                                  <= PetConcertConst.animPoolBudgetBytes {
                        actors[out]?.detachSticker()
                        admittedAnimated.remove(out)
                        admittedCost -= actors[out]?.decodedCost ?? 0
                        actor.attachSticker()
                        actor.decodedCost = cost
                        admittedAnimated.insert(swapIn)
                        admittedCost += cost
                    }
                }
            }
        } else if !entering, interludeSwapped {
            interludeSwapped = false
            for swapIn in PetConcertConst.interludeSwapIn
            where admittedAnimated.contains(swapIn) {
                actors[swapIn]?.detachSticker()
                admittedCost -= actors[swapIn]?.decodedCost ?? 0
                admittedAnimated.remove(swapIn)
            }
            admitAnimatedPool(plan: plan)
        }
    }

    private func handlePhaseEnter(_ phase: ConcertPhase, plan: ConcertPlan) {
        switch phase {
        case .interlude:
            if let gap = plan.interlude {
                curtainView.scheduleConfetti(bursts: [
                    gap.start + 0.05,
                    gap.start + (gap.end - gap.start) * 0.55,
                ])
            }
            applyInterludeSwap(plan: plan, entering: true)
        case .singing2, .farewell:
            applyInterludeSwap(plan: plan, entering: false)
        default:
            break
        }
    }

    // MARK: 降级（内存警告：先砍氛围，再砍动图，歌词不动）

    @objc private func handleMemoryWarning() {
        guard plan != nil, !atmosphereReduced else { return }
        atmosphereReduced = true
        curtainView.atmosphereReduced = true
        lightView.atmosphereReduced = true
        for asset in admittedAnimated {
            actors[asset]?.detachSticker()
        }
        admittedAnimated.removeAll()
        admittedCost = 0
        // (65) A 组：副本动图同列降级——摘动图层、前排落
        // 副本静帧（copyImageView），副本身份不丢。
        for actor in actors.values {
            actor.detachCopySticker()
        }
        Breadcrumbs.log("concert.degrade reason=memoryWarning atmosphere=off animated=static")
    }

    // MARK: 独唱发光（(54) S）

    private static let glowCIContext = CIContext(options: nil)

    /// 发光包络：与跑位同一时间轴——出发→到达 easeInOut 渐
    /// 入、独唱位恒 1、归队渐出；连唱（下一行同人且已出发）
    /// 恒 1 不闪断。无 trip（群唱/非演唱窗）为 0。
    private func glowEnvelope(asset: String, at t: TimeInterval,
                              plan: ConcertPlan) -> CGFloat {
        let trip = plan.tripsByLine.values
            .filter { $0.singer == asset && t >= $0.depart && t < $0.returnEnd }
            .sorted { $0.lineIndex < $1.lineIndex }
            .first
        guard let trip else { return 0 }
        if t < trip.arrive {
            return CGFloat(concertEaseInOut(
                (t - trip.depart) / (trip.arrive - trip.depart)))
        }
        if t < trip.returnStart { return 1 }
        if let next = plan.tripsByLine[trip.lineIndex + 1],
           next.singer == asset, t >= next.depart { return 1 }
        return CGFloat(1 - concertEaseInOut(
            (t - trip.returnStart) / (trip.returnEnd - trip.returnStart)))
    }

    /// 轮廓发光图（按 asset 缓存、离屏只生成一次）：贴纸静帧
    /// alpha 作掩码染暖金 → CIAffineClamp + 高斯模糊外扩 →
    /// 双遍绘制加强。后续帧只动 glowView 的 transform/alpha。
    private func glowImage(for asset: String, source: UIImage?) -> UIImage? {
        if let cached = glowCache[asset] { return cached }
        guard let source else { return nil }
        // withTintColor 以贴纸 alpha 为掩码出纯色剪影（本体图
        // 本身不被修改、发光图是独立缓存图）。
        let tinted = source.withTintColor(
            UIColor(red: 1, green: 0.84, blue: 0.45, alpha: 1),
            renderingMode: .alwaysOriginal)
        guard let ci = CIImage(image: tinted),
              let clamp = CIFilter(name: "CIAffineClamp"),
              let blur = CIFilter(name: "CIGaussianBlur")
        else { return nil }
        clamp.setValue(ci, forKey: kCIInputImageKey)
        clamp.setValue(NSValue(cgAffineTransform: .identity),
                       forKey: kCIInputTransformKey)
        guard let clamped = clamp.outputImage else { return nil }
        let radius = max(3, Double(source.size.width) * 0.07)
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage else { return nil }
        let extent = ci.extent.insetBy(dx: -CGFloat(radius) * 2,
                                       dy: -CGFloat(radius) * 2)
        guard let cg = Self.glowCIContext.createCGImage(
            blurred, from: extent) else { return nil }
        let soft = UIImage(cgImage: cg, scale: source.scale,
                           orientation: .up)
        let renderer = UIGraphicsImageRenderer(size: soft.size)
        let out = renderer.image { _ in
            soft.draw(in: CGRect(origin: .zero, size: soft.size),
                      blendMode: .normal, alpha: 0.85)
            soft.draw(in: CGRect(origin: .zero, size: soft.size),
                      blendMode: .normal, alpha: 0.85)
        }
        glowCache[asset] = out
        return out
    }

    private func updateSingerGlow(position: TimeInterval,
                                  plan: ConcertPlan,
                                  singerAsset: String?,
                                  singerActor: PetConcertActorView?,
                                  singerCenter: CGPoint?,
                                  singerScale: CGFloat,
                                  size: CGSize) {
        guard let singerAsset, let singerActor, let singerCenter else {
            singerGlowView.isHidden = true
            sparkleView.isHidden = true
            glowAsset = nil
            return
        }
        let envelope = glowEnvelope(asset: singerAsset, at: position,
                                    plan: plan)
        guard envelope > 0.01 else {
            singerGlowView.isHidden = true
            sparkleView.isHidden = true
            return
        }
        if glowAsset != singerAsset {
            glowAsset = singerAsset
            singerGlowView.image = glowImage(
                for: singerAsset, source: singerActor.imageView.image)
        } else if singerGlowView.image == nil {
            // 静帧异步未到：每帧重试，成功即缓存不再生成。
            singerGlowView.image = glowImage(
                for: singerAsset, source: singerActor.imageView.image)
        }
        let landscape = PetConcertConst.isLandscape(size)
        let sx = size.width / (landscape ? PetConcertConst.refWL : PetConcertConst.refW)
        let base = (landscape ? PetConcertConst.petBaseL : PetConcertConst.petBase) * sx
        let w = base * singerScale * 1.5
        singerGlowView.bounds = CGRect(x: 0, y: 0, width: w, height: w)
        singerGlowView.center = singerCenter
        singerGlowView.alpha = envelope * 0.95
        singerGlowView.isHidden = singerGlowView.image == nil
        if !singerGlowView.isHidden {
            petField.insertSubview(singerGlowView, belowSubview: singerActor)
        }
        // 星点：12 颗，1.4s 周期确定性生灭（seed = 周期序号×
        // 星序，同 t 同结果、seek 可重建），绕身椭圆分布。
        sparkleView.frame = CGRect(x: singerCenter.x - w / 2,
                                   y: singerCenter.y - w / 2,
                                   width: w, height: w)
        sparkleView.isHidden = false
        let cycle = 1.4
        for (i, star) in sparkleLayers.enumerated() {
            let shifted = position / cycle + Double(i) * 0.6180339887
            let generation = floor(shifted)
            let phase = shifted - generation
            var rng = ConcertRNG(seed: concertHash(
                "spark-\(Int(generation))-\(i)"))
            let angle = rng.next(in: 0...(2 * Double.pi))
            let dist = 0.52 + 0.48 * rng.next()
            let starRef = 7 + rng.next(in: 0...6)
            let px = w / 2 + CGFloat(cos(angle) * dist) * w * 0.46
            let py = w / 2 + CGFloat(sin(angle) * dist) * w * 0.40
            let starSize = CGFloat(starRef) * sx
                * CGFloat(0.6 + 0.4 * sin(Double.pi * phase))
            star.path = PetConcertDeco.starPath(
                center: CGPoint(x: px, y: py), size: max(1, starSize),
                rotation: CGFloat(phase) * 1.2).cgPath
            star.opacity = Float(envelope)
                * Float(sin(Double.pi * phase)) * 0.95
        }
        petField.bringSubviewToFront(sparkleView)
    }

    // MARK: 位置计算（参考画布坐标，纯函数）

    private func currentLine(at t: TimeInterval, plan: ConcertPlan) -> Int? {
        for line in plan.lines where t >= line.start && t < line.end {
            return line.id
        }
        return nil
    }

    /// 基础锚点（无跑位）：降落/散位/列队/队形/间奏玩耍位。
    /// (54) U：横屏走横屏槽位/散位/玩耍位表（独立参考系）。
    private func basePosition(asset: String, at t: TimeInterval,
                              plan: ConcertPlan, landscape: Bool = false) -> CGPoint {
        let slot = landscape
            ? ConcertPlan.slotPointLandscape(plan.slotOfLandscape[asset] ?? 0)
            : ConcertPlan.slotPoint(plan.slotOf[asset] ?? 0)
        guard let scatter = (landscape ? plan.scatterOfLandscape[asset]
                                : plan.scatterOf[asset]) else { return slot }
        let k = max(0.4, plan.formAt / PetConcertConst.formNominal * 1.667) // ≈ formAt/1.5
        let stagger = (plan.staggerOf[asset] ?? 0) * k
        let fall = PetConcertConst.dropFallDuration * k
        if t < stagger {
            return CGPoint(x: scatter.x, y: -320)
        }
        if t < stagger + fall {
            let u = concertEaseOutQuad((t - stagger) / fall)
            return CGPoint(x: scatter.x,
                           y: concertLerp(-320, scatter.y, u))
        }
        // 散位弹跳（落定余震，v3 bounce 至列队开始）。
        var pos = scatter
        if t < plan.formAt {
            let dt = t - (stagger + fall)
            if dt > 0 {
                let b = abs(sin(dt * 14)) * 13 * exp(-dt * 5)
                pos = CGPoint(x: scatter.x, y: scatter.y - CGFloat(b))
            }
            return pos
        }
        // 列队移动（easeOutBack，每只延迟不同）。
        let moveStart = plan.formAt + (plan.formDelayOf[asset] ?? 0) * k
        let moveDur = max(0.25, PetConcertConst.formMoveDuration * k)
        if t < moveStart { return pos }
        if t < moveStart + moveDur {
            let u = concertEaseOutBack((t - moveStart) / moveDur)
            return concertLerp(pos, slot, u)
        }
        // 间奏玩耍位（出入各一段平滑过渡）。
        if let gap = plan.interlude,
           let play = (landscape ? plan.playOfLandscape[asset] : plan.playOf[asset]) {
            let inDur = 0.45, outDur = 0.55
            if t >= gap.start && t < gap.start + inDur {
                return concertLerp(slot, play, concertEaseInOut((t - gap.start) / inDur))
            }
            if t >= gap.start + inDur && t < gap.end - outDur {
                return play
            }
            if t >= gap.end - outDur && t < gap.end {
                return concertLerp(play, slot, concertEaseInOut((t - (gap.end - outDur)) / outDur))
            }
        }
        return slot
    }

    private func actorState(asset: String, at t: TimeInterval,
                            plan: ConcertPlan, landscape: Bool = false)
        -> (center: CGPoint, scale: CGFloat, rotation: CGFloat, onTrip: Bool) {
        let base = basePosition(asset: asset, at: t, plan: plan, landscape: landscape)
        // (54) Q 透视：行缩放（后排 0.70 → 前排 1.00）；队长再乘 captainScale。
        // (54) U 横屏：行缩放走 L 表（0.78 → 1.00，5 行）。
        let slotRow = landscape
            ? (plan.slotOfLandscape[asset] ?? 0) / PetConcertConst.gridColsL
            : (plan.slotOf[asset] ?? 0) / PetConcertConst.gridCols
        let formScale = landscape ? PetConcertConst.formationScaleL(row: slotRow)
            : PetConcertConst.formationScale(row: slotRow)
        let soloPoint = landscape
            ? CGPoint(x: PetConcertConst.soloXL, y: PetConcertConst.soloYL)
            : CGPoint(x: PetConcertConst.soloX, y: PetConcertConst.soloY)
        let soloScaleValue = landscape ? PetConcertConst.soloScaleL
            : PetConcertConst.soloScale
        var scale: CGFloat = formScale
            * (asset == plan.captain ? PetConcertConst.captainScale : 1)
        let phase = plan.phase(at: t)

        // 跑位覆盖（独唱者）。连唱时相邻 trip 窗口重叠，必须
        // 按行号确定性取最早一条（字典序任意会随机跳变），
        // 续唱衔接由下方 nextTrip 分支处理。
        let trip = plan.tripsByLine.values
            .filter { $0.singer == asset && t >= $0.depart && t < $0.returnEnd }
            .sorted { $0.lineIndex < $1.lineIndex }
            .first
        if let trip {
            let solo = soloPoint
            // 连唱：下一行同为本只且其 depart 已到 → 停在独唱位。
            let nextTrip = plan.tripsByLine[trip.lineIndex + 1]
            if t >= trip.returnStart, let next = nextTrip,
               next.singer == asset, t >= next.depart {
                return (solo, soloScaleValue, 0, true)
            }
            if t < trip.arrive {
                let u = concertEaseInOut((t - trip.depart) / (trip.arrive - trip.depart))
                let from = basePosition(asset: asset, at: trip.depart, plan: plan, landscape: landscape)
                return (concertBezier(from, solo, lift: PetConcertConst.bezierLift, u),
                        concertLerp(formScale, soloScaleValue, u), 0, true)
            }
            if t < trip.returnStart {
                return (solo, soloScaleValue, 0, true)
            }
            let u = concertEaseInOut((t - trip.returnStart) / (trip.returnEnd - trip.returnStart))
            let to = basePosition(asset: asset, at: trip.returnEnd, plan: plan, landscape: landscape)
            return (concertBezier(solo, to, lift: PetConcertConst.bezierLift, u),
                    concertLerp(soloScaleValue, formScale, u), 0, true)
        }

        // 通道预订（(60) 9③）：同一演员同一时间窗只许一个
        // 动作占用 transform/torso/head/bubble/arms 通道。
        // 优先级：歌曲同步动作（独唱跑位 trip 已在上方先行
        // 返回、天然最高）> 间奏耳语倾身（cue 窗内的说话人
        // 与其配对伙伴）> 装饰动作（间奏弹跳让路，见下方
        // 弹跳分支的 !interludeWhisperActive 守卫）。
        let interludeWhisperActive = phase == .interlude
            && plan.interludeCues.contains {
                t >= $0.start && t < $0.end
                    && ($0.asset == asset
                        || plan.whisperPartnerOf[$0.asset] == asset)
            }
        // 队形内动态（闲晃/律动/间奏跳/告别鞠躬）。
        var center = base
        let swayPhase = plan.swayPhaseOf[asset] ?? 0
        let inFormation: Bool
        switch phase {
        case .formation, .greeting, .preludeChat, .singing1, .singing2, .farewell, .ended:
            inFormation = t >= plan.formAt
        default:
            inFormation = false
        }
        // 前排舞步（(65) A 组，v3b 模板 star_dance）：演唱
        // 相位下末行整排跳舞（弹跳/摇摆/倾斜/逐列错峰旋
        // 转），替代本排的通用闲晃与下方群唱前排蹦；仪式
        // 相位（招呼/耳语/告别）与间奏玩耍位不抢——那些
        // 相位 dancing 恒假、既有编排原样。
        let isFrontRow = slotRow == (landscape
            ? PetConcertConst.gridRowsL - 1 : PetConcertConst.gridRows - 1)
        let dancing = isFrontRow
            && (phase == .singing1 || phase == .singing2)
            && t >= plan.formAt
        var rotation: CGFloat = 0
        if dancing {
            let cols = landscape ? PetConcertConst.gridColsL
                : PetConcertConst.gridCols
            let slot = landscape ? (plan.slotOfLandscape[asset] ?? 0)
                : (plan.slotOf[asset] ?? 0)
            let d = PetConcertFrontRow.dance(
                column: slot % cols, columns: cols, at: t)
            center.x += d.dx
            center.y += d.dy
            rotation = d.rotation
        }
        if inFormation && !dancing {
            let freqMul = phase == .farewell || phase == .ended ? 0.5 : 1.0
            center.x += 2 * CGFloat(sin(1.3 * t * freqMul + swayPhase))
            center.y += 1.5 * CGFloat(sin(1.7 * t * freqMul + swayPhase * 1.7))
            if phase == .singing1 || phase == .singing2 {
                center.y -= abs(CGFloat(sin(2.6 * t + swayPhase))) * 3
            }
        }
        // 打招呼动作（(54) T）：全员面向观众轻跳致意——动图
        // 池成员播自带挥手/招手帧（dog-05 招手、dog-16 挥
        // 手、cat-18 挥爪等既有帧），静帧成员用此通用轻跳
        // （两下、包络收尾）替代，不生造帧。进度由相位窗
        // 纯函数推导，seek 可重建。
        if phase == .greeting, let greetAt = plan.greetAt,
           plan.greetingDuration > 0 {
            let u = min(max((t - greetAt) / plan.greetingDuration, 0), 1)
            let envelope = sin(u * Double.pi)
            center.y -= CGFloat(abs(sin(u * Double.pi * 2 + swayPhase * 0.15))
                * 9 * envelope)
            scale *= 1 + 0.05 * CGFloat(envelope)
        }
        // 交头接耳动作（(54) T，(60) 9③ 扩到间奏）：配对成
        // 员在耳语窗内向伙伴贴近（位移向伙伴槽位、封顶 16
        // 参考 px）并微微下倾（y +3），呈现成对倾身；无配
        // 对者保持闲晃。间奏只在 cue 激活窗内倾身（通道预
        // 订，见 interludeWhisperActive），其余时间走玩耍位。
        if phase == .preludeChat || interludeWhisperActive,
           let partner = plan.whisperPartnerOf[asset],
           let partnerSlot = (landscape ? plan.slotOfLandscape[partner]
                                  : plan.slotOf[partner]) {
            let target = ConcertPlan.slotPoint(partnerSlot, landscape: landscape)
            var dx = target.x - base.x, dy = target.y - base.y
            let len = max(1, hypot(dx, dy))
            let step = min(16, len * 0.22)
            dx = dx / len * step; dy = dy / len * step
            center.x += dx
            center.y += dy + 3
        }
        // 告别动作（(54) T）：全员缓幅挥别式轻晃（与曲终
        // 0.65s 鞠躬叠加，鞠躬在下方既有逻辑）。
        if phase == .farewell {
            center.y -= abs(CGFloat(sin(2.2 * t + swayPhase))) * 5
        }
        if phase == .interlude, !interludeWhisperActive,
           let gap = plan.interlude,
           t >= gap.start + 0.45, t < gap.end - 0.55 {
            // (55) B：16 → 12——玩耍位 y 抖动上限 30（竖屏）
            // 与弹跳同向叠加时 30+12=42 < 最小格半高 44，中
            // 心不出玩耍格（横屏 35+12=47 < 55 同理）。
            let amp = 12 * CGFloat(gap.intensity)
            center.y -= abs(CGFloat(sin(5 * t + swayPhase))) * amp
        }
        // 群唱行：前排两排齐蹦。（65）前排本体在演唱相位
        // 跳舞步（dancing），群唱蹦让位于它、只余倒数第二
        // 排照旧。
        if let lineId = currentLine(at: t, plan: plan),
           plan.chorusLines.contains(lineId) {
            let row = landscape
                ? (plan.slotOfLandscape[asset] ?? 0) / PetConcertConst.gridColsL
                : (plan.slotOf[asset] ?? 0) / PetConcertConst.gridCols
            if !dancing, row >= (landscape ? PetConcertConst.gridRowsL - 2
                          : PetConcertConst.gridRows - 2) {
                center.y -= abs(CGFloat(sin(6 * t + swayPhase))) * 10
            }
        }
        // 曲终鞠躬（末 0.65s 下沉，v3 bow 口径）。
        if t >= plan.duration - 0.65, plan.duration > 0 {
            let u = min(max((t - (plan.duration - 0.65)) / 0.3, 0), 1)
            let s = u * u * (3 - 2 * u)
            center.y += 13 * CGFloat(s)
            scale *= 1 - 0.03 * CGFloat(s)
        }
        return (center, scale, rotation, false)
    }

    private func refToStage(_ point: CGPoint, size: CGSize,
                            landscape: Bool = false) -> CGPoint {
        let rw = landscape ? PetConcertConst.refWL : PetConcertConst.refW
        let rh = landscape ? PetConcertConst.refHL : PetConcertConst.refH
        return CGPoint(x: point.x * size.width / rw,
                       y: point.y * size.height / rh)
    }

    // MARK: 气泡与提词条

    private func updateBubble(position: TimeInterval, phase: ConcertPhase,
                              plan: ConcertPlan, singerAsset: String?,
                              soloLine: Int?, size: CGSize) {
        // 队长口令（列队相位，逐字原样）。口令指向队长本人，
        // 现有追光不指向队长，故队长不发光（(54) S 一致处理）。
        if phase == .formation {
            let captain = actors[plan.captain]
            let tip = CGPoint(
                x: (captain?.center.x ?? size.width / 2),
                y: (captain?.frame.minY ?? size.height * 0.6) - 6)
            bubbleView.show(key: "captain", text: "稍息，立正",
                            fontRefPx: PetConcertConst.bubbleFontCaptain,
                            tip: tip, stageSize: size)
            return
        }
        // 打招呼（(54) T）：列队落定后、开唱前，队长与前
        // 排代表向观众致意；头顶小气泡（非歌词不套整行专
        // 区），与队长口令前后相继、互不重叠。
        if phase == .greeting,
           let cue = plan.cue(in: plan.greetingCues, at: position),
           let actor = actors[cue.asset] {
            bubbleView.show(
                key: "greet-\(cue.asset)-\(cue.start)",
                text: cue.text, fontRefPx: PetConcertConst.bubbleFontChat,
                tip: CGPoint(x: actor.center.x, y: actor.frame.minY - 6),
                stageSize: size)
            return
        }
        // 前奏闲聊 / 间奏耳语（(60) 9③）/ 告别关心（cue 表
        // 驱动，非歌词不套整行专区）。
        let cues = phase == .preludeChat ? plan.chatCues
            : (phase == .farewell ? plan.farewellCues
               : (phase == .interlude ? plan.interludeCues : []))
        if let cue = cues.first(where: { position >= $0.start && position < $0.end }),
           let actor = actors[cue.asset] {
            bubbleView.show(
                key: "cue-\(phase.rawValue)-\(cue.asset)-\(cue.start)",
                text: cue.text, fontRefPx: PetConcertConst.bubbleFontChat,
                tip: CGPoint(x: actor.center.x, y: actor.frame.minY - 6),
                stageSize: size)
            return
        }
        // 歌词行（轮唱/群唱）：(62) 胶囊版起不再走头顶气泡
        // ——歌词统一由主胶囊呈现（updateCapsule：当前行扫
        // 光 + 下一行预览，固定背景带）；气泡只余仪式口令/
        // 闲聊/告别等非歌词言语。歌词在唱时气泡收起。
        if soloLine != nil {
            bubbleView.hide()
            return
        }
        if let lineId = currentLine(at: position, plan: plan),
           plan.chorusLines.contains(lineId) {
            bubbleView.hide()
            return
        }
        bubbleView.hide()
    }

    /// 主胶囊歌词（(62) 胶囊版）：当前行（独唱或群唱）进胶
    /// 囊行一逐词扫光、下一行进行二弱化预览；无当前行（仪
    /// 式/间奏无词段）胶囊隐藏。徽记物种随独唱者（群唱行沿
    /// 用上一物种），换人弹跳在 CapsuleView.setLine 内。
    private func updateCapsule(position: TimeInterval, plan: ConcertPlan,
                               size: CGSize) {
        let landscape = PetConcertConst.isLandscape(size)
        let sx = size.width / (landscape ? PetConcertConst.refWL
                                          : PetConcertConst.refW)
        guard let lineId = currentLine(at: position, plan: plan),
              let line = plan.lines.first(where: { $0.id == lineId }) else {
            capsuleView.isHidden = true
            capsuleSparkleView.isHidden = true
            lastCapsuleLineId = nil
            return
        }
        capsuleView.isHidden = false
        capsuleSparkleView.isHidden = false
        let next = plan.lines
            .filter { $0.start > line.start }
            .min(by: { $0.start < $1.start })
        let species = plan.singerByLine[lineId]
            .map { $0.hasPrefix("dog") ? "dog" : "cat" }
            ?? lastCapsuleSpecies
        if lineId != lastCapsuleLineId {
            let speciesChanged = species != lastCapsuleSpecies
            lastCapsuleLineId = lineId
            lastCapsuleSpecies = species
            capsuleView.setLine(
                current: line.text, next: next?.text,
                words: line.words, sx: sx, species: species,
                speciesChanged: speciesChanged,
                animated: capsuleView.superview != nil)
            Breadcrumbs.log("concert.capsule line=\(lineId)"
                + " species=\(species) next=\(next != nil)")
        }
        // 扫光进度：有逐字戳走查表（wordProgress 表未就绪回
        // -1），否则行内时间比例。
        var progress = capsuleView.wordProgress(
            words: line.words ?? [], now: position)
        if progress < 0 {
            let span = max(0.1, line.end - line.start)
            progress = min(max((position - line.start) / span, 0), 1)
        }
        capsuleView.setProgress(progress)
        // 上缘闪光：5 颗沿胶囊顶边稀疏分布，位置/明暗由歌曲
        // 时间确定性驱动（v2 样片 fx 与相位口径）。
        let frame = capsuleSparkleView.frame
        let fxs: [CGFloat] = [0.16, 0.36, 0.58, 0.80, 0.93]
        for (i, layer) in capsuleSparkleLayers.enumerated() {
            let tw = 0.5 + 0.5 * sin(position * 2.2 + Double(i) * 2.3)
            let s = (8 + 7 * tw) * sx * 1.6
            let cx = frame.width * fxs[i]
            let cy = frame.height / 2 + 3 * sin(position * 1.3
                                               + Double(i) * 1.7) * sx * 2
            var path = UIBezierPath()
            for k in 0..<8 {
                let ang = Double(k) * Double.pi / 4 - Double.pi / 2
                let rad = k % 2 == 0 ? s : s * 0.3
                let p = CGPoint(x: cx + rad * cos(ang), y: cy + rad * sin(ang))
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.close()
            layer.path = path.cgPath
            layer.opacity = Float(0.35 + 0.6 * tw)
        }
    }

    // (65) A 组：updateTeleprompter 随底部提词小胶囊一并
    // 摘除（见 init 处注释）——歌词呈现只走上方主胶囊。

    // MARK: 布局

    /// 上次落面包屑的布局尺寸（旋转检测：尺寸变即重排+记录）。
    private var lastLayoutLoggedSize: CGSize = .zero
    /// (60) 5② concert.probe：layout/tick 代次计数与探针状态。
    private var layoutGen = 0
    private var tickGen = 0
    private var probeOrientation: Bool?
    private var probeItems: [DispatchWorkItem] = []

    private func performLayout() {
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        layoutGen += 1
        // (55) B 第 1 项域内口径：本渲染器全部子层（背景/灯
        // 光/宠物/幕布/气泡/提词条）一律 = 容器 bounds、内部
        // 映射走等比拉伸（refToStage 的 sx/sy 独立换算），无
        // 任何 aspect-fit 留带——横屏信箱化的唯一来源是宿主
        // StageViewController.layoutStage 给 rendererContainer
        // 的限高 frame（域外，精确位置与改法见 (55) B 报告）。
        // concert.hostframe 面包屑记录容器 vs 窗口的覆盖率，
        // 供集成后真机核验宿主修复是否生效（cover < 1 = 宿主
        // 仍在限高/限宽）。
        backdropView.frame = bounds
        backdropView.setNeedsDisplay()
        lightView.frame = bounds
        curtainView.frame = bounds
        petField.frame = bounds
        // (54) U 旋转重排：容器尺寸一变，全部站位在下一帧
        // frameTick 按新朝向参考系重算（plan + position 纯函
        // 数，无运行期累积位置）。(65) A 组：朝向翻转时前
        // 排副本归属/相位随新网格重刷（见本方法末尾）。
        if bounds.size != lastLayoutLoggedSize {
            let first = lastLayoutLoggedSize == .zero
            lastLayoutLoggedSize = bounds.size
            // (60) 5②：朝向翻转触发 concert.probe 采样列。
            let landNow = PetConcertConst.isLandscape(bounds.size)
            if let prev = probeOrientation, prev != landNow {
                startConcertProbe()
            }
            probeOrientation = landNow
            if !first || plan != nil {
                let land = PetConcertConst.isLandscape(bounds.size)
                let f: String, so: String
                if land {
                    f = "(0.088,0.255)-(0.913,0.764)"
                    so = "(0.500,0.831)"
                } else {
                    f = "(0.111,0.283)-(0.889,0.750)"
                    so = "(0.500,0.842)"
                }
                Breadcrumbs.log("concert.layout orient=\(land ? "landscape" : "portrait")"
                    + " size=\(Int(bounds.width))x\(Int(bounds.height))"
                    + " formation=\(f) solo=\(so)")
                if let win = rootView.window?.bounds.size, win.width > 0 {
                    let cover = (bounds.width * bounds.height)
                        / (win.width * win.height)
                    Breadcrumbs.log("concert.hostframe container="
                        + "\(Int(bounds.width))x\(Int(bounds.height))"
                        + " window=\(Int(win.width))x\(Int(win.height))"
                        + " cover=\(String(format: "%.3f", cover))")
                }
            }
        }
        let landscape = PetConcertConst.isLandscape(bounds.size)
        let sx = bounds.width / (landscape ? PetConcertConst.refWL : PetConcertConst.refW)
        let sy = bounds.height / (landscape ? PetConcertConst.refHL : PetConcertConst.refH)
        // (62) 胶囊版：主胶囊落背景带（竖屏参考 (210,300)
        // 660×164＝垂幔下沿 ~250 至地板起点 556 之间，不压
        // 队形；横屏同带口径 (630,140) 660×130），(65) 不动。
        if landscape {
            capsuleView.frame = CGRect(x: 630 * sx, y: 140 * sy,
                                       width: 660 * sx, height: 130 * sy)
        } else {
            capsuleView.frame = CGRect(x: 210 * sx, y: 300 * sy,
                                       width: 660 * sx, height: 164 * sy)
        }
        capsuleSparkleView.frame = capsuleView.frame
            .insetBy(dx: 0, dy: -24 * sy)
        capsuleView.setNeedsLayout()
        // 迷你麦（(65) A 组，v3b 口径替 (62) 的 v2×0.7）：
        // 全部尺寸由独唱者身高 singerH（petBase×soloScale，
        // 参考 px）按比例推导、横竖屏同式——麦总高
        // micH = 0.55·singerH；麦头半径 = 0.13·micH（绘图
        // 侧设计空间 100×128 里 mic 段占 112，见
        // PetConcertMicView）；杆轴落独唱点左 0.15·singerH；
        // 底座中心落脚线下 0.06·singerH。麦头顶因此落在
        // 独唱者身高约 45% 处＝胸口高（模板实测口径）。
        let singerH = (landscape ? PetConcertConst.petBaseL
                          : PetConcertConst.petBase)
            * (landscape ? PetConcertConst.soloScaleL
                  : PetConcertConst.soloScale)
        let micH = 0.55 * singerH
        let micFrameH = micH * (128.0 / 112.0)
        let micFrameW = micFrameH * (100.0 / 128.0)
        let soloRefX = landscape ? PetConcertConst.soloXL
            : PetConcertConst.soloX
        let soloRefY = landscape ? PetConcertConst.soloYL
            : PetConcertConst.soloY
        let poleRefX = soloRefX - 0.15 * singerH
        let baseRefY = soloRefY + singerH / 2 + 0.06 * singerH
        micView.frame = CGRect(
            x: (poleRefX - 0.46 * micFrameW) * sx,
            y: (baseRefY - (116.0 / 128.0) * micFrameH) * sy,
            width: micFrameW * sx, height: micFrameH * sy)
        micView.setNeedsDisplay()
        // (65) A 组：前排副本按当前朝向刷新（内部按
        // copyOrientation 自守，朝向未变时为空转）。
        refreshFrontRowCopies()
    }

    /// 前排副本刷新（3.7 (65) A 组）：按当前朝向的槽位表
    /// 判定末行成员，逐只开/关副本呈现并注入该列相位帧偏
    /// 移；后排阵容、槽位分配、计划层一概不动。建团与旋
    /// 转换向各走一次（copyOrientation 自守去重）。
    private func refreshFrontRowCopies() {
        guard let plan, rootView.bounds.width > 0 else { return }
        let landscape = PetConcertConst.isLandscape(rootView.bounds.size)
        guard copyOrientation != landscape else { return }
        copyOrientation = landscape
        let cols = landscape ? PetConcertConst.gridColsL
            : PetConcertConst.gridCols
        let rows = landscape ? PetConcertConst.gridRowsL
            : PetConcertConst.gridRows
        var count = 0
        for (asset, actor) in actors {
            let slot = (landscape ? plan.slotOfLandscape[asset]
                : plan.slotOf[asset]) ?? 0
            if slot / cols == rows - 1 {
                count += 1
                actor.setFrontRowCopy(
                    active: true,
                    phaseOffsetMs: PetConcertFrontRow.frameOffsetMs(
                        column: slot % cols, columns: cols),
                    animatedAvailable: !atmosphereReduced)
            } else {
                actor.setFrontRowCopy(
                    active: false, phaseOffsetMs: 0,
                    animatedAvailable: false)
            }
        }
        Breadcrumbs.log("concert.copies n=\(count)"
            + " orient=\(landscape ? "L" : "P")")
    }

    // MARK: (60) 5② concert.probe（横屏半幅未定级取证探针）
    //
    // 旋转（朝向翻转）时由 performLayout 触发，其后 0.5s×6
    // 采样：容器覆盖率、队形包围盒（归一化 + 像素）、六层
    // frame、layout/tick 代次、chrome 遮挡比。只读采样、
    // 不改任何几何；演唱会退出（unmount/destroyed）即停。

    private func startConcertProbe() {
        cancelConcertProbe()
        for i in 1...6 {
            let item = DispatchWorkItem { [weak self] in
                self?.logConcertProbe(index: i)
            }
            probeItems.append(item)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.5 * Double(i), execute: item)
        }
    }

    private func cancelConcertProbe() {
        probeItems.forEach { $0.cancel() }
        probeItems.removeAll()
    }

    private func logConcertProbe(index: Int) {
        let bounds = rootView.bounds
        guard bounds.width > 0, let plan else { return }
        let land = PetConcertConst.isLandscape(bounds.size)
        let refW = land ? PetConcertConst.refWL : PetConcertConst.refW
        let refH = land ? PetConcertConst.refHL : PetConcertConst.refH
        let sx = bounds.width / refW, sy = bounds.height / refH
        // 队形包围盒：当前朝向全部已占格位的并集（参考 px）。
        var union = CGRect.null
        let slots = land ? plan.slotOfLandscape : plan.slotOf
        for slot in Set(slots.values) {
            union = union.union(
                ConcertPlan.slotCellRect(slot, landscape: land))
        }
        let bboxN = union.isNull ? "none"
            : String(format: "(%.3f,%.3f)-(%.3f,%.3f)",
                     union.minX / refW, union.minY / refH,
                     union.maxX / refW, union.maxY / refH)
        let bboxPx = union.isNull ? "none"
            : "\(Int(union.minX * sx)),\(Int(union.minY * sy)),"
                + "\(Int(union.width * sx)),\(Int(union.height * sy))"
        let cover: Double
        if let win = rootView.window?.bounds.size, win.width > 0, win.height > 0 {
            cover = Double(bounds.width * bounds.height)
                / Double(win.width * win.height)
        } else { cover = 0 }
        func rectStr(_ v: UIView) -> String {
            let f = v.frame
            return "\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))"
        }
        Breadcrumbs.log("concert.probe i=\(index)"
            + " cover=\(String(format: "%.3f", cover))"
            + " bboxN=\(bboxN) bboxPx=\(bboxPx)"
            + " frames[curtain=\(rectStr(curtainView))"
            + "/floor=\(rectStr(backdropView))"
            + "/bubble=\(rectStr(bubbleView))"
            + "/spot=\(rectStr(lightView))"
            + "/bg=\(rectStr(backdropView))]"
            + " gen[layout=\(layoutGen)/tick=\(tickGen)]"
            + " occ=\(String(format: "%.3f", chromeOcclusionRatio()))")
    }

    /// chrome 遮挡比：视图层级中位于本容器之上、与容器在
    /// 窗口坐标内相交的兄弟视图（点播台/顶栏等宿主 chrome）
    /// 覆盖容器面积的比例（多 rect 面积和、上限 1）。
    private func chromeOcclusionRatio() -> Double {
        guard let window = rootView.window, rootView.bounds.width > 0
        else { return 0 }
        let mine = rootView.convert(rootView.bounds, to: window)
        guard mine.width > 0, mine.height > 0 else { return 0 }
        var covered: CGFloat = 0
        var child: UIView = rootView
        while let parent = child.superview {
            if let idx = parent.subviews.firstIndex(of: child) {
                for sib in parent.subviews[(idx + 1)...] {
                    guard !sib.isHidden, sib.alpha > 0.01 else { continue }
                    let r = sib.convert(sib.bounds, to: window)
                        .intersection(mine)
                    if !r.isNull, !r.isEmpty {
                        covered += r.width * r.height
                    }
                }
            }
            if parent === window { break }
            child = parent
        }
        return min(1, Double(covered / (mine.width * mine.height)))
    }
}

// MARK: - 立式麦克风（(62) 胶囊版立、(65) 改 v3b 迷你口径）
//
// 贴纸风立麦：奶油球形麦头（焦糖格栅）+ 焦糖杆身 + 圆形配
// 重底座。(62) 版为 v2 样片 ×0.7（麦高约与独唱者等高）；
// (65) 按 v3b 定版改迷你口径：麦总高 = 0.55×独唱者身高、
// 麦头半径 = 0.13×麦高、麦头顶落在胸口高（模板 draw_mic
// 逐项比例）。设计空间 100×128：麦段（底座中心 y=116 到
// 麦头顶 y=4）占 112 单位，渲染方按 micH 反推 frame（高
// = micH×128/112、杆轴在本地 x=46）。视图挂 petField 之
// 上（样片口径：宠物先画、麦后画，独唱者站麦后），纯装
// 饰、不吃手势。

final class PetConcertMicView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func draw(_ rect: CGRect) {
        let ux = bounds.width / 100
        let uy = bounds.height / 128
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * ux, y: y * uy)
        }
        let outline = UIColor(red: 110 / 255, green: 74 / 255, blue: 47 / 255, alpha: 1)
        let caramel = UIColor(red: 176 / 255, green: 128 / 255, blue: 74 / 255, alpha: 1)
        let caramelDark = UIColor(red: 146 / 255, green: 100 / 255, blue: 54 / 255, alpha: 1)
        let cream = UIColor(red: 250 / 255, green: 240 / 255, blue: 220 / 255, alpha: 1)
        // 圆形配重底座：中心 (46,116)、宽 0.42·micH（设计
        // 47）、高 13（外圈深焦糖 + 内圈焦糖）。
        let basePath = UIBezierPath(ovalIn: CGRect(
            x: 22.5 * ux, y: 109.5 * uy, width: 47 * ux, height: 13 * uy))
        caramelDark.setFill(); basePath.fill()
        outline.setStroke(); basePath.lineWidth = 3 * ux; basePath.stroke()
        let baseIn = UIBezierPath(ovalIn: CGRect(
            x: 31 * ux, y: 111 * uy, width: 30 * ux, height: 8 * uy))
        caramel.setFill(); baseIn.fill()
        // 杆身：自底座 (46,114) 直达麦头下缘 (46,31)（轮廓
        // 道 + 内道，模板杆宽比同口径）。
        let pole = UIBezierPath()
        pole.move(to: pt(46, 114)); pole.addLine(to: pt(46, 31))
        outline.setStroke(); pole.lineWidth = 8 * ux; pole.stroke()
        let poleIn = UIBezierPath()
        poleIn.move(to: pt(46, 114)); poleIn.addLine(to: pt(46, 31))
        caramel.setStroke(); poleIn.lineWidth = 4.5 * ux; poleIn.stroke()
        // 领口（奶油圆角块）：中心 (46,69)＝底座上 0.42·micH
        // 处（模板 collar_y 口径），15×15。
        let collar = UIBezierPath(
            roundedRect: CGRect(x: 38.5 * ux, y: 61.5 * uy,
                                width: 15 * ux, height: 15 * uy),
            cornerRadius: 4 * ux)
        cream.setFill(); collar.fill()
        outline.setStroke(); collar.lineWidth = 2.5 * ux; collar.stroke()
        // 球形麦头：中心 (48,19)、半径 15（=0.13·112 设计
        // 口径）；奶油球 + 焦糖横格栅弧（模板三弧 k=−0.55/
        // 0/0.55）+ 中央带 + 高光。
        let head = UIBezierPath(ovalIn: CGRect(
            x: 33 * ux, y: 4 * uy, width: 30 * ux, height: 30 * uy))
        cream.setFill(); head.fill()
        outline.setStroke(); head.lineWidth = 3 * ux; head.stroke()
        caramel.setStroke()
        for k in [-0.55, 0, 0.55] as [CGFloat] {
            let yy = 19 + k * 15
            let half = sqrt(max(1, 1 - k * k)) * 12.5
            let arc = UIBezierPath()
            arc.move(to: pt(48 - half, yy))
            arc.addQuadCurve(to: pt(48 + half, yy),
                             controlPoint: pt(48, yy + 5))
            arc.lineWidth = 1.8 * ux; arc.stroke()
        }
        let band = UIBezierPath()
        band.move(to: pt(35, 19)); band.addLine(to: pt(61, 19))
        caramelDark.setStroke(); band.lineWidth = 3 * ux; band.stroke()
        let shine = UIBezierPath(ovalIn: CGRect(
            x: 39.5 * ux, y: 7.5 * uy, width: 4.4 * ux, height: 4.4 * uy))
        UIColor.white.setFill(); shine.fill()
    }
}

// MARK: - 爪印徽记（胶囊框角，物种切换）

/// 圆徽：奶油底 + 焦糖环 + 爪印（猫＝粉爪无爪尖、狗＝棕爪
/// 带爪尖，v2 样片 draw_badge/draw_paw_flat 口径）。draw 式
/// 绘制，species 变化时 setNeedsDisplay。
final class PetConcertBadgeView: UIView {
    var species = "cat" { didSet { if species != oldValue { setNeedsDisplay() } } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func draw(_ rect: CGRect) {
        let s = min(bounds.width, bounds.height)
        let u = s / 108
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let circle = UIBezierPath(ovalIn: CGRect(
            x: center.x - 46 * u, y: center.y - 46 * u,
            width: 92 * u, height: 92 * u))
        UIColor(red: 255 / 255, green: 250 / 255, blue: 238 / 255, alpha: 1).setFill()
        circle.fill()
        UIColor(red: 196 / 255, green: 150 / 255, blue: 90 / 255, alpha: 1).setStroke()
        circle.lineWidth = 6 * u; circle.stroke()
        // 爪印：主垫 + 四趾（相对爪心 (0, +6u) 起，s=44 口径）。
        let pawColor = species == "dog"
            ? UIColor(red: 156 / 255, green: 108 / 255, blue: 66 / 255, alpha: 1)
            : UIColor(red: 238 / 255, green: 138 / 255, blue: 158 / 255, alpha: 1)
        pawColor.setFill()
        let pc = CGPoint(x: center.x, y: center.y + 6 * u)
        let pad = UIBezierPath(ovalIn: CGRect(
            x: pc.x - 22 * u, y: pc.y - 1 * u, width: 44 * u, height: 32 * u))
        pad.fill()
        let toes: [(CGFloat, CGFloat, CGFloat)] = [
            (-26.4, -17.6, 13.2), (-8.8, -26.4, 14.1),
            (8.8, -26.4, 14.1), (26.4, -17.6, 13.2)]
        for (dx, dy, rr) in toes {
            let toe = UIBezierPath(ovalIn: CGRect(
                x: pc.x + (dx - rr / 2) * u, y: pc.y + (dy - rr / 2) * u,
                width: rr * u, height: rr * u))
            toe.fill()
            if species == "dog" {
                let claw = UIBezierPath()
                let mx = pc.x + dx * u
                let top = pc.y + (dy - rr / 2) * u
                claw.move(to: CGPoint(x: mx - 3 * u, y: top + 2 * u))
                claw.addLine(to: CGPoint(x: mx + 3 * u, y: top + 2 * u))
                claw.addLine(to: CGPoint(x: mx, y: top - 9 * u))
                claw.close()
                claw.fill()
            }
        }
    }
}

// MARK: - 胶囊歌词板（(62) 胶囊歌词版，v2 样片验收口径）
//
// 主胶囊：毛玻璃（背景模糊 + 白洗 + 顶部高光 + 白描边），
// 固定嵌垂幔下方至地板起点之间的背景带（竖屏参考
// (210,300) 660×164），不压队形。行一＝当前独唱/群唱行
// （深棕字 + 逐词扫光：未唱 38% 透明 → 已唱全色，mask 按
// 词宽前缀推进）；行二＝下一行（同材质弱化）。换行交叉淡
// 化 0.3s + 胶囊轻脉动 1.03；框角爪印徽记按独唱物种切
// 换、换人弹跳。上缘 5 颗闪光由渲染器逐 tick 驱动（同文件
// capsuleSparkleView）。文字不截断：字号 45→30 参考 px 逐
// 档适配，仍溢出由 adjustsFontSizeToFitWidth 兜底缩放。

final class PetConcertCapsuleView: UIView {
    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
    private let washView = UIView()
    private let sheenView = UIView()
    private let borderLayer = CAShapeLayer()
    private let row1Dim = UILabel()
    private let row1Bright = UILabel()
    private let row1Mask = CALayer()
    private let row2Label = UILabel()
    let badgeView = PetConcertBadgeView()
    private var row1TextWidth: CGFloat = 0
    private var prefixWidths: [CGFloat] = []
    private var wordWidths: [CGFloat] = []
    private var hasNext = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        blurView.clipsToBounds = true
        addSubview(blurView)
        washView.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        addSubview(washView)
        sheenView.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        addSubview(sheenView)
        let textDark = UIColor(red: 62 / 255, green: 45 / 255, blue: 32 / 255, alpha: 1)
        for label in [row1Dim, row1Bright, row2Label] {
            label.textAlignment = .center
            label.numberOfLines = 1
            label.lineBreakMode = .byClipping
            addSubview(label)
        }
        row1Dim.textColor = textDark.withAlphaComponent(0.38)
        row1Bright.textColor = textDark
        row2Label.textColor = textDark.withAlphaComponent(0.72)
        row1Bright.layer.mask = row1Mask
        row1Mask.backgroundColor = UIColor.black.cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
        layer.addSublayer(borderLayer)
        addSubview(badgeView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = bounds.height / 2
        blurView.frame = bounds
        blurView.layer.cornerRadius = radius
        washView.frame = bounds
        washView.layer.cornerRadius = radius
        washView.clipsToBounds = true
        sheenView.frame = CGRect(x: 6, y: 5, width: bounds.width - 12,
                                 height: bounds.height / 2)
        sheenView.layer.cornerRadius = bounds.height / 4
        sheenView.clipsToBounds = true
        borderLayer.frame = bounds
        borderLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
            cornerRadius: radius - 1.5).cgPath
        borderLayer.lineWidth = 2
        let rowH = bounds.height * 62 / 164
        if hasNext {
            row1Dim.frame = CGRect(x: 0, y: bounds.height * 51 / 164 - rowH / 2,
                                   width: bounds.width, height: rowH)
            row2Label.frame = CGRect(x: 0, y: bounds.height * 113 / 164 - rowH / 2,
                                     width: bounds.width, height: rowH)
        } else {
            row1Dim.frame = CGRect(x: 0, y: bounds.height / 2 - rowH / 2,
                                   width: bounds.width, height: rowH)
            row2Label.frame = .zero
        }
        row1Bright.frame = row1Dim.frame
        let badgeSide = bounds.height * 108 / 164
        badgeView.frame = CGRect(
            x: 4 * bounds.width / 660 - badgeSide / 2,
            y: 2 * bounds.height / 164 - badgeSide / 2,
            width: badgeSide, height: badgeSide)
        updateMask(progress: lastProgress)
    }

    private var lastProgress: Double = 0

    /// 换行装配：字号适配（45→30 参考 px）+ 逐字前缀宽表一
    /// 次量好；animated 时行文字交叉淡入 + 胶囊轻脉动；物种
    /// 变化时徽记弹跳切换（系统弹簧口径）。
    func setLine(current: String, next: String?, words: [LyricWord]?,
                 sx: CGFloat, species: String, speciesChanged: Bool,
                 animated: Bool) {
        hasNext = !(next ?? "").isEmpty
        row2Label.isHidden = !hasNext
        let maxW = max(80, bounds.width - 64 * sx)
        let font = Self.fittedFont(text: current, sx: sx, maxW: maxW)
        row1Dim.font = font
        row1Bright.font = font
        row1Dim.text = current
        row1Bright.text = current
        row1Dim.adjustsFontSizeToFitWidth = true
        row1Dim.minimumScaleFactor = 0.7
        row1Bright.adjustsFontSizeToFitWidth = true
        row1Bright.minimumScaleFactor = 0.7
        row1TextWidth = (current as NSString).size(
            withAttributes: [.font: font]).width
        if let next {
            let f2 = Self.fittedFont(text: next, sx: sx, maxW: maxW)
            row2Label.font = f2
            row2Label.text = next
            row2Label.adjustsFontSizeToFitWidth = true
            row2Label.minimumScaleFactor = 0.7
        }
        // 逐字前缀宽表（与行一字号同口径量宽）。
        if let words, !words.isEmpty {
            var prefix: [CGFloat] = [0]
            var widths: [CGFloat] = []
            var acc = ""
            for word in words {
                widths.append((word.text as NSString).size(
                    withAttributes: [.font: font]).width)
                acc += word.text
                prefix.append((acc as NSString).size(
                    withAttributes: [.font: font]).width)
            }
            prefixWidths = prefix
            wordWidths = widths
        } else {
            prefixWidths = []
            wordWidths = []
        }
        badgeView.species = species
        setProgress(0)
        setNeedsLayout()
        if animated {
            for label in [row1Dim, row1Bright, row2Label] {
                label.alpha = 0
                UIView.animate(withDuration: 0.3) { label.alpha = 1 }
            }
            transform = .identity
            UIView.animate(withDuration: 0.25, animations: {
                self.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
            }, completion: { _ in
                UIView.animate(withDuration: 0.25) {
                    self.transform = .identity
                }
            })
            if speciesChanged {
                badgeView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
                UIView.animate(withDuration: 0.35, delay: 0,
                               usingSpringWithDamping: 0.55,
                               initialSpringVelocity: 0.4,
                               options: []) {
                    self.badgeView.transform = .identity
                }
            }
        }
    }

    private static func fittedFont(text: String, sx: CGFloat,
                                   maxW: CGFloat) -> UIFont {
        var size = 45 * sx
        let minSize = 30 * sx
        while size > minSize {
            let font = UIFont.systemFont(ofSize: size, weight: .semibold)
            if (text as NSString).size(withAttributes: [.font: font]).width <= maxW {
                return font
            }
            size -= sx
        }
        return UIFont.systemFont(ofSize: minSize, weight: .semibold)
    }

    /// 逐词进度（查表版）：分子＝已唱前缀宽 + 当前词内插。
    func wordProgress(words: [LyricWord], now: Double) -> Double {
        guard row1TextWidth > 0,
              prefixWidths.count == words.count + 1,
              wordWidths.count == words.count else {
            return -1
        }
        for (i, word) in words.enumerated() {
            if now >= word.end { continue }
            if now >= word.start {
                let frac = word.end > word.start
                    ? (now - word.start) / (word.end - word.start) : 0
                let width = prefixWidths[i] + wordWidths[i] * CGFloat(frac)
                return min(max(Double(width / row1TextWidth), 0), 1)
            }
            return min(max(Double(prefixWidths[i] / row1TextWidth), 0), 1)
        }
        return min(max(Double(prefixWidths[words.count] / row1TextWidth), 0), 1)
    }

    func setProgress(_ progress: Double) {
        lastProgress = progress
        updateMask(progress: progress)
    }

    private func updateMask(progress: Double) {
        // mask.frame 在被遮标签的本地坐标系：文字居中，扫光
        // 自文字左缘起按已唱宽推进。
        let w = row1Bright.bounds.width
        guard w > 0, row1TextWidth > 0 else {
            row1Mask.frame = .zero
            return
        }
        let startX = (w - row1TextWidth) / 2
        row1Mask.frame = CGRect(
            x: startX, y: 0,
            width: row1TextWidth * CGFloat(min(max(progress, 0), 1)),
            height: row1Bright.bounds.height)
    }
}
