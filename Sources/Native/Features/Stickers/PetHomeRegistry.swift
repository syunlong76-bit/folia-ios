import Foundation

// 宠物去向登记（3.7 (32)，Miller 2026-11-20 01:55 定案「一套
// 班底、三个家、身份连续」）：全 App 一份班底，每只宠物同一
// 时刻只有一个位置——墙台 / 灵动岛 / 详情页台 / 幕后。任何
// 位置变更都经此登记并落 pet.move 面包屑（asset/from/to），
// 供真机核对流转。会话级即可，不持久化（岛与详情页的「等
// 你」关系靠墙台告别分流在本会话内自然形成）。
//
// 身份连续的两条硬保证：
// 1. 在场互斥：各 MiniBarPetStage 把自己当前在场名单登记在
//    live 表里，取人时排除「在别处在场」的宠物，杜绝同一只
//    同时出现在两个台面上。
// 2. 岛上限与顺序：islandOrder 保持落座顺序，上限 2 只由
//    分流决策方（墙台告别流）查 islandResidents 后决定。

enum PetHome: String {
    case wallBar, island, stageBar, pool

    var logName: String { rawValue }
}

final class PetHomeRegistry {

    static let shared = PetHomeRegistry()

    private var homes: [String: PetHome] = [:]
    /// 灵动岛落座顺序（先到先坐，点岛回台/被召回时移除）。
    private(set) var islandOrder: [String] = []
    static let islandCapacity = 2

    /// 各宠物层当前在场名单（key = 层实例标识）。
    private var liveByStage: [ObjectIdentifier: Set<String>] = [:]
    /// 当前最前面的宠物层（舞台优先于墙）：岛上宠物点按回台
    /// 的落点判定用。各层在 barPresentationChanged 时登记。
    private weak var frontStageRoleStage: MiniBarPetStage?
    private weak var frontWallRoleStage: MiniBarPetStage?

    /// 宠物离开灵动岛（被召回/点按回台）时通知岛层撤下演员。
    var onIslandDeparture: ((String) -> Void)?

    private init() {}

    func home(of asset: String) -> PetHome {
        homes[asset] ?? .pool
    }

    /// 变更去向（幂等：同值不记）。from/to 都落面包屑。
    func setHome(_ asset: String, _ newHome: PetHome) {
        let old = home(of: asset)
        guard old != newHome else { return }
        homes[asset] = newHome
        if newHome == .island {
            if !islandOrder.contains(asset) { islandOrder.append(asset) }
        } else {
            islandOrder.removeAll { $0 == asset }
        }
        Breadcrumbs.log("pet.move asset=\(asset)"
            + " from=\(old.logName) to=\(newHome.logName)")
        if old == .island {
            onIslandDeparture?(asset)
        }
    }

    var islandResidents: [String] { islandOrder }
    var stageBarResidents: [String] {
        homes.filter { $0.value == .stageBar }.map { $0.key }
    }

    // MARK: 在场互斥登记

    func noteLiveAssets(stage: MiniBarPetStage, assets: Set<String>) {
        liveByStage[ObjectIdentifier(stage)] = assets
    }

    func liveAssetsElsewhere(excluding stage: MiniBarPetStage) -> Set<String> {
        let me = ObjectIdentifier(stage)
        var out = Set<String>()
        for (key, assets) in liveByStage where key != me {
            out.formUnion(assets)
        }
        return out
    }

    // MARK: 最前层登记（岛上宠物回台落点）

    func noteFrontmost(stage: MiniBarPetStage, presented: Bool) {
        switch stage.role {
        case .stage:
            if presented { frontStageRoleStage = stage }
            else if frontStageRoleStage === stage { frontStageRoleStage = nil }
        case .wall:
            if presented { frontWallRoleStage = stage }
            else if frontWallRoleStage === stage { frontWallRoleStage = nil }
        }
    }

    /// 岛上宠物点按回台的落点：舞台在场优先，其次墙台；都
    /// 不在场返回 nil（宠物留在岛上）。
    func frontmostStage() -> MiniBarPetStage? {
        if let stage = frontStageRoleStage, stage.isBarPresented {
            return stage
        }
        if let wall = frontWallRoleStage, wall.isBarPresented {
            return wall
        }
        return nil
    }
}
