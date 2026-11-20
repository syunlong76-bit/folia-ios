import Foundation

/// 统一设置存储（3.7 (53) 工作流 C，DS 对账定案）：
///
/// - 命名空间 `settings.<group>.<key>`；类型化 schema 集中在本
///   文件，调用方只用下面的类型化属性，不散写键名字符串。
/// - 默认值经 `register(defaults:)` 注册（注册域不写盘）；带旧
///   键的条目走兼容读：新键已落盘 → 读新键；否则旧键存在 →
///   读旧键并回填新键。**旧键本包不删**，且每次写新键同步写旧
///   键——本包禁改文件里的既有读者（MiniPlayerTheme /
///   StickerSettings 等）继续读旧键，行为不变。
/// - 存在性判定：Bool 一律以落盘域是否含键为准。新键已注册默
///   认值，`object(forKey:)` 会把注册域也算进去、无法区分「用
///   户已写」与「仅注册」，故新键存在性查 persistentDomain；
///   旧键从未注册，`object(forKey:)` 即真实存在性。
/// - 不入本存储（DS 定案）：登录态/会话、队列/进度/当前曲目、
///   侧栏/抽屉开合等 UI 瞬态、server 状态、睡眠倒计时激活态。
enum SettingsStore {

    // MARK: - Schema（键名）

    enum Key {
        static let miniPlayerThemeEffectsEnabled =
            "settings.interface.miniPlayerThemeEffectsEnabled"
        static let wordEmphasisEnabled = "settings.lyrics.wordEmphasisEnabled"
        static let particleFlipEnabled = "settings.lyrics.particleFlipEnabled"
        static let showPrevButton = "settings.player.showPrevButton"
        static let showNextButton = "settings.player.showNextButton"
        static let showQueueButton = "settings.player.showQueueButton"
        static let miniPetsEnabled = "settings.general.miniPetsEnabled"
        static let loopMode = "settings.playback.loopMode"
        static let globalLyricTimelineOffsetMs =
            "settings.lyrics.globalLyricTimelineOffsetMs"
    }

    /// 旧键映射（(50) 及以前的原生键名）：仅作兼容读与同步写
    /// 的目标，本包不删除任何旧键。
    private enum LegacyKey {
        static let miniPlayerThemeEffectsEnabled = "folia.miniPlayerThemeEnabled"
        static let wordEmphasisEnabled = "folia.stage.wordEmphasis"
        static let particleFlipEnabled = "folia.stage.particleFlip"
        static let showPrevButton = "folia.miniBar.showPrev"
        static let showNextButton = "folia.miniBar.showNext"
        static let showQueueButton = "folia.miniBar.showQueue"
        static let miniPetsEnabled = "folia.stickers.miniPetsEnabled"
    }

    // MARK: - 默认值注册（只注册、不写盘；static let 初始化线程安全）

    private static let defaultsRegistration: Void = {
        UserDefaults.standard.register(defaults: [
            Key.miniPlayerThemeEffectsEnabled: true,
            Key.wordEmphasisEnabled: true,
            Key.particleFlipEnabled: true,
            Key.showPrevButton: true,
            Key.showNextButton: true,
            Key.showQueueButton: true,
            Key.miniPetsEnabled: true,
            Key.loopMode: "loopAll",
            Key.globalLyricTimelineOffsetMs: 0,
        ])
    }()

    private static func ensureRegistered() { _ = defaultsRegistration }

    // MARK: - 兼容读/写原语

    /// 新键是否已有用户落盘值（注册域不算）。persistentDomain
    /// 只含落盘域、不含注册域，正合所需；域名取 bundle id
    /// （UserDefaults.standard 的落盘域名），取不到时退回工程
    /// 既定 id（project.yml PRODUCT_BUNDLE_IDENTIFIER）。
    private static func hasPersistedValue(forKey key: String) -> Bool {
        let domainName = Bundle.main.bundleIdentifier ?? "com.miller.folia"
        guard let domain = UserDefaults.standard.persistentDomain(forName: domainName)
        else { return false }
        return domain[key] != nil
    }

    /// 带旧键的 Bool 兼容读：新键已落盘读新键；否则旧键存在
    /// 则读旧键并回填新键；两者皆无落 schema 默认。
    private static func boolValue(key: String, legacyKey: String,
                                  defaultValue: Bool) -> Bool {
        ensureRegistered()
        let defaults = UserDefaults.standard
        if hasPersistedValue(forKey: key) {
            return defaults.bool(forKey: key)
        }
        if defaults.object(forKey: legacyKey) != nil {
            let value = defaults.bool(forKey: legacyKey)
            defaults.set(value, forKey: key)
            return value
        }
        return defaultValue
    }

    /// 写新键的同时同步写旧键：旧读者（本包禁改文件）读到的
    /// 永远是最新值；新旧键同值，任一侧的存在性判定不打架。
    private static func setBoolValue(_ value: Bool, key: String, legacyKey: String) {
        ensureRegistered()
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        defaults.set(value, forKey: legacyKey)
    }

    // MARK: - 界面组

    /// 播放台主题特效总开关（原生既有，(13.5)）：消费者
    /// MiniPlayerTheme.effectsEnabled / effective（墙/舞台点播
    /// 台长按切换与主题层）。旧键由 MiniPlayerTheme 直读，本
    /// 属性每次写同步旧键，读者行为不变。
    static var miniPlayerThemeEffectsEnabled: Bool {
        get {
            boolValue(key: Key.miniPlayerThemeEffectsEnabled,
                      legacyKey: LegacyKey.miniPlayerThemeEffectsEnabled,
                      defaultValue: true)
        }
        set {
            setBoolValue(newValue, key: Key.miniPlayerThemeEffectsEnabled,
                         legacyKey: LegacyKey.miniPlayerThemeEffectsEnabled)
        }
    }

    // MARK: - 歌词组

    /// 逐词强调开关（原生既有，(49)）：经 StageEffectSettings
    /// 门面供 GlowWordEngine / CadenzaStageRenderer /
    /// StageTextKit 读。
    static var wordEmphasisEnabled: Bool {
        get {
            boolValue(key: Key.wordEmphasisEnabled,
                      legacyKey: LegacyKey.wordEmphasisEnabled,
                      defaultValue: true)
        }
        set {
            setBoolValue(newValue, key: Key.wordEmphasisEnabled,
                         legacyKey: LegacyKey.wordEmphasisEnabled)
        }
    }

    /// 粒子换行开关（原生既有，(49)）：经 StageEffectSettings
    /// 门面供 ClassicStageRenderer / MonetStageRenderer 读。
    static var particleFlipEnabled: Bool {
        get {
            boolValue(key: Key.particleFlipEnabled,
                      legacyKey: LegacyKey.particleFlipEnabled,
                      defaultValue: true)
        }
        set {
            setBoolValue(newValue, key: Key.particleFlipEnabled,
                         legacyKey: LegacyKey.particleFlipEnabled)
        }
    }

    /// 全局歌词时间轴偏移（网页 globalLyricTimelineOffsetMs
    /// 对应物，(53) 任务点名）：**仅落存储与设置页入口**——
    /// LyricTiming 与全部歌词时钟/播放链路不读本键（待 C 项真
    /// 机测量结论后另包接入）。默认 0，钳制 ±2000ms，读写都
    /// 钳。无旧键（原生此前无此设置）。
    static var globalLyricTimelineOffsetMs: Int {
        get {
            ensureRegistered()
            return Self.clampLyricOffsetMs(
                UserDefaults.standard.integer(forKey: Key.globalLyricTimelineOffsetMs))
        }
        set {
            ensureRegistered()
            UserDefaults.standard.set(
                Self.clampLyricOffsetMs(newValue),
                forKey: Key.globalLyricTimelineOffsetMs)
        }
    }

    static func clampLyricOffsetMs(_ ms: Int) -> Int {
        min(max(ms, -2000), 2000)
    }

    // MARK: - 播放组

    /// 循环模式（网页 loopMode 对应物）：存 QueueManager
    /// .PlayMode 的 rawValue（loopAll / repeatOne / shuffle /
    /// off）。无旧键——playMode 此前从未落盘（队列面板内内存
    /// 态）；设置页读写以 QueueManager.shared.playMode 为生
    /// 效面、本键为偏好镜像（冷启恢复待 QueueManager 初始化
    /// 侧后续包接入，本包禁改该文件）。
    static var loopModeRaw: String {
        get {
            ensureRegistered()
            return UserDefaults.standard.string(forKey: Key.loopMode) ?? "loopAll"
        }
        set {
            ensureRegistered()
            UserDefaults.standard.set(newValue, forKey: Key.loopMode)
        }
    }

    // MARK: - 播放器（点播台）组

    /// 点播台三键显隐（原生既有，(50)）：经 MiniBarSlotSettings
    /// 门面供三台 applyMiniBarSlots 读。
    static var showPrevButton: Bool {
        get {
            boolValue(key: Key.showPrevButton,
                      legacyKey: LegacyKey.showPrevButton, defaultValue: true)
        }
        set {
            setBoolValue(newValue, key: Key.showPrevButton,
                         legacyKey: LegacyKey.showPrevButton)
        }
    }

    static var showNextButton: Bool {
        get {
            boolValue(key: Key.showNextButton,
                      legacyKey: LegacyKey.showNextButton, defaultValue: true)
        }
        set {
            setBoolValue(newValue, key: Key.showNextButton,
                         legacyKey: LegacyKey.showNextButton)
        }
    }

    static var showQueueButton: Bool {
        get {
            boolValue(key: Key.showQueueButton,
                      legacyKey: LegacyKey.showQueueButton, defaultValue: true)
        }
        set {
            setBoolValue(newValue, key: Key.showQueueButton,
                         legacyKey: LegacyKey.showQueueButton)
        }
    }

    // MARK: - 通用组

    /// 迷你台小宠物开关（原生既有，(29)）：消费者
    /// StickerSettings.miniPetsEnabled（MiniBarPetStage 读）。
    /// StickerSettings 在本包禁改文件内，其旧键由本属性每次
    /// 写同步，读者行为不变。
    static var miniPetsEnabled: Bool {
        get {
            boolValue(key: Key.miniPetsEnabled,
                      legacyKey: LegacyKey.miniPetsEnabled, defaultValue: true)
        }
        set {
            setBoolValue(newValue, key: Key.miniPetsEnabled,
                         legacyKey: LegacyKey.miniPetsEnabled)
        }
    }
}
