import Foundation

/// 样式运行位（3.7 (67) A3 立、(70) 收敛）：网页 17 式在原生
/// 台面内嵌网页原版特效层运行，自有样式（原创三稿＋汪汪队）
/// 无网页实现、恒原生渲染。(67) 期为逐式可切换的双运行位
/// （UserDefaults 键 folia.stage.runtime67.*、缺省原生）；
/// (70) Miller 真机验网页切换后下令删 17 式原生移植、只走
/// 网页单路——运行位自此由注册表 hasWebRuntime 唯一决定，
/// 不再读存储：遗留键 folia.stage.runtime67.* 留盘不读、
/// 无害化（任何残值都不会让已删渲染器复活，注册表 17 式
/// factory 已为 nil）。切换钮与 styleruntime 面包屑随之退役。
enum StageRuntime: String {
    case native
    case web
}

enum StageRuntimeStore {

    static func runtime(for styleId: String) -> StageRuntime {
        guard let info = LyricStageRegistry.info(for: styleId) else {
            return .native
        }
        return info.hasWebRuntime ? .web : .native
    }

    static func isWeb(_ styleId: String) -> Bool {
        runtime(for: styleId) == .web
    }
}
