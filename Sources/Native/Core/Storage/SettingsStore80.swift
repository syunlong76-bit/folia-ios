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
