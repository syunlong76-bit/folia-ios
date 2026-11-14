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
                artworkURL: secureArt.flatMap(URL.init(string:))
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

/// 歌单详情（M1 只取 id / 名称 / 封面 / 曲目 id 列表；曲目元数据由 M3 搜索补齐）。
struct NeteasePlaylistDetail: Decodable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let trackIds: [TrackId]?

    struct TrackId: Decodable { let id: Int }

    var trackIdList: [Int] { trackIds?.map(\.id) ?? [] }
}
