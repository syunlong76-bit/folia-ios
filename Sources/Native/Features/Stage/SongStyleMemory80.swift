import Foundation

/// 逐歌记忆特效（3.7 (80) 第 3 项，借鉴 Folium 模组 AI 导演
/// 的「每首歌记住自己的选择」）：trackId → styleId 本地持久
/// 映射（UserDefaults 字典）。记录只发生在用户手动切样式时
/// （StageViewController 的选择器点选 / 三击轮换钩子）；套用
/// 发生在切歌边沿（StageViewController.handleTrackChanged）
/// 与下一首预备的预热选式（NextTrackPrep80）。
///
/// 纪律：
/// - 总开关 SettingsStore.songStyleMemoryEnabled80 关时：
///   record 为空操作、style(for:) 恒 nil（存量保留不清，
///   清除走设置页显式动作 clearAll）。
/// - 样式有效性在消费端校验（注册表存在且未锁定），本店只
///   存原始映射——样式日后被锁/下架时消费端跳过即可，存量
///   不需要迁移。
/// - 进程内镜像 + 写时落盘：读多写少（每次手动切样式才写
///   一次），全量字典回写足够，不做增量持久化。
final class SongStyleMemory80 {

    static let shared = SongStyleMemory80()

    private static let storageKey = "folia.stage.songStyleMemory80"

    private let lock = NSLock()
    private var map: [String: String]

    private init() {
        map = UserDefaults.standard.dictionary(forKey: Self.storageKey)
            as? [String: String] ?? [:]
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return map.count
    }

    /// 查某曲的记忆样式（开关关 / 无记录 → nil）。
    func style(for trackId: String) -> String? {
        guard SettingsStore.songStyleMemoryEnabled80 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return map[trackId]
    }

    /// 记录一次手动选择（开关关时为空操作）。同曲同式重复
    /// 记录不重复落盘/落屑。
    func record(trackId: String, styleId: String) {
        guard SettingsStore.songStyleMemoryEnabled80 else { return }
        lock.lock()
        let changed = map[trackId] != styleId
        if changed {
            map[trackId] = styleId
            UserDefaults.standard.set(map, forKey: Self.storageKey)
        }
        lock.unlock()
        if changed {
            Breadcrumbs.log("style.mem80 rec track=\(trackId) style=\(styleId)")
        }
    }

    /// 清除全部逐歌记忆（设置页显式动作）。
    func clearAll() {
        lock.lock()
        let had = map.count
        map = [:]
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        Breadcrumbs.log("style.mem80 clear n=\(had)")
    }
}
