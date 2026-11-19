import Combine
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
    /// 入场视频槽位（3.7 (17)，替换 (12) 的电影长卷）：数据在途
    /// 时由 EntryIntroPresenter 以横屏 modal 呈现 v5 油画视频；
    /// 每进程只播一次的守卫在 Presenter 内（与 (13) 长卷的启动级
    /// 守卫同语义、随槽迁移）。退出条件（3.7 (18) 定版）：只认
    /// 关闭按钮与自然播完，数据落定不再触发退场——(17) 把
    /// load-ok / load-failed / not-logged-in 三路落定接到
    /// finishCurrent 的接线已全部拆除。
    private var didCenterCamera = false
    private var isWrapping = false
    /// 加载失败重试（3.7 (13) #3）：自动重试一次，之后点按重试。
    private var loadAttempts = 0
    private var loadFailed = false

    // 底部播放台（3.7 (13.4) #4，Miller 点名）：与曲目墙同款
    // E 液态玻璃台（构造同构、按仓库惯例有意重复）；差异是主页
    // 没有定位语义——封面与台身都进播放页，回程存主页票。
    private var miniBar: UIView?
    private var miniCover: UIImageView!
    private var miniTitle: UILabel!
    private var miniArtist: UILabel!
    private var miniPlayButton: UIButton!
    private var miniPrevButton: UIButton!
    private var miniNextButton: UIButton!
    private var miniProgressTrack: UIView!
    private var miniProgressFill: UIView!
    private var miniProgressKnob: UIView!
    private var miniKnobLeading: NSLayoutConstraint?
    private var miniSeekHit: UIView!
    private var miniSeekDragging = false
    private var playbackCancellables = Set<AnyCancellable>()
    private let progressDriver = StageProgressDriver()
    /// 台内主题层（13.5 定版形态，与曲目墙同构装配）：画与
    /// 动画收进台内，替代 13.4 被否的台上方主题带；长按台身
    /// 循环切换、UserDefaults 持久化（见 MiniPlayerTheme）。
    private var miniThemeLayer: MiniPlayerThemeLayer?
    private var miniTheme: MiniPlayerTheme = MiniPlayerTheme.effective
    private var miniKnobSkin: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        // 播放台特效总开关/主题变更（设置页）即时同步。
        NotificationCenter.default.addObserver(
            self, selector: #selector(miniPlayerThemeSettingsChanged),
            name: .foliaMiniPlayerThemeChanged, object: nil)

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

        // 播放态同步：切歌/播停时刷新台面内容（与曲目墙同构）。
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMiniBar() }
            .store(in: &playbackCancellables)
        PlaybackEngine.shared.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMiniBar() }
            .store(in: &playbackCancellables)

        buildMiniBar()
        progressDriver.onFraction = { [weak self] fraction in
            guard let self else { return }
            guard let bar = self.miniBar, !bar.isHidden,
                  !self.miniSeekDragging else { return }
            self.setMiniProgress(fraction)
        }

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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Breadcrumbs.log("home appear")
        Breadcrumbs.samplerStart()
        progressDriver.start()
        miniThemeLayer?.setHostVisible(true)
        refreshMiniBar()
        // 入场视频（3.7 (17)）：数据还没到才触发；先到（缓存快
        // 路径）则整段跳过。每进程只播一次、重进不重播由
        // EntryIntroPresenter 的静态守卫保证——本方法在入场退场
        // 后会被再次调用（墙重新露面），守卫挡住双播；退场只由
        // 关闭按钮/自然播完/视频自身失败与看门狗驱动（3.7 (18)），
        // appear 与数据落定都不做任何关闭动作（(13.1) 长卷误关
        // 黑屏的教训）。
        if entries.isEmpty {
            EntryIntroPresenter.presentIfNeeded(from: self)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Breadcrumbs.samplerStop()
        progressDriver.stop()
        miniThemeLayer?.setHostVisible(false)
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
                        // 首次失败先自动重试；加载失败（含最终失败）
                        // 不触发入场退场，视频继续播到关闭/播完（3.7 (18)）。
                        self.statusLabel.text = "主页墙加载失败，正在重试…"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                            self?.loadEntries()
                        }
                    } else {
                        self.loadFailed = true
                        self.statusLabel.text = "主页墙加载失败，点按这里重试"
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

    // MARK: - 底部播放台（13.4 #4：与曲目墙同款 E 液态玻璃）

    private func buildMiniBar() {
        let bar = UIView()
        bar.backgroundColor = .clear
        bar.layer.cornerRadius = 35
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOpacity = 0.25
        bar.layer.shadowRadius = 20
        bar.layer.shadowOffset = CGSize(width: 0, height: 8)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        view.addSubview(bar)
        miniBar = bar

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.layer.cornerRadius = 35
        blur.layer.borderWidth = 1
        blur.layer.borderColor = UIColor.white.withAlphaComponent(0.30).cgColor
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(blur)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            blur.topAnchor.constraint(equalTo: bar.topAnchor),
            blur.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        // 台内主题层（13.5）：垫在玻璃材质之上、高光/文字/
        // 按钮之下，全幅圆角裁切；整层不拦手势。
        let themeLayer = MiniPlayerThemeLayer()
        themeLayer.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(themeLayer)
        miniThemeLayer = themeLayer
        NSLayoutConstraint.activate([
            themeLayer.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            themeLayer.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            themeLayer.topAnchor.constraint(equalTo: bar.topAnchor),
            themeLayer.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        let rimLight = UIView()
        rimLight.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        rimLight.layer.cornerRadius = 0.5
        rimLight.isUserInteractionEnabled = false
        rimLight.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(rimLight)
        let glassTint = UIView()
        glassTint.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        glassTint.layer.cornerRadius = 35
        glassTint.isUserInteractionEnabled = false
        glassTint.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(glassTint)
        NSLayoutConstraint.activate([
            rimLight.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 30),
            rimLight.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -30),
            rimLight.topAnchor.constraint(equalTo: bar.topAnchor, constant: 1),
            rimLight.heightAnchor.constraint(equalToConstant: 1),
            glassTint.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            glassTint.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            glassTint.topAnchor.constraint(equalTo: bar.topAnchor),
            glassTint.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        let progressTrack = UIView()
        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        progressTrack.layer.cornerRadius = 2
        progressTrack.clipsToBounds = true
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(progressTrack)
        miniProgressTrack = progressTrack
        let fill = UIView()
        fill.backgroundColor = .white
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressTrack.addSubview(fill)
        miniProgressFill = fill

        let knob = UIView()
        knob.backgroundColor = .white
        knob.layer.cornerRadius = 4.5
        knob.layer.shadowColor = UIColor.white.cgColor
        knob.layer.shadowOpacity = 0.9
        knob.layer.shadowRadius = 4
        knob.layer.shadowOffset = .zero
        knob.isUserInteractionEnabled = false
        knob.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(knob)
        miniProgressKnob = knob

        miniCover = UIImageView()
        miniCover.contentMode = .scaleAspectFill
        miniCover.clipsToBounds = true
        miniCover.layer.cornerRadius = 22
        miniCover.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        miniCover.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniCover)

        miniTitle = UILabel()
        miniTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        miniTitle.textColor = .white
        miniTitle.lineBreakMode = .byTruncatingTail
        miniTitle.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniTitle)

        miniArtist = UILabel()
        miniArtist.font = .systemFont(ofSize: 12)
        miniArtist.textColor = UIColor.white.withAlphaComponent(0.6)
        miniArtist.lineBreakMode = .byTruncatingTail
        miniArtist.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniArtist)

        miniPlayButton = UIButton(type: .system)
        miniPlayButton.tintColor = .white
        miniPlayButton.setImage(UIImage(systemName: "play.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)), for: .normal)
        miniPlayButton.translatesAutoresizingMaskIntoConstraints = false
        miniPlayButton.addTarget(self, action: #selector(miniPlayTapped), for: .touchUpInside)
        bar.addSubview(miniPlayButton)

        miniPrevButton = UIButton(type: .system)
        miniPrevButton.tintColor = .white
        miniPrevButton.setImage(UIImage(systemName: "backward.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        miniPrevButton.translatesAutoresizingMaskIntoConstraints = false
        miniPrevButton.addTarget(self, action: #selector(miniPrevTapped), for: .touchUpInside)
        bar.addSubview(miniPrevButton)

        miniNextButton = UIButton(type: .system)
        miniNextButton.tintColor = .white
        miniNextButton.setImage(UIImage(systemName: "forward.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        miniNextButton.translatesAutoresizingMaskIntoConstraints = false
        miniNextButton.addTarget(self, action: #selector(miniNextTapped), for: .touchUpInside)
        bar.addSubview(miniNextButton)

        let seekHit = UIView()
        seekHit.backgroundColor = .clear
        seekHit.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(seekHit)
        miniSeekHit = seekHit
        let seekPan = UIPanGestureRecognizer(target: self, action: #selector(miniSeekPanned(_:)))
        seekHit.addGestureRecognizer(seekPan)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            bar.heightAnchor.constraint(equalToConstant: 70),

            progressTrack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            progressTrack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
            progressTrack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -7),
            progressTrack.heightAnchor.constraint(equalToConstant: 4),
            fill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            fill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            fill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor),

            knob.centerYAnchor.constraint(equalTo: progressTrack.centerYAnchor),
            knob.widthAnchor.constraint(equalToConstant: 9),
            knob.heightAnchor.constraint(equalToConstant: 9),

            miniCover.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            miniCover.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            miniCover.widthAnchor.constraint(equalToConstant: 44),
            miniCover.heightAnchor.constraint(equalToConstant: 44),

            miniTitle.leadingAnchor.constraint(equalTo: miniCover.trailingAnchor, constant: 12),
            miniTitle.trailingAnchor.constraint(equalTo: miniPrevButton.leadingAnchor, constant: -6),
            miniTitle.topAnchor.constraint(equalTo: bar.topAnchor, constant: 13),

            miniArtist.leadingAnchor.constraint(equalTo: miniTitle.leadingAnchor),
            miniArtist.trailingAnchor.constraint(equalTo: miniTitle.trailingAnchor),
            miniArtist.topAnchor.constraint(equalTo: miniTitle.bottomAnchor, constant: 2),

            miniNextButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            miniNextButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            miniNextButton.widthAnchor.constraint(equalToConstant: 34),
            miniNextButton.heightAnchor.constraint(equalToConstant: 40),

            miniPlayButton.trailingAnchor.constraint(equalTo: miniNextButton.leadingAnchor, constant: -2),
            miniPlayButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            miniPlayButton.widthAnchor.constraint(equalToConstant: 40),
            miniPlayButton.heightAnchor.constraint(equalToConstant: 40),

            miniPrevButton.trailingAnchor.constraint(equalTo: miniPlayButton.leadingAnchor, constant: -2),
            miniPrevButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            miniPrevButton.widthAnchor.constraint(equalToConstant: 34),
            miniPrevButton.heightAnchor.constraint(equalToConstant: 40),

            miniSeekHit.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            miniSeekHit.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            miniSeekHit.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            miniSeekHit.heightAnchor.constraint(equalToConstant: 20),
        ])
        miniKnobLeading = knob.leadingAnchor.constraint(
            equalTo: progressTrack.leadingAnchor, constant: -4.5)
        miniKnobLeading?.isActive = true
        fill.transform = CGAffineTransform(scaleX: 0, y: 1)

        // 长按切主题（13.5）：tap 须等长按落空才触发（短点按
        // 时触摸抬起即判长按失败，点按进播放页不加可感延迟）；
        // seek 拖动不与长按互斥（长按静止触发时拖动尚未产生
        // 位移，松手至多以长按点 seek 一次，与点按跳点同义）。
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(miniBarLongPressed(_:)))
        longPress.minimumPressDuration = 0.55
        bar.addGestureRecognizer(longPress)
        let tap = UITapGestureRecognizer(target: self, action: #selector(miniBarTapped(_:)))
        tap.require(toFail: longPress)
        bar.addGestureRecognizer(tap)

        applyMiniTheme()
    }

    /// 进度填充与发光圆钮的唯一步进点（与曲目墙同构）：主题
    /// 层的积雪/鲨鳍/流星头位也在此转喂，同源同步。
    private func setMiniProgress(_ fraction: Double) {
        let clamped = CGFloat(min(max(fraction, 0), 1))
        miniProgressFill.transform = CGAffineTransform(scaleX: clamped, y: 1)
        let trackWidth = miniProgressTrack.bounds.width
        if trackWidth > 0 {
            miniKnobLeading?.constant = clamped * trackWidth - 4.5
        }
        miniThemeLayer?.setFraction(Double(clamped))
    }

    /// 主题应用（13.5）：主题层换装 + 圆点皮肤 + 填充色，只
    /// 动视觉，不碰播放/进度/手势分发。
    private func applyMiniTheme() {
        miniThemeLayer?.apply(theme: miniTheme)
        // 圆点皮肤：13pt 贴图居中压在既有 9pt knob 框上（knob
        // 不裁剪、贴图溢出显示，中心仍与轨道头位对齐，原
        // leading 公式 -4.5 不变）。
        miniKnobSkin?.removeFromSuperview()
        miniKnobSkin = nil
        if let skin = MiniPlayerThemeLayer.knobSkinView(for: miniTheme) {
            skin.translatesAutoresizingMaskIntoConstraints = false
            miniProgressKnob.addSubview(skin)
            NSLayoutConstraint.activate([
                skin.centerXAnchor.constraint(equalTo: miniProgressKnob.centerXAnchor),
                skin.centerYAnchor.constraint(equalTo: miniProgressKnob.centerYAnchor),
                skin.widthAnchor.constraint(equalToConstant: 13),
                skin.heightAnchor.constraint(equalToConstant: 13),
            ])
            miniKnobSkin = skin
        }
        let themed = miniTheme != .none
        miniProgressKnob.backgroundColor = themed ? .clear : .white
        miniProgressKnob.layer.shadowOpacity = themed ? 0 : 0.9
        miniProgressFill.backgroundColor = Self.miniFillColor(for: miniTheme)
    }

    private static func miniFillColor(for theme: MiniPlayerTheme) -> UIColor {
        switch theme {
        case .meadow: return UIColor(red: 0.96, green: 0.72, blue: 0.25, alpha: 1)
        case .star: return UIColor(red: 1, green: 0.91, blue: 0.62, alpha: 1)
        default: return .white
        }
    }

    /// 特效总开关/主题变更（设置页开关或另一台长按）后同步。
    @objc private func miniPlayerThemeSettingsChanged() {
        // 生效值没变就不重应用（长按方会自收自己的通知，防
        // 背景图重复解码，13.5 审查低-5）。
        let eff = MiniPlayerTheme.effective
        guard eff != miniTheme else { return }
        miniTheme = eff
        applyMiniTheme()
    }

    /// 长按台身循环切主题（13.5）：按键区长按不切换（与点按
    /// 分发一致，按键只管切歌播停）；切换即落盘，两台下次
    /// 打开同主题。特效总开关关着时停用（设置页一键全关）。
    @objc private func miniBarLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let bar = miniBar,
              MiniPlayerTheme.effectsEnabled else { return }
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point) { return }
        miniTheme = miniTheme.next
        MiniPlayerTheme.stored = miniTheme
        applyMiniTheme()
        NotificationCenter.default.post(name: .foliaMiniPlayerThemeChanged, object: nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func miniPlayTapped() {
        PlaybackEngine.shared.togglePlayPause()
    }

    @objc private func miniPrevTapped() {
        QueueManager.shared.playPrevious()
    }

    @objc private func miniNextTapped() {
        QueueManager.shared.playNext(manual: true)
    }

    /// 台面点按分发（主页版）：按键各自处理；底部进度带 = 点按
    /// 跳点；其余（封面 + 台身）= 进播放详情页——主页没有定位
    /// 语义，Miller 要的就是在主页能进详情页（13.4 #4）。
    @objc private func miniBarTapped(_ gesture: UITapGestureRecognizer) {
        guard let bar = miniBar else { return }
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point) { return }
        // 封面优先于底部进度带（与曲目墙分发序一致）：封面下缘
        // 与 seekHit 带约 2pt 重叠，点封面应开页不跳点。
        if miniCover.frame.contains(point) {
            openNativeStageFromHome()
            return
        }
        if miniSeekHit.frame.contains(point) {
            let track = miniProgressTrack.frame
            let engine = PlaybackEngine.shared
            guard track.width > 0, engine.duration > 0 else { return }
            let fraction = min(max((point.x - track.minX) / track.width, 0), 1)
            setMiniProgress(Double(fraction))
            engine.seek(to: Double(fraction) * engine.duration)
            return
        }
        openNativeStageFromHome()
    }

    /// 进度拖动（与曲目墙同构）：拖动中只更新填充，松手才 seek；
    /// 终结状态先复位拖动标记再走守卫；轨道零宽整体不处理。
    @objc private func miniSeekPanned(_ gesture: UIPanGestureRecognizer) {
        guard miniSeekHit != nil, miniBar != nil else { return }
        let engine = PlaybackEngine.shared
        let barPoint = gesture.location(in: miniBar)
        let track = miniProgressTrack.frame
        guard track.width > 0 else {
            if gesture.state == .ended || gesture.state == .cancelled
                || gesture.state == .failed {
                miniSeekDragging = false
            }
            return
        }
        let fraction = min(max((barPoint.x - track.minX) / track.width, 0), 1)
        switch gesture.state {
        case .began:
            if miniCover.frame.contains(barPoint)
                || miniPlayButton.frame.contains(barPoint)
                || miniPrevButton.frame.contains(barPoint)
                || miniNextButton.frame.contains(barPoint) { return }
            guard engine.duration > 0 else { return }
            miniSeekDragging = true
            setMiniProgress(Double(fraction))
        case .changed:
            guard miniSeekDragging else { return }
            setMiniProgress(Double(fraction))
        case .ended:
            guard miniSeekDragging else { return }
            miniSeekDragging = false
            guard engine.duration > 0 else { return }
            engine.seek(to: Double(fraction) * engine.duration)
        case .cancelled, .failed:
            miniSeekDragging = false
        default:
            break
        }
    }

    /// 播放台内容同步（与曲目墙同构）：有当前曲才显示。
    private func refreshMiniBar() {
        guard let bar = miniBar else { return }
        let engine = PlaybackEngine.shared
        guard let track = engine.currentTrack else {
            bar.isHidden = true
            miniThemeLayer?.setBarVisible(false)
            return
        }
        bar.isHidden = false
        miniThemeLayer?.setBarVisible(true)
        miniTitle.text = track.title
        miniArtist.text = track.artist
        miniPlayButton.setImage(
            UIImage(systemName: engine.playbackState == .playing ? "pause.fill" : "play.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)),
            for: .normal)
        if let art = engine.currentArtwork {
            miniCover.image = art
        } else if let url = track.artworkURL {
            let raw = url.absoluteString
            let tier = NativeCoverLoader.tier(forPixelExtent: 126)
            if let proxied = NativeCoverLoader.shared.proxiedURLString(raw, tier: tier) {
                if let cached = NativeCoverLoader.shared.cachedImage(for: proxied) {
                    miniCover.image = cached
                } else {
                    miniCover.image = nil
                    let trackId = track.id
                    Task { [weak self] in
                        let image = await NativeCoverLoader.shared.image(for: proxied, tier: tier)
                        await MainActor.run {
                            guard let self,
                                  PlaybackEngine.shared.currentTrack?.id == trackId
                            else { return }
                            self.miniCover.image = image
                        }
                    }
                }
            }
        } else {
            miniCover.image = nil
        }
    }

    /// 从主页墙进播放页：存主页票（关页只回主页墙）+ 请前端
    /// 开页 + 收起整摞原生墙（与曲目墙 openStageFromWall 同构）。
    /// 原生舞台入口（3.7 (14)，M2'）：与曲目墙同构——舞台全屏
    /// 盖在主页墙上、关闭即回墙；跳网页舞台时先关原生舞台，
    /// 再走 openStageFromHome 原套（存票+收墙+凭票恢复）。
    private func openNativeStageFromHome() {
        Breadcrumbs.log("stage open (native) from home wall")
        let stage = StageViewController()
        stage.modalPresentationStyle = .fullScreen
        stage.onRequestWebStage = { [weak self] in
            guard let self else { return }
            if self.presentedViewController != nil {
                self.dismiss(animated: false) { [weak self] in
                    self?.openStageFromHome()
                }
            } else {
                self.openStageFromHome()
            }
        }
        present(stage, animated: true)
    }

    private func openStageFromHome() {
        WallReturnTicketStore.pending = WallReturnTicket(
            kind: .home,
            playlistId: "",
            title: nil,
            coverUrl: nil,
            worldOrigin: .zero,
            contentOffset: .zero,
            expandedInstanceId: nil,
            expandedQueueIndex: nil)
        Breadcrumbs.log("stage open from home wall")
        // 13.5 闭环：收墙改由桥在 landed 或 1.2s 截止（先到者）
        // 时回调；等待期锁交互防重复点（回调必到，不会锁死）。
        view.isUserInteractionEnabled = false
        WebEffectBridge.shared.requestOpenStage { [weak self] in
            guard let self else { return }
            var host: UIViewController = self
            while let presenter = host.presentingViewController { host = presenter }
            if host !== self { host.dismiss(animated: true) }
        }
    }
}
