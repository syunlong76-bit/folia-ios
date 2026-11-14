// DatabaseManager.swift
//
// M1 播放内核：SQLite 统一曲库（native-arch.md §7）。
// - 四表：tracks / playlists / playlist_tracks / play_history
//   （表结构采用骨架第一批 §三，并加以下定版）。
// - remote_stream_url 列仅作元数据缓存，禁止作为播放地址直接使用
//   （平台 CDN 地址会过期，播放一律按 id 现换；本文件不提供任何
//   读取该列作播放地址的接口）。
// - 所有文件路径字段只存沙盒相对路径（LocalAudio/…、Cache/Covers/…、
//   Cache/Lyrics/…），动态拼接 FileManager.documentDirectory；
//   绝对路径含容器 UUID，重装即失效。
// - SQLite 加 user_version 迁移框架（当前版本 1；后续迁移按
//   `if version < N` 追加，不改旧分支）。
// - M1 范围：表结构 + upsertTrack 基础 + 播放流水记账；
//   Importer / LRU 全量在 M3（本文件只留接口占位，不展开）。

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DatabaseManager {

    static let shared = DatabaseManager()

    /// 当前 schema 版本。升版时：建表处不动，在 migrateIfNeeded 里追加
    /// `if version < N { ...; }`，最后 PRAGMA user_version = N。
    private let currentSchemaVersion = 1

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.folia.database", qos: .utility)

    private init() {
        openDatabase()
        migrateIfNeeded()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - 打开 / 迁移

    private func openDatabase() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbURL = documents.appendingPathComponent("folia.db")
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            NSLog("[DatabaseManager] sqlite3_open failed: \(dbURL.path)")
            db = nil
        } else {
            sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        }
    }

    private func userVersion() -> Int {
        var version = 0
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            version = Int(sqlite3_column_int(stmt, 0))
        }
        return version
    }

    private func migrateIfNeeded() {
        guard let db else { return }
        let version = userVersion()
        queue.sync {
            if version < 1 {
                self.createSchemaV1()
                self.setUserVersion(1)
            }
            // 后续迁移在此追加：if version < 2 { ...; setUserVersion(2) }
        }
    }

    private func setUserVersion(_ version: Int) {
        sqlite3_exec(db, "PRAGMA user_version = \(version);", nil, nil, nil)
    }

    private func createSchemaV1() {
        let sql = """
        CREATE TABLE IF NOT EXISTS tracks (
            id TEXT PRIMARY KEY,
            source_type TEXT NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL DEFAULT '未知歌手',
            album TEXT NOT NULL DEFAULT '',
            duration_ms INTEGER NOT NULL DEFAULT 0,
            local_audio_rel_path TEXT,
            local_artwork_rel_path TEXT,
            local_lrc_rel_path TEXT,
            custom_bg_rel_path TEXT,
            -- 元数据缓存列：仅记录最后一次取到的流地址供排查，禁止作为播放地址使用。
            remote_stream_url TEXT,
            monet_primary_hex TEXT,
            monet_secondary_hex TEXT,
            lufs_gain REAL DEFAULT 0.0,
            bpm REAL,
            is_liked INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS playlists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            cover_rel_path TEXT,
            monet_primary_hex TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS playlist_tracks (
            playlist_id TEXT NOT NULL,
            track_id TEXT NOT NULL,
            position INTEGER NOT NULL,
            added_at INTEGER NOT NULL,
            PRIMARY KEY (playlist_id, track_id),
            FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
            FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS play_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id TEXT NOT NULL,
            played_at INTEGER NOT NULL,
            listened_ms INTEGER NOT NULL,
            is_completed INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_tracks_liked ON tracks(is_liked);
        CREATE INDEX IF NOT EXISTS idx_history_track_time ON play_history(track_id, played_at);
        """
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            NSLog("[DatabaseManager] createSchemaV1 failed: \(message)")
            sqlite3_free(errorMessage)
        }
    }

    // MARK: - 曲目 upsert（基础）

    /// 曲目元数据 upsert。只写元数据字段；不写 remote_stream_url（播放地址永不落库）。
    /// 扩展字段（monet/lufs/bpm/customBg）由 updateTrackExtensions 单独更新。
    func upsertTrack(_ track: FoliaTrack) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = """
            INSERT INTO tracks (id, source_type, title, artist, album, duration_ms, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                source_type = excluded.source_type,
                title = excluded.title,
                artist = excluded.artist,
                album = excluded.album,
                duration_ms = excluded.duration_ms;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                NSLog("[DatabaseManager] upsertTrack prepare failed")
                return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, track.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, track.sourceType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, track.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, track.artist, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, track.album, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, Int64(track.duration * 1000))
            sqlite3_bind_int64(stmt, 7, Int64(Date().timeIntervalSince1970))
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("[DatabaseManager] upsertTrack step failed for \(track.id)")
            }
        }
    }

    /// 更新扩展字段（monet/lufs/bpm/customBg）。M1 只留接口，由 M3 导入/取色链路调用。
    func updateTrackExtensions(
        id: String,
        monetPrimaryHex: String? = nil,
        monetSecondaryHex: String? = nil,
        lufsGain: Double? = nil,
        bpm: Double? = nil,
        customBgRelPath: String? = nil
    ) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = """
            UPDATE tracks SET
                monet_primary_hex = COALESCE(?, monet_primary_hex),
                monet_secondary_hex = COALESCE(?, monet_secondary_hex),
                lufs_gain = COALESCE(?, lufs_gain),
                bpm = COALESCE(?, bpm),
                custom_bg_rel_path = COALESCE(?, custom_bg_rel_path)
            WHERE id = ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            Self.bindNullableText(stmt, 1, monetPrimaryHex)
            Self.bindNullableText(stmt, 2, monetSecondaryHex)
            if let lufsGain { sqlite3_bind_double(stmt, 3, lufsGain) } else { sqlite3_bind_null(stmt, 3) }
            if let bpm { sqlite3_bind_double(stmt, 4, bpm) } else { sqlite3_bind_null(stmt, 4) }
            Self.bindNullableText(stmt, 5, customBgRelPath)
            sqlite3_bind_text(stmt, 6, id, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("[DatabaseManager] updateTrackExtensions failed for \(id)")
            }
        }
    }

    // MARK: - 读（供 QueueManager 本地曲目解析）

    /// 按 id 读曲目元数据。注意：artworkURL 不入库（搜索时态字段），返回 nil；
    /// 本地封面走 local_artwork_rel_path（M3 填充）。
    func fetchTrack(id: String) -> FoliaTrack? {
        queue.sync { [weak self] in
            guard let self, let db = self.db else { return nil }
            let sql = "SELECT id, source_type, title, artist, album, duration_ms FROM tracks WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let trackId = Self.columnText(stmt, 0) ?? id
            let sourceRaw = Self.columnText(stmt, 1) ?? "netease"
            return FoliaTrack(
                id: trackId,
                sourceType: AudioSourceType(rawValue: sourceRaw) ?? .netease,
                title: Self.columnText(stmt, 2) ?? "",
                artist: Self.columnText(stmt, 3) ?? "未知歌手",
                album: Self.columnText(stmt, 4) ?? "",
                duration: Double(sqlite3_column_int64(stmt, 5)) / 1000.0,
                artworkURL: nil
            )
        }
    }

    /// 本地音频沙盒相对路径（供 QueueManager 拼 file URL）。无记录返回 nil。
    func localAudioRelPath(trackId: String) -> String? {
        queue.sync { [weak self] in
            guard let self, let db = self.db else { return nil }
            let sql = "SELECT local_audio_rel_path FROM tracks WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trackId, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return Self.columnText(stmt, 0)
        }
    }

    // MARK: - 播放流水

    /// 记一条播放流水。调用方（PlaybackEngine）保证单曲累计 >= 15 秒才调。
    func recordPlayHistory(trackId: String, listenedMs: Int, isCompleted: Bool, playedAt: Date = Date()) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = "INSERT INTO play_history (track_id, played_at, listened_ms, is_completed) VALUES (?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trackId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(playedAt.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 3, Int64(listenedMs))
            sqlite3_bind_int(stmt, 4, isCompleted ? 1 : 0)
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("[DatabaseManager] recordPlayHistory failed for \(trackId)")
            }
        }
    }

    // MARK: - 小工具

    private static func bindNullableText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }
}
