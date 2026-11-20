import CryptoKit
import Foundation
import Security

/// (51) A 组：原生会话存储。网易云登录 cookie 整串存 Keychain
/// （kSecClassGenericPassword），取代 WebView localStorage 作为
/// 登录态的权威数据源（迁移见 SessionMigrator）。
///
/// 纪律：cookie 是凭据——本类只做存取，绝不写日志；对外只许
/// 暴露 len 与 SHA-256 前 8 位（hash8）供面包屑对账。
final class NativeSessionStore {

    static let shared = NativeSessionStore()

    /// Keychain service：bundle 相关常量（随 bundle id 派生，
    /// 不同包互不串话）。
    static var service: String {
        (Bundle.main.bundleIdentifier ?? "com.miller.folia") + ".session"
    }
    private static let account = "netease-cookie"

    private let lock = NSLock()
    private var memoryCache: String?
    private var memoryCacheLoaded = false

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

    /// 面包屑专用指纹：SHA-256 十六进制前 8 位。
    static func hash8(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    // MARK: - 存取（内存缓存一层）

    /// 读会话串：先内存缓存，未命中查 Keychain 并回填。
    func load() -> String? {
        lock.lock()
        if memoryCacheLoaded {
            let cached = memoryCache
            lock.unlock()
            return cached
        }
        lock.unlock()
        let value = keychainRead()
        lock.lock()
        memoryCache = value
        memoryCacheLoaded = true
        lock.unlock()
        return value
    }

    /// 绕缓存直读 Keychain（迁移回读比对专用）。
    func loadDirect() -> String? {
        keychainRead()
    }

    /// 写会话串（add-or-update），成功同步内存缓存。
    @discardableResult
    func save(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
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
        guard status == errSecSuccess else { return false }
        lock.lock()
        memoryCache = value
        memoryCacheLoaded = true
        lock.unlock()
        return true
    }

    /// 清会话（退出登录/会话失效），同步清内存缓存。
    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        SecItemDelete(query as CFDictionary)
        lock.lock()
        memoryCache = nil
        memoryCacheLoaded = true
        lock.unlock()
    }

    private func keychainRead() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
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
}
