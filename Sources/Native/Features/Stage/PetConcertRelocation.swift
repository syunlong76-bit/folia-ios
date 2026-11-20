import Foundation

// 汪汪队开大会（3.7 (53) 工作流 J §8）：宠物条件迁移协调。
//
// 触发条件（Miller 2026-11-21 00:44 定版）：当且仅当当前样式
// = petconcert 且舞台呈现中——迷你台（墙台 + 详情页台）与灵
// 动岛的宠物全部撤下，53 只只在演唱会舞台出现（单实例口径）。
// 切走样式或退出舞台即恢复。触发点挂在渲染器生命周期上：
// PetConcertStageRenderer 首次 setLifecycle(active) → begin，
// unmount / destroyed → end（样式切换走 swapRenderer 的
// unmount、舞台退出走 teardown 的 unmount，两路都覆盖）。
//
// 撤下/恢复一律走既有退场/入场机制，不硬闪：
//  - 迷你台：MiniBarPetStage.concertRelocateOut（既有告别流：
//    逐个说离开词再淡出）/ concertRestore（既有取人重组）。
//  - 灵动岛：只调公开面——PetHomeRegistry.setHome(.pool) 经
//    onIslandDeparture 回调触发 PetIslandLayer.releasePet 的
//    既有小跳淡出撤下动画（PetIslandLayer 本文件零改动，其
//    公开 API 足够，无需新钩子）。
//  - 岛的恢复不瞬移回岛：按原有逻辑，岛居民由墙台告别分流
//    在后续收起/批次轮换时自然重新落座（这正是「按原有逻辑
//    恢复」——原逻辑里岛从来不是即时回填的）。
//
// 状态不丢的论证：迁移不写任何持久键。seen 名单（UserDefaults
// folia.minipets.seenAssets）、人格分配（PetPersonalities 静态
// 表）、停聊冷却（MiniBarPetStage 实例内状态，实例不销毁）、
// 去向登记（PetHomeRegistry 会话表）都不被迁移触碰或只按既
// 有语义流转：墙台宠物离场回 .pool、详情页台宠物保留
// .stageBar 等候登记（恢复时优先原班底回台、照常冒「等你」
// 台词）、岛居民回 .pool 待下次分流。

final class PetConcertRelocation {

    static let shared = PetConcertRelocation()

    private var active = false

    private init() {}

    /// 进入演唱会（样式生效 + 舞台呈现）：全场宠物撤下。
    func beginConcert() {
        guard !active else { return }
        active = true
        // 灵动岛先撤：登记回池即触发岛层既有撤下动画。
        let islanders = PetHomeRegistry.shared.islandResidents
        for asset in islanders {
            PetHomeRegistry.shared.setHome(asset, .pool)
        }
        Breadcrumbs.log("concert.pets.relocate surface=island count=\(islanders.count)")
        // 两个迷你台（墙/舞台角色）经实例注册表逐个告别退场。
        MiniBarPetStage.concertRelocateAll()
        Breadcrumbs.log("concert.pets.relocate island=\(islanders.count)"
            + " islanders=\(islanders.joined(separator: ","))")
    }

    /// 退出演唱会（切走样式 / 退出舞台）：迷你台按原逻辑恢复。
    func endConcert() {
        guard active else { return }
        active = false
        Breadcrumbs.log("concert.pets.restore surface=island mode=deferred-farewell-flow")
        MiniBarPetStage.concertRestoreAll()
        Breadcrumbs.log("concert.pets.restore island=deferred-farewell-flow")
    }
}
