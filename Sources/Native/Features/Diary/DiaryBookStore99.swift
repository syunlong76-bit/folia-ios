import Foundation
import Combine
import UIKit

// DiaryBookStore99.swift — (99) 第 7 项：音乐日记本 P0 原生试用版数据层。
//
// 与既有两套数据的分工（调研结论）：
// - DiaryStore90（Player/）：旧简版日记（贴歌＋文字＋涂鸦，UserDefaults），
//   控制台/拍立得入口仍在用，本文件不改它、不迁它的数据。
// - SketchbookStore（Sketchbook/）：名为「日记本」的歌曲暂存抽屉（收歌器），
//   不是日记正文，与本功能无关，不复用。
// 本店是 P0 新版的独立单源：Documents/folia-diary99.json（整表 JSON、原子写，
// 照 PlayHistoryStore / SketchbookStore 既有口径），含正式条目、回收站、
// 今日草稿确认标记、编辑器自动保存草稿四部分。
//
// 今日草稿数据口径（如实）：数据源为 PlayHistoryStore（成功起播记账，
// 听众日 = 凌晨 4 点分界）。今日次数取 records.days 里听众日 == 今天的计数；
// 总时长为「次数 × 曲长」的估算（PlayHistoryStore 不记实际收听秒数）。

struct DiaryEntry99: Codable, Identifiable, Equatable {
    var id: String
    /// 本地日历日键 yyyy-MM-dd。
    var dateKey: String
    var createdAt: TimeInterval
    var text: String
    /// 情绪标签（预设：开心/低落/失眠/通勤/平静/想哭/兴奋），可空。
    var mood: String?
    /// 贴纸相对路径（Diary/Stickers/<类>/<名>.png 里的 <类>/<名>），正文区小图呈现。
    var stickerNames: [String]
    var songId: String?
    var songTitle: String?
    var songArtist: String?
    var songArtwork: String?
    /// true = 由今日草稿确认生成（卡面打「今日草稿」标）。
    var fromDraft: Bool
}

struct DiaryTodayPlay99 {
    var track: FoliaTrack
    var playsToday: Int
}

final class DiaryStore99: ObservableObject {

    static let shared = DiaryStore99()

    static let moods = ["开心", "低落", "失眠", "通勤", "平静", "想哭", "兴奋"]

    @Published private(set) var entries: [DiaryEntry99] = []
    @Published private(set) var trashed: [DiaryEntry99] = []
    /// 今日草稿已确认的日键（yyyy-MM-dd）；等于今天 = 今日草稿已入册。
    @Published private(set) var draftConfirmedKey: String?
    /// 编辑器自动保存的未完成正文（打开编辑器时恢复）。
    @Published var editorAutosave: String = ""

    private struct Persisted: Codable {
        var entries: [DiaryEntry99]
        var trashed: [DiaryEntry99]
        var draftConfirmedKey: String?
        var editorAutosave: String
    }

    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("folia-diary99.json")
        load()
    }

    // MARK: - 今日草稿（PlayHistoryStore 派生）

    /// 今天（听众日口径）播放过的歌与次数，次数多者在前。
    func todayPlays() -> [DiaryTodayPlay99] {
        let today = PlayHistoryStore.listenerDay(at: Date().timeIntervalSince1970)
        var result: [DiaryTodayPlay99] = []
        for record in PlayHistoryStore.shared.records {
            let count = record.days.first(where: { $0[0] == today })?[1] ?? 0
            if count > 0 {
                result.append(DiaryTodayPlay99(track: record.track, playsToday: count))
            }
        }
        return result.sorted { $0.playsToday > $1.playsToday }
    }

    var todayDraftConfirmed: Bool { draftConfirmedKey == Self.dateKey(for: Date()) }

    /// 草稿自动正文：听了哪些歌、共多少次、估算总时长。
    func draftText(plays: [DiaryTodayPlay99]) -> String {
        let totalPlays = plays.reduce(0) { $0 + $1.playsToday }
        let estSeconds = plays.reduce(0.0) { $0 + Double($1.playsToday) * $1.track.duration }
        let minutes = Int(estSeconds / 60)
        var lines = ["今天听了 \(plays.count) 首歌，共播放 \(totalPlays) 次，约 \(minutes) 分钟。"]
        for play in plays.prefix(8) {
            lines.append("· \(play.track.title) — \(play.track.artist)（\(play.playsToday) 次）")
        }
        return lines.joined(separator: "\n")
    }

    /// 确认今日草稿为正式日记（挂今日播放最多的一首歌）。
    @discardableResult
    func confirmTodayDraft() -> DiaryEntry99? {
        let plays = todayPlays()
        guard !plays.isEmpty, !todayDraftConfirmed else { return nil }
        let top = plays[0].track
        let entry = DiaryEntry99(
            id: UUID().uuidString,
            dateKey: Self.dateKey(for: Date()),
            createdAt: Date().timeIntervalSince1970,
            text: draftText(plays: plays),
            mood: nil,
            stickerNames: [],
            songId: top.id, songTitle: top.title, songArtist: top.artist,
            songArtwork: top.artworkURL?.absoluteString,
            fromDraft: true)
        entries.insert(entry, at: 0)
        draftConfirmedKey = entry.dateKey
        save()
        Breadcrumbs.log("p99 diary confirm")
        return entry
    }

    /// 「编辑草稿并确认」路径：编辑器存完条目后标今日草稿已确认。
    func markDraftConfirmed() {
        draftConfirmedKey = Self.dateKey(for: Date())
        save()
    }

    // MARK: - 条目增删改

    @discardableResult
    func addEntry(text: String, mood: String?, stickerNames: [String],
                  song: DiarySong90?) -> DiaryEntry99 {
        let entry = DiaryEntry99(
            id: UUID().uuidString,
            dateKey: Self.dateKey(for: Date()),
            createdAt: Date().timeIntervalSince1970,
            text: text, mood: mood, stickerNames: stickerNames,
            songId: song?.id, songTitle: song?.title, songArtist: song?.artist,
            songArtwork: song?.artwork, fromDraft: false)
        entries.insert(entry, at: 0)
        editorAutosave = ""
        save()
        Breadcrumbs.log("p99 diary save")
        return entry
    }

    func updateEntry(_ entry: DiaryEntry99) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        save()
        Breadcrumbs.log("p99 diary save")
    }

    /// 删除进回收站（可恢复）。
    func trashEntry(id: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        trashed.insert(entries.remove(at: idx), at: 0)
        save()
    }

    func restoreEntry(id: String) {
        guard let idx = trashed.firstIndex(where: { $0.id == id }) else { return }
        entries.insert(trashed.remove(at: idx), at: 0)
        entries.sort { $0.createdAt > $1.createdAt }
        save()
    }

    func purgeEntry(id: String) {
        trashed.removeAll { $0.id == id }
        save()
    }

    func setEditorAutosave(_ text: String) {
        guard editorAutosave != text else { return }
        editorAutosave = text
        save()
    }

    // MARK: - 派生视图

    /// 时间轴：按日倒序分组。
    func entriesByDay() -> [(day: String, items: [DiaryEntry99])] {
        var order: [String] = []
        var map: [String: [DiaryEntry99]] = [:]
        for entry in entries.sorted(by: { $0.createdAt > $1.createdAt }) {
            if map[entry.dateKey] == nil { order.append(entry.dateKey) }
            map[entry.dateKey, default: []].append(entry)
        }
        return order.map { (day: $0, items: map[$0] ?? []) }
    }

    func entries(onDayKey key: String) -> [DiaryEntry99] {
        entries.filter { $0.dateKey == key }.sorted { $0.createdAt > $1.createdAt }
    }

    var daysWithEntries: Set<String> { Set(entries.map(\.dateKey)) }

    /// 往年今日：同月同日、年份不同于今年的条目（无则空，不硬凑）。
    func onThisDayPastYears() -> [DiaryEntry99] {
        let now = Date()
        let cal = Calendar.current
        let month = cal.component(.month, from: now)
        let day = cal.component(.day, from: now)
        let year = cal.component(.year, from: now)
        return entries.filter { entry in
            let date = Date(timeIntervalSince1970: entry.createdAt)
            return cal.component(.month, from: date) == month
                && cal.component(.day, from: date) == day
                && cal.component(.year, from: date) != year
        }
    }

    /// 歌曲聚合：按 songId 分组（无挂歌条目不入），按条数多者在前。
    func entriesBySong() -> [(song: DiarySong90, items: [DiaryEntry99])] {
        var map: [String: (song: DiarySong90, items: [DiaryEntry99])] = [:]
        for entry in entries {
            guard let songId = entry.songId, let title = entry.songTitle else { continue }
            let song = DiarySong90(id: songId, title: title,
                                   artist: entry.songArtist ?? "",
                                   artwork: entry.songArtwork)
            if map[songId] == nil { map[songId] = (song, []) }
            map[songId]?.items.append(entry)
        }
        return map.values
            .map { (song: $0.song, items: $0.items.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.items.count > $1.items.count }
    }

    // MARK: - 落盘

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        entries = file.entries
        trashed = file.trashed
        draftConfirmedKey = file.draftConfirmedKey
        editorAutosave = file.editorAutosave
    }

    private func save() {
        let file = Persisted(entries: entries, trashed: trashed,
                             draftConfirmedKey: draftConfirmedKey,
                             editorAutosave: editorAutosave)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Fluent 3D 贴纸目录（37 张，样板同源素材）

struct DiarySticker99: Identifiable {
    /// 相对路径 <类>/<名>（不含扩展名），落进条目 stickerNames。
    var id: String { relativeName }
    let relativeName: String
    let category: String

    /// bundle 内实文件（folder reference Resources/Diary → "Diary/Stickers/..."）。
    var image: UIImage? {
        let parts = relativeName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        if let url = Bundle.main.url(forResource: String(parts[1]), withExtension: "png",
                                     subdirectory: "Diary/Stickers/\(parts[0])") {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    static let all: [DiarySticker99] = {
        let catalog: [(String, [String])] = [
            ("faces", ["crying_face_3d", "face_blowing_a_kiss_3d", "face_with_tears_of_joy_3d",
                       "pensive_face_3d", "sleeping_face_3d", "smiling_face_with_heart-eyes_3d",
                       "smiling_face_with_hearts_3d", "smiling_face_with_smiling_eyes_3d",
                       "star-struck_3d", "thinking_face_3d", "winking_face_3d", "yawning_face_3d"]),
            ("animals", ["bear_3d", "bird_3d", "butterfly_3d", "cat_face_3d", "dog_face_3d",
                         "fox_3d", "panda_3d", "rabbit_face_3d"]),
            ("music_daily", ["blossom_3d", "cloud_with_rain_3d", "crescent_moon_3d", "guitar_3d",
                             "headphone_3d", "hot_beverage_3d", "microphone_3d", "musical_note_3d",
                             "musical_notes_3d", "musical_score_3d", "open_book_3d", "optical_disk_3d",
                             "radio_3d", "red_heart_3d", "sparkles_3d", "sparkling_heart_3d",
                             "sunflower_3d"]),
        ]
        return catalog.flatMap { category, names in
            names.map { DiarySticker99(relativeName: "\(category)/\($0)", category: category) }
        }
    }()

    static func named(_ relativeName: String) -> DiarySticker99? {
        all.first { $0.relativeName == relativeName }
    }
}
