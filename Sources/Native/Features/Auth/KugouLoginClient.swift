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
        case failed(message: String)
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
        /// (92) 任务 10：资料内 VIP 初值（vip_type|vipType|
        /// is_vip，网页版 normalizeUser 同键）；复核走
        /// fetchVIPLevel（/user/vip/detail）。
        let vipLevel: Int?
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

    // MARK: - (62) 账号密码 / 手机验证码（端点 2026-11-21 线上实测在）

    /// 发验证码：GET /captcha/sent?mobile=（模块 captcha_sent，
    /// 服务端校验手机号格式并下发短信）。status==1 为成功，
    /// 否则抛错带回后端文案（如「手机格式不正确」）。
    func sendCaptcha(mobile: String) async throws {
        let response = try await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/captcha/sent",
            query: ["mobile": mobile])
        let root = response.root
        captureDfid(from: root)
        if Self.isDeviceVerificationRequired(root) {
            try await registerDevice()
            let retry = try await ProviderLoginTransport.getJSON(
                provider: .kugou, path: "/captcha/sent",
                query: ["mobile": mobile])
            guard NativeJSON.int(retry.root["status"]) == 1 else {
                throw KugouLoginError.failed(
                    message: Self.backendMessage(retry.root) ?? "验证码发送失败")
            }
            return
        }
        guard NativeJSON.int(root["status"]) == 1 else {
            throw KugouLoginError.failed(
                message: Self.backendMessage(root) ?? "验证码发送失败")
        }
    }

    /// 账号密码登录：GET /login?username=&password=（模块
    /// login.js，密码加密在服务端完成）。成功回包 data 带
    /// token/userid（secu_params 已由服务端解密合并），cookie
    /// 组装复用扫码确认的 assembleAuthorized 同口径。
    func loginByPassword(username: String, password: String) async throws -> CheckResult {
        let response = try await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/login",
            query: ["username": username, "password": password])
        captureDfid(from: response.root)
        return finishCredentialLogin(root: response.root)
    }

    /// 手机验证码登录：GET /login/cellphone?mobile=&code=
    /// （模块 login_cellphone.js，加密在服务端完成）。
    func loginByCellphone(mobile: String, code: String) async throws -> CheckResult {
        let response = try await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/login/cellphone",
            query: ["mobile": mobile, "code": code])
        captureDfid(from: response.root)
        return finishCredentialLogin(root: response.root)
    }

    private func finishCredentialLogin(root: [String: Any]) -> CheckResult {
        let data = ProviderLoginTransport.dataObject(of: root)
        guard NativeJSON.int(root["status"]) == 1 else {
            return .failed(message: Self.backendMessage(root) ?? "登录失败")
        }
        return assembleAuthorized(root: root, data: data)
    }

    /// 后端失败文案：data 可能是字符串（如「参数错误」）或
    /// 对象里的 message/msg/error。
    private static func backendMessage(_ root: [String: Any]) -> String? {
        if let text = root["data"] as? String, !text.isEmpty { return text }
        let data = ProviderLoginTransport.dataObject(of: root)
        return ProviderLoginTransport.stringValue(
            data, "message", "msg", "error")
            ?? ProviderLoginTransport.stringValue(root, "message", "msg", "error")
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
        // (92) 任务 10：头像改走网页版 coverOf 整体移植
        // （候选集/优先级/URL 后处理，见 coverOf92）。
        let avatar = Self.coverOf92(profile)
        let accountId = ProviderLoginTransport.stringValue(
            profile, "userid", "user_id", "id", "uid") ?? userId
        guard nickname != nil || accountId != nil else {
            throw KugouLoginError.malformed
        }
        return LoginProfile(accountId: accountId, nickname: nickname,
                            avatarURLString: avatar,
                            vipLevel: Self.vipValue92(in: profile))
    }

    /// JSON 值 → Int（字符串数字与 NSNumber 都认，其余 nil）。
    private static func vipValue92(in dict: [String: Any]) -> Int? {
        for key in ["vip_type", "vipType", "is_vip"] {
            guard let raw = dict[key] else { continue }
            if let text = raw as? String, let value = Int(text) { return value }
            if let number = raw as? NSNumber { return number.intValue }
        }
        return nil
    }

    /// (92) 任务 10：网页版 coverOf 整体移植（kugouProvider
    /// .ts:100-113＋:493，审计对账定案）：对 profile 本体按
    /// 序试封面族 9 键（sizable_cover→Image→image→img→pic
    /// →picUrl→cover→coverUrl→sizable_avatar）、再 avatar
    /// 兜底；命中后必做 URL 后处理——{size}→1024、裸文件
    /// 名拼 c1.kgimg.com/stdmusic/1024/<前8位>/<文件名>、
    /// //补 https:、http→https。命中键名与值形态落 p92 面
    /// 包屑（不记 URL 本体），把实回形态在真机定案。
    private static func coverOf92(_ profile: [String: Any]) -> String? {
        let keys = ["sizable_cover", "Image", "image", "img", "pic",
                    "picUrl", "cover", "coverUrl", "sizable_avatar", "avatar"]
        var hitKey: String?
        var raw: String?
        for key in keys {
            if let value = ProviderLoginTransport.stringValue(profile, key),
               !value.isEmpty {
                hitKey = key
                raw = value
                break
            }
        }
        guard let value = raw else {
            Breadcrumbs.log("p92 kg avatar key=none form=none")
            return nil
        }
        var url = value
        var form = "https"
        if url.contains("{size}") {
            url = url.replacingOccurrences(of: "{size}", with: "1024")
            form = "tpl"
        }
        if url.hasPrefix("//") {
            url = "https:" + url
            if form == "https" { form = "proto-rel" }
        } else if isBareKugouFilename92(url) {
            let date = String(url.prefix(8))
            url = "https://c1.kgimg.com/stdmusic/1024/\(date)/\(url)"
            form = "bare"
        } else if url.hasPrefix("http://") {
            url = "https://" + String(url.dropFirst(7))
            if form == "https" { form = "http" }
        } else if !url.hasPrefix("https://") {
            form = "other"
        }
        Breadcrumbs.log("p92 kg avatar key=\(hitKey ?? "none") form=\(form)")
        return url
    }

    /// 裸文件名判据（网页版正则 ^\d{8,}\.(jpe?g|png|webp)$）。
    private static func isBareKugouFilename92(_ value: String) -> Bool {
        guard let dot = value.lastIndex(of: ".") else { return false }
        let ext = value[value.index(after: dot)...].lowercased()
        guard ["jpg", "jpeg", "png", "webp"].contains(ext) else { return false }
        let stem = value[..<dot]
        return stem.count >= 8 && stem.allSatisfy { $0.isNumber }
    }

    /// (92) 任务 10：酷狗 VIP 复核端点（网页版 getLoginStatus
    /// 复核段同路）：GET /user/vip/detail，data 认 vip_type|
    /// vipType|is_vip，或 busi_vip[] 条目的同名键（任一为正
    /// 即会员、全条目皆零回 0）；端点失败/无字段回 nil（保
    /// 留资料内初值，不当免费）。
    func fetchVIPLevel(cookie: String) async -> Int? {
        guard let response = try? await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/user/vip/detail", cookie: cookie)
        else { return nil }
        let data = ProviderLoginTransport.dataObject(of: response.root)
        if let value = Self.vipValue92(in: data) { return value }
        if let busi = data["busi_vip"] as? [Any], !busi.isEmpty {
            for item in busi {
                guard let dict = item as? [String: Any],
                      let value = Self.vipValue92(in: dict) else { continue }
                if value > 0 { return value }
            }
            return 0
        }
        return nil
    }

    /// 退出登录（best effort：本地先清，后端通知失败忽略——
    /// 网页版 logout 同口径）。
    func logout(cookie: String) async {
        _ = try? await ProviderLoginTransport.getJSON(
            provider: .kugou, path: "/logout", cookie: cookie)
    }
}
