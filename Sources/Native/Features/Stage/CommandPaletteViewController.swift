import SwiftUI
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
        overrideUserInterfaceStyle = ThemeSystem62.interfaceStyleOverride() // (62) INT-1：明暗三段读主题系统，不再写死深色
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
        WC62Bootstrap.startIfNeeded()
        let track = engine.currentTrack
        let hasTrack = track != nil
        let liked = track.map { LikesStore.shared.isLiked($0.id) } ?? false
        let starred = track.map { StarStore.shared.isStarred($0.id) } ?? false
        var sections: [Section] = [
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
                        // (62) WC：宿主未注入时兜底直达面板队列签
                        // （兼修 C2 墙面两宿主该命令空转）。
                        if host.onOpenQueuePanel != nil {
                            host.finish(id: "queue.open",
                                        then: host.onOpenQueuePanel)
                        } else {
                            host.openPanel62(tab: .queue)
                        }
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
        sections += buildRegistry62(track: track, hasTrack: hasTrack)
        // 置顶槽位（§4.8）：WB 的 PinnedCommands62 未就绪时按任务
        // 口径直读键 settings.shortcuts.pinnedCommandIDs 兜底。
        let pinnedIds = UserDefaults.standard.stringArray(
            forKey: "settings.shortcuts.pinnedCommandIDs") ?? []
        if !pinnedIds.isEmpty {
            let all = sections.flatMap { $0.commands }
            let pinned = pinnedIds.compactMap { id in all.first { $0.id == id } }
            if !pinned.isEmpty {
                sections.insert(Section(title: "置顶", commands: pinned), at: 0)
            }
        }
        return sections
    }

    // MARK: - (62) WC 簇命令全集（导航/面板/歌词/速记簿/目录/大肥鱼/场景/主题）

    private func buildRegistry62(track: FoliaTrack?, hasTrack: Bool) -> [Section] {
        [
            Section(title: "导航", commands: [
                Command(id: "nav.search", title: "去搜索", subtitle: "搜索工作区",
                        icon: "magnifyingglass", isEnabled: true, action: { host in
                    host.finish(id: "nav.search", then: {
                        guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
                        SearchHostPresenter.presentSearch(from: top)
                    })
                }),
                Command(id: "nav.settings", title: "打开设置", subtitle: nil,
                        icon: "gearshape", isEnabled: true, action: { host in
                    host.finish(id: "nav.settings", then: {
                        MiniPlayerPanelPresenter.presentSettings()
                    })
                }),
                Command(id: "nav.sketchbook", title: "打开速记簿", subtitle: "主页墙左缘抽屉",
                        icon: "note.text", isEnabled: true, action: { host in
                    host.openSketchbook62()
                }),
                Command(id: "nav.local", title: "本地曲库", subtitle: "工作台 · 本地分区",
                        icon: "folder", isEnabled: true, action: { host in
                    host.finish(id: "nav.local", then: {
                        guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
                        let local = WorkbenchLocalViewController()
                        local.modalPresentationStyle = .fullScreen
                        top.present(local, animated: true)
                    })
                }),
                Command(id: "nav.navidrome", title: "Navidrome", subtitle: "服务器歌单/专辑",
                        icon: "server.rack", isEnabled: SettingsStore.navidromeEnabled62,
                        action: { host in
                    host.finish(id: "nav.navidrome", then: {
                        guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
                        NavidromeBrowser62ViewController.present(from: top)
                    })
                }),
                Command(id: "nav.cloud", title: "云盘", subtitle: "网易云云盘",
                        icon: "cloud", isEnabled: true, action: { host in
                    host.finish(id: "nav.cloud", then: {
                        guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
                        let drive = CloudDriveViewController()
                        drive.modalPresentationStyle = .fullScreen
                        top.present(drive, animated: true)
                    })
                }),
                Command(id: "nav.explore", title: "探索页", subtitle: "货架与每日推荐",
                        icon: "safari", isEnabled: true, action: { host in
                    host.finish(id: "nav.explore", then: {
                        guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
                        let browse = UIHostingController(rootView: NativeBrowseView())
                        browse.modalPresentationStyle = .fullScreen
                        top.present(browse, animated: true)
                    })
                }),
                // (71) 与网页版 command-palette 同名命令
                // navigate-lattice：整条队列铺成海报墙。
                Command(id: "navigate-lattice", title: "队列拼贴", subtitle: "Lattice · 整条播放队列铺墙",
                        icon: "square.grid.3x3.fill", isEnabled: true, action: { host in
                    host.finish(id: "navigate-lattice", then: {
                        guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
                        QueueLatticeViewController.present(from: top)
                    })
                }),
            ]),
            Section(title: "面板", commands: [
                Command(id: "panel.open", title: "打开播放面板", subtitle: "封面页签",
                        icon: "square.grid.2x2", isEnabled: true, action: { host in
                    host.openPanel62(tab: .cover)
                }),
                Command(id: "panel.quality", title: "播放面板 · 音质", subtitle: "取流档位",
                        icon: "waveform", isEnabled: true, action: { host in
                    host.openPanel62(tab: .quality)
                }),
                Command(id: "panel.local", title: "播放面板 · 本地", subtitle: "本地曲库/已缓存",
                        icon: "internaldrive", isEnabled: true, action: { host in
                    host.openPanel62(tab: .local)
                }),
                Command(id: "panel.navidrome", title: "播放面板 · Navidrome", subtitle: nil,
                        icon: "server.rack", isEnabled: SettingsStore.navidromeEnabled62,
                        action: { host in
                    host.openPanel62(tab: .navidrome)
                }),
                Command(id: "panel.style", title: "样式选择器", subtitle: "歌词样式",
                        icon: "sparkles", isEnabled: onOpenStylePicker != nil, action: { host in
                    host.finish(id: "panel.style", then: host.onOpenStylePicker)
                }),
                Command(id: "panel.posterwall", title: "直播海报墙", subtitle: "全屏封面轮播",
                        icon: "rectangle.on.rectangle", isEnabled: true, action: { host in
                    host.finish(id: "panel.posterwall", then: {
                        guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
                        LivePosterWall62ViewController.present(from: top)
                    })
                }),
            ]),
            Section(title: "歌词", commands: [
                Command(id: "lyric.export", title: "导出歌词", subtitle: track?.title ?? "暂无播放",
                        icon: "square.and.arrow.up", isEnabled: hasTrack, action: { host in
                    host.finish(id: "lyric.export", then: {
                        guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
                        LyricExport62.exportCurrentTrack(from: top)
                    })
                }),
                Command(id: "lyric.offsetMinus", title: "歌词偏移 −100ms",
                        subtitle: "当前 \(SettingsStore.globalLyricTimelineOffsetMs)ms",
                        icon: "minus.circle", isEnabled: true, action: { host in
                    SettingsStore.globalLyricTimelineOffsetMs -= 100
                    host.finish(id: "lyric.offsetMinus",
                                toast: "歌词偏移 \(SettingsStore.globalLyricTimelineOffsetMs)ms")
                }),
                Command(id: "lyric.offsetPlus", title: "歌词偏移 +100ms",
                        subtitle: "当前 \(SettingsStore.globalLyricTimelineOffsetMs)ms",
                        icon: "plus.circle", isEnabled: true, action: { host in
                    SettingsStore.globalLyricTimelineOffsetMs += 100
                    host.finish(id: "lyric.offsetPlus",
                                toast: "歌词偏移 \(SettingsStore.globalLyricTimelineOffsetMs)ms")
                }),
                Command(id: "lyric.offsetReset", title: "歌词偏移归零", subtitle: nil,
                        icon: "arrow.counterclockwise", isEnabled: true, action: { host in
                    SettingsStore.globalLyricTimelineOffsetMs = 0
                    host.finish(id: "lyric.offsetReset", toast: "歌词偏移已归零")
                }),
                Command(id: "lyric.checkin", title: "网易云听歌打卡", subtitle: "接口可用性待核对",
                        icon: "checkmark.seal", isEnabled: true, action: { host in
                    host.finish(id: "lyric.checkin")
                    Task {
                        let text = await Scrobble62.shared.performCheckIn()
                        await MainActor.run {
                            NativePlaybackFailureToast.show(message: text)
                        }
                    }
                }),
            ]),
            Section(title: "速记簿", commands: [
                Command(id: "sketch.open", title: "打开速记簿", subtitle: nil,
                        icon: "note.text", isEnabled: true, action: { host in
                    host.openSketchbook62()
                }),
                Command(id: "sketch.addCurrent", title: "收当前歌进速记簿",
                        subtitle: track?.title ?? "暂无播放",
                        icon: "plus.rectangle.on.folder", isEnabled: hasTrack, action: { host in
                    guard let current = host.engine.currentTrack else { return }
                    let added = SketchbookStore.shared.add(
                        current, source: "command62", originLabel: "命令面板")
                    host.finish(id: "sketch.addCurrent",
                                toast: added ? "已收进速记簿" : "已在速记簿里")
                }),
                Command(id: "sketch.clear", title: "清空速记簿", subtitle: "需二次确认",
                        icon: "trash", isEnabled: !SketchbookStore.shared.entries.isEmpty,
                        action: { host in
                    host.confirmClearSketchbook62()
                }),
            ]),
            Section(title: "目录管理", commands: [
                Command(id: "dir.rescanLocal", title: "重扫本地库", subtitle: "已导入文件夹",
                        icon: "arrow.clockwise", isEnabled: true, action: { host in
                    LocalLibrary62.shared.rescanFolders()
                    host.finish(id: "dir.rescanLocal", toast: "已触发本地库重扫")
                }),
                Command(id: "dir.precache", title: "预缓存队列", subtitle: "当前曲＋后 5 首",
                        icon: "arrow.down.circle", isEnabled: hasTrack, action: { host in
                    host.finish(id: "dir.precache")
                    Task {
                        let done = await MediaCache62.shared.precacheQueue()
                        await MainActor.run {
                            NativePlaybackFailureToast.show(message: "预缓存完成 \(done) 首")
                        }
                    }
                }),
                Command(id: "dir.clearCache", title: "清除媒体缓存",
                        subtitle: "\(MediaCache62.shared.cachedCount) 首",
                        icon: "trash", isEnabled: true, action: { host in
                    let freed = MediaCache62.shared.clearAll()
                    host.finish(id: "dir.clearCache",
                                toast: "已清除 \(SettingsCacheManager.sizeText(freed))")
                }),
                Command(id: "dir.clearStats", title: "清除听歌统计", subtitle: "分析数据",
                        icon: "chart.bar.xaxis", isEnabled: true, action: { host in
                    ListeningStats62.shared.clearAll()
                    host.finish(id: "dir.clearStats", toast: "听歌统计已清除")
                }),
            ]),
            Section(title: "大肥鱼", commands: [
                Command(id: "dafeiyu.open", title: "打开陪伴面板", subtitle: "QQ 机器人 · 以 QQ 端为准",
                        icon: "fish", isEnabled: true, action: { host in
                    host.finish(id: "dafeiyu.open", then: {
                        guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
                        DafeiyuPanel62ViewController.present(from: top)
                    })
                }),
                Command(id: "dafeiyu.copyGroup", title: "复制大肥鱼群号",
                        subtitle: DafeiyuPanel62ViewController.groupQQ,
                        icon: "doc.on.doc", isEnabled: true, action: { host in
                    UIPasteboard.general.string = DafeiyuPanel62ViewController.groupQQ
                    host.finish(id: "dafeiyu.copyGroup", toast: "群号已复制")
                }),
            ]),
            Section(title: "场景与主题", commands: [
                Command(id: "scene.cinema", title: "切换场景：影厅", subtitle: "场景键直写（WA 场景系统消费）",
                        icon: "film", isEnabled: true, action: { host in
                    host.applyScene62("cinema")
                }),
                Command(id: "scene.default", title: "切换场景：默认", subtitle: "场景键直写（WA 场景系统消费）",
                        icon: "house", isEnabled: true, action: { host in
                    host.applyScene62("default")
                }),
                Command(id: "theme.park", title: "打开主题乐园", subtitle: "设置 · 外观页签",
                        icon: "paintpalette", isEnabled: true, action: { host in
                    host.finish(id: "theme.park", then: {
                        MiniPlayerPanelPresenter.presentSettings()
                    })
                }),
                Command(id: "theme.workbench", title: "歌词样式工作台", subtitle: "经样式选择器进入",
                        icon: "slider.horizontal.3", isEnabled: onOpenStylePicker != nil,
                        action: { host in
                    host.finish(id: "theme.workbench", then: host.onOpenStylePicker)
                }),
            ]),
        ]
    }

    /// 场景切换（62）：WA 的 SceneSystem62 未就绪时按任务口径
    /// 以设置键直写兜底（键 settings.appearance.scene），WA 就绪
    /// 后由其消费同一键。面包屑标注 fallback=key。
    private func applyScene62(_ scene: String) {
        UserDefaults.standard.set(scene, forKey: "settings.appearance.scene")
        Breadcrumbs.log("stage.palette.scene value=\(scene) fallback=key")
        finish(id: "scene.\(scene)", toast: "场景已切换：\(scene == "cinema" ? "影厅" : "默认")")
    }

    /// 打开播放面板指定页签：宿主注入了队列回调也统一走面板
    /// 直达（墙面宿主未注入时的兜底，兼修 C2 队列命令落点）。
    private func openPanel62(tab: PlaybackPanelViewController.Tab) {
        finish(id: "panel.open.\(tab.title)", then: {
            guard let top = MiniPlayerPanelPresenter.topViewController() else { return }
            PlaybackPanelViewController.present(from: top, initialTab: tab)
        })
    }

    /// 打开速记簿：在窗口视图树里找已装配的 SketchbookDrawerView
    /// 真调 setOpen；不在场（不在主页墙）时诚实 toast。
    private func openSketchbook62() {
        Breadcrumbs.log("stage.palette.exec id=sketch.open62")
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            if let drawer = self.findSketchbookDrawer62() {
                drawer.setOpen(true, source: "command62")
            } else {
                NativePlaybackFailureToast.show(message: "速记簿在主页墙左缘，请先回到主页墙")
            }
        }
    }

    private func findSketchbookDrawer62() -> SketchbookDrawerView? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
        for window in scene?.windows ?? [] {
            if let found = searchDrawer62(in: window) { return found }
        }
        return nil
    }

    private func searchDrawer62(in view: UIView) -> SketchbookDrawerView? {
        if let drawer = view as? SketchbookDrawerView { return drawer }
        for sub in view.subviews {
            if let found = searchDrawer62(in: sub) { return found }
        }
        return nil
    }

    private func confirmClearSketchbook62() {
        let alert = UIAlertController(
            title: "清空速记簿", message: "将移除全部暂存歌曲（历史保留）。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            SketchbookStore.shared.clear(source: "command62")
            self?.finish(id: "sketch.clear", toast: "速记簿已清空")
        })
        present(alert, animated: true)
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
