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

    /// 歌词行边界回调（3.6 (3)），由 WebEffectBridge 注入：音频时钟跨过
    /// 前端注册的行界时回调 (cueId, cueTime)，桥转成 cue 事件钉前端锚点。
    var onLyricCue: ((String, TimeInterval) -> Void)?

    /// 前端注册的歌词行界表（按 trackId 绑定，切歌自动失效）。
    private var lyricCues: (trackId: String, cues: [(id: String, time: TimeInterval)])?
    private var cueBoundaryObserver: Any?
    private var cueFiredThroughIndex = -1

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

    /// 真实 playhead（3.7 (17)）：直读 active 轨 AVPlayer 时钟。
    /// @Published currentTime 是 200ms 周期 observer 的台阶缓存，
    /// 相对真值恒有 0–200ms 滞后；歌词时钟锚点与面包屑对账必须
    /// 读真值（引擎内部布防/回正已有直读先例：armLyricCues、
    /// seek 完成回调）。无 item 或时钟无效时回落缓存值。
    /// 须主线程调用（与本类其余方法同一约定）。
    func rawPlayhead() -> TimeInterval {
        let raw = activePlayer.currentTime().seconds
        return raw.isFinite ? raw : currentTime
    }

    /// seek 在途标志（竞态三件套之②的对外只读面）：歌词时钟在
    /// seek 落点未定期间暂停漂移重锚，防乐观锚点引发的行判定抖动。
    var isSeekPending: Bool { pendingSeek }

    /// 墙链歌词 boundary 锚定（3.7 (21)）的注册面：active 轨只读
    /// 引用。墙链的行界 observer 直接挂这台 player（与桥 cue 的
    /// lyricCues 互不干扰、两套 observer 并存）；注册/消费/护栏
    /// 归 LyricBoundaryFlipDriver，引擎不感知。一期 usingA 固定，
    /// 返回恒为 playerA；二期双轨切换时消费方按身份变化重注册。
    var lyricBoundaryPlayer: AVPlayer { activePlayer }

    // MARK: - init

    private override init() {
        super.init()
        configureAudioSessionCategory()
        setupTimeControlStatusObservations()
        setupPeriodicTimeObservers()
        setupInterruptionAndRouteObservers()
        setupLifecycleObservers()
        // (62) WB：后台节流策略层与外部舞台数据源的冷启恢复
        // （引擎是冷启必经的单例，在此装配一次）。
        BackgroundThrottle62.install()
        StageDataSource62.shared.startIfEnabled()
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
        // (62) WB：淡出途中被重新起播时，先废掉淡出斜坡并恢
        // 复有效音量，防旧计时器稍后把已恢复的播放又暂停。
        if fadeTimer != nil {
            fadeTimer?.invalidate()
            fadeTimer = nil
            applyEffectiveVolume()
        }
        // (62) WB §4.5：播放淡入——时长键 playPauseFadeMs（默
        // 认 200ms）；过渡进行中或已在播时不走斜坡，直达 play。
        let fade = fadeDuration()
        guard fade > 0, currentTrack != nil, playbackState != .playing,
              crossfadeContext == nil else {
            activePlayer.play()
            return
        }
        activePlayer.volume = 0
        activePlayer.play()
        rampActiveVolume(to: effectiveVolume(), duration: fade)
        // 状态不手工置位：等 timeControlStatus KVO 收敛为 .playing 后再同步锁屏。
    }

    func pause() {
        // (62) WB §4.5：暂停淡出——斜坡到 0 后再真 pause，完
        // 成后恢复有效音量待下次起播（起播侧另有淡入斜坡）。
        let fade = fadeDuration()
        if fade > 0, playbackState == .playing, crossfadeContext == nil {
            rampActiveVolume(to: 0, duration: fade) { [weak self] in
                guard let self else { return }
                self.activePlayer.pause()
                self.applyEffectiveVolume()
            }
            return
        }
        activePlayer.pause()
        // 3.6 (3)：暂停不再停用音频会话。有曲目在手时保持会话激活，App 才
        // 稳定保持「正在播放应用」身份，锁屏/控制中心（含上一首/下一首）
        // 不会因暂停被系统收走；会话只在 stop()（无曲目）时释放。
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

    /// 播放音量 0...1（两轨统一；播放页面板 VolumeRow 经 foliaNative 通道下发，
    /// 用的是 AVPlayer 本级音量，不动系统音量）。A/B 两台 player 是常驻实例，
    /// 切歌不换实例，设一次即长期有效；快照经 bridge 回报给网页面板回显。
    @Published private(set) var volume: Float = 1.0

    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        applyEffectiveVolume()
    }

    // MARK: - (62) WB：ReplayGain 与有效音量

    /// ReplayGain 增益系数（线性）。来源优先级（任务定死）：
    /// ① WC 的 VolumeBalanceStore62 学习偏移（逐曲）② 曲目
    /// 元数据 gain（FoliaTrack 现无 gain 字段，此级恒缺省，
    /// 待模型补字段后在此接入）③ 1.0。
    /// 学习偏移的量纲假设：dB（音量平衡学习惯例），换算
    /// factor = 10^(dB/20)，夹 [0.25, 4]；原始值落面包屑供
    /// 真机对账量纲是否一致。
    private var replayGainFactor: Float = 1.0

    /// 当前应作用于两台 player 的音量 = 用户音量 × 增益。
    private func effectiveVolume() -> Float {
        min(max(volume * replayGainFactor, 0), 1)
    }

    private func applyEffectiveVolume() {
        let value = effectiveVolume()
        playerA.volume = value
        playerB.volume = value
    }

    /// 重算当前曲的增益系数并应用（切歌与设置开关变更时调）。
    /// 符号依赖：VolumeBalanceStore62 由 WC 簇提供（同模块合
    /// 并后链接）；本函数是全仓唯一调用点，若 WC 符号未就绪
    /// 只需在此一处兜底。
    func refreshReplayGain() {
        guard SettingsStore.replayGainEnabled, let track = currentTrack else {
            replayGainFactor = 1.0
            applyEffectiveVolume()
            return
        }
        let learnedDb = VolumeBalanceStore62.shared.learnedOffset(forTrackKey: track.id)
        if learnedDb != 0 {
            replayGainFactor = min(max(powf(10, learnedDb / 20), 0.25), 4)
            Breadcrumbs.log("replayGain62 track=\(track.id) src=learned dB=\(learnedDb) factor=\(replayGainFactor)")
        } else {
            replayGainFactor = 1.0
            Breadcrumbs.log("replayGain62 track=\(track.id) src=none factor=1.0")
        }
        applyEffectiveVolume()
    }

    // MARK: - (62) WB：播放/暂停淡变斜坡

    private var fadeTimer: Timer?

    private func fadeDuration() -> TimeInterval {
        TimeInterval(SettingsStore.playPauseFadeMs) / 1000
    }

    /// 20ms 一拍的音量斜坡（只动 active 轨；过渡期由 crossfade
    /// 自己管两轨音量，互斥见 play/pause 的 crossfadeContext 守卫）。
    private func rampActiveVolume(to target: Float, duration: TimeInterval,
                                  completion: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        let start = activePlayer.volume
        let steps = max(Int(duration / 0.02), 1)
        var step = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            let fraction = Float(step) / Float(steps)
            self.activePlayer.volume = start + (target - start) * fraction
            if step >= steps {
                timer.invalidate()
                self.fadeTimer = nil
                completion?()
            }
        }
    }

    /// (62) WB §4.5：播放时阻止休眠——按播放态写系统空闲计
    /// 时器（设置行/状态收敛点共用）。
    func refreshIdleTimerGate() {
        let shouldBlock = SettingsStore.preventSleepWhilePlaying && playbackState == .playing
        UIApplication.shared.isIdleTimerDisabled = shouldBlock
        Breadcrumbs.log("idleTimer62 disabled=\(shouldBlock)")
    }

    func stop() {
        cancelCrossfade()
        fadeTimer?.invalidate()
        fadeTimer = nil
        activePlayer.pause()
        disarmLyricCues()
        lyricCues = nil
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
        // (66) DSD 通路：本地 .dsf 先经 DSDPlayback62 转换
        // （DoP 封装或 PCM 降级，条件与路径见该组件与面包
        // 屑 dsd66.*），产物以新地址重入本函数（扩展名已变
        // wav，不再回本分支）；解析失败回原路径。
        if track.sourceType == .local, playableURL.isFileURL,
           playableURL.pathExtension.lowercased() == "dsf" {
            Breadcrumbs.log("dsd66 hook dop=\(SettingsStore.dsdDopEnabled62 ? 1 : 0)")
            Task { [weak self] in
                let converted = DSDPlayback62.convertDSF(playableURL)
                await MainActor.run {
                    guard let self else { return }
                    if let (url, usedDoP) = converted {
                        Breadcrumbs.log("dsd66 play dop=\(usedDoP ? 1 : 0)")
                        self.load(track: track, playableURL: url, artwork: artwork)
                    } else {
                        self.loadAfterTranscodeCheck(track: track, playableURL: playableURL, artwork: artwork)
                    }
                }
            }
            return
        }
        // (62) WB §4.5 / D7：本地资产不可播且自动转换开时，
        // 先走本地转码通路（转 m4a 落缓存后以新地址重入本函
        // 数）；流媒体地址不进此路（不可播走既有跳过逻辑，
        // 服务端转码链不在本机能力内）。
        if SettingsStore.autoTranscodeEnabled, track.sourceType == .local,
           playableURL.isFileURL, !Self.isPlayableFile(playableURL) {
            Breadcrumbs.log("transcode62 start track=\(track.id)")
            Task { [weak self] in
                let converted = await Self.transcodeToM4A(source: playableURL)
                await MainActor.run {
                    guard let self else { return }
                    if let converted {
                        Breadcrumbs.log("transcode62 ok track=\(track.id)")
                        self.load(track: track, playableURL: converted, artwork: artwork)
                    } else {
                        Breadcrumbs.log("transcode62 failed track=\(track.id) fallback=original")
                        self.loadAfterTranscodeCheck(track: track, playableURL: playableURL, artwork: artwork)
                    }
                }
            }
            return
        }
        loadAfterTranscodeCheck(track: track, playableURL: playableURL, artwork: artwork)
    }

    private func loadAfterTranscodeCheck(track: FoliaTrack, playableURL: URL, artwork: UIImage?) {
        Breadcrumbs.log("engine load track=\(track.id)")
        // (62) WB：硬切歌时未完成的过渡/预载一律作废，防 B
        // 轨残留与新装载打架。
        cancelCrossfade()
        automixApproxLogged = false
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
        // 歌词行界：注册表与新曲对不上就作废；对得上（同曲重载）重新布防。
        if lyricCues?.trackId == track.id {
            cueFiredThroughIndex = -1
            armLyricCues()
        } else {
            disarmLyricCues()
            lyricCues = nil
        }
        refreshReplayGain()
        play()
        // 切歌是离散事件：先推一次乐观锁屏状态（elapsed 0 / rate 1），
        // KVO 收敛后 NowPlayingController 会再同步一次。
        NowPlayingController.shared.syncNowPlaying(elapsed: 0, rate: 1.0)
    }

    // MARK: - (62) WB：本地转码通路（D7）

    /// 文件是否可被 AVPlayer 直接播放（资产可播性判定）。
    private static func isPlayableFile(_ url: URL) -> Bool {
        AVURLAsset(url: url).isPlayable
    }

    /// AVAssetExportSession 转 m4a：产物落 Caches/folia-transcode
    /// （按源文件路径哈希命名，重复转码复用）；失败返回 nil。
    private static func transcodeToM4A(source: URL) async -> URL? {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetAppleM4A)
        else { return nil }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("folia-transcode", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = source.lastPathComponent.replacingOccurrences(of: ".", with: "_")
            + "-\(abs(source.path.hashValue)).m4a"
        let output = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: output.path) { return output }
        session.outputURL = output
        session.outputFileType = .m4a
        // iOS 17 口径：exportAsynchronously + continuation 桥接
        // （async export() 是 iOS 18 SDK 面，不用）。
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        return session.status == .completed ? output : nil
    }

    // MARK: - 歌词行边界（3.6 (3)）

    /// 前端注册当前曲的歌词行界（桥 registerCues 的落点）。只存表 + 布防，
    /// 跨界判定由 AVPlayer boundary observer 按音频时钟触发，不占周期推送。
    func setLyricCues(trackId: String, cues: [(id: String, time: TimeInterval)]) {
        lyricCues = (trackId: trackId, cues: cues.sorted { $0.time < $1.time })
        cueFiredThroughIndex = -1
        if currentTrack?.id == trackId {
            armLyricCues()
        } else {
            disarmLyricCues()
        }
    }

    /// 给 active 轨挂 boundary observer（接下来 24 个未跨过的行界）。
    private func armLyricCues() {
        disarmLyricCues()
        guard let lyricCues, lyricCues.trackId == currentTrack?.id else { return }
        // 布防按播放器实时 playhead 算，不用 200ms 周期缓存的 currentTime：
        // 缓存值可慢近 200ms，已跨过的行界进了 observer 也永不触发（审查中 2）。
        let rawNow = activePlayer.currentTime().seconds
        let now = rawNow.isFinite ? rawNow : currentTime
        let upcoming = lyricCues.cues.enumerated()
            .filter { $0.element.time > now + 0.05 }
            .prefix(24)
        guard !upcoming.isEmpty else { return }
        let times = upcoming.map { NSValue(time: CMTime(seconds: $0.element.time, preferredTimescale: 600)) }
        cueBoundaryObserver = activePlayer.addBoundaryTimeObserver(
            forTimes: times, queue: .main
        ) { [weak self] in
            self?.handleCueBoundaryCrossed()
        }
    }

    private func disarmLyricCues() {
        if let observer = cueBoundaryObserver {
            activePlayer.removeTimeObserver(observer)
            cueBoundaryObserver = nil
        }
    }

    /// boundary 回调不指明跨的是哪一界：按当前音频时间找最后一个已跨过的
    /// 行界补发 cue，并为后续行界重新布防。
    private func handleCueBoundaryCrossed() {
        guard let lyricCues, lyricCues.trackId == currentTrack?.id else { return }
        let now = activePlayer.currentTime().seconds
        guard now.isFinite else { return }
        var latest = cueFiredThroughIndex
        for (index, cue) in lyricCues.cues.enumerated() {
            if cue.time <= now + 0.05 { latest = index } else { break }
        }
        if latest > cueFiredThroughIndex {
            cueFiredThroughIndex = latest
            let cue = lyricCues.cues[latest]
            onLyricCue?(cue.id, cue.time)
        }
        armLyricCues()
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
                // seek 后行界重新对齐：已跨过的界标为已发，为后续界重新布防。
                if let cues = self.lyricCues, cues.trackId == self.currentTrack?.id {
                    self.cueFiredThroughIndex = cues.cues.lastIndex { $0.time <= resolved + 0.05 } ?? -1
                    self.armLyricCues()
                }
                self.onTimeSync?(resolved, self.currentRate)
                NowPlayingController.shared.syncNowPlaying(elapsed: resolved, rate: self.currentRate)
            }
        }
    }

    // MARK: - Crossfade（(62) WB §4.5 智能过渡实装）

    /// 预载完成的下一首（B 轨 item 已装入 inactive player）。
    private var preparedCrossfade: (track: FoliaTrack, item: AVPlayerItem)?
    /// 进行中的过渡上下文（20ms 一拍的音量斜坡计时器）。
    private var crossfadeContext: (track: FoliaTrack, duration: TimeInterval,
                                   elapsed: TimeInterval, timer: Timer)?
    /// Automix 固定提前量近似只落一次面包屑（防周期 observer 刷屏）。
    private var automixApproxLogged = false

    /// 过渡完成回调（QueueManager 注入）：引擎已切到新曲，
    /// 队列侧据此静默推进下标（不重走 load，防双起播）。
    var onCrossfadeCompleted: ((FoliaTrack) -> Void)?

    /// 协议面 prepare：只认已由 prepareCrossfade(track:url:)
    /// 预载好的同曲（地址组装归 QueueManager，引擎不拼 URL，
    /// 与 load 的分工一致）；未预载返回 false 并落痕。
    func prepareCrossfade(to track: FoliaTrack) async -> Bool {
        if preparedCrossfade?.track.id == track.id { return true }
        Breadcrumbs.log("crossfade62 prepare miss track=\(track.id) reason=no-url-preload")
        return false
    }

    /// 预载下一首到 B 轨（QueueManager 解析出地址后调用）：
    /// 建 item 装入 inactive player、音量 0、不发声。解码并
    /// 发红线：全程至多 A/B 两台 player，与既有双轨结构一致，
    /// 不新增解码路。
    @discardableResult
    func prepareCrossfade(track: FoliaTrack, playableURL: URL) -> Bool {
        guard SettingsStore.smartTransitionEnabled else { return false }
        guard crossfadeContext == nil, currentTrack?.id != track.id else { return false }
        let asset = RangeStreamResourceLoader.makeAsset(for: playableURL)
        let item = AVPlayerItem(asset: asset)
        preparedCrossfade = (track, item)
        inactivePlayer.replaceCurrentItem(with: item)
        inactivePlayer.volume = 0
        Breadcrumbs.log("crossfade62 prepared track=\(track.id)")
        return true
    }

    var isCrossfadeReady: Bool {
        preparedCrossfade != nil && crossfadeContext == nil
    }

    /// 过渡进行中标志：完播通知在此期间到达应被忽略（收口
    /// 由 finishCrossfade 的 onCrossfadeCompleted 推进队列，
    /// QueueManager 的 onTrackEnded 据此守卫，防双推进）。
    var isCrossfading: Bool { crossfadeContext != nil }

    /// 开始过渡：B 轨起播，两轨按表现模式曲线斜坡（出轨降、
    /// 入轨升，均乘有效音量）；时长受 transitionMaxDurationSec
    /// 封顶。失败/无预载时直接返回，由完播链硬切兜底。
    func beginCrossfade(duration: TimeInterval) {
        guard SettingsStore.smartTransitionEnabled,
              let prepared = preparedCrossfade, crossfadeContext == nil else {
            Breadcrumbs.log("crossfade62 begin skipped ready=\(preparedCrossfade != nil)")
            return
        }
        let effective = min(max(duration, 0.5), Self.effectiveTransitionMax62)
        preparedCrossfade = nil
        inactivePlayer.volume = 0
        inactivePlayer.play()
        // 过渡动画层（圆环/描边）：降低动态·混音过渡命中时停用。
        if !FoliaMotion62.reduced(.mixTransition) {
            TransitionAnim62.playCurrent()
        }
        Breadcrumbs.log("crossfade62 begin track=\(prepared.track.id) dur=\(String(format: "%.2f", effective)) mode=\(SettingsStore.transitionMode) curve=\(SettingsStore.transitionCurve) aggr=\(SettingsStore.transitionAggressive62 ? 1 : 0)")
        var elapsed: TimeInterval = 0
        let aggressive = SettingsStore.transitionAggressive62
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
            guard let self, self.crossfadeContext != nil else { timer.invalidate(); return }
            elapsed += 0.02
            let progress = min(elapsed / effective, 1)
            let gains = Self.crossfadeGains(progress: progress,
                                            curve: SettingsStore.transitionCurve)
            let base = self.effectiveVolume()
            // (66) 激进表现：双轨中段增益抬升（正弦包络，峰值
            // +18%），让混音段被听见；钳到 1 不爆音量上限。
            let boost: Float = aggressive
                ? Float(1 + 0.18 * sin(progress * Double.pi)) : 1
            self.activePlayer.volume = min(1, base * gains.out * boost)
            self.inactivePlayer.volume = min(1, base * gains.in * boost)
            if progress >= 1 {
                timer.invalidate()
                self.finishCrossfade()
            }
        }
        crossfadeContext = (prepared.track, effective, 0, timer)
    }

    /// (66) 过渡时长有效上限：激进表现开时上限 ×1.5（窗口
    /// 与时长同步放大，网页「激进表现」语义）；关时 = 用户
    /// 设置的 transitionMaxDurationSec 原值。
    private static var effectiveTransitionMax62: TimeInterval {
        let base = SettingsStore.transitionMaxDurationSec
        return SettingsStore.transitionAggressive62 ? base * 1.5 : base
    }

    /// 过渡音量曲线（出/入增益）：equalPower 恒功率、linear
    /// 线性、easeInOut smoothstep。
    private static func crossfadeGains(progress: Double, curve: String) -> (out: Float, in: Float) {
        switch curve {
        case "linear":
            return (Float(1 - progress), Float(progress))
        case "easeInOut":
            let eased = progress * progress * (3 - 2 * progress)
            return (Float(1 - eased), Float(eased))
        default: // equalPower
            let angle = progress * Double.pi / 2
            return (Float(cos(angle)), Float(sin(angle)))
        }
    }

    /// 过渡收口：换轨（usingA 翻转）、旧轨停并卸 item、新曲
    /// 接管 currentTrack 与 item 观察者、音量回复有效值，末
    /// 尾通知 QueueManager 静默推进下标。
    private func finishCrossfade() {
        guard let context = crossfadeContext else { return }
        crossfadeContext = nil
        let newTrack = context.track
        let oldPlayer = activePlayer
        usingA.toggle()
        oldPlayer.pause()
        teardownCurrentItemObservers()
        oldPlayer.replaceCurrentItem(with: nil)
        if let item = activePlayer.currentItem {
            currentItem = item
            registerCurrentItemObservers(item)
        }
        flushListeningHistory(isCompleted: true)
        currentTrack = newTrack
        currentTime = 0
        listenedSeconds = 0
        lastTickDate = nil
        pendingSeek = false
        disarmLyricCues()
        lyricCues = nil
        refreshReplayGain()
        applyEffectiveVolume()
        NowPlayingController.shared.syncNowPlaying(elapsed: 0, rate: 1.0)
        Breadcrumbs.log("crossfade62 finished track=\(newTrack.id)")
        onCrossfadeCompleted?(newTrack)
    }

    func cancelCrossfade() {
        if let context = crossfadeContext {
            context.timer.invalidate()
            crossfadeContext = nil
            inactivePlayer.pause()
            inactivePlayer.replaceCurrentItem(with: nil)
            applyEffectiveVolume()
            Breadcrumbs.log("crossfade62 cancelled during-fade")
            return
        }
        if preparedCrossfade != nil {
            preparedCrossfade = nil
            inactivePlayer.replaceCurrentItem(with: nil)
            Breadcrumbs.log("crossfade62 cancelled prepared")
        }
    }

    /// 周期 observer 内的尾段触发判定：剩余时长进入过渡窗
    /// 口且预载就绪时开过渡。Automix 的对齐点本应按下一首
    /// 前奏能量点——无能量数据源，以固定提前量（= 过渡时
    /// 长，上限封顶）近似并落面包屑标注，不冒充能量对齐。
    private func checkCrossfadeTrigger() {
        guard SettingsStore.smartTransitionEnabled, isCrossfadeReady,
              duration > 0, playbackState == .playing else { return }
        let remaining = duration - currentTime
        let window: TimeInterval
        if SettingsStore.transitionMode == "automix" {
            window = min(Self.effectiveTransitionMax62, 10)
            if !automixApproxLogged {
                automixApproxLogged = true
                Breadcrumbs.log("crossfade62 automix approx=fixed-lead lead=\(window) energy-data=none")
            }
        } else {
            window = min(Self.effectiveTransitionMax62, duration * 0.25)
        }
        guard remaining > 0.3, remaining <= window else { return }
        beginCrossfade(duration: remaining)
    }

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
        refreshIdleTimerGate()
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
                // (62) WB：智能过渡尾段触发（仅 active 轨的
                // observer 走到这里，与上方 guard 同域）。
                self.checkCrossfadeTrigger()
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
            // (62) WB §4.5：语音输入时暂停开时，中断（Siri/语
            // 音输入）一律按用户暂停处理——ended 分支不再自动
            // 恢复（wasPlaying 旗标在此清掉即达此效）。
            if SettingsStore.pauseOnVoiceInput, wasPlayingBeforeInterruption {
                wasPlayingBeforeInterruption = false
                Breadcrumbs.log("voicePause62 interruption-held=1")
            }
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
