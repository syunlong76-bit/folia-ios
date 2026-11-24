import UIKit

/// (82) 第 9 条：开灯/关灯（墙面灯光，Miller 18:18 定义）。
///
/// - 开灯（isOn=true，默认）：全部海报封面亮起——即墙面常
///   态；从关灯切回开灯时，可见砖按对角波浪依次点亮、每
///   张带闪光＋星尘粒子（宿主负责逐砖调度，本件只管状态）。
/// - 关灯（isOn=false）：整墙暗下，只有被点封面亮起（聚
///   光）；点别张时亮光带粒子拖尾转移。关灯态下点砖的交
///   互规则（与 v2 动效定版一致）：首点＝点亮该砖（不触
///   发砖的原动作），再点已亮砖＝走原动作（开墙/播放）。
/// 状态持久化（UserDefaults），跨页一致：任一页切换/点亮
/// 都发 .foliaWallLight82Changed，各封面页宿主订阅后重刷
/// 可见砖。焦点按墙名分存（内存），切回开灯即清焦点。
enum WallLight82 {

    private static let onKey = "wallLight82.on"
    private static var focusByWall: [String: String] = [:]

    static var isOn: Bool {
        get {
            // 默认开灯：未写过键时墙面保持常态全亮。
            if UserDefaults.standard.object(forKey: onKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: onKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: onKey) }
    }

    static func focusedId(wall: String) -> String? {
        focusByWall[wall]
    }

    /// (82) 第 8 条：海报聚焦叠色开关（控制台外观行）——
    /// 关时关灯态也不压暗不聚焦（灯钮仅记状态），默认开。
    private static let focusEnabledKey = "wallLight82.focusEnabled"
    static var focusEnabled82: Bool {
        get {
            if UserDefaults.standard.object(forKey: focusEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: focusEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: focusEnabledKey)
            Breadcrumbs.log("light82 focusgate=\(newValue ? 1 : 0)")
            NotificationCenter.default.post(name: .foliaWallLight82Changed, object: nil)
        }
    }

    /// 砖应有的压暗强度：开灯恒 0；关灯时焦点砖 0、其余 0.78。
    static func dimAlpha(wall: String, entryId: String) -> CGFloat {
        if isOn || !focusEnabled82 { return 0 }
        return focusByWall[wall] == entryId ? 0 : 0.78
    }

    /// 控制台灯钮切换入口（落 light82 见证＋广播）。
    static func setOn(_ on: Bool, source: String) {
        let was = isOn
        isOn = on
        if on { focusByWall.removeAll() }
        Breadcrumbs.log("light82 on=\(on ? 1 : 0) src=\(source)"
            + " was=\(was ? 1 : 0)")
        NotificationCenter.default.post(name: .foliaWallLight82Changed, object: nil)
    }

    /// 关灯态点亮一张砖（落 light82 见证＋广播）；transfer
    /// 为真表示亮光从另一张转移过来（宿主据此加粒子拖尾）。
    static func setFocus(wall: String, entryId: String) {
        let transfer = focusByWall[wall] != nil && focusByWall[wall] != entryId
        focusByWall[wall] = entryId
        Breadcrumbs.log("light82 focus wall=\(wall) id=\(entryId)"
            + " mv=\(transfer ? 1 : 0)")
        // (83) 第 3 条见证：点亮伴随封面放大（宿主 cell 在
        // applyLight82 内按焦点态落放大动画，曲线与点按展
        // 开同参，见 WallPosterCell.applyLightFocusZoom83）。
        Breadcrumbs.log("light83 focus wall=\(wall) id=\(entryId)"
            + " mv=\(transfer ? 1 : 0) zoom=1")
        NotificationCenter.default.post(name: .foliaWallLight82Changed, object: nil)
    }

    /// (83) 第 3 条：灯光状态不跨启动保留——冷启动与每次
    /// 从后台重新进入 App 都自动恢复开灯（白天）模式；会
    /// 话内（不进后台）状态不变。AppDelegate 启动与
    /// SceneDelegate willEnterForeground 各调一次（幂等：
    /// 已是开灯且无焦点时不落痕不广播）。
    static func resetOnEntry83(source: String) {
        let was = isOn
        let hadFocus = !focusByWall.isEmpty
        guard !was || hadFocus else { return }
        UserDefaults.standard.set(true, forKey: onKey)
        focusByWall.removeAll()
        Breadcrumbs.log("light83 reset src=\(source)"
            + " was=\(was ? 1 : 0) focus=\(hadFocus ? 1 : 0)")
        NotificationCenter.default.post(name: .foliaWallLight82Changed, object: nil)
    }

    /// 关灯态点砖的仲裁：返回 true 表示本次点按已被灯光
    /// 消费（点亮/转移），宿主不再走原动作；已亮砖再点返
    /// 回 false 放行原动作。开灯态恒 false。
    static func consumeTapIfNeeded(wall: String, entryId: String) -> Bool {
        if isOn || !focusEnabled82 { return false }
        if focusByWall[wall] == entryId { return false }
        setFocus(wall: wall, entryId: entryId)
        return true
    }

    // MARK: 宿主辅助（两墙共用，cell 均为 WallPosterCell）

    /// 灯光广播到达时宿主调用：开灯走对角波浪逐砖点亮
    /// （按砖帧 x+y 排序、每砖错峰 45ms、带闪光粒子）；
    /// 关灯即时全墙压暗（焦点砖保持亮）。
    @MainActor
    static func applyToVisibleCells(in collectionView: UICollectionView, wave: Bool) {
        let cells = collectionView.indexPathsForVisibleItems
            .compactMap { collectionView.cellForItem(at: $0) as? WallPosterCell }
        guard wave else {
            cells.forEach { $0.applyLight82(animated: true) }
            return
        }
        let sorted = cells.sorted {
            ($0.frame.minX + $0.frame.minY) < ($1.frame.minX + $1.frame.minY)
        }
        for (index, cell) in sorted.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.045) {
                cell.applyLight82(animated: true)
                cell.playLightFlash82()
            }
        }
    }

    /// 关灯态焦点点按的视觉收口（宿主在 consumeTapIfNeeded
    /// 返回 true 后调用）：全墙重刷压暗、新焦点出粒子环、
    /// 焦点转移时从旧焦点砖拉一条粒子拖尾过来。
    @MainActor
    static func playFocusTap(in collectionView: UICollectionView,
                             entryId: String, previousFocus: String?) {
        applyToVisibleCells(in: collectionView, wave: false)
        let cells = collectionView.indexPathsForVisibleItems
            .compactMap { collectionView.cellForItem(at: $0) as? WallPosterCell }
        guard let target = cells.first(where: { $0.lightEntryId82Value == entryId })
        else { return }
        Particles82.ring(in: target.contentView,
                         center: CGPoint(x: target.bounds.midX, y: target.bounds.midY),
                         color: UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1))
        guard let previousFocus, previousFocus != entryId,
              let source = cells.first(where: { $0.lightEntryId82Value == previousFocus })
        else { return }
        Particles82.trail(in: collectionView,
                          from: source.center, to: target.center,
                          color: UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1))
    }
}

extension Notification.Name {
    /// (82) 灯光状态/焦点变化（切换、点亮、转移）。
    static let foliaWallLight82Changed = Notification.Name("foliaWallLight82Changed")
}
