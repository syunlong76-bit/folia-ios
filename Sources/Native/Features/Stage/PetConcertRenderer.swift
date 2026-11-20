import UIKit
import QuartzCore
import CoreImage

// 汪汪队开大会 petconcert（3.7 (53) J）：演唱会渲染器。
//
// 中央大歌词隐藏：唱词走上方专区气泡（(54) P+Q：整行全
// 显、不分段、引导线指向独唱者）+ 底部细提词条兜底（整
// 行、不省略）。53 只全员上台：静帧
// atlas（首帧缩到 ≤160px，≈5.4MB）+ 动图池 ≤8 只 StickerView
// （解码成本实测准入、合计 ≤40MB，见 PetConcertConst 红线）。
// 素材优先级：StickersCutout 抠图版 > 原贴纸（本来就透明底）。
//
// 时钟纪律与全舞台一致：只消费宿主 frameTick 的锚点位置；所
// 有位置/相位/气泡都是 plan + position 的函数，seek 后自动
// 重建。降级顺序：先砍氛围（光束/纸屑/闪烁 → 动图池转静帧），
// 永不砍提词条与气泡（歌词可读性）。

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
    /// 尾尖在舞台坐标（showInZone 后有效），供引导线起点。
    private(set) var tailTipInParent: CGPoint?

    // (54) P 整行气泡布局常量（参考 px，1080×1920 参考系）。
    /// 歌词字号下限：44 → 28（与提词条 teleFontMin 同口径，
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
        label.textColor = PetConcertPalette.bubbleText
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

    /// 落位与绘制（show/showInZone 共用）：按实测尺寸定 bounds，
    /// 中心由调用方给（已钳制），尾尖对 anchorX。
    private func apply(key: String, text: String,
                       solved: (font: UIFont, fontRef: CGFloat,
                                size: CGSize, lines: Int),
                       center: CGPoint, anchorX: CGFloat,
                       stageSize: CGSize) {
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
        tailTipInParent = nil // 通用气泡不用引导线
    }

    /// 歌词气泡（(54) P+Q）：整行全文固定落上方专区（垂幔
    /// 之下、队形之上，布局零重叠），横向跟随 anchorX（独唱
    /// 者 x），尾巴对 anchorX，归属再由渲染方引导线补强。
    /// 自适应：常规宽 600 内降字号（44→28）至 ≤3 行；仍放
    /// 不下走 wide——加宽到舞台全宽（留 12 边距）再降字号；
    /// 极端长行 wide+下限仍超 3 行时按实测行数放行（加高），
    /// 任何路径不截断、不省略。wide 触发落面包屑（按 key
    /// 去重，只在切换时记一次）。
    func showInZone(key: String, text: String, fontRefPx: CGFloat,
                    stageSize: CGSize, anchorX: CGFloat) {
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
        let zoneTop = (sc.landscape ? PetConcertConst.bubbleZoneTopL
                          : PetConcertConst.bubbleZoneTop) * sy
        let zoneBottom = (sc.landscape ? PetConcertConst.bubbleZoneBottomL
                             : PetConcertConst.bubbleZoneBottom) * sy
        let cx = min(max(anchorX, bw / 2 + 12 * sx),
                     stageSize.width - bw / 2 - 12 * sx)
        var cy = (zoneTop + zoneBottom) / 2
        if totalH <= zoneBottom - zoneTop {
            cy = min(max(cy, zoneTop + totalH / 2),
                     zoneBottom - totalH / 2)
        }
        apply(key: key, text: text, solved: solved,
              center: CGPoint(x: cx, y: cy), anchorX: anchorX,
              stageSize: stageSize)
    }

    func hide() {
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

    init(asset: String) {
        self.asset = asset
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        stickerView?.frame = bounds
    }

    func setStaticImage(_ image: UIImage?) {
        imageView.image = image
        if stickerView == nil { imageView.isHidden = false }
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
        imageView.isHidden = true
    }

    func detachSticker() {
        stickerView?.removeFromSuperview()
        stickerView = nil
        imageView.isHidden = false
    }
}

// MARK: - 渲染器

final class PetConcertStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: true, requiresSpectrum: false, supportsLineSeek: true)

    private let rootView = LyricStageRootView()
    private let backdropView = PetConcertBackdropView()
    private let curtainView = PetConcertCurtainView()
    private let petField = UIView()
    private let bubbleView = PetConcertBubbleView()
    /// 气泡专区 → 独唱者的引导线（(54) P+Q，金色虚线）。
    private let guideView = UIView()
    private let guideLayer = CAShapeLayer()
    /// 独唱发光（(54) S）：贴纸 alpha 轮廓外发光图，贴在独唱
    /// 宠物身后跟随；本体层不挂任何滤镜/混合，像素零改动。
    private let singerGlowView = UIImageView()
    private var glowCache: [String: UIImage] = [:]
    private var glowAsset: String?
    /// 独唱星点（(54) S）：12 颗小星形，绕独唱者确定性生灭。
    private let sparkleView = UIView()
    private var sparkleLayers: [CAShapeLayer] = []
    private let teleBar = UIView()
    private let teleLabel = UILabel()

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
    private var lastTeleLineId: Int?
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
        petField.isUserInteractionEnabled = false
        rootView.addSubview(petField)
        rootView.addSubview(curtainView)
        // 幕布在宠物之后加：侧幕/垂幔盖住队形上缘是样片口径。
        // (54) S 后幕布层内只剩地板光池/洗光/光束等氛围，不再
        // 有任何盖在独唱宠物身上的染⾊层；发光在 petField 内
        // 贴本体身后生成（singerGlowView/sparkleView）。
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
        guideView.isUserInteractionEnabled = false
        guideLayer.fillColor = nil
        guideLayer.strokeColor = PetConcertPalette.gold
            .withAlphaComponent(0.85).cgColor
        guideLayer.lineCap = .round
        guideView.layer.addSublayer(guideLayer)
        rootView.addSubview(guideView)
        rootView.addSubview(bubbleView)
        bubbleView.isHidden = true
        teleBar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        teleBar.isUserInteractionEnabled = false
        teleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        teleLabel.textAlignment = .center
        teleLabel.lineBreakMode = .byWordWrapping
        teleBar.addSubview(teleLabel)
        rootView.addSubview(teleBar)
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
        if state == .destroyed, relocationActive {
            relocationActive = false
            PetConcertRelocation.shared.endConcert()
        }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let plan, rootView.bounds.width > 0 else { return }
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
            actor.transform = CGAffineTransform(scaleX: state.scale, y: state.scale)
            if asset == singerAsset {
                singerCenter = center
                singerFeetY = center.y + base * state.scale / 2
                singerActor = actor
                singerScale = state.scale
                petField.bringSubviewToFront(actor)
            }
        }

        // 幕布/灯光（氛围层；(54) S 后不再染独唱本体）。
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
        updateTeleprompter(position: position, plan: plan, size: size)
    }

    func unmount() {
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
        hideGuide()
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
        lastTeleLineId = nil

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
            + " farewellCues=\(built.farewellCues.count)")

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
        for asset in admittedAnimated {
            actors[asset]?.detachSticker()
        }
        admittedAnimated.removeAll()
        admittedCost = 0
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
        -> (center: CGPoint, scale: CGFloat) {
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
                return (solo, soloScaleValue)
            }
            if t < trip.arrive {
                let u = concertEaseInOut((t - trip.depart) / (trip.arrive - trip.depart))
                let from = basePosition(asset: asset, at: trip.depart, plan: plan, landscape: landscape)
                return (concertBezier(from, solo, lift: PetConcertConst.bezierLift, u),
                        concertLerp(formScale, soloScaleValue, u))
            }
            if t < trip.returnStart {
                return (solo, soloScaleValue)
            }
            let u = concertEaseInOut((t - trip.returnStart) / (trip.returnEnd - trip.returnStart))
            let to = basePosition(asset: asset, at: trip.returnEnd, plan: plan, landscape: landscape)
            return (concertBezier(solo, to, lift: PetConcertConst.bezierLift, u),
                    concertLerp(soloScaleValue, formScale, u))
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
        if inFormation {
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
        // 交头接耳动作（(54) T）：配对成员在耳语窗内向伙伴
        // 贴近（位移向伙伴槽位、封顶 16 参考 px）并微微下
        // 倾（y +3），呈现成对倾身；无配对者保持闲晃。
        if phase == .preludeChat, let partner = plan.whisperPartnerOf[asset],
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
        if phase == .interlude, let gap = plan.interlude,
           t >= gap.start + 0.45, t < gap.end - 0.55 {
            let amp = 16 * CGFloat(gap.intensity)
            center.y -= abs(CGFloat(sin(5 * t + swayPhase))) * amp
        }
        // 群唱行：前排两排齐蹦。
        if let lineId = currentLine(at: t, plan: plan),
           plan.chorusLines.contains(lineId) {
            let row = landscape
                ? (plan.slotOfLandscape[asset] ?? 0) / PetConcertConst.gridColsL
                : (plan.slotOf[asset] ?? 0) / PetConcertConst.gridCols
            if row >= (landscape ? PetConcertConst.gridRowsL - 2
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
        return (center, scale)
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
        let landscape = PetConcertConst.isLandscape(size)
        let sx = size.width / (landscape ? PetConcertConst.refWL : PetConcertConst.refW)
        let base = (landscape ? PetConcertConst.petBaseL : PetConcertConst.petBase) * sx
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
            hideGuide()
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
            hideGuide()
            return
        }
        // 前奏闲聊 / 告别关心（cue 表驱动，非歌词不套整行专区）。
        let cues = phase == .preludeChat ? plan.chatCues
            : (phase == .farewell ? plan.farewellCues : [])
        if let cue = cues.first(where: { position >= $0.start && position < $0.end }),
           let actor = actors[cue.asset] {
            bubbleView.show(
                key: "cue-\(phase.rawValue)-\(cue.asset)-\(cue.start)",
                text: cue.text, fontRefPx: PetConcertConst.bubbleFontChat,
                tip: CGPoint(x: actor.center.x, y: actor.frame.minY - 6),
                stageSize: size)
            hideGuide()
            return
        }
        // 轮唱气泡（(54) P+Q）：当前行全文进上方专区，key 按
        // 行+唱者粒度——换行/换人当帧即换 key 刷新，不残留
        // 上一行；引导线自气泡尾尖指向独唱者头顶。
        if let soloLine,
           let line = plan.lines.first(where: { $0.id == soloLine }) {
            let singerActor = singerAsset.flatMap { actors[$0] }
            bubbleView.showInZone(
                key: "lyric-\(soloLine)-\(singerAsset ?? "none")",
                text: line.text,
                fontRefPx: PetConcertConst.bubbleFontLyric,
                stageSize: size,
                anchorX: singerActor?.center.x ?? size.width / 2)
            if let singerActor, let tailTip = bubbleView.tailTipInParent {
                updateGuide(from: tailTip,
                            to: CGPoint(x: singerActor.center.x,
                                        y: singerActor.frame.minY + 4))
            } else {
                hideGuide()
            }
            return
        }
        // 群唱行气泡（(54) P+Q）：同样整行进专区，引导线指向
        // 独唱位（群唱的发声锚点），追光圈同步标明。
        if let lineId = currentLine(at: position, plan: plan),
           plan.chorusLines.contains(lineId),
           let line = plan.lines.first(where: { $0.id == lineId }) {
            let soloStage = refToStage(
                landscape ? CGPoint(x: PetConcertConst.soloXL, y: PetConcertConst.soloYL)
                    : CGPoint(x: PetConcertConst.soloX, y: PetConcertConst.soloY),
                size: size, landscape: landscape)
            bubbleView.showInZone(
                key: "chorus-\(lineId)", text: line.text,
                fontRefPx: PetConcertConst.bubbleFontLyric,
                stageSize: size, anchorX: soloStage.x)
            if let tailTip = bubbleView.tailTipInParent {
                updateGuide(from: tailTip,
                            to: CGPoint(x: soloStage.x,
                                        y: soloStage.y - base
                                            * (landscape ? PetConcertConst.soloScaleL
                                                  : PetConcertConst.soloScale) / 2))
            } else {
                hideGuide()
            }
            return
        }
        bubbleView.hide()
        hideGuide()
    }

    private func updateGuide(from: CGPoint, to: CGPoint) {
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        guideLayer.path = path.cgPath
    }

    private func hideGuide() {
        guideLayer.path = nil
    }

    private func updateTeleprompter(position: TimeInterval,
                                    plan: ConcertPlan, size: CGSize) {
        let lineId = currentLine(at: position, plan: plan)
        guard let lineId, let line = plan.lines.first(where: { $0.id == lineId })
        else {
            teleBar.isHidden = true
            lastTeleLineId = nil
            return
        }
        teleBar.isHidden = false
        if lineId != lastTeleLineId {
            lastTeleLineId = lineId
            teleLabel.text = line.text
            // 字号：40 起、缩到 28 止（v3 口径）；仍放不下则
            // 两行（提词条加高），任何情况下不截断、不省略。
            let sx = size.width / (PetConcertConst.isLandscape(size)
                                      ? PetConcertConst.refWL : PetConcertConst.refW)
            let maxW = size.width - 48 * sx
            var fontSize = PetConcertConst.teleFontMax * sx
            let minSize = PetConcertConst.teleFontMin * sx
            teleLabel.numberOfLines = 1
            while fontSize > minSize {
                teleLabel.font = .systemFont(ofSize: fontSize, weight: .medium)
                let w = (line.text as NSString).size(
                    withAttributes: [.font: teleLabel.font!]).width
                if w <= maxW { break }
                fontSize -= 2 * sx
            }
            if fontSize <= minSize {
                teleLabel.font = .systemFont(ofSize: minSize, weight: .medium)
                let w = (line.text as NSString).size(
                    withAttributes: [.font: teleLabel.font!]).width
                if w > maxW { teleLabel.numberOfLines = 2 }
            }
        }
    }

    // MARK: 布局

    /// 上次落面包屑的布局尺寸（旋转检测：尺寸变即重排+记录）。
    private var lastLayoutLoggedSize: CGSize = .zero

    private func performLayout() {
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        backdropView.frame = bounds
        backdropView.setNeedsDisplay()
        curtainView.frame = bounds
        petField.frame = bounds
        guideView.frame = bounds
        guideLayer.frame = bounds
        // (54) U 旋转重排：容器尺寸一变，全部站位在下一帧
        // frameTick 按新朝向参考系重算（plan + position 纯函
        // 数，无运行期累积位置）；提词字号须按新 sx 重解，
        // 故清 lastTeleLineId 强制下一帧重算字号/行数。
        if bounds.size != lastLayoutLoggedSize {
            let first = lastLayoutLoggedSize == .zero
            lastLayoutLoggedSize = bounds.size
            lastTeleLineId = nil
            if !first || plan != nil {
                let land = PetConcertConst.isLandscape(bounds.size)
                let f: String, so: String, bz: String
                if land {
                    f = "(0.109,0.306)-(0.891,0.713)"
                    so = "(0.500,0.819)"
                    bz = "0.134-0.292"
                } else {
                    f = "(0.133,0.306)-(0.867,0.715)"
                    so = "(0.500,0.842)"
                    bz = "0.140-0.281"
                }
                Breadcrumbs.log("concert.layout orient=\(land ? "landscape" : "portrait")"
                    + " size=\(Int(bounds.width))x\(Int(bounds.height))"
                    + " formation=\(f) solo=\(so) bubbleY=\(bz)")
            }
        }
        let landscape = PetConcertConst.isLandscape(bounds.size)
        let sx = bounds.width / (landscape ? PetConcertConst.refWL : PetConcertConst.refW)
        let sy = bounds.height / (landscape ? PetConcertConst.refHL : PetConcertConst.refH)
        guideLayer.lineWidth = max(1.5, 2.5 * sx)
        guideLayer.lineDashPattern = [NSNumber(value: Double(7 * sx)),
                                      NSNumber(value: Double(5 * sx))]
        let twoLines = teleLabel.numberOfLines == 2
        // (54) U：提词字号按 sx 换算，横屏 sxL(0.444)>syL(0.364)，
        // 条高若仍按 sy 定会挤压字号行高（17.8pt 字行高 ≈21pt
        // > 27.7−8pt）——横屏条高改按 sx 换算（76×0.444=33.7pt，
        // 条底 354.8+33.7=388.5pt 仍在 393pt 内）。
        let barH = PetConcertConst.teleBarH * (landscape ? sx : sy) * (twoLines ? 1.5 : 1)
        teleBar.frame = CGRect(
            x: 24 * sx,
            y: (landscape ? PetConcertConst.teleBarYL : PetConcertConst.teleBarY) * sy,
            width: bounds.width - 48 * sx, height: barH)
        teleBar.layer.cornerRadius = 20 * sx
        teleLabel.frame = teleBar.bounds.insetBy(dx: 12 * sx, dy: 4)
    }
}
