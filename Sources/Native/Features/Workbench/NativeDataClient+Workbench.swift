import Foundation

// NativeDataClient+Workbench.swift
//
// (53) A 组工作台的数据通路（NativeDataClient 扩展，新文件、
// 既有方法零改动）。全部经既有 getJSON 走 LocalServer 同源代理
// （/api/netease 前缀通用转发，见 LocalServer.upstreamURLs：任意
// 子路径都转 EdgeOne 函数、失败回退 Netlify），且 getJSON 统一
// 附 `cookie=` 会话参数——电台与收藏专辑都是登录态接口，必须走
// 这条带会话的链，不能走匿名的 EdgeOneAPIClient 直连。
//
// 网页版对照（folia-major src/services/onlineMusic/netease/）：
// - 收藏专辑：netease.ts getFavoriteAlbums → /album/sublist
// - 私人 FM：netease.ts getPersonalFm → /personal_fm
// - 每日推荐：netease.ts getDailyRecommendedSongs → /recommend/songs
// - 推荐歌单：netease.ts getDailyRecommendedPlaylists → /recommend/resource
// 四条路由在网页侧均经 fetchWithCreds（带 cookie）调用，与本链同构。

extension NativeDataClient {

    /// 收藏专辑全量：按页拉 /album/sublist 直到接口说没有更多
    /// （网页侧 loadAllFavoriteAlbums 同口径：hasMore 且 offset
    /// 仍在前进才继续；原生侧响应无 hasMore 字段时以「本页满额」
    /// 近似，页大小 50 与网页侧 FAVORITE_ALBUMS_PAGE_SIZE 一致）。
    func fetchFavoriteAlbums() async throws -> [WorkbenchAlbumSummary] {
        var result: [WorkbenchAlbumSummary] = []
        var offset = 0
        let pageSize = 50
        // 页数封顶防异常响应无限翻页（50 页 = 2500 张，远超真实收藏量）。
        for _ in 0..<50 {
            let root = try await getJSON(
                "/api/netease/album/sublist",
                query: ["limit": String(pageSize), "offset": String(offset)])
            let page = NativeJSON.array(root["data"]).compactMap(WorkbenchParse.albumSummary)
            result.append(contentsOf: page)
            let hasMore = (root["hasMore"] as? Bool) ?? (page.count == pageSize)
            guard hasMore, !page.isEmpty else { break }
            offset += page.count
        }
        return result
    }

    /// 私人 FM 一批（/personal_fm 的 data[]；网页侧注明上游恒回
    /// 约 3 首、不认 limit，续航靠队列播完再取——本轮只取一批
    /// 起播，与网页侧单批语义一致）。
    func fetchPersonalFM() async throws -> [NativeTrack] {
        let root = try await getJSON("/api/netease/personal_fm")
        return NativeJSON.array(root["data"]).compactMap(WorkbenchParse.flexibleTrack)
    }

    /// 每日推荐歌曲（/recommend/songs 的 data.dailySongs[]；
    /// 形状回退顺序照 netease.ts getDailyRecommendedSongs）。
    func fetchDailySongs() async throws -> [NativeTrack] {
        let root = try await getJSON("/api/netease/recommend/songs")
        let data = NativeJSON.dict(root["data"])
        let rawSongs = NativeJSON.array(data?["dailySongs"])
            .ifEmpty { NativeJSON.array(data?["songs"]) }
            .ifEmpty { NativeJSON.array(root["songs"]) }
        return rawSongs.compactMap(WorkbenchParse.flexibleTrack)
    }

    /// 每日推荐歌单（/recommend/resource 的 recommend[]，摘要解析
    /// 复用 NativeParse.playlistSummary：picUrl 字段它已兼容）。
    func fetchRecommendedPlaylists() async throws -> [NativePlaylistSummary] {
        let root = try await getJSON("/api/netease/recommend/resource")
        return NativeJSON.array(root["recommend"]).compactMap(NativeParse.playlistSummary)
    }
}

private extension Array {
    /// 非空原样返回，空则取回退（响应形状多路回退用）。
    func ifEmpty(_ fallback: () -> [Element]) -> [Element] {
        isEmpty ? fallback() : self
    }
}
