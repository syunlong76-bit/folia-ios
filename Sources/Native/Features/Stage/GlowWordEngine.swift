import UIKit
import QuartzCore

// classic / partita 照搬对齐的共享逐词引擎（3.7 (26)，M2'）：
// 把 folia-major 网页版 GlowWord 的三态机（waiting → active →
// passed）、确定性伪随机姿态（种子 = 行 startTime）、逐字辉光
// 扫光与正文颜色迁移逐项落到 UIKit。数据源口径与网页一致：
// 协议行带逐字戳（YRC 派生）时用真戳；只有行级 LRC 时按网页
// buildLineGraphemeTimeline 的兜底——整行字素在行时长内均分。
// 时钟纪律不变：渲染方只消费宿主 frameTick 喂入的位置，本文件
// 不建任何时钟源。

/// 渲染方根视图：把 layoutSubviews 转给持有它的渲染方排版。
final class LyricStageRootView: UIView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// 舞台字体：网页主题 serif 栈在 iOS 上的落点即 Songti SC；
/// 逐词字重恒 700（resolveThemeFontWeight(theme, 700)）。
enum StageFonts {
    static func bold(size: CGFloat) -> UIFont {
        let font = UIFont(name: "STSongti-SC-Bold", size: size)
            ?? .systemFont(ofSize: size, weight: .bold)
        StageFontBreadcrumb.note(slot: "bold",
                                 requested: "STSongti-SC-Bold",
                                 resolved: font)
        return font
    }
    static func light(size: CGFloat) -> UIFont {
        let font = UIFont(name: "STSongti-SC-Light", size: size)
            ?? .systemFont(ofSize: size, weight: .light)
        StageFontBreadcrumb.note(slot: "light",
                                 requested: "STSongti-SC-Light",
                                 resolved: font)
        return font
    }
}

/// 网页 fract(sin(x) * 10000) 确定性伪随机（classic/partita
/// 布局共用同一公式，保证同行同位姿与网页一致）。
func stageSeededRandom(_ x: Double) -> Double {
    let s = sin(x) * 10000
    return s - floor(s)
}

/// 一个显示单元（词）。逐字戳缺失时的均分兜底见 units(for:)。
struct StageWordUnit {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

enum StageLyricUnits {

    /// 协议行 → 显示单元：有逐字戳用真戳；无戳时按字素切分
    /// （CJK 逐字成单元、拉丁词按空白分词），整行时长按字素
    /// 数均分（与网页无词行时的 even grapheme timing 同口径）。
    static func units(for line: LyricLine) -> [StageWordUnit] {
        if let words = line.words, !words.isEmpty {
            return words.map {
                StageWordUnit(text: $0.text, start: $0.start,
                              end: max($0.end, $0.start + 0.05))
            }
        }
        let tokens = tokenize(line.text)
        guard !tokens.isEmpty else { return [] }
        // 时间份额按整行字素数（含空白）均分，与网页 even
        // grapheme timing 的分母一致。
        let totalGraphemes = max(line.text.count, 1)
        // 演唱跨度压缩（3.7 (43) 路3）：均分跨度乘 r——人声
        // 唱完早于下行 start，行尾气口若摊进每个字，逐字亮
        // 起恒慢（lag 随行内分位线性增长、行尾最重）。压缩
        // 后逐字时刻落在行首起算的演唱窗内，窗尾留白段不再
        // 点亮任何字（扫光停在全亮，正确）。r 由仓库按同曲
        // 有戳行标定、随行下发（line.singingRatio）。
        let ratio = min(max(line.singingRatio, 0.3), 1)
        let span = max((line.end - line.start) * ratio, 0.1)
        return tokens.map { token in
            let start = line.start + span * Double(token.offset) / Double(totalGraphemes)
            let end = line.start + span * Double(token.offset + token.count) / Double(totalGraphemes)
            return StageWordUnit(text: token.text, start: start, end: end)
        }
    }

    /// 切分：CJK/假名/谚文字素逐字成 token；其余连续非空白
    /// 串成 token；空白不产出 token 但推进字素偏移（占份额）。
    private static func tokenize(_ text: String)
        -> [(text: String, offset: Int, count: Int)] {
        var tokens: [(text: String, offset: Int, count: Int)] = []
        var latin = ""
        var latinStart = 0
        var latinCount = 0
        var offset = 0
        func flushLatin() {
            if !latin.isEmpty {
                tokens.append((latin, latinStart, latinCount))
                latin = ""
                latinCount = 0
            }
        }
        for ch in text {
            let s = String(ch)
            if ch == " " || ch == "\t" || ch == "　" {
                flushLatin()
                offset += 1
                continue
            }
            if isCJK(s) {
                flushLatin()
                tokens.append((s, offset, 1))
            } else {
                if latin.isEmpty { latinStart = offset }
                latin += s
                latinCount += 1
            }
            offset += 1
        }
        flushLatin()
        return tokens
    }

    private static func isCJK(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FA5).contains(v) || (0x3040...0x30FF).contains(v)
            || (0xAC00...0xD7AF).contains(v)
    }

    // MARK: 语义分组（(57) C1b 纯新增 API；既有 units(for:) 等
    // 既有函数一字未动）
    //
    // 网页 partita 恒以 { semantic: tuning.useSemanticLayout,
    // sticky: true } 调 buildPostLyricLayoutUnits
    // （cjkSemanticLayout.ts）：semantic 开时先按词分段
    // （segmentLyricWords → Intl.Segmenter）把解析词编成语义
    // 布局组，再做标点/缩约粘连（applyStickyPunctuation），
    // 最后 buildDisplayWordsFromLayoutUnits 派生显示词——
    // 语义组保留组内原词逐个显示（逐字时序不丢），粘连的
    // 非语义组才合并成一个显示词。本 API 同构：先经既有
    // units(for:) 取显示单元（时序来源与口径一字不变），再
    // 把单元编成布局组返回；组即网页 LyricLayoutUnit 的边
    // 界，消费方只许在组界切分。分段与单元文本对不齐时整
    // 行回退单元素组（网页 mapSegmentsToWords 返回 nil →
    // createSingleWordLayoutUnits 同义），粘连照常在其上做。
    // 已知数据源差异：原生 LyricLine 无 wordSegments /
    // autoWordSegments 字段（协议冻结面），用户保存分词与
    // icu-folia 预分词无从下发，故分段只走系统词界
    // （NSString.enumerateSubstrings .byWords，ICU 词界，
    // 与 Intl.Segmenter 同源；词典版本可致个别边界出入，
    // 出入只影响分组、不影响时序，且有整行回退兜底）。

    /// 语义布局组：一项 = 一个布局组（网页一个
    /// LyricLayoutUnit 的显示单元集，组内顺序 = 原单元序，
    /// 全组单元拼接与 units(for:) 输出同序同值）。
    static func semanticGroups(for line: LyricLine) -> [[StageWordUnit]] {
        let base = units(for: line)
        guard !base.isEmpty else { return [] }
        var groups = base.map {
            SemanticGroup(text: $0.text, units: [$0], isSemantic: false)
        }
        // 网页 CJK 闸门：fullText 无 CJK 且无用户分词覆盖时
        // 语义分组恒回退单词单元（原生无覆盖数据源，只判
        // CJK）；非 CJK 行跳过分段、粘连仍照常（拉丁缩约）。
        if line.text.contains(where: { isCJK(String($0)) }),
           let mapped = mapSemanticSegments(base: base, text: line.text) {
            groups = mapped
        }
        return applyStickyPunctuation(groups).map { group in
            // buildDisplayWordsFromLayoutUnits：粘连的非语义
            // 组合并成一个显示单元（文本 = 组内原文拼接、
            // 时段 = 首尾单元时段）；其余组原样返回组内单元。
            if group.isSticky, !group.isSemantic,
               let first = group.units.first, let last = group.units.last {
                return [StageWordUnit(text: group.text,
                                      start: first.start, end: last.end)]
            }
            return group.units
        }
    }

    /// 网页 LyricLayoutUnit 的原生镜像（仅本组 API 内部用）。
    private struct SemanticGroup {
        var text: String
        var units: [StageWordUnit]
        var isSemantic: Bool
        var isSticky: Bool = false
    }

    /// 系统词分段（wordSegmentation.segmentTextWords 的原生
    /// 落点）：.byWords 枚举全文（词/标点/空白各自成段），
    /// isWordLike = 段内含字母或数字（网页回退口径
    /// !/^[\s\p{P}\p{S}]+$/ 的等价判据）。
    private static func wordSegments(of text: String)
        -> [(segment: String, isWordLike: Bool)] {
        var result: [(segment: String, isWordLike: Bool)] = []
        let ns = text as NSString
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: [.byWords]) { substring, range, _, _ in
            let segment = substring ?? ns.substring(with: range)
            let wordLike = segment.unicodeScalars.contains {
                CharacterSet.alphanumerics.contains($0)
            }
            result.append((segment: segment, isWordLike: wordLike))
        }
        return result
    }

    /// mapSegmentsToWords 逐项对应：空白剥离后精确对齐，
    /// 任一段对不上返回 nil（整行回退）；空白-only 单元并
    /// 入前组（行首的并入首段）；非词段并入前组；语义标记
    /// = 词段 && 含 CJK && 非空单元数 > 1。
    private static func mapSemanticSegments(base: [StageWordUnit],
                                            text: String)
        -> [SemanticGroup]? {
        let segments = wordSegments(of: text)
        guard !segments.isEmpty else { return nil }
        func strip(_ s: String) -> String {
            s.filter { !$0.isWhitespace }
        }
        var groups: [SemanticGroup] = []
        var index = 0
        func absorbWhitespace() {
            guard !groups.isEmpty else { return }
            while index < base.count, strip(base[index].text).isEmpty {
                groups[groups.count - 1].text += base[index].text
                groups[groups.count - 1].units.append(base[index])
                index += 1
            }
        }
        for segment in segments {
            let key = strip(segment.segment)
            if key.isEmpty { continue }
            absorbWhitespace()
            let startIndex = index
            var collected = ""
            while index < base.count, collected.count < key.count {
                collected += strip(base[index].text)
                index += 1
                if !key.hasPrefix(collected) { return nil }
            }
            if collected != key { return nil }
            let segUnits = Array(base[startIndex..<index])
            guard !segUnits.isEmpty else { return nil }
            let segText = segUnits.map { $0.text }.joined()
            if !segment.isWordLike, !groups.isEmpty {
                groups[groups.count - 1].text += segText
                groups[groups.count - 1].units.append(contentsOf: segUnits)
                continue
            }
            let glyphCount = segUnits.filter { !strip($0.text).isEmpty }.count
            let semantic = segment.isWordLike
                && segText.contains(where: { isCJK(String($0)) })
                && glyphCount > 1
            groups.append(SemanticGroup(text: segText, units: segUnits,
                                        isSemantic: semantic))
        }
        absorbWhitespace()
        if index != base.count || groups.isEmpty { return nil }
        return groups
    }

    // MARK: 标点/缩约粘连（applyStickyPunctuationLayoutUnits 对应）

    private static let contractionSuffixes: Set<String> =
        ["s", "t", "m", "d", "ll", "re", "ve", "em"]
    /// STICKY_TRAILING_PUNCTUATION_REGEX 的字符集逐字转录。
    private static let stickyPunctuationChars: Set<Character> = [
        ",", ".", ";", ":", "!", "?",
        "，", "。", "！", "？", "、", "：", "；",
        "）", "】", "》", "」", "『", "〉", "〕", "］",
        ")", "}", "]", "\"", "'", "’", "”",
    ]

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimEnd(_ s: String) -> String {
        var t = s
        while let last = t.last, last.isWhitespace { t.removeLast() }
        return t
    }

    private static func isApostropheOnly(_ text: String) -> Bool {
        let t = trimmed(text)
        return t == "'" || t == "’"
    }

    private static func isContractionSuffix(_ text: String) -> Bool {
        contractionSuffixes.contains(trimmed(text).lowercased())
    }

    private static func isDirectContraction(_ text: String) -> Bool {
        let t = trimmed(text)
        guard let first = t.first, first == "'" || first == "’"
        else { return false }
        return contractionSuffixes.contains(
            String(t.dropFirst()).lowercased())
    }

    private static func isStickyTrailingPunctuation(_ text: String) -> Bool {
        let t = trimmed(text)
        return !t.isEmpty && t.allSatisfy { stickyPunctuationChars.contains($0) }
    }

    /// canAttachToPrevious：trimEnd 后末字为字母/数字。
    private static func canAttachToPrevious(_ text: String) -> Bool {
        guard let last = trimEnd(text).unicodeScalars.last else { return false }
        return CharacterSet.alphanumerics.contains(last)
    }

    private static func endsWithApostrophe(_ text: String) -> Bool {
        guard let last = trimEnd(text).last else { return false }
        return last == "'" || last == "’"
    }

    /// INLINE_CONTRACTION_REGEX 的存在性扫描：撇号前有字母/
    /// 数字、后接缩约后缀之一（与网页正则同为不锚尾的宽松
    /// 匹配，交替序 s|t|m|d|ll|re|ve|em）。
    private static func hasInlineContraction(_ text: String) -> Bool {
        let chars = Array(text)
        for i in chars.indices where chars[i] == "'" || chars[i] == "’" {
            guard i > 0,
                  let prev = chars[i - 1].unicodeScalars.last,
                  CharacterSet.alphanumerics.contains(prev)
            else { continue }
            let rest = String(chars[(i + 1)...]).lowercased()
            for suffix in ["s", "t", "m", "d", "ll", "re", "ve", "em"]
            where rest.hasPrefix(suffix) { return true }
        }
        return false
    }

    private static func applyStickyPunctuation(_ input: [SemanticGroup])
        -> [SemanticGroup] {
        var merged: [SemanticGroup] = []
        func appendToPrevious(_ group: SemanticGroup) {
            let last = merged.count - 1
            merged[last].text += group.text
            merged[last].units.append(contentsOf: group.units)
            merged[last].isSticky = true
        }
        var index = 0
        while index < input.count {
            let current = input[index]
            guard !merged.isEmpty else {
                merged.append(current)
                index += 1
                continue
            }
            let previousText = merged[merged.count - 1].text
            let next = index + 1 < input.count ? input[index + 1] : nil
            // 撇号独元 + 缩约后缀：三元一并粘（It | ’ | s）。
            if isApostropheOnly(current.text), let next,
               canAttachToPrevious(previousText),
               isContractionSuffix(next.text) {
                appendToPrevious(current)
                appendToPrevious(next)
                index += 2
                continue
            }
            if isDirectContraction(current.text),
               canAttachToPrevious(previousText) {
                appendToPrevious(current)
                index += 1
                continue
            }
            if isContractionSuffix(current.text),
               endsWithApostrophe(previousText) {
                appendToPrevious(current)
                index += 1
                continue
            }
            if isStickyTrailingPunctuation(current.text),
               canAttachToPrevious(previousText) {
                appendToPrevious(current)
                index += 1
                continue
            }
            merged.append(current)
            index += 1
        }
        // 收尾标记：末元为粘性标点、或组内含内联缩约 →
        // isSticky（网页 hasAttachedTrailingPunctuation /
        // hasInlineContraction 的 map 标记步）。
        return merged.map { group in
            var group = group
            let hasTrailing = group.units.count > 1
                && isStickyTrailingPunctuation(group.units.last?.text ?? "")
            let hasInline = group.units.count > 1 && !group.isSemantic
                && hasInlineContraction(group.text)
            if hasTrailing || hasInline { group.isSticky = true }
            return group
        }
    }
}

/// 词姿态（网页 WordLayoutConfig 的几何子集，单位 pt/度）。
struct StageWordPose {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotate: CGFloat = 0        // 度
    var scale: CGFloat = 1
    var passedRotate: CGFloat = 0  // 度
}

/// 行时序模式（网页 renderHints：按行时长分级，真实歌词行
/// 几乎恒为 normal；fast/instant 只在亚 0.18s 行出现）。
struct StageLineProfile {
    var wordLookahead: TimeInterval
    /// 辉光阴影半径（pt）：网页 text-shadow 半径 [内, 外] 按
    /// drop-shadow 拟合系数 0.4 折算后取双层等效单值。
    var glowRadius: CGFloat

    static func profile(for line: LyricLine) -> StageLineProfile {
        let duration = line.end - line.start
        if duration < 0.10 {   // micro → instant，半径 [14, 24]
            return StageLineProfile(wordLookahead: 0.03, glowRadius: 8)
        }
        if duration < 0.18 {   // short → fast，半径 [18, 32]
            return StageLineProfile(wordLookahead: 0.08, glowRadius: 11)
        }
        // normal，半径 [20, 40]
        return StageLineProfile(wordLookahead: 0.15, glowRadius: 12)
    }
}

/// 逐词视图：正文层（颜色/状态）+ 辉光层（逐字素标签，靠
/// CALayer 阴影出光晕，与网页 drop-shadow 拟合口径同向）。
/// 状态迁移只由 update(position:) 驱动；动画参数对网页
/// framer-motion variants：入场弹簧 stiffness 200 / damping
/// 20（ζ≈0.707）、passed 0.5s、正文回色 0.8s、辉光淡出 0.9s。
final class GlowWordView: UIView {

    enum Status { case waiting, active, passed }

    let unit: StageWordUnit
    var pose: StageWordPose
    private(set) var status: Status = .waiting

    private let font: UIFont
    private let baseColor: UIColor
    private let activeColor: UIColor
    private let profile: StageLineProfile
    /// 超采样倍率（3.7 (47) 清晰度修复）：UILabel 活字由
    /// 图层按 bounds×屏幕倍率栅格化，active 姿态 transform
    /// （pose.scale×1.4，云阶最高 2.38）一放大就软。本视图
    /// 改为内部按 renderScale 倍字号/几何构建、再由内容容
    /// 器反向缩放回逻辑尺寸——栅格像素恒 ≥ 最大显示尺寸，
    /// 姿态、弹簧与时序参数一字不动。renderScale 按本词
    /// pose 的最大放大推导（×1.4 active 系数 ×1.1 弹簧过
    /// 冲/容器余量，0.25 档进位，上限 3，下限 1 时直通）。
    private let renderScale: CGFloat
    private let contentView = UIView()
    private let bodyLabel = UILabel()
    private let glowContainer = UIView()
    private var glowLabels: [UILabel] = []
    private var graphemeSpans: [(start: TimeInterval, end: TimeInterval)] = []
    /// 逐词强调辉光（3.7 (49)）：暖金色同文标签，垫在正文
    /// 之下，alpha 由强调弹簧值驱动（见 tickEmphasis）。
    private let emphasisGlowLabel = UILabel()
    /// 强调弹簧状态（stiffness 200 / damping 15.5 积分值）。
    private var emphasisValue: CGFloat = 1
    private var emphasisVelocity: CGFloat = 0
    private var emphasisApplied: CGFloat = 1
    private var lastEmphasisTime: CFTimeInterval = 0

    /// active 段终点（normal 模式 = 词 end）。
    private var activeEnd: TimeInterval { unit.end }
    private var displayDuration: TimeInterval {
        max(activeEnd - unit.start, 0.1)
    }

    init(unit: StageWordUnit, pose: StageWordPose, font: UIFont,
         baseColor: UIColor, activeColor: UIColor, profile: StageLineProfile) {
        self.unit = unit
        self.pose = pose
        self.font = font
        self.baseColor = baseColor
        self.activeColor = activeColor
        self.profile = profile
        // (49) 余量口径：逐词强调开启时，强调放大叠在姿态
        // 之上——长音词最高 ≈1.85、短词弹簧峰值 ≈1.38，
        // 栅格余量按词时长分档、上限放宽到 4，保证强调放
        // 大后清晰度不退回 (47) 前；关时维持 (47) 原口径
        // （×1.1、上限 3），关掉开关即回 (48) 观感。
        let emphasisOn = StageEffectSettings.wordEmphasisEnabled
        let headroom: CGFloat = emphasisOn
            ? ((unit.end - unit.start) >= 1.0 ? 1.9 : 1.38) : 1.1
        // (62) WB §4.4：全局歌词画布分辨率档位叠加本词超采
        // 样推导（上限仍受下方 3/4 封顶约束，逐样式上限优先）。
        let rawScale = pose.scale * 1.4 * headroom * (emphasisOn ? 1.03 : 1)
            * LyricCanvas62.globalScale
        self.renderScale = rawScale <= 1.05
            ? 1 : min(emphasisOn ? 4 : 3, ceil(rawScale * 4) / 4)
        super.init(frame: .zero)

        // 内部几何全在 renderScale 倍空间构建（字号、坐标、
        // 阴影半径同倍），内容容器反向缩放回逻辑尺寸。
        let r = renderScale
        let rFont = font.withSize(font.pointSize * r)
        bodyLabel.text = unit.text
        bodyLabel.font = rFont
        bodyLabel.textColor = baseColor
        bodyLabel.textAlignment = .center
        bodyLabel.layer.shadowColor = UIColor.black.cgColor
        bodyLabel.layer.shadowOpacity = 0.45
        bodyLabel.layer.shadowRadius = 3 * r
        bodyLabel.layer.shadowOffset = .zero
        bodyLabel.sizeToFit()

        // 辉光层：逐字素一标签，与正文同字同宽，靠阴影出晕；
        // 字素时刻按词内均分（网页 buildWordGraphemeTimings
        // 无音节数据时的 even 口径）。
        let graphemes = unit.text.map { String($0) }
        let span = max(unit.end - unit.start, 0.05)
        var gx: CGFloat = 0
        for (index, g) in graphemes.enumerated() {
            let label = UILabel()
            label.text = g
            label.font = rFont
            label.textColor = activeColor
            label.layer.shadowColor = activeColor.cgColor
            label.layer.shadowOpacity = 1
            label.layer.shadowRadius = profile.glowRadius * r
            label.layer.shadowOffset = .zero
            label.sizeToFit()
            label.frame.origin = CGPoint(x: gx, y: 0)
            gx += label.bounds.width
            glowLabels.append(label)
            glowContainer.addSubview(label)
            let gStart = unit.start + span * Double(index) / Double(max(graphemes.count, 1))
            let gEnd = unit.start + span * Double(index + 1) / Double(max(graphemes.count, 1))
            graphemeSpans.append((gStart, gEnd))
        }
        glowContainer.frame = CGRect(
            x: 0, y: 0, width: gx, height: bodyLabel.bounds.height)
        glowContainer.alpha = 0
        glowContainer.isUserInteractionEnabled = false

        // 强调辉光标签（3.7 (49)）：与正文同字同宽，暖金
        // 色＋大半径同色阴影，alpha 恒由强调值驱动（静止
        // 时为 0）；颜色不取样式 accent，AMLL 口径恒暖金。
        emphasisGlowLabel.text = unit.text
        emphasisGlowLabel.font = rFont
        emphasisGlowLabel.textAlignment = .center
        let warmGold = UIColor(red: 1.0, green: 0.76, blue: 0.32, alpha: 1)
        emphasisGlowLabel.textColor = warmGold
        emphasisGlowLabel.layer.shadowColor = warmGold.cgColor
        emphasisGlowLabel.layer.shadowOpacity = 1
        emphasisGlowLabel.layer.shadowRadius = 16 * r
        emphasisGlowLabel.layer.shadowOffset = .zero
        emphasisGlowLabel.sizeToFit()
        emphasisGlowLabel.alpha = 0
        emphasisGlowLabel.isUserInteractionEnabled = false

        let widthR = max(bodyLabel.bounds.width, gx)
        let heightR = bodyLabel.bounds.height
        bodyLabel.frame = CGRect(
            x: (widthR - bodyLabel.bounds.width) / 2, y: 0,
            width: bodyLabel.bounds.width, height: heightR)
        emphasisGlowLabel.frame = CGRect(
            x: (widthR - emphasisGlowLabel.bounds.width) / 2, y: 0,
            width: emphasisGlowLabel.bounds.width, height: heightR)
        glowContainer.frame.origin = CGPoint(x: (widthR - gx) / 2, y: 0)
        let width = widthR / r
        let height = heightR / r
        contentView.bounds = CGRect(x: 0, y: 0, width: widthR, height: heightR)
        contentView.center = CGPoint(x: width / 2, y: height / 2)
        if r != 1 {
            contentView.transform = CGAffineTransform(scaleX: 1 / r, y: 1 / r)
        }
        contentView.isUserInteractionEnabled = false
        contentView.addSubview(glowContainer)
        contentView.addSubview(emphasisGlowLabel)
        contentView.addSubview(bodyLabel)
        addSubview(contentView)
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        isUserInteractionEnabled = false
        applyWaitingPose(animated: false)
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 姿态

    private func transform(for status: Status) -> CGAffineTransform {
        switch status {
        case .waiting:
            // 网页 waiting：scale 0.5、rotate +20°、位置带
            // sin/cos 漂移（入参为姿态 x/y 本值，逐字照搬）。
            let driftX = pose.x + CGFloat(sin(Double(pose.y))) * 100
            let driftY = pose.y + CGFloat(cos(Double(pose.x))) * 50
            return CGAffineTransform(translationX: driftX, y: driftY)
                .rotated(by: (pose.rotate + 20) * .pi / 180)
                .scaledBy(x: 0.5, y: 0.5)
        case .active:
            return CGAffineTransform(translationX: pose.x, y: pose.y)
                .rotated(by: pose.rotate * .pi / 180)
                .scaledBy(x: pose.scale * 1.4, y: pose.scale * 1.4)
        case .passed:
            return CGAffineTransform(translationX: pose.x, y: pose.y)
                .rotated(by: (pose.rotate + pose.passedRotate) * .pi / 180)
                .scaledBy(x: pose.scale, y: pose.scale)
        }
    }

    private func applyWaitingPose(animated: Bool) {
        let apply = { self.transform = self.transform(for: .waiting) }
        if animated {
            UIView.animate(withDuration: 0.4, animations: apply)
        } else { apply() }
    }

    // MARK: 状态驱动

    /// 每帧调用：按位置算目标状态，变化时才跑迁移；
    /// 逐词强调弹簧每帧都积分（见 tickEmphasis）。
    func update(position: TimeInterval) {
        let target: Status
        if position < unit.start - profile.wordLookahead {
            target = .waiting
        } else if position <= activeEnd {
            target = .active
        } else {
            target = .passed
        }
        if target != status { transition(to: target) }
        tickEmphasis(position: position)
    }

    // MARK: 逐词强调（3.7 (49)）

    /// AMLL emphasize 的原生落点（借概念与弹簧参数，实
    /// 现自研）：唱到的词放大＋暖金辉光＋上浮，长音词随
    /// 音长持续膨胀带正弦微浪，唱完弹簧缓落。弹簧
    /// stiffness 200 / damping 15.5（ζ≈0.55，带过冲）在
    /// 本函数内按帧积分。数据源纪律：unit 的 start/end
    /// 即扫光链同一时间轴（YRC 真戳或 (46) 跨曲学习 r
    /// 分布），本层不另建分布、不重排布局、不动扫光
    /// x 轴——变换只落在内容容器上，与状态姿态 transform
    /// 分层合成；栅格余量已在 init 按词时长预留（见
    /// renderScale 口径），放大后不回软。
    private func tickEmphasis(position: TimeInterval) {
        let now = CACurrentMediaTime()
        let dt = lastEmphasisTime > 0
            ? min(max(now - lastEmphasisTime, 0), 0.05) : 1.0 / 60
        lastEmphasisTime = now
        var target: CGFloat = 1
        if StageEffectSettings.emphasisEnabledCached(now: now),
           status == .active {
            let dur = max(unit.end - unit.start, 0.05)
            let p = CGFloat(min(max((position - unit.start) / dur, 0), 1))
            if dur >= 1.0 {
                // 长音：目标随演唱进度爬升至 ≈1.85（样片
                // 定档），微浪 ±0.035 随进度渐入。
                target = 1 + 0.85 * pow(p, 0.65)
                    + 0.035 * CGFloat(sin((position - unit.start) * 7.0)) * p
            } else {
                // 短词：1.30 定档（样片 1+0.30e），词尾轻收。
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
            applyEmphasis()
        }
    }

    private func applyEmphasis() {
        emphasisApplied = emphasisValue
        let e = emphasisValue
        var transform = CGAffineTransform(
            scaleX: 1 / renderScale, y: 1 / renderScale)
        if abs(e - 1) > 0.0005 {
            // 上浮与字号成比例：e=1.30 时 ≈17pt@50pt 字
            // （样片定档），上限 0.8 倍字号防长音飘太远。
            let floatY = -min((e - 1) * font.pointSize * 1.1,
                              font.pointSize * 0.8)
            let emphasis = CGAffineTransform(translationX: 0, y: floatY)
                .scaledBy(x: e, y: e)
            transform = transform.concatenating(emphasis)
        }
        contentView.transform = transform
        emphasisGlowLabel.alpha = min(max((e - 1) / 0.85, 0), 1) * 0.9
    }

    /// 构建后立即按当前位定格（中途进台/seek 落位）：不跑
    /// 入场动画，直接摆到目标姿态；active 的辉光照常起。
    func snap(position: TimeInterval) {
        let target: Status
        if position < unit.start - profile.wordLookahead {
            target = .waiting
        } else if position <= activeEnd {
            target = .active
        } else {
            target = .passed
        }
        status = target
        layer.removeAllAnimations()
        bodyLabel.layer.removeAllAnimations()
        glowContainer.layer.removeAllAnimations()
        // 强调弹簧同步复位（seek/中途进台不带残留膨胀）。
        emphasisValue = 1
        emphasisVelocity = 0
        lastEmphasisTime = 0
        applyEmphasis()
        transform = transform(for: target)
        switch target {
        case .waiting:
            alpha = 0
            bodyLabel.textColor = baseColor
            glowContainer.alpha = 0
        case .active:
            alpha = 1
            bodyLabel.textColor = activeColor
            startGlow()
        case .passed:
            alpha = 0.82
            bodyLabel.textColor = baseColor
            glowContainer.alpha = 0
        }
    }

    private func transition(to target: Status) {
        status = target
        switch target {
        case .waiting:
            layer.removeAllAnimations()
            glowContainer.layer.removeAllAnimations()
            UIView.animate(withDuration: 0.4) {
                self.transform = self.transform(for: .waiting)
                self.alpha = 0
            }
            bodyLabel.textColor = baseColor
            glowContainer.alpha = 0
        case .active:
            // 入场弹簧（网页 stiffness 200 / damping 20）；
            // 不透明度单独 0.1s（网页 opacity 子过渡）。
            UIView.animate(withDuration: 0.55, delay: 0,
                           usingSpringWithDamping: 0.707,
                           initialSpringVelocity: 0,
                           options: [.beginFromCurrentState]) {
                self.transform = self.transform(for: .active)
            }
            UIView.animate(withDuration: 0.1) { self.alpha = 1 }
            // 激活色交叉淡化 0.2s → 0.1s（3.7 (44) 呈现层迟滞
            // 审计）：wordLookahead 仅 0.03–0.15s，吸收不全
            // 0.2s 淡化——词到点后全色恒晚 50–170ms。缩半后
            // 净拖尾 ≤70ms，仍保留一帧级柔和上色不硬切。
            UIView.transition(with: bodyLabel, duration: 0.1,
                              options: .transitionCrossDissolve) {
                self.bodyLabel.textColor = self.activeColor
            }
            startGlow()
        case .passed:
            UIView.animate(withDuration: 0.5, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) {
                self.transform = self.transform(for: .passed)
                self.alpha = 0.82
            }
            UIView.transition(with: bodyLabel, duration: 0.8,
                              options: .transitionCrossDissolve) {
                self.bodyLabel.textColor = self.baseColor
            }
            if graphemeSpans.count <= 1 {
                UIView.animate(withDuration: 0.9) { self.glowContainer.alpha = 0 }
            }
        }
    }

    /// 辉光起动：单字素 = 持续辉（随词时长爬升到峰值，网页
    /// peaks [0,1,1] / times [0,0.9,1]）；多字素 = 逐字扫光
    /// （每字素辉光时长 = 字素时长 ×6、峰值在 30% 处）。
    private func startGlow() {
        glowContainer.layer.removeAllAnimations()
        if graphemeSpans.count <= 1 {
            glowContainer.alpha = 0
            UIView.animate(withDuration: displayDuration * 0.9,
                           delay: 0, options: [.curveEaseInOut]) {
                self.glowContainer.alpha = 1
            }
            return
        }
        glowContainer.alpha = 1
        for (index, label) in glowLabels.enumerated() {
            let span = graphemeSpans[index]
            let charDuration = max(span.end - span.start, 0.001)
            let delay = max(0, span.start - unit.start)
            label.layer.removeAllAnimations()
            label.alpha = 0
            UIView.animateKeyframes(withDuration: charDuration * 6, delay: delay,
                                    options: [.beginFromCurrentState]) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.3) {
                    label.alpha = 1
                }
                UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.7) {
                    label.alpha = 0
                }
            }
        }
    }
}

/// 整行呼吸浮动（网页 lyricContainerFloat，normal 强度档）：
/// y [0, −14, 0, +6.3, 0]、scale [1, 1.01, 1, 0.995, 1]，
/// 7s easeInOut 无限循环。挂在行容器外层，与行进出场动画
/// 分层互不干扰。
enum StageBreathingFloat {
    private static let key = "stage.breathingFloat"

    static func start(on view: UIView) {
        guard view.layer.animation(forKey: key) == nil else { return }
        let duration: CFTimeInterval = 7
        let ys: [CGFloat] = [0, -14, 0, 6.3, 0]
        let scales: [CGFloat] = [1, 1.01, 1, 0.995, 1]
        var transforms: [CATransform3D] = []
        for i in ys.indices {
            var t = CATransform3DMakeTranslation(0, ys[i], 0)
            t = CATransform3DScale(t, scales[i], scales[i], 1)
            transforms.append(t)
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = transforms.map { NSValue(caTransform3D: $0) }
        animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        animation.isRemovedOnCompletion = false
        view.layer.add(animation, forKey: key)
    }

    static func stop(on view: UIView) {
        view.layer.removeAnimation(forKey: key)
    }
}
