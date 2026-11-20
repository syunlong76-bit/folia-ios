import UIKit

// 命令面板（3.7 (55) 工作流 D）：网页版 command-palette 的原生承接。
// 入口 = 舞台点播台「命令」钮发出的 Notification.Name("FoliaMiniBarCommand")
// （工作流 C 定名），StageViewController 订阅后 present 本面板。
//
// 形态（DS 对账修正）：pageSheet 大 detent 呈现（不做固定 2/3 高），
// 搜索框置顶吸顶（头部固定、只有列表滚动），命令按分组分节呈现。
// 数据形态按可扩展到网页全集设计：命令是注册表数据（sections →
// commands），渲染与搜索过滤都由注册表生成——将来补命令只往注册
// 表加行，不改渲染代码；不许把三百条平铺写死。
//
// 今晚只上「有真后端」的命令（逐条执行落点见各命令 action 注释）；
// 点按 = 真执行 → 面板关闭 → 必要时窗口 toast 反馈。网页命令全集里
// 没后端的类别（场景/Navidrome/歌词导出/桌面专属/HiFi/FM 模式等）
// 不放假命令，逐类列在报告。
// 睡眠定时入口按 (55) 定案由本面板承接（顶排已无睡眠钮）：本面板
// 的睡眠命令点开预设菜单（关/10/20/30/45/60，SleepTimerController
// 真设置），与 PlaybackPanel 控制页签双落点。
final class CommandPaletteViewController: UIViewController {

    /// 跨面板跳转注入（StageViewController 呈现时接线）：命令面板
    /// 自身关掉后由宿主在舞台上呈现目标面（样式选择需舞台的选样式
    /// 通路、队列需 PlaybackPanel 队列页签），不经面板叠面板。
    var onOpenSubtitleSettings: (() -> Void)?
    var onOpenStylePicker: (() -> Void)?
    var onOpenQueuePanel: (() -> Void)?

    static func present(from presenter: UIViewController,
                        configure: ((CommandPaletteViewController) -> Void)? = nil) {
        let palette = CommandPaletteViewController()
        configure?(palette)
        palette.modalPresentationStyle = .pageSheet
        if let sheet = palette.sheetPresentationController {
            // 大高度呈现（DS 对账）：只给 large detent，搜索吸顶、
            // 列表滚动；不用固定分数高。
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        Breadcrumbs.log("stage.palette.open")
        presenter.present(palette, animated: true)
    }

    // MARK: - 命令注册表（数据驱动，扩展只加行）

    private struct Command {
        let id: String
        let title: String
        let subtitle: String?
        let icon: String
        let isEnabled: Bool
        let action: (CommandPaletteViewController) -> Void
    }

    private struct Section {
        let title: String
        let commands: [Command]
    }

    private let engine = PlaybackEngine.shared
    private let queueManager = QueueManager.shared

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var allSections: [Section] = []
    private var visibleSections: [Section] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        overrideUserInterfaceStyle = .dark
        buildViews()
        allSections = buildRegistry()
        visibleSections = allSections
        tableView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    // MARK: - 搭建（搜索吸顶：头部固定在安全区下，列表独立滚动）

    private func buildViews() {
        let titleLabel = UILabel()
        titleLabel.text = "命令"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        searchBar.placeholder = "搜索命令"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cmd")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            searchBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 2),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - 注册表（今晚有真后端的命令全集）

    private func buildRegistry() -> [Section] {
        let track = engine.currentTrack
        let hasTrack = track != nil
        let liked = track.map { LikesStore.shared.isLiked($0.id) } ?? false
        let starred = track.map { StarStore.shared.isStarred($0.id) } ?? false
        return [
            Section(title: "播放", commands: [
                Command(
                    id: "playback.toggle",
                    title: engine.isPlaying ? "暂停" : "播放",
                    subtitle: track.map { "\($0.title) - \($0.artist)" },
                    icon: engine.isPlaying ? "pause.fill" : "play.fill",
                    isEnabled: hasTrack,
                    action: { host in
                        host.engine.togglePlayPause()
                        host.finish(id: "playback.toggle")
                    }),
                Command(
                    id: "playback.prev",
                    title: "上一首",
                    subtitle: nil,
                    icon: "backward.end.fill",
                    isEnabled: hasTrack,
                    action: { host in
                        host.queueManager.playPrevious()
                        host.finish(id: "playback.prev")
                    }),
                Command(
                    id: "playback.next",
                    title: "下一首",
                    subtitle: nil,
                    icon: "forward.end.fill",
                    isEnabled: hasTrack,
                    action: { host in
                        host.queueManager.playNext(manual: true)
                        host.finish(id: "playback.next")
                    }),
            ]),
            Section(title: "队列", commands: [
                Command(
                    id: "queue.shuffle",
                    title: "打乱队列",
                    subtitle: queueManager.queue.count >= 2
                        ? "共 \(queueManager.queue.count) 首" : "队列不足 2 首",
                    icon: "shuffle",
                    isEnabled: queueManager.queue.count >= 2,
                    action: { host in
                        host.queueManager.shuffleQueue()
                        host.finish(id: "queue.shuffle",
                                    toast: "队列已打乱")
                    }),
                Command(
                    id: "queue.open",
                    title: "打开队列",
                    subtitle: "播放面板 · 队列页签",
                    icon: "list.bullet",
                    isEnabled: true,
                    action: { host in
                        host.finish(id: "queue.open",
                                    then: host.onOpenQueuePanel)
                    }),
            ]),
            Section(title: "当前歌曲", commands: [
                Command(
                    id: "track.like",
                    title: liked ? "取消喜欢" : "喜欢",
                    subtitle: track?.title,
                    icon: liked ? "heart.fill" : "heart",
                    isEnabled: hasTrack,
                    action: { host in
                        host.toggleLike()
                    }),
                Command(
                    id: "track.star",
                    title: starred ? "取消星标" : "星标",
                    subtitle: track?.title,
                    icon: starred ? "star.fill" : "star",
                    isEnabled: hasTrack,
                    action: { host in
                        host.toggleStar()
                    }),
            ]),
            Section(title: "工具", commands: [
                Command(
                    id: "tool.sleep",
                    title: "睡眠定时",
                    subtitle: sleepSubtitle(),
                    icon: "moon.zzz",
                    isEnabled: true,
                    action: { host in
                        host.presentSleepMenu()
                    }),
                Command(
                    id: "tool.subtitle",
                    title: "字幕调节",
                    subtitle: "底部字幕层设置",
                    icon: "captions.bubble",
                    isEnabled: true,
                    action: { host in
                        host.finish(id: "tool.subtitle",
                                    then: host.onOpenSubtitleSettings)
                    }),
                Command(
                    id: "tool.visualizer",
                    title: "选择可视化",
                    subtitle: "歌词样式选择器",
                    icon: "sparkles",
                    isEnabled: true,
                    action: { host in
                        host.finish(id: "tool.visualizer",
                                    then: host.onOpenStylePicker)
                    }),
                Command(
                    id: "tool.volumeUp",
                    title: "音量 +",
                    subtitle: "当前 \(Int((engine.volume * 100).rounded()))%",
                    icon: "speaker.wave.3",
                    isEnabled: true,
                    action: { host in
                        host.engine.setVolume(host.engine.volume + 0.1)
                        host.finish(id: "tool.volumeUp",
                                    toast: "音量 \(Int((host.engine.volume * 100).rounded()))%")
                    }),
                Command(
                    id: "tool.volumeDown",
                    title: "音量 −",
                    subtitle: "当前 \(Int((engine.volume * 100).rounded()))%",
                    icon: "speaker.wave.1",
                    isEnabled: true,
                    action: { host in
                        host.engine.setVolume(host.engine.volume - 0.1)
                        host.finish(id: "tool.volumeDown",
                                    toast: "音量 \(Int((host.engine.volume * 100).rounded()))%")
                    }),
            ]),
        ]
    }

    private func sleepSubtitle() -> String {
        let timer = SleepTimerController.shared
        guard timer.isActive, let remaining = timer.remainingSeconds else {
            return "未设置"
        }
        let total = Int(remaining.rounded())
        return String(format: "剩 %d:%02d 后暂停", total / 60, total % 60)
    }

    // MARK: - 执行收口

    /// 真执行后的统一收口：落面包屑 → 关面板 → 可选 toast / 可选
    /// 宿主跳转（跳转在 dismiss 完成后由宿主呈现目标面）。
    private func finish(id: String, toast: String? = nil,
                        then: (() -> Void)? = nil) {
        Breadcrumbs.log("stage.palette.exec id=\(id)")
        dismiss(animated: true) {
            if let toast {
                NativePlaybackFailureToast.show(message: toast)
            }
            then?()
        }
    }

    private func toggleLike() {
        guard let track = engine.currentTrack else { return }
        let id = track.id
        let newState = LikesStore.shared.toggle(id)
        Breadcrumbs.log("stage.palette.like id=\(id) on=\(newState)")
        Task {
            do {
                _ = try await NativeDataClient.shared.setLike(
                    trackId: id, like: newState)
            } catch {
                LikesStore.shared.toggle(id)
            }
        }
        finish(id: "track.like", toast: newState ? "已喜欢" : "已取消喜欢")
    }

    private func toggleStar() {
        guard let track = engine.currentTrack else { return }
        // StarStore（工作流 C 已落盘）：纯本地真源，toggle 返回新态。
        let newState = StarStore.shared.toggle(track.id)
        Breadcrumbs.log("stage.palette.star id=\(track.id) on=\(newState)")
        finish(id: "track.star", toast: newState ? "已星标" : "已取消星标")
    }

    /// 睡眠定时预设菜单（现有预设档全集）：面板不关、先选档，选后
    /// 走 finish 收口（关面板＋toast）。当前档打勾（activePresetMinutes
    /// 反推，与队列面板同口径）。
    private func presentSleepMenu() {
        let alert = UIAlertController(
            title: "睡眠定时", message: nil, preferredStyle: .actionSheet)
        let active = SleepTimerController.shared.activePresetMinutes
        for minutes in SleepTimerController.presets {
            let isCurrent = SleepTimerController.shared.isActive
                ? (active == minutes && minutes > 0) : minutes == 0
            let title = (minutes == 0 ? "关" : "\(minutes) 分钟后暂停")
                + (isCurrent ? " ✓" : "")
            alert.addAction(UIAlertAction(title: title, style: .default) {
                [weak self] _ in
                SleepTimerController.shared.set(minutes: minutes)
                self?.finish(id: "tool.sleep",
                             toast: minutes == 0 ? "睡眠定时已关"
                                 : "睡眠定时 \(minutes) 分钟")
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        // iPad 锚点兜底（actionSheet 无锚会崩）：锚到搜索框。
        if let popover = alert.popoverPresentationController {
            popover.sourceView = searchBar
            popover.sourceRect = searchBar.bounds
        }
        present(alert, animated: true)
    }
}

// MARK: - 搜索过滤（注册表驱动：按标题/副标题匹配，空组剔除）

extension CommandPaletteViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            visibleSections = allSections
            tableView.reloadData()
            return
        }
        visibleSections = allSections.compactMap { section in
            let matched = section.commands.filter {
                $0.title.lowercased().contains(query)
                    || ($0.subtitle?.lowercased().contains(query) ?? false)
                    || $0.id.contains(query)
            }
            return matched.isEmpty ? nil
                : Section(title: section.title, commands: matched)
        }
        tableView.reloadData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - 列表（分组分节，注册表渲染）

extension CommandPaletteViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    func tableView(_ tableView: UITableView,
                   titleForHeaderInSection section: Int) -> String? {
        visibleSections[section].title
    }

    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        visibleSections[section].commands.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "cmd", for: indexPath)
        let command = visibleSections[indexPath.section].commands[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = command.title
        config.secondaryText = command.subtitle
        config.image = UIImage(systemName: command.icon)
        config.textProperties.color = command.isEnabled
            ? .white : UIColor.white.withAlphaComponent(0.4)
        config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.5)
        config.imageProperties.tintColor = command.isEnabled
            ? UIColor.white.withAlphaComponent(0.85)
            : UIColor.white.withAlphaComponent(0.35)
        cell.contentConfiguration = config
        cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        cell.accessoryType = .none
        cell.selectionStyle = command.isEnabled ? .default : .none
        return cell
    }

    func tableView(_ tableView: UITableView,
                   didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let command = visibleSections[indexPath.section].commands[indexPath.row]
        guard command.isEnabled else { return }
        searchBar.resignFirstResponder()
        command.action(self)
    }
}
