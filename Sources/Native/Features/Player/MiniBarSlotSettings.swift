import Foundation

/// 点播台按钮槽位设置（3.7 (50)，(48) 挂账③）：控制三台
/// （主页墙/曲目墙/舞台）点播台上「上一首 / 下一首 / 播放
/// 列表」三键的显隐；播放键恒显、不设槽位（三台的动作分发
/// 与收起计时都以它为锚）。主页墙台本无列表键，showQueue
/// 只对曲目墙台与舞台台生效。
///
/// (53) 工作流 C 存储兼容改造（行为不变）：落盘改经统一
/// SettingsStore（新键 settings.player.* 为主、旧键
/// folia.miniBar.* 兼容读并同步写、旧键不删）。公开 API 与
/// 缺省口径（键不存在 → true，即默认全显 = 现状）逐字不
/// 变，三台 applyMiniBarSlots 读者无感知。
enum MiniBarSlotSettings {

    static var showPrev: Bool {
        get { SettingsStore.showPrevButton }
        set { SettingsStore.showPrevButton = newValue }
    }

    static var showNext: Bool {
        get { SettingsStore.showNextButton }
        set { SettingsStore.showNextButton = newValue }
    }

    static var showQueue: Bool {
        get { SettingsStore.showQueueButton }
        set { SettingsStore.showQueueButton = newValue }
    }
}

extension Notification.Name {
    /// 点播台槽位变更（3.7 (50)）：设置页开关发出，三台各自
    /// 订阅后重跑 applyMiniBarSlots。专用通知，不复用主题通
    /// 知——主题回调带「主题未变即 return」的守卫，会把槽位
    /// 变更吞掉。
    static let foliaMiniBarSlotsChanged = Notification.Name("foliaMiniBarSlotsChanged")
}
