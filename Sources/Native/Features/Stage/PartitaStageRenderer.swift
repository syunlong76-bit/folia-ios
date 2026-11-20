import UIKit

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
    }
    var chunks: [Chunk]
    var fontSize: CGFloat
    var profile: StageLineProfile
    var columnWidth: CGFloat
    var columnHeight: CGFloat
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

    init(layout: PartitaLayout.Chunk, words: [GlowWordView], activeColor: UIColor) {
        self.layout = layout
        self.words = words
        self.activeColor = activeColor
        super.init(frame: CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
        isUserInteractionEnabled = false

        // 词行：左内边距 8pt 起，词距 12.8pt（0.8rem），纵向居中。
        var cursor: CGFloat = 8
        for word in words {
            word.frame.origin = CGPoint(
                x: cursor, y: (layout.height - word.bounds.height) / 2)
            addSubview(word)
            cursor += word.bounds.width + 12.8
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
    private var isActive = false
    private var activeLineId: Int? = nil
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var layoutCache: [Int: PartitaLayout] = [:]
    private var layoutCacheOrder: [Int] = []
    private var layoutViewportSize: CGSize = .zero

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
        self.snapshot = snapshot
        // 布局依赖视口（行数按视口高、字号按短边）：视口变
        // （旋转）时缓存与当前行一并失效重建。
        let viewportChanged = snapshot.viewport.size != layoutViewportSize
            && layoutViewportSize != .zero
        if snapshot.track?.id != builtTrackId
            || snapshot.lines.count != builtLineCount
            || viewportChanged {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
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
        var y: CGFloat = 0
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
                activeColor: snapshot.palette.accent)
            chunkView.frame.origin = CGPoint(
                x: (layout.columnWidth - chunkLayout.width) / 2, y: y)
            y += chunkLayout.height + 9.6
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
                                 columnWidth: 0, columnHeight: 0)
        }
        let profile = StageLineProfile.profile(for: line)
        let units = StageLyricUnits.units(for: line)
        let viewport = snapshot.viewport.size
        let vmin = min(viewport.width, viewport.height)
        let graphemeCount = line.text.reduce(0) {
            $0 + ($1.isWhitespace ? 0 : 1)
        }
        let totalGraphemes = max(graphemeCount, units.count, 1)
        let densityScale: CGFloat = totalGraphemes > 40 ? 0.8 : 1
        var fontSize = (vmin > 0
            ? max(40, min(5.5 * vmin / 100, 72)) : 40) * densityScale
        let font = StageFonts.bold(size: fontSize)

        // 行数：可用高 = 视口高 × 0.65，基准行高 100。
        let windowHeight = viewport.height > 0 ? viewport.height : rootView.bounds.height
        let targetRows = max(1, Int((windowHeight * 0.65 / 100).rounded(.down)))
        let actualRows = min(units.count, targetRows)

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
            var remainingUnits = units.count
            var remainingChunks = actualRows
            var unitIndex = 0
            for c in 0..<actualRows {
                let isLast = c == actualRows - 1
                var chunkLength = 1
                if isLast {
                    chunkLength = remainingUnits
                } else {
                    let avg = Double(remainingUnits) / Double(remainingChunks)
                    let maxLen = Int((avg * 1.5).rounded(.up))
                    let randVal = nextRandom()
                    chunkLength = max(1, min(maxLen,
                        Int((avg + (randVal - 0.5) * avg).rounded())))
                }
                chunkLength = max(1, min(chunkLength,
                                         remainingUnits - (remainingChunks - 1)))
                chunkUnitsList.append(Array(units[unitIndex..<unitIndex + chunkLength]))
                unitIndex += chunkLength
                remainingUnits -= chunkLength
                remainingChunks -= 1
            }
        }

        var chunks: [PartitaLayout.Chunk] = []
        var columnWidth: CGFloat = 0
        var columnHeight: CGFloat = 0
        let chunkHeight = fontSize * 1.22 + 6.4
        for (rowIndex, chunkUnits) in chunkUnitsList.enumerated() {
            let staggerMagnitude = CGFloat(20 + nextRandom() * 80)
            let staggerX = rowIndex % 2 == 0 ? -staggerMagnitude : staggerMagnitude
            let staggerScale = CGFloat(0.8 + nextRandom() * 0.9)
            let rowBias = CGFloat(rowIndex) - CGFloat(actualRows - 1) / 2
            // 词姿态（buildPartitaWordConfigs）：种子 = 首词
            // start + 词序 × 7.13，偏移 ±6、旋转 ±3、passed ±10°。
            var poses: [StageWordPose] = []
            var contentWidth: CGFloat = 0
            for (i, unit) in chunkUnits.enumerated() {
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
                contentWidth += (unit.text as NSString)
                    .size(withAttributes: [.font: font]).width + 12.8
            }
            let width = contentWidth + 16
            chunks.append(PartitaLayout.Chunk(
                units: chunkUnits, wordPoses: poses,
                x: staggerX, y: rowBias * 2.5,
                guideLeft: rowIndex % 2 == 0,
                width: width, height: chunkHeight))
            columnWidth = max(columnWidth, width)
            columnHeight += chunkHeight + 9.6
        }
        if !chunks.isEmpty { columnHeight -= 9.6 }
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
                let n = CGFloat(chunk.units.count)
                let sumW = chunk.width - 16 - 12.8 * n
                guard sumW > 0 else { continue }
                let room = availW - 40 - 12.8 * n - 16
                if room < sumW { scale = min(scale, max(room, 1) / sumW) }
            }
            if scale < 1 {
                scale = max(scale, 0.5)
                fontSize *= scale
                columnWidth = 0
                columnHeight = 0
                let newChunkHeight = fontSize * 1.22 + 6.4
                for i in chunks.indices {
                    let n = CGFloat(chunks[i].units.count)
                    let sumW = chunks[i].width - 16 - 12.8 * n
                    chunks[i].width = sumW * scale + 12.8 * n + 16
                    chunks[i].height = newChunkHeight
                    columnWidth = max(columnWidth, chunks[i].width)
                    columnHeight += newChunkHeight + 9.6
                }
                columnHeight -= 9.6
                clampStaggers()
            }
        }
        return PartitaLayout(
            chunks: chunks, fontSize: fontSize, profile: profile,
            columnWidth: columnWidth, columnHeight: columnHeight)
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
