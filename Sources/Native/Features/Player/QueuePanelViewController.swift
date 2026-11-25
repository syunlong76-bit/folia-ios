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
///
/// (89)B b-queue-form（Miller 工坊裁决按网页形态）：呈出由
/// .pageSheet 改浮动面板——.overFullScreen＋根 view 压暗层
/// （点卡外关闭）、全部内容收进 card89 毛玻璃卡（与
/// ConsolePanel82 同语言）；队列主体由封面网格改回网页
/// QueueTab 文字行（行高 48、无封面、当前行左侧 3pt 强调
/// 条、右侧时长），grid87 封面网格自本页撤除（CoverModule87
/// 在控制台的条带/网格装配不受影响）；行尾动作由长按菜单
/// （UIContextMenu）承接、拖拽排序与编辑多选（批量条）随
/// 文字行一并恢复（(87) 退役的两件就此回归）；本机歌单表
/// 保留为第二段；管理卡功能全保留、只压缩间距。
final class QueuePanelViewController: UIViewController {

    /// 面板关闭回调（两台用它重置无操作计时）。
    var onDismiss: (() -> Void)?

    static func present(from presenter: UIViewController,
                        onDismiss: (() -> Void)? = nil) {
        let panel = QueuePanelViewController()
        panel.onDismiss = onDismiss
        // (89)B ①：浮动面板呈出（.pageSheet 退役）。
        panel.modalPresentationStyle = .overFullScreen
        panel.modalTransitionStyle = .crossDissolve
        Breadcrumbs.log("queue.panel.open")
        Breadcrumbs.log("port89 queueform=panel/rows48")
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
    /// (89)B 浮动卡容器：全部内容收进本卡（毛玻璃＋黑 tint＋
    /// 描边、圆角 20），宽/高约束在布局时按屏收口（viewDid-
    /// LayoutSubviews：宽 min(360, 屏宽−32)、高 = 顶线
    /// （安全区顶＋56）到卡底（安全区底−16）的可用高）。
    private let card89 = UIView()
    private var cardWidth89: NSLayoutConstraint?
    private var cardHeight89: NSLayoutConstraint?

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
        // (89)B 入场：卡弹簧缩放 0.96→1＋淡入（ConsolePanel82
        // 同语言：0.5s、damping 0.82、velocity 0.4）。
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.82,
                       initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction]) {
            self.card89.alpha = 1
            self.card89.transform = .identity
        }
        if !didScrollToCurrent, !tracks.isEmpty {
            didScrollToCurrent = true
            let row = min(max(currentIndex, 0), tracks.count - 1)
            // (89)B 定位当前曲改走文字行表（section 0）。
            tableView.scrollToRow(at: IndexPath(row: row, section: 0),
                                  at: .middle, animated: false)
        }
        startCountdown()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // (89)B 卡宽/高收口：宽 min(360, 屏宽−32)；高 = 顶线
        //（安全区顶＋56）至卡底（安全区底−16）的可用高。
        cardWidth89?.constant = min(360, max(0, view.bounds.width - 32))
        let available = view.bounds.height - view.safeAreaInsets.top - 56
            - view.safeAreaInsets.bottom - 16
        cardHeight89?.constant = max(200, available)
    }

    /// (89)B 点卡外（压暗层）关闭：复用既有 closeTapped。
    @objc private func dimTapped89(_ recognizer: UITapGestureRecognizer) {
        guard !card89.frame.contains(recognizer.location(in: view)) else { return }
        Breadcrumbs.log("port89 queueform dimtap")
        closeTapped()
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
        // (89)B ① 根 view = 压暗层（点卡外关闭，dimTapped89
        // 复用 closeTapped）；全部内容收进 card89 浮动卡
        //（.systemUltraThinMaterialDark 毛玻璃＋黑 0.25 tint
        // ＋白 0.16 描边、圆角 20，与 ConsolePanel82 同语言；
        // 右对齐 trailing −16、底 = 安全区底 −16、顶 ≥ 安全
        // 区顶＋56，宽/高约束在 viewDidLayoutSubviews 收口）。
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        let dimTap89 = UITapGestureRecognizer(
            target: self, action: #selector(dimTapped89(_:)))
        view.addGestureRecognizer(dimTap89)
        card89.layer.cornerRadius = 20
        card89.layer.borderWidth = 1
        card89.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        card89.clipsToBounds = true
        card89.alpha = 0
        card89.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        card89.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card89)
        let cardBlur89 = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        cardBlur89.translatesAutoresizingMaskIntoConstraints = false
        card89.addSubview(cardBlur89)
        let cardTint89 = UIView()
        cardTint89.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        cardTint89.translatesAutoresizingMaskIntoConstraints = false
        card89.addSubview(cardTint89)
        cardWidth89 = card89.widthAnchor.constraint(equalToConstant: 360)
        cardHeight89 = card89.heightAnchor.constraint(equalToConstant: 480)
        NSLayoutConstraint.activate([
            card89.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            card89.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            card89.topAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            card89.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cardWidth89!,
            cardHeight89!,
            cardBlur89.leadingAnchor.constraint(equalTo: card89.leadingAnchor),
            cardBlur89.trailingAnchor.constraint(equalTo: card89.trailingAnchor),
            cardBlur89.topAnchor.constraint(equalTo: card89.topAnchor),
            cardBlur89.bottomAnchor.constraint(equalTo: card89.bottomAnchor),
            cardTint89.leadingAnchor.constraint(equalTo: card89.leadingAnchor),
            cardTint89.trailingAnchor.constraint(equalTo: card89.trailingAnchor),
            cardTint89.topAnchor.constraint(equalTo: card89.topAnchor),
            cardTint89.bottomAnchor.constraint(equalTo: card89.bottomAnchor),
        ])

        // 标题行
        titleLabel.text = "播放列表"
        // (89) §7-4：头行标题对齐网页 QueueTab 头行 13 semibold
        //（头行总高由关闭钮 36 决定、与网页 HEAD_PX 36 同值）。
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card89.addSubview(titleLabel)
        countLabel.font = .systemFont(ofSize: 13)
        countLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        card89.addSubview(countLabel)
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.8)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        card89.addSubview(closeButton)
        // 编辑（多选）入口（3.7 (50)）：标题行、关闭键左侧。
        editButton.setTitle("编辑", for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 15)
        editButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        card89.addSubview(editButton)

        // 头部睡眠定时状态行（3.7 (55) 工作流 D/DS 修正3）
        sleepHeaderRow.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        sleepHeaderRow.layer.cornerRadius = 10
        sleepHeaderRow.translatesAutoresizingMaskIntoConstraints = false
        card89.addSubview(sleepHeaderRow)
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
            sleepHeaderRow.leadingAnchor.constraint(equalTo: card89.leadingAnchor, constant: 16),
            sleepHeaderRow.trailingAnchor.constraint(equalTo: card89.trailingAnchor, constant: -16),
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

        // 管理卡（(89)B ③：功能全保留，只压缩为头区下的紧凑
        // 行组——间距收紧、行高 42→38、圆角与 card89 同语言）
        let card = UIView()
        card.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        card.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        card89.addSubview(card)

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

        // (89)B：锚点自 view.safeAreaLayoutGuide 改挂 card89；
        // 管理卡内部间距按紧凑行组收紧（段距 12→8、chips
        // 30→28、动作/功能行 42→38）。
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: card89.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: card89.topAnchor, constant: 18),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: card89.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
            editButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            editButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            editButton.widthAnchor.constraint(equalToConstant: 48),
            editButton.heightAnchor.constraint(equalToConstant: 36),

            card.leadingAnchor.constraint(equalTo: card89.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: card89.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: sleepHeaderRow.bottomAnchor, constant: 10),

            modeTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            modeTitle.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            modeChipsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            modeChipsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            modeChipsStack.topAnchor.constraint(equalTo: modeTitle.bottomAnchor, constant: 6),
            modeChipsStack.heightAnchor.constraint(equalToConstant: 28),

            divider1.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            divider1.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            divider1.topAnchor.constraint(equalTo: modeChipsStack.bottomAnchor, constant: 8),
            divider1.heightAnchor.constraint(equalToConstant: 0.5),

            sleepTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            sleepTitle.topAnchor.constraint(equalTo: divider1.bottomAnchor, constant: 8),
            sleepStateLabel.leadingAnchor.constraint(equalTo: sleepTitle.trailingAnchor, constant: 8),
            sleepStateLabel.centerYAnchor.constraint(equalTo: sleepTitle.centerYAnchor),
            sleepChipsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            sleepChipsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            sleepChipsStack.topAnchor.constraint(equalTo: sleepTitle.bottomAnchor, constant: 6),
            sleepChipsStack.heightAnchor.constraint(equalToConstant: 28),

            divider2.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            divider2.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            divider2.topAnchor.constraint(equalTo: sleepChipsStack.bottomAnchor, constant: 8),
            divider2.heightAnchor.constraint(equalToConstant: 0.5),

            shuffleRow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            shuffleRow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            shuffleRow.topAnchor.constraint(equalTo: divider2.bottomAnchor, constant: 2),
            shuffleRow.heightAnchor.constraint(equalToConstant: 38),
            clearRow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            clearRow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            clearRow.topAnchor.constraint(equalTo: shuffleRow.bottomAnchor),
            clearRow.heightAnchor.constraint(equalToConstant: 38),
            saveRow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            saveRow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            saveRow.topAnchor.constraint(equalTo: clearRow.bottomAnchor),
            saveRow.heightAnchor.constraint(equalToConstant: 38),

            // (87) 功能三件行（卡底由此收口）。
            divider3.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            divider3.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            divider3.topAnchor.constraint(equalTo: saveRow.bottomAnchor, constant: 2),
            divider3.heightAnchor.constraint(equalToConstant: 0.5),
            commentsRow87.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            commentsRow87.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            commentsRow87.topAnchor.constraint(equalTo: divider3.bottomAnchor, constant: 2),
            commentsRow87.heightAnchor.constraint(equalToConstant: 38),
            infoRow87.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            infoRow87.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            infoRow87.topAnchor.constraint(equalTo: commentsRow87.bottomAnchor),
            infoRow87.heightAnchor.constraint(equalToConstant: 38),
            statsRow87.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            statsRow87.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            statsRow87.topAnchor.constraint(equalTo: infoRow87.bottomAnchor),
            statsRow87.heightAnchor.constraint(equalToConstant: 38),
            statsRow87.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -2),
        ])

        // (89)B ② 编辑（多选）入口随文字行恢复：(87) 退役的
        // 批量多选重新落回队列行（section 0）＋底部批量条，
        // editButton 不再恒隐藏（显隐/文案由 setEditing 管）。

        // (89)B ② 队列表改两段文字行：section 0 = 队列曲目
        //（QueueTrackCell 网页 QueueTab 行规格：行高 48、无
        // 封面、左 3pt 强调条、右侧时长；点行切歌、长按菜单
        // 承接单曲动作、拖拽排序走 moveQueueItem、编辑多选
        // 走批量条）；section 1 = 本机歌单（QueuePlaylistCell
        // 行高 60、既有整队载入/追加/删除不变）。(87) 的
        // grid87 封面网格自本页撤除——CoverModule87 本体不
        // 动，控制台条带/网格的装配在 ConsolePanel82 侧。
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 48
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        tableView.register(QueueTrackCell.self,
                           forCellReuseIdentifier: QueueTrackCell.reuseId)
        tableView.register(QueuePlaylistCell.self,
                           forCellReuseIdentifier: QueuePlaylistCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        card89.addSubview(tableView)

        emptyLabel.text = "队列是空的"
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        card89.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: card89.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: card89.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 10),
            tableView.bottomAnchor.constraint(equalTo: card89.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])

        // 批量操作条（3.7 (50)）：编辑态浮显于底部；非编辑态隐藏。
        // (89)B：批量条改锚 card89 底（原锚根 view 底）。
        batchBar.isHidden = true
        batchBar.translatesAutoresizingMaskIntoConstraints = false
        card89.addSubview(batchBar)
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
            batchBar.leadingAnchor.constraint(equalTo: card89.leadingAnchor),
            batchBar.trailingAnchor.constraint(equalTo: card89.trailingAnchor),
            batchBar.bottomAnchor.constraint(equalTo: card89.bottomAnchor),
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
        // (89)B：chips 高 28 后圆角 14 成全胶囊（原 15/高 30）。
        chip.layer.cornerRadius = 14
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
                // (89)B 队列回刷走文字行表（section 0）。
                if !self.dragInFlight { self.tableView.reloadData() }
            }
            .store(in: &cancellables)
        LocalPlaylistStore.shared.$playlists
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playlists in
                guard let self else { return }
                self.localPlaylists = playlists
                // (89)B 歌单段与队列段同表（section 1），整表
                // 回刷即可；(87) 的歌单表高度收口随网格撤除作废
                //（表高由 card89 内顶/底锚决定）。
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

    /// 当前多选集合（只认队列 section 的行号；(89)B 队列段
    /// 回到 section 0——(87) 网格期此判据指向歌单段的旧值作废）。
    private func selectedQueueIndices() -> IndexSet {
        var set = IndexSet()
        for path in tableView.indexPathsForSelectedRows ?? []
        where path.section == 0 {
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

    // (89)B 两段：section 0 = 队列文字行（tracks），
    // section 1 = 本机歌单（localPlaylists）——数据源以
    // section 区分，两段各自的行高/点按/侧滑互不串。
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? tracks.count : localPlaylists.count
    }

    func tableView(_ tableView: UITableView,
                   titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return tracks.isEmpty ? nil : "播放队列" }
        return localPlaylists.isEmpty ? nil : "我的歌单"
    }

    func tableView(_ tableView: UITableView,
                   willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.contentView.backgroundColor = .clear
        header.textLabel?.textColor = UIColor.white.withAlphaComponent(0.55)
        header.textLabel?.font = .systemFont(ofSize: 13, weight: .medium)
    }

    func tableView(_ tableView: UITableView,
                   heightForRowAt indexPath: IndexPath) -> CGFloat {
        // (89)B：队列行 48（网页 QueueTab ROW_PX）；歌单行沿用 60。
        indexPath.section == 0 ? 48 : 60
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: QueueTrackCell.reuseId,
                for: indexPath) as! QueueTrackCell
            cell.configure(track: tracks[indexPath.row],
                           index: indexPath.row,
                           isCurrent: indexPath.row == currentIndex)
            return cell
        }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: QueuePlaylistCell.reuseId,
            for: indexPath) as! QueuePlaylistCell
        cell.configure(playlist: localPlaylists[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            // 编辑多选态：点按只改选中集、批量条计数跟随。
            if indexPath.section == 0 { updateBatchBar() }
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            // 点行切歌（当前行不重复触发，与旧网格口径同）。
            guard indexPath.row != currentIndex else { return }
            Breadcrumbs.log("port89 queue row play idx=\(indexPath.row)")
            queueManager.playAtIndex(indexPath.row)
        } else {
            presentPlaylistActions(at: indexPath.row)
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing { updateBatchBar() }
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        // 侧滑只对歌单段：删除歌单。队列行动作走长按菜单/
        // 编辑多选，不在此重复。
        guard indexPath.section == 1 else { return nil }
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

    /// (89)B 队列行长按菜单：承接 (87) 网格长按菜单的单曲
    /// 动作全集（播放/下一首播放/移到末尾/从队列移除），
    /// 系统 UIContextMenu 呈出；歌单段不挂（其动作在点按
    /// 的 actionSheet 里）。编辑多选态不挂菜单（点按即多选）。
    func tableView(_ tableView: UITableView,
                   contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.section == 0, !tableView.isEditing,
              tracks.indices.contains(indexPath.row) else { return nil }
        let row = indexPath.row
        let track = tracks[row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
            [weak self] _ in
            guard let self else { return nil }
            var actions: [UIAction] = []
            if row != self.currentIndex {
                actions.append(UIAction(title: "播放",
                                        image: UIImage(systemName: "play.fill")) { _ in
                    self.queueManager.playAtIndex(row)
                })
                if row != self.currentIndex + 1 {
                    actions.append(UIAction(
                        title: "下一首播放",
                        image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward")) { _ in
                        self.queueManager.moveToNext(at: row)
                    })
                }
                actions.append(UIAction(title: "移到末尾",
                                        image: UIImage(systemName: "arrow.down.to.line")) { _ in
                    self.queueManager.moveToEnd(at: row)
                })
            }
            actions.append(UIAction(title: "从队列移除",
                                    image: UIImage(systemName: "trash"),
                                    attributes: .destructive) { _ in
                self.queueManager.removeFromQueue(at: row)
            })
            Breadcrumbs.log("port89 queue menu idx=\(row)")
            return UIMenu(title: track.title, children: actions)
        }
    }
}

// MARK: - 拖拽排序

extension QueuePanelViewController: UITableViewDragDelegate, UITableViewDropDelegate {

    func tableView(_ tableView: UITableView,
                   itemsForBeginning session: UIDragSession,
                   at indexPath: IndexPath) -> [UIDragItem] {
        // 拖拽排序只对队列 section 开放（歌单 section 不可拖）。
        // (89)B：队列段为 section 0（(87) 网格期的旧段位作废）。
        guard indexPath.section == 0 else { return [] }
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
              destinationPath.section == 0 else { return }
        queueManager.moveQueueItem(from: source, to: destinationPath.row)
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

/// (89)B 队列文字行（网页 QueueTab 行规格）：行高 48（由
/// VC heightForRowAt 给）、无封面；歌名 13pt（当前行
/// semibold）、歌手 12pt、当前行左侧 3pt 强调竖条（上下
/// 各缩 12）、右侧时长（12pt 等宽数字）。(87) 前的封面/
/// 序号/声浪图标三件就此退役——当前行只靠竖条＋字重区分。
final class QueueTrackCell: UITableViewCell {

    static let reuseId = "QueueTrackCell"

    /// 当前行左侧 3pt 强调竖条（网页 QueueTab 同款）。
    private let accentBar89 = UIView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let durationLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        accentBar89.backgroundColor = ThemeSystem62.currentAccent
        accentBar89.isHidden = true
        accentBar89.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(accentBar89)

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        artistLabel.font = .systemFont(ofSize: 12)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artistLabel)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        durationLabel.textAlignment = .right
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(durationLabel)

        NSLayoutConstraint.activate([
            accentBar89.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            accentBar89.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            accentBar89.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            accentBar89.widthAnchor.constraint(equalToConstant: 3),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            durationLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 46),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        artistLabel.text = nil
        durationLabel.text = nil
        accentBar89.isHidden = true
    }

    func configure(track: FoliaTrack, index: Int, isCurrent: Bool) {
        titleLabel.text = track.title
        artistLabel.text = track.artist
        // 网页当前行歌名加粗；其余行常规字重。
        titleLabel.font = .systemFont(ofSize: 13, weight: isCurrent ? .semibold : .regular)
        accentBar89.isHidden = !isCurrent
        if isCurrent {
            accentBar89.backgroundColor = ThemeSystem62.currentAccent
        }
        durationLabel.text = Self.durationText89(track.duration)
    }

    /// 时长 m:ss（无有效时长留空，不造数）。
    private static func durationText89(_ seconds: TimeInterval) -> String {
        guard seconds > 0, seconds.isFinite else { return "" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
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
