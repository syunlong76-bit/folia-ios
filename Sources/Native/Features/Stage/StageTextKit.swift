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
        let font = UIFont(name: "STSongti-SC-Regular", size: size)
            ?? .systemFont(ofSize: size, weight: .regular)
        StageFontBreadcrumb.note(slot: "serifRegular",
                                 requested: "STSongti-SC-Regular",
                                 resolved: font)
        return font
    }
}

/// 字体落点面包屑（3.7 (46)，DS 莫奈 H4 取证）：每个字体槽位
/// 只落一次——请求名、实际解析到的字体名、是否走了系统回退。
/// Songti SC 在个别系统版本/语言环境下缺字重时，回退是静默的；
/// 下次莫奈出问题凭此一行先判死字体线。
enum StageFontBreadcrumb {
    private static var noted = Set<String>()
    private static let lock = NSLock()

    static func note(slot: String, requested: String, resolved: UIFont) {
        lock.lock()
        let first = !noted.contains(slot)
        if first { noted.insert(slot) }
        lock.unlock()
        guard first else { return }
        Breadcrumbs.log("stage.font slot=\(slot) requested=\(requested) resolved=\(resolved.fontName) fallback=\(resolved.fontName != requested)")
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

    // MARK: 大字适配（原创样式共用，3.7 (46)）

    /// 逐行字号自适应收缩：以 base 字号实测整行文本宽，超出
    /// availWidth 时按比例缩字号（下限 floor），保证任何行不
    /// 溢出可用宽度。原创三样式（深廊/调频/残光）的字体溢出
    /// 修复共用此口径：先缩字号保大字感，缩到下限仍超宽的极
    /// 端行再由各样式自己的容器级兜底（fitScale/压印）收尾，
    /// 「不溢出」为硬线。测量字体与三样式实际用字同为
    /// StageFonts.bold（Songti SC Bold）。
    static func fittedBoldSize(text: String, base: CGFloat,
                               availWidth: CGFloat,
                               floor: CGFloat = 12) -> CGFloat {
        guard base > floor, availWidth > 0, !text.isEmpty else {
            return max(base, floor)
        }
        let width = (text as NSString)
            .size(withAttributes: [.font: StageFonts.bold(size: base)]).width
        guard width > availWidth else { return base }
        return max(floor, base * availWidth / width)
    }

    /// 渲染路径实测后的保证适配（3.7 (53) 工作流 K 新增，
    /// 只新增不改 fittedBoldSize 既有口径）：fittedBoldSize
    /// 以整串文本宽估算、且带业务下限（12/14），与各样式的
    /// 真实渲染宽（逐字素求和 / GlowWord 词宽合计 + 间距 /
    /// 辉光垫）存在系统差，下限处更是直接放弃适配——长行
    /// 恒溢出框。本函数供各样式在「按自身渲染路径实测出
    /// 实际内容宽」后调用：超宽则按实测宽等比折算字号，
    /// 不设业务下限（字宽与字号成正比，一次折算即精确落
    /// 回可用宽内）；未超宽原样返回。调用方以折算字号重
    /// 建一次即收敛，不做逐帧/循环调用。
    static func resizedToFit(currentSize: CGFloat, measuredWidth: CGFloat,
                             availWidth: CGFloat) -> CGFloat {
        guard currentSize > 0, measuredWidth > availWidth,
              measuredWidth > 0, availWidth > 0 else { return currentSize }
        return currentSize * availWidth / measuredWidth
    }

    // MARK: CoreText 栅格

    /// 显式位图上下文栅格（3.7 (46)，DS 莫奈 H2 定案）：替代
    /// UIGraphicsImageRenderer——后者在后台 bake 队列里创建
    /// UIKit 图形上下文属未定义行为面（线程安全/上下文隔离
    /// 无保证，是莫奈闪退的嫌疑路径之一）。改走纯
    /// CGBitmapContext（DeviceRGB/premultipliedLast）：初始
    /// CTM 按 UIGraphics 口径复刻（scale ∘ y 翻转、原点左
    /// 上），三个栅格函数的绘制代码与原渲染器闭包逐字一致，
    /// 输出 UIImage 的 scale 语义不变；主/后台线程均可安全
    /// 调用，保真不降（同字号、同 scale、同 CT 绘制）。
    private static func bitmapImage(size: CGSize, scale: CGFloat,
                                    draw: (CGContext) -> Void) -> UIImage? {
        let widthPx = max(1, Int(ceil(size.width * scale)))
        let heightPx = max(1, Int(ceil(size.height * scale)))
        guard let cg = CGContext(
            data: nil, width: widthPx, height: heightPx,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        draw(cg)
        guard let cgImage = cg.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

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
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color,
        ])
        guard let image = bitmapImage(size: size, scale: scale, draw: { cg in
            let framesetter = CTFramesetterCreateWithAttributedString(attr)
            let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: 0, length: 0), path, nil)
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            cg.textMatrix = .identity
            CTFrameDraw(frame, cg)
        }) else { return nil }
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
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color,
        ])
        let ctLine = CTLineCreateWithAttributedString(attr)
        return bitmapImage(size: size, scale: scale) { cg in
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
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color,
        ])
        let ctLine = CTLineCreateWithAttributedString(attr)
        return bitmapImage(size: size, scale: scale) { cg in
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

    // MARK: 扫字成图预备（后台队列专用，3.7 (44)）

    /// 逐 token 成图预备：把扫字词视图/静态 token 原先在主线
    /// 程 init/configure 里同步做的全部栅格化（timed 词三图
    /// @scale3、静态 token 单图）集中到此，专供后台队列调
    /// 用；主线程只拿成品图装配视图。基线与字素偏移口径与
    /// 视图侧原实现逐项一致（词盒高 = 行高）。
    static func prepareSweepImages(
        tokens: [StageSweepToken], font: UIFont,
        baseColor: UIColor, fillColor: UIColor, glowColor: UIColor,
        lineHeight: CGFloat, rtl: Bool, scale: CGFloat = 3
    ) -> [Int: StageSweepWordImages] {
        var result: [Int: StageSweepWordImages] = [:]
        for (index, token) in tokens.enumerated() {
            let offsets = graphemeOffsets(text: token.text, font: font)
            let wordWidth = offsets.last ?? 0
            guard wordWidth > 0 else {
                result[index] = StageSweepWordImages(
                    glow: nil, base: nil, fill: nil,
                    wordWidth: 0, graphemeOffsets: offsets)
                continue
            }
            let glyphH = glyphHeight(text: token.text, font: font)
            var descent: CGFloat = 0
            let attr = NSAttributedString(string: token.text,
                                          attributes: [.font: font])
            let ctLine = CTLineCreateWithAttributedString(attr)
            _ = CTLineGetTypographicBounds(ctLine, nil, &descent, nil)
            let baseline = (lineHeight - glyphH) / 2 + descent
            // 栅格倍率用入参 scale（3.7 (47)：由调用方按当前
            // 屏幕倍率传入；旧版在此恒 3，@2x 屏白烘、@3x
            // 屏恰合，改动态后两边都贴合显示尺寸）。
            if token.timed {
                result[index] = StageSweepWordImages(
                    glow: rasterizeWord(
                        text: token.text, font: font, color: glowColor,
                        width: wordWidth, boxHeight: lineHeight,
                        baselineFromBottom: baseline, scale: scale),
                    base: rasterizeWord(
                        text: token.text, font: font, color: baseColor,
                        width: wordWidth, boxHeight: lineHeight,
                        baselineFromBottom: baseline, scale: scale),
                    fill: rasterizeWordFill(
                        text: token.text, font: font, color: fillColor,
                        width: wordWidth, boxHeight: lineHeight,
                        baselineFromBottom: baseline, scale: scale,
                        rtl: rtl),
                    wordWidth: wordWidth, graphemeOffsets: offsets)
            } else {
                result[index] = StageSweepWordImages(
                    glow: nil,
                    base: rasterizeWord(
                        text: token.text, font: font, color: baseColor,
                        width: wordWidth, boxHeight: lineHeight,
                        baselineFromBottom: baseline, scale: scale),
                    fill: nil,
                    wordWidth: wordWidth, graphemeOffsets: offsets)
            }
        }
        return result
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

/// 扫字成图预备产物（3.7 (44)）：后台队列经
/// StageTextKit.prepareSweepImages 一次备齐，视图 init 只装
/// 配、不再栅格化。timed token 三图齐全（glow/base/fill）；
/// 静态 token 只有 base。wordWidth/graphemeOffsets 与视图
/// 侧原 init 的实测口径一致。
struct StageSweepWordImages {
    var glow: UIImage?
    var base: UIImage?
    var fill: UIImage?
    var wordWidth: CGFloat
    var graphemeOffsets: [CGFloat]
}

/// 逐词软边扫字（网页 MonetWordSweep 三层结构的原生等价）：
/// 底字层（baseColor 图）＋填充层（fillColor 图 + 渐变 mask
/// 逐帧推进，柔边 6–16px）＋Glow 层（两枚带 shadow 的同文
/// 图，只动 opacity 走包络）。全部图由 prepareSweepImages
/// 在后台备好后注入（3.7 (44) 异步化；此前在 init 里主线
/// 程同步绘制），update 只改 mask locations 与 glow alpha。
final class StageSweepWordView: UIView {

    let start: TimeInterval
    let end: TimeInterval
    /// 词宽（pt）与字素前缀偏移（与 graphemeTimes 同序）。
    let wordWidth: CGFloat
    private let graphemeTimes: [(start: TimeInterval, end: TimeInterval)]
    private let graphemeOffsets: [CGFloat]
    private let edgeSoftness: CGFloat
    private let rtl: Bool
    /// 逻辑字号（逐词强调上浮量纲，见 tickEmphasis）。
    private let fontPx: CGFloat
    /// 逐词强调弹簧状态（3.7 (50)，与 GlowWord 系同参数）。
    private var emphasisValue: CGFloat = 1
    private var emphasisVelocity: CGFloat = 0
    private var emphasisApplied: CGFloat = 1
    private var lastEmphasisTime: CFTimeInterval = 0

    private let glowViewFar = UIImageView()
    private let glowViewNear = UIImageView()
    private let baseView = UIImageView()
    private let fillView = UIImageView()
    private let fillMask = CAGradientLayer()

    init(start: TimeInterval, end: TimeInterval,
         graphemeTimes: [(start: TimeInterval, end: TimeInterval)],
         images: StageSweepWordImages,
         font: UIFont, glowColor: UIColor,
         isChorus: Bool, boxHeight: CGFloat, rtl: Bool) {
        self.start = start
        self.end = end
        self.graphemeTimes = graphemeTimes
        self.rtl = rtl
        self.graphemeOffsets = images.graphemeOffsets
        self.wordWidth = images.wordWidth
        let fontPx = font.pointSize
        self.fontPx = fontPx
        self.edgeSoftness = min(max(fontPx * 0.45, 6), 16)
        super.init(frame: CGRect(x: 0, y: 0, width: wordWidth, height: boxHeight))
        isUserInteractionEnabled = false
        // Glow：双层 text-shadow 等价——两枚同文图各挂一档
        // shadow 半径（近 0.28/0.45、远 0.65/0.90 ×fontPx），
        // 合成层只动 opacity（网页 glowHalo 同口径）。
        let r1 = (fontPx * (isChorus ? 0.45 : 0.28)).rounded()
        let r2 = (fontPx * (isChorus ? 0.90 : 0.65)).rounded()
        for (glowView, radius) in [(glowViewNear, r1), (glowViewFar, r2)] {
            glowView.image = images.glow
            glowView.frame = bounds
            glowView.layer.shadowColor = glowColor.cgColor
            glowView.layer.shadowOpacity = 1
            glowView.layer.shadowRadius = radius
            glowView.layer.shadowOffset = .zero
            glowView.alpha = 0
            addSubview(glowView)
        }
        baseView.image = images.base
        baseView.frame = bounds
        addSubview(baseView)
        fillView.image = images.fill
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
        tickEmphasis(position: position)
        CATransaction.commit()
    }

    /// 逐词强调（3.7 (50) 莫奈扫字层接入，与 GlowWord 系同口
    /// 径同参数）：弹簧 stiffness 200 / damping 15.5 按墙钟
    /// dt 积分（本视图 update 无 dt 入参，自管上帧时刻，与
    /// GlowWordView 同法）；目标只在唱到本词时非 1——长音按
    /// 词真实时长（YRC 真戳或均分×r，与扫光同一时间轴）爬
    /// 升至约 1.85 带微浪、短词 1.30。合成 = 本视图 transform
    /// （放大 + 上浮）：布局方只写 frame、无人写本视图
    /// transform，不与任何既有动画相争。两点取舍（已定案）：
    /// ①暖金辉光层不做——词图由后台烘焙链以样式色出图，
    /// 再烘一版暖金图须动烘焙链，该链闪退未定案、冻结不
    /// 碰；辉光沿用样式自身包络。②词图为 3 倍率烘焙位图，
    /// 强调峰值缩放期间有瞬时柔化，属位图词视图的固有取
    /// 舍（活字样式无此问题）。
    private func tickEmphasis(position: TimeInterval) {
        let now = CACurrentMediaTime()
        let dt = lastEmphasisTime > 0
            ? min(max(now - lastEmphasisTime, 0), 0.05) : 1.0 / 60
        lastEmphasisTime = now
        var target: CGFloat = 1
        if StageEffectSettings.emphasisEnabledCached(now: now),
           position >= start, position <= end {
            let dur = max(end - start, 0.05)
            let p = CGFloat(min(max((position - start) / dur, 0), 1))
            if dur >= 1.0 {
                target = 1 + 0.85 * pow(p, 0.65)
                    + 0.035 * CGFloat(sin((position - start) * 7.0)) * p
            } else {
                target = 1 + 0.30 * (1 - 0.3 * p)
            }
        }
        let stiffness: CGFloat = 200, damping: CGFloat = 15.5
        let accel = -stiffness * (emphasisValue - target)
            - damping * emphasisVelocity
        emphasisVelocity += accel * CGFloat(dt)
        emphasisValue += emphasisVelocity * CGFloat(dt)
        if abs(emphasisValue - emphasisApplied) > 0.0015
            || abs(emphasisVelocity) > 0.002 {
            emphasisApplied = emphasisValue
            let e = emphasisValue
            if abs(e - 1) > 0.0005 {
                let floatY = -min((e - 1) * fontPx * 1.1, fontPx * 0.8)
                transform = CGAffineTransform(translationX: 0, y: floatY)
                    .scaledBy(x: e, y: e)
            } else {
                transform = .identity
            }
        }
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

    /// 纯测量（无栅格化）：与 configure 同一贪心折行口径，
    /// 只算总高——供调用方在成图未就绪时先占住行盒（3.7
    /// (44) 异步成图的占位高度，与成图后 configure 的返回
    /// 值同源同值，不跳高）。
    static func measureHeight(tokens: [StageSweepToken], font: UIFont,
                              maxWidth: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let widths = tokens.map {
            StageTextKit.graphemeOffsets(text: $0.text, font: font).last ?? 0
        }
        var rows = 0
        var currentWidth: CGFloat = 0
        var rowHasToken = false
        for tokenWidth in widths {
            if rowHasToken && currentWidth + tokenWidth > maxWidth {
                rows += 1
                currentWidth = 0
                rowHasToken = false
            }
            rowHasToken = true
            currentWidth += tokenWidth
        }
        if rowHasToken { rows += 1 }
        return CGFloat(rows) * lineHeight
    }

    /// 配置并完成布局。maxWidth 为行内容宽；lineHeight 为
    /// 单行行高；返回总高（行数 × lineHeight）。成图一律取
    /// prepared（后台 prepareSweepImages 的产物，3.7 (44)），
    /// 本方法只做视图装配，主线程零栅格化。
    @discardableResult
    func configure(tokens: [StageSweepToken], font: UIFont,
                   glowColor: UIColor, isChorus: Bool,
                   maxWidth: CGFloat, lineHeight: CGFloat,
                   rtl: Bool,
                   prepared: [Int: StageSweepWordImages]) -> CGFloat {
        for sub in subviews { sub.removeFromSuperview() }
        wordViews = []
        // 量词宽：取预备产物的实测宽（与成图同一口径）。
        let widths = tokens.indices.map { prepared[$0]?.wordWidth ?? 0 }
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
                    guard let images = prepared[index] else { continue }
                    let word = StageSweepWordView(
                        start: token.start,
                        end: token.end, graphemeTimes: token.graphemeTimes,
                        images: images,
                        font: font, glowColor: glowColor,
                        isChorus: isChorus,
                        boxHeight: lineHeight, rtl: rtl)
                    word.frame = frame
                    addSubview(word)
                    wordViews.append(word)
                } else {
                    let imageView = UIImageView(frame: frame)
                    imageView.image = prepared[index]?.base
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
}
