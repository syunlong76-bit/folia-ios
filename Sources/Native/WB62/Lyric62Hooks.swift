import Foundation

/// (62) WB §4.6：歌词过滤正则。校验在保存时（设置行调
/// validate，非法不落盘）；消费在 LyricParser.stageLines 出
/// 口与 LyricRepository 合并出口（LyricFilter62.apply）。
/// 运行时若落盘值仍非法（旧数据/导入配置），apply 直接原样
/// 返回并落一条面包屑，不吞歌词。
enum LyricFilter62 {

    /// 保存时校验：空串合法（= 不过滤）；非法返回错误描述。
    static func validate(_ pattern: String) -> String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: trimmed)
            return nil
        } catch {
            return "正则不合法：\(error.localizedDescription)"
        }
    }

    private static var compiled: NSRegularExpression? {
        let pattern = SettingsStore.lyricFilterRegex
            .trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: pattern)
    }

    static var isActive: Bool { compiled != nil }

    /// 按行过滤仓库行表：命中正则的行整行剔除。
    static func apply(to lines: [LyricLineData]) -> [LyricLineData] {
        guard let regex = compiled else {
            if !SettingsStore.lyricFilterRegex.isEmpty {
                Breadcrumbs.log("lyric62.filter invalid-pattern passthrough=1")
            }
            return lines
        }
        let kept = lines.filter { line in
            regex.firstMatch(in: line.text,
                             range: NSRange(line.text.startIndex..., in: line.text)) == nil
        }
        if kept.count != lines.count {
            Breadcrumbs.log("lyric62.filter removed=\(lines.count - kept.count) kept=\(kept.count)")
        }
        return kept
    }

    /// 舞台形状行表同口径过滤（LyricParser 出口调用）。
    static func applyToStageLines(_ lines: [LyricLine]) -> [LyricLine] {
        guard let regex = compiled else { return lines }
        return lines.filter { line in
            regex.firstMatch(in: line.text,
                             range: NSRange(line.text.startIndex..., in: line.text)) == nil
        }
    }

    // MARK: - (66) 规则卡＋开头署名块

    /// 预置词表（行首制作人员词）：命中且其后接冒号/间隔符/
    /// 行尾时，该行判为署名形态行。
    static let presetHeads = [
        "作词", "作曲", "编曲", "制作人", "制作", "监制", "演唱",
        "原唱", "翻唱", "和声", "吉他", "贝斯", "鼓手", "键盘",
        "弦乐", "混音", "母带", "录音", "统筹", "策划", "出品",
        "发行", "词", "曲", "编", "OP", "SP", "Lyrics", "Music",
        "Composer", "Arranger", "Producer",
    ]

    private static var customCreditsRegex: NSRegularExpression? {
        let pattern = SettingsStore.lyricCreditsCustom62
            .trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: pattern)
    }

    /// 一行是否呈署名形态（按当前开启的判据：自定义正则 /
    /// 预置词表 / 冒号形态，任一命中即是）。
    static func isCreditLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if let custom = customCreditsRegex,
           custom.firstMatch(in: trimmed,
                             range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        if SettingsStore.lyricFilterPresetWords62 {
            for head in presetHeads where trimmed.hasPrefix(head) {
                let rest = trimmed.dropFirst(head.count)
                if rest.isEmpty || rest.first == "：" || rest.first == ":"
                    || rest.first == " " || rest.first == "、" || rest.first == "·" {
                    return true
                }
            }
        }
        if SettingsStore.lyricFilterColonForm62 {
            // 行首 1...12 字后接全/半角冒号 = 署名形态。
            if let regex = try? NSRegularExpression(
                pattern: "^[^：:\\n]{1,12}[：:]"),
               regex.firstMatch(in: trimmed,
                                range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return true
            }
        }
        return false
    }

    private static func isBlankOrSymbol(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces)
            .allSatisfy { !$0.isLetter && !$0.isNumber }
    }

    /// (66) 全管线处理：署名块处理（开头连续署名行）＋规则
    /// 卡过滤（预置词表/冒号形态/自定义正则；openingOnly 时
    /// 只作用于第一句正式歌词之前）。输入输出为 (时刻, 文本)
    /// 行表，合并行以 mergedText 非 nil 标记（时刻取块首行）。
    struct FilterRow {
        var time: Double
        var text: String
        var mergedText: String? = nil
    }

    static func process66(_ rows: [FilterRow]) -> [FilterRow] {
        guard !rows.isEmpty else { return rows }
        let mode = SettingsStore.lyricCreditsMode62
        let anyRuleOn = SettingsStore.lyricFilterPresetWords62
            || SettingsStore.lyricFilterColonForm62
            || customCreditsRegex != nil
        // 开头署名块界：自首行起连续的署名形态行（absorb 时
        // 把块内相邻的空行/纯符号行并入）。mode != keep 时
        // 块由块处理独占，规则过滤不进块内。
        var blockEnd = 0
        if anyRuleOn {
            while blockEnd < rows.count {
                let row = rows[blockEnd]
                if isCreditLike(row.text) { blockEnd += 1; continue }
                if SettingsStore.lyricCreditsAbsorb62, blockEnd > 0,
                   isBlankOrSymbol(row.text) { blockEnd += 1; continue }
                break
            }
        }
        let blockOwned = mode != "keep" ? blockEnd : 0
        // 1) 规则卡过滤（正则＋预置词表＋冒号形态）：作用域
        //    为块外行；openingOnly 时再限于第一句正式歌词前。
        let openingOnly = SettingsStore.lyricFilterOpeningOnly62
        let firstReal = rows.firstIndex { !isCreditLike($0.text) } ?? rows.count
        let regex = compiled
        var removedCount = 0
        var result: [FilterRow] = []
        for (index, row) in rows.enumerated() {
            if index < blockOwned { result.append(row); continue }
            let inScope = !openingOnly || index < firstReal
            if inScope {
                if let regex,
                   regex.firstMatch(in: row.text,
                                    range: NSRange(row.text.startIndex..., in: row.text)) != nil {
                    removedCount += 1
                    continue
                }
                if (SettingsStore.lyricFilterPresetWords62
                    || SettingsStore.lyricFilterColonForm62),
                   isCreditLike(row.text) {
                    removedCount += 1
                    continue
                }
            }
            result.append(row)
        }
        if removedCount > 0 {
            Breadcrumbs.log("lyric66.rules removed=\(removedCount)")
        }
        // 2) 署名块处理（块在 result 头部、原样保留的行）。
        guard blockOwned > 0 else { return result }
        let minStay = SettingsStore.lyricCreditsMinStay62
        func stay(of index: Int) -> Double {
            index + 1 < rows.count
                ? max(0, rows[index + 1].time - rows[index].time) : 10
        }
        let eligible = (0..<blockOwned).filter { stay(of: $0) >= minStay }
        if mode == "remove" {
            let drop = Set(eligible)
            let kept = result.enumerated().filter { !drop.contains($0.offset) }
                .map { $0.element }
            Breadcrumbs.log("lyric66.credits removed=\(drop.count)")
            return kept
        }
        if mode == "merge", eligible.count > 1 {
            let merged = eligible.map { rows[$0].text
                .trimmingCharacters(in: .whitespaces) }
                .joined(separator: " / ")
            let eligibleSet = Set(eligible)
            var kept: [FilterRow] = []
            for (index, row) in result.enumerated() {
                if index == eligible.first {
                    kept.append(FilterRow(time: row.time, text: row.text,
                                          mergedText: merged))
                } else if eligibleSet.contains(index) {
                    continue
                } else {
                    kept.append(row)
                }
            }
            Breadcrumbs.log("lyric66.credits merged=\(eligible.count)")
            return kept
        }
        return result
    }

    /// (66) 仓库行表全管线（替代/叠加既有 apply 的新入口：
    /// LyricRepository 四处出口改调本函数；默认键位下行为与
    /// 旧 apply 完全一致——正则照旧、其余规则默认关）。
    static func apply66(to lines: [LyricLineData]) -> [LyricLineData] {
        let rows = lines.map { FilterRow(time: $0.time, text: $0.text) }
        let processed = process66(rows)
        if processed.count == lines.count,
           processed.allSatisfy({ $0.mergedText == nil }) {
            // 无结构变化时仍要过一遍旧正则口径的兜底（process66
            // 已含正则过滤，此处只在完全无变化时原样返回）。
            return lines
        }
        var byTime: [Double: LyricLineData] = [:]
        for line in lines where byTime[line.time] == nil { byTime[line.time] = line }
        return processed.map { row in
            if let merged = row.mergedText {
                return LyricLineData(time: row.time, text: merged, words: nil)
            }
            return byTime[row.time] ?? LyricLineData(time: row.time, text: row.text, words: nil)
        }
    }

    /// (66) 舞台行表全管线（LyricParser 出口）。
    static func apply66ToStageLines(_ lines: [LyricLine]) -> [LyricLine] {
        let rows = lines.map { FilterRow(time: $0.start, text: $0.text) }
        let processed = process66(rows)
        if processed.count == lines.count,
           processed.allSatisfy({ $0.mergedText == nil }) {
            return lines
        }
        var byStart: [Double: LyricLine] = [:]
        for line in lines where byStart[line.start] == nil { byStart[line.start] = line }
        return processed.enumerated().map { index, row in
            if let merged = row.mergedText {
                var line = byStart[row.time] ?? lines.first
                    ?? LyricLine(id: index, start: row.time, end: row.time + 1, text: merged)
                line.id = index
                line.text = merged
                line.words = nil
                return line
            }
            var line = byStart[row.time]
                ?? LyricLine(id: index, start: row.time, end: row.time + 1, text: row.text)
            line.id = index
            return line
        }
    }
}

/// (62) WB §4.6 / D8：本地歌词源钩子协议。本地曲库本体归
/// WC——WC 落地本地曲库后把实现注册进
/// `LocalLyricSource62Registry.shared.source`；未注册时钩子
/// 返回 nil、LyricRepository 行为与现行远端链完全一致。
protocol LocalLyricSource62: AnyObject {
    /// 返回该曲的本地歌词原始文本（LRC/YRC 任一，按
    /// SettingsStore.localLyricFormatOrderList 的格式序由实
    /// 现方探文件后给出命中的那一份）；无本地歌词返回 nil。
    func localLyricText(songId: String) -> String?
    /// 本地歌词是否为 YRC 逐字格式（决定解析器）。
    func localLyricIsWordTimed(songId: String) -> Bool
}

final class LocalLyricSource62Registry {
    static let shared = LocalLyricSource62Registry()
    /// WC 注册点（本地曲库子系统初始化时赋值一次）。
    var source: LocalLyricSource62?
    private init() {}
}

/// (62) WB §4.6 / D9：自动 AI 分词客户端框架。
///
/// 协议假设（端点由用户在设置里配置，默认空）：POST JSON
/// `{ "text": String, "start": Double, "end": Double }` →
/// `{ "words": [ { "text": String, "start": Double,
/// "duration": Double } ] }`（时刻为绝对秒，与 LyricWordStamp
/// 同口径）。端点未配置或调用失败时返回 nil，调用方
/// （LyricRepository）回落现有均分＋跨曲标定并落面包屑
/// `aiSegment fallback=local-estimate`——本地估算不冒充 AI。
enum AISegment62 {

    static var isConfigured: Bool {
        SettingsStore.aiSegmentEnabled
            && !SettingsStore.aiSegmentEndpoint
                .trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 对单行无戳歌词请求分词戳；未配置/失败返回 nil。
    static func fetchWords(text: String, start: Double, end: Double) async -> [LyricWordStamp]? {
        guard isConfigured,
              let url = URL(string: SettingsStore.aiSegmentEndpoint
                .trimmingCharacters(in: .whitespaces)) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        let body: [String: Any] = ["text": text, "start": start, "end": end]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawWords = json["words"] as? [[String: Any]] else {
            Breadcrumbs.log("lyric62.aiSegment request-failed text=\(text.prefix(12))")
            return nil
        }
        let words = rawWords.compactMap { raw -> LyricWordStamp? in
            guard let wordText = raw["text"] as? String,
                  let wordStart = (raw["start"] as? NSNumber)?.doubleValue,
                  let wordDuration = (raw["duration"] as? NSNumber)?.doubleValue
            else { return nil }
            return LyricWordStamp(start: wordStart, duration: wordDuration, text: wordText)
        }
        return words.isEmpty ? nil : words
    }
}
