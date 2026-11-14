// PlaybackEngine.swift
//
// M1 播放内核：A/B 双轨 AVPlayer 封装（native-arch.md §2/§3）。
// - 一期只激活主轨（usingA 固定 true，B 轨不建 item、不发声）；二期 crossfade
//   只加音量渐变定时器，不动本期结构。
// - 状态单一化：isPlaying / rate 不手工置位；两轨各常驻 timeControlStatus KVO，
//   只认 active 轨，三态派生；toggle 只发意图，状态由 KVO 收敛。
// - 双轨各挂 200ms periodic observer，按 active 轨取值。
// - 所有方法须在主线程调用（QueueManager 经 MainActor.run 转发）。
// - AVPlayerItem 一律走 RangeStreamResourceLoader.makeAsset 建 AVURLAsset 再建 item，
//   禁止 AVPlayerItem(url:) 直建。

import AVFoundation
import UIKit

final class PlaybackEngine: NSObject, ObservableObject, AudioPlaybackProtocol {

    static let shared = PlaybackEngine()

    // MARK: - A/B 双轨

    private let playerA = AVPlayer()
    private let playerB = AVPlayer()
    /// 一期固定 true：只激活主轨。B 轨预留给二期 crossfade。
    private var usingA = true
    private var activePlayer: AVPlayer { usingA ? playerA : playerB }
    private var inactivePlayer: AVPlayer { usingA ? playerB : playerA }

    // MARK: - 发布状态（供 M2 迷你条 / 全屏容器订阅；只由 KVO 与 observer 写入）

    @Published private(set) var currentTrack: FoliaTrack?
    @Published private(set) var currentArtwork: UIImage?
    @Published private(set) var playbackState: PlaybackState = .paused
    /// 由 timeControlStatus KVO 派生的镜像标志（唯一写入点是
    /// handleTimeControlStatusChange；play/pause/toggle/load 一律不写它）。
    /// 供 M2 桥订阅 $isPlaying 用；状态单一事实源仍是 playbackState。
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    /// 频谱带：阶段二 POC 通过前恒返回 []。
    var fftBands: [Float] { [] }

    /// 200ms 时间同步回调（供 M2 WebEffectBridge；单消费者，见骨架第二批评审 #3）。
    /// pendingSeek 期间跳过推送；seek 完成回调回推真实位置。
    var onTimeSync: ((TimeInterval, Float) -> Void)?

    /// 完播 / 失败回调，由 QueueManager 注入（唯一改曲方）。
    var onTrackEnded: (() -> Void)?
    var onTrackFailed: ((Error?) -> Void)?

    // MARK: - 内部状态

    private var statusObservations: [NSKeyValueObservation] = []
    private var timeObservers: [Any?] = [nil, nil] // 与 [playerA, playerB] 对齐
    private var endObserver: NSObjectProtocol?
    private var failedToPlayObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var currentItem: AVPlayerItem?

    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    /// seek 竞态三件套之②：pendingSeek 期间周期 observer 跳过推送。
    private var pendingSeek = false

    /// 中断前是否在播（中断结束恢复用）。
    private var wasPlayingBeforeInterruption = false

    /// 聆听累计：单曲累计 >= 15 秒才记 play_history 流水。
    private var listenedSeconds: TimeInterval = 0
    private var lastTickDate: Date?

    private var currentRate: Float { playbackState == .playing ? 1.0 : 0.0 }

    // MARK: - init

    private override init() {
        super.init()
        configureAudioSessionCategory()
        setupTimeControlStatusObservations()
        setupPeriodicTimeObservers()
        setupInterruptionAndRouteObservers()
        setupLifecycleObservers()
    }

    deinit {
        teardownCurrentItemObservers()
        if let token = timeObservers[0] { playerA.removeTimeObserver(token) }
        if let token = timeObservers[1] { playerB.removeTimeObserver(token) }
        [interruptionObserver, routeChangeObserver, backgroundObserver, terminateObserver]
            .compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - AudioPlaybackProtocol：意图方法

    func play() {
        activateSessionIfNeeded()
        activePlayer.play()
        // 状态不手工置位：等 timeControlStatus KVO 收敛为 .playing 后再同步锁屏。
    }

    func pause() {
        activePlayer.pause()
        releaseSessionIfNeeded()
        // 状态不手工置位：等 KVO 收敛为 .paused。
    }

    func togglePlayPause() {
        // 只表达用户意图；状态由 KVO 收敛。
        if playbackState == .playing {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        activePlayer.pause()
        flushListeningHistory(isCompleted: false)
        teardownCurrentItemObservers()
        activePlayer.replaceCurrentItem(with: nil)
        currentTrack = nil
        currentArtwork = nil
        currentTime = 0
        duration = 0
        listenedSeconds = 0
        releaseSessionIfNeeded()
    }

    // MARK: - 唯一改曲入口（internal；唯一调用方是 QueueManager）

    /// 唯一改曲入口。调用图写死：一切改曲 → QueueManager → loadTrackAtCurrentIndex → engine.load。
    /// playableURL 由 QueueManager 按 track id 现换（在线 URL 有效期仅 1200 秒，不落库）。
    func load(track: FoliaTrack, playableURL: URL, artwork: UIImage?) {
        flushListeningHistory(isCompleted: false)
        teardownCurrentItemObservers()

        let asset = RangeStreamResourceLoader.makeAsset(for: playableURL)
        let item = AVPlayerItem(asset: asset)
        currentItem = item
        registerCurrentItemObservers(item)

        currentTrack = track
        currentArtwork = artwork
        duration = track.duration > 0 ? track.duration : 0
        currentTime = 0
        listenedSeconds = 0
        lastTickDate = nil
        pendingSeek = false

        activePlayer.replaceCurrentItem(with: item)
        play()
        // 切歌是离散事件：先推一次乐观锁屏状态（elapsed 0 / rate 1），
        // KVO 收敛后 NowPlayingController 会再同步一次。
        NowPlayingController.shared.syncNowPlaying(elapsed: 0, rate: 1.0)
    }

    /// 封面后到补齐：QueueManager 异步下载到封面后调用；仅当仍是当前曲时生效，
    /// 随后重推一次锁屏（syncNowPlaying 是锁屏唯一写入点）。
    func updateCurrentArtwork(_ image: UIImage?) {
        guard currentTrack != nil, image != nil else { return }
        currentArtwork = image
        NowPlayingController.shared.syncNowPlaying(elapsed: currentTime, rate: currentRate)
    }

    // MARK: - Seek（含竞态三件套）

    func seek(to seconds: TimeInterval) {
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        // ① 松手 seek 时立即推乐观锚点。
        pendingSeek = true
        currentTime = target
        onTimeSync?(target, currentRate)

        // tolerance：本地 .zero 精确 seek；在线放宽 2s（在线精确 seek 易卡顿/久等）。
        let isLocal = currentTrack?.sourceType == .local
        let tolerance = isLocal ? CMTime.zero : CMTime(seconds: 2, preferredTimescale: 600)
        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        activePlayer.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            // ③ 完成回调无论 finished 真假都回推真实位置并 syncNowPlaying。
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingSeek = false
                let real = self.activePlayer.currentTime().seconds
                let resolved = real.isFinite ? real : target
                self.currentTime = resolved
                self.onTimeSync?(resolved, self.currentRate)
                NowPlayingController.shared.syncNowPlaying(elapsed: resolved, rate: self.currentRate)
            }
        }
    }

    // MARK: - Crossfade（阶段二 POC 前只留签名/桩，不实现）

    func prepareCrossfade(to track: FoliaTrack) async -> Bool { false }
    func beginCrossfade(duration: TimeInterval) {}
    func cancelCrossfade() {}
    var isCrossfadeReady: Bool { false }

    // MARK: - KVO：状态由 timeControlStatus 派生

    private func setupTimeControlStatusObservations() {
        for player in [playerA, playerB] {
            let observation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observedPlayer, _ in
                DispatchQueue.main.async {
                    self?.handleTimeControlStatusChange(of: observedPlayer)
                }
            }
            statusObservations.append(observation)
        }
    }

    private func handleTimeControlStatusChange(of player: AVPlayer) {
        // 只认 active 轨；inactive 轨的状态变化不参与派生。
        guard player === activePlayer else { return }
        let derived: PlaybackState
        switch player.timeControlStatus {
        case .playing:
            derived = .playing
        case .paused:
            derived = .paused
        case .waitingToPlayAtSpecifiedRate:
            derived = .waiting
        @unknown default:
            derived = .paused
        }
        guard derived != playbackState else { return }
        playbackState = derived
        // isPlaying 是 playbackState 的派生镜像，只在这里写（KVO 收敛点），
        // 不在 play/pause/toggle/load 里手工置位。
        isPlaying = (derived == .playing)
        // waiting 时锁屏 rate=0（由系统按 rate 外推，200ms 周期不写锁屏）。
        NowPlayingController.shared.syncNowPlaying(elapsed: currentTime, rate: currentRate)
        if derived == .playing { lastTickDate = Date() }
    }

    // MARK: - 200ms 周期 observer（双轨各挂，按 active 取值）

    private func setupPeriodicTimeObservers() {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        let players = [playerA, playerB]
        for (index, player) in players.enumerated() {
            timeObservers[index] = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self else { return }
                // 只认 active 轨；crossfade 期时间源 = 新曲轨（本期 usingA 固定 true）。
                guard player === self.activePlayer else { return }
                // ② pendingSeek 期间跳过推送（防 observer 把进度推回 seek 前）。
                guard !self.pendingSeek else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                self.currentTime = seconds
                if self.playbackState == .playing {
                    let now = Date()
                    if let last = self.lastTickDate {
                        self.listenedSeconds += now.timeIntervalSince(last)
                    }
                    self.lastTickDate = now
                }
                if let itemDuration = self.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0, itemDuration != self.duration {
                    self.duration = itemDuration
                }
                self.onTimeSync?(seconds, self.currentRate)
            }
        }
    }

    // MARK: - 完播 / 失败监听 → QueueManager

    private func registerCurrentItemObservers(_ item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.flushListeningHistory(isCompleted: true)
            self.onTrackEnded?()
        }
        failedToPlayObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self.onTrackFailed?(error)
        }
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            DispatchQueue.main.async {
                guard let self, let item else { return }
                if item.status == .failed {
                    self.onTrackFailed?(item.error)
                } else if item.status == .readyToPlay {
                    let d = item.duration.seconds
                    if d.isFinite, d > 0 { self.duration = d }
                }
            }
        }
    }

    private func teardownCurrentItemObservers() {
        if let token = endObserver { NotificationCenter.default.removeObserver(token) }
        if let token = failedToPlayObserver { NotificationCenter.default.removeObserver(token) }
        endObserver = nil
        failedToPlayObserver = nil
        itemStatusObservation = nil
        currentItem = nil
    }

    // MARK: - AVAudioSession

    /// 只定类别，不激活。激活发生在真正起播时（play），暂停/停止时按需释放；
    /// 不在 init 里 setActive(true) 了事（会立刻打断其他 App 的声音）。
    private func configureAudioSessionCategory() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
        } catch {
            NSLog("[PlaybackEngine] AVAudioSession setCategory failed: \(error.localizedDescription)")
        }
    }

    private func activateSessionIfNeeded() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("[PlaybackEngine] AVAudioSession setActive(true) failed: \(error.localizedDescription)")
        }
    }

    private func releaseSessionIfNeeded() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            NSLog("[PlaybackEngine] AVAudioSession setActive(false) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 中断 / 路由监听

    private func setupInterruptionAndRouteObservers() {
        let session = AVAudioSession.sharedInstance()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = (playbackState == .playing)
            if wasPlayingBeforeInterruption { activePlayer.pause() }
        case .ended:
            guard let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            guard options.contains(.shouldResume), wasPlayingBeforeInterruption else { return }
            wasPlayingBeforeInterruption = false
            // 恢复分支：先 setActive(true) 再 play；激活失败走 log 报错，不静默假装恢复。
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                NSLog("[PlaybackEngine] interruption resume: setActive(true) failed: \(error.localizedDescription)")
                return
            }
            activePlayer.play()
            // 恢复即推锚点，不等下个 200ms tick。
            onTimeSync?(currentTime, currentRate)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // 耳机拔插（旧设备不可用）→ 暂停。
        if reason == .oldDeviceUnavailable, playbackState == .playing {
            pause()
        }
    }

    // MARK: - 生命周期：后台 / 退出时落聆听流水

    private func setupLifecycleObservers() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.flushListeningHistory(isCompleted: false)
        }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.flushListeningHistory(isCompleted: false)
        }
    }

    /// 单曲累计 >= 15 秒才记 play_history 流水；不足 15 秒不记。
    private func flushListeningHistory(isCompleted: Bool) {
        guard let track = currentTrack, listenedSeconds >= 15 else { return }
        DatabaseManager.shared.recordPlayHistory(
            trackId: track.id,
            listenedMs: Int(listenedSeconds * 1000),
            isCompleted: isCompleted
        )
        listenedSeconds = 0
    }
}
