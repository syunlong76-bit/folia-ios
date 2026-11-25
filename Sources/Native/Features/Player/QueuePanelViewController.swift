import UIKit
import Combine

/// 播放列表面板（3.7 (48) 点播台管理搬入）。
///
/// 网页版点播台管理面（QueueTab + createQueueMutations + 睡眠定时）的
/// 原生承接：队列查看/点歌跳播/拖拽排序/行操作（下一首·移到末尾·移除）
/// ＋管理区（播放模式四档、打乱队列、清空队列、定时关闭预设档）。
/// 形态为原生 sheet（.medium/.large），不改变点播台本身的外观结构；
/// 墙面台与舞台台共用此面板，状态全部同源 QueueManager。
///
/// (87) 队列封面模块：队列区由文字行表改封面网格
/// （CoverGridCell87，金环＋律动、点格切歌、长按出动作
/// 菜单、拖拽排序走 moveQueueItem）；本机歌单保留行表
/// 在网格下方；表格多选批量条随文字行退役（长按菜单承
/// 接移除/移到末尾/下一首，报告注明取舍）；管理卡加功
/// 能三件入口（评论/歌曲资料/听歌统计，对象＝当前曲）。
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
    /// 本机歌单镜像（3.7 (50)）：LocalPlaylistStore.$playlists 订阅回填。
    private var localPlaylists: [LocalPlaylistStore.LocalPlaylist] = []

    // MARK: - 视图

    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let editButton = UIButton(type: .system)
    /// 批量操作条（3.7 (50) 多选）：编辑态才显，浮在列表底部。
    private let batchBar = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let batchCountLabel = UILabel()
    private let batchRemoveButton = UIButton(type: .system)
    private let batchMoveEndButton = UIButton(type: .system)
    private let modeChipsStack = UIStackView()
    private let sleepChipsStack = UIStackView()
    private let sleepStateLabel = UILabel()
    /// 头部睡眠定时状态行（3.7 (55) 工作流 D/DS 修正3，仅头部）：
    /// 标题行与管理卡之间的一行状态——有定时：月亮图标＋「睡眠
    /// 定时 · 剩 m:ss」＋取消钮；无定时：整行是「睡眠定时」入口，
    /// 点开预设菜单（与管理卡定时档同源 SleepTimerController）。
    /// 队列行逻辑零改动；刷新挂在既有 refreshSleepUI 末尾（睡眠
    /// 变更通知与 1 秒倒计时都经它），状态天然同源。
    private let sleepHeaderRow = UIView()
    private let sleepHeaderLabel = UILabel()
    private let sleepHeaderCancelButton = UIButton(type: .system)
    private var modeChips: [UIButton] = []
    private var sleepChips: [UIButton] = []
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    /// (87) 队列封面网格＋歌单表高度约束（无歌单时收 0、
    /// 网格吃满剩余高度）。
    private var grid87: UICollectionView!
    private var tableHeight87: NSLayoutConstraint?

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
            // (87) 定位当前曲改走封面网格。
            grid87?.scrollToItem(at: IndexPath(item: row, section: 0),
                                 at: .centeredVertically, animated: false)
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
        // (89) §7-4：头行标题对齐网页 QueueTab 头行 13 semibold
        //（头行总高由关闭钮 36 决定、与网页 HEAD_PX 36 同值）。
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
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
        // 编辑（多选）入口（3.7 (50)）：标题行、关闭键左侧。
        editButton.setTitle("编辑", for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 15)
        editButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        view.addSubview(editButton)

        // 头部睡眠定时状态行（3.7 (55) 工作流 D/DS 修正3）
        sleepHeaderRow.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        sleepHeaderRow.layer.cornerRadius = 10
        sleepHeaderRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sleepHeaderRow)
        let sleepHeaderIcon = UIImageView(
            image: UIImage(systemName: "moon.zzz"))
        sleepHeaderIcon.tintColor = UIColor.white.withAlphaComponent(0.75)
        sleepHeaderIcon.translatesAutoresizingMaskIntoConstraints = false
        sleepHeaderRow.addSubview(sleepHeaderIcon)
        sleepHeaderLabel.font = .systemFont(ofSize: 13, weight: .medium)
        sleepHeaderLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        sleepHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        sleepHeaderRow.addSubview(sleepHeaderLabel)
        sleepHeaderCancelButton.setTitle("取消", for: .normal)
        sleepHeaderCancelButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        sleepHeaderCancelButton.tintColor = UIColor(red: 1, green: 0.42, blue: 0.42, alpha: 1)
        sleepHeaderCancelButton.translatesAutoresizingMaskIntoConstraints = false
        sleepHeaderCancelButton.addTarget(
            self, action: #selector(sleepHeaderCancelTapped), for: .touchUpInside)
        sleepHeaderRow.addSubview(sleepHeaderCancelButton)
        let sleepHeaderTap = UITapGestureRecognizer(
            target: self, action: #selector(sleepHeaderRowTapped))
        sleepHeaderRow.addGestureRecognizer(sleepHeaderTap)
        NSLayoutConstraint.activate([
            sleepHeaderRow.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            sleepHeaderRow.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            sleepHeaderRow.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            sleepHeaderRow.heightAnchor.constraint(equalToConstant: 36),
            sleepHeaderIcon.leadingAnchor.constraint(equalTo: sleepHeaderRow.leadingAnchor, constant: 12),
            sleepHeaderIcon.centerYAnchor.constraint(equalTo: sleepHeaderRow.centerYAnchor),
            sleepHeaderIcon.widthAnchor.constraint(equalToConstant: 16),
            sleepHeaderIcon.heightAnchor.constraint(equalToConstant: 16),
            sleepHeaderLabel.leadingAnchor.constraint(equalTo: sleepHeaderIcon.trailingAnchor, constant: 8),
            sleepHeaderLabel.centerYAnchor.constraint(equalTo: sleepHeaderRow.centerYAnchor),
            sleepHeaderCancelButton.trailingAnchor.constraint(equalTo: sleepHeaderRow.trailingAnchor, constant: -8),
            sleepHeaderCancelButton.centerYAnchor.constraint(equalTo: sleepHeaderRow.centerYAnchor),
            sleepHeaderCancelButton.widthAnchor.constraint(equalToConstant: 48),
            sleepHeaderCancelButton.heightAnchor.constraint(equalToConstant: 32),
            sleepHeaderLabel.trailingAnchor.constraint(lessThanOrEqualTo: sleepHeaderCancelButton.leadingAnchor, constant: -8),
        ])

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
        // 保存为本机歌单（3.7 (50)，(48) 挂账②）：整队命名存本机。
        let saveRow = actionRow(icon: "square.and.arrow.down", title: "保存为歌单",
                                color: .white, action: #selector(savePlaylistTapped))
        card.addSubview(saveRow)

        // (87) 功能三件入口（对象＝当前播放曲）。
        let divider3 = divider()
        card.addSubview(divider3)
        let commentsRow87 = actionRow(icon: "text.bubble", title: "评论",
                                      color: .white, action: #selector(commentsTapped87))
        card.addSubview(commentsRow87)
        let infoRow87 = actionRow(icon: "info.circle", title: "歌曲资料",
                                  color: .white, action: #selector(infoTapped87))
        card.addSubview(infoRow87)
        let statsRow87 = actionRow(icon: "chart.bar", title: "听歌统计",
                                   color: .white, action: #selector(statsTapped87))
        card.addSubview(statsRow87)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
            editButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            editButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            editButton.widthAnchor.constraint(equalToConstant: 48),
            editButton.heightAnchor.constraint(equalToConstant: 36),

            card.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: sleepHeaderRow.bottomAnchor, constant: 10),

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
            saveRow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            saveRow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            saveRow.topAnchor.constraint(equalTo: clearRow.bottomAnchor),
            saveRow.heightAnchor.constraint(equalToConstant: 42),

            // (87) 功能三件行（卡底由此收口）。
            divider3.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            divider3.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            divider3.topAnchor.constraint(equalTo: saveRow.bottomAnchor, constant: 4),
            divider3.heightAnchor.constraint(equalToConstant: 0.5),
            commentsRow87.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            commentsRow87.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            commentsRow87.topAnchor.constraint(equalTo: divider3.bottomAnchor, constant: 4),
            commentsRow87.heightAnchor.constraint(equalToConstant: 42),
            infoRow87.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            infoRow87.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            infoRow87.topAnchor.constraint(equalTo: commentsRow87.bottomAnchor),
            infoRow87.heightAnchor.constraint(equalToConstant: 42),
            statsRow87.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            statsRow87.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            statsRow87.topAnchor.constraint(equalTo: infoRow87.bottomAnchor),
            statsRow87.heightAnchor.constraint(equalToConstant: 42),
            statsRow87.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
        ])

        // (87) 编辑（多选）入口退役：队列改封面网格后批
        // 量多选无落点，移除/移到末尾/下一首由网格长按菜
        // 单承接（报告注明取舍）；钮对象保留、恒隐藏。
        editButton.isHidden = true

        // (87) 队列封面网格（点格切歌、金环＋律动、长按
        // 菜单、拖拽排序）。
        let gridLayout87 = UICollectionViewFlowLayout()
        gridLayout87.scrollDirection = .vertical
        gridLayout87.minimumInteritemSpacing = 10
        gridLayout87.minimumLineSpacing = 12
        grid87 = UICollectionView(frame: .zero, collectionViewLayout: gridLayout87)
        grid87.backgroundColor = .clear
        grid87.showsVerticalScrollIndicator = false
        grid87.dataSource = self
        grid87.delegate = self
        grid87.dragDelegate = self
        grid87.dropDelegate = self
        grid87.dragInteractionEnabled = true
        grid87.register(CoverGridCell87.self, forCellWithReuseIdentifier: "qgrid87")
        grid87.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid87)
        let gridLongPress87 = UILongPressGestureRecognizer(
            target: self, action: #selector(gridLongPressed87(_:)))
        grid87.addGestureRecognizer(gridLongPress87)

        // 歌单表（(87) 起只承本机歌单 section；队列文字
        // 行退役——QueueTrackCell 类保留但不再注册使用）。
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 60
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(QueuePlaylistCell.self,
                           forCellReuseIdentifier: QueuePlaylistCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableHeight87 = tableView.heightAnchor.constraint(equalToConstant: 0)

        emptyLabel.text = "队列是空的"
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            grid87.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            grid87.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            grid87.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 10),
            grid87.bottomAnchor.constraint(equalTo: tableView.topAnchor, constant: -6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableHeight87!,
            emptyLabel.centerXAnchor.constraint(equalTo: grid87.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: grid87.centerYAnchor),
        ])

        // 批量操作条（3.7 (50)）：编辑态浮显于底部；非编辑态隐藏。
        batchBar.isHidden = true
        batchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(batchBar)
        batchCountLabel.font = .systemFont(ofSize: 13.5)
        batchCountLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        batchCountLabel.translatesAutoresizingMaskIntoConstraints = false
        batchBar.contentView.addSubview(batchCountLabel)
        batchRemoveButton.setTitle("移除所选", for: .normal)
        batchRemoveButton.titleLabel?.font = .systemFont(ofSize: 14.5, weight: .medium)
        batchRemoveButton.setTitleColor(
            UIColor(red: 1, green: 0.42, blue: 0.42, alpha: 1), for: .normal)
        batchRemoveButton.translatesAutoresizingMaskIntoConstraints = false
        batchRemoveButton.addTarget(self, action: #selector(batchRemoveTapped),
                                    for: .touchUpInside)
        batchBar.contentView.addSubview(batchRemoveButton)
        batchMoveEndButton.setTitle("移到末尾", for: .normal)
        batchMoveEndButton.titleLabel?.font = .systemFont(ofSize: 14.5, weight: .medium)
        batchMoveEndButton.setTitleColor(.white, for: .normal)
        batchMoveEndButton.translatesAutoresizingMaskIntoConstraints = false
        batchMoveEndButton.addTarget(self, action: #selector(batchMoveEndTapped),
                                     for: .touchUpInside)
        batchBar.contentView.addSubview(batchMoveEndButton)
        NSLayoutConstraint.activate([
            batchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            batchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            batchBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            batchBar.heightAnchor.constraint(equalToConstant: 78),
            batchCountLabel.leadingAnchor.constraint(
                equalTo: batchBar.contentView.leadingAnchor, constant: 20),
            batchCountLabel.topAnchor.constraint(
                equalTo: batchBar.contentView.topAnchor, constant: 14),
            batchMoveEndButton.trailingAnchor.constraint(
                equalTo: batchBar.contentView.trailingAnchor, constant: -20),
            batchMoveEndButton.centerYAnchor.constraint(
                equalTo: batchCountLabel.centerYAnchor),
            batchRemoveButton.trailingAnchor.constraint(
                equalTo: batchMoveEndButton.leadingAnchor, constant: -22),
            batchRemoveButton.centerYAnchor.constraint(
                equalTo: batchCountLabel.centerYAnchor),
        ])
        updateBatchBar()
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
                if queue.isEmpty, self.isEditing {
                    self.setEditing(false, animated: false)
                }
                // (87) 队列回刷改走封面网格。
                if !self.dragInFlight { self.grid87?.reloadData() }
            }
            .store(in: &cancellables)
        LocalPlaylistStore.shared.$playlists
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playlists in
                guard let self else { return }
                self.localPlaylists = playlists
                if !self.dragInFlight { self.tableView.reloadData() }
                // (87) 歌单表高随条数收口（0 时网格吃满）。
                self.tableHeight87?.constant = playlists.isEmpty
                    ? 0 : min(CGFloat(playlists.count) * 60 + 38, 200)
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
        refreshSleepHeaderRow()
    }

    /// 头部睡眠状态行回显（3.7 (55) 工作流 D）：有定时显剩余＋
    /// 取消钮，无定时显入口文案、藏取消钮。经 refreshSleepUI 调用
    /// （变更通知＋面板在场 1 秒倒计时同路），无需另建计时器。
    private func refreshSleepHeaderRow() {
        let timer = SleepTimerController.shared
        if let remaining = timer.remainingSeconds, timer.isActive {
            let total = Int(remaining.rounded())
            sleepHeaderLabel.text = String(
                format: "睡眠定时 · 剩 %d:%02d 后暂停", total / 60, total % 60)
            sleepHeaderCancelButton.isHidden = false
        } else {
            sleepHeaderLabel.text = "睡眠定时"
            sleepHeaderCancelButton.isHidden = true
        }
    }

    /// 头部行点按（无定时=入口、有定时=改档）：弹既有预设档菜单
    /// （SleepTimerController.presets 全集，当前档打勾），与管理
    /// 卡定时档同一设置源。
    @objc private func sleepHeaderRowTapped() {
        let alert = UIAlertController(
            title: "睡眠定时", message: nil, preferredStyle: .actionSheet)
        let active = SleepTimerController.shared.activePresetMinutes
        for minutes in SleepTimerController.presets {
            let isCurrent = SleepTimerController.shared.isActive
                ? (active == minutes && minutes > 0) : minutes == 0
            let title = (minutes == 0 ? "关" : "\(minutes) 分钟后暂停")
                + (isCurrent ? " ✓" : "")
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                SleepTimerController.shared.set(minutes: minutes)
                Breadcrumbs.log("queue.panel.sleepHeader set minutes=\(minutes)")
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sleepHeaderRow
            popover.sourceRect = sleepHeaderRow.bounds
        }
        Breadcrumbs.log("queue.panel.sleepHeader menu")
        present(alert, animated: true)
    }

    @objc private func sleepHeaderCancelTapped() {
        SleepTimerController.shared.cancel()
        Breadcrumbs.log("queue.panel.sleepHeader cancel")
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

    // MARK: - 多选与本机歌单（3.7 (50)）

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
        // 编辑态关长按拖拽：与多选手势同占 tableView，不关互抢。
        tableView.dragInteractionEnabled = !editing
        batchBar.isHidden = !editing
        tableView.contentInset.bottom = editing ? 84 : 0
        editButton.setTitle(editing ? "完成" : "编辑", for: .normal)
        updateBatchBar()
    }

    @objc private func editTapped() {
        guard !tracks.isEmpty else { return }
        setEditing(!isEditing, animated: true)
    }

    /// 当前多选集合（只认队列 section 的行号）。
    private func selectedQueueIndices() -> IndexSet {
        var set = IndexSet()
        for path in tableView.indexPathsForSelectedRows ?? []
        where path.section == 1 {
            set.insert(path.row)
        }
        return set
    }

    private func updateBatchBar() {
        let count = selectedQueueIndices().count
        batchCountLabel.text = "已选 \(count) 首"
        let enabled = count > 0
        batchRemoveButton.alpha = enabled ? 1 : 0.35
        batchMoveEndButton.alpha = enabled ? 1 : 0.35
        batchRemoveButton.isEnabled = enabled
        batchMoveEndButton.isEnabled = enabled
    }

    @objc private func batchRemoveTapped() {
        let indices = selectedQueueIndices()
        guard !indices.isEmpty else { return }
        setEditing(false, animated: true)
        queueManager.removeFromQueue(atIndices: indices)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func batchMoveEndTapped() {
        let indices = selectedQueueIndices()
        guard !indices.isEmpty else { return }
        setEditing(false, animated: true)
        queueManager.moveToEnd(atIndices: indices)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func savePlaylistTapped() {
        guard !tracks.isEmpty else { return }
        let alert = UIAlertController(
            title: "保存为歌单",
            message: "把当前队列的 \(tracks.count) 首歌存为本机歌单，之后可在本面板整队载入。",
            preferredStyle: .alert)
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        alert.addTextField { field in
            field.placeholder = "歌单名称"
            field.text = "我的队列 · \(formatter.string(from: Date()))"
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) {
            [weak self, weak alert] _ in
            guard let self,
                  let name = alert?.textFields?.first?.text else { return }
            if LocalPlaylistStore.shared.saveQueue(
                named: name, tracks: self.tracks) != nil {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Breadcrumbs.log("queue.panel.savePlaylist n=\(self.tracks.count)")
            }
        })
        present(alert, animated: true)
    }

    /// 歌单行点按：整队载入 / 追加 / 删除。
    private func presentPlaylistActions(at row: Int) {
        guard localPlaylists.indices.contains(row) else { return }
        let playlist = localPlaylists[row]
        let sheet = UIAlertController(
            title: playlist.name,
            message: "\(playlist.tracks.count) 首 · 存于本机",
            preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "整队载入并播放", style: .default) {
            [weak self] _ in
            self?.queueManager.setQueue(playlist.tracks, startingAt: 0,
                                        source: "local-playlist")
            self?.dismiss(animated: true)
        })
        sheet.addAction(UIAlertAction(title: "追加到队列末尾", style: .default) {
            [weak self] _ in
            self?.queueManager.appendToQueue(playlist.tracks)
        })
        sheet.addAction(UIAlertAction(title: "删除歌单", style: .destructive) {
            _ in
            LocalPlaylistStore.shared.delete(id: playlist.id)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }
}

// MARK: - 队列表

extension QueuePanelViewController: UITableViewDataSource, UITableViewDelegate {

    // (87) 表格只剩本机歌单一段（队列已迁封面网格）。
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        localPlaylists.count
    }

    func tableView(_ tableView: UITableView,
                   titleForHeaderInSection section: Int) -> String? {
        localPlaylists.isEmpty ? nil : "我的歌单"
    }

    func tableView(_ tableView: UITableView,
                   willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.contentView.backgroundColor = .clear
        header.textLabel?.textColor = UIColor.white.withAlphaComponent(0.55)
        header.textLabel?.font = .systemFont(ofSize: 13, weight: .medium)
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: QueuePlaylistCell.reuseId,
            for: indexPath) as! QueuePlaylistCell
        cell.configure(playlist: localPlaylists[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presentPlaylistActions(at: indexPath.row)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing { updateBatchBar() }
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        // (87) 表格只剩歌单：仅删除歌单（队列行操作已迁
        // 网格长按菜单）。
        let playlist = localPlaylists[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") {
            _, _, done in
            LocalPlaylistStore.shared.delete(id: playlist.id)
            done(true)
        }
        delete.image = UIImage(systemName: "trash")
        let config = UISwipeActionsConfiguration(actions: [delete])
        config.performsFirstActionWithFullSwipe = false
        return config
    }
}

// MARK: - 拖拽排序

extension QueuePanelViewController: UITableViewDragDelegate, UITableViewDropDelegate {

    func tableView(_ tableView: UITableView,
                   itemsForBeginning session: UIDragSession,
                   at indexPath: IndexPath) -> [UIDragItem] {
        // 拖拽排序只对队列 section 开放（歌单 section 不可拖）。
        guard indexPath.section == 1 else { return [] }
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
              let destinationPath = coordinator.destinationIndexPath,
              destinationPath.section == 1 else { return }
        queueManager.moveQueueItem(from: source, to: destinationPath.row)
    }
}

// MARK: - (87) 队列封面网格

extension QueuePanelViewController: UICollectionViewDataSource,
                                    UICollectionViewDelegateFlowLayout,
                                    UICollectionViewDragDelegate,
                                    UICollectionViewDropDelegate {

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        tracks.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "qgrid87", for: indexPath) as! CoverGridCell87
        cell.configure(track: tracks[indexPath.item],
                       index: indexPath.item,
                       isCurrent: indexPath.item == currentIndex,
                       isPlaying: PlaybackEngine.shared.isPlaying)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item != currentIndex else { return }
        Breadcrumbs.log("queue87 grid play idx=\(indexPath.item)")
        queueManager.playAtIndex(indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        let columns: CGFloat = width > 500 ? 6 : 4
        let side = floor((width - (columns - 1) * 10) / columns)
        return CGSize(width: side, height: side + 30)
    }

    // 拖拽排序（与旧表格同源 moveQueueItem）。
    func collectionView(_ collectionView: UICollectionView,
                        itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = indexPath.item
        return [item]
    }

    func collectionView(_ collectionView: UICollectionView,
                        dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?)
        -> UICollectionViewDropProposal {
        UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView,
                        performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let item = coordinator.items.first,
              let source = item.dragItem.localObject as? Int,
              let destination = coordinator.destinationIndexPath else { return }
        dragInFlight = true
        queueManager.moveQueueItem(from: source, to: destination.item)
        dragInFlight = false
        grid87?.reloadData()
        Breadcrumbs.log("queue87 grid move \(source)->\(destination.item)")
    }

    /// 长按封面：动作菜单承接旧行操作（下一首/移到末
    /// 尾/移除——批量多选的单曲等价物）。
    @objc func gridLongPressed87(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let point = recognizer.location(in: grid87)
        guard let indexPath = grid87.indexPathForItem(at: point),
              tracks.indices.contains(indexPath.item) else { return }
        let row = indexPath.item
        let track = tracks[row]
        let sheet = UIAlertController(title: track.title, message: track.artist,
                                      preferredStyle: .actionSheet)
        if row != currentIndex {
            sheet.addAction(UIAlertAction(title: "播放", style: .default) {
                [weak self] _ in self?.queueManager.playAtIndex(row)
            })
            if row != currentIndex + 1 {
                sheet.addAction(UIAlertAction(title: "下一首播放", style: .default) {
                    [weak self] _ in self?.queueManager.moveToNext(at: row)
                })
            }
            sheet.addAction(UIAlertAction(title: "移到末尾", style: .default) {
                [weak self] _ in self?.queueManager.moveToEnd(at: row)
            })
        }
        sheet.addAction(UIAlertAction(title: "从队列移除", style: .destructive) {
            [weak self] _ in self?.queueManager.removeFromQueue(at: row)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController,
           let cell = grid87.cellForItem(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Breadcrumbs.log("queue87 grid menu idx=\(row)")
        present(sheet, animated: true)
    }
}

// MARK: - (87) 功能三件入口

extension QueuePanelViewController {

    /// 三件的对象：正在播放的曲（无则队列当前曲）。
    private func currentTrack87() -> FoliaTrack? {
        if let playing = PlaybackEngine.shared.currentTrack { return playing }
        return tracks.indices.contains(currentIndex) ? tracks[currentIndex] : nil
    }

    @objc func commentsTapped87() {
        guard let track = currentTrack87() else {
            NativePlaybackFailureToast.show(message: "暂无正在播放的歌曲")
            return
        }
        Breadcrumbs.log("queue87 open=cmt")
        CommentsPanel87ViewController.present(from: self, track: track)
    }

    @objc func infoTapped87() {
        guard let track = currentTrack87() else {
            NativePlaybackFailureToast.show(message: "暂无正在播放的歌曲")
            return
        }
        Breadcrumbs.log("queue87 open=info")
        SongInfoPanel87ViewController.present(from: self, track: track)
    }

    @objc func statsTapped87() {
        Breadcrumbs.log("queue87 open=stats")
        ListenStats87ViewController.present(from: self)
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

// MARK: - 本机歌单行（3.7 (50)）

final class QueuePlaylistCell: UITableViewCell {

    static let reuseId = "QueuePlaylistCell"

    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        iconView.image = UIImage(systemName: "music.note.list")
        iconView.tintColor = UIColor.white.withAlphaComponent(0.75)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)
        nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
        nameLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)
        metaLabel.font = .systemFont(ofSize: 12.5)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(metaLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            metaLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func configure(playlist: LocalPlaylistStore.LocalPlaylist) {
        nameLabel.text = playlist.name
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        metaLabel.text = "\(playlist.tracks.count) 首 · "
            + formatter.string(from: Date(timeIntervalSince1970: playlist.createdAt))
    }
}
