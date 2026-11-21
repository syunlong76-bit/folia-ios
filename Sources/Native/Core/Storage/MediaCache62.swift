import Combine
import Foundation

// MediaCache62.swift
//
// 3.7 (62) WC 簇 §4.10 存储三件：
// - MediaCache62：媒体文件磁盘缓存（Caches/folia-media62）。
//   诚实边界：QueueManager/PlaybackEngine 归 WB 簇不可改，
//   在线播放的取流链没有旁路挂点可把播出 URL 换成本地文件，
//   故本缓存以「预缓存/手动缓存」形态落地——缓存当前歌与
//   队列后续曲目落盘、计数/上限/LRU/清除全真执行；在线播放
//   自动回填缓存的挂点缺口见交付报告，不假装全自动。
// - ListeningStats62：听歌统计（分析数据）：订阅引擎当前曲
//   ＋播放态，累计播放次数与聆听秒数，落盘 JSON；清除行真删。
//   （任务书原拟观察切歌通知——仓库无现成切歌通知，改订
//   PlaybackEngine.$currentTrack，同为既有通路，见报告。）
// - VolumeBalanceStore62：智能平衡数据：逐曲音量学习偏移
//   存储，供 WB 的 ReplayGain 消费（learnedOffset/record）。

// MARK: - 媒体缓存

final class MediaCache62: ObservableObject {

    static let shared = MediaCache62()

    struct Entry: Codable, Identifiable {
        var trackId: String
        var title: String
        var artist: String
        var fileName: String
        var bytes: Int
        var cachedAt: TimeInterval
        var lastAccessAt: TimeInterval
        var id: String { trackId }
    }

    @Published private(set) var entries: [Entry] = []

    var directory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("folia-media62", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    var totalBytes: Int { entries.reduce(0) { $0 + $1.bytes } }
    var cachedCount: Int { entries.count }

    private init() { loadIndex() }

    func isCached(trackId: String) -> Bool {
        entries.contains { $0.trackId == trackId }
    }

    func localFileURL(for trackId: String) -> URL? {
        guard let entry = entries.first(where: { $0.trackId == trackId }) else { return nil }
        let url = directory.appendingPathComponent(entry.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func track(for trackId: String) -> FoliaTrack? {
        cachedTracks().first { $0.id == trackId }
    }

    /// 已缓存曲目（以 FoliaTrack 形态回放列表用；元数据随索引存）。
    private var trackMeta: [String: FoliaTrack] = [:]
    func cachedTracks() -> [FoliaTrack] {
        entries.compactMap { trackMeta[$0.trackId] }
    }

    /// 下载一首到缓存（在线曲目按 id 现换流地址再落盘）。
    @discardableResult
    func cache(track: FoliaTrack) async -> Bool {
        guard SettingsStore.mediaCacheEnabled62 else { return false }
        guard track.sourceType == .netease else { return false }
        if isCached(trackId: track.id) { return true }
        do {
            let stream = try await EdgeOneAPIClient.shared.fetchSongStreamURL(
                provider: track.sourceType, songId: track.id)
            let (tempURL, response) = try await URLSession.shared.download(from: stream)
            let expected = response.expectedContentLength
            let ext = stream.pathExtension.isEmpty ? "mp3" : stream.pathExtension
            let fileName = track.id.replacingOccurrences(of: "/", with: "_") + "." + ext
            let dest = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            let bytes = (try? dest.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                ?? (expected > 0 ? Int(expected) : 0)
            await MainActor.run {
                self.entries.removeAll { $0.trackId == track.id }
                self.entries.append(Entry(
                    trackId: track.id, title: track.title, artist: track.artist,
                    fileName: fileName, bytes: bytes,
                    cachedAt: Date().timeIntervalSince1970,
                    lastAccessAt: Date().timeIntervalSince1970))
                self.trackMeta[track.id] = track
                self.saveIndex()
                self.enforceLimitLocked()
            }
            Breadcrumbs.log("mediacache62.cached id=\(track.id) bytes=\(bytes)")
            return true
        } catch {
            Breadcrumbs.log("mediacache62.cache fail id=\(track.id) err=\(error.localizedDescription)")
            return false
        }
    }

    /// 预缓存：当前曲＋队列后 N 首（手动触发入口：设置行/
    /// 命令/播放面板本地页签）。
    func precacheQueue(lookahead: Int = 5) async -> Int {
        let queue = QueueManager.shared.queue
        let start = QueueManager.shared.currentIndex
        guard !queue.isEmpty else { return 0 }
        var done = 0
        for offset in 0...lookahead {
            let track = queue[(start + offset) % queue.count]
            if await cache(track: track) { done += 1 }
        }
        return done
    }

    @discardableResult
    func remove(trackId: String) -> Int {
        guard let entry = entries.first(where: { $0.trackId == trackId }) else { return 0 }
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(entry.fileName))
        entries.removeAll { $0.trackId == trackId }
        trackMeta.removeValue(forKey: trackId)
        saveIndex()
        return entry.bytes
    }

    @discardableResult
    func clearAll() -> Int {
        let freed = totalBytes
        for entry in entries {
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent(entry.fileName))
        }
        entries = []
        trackMeta = [:]
        saveIndex()
        Breadcrumbs.log("mediacache62.clearAll freed=\(freed)")
        return freed
    }

    /// LRU 清理：超上限时按 lastAccessAt 最旧先删，真执行。
    private func enforceLimitLocked() {
        let limit = SettingsStore.mediaCacheLimitMB62 * 1_048_576
        while totalBytes > limit,
              let oldest = entries.min(by: { $0.lastAccessAt < $1.lastAccessAt }) {
            _ = remove(trackId: oldest.trackId)
        }
    }

    func enforceLimit() { enforceLimitLocked() }

    // MARK: - 索引落盘（含 FoliaTrack 元数据，播放在线地址不存）

    private struct IndexFile: Codable {
        var entries: [Entry]
        var tracks: [FoliaTrack]
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode(IndexFile.self, from: data)
        else { return }
        entries = decoded.entries
        trackMeta = Dictionary(uniqueKeysWithValues: decoded.tracks.map { ($0.id, $0) })
    }

    private func saveIndex() {
        let file = IndexFile(entries: entries, tracks: Array(trackMeta.values))
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

// MARK: - 听歌统计（分析数据）

final class ListeningStats62: ObservableObject {

    static let shared = ListeningStats62()

    struct TrackStat: Codable {
        var playCount: Int = 0
        var listenedSeconds: Double = 0
    }

    @Published private(set) var stats: [String: TrackStat] = [:]
    @Published private(set) var totalPlays: Int = 0
    @Published private(set) var totalListenedSeconds: Double = 0

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var currentTrackId: String?
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("folia-listening-stats62.json")
    }

    private init() { load() }

    func start() {
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self, let track, self.currentTrackId != track.id else { return }
                self.currentTrackId = track.id
                var stat = self.stats[track.id] ?? TrackStat()
                stat.playCount += 1
                self.stats[track.id] = stat
                self.recomputeTotals()
                self.save()
                Breadcrumbs.log("stats62.play id=\(track.id) count=\(stat.playCount)")
            }
            .store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) {
            [weak self] _ in
            guard let self, PlaybackEngine.shared.isPlaying,
                  let id = self.currentTrackId else { return }
            var stat = self.stats[id] ?? TrackStat()
            stat.listenedSeconds += 5
            self.stats[id] = stat
            self.recomputeTotals()
            self.save()
        }
    }

    func stat(for trackId: String) -> TrackStat? { stats[trackId] }

    func clearAll() {
        stats = [:]
        recomputeTotals()
        try? FileManager.default.removeItem(at: fileURL)
        Breadcrumbs.log("stats62.clearAll")
    }

    private func recomputeTotals() {
        totalPlays = stats.values.reduce(0) { $0 + $1.playCount }
        totalListenedSeconds = stats.values.reduce(0) { $0 + $1.listenedSeconds }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: TrackStat].self, from: data)
        else { return }
        stats = decoded
        recomputeTotals()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - 智能平衡数据（逐曲音量学习偏移）

/// 供 WB 簇 ReplayGain 消费的对外符号（任务书定名）：
/// learnedOffset(forTrackKey:) 读偏移（dB，无记录 0）；
/// record(trackKey:offset:) 写学习结果。清除行真删本存储。
final class VolumeBalanceStore62 {

    static let shared = VolumeBalanceStore62()

    private let defaultsKey = "folia62.volumeBalance.offsets"
    private var offsets: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private init() {}

    func learnedOffset(forTrackKey key: String) -> Float {
        Float(offsets[key] ?? 0)
    }

    func record(trackKey: String, offset: Float) {
        var map = offsets
        map[trackKey] = Double(offset)
        offsets = map
        Breadcrumbs.log("volumebalance62.record key=\(trackKey) offset=\(offset)")
    }

    var count: Int { offsets.count }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        Breadcrumbs.log("volumebalance62.clearAll")
    }
}
