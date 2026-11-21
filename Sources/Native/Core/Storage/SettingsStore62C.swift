import CryptoKit
import Foundation
import Security

// SettingsStore62C.swift
//
// 3.7 (62) WC 簇设置键层（通用契约）：extension SettingsStore
// ＋ Key62C ＋计算属性访问器。键名一律 `settings.<group>.<key>`。
// 凭据类（Navidrome 密码、同步令牌、Discord Webhook、PlayerCap
// 令牌位）不进 UserDefaults，走 SecretStore62C（Keychain，沿用
// NativeSessionStore 的 kSecClassGenericPassword 写法）。

extension SettingsStore {

    enum Key62C {
        // 连接与集成（§4.9）
        static let navidromeEnabled = "settings.navidrome.enabled"
        static let navidromeBaseURL = "settings.navidrome.baseURL"
        static let navidromeUsername = "settings.navidrome.username"
        static let syncEnabled = "settings.sync.enabled"
        static let syncBaseURL = "settings.sync.baseURL"
        static let syncLastStatus = "settings.sync.lastStatus"
        static let discordEnabled = "settings.discord.enabled"
        static let scrobbleEnabled = "settings.scrobble.enabled"
        static let playerCapEnabled = "settings.playercap.enabled"
        static let playerCapBaseURL = "settings.playercap.baseURL"
        static let playerCapPlayerName = "settings.playercap.playerName"
        static let playerCapTimelineEnabled = "settings.playercap.timelineEnabled"
        static let playerCapIgnoreClear = "settings.playercap.ignoreClear"
        static let transparentStageBackground = "settings.live.transparentStageBackground"
        // (66) 本机歌词接口开放开关（LocalServer /v1/lyric）
        static let lyricAPIEnabled = "settings.integration.lyricAPIEnabled"
        // (66) 媒体缓存目录自选（安全作用域书签 Data）
        static let mediaCacheDirBookmark = "settings.storage.mediaCacheDirBookmark"
        // (66) 运行日志采集开关（FoliaBridgeLogStore 总门控）
        static let logCaptureEnabled = "settings.dev.logCaptureEnabled"
        // 播放面板（§5）
        static let streamQuality = "settings.player.streamQuality"
        // 存储与备份（§4.10）
        static let mediaCacheEnabled = "settings.storage.mediaCacheEnabled"
        static let mediaCacheAutoRefill = "settings.storage.mediaCacheAutoRefill"
        static let mediaCacheLimitMB = "settings.storage.mediaCacheLimitMB"
        static let autoScanImportedFolders = "settings.storage.autoScanImportedFolders"
        static let folderWatchEnabled = "settings.storage.folderWatchEnabled"
        // 开发者（§4.11）
        static let bridgeLogWriteEnabled = "settings.dev.bridgeLogWriteEnabled"
        static let memorySampleIntervalSec = "settings.dev.memorySampleIntervalSec"
        // 本地歌词（§4.6 消费端，键由 WC 落、WB 歌词链可读）
        static let localLyricFormatOrder = "settings.lyrics.localLyricFormatOrder"
        static let localLyricPriority = "settings.lyrics.localLyricPriority"
    }

    private static var d62c: UserDefaults { .standard }

    // MARK: - Navidrome

    static var navidromeEnabled62: Bool {
        get { d62c.bool(forKey: Key62C.navidromeEnabled) }
        set { d62c.set(newValue, forKey: Key62C.navidromeEnabled) }
    }
    static var navidromeBaseURL62: String {
        get { d62c.string(forKey: Key62C.navidromeBaseURL) ?? "" }
        set { d62c.set(newValue, forKey: Key62C.navidromeBaseURL) }
    }
    static var navidromeUsername62: String {
        get { d62c.string(forKey: Key62C.navidromeUsername) ?? "" }
        set { d62c.set(newValue, forKey: Key62C.navidromeUsername) }
    }

    // MARK: - 同步服务 R2

    static var syncEnabled62: Bool {
        get { d62c.bool(forKey: Key62C.syncEnabled) }
        set { d62c.set(newValue, forKey: Key62C.syncEnabled) }
    }
    static var syncBaseURL62: String {
        get { d62c.string(forKey: Key62C.syncBaseURL) ?? "" }
        set { d62c.set(newValue, forKey: Key62C.syncBaseURL) }
    }
    static var syncLastStatus62: String {
        get { d62c.string(forKey: Key62C.syncLastStatus) ?? "" }
        set { d62c.set(newValue, forKey: Key62C.syncLastStatus) }
    }

    // MARK: - Discord / scrobble / PlayerCap

    static var discordEnabled62: Bool {
        get { d62c.bool(forKey: Key62C.discordEnabled) }
        set { d62c.set(newValue, forKey: Key62C.discordEnabled) }
    }
    static var scrobbleEnabled62: Bool {
        get { d62c.bool(forKey: Key62C.scrobbleEnabled) }
        set { d62c.set(newValue, forKey: Key62C.scrobbleEnabled) }
    }
    static var playerCapEnabled62: Bool {
        get { d62c.bool(forKey: Key62C.playerCapEnabled) }
        set { d62c.set(newValue, forKey: Key62C.playerCapEnabled) }
    }
    static var playerCapBaseURL62: String {
        get { d62c.string(forKey: Key62C.playerCapBaseURL) ?? "" }
        set { d62c.set(newValue, forKey: Key62C.playerCapBaseURL) }
    }
    static var playerCapPlayerName62: String {
        get { d62c.string(forKey: Key62C.playerCapPlayerName) ?? "Folia iOS" }
        set { d62c.set(newValue, forKey: Key62C.playerCapPlayerName) }
    }
    static var playerCapTimelineEnabled62: Bool {
        get {
            if d62c.object(forKey: Key62C.playerCapTimelineEnabled) == nil { return true }
            return d62c.bool(forKey: Key62C.playerCapTimelineEnabled)
        }
        set { d62c.set(newValue, forKey: Key62C.playerCapTimelineEnabled) }
    }
    static var playerCapIgnoreClear62: Bool {
        get { d62c.bool(forKey: Key62C.playerCapIgnoreClear) }
        set { d62c.set(newValue, forKey: Key62C.playerCapIgnoreClear) }
    }

    // MARK: - 直播 / OBS

    /// 播放页透明背景（§4.9）：消费在 StageVC（WA 簇），WC 只
    /// 提供键与设置行。键名按任务书定死。
    static var transparentStageBackground62: Bool {
        get { d62c.bool(forKey: Key62C.transparentStageBackground) }
        set { d62c.set(newValue, forKey: Key62C.transparentStageBackground) }
    }

    /// (66) 本机歌词接口（默认关）：开时 LocalServer 增开
    /// GET /v1/lyric 输出当前曲歌词 JSON 供本机外部程序读。
    static var lyricAPIEnabled62: Bool {
        get { d62c.bool(forKey: Key62C.lyricAPIEnabled) }
        set { d62c.set(newValue, forKey: Key62C.lyricAPIEnabled) }
    }

    /// (66) 运行日志采集（默认开）：关时 FoliaBridgeLogStore
    /// 不再记录（落盘与内存环都停，控制台 NSLog 不受影响）。
    static var logCaptureEnabled62: Bool {
        get {
            if d62c.object(forKey: Key62C.logCaptureEnabled) == nil { return true }
            return d62c.bool(forKey: Key62C.logCaptureEnabled)
        }
        set { d62c.set(newValue, forKey: Key62C.logCaptureEnabled) }
    }

    /// (66) 媒体缓存自选目录书签（DS 改判落地）：UIDocument-
    /// Picker 选文件夹后存安全作用域书签；MediaCache62 根目
    /// 录解析消费。nil = 用默认 Caches/folia-media62。
    static var mediaCacheDirBookmark62: Data? {
        get { d62c.data(forKey: Key62C.mediaCacheDirBookmark) }
        set {
            if let newValue { d62c.set(newValue, forKey: Key62C.mediaCacheDirBookmark) }
            else { d62c.removeObject(forKey: Key62C.mediaCacheDirBookmark) }
        }
    }

    // MARK: - 音质（§5 音质页签，EdgeOneAPIClient 取流消费）

    /// 取流音质档位（网易云 /song/url/v1 的 level 参数）：
    /// standard / higher / exhigh（默认，与既有行为一致）/
    /// lossless / hires。后端是否认账待真机验，见报告。
    static var streamQuality62: String {
        get {
            let raw = d62c.string(forKey: Key62C.streamQuality) ?? "exhigh"
            return ["standard", "higher", "exhigh", "lossless", "hires"].contains(raw)
                ? raw : "exhigh"
        }
        set { d62c.set(newValue, forKey: Key62C.streamQuality) }
    }

    // MARK: - 存储

    static var mediaCacheEnabled62: Bool {
        get {
            if d62c.object(forKey: Key62C.mediaCacheEnabled) == nil { return true }
            return d62c.bool(forKey: Key62C.mediaCacheEnabled)
        }
        set { d62c.set(newValue, forKey: Key62C.mediaCacheEnabled) }
    }
    /// (66) 缓存歌曲自动回填（默认开）：切歌时自动把当前
    /// 曲与队列后续曲目回填进媒体缓存（MediaCache62.
    /// startAutoRefill 消费；仍受 mediaCacheEnabled62 总闸）。
    static var mediaCacheAutoRefill62: Bool {
        get {
            if d62c.object(forKey: Key62C.mediaCacheAutoRefill) == nil { return true }
            return d62c.bool(forKey: Key62C.mediaCacheAutoRefill)
        }
        set { d62c.set(newValue, forKey: Key62C.mediaCacheAutoRefill) }
    }
    /// 媒体缓存上限（MB）：默认 256，钳制 32...512（通用契约
    /// 媒体缓存默认上限克制 ≤512MB）。
    static var mediaCacheLimitMB62: Int {
        get {
            let raw = d62c.integer(forKey: Key62C.mediaCacheLimitMB)
            return raw == 0 ? 256 : min(max(raw, 32), 512)
        }
        set { d62c.set(min(max(newValue, 32), 512), forKey: Key62C.mediaCacheLimitMB) }
    }
    static var autoScanImportedFolders62: Bool {
        get {
            if d62c.object(forKey: Key62C.autoScanImportedFolders) == nil { return true }
            return d62c.bool(forKey: Key62C.autoScanImportedFolders)
        }
        set { d62c.set(newValue, forKey: Key62C.autoScanImportedFolders) }
    }
    static var folderWatchEnabled62: Bool {
        get { d62c.bool(forKey: Key62C.folderWatchEnabled) }
        set { d62c.set(newValue, forKey: Key62C.folderWatchEnabled) }
    }

    // MARK: - 开发者

    /// 桥日志写入本地文件开关（§4.11）：默认开（既有行为）；
    /// 关时 FoliaBridgeLogStore.write 只走 NSLog 不落盘。
    static var bridgeLogWriteEnabled62: Bool {
        get {
            if d62c.object(forKey: Key62C.bridgeLogWriteEnabled) == nil { return true }
            return d62c.bool(forKey: Key62C.bridgeLogWriteEnabled)
        }
        set { d62c.set(newValue, forKey: Key62C.bridgeLogWriteEnabled) }
    }
    /// 内存监控采样间隔（秒）：默认 5，钳制 2...60。
    static var memorySampleIntervalSec62: Int {
        get {
            let raw = d62c.integer(forKey: Key62C.memorySampleIntervalSec)
            return raw == 0 ? 5 : min(max(raw, 2), 60)
        }
        set { d62c.set(min(max(newValue, 2), 60), forKey: Key62C.memorySampleIntervalSec) }
    }

    // MARK: - 本地歌词（§4.6 消费端键）

    /// 本地歌词格式顺序：逗号分隔的扩展名序，默认 "lrc,txt"。
    static var localLyricFormatOrder62: String {
        get { d62c.string(forKey: Key62C.localLyricFormatOrder) ?? "lrc,txt" }
        set { d62c.set(newValue, forKey: Key62C.localLyricFormatOrder) }
    }
    /// 本地歌曲歌词优先级：localFirst（默认）/ remoteFirst。
    static var localLyricPriority62: String {
        get { d62c.string(forKey: Key62C.localLyricPriority) ?? "localFirst" }
        set { d62c.set(newValue, forKey: Key62C.localLyricPriority) }
    }
}

// MARK: - 凭据存储（Keychain，沿用 NativeSessionStore 写法）

/// 62 WC 簇凭据：Navidrome 密码 / 同步令牌 / Discord Webhook
/// URL（本质是带令牌的 URL，按凭据处理）。service 与
/// NativeSessionStore 同域不同 account 前缀，互不干扰。
enum SecretStore62C {

    private static let service: String = {
        (Bundle.main.bundleIdentifier ?? "com.miller.folia") + ".folia-session"
    }()

    static let navidromePasswordAccount = "62c.navidrome.password"
    static let syncTokenAccount = "62c.sync.token"
    static let discordWebhookAccount = "62c.discord.webhook"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return delete(account: account) }
        guard let data = trimmed.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// MD5 十六进制（Subsonic token 认证用：md5(password + salt)）。
enum MD5Hex62 {
    static func of(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    static func of(data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
