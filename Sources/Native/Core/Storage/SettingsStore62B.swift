import Foundation

/// (62) WB 簇设置键层：§4.4 动画与性能 / §4.5 播放控制 /
/// §4.6 歌词 / §4.7 通用余项 / §4.8 快捷操作 / §4.9 两项
/// （歌词接口、舞台模式与数据来源）。
///
/// 契约（四簇共同）：键名 `settings.<group>.<key>`；本文件只
/// 做 `extension SettingsStore` + `enum Key62B` + 计算属性访
/// 问器（extension 不许 stored static）。基座 SettingsStore
/// 的 defaultsRegistration 是 private，本层自带存在性判定：
/// Bool/数值一律以「落盘域是否含键」区分未写与已写，未写时
/// 回 schema 默认，不依赖 register(defaults:)。
extension SettingsStore {

    enum Key62B {
        // §4.4 动画与性能
        static let reduceQueueCollage = "settings.graphics.reduceMotionQueueCollage"
        static let reduceMixTransition = "settings.graphics.reduceMotionMixTransition"
        static let reducePlaylistExpand = "settings.graphics.reduceMotionPlaylistExpand"
        static let reduceMonetDrift = "settings.graphics.reduceMotionMonetDrift"
        static let reduceMicroEffects = "settings.graphics.reduceMotionMicroEffects"
        static let reduceSettingsScroll = "settings.graphics.reduceMotionSettingsScroll"
        static let staticMode = "settings.graphics.staticMode"
        static let homeDynamicBackgroundEnabled = "settings.graphics.homeDynamicBackgroundEnabled"
        static let frameRateLimitEnabled = "settings.graphics.frameRateLimitEnabled"
        static let frameRateLimitFPS = "settings.graphics.frameRateLimitFPS"
        static let lyricAntialiasEnabled = "settings.graphics.lyricAntialiasEnabled"
        static let backgroundThrottlePolicy = "settings.graphics.backgroundThrottlePolicy"
        static let touchGlowEnabled = "settings.graphics.touchGlowEnabled"
        static let touchGlowDensity = "settings.graphics.touchGlowDensity"
        static let stageBackdropBlurEnabled = "settings.graphics.stageBackdropBlurEnabled"
        // §4.5 播放控制
        static let smartTransitionEnabled = "settings.playback.smartTransitionEnabled"
        static let transitionMode = "settings.playback.transitionMode"
        static let transitionMaxDurationSec = "settings.playback.transitionMaxDurationSec"
        static let transitionCurve = "settings.playback.transitionCurve"
        static let transitionAnimation = "settings.playback.transitionAnimation"
        static let replayGainEnabled = "settings.playback.replayGainEnabled"
        static let playPauseFadeMs = "settings.playback.playPauseFadeMs"
        static let autoTranscodeEnabled = "settings.playback.autoTranscodeEnabled"
        static let preventSleepWhilePlaying = "settings.playback.preventSleepWhilePlaying"
        static let pauseOnVoiceInput = "settings.playback.pauseOnVoiceInput"
        // §4.6 歌词
        static let autoBestLyricEnabled = "settings.lyrics.autoBestLyricEnabled"
        static let bestLyricStrategy = "settings.lyrics.bestLyricStrategy"
        static let lyricMatchPriority = "settings.lyrics.matchPriority"
        static let keepPlatformWordLyrics = "settings.lyrics.keepPlatformWordLyrics"
        static let localLyricPriority = "settings.lyrics.localLyricPriority"
        static let localLyricFormatOrder = "settings.lyrics.localLyricFormatOrder"
        static let lyricFilterRegex = "settings.lyrics.filterRegex"
        static let aiSegmentEnabled = "settings.lyrics.aiSegmentEnabled"
        static let aiSegmentEndpoint = "settings.lyrics.aiSegmentEndpoint"
        // §4.7 通用
        static let appLanguage = "settings.general.appLanguage"
        static let openPlayerOnLaunch = "settings.general.openPlayerOnLaunch"
        static let ponderTipsEnabled = "settings.general.ponderTipsEnabled"
        static let ponderTouchButtonEnabled = "settings.general.ponderTouchButtonEnabled"
        static let ponderSeenIDs = "settings.general.ponderSeenIDs"
        // §4.8 快捷操作
        static let pinnedCommandIDs = "settings.shortcuts.pinnedCommandIDs"
        static let gestureShortcutsEnabled = "settings.shortcuts.gestureShortcutsEnabled"
        static let longPressToolbarCommandPalette = "settings.shortcuts.longPressToolbarCommandPalette"
        static let swipeLeftTarget = "settings.shortcuts.swipeLeftTarget"
        static let posterWallSHotkeyEnabled = "settings.shortcuts.posterWallSHotkeyEnabled"
        // §4.9（WB 两项）
        static let lyricAPIBaseURL = "settings.integration.lyricAPIBaseURL"
        static let stageModeEnabled = "settings.integration.stageModeEnabled"
        static let stageDataSourceURL = "settings.integration.stageDataSourceURL"
    }

    // MARK: - 62B 读写原语（未写回默认，写后以落盘为准）

    private static func boolB62(_ key: String, default def: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return def }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func setBoolB62(_ value: Bool, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func int62(_ key: String, default def: Int) -> Int {
        guard UserDefaults.standard.object(forKey: key) != nil else { return def }
        return UserDefaults.standard.integer(forKey: key)
    }

    private static func double62(_ key: String, default def: Double) -> Double {
        guard UserDefaults.standard.object(forKey: key) != nil else { return def }
        return UserDefaults.standard.double(forKey: key)
    }

    private static func stringB62(_ key: String, default def: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? def
    }

    // MARK: - §4.4 降低动态细分（C1 门控的被控面；判定走 FoliaMotion62）

    /// 队列拼贴动效的独立降低动态开关（跟随系统关时生效）。
    static var reduceMotionQueueCollage: Bool {
        get { boolB62(Key62B.reduceQueueCollage, default: false) }
        set { setBoolB62(newValue, Key62B.reduceQueueCollage) }
    }

    /// 混音过渡动效的独立降低动态开关。
    static var reduceMotionMixTransition: Bool {
        get { boolB62(Key62B.reduceMixTransition, default: false) }
        set { setBoolB62(newValue, Key62B.reduceMixTransition) }
    }

    /// 歌单展开转场的独立降低动态开关。
    static var reduceMotionPlaylistExpand: Bool {
        get { boolB62(Key62B.reducePlaylistExpand, default: false) }
        set { setBoolB62(newValue, Key62B.reducePlaylistExpand) }
    }

    /// Monet 背景漂移的独立降低动态开关（消费符号
    /// FoliaMotion62.reduced(.monetDrift)，渲染器在 WD 文件域）。
    static var reduceMotionMonetDrift: Bool {
        get { boolB62(Key62B.reduceMonetDrift, default: false) }
        set { setBoolB62(newValue, Key62B.reduceMonetDrift) }
    }

    /// 界面微动效的独立降低动态开关。
    static var reduceMotionMicroEffects: Bool {
        get { boolB62(Key62B.reduceMicroEffects, default: false) }
        set { setBoolB62(newValue, Key62B.reduceMicroEffects) }
    }

    /// 设置页平滑滚动的独立降低动态开关。
    static var reduceMotionSettingsScroll: Bool {
        get { boolB62(Key62B.reduceSettingsScroll, default: false) }
        set { setBoolB62(newValue, Key62B.reduceSettingsScroll) }
    }

    // MARK: - §4.4 静态模式 / 主页动态背景 / 帧率 / 抗锯齿 / 后台节流 / 触摸光效 / 毛玻璃

    /// 静态模式（全局）：开时舞台渲染器逐帧动画停、墙面动效
    /// 停。消费：StageProgressDriver 停链 + 通知
    /// .foliaStaticModeChanged 供 StageVC（WA）停其 DisplayLink。
    static var staticModeEnabled: Bool {
        get { boolB62(Key62B.staticMode, default: false) }
        set { setBoolB62(newValue, Key62B.staticMode) }
    }

    /// 主页动态背景（默认开）：关时 HomeWall 动态背景层停显
    /// （消费在 WB62HomeWallHooks 的层门控）。
    static var homeDynamicBackgroundEnabled: Bool {
        get { boolB62(Key62B.homeDynamicBackgroundEnabled, default: true) }
        set { setBoolB62(newValue, Key62B.homeDynamicBackgroundEnabled) }
    }

    /// 实验性动画帧率限制开关（任务定死键名）。
    static var frameRateLimitEnabled: Bool {
        get { boolB62(Key62B.frameRateLimitEnabled, default: false) }
        set { setBoolB62(newValue, Key62B.frameRateLimitEnabled) }
    }

    /// 帧率限制档位（30/60/120，越界回 60；任务定死键名）。
    /// 消费：StageProgressDriver 直达；StageVC 的 DisplayLink
    /// 由 WA 读本访问器接线。
    static var frameRateLimitFPS: Int {
        get {
            let raw = int62(Key62B.frameRateLimitFPS, default: 60)
            return [30, 60, 120].contains(raw) ? raw : 60
        }
        set {
            UserDefaults.standard.set(
                [30, 60, 120].contains(newValue) ? newValue : 60,
                forKey: Key62B.frameRateLimitFPS)
        }
    }

    /// 歌词画布抗锯齿（全局，默认开）：消费在 LyricCanvas62
    /// （StageTextKit 烘焙入口的插值/抗锯齿口径）；逐样式
    /// antialias 调参仍优先于本全局键（见设置行 hint）。
    static var lyricAntialiasEnabled: Bool {
        get { boolB62(Key62B.lyricAntialiasEnabled, default: true) }
        set { setBoolB62(newValue, Key62B.lyricAntialiasEnabled) }
    }

    /// 后台节流策略：standard（默认，仅生命周期代偿）/
    /// aggressive（进后台即停进度驱动并降采样）。
    static var backgroundThrottlePolicy: String {
        get {
            let raw = stringB62(Key62B.backgroundThrottlePolicy, default: "standard")
            return raw == "aggressive" ? "aggressive" : "standard"
        }
        set {
            UserDefaults.standard.set(newValue == "aggressive" ? "aggressive" : "standard",
                                      forKey: Key62B.backgroundThrottlePolicy)
        }
    }

    /// 播放页触摸光效开关（默认关）：消费 TouchGlow62。
    static var touchGlowEnabled: Bool {
        get { boolB62(Key62B.touchGlowEnabled, default: false) }
        set { setBoolB62(newValue, Key62B.touchGlowEnabled) }
    }

    /// 触摸光效密度（0...1，默认 0.5）：决定并发光晕上限与
    /// 每晕粒子数（见 TouchGlow62）。
    static var touchGlowDensity: Double {
        get { min(max(double62(Key62B.touchGlowDensity, default: 0.5), 0), 1) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 1),
                                        forKey: Key62B.touchGlowDensity) }
    }

    /// 播放页原生毛玻璃背景开关（默认开 = 现状恒开行为）：
    /// 消费在 StageVC backdropBlur（WA 文件域），WA 读本访问器。
    static var stageBackdropBlurEnabled: Bool {
        get { boolB62(Key62B.stageBackdropBlurEnabled, default: true) }
        set { setBoolB62(newValue, Key62B.stageBackdropBlurEnabled) }
    }

    // MARK: - §4.5 播放控制

    /// 智能过渡总开关（默认关）：消费 PlaybackEngine 双轨。
    static var smartTransitionEnabled: Bool {
        get { boolB62(Key62B.smartTransitionEnabled, default: false) }
        set { setBoolB62(newValue, Key62B.smartTransitionEnabled) }
    }

    /// 过渡模式：crossfade（等功率音量斜坡）/ automix（按
    /// 下一首前奏提前量对齐，无能量数据时固定提前量近似）。
    static var transitionMode: String {
        get {
            let raw = stringB62(Key62B.transitionMode, default: "crossfade")
            return raw == "automix" ? "automix" : "crossfade"
        }
        set {
            UserDefaults.standard.set(newValue == "automix" ? "automix" : "crossfade",
                                      forKey: Key62B.transitionMode)
        }
    }

    /// 过渡最长时长（秒，1...12，默认 6）。
    static var transitionMaxDurationSec: Double {
        get { min(max(double62(Key62B.transitionMaxDurationSec, default: 6), 1), 12) }
        set { UserDefaults.standard.set(min(max(newValue, 1), 12),
                                        forKey: Key62B.transitionMaxDurationSec) }
    }

    /// 过渡表现模式（音量曲线）：equalPower（默认）/ linear /
    /// easeInOut。
    static var transitionCurve: String {
        get {
            let raw = stringB62(Key62B.transitionCurve, default: "equalPower")
            return ["equalPower", "linear", "easeInOut"].contains(raw) ? raw : "equalPower"
        }
        set {
            UserDefaults.standard.set(
                ["equalPower", "linear", "easeInOut"].contains(newValue) ? newValue : "equalPower",
                forKey: Key62B.transitionCurve)
        }
    }

    /// 过渡动画：none（默认）/ ring（屏幕圆环）/ cardStroke
    /// （卡片描边）。消费 TransitionAnim62（舞台顶层）。
    static var transitionAnimation: String {
        get {
            let raw = stringB62(Key62B.transitionAnimation, default: "none")
            return ["none", "ring", "cardStroke"].contains(raw) ? raw : "none"
        }
        set {
            UserDefaults.standard.set(
                ["none", "ring", "cardStroke"].contains(newValue) ? newValue : "none",
                forKey: Key62B.transitionAnimation)
        }
    }

    /// ReplayGain 开关（默认关）：消费 PlaybackEngine 音量链。
    static var replayGainEnabled: Bool {
        get { boolB62(Key62B.replayGainEnabled, default: false) }
        set { setBoolB62(newValue, Key62B.replayGainEnabled) }
    }

    /// 暂停/播放淡入淡出时长（毫秒，0...1000，默认 200）。
    static var playPauseFadeMs: Int {
        get { min(max(int62(Key62B.playPauseFadeMs, default: 200), 0), 1000) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 1000),
                                        forKey: Key62B.playPauseFadeMs) }
    }

    /// 自动转换无法播放的音频（默认关）：仅已落盘资产可走
    /// 本地转码（AVAssetExportSession → m4a）；流媒体不可播
    /// 仍走既有跳过逻辑（见 PlaybackEngine 转码通路注释）。
    static var autoTranscodeEnabled: Bool {
        get { boolB62(Key62B.autoTranscodeEnabled, default: false) }
        set { setBoolB62(newValue, Key62B.autoTranscodeEnabled) }
    }

    /// 播放时阻止休眠（默认关）：消费 PlaybackEngine 按播放
    /// 态写 UIApplication.isIdleTimerDisabled。
    static var preventSleepWhilePlaying: Bool {
        get { boolB62(Key62B.preventSleepWhilePlaying, default: false) }
        set { setBoolB62(newValue, Key62B.preventSleepWhilePlaying) }
    }

    /// 语音输入时暂停（默认关）：消费 PlaybackEngine 的音频
    /// 会话中断监听（Siri/语音输入中断到达即暂停且不自动恢复）。
    static var pauseOnVoiceInput: Bool {
        get { boolB62(Key62B.pauseOnVoiceInput, default: false) }
        set { setBoolB62(newValue, Key62B.pauseOnVoiceInput) }
    }

    // MARK: - §4.6 歌词

    /// 自动使用最佳歌词（默认开 = 现行写死链行为）：关时恒
    /// 走行级 LRC、不合并 YRC。策略见 bestLyricStrategy。
    static var autoBestLyricEnabled: Bool {
        get { boolB62(Key62B.autoBestLyricEnabled, default: true) }
        set { setBoolB62(newValue, Key62B.autoBestLyricEnabled) }
    }

    /// 最佳歌词策略：yrcFirst（默认，YRC 逐字优先）/
    /// lrcFirst（行级优先，丢逐字）/ durationMatch（按两表
    /// 末行时刻与曲目跨度接近度择优）。消费 LyricRepository。
    static var bestLyricStrategy: String {
        get {
            let raw = stringB62(Key62B.bestLyricStrategy, default: "yrcFirst")
            return ["yrcFirst", "lrcFirst", "durationMatch"].contains(raw) ? raw : "yrcFirst"
        }
        set {
            UserDefaults.standard.set(
                ["yrcFirst", "lrcFirst", "durationMatch"].contains(newValue) ? newValue : "yrcFirst",
                forKey: Key62B.bestLyricStrategy)
        }
    }

    /// 歌词匹配优先级（两级匹配的级序）：exactFirst（默认，
    /// 精确优先折叠兜底 = 现行行为）/ foldedFirst（折叠优先）/
    /// timeFirst（按行时刻最近优先）。消费 LyricParsing 合并。
    static var lyricMatchPriority: String {
        get {
            let raw = stringB62(Key62B.lyricMatchPriority, default: "exactFirst")
            return ["exactFirst", "foldedFirst", "timeFirst"].contains(raw) ? raw : "exactFirst"
        }
        set {
            UserDefaults.standard.set(
                ["exactFirst", "foldedFirst", "timeFirst"].contains(newValue) ? newValue : "exactFirst",
                forKey: Key62B.lyricMatchPriority)
        }
    }

    /// 保留平台自带的逐字歌词（默认开 = 现行恒用行为）：关
    /// 时合并后丢 words、退行级。消费 LyricRepository 出口与
    /// LyricParser.stageLines 出口双处同口径。
    static var keepPlatformWordLyrics: Bool {
        get { boolB62(Key62B.keepPlatformWordLyrics, default: true) }
        set { setBoolB62(newValue, Key62B.keepPlatformWordLyrics) }
    }

    /// 本地歌曲歌词优先级：platformFirst（默认）/ localFirst。
    /// 消费 LyricRepository 的 LocalLyricSource62 钩子查询序。
    static var localLyricPriority: String {
        get {
            let raw = stringB62(Key62B.localLyricPriority, default: "platformFirst")
            return raw == "localFirst" ? "localFirst" : "platformFirst"
        }
        set {
            UserDefaults.standard.set(newValue == "localFirst" ? "localFirst" : "platformFirst",
                                      forKey: Key62B.localLyricPriority)
        }
    }

    /// 本地歌词格式顺序（逗号分隔，如 "lrc,yrc,txt"，默认
    /// "lrc,yrc,txt"）：供 WC 的 LocalLyricSource62 实现按序
    /// 探本地歌词文件；钩子协议见 Lyric62Hooks。
    static var localLyricFormatOrder: String {
        get { stringB62(Key62B.localLyricFormatOrder, default: "lrc,yrc,txt") }
        set { UserDefaults.standard.set(newValue, forKey: Key62B.localLyricFormatOrder) }
    }

    /// 本地歌词格式顺序的解析面（去空白、去空项）。
    static var localLyricFormatOrderList: [String] {
        localLyricFormatOrder
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// 歌词过滤正则（默认空 = 不过滤）：LyricParser 出口按行
    /// 过滤命中行；保存时经 LyricFilter62.validate 校验，非法
    /// 正则不落盘（设置行报错）。
    static var lyricFilterRegex: String {
        get { stringB62(Key62B.lyricFilterRegex, default: "") }
        set { UserDefaults.standard.set(newValue, forKey: Key62B.lyricFilterRegex) }
    }

    /// 自动 AI 分词开关（默认关）：消费 LyricRepository——开
    /// 且端点已配置时对无戳行调 AISegment62；未配置端点时走
    /// 现有均分＋跨曲标定并如实落面包屑（不冒充 AI 分词）。
    static var aiSegmentEnabled: Bool {
        get { boolB62(Key62B.aiSegmentEnabled, default: false) }
        set { setBoolB62(newValue, Key62B.aiSegmentEnabled) }
    }

    /// AI 分词服务端点（默认空 = 未配置）。
    static var aiSegmentEndpoint: String {
        get { stringB62(Key62B.aiSegmentEndpoint, default: "") }
        set { UserDefaults.standard.set(newValue, forKey: Key62B.aiSegmentEndpoint) }
    }

    // MARK: - §4.7 通用

    /// 界面语言偏好：zh-Hans（默认）/ en。覆盖范围见
    /// FoliaLanguage62（设置页签标题等关键面文案字典），非
    /// 全量本地化（报告如实标注）。
    static var appLanguage: String {
        get {
            let raw = stringB62(Key62B.appLanguage, default: "zh-Hans")
            return raw == "en" ? "en" : "zh-Hans"
        }
        set {
            UserDefaults.standard.set(newValue == "en" ? "en" : "zh-Hans",
                                      forKey: Key62B.appLanguage)
        }
    }

    /// 启动后直接进入播放界面（默认关）：与入场口径的冲突
    /// 以「入场播完/关闭后直达」消解——消费在 HomeWall 入场
    /// 退场落点（WB62HomeWallHooks.entryDidFinish），无队列/
    /// 无装载时不直达。
    static var openPlayerOnLaunch: Bool {
        get { boolB62(Key62B.openPlayerOnLaunch, default: false) }
        set { setBoolB62(newValue, Key62B.openPlayerOnLaunch) }
    }

    /// 思索教程提示（默认开）：消费 Ponder62（首访功能面一
    /// 次性气泡，已读态落盘）。
    static var ponderTipsEnabled: Bool {
        get { boolB62(Key62B.ponderTipsEnabled, default: true) }
        set { setBoolB62(newValue, Key62B.ponderTipsEnabled) }
    }

    /// 触屏思索按钮（默认开）：墙面悬浮「?」钮，点开教程
    /// 提示列表面。消费 WB62HomeWallHooks 安装点。
    static var ponderTouchButtonEnabled: Bool {
        get { boolB62(Key62B.ponderTouchButtonEnabled, default: true) }
        set { setBoolB62(newValue, Key62B.ponderTouchButtonEnabled) }
    }

    /// 思索已读集合（Ponder62 落盘面）。
    static var ponderSeenIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: Key62B.ponderSeenIDs) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Key62B.ponderSeenIDs) }
    }

    // MARK: - §4.8 快捷操作

    /// 快捷命令固定槽位（命令 id 数组）：存取符号
    /// PinnedCommands62（WC 的 CommandPalette 消费置顶区）。
    static var pinnedCommandIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: Key62B.pinnedCommandIDs) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Key62B.pinnedCommandIDs) }
    }

    /// 手势快捷总开关（默认开）：iOS 无键盘场景的等价实现
    /// （可绑定手势动作表，见设置行与 WB62HomeWallHooks）。
    static var gestureShortcutsEnabled: Bool {
        get { boolB62(Key62B.gestureShortcutsEnabled, default: true) }
        set { setBoolB62(newValue, Key62B.gestureShortcutsEnabled) }
    }

    /// 长按工具条打开命令面板（默认开）：§4.8 自定义快捷键
    /// 的至少一条真消费——消费在 WB62HomeWallHooks 给工具条
    /// 宿主视图挂的长按手势（经宿主既有命令面板入口）。
    static var longPressToolbarCommandPalette: Bool {
        get { boolB62(Key62B.longPressToolbarCommandPalette, default: true) }
        set { setBoolB62(newValue, Key62B.longPressToolbarCommandPalette) }
    }

    /// 向左滑动打开的目标：commandPalette（默认）/
    /// sketchbook / search / none。消费 WB62HomeWallHooks 的
    /// 墙面左滑手势。
    static var swipeLeftTarget: String {
        get {
            let raw = stringB62(Key62B.swipeLeftTarget, default: "commandPalette")
            return ["commandPalette", "sketchbook", "search", "none"].contains(raw)
                ? raw : "commandPalette"
        }
        set {
            UserDefaults.standard.set(
                ["commandPalette", "sketchbook", "search", "none"].contains(newValue)
                    ? newValue : "commandPalette",
                forKey: Key62B.swipeLeftTarget)
        }
    }

    /// 海报墙 S 键打开命令窗口（默认开）：外接键盘
    /// UIKeyCommand 消费在 HomeWall/WallPrototype 的
    /// keyCommands hunk（WB 簇小改，见报告）。
    static var posterWallSHotkeyEnabled: Bool {
        get { boolB62(Key62B.posterWallSHotkeyEnabled, default: true) }
        set { setBoolB62(newValue, Key62B.posterWallSHotkeyEnabled) }
    }

    // MARK: - §4.9 WB 两项（连接与集成）

    /// 自定义歌词 API 基址（默认空 = 走自有 EdgeOne 代理）：
    /// 非空时 LyricRepository 先试该基址的 /lyric 兼容端点，
    /// 失败回落 EdgeOne 并落面包屑。
    static var lyricAPIBaseURL: String {
        get { stringB62(Key62B.lyricAPIBaseURL, default: "") }
        set { UserDefaults.standard.set(newValue, forKey: Key62B.lyricAPIBaseURL) }
    }

    /// 舞台模式（外部舞台数据源总开关，默认关）：消费
    /// StageDataSource62 轮询客户端。
    static var stageModeEnabled: Bool {
        get { boolB62(Key62B.stageModeEnabled, default: false) }
        set { setBoolB62(newValue, Key62B.stageModeEnabled) }
    }

    /// 舞台数据来源 URL（默认空）：StageDataSource62 按此
    /// 地址轮询 {title, artist, progress} JSON 映射到舞台信
    /// 息卡数据源（协议假设见 StageDataSource62 头注）。
    static var stageDataSourceURL: String {
        get { stringB62(Key62B.stageDataSourceURL, default: "") }
        set { UserDefaults.standard.set(newValue, forKey: Key62B.stageDataSourceURL) }
    }
}
