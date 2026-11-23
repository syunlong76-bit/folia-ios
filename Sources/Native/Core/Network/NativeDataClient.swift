import Foundation

/// M1 阶段 2：原生数据链（规格 v2.1 §2/§3）。经 LocalServer 同源
/// 路径调 /api/netease/*，与 Web 侧走同一代理、同一上游、同一回退
/// 逻辑；差别只有请求方：原生 URLSession（自带 Cookie 管理关闭）。
///
/// 登录会话的载体（3.7 (5) 真机纠正，详见 WebSession.swift）：不是
/// 浏览器 Cookie，而是整串会话，以查询参数 `cookie=` 附在请求
/// 上——与 netease.ts 的 fetchWithCreds 完全同构。CookieSync 的
/// Cookie 头注入保留（同源请求与 Web 行为对齐），但它不是登录
/// 态的载体。
/// (51) A 组：会话存储已迁 Keychain（NativeSessionStore），
/// WebView localStorage 只剩一次性迁移源与异常兜底，见
/// SessionMigrator / webCookie() 的数据源优先级。
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
    /// Web 会话串缓存（凭据，只存内存）。301 时作废，下次请求重读。
    /// (51) 起仅作迁移未完成窗口期的 webview 源缓存；native 源
    /// 的缓存由 NativeSessionStore 自带内存层承担。
    private let sessionLock = NSLock()
    private var cachedWebCookie: String?
    /// 当前会话数据源（(51) A 组）：native = Keychain 原生存
    /// 储，webview = 旧 WebView 现读（迁移未完成/异常兜底）。
    enum SessionSource: String {
        case native
        case webview
    }
    private var notedSource: SessionSource?
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

    // MARK: - 会话（登录态载体，(51) 数据源改造）

    /// 数据源面包屑：首次确定与每次切换各一条，不逐请求刷屏。
    func noteSessionSource(_ source: SessionSource) {
        sessionLock.lock()
        let changed = notedSource != source
        notedSource = source
        sessionLock.unlock()
        if changed {
            Breadcrumbs.log("session.source=\(source.rawValue)")
        }
    }

    /// 刷新会话（进原生表面前调用）。native 源以 Keychain 为
    /// 准、无需刷新；仅迁移未完成（pending 且原生存储为空）时
    /// 走旧法重读 WebView 并顺带触发迁移。
    func refreshWebSession() async {
        if NativeSessionStore.shared.load() != nil {
            noteSessionSource(.native)
            return
        }
        if SessionMigrator.state == .pending {
            SessionMigrator.triggerIfNeeded()
        }
        let value = await WebSession.readNeteaseCookie()
        sessionLock.lock()
        cachedWebCookie = value
        sessionLock.unlock()
        if value != nil { noteSessionSource(.webview) }
    }

    /// 当前会话串。数据源优先级（(51) A 组，DS 风险一终案）：
    /// 1. NativeSessionStore（Keychain）——权威源；
    /// 2. store 为空且迁移曾成功（state=done）：异常兜底，一次
    ///    性回退 WebView 读取（session.fallback 面包屑），读到
    ///    则修复原生存储后使用，不直接判登出；
    /// 3. store 为空且迁移未完成：触发迁移（异步不阻塞），本
    ///    次先用旧 WebView 读法（缓存/现读）。
    /// 3.7 (30) 起取流链（EdgeOneAPIClient.fetchSongStreamURL）也复用
    /// 本方法附 `cookie` 参数——同一数据源、同一失效路径。
    func webCookie() async -> String? {
        if let stored = NativeSessionStore.shared.load() {
            noteSessionSource(.native)
            return stored
        }
        if SessionMigrator.state == .done {
            // 迁移曾成功但原生存储异常/为空：一次性回退读取。
            Breadcrumbs.log("session.fallback reason=native-empty")
            if let value = await WebSession.readNeteaseCookie(),
               NativeSessionStore.isValidNeteaseCookie(value) {
                NativeSessionStore.shared.save(value)
                Breadcrumbs.log("session.migrate.ok len=\(value.count) hash=\(NativeSessionStore.hash8(value)) via=fallback")
                noteSessionSource(.native)
                return value
            }
            return nil
        }
        SessionMigrator.triggerIfNeeded()
        sessionLock.lock()
        let cached = cachedWebCookie
        sessionLock.unlock()
        if let cached {
            noteSessionSource(.webview)
            return cached
        }
        await refreshWebSession()
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if cachedWebCookie != nil { noteSessionSource(.webview) }
        return cachedWebCookie
    }

    private func invalidateWebSession() {
        sessionLock.lock()
        cachedWebCookie = nil
        sessionLock.unlock()
    }

    /// 原生登录成功后收编会话：存 Keychain、标迁移 done、清
    /// webview 源缓存，后续请求全走 native 源。
    func adoptNativeSession(_ cookie: String) {
        NativeSessionStore.shared.save(cookie)
        SessionMigrator.state = .done
        invalidateWebSession()
        noteSessionSource(.native)
    }

    /// 清会话（退出登录/会话失效）：原生存储与 Web 侧两键同步
    /// 清，防兜底回读把已清会话复活。
    func clearNativeSession() {
        NativeSessionStore.shared.clear()
        invalidateWebSession()
        Task { await WebSession.clearNeteaseCookie() }
    }

    // MARK: - 基础请求

    /// GET 一个 /api/netease 路径，返回解析后的 JSON 字典。
    /// 业务码判定：code==200 或无 code 视为成功；301 走会话
    /// 失效路径（见 getJSONImpl 的 DS 第 5 点终案）。
    func getJSON(_ path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        try await getJSONImpl(path, query: query, retriedAfter301: false,
                              retriedAfterConnect: false)
    }

    private func getJSONImpl(_ path: String, query: [String: String],
                             retriedAfter301: Bool,
                             retriedAfterConnect: Bool) async throws -> [String: Any] {
        guard let base = baseURL else { throw DataError.serverNotReady }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        // 登录会话按 Web 同构方式走 `cookie` 查询参数（见文件头）。
        let usedCookie = await webCookie()
        if let usedCookie {
            items.append(URLQueryItem(name: "cookie", value: usedCookie))
        }
        if !items.isEmpty {
            components?.queryItems = items
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
            // -1004 断连自愈：(72) 版走 start()+waitUntilAlive，
            // (72) 真机定案失效——挂起静默死亡时 start() 被幂
            // 等锁空转、listenerAlive 过期恒 true 把等待即刻
            // 放行，重发必再撞 -1004。(73) 改走 ensureAlive：
            // 探针实测判死 → restart 强制重建 → 等新监听真
            // ready 后整请求重发一次。
            if !retriedAfterConnect,
               let urlError = error as? URLError,
               urlError.code == .cannotConnectToHost {
                _ = await LocalServer.shared.ensureAlive(timeout: 4)
                Breadcrumbs.log("data.retry connect path=\(path)")
                return try await getJSONImpl(
                    path, query: query, retriedAfter301: retriedAfter301,
                    retriedAfterConnect: true)
            }
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
            if code == 301 {
                // (51) DS 第 5 点终案：作废缓存后按当前数据源重
                // 读；重读到不同 cookie 才重试一次（会话已轮换）；
                // 同一 cookie 仍 301 = 会话失效——清原生会话并
                // 判未登录（UI 引导原生扫码登录）。
                invalidateWebSession()
                if !retriedAfter301 {
                    let reread = await webCookie()
                    if let reread,
                       NativeSessionStore.hash8(reread) != usedCookie.map(NativeSessionStore.hash8) {
                        return try await getJSONImpl(
                            path, query: query, retriedAfter301: true,
                            retriedAfterConnect: retriedAfterConnect)
                    }
                }
                if usedCookie != nil || NativeSessionStore.shared.load() != nil {
                    Breadcrumbs.log("session.invalidate reason=301")
                    clearNativeSession()
                }
                throw DataError.notLoggedIn
            }
            if code != 200 { throw DataError.api(code: code) }
        }
        return dict
    }

    // MARK: - 业务接口

    struct LoginStatus {
        let loggedIn: Bool
        let userId: String?
        let nickname: String?
        /// (61) WA 4①：profile["avatarUrl"]——此前解析层丢弃，
        /// 侧栏/导航台头像永远拿不到网易云头像 URL。
        let avatarURL: String?
    }

    /// 登录态探针：/login/status 的 profile 在就视为已登录
    /// （新旧两种响应形态都兼容：根级或 data 包裹）。
    func fetchLoginStatus() async throws -> LoginStatus {
        let root = try await getJSON("/api/netease/login/status")
        let container = NativeJSON.dict(root["data"]) ?? root
        guard let profile = NativeJSON.dict(container["profile"]) else {
            return LoginStatus(loggedIn: false, userId: nil, nickname: nil, avatarURL: nil)
        }
        return LoginStatus(
            loggedIn: true,
            userId: NativeJSON.string(profile["userId"]),
            nickname: NativeJSON.string(profile["nickname"]),
            avatarURL: NativeJSON.string(profile["avatarUrl"])
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
