import CryptoKit
import Foundation
import Security

/// (51) A 组：原生会话存储。网易云登录 cookie 整串存 Keychain
/// （kSecClassGenericPassword），取代 WebView localStorage 作为
/// 登录态的权威数据源（迁移见 SessionMigrator）。
///
/// (53) B 组泛化为 per-provider 三家共存：
/// - 网易云：account "netease-cookie"（(51) 原值，兼容保留），
///   整串 cookie；
/// - QQ：account "qq-credential"，结构化 JSON envelope
///   （QQCredentialEnvelope）——后端回的整串 cookie（含
///   qqmusic_session=<sealed token>）只进 rawPayload，
///   不许再拼拆 cookie 串当结构用；
/// - 酷狗：account "kugou-cookie"，整串 cookie（token/userid/
///   dfid 合成串，与网页版 getWebSessionCookie 同形态）。
/// 内存缓存按 provider 分开；clear(provider:) 只清来源一家。
///
/// 纪律：会话是凭据——本类只做存取，绝不写日志；对外只许
/// 暴露 len 与 SHA-256 前 8 位（hash8）供面包屑对账。账号昵称/
/// 头像等非敏感资料另存 UserDefaults 资料缓存（saveProfile），
/// 供侧栏头像区同步读取（ProviderSessionStatus）。
final class NativeSessionStore {

    static let shared = NativeSessionStore()

    /// 业务平台（三家会话各自独立，互不清、互不串）。
    enum Provider: String, CaseIterable {
        case netease
        case qq
        case kugou

        /// Keychain account：网易云沿用 (51) 原值保证旧会话可读。
        var keychainAccount: String {
            switch self {
            case .netease: return "netease-cookie"
            case .qq: return "qq-credential"
            case .kugou: return "kugou-cookie"
            }
        }

        /// 由 LocalServer 代理路径前缀判定 provider（cookie 注入
        /// 分发键）：/api/netease、/api/qq、/api/kugou。
        static func fromAPIPath(_ path: String) -> Provider? {
            if path.hasPrefix("/api/netease") { return .netease }
            if path.hasPrefix("/api/qq") { return .qq }
            if path.hasPrefix("/api/kugou") { return .kugou }
            return nil
        }
    }

    /// QQ 凭据 envelope（DS 定案结构）：rawPayload 是 803 回包的
    /// 整串 cookie 原文；loginType 为后端凭据交换的收回类型
    /// （送 tmeLoginType 6、收 loginType 2，见 qqProvider 注释）；
    /// expiresAt 为 ISO8601 估算到期（sealed 会话约 3 天，仅作
    /// 展示/续期提示元数据，不作失效判据——失效以 login_status
    /// 为准）。
    struct QQCredentialEnvelope: Codable {
        var provider: String
        var accountId: String?
        var displayName: String?
        var loginType: Int
        var expiresAt: String?
        var rawPayload: String
        var schemaVersion: Int
    }

    /// Keychain service：bundle 相关常量（随 bundle id 派生，
    /// 不同包互不串话）。
    static var service: String {
        (Bundle.main.bundleIdentifier ?? "com.miller.folia") + ".session"
    }

    private let lock = NSLock()
    private var memoryCaches: [Provider: String?] = [:]
    private var loadedProviders: Set<Provider> = []

    private init() {}

    // MARK: - 校验与指纹（不暴露原文）

    /// 网易云会话有效性判据（DS 风险一三分判据共用）：必须含
    /// MUSIC_U 且整体是 name=value; 形态。check 接口在 800/801
    /// 也回只含 NMTID 的 cookie 串，无 MUSIC_U 一律判无效。
    static func isValidNeteaseCookie(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("MUSIC_U=") else { return false }
        // 至少一段 name=value（name 非空）。
        return trimmed.split(separator: ";").contains { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            return parts.count == 2
                && !parts[0].trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// QQ 会话有效性判据（对齐 qqTransport/qqSessionRefresh）：
    /// 整串里必须有 qqmusic_session=<token>，token 非空且不含
    /// 分号/空白（sealed token 是密文本身，混入分隔符即坏串）。
    static func isValidQQCookie(_ value: String) -> Bool {
        guard let token = qqSessionToken(in: value) else { return false }
        return !token.isEmpty
            && !token.contains(where: { $0 == ";" || $0.isWhitespace })
    }

    /// 从 QQ 整串 cookie 中取 qqmusic_session 的裸 token（后端
    /// header 入口 X-QQ-Session 只收裸 token，与整串不可互换，
    /// 见 qqTransport 注释）。取不到返回 nil。
    static func qqSessionToken(in cookie: String) -> String? {
        for entry in cookie.split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces) == "qqmusic_session" {
                let token = parts[1].trimmingCharacters(in: .whitespaces)
                return token.isEmpty ? nil : token
            }
        }
        return nil
    }

    /// 酷狗会话有效性判据（对齐 kugouTransport 的
    /// hasKugouAuthenticatedSearchSession 与 rememberConfirmedSignIn
    /// 的成对纪律）：token 与 userid 必须成对存在且非空——半对
    /// 可能是上一个账号的残留，绝不落存。
    static func isValidKugouCookie(_ value: String) -> Bool {
        func hasPair(_ name: String) -> Bool {
            for entry in value.split(separator: ";") {
                let parts = entry.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                if parts[0].trimmingCharacters(in: .whitespaces).lowercased() == name {
                    return !parts[1].trimmingCharacters(in: .whitespaces).isEmpty
                }
            }
            return false
        }
        return hasPair("token") && hasPair("userid")
    }

    /// 面包屑专用指纹：SHA-256 十六进制前 8 位。
    static func hash8(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    // MARK: - 失效判据（per-provider，DS 定案）

    /// 会话校验结论：只有 .sessionInvalid 才许清会话；
    /// .transientFailure（超时/5xx/网络）与 .indeterminate
    /// （解析失败/未知码）一律保留会话。
    enum AuthVerdict {
        case sessionInvalid
        case transientFailure
        case indeterminate
    }

    /// 统一失效判据入口。入参只传已观测到的信号（缺失传 nil）：
    /// - 网易云：业务 code 301 = 失效（既有判据）；其余不清。
    /// - QQ：以 login_status 为准——HTTP 401，或 2xx 但无
    ///   profile（hasProfile=false）= 后端不认会话；其余不清。
    /// - 酷狗：HTTP 401/403 或 error_code 152 = 失效（见
    ///   kugouTransport 的 KUGOU_AUTH_FAILURE_*）；502 等其余
    ///   上游失败一律不清。
    static func classifyAuthFailure(
        provider: Provider,
        httpStatus: Int?,
        businessCode: Int?,
        errorCode: Int?,
        hasProfile: Bool?
    ) -> AuthVerdict {
        if let httpStatus, httpStatus >= 500 { return .transientFailure }
        switch provider {
        case .netease:
            if businessCode == 301 { return .sessionInvalid }
            return .indeterminate
        case .qq:
            if httpStatus == 401 { return .sessionInvalid }
            if hasProfile == false { return .sessionInvalid }
            return .indeterminate
        case .kugou:
            if httpStatus == 401 || httpStatus == 403 { return .sessionInvalid }
            if errorCode == 152 { return .sessionInvalid }
            return .indeterminate
        }
    }

    // MARK: - 通用存取（per-provider，内存缓存按 provider 分开）

    /// 读指定 provider 的会话原文（内存缓存优先）。
    func load(provider: Provider) -> String? {
        lock.lock()
        if loadedProviders.contains(provider) {
            let cached = memoryCaches[provider] ?? nil
            lock.unlock()
            return cached
        }
        lock.unlock()
        let value = keychainRead(account: provider.keychainAccount)
        lock.lock()
        memoryCaches[provider] = value
        loadedProviders.insert(provider)
        lock.unlock()
        return value
    }

    /// 绕缓存直读 Keychain（迁移回读比对专用）。
    func loadDirect(provider: Provider) -> String? {
        keychainRead(account: provider.keychainAccount)
    }

    /// 写指定 provider 的会话原文（add-or-update）。
    @discardableResult
    func save(_ value: String, provider: Provider) -> Bool {
        guard keychainWrite(value, account: provider.keychainAccount) else { return false }
        lock.lock()
        memoryCaches[provider] = value
        loadedProviders.insert(provider)
        lock.unlock()
        return true
    }

    /// 只清指定 provider 的会话与资料缓存（统一清会话入口：
    /// 退出登录/会话失效都走这里，reason 只进面包屑不含凭据）。
    func clear(provider: Provider, reason: String) {
        Breadcrumbs.log("session.clear provider=\(provider.rawValue) reason=\(reason)")
        clearKeychainOnly(provider: provider)
        saveProfile(provider: provider, accountId: nil, displayName: nil, avatarURLString: nil)
    }

    private func clearKeychainOnly(provider: Provider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: provider.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        lock.lock()
        memoryCaches[provider] = nil
        loadedProviders.insert(provider)
        lock.unlock()
    }

    // MARK: - 网易云兼容面（(51) 既有调用方零改动）

    /// 读网易云会话串（= load(provider: .netease)）。
    func load() -> String? { load(provider: .netease) }

    /// 绕缓存直读网易云 Keychain（迁移回读比对专用）。
    func loadDirect() -> String? { loadDirect(provider: .netease) }

    /// 写网易云会话串。
    @discardableResult
    func save(_ value: String) -> Bool { save(value, provider: .netease) }

    /// 清网易云会话（退出登录/会话失效），同步清内存缓存。
    /// 保持 (51) 行为：本方法本身不写面包屑（调用方
    /// NativeDataClient 已记 session.invalidate）。
    func clear() { clearKeychainOnly(provider: .netease) }

    // MARK: - QQ envelope 存取

    /// 落存 QQ 凭据：cookie 先过 isValidQQCookie 校验才组装
    /// envelope；回读比对一致才算成功（失败不写坏会话）。
    @discardableResult
    func saveQQSession(cookie: String, accountId: String?,
                       displayName: String?, loginType: Int,
                       expiresAt: Date?) -> Bool {
        let value = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidQQCookie(value) else { return false }
        let envelope = QQCredentialEnvelope(
            provider: Provider.qq.rawValue,
            accountId: accountId,
            displayName: displayName,
            loginType: loginType,
            expiresAt: expiresAt.map { ISO8601DateFormatter().string(from: $0) },
            rawPayload: value,
            schemaVersion: 1)
        guard let data = try? JSONEncoder().encode(envelope),
              let json = String(data: data, encoding: .utf8) else { return false }
        guard save(json, provider: .qq) else { return false }
        // 回读比对：直读 Keychain 解出的 rawPayload 必须同 hash。
        guard let readback = loadQQEnvelope(),
              Self.hash8(readback.rawPayload) == Self.hash8(value) else {
            return false
        }
        return true
    }

    /// 读 QQ envelope；存量若不是 JSON（不应发生）按整串
    /// rawPayload 兜底，绝不因解码失败丢会话。
    func loadQQEnvelope() -> QQCredentialEnvelope? {
        guard let raw = load(provider: .qq) else { return nil }
        if let data = raw.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(QQCredentialEnvelope.self, from: data) {
            return envelope
        }
        return QQCredentialEnvelope(
            provider: Provider.qq.rawValue, accountId: nil, displayName: nil,
            loginType: 2, expiresAt: nil, rawPayload: raw, schemaVersion: 1)
    }

    /// QQ 整串 cookie（发往外部节点时走 ?cookie= 载体）。
    func qqCookieString() -> String? { loadQQEnvelope()?.rawPayload }

    /// QQ 裸 token（同源入口走 X-QQ-Session 头，只收裸 token）。
    func qqSessionToken() -> String? {
        loadQQEnvelope().flatMap { Self.qqSessionToken(in: $0.rawPayload) }
    }

    // MARK: - 酷狗存取

    /// 落存酷狗 cookie：先过成对校验（token+userid），回读
    /// 比对一致才算成功。
    @discardableResult
    func saveKugouCookie(_ cookie: String) -> Bool {
        let value = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidKugouCookie(value) else { return false }
        guard save(value, provider: .kugou) else { return false }
        guard let readback = loadDirect(provider: .kugou),
              Self.hash8(readback) == Self.hash8(value) else { return false }
        return true
    }

    /// 酷狗整串 cookie（请求走 ?cookie= 查询参数，与网页版
    /// kugouTransport 的 Web 载体同构）。
    func kugouCookieString() -> String? { load(provider: .kugou) }

    // MARK: - 账号资料缓存（非敏感，供状态同步读）

    private static func profileKey(_ provider: Provider) -> String {
        "session.profile.\(provider.rawValue)"
    }

    /// 存账号展示资料（昵称/头像/accountId，均非凭据）。
    /// (62) 尾波第 3 组：改合并语义——nil 表示「不改此字段」，
    /// 非 nil 字段并入既有缓存；三项皆 nil = 显式清除该
    /// provider 的资料缓存（退出登录/会话失效的 clear 走此
    /// 路）。旧整表覆盖写会被只传部分字段的调用抹掉其余字段
    /// （酷狗先存 accountId 后补资料即此模式险例），且是头像
    /// 回填的同型隐患，故切换；现有调用点已逐个核对。
    func saveProfile(provider: Provider, accountId: String?,
                     displayName: String?, avatarURLString: String?) {
        let key = Self.profileKey(provider)
        if accountId == nil && displayName == nil && avatarURLString == nil {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        var dict = (UserDefaults.standard.dictionary(forKey: key)
            as? [String: String]) ?? [:]
        if let accountId { dict["accountId"] = accountId }
        if let displayName { dict["displayName"] = displayName }
        if let avatarURLString { dict["avatarURL"] = avatarURLString }
        UserDefaults.standard.set(dict, forKey: key)
    }

    /// 读账号展示资料缓存（同步，侧栏头像区直接用）。
    func profile(provider: Provider)
        -> (accountId: String?, displayName: String?, avatarURLString: String?) {
        let dict = UserDefaults.standard.dictionary(forKey: Self.profileKey(provider))
            as? [String: String]
        return (dict?["accountId"], dict?["displayName"], dict?["avatarURL"])
    }

    /// (92) 任务 10：VIP 等级缓存——与资料缓存同 dict 合并
    /// 写，只动 "vipLevel" 键（nil = 清除该键）；退出登录走
    /// clear 的整表删除、VIP 随之清，不另设路。
    func saveVIP(provider: Provider, level: Int?) {
        let key = Self.profileKey(provider)
        var dict = (UserDefaults.standard.dictionary(forKey: key)
            as? [String: String]) ?? [:]
        if let level {
            dict["vipLevel"] = String(level)
        } else {
            dict.removeValue(forKey: "vipLevel")
        }
        UserDefaults.standard.set(dict, forKey: key)
    }

    /// 读 VIP 等级缓存（0 = 免费、>0 = 会员、nil = 未知）。
    func vipLevel(provider: Provider) -> Int? {
        let dict = UserDefaults.standard.dictionary(
            forKey: Self.profileKey(provider)) as? [String: String]
        return dict?["vipLevel"].flatMap { Int($0) }
    }

    // MARK: - Keychain 基础读写

    private func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func keychainWrite(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}
