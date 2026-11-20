import Combine
import UIKit

// WorkbenchLocalViewController.swift
//
// (53) A 组：本地分区。网页版本地页签是本地曲库（文件夹/专辑/
// 歌手/歌单 + 文件导入），原生侧没有文件导入能力（无对口
// 既有通路），本轮只落原生真实存在的本机数据，缺的诚实标注：
// - 本机歌单：LocalPlaylistStore（(50) 落地：在播放队列面板
//   把当前队列命名存到本机），点开是其曲目列表、可整表点播；
// - 最近播放：PlayHistoryStore 近 7 天记录（探索页自有分区
//   同源），点开列表点播。
// 两者皆空时落诚实空态，说明本机歌单的产生方式，不假装有
// 文件导入。

final class WorkbenchLocalViewController: WorkbenchSectionViewController,
    UITableViewDataSource, UITableViewDelegate {

    private enum Row {
        case localPlaylist(LocalPlaylistStore.LocalPlaylist)
        case recent
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var rows: [Row] = []
    private var recentTracks: [FoliaTrack] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(title: "本地")
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
        // 本机歌单增删（队列面板保存/删除）时原地刷新。
        LocalPlaylistStore.shared.$playlists
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadRows() }
            .store(in: &cancellables)
        reloadRows()
    }

    private func reloadRows() {
        recentTracks = PlayHistoryStore.shared.recentTracks()
        var built: [Row] = LocalPlaylistStore.shared.playlists.map(Row.localPlaylist)
        if !recentTracks.isEmpty { built.append(.recent) }
        rows = built
        tableView.reloadData()
        Breadcrumbs.log("workbench.local ok playlists=\(LocalPlaylistStore.shared.playlists.count) recent=\(recentTracks.count)")
        if built.isEmpty {
            stateView.showMessage("本机还没有歌单。播放时在队列面板里把当前队列「保存为歌单」，就会出现在这里。")
        } else {
            stateView.hide()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: WorkbenchTrackCell.reuseId, for: indexPath) as! WorkbenchTrackCell
        switch rows[indexPath.row] {
        case .localPlaylist(let playlist):
            cell.configure(title: playlist.name, subtitle: "本机歌单 · \(playlist.tracks.count) 首",
                           coverRaw: playlist.tracks.first?.artworkURL?.absoluteString,
                           representedId: "local-pl-\(playlist.id)")
        case .recent:
            cell.configure(title: "最近播放", subtitle: "近 7 天 · \(recentTracks.count) 首",
                           coverRaw: recentTracks.first?.artworkURL?.absoluteString,
                           representedId: "local-recent")
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .localPlaylist(let playlist):
            guard !playlist.tracks.isEmpty else { return }
            Breadcrumbs.log("workbench.local open playlist id=\(playlist.id) n=\(playlist.tracks.count)")
            let list = WorkbenchTrackListViewController(
                title: playlist.name, tracks: playlist.tracks, queueSource: "workbench-local")
            list.dismissToWall = dismissToWall
            list.modalPresentationStyle = .fullScreen
            present(list, animated: true)
        case .recent:
            guard !recentTracks.isEmpty else { return }
            Breadcrumbs.log("workbench.local open recent n=\(recentTracks.count)")
            let list = WorkbenchTrackListViewController(
                title: "最近播放", tracks: recentTracks, queueSource: "workbench-local")
            list.dismissToWall = dismissToWall
            list.modalPresentationStyle = .fullScreen
            present(list, animated: true)
        }
    }
}
