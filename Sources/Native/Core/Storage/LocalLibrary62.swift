import AVFoundation
import Combine
import CryptoKit
import Foundation
import SQLite3
import UIKit

// LocalLibrary62.swift
//
// 3.7 (62) WC 簇 §8 本地曲库（L）：
// - 导入：UIDocumentPicker（音频多选/文件夹）选入的文件复制进
//   沙盒库目录 Documents/FoliaLocalLibrary/audio，AVAsset 解析
//   标题/歌手/专辑/时长/封面；文件夹以 security-scoped bookmark
//   落盘，重扫时重新访问并收新文件。
// - 索引：index.json（曲目元数据＋相对路径），FoliaTrack id 为
//   local_<内容指纹前 16 位>，与内核 id 口径一致。
// - 播放通路：QueueManager 的 .local 分支按 DatabaseManager
//   .localAudioRelPath 取相对路径——该列全仓无写入方（M3 未落），
//   本簇在导入时经 upsertTrack 建行后以 SQLite 直写补上该列
//   （folia.db 同库同表，相对路径相对 Documents）。集成建议：
//   DatabaseManager 增设 setLocalAudioRelPath 后可替换此旁路。
// - 本地歌词：LocalLyricSource62（WB 定义的钩子口径，签名按
//   合理形态实现，集成时主聊天对齐）——同目录同名 .lrc/.txt
//   伴随文件按「本地歌词格式顺序」键的次序取第一命中。

protocol LocalLyricSource62: AnyObject {
    /// 本地伴随歌词原文（LRC/TXT 文本）；无则 nil。
    func localLyricText(for track: FoliaTrack) -> String?
    /// 本地伴随歌词文件 URL；无则 nil。
    func localLyricFileURL(for track: FoliaTrack) -> URL?
}

/// SQLite 文本绑定析构标记（与 DatabaseManager 同写法；该常量
/// 在其文件内为 private，本文件自备一份）。
private let SQLITE_TRANSIENT62 = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class LocalLibrary62: ObservableObject, LocalLyricSource62 {

    static let shared = LocalLibrary62()

    enum SortMode: String, CaseIterable {
        case added = "导入顺序"
        case title = "标题"
        case artist = "歌手"
        case album = "专辑"
    }

    struct ImportedFolder: Codable, Identifiable {
        var id: String
        var displayName: String
        var bookmark: Data
    }

    @Published private(set) var tracks: [FoliaTrack] = []
    @Published private(set) var folders: [ImportedFolder] = []
    @Published var sortMode: SortMode = .added

    private struct IndexEntry: Codable {
        var track: FoliaTrack
        var audioRelPath: String
        var artworkRelPath: String?
        var addedAt: TimeInterval
    }

    private var entries: [IndexEntry] = []

    var rootDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoliaLocalLibrary", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent("art"), withIntermediateDirectories: true)
        return dir
    }
    private var indexURL: URL { rootDir.appendingPathComponent("index.json") }
    private var foldersKey: String { "folia62.localLibrary.folders" }

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "flac", "aac", "ogg", "aif", "aiff", "caf",
    ]

    private init() {
        loadIndex()
        loadFolders()
        if SettingsStore.autoScanImportedFolders62 { rescanFolders() }
    }

    // MARK: - 查询（四视图数据源）

    func sortedTracks() -> [FoliaTrack] {
        switch sortMode {
        case .added: return tracks
        case .title: return tracks.sorted { $0.title < $1.title }
        case .artist: return tracks.sorted { $0.artist < $1.artist }
        case .album: return tracks.sorted { $0.album < $1.album }
        }
    }

    func albums() -> [(name: String, artist: String, tracks: [FoliaTrack])] {
        let grouped = Dictionary(grouping: sortedTracks()) {
            $0.album.isEmpty ? "未知专辑" : $0.album
        }
        return grouped.map { (name: $0.key, artist: $0.value.first?.artist ?? "", tracks: $0.value) }
            .sorted { $0.name < $1.name }
    }

    func artists() -> [(name: String, tracks: [FoliaTrack])] {
        let grouped = Dictionary(grouping: sortedTracks()) { $0.artist }
        return grouped.map { (name: $0.key, tracks: $0.value) }
            .sorted { $0.name < $1.name }
    }

    func artworkImage(for trackId: String) -> UIImage? {
        guard let entry = entries.first(where: { $0.track.id == trackId }),
              let rel = entry.artworkRelPath else { return nil }
        return UIImage(contentsOfFile: rootDir.appendingPathComponent(rel).path)
    }

    func audioFileURL(for trackId: String) -> URL? {
        guard let entry = entries.first(where: { $0.track.id == trackId }) else { return nil }
        return rootDir.appendingPathComponent(entry.audioRelPath)
    }

    // MARK: - 导入

    /// 导入一批文件 URL（picker 回调）：逐个复制＋解析＋登记。
    /// 返回成功导入数。文件夹 URL 走 registerFolder＋展开导入。
    @discardableResult
    func importFiles(urls: [URL]) async -> Int {
        var count = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                registerFolder(url: url)
                count += await importFolderContents(url: url)
            } else if Self.audioExtensions.contains(url.pathExtension.lowercased()) {
                if await importOne(source: url) != nil { count += 1 }
            }
        }
        Breadcrumbs.log("locallibrary62.import done n=\(count) total=\(tracks.count)")
        return count
    }

    private func importFolderContents(url: URL) async -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        while let file = enumerator.nextObject() as? URL {
            if Self.audioExtensions.contains(file.pathExtension.lowercased()) {
                if await importOne(source: file) != nil { count += 1 }
            }
        }
        return count
    }

    private func importOne(source: URL) async -> FoliaTrack? {
        do {
            let data = try Data(contentsOf: source)
            let fingerprint = MD5Hex62.of(data: data).prefix(16)
            let trackId = "local_\(fingerprint)"
            if entries.contains(where: { $0.track.id == trackId }) {
                return tracks.first { $0.id == trackId }
            }
            let ext = source.pathExtension.isEmpty ? "mp3" : source.pathExtension
            let fileName = "\(fingerprint).\(ext)"
            let dest = rootDir.appendingPathComponent("audio").appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try data.write(to: dest, options: .atomic)
            }
            // 伴随歌词一并收进库目录（同名 .lrc/.txt）。
            let base = source.deletingPathExtension()
            for lyricExt in ["lrc", "txt"] {
                let lyricSource = base.appendingPathExtension(lyricExt)
                let lyricDest = rootDir.appendingPathComponent("audio")
                    .appendingPathComponent("\(fingerprint).\(lyricExt)")
                if FileManager.default.fileExists(atPath: lyricSource.path),
                   !FileManager.default.fileExists(atPath: lyricDest.path) {
                    try? FileManager.default.copyItem(at: lyricSource, to: lyricDest)
                }
            }
            let meta = await Self.parseMetadata(url: dest, fallbackName: source.lastPathComponent)
            var artworkRel: String? = nil
            if let imageData = meta.artworkData {
                let artName = "\(fingerprint).jpg"
                let artDest = rootDir.appendingPathComponent("art").appendingPathComponent(artName)
                if (try? imageData.write(to: artDest, options: .atomic)) != nil {
                    artworkRel = "art/\(artName)"
                }
            }
            let track = FoliaTrack(
                id: trackId, sourceType: .local,
                title: meta.title, artist: meta.artist, album: meta.album,
                duration: meta.duration)
            let entry = IndexEntry(
                track: track, audioRelPath: "audio/\(fileName)",
                artworkRelPath: artworkRel, addedAt: Date().timeIntervalSince1970)
            await MainActor.run {
                self.entries.append(entry)
                self.tracks.append(track)
                self.saveIndex()
            }
            registerWithDatabase(track: track, audioRelPath: "FoliaLocalLibrary/audio/\(fileName)")
            return track
        } catch {
            Breadcrumbs.log("locallibrary62.importOne fail err=\(error.localizedDescription)")
            return nil
        }
    }

    private struct Metadata {
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var artworkData: Data?
    }

    private static func parseMetadata(url: URL, fallbackName: String) async -> Metadata {
        let asset = AVURLAsset(url: url)
        var title = (fallbackName as NSString).deletingPathExtension
        var artist = "未知歌手"
        var album = ""
        var artworkData: Data?
        let durationSeconds = (try? await asset.load(.duration))?.seconds ?? 0
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue), !value.isEmpty { title = value }
                case .commonKeyArtist:
                    if let value = try? await item.load(.stringValue), !value.isEmpty { artist = value }
                case .commonKeyAlbumName:
                    if let value = try? await item.load(.stringValue) { album = value }
                case .commonKeyArtwork:
                    artworkData = try? await item.load(.dataValue)
                default:
                    break
                }
            }
        }
        return Metadata(title: title, artist: artist, album: album,
                        duration: durationSeconds.isFinite ? durationSeconds : 0,
                        artworkData: artworkData)
    }

    /// 登记到内核 DB：upsertTrack 建行（异步）后直写
    /// local_audio_rel_path 列（重试兜底异步次序）。
    private func registerWithDatabase(track: FoliaTrack, audioRelPath: String, attempt: Int = 0) {
        DatabaseManager.shared.upsertTrack(track)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4) {
            if Self.writeLocalRelPath(trackId: track.id, relPath: audioRelPath) {
                Breadcrumbs.log("locallibrary62.db registered id=\(track.id)")
            } else if attempt < 3 {
                self.registerWithDatabase(track: track, audioRelPath: audioRelPath, attempt: attempt + 1)
            } else {
                Breadcrumbs.log("locallibrary62.db register FAIL id=\(track.id)")
            }
        }
    }

    private static func writeLocalRelPath(trackId: String, relPath: String) -> Bool {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbURL = documents.appendingPathComponent("folia.db")
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "UPDATE tracks SET local_audio_rel_path = ? WHERE id = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, relPath, -1, SQLITE_TRANSIENT62)
        sqlite3_bind_text(stmt, 2, trackId, -1, SQLITE_TRANSIENT62)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return false }
        return sqlite3_changes(db) > 0
    }

    // MARK: - 文件夹（bookmark 落盘＋重扫；监视差异见设置 hint）

    private func registerFolder(url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        if folders.contains(where: { $0.displayName == url.lastPathComponent }) { return }
        folders.append(ImportedFolder(
            id: UUID().uuidString, displayName: url.lastPathComponent, bookmark: bookmark))
        saveFolders()
        Breadcrumbs.log("locallibrary62.folder added name=\(url.lastPathComponent)")
    }

    /// 移除一个已导入目录的登记（库内已复制文件保留）。
    func removeFolder(id: String) {
        folders.removeAll { $0.id == id }
        saveFolders()
        Breadcrumbs.log("locallibrary62.folder removed id=\(id)")
    }

    /// 重扫全部已登记文件夹：bookmark 解开→访问→收新文件。
    /// iOS 无常驻文件夹监视：启动时（开关开）与手动触发时执行。
    func rescanFolders() {
        let snapshot = folders
        guard !snapshot.isEmpty else { return }
        Task {
            var added = 0
            for folder in snapshot {
                var stale = false
                guard let url = try? URL(resolvingBookmarkData: folder.bookmark,
                                         options: .withSecurityScope, relativeTo: nil,
                                         bookmarkDataIsStale: &stale) else { continue }
                let scoped = url.startAccessingSecurityScopedResource()
                added += await self.importFolderContents(url: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            Breadcrumbs.log("locallibrary62.rescan added=\(added) folders=\(snapshot.count)")
        }
    }

    /// 删除一首本地曲（文件＋索引＋歌词伴随文件）。
    func removeTrack(trackId: String) {
        guard let entry = entries.first(where: { $0.track.id == trackId }) else { return }
        try? FileManager.default.removeItem(at: rootDir.appendingPathComponent(entry.audioRelPath))
        if let art = entry.artworkRelPath {
            try? FileManager.default.removeItem(at: rootDir.appendingPathComponent(art))
        }
        for ext in ["lrc", "txt"] {
            let name = (entry.audioRelPath as NSString).lastPathComponent
            let base = (name as NSString).deletingPathExtension
            try? FileManager.default.removeItem(
                at: rootDir.appendingPathComponent("audio").appendingPathComponent("\(base).\(ext)"))
        }
        entries.removeAll { $0.track.id == trackId }
        tracks.removeAll { $0.id == trackId }
        saveIndex()
        Breadcrumbs.log("locallibrary62.remove id=\(trackId)")
    }

    // MARK: - LocalLyricSource62

    func localLyricFileURL(for track: FoliaTrack) -> URL? {
        guard track.sourceType == .local,
              let entry = entries.first(where: { $0.track.id == track.id }) else { return nil }
        let order = SettingsStore.localLyricFormatOrder62
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        let base = (entry.audioRelPath as NSString).deletingPathExtension
        for ext in order.isEmpty ? ["lrc", "txt"] : order {
            let candidate = rootDir.appendingPathComponent("\(base).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    func localLyricText(for track: FoliaTrack) -> String? {
        guard let url = localLyricFileURL(for: track) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 落盘

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([IndexEntry].self, from: data)
        else { return }
        entries = decoded
        tracks = decoded.map { $0.track }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: foldersKey),
              let decoded = try? JSONDecoder().decode([ImportedFolder].self, from: data)
        else { return }
        folders = decoded
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: foldersKey)
    }
}
