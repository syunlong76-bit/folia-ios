// QueueManager.swift
//
// M1 播放内核：唯一改曲入口（native-arch.md §4）。
// 调用图写死：一切改曲 → QueueManager → loadTrackAtCurrentIndex → engine.load。
// 地址组装归 QueueManager：播放时按 track id 向接口现换 URL（在线 URL 有效期
// 仅 1200 秒），不在 engine 里拼地址，不写死过期 URL。
// 队列语义：列表循环（currentIndex % count）；上一首 >5 秒先回开头；
// 完播 → 下一首；失败跳歌 + 熔断（整队一轮仍无一可播后停并报错）。

import AVFoundation
import UIKit

enum QueueError: Error {
    case emptyQueue
    case localFileMissing(trackId: String)
    case allTracksFailed
}

extension Notification.Name {
    /// 确定性不可播被自动跳过（3.7 (28)）：userInfo 带 trackId。
    /// 墙面据此在既有失败贴纸落点闪现一次无版权贴纸作提示。
    static let foliaTrackSkippedUnplayable = Notification.Name("FoliaTrackSkippedUnplayable")
}

/// 唯一改曲入口。PlaybackEngine 要求主线程调用：本类方法凡触 engine 者，
/// 先经 runOnMain 回到主线程再执行（调用方多为锁屏命令 / 桥回调 / engine 回调，
/// 正常都在主线程，hop 只是兜底）；取流等耗时工作在 Task 里做，状态变更与
/// engine.load 一律经 MainActor.run 回主线程。
final class QueueManager: ObservableObject {

    static let shared = QueueManager()

    /// M2 桥订阅 $queue / $currentIndex 推 queue 摘要，故用 @Published。
    @Published private(set) var queue: [FoliaTrack] = []
    @Published private(set) var currentIndex: Int = 0

    /// 播放模式（3.3 播放页收口新增）：列表循环 / 单曲循环 / 随机。
    enum PlayMode: String {
        case loopAll
        case repeatOne
        case shuffle
        /// 不循环（播放页面板循环磁贴的 off 档）：队列最后一首播完停住。
        case off
    }

    @Published var playMode: PlayMode = .loopAll

    /// 最近一次「用户点播的歌无法播放」的错误文案（UI 展示用）。
    /// 点播失败分两路（3.7 (28) 修订）：确定性不可播（VIP/版权/
    /// 无音源等接口明确信号）顺跳下一首可播的，不停住；瞬时失败
    /// （网络超时/节点故障）仍按 3.2 教训停住报错，不连环跳歌。
    @Published private(set) var lastError: String?

    /// 本次 load 是否来自用户点播（setQueue / insertAndPlay / playAtIndex）。
    /// 自动推进（完播切歌）置 false：失败按老规矩跳歌 + 熔断。
    private var loadIsManual = false

    /// 用户刚点选的曲目尚未成功播出过：此窗口内任何失败（取流失败或
    /// 引擎播流失败）都算点播失败——停住报错，不许连环跳歌把队列跳空、
    /// 最后留一个无标题无提示的黑屏播放页（3.3 真机录屏实证）。
    /// 首次成功起播后清零，回到自动推进的跳歌语义。
    private var manualSelectionPending = false

    var currentTrack: FoliaTrack? {
        guard !queue.isEmpty else { return nil }
        return queue[currentIndex % queue.count]
    }

    /// 整队一轮仍无一可播后停止并回调（由 M2/M3 的 UI 层接错误提示）。
    var onFatalError: ((Error) -> Void)?
    /// 用户点播装载失败回调（3.6 (3)）：桥据此推 playbackError 事件给前端
    /// 展示；旧原生界面走 lastError，全量前端壳没有原生报错面，必须走桥。
    var onManualLoadFailed: ((FoliaTrack) -> Void)?

    private let engine = PlaybackEngine.shared
    private let apiClient = EdgeOneAPIClient.shared

    /// 取流地址缓存（DS26 预取）：展开卡对当前曲预取一次，点播直接
    /// 命中；TTL 10 分钟（与 song/url 的 expi 量级对齐）。锁保护，
    /// 因装载 Task 在后台线程读写。
    private var streamURLCache: [String: (url: URL, fetchedAt: Date)] = [:]
    private var streamPrefetchInFlight: Set<String> = []
    private let streamCacheLock = NSLock()
    private static let streamCacheTTL: TimeInterval = 600

    private func cachedStreamURL(for trackId: String) -> URL? {
        streamCacheLock.lock()
        defer { streamCacheLock.unlock() }
        guard let entry = streamURLCache[trackId],
              Date().timeIntervalSince(entry.fetchedAt) < Self.streamCacheTTL
        else { return nil }
        return entry.url
    }

    private func storeStreamURL(_ url: URL, for trackId: String) {
        streamCacheLock.lock()
        streamURLCache[trackId] = (url, Date())
        streamCacheLock.unlock()
    }

    /// 预取一首的播放地址入缓存（不装载、不起播）。已缓存或在途则跳过。
    func prefetchStream(for track: FoliaTrack) {
        guard track.sourceType != .local else { return }
        let id = track.id
        streamCacheLock.lock()
        let cacheHit = streamURLCache[id].map {
            Date().timeIntervalSince($0.fetchedAt) < Self.streamCacheTTL
        } ?? false
        let shouldFetch = !cacheHit && !streamPrefetchInFlight.contains(id)
        if shouldFetch { streamPrefetchInFlight.insert(id) }
        streamCacheLock.unlock()
        guard shouldFetch else { return }
        Task { [weak self] in
            guard let self else { return }
            var resolved: URL?
            do {
                let raw = try await self.apiClient.fetchSongStreamURL(
                    provider: track.sourceType, songId: id)
                if let cachedResolved = self.apiClient.cachedRangeResolvedURL(rawStreamURL: raw) {
                    resolved = cachedResolved
                } else {
                    Task { _ = await self.apiClient.resolvePlayableURL(rawStreamURL: raw) }
                    resolved = raw
                }
            } catch {
                resolved = nil
            }
            self.streamCacheLock.lock()
            self.streamPrefetchInFlight.remove(id)
            if let resolved { self.streamURLCache[id] = (resolved, Date()) }
            self.streamCacheLock.unlock()
        }
    }

    /// 连续失败计数；成功起播即清零。达到 queue.count 即整队一轮无一可播 → 熔断停播。
    private var consecutiveFailures = 0
    /// 切歌代际令牌：快速连续切歌时，过期 Task 的 load 结果直接丢弃。
    private var loadGeneration = 0

    // MARK: - 队列快照落盘与冷启恢复（3.7 (43) 路2）

    /// 快照键。审计 folia43 路2 定案：队列此前纯内存、无落
    /// 盘无回填，进程死亡后冷启 currentTrack 恒 nil——(41)
    /// 冷启点卡 guard 第一关 100% 判死。本版：队列变更边沿
    /// 写轻量快照，启动回填为「恢复态」（只回填 queue /
    /// currentIndex，不装载、不发声），点卡 route 成功后经
    /// resumeRestoredQueue 现换地址装载、默认保持暂停。
    private static let snapshotKey = "folia.queue.snapshot"
    /// 快照有效期：与在线播放地址有效期同量级（1200s）。
    private static let snapshotTTL: TimeInterval = 1200
    /// 快照条数上限（防超大队列把 UserDefaults 撑爆）。
    private static let snapshotMaxTracks = 500

    /// 快照形状：曲目轻量字段（复用桥 mapPair 的字典口径）。
    /// **playableURL 禁止落盘**——FoliaTrack 本就不含播放地
    /// 址字段，恢复后一律按 id 现换。
    private struct QueueSnapshot: Codable {
        struct TrackDTO: Codable {
            let id: String
            let sourceType: String
            let title: String
            let artist: String
            let album: String
            let duration: TimeInterval
            let artworkURL: String?
            let fee: Int?
        }
        let tracks: [TrackDTO]
        let currentIndex: Int
        let savedAt: TimeInterval
    }

    /// 当前队列处于「冷启恢复态」（已回填、未装载）。
    private(set) var hasRestoredQueue = false

    /// 队列变更边沿调用：写快照；空队列清键。
    private func persistQueueSnapshot() {
        let defaults = UserDefaults.standard
        guard !queue.isEmpty else {
            defaults.removeObject(forKey: Self.snapshotKey)
            return
        }
        let snapshot = QueueSnapshot(
            tracks: queue.prefix(Self.snapshotMaxTracks).map {
                QueueSnapshot.TrackDTO(
                    id: $0.id, sourceType: $0.sourceType.rawValue,
                    title: $0.title, artist: $0.artist, album: $0.album,
                    duration: $0.duration,
                    artworkURL: $0.artworkURL?.absoluteString, fee: $0.fee)
            },
            currentIndex: currentIndex,
            savedAt: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.snapshotKey)
        }
    }

    /// 启动回填（init 内、首激活判定之前）：快照未过期才恢
    /// 复；只回填队列与下标，不调 engine.load、不发声。
    private func restoreQueueSnapshotIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let snapshot = try? JSONDecoder().decode(QueueSnapshot.self, from: data)
        else { return }
        guard Date().timeIntervalSince1970 - snapshot.savedAt < Self.snapshotTTL,
              !snapshot.tracks.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
            return
        }
        queue = snapshot.tracks.compactMap { dto in
            guard let source = AudioSourceType(rawValue: dto.sourceType)
            else { return nil }
            return FoliaTrack(
                id: dto.id, sourceType: source, title: dto.title,
                artist: dto.artist, album: dto.album,
                duration: dto.duration,
                artworkURL: dto.artworkURL.flatMap { URL(string: $0) },
                fee: dto.fee)
        }
        guard !queue.isEmpty else { return }
        currentIndex = min(max(snapshot.currentIndex, 0), queue.count - 1)
        hasRestoredQueue = true
        updateCommandAvailability()
        Breadcrumbs.log("queue.restore snapshot n=\(queue.count) at=\(currentIndex)")
    }

    /// 冷启恢复态装载（route 成功落到播放页后由 SceneDelegate
    /// 调用）：走唯一改曲路径现换地址装载当前曲；装载落地
    /// 后立即暂停——**默认保持暂停（已定）**：进程死亡前的
    /// 播/停状态不可知，点卡意图是「打开播放页」，自动出声
    /// 不可逆、更冒犯。非恢复态调用为无操作。
    func resumeRestoredQueue() {
        runOnMain { [weak self] in
            guard let self, self.hasRestoredQueue else { return }
            self.hasRestoredQueue = false
            guard let target = self.currentTrack else { return }
            self.loadIsManual = true
            self.manualSelectionPending = true
            self.loadTrackAtCurrentIndex()
            // engine.load 在装载 Task 落地时内部起播，暂停须
            // 等落地：轮询本曲成为 engine 当前曲后 pause 一
            // 次；代际被新装载顶替（用户已自行操作/自动顺
            // 跳）即放弃，不与用户抢。
            let generation = self.loadGeneration
            var attempts = 0
            func pauseWhenLoaded() {
                attempts += 1
                guard generation == self.loadGeneration else { return }
                if self.engine.currentTrack?.id == target.id {
                    self.engine.pause()
                    Breadcrumbs.log("queue.restore resumed-paused track=\(target.id)")
                    return
                }
                if attempts < 40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        pauseWhenLoaded()
                    }
                }
            }
            pauseWhenLoaded()
        }
    }

    private init() {
        engine.onTrackEnded = { [weak self] in
            guard let self else { return }
            if self.playMode == .repeatOne {
                // 单曲循环：回开头续播同一首（地址不重换，条目仍在引擎里）。
                self.engine.seek(to: 0)
                self.engine.play()
                return
            }
            if self.playMode == .off {
                // 不循环：最后一首播完停住；未到末尾照常推进（playNext 的
                // 取模绕回只会在手动切歌时触发，自动推进到末尾前不会绕）。
                if self.currentIndex >= self.queue.count - 1 {
                    self.stop()
                    return
                }
                self.playNext(manual: false)
                return
            }
            self.playNext(manual: false)
        }
        engine.onTrackFailed = { [weak self] error in
            self?.handleFailure(error)
        }
        NowPlayingController.shared.onNextTrack = { [weak self] in
            self?.playNext(manual: true)
        }
        NowPlayingController.shared.onPreviousTrack = { [weak self] in
            self?.playPrevious()
        }
        // 冷启队列回填（3.7 (43) 路2）：单例首次被触达即恢复，
        // 保证 SceneDelegate 首激活的 hasQueue 判定读到恢复态。
        restoreQueueSnapshotIfNeeded()
    }

    /// 主线程兜底：已在主线程直接执行，否则异步跳主线程再执行。
    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    // MARK: - 测试队列（M1 最小闭环）

    /// 网易云可播测试曲：id 1973665667《海屿你》（fee=8，现换成功；实测
    /// /song/url/v1 回真实 URL code:200，expi=1200 秒）。
    /// VIP 曲 fee=1 回 url:null/code:404，不可入队——不要把 VIP 曲放进测试队列。
    /// 注意：搜索接口不返回专辑 picUrl，本测试曲 artworkURL 暂为 nil（锁屏无封面，
    /// 待 M3 封面链路补齐）。
    static func testQueue() -> [FoliaTrack] {
        [FoliaTrack(
            id: "ncm_1973665667",
            sourceType: .netease,
            title: "海屿你",
            artist: "马也_Crabbit",
            album: "海屿你",
            duration: 295.94,
            artworkURL: nil
        )]
    }

    /// M1 闭环入口：装载测试队列并起播《海屿你》。M2 桥接通后由桥调用。
    func playTestQueue() {
        setQueue(Self.testQueue(), startingAt: 0)
    }

    // MARK: - 队列操作

    /// source（DS26 丙路线最小埋点）：队列变更来源标记，进桥日志，
    /// 日后若真出现队列竞争，凭来源/时序即可判责，不必再猜。
    func setQueue(_ tracks: [FoliaTrack], startingAt index: Int = 0, source: String = "core") {
        runOnMain { [weak self] in
            guard let self else { return }
            FoliaBridgeLogStore.shared.write(
                level: "info", module: "queue",
                message: "setQueue source=\(source) count=\(tracks.count) start=\(index)")
            Breadcrumbs.log("setQueue n=\(tracks.count) at=\(index) src=\(source)")
            // 真实点播接管：恢复态作废（本入口自会装载）。
            self.hasRestoredQueue = false
            self.queue = tracks
            self.currentIndex = tracks.isEmpty ? 0 : (index % tracks.count)
            self.consecutiveFailures = 0
            self.loadIsManual = true
            self.manualSelectionPending = true
            self.updateCommandAvailability()
            self.persistQueueSnapshot()
            self.loadTrackAtCurrentIndex()
        }
    }

    /// 全量队列静默替换（3.6 全量前端 setQueue 消息专用）：网页侧队列变异后
    /// 全量重发，原生只换队列与下标，不打断正在播的歌。
    /// - 当前曲在新队列的 currentIndex 处仍是同一首：只换队列/下标。
    /// - 引擎尚无当前曲（冷启恢复等）：只换队列/下标，不起播。
    /// - 当前曲已被移出/替换且引擎有歌在手：装载新当前曲（与网页 deck
    ///   移除当前曲后自动落到下一首的行为对齐）。
    /// - 空队列：只清队列/下标，引擎不动（网页清队列不等于停播）。
    func replaceQueueSilently(_ tracks: [FoliaTrack], currentIndex index: Int) {
        runOnMain { [weak self] in
            guard let self else { return }
            if tracks.isEmpty {
                self.queue = []
                self.currentIndex = 0
                self.updateCommandAvailability()
                self.persistQueueSnapshot()
                return
            }
            let clamped = min(max(index, 0), tracks.count - 1)
            let currentId = self.engine.currentTrack?.id
            self.queue = tracks
            self.currentIndex = clamped
            self.updateCommandAvailability()
            self.persistQueueSnapshot()
            if let currentId, tracks[clamped].id != currentId {
                self.loadIsManual = true
                self.manualSelectionPending = true
                self.loadTrackAtCurrentIndex()
            }
        }
    }

    /// 跳到队列中指定位置播放（原生队列页点选）。
    func playAtIndex(_ index: Int) {
        runOnMain { [weak self] in
            guard let self, self.queue.indices.contains(index) else { return }
            self.hasRestoredQueue = false
            self.currentIndex = index
            self.consecutiveFailures = 0
            self.loadIsManual = true
            self.manualSelectionPending = true
            self.updateCommandAvailability()
            self.persistQueueSnapshot()
            self.loadTrackAtCurrentIndex()
        }
    }

    /// 从队列移除一首（播放页队列页签的 queueRemove 用）。移除当前曲时装载
    /// 落到该位置的下一首（越界回落最后一首）；队列清空则停播；移除当前曲
    /// 之前的歌只平移下标，不打断播放。
    func removeFromQueue(at index: Int) {
        runOnMain { [weak self] in
            guard let self, self.queue.indices.contains(index) else { return }
            let wasCurrent = index == self.currentIndex
            self.queue.remove(at: index)
            if self.queue.isEmpty {
                self.currentIndex = 0
                self.consecutiveFailures = 0
                self.updateCommandAvailability()
                self.persistQueueSnapshot()
                self.engine.stop()
                return
            }
            if index < self.currentIndex {
                self.currentIndex -= 1
                self.updateCommandAvailability()
                self.persistQueueSnapshot()
            } else if wasCurrent {
                self.currentIndex = min(self.currentIndex, self.queue.count - 1)
                self.consecutiveFailures = 0
                self.loadIsManual = false
                self.updateCommandAvailability()
                self.persistQueueSnapshot()
                self.loadTrackAtCurrentIndex()
            } else {
                self.updateCommandAvailability()
                self.persistQueueSnapshot()
            }
        }
    }

    func playNext(manual: Bool) {
        runOnMain { [weak self] in
            guard let self, !self.queue.isEmpty else { return }
            if self.playMode == .shuffle, self.queue.count > 1 {
                var next = self.currentIndex
                while next == self.currentIndex {
                    next = Int.random(in: 0..<self.queue.count)
                }
                self.currentIndex = next
            } else {
                self.currentIndex = (self.currentIndex + 1) % self.queue.count
            }
            self.loadIsManual = false
            self.updateCommandAvailability()
            self.persistQueueSnapshot()
            self.loadTrackAtCurrentIndex()
        }
    }

    func playPrevious() {
        runOnMain { [weak self] in
            guard let self, !self.queue.isEmpty else { return }
            // 当前播放 >5 秒先回开头，否则切上一首。
            if self.engine.currentTime > 5 {
                self.engine.seek(to: 0)
                return
            }
            self.currentIndex = (self.currentIndex - 1 + self.queue.count) % self.queue.count
            self.loadIsManual = false
            self.updateCommandAvailability()
            self.persistQueueSnapshot()
            self.loadTrackAtCurrentIndex()
        }
    }

    /// 追加到队尾（去重，不打断当前播放；3.2 桥 addToQueue 用）。
    func appendToQueue(_ tracks: [FoliaTrack]) {
        runOnMain { [weak self] in
            guard let self else { return }
            let existing = Set(self.queue.map(\.id))
            let fresh = tracks.filter { !existing.contains($0.id) }
            guard !fresh.isEmpty else { return }
            self.queue.append(contentsOf: fresh)
            self.updateCommandAvailability()
            self.persistQueueSnapshot()
        }
    }

    /// 插入并立即播放（3.2 桥 addAndPlay 用）：已在队内则跳过去播，
    /// 否则插到当前曲之后并切过去。
    func insertAndPlay(_ track: FoliaTrack) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.hasRestoredQueue = false
            if let idx = self.queue.firstIndex(where: { $0.id == track.id }) {
                self.currentIndex = idx
            } else if self.queue.isEmpty {
                self.queue = [track]
                self.currentIndex = 0
            } else {
                let at = self.currentIndex + 1
                self.queue.insert(track, at: at)
                self.currentIndex = at
            }
            self.consecutiveFailures = 0
            self.loadIsManual = true
            self.manualSelectionPending = true
            self.updateCommandAvailability()
            self.persistQueueSnapshot()
            self.loadTrackAtCurrentIndex()
        }
    }

    func stop() {
        runOnMain { [weak self] in
            guard let self else { return }
            self.consecutiveFailures = 0
            self.engine.stop()
        }
    }

    // MARK: - 唯一改曲路径

    /// 装载失败四分（DS26 埋点）：取流被拒（VIP/版权/匿名拿不到地址）
    /// 与网络超时在修法上完全不同，日志里必须分开记。
    private static func loadErrorClass(_ error: Error) -> String {
        if let edgeError = error as? EdgeOneError {
            switch edgeError {
            case .streamURLMissing: return "auth-missing"
            case .allNodesFailed: return "timeout-or-nodes"
            case .invalidResponse: return "network"
            case .providerUnverified: return "other"
            }
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut ? "timeout" : "network"
        }
        return "other"
    }

    private func loadTrackAtCurrentIndex() {
        // 本方法只在主线程调（经 runOnMain）。
        guard let track = currentTrack else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let manual = loadIsManual
        let resolveStart = Date()

        Task {
            do {
                let playableURL = try await self.resolvePlayableURL(for: track)
                // 状态变更与 engine.load 一律回主线程（防后台 Task 与主线程竞态）。
                await MainActor.run {
                    // 切歌代际已过期（用户又切了歌）→ 丢弃本次结果。
                    guard generation == self.loadGeneration else { return }
                    self.consecutiveFailures = 0
                    self.lastError = nil
                    self.manualSelectionPending = false
                    // 曲目元数据入库（仅元数据；remote_stream_url 不写入播放地址）。
                    DatabaseManager.shared.upsertTrack(track)
                    // 本机播放记录（探索页「最近播放 / 再听一次」自有分区的数据源）：
                    // 取流成功、即将起播 = 一次成功起播，记在这里改动最小。
                    PlayHistoryStore.shared.recordPlay(track)
                    // 封面不阻塞起播：先以 nil 起播，封面到后再补。
                    self.engine.load(track: track, playableURL: playableURL, artwork: nil)
                    // 取流耗时埋点（DS26）：与失败分类成对，判冷热节点与缓存命中。
                    let resolveMs = Int(Date().timeIntervalSince(resolveStart) * 1000)
                    FoliaBridgeLogStore.shared.write(
                        level: "info", module: "queue",
                        message: "load ok track=\(track.id) resolveMs=\(resolveMs)")
                }
                await self.fetchArtworkIfNeeded(for: track, generation: generation)
            } catch {
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    NSLog("[QueueManager] load failed for \(track.id): \(error.localizedDescription)")
                    // 失败分类埋点（DS26）：timeout / auth-missing / network /
                    // other 四分，下一轮按类定修法（尤其 (d) Cookie 路径
                    // 是否立项，只看 auth-missing 占比）。
                    let resolveMs = Int(Date().timeIntervalSince(resolveStart) * 1000)
                    FoliaBridgeLogStore.shared.write(level: "warn", module: "queue",
                        message: "load failed track=\(track.id) manual=\(manual) class=\(Self.loadErrorClass(error)) resolveMs=\(resolveMs) error=\(error.localizedDescription)")
                    if manual {
                        if Self.isDeterministicallyUnplayable(error) {
                            // 点播到的歌确定性不可播（3.7 (28)）：顺跳
                            // 下一首可播的，不停在失败态；连跳由熔断
                            // 封顶（整队一轮无一可播才停并报错）。
                            self.skipUnplayableLoad(error: error, track: track)
                        } else {
                            // 瞬时失败（网络超时/节点故障）：停住报错，
                            // 不连环跳歌（3.2 录屏里歌名闪切的教训）。
                            self.consecutiveFailures = 0
                            self.manualSelectionPending = false
                            self.engine.stop()
                            self.lastError = "《\(track.title)》暂时无法播放，可能需要 VIP 或受版权限制"
                            self.onManualLoadFailed?(track)
                        }
                    } else if Self.isDeterministicallyUnplayable(error) {
                        // 自动推进/手动切歌落到不可播歌：同样顺跳，
                        // 跳过闪现由墙面订阅通知处理；熔断判定在
                        // handleFailure 内，本次将触发熔断时不闪现
                        // （持久失败态接管提示）。
                        if self.consecutiveFailures + 1 < self.queue.count {
                            self.notifySkippedUnplayable(track)
                        }
                        self.handleFailure(error)
                    } else {
                        self.handleFailure(error)
                    }
                }
            }
        }
    }

    /// 按 track id 现换播放地址。在线流走接口现换；本地文件走 DB 查相对路径拼 file URL。
    private func resolvePlayableURL(for track: FoliaTrack) async throws -> URL {
        switch track.sourceType {
        case .netease, .qq, .kugou:
            if let cached = cachedStreamURL(for: track.id) { return cached }
            let rawURL = try await apiClient.fetchSongStreamURL(provider: track.sourceType, songId: track.id)
            // Range 探测后置（DS26）：探明过的 host 按缓存改写；未探明
            // 先按原地址起播，后台探热供后续曲目，不挡本次起播。
            let resolved: URL
            if let cachedResolved = apiClient.cachedRangeResolvedURL(rawStreamURL: rawURL) {
                resolved = cachedResolved
            } else {
                Task { _ = await apiClient.resolvePlayableURL(rawStreamURL: rawURL) }
                resolved = rawURL
            }
            storeStreamURL(resolved, for: track.id)
            return resolved
        case .local:
            guard let relPath = DatabaseManager.shared.localAudioRelPath(trackId: track.id) else {
                throw QueueError.localFileMissing(trackId: track.id)
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documents.appendingPathComponent(relPath)
        }
    }

    /// 封面异步补齐：下载成功且仍是当前曲时，更新 engine 封面并重推锁屏。
    /// 代际判定回主线程做（loadGeneration 只在主线程写）。
    ///
    /// 3.7 (40) 项5（审计 nowplaying-audit-2026-11-20 失败二）：原实现
    /// 三个出口全静默（artworkURL 为 nil / try? 吞下载失败 / 代际守卫
    /// 丢弃），且与墙面是两条独立链——锁屏链每首歌裸 URLSession 直下、
    /// 无复用，静默失败时「墙上有封面、锁屏没有」可长期并存。本版：
    /// ①每个出口各打一条 artwork.fetch 面包屑，下次导出一次定案；
    /// ②下载改走 NativeCoverLoader 的代理/缓存链（见下），不再裸直下；
    /// ③http→https 升级在加载器内已有（proxiedURLString 内部
    /// upgradedHTTPS / upgradedImgPath），主路径依赖它、不再自升；
    /// 仅加载器给不出代理地址时回退的直下分支保留原升级逻辑。
    ///
    /// 线程/隔离：本函数是 nonisolated async（由 loadTrackAtCurrentIndex
    /// 的 Task await 调用）；NativeCoverLoader 是 nonisolated final class，
    /// 其 NSCache 与 URLSession 均为线程安全构件，image(for:tier:)
    /// 本身先查内存缓存、下载与解码都在其内部完成——从本上下文直接
    /// await 与 StageViewController.loadBackdropFallback 的 Task 内
    /// 调用同构，不引入新的数据竞争；触 engine 的落地仍经 MainActor.run。
    private func fetchArtworkIfNeeded(for track: FoliaTrack, generation: Int) async {
        guard let rawArtworkURL = track.artworkURL else {
            Breadcrumbs.log("artwork.fetch songId=\(track.id) result=nil-url")
            return
        }
        let raw = rawArtworkURL.absoluteString
        var image: UIImage?
        // source 标记本次实际走的取图路径，随 landed/stale/download-failed
        // 一并入面包屑，区分缓存/代理链与回退直下。
        var source = "loader"
        // 主路径：NativeCoverLoader。档位用 wallTier(raw, 600)：/img 形态
        // 沿用地址内嵌档（曲目 picUrl 640）——与墙面 cell 的缓存键完全
        // 一致，墙已解码的图直接命中其内存缓存；非 /img 形态按 600
        // （锁屏封面最大边，见 NowPlayingController）选档得 1024。
        // image(for:tier:) 内部先查缓存、未命中才经 LocalServer /img
        // 代理下载（代理侧另有磁盘缓存）并降采样回填缓存。
        let loader = NativeCoverLoader.shared
        let tier = NativeCoverLoader.wallTier(raw: raw, pixelExtent: 600)
        if let proxied = loader.proxiedURLString(raw, tier: tier) {
            image = await loader.image(for: proxied, tier: tier)
            if image == nil {
                // 精确档下载失败时再捞任一档的已缓存图（仍算 loader 路）：
                // 墙解码过任一档都不该让锁屏继续灰着。
                image = loader.cachedImageAnyTier(raw: raw, excludingTier: tier)
            }
        } else {
            // 加载器给不出代理地址（LocalServer 端口未就绪，或地址非
            // /img 与 http(s) 形态）：回退原裸直下路径。3.7 (31) 的
            // http→https 升级只在此分支保留（主路径由加载器内部升级）：
            // 歌单详情内嵌 tracks 的 al.picUrl 是 http:// 明文，ATS 只给
            // 本机开例外，不升级会被系统拦死。
            source = "direct"
            let artworkURL: URL
            if rawArtworkURL.scheme == "http",
               let upgraded = URL(string: "https://" + rawArtworkURL.absoluteString.dropFirst(7)) {
                artworkURL = upgraded
            } else {
                artworkURL = rawArtworkURL
            }
            if let (data, _) = try? await URLSession.shared.data(from: artworkURL) {
                image = UIImage(data: data)
            }
        }
        guard let image else {
            Breadcrumbs.log("artwork.fetch songId=\(track.id) result=download-failed source=\(source)")
            return
        }
        await MainActor.run {
            guard generation == self.loadGeneration,
                  self.engine.currentTrack?.id == track.id else {
                Breadcrumbs.log("artwork.fetch songId=\(track.id) result=stale source=\(source)")
                return
            }
            self.engine.updateCurrentArtwork(image)
            Breadcrumbs.log("artwork.fetch songId=\(track.id) result=landed source=\(source)")
        }
    }

    // MARK: - 确定性不可播分类 + 点播顺跳（3.7 (28)）

    /// 确定性不可播判定：只认接口明确信号——取流被拒（VIP/版权
    /// 致 url 为空，EdgeOneError.streamURLMissing）、平台取流未
    /// 提供（providerUnverified，重试永不会成功）、本地文件缺失
    /// （QueueError.localFileMissing）。网络超时、双节点失败、
    /// 响应异常、URLError 一律不算：那是瞬时失败，抖动一下就
    /// 跳歌会把可播的歌误杀。引擎播流阶段的失败（onTrackFailed）
    /// 无接口信号可判，不走本分类，保持既有处理。
    private static func isDeterministicallyUnplayable(_ error: Error) -> Bool {
        if let edgeError = error as? EdgeOneError {
            switch edgeError {
            case .streamURLMissing, .providerUnverified: return true
            case .allNodesFailed, .invalidResponse: return false
            }
        }
        if let queueError = error as? QueueError {
            switch queueError {
            case .localFileMissing: return true
            case .emptyQueue, .allTracksFailed: return false
            }
        }
        return false
    }

    /// 跳过闪现通知（墙面在既有失败贴纸落点闪现一次作提示）。
    private func notifySkippedUnplayable(_ track: FoliaTrack) {
        Breadcrumbs.log("queue skip unplayable track=\(track.id)")
        NotificationCenter.default.post(
            name: .foliaTrackSkippedUnplayable, object: self,
            userInfo: ["trackId": track.id])
    }

    /// 点播顺跳：用户点中的歌确定性不可播时调用（主线程）。
    /// 熔断口径与自动跳歌共用 consecutiveFailures：整队一轮无一
    /// 可播 → 停住、报错、回既有失败态；未熔断 → 发闪现通知后
    /// 按当前模式推进下一首（playNext 内含随机模式取序；单曲
    /// 循环模式下本曲不可播同样顺跳，不死循环重播本曲）。
    private func skipUnplayableLoad(error: Error, track: FoliaTrack) {
        consecutiveFailures += 1
        manualSelectionPending = false
        if consecutiveFailures >= queue.count {
            consecutiveFailures = 0
            engine.stop()
            NSLog("[QueueManager] manual skip exhausted queue: \(error.localizedDescription)")
            lastError = "《\(track.title)》暂时无法播放，可能需要 VIP 或受版权限制"
            onManualLoadFailed?(track)
            onFatalError?(error)
            return
        }
        notifySkippedUnplayable(track)
        playNext(manual: false)
    }

    // MARK: - 失败跳歌 + 熔断

    private func handleFailure(_ error: Error?) {
        // 熔断与跳歌触 engine，必须在主线程；engine 回调已在主线程，
        // Task catch 路径经 MainActor.run 进来，runOnMain 是兜底。
        runOnMain { [weak self] in
            guard let self, !self.queue.isEmpty else { return }
            if self.manualSelectionPending {
                // 用户点选的歌在播流阶段失败：同点播失败处理，停住报错，
                // 不进跳歌循环（跳空队列会留下无标题无提示的黑屏播放页）。
                self.manualSelectionPending = false
                self.consecutiveFailures = 0
                self.engine.stop()
                if let track = self.currentTrack {
                    self.lastError = "《\(track.title)》暂时无法播放，可能需要 VIP 或受版权限制"
                    self.onManualLoadFailed?(track)
                }
                return
            }
            self.consecutiveFailures += 1
            if self.consecutiveFailures >= self.queue.count {
                // 整队一轮仍无一可播 → 停并报错，不无限循环。
                let failure = error ?? QueueError.allTracksFailed
                self.consecutiveFailures = 0
                self.engine.stop()
                NSLog("[QueueManager] circuit breaker: no playable track in queue: \(failure.localizedDescription)")
                self.onFatalError?(failure)
                return
            }
            self.playNext(manual: false)
        }
    }

    // MARK: - 锁屏命令可用性（循环模式）

    private func updateCommandAvailability() {
        // 列表循环：队内多于 1 首时上下首都可用；单曲/空队禁用。
        let canMove = queue.count > 1
        NowPlayingController.shared.updateCommandAvailability(canGoNext: canMove, canGoPrevious: canMove)
    }
}
