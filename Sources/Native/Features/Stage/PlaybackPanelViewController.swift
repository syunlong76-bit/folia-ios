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
        case cover, controls, queue, lyrics

        var title: String {
            switch self {
            case .cover: return "封面"
            case .controls: return "控制"
            case .queue: return "队列"
            case .lyrics: return "歌词"
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
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        overrideUserInterfaceStyle = .dark
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

        for container in [coverContainer, controlsScroll, queueContainer, lyricsContainer] {
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
        for container in [coverContainer, controlsScroll, queueContainer, lyricsContainer] {
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
        if tab == .queue { embedQueuePanelIfNeeded() }
        if tab == .lyrics { refreshLyricHighlight(scroll: true) }
        Breadcrumbs.log("stage.panel.tab=\(tab.title)")
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

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        lyricLines.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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
        guard lyricLines.indices.contains(indexPath.row) else { return }
        let line = lyricLines[indexPath.row]
        engine.seek(to: line.start)
        currentLyricIndex = indexPath.row
        tableView.reloadData()
        Breadcrumbs.log("stage.panel.lyric.seek idx=\(indexPath.row)"
            + " to=\(String(format: "%.2f", line.start))")
    }
}
