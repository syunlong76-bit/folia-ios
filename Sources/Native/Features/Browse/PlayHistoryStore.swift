import Foundation

// PlayHistoryStore.swift
//
// 本机播放记录（对应 folia-major 的 explore/recentPlays.ts）：
// 每首歌一条记录——最后播放时间 + 按「听众日」（凌晨 4 点分界）计的播放次数。
// 保留 30 天、上限 300 首，JSON 落盘 Documents/folia-play-history.json。
// 探索页自有分区由它派生：「最近播放」= 近 7 天按时间倒序；
// 「再听一次」= 30 天内播放 ≥2 次、按近期权重排序（权重公式照源码 weightOf：
// 每天的次数取 log2(1+n)，每 7 天衰减一半；同权重取最后播放更晚者），上限 30 首。
//
// 与源码的口径差（移植报告已登记）：源码把「播放」（响几秒）与「收听」
// （听满一半）分开记，再听一次只认收听次数且有 goesOn 去重；原生侧的最小
// 记录点是 QueueManager 成功起播，没有现成的收听进度记账点，故本轮以
// 「成功起播次数」近似收听次数，权重公式与排序规则照源码。

final class PlayHistoryStore: ObservableObject {

    static let shared = PlayHistoryStore()

    struct Record: Codable {
        var track: FoliaTrack
        var lastPlayedAt: TimeInterval
        /// [听众日序号, 当日播放次数]，新日在前。
        var days: [[Int]]
    }

    @Published private(set) var records: [Record] = []

    private let fileURL: URL
    private static let keptMs: TimeInterval = 30 * 86_400
    private static let recentMs: TimeInterval = 7 * 86_400
    private static let maxRecords = 300
    private static let maxReplayed = 30
    private static let listeningKeptDays = 30
    private static let halfLifeDays = 7.0

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("folia-play-history.json")
        load()
    }

    // MARK: - 记账

    /// 记录一次成功起播（QueueManager 在取流成功、engine.load 前后调用；
    /// 调用方保证在主线程）。
    func recordPlay(_ track: FoliaTrack) {
        let now = Date().timeIntervalSince1970
        let today = Self.listenerDay(at: now)
        var list = records.filter { now - $0.lastPlayedAt <= Self.keptMs }
        if let index = list.firstIndex(where: { $0.track.id == track.id }) {
            var record = list.remove(at: index)
            record.track = track
            record.lastPlayedAt = now
            record.days = Self.withPlay(record.days, day: today)
            list.insert(record, at: 0)
        } else {
            list.insert(Record(track: track, lastPlayedAt: now, days: [[today, 1]]), at: 0)
        }
        records = Array(list.prefix(Self.maxRecords))
        save()
    }

    // MARK: - 自有分区派生

    /// 近 7 天播放过的歌，最后播放倒序（records 本身即倒序）。
    func recentTracks(now: TimeInterval = Date().timeIntervalSince1970) -> [FoliaTrack] {
        records.filter { now - $0.lastPlayedAt <= Self.recentMs }.map(\.track)
    }

    /// 播放 ≥2 次的歌按近期权重排序（照源码 replayedSongsOf）。
    func playAgainTracks(now: TimeInterval = Date().timeIntervalSince1970) -> [FoliaTrack] {
        let today = Self.listenerDay(at: now)
        let scored: [(track: FoliaTrack, weight: Double, at: TimeInterval)] = records.compactMap { record in
            let counted = record.days.filter { today - $0[0] < Self.listeningKeptDays }
            let total = counted.reduce(0) { $0 + $1[1] }
            guard total > 1 else { return nil }
            let weight = counted.reduce(0.0) { sum, dayCount in
                sum + log2(1.0 + Double(dayCount[1]))
                    * pow(0.5, Double(max(0, today - dayCount[0])) / Self.halfLifeDays)
            }
            return (record.track, weight, record.lastPlayedAt)
        }
        return scored
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.at > $1.at }
            .prefix(Self.maxReplayed)
            .map(\.track)
    }

    // MARK: - 听众日（源码 dayOf：本地时区、凌晨 4 点分界）

    static func listenerDay(at time: TimeInterval) -> Int {
        let date = Date(timeIntervalSince1970: time)
        let offset = TimeZone.current.secondsFromGMT(for: date)
        return Int(floor((time + Double(offset) - 4 * 3600) / 86_400))
    }

    /// 某日播放 +1，并剔除不再计数的旧日（30 天窗口）。
    private static func withPlay(_ days: [[Int]], day: Int) -> [[Int]] {
        var counted = days.filter { day - $0[0] < listeningKeptDays }
        if let index = counted.firstIndex(where: { $0[0] == day }) {
            counted[index][1] += 1
            let entry = counted.remove(at: index)
            return [entry] + counted
        }
        return [[day, 1]] + counted
    }

    // MARK: - 落盘

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Record].self, from: data) else { return }
        let now = Date().timeIntervalSince1970
        records = decoded
            .filter { now - $0.lastPlayedAt <= Self.keptMs }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
