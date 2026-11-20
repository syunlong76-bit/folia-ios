import Foundation

/// 点播台按钮槽位设置（3.7 (50)，(48) 挂账③）：控制三台
/// （主页墙/曲目墙/舞台）点播台上「上一首 / 下一首 / 播放
/// 列表」三键的显隐；播放键恒显、不设槽位（三台的动作分发
/// 与收起计时都以它为锚）。存储与 StageEffectSettings 同构：
/// UserDefaults、键不存在 → true，即默认全显 = 现状，零迁移。
/// 主页墙台本无列表键，showQueue 只对曲目墙台与舞台台生效。
enum MiniBarSlotSettings {

    private static let prevKey = "folia.miniBar.showPrev"
    private static let nextKey = "folia.miniBar.showNext"
    private static let queueKey = "folia.miniBar.showQueue"

    private static func flag(_ key: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    static var showPrev: Bool {
        get { flag(prevKey) }
        set { UserDefaults.standard.set(newValue, forKey: prevKey) }
    }

    static var showNext: Bool {
        get { flag(nextKey) }
        set { UserDefaults.standard.set(newValue, forKey: nextKey) }
    }

    static var showQueue: Bool {
        get { flag(queueKey) }
        set { UserDefaults.standard.set(newValue, forKey: queueKey) }
    }
}

extension Notification.Name {
    /// 点播台槽位变更（3.7 (50)）：设置页开关发出，三台各自
    /// 订阅后重跑 applyMiniBarSlots。专用通知，不复用主题通
    /// 知——主题回调带「主题未变即 return」的守卫，会把槽位
    /// 变更吞掉。
    static let foliaMiniBarSlotsChanged = Notification.Name("foliaMiniBarSlotsChanged")
}
