import SwiftUI
import UIKit

// WorkbenchAlbumListViewController.swift
//
// (53) A 组：专辑分区——收藏专辑列表（网页版专辑页签口径：
// omni.getUserAlbums → netease /album/sublist，登录态接口，
// 经 NativeDataClient 带会话拉取，见 NativeDataClient+Workbench）。
// 点行打开专辑详情：复用既有 CollectionView（kind=.album，
// 内部走 EdgeOneAPIClient.fetchAlbumDetail 的 /album 路由，
// 专辑详情为公开接口），挂载方式与 SearchHostPresenter 呈
// CollectionView 同构（UIHostingController 全屏），其点歌
// 自带 setQueue 漏斗，本页不另造播放通路。

final class WorkbenchAlbumListViewController: WorkbenchSectionViewController,
    UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var albums: [WorkbenchAlbumSummary] = []
    private var loadGeneration = 0

    init() {
        super.init(title: "专辑")
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
        stateView.showLoading("专辑加载中…")
        Task { [weak self] in
            guard let self else { return }
            await NativeDataClient.shared.refreshWebSession()
            do {
                let result = try await NativeDataClient.shared.fetchFavoriteAlbums()
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    self.albums = result
                    self.tableView.reloadData()
                    Breadcrumbs.log("workbench.albums ok n=\(result.count)")
                    if result.isEmpty {
                        self.stateView.showMessage("还没有收藏的专辑")
                    } else {
                        self.stateView.hide()
                    }
                }
            } catch NativeDataClient.DataError.notLoggedIn {
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    Breadcrumbs.log("workbench.albums state=not-logged-in")
                    self.showLoginPrompt(message: "登录网易云后，这里会显示你收藏的专辑") { [weak self] in
                        self?.load()
                    }
                }
            } catch {
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    Breadcrumbs.log("workbench.albums failed err=\(error)")
                    self.stateView.showMessage("专辑加载失败", actionTitle: "重试") { [weak self] in
                        self?.load()
                    }
                }
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        albums.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: WorkbenchTrackCell.reuseId, for: indexPath) as! WorkbenchTrackCell
        let album = albums[indexPath.row]
        let artist = album.artistLabel.isEmpty ? "专辑" : album.artistLabel
        let subtitle = album.trackCount > 0 ? "\(artist) · \(album.trackCount) 首" : artist
        cell.configure(title: album.name, subtitle: subtitle,
                       coverRaw: album.coverUrl, representedId: "album-\(album.id)")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let album = albums[indexPath.row]
        guard let numericId = Int(album.id) else {
            Breadcrumbs.log("workbench.albums open-skip id=\(album.id) reason=non-numeric")
            return
        }
        Breadcrumbs.log("workbench.albums open id=\(album.id)")
        let collection = ExploreCollection(
            kind: .album, id: numericId, name: album.name,
            coverURL: album.coverUrl.flatMap { URL(string: $0) },
            subtitle: album.artistLabel.isEmpty ? "专辑" : album.artistLabel)
        let host = UIHostingController(rootView: CollectionView(collection: collection))
        host.modalPresentationStyle = .fullScreen
        present(host, animated: true)
    }
}
