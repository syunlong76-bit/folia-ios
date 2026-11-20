import UIKit
import QuartzCore

// 调频 tuning（原创稿一，2026-11-20 定稿，DESIGN.md 第一稿）：
// 文字本身的动——下一行先以噪声字形浮在暗处，随演唱临近逐字
// 「锁台」成真字；当前行在唱词走一次锁定脉冲；唱完的行以
// 「信号丢失」退场。舞台恒定两行（当前行 + 下一行）。
//
// 数据口径：只消费宿主 frameTick 喂入的 lines/words/anchor
// 派生位置，不自建时钟源，不碰同步/judge 逻辑。逐字素槽位在
// 建行时按真字宽锁定，噪声换字只写 label.text，零布局抖动。
// 噪声字池只用 Songti SC 确定覆盖的大写拉丁/数字/符号（DS
// 对账 #1：片假名会触发字体回退，已删）。

/// 噪声字池（Songti SC 确定覆盖集，DESIGN 第一稿 §②）。
private let tuningNoisePool: [String] =
    Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map { String($0) }
    + ["+", "−", "×", "=", "%", "#"]

// MARK: - 单行视图（逐字素标签 + 噪声/锁台状态机）

final class TuningLineView: UIView {

    let line: LyricLine
    let graphemes: [String]
    /// 字素 → 词单元下标（-1 = 空格等无单元字素）。
    let unitIndexByGrapheme: [Int]
    let units: [StageWordUnit]
    /// 字素起止时刻（词内均分，与 GlowWordEngine 同口径）。
    let graphemeTimes: [(start: TimeInterval, end: TimeInterval)]
    private let labels: [UILabel]
    private let font: UIFont
    private let palette: PaletteTokens
    let contentWidth: CGFloat
    let contentHeight: CGFloat

    // 噪声/锁台状态（next 角色）
    private var locked: [Bool]
    private var noiseChars: [String]
    private var lastBuckets: [Int]
    private var bucketLengths: [TimeInterval]
    private var lockTimes: [TimeInterval] = []
    // 当前行状态（current 角色）
    private var graphemeStates: [Int]   // 0 未唱 / 1 在唱 / 2 已唱
    private var pulsedUnits: Set<Int> = []

    init(line: LyricLine, fontSize: CGFloat, palette: PaletteTokens) {
        self.line = line
        self.palette = palette
        self.font = StageFonts.bold(size: fontSize)
        let graphemes = line.text.map { String($0) }
        self.graphemes = graphemes

        // 字素 ↔ 词单元对齐：按序在原文中匹配单元文本（跳过
        // 空格），失败则整行均分兜底（与 StageLyricUnits 的
        // even grapheme timing 同口径）。
        let units = StageLyricUnits.units(for: line)
        self.units = units
        var unitByGrapheme = [Int](repeating: -1, count: graphemes.count)
        var times = [(start: TimeInterval, end: TimeInterval)](
            repeating: (line.start, line.end), count: graphemes.count)
        var cursor = 0
        var matched = true
        for (unitIndex, unit) in units.enumerated() {
            let unitGraphemes = unit.text.map { String($0) }
            var start = cursor
            while start < graphemes.count && graphemes[start] == " " { start += 1 }
            guard start + unitGraphemes.count <= graphemes.count else { matched = false; break }
            for j in unitGraphemes.indices {
                if graphemes[start + j] != unitGraphemes[j] { matched = false; break }
                unitByGrapheme[start + j] = unitIndex
                let span = max(unit.end - unit.start, 0.05)
                times[start + j] = (
                    unit.start + span * Double(j) / Double(max(unitGraphemes.count, 1)),
                    unit.start + span * Double(j + 1) / Double(max(unitGraphemes.count, 1)))
            }
            if !matched { break }
            cursor = start + unitGraphemes.count
        }
        if !matched {
            // 均分兜底同乘演唱跨度压缩比（3.7 (43) 路3，与
            // StageLyricUnits 无戳行同一口径）。
            let ratio = min(max(line.singingRatio, 0.3), 1)
            let span = max((line.end - line.start) * ratio, 0.1)
            let total = max(graphemes.count, 1)
            for i in graphemes.indices {
                times[i] = (line.start + span * Double(i) / Double(total),
                            line.start + span * Double(i + 1) / Double(total))
            }
        }
        self.unitIndexByGrapheme = unitByGrapheme
        self.graphemeTimes = times

        // 槽位：按真字宽锁定（空格按字宽计），噪声字在槽内居中。
        var labels: [UILabel] = []
        var x: CGFloat = 0
        let height = fontSize * 1.3
        for g in graphemes {
            let width = (g as NSString).size(withAttributes: [.font: font]).width
            let label = UILabel(frame: CGRect(x: x, y: 0, width: max(width, 1), height: height))
            label.text = g
            label.font = font
            label.textAlignment = .center
            label.textColor = palette.primary
            label.isUserInteractionEnabled = false
            labels.append(label)
            x += width
        }
        self.labels = labels
        self.contentWidth = x
        self.contentHeight = height
        self.locked = [Bool](repeating: false, count: graphemes.count)
        self.noiseChars = graphemes
        self.lastBuckets = [Int](repeating: Int.min, count: graphemes.count)
        // 每字素桶长 120–200ms：种子 = line.id × 1000 + 字素序。
        self.bucketLengths = graphemes.indices.map { i in
            0.12 + 0.08 * stageSeededRandom(Double(line.id * 1000 + i) + 977)
        }
        self.graphemeStates = [Int](repeating: 0, count: graphemes.count)
        super.init(frame: CGRect(x: 0, y: 0, width: x, height: height))
        isUserInteractionEnabled = false
        for label in labels { addSubview(label) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func seed(for graphemeIndex: Int) -> Double {
        Double(line.id * 1000 + graphemeIndex)
    }

    private func isSpace(_ index: Int) -> Bool {
        graphemes[index] == " " || graphemes[index] == "　"
    }

    // MARK: 锁台时刻

    /// 锁台窗 W 与逐字锁定时刻由渲染方按 DESIGN 公式算好后
    /// 注入：lockTime(i) = start − W × (1 − i/n)；快歌批量
    /// 模式下 i 先量化到三段（batch = true 时本数组已量化）。
    func setLockTimes(_ times: [TimeInterval]) {
        lockTimes = times
    }

    // MARK: 噪声态（next 角色）

    /// 进入噪声态：未锁字素换成噪声字，颜色 secondary/0.5。
    func enterNoiseState(at position: TimeInterval) {
        for i in graphemes.indices {
            if isSpace(i) { locked[i] = true; labels[i].text = graphemes[i]; continue }
            let bucket = Int(floor(position / bucketLengths[i]))
            lastBuckets[i] = bucket
            noiseChars[i] = Self.noiseChar(seed: seed(for: i), bucket: bucket)
            labels[i].text = noiseChars[i]
            labels[i].textColor = palette.secondary
            labels[i].alpha = 0.5
        }
    }

    private static func noiseChar(seed: Double, bucket: Int) -> String {
        let r = stageSeededRandom(seed * 3.1 + Double(bucket) * 17.3)
        let index = min(Int(r * Double(tuningNoisePool.count)), tuningNoisePool.count - 1)
        return tuningNoisePool[index]
    }

    /// 逐帧推进（next 角色）：算时间桶、比对锁定时刻；状态
    /// 变化才动视图。changeFraction 为每桶换字比例。
    func updateNoise(position: TimeInterval, relaxedInterlude: Bool,
                     lowPower: Bool, reduceMotion: Bool) {
        if reduceMotion {
            // 降级：真字静态预告（渲染方另置 alpha 0.45）。
            for i in graphemes.indices where labels[i].text != graphemes[i] {
                labels[i].text = graphemes[i]
                labels[i].textColor = palette.primary
            }
            return
        }
        let changeFraction: Double
        if lowPower { changeFraction = 0.20 }
        else if relaxedInterlude { changeFraction = 0.25 }
        else { changeFraction = 0.40 }
        for i in graphemes.indices {
            if locked[i] || isSpace(i) { continue }
            if i < lockTimes.count && position >= lockTimes[i] {
                lockGrapheme(i, animated: true)
                continue
            }
            let bucketLength: TimeInterval
            if lowPower { bucketLength = 0.24 }
            else if relaxedInterlude { bucketLength = 0.28 }
            else { bucketLength = bucketLengths[i] }
            let bucket = Int(floor(position / bucketLength))
            guard bucket != lastBuckets[i] else { continue }
            lastBuckets[i] = bucket
            // 错相低频替换：本桶是否换字由种子+桶号确定性决定；
            // 「不换」需要历史状态（上一桶字形），故换字决定
            // 落在本视图的每字素桶记录里，字形本身仍由
            // stageSeededRandom(种子+桶) 确定性生成。
            let decision = stageSeededRandom(seed(for: i) + Double(bucket) * 31.7)
            if decision < changeFraction {
                noiseChars[i] = Self.noiseChar(seed: seed(for: i), bucket: bucket)
                labels[i].text = noiseChars[i]
            }
        }
    }

    /// 锁台一瞬：140ms 交叉淡化换真字 + 弹簧 scale 1.12→1.0
    /// （damping 0.6）+ 色闪（secondary→mix(accent 40%,
    /// primary)→primary，200ms 走完）。
    func lockGrapheme(_ index: Int, animated: Bool) {
        guard !locked[index] else { return }
        locked[index] = true
        let label = labels[index]
        let flash = fumeMixColor(palette.primary, palette.accent, 0.4, alpha: 1)
        if !animated {
            label.layer.removeAllAnimations()
            label.transform = .identity
            label.text = graphemes[index]
            label.textColor = palette.primary
            label.alpha = 0.92
            return
        }
        label.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
        UIView.transition(with: label, duration: 0.14,
                          options: .transitionCrossDissolve) {
            label.text = self.graphemes[index]
            label.textColor = flash
            label.alpha = 0.92
        }
        UIView.animate(withDuration: 0.28, delay: 0,
                       usingSpringWithDamping: 0.6, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            label.transform = .identity
        }
        // 色闪回落：UIView.transition 无 delay 参数，以 0 时长
        // 动画的 completion 作 60ms 定时，再交叉淡化回 primary
        // （色闪全程 200ms 走完，规格不变）。
        UIView.animate(withDuration: 0, delay: 0.06, options: []) {
        } completion: { _ in
            UIView.transition(with: label, duration: 0.2,
                              options: .transitionCrossDissolve) {
                label.textColor = self.palette.primary
            }
        }
    }

    func lockAll(animated: Bool) {
        for i in graphemes.indices where !locked[i] { lockGrapheme(i, animated: animated) }
    }

    /// seek 落位：已过锁定时刻的字素直接锁定，其余回噪声态。
    func snapNoise(position: TimeInterval) {
        for i in graphemes.indices {
            if isSpace(i) { continue }
            if i < lockTimes.count && position >= lockTimes[i] {
                lockGrapheme(i, animated: false)
            }
        }
    }

    // MARK: 当前行（current 角色）

    /// 逐帧推进（current 角色）：已唱 text/0.85、未唱
    /// primary/0.92；在唱词触发锁定脉冲（门控见 pulseIfNeeded）。
    func updateCurrent(position: TimeInterval, lowPower: Bool,
                       reduceMotion: Bool, fastLine: Bool) {
        for i in graphemes.indices {
            let state: Int
            if position >= graphemeTimes[i].end { state = 2 }
            else if position >= graphemeTimes[i].start { state = 1 }
            else { state = 0 }
            if state != graphemeStates[i] {
                graphemeStates[i] = state
                let label = labels[i]
                switch state {
                case 2: label.textColor = palette.text; label.alpha = 0.85
                default: label.textColor = palette.primary; label.alpha = 0.92
                }
            }
        }
        // 在唱词脉冲：按词单元判定（消费 words/均分单元）。
        for (unitIndex, unit) in units.enumerated() {
            guard position >= unit.start && position <= unit.end else { continue }
            guard !pulsedUnits.contains(unitIndex) else { continue }
            pulsedUnits.insert(unitIndex)
            pulse(unitIndex: unitIndex, lowPower: lowPower,
                  reduceMotion: reduceMotion, fastLine: fastLine)
        }
    }

    /// 落位（seek/首建）：颜色直接摆位，已过词不补脉冲。
    func snapCurrent(position: TimeInterval) {
        for i in graphemes.indices {
            let state = position >= graphemeTimes[i].end ? 2
                : (position >= graphemeTimes[i].start ? 1 : 0)
            graphemeStates[i] = state
            labels[i].textColor = state == 2 ? palette.text : palette.primary
            labels[i].alpha = state == 2 ? 0.85 : 0.92
        }
        for (unitIndex, unit) in units.enumerated() where position > unit.end {
            pulsedUnits.insert(unitIndex)
        }
    }

    /// 锁定脉冲：scale 1.06 弹簧回落（0.18s、damping 0.55、
    /// beginFromCurrentState 不排队）+ accent 重影（x+1.5pt、
    /// alpha 0.35、220ms 淡出）。门控：词时长 ≥0.22s 才触发；
    /// 快行（行时长 <0.8s）整体跳过；低电量取消重影。
    private func pulse(unitIndex: Int, lowPower: Bool,
                       reduceMotion: Bool, fastLine: Bool) {
        let unit = units[unitIndex]
        guard unit.end - unit.start >= 0.22, !fastLine else { return }
        let indices = graphemes.indices.filter { unitIndexByGrapheme[$0] == unitIndex }
        guard !indices.isEmpty else { return }
        if !reduceMotion {
            for i in indices {
                let label = labels[i]
                label.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
                UIView.animate(withDuration: 0.18, delay: 0,
                               usingSpringWithDamping: 0.55, initialSpringVelocity: 0,
                               options: [.beginFromCurrentState]) {
                    label.transform = .identity
                }
            }
        }
        guard !lowPower && !reduceMotion else { return }
        let minX = indices.map { labels[$0].frame.minX }.min() ?? 0
        let maxX = indices.map { labels[$0].frame.maxX }.max() ?? 0
        let ghost = UILabel(frame: CGRect(x: minX + 1.5, y: 0,
                                          width: maxX - minX, height: contentHeight))
        ghost.text = unit.text
        ghost.font = font
        ghost.textAlignment = .center
        ghost.textColor = palette.accent
        ghost.alpha = 0.35
        ghost.isUserInteractionEnabled = false
        insertSubview(ghost, at: 0)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            ghost.alpha = 0
        } completion: { _ in ghost.removeFromSuperview() }
    }
}

// MARK: - 渲染方

final class TuningStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    private var isActive = false
    private var currentView: TuningLineView?
    private var nextView: TuningLineView?
    private var currentIndex: Int? = nil
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var lastPosition: TimeInterval? = nil

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        rootView.clipsToBounds = true
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) { self.context = context }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        self.snapshot = snapshot
        if snapshot.track?.id != builtTrackId || snapshot.lines.count != builtLineCount {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            clearAll()
        }
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let lines = snapshot.lines
        guard !lines.isEmpty else { lastPosition = position; return }
        let jumped = lastPosition.map {
            position < $0 - 0.3 || position - $0 > 1.5
        } ?? false
        let idx = LyricParser.currentIndex(in: lines, at: position)
        if lastPosition == nil {
            // 首帧落位（含前奏：当前行空缺、首行以噪声态预告）。
            transition(to: idx, position: position, snap: true)
        } else if jumped || idx != currentIndex || currentView == nil && idx != nil {
            transition(to: idx, position: position, snap: jumped)
        }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if let current = currentView {
            let fastLine = (current.line.end - current.line.start) < 0.8
            current.updateCurrent(position: position, lowPower: lowPower,
                                  reduceMotion: reduceMotion, fastLine: fastLine)
        }
        if let next = nextView {
            let timeUntilNext = next.line.start - position
            let gap = currentView.map { next.line.start - $0.line.end } ?? timeUntilNext
            let relaxed = timeUntilNext > 4 || gap > 4
            next.updateNoise(position: position, relaxedInterlude: relaxed,
                             lowPower: lowPower, reduceMotion: reduceMotion)
        }
        lastPosition = position
    }

    func unmount() {
        isActive = false
        clearAll()
        context = nil
    }

    // MARK: 行切换

    private func clearAll() {
        currentView?.removeFromSuperview()
        nextView?.removeFromSuperview()
        currentView = nil
        nextView = nil
        currentIndex = nil
        lastPosition = nil
    }

    /// 锁台时刻表（DESIGN §②）：W = min(本行时长, 1.6s)，
    /// lockTime(i) = start − W × (1 − i/n)。注：解析口径下
    /// 行 end == 下行 start（间奏 ≈ 0 为常态），DESIGN 的
    /// 间奏分支据此落为：间奏 <0.4s 时整行分三段批量锁
    /// （量化 i 到三段），间奏 ≥0.4s 时逐字锁；W 本身即借
    /// 上一行尾段完成（start − W 起点落在上一行内）。
    private func lockTimes(for line: LyricLine, after current: LyricLine?) -> [TimeInterval] {
        let n = max(line.text.count, 1)
        let window = min(line.end - line.start, 1.6)
        let gap = current.map { line.start - $0.end } ?? window
        let batch = gap < 0.4
        return (0..<n).map { i in
            let fraction: Double
            if batch {
                let segment = min(2, i * 3 / n)
                fraction = Double(segment) / 2 * Double(max(n - 1, 1)) / Double(n)
            } else {
                fraction = Double(i) / Double(n)
            }
            return line.start - window * (1 - fraction)
        }
    }

    private func transition(to idx: Int?, position: TimeInterval, snap: Bool) {
        guard let snapshot else { return }
        let lines = snapshot.lines
        let reduceMotion = UIAccessibility.isReduceMotionEnabled

        // 旧当前行退场（信号丢失）：260ms alpha→0.25 + 退
        // secondary + 下沉 0.8pt，再 200ms 淡出。snap 时直删。
        if let old = currentView {
            currentView = nil
            if snap {
                old.removeFromSuperview()
            } else {
                UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseIn]) {
                    old.alpha = 0.25
                    old.transform = old.transform.translatedBy(x: 0, y: 0.8)
                } completion: { _ in
                    UIView.animate(withDuration: 0.2) { old.alpha = 0 }
                    completion: { _ in old.removeFromSuperview() }
                }
                // 退色与第一段同步走（标签色非可动画属性，用
                // crossDissolve 过渡近似同段退色）。
                for sub in old.subviews.compactMap({ $0 as? UILabel }) {
                    UIView.transition(with: sub, duration: 0.26,
                                      options: .transitionCrossDissolve) {
                        sub.textColor = snapshot.palette.secondary
                    }
                }
            }
        }

        currentIndex = idx

        // 当前行：优先升用已锁台的 next 视图，否则新建落位。
        var promoted: TuningLineView? = nil
        if let idx, let next = nextView, next.line.id == lines[idx].id {
            promoted = next
            nextView = nil
        } else if let next = nextView {
            next.removeFromSuperview()
            nextView = nil
        }
        if let idx, lines.indices.contains(idx) {
            let line = lines[idx]
            if let promoted {
                promoted.lockAll(animated: false)
                promoted.snapCurrent(position: position)
                currentView = promoted
                if !rootView.subviews.contains(promoted) { rootView.addSubview(promoted) }
                placeCurrent(promoted, animated: !snap && !reduceMotion)
            } else {
                let built = makeLineView(line: line)
                built.snapCurrent(position: position)
                currentView = built
                rootView.addSubview(built)
                placeCurrent(built, animated: false)
                built.alpha = 1
            }
        }

        // 下一行：idx 的下一行；前奏（idx == nil）时为首行。
        let nextIndex: Int? = idx.map { $0 + 1 } ?? 0
        if let nextIndex, lines.indices.contains(nextIndex) {
            let line = lines[nextIndex]
            let built = makeLineView(line: line)
            built.setLockTimes(lockTimes(for: line, after: idx.map { lines[$0] }))
            if reduceMotion {
                built.alpha = 0.45
            } else {
                built.enterNoiseState(at: position)
                built.snapNoise(position: position)
            }
            nextView = built
            rootView.addSubview(built)
            placeNext(built)
        }
        rootView.setNeedsLayout()
    }

    // MARK: 构建与布局

    private func fontSize() -> CGFloat {
        let viewport = snapshot?.viewport.size ?? rootView.bounds.size
        let vmin = min(viewport.width, viewport.height)
        guard vmin > 0 else { return 36 }
        return max(36, min(6 * vmin / 100, 72))
    }

    private func makeLineView(line: LyricLine) -> TuningLineView {
        guard let snapshot else {
            return TuningLineView(line: line, fontSize: 36, palette: .neutralDark)
        }
        return TuningLineView(line: line, fontSize: fontSize(), palette: snapshot.palette)
    }

    /// 当前行槽位：居中于舞台 42% 高处，恒等变换。
    private func placeCurrent(_ lineView: TuningLineView, animated: Bool) {
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        let center = CGPoint(x: bounds.width / 2, y: bounds.height * 0.42)
        let apply = {
            lineView.center = center
            lineView.transform = .identity
            lineView.alpha = 1
        }
        if animated {
            // 升焦平面：0.5s 系统弹簧（damping 0.85）。
            UIView.animate(withDuration: 0.5, delay: 0,
                           usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState], animations: apply)
        } else { apply() }
    }

    /// 下一行槽位：当前行下方，scale 0.55（0.55 倍字号区）。
    private func placeNext(_ lineView: TuningLineView) {
        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        lineView.center = CGPoint(
            x: bounds.width / 2,
            y: bounds.height * 0.42 + fontSize() * 2.0)
        lineView.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
    }

    private func performLayout() {
        if let current = currentView {
            let center = CGPoint(x: rootView.bounds.width / 2,
                                 y: rootView.bounds.height * 0.42)
            if current.transform == .identity { current.center = center }
        }
        if let next = nextView {
            next.center = CGPoint(x: rootView.bounds.width / 2,
                                  y: rootView.bounds.height * 0.42 + fontSize() * 2.0)
        }
    }
}
