import UIKit

// WorkbenchPlaylistListViewController.swift
//
// (53) A 组：歌单分区——用户歌单列表（创建 + 收藏）。
// 数据通路与主页墙完全同路：NativeDataClient 的登录态探针 +
// fetchUserPlaylists（带 cookie= 会话参数），顺序即接口顺序
// （= 网页侧卡片顺序）。点行打开该歌单的曲目墙
// WallPrototypeViewController——与主页墙点卡同一目标、同一
// present 规格（fullScreen + crossDissolve + 预加载种子），
// 点歌在曲目墙内经既有 setQueue(source:"native-wall") 漏斗，
// 本页不另造播放通路。

final class WorkbenchPlaylistListViewController: WorkbenchSectionViewController,
    UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var playlists: [NativePlaylistSummary] = []
    private var loadGeneration = 0

    init() {
        super.init(title: "歌单")
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
        stateView.showLoading("歌单加载中…")
        Task { [weak self] in
            guard let self else { return }
            await NativeDataClient.shared.refreshWebSession()
            do {
                let status = try await NativeDataClient.shared.fetchLoginStatus()
                guard status.loggedIn, let userId = status.userId else {
                    await MainActor.run {
                        guard generation == self.loadGeneration else { return }
                        Breadcrumbs.log("workbench.playlists state=not-logged-in")
                        self.showLoginPrompt(message: "登录网易云后，这里会显示你的歌单") { [weak self] in
                            self?.load()
                        }
                    }
                    return
                }
                let result = try await NativeDataClient.shared.fetchUserPlaylists(userId: userId)
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    self.playlists = result
                    self.tableView.reloadData()
                    Breadcrumbs.log("workbench.playlists ok n=\(result.count)")
                    if result.isEmpty {
                        self.stateView.showMessage("还没有歌单")
                    } else {
                        self.stateView.hide()
                    }
                }
            } catch NativeDataClient.DataError.notLoggedIn {
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    Breadcrumbs.log("workbench.playlists state=not-logged-in err=301")
                    self.showLoginPrompt(message: "登录网易云后，这里会显示你的歌单") { [weak self] in
                        self?.load()
                    }
                }
            } catch {
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    Breadcrumbs.log("workbench.playlists failed err=\(error)")
                    self.stateView.showMessage("歌单加载失败", actionTitle: "重试") { [weak self] in
                        self?.load()
                    }
                }
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        playlists.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: WorkbenchTrackCell.reuseId, for: indexPath) as! WorkbenchTrackCell
        let playlist = playlists[indexPath.row]
        let subtitle = playlist.isLikedCollection
            ? "我喜欢的音乐 · \(playlist.trackCount) 首"
            : "歌单 · \(playlist.trackCount) 首"
        cell.configure(title: playlist.name, subtitle: subtitle,
                       coverRaw: playlist.coverUrl, representedId: "playlist-\(playlist.id)")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let playlist = playlists[indexPath.row]
        Breadcrumbs.log("workbench.playlists open id=\(playlist.id)")
        // 与主页墙点卡同规格（见 HomeWallViewController 点按段）。
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
