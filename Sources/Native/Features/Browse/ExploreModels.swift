import Foundation

// ExploreModels.swift
//
// 探索页条目模型（对应 folia-major 的 OmniExploreItem / ProviderCollection）。
// 歌曲直接用内核的 FoliaTrack；集合（歌单/专辑/歌手）用 ExploreCollection，
// 点开走 CollectionView 集合页。

/// 集合引用：探索卡片与集合页之间传递的最小信息。
struct ExploreCollection: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case playlist
        case album
        case artist
    }

    let kind: Kind
    let id: Int
    let name: String
    let coverURL: URL?
    /// 副文本（faceOf 规则：歌手名单 || 创建者昵称 || 种类词「歌单/专辑/歌手」；
    /// 榜单卡用服务端更新频率文案）。
    let subtitle: String

    var identity: String { "collection:\(kind.rawValue):\(id)" }

    /// 种类词（i18n home.explorePlaylist / exploreAlbum / exploreArtist）。
    var kindLabel: String {
        switch kind {
        case .playlist: return "歌单"
        case .album: return "专辑"
        case .artist: return "歌手"
        }
    }
}

/// 探索页一条条目：歌曲或集合。
enum ExploreItem: Identifiable {
    case song(FoliaTrack)
    case collection(ExploreCollection)

    var id: String {
        switch self {
        case .song(let track): return "song:\(track.id)"
        case .collection(let collection): return collection.identity
        }
    }

    var song: FoliaTrack? {
        if case .song(let track) = self { return track }
        return nil
    }
}

/// 一个探索分区（接口层产出；界面层再按 BATCH 分批展示）。
struct ExploreFeedSection {
    let id: String
    let title: String
    let items: [ExploreItem]
}
