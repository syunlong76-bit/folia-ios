import UIKit
import QuartzCore

// 汪汪队开大会 petconcert（3.7 (53) J）：演唱会渲染器。
//
// 中央大歌词隐藏：唱词只走独唱者头顶气泡（按呼吸块推进）+
// 底部细提词条兜底（整行、不省略）。53 只全员上台：静帧
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        shapeLayer.fillColor = PetConcertPalette.bubbleFill.cgColor
        shapeLayer.strokeColor = PetConcertPalette.outline.cgColor
        layer.addSublayer(shapeLayer)
        label.textColor = PetConcertPalette.bubbleText
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// - tip: 气泡尾尖应指向的点（舞台坐标）；气泡底边（含尾）
    ///   落在 tip 上方。
    func show(key: String, text: String, fontRefPx: CGFloat,
              tip: CGPoint, stageSize: CGSize) {
        let sx = stageSize.width / PetConcertConst.refW
        let font = UIFont.systemFont(ofSize: fontRefPx * sx, weight: .bold)
        let maxTextW = 600 * sx
        label.font = font
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: maxTextW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font], context: nil)
        let padX: CGFloat = 26 * sx, padY: CGFloat = 15 * sx
        let tail: CGFloat = 18 * sx
        let bw = ceil(measured.width) + padX * 2 + 8
        let bh = ceil(measured.height) + padY * 2
        let totalH = bh + tail + 4
        let cx = min(max(tip.x, bw / 2 + 12 * sx), stageSize.width - bw / 2 - 12 * sx)
        let center = CGPoint(x: cx, y: tip.y - totalH / 2)
        let sizeChanged = abs(bounds.width - bw) > 0.5
            || abs(bounds.height - totalH) > 0.5
        if sizeChanged {
            bounds = CGRect(x: 0, y: 0, width: bw, height: totalH)
            label.frame = CGRect(x: padX, y: padY, width: bw - padX * 2, height: bh - padY * 2)
        }
        self.center = center
        let newTailX = min(max(tip.x - (cx - bw / 2), 30 * sx), bw - 30 * sx)
        if key != currentKey || sizeChanged || abs(newTailX - tailX) > 1 {
            tailX = newTailX
            redrawShape(bubbleRect: CGRect(x: 2, y: 2, width: bw - 4, height: bh - 2),
                        tail: tail, sx: sx)
        }
        if key != currentKey {
            currentKey = key
            label.text = text
            isHidden = false
            // 弹入（v3 pop：0.55 → 1，0.18s easeOutBack 的弹簧等价）。
            transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
            UIView.animate(withDuration: 0.32, delay: 0,
                           usingSpringWithDamping: 0.55,
                           initialSpringVelocity: 1.1, options: []) {
                self.transform = .identity
            }
        }
    }

    func hide() {
        guard !isHidden else { return }
        isHidden = true
        currentKey = ""
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
        // 幕布在宠物之后加：侧幕/垂幔盖住队形上缘是样片口径；
        // 追光/洗光在幕布层内、位于宠物之上（光打在宠物身上）。
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
            Breadcrumbs.log("concert.phase track=\(plan.trackId)"
                + " phase=\(phase.rawValue) at=\(String(format: "%.2f", position))")
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
        for asset in actorOrder {
            guard let actor = actors[asset] else { continue }
            let state = actorState(asset: asset, at: position, plan: plan)
            let center = refToStage(state.center, size: size)
            actor.center = center
            let base = PetConcertConst.petBase * (size.width / PetConcertConst.refW)
            actor.bounds = CGRect(x: 0, y: 0, width: base, height: base)
            actor.transform = CGAffineTransform(scaleX: state.scale, y: state.scale)
            if asset == singerAsset {
                singerCenter = center
                singerFeetY = center.y + base * state.scale / 2
                petField.bringSubviewToFront(actor)
            }
        }

        // 幕布/灯光。
        curtainView.update(
            t: position, phase: phase, params: params,
            singerPos: singerCenter, singerFeetY: singerFeetY,
            interludeIntensity: plan.interlude?.intensity ?? 0)

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
                        .filter { $0 != plan.captain && $0 != lastSingerAsset }
                        .max { (actors[$0]?.decodedCost ?? 0)
                            < (actors[$1]?.decodedCost ?? 0) }
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

    // MARK: 位置计算（参考画布坐标，纯函数）

    private func currentLine(at t: TimeInterval, plan: ConcertPlan) -> Int? {
        for line in plan.lines where t >= line.start && t < line.end {
            return line.id
        }
        return nil
    }

    /// 基础锚点（无跑位）：降落/散位/列队/队形/间奏玩耍位。
    private func basePosition(asset: String, at t: TimeInterval,
                              plan: ConcertPlan) -> CGPoint {
        let slot = ConcertPlan.slotPoint(plan.slotOf[asset] ?? 0)
        guard let scatter = plan.scatterOf[asset] else { return slot }
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
        if let gap = plan.interlude, let play = plan.playOf[asset] {
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
                            plan: ConcertPlan) -> (center: CGPoint, scale: CGFloat) {
        let base = basePosition(asset: asset, at: t, plan: plan)
        var scale: CGFloat = asset == plan.captain ? PetConcertConst.captainScale : 1
        let phase = plan.phase(at: t)

        // 跑位覆盖（独唱者）。连唱时相邻 trip 窗口重叠，必须
        // 按行号确定性取最早一条（字典序任意会随机跳变），
        // 续唱衔接由下方 nextTrip 分支处理。
        let trip = plan.tripsByLine.values
            .filter { $0.singer == asset && t >= $0.depart && t < $0.returnEnd }
            .sorted { $0.lineIndex < $1.lineIndex }
            .first
        if let trip {
            let solo = CGPoint(x: PetConcertConst.soloX, y: PetConcertConst.soloY)
            // 连唱：下一行同为本只且其 depart 已到 → 停在独唱位。
            let nextTrip = plan.tripsByLine[trip.lineIndex + 1]
            if t >= trip.returnStart, let next = nextTrip,
               next.singer == asset, t >= next.depart {
                return (solo, PetConcertConst.soloScale)
            }
            if t < trip.arrive {
                let u = concertEaseInOut((t - trip.depart) / (trip.arrive - trip.depart))
                let from = basePosition(asset: asset, at: trip.depart, plan: plan)
                return (concertBezier(from, solo, lift: PetConcertConst.bezierLift, u),
                        concertLerp(1, PetConcertConst.soloScale, u))
            }
            if t < trip.returnStart {
                return (solo, PetConcertConst.soloScale)
            }
            let u = concertEaseInOut((t - trip.returnStart) / (trip.returnEnd - trip.returnStart))
            let to = basePosition(asset: asset, at: trip.returnEnd, plan: plan)
            return (concertBezier(solo, to, lift: PetConcertConst.bezierLift, u),
                    concertLerp(PetConcertConst.soloScale, 1, u))
        }

        // 队形内动态（闲晃/律动/间奏跳/告别鞠躬）。
        var center = base
        let swayPhase = plan.swayPhaseOf[asset] ?? 0
        let inFormation: Bool
        switch phase {
        case .formation, .preludeChat, .singing1, .singing2, .farewell, .ended:
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
        if phase == .interlude, let gap = plan.interlude,
           t >= gap.start + 0.45, t < gap.end - 0.55 {
            let amp = 16 * CGFloat(gap.intensity)
            center.y -= abs(CGFloat(sin(5 * t + swayPhase))) * amp
        }
        // 群唱行：前排两排齐蹦。
        if let lineId = currentLine(at: t, plan: plan),
           plan.chorusLines.contains(lineId) {
            let row = (plan.slotOf[asset] ?? 0) / PetConcertConst.gridCols
            if row >= 6 {
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

    private func refToStage(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width / PetConcertConst.refW,
                y: point.y * size.height / PetConcertConst.refH)
    }

    // MARK: 气泡与提词条

    private func updateBubble(position: TimeInterval, phase: ConcertPhase,
                              plan: ConcertPlan, singerAsset: String?,
                              soloLine: Int?, size: CGSize) {
        let sx = size.width / PetConcertConst.refW
        let base = PetConcertConst.petBase * sx
        // 队长口令（列队相位，逐字原样）。
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
        // 前奏闲聊 / 告别关心（cue 表驱动）。
        let cues = phase == .preludeChat ? plan.chatCues
            : (phase == .farewell ? plan.farewellCues : [])
        if let cue = cues.first(where: { position >= $0.start && position < $0.end }),
           let actor = actors[cue.asset] {
            bubbleView.show(
                key: "cue-\(phase.rawValue)-\(cue.asset)-\(cue.start)",
                text: cue.text, fontRefPx: PetConcertConst.bubbleFontChat,
                tip: CGPoint(x: actor.center.x, y: actor.frame.minY - 6),
                stageSize: size)
            return
        }
        // 轮唱气泡（独唱位上方，按呼吸块推进）。
        if let soloLine, let blocks = plan.breathBlocksByLine[soloLine],
           let block = blocks.first(where: { position >= $0.start && position < $0.end }) {
            let soloRef = CGPoint(x: PetConcertConst.soloX, y: PetConcertConst.soloY)
            let soloStage = refToStage(soloRef, size: size)
            let tip = CGPoint(x: soloStage.x,
                              y: soloStage.y - base * PetConcertConst.soloScale / 2 - 8)
            bubbleView.show(
                key: "lyric-\(soloLine)-\(block.start)",
                text: block.text, fontRefPx: PetConcertConst.bubbleFontLyric,
                tip: tip, stageSize: size)
            return
        }
        // 群唱行气泡（前排中央上方）。
        if let lineId = currentLine(at: position, plan: plan),
           plan.chorusLines.contains(lineId) {
            let tipRef = CGPoint(x: PetConcertConst.soloX, y: PetConcertConst.soloY)
            let tipStage = refToStage(tipRef, size: size)
            bubbleView.show(
                key: "chorus-\(lineId)", text: plan.lines.first { $0.id == lineId }?.text ?? "",
                fontRefPx: PetConcertConst.bubbleFontLyric,
                tip: CGPoint(x: tipStage.x, y: tipStage.y - base - 8),
                stageSize: size)
            return
        }
        bubbleView.hide()
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
            let sx = size.width / PetConcertConst.refW
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

    private func performLayout() {
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        backdropView.frame = bounds
        backdropView.setNeedsDisplay()
        curtainView.frame = bounds
        petField.frame = bounds
        let sx = bounds.width / PetConcertConst.refW
        let sy = bounds.height / PetConcertConst.refH
        let twoLines = teleLabel.numberOfLines == 2
        let barH = PetConcertConst.teleBarH * sy * (twoLines ? 1.5 : 1)
        teleBar.frame = CGRect(
            x: 24 * sx, y: PetConcertConst.teleBarY * sy,
            width: bounds.width - 48 * sx, height: barH)
        teleBar.layer.cornerRadius = 20 * sx
        teleLabel.frame = teleBar.bounds.insetBy(dx: 12 * sx, dy: 4)
    }
}
