import Foundation
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
                if case .posix(let code) = error, code == POSIXErrorCode.addrInUse {
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

        if rawPath == "/sw.js" {
            handler.respond(status: 200, reason: "OK",
                            headers: [("Content-Type", "text/javascript; charset=utf-8"),
                                      ("Cache-Control", "no-store")],
                            body: Data(LocalServer.serviceWorkerStub.utf8))
            return
        }

        if rawPath == "/api" || rawPath.hasPrefix("/api/") {
            Proxy.proxy(request: request, handler: handler)
            return
        }

        serveStatic(request: request, rawPath: rawPath, handler: handler)
    }

    // MARK: - 静态文件

    private func serveStatic(request: HTTPRequest, rawPath: String, handler: ConnectionHandler) {
        let root = WebRootManager.shared.activeWebDir
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
            var headers: [(String, String)] = [("Content-Type", mime),
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
            let body = data ?? Data()
            let status = http.statusCode
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
