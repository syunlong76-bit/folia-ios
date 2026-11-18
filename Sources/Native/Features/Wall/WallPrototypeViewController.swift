import Combine
import UIKit

/// M1 阶段 3：单墙原型（队列墙几何 + 真实歌单数据）。入口：主界面
/// 设置齿轮长按（壳级调试入口，不影响正常使用）。只验证三件事：
/// 自由平移的帧率与手感、封面按档出图、点按展开的同块重排。
/// 不是正式表面：无播放焦点、无详情交接、无标题分区（探索墙的
/// lot 系统与 Bravais 的 rank 系统在阶段 4 各自接入）。
final class WallPrototypeViewController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching {

    struct Entry {
        let id: String
        let title: String
        let picUrl: String?
        /// 副行（如歌单的「歌单 · 285」）；曲目墙不用。
        var subtitle: String? = nil
    }

    private let playlistId: String
    /// 切入氛围底用的歌单名/封面（由主页墙点按时传入；原型入口可缺省）。
    private let playlistTitle: String?
    private let playlistCoverUrl: String?
    private var entries: [Entry] = []
    /// 详情 MVP：与 entries 平行的完整曲目模型 + 全量 id 骨架
    /// （队列按 trackIds 建、元数据按已加载曲目填，未加载的占位）。
    private var nativeTracks: [NativeTrack] = []
    private var allTrackIds: [String] = []
    private var playbackCancellables = Set<AnyCancellable>()
    private var progressTimer: Timer?
    /// 播放三态（DS26）：原生点播在途的曲目 id，起播确认或失败即清。
    private var pendingTrackId: String?
    /// 原生点播失败的曲目与短文案（展开卡失败条用）。
    private var failedPlayback: (id: String, message: String)?
    /// 滚动歌词缓存：trackId → [(time, text)]；空数组 = 已查无词。
    private var lyricCache: [String: [(time: Double, text: String)]] = [:]
    private var lyricFetchInFlight: Set<String> = []
    private var lastLyricKey = ""
    private let wallLayout = WallLayout()
    private var collectionView: UICollectionView!
    private var statusLabel: UILabel!
    private var backdrop: LoadingBackdropView?
    private var didCenterCamera = false
    private var isWrapping = false

    // 丝滑切入（3.7 (8)）：预加载 + 等首批数据再 present 的信号。
    private(set) var seedReady = false
    private var seedWaiters: [CheckedContinuation<Bool, Never>] = []
    /// 加载胶囊防闪：出现时刻（>600ms 才显示、最小展示 300ms）。
    private var pillShownAt: Date?
    /// 首屏波次入场：种子落地时刻 + 已发出的波次序号。
    private var waveStart: Date?
    private var waveCount = 0

    init(playlistId: String = "19723756", title: String? = nil, coverUrl: String? = nil) {
        self.playlistId = playlistId
        self.playlistTitle = title
        self.playlistCoverUrl = coverUrl
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

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

        statusLabel = UILabel()
        statusLabel.text = "墙原型加载中…"
        statusLabel.isHidden = true
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
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

        // 氛围底（丝滑切入）：盖在空墙上、垫在胶囊/关闭键下；数据
        // 到达后淡出。封面来自内存缓存（主页墙刚显示过），零等待。
        let backdropView = LoadingBackdropView(title: playlistTitle)
        backdropView.setCover(rawUrl: playlistCoverUrl)
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(backdropView, belowSubview: statusLabel)
        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        backdrop = backdropView

        // 转场落定：墙以 1.04 倍入场、viewDidAppear 里收回 1.0。
        collectionView.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)

        // 播放态同步（详情 MVP）：切歌/播放暂停时只更新可见 cell
        // 的角标与展开卡控件，不整表刷新。
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self else { return }
                if let track, track.id == self.pendingTrackId {
                    self.pendingTrackId = nil
                }
                self.refreshVisiblePlaybackUI()
            }
            .store(in: &playbackCancellables)
        PlaybackEngine.shared.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshVisiblePlaybackUI() }
            .store(in: &playbackCancellables)
        // 原生点播失败落地（DS26 三态的失败支）：只认领自己在途的
        // 那次点播；网页侧发起的失败不归本墙管。
        QueueManager.shared.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self, let message,
                      let pending = self.pendingTrackId else { return }
                self.pendingTrackId = nil
                self.failedPlayback = (pending, message.contains("VIP")
                    ? "VIP 或版权受限，点播放重试" : "播放失败，点播放重试")
                self.refreshVisiblePlaybackUI()
            }
            .store(in: &playbackCancellables)

        loadEntries()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) {
            [weak self] _ in self?.tickProgress()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        progressTimer?.invalidate()
        progressTimer = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut]) {
            self.collectionView.transform = .identity
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - 预加载（等首批数据再 present，DS 第二十四轮栈首）

    /// 提前触发 view 加载（连带 loadEntries 开跑）：主页墙点按时先
    /// 调它，再 awaitSeed 短等，命中就带内容 present。
    func startPreload() {
        loadViewIfNeeded()
    }

    /// 等种子（首批条目）落地；超时返回当前状态（多半 false），
    /// 调用方照常 present、由氛围底兜住剩余等待。
    func awaitSeed(timeout: TimeInterval) async -> Bool {
        if seedReady { return true }
        return await withCheckedContinuation { continuation in
            seedWaiters.append(continuation)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run { self?.flushSeedWaiters() }
            }
        }
    }

    /// 在主线程统一唤醒等待者（种子落地与超时共用，保证只唤醒一次）。
    private func flushSeedWaiters() {
        let waiters = seedWaiters
        seedWaiters.removeAll()
        waiters.forEach { $0.resume(returning: seedReady) }
    }

    // MARK: - 数据

    private func loadEntries() {
        Task { [weak self] in
            guard let self else { return }
            do {
                // 3.7 (7) 单趟立墙（实测推翻分页必要性）：/playlist/
                // detail 的响应直接内嵌全部曲目对象（338/338 首全在，
                // 含 picUrl），一次往返数据全齐、封面立刻全量开取。
                // 3.7 (6) 的分页拼接只留作缺口兜底：超大歌单内嵌被
                // 截断时，从已得数量处继续分页补齐。
                // 加载胶囊延迟出现：600ms 内种子落地就不显示加载态，
                // 防快路径下胶囊一闪（DS 第二十四轮 e 项）。
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await MainActor.run {
                        guard let self, !self.seedReady else { return }
                        self.pillShownAt = Date()
                        self.statusLabel.text = "墙原型加载中…"
                        self.statusLabel.isHidden = false
                    }
                }
                let detail = try await NativeDataClient.shared.fetchPlaylistDetail(id: playlistId)
                let total = detail.trackCount
                let seed = detail.tracks.map {
                    Entry(id: $0.id, title: $0.name, picUrl: $0.picUrl, subtitle: $0.artists)
                }
                await MainActor.run {
                    self.nativeTracks = detail.tracks
                    self.allTrackIds = detail.trackIds
                    self.entries = seed
                    self.wallLayout.totalEntries = total
                    self.statusLabel.text = seed.count >= total
                        ? "墙原型：\(total) 首 · 拖动平移 · 点按展开"
                        : "墙原型：共 \(total) 首 · 加载中 \(seed.count)"
                    self.statusLabel.isHidden = false
                    self.wallLayout.refreshInstances()
                    self.collectionView.reloadData()
                    self.centerCameraIfNeeded()
                    // 丝滑切入收口：唤醒等数据的 present、氛围底退场、
                    // 首屏波次从此刻起算。
                    self.seedReady = true
                    self.flushSeedWaiters()
                    self.waveStart = Date()
                    self.backdrop?.dismiss()
                }
                // 页大小 400（3.7 (7) 实测）：往返的固定开销占大头
                // （EdgeOne→网易云单次 4–9 秒、与页大小关系不大），
                // limit=400 一次拿全 338 首 9.0 秒 / 712KB；100 一页
                // 4.5–6.4 秒、四页并发两批也要 11 秒以上，且后页封面
                // 必须等数据页落地才能开取。≤400 首的歌单自此单趟
                // 到齐；更大的仍走下面的并发前缀拼接。
                let pageSize = 400
                var offset = seed.count
                while offset < total {
                    // 3 路并发取页；结果按 offset 收齐，只拼连续前缀：
                    // 中间页失败就在缺口处停下，下一轮从缺口重取，
                    // 绝不让序号错位。
                    let batchOffsets = Array(stride(from: offset, to: min(offset + pageSize * 3, total), by: pageSize))
                    var byOffset: [Int: [NativeTrack]] = [:]
                    await withTaskGroup(of: (Int, [NativeTrack]?).self) { group in
                        for pageOffset in batchOffsets {
                            group.addTask {
                                do {
                                    let tracks = try await NativeDataClient.shared.fetchPlaylistTracksPage(
                                        id: self.playlistId, limit: pageSize, offset: pageOffset)
                                    return (pageOffset, tracks)
                                } catch {
                                    return (pageOffset, nil)
                                }
                            }
                        }
                        for await (pageOffset, page) in group { byOffset[pageOffset] = page }
                    }
                    // 失败页不入表（字典赋 nil 即删键）：连续前缀在
                    // 失败页处自然停住，本轮不再前进（重进墙会重拉）。
                    var chunk: [NativeTrack] = []
                    var reachedEnd = false
                    while let page = byOffset[offset] {
                        chunk.append(contentsOf: page)
                        offset += page.count
                        if page.count < pageSize { reachedEnd = true; break }
                    }
                    let progressed = !chunk.isEmpty
                    await MainActor.run {
                        self.nativeTracks.append(contentsOf: chunk)
                        self.entries.append(contentsOf: chunk.map {
                            Entry(id: $0.id, title: $0.name, picUrl: $0.picUrl, subtitle: $0.artists)
                        })
                        self.statusLabel.text = reachedEnd || self.entries.count >= total
                            ? "墙原型：\(total) 首 · 拖动平移 · 点按展开"
                            : "墙原型：共 \(total) 首 · 加载中 \(self.entries.count)"
                        self.collectionView.reloadData()
                    }
                    if reachedEnd || !progressed { break }
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.text = "墙原型加载失败：\(error)"
                    self.statusLabel.isHidden = false
                    self.flushSeedWaiters()
                    self.backdrop?.dismiss()
                }
            }
        }
    }

    // MARK: - 相机

    static func cameraScale(forWidth width: CGFloat) -> Double {
        if width < 640 { return 0.52 }
        if width < 1100 { return 0.64 }
        return 0.76
    }

    private func centerCameraIfNeeded() {
        guard !didCenterCamera, wallLayout.totalEntries > 0 else { return }
        didCenterCamera = true
        wallLayout.cameraScale = Self.cameraScale(forWidth: collectionView.bounds.width)
        let cell = wallLayout.cellViewSize
        collectionView.contentOffset = CGPoint(x: cell.width, y: cell.height)
        wallLayout.invalidateLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        centerCameraIfNeeded()
    }

    /// 相机增量折叠（3.7 (2) 修复）：3.7 (1) 的整格绕回模型有个致命
    /// 错误——属性帧 =（世界 − 原点）× scale + contentOffset，视觉位置
    /// = 帧 − offset 恒等于（世界 − 原点）× scale，与拖动无关：拖动时
    /// 画面纹丝不动，跨过绕回阈值才整格跳一次，真机录屏实证为 PPT。
    /// 改法：offset 恒钉在中心单元，任一滚动增量立即折进 worldOrigin
    /// 并把 offset 拉回中心——相机连续跟手，帧公式不变即成立。
    /// 实例集身份（首/尾 id + 计数）变了才 reloadData，否则只失效布局。
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

    /// 实例集身份指纹：判断下标→实例的映射是否还成立。
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
        // 渐进加载期：该序号的曲目可能还没补到，先给空占位（深灰砖），
        // 页落地 reloadData 后自然填上。
        guard instance.queueIndex < entries.count else {
            cell.configure(entry: Entry(id: "", title: "", picUrl: nil), tier: 512)
            cell.configurePlayback(expanded: false, isCurrent: false,
                                   isPlaying: false, liked: false, progress: 0)
            return cell
        }
        let entry = entries[instance.queueIndex]
        let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
        let pixelExtent = Double(max(frame.width, frame.height)) * Double(UIScreen.main.scale)
        let tier = entry.picUrl.map { NativeCoverLoader.wallTier(raw: $0, pixelExtent: pixelExtent) }
            ?? NativeCoverLoader.tier(forPixelExtent: pixelExtent)
        cell.configure(entry: entry, tier: tier)
        // 首屏波次（种子落地 0.9 秒内）：按出现序给递增延迟，
        // 总时长压在约 0.45 秒内（DS 第二十四轮 c 项上限）。
        var entranceDelay: TimeInterval = 0
        if let waveStart, Date().timeIntervalSince(waveStart) < 0.9 {
            entranceDelay = Double(min(waveCount, 12)) * 0.035
            waveCount += 1
        }
        cell.playEntranceIfNeeded(key: entry.id, delay: entranceDelay)
        applyPlaybackState(to: cell, instance: instance)
        return cell
    }

    // MARK: 详情 MVP：展开卡播放 / 红心 / 播放态同步

    /// 把引擎实况刷到一个 cell：展开卡控件、当前曲角标、红心、进度。
    private func applyPlaybackState(to cell: WallPosterCell, instance: QueueInstance) {
        guard instance.queueIndex < entries.count else { return }
        let entry = entries[instance.queueIndex]
        let engine = PlaybackEngine.shared
        let isCurrent = engine.currentTrack?.id == entry.id
        let progress = isCurrent && engine.duration > 0
            ? engine.currentTime / engine.duration : 0
        let loadState: WallPlayLoadState
        if entry.id == pendingTrackId {
            loadState = .connecting
        } else if let failed = failedPlayback, failed.id == entry.id {
            loadState = .failed(failed.message)
        } else {
            loadState = .idle
        }
        cell.configurePlayback(
            expanded: wallLayout.expandedInstanceId == instance.instanceId,
            isCurrent: isCurrent,
            isPlaying: engine.isPlaying,
            liked: LikesStore.shared.isLiked(entry.id),
            progress: progress,
            loadState: loadState)
        // 展开卡是当前曲且词已到手：作废歌词窗口键，下一拍心跳重刷
        // （收起时 cell 已清窗口，光靠键去重会漏刷）。
        if wallLayout.expandedInstanceId == instance.instanceId, isCurrent,
           lyricCache[entry.id] != nil {
            lastLyricKey = ""
        }
        let queueIndex = instance.queueIndex
        cell.onPlayTap = { [weak self] in self?.playTapped(queueIndex: queueIndex) }
        cell.onLikeTap = { [weak self] in self?.likeTapped(queueIndex: queueIndex) }
        cell.onBadgeTap = { [weak self] in self?.badgeTapped() }
    }

    /// 小喇叭点按：请前端打开播放页，并收起整摞原生墙。前端监听器
    /// 落地前事件无声投递，用户落在网页层迷你播放器旁（DS26 降级
    /// (b)）；落地后同一路径直接弹开舞台 (a)。
    private func badgeTapped() {
        WebEffectBridge.shared.requestOpenStage()
        var host: UIViewController = self
        while let presenter = host.presentingViewController { host = presenter }
        if host !== self { host.dismiss(animated: true) }
    }

    private func refreshVisiblePlaybackUI() {
        for case let cell as WallPosterCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  indexPath.item < wallLayout.instances.count else { continue }
            applyPlaybackState(to: cell, instance: wallLayout.instances[indexPath.item])
        }
    }

    /// 0.3 秒心跳：只更新展开中的当前曲卡的迷你进度条。
    private func tickProgress() {
        let engine = PlaybackEngine.shared
        guard let currentId = engine.currentTrack?.id, engine.duration > 0 else { return }
        for case let cell as WallPosterCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  indexPath.item < wallLayout.instances.count else { continue }
            let instance = wallLayout.instances[indexPath.item]
            guard instance.queueIndex < entries.count,
                  entries[instance.queueIndex].id == currentId,
                  wallLayout.expandedInstanceId == instance.instanceId else { continue }
            cell.updateProgress(engine.currentTime / engine.duration)
            updateLyricWindow(for: cell, trackId: currentId,
                              currentTime: engine.currentTime)
        }
    }

    /// 滚动歌词（Miller 第 5 点，P0 隔离附加项）：展开卡是当前曲时，
    /// 按引擎时钟推进 5 行窗口。只读时钟 + 现成歌词接口，取词失败
    /// 或无词就不显示，碰不到队列/取流链。
    private func updateLyricWindow(for cell: WallPosterCell, trackId: String,
                                   currentTime: Double) {
        guard let lines = lyricCache[trackId] else {
            ensureLyrics(for: trackId)
            return
        }
        guard !lines.isEmpty else { return }
        var idx = 0
        for (i, line) in lines.enumerated() {
            if line.time <= currentTime + 0.15 { idx = i } else { break }
        }
        let key = "\(trackId)#\(idx)"
        guard key != lastLyricKey else { return }
        lastLyricKey = key
        let window = (-2...2).map { offset -> String in
            let j = idx + offset
            return (j >= 0 && j < lines.count) ? lines[j].text : ""
        }
        cell.setLyricWindow(window)
    }

    private func ensureLyrics(for trackId: String) {
        guard lyricCache[trackId] == nil,
              !lyricFetchInFlight.contains(trackId) else { return }
        lyricFetchInFlight.insert(trackId)
        Task { [weak self] in
            let text = try? await EdgeOneAPIClient.shared.fetchLyricText(songId: trackId)
            let parsed = text.map { Self.parseLRC($0) } ?? []
            await MainActor.run {
                guard let self else { return }
                self.lyricFetchInFlight.remove(trackId)
                self.lyricCache[trackId] = parsed
                self.lastLyricKey = ""
            }
        }
    }

    /// LRC 解析：[mm:ss.xx] 前缀行 → (秒， 文本）；多时间戳行只取
    /// 首个，空文本行丢弃，结果按时间升序。
    private static func parseLRC(_ raw: String) -> [(time: Double, text: String)] {
        var out: [(time: Double, text: String)] = []
        for line in raw.split(separator: "\n") {
            let s = String(line)
            guard s.hasPrefix("["), let close = s.firstIndex(of: "]") else { continue }
            let stamp = s[s.index(after: s.startIndex)..<close]
            let parts = stamp.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { continue }
            let text = String(s[s.index(after: close)...])
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            out.append((time: minutes * 60 + seconds, text: text))
        }
        return out.sorted { $0.time < $1.time }
    }

    /// 点播放：当前曲切换播放/暂停；否则按全量 trackIds 建队列
    /// （规格 v2.1：点行播放 = 全量队列，未加载曲目占位入队、取流
    /// 时按 id 解析），从点中曲目起播。
    private func playTapped(queueIndex: Int) {
        guard queueIndex < entries.count else { return }
        let tappedId = entries[queueIndex].id
        if PlaybackEngine.shared.currentTrack?.id == tappedId {
            PlaybackEngine.shared.togglePlayPause()
            return
        }
        let ids = allTrackIds.isEmpty ? nativeTracks.map(\.id) : allTrackIds
        guard let start = ids.firstIndex(of: tappedId) else { return }
        let meta = Dictionary(nativeTracks.map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        let queue: [FoliaTrack] = ids.map { tid in
            if let t = meta[tid] { return foliaTrack(for: t) }
            return FoliaTrack(id: tid, sourceType: .netease, title: "",
                              artist: "", duration: 0)
        }
        // 三态入场：先亮连接中，起播确认（currentTrack 落地）或失败
        // （lastError）到达时由订阅清状态。
        pendingTrackId = tappedId
        failedPlayback = nil
        refreshVisiblePlaybackUI()
        QueueManager.shared.setQueue(queue, startingAt: start, source: "native-wall")
    }

    /// NativeTrack → FoliaTrack 的唯一构造点（点播队列与预取共用）。
    private func foliaTrack(for track: NativeTrack) -> FoliaTrack {
        FoliaTrack(
            id: track.id, sourceType: .netease, title: track.name,
            artist: track.artists, album: track.albumName ?? "",
            duration: Double(track.durationMs) / 1000,
            artworkURL: track.picUrl.flatMap { URL(string: $0) })
    }

    /// 红心：本地真源乐观切换 → /like 同步账号，失败回滚本地与界面。
    private func likeTapped(queueIndex: Int) {
        guard queueIndex < entries.count else { return }
        let id = entries[queueIndex].id
        let newState = LikesStore.shared.toggle(id)
        refreshVisiblePlaybackUI()
        Task {
            do {
                _ = try await NativeDataClient.shared.setLike(trackId: id, like: newState)
            } catch {
                LikesStore.shared.toggle(id)
                await MainActor.run { self.refreshVisiblePlaybackUI() }
            }
        }
    }

    // MARK: - 预取（拖动闪黑对策：图先进内存缓存，cell 出现时同步上图）

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

    // MARK: - 点按展开

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let instance = wallLayout.instances[indexPath.item]
        let before = setIdentity()
        // 3.7 (3)：不再跳切相机居中（那是生硬感主源）——原地弹簧重排：
        // 被点卡在原地长大、同块卡让位，镜头不动。
        if wallLayout.expandedInstanceId == instance.instanceId {
            wallLayout.expandedInstanceId = nil
        } else {
            wallLayout.expandedInstanceId = instance.instanceId
            // 展开即预取（DS26 深度 1）：只解这一首的播放地址入缓存，
            // 用户真点播放时少等一程取流。元数据未补到的序号跳过。
            if instance.queueIndex < nativeTracks.count {
                QueueManager.shared.prefetchStream(
                    for: foliaTrack(for: nativeTracks[instance.queueIndex]))
            }
        }
        wallLayout.refreshInstances()
        if setIdentity() == before {
            let animator = UIViewPropertyAnimator(duration: 0.45, dampingRatio: 0.86) {
                self.wallLayout.invalidateLayout()
                collectionView.layoutIfNeeded()
            }
            animator.startAnimation()
        } else {
            collectionView.reloadData()
        }
        // 展开/收起后控件归属变了：动画路径不重查 cell，手动刷一遍
        // 可见 cell 的播放态（展开卡出控件、收起卡撤控件）。
        refreshVisiblePlaybackUI()
    }
}

/// 展开卡播放三态（DS26）：连接中转圈、失败出文案可重试，
/// 不再出现「点了 11 秒没反应」的静默态。
enum WallPlayLoadState {
    case idle
    case connecting
    case failed(String)

    var isConnecting: Bool { if case .connecting = self { return true }; return false }
    var isFailed: Bool { if case .failed = self { return true }; return false }
}

/// 墙海报 cell：封面 + 底部标题。圆角用图层裁切、阴影用 shadowPath
/// 挂在外层容器（规格 §4：禁止默认离屏渲染路径）。
final class WallPosterCell: UICollectionViewCell {

    static let reuseId = "WallPosterCell"

    private let shadowView = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var loadTask: Task<Void, Never>?
    private var currentUrl: String?

    // 展开卡控件（详情 MVP 第一刀）：播放/暂停、红心、迷你进度条；
    // 未展开只留「正在播放」角标。回调由 VC 按实例注入，普通卡
    // （主页墙歌单卡）永不配置、恒隐藏。
    var onPlayTap: (() -> Void)?
    var onLikeTap: (() -> Void)?
    /// 正在播放角标点按（DS26 改真按钮）：VC 收墙 + 请前端开播放页。
    var onBadgeTap: (() -> Void)?
    private let playButton = UIButton(type: .system)
    private let likeButton = UIButton(type: .system)
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let playingBadge = UIButton(type: .system)
    private let playSpinner = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private let lyricLabels: [UILabel] = (0..<5).map { _ in UILabel() }
    private var controlsVisible = false
    private var progressValue: Double = 0

    /// 入场淡入已播过的条目（按条目 id 去重、跨 cell 复用有效）：
    /// 同一面墙里平铺重复的同一条目只在首现时淡入，后续实例直接
    /// 显示，平移时不反复闪。
    private static var entranceSeen = Set<String>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0.35
        shadowView.layer.shadowRadius = 6
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 2)
        contentView.addSubview(shadowView)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        // 未出图占位用深灰而非近黑：拖动中未加载的卡读作灰砖，不读作黑洞。
        imageView.backgroundColor = UIColor(white: 0.13, alpha: 1)
        shadowView.addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOpacity = 0.8
        titleLabel.layer.shadowRadius = 2
        titleLabel.layer.shadowOffset = .zero
        shadowView.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 9, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        subtitleLabel.numberOfLines = 1
        subtitleLabel.layer.shadowColor = UIColor.black.cgColor
        subtitleLabel.layer.shadowOpacity = 0.8
        subtitleLabel.layer.shadowRadius = 2
        subtitleLabel.layer.shadowOffset = .zero
        shadowView.addSubview(subtitleLabel)

        playButton.tintColor = .white
        playButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        playButton.layer.cornerRadius = 15
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        playButton.isHidden = true
        shadowView.addSubview(playButton)

        likeButton.tintColor = .white
        likeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        likeButton.layer.cornerRadius = 15
        likeButton.setImage(UIImage(systemName: "heart"), for: .normal)
        likeButton.addTarget(self, action: #selector(likeButtonTapped), for: .touchUpInside)
        likeButton.isHidden = true
        shadowView.addSubview(likeButton)

        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.28)
        progressTrack.isHidden = true
        shadowView.addSubview(progressTrack)
        progressFill.backgroundColor = .white
        progressTrack.addSubview(progressFill)

        // 角标改真按钮（DS26 Q4）：此前是纯指示图、点不动，被 Miller
        // 直接点名。点按 = 回网页播放页（VC 处理）。
        playingBadge.setImage(UIImage(systemName: "speaker.wave.2.fill"), for: .normal)
        playingBadge.tintColor = .white
        playingBadge.layer.shadowColor = UIColor.black.cgColor
        playingBadge.layer.shadowOpacity = 0.8
        playingBadge.layer.shadowRadius = 2
        playingBadge.layer.shadowOffset = .zero
        playingBadge.addTarget(self, action: #selector(badgeButtonTapped), for: .touchUpInside)
        playingBadge.isHidden = true
        shadowView.addSubview(playingBadge)

        playSpinner.color = .white
        playSpinner.hidesWhenStopped = true
        playSpinner.isHidden = true
        shadowView.addSubview(playSpinner)

        errorLabel.font = .systemFont(ofSize: 10, weight: .medium)
        errorLabel.textColor = .white
        errorLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        errorLabel.layer.cornerRadius = 4
        errorLabel.clipsToBounds = true
        errorLabel.textAlignment = .center
        errorLabel.isHidden = true
        errorLabel.isUserInteractionEnabled = true
        errorLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(playButtonTapped)))
        shadowView.addSubview(errorLabel)

        for label in lyricLabels {
            label.textAlignment = .center
            label.textColor = .white
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.85
            label.layer.shadowRadius = 2
            label.layer.shadowOffset = .zero
            label.isHidden = true
            shadowView.addSubview(label)
        }
    }

    @objc private func playButtonTapped() { onPlayTap?() }
    @objc private func likeButtonTapped() { onLikeTap?() }
    @objc private func badgeButtonTapped() { onBadgeTap?() }

    /// 播放态配置（VC 在 cellForItem 与播放状态变化时调用）：展开卡
    /// 显示控件行 + 进度，当前曲目显示角标，播放/暂停与红心按实况；
    /// loadState 驱动三态（连接中转圈盖住播放键、失败出文案条）。
    func configurePlayback(expanded: Bool, isCurrent: Bool, isPlaying: Bool,
                           liked: Bool, progress: Double,
                           loadState: WallPlayLoadState = .idle) {
        controlsVisible = expanded
        playButton.isHidden = !expanded
        likeButton.isHidden = !expanded
        progressTrack.isHidden = !expanded
        playingBadge.isHidden = !isCurrent
        progressValue = progress
        playButton.setImage(
            UIImage(systemName: isCurrent && isPlaying ? "pause.fill" : "play.fill"),
            for: .normal)
        if loadState.isConnecting {
            playButton.setImage(nil, for: .normal)
            if expanded { playSpinner.startAnimating() }
        } else {
            playSpinner.stopAnimating()
        }
        playSpinner.isHidden = !(expanded && loadState.isConnecting)
        if case .failed(let message) = loadState {
            errorLabel.text = message
            errorLabel.isHidden = !expanded
        } else {
            errorLabel.isHidden = true
        }
        // 收起卡不留歌词残影（展开态由 VC 的心跳重新刷入）。
        if !expanded { setLyricWindow([]) }
        setLiked(liked)
        setNeedsLayout()
    }

    /// 滚动歌词 5 行窗口（中间 = 当前行）：空/全空行 = 整组收起。
    func setLyricWindow(_ lines: [String]) {
        let hasContent = lines.contains { !$0.isEmpty }
        let alphas: [CGFloat] = [0.35, 0.55, 1.0, 0.55, 0.35]
        for (i, label) in lyricLabels.enumerated() {
            label.isHidden = !hasContent
            guard hasContent else { continue }
            label.text = i < lines.count ? lines[i] : ""
            let isCenter = i == 2
            label.font = .systemFont(ofSize: isCenter ? 12.5 : 10.5,
                                     weight: isCenter ? .semibold : .regular)
            label.alpha = alphas[i]
        }
    }

    func setLiked(_ liked: Bool) {
        likeButton.setImage(
            UIImage(systemName: liked ? "heart.fill" : "heart"), for: .normal)
        likeButton.tintColor = liked ? .systemRed : .white
    }

    /// 进度条热更新（VC 的 0.3 秒计时器只打这一处，不整表刷新）。
    func updateProgress(_ progress: Double) {
        progressValue = progress
        layoutProgressFill()
    }

    private func layoutProgressFill() {
        let w = progressTrack.bounds.width
        progressFill.frame = CGRect(
            x: 0, y: 0,
            width: w * CGFloat(max(0, min(1, progressValue))),
            height: progressTrack.bounds.height)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        shadowView.frame = contentView.bounds
        shadowView.layer.shadowPath = UIBezierPath(
            roundedRect: contentView.bounds, cornerRadius: 8).cgPath
        imageView.frame = shadowView.bounds
        let bounds = shadowView.bounds
        // 展开卡底部让位：进度条 3 + 控件行 34，标题/副行整体上移。
        let bottomInset: CGFloat = controlsVisible ? 41 : 4
        let labelHeight: CGFloat = 16
        let hasSubtitle = !(subtitleLabel.text ?? "").isEmpty
        let titleY = bounds.height - bottomInset - labelHeight - (hasSubtitle ? 13 : 0)
        titleLabel.frame = CGRect(
            x: 6, y: titleY,
            width: bounds.width - 12, height: labelHeight)
        subtitleLabel.frame = CGRect(
            x: 6, y: bounds.height - bottomInset - 13,
            width: bounds.width - 12, height: 12)
        subtitleLabel.isHidden = !hasSubtitle
        if controlsVisible {
            let barTop = bounds.height - 37
            playButton.frame = CGRect(x: 8, y: barTop + 2, width: 30, height: 30)
            likeButton.frame = CGRect(x: bounds.width - 38, y: barTop + 2, width: 30, height: 30)
            progressTrack.frame = CGRect(x: 0, y: bounds.height - 3, width: bounds.width, height: 3)
            layoutProgressFill()
            playSpinner.frame = playButton.frame
            errorLabel.frame = CGRect(x: 6, y: barTop - 19,
                                      width: bounds.width - 12, height: 15)
        }
        // 滚动歌词：5 行窗口居卡片中上部（避开底部标题与控件行）。
        let lyricRowH: CGFloat = 15
        let lyricTop = bounds.height * 0.40 - lyricRowH * 2.5
        for (i, label) in lyricLabels.enumerated() {
            label.frame = CGRect(x: 10, y: lyricTop + CGFloat(i) * lyricRowH,
                                 width: bounds.width - 20, height: lyricRowH)
        }
        playingBadge.frame = CGRect(x: bounds.width - 30, y: 4, width: 24, height: 24)
    }

    /// 按压反馈：轻微缩放（原生点击手感的最低成本件）。
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.contentView.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    func configure(entry: WallPrototypeViewController.Entry, tier: Int) {
        titleLabel.text = entry.title
        subtitleLabel.text = entry.subtitle
        setNeedsLayout()
        loadTask?.cancel()
        guard let pic = entry.picUrl,
              let urlString = NativeCoverLoader.shared.proxiedURLString(pic, tier: tier) else {
            currentUrl = nil
            imageView.image = nil
            stopPlaceholderPulse()
            return
        }
        currentUrl = urlString
        // 缓存命中同步上图：reloadData/复用重建时不先清空、不异步等一帧，
        // 这是拖动闪黑的主修复。
        if let cached = NativeCoverLoader.shared.cachedImage(for: urlString) {
            stopPlaceholderPulse()
            imageView.image = cached
            return
        }
        imageView.image = nil
        startPlaceholderPulse()
        loadTask = Task { [weak self] in
            let image = await NativeCoverLoader.shared.image(for: urlString, tier: tier)
            guard let self else { return }
            await MainActor.run {
                guard self.currentUrl == urlString else { return }
                self.stopPlaceholderPulse()
                self.imageView.image = image
            }
        }
    }

    /// 未出图占位的呼吸微光（Miller 定：加载不能干等）：只在无图且
    /// 加载在途时跑；图片到达、加载失败（image 为 nil 时同样停）、
    /// cell 复用时都停，不留常驻动画。
    private func startPlaceholderPulse() {
        guard imageView.layer.animation(forKey: "foliaPulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.55
        pulse.toValue = 0.92
        pulse.duration = 1.05
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageView.layer.add(pulse, forKey: "foliaPulse")
    }

    private func stopPlaceholderPulse() {
        imageView.layer.removeAnimation(forKey: "foliaPulse")
    }

    /// 首现淡入（每条目每进程一次）：alpha + 0.97→1 轻缩放；
    /// delay 由 VC 的首屏波次调度给出（总时长 ≤0.45 秒）。
    func playEntranceIfNeeded(key: String, delay: TimeInterval = 0) {
        guard !key.isEmpty, !Self.entranceSeen.contains(key) else { return }
        Self.entranceSeen.insert(key)
        contentView.alpha = 0
        contentView.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        UIView.animate(withDuration: 0.32, delay: delay, options: [.curveEaseOut]) {
            self.contentView.alpha = 1
            self.contentView.transform = .identity
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentUrl = nil
        imageView.image = nil
        stopPlaceholderPulse()
        contentView.alpha = 1
        contentView.transform = .identity
        titleLabel.text = nil
        subtitleLabel.text = nil
        onPlayTap = nil
        onLikeTap = nil
        onBadgeTap = nil
        controlsVisible = false
        playButton.isHidden = true
        likeButton.isHidden = true
        progressTrack.isHidden = true
        playingBadge.isHidden = true
        playSpinner.stopAnimating()
        playSpinner.isHidden = true
        errorLabel.isHidden = true
        errorLabel.text = nil
        for label in lyricLabels { label.isHidden = true; label.text = nil }
        progressValue = 0
    }
}
