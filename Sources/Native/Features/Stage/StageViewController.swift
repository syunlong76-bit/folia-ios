import UIKit
import Combine
import QuartzCore

/// 舞台进度条：填充 + 光点，点按跳点、拖动松手才 seek（与迷你台
/// 同一手势语义）。填充由 StageProgressDriver 逐帧喂 fraction。
final class StageProgressBarView: UIView {
    var onSeekFraction: ((Double) -> Void)?
    private(set) var fraction: Double = 0
    private var dragging = false
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let knob = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        trackLayer.backgroundColor = UIColor.white.withAlphaComponent(0.22).cgColor
        trackLayer.cornerRadius = 2
        fillLayer.backgroundColor = UIColor.white.cgColor
        fillLayer.cornerRadius = 2
        knob.backgroundColor = .white
        knob.layer.cornerRadius = 5
        knob.layer.shadowColor = UIColor.white.cgColor
        knob.layer.shadowOpacity = 0.8
        knob.layer.shadowRadius = 4
        layer.addSublayer(trackLayer)
        layer.addSublayer(fillLayer)
        addSubview(knob)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.require(toFail: pan)
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setFraction(_ value: Double) {
        guard !dragging else { return }
        fraction = min(max(value, 0), 1)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let trackFrame = CGRect(x: 0, y: bounds.height / 2 - 2, width: bounds.width, height: 4)
        trackLayer.frame = trackFrame
        fillLayer.frame = CGRect(
            x: 0, y: trackFrame.minY, width: trackFrame.width * CGFloat(fraction), height: 4)
        knob.frame = CGRect(
            x: trackFrame.width * CGFloat(fraction) - 5, y: bounds.height / 2 - 5,
            width: 10, height: 10)
    }

    private func fractionAt(_ gesture: UIGestureRecognizer) -> Double {
        guard bounds.width > 0 else { return 0 }
        return min(max(Double(gesture.location(in: self).x / bounds.width), 0), 1)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        onSeekFraction?(fractionAt(gesture))
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            dragging = true
            fraction = fractionAt(gesture)
            setNeedsLayout()
        case .ended, .cancelled:
            dragging = false
            onSeekFraction?(fractionAt(gesture))
        default:
            break
        }
    }
}

// 原生舞台页壳（3.7 (14)，M2'）：全屏舞台——封面氛围背景、
// LyricStage 协议驱动的歌词面、与迷你台/展开卡同一命令入口的
// 控制层。入口由双墙迷你台/双击卡片改道至此（网页 openStage
// 保留为回退与未迁样式的去处，不删）。
//
// 命令入口（与现役双墙逐行同构，全仓无 PlayerAction 枚举）：
//  toggle → PlaybackEngine.togglePlayPause；next/prev →
//  QueueManager.playNext(manual:)/playPrevious；seek →
//  PlaybackEngine.seek(to:)；红心 → LikesStore.toggle + 云端
//  setLike 同步（失败回滚，同展开卡 likeTapped）。
final class StageViewController: UIViewController {

    /// 跳网页舞台（用户选未迁样式 / 提示条回网页 / 挂载失败回退）：
    /// 由呈现本舞台的墙 VC 注入——它负责关掉本舞台后走原
    /// openStageFromWall/openStageFromHome 全套（存票+收墙+恢复）。
    var onRequestWebStage: (() -> Void)?

    private let engine = PlaybackEngine.shared
    private let queueManager = QueueManager.shared

    // MARK: 视图

    private let backdropImageView = UIImageView()
    private let backdropBlur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let backdropTint = UIView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let likeButton = UIButton(type: .system)
    private let styleButton = UIButton(type: .system)
    private let noticeBar = UIView()
    private let noticeLabel = UILabel()
    private let noticeWebButton = UIButton(type: .system)
    private let noticeCloseButton = UIButton(type: .system)
    private let rendererContainer = UIView()
    private let progressBar = StageProgressBarView()
    private let currentTimeLabel = UILabel()
    private let totalTimeLabel = UILabel()
    private let prevButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    // MARK: 状态

    private var context: LyricStageContext!
    private var renderer: LyricStageRenderer?
    private var activeStyleId: String = LyricStageRegistry.defaultStyleId
    private var anchor = PlaybackAnchor(
        trackId: "", positionAtAnchor: 0,
        wallTimeAtAnchor: CACurrentMediaTime(), rate: 0, anchorSeq: 0)
    private var cancellables = Set<AnyCancellable>()
    private var linesCache: [String: [LyricLine]] = [:]
    private var palette: PaletteTokens = .neutralDark
    private var currentTrackId: String? = nil
    private var backdropTrackId: String? = nil
    private var lyricsTask: Task<Void, Never>?
    private var backdropTask: Task<Void, Never>?
    private let progressDriver = StageProgressDriver()
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var frameDurations: [Double] = []
    private var driftTimer: Timer?
    private var gateTimer: Timer?
    private var lastLayoutSize: CGSize = .zero
    private var lastTimeLabelSecond = -1
    private var tornDown = false
    private var webJumpFired = false
    private var noticeDismissed = false

    // MARK: 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildLayout()
        context = LyricStageContext(
            sendCommand: { [weak self] command in self?.handleCommand(command) },
            currentAnchor: { [weak self] in
                self?.anchor ?? PlaybackAnchor(
                    trackId: "", positionAtAnchor: 0,
                    wallTimeAtAnchor: CACurrentMediaTime(), rate: 0, anchorSeq: 0)
            })
        resolveInitialStyle()
        // 订阅的 sink 会立即以当前值首发（有曲走 handleTrackChanged），
        // 不需要再显式调一次，避免双跑取词；无曲时 sink 不触发刷新，
        // 这里补一次页眉空态。
        subscribePlayback()
        refreshHeader()
        reanchor()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Breadcrumbs.samplerStart()
        Breadcrumbs.log("stage gate enter style=\(activeStyleId)")
        progressDriver.onFraction = { [weak self] fraction in
            self?.progressBar.setFraction(fraction)
        }
        progressDriver.start()
        startDisplayLink()
        driftTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkDrift()
        }
        gateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self else { return }
            Breadcrumbs.log("stage gate +30s frames \(self.frameStatsText())")
        }
        renderer?.setLifecycle(engine.isPlaying ? .playing : .paused, active: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        progressDriver.stop()
        stopDisplayLink()
        driftTimer?.invalidate()
        driftTimer = nil
        gateTimer?.invalidate()
        gateTimer = nil
        renderer?.setLifecycle(engine.isPlaying ? .playing : .paused, active: false)
        Breadcrumbs.samplerStop()
        if isBeingDismissed {
            Breadcrumbs.log("stage gate exit frames \(frameStatsText())")
            teardown()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutStage()
        if view.bounds.size != lastLayoutSize {
            lastLayoutSize = view.bounds.size
            pushSnapshot()
        }
    }

    private func teardown() {
        guard !tornDown else { return }
        tornDown = true
        lyricsTask?.cancel()
        backdropTask?.cancel()
        renderer?.setLifecycle(.destroyed, active: false)
        renderer?.unmount()
        renderer = nil
        cancellables.removeAll()
    }

    // MARK: 布局

    private func buildLayout() {
        backdropImageView.contentMode = .scaleAspectFill
        backdropImageView.clipsToBounds = true
        backdropBlur.alpha = 0.55
        backdropTint.backgroundColor = palette.background.withAlphaComponent(0.5)
        for v in [backdropImageView, backdropBlur, backdropTint] as [UIView] {
            view.addSubview(v)
        }
        closeButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        likeButton.tintColor = .white
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        artistLabel.font = .systemFont(ofSize: 13)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        artistLabel.textAlignment = .center
        artistLabel.lineBreakMode = .byTruncatingTail
        styleButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        styleButton.setTitleColor(.white, for: .normal)
        styleButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        styleButton.layer.cornerRadius = 12
        styleButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        styleButton.addTarget(self, action: #selector(styleTapped), for: .touchUpInside)
        for v in [closeButton, titleLabel, artistLabel, likeButton, styleButton] as [UIView] {
            view.addSubview(v)
        }
        noticeBar.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        noticeBar.layer.cornerRadius = 10
        noticeBar.isHidden = true
        noticeLabel.font = .systemFont(ofSize: 12)
        noticeLabel.textColor = .white
        noticeLabel.numberOfLines = 2
        noticeWebButton.setTitle("回网页版", for: .normal)
        noticeWebButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        noticeWebButton.setTitleColor(UIColor(red: 0.65, green: 0.85, blue: 1, alpha: 1), for: .normal)
        noticeWebButton.addTarget(self, action: #selector(noticeWebTapped), for: .touchUpInside)
        noticeCloseButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        noticeCloseButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        noticeCloseButton.addTarget(self, action: #selector(noticeCloseTapped), for: .touchUpInside)
        noticeBar.addSubview(noticeLabel)
        noticeBar.addSubview(noticeWebButton)
        noticeBar.addSubview(noticeCloseButton)
        view.addSubview(noticeBar)
        view.addSubview(rendererContainer)
        progressBar.onSeekFraction = { [weak self] fraction in
            guard let self, self.engine.duration > 0 else { return }
            self.performSeek(to: fraction * self.engine.duration, source: "stage.progress")
        }
        view.addSubview(progressBar)
        for label in [currentTimeLabel, totalTimeLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = UIColor.white.withAlphaComponent(0.6)
            view.addSubview(label)
        }
        totalTimeLabel.textAlignment = .right
        prevButton.setImage(UIImage(systemName: "backward.end.fill"), for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.end.fill"), for: .normal)
        for button in [prevButton, nextButton] {
            button.tintColor = .white
            view.addSubview(button)
        }
        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        playButton.tintColor = .white
        playButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        playButton.layer.cornerRadius = 32
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        view.addSubview(playButton)
        refreshPlayButton()
        refreshLikeButton()
    }

    private func layoutStage() {
        let bounds = view.bounds
        let safe = view.safeAreaInsets
        backdropImageView.frame = bounds
        backdropBlur.frame = bounds
        backdropTint.frame = bounds
        let headerTop = safe.top + 6
        closeButton.frame = CGRect(x: 12, y: headerTop, width: 38, height: 38)
        likeButton.frame = CGRect(x: bounds.width - 50, y: headerTop, width: 38, height: 38)
        let titleWidth = bounds.width - 120
        titleLabel.frame = CGRect(x: 60, y: headerTop, width: titleWidth, height: 22)
        artistLabel.frame = CGRect(x: 60, y: headerTop + 22, width: titleWidth, height: 17)
        styleButton.sizeToFit()
        styleButton.frame = CGRect(
            x: bounds.width - styleButton.bounds.width - 14,
            y: headerTop + 44, width: styleButton.bounds.width, height: 24)
        var contentTop = headerTop + 76
        if !noticeBar.isHidden {
            noticeBar.frame = CGRect(x: 16, y: contentTop, width: bounds.width - 32, height: 40)
            noticeCloseButton.frame = CGRect(x: noticeBar.bounds.width - 34, y: 5, width: 30, height: 30)
            noticeWebButton.sizeToFit()
            noticeWebButton.frame = CGRect(
                x: noticeBar.bounds.width - 44 - noticeWebButton.bounds.width,
                y: 5, width: noticeWebButton.bounds.width, height: 30)
            noticeLabel.frame = CGRect(
                x: 10, y: 4, width: noticeWebButton.frame.minX - 16, height: 32)
            contentTop += 48
        }
        let controlsHeight: CGFloat = 128
        let controlsTop = bounds.height - safe.bottom - controlsHeight
        rendererContainer.frame = CGRect(
            x: 0, y: contentTop, width: bounds.width,
            height: max(controlsTop - contentTop - 4, 0))
        renderer?.view.frame = rendererContainer.bounds
        progressBar.frame = CGRect(x: 22, y: controlsTop, width: bounds.width - 44, height: 26)
        currentTimeLabel.frame = CGRect(x: 22, y: controlsTop + 27, width: 60, height: 14)
        totalTimeLabel.frame = CGRect(x: bounds.width - 82, y: controlsTop + 27, width: 60, height: 14)
        let transportY = controlsTop + 52
        playButton.frame = CGRect(x: bounds.width / 2 - 32, y: transportY, width: 64, height: 64)
        prevButton.frame = CGRect(x: bounds.width / 2 - 116, y: transportY + 10, width: 44, height: 44)
        nextButton.frame = CGRect(x: bounds.width / 2 + 72, y: transportY + 10, width: 44, height: 44)
    }

    // MARK: 样式解析与渲染方装配

    private func resolveInitialStyle() {
        let recorded = StageStyleStore.currentStyleId
        activeStyleId = StageStyleStore.effectiveStyleId()
        mountRenderer(styleId: activeStyleId)
        if !StageStyleStore.currentStyleIsNative && !noticeDismissed {
            let recordedName = LyricStageRegistry.info(for: recorded)?.displayName ?? recorded
            let effectiveName = LyricStageRegistry.info(for: activeStyleId)?.displayName ?? activeStyleId
            noticeLabel.text = "当前样式『\(recordedName)』尚未原生化，暂时用『\(effectiveName)』"
            noticeBar.isHidden = false
        }
        refreshStyleButton()
    }

    private func mountRenderer(styleId: String) {
        guard let info = LyricStageRegistry.info(for: styleId),
              let factory = info.factory else {
            // 已迁样式却拿不到工厂 = 装配异常，走回退不硬撑。
            jumpToWebStage(reason: "no renderer factory for \(styleId)")
            return
        }
        let next = factory()
        next.mount(context: context)
        rendererContainer.addSubview(next.view)
        next.view.frame = rendererContainer.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        renderer = next
        next.applySnapshot(makeSnapshot())
        next.setLifecycle(engine.isPlaying ? .playing : .paused, active: isViewLoaded && view.window != nil)
        StageStyleStore.lastNativeStyleId = styleId
    }

    private func swapRenderer(to styleId: String) {
        renderer?.setLifecycle(.destroyed, active: false)
        renderer?.unmount()
        renderer?.view.removeFromSuperview()
        renderer = nil
        activeStyleId = styleId
        mountRenderer(styleId: styleId)
        refreshStyleButton()
        Breadcrumbs.log("stage gate style switch to=\(styleId)")
    }

    private func refreshStyleButton() {
        let name = LyricStageRegistry.info(for: activeStyleId)?.displayName ?? activeStyleId
        styleButton.setTitle("样式 · \(name)", for: .normal)
        view.setNeedsLayout()
    }

    // MARK: 播放状态订阅

    private func subscribePlayback() {
        engine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self else { return }
                if track?.id != self.currentTrackId {
                    if let track { self.handleTrackChanged(to: track) }
                    else {
                        self.currentTrackId = nil
                        self.refreshHeader()
                        self.pushSnapshot()
                    }
                }
            }
            .store(in: &cancellables)
        engine.$currentArtwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                guard let self, let image, self.engine.currentTrack != nil else { return }
                self.applyBackdrop(image: image, trackId: self.engine.currentTrack?.id)
            }
            .store(in: &cancellables)
        engine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reanchor()
                self.refreshPlayButton()
                self.renderer?.setLifecycle(
                    self.engine.isPlaying ? .playing : .paused,
                    active: self.view.window != nil)
            }
            .store(in: &cancellables)
    }

    private func handleTrackChanged(to track: FoliaTrack) {
        currentTrackId = track.id
        backdropTrackId = nil
        palette = .neutralDark
        backdropImageView.image = nil
        backdropTint.backgroundColor = palette.background.withAlphaComponent(0.5)
        refreshHeader()
        refreshLikeButton()
        reanchor()
        pushSnapshot()
        loadLyrics(for: track)
        loadBackdropFallback(for: track)
        Breadcrumbs.log("stage track \(track.id) title=\(track.title)")
    }

    private func refreshHeader() {
        let track = engine.currentTrack
        titleLabel.text = track?.title ?? "暂无播放"
        artistLabel.text = track?.artist ?? ""
        totalTimeLabel.text = Self.formatTime(engine.duration)
    }

    private func refreshPlayButton() {
        playButton.setImage(
            UIImage(systemName: engine.isPlaying ? "pause.fill" : "play.fill"),
            for: .normal)
    }

    private func refreshLikeButton() {
        let liked = engine.currentTrack.map { LikesStore.shared.isLiked($0.id) } ?? false
        likeButton.setImage(
            UIImage(systemName: liked ? "heart.fill" : "heart"), for: .normal)
        likeButton.tintColor = liked ? UIColor(red: 1, green: 0.35, blue: 0.45, alpha: 1) : .white
    }

    // MARK: 歌词与封面

    private func loadLyrics(for track: FoliaTrack) {
        if let cached = linesCache[track.id] {
            _ = cached
            pushSnapshot()
            return
        }
        lyricsTask?.cancel()
        let trackId = track.id
        let duration = track.duration
        lyricsTask = Task { [weak self] in
            let raw = try? await EdgeOneAPIClient.shared.fetchLyricText(songId: trackId)
            guard let self, !Task.isCancelled, self.currentTrackId == trackId else { return }
            let lines = raw.map { LyricParser.parse($0, trackDuration: duration) } ?? []
            self.linesCache[trackId] = lines
            Breadcrumbs.log("stage lrc parsed track=\(trackId) lines=\(lines.count)")
            self.pushSnapshot()
        }
    }

    private func loadBackdropFallback(for track: FoliaTrack) {
        guard engine.currentArtwork == nil, let raw = track.artworkURL?.absoluteString else { return }
        backdropTask?.cancel()
        let trackId = track.id
        backdropTask = Task { [weak self] in
            let loader = NativeCoverLoader.shared
            let urlString = loader.proxiedURLString(raw, tier: 1024) ?? raw
            let image = await loader.image(for: urlString, tier: 1024)
            guard let self, !Task.isCancelled, self.currentTrackId == trackId,
                  let image, self.engine.currentArtwork == nil else { return }
            self.applyBackdrop(image: image, trackId: trackId)
        }
    }

    private func applyBackdrop(image: UIImage, trackId: String?) {
        guard backdropTrackId != trackId else { return }
        backdropTrackId = trackId
        backdropImageView.image = image
        palette = StagePalette.tokens(from: image)
        backdropTint.backgroundColor = palette.background.withAlphaComponent(0.5)
        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        let estMB = Double(pixelWidth * pixelHeight * 4) / 1_048_576
        Breadcrumbs.log(String(
            format: "stage gate backdrop decoded %dx%d estMB=%.1f",
            pixelWidth, pixelHeight, estMB))
        pushSnapshot()
    }

    // MARK: 快照与锚点

    private func makeSnapshot() -> LyricStageSnapshot {
        let track = engine.currentTrack
        return LyricStageSnapshot(
            protocolVersion: LyricStageProtocolInfo.version,
            track: track.map { TrackMeta(track: $0) },
            lines: track.flatMap { linesCache[$0.id] } ?? [],
            palette: palette,
            styleId: activeStyleId,
            styleVersion: LyricStageRegistry.info(for: activeStyleId)?.styleVersion ?? 1,
            viewport: LyricStageViewport(
                size: view.bounds.size,
                safeAreaInsets: view.safeAreaInsets,
                dynamicTypeScale: 1),
            anchor: anchor,
            hostCapabilities: LyricStageProtocolInfo.hostCapabilities,
            ext: ["entry": "native-stage"])
    }

    private func pushSnapshot() {
        renderer?.applySnapshot(makeSnapshot())
        refreshHeader()
    }

    private func reanchor() {
        anchor = PlaybackAnchor(
            trackId: engine.currentTrack?.id ?? "",
            positionAtAnchor: engine.currentTime,
            wallTimeAtAnchor: CACurrentMediaTime(),
            rate: engine.isPlaying ? 1 : 0,
            anchorSeq: anchor.anchorSeq + 1)
    }

    private func positionNow() -> TimeInterval {
        anchor.position(atWallTime: CACurrentMediaTime())
    }

    private func checkDrift() {
        guard engine.currentTrack != nil else { return }
        if abs(engine.currentTime - positionNow()) > 0.35 { reanchor() }
    }

    // MARK: 命令处理（与迷你台/展开卡同一入口）

    private func handleCommand(_ command: LyricStageCommand) {
        Breadcrumbs.log("stage cmd \(command.kind.logName) from=\(command.source)")
        switch command.kind {
        case .toggle:
            engine.togglePlayPause()
        case .seek(let position):
            performSeek(to: position, source: command.source)
        case .next:
            queueManager.playNext(manual: true)
        case .prev:
            queueManager.playPrevious()
        case .like:
            toggleLike()
        case .close:
            closeStage()
        }
    }

    private func performSeek(to position: TimeInterval, source: String) {
        engine.seek(to: position)
        anchor = PlaybackAnchor(
            trackId: engine.currentTrack?.id ?? "",
            positionAtAnchor: position,
            wallTimeAtAnchor: CACurrentMediaTime(),
            rate: engine.isPlaying ? 1 : 0,
            anchorSeq: anchor.anchorSeq + 1)
        Breadcrumbs.log("stage gate seek to=\(Int(position))s from=\(source)")
    }

    private func toggleLike() {
        guard let track = engine.currentTrack else { return }
        let id = track.id
        let newState = LikesStore.shared.toggle(id)
        refreshLikeButton()
        Task {
            do {
                _ = try await NativeDataClient.shared.setLike(trackId: id, like: newState)
            } catch {
                LikesStore.shared.toggle(id)
                refreshLikeButton()
            }
        }
    }

    private func closeStage() {
        dismiss(animated: true)
    }

    private func jumpToWebStage(reason: String) {
        guard !webJumpFired else { return }
        webJumpFired = true
        Breadcrumbs.log("stage fallback to web: \(reason)")
        if let onRequestWebStage {
            onRequestWebStage()
        } else {
            dismiss(animated: true)
        }
    }

    // MARK: 按钮动作

    @objc private func closeTapped() { closeStage() }
    @objc private func playTapped() {
        handleCommand(LyricStageCommand(kind: .toggle, source: "stage.controls"))
    }
    @objc private func prevTapped() {
        handleCommand(LyricStageCommand(kind: .prev, source: "stage.controls"))
    }
    @objc private func nextTapped() {
        handleCommand(LyricStageCommand(kind: .next, source: "stage.controls"))
    }
    @objc private func likeTapped() {
        handleCommand(LyricStageCommand(kind: .like, source: "stage.controls"))
    }

    @objc private func styleTapped() {
        let picker = StageStylePickerViewController(activeStyleId: activeStyleId)
        picker.onPickNative = { [weak self] styleId in
            guard let self else { return }
            StageStyleStore.currentStyleId = styleId
            self.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.noticeBar.isHidden = true
                self.view.setNeedsLayout()
                self.swapRenderer(to: styleId)
            }
        }
        picker.onPickWeb = { [weak self] info in
            guard let self else { return }
            StageStyleStore.currentStyleId = info.id
            self.dismiss(animated: true) { [weak self] in
                self?.jumpToWebStage(reason: "picker web style \(info.id)")
            }
        }
        picker.modalPresentationStyle = .pageSheet
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(picker, animated: true)
    }

    @objc private func noticeWebTapped() {
        jumpToWebStage(reason: "notice web jump style=\(StageStyleStore.currentStyleId)")
    }

    @objc private func noticeCloseTapped() {
        noticeDismissed = true
        noticeBar.isHidden = true
        view.setNeedsLayout()
    }

    // MARK: 帧驱动与 gate 统计

    private final class DisplayLinkProxy: NSObject {
        weak var owner: StageViewController?
        @objc func step(_ link: CADisplayLink) { owner?.frameStep(link) }
    }
    private let linkProxy = DisplayLinkProxy()

    private func startDisplayLink() {
        linkProxy.owner = self
        let link = CADisplayLink(target: linkProxy, selector: #selector(DisplayLinkProxy.step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrameTimestamp = 0
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func frameStep(_ link: CADisplayLink) {
        if lastFrameTimestamp > 0 {
            let dt = link.timestamp - lastFrameTimestamp
            if dt > 0 && dt < 0.5 {
                frameDurations.append(dt)
                if frameDurations.count > 7200 { frameDurations.removeFirst(1800) }
            }
        }
        lastFrameTimestamp = link.timestamp
        let position = positionNow()
        renderer?.frameTick(position: position)
        let second = Int(position)
        if second != lastTimeLabelSecond {
            lastTimeLabelSecond = second
            currentTimeLabel.text = Self.formatTime(position)
            if engine.duration > 0 { totalTimeLabel.text = Self.formatTime(engine.duration) }
        }
    }

    private func frameStatsText() -> String {
        guard !frameDurations.isEmpty else { return "p95=n/a n=0" }
        let sorted = frameDurations.sorted()
        let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return String(format: "p95=%.1fms n=%d", sorted[index] * 1000, sorted.count)
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private extension LyricStageCommand.Kind {
    var logName: String {
        switch self {
        case .toggle: return "toggle"
        case .seek(let position): return "seek(\(Int(position)))"
        case .next: return "next"
        case .prev: return "prev"
        case .like: return "like"
        case .close: return "close"
        }
    }
}
