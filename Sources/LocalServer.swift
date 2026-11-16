import CryptoKit
import Foundation
import ImageIO
import Network

/// 内置本地 HTTP 服务器（与安卓版同构）：
/// - NWListener 监听 127.0.0.1:18765（仅回环接口；端口被占则 +1 回退，最多试 11 个端口）
/// - 静态文件：根目录 = WebRootManager 当前生效版本目录；MIME 齐全；SPA 回退 index.html
/// - /sw.js：返回自注销 stub（壳内禁用 Folia 自带 Service Worker，避免其缓存与
///   壳的整包版本切换机制互相打架；离线能力由本地文件本身提供）
/// - /api/*：反向代理到 https://folia-music.netlify.app
///   完整转发 method / 请求头（含 Cookie）/ 请求体；响应状态、响应头、Set-Cookie、响应体原样回传。
///   因为本服务器就是 WKWebView 的源（origin），登录 Cookie 在 WebView 与本服务器之间
///   按标准浏览器规则流转，再由代理原样带给上游，不需要另做 cookie 罐。
final class LocalServer {

    static let shared = LocalServer()

    /// API 代理的上游站点（前端构建里 API 基址为同源相对路径 /api/...，故只需换源）
    static let upstreamBase = "https://folia-music.netlify.app"

    static let preferredPort: UInt16 = 18765
    static let maxPortRetries = 10

    /// 实际监听端口（ready 后有效）
    private(set) var port: UInt16 = 0
    var isRunning: Bool { port != 0 }

    /// 服务器就绪回调（主线程）
    var onReady: ((UInt16) -> Void)?

    private var listener: NWListener?
    private let listenerQueue = DispatchQueue(label: "com.miller.folia.localserver")
    private var liveHandlers = [ObjectIdentifier: ConnectionHandler]()
    private let handlersLock = NSLock()

    private init() {}

    // MARK: - 启动（含端口回退）

    func start() {
        attempt(port: LocalServer.preferredPort, retriesLeft: LocalServer.maxPortRetries)
    }

    private func attempt(port: UInt16, retriesLeft: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback      // 只绑回环接口，不对外暴露
        params.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            NSLog("[LocalServer] NWListener init failed on \(port): \(error)")
            if retriesLeft > 0 { attempt(port: port + 1, retriesLeft: retriesLeft - 1) }
            return
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.port = port
                NSLog("[LocalServer] listening on 127.0.0.1:\(port)")
                if let cb = self.onReady {
                    DispatchQueue.main.async { cb(port) }
                }
            case .failed(let error):
                NSLog("[LocalServer] failed on \(port): \(error)")
                listener.cancel()
                if retriesLeft > 0 {
                    self.attempt(port: port + 1, retriesLeft: retriesLeft - 1)
                }
            case .waiting(let error):
                // waiting 多为瞬态（接口未就绪等），其后通常会转 ready/failed，不要贸然取消；
                // 仅当明确是「地址已被占用」时才按失败处理，换下一个端口
                if case .posix(let code) = error, code == POSIXErrorCode.EADDRINUSE {
                    NSLog("[LocalServer] port \(port) in use, trying next")
                    listener.cancel()
                    if retriesLeft > 0 {
                        self.attempt(port: port + 1, retriesLeft: retriesLeft - 1)
                    }
                } else {
                    NSLog("[LocalServer] waiting on \(port): \(error)")
                }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { connection.cancel(); return }
            let handler = ConnectionHandler(connection: connection, server: self)
            self.handlersLock.lock()
            self.liveHandlers[ObjectIdentifier(handler)] = handler
            self.handlersLock.unlock()
            handler.start()
        }

        listener.start(queue: listenerQueue)
    }

    fileprivate func handlerFinished(_ handler: ConnectionHandler) {
        handlersLock.lock()
        liveHandlers.removeValue(forKey: ObjectIdentifier(handler))
        handlersLock.unlock()
    }

    // MARK: - 请求路由

    fileprivate func route(_ request: HTTPRequest, for handler: ConnectionHandler) {
        let rawPath = request.pathWithoutQuery

        if rawPath == "/sw.js" || rawPath == "/browse/sw.js" {
            handler.respond(status: 200, reason: "OK",
                            headers: [("Content-Type", "text/javascript; charset=utf-8"),
                                      ("Cache-Control", "no-store")],
                            body: Data(LocalServer.serviceWorkerStub.utf8))
            return
        }

        if rawPath.hasPrefix("/__bridge/") {
            handleBridge(request: request, handler: handler)
            return
        }

        if rawPath == "/img" || rawPath.hasPrefix("/img/") {
            CoverImageProxy.handle(request: request, handler: handler)
            return
        }

        if rawPath == "/api" || rawPath.hasPrefix("/api/") {
            Proxy.proxy(request: request, handler: handler)
            return
        }

        // 双壳浏览表面：/browse/* 映射到浏览根目录（SPA 回退在浏览根内），
        // 其余路径仍走播放根（含 OTA 版本目录）。
        if rawPath == "/browse" || rawPath.hasPrefix("/browse/") {
            let sub = String(rawPath.dropFirst("/browse".count))
            serveStatic(request: request, rawPath: sub.isEmpty ? "/" : sub,
                        handler: handler, root: WebRootManager.shared.browseWebDir)
            return
        }

        // 3.6：主根 = 包内 WebEffect 目录（全量前端）；缺失时回退旧 OTA 根。
        if let webEffectDir = WebRootManager.shared.webEffectDir {
            serveStatic(request: request, rawPath: rawPath, handler: handler, root: webEffectDir)
        } else {
            serveStatic(request: request, rawPath: rawPath, handler: handler)
        }
    }

    // MARK: - 跨表面桥（/__bridge/*，协议见 BridgeStore）

    private func handleBridge(request: HTTPRequest, handler: ConnectionHandler) {
        let rawPath = request.pathWithoutQuery
        let jsonHeaders: [(String, String)] = [("Content-Type", "application/json; charset=utf-8"),
                                               ("Cache-Control", "no-store")]
        func respondJson(_ object: [String: Any]) {
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
            handler.respond(status: 200, reason: "OK", headers: jsonHeaders, body: data)
        }
        func respondBadRequest() {
            handler.respond(status: 400, reason: "Bad Request",
                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                            body: Data("Bad Request".utf8))
        }

        switch rawPath {
        case "/__bridge/cmd":
            guard request.method == "POST",
                  let cmd = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
                respondBadRequest()
                return
            }
            let assigned = BridgeStore.shared.enqueue(cmd)
            respondJson(["ok": true, "seq": assigned])
        case "/__bridge/cmds":
            var since = 0
            if let qIdx = request.target.firstIndex(of: "?") {
                let query = request.target[request.target.index(after: qIdx)...]
                for pair in query.split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    if kv.count == 2, kv[0] == "since" { since = Int(kv[1]) ?? 0 }
                }
            }
            let result = BridgeStore.shared.commands(since: since)
            respondJson(["seq": result.seq, "cmds": result.cmds])
        case "/__bridge/state":
            if request.method == "POST" {
                if let state = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] {
                    BridgeStore.shared.setState(state)
                }
                respondJson(["ok": true])
            } else {
                let snap = BridgeStore.shared.snapshot()
                respondJson(["state": snap.state ?? NSNull()])
            }
        case "/__bridge/session":
            let snap = BridgeStore.shared.snapshot()
            respondJson(["lastPlay": snap.lastPlay ?? NSNull(), "state": snap.state ?? NSNull()])
        default:
            handler.respond(status: 404, reason: "Not Found",
                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                            body: Data("Not Found".utf8))
        }
    }

    // MARK: - 静态文件

    private func serveStatic(request: HTTPRequest, rawPath: String, handler: ConnectionHandler,
                             root: URL = WebRootManager.shared.activeWebDir) {
        let decoded = rawPath.removingPercentEncoding ?? rawPath

        var relative = decoded
        if relative.hasPrefix("/") { relative.removeFirst() }
        if relative.isEmpty { relative = "index.html" }

        var candidate = root.appendingPathComponent(relative)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
            candidate = candidate.appendingPathComponent("index.html")
        }

        // 防目录穿越：标准化后必须仍在根目录内
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            handler.respond(status: 403, reason: "Forbidden",
                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                            body: Data("Forbidden".utf8))
            return
        }

        if FileManager.default.fileExists(atPath: candidatePath) {
            sendFile(url: URL(fileURLWithPath: candidatePath), request: request, handler: handler)
            return
        }

        // SPA 回退：无扩展名的路径交给前端路由（返回 index.html）；带扩展名的缺失文件回真实 404
        let ext = (decoded as NSString).pathExtension
        if ext.isEmpty {
            let index = root.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: index.path) {
                sendFile(url: index, request: request, handler: handler)
                return
            }
        }
        handler.respond(status: 404, reason: "Not Found",
                        headers: [("Content-Type", "text/plain; charset=utf-8")],
                        body: Data("Not Found".utf8))
    }

    private func sendFile(url: URL, request: HTTPRequest, handler: ConnectionHandler) {
        do {
            let data = try Data(contentsOf: url)
            let mime = LocalServer.mimeType(forExtension: url.pathExtension.lowercased())
            // 本地文件读取成本低，一律 no-cache，保证整包版本切换后不吃旧缓存
            let headers: [(String, String)] = [("Content-Type", mime),
                                               ("Cache-Control", "no-cache")]
            if request.method == "HEAD" {
                handler.respond(status: 200, reason: "OK", headers: headers, body: Data(),
                                contentLengthOverride: data.count)
            } else {
                handler.respond(status: 200, reason: "OK", headers: headers, body: data)
            }
        } catch {
            handler.respond(status: 500, reason: "Internal Server Error",
                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                            body: Data("Read Error".utf8))
        }
    }

    // MARK: - 常量

    /// /sw.js 自注销 stub：装上后立即注销自身并清掉 Workbox 预缓存，
    /// 之后页面在壳内以「无 Service Worker」方式运行。
    static let serviceWorkerStub = """
    // Folia iOS shell: Service Worker is disabled inside the app shell.
    // Version management is handled by the shell itself (bundled web root + OTA bundles).
    self.addEventListener('install', function () { self.skipWaiting(); });
    self.addEventListener('activate', function (event) {
      event.waitUntil((async function () {
        try {
          var keys = await caches.keys();
          await Promise.all(keys.map(function (k) { return caches.delete(k); }));
        } catch (e) {}
        try { await self.registration.unregister(); } catch (e) {}
      })());
    });
    """

    static func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "webmanifest": return "application/manifest+json; charset=utf-8"
        case "map": return "application/json; charset=utf-8"
        case "txt": return "text/plain; charset=utf-8"
        case "xml": return "application/xml; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "eot": return "application/vnd.ms-fontobject"
        case "wasm": return "application/wasm"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "wav": return "audio/wav"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "Status"
        }
    }
}

// MARK: - HTTP 请求模型

struct HTTPRequest {
    let method: String
    /// 原始请求目标（含 query，未解码）
    let target: String
    /// 不含 query 的原始路径（未解码）
    var pathWithoutQuery: String {
        if let idx = target.firstIndex(of: "?") {
            return String(target[..<idx])
        }
        return target
    }
    /// 保持原始顺序的请求头列表
    let headers: [(String, String)]
    let body: Data

    func header(_ name: String) -> String? {
        headers.first { $0.0.lowercased() == name.lowercased() }?.1
    }
}

// MARK: - 单连接处理

private final class ConnectionHandler {
    private let connection: NWConnection
    private weak var server: LocalServer?
    private var buffer = Data()
    private var headerEnd: Int?
    private var expectedBodyLength = 0
    private var responded = false

    init(connection: NWConnection, server: LocalServer) {
        self.connection = connection
        self.server = server
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish() }
            if case .cancelled = state { self?.finish() }
        }
        connection.start(queue: DispatchQueue(label: "com.miller.folia.conn"))
        receiveMore()
    }

    private func receiveMore() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.buffer.append(data)
                if self.tryParseAndRoute() { return }
            }
            if error != nil || isComplete {
                self.finish()
                return
            }
            self.receiveMore()
        }
    }

    /// 数据够一整请求时返回 true 并完成路由
    private func tryParseAndRoute() -> Bool {
        if headerEnd == nil {
            guard let range = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
                // 请求头异常巨大时直接断开，避免内存被撑爆
                if buffer.count > 1024 * 1024 { finish() ; return true }
                return false
            }
            headerEnd = range.upperBound
            let headerData = buffer.subdata(in: 0..<range.lowerBound)
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                respondBadRequest()
                return true
            }
            var lines = headerText.components(separatedBy: "\r\n")
            let requestLine = lines.removeFirst()
            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else {
                respondBadRequest()
                return true
            }
            var parsedHeaders: [(String, String)] = []
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                parsedHeaders.append((name, value))
            }
            pendingMethod = String(parts[0])
            pendingTarget = String(parts[1])
            pendingHeaders = parsedHeaders
            if let cl = parsedHeaders.first(where: { $0.0.lowercased() == "content-length" })?.1,
               let n = Int(cl) {
                expectedBodyLength = n
            } else {
                expectedBodyLength = 0
            }
            // 带请求体但没有 Content-Length（chunked）本实现不支持，回 501 而不是挂死
            if let te = parsedHeaders.first(where: { $0.0.lowercased() == "transfer-encoding" })?.1,
               te.lowercased().contains("chunked") {
                respond(status: 501, reason: "Not Implemented",
                        headers: [("Content-Type", "text/plain; charset=utf-8")],
                        body: Data("Chunked request bodies are not supported".utf8))
                return true
            }
        }
        guard let end = headerEnd else { return false }
        guard buffer.count - end >= expectedBodyLength else { return false }
        let body = buffer.subdata(in: end..<(end + expectedBodyLength))
        let request = HTTPRequest(method: pendingMethod, target: pendingTarget,
                                  headers: pendingHeaders, body: body)
        server?.route(request, for: self)
        return true
    }

    private var pendingMethod = ""
    private var pendingTarget = ""
    private var pendingHeaders: [(String, String)] = []

    private func respondBadRequest() {
        respond(status: 400, reason: "Bad Request",
                headers: [("Content-Type", "text/plain; charset=utf-8")],
                body: Data("Bad Request".utf8))
    }

    /// 组装并发送 HTTP 响应（Connection: close，发送完断开）
    func respond(status: Int, reason: String, headers: [(String, String)], body: Data,
                 contentLengthOverride: Int? = nil) {
        guard !responded else { return }
        responded = true
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(contentLengthOverride ?? body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
            self?.finish()
        })
    }

    private var finished = false
    private func finish() {
        guard !finished else { return }
        finished = true
        server?.handlerFinished(self)
    }
}

// MARK: - /api 反向代理

private enum Proxy {

    /// 专用 session：禁用 URLSession 自带 cookie 管理——Cookie 由 WebView 按源规则管，
    /// 我们只做原样转发，避免双重处理。
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

    static func proxy(request: HTTPRequest, handler: ConnectionHandler) {
        guard let url = URL(string: LocalServer.upstreamBase + request.target) else {
            handler.respond(status: 502, reason: "Bad Gateway",
                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                            body: Data("Bad upstream URL".utf8))
            return
        }
        var upstream = URLRequest(url: url)
        upstream.httpMethod = request.method
        // 逐项转发请求头；Host/Content-Length 由 URLSession 生成，
        // Accept-Encoding 强制 identity，避免上游 gzip 后与回传头不一致
        for (name, value) in request.headers {
            let lower = name.lowercased()
            if ["host", "connection", "content-length", "accept-encoding"].contains(lower) { continue }
            upstream.addValue(value, forHTTPHeaderField: name)
        }
        upstream.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if !request.body.isEmpty {
            upstream.httpBody = request.body
        }

        let task = session.dataTask(with: upstream) { data, response, error in
            if let error = error {
                NSLog("[Proxy] \(request.method) \(request.target) failed: \(error)")
                handler.respond(status: 502, reason: "Bad Gateway",
                                headers: [("Content-Type", "text/plain; charset=utf-8")],
                                body: Data("Upstream Error".utf8))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                handler.respond(status: 502, reason: "Bad Gateway",
                                headers: [("Content-Type", "text/plain; charset=utf-8")],
                                body: Data("Bad upstream response".utf8))
                return
            }
            var outHeaders: [(String, String)] = []
            var setCookies: [String] = []
            for (key, value) in http.allHeaderFields {
                guard let name = key as? String, let text = value as? String else { continue }
                let lower = name.lowercased()
                // 这些头由本服务器重新生成；Content-Encoding 因 identity 请求一般不会出现，
                // 若出现则说明上游未按 identity 返回，仍原样透传由 WebView 处理
                if ["content-length", "transfer-encoding", "connection"].contains(lower) { continue }
                if lower == "set-cookie" {
                    setCookies.append(text)
                    continue
                }
                outHeaders.append((name, text))
            }
            // Set-Cookie 可能被合并成一条逗号拼接字符串；用 HTTPCookie 解析后逐条重发。
            // 重发时去掉 Domain 属性：让 cookie 成为本机源（127.0.0.1）的 host-only cookie，
            // 这样 WebView 才会存下并在后续请求里带给本服务器，代理再原样转给上游。
            if !setCookies.isEmpty {
                let parsed = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": setCookies.joined(separator: ", ")],
                                                for: url)
                for cookie in parsed {
                    outHeaders.append(("Set-Cookie", reserialize(cookie)))
                }
            }
            var body = data ?? Data()
            let status = http.statusCode
            // 3.6 (3)：JSON 响应里的封面 URL 改写到本地图片代理（按显示尺寸
            // 降分辨率下发），治格子墙全尺寸封面解码把 WebView 进程撑爆被杀。
            // 只改图片地址这一处数据，不动任何字段结构与界面。
            if (200...299).contains(status), !body.isEmpty,
               let contentType = http.value(forHTTPHeaderField: "Content-Type"),
               contentType.contains("json") {
                body = CoverURLRewriter.rewrite(body: body, port: LocalServer.shared.port)
            }
            if status == 204 || status == 304 {
                handler.respond(status: status,
                                reason: LocalServer.reasonPhrase(for: status),
                                headers: outHeaders, body: Data())
            } else {
                handler.respond(status: status,
                                reason: LocalServer.reasonPhrase(for: status),
                                headers: outHeaders, body: body)
            }
        }
        task.resume()
    }

    /// 把 HTTPCookie 重新序列化为一条 Set-Cookie 头（不带 Domain，见 proxy 内注释）
    private static func reserialize(_ cookie: HTTPCookie) -> String {
        var parts = ["\(cookie.name)=\(cookie.value)"]
        if let expires = cookie.expiresDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            parts.append("Expires=\(formatter.string(from: expires))")
        }
        if !cookie.path.isEmpty {
            parts.append("Path=\(cookie.path)")
        }
        if cookie.isSecure { parts.append("Secure") }
        if cookie.isHTTPOnly { parts.append("HttpOnly") }
        return parts.joined(separator: "; ")
    }
}

// MARK: - 封面图本地代理（3.6 (3) 热修）

/// /img/<base64url(原图URL)>?w=<最大边>：把平台 CDN 的全尺寸封面在本地降
/// 分辨率后再下发给 WebView，并做磁盘缓存与同图合并请求。
/// 地址形态是刻意的：前端（原版 App）多处把 http: 封面无条件升级成 https:
/// （provider 入库、toSafeRemoteUrl、Carousel3D 等），还有按 '126.net' 子串
/// 匹配改尺寸的兜底——绝对 http 代理地址会被升成 https://127.0.0.1 打不通，
/// 明文内嵌原地址又会触发子串误伤。相对路径 + base64url（无 '.'、无明文
/// 主机名）两种都避开，且路径自带唯一身份，前端的封面同一性判断不串图。
///
/// 动机（2026-11-16 真机实证）：格子墙几十张 1500–3000px 封面同时解码，
/// WKWebView 内容进程内存冲爆被系统杀（Jetsam），页面反复重启。改的是
/// 图片源分辨率（数据层），不改 CSS、不封 DPR、不关动画，不属于降级特效。
/// 任何一步失败都 302 回原图地址，最差与不改写时一致，绝不让封面消失。
private enum CoverImageProxy {

    /// 只代理音乐平台图片 CDN 的域名（后缀匹配），防被当开放代理用。
    static let allowedHostSuffixes = ["126.net", "163.com", "gtimg.cn", "qq.com", "kugou.com", "sinaimg.cn"]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// 同时进行的取图+缩放上限（本地 CPU 与内存保护）。
    private static let gate = DispatchSemaphore(value: 3)
    private static let workQueue = DispatchQueue(label: "com.miller.folia.imgproxy", qos: .utility, attributes: .concurrent)

    /// 同图在途合并：key -> 等待者。
    private static let flightLock = NSLock()
    private static var inFlight: [String: [(Data?, String?) -> Void]] = [:]

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("folia-img", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func isAllowedHost(_ host: String) -> Bool {
        allowedHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func handle(request: HTTPRequest, handler: ConnectionHandler) {
        guard request.method == "GET" || request.method == "HEAD" else {
            handler.respond(status: 405, reason: "Method Not Allowed",
                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                            body: Data("Method Not Allowed".utf8))
            return
        }
        let params = queryParams(request.target)
        // 原图地址走路径段的 base64url（改写侧 CoverURLRewriter 同口径）：
        // 相对路径 + 无明文主机名，避开前端多处 http→https 升级与 '126.net'
        // 子串匹配对代理地址的误伤。旧 ?src= 形式仅作兜底兼容。
        let src = srcFromPath(request.target) ?? params["src"]
        guard let src, let srcURL = URL(string: src),
              let host = srcURL.host?.lowercased(), isAllowedHost(host),
              srcURL.scheme == "https" || srcURL.scheme == "http" else {
            handler.respond(status: 400, reason: "Bad Request",
                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                            body: Data("Bad src".utf8))
            return
        }
        let maxPixel = min(max(Int(params["w"] ?? "") ?? 1024, 240), 1600)
        let key = cacheKey(src: src, maxPixel: maxPixel)

        // 磁盘命中直接回（HEAD 只回头）。
        let fileURL = cacheDir.appendingPathComponent(key + ".jpg")
        if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
            respondImage(data: data, request: request, handler: handler)
            return
        }

        fetchCoalesced(key: key, srcURL: srcURL, maxPixel: maxPixel) { data, contentType in
            if let data, let contentType {
                if request.method != "HEAD" {
                    try? data.write(to: fileURL, options: .atomic)
                    trimCacheIfNeeded()
                }
                handler.respond(status: 200, reason: "OK",
                                headers: [("Content-Type", contentType),
                                          ("Cache-Control", "public, max-age=604800")],
                                body: request.method == "HEAD" ? Data() : data,
                                contentLengthOverride: request.method == "HEAD" ? data.count : nil)
            } else {
                // 兜底：跳回原图，WebView 直连加载，最差与改写前一致。
                handler.respond(status: 302, reason: "Found",
                                headers: [("Location", src)],
                                body: Data())
            }
        }
    }

    private static func respondImage(data: Data, request: HTTPRequest, handler: ConnectionHandler) {
        if request.method == "HEAD" {
            handler.respond(status: 200, reason: "OK",
                            headers: [("Content-Type", "image/jpeg"),
                                      ("Cache-Control", "public, max-age=604800")],
                            body: Data(), contentLengthOverride: data.count)
        } else {
            handler.respond(status: 200, reason: "OK",
                            headers: [("Content-Type", "image/jpeg"),
                                      ("Cache-Control", "public, max-age=604800")],
                            body: data)
        }
    }

    private static func fetchCoalesced(key: String, srcURL: URL, maxPixel: Int,
                                       completion: @escaping (Data?, String?) -> Void) {
        flightLock.lock()
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            flightLock.unlock()
            return
        }
        inFlight[key] = [completion]
        flightLock.unlock()

        workQueue.async {
            gate.wait()
            let result = fetchAndScale(srcURL: srcURL, maxPixel: maxPixel)
            gate.signal()
            flightLock.lock()
            let waiters = inFlight.removeValue(forKey: key) ?? []
            flightLock.unlock()
            for waiter in waiters { waiter(result.0, result.1) }
        }
    }

    private static func fetchAndScale(srcURL: URL, maxPixel: Int) -> (Data?, String?) {
        let semaphore = DispatchSemaphore(value: 0)
        var fetched: Data?
        let task = session.dataTask(with: srcURL) { data, response, _ in
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                fetched = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 25)
        guard let data = fetched, !data.isEmpty, data.count <= 16 * 1024 * 1024 else { return (nil, nil) }
        guard let scaled = downscale(data: data, maxPixel: maxPixel) else { return (nil, nil) }
        return (scaled, "image/jpeg")
    }

    /// ImageIO 缩略图：只解码到目标尺寸，不整图进内存。
    private static func downscale(data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// 从 /img/<base64url> 路径段解出原图地址（target 含 query，先剥掉）。
    private static func srcFromPath(_ target: String) -> String? {
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        guard path.hasPrefix("/img/") else { return nil }
        let encoded = String(path.dropFirst("/img/".count))
        guard !encoded.isEmpty else { return nil }
        var b64 = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func cacheKey(src: String, maxPixel: Int) -> String {
        let digest = SHA256.hash(data: Data("\(src)#\(maxPixel)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 缓存总量超过约 200MB 时按修改时间删旧到约 150MB（低频触发即可）。
    private static var lastTrimAt = Date.distantPast
    private static func trimCacheIfNeeded() {
        // lastTrimAt 的检查+赋值在 flightLock 内做，避免多连接完成回调并发读写（审查低 10）。
        flightLock.lock()
        guard Date().timeIntervalSince(lastTrimAt) > 60 else { flightLock.unlock(); return }
        lastTrimAt = Date()
        flightLock.unlock()
        workQueue.async {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
            var total = 0
            var entries: [(url: URL, size: Int, date: Date)] = []
            for file in files {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = values?.fileSize ?? 0
                total += size
                entries.append((file, size, values?.contentModificationDate ?? .distantPast))
            }
            guard total > 200 * 1024 * 1024 else { return }
            for entry in entries.sorted(by: { $0.date < $1.date }) {
                if total <= 150 * 1024 * 1024 { break }
                try? fm.removeItem(at: entry.url)
                total -= entry.size
            }
        }
    }

    private static func queryParams(_ target: String) -> [String: String] {
        guard let qIdx = target.firstIndex(of: "?") else { return [:] }
        var result: [String: String] = [:]
        for pair in target[target.index(after: qIdx)...].split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return result
    }
}

// MARK: - /api JSON 封面 URL 改写（3.6 (3) 热修）

/// 把 JSON 响应里平台 CDN 的封面地址改写成本地 /img 代理地址。
/// 尺寸档：blur 图 480、avatar 512、其余（专辑封面）1024。
/// 只认图片专用域名或带图片扩展名的地址；改写失败/不匹配一律原样保留。
private enum CoverURLRewriter {

    // 专用图片域名只留图片 CDN 本体：music.126.net / kugou.com 的同后缀域名还承载
    // 音频流（m*.music.126.net、webfs.kugou.com），放进来会把流地址误改成图片代理
    // （审查高 1）。这两家的图片 URL 基本带图片扩展名，走扩展名规则即可。
    private static let dedicatedImageHostSuffixes = ["gtimg.cn", "singerimg.kugou.com"]
    private static let imageExtensions = [".jpg", ".jpeg", ".png", ".webp"]
    /// 音频扩展名黑名单：任何情况下不改写（双保险）。
    private static let audioExtensions = [".mp3", ".m4a", ".flac", ".aac", ".ogg", ".wav", ".opus"]

    static func rewrite(body: Data, port: UInt16) -> Data {
        guard port != 0, var text = String(data: body, encoding: .utf8) else { return body }
        // JSON 里 \/ 与 / 等价，先归一方便匹配（语义不变）。
        if text.contains("\\/") { text = text.replacingOccurrences(of: "\\/", with: "/") }
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s"'<>\\]+"#, options: []) else { return body }
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return body }
        var changed = false
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let original = String(text[range])
            guard let replacement = proxiedURL(original, port: port) else { continue }
            text.replaceSubrange(range, with: replacement)
            changed = true
        }
        return changed ? Data(text.utf8) : body
    }

    private static func proxiedURL(_ original: String, port: UInt16) -> String? {
        guard let url = URL(string: original), let host = url.host?.lowercased(),
              CoverImageProxy.isAllowedHost(host) else { return nil }
        let path = url.path.lowercased()
        guard !audioExtensions.contains(where: { path.hasSuffix($0) }) else { return nil }
        let dedicated = dedicatedImageHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
        let hasImageExtension = imageExtensions.contains { path.hasSuffix($0) }
        guard dedicated || hasImageExtension else { return nil }
        let lower = original.lowercased()
        let tier = lower.contains("blur") ? 480 : (lower.contains("avatar") ? 512 : 1024)
        // 相对路径 + base64url：见 CoverImageProxy 头注（避前端 https 升级与子串误伤）。
        _ = port // 地址已改相对路径，端口不再出现在产物里（签名保留兼容调用点）
        return "/img/\(base64URL(original))?w=\(tier)"
    }

    /// base64url（无填充）：字母表不含 '.'，原地址的主机名不会以明文出现。
    private static func base64URL(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
