import SwiftUI
import UIKit

// Panels62.swift
//
// 3.7 (62) WC 簇新面集合：
// - ArtistView62：歌手页（§8）——头图/热门歌曲/专辑分区，走
//   NativeDataClient 既有带会话通路打网易云 artist 端点
//   （/artists、/artist/top/song、/artist/album，均经 LocalServer
//   同源代理）。歌手简介字段上游未必给到：拿到才显示，拿不到
//   诚实标注「暂无简介」，不编造。
// - NavidromeBrowser62：Navidrome 歌单/专辑浏览＋点播（引擎
//   直放旁路，见类注）。
// - LivePosterWall62：直播海报墙（§8）——App 内全屏面，队列
//   封面大图轮播＋当前歌信息。与 OBS 页（LocalServer 输出）区分。
// - DafeiyuPanel62：大肥鱼陪伴面板（§8，D14）——机器人信息取
//   仓库 qq-bot 资料真值（小号 3868261380、群 1135730800、
//   主人号 2737140269）；状态文案诚实写「以 QQ 端为准」。

// MARK: - 歌手页

struct ArtistView62: View {
    let collection: ExploreCollection

    @Environment(\.dismiss) private var dismiss
    @State private var hotTracks: [FoliaTrack] = []
    @State private var albums: [ExploreCollection] = []
    @State private var brief: String?
    @State private var phase: String = "loading"

    var body: some View {
        ZStack(alignment: .top) {
            FoliaTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NativeCoverView(url: collection.coverURL, targetPixels: 700)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(collection.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(FoliaTheme.primary)
                    if let brief, !brief.isEmpty {
                        Text(brief)
                            .font(.system(size: 12))
                            .foregroundColor(FoliaTheme.primary.opacity(0.65))
                    } else {
                        Text("歌手简介：上游接口未提供，暂无简介。")
                            .font(.system(size: 12))
                            .foregroundColor(FoliaTheme.primary.opacity(0.4))
                    }
                    if phase == "loading" {
                        ProgressView().tint(FoliaTheme.primary)
                    } else if phase == "failed" {
                        Text("歌手数据加载失败，请稍后重试。")
                            .font(.system(size: 13))
                            .foregroundColor(FoliaTheme.primary.opacity(0.6))
                        Button("重试") { Task { await load() } }
                            .foregroundColor(FoliaTheme.primary)
                    }
                    if !hotTracks.isEmpty {
                        Text("热门歌曲")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(FoliaTheme.primary)
                        ForEach(hotTracks) { track in
                            Button {
                                QueueManager.shared.setQueue(hotTracks, startingAt:
                                    hotTracks.firstIndex(where: { $0.id == track.id }) ?? 0)
                                NativeBrowseView.openFullPlayer()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(FoliaTheme.primary)
                                        Text(track.album)
                                            .font(.system(size: 11))
                                            .foregroundColor(FoliaTheme.primary.opacity(0.5))
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill")
                                        .foregroundColor(FoliaTheme.primary.opacity(0.7))
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !albums.isEmpty {
                        Text("专辑")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(FoliaTheme.primary)
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                HStack(spacing: 12) {
                                    NativeCoverView(url: album.coverURL, targetPixels: 200)
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Text(album.name)
                                        .font(.system(size: 14))
                                        .foregroundColor(FoliaTheme.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .padding(.top, 56)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FoliaTheme.primary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.ultraThinMaterial))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if phase == "loading" { await load() } }
    }

    private func load() async {
        phase = "loading"
        let id = String(collection.id)
        do {
            async let infoTask = NativeDataClient.shared.getJSON(
                "/api/netease/artists", query: ["id": id])
            async let topTask = NativeDataClient.shared.getJSON(
                "/api/netease/artist/top/song", query: ["id": id])
            async let albumTask = NativeDataClient.shared.getJSON(
                "/api/netease/artist/album", query: ["id": id, "limit": "30"])
            let info = try await infoTask
            if let artist = NativeJSON.dict(info["artist"]) {
                brief = NativeJSON.string(artist["briefDesc"])
            }
            if let top = try? await topTask {
                hotTracks = NativeJSON.array(top["songs"]).compactMap(WorkbenchParse.flexibleTrack)
                    .map(workbenchFoliaTrack)
            }
            if let albumRoot = try? await albumTask {
                albums = NativeJSON.array(albumRoot["hotAlbums"]).compactMap { raw in
                    guard let albumId = NativeJSON.string(raw["id"]) else { return nil }
                    return ExploreCollection(
                        kind: .album, id: Int(albumId) ?? 0,
                        name: NativeJSON.string(raw["name"]) ?? "",
                        coverURL: NativeJSON.string(raw["picUrl"]).flatMap { URL(string: $0) },
                        subtitle: "专辑")
                }
            }
            phase = (hotTracks.isEmpty && albums.isEmpty) ? "failed" : "ready"
            Breadcrumbs.log("artist62.load id=\(id) hot=\(hotTracks.count) albums=\(albums.count)")
        } catch {
            phase = "failed"
            Breadcrumbs.log("artist62.load fail id=\(id) err=\(error.localizedDescription)")
        }
    }
}

// MARK: - Navidrome 浏览

/// Navidrome 歌单/专辑浏览与点播。点播走 PlaybackEngine 直放
/// 旁路：QueueManager 的取流分支（WB 簇）没有 Subsonic 通路，
/// setQueue 会按网易云 id 取流必失败；这里以 streamURL 拼装
/// 地址直放单曲并落面包屑标注旁路，队列联动为已知缺口。
final class NavidromeBrowser62ViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate {

    private enum Row {
        case playlist(NavidromePlaylist62)
        case album(NavidromeAlbum62)
        case track(FoliaTrack, all: [FoliaTrack])
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let statusLabel = UILabel()
    private var rows: [Row] = []
    private var mode: String = "root"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        overrideUserInterfaceStyle = .dark
        title = "Navidrome"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "navi62")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
        loadRoot()
    }

    static func present(from presenter: UIViewController) {
        let browser = NavidromeBrowser62ViewController()
        let nav = UINavigationController(rootViewController: browser)
        nav.modalPresentationStyle = .pageSheet
        presenter.present(nav, animated: true)
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    private func loadRoot() {
        mode = "root"
        statusLabel.text = "加载中…"
        Task { @MainActor in
            do {
                async let playlistsTask = NavidromeClient62.shared.fetchPlaylists()
                async let albumsTask = NavidromeClient62.shared.fetchAlbumList()
                let playlists = try await playlistsTask
                let albums = try await albumsTask
                self.rows = playlists.map(Row.playlist) + albums.map(Row.album)
                self.statusLabel.text = self.rows.isEmpty ? "服务器上暂无歌单/专辑" : nil
                self.tableView.reloadData()
                Breadcrumbs.log("navidrome62.browse root rows=\(self.rows.count)")
            } catch {
                self.statusLabel.text = "加载失败：\(error.localizedDescription)"
                Breadcrumbs.log("navidrome62.browse fail err=\(error.localizedDescription)")
            }
        }
    }

    private func loadDirectory(id: String, name: String) {
        mode = "directory"
        title = name
        statusLabel.text = "加载中…"
        Task { @MainActor in
            do {
                let dir = try await NavidromeClient62.shared.fetchDirectory(id: id)
                var built: [Row] = dir.childAlbums.map(Row.album)
                built += dir.childTracks.map { Row.track($0, all: dir.childTracks) }
                self.rows = built
                self.statusLabel.text = built.isEmpty ? "此目录暂无内容" : nil
                self.tableView.reloadData()
            } catch {
                self.statusLabel.text = "加载失败：\(error.localizedDescription)"
            }
        }
    }

    /// 引擎直放旁路（见类注）：streamURL 现拼现放。
    static func playViaEngine(track: FoliaTrack) {
        let rawId = track.id.replacingOccurrences(of: "navi_", with: "")
        guard let url = NavidromeClient62.shared.streamURL(songId: rawId) else {
            NativePlaybackFailureToast.show(message: "Navidrome 未配置，无法播放")
            return
        }
        PlaybackEngine.shared.load(track: track, playableURL: url, artwork: nil)
        Breadcrumbs.log("navidrome62.play bypass id=\(track.id)")
        NativePlaybackFailureToast.show(message: "Navidrome 直放：\(track.title)")
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "navi62", for: indexPath)
        var config = cell.defaultContentConfiguration()
        switch rows[indexPath.row] {
        case .playlist(let playlist):
            config.text = playlist.name
            config.secondaryText = "歌单 · \(playlist.songCount) 首"
            config.image = UIImage(systemName: "music.note.list")
        case .album(let album):
            config.text = album.name
            config.secondaryText = "专辑 · \(album.artist)"
            config.image = UIImage(systemName: "rectangle.stack")
        case .track(let track, _):
            config.text = track.title
            config.secondaryText = "\(track.artist) · \(track.album)"
            config.image = UIImage(systemName: "music.note")
        }
        config.textProperties.color = .white
        config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.5)
        cell.contentConfiguration = config
        cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .playlist(let playlist):
            loadDirectory(id: playlist.id, name: playlist.name)
        case .album(let album):
            loadDirectory(id: album.id, name: album.name)
        case .track(let track, _):
            Self.playViaEngine(track: track)
        }
    }
}

// MARK: - 直播海报墙

/// 全屏海报墙：队列封面大图居中轮播（每 6 秒切下一张队列封面，
/// 系统弹簧交叉淡化）＋当前歌信息。入口：命令面板/帮助说明行。
final class LivePosterWall62ViewController: UIViewController {

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private var timer: Timer?
    private var posterIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        artistLabel.font = .systemFont(ofSize: 16)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        artistLabel.textAlignment = .center
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        view.addSubview(artistLabel)
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关闭", for: .normal)
        closeButton.tintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) },
                              for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            imageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.62),
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        refreshCurrent()
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) {
            [weak self] _ in self?.advancePoster() }
        Breadcrumbs.log("posterwall62.open")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    static func present(from presenter: UIViewController) {
        let wall = LivePosterWall62ViewController()
        wall.modalPresentationStyle = .fullScreen
        presenter.present(wall, animated: true)
    }

    private func refreshCurrent() {
        let track = PlaybackEngine.shared.currentTrack
        titleLabel.text = track?.title ?? "暂无播放"
        artistLabel.text = track?.artist ?? ""
        advancePoster()
    }

    private func advancePoster() {
        let queue = QueueManager.shared.queue
        let posters = queue.compactMap { $0.artworkURL }
        guard !posters.isEmpty else {
            if let artwork = PlaybackEngine.shared.currentArtwork {
                imageView.image = artwork
            }
            return
        }
        posterIndex = (posterIndex + 1) % posters.count
        let raw = posters[posterIndex].absoluteString
        let loader = NativeCoverLoader.shared
        let urlString = loader.proxiedURLString(raw, tier: 1024) ?? raw
        Task { [weak self] in
            let image = await loader.image(for: urlString, tier: 1024)
            guard let self, let image else { return }
            UIView.transition(with: self.imageView, duration: 0.6,
                              options: [.transitionCrossDissolve, .curveEaseInOut]) {
                self.imageView.image = image
            }
        }
        if let track = PlaybackEngine.shared.currentTrack {
            titleLabel.text = track.title
            artistLabel.text = track.artist
        }
    }
}

// MARK: - 大肥鱼陪伴

/// 大肥鱼陪伴面板（外部 QQ 机器人系统，D14）：信息取 qq-bot
/// 资料真值；机器人在线状态以 QQ 端为准，App 内不假装可探活。
final class DafeiyuPanel62ViewController: UIViewController {

    static let botQQ = "3868261380"
    static let groupQQ = "1135730800"
    static let ownerQQ = "2737140269"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        overrideUserInterfaceStyle = .dark
        title = "大肥鱼陪伴"

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        func label(_ text: String, size: CGFloat = 14, dim: Bool = false) -> UILabel {
            let view = UILabel()
            view.text = text
            view.font = .systemFont(ofSize: size)
            view.textColor = dim ? UIColor.white.withAlphaComponent(0.55) : .white
            view.numberOfLines = 0
            return view
        }
        func button(_ title: String, action: @escaping () -> Void) -> UIButton {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.tintColor = .white
            button.backgroundColor = UIColor.white.withAlphaComponent(0.1)
            button.layer.cornerRadius = 12
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            return button
        }

        stack.addArrangedSubview(label("大肥鱼（QQ 机器人）", size: 18))
        stack.addArrangedSubview(label("机器人 QQ：\(Self.botQQ)"))
        stack.addArrangedSubview(label("交流群「大肥鱼GoGoGo!」：\(Self.groupQQ)"))
        stack.addArrangedSubview(label(
            "状态说明：大肥鱼是运行在外部盒子上的 QQ 机器人（NapCat＋AstrBot），"
            + "在线与否以 QQ 端实际状态为准；App 内无法探活，此处不显示假状态。"
            + "盒子休眠/欠费时她会离线，需在盒子侧恢复。", dim: true))
        stack.addArrangedSubview(button("复制机器人 QQ") {
            UIPasteboard.general.string = Self.botQQ
            NativePlaybackFailureToast.show(message: "机器人 QQ 已复制")
            Breadcrumbs.log("dafeiyu62.copy botQQ")
        })
        stack.addArrangedSubview(button("复制群号") {
            UIPasteboard.general.string = Self.groupQQ
            NativePlaybackFailureToast.show(message: "群号已复制")
            Breadcrumbs.log("dafeiyu62.copy groupQQ")
        })
        stack.addArrangedSubview(button("使用说明") { [weak self] in
            let page = SettingsTextPageViewController(
                title: "大肥鱼使用说明",
                text: "在 QQ 里加机器人 \(Self.botQQ) 为好友，或在群「大肥鱼GoGoGo!」"
                    + "（\(Self.groupQQ)）里 @ 她即可聊天。群里只有主人能触发她回复。"
                    + "她由外部盒子供电运行，离线时先确认盒子状态。")
            page.modalPresentationStyle = .overFullScreen
            self?.present(page, animated: true)
        })
        Breadcrumbs.log("dafeiyu62.open")
    }

    static func present(from presenter: UIViewController) {
        let panel = DafeiyuPanel62ViewController()
        let nav = UINavigationController(rootViewController: panel)
        panel.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: panel, action: #selector(closeTapped))
        nav.modalPresentationStyle = .pageSheet
        presenter.present(nav, animated: true)
    }

    @objc private func closeTapped() { dismiss(animated: true) }
}

// MARK: - 桥日志全量查看器（§4.11 升级面）

/// 全量桥日志查看：读 FoliaBridgeLogStore 双轮换文件全量，
/// 分页（每页 300 行，可翻页）＋导出分享（写临时 .log 经系统
/// 分享）。既有 BridgeLogViewController（最近 300 行）保留，
/// 本面由设置 62 簇开发者行与命令入口真达。
final class BridgeLog62ViewController: UIViewController {

    private let textView = UITextView()
    private let pageLabel = UILabel()
    private var allLines: [String] = []
    private var page = 0
    private let pageSize = 300

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)
        title = "运行日志（全量）"

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UILabel()
        titleLabel.text = "运行日志"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        pageLabel.font = .systemFont(ofSize: 12)
        pageLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        let exportButton = UIButton(type: .system)
        exportButton.setTitle("导出", for: .normal)
        exportButton.addAction(UIAction { [weak self] _ in self?.exportTapped() },
                               for: .touchUpInside)
        let prevButton = UIButton(type: .system)
        prevButton.setTitle("上一页", for: .normal)
        prevButton.addAction(UIAction { [weak self] _ in
            guard let self, self.page > 0 else { return }
            self.page -= 1
            self.renderPage()
        }, for: .touchUpInside)
        let nextButton = UIButton(type: .system)
        nextButton.setTitle("下一页", for: .normal)
        nextButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let pages = max(1, Int(ceil(Double(self.allLines.count) / Double(self.pageSize))))
            guard self.page + 1 < pages else { return }
            self.page += 1
            self.renderPage()
        }, for: .touchUpInside)
        let doneButton = UIButton(type: .system)
        doneButton.setTitle("完成", for: .normal)
        doneButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) },
                             for: .touchUpInside)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(pageLabel)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(prevButton)
        header.addArrangedSubview(nextButton)
        header.addArrangedSubview(exportButton)
        header.addArrangedSubview(doneButton)
        view.addSubview(header)

        textView.backgroundColor = .clear
        textView.textColor = UIColor.white.withAlphaComponent(0.85)
        textView.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        textView.isEditable = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])

        let full = FoliaBridgeLogStore.shared.recentLogText(maxLines: 100_000)
        allLines = full.isEmpty ? [] : full.split(separator: "\n").map(String.init)
        page = max(0, Int(ceil(Double(allLines.count) / Double(pageSize))) - 1)
        renderPage()
        Breadcrumbs.log("bridgelog62.open lines=\(allLines.count)")
    }

    private func renderPage() {
        let pages = max(1, Int(ceil(Double(allLines.count) / Double(pageSize))))
        page = min(page, pages - 1)
        let start = page * pageSize
        let slice = allLines[start..<min(start + pageSize, allLines.count)]
        textView.text = slice.isEmpty ? "（暂无日志）" : slice.joined(separator: "\n")
        pageLabel.text = "第 \(page + 1)/\(pages) 页 · 共 \(allLines.count) 行"
        textView.setContentOffset(.zero, animated: false)
    }

    private func exportTapped() {
        let text = allLines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("folia-log-export.log")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(activity, animated: true)
        Breadcrumbs.log("bridgelog62.export lines=\(allLines.count)")
    }

    static func present(from presenter: UIViewController) {
        let viewer = BridgeLog62ViewController()
        viewer.modalPresentationStyle = .overFullScreen
        presenter.present(viewer, animated: true)
    }
}
