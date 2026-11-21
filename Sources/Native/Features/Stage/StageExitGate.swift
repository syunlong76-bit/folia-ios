import UIKit

// 舞台退出统一闸门 + 点卡 route 守卫（3.7 (46)，DS route-final 定案）。
//
// 背景：(43)/(44)/(45) 三版点卡 route 反复失败，(45) 真机日志坐实
// 机制 H1——route 其实把舞台送达了，但 0.85–1.9s 内被一记来源不明
// 的自动 gate exit 赶回墙；(45) 又用 gateEventSeq 变化推断「用户
// 自主操作」自弃重试，把 bug 的速退误判成用户意图，形成自锁。
// 本闸门按 DS 定案收敛全部舞台退出：
// - 所有 pop/dismiss/gate exit 必经 requestExit 登记来源；进程内
//   已知发起方先登记再 dismiss，未登记的 dismiss 由 Stage/墙/Main
//   的 dismiss override 在闸门处拦截（守卫期内 veto）。
// - route 进入（presented / alreadyOnStage）后开 3 秒 RouteGuard：
//   非用户 exit 一律 veto 并落完整来源面包屑；万一仍被未知路径带下
//   （viewWillDisappear 旁路检测），同代际允许 reenter 一次，再犯
//   giveup 并落 source（该来源判死，交下一轮日志定案）。
// - 用户手势/按钮的 exit 立即放行并 settle route。
// - 舞台永不因播放状态变化自退：播放状态变化不经过任何 exit 路径
//   （本闸门是唯一出口，trackChanged/playbackStateChanged 来源在
//   守卫期内必被 veto，非守卫期也只应由显式调用方登记——仓内无此
//   调用方）。异步回调须凭 stageToken 校验，见各调用点。
// - 用户意图只认显式信号：gate 序号推断（(45) gateEventSeq 自弃）
//   已废除；route pending 期间用户 touch 由 SceneDelegate 的触摸
//   观察器 cancel。

/// 退出来源枚举（DS 稿原文）。
enum StageExitSource: String {
    case userBackButton
    case interactivePopGesture
    case userCloseTap
    case trackChanged
    case playbackStateChanged
    case engineRestoreCompletion
    case routeTransitionCompletion
    case gateSeqMismatch
    case wallAppear
    case scenePhase
    case layoutOrScrollSettle
    case unknown
}

final class StageExitGate {

    static let shared = StageExitGate()

    private init() {}

    // MARK: canonical 舞台登记（route 复用同一实例的判据）

    /// 当前存活的舞台实例（舞台在 viewDidLoad 登记、deinit 注销）。
    /// route 的「复用 canonical 实例」= 呈现后校验链顶舞台与此处
    /// 登记的是同一实例同一 token，禁止第二套舞台并存。
    private(set) weak var canonicalStage: StageViewController?
    private(set) var canonicalStageToken = "-"
    private var tokenCounter = 0

    @discardableResult
    func registerStage(_ stage: StageViewController) -> String {
        tokenCounter += 1
        let token = "S\(tokenCounter)"
        // (62) 尾波第 1 组：防重——canonical 已有存活实例且非本台
        // 时拒绝覆盖登记（仍发独立 token，本台 deinit 的 unregister
        // 因 === 校验不会误清 canonical），防呈现竞态下第二台把
        // 闸门状态机带错位（双击闪退候选 2）。
        if let existing = canonicalStage, existing !== stage {
            Breadcrumbs.log("gate.register.replaced kept=\(canonicalStageToken) refused=\(token)")
            return token
        }
        canonicalStage = stage
        canonicalStageToken = token
        return token
    }

    func unregisterStage(_ stage: StageViewController) {
        if canonicalStage === stage {
            canonicalStage = nil
            canonicalStageToken = "-"
        }
    }

    // MARK: RouteGuard（route 进入后 3 秒）

    private(set) var guardGeneration: Int?
    private(set) var guardStageToken: String?
    /// CACurrentMediaTime 基准；presented 模式在 viewDidAppear 时
    /// 顺延到 appear+3s（DS：presented 以 appear 后 3 秒为准，
    /// alreadyOnStage 以激活后 3 秒为准——arm 时先给激活+3s）。
    private var guardDeadline: TimeInterval = 0
    private var guardReenterUsed = false

    /// 用户/程序化正当退出使 route 落定（SceneDelegate 接线）。
    var onRouteResolvedByExit: (() -> Void)?
    /// 守卫期内舞台被未知路径带下 → 请 SceneDelegate 同代际重入一次。
    var onGuardReenter: ((_ generation: Int) -> Void)?
    /// 同代际重入后再次被带下 → route giveup。
    var onRouteGaveUp: ((_ generation: Int) -> Void)?

    var guardActive: Bool {
        guard guardGeneration != nil else { return false }
        return CACurrentMediaTime() <= guardDeadline
    }

    func armRouteGuard(generation: Int, stageToken: String, alreadyOnStage: Bool) {
        // 同代际重入（guard.reenter 后 routeSucceed 再 arm）不重置
        // reenter 配额，否则 veto→reenter 可无限循环。
        if guardGeneration != generation { guardReenterUsed = false }
        guardGeneration = generation
        guardStageToken = stageToken
        guardDeadline = CACurrentMediaTime() + 3.0
        Breadcrumbs.log("nowplaying.route guard armed gen=\(generation) token=\(stageToken) mode=\(alreadyOnStage ? "already" : "presented") window=3.0s")
    }

    /// presented 模式：舞台 viewDidAppear 时把守卫窗顺延到 appear+3s。
    func noteStageAppeared(token: String) {
        guard guardStageToken == token, guardGeneration != nil else { return }
        let extended = CACurrentMediaTime() + 3.0
        if extended > guardDeadline { guardDeadline = extended }
    }

    func disarmGuard(reason: String) {
        guard guardGeneration != nil else { return }
        Breadcrumbs.log("nowplaying.route guard disarm reason=\(reason)")
        guardGeneration = nil
        guardStageToken = nil
    }

    // MARK: 退出登记与放行

    /// 一次性放行凭据：requestExit 通过后记录，dismiss override 或
    /// viewWillDisappear 旁路检测消费（3 秒内有效，防陈旧凭据误放）。
    private var approvedExit: (token: String, source: StageExitSource, at: TimeInterval)?

    /// 全部显式退出发起方的统一入口。返回 false = 守卫期 veto，
    /// 调用方不得继续 dismiss。
    @discardableResult
    func requestExit(source: StageExitSource, userInitiated: Bool,
                     stage: StageViewController, caller: String = "-") -> Bool {
        let token = stage.stageToken
        Breadcrumbs.log("stage exit.request source=\(source.rawValue) user=\(userInitiated) gen=\(guardGeneration.map(String.init) ?? "-") token=\(token) caller=\(caller)")
        if userInitiated {
            approvedExit = (token, source, CACurrentMediaTime())
            Breadcrumbs.log("stage exit.allowed source=\(source.rawValue) token=\(token) via=user")
            if guardStageToken == token, guardGeneration != nil {
                disarmGuard(reason: "user-exit")
                onRouteResolvedByExit?()
            }
            return true
        }
        if guardActive, guardStageToken == token {
            Breadcrumbs.log("stage exit.vetoed source=\(source.rawValue) token=\(token) gen=\(guardGeneration ?? -1) reenterUsed=\(guardReenterUsed)")
            return false
        }
        approvedExit = (token, source, CACurrentMediaTime())
        Breadcrumbs.log("stage exit.allowed source=\(source.rawValue) token=\(token) via=no-guard")
        return true
    }

    /// 程序化正当转移（原生舞台跳网页舞台：目的地仍是舞台，route
    /// 目标视为达成）：放行并 settle，不走 veto。
    func approveProgrammaticExit(stage: StageViewController, reason: String) {
        let token = stage.stageToken
        Breadcrumbs.log("stage exit.allowed source=\(StageExitSource.routeTransitionCompletion.rawValue) token=\(token) via=programmatic reason=\(reason)")
        approvedExit = (token, .routeTransitionCompletion, CACurrentMediaTime())
        if guardStageToken == token, guardGeneration != nil {
            disarmGuard(reason: "programmatic-exit")
            onRouteResolvedByExit?()
        }
    }

    private func consumeApproval(for stage: StageViewController) -> StageExitSource? {
        guard let approval = approvedExit, approval.token == stage.stageToken,
              CACurrentMediaTime() - approval.at < 3 else { return nil }
        approvedExit = nil
        return approval.source
    }

    // MARK: dismiss override 拦截（未登记退出的最后防线）

    /// Stage/墙/Main 的 dismiss override 调用：本次 dismiss 若会带下
    /// canonical 舞台且无放行凭据、且 RouteGuard 在期 → veto（返回
    /// true 时调用方不得调 super.dismiss）。只解舞台之上盖层的
    /// dismiss（presentedViewController 链不含舞台本体被带下时）
    /// 不在此列。
    func shouldVetoDismiss(from vc: UIViewController) -> Bool {
        guard let stage = canonicalStage else { return false }
        let targetsStage: Bool
        if vc === stage {
            // 舞台自己 dismiss 且其上无盖层 = 舞台本体退出；
            // 其上有盖层时 dismiss 只解盖层，放行。
            targetsStage = stage.presentedViewController == nil
        } else {
            var cursor = vc.presentedViewController
            var found = false
            while let current = cursor {
                if current === stage { found = true; break }
                cursor = current.presentedViewController
            }
            targetsStage = found
        }
        guard targetsStage else { return false }
        if consumeApproval(for: stage) != nil { return false }
        if guardActive, guardStageToken == stage.stageToken {
            Breadcrumbs.log("stage exit.vetoed source=unknown token=\(stage.stageToken) gen=\(guardGeneration ?? -1) caller=\(type(of: vc)) via=dismiss-override")
            return true
        }
        return false
    }

    // MARK: 旁路检测（viewWillDisappear isBeingDismissed 汇点）

    /// 舞台确实被带下时的汇点：有放行凭据 = 正当退出（痕迹已在
    /// request/override 落过）；无凭据且守卫在期 = 未知路径旁路，
    /// 落 exit.bypass 并按配额触发同代际 reenter / giveup。
    func noteStageDismissed(_ stage: StageViewController) {
        let token = stage.stageToken
        if consumeApproval(for: stage) != nil { return }
        guard guardActive, guardStageToken == token,
              let generation = guardGeneration else { return }
        Breadcrumbs.log("stage exit.bypass source=unknown token=\(token) gen=\(generation) reenterUsed=\(guardReenterUsed)")
        if !guardReenterUsed {
            guardReenterUsed = true
            Breadcrumbs.log("nowplaying.route guard.reenter gen=\(generation) token=\(token)")
            let handler = onGuardReenter
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                handler?(generation)
            }
        } else {
            Breadcrumbs.log("nowplaying.route giveup gen=\(generation) reason=exit-bypass-twice source=unknown token=\(token)")
            disarmGuard(reason: "giveup-bypass")
            onRouteGaveUp?(generation)
        }
    }
}
