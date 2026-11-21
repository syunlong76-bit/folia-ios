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
