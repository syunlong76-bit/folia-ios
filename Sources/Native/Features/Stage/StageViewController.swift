import UIKit
import Combine
import QuartzCore

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
    // 点播台（3.7 (32) 同步改造）：原固定 128pt 控制带（私有
    // 进度条 + 时间标签 + 44/64/44 三键）整体换成与墙台同规
    // 格的点播台——70pt 玻璃胶囊 + 同款主题层 + 可拖进度轨，
    // 闲置 5 秒收成 16pt 细条（命中带 44pt）；去重变体：不
    // 带封面缩略与标题/歌手行（页眉已有），只留控制与进度
    // + 时间标签。实现见文件内「点播台」MARK 段，与墙台的
    // 参数逐项对齐（弹簧/时长/填充色/圆点皮肤）。
    private let stageBar = MiniBarHitView()
    private var stageBlurView: UIVisualEffectView?
    private var stageThemeLayer: MiniPlayerThemeLayer?
    private var stageRimLight: UIView?
    private var stageGlassTint: UIView?
    private var stageProgressTrack: UIView?
    private var stageProgressFill: UIView?
    private var stageProgressKnob: UIView?
    private var stageKnobSkin: UIView?
    private var stageSeekHit: UIView?
    private let currentTimeLabel = UILabel()
    private let totalTimeLabel = UILabel()
    private let prevButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private var stageBarWidthConstraint: NSLayoutConstraint?
    private var stageBarHeightConstraint: NSLayoutConstraint?
    private var stageTrackBottomConstraint: NSLayoutConstraint?
    private var stageKnobLeading: NSLayoutConstraint?
    private var stageTheme: MiniPlayerTheme = MiniPlayerTheme.effective
    private var stageBarCollapsed = false
    private var stageBarPresented = false
    private var stageSeekDragging = false
    private var stageIdleWorkItem: DispatchWorkItem?
    private var stagePetStage: MiniBarPetStage?

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
    // 容器右上）、无歌词陪衬（容器居中）、红心庆祝（容器右
    // 上内侧）。方法全在文件尾 extension；显隐只由既有取
    // 词/点赞落点的一行钩子驱动，不改任何歌词/时钟逻辑。
    private var stickerFetchBadge: StickerView?
    private var stickerNoLyrics: StickerView?
    private var stickerLike: StickerView?
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

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
        Breadcrumbs.samplerStart()
        Breadcrumbs.log("stage gate enter style=\(activeStyleId)")
        progressDriver.onFraction = { [weak self] fraction in
            self?.setStageProgress(fraction)
        }
        progressDriver.start()
        startDisplayLink()
        // 点播台在场边沿（3.7 (32)）：主题层门控 + 宠物钩子 +
        // 无操作计时，与墙台 setMiniBarVisible 同构。
        stageBarPresented = true
        stageThemeLayer?.setHostVisible(true)
        stageThemeLayer?.setBarVisible(true)
        if stageBarCollapsed { resetStageBarFormInstant() }
        stagePetStage?.barPresentationChanged(true)
        resetStageIdleTimer()
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
        stageBarPresented = false
        cancelStageIdleTimer()
        stageThemeLayer?.setHostVisible(false)
        stageThemeLayer?.setBarVisible(false)
        stagePetStage?.barPresentationChanged(false)
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
        // 点播台（3.7 (32)）：与墙台同规格的台体在此装配，
        // 三键仍走既有按钮与命令入口（handleCommand 同路）。
        buildStageBar()
        refreshPlayButton()
        refreshLikeButton()
        // 主题变更通知（设置页/任一台长按）→ 本台同步换装。
        NotificationCenter.default.addObserver(
            self, selector: #selector(stageThemeSettingsChanged),
            name: .foliaMiniPlayerThemeChanged, object: nil)
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
        // 点播台几何（3.7 (32)）：宽 = min(屏宽, 屏高) − 24
        // 居中（横屏同宽不拉伸，与墙台 (21) 定版一致，约束在
        // buildStageBar 定、此处按当前尺寸更新常量）；台顶 =
        // 屏底 − 安全区 − 10 − 形态高（展开 70 / 收起 16）。
        // 台内子视图全走约束（同墙台结构），此处不再逐个定
        // 帧。歌词容器底边到台顶上 4pt。
        stageBarWidthConstraint?.constant =
            min(bounds.width, bounds.height) - 24
        let barHeight: CGFloat = stageBarCollapsed ? 16 : 70
        let controlsTop = bounds.height - safe.bottom - 10 - barHeight
        rendererContainer.frame = CGRect(
            x: 0, y: contentTop, width: bounds.width,
            height: max(controlsTop - contentTop - 4, 0))
        renderer?.view.frame = rendererContainer.bounds
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
        // 点播台切歌边沿（3.7 (32)，与墙 refreshMiniBar 同
        // 构）：宠物切歌钩子 + 收起态先展开、否则重置计时。
        stagePetStage?.setTrack(id: track.id)
        if stageBarCollapsed { expandStageBar() } else { resetStageIdleTimer() }
    }

    private func refreshHeader() {
        let track = engine.currentTrack
        titleLabel.text = track?.title ?? "暂无播放"
        artistLabel.text = track?.artist ?? ""
        totalTimeLabel.text = Self.formatTime(engine.duration)
    }

    private func refreshPlayButton() {
        // 字形（3.7 (32) 同步后）：与墙台同值——播放 19pt
        // semibold（(23) 的舞台专属 32pt 随旧控制带退役）。
        let config = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
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
        // 贴纸层（3.7 (24)，纯新增）：点亮时红心左侧浮贴纸；
        // 取消收藏补依依不舍贴纸（3.7 (28)），同一落点成对。
        if newState { stickerShowLikeCelebration() }
        else { stickerShowUnlikeSticker() }
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
        resetStageIdleTimer()
        handleCommand(LyricStageCommand(kind: .toggle, source: "stage.controls"))
    }
    @objc private func prevTapped() {
        resetStageIdleTimer()
        handleCommand(LyricStageCommand(kind: .prev, source: "stage.controls"))
    }
    @objc private func nextTapped() {
        resetStageIdleTimer()
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

    // MARK: - 点播台（3.7 (32)：与墙台同规格的同步改造）
    //
    // 结构与参数逐项对齐墙台（WallPrototypeViewController 的
    // buildMiniBar 一族）：70pt 玻璃胶囊（systemUltraThin-
    // MaterialDark + 1pt 亮边 + rim 高光 + 0.06 白罩）、同款
    // MiniPlayerThemeLayer 主题层（同一主题来源/存储/变更通
    // 知）、底部内缘进度轨（左右内缩 20、高 4、底距 −7）+
    // 发光圆钮/主题圆点皮肤、底部 20pt seek 命中带（拖动只
    // 更填充、松手 seek；点按按轨道实际帧算比例跳点）、长按
    // 0.55s 循环切主题、闲置 5 秒收成 16pt 细条（轨道底距
    // −6、圆角 8、命中带纵向外扩 14pt 至 44pt、主题层/毛玻
    // 璃/高光全隐、填充走收起态兜底色、圆点保留主题皮肤）、
    // 形态弹簧 0.5s/damping 0.85/velocity 0.1、Reduce Motion
    // 降级为 0.2s 纯 alpha。去重变体差异只有两处：无封面缩
    // 略与标题/歌手行（页眉已有）；三键居中排布（墙台靠右，
    // 因其左侧有封面标题），两侧补时间标签（旧控制带既有
    // 元素保留）。命令落点与墙完全相同：toggle →
    // PlaybackEngine.togglePlayPause、next/prev →
    // QueueManager（经 handleCommand 统一入口）、seek →
    // PlaybackEngine.seek（经 performSeek）。进度源仍是既有
    // StageProgressDriver（viewWillDisappear 必 stop），不新
    // 造第二套。

    private func buildStageBar() {
        let bar = stageBar
        bar.backgroundColor = .clear
        bar.layer.cornerRadius = 35
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOpacity = 0.25
        bar.layer.shadowRadius = 20
        bar.layer.shadowOffset = CGSize(width: 0, height: 8)
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        // 宠物层（细修 B）：详情页台班底，钩子与墙等价。
        let petStage = MiniBarPetStage(bar: bar, role: .stage)
        view.addSubview(petStage)
        stagePetStage = petStage

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.layer.cornerRadius = 35
        blur.layer.borderWidth = 1
        blur.layer.borderColor = UIColor.white.withAlphaComponent(0.30).cgColor
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(blur)
        stageBlurView = blur

        let themeLayer = MiniPlayerThemeLayer()
        themeLayer.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(themeLayer)
        stageThemeLayer = themeLayer

        let rimLight = UIView()
        rimLight.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        rimLight.layer.cornerRadius = 0.5
        rimLight.isUserInteractionEnabled = false
        rimLight.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(rimLight)
        stageRimLight = rimLight
        let glassTint = UIView()
        glassTint.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        glassTint.layer.cornerRadius = 35
        glassTint.isUserInteractionEnabled = false
        glassTint.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(glassTint)
        stageGlassTint = glassTint

        let progressTrack = UIView()
        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        progressTrack.layer.cornerRadius = 2
        progressTrack.clipsToBounds = true
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(progressTrack)
        stageProgressTrack = progressTrack
        let fill = UIView()
        fill.backgroundColor = .white
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressTrack.addSubview(fill)
        stageProgressFill = fill
        fill.transform = CGAffineTransform(scaleX: 0, y: 1)

        let knob = UIView()
        knob.backgroundColor = .white
        knob.layer.cornerRadius = 4.5
        knob.layer.shadowColor = UIColor.white.cgColor
        knob.layer.shadowOpacity = 0.9
        knob.layer.shadowRadius = 4
        knob.layer.shadowOffset = .zero
        knob.isUserInteractionEnabled = false
        knob.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(knob)
        stageProgressKnob = knob

        for label in [currentTimeLabel, totalTimeLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = UIColor.white.withAlphaComponent(0.6)
            label.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(label)
        }
        totalTimeLabel.textAlignment = .right

        // 三键字形与墙台同值（play 19pt / prev·next 15pt，
        // semibold）；命令走既有 handleCommand 入口。
        playButton.tintColor = .white
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        bar.addSubview(playButton)
        let sideConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        prevButton.setImage(UIImage(systemName: "backward.fill", withConfiguration: sideConfig), for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: sideConfig), for: .normal)
        for button in [prevButton, nextButton] {
            button.tintColor = .white
            button.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(button)
        }
        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        let seekHit = UIView()
        seekHit.backgroundColor = .clear
        seekHit.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(seekHit)
        stageSeekHit = seekHit
        let seekPan = UIPanGestureRecognizer(target: self, action: #selector(stageSeekPanned(_:)))
        seekHit.addGestureRecognizer(seekPan)

        stageBarWidthConstraint = bar.widthAnchor.constraint(
            equalToConstant: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) - 24)
        stageBarHeightConstraint = bar.heightAnchor.constraint(equalToConstant: 70)
        stageBarWidthConstraint?.isActive = true
        stageBarHeightConstraint?.isActive = true
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bar.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),

            blur.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            blur.topAnchor.constraint(equalTo: bar.topAnchor),
            blur.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            themeLayer.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            themeLayer.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            themeLayer.topAnchor.constraint(equalTo: bar.topAnchor),
            themeLayer.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            rimLight.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 30),
            rimLight.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -30),
            rimLight.topAnchor.constraint(equalTo: bar.topAnchor, constant: 1),
            rimLight.heightAnchor.constraint(equalToConstant: 1),
            glassTint.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            glassTint.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            glassTint.topAnchor.constraint(equalTo: bar.topAnchor),
            glassTint.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            progressTrack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            progressTrack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
            progressTrack.heightAnchor.constraint(equalToConstant: 4),
            fill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            fill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            fill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor),

            knob.centerYAnchor.constraint(equalTo: progressTrack.centerYAnchor),
            knob.widthAnchor.constraint(equalToConstant: 9),
            knob.heightAnchor.constraint(equalToConstant: 9),

            currentTimeLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            currentTimeLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 44),
            totalTimeLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            totalTimeLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            totalTimeLabel.widthAnchor.constraint(equalToConstant: 44),

            playButton.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            playButton.widthAnchor.constraint(equalToConstant: 40),
            playButton.heightAnchor.constraint(equalToConstant: 40),
            prevButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -2),
            prevButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            prevButton.widthAnchor.constraint(equalToConstant: 34),
            prevButton.heightAnchor.constraint(equalToConstant: 40),
            nextButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            nextButton.widthAnchor.constraint(equalToConstant: 34),
            nextButton.heightAnchor.constraint(equalToConstant: 40),

            seekHit.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            seekHit.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            seekHit.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            seekHit.heightAnchor.constraint(equalToConstant: 20),
        ])
        stageKnobLeading = knob.leadingAnchor.constraint(
            equalTo: progressTrack.leadingAnchor, constant: -4.5)
        stageKnobLeading?.isActive = true
        stageTrackBottomConstraint = progressTrack.bottomAnchor.constraint(
            equalTo: bar.bottomAnchor, constant: -7)
        stageTrackBottomConstraint?.isActive = true

        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(stageBarLongPressed(_:)))
        longPress.minimumPressDuration = 0.55
        bar.addGestureRecognizer(longPress)
        let tap = UITapGestureRecognizer(target: self, action: #selector(stageBarTapped(_:)))
        tap.require(toFail: longPress)
        bar.addGestureRecognizer(tap)

        applyStageTheme()
    }

    /// 进度填充与圆钮的唯一步进点（与墙 setMiniProgress 同
    /// 构）：StageProgressDriver 逐帧喂、拖动/点按跳点先行
    /// 预览都走这里；主题层积雪/鲨鳍/流星头位同源转喂。
    private func setStageProgress(_ fraction: Double) {
        let clamped = CGFloat(min(max(fraction, 0), 1))
        stageProgressFill?.transform = CGAffineTransform(scaleX: clamped, y: 1)
        if let trackWidth = stageProgressTrack?.bounds.width, trackWidth > 0 {
            stageKnobLeading?.constant = clamped * trackWidth - 4.5
        }
        stageThemeLayer?.setFraction(Double(clamped))
    }

    private func applyStageTheme() {
        stageThemeLayer?.apply(theme: stageTheme)
        refreshStageProgressChrome()
    }

    /// 填充/圆点配色的形态收口（与墙 refreshMiniProgress-
    /// Chrome 同值）：展开 = 主题口径；收起 = 兜底色（星空
    /// 强金），圆点两形态都保留主题皮肤、无皮肤才白发光点。
    private func refreshStageProgressChrome() {
        stageKnobSkin?.removeFromSuperview()
        stageKnobSkin = nil
        if let skin = MiniPlayerThemeLayer.knobSkinView(for: stageTheme) {
            skin.translatesAutoresizingMaskIntoConstraints = false
            stageProgressKnob?.addSubview(skin)
            NSLayoutConstraint.activate([
                skin.centerXAnchor.constraint(equalTo: stageProgressKnob!.centerXAnchor),
                skin.centerYAnchor.constraint(equalTo: stageProgressKnob!.centerYAnchor),
                skin.widthAnchor.constraint(equalToConstant: 13),
                skin.heightAnchor.constraint(equalToConstant: 13),
            ])
            stageKnobSkin = skin
        }
        let themed = stageKnobSkin != nil
        stageProgressKnob?.backgroundColor = themed ? .clear : .white
        stageProgressKnob?.layer.shadowOpacity = themed ? 0 : 0.9
        stageProgressFill?.backgroundColor = stageBarCollapsed
            ? Self.stageCollapsedFillColor(for: stageTheme)
            : Self.stageFillColor(for: stageTheme)
    }

    /// 与墙 miniFillColor 同值（主题填充色）。
    private static func stageFillColor(for theme: MiniPlayerTheme) -> UIColor {
        switch theme {
        case .meadow: return UIColor(red: 0.96, green: 0.72, blue: 0.25, alpha: 1)
        case .star: return UIColor(red: 1, green: 0.91, blue: 0.62, alpha: 1)
        default: return .white
        }
    }

    /// 与墙 miniCollapsedFillColor 同值（收起态兜底）。
    private static func stageCollapsedFillColor(for theme: MiniPlayerTheme) -> UIColor {
        switch theme {
        case .star: return UIColor(red: 1, green: 0.80, blue: 0.28, alpha: 1)
        default: return stageFillColor(for: theme)
        }
    }

    @objc private func stageThemeSettingsChanged() {
        let eff = MiniPlayerTheme.effective
        guard eff != stageTheme else { return }
        stageTheme = eff
        applyStageTheme()
    }

    /// 长按台身循环切主题（与墙同规：收起态不切、按键区不
    /// 切、总开关关时停用；切换落盘 + 发同一变更通知）。
    @objc private func stageBarLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !stageBarCollapsed,
              MiniPlayerTheme.effectsEnabled else { return }
        let point = gesture.location(in: stageBar)
        if playButton.frame.contains(point)
            || prevButton.frame.contains(point)
            || nextButton.frame.contains(point) { return }
        stageTheme = stageTheme.next
        MiniPlayerTheme.stored = stageTheme
        applyStageTheme()
        NotificationCenter.default.post(name: .foliaMiniPlayerThemeChanged, object: nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        resetStageIdleTimer()
    }

    /// 台面点按分发（与墙同构）：收起态只展开；展开态按键
    /// 各自处理、底部进度带按轨道实际帧跳点、其余台身无动
    /// 作（已在详情页，不再开台）。任何点按重置无操作计时。
    @objc private func stageBarTapped(_ gesture: UITapGestureRecognizer) {
        if stageBarCollapsed {
            expandStageBar()
            return
        }
        resetStageIdleTimer()
        let point = gesture.location(in: stageBar)
        if playButton.frame.contains(point)
            || prevButton.frame.contains(point)
            || nextButton.frame.contains(point) { return }
        if let seekHit = stageSeekHit, seekHit.frame.contains(point) {
            guard let track = stageProgressTrack?.frame, track.width > 0,
                  engine.duration > 0 else { return }
            let fraction = min(max((point.x - track.minX) / track.width, 0), 1)
            setStageProgress(Double(fraction))
            performSeek(to: Double(fraction) * engine.duration, source: "stage.bar.tap")
        }
    }

    /// 进度拖动（与墙同构）：拖动只更填充、松手才 seek；拖
    /// 动期间挂起无操作计时；收起态不响应。
    @objc private func stageSeekPanned(_ gesture: UIPanGestureRecognizer) {
        guard stageSeekHit != nil else { return }
        let barPoint = gesture.location(in: stageBar)
        guard let track = stageProgressTrack?.frame, track.width > 0 else {
            if gesture.state == .ended || gesture.state == .cancelled
                || gesture.state == .failed {
                stageSeekDragging = false
                resetStageIdleTimer()
            }
            return
        }
        let fraction = min(max((barPoint.x - track.minX) / track.width, 0), 1)
        switch gesture.state {
        case .began:
            if stageBarCollapsed { return }
            if playButton.frame.contains(barPoint)
                || prevButton.frame.contains(barPoint)
                || nextButton.frame.contains(barPoint) { return }
            guard engine.duration > 0 else { return }
            stageSeekDragging = true
            cancelStageIdleTimer()
            setStageProgress(Double(fraction))
        case .changed:
            guard stageSeekDragging else { return }
            setStageProgress(Double(fraction))
        case .ended:
            guard stageSeekDragging else { return }
            stageSeekDragging = false
            resetStageIdleTimer()
            guard engine.duration > 0 else { return }
            performSeek(to: Double(fraction) * engine.duration, source: "stage.bar.seek")
        case .cancelled, .failed:
            stageSeekDragging = false
            resetStageIdleTimer()
        default:
            break
        }
    }

    // MARK: 点播台收起（与墙同规：5 秒无操作自动收成细条）

    private static let stageIdleCollapseDelay: TimeInterval = 5

    private func resetStageIdleTimer() {
        stageIdleWorkItem?.cancel()
        stageIdleWorkItem = nil
        guard stageBarPresented, !stageBarCollapsed, !stageSeekDragging else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.collapseStageBarIdle()
        }
        stageIdleWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.stageIdleCollapseDelay, execute: work)
    }

    private func cancelStageIdleTimer() {
        stageIdleWorkItem?.cancel()
        stageIdleWorkItem = nil
    }

    private func collapseStageBarIdle() {
        guard stageBarPresented, !stageBarCollapsed, !stageSeekDragging else { return }
        stageBarCollapsed = true
        stagePetStage?.barFormChanged(collapsed: true)
        cancelStageIdleTimer()
        Breadcrumbs.log("stage bar collapse idle")
        setStageBarContentsInteractive(false)
        if UIAccessibility.isReduceMotionEnabled {
            setStageBarForm(collapsed: true)
            UIView.animate(withDuration: 0.2) { self.setStageBarContentsAlpha(0) }
            return
        }
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0.1,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.setStageBarForm(collapsed: true)
            self.setStageBarContentsAlpha(0)
            self.view.layoutIfNeeded()
        }
    }

    private func expandStageBar() {
        guard stageBarCollapsed else {
            resetStageIdleTimer()
            return
        }
        stageBarCollapsed = false
        stagePetStage?.barFormChanged(collapsed: false)
        Breadcrumbs.log("stage bar expand")
        setStageBarContentsInteractive(true)
        if UIAccessibility.isReduceMotionEnabled {
            setStageBarForm(collapsed: false)
            UIView.animate(withDuration: 0.2) { self.setStageBarContentsAlpha(1) }
        } else {
            UIView.animate(withDuration: 0.5, delay: 0,
                           usingSpringWithDamping: 0.85, initialSpringVelocity: 0.1,
                           options: [.curveEaseOut, .allowUserInteraction]) {
                self.setStageBarForm(collapsed: false)
                self.setStageBarContentsAlpha(1)
                self.view.layoutIfNeeded()
            }
        }
        resetStageIdleTimer()
    }

    private func setStageBarForm(collapsed: Bool) {
        stageBarHeightConstraint?.constant = collapsed ? 16 : 70
        stageTrackBottomConstraint?.constant = collapsed ? -6 : -7
        let radius: CGFloat = collapsed ? 8 : 35
        stageBar.layer.cornerRadius = radius
        stageBlurView?.layer.cornerRadius = radius
        stageBar.hitExpansionY = collapsed ? 14 : 0
        stageThemeLayer?.isHidden = collapsed
        stageBlurView?.isHidden = collapsed
        stageRimLight?.isHidden = collapsed
        stageGlassTint?.isHidden = collapsed
        refreshStageProgressChrome()
    }

    private func setStageBarContentsAlpha(_ alpha: CGFloat) {
        // 圆点不淡出（收起态保留主题圆点随进度步进，同墙）。
        for view in [currentTimeLabel, totalTimeLabel,
                     playButton, prevButton, nextButton] as [UIView] {
            view.alpha = alpha
        }
    }

    private func setStageBarContentsInteractive(_ interactive: Bool) {
        for button in [playButton, prevButton, nextButton] {
            button.isUserInteractionEnabled = interactive
        }
    }

    /// 在场边沿的形态无动画复位：收起态不跨呈现周期残留。
    private func resetStageBarFormInstant() {
        stageBarCollapsed = false
        setStageBarForm(collapsed: false)
        setStageBarContentsAlpha(1)
        setStageBarContentsInteractive(true)
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
// - 播放陪伴：(25) 的框内陪伴层（CompanionPetView）已于
//   3.7 (27) 按 Miller 定案整体删除（「都没看见出现过」），
//   表情包互动主场迁至迷你台/进度条（MiniBarPetStage）。
// 显隐只由取词/点赞既有落点的一行钩子驱动；歌词数据、时钟
// 与渲染逻辑零改动。

extension StageViewController {

    func stickerInstall() {
        let badge = StickerView()
        badge.crumbScene = "stage-lyric-fetch"
        badge.isHidden = true
        view.addSubview(badge)
        stickerFetchBadge = badge
        let noLyrics = StickerView()
        noLyrics.crumbScene = "stage-no-lyrics"
        noLyrics.isHidden = true
        view.addSubview(noLyrics)
        stickerNoLyrics = noLyrics
        let like = StickerView()
        like.crumbScene = "stage-like"
        like.isHidden = true
        view.addSubview(like)
        stickerLike = like
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
        // 轮廓柔光（3.7 (28)）：dog-11 线条型浅色主体，深色
        // 封面上靠一圈极淡亮边保轮廓可辨。
        like.silhouetteHaloEnabled = true
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

    /// 取消收藏（3.7 (28) 新增，与收藏庆祝成对）：同一落点冒
    /// cat-04（单爪抹泪，映射里「取消收藏」场景的定案主选），
    /// 播一次停末帧、多停留 1.1s 再淡出。
    func stickerShowUnlikeSticker() {
        guard let like = stickerLike else { return }
        like.alpha = 1
        like.isHidden = false
        like.silhouetteHaloEnabled = false
        like.setSticker("cat-04", mode: .once(holdLast: true))
        like.onFinished = { [weak like] in
            UIView.animate(withDuration: 0.3, delay: 1.1, options: []) {
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
    }
}
