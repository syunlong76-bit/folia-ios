// EdgeOneAPIClient.swift
//
// M1 播放内核：EdgeOne / Netlify JSON 接口客户端（native-arch.md §6）。
// - 节点顺序以 2026-11-14 实测结论为准：Netlify 同源代理为主节点，
//   EdgeOne 直连默认域名为备用（大陆网络直连 *.edgeone.cool 曾回 401 访问保护）。
// - 单节点 6 秒超时故障转移，锁定当前可用节点。
// - path 前缀以函数实测路由为准：网易云 /search、/song/url/v1、/lyric、
//   /playlist/detail（2026-11-14 本机 curl 实测全部 200；全量文档的
//   /cloudsearch 前缀不盲抄）。
// - QQ search 已知用当前参数回 400（参数待核对）：QQ/酷狗的取流与搜索 DTO
//   未实测核对，M1 不卡 QQ——相关方法抛 providerUnverified 并记 TODO，
//   搜索原始数据可走 searchRaw 供 M3 核对形状后再接类型化 DTO。
// - 音频流 URL 一律直连平台 CDN，代理只代理 JSON。

import Foundation

enum EdgeOneError: Error {
    case allNodesFailed
    case invalidResponse
    case streamURLMissing
    /// 该平台的方法/响应体未实测核对，M1 不提供（防把未验证的形状写成确定能力）。
    case providerUnverified(provider: AudioSourceType, method: String)
}

final class EdgeOneAPIClient {

    static let shared = EdgeOneAPIClient()

    /// 节点优先级：0 = Netlify 同源代理（主），1 = EdgeOne 直连默认域名（备）。
    private struct NodePair {
        let primary: URL
        let backup: URL
    }

    private static func nodes(for provider: AudioSourceType) -> NodePair? {
        switch provider {
        case .netease:
            return NodePair(
                primary: URL(string: "https://folia-music.netlify.app/api/netease")!,
                backup: URL(string: "https://folia-netease-8v5g6dx9.edgeone.cool")!
            )
        case .qq:
            return NodePair(
                primary: URL(string: "https://folia-music.netlify.app/api/qq")!,
                backup: URL(string: "https://folia-qq-8j540jls.edgeone.cool")!
            )
        case .kugou:
            return NodePair(
                primary: URL(string: "https://folia-music.netlify.app/api/kugou")!,
                backup: URL(string: "https://folia-kugou-k62owtqf.edgeone.cool")!
            )
        case .local:
            return nil
        }
    }

    /// 每个平台独立锁定当前可用节点（0 = 主，1 = 备）。
    private var activeNodeIndex: [AudioSourceType: Int] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0 // 单节点 6 秒超时快速切换
        config.timeoutIntervalForResource = 30.0
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - 通用 GET（主备故障转移）

    /// 通用 JSON GET。path 为函数实测路由（如 "/search"），不含平台前缀
    /// （平台前缀已在节点 base URL 里）。
    func requestJSON<T: Decodable>(
        provider: AudioSourceType,
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        let data = try await requestData(provider: provider, path: path, queryItems: queryItems)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 原始 JSON GET（不解码，供 M3 核对未验证平台的响应形状）。
    func requestData(
        provider: AudioSourceType,
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        guard let pair = Self.nodes(for: provider) else {
            throw EdgeOneError.providerUnverified(provider: provider, method: path)
        }
        let bases = [pair.primary, pair.backup]
        let startIndex = activeNodeIndex[provider] ?? 0

        for attempt in 0..<bases.count {
            let index = (startIndex + attempt) % bases.count
            let baseURL = bases[index]
            guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
                continue
            }
            if !queryItems.isEmpty { components.queryItems = queryItems }
            guard let finalURL = components.url else { continue }

            var request = URLRequest(url: finalURL)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResp = response as? HTTPURLResponse,
                      (200...299).contains(httpResp.statusCode) else {
                    throw EdgeOneError.invalidResponse
                }
                // 锁定当前可用节点，避免后续请求重复试错。
                activeNodeIndex[provider] = index
                return data
            } catch {
                // 当前节点失败，循环自动尝试下一个备用节点。
                continue
            }
        }
        throw EdgeOneError.allNodesFailed
    }

    // MARK: - 网易云业务方法（实测路由，2026-11-14 全部 200）

    /// 搜索。实测：GET /api/netease/search?keywords=&limit=&type=1 → 200。
    /// 响应体用新形状：songs[].artists / .duration(ms) / .album.picUrl；
    /// 兼容旧键 ar / dt / al 作回退。
    func searchSongs(keywords: String, limit: Int = 30) async throws -> [FoliaTrack] {
        let resp = try await requestJSON(
            provider: .netease,
            path: "/search",
            queryItems: [
                URLQueryItem(name: "keywords", value: keywords),
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "type", value: "1")
            ],
            as: NeteaseSearchResponse.self
        )
        return (resp.result?.songs ?? []).map { $0.toFoliaTrack() }
    }

    /// 取流（/song/url/v1）。VIP 曲 fee=1 回 url:null/code:404 → 抛 streamURLMissing，
    /// 由 QueueManager 走失败跳歌 + 熔断，不写死过期 URL。
    /// 实测：id 1973665667《海屿你》（fee=8）回真实 URL code:200，expi=1200 秒。
    func fetchSongStreamURL(provider: AudioSourceType, songId: String) async throws -> URL {
        guard provider == .netease else {
            // TODO(M3)：QQ/酷狗取流路由与响应体未实测核对，先不提供，防误接。
            throw EdgeOneError.providerUnverified(provider: provider, method: "song/url/v1")
        }
        let rawId = songId.replacingOccurrences(of: "ncm_", with: "")
        let resp = try await requestJSON(
            provider: .netease,
            path: "/song/url/v1",
            queryItems: [
                URLQueryItem(name: "id", value: rawId),
                URLQueryItem(name: "level", value: "exhigh")
            ],
            as: NeteaseSongURLResponse.self
        )
        guard let urlStr = resp.data?.first?.url,
              let url = URL(string: urlStr.replacingOccurrences(of: "http://", with: "https://")) else {
            throw EdgeOneError.streamURLMissing
        }
        return url
    }

    /// 歌词。实测：GET /api/netease/lyric?id=1973665667 → 200，lrc.lyric 为 LRC 文本。
    func fetchLyricText(songId: String) async throws -> String {
        let rawId = songId.replacingOccurrences(of: "ncm_", with: "")
        let resp = try await requestJSON(
            provider: .netease,
            path: "/lyric",
            queryItems: [URLQueryItem(name: "id", value: rawId)],
            as: NeteaseLyricResponse.self
        )
        return resp.lrc?.lyric ?? ""
    }

    /// 歌单详情。实测：GET /api/netease/playlist/detail?id=19723756（飙升榜）→ 200。
    func fetchPlaylistDetail(playlistId: String) async throws -> NeteasePlaylistDetail {
        let resp = try await requestJSON(
            provider: .netease,
            path: "/playlist/detail",
            queryItems: [URLQueryItem(name: "id", value: playlistId)],
            as: NeteasePlaylistDetailResponse.self
        )
        guard let playlist = resp.playlist else { throw EdgeOneError.invalidResponse }
        return playlist
    }

    /// 歌曲详情批量取（歌单页补齐曲目元数据）。实测 2026-11-16：
    /// GET /api/netease/song/detail?ids=1973665667,186016 → 200，songs[] 含
    /// ar / al（含 picUrl）/ dt。按 200 首分片并发取，按入参顺序拼回。
    func fetchSongDetails(ids: [Int]) async throws -> [FoliaTrack] {
        guard !ids.isEmpty else { return [] }
        // 分片并行取（3.4）：顺序分片在几百首的歌单上要串行等多个往返，
        // TaskGroup 并发后总时长≈最慢的一片。
        let chunkSize = 100
        let chunks: [[Int]] = stride(from: 0, to: ids.count, by: chunkSize).map {
            Array(ids[$0..<min($0 + chunkSize, ids.count)])
        }
        var byId: [Int: FoliaTrack] = [:]
        try await withThrowingTaskGroup(of: [SongDetailDTO].self) { group in
            for chunk in chunks {
                group.addTask {
                    let resp = try await self.requestJSON(
                        provider: .netease,
                        path: "/song/detail",
                        queryItems: [URLQueryItem(name: "ids", value: chunk.map(String.init).joined(separator: ","))],
                        as: NeteaseSongDetailResponse.self
                    )
                    return resp.songs ?? []
                }
            }
            for try await songs in group {
                for song in songs {
                    byId[song.id] = song.toFoliaTrack()
                }
            }
        }
        // 保持歌单原序；接口没回的 id 直接跳过（已下架等）。
        return ids.compactMap { byId[$0] }
    }

    /// 推荐歌单（免登录）。实测 2026-11-16：GET /api/netease/personalized?limit= → 200。
    func fetchPersonalizedPlaylists(limit: Int = 30) async throws -> [PlaylistSummary] {
        let resp = try await requestJSON(
            provider: .netease,
            path: "/personalized",
            queryItems: [URLQueryItem(name: "limit", value: "\(limit)")],
            as: NeteasePersonalizedResponse.self
        )
        return (resp.result ?? []).map {
            PlaylistSummary(id: $0.id, name: $0.name,
                            coverURL: $0.picUrl.flatMap(Self.secureURL),
                            trackCount: $0.trackCount ?? 0,
                            playCount: $0.playCount,
                            copywriter: $0.copywriter)
        }
    }

    /// 排行榜（免登录）。实测 2026-11-16：GET /api/netease/toplist → 200，
    /// list[] 的 id 可直接喂 fetchPlaylistDetail。
    func fetchToplist() async throws -> [PlaylistSummary] {
        let resp = try await requestJSON(
            provider: .netease,
            path: "/toplist",
            queryItems: [],
            as: NeteaseToplistResponse.self
        )
        return (resp.list ?? []).map {
            PlaylistSummary(id: $0.id, name: $0.name,
                            coverURL: $0.coverImgUrl.flatMap(Self.secureURL),
                            trackCount: $0.trackCount ?? 0,
                            playCount: $0.playCount,
                            updateFrequency: $0.updateFrequency,
                            toplistType: $0.ToplistType)
        }
    }

    // MARK: - 探索页货架（neteaseExplore 映射，2026-11-16 移植）

    /// 网易云首页 blocks 第一页（/homepage/block/page）。映射 folia-major
    /// neteaseExplore.shelvesOf：剔除榜单块（排行榜另有分区）与听歌记录块
    /// （RECENT/HISTORY 或标题以「最近」开头），块内条目按 key 去重；
    /// 资源种类只认 song/list/album，其余（播客/视频/数字专辑）跳过。
    /// 后续 blocks 页（cursor 翻页）本轮未映射，见移植报告偏差清单。
    func fetchHomeBlockSections() async throws -> [ExploreFeedSection] {
        let resp = try await requestJSON(
            provider: .netease,
            path: "/homepage/block/page",
            queryItems: [URLQueryItem(name: "refresh", value: "false")],
            as: NeteaseHomeBlocksResponse.self
        )
        var sections: [ExploreFeedSection] = []
        var usedIds = Set<String>()
        for block in resp.data?.blocks ?? [] {
            let code = block.blockCode ?? ""
            let title = block.uiElement?.subTitle?.title ?? block.uiElement?.mainTitle?.title ?? ""
            if code == "HOMEPAGE_BLOCK_TOPLIST" { continue }
            if code.contains("RECENT") || code.contains("HISTORY") || title.hasPrefix("最近") { continue }
            var seen = Set<String>()
            var items: [ExploreItem] = []
            for creative in block.creatives ?? [] {
                for resource in creative.resources ?? [] {
                    guard let item = Self.exploreItem(of: resource) else { continue }
                    if seen.contains(item.id) { continue }
                    seen.insert(item.id)
                    items.append(item)
                }
            }
            if items.isEmpty || title.isEmpty { continue }
            var sectionId = "netease-block-\(code)"
            var suffix = 2
            while usedIds.contains(sectionId) {
                sectionId = "netease-block-\(code)-\(suffix)"
                suffix += 1
            }
            usedIds.insert(sectionId)
            sections.append(ExploreFeedSection(id: sectionId, title: title, items: items))
        }
        return sections
    }

    /// 首页 block 的一条资源 → 探索条目（对应源码 itemOf）。
    private static func exploreItem(of resource: HomeBlockResourceDTO) -> ExploreItem? {
        let info = resource.resourceExtInfo
        if resource.resourceType == "song" {
            guard var dto = info?.songData ?? info?.song, dto.id != 0 else { return nil }
            // 歌曲自带封面缺失时用资源图（源码同规则）。
            if dto.album?.picUrl == nil, let cover = resource.uiElement?.image?.imageUrl {
                dto = dto.withAlbumCover(cover)
            }
            return .song(dto.toFoliaTrack())
        }
        guard let rawId = resource.resourceId?.value, rawId > 0,
              let name = resource.uiElement?.mainTitle?.title, !name.isEmpty else { return nil }
        let cover = resource.uiElement?.image?.imageUrl.flatMap(Self.secureURL)
        if resource.resourceType == "list" {
            return .collection(ExploreCollection(
                kind: .playlist, id: rawId, name: name, coverURL: cover,
                subtitle: "歌单"))
        }
        if resource.resourceType == "album" {
            let artists = (info?.artists ?? []).map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
            return .collection(ExploreCollection(
                kind: .album, id: rawId, name: name, coverURL: cover,
                subtitle: artists.isEmpty ? "专辑" : artists))
        }
        return nil
    }

    /// 新歌速递（/top/song?type=0，一次回约 100 首旧格式歌曲）。
    /// 对应 neteaseExplore 的 NEW_SONGS 货架（listShelf 整表分批）。
    func fetchNewSongs() async throws -> [FoliaTrack] {
        let resp = try await requestJSON(
            provider: .netease,
            path: "/top/song",
            queryItems: [URLQueryItem(name: "type", value: "0")],
            as: NeteaseTopSongResponse.self
        )
        return (resp.data ?? []).map { $0.toFoliaTrack() }
    }

    /// 新碟上架（/album/new 分页）。对应 neteaseExplore 的 NEW_ALBUMS 分页货架。
    /// 返回本页专辑与总数（hasMore 由调用方按 offset+count < total 判定）。
    func fetchNewAlbums(limit: Int, offset: Int) async throws -> (albums: [ExploreCollection], total: Int) {
        let resp = try await requestJSON(
            provider: .netease,
            path: "/album/new",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ],
            as: NeteaseNewAlbumsResponse.self
        )
        let albums = (resp.albums ?? []).map { dto in
            let artists = (dto.artists ?? []).map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
            return ExploreCollection(
                kind: .album, id: dto.id, name: dto.name,
                coverURL: dto.picUrl.flatMap(Self.secureURL),
                subtitle: artists.isEmpty ? "专辑" : artists)
        }
        return (albums, resp.total ?? 0)
    }

    /// 相似歌曲（/simi/song）。对应 neteaseExplore 的相似货架数据源（每首约 5 首）。
    func fetchSimilarSongs(songId: Int) async throws -> [FoliaTrack] {
        let resp = try await requestJSON(
            provider: .netease,
            path: "/simi/song",
            queryItems: [URLQueryItem(name: "id", value: "\(songId)")],
            as: NeteaseSimilarResponse.self
        )
        return (resp.songs ?? []).map { $0.toFoliaTrack() }
    }

    /// 专辑详情（/album?id=）：专辑信息 + 全部曲目一次回。
    func fetchAlbumDetail(albumId: String) async throws -> NeteaseAlbumDetail {
        let resp = try await requestJSON(
            provider: .netease,
            path: "/album",
            queryItems: [URLQueryItem(name: "id", value: albumId)],
            as: NeteaseAlbumDetailResponse.self
        )
        guard let album = resp.album else { throw EdgeOneError.invalidResponse }
        return NeteaseAlbumDetail(info: album, tracks: (resp.songs ?? []).map { $0.toFoliaTrack() })
    }

    /// http → https + URL 化（网易云图片 CDN 地址归一化）。
    private static func secureURL(_ text: String) -> URL? {
        URL(string: text.replacingOccurrences(of: "http://", with: "https://"))
    }

    // MARK: - QQ / 酷狗（M1 仅留 raw 逃生口，类型化方法待 M3 核对）

    /// QQ/酷狗搜索原始数据（不解码）。已知：/api/qq/search 用当前参数回 400，
    /// 参数待核对；/api/kugou/search 曾回 200 但响应体形状未核对。
    /// TODO(M3)：核对参数与形状后接类型化 DTO，再开放给 QueueManager。
    func searchRaw(provider: AudioSourceType, keywords: String, limit: Int = 30) async throws -> Data {
        try await requestData(
            provider: provider,
            path: "/search",
            queryItems: [
                URLQueryItem(name: "keywords", value: keywords),
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "type", value: "1")
            ]
        )
    }

    // MARK: - 流地址探测（delegate，收到响应头即 cancel，不拉整首歌）

    /// 探测音频流是否支持 HTTP 206 Partial Content：
    /// - 206 → 直连 AVPlayer，性能最佳；
    /// - 200（网关吞 Range）→ 改走 folia-stream 自定义 Scheme，
    ///   由 RangeStreamResourceLoader 做 200→206 切片代理。
    /// 302 跟随策略：m801.music.126.net 实测直连通，无需特殊 header/cookie，
    /// 默认跟随（不盲抄拒绝跟随；平台流地址若以 302 分发到 CDN，拒绝跟随会被误判）。
    func resolvePlayableURL(rawStreamURL: URL) async -> URL {
        let supportsRange = await probeRangeSupport(url: rawStreamURL)
        if supportsRange { return rawStreamURL }
        var comps = URLComponents(url: rawStreamURL, resolvingAgainstBaseURL: false)
        comps?.scheme = RangeStreamResourceLoader.customScheme
        return comps?.url ?? rawStreamURL
    }

    /// delegate 探测：收到响应头判定 206/200 后立即 cancel，禁止 data(for:) 拉整首歌。
    private func probeRangeSupport(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            var probe = URLRequest(url: url)
            probe.httpMethod = "GET"
            probe.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            probe.timeoutInterval = 4.0

            let delegate = RangeProbeDelegate(continuation: continuation)
            let probeSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = probeSession
            let task = probeSession.dataTask(with: probe)
            task.resume()
        }
    }
}

// MARK: - 探测 delegate（收到响应头即判定 + cancel）

private final class RangeProbeDelegate: NSObject, URLSessionDataDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var resumed = false
    var session: URLSession?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    private func finish(_ value: Bool) {
        guard !resumed else { return }
        resumed = true
        continuation?.resume(returning: value)
        continuation = nil
        // 探测 session 用后即 invalidate（与流式 session 同型问题，不留累积）。
        session?.finishTasksAndInvalidate()
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // 206 = 原生支持 Range；200 = 网关吞 Range，需走本地切片代理。
        let supportsRange = (response as? HTTPURLResponse)?.statusCode == 206
        completionHandler(.cancel)
        dataTask.cancel()
        finish(supportsRange)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 超时 / 网络失败 / 被 cancel 后走到这里：按不支持 Range 处理。
        finish(false)
    }
}

// MARK: - 网易云响应 DTO（按 2026-11-14 实测形状；旧键仅作回退）

private struct NeteaseSearchResponse: Decodable {
    let result: SearchResult?
    struct SearchResult: Decodable {
        let songs: [SongDTO]?
    }
    struct SongDTO: Decodable {
        let id: Int
        let name: String
        let duration: Int?      // 实测键：毫秒
        let dt: Int?            // 旧键回退：毫秒
        let artists: [ArtistDTO]?
        let ar: [ArtistDTO]?    // 旧键回退
        let album: AlbumDTO?
        let al: AlbumDTO?       // 旧键回退
        let fee: Int?

        struct ArtistDTO: Decodable { let name: String }
        struct AlbumDTO: Decodable {
            let name: String
            let picUrl: String?
        }

        func toFoliaTrack() -> FoliaTrack {
            let artistList = artists ?? ar ?? []
            let artistNames = artistList.map(\.name).joined(separator: " / ")
            let albumInfo = album ?? al
            let secureArt = albumInfo?.picUrl?.replacingOccurrences(of: "http://", with: "https://")
            let durationMs = duration ?? dt ?? 0
            return FoliaTrack(
                id: "ncm_\(id)",
                sourceType: .netease,
                title: name,
                artist: artistNames.isEmpty ? "未知歌手" : artistNames,
                album: albumInfo?.name ?? "",
                duration: Double(durationMs) / 1000.0,
                artworkURL: secureArt.flatMap { URL(string: $0) },
                fee: fee
            )
        }
    }
}

private struct NeteaseSongURLResponse: Decodable {
    let data: [Item]?
    struct Item: Decodable {
        let id: Int?
        let url: String?
        let code: Int?
    }
}

private struct NeteaseLyricResponse: Decodable {
    let lrc: LrcBody?
    struct LrcBody: Decodable { let lyric: String? }
}

private struct NeteasePlaylistDetailResponse: Decodable {
    let code: Int?
    let playlist: NeteasePlaylistDetail?
}

/// 歌单详情（id / 名称 / 封面 / 曲目 id 列表 + 接口顺带回的首批完整曲目）。
struct NeteasePlaylistDetail: Decodable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let trackIds: [TrackId]?
    let tracks: [SongDetailDTO]?
    let trackCount: Int?
    let playCount: Int?
    let description: String?
    let creator: CreatorDTO?

    struct TrackId: Decodable { let id: Int }
    struct CreatorDTO: Decodable {
        let nickname: String?
        let avatarUrl: String?
    }

    var trackIdList: [Int] { trackIds?.map(\.id) ?? [] }

    /// 接口在 detail 里顺带回的首批完整曲目（通常前若干首），可省一次详情请求。
    var prefetchedTracks: [FoliaTrack] { (tracks ?? []).map { $0.toFoliaTrack() } }

    // 注：不要把 .flatMap 直接链在 ?. 后面——可选链会把 flatMap 吃进链内
    // 落到 String 的 Sequence.flatMap 上（元素是 Character），编译不过；
    // 先 guard 取出原文再构造 URL。
    var coverURL: URL? {
        guard let raw = coverImgUrl else { return nil }
        return URL(string: raw.replacingOccurrences(of: "http://", with: "https://"))
    }
    var creatorAvatarURL: URL? {
        guard let raw = creator?.avatarUrl else { return nil }
        return URL(string: raw.replacingOccurrences(of: "http://", with: "https://"))
    }
}

/// 歌单摘要（推荐歌单 / 排行榜共用）。
struct PlaylistSummary: Identifiable {
    let id: Int
    let name: String
    let coverURL: URL?
    let trackCount: Int
    var playCount: Int? = nil
    /// 榜单更新频率文案（「每天更新」），探索页榜单卡的副文本。
    var updateFrequency: String? = nil
    /// 官方榜标记（neteaseExplore 以 ToplistType 挑官方四榜做歌曲货架）。
    var toplistType: String? = nil
    var copywriter: String? = nil
}

private struct NeteasePersonalizedResponse: Decodable {
    let result: [Item]?
    struct Item: Decodable {
        let id: Int
        let name: String
        let picUrl: String?
        let trackCount: Int?
        let playCount: Int?
        let copywriter: String?
    }
}

private struct NeteaseToplistResponse: Decodable {
    let list: [Item]?
    struct Item: Decodable {
        let id: Int
        let name: String
        let coverImgUrl: String?
        let trackCount: Int?
        let playCount: Int?
        let updateFrequency: String?
        let ToplistType: String?
    }
}

private struct NeteaseSongDetailResponse: Decodable {
    let songs: [SongDetailDTO]?
}

/// /song/detail 的单曲形状（ar / al / dt，与搜索实测形状同族）。
struct SongDetailDTO: Decodable {
    let id: Int
    let name: String
    let dt: Int?
    let ar: [ArtistDTO]?
    let al: AlbumDTO?
    let fee: Int?

    struct ArtistDTO: Decodable { let name: String }
    struct AlbumDTO: Decodable {
        let name: String
        let picUrl: String?
    }

    func toFoliaTrack() -> FoliaTrack {
        let artistNames = (ar ?? []).map(\.name).joined(separator: " / ")
        let secureArt = al?.picUrl?.replacingOccurrences(of: "http://", with: "https://")
        return FoliaTrack(
            id: "ncm_\(id)",
            sourceType: .netease,
            title: name,
            artist: artistNames.isEmpty ? "未知歌手" : artistNames,
            album: al?.name ?? "",
            duration: Double(dt ?? 0) / 1000.0,
            artworkURL: secureArt.flatMap { URL(string: $0) },
            fee: fee
        )
    }
}

// MARK: - 探索页 DTO（形状随 folia-major netease.ts 的归一化前原始响应）

/// 宽松歌曲形状：新旧两套键都认（artists/ar、album/al、duration/dt）。
/// /top/song 与 /simi/song 与首页 block 的 songData 都走这个形状。
struct FlexibleSongDTO: Decodable {
    let id: Int
    let name: String
    let duration: Int?
    let dt: Int?
    let artists: [NameDTO]?
    let ar: [NameDTO]?
    let album: AlbumDTO?
    let al: AlbumDTO?
    let fee: Int?

    struct NameDTO: Decodable { let name: String }
    struct AlbumDTO: Decodable {
        let name: String
        let picUrl: String?
    }

    /// 换一张专辑封面（首页 block 歌曲缺封面时用资源图补，源码 itemOf 同规则）。
    func withAlbumCover(_ picUrl: String) -> FlexibleSongDTO {
        FlexibleSongDTO(
            id: id, name: name, duration: duration, dt: dt,
            artists: artists, ar: ar,
            album: AlbumDTO(name: album?.name ?? al?.name ?? "", picUrl: picUrl),
            al: al, fee: fee)
    }

    func toFoliaTrack() -> FoliaTrack {
        let artistNames = (artists ?? ar ?? []).map(\.name).joined(separator: " / ")
        let albumInfo = album ?? al
        let secureArt = albumInfo?.picUrl?.replacingOccurrences(of: "http://", with: "https://")
        return FoliaTrack(
            id: "ncm_\(id)",
            sourceType: .netease,
            title: name,
            artist: artistNames.isEmpty ? "未知歌手" : artistNames,
            album: albumInfo?.name ?? "",
            duration: Double(duration ?? dt ?? 0) / 1000.0,
            artworkURL: secureArt.flatMap { URL(string: $0) },
            fee: fee
        )
    }
}

/// resourceId 在 block 里时而数字时而字符串，两边都收。
struct FlexibleID: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Int(text)
        } else {
            value = nil
        }
    }
}

private struct NeteaseHomeBlocksResponse: Decodable {
    let data: DataBody?
    struct DataBody: Decodable {
        let blocks: [BlockDTO]?
        let hasMore: Bool?
    }
    struct BlockDTO: Decodable {
        let blockCode: String?
        let uiElement: UIElementDTO?
        let creatives: [CreativeDTO]?
    }
    struct CreativeDTO: Decodable {
        let resources: [HomeBlockResourceDTO]?
    }
    struct UIElementDTO: Decodable {
        let mainTitle: TitleDTO?
        let subTitle: TitleDTO?
    }
    struct TitleDTO: Decodable { let title: String? }
}

struct HomeBlockResourceDTO: Decodable {
    let resourceType: String?
    let resourceId: FlexibleID?
    let uiElement: ResourceUIElementDTO?
    let resourceExtInfo: ExtInfoDTO?

    struct ResourceUIElementDTO: Decodable {
        let mainTitle: TitleDTO?
        let image: ImageDTO?
    }
    struct TitleDTO: Decodable { let title: String? }
    struct ImageDTO: Decodable { let imageUrl: String? }
    struct ExtInfoDTO: Decodable {
        let songData: FlexibleSongDTO?
        let song: FlexibleSongDTO?
        let playCount: Int?
        let artists: [FlexibleSongDTO.NameDTO]?
    }
}

private struct NeteaseTopSongResponse: Decodable {
    let data: [FlexibleSongDTO]?
}

private struct NeteaseSimilarResponse: Decodable {
    let songs: [FlexibleSongDTO]?
}

private struct NeteaseNewAlbumsResponse: Decodable {
    let total: Int?
    let albums: [AlbumItemDTO]?
    struct AlbumItemDTO: Decodable {
        let id: Int
        let name: String
        let picUrl: String?
        let artists: [FlexibleSongDTO.NameDTO]?
        let size: Int?
    }
}

/// 专辑详情（信息 + 曲目）。publishTime 为毫秒时间戳。
struct NeteaseAlbumDetail {
    let info: AlbumInfoDTO
    let tracks: [FoliaTrack]

    struct AlbumInfoDTO: Decodable {
        let id: Int
        let name: String
        let picUrl: String?
        let artist: ArtistDTO?
        let artists: [ArtistDTO]?
        let publishTime: Int64?
        let company: String?
        let description: String?
        let size: Int?

        struct ArtistDTO: Decodable { let name: String }
    }

    var coverURL: URL? {
        guard let raw = info.picUrl else { return nil }
        return URL(string: raw.replacingOccurrences(of: "http://", with: "https://"))
    }
    var artistLabel: String {
        let names = (info.artists ?? []).map(\.name).filter { !$0.isEmpty }
        if !names.isEmpty { return names.joined(separator: ", ") }
        return info.artist?.name ?? ""
    }
    var publishDateText: String? {
        guard let ms = info.publishTime, ms > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
    }
}

private struct NeteaseAlbumDetailResponse: Decodable {
    let album: NeteaseAlbumDetail.AlbumInfoDTO?
    let songs: [SongDetailDTO]?
}
