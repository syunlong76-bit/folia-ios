import UIKit
import QuartzCore

// 云阶 partita（3.7 (26) 照搬对齐版，M2'）：按 folia-major 网页版
// partita（VisualizerPartita + partitaLayout + PartitaChunk）的
// 展示行为逐项实现，替换 (14) 借用展开卡视觉语言的自有风格
// 5 行窗口版。对齐要点（依据文件见 (26) 回报附表）：
//  - 画面只呈现当前一行：整行按语义单元切成不等长的 chunk，
//    chunk 在单列里纵向堆叠（列水平居中），逐个 chunk 带交替
//    左右的横向错位（stagger 20–100pt、种子 RNG 与网页同序）
//    与交替侧的引导线（竖线 32pt + 横线 宽+36pt）。
//  - chunk 三态：waiting 不可见（透明、scale 0.85、自引导线
//    侧外移 40pt），到时弹簧落位；chunk 内词走共享 GlowWord
//    三态机（小偏移 ±6pt/旋转 ±3°，词距 0.8rem）。
//  - 字号 clamp(40, 5.5vmin, 72)，整行字素 >40 时 ×0.8；
//    行容器进出场与 classic 同（scale/透明 0.3s）；整列呼吸
//    浮动同 classic。下一行布局按网页预热窗（提前 0.18–1.2s）
//    预构建缓存（上限 48 行）。
// 时钟纪律不变：只消费宿主 frameTick 的锚点位置；seek 后所有
// chunk/词状态按新位置逐帧重算（状态机无历史依赖）。
// 调参（(57) C1 接线）：经 PartitaTuningStore 门面读（缺省 =
// DEFAULT_PARTITA_TUNING）：stagger 改走 [staggerMin,
// staggerMax] 区间、showGuideLines 控制引导线显隐、
// avoidOverlap 开时按 partitaOverlap 公式放大词距/行距并
// 走 overlapFit 缩字号。useSemanticLayout 数据通路（(57)
// C1b 接通）：开时经 StageLyricUnits.semanticGroups 取语义
// 布局组（网页 buildPostLyricLayoutUnits(semantic:sticky:)
// 对应实现，分组规则见 GlowWordEngine），chunk 只在组界
// 切分；关时每单元自成一组、与原平铺切分逐字等价。开关
// 已含在调参指纹里（PartitaTuningValues 全字段 Equatable），
// 切换即整表失效重建。

/// partita 布局（纯数据）：一行的 chunk 划分与几何。
private struct PartitaLayout {
    struct Chunk {
        var units: [StageWordUnit]
        var wordPoses: [StageWordPose]
        var x: CGFloat
        var y: CGFloat
        var guideLeft: Bool
        var width: CGFloat
        var height: CGFloat
        /// 每词后的间距（词数同长，末词为尾距 12.8）：默认恒
        /// 12.8（0.8rem）；avoidOverlap 开时按 partitaOverlap
        /// 的成对 reach 公式逐对放大（见 buildLayout）。
        var wordGaps: [CGFloat]
        /// 本 chunk 下间距：默认 9.6（0.6rem）；avoidOverlap
        /// 开时按相邻行 reach 放大（partitaOverlap 口径）。
        var marginBottom: CGFloat
    }
    var chunks: [Chunk]
    var fontSize: CGFloat
    var profile: StageLineProfile
    var columnWidth: CGFloat
    var columnHeight: CGFloat
    /// 首行上间距：默认 0；avoidOverlap 开时为首行上 reach
    /// 扣 chunk 上 padding 后的值（partitaOverlap marginTop）。
    var marginTop: CGFloat
}

/// 一个 chunk 的视图：词行 + 两条引导线 + chunk 级三态动画。
private final class PartitaChunkView: UIView {

    enum Status { case waiting, active, passed }

    private let layout: PartitaLayout.Chunk
    private let activeColor: UIColor
    private let words: [GlowWordView]
    private let vGuide = UIView()
    private let hGuide = UIView()
    private(set) var status: Status = .waiting

    var start: TimeInterval { layout.units.first?.start ?? 0 }
    var activeEnd: TimeInterval { layout.units.last?.end ?? 0 }

    init(layout: PartitaLayout.Chunk, words: [GlowWordView], activeColor: UIColor,
         showGuides: Bool = true) {
        self.layout = layout
        self.words = words
        self.activeColor = activeColor
        super.init(frame: CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
        isUserInteractionEnabled = false

        // 词行：左内边距 8pt 起，词距逐词取 layout.wordGaps
        // （默认 12.8pt = 0.8rem；avoidOverlap 时逐对放大），
        // 纵向居中。
        var cursor: CGFloat = 8
        for (index, word) in words.enumerated() {
            word.frame.origin = CGPoint(
                x: cursor, y: (layout.height - word.bounds.height) / 2)
            addSubview(word)
            cursor += word.bounds.width
                + (layout.wordGaps.indices.contains(index)
                    ? layout.wordGaps[index] : 12.8)
        }

        // 引导线（网页 PartitaChunk）：竖线在 chunk 底侧外
        // 8pt、高 32pt、自底向上生长；横线在底侧下 8pt、
        // 宽 = chunk 宽 + 36pt、自引导线侧生长。waiting 时
        // 缩放为 0 不可见；active 着 accent 色 + 光晕；
        // passed 转白 0.22。
        let guideColor = UIColor.white.withAlphaComponent(0.14)
        vGuide.backgroundColor = guideColor
        hGuide.backgroundColor = guideColor
        let w = layout.width
        let h = layout.height
        if layout.guideLeft {
            vGuide.bounds = CGRect(x: 0, y: 0, width: 1, height: 32)
            vGuide.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
            vGuide.center = CGPoint(x: -8 + 0.5, y: h + 16)
            hGuide.bounds = CGRect(x: 0, y: 0, width: w + 36, height: 1)
            hGuide.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
            hGuide.center = CGPoint(x: -16, y: h + 8)
        } else {
            vGuide.bounds = CGRect(x: 0, y: 0, width: 1, height: 32)
            vGuide.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
            vGuide.center = CGPoint(x: w + 8 - 0.5, y: h + 16)
            hGuide.bounds = CGRect(x: 0, y: 0, width: w + 36, height: 1)
            hGuide.layer.anchorPoint = CGPoint(x: 1, y: 0.5)
            hGuide.center = CGPoint(x: w + 16, y: h + 8)
        }
        vGuide.transform = CGAffineTransform(scaleX: 1, y: 0.001)
        hGuide.transform = CGAffineTransform(scaleX: 0.001, y: 1)
        addSubview(vGuide)
        addSubview(hGuide)
        // 网页 showGuideLines=false 时引导线整组不渲染
        // （PartitaChunk 的条件渲染），原生以隐藏等价。
        vGuide.isHidden = !showGuides
        hGuide.isHidden = !showGuides
        applyWaitingPose()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func waitingTransform() -> CGAffineTransform {
        let side: CGFloat = layout.guideLeft ? -40 : 40
        return CGAffineTransform(translationX: layout.x + side, y: layout.y)
            .scaledBy(x: 0.85, y: 0.85)
    }

    private func settledTransform() -> CGAffineTransform {
        CGAffineTransform(translationX: layout.x, y: layout.y)
    }

    private func applyWaitingPose() {
        transform = waitingTransform()
        alpha = 0
    }

    func update(position: TimeInterval, lookahead: TimeInterval) {
        let target: Status
        if position < start - lookahead {
            target = .waiting
        } else if position <= activeEnd {
            target = .active
        } else {
            target = .passed
        }
        if target != status {
            status = target
            switch target {
            case .waiting:
                layer.removeAllAnimations()
                UIView.animate(withDuration: 0.4) {
                    self.transform = self.waitingTransform()
                    self.alpha = 0
                }
                setGuides(grown: false, active: false)
            case .active:
                UIView.animate(withDuration: 0.55, delay: 0,
                               usingSpringWithDamping: 0.707,
                               initialSpringVelocity: 0,
                               options: [.beginFromCurrentState]) {
                    self.transform = self.settledTransform()
                }
                UIView.animate(withDuration: 0.1) { self.alpha = 1 }
                setGuides(grown: true, active: true)
            case .passed:
                transform = settledTransform()
                alpha = 1
                setGuides(grown: true, active: false)
            }
        }
        for word in words { word.update(position: position) }
    }

    /// 构建后按当前位定格（中途进台/seek 落位）。
    func snap(position: TimeInterval, lookahead: TimeInterval) {
        let target: Status
        if position < start - lookahead {
            target = .waiting
        } else if position <= activeEnd {
            target = .active
        } else {
            target = .passed
        }
        status = target
        layer.removeAllAnimations()
        switch target {
        case .waiting:
            applyWaitingPose()
            setGuides(grown: false, active: false, animated: false)
        case .active:
            transform = settledTransform()
            alpha = 1
            setGuides(grown: true, active: true, animated: false)
        case .passed:
            transform = settledTransform()
            alpha = 1
            setGuides(grown: true, active: false, animated: false)
        }
        for word in words { word.snap(position: position) }
    }

    private func setGuides(grown: Bool, active: Bool, animated: Bool = true) {
        let color: UIColor
        if active {
            color = activeColor
        } else if status == .passed || grown {
            color = UIColor.white.withAlphaComponent(0.22)
        } else {
            color = UIColor.white.withAlphaComponent(0.14)
        }
        let apply = {
            self.vGuide.transform = CGAffineTransform(scaleX: 1, y: grown ? 1 : 0.001)
            self.hGuide.transform = CGAffineTransform(scaleX: grown ? 1 : 0.001, y: 1)
            self.vGuide.backgroundColor = color
            self.hGuide.backgroundColor = color
            for guide in [self.vGuide, self.hGuide] {
                guide.layer.shadowColor = self.activeColor.cgColor
                guide.layer.shadowRadius = 5
                guide.layer.shadowOpacity = active ? 0.27 : 0
                guide.layer.shadowOffset = .zero
            }
        }
        if animated {
            UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseOut],
                           animations: apply)
        } else { apply() }
    }
}

final class PartitaStageRenderer: LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    private let floatView = UIView()
    private var lineContainer: UIView?
    private var chunkViews: [PartitaChunkView] = []
    private var currentProfile: StageLineProfile?
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false
    private var activeLineId: Int? = nil
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var layoutCache: [Int: PartitaLayout] = [:]
    private var layoutCacheOrder: [Int] = []
    private var layoutViewportSize: CGSize = .zero
    /// 调参指纹（PartitaTuningStore，C1 接线）：布局缓存键
    /// 网页含 staggerMin/Max、showGuideLines、useSemanticLayout
    /// （buildPartitaLayoutCacheKey），原生以指纹变化整表失效
    /// 等价。缺省 = DEFAULT_PARTITA_TUNING。
    private var builtTuning: PartitaTuningValues?
    private func tuning() -> PartitaTuningValues {
        PartitaTuningStore.valuesCached(now: CACurrentMediaTime())
    }

    init() {
        view = rootView
        rootView.backgroundColor = .clear
        rootView.addSubview(floatView)
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        // (61) WC：入口统一过对比钳制——下游 palette.* 全走保护副本。
        var snapshot = snapshot
        snapshot.palette = snapshot.palette.contrastProtected()
        self.snapshot = snapshot
        // 布局依赖视口（行数按视口高、字号按短边）：视口变
        // （旋转）时缓存与当前行一并失效重建。
        let viewportChanged = snapshot.viewport.size != layoutViewportSize
            && layoutViewportSize != .zero
        if snapshot.track?.id != builtTrackId
            || snapshot.lines.count != builtLineCount
            || viewportChanged
            || tuning() != builtTuning {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            builtTuning = tuning()
            layoutCache.removeAll()
            layoutCacheOrder.removeAll()
            clearLine()
        }
        layoutViewportSize = snapshot.viewport.size
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if isActive {
            StageBreathingFloat.start(on: floatView)
        } else {
            StageBreathingFloat.stop(on: floatView)
        }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        // 面板中途改参（无新快照）：指纹一变即失效布局缓存
        // 并清当前行，下帧按新参重建（网页 cacheKey 含调参
        // 字段、键变即新布局同义）。
        if tuning() != builtTuning {
            builtTuning = tuning()
            layoutCache.removeAll()
            layoutCacheOrder.removeAll()
            clearLine()
        }
        let idx = ClassicStageRenderer.activeIndex(in: snapshot.lines, at: position)
        if idx != activeLineId {
            transitionLine(to: idx, position: position)
        }
        if let profile = currentProfile {
            for chunk in chunkViews {
                chunk.update(position: position, lookahead: profile.wordLookahead)
            }
        }
        preheatIfNeeded(position: position)
    }

    func unmount() {
        isActive = false
        StageBreathingFloat.stop(on: floatView)
        context = nil
    }

    // MARK: 行切换

    private func clearLine() {
        lineContainer?.removeFromSuperview()
        lineContainer = nil
        chunkViews = []
        activeLineId = nil
        currentProfile = nil
    }

    private func transitionLine(to idx: Int?, position: TimeInterval) {
        if let old = lineContainer {
            lineContainer = nil
            chunkViews = []
            UIView.animate(withDuration: 0.3, delay: 0,
                           options: [.curveEaseInOut]) {
                old.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                old.alpha = 0
            } completion: { _ in old.removeFromSuperview() }
        }
        activeLineId = idx
        guard let idx, let snapshot,
              snapshot.lines.indices.contains(idx) else {
            currentProfile = nil
            return
        }
        let line = snapshot.lines[idx]
        let layout = layoutFor(line: line)
        currentProfile = layout.profile
        let container = UIView()
        container.isUserInteractionEnabled = false
        container.frame = CGRect(
            x: (rootView.bounds.width - layout.columnWidth) / 2,
            y: (rootView.bounds.height - layout.columnHeight) / 2,
            width: layout.columnWidth, height: layout.columnHeight)
        var chunks: [PartitaChunkView] = []
        var y: CGFloat = layout.marginTop
        for chunkLayout in layout.chunks {
            let words = chunkLayout.units.enumerated().map { (i, unit) in
                GlowWordView(
                    unit: unit, pose: chunkLayout.wordPoses[i],
                    font: StageFonts.bold(size: layout.fontSize),
                    baseColor: snapshot.palette.primary,
                    activeColor: snapshot.palette.accent,
                    profile: layout.profile)
            }
            let chunkView = PartitaChunkView(
                layout: chunkLayout, words: words,
                activeColor: snapshot.palette.accent,
                showGuides: tuning().showGuideLines)
            chunkView.frame.origin = CGPoint(
                x: (layout.columnWidth - chunkLayout.width) / 2, y: y)
            y += chunkLayout.height + chunkLayout.marginBottom
            container.addSubview(chunkView)
            chunks.append(chunkView)
        }
        lineContainer = container
        chunkViews = chunks
        floatView.addSubview(container)
        for chunk in chunks {
            chunk.snap(position: position, lookahead: layout.profile.wordLookahead)
        }
        container.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        container.alpha = 0
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            container.transform = .identity
            container.alpha = 1
        }
    }

    // MARK: 布局构建（partitaLayout.ts 逐项对应）

    private func layoutFor(line: LyricLine) -> PartitaLayout {
        if let cached = layoutCache[line.id] { return cached }
        let layout = buildLayout(line: line)
        layoutCache[line.id] = layout
        layoutCacheOrder.append(line.id)
        if layoutCacheOrder.count > 48 {
            let evict = layoutCacheOrder.removeFirst()
            layoutCache.removeValue(forKey: evict)
        }
        return layout
    }

    private func buildLayout(line: LyricLine) -> PartitaLayout {
        guard let snapshot else {
            return PartitaLayout(chunks: [], fontSize: 40,
                                 profile: StageLineProfile.profile(for: line),
                                 columnWidth: 0, columnHeight: 0,
                                 marginTop: 0)
        }
        let profile = StageLineProfile.profile(for: line)
        let units = StageLyricUnits.units(for: line)
        // 布局组（(57) C1b）：useSemanticLayout 开时用语义组
        // （组数 = 网页 layoutUnits 数，决定行数与 chunk 切
        // 界）；关时单元素组与下方平铺切分逐字等价。组内单
        // 元与 units 同源同序，totalGraphemes 等计数仍走
        // units 口径不变；语义组异常为空时回退单元素组。
        let layoutGroups: [[StageWordUnit]] = tuning().useSemanticLayout
            ? StageLyricUnits.semanticGroups(for: line)
            : units.map { [$0] }
        let effectiveGroups = layoutGroups.isEmpty
            ? units.map { [$0] } : layoutGroups
        let viewport = snapshot.viewport.size
        let vmin = min(viewport.width, viewport.height)
        let graphemeCount = line.text.reduce(0) {
            $0 + ($1.isWhitespace ? 0 : 1)
        }
        let totalGraphemes = max(graphemeCount, units.count, 1)
        let densityScale: CGFloat = totalGraphemes > 40 ? 0.8 : 1
        var fontSize = (vmin > 0
            ? max(40, min(5.5 * vmin / 100, 72)) : 40) * densityScale

        // 行数：可用高 = 视口高 × 0.65，基准行高 100。
        let windowHeight = viewport.height > 0 ? viewport.height : rootView.bounds.height
        let targetRows = max(1, Int((windowHeight * 0.65 / 100).rounded(.down)))
        let actualRows = min(effectiveGroups.count, targetRows)

        // 种子 RNG（网页 buildSequentialColumns 的调用序：
        // 切分阶段每非末 chunk 一次，之后每 chunk 两次
        // （stagger 幅度、stagger 缩放），种子自 startTime 起 +1。
        var seed = line.start
        func nextRandom() -> Double {
            let value = stageSeededRandom(seed)
            seed += 1
            return value
        }

        var chunkUnitsList: [[StageWordUnit]] = []
        if actualRows > 0 {
            var remainingGroups = effectiveGroups.count
            var remainingChunks = actualRows
            var groupIndex = 0
            for c in 0..<actualRows {
                let isLast = c == actualRows - 1
                var chunkLength = 1
                if isLast {
                    chunkLength = remainingGroups
                } else {
                    let avg = Double(remainingGroups) / Double(remainingChunks)
                    let maxLen = Int((avg * 1.5).rounded(.up))
                    let randVal = nextRandom()
                    chunkLength = max(1, min(maxLen,
                        Int((avg + (randVal - 0.5) * avg).rounded())))
                }
                chunkLength = max(1, min(chunkLength,
                                         remainingGroups - (remainingChunks - 1)))
                chunkUnitsList.append(
                    effectiveGroups[groupIndex..<groupIndex + chunkLength]
                        .flatMap { $0 })
                groupIndex += chunkLength
                remainingGroups -= chunkLength
                remainingChunks -= 1
            }
        }

        // chunk 草稿：stagger 与词姿态在此消费种子序列（与
        // 网页 buildSequentialColumns 的调用序一致：每 chunk
        // 两次——stagger 幅度、stagger 缩放；stagger 幅度改走
        // 调参区间 [staggerMin, staggerMax]，C1 接线，缺省
        // 20…100 与旧硬编码逐值一致）。
        struct ChunkDraft {
            var units: [StageWordUnit]
            var poses: [StageWordPose]
            var x: CGFloat
            var y: CGFloat
            var guideLeft: Bool
        }
        var drafts: [ChunkDraft] = []
        for (rowIndex, chunkUnits) in chunkUnitsList.enumerated() {
            let t = tuning()
            let staggerMagnitude = CGFloat(t.staggerMin
                + nextRandom() * max(t.staggerMax - t.staggerMin, 0))
            let staggerX = rowIndex % 2 == 0 ? -staggerMagnitude : staggerMagnitude
            let staggerScale = CGFloat(0.8 + nextRandom() * 0.9)
            let rowBias = CGFloat(rowIndex) - CGFloat(actualRows - 1) / 2
            // 词姿态（buildPartitaWordConfigs）：种子 = 首词
            // start + 词序 × 7.13，偏移 ±6、旋转 ±3、passed ±10°。
            var poses: [StageWordPose] = []
            for (i, _) in chunkUnits.enumerated() {
                let wordSeed = (chunkUnits.first?.start ?? 0) + Double(i) * 7.13
                let r = { (offset: Double) in
                    stageSeededRandom(wordSeed + offset)
                }
                poses.append(StageWordPose(
                    x: CGFloat(r(1) - 0.5) * 12,
                    y: CGFloat(r(2) - 0.5) * 12,
                    rotate: CGFloat(r(3) - 0.5) * 6,
                    scale: staggerScale,
                    passedRotate: CGFloat(r(8) - 0.5) * 20))
            }
            drafts.append(ChunkDraft(
                units: chunkUnits, poses: poses,
                x: staggerX, y: rowBias * 2.5,
                guideLeft: rowIndex % 2 == 0))
        }

        // MARK: avoidOverlap 间距（partitaOverlap.ts 的 pt 等价）
        //
        // getGlowWordReach：字形高 = 1em；active 态 scale×1.4
        // （GLOW_WORD_ACTIVE_SCALE）于 rotate 处、passed 态
        // rotate→rotate+passedRotate 采样 9 点，取最大半宽高。
        func glowReach(width: CGFloat, fontSize: CGFloat,
                       pose: StageWordPose)
            -> (halfWidth: CGFloat, halfHeight: CGFloat) {
            func reachAt(_ scale: CGFloat, _ rotateDeg: CGFloat)
                -> (CGFloat, CGFloat) {
                let rad = abs(rotateDeg) * .pi / 180
                let c = abs(cos(rad)), s = abs(sin(rad))
                return (scale * (width * c + fontSize * s) / 2,
                        scale * (fontSize * c + width * s) / 2)
            }
            var best = reachAt(pose.scale * 1.4, pose.rotate)
            for step in 0...8 {
                let r = reachAt(pose.scale, pose.rotate
                    + pose.passedRotate * CGFloat(step) / 8)
                best = (max(best.0, r.0), max(best.1, r.1))
            }
            return best
        }

        /// 一行（chunk）的上下 reach：em 部分（半高超出
        /// 1.22em 行框的量）与 px 部分（词自身 y 偏移）分开，
        /// 与 partitaOverlap.rowReach 同构。chunk 自身 rotate
        /// 网页仅 chaotic 档非 0、原生恒 normal 档 → turn 项
        /// 恒 0，不引入估算（差异见 C1 报告）。
        func rowReach(draft: ChunkDraft, widths: [CGFloat],
                      fontSize: CGFloat)
            -> (emTop: CGFloat, pxTop: CGFloat,
                emBottom: CGFloat, pxBottom: CGFloat) {
            var topEm: CGFloat = -.greatestFiniteMagnitude
            var bottomEm: CGFloat = -.greatestFiniteMagnitude
            var topPx: CGFloat = -.greatestFiniteMagnitude
            var bottomPx: CGFloat = -.greatestFiniteMagnitude
            for (i, pose) in draft.poses.enumerated() {
                let reach = glowReach(width: widths[i],
                                      fontSize: fontSize, pose: pose)
                let over = reach.halfHeight - fontSize * 1.22 / 2
                topEm = max(topEm, over)
                bottomEm = max(bottomEm, over)
                topPx = max(topPx, -pose.y)
                bottomPx = max(bottomPx, pose.y)
            }
            return (topEm, topPx, bottomEm, bottomPx)
        }

        /// 按给定字号组装全部 chunk（词宽实测、词距/行距按
        /// avoidOverlap 开关取缺省或 reach 公式）。组装不消费
        /// 种子序列，可按 overlapFit 的新字号重组一次。
        func assemble(fontSize: CGFloat)
            -> (chunks: [PartitaLayout.Chunk], width: CGFloat,
                height: CGFloat, marginTop: CGFloat) {
            let font = StageFonts.bold(size: fontSize)
            let chunkHeight = fontSize * 1.22 + 6.4
            let avoid = tuning().avoidOverlap
            var widthsPerChunk: [[CGFloat]] = []
            var gapsPerChunk: [[CGFloat]] = []
            var reaches: [(emTop: CGFloat, pxTop: CGFloat,
                           emBottom: CGFloat, pxBottom: CGFloat)] = []
            for draft in drafts {
                let widths = draft.units.map {
                    ($0.text as NSString)
                        .size(withAttributes: [.font: font]).width
                }
                widthsPerChunk.append(widths)
                var gaps = [CGFloat](repeating: 12.8,
                                     count: draft.units.count)
                if avoid, widths.count > 1 {
                    for i in 0..<(widths.count - 1) {
                        // getGlowWordPairGap（无 offset 形）+
                        // partitaOverlap 的 gapPx（相邻词 x
                        // 偏移差）+ BREATH 0.05em，下限 12.8。
                        let r1 = glowReach(width: widths[i],
                            fontSize: fontSize, pose: draft.poses[i])
                        let r2 = glowReach(width: widths[i + 1],
                            fontSize: fontSize, pose: draft.poses[i + 1])
                        let pair = (r1.halfWidth - widths[i] / 2)
                            + (r2.halfWidth - widths[i + 1] / 2)
                            + (draft.poses[i].x - draft.poses[i + 1].x)
                        gaps[i] = max(12.8, pair + 0.05 * fontSize)
                    }
                }
                gapsPerChunk.append(gaps)
                reaches.append(rowReach(draft: draft, widths: widths,
                                        fontSize: fontSize))
            }
            var chunks: [PartitaLayout.Chunk] = []
            var columnWidth: CGFloat = 0
            var marginTop: CGFloat = 0
            if avoid, let first = reaches.first {
                // 首行 marginTop：上 reach 扣 chunk 上 padding
                // 0.2rem（3.2pt），下限 0（网页 max(0px, …)）。
                marginTop = max(0, first.emTop + first.pxTop - 3.2)
            }
            var columnHeight: CGFloat = marginTop
            for (rowIndex, draft) in drafts.enumerated() {
                let widths = widthsPerChunk[rowIndex]
                let gaps = gapsPerChunk[rowIndex]
                var content: CGFloat = 0
                for i in widths.indices { content += widths[i] + gaps[i] }
                let width = content + 16
                var marginBottom: CGFloat = 9.6
                if avoid {
                    let r = reaches[rowIndex]
                    if rowIndex + 1 < reaches.count {
                        let below = reaches[rowIndex + 1]
                        // 相邻行：下伸 + 上伸 + 0.05em + px
                        // 分量 − 两行 padding 合计 0.4rem。
                        marginBottom = max(9.6, r.emBottom + below.emTop
                            + 0.05 * fontSize + r.pxBottom + below.pxTop
                            - 6.4)
                    } else {
                        marginBottom = max(9.6, r.emBottom + r.pxBottom - 3.2)
                    }
                }
                chunks.append(PartitaLayout.Chunk(
                    units: draft.units, wordPoses: draft.poses,
                    x: draft.x, y: draft.y,
                    guideLeft: draft.guideLeft,
                    width: width, height: chunkHeight,
                    wordGaps: gaps, marginBottom: marginBottom))
                columnWidth = max(columnWidth, width)
                columnHeight += chunkHeight + marginBottom
            }
            if !avoid, !chunks.isEmpty { columnHeight -= 9.6 }
            return (chunks, columnWidth, columnHeight, marginTop)
        }

        var assembled = assemble(fontSize: fontSize)
        // overlapFit（useOverlapFit.ts）：avoidOverlap 拉开
        // 间距后整列高过歌词区时，字号按比例缩小（下限 0.5、
        // ×0.98 余量），以新字号重组一次。原生歌词区取视口
        // 全高（网页为壳层内容区，差异见 C1 报告）；宽度向
        // 的 fit 由下方 (53) 宽适配 pass 承担。
        if tuning().avoidOverlap, assembled.height > windowHeight,
           assembled.height > 0 {
            let fit = max(0.5, (windowHeight / assembled.height) * 0.98)
            if fit < 1 {
                fontSize *= CGFloat(fit)
                assembled = assemble(fontSize: fontSize)
            }
        }
        var chunks = assembled.chunks
        var columnWidth = assembled.width
        var columnHeight = assembled.height
        let layoutMarginTop = assembled.marginTop
        // 宽适配（3.7 (53) 工作流 K）：原布局按视口高定行数
        // 切 chunk、从不核宽——chunk 实测宽 + 横向错位
        // （stagger ±20–100，chunk 帧恒居中于列/屏中心，
        // 视觉半 extent = 宽/2 + |stagger|）+ 引导线外伸
        // （横线宽 = chunk 宽 + 36）可超屏宽，长行/大错位
        // 时冲出框（网页版同构、亦无核宽，属移植带入的隐
        // 患）。修法两段、只在超宽时生效、互不连坐：
        // ①错位夹取：逐 chunk 把 |stagger| 夹到当前宽恰好
        //   落框的额度（错位是位置量，夹它不动字号；未超
        //   额者逐值不变）；
        // ②字号缩放：宽本身（含引导线外伸 40）仍超框才
        //   按额度等比缩字号重算宽高（词宽∝字号；切分/
        //   种子/词距不变；下限 0.5，触限后错位再夹一遍
        //   兜底——>40 字素行已有 densityScale 0.8 前置，
        //   0.5 下限内可解，见工作流 K 报告推导）。
        // C1 注：词距和由常数 12.8×n 改为 chunk.wordGaps 实
        // 和（avoidOverlap 时逐对放大）；缩放时 avoidOverlap
        // 的词距随字号同比例缩放（网页词距为 em 计、同义），
        // 缺省模式词距恒 12.8 不动，与旧行为一致。列高按
        // marginTop + Σ（高 + marginBottom）重算（缺省模式
        // 末行 margin 不计，与旧口径一致）。
        let availW = (rootView.bounds.width > 0
            ? rootView.bounds.width : snapshot.viewport.size.width) - 16
        if availW > 0, !chunks.isEmpty {
            func clampStaggers() {
                for i in chunks.indices {
                    let allowed: CGFloat = max(
                        0, (availW - (chunks[i].width + 40)) / 2)
                    chunks[i].x = min(max(chunks[i].x, -allowed), allowed)
                }
            }
            clampStaggers()
            var scale: CGFloat = 1
            for chunk in chunks {
                let gapSum = chunk.wordGaps.reduce(0, +)
                let sumW = chunk.width - 16 - gapSum
                guard sumW > 0 else { continue }
                let room = availW - 40 - gapSum - 16
                if room < sumW { scale = min(scale, max(room, 1) / sumW) }
            }
            if scale < 1 {
                scale = max(scale, 0.5)
                fontSize *= scale
                columnWidth = 0
                columnHeight = layoutMarginTop
                let newChunkHeight = fontSize * 1.22 + 6.4
                let avoid = tuning().avoidOverlap
                for i in chunks.indices {
                    let gapSum = chunks[i].wordGaps.reduce(0, +)
                    let sumW = chunks[i].width - 16 - gapSum
                    if avoid {
                        chunks[i].wordGaps = chunks[i].wordGaps
                            .map { $0 * scale }
                    }
                    let newGapSum = avoid ? gapSum * scale : gapSum
                    chunks[i].width = sumW * scale + newGapSum + 16
                    chunks[i].height = newChunkHeight
                    columnWidth = max(columnWidth, chunks[i].width)
                    columnHeight += newChunkHeight + chunks[i].marginBottom
                }
                if !avoid { columnHeight -= chunks.last?.marginBottom ?? 0 }
                clampStaggers()
            }
        }
        return PartitaLayout(
            chunks: chunks, fontSize: fontSize, profile: profile,
            columnWidth: columnWidth, columnHeight: columnHeight,
            marginTop: layoutMarginTop)
    }

    /// 下一行预热（网页 PARTITA_PREHEAT_WINDOW：提前量
    /// 0.18–1.2s 时预构建布局进缓存）。
    private func preheatIfNeeded(position: TimeInterval) {
        guard let snapshot, let idx = activeLineId,
              snapshot.lines.indices.contains(idx + 1) else { return }
        let next = snapshot.lines[idx + 1]
        let lead = next.start - position
        guard lead >= 0.18, lead <= 1.2 else { return }
        _ = layoutFor(line: next)
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        floatView.frame = bounds
        if let container = lineContainer {
            container.frame.origin = CGPoint(
                x: (bounds.width - container.bounds.width) / 2,
                y: (bounds.height - container.bounds.height) / 2)
        }
    }
}
