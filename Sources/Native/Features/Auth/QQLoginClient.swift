import Foundation

/// (53) B 组：QQ 原生扫码登录客户端。数据通路按网页版
/// qqProvider/qqTransport 实查（2026-11-21）：
/// - 通道声明：GET /login/channels → {data:{channels:[...]}}，
///   404/失败 = 旧后端未声明，回落硬编码 [qq, wechat]（网页版
///   同口径）；qqmusic 通道只有后端声明了才显示；
/// - 取码：GET /login/qr/key?channel=<id> → {data:{unikey}}；
/// - 建码：GET /login/qr/create?key= → {data:{qrimg}}（base64
///   data URL，后端不给 qrurl，缺图无法本地生成——与网页版
///   createQr 同口径，空图即失败）；
/// - 轮询：GET /login/qr/check?key= → 后端把原生状态翻译成
///   网易云同款码：801 等待、802 已扫、803 确认（根级 cookie
///   字段带整串会话，含 qqmusic_session=<sealed token>）、
///   800 过期或失败（带 upstreamCode/failureStage 时是失败
///   不是过期）；
/// - 校验：GET /login/status → {data:{profile}}，profile 在 =
///   已登录（normalizeQqUser 字段：id 取 str_musicid/musicid/
///   uin，昵称 nickname/nick/name，头像 info.logo/avatarUrl）；
/// - 取消：GET /login/qr/cancel?key=（best effort）；
/// - 退出：GET /logout（best effort，本地先清）。
/// 凭据交换（tmeLoginType 6 送、loginType 2 收）在后端内部，
/// 前端不可见；envelope.loginType 按收回类型记 2。
final class QQLoginClient {

    enum QQLoginError: Error {
        case transport
        case malformed
    }

    struct QRCode {
        let key: String
        let qrimgBase64: String?
    }

    enum CheckResult {
        case waiting            // 801
        case scanned            // 802
        case authorized(cookie: String)  // 803
        case expired            // 800 自然过期/用户取消
        case failed(message: String?)    // 800 上游拒绝/交换失败
        case unknown(code: Int)
    }

    struct LoginProfile {
        let accountId: String?
        let nickname: String?
        let avatarURLString: String?
    }

    /// 网页版硬编码登录方式（后端未声明时的回落集）。
    static let fallbackChannels = ["qq", "wechat"]
    /// 全部已知方式的展示名（UI 层用）。
    static let channelLabels = ["qq": "QQ", "wechat": "微信", "qqmusic": "QQ音乐 App"]

    // MARK: - 通道声明

    /// 探测后端声明的通道；拿不到（旧后端 404/网络失败）返回
    /// nil，调用方按 fallbackChannels 回落，不当错误。
    func fetchChannels() async -> [String]? {
        do {
            let response = try await ProviderLoginTransport.getJSON(
                provider: .qq, path: "/login/channels")
            let data = ProviderLoginTransport.dataObject(of: response.root)
            guard let channels = data["channels"] as? [Any] else { return nil }
            let ids = channels.compactMap { NativeJSON.string($0) }
                .filter { Self.channelLabels[$0] != nil }
            return ids.isEmpty ? nil : ids
        } catch {
            return nil
        }
    }

    // MARK: - 扫码三步

    func fetchKey(channel: String) async throws -> String {
        let response = try await ProviderLoginTransport.getJSON(
            provider: .qq, path: "/login/qr/key", query: ["channel": channel])
        let data = ProviderLoginTransport.dataObject(of: response.root)
        guard let key = ProviderLoginTransport.stringValue(data, "unikey", "key"),
              !key.isEmpty else {
            throw QQLoginError.malformed
        }
        return key
    }

    func createQR(key: String) async throws -> QRCode {
        let response = try await ProviderLoginTransport.getJSON(
            provider: .qq, path: "/login/qr/create", query: ["key": key])
        let data = ProviderLoginTransport.dataObject(of: response.root)
        return QRCode(key: key, qrimgBase64: data["qrimg"] as? String)
    }

    func check(key: String) async throws -> CheckResult {
        let response = try await ProviderLoginTransport.getJSON(
            provider: .qq, path: "/login/qr/check", query: ["key": key])
        let root = response.root
        let code = NativeJSON.int(root["code"])
        switch code {
        case 801:
            return .waiting
        case 802:
            return .scanned
        case 803:
            return .authorized(cookie: (root["cookie"] as? String) ?? "")
        case 800:
            // 网页版 qqProvider.checkLogin 口径：带 upstreamCode
            // 或结构化 failureStage（且非 qr-timeout/user-canceled）
            // 是上游拒绝/交换失败；其余 800 按过期处理。
            let reason = root["failureReason"] as? String
            let hasUpstream = root["upstreamCode"] != nil
            let hasStage = (root["failureStage"] as? String) != nil
                && reason != "qr-timeout" && reason != "user-canceled"
            if hasUpstream || hasStage {
                return .failed(message: root["message"] as? String)
            }
            return .expired
        default:
            return .unknown(code: code)
        }
    }

    /// 取消扫码（关窗/切换时 best effort，失败忽略——残留
    /// 会话最迟随 QR_TTL 180 秒自过期，网页版同口径）。
    func cancelQR(key: String) async {
        _ = try? await ProviderLoginTransport.getJSON(
            provider: .qq, path: "/login/qr/cancel", query: ["key": key])
    }

    // MARK: - 状态校验与退出

    /// login_status 校验：profile 在 → 回资料；2xx 无 profile
    /// 或 401 → nil（后端不认会话，失效判据在调用方走
    /// NativeSessionStore.classifyAuthFailure）；网络/5xx 抛错，
    /// 调用方按 transient 处理、绝不清会话。
    func fetchLoginStatus(cookie: String) async throws -> LoginProfile? {
        let response: ProviderLoginTransport.Response
        do {
            response = try await ProviderLoginTransport.getJSON(
                provider: .qq, path: "/login/status", cookie: cookie)
        } catch ProviderLoginTransport.TransportError.http(let status) {
            if status == 401 { return nil }
            throw QQLoginError.transport
        }
        let data = ProviderLoginTransport.dataObject(of: response.root)
        guard let profile = NativeJSON.dict(data["profile"]) else { return nil }
        let info = NativeJSON.dict(profile["info"]) ?? [:]
        let accountId = ProviderLoginTransport.stringValue(
            profile, "str_musicid", "musicid", "uin", "id")
            ?? ProviderLoginTransport.stringValue(info, "str_musicid", "musicid", "uin")
        let nickname = ProviderLoginTransport.stringValue(
            profile, "nickname", "nick", "name", "userName")
            ?? ProviderLoginTransport.stringValue(info, "nickname", "nick", "name", "userName")
        let avatar = ProviderLoginTransport.stringValue(profile, "avatarUrl")
            ?? ProviderLoginTransport.stringValue(info, "logo", "avatarUrl")
        return LoginProfile(accountId: accountId, nickname: nickname,
                            avatarURLString: avatar)
    }

    /// 退出登录（best effort：后端通知失败不阻塞本地清会话）。
    func logout(cookie: String) async {
        _ = try? await ProviderLoginTransport.getJSON(
            provider: .qq, path: "/logout", cookie: cookie)
    }
}
