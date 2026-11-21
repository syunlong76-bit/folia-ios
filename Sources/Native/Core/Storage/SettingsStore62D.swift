import Foundation

// 3.7 (62) WD 簇设置键（契约：extension SettingsStore + Key62D +
// 计算属性访问器；extension 内不许 stored static，故全部走
// UserDefaults 直读直写，缺省以 object 存在性判定，不依赖主文件
// 的私有 ensureRegistered）。
//
// 本文件只登记 WD 簇自有键：
//  - 每首歌随机歌词动画（§6，消费在 RandomStylePerSong62）
//  - 舞台背景体系模式（§6 背景，消费在 StageBackdrop62）
//  - 搜索来源范围（§3，消费在 SearchWorkspaceView）
// WA 的墙面键（wallTransparency 等）与 WB 的降低动态键不在此重复。

extension SettingsStore {

    enum Key62D {
        static let randomPerSongEnabled = "settings.stage.randomPerSongEnabled"
        static let backdropMode = "settings.stage.backdropMode"
        static let backdropRemoteURL = "settings.stage.backdropRemoteURL"
        static let searchProviderQQEnabled = "settings.search.providerQQEnabled"
        static let searchProviderKugouEnabled = "settings.search.providerKugouEnabled"
    }

    // MARK: - §6 每首歌随机歌词动画

    /// 切歌自动随机样式（默认关）：开时 RandomStylePerSong62 在
    /// 切歌边沿从 StageStyleCycleBag 洗牌袋取下一式写入
    /// StageStyleStore.currentStyleId（与三击轮换同袋同通路）。
    static var randomPerSongEnabled62: Bool {
        get { UserDefaults.standard.bool(forKey: Key62D.randomPerSongEnabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: Key62D.randomPerSongEnabled)
            Breadcrumbs.log("settings62d.randomPerSong on=\(newValue ? 1 : 0)")
        }
    }

    // MARK: - §6 舞台背景体系

    /// 背景模式 raw 值：none（样式自带）/ common / latentCover /
    /// latentLyric / latentSpectrum / monet / nomand / sora / url。
    /// 自定义背景（(47) 单槽）与本模式互斥：CustomBackgroundStore
    /// 有槽位时选择器与 StageBackdrop62 都以自定义背景优先，本值
    /// 保留待清除自定义背景后恢复。
    static var backdropMode62: String {
        get {
            let raw = UserDefaults.standard.string(forKey: Key62D.backdropMode) ?? "none"
            let valid = ["none", "common", "latentCover", "latentLyric",
                         "latentSpectrum", "monet", "nomand", "sora", "url"]
            return valid.contains(raw) ? raw : "none"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key62D.backdropMode)
            Breadcrumbs.log("settings62d.backdropMode mode=\(newValue)")
        }
    }

    /// url 背景模式的远程图地址（D13 口径：下载本地缓存后作背景，
    /// 禁 WebView；消费在 StageBackdrop62）。
    static var backdropRemoteURL62: String {
        get { UserDefaults.standard.string(forKey: Key62D.backdropRemoteURL) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Key62D.backdropRemoteURL) }
    }

    // MARK: - §3 搜索来源范围（网易云恒开，另两家可勾选聚合）

    /// QQ 来源（默认关；后端 search 现回 400/D5，开启后真发请求、
    /// 失败诚实空态，见 SearchWorkspaceView）。
    static var searchProviderQQEnabled62: Bool {
        // 缺省开（未写过键 = 参与聚合，用户可在搜索页关掉）。
        get { UserDefaults.standard.object(forKey: Key62D.searchProviderQQEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key62D.searchProviderQQEnabled) }
    }

    /// 酷狗来源（默认关；形状经 searchRaw 宽松解析，能通则接）。
    static var searchProviderKugouEnabled62: Bool {
        get { UserDefaults.standard.object(forKey: Key62D.searchProviderKugouEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key62D.searchProviderKugouEnabled) }
    }
}
