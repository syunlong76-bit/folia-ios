import Foundation

/// (51) A 组：网易云扫码登录函数侧客户端（NeteaseCloudMusicApi
/// Enhanced 的 /login/qr/* 路由组）。
///
/// 2026-11-20 本机 curl 实测结论（EdgeOne 直连与 Netlify 代理
/// 两节点均通）：
/// - GET /login/qr/key → 200，{data:{unikey}}；
/// - GET /login/qr/create?key=&qrimg=true → 200，
///   {data:{qrurl, qrimg:"data:image/png;base64,..."}}；
/// - GET /login/qr/check?key= → code 语义：800 二维码不存在或
///   已过期（实测假 key 回 800）、801 等待扫码（实测）、802 已
///   扫码待确认、803 授权成功（802/803 需真人扫码，未实测，
///   按该 API 既有约定）。注意：800/801 回包也带 cookie 字段
///   但只有 NMTID、无 MUSIC_U——只有 803 的 cookie 可取，且
///   存前必须过 NativeSessionStore.isValidNeteaseCookie 校验。
/// 全部请求带 timestamp 参数防缓存。节点顺序与 EdgeOneAPIClient
/// 对齐：Netlify 为主、EdgeOne 直连为备，单请求失败换备节点。
final class NeteaseQRLoginClient {

    enum QRLoginError: Error {
        case transport
        case malformed
    }

    struct QRCode {
        let key: String
        let qrurl: String?
        let qrimgBase64: String?
    }

    enum CheckResult {
        case expired          // 800
        case waiting          // 801
        case scanned          // 802
        case authorized(cookie: String)  // 803
        case unknown(code: Int)
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private static let bases: [URL] = [
        URL(string: "https://folia-music.netlify.app/api/netease")!,
        URL(string: "https://folia-netease-8v5g6dx9.edgeone.cool")!
    ]

    private func timestamp() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000))
    }

    /// 主备两节点依次尝试的原始 JSON GET。
    private func getJSON(path: String, query: [String: String]) async throws -> [String: Any] {
        var lastError: Error = QRLoginError.transport
        for base in Self.bases {
            do {
                var components = URLComponents(
                    url: base.appendingPathComponent(path),
                    resolvingAgainstBaseURL: false)
                var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                items.append(URLQueryItem(name: "timestamp", value: timestamp()))
                components?.queryItems = items
                guard let url = components?.url else { throw QRLoginError.malformed }
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let dict = object as? [String: Any] else {
                    throw QRLoginError.malformed
                }
                return dict
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    func fetchKey() async throws -> String {
        let root = try await getJSON(path: "/login/qr/key", query: [:])
        guard let data = root["data"] as? [String: Any],
              let key = data["unikey"] as? String, !key.isEmpty else {
            throw QRLoginError.malformed
        }
        return key
    }

    func createQR(key: String) async throws -> QRCode {
        let root = try await getJSON(
            path: "/login/qr/create",
            query: ["key": key, "qrimg": "true"])
        guard let data = root["data"] as? [String: Any] else {
            throw QRLoginError.malformed
        }
        return QRCode(
            key: key,
            qrurl: data["qrurl"] as? String,
            qrimgBase64: data["qrimg"] as? String)
    }

    func check(key: String) async throws -> CheckResult {
        let root = try await getJSON(path: "/login/qr/check", query: ["key": key])
        let code = NativeJSON.int(root["code"])
        switch code {
        case 800: return .expired
        case 801: return .waiting
        case 802: return .scanned
        case 803: return .authorized(cookie: (root["cookie"] as? String) ?? "")
        default: return .unknown(code: code)
        }
    }
}
