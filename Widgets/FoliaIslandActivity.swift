import ActivityKit
import Foundation

/// (75) 灵动岛宠物 Live Activity 的共享属性定义：本文件同
/// 时编入 App 与 FoliaWidgets 扩展两个 target（project.yml
/// 双侧声明），两侧 ContentState 结构恒一致。图片不走共享
/// 容器（DS 对账 A：v1 删除 App Group）——53 只宠物首帧图
/// 以 imageset 打进扩展包内，id 即贴纸资产名（cat-live /
/// dog-11 / cat-01…），扩展侧 Image(id) 直接命中。
///
/// ContentState 不设 petsHidden（DS 对账次要 C）：汪汪队
/// 期间只走「结束活动」路径，不用隐藏态表达撤岛。
struct FoliaIslandAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 左（compact leading / 展开 leading）宠物资产名。
        var leftPetId: String
        /// 右（compact trailing / 展开 trailing）宠物资产名。
        var rightPetId: String
        var songTitle: String
        var artist: String
        var isPlaying: Bool
        /// 展开/锁屏面的一句宠物词；(77) ⑩起内容源改岛上
        /// 专属对话引擎（IslandDialogue77：自嘲定稿链→聊
        /// 当前歌→关心句→人格词库垫场），45 秒一拍随协调
        /// 器合并更新推进，不单独高频发 update。
        var phrase: String
        /// (77) ⑩台词说话侧：0 = 左住客、1 = 右住客。呈
        /// 现侧据此把台词放在说话者一侧（归属呈现）；
        /// compact/minimal 不读本字段（不放文字）。
        var phraseSide: Int
    }
}
