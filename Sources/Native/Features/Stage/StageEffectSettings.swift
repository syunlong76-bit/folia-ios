import Foundation

/// 舞台特效增强开关（3.7 (49)）：逐词强调层与粒子换行层
/// 的用户开关，缺省全开。设置页（SettingsViewController
/// 「歌词」组）写、渲染方读。关掉逐词强调 → GlowWord 系回
/// 到 (48) 观感（超采样口径亦回 (47) 定档）；关掉粒子换行
/// → 翻行走各样式原出入场。
///
/// (53) 工作流 C 存储兼容改造（行为不变）：落盘改经统一
/// SettingsStore（新键 settings.lyrics.* 为主、旧键
/// folia.stage.* 兼容读并同步写、旧键不删）。本门面的公开
/// API 与缺省口径（键不存在 → true）逐字不变，全部既有读
/// 者（GlowWordEngine / StageTextKit；原读者 Cadenza /
/// Classic / Monet 三渲染器已随 (70) A 组删除）无感知。
enum StageEffectSettings {

    static var wordEmphasisEnabled: Bool {
        get { SettingsStore.wordEmphasisEnabled }
        set { SettingsStore.wordEmphasisEnabled = newValue }
    }

    static var particleFlipEnabled: Bool {
        get { SettingsStore.particleFlipEnabled }
        set { SettingsStore.particleFlipEnabled = newValue }
    }

    // MARK: 逐帧读的缓存面

    /// GlowWordView.update 每帧每词都会问一次开关：
    /// UserDefaults 直读太频，这里做 0.25s 刷新的进程内
    /// 缓存（设置页拨动后至多 0.25s 在舞台生效）。
    private static var cachedEmphasis = true
    private static var cachedEmphasisAt: CFTimeInterval = -1

    static func emphasisEnabledCached(now: CFTimeInterval) -> Bool {
        if cachedEmphasisAt < 0 || now - cachedEmphasisAt > 0.25 {
            cachedEmphasis = wordEmphasisEnabled
            cachedEmphasisAt = now
        }
        return cachedEmphasis
    }
}
