import Foundation

/// 样式运行位（3.7 (67) A3）：网页 17 式每式一个持久化运行位
/// ——原生（本仓移植渲染器）或网页运行（原生台面内嵌网页原版
/// 特效层）。缺省原生：原生移植是已验兜底，网页运行由用户在
/// 样式选择器逐式切换、真机验过后再逐式定版。自有样式（原创
/// 三稿＋汪汪队）无网页实现，恒原生、不读本存储。
enum StageRuntime: String {
    case native
    case web
}

enum StageRuntimeStore {
    private static let keyPrefix = "folia.stage.runtime67."

    static func runtime(for styleId: String) -> StageRuntime {
        guard LyricStageRegistry.info(for: styleId)?.hasWebRuntime == true else {
            return .native
        }
        let raw = UserDefaults.standard.string(forKey: keyPrefix + styleId)
        return StageRuntime(rawValue: raw ?? "") ?? .native
    }

    static func setRuntime(_ runtime: StageRuntime, for styleId: String) {
        guard LyricStageRegistry.info(for: styleId)?.hasWebRuntime == true else { return }
        UserDefaults.standard.set(runtime.rawValue, forKey: keyPrefix + styleId)
        Breadcrumbs.log("styleruntime style=\(styleId) rt=\(runtime.rawValue)")
    }

    static func isWeb(_ styleId: String) -> Bool {
        runtime(for: styleId) == .web
    }
}
