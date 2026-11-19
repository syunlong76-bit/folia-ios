import UIKit

// 浮名 fume · 文章版面与歌词揭示（照搬 folia-major 网页版）：
// 依据文件：fumeArticleLayout.ts（纸面/栏/块变体/放置）、
// fumeTextMeasure.ts（chooseSingleLineFontPx 二分找字号）、
// fumeMath.ts（FNV-1a seeded / 缓动）、fumeReveal.ts（词区间与
// 已印字素数）、renderHints.ts（行渲染结束时刻与转场时序）。
//
// 与网页的已知口径差（档案同步注明）：
//  - 网页用 pretext 做断行，原生无 pretext：断行用字素贪心
//    （逐字素测宽累加超宽换行）；CJK 与网页口径接近，拉丁词
//    内断点可能不同（网页按词边界断）。
//  - 协议 LyricLine 无 isChorus 字段：副歌 hero 分支恒不触发，
//    hero 只由短句周期/随机规则与兜底 hero 产生。
//  - 版面 seedKey 的主题名分量原生无来源（协议不传主题名），
//    以样式 id "fume" 代替，故洗牌顺序与网页不逐位一致，但
//    规则与分布同构。
//  - lyricsFontScale 原生恒 1（协议无此输入）。

// MARK: - 数学与种子（fumeMath.ts）

func fumeClamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
    max(minValue, min(maxValue, value))
}

func fumeClampF(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
    max(minValue, min(maxValue, value))
}

func fumeMix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
    from + (to - from) * amount
}

func fumeMixF(_ from: CGFloat, _ to: CGFloat, _ amount: CGFloat) -> CGFloat {
    from + (to - from) * amount
}

func fumeEaseOutCubic(_ value: Double) -> Double {
    1 - pow(1 - fumeClamp(value, 0, 1), 3)
}

func fumeEaseInCubic(_ value: Double) -> Double {
    pow(fumeClamp(value, 0, 1), 3)
}

func fumeEaseInOutCubic(_ value: Double) -> Double {
    let t = fumeClamp(value, 0, 1)
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

func fumeQuadraticBezier(_ from: Double, _ control: Double, _ to: Double, _ amount: Double) -> Double {
    let t = fumeClamp(amount, 0, 1)
    let inverse = 1 - t
    return inverse * inverse * from + 2 * inverse * t * control + t * t * to
}

/// 延迟辉光包络（fumeMath.resolveDelayedGlowEnvelope，峰值 0.8）。
func fumeDelayedGlowEnvelope(_ progress: Double, peakProgress: Double = 0.8) -> Double {
    let normalized = fumeClamp(progress, 0, 1)
    let peak = fumeClamp(peakProgress, 0.05, 0.95)
    if normalized <= peak {
        return fumeEaseOutCubic(normalized / peak)
    }
    return 1 - fumeEaseInCubic((normalized - peak) / (1 - peak))
}

/// FNV-1a 哈希（fumeMath.hashString）：按 UTF-16 码元迭代，
/// 与 JS charCodeAt 口径一致（&* 为 UInt32 溢出乘）。
func fumeHashString(_ input: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for unit in input.utf16 {
        hash ^= UInt32(unit)
        hash = hash &* 16_777_619
    }
    return hash
}

/// fumeMath.seeded：(hash % 10000) / 10000。
func fumeSeeded(_ seed: String) -> Double {
    Double(fumeHashString(seed) % 10000) / 10000
}

/// JS 数字模板插值口径（整数不带小数点），供种子串拼接。
func fumeJSNumber(_ value: Double) -> String {
    if value.isFinite && value == value.rounded() && abs(value) < 1e15 {
        return String(Int(value))
    }
    return String(value)
}

func fumeIsCJK(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        let v = scalar.value
        if (0x4E00...0x9FFF).contains(v) || (0x3040...0x30FF).contains(v)
            || (0xAC00...0xD7AF).contains(v) {
            return true
        }
    }
    return false
}

/// 颜色线性混合（colorMix.mixColors 的 RGB 口径，含 alpha）。
func fumeMixColor(_ from: UIColor, _ to: UIColor, _ amount: CGFloat, alpha: CGFloat) -> UIColor {
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    return UIColor(
        red: fumeMixF(r1, r2, amount), green: fumeMixF(g1, g2, amount),
        blue: fumeMixF(b1, b2, amount), alpha: alpha)
}

// MARK: - 行渲染时序（renderHints.ts 移植）

/// renderHints.getLineTransitionTiming 的原生复刻：入参为行
/// 时长分级（micro <0.10 / short <0.18 / 其余 normal）。
struct FumeLineTiming {
    var enterDuration: Double
    var exitDuration: Double
    var linePassHold: Double
    var transitionMode: Int   // 0 none / 1 fast / 2 normal
    var renderEnd: TimeInterval
}

func fumeLineTiming(for line: LyricLine) -> FumeLineTiming {
    let rawDuration = max(line.end - line.start, 0)
    let mode: Int = rawDuration < 0.10 ? 0 : (rawDuration < 0.18 ? 1 : 2)
    var enter: Double = 0, exit: Double = 0, hold: Double = 0
    if mode == 1 {
        enter = fumeClamp(rawDuration * 0.45, 0.045, 0.06)
        exit = fumeClamp(rawDuration * 0.22, 0.03, 0.04)
        hold = 0.03
    } else if mode == 2 {
        enter = min(0.42, max(0.22, max(rawDuration, 0.12) * 0.34))
        exit = min(0.32, max(0.18, max(rawDuration, 0.12) * 0.18))
        hold = 0.06
    }
    // renderEndTime（buildLineRenderEndTime）：末词结束以行 end
    // 代（原生 words 末词 end 与行 end 在解析器口径下一致）。
    let renderEnd: TimeInterval
    if mode == 0 {
        renderEnd = max(line.end, line.start + 0.067)
    } else {
        let passStart = max(line.end, line.start) + hold
        let exitStart = mode == 1
            ? max(line.start + enter + 0.01, passStart, line.end - exit)
            : max(passStart, line.end - exit)
        renderEnd = max(line.end, exitStart + exit)
    }
    return FumeLineTiming(enterDuration: enter, exitDuration: exit,
                          linePassHold: hold, transitionMode: mode,
                          renderEnd: renderEnd)
}

/// fumeCamera.resolveCameraRetargetDuration：相机换目标时长。
func fumeCameraRetargetDuration(for line: LyricLine) -> Double {
    let timing = fumeLineTiming(for: line)
    let rawDuration = max(line.end - line.start, 0)
    if timing.transitionMode == 0 {
        return fumeClamp(max(rawDuration, 0.08) * 0.34, 0.04, 0.075)
    }
    if timing.transitionMode == 1 {
        return fumeClamp(timing.enterDuration * 0.5 + timing.exitDuration * 0.12, 0.055, 0.095)
    }
    return fumeClamp(timing.enterDuration * 0.44 + timing.linePassHold * 0.22, 0.075, 0.13)
}

// MARK: - 版面数据结构（fumeTypes.ts 的原生子集）

struct FumeWordRangeData {
    var start: Int          // 字素区间（含尾随空白，与网页同）
    var end: Int
    var wordStart: TimeInterval
    var wordEnd: TimeInterval
    var text: String
}

struct FumeRenderLineData {
    var text: String
    var start: Int          // 全局字素偏移
    var end: Int
    var graphemes: [String]
    var glyphOffsets: [CGFloat]  // 相对行首的逐字素前沿偏移
    var left: CGFloat
    var top: CGFloat
    var width: CGFloat
}

struct FumeBlockData {
    var id: String
    var sourceLineIndex: Int
    var line: LyricLine
    var isHero: Bool
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var innerWidth: CGFloat
    var fontPx: CGFloat
    var lineHeight: CGFloat
    var graphemes: [String]
    var wordRanges: [FumeWordRangeData]
    var renderLines: [FumeRenderLineData]
    var renderEnd: TimeInterval
}

struct FumeArticleData {
    var width: CGFloat
    var height: CGFloat
    var paperLeft: CGFloat
    var paperTop: CGFloat
    var paperRight: CGFloat
    var paperBottom: CGFloat
    var blocks: [FumeBlockData]                    // 放置（洗牌）序
    var blockIndexBySourceLine: [Int: Int]         // 源行序 → blocks 下标
    var chronological: [Int]                       // 按源行序的 blocks 下标
    var firstRenderableStart: TimeInterval
    var lastRenderEnd: TimeInterval
}

// MARK: - 词区间与揭示（fumeReveal.ts 移植）

/// buildWordRangesFromWords：协议行 words → 字素区间；无 words
/// 时返回空（揭示走整行均分回退，与网页同）。尾随空白并入前词。
func fumeBuildWordRanges(line: LyricLine, graphemes: [String]) -> [FumeWordRangeData] {
    guard let words = line.words, !words.isEmpty, !graphemes.isEmpty else { return [] }
    let ranged = words.filter { !$0.text.isEmpty }
    guard !ranged.isEmpty else { return [] }
    var ranges: [FumeWordRangeData] = []
    var cursor = 0
    for word in ranged {
        let wordCount = word.text.count
        let start = min(max(cursor, 0), graphemes.count)
        var end = min(max(start + wordCount, start), graphemes.count)
        while end < graphemes.count && graphemes[end].trimmingCharacters(in: .whitespaces).isEmpty {
            end += 1
        }
        ranges.append(FumeWordRangeData(
            start: start, end: end,
            wordStart: word.start, wordEnd: word.end, text: word.text))
        cursor = end
    }
    return ranges
}

private func fumeWordRevealProgress(_ range: FumeWordRangeData, at time: TimeInterval) -> Double {
    if range.wordEnd <= range.wordStart {
        return time >= range.wordEnd ? 1 : 0
    }
    let duration = max(range.wordEnd - range.wordStart, 0.08)
    return fumeClamp((time - range.wordStart) / duration, 0, 1)
}

private func fumePrintedGlyphs(in range: FumeWordRangeData, at time: TimeInterval) -> Int {
    let length = max(range.end - range.start, 0)
    if length == 0 { return 0 }
    if time < range.wordStart { return 0 }
    // 原生 words 无音节戳：走网页无 timed glyphs 的进度分支。
    let progress = fumeWordRevealProgress(range, at: time)
    if progress >= 1 { return length }
    // 网页：clamp(floor(progress × length + 0.2), progress>0 ? 1 : 0, length)
    return Int(fumeClamp(
        floor(progress * Double(length) + 0.2),
        progress > 0 ? 1 : 0, Double(length)))
}

/// resolvePrintedGraphemeCount：时刻 time 已印字素数（整数）。
func fumePrintedCount(line: LyricLine, ranges: [FumeWordRangeData],
                      graphemeCount: Int, at time: TimeInterval) -> Int {
    if graphemeCount == 0 { return 0 }
    if time < line.start { return 0 }
    if time >= line.end { return graphemeCount }
    if ranges.isEmpty {
        let duration = max(line.end - line.start, 0.12)
        let progress = fumeClamp((time - line.start) / duration, 0, 1)
        let raw = floor(progress * Double(graphemeCount) + (progress > 0 ? 1 : 0))
        return Int(fumeClamp(raw, 0, Double(graphemeCount)))
    }
    var printed = 0
    for range in ranges {
        let partial = fumePrintedGlyphs(in: range, at: time)
        printed = range.start + partial
        if partial < range.end - range.start {
            return Int(fumeClamp(Double(printed), 0, Double(graphemeCount)))
        }
    }
    return Int(fumeClamp(Double(printed), 0, Double(graphemeCount)))
}

/// resolvePrintedGraphemeProgress：同上但保留小数（smooth 相机）。
func fumePrintedProgress(line: LyricLine, ranges: [FumeWordRangeData],
                         graphemeCount: Int, at time: TimeInterval) -> Double {
    if graphemeCount == 0 { return 0 }
    if time < line.start { return 0 }
    if time >= line.end { return Double(graphemeCount) }
    if ranges.isEmpty {
        let duration = max(line.end - line.start, 0.12)
        let progress = fumeClamp((time - line.start) / duration, 0, 1)
        return fumeClamp(progress * Double(graphemeCount), 0, Double(graphemeCount))
    }
    var printed: Double = 0
    for range in ranges {
        if time < range.wordStart { return fumeClamp(printed, 0, Double(graphemeCount)) }
        let progress = fumeWordRevealProgress(range, at: time)
        let length = Double(max(range.end - range.start, 0))
        printed = Double(range.start) + progress * length
        if progress < 1 { return fumeClamp(printed, 0, Double(graphemeCount)) }
    }
    return fumeClamp(printed, 0, Double(graphemeCount))
}

// MARK: - 文章版面构建（fumeArticleLayout.ts 移植）

/// 版面构建器：测宽缓存跨 attempt 共享（对应网页 lineMeasures）。
final class FumeArticleBuilder {
    private var widthCache: [String: CGFloat] = [:]
    private var fontCache: [String: UIFont] = [:]

    /// 块字体：hero 字重 780 → Songti Bold；body 640 → Songti
    /// Regular 回退系统 semibold（iOS 宋体无 640 档，档案注明）。
    func font(fontPx: CGFloat, isHero: Bool) -> UIFont {
        let key = "\(isHero ? "h" : "b")|\(Int((fontPx * 100).rounded()))"
        if let cached = fontCache[key] { return cached }
        let font: UIFont
        if isHero {
            font = StageFonts.bold(size: fontPx)
        } else {
            font = UIFont(name: "STSongti-SC-Regular", size: fontPx)
                ?? .systemFont(ofSize: fontPx, weight: .semibold)
        }
        fontCache[key] = font
        return font
    }

    private func naturalWidth(text: String, fontPx: CGFloat, isHero: Bool) -> CGFloat {
        let key = "\(isHero ? "h" : "b")|\(Int((fontPx * 100).rounded()))|\(text)"
        if let cached = widthCache[key] { return cached }
        let width = (text as NSString).size(withAttributes: [.font: font(fontPx: fontPx, isHero: isHero)]).width
        widthCache[key] = width
        return width
    }

    private func graphemeWidths(text: String, fontPx: CGFloat, isHero: Bool) -> [CGFloat] {
        let font = font(fontPx: fontPx, isHero: isHero)
        return text.map { ch in
            (String(ch) as NSString).size(withAttributes: [.font: font]).width
        }
    }

    /// 贪心断行：返回每行的字素区间与行宽（pretext 的原生近似）。
    private func wrap(text: String, fontPx: CGFloat, isHero: Bool, innerWidth: CGFloat)
        -> [(start: Int, end: Int, width: CGFloat, offsets: [CGFloat])] {
        let graphemes = text.map { String($0) }
        let widths = graphemeWidths(text: text, fontPx: fontPx, isHero: isHero)
        var lines: [(Int, Int, CGFloat, [CGFloat])] = []
        var lineStart = 0
        var lineWidth: CGFloat = 0
        var offsets: [CGFloat] = [0]
        for i in graphemes.indices {
            let w = widths[i]
            if i > lineStart && lineWidth + w > innerWidth {
                lines.append((lineStart, i, lineWidth, offsets))
                lineStart = i
                lineWidth = 0
                offsets = [0]
            }
            lineWidth += w
            offsets.append(lineWidth)
        }
        if lineStart < graphemes.count || lines.isEmpty {
            lines.append((lineStart, graphemes.count, lineWidth, offsets))
        }
        return lines
    }

    private func renderableCount(_ text: String) -> Int {
        text.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
    }

    // MARK: 块变体（chooseNaturalBlockVariant / 兜底 hero）

    private func naturalVariant(text: String, index: Int, total: Int) -> Bool {
        let count = renderableCount(text)
        if count == 0 { return false }
        // isChorus 分支：协议无副歌标记，恒不触发（档案注明）。
        let shortEnough = count >= 4 && count <= 28
        let centered = abs(Double(index) - Double(total) / 2) / Double(max(total, 1))
        let random = fumeSeeded("\(text):\(index)")
        return shortEnough && centered < 0.72 && ((index + 1) % 6 == 0 || random > 0.965)
    }

    private func fallbackHeroIndex(entries: [(line: LyricLine, index: Int)]) -> Int {
        if entries.isEmpty { return -1 }
        let hasNatural = entries.enumerated().contains {
            naturalVariant(text: $0.element.line.text, index: $0.offset, total: entries.count)
        }
        if hasNatural { return -1 }
        var bestIndex = -1
        var bestScore = -Double.infinity
        for (blockIndex, entry) in entries.enumerated() {
            let count = renderableCount(entry.line.text)
            if count == 0 { continue }
            let comfortable = count >= 4 && count <= 28
            let acceptable = count <= 36
            if !comfortable && !acceptable { continue }
            let centered = abs(Double(blockIndex) - Double(entries.count) / 2) / Double(max(entries.count, 1))
            let centerScore = 1 - centered
            let lengthScore = (count >= 6 && count <= 22) ? 1.0 : (count <= 28 ? 0.72 : 0.36)
            let jitter = fumeSeeded("\(entry.line.text):\(blockIndex):fallback-hero") * 0.04
            let score = centerScore * 0.62 + lengthScore * 0.34 + jitter
            if score > bestScore { bestScore = score; bestIndex = blockIndex }
        }
        if bestIndex >= 0 { return bestIndex }
        var shortest = -1
        var shortestCount = Int.max
        for (blockIndex, entry) in entries.enumerated() {
            let count = renderableCount(entry.line.text)
            if count > 0 && count < shortestCount { shortestCount = count; shortest = blockIndex }
        }
        return shortest
    }

    // MARK: 字号（chooseSingleLineFontPx 的二分移植）

    private func chooseFontPx(text: String, isHero: Bool, innerWidth: CGFloat,
                              densityScale: Double, heroScale: Double)
        -> (fontPx: CGFloat, lineCount: Int) {
        var low = isHero ? 18.0 : 10.0
        var high = isHero ? 58.0 : 30.0
        var best: Double? = nil
        for _ in 0..<8 {
            let mid = (low + high) / 2
            let candidate = mid * densityScale * (isHero ? heroScale : 1)
            if naturalWidth(text: text, fontPx: CGFloat(candidate), isHero: isHero) <= innerWidth {
                best = candidate
                low = mid
            } else {
                high = mid
            }
        }
        if let best {
            let wrapped = wrap(text: text, fontPx: CGFloat(best), isHero: isHero, innerWidth: innerWidth)
            return (CGFloat(best), max(wrapped.count, 1))
        }
        let fallback = (isHero ? 18.0 : 10.0) * densityScale * (isHero ? heroScale : 1)
        let wrapped = wrap(text: text, fontPx: CGFloat(fallback), isHero: isHero, innerWidth: innerWidth)
        return (CGFloat(fallback), max(wrapped.count, 1))
    }

    // MARK: 单次 attempt（measure 只算高度，render 出全部细节）

    private struct AttemptResult {
        var height: CGFloat
        var blocks: [FumeBlockData]
    }

    private func attempt(lines: [LyricLine], viewport: CGSize,
                         paperWidth: CGFloat, columns: Int, gap: CGFloat,
                         densityScale: Double, heroScale: Double,
                         render: Bool) -> AttemptResult {
        let horizontalMargin = max(viewport.width * 0.86, 280)
        let verticalMargin = max(viewport.height * 0.82, 220)
        let columnWidth = (paperWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let seedKey = "fume:\(columns):\(fumeJSNumber(Double(paperWidth)))"

        let filtered = lines.enumerated()
            .map { (line: $0.element, index: $0.offset) }
            .filter { !$0.line.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted {
                fumeSeeded("\(seedKey):\($0.index):\($0.line.text)")
                    < fumeSeeded("\(seedKey):\($1.index):\($1.line.text)")
            }
        let forcedHero = fallbackHeroIndex(entries: filtered)

        var blocks: [FumeBlockData] = []
        var columnHeights = [CGFloat](repeating: verticalMargin, count: columns)
        var bodyTie = 0
        var heroTie = 0

        for (blockIndex, entry) in filtered.enumerated() {
            let line = entry.line
            let isHero = blockIndex == forcedHero
                || naturalVariant(text: line.text, index: blockIndex, total: filtered.count)
            let heroSpanColumns = isHero ? min(columns, columns <= 1 ? 1 : 2) : 1
            let heroSpanWidth = heroSpanColumns > 1
                ? columnWidth * CGFloat(heroSpanColumns) + gap * CGFloat(heroSpanColumns - 1)
                : paperWidth
            let blockWidth: CGFloat
            if isHero {
                if heroSpanColumns == 1 { blockWidth = paperWidth }
                else if columns == 2 { blockWidth = columnWidth * 1.5 + gap * 0.5 }
                else { blockWidth = heroSpanWidth }
            } else {
                blockWidth = columnWidth
            }
            let innerWidth = max(blockWidth, 120)
            let (fontPx, lineCount) = chooseFontPx(
                text: line.text, isHero: isHero, innerWidth: innerWidth,
                densityScale: densityScale, heroScale: heroScale)
            let lineHeight = CGFloat(Int((Double(fontPx) * (isHero ? 1.02 : 1.06)).rounded()))
            let blockGap = isHero
                ? max((Double(lineHeight) * 0.2).rounded(), 6)
                : max((Double(lineHeight) * 0.08).rounded(), 2)
            let blockHeight = lineHeight * CGFloat(lineCount)
            var x: CGFloat = 0
            var y: CGFloat = 0

            if isHero {
                if heroSpanColumns == 1 {
                    y = columnHeights.max() ?? verticalMargin
                    x = horizontalMargin
                    columnHeights[0] = y + blockHeight + CGFloat(blockGap)
                } else {
                    var bestHeight = CGFloat.infinity
                    var candidates: [Int] = []
                    for startColumn in 0...(columns - heroSpanColumns) {
                        var covered: CGFloat = 0
                        for c in startColumn..<(startColumn + heroSpanColumns) {
                            covered = max(covered, columnHeights[c])
                        }
                        if covered < bestHeight { bestHeight = covered; candidates = [startColumn] }
                        else if covered == bestHeight { candidates.append(startColumn) }
                    }
                    let targetStart = candidates.isEmpty ? 0 : candidates[heroTie % candidates.count]
                    heroTie += 1
                    y = bestHeight
                    x = horizontalMargin + CGFloat(targetStart) * (columnWidth + gap)
                        + max((heroSpanWidth - blockWidth) * 0.5, 0)
                    for c in targetStart..<(targetStart + heroSpanColumns) {
                        columnHeights[c] = y + blockHeight + CGFloat(blockGap)
                    }
                }
            } else {
                var minHeight = columnHeights[0]
                var candidates = [0]
                for c in 1..<columns {
                    if columnHeights[c] < minHeight {
                        minHeight = columnHeights[c]
                        candidates = [c]
                    } else if columnHeights[c] == minHeight {
                        candidates.append(c)
                    }
                }
                let target = candidates[bodyTie % candidates.count]
                bodyTie += 1
                x = horizontalMargin + CGFloat(target) * (columnWidth + gap)
                y = columnHeights[target]
                columnHeights[target] = y + blockHeight + CGFloat(blockGap)
            }

            if render {
                let graphemes = line.text.map { String($0) }
                let wrapped = wrap(text: line.text, fontPx: fontPx, isHero: isHero, innerWidth: innerWidth)
                var renderLines: [FumeRenderLineData] = []
                for (lineIndex, w) in wrapped.enumerated() {
                    let sliceGraphemes = Array(graphemes[w.start..<w.end])
                    renderLines.append(FumeRenderLineData(
                        text: sliceGraphemes.joined(),
                        start: w.start, end: w.end,
                        graphemes: sliceGraphemes,
                        glyphOffsets: Array(w.offsets.dropLast()),
                        left: isHero ? max((blockWidth - w.width) * 0.08, 0) : 0,
                        top: CGFloat(lineIndex) * lineHeight,
                        width: w.width))
                }
                blocks.append(FumeBlockData(
                    id: "fume-\(line.start)-\(entry.index)",
                    sourceLineIndex: entry.index, line: line, isHero: isHero,
                    x: x, y: y, width: blockWidth, height: blockHeight,
                    innerWidth: innerWidth, fontPx: fontPx, lineHeight: lineHeight,
                    graphemes: graphemes,
                    wordRanges: fumeBuildWordRanges(line: line, graphemes: graphemes),
                    renderLines: renderLines,
                    renderEnd: fumeLineTiming(for: line).renderEnd))
            }
        }

        let articleHeight = (columnHeights.max() ?? 0) + verticalMargin
        return AttemptResult(height: articleHeight, blocks: blocks)
    }

    // MARK: 全文版面（buildArticleLayout 的 attempt 搜索移植）

    func build(lines: [LyricLine], viewport: CGSize, heroScale: Double) -> FumeArticleData? {
        guard viewport.width > 0, viewport.height > 0, !lines.isEmpty else { return nil }
        let paperWidth = fumeClampF(max(viewport.width * 1.95, viewport.width + 520), 920, 2400)
        let viewportHeight = max(viewport.height, 240)
        let maxColumns = paperWidth >= 1120 ? 4 : (paperWidth >= 760 ? 3 : (paperWidth >= 500 ? 2 : 1))
        let targetHeight = viewportHeight * 2.45
        let horizontalMargin = max(viewport.width * 0.86, 280)
        let verticalMargin = max(viewport.height * 0.82, 220)

        var bestScore = Double.infinity
        var bestColumns = 1
        var bestGap: CGFloat = 6
        var bestDensity = 1.0

        for columns in stride(from: maxColumns, through: 1, by: -1) {
            let gap = fumeClampF(
                CGFloat(Int((Double(paperWidth) * (columns >= 4 ? 0.0065 : (columns == 3 ? 0.0085 : 0.0115))).rounded())),
                6, 14)
            var low = 0.82
            var high = 1.42
            for _ in 0..<8 {
                let density = (low + high) / 2
                let result = attempt(lines: lines, viewport: viewport,
                                     paperWidth: paperWidth, columns: columns, gap: gap,
                                     densityScale: density, heroScale: heroScale, render: false)
                let height = Double(result.height)
                let target = Double(targetHeight)
                let score = abs(height - target) + (height < target ? 0 : (height - target) * 0.14)
                if score < bestScore {
                    bestScore = score
                    bestColumns = columns
                    bestGap = gap
                    bestDensity = density
                }
                if height < target { low = density } else { high = density }
            }
        }

        let rendered = attempt(lines: lines, viewport: viewport,
                               paperWidth: paperWidth, columns: bestColumns, gap: bestGap,
                               densityScale: bestDensity, heroScale: heroScale, render: true)
        guard !rendered.blocks.isEmpty else { return nil }
        let chronological = rendered.blocks.indices.sorted {
            rendered.blocks[$0].sourceLineIndex < rendered.blocks[$1].sourceLineIndex
        }
        var bySource: [Int: Int] = [:]
        for (idx, block) in rendered.blocks.enumerated() {
            bySource[block.sourceLineIndex] = idx
        }
        let firstStart = chronological.first.map { rendered.blocks[$0].line.start } ?? .infinity
        let lastEnd = chronological.last.map { rendered.blocks[$0].renderEnd } ?? -.infinity
        return FumeArticleData(
            width: paperWidth + horizontalMargin * 2,
            height: rendered.height,
            paperLeft: horizontalMargin, paperTop: verticalMargin,
            paperRight: horizontalMargin + paperWidth,
            paperBottom: max(rendered.height - verticalMargin, verticalMargin),
            blocks: rendered.blocks,
            blockIndexBySourceLine: bySource,
            chronological: chronological,
            firstRenderableStart: firstStart,
            lastRenderEnd: lastEnd)
    }
}
