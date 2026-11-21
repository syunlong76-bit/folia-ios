import UIKit
import QuartzCore

// 回环 claddagh（M2' 照搬对齐版）：按 folia-major 网页版 claddagh
// 的展示行为逐项实现。依据文件：
//  - claddagh/VisualizerCladdagh.tsx（半径/轴线/行偏移弹簧/渲染窗）
//  - claddagh/CladdaghRingLine.tsx（逐字素椭圆投影/聚焦/辉光，约 683 行）
//  - claddagh/claddaghLayout.ts（弧长间距测量/最大弧跨/可读角度归一）
//  - claddagh/claddaghTimeline.ts（零时长字素借时/小数下标/整行偏移角）
//  - claddagh/claddaghGlow.ts（drop-shadow 拟合系数 0.5 / 副歌 0.4）
//  - types.ts DEFAULT_CLADDAGH_TUNING（focus 0.65 / radius 1.0 /
//    ellipseTilt 45° / showAxisLine true / letterSpacingOffset 0 /
//    position 0,0 / showTranslation false）——(57) C2 起全量经
//    CladdaghTuningStore（CladdaghTuning.swift）可调：focus/
//    radius/tilt/字距/轴线开关/圆环位置均已接线（含 focus 驱动
//    的 focusSpacingScale 间距标尺与 position 的环+轴线同移）；
//    译文一组只存不用（协议无译文字段，见下）。
// 对齐要点：
//  - 画面是倾斜椭圆环：歌词逐字素沿弧长定位（nominalAngle），整环
//    随行号以 π 为步进自转（lineOffset 弹簧 stiffness 55 / damping
//    14 / mass 0.9，跳变 >1 行直接落位），当前字素被 wordOffset
//    带到焦点（psi = 0）处；深度 D、聚焦 F 决定缩放/透明/辉光。
//  - 渲染窗与网页一致：renderBaseIndex−1 … +2 共至多 4 行常驻，
//    行切换时 renderBase 立即跟随新中心行（网页注释明示此举消除
//    wordOffset 跳变），旧行靠 lineDiff 连续淡出而非整行出场动画。
//  - 字号恒 72pt × dynamicTypeScale（网页 72px × lyricsFontScale，
//    无 vmin clamp，与 classic/partita 不同）；字重 700 宋体。
//  - 协议缺失项（未落，见回报档案）：逐字 wordColors（charColor）、
//    isChorus（副歌三层辉光与交错 stagger；LyricLine 无 isChorus
//    字段）、译文环（showTranslation 参数已存、协议无译文字段）、
//    音频功率（宿主无频谱下发，power 恒 0：半径不脉动、
//    轴线静止、动画强度 normal 档系数只在公式里保留）。
//    renderHints.renderEnd 已于 (57) C2 按 renderHints.ts
//    公式现算（纯函数、无数据缺口），不再以行 end 代。
//  - 逐字素 blur（网页 filter: blur(8·(1−D)·(1−0.5F))px）未落：
//    UILabel 无低成本逐字模糊，深度感已由同一 D/F 驱动的透明度
//    公式承载，与 classic 行进出场 blur 分量未做的口径一致。
// 时钟纪律不变：只消费宿主 frameTick 的锚点位置，lineOffset 弹簧
// 在 frameTick 内以墙钟差分积分（读 CACurrentMediaTime 仅为求帧
// 间隔，不自建任何 CADisplayLink/Timer 时钟源）；inactive /
// destroyed 时 frameTick 守门停摆，unmount 释放全部视图与缓存。

/// 字素时序（claddaghTimeline 的 GraphemeTiming 等价物）。
private struct CladdaghGrapheme {
    var char: String
    var start: TimeInterval
    var end: TimeInterval
}

/// 间距信息（claddaghLayout.buildMeasuredSpacingInfo 的输出）。
private struct CladdaghSpacingItem {
    var char: String
    var start: TimeInterval
    var end: TimeInterval
    var nominalAngle: Double
    var scaleFactor: Double
}

/// 一个字素标签：缓存上次写入值，逐帧只写变化项（网页
/// writeGlyph 以字符串比对跳过重复写入口径的原生等价）。
private final class CladdaghGlyphLabel: UILabel {
    var appliedCenter = CGPoint(x: -10000, y: -10000)
    var appliedScale: CGFloat = -1
    var appliedRotation: CGFloat = 0
    var appliedAlpha: CGFloat = -1
    var appliedColor: UIColor?
    var appliedShadowRadius: CGFloat = -1
    var appliedShadowOpacity: Float = -1
}

/// 一行在环上的视图：整屏容器 + 逐字素标签（中心锚在环心）。
private final class CladdaghRingLineView: UIView {
    let lineIndex: Int
    let spacing: [CladdaghSpacingItem]
    let glyphs: [CladdaghGlyphLabel]

    init(lineIndex: Int, spacing: [CladdaghSpacingItem],
         glyphs: [CladdaghGlyphLabel]) {
        self.lineIndex = lineIndex
        self.spacing = spacing
        self.glyphs = glyphs
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        for glyph in glyphs { addSubview(glyph) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class CladdaghStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    // MARK: 调参与网页常量（DEFAULT_CLADDAGH_TUNING 与各源文件）

    /// 调参当前值（CladdaghTuningStore 0.25s 缓存，(57) C2
    /// 接线；缺省 = DEFAULT_CLADDAGH_TUNING 逐字对齐）。
    private var tuning: CladdaghTuningValues {
        CladdaghTuningStore.valuesCached(now: CACurrentMediaTime())
    }
    /// focusScaleRatio（types.ts，缺省 0.65）。
    private var focusScaleRatio: Double { tuning.focusScaleRatio }
    /// radiusScale（缺省 1.0）。
    private var radiusScale: Double { tuning.radiusScale }
    /// ellipseTiltDeg（缺省 45）；投影旋转角 = −ellipseTiltDeg。
    private var ellipseTiltDeg: Double { tuning.ellipseTiltDeg }
    /// letterSpacingOffset（缺省 0，px/字间隙）。
    private var letterSpacingOffsetPx: Double { tuning.letterSpacingOffset }
    /// 已落地的调参指纹：任一参数变化即失效间距缓存并
    /// 重建渲染窗（网页 tuning 变化重算 spacing 同义）。
    private var appliedTuning: CladdaghTuningValues? = nil
    /// CLADDAGH_LETTER_SPACING_EM（claddaghLayout.ts）。
    private let letterSpacingEm: Double = 0.04
    /// CLADDAGH_BASE_TRACKING_EM（claddaghLayout.ts，私有常量）。
    private let baseTrackingEm: Double = 0.18
    /// CLADDAGH_MAX_ARC_SPAN（claddaghLayout.ts，私有常量）。
    private let maxArcSpan: Double = 4.25
    /// CLADDAGH_BACK_FOLLOW_RATIO（claddaghLayout.ts）。
    private let backFollowRatio: Double = 0.28
    /// CLADDAGH_BACK_ORBIT_FOLLOW_RATIO（claddaghLayout.ts）。
    private let backOrbitFollowRatio: Double = 0.52
    /// CLADDAGH_NEXT_LINE_ENTRY_LEAD_SECONDS（claddaghLayout.ts）。
    private let nextLineEntryLead: Double = 0.34
    /// CLADDAGH_GLOW_DROP_SHADOW_SCALE（claddaghGlow.ts）：原生
    /// CALayer 阴影半径按此系数由网页 text-shadow 半径折算。
    private let glowDropShadowScale: Double = 0.5
    /// 渲染窗字素预算上限：至多 4 行（网页窗）且总字素 ≤ 400，
    /// 超出时按距中心远近舍远行（内存纪律，网页无此上限）。
    private let glyphBudget = 400
    /// 间距布局缓存上限（网页 spacing 缓存 240 条；原生只缓存
    /// 渲染窗附近行，12 条足够且更省）。
    private let layoutCacheLimit = 12

    private let rootView = LyricStageRootView()
    private let contentView = UIView()
    private let axisView = UIView()
    private let axisGradient = CAGradientLayer()
    private let ringContainer = UIView()
    private var lineViews: [CladdaghRingLineView] = []
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false
    private var didPlayEntry = false

    private var builtTrackId: String?
    private var builtLineCount = -1
    private var builtRadius: CGFloat = 0
    private var layoutCache: [String: [CladdaghSpacingItem]] = [:]
    private var layoutCacheOrder: [String] = []

    /// 中心行（网页 centerLineIndex）：最后一个 start ≤ position
    /// 的行，无则 −1（空档期保持最近完成行，与 runtime 的
    /// recentCompletedLine 回退同结果）。
    private var centerIndex = -1
    private var renderBaseIndex = -1
    /// 整环自转角（网页 lineOffset MotionValue，目标 = 中心行 × π）。
    private var lineOffsetValue: Double = 0
    private var lineOffsetVelocity: Double = 0
    private var lineOffsetTarget: Double = 0
    private var hasOffsetBase = false
    private var lastTickWallTime: TimeInterval?
    private var previousPosition: TimeInterval = 0
    private var holdResetFrame = false
    private var windowDirty = true

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        contentView.isUserInteractionEnabled = false
        ringContainer.isUserInteractionEnabled = false
        // 中心轴线（VisualizerCladdagh）：300×4，渐变两端 20%/80%
        // 淡出，旋转角 = 90 − ellipseTiltDeg = 45°。颜色在
        // applySnapshot 按调色板刷新（power 恒 0 时混合比为 0，
        // 即 primary、alpha 0.2，见 updateAxisLine）。
        axisGradient.startPoint = CGPoint(x: 0, y: 0.5)
        axisGradient.endPoint = CGPoint(x: 1, y: 0.5)
        axisGradient.locations = [0, 0.2, 0.8, 1]
        axisView.layer.addSublayer(axisGradient)
        axisView.isUserInteractionEnabled = false
        contentView.addSubview(axisView)
        contentView.addSubview(ringContainer)
        rootView.addSubview(contentView)
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    /// 调参指纹同步：变化时清间距缓存、重建窗口并触发布局
    ///（位置/轴线/半径都随之变）。applySnapshot 与 frameTick
    /// 各调一次（0.25s 缓存下开销可忽略）。
    private func syncTuning() {
        let current = tuning
        guard appliedTuning != current else { return }
        appliedTuning = current
        layoutCache.removeAll()
        layoutCacheOrder.removeAll()
        clearWindow()
        windowDirty = true
        updateAxisLine()
        rootView.setNeedsLayout()
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        // (61) WC：入口统一过对比钳制——下游 palette.* 全走保护副本。
        var snapshot = snapshot
        snapshot.palette = snapshot.palette.contrastProtected()
        self.snapshot = snapshot
        syncTuning()
        if snapshot.track?.id != builtTrackId
            || snapshot.lines.count != builtLineCount {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            layoutCache.removeAll()
            layoutCacheOrder.removeAll()
            centerIndex = -1
            renderBaseIndex = -1
            hasOffsetBase = false
            lineOffsetVelocity = 0
            clearWindow()
        }
        updateAxisLine()
        windowDirty = true
        playEntryIfNeeded()
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if !isActive {
            // 停摆：弹簧速度清零，frameTick 守门后不再推进；
            // 恢复时以当前锚点位置重新落位（snap 路径）。
            lineOffsetVelocity = 0
            lastTickWallTime = nil
        }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        syncTuning()
        let lines = snapshot.lines
        if lines.isEmpty {
            if !lineViews.isEmpty { clearWindow() }
            previousPosition = position
            return
        }
        // 回退保持帧（claddaghTimeline.shouldHoldCladdaghFrame-
        // ForPlaybackReset）：时间大幅回退到 0.5s 内且已有中心行
        // 时保留上一帧画面，不把旧行按零时刻重绘。
        if Self.shouldHoldReset(previous: previousPosition,
                                current: position,
                                centerLineIndex: centerIndex) {
            holdResetFrame = true
        }
        previousPosition = position
        if holdResetFrame && centerIndex > 0 { return }
        holdResetFrame = false

        let rawCenter = LyricParser.currentIndex(in: lines, at: position) ?? -1
        if rawCenter != centerIndex || windowDirty {
            let previous = centerIndex
            centerIndex = rawCenter
            renderBaseIndex = rawCenter
            lineOffsetTarget = Double(rawCenter) * Double.pi
            if !hasOffsetBase || abs(rawCenter - previous) > 1 {
                // 网页：|curr − prev| > 1 直接 set 新角，不走弹簧。
                lineOffsetValue = lineOffsetTarget
                lineOffsetVelocity = 0
                hasOffsetBase = true
            }
            rebuildWindowIfNeeded()
            windowDirty = false
        }
        integrateSpring()
        updateGlyphs(position: position)
    }

    func unmount() {
        isActive = false
        contentView.layer.removeAllAnimations()
        clearWindow()
        layoutCache.removeAll()
        layoutCacheOrder.removeAll()
        context = nil
        snapshot = nil
    }

    // MARK: 整环自转弹簧（framer-motion spring 55/14/0.9）

    /// 半隐式欧拉积分：a = −(k/m)(x − target) − (c/m)v。
    /// dt 取相邻 frameTick 的墙钟差（钳 0…50ms，首帧 1/60），
    /// 与网页按真实帧间隔推进弹簧同口径。
    private func integrateSpring() {
        let now = CACurrentMediaTime()
        let dt: TimeInterval
        if let last = lastTickWallTime {
            dt = min(max(now - last, 0), 0.05)
        } else {
            dt = 1.0 / 60.0
        }
        lastTickWallTime = now
        guard dt > 0 else { return }
        let stiffness = 55.0 / 0.9
        let damping = 14.0 / 0.9
        let acceleration = -stiffness * (lineOffsetValue - lineOffsetTarget)
            - damping * lineOffsetVelocity
        lineOffsetVelocity += acceleration * dt
        lineOffsetValue += lineOffsetVelocity * dt
        if abs(lineOffsetValue - lineOffsetTarget) < 0.0005
            && abs(lineOffsetVelocity) < 0.0005 {
            lineOffsetValue = lineOffsetTarget
            lineOffsetVelocity = 0
        }
    }

    private static func shouldHoldReset(previous: TimeInterval,
                                        current: TimeInterval,
                                        centerLineIndex: Int) -> Bool {
        centerLineIndex > 0 && current <= 0.5 && current < previous - 0.5
    }

    // MARK: 入场（VisualizerCladdagh 壳层 motion.div）

    /// opacity 0→1、scale 0.96→1、0.8s、ease [0.16, 1, 0.3, 1]
    /// （原生以 CAMediaTimingFunction 控制点同值落）；网页的
    /// blur(4px) 分量未落（同 classic 口径）。
    private func playEntryIfNeeded() {
        guard !didPlayEntry else { return }
        didPlayEntry = true
        // UIView.animate 无 cubic-bezier 控制点入口，故以
        // CABasicAnimation 驱动 opacity / transform.scale，
        // 模型值直接落终态，表现层按控制点曲线补间。
        contentView.layer.removeAllAnimations()
        let timing = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.96
        scaleAnim.toValue = 1.0
        scaleAnim.duration = 0.8
        scaleAnim.timingFunction = timing
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 0.0
        fadeAnim.toValue = 1.0
        fadeAnim.duration = 0.8
        fadeAnim.timingFunction = timing
        contentView.layer.add(scaleAnim, forKey: "claddagh.entry.scale")
        contentView.layer.add(fadeAnim, forKey: "claddagh.entry.opacity")
        contentView.alpha = 1
        contentView.transform = .identity
    }

    // MARK: 中心轴线

    /// power 恒 0（无频谱下发）：colorRatio = clamp((0 − 0.02) /
    /// 0.58) = 0 → mixed = primary、alpha = 0.2 + 0.75×0 = 0.2；
    /// scaleX/scaleY = 1；副歌辉光不触发（isChorus 无数据源）。
    private func updateAxisLine() {
        guard let snapshot else { return }
        // showAxisLine 经调参可关（缺省 true，(57) C2 接线）。
        axisView.isHidden = !tuning.showAxisLine
        let mixed = snapshot.palette.primary.withAlphaComponent(0.2)
        axisGradient.colors = [
            UIColor.clear.cgColor,
            mixed.cgColor,
            mixed.cgColor,
            UIColor.clear.cgColor,
        ]
    }

    // MARK: 渲染窗（renderBaseIndex−1 … +2，至多 4 行）

    private func clearWindow() {
        for lineView in lineViews { lineView.removeFromSuperview() }
        lineViews = []
    }

    private func rebuildWindowIfNeeded() {
        guard let snapshot else { return }
        let lines = snapshot.lines
        var wanted: [Int] = []
        for idx in (renderBaseIndex - 1)...(renderBaseIndex + 2)
        where lines.indices.contains(idx) {
            wanted.append(idx)
        }
        let existing = Set(lineViews.map { $0.lineIndex })
        if existing == Set(wanted) && !windowDirty { return }
        // 字素预算：按距中心优先级（中心、+1、−1、+2）保留。
        let priority = [renderBaseIndex, renderBaseIndex + 1,
                        renderBaseIndex - 1, renderBaseIndex + 2]
        var budget = glyphBudget
        var kept = Set<Int>()
        for idx in priority where wanted.contains(idx) {
            let count = spacingInfo(for: lines[idx]).count
            if count <= budget || kept.isEmpty {
                kept.insert(idx)
                budget -= count
            }
        }
        clearWindow()
        for idx in wanted where kept.contains(idx) {
            let spacing = spacingInfo(for: lines[idx])
            let lineView = buildRingLineView(lineIndex: idx, spacing: spacing)
            lineView.frame = ringContainer.bounds
            ringContainer.addSubview(lineView)
            lineViews.append(lineView)
        }
    }

    private func buildRingLineView(lineIndex: Int,
                                    spacing: [CladdaghSpacingItem])
        -> CladdaghRingLineView {
        guard let snapshot else {
            return CladdaghRingLineView(lineIndex: lineIndex,
                                        spacing: spacing, glyphs: [])
        }
        let font = StageFonts.bold(size: fontSize())
        let baseColor = snapshot.palette.primary.withAlphaComponent(0.55)
        var glyphs: [CladdaghGlyphLabel] = []
        for item in spacing {
            let label = CladdaghGlyphLabel()
            label.text = item.char
            label.font = font
            label.textColor = baseColor
            label.textAlignment = .center
            label.alpha = 0
            label.isUserInteractionEnabled = false
            label.layer.shadowOffset = .zero
            label.sizeToFit()
            if label.bounds.width < 1 {
                // 空格等零宽字素：按网页 fallback 宽 0.36em 占位。
                label.frame.size.width = fontSize() * 0.36
                label.frame.size.height = fontSize()
            }
            glyphs.append(label)
        }
        return CladdaghRingLineView(lineIndex: lineIndex,
                                    spacing: spacing, glyphs: glyphs)
    }

    // MARK: 几何与字号

    /// 字号：72 × lyricsFontScale；原生落点 dynamicTypeScale。
    private func fontSize() -> CGFloat {
        72 * (snapshot?.viewport.dynamicTypeScale ?? 1)
    }

    /// Rx = min(容器宽 × 0.44, 560) × radiusScale；宽为 0 时
    /// 网页回退 360。Ry = Rx × 0.707（45° 投影比），网页中 Ry
    /// 只作存在性门与调试量，逐字投影实际用 R_minor = Rx×0.09。
    private func currentRadius() -> CGFloat {
        let width = rootView.bounds.width > 0
            ? rootView.bounds.width
            : (snapshot?.viewport.size.width ?? 0)
        let base: CGFloat = width > 0 ? min(width * 0.44, 560) : 360
        return base * CGFloat(radiusScale)
    }

    // MARK: 字素时序（graphemeTiming + claddaghTimeline）

    /// 整行字素时序：有逐字戳时按词均分到字素（网页
    /// buildWordGraphemeTimings 无音节数据时的 even 口径），
    /// 词间空隙字素先记零时长，再由 adjustTimeline 借时均分；
    /// 无逐字戳时整行字素均分（buildEvenGraphemeTimings）。
    private func graphemeTimeline(for line: LyricLine) -> [CladdaghGrapheme] {
        let graphemes = line.text.map { String($0) }
        guard !graphemes.isEmpty else { return [] }
        guard let words = line.words, !words.isEmpty else {
            let span = max(line.end - line.start, 0)
            let unit = span / Double(graphemes.count)
            return graphemes.enumerated().map { (index, char) in
                CladdaghGrapheme(
                    char: char,
                    start: line.start + unit * Double(index),
                    end: index == graphemes.count - 1
                        ? line.end : line.start + unit * Double(index + 1))
            }
        }
        let units = StageLyricUnits.units(for: line)
        var timeline: [CladdaghGrapheme?] = Array(
            repeating: nil, count: graphemes.count)
        var cursor = 0
        var lastResolved = line.start
        for unit in units {
            let unitGraphemes = unit.text.map { String($0) }
            if unitGraphemes.isEmpty { continue }
            let matched = Self.findSequence(graphemes, unitGraphemes,
                                            from: cursor)
            let start = matched >= 0 ? matched : cursor
            let end = min(start + unitGraphemes.count, graphemes.count)
            for gap in cursor..<start {
                timeline[gap] = CladdaghGrapheme(
                    char: graphemes[gap], start: unit.start, end: unit.start)
            }
            let count = max(end - start, 1)
            let unitSpan = max(unit.end - unit.start, 0)
            for local in 0..<(end - start) {
                let itemStart = unit.start + unitSpan * Double(local) / Double(count)
                let itemEnd = local == count - 1
                    ? unit.end
                    : unit.start + unitSpan * Double(local + 1) / Double(count)
                timeline[start + local] = CladdaghGrapheme(
                    char: graphemes[start + local],
                    start: itemStart, end: itemEnd)
                lastResolved = max(lastResolved, itemEnd)
            }
            cursor = max(cursor, end)
        }
        var filled: [CladdaghGrapheme] = []
        for (index, char) in graphemes.enumerated() {
            filled.append(timeline[index] ?? CladdaghGrapheme(
                char: char, start: lastResolved, end: lastResolved))
        }
        return Self.adjustTimeline(filled, line: line)
    }

    private static func findSequence(_ source: [String], _ target: [String],
                                     from: Int) -> Int {
        if target.isEmpty { return from }
        guard source.count >= target.count else { return -1 }
        var index = from
        while index <= source.count - target.count {
            var matched = true
            for offset in target.indices where source[index + offset] != target[offset] {
                matched = false
                break
            }
            if matched { return index }
            index += 1
        }
        return -1
    }

    /// adjustCladdaghTimeline 逐行移植：连续零时长字素段按
    /// 每字 60ms 的最低需求向邻字借时（邻字保底 40ms），段内均分。
    private static func adjustTimeline(_ timeline: [CladdaghGrapheme],
                                       line: LyricLine) -> [CladdaghGrapheme] {
        if timeline.isEmpty { return timeline }
        var adjusted = timeline
        let n = adjusted.count
        var i = 0
        while i < n {
            if adjusted[i].start != adjusted[i].end {
                i += 1
                continue
            }
            var j = i
            while j < n && adjusted[j].start == adjusted[j].end { j += 1 }
            let gapCount = j - i
            var gapStart = i > 0 ? adjusted[i - 1].end : line.start
            var gapEnd = j < n ? adjusted[j].start : line.end
            let minNeeded = Double(gapCount) * 0.06
            var duration = gapEnd - gapStart
            if duration < minNeeded {
                let deficit = minNeeded - duration
                if i > 0 && j < n {
                    let half = deficit / 2
                    let prevDuration = adjusted[i - 1].end - adjusted[i - 1].start
                    let prevSteal = min(half, max(0, prevDuration - 0.04))
                    let nextDuration = adjusted[j].end - adjusted[j].start
                    let nextSteal = min(deficit - prevSteal,
                                        max(0, nextDuration - 0.04))
                    gapStart -= prevSteal
                    gapEnd += nextSteal
                    adjusted[i - 1].end = gapStart
                    adjusted[j].start = gapEnd
                } else if i > 0 {
                    let prevDuration = adjusted[i - 1].end - adjusted[i - 1].start
                    let prevSteal = min(deficit, max(0, prevDuration - 0.04))
                    gapStart -= prevSteal
                    adjusted[i - 1].end = gapStart
                } else if j < n {
                    let nextDuration = adjusted[j].end - adjusted[j].start
                    let nextSteal = min(deficit, max(0, nextDuration - 0.04))
                    gapEnd += nextSteal
                    adjusted[j].start = gapEnd
                }
                duration = gapEnd - gapStart
            }
            let gapUnit = duration > 0 ? duration / Double(gapCount) : 0
            for k in i..<j {
                let offset = k - i
                adjusted[k].start = gapStart + gapUnit * Double(offset)
                adjusted[k].end = gapStart + gapUnit * Double(offset + 1)
            }
            i = j
        }
        return adjusted
    }

    // MARK: 弧长间距（claddaghLayout.buildMeasuredSpacingInfo）

    /// 字素中心按实测前缀宽定位：offsets[count] = 前缀实测宽
    /// （含 0.04em 字距）+ (count−1) × 0.18em 基础 tracking
    /// + (count−1) × letterSpacingOffset；实测失效时回退宽
    /// （空白 0.36em / CJK 1em / 其余 0.62em）。总弧跨超
    /// 4.25 rad 时等比压缩 scaleFactor。
    private func spacingInfo(for line: LyricLine) -> [CladdaghSpacingItem] {
        let radius = currentRadius()
        let cacheKey = "\(line.id)|\(Int(radius.rounded()))|\(line.text.count)"
        if let cached = layoutCache[cacheKey] { return cached }
        let timeline = graphemeTimeline(for: line)
        let fontPx = Double(fontSize())
        let font = StageFonts.bold(size: fontSize())
        let graphemes = timeline.map { $0.char }
        var offsets: [Double] = [0]
        var fallbackCumulative: Double = 0
        for count in 1...max(graphemes.count, 1) where count <= graphemes.count {
            fallbackCumulative += Self.fallbackWidth(
                of: graphemes[count - 1], fontPx: fontPx)
            let prefix = graphemes[0..<count].joined()
            let measured = NSAttributedString(
                string: prefix,
                attributes: [.font: font, .kern: fontPx * letterSpacingEm]
            ).size().width
            let baseWidth = measured > 0 ? Double(measured) : fallbackCumulative
            let tracking = Double(max(0, count - 1)) * fontPx * baseTrackingEm
            let extra = Double(max(0, count - 1)) * letterSpacingOffsetPx
            offsets.append(max(offsets[count - 1],
                               baseWidth + tracking + extra))
        }
        // focusSpacingScale = (1 + focus) / (1 + DEFAULT.focus)
        //（VisualizerCladdagh：缺省 focus 0.65 时为 1；调参
        // 改 focus 后按此公式缩放全部行的间距，(57) C2 接线）。
        let spacingScale = (1 + focusScaleRatio) / (1 + 0.65)
        let totalWidth = (offsets.last ?? 0) * spacingScale
        let safeRadius = max(Double(radius), fontPx * 2, 1)
        let totalSpan = totalWidth / safeRadius
        let scaleFactor = totalSpan > maxArcSpan ? maxArcSpan / totalSpan : 1.0
        let items: [CladdaghSpacingItem] = timeline.enumerated().map { (index, item) in
            let centerPx = ((offsets[index] + offsets[index + 1]) / 2) * spacingScale
            let startAngle = centerPx / safeRadius
            return CladdaghSpacingItem(
                char: item.char, start: item.start, end: item.end,
                nominalAngle: (startAngle - totalSpan / 2) * scaleFactor,
                scaleFactor: scaleFactor)
        }
        layoutCache[cacheKey] = items
        layoutCacheOrder.append(cacheKey)
        if layoutCacheOrder.count > layoutCacheLimit {
            let evict = layoutCacheOrder.removeFirst()
            layoutCache.removeValue(forKey: evict)
        }
        return items
    }

    private static func fallbackWidth(of char: String, fontPx: Double) -> Double {
        if char.allSatisfy({ $0.isWhitespace }) { return fontPx * 0.36 }
        if isCJK(char) { return fontPx }
        return fontPx * 0.62
    }

    private static func isCJK(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FA5).contains(v) || (0x3040...0x30FF).contains(v)
            || (0xAC00...0xD7AF).contains(v)
    }

    /// 视觉长度（claddaghTimeline.getVisualLength）：网页按
    /// UTF-16 码元逐个计（CJK 码元记 1、其余 0.5，代理对
    /// 两码元合计 1.0）；原生自 (57) C2 起同按 utf16 码元
    /// 计，与网页逐项一致。
    private static func visualLength(of text: String) -> Double {
        var score = 0.0
        for unit in text.utf16 {
            score += isCJKCodeUnit(unit) ? 1.0 : 0.5
        }
        return score
    }

    private static func isCJKCodeUnit(_ value: UInt16) -> Bool {
        (0x4E00...0x9FA5).contains(value) || (0x3040...0x30FF).contains(value)
            || (0xAC00...0xD7AF).contains(value)
    }

    // MARK: 小数下标 / 整行偏移角 / 播放进度（claddaghTimeline）

    private static func clampD(_ value: Double, _ min: Double, _ max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    /// getFractionalActiveIndex 逐行移植（含末字外推：有
    /// renderEnd 时末字后最多 +2，无则按末字时长外推、上限 1.8）。
    private static func fractionalIndex(in items: [CladdaghSpacingItem],
                                        at t: TimeInterval,
                                        renderEnd: TimeInterval?) -> Double {
        if items.isEmpty { return 0 }
        if items.count == 1 {
            let item = items[0]
            let targetEnd = renderEnd ?? item.end
            let duration = max(0.2, targetEnd - item.start)
            if t <= item.start { return 0 }
            return (t - item.start) / duration
        }
        if t <= items[0].start { return 0 }
        let lastIdx = items.count - 1
        if t >= items[lastIdx].start {
            let lastItem = items[lastIdx]
            if let renderEnd, renderEnd > lastItem.start {
                let progress = clampD((t - lastItem.start)
                    / (renderEnd - lastItem.start), 0, 1)
                return Double(lastIdx) + progress * 2.0
            }
            let prevItem = items[lastIdx - 1]
            let itemDuration = lastItem.end - lastItem.start
            let gapDuration = lastItem.start - prevItem.start
            let stepDuration = itemDuration > 0 ? itemDuration
                : (gapDuration > 0 ? gapDuration : 0.5)
            let progress = (t - lastItem.start) / stepDuration
            return Double(lastIdx) + min(progress, 1.8)
        }
        for i in 0..<(items.count - 1) {
            let tStart = items[i].start
            let tEnd = items[i + 1].start
            if t >= tStart && t < tEnd {
                if tEnd == tStart { return Double(i) }
                return Double(i) + (t - tStart) / (tEnd - tStart)
            }
        }
        return Double(items.count - 1)
    }

    /// getLineWordOffset：小数下标在 nominalAngle 上插值，
    /// 越过末字后按末步长外推。
    private static func wordOffset(in items: [CladdaghSpacingItem],
                                   at t: TimeInterval,
                                   renderEnd: TimeInterval?) -> Double {
        if items.isEmpty { return 0 }
        let fraction = fractionalIndex(in: items, at: t, renderEnd: renderEnd)
        let lastIdx = items.count - 1
        if fraction <= Double(lastIdx) {
            let intPart = Int(floor(fraction))
            let fracPart = fraction - Double(intPart)
            let angleA = items[intPart].nominalAngle
            let angleB = items[min(intPart + 1, lastIdx)].nominalAngle
            return angleA + (angleB - angleA) * fracPart
        }
        let lastAngle = items[lastIdx].nominalAngle
        let prevAngle = items[max(0, lastIdx - 1)].nominalAngle
        return lastAngle + (lastAngle - prevAngle) * (fraction - Double(lastIdx))
    }

    /// getLinePlaybackProgress。
    private static func playbackProgress(in items: [CladdaghSpacingItem],
                                         at t: TimeInterval,
                                         renderEnd: TimeInterval?) -> Double {
        if items.isEmpty { return 0 }
        if items.count == 1 {
            let item = items[0]
            let targetEnd = renderEnd ?? item.end
            let duration = max(0.001, targetEnd - item.start)
            return clampD((t - item.start) / duration, 0, 1)
        }
        let fraction = fractionalIndex(in: items, at: t, renderEnd: renderEnd)
        return clampD(fraction / Double(max(1, items.count - 1)), 0, 1)
    }

    /// normalizeReadableAngle（claddaghLayout）：折进 [−90, 90]。
    private static func normalizeReadableAngle(_ degrees: Double) -> Double {
        var normalized = degrees
        while normalized > 90 { normalized -= 180 }
        while normalized < -90 { normalized += 180 }
        return normalized
    }

    // MARK: 逐帧投影（CladdaghRingLine.handler）

    /// buildLineRenderHints 的 renderEndTime（renderHints.ts
    /// 公式逐行移植，与 TiltStageRenderer.renderEnd 同式）：
    /// 协议无 renderHints 字段，但该值是 start/end/末词 end
    /// 的纯函数，网页无存档时同样现算，数据通路无缺口。
    private static func renderHintEnd(of line: LyricLine) -> TimeInterval {
        let rawDuration = max(line.end - line.start, 0)
        if rawDuration < 0.10 {
            return max(line.end, line.start + 0.067)
        }
        let lastWordEnd = line.words?.last?.end ?? line.end
        if rawDuration < 0.18 {
            let enter = min(0.06, max(0.045, rawDuration * 0.45))
            let exit = min(0.04, max(0.03, rawDuration * 0.22))
            let linePassStart = max(lastWordEnd, line.start) + 0.03
            let exitStart = max(line.start + enter + 0.01,
                                linePassStart, line.end - exit)
            return max(line.end, exitStart + exit)
        }
        let exit = min(0.32, max(0.18, max(rawDuration, 0.12) * 0.18))
        let linePassStart = max(lastWordEnd, line.start) + 0.06
        let exitStart = max(linePassStart, line.end - exit)
        return max(line.end, exitStart + exit)
    }

    private func renderEnd(for lineIndex: Int) -> TimeInterval? {
        guard let snapshot, snapshot.lines.indices.contains(lineIndex)
        else { return nil }
        let line = snapshot.lines[lineIndex]
        let next = lineIndex + 1 < snapshot.lines.count
            ? snapshot.lines[lineIndex + 1] : nil
        // 网页：max(renderHints.renderEnd, next.start − lead
        // 或 end + 10)；renderEnd 自 (57) C2 起按公式现算。
        return max(Self.renderHintEnd(of: line),
                   next != nil ? next!.start - nextLineEntryLead
                               : line.end + 10.0)
    }

    private func updateGlyphs(position: TimeInterval) {
        guard let snapshot, !lineViews.isEmpty else { return }
        let lines = snapshot.lines
        let radius = Double(currentRadius())
        guard radius > 0 else { return }
        let bounds = ringContainer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let centerX = Double(bounds.width) / 2
        let centerY = Double(bounds.height) / 2
        let palette = snapshot.palette
        let baseRGB = palette.primary
        let highlight = palette.accent

        // 焦点行（renderBase）的偏移与进度：供其余行的 back-follow。
        let activeSpacing: [CladdaghSpacingItem]
        if lines.indices.contains(renderBaseIndex) {
            activeSpacing = spacingInfo(for: lines[renderBaseIndex])
        } else {
            activeSpacing = []
        }
        let activeEnd = renderEnd(for: renderBaseIndex)
        let activeWordOffset = Self.wordOffset(
            in: activeSpacing, at: position, renderEnd: activeEnd)
        let activeProgress = Self.playbackProgress(
            in: activeSpacing, at: position, renderEnd: activeEnd)
        let backOrbitFollow = Double.pi * backOrbitFollowRatio
            * (1 - pow(1 - activeProgress, 1.35))

        let currentLength = lines.indices.contains(centerIndex)
            ? Self.visualLength(of: lines[centerIndex].text) : 0
        let thetaRot = -ellipseTiltDeg * Double.pi / 180
        let cosRot = cos(thetaRot)
        let sinRot = sin(thetaRot)
        // power 恒 0 → 半径缩放 = min(1 + 0 × 0.25, 1.25) = 1。
        let currentRx = radius
        let rMajor = currentRx
        let rMinor = currentRx * 0.09

        for lineView in lineViews {
            let lineIndex = lineView.lineIndex
            guard lines.indices.contains(lineIndex) else { continue }
            let line = lines[lineIndex]
            let ownEnd = renderEnd(for: lineIndex)
            let ownWordOffset = Self.wordOffset(
                in: lineView.spacing, at: position, renderEnd: ownEnd)
            let lineDiff = abs(lineOffsetValue - Double(lineIndex) * Double.pi)
                / Double.pi

            var wordOffset = ownWordOffset
            if lineIndex >= centerIndex {
                // 过去行保持 own offset（网页注释：防跳回 0）；
                // 中心/未来行叠加 back-follow，未来行系数恒 1，
                // 中心行随 lineDiff 连续淡出。
                let factor = lineIndex > centerIndex
                    ? 1.0 : Self.clampD(lineDiff, 0, 1)
                wordOffset += (activeWordOffset * backFollowRatio
                    + backOrbitFollow) * factor
            }

            // 长句重叠抑制（当前行视觉长度 > 10 时压未来行）。
            var lengthFade = 1.0
            var lengthScale = 1.0
            if lineIndex > centerIndex && currentLength > 10 {
                let targetLength = Self.visualLength(of: line.text)
                let fadeStrength = Self.clampD((currentLength - 10) / 8, 0, 1)
                let targetStrength = Self.clampD((targetLength - 5) / 5, 0.4, 1)
                let combined = fadeStrength * targetStrength
                let targetMinOpacity = 1.0 - combined
                let targetMinScale = 1.0 - combined * 0.25
                let transition = Self.clampD((lineDiff - 0.4) / 0.5, 0, 1)
                lengthFade = 1.0 - (1.0 - targetMinOpacity) * transition
                lengthScale = 1.0 - (1.0 - targetMinScale) * transition
            }

            let isUpcoming = lineIndex > centerIndex
            let entryProgress = isUpcoming
                ? Self.clampD((position - (line.start - nextLineEntryLead))
                    / nextLineEntryLead, 0, 1)
                : 0
            let activeLineFactor = max(0, 1 - lineDiff)
            let maxVisibleDist = currentRx * 0.48

            for (index, item) in lineView.spacing.enumerated() {
                let label = lineView.glyphs[index]
                let theta = Double(lineIndex) * Double.pi + item.nominalAngle
                let psi = theta - lineOffsetValue - wordOffset
                let deltaDist = psi * currentRx
                let thetaCurve = deltaDist / rMajor
                let localCos = cos(thetaCurve)
                let depth = (localCos + 1) / 2
                let spacingFactor = 0.35 + 0.65 * pow(depth, 1.2)
                let rawX = sin(thetaCurve) * rMajor * spacingFactor
                let rawY = localCos * rMinor
                let x = rawX * cosRot - rawY * sinRot
                let y = rawX * sinRot + rawY * cosRot

                let distRatio = min(1, abs(deltaDist) / maxVisibleDist)
                let focus = activeLineFactor * pow(1 - distRatio, 1.8)
                let distanceOpacity = 0.68 + 0.32 * pow(depth, 1.9)
                // (61) WC：非当前行基础不透明下限 0.35→0.45（权重相应 0.65→0.55）。
                var opacity = (0.45 + 0.55 * pow(depth, 1.5)
                    * (0.35 + 0.65 * focus)) * distanceOpacity
                opacity *= Self.clampD(2 - lineDiff, 0, 1)
                if lineIndex < centerIndex {
                    opacity *= max(0, 1 - lineDiff)
                }
                opacity *= lengthFade
                if isUpcoming {
                    opacity *= 0.18 + 0.82 * entryProgress
                }
                if lineDiff > 0.02 {
                    let progress = Self.clampD((lineDiff - 0.3) / 0.6, 0, 1)
                    let cosThreshold = 1.0 - 1.2 * progress
                    if localCos > cosThreshold {
                        opacity *= Self.clampD(
                            1.0 - (localCos - cosThreshold) / 0.15, 0, 1)
                    }
                }
                let finalOpacity = CGFloat(opacity)
                if finalOpacity < 0.001 {
                    if label.appliedAlpha != 0 {
                        label.alpha = 0
                        label.appliedAlpha = 0
                    }
                    continue
                }

                let scale = (0.22 + 0.98 * pow(depth, 1.5))
                    * (1.0 + focusScaleRatio * focus)
                    * lengthScale * item.scaleFactor
                let tangentX = cos(thetaCurve) * rMajor
                let tangentY = -sin(thetaCurve) * rMinor
                let rotatedTangentX = tangentX * cosRot - tangentY * sinRot
                let rotatedTangentY = tangentX * sinRot + tangentY * cosRot
                let tangentAngle = Self.normalizeReadableAngle(
                    atan2(rotatedTangentY, rotatedTangentX) * 180 / Double.pi)
                let tilt = Self.clampD(tangentAngle * (0.4 + 0.6 * depth),
                                       -38, 38)

                // 颜色与辉光（charProgress → 近瞬时变色 + flash pop）。
                var charProgress = 0.0
                if position >= item.end {
                    charProgress = 1
                } else if position > item.start {
                    let duration = item.end - item.start
                    charProgress = duration > 0
                        ? (position - item.start) / duration : 1
                }
                let baseGlow = 24 * pow(focus, 2.0)
                var targetRGB = baseRGB
                var currentAlpha: CGFloat = 0.55
                var flashPop = 0.0
                if charProgress >= 1 {
                    targetRGB = highlight
                    currentAlpha = 1.0
                } else if charProgress > 0 {
                    let progressFactor = min(1, charProgress * 15.0)
                    currentAlpha = CGFloat(0.55 + 0.45 * progressFactor)
                    targetRGB = Self.mix(baseRGB, highlight,
                                         amount: CGFloat(progressFactor))
                    if charProgress < 0.4 {
                        flashPop = pow(1 - charProgress / 0.4, 2.0) * 0.65
                    }
                }
                let glowRadius = baseGlow * (1.0 + flashPop)
                let shadowFade = Self.clampD((glowRadius - 0.5) / 2.0, 0, 1)
                let shadowRadius: CGFloat = (glowRadius > 0.5 && shadowFade > 0.01)
                    ? CGFloat(glowRadius * glowDropShadowScale) : 0
                let shadowOpacity: Float = shadowRadius > 0
                    ? Float(Double(currentAlpha) * shadowFade) : 0
                let textColor = targetRGB.withAlphaComponent(currentAlpha)

                let newCenter = CGPoint(x: CGFloat(centerX + x),
                                        y: CGFloat(centerY + y))
                let newScale = CGFloat(scale)
                let newRotation = CGFloat(tilt * Double.pi / 180)
                if abs(label.appliedCenter.x - newCenter.x) > 0.05
                    || abs(label.appliedCenter.y - newCenter.y) > 0.05
                    || abs(label.appliedScale - newScale) > 0.002
                    || abs(label.appliedRotation - newRotation) > 0.0005 {
                    label.center = newCenter
                    label.transform = CGAffineTransform(rotationAngle: newRotation)
                        .scaledBy(x: newScale, y: newScale)
                    label.appliedCenter = newCenter
                    label.appliedScale = newScale
                    label.appliedRotation = newRotation
                }
                if abs(label.appliedAlpha - finalOpacity) > 0.002 {
                    label.alpha = finalOpacity
                    label.appliedAlpha = finalOpacity
                }
                if label.appliedColor != textColor {
                    label.textColor = textColor
                    label.layer.shadowColor = targetRGB.cgColor
                    label.appliedColor = textColor
                }
                if abs(label.appliedShadowRadius - shadowRadius) > 0.1
                    || abs(label.appliedShadowOpacity - shadowOpacity) > 0.01 {
                    label.layer.shadowRadius = shadowRadius
                    label.layer.shadowOpacity = shadowOpacity
                    label.appliedShadowRadius = shadowRadius
                    label.appliedShadowOpacity = shadowOpacity
                }
            }
        }
    }

    /// mixColors 的 RGB 线性混合（alpha 由调用方另行处理）。
    private static func mix(_ from: UIColor, _ to: UIColor,
                            amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: 1)
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        contentView.frame = bounds
        // 圆环位置（调参 positionX/Y，画面宽/高百分比，#1124）：
        // 网页歌词层 wrapper 以 translate(%, %)（相对自身尺寸
        // = 全舞台）平移、轴线以 left/top 50%+position 定位，
        // 两者同移；原生以帧原点偏移承接（bounds 不变，逐字
        // 投影的中心口径不受影响），(57) C2 接线。
        let positionOffset = CGPoint(
            x: bounds.width * CGFloat(tuning.positionX) / 100,
            y: bounds.height * CGFloat(tuning.positionY) / 100)
        ringContainer.frame = bounds.offsetBy(dx: positionOffset.x,
                                              dy: positionOffset.y)
        // 半径随视口变（旋转）时布局缓存失效、窗口重建。
        let radius = currentRadius()
        if builtRadius > 0 && abs(radius - builtRadius) > 0.5 {
            layoutCache.removeAll()
            layoutCacheOrder.removeAll()
            clearWindow()
            windowDirty = true
        }
        builtRadius = radius
        // 轴线：300×4、居中（position 缺省 0）、旋转 45°
        // （centerNormalTiltDeg = 90 − ellipseTiltDeg）。
        axisView.bounds = CGRect(x: 0, y: 0, width: 300, height: 4)
        axisView.center = CGPoint(x: bounds.width / 2 + positionOffset.x,
                                  y: bounds.height / 2 + positionOffset.y)
        axisView.transform = CGAffineTransform(
            rotationAngle: CGFloat((90 - ellipseTiltDeg) * Double.pi / 180))
        axisGradient.frame = axisView.bounds
        for lineView in lineViews {
            lineView.frame = ringContainer.bounds
        }
        if isActive, let position = context?.positionNow() {
            updateGlyphs(position: position)
        }
    }
}
