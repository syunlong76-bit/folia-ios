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
        /// 展开/锁屏面的一句宠物词（既有岛上语料
        /// PetLines.islandHome 口径）；best-effort 字段，只
        /// 随切歌/播放态更新同次刷新，不单独发 update。
        var phrase: String
    }
}
