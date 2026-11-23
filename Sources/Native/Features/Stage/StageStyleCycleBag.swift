import Foundation
import UIKit

// 舞台样式轮换洗牌袋（3.7 (54) 工作流 R 立、(61) 改三击触
// 发）：StageStyleCycleBag 为洗牌袋状态（进程单例、纯内
// 存——轮次跨切歌/跨开台保留、冷启重建，不落盘）。触发本
// 体是 StageViewController 的三击识别器，切换落点在
// applyNativeStyleSelection / applyWebStyleSelection（与
// 样式选择器同一通路）。
// (70) B2：同文件原 StageCyclePressObserver（按压观察器）
// 与 StageCycleProgressRingView（进度环）整类删除——二者
// 自 (61) 后唯一消费者是点播台宠物 4s 开启手势，(70) 该
// 手势整套撤走后无引用。holdDuration/pressMoveTolerance
// 常量保留作沿革口径（三击现行触发不读）。

final class StageStyleCycleBag {

    static let shared = StageStyleCycleBag()

    /// 长按触发时长（Miller 口径：满 5 秒）。
    static let holdDuration: TimeInterval = 5
    /// 按压容忍位移：观察器撤环与触发识别器 allowableMovement
    /// 共用此值，手指漂移超限即整次长按作废。
    static let pressMoveTolerance: CGFloat = 12

    private var poolObserver: NSObjectProtocol?

    private init() {
        // 随机池变更（3.7 (69) P3）：只清本轮余量——下一次取
        // 样式时按新候选集开新轮；当前正在播的样式不跳变
        // （DS 对账 Q5「池变更重建袋但当前曲不跳变」）。
        poolObserver = NotificationCenter.default.addObserver(
            forName: StageStylePoolStore.changedNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.remaining.removeAll()
        }
    }

    /// 本轮余量（洗牌后的待切队列，队头先出）。不变量：当前
    /// 样式永不在余量内（next 取前对账 + noteExternalSelection
    /// 两处收口）。
    private var remaining: [String] = []
    /// 已开始的轮次序号（首次装填 = 1）；0 = 尚未开轮。
    private(set) var round = 0

    var remainingCount: Int { remaining.count }

    /// 可选全集（与样式选择器同源同序）：LyricStageRegistry
    /// 全部登记条目——已迁条目在选择器走原生切换、未迁条目
    /// 走网页兜底，两者在选择器里都可选，故全部入袋；注册
    /// 表之外不存在其他可选样式。（60) 第 4 条：锁定样式
    /// （isLocked）过滤出袋——next() 取前对账会把已在余量
    /// 里的锁定残留一并剔除，进行中的一轮自动清净。（74）
    /// machi 解除锁定后注册表已无锁定样式，全集 = 21 只，
    /// 町景与三击/长按轮换同源入袋。
    static var selectableStyleIds: [String] {
        LyricStageRegistry.allStyles
            .filter { !$0.isLocked }
            .sorted { $0.order < $1.order }.map { $0.id }
    }

    /// 外部选样式对账（选择器手选 / 提示条回网页 / 开台初始
    /// 样式 / 轮换自身落点都经此）：被选样式成为当前样式，
    /// 从本轮余量剔除——本轮内长按不会再切回刚被选走的同
    /// 一只。余量因此耗尽时，下一取自动开新轮。
    func noteExternalSelection(_ styleId: String) {
        remaining.removeAll { $0 == styleId }
    }

    /// 取下一只：先以当前样式对账（剔除当前样式与已不可选
    /// 的残留），余量空则开新轮——全集洗牌后剔除当前样式，
    /// 故新轮第一只必然不是刚切走的那只（强于「首只不同」
    /// 的口径：当前样式整轮不入袋，与不变量一致）。一轮内
    /// 每只至多递出一次。可选全集不足 2 只时返回 nil。
    /// 候选集经随机池过滤（3.7 (69) P3）：池未启用过滤时即
    /// 可选全集；启用时只在池内轮换。池内不足 2 只（含单只
    /// 退化）同样返回 nil，退化态由池面板明示。
    func next(currentStyleId: String)
        -> (styleId: String, round: Int, remaining: Int)? {
        let selectable = StageStylePoolStore.effectiveCandidates
        guard selectable.count > 1 else { return nil }
        remaining.removeAll { $0 == currentStyleId || !selectable.contains($0) }
        if remaining.isEmpty {
            round += 1
            remaining = selectable.shuffled()
            remaining.removeAll { $0 == currentStyleId }
            Breadcrumbs.log("style.cycle.round start round=\(round) size=\(remaining.count)")
        }
        let nextId = remaining.removeFirst()
        return (nextId, round, remaining.count)
    }
}

