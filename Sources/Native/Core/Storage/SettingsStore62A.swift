import Foundation

/// 3.7 (62) WA 簇设置存储：外观（主题/明暗/场景/声线）、播放页、
/// 主页与歌单三组的新键与类型化访问器。
///
/// 契约（四簇共同）：键名 `settings.<group>.<key>`；本文件只用
/// 计算属性读写 UserDefaults.standard（extension 内不写 stored
/// static）；默认值在 getter 内兜底（object(forKey:) == nil 时回
/// 缺省），不走 register(defaults:)——避免与基座 SettingsStore
/// 的注册表互相覆盖。钳制在读写两侧都做。
extension SettingsStore {

    enum Key62A {
        // 外观·主题
        static var themePresetId: String { "settings.appearance.themePresetId" }
        static var themeCustomAccentHex: String { "settings.appearance.themeCustomAccentHex" }
        static var themeCustomSecondaryHex: String { "settings.appearance.themeCustomSecondaryHex" }
        static var themeCustomBackgroundHex: String { "settings.appearance.themeCustomBackgroundHex" }
        static var songThemeAutoSwitch: String { "settings.appearance.songThemeAutoSwitch" }
        static var songThemeAutoGenerate: String { "settings.appearance.songThemeAutoGenerate" }
        static var themeSource: String { "settings.appearance.themeSource" }
        static var preferCustomTheme: String { "settings.appearance.preferCustomTheme" }
        // 外观·明暗/场景/声线
        static var daylightMode: String { "settings.appearance.daylightMode" }
        static var scenePreset: String { "settings.appearance.scenePreset" }
        static var soundTracingEnabled: String { "settings.appearance.soundTracingEnabled" }
        // 播放页·进入视图
        static var playbackEntryView: String { "settings.player.playbackEntryView" }
        // 播放页·Lattice
        static var latticeVignetteEnabled: String { "settings.player.latticeVignetteEnabled" }
        static var latticeVignetteStrength: String { "settings.player.latticeVignetteStrength" }
        static var latticePosterTintEnabled: String { "settings.player.latticePosterTintEnabled" }
        static var latticePosterTintForceCustom: String { "settings.player.latticePosterTintForceCustom" }
        static var latticePosterTintColorHex: String { "settings.player.latticePosterTintColorHex" }
        static var latticePosterTintStrength: String { "settings.player.latticePosterTintStrength" }
        static var latticeBadgeCurrentOnly: String { "settings.player.latticeBadgeCurrentOnly" }
        // 播放页·控制栏/底栏
        static var headerAutoHideEnabled: String { "settings.player.headerAutoHideEnabled" }
        // (68) B 组出样：舞台全宽控制条开关
        static var wideBar68Enabled: String { "settings.player.wideBar68Enabled" }
        static var bottomBarHeight: String { "settings.player.bottomBarHeight" }
        static var barSlots62: String { "settings.player.barSlots62" }
        static var hideBottomBar: String { "settings.player.hideBottomBar" }
        static var hideRightButtons: String { "settings.player.hideRightButtons" }
        static var alwaysShowBackButton: String { "settings.player.alwaysShowBackButton" }
        static var alwaysShowSkipButtons: String { "settings.player.alwaysShowSkipButtons" }
        static var headerBlurEnabled: String { "settings.player.headerBlurEnabled" }
        static var showPanelCloseButton: String { "settings.player.showPanelCloseButton" }
        // 播放页·舞台歌曲卡 TrackPill
        static var trackPillDisplayMode: String { "settings.player.trackPillDisplayMode" }
        static var trackPillDurationSeconds: String { "settings.player.trackPillDurationSeconds" }
        static var trackPillPosition: String { "settings.player.trackPillPosition" }
        static var trackPillShowOnHome: String { "settings.player.trackPillShowOnHome" }
        static var trackPillOBSEnabled: String { "settings.player.trackPillOBSEnabled" }
        // (66) 进度条右侧两槽指派（网页「两槽 × 功能指派」的原生落点）
        static var barSlotLeft62: String { "settings.player.barSlotLeft62" }
        static var barSlotRight62: String { "settings.player.barSlotRight62" }
        // (66) 逐场景调参覆盖（JSON：sceneId → [暗角, 氛围, 氛围tint]）
        static var sceneOverrides62: String { "settings.appearance.sceneOverrides62" }
        // (66) 歌单卡片样式：card 拍立得（默认）/ image 纯图片封面
        static var playlistCardStyle62: String { "settings.home.playlistCardStyle62" }
        // (66) 主页卡片位置记忆的几何面：墙相机原点 "x,y"
        // （网格滚动偏移复用既有 wallScrollOriginY 键）
        static var wallCamera62: String { "settings.home.wallCamera62" }
        // 播放页·视频层
        static var videoLayerEnabled: String { "settings.player.videoLayerEnabled" }
        static var videoLayerURL: String { "settings.player.videoLayerURL" }
        static var videoLayerOpacity: String { "settings.player.videoLayerOpacity" }
        static var videoLayerFillMode: String { "settings.player.videoLayerFillMode" }
        // 主页与歌单·资料库/胶囊入口
        static var librarySuiteChoice: String { "settings.home.librarySuiteChoice" }
        static var homeTabsEnabled: String { "settings.home.homeTabsEnabled" }
        static var showHomeTabPlaylists: String { "settings.home.showHomeTabPlaylists" }
        static var showHomeTabRecommend: String { "settings.home.showHomeTabRecommend" }
        static var showHomeTabExplore: String { "settings.home.showHomeTabExplore" }
        static var showHomeTabAlbums: String { "settings.home.showHomeTabAlbums" }
        static var showHomeTabLocal: String { "settings.home.showHomeTabLocal" }
        // 主页与歌单·网格卡片
        static var grid3DCardStyle: String { "settings.home.grid3DCardStyle" }
        static var gridFullBleedCover: String { "settings.home.gridFullBleedCover" }
        static var gridSquareCards: String { "settings.home.gridSquareCards" }
        static var gridCardMinSize: String { "settings.home.gridCardMinSize" }
        static var gridCardMinOpacity: String { "settings.home.gridCardMinOpacity" }
        // 主页与歌单·卡片位置记忆
        static var rememberCardPositions: String { "settings.home.rememberCardPositions" }
        static var wallCardOrder: String { "settings.home.wallCardOrder" }
        static var wallScrollOriginY: String { "settings.home.wallScrollOriginY" }
        // 主页与歌单·墙面组（访问器名任务定死，供 WD 簇消费）
        static var wallTransparency: String { "settings.wall.transparency" }
        static var wallWindowsPerPane: String { "settings.wall.windowsPerPane" }
        static var stackEdgesEnabled: String { "settings.wall.stackEdgesEnabled" }
        static var stripDirection: String { "settings.wall.stripDirection" }
        static var stripAlwaysTransparent: String { "settings.wall.stripAlwaysTransparent" }
        static var stripStyle: String { "settings.wall.stripStyle" }
        static var backdropLyricsEnabled: String { "settings.wall.backdropLyricsEnabled" }
        static var backdropBlurAmount: String { "settings.wall.backdropBlurAmount" }
    }

    // MARK: - 读写原语（计算属性口径：nil → 缺省）

    private static func bool62(_ key: String, default def: Bool) -> Bool {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil ? def : d.bool(forKey: key)
    }
    private static func setBool62(_ v: Bool, _ key: String) {
        UserDefaults.standard.set(v, forKey: key)
    }
    private static func int62(_ key: String, default def: Int, range: ClosedRange<Int>) -> Int {
        let d = UserDefaults.standard
        let raw = d.object(forKey: key) == nil ? def : d.integer(forKey: key)
        return min(max(raw, range.lowerBound), range.upperBound)
    }
    private static func setInt62(_ v: Int, _ key: String, range: ClosedRange<Int>) {
        UserDefaults.standard.set(min(max(v, range.lowerBound), range.upperBound), forKey: key)
    }
    private static func double62(_ key: String, default def: Double, range: ClosedRange<Double>) -> Double {
        let d = UserDefaults.standard
        let raw = d.object(forKey: key) == nil ? def : d.double(forKey: key)
        return min(max(raw, range.lowerBound), range.upperBound)
    }
    private static func setDouble62(_ v: Double, _ key: String, range: ClosedRange<Double>) {
        UserDefaults.standard.set(min(max(v, range.lowerBound), range.upperBound), forKey: key)
    }
    private static func string62(_ key: String, default def: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? def
    }

    // MARK: - 外观·主题系统（消费：ThemeSystem62）

    /// 配色主题预设 id（内置预设见 ThemePreset62.all；"custom" 为用户自选三色）。
    static var themePresetId: String {
        get { string62(Key62A.themePresetId, default: "midnight") }
        set { UserDefaults.standard.set(newValue, forKey: Key62A.themePresetId) }
    }
    static var themeCustomAccentHex: String {
        get { string62(Key62A.themeCustomAccentHex, default: "#8B7CF0") }
        set { UserDefaults.standard.set(newValue, forKey: Key62A.themeCustomAccentHex) }
    }
    static var themeCustomSecondaryHex: String {
        get { string62(Key62A.themeCustomSecondaryHex, default: "#5EC8D8") }
        set { UserDefaults.standard.set(newValue, forKey: Key62A.themeCustomSecondaryHex) }
    }
    static var themeCustomBackgroundHex: String {
        get { string62(Key62A.themeCustomBackgroundHex, default: "#16161A") }
        set { UserDefaults.standard.set(newValue, forKey: Key62A.themeCustomBackgroundHex) }
    }
    /// 歌曲主题自动切换：切歌时当前主题跟随封面主色（默认开）。
    static var songThemeAutoSwitch: Bool {
        get { bool62(Key62A.songThemeAutoSwitch, default: true) }
        set { setBool62(newValue, Key62A.songThemeAutoSwitch) }
    }
    /// 自动生成歌曲主题：允许按封面主色生成当前主题（默认开；关时切歌不生成）。
    static var songThemeAutoGenerate: Bool {
        get { bool62(Key62A.songThemeAutoGenerate, default: true) }
        set { setBool62(newValue, Key62A.songThemeAutoGenerate) }
    }
    /// 主题生成来源：0 封面 / 1 专辑 / 2 艺术家。
    static var themeSource: Int {
        get { int62(Key62A.themeSource, default: 0, range: 0...2) }
        set { setInt62(newValue, Key62A.themeSource, range: 0...2) }
    }
    /// 优先使用自定义主题：开时自定义/预设主题压过自动生成（默认关）。
    static var preferCustomTheme: Bool {
        get { bool62(Key62A.preferCustomTheme, default: false) }
        set { setBool62(newValue, Key62A.preferCustomTheme) }
    }

    // MARK: - 外观·明暗/场景/声线

    /// 明暗模式：0 跟随系统 / 1 恒深色（默认，沿现状）/ 2 恒浅色。
    static var daylightMode: Int {
        get { int62(Key62A.daylightMode, default: 1, range: 0...2) }
        set { setInt62(newValue, Key62A.daylightMode, range: 0...2) }
    }
    /// 场景预设：0 无 / 1 影厅 / 2 现场 / 3 书房（消费：SceneSystem62 → StageVC 氛围层）。
    static var scenePreset: Int {
        get { int62(Key62A.scenePreset, default: 0, range: 0...3) }
        set { setInt62(newValue, Key62A.scenePreset, range: 0...3) }
    }
    /// 声线追踪：舞台显示声线/电平轨迹线（默认关；无真实频谱数据源时画诚实基线）。
    static var soundTracingEnabled: Bool {
        get { bool62(Key62A.soundTracingEnabled, default: false) }
        set { setBool62(newValue, Key62A.soundTracingEnabled) }
    }

    // MARK: - 播放页

    /// 播放后进入的视图：0 舞台（默认，现行为）/ 1 播放详情 / 2 留在当前页。
    static var playbackEntryView: Int {
        get { int62(Key62A.playbackEntryView, default: 0, range: 0...2) }
        set { setInt62(newValue, Key62A.playbackEntryView, range: 0...2) }
    }
    static var latticeVignetteEnabled: Bool {
        get { bool62(Key62A.latticeVignetteEnabled, default: true) }
        set { setBool62(newValue, Key62A.latticeVignetteEnabled) }
    }
    static var latticeVignetteStrength: Double {
        get { double62(Key62A.latticeVignetteStrength, default: 0.6, range: 0...1) }
        set { setDouble62(newValue, Key62A.latticeVignetteStrength, range: 0...1) }
    }
    static var latticePosterTintEnabled: Bool {
        get { bool62(Key62A.latticePosterTintEnabled, default: false) }
        set { setBool62(newValue, Key62A.latticePosterTintEnabled) }
    }
    static var latticePosterTintForceCustom: Bool {
        get { bool62(Key62A.latticePosterTintForceCustom, default: false) }
        set { setBool62(newValue, Key62A.latticePosterTintForceCustom) }
    }
    static var latticePosterTintColorHex: String {
        get { string62(Key62A.latticePosterTintColorHex, default: "#8B7CF0") }
        set { UserDefaults.standard.set(newValue, forKey: Key62A.latticePosterTintColorHex) }
    }
    static var latticePosterTintStrength: Double {
        get { double62(Key62A.latticePosterTintStrength, default: 0.35, range: 0...1) }
        set { setDouble62(newValue, Key62A.latticePosterTintStrength, range: 0...1) }
    }
    static var latticeBadgeCurrentOnly: Bool {
        get { bool62(Key62A.latticeBadgeCurrentOnly, default: false) }
        set { setBool62(newValue, Key62A.latticeBadgeCurrentOnly) }
    }
    /// 顶栏自动隐藏（默认开，现行为）；关时顶栏常显。范围仅顶栏（底部台另有 5 秒收起机制）。
    static var headerAutoHideEnabled: Bool {
        get { bool62(Key62A.headerAutoHideEnabled, default: true) }
        set { setBool62(newValue, Key62A.headerAutoHideEnabled) }
    }
    /// (68) B 组出样：舞台全宽控制条（默认关）。开时舞台点屏
    /// 唤出全宽条（进度＋播放控制一行）、闲置 5 秒自隐；关时
    /// 舞台行为与现行逐项一致。消费面只有 StageWideBar68 与
    /// StageVC 的装配钩子，出样可整体摘除，不迁移现行控制。
    static var wideBar68Enabled: Bool {
        get { bool62(Key62A.wideBar68Enabled, default: false) }
        set { setBool62(newValue, Key62A.wideBar68Enabled) }
    }
    /// 底部组件高度（pt，48...110，默认 70＝现行展开台高）：StageVC 消费；
    /// MiniPlayerView（WD 簇）按同键消费。键名任务定死。
    static var bottomBarHeight: Double {
        get { double62(Key62A.bottomBarHeight, default: 70, range: 48...110) }
        set { setDouble62(newValue, Key62A.bottomBarHeight, range: 48...110) }
    }
    /// 进度条右侧按钮槽位（62 扩展集）：逗号分隔的槽位 id 有序集，
    /// 候选 prev/next/queue/like/mode/sleep；默认 "prev,next,queue"（现行三键）。
    /// StageVC 侧消费；MiniPlayerView 侧由 WD 按同键消费。
    static var barSlots62: [String] {
        get {
            let raw = string62(Key62A.barSlots62, default: "prev,next,queue")
            let allowed: Set<String> = ["prev", "next", "queue", "like", "mode", "sleep"]
            let parsed = raw.split(separator: ",").map(String.init).filter { allowed.contains($0) }
            return parsed.isEmpty ? ["prev", "next", "queue"] : parsed
        }
        set {
            let allowed: Set<String> = ["prev", "next", "queue", "like", "mode", "sleep"]
            let cleaned = newValue.filter { allowed.contains($0) }
            UserDefaults.standard.set(cleaned.joined(separator: ","), forKey: Key62A.barSlots62)
        }
    }
    static var hideBottomBar: Bool {
        get { bool62(Key62A.hideBottomBar, default: false) }
        set { setBool62(newValue, Key62A.hideBottomBar) }
    }
    static var hideRightButtons: Bool {
        get { bool62(Key62A.hideRightButtons, default: false) }
        set { setBool62(newValue, Key62A.hideRightButtons) }
    }
    static var alwaysShowBackButton: Bool {
        get { bool62(Key62A.alwaysShowBackButton, default: false) }
        set { setBool62(newValue, Key62A.alwaysShowBackButton) }
    }
    static var alwaysShowSkipButtons: Bool {
        get { bool62(Key62A.alwaysShowSkipButtons, default: false) }
        set { setBool62(newValue, Key62A.alwaysShowSkipButtons) }
    }
    static var headerBlurEnabled: Bool {
        get { bool62(Key62A.headerBlurEnabled, default: false) }
        set { setBool62(newValue, Key62A.headerBlurEnabled) }
    }
    /// 显示信息卡片关闭按钮（键名任务定死）：PlaybackPanel（WC 簇文件）消费。
    static var showPanelCloseButton: Bool {
        get { bool62(Key62A.showPanelCloseButton, default: true) }
        set { setBool62(newValue, Key62A.showPanelCloseButton) }
    }
    /// 舞台歌曲卡显示方式：0 切歌时显（默认）/ 1 常显 / 2 关。
    static var trackPillDisplayMode: Int {
        get { int62(Key62A.trackPillDisplayMode, default: 0, range: 0...2) }
        set { setInt62(newValue, Key62A.trackPillDisplayMode, range: 0...2) }
    }
    static var trackPillDurationSeconds: Double {
        get { double62(Key62A.trackPillDurationSeconds, default: 4, range: 1...15) }
        set { setDouble62(newValue, Key62A.trackPillDurationSeconds, range: 1...15) }
    }
    /// 舞台歌曲卡位置：0 左上（默认）/ 1 右上 / 2 左下 / 3 右下。
    static var trackPillPosition: Int {
        get { int62(Key62A.trackPillPosition, default: 0, range: 0...3) }
        set { setInt62(newValue, Key62A.trackPillPosition, range: 0...3) }
    }
    static var trackPillShowOnHome: Bool {
        get { bool62(Key62A.trackPillShowOnHome, default: false) }
        set { setBool62(newValue, Key62A.trackPillShowOnHome) }
    }
    /// 舞台歌曲卡在 OBS 浏览器源启用：(66) 做真——消费在
    /// LocalServer /obs 页（开启时页面加渲染歌曲卡区块）。
    static var trackPillOBSEnabled: Bool {
        get { bool62(Key62A.trackPillOBSEnabled, default: false) }
        set { setBool62(newValue, Key62A.trackPillOBSEnabled) }
    }
    /// (66) 进度条右侧两槽可指派功能集（原生现有功能面）。
    static let barSlotFunctions62 = ["none", "prev", "next", "queue", "like", "mode", "sleep"]
    /// (66) 左槽指派（默认 mode，对齐网页左槽默认循环模式）。
    static var barSlotLeft62: String {
        get {
            let raw = string62(Key62A.barSlotLeft62, default: "mode")
            return barSlotFunctions62.contains(raw) ? raw : "mode"
        }
        set {
            UserDefaults.standard.set(
                barSlotFunctions62.contains(newValue) ? newValue : "mode",
                forKey: Key62A.barSlotLeft62)
        }
    }
    /// (66) 右槽指派（默认 queue；网页右槽默认歌词时间轴，
    /// 原生无此功能面，取最接近的队列入口，见交付报告）。
    static var barSlotRight62: String {
        get {
            let raw = string62(Key62A.barSlotRight62, default: "queue")
            return barSlotFunctions62.contains(raw) ? raw : "queue"
        }
        set {
            UserDefaults.standard.set(
                barSlotFunctions62.contains(newValue) ? newValue : "queue",
                forKey: Key62A.barSlotRight62)
        }
    }
    /// (66) 逐场景调参覆盖：[sceneId: [暗角, 氛围alpha, tint alpha]]，
    /// sceneId = "1" 影厅 / "2" 现场 / "3" 书房；SceneSystem62 消费，
    /// 无覆盖时用注册表内置参数。
    static var sceneOverrides62: [String: [Double]] {
        get {
            let raw = string62(Key62A.sceneOverrides62, default: "")
            guard let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let text = String(data: data, encoding: .utf8) else { return }
            UserDefaults.standard.set(text, forKey: Key62A.sceneOverrides62)
        }
    }
    /// (66) 歌单卡片样式：card（拍立得卡片，默认）/ image（纯图片封面）。
    /// 消费：CollectionView 拍立得网格（image 时去白框与标题条、纯封面）。
    static var playlistCardStyle62: String {
        get {
            let raw = string62(Key62A.playlistCardStyle62, default: "card")
            return raw == "image" ? "image" : "card"
        }
        set {
            UserDefaults.standard.set(newValue == "image" ? "image" : "card",
                                      forKey: Key62A.playlistCardStyle62)
        }
    }
    /// (66) 墙相机原点记忆（worldOrigin，rememberCardPositions 的几何面）。
    static var wallCamera62: CGPoint? {
        get {
            let raw = string62(Key62A.wallCamera62, default: "")
            let parts = raw.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else { return nil }
            return CGPoint(x: parts[0], y: parts[1])
        }
        set {
            if let point = newValue {
                UserDefaults.standard.set("\(point.x),\(point.y)", forKey: Key62A.wallCamera62)
            } else {
                UserDefaults.standard.removeObject(forKey: Key62A.wallCamera62)
            }
        }
    }
    /// (66) 网格滚动偏移记忆走既有 wallScrollOriginY 键
    /// （HomeWall 网格 contentOffset.y 的落盘面）。
    /// 视频层（歌词后方）独立开关：独立于 (47) 自定义背景槽的启用语义。
    static var videoLayerEnabled: Bool {
        get { bool62(Key62A.videoLayerEnabled, default: false) }
        set { setBool62(newValue, Key62A.videoLayerEnabled) }
    }
    static var videoLayerURL: String {
        get { string62(Key62A.videoLayerURL, default: "") }
        set { UserDefaults.standard.set(newValue, forKey: Key62A.videoLayerURL) }
    }
    static var videoLayerOpacity: Double {
        get { double62(Key62A.videoLayerOpacity, default: 0.85, range: 0.1...1) }
        set { setDouble62(newValue, Key62A.videoLayerOpacity, range: 0.1...1) }
    }
    /// 视频层填充方式：0 fill（默认）/ 1 fit。
    static var videoLayerFillMode: Int {
        get { int62(Key62A.videoLayerFillMode, default: 0, range: 0...1) }
        set { setInt62(newValue, Key62A.videoLayerFillMode, range: 0...1) }
    }

    // MARK: - 主页与歌单

    /// 资料库界面：0 Bravais 墙（默认）/ 1 网格。与工具条布局钮同状态源：
    /// 旧键 folia.wall.gridMode 为既有读者（HomeWall seamGridMode 初值）的
    /// 落盘面——新键未落盘时读旧键，写时双写，保证改一处另一处跟随。
    static var librarySuiteChoice: Int {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: Key62A.librarySuiteChoice) != nil {
                return int62(Key62A.librarySuiteChoice, default: 0, range: 0...1)
            }
            return d.bool(forKey: "folia.wall.gridMode") ? 1 : 0
        }
        set {
            setInt62(newValue, Key62A.librarySuiteChoice, range: 0...1)
            UserDefaults.standard.set(newValue == 1, forKey: "folia.wall.gridMode")
        }
    }
    static var homeTabsEnabled: Bool {
        get { bool62(Key62A.homeTabsEnabled, default: true) }
        set { setBool62(newValue, Key62A.homeTabsEnabled) }
    }
    static var showHomeTabPlaylists: Bool {
        get { bool62(Key62A.showHomeTabPlaylists, default: true) }
        set { setBool62(newValue, Key62A.showHomeTabPlaylists) }
    }
    static var showHomeTabRecommend: Bool {
        get { bool62(Key62A.showHomeTabRecommend, default: true) }
        set { setBool62(newValue, Key62A.showHomeTabRecommend) }
    }
    static var showHomeTabExplore: Bool {
        get { bool62(Key62A.showHomeTabExplore, default: true) }
        set { setBool62(newValue, Key62A.showHomeTabExplore) }
    }
    static var showHomeTabAlbums: Bool {
        get { bool62(Key62A.showHomeTabAlbums, default: true) }
        set { setBool62(newValue, Key62A.showHomeTabAlbums) }
    }
    static var showHomeTabLocal: Bool {
        get { bool62(Key62A.showHomeTabLocal, default: true) }
        set { setBool62(newValue, Key62A.showHomeTabLocal) }
    }
    static var grid3DCardStyle: Bool {
        get { bool62(Key62A.grid3DCardStyle, default: false) }
        set { setBool62(newValue, Key62A.grid3DCardStyle) }
    }
    static var gridFullBleedCover: Bool {
        get { bool62(Key62A.gridFullBleedCover, default: false) }
        set { setBool62(newValue, Key62A.gridFullBleedCover) }
    }
    static var gridSquareCards: Bool {
        get { bool62(Key62A.gridSquareCards, default: true) }
        set { setBool62(newValue, Key62A.gridSquareCards) }
    }
    static var gridCardMinSize: Double {
        get { double62(Key62A.gridCardMinSize, default: 96, range: 60...180) }
        set { setDouble62(newValue, Key62A.gridCardMinSize, range: 60...180) }
    }
    static var gridCardMinOpacity: Double {
        get { double62(Key62A.gridCardMinOpacity, default: 1, range: 0.3...1) }
        set { setDouble62(newValue, Key62A.gridCardMinOpacity, range: 0.3...1) }
    }
    static var rememberCardPositions: Bool {
        get { bool62(Key62A.rememberCardPositions, default: false) }
        set { setBool62(newValue, Key62A.rememberCardPositions) }
    }
    /// 卡片顺序记忆（逗号分隔 entry id 序）：rememberCardPositions 的落盘面。
    static var wallCardOrder: [String] {
        get {
            let raw = string62(Key62A.wallCardOrder, default: "")
            return raw.isEmpty ? [] : raw.split(separator: ",").map(String.init)
        }
        set { UserDefaults.standard.set(newValue.joined(separator: ","), forKey: Key62A.wallCardOrder) }
    }
    static var wallScrollOriginY: Double {
        get { double62(Key62A.wallScrollOriginY, default: 0, range: 0...1_000_000) }
        set { setDouble62(newValue, Key62A.wallScrollOriginY, range: 0...1_000_000) }
    }

    // MARK: - 墙面组（访问器名任务定死，供 WD 簇消费；本体在 WD）

    /// 墙面透光：0 不透光（默认）...1 全透。
    static var wallTransparency: Double {
        get { double62(Key62A.wallTransparency, default: 0, range: 0...1) }
        set { setDouble62(newValue, Key62A.wallTransparency, range: 0...1) }
    }
    /// 每块窗数：1...12，默认 4。
    static var wallWindowsPerPane: Int {
        get { int62(Key62A.wallWindowsPerPane, default: 4, range: 1...12) }
        set { setInt62(newValue, Key62A.wallWindowsPerPane, range: 1...12) }
    }
    static var stackEdgesEnabled: Bool {
        get { bool62(Key62A.stackEdgesEnabled, default: true) }
        set { setBool62(newValue, Key62A.stackEdgesEnabled) }
    }
    /// 信息条方向：0 横 / 1 纵。
    static var stripDirection: Int {
        get { int62(Key62A.stripDirection, default: 0, range: 0...1) }
        set { setInt62(newValue, Key62A.stripDirection, range: 0...1) }
    }
    static var stripAlwaysTransparent: Bool {
        get { bool62(Key62A.stripAlwaysTransparent, default: false) }
        set { setBool62(newValue, Key62A.stripAlwaysTransparent) }
    }
    /// 信息条样式：0...3，默认 0。
    static var stripStyle: Int {
        get { int62(Key62A.stripStyle, default: 0, range: 0...3) }
        set { setInt62(newValue, Key62A.stripStyle, range: 0...3) }
    }
    static var backdropLyricsEnabled: Bool {
        get { bool62(Key62A.backdropLyricsEnabled, default: false) }
        set { setBool62(newValue, Key62A.backdropLyricsEnabled) }
    }
    /// 墙后画面模糊量：0...30，默认 12。
    static var backdropBlurAmount: Double {
        get { double62(Key62A.backdropBlurAmount, default: 12, range: 0...30) }
        set { setDouble62(newValue, Key62A.backdropBlurAmount, range: 0...30) }
    }
}

extension Notification.Name {
    /// (62) WA 簇设置变更总线：设置行写盘后发，消费面（StageVC/HomeWall/
    /// SceneDelegate 根）订阅后重读 SettingsStore62A。userInfo["key"] 为键名。
    static let foliaSettings62AChanged = Notification.Name("foliaSettings62AChanged")
}
