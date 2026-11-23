import ActivityKit
import Combine
import Foundation

/// (75) 真 Live Activity 灵动岛宠物——单一协调器（DS 对
/// 账：互斥归一 C、拉起甲案 G、stale 分态 B、request 只前
/// 台 F）。独占三件事：活动的拉起/更新/结束、与应用内障
/// 眼法（PetIslandLayer perch）的互斥抑制、活动状态监听。
/// 岛层不自查 Activity.activities，只认本协调器的抑制写
/// 入，二者恒互斥、不叠影（各自证：la.* 与 isl.perch75）。
///
/// 拉起条件（甲案，与 miniPetsEnabled / introDone 完全解
/// 耦——(73)/(74)「陈旧 off 态静默压死新功能」的前科不许
/// 在 LA 上重演）：areActivitiesEnabled && 有当前曲 &&
/// 非汪汪队 && (scene 已激活 || 正在播放)。任何被挡落
/// la.gate reason=（disabled/noTrack/concert/background），
/// 不静默。用户在系统设置关了实时活动时本协调器恒拉不
/// 起，障眼法自动回落为唯一呈现（抑制恒关）。
///
/// (76) 互斥改前后台感知（Miller 21:48 截图定案）：iOS
/// 不渲染「自家 App 前台时」的自家活动——(75) 的互斥不
/// 分前后台（活动在跑就全程压制障眼法），结果前台系统
/// 不渲染、障眼法又被压制，Folia 内岛空黑；退到别家
/// App 时系统活动里的猫狗却真实可见（活动本身是活的）。
/// 改：抑制有效值 = 有活动 && 非前台，统一经
/// applySuppression() 写入与落痕（la.fg76）。前台障眼
/// 法照常落座（系统此时不渲染、无叠影）；退后台障眼法
/// 撤、系统活动接管（锁屏/别家 App/岛展开形态）。汪汪
/// 队口径不破：演唱会期间活动已 end、抑制恒关，岛全撤
/// 仍由登记表 islandSuspended 一路管。
///
/// (76) ③口径修正（Miller 21:54）：不是两套各行其是——
/// 活动全程运行、ContentState 是唯一真相源（住客名单/
/// 台词/播放态）；前台岛层只是活动的另一个渲染面，经
/// publishMirror 把每个新 ContentState 同步给岛层（同
/// 名单、同句词、同状态），岛层自有抽词/停聊在镜像期
/// 停用（见 PetIslandLayer.setIslandMirror）。前台应用
/// 画、后台系统画，交接点（回前台 contentChanged）先刷
/// 新状态再放行岛层，视觉上始终是同一个活动在动。活
/// 动结束/被闸挡下（无活动）时镜像置 nil，岛层回落自
/// 有逻辑（= 系统设置关实时活动时的回落障眼法口径）。
///
/// 正在播放干涉口径：切歌/播放态变化即 contentChanged
/// 刷新活动并按播放态保 relevance（播放 100/暂停 50），
/// 活动在新鲜期内系统「正在播放」不单独抢位；长暂停
/// 活动转 stale 后让位属既定规矩——stale 边沿落
/// la.yield76（播放中即刷新续命）、ended/dismissed 落
/// la.yield76、让位后重拉成功落 la.back76，下轮日志可
/// 对位让位与回来。
final class IslandLiveActivityManager {

    static let shared = IslandLiveActivityManager()

    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var activity: Activity<FoliaIslandAttributes>?
    private var sceneActive = false
    private var concertSuspended = false
    private var resumeWorkItem: DispatchWorkItem?
    private var phraseSerial = 0
    /// (76) 已写入岛层的抑制值（applySuppression 去重）。
    private var suppressionApplied = false
    /// (76) 让位标记：stale/ended/dismissed 置位，重拉成
    /// 功时落 la.back76 并清（让位/回来对位自证）。
    private var didYield = false

    private init() {}

    // MARK: 装配（SceneDelegate willConnect 一行调用）

    func start() {
        guard !started else { return }
        started = true
        // 进程重启时系统侧活动可能仍在：认领既有活动并接
        // 上互斥（(76) 起统一经 applySuppression 按前后台
        // 定抑制值，冷启前台随即在 sceneBecameActive 放行
        // 障眼法、后台拉起则保持抑制）。
        if let existing = Activity<FoliaIslandAttributes>.activities.first {
            activity = existing
            watch(existing)
            applySuppression()
            Breadcrumbs.log("la.start75 adopted=1")
        } else {
            Breadcrumbs.log("la.start75 adopted=0")
        }
        let engine = PlaybackEngine.shared
        engine.$currentTrack
            .map { $0?.id }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.contentChanged(reason: "track") }
            .store(in: &cancellables)
        engine.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.contentChanged(reason: "play") }
            .store(in: &cancellables)
        // 住客名单变更（拖拽换住/召回）→ 同源更新活动。
        PetHomeRegistry.shared.onIslandLineupChanged = { [weak self] _ in
            self?.contentChanged(reason: "lineup")
        }
    }

    // MARK: 场景边沿（SceneDelegate 转发）

    func sceneBecameActive() {
        sceneActive = true
        // 回前台对账：活动可能已被系统收走（8 小时上限/
        // 抢占结束）——activities 为空即视为已结束，清抑
        // 制回落障眼法，随后按闸重新拉起。
        if activity == nil,
           let existing = Activity<FoliaIslandAttributes>.activities.first {
            activity = existing
            watch(existing)
            Breadcrumbs.log("la.state75 s=readopt")
        }
        // (76) 前台边沿：系统不渲染前台自家活动，抑制解
        // 除、障眼法即刻回座（无空窗叠加：系统渲染在退
        // 后台时才存在，与本边沿天然错开）。
        applySuppression()
        if activity != nil {
            contentChanged(reason: "foreground")
        } else {
            evaluate(reason: "foreground")
        }
    }

    func sceneWillResignActive() {
        sceneActive = false
        // (76) 退后台边沿：障眼法撤、系统活动接管（用户
        // 切到别家 App/锁屏后岛里是系统渲染的猫狗）。
        applySuppression()
    }

    /// (76) 互斥收口：抑制有效值 = 有活动 && 非前台。
    /// 全部切换点（认领/拉起/活动态边沿/前后台边沿/汪汪
    /// 队）只改 activity/sceneActive 后调本函数，不再各
    /// 自直写岛层；值真变化才写入并落痕 la.fg76。
    private func applySuppression() {
        let on = activity != nil && !sceneActive
        guard on != suppressionApplied else { return }
        suppressionApplied = on
        PetIslandLayer.shared.setLiveActivitySuppressed(on)
        Breadcrumbs.log("la.fg76 supp=\(on ? 1 : 0)"
            + " fg=\(sceneActive ? 1 : 0)")
    }

    // MARK: 汪汪队口径（PetConcertRelocation 转发）

    /// 演唱会开始：活动直接结束（ContentState 无隐藏态，
    /// DS 对账次要 C），抑制清除——岛上本就全撤，障眼法
    /// 与活动同空。
    func concertBegan() {
        concertSuspended = true
        resumeWorkItem?.cancel()
        guard let act = activity else { return }
        activity = nil
        applySuppression()
        publishMirror(nil)
        Task { await act.end(nil, dismissalPolicy: .immediate) }
        Breadcrumbs.log("la.end75 why=concert")
    }

    /// 演唱会结束：1s 防抖后按闸重拉（DS 对账 B：防切走
    /// 又切回的 end/request 抖动撞限频）。
    func concertEnded() {
        concertSuspended = false
        resumeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.evaluate(reason: "concert-resume")
        }
        resumeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: 拉起闸（甲案）

    private func evaluate(reason: String) {
        guard activity == nil else { return }
        // (76) 无活动 = 无真相源：镜像清零，岛层回落自有
        // 逻辑（置 nil 在岛层侧去重、无变化不落痕）。
        publishMirror(nil)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Breadcrumbs.log("la.gate reason=disabled r=\(reason)")
            return
        }
        guard PlaybackEngine.shared.currentTrack != nil else {
            Breadcrumbs.log("la.gate reason=noTrack r=\(reason)")
            return
        }
        guard !concertSuspended,
              !PetHomeRegistry.shared.islandSuspended else {
            Breadcrumbs.log("la.gate reason=concert r=\(reason)")
            return
        }
        guard sceneActive || PlaybackEngine.shared.isPlaying else {
            Breadcrumbs.log("la.gate reason=background r=\(reason)")
            return
        }
        request()
    }

    private func request() {
        let state = makeState()
        let content = ActivityContent(
            state: state,
            staleDate: staleDate(for: state),
            relevanceScore: state.isPlaying ? 100 : 50)
        do {
            let act = try Activity.request(
                attributes: FoliaIslandAttributes(),
                content: content,
                pushType: nil)
            activity = act
            applySuppression()
            publishMirror(state)
            watch(act)
            if didYield {
                didYield = false
                Breadcrumbs.log("la.back76")
            }
            Breadcrumbs.log("la.req75 ok pets=\(state.leftPetId),\(state.rightPetId)"
                + " play=\(state.isPlaying ? 1 : 0)")
        } catch {
            Breadcrumbs.log("la.req75 err=\(String(describing: type(of: error)))")
        }
    }

    // MARK: 更新（切歌/播放态/名单/回前台同源合并一发）

    private func contentChanged(reason: String) {
        guard let act = activity else {
            evaluate(reason: reason)
            return
        }
        let state = makeState()
        // (76) ③：新 ContentState 先同步给前台岛层（镜像
        // 同句词/同名单），再发系统更新——两渲染面同源。
        publishMirror(state)
        let content = ActivityContent(
            state: state,
            staleDate: staleDate(for: state),
            relevanceScore: state.isPlaying ? 100 : 50)
        Task { await act.update(content) }
        // (76) ③补：upd 落双 id——(75) 版 upd 不记名单，
        // 日志只能对账 request 时刻；补后每发更新可逐发判
        // 读 trailing id 是否在更新路径丢失（定案佐证）。
        Breadcrumbs.log("la.upd75 r=\(reason) play=\(state.isPlaying ? 1 : 0)"
            + " rel=\(state.isPlaying ? 100 : 50)"
            + " pets=\(state.leftPetId),\(state.rightPetId)")
    }

    /// (76) ③镜像发布：ContentState → 岛层前台渲染面；
    /// nil = 无活动、岛层回落自有逻辑。
    private func publishMirror(
        _ state: FoliaIslandAttributes.ContentState?
    ) {
        if let state {
            PetIslandLayer.shared.setIslandMirror(
                leftId: state.leftPetId, rightId: state.rightPetId,
                phrase: state.phrase, isPlaying: state.isPlaying)
        } else {
            PetIslandLayer.shared.setIslandMirror(
                leftId: nil, rightId: nil, phrase: nil,
                isPlaying: false)
        }
    }

    /// stale 分态（DS 对账 B）：播放中给满 8 小时（系统上
    /// 限内靠后续 update 续命）；暂停 15 分钟后系统可收，
    /// 回前台对账重拉。relevance（(75) 追加验收点）：播放
    /// 中拉满 100 与系统「正在播放」争位、暂停降 50 让位，
    /// 他方活动结束后的回归靠回前台/切歌 update 保活。
    private func staleDate(for state: FoliaIslandAttributes.ContentState) -> Date {
        Date().addingTimeInterval(state.isPlaying ? 8 * 3600 : 15 * 60)
    }

    private func makeState() -> FoliaIslandAttributes.ContentState {
        let duo = PetHomeRegistry.shared.islandTargetDuo
        let engine = PlaybackEngine.shared
        phraseSerial += 1
        let phrases = PetLines.islandHome
        let phrase = phrases.isEmpty
            ? "" : phrases[phraseSerial % phrases.count]
        // (76) ③补（Miller 21:57：播放中主岛 trailing 狗缺
        // 席）：双 id 完整性硬保证。静态审结论——名单结构
        // 恒 2 元（登记表 override 加载要求 count==2、
        // dragSeat/dragRecall 均按侧替换、缺省 islandFixed
        // Duo=[cat-live, dog-11]），且本函数是 ContentState
        // 唯一构造点（request/contentChanged 同源），原写
        // 法 duo.last 在名单恒 2 元时不丢右 id；此处再兜一
        // 层：右位缺失或与左位同只（同只被先后拖到两侧的
        // 唯一同值路径）时回落固定搭档的另一只——
        // ContentState 绝不带空 id / 同只双占出门。
        let left = duo.first ?? "cat-live"
        var right = duo.count > 1 ? duo[1] : ""
        if right.isEmpty || right == left {
            right = (left == "dog-11") ? "cat-live" : "dog-11"
        }
        return FoliaIslandAttributes.ContentState(
            leftPetId: left,
            rightPetId: right,
            songTitle: engine.currentTrack?.title ?? "",
            artist: engine.currentTrack?.artist ?? "",
            isPlaying: engine.isPlaying,
            phrase: phrase)
    }

    // MARK: 活动状态监听（清抑制的唯一真源）

    private func watch(_ act: Activity<FoliaIslandAttributes>) {
        Task { [weak self] in
            for await state in act.activityStateUpdates {
                await MainActor.run { [weak self] in
                    self?.handleActivityState(state)
                }
            }
        }
    }

    private func handleActivityState(_ state: ActivityState) {
        switch state {
        case .active:
            // (76) 活动转 active 只登记在案；抑制与否由前
            // 后台定（前台活动在跑也不压障眼法）。
            applySuppression()
            Breadcrumbs.log("la.state75 s=active")
        case .stale:
            // (76) 正在播放干涉口径：长暂停转 stale = 让位
            // 边沿（落痕）；播放中则立即刷新续命（新
            // staleDate＋relevance 保位），不无声让位。
            didYield = true
            Breadcrumbs.log("la.yield76 why=stale")
            if PlaybackEngine.shared.isPlaying {
                contentChanged(reason: "stale")
            }
        case .ended, .dismissed:
            // 系统收走（8h/抢占/用户关）：清活动与抑制，
            // 障眼法回落；若人还在前台且闸口径成立，随即
            // 按闸重拉（evaluate 内逐项落 la.gate）。
            activity = nil
            didYield = true
            Breadcrumbs.log("la.yield76 why="
                + "\(state == .ended ? "ended" : "dismissed")")
            applySuppression()
            publishMirror(nil)
            Breadcrumbs.log("la.state75 s=\(state == .ended ? "ended" : "dismissed")")
            evaluate(reason: "state-ended")
        default:
            Breadcrumbs.log("la.state75 s=other")
        }
    }
}
