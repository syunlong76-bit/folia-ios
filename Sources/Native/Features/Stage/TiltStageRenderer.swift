import UIKit
import NaturalLanguage

// 倾诉 tilt（M2' 照搬对齐版）：按 folia-major 网页版
// tilt/VisualizerTilt.tsx 的展示行为逐项实现。依据文件：
// VisualizerTilt.tsx、tilt/tuning.ts、tilt/entry.tsx、types.ts
// （DEFAULT_TILT_TUNING）、utils/lyrics/sentenceLayout.ts、
// utils/lyrics/renderHints.ts、utils/lyrics/graphemeTiming.ts、
// utils/iosWebKit.ts（lyricViewportUnit，iOS 取 vmin）。
// 对齐要点：
// - 画面只呈现当前一行：整行先按概率分成 1–4 个分段
// （determineLineCount + SentenceLayout），分段在纵列里居中
// 堆叠（段间 gap 12pt、视口宽 ≥640 时 16pt），按时间顺序
// 逐段揭示（段 start − 0.25s 起算），无当前行时画面空白
// （waitingForMusic 三份语言文件均为空串，与 classic 同）。
// - 「倾斜」在源码里不是容器透视/旋转：全行至多一个分段被
// 抽中为 tilt 段（概率 0.35），该段用斜体细字重（300）、
// 字距 0.15em，段内字素按奇偶交替上下错落 ±fontPx/6；
// 其余段为正体 400 字重、字距 0.08em。源码全文无
// perspective / rotate / skew 容器变换，故原生不臆造
// CATransform3D 透视；斜体在 Songti 无斜体字形，原生以
// 逐字斜切矩阵（c = −0.22）近似，差异见回报档案。
// - 逐字行为与 GlowWord 三态机不同源：tilt 无辉光扫光、无
// 词姿态随机、无 passed 态；字素只有「延迟淡入（段内序
// ×0.04/0.05s）+ 唱到时脉冲放大（sin 脉冲 + 0.25 余辉，
// 峰值 tilt 段 ×1.18 / 普通段 ×1.15）」。故不复用
// GlowWordView（强行复用会引入网页没有的辉光与姿态），
// 只复用 LyricStageRootView、StageFonts、StageLyricUnits
// （逐字时序来源）、ClassicStageRenderer.activeIndex
// （当前行判定）与种子随机公式 fract(sin(x)·10000)；
// tilt 自己的 seededRandom 入参为 sin(seed·1000+offset)，
// 在本文件内按源码另行实现，不与 stageSeededRandom 混用。
// - 调音参数（splitProbability 0.75 / tiltStyleProbability
// 0.35 / colorScheme default）来自 DEFAULT_TILT_TUNING，
// 经 TiltTuningStore（TiltTuning.swift，(57) C2）可调：
// 渲染器逐布局读 0.25s 缓存值，调参指纹变化即失效布局
// 缓存；colorScheme 四档（default/swap/accentAll/
// primaryAll）按 TiltLine.getColors 全落（正段/倾段取色
// 组合逐档对应）。协议快照本身无 tuning 字段，参数走
// 本地 UserDefaults，与网页 localStorage 存档同位。
// - 整行呼吸浮动源码没有（那是 classic/partita 侧的
// lyricContainerFloat），本样式不加。
// 时钟纪律不变：只消费宿主 frameTick 的锚点位置，不自建
// 时钟源；逐字脉冲在 frameTick 内按位置直接算，不跑定时器。
final class TiltStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    private var lineContainer: UIView?
    private var segmentViews: [TiltSegmentView] = []
    private var currentLayout: TiltLayoutData?
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false
    private var activeLineId: Int? = nil
    /// §0 量测（3.7 (67) B 组）：flip.up 每行只落一次的记账。
    private var probeUpLine67: Int? = nil
    private var visibleSegmentIndex = -1
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var builtViewportSize: CGSize = .zero
    private var layoutCache: [Int: TiltLayoutData] = [:]
    private var layoutCacheOrder: [Int] = []
    /// 上次构建布局时的调参指纹：概率/配色任一变化，整表
    /// 布局缓存失效（网页 tuning 变化即重算 layout 同义）。
    private var builtTuning: TiltTuningValues? = nil

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
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
        // 布局依赖视口（字号按 vmin、可用宽按视口宽）：视口
        // 变（旋转）时缓存与当前行一并失效重建（同 partita）。
        let viewportChanged = snapshot.viewport.size != builtViewportSize
            && builtViewportSize != .zero
        if snapshot.track?.id != builtTrackId
            || snapshot.lines.count != builtLineCount
            || viewportChanged {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            layoutCache.removeAll()
            layoutCacheOrder.removeAll()
            clearLine()
        }
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        // 本样式无自持时钟/呼吸层，inactive 时 frameTick 自行
        // 守门即停掉全部逐帧工作（脉冲只在 frameTick 内算）。
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let idx = ClassicStageRenderer.activeIndex(in: snapshot.lines, at: position)
        if idx != activeLineId {
            // §0 呈现侧（3.7 (67) B 组）：翻行提交点。
            Breadcrumbs.log("flip.cmt style=tilt idx=\(idx ?? -1) judge=\(SyncProbe67.fmt(position)) wall=\(SyncProbe67.fmt(CACurrentMediaTime()))")
            transitionLine(to: idx, position: position)
        }
        guard let layout = currentLayout, let lineIndex = activeLineId,
            snapshot.lines.indices.contains(lineIndex) else { return }
        let line = snapshot.lines[lineIndex]
        // 可见段序号（源码 useLayoutEffect 口径）：最后一个
        // start − 0.25 ≤ position 的段；position 在
        // [行 start − 0.1, renderEnd] 之外时为 −1（全隐）。
        // renderEnd 为 renderHints 公式值（Self.renderEnd，
        // (57) C2 起逐行移植，不再以 end + 0.35 近似）。
        var target = -1
        if position >= line.start - 0.1 && position <= Self.renderEnd(of: line) {
            for i in layout.segments.indices {
                if position >= layout.segmentTimings[i].start - 0.25 {
                    target = i
                }
            }
        }
        if target != visibleSegmentIndex {
            visibleSegmentIndex = target
            for (i, segmentView) in segmentViews.enumerated() {
                segmentView.setVisible(i <= target, animated: true)
            }
        }
        // §0 呈现侧（3.7 (67) B 组）：级联收敛点＝末段亮起的
        // 那一帧（段尾滞后在此量到），每行只落一次。
        if target >= 0, target == layout.segments.count - 1,
           probeUpLine67 != lineIndex {
            probeUpLine67 = lineIndex
            Breadcrumbs.log("flip.up style=tilt idx=\(lineIndex) judge=\(SyncProbe67.fmt(position)) wall=\(SyncProbe67.fmt(CACurrentMediaTime()))")
        }
        for segmentView in segmentViews {
            segmentView.updatePulse(position: position)
        }
    }

    func unmount() {
        isActive = false
        clearLine()
        layoutCache.removeAll()
        layoutCacheOrder.removeAll()
        context = nil
        snapshot = nil
    }

    // MARK: 行切换

    private func clearLine() {
        lineContainer?.removeFromSuperview()
        lineContainer = nil
        segmentViews = []
        currentLayout = nil
        activeLineId = nil
        visibleSegmentIndex = -1
    }

    private func transitionLine(to idx: Int?, position: TimeInterval) {
        // 旧行出场：整容器淡出 0.45s easeInOut 后移除（源码
        // 外层 motion.div exit），段级 exit 姿态（普通
        // y −12 / tilt y −16·scale 0.95）由各段自身动画叠加
        //（(57) C2 补齐；网页段级时长 0.55/0.6 略长于容器
        // 0.45，原生以容器移除为界截断，残差见报告）。
        if let old = lineContainer {
            let oldSegments = segmentViews
            lineContainer = nil
            segmentViews = []
            for segmentView in oldSegments { segmentView.applyExitPose() }
            UIView.animate(withDuration: 0.45, delay: 0,
                           options: [.curveEaseInOut]) {
                old.alpha = 0
            } completion: { _ in old.removeFromSuperview() }
        }
        activeLineId = idx
        currentLayout = nil
        visibleSegmentIndex = -1
        guard let idx, let snapshot,
            snapshot.lines.indices.contains(idx) else { return }
        let line = snapshot.lines[idx]
        let layout = layoutFor(line: line)
        currentLayout = layout

        let container = UIView()
        container.isUserInteractionEnabled = false
        // 配色方案（TiltLine.getColors 四档，(57) C2 全落）：
        // default 正 primary/倾 accent、swap 正 accent/倾
        // primary、accentAll 皆 accent、primaryAll 皆 primary。
        let scheme = TiltTuningStore.valuesCached(
            now: CACurrentMediaTime()).colorScheme
        let normalColor: UIColor
        let tiltColor: UIColor
        switch scheme {
        case .default:
            normalColor = snapshot.palette.primary
            tiltColor = snapshot.palette.accent
        case .swap:
            normalColor = snapshot.palette.accent
            tiltColor = snapshot.palette.primary
        case .accentAll:
            normalColor = snapshot.palette.accent
            tiltColor = snapshot.palette.accent
        case .primaryAll:
            normalColor = snapshot.palette.primary
            tiltColor = snapshot.palette.primary
        }
        var views: [TiltSegmentView] = []
        for (i, segment) in layout.segments.enumerated() {
            let segmentView = TiltSegmentView(
                segment: segment,
                fontSize: layout.fontSizes[i],
                font: layout.fonts[i],
                color: segment.isTilt ? tiltColor : normalColor,
                charTimings: layout.charTimings[i],
                yOffset: layout.yOffset)
            views.append(segmentView)
            container.addSubview(segmentView)
        }
        lineContainer = container
        segmentViews = views
        rootView.addSubview(container)
        layoutContainer(container)

        // 构建后按当前位定格（中途进台/seek 落位）：已到揭示
        // 时刻的段直接摆到落定态，不补播入场动画。
        var target = -1
        if position >= line.start - 0.1 && position <= Self.renderEnd(of: line) {
            for i in layout.segments.indices {
                if position >= layout.segmentTimings[i].start - 0.25 {
                    target = i
                }
            }
        }
        visibleSegmentIndex = target
        for (i, segmentView) in views.enumerated() {
            segmentView.setVisible(i <= target, animated: false)
            segmentView.updatePulse(position: position)
        }
        // 新行入场：整容器淡入（源码 initial opacity 0 →
        // animate 1；源码未给该层 transition，原生取 0.3s
        // easeOut，与 classic 行入场同时长）。
        container.alpha = 0
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            container.alpha = 1
        }
    }

    private func layoutContainer(_ container: UIView) {
        guard let layout = currentLayout else { return }
        let bounds = rootView.bounds
        let gap = segmentGap()
        var totalHeight: CGFloat = 0
        for size in layout.segmentSizes { totalHeight += size.height }
        if layout.segmentSizes.count > 1 {
            totalHeight += gap * CGFloat(layout.segmentSizes.count - 1)
        }
        let width = layout.segmentSizes.map { $0.width }.max() ?? 0
        container.frame = CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - totalHeight) / 2,
            width: width, height: totalHeight)
        var cursorY: CGFloat = 0
        for (i, segmentView) in segmentViews.enumerated() {
            let size = layout.segmentSizes[i]
            segmentView.frame = CGRect(
                x: (width - size.width) / 2, y: cursorY,
                width: size.width, height: size.height)
            cursorY += size.height + gap
        }
    }

    /// 段间纵距：源码 gap-y-3（12pt），sm（≥640pt 宽）gap-y-4。
    private func segmentGap() -> CGFloat {
        viewportSize().width >= 640 ? 16 : 12
    }

    private func viewportSize() -> CGSize {
        if let size = snapshot?.viewport.size, size.width > 0, size.height > 0 {
            return size
        }
        return rootView.bounds.size
    }

    // MARK: 布局构建（VisualizerTilt.buildTiltLayout 逐项对应）

    private func layoutFor(line: LyricLine) -> TiltLayoutData {
        // 调参指纹变化 → 整表失效（概率决定分段与 tilt 段
        // 抽选，旧布局不得跨调参复用）。
        let tuning = TiltTuningStore.valuesCached(now: CACurrentMediaTime())
        if builtTuning != tuning {
            builtTuning = tuning
            layoutCache.removeAll()
            layoutCacheOrder.removeAll()
        }
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

    private func buildLayout(line: LyricLine) -> TiltLayoutData {
        // 调参经 TiltTuningStore 读（缺省 = DEFAULT_TILT_
        // TUNING，(57) C2）；lyricsFontScale 的原生落点为
        // 视口 dynamicTypeScale（本期恒 1，同 still 口径）。
        let tuning = TiltTuningStore.valuesCached(now: CACurrentMediaTime())
        let splitProbability = tuning.splitProbability
        let tiltStyleProbability = tuning.tiltStyleProbability
        let fontScale = snapshot?.viewport.dynamicTypeScale ?? 1

        let viewport = viewportSize()
        let viewportWidth = viewport.width > 0 ? viewport.width : 390
        let vmin = min(viewportWidth, viewport.height > 0 ? viewport.height : viewportWidth)
        // 测量基准（源码 measureMaxPx）：max(视口宽 × 0.06875,
        // 5.625rem × fontScale)；可用宽 = max(320, 视口宽) × 0.85。
        let measureBasePx = max(viewportWidth * 0.06875, 90 * fontScale)
        let availableWidth = max(320, viewportWidth) * 0.85
        let normalMeasureFont = Self.songtiRegular(size: measureBasePx)
        let tiltMeasureFont = StageFonts.light(size: measureBasePx)

        let fullText = line.text
        // 网页 charCount = fullText.trim().length：JS length
        // 为 UTF-16 码元数，原生以修剪后 utf16.count 对齐
        //（字素数在星光字符上会少计，(57) C2 修正）。
        let trimmedCount = fullText
            .trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        let isEllipsisOnly = Self.isEllipsisOnly(fullText)

        var segmentTexts: [String]
        if isEllipsisOnly {
            segmentTexts = [fullText]
        } else {
            let numLines = Self.determineLineCount(
                charCount: trimmedCount, seed: line.start,
                splitProbability: splitProbability)
            segmentTexts = TiltSentenceSplitter.splitIntoSentences(
                text: fullText, targetCount: numLines, seed: line.start)
        }

        // tilt 段抽选：每段先掷 roll（offset 100+i），中选者
        // 再掷一次（offset 200）挑唯一 tilt 段。
        var candidates: [Int] = []
        for i in segmentTexts.indices {
            let roll = Self.tiltSeededRandom(seed: line.start, offset: 100 + Double(i))
            if roll < tiltStyleProbability { candidates.append(i) }
        }
        var tiltIndex = -1
        if !candidates.isEmpty {
            let pick = Int((Self.tiltSeededRandom(seed: line.start, offset: 200)
                * Double(candidates.count)).rounded(.down))
            tiltIndex = candidates[min(pick, candidates.count - 1)]
        }

        var segments: [TiltSegmentData] = []
        var offsetAccum = 0
        for (i, rawText) in segmentTexts.enumerated() {
            let leading = rawText.count - rawText.drop(while: { $0 == " " || $0 == "\t" }).count
            let trimmed = rawText.trimmingCharacters(in: .whitespaces)
            segments.append(TiltSegmentData(
                text: trimmed, isTilt: i == tiltIndex,
                isShortLastLine: false, charOffset: offsetAccum + leading))
            offsetAccum += rawText.count
        }

        func measure(_ text: String, font: UIFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }

        var scaleMultiplier: CGFloat = 1
        let tiltWidths = segments.filter { $0.isTilt }
            .map { measure($0.text, font: tiltMeasureFont) }
        let normalWidths = segments.filter { !$0.isTilt }
            .map { measure($0.text, font: normalMeasureFont) }
        let tiltWidth = tiltWidths.max() ?? 0
        let normalWidth = normalWidths.max() ?? 0
        let tiltOverflow = tiltWidth > 0 ? tiltWidth / availableWidth : 0
        let normalOverflow = normalWidth > 0 ? normalWidth / availableWidth : 0
        let maxOverflow = max(tiltOverflow, normalOverflow)

        if maxOverflow > 1 {
            if maxOverflow >= 1.6 {
                // RESPLIT_THRESHOLD：重切更多段再定缩放。
                let targetWidth = availableWidth * (1.6 - 0.15)
                let totalEstWidth = measure(fullText, font: normalMeasureFont)
                let extra = min(4, max(segments.count + 1,
                                       Int((totalEstWidth / targetWidth).rounded(.up))))
                if extra > segments.count {
                    let reTexts = TiltSentenceSplitter.splitIntoSentences(
                        text: fullText, targetCount: extra, seed: line.start)
                    var reSegments: [TiltSegmentData] = []
                    var reOffset = 0
                    for rawText in reTexts {
                        let dropped: Substring = rawText.drop(
                            while: { $0 == " " || $0 == "\t" })
                        let leading = rawText.count - dropped.count
                        let trimmed = rawText.trimmingCharacters(
                            in: CharacterSet.whitespaces)
                        reSegments.append(TiltSegmentData(
                            text: trimmed, isTilt: false,
                            isShortLastLine: false, charOffset: reOffset + leading))
                        reOffset += rawText.count
                    }
                    if !reSegments.isEmpty {
                        let roll = Self.tiltSeededRandom(seed: line.start, offset: 300)
                        if roll < tiltStyleProbability {
                            let picked = Int((Self.tiltSeededRandom(
                                seed: line.start, offset: 301)
                                * Double(reSegments.count)).rounded(.down))
                            reSegments[min(picked, reSegments.count - 1)].isTilt = true
                        }
                    }
                    var postScale: CGFloat = 1
                    if let tiltSeg = reSegments.first(where: { $0.isTilt }) {
                        let w = measure(tiltSeg.text, font: tiltMeasureFont)
                        if w > availableWidth {
                            postScale = max(0.5, availableWidth / w)
                        }
                    } else if let widest = reSegments.filter({ !$0.isTilt })
                        .map({ measure($0.text, font: normalMeasureFont) }).max() {
                        if widest > availableWidth {
                            postScale = max(0.55, availableWidth / widest)
                        }
                    }
                    segments = Self.markShortLastLine(reSegments)
                    return finishLayout(line: line, segments: segments,
                                        scaleMultiplier: postScale,
                                        fontScale: fontScale, vmin: vmin,
                                        viewportWidth: viewportWidth)
                }
            }
            if tiltOverflow >= normalOverflow && tiltWidth > 0 {
                scaleMultiplier = max(0.5, availableWidth / tiltWidth)
            } else if normalWidth > 0 {
                scaleMultiplier = max(0.55, availableWidth / normalWidth)
            }
        }

        segments = Self.markShortLastLine(segments)
        return finishLayout(line: line, segments: segments,
                            scaleMultiplier: scaleMultiplier,
                            fontScale: fontScale, vmin: vmin,
                            viewportWidth: viewportWidth)
    }

    /// 由最终分段组装布局：字号、字体、段尺寸、段时序、逐字时序。
    private func finishLayout(line: LyricLine, segments: [TiltSegmentData],
        scaleMultiplier: CGFloat, fontScale: CGFloat,
        vmin: CGFloat, viewportWidth: CGFloat) -> TiltLayoutData {
        builtViewportSize = viewportSize()
        let base = fontScale * scaleMultiplier
        // tiltFontPx（源码 TiltLine）：min(视口宽 × 0.06875 ×
        // base, 5.625rem × base)；yOffset = tiltFontPx / 6。
        let tiltFontPx = min(viewportWidth * 0.06875 * base, 90 * base)
        let yOffset = tiltFontPx / 6

        var fontSizes: [CGFloat] = []
        var fonts: [UIFont] = []
        var sizes: [CGSize] = []
        for segment in segments {
            // 字号 clamp(3.125rem×s, 6.875vmin×s, 5.625rem×s)；
            // 普通段短末段 ×1.18（shortLastBoost），tilt 段无。
            let boost: CGFloat = segment.isShortLastLine && !segment.isTilt ? 1.18 : 1
            let s = base * boost
            let size = max(50 * s, min(6.875 * vmin / 100 * s, 90 * s))
            fontSizes.append(size)
            // 字重：普通 400 / tilt 300（resolveThemeFontWeight
            // 的 fallback；主题自带 fontWeight 时网页整体覆盖，
            // 协议无此字段，未落）。
            let font = segment.isTilt ? StageFonts.light(size: size)
                : Self.songtiRegular(size: size)
            fonts.append(font)
            let height = size * (segment.isTilt ? 1.25 : 1.35)
            let width = TiltSegmentView.measureWidth(
                text: segment.text, font: font, fontSize: size,
                isTilt: segment.isTilt)
            sizes.append(CGSize(width: width, height: height))
        }

        let timings = segmentTimings(for: line, segments: segments)
        var charTimings: [[TiltCharTiming]] = []
        for (i, segment) in segments.enumerated() {
            charTimings.append(buildCharTimings(
                line: line, segment: segment,
                segmentStart: timings[i].start, segmentEnd: timings[i].end))
        }
        return TiltLayoutData(
            segments: segments, scaleMultiplier: scaleMultiplier,
            fontSizes: fontSizes, fonts: fonts, segmentSizes: sizes,
            segmentTimings: timings, charTimings: charTimings,
            yOffset: yOffset)
    }

    // MARK: 时序（segmentTimings / buildCharTimings 对应）

    /// 全行非空白字素的逐字时序（以 StageLyricUnits 的单元
    /// 为源：单元内字素均分，与网页 buildWordGraphemeTimings
    /// 无音节数据时的 even 口径一致；YRC 逐字戳在场时单元即
    /// 真词，时序随之为真戳）。
    private func lineCharTimings(for line: LyricLine) -> [TiltCharTiming] {
        let units = StageLyricUnits.units(for: line)
        var result: [TiltCharTiming] = []
        for unit in units {
            let graphemes = unit.text.filter { !$0.isWhitespace }
            guard !graphemes.isEmpty else { continue }
            let span = max(unit.end - unit.start, 0.05)
            for (j, _) in graphemes.enumerated() {
                result.append(TiltCharTiming(
                    charIndex: result.count,
                    start: unit.start + span * Double(j) / Double(graphemes.count),
                    end: unit.start + span * Double(j + 1) / Double(graphemes.count)))
            }
        }
        return result
    }

    /// 段在全行非空白字素序中的起始下标。
    private func nonSpaceOffset(fullText: String, charOffset: Int) -> Int {
        let graphemes = Array(fullText)
        var count = 0
        for i in 0..<min(charOffset, graphemes.count) {
            if !graphemes[i].isWhitespace { count += 1 }
        }
        return count
    }

    private func segmentTimings(for line: LyricLine,
        segments: [TiltSegmentData]) -> [(start: TimeInterval, end: TimeInterval)] {
        let units = StageLyricUnits.units(for: line)
        // 每个单元覆盖的非空白字素区间（与 lineCharTimings 同序）。
        var unitRanges: [(start: Int, end: Int, timeStart: TimeInterval, timeEnd: TimeInterval)] = []
        var cursor = 0
        for unit in units {
            let count = unit.text.filter { !$0.isWhitespace }.count
            unitRanges.append((cursor, cursor + count, unit.start, unit.end))
            cursor += count
        }
        return segments.map { segment in
            let segStart = nonSpaceOffset(fullText: line.text, charOffset: segment.charOffset)
            let segCount = segment.text.filter { !$0.isWhitespace }.count
            let segEnd = segStart + segCount
            let overlapping = unitRanges.filter { $0.start < segEnd && $0.end > segStart }
            if let first = overlapping.first, let last = overlapping.last {
                return (first.timeStart, last.timeEnd)
            }
            // 源码兜底：段无词时 start = 行 start、end =
            // getLineRenderEndTime（Self.renderEnd 公式值）。
            return (line.start, Self.renderEnd(of: line))
        }
    }

    private func buildCharTimings(line: LyricLine, segment: TiltSegmentData,
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval) -> [TiltCharTiming] {
        let nonSpaceCount = segment.text.filter { !$0.isWhitespace }.count
        guard nonSpaceCount > 0 else { return [] }
        let global = lineCharTimings(for: line)
        let start = nonSpaceOffset(fullText: line.text, charOffset: segment.charOffset)
        if global.count >= start + nonSpaceCount {
            // 与网页一致：切片后 charIndex 重排为段内序。
            return (0..<nonSpaceCount).map { i in
                let t = global[start + i]
                return TiltCharTiming(charIndex: i, start: t.start, end: t.end)
            }
        }
        // 源码兜底：时序数与段字素数对不上时整段均分，
        // 总时长下限 0.3s。
        let totalDuration = max(segmentEnd - segmentStart, 0.3)
        let avg = totalDuration / Double(nonSpaceCount)
        return (0..<nonSpaceCount).map { i in
            TiltCharTiming(charIndex: i,
                           start: segmentStart + Double(i) * avg,
                           end: segmentStart + Double(i + 1) * avg)
        }
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        // 视口宽变化（旋转）时字号/分段宽度口径随之变：
        // applySnapshot 已清缓存，这里重建当前行。
        if let container = lineContainer {
            if builtViewportSize != .zero
                && snapshot?.viewport.size != builtViewportSize,
                let idx = activeLineId {
                let position = context?.positionNow() ?? 0
                lineContainer?.removeFromSuperview()
                lineContainer = nil
                segmentViews = []
                activeLineId = nil
                transitionLine(to: idx, position: position)
            } else {
                layoutContainer(container)
            }
        }
    }

    // MARK: 源码常量与判定（类内静态工具）

    /// Songti 正体 400（StageFonts 只有 700/300 两档，400 在
    /// 本文件内取 STSongti-SC-Regular，缺失时系统正体）。
    static func songtiRegular(size: CGFloat) -> UIFont {
        UIFont(name: "STSongti-SC-Regular", size: size)
            ?? .systemFont(ofSize: size, weight: .regular)
    }

    /// tilt 专用种子随机（源码 seededRandom）：fract(sin(seed
    /// × 1000 + offset) × 10000)。与 GlowWordEngine 的
    /// stageSeededRandom（sin(x) 本值）入参口径不同，不混用。
    static func tiltSeededRandom(seed: Double, offset: Double) -> Double {
        let x = sin(seed * 1000 + offset) * 10000
        return x - floor(x)
    }

    /// determineLineCount：CHAR_REF_LENGTH 20、LOG_OFFSET 4、
    /// 阈值 [0.45, 1.05, 1.7]；字数口径原生以字素数近似
    /// JS 的 UTF-16 length（BMP 内一致，见档案）。
    static func determineLineCount(charCount: Int, seed: Double,
        splitProbability: Double) -> Int {
        let normalized = log(Double(charCount) + 4) / log(24)
        let jitter = tiltSeededRandom(seed: seed, offset: 1) * 0.6 + 0.7
        let score = normalized * jitter * splitProbability
        if score < 0.45 { return 1 }
        if score < 1.05 { return 2 }
        if score < 1.7 { return 3 }
        return 4
    }

    /// 纯省略号行（源码 /^[\s.…·。]+$/）不分段。
    static func isEllipsisOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let allowed: Set<Character> = [" ", ".", "…", "·", "。", "\t"]
        return trimmed.allSatisfy { allowed.contains($0) || $0.isWhitespace }
    }

    /// markShortLastLine：末段非 tilt、修剪后 ≤2 字且长度
    /// ×2 ≤ 前段长度时标短末段（渲染时字号 ×1.18）。长度
    /// 口径为 JS length（UTF-16 码元）：末段取 trim 后、
    /// 前段取段文本原长（网页源码同，(57) C2 对齐）。
    fileprivate static func markShortLastLine(_ input: [TiltSegmentData]) -> [TiltSegmentData] {
        var segs = input
        guard segs.count >= 2 else { return segs }
        let last = segs[segs.count - 1]
        let lastTrimmedLength = last.text
            .trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        if last.isTilt || lastTrimmedLength > 2 { return segs }
        let prev = segs[segs.count - 2]
        if lastTrimmedLength * 2 <= prev.text.utf16.count {
            segs[segs.count - 1].isShortLastLine = true
        }
        return segs
    }

    /// getLineRenderEndTime（utils/lyrics/renderHints.ts 的
    /// buildLineRenderHints 公式逐行移植，(57) C2）：按行时
    /// 长分 micro（<0.10）/ short（<0.18）/ normal 三档算
    /// renderEndTime。协议 LyricLine 无 renderHints 字段，
    /// 但该值本就是 start/end/末词 end 的纯函数（网页
    /// getLineRenderHints 在行上无存档时同样现算），数据
    /// 通路无缺口。lastWordEnd 取协议 words 末词 end、无词
    /// 时行 end（网页 getLastWordEndTime 同义）。
    static func renderEnd(of line: LyricLine) -> TimeInterval {
        let rawDuration = max(line.end - line.start, 0)
        if rawDuration < 0.10 {
            // micro：transitionMode none，renderEnd 下限
            // start + MICRO_LINE_RENDER_FLOOR(0.067)。
            return max(line.end, line.start + 0.067)
        }
        let lastWordEnd = line.words?.last?.end ?? line.end
        if rawDuration < 0.18 {
            // short/fast：enter clamp(raw×0.45, .045, .06)、
            // exit clamp(raw×0.22, .03, .04)、hold 0.03。
            let enter = min(0.06, max(0.045, rawDuration * 0.45))
            let exit = min(0.04, max(0.03, rawDuration * 0.22))
            let linePassStart = max(lastWordEnd, line.start) + 0.03
            let exitStart = max(line.start + enter + 0.01,
                                linePassStart, line.end - exit)
            return max(line.end, exitStart + exit)
        }
        // normal：exit min(.32, max(.18, max(raw,.12)×.18))、
        // hold 0.06（enter 只参与 fast 档 exitStart，源码同）。
        let exit = min(0.32, max(0.18, max(rawDuration, 0.12) * 0.18))
        let linePassStart = max(lastWordEnd, line.start) + 0.06
        let exitStart = max(linePassStart, line.end - exit)
        return max(line.end, exitStart + exit)
    }

    /// 逐字脉冲强度（源码 getCharPulseIntensity）：时长夹在
    /// [0.2, 0.9]（原始下限 0.05）；段内 sin(π·p) 升降，
    /// 段后以 duration × 1.2 的斜坡爬到 0.25 余辉并保持。
    static func charPulseIntensity(currentTime: TimeInterval,
        start: TimeInterval,
        end: TimeInterval) -> CGFloat {
        let rawDuration = max(end - start, 0.05)
        let duration = min(max(rawDuration, 0.2), 0.9)
        let elapsed = currentTime - start
        if elapsed < 0 { return 0 }
        if elapsed <= duration {
            return CGFloat(sin(elapsed / duration * .pi))
        }
        let afterElapsed = elapsed - duration
        let afterglowRamp = duration * 1.2
        if afterElapsed >= afterglowRamp { return 0.25 }
        return CGFloat(0.25 * (afterElapsed / afterglowRamp))
    }
}

// MARK: - 布局数据

private struct TiltSegmentData {
    var text: String
    var isTilt: Bool
    var isShortLastLine: Bool
    var charOffset: Int
}

private struct TiltCharTiming {
    var charIndex: Int
    var start: TimeInterval
    var end: TimeInterval
}

private struct TiltLayoutData {
    var segments: [TiltSegmentData]
    var scaleMultiplier: CGFloat
    var fontSizes: [CGFloat]
    var fonts: [UIFont]
    var segmentSizes: [CGSize]
    var segmentTimings: [(start: TimeInterval, end: TimeInterval)]
    var charTimings: [[TiltCharTiming]]
    var yOffset: CGFloat
}

// MARK: - 分段视图

/// 一个分段的视图：逐字素单元（外层 wrapper 管淡入与错落
/// 位移，内层 label 管脉冲缩放与斜切），段级管进出场位移/
/// 缩放/透明。动画曲线为源码 framer-motion 的
/// cubic-bezier(0.25, 0.46, 0.45, 0.94)。
private final class TiltSegmentView: UIView {

    private struct CharCell {
        var wrapper: UIView
        var label: UILabel
        var isSpace: Bool
        var visualIndex: Int
        var timingIndex: Int
    }

    private let segment: TiltSegmentData
    private let charTimings: [TiltCharTiming]
    private let yOffset: CGFloat
    private var cells: [CharCell] = []
    private(set) var isShown = false

    init(segment: TiltSegmentData, fontSize: CGFloat, font: UIFont,
        color: UIColor, charTimings: [TiltCharTiming], yOffset: CGFloat) {
        self.segment = segment
        self.charTimings = charTimings
        self.yOffset = yOffset
        super.init(frame: .zero)
        isUserInteractionEnabled = false

        let letterSpacing = fontSize * (segment.isTilt ? 0.15 : 0.08)
        let spaceWidth = fontSize * (segment.isTilt ? 0.35 : 0.25)
        let segmentHeight = fontSize * (segment.isTilt ? 1.25 : 1.35)
        var cursor: CGFloat = 0
        var visualIndex = 0
        for grapheme in segment.text.map({ String($0) }) {
            let isSpace = grapheme.allSatisfy { $0.isWhitespace }
            let wrapper = UIView()
            wrapper.isUserInteractionEnabled = false
            let label = UILabel()
            label.text = isSpace ? "\u{00A0}" : grapheme
            label.font = font
            label.textColor = color
            label.isUserInteractionEnabled = false
            label.sizeToFit()
            let width = isSpace ? spaceWidth : label.bounds.width
            let height = label.bounds.height
            label.frame = CGRect(x: 0, y: 0, width: width, height: height)
            if segment.isTilt && !isSpace {
                // 斜体近似：逐字斜切（见头部注释）。
                label.transform = CGAffineTransform(
                    a: 1, b: 0, c: -0.22, d: 1, tx: 0, ty: 0)
            }
            wrapper.frame = CGRect(
                x: cursor, y: (segmentHeight - height) / 2,
                width: width, height: height)
            wrapper.addSubview(label)
            addSubview(wrapper)
            let timingIndex = isSpace ? -1 : visualIndex
            if !isSpace { visualIndex += 1 }
            cells.append(CharCell(
                wrapper: wrapper, label: label, isSpace: isSpace,
                visualIndex: timingIndex, timingIndex: timingIndex))
            cursor += width + letterSpacing
        }
        applyHiddenPose(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 段宽测量（与 init 内的逐字排布同口径，供布局阶段定尺寸）。
    static func measureWidth(text: String, font: UIFont,
        fontSize: CGFloat, isTilt: Bool) -> CGFloat {
        let letterSpacing = fontSize * (isTilt ? 0.15 : 0.08)
        let spaceWidth = fontSize * (isTilt ? 0.35 : 0.25)
        var width: CGFloat = 0
        var count = 0
        for grapheme in text.map({ String($0) }) {
            if grapheme.allSatisfy({ $0.isWhitespace }) {
                width += spaceWidth
            } else {
                width += (grapheme as NSString)
                    .size(withAttributes: [.font: font]).width
            }
            count += 1
        }
        if count > 1 { width += letterSpacing * CGFloat(count - 1) }
        return width
    }

    // MARK: 姿态与显隐

    private func hiddenTransform() -> CGAffineTransform {
        if segment.isTilt {
            return CGAffineTransform(translationX: 0, y: 24)
                .scaledBy(x: 0.92, y: 0.92)
        }
        return CGAffineTransform(translationX: 0, y: 20)
    }

    private func charHiddenOffset(visualIndex: Int, isSpace: Bool) -> CGFloat {
        guard segment.isTilt, !isSpace else { return 0 }
        let stagger: CGFloat = visualIndex % 2 == 0 ? -1 : 1
        return stagger * yOffset * 2
    }

    private func charShownOffset(visualIndex: Int, isSpace: Bool) -> CGFloat {
        guard segment.isTilt, !isSpace else { return 0 }
        let stagger: CGFloat = visualIndex % 2 == 0 ? -1 : 1
        return stagger * yOffset
    }

    private func applyHiddenPose(animated: Bool) {
        let apply = {
            self.transform = self.hiddenTransform()
            self.alpha = 0
            for cell in self.cells {
                cell.wrapper.alpha = 0
                cell.wrapper.transform = CGAffineTransform(
                    translationX: 0,
                    y: self.charHiddenOffset(visualIndex: cell.visualIndex,
                                             isSpace: cell.isSpace))
            }
        }
        if animated {
            Self.bezierAnimator(duration: segment.isTilt ? 0.6 : 0.55,
                                animations: apply).startAnimation()
        } else { apply() }
    }

    /// 显隐切换（源码 TiltLine 的 initial/animate 两态）：段级
    /// 0.55s（普通）/0.6s（tilt），字素 0.5s + 段内序延迟
    /// （普通 ×0.04、tilt ×0.05，空格无延迟）。
    func setVisible(_ visible: Bool, animated: Bool) {
        guard visible != isShown || !animated else {
            if visible { return }
            return
        }
        isShown = visible
        if !visible {
            applyHiddenPose(animated: animated)
            return
        }
        let segmentApply = {
            self.transform = .identity
            self.alpha = 1
        }
        if animated {
            Self.bezierAnimator(duration: segment.isTilt ? 0.6 : 0.55,
                                animations: segmentApply).startAnimation()
        } else { segmentApply() }
        for cell in cells {
            let delay = animated && !cell.isSpace
                ? Double(cell.visualIndex) * (segment.isTilt ? 0.05 : 0.04) : 0
            let apply = {
                cell.wrapper.alpha = 1
                cell.wrapper.transform = CGAffineTransform(
                    translationX: 0,
                    y: self.charShownOffset(visualIndex: cell.visualIndex,
                                            isSpace: cell.isSpace))
            }
            if animated {
                Self.bezierAnimator(duration: 0.5, animations: apply)
                    .startAnimation(afterDelay: delay)
            } else { apply() }
        }
    }

    /// 段级出场姿态（源码 TiltLine exit：普通 y −12、tilt
    /// y −16 + scale 0.95、opacity 0；曲线同段级 bezier）。
    func applyExitPose() {
        let apply = {
            self.alpha = 0
            if self.segment.isTilt {
                self.transform = CGAffineTransform(translationX: 0, y: -16)
                    .scaledBy(x: 0.95, y: 0.95)
            } else {
                self.transform = CGAffineTransform(translationX: 0, y: -12)
            }
        }
        Self.bezierAnimator(duration: 0.45, animations: apply).startAnimation()
    }

    /// 逐字脉冲（frameTick 驱动）：scale = 1 + 强度 ×（tilt
    /// 0.18 / 普通 0.15）；源码靠 MotionValue + CSS 0.06s
    /// 过渡平滑，原生逐帧直设（60fps 下更跟手，见档案）。
    func updatePulse(position: TimeInterval) {
        guard isShown else { return }
        for cell in cells {
            if cell.isSpace { continue }
            var scale: CGFloat = 1
            if cell.timingIndex >= 0 && cell.timingIndex < charTimings.count {
                let timing = charTimings[cell.timingIndex]
                let intensity = TiltStageRenderer.charPulseIntensity(
                    currentTime: position, start: timing.start, end: timing.end)
                scale = 1 + intensity * (segment.isTilt ? 0.18 : 0.15)
            }
            if segment.isTilt {
                cell.label.transform = CGAffineTransform(
                    a: scale, b: 0, c: -0.22 * scale, d: scale, tx: 0, ty: 0)
            } else {
                cell.label.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
    }

    /// 源码 framer-motion 曲线 cubic-bezier(0.25, 0.46, 0.45, 0.94)。
    static func bezierAnimator(duration: TimeInterval,
        animations: @escaping () -> Void) -> UIViewPropertyAnimator {
        let params = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0.25, y: 0.46),
            controlPoint2: CGPoint(x: 0.45, y: 0.94))
        let animator = UIViewPropertyAnimator(
            duration: duration, timingParameters: params)
        animator.addAnimations(animations)
        return animator
    }
}

// MARK: - 句子分段（SentenceLayout.splitIntoSentences 对应）

/// 源码 SentenceLayout 的原生移植：五级切分（标点 → 括号
/// 引号 → 西文词块 → CJK 空格 → 特殊符）逐级切到目标段数，
/// 不足时 secondarySplit 补切、过量时 mergeSentences 并最
/// 短对。字数口径以字素计（源码为 JS UTF-16 length，BMP
/// 内一致；已单项对齐 UTF-16 的判定点见 determineLineCount
/// 与 markShortLastLine）。secondarySplit 的 Intl.Segmenter
/// 词边界以 NLTokenizer（.word）承接（(57) C2）：词起点集、
/// 最接近中点的间隙、score = balance×10 + 词数均照网页
/// 公式；无可用词边界时走网页兜底（种子伪随机选段、中点
/// 切开）。残差：NLTokenizer 与 ICU Intl.Segmenter 的分词
/// 结果在个别词上可不同、索引按字素计而非 UTF-16，见报告。
private enum TiltSentenceSplitter {

    static func splitIntoSentences(text: String, targetCount: Int, seed: Double) -> [String] {
        if targetCount <= 1 { return [text] }
        var sentences = [text]
        for level in 1...5 {
            if sentences.count >= targetCount { break }
            sentences = sentences.flatMap { splitByLevel($0, level) }
        }
        var result = sentences
        if result.count < targetCount {
            result = secondarySplit(result, targetCount: targetCount, seed: seed)
        }
        if result.count > targetCount {
            result = mergeSentences(result, targetCount: targetCount)
        }
        return result
    }

    private static func splitByLevel(_ text: String, _ level: Int) -> [String] {
        switch level {
        case 1: return splitByPunctuation(text)
        case 2: return splitByBracketsQuotes(text)
        case 3: return splitByWesternWords(text)
        case 4: return splitCJKBySpace(text)
        case 5: return splitBySpecialChars(text)
        default: return [text]
        }
    }

    // 一级：标点（标点串 + 其后空格归前段；标点串前无正文
    // 时并入上一段——网页 splitByPunctuation 的 beforePunct
    // 为空分支，(57) C2 对齐：如 "a。，b" 切为 ["a，。", "b"]
    // 而非 ["a，", "。", "b"]）。
    private static func splitByPunctuation(_ text: String) -> [String] {
        let punct: Set<Character> = ["，", "。", "；", "！", "？", "、", "…", "·",
                                     ".", ",", ";", "!", "?"]
        let chars = Array(text)
        var result: [String] = []
        var lastIndex = 0
        var i = 0
        var sawMatch = false
        while i < chars.count {
            guard punct.contains(chars[i]) else { i += 1; continue }
            sawMatch = true
            var clusterEnd = i
            while clusterEnd < chars.count && punct.contains(chars[clusterEnd]) {
                clusterEnd += 1
            }
            var trailingEnd = clusterEnd
            while trailingEnd < chars.count && chars[trailingEnd].isWhitespace {
                trailingEnd += 1
            }
            let before = String(chars[lastIndex..<i])
            let cluster = String(chars[i..<trailingEnd])
            if !before.isEmpty {
                result.append(before + cluster)
            } else if !result.isEmpty {
                result[result.count - 1] += cluster
            } else {
                result.append(cluster)
            }
            lastIndex = trailingEnd
            i = trailingEnd
        }
        guard sawMatch else { return [text] }
        if lastIndex < chars.count {
            result.append(String(chars[lastIndex...]))
        }
        let filtered = result.filter { !$0.isEmpty }
        return filtered.isEmpty ? [text] : filtered
    }

    // 二级：括号/引号最外层配对（递归切 before/配对段/rest）。
    private static func splitByBracketsQuotes(_ text: String) -> [String] {
        let pairs: [(String, String)] = [
            ("「", "」"), ("『", "』"), ("《", "》"), ("【", "】"),
            ("｛", "｝"), ("［", "］"), ("[", "]"), ("（", "）"),
            ("(", ")"), ("\"", "\""), ("'", "'")
        ]
        let chars = Array(text).map { String($0) }
        var best: (open: Int, close: Int)? = nil
        for (openStr, closeStr) in pairs {
            guard let openIdx = chars.firstIndex(of: openStr) else { continue }
            var closeIdx: Int? = nil
            if openIdx + 1 < chars.count {
                for j in (openIdx + 1)..<chars.count where chars[j] == closeStr {
                    closeIdx = j
                    break
                }
            }
            guard let close = closeIdx else { continue }
            if best == nil || openIdx < best!.open
                || (openIdx == best!.open && close > best!.close) {
                best = (openIdx, close)
            }
        }
        guard let found = best else { return [text] }
        var result: [String] = []
        let before = chars[0..<found.open].joined()
        let paired = chars[found.open...found.close].joined()
        let rest = found.close + 1 < chars.count
            ? chars[(found.close + 1)...].joined() : ""
        if !before.isEmpty { result.append(contentsOf: splitByBracketsQuotes(before)) }
        result.append(paired)
        if !rest.isEmpty { result.append(contentsOf: splitByBracketsQuotes(rest)) }
        return result.count > 1 ? result : [text]
    }

    // 三级：含 CJK 时把多词西文块切成独立段。
    private static func splitByWesternWords(_ text: String) -> [String] {
        guard hasCJK(text) else { return [text] }
        let pattern = "[a-zA-Z0-9]+(?:[a-zA-Z0-9'\\-]*[a-zA-Z0-9]+)?"
            + "(?:\\s+[a-zA-Z0-9]+(?:[a-zA-Z0-9'\\-]*[a-zA-Z0-9]+)?)+"
            + "[.,;:!?。，；：！？]?\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let nsText = text as NSString
        let matches = regex.matches(
            in: text, range: NSRange(location: 0, length: nsText.length))
        var hasMultiWordBlock = false
        for match in matches {
            let block = nsText.substring(with: match.range)
            let words = block.split(whereSeparator: { $0.isWhitespace }).count
            if words > 1 { hasMultiWordBlock = true; break }
        }
        guard hasMultiWordBlock, !matches.isEmpty else { return [text] }
        var parts: [String] = []
        var lastIndex = 0
        for match in matches {
            let blockStart = match.range.location
            let blockEnd = blockStart + match.range.length
            let before = nsText.substring(
                with: NSRange(location: lastIndex, length: blockStart - lastIndex))
            let block = nsText.substring(with: match.range)
            if shouldSkipBoundary(fullText: text, beforeBlock: before) {
                parts.append(before + block)
            } else if blockStart > lastIndex {
                parts.append(before)
                parts.append(block)
            } else {
                parts.append(block)
            }
            lastIndex = blockEnd
        }
        if lastIndex < nsText.length {
            parts.append(nsText.substring(from: lastIndex))
        }
        let filtered = parts.filter { !$0.isEmpty }
        return filtered.count > 1 ? filtered : [text]
    }

    private static func shouldSkipBoundary(fullText: String, beforeBlock: String) -> Bool {
        guard let last = beforeBlock.last else { return false }
        if last == "-" { return true }
        if last == ":" || last == "：" || last == "/" || last == "／"
            || last == "|" || last == "｜" {
            return fullText.filter { $0 == last }.count >= 2
        }
        return false
    }

    // 四级：CJK 块内空格切分（全角空格恒切；半角空格在
    // CJK 字后切；其余空格跟随当前块）。
    private static func splitCJKBySpace(_ text: String) -> [String] {
        guard hasCJK(text) else { return [text] }
        var segments: [String] = []
        var current = ""
        var inCjkBlock = false
        for ch in text {
            if isCJK(ch) {
                current.append(ch)
                inCjkBlock = true
            } else if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if ch.isWhitespace {
                if ch == "　" && !current.isEmpty {
                    current.append(ch)
                    segments.append(current)
                    current = ""
                    inCjkBlock = false
                } else if inCjkBlock && !current.isEmpty,
                    let last = current.last, isCJK(last) {
                    current.append(ch)
                    segments.append(current)
                    current = ""
                    inCjkBlock = false
                } else if current.isEmpty && !segments.isEmpty {
                    segments[segments.count - 1].append(ch)
                } else {
                    current.append(ch)
                }
            } else {
                if current.isEmpty && !segments.isEmpty {
                    segments[segments.count - 1].append(ch)
                } else {
                    current.append(ch)
                }
            }
        }
        if !current.isEmpty {
            if !segments.isEmpty && current.allSatisfy({ $0.isWhitespace }) {
                segments[segments.count - 1] += current
            } else {
                segments.append(current)
            }
        }
        return segments.count > 1 ? segments : [text]
    }

    // 五级：特殊符（分隔符串归前段）。
    private static func splitBySpecialChars(_ text: String) -> [String] {
        let separators: Set<Character> = ["：", ":", "/", "／", "\\", "|", "｜", "~", "～"]
        let chars = Array(text)
        var result: [String] = []
        var current = ""
        var i = 0
        var sawSeparator = false
        while i < chars.count {
            if separators.contains(chars[i]) {
                sawSeparator = true
                while i < chars.count && separators.contains(chars[i]) {
                    current.append(chars[i]); i += 1
                }
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(chars[i]); i += 1
            }
        }
        if !current.isEmpty { result.append(current) }
        guard sawSeparator, result.count > 1 else { return [text] }
        return result
    }

    // 补切（网页 secondarySplit 逐项移植，(57) C2）：候选段
    //（字素 >2）逐段取词起点（NLTokenizer .word 的词类
    // token 起点，承接 Intl.Segmenter isWordLike 位置），
    // 在最接近中点的词间隙切开，score = balance×10 + 词数，
    // 全候选取最高分一段切一刀、循环至目标段数；任一段都
    // 凑不出 ≥2 个词时走网页兜底：seed = 全段 UTF-16 码元
    // 值总和 + 段数 + timeSeed，fract(sin(seed)×10000) 选段、
    // 中点切开。
    private static func secondarySplit(_ input: [String], targetCount: Int,
                                       seed: Double) -> [String] {
        var sentences = input
        while sentences.count < targetCount {
            let candidates = sentences.indices.filter {
                sentences[$0].count > 2
            }
            if candidates.isEmpty { break }

            var best: (index: Int, splitPos: Int, score: Double)? = nil
            for index in candidates {
                let sentence = sentences[index]
                let wordStarts = wordLikeStarts(in: sentence)
                guard wordStarts.count >= 2 else { continue }
                let mid = Double(sentence.count) / 2
                var bestGap = 1
                var bestDist = Double.greatestFiniteMagnitude
                for gap in 1..<wordStarts.count {
                    let dist = abs(Double(wordStarts[gap]) - mid)
                    if dist < bestDist { bestDist = dist; bestGap = gap }
                }
                let splitPos = wordStarts[bestGap]
                guard splitPos > 0 && splitPos < sentence.count else { continue }
                let balance = 1 - abs(Double(splitPos) - mid) / mid
                let score = balance * 10 + Double(wordStarts.count)
                if best == nil || score > best!.score {
                    best = (index, splitPos, score)
                }
            }
            if let chosen = best {
                let chars = Array(sentences[chosen.index])
                let first = String(chars[0..<chosen.splitPos])
                let second = String(chars[chosen.splitPos...])
                sentences.replaceSubrange(
                    chosen.index...chosen.index, with: [first, second])
                continue
            }

            // 网页兜底（无 Segmenter 词边界时）：种子伪随机
            // 选一段候选、在中点切开。textHash 按 UTF-16 码
            // 元值求和（JS charCodeAt 口径）。
            var textHash: Double = 0
            for sentence in sentences {
                for unit in sentence.utf16 { textHash += Double(unit) }
            }
            let hashSeed = textHash + Double(sentences.count) + seed
            let roll = stageSeededRandom(hashSeed)
            let pick = min(Int(roll * Double(candidates.count)),
                           candidates.count - 1)
            let index = candidates[pick]
            let chars = Array(sentences[index])
            let mid = chars.count / 2
            guard mid > 0 && mid < chars.count else { break }
            let first = String(chars[0..<mid])
            let second = String(chars[mid...])
            sentences.replaceSubrange(index...index, with: [first, second])
        }
        return sentences
    }

    /// 词类 token 的字素起点集（NLTokenizer .word；含字母/
    /// 数字标量的 token 记为词类，承接 Intl.Segmenter 的
    /// isWordLike）。返回升序字素下标（含 0）。
    private static func wordLikeStarts(in text: String) -> [Int] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var starts: [Int] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) {
            range, _ in
            let token = text[range]
            let isWordLike = token.unicodeScalars.contains {
                CharacterSet.alphanumerics.contains($0)
            }
            if isWordLike {
                starts.append(text[..<range.lowerBound].count)
            }
            return true
        }
        return starts
    }

    // 并段：反复合并相邻最短对直到目标段数。
    private static func mergeSentences(_ input: [String], targetCount: Int) -> [String] {
        var sentences = input
        while sentences.count > targetCount {
            var bestIndex = 0
            var shortest = Int.max
            for i in 0..<(sentences.count - 1) {
                let combined = sentences[i].count + sentences[i + 1].count
                if combined < shortest {
                    shortest = combined
                    bestIndex = i
                }
            }
            let merged = sentences[bestIndex] + sentences[bestIndex + 1]
            sentences.replaceSubrange(bestIndex...(bestIndex + 1), with: [merged])
        }
        return sentences
    }

    private static func hasCJK(_ text: String) -> Bool {
        text.contains { isCJK($0) }
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FA5).contains(v) || (0x3040...0x30FF).contains(v)
            || (0xAC00...0xD7AF).contains(v)
    }

}
