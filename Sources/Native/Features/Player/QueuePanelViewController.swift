import UIKit
import Combine

/// 播放列表面板（3.7 (48) 点播台管理搬入）。
///
/// 网页版点播台管理面（QueueTab + createQueueMutations + 睡眠定时）的
/// 原生承接：队列查看/点歌跳播/拖拽排序/行操作（下一首·移到末尾·移除）
/// ＋管理区（播放模式四档、打乱队列、清空队列、定时关闭预设档）。
/// 形态为原生 sheet（.medium/.large），不改变点播台本身的外观结构；
/// 墙面台与舞台台共用此面板，状态全部同源 QueueManager。
final class QueuePanelViewController: UIViewController {

    /// 面板关闭回调（两台用它重置无操作计时）。
    var onDismiss: (() -> Void)?

    static func present(from presenter: UIViewController,
                        onDismiss: (() -> Void)? = nil) {
        let panel = QueuePanelViewController()
        panel.onDismiss = onDismiss
        panel.modalPresentationStyle = .pageSheet
        if let sheet = panel.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        Breadcrumbs.log("queue.panel.open")
        presenter.present(panel, animated: true)
    }

    // MARK: - 状态

    private let queueManager = QueueManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var tracks: [FoliaTrack] = []
    private var currentIndex: Int = 0
    private var dragInFlight = false
    private var didScrollToCurrent = false
    private var countdownTimer: Timer?

    // MARK: - 视图

    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let modeChipsStack = UIStackView()
    private let sleepChipsStack = UIStackView()
    private let sleepStateLabel = UILabel()
    private var modeChips: [UIButton] = []
    private var sleepChips: [UIButton] = []
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    private static let modes: [(mode: QueueManager.PlayMode, label: String)] = [
        (.off, "顺序"), (.loopAll, "循环"), (.repeatOne, "单曲"), (.shuffle, "随机"),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        buildViews()
        bindState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didScrollToCurrent, !tracks.isEmpty {
            didScrollToCurrent = true
            let row = min(max(currentIndex, 0), tracks.count - 1)
            tableView.scrollToRow(at: IndexPath(row: row, section: 0),
                                  at: .middle, animated: false)
        }
        startCountdown()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        countdownTimer?.invalidate()
        countdownTimer = nil
        if isBeingDismissed {
            onDismiss?()
        }
    }

    // MARK: - 搭建

    private func buildViews() {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blur)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blur.topAnchor.constraint(equalTo: view.topAnchor),
            blur.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)

        // 标题行
        titleLabel.text = "播放列表"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        countLabel.font = .systemFont(ofSize: 13)
        countLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countLabel)
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.8)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        // 管理卡
        let card = UIView()
        card.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        card.layer.cornerRadius = 14
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let modeTitle = sectionLabel("播放模式")
        card.addSubview(modeTitle)
        modeChipsStack.axis = .horizontal
        modeChipsStack.spacing = 8
        modeChipsStack.distribution = .fillEqually
        modeChipsStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(modeChipsStack)
        modeChips = Self.modes.map { entry in
            let chip = makeChip(entry.label)
            chip.addAction(UIAction { [weak self] _ in
                self?.queueManager.playMode = entry.mode
                Breadcrumbs.log("queue.panel.mode=\(entry.mode.rawValue)")
            }, for: .touchUpInside)
            modeChipsStack.addArrangedSubview(chip)
            return chip
        }

        let divider1 = divider()
        card.addSubview(divider1)

        let sleepTitle = sectionLabel("定时关闭")
        card.addSubview(sleepTitle)
        sleepStateLabel.font = .systemFont(ofSize: 12)
        sleepStateLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        sleepStateLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(sleepStateLabel)
        sleepChipsStack.axis = .horizontal
        sleepChipsStack.spacing = 8
        sleepChipsStack.distribution = .fillEqually
        sleepChipsStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(sleepChipsStack)
        sleepChips = SleepTimerController.presets.map { minutes in
            let chip = makeChip(minutes == 0 ? "关" : "\(minutes)")
            chip.addAction(UIAction { _ in
                SleepTimerController.shared.set(minutes: minutes)
            }, for: .touchUpInside)
            sleepChipsStack.addArrangedSubview(chip)
            return chip
        }

        let divider2 = divider()
        card.addSubview(divider2)

        let shuffleRow = actionRow(icon: "shuffle", title: "打乱队列",
                                   color: .white, action: #selector(shuffleTapped))
        card.addSubview(shuffleRow)
        let clearRow = actionRow(icon: "trash", title: "清空队列",
                                 color: UIColor(red: 1, green: 0.42, blue: 0.42, alpha: 1),
                                 action: #selector(clearTapped))
        card.addSubview(clearRow)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            card.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),

            modeTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            modeTitle.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            modeChipsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            modeChipsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            modeChipsStack.topAnchor.constraint(equalTo: modeTitle.bottomAnchor, constant: 8),
            modeChipsStack.heightAnchor.constraint(equalToConstant: 30),

            divider1.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            divider1.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            divider1.topAnchor.constraint(equalTo: modeChipsStack.bottomAnchor, constant: 12),
            divider1.heightAnchor.constraint(equalToConstant: 0.5),

            sleepTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            sleepTitle.topAnchor.constraint(equalTo: divider1.bottomAnchor, constant: 12),
            sleepStateLabel.leadingAnchor.constraint(equalTo: sleepTitle.trailingAnchor, constant: 8),
            sleepStateLabel.centerYAnchor.constraint(equalTo: sleepTitle.centerYAnchor),
            sleepChipsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            sleepChipsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            sleepChipsStack.topAnchor.constraint(equalTo: sleepTitle.bottomAnchor, constant: 8),
            sleepChipsStack.heightAnchor.constraint(equalToConstant: 30),

            divider2.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            divider2.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            divider2.topAnchor.constraint(equalTo: sleepChipsStack.bottomAnchor, constant: 12),
            divider2.heightAnchor.constraint(equalToConstant: 0.5),

            shuffleRow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            shuffleRow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            shuffleRow.topAnchor.constraint(equalTo: divider2.bottomAnchor, constant: 4),
            shuffleRow.heightAnchor.constraint(equalToConstant: 42),
            clearRow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            clearRow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            clearRow.topAnchor.constraint(equalTo: shuffleRow.bottomAnchor),
            clearRow.heightAnchor.constraint(equalToConstant: 42),
            clearRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
        ])

        // 队列表
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 60
        tableView.dataSource = self
        tableView.delegate = self
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        tableView.register(QueueTrackCell.self,
                           forCellReuseIdentifier: QueueTrackCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.text = "队列是空的"
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 10),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 48),
        ])
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func divider() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func makeChip(_ title: String) -> UIButton {
        let chip = UIButton(type: .system)
        chip.setTitle(title, for: .normal)
        chip.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        chip.layer.cornerRadius = 15
        chip.clipsToBounds = true
        return chip
    }

    private func styleChip(_ chip: UIButton, selected: Bool) {
        if selected {
            chip.backgroundColor = UIColor.white.withAlphaComponent(0.92)
            chip.setTitleColor(.black, for: .normal)
        } else {
            chip.backgroundColor = UIColor.white.withAlphaComponent(0.10)
            chip.setTitleColor(UIColor.white.withAlphaComponent(0.85), for: .normal)
        }
    }

    private func actionRow(icon: String, title: String, color: UIColor,
                           action: Selector) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let imageView = UIImageView(image: UIImage(systemName: icon))
        imageView.tintColor = color
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(imageView)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14.5)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        row.addSubview(button)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            imageView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.topAnchor.constraint(equalTo: row.topAnchor),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    // MARK: - 状态绑定

    private func bindState() {
        queueManager.$queue
            .combineLatest(queueManager.$currentIndex)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue, index in
                guard let self else { return }
                self.tracks = queue
                self.currentIndex = index
                self.countLabel.text = queue.isEmpty ? "" : "\(queue.count) 首"
                self.emptyLabel.isHidden = !queue.isEmpty
                if !self.dragInFlight { self.tableView.reloadData() }
            }
            .store(in: &cancellables)
        queueManager.$playMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self else { return }
                for (i, entry) in Self.modes.enumerated() {
                    self.styleChip(self.modeChips[i], selected: entry.mode == mode)
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(
            for: SleepTimerController.changedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSleepUI() }
            .store(in: &cancellables)
        refreshSleepUI()
    }

    private func refreshSleepUI() {
        let timer = SleepTimerController.shared
        for (i, chip) in sleepChips.enumerated() {
            let minutes = SleepTimerController.presets[i]
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

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            guard let self, SleepTimerController.shared.isActive else { return }
            self.refreshSleepUI()
        }
    }

    // MARK: - 动作

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func shuffleTapped() {
        queueManager.shuffleQueue()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func clearTapped() {
        guard !tracks.isEmpty else { return }
        let alert = UIAlertController(
            title: "清空队列",
            message: "将停止播放并移除全部 \(tracks.count) 首歌曲。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) {
            [weak self] _ in
            self?.queueManager.clearQueue()
        })
        present(alert, animated: true)
    }
}

// MARK: - 队列表

extension QueuePanelViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tracks.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: QueueTrackCell.reuseId, for: indexPath) as! QueueTrackCell
        cell.configure(track: tracks[indexPath.row],
                       index: indexPath.row,
                       isCurrent: indexPath.row == currentIndex)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row != currentIndex else { return }
        queueManager.playAtIndex(indexPath.row)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        let row = indexPath.row
        let remove = UIContextualAction(style: .destructive, title: "移除") {
            [weak self] _, _, done in
            self?.queueManager.removeFromQueue(at: row)
            done(true)
        }
        remove.image = UIImage(systemName: "trash")
        var actions: [UIContextualAction] = [remove]
        if row != currentIndex {
            let toEnd = UIContextualAction(style: .normal, title: "移到末尾") {
                [weak self] _, _, done in
                self?.queueManager.moveToEnd(at: row)
                done(true)
            }
            toEnd.image = UIImage(systemName: "arrow.down.to.line")
            toEnd.backgroundColor = UIColor(white: 0.32, alpha: 1)
            actions.append(toEnd)
            if row != currentIndex + 1 {
                let playNext = UIContextualAction(style: .normal, title: "下一首") {
                    [weak self] _, _, done in
                    self?.queueManager.moveToNext(at: row)
                    done(true)
                }
                playNext.image = UIImage(systemName: "text.line.first.and.arrowtriangle.forward")
                playNext.backgroundColor = UIColor(red: 0.25, green: 0.45, blue: 0.95, alpha: 1)
                actions.append(playNext)
            }
        }
        let config = UISwipeActionsConfiguration(actions: actions)
        config.performsFirstActionWithFullSwipe = false
        return config
    }
}

// MARK: - 拖拽排序

extension QueuePanelViewController: UITableViewDragDelegate, UITableViewDropDelegate {

    func tableView(_ tableView: UITableView,
                   itemsForBeginning session: UIDragSession,
                   at indexPath: IndexPath) -> [UIDragItem] {
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = indexPath.row
        return [item]
    }

    func tableView(_ tableView: UITableView, dragSessionWillBegin session: UIDragSession) {
        dragInFlight = true
    }

    func tableView(_ tableView: UITableView, dragSessionDidEnd session: UIDragSession) {
        dragInFlight = false
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView,
                   canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil
    }

    func tableView(_ tableView: UITableView,
                   dropSessionDidUpdate session: UIDropSession,
                   withDestinationIndexPath destinationIndexPath: IndexPath?)
        -> UITableViewDropProposal {
        UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView,
                   performDropWith coordinator: UITableViewDropCoordinator) {
        guard let item = coordinator.items.first,
              let source = item.dragItem.localObject as? Int,
              let destination = coordinator.destinationIndexPath?.row else { return }
        queueManager.moveQueueItem(from: source, to: destination)
    }
}

// MARK: - 队列行

final class QueueTrackCell: UITableViewCell {

    static let reuseId = "QueueTrackCell"

    private let stateIcon = UIImageView()
    private let indexLabel = UILabel()
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private var coverTask: Task<Void, Never>?
    private var trackId: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        stateIcon.tintColor = UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 1)
        stateIcon.contentMode = .scaleAspectFit
        stateIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stateIcon)
        indexLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        indexLabel.textColor = UIColor.white.withAlphaComponent(0.4)
        indexLabel.textAlignment = .center
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(indexLabel)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 6
        coverView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        artistLabel.font = .systemFont(ofSize: 12.5)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artistLabel)

        NSLayoutConstraint.activate([
            stateIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stateIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stateIcon.widthAnchor.constraint(equalToConstant: 20),
            stateIcon.heightAnchor.constraint(equalToConstant: 20),
            indexLabel.centerXAnchor.constraint(equalTo: stateIcon.centerXAnchor),
            indexLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.leadingAnchor.constraint(equalTo: stateIcon.trailingAnchor, constant: 12),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 40),
            coverView.heightAnchor.constraint(equalToConstant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverTask?.cancel()
        coverTask = nil
        trackId = nil
        coverView.image = nil
    }

    func configure(track: FoliaTrack, index: Int, isCurrent: Bool) {
        trackId = track.id
        titleLabel.text = track.title
        artistLabel.text = track.artist
        titleLabel.font = .systemFont(ofSize: 15, weight: isCurrent ? .semibold : .medium)
        stateIcon.image = isCurrent ? UIImage(systemName: "speaker.wave.2.fill") : nil
        stateIcon.isHidden = !isCurrent
        indexLabel.text = isCurrent ? "" : "\(index + 1)"
        indexLabel.isHidden = isCurrent

        coverView.image = nil
        guard let raw = track.artworkURL?.absoluteString else { return }
        let loader = NativeCoverLoader.shared
        if let cached = loader.cachedImage(for: raw)
            ?? loader.cachedImageAnyTier(raw: raw, excludingTier: -1) {
            coverView.image = cached
            return
        }
        let id = track.id
        coverTask = Task { [weak self] in
            let image = await loader.image(for: raw, tier: 256)
            guard let self, self.trackId == id, let image else { return }
            self.coverView.image = image
        }
    }
}
