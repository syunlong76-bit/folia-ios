import Foundation

/// 二分开关（3.7 (35)，(32) 卡死续查专用）：(34) 热修后真机
/// 症状原样（墙渲染、整体偏暗、完全静止、点不动），静态审
/// 计未能再证出第二个阻塞点，故出二分版把 (32) 两大新增子
/// 系统整体旁路，用真机结果当判据：
///
/// - islandWindowDisabled：灵动岛穿透窗整层不安装
///   （SceneDelegate 安装点短路）。岛窗是 (32) 唯一全局新
///   增的窗口级覆盖层。
/// - pet32SubsystemsBypassed：MiniBarPetStage 的 (32) 新增
///   子系统整体旁路——去向登记（PetHomeRegistry 写入/互斥/
///   最前台登记在登记表咽喉点统一关门）、人格停聊（tick 内
///   advanceChat 不再调用）、停靠过期（tick 内过期扫描关
///   门，dropActor 的落位定格退回 (27)/(30) 安置语义）、告
///   别分流（prepareFarewellDestinations 不再打标，告别回
///   (30) 的淡出回池）。宠物生成/漫游/关心/批次/切歌探头
///   等 (30) 已验行为不动。
///
/// 两开关均为编译期常量：下一轮按判读逐个改 false 恢复，
/// 定位到具体子系统后再拆细。
enum FoliaBisect {
    static let islandWindowDisabled = false
    static let pet32SubsystemsBypassed = true
}
