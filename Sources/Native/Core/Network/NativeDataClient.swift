import Foundation

/// M1 阶段 2：原生数据链（规格 v2.1 §2/§3）。经 LocalServer 同源
/// 路径调 /api/netease/*，与 Web 侧走同一代理、同一上游、同一回退
/// 逻辑；差别只有请求方：原生 URLSession + CookieSync 手工注入
/// 本地源 Cookie（URLSession 自带 Cookie 管理关闭，防双路打架）。
///
/// 只做网易云（一期口径，与全项目「只验网易云」一致）。
final class NativeDataClient {

    static let shared = NativeDataClient()

    enum DataError: Error {
        case serverNotReady
        case transport(Error)
        case http(status: Int)
        /// 上游业务码表示未登录（网易云常见 301）。
        case notLoggedIn
        /// 其他业务错误码（原样带出，便于日志定位）。
        case api(code: Int)
        case decoding
    }

    private let session: URLSession
    /// /song/detail 单批 id 数：与 Web 侧 NETEASE_SONG_DETAIL_BATCH
    /// 对齐的已验证安全值（50）；原生侧实测调整时改这里并记规格。
    static let songDetailBatch = 50
    /// 歌单详情曲目分页大小（规格 §3 起始值，验收中实测调整）。
    static let trackPageSize = 100

    private init() {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    private var baseURL: URL? {
        let port = LocalServer.shared.port
        guard port != 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    // MARK: - 基础请求

    /// GET 一个 /api/netease 路径，返回解析后的 JSON 字典。
    /// 业务码判定：code==200 或无 code 视为成功；301 判未登录。
    func getJSON(_ path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        guard let base = baseURL else { throw DataError.serverNotReady }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw DataError.decoding }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let cookie = CookieSync.shared.cookieHeader(for: url.path) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DataError.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DataError.http(status: http.statusCode)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            throw DataError.decoding
        }
        if let codeValue = dict["code"] {
            let code = NativeJSON.int(codeValue)
            if code == 301 { throw DataError.notLoggedIn }
            if code != 200 { throw DataError.api(code: code) }
        }
        return dict
    }

    // MARK: - 业务接口

    struct LoginStatus {
        let loggedIn: Bool
        let userId: String?
        let nickname: String?
    }

    /// 登录态探针：/login/status 的 profile 在就视为已登录
    /// （新旧两种响应形态都兼容：根级或 data 包裹）。
    func fetchLoginStatus() async throws -> LoginStatus {
        let root = try await getJSON("/api/netease/login/status")
        let container = NativeJSON.dict(root["data"]) ?? root
        guard let profile = NativeJSON.dict(container["profile"]) else {
            return LoginStatus(loggedIn: false, userId: nil, nickname: nil)
        }
        return LoginStatus(
            loggedIn: true,
            userId: NativeJSON.string(profile["userId"]),
            nickname: NativeJSON.string(profile["nickname"])
        )
    }

    /// 用户歌单全量（创建 + 收藏）。一次全拉、本地呈现（规格 §3）。
    func fetchUserPlaylists(userId: String) async throws -> [NativePlaylistSummary] {
        let root = try await getJSON("/api/netease/user/playlist",
                                     query: ["uid": userId, "limit": "1000", "offset": "0"])
        return NativeJSON.array(root["playlist"]).compactMap(NativeParse.playlistSummary)
    }

    /// 歌单详情：元数据 + 全量 trackIds（分页队列的骨架）。
    func fetchPlaylistDetail(id: String) async throws -> NativePlaylistDetail {
        let root = try await getJSON("/api/netease/playlist/detail", query: ["id": id])
        guard let detail = NativeParse.playlistDetail(root) else { throw DataError.decoding }
        return detail
    }

    /// 歌单曲目分页（完整曲目对象，按歌单序）。
    func fetchPlaylistTracksPage(id: String, limit: Int, offset: Int) async throws -> [NativeTrack] {
        let root = try await getJSON("/api/netease/playlist/track/all",
                                     query: ["id": id, "limit": String(limit), "offset": String(offset)])
        return NativeJSON.array(root["songs"]).compactMap(NativeParse.track)
    }

    /// 按 id 批量取曲目详情（队列占位填充用），内部按批切分。
    func fetchSongDetails(ids: [String]) async throws -> [NativeTrack] {
        var result: [NativeTrack] = []
        var index = 0
        while index < ids.count {
            let batch = Array(ids[index..<min(index + Self.songDetailBatch, ids.count)])
            let root = try await getJSON("/api/netease/song/detail",
                                         query: ["ids": batch.joined(separator: ",")])
            result.append(contentsOf: NativeJSON.array(root["songs"]).compactMap(NativeParse.track))
            index += Self.songDetailBatch
        }
        return result
    }

    /// 红心（写操作）：成功返回 true；业务失败抛错由调用方处理
    /// （规格 §5：失败保留原状态并提示）。
    @discardableResult
    func setLike(trackId: String, like: Bool) async throws -> Bool {
        let root = try await getJSON("/api/netease/like",
                                     query: ["id": trackId, "like": like ? "true" : "false"])
        return NativeJSON.int(root["code"]) == 200
    }

    /// 红心列表（初始化三端一致状态用）。
    func fetchLikeList(userId: String) async throws -> Set<String> {
        let root = try await getJSON("/api/netease/likelist", query: ["uid": userId])
        let ids = (root["ids"] as? [Any]) ?? []
        return Set(ids.compactMap { NativeJSON.string($0) })
    }
}
