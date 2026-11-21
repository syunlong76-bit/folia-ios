import Foundation

/// (66) 后台节流的活动信号面（网页「后台节流」有条件项的
/// 客户端落点）：节流判据需要知道 OBS 浏览器源客户端是否
/// 在场——LocalServer 每次服务 /obs 请求时登记时刻，本面
/// 以「最近 12 秒内有拉取」判在场（OBS 页 5 秒自动刷新，
/// 两轮未到即判离场）。
///
/// 消费：MediaCache62 自动回填——节流开且 OBS 客户端在场
/// 时推迟回填（不与直播捕获抢资源）；节流关时恒放行。
/// 设置行（直播与 OBS 组）文案按此联动如实标注。
enum BackgroundThrottle62 {

    private static let lock = NSLock()
    private static var lastOBSActivity: Date?

    /// LocalServer /obs 路由调用。
    static func noteOBSActivity() {
        lock.lock()
        lastOBSActivity = Date()
        lock.unlock()
    }

    /// OBS 客户端是否在场（最近 12 秒内拉过 /obs）。
    static var obsClientActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let last = lastOBSActivity else { return false }
        return Date().timeIntervalSince(last) < 12
    }

    /// 后台工作是否可执行：节流策略 standard → 恒可；
    /// aggressive 且 OBS 在场 → 不可（推迟）；aggressive
    /// 且 OBS 不在场 → 可。策略键为既有
    /// SettingsStore.backgroundThrottlePolicy（图形页签）。
    static var allowsBackgroundWork: Bool {
        guard SettingsStore.backgroundThrottlePolicy == "aggressive" else { return true }
        return !obsClientActive
    }
}
