import UIKit
import Combine

/// (104) 搜索线①：搜索页内播放台——点播放当场出台，不再
/// 靠切回主页才播。病灶（(102) 真机＋日志实证）：搜索宿主
/// 内没有台实例，onPlaySong 只调 QueueManager.setQueue，
/// 台在被全屏盖住的墙宿主上，播放已开始却无台可见。
///
/// 本台与三宿主（wallproto/homewall/stage）同一套构成与
/// 通路，不另造假台：
/// - 层栈同构：毛玻璃＋MiniPlayerThemeLayer 主题层＋rim
///   高光＋glassTint 罩（边框单源在 glassTint，同 (104)
///   毛边修复口径）；几何走 DeckLayout82 单源（展开高
///   MiniBarQuickRowView.expandedBarHeight、圆角高之半、
///   收起 16/8、轨道底距 expandedTrackBottomInset102）。
/// - 钮簇同构：封面 40 圆＋标题/歌手＋上一曲/播放(46)/
///   下一曲/控制台四钮，字形 DeckGlyph82＋A4Chrome91 面。
/// - 播放通路同一漏斗：钮 → PlaybackEngine.togglePlayPause
///   / QueueManager.playPrevious/playNext；控制台 →
///   ConsolePanel82.present；进度 → StageProgressDriver。
/// - 主题同一通路：长按台身循环 MiniPlayerTheme（stored
///   落盘＋.foliaMiniPlayerThemeChanged 广播）——搜索页
///   SwiftUI 订阅同一通知，台上切主题即整页实时变色
///   （(104) 搜索线②的落点）；外部切主题经同通知回读。
/// - 仲裁同制：宿主名 "search"，容器 viewDidAppear 时
///   MiniBarArbiter99.claim＋MiniBarSingleHost.claim，
///   消失让位（SingleHost.release；仲裁由下一宿主
///   claim 覆盖，与三宿主同制）。
/// - 形态同制：5 秒无操作收细条（主题层打底＋进度填
///   充），点细条展开并重置计时；点台身（非钮区）进
///   舞台（回调由容器接回原呈现者开台）。
///
/// 偏差如实记：宠物层（MiniBarPetStage/岛）按宿主名册
/// 在三宿主，本台未挂宠物舞台——宠物仍在灵动岛与原宿
/// 主台，搜索台不假装有宠物；控制台自本台打开时
/// ConsolePanel82 的宿主专属两格（去处/播放器）走其
/// 通用面（present(from:) 按宿主类型接线，搜索容器
/// 不在名册），队列/设置等主体功能同。
final class SearchDeck104: UIView {

    /// 点台身进舞台（容器接：关搜索 → 原呈现者开台）。
    var onOpenStage: (() -> Void)?
    /// 控制台呈现宿主（容器自身）。
    weak var consoleHost: UIViewController?

    private let engine = PlaybackEngine.shared
    private var cancellables = Set<AnyCancellable>()

    private var blurView: UIVisualEffectView!
    private var themeLayer: MiniPlayerThemeLayer!
    private var rimLight: UIView!
    private var glassTint: UIView!
    private var coverView: UIImageView!
    private var titleLabel: UILabel!
    private var artistLabel: UILabel!
    private var prevButton: UIButton!
    private var playButton: UIButton!
    private var nextButton: UIButton!
    private var consoleButton: UIButton!
    private var trackView: UIView!
    private var fillView: UIView!
    private var knobView: UIView!

    private var heightC: NSLayoutConstraint!
    private var knobCenterXC: NSLayoutConstraint!
    private var trackExpandedCs: [NSLayoutConstraint] = []
    private var trackCollapsedCs: [NSLayoutConstraint] = []

    private(set) var collapsed = false
    private var idleTimer: Timer?
    private let progressDriver = StageProgressDriver()
    private var lastFraction: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildLayers()
        buildContent()
        bindEngine()
        progressDriver.onFraction = { [weak self] fraction in
            guard let self else { return }
            self.setProgress(fraction)
        }
        let tap = UITapGestureRecognizer(target: self,
                                         action: #selector(bodyTapped(_:)))
        addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(bodyLongPressed(_:)))
        longPress.minimumPressDuration = 0.55
        addGestureRecognizer(longPress)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    // MARK: - 装配（层栈与墙台同序同值）

    private func buildLayers() {
        let radius = DeckLayout82.expandedRadius102
        blurView = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blurView.layer.cornerRadius = radius
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        themeLayer = MiniPlayerThemeLayer()
        themeLayer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(themeLayer)

        rimLight = UIView()
        rimLight.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        rimLight.layer.cornerRadius = 0.5
        rimLight.isUserInteractionEnabled = false
        rimLight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rimLight)

        // (104) 毛边口径：唯一可见边框在本层（最上层罩）。
        glassTint = UIView()
        glassTint.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        glassTint.layer.cornerRadius = radius
        glassTint.layer.borderWidth = 1
        glassTint.layer.borderColor = UIColor.white
            .withAlphaComponent(0.30).cgColor
        glassTint.isUserInteractionEnabled = false
        glassTint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassTint)

        for layerView in [blurView as UIView, themeLayer as UIView,
                          glassTint as UIView] {
            NSLayoutConstraint.activate([
                layerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                layerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                layerView.topAnchor.constraint(equalTo: topAnchor),
                layerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            rimLight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
            rimLight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30),
            rimLight.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            rimLight.heightAnchor.constraint(equalToConstant: 1),
        ])
        heightC = heightAnchor.constraint(
            equalToConstant: MiniBarQuickRowView.expandedBarHeight)
        heightC.isActive = true
    }

    private func buildContent() {
        coverView = UIImageView()
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 20
        coverView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        coverView.isUserInteractionEnabled = false
        coverView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverView)

        titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isUserInteractionEnabled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        artistLabel = UILabel()
        artistLabel.font = .systemFont(ofSize: 12)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.isUserInteractionEnabled = false
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artistLabel)

        playButton = UIButton(type: .system)
        playButton.tintColor = .white
        playButton.layer.cornerRadius = 23
        playButton.setImage(DeckGlyph82.image(.play, pointSize: 21),
                            for: .normal)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(playTapped),
                             for: .touchUpInside)
        addSubview(playButton)
        A4Chrome91.apply(to: playButton, cornerRadius: 23)

        prevButton = DeckHitButton96(type: .system)
        prevButton.tintColor = .white
        prevButton.layer.cornerRadius = 20
        prevButton.setImage(DeckGlyph82.image(.prev, pointSize: 19),
                            for: .normal)
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        prevButton.addTarget(self, action: #selector(prevTapped),
                             for: .touchUpInside)
        addSubview(prevButton)
        A4Chrome91.apply(to: prevButton, cornerRadius: 20)

        nextButton = DeckHitButton96(type: .system)
        nextButton.tintColor = .white
        nextButton.layer.cornerRadius = 20
        nextButton.setImage(DeckGlyph82.image(.next, pointSize: 19),
                            for: .normal)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.addTarget(self, action: #selector(nextTapped),
                             for: .touchUpInside)
        addSubview(nextButton)
        A4Chrome91.apply(to: nextButton, cornerRadius: 20)

        consoleButton = DeckHitButton96(type: .system)
        consoleButton.tintColor = .white
        consoleButton.backgroundColor = UIColor.white.withAlphaComponent(0.13)
        consoleButton.layer.cornerRadius = 20
        consoleButton.setImage(DeckGlyph82.image(.consoleNotes, pointSize: 19),
                               for: .normal)
        consoleButton.accessibilityLabel = "控制台"
        consoleButton.translatesAutoresizingMaskIntoConstraints = false
        consoleButton.addTarget(self, action: #selector(consoleTapped),
                                for: .touchUpInside)
        addSubview(consoleButton)
        A4Chrome91.apply(to: consoleButton, cornerRadius: 20)

        trackView = UIView()
        trackView.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        trackView.layer.cornerRadius = 1.5
        trackView.clipsToBounds = true
        trackView.isUserInteractionEnabled = false
        trackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackView)

        fillView = UIView()
        fillView.backgroundColor = .white
        fillView.translatesAutoresizingMaskIntoConstraints = false
        fillView.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        trackView.addSubview(fillView)

        knobView = UIView()
        knobView.backgroundColor = .white
        knobView.layer.cornerRadius = 7
        knobView.layer.shadowColor = UIColor.white.cgColor
        knobView.layer.shadowOpacity = 0.9
        knobView.layer.shadowRadius = 4
        knobView.layer.shadowOffset = .zero
        knobView.isUserInteractionEnabled = false
        knobView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(knobView)

        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            coverView.widthAnchor.constraint(equalToConstant: 40),
            coverView.heightAnchor.constraint(equalToConstant: 40),
            coverView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -5),

            titleLabel.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: prevButton.leadingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: coverView.topAnchor, constant: 5),

            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            consoleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            consoleButton.widthAnchor.constraint(equalToConstant: 40),
            consoleButton.heightAnchor.constraint(equalToConstant: 40),
            consoleButton.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),

            nextButton.trailingAnchor.constraint(equalTo: consoleButton.leadingAnchor, constant: -8),
            nextButton.widthAnchor.constraint(equalToConstant: 40),
            nextButton.heightAnchor.constraint(equalToConstant: 40),
            nextButton.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),

            playButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -8),
            playButton.widthAnchor.constraint(equalToConstant: 46),
            playButton.heightAnchor.constraint(equalToConstant: 46),
            playButton.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),

            prevButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -8),
            prevButton.widthAnchor.constraint(equalToConstant: 40),
            prevButton.heightAnchor.constraint(equalToConstant: 40),
            prevButton.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),

            fillView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
            fillView.topAnchor.constraint(equalTo: trackView.topAnchor),
            fillView.bottomAnchor.constraint(equalTo: trackView.bottomAnchor),
            fillView.widthAnchor.constraint(equalTo: trackView.widthAnchor),

            knobView.widthAnchor.constraint(equalToConstant: DeckLayout82.knobDiameter102),
            knobView.heightAnchor.constraint(equalToConstant: DeckLayout82.knobDiameter102),
            knobView.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
        ])
        knobCenterXC = knobView.leadingAnchor.constraint(
            equalTo: trackView.leadingAnchor, constant: -DeckLayout82.knobDiameter102 / 2)
        knobCenterXC.isActive = true

        trackExpandedCs = [
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            trackView.heightAnchor.constraint(
                equalToConstant: DeckLayout82.expandedTrackHeight102),
            trackView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -DeckLayout82.expandedTrackBottomInset102),
        ]
        trackCollapsedCs = [
            trackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            trackView.widthAnchor.constraint(
                equalToConstant: DeckLayout82.collapsedTrackWidth),
            trackView.heightAnchor.constraint(
                equalToConstant: DeckLayout82.collapsedTrackHeight),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        NSLayoutConstraint.activate(trackExpandedCs)
    }

    // MARK: - 引擎订阅（当前曲/封面/播停/主题）

    private func bindEngine() {
        engine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self else { return }
                self.trackChanged(track)
            }
            .store(in: &cancellables)
        engine.$currentArtwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                guard let self, let image else { return }
                self.coverView.image = image
            }
            .store(in: &cancellables)
        engine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self else { return }
                self.playButton.setImage(
                    DeckGlyph82.image(playing ? .pause : .play, pointSize: 21),
                    for: .normal)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(
            for: .foliaMiniPlayerThemeChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyTheme()
            }
            .store(in: &cancellables)
        applyTheme()
    }

    private func trackChanged(_ track: FoliaTrack?) {
        guard let track else {
            setVisible(false)
            return
        }
        titleLabel.text = track.title
        artistLabel.text = track.artist
        if engine.currentArtwork == nil,
           let pic = track.artworkURL?.absoluteString {
            Task { [weak self] in
                guard let url = NativeCoverLoader.shared
                    .proxiedURLString(pic, tier: 200) else { return }
                let image = await NativeCoverLoader.shared
                    .image(for: url, tier: 200)
                if let image, PlaybackEngine.shared.currentTrack?.id == track.id {
                    self?.coverView.image = image
                }
            }
        }
        if isHidden {
            setVisible(true)
            Breadcrumbs.log("p104 decksearch show=1")
        }
        resetIdleTimer()
    }

    private func applyTheme() {
        themeLayer?.apply(theme: MiniPlayerTheme.effective)
    }

    // MARK: - 显隐与形态

    func setActive(_ active: Bool) {
        if active {
            if engine.currentTrack != nil { setVisible(true) }
            progressDriver.start()
        } else {
            progressDriver.stop()
            idleTimer?.invalidate()
            idleTimer = nil
        }
    }

    private func setVisible(_ visible: Bool) {
        guard visible != !isHidden else { return }
        if visible {
            isHidden = false
            alpha = 0
            transform = CGAffineTransform(translationX: 0, y: 16)
            UIView.animate(withDuration: 0.45, delay: 0,
                           usingSpringWithDamping: 0.85,
                           initialSpringVelocity: 0.4) {
                self.alpha = 1
                self.transform = .identity
            }
            if collapsed { setCollapsed(false, animated: false) }
            resetIdleTimer()
        } else {
            isHidden = true
        }
    }

    private func setCollapsed(_ want: Bool, animated: Bool = true) {
        guard want != collapsed else { return }
        collapsed = want
        MiniBarSingleHost.shared.sharedCollapsed = want
        let radius = DeckLayout82.radius102(
            collapsed: want,
            barHeight: MiniBarQuickRowView.expandedBarHeight)
        heightC.constant = want ? DeckLayout82.collapsedHeight
            : MiniBarQuickRowView.expandedBarHeight
        blurView.layer.cornerRadius = radius
        glassTint.layer.cornerRadius = radius
        themeLayer.setCornerRadius(radius)
        for content in [coverView, titleLabel, artistLabel, prevButton,
                        playButton, nextButton, consoleButton, rimLight,
                        knobView] {
            content?.isHidden = want
        }
        trackView.layer.cornerRadius = want
            ? DeckLayout82.collapsedTrackHeight / 2
            : DeckLayout82.expandedTrackHeight102 / 2
        NSLayoutConstraint.deactivate(want ? trackExpandedCs : trackCollapsedCs)
        NSLayoutConstraint.activate(want ? trackCollapsedCs : trackExpandedCs)
        let changes = { [weak self] in
            guard let self else { return }
            self.superview?.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.5, delay: 0,
                           usingSpringWithDamping: 0.9,
                           initialSpringVelocity: 0.3, animations: changes)
        } else {
            changes()
        }
        setProgress(lastFraction)
        Breadcrumbs.log("p104 decksearch form=\(want ? "thin" : "full")")
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        guard !isHidden, engine.currentTrack != nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5,
                                         repeats: false) { [weak self] _ in
            guard let self else { return }
            self.setCollapsed(true)
        }
    }

    private func setProgress(_ fraction: Double) {
        lastFraction = fraction
        let clamped = min(1, max(0, fraction))
        fillView.transform = CGAffineTransform(scaleX: max(clamped, 0.0001), y: 1)
        let trackWidth = trackView.bounds.width
        if trackWidth > 0 {
            knobCenterXC.constant = clamped * trackWidth
                - DeckLayout82.knobDiameter102 / 2
        }
    }

    // MARK: - 钮与手势

    @objc private func playTapped() {
        resetIdleTimer()
        engine.togglePlayPause()
    }

    @objc private func prevTapped() {
        resetIdleTimer()
        QueueManager.shared.playPrevious()
    }

    @objc private func nextTapped() {
        resetIdleTimer()
        QueueManager.shared.playNext(manual: true)
    }

    @objc private func consoleTapped() {
        resetIdleTimer()
        guard let host = consoleHost else { return }
        ConsolePanel82.present(from: host)
    }

    private func inButton(_ point: CGPoint) -> Bool {
        [playButton, prevButton, nextButton, consoleButton]
            .contains { $0.frame.contains(point) }
    }

    @objc private func bodyTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if collapsed {
            setCollapsed(false)
            resetIdleTimer()
            return
        }
        if inButton(point) { return }
        // 进度带点按即 seek（展开态轨道上下 12pt 域）。
        let seekZone = trackView.frame.insetBy(dx: 0, dy: -12)
        if seekZone.contains(point), trackView.bounds.width > 0 {
            let fraction = min(1, max(0, Double(
                (point.x - trackView.frame.minX) / trackView.frame.width)))
            if engine.duration > 0 {
                engine.seek(to: fraction * engine.duration)
            }
            resetIdleTimer()
            return
        }
        onOpenStage?()
    }

    @objc private func bodyLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !collapsed,
              MiniPlayerTheme.effectsEnabled else { return }
        if inButton(gesture.location(in: self)) { return }
        let next = MiniPlayerTheme.effective.next
        MiniPlayerTheme.stored = next
        applyTheme()
        NotificationCenter.default.post(
            name: .foliaMiniPlayerThemeChanged, object: nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Breadcrumbs.log("p104 decksearch theme=\(String(describing: next))")
        resetIdleTimer()
    }
}

/// (104) 搜索宿主容器：SwiftUI 搜索页＋搜索台同窗。原
/// (62) 宿主只抱 UIHostingController，台无处落——本容器
/// 把台钉在搜索页之上、底锚与三宿主同口径（安全区底
/// −10、宽 min(宽,高)−24 居中，横竖屏同尺寸）。
final class SearchDeckHostVC104: UIViewController {

    private let hosting: UIViewController
    private let deck = SearchDeck104()
    private var deckWidthC: NSLayoutConstraint?

    init(hosting: UIViewController) {
        self.hosting = hosting
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        deck.translatesAutoresizingMaskIntoConstraints = false
        deck.consoleHost = self
        deck.onOpenStage = { [weak self] in
            guard let self else { return }
            self.openStageFromDeck()
        }
        view.addSubview(deck)

        deckWidthC = deck.widthAnchor.constraint(
            equalToConstant: min(UIScreen.main.bounds.width,
                                 UIScreen.main.bounds.height) - 24)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            deck.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            deck.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            deckWidthC!,
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        deckWidthC?.constant = min(view.bounds.width, view.bounds.height) - 24
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        MiniBarSingleHost.shared.claim("search")
        MiniBarArbiter99.shared.claim(host: "search", bar: deck)
        deck.setActive(true)
        Breadcrumbs.log("p104 decksearch claim=1")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        MiniBarSingleHost.shared.release("search")
        deck.setActive(false)
    }

    /// 点台身进舞台：关搜索后由原呈现者开台（与三宿主
    /// present StageViewController fullScreen 同式）。
    private func openStageFromDeck() {
        let presenter = presentingViewController
        Breadcrumbs.log("p104 decksearch stage=1")
        dismiss(animated: true) {
            guard let presenter else { return }
            let stage = StageViewController()
            stage.modalPresentationStyle = .fullScreen
            presenter.present(stage, animated: true)
        }
    }

    // 右滑退出：沿原 SearchHostPresenter 口径由呈现器以
    // EdgeBack101.install(on: 本容器, page: "search") 装配
    // （左缘起手），本类不另挂手势，防双 pan 打架。
}
