import Combine
import UIKit

// 播放面板（3.7 (55) 工作流 D）：网页版 UnifiedPanel 的原生承接。
// 入口 = 舞台点播台「格子」钮发出的 Notification.Name("FoliaMiniBarPanel")
// （工作流 C 定名），StageViewController 订阅后 present 本面板。
//
// 页签只放有真后端的（对网页 PanelTab 全集裁剪，缺项见报告）：
// - 封面：封面图＋歌名/歌手/专辑＋复制歌曲信息（UIPasteboard 真写）。
// - 控制：播放模式四档（QueueManager.playMode 真切换，置于首行——
//   DS 对账「模式可见」双落点之一，另一落点在舞台主排模式钮）；
//   睡眠定时预设档（SleepTimerController 真设置）；音量条
//   （PlaybackEngine.setVolume / $volume 真接）；打开设置入口
//   （MiniPlayerPanelPresenter.presentSettings 既有通路）。
// - 队列：内嵌现有 QueuePanelViewController 本体（addChild 容器
//   承载，不重写任何队列逻辑）。
// - 歌词：当前曲歌词行列表（LyricRepository 同源行表），当前行
//   高亮（PlaybackEngine.rawPlayhead 真值＋LyricParser.currentIndex，
//   与舞台同一判定口径，不自建第二套歌词时钟——面板定时器只决定
//   「何时重查高亮」，位置真值始终来自引擎锚点真值），点行真 seek
//   （PlaybackEngine.seek(to:)）。
// 网页有而未上的页签：account（账户/音质/同步）、local（本地文件）、
// navi（Navidrome）、onlineLyrics（在线歌词匹配）——原生无对应后端，
// 不放假页签，报告列明。
final class PlaybackPanelViewController: UIViewController {

    enum Tab: Int, CaseIterable {
        case cover, controls, queue, lyrics, quality, local, navidrome

        var title: String {
            switch self {
            case .cover: return "封面"
            case .controls: return "控制"
            case .queue: return "队列"
            case .lyrics: return "歌词"
            case .quality: return "音质"
            case .local: return "本地"
            case .navidrome: return "Navidrome"
            }
        }
    }

    static func present(from presenter: UIViewController,
                        initialTab: Tab = .cover) {
        let panel = PlaybackPanelViewController(initialTab: initialTab)
        panel.modalPresentationStyle = .pageSheet
        if let sheet = panel.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        Breadcrumbs.log("stage.panel.open tab=\(initialTab.title)")
        presenter.present(panel, animated: true)
    }

    private let initialTab: Tab
    private var currentTab: Tab

    private let engine = PlaybackEngine.shared
    private let queueManager = QueueManager.shared
    private var cancellables = Set<AnyCancellable>()

    private let tabSegment = UISegmentedControl(
        items: Tab.allCases.map { $0.title })
    private let coverContainer = UIView()
    private let controlsScroll = UIScrollView()
    private let queueContainer = UIView()
    private let lyricsContainer = UIView()
    // (62) WC 簇三页签容器
    private let qualityContainer = UIView()
    private let localContainer = UIView()
    private let navidromeContainer = UIView()
    private let localTable = UITableView(frame: .zero, style: .insetGrouped)
    private let navidromeTable = UITableView(frame: .zero, style: .insetGrouped)
    private let navidromeStatusLabel = UILabel()
    private var qualityChips: [UIButton] = []
    private var naviRows: [NaviRow62] = []
    private var naviLoaded = false

    private enum NaviRow62 {
        case playlist(NavidromePlaylist62)
        case album(NavidromeAlbum62)
        case track(FoliaTrack)
        case back
    }

    private static let qualityLevels: [(level: String, label: String)] = [
        ("standard", "标准"), ("higher", "较高"), ("exhigh", "极高"),
        ("lossless", "无损"), ("hires", "Hi-Res"),
    ]

    // 封面页签
    private let coverImageView = UIImageView()
    private let coverTitleLabel = UILabel()
    private let coverArtistLabel = UILabel()
    private let coverAlbumLabel = UILabel()

    // 控制页签
    private var modeChips: [UIButton] = []
    private var sleepChips: [UIButton] = []
    private let sleepStateLabel = UILabel()
    private let volumeSlider = UISlider()
    private var sleepCountdown: Timer?

    // 队列页签（内嵌本体）
    private var embeddedQueuePanel: QueuePanelViewController?

    // 歌词页签
    private let lyricsTable = UITableView(frame: .zero, style: .plain)
    private let lyricsEmptyLabel = UILabel()
    private var lyricLines: [LyricLine] = []
    private var lyricTrackId: String?
    private var currentLyricIndex: Int?
    private var lyricHighlightTimer: Timer?

    private static let modes: [(mode: QueueManager.PlayMode, label: String)] = [
        (.off, "顺序"), (.loopAll, "循环"), (.repeatOne, "单曲"), (.shuffle, "随机"),
    ]

    init(initialTab: Tab) {
        self.initialTab = initialTab
        self.currentTab = initialTab
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        WC62Bootstrap.startIfNeeded()
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        overrideUserInterfaceStyle = ThemeSystem62.interfaceStyleOverride() // (62) INT-1：明暗三段读主题系统，不再写死深色
        buildViews()
        bindState()
        showTab(initialTab)
        refreshCover()
        refreshModeChips()
        refreshSleepUI()
        loadLyricsForCurrentTrack()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sleepCountdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            guard let self, SleepTimerController.shared.isActive else { return }
            self.refreshSleepUI()
        }
        lyricHighlightTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self] _ in self?.refreshLyricHighlight(scroll: false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sleepCountdown?.invalidate()
        sleepCountdown = nil
        lyricHighlightTimer?.invalidate()
        lyricHighlightTimer = nil
    }

    // MARK: - 搭建

    private func buildViews() {
        let titleLabel = UILabel()
        titleLabel.text = "播放面板"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        tabSegment.selectedSegmentIndex = initialTab.rawValue
        tabSegment.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        tabSegment.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabSegment)

        // 关闭钮（(62) WC 消费 WA 键 showPanelCloseButton）：
        // 开关关时不显钮，靠下滑手势关面板。
        if SettingsStore.showPanelCloseButton {
            let closeButton = UIButton(type: .system)
            closeButton.setTitle("关闭", for: .normal)
            closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            closeButton.tintColor = .white
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            closeButton.addAction(UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }, for: .touchUpInside)
            view.addSubview(closeButton)
            NSLayoutConstraint.activate([
                closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            ])
        }

        let allContainers: [UIView] = [coverContainer, controlsScroll, queueContainer,
                                       lyricsContainer, qualityContainer,
                                       localContainer, navidromeContainer]
        for container in allContainers {
            container.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(container)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tabSegment.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            tabSegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tabSegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
        for container in allContainers {
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: tabSegment.bottomAnchor, constant: 10),
                container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        buildCoverTab()
        buildControlsTab()
        buildLyricsTab()
        buildQualityTab62()
        buildLocalTab62()
        buildNavidromeTab62()
        // 队列容器在切到队列页签时才挂子 VC（见 showTab），避免未
        // 访问先建整张队列表。
    }

    private func buildCoverTab() {
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 16
        coverImageView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(coverImageView)
        for (label, font, color) in [
            (coverTitleLabel, UIFont.systemFont(ofSize: 19, weight: .semibold), UIColor.white),
            (coverArtistLabel, UIFont.systemFont(ofSize: 15), UIColor.white.withAlphaComponent(0.75)),
            (coverAlbumLabel, UIFont.systemFont(ofSize: 13), UIColor.white.withAlphaComponent(0.5)),
        ] as [(UILabel, UIFont, UIColor)] {
            label.font = font
            label.textColor = color
            label.textAlignment = .center
            label.numberOfLines = 2
            label.translatesAutoresizingMaskIntoConstraints = false
            coverContainer.addSubview(label)
        }
        let copyButton = UIButton(type: .system)
        copyButton.setTitle("复制歌曲信息", for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        copyButton.tintColor = .white
        copyButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        copyButton.layer.cornerRadius = 12
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addTarget(self, action: #selector(copyInfoTapped), for: .touchUpInside)
        coverContainer.addSubview(copyButton)
        NSLayoutConstraint.activate([
            coverImageView.topAnchor.constraint(equalTo: coverContainer.topAnchor, constant: 14),
            coverImageView.centerXAnchor.constraint(equalTo: coverContainer.centerXAnchor),
            coverImageView.widthAnchor.constraint(equalToConstant: 168),
            coverImageView.heightAnchor.constraint(equalToConstant: 168),
            coverTitleLabel.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 16),
            coverTitleLabel.leadingAnchor.constraint(equalTo: coverContainer.leadingAnchor, constant: 24),
            coverTitleLabel.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor, constant: -24),
            coverArtistLabel.topAnchor.constraint(equalTo: coverTitleLabel.bottomAnchor, constant: 5),
            coverArtistLabel.leadingAnchor.constraint(equalTo: coverTitleLabel.leadingAnchor),
            coverArtistLabel.trailingAnchor.constraint(equalTo: coverTitleLabel.trailingAnchor),
            coverAlbumLabel.topAnchor.constraint(equalTo: coverArtistLabel.bottomAnchor, constant: 3),
            coverAlbumLabel.leadingAnchor.constraint(equalTo: coverTitleLabel.leadingAnchor),
            coverAlbumLabel.trailingAnchor.constraint(equalTo: coverTitleLabel.trailingAnchor),
            copyButton.topAnchor.constraint(equalTo: coverAlbumLabel.bottomAnchor, constant: 20),
            copyButton.centerXAnchor.constraint(equalTo: coverContainer.centerXAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 168),
            copyButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func buildControlsTab() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        controlsScroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: controlsScroll.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: controlsScroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: controlsScroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: controlsScroll.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        // 播放模式（首行，DS「模式可见」落点之一）：四档点选真切换。
        stack.addArrangedSubview(sectionLabel("播放模式"))
        let modeStack = UIStackView()
        modeStack.axis = .horizontal
        modeStack.spacing = 8
        modeStack.distribution = .fillEqually
        for entry in Self.modes {
            let chip = makeChip(entry.label)
            chip.addAction(UIAction { [weak self] _ in
                self?.queueManager.playMode = entry.mode
                Breadcrumbs.log("stage.panel.mode=\(entry.mode.rawValue)")
            }, for: .touchUpInside)
            modeStack.addArrangedSubview(chip)
            modeChips.append(chip)
        }
        stack.addArrangedSubview(modeStack)

        // 睡眠定时：预设档真设置＋剩余时间回显。
        let sleepHeader = UIStackView()
        sleepHeader.axis = .horizontal
        sleepHeader.spacing = 8
        sleepHeader.addArrangedSubview(sectionLabel("睡眠定时"))
        sleepStateLabel.font = .systemFont(ofSize: 12)
        sleepStateLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        sleepHeader.addArrangedSubview(sleepStateLabel)
        stack.addArrangedSubview(sleepHeader)
        let sleepStack = UIStackView()
        sleepStack.axis = .horizontal
        sleepStack.spacing = 8
        sleepStack.distribution = .fillEqually
        for minutes in SleepTimerController.presets {
            let chip = makeChip(minutes == 0 ? "关" : "\(minutes)分")
            chip.addAction(UIAction { _ in
                SleepTimerController.shared.set(minutes: minutes)
                Breadcrumbs.log("stage.panel.sleep minutes=\(minutes)")
            }, for: .touchUpInside)
            sleepStack.addArrangedSubview(chip)
            sleepChips.append(chip)
        }
        stack.addArrangedSubview(sleepStack)

        // 音量：PlaybackEngine.setVolume 真接（AVPlayer 本级音量）。
        stack.addArrangedSubview(sectionLabel("音量"))
        volumeSlider.minimumValue = 0
        volumeSlider.maximumValue = 1
        volumeSlider.value = engine.volume
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        stack.addArrangedSubview(volumeSlider)

        // 打开设置：既有设置页通路。
        let settingsButton = UIButton(type: .system)
        settingsButton.setTitle("打开设置", for: .normal)
        settingsButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        settingsButton.tintColor = .white
        settingsButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        settingsButton.layer.cornerRadius = 12
        settingsButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        settingsButton.addTarget(self, action: #selector(openSettingsTapped), for: .touchUpInside)
        stack.addArrangedSubview(settingsButton)
    }

    private func buildLyricsTab() {
        lyricsTable.backgroundColor = .clear
        lyricsTable.separatorStyle = .none
        lyricsTable.rowHeight = 40
        lyricsTable.dataSource = self
        lyricsTable.delegate = self
        lyricsTable.register(UITableViewCell.self, forCellReuseIdentifier: "lyric")
        lyricsTable.translatesAutoresizingMaskIntoConstraints = false
        lyricsContainer.addSubview(lyricsTable)
        lyricsEmptyLabel.text = "暂无歌词"
        lyricsEmptyLabel.font = .systemFont(ofSize: 14)
        lyricsEmptyLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        lyricsEmptyLabel.textAlignment = .center
        lyricsEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        lyricsContainer.addSubview(lyricsEmptyLabel)
        NSLayoutConstraint.activate([
            lyricsTable.topAnchor.constraint(equalTo: lyricsContainer.topAnchor),
            lyricsTable.leadingAnchor.constraint(equalTo: lyricsContainer.leadingAnchor),
            lyricsTable.trailingAnchor.constraint(equalTo: lyricsContainer.trailingAnchor),
            lyricsTable.bottomAnchor.constraint(equalTo: lyricsContainer.bottomAnchor),
            lyricsEmptyLabel.centerXAnchor.constraint(equalTo: lyricsContainer.centerXAnchor),
            lyricsEmptyLabel.centerYAnchor.constraint(equalTo: lyricsContainer.centerYAnchor),
        ])
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        return label
    }

    private func makeChip(_ title: String) -> UIButton {
        let chip = UIButton(type: .system)
        chip.setTitle(title, for: .normal)
        chip.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        chip.layer.cornerRadius = 10
        chip.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return chip
    }

    private func styleChip(_ chip: UIButton, selected: Bool) {
        chip.backgroundColor = selected
            ? UIColor.white.withAlphaComponent(0.28) : UIColor.white.withAlphaComponent(0.08)
        chip.tintColor = selected ? .white : UIColor.white.withAlphaComponent(0.7)
    }

    // MARK: - 页签切换

    @objc private func tabChanged() {
        guard let tab = Tab(rawValue: tabSegment.selectedSegmentIndex) else { return }
        showTab(tab)
    }

    private func showTab(_ tab: Tab) {
        currentTab = tab
        tabSegment.selectedSegmentIndex = tab.rawValue
        coverContainer.isHidden = tab != .cover
        controlsScroll.isHidden = tab != .controls
        queueContainer.isHidden = tab != .queue
        lyricsContainer.isHidden = tab != .lyrics
        qualityContainer.isHidden = tab != .quality
        localContainer.isHidden = tab != .local
        navidromeContainer.isHidden = tab != .navidrome
        if tab == .queue { embedQueuePanelIfNeeded() }
        if tab == .lyrics { refreshLyricHighlight(scroll: true) }
        if tab == .local { localTable.reloadData() }
        if tab == .navidrome && !naviLoaded { loadNavidromeRoot62() }
        Breadcrumbs.log("stage.panel.tab=\(tab.title)")
    }

    // MARK: - (62) 音质页签

    private func buildQualityTab62() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        qualityContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: qualityContainer.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: qualityContainer.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: qualityContainer.trailingAnchor, constant: -20),
        ])
        stack.addArrangedSubview(sectionLabel("取流音质（下一首生效）"))
        let chipsStack = UIStackView()
        chipsStack.axis = .horizontal
        chipsStack.spacing = 8
        chipsStack.distribution = .fillEqually
        for entry in Self.qualityLevels {
            let chip = makeChip(entry.label)
            chip.addAction(UIAction { [weak self] _ in
                SettingsStore.streamQuality62 = entry.level
                Breadcrumbs.log("stage.panel.quality level=\(entry.level)")
                self?.refreshQualityChips62()
            }, for: .touchUpInside)
            chipsStack.addArrangedSubview(chip)
            qualityChips.append(chip)
        }
        stack.addArrangedSubview(chipsStack)
        let hint = UILabel()
        hint.text = "档位经取流参数 level 透传到网易云 /song/url/v1；无损/Hi-Res 是否给流取决于账号与后端，拿到空地址时按不可播处理并如实报错，不假装已生效。"
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = UIColor.white.withAlphaComponent(0.5)
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)
        refreshQualityChips62()
    }

    private func refreshQualityChips62() {
        for (index, chip) in qualityChips.enumerated() {
            styleChip(chip, selected: Self.qualityLevels[index].level == SettingsStore.streamQuality62)
        }
    }

    // MARK: - (62) 本地页签

    private func buildLocalTab62() {
        localTable.backgroundColor = .clear
        localTable.dataSource = self
        localTable.delegate = self
        localTable.register(UITableViewCell.self, forCellReuseIdentifier: "local62")
        localTable.translatesAutoresizingMaskIntoConstraints = false
        localContainer.addSubview(localTable)
        NSLayoutConstraint.activate([
            localTable.topAnchor.constraint(equalTo: localContainer.topAnchor),
            localTable.leadingAnchor.constraint(equalTo: localContainer.leadingAnchor),
            localTable.trailingAnchor.constraint(equalTo: localContainer.trailingAnchor),
            localTable.bottomAnchor.constraint(equalTo: localContainer.bottomAnchor),
        ])
        // 歌词页签长按导出（歌词导出三入口之一）。
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(lyricsLongPressed62(_:)))
        lyricsTable.addGestureRecognizer(longPress)
    }

    @objc private func lyricsLongPressed62(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let track = engine.currentTrack else { return }
        Breadcrumbs.log("stage.panel.lyric.longpress export id=\(track.id)")
        LyricExport62.export(track: track, from: self)
    }

    // MARK: - (62) Navidrome 页签

    private func buildNavidromeTab62() {
        navidromeTable.backgroundColor = .clear
        navidromeTable.dataSource = self
        navidromeTable.delegate = self
        navidromeTable.register(UITableViewCell.self, forCellReuseIdentifier: "navi62")
        navidromeTable.translatesAutoresizingMaskIntoConstraints = false
        navidromeContainer.addSubview(navidromeTable)
        navidromeStatusLabel.font = .systemFont(ofSize: 13)
        navidromeStatusLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        navidromeStatusLabel.numberOfLines = 0
        navidromeStatusLabel.textAlignment = .center
        navidromeStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        navidromeContainer.addSubview(navidromeStatusLabel)
        NSLayoutConstraint.activate([
            navidromeTable.topAnchor.constraint(equalTo: navidromeContainer.topAnchor),
            navidromeTable.leadingAnchor.constraint(equalTo: navidromeContainer.leadingAnchor),
            navidromeTable.trailingAnchor.constraint(equalTo: navidromeContainer.trailingAnchor),
            navidromeTable.bottomAnchor.constraint(equalTo: navidromeContainer.bottomAnchor),
            navidromeStatusLabel.centerXAnchor.constraint(equalTo: navidromeContainer.centerXAnchor),
            navidromeStatusLabel.centerYAnchor.constraint(equalTo: navidromeContainer.centerYAnchor),
            navidromeStatusLabel.leadingAnchor.constraint(equalTo: navidromeContainer.leadingAnchor, constant: 32),
            navidromeStatusLabel.trailingAnchor.constraint(equalTo: navidromeContainer.trailingAnchor, constant: -32),
        ])
    }

    private func loadNavidromeRoot62() {
        naviLoaded = true
        guard SettingsStore.navidromeEnabled62, NavidromeClient62.shared.isConfigured else {
            navidromeStatusLabel.text = "Navidrome 未开启或未配置（设置 → 连接与集成）"
            return
        }
        navidromeStatusLabel.text = "加载中…"
        Task { @MainActor in
            do {
                async let playlistsTask = NavidromeClient62.shared.fetchPlaylists()
                async let albumsTask = NavidromeClient62.shared.fetchAlbumList()
                let playlists = try await playlistsTask
                let albums = try await albumsTask
                let rows = playlists.map(NaviRow62.playlist) + albums.map(NaviRow62.album)
                self.naviRows = rows
                self.navidromeStatusLabel.text = rows.isEmpty ? "服务器上暂无歌单/专辑" : nil
                self.navidromeTable.reloadData()
            } catch {
                self.navidromeStatusLabel.text = "加载失败：\(error.localizedDescription)"
            }
        }
    }

    private func loadNavidromeDirectory62(id: String) {
        navidromeStatusLabel.text = "加载中…"
        Task { @MainActor in
            do {
                let dir = try await NavidromeClient62.shared.fetchDirectory(id: id)
                var rows: [NaviRow62] = [.back]
                rows += dir.childAlbums.map(NaviRow62.album)
                rows += dir.childTracks.map(NaviRow62.track)
                self.naviRows = rows
                self.navidromeStatusLabel.text = nil
                self.navidromeTable.reloadData()
            } catch {
                self.navidromeStatusLabel.text = "加载失败：\(error.localizedDescription)"
            }
        }
    }

    private func embedQueuePanelIfNeeded() {
        guard embeddedQueuePanel == nil else { return }
        let panel = QueuePanelViewController()
        addChild(panel)
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        queueContainer.addSubview(panel.view)
        NSLayoutConstraint.activate([
            panel.view.topAnchor.constraint(equalTo: queueContainer.topAnchor),
            panel.view.leadingAnchor.constraint(equalTo: queueContainer.leadingAnchor),
            panel.view.trailingAnchor.constraint(equalTo: queueContainer.trailingAnchor),
            panel.view.bottomAnchor.constraint(equalTo: queueContainer.bottomAnchor),
        ])
        panel.didMove(toParent: self)
        embeddedQueuePanel = panel
        Breadcrumbs.log("stage.panel.queue embedded")
    }

    // MARK: - 状态绑定

    private func bindState() {
        engine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCover()
                self?.loadLyricsForCurrentTrack()
            }
            .store(in: &cancellables)
        engine.$currentArtwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshCover() }
            .store(in: &cancellables)
        engine.$volume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, !self.volumeSlider.isTracking else { return }
                self.volumeSlider.value = value
            }
            .store(in: &cancellables)
        queueManager.$playMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshModeChips() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(
            for: SleepTimerController.changedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSleepUI() }
            .store(in: &cancellables)
    }

    private func refreshCover() {
        let track = engine.currentTrack
        coverTitleLabel.text = track?.title ?? "暂无播放"
        coverArtistLabel.text = track?.artist ?? ""
        coverAlbumLabel.text = track?.album ?? ""
        if let artwork = engine.currentArtwork {
            coverImageView.image = artwork
        } else if let raw = track?.artworkURL?.absoluteString {
            // 封面兜底与舞台同路：NativeCoverLoader 代理档位取图。
            let loader = NativeCoverLoader.shared
            let urlString = loader.proxiedURLString(raw, tier: 512) ?? raw
            Task { [weak self] in
                let image = await loader.image(for: urlString, tier: 512)
                guard let self, let image,
                      self.engine.currentArtwork == nil,
                      self.engine.currentTrack?.artworkURL?.absoluteString == raw
                else { return }
                self.coverImageView.image = image
            }
        } else {
            coverImageView.image = nil
        }
    }

    private func refreshModeChips() {
        for (index, chip) in modeChips.enumerated() {
            styleChip(chip, selected: Self.modes[index].mode == queueManager.playMode)
        }
    }

    private func refreshSleepUI() {
        let timer = SleepTimerController.shared
        for (index, chip) in sleepChips.enumerated() {
            let minutes = SleepTimerController.presets[index]
            let selected = timer.isActive
                ? (timer.activePresetMinutes == minutes && minutes > 0)
                : minutes == 0
            styleChip(chip, selected: selected)
        }
        if let remaining = timer.remainingSeconds, timer.isActive {
            let total = Int(remaining.rounded())
            sleepStateLabel.text = String(format: "剩 %d:%02d 后暂停", total / 60, total % 60)
        } else {
            sleepStateLabel.text = ""
        }
    }

    // MARK: - 歌词页签

    private func loadLyricsForCurrentTrack() {
        guard let track = engine.currentTrack else {
            lyricLines = []
            lyricTrackId = nil
            currentLyricIndex = nil
            lyricsTable.reloadData()
            lyricsEmptyLabel.isHidden = false
            return
        }
        guard lyricTrackId != track.id else { return }
        lyricTrackId = track.id
        currentLyricIndex = nil
        if let hit = LyricRepository.shared.cachedEntry(for: track.id) {
            lyricLines = LyricParser.stageLines(
                from: hit.lines, trackDuration: track.duration,
                singingRatio: hit.singingRatio)
            lyricsTable.reloadData()
            lyricsEmptyLabel.isHidden = !lyricLines.isEmpty
            refreshLyricHighlight(scroll: true)
            return
        }
        let trackId = track.id
        let duration = track.duration
        Task { [weak self] in
            let entry = await LyricRepository.shared.entry(for: trackId)
            guard let self, self.lyricTrackId == trackId else { return }
            self.lyricLines = LyricParser.stageLines(
                from: entry.lines, trackDuration: duration,
                singingRatio: entry.singingRatio)
            self.lyricsTable.reloadData()
            self.lyricsEmptyLabel.isHidden = !self.lyricLines.isEmpty
            self.refreshLyricHighlight(scroll: true)
        }
    }

    private func refreshLyricHighlight(scroll: Bool) {
        guard currentTab == .lyrics, !lyricLines.isEmpty else { return }
        let idx = LyricParser.currentIndex(in: lyricLines, at: engine.rawPlayhead())
        guard idx != currentLyricIndex else { return }
        let old = currentLyricIndex
        currentLyricIndex = idx
        var rows: [IndexPath] = []
        if let old, lyricLines.indices.contains(old) {
            rows.append(IndexPath(row: old, section: 0))
        }
        if let idx, lyricLines.indices.contains(idx) {
            rows.append(IndexPath(row: idx, section: 0))
        }
        if !rows.isEmpty {
            lyricsTable.reloadRows(at: rows, with: .none)
        }
        if scroll, let idx, lyricLines.indices.contains(idx) {
            lyricsTable.scrollToRow(at: IndexPath(row: idx, section: 0),
                                    at: .middle, animated: true)
        }
    }

    // MARK: - 动作

    @objc private func copyInfoTapped() {
        guard let track = engine.currentTrack else { return }
        var parts = [track.title, track.artist]
        if !track.album.isEmpty { parts.append(track.album) }
        UIPasteboard.general.string = parts.joined(separator: " - ")
        Breadcrumbs.log("stage.panel.copyinfo id=\(track.id)")
        NativePlaybackFailureToast.show(message: "歌曲信息已复制")
    }

    @objc private func volumeChanged() {
        engine.setVolume(volumeSlider.value)
    }

    @objc private func openSettingsTapped() {
        Breadcrumbs.log("stage.panel.openSettings")
        MiniPlayerPanelPresenter.presentSettings()
    }
}

// MARK: - 歌词列表

extension PlaybackPanelViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        // 本地页签两段（本地曲库/已缓存）；其余表一段。
        tableView == localTable ? 2 : 1
    }

    func tableView(_ tableView: UITableView,
                   titleForHeaderInSection section: Int) -> String? {
        guard tableView == localTable else { return nil }
        return section == 0 ? "本地曲库" : "已缓存歌曲"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == localTable {
            return section == 0
                ? LocalLibrary62.shared.sortedTracks().count
                : MediaCache62.shared.cachedTracks().count
        }
        if tableView == navidromeTable { return naviRows.count }
        return lyricLines.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == localTable {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "local62", for: indexPath)
            let track = indexPath.section == 0
                ? LocalLibrary62.shared.sortedTracks()[indexPath.row]
                : MediaCache62.shared.cachedTracks()[indexPath.row]
            var config = cell.defaultContentConfiguration()
            config.text = track.title
            config.secondaryText = "\(track.artist) · \(track.album)"
            config.textProperties.color = .white
            config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.5)
            cell.contentConfiguration = config
            cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
            return cell
        }
        if tableView == navidromeTable {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "navi62", for: indexPath)
            var config = cell.defaultContentConfiguration()
            switch naviRows[indexPath.row] {
            case .back:
                config.text = "‹ 返回歌单/专辑"
            case .playlist(let playlist):
                config.text = playlist.name
                config.secondaryText = "歌单 · \(playlist.songCount) 首"
            case .album(let album):
                config.text = album.name
                config.secondaryText = "专辑 · \(album.artist)"
            case .track(let track):
                config.text = track.title
                config.secondaryText = "\(track.artist) · \(track.album)"
            }
            config.textProperties.color = .white
            config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.5)
            cell.contentConfiguration = config
            cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
            return cell
        }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "lyric", for: indexPath)
        let line = lyricLines[indexPath.row]
        let isCurrent = indexPath.row == currentLyricIndex
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.textLabel?.text = line.text
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.font = .systemFont(
            ofSize: 15, weight: isCurrent ? .semibold : .regular)
        cell.textLabel?.textColor = isCurrent
            ? .white : UIColor.white.withAlphaComponent(0.55)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        if tableView == localTable {
            if indexPath.section == 0 {
                let tracks = LocalLibrary62.shared.sortedTracks()
                guard tracks.indices.contains(indexPath.row) else { return }
                QueueManager.shared.setQueue(tracks, startingAt: indexPath.row,
                                             source: "panel-local62")
                Breadcrumbs.log("stage.panel.local.play idx=\(indexPath.row)")
            } else {
                let tracks = MediaCache62.shared.cachedTracks()
                guard tracks.indices.contains(indexPath.row) else { return }
                QueueManager.shared.setQueue(tracks, startingAt: indexPath.row,
                                             source: "panel-cache62")
                Breadcrumbs.log("stage.panel.cache.play idx=\(indexPath.row)")
            }
            return
        }
        if tableView == navidromeTable {
            guard naviRows.indices.contains(indexPath.row) else { return }
            switch naviRows[indexPath.row] {
            case .back:
                loadNavidromeRoot62()
            case .playlist(let playlist):
                loadNavidromeDirectory62(id: playlist.id)
            case .album(let album):
                loadNavidromeDirectory62(id: album.id)
            case .track(let track):
                NavidromeBrowser62ViewController.playViaEngine(track: track)
            }
            return
        }
        guard lyricLines.indices.contains(indexPath.row) else { return }
        let line = lyricLines[indexPath.row]
        engine.seek(to: line.start)
        currentLyricIndex = indexPath.row
        tableView.reloadData()
        Breadcrumbs.log("stage.panel.lyric.seek idx=\(indexPath.row)"
            + " to=\(String(format: "%.2f", line.start))")
    }
}
