import UIKit

// AddToPlaylistViewController.swift
//
// 「收藏到歌单」弹层（3.7 (55) 工作流 F）：形态对网页版
// AddToPlaylistHost / PlaylistSelectionDialog——顶部待收藏歌曲
// 主题行 + 歌单搜索框 + 歌单列表（封面/名/曲数，已含当前歌曲的
// 行给「已包含」标记），「我喜欢的音乐」置顶。本文件放搜索同
// 目录（Features/Browse），由 SearchWorkspaceView 的加号经
// sheet 呈出（UIViewControllerRepresentable 包 UINavigation-
// Controller），关闭走导航栏 ✕ 或系统下拉手势。
//
// 数据通路（开工查实，2026-11-21）：
// - 云端加曲：网页 netease.ts updatePlaylistTracks 走 GET
//   /playlist/tracks?op=add&pid=&tracks=&timestamp=（fetchWithCreds
//   带会话）；EdgeOne 函数 ncm-modules 有同名路由（playlist_
//   tracks 模块），LocalServer 对 /api/netease/* 前缀通用转发、
//   NativeDataClient.getJSON 自带 cookie= 会话参数且业务码
//   !=200 即抛错——原生侧此前只是没有调用方，本弹层即补上，
//   不需要改 NativeDataClient 本体。
// - 「我喜欢的音乐」行：网页在线分支走平台红心（omni.likeSong），
//   原生同构 = LikesStore 本地真源 + NativeDataClient.setLike
//   云端同步、失败回滚（与 MiniBarQuickRowView 喜欢钮同口径）。
// - 云端歌单列表：NativeDataClient.fetchLoginStatus +
//   fetchUserPlaylists（创建 + 收藏全量）；只有本人创建的歌单
//   可加曲（creatorId == 当前 userId），收藏的他人歌单行给
//   不可写态；user/playlist 自带的「我喜欢的音乐」
//   （specialType==5）不在列表重复出现，由置顶喜欢行代表。
// - 已包含判定：本机歌单直接查 tracks；云端歌单逐个拉
//   fetchPlaylistDetail 的 trackIds 比对（上限 40 个，超出者
//   不预判、点按时由上游结果说话，重复加曲上游报错走失败
//   toast，不假报成功）。
// - 本机歌单（LocalPlaylistStore）：既有本机歌单点按走
//   addTrack 真追加（(55) 协调者集成补齐，含同 id 防重复）；
//   新建本机歌单（含当前歌曲）走 saveQueue 真写入。

final class AddToPlaylistViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {

    private let track: FoliaTrack

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    /// 列表一行。remote 的 contains：true 已含 / false 未含 /
    /// nil 未预判（未查或超上限）。
    private enum Row {
        case liked(already: Bool)
        case remote(NativePlaylistSummary, contains: Bool?)
        case remoteForeign(NativePlaylistSummary)
        case remoteLoginHint
        case remoteUnsupportedHint
        case local(LocalPlaylistStore.LocalPlaylist, contains: Bool)
        case createLocal
    }

    // 数据快照（远端异步落地后整表重建行）。
    private var loggedIn = false
    private var loginResolved = false
    private var remoteOwn: [(summary: NativePlaylistSummary, contains: Bool?)] = []
    private var remoteForeign: [NativePlaylistSummary] = []
    private var localPlaylists: [LocalPlaylistStore.LocalPlaylist] = []
    private var rows: [Row] = []
    private var searchText = ""
    /// 正在写入的云端歌单 id（防重复点按，行上转菊花）。
    private var busyPlaylistId: String?

    init(track: FoliaTrack) {
        self.track = track
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private var rawTrackId: String {
        track.id.replacingOccurrences(of: "ncm_", with: "")
    }

    private var isNeteaseTrack: Bool { track.sourceType == .netease }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "收藏到歌单"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self,
            action: #selector(closeTapped))
        Breadcrumbs.log("addtoplaylist.open track=\(track.id)")

        searchBar.placeholder = "搜索歌单"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 60
        tableView.backgroundColor = .systemBackground
        tableView.register(AddToPlaylistCell.self,
                           forCellReuseIdentifier: AddToPlaylistCell.reuseId)
        tableView.tableHeaderView = makeSubjectHeader()
        tableView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchBar)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        localPlaylists = LocalPlaylistStore.shared.playlists
        rebuildRows()
        loadRemote()
    }

    /// 主题行：待收藏歌曲的封面 + 歌名 + 歌手（对网页对话框
    /// 顶部的 subject 区）。
    private func makeSubjectHeader() -> UIView {
        let width = UIScreen.main.bounds.width
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 72))
        let cover = UIImageView()
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 6
        cover.backgroundColor = .secondarySystemFill
        cover.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UILabel()
        titleLabel.text = track.title
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        let artistLabel = UILabel()
        artistLabel.text = track.artist
        artistLabel.font = .systemFont(ofSize: 12)
        artistLabel.textColor = .secondaryLabel
        artistLabel.lineBreakMode = .byTruncatingTail
        let labels = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
        labels.axis = .vertical
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(cover)
        header.addSubview(labels)
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            cover.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            cover.widthAnchor.constraint(equalToConstant: 44),
            cover.heightAnchor.constraint(equalToConstant: 44),
            labels.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            labels.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        WorkbenchCover.load(raw: track.artworkURL?.absoluteString, into: cover) { true }
        return header
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    /// 主题行宽度随旋转/尺寸变化跟随（tableHeaderView 的 frame
    /// 不自动重排，宽度变了才重设并重新指派触发布局）。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView,
           abs(header.frame.width - tableView.bounds.width) > 0.5 {
            header.frame.size.width = tableView.bounds.width
            tableView.tableHeaderView = header
        }
    }

    // MARK: - 行构建

    private func rebuildRows() {
        var built: [Row] = []
        built.append(.liked(already: LikesStore.shared.isLiked(track.id)))
        if !isNeteaseTrack {
            built.append(.remoteUnsupportedHint)
        } else if !loginResolved {
            // 登录态未定先不占行，落地后重建补上。
        } else if !loggedIn {
            built.append(.remoteLoginHint)
        } else {
            for entry in remoteOwn where matchesSearch(entry.summary.name) {
                built.append(.remote(entry.summary, contains: entry.contains))
            }
            for summary in remoteForeign where matchesSearch(summary.name) {
                built.append(.remoteForeign(summary))
            }
        }
        for playlist in localPlaylists where matchesSearch(playlist.name) {
            built.append(.local(playlist,
                                 contains: playlist.tracks.contains { $0.id == track.id }))
        }
        built.append(.createLocal)
        rows = built
        tableView.reloadData()
    }

    private func matchesSearch(_ name: String) -> Bool {
        searchText.isEmpty || name.localizedCaseInsensitiveContains(searchText)
    }

    // MARK: - 远端加载与已包含预判

    private func loadRemote() {
        guard isNeteaseTrack else {
            loginResolved = true
            rebuildRows()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await NativeDataClient.shared.refreshWebSession()
            do {
                let status = try await NativeDataClient.shared.fetchLoginStatus()
                guard status.loggedIn, let userId = status.userId else {
                    await MainActor.run {
                        self.loggedIn = false
                        self.loginResolved = true
                        Breadcrumbs.log("addtoplaylist.load state=not-logged-in")
                        self.rebuildRows()
                    }
                    return
                }
                let all = try await NativeDataClient.shared.fetchUserPlaylists(userId: userId)
                // 「我喜欢的音乐」由置顶喜欢行代表，不在列表重复。
                let usable = all.filter { !$0.isLikedCollection }
                let own = usable.filter { $0.creatorId == userId }
                let foreign = usable.filter { $0.creatorId != userId }
                await MainActor.run {
                    self.loggedIn = true
                    self.loginResolved = true
                    self.remoteOwn = own.map { (summary: $0, contains: nil) }
                    self.remoteForeign = foreign
                    Breadcrumbs.log("addtoplaylist.load own=\(own.count) foreign=\(foreign.count)")
                    self.rebuildRows()
                }
                await self.checkContainment(ownIds: own.map(\.id))
            } catch {
                await MainActor.run {
                    self.loggedIn = false
                    self.loginResolved = true
                    Breadcrumbs.log("addtoplaylist.load failed err=\(error)")
                    self.rebuildRows()
                }
            }
        }
    }

    /// 已包含预判：逐个拉歌单详情比对 trackIds（详情走
    /// LocalServer GET 缓存，重复打开弹层基本命中缓存）。
    /// 上限 40 个，超出保持 nil（未预判）。
    private func checkContainment(ownIds: [String]) async {
        for playlistId in ownIds.prefix(40) {
            guard let detail = try? await NativeDataClient.shared.fetchPlaylistDetail(id: playlistId)
            else { continue }
            let contains = detail.trackIds.contains(rawTrackId)
            await MainActor.run {
                guard let index = self.remoteOwn.firstIndex(where: { $0.summary.id == playlistId })
                else { return }
                self.remoteOwn[index].contains = contains
                self.rebuildRows()
            }
        }
    }

    // MARK: - 表格

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AddToPlaylistCell.reuseId, for: indexPath) as! AddToPlaylistCell
        switch rows[indexPath.row] {
        case .liked(let already):
            cell.configure(
                symbol: "heart.fill", symbolColor: .systemPink,
                title: "我喜欢的音乐",
                subtitle: already ? "已喜欢" : "点按加入喜欢",
                badge: already ? "已包含" : nil,
                enabled: true, busy: false)
        case .remote(let summary, let contains):
            cell.configure(
                coverRaw: summary.coverUrl,
                title: summary.name,
                subtitle: "\(summary.trackCount) 首",
                badge: contains == true ? "已包含" : nil,
                enabled: busyPlaylistId == nil,
                busy: busyPlaylistId == summary.id)
        case .remoteForeign(let summary):
            cell.configure(
                coverRaw: summary.coverUrl,
                title: summary.name,
                subtitle: "\(summary.trackCount) 首 · 收藏的歌单不可加曲",
                badge: nil, enabled: false, busy: false)
        case .remoteLoginHint:
            cell.configure(
                symbol: "person.crop.circle.badge.exclamationmark", symbolColor: .secondaryLabel,
                title: "云端歌单",
                subtitle: "登录网易云后，这里会显示你的歌单",
                badge: nil, enabled: false, busy: false)
        case .remoteUnsupportedHint:
            cell.configure(
                symbol: "exclamationmark.circle", symbolColor: .secondaryLabel,
                title: "云端歌单",
                subtitle: "仅网易云歌曲可加入网易云歌单",
                badge: nil, enabled: false, busy: false)
        case .local(let playlist, let contains):
            cell.configure(
                coverRaw: playlist.tracks.first?.artworkURL?.absoluteString,
                title: playlist.name,
                subtitle: "\(playlist.tracks.count) 首 · 本机歌单",
                badge: contains ? "已包含" : nil,
                enabled: true, busy: false)
        case .createLocal:
            cell.configure(
                symbol: "plus.circle.fill", symbolColor: .label,
                title: "新建本机歌单",
                subtitle: "建一个新歌单并加入这首歌",
                badge: nil, enabled: true, busy: false)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .liked(let already):
            likedTapped(already: already)
        case .remote(let summary, let contains):
            remoteTapped(summary: summary, contains: contains)
        case .remoteForeign:
            NativePlaybackFailureToast.show(message: "收藏的歌单不能加曲，只能加入自己创建的歌单")
        case .remoteLoginHint, .remoteUnsupportedHint:
            break
        case .local(let playlist, let contains):
            if contains {
                NativePlaybackFailureToast.show(message: "这首歌已经在「\(playlist.name)」里了")
            } else if LocalPlaylistStore.shared.addTrack(track, toPlaylist: playlist.id) {
                Breadcrumbs.log("addtoplaylist.local.add id=\(playlist.id) track=\(track.id)")
                NativePlaybackFailureToast.show(message: "已加入「\(playlist.name)」")
                rebuildRows()
            } else {
                Breadcrumbs.log("addtoplaylist.local.addFail id=\(playlist.id)")
                NativePlaybackFailureToast.show(message: "加入「\(playlist.name)」失败")
            }
        case .createLocal:
            createLocalTapped()
        }
    }

    // MARK: - 写入动作

    /// 喜欢行：本地真源先行；已登录且网易云曲目再同步云端
    /// 红心，失败回滚（与点播台喜欢钮同口径）。未登录只落
    /// 本机并如实 toast，不假报云端成功。
    private func likedTapped(already: Bool) {
        guard !already else {
            Breadcrumbs.log("addtoplaylist.like dup track=\(track.id)")
            NativePlaybackFailureToast.show(message: "已经在「我喜欢的音乐」里了")
            return
        }
        let newState = LikesStore.shared.toggle(track.id)
        Breadcrumbs.log("addtoplaylist.like track=\(track.id) on=\(newState)")
        rebuildRows()
        guard isNeteaseTrack, loggedIn else {
            NativePlaybackFailureToast.show(message: "已加入「我喜欢的音乐」（本机）")
            dismiss(animated: true)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await NativeDataClient.shared.setLike(trackId: track.id, like: newState)
                Breadcrumbs.log("addtoplaylist.like.remote ok track=\(track.id)")
                await MainActor.run {
                    NativePlaybackFailureToast.show(message: "已加入「我喜欢的音乐」")
                    self.dismiss(animated: true)
                }
            } catch {
                LikesStore.shared.toggle(track.id)
                Breadcrumbs.log("addtoplaylist.like.remote fail track=\(track.id) err=\(error)")
                await MainActor.run {
                    self.rebuildRows()
                    NativePlaybackFailureToast.show(message: "云端喜欢同步失败，请稍后重试")
                }
            }
        }
    }

    /// 云端歌单加曲：GET /api/netease/playlist/tracks
    /// （op=add），getJSON 业务码 !=200 即抛错，成功才报成功。
    private func remoteTapped(summary: NativePlaylistSummary, contains: Bool?) {
        guard busyPlaylistId == nil else { return }
        guard contains != true else {
            Breadcrumbs.log("addtoplaylist.remote dup pid=\(summary.id)")
            NativePlaybackFailureToast.show(message: "这首歌已经在「\(summary.name)」里了")
            return
        }
        busyPlaylistId = summary.id
        rebuildRows()
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await NativeDataClient.shared.getJSON(
                    "/api/netease/playlist/tracks",
                    query: [
                        "op": "add",
                        "pid": summary.id,
                        "tracks": rawTrackId,
                        "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
                    ])
                Breadcrumbs.log("addtoplaylist.remote.ok pid=\(summary.id) track=\(track.id)")
                await MainActor.run {
                    self.busyPlaylistId = nil
                    if let index = self.remoteOwn.firstIndex(where: { $0.summary.id == summary.id }) {
                        self.remoteOwn[index].contains = true
                    }
                    self.rebuildRows()
                    NativePlaybackFailureToast.show(message: "已加入「\(summary.name)」")
                    self.dismiss(animated: true)
                }
            } catch {
                Breadcrumbs.log("addtoplaylist.remote.fail pid=\(summary.id) err=\(error)")
                await MainActor.run {
                    self.busyPlaylistId = nil
                    self.rebuildRows()
                    if case NativeDataClient.DataError.notLoggedIn = error {
                        NativePlaybackFailureToast.show(message: "登录状态已失效，请重新登录后再试")
                    } else {
                        NativePlaybackFailureToast.show(message: "加入歌单失败，请稍后重试")
                    }
                }
            }
        }
    }

    /// 新建本机歌单：LocalPlaylistStore.saveQueue 是本机侧
    /// 唯一真写口（整队命名新建），以当前歌曲单曲成单。
    private func createLocalTapped() {
        let alert = UIAlertController(title: "新建本机歌单", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "歌单名称"
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "创建并加入", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = alert?.textFields?.first?.text ?? ""
            guard let playlist = LocalPlaylistStore.shared.saveQueue(named: name, tracks: [track]) else {
                NativePlaybackFailureToast.show(message: "歌单名不能为空")
                return
            }
            Breadcrumbs.log("addtoplaylist.local.create name=\(playlist.name) track=\(track.id)")
            NativePlaybackFailureToast.show(message: "已新建「\(playlist.name)」并加入")
            self.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: - 搜索

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        rebuildRows()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - 弹层行（封面 44 + 两行文字 + 右侧标记，整行高 60）

private final class AddToPlaylistCell: UITableViewCell {
    static let reuseId = "AddToPlaylistCell"

    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badgeLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var representedKey = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 6
        coverView.backgroundColor = .secondarySystemFill
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        badgeLabel.textColor = .secondaryLabel
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 3
        for item in [coverView, labels, badgeLabel, spinner] {
            item.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(item)
        }
        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 44),
            coverView.heightAnchor.constraint(equalToConstant: 44),
            labels.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            badgeLabel.leadingAnchor.constraint(equalTo: labels.trailingAnchor, constant: 8),
            badgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            badgeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedKey = ""
        coverView.image = nil
        spinner.stopAnimating()
    }

    /// 封面图行（云端/本机歌单）。
    func configure(coverRaw: String?, title: String, subtitle: String,
                   badge: String?, enabled: Bool, busy: Bool) {
        representedKey = title + "|" + (coverRaw ?? "")
        coverView.image = nil
        coverView.tintColor = nil
        coverView.contentMode = .scaleAspectFill
        let key = representedKey
        WorkbenchCover.load(raw: coverRaw, into: coverView) { [weak self] in
            self?.representedKey == key
        }
        apply(title: title, subtitle: subtitle, badge: badge, enabled: enabled, busy: busy)
    }

    /// 符号图行（喜欢/新建/提示行）：符号画进封面位。
    func configure(symbol: String, symbolColor: UIColor, title: String, subtitle: String,
                   badge: String?, enabled: Bool, busy: Bool) {
        representedKey = title
        coverView.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        coverView.tintColor = symbolColor
        coverView.contentMode = .center
        apply(title: title, subtitle: subtitle, badge: badge, enabled: enabled, busy: busy)
    }

    private func apply(title: String, subtitle: String, badge: String?,
                       enabled: Bool, busy: Bool) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        badgeLabel.text = badge
        badgeLabel.isHidden = badge == nil || busy
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
        contentView.alpha = enabled ? 1 : 0.45
        selectionStyle = enabled ? .default : .none
        accessoryType = .none
    }
}
