import UIKit

// WorkbenchRadioViewController.swift
//
// (53) A 组：电台分区。网页版对照：电台页签 = omni.getHomeFeed
// 三路并行组装（library/core/home/homeCards.buildOnlineRadioCards
// + onlineHomeFeeds.createRadioFeed）——私人 FM 卡（点它直接
// 播放）+ 每日推荐卡 + 推荐歌单，任一路失败只空该路、三路全空
// 才整份失败。原生侧同构：三路经 NativeDataClient 带会话并发
// 拉取（/personal_fm、/recommend/songs、/recommend/resource，
// 见 NativeDataClient+Workbench），各自成败互不拖垮；三路全空
// （含未登录 301）落诚实空态 + 面包屑 workbench.radio.unavailable。
//
// 交互：私人 FM 行点按即以该批为队列起播；每日推荐行进曲目
// 列表页点播；推荐歌单行开曲目墙（与歌单分区同一目标）。

final class WorkbenchRadioViewController: WorkbenchSectionViewController,
    UITableViewDataSource, UITableViewDelegate {

    private enum Row {
        case personalFM
        case daily
        case playlist(NativePlaylistSummary)
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var fmTracks: [FoliaTrack] = []
    private var dailyTracks: [FoliaTrack] = []
    private var recommended: [NativePlaylistSummary] = []
    private var rows: [Row] = []
    private var loadGeneration = 0

    init() {
        super.init(title: "电台")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .clear
        tableView.separatorColor = WorkbenchTheme.hairline
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.register(WorkbenchTrackCell.self, forCellReuseIdentifier: WorkbenchTrackCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
        load()
    }

    private func load() {
        loadGeneration += 1
        let generation = loadGeneration
        stateView.showLoading("电台加载中…")
        Task { [weak self] in
            guard let self else { return }
            await NativeDataClient.shared.refreshWebSession()
            // 三路并发、各自成败（omni.getHomeFeed 的 allSettled 口径）。
            async let fmTask = NativeDataClient.shared.fetchPersonalFM()
            async let dailyTask = NativeDataClient.shared.fetchDailySongs()
            async let recommendedTask = NativeDataClient.shared.fetchRecommendedPlaylists()
            let fm = (await try? fmTask) ?? []
            let daily = (await try? dailyTask) ?? []
            let rec = (await try? recommendedTask) ?? []
            await MainActor.run {
                guard generation == self.loadGeneration else { return }
                self.fmTracks = fm.map(workbenchFoliaTrack)
                self.dailyTracks = daily.map(workbenchFoliaTrack)
                self.recommended = rec
                var built: [Row] = []
                if !fm.isEmpty { built.append(.personalFM) }
                if !daily.isEmpty { built.append(.daily) }
                built.append(contentsOf: rec.map(Row.playlist))
                self.rows = built
                self.tableView.reloadData()
                Breadcrumbs.log("workbench.radio ok fm=\(fm.count) daily=\(daily.count) rec=\(rec.count)")
                if built.isEmpty {
                    Breadcrumbs.log("workbench.radio.unavailable")
                    if NativeSessionStore.shared.load() == nil {
                        self.showLoginPrompt(message: "电台需要登录网易云（私人 FM 与每日推荐都是按你的账号生成的）") { [weak self] in
                            self?.load()
                        }
                    } else {
                        self.stateView.showMessage("电台暂时没有内容", actionTitle: "重试") { [weak self] in
                            self?.load()
                        }
                    }
                } else {
                    self.stateView.hide()
                }
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: WorkbenchTrackCell.reuseId, for: indexPath) as! WorkbenchTrackCell
        switch rows[indexPath.row] {
        case .personalFM:
            cell.configure(title: "私人 FM", subtitle: "按你的口味生成 · 点按直接播放",
                           coverRaw: fmTracks.first?.artworkURL?.absoluteString,
                           representedId: "radio-fm")
        case .daily:
            cell.configure(title: "每日推荐", subtitle: "\(dailyTracks.count) 首 · 点按查看",
                           coverRaw: dailyTracks.first?.artworkURL?.absoluteString,
                           representedId: "radio-daily")
        case .playlist(let playlist):
            cell.configure(title: playlist.name, subtitle: "推荐歌单 · \(playlist.trackCount) 首",
                           coverRaw: playlist.coverUrl, representedId: "radio-pl-\(playlist.id)")
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .personalFM:
            guard !fmTracks.isEmpty else { return }
            Breadcrumbs.log("workbench.radio play fm n=\(fmTracks.count)")
            QueueManager.shared.setQueue(fmTracks, startingAt: 0, source: "workbench-radio")
            if let dismissToWall { dismissToWall() } else { dismiss(animated: true) }
        case .daily:
            guard !dailyTracks.isEmpty else { return }
            Breadcrumbs.log("workbench.radio open daily n=\(dailyTracks.count)")
            let list = WorkbenchTrackListViewController(
                title: "每日推荐", tracks: dailyTracks, queueSource: "workbench-radio")
            list.dismissToWall = dismissToWall
            list.modalPresentationStyle = .fullScreen
            present(list, animated: true)
        case .playlist(let playlist):
            Breadcrumbs.log("workbench.radio open playlist id=\(playlist.id)")
            let wall = WallPrototypeViewController(
                playlistId: playlist.id, title: playlist.name, coverUrl: playlist.coverUrl)
            wall.modalPresentationStyle = .fullScreen
            wall.modalTransitionStyle = .crossDissolve
            wall.startPreload()
            Task { [weak self] in
                _ = await wall.awaitSeed(timeout: 0.25)
                self?.present(wall, animated: true)
            }
        }
    }
}
