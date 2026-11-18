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
            guard let stored, LyricStageRegistry.nativeStyleIds.contains(stored) else { return nil }
            return stored
        }
        set { UserDefaults.standard.set(newValue, forKey: lastNativeKey) }
    }

    /// 进原生舞台时应实际使用的样式：当前样式已迁则用它，未迁
    /// 则用最近用过的已迁样式（再无则默认 classic）。
    static func effectiveStyleId() -> String {
        let current = currentStyleId
        if LyricStageRegistry.nativeStyleIds.contains(current) { return current }
        return lastNativeStyleId ?? LyricStageRegistry.defaultStyleId
    }

    static var currentStyleIsNative: Bool {
        LyricStageRegistry.nativeStyleIds.contains(currentStyleId)
    }
}
