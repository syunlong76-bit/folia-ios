import Foundation

/// 舞台特效增强开关（3.7 (49)）：逐词强调层与粒子换行层
/// 的用户开关，UserDefaults 落盘，缺省全开。设置页
/// （SettingsViewController「歌词特效增强」卡）写、渲染方读。
/// 关掉逐词强调 → GlowWord 系回到 (48) 观感（超采样口径
/// 亦回 (47) 定档）；关掉粒子换行 → 翻行走各样式原出入场。
enum StageEffectSettings {

    private static let emphasisKey = "folia.stage.wordEmphasis"
    private static let particleKey = "folia.stage.particleFlip"

    static var wordEmphasisEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: emphasisKey) != nil else { return true }
            return defaults.bool(forKey: emphasisKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: emphasisKey) }
    }

    static var particleFlipEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: particleKey) != nil else { return true }
            return defaults.bool(forKey: particleKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: particleKey) }
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
