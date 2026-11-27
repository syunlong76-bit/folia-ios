import Foundation

/// (53) B 组：QQ/酷狗登录函数侧的共用传输（节点与
/// EdgeOneAPIClient.nodes / LocalServer.edgeOneBases 同源：
/// Netlify 同源代理为主、EdgeOne 直连为备，单请求失败换备
/// 节点——与 NeteaseQRLoginClient 的既有口径一致）。
/// 网易云登录不走这里（NeteaseQRLoginClient 已有自有实现，
/// 零回归不动）。
///
/// 会话载体按网页版 transport 实查结论分发：
/// - QQ 同源入口收 X-QQ-Session 头（裸 token），外部入口收
///   ?cookie=<整串>；原生直连两节点都带（头给 Netlify 同源
///   语义、query 给 EdgeOne 外部语义，后端各取所需）。
/// - 酷狗 Web 载体只有 ?cookie=<整串>。
/// 凭据只进请求，绝不进日志/本类面包屑（调用方只记 len/hash8）。
enum ProviderLoginTransport {

    enum TransportError: Error {
        case transport
        case malformed
        case http(status: Int)
    }

    struct Response {
        let root: [String: Any]
        let httpStatus: Int
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    static func bases(for provider: NativeSessionStore.Provider) -> [URL] {
        switch provider {
        case .qq:
            return [
                URL(string: "https://folia-music.netlify.app/api/qq")!,
                URL(string: "https://folia-qq-8j540jls.edgeone.cool")!
            ]
        case .kugou:
            return [
                URL(string: "https://folia-music.netlify.app/api/kugou")!,
                URL(string: "https://folia-kugou-k62owtqf.edgeone.cool")!
            ]
        case .netease:
            return [
                URL(string: "https://folia-music.netlify.app/api/netease")!,
                URL(string: "https://folia-netease-8v5g6dx9.edgeone.cool")!
            ]
        }
    }

    /// GET JSON（主备两节点依次尝试）。cookie 非 nil 时按
    /// provider 载体规则附带会话；timestamp 防缓存（网页版
    /// 两家 transport 均带）。
    /// (98) 第 5 条：最近一次成功命中的节点序（0=Netlify 主、1=EdgeOne 备），供 p98 qr seg 对读。
    static var lastNodeIndex98 = -1

    static func getJSON(
        provider: NativeSessionStore.Provider,
        path: String,
        query: [String: String] = [:],
        cookie: String? = nil
    ) async throws -> Response {
        var lastError: Error = TransportError.transport
        for (nodeIdx, base) in bases(for: provider).enumerated() {
            do {
                var components = URLComponents(
                    url: base.appendingPathComponent(path),
                    resolvingAgainstBaseURL: false)
                var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                if let cookie, provider == .kugou || provider == .qq {
                    items.append(URLQueryItem(name: "cookie", value: cookie))
                }
                items.append(URLQueryItem(
                    name: "timestamp",
                    value: String(Int(Date().timeIntervalSince1970 * 1000))))
                components?.queryItems = items
                guard let url = components?.url else {
                    throw TransportError.malformed
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                if provider == .qq, let cookie,
                   let token = NativeSessionStore.qqSessionToken(in: cookie) {
                    request.setValue(token, forHTTPHeaderField: "X-QQ-Session")
                }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw TransportError.transport
                }
                guard (200...299).contains(http.statusCode) else {
                    throw TransportError.http(status: http.statusCode)
                }
                guard let object = try? JSONSerialization.jsonObject(with: data),
                      let dict = object as? [String: Any] else {
                    throw TransportError.malformed
                }
                lastNodeIndex98 = nodeIdx
                return Response(root: dict, httpStatus: http.statusCode)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    /// POST JSON（(62) QQ keepalive 用）：与 getJSON 同节点序
    /// 与 cookie 载体（?cookie= 查询参数 + X-QQ-Session 头），
    /// 另在 JSON body 里带一份 cookie（后端 /login/refresh
    /// 实测 POST-only、401 无会话——双载体兼容其读法）。
    static func postJSON(
        provider: NativeSessionStore.Provider,
        path: String,
        query: [String: String] = [:],
        cookie: String? = nil
    ) async throws -> Response {
        var lastError: Error = TransportError.transport
        for (nodeIdx, base) in bases(for: provider).enumerated() {
            do {
                var components = URLComponents(
                    url: base.appendingPathComponent(path),
                    resolvingAgainstBaseURL: false)
                var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                if let cookie, provider == .kugou || provider == .qq {
                    items.append(URLQueryItem(name: "cookie", value: cookie))
                }
                items.append(URLQueryItem(
                    name: "timestamp",
                    value: String(Int(Date().timeIntervalSince1970 * 1000))))
                components?.queryItems = items
                guard let url = components?.url else {
                    throw TransportError.malformed
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if provider == .qq, let cookie,
                   let token = NativeSessionStore.qqSessionToken(in: cookie) {
                    request.setValue(token, forHTTPHeaderField: "X-QQ-Session")
                }
                var body: [String: String] = [:]
                if let cookie { body["cookie"] = cookie }
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw TransportError.transport
                }
                guard (200...299).contains(http.statusCode) else {
                    throw TransportError.http(status: http.statusCode)
                }
                guard let object = try? JSONSerialization.jsonObject(with: data),
                      let dict = object as? [String: Any] else {
                    throw TransportError.malformed
                }
                lastNodeIndex98 = nodeIdx
                return Response(root: dict, httpStatus: http.statusCode)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    /// 回包层级拆解（酷狗网页版 dataOf/responsePayload 同构）：
    /// 先剥 body 包裹，再取 data。
    static func dataObject(of root: [String: Any]) -> [String: Any] {
        let payload = NativeJSON.dict(root["body"]) ?? root
        return NativeJSON.dict(payload["data"]) ?? payload
    }

    /// 松散取字符串值（数字/字符串混杂逐键兜底，同网页版 valueOf）。
    static func stringValue(_ dict: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = NativeJSON.string(dict[key]),
               !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return value
            }
        }
        return nil
    }
}
