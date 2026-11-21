import Foundation

// 舞台样式的原生侧记录（UserDefaults）：
//  - currentStyleId：用户最近在原生选择器里选定的样式（或默认
//    classic）。注意边界：网页舞台内部改样式只发无载荷的
//    visualChanged 通知，原生无从得知其确切样式——本记录只是
//    「原生侧最后所知」，「当前样式未迁」提示以此为准（已知限制，
//    见 M2' 实施报告）。
//  - lastNativeStyleId：最近实际在原生舞台用过的已迁样式；当前
//    样式未迁时用它作替代样式（无记录时回默认 classic）。
enum StageStyleStore {
    private static let currentKey = "folia.stage.currentStyleId"
    private static let lastNativeKey = "folia.stage.lastNativeStyleId"

    static var currentStyleId: String {
        get {
            let stored = UserDefaults.standard.string(forKey: currentKey)
            if let stored, LyricStageRegistry.info(for: stored) != nil { return stored }
            return LyricStageRegistry.defaultStyleId
        }
        set { UserDefaults.standard.set(newValue, forKey: currentKey) }
    }

    static var lastNativeStyleId: String? {
        get {
            let stored = UserDefaults.standard.string(forKey: lastNativeKey)
            // (60) 第 4 条：锁定样式不得作回退落点（与未迁同等对待）。
            guard let stored, LyricStageRegistry.nativeStyleIds.contains(stored),
                  !LyricStageRegistry.isLocked(stored) else { return nil }
            return stored
        }
        set { UserDefaults.standard.set(newValue, forKey: lastNativeKey) }
    }

    /// 进原生舞台时应实际使用的样式：当前样式已迁且未锁定则用
    /// 它，未迁/被锁定则用最近用过的已迁未锁样式（再无则默认
    /// classic）。当前样式被锁定时同时把持久值改写为回退值并落
    /// 面包屑（存量 machi 一次清净，后续读到的恒为回退值）。
    static func effectiveStyleId() -> String {
        let current = currentStyleId
        if LyricStageRegistry.nativeStyleIds.contains(current),
           !LyricStageRegistry.isLocked(current) { return current }
        let fallback = lastNativeStyleId ?? LyricStageRegistry.defaultStyleId
        if LyricStageRegistry.isLocked(current) {
            currentStyleId = fallback
            Breadcrumbs.log("style.lock fallback style=\(current) to=\(fallback)")
        }
        return fallback
    }

    /// 启动改写（3.7 (60) 第 4 条）：存量 currentStyleId 是锁定
    /// 样式（如 machi）时，在任何舞台呈现之前直接改写为回退值，
    /// 避免「当前样式」提示条等显示路径还报锁定样式。由
    /// runLaunchStyleGuard 在启动最先调用。
    static func applyLockedStyleFallbackIfNeeded() {
        let current = currentStyleId
        guard LyricStageRegistry.isLocked(current) else { return }
        _ = effectiveStyleId()
    }

    static var currentStyleIsNative: Bool {
        LyricStageRegistry.nativeStyleIds.contains(currentStyleId)
    }

    // MARK: - 防卡死守卫（3.7 (44)）

    /// pending 标记：某样式已在舞台装配（mountRenderer）但尚
    /// 未被证明能存活渲染（StageViewController frameStep 满
    /// 60 帧或存活 2 秒后清除）。进程若在证明前消亡（卡死
    /// 被杀/崩溃），标记留存到下次启动——runLaunchStyleGuard
    /// 据此把该样式回退 classic，保证任何开台入口都不再撞
    /// 上同一块未证明的渲染路径。纵深防御：与冷启 route 取
    /// 消、莫奈成图异步化互不依赖。
    private static let stylePendingKey = "folia.stage.stylePending"

    static var stylePendingId: String? {
        UserDefaults.standard.string(forKey: stylePendingKey)
    }

    static func armStylePending(_ styleId: String) {
        UserDefaults.standard.set(styleId, forKey: stylePendingKey)
    }

    static func clearStylePending() {
        UserDefaults.standard.removeObject(forKey: stylePendingKey)
    }

    /// 启动守卫：SceneDelegate.willConnectTo 最先调用（任何
    /// 舞台呈现之前）。上次会话 pending 未清 = 上次开台未成
    /// 功：回退持久化样式至 classic 并清标记、落面包屑。
    /// 无 pending 时为空操作。
    static func runLaunchStyleGuard() {
        // (60) 第 4 条：锁定样式存量改写先行（与 pending 守卫互不依赖）。
        applyLockedStyleFallbackIfNeeded()
        guard let pending = stylePendingId else { return }
        clearStylePending()
        if currentStyleId == pending {
            currentStyleId = LyricStageRegistry.defaultStyleId
        }
        if lastNativeStyleId == pending {
            UserDefaults.standard.removeObject(forKey: lastNativeKey)
        }
        Breadcrumbs.log("stage style-guard reset from=\(pending)")
    }
}
