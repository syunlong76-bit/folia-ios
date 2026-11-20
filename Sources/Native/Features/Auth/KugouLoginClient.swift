import Foundation

/// (53) B 组：酷狗原生扫码登录客户端。数据通路按网页版
/// kugouProvider（:1406 起）/kugouTransport 实查（2026-11-21）：
/// - 取码：GET /login/qr/key → data 里 qrcode/qrkey/key/ticket；
/// - 建码：GET /login/qr/create?key=&qrimg=true → data 里
///   base64/qrimg（图）或 qrcode/url（内容串，本地生成二维码）；
/// - 轮询：GET /login/qr/check?key=&qrcode=<key> → data.status：
///   0 过期、1 等待、2/3 已扫、4 确认；确认回包带 token 与
///   userid（成对才算数，见 kugouTransport 的
///   rememberConfirmedSignIn），另有 cookie 条目与 dfid；
/// - 落存形态：整串 cookie = cookie 条目 + token/userid/dfid
///   合成（网页版 getWebSessionCookie 同形态），请求走
///   ?cookie= 查询参数；
/// - 校验：GET /user/detail?userid= → data.user_info/profile
///   里 nickname/avatar；失效判据 HTTP 401/403 或
///   error_code 152，其余（502 等）一律不清会话；
/// - 设备验证：回包 errcode 20028 或文案含「本次请求需要
///   验证」时先 GET /register/dev 换 dfid 再重试一次
///   （kugouTransport 同流程，入口只挂在取码一步）。
final class KugouLoginClient {

    enum KugouLoginError: Error {
        case transport
        case malformed
    }

    struct QRCode {
        let key: String
        /// base64 图（data URL 或纯 base64），后端给了才有。
        let qrimgBase64: String?
        /// 二维码内容串（后端只给内容时本地生成二维码图）。
        let qrContent: String?
    }

    enum CheckResult {
        case expired            // status 0
        case waiting            // status 1
        case scanned            // status 2/3
        case authorized(cookie: String, userId: String)  // status 4
        case failed(message: String?)
        case unknown(status: Int)
    }

    struct LoginProfile {
        let accountId: String?
        let nickname: String?
        let avatarURLString: String?
    }

    /// register_dev 换到的设备 id（本次登录流程内暂存，
    /// 确认时并入 cookie 合成串）。
    private var pendingDfid: String?

    private static func isDeviceVerificationRequired(_ root: [String: Any]) -> Bool {
        let data = ProviderLoginTransport.dataObject(of: root)
        var code = NativeJSON.int(root["errcode"] ?? root["error_code"])
        if code == 0 { code = NativeJSON.int(data["errcode"] ?? data["error_code"]) }
        if code == 20028 { return true }
        let message = (root["error"] as? String) ?? (root["error_msg"] as? String)
            ?? (data["error"] as? String) ?? (data["msg"] as? String) ?? ""
        return message.contains("本次请求需要验证")
    }

    // MARK: - 扫码三步

    func fetchKey() async throws -> String {
        var response = try await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/login/qr/key")
        if Self.isDeviceVerificationRequired(response.root) {
            try await registerDevice()
            response = try await ProviderLoginTransport.getJSON(
                provider: .kugou, path: "/login/qr/key")
        }
        let data = ProviderLoginTransport.dataObject(of: response.root)
        captureDfid(from: response.root)
        guard let key = ProviderLoginTransport.stringValue(
            data, "qrcode", "qrkey", "key", "ticket"), !key.isEmpty else {
            throw KugouLoginError.malformed
        }
        return key
    }

    func createQR(key: String) async throws -> QRCode {
        let response = try await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/login/qr/create",
            query: ["key": key, "qrimg": "true"])
        let data = ProviderLoginTransport.dataObject(of: response.root)
        captureDfid(from: response.root)
        let image = ProviderLoginTransport.stringValue(data, "base64", "qrimg")
        let content = ProviderLoginTransport.stringValue(data, "qrcode", "url")
        // qrcode 字段在带图时可能就是图本身（长 base64 串）：
        // 只有短串才当内容串用，长串归图。
        if image == nil, let content, content.count > 200 {
            return QRCode(key: key, qrimgBase64: content, qrContent: nil)
        }
        return QRCode(key: key, qrimgBase64: image, qrContent: content)
    }

    func check(key: String) async throws -> CheckResult {
        let response = try await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/login/qr/check",
            query: ["key": key, "qrcode": key])
        let root = response.root
        let data = ProviderLoginTransport.dataObject(of: root)
        captureDfid(from: root)
        let statusValue = data["status"] ?? data["code"] ?? root["status"] ?? root["code"]
        let status = NativeJSON.int(statusValue)
        switch status {
        case 0:
            return .expired
        case 1:
            return .waiting
        case 2, 3:
            return .scanned
        case 4:
            return assembleAuthorized(root: root, data: data)
        default:
            // 网页版口径：status 缺失但带 token 也算确认。
            if ProviderLoginTransport.stringValue(data, "token") != nil {
                return assembleAuthorized(root: root, data: data)
            }
            let message = ProviderLoginTransport.stringValue(data, "message", "msg", "error")
            if statusValue == nil { return .failed(message: message) }
            return .unknown(status: status)
        }
    }

    /// 确认回包组装整串 cookie：token/userid 必须成对（半对
    /// 不落存，回 failed）；cookie 条目里的账号项以确认回包
    /// 的 token/userid 为准，dfid 并入。
    private func assembleAuthorized(root: [String: Any], data: [String: Any]) -> CheckResult {
        guard let token = ProviderLoginTransport.stringValue(data, "token"),
              let userId = ProviderLoginTransport.stringValue(
                data, "userid", "user_id", "uid") else {
            return .failed(message: "登录回包缺 token/userid")
        }
        var pairs: [(String, String)] = []
        var seen = Set<String>()
        func put(_ name: String, _ value: String) {
            let key = name.lowercased()
            if seen.contains(key) {
                if let idx = pairs.firstIndex(where: { $0.0.lowercased() == key }) {
                    pairs[idx] = (name, value)
                }
                return
            }
            seen.insert(key)
            pairs.append((name, value))
        }
        // 后端顺带回的 cookie 条目（根级或 data 级，字符串或数组）。
        let rawCookies = root["cookie"] ?? data["cookie"]
        let entries: [String]
        if let text = rawCookies as? String {
            entries = text.split(separator: ";").map(String.init)
        } else if let array = rawCookies as? [Any] {
            entries = array.compactMap { $0 as? String }
        } else {
            entries = []
        }
        for entry in entries {
            let parts = entry.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !value.isEmpty { put(name, value) }
        }
        put("token", token)
        put("userid", userId)
        if let dfid = pendingDfid
            ?? ProviderLoginTransport.stringValue(data, "dfid") {
            put("dfid", dfid)
        }
        let cookie = pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
        return .authorized(cookie: cookie, userId: userId)
    }

    private func captureDfid(from root: [String: Any]) {
        let data = ProviderLoginTransport.dataObject(of: root)
        if let dfid = ProviderLoginTransport.stringValue(data, "dfid") {
            pendingDfid = dfid
        }
    }

    private func registerDevice() async throws {
        let response = try await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/register/dev")
        captureDfid(from: response.root)
    }

    // MARK: - 状态校验与退出

    /// user/detail 校验：拿到昵称资料 = 已登录；HTTP 401/403
    /// 或 error_code 152 抛错由调用方走 classifyAuthFailure
    /// 判失效，其余失败同样抛错但判据会归 transient/indeterminate。
    func fetchUserDetail(cookie: String, userId: String?) async throws -> LoginProfile {
        var query: [String: String] = [:]
        if let userId { query["userid"] = userId }
        let response = try await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/user/detail", query: query, cookie: cookie)
        let root = response.root
        let data = ProviderLoginTransport.dataObject(of: root)
        let errorCode = NativeJSON.int(root["error_code"] ?? root["errcode"])
        if errorCode == 152 {
            throw ProviderLoginTransport.TransportError.http(status: 401)
        }
        let profile = NativeJSON.dict(data["user_info"])
            ?? NativeJSON.dict(data["userinfo"])
            ?? NativeJSON.dict(data["profile"]) ?? data
        let nickname = ProviderLoginTransport.stringValue(
            profile, "nickname", "nick_name", "username", "name")
        let avatar = ProviderLoginTransport.stringValue(
            profile, "avatar", "pic", "sizable_avatar", "picUrl")
        let accountId = ProviderLoginTransport.stringValue(
            profile, "userid", "user_id", "id", "uid") ?? userId
        guard nickname != nil || accountId != nil else {
            throw KugouLoginError.malformed
        }
        return LoginProfile(accountId: accountId, nickname: nickname,
                            avatarURLString: avatar)
    }

    /// 退出登录（best effort：本地先清，后端通知失败忽略——
    /// 网页版 logout 同口径）。
    func logout(cookie: String) async {
        _ = try? await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/logout", cookie: cookie)
    }
}
