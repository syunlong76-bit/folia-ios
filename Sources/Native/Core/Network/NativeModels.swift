import Foundation

/// M1 原生数据模型（网易云一期）。字段与 Web 侧 omni 归一化口径对齐
/// 的最小子集：墙与详情 MVP 需要什么就有什么，不预埋多余字段。
/// API 的 id 在 JSON 里是数字，统一转 String（与 Web 侧 String(id) 一致）。

struct NativePlaylistSummary: Equatable {
    let id: String
    let name: String
    let coverUrl: String?
    let trackCount: Int
    let playCount: Int
    /// 网易云标记：5 = 「我喜欢的音乐」（且创建者为本人时）。
    let specialType: Int
    let creatorId: String?
    let creatorName: String?

    var isLikedCollection: Bool { specialType == 5 }
}

struct NativePlaylistDetail: Equatable {
    let id: String
    let name: String
    let coverUrl: String?
    let creatorName: String?
    let trackCount: Int
    let playCount: Int
    let detailText: String?
    /// 全量曲目 id（顺序即歌单序）——分页队列模型的骨架（规格 §3）。
    let trackIds: [String]
    /// 详情响应内嵌的完整曲目（3.7 (7) 实测：/playlist/detail 直接
    /// 带全部曲目对象，338/338 首全在——曲目墙可一次调用立全墙，
    /// 不必再走 track/all 分页；超大歌单内嵌可能截断，缺口再分页补）。
    let tracks: [NativeTrack]
}

struct NativeTrack: Equatable {
    let id: String
    let name: String
    let artists: String
    let albumName: String?
    let picUrl: String?
    /// 时长（毫秒）。
    let durationMs: Int
}

// MARK: - JSON 松散取值（API 数字/字符串混杂，逐个兜底）

enum NativeJSON {
    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    static func int(_ value: Any?) -> Int {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    static func dict(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func array(_ value: Any?) -> [[String: Any]] {
        (value as? [[String: Any]]) ?? []
    }
}

// MARK: - 原始响应解析

enum NativeParse {

    static func playlistSummary(_ raw: [String: Any]) -> NativePlaylistSummary? {
        guard let id = NativeJSON.string(raw["id"]) else { return nil }
        let creator = NativeJSON.dict(raw["creator"])
        return NativePlaylistSummary(
            id: id,
            name: NativeJSON.string(raw["name"]) ?? "",
            coverUrl: NativeJSON.string(raw["coverImgUrl"]) ?? NativeJSON.string(raw["picUrl"]),
            trackCount: NativeJSON.int(raw["trackCount"]),
            playCount: NativeJSON.int(raw["playCount"]),
            specialType: NativeJSON.int(raw["specialType"]),
            creatorId: creator.flatMap { NativeJSON.string($0["userId"]) } ?? NativeJSON.string(raw["userId"]),
            creatorName: creator.flatMap { NativeJSON.string($0["nickname"]) }
        )
    }

    static func playlistDetail(_ raw: [String: Any]) -> NativePlaylistDetail? {
        guard let playlist = NativeJSON.dict(raw["playlist"]),
              let id = NativeJSON.string(playlist["id"]) else { return nil }
        let creator = NativeJSON.dict(playlist["creator"])
        var ids: [String] = []
        if let trackIds = playlist["trackIds"] as? [[String: Any]] {
            ids = trackIds.compactMap { NativeJSON.string($0["id"]) }
        }
        return NativePlaylistDetail(
            id: id,
            name: NativeJSON.string(playlist["name"]) ?? "",
            coverUrl: NativeJSON.string(playlist["coverImgUrl"]),
            creatorName: creator.flatMap { NativeJSON.string($0["nickname"]) },
            trackCount: NativeJSON.int(playlist["trackCount"]),
            playCount: NativeJSON.int(playlist["playCount"]),
            detailText: NativeJSON.string(playlist["description"]),
            trackIds: ids,
            tracks: NativeJSON.array(playlist["tracks"]).compactMap(track)
        )
    }

    static func track(_ raw: [String: Any]) -> NativeTrack? {
        guard let id = NativeJSON.string(raw["id"]) else { return nil }
        var artistNames: [String] = []
        if let ars = raw["ar"] as? [[String: Any]] {
            artistNames = ars.compactMap { NativeJSON.string($0["name"]) }
        }
        let album = NativeJSON.dict(raw["al"])
        return NativeTrack(
            id: id,
            name: NativeJSON.string(raw["name"]) ?? "",
            artists: artistNames.joined(separator: " / "),
            albumName: album.flatMap { NativeJSON.string($0["name"]) },
            picUrl: album.flatMap { NativeJSON.string($0["picUrl"]) },
            durationMs: NativeJSON.int(raw["dt"])
        )
    }
}
