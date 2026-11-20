import Foundation

// LocalPlaylistStore.swift
//
// 本机命名歌单（3.7 (50)，(48) 挂账②「保存队列为歌单」）：
// 把当前播放队列整队命名存到本机，之后可从队列面板整队载
// 入。最小实现：整表 [LocalPlaylist] 一份 JSON 落盘
// Documents/folia-local-playlists.json（照 PlayHistoryStore
// 模板：FoliaTrack 本身 Codable、原子写）。曲目只存元数据
// （id/来源/标题/歌手/专辑/时长/封面/fee），播放在线地址按
// id 现换（与队列快照同一口径）。不存 currentIndex/playMode
// ——歌单是曲目集合，不是播放会话（会话恢复归队列快照）。
// 上限 50 个歌单防误存膨胀；同名可重存（各存一份，删除在
// 队列面板歌单行左滑）。

final class LocalPlaylistStore: ObservableObject {

    static let shared = LocalPlaylistStore()

    struct LocalPlaylist: Codable, Identifiable {
        var id: String
        var name: String
        var createdAt: TimeInterval
        var tracks: [FoliaTrack]
    }

    @Published private(set) var playlists: [LocalPlaylist] = []

    private let fileURL: URL
    private static let maxPlaylists = 50

    private init() {
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("folia-local-playlists.json")
        load()
    }

    /// 保存当前队列为一个命名歌单（新歌单在前）。队列为空
    /// 或名称为空白时拒绝并返回 nil。
    @discardableResult
    func saveQueue(named rawName: String, tracks: [FoliaTrack]) -> LocalPlaylist? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !tracks.isEmpty else { return nil }
        let playlist = LocalPlaylist(
            id: UUID().uuidString,
            name: name,
            createdAt: Date().timeIntervalSince1970,
            tracks: tracks)
        playlists.insert(playlist, at: 0)
        if playlists.count > Self.maxPlaylists {
            playlists.removeLast(playlists.count - Self.maxPlaylists)
        }
        save()
        Breadcrumbs.log("localPlaylist.save name=\(name) tracks=\(tracks.count) total=\(playlists.count)")
        return playlist
    }

    func delete(id: String) {
        let before = playlists.count
        playlists.removeAll { $0.id == id }
        guard playlists.count != before else { return }
        save()
        Breadcrumbs.log("localPlaylist.delete id=\(id) total=\(playlists.count)")
    }

    func playlist(id: String) -> LocalPlaylist? {
        playlists.first { $0.id == id }
    }

    /// 向既有本机歌单追加一首（3.7 (55) 协调者集成，收藏到
    /// 歌单弹层消费）：歌单不存在或已含同 id 曲目时拒绝并
    /// 返回 false（防重复），成功落盘并返回 true。
    @discardableResult
    func addTrack(_ track: FoliaTrack, toPlaylist id: String) -> Bool {
        guard let index = playlists.firstIndex(where: { $0.id == id }),
              !playlists[index].tracks.contains(where: { $0.id == track.id })
        else { return false }
        playlists[index].tracks.append(track)
        save()
        Breadcrumbs.log("localPlaylist.addTrack playlist=\(id) track=\(track.id) total=\(playlists[index].tracks.count)")
        return true
    }

    // MARK: - 落盘

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(
                [LocalPlaylist].self, from: data) else { return }
        playlists = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
