import CryptoKit
import Foundation
import ImageIO
import Network

/// 内置本地 HTTP 服务器（与安卓版同构）：
/// - NWListener 监听 127.0.0.1:18765（仅回环接口；端口被占则 +1 回退，最多试 11 个端口）
/// - 静态文件：根目录 = WebRootManager 当前生效版本目录；MIME 齐全；SPA 回退 index.html
/// - /sw.js：返回自注销 stub（壳内禁用 Folia 自带 Service Worker，避免其缓存与
///   壳的整包版本切换机制互相打架；离线能力由本地文件本身提供）
/// - /api/*：反向代理（3.6 (4) 起主上游为各平台 EdgeOne 函数直连，传输
///   错误/5xx 时回退 Netlify 站点一次；GET 响应带磁盘缓存与 TTL）。
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
    /// 同端口重试计数（3.7 (13) #3）：监听失败先在原端口重试，
    /// 避免端口漂移后已加载的网页与数据客户端集体失联。
    private var samePortRetries = 0
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
                self.samePortRetries = 0
                NSLog("[LocalServer] listening on 127.0.0.1:\(port)")
                FoliaBridgeLogStore.shared.write(
                    level: "info", module: "server",
                    message: "listening on 127.0.0.1:\(port)")
                if let cb = self.onReady {
                    DispatchQueue.main.async { cb(port) }
                }
            case .failed(let error):
                NSLog("[LocalServer] failed on \(port): \(error)")
                FoliaBridgeLogStore.shared.write(
                    level: "error", module: "server",
                    message: "listener failed on \(port): \(error)")
                listener.cancel()
                // 端口被占：同端口重试不会恢复，立即漂移（DS31）。
                if case .posix(let code) = error, code == .EADDRINUSE {
                    self.samePortRetries = 0
                    if retriesLeft > 0 {
                        self.attempt(port: port + 1, retriesLeft: retriesLeft - 1)
                    }
                    return
                }
                if self.samePortRetries < 3 {
                    // 先同端口重试（1 秒后）：端口不变，已加载的
                    // 网页与数据客户端无需感知（3.7 (13) #3）。
                    self.samePortRetries += 1
                    let retryNo = self.samePortRetries
                    self.listenerQueue.asyncAfter(deadline: .now() + 1) { [weak self] in
                        NSLog("[LocalServer] same-port retry \(retryNo) on \(port)")
                        self?.attempt(port: port, retriesLeft: retriesLeft)
                    }
                } else if retriesLeft > 0 {
                    self.samePortRetries = 0
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
            let rawData = try Data(contentsOf: url)
            // 3.6 (7) P1：JS 供包时做墙解码登记表钳制定点替换（fail-open）。
            // 3.6 (8) 止损停用：实查登记表只存 URL 字符串、不持有位图，
            // 钳制压不到真实内存（WebKit 图片缓存），且大书库登记抖动
            // 放大取图请求、出图更慢（review-367 取证 + DS 第十七轮）。
            var patchCap: Int? = nil
            let data: Data
            if WallRegistryPatch.isEnabled, url.pathExtension.lowercased() == "js" {
                let (patched, usedCap) = WallRegistryPatch.apply(to: rawData, fileName: url.lastPathComponent)
                data = patched
                patchCap = usedCap
            } else {
                data = rawData
            }
            let mime = LocalServer.mimeType(forExtension: url.pathExtension.lowercased())
            // 本地文件读取成本低，一律 no-cache，保证整包版本切换后不吃旧缓存
            var headers: [(String, String)] = [("Content-Type", mime),
                                               ("Cache-Control", "no-cache")]
            if let patchCap {
                headers.append(("X-Folia-Registry-Cap", String(patchCap)))
            }
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

// MARK: - 持久文件日志（3.6 (4) 最小埋点）

/// Documents/folia-native.log：只记生命周期级事件（进程终止/重载/视图
/// 恢复）与 /api 慢请求（>1s）/失败，供真机复盘。纪律取自社区版 3.0.5 的
/// 真机教训：环形上限 2MB、串行队列异步写、写失败一律静默吞掉、错误
/// 路径不再写日志、不记 Cookie/csrf/token 任何凭据值；排除 iCloud 备份。
enum FoliaFileLog {
    private static let queue = DispatchQueue(label: "com.miller.folia.filelog")
    private static let maxBytes = 2 * 1024 * 1024

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("folia-native.log")
    }

    static func write(_ module: String, _ message: String) {
        queue.async {
            let line = "\(ISO8601DateFormatter().string(from: Date())) [\(module)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let url = fileURL
            do {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    var mutable = url
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    try? mutable.setResourceValues(values)
                }
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? NSNumber, size.intValue > maxBytes,
                   let existing = try? Data(contentsOf: url) {
                    try Data(existing.suffix(512 * 1024)).write(to: url, options: .atomic)
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // 静默：日志失败绝不影响主流程，也不再记录这次失败（防自激）。
            }
        }
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

    // MARK: - 上游映射（3.6 (4)：去 Netlify 跳）

    /// 各平台 EdgeOne 函数直连地址（与 EdgeOneAPIClient 的 backup 同源）。
    /// Netlify 站点只剩回退角色：主上游传输错误或 5xx 时回退一次。
    private static let edgeOneBases: [(prefix: String, base: String)] = [
        ("/api/netease", "https://folia-netease-8v5g6dx9.edgeone.cool"),
        ("/api/qq", "https://folia-qq-8j540jls.edgeone.cool"),
        ("/api/kugou", "https://folia-kugou-k62owtqf.edgeone.cool"),
    ]

    private static func upstreamURLs(for target: String) -> (primary: URL?, fallback: URL?) {
        for (prefix, base) in edgeOneBases
        where target.hasPrefix(prefix + "/") || target.hasPrefix(prefix + "?") {
            let rest = String(target.dropFirst(prefix.count))
            return (URL(string: base + rest), URL(string: LocalServer.upstreamBase + target))
        }
        return (URL(string: LocalServer.upstreamBase + target), nil)
    }

    // MARK: - 上游健康记忆（3.6 (5)）

    /// 3.6 (4) 真机实锤：edgeone.cool 是 EdgeOne Makers 预览域名，项目
    /// 部署区域为「全球（不含中国大陆）」，大陆来源直连在边缘层被 401
    /// 拦截（HTML 页、请求根本到不了函数），而旧回退只认传输错误/5xx，
    /// 401 被原样交回页面导致全量 /api 失败。修复：平台级拦截可回退，
    /// 且一旦证实被拦，该平台 30 分钟内直走 Netlify，不让每个请求都
    /// 先撞一次墙。
    private static func platformKey(for target: String) -> String? {
        for (prefix, _) in edgeOneBases
        where target.hasPrefix(prefix + "/") || target.hasPrefix(prefix + "?") {
            return String(prefix.dropFirst("/api/".count))
        }
        return nil
    }

    private static func edgeOneDown(_ platform: String) -> Bool {
        UserDefaults.standard.double(forKey: "folia.eoDown.\(platform)") > Date().timeIntervalSince1970
    }

    private static func markEdgeOneDown(_ platform: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970 + 1800,
                                  forKey: "folia.eoDown.\(platform)")
    }

    private enum Rejection {
        case transport, serverError, platformBlock
        var tag: String {
            switch self {
            case .transport: return "transport"
            case .serverError: return "5xx"
            case .platformBlock: return "platform-block"
            }
        }
    }

    /// 主上游响应是否属于「没拿到可用 API 响应」：传输错误、5xx、平台
    /// 层拦截（401/403/429/451——请求未达函数），或 2xx 但不是 JSON
    /// （200 挑战/拦截页）。业务性 4xx（400/404 的 JSON）不回退。
    private static func rejection(data: Data?, http: HTTPURLResponse?, error: Error?) -> Rejection? {
        if error != nil { return .transport }
        guard let http else { return .transport }
        if http.statusCode >= 500 { return .serverError }
        if [401, 403, 429, 451].contains(http.statusCode) { return .platformBlock }
        if (200...299).contains(http.statusCode), let data, !data.isEmpty {
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            if !contentType.contains("json") { return .platformBlock }
        }
        return nil
    }

    // MARK: - GET 磁盘缓存（3.6 (4)）

    private static var apiCacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("folia-api", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 缓存键含 Cookie 哈希：不同登录态不串数据，哈希值不可逆推凭据。
    /// 另含代次号（独立审查 M4）：歌单增删/订阅/喜欢类写操作成功后代次
    /// +1，旧代次条目整体作废（孤儿文件由容量淘汰回收），避免用户改完
    /// 歌单后在 TTL 内还看到旧内容。
    private static var cacheGeneration: Int {
        UserDefaults.standard.integer(forKey: "folia.apiCacheGen")
    }

    private static func bumpCacheGeneration() {
        UserDefaults.standard.set(cacheGeneration + 1, forKey: "folia.apiCacheGen")
    }

    private static func cacheFile(target: String, cookieHash: String) -> URL {
        apiCacheDir.appendingPathComponent(sha256Hex(target + "|" + cookieHash + "|g\(cacheGeneration)") + ".json")
    }

    /// 网易云大量错误是 HTTP 200 + 业务 code != 200，错误体不许落缓存
    /// （独立审查 H2 附带项）。仅对网易云目标生效：QQ/酷狗的 code 约定
    /// 不同（0 为成功），不在此判。无 code 字段时放行。
    private static func neteaseBusinessOK(_ body: Data, target: String) -> Bool {
        guard target.hasPrefix("/api/netease") else { return true }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let code = (object["code"] as? NSNumber)?.intValue else { return true }
        return code == 200
    }

    /// API 缓存容量上限与 LRU 淘汰（独立审查 M1）：图片缓存有配额，
    /// API 缓存此前无界增长。超限时按修改时间从旧到新删到达标。
    private static let apiCacheCapBytes = 150 * 1024 * 1024

    private static func trimAPICacheIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: apiCacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        var entries: [(url: URL, size: Int, mtime: Date)] = []
        var total = 0
        for file in files {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            total += size
            entries.append((file, size, values?.contentModificationDate ?? .distantPast))
        }
        guard total > apiCacheCapBytes else { return }
        for entry in entries.sorted(by: { $0.mtime < $1.mtime }) {
            if total <= apiCacheCapBytes { break }
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// GET 缓存 TTL（秒）；nil 表示不缓存（登录/二维码/取流/写操作类）。
    /// 独立审查 M4 补排除：personal_fm 每次须取新一批、check 类是实时
    /// 校验、download 地址带过期签名——都不许进缓存。
    private static func cacheTTL(for target: String) -> TimeInterval? {
        let path = target.components(separatedBy: "?").first ?? target
        let lower = path.lowercased()
        if lower.contains("login") || lower.contains("/qr") || lower.contains("/song/url")
            || lower.contains("scrobble") || lower.contains("/like")
            || lower.contains("personal_fm") || lower.contains("/check/")
            || lower.contains("download") { return nil }
        if lower.contains("lyric") { return 24 * 3600 }
        if lower.contains("/playlist/detail") || lower.contains("/song/detail") { return 600 }
        if lower.contains("search") { return 1800 }
        return 300
    }

    /// 封面分档上下文（3.6 (6)，DS 第十三轮对账定版，废弃旧 isListContext
    /// 口径）：只有白名单内的集合列表端点把 coverImgUrl 降到墙档；详情类
    /// 与未枚举端点一律维持现行档位，防详情头图被误降（DS Q7 点名风险）。
    /// 榜单详情实际走 playlist/detail（详情口径保 768）；artist/ 的大图走
    /// picUrl/avatarUrl，其 coverImgUrl 只是专辑/歌单小卡，归列表。
    private static func isWallListTarget(_ target: String) -> Bool {
        let path = (target.components(separatedBy: "?").first ?? target).lowercased()
        if path.contains("/playlist/detail") || path.contains("/song/detail") { return false }
        return path.contains("/user/playlist") || path.contains("/toplist")
            || path.contains("search") || path.contains("/personalized")
            || path.contains("/artist/") || path.contains("/recommend")
            || path.contains("/dj/program") || path.contains("/album/list")
    }

    private static func freshCacheData(target: String, cookieHash: String, ttl: TimeInterval) -> Data? {
        let file = cacheFile(target: target, cookieHash: cookieHash)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        // 过期文件顺手删掉，不让它占着容量配额（M1）。
        guard Date().timeIntervalSince(mtime) < ttl else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        return data
    }

    static func proxy(request: HTTPRequest, handler: ConnectionHandler) {
        let startedAt = Date()
        let cookieHash = sha256Hex(request.header("Cookie") ?? "")
        // GET 缓存先行：新鲜条目直接回，不打上游（存的是已改写封面的成品体）。
        var cacheTarget: String?
        if request.method == "GET", let ttl = cacheTTL(for: request.target) {
            if let cached = freshCacheData(target: request.target, cookieHash: cookieHash, ttl: ttl) {
                handler.respond(status: 200, reason: "OK",
                                headers: [("Content-Type", "application/json; charset=utf-8"),
                                          ("X-Folia-Cache", "hit")],
                                body: cached)
                return
            }
            cacheTarget = request.target
        }

        let (edgeOneURL, netlifyURL) = upstreamURLs(for: request.target)
        let platform = platformKey(for: request.target)
        let pathOnly = request.target.components(separatedBy: "?").first ?? request.target
        let isIdempotent = request.method == "GET" || request.method == "HEAD"

        // 写请求固定走 Netlify 单上游（3.6 (5)，DS 对账）：EdgeOne 直连
        // 在大陆来源被预览域名拦截、未经真机证明，且写请求不许跨上游
        // 重放（独立审查 H1）。这与 3.6 (3) 验证过的路径一致。
        if !isIdempotent {
            guard let sole = netlifyURL ?? edgeOneURL else {
                handler.respond(status: 502, reason: "Bad Gateway",
                                headers: [("Content-Type", "text/plain; charset=utf-8")],
                                body: Data("Bad upstream URL".utf8))
                return
            }
            // 例外（3.6 (6) W5）：song/url 语义只读、重放无副作用，POST 也
            // 允许一次性跨上游重试（其余写请求维持不重放）。录屏里取流
            // 500 未复现，先靠重试降偶发 + finish 的 id/upstream 埋点定位。
            let songURLRetry: URL? = (pathOnly.contains("/song/url") && netlifyURL != nil
                                      && sole == netlifyURL && !(platform.map { edgeOneDown($0) } ?? false))
                ? edgeOneURL : nil
            perform(url: sole, request: request) { data, http, error in
                if let retryURL = songURLRetry,
                   let primaryRejection = Proxy.rejection(data: data, http: http, error: error) {
                    FoliaFileLog.write("api", "POST \(pathOnly) song/url retry reason=\(primaryRejection.tag) primaryStatus=\(http?.statusCode ?? 0)")
                    perform(url: retryURL, request: request) { data2, http2, error2 in
                        // 重试结果必须复检（独立审查中-1）：EdgeOne 直连在
                        // 大陆会被预览域名 401 拦截，未复检直接透传会把
                        // 401+HTML 交给页面，比原 500 更坏。重试被拒时记
                        // 健康标记，并回落主上游的原始结果。
                        if let retryRejection = Proxy.rejection(data: data2, http: http2, error: error2) {
                            if retryRejection == .platformBlock, let platform {
                                markEdgeOneDown(platform)
                            }
                            FoliaFileLog.write("api", "POST \(pathOnly) song/url retry rejected reason=\(retryRejection.tag); keeping primary result")
                            finish(data: data, http: http, error: error, url: sole,
                                   request: request, handler: handler, startedAt: startedAt,
                                   upstream: "netlify", cacheTarget: nil, cookieHash: cookieHash)
                            return
                        }
                        finish(data: data2, http: http2, error: error2, url: retryURL,
                               request: request, handler: handler, startedAt: startedAt,
                               upstream: "edgeone-retry", cacheTarget: nil, cookieHash: cookieHash)
                    }
                    return
                }
                finish(data: data, http: http, error: error, url: sole,
                       request: request, handler: handler, startedAt: startedAt,
                       upstream: "netlify", cacheTarget: nil, cookieHash: cookieHash)
            }
            return
        }

        // 该平台已被证实被拦且在记忆期内：直走 Netlify，不撞墙。
        if let platform, edgeOneDown(platform), let netlifyURL {
            perform(url: netlifyURL, request: request) { data, http, error in
                finish(data: data, http: http, error: error, url: netlifyURL,
                       request: request, handler: handler, startedAt: startedAt,
                       upstream: "netlify", cacheTarget: cacheTarget, cookieHash: cookieHash)
            }
            return
        }

        guard let primary = edgeOneURL else {
            handler.respond(status: 502, reason: "Bad Gateway",
                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                            body: Data("Bad upstream URL".utf8))
            return
        }
        perform(url: primary, request: request) { data, http, error in
            // 没拿到可用 API 响应就回退 Netlify 一次（3.6 (5) 放宽：
            // 3.6 (4) 只认传输错误/5xx，大陆直连的 401 拦截页漏网）。
            // 平台级拦截（请求未达函数）另记健康标记，30 分钟内直走备路。
            if let fallback = netlifyURL, let rejection = rejection(data: data, http: http, error: error) {
                if rejection == .platformBlock, let platform {
                    markEdgeOneDown(platform)
                }
                FoliaFileLog.write("api", "\(request.method) \(pathOnly) fallback reason=\(rejection.tag) primaryStatus=\(http?.statusCode ?? 0)")
                perform(url: fallback, request: request) { data2, http2, error2 in
                    finish(data: data2, http: http2, error: error2, url: fallback,
                           request: request, handler: handler, startedAt: startedAt,
                           upstream: "netlify-fallback", cacheTarget: cacheTarget, cookieHash: cookieHash)
                }
                return
            }
            finish(data: data, http: http, error: error, url: primary,
                   request: request, handler: handler, startedAt: startedAt,
                   upstream: netlifyURL != nil ? "edgeone" : "netlify",
                   cacheTarget: cacheTarget, cookieHash: cookieHash)
        }
    }

    /// song/url 请求里的首个歌曲 id（query 的 id= 或 body 的 "id"），仅供
    /// 失败日志定位；取不到返回 nil，绝不记录 Cookie/完整参数。
    private static func firstSongId(request: HTTPRequest) -> String? {
        if let query = request.target.components(separatedBy: "?").dropFirst().first {
            for pair in query.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2, kv[0] == "id" {
                    let digits = kv[1].prefix { $0.isNumber }
                    if !digits.isEmpty { return String(digits) }
                }
            }
        }
        if !request.body.isEmpty,
           let text = String(data: request.body, encoding: .utf8),
           let match = try? NSRegularExpression(pattern: "\"id\"\\s*:\\s*\"?(\\d+)")
               .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range])
        }
        return nil
    }

    private static func perform(url: URL, request: HTTPRequest,
                                completion: @escaping (Data?, HTTPURLResponse?, Error?) -> Void) {
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
            completion(data, response as? HTTPURLResponse, error)
        }
        task.resume()
    }

    private static func finish(data: Data?, http: HTTPURLResponse?, error: Error?, url: URL,
                               request: HTTPRequest, handler: ConnectionHandler,
                               startedAt: Date, upstream: String,
                               cacheTarget: String?, cookieHash: String) {
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let pathOnly = request.target.components(separatedBy: "?").first ?? request.target
        if let error = error {
            NSLog("[Proxy] \(request.method) \(request.target) failed: \(error)")
            FoliaFileLog.write("api", "\(request.method) \(pathOnly) FAILED \(elapsedMs)ms upstream=\(upstream)")
            handler.respond(status: 502, reason: "Bad Gateway",
                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                            body: Data("Upstream Error".utf8))
            return
        }
        guard let http else {
            handler.respond(status: 502, reason: "Bad Gateway",
                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                            body: Data("Bad upstream response".utf8))
            return
        }
        // 慢请求与上游错误落持久日志。3.6 (5) 起所有非 2xx 都记：
        // 3.6 (4) 只记 5xx/慢请求，真机 401 拦截正好漏在阈值外。
        // 3.6 (6) W5：song/url 的失败行补首个歌曲 id，下次真机复现可直接
        // 定位是哪首歌、哪个上游（DS Q7：只记 id/upstream/耗时，不记
        // Cookie 与完整参数）。
        if elapsedMs > 1000 || http.statusCode >= 400 {
            var line = "\(request.method) \(pathOnly) \(http.statusCode) \(elapsedMs)ms upstream=\(upstream) bytes=\(data?.count ?? 0)"
            if pathOnly.contains("/song/url"), let songId = firstSongId(request: request) {
                line += " songId=\(songId)"
            }
            FoliaFileLog.write("api", line)
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
        let isJSON = http.value(forHTTPHeaderField: "Content-Type")?.contains("json") ?? false
        if (200...299).contains(status), !body.isEmpty, isJSON {
            body = CoverURLRewriter.rewrite(body: body, port: LocalServer.shared.port,
                                            wallTier: isWallListTarget(request.target) ? CoverPolicy.wallTier : nil)
        }
        // GET 缓存落盘：200 + JSON + 无 Set-Cookie（带 Cookie 的响应多为
        // 登录态流转，不缓存）+ 网易云业务码 200。存改写后的成品体，
        // 命中时直接回。
        if let cacheTarget, status == 200, isJSON, setCookies.isEmpty, !body.isEmpty,
           neteaseBusinessOK(body, target: cacheTarget) {
            let file = cacheFile(target: cacheTarget, cookieHash: cookieHash)
            try? body.write(to: file, options: .atomic)
            prefetchQueue.async { trimAPICacheIfNeeded() }
            // 「我的歌单」列表一到手，后台把各歌单详情预热进缓存：
            // 用户点开任意自有歌单时大概率直接命中（治 #4 首次点开慢）。
            // 触发收紧为网易云（独立审查 H2 附带项：预热硬编码网易云
            // base 与缓存键，别家同名路径不许误触）。
            if cacheTarget.hasPrefix("/api/netease/user/playlist") {
                prefetchPlaylistDetails(from: body, cookie: request.header("Cookie") ?? "",
                                        cookieHash: cookieHash)
            }
        }
        // 写操作成功后推进缓存代次（M4）：歌单增删曲目/订阅/喜欢会改变
        // detail 与 user/playlist 的内容，旧代次条目整体作废。
        if request.method == "POST", (200...299).contains(status) {
            let lower = pathOnly.lowercased()
            if lower.contains("/playlist/tracks") || lower.contains("/playlist/subscribe")
                || lower.contains("/playlist/create") || lower.contains("/playlist/delete")
                || lower.contains("/like") {
                bumpCacheGeneration()
            }
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

    // MARK: - 歌单详情预热（3.6 (4)）

    private static let prefetchQueue = DispatchQueue(label: "com.miller.folia.api-prefetch", qos: .utility)
    private static let prefetchGate = DispatchSemaphore(value: 2)

    /// 从 user/playlist 响应里取歌单 id（最多 24 个），后台逐个把
    /// playlist/detail 拉进缓存。全程失败静默：预热只是加速，不成不报错。
    private static func prefetchPlaylistDetails(from body: Data, cookie: String, cookieHash: String) {
        // 响应数组键是单数 playlist（独立审查 H2：此前误写复数，
        // guard 必然失败，整个预热是死代码）。
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let playlists = object["playlist"] as? [[String: Any]] else { return }
        let ids = playlists.prefix(24).compactMap { entry -> Int64? in
            if let number = entry["id"] as? NSNumber { return number.int64Value }
            if let text = entry["id"] as? String { return Int64(text) }
            return nil
        }
        for id in ids {
            let target = "/api/netease/playlist/detail?id=\(id)"
            guard let ttl = cacheTTL(for: target),
                  let url = URL(string: "https://folia-netease-8v5g6dx9.edgeone.cool/playlist/detail?id=\(id)")
            else { continue }
            prefetchQueue.async {
                // 新鲜度在执行时复查（审查 L6）：排队期间可能已被主链路
                // 或前一个预热任务写入，不重复拉取。
                guard freshCacheData(target: target, cookieHash: cookieHash, ttl: ttl) == nil else { return }
                prefetchGate.wait()
                defer { prefetchGate.signal() }
                var upstream = URLRequest(url: url)
                if !cookie.isEmpty { upstream.setValue(cookie, forHTTPHeaderField: "Cookie") }
                upstream.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let semaphore = DispatchSemaphore(value: 0)
                var fetched: Data?
                var fetchedStatus = 0
                let task = session.dataTask(with: upstream) { data, response, _ in
                    if let http = response as? HTTPURLResponse {
                        fetchedStatus = http.statusCode
                        if http.statusCode == 200 { fetched = data }
                    }
                    semaphore.signal()
                }
                task.resume()
                _ = semaphore.wait(timeout: .now() + 30)
                guard fetchedStatus == 200, var data = fetched, !data.isEmpty,
                      neteaseBusinessOK(data, target: target) else { return }
                // 预热目标是 playlist/detail（详情口径）：按 target 走统一
                // 分档判定，不再写死列表上下文（3.6 (6)，DS Q1 点名）。
                data = CoverURLRewriter.rewrite(body: data, port: LocalServer.shared.port,
                                                wallTier: isWallListTarget(target) ? CoverPolicy.wallTier : nil)
                try? data.write(to: cacheFile(target: target, cookieHash: cookieHash), options: .atomic)
            }
        }
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

/// 封面内存策略（3.6 (6)，DS 第十三轮定版）：两级触发，只存时间戳、
/// 读取时按当前时间计算，过期自然失效；触发源一律落日志。
/// - 闸门级：系统内存警告（WebEffectBridge 转发）→ 取图并发降到 2、
///   保持 3 分钟 + 立即积极修剪图片缓存。不降清晰度：内存警告来源
///   不定向，只凭它降档会让墙面长期发糊（DS Q6）。
/// - 降档级：30 秒内网页进程连杀 ≥2 次（WebEffectBridge 的终止计数
///   是单一源头，由它回调）→ 墙档 384→320、保持 10 分钟，闸门同降 2。
enum CoverPolicy {
    private static let lock = NSLock()
    private static var gateLevelUntil = Date.distantPast
    private static var lowTierUntil = Date.distantPast

    /// 当前墙档（列表端点 coverImgUrl 用）：正常 384，降档期 320。
    static var wallTier: Int {
        lock.lock(); defer { lock.unlock() }
        return Date() < lowTierUntil ? 320 : 384
    }

    /// 当前取图并发上限：任一级生效期间 2，否则 3（DS Q2 定版维持 3）。
    static var gateLimit: Int {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        return (now < gateLevelUntil || now < lowTierUntil) ? 2 : 3
    }

    static func triggerGateLevel(source: String) {
        lock.lock()
        gateLevelUntil = Date().addingTimeInterval(180)
        lock.unlock()
        FoliaFileLog.write("cover", "gate level on (limit=2 for 180s) source=\(source)")
        CoverImageProxy.applyGateLimit()
        CoverImageProxy.trimCacheNow()
    }

    static func triggerLowTier(source: String) {
        lock.lock()
        let alreadyActive = Date() < lowTierUntil
        lowTierUntil = Date().addingTimeInterval(600)
        lock.unlock()
        if !alreadyActive {
            FoliaFileLog.write("cover", "low tier on (wall=320 for 600s) source=\(source)")
        }
        CoverImageProxy.applyGateLimit()
    }

    /// 3.6 (7) P1：墙解码登记表上限。正常 128，低档期 64——页面被杀
    /// 重载时经 LocalServer 重新取 JS，新页面天生更小的登记表（供包
    /// 定点替换 WallRegistryPatch 读此值）。600 原值 ×640² 解码约
    /// 1.6MB/变体 ≈ 980MB 驻留上限；128 → 约 210MB，64 → 约 100MB。
    static var registryCap: Int {
        lock.lock(); defer { lock.unlock() }
        return Date() < lowTierUntil ? 64 : 128
    }

    /// 低档期是否生效（日志/埋点用）。
    static var lowTierActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date() < lowTierUntil
    }
}

/// 3.6 (7) P1：供包时对 wall chunk 里 MAX_TRACKED_VARIANTS 做定点替换。
/// 锚点是结构模式而非变量名（变量名随构建变）：cap 变量赋值 + 紧跟三张
/// =new Map 登记表 + remember 驱逐函数（delete/set 后以 e.size>capVar
/// 循环）。全文件恰好命中 1 次才替换；未命中原样供包（fail-open），
/// 命中与未命中都只记一次日志（按 文件名+cap 去重，防刷屏）。
private enum WallRegistryPatch {
    /// 3.6 (8) 止损：停用（见 sendFile 处注释）。代码保留备查，CI 锚点
    /// 检查仍在（scripts/check-registry-patch.py），防锚点腐烂。
    static let isEnabled = false

    private static let regex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"([A-Za-z_$][\w$]*)=(\d{2,4}),([A-Za-z_$][\w$]*)=new Map,([A-Za-z_$][\w$]*)=new Map,([A-Za-z_$][\w$]*)=new Map,([A-Za-z_$][\w$]*)=\(e,t\)=>\{for\(e\.delete\(t\),e\.set\(t,!0\);e\.size>\1"#)

    private static var loggedKeys = Set<String>()
    private static let logLock = NSLock()

    /// 返回 (供包字节, 实际替换用的 cap)。未命中 cap 为 nil。命中时
    /// 调用方给响应加 X-Folia-Registry-Cap 标记头（DS 第十六轮 4.5），
    /// 值取本次替换实际用的 cap（独立审查低：避免二次读 CoverPolicy
    /// 与替换值不一致）。
    static func apply(to data: Data, fileName: String) -> (Data, Int?) {
        guard let regex else { return (data, nil) }
        // 前置过滤：三张登记表同现才值得跑正则；也把 MISS 日志收窄到
        // 真正像 wall chunk 的文件，防全量 JS 首载时日志爆发（审查低）。
        var mapHits = 0
        var searchRange = data.startIndex..<data.endIndex
        let needle = Data("=new Map,".utf8)
        while let found = data.range(of: needle, in: searchRange) {
            mapHits += 1
            if mapHits >= 3 { break }
            searchRange = found.upperBound..<data.endIndex
        }
        guard mapHits >= 3 else { return (data, nil) }
        guard let text = String(data: data, encoding: .utf8) else {
            logOnce(key: "nonutf8:\(fileName)", message: "registry patch SKIP non-utf8 file=\(fileName)")
            return (data, nil)
        }
        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: fullRange)
        let cap = CoverPolicy.registryCap
        guard matches.count == 1, let match = matches.first,
              let digitsRange = Range(match.range(at: 2), in: text) else {
            logOnce(key: "miss:\(fileName)", message: "registry patch MISS file=\(fileName) matches=\(matches.count)")
            return (data, nil)
        }
        let original = text[digitsRange]
        var patched = text
        patched.replaceSubrange(digitsRange, with: String(cap))
        logOnce(key: "hit:\(fileName):\(cap)", message: "registry patch HIT file=\(fileName) \(original)->\(cap)")
        return (Data(patched.utf8), cap)
    }

    private static func logOnce(key: String, message: String) {
        logLock.lock()
        let isNew = loggedKeys.insert(key).inserted
        logLock.unlock()
        if isNew { FoliaFileLog.write("cover", message) }
    }
}

private enum CoverImageProxy {

    /// 只代理音乐平台图片 CDN 的域名（后缀匹配），防被当开放代理用。
    static let allowedHostSuffixes = ["126.net", "163.com", "gtimg.cn", "qq.com", "kugou.com", "sinaimg.cn"]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// 同时进行的取图+缩放上限（本地 CPU 与内存保护）。3.6 (6) 起改用
    /// OperationQueue 动态限流（CoverPolicy 两级策略 3↔2，DS Q7：不另
    /// 手写一套并发原语）；workQueue 只留给缓存修剪等杂活。
    private static let fetchQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .utility
        return queue
    }()
    private static let workQueue = DispatchQueue(label: "com.miller.folia.imgproxy", qos: .utility, attributes: .concurrent)

    /// 把 CoverPolicy 当前并发上限同步进取图队列（幂等，请求入口顺手调）。
    static func applyGateLimit() {
        let limit = CoverPolicy.gateLimit
        if fetchQueue.maxConcurrentOperationCount != limit {
            fetchQueue.maxConcurrentOperationCount = limit
        }
    }

    /// 同图在途合并：key -> 等待者。
    private static let flightLock = NSLock()
    private static var inFlight: [String: [(Data?, String?) -> Void]] = [:]

    /// 代理统计（3.6 (6) 诊断，DS 第十二轮 F 组轻量版）：全部在
    /// flightLock 内读写；每 100 次请求落一行日志，不另起统计系统。
    private static var statRequests = 0
    private static var statHits = 0
    private static var statMisses = 0
    private static var statCoalesced = 0
    private static var statFetches = 0
    private static var statFetchMs = 0
    private static var purgeChecked = false

    /// 档位体系变更后的一次性清仓：3.6 (6) 新增墙档 384/320，旧档成品
    /// （768 等）不会再被请求，留着只占 200MB 配额、压命中率。首个
    /// /img 请求时按代次标记清一次，重建交给正常流量。
    private static func purgeStaleTierCacheOnce() {
        flightLock.lock()
        if purgeChecked { flightLock.unlock(); return }
        purgeChecked = true
        flightLock.unlock()
        let gen = UserDefaults.standard.integer(forKey: "folia.imgCacheGen")
        guard gen < 2 else { return }
        // 代次先落标记（同步、廉价）；实际删文件挪到后台队列（独立审查
        // 低-2）：在连接线程上同步删 200MB 量级小文件会阻塞首图响应。
        UserDefaults.standard.set(2, forKey: "folia.imgCacheGen")
        let dir = cacheDir
        workQueue.async {
            if let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) {
                for file in files { try? FileManager.default.removeItem(at: file) }
            }
            FoliaFileLog.write("cover", "img cache purged for tier gen 2 (was \(gen))")
        }
    }

    /// 请求计数与百次统计日志（handle 入口调用）。
    private static func noteRequest() {
        flightLock.lock()
        statRequests += 1
        let n = statRequests
        var snapshot: (Int, Int, Int, Int, Int)?
        if n % 100 == 0 {
            snapshot = (statHits, statMisses, statCoalesced, statFetches, statFetchMs)
        }
        flightLock.unlock()
        if let (hits, misses, coalesced, fetches, fetchMs) = snapshot {
            let avg = fetches > 0 ? fetchMs / fetches : 0
            FoliaFileLog.write("cover", "img stats req=\(n) hit=\(hits) miss=\(misses) coalesced=\(coalesced) fetches=\(fetches) avgFetchMs=\(avg) gate=\(CoverPolicy.gateLimit) wallTier=\(CoverPolicy.wallTier)")
        }
    }

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
        purgeStaleTierCacheOnce()
        applyGateLimit()
        noteRequest()
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
            flightLock.lock()
            statHits += 1
            flightLock.unlock()
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
                                          ("Cache-Control", "public, max-age=2592000")],
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
                                      ("Cache-Control", "public, max-age=2592000")],
                            body: Data(), contentLengthOverride: data.count)
        } else {
            handler.respond(status: 200, reason: "OK",
                            headers: [("Content-Type", "image/jpeg"),
                                      ("Cache-Control", "public, max-age=2592000")],
                            body: data)
        }
    }

    private static func fetchCoalesced(key: String, srcURL: URL, maxPixel: Int,
                                       completion: @escaping (Data?, String?) -> Void) {
        flightLock.lock()
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            statCoalesced += 1
            flightLock.unlock()
            return
        }
        inFlight[key] = [completion]
        statMisses += 1
        flightLock.unlock()

        fetchQueue.addOperation {
            let fetchStarted = Date()
            let result = fetchAndScale(srcURL: srcURL, maxPixel: maxPixel)
            flightLock.lock()
            statFetches += 1
            statFetchMs += Int(Date().timeIntervalSince(fetchStarted) * 1000)
            let waiters = inFlight.removeValue(forKey: key) ?? []
            flightLock.unlock()
            for waiter in waiters { waiter(result.0, result.1) }
        }
    }

    private static func fetchAndScale(srcURL: URL, maxPixel: Int) -> (Data?, String?) {
        // 3.6 (4)：网易云图片 CDN 支持 ?param=<边>y<边> 服务端缩放。优先取
        // 尺寸变体（下载量从原图数 MB 降到档位量级，治 #3 封面久不出来），
        // 变体失败再退原图；ImageIO 仍作最终上限兜底。其他 CDN 直接取原图。
        if let host = srcURL.host?.lowercased(), host.hasSuffix("music.126.net"),
           let variant = sizedVariantURL(srcURL, maxPixel: maxPixel),
           let result = fetchScaledOnce(url: variant, maxPixel: maxPixel) {
            return result
        }
        return fetchScaledOnce(url: srcURL, maxPixel: maxPixel) ?? (nil, nil)
    }

    private static func sizedVariantURL(_ url: URL, maxPixel: Int) -> URL? {
        let tier = maxPixel <= 512 ? 512 : (maxPixel <= 768 ? 768 : 1080)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var query = components.queryItems ?? []
        query.removeAll { $0.name == "param" }
        query.append(URLQueryItem(name: "param", value: "\(tier)y\(tier)"))
        components.queryItems = query
        return components.url
    }

    /// 取一张图并缩到 maxPixel；失败返回 nil（区别于「取到了但内容不可用」）。
    private static func fetchScaledOnce(url: URL, maxPixel: Int) -> (Data?, String?)? {
        let semaphore = DispatchSemaphore(value: 0)
        var fetched: Data?
        let task = session.dataTask(with: url) { data, response, _ in
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                fetched = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 25)
        guard let data = fetched, !data.isEmpty, data.count <= 16 * 1024 * 1024 else { return nil }
        guard let scaled = downscale(data: data, maxPixel: maxPixel) else { return nil }
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
        trimCache(ceiling: 200 * 1024 * 1024, floor: 150 * 1024 * 1024, force: false)
    }

    /// 内存警告时的积极修剪（CoverPolicy 闸门级触发调用）：绕过 60 秒
    /// 节流，阈值更低（超 120MB 删到 80MB），先把能让出的磁盘/页缓存让出来。
    static func trimCacheNow() {
        trimCache(ceiling: 120 * 1024 * 1024, floor: 80 * 1024 * 1024, force: true)
    }

    private static func trimCache(ceiling: Int, floor: Int, force: Bool) {
        // lastTrimAt 的检查+赋值在 flightLock 内做，避免多连接完成回调并发读写（审查低 10）。
        // force 也回写时间戳（独立审查低-3）：否则强制修剪后常规修剪会
        // 紧接着再跑一次全目录扫描。
        flightLock.lock()
        if !force {
            guard Date().timeIntervalSince(lastTrimAt) > 60 else { flightLock.unlock(); return }
        }
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
            guard total > ceiling else { return }
            for entry in entries.sorted(by: { $0.date < $1.date }) {
                if total <= floor { break }
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
/// 尺寸档（3.6 (4)，与 DS 第十轮回评对账定版）：先按 JSON 字段名分档
/// （coverImgUrl 头图 768；picUrl 一律 640；img1v1Url/avatarUrl
/// 512），未命中字段名的走通用档（blur 480、avatar 512、其余 640）。
/// 3.6 (6) 起 coverImgUrl 在集合列表端点改走墙档（见 rewrite 的
/// wallTier 参数与 LocalServer.isWallListTarget）。
/// 依据：1024² 单图解码约 4MB 是大歌单滚动时解码内存的主项；播放页
/// 封面约 300pt 显示（@3x 理想 900），640 属轻微不足且有歌词特效覆
/// 层，是砍不可见浪费而非降级感官——此点已列入真机验收确认项，
/// Miller 若判糊再给播放页单开高档。
/// 注：DS 回评曾把纯列表端点的 picUrl 定为 400，前提是「详情页曲目
/// 的 picUrl 不会被播放页复用」；独立审查 L4 指出该前提不成立——从
/// 歌单详情点播时播放页用的正是该响应的曲目对象。400 在播放页必然
/// 糊、属可见降级，故 picUrl 统一 640（仍比原 1024 档省约 60% 解码
/// 量）。此偏离已记录，晨报与真机清单同步说明。
/// 只认图片专用域名或带图片扩展名的地址；改写失败/不匹配一律原样保留。
private enum CoverURLRewriter {

    // 专用图片域名只留图片 CDN 本体：music.126.net / kugou.com 的同后缀域名还承载
    // 音频流（m*.music.126.net、webfs.kugou.com），放进来会把流地址误改成图片代理
    // （审查高 1）。这两家的图片 URL 基本带图片扩展名，走扩展名规则即可。
    private static let dedicatedImageHostSuffixes = ["gtimg.cn", "singerimg.kugou.com"]
    private static let imageExtensions = [".jpg", ".jpeg", ".png", ".webp"]
    /// 音频扩展名黑名单：任何情况下不改写（双保险）。
    private static let audioExtensions = [".mp3", ".m4a", ".flac", ".aac", ".ogg", ".wav", ".opus"]

    /// wallTier（3.6 (6)）：非 nil 表示该响应来自集合列表端点（调用方按
    /// target 白名单判定），coverImgUrl 改用墙档（CoverPolicy 给出，
    /// 正常 384 / 低内存 320）；nil（详情与未枚举端点）coverImgUrl 维持
    /// 768，防详情头图误降。其余字段档位不随它变化。
    static func rewrite(body: Data, port: UInt16, wallTier: Int? = nil) -> Data {
        guard port != 0, var text = String(data: body, encoding: .utf8) else { return body }
        // JSON 里 \/ 与 / 等价，先归一方便匹配（语义不变）。
        if text.contains("\\/") { text = text.replacingOccurrences(of: "\\/", with: "/") }
        var changed = false
        // 第一遍：字段名分档。只替换 URL 部分，键与结构原样不动。
        if let keyed = try? NSRegularExpression(
            pattern: #""(coverImgUrl|picUrl|img1v1Url|avatarUrl)"\s*:\s*"(https?://[^\s"'<>\\]+)""#,
            options: []) {
            let keyedMatches = keyed.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in keyedMatches.reversed() {
                guard match.numberOfRanges >= 3,
                      let keyRange = Range(match.range(at: 1), in: text),
                      let urlRange = Range(match.range(at: 2), in: text) else { continue }
                let key = String(text[keyRange])
                let original = String(text[urlRange])
                let tier: Int
                switch key {
                case "coverImgUrl": tier = wallTier ?? 768
                case "picUrl": tier = 640
                default: tier = 512
                }
                guard let replacement = proxiedURL(original, port: port, tierOverride: tier) else { continue }
                text.replaceSubrange(urlRange, with: replacement)
                changed = true
            }
        }
        // 第二遍：其余图片 URL 走通用档（已改写的 /img 相对地址不含 http 前缀，不会二次命中）。
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s"'<>\\]+"#, options: []) else {
            return changed ? Data(text.utf8) : body
        }
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let original = String(text[range])
            guard let replacement = proxiedURL(original, port: port, tierOverride: nil) else { continue }
            text.replaceSubrange(range, with: replacement)
            changed = true
        }
        return changed ? Data(text.utf8) : body
    }

    private static func proxiedURL(_ original: String, port: UInt16, tierOverride: Int?) -> String? {
        guard let url = URL(string: original), let host = url.host?.lowercased(),
              CoverImageProxy.isAllowedHost(host) else { return nil }
        let path = url.path.lowercased()
        guard !audioExtensions.contains(where: { path.hasSuffix($0) }) else { return nil }
        let dedicated = dedicatedImageHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
        let hasImageExtension = imageExtensions.contains { path.hasSuffix($0) }
        guard dedicated || hasImageExtension else { return nil }
        let lower = original.lowercased()
        let tier = tierOverride ?? (lower.contains("blur") ? 480 : (lower.contains("avatar") ? 512 : 640))
        // http 明文原图先升 https（3.7 (7)）：歌单 coverImgUrl 是
        // http:// 地址，ATS 只给本机开例外，代理取图会被拦；同图
        // http/https 字节一致，升级无损，Web 与原生同时受益。
        let upgraded = original.hasPrefix("http://")
            ? "https://" + original.dropFirst(7) : original
        // 相对路径 + base64url：见 CoverImageProxy 头注（避前端 https 升级与子串误伤）。
        _ = port // 地址已改相对路径，端口不再出现在产物里（签名保留兼容调用点）
        return "/img/\(base64URL(upgraded))?w=\(tier)"
    }

    /// base64url（无填充）：字母表不含 '.'，原地址的主机名不会以明文出现。
    private static func base64URL(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
