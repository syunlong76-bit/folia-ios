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
    /// 入场视频槽位（3.7 (17)，替换 (12) 的电影长卷）：由
    /// EntryIntroPresenter 以横屏 modal 呈现 v5 油画视频。
    /// 触发口径（3.7 (21) 修正，audit-3721 A2）：实例级一次性
    /// ——本实例首次露面才播，同实例后续露面（歌单曲目墙/原生
    /// 舞台等子页 dismiss 返回）不播。判别成立依赖当前拓扑：
    /// 三处顶层进墙点（MainViewController 齿轮入口/舞台回程票/
    /// 回程直达）都是现场新建 HomeWall 实例、无复用，故「实例
    /// 首露面 = 真进墙」严格成立；若将来改成常驻实例（如 tab
    /// 复用），必须改走显式 arm 武装。(20) 曾挂 viewDidAppear
    /// 每次露面触发，进歌单退回也重播，即 Miller 说的「镶嵌
    /// 错了」。动画用途仍是掩盖拉取数据慢（16:12 口径）：新实
    /// 例进墙时数据必然重拉，首露面播满正对需求。退出条件
    /// （3.7 (18) 定版 + (20) 循环掩盖）：只认关闭按钮与自然
    /// 播完，数据先落定不掐断当前播次；每轮播完时数据仍在加载
    /// 则再播一轮，数据已明确失败则退场落到墙的失败态（见
    /// entryDataState）。
    private var didPlayEntryIntro = false
    private var didCenterCamera = false
    /// 入场循环的数据状态答复（3.7 (20)）：loadEntries 各落点
    /// 维护，入场呈现时以闭包快照交给 EntryIntroPresenter（按
    /// 呈现隔离，防并行实例的加载互相污染——(20) 真机出现过
    /// entries 已 ok、入场却以 data-failed 退场）。写侧另有
    /// 代次守卫：只有最新一代 loadEntries 的落点能写本状态，
    /// 旧代在途请求（登录态探测超时等）迟到回写一律作废；
    /// entries 成功即 ready，仅 entries 本身最终失败才 failed。
    private var entryDataState: EntryIntroDataState = .loading {
        // 贴纸层（3.7 (24)，纯新增）：状态变化只驱动贴纸显隐，
        // 不参与任何既有状态机逻辑。方法在文件尾 extension。
        didSet { stickerDataStateChanged() }
    }
    /// loadEntries 代次（每次调用 +1）：异步落点写状态/条目
    /// 前先验代，防旧请求迟到污染新状态。
    private var entryLoadGeneration = 0
    private var isWrapping = false
    /// 加载失败重试（3.7 (13) #3）：自动重试一次，之后点按重试。
    private var loadAttempts = 0
    private var loadFailed = false

    // 贴纸层状态（3.7 (24)，纯新增视图层）：入场跑动（底部
    // dock 内横向跑过）、失败陪衬（居中）、切歌缓冲（迷你台
    // 封面角上方）。视图懒建，方法全在文件尾 extension。
    private var stickerDock: UIView?
    private var stickerRunnerView: StickerView?
    private var stickerLastRunnerWasDog = false
    private var stickerFailureView: StickerView?
    private var stickerFailureReplayTimer: Timer?
    private var stickerBufferView: StickerView?
    private var stickerBufferEpisode = 0
    private var stickerBufferVisible = false

    // 底部播放台（3.7 (13.4) #4，Miller 点名）：与曲目墙同款
    // E 液态玻璃台（构造同构、按仓库惯例有意重复）；差异是主页
    // 没有定位语义——封面与台身都进播放页，回程存主页票。
    private var miniBar: UIView?
    /// 台面毛玻璃层（3.7 (20)）：入场时 effect 从 nil 渐入做
    /// 「显影」联动，须持有引用（原为 buildMiniBar 局部量）。
    private var miniBlurView: UIVisualEffectView?
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
    /// 迷你台尺寸约束（3.7 (21)，与曲目墙同构）：宽度按竖屏
    /// 定版居中（横屏不拉伸，viewDidLayoutSubviews 按
    /// min(宽,高) 更新）、高度在完整/收起两形态间切换。
    private var miniBarWidthConstraint: NSLayoutConstraint?
    private var miniBarHeightConstraint: NSLayoutConstraint?
    private var miniTrackBottomConstraint: NSLayoutConstraint?
    /// 迷你台收起态（3.7 (21)：5 秒无操作自动收成进度条）：
    /// 与 miniBarPresented 分工——后者管在不在场，本标志管
    /// 完整/细条形态。收起形态 (22) 定版：背景全去（主题层/
    /// 毛玻璃/玻璃高光隐藏），只剩轨道+填充+发光圆点步进，
    /// 内容淡出且按钮禁交互。
    private var miniBarCollapsed = false
    private var miniIdleWorkItem: DispatchWorkItem?
    /// 上次 refreshMiniBar 同步的曲目 id：识别切歌（切歌先
    /// 完整形态再起计时）。
    private var miniLastTrackId: String?
    private var playbackCancellables = Set<AnyCancellable>()
    private let progressDriver = StageProgressDriver()
    /// 台内主题层（13.5 定版形态，与曲目墙同构装配）：画与
    /// 动画收进台内，替代 13.4 被否的台上方主题带；长按台身
    /// 循环切换、UserDefaults 持久化（见 MiniPlayerTheme）。
    private var miniThemeLayer: MiniPlayerThemeLayer?
    private var miniTheme: MiniPlayerTheme = MiniPlayerTheme.effective
    private var miniKnobSkin: UIView?
    /// 玻璃高光两件（顶部亮线 + 极淡白罩）：buildMiniBar 建时
    /// 存引用，供收起态去背景时与主题层/毛玻璃一并隐藏
    /// （3.7 (22)，见 setMiniBarForm）。
    private var miniRimLight: UIView?
    private var miniGlassTint: UIView?

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
        // 贴纸层（3.7 (24)，纯新增订阅）：切歌缓冲态驱动缓冲
        // 贴纸显隐，只读引擎状态，不回写。
        PlaybackEngine.shared.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.stickerBufferStateChanged(state) }
            .store(in: &playbackCancellables)

        buildMiniBar()
        // 入场循环的数据状态（3.7 (21)）：不再登记全局静态
        // provider（后建实例会覆盖先建实例的登记，并行加载时
        // 入场读到别家的状态）；改为呈现时由 viewDidAppear 把
        // 本实例的状态闭包快照交给 Presenter，按呈现隔离。
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
        // 入场视频（3.7 (21) 口径，audit-3721 A2）：实例级一次
        // 性——本实例首次露面才触发（= 真进墙，三处顶层进墙点
        // 都是新建实例）；同实例后续露面（子页 dismiss 返回）
        // 不播。Presenter 的抑制标志仍每次消费：它防的是入场
        // 自身退场引发的那次露面与首露面判定打架（同一次进墙
        // 事件的下半程），与实例标志分工不重叠。呈现时把本
        // 实例的数据状态闭包一并快照给 Presenter。
        if EntryIntroPresenter.consumeSuppression() {
            // 入场刚退场引发的露面，不重播（这次露面计入实例
            // 的「已播」：它就是首露面播出的下半程）。
            didPlayEntryIntro = true
        } else if !didPlayEntryIntro {
            // present 受理才置位：资源缺失/呈现中被拒时不烧掉
            // 本实例唯一的一次，留待下次露面重试，不漏播真入口。
            if EntryIntroPresenter.present(from: self, dataState: { [weak self] in
                self?.entryDataState ?? .failed
            }) {
                didPlayEntryIntro = true
            }
        }
        // 方向恢复兜底（3.7 (23)，DS R49 Q6）：入场退场后的
        // 竖屏请求主发点在 dismiss 完成回调（PortraitRestore），
        // 本处是第二次露面的兜底——若彼时界面仍横屏（请求落
        // 空/被打断），在此再发一次（与主发点 0.3s 去重、幂
        // 等，竖屏时无操作）。修 (22) 前横屏卡死等转动的病。
        PortraitRestore.requestIfLandscape(from: self, source: "home-appear")
        // 迷你台无操作计时（3.7 (21)）：回墙即续命（在场且
        // 完整形态才起，resetMiniIdleTimer 内部把关）。
        resetMiniIdleTimer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Breadcrumbs.samplerStop()
        progressDriver.stop()
        // 迷你台无操作计时随墙消失取消（回墙 viewDidAppear 续命）。
        cancelMiniIdleTimer()
        miniThemeLayer?.setHostVisible(false)
        Breadcrumbs.log("home disappear")
    }

    // MARK: - 数据

    private func loadEntries() {
        loadAttempts += 1
        entryDataState = .loading
        // 代次（3.7 (21)）：本次加载的代号；下面每个异步落点
        // 写状态/条目前先验代——旧代请求（尤其登录态探测在
        // 本地服务冷启时可超时数十秒）迟到返回时不得污染新
        // 一代已落定的状态（(20) 真机：entries 已 ok 后入场
        // 仍读到 data-failed）。
        entryLoadGeneration += 1
        let generation = entryLoadGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                // 先从 WebView 重读最新会话（用户可能刚扫码登录），
                // 再探登录态——3.7 (4) 的误判就出在这里。
                await NativeDataClient.shared.refreshWebSession()
                let status = try await NativeDataClient.shared.fetchLoginStatus()
                guard status.loggedIn, let userId = status.userId else {
                    await MainActor.run {
                        guard generation == self.entryLoadGeneration else { return }
                        // 未登录是落定态：入场播完即退场落到此提示，
                        // 不许循环掩盖把用户挡在视频后（3.7 (20)）。
                        self.entryDataState = .failed
                        Breadcrumbs.log("home entry-state failed reason=not-logged-in gen=\(generation)")
                        self.statusLabel.text = "主页墙：未登录（先在网页侧登录网易云）"
                    }
                    return
                }
                let playlists = try await NativeDataClient.shared.fetchUserPlaylists(userId: userId)
                await MainActor.run {
                    guard generation == self.entryLoadGeneration else { return }
                    self.loadAttempts = 0
                    self.loadFailed = false
                    self.entryDataState = .ready
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
                    // 旧代迟到失败：不写状态、不排重试（新一代自理）。
                    guard generation == self.entryLoadGeneration else { return }
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
                        // 最终失败落定：入场播完即退场落到失败态，
                        // 不再循环掩盖（3.7 (20)）。这是 entries
                        // 本身最终失败、且经代次验证的唯一 failed
                        // 落点之一（另一处是未登录落定）。
                        self.entryDataState = .failed
                        Breadcrumbs.log("home entry-state failed reason=load-failed gen=\(generation)")
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
        // 迷你台宽度按竖屏定版（3.7 (21)）：min(宽,高) 即竖屏
        // 布局宽（横屏时宽高互换），减两侧各 12 边距；横竖屏
        // 同一宽度、居中，横屏左右留白。
        let portraitBarWidth = min(view.bounds.width, view.bounds.height) - 24
        if let constraint = miniBarWidthConstraint,
           abs(constraint.constant - portraitBarWidth) > 0.5 {
            constraint.constant = portraitBarWidth
        }
        // 贴纸层（3.7 (24)，纯新增）：dock/失败/缓冲贴纸定位。
        stickerLayoutOverlays()
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
        let bar = MiniBarHitView()
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
        miniBlurView = blur
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
        miniRimLight = rimLight
        let glassTint = UIView()
        glassTint.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        glassTint.layer.cornerRadius = 35
        glassTint.isUserInteractionEnabled = false
        glassTint.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(glassTint)
        miniGlassTint = glassTint
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

        // 宽度按竖屏定版（3.7 (21)）：居中 + 宽度约束存引用，
        // viewDidLayoutSubviews 按 min(宽,高)−24 更新——横屏时
        // 即竖屏布局宽，左右留白，不再拉伸满宽；高度存引用供
        // 收起形态切换（70↔16）。
        miniBarWidthConstraint = bar.widthAnchor.constraint(
            equalToConstant: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) - 24)
        miniBarHeightConstraint = bar.heightAnchor.constraint(equalToConstant: 70)
        miniBarWidthConstraint?.isActive = true
        miniBarHeightConstraint?.isActive = true
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bar.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),

            progressTrack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            progressTrack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
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
        // 轨道底距存引用（3.7 (21)）：收起形态 −7→−6 使轨道
        // 在 16pt 细条内居中（轨道高 4：(16−4)/2=6）。
        miniTrackBottomConstraint = progressTrack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -7)
        miniTrackBottomConstraint?.isActive = true
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
    /// 动视觉，不碰播放/进度/手势分发。皮肤/填充/圆点的最终
    /// 落色经 refreshMiniProgressChrome 按当前形态收口——
    /// 收起态（(22) 去背景）走对比度兜底口径。
    private func applyMiniTheme() {
        miniThemeLayer?.apply(theme: miniTheme)
        refreshMiniProgressChrome()
    }

    /// 进度填充与圆点配色的形态收口（3.7 (22) 立、(23) 修）：
    /// 展开态 = 主题口径（皮肤 + 主题填充色）；收起态背景已
    /// 移除、只留极淡底轨，填充改强色兜底（miniCollapsedFillColor）。
    /// 圆点皮肤 (22) 曾在收起态一并摘掉改白色发光点，Miller
    /// 真机否决（「花海小圆点就是一朵花」）——(23) 恢复：收
    /// 起态与展开态同款挂 knobSkinView，有皮肤时 knob 底色
    /// 转清、关发光阴影；无主题（皮肤为 nil）才用白色发光
    /// 点兜底。主题变更（包括收起态下经设置页变更）与形态
    /// 切换都经此重算（收起态切主题/切歌经 applyMiniTheme /
    /// setMiniBarForm 回到这里重挂皮肤）；进度本身仍由
    /// setMiniProgress 唯一驱动。
    private func refreshMiniProgressChrome() {
        miniKnobSkin?.removeFromSuperview()
        miniKnobSkin = nil
        // 圆点皮肤：13pt 贴图居中压在既有 9pt knob 框上（knob
        // 不裁剪、贴图溢出显示，中心仍与轨道头位对齐，原
        // leading 公式 -4.5 不变）；皮肤层不拦截触摸
        // （knobSkinView 内已置 isUserInteractionEnabled=false）。
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
        let themed = miniKnobSkin != nil
        miniProgressKnob.backgroundColor = themed ? .clear : .white
        miniProgressKnob.layer.shadowOpacity = themed ? 0 : 0.9
        miniProgressFill.backgroundColor = miniBarCollapsed
            ? Self.miniCollapsedFillColor(for: miniTheme)
            : Self.miniFillColor(for: miniTheme)
    }

    /// 收起态填充兜底色：只星空改强金（展开态的淡金在无
    /// 背景时易糊），其余沿用展开态主题填充色。
    private static func miniCollapsedFillColor(for theme: MiniPlayerTheme) -> UIColor {
        switch theme {
        case .star: return UIColor(red: 1, green: 0.80, blue: 0.28, alpha: 1)
        default: return miniFillColor(for: theme)
        }
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
        // 收起态不切主题（3.7 (21)）：细条只认点按展开。
        guard gesture.state == .began, let bar = miniBar, !miniBarCollapsed,
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
        resetMiniIdleTimer()
    }

    @objc private func miniPlayTapped() {
        resetMiniIdleTimer()
        PlaybackEngine.shared.togglePlayPause()
    }

    @objc private func miniPrevTapped() {
        resetMiniIdleTimer()
        QueueManager.shared.playPrevious()
    }

    @objc private func miniNextTapped() {
        resetMiniIdleTimer()
        QueueManager.shared.playNext(manual: true)
    }

    /// 台面点按分发（主页版）：按键各自处理；底部进度带 = 点按
    /// 跳点；其余（封面 + 台身）= 进播放详情页——主页没有定位
    /// 语义，Miller 要的就是在主页能进详情页（13.4 #4）。
    @objc private func miniBarTapped(_ gesture: UITapGestureRecognizer) {
        guard let bar = miniBar else { return }
        // 收起态点按（3.7 (21)）：只展开回完整形态并重新计时，
        // 不走原分发（不 seek/不开台）。
        if miniBarCollapsed {
            expandMiniBar()
            return
        }
        // 完整形态的任何点按都算操作，重置无操作计时。
        resetMiniIdleTimer()
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
                resetMiniIdleTimer()
            }
            return
        }
        let fraction = min(max((barPoint.x - track.minX) / track.width, 0), 1)
        switch gesture.state {
        case .began:
            // 收起态不响应拖动（3.7 (21)）：细条只认点按展开。
            if miniBarCollapsed { return }
            if miniCover.frame.contains(barPoint)
                || miniPlayButton.frame.contains(barPoint)
                || miniPrevButton.frame.contains(barPoint)
                || miniNextButton.frame.contains(barPoint) { return }
            guard engine.duration > 0 else { return }
            miniSeekDragging = true
            // 拖动期间挂起无操作计时（3.7 (21)），松手后重置。
            cancelMiniIdleTimer()
            setMiniProgress(Double(fraction))
        case .changed:
            guard miniSeekDragging else { return }
            setMiniProgress(Double(fraction))
        case .ended:
            guard miniSeekDragging else { return }
            miniSeekDragging = false
            resetMiniIdleTimer()
            guard engine.duration > 0 else { return }
            engine.seek(to: Double(fraction) * engine.duration)
        case .cancelled, .failed:
            miniSeekDragging = false
            resetMiniIdleTimer()
        default:
            break
        }
    }

    /// 迷你台逻辑显隐（3.7 (20)）：动画边沿的唯一事实源，与
    /// isHidden（视觉落定态）分工——进/退动画互相打断时以它
    /// 为准判去留，防退场 completion 把已重入的台又藏掉。
    private var miniBarPresented = false

    /// 迷你台显隐边沿动画（3.7 (20)，audit-3720 §三规格；与
    /// 曲目墙同构）：只认 miniBarPresented 的 false↔true 边沿
    /// ——内容刷新（播/停、切歌）每次都走 refreshMiniBar，但
    /// 动画只在 currentTrack nil→非 nil（入场）与非 nil→nil
    /// （退场）时播。入场：alpha 0→1 + 自下方 16pt 升起回落 +
    /// 缩放 0.98→1，系统弹簧 0.65s/damping 0.88；台面毛玻璃
    /// effect 从 nil 在同一段动画里渐入（UIVisualEffectView 的
    /// effect 在 animate 块内赋值由系统做交叉淡化）——玻璃
    /// 「显影」即像画慢慢铺开；封面以 0.05s 延迟做 0.92→1 次级
    /// 缩放。退场对称：0.28s 淡出 + 下沉 8pt，完成后才置
    /// hidden。Reduce Motion 时降级为纯 alpha 淡化（0.2s、无
    /// 位移缩放、effect 直接置位不做显影）。
    private func setMiniBarVisible(_ visible: Bool) {
        guard let bar = miniBar else { return }
        miniThemeLayer?.setBarVisible(visible)
        guard visible != miniBarPresented else { return }
        miniBarPresented = visible
        if visible {
            // 形态复位（3.7 (21)）：收起态不跨显隐周期残留——
            // 每次出现先完整形态，再起无操作计时。
            if miniBarCollapsed { resetMiniBarFormInstant() }
            resetMiniIdleTimer()
        } else {
            cancelMiniIdleTimer()
        }
        bar.layer.removeAllAnimations()
        if visible {
            if UIAccessibility.isReduceMotionEnabled {
                miniBlurView?.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
                bar.transform = .identity
                bar.isHidden = false
                UIView.animate(withDuration: 0.2, animations: {
                    bar.alpha = 1
                })
                return
            }
            bar.alpha = 0
            bar.transform = CGAffineTransform(translationX: 0, y: 16)
                .scaledBy(x: 0.98, y: 0.98)
            miniBlurView?.effect = nil
            bar.isHidden = false
            miniCover.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            miniCover.alpha = 0
            UIView.animate(withDuration: 0.65, delay: 0,
                           usingSpringWithDamping: 0.88, initialSpringVelocity: 0.15,
                           options: [.curveEaseOut, .allowUserInteraction]) {
                bar.alpha = 1
                bar.transform = .identity
                self.miniBlurView?.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            }
            UIView.animate(withDuration: 0.65, delay: 0.05,
                           usingSpringWithDamping: 0.88, initialSpringVelocity: 0.15,
                           options: [.curveEaseOut, .allowUserInteraction]) {
                self.miniCover.transform = .identity
                self.miniCover.alpha = 1
            }
        } else {
            let duration = UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.28
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.curveEaseIn, .beginFromCurrentState], animations: {
                bar.alpha = 0
                if !UIAccessibility.isReduceMotionEnabled {
                    bar.transform = CGAffineTransform(translationX: 0, y: 8)
                }
            }, completion: { [weak self] _ in
                // 已被重入打断（逻辑态已翻回）则不落 hidden。
                guard let self, !self.miniBarPresented else { return }
                bar.isHidden = true
                bar.transform = .identity
                // 退场落定时形态静默复位（3.7 (21)）：下次出现
                // 必是完整形态（与出现边沿的复位双保险）。
                self.resetMiniBarFormInstant()
            })
        }
    }

    // MARK: - 迷你台收起（3.7 (21)：5 秒无操作自动收成进度条，与曲目墙同构）

    /// 无操作收起延迟（Miller 17:01 定：5 秒）。
    private static let miniIdleCollapseDelay: TimeInterval = 5

    /// 重置无操作计时：在场、完整形态、非拖动中才起 5 秒倒
    /// 计时；任何对台的操作（点按/按键/长按切主题/seek 结束/
    /// 切歌/回墙）都经这里续命。
    private func resetMiniIdleTimer() {
        miniIdleWorkItem?.cancel()
        miniIdleWorkItem = nil
        guard miniBarPresented, !miniBarCollapsed, !miniSeekDragging else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.collapseMiniBarIdle()
        }
        miniIdleWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.miniIdleCollapseDelay, execute: work)
    }

    private func cancelMiniIdleTimer() {
        miniIdleWorkItem?.cancel()
        miniIdleWorkItem = nil
    }

    /// 收成细进度条：同位置同宽，高度 70→16、轨道居中，封面/
    /// 标题/歌手/按键淡出且按键禁交互；背景全去（3.7 (22)：
    /// 主题层/毛玻璃/玻璃高光隐藏），只保留轨道（极淡底轨）
    /// + 填充 + 发光圆点，由 setMiniProgress 继续步进。系统
    /// 弹簧 0.5s；Reduce Motion 降级为仅 alpha 淡化、几何
    /// 瞬时切换。
    private func collapseMiniBarIdle() {
        guard miniBarPresented, !miniBarCollapsed, !miniSeekDragging,
              let bar = miniBar else { return }
        miniBarCollapsed = true
        cancelMiniIdleTimer()
        Breadcrumbs.log("minibar collapse idle")
        setMiniBarContentsInteractive(false)
        if UIAccessibility.isReduceMotionEnabled {
            setMiniBarForm(collapsed: true)
            UIView.animate(withDuration: 0.2) { self.setMiniBarContentsAlpha(0) }
            return
        }
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0.1,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.setMiniBarForm(collapsed: true)
            self.setMiniBarContentsAlpha(0)
            bar.superview?.layoutIfNeeded()
        }
    }

    /// 恢复完整形态（点细条/切歌触发）并重新计时。
    private func expandMiniBar() {
        guard miniBarCollapsed, let bar = miniBar else {
            resetMiniIdleTimer()
            return
        }
        miniBarCollapsed = false
        Breadcrumbs.log("minibar expand")
        setMiniBarContentsInteractive(true)
        if UIAccessibility.isReduceMotionEnabled {
            setMiniBarForm(collapsed: false)
            UIView.animate(withDuration: 0.2) { self.setMiniBarContentsAlpha(1) }
        } else {
            UIView.animate(withDuration: 0.5, delay: 0,
                           usingSpringWithDamping: 0.85, initialSpringVelocity: 0.1,
                           options: [.curveEaseOut, .allowUserInteraction]) {
                self.setMiniBarForm(collapsed: false)
                self.setMiniBarContentsAlpha(1)
                bar.superview?.layoutIfNeeded()
            }
        }
        resetMiniIdleTimer()
    }

    /// 形态几何（高度/轨道底距/圆角）：在动画块内调用即随
    /// 动画走；显隐边沿复位与 Reduce Motion 时在动画块外
    /// 直接置位即瞬时生效。
    private func setMiniBarForm(collapsed: Bool) {
        miniBarHeightConstraint?.constant = collapsed ? 16 : 70
        miniTrackBottomConstraint?.constant = collapsed ? -6 : -7
        let radius: CGFloat = collapsed ? 8 : 35
        miniBar?.layer.cornerRadius = radius
        miniBlurView?.layer.cornerRadius = radius
        // 收起态命中带（3.7 (21.1)）：视觉仍 16pt，纵向命中
        // 扩到 44pt（上下各 14pt）；展开态归零，原分发不变。
        // 全部形态切换（收起/展开/边沿复位）都经此收口，开关
        // 与形态严格同步。
        (miniBar as? MiniBarHitView)?.hitExpansionY = collapsed ? 14 : 0
        // 收起态去背景（3.7 (22)，Miller 定版 + DS R48）：主题
        // 层、毛玻璃、玻璃高光/罩全部隐藏，只保留轨道（白
        // 0.25 极淡底轨，属进度条本体）+ 填充 + 发光圆点；
        // 展开态全部恢复。填充/圆点配色同步经形态收口重算
        // （对比度兜底）。
        miniThemeLayer?.isHidden = collapsed
        miniBlurView?.isHidden = collapsed
        miniRimLight?.isHidden = collapsed
        miniGlassTint?.isHidden = collapsed
        refreshMiniProgressChrome()
    }

    private func setMiniBarContentsAlpha(_ alpha: CGFloat) {
        // 圆点不在淡出名单（3.7 (22)）：收起态保留发光圆点
        // 随进度步进，淡出的只有封面/标题/歌手/按键。
        let views: [UIView?] = [miniCover, miniTitle, miniArtist, miniPlayButton,
                                miniPrevButton, miniNextButton]
        for view in views {
            view?.alpha = alpha
        }
    }

    private func setMiniBarContentsInteractive(_ interactive: Bool) {
        let buttons: [UIButton?] = [miniPlayButton, miniPrevButton, miniNextButton]
        for button in buttons {
            button?.isUserInteractionEnabled = interactive
        }
    }

    /// 显隐边沿的形态无动画复位：收起态不跨显隐周期残留。
    private func resetMiniBarFormInstant() {
        miniBarCollapsed = false
        setMiniBarForm(collapsed: false)
        setMiniBarContentsAlpha(1)
        setMiniBarContentsInteractive(true)
    }

    /// 播放台内容同步（与曲目墙同构）：有当前曲才显示。
    private func refreshMiniBar() {
        guard miniBar != nil else { return }
        let engine = PlaybackEngine.shared
        guard let track = engine.currentTrack else {
            miniLastTrackId = nil
            setMiniBarVisible(false)
            return
        }
        setMiniBarVisible(true)
        if track.id != miniLastTrackId {
            miniLastTrackId = track.id
            // 切歌（3.7 (21)）：收起态先展开回完整形态，未
            // 收起则重置无操作计时——新歌先以完整形态亮相。
            if miniBarCollapsed { expandMiniBar() } else { resetMiniIdleTimer() }
        }
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

// MARK: - 贴纸层（3.7 (24)，纯新增视图层）
//
// 场景（scene-mapping.md 终版）：
// - 主页墙入场/同步：加载中底部 dock 内横向跑过——dog-21
//   （举枫叶跑动，100pt，循环横穿）与 cat-13（含泪迈步入场，
//   72pt，走入后停住）按加载回合轮换。
// - 断网/加载失败：最终失败态居中 cat-03（站立流泪打转，
//   80pt，播一次；失败持续存在时每 8 秒低频重播）。
// - 切歌缓冲：引擎 .waiting 且有当前曲时，迷你台封面角上方
//   小只——dog-05（原地翻滚，循环）与 cat-08（翻滚，每回
//   合播一次）按回合轮换，58pt。
// 全部只读既有状态（entryDataState / playbackState），不回写
// 任何状态机；狗素材带浅色贴纸底（映射口径：狗须浅色底面）。

extension HomeWallViewController {

    private func stickerEnsureViews() {
        if stickerDock == nil {
            let dock = UIView()
            dock.isUserInteractionEnabled = false
            view.addSubview(dock)
            stickerDock = dock
        }
        if stickerFailureView == nil {
            let failure = StickerView()
            failure.isHidden = true
            view.addSubview(failure)
            stickerFailureView = failure
        }
        if stickerBufferView == nil {
            let buffer = StickerView()
            buffer.isHidden = true
            view.addSubview(buffer)
            stickerBufferView = buffer
        }
    }

    func stickerDataStateChanged() {
        stickerEnsureViews()
        switch entryDataState {
        case .loading:
            stickerHideFailure()
            stickerStartRunner()
        case .ready:
            stickerStopRunner()
            stickerHideFailure()
        case .failed:
            stickerStopRunner()
            stickerShowFailure()
        }
    }

    // MARK: 入场跑动

    private func stickerStartRunner() {
        guard let dock = stickerDock else { return }
        // 按加载回合轮换：狗跑动 / 猫走入交替。
        stickerLastRunnerWasDog.toggle()
        let useDog = stickerLastRunnerWasDog
        let runner: StickerView
        if let existing = stickerRunnerView {
            runner = existing
        } else {
            runner = StickerView()
            dock.addSubview(runner)
            stickerRunnerView = runner
        }
        runner.layer.removeAllAnimations()
        if useDog {
            runner.showsTileBackground = true
            runner.frame = CGRect(x: -110, y: 8, width: 100, height: 100)
            runner.setSticker("dog-21", mode: .loop)
        } else {
            runner.showsTileBackground = false
            runner.frame = CGRect(x: -80, y: 36, width: 72, height: 72)
            runner.setSticker("cat-13", mode: .once(holdLast: true))
        }
        runner.isHidden = false
        stickerLayoutOverlays()
        if useDog {
            stickerRunAcross()
        } else {
            UIView.animate(withDuration: 2.4, delay: 0, options: [.curveLinear]) {
                runner.center = CGPoint(x: 110, y: runner.center.y)
            }
        }
    }

    private func stickerRunAcross() {
        guard entryDataState == .loading,
              let runner = stickerRunnerView, !runner.isHidden,
              stickerLastRunnerWasDog,
              let dock = stickerDock, dock.bounds.width > 0 else { return }
        runner.center = CGPoint(x: -60, y: runner.center.y)
        UIView.animate(withDuration: 3.6, delay: 0, options: [.curveLinear]) {
            runner.center = CGPoint(x: dock.bounds.width + 60, y: runner.center.y)
        } completion: { [weak self] _ in
            self?.stickerRunAcross()
        }
    }

    private func stickerStopRunner() {
        stickerRunnerView?.layer.removeAllAnimations()
        stickerRunnerView?.isHidden = true
    }

    // MARK: 失败陪衬

    private func stickerShowFailure() {
        guard let failure = stickerFailureView else { return }
        failure.setSticker("cat-03", mode: .once(holdLast: true))
        failure.isHidden = false
        stickerLayoutOverlays()
        stickerFailureReplayTimer?.invalidate()
        stickerFailureReplayTimer = Timer.scheduledTimer(
            withTimeInterval: 8, repeats: true) { [weak self] _ in
                guard let self, self.entryDataState == .failed,
                      self.view.window != nil else {
                    self?.stickerFailureReplayTimer?.invalidate()
                    self?.stickerFailureReplayTimer = nil
                    return
                }
                self.stickerFailureView?.restart()
            }
    }

    private func stickerHideFailure() {
        stickerFailureReplayTimer?.invalidate()
        stickerFailureReplayTimer = nil
        stickerFailureView?.isHidden = true
    }

    // MARK: 切歌缓冲

    func stickerBufferStateChanged(_ state: PlaybackState) {
        let shouldShow = state == .waiting
            && PlaybackEngine.shared.currentTrack != nil
        if shouldShow, !stickerBufferVisible {
            stickerBufferVisible = true
            stickerEnsureViews()
            stickerBufferEpisode += 1
            guard let buffer = stickerBufferView else { return }
            if stickerBufferEpisode % 2 == 1 {
                buffer.showsTileBackground = true
                buffer.setSticker("dog-05", mode: .loop)
            } else {
                buffer.showsTileBackground = false
                buffer.onFinished = { [weak buffer] in buffer?.isHidden = true }
                buffer.setSticker("cat-08", mode: .once(holdLast: false))
            }
            buffer.isHidden = false
            stickerLayoutOverlays()
        } else if !shouldShow, stickerBufferVisible {
            stickerBufferVisible = false
            stickerBufferView?.isHidden = true
        }
    }

    // MARK: 定位

    func stickerLayoutOverlays() {
        let bounds = view.bounds
        guard bounds.width > 0 else { return }
        if let dock = stickerDock {
            dock.frame = CGRect(
                x: 0, y: bounds.height - view.safeAreaInsets.bottom - 116,
                width: bounds.width, height: 116)
        }
        if let failure = stickerFailureView {
            failure.frame = CGRect(
                x: (bounds.width - 80) / 2, y: (bounds.height - 80) / 2 - 24,
                width: 80, height: 80)
        }
        if let buffer = stickerBufferView, let bar = miniBar {
            buffer.frame = CGRect(
                x: bar.frame.minX + 4, y: bar.frame.minY - 64,
                width: 58, height: 58)
        }
    }
}
