import Foundation

// LRC 解析（舞台用）：产出 LyricStage 协议的 LyricLine 数组。
// 解析规则与墙面展开卡现行口径对齐（WallPrototypeViewController
// .parseLRC）：只认行首 [mm:ss.xx] 首个时间戳、丢空行、按时间
// 升序、丢弃正文开始前的制作名单行。差异仅在输出形状：补 end
// （下一行 start，末行为曲目时长或 start+5 兜底）与稳定行 id。
// 逐字数据无来源，words 恒 nil（协议扩展位）。
enum LyricParser {

    static func parse(_ raw: String, trackDuration: TimeInterval) -> [LyricLine] {
        var rows: [(time: Double, text: String)] = []
        for rawLine in raw.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let stamp = line[line.index(after: line.startIndex)..<close]
            let parts = stamp.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { continue }
            let text = line[line.index(after: close)...]
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            rows.append((time: minutes * 60 + seconds, text: text))
        }
        rows.sort { $0.time < $1.time }
        let body = rows.drop(while: { isCreditLine($0.text) })
        var lines: [LyricLine] = []
        lines.reserveCapacity(body.count)
        for (index, row) in body.enumerated() {
            let next = body.dropFirst(index + 1).first
            let end: TimeInterval
            if let next {
                end = max(next.time, row.time + 0.1)
            } else if trackDuration > row.time {
                end = trackDuration
            } else {
                end = row.time + 5
            }
            lines.append(LyricLine(id: index, start: row.time, end: end, text: row.text))
        }
        return lines
    }

    /// 当前行查找：最后一个 start <= position 的行下标；无歌词或
    /// 尚未开始返回 nil。前奏提前量由调用方决定（展开卡口径 +0.15s）。
    static func currentIndex(in lines: [LyricLine], at position: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var result: Int? = nil
        for (index, line) in lines.enumerated() {
            if line.start <= position { result = index } else { break }
        }
        return result
    }

    // 制作名单行判定：与墙面 isCreditLine 同一份名目表，改动须两处同步。
    private static let creditPrefixes = [
        "作词", "作曲", "编曲", "制作人", "监制", "混音", "母带",
        "录音", "和声", "配唱", "音乐总监", "出品", "发行",
        "统筹", "企划", "演唱", "原唱", "OP", "SP"
    ]

    private static func isCreditLine(_ text: String) -> Bool {
        for prefix in creditPrefixes where text.hasPrefix(prefix) {
            let rest = text.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("：") || rest.hasPrefix(":") { return true }
        }
        let lower = text.lowercased()
        return lower.hasPrefix("lyrics by") || lower.hasPrefix("composed by")
            || lower.hasPrefix("produced by") || lower.hasPrefix("arranged by")
    }
}
