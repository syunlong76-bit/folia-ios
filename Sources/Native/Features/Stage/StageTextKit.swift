import UIKit
import CoreText
import QuartzCore

// StageTextKit — CoreText 文字基建（3.7 (42)，特效移植第 0 号
// 共性工程，莫奈先行、后续七稿复用）：
//  - 字体落点：网页主题 serif 栈（首选「獅尾四季春加糖SC」）
//    在 iOS 不内置，栈内首个可达者为 Songti SC；StageFonts
//    既有 bold(700)/light(300)，本文件补 regular(400)。
//  - 测量：CTLine/CTFramesetter 实测字素偏移与字形高度，
//    口径对齐网页 pretext/canvas measureText（字素前缀宽度、
//    ascent+descent 字形高、安全量 2px、默认行高 1.18 倍）。
//  - 栅格：CoreText 自绘（CTFrameDraw/CTLineDraw）成图，供
//    静态行与扫字词层使用；逐词软边扫字（网页 background-
//    clip:text + mask 的等价物）由 StageSweepWordView 以
//    「底色图 + 填充图（渐变 alpha 预烘焙）+ 渐变 mask 逐帧
//    推进」实现——逐帧只改 mask 的 locations，不重栅格化。
//  - 时刻：逐字素时刻表（词单元匹配注入、空格取间隙、失配
//    整行均分），与 Afterglow 私有实现同一套对齐口径，此处
//    沉淀为共用件（Afterglow 不动，避免已验样式返工）。
// 时钟纪律与全舞台一致：只消费宿主 frameTick 位置。

extension StageFonts {
    /// Songti SC 正体 400（网页 serif 栈 500 档在 iOS 的落点
    /// 之一；主题字重解析缺省 600 时用不到，留给副字幕等
    /// 400/500 档场景）。
    static func serifRegular(size: CGFloat) -> UIFont {
        UIFont(name: "STSongti-SC-Regular", size: size)
            ?? .systemFont(ofSize: size, weight: .regular)
    }
}

/// 字符串的字素 ↔ UTF-16 索引映射（CoreText 全程 UTF-16 计量，
/// 歌词时刻与切分全程字素计量，两边靠本表换算）。
struct StageTextMap {
    let text: String
    let graphemes: [String]
    /// 每字素的 UTF-16 起点与长度。
    let utf16Start: [Int]
    let utf16Length: [Int]

    init(_ text: String) {
        self.text = text
        var graphemes: [String] = []
        var starts: [Int] = []
        var lengths: [Int] = []
        var offset = 0
        for ch in text {
            let s = String(ch)
            graphemes.append(s)
            starts.append(offset)
            lengths.append(s.utf16.count)
            offset += s.utf16.count
        }
        self.graphemes = graphemes
        self.utf16Start = starts
        self.utf16Length = lengths
    }

    /// UTF-16 偏移 → 所属字素序（偏移落在字素内部取该字素；
    /// 偏移 == 全长取末字素后一位，即 graphemes.count）。
    func graphemeIndex(forUTF16 offset: Int) -> Int {
        if offset <= 0 { return 0 }
        var lo = 0, hi = graphemes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if utf16Start[mid] + utf16Length[mid] <= offset { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

/// 一行文本的折行结果（CTFramesetter 实测）。
struct StageWrappedText {
    /// 每行的字素区间与实测行宽（pt）。
    var rows: [(graphemeRange: Range<Int>, width: CGFloat)]
    /// 单行行高（字形实测口径，全行共用一个值）。
    var lineHeight: CGFloat
    /// 是否因 maxLines 上限被截断。
    var clipped: Bool
    var totalHeight: CGFloat { CGFloat(rows.count) * lineHeight }
}

enum StageTextKit {

    // MARK: 字素偏移（单行不折行，CTLine 实测）

    /// 字素前缀 x 偏移表：count+1 个值，offsets[0]=0，末元 =
    /// 整串实测宽。任一字素测不到（连字/合字等）时整体回退
    /// 逐字素 NSString 宽度求和（与 Afterglow 旧口径一致）。
    static func graphemeOffsets(text: String, font: UIFont) -> [CGFloat] {
        let map = StageTextMap(text)
        let count = map.graphemes.count
        guard count > 0 else { return [0] }
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let ctLine = CTLineCreateWithAttributedString(attr)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        // 收集（UTF-16 索引 → 字形 x），按索引排序后逐字素取
        // 其首字形 x；同索引多字形取最小 x。
        var glyphX: [Int: CGFloat] = [:]
        let runs = CTLineGetGlyphRuns(ctLine) as! [CTRun]
        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            var indices = [CFIndex](repeating: 0, count: glyphCount)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            for i in 0..<glyphCount {
                let idx = indices[i]
                if let existing = glyphX[idx] {
                    glyphX[idx] = min(existing, positions[i].x)
                } else {
                    glyphX[idx] = positions[i].x
                }
            }
        }
        var offsets: [CGFloat] = []
        offsets.reserveCapacity(count + 1)
        var complete = true
        for g in 0..<count {
            if let x = glyphX[map.utf16Start[g]] {
                offsets.append(x)
            } else { complete = false; break }
        }
        if complete {
            offsets.append(lineWidth)
            return offsets
        }
        // 回退：逐字素宽度求和。
        var fallback: [CGFloat] = [0]
        for g in map.graphemes {
            let w = (g as NSString).size(withAttributes: [.font: font]).width
            fallback.append(fallback[fallback.count - 1] + w)
        }
        return fallback
    }

    // MARK: 字形高度与行高

    /// 字形高度 = CTLine 实测 ascent + descent（对齐网页
    /// canvas actualBoundingBoxAscent/Descent）。
    static func glyphHeight(text: String, font: UIFont) -> CGFloat {
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let ctLine = CTLineCreateWithAttributedString(attr)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(ctLine, &ascent, &descent, nil)
        return ascent + descent
    }

    /// 行高（网页 measureMonetLineHeight 口径）：空串以 "Hg"
    /// 代测；字形高 >0 时 max(默认行高, ceil(字形高 + 2))，
    /// 默认行高 = fontPx × 1.18。
    static func lineHeight(text: String, font: UIFont, fontPx: CGFloat) -> CGFloat {
        let defaultHeight = fontPx * 1.18
        let measured = glyphHeight(text: text.isEmpty ? "Hg" : text, font: font)
        return measured > 0 ? max(defaultHeight, ceil(measured + 2)) : defaultHeight
    }

    // MARK: 折行（CTFramesetter）

    static func wrap(text: String, font: UIFont, maxWidth: CGFloat,
                     maxLines: Int, fontPx: CGFloat) -> StageWrappedText {
        let height = lineHeight(text: text, font: font, fontPx: fontPx)
        guard !text.isEmpty, maxWidth > 0 else {
            return StageWrappedText(rows: [], lineHeight: height, clipped: false)
        }
        let map = StageTextMap(text)
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: maxWidth, height: 100_000),
                          transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), path, nil)
        let ctLines = CTFrameGetLines(frame) as! [CTLine]
        var rows: [(graphemeRange: Range<Int>, width: CGFloat)] = []
        for ctLine in ctLines {
            let range = CTLineGetStringRange(ctLine)
            let gStart = map.graphemeIndex(forUTF16: range.location)
            let gEnd = map.graphemeIndex(forUTF16: range.location + range.length)
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            rows.append((gStart..<max(gEnd, gStart), width))
            if rows.count >= maxLines { break }
        }
        return StageWrappedText(
            rows: rows, lineHeight: height, clipped: ctLines.count > maxLines)
    }

    // MARK: CoreText 栅格

    /// 整段文本栅格（CTFrameDraw）：按 maxWidth 折行、最多
    /// maxLines 行，返回图与折行信息。图尺寸 = maxWidth ×
    /// 实际行高总和（宽由调用方按需裁切/定位）。
    static func rasterize(text: String, font: UIFont, color: UIColor,
                          maxWidth: CGFloat, maxLines: Int, fontPx: CGFloat,
                          scale: CGFloat)
        -> (image: UIImage, wrapped: StageWrappedText)? {
        let wrapped = wrap(text: text, font: font, maxWidth: maxWidth,
                           maxLines: maxLines, fontPx: fontPx)
        guard !wrapped.rows.isEmpty else { return nil }
        let size = CGSize(width: maxWidth, height: wrapped.totalHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color,
        ])
        let image = renderer.image { context in
            let cg = context.cgContext
            let framesetter = CTFramesetterCreateWithAttributedString(attr)
            let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: 0, length: 0), path, nil)
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            cg.textMatrix = .identity
            CTFrameDraw(frame, cg)
        }
        return (image, wrapped)
    }

    /// 单词栅格（CTLineDraw）：图高 = boxHeight，基线由
    /// baselineFromBottom 定位（调用方按行盒几何算好）。
    static func rasterizeWord(text: String, font: UIFont, color: UIColor,
                              width: CGFloat, boxHeight: CGFloat,
                              baselineFromBottom: CGFloat, scale: CGFloat)
        -> UIImage? {
        guard width > 0, boxHeight > 0 else { return nil }
        let size = CGSize(width: width, height: boxHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color,
        ])
        let ctLine = CTLineCreateWithAttributedString(attr)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            cg.textMatrix = .identity
            cg.textPosition = CGPoint(x: 0, y: baselineFromBottom)
            CTLineDraw(ctLine, cg)
        }
    }

    /// 单词填充图：先以 fillColor 绘词，再以横向渐变
    /// （α 1 → 0.92 @68% → 0.72）destinationIn 烘焙——网页
    /// 扫字填充渐变的静态分量，逐帧只剩 mask 推进。
    static func rasterizeWordFill(text: String, font: UIFont, color: UIColor,
                                  width: CGFloat, boxHeight: CGFloat,
                                  baselineFromBottom: CGFloat, scale: CGFloat,
                                  rtl: Bool) -> UIImage? {
        guard width > 0, boxHeight > 0 else { return nil }
        let size = CGSize(width: width, height: boxHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color,
        ])
        let ctLine = CTLineCreateWithAttributedString(attr)
        return renderer.image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            cg.textMatrix = .identity
            cg.textPosition = CGPoint(x: 0, y: baselineFromBottom)
            CTLineDraw(ctLine, cg)
            cg.restoreGState()
            // 渐变 alpha 烘焙（destinationIn 与已绘像素取交）。
            cg.setBlendMode(.destinationIn)
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(white: 1, alpha: 1).cgColor,
                UIColor(white: 1, alpha: 0.92).cgColor,
                UIColor(white: 1, alpha: 0.72).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: colors,
                                         locations: [0, 0.68, 1]) {
                // LTR：左满右淡（渐变方向与填充色定义一致，
                // α 自左 1 降到右 0.72）；RTL 反向。
                let start = rtl ? CGPoint(x: size.width, y: 0) : CGPoint(x: 0, y: 0)
                let end = rtl ? CGPoint(x: 0, y: 0) : CGPoint(x: size.width, y: 0)
                cg.drawLinearGradient(gradient, start: start, end: end, options: [])
            }
            cg.setBlendMode(.normal)
        }
    }

    // MARK: 逐字素时刻表

    /// 逐字素 (start,end)：词单元按原文宇素序匹配注入（词内
    /// 均分），空格字素取前后间隙；匹配失败整行均分兜底。
    /// 与 AfterglowStageRenderer.textGraphemeLayout 同口径。
    static func graphemeTimes(line: LyricLine, words: [StageWordUnit])
        -> [(start: TimeInterval, end: TimeInterval)] {
        let graphemes = line.text.map { String($0) }
        var times = [(start: TimeInterval, end: TimeInterval)](
            repeating: (line.start, line.end), count: graphemes.count)
        var cursor = 0
        var matched = true
        for unit in words {
            let unitGraphemes = unit.text.map { String($0) }
            var start = cursor
            while start < graphemes.count && graphemes[start] == " " { start += 1 }
            guard start + unitGraphemes.count <= graphemes.count else {
                matched = false; break
            }
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
            for i in graphemes.indices where graphemes[i] == " " {
                let prevEnd = i > 0 ? times[i - 1].end : line.start
                let nextStart = i + 1 < graphemes.count ? times[i + 1].start : line.end
                times[i] = (prevEnd, max(nextStart, prevEnd))
            }
        }
        return times
    }

    // MARK: 扫字填充宽度（网页 resolveMonetFillWidth 逐行对译）

    /// offsets 为字素前缀宽（count+1），timings 与 offsets
    /// 前 count 段对应；在当前字素段时间段内线性插值。
    static func fillWidth(position: TimeInterval, start: TimeInterval,
                          end: TimeInterval, offsets: [CGFloat],
                          timings: [(start: TimeInterval, end: TimeInterval)])
        -> CGFloat {
        let width = offsets.last ?? 0
        if position <= start { return 0 }
        if position >= end { return width }
        let count = min(timings.count, offsets.count - 1)
        if count > 0 {
            for i in 0..<count {
                let tStart = max(start, timings[i].start)
                let tEnd = max(tStart, timings[i].end)
                if position < tStart { return offsets[i] }
                if position <= tEnd {
                    let p = (position - tStart) / max(0.001, tEnd - tStart)
                    return offsets[i] + (offsets[i + 1] - offsets[i]) * CGFloat(p)
                }
            }
            return offsets[count]
        }
        let progress = min(max((position - start) / max(0.001, end - start), 0), 1)
        let idx = progress * Double(offsets.count - 1)
        let whole = Int(floor(idx))
        if whole + 1 < offsets.count {
            return offsets[whole] + (offsets[whole + 1] - offsets[whole]) * CGFloat(idx - Double(whole))
        }
        return width
    }

    /// smoothstep（网页同名函数逐行对译）。
    static func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// Glow 包络（网页 resolveMonetGlow 逐行对译）：升程 =
    /// 词时长 ×1.18 smoothstep 升至峰值，其后 smoothstep 降
    /// 至 tail = max(行尾, 词尾 + 1.05s)，衰减分母下限 0.18。
    static func glowEnvelope(position: TimeInterval, start: TimeInterval,
                             end: TimeInterval, lineEnd: TimeInterval) -> Double {
        if position <= start { return 0 }
        let rise = max(0.001, end - start) * 1.18
        let peak = start + rise
        let tail = max(lineEnd, end + 1.05)
        if position <= peak {
            return smoothstep((position - start) / rise)
        }
        let remaining = 1 - min(max((position - peak) / max(0.18, tail - peak), 0), 1)
        return smoothstep(remaining)
    }
}

// MARK: - 扫字词视图

/// 逐词软边扫字（网页 MonetWordSweep 三层结构的原生等价）：
/// 底字层（baseColor 图）＋填充层（fillColor 图 + 渐变 mask
/// 逐帧推进，柔边 6–16px）＋Glow 层（两枚带 shadow 的同文
/// 图，只动 opacity 走包络）。全部图在配置时以 CoreText
/// 一次绘好，update 只改 mask locations 与 glow alpha。
final class StageSweepWordView: UIView {

    let start: TimeInterval
    let end: TimeInterval
    /// 词宽（pt）与字素前缀偏移（与 graphemeTimes 同序）。
    let wordWidth: CGFloat
    private let graphemeTimes: [(start: TimeInterval, end: TimeInterval)]
    private let graphemeOffsets: [CGFloat]
    private let edgeSoftness: CGFloat
    private let rtl: Bool

    private let glowViewFar = UIImageView()
    private let glowViewNear = UIImageView()
    private let baseView = UIImageView()
    private let fillView = UIImageView()
    private let fillMask = CAGradientLayer()

    init(text: String, font: UIFont, start: TimeInterval, end: TimeInterval,
         graphemeTimes: [(start: TimeInterval, end: TimeInterval)],
         baseColor: UIColor, fillColor: UIColor, glowColor: UIColor,
         isChorus: Bool, boxHeight: CGFloat, rtl: Bool) {
        self.start = start
        self.end = end
        self.graphemeTimes = graphemeTimes
        self.rtl = rtl
        let offsets = StageTextKit.graphemeOffsets(text: text, font: font)
        self.graphemeOffsets = offsets
        self.wordWidth = offsets.last ?? 0
        let fontPx = font.pointSize
        self.edgeSoftness = min(max(fontPx * 0.45, 6), 16)
        super.init(frame: CGRect(x: 0, y: 0, width: wordWidth, height: boxHeight))
        isUserInteractionEnabled = false
        // 基线：字形在行盒内垂直居中。
        let glyphH = StageTextKit.glyphHeight(text: text, font: font)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let ctLine = CTLineCreateWithAttributedString(attr)
        _ = CTLineGetTypographicBounds(ctLine, &ascent, &descent, nil)
        let baseline = (boxHeight - glyphH) / 2 + descent
        let scale: CGFloat = 3
        let glowImage = StageTextKit.rasterizeWord(
            text: text, font: font, color: glowColor, width: wordWidth,
            boxHeight: boxHeight, baselineFromBottom: baseline, scale: scale)
        // Glow：双层 text-shadow 等价——两枚同文图各挂一档
        // shadow 半径（近 0.28/0.45、远 0.65/0.90 ×fontPx），
        // 合成层只动 opacity（网页 glowHalo 同口径）。
        let r1 = (fontPx * (isChorus ? 0.45 : 0.28)).rounded()
        let r2 = (fontPx * (isChorus ? 0.90 : 0.65)).rounded()
        for (glowView, radius) in [(glowViewNear, r1), (glowViewFar, r2)] {
            glowView.image = glowImage
            glowView.frame = bounds
            glowView.layer.shadowColor = glowColor.cgColor
            glowView.layer.shadowOpacity = 1
            glowView.layer.shadowRadius = radius
            glowView.layer.shadowOffset = .zero
            glowView.alpha = 0
            addSubview(glowView)
        }
        baseView.image = StageTextKit.rasterizeWord(
            text: text, font: font, color: baseColor, width: wordWidth,
            boxHeight: boxHeight, baselineFromBottom: baseline, scale: scale)
        baseView.frame = bounds
        addSubview(baseView)
        fillView.image = StageTextKit.rasterizeWordFill(
            text: text, font: font, color: fillColor, width: wordWidth,
            boxHeight: boxHeight, baselineFromBottom: baseline, scale: scale,
            rtl: rtl)
        fillView.frame = bounds
        fillMask.startPoint = CGPoint(x: rtl ? 1 : 0, y: 0.5)
        fillMask.endPoint = CGPoint(x: rtl ? 0 : 1, y: 0.5)
        fillMask.frame = bounds
        fillMask.colors = [
            UIColor.black.cgColor, UIColor.black.cgColor,
            UIColor.black.withAlphaComponent(0.92).cgColor,
            UIColor.clear.cgColor, UIColor.clear.cgColor,
        ]
        fillMask.locations = [0, 0, 0, 0, 1]
        fillView.layer.mask = fillMask
        addSubview(fillView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// 逐帧推进：position 为宿主 frameTick 位置；lineEnd 为
    /// 本行渲染结束（glow 包络尾参）。
    func update(position: TimeInterval, lineEnd: TimeInterval) {
        let filled = StageTextKit.fillWidth(
            position: position, start: start, end: end,
            offsets: graphemeOffsets, timings: graphemeTimes)
        let width = max(wordWidth, 0.001)
        let progress = min(max(Double(filled / width), 0), 1)
        // 网页 resolveMonetSweepEnd / mask stops 逐行对译。
        let sweepEnd = Double(filled) + Double(edgeSoftness) * progress
        let solidEnd = max(sweepEnd - Double(edgeSoftness), 0)
        let featherStart = max(sweepEnd - Double(edgeSoftness) * 0.55, 0)
        let featherEnd = max(sweepEnd, 0)
        var locations: [Double] = [
            0,
            min(solidEnd / Double(width), 1),
            min(featherStart / Double(width), 1),
            min(featherEnd / Double(width), 1),
            1,
        ]
        for i in 1..<locations.count {
            locations[i] = max(locations[i], locations[i - 1])
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillMask.locations = locations.map { NSNumber(value: $0) }
        let glow = StageTextKit.glowEnvelope(
            position: position, start: start, end: end, lineEnd: lineEnd)
        glowViewNear.alpha = CGFloat(glow)
        glowViewFar.alpha = CGFloat(glow)
        CATransaction.commit()
    }
}

// MARK: - 扫字行视图

/// 扫字 token：静态 token（间隙/标点，无时刻）只以底色绘；
/// timed token 走 StageSweepWordView 三层。
struct StageSweepToken {
    var text: String
    var graphemeRange: Range<Int>
    var timed: Bool
    var start: TimeInterval = 0
    var end: TimeInterval = 0
    var graphemeTimes: [(start: TimeInterval, end: TimeInterval)] = []
    /// 布局后帧（行视图坐标系），由布局方回填。
    var frame: CGRect = .zero
}

/// 一整行扫字：token 原子盒布局（贪心折行，timed token
/// break:'never' 与网页测量口径一致），行内各词视图由
/// frameTick 统一 update。
final class StageSweepLineView: UIView {

    private var wordViews: [StageSweepWordView] = []
    private(set) var rowCount: Int = 0

    /// 配置并完成布局。maxWidth 为行内容宽；lineHeight 为
    /// 单行行高；返回总高（行数 × lineHeight）。
    @discardableResult
    func configure(tokens: [StageSweepToken], font: UIFont,
                   baseColor: UIColor, fillColor: UIColor,
                   glowColor: UIColor, isChorus: Bool,
                   maxWidth: CGFloat, lineHeight: CGFloat,
                   rtl: Bool) -> CGFloat {
        for sub in subviews { sub.removeFromSuperview() }
        wordViews = []
        // 量词宽：timed/static 都按 CTLine 实测（offsets 末元）。
        let widths = tokens.map {
            StageTextKit.graphemeOffsets(text: $0.text, font: font).last ?? 0
        }
        // 贪心折行（token 原子）：超宽 token 独占一行溢出。
        var rows: [[Int]] = []
        var currentRow: [Int] = []
        var currentWidth: CGFloat = 0
        for (index, tokenWidth) in widths.enumerated() {
            if !currentRow.isEmpty && currentWidth + tokenWidth > maxWidth {
                rows.append(currentRow)
                currentRow = []
                currentWidth = 0
            }
            currentRow.append(index)
            currentWidth += tokenWidth
        }
        if !currentRow.isEmpty { rows.append(currentRow) }
        rowCount = rows.count
        for (rowIndex, row) in rows.enumerated() {
            var x: CGFloat = 0
            for index in row {
                let token = tokens[index]
                let width = widths[index]
                defer { x += width }
                guard width > 0 else { continue }
                let frame = CGRect(x: x, y: CGFloat(rowIndex) * lineHeight,
                                   width: width, height: lineHeight)
                if token.timed {
                    let word = StageSweepWordView(
                        text: token.text, font: font, start: token.start,
                        end: token.end, graphemeTimes: token.graphemeTimes,
                        baseColor: baseColor, fillColor: fillColor,
                        glowColor: glowColor, isChorus: isChorus,
                        boxHeight: lineHeight, rtl: rtl)
                    word.frame = frame
                    addSubview(word)
                    wordViews.append(word)
                } else {
                    let imageView = UIImageView(frame: frame)
                    imageView.image = Self.staticTokenImage(
                        text: token.text, font: font, color: baseColor,
                        width: width, boxHeight: lineHeight)
                    imageView.isUserInteractionEnabled = false
                    addSubview(imageView)
                }
            }
        }
        return CGFloat(rows.count) * lineHeight
    }

    func update(position: TimeInterval, lineEnd: TimeInterval) {
        for word in wordViews { word.update(position: position, lineEnd: lineEnd) }
    }

    private static func staticTokenImage(text: String, font: UIFont,
                                         color: UIColor, width: CGFloat,
                                         boxHeight: CGFloat) -> UIImage? {
        let glyphH = StageTextKit.glyphHeight(text: text, font: font)
        var descent: CGFloat = 0
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let ctLine = CTLineCreateWithAttributedString(attr)
        _ = CTLineGetTypographicBounds(ctLine, nil, &descent, nil)
        let baseline = (boxHeight - glyphH) / 2 + descent
        return StageTextKit.rasterizeWord(
            text: text, font: font, color: color, width: width,
            boxHeight: boxHeight, baselineFromBottom: baseline, scale: 3)
    }
}
