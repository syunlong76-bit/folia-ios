import Foundation
import Combine

/// 下一首预备（3.7 (80) 第 1 项，借鉴 Folium 模组 AI 导演的
/// 「提前为下一首备好」）：当前曲播放期间，把可预判的下一
/// 首（QueueManager.peekNextTrackForCrossfade 口径：loopAll
/// 取模 / off 未到末尾；repeatOne/shuffle 不可预判不备）提
/// 前备齐——
///
/// - 歌词走 LyricRepository 现有 EdgeOne 通路预拉（含逐字
///   YRC 合并，与舞台现拉同一条链、同一张合并表），并预先
///   派生舞台直接消费的行表（LyricParser.stageLines）按
///   trackId 存单槽；切歌时 StageViewController.loadLyrics
///   先查本槽，命中直用（prep.hit80/prep.ms80 量测）。
/// - 该曲有逐歌记忆样式（SongStyleMemory80）时连同预热：
///   网页样式提前确保 WebEffect 特效页装载完成（首装不压
///   切歌瞬间）；原生样式无独立资源装载步（工厂即时构造），
///   预热落点为行表＋样式决定本身，槽内 styleId 供判读。
///
/// 纪律：
/// - 只备一首：队列/下标/模式任一变化即重估——预备目标与
///   当下 peek 不符则作废重备（prep.drop80 留痕）；切歌后
///   槽内若不是刚切到的那首同样作废。
/// - 槽的存活规则：槽属「正在播放的这一首」时不被下一首的
///   预备覆盖——舞台可能整首歌都没开、临开台才来消费；下
///   一首的预备结果此时只入仓库缓存（取数不白费），待本槽
///   被消费/作废后由 refresh 续备。舞台消费后自动续备。
/// - 未命中走原路：loadLyrics 原三级链一字不动，预备失败/
///   未及备完只表现为未命中，不许比原路更慢。
/// - 内存账：单槽只持一首的派生行表（与仓库 8MB 上限、舞台
///   linesCache 同量级的一份），计入全应用 ≤450MB 硬线；
///   仓库条目本身走仓库自有 LRU，不在本槽重复存原始表。
final class NextTrackPrep80 {

    static let shared = NextTrackPrep80()

    struct Prepared {
        let trackId: String
        /// 舞台直接消费的行表（已派生，含逐字戳与 singingRatio）。
        let lines: [LyricLine]
        /// 仓库来源标记（判读对账：lrc+yrc / lrc / none 等）。
        let source: String
        /// 该曲记忆样式（已校验注册表存在且未锁定；无记忆为 nil）。
        let styleId: String?
        let preparedAt: Date
    }

    private let lock = NSLock()
    private var slot: Prepared?
    /// 正在预备的目标（防重复发起；与 slot 分开记——预备中
    /// 槽可能还留着当前曲的那份）。
    private var preparingId: String?
    private var prepTask: Task<Void, Never>?
    private var generation = 0
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - 启动与触发

    /// 进程级启动（AppDelegate 冷启调一次）：订阅当前曲与队
    /// 列三源（queue/currentIndex/playMode），任一变化重估预
    /// 备目标。订阅首发即按当前队列算一次（恢复队列在播时
    /// 同样备上）。
    func startIfNeeded() {
        guard !started else { return }
        started = true
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self else { return }
                // 切歌落地：槽里备的若不是刚切到的这首，是
                // 上一首视角的过期预备，作废（是本首则留给
                // 舞台 consume——舞台可能还没开/还没查）。
                if let track {
                    self.dropSlotIfNotFor(track.id)
                }
                self.refresh()
            }
            .store(in: &cancellables)
        let queueManager = QueueManager.shared
        Publishers.Merge3(
            queueManager.$queue.map { _ in () },
            queueManager.$currentIndex.map { _ in () },
            queueManager.$playMode.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    // MARK: - 舞台取用

    /// 切歌时取用：命中（槽内正是本曲）返回预备并清槽（一
    /// 次性消费——同曲再播要重新备，防陈旧行表跨会话误用）；
    /// 未命中返回 nil，调用方走原路。消费后自动续备下一首。
    func consume(trackId: String) -> Prepared? {
        lock.lock()
        guard let prepared = slot, prepared.trackId == trackId else {
            lock.unlock()
            return nil
        }
        slot = nil
        lock.unlock()
        refresh()
        return prepared
    }

    // MARK: - 内部

    /// 重估：peek 出的下一首与已备/在备目标一致则不动；无可
    /// 预判下一首（队列 ≤1 / repeatOne / shuffle / off 到末
    /// 尾）则作废现有预备。槽属当前曲（待消费）时不因 peek
    /// 变化作废它——它备的是当前曲本身、不是 peek 目标。
    func refresh() {
        guard let next = QueueManager.shared.peekNextTrackForCrossfade() else {
            invalidate(reason: "nonext")
            return
        }
        lock.lock()
        let readyId = slot?.trackId
        let inFlightId = preparingId
        lock.unlock()
        if readyId == next.id || inFlightId == next.id { return }
        prepare(next)
    }

    private func dropSlotIfNotFor(_ trackId: String) {
        lock.lock()
        let stale = slot != nil && slot?.trackId != trackId
        if stale { slot = nil }
        lock.unlock()
        if stale { Breadcrumbs.log("prep.drop80 r=stale") }
    }

    private func invalidate(reason: String) {
        lock.lock()
        let currentId = PlaybackEngine.shared.currentTrack?.id
        // 槽属当前曲时保留：它不是 peek 预备而是当前曲的行
        // 表，作废与否由切歌边沿 dropSlotIfNotFor 决定。
        let slotIsCurrent = slot != nil && slot?.trackId == currentId
        let had = preparingId != nil || (slot != nil && !slotIsCurrent)
        if !slotIsCurrent { slot = nil }
        preparingId = nil
        lock.unlock()
        prepTask?.cancel()
        generation += 1
        if had { Breadcrumbs.log("prep.drop80 r=\(reason)") }
    }

    private func prepare(_ track: FoliaTrack) {
        prepTask?.cancel()
        generation += 1
        let gen = generation
        lock.lock()
        preparingId = track.id
        lock.unlock()
        // 记忆样式预热：先校验存活（注册表在册且未锁定）；
        // 网页样式提前把特效页装载推完，原生样式无此步。
        let remembered = SongStyleMemory80.shared.style(for: track.id)
        let validStyle: String? = remembered.flatMap { id in
            guard LyricStageRegistry.info(for: id) != nil,
                  !LyricStageRegistry.isLocked(id) else { return nil }
            return id
        }
        if let validStyle, StageRuntimeStore.isWeb(validStyle) {
            WebEffectBridge.shared.prewarmEffectPage80()
        }
        Breadcrumbs.log("prep.arm80 track=\(track.id) style=\(validStyle ?? "-")")
        let duration = track.duration
        prepTask = Task { [weak self] in
            // 与舞台现拉同一条仓库链：在途合并保证与 (72)
            // prefetchUpcoming 的预拉不重复发请求。
            let entry = await LyricRepository.shared.entry(for: track.id)
            guard let self, !Task.isCancelled else { return }
            let lines = LyricParser.stageLines(
                from: entry.lines, trackDuration: duration,
                singingRatio: entry.singingRatio)
            // (81) 第 11 条：AI 歌词导演挂预备管线——无手
            // 动记忆时才判定（手动优先的另一半在存储层
            // recordDirector 收口）；判定在本曲播放期间完
            // 成、写入逐歌记忆，切歌边沿由舞台既有套用钩
            // 子读存储生效，槽内 styleId 同步供判读/预热。
            var slotStyle = validStyle
            if slotStyle == nil {
                if let pick = await LyricDirector81.shared.decide(
                    track: track, lines: entry.lines) {
                    SongStyleMemory80.shared.recordDirector(
                        trackId: track.id, styleId: pick.styleId)
                    slotStyle = pick.styleId
                    if StageRuntimeStore.isWeb(pick.styleId) {
                        WebEffectBridge.shared.prewarmEffectPage80()
                    }
                }
            }
            self.lock.lock()
            guard self.generation == gen else {
                self.lock.unlock()
                return
            }
            self.preparingId = nil
            // 存入规则：槽空 → 存；槽属正在播放的曲（待舞台
            // 消费）→ 不覆盖，本结果只入仓库缓存（取数已在
            // entry 时落仓库，不白费）；其余（槽是过期残留）
            // → 覆盖。
            let currentId = PlaybackEngine.shared.currentTrack?.id
            let occupiedByCurrent = self.slot != nil
                && self.slot?.trackId == currentId
                && self.slot?.trackId != track.id
            if !occupiedByCurrent {
                self.slot = Prepared(trackId: track.id, lines: lines,
                                     source: entry.source, styleId: slotStyle,
                                     preparedAt: Date())
            }
            self.lock.unlock()
            Breadcrumbs.log("prep.done80 track=\(track.id) lines=\(lines.count) src=\(entry.source) held=\(occupiedByCurrent ? 0 : 1)")
        }
    }
}
