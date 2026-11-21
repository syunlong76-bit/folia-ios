import Foundation

// 3.7 (62) WD 簇：译文侧通路（C3 / monet 副字幕轨的数据源）。
//
// 协议 LyricLine 无译文字段、LyricRepository 的 bundle 只取
// lrc/yrc——本层不改冻结协议、不改仓库，另走同一 /lyric/new
// 端点读 tlyric 字段（网易云响应自带），按行 start 对齐成
// [trackId: [lineStart: 译文]] 缓存。仅网易云（ncm_ 前缀）有此
// 字段；QQ/酷狗与无译文歌曲诚实返回空，消费方据此不显示并在
// 面板标注「无数据源」。渲染器在 applySnapshot 调
// ensureLoaded(trackId:)，在建行时查 translation(for:lineStart:)。

final class LyricTranslation62 {

    static let shared = LyricTranslation62()

    private let lock = NSLock()
    private var cache: [String: [TimeInterval: String]] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    /// 触发加载（幂等）：非网易云曲目直接记空，不发请求。
    func ensureLoaded(trackId: String?) {
        guard let trackId, !trackId.isEmpty else { return }
        lock.lock()
        if cache[trackId] != nil || inFlight.contains(trackId) {
            lock.unlock()
            return
        }
        inFlight.insert(trackId)
        lock.unlock()
        guard trackId.hasPrefix("ncm_") else {
            finish(trackId: trackId, map: [:])
            return
        }
        Task { [weak self] in
            guard let self else { return }
            var map: [TimeInterval: String] = [:]
            if let data = try? await EdgeOneAPIClient.shared.requestData(
                provider: .netease, path: "/lyric/new",
                queryItems: [URLQueryItem(name: "id",
                    value: trackId.replacingOccurrences(of: "ncm_", with: ""))]),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tlyric = root["tlyric"] as? [String: Any],
               let text = tlyric["lyric"] as? String, !text.isEmpty {
                for line in LyricParsing.parseLRC(text) where !line.text.isEmpty {
                    map[line.time] = line.text
                }
            }
            self.finish(trackId: trackId, map: map)
        }
    }

    private func finish(trackId: String, map: [TimeInterval: String]) {
        lock.lock()
        cache[trackId] = map
        inFlight.remove(trackId)
        lock.unlock()
        Breadcrumbs.log("stage62.translation track=\(trackId) lines=\(map.count)")
    }

    /// 按行 start 查译文：先精确命中，再 ±0.6s 内最近一条。
    func translation(for trackId: String?, lineStart: TimeInterval) -> String? {
        guard let trackId else { return nil }
        lock.lock()
        let map = cache[trackId]
        lock.unlock()
        guard let map, !map.isEmpty else { return nil }
        if let exact = map[lineStart] { return exact }
        var best: (delta: TimeInterval, text: String)?
        for (time, text) in map {
            let delta = abs(time - lineStart)
            if delta <= 0.6, best == nil || delta < best!.delta {
                best = (delta, text)
            }
        }
        return best?.text
    }

    /// 该曲是否已有译文数据（面板/面包屑判读用）。
    func hasData(for trackId: String?) -> Bool {
        guard let trackId else { return false }
        lock.lock()
        defer { lock.unlock() }
        return (cache[trackId]?.isEmpty == false)
    }
}
