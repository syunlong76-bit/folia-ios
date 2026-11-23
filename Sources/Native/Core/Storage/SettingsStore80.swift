import Foundation

// 3.7 (80) 设置键（契约同 SettingsStore62D：extension
// SettingsStore + Key80 + 计算属性访问器，UserDefaults 直读
// 直写，缺省以 object 存在性判定）。
//
// 本文件只登记 (80) 自有键：
//  - 逐歌记忆特效总开关（第 3 项，消费在 SongStyleMemory80
//    与 StageViewController 的记录/套用钩子）。

extension SettingsStore {

    enum Key80 {
        static let songStyleMemoryEnabled = "settings.stage.songStyleMemoryEnabled"
    }

    enum Key81 {
        static let directorEnabled = "settings.stage.directorEnabled81"
        static let directorEndpoint = "settings.stage.directorEndpoint81"
        static let directorModel = "settings.stage.directorModel81"
    }

    // MARK: - (81) AI 歌词导演（双模式）

    /// 导演总开关（默认开）：开时 (80) 预备管线为下一首
    /// 提前判定配式并写入逐歌记忆（来源 director）；关时
    /// 不判定、存量导演记录也不套用。手动记录不受此开关
    /// 影响（走 songStyleMemoryEnabled80）。
    static var directorEnabled81: Bool {
        get {
            UserDefaults.standard.object(forKey: Key81.directorEnabled)
                as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key81.directorEnabled)
            Breadcrumbs.log("dir81.set on=\(newValue ? 1 : 0)")
        }
    }

    /// AI 接口地址（用户自填的 OpenAI 兼容 chat/completions
    /// 完整 URL；空 = 未接 AI、走本地规则引擎）。key 不存
    /// 这里——在 Keychain（DirectorKeychain81）。
    static var directorEndpoint81: String {
        get { UserDefaults.standard.string(forKey: Key81.directorEndpoint) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: Key81.directorEndpoint)
            Breadcrumbs.log("dir81.set endpoint len=\(newValue.count)")
        }
    }

    /// AI 模型名（用户自填，默认 gpt-4o-mini 占位——实际
    /// 以用户接口的模型为准）。
    static var directorModel81: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Key81.directorModel) ?? ""
            return stored.isEmpty ? "gpt-4o-mini" : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: Key81.directorModel) }
    }

    // MARK: - (80) 逐歌记忆特效

    /// 逐歌记忆特效（默认开）：开时用户在一首歌播放中手动切
    /// 换的特效按 trackId 记住，该歌再次播放时自动套用（与
    /// 下一首预备联动预热）；关时既不记录也不套用，存量记忆
    /// 保留（设置页另有「清除逐歌记忆」显式清）。
    static var songStyleMemoryEnabled80: Bool {
        get {
            UserDefaults.standard.object(forKey: Key80.songStyleMemoryEnabled)
                as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key80.songStyleMemoryEnabled)
            Breadcrumbs.log("settings80.songStyleMemory on=\(newValue ? 1 : 0)")
        }
    }
}
