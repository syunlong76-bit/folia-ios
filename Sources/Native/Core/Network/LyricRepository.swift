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
        /// 演唱跨度压缩比 r（3.7 (43) 路3）：无逐字戳行的逐字
        /// 时刻表按 span×r 排（行尾气口不再摊进每个字）；由
        /// 本曲有戳行标定（中位）。3.7 (46) 跨曲学习：本曲无
        /// 戳时改取 SingingRatioPool 的跨曲标定中位数（有戳歌
        /// 逐曲入池），池空才落缺省 0.8。墙面 lineDuration 与
        /// 舞台均分共用此值（同一 r 源）。
        let singingRatio: Double
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
                             flip: "lrc", singingRatio: 0.8, isNegative: true,
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
        var mergeStats = LyricParsing.MergeStats()
        if let bundle = try? await EdgeOneAPIClient.shared.fetchLyricBundle(songId: songId) {
            lrcText = bundle.lrc
            let merged = LyricParsing.mergeLyricLines(
                lrcLines: LyricParsing.parseLRC(bundle.lrc),
                yrcLines: bundle.yrc.map(LyricParsing.parseYRC) ?? [])
            parsed = merged.lines
            source = merged.source
            flip = merged.flip
            mergeStats = merged.stats
        } else if let text = try? await EdgeOneAPIClient.shared.fetchLyricText(songId: songId) {
            lrcText = text
            parsed = LyricParsing.parseLRC(text)
            source = parsed.isEmpty ? "none" : "lrc-fallback"
            flip = "lrc"
        }
        let bytes = Self.estimateBytes(lines: parsed, lrcText: lrcText)
        // r 三级来源（3.7 (46) 跨曲学习）：本曲有戳 → 同曲标定
        // 并入池（rSource=track）；本曲无戳 → 池中位数
        // （rSource=calibrated-pool）；池空 → 缺省 0.8
        // （rSource=default）。(45) 真机日志定级：全库多为无戳
        // LRC、r 恒落写死 0.8 是扫光普遍慢的主因之一——单曲
        // 标定救不了无戳歌，跨曲中位数把有戳歌的演唱跨度分
        // 布迁移给无戳歌。红线不变：不动 LyricTiming.lead、
        // 不动翻行链，r 只喂无戳行的逐字均分跨度。
        let ratio: Double
        let rSource: String
        if let calibrated = Self.singingCalibration(for: parsed) {
            ratio = calibrated
            rSource = "track"
            SingingRatioPool.record(songId: songId, ratio: calibrated)
        } else if let pooled = SingingRatioPool.median() {
            ratio = pooled
            rSource = "calibrated-pool"
        } else {
            ratio = 0.8
            rSource = "default"
        }
        // 逐字覆盖率面包屑（3.7 (43) 路3 埋点先行）：此前仓库
        // 零面包屑，一首歌有无 YRC 逐字戳无从判读、均分定案
        // 与否全靠猜。此行落盘后：withWords≈0 → 无戳均分行
        // 占全表（span×r 修复面）；withWords≈lines 仍慢 →
        // 转查 rebase 平移/动画层，勿动均分。
        let withWords = parsed.filter { $0.words != nil }.count
        // wordSrc（3.7 (50)，DS YRC50 评审）：真机一轮判死真戳
        // 是否生效——yrc=全行带真戳 / mixed=部分行 / uniform=
        // 全行均分（无 YRC 或全未配上）。yrcLines/yrcMatched/
        // yrcAmbiguous 为合并诊断（见 MergeStats）。
        let wordSrc = withWords == 0 ? "uniform"
            : (withWords == parsed.count ? "yrc" : "mixed")
        Breadcrumbs.log("lrc source track=\(songId)"
            + " lines=\(parsed.count) withWords=\(withWords)"
            + " yrc=\(source.contains("yrc") ? "yes" : "no")"
            + " src=\(source) flip=\(flip)"
            + " r=\(String(format: "%.3f", ratio))"
            + " rSource=\(rSource) pool=\(SingingRatioPool.count)"
            + " yrcLines=\(mergeStats.yrcLineCount)"
            + " yrcMatched=\(mergeStats.yrcMatched)"
            + " yrcAmbiguous=\(mergeStats.yrcAmbiguous)"
            + " wordSrc=\(wordSrc)")
        return Entry(lines: parsed, lrcText: lrcText, source: source,
                     flip: flip, singingRatio: ratio,
                     isNegative: parsed.isEmpty,
                     fetchedAt: Date(), estimatedBytes: bytes)
    }

    /// 演唱跨度压缩比标定（3.7 (43) 路3）：人声唱完一行通常
    /// 早于下一行 start（行尾气口 G 常见 0.3–2.0s），无戳行
    /// 若按 [行 start, 下行 start] 全跨度均分逐字时刻，G 被
    /// 摊进每个字、扫光恒慢（lag(f)=f·G、行尾最重——审计
    /// folia43 路3 定案）。有戳行给出真演唱跨度：r 样本 =
    /// (末字 end − 行 start) / (下行 start − 行 start)，取全
    /// 曲中位；全曲无戳回缺省 0.8。结果夹 [0.3, 1]：防个别
    /// 行戳异常（rebase 边界夹取可把末字 end 顶到行界、样本
    /// =1，中位对此不敏感）把 r 标定失真。
    static func singingRatio(for lines: [LyricLineData]) -> Double {
        singingCalibration(for: lines) ?? 0.8
    }

    /// 同曲标定本体（3.7 (46) 拆分）：无可用样本返回 nil（与
    /// 「标定值恰为 0.8」区分——前者要走跨曲池兜底，后者是真
    /// 标定），供 fetch 决定 rSource 与是否入池。
    static func singingCalibration(for lines: [LyricLineData]) -> Double? {
        var samples: [Double] = []
        for i in lines.indices {
            guard let words = lines[i].words, let last = words.last,
                  i + 1 < lines.count else { continue }
            let span = lines[i + 1].time - lines[i].time
            let sung = last.start + last.duration - lines[i].time
            guard span > 0.3, sung > 0 else { continue }
            samples.append(min(max(sung / span, 0.3), 1))
        }
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        return min(max(median, 0.3), 1)
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

    // MARK: - 缓存管理（3.7 (55) 协调者集成：设置页存储签消费）

    /// 当前缓存条目数与估算字节（设置页显示用）。
    var cacheStats: (count: Int, bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (cache.count, totalBytes)
    }

    /// 清空全部内存歌词缓存（下次取词重新拉取）。
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        lruOrder.removeAll()
        totalBytes = 0
        Breadcrumbs.log("lyricRepo.clearAll")
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

    /// 合并诊断（3.7 (50)，DS YRC50 评审对账）：供仓库面包屑
    /// 判读匹配覆盖——yrcMatched=精确+折叠两级共匹配上的行
    /// 数；yrcAmbiguous=折叠级因候选不唯一被跳过的行数。
    struct MergeStats {
        var yrcLineCount: Int = 0
        var yrcMatched: Int = 0
        var yrcAmbiguous: Int = 0
    }

    /// 双表合并（3.7 (20)，DS R45 对账 + onset 实测拍板）：
    /// 翻行时刻源由 LyricTiming.flipSource 决定（默认 LRC）；
    /// YRC 逐字戳只做行内扫光。flip=lrc 且双表齐时逐行按文本
    /// 匹配（同文本多行按出现顺序消费）：行时刻取 LRC，逐字
    /// 戳经 rebaseWords 按 DS 法重标定；匹配不上的 LRC 行
    /// words=nil（行级扫光）。只有单表时该表即翻行源（flip
    /// 随之）；双表皆空返回空。flip=yrc 时恢复 (19) 口径
    /// （YRC 行时刻 + 原戳，不重标定）。
    ///
    /// 匹配两级（3.7 (50)，DS YRC50 评审定案「精确优先、折叠
    /// 兜底、歧义不配」）：一级沿用去空白精确键（行为不变）；
    /// 二级只对一级未配上的行，用折叠键（全角 ASCII→半角、
    /// 拉丁 A-Z→a-z，逐字 1:1 折叠，不用 lowercased()/NFKC
    /// 防字符数变化）在「未消费 YRC 行」中找候选——候选须唯
    /// 一且落在该行前后已匹配 YRC 下标之间（顺序单调），否
    /// 则计 yrcAmbiguous 并跳过（该行退均分，不错用他行词分
    /// 布）。实测动因：《孤勇者》LRC 半角括号 vs YRC 全角括
    /// 号一行漏配，折叠后该曲 57/57 全配（2026-11-20 真回包
    /// 复刻验证）。折叠只影响匹配键，显示文本仍用 LRC 原行。
    static func mergeLyricLines(lrcLines: [LyricLineData], yrcLines: [LyricLineData])
        -> (lines: [LyricLineData], source: String, flip: String, stats: MergeStats) {
        var stats = MergeStats(yrcLineCount: yrcLines.count)
        if LyricTiming.flipSource == .yrc {
            if !yrcLines.isEmpty {
                stats.yrcMatched = yrcLines.count
                return (yrcLines, lrcLines.isEmpty ? "yrc" : "lrc+yrc", "yrc", stats)
            }
            return (lrcLines, lrcLines.isEmpty ? "none" : "lrc", "lrc", stats)
        }
        guard !lrcLines.isEmpty else {
            stats.yrcMatched = yrcLines.count
            return (yrcLines, yrcLines.isEmpty ? "none" : "yrc", "yrc", stats)
        }
        guard !yrcLines.isEmpty else {
            return (lrcLines, "lrc", "lrc", stats)
        }
        // 匹配键去掉全部空白：YRC 文本是逐字拼接（词间空格形
        // 式与 LRC 原行可能不同），LRC 文本经 trim——去空白后
        // 两边可比，显示文本仍用 LRC 原行。
        func matchKey(_ text: String) -> String {
            text.filter { !$0.isWhitespace }
        }
        // 折叠键：全角 ASCII（FF01–FF5E）→半角、拉丁大写→小
        // 写，逐标量 1:1 映射（多标量字素原样保留），字符数
        // 与精确键一致，折叠后同键即全文等价（标点宽度/拉丁
        // 大小写差异除外）。
        func foldedKey(_ text: String) -> String {
            var out = ""
            out.reserveCapacity(text.count)
            for ch in text {
                if ch.isWhitespace { continue }
                let scalars = ch.unicodeScalars
                guard scalars.count == 1, let scalar = scalars.first else {
                    out.append(ch)
                    continue
                }
                let v = scalar.value
                if v >= 0xFF01 && v <= 0xFF5E,
                   let half = Unicode.Scalar(v - 0xFEE0) {
                    out.append(Character(half))
                } else if v >= 0x41 && v <= 0x5A,
                          let lower = Unicode.Scalar(v + 0x20) {
                    out.append(Character(lower))
                } else {
                    out.append(ch)
                }
            }
            return out
        }
        var yrcByText: [String: [Int]] = [:]
        for (i, line) in yrcLines.enumerated() {
            yrcByText[matchKey(line.text), default: []].append(i)
        }
        // 一级：精确键消费。matchedYrc[i] = 第 i 个 LRC 行配到
        // 的 YRC 下标（二级单调判定与消费记账共用）。
        var matchedYrc: [Int?] = Array(repeating: nil, count: lrcLines.count)
        var consumedYrc = Set<Int>()
        for (i, lrcLine) in lrcLines.enumerated() {
            let key = matchKey(lrcLine.text)
            if var queue = yrcByText[key], !queue.isEmpty {
                let idx = queue.removeFirst()
                yrcByText[key] = queue
                matchedYrc[i] = idx
                consumedYrc.insert(idx)
            }
        }
        // 二级：折叠键兜底（候选唯一 + 顺序单调才配）。
        var yrcByFolded: [String: [Int]] = [:]
        for (i, line) in yrcLines.enumerated() where !consumedYrc.contains(i) {
            yrcByFolded[foldedKey(line.text), default: []].append(i)
        }
        for i in lrcLines.indices where matchedYrc[i] == nil {
            let candidates = (yrcByFolded[foldedKey(lrcLines[i].text)] ?? [])
                .filter { !consumedYrc.contains($0) }
            guard candidates.count == 1, let idx = candidates.first else {
                if candidates.count > 1 { stats.yrcAmbiguous += 1 }
                continue
            }
            let prev = (0..<i).reversed().compactMap { matchedYrc[$0] }.first ?? -1
            let next = ((i + 1)..<lrcLines.count).compactMap { matchedYrc[$0] }.first
                ?? Int.max
            guard idx > prev && idx < next else {
                stats.yrcAmbiguous += 1
                continue
            }
            matchedYrc[i] = idx
            consumedYrc.insert(idx)
        }
        var out: [LyricLineData] = []
        for (i, lrcLine) in lrcLines.enumerated() {
            var words: [LyricWordStamp]? = nil
            if let idx = matchedYrc[i] {
                stats.yrcMatched += 1
                let yrcLine = yrcLines[idx]
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
        return (out, "lrc+yrc", "lrc", stats)
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

/// 扫光 r 跨曲标定样本池（3.7 (46)）：每遇到一首有逐字戳的歌，
/// 把其同曲标定 r 按 songId 入池持久化（UserDefaults）；无戳歌
/// 取池中位数作 r。策略：同曲重标定覆盖旧样本（不重复计数）；
/// 上限 40 首，超限淘汰最旧；样本 90 天过期（读时清理）——r 分
/// 布随曲库构成缓慢漂移，过期与上限保证中位数反映近期曲库。
/// 读写经 NSLock 串行（fetch 在并发 Task 里跑）。
enum SingingRatioPool {

    private static let defaultsKey = "folia.lrc.singingRatioPool.v1"
    private static let maxSamples = 40
    private static let maxAge: TimeInterval = 90 * 24 * 3600
    private static let lock = NSLock()

    private struct Sample {
        var songId: String
        var ratio: Double
        var recordedAt: TimeInterval
    }

    private static func loadLocked() -> [Sample] {
        let raw = UserDefaults.standard.array(forKey: defaultsKey) ?? []
        let now = Date().timeIntervalSince1970
        return raw.compactMap { item -> Sample? in
            guard let dict = item as? [String: Any],
                  let id = dict["id"] as? String,
                  let r = dict["r"] as? Double,
                  let t = dict["t"] as? Double,
                  now - t < maxAge else { return nil }
            return Sample(songId: id, ratio: r, recordedAt: t)
        }
    }

    private static func saveLocked(_ samples: [Sample]) {
        let raw: [[String: Any]] = samples.map {
            ["id": $0.songId, "r": $0.ratio, "t": $0.recordedAt]
        }
        UserDefaults.standard.set(raw, forKey: defaultsKey)
    }

    static func record(songId: String, ratio: Double) {
        lock.lock()
        defer { lock.unlock() }
        var samples = loadLocked()
        samples.removeAll { $0.songId == songId }
        samples.append(Sample(songId: songId, ratio: ratio,
                              recordedAt: Date().timeIntervalSince1970))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        saveLocked(samples)
    }

    /// 池中位数（夹 [0.3, 1] 与单曲标定同口径）；池空返回 nil。
    static func median() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let samples = loadLocked()
        guard !samples.isEmpty else { return nil }
        let sorted = samples.map { $0.ratio }.sorted()
        return min(max(sorted[sorted.count / 2], 0.3), 1)
    }

    static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked().count
    }
}
