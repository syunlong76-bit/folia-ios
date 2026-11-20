import Foundation

/// 星标本地存档（3.7 (55) 工作流 C 新建）：只存曲目 id 集合，
/// UserDefaults 落盘，键 folia.starredTrackIDs（[String]）。
///
/// 与 LikesStore 同构但语义独立：喜欢走云端同步
/// （NativeDataClient.setLike、失败回滚），星标本期是纯本地
/// 真源（网页星标＝「加入歌单」，AddToPlaylist 本体未迁），
/// 不与喜欢共用集合、不互相回滚。当前歌曲 id 的取法与喜欢
/// 同源：PlaybackEngine.currentTrack.id（String）。
///
/// 变更通知：状态实际变更后 post .foliaStarChanged
/// （"FoliaStarChanged"），userInfo = ["id": 曲目 id,
/// "starred": 变更后状态]，供星标回显面（点播台顶排星标钮
/// 自订）与后续星标列表面订阅。toggle 必变更、必发；
/// setStarred 在状态未变时不落盘、不发通知。发送在调用线
/// 程同步进行（既有调用方均为 主线程 UI 动作）。
final class StarStore {
    static let shared = StarStore()

    private let defaultsKey = "folia.starredTrackIDs"
    private var ids: Set<String>

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        ids = Set(saved)
    }

    func isStarred(_ id: String) -> Bool {
        ids.contains(id)
    }

    /// 切换星标态并落盘，返回切换后的状态；变更后发通知。
    @discardableResult
    func toggle(_ id: String) -> Bool {
        let newState = !ids.contains(id)
        apply(id, starred: newState)
        return newState
    }

    /// 直接设定星标态并落盘；状态未变时不落盘、不发通知。
    func setStarred(_ id: String, _ on: Bool) {
        guard ids.contains(id) != on else { return }
        apply(id, starred: on)
    }

    private func apply(_ id: String, starred: Bool) {
        if starred {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        UserDefaults.standard.set(Array(ids), forKey: defaultsKey)
        NotificationCenter.default.post(
            name: .foliaStarChanged, object: nil,
            userInfo: ["id": id, "starred": starred])
    }
}

extension Notification.Name {
    /// 星标变更（3.7 (55) C）：StarStore 在状态实际变更后
    /// 发出，userInfo 带 id 与 starred。
    static let foliaStarChanged = Notification.Name("FoliaStarChanged")
}
