import UIKit
import QuartzCore

// 残光 afterglow（原创稿三，2026-11-20 定稿，DESIGN.md 第三稿）：
// 长曝光——唱过的每个短语段在原位印成一枚残影，缓沉淡出、
// 在身后积成沉积层；当前行被封面色的一束光从侧面擦过（擦光
// 带 + 干净字形蒙版，光只落在字上）；逐词辉光淡出拉长到
// 1.6s（见 GlowEcho 说明）。下一行 primary/0.3 静态预告。
//
// 印制单位是短语段（DS 对账 #7）：标点（。，、；！？与空格）
// 切分，无标点按约 0.7s 或 4 字素兜底、下限 0.5s/段——释放
// 节奏只依赖行时间轴与文本，不依赖逐字戳真伪。残影池上限
// 10 枚，池满最老一枚提前 0.4s 淡出回收。
//
// 时钟纪律：只消费宿主 frameTick，不自建时钟源；残影沉降/
// 淡出、辉光余辉走 UIView 动画（系统合成），frameTick 只做
// 段落边界判定与擦光带位置（二者均为状态变化/单值更新）。

// MARK: - 短语段

private struct AfterglowSegment {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    /// 字素区间（行内字素序，含段尾标点）。
    var graphemeRange: Range<Int>
}

// MARK: - 渲染方

final class AfterglowStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    private let ghostLayer = UIView()
    private let grainView = UIView()
    private let currentContainer = UIView()
    private let echoContainer = UIView()
    private let sweepContainer = UIView()
    private let sweepGradient = CAGradientLayer()
    private let nextLabel = UILabel()

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    private var isActive = false
    private var wordViews: [GlowWordView] = []
    /// 当前行字素布局：(字素, x 起点, 宽, start, end, 所属词视图帧)。
    private var graphemeLayout: [(x: CGFloat, width: CGFloat,
                                  start: TimeInterval, end: TimeInterval)] = []
    private var segments: [AfterglowSegment] = []
    private var nextPrintIndex = 0
    private var echoedUnits: Set<Int> = []
    private var ghosts: [UIImageView] = []
    private var ghostSerial = 0
    private var currentIndex: Int? = nil
    private var currentLineFrame: CGRect = .zero
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var lastPosition: TimeInterval? = nil
    private var lastSweepSegment = -1
    private static var grainImage: UIImage?

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        rootView.clipsToBounds = true
        ghostLayer.isUserInteractionEnabled = false
        currentContainer.isUserInteractionEnabled = false
        echoContainer.isUserInteractionEnabled = false
        sweepContainer.isUserInteractionEnabled = false
        sweepContainer.clipsToBounds = false
        sweepGradient.startPoint = CGPoint(x: 0, y: 0.5)
        sweepGradient.endPoint = CGPoint(x: 1, y: 0.5)
        sweepContainer.layer.addSublayer(sweepGradient)
        nextLabel.textAlignment = .center
        nextLabel.isUserInteractionEnabled = false
        // 下一行预览的溢出兜底（3.7 (46)）：定宽框内自适应缩
        // 字（最低 0.6 倍），长行不截断溢出。
        nextLabel.adjustsFontSizeToFitWidth = true
        nextLabel.minimumScaleFactor = 0.6
        // 层序：残影（后）→ 当前行（中）→ 余辉/擦光（前）。
        rootView.addSubview(ghostLayer)
        rootView.addSubview(currentContainer)
        rootView.addSubview(echoContainer)
        rootView.addSubview(sweepContainer)
        rootView.addSubview(nextLabel)
        // 静态颗粒层（256×256 平铺、alpha 0.05、一次性生成；
        // 是预渲染纹理层，不是逐帧滤镜/后处理链）。
        if Self.grainImage == nil { Self.grainImage = Self.makeGrainImage() }
        if let grain = Self.grainImage {
            grainView.backgroundColor = UIColor(patternImage: grain)
        }
        grainView.alpha = 0.05
        grainView.isUserInteractionEnabled = false
        rootView.addSubview(grainView)
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) { self.context = context }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        self.snapshot = snapshot
        if snapshot.track?.id != builtTrackId || snapshot.lines.count != builtLineCount {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            clearGhosts(fade: false)
            clearCurrentLine()
            currentIndex = nil
            lastPosition = nil
        }
        sweepGradient.colors = [
            snapshot.palette.accent.withAlphaComponent(0).cgColor,
            snapshot.palette.accent.withAlphaComponent(0.22).cgColor,
            snapshot.palette.accent.withAlphaComponent(0).cgColor,
        ]
        grainView.isHidden = ProcessInfo.processInfo.isLowPowerModeEnabled
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
            // 首帧建行（含前奏的下一行预告与擦光待命位）。
            buildCurrentLine(at: idx, position: position)
            if idx != nil { skipSegmentsPast(position: position) }
        } else if jumped {
            // 切歌/seek：整池 0.3s 淡出清空，seek 不补印。
            clearGhosts(fade: true)
            clearEchoes()
            if idx != currentIndex {
                buildCurrentLine(at: idx, position: position)
            }
            skipSegmentsPast(position: position)
        } else if idx != currentIndex {
            // 自然行进：旧行剩余已唱完的段先补印（真实唱过
            // 的路径），再换行。
            printDueSegments(upTo: position, includeAllPast: true)
            buildCurrentLine(at: idx, position: position)
        }
        if idx != nil {
            printDueSegments(upTo: position, includeAllPast: false)
            spawnDueEchoes(position: position)
            for word in wordViews { word.update(position: position) }
            updateSweep(position: position, hasCurrent: true)
        } else {
            updateSweep(position: position, hasCurrent: false)
        }
        lastPosition = position
    }

    func unmount() {
        isActive = false
        clearGhosts(fade: false)
        clearEchoes()
        clearCurrentLine()
        context = nil
    }

    // MARK: 颗粒纹理（一次性生成，确定性种子）

    private static func makeGrainImage() -> UIImage {
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.clear.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: side, height: side))
            for i in 0..<6000 {
                let x = stageSeededRandom(Double(i) * 1.3 + 11) * Double(side)
                let y = stageSeededRandom(Double(i) * 2.9 + 47) * Double(side)
                let bright = stageSeededRandom(Double(i) * 0.7 + 83) > 0.5
                let alpha = 0.25 + stageSeededRandom(Double(i) * 1.9 + 5) * 0.5
                context.cgContext.setFillColor(
                    (bright ? UIColor.white : UIColor.black)
                        .withAlphaComponent(CGFloat(alpha)).cgColor)
                context.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }

    // MARK: 字号与当前行构建

    private func baseFontSize() -> CGFloat {
        let viewport = snapshot?.viewport.size ?? rootView.bounds.size
        let vmin = min(viewport.width, viewport.height)
        guard vmin > 0 else { return 36 }
        return max(36, min(6 * vmin / 100, 72))
    }

    /// 逐行适配（3.7 (46)）：与深廊同口径——整行实测宽按比例
    /// 缩字号、下限 12（旧下限 18 长行溢出）；词宽含辉光垫的
    /// 残余超宽由 buildCurrentLine 的两遍重建收尾。
    private func fontSize(for line: LyricLine) -> CGFloat {
        let avail = max(rootView.bounds.width - 64, 0)
        guard avail > 0 else { return baseFontSize() }
        return StageTextKit.fittedBoldSize(
            text: line.text, base: baseFontSize(),
            availWidth: avail, floor: 12)
    }

    private func clearCurrentLine() {
        for word in wordViews { word.removeFromSuperview() }
        wordViews = []
        graphemeLayout = []
        segments = []
        nextPrintIndex = 0
        echoedUnits = []
        sweepContainer.layer.mask = nil
        nextLabel.text = nil
    }

    private func clearEchoes() {
        for sub in echoContainer.subviews { sub.removeFromSuperview() }
    }

    private func buildCurrentLine(at idx: Int?, position: TimeInterval) {
        clearCurrentLine()
        clearEchoes()
        currentIndex = idx
        guard let idx, let snapshot, snapshot.lines.indices.contains(idx) else {
            updateNextLabel()
            // 前奏/间奏：擦光带停在下一行行首待命——把扫光
            // 容器与蒙版切到下一行的位置与字形上。
            if let snapshot, let nextLine = snapshot.lines.indices.contains(
                currentIndex.map { $0 + 1 } ?? 0)
                ? snapshot.lines[currentIndex.map { $0 + 1 } ?? 0] : nil {
                let size = fontSize(for: nextLine)
                let frame = CGRect(
                    x: 32, y: rootView.bounds.height * 0.40 - size * 0.75,
                    width: max(rootView.bounds.width - 64, 0), height: size * 1.5)
                currentLineFrame = frame
                sweepContainer.frame = frame
                installSweepMask(line: nextLine, font: StageFonts.bold(size: size),
                                 containerSize: frame.size)
            }
            return
        }
        let line = snapshot.lines[idx]
        let palette = snapshot.palette
        var size = fontSize(for: line)
        var font = StageFonts.bold(size: size)
        let profile = StageLineProfile.profile(for: line)
        let units = StageLyricUnits.units(for: line)

        // 活字行：GlowWordView 单行居中排布（长句已压字号）。
        func makeWords(_ wordFont: UIFont) -> ([GlowWordView], CGFloat) {
            var built: [GlowWordView] = []
            var sum: CGFloat = 0
            for unit in units {
                let word = GlowWordView(
                    unit: unit, pose: StageWordPose(), font: wordFont,
                    baseColor: palette.primary, activeColor: palette.accent,
                    profile: profile)
                built.append(word)
                sum += word.bounds.width
            }
            return (built, sum)
        }
        var (words, total) = makeWords(font)
        // 两遍适配（3.7 (46)）：词宽含辉光垫、纯文本测量估不
        // 到，合计超可用宽时按比例缩字号重建一遍（下限 8）；
        // 其后字素布局与扫光 mask 都用重建后的 font，几何一致。
        let availW = max(rootView.bounds.width - 64, 0)
        if total > availW, total > 0 {
            let scaled = max(8, size * availW / total)
            if scaled < size {
                size = scaled
                font = StageFonts.bold(size: size)
                (words, total) = makeWords(font)
            }
        }
        let bounds = rootView.bounds
        let lineHeight = size * 1.5
        let containerFrame = CGRect(
            x: 32, y: bounds.height * 0.40 - lineHeight / 2,
            width: max(bounds.width - 64, 0), height: lineHeight)
        currentLineFrame = containerFrame
        currentContainer.frame = containerFrame
        echoContainer.frame = containerFrame
        sweepContainer.frame = containerFrame
        var x = (containerFrame.width - total) / 2
        for word in words {
            word.frame.origin = CGPoint(
                x: x, y: (lineHeight - word.bounds.height) / 2)
            currentContainer.addSubview(word)
            word.snap(position: position)
            x += word.bounds.width
        }
        wordViews = words
        // 字素布局（段切分与擦光进度共用）：按原文宇素序建
        // 表（含空格），时刻由词单元匹配注入（空格取相邻单元
        // 间隙），匹配失败整行均分兜底——与 TuningLineView
        // 同一套对齐口径，保证段区间与布局表同序同长。
        graphemeLayout = Self.textGraphemeLayout(
            line: line, units: units, font: font, containerWidth: containerFrame.width)
        segments = Self.segment(line: line, graphemeTimes: graphemeLayout.map {
            (start: $0.start, end: $0.end)
        })
        nextPrintIndex = 0
        echoedUnits = []
        installSweepMask(line: line, font: font, containerSize: containerFrame.size)
        updateNextLabel()
        lastSweepSegment = -1
    }

    private func updateNextLabel() {
        guard let snapshot else { nextLabel.text = nil; return }
        let nextIndex = currentIndex.map { $0 + 1 } ?? 0
        guard snapshot.lines.indices.contains(nextIndex) else {
            nextLabel.text = nil
            return
        }
        let line = snapshot.lines[nextIndex]
        nextLabel.text = line.text
        nextLabel.font = StageFonts.bold(size: fontSize(for: line) * 0.62)
        nextLabel.textColor = snapshot.palette.primary
        nextLabel.alpha = 0.3
        if currentIndex != nil {
            nextLabel.frame = CGRect(
                x: 32, y: currentLineFrame.maxY + 18,
                width: max(rootView.bounds.width - 64, 0), height: baseFontSize())
        }
    }

    /// 原文字素布局：x 按真字宽从整行居中起点推进，时刻按
    /// 词单元匹配（词内均分）；空格字素时刻取前后单元间隙。
    private static func textGraphemeLayout(
        line: LyricLine, units: [StageWordUnit], font: UIFont, containerWidth: CGFloat)
        -> [(x: CGFloat, width: CGFloat, start: TimeInterval, end: TimeInterval)] {
        let graphemes = line.text.map { String($0) }
        let widths = graphemes.map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }
        let totalWidth = widths.reduce(0, +)
        var times = [(start: TimeInterval, end: TimeInterval)](
            repeating: (line.start, line.end), count: graphemes.count)
        var cursor = 0
        var matched = true
        for unit in units {
            let unitGraphemes = unit.text.map { String($0) }
            var start = cursor
            while start < graphemes.count && graphemes[start] == " " { start += 1 }
            guard start + unitGraphemes.count <= graphemes.count else { matched = false; break }
            for j in unitGraphemes.indices {
                if graphemes[start + j] != unitGraphemes[j] { matched = false; break }
                let span = max(unit.end - unit.start, 0.05)
                times[start + j] = (
                    unit.start + span * Double(j) / Double(max(unitGraphemes.count, 1)),
                    unit.start + span * Double(j + 1) / Double(max(unitGraphemes.count, 1)))
            }
            if !matched { break }
            cursor = start + unitGraphemes.count
        }
        if !matched {
            let span = max(line.end - line.start, 0.1)
            let total = max(graphemes.count, 1)
            for i in graphemes.indices {
                times[i] = (line.start + span * Double(i) / Double(total),
                            line.start + span * Double(i + 1) / Double(total))
            }
        } else {
            // 空格字素：时刻填前后已定字素之间的间隙。
            for i in graphemes.indices where graphemes[i] == " " {
                let prevEnd = i > 0 ? times[i - 1].end : line.start
                let nextStart = i + 1 < graphemes.count ? times[i + 1].start : line.end
                times[i] = (prevEnd, max(nextStart, prevEnd))
            }
        }
        var result: [(x: CGFloat, width: CGFloat, start: TimeInterval, end: TimeInterval)] = []
        var gx = (containerWidth - totalWidth) / 2
        for i in graphemes.indices {
            result.append((x: gx, width: widths[i], start: times[i].start, end: times[i].end))
            gx += widths[i]
        }
        return result
    }

    // MARK: 段切分（标点 + 兜底，下限 0.5s/段）

    private static func segment(line: LyricLine,
                                graphemeTimes: [(start: TimeInterval, end: TimeInterval)])
        -> [AfterglowSegment] {
        let graphemes = line.text.map { String($0) }
        // graphemeTimes 与 graphemes 等长时按其切分；词单元
        // 排布丢弃空格时长度可能不等，此时按行内均分兜底
        // （切分只依赖行时间轴与文本，DESIGN §② 改版口径）。
        let times: [(start: TimeInterval, end: TimeInterval)]
        if graphemeTimes.count == graphemes.count {
            times = graphemeTimes
        } else {
            let span = max(line.end - line.start, 0.1)
            let total = max(graphemes.count, 1)
            times = graphemes.indices.map {
                (line.start + span * Double($0) / Double(total),
                 line.start + span * Double($0 + 1) / Double(total))
            }
        }
        let punctuation: Set<String> = ["。", "，", "、", "；", "！", "？", " ", "　"]
        var result: [AfterglowSegment] = []
        var segmentStart = 0
        for i in graphemes.indices {
            let isPunctuation = punctuation.contains(graphemes[i])
            let duration = times[i].end - times[segmentStart].start
            let count = i - segmentStart + 1
            let fallbackDue = duration >= 0.5 && (duration >= 0.7 || count >= 4)
            if isPunctuation || fallbackDue || i == graphemes.count - 1 {
                // 空格作切分点时不并入段文本（段以空格前收尾）。
                var end = i + 1
                if graphemes[i] == " " || graphemes[i] == "　" { end = i }
                if end > segmentStart {
                    result.append(AfterglowSegment(
                        text: graphemes[segmentStart..<end].joined(),
                        start: times[segmentStart].start,
                        end: times[end - 1].end,
                        graphemeRange: segmentStart..<end))
                }
                segmentStart = i + 1
            }
        }
        return result
    }

    private func skipSegmentsPast(position: TimeInterval) {
        nextPrintIndex = segments.firstIndex { $0.end > position } ?? segments.count
        // 已开始的词不补余辉回放。
        echoedUnits = Set(wordViews.indices.filter {
            wordViews[$0].unit.end <= position
        })
    }

    // MARK: 残影池（GhostPool，上限 10）

    private func printDueSegments(upTo position: TimeInterval, includeAllPast: Bool) {
        while nextPrintIndex < segments.count
                && segments[nextPrintIndex].end <= position {
            let segment = segments[nextPrintIndex]
            nextPrintIndex += 1
            if includeAllPast || segment.end <= (currentIndexLineEnd() ?? position) {
                printGhost(segment: segment)
            }
        }
    }

    private func currentIndexLineEnd() -> TimeInterval? {
        guard let idx = currentIndex, let snapshot,
              snapshot.lines.indices.contains(idx) else { return nil }
        return snapshot.lines[idx].end
    }

    /// 印制一枚残影：段快照 UIImageView 落在原位，颜色
    /// mix(secondary, accent, 0.35)、初始 alpha 0.30，16s 内
    /// 淡出 + 缓沉 26pt、横向微偏 ±3pt（种子取段序）；沉降
    /// 终点朝舞台下三分之一（+26pt 为定稿位移量，从当前行
    /// 所在的舞台中段向下落底）。池满时最老一枚提前 0.4s
    /// 淡出回收。Reduce Motion：不沉降、原地淡出。
    private func printGhost(segment: AfterglowSegment) {
        guard let snapshot, let idx = currentIndex,
              snapshot.lines.indices.contains(idx),
              segment.graphemeRange.lowerBound < graphemeLayout.count else { return }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let poolLimit = lowPower ? 6 : 10
        while ghosts.count >= poolLimit, let oldest = ghosts.first {
            ghosts.removeFirst()
            UIView.animate(withDuration: 0.4) { oldest.alpha = 0 }
            completion: { _ in oldest.removeFromSuperview() }
        }
        let line = snapshot.lines[idx]
        let size = fontSize(for: line)
        let font = StageFonts.bold(size: size)
        let color = fumeMixColor(snapshot.palette.secondary, snapshot.palette.accent,
                                 0.35, alpha: 1)
        let range = segment.graphemeRange
        let minX = graphemeLayout[range.lowerBound].x
        let maxIndex = min(range.upperBound - 1, graphemeLayout.count - 1)
        let maxX = graphemeLayout[maxIndex].x + graphemeLayout[maxIndex].width
        let width = max(maxX - minX, 1)
        let height = size * 1.5
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color,
            ]
            let textSize = (segment.text as NSString).size(withAttributes: attributes)
            (segment.text as NSString).draw(
                in: CGRect(x: 0, y: (height - textSize.height) / 2,
                           width: width, height: textSize.height),
                withAttributes: attributes)
        }
        let ghostView = UIImageView(image: image)
        ghostSerial += 1
        let drift = CGFloat(stageSeededRandom(Double(ghostSerial) * 7.7 + 3) - 0.5) * 6
        ghostView.frame = CGRect(
            x: currentLineFrame.minX + minX, y: currentLineFrame.minY,
            width: width, height: height)
        ghostView.alpha = 0.30
        ghostView.isUserInteractionEnabled = false
        ghostLayer.addSubview(ghostView)
        ghosts.append(ghostView)
        let lifetime: TimeInterval = lowPower ? 9 : 16
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: lifetime, delay: 0, options: [.curveLinear]) {
            ghostView.alpha = 0
            if !reduceMotion {
                ghostView.transform = CGAffineTransform(translationX: drift, y: 26)
            }
        } completion: { [weak self] _ in
            ghostView.removeFromSuperview()
            self?.ghosts.removeAll { $0 === ghostView }
        }
    }

    private func clearGhosts(fade: Bool) {
        let pool = ghosts
        ghosts = []
        for ghost in pool {
            if fade {
                UIView.animate(withDuration: 0.3) { ghost.alpha = 0 }
                completion: { _ in ghost.removeFromSuperview() }
            } else {
                ghost.layer.removeAllAnimations()
                ghost.removeFromSuperview()
            }
        }
    }

    // MARK: 辉光余辉（1.6s）

    /// GlowWordEngine 内建辉光淡出为 0.9s 且写死在共享引擎
    /// （本任务不可改）。残光的 1.6s 口径以余辉层实现：词
    /// 唱完瞬间在其原位压一份 accent 辉光字（阴影出晕），
    /// 1.6s 淡出——与引擎自身 0.9s 辉光叠加后，可见辉光的
    /// 尾巴由 1.6s 余辉收尾，达成定稿时长。
    private func spawnDueEchoes(position: TimeInterval) {
        guard let snapshot else { return }
        for (index, word) in wordViews.enumerated() {
            guard position > word.unit.end, !echoedUnits.contains(index) else { continue }
            echoedUnits.insert(index)
            let size = fontSize(for: snapshot.lines[currentIndex ?? 0])
            let echo = UILabel(frame: word.frame)
            echo.text = word.unit.text
            echo.font = StageFonts.bold(size: size)
            echo.textAlignment = .center
            echo.textColor = snapshot.palette.accent
            echo.layer.shadowColor = snapshot.palette.accent.cgColor
            echo.layer.shadowOpacity = 1
            echo.layer.shadowRadius = 12
            echo.layer.shadowOffset = .zero
            echo.alpha = 0.85
            echo.isUserInteractionEnabled = false
            echoContainer.addSubview(echo)
            UIView.animate(withDuration: 1.6, delay: 0, options: [.curveEaseOut]) {
                echo.alpha = 0
            } completion: { _ in echo.removeFromSuperview() }
        }
    }

    // MARK: 擦光带（渐变 + 干净字形蒙版）

    /// 蒙版 = 无阴影无辉光的干净字形快照（建行时一次性渲染，
    /// DS 对账 #9），光只落在字上。
    private func installSweepMask(line: LyricLine, font: UIFont, containerSize: CGSize) {
        guard containerSize.width > 0 else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: containerSize, format: format)
        let image = renderer.image { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: UIColor.white,
            ]
            let textSize = (line.text as NSString).size(withAttributes: attributes)
            (line.text as NSString).draw(
                in: CGRect(x: (containerSize.width - textSize.width) / 2,
                           y: (containerSize.height - textSize.height) / 2,
                           width: textSize.width, height: textSize.height),
                withAttributes: attributes)
        }
        let maskLayer = CALayer()
        maskLayer.frame = CGRect(origin: .zero, size: containerSize)
        maskLayer.contents = image.cgImage
        sweepContainer.layer.mask = maskLayer
        sweepGradient.frame = CGRect(x: -containerSize.width * 0.38, y: 0,
                                     width: containerSize.width * 0.38,
                                     height: containerSize.height)
    }

    /// 擦光位置由已唱进度驱动：光带中心 x = 行内已唱进度
    /// 位置（字素时刻插值）。间奏时停在下一行行首待命、
    /// alpha 降到 0.08（以 layer.opacity 相对 0.22 峰值计）。
    /// Reduce Motion：位置只在段边界阶跃更新、不滑动。
    private func updateSweep(position: TimeInterval, hasCurrent: Bool) {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if reduceMotion && hasCurrent {
            let segmentIndex = segments.firstIndex { position < $0.end } ?? segments.count
            guard segmentIndex != lastSweepSegment else { return }
            lastSweepSegment = segmentIndex
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if hasCurrent, !graphemeLayout.isEmpty {
            sweepContainer.layer.opacity = 1
            var progressX: CGFloat = graphemeLayout[0].x
            for entry in graphemeLayout {
                if position >= entry.end {
                    progressX = entry.x + entry.width
                } else if position >= entry.start {
                    let fraction = CGFloat((position - entry.start)
                        / max(entry.end - entry.start, 0.001))
                    progressX = entry.x + entry.width * fraction
                    break
                } else { break }
            }
            let sweepWidth = sweepGradient.bounds.width
            sweepGradient.frame.origin = CGPoint(
                x: progressX - sweepWidth / 2, y: 0)
        } else {
            // 待命：停在行首，alpha 0.08 / 峰值 0.22 ≈ 0.36。
            sweepContainer.layer.opacity = 0.36
            let sweepWidth = sweepGradient.bounds.width
            sweepGradient.frame.origin = CGPoint(x: -sweepWidth / 2, y: 0)
        }
        CATransaction.commit()
    }

    // MARK: 布局

    private var lastLayoutSize: CGSize = .zero

    private func performLayout() {
        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        ghostLayer.frame = bounds
        grainView.frame = bounds
        // 只在尺寸真变化时重建当前行（旋转/分屏），避免普通
        // 布局 pass 反复重建冲掉段指针与余辉。
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        if let idx = currentIndex {
            buildCurrentLine(at: idx, position: lastPosition ?? 0)
            // 布局重建不补印：段指针按当前位跳过已唱段。
            skipSegmentsPast(position: lastPosition ?? 0)
        } else {
            nextLabel.frame = CGRect(
                x: 32, y: bounds.height * 0.40 + baseFontSize() * 1.4,
                width: bounds.width - 64, height: baseFontSize())
        }
        if currentIndex != nil {
            nextLabel.frame = CGRect(
                x: 32, y: currentLineFrame.maxY + 18,
                width: bounds.width - 64, height: baseFontSize())
        }
    }
}
