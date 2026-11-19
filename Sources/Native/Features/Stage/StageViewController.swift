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

    // 贴纸层（3.7 (24)，纯新增视图层）：拉歌词角标（renderer
    // 容器右上）、无歌词陪衬（容器居中）、红心庆祝（红心按
    // 钮左侧）、播放陪伴宠物（容器周界漫游）。方法全在文件
    // 尾 extension；显隐只由既有取词/点赞落点的一行钩子驱动，
    // 不改任何歌词/时钟逻辑。
    private var stickerFetchBadge: StickerView?
    private var stickerNoLyrics: StickerView?
    private var stickerLike: StickerView?
    private var companionPet: CompanionPetView?
    private let progressDriver = StageProgressDriver()
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var frameDurations: [Double] = []
    private var driftTimer: Timer?
    /// 漂移连续超限计数（3.7 (23)）：连续 2 次 >0.15s 才重锚。
    private var driftOverCount = 0
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
        // 贴纸层（3.7 (24)，纯新增）：建贴纸视图与陪伴宠物。
        stickerInstall()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 贴纸层（3.7 (24)，纯新增）：陪伴宠物开始漫游。
        companionPet?.startRoaming()
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
        // 贴纸层（3.7 (24)，纯新增）：陪伴宠物停漫游。
        companionPet?.stopRoaming()
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
        // transport 字形定版（3.7 (23)，Miller 19:13 拍板）：
        // 上一首/下一首换圆润的 backward.fill/forward.fill
        // （去掉 .end 的竖杠尖角，与迷你台同款）；三键统一
        // semibold 字重——上一/下一 26pt、播放/暂停 32pt
        // （DS R49 尺寸）；按钮框 prev/next 44pt、play 64pt，
        // 热区均 ≥44pt（layoutStage 定尺寸）。
        let transportConfig = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        prevButton.setImage(UIImage(systemName: "backward.fill", withConfiguration: transportConfig), for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: transportConfig), for: .normal)
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
        // 贴纸层（3.7 (24)，纯新增）：贴纸与陪伴宠物定位。
        stickerLayoutOverlays()
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
        // gate 解码图像清单（3.7 (26)，R40 Q4 口径）：本期两
        // 样式为 UIKit/文本类，渲染方自身解码图像 0 张、无
        // Metal 纹理；舞台唯一解码图像是宿主背景封面（到货
        // 时由 applyBackdrop 落 `stage gate backdrop decoded`
        // 一行，含像素尺寸与估算 MB）。
        Breadcrumbs.log("stage gate decoded style=\(styleId) rendererImages=0 textOnly=1 metalTextures=0")
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
        // 贴纸层（3.7 (24)，纯新增）：陪伴宠物按曲换装判定。
        companionPet?.setTrack(id: track.id)
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
        // 字形定版（3.7 (23)）：32pt semibold，与 prev/next 同口径。
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold)
        playButton.setImage(
            UIImage(systemName: engine.isPlaying ? "pause.fill" : "play.fill",
                    withConfiguration: config),
            for: .normal)
    }

    private func refreshLikeButton() {
        let liked = engine.currentTrack.map { LikesStore.shared.isLiked($0.id) } ?? false
        likeButton.setImage(
            UIImage(systemName: liked ? "heart.fill" : "heart"), for: .normal)
        likeButton.tintColor = liked ? UIColor(red: 1, green: 0.35, blue: 0.45, alpha: 1) : .white
    }

    // MARK: 歌词与封面

    /// 取词（3.7 (23) 改经共享仓库 LyricRepository）：此前舞台
    /// 每次打开都是新实例、实例级缓存恒空，进台才向 EdgeOne
    /// 现拉 /lyric（真机约 3s「暂无歌词」，audit-3723 §5.2），
    /// 且与墙面已取过的同一首歌不共享。改走仓库：墙面取过或
    /// 本会话开台取过的歌，仓库命中即时派生舞台形状（同一
    /// 张合并表）；实例级 linesCache 只留派生结果，不再决定
    /// 是否发网络请求。
    private func loadLyrics(for track: FoliaTrack) {
        if linesCache[track.id] != nil {
            pushSnapshot()
            // 贴纸层（3.7 (24)，纯新增钩子）：缓存命中即已落定。
            stickerLyricsResolved(lines: linesCache[track.id] ?? [])
            return
        }
        if let hit = LyricRepository.shared.cachedEntry(for: track.id) {
            linesCache[track.id] = LyricParser.stageLines(
                from: hit.lines, trackDuration: track.duration)
            pushSnapshot()
            // 贴纸层（3.7 (24)，纯新增钩子）：仓库命中即已落定。
            stickerLyricsResolved(lines: linesCache[track.id] ?? [])
            return
        }
        lyricsTask?.cancel()
        // 贴纸层（3.7 (24)，纯新增钩子）：网络取词开始，亮角标。
        stickerLyricsFetching()
        let trackId = track.id
        let duration = track.duration
        lyricsTask = Task { [weak self] in
            let entry = await LyricRepository.shared.entry(for: trackId)
            guard let self, !Task.isCancelled, self.currentTrackId == trackId else { return }
            let lines = LyricParser.stageLines(from: entry.lines, trackDuration: duration)
            self.linesCache[trackId] = lines
            Breadcrumbs.log("stage lrc parsed track=\(trackId) lines=\(lines.count) source=\(entry.source)")
            self.pushSnapshot()
            // 贴纸层（3.7 (24)，纯新增钩子）：取词落定。
            self.stickerLyricsResolved(lines: lines)
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

    /// 锚点（3.7 (23) 改真值，DS R49 Q2）：此前取
    /// engine.currentTime——200ms 周期 observer 的台阶缓存，
    /// 引擎自家注释明文禁止歌词锚点读它（恒滞后真值
    /// 0–200ms）；且 checkDrift 拿同一缓存自比，恒定滞后永
    /// 不纠正（audit-3723 §5.1 实测舞台翻行晚行界
    /// +0.48~0.68s 的主因）。改直读 rawPlayhead() 真值；每
    /// 次重锚落 `stage anchor` 面包屑（锚值 + raw 与旧台阶
    /// 缓存之差），补舞台路径此前零锚点埋点的可观测性缺口。
    private func reanchor() {
        let raw = engine.rawPlayhead()
        anchor = PlaybackAnchor(
            trackId: engine.currentTrack?.id ?? "",
            positionAtAnchor: raw,
            wallTimeAtAnchor: CACurrentMediaTime(),
            rate: engine.isPlaying ? 1 : 0,
            anchorSeq: anchor.anchorSeq + 1)
        Breadcrumbs.log("stage anchor pos=\(String(format: "%.3f", raw)) cacheDelta=\(String(format: "%.3f", raw - engine.currentTime)) seq=\(anchor.anchorSeq)")
    }

    private func positionNow() -> TimeInterval {
        anchor.position(atWallTime: CACurrentMediaTime())
    }

    /// 漂移校正（3.7 (23)）：比对对象改 rawPlayhead 真值（禁
    /// 自比）；阈值 0.15s、连续 2 次超限才重锚，防单帧抖动
    /// 误纠（driftTimer 周期 0.3s，两次 ≈ 0.6s 确认窗）。
    private func checkDrift() {
        guard engine.currentTrack != nil else { return }
        if abs(engine.rawPlayhead() - positionNow()) > 0.15 {
            driftOverCount += 1
            if driftOverCount >= 2 {
                driftOverCount = 0
                reanchor()
            }
        } else {
            driftOverCount = 0
        }
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
        // 贴纸层（3.7 (24)，纯新增）：点亮时红心左侧浮贴纸。
        if newState { stickerShowLikeCelebration() }
        Task { [weak self] in
            do {
                _ = try await NativeDataClient.shared.setLike(trackId: id, like: newState)
            } catch {
                LikesStore.shared.toggle(id)
                self?.refreshLikeButton()
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
        picker.onOpenWebStage = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) { [weak self] in
                self?.jumpToWebStage(reason: "picker open web stage entry")
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
        guard displayLink == nil else { return }
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
        guard !frameDurations.isEmpty else { return "mean=n/a p95=n/a n=0" }
        let sorted = frameDurations.sorted()
        let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        let mean = frameDurations.reduce(0, +) / Double(frameDurations.count)
        return String(format: "mean=%.1fms p95=%.1fms n=%d",
                      mean * 1000, sorted[index] * 1000, sorted.count)
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

// MARK: - 贴纸层（3.7 (24)，纯新增视图层）
//
// 场景（scene-mapping.md 终版；3.7 (25) 修订）：
// - 拉歌词：取词在途时 renderer 容器右上内侧亮 dog-06 角标
//   （探头张望，40pt，循环；抠图透明底直贴、无底板）。
// - 没找到歌词：取词落定且行为空时，cat-11（流泪转圈）
//   72pt 居中于容器中央上方（「暂无歌词」标签上方），播
//   一次停末帧。
// - 点红心：点亮时 dog-11（抱爱心）64pt 浮在容器右上内侧
//   （取词角标在显时左移让位），播 2 圈后淡出；旧落点（红心
//   按钮左侧）会压标题右端，(25) 迁走。
// - 播放陪伴：CompanionPetView 在容器内下半活动带玩耍（框
//   内漫游/双宠互动/双击召唤/点按对话/拖动占座），细则见
//   CompanionPetView 文件头。设置页开关关闭时整层停用。
// 显隐只由取词/点赞既有落点的一行钩子驱动；歌词数据、时钟
// 与渲染逻辑零改动。

extension StageViewController {

    func stickerInstall() {
        let badge = StickerView()
        badge.isHidden = true
        view.addSubview(badge)
        stickerFetchBadge = badge
        let noLyrics = StickerView()
        noLyrics.isHidden = true
        view.addSubview(noLyrics)
        stickerNoLyrics = noLyrics
        let like = StickerView()
        like.isHidden = true
        view.addSubview(like)
        stickerLike = like
        let pet = CompanionPetView()
        pet.onResidentRetired = {
            Breadcrumbs.log("companion pet retired (dragged out)")
        }
        view.addSubview(pet)
        companionPet = pet
        // 双击召唤（3.7 (25)）：识别器挂在歌词容器上，宠物层
        // 本身透传触摸（hitTest 只认领宠物/对话框），歌词行
        // 点按 seek 不受影响（识别器不取消容器内既有触摸）。
        pet.summonTapRecognizer.cancelsTouchesInView = false
        rendererContainer.addGestureRecognizer(pet.summonTapRecognizer)
        // 对话框「点别处关闭」：挂在舞台根视图的旁观识别器，
        // 不取消任何既有触摸（歌词行 seek/按钮照常）。
        view.addGestureRecognizer(pet.dismissTapRecognizer)
        stickerLayoutOverlays()
    }

    func stickerLyricsFetching() {
        stickerNoLyrics?.isHidden = true
        guard let badge = stickerFetchBadge else { return }
        if badge.isHidden {
            badge.setSticker("dog-06", mode: .loop)
            badge.isHidden = false
        }
    }

    func stickerLyricsResolved(lines: [LyricLine]) {
        stickerFetchBadge?.isHidden = true
        if lines.isEmpty {
            stickerNoLyrics?.setSticker("cat-11", mode: .once(holdLast: true))
            stickerNoLyrics?.isHidden = false
        } else {
            stickerNoLyrics?.isHidden = true
        }
    }

    func stickerShowLikeCelebration() {
        guard let like = stickerLike else { return }
        like.alpha = 1
        like.isHidden = false
        like.setSticker("dog-11", mode: .loops(2))
        like.onFinished = { [weak like] in
            UIView.animate(withDuration: 0.3) {
                like?.alpha = 0
            } completion: { _ in
                like?.isHidden = true
                like?.alpha = 1
            }
        }
        stickerLayoutOverlays()
    }

    func stickerLayoutOverlays() {
        let region = rendererContainer.frame
        if let badge = stickerFetchBadge {
            badge.frame = CGRect(
                x: region.maxX - 12 - 40, y: region.minY + 12,
                width: 40, height: 40)
        }
        if let noLyrics = stickerNoLyrics {
            noLyrics.frame = CGRect(
                x: region.midX - 36, y: region.midY - 56 - 36,
                width: 72, height: 72)
        }
        if let like = stickerLike {
            // 穿模治理（3.7 (25)）：迁到容器右上内侧纯封面/歌词
            // 空区；取词角标同在右上时左移 48 让位，不叠贴。
            var likeX = region.maxX - 12 - 64
            if let badge = stickerFetchBadge, !badge.isHidden {
                likeX -= 48
            }
            like.frame = CGRect(
                x: likeX, y: region.minY + 12,
                width: 64, height: 64)
        }
        companionPet?.roamRegion = region
    }
}
