import Foundation

/// (53) B 组：单家登录状态快照（侧栏头像区/设置页共用）。
/// 全部字段来自本地缓存同步读：isLoggedIn 以 Keychain 会话
/// 是否存在为准，昵称/头像/accountId 来自 NativeSessionStore
/// 的资料缓存（登录成功或状态刷新时写入）——拿不到就不给，
/// 不在此发网络请求。
struct ProviderSessionStatus {
    let provider: NativeSessionStore.Provider
    let isLoggedIn: Bool
    let accountId: String?
    let displayName: String?
    let avatarURL: URL?
    /// (92) 任务 10：VIP 等级（0 免费、>0 会员、nil 未知），
    /// 来自资料缓存的 vipLevel 键（写入点见三家 enrich）。
    let vipLevel: Int?
}

/// 轻量状态查询 API（供工作流 A 的侧栏头像区调用，同步、
/// 无网络、主线程可直接调）：
///
///   let status = ProviderSessionStatusQuery.status(for: .qq)
///   let all = ProviderSessionStatusQuery.allStatuses()
///
/// status(for:) 对 .netease 的 isLoggedIn 与 (51) 既有口径
/// 一致（NativeSessionStore.load() != nil）。
enum ProviderSessionStatusQuery {

    static func status(for provider: NativeSessionStore.Provider) -> ProviderSessionStatus {
        let store = NativeSessionStore.shared
        let profile = store.profile(provider: provider)
        var accountId = profile.accountId
        var displayName = profile.displayName
        // QQ envelope 自带 accountId/displayName，资料缓存缺失时回填。
        if provider == .qq, let envelope = store.loadQQEnvelope() {
            if accountId == nil { accountId = envelope.accountId }
            if displayName == nil { displayName = envelope.displayName }
        }
        return ProviderSessionStatus(
            provider: provider,
            isLoggedIn: store.load(provider: provider) != nil,
            accountId: accountId,
            displayName: displayName,
            avatarURL: profile.avatarURLString.flatMap { URL(string: $0) },
            vipLevel: store.vipLevel(provider: provider))
    }

    static func allStatuses() -> [ProviderSessionStatus] {
        NativeSessionStore.Provider.allCases.map { status(for: $0) }
    }
}
