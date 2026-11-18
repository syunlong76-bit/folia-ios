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
    /// 点播失败不再连环跳歌：停住、报错，等用户自己选下一首（3.2 教训）。
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
            self.queue = tracks
            self.currentIndex = tracks.isEmpty ? 0 : (index % tracks.count)
            self.consecutiveFailures = 0
            self.loadIsManual = true
            self.manualSelectionPending = true
            self.updateCommandAvailability()
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
                return
            }
            let clamped = min(max(index, 0), tracks.count - 1)
            let currentId = self.engine.currentTrack?.id
            self.queue = tracks
            self.currentIndex = clamped
            self.updateCommandAvailability()
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
            self.currentIndex = index
            self.consecutiveFailures = 0
            self.loadIsManual = true
            self.manualSelectionPending = true
            self.updateCommandAvailability()
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
                self.engine.stop()
                return
            }
            if index < self.currentIndex {
                self.currentIndex -= 1
                self.updateCommandAvailability()
            } else if wasCurrent {
                self.currentIndex = min(self.currentIndex, self.queue.count - 1)
                self.consecutiveFailures = 0
                self.loadIsManual = false
                self.updateCommandAvailability()
                self.loadTrackAtCurrentIndex()
            } else {
                self.updateCommandAvailability()
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
        }
    }

    /// 插入并立即播放（3.2 桥 addAndPlay 用）：已在队内则跳过去播，
    /// 否则插到当前曲之后并切过去。
    func insertAndPlay(_ track: FoliaTrack) {
        runOnMain { [weak self] in
            guard let self else { return }
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
                        // 用户点播的歌拿不到地址（VIP / 版权 / 下架）：停住报错，
                        // 不连环跳歌（3.2 录屏里歌名闪切的教训）。
                        self.consecutiveFailures = 0
                        self.manualSelectionPending = false
                        self.engine.stop()
                        self.lastError = "《\(track.title)》暂时无法播放，可能需要 VIP 或受版权限制"
                        self.onManualLoadFailed?(track)
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
    private func fetchArtworkIfNeeded(for track: FoliaTrack, generation: Int) async {
        guard let artworkURL = track.artworkURL else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: artworkURL),
              let image = UIImage(data: data) else { return }
        await MainActor.run {
            guard generation == self.loadGeneration,
                  self.engine.currentTrack?.id == track.id else { return }
            self.engine.updateCurrentArtwork(image)
        }
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
