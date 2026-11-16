import Foundation

/// 喜欢（红心）本地存档：只存曲目 id 集合，UserDefaults 落盘。
///
/// 唯一真源：桥快照的 isLiked（WebEffectBridge.isLikedProvider）与播放页
/// 面板 LikeButton 的回显都读它；foliaAction 的 like 动作经
/// onToggleLikeRequested 写它。登录态的账号喜欢不在此列（M3 登录线未接）。
final class LikesStore {
    static let shared = LikesStore()

    private let defaultsKey = "folia.likedTrackIds"
    private var ids: Set<String>

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        ids = Set(saved)
    }

    func isLiked(_ trackId: String) -> Bool {
        ids.contains(trackId)
    }

    /// 切换喜欢态并落盘，返回切换后的状态。
    @discardableResult
    func toggle(_ trackId: String) -> Bool {
        if ids.contains(trackId) {
            ids.remove(trackId)
        } else {
            ids.insert(trackId)
        }
        UserDefaults.standard.set(Array(ids), forKey: defaultsKey)
        return ids.contains(trackId)
    }
}
