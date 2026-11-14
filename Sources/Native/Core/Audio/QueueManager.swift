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
final class QueueManager {

    static let shared = QueueManager()

    /// M2 桥订阅 $queue / $currentIndex 推 queue 摘要，故用 @Published。
    @Published private(set) var queue: [FoliaTrack] = []
    @Published private(set) var currentIndex: Int = 0

    var currentTrack: FoliaTrack? {
        guard !queue.isEmpty else { return nil }
        return queue[currentIndex % queue.count]
    }

    /// 整队一轮仍无一可播后停止并回调（由 M2/M3 的 UI 层接错误提示）。
    var onFatalError: ((Error) -> Void)?

    private let engine = PlaybackEngine.shared
    private let apiClient = EdgeOneAPIClient.shared

    /// 连续失败计数；成功起播即清零。达到 queue.count 即整队一轮无一可播 → 熔断停播。
    private var consecutiveFailures = 0
    /// 切歌代际令牌：快速连续切歌时，过期 Task 的 load 结果直接丢弃。
    private var loadGeneration = 0

    private init() {
        engine.onTrackEnded = { [weak self] in
            self?.playNext(manual: false)
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

    func setQueue(_ tracks: [FoliaTrack], startingAt index: Int = 0) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.queue = tracks
            self.currentIndex = tracks.isEmpty ? 0 : (index % tracks.count)
            self.consecutiveFailures = 0
            self.updateCommandAvailability()
            self.loadTrackAtCurrentIndex()
        }
    }

    func playNext(manual: Bool) {
        runOnMain { [weak self] in
            guard let self, !self.queue.isEmpty else { return }
            self.currentIndex = (self.currentIndex + 1) % self.queue.count
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

    private func loadTrackAtCurrentIndex() {
        // 本方法只在主线程调（经 runOnMain）。
        guard let track = currentTrack else { return }
        loadGeneration += 1
        let generation = loadGeneration

        Task {
            do {
                let playableURL = try await self.resolvePlayableURL(for: track)
                // 状态变更与 engine.load 一律回主线程（防后台 Task 与主线程竞态）。
                await MainActor.run {
                    // 切歌代际已过期（用户又切了歌）→ 丢弃本次结果。
                    guard generation == self.loadGeneration else { return }
                    self.consecutiveFailures = 0
                    // 曲目元数据入库（仅元数据；remote_stream_url 不写入播放地址）。
                    DatabaseManager.shared.upsertTrack(track)
                    // 封面不阻塞起播：先以 nil 起播，封面到后再补。
                    self.engine.load(track: track, playableURL: playableURL, artwork: nil)
                }
                await self.fetchArtworkIfNeeded(for: track, generation: generation)
            } catch {
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    NSLog("[QueueManager] load failed for \(track.id): \(error.localizedDescription)")
                    self.handleFailure(error)
                }
            }
        }
    }

    /// 按 track id 现换播放地址。在线流走接口现换；本地文件走 DB 查相对路径拼 file URL。
    private func resolvePlayableURL(for track: FoliaTrack) async throws -> URL {
        switch track.sourceType {
        case .netease, .qq, .kugou:
            let rawURL = try await apiClient.fetchSongStreamURL(provider: track.sourceType, songId: track.id)
            return await apiClient.resolvePlayableURL(rawStreamURL: rawURL)
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
