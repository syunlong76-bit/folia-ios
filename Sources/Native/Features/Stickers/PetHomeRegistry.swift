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
// 2. 岛上限与顺序：islandOrder 保持落座顺序，上限由分流
//    决策方（墙台告别流）查 islandResidents 后决定。
//    (53) 工作流 M 改定（Miller 2026-11-21）：居民不再是
//    (43) 的「容量 3／{猫2, 狗1}／活泼优先轮换」——恒为固定
//    双人组 islandFixedDuo（捂脸猫 cat-live + 爱心狗
//    dog-11），容量随之改 2；非双人组写入 .island 时在
//    setHome 改道回池（见下），islandOrder 恒只含双人组。

enum PetHome: String {
    case wallBar, island, stageBar, pool

    var logName: String { rawValue }
}

final class PetHomeRegistry {

    static let shared = PetHomeRegistry()

    private var homes: [String: PetHome] = [:]
    /// 灵动岛落座顺序（先到先坐，点岛回台/被召回时移除）。
    private(set) var islandOrder: [String] = []
    /// 灵动岛固定居民（(53) 工作流 M 定版）：捂脸猫
    /// cat-live（歌单加载页 LoadingBackdropView 定版同只，
    /// APNG 原帧）+ 爱心狗 dog-11（抱大红爱心，贴纸包内
    /// 唯一抱爱心者）。数组序即岛上站位序（猫左狗右）。
    static let islandFixedDuo: [String] = ["cat-live", "dog-11"]
    /// 岛容量 = 固定双人组人数（(43) 的 3 退役）。
    static let islandCapacity = 2

    /// (75) 第 4 项：用户拖拽定版的住客名单（[左, 右]，持久
    /// 化）。nil = 没人拖过、走 islandFixedDuo 缺省。固定双
    /// 人组门自此只辖自动路径（reconcile/告别分流/选角），
    /// 用户拖拽经 dragSeat 越门换住——53 只全可。
    private static let residentsKey75 = "folia.island.residents75"
    private(set) var islandOverride75: [String]? = {
        let saved = UserDefaults.standard.stringArray(forKey: PetHomeRegistry.residentsKey75)
        return (saved?.count == 2) ? saved : nil
    }()

    /// 当前岛住客名单（[左, 右]）：拖拽定版优先、缺省双人组。
    var islandTargetDuo: [String] { islandOverride75 ?? Self.islandFixedDuo }

    /// 住客名单变更回调（(75)：真 Live Activity 侧据此同步
    /// ContentState 的左右宠物 id）。
    var onIslandLineupChanged: (([String]) -> Void)?

    /// 各宠物层当前在场名单（key = 层实例标识）。
    private var liveByStage: [ObjectIdentifier: Set<String>] = [:]
    /// 当前最前面的宠物层（舞台优先于墙）：岛上宠物点按回台
    /// 的落点判定用。各层在 barPresentationChanged 时登记。
    private weak var frontStageRoleStage: MiniBarPetStage?
    private weak var frontWallRoleStage: MiniBarPetStage?

    /// 宠物离开灵动岛（被召回/点按回台）时通知岛层撤下演员。
    var onIslandDeparture: ((String) -> Void)?
    /// 宠物应落座灵动岛时通知岛层接走（(72) 新增，与
    /// onIslandDeparture 对称：登记表只裁决、岛层只执行）。
    var onIslandArrival: ((String) -> Void)?

    /// 演唱会迁移期岛回填冻结（(72)，PetConcertRelocation
    /// begin 置位、end 清除后才 reconcile，防撤场中途回岛）。
    var islandSuspended = false
    /// 入场油画已完成过一次（(72) bootstrap 门控：scene 激
    /// 活触发在入场未落定前不落座，防宠物浮在油画上抢戏）。
    private var introDone = false

    /// 台上选角占位（(72)，DS 评审对账第 2 条）：pickAssets
    /// 是所有取人的唯一出口，返回前对所选资产打时间戳；
    /// 批次预排（pendingSpawns 错峰 ≤0.22×8≈1.8s）期间资产
    /// 尚未 makeActor 写 home、未进在场表，reconcile 凭此
    /// 跳过。3 秒过期自动失效，不需释放记账。
    private var claimedAtMap: [String: TimeInterval] = [:]

    func claim(_ assets: [String]) {
        let now = Date().timeIntervalSince1970
        for asset in assets { claimedAtMap[asset] = now }
    }

    private func isClaimed(_ asset: String) -> Bool {
        guard let at = claimedAtMap[asset] else { return false }
        return Date().timeIntervalSince1970 - at < 3
    }

    /// 任一台上当前在场（在场互斥表的全量视角）。
    func isLiveAnywhere(_ asset: String) -> Bool {
        liveByStage.values.contains { $0.contains(asset) }
    }

    private init() {}

    func home(of asset: String) -> PetHome {
        homes[asset] ?? .pool
    }

    /// 变更去向（幂等：同值不记）。from/to 都落面包屑。
    /// 3.7 (35) 二分门：旁路时登记表整体冻结（写入不生效、
    /// home 恒 .pool、各名单恒空），取人退回 (30) 口径。
    func setHome(_ asset: String, _ newHome: PetHome) {
        if FoliaBisect.pet32SubsystemsBypassed { return }
        // (53) M 固定双人组闸：岛居民选角的唯一数据源在此
        // ——非双人组不得登记为岛民。墙台告别分流（MiniBar
        // PetStage 的 (43) 缺口/活泼优先挑选，本工作流禁改
        // 该文件）仍会把任意宠物标向岛，其 setHome(.island)
        // 在此改道回池：该宠物说完告别词离台后回池待下次
        // 上台，岛上恒只有双人组；双人组被标向岛时照常
        // 落座，不受影响。改道落 island.resident.redirect
        // 面包屑供真机对账（与 pet.farewell.dest 的 island=
        // 名单对照即知哪些被改道）。
        var target = newHome
        // (75) 闸口径：认当前住客名单（拖拽定版优先）——拖
        // 拽换住先经 dragSeat 改名单再 setHome(.island)，不
        // 被本闸改道；自动路径标来的名单外宠物照旧回池。
        if newHome == .island, !islandTargetDuo.contains(asset) {
            target = .pool
            Breadcrumbs.log("island.resident.redirect asset=\(asset)"
                + " resident=targetDuo"
                + " duo=\(islandTargetDuo.joined(separator: ","))")
        }
        let old = home(of: asset)
        guard old != target else { return }
        homes[asset] = target
        if target == .island {
            if !islandOrder.contains(asset) { islandOrder.append(asset) }
        } else {
            islandOrder.removeAll { $0 == asset }
        }
        Breadcrumbs.log("pet.move asset=\(asset)"
            + " from=\(old.logName) to=\(target.logName)")
        if old == .island {
            onIslandDeparture?(asset)
        }
    }

    var islandResidents: [String] { islandOrder }

    // MARK: (75) 第 4 项：拖拽换住 / 拖出召回

    /// 拖拽落座：asset 占 side（0=左 leading、1=右
    /// trailing）。名单按侧替换并持久化；被换下且在岛者回
    /// 池（setHome 触发 onIslandDeparture 撤演员，说完告别
    /// 词的呈现由岛层 releasePet 动画承接）；拖入者登记岛
    /// 并经 onIslandArrival 由岛层落座。拖拽＝明确用户意
    /// 图：顺带把台面宠物开关双写 on（与爪印召唤同路），
    /// 不许陈旧 off 静默拦死落座。汪汪队期间
    /// （islandSuspended）不落座、返回 false。
    @discardableResult
    func dragSeat(asset: String, side: Int) -> Bool {
        guard side == 0 || side == 1 else { return false }
        guard !islandSuspended else {
            Breadcrumbs.log("isl.drag75 seat=\(asset) side=\(side) deny=concert")
            return false
        }
        var duo = islandTargetDuo
        let displaced = duo[side]
        if displaced == asset {
            Breadcrumbs.log("isl.drag75 seat=\(asset) side=\(side) same=1")
            return true
        }
        duo[side] = asset
        islandOverride75 = duo
        UserDefaults.standard.set(duo, forKey: Self.residentsKey75)
        if home(of: displaced) == .island {
            setHome(displaced, .pool)
        }
        setHome(asset, .island)
        onIslandArrival?(asset)
        if !StickerSettings.miniPetsEnabled {
            SettingsStore.miniPetsEnabled = true
            StickerSettings.miniPetsEnabled = true
            Breadcrumbs.log("isl.drag75 pets=on")
        }
        Breadcrumbs.log("isl.drag75 seat=\(asset) side=\(side) out=\(displaced)")
        onIslandLineupChanged?(duo)
        return true
    }

    /// 拖出召回的名单收口：被召回者所在侧回落缺省双人组
    /// 同侧位（名单与缺省全同时撤 override 回纯缺省态）。
    /// 宠物本体的离岛（回台/回池）由岛层走既有回台路执
    /// 行，本方法只管名单。缺省成员在下个稳定事件被
    /// reconcile 重新落座——召回的即时语义（离岛回台）不
    /// 受影响。
    func dragRecall(asset: String) {
        guard var duo = islandOverride75,
              let idx = duo.firstIndex(of: asset) else {
            Breadcrumbs.log("isl.drag75 recall=\(asset) list=default")
            return
        }
        duo[idx] = Self.islandFixedDuo[idx]
        if duo == Self.islandFixedDuo {
            islandOverride75 = nil
            UserDefaults.standard.removeObject(forKey: Self.residentsKey75)
        } else {
            islandOverride75 = duo
            UserDefaults.standard.set(duo, forKey: Self.residentsKey75)
        }
        Breadcrumbs.log("isl.drag75 recall=\(asset) side=\(idx)")
        onIslandLineupChanged?(islandTargetDuo)
    }

    // MARK: 灵动岛确定性落座（(72) 头条，DS 评审对账后定版）
    //
    // 背景：(71) 真机日志实证——上岛唯一路径（墙台收台告别
    // →分流抽签→三闸放行）在真实使用里几乎永不走完（抽样
    // 会话台上 cast=0、pet.move/pet.farewell.dest 均 0 次），
    // 且 (43) 活泼序选角与 (53) 固定双人组闸口径相反。本版
    // 改为：双人组的默认家就是岛，由本登记表在**稳定事件**
    // 上裁决落座（reconcile），岛层只经 onIslandArrival 执行。
    // 触发点（均为稳定态，不在 tick/选角中途跑）：入场完成
    // (intro)、scene 激活 (active)、召唤开关切换 (switch)、
    // 演唱会结束 (concert)、告别流完成 (farewell)。内部
    // 0.5s 合并去抖，重复触发只跑最后一次。

    private var reconcileWorkItem: DispatchWorkItem?

    func reconcileIsland(reason: String) {
        if FoliaBisect.pet32SubsystemsBypassed { return }
        if reason == "intro" { introDone = true }
        reconcileWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.runReconcile(reason: reason)
        }
        reconcileWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func runReconcile(reason: String) {
        // (73) 解耦定案：岛民落座不再过 miniPetsEnabled 闸。
        // (72) 真机实证——该开关被爪印钮/长按宠物的「关闭」
        // 语义持久化写 false 后（Miller (70)/(71) 验收爪印钮
        // 时关过），此后每次 reconcile 都走 off 分支提前返回，
        // 落座裁决永不执行：isl.gate/isl.seat.*/isl.drive 全
        // 程 0 次、日志只有 isl.boot off 一行。但 Miller 定版
        // 里岛民是常驻固定双人组，唯一认可的撤岛口径是汪汪
        // 队样式（islandSuspended，见下段闸）；迷你台开关只
        // 管台上 cast 的召唤与否，不辖岛民。开关态只记进
        // isl.boot 的 bar= 字段供对账，不再拦裁决。
        if reason == "active", !introDone {
            Breadcrumbs.log("isl.gate why=intro r=active")
            return
        }
        if islandSuspended {
            Breadcrumbs.log("isl.gate why=concert r=\(reason)")
            return
        }
        var decisions: [String] = []
        for asset in islandTargetDuo {
            switch home(of: asset) {
            case .island:
                // 已登记在岛：仍调 arrival 自愈（岛层 seatPet
                // 对重复落座静默去重），防层重建后登记与画面脱钩。
                onIslandArrival?(asset)
                decisions.append("\(asset):isl")
            case .pool:
                if isLiveAnywhere(asset) {
                    decisions.append("\(asset):onstage")
                } else if isClaimed(asset) {
                    decisions.append("\(asset):claimed")
                } else {
                    setHome(asset, .island)
                    onIslandArrival?(asset)
                    decisions.append("\(asset):seated")
                }
            case .wallBar, .stageBar:
                decisions.append("\(asset):onstage")
            }
        }
        Breadcrumbs.log("isl.boot r=\(reason) \(decisions.joined(separator: " "))"
            + " bar=\(StickerSettings.miniPetsEnabled ? "on" : "off")")
    }
    var stageBarResidents: [String] {
        homes.filter { $0.value == .stageBar }.map { $0.key }
    }

    // MARK: 在场互斥登记

    func noteLiveAssets(stage: MiniBarPetStage, assets: Set<String>) {
        if FoliaBisect.pet32SubsystemsBypassed { return }
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
        if FoliaBisect.pet32SubsystemsBypassed { return }
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
