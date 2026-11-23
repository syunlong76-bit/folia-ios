import Foundation
import Security

/// AI 歌词导演·双模式（3.7 (81) 第 11 条，借鉴 Folium 模组
/// 市场「AI 歌词导演」）：按歌词情感为每首歌配一只歌词特
/// 效，判定挂在 (80) 下一首预备管线——当前歌播放中就把下
/// 一首算好、写进逐歌记忆同一存储（来源标记 director，
/// 手动三击/点选记的 manual 永远优先、导演不覆盖），切歌
/// 瞬间由既有 applySongStyleMemory80 套用、零新增延迟。
///
/// 双模式：
/// - 未接 AI（接口地址或 key 任一为空）：本地规则引擎——
///   节奏能量（行密度/字速）＋歌词关键词情感桶打分选式。
/// - 接了 AI（用户在设置里自填 OpenAI 兼容接口地址＋key，
///   key 只存 Keychain）：本地引擎关闭，歌词摘要发用户自
///   己的接口判情感选式；请求失败只落痕不回退本地（模式
///   语义如约：接了 AI 就由 AI 管），本曲不写判定、下次
///   预备再试。
///
/// 总开关默认开（SettingsStore.directorEnabled81）；关时
/// 预备管线不调本引擎、存量导演记录也不再套用（消费端
/// SongStyleMemory80.style(for:) 按同一开关收口）。
/// 候选池：注册表全样式减 petconcert（演唱会是整场表演
/// 模式、不作逐歌自动配式）；锁定/下架在消费端校验。
final class LyricDirector81 {

    static let shared = LyricDirector81()

    private init() {}

    // MARK: - 配置（设置页读写）

    static var aiConfigured: Bool {
        !SettingsStore.directorEndpoint81.isEmpty
            && !DirectorKeychain81.read().isEmpty
    }

    /// 候选样式（id＋中文名），导演两模式共用同一池。
    static var candidates: [(id: String, name: String)] {
        LyricStageRegistry.allStyles
            .filter { $0.id != "petconcert" && !LyricStageRegistry.isLocked($0.id) }
            .map { ($0.id, $0.displayName) }
    }

    // MARK: - 判定入口（预备管线调用）

    /// 返回 (styleId, via)：via = local / ai。关开关、无候
    /// 选、AI 失败 → nil（不写记录）。
    func decide(track: FoliaTrack, lines: [LyricLine]) async -> (styleId: String, via: String)? {
        guard SettingsStore.directorEnabled81 else { return nil }
        let pool = Self.candidates
        guard !pool.isEmpty else { return nil }
        if Self.aiConfigured {
            if let styleId = await decideByAI(track: track, lines: lines, pool: pool) {
                Breadcrumbs.log("dir81.pick track=\(track.id) style=\(styleId) via=ai")
                return (styleId, "ai")
            }
            return nil
        }
        let styleId = decideLocally(track: track, lines: lines, pool: pool)
        Breadcrumbs.log("dir81.pick track=\(track.id) style=\(styleId) via=local")
        return (styleId, "local")
    }

    // MARK: - 本地规则引擎

    /// 关键词情感桶（子串计数，逐桶取最高分；同分按
    /// fire > sad > love > calm 的冲击优先序，与特效审美
    /// 口径「华丽冲击优先」同向）。
    private static let buckets: [(name: String, style: String, words: [String])] = [
        ("fire", "hanabi", ["燃", "战", "火", "冲", "奔", "跑", "飞", "跳",
                            "爆发", "热血", "闪耀", "光芒", "燃烧"]),
        ("sad", "nebbia", ["泪", "雨", "别", "离", "思念", "忘", "孤单",
                           "寂寞", "遗憾", "心碎", "梦醒", "再见"]),
        ("love", "lumiere", ["爱", "心", "吻", "拥抱", "喜欢", "星", "月",
                             "温柔", "甜", "宝贝", "亲爱"]),
        ("calm", "monet", ["风", "云", "山", "水", "田", "茶", "慢", "静",
                           "安", "眠", "海", "林", "花"]),
    ]

    private func decideLocally(track: FoliaTrack,
                               lines: [LyricLine],
                               pool: [(id: String, name: String)]) -> String {
        let text = lines.map(\.text).joined(separator: "\n")
        var best: (name: String, style: String, score: Int)?
        for bucket in Self.buckets {
            let score = bucket.words.reduce(0) { sum, word in
                sum + text.components(separatedBy: word).count - 1
            }
            if score > (best?.score ?? 0) {
                best = (bucket.name, bucket.style, score)
            }
        }
        if let best, best.score >= 2, pool.contains(where: { $0.id == best.style }) {
            Breadcrumbs.log("dir81.local track=\(track.id) mood=\(best.name) score=\(best.score)")
            return best.style
        }
        // 节奏能量兜底：行密度（行/分钟）判快慢。
        let span = max(lines.last?.end ?? track.duration, 1)
        let perMinute = Double(lines.count) / span * 60
        let fallback: String
        if perMinute >= 26 { fallback = "cadenza" }
        else if perMinute <= 11 { fallback = "still" }
        else { fallback = "classic" }
        Breadcrumbs.log("dir81.local track=\(track.id) mood=tempo"
            + " lpm=\(Int(perMinute)) -> \(fallback)")
        return pool.contains(where: { $0.id == fallback })
            ? fallback : (pool.first?.id ?? "classic")
    }

    // MARK: - AI 模式（用户自备 OpenAI 兼容接口）

    private func decideByAI(track: FoliaTrack,
                            lines: [LyricLine],
                            pool: [(id: String, name: String)]) async -> String? {
        let endpoint = SettingsStore.directorEndpoint81
        let key = DirectorKeychain81.read()
        guard let url = URL(string: endpoint), !key.isEmpty else { return nil }
        let excerpt = lines.map(\.text).joined(separator: "\n")
        let lyricText = String(excerpt.prefix(1500))
        let poolText = pool.map { "\($0.id)（\($0.name)）" }.joined(separator: "、")
        let prompt = """
        你是音乐演出导演。根据下面这首歌的歌词情感，从候选特效里只选一只最配的。
        候选（id（名称））：\(poolText)
        歌曲：《\(track.title)》歌手：\(track.artist)
        歌词：
        \(lyricText)
        只回复所选的 id 本身，不要任何其他文字。
        """
        let body: [String: Any] = [
            "model": SettingsStore.directorModel81,
            "temperature": 0.2,
            "messages": [["role": "user", "content": prompt]],
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Breadcrumbs.log("dir81.err http=\(code)")
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                Breadcrumbs.log("dir81.err shape=1")
                return nil
            }
            // 回答里第一个出现的候选 id 即判定（模型多话时
            // 也稳得住）；一个都没有 = 判废。
            for candidate in pool where content.contains(candidate.id) {
                return candidate.id
            }
            Breadcrumbs.log("dir81.err nomatch=1")
            return nil
        } catch {
            Breadcrumbs.log("dir81.err net=1")
            return nil
        }
    }
}

/// 导演 API key 的 Keychain 收纳（服务级通用密码项；只存
/// 本机钥匙串，不进 UserDefaults、不落日志）。
enum DirectorKeychain81 {

    private static let service = "folia.director81"
    private static let account = "apiKey"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func write(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
