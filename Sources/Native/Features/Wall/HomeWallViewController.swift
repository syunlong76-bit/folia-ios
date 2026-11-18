import UIKit

/// M1 阶段 4：Bravais 主页墙（用户歌单墙）原生表面。
/// 几何与取项：实色外观档 reservedPerBlock=0，StartTile 的无限拼贴
/// 在 k=0 时与 WallLayout 的单元序列完全一致（周期几何同源、within
/// 即 slotIndex），故直接复用已真机验证的 WallLayout + WallPosterCell，
/// wrapOffset=0（无起点 slot 时网页侧同为 0）。
/// 条目 = 登录用户的歌单（创建 + 收藏，接口顺序即网页侧卡片顺序）；
/// 特殊卡（喜欢/云盘/FM 等按 LIBRARY_HOME_SPECIAL_ORDER 的投影）
/// 与专辑/电台页签留待后续增量，本步先立歌单墙本体。
/// 点按歌单 → 打开该歌单的曲目墙（详情 MVP 落地后改走协调器交接）。
/// 相机折叠逻辑与 WallPrototypeViewController 同构（有意重复：
/// 两处都已验证的手势路径不做抽象合并，协调器接线时再抽共享基类）。
final class HomeWallViewController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching {

    private var entries: [WallPrototypeViewController.Entry] = []
    private var playlistIds: [String] = []
    private let wallLayout = WallLayout()
    private var collectionView: UICollectionView!
    private var statusLabel: UILabel!
    /// 电影长卷入场（3.7 (12)）：数据在途时盖住空墙，数据到即退场。
    private var filmStrip: FilmStripView?
    private var didCenterCamera = false
    private var isWrapping = false
    /// 加载失败重试（3.7 (13) #3）：自动重试一次，之后点按重试。
    private var loadAttempts = 0
    private var loadFailed = false
    /// 电影长卷每次启动只播一次（3.7 (13)）：重进主页墙不重播。
    private static var filmStripPlayedThisLaunch = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: wallLayout)
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.register(WallPosterCell.self, forCellWithReuseIdentifier: WallPosterCell.reuseId)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // 电影长卷：盖在空墙上、垫在胶囊/关闭键下（后加的在上层）。
        let strip = FilmStripView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: view.topAnchor),
            strip.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        filmStrip = strip

        statusLabel = UILabel()
        statusLabel.text = "主页墙加载中…"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isUserInteractionEnabled = true
        statusLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(statusTapped)))
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            statusLabel.heightAnchor.constraint(equalToConstant: 26)
        ])

        let close = UIButton(type: .system)
        close.setTitle("关闭", for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        close.layer.cornerRadius = 13
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            close.widthAnchor.constraint(equalToConstant: 56),
            close.heightAnchor.constraint(equalToConstant: 26)
        ])

        loadEntries()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    /// 失败态点按状态胶囊：重置计数重新加载（3.7 (13) #3）。
    @objc private func statusTapped() {
        guard loadFailed else { return }
        loadFailed = false
        loadAttempts = 0
        statusLabel.text = "主页墙加载中…"
        loadEntries()
    }

    /// 本实例是否正在播长卷（3.7 (13.1) 黑屏修复，DS32 裁定 (a)）：
    /// (13) 用启动级静态标记判 finish，viewDidAppear 二次触发时把
    /// 还在播的长卷误关、留下数秒纯黑。finish 从此只由本实例的
    /// 加载落定驱动，appear 只记账。
    private var stripPlayingHere = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Breadcrumbs.log("home appear")
        Breadcrumbs.samplerStart()
        // 数据还没到才播长卷；先到（缓存快路径）则整段跳过。
        // 每次启动只播一次：重进主页墙直接见墙（3.7 (13)）。
        if entries.isEmpty, !Self.filmStripPlayedThisLaunch {
            Self.filmStripPlayedThisLaunch = true
            stripPlayingHere = true
            filmStrip?.play()
        } else if entries.isEmpty, !stripPlayingHere {
            // 本实例没播过（重进的新实例）：撤掉静止卷面直接见墙。
            filmStrip?.finish("reentry")
        }
        // 本实例正在播且仍在加载：什么都不做，等加载落定 finish。
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Breadcrumbs.samplerStop()
        Breadcrumbs.log("home disappear")
    }

    // MARK: - 数据

    private func loadEntries() {
        loadAttempts += 1
        Task { [weak self] in
            guard let self else { return }
            do {
                // 先从 WebView 重读最新会话（用户可能刚扫码登录），
                // 再探登录态——3.7 (4) 的误判就出在这里。
                await NativeDataClient.shared.refreshWebSession()
                let status = try await NativeDataClient.shared.fetchLoginStatus()
                guard status.loggedIn, let userId = status.userId else {
                    await MainActor.run {
                        self.statusLabel.text = "主页墙：未登录（先在网页侧登录网易云）"
                        self.filmStrip?.finish("not-logged-in")
                    }
                    return
                }
                let playlists = try await NativeDataClient.shared.fetchUserPlaylists(userId: userId)
                await MainActor.run {
                    self.loadAttempts = 0
                    self.loadFailed = false
                    Breadcrumbs.log("home entries ok n=\(playlists.count)")
                    self.playlistIds = playlists.map(\.id)
                    self.entries = playlists.map { playlist in
                        WallPrototypeViewController.Entry(
                            id: playlist.id,
                            title: playlist.name,
                            picUrl: playlist.coverUrl,
                            subtitle: "歌单 · \(playlist.trackCount)")
                    }
                    self.wallLayout.totalEntries = self.entries.count
                    self.statusLabel.text = "主页墙：\(self.entries.count) 个歌单 · 拖动平移 · 点按打开"
                    self.wallLayout.refreshInstances()
                    self.collectionView.reloadData()
                    self.centerCameraIfNeeded()
                    self.filmStrip?.finish("load-ok")
                }
            } catch {
                // 原始错误只进日志，标签只给人话（3.7 (13) #3：根因是
                // 把 Error 整段插值上屏）；自动重试一次，之后点按重试。
                await MainActor.run {
                    FoliaBridgeLogStore.shared.write(
                        level: "error", module: "wall",
                        message: "home load failed attempt=\(self.loadAttempts): \(error)")
                    Breadcrumbs.log("home load failed attempt=\(self.loadAttempts)")
                    if self.loadAttempts < 2 {
                        // 首次失败不是落定：长卷继续播着等重试（13.1）。
                        self.statusLabel.text = "主页墙加载失败，正在重试…"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                            self?.loadEntries()
                        }
                    } else {
                        self.loadFailed = true
                        self.statusLabel.text = "主页墙加载失败，点按这里重试"
                        self.filmStrip?.finish("load-failed")
                    }
                }
            }
        }
    }

    // MARK: - 相机（与原型同构的增量折叠）

    private func centerCameraIfNeeded() {
        guard !didCenterCamera, wallLayout.totalEntries > 0 else { return }
        didCenterCamera = true
        wallLayout.cameraScale = WallPrototypeViewController.cameraScale(
            forWidth: collectionView.bounds.width)
        let cell = wallLayout.cellViewSize
        collectionView.contentOffset = CGPoint(x: cell.width, y: cell.height)
        wallLayout.invalidateLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        centerCameraIfNeeded()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isWrapping, didCenterCamera else { return }
        let cell = wallLayout.cellViewSize
        guard cell.width > 0, cell.height > 0 else { return }
        let center = CGPoint(x: cell.width, y: cell.height)
        let delta = CGPoint(
            x: scrollView.contentOffset.x - center.x,
            y: scrollView.contentOffset.y - center.y)
        guard delta.x != 0 || delta.y != 0 else { return }
        isWrapping = true
        let before = setIdentity()
        wallLayout.worldOrigin = CGPoint(
            x: wallLayout.worldOrigin.x + delta.x / CGFloat(wallLayout.cameraScale),
            y: wallLayout.worldOrigin.y + delta.y / CGFloat(wallLayout.cameraScale))
        scrollView.contentOffset = center
        wallLayout.refreshInstances()
        if setIdentity() != before {
            collectionView.reloadData()
        }
        isWrapping = false
    }

    private func setIdentity() -> String {
        let list = wallLayout.instances
        return "\(list.first?.instanceId ?? "-")/\(list.last?.instanceId ?? "-")/\(list.count)"
    }

    // MARK: - 数据源

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        wallLayout.instances.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WallPosterCell.reuseId, for: indexPath) as! WallPosterCell
        let instance = wallLayout.instances[indexPath.item]
        let entry = entries[instance.queueIndex]
        let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
        let pixelExtent = Double(max(frame.width, frame.height)) * Double(UIScreen.main.scale)
        let tier = entry.picUrl.map { NativeCoverLoader.wallTier(raw: $0, pixelExtent: pixelExtent) }
            ?? NativeCoverLoader.tier(forPixelExtent: pixelExtent)
        cell.configure(entry: entry, tier: tier)
        cell.playEntranceIfNeeded(key: entry.id)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard indexPath.item < wallLayout.instances.count else { continue }
            let instance = wallLayout.instances[indexPath.item]
            guard instance.queueIndex < entries.count else { continue }
            let entry = entries[instance.queueIndex]
            guard let pic = entry.picUrl else { continue }
            let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
            let pixelExtent = Double(max(frame.width, frame.height)) * Double(UIScreen.main.scale)
            let tier = NativeCoverLoader.wallTier(raw: pic, pixelExtent: pixelExtent)
            guard let urlString = NativeCoverLoader.shared.proxiedURLString(pic, tier: tier) else { continue }
            if NativeCoverLoader.shared.cachedImage(for: urlString) != nil { continue }
            Task { _ = await NativeCoverLoader.shared.image(for: urlString, tier: tier) }
        }
    }

    // MARK: - 点按：打开该歌单的曲目墙（详情 MVP 前的桥）

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let instance = wallLayout.instances[indexPath.item]
        guard instance.queueIndex < playlistIds.count else { return }
        let entry = entries[instance.queueIndex]
        let wall = WallPrototypeViewController(
            playlistId: playlistIds[instance.queueIndex],
            title: entry.title, coverUrl: entry.picUrl)
        wall.modalPresentationStyle = .fullScreen
        wall.modalTransitionStyle = .crossDissolve
        // 丝滑切入（3.7 (8)）：先预加载，最多等 250ms 让首批数据
        // 落地再 present——预热命中时墙带着内容直接切入，黑屏不
        // 出现；超时照常切入，由墙内氛围底兜住剩余等待。
        wall.startPreload()
        Task { [weak self] in
            _ = await wall.awaitSeed(timeout: 0.25)
            self?.present(wall, animated: true)
        }
    }

    /// 回程恢复（3.7 (13) #6）：播放页关闭后由 MainViewController
    /// 重呈主页墙时调用，按票直达原歌单曲目墙并恢复上下文。
    func presentRestoredWall(ticket: WallReturnTicket) {
        let wall = WallPrototypeViewController(
            playlistId: ticket.playlistId,
            title: ticket.title, coverUrl: ticket.coverUrl)
        wall.modalPresentationStyle = .fullScreen
        wall.modalTransitionStyle = .crossDissolve
        wall.pendingReturnTicket = ticket
        wall.startPreload()
        Task { [weak self] in
            _ = await wall.awaitSeed(timeout: 0.25)
            self?.present(wall, animated: true)
        }
    }
}
