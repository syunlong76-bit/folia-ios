import Foundation
import Combine

// SketchbookStore.swift
//
// 速记簿数据层（(53) 工作流 D；对应 folia-major 的
// src/stores/useScratchpadStore.ts）：本机的、跨来源的歌曲暂存区，
// 与播放队列分开（收进来不动正在播的队列）、与歌单分开（不在任何
// 平台上建东西）。条目按加入先后追加（记事本语义），按
// FoliaTrack.id 去重（原生 id 已带来源前缀 ncm_/qq_/kg_/local_，
// 与网页版 getPlaybackSongKey 同一身份口径），满 1000 条拒收不挤旧。
//
// 持久化照原生既有同类口径（LocalPlaylistStore / PlayHistoryStore
// 模板）：整表一份 JSON 落盘 Documents/folia-sketchbook.json、
// 原子写；曲目只存 FoliaTrack 元数据（id/来源/标题/歌手/专辑/
// 时长/封面/fee 本身即 Codable 最小集），播放在线地址按 id 现换，
// 不存任何流地址。网页版存 localStorage 键
// folia_scratchpad_entries（version 1 信封），原生按本机文件口径
// 落盘、语义对齐（去重/容量/追加序），不共享存储介质。

final class SketchbookStore: ObservableObject {

    static let shared = SketchbookStore()

    struct Entry: Codable {
        var track: FoliaTrack
        var addedAt: TimeInterval
        /// 收进来的出处小字（如「搜索」）；没有就不写（照网页版 origin）。
        var originLabel: String?
    }

    @Published private(set) var entries: [Entry] = []

    private let fileURL: URL
    /// 网页版 SCRATCHPAD_CAPACITY：满了拒收而不挤掉旧的。
    private static let capacity = 1000

    private init() {
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("folia-sketchbook.json")
        load()
    }

    // MARK: - 查询

    func contains(trackId: String) -> Bool {
        entries.contains { $0.track.id == trackId }
    }

    // MARK: - 增删

    /// 收进一首：已在里面或已满则拒收，返回是否真收下了。
    /// source 只进面包屑（如 search / drawer），不落盘。
    @discardableResult
    func add(_ track: FoliaTrack, source: String, originLabel: String? = nil) -> Bool {
        if contains(trackId: track.id) {
            Breadcrumbs.log("sketchbook.add source=\(source) id=\(track.id) dup=1")
            return false
        }
        guard entries.count < Self.capacity else {
            Breadcrumbs.log("sketchbook.add source=\(source) id=\(track.id) full=1")
            return false
        }
        entries.append(Entry(
            track: track,
            addedAt: Date().timeIntervalSince1970,
            originLabel: originLabel))
        save()
        Breadcrumbs.log("sketchbook.add source=\(source) id=\(track.id) total=\(entries.count)")
        return true
    }

    func remove(trackId: String, source: String) {
        let before = entries.count
        entries.removeAll { $0.track.id == trackId }
        guard entries.count != before else { return }
        save()
        Breadcrumbs.log("sketchbook.remove source=\(source) id=\(trackId) total=\(entries.count)")
    }

    func clear(source: String) {
        guard !entries.isEmpty else { return }
        entries = []
        save()
        Breadcrumbs.log("sketchbook.clear source=\(source)")
    }

    // MARK: - 落盘

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(
                [Entry].self, from: data) else { return }
        entries = decoded
        Breadcrumbs.log("sketchbook.load n=\(entries.count)")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
