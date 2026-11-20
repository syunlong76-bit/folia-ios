import UIKit

// WorkbenchTrackListViewController.swift
//
// (53) A 组：通用曲目列表页（电台每日推荐、本机歌单详情、
// 最近播放共用）。点行 = 以整表为队列经 QueueManager.setQueue
// 起播（与搜索页/集合页同漏斗），随后经宿主注入的
// dismissToWall 回主页墙，墙上迷你台接管呈现。

final class WorkbenchTrackListViewController: WorkbenchSectionViewController,
    UITableViewDataSource, UITableViewDelegate {

    private let tracks: [FoliaTrack]
    private let queueSource: String
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(title: String, tracks: [FoliaTrack], queueSource: String) {
        self.tracks = tracks
        self.queueSource = queueSource
        super.init(title: title)
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
        if tracks.isEmpty {
            stateView.showMessage("这里还没有歌曲")
        } else {
            stateView.hide()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tracks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: WorkbenchTrackCell.reuseId, for: indexPath) as! WorkbenchTrackCell
        let track = tracks[indexPath.row]
        cell.configure(track: track,
                       isCurrent: QueueManager.shared.currentTrack?.id == track.id)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Breadcrumbs.log("workbench.play src=\(queueSource) at=\(indexPath.row) n=\(tracks.count)")
        QueueManager.shared.setQueue(tracks, startingAt: indexPath.row, source: queueSource)
        if let dismissToWall {
            dismissToWall()
        } else {
            dismiss(animated: true)
        }
    }
}
