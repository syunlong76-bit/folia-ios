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
final class IslandLiveActivityManager {

    static let shared = IslandLiveActivityManager()

    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var activity: Activity<FoliaIslandAttributes>?
    private var sceneActive = false
    private var concertSuspended = false
    private var resumeWorkItem: DispatchWorkItem?
    private var phraseSerial = 0

    private init() {}

    // MARK: 装配（SceneDelegate willConnect 一行调用）

    func start() {
        guard !started else { return }
        started = true
        // 进程重启时系统侧活动可能仍在：认领既有活动并接
        // 上抑制（防双开叠影）。
        if let existing = Activity<FoliaIslandAttributes>.activities.first {
            activity = existing
            PetIslandLayer.shared.setLiveActivitySuppressed(true)
            watch(existing)
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
            PetIslandLayer.shared.setLiveActivitySuppressed(true)
            watch(existing)
            Breadcrumbs.log("la.state75 s=readopt")
        }
        if activity != nil {
            contentChanged(reason: "foreground")
        } else {
            evaluate(reason: "foreground")
        }
    }

    func sceneWillResignActive() {
        sceneActive = false
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
        PetIslandLayer.shared.setLiveActivitySuppressed(false)
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
            PetIslandLayer.shared.setLiveActivitySuppressed(true)
            watch(act)
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
        let content = ActivityContent(
            state: state,
            staleDate: staleDate(for: state),
            relevanceScore: state.isPlaying ? 100 : 50)
        Task { await act.update(content) }
        Breadcrumbs.log("la.upd75 r=\(reason) play=\(state.isPlaying ? 1 : 0)"
            + " rel=\(state.isPlaying ? 100 : 50)")
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
        return FoliaIslandAttributes.ContentState(
            leftPetId: duo.first ?? "cat-live",
            rightPetId: duo.last ?? "dog-11",
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
            PetIslandLayer.shared.setLiveActivitySuppressed(true)
            Breadcrumbs.log("la.state75 s=active")
        case .ended, .dismissed:
            // 系统收走（8h/抢占/用户关）：清活动与抑制，
            // 障眼法回落；若人还在前台且闸口径成立，随即
            // 按闸重拉（evaluate 内逐项落 la.gate）。
            activity = nil
            PetIslandLayer.shared.setLiveActivitySuppressed(false)
            Breadcrumbs.log("la.state75 s=\(state == .ended ? "ended" : "dismissed")")
            evaluate(reason: "state-ended")
        default:
            Breadcrumbs.log("la.state75 s=other")
        }
    }
}
