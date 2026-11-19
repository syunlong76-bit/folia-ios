import Foundation

/// 歌词共享仓库（3.7 (23)，DS R49 Q3 对账）：API 客户端层的
/// 单一歌词缓存——墙面展开卡 / 原生舞台 / Web 详情桥此前各
/// 自 fetchLyric、互不共享：同一首歌墙面取过后开舞台还要再
/// 向 EdgeOne 现拉一次（真机约 3s「暂无歌词」，audit-3723
/// §5.2）；舞台实例级缓存随实例生灭、每次开台必重付。
///
/// 口径：
/// - 键 = songId；值 = 解析后行表（墙面合并表 LyricLineData，
///   舞台经 LyricParser.stageLines 派生）+ 原始 LRC 文本
///   （Web 桥的快照 lrc 字段用）。
/// - 取数链与墙面 (20) 口径逐字一致：先 /lyric/new 双表合并
///   （LyricParsing.mergeLyricLines），失败回落 /lyric LRC；
///   两路皆空/皆失败 = 负结果。
/// - 策略（R49 拍板）：内存 LRU 64 首或估算 8MB 取小者；
///   正缓存会话内 30 分钟；负缓存 5 分钟（到期可重试，不再
///   像旧 VC 缓存那样把空结果钉死一整个会话）；同 songId
///   并发请求合并为一次在途 Task。磁盘持久化本轮不做。
final class LyricRepository {

    static let shared = LyricRepository()

    struct Entry {
        /// 合并后行表（翻行源由 LyricTiming.flipSource 决定，
        /// 现行默认 LRC 时刻 + YRC 逐字扫光）。
        let lines: [LyricLineData]
        /// 原始 LRC 文本（bundle 路径取 bundle.lrc，回落路径
        /// 取 /lyric 原文；负结果为空串）。
        let lrcText: String
        /// 来源标记（面包屑对账用）：lrc+yrc / lrc / yrc /
        /// lrc-fallback / none。
        let source: String
        /// 实际翻行源标记：lrc / yrc。
        let flip: String
        /// 负结果（无歌词/取数失败）：lines 为空、短 TTL。
        let isNegative: Bool
        let fetchedAt: Date
        /// LRU 内存估算（文本 UTF-16 字节 + 逐字戳开销）。
        let estimatedBytes: Int
    }

    private static let maxEntries = 64
    private static let maxBytes = 8 * 1024 * 1024
    private static let positiveTTL: TimeInterval = 30 * 60
    private static let negativeTTL: TimeInterval = 5 * 60

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    /// LRU 顺序（最久未用在前）：命中与写入都把 key 挪到末尾。
    private var lruOrder: [String] = []
    private var totalBytes = 0
    private var inFlight: [String: Task<Entry, Never>] = [:]

    private init() {}

    // MARK: - 同步读（墙面逐帧 tick 用）

    /// 已缓存且未过期的条目；未命中/已过期返回 nil（过期即
    /// 淘汰）。负条目在 5 分钟内同样返回（lines 为空），调用
    /// 方据此不再重复发起请求。
    func cachedEntry(for songId: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[songId] else { return nil }
        let ttl = entry.isNegative ? Self.negativeTTL : Self.positiveTTL
        guard Date().timeIntervalSince(entry.fetchedAt) < ttl else {
            removeLocked(songId)
            return nil
        }
        touchLocked(songId)
        return entry
    }

    // MARK: - 异步取（舞台/桥/墙面预取用）

    /// 缓存命中直接返回；未命中走在途合并——同 songId 并发
    /// 只发一次网络请求，其余调用方等同一个 Task。
    func entry(for songId: String) async -> Entry {
        if let hit = cachedEntry(for: songId) { return hit }
        lock.lock()
        if let existing = inFlight[songId] {
            lock.unlock()
            return await existing.value
        }
        let task = Task<Entry, Never> { [weak self] in
            guard let self else {
                return Entry(lines: [], lrcText: "", source: "none",
                             flip: "lrc", isNegative: true,
                             fetchedAt: Date(), estimatedBytes: 0)
            }
            let fetched = await self.fetch(songId: songId)
            self.store(fetched, for: songId)
            self.lock.lock()
            self.inFlight[songId] = nil
            self.lock.unlock()
            return fetched
        }
        inFlight[songId] = task
        lock.unlock()
        return await task.value
    }

    // MARK: - 取数（与墙面 (20) ensureLyrics 同链）

    private func fetch(songId: String) async -> Entry {
        var parsed: [LyricLineData] = []
        var source = "none"
        var flip = "lrc"
        var lrcText = ""
        if let bundle = try? await EdgeOneAPIClient.shared.fetchLyricBundle(songId: songId) {
            lrcText = bundle.lrc
            let merged = LyricParsing.mergeLyricLines(
                lrcLines: LyricParsing.parseLRC(bundle.lrc),
                yrcLines: bundle.yrc.map(LyricParsing.parseYRC) ?? [])
            parsed = merged.lines
            source = merged.source
            flip = merged.flip
        } else if let text = try? await EdgeOneAPIClient.shared.fetchLyricText(songId: songId) {
            lrcText = text
            parsed = LyricParsing.parseLRC(text)
            source = parsed.isEmpty ? "none" : "lrc-fallback"
            flip = "lrc"
        }
        let bytes = Self.estimateBytes(lines: parsed, lrcText: lrcText)
        return Entry(lines: parsed, lrcText: lrcText, source: source,
                     flip: flip, isNegative: parsed.isEmpty,
                     fetchedAt: Date(), estimatedBytes: bytes)
    }

    private static func estimateBytes(lines: [LyricLineData], lrcText: String) -> Int {
        var total = lrcText.utf16.count * 2 + 256
        for line in lines {
            total += line.text.utf16.count * 2 + 64
            if let words = line.words {
                for word in words { total += word.text.utf16.count * 2 + 48 }
            }
        }
        return total
    }

    // MARK: - 存储与 LRU（lock 内部版要求已持锁）

    private func store(_ entry: Entry, for songId: String) {
        lock.lock()
        defer { lock.unlock() }
        if let old = cache[songId] { totalBytes -= old.estimatedBytes }
        cache[songId] = entry
        totalBytes += entry.estimatedBytes
        touchLocked(songId)
        while (cache.count > Self.maxEntries || totalBytes > Self.maxBytes),
              let victim = lruOrder.first, victim != songId {
            removeLocked(victim)
        }
    }

    private func touchLocked(_ songId: String) {
        lruOrder.removeAll { $0 == songId }
        lruOrder.append(songId)
    }

    private func removeLocked(_ songId: String) {
        if let old = cache[songId] { totalBytes -= old.estimatedBytes }
        cache[songId] = nil
        lruOrder.removeAll { $0 == songId }
    }
}

/// 歌词文本解析（3.7 (23) 自 WallPrototypeViewController 搬家
/// 至此，函数体逐字不变）：LRC/YRC 解析、双表合并、逐字戳
/// 重标定、制作名单行识别。仓库取数链专用；LyricParser（舞
/// 台形状）是另一套输出形状，不在此合并。
enum LyricParsing {

    /// 双表合并（3.7 (20)，DS R45 对账 + onset 实测拍板）：
    /// 翻行时刻源由 LyricTiming.flipSource 决定（默认 LRC）；
    /// YRC 逐字戳只做行内扫光。flip=lrc 且双表齐时逐行按文本
    /// 匹配（同文本多行按出现顺序消费）：行时刻取 LRC，逐字
    /// 戳经 rebaseWords 按 DS 法重标定；匹配不上的 LRC 行
    /// words=nil（行级扫光）。只有单表时该表即翻行源（flip
    /// 随之）；双表皆空返回空。flip=yrc 时恢复 (19) 口径
    /// （YRC 行时刻 + 原戳，不重标定）。
    static func mergeLyricLines(lrcLines: [LyricLineData], yrcLines: [LyricLineData])
        -> (lines: [LyricLineData], source: String, flip: String) {
        if LyricTiming.flipSource == .yrc {
            if !yrcLines.isEmpty {
                return (yrcLines, lrcLines.isEmpty ? "yrc" : "lrc+yrc", "yrc")
            }
            return (lrcLines, lrcLines.isEmpty ? "none" : "lrc", "lrc")
        }
        guard !lrcLines.isEmpty else {
            return (yrcLines, yrcLines.isEmpty ? "none" : "yrc", "yrc")
        }
        guard !yrcLines.isEmpty else {
            return (lrcLines, "lrc", "lrc")
        }
        // 匹配键去掉全部空白：YRC 文本是逐字拼接（词间空格形
        // 式与 LRC 原行可能不同），LRC 文本经 trim——去空白后
        // 两边可比，显示文本仍用 LRC 原行。
        func matchKey(_ text: String) -> String {
            text.filter { !$0.isWhitespace }
        }
        var yrcByText: [String: [Int]] = [:]
        for (i, line) in yrcLines.enumerated() {
            yrcByText[matchKey(line.text), default: []].append(i)
        }
        var out: [LyricLineData] = []
        for (i, lrcLine) in lrcLines.enumerated() {
            var words: [LyricWordStamp]? = nil
            let key = matchKey(lrcLine.text)
            if var queue = yrcByText[key], !queue.isEmpty {
                let yrcLine = yrcLines[queue.removeFirst()]
                yrcByText[key] = queue
                if let yrcWords = yrcLine.words {
                    let boundary = i + 1 < lrcLines.count
                        ? lrcLines[i + 1].time : Double.infinity
                    words = rebaseWords(yrcWords,
                                        shift: lrcLine.time - yrcLine.time,
                                        boundary: boundary)
                }
            }
            out.append(LyricLineData(time: lrcLine.time, text: lrcLine.text, words: words))
        }
        return (out, "lrc+yrc", "lrc")
    }

    /// 逐字戳重标定（DS R45 法，禁全行仿射拉伸）：整行平移
    /// shift（= LRC 行首 − YRC 行首，首字落 LRC 行首）、保留
    /// 字间相对间隔、下一 LRC 行首为硬边界；溢出时只压缩行
    /// 尾空白/尾字停留（末字时长夹到边界），起始已越界的字
    /// 截断丢弃，不压缩字间节奏。全部越界返回 nil（行级扫光）。
    static func rebaseWords(_ words: [LyricWordStamp], shift: Double,
                            boundary: Double) -> [LyricWordStamp]? {
        var out: [LyricWordStamp] = []
        for word in words {
            let start = word.start + shift
            if start >= boundary { break }
            out.append(LyricWordStamp(start: start,
                                      duration: min(word.duration, boundary - start),
                                      text: word.text))
        }
        return out.isEmpty ? nil : out
    }

    /// LRC 解析：[mm:ss.xx] 前缀行 → 行模型（words = nil）；多时间
    /// 戳行只取首个，空文本行丢弃，结果按时间升序。
    /// [offset:±ms] 全局偏移（3.7 (17)）：带此标签的文件要求把
    /// 全部行时间整体平移 offset 毫秒（正值 = 歌词延后呈现，
    /// 行时间 = 时间戳 + offset）；旧实现不认此标签、解析失败
    /// 直接丢弃，带 offset 的歌整首恒定偏移数百毫秒。
    static func parseLRC(_ raw: String) -> [LyricLineData] {
        var offsetSeconds = 0.0
        for line in raw.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.lowercased().hasPrefix("[offset:") else { continue }
            let inner = s.dropFirst("[offset:".count).prefix { $0 != "]" }
            if let ms = Double(inner.trimmingCharacters(in: .whitespaces)) {
                offsetSeconds = ms / 1000
            }
        }
        var out: [LyricLineData] = []
        for line in raw.split(separator: "\n") {
            let s = String(line)
            guard s.hasPrefix("["), let close = s.firstIndex(of: "]") else { continue }
            let stamp = s[s.index(after: s.startIndex)..<close]
            let parts = stamp.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { continue }
            let text = String(s[s.index(after: close)...])
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            out.append(LyricLineData(time: minutes * 60 + seconds + offsetSeconds,
                                     text: text, words: nil))
        }
        let sorted = out.sorted { $0.time < $1.time }
        // 制作名单行只在首个正文行之前过滤（3.7 (13) #2，DS30
        // 位置约束）：正文开始后出现的同形行是歌词本体，不动。
        return Array(sorted.drop(while: { isCreditLine($0.text) }))
    }

    /// YRC 解析（3.7 (19)）：行格式 [startMs,durMs](startMs,durMs,flag)字…
    /// 行起始取头戳、逐字取元组戳（毫秒 → 秒）；行文本 = 逐字文本
    /// 拼接。不以 [ 开头的行是 JSON 制作名单行（{"t":…,"c":…}），
    /// 与 LRC 路径同口径跳过；带时间戳的名单行同样只在正文开始
    /// 前按 isCreditLine 过滤。元组中途解析失败的行降级为行级
    /// （words = nil，文本取已拼接部分），整表为空时调用方回落
    /// LRC。YRC 是机器生成格式，实测（529319768）33 行元组全
    /// 为三元组、无异常。
    static func parseYRC(_ raw: String) -> [LyricLineData] {
        var out: [LyricLineData] = []
        for rawLine in raw.split(separator: "\n") {
            let line = String(rawLine)
            guard line.hasPrefix("["), let headEnd = line.firstIndex(of: "]") else { continue }
            let head = line[line.index(after: line.startIndex)..<headEnd]
            let headParts = head.split(separator: ",")
            guard headParts.count >= 2,
                  let startMs = Double(headParts[0].trimmingCharacters(in: .whitespaces))
            else { continue }
            var words: [LyricWordStamp] = []
            var text = ""
            var cursor = line.index(after: headEnd)
            var malformed = false
            while cursor < line.endIndex {
                guard line[cursor] == "(",
                      let close = line[cursor...].firstIndex(of: ")") else {
                    malformed = true
                    break
                }
                let tuple = line[line.index(after: cursor)..<close]
                let tp = tuple.split(separator: ",")
                guard tp.count >= 2,
                      let wordStart = Double(tp[0].trimmingCharacters(in: .whitespaces)),
                      let wordDur = Double(tp[1].trimmingCharacters(in: .whitespaces))
                else { malformed = true; break }
                let textStart = line.index(after: close)
                let textEnd = line[textStart...].firstIndex(of: "(") ?? line.endIndex
                let wordText = String(line[textStart..<textEnd])
                words.append(LyricWordStamp(start: wordStart / 1000,
                                             duration: wordDur / 1000,
                                             text: wordText))
                text += wordText
                cursor = textEnd
            }
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            out.append(LyricLineData(time: startMs / 1000, text: text,
                                     words: (malformed || words.isEmpty) ? nil : words))
        }
        let sorted = out.sorted { $0.time < $1.time }
        return Array(sorted.drop(while: { isCreditLine($0.text) }))
    }

    /// 制作名单行识别（3.7 (13) #2）：网易云 LRC 开头是制作名单
    /// （作词/作曲/制作人/监制/混音/母带…），时间戳挤在亚秒级，
    /// (12) 里被当歌词行逐行扫光。只认「名目 + 冒号」或英文
    /// "X by" 形状；叙事行（如「妈妈：…」）不在名目表里。
    private static let creditPrefixes = [
        "作词", "作曲", "编曲", "制作人", "监制", "混音", "母带",
        "录音", "和声", "配唱", "音乐总监", "出品", "发行",
        "统筹", "企划", "演唱", "原唱", "OP", "SP"
    ]

    static func isCreditLine(_ text: String) -> Bool {
        for prefix in creditPrefixes where text.hasPrefix(prefix) {
            // 冒号前可能带空格（「作词 : 林夕」），先削掉再判。
            let rest = text.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("：") || rest.hasPrefix(":") { return true }
        }
        let lower = text.lowercased()
        return lower.hasPrefix("lyrics by") || lower.hasPrefix("composed by")
            || lower.hasPrefix("produced by") || lower.hasPrefix("arranged by")
    }
}
