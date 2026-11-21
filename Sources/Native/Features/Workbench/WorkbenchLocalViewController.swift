import Combine
import UIKit
import UniformTypeIdentifiers

// WorkbenchLocalViewController.swift
//
// (53) A 组：本地分区——本机歌单（LocalPlaylistStore）＋最近
// 播放（PlayHistoryStore）。
// (62) WC 簇升格：本地曲库本体（LocalLibrary62）接入——文件/
// 文件夹导入、四视图（歌单/歌曲/专辑/歌手）、排序与重扫、已
// 导入文件夹管理（移除目录）；另加 Navidrome 入口段（§4.9
// 消费面）。本机歌单与最近播放两段保留原行为。

final class WorkbenchLocalViewController: WorkbenchSectionViewController,
    UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {

    private enum Mode: Int, CaseIterable {
        case playlists, songs, albums, artists
        var title: String {
            switch self {
            case .playlists: return "歌单"
            case .songs: return "歌曲"
            case .albums: return "专辑"
            case .artists: return "歌手"
            }
        }
    }

    private enum PlaylistRow {
        case navidrome
        case localPlaylist(LocalPlaylistStore.LocalPlaylist)
        case recent
        case folder(LocalLibrary62.ImportedFolder)
        case importAction
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let modeControl = UISegmentedControl(items: Mode.allCases.map { $0.title })
    private var mode: Mode = .playlists
    private var playlistRows: [PlaylistRow] = []
    private var recentTracks: [FoliaTrack] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(title: "本地")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 顶部控制行：四视图切换＋导入/重扫/排序。
        let controls = UIStackView()
        controls.axis = .vertical
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controls)
        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        controls.addArrangedSubview(modeControl)
        let buttonRow = UIStackView()
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually
        for (title, selector) in [("导入文件", #selector(importTapped)),
                                  ("重扫", #selector(rescanTapped)),
                                  ("排序", #selector(sortTapped))] as [(String, Selector)] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setTitleColor(WorkbenchTheme.accent, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            button.layer.cornerRadius = 10
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            button.addTarget(self, action: selector, for: .touchUpInside)
            buttonRow.addArrangedSubview(button)
        }
        controls.addArrangedSubview(buttonRow)

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
            controls.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            controls.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            tableView.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
        LocalPlaylistStore.shared.$playlists
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadRows() }
            .store(in: &cancellables)
        LocalLibrary62.shared.$tracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadRows() }
            .store(in: &cancellables)
        LocalLibrary62.shared.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadRows() }
            .store(in: &cancellables)
        reloadRows()
    }

    // MARK: - 数据组装

    private func reloadRows() {
        recentTracks = PlayHistoryStore.shared.recentTracks()
        var built: [PlaylistRow] = []
        if SettingsStore.navidromeEnabled62 { built.append(.navidrome) }
        built += LocalPlaylistStore.shared.playlists.map(PlaylistRow.localPlaylist)
        if !recentTracks.isEmpty { built.append(.recent) }
        built += LocalLibrary62.shared.folders.map(PlaylistRow.folder)
        built.append(.importAction)
        playlistRows = built
        tableView.reloadData()
        Breadcrumbs.log("workbench.local62 mode=\(mode.title) playlists=\(LocalPlaylistStore.shared.playlists.count) local=\(LocalLibrary62.shared.tracks.count)")
        updateEmptyState()
    }

    private func updateEmptyState() {
        switch mode {
        case .playlists:
            stateView.hide()
        case .songs, .albums, .artists:
            if LocalLibrary62.shared.tracks.isEmpty {
                stateView.showMessage("本地曲库还是空的。点上方「导入文件」选择音频文件或整个文件夹，导入后可离线点播。")
            } else {
                stateView.hide()
            }
        }
    }

    // MARK: - 动作

    @objc private func modeChanged() {
        mode = Mode(rawValue: modeControl.selectedSegmentIndex) ?? .playlists
        tableView.reloadData()
        updateEmptyState()
    }

    @objc private func importTapped() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.audio, .folder], asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func rescanTapped() {
        LocalLibrary62.shared.rescanFolders()
        reloadRows()
        NativePlaybackFailureToast.show(message: "已触发重扫")
    }

    @objc private func sortTapped() {
        let alert = UIAlertController(title: "排序", message: nil, preferredStyle: .actionSheet)
        for sortMode in LocalLibrary62.SortMode.allCases {
            alert.addAction(UIAlertAction(title: sortMode.rawValue, style: .default) { _ in
                LocalLibrary62.shared.sortMode = sortMode
                self.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: 80, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        Task { @MainActor in
            let count = await LocalLibrary62.shared.importFiles(urls: urls)
            self.reloadRows()
            NativePlaybackFailureToast.show(
                message: count > 0 ? "已导入 \(count) 首" : "没有可导入的音频文件")
        }
    }

    private func openTrackList(title: String, tracks: [FoliaTrack]) {
        guard !tracks.isEmpty else { return }
        let list = WorkbenchTrackListViewController(
            title: title, tracks: tracks, queueSource: "workbench-local62")
        list.dismissToWall = dismissToWall
        list.modalPresentationStyle = .fullScreen
        present(list, animated: true)
    }

    // MARK: - 表格

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch mode {
        case .playlists: return playlistRows.count
        case .songs: return LocalLibrary62.shared.sortedTracks().count
        case .albums: return LocalLibrary62.shared.albums().count
        case .artists: return LocalLibrary62.shared.artists().count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: WorkbenchTrackCell.reuseId, for: indexPath) as! WorkbenchTrackCell
        switch mode {
        case .playlists:
            switch playlistRows[indexPath.row] {
            case .navidrome:
                cell.configure(title: "Navidrome", subtitle: "服务器歌单/专辑 · 点按浏览",
                               coverRaw: nil, representedId: "local62-navi")
            case .localPlaylist(let playlist):
                cell.configure(title: playlist.name, subtitle: "本机歌单 · \(playlist.tracks.count) 首",
                               coverRaw: playlist.tracks.first?.artworkURL?.absoluteString,
                               representedId: "local-pl-\(playlist.id)")
            case .recent:
                cell.configure(title: "最近播放", subtitle: "近 7 天 · \(recentTracks.count) 首",
                               coverRaw: recentTracks.first?.artworkURL?.absoluteString,
                               representedId: "local-recent")
            case .folder(let folder):
                cell.configure(title: folder.displayName, subtitle: "已导入文件夹 · 左滑移除登记",
                               coverRaw: nil, representedId: "local62-folder-\(folder.id)")
            case .importAction:
                cell.configure(title: "导入文件/文件夹", subtitle: "音频多选或整个文件夹",
                               coverRaw: nil, representedId: "local62-import")
            }
        case .songs:
            let track = LocalLibrary62.shared.sortedTracks()[indexPath.row]
            cell.configure(title: track.title, subtitle: "\(track.artist) · \(track.album)",
                           coverRaw: nil, representedId: "local62-song-\(track.id)")
        case .albums:
            let album = LocalLibrary62.shared.albums()[indexPath.row]
            cell.configure(title: album.name, subtitle: "\(album.artist) · \(album.tracks.count) 首",
                           coverRaw: nil, representedId: "local62-album-\(album.name)")
        case .artists:
            let artist = LocalLibrary62.shared.artists()[indexPath.row]
            cell.configure(title: artist.name, subtitle: "\(artist.tracks.count) 首",
                           coverRaw: nil, representedId: "local62-artist-\(artist.name)")
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch mode {
        case .playlists:
            switch playlistRows[indexPath.row] {
            case .navidrome:
                NavidromeBrowser62ViewController.present(from: self)
            case .localPlaylist(let playlist):
                openTrackList(title: playlist.name, tracks: playlist.tracks)
            case .recent:
                openTrackList(title: "最近播放", tracks: recentTracks)
            case .folder:
                rescanTapped()
            case .importAction:
                importTapped()
            }
        case .songs:
            let tracks = LocalLibrary62.shared.sortedTracks()
            guard tracks.indices.contains(indexPath.row) else { return }
            QueueManager.shared.setQueue(tracks, startingAt: indexPath.row,
                                         source: "workbench-local62")
            dismissToWall?()
        case .albums:
            let album = LocalLibrary62.shared.albums()[indexPath.row]
            openTrackList(title: album.name, tracks: album.tracks)
        case .artists:
            let artist = LocalLibrary62.shared.artists()[indexPath.row]
            openTrackList(title: artist.name, tracks: artist.tracks)
        }
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        switch mode {
        case .playlists:
            if case .folder(let folder) = playlistRows[indexPath.row] {
                let remove = UIContextualAction(style: .destructive, title: "移除目录") {
                    [weak self] _, _, done in
                    LocalLibrary62.shared.removeFolder(id: folder.id)
                    self?.reloadRows()
                    done(true)
                }
                return UISwipeActionsConfiguration(actions: [remove])
            }
            return nil
        case .songs:
            let track = LocalLibrary62.shared.sortedTracks()[indexPath.row]
            let delete = UIContextualAction(style: .destructive, title: "删除") {
                [weak self] _, _, done in
                LocalLibrary62.shared.removeTrack(trackId: track.id)
                self?.reloadRows()
                done(true)
            }
            return UISwipeActionsConfiguration(actions: [delete])
        case .albums, .artists:
            return nil
        }
    }
}
