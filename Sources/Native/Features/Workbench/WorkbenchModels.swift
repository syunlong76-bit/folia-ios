import Foundation

// WorkbenchModels.swift
//
// (53) A 组工作台的数据模型与宽松解析。网页版对照（folia-major）：
// - 收藏专辑：netease.ts getFavoriteAlbums → `/album/sublist`，
//   响应 `data[]`（id/name/picUrl/size/artists[]），见
//   neteaseProvider.getUserAlbums 与 onlineHomeFeeds 的收藏专辑 feed。
// - 电台 feed：omni.getHomeFeed 三路并行（onlineHomeFeeds.service
//   createRadioFeed）——私人 FM `/personal_fm`、每日推荐
//   `/recommend/songs`、推荐歌单 `/recommend/resource`，任一路失败
//   只空该路（partial），三路全空才算整份失败；原生侧同口径。
// NativeModels.swift 不在本工作流可改清单内，故模型与解析都落本文件；
// NativeParse 既有解析（playlistSummary/track）能复用的直接复用。

/// 收藏专辑摘要（/album/sublist 的 data[] 一条）。
struct WorkbenchAlbumSummary: Equatable {
    let id: String
    let name: String
    let coverUrl: String?
    /// 歌手名（artists 拼接），无则空串。
    let artistLabel: String
    /// 曲目数（size），接口没给时为 0。
    let trackCount: Int
}

enum WorkbenchParse {

    /// /album/sublist 一条 → 专辑摘要。字段口径照 netease.ts
    /// getFavoriteAlbums 的归一化前形状（picUrl 已在网页侧升 https，
    /// 原生侧封面加载器内部同样升 https，此处原样保留）。
    static func albumSummary(_ raw: [String: Any]) -> WorkbenchAlbumSummary? {
        guard let id = NativeJSON.string(raw["id"]) else { return nil }
        var artists: [String] = []
        if let list = raw["artists"] as? [[String: Any]] {
            artists = list.compactMap { NativeJSON.string($0["name"]) }
        }
        if artists.isEmpty, let single = NativeJSON.dict(raw["artist"]),
           let name = NativeJSON.string(single["name"]) {
            artists = [name]
        }
        return WorkbenchAlbumSummary(
            id: id,
            name: NativeJSON.string(raw["name"]) ?? "",
            coverUrl: NativeJSON.string(raw["picUrl"]),
            artistLabel: artists.filter { !$0.isEmpty }.joined(separator: " / "),
            trackCount: NativeJSON.int(raw["size"]))
    }

    /// 宽松单曲解析：电台两路（/personal_fm 的 data[]、
    /// /recommend/songs 的 dailySongs[]）的歌曲形状新旧键混杂
    /// （ar/artists、al/album、dt/duration），NativeParse.track 只认
    /// 旧键，故这里两套都认；privilege 内嵌 fee 一并带出（不可播标记）。
    static func flexibleTrack(_ raw: [String: Any]) -> NativeTrack? {
        guard let id = NativeJSON.string(raw["id"]) else { return nil }
        var artistNames: [String] = []
        if let list = (raw["ar"] as? [[String: Any]]) ?? (raw["artists"] as? [[String: Any]]) {
            artistNames = list.compactMap { NativeJSON.string($0["name"]) }
        }
        let album = NativeJSON.dict(raw["al"]) ?? NativeJSON.dict(raw["album"])
        var durationMs = NativeJSON.int(raw["dt"])
        if durationMs == 0 { durationMs = NativeJSON.int(raw["duration"]) }
        return NativeTrack(
            id: id,
            name: NativeJSON.string(raw["name"]) ?? "",
            artists: artistNames.joined(separator: " / "),
            albumName: album.flatMap { NativeJSON.string($0["name"]) },
            picUrl: album.flatMap {
                NativeJSON.string($0["picUrl"]) ?? NativeJSON.string($0["coverUrl"])
            },
            durationMs: durationMs)
    }
}

/// NativeTrack → FoliaTrack：与浏览面（Search/Explore/Collection）
/// 的 id 口径统一为 `ncm_<数字 id>`（取流侧 fetchSongStreamURL 会
/// 剥前缀，裸 id 与带前缀等价；统一前缀防同一首歌在播放历史里
/// 以两种 id 重复记账）。已带前缀或非纯数字 id 原样保留。
func workbenchFoliaTrack(_ track: NativeTrack) -> FoliaTrack {
    let rawId = track.id
    let foliaId: String
    if rawId.hasPrefix("ncm_") || Int(rawId) == nil {
        foliaId = rawId
    } else {
        foliaId = "ncm_\(rawId)"
    }
    return FoliaTrack(
        id: foliaId,
        sourceType: .netease,
        title: track.name,
        artist: track.artists,
        album: track.albumName ?? "",
        duration: Double(track.durationMs) / 1000,
        artworkURL: track.picUrl.flatMap { URL(string: $0) })
}
