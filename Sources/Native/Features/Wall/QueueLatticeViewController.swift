import UIKit
import Combine

/// 3.7 (71) Lattice 队列拼贴（原生新写 MVP，路线评估
/// lattice-route-eval-2026-11-21 第九节 C2 交付范围）：整条播放
/// 队列铺成海报墙——有限有序网格（WallLayout.finiteQueueMode，
/// 128 方块/pitch 136/overscan 500，port-spec-lattice 第一节）、
/// 左上序号牌（当前曲 accent）、底部歌名/歌手、按播放头分段
/// （played 压暗/now accent/upcoming 原样）。
///
/// 数据语义：打开时取 QueueManager 队列快照定死为本页数据源
/// （cell 只读本页快照、不直读管理器，防数据源时序错位）；
/// $queue 变更（加/删/换序）经 dataVersion 显式整墙刷新，
/// $currentIndex 只做定向刷牌——只重配受影响的可见 cell，
/// 严禁入布局指纹、严禁触发 refreshInstances 全量重算
/// （(59) 冻结教训的硬约束，见 WallLayout 类头注）。
///
/// 交互：点块先展开（原位放大＋底部 lattice-chrome 播放条）、
/// 双击直播、定位当前曲（墙相机弹簧平移）、返回两段式
/// （先收展开再退出）。砍掉/后置面（暗角/海报灯光/染色/
/// 只标当前序号/块右上快捷钮/展开条可配槽）见交付报告。
final class QueueLatticeViewController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegate, UIScrollViewDelegate {

    /// 统一落点：主页墙路由（.lattice 档）、缝合工具条「拼」格、
    /// 命令面板 navigate-lattice 三入口共用。
    static func present(from host: UIViewController) {
        var top = host
        while let presented = top.presentedViewController { top = presented }
        guard top.presentedViewController == nil else { return }
        let vc = QueueLatticeViewController()
        vc.modalPresentationStyle = .fullScreen
        Breadcrumbs.log("lattice.open")
        top.present(vc, animated: true)
    }

    // MARK: - 状态

    /// 本页队列快照（打开定死、$queue 变更时整表替换）。
    private var tracks: [FoliaTrack] = []
    /// 播放头（快照内下标；无队列/未定位为 -1）。只驱动刷牌。
    private var currentIndex: Int = -1
    /// 快照代次：内容变更时递增并同步给布局 dataVersion。
    private var snapshotVersion = 0

    private let wallLayout = WallLayout()
    private var collectionView: UICollectionView!
    private let scrollMetrics = WallScrollMetrics(wallName: "lattice")
    private var cancellables = Set<AnyCancellable>()
    private var didCenterCamera = false
    private var isWrapping = false
    private var expandedIndex: Int?

    private let backButton = UIButton(type: .system)
    private let locateButton = UIButton(type: .system)
    private let emptyStack = UIStackView()
    private let chrome = LatticeChromeView()

    // 定位飞行（与曲目墙 locate 同弹簧口径：ζ=0.85、ω=6）。
    private var locateLink: CADisplayLink?
    private var locateStartOrigin = CGPoint.zero
    private var locateTargetOrigin = CGPoint.zero
    private var locateStartTime: CFTimeInterval = 0
    private var locateDuration: TimeInterval = 0.6
    private var locateTargetIndex = -1

    private var rotationGeneration = 0

    // MARK: - 生命周期

    /// (78) 第 7 条宠物登顶（Miller 00:31 拍板）：本页同样
    /// refront 岛镜像宠物层，隐藏状态栏（系统时间）让宠物
    /// 占顶部带完整显示。安全区顶恒 59pt、既有布局不跳位。
    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.035, alpha: 1)

        wallLayout.finiteQueueMode = true
        wallLayout.totalEntries = 0

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: wallLayout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.allowsSelection = false
        collectionView.register(QueueLatticeCell.self,
                                forCellWithReuseIdentifier: QueueLatticeCell.reuseId)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        collectionView.addGestureRecognizer(doubleTap)
        collectionView.addGestureRecognizer(singleTap)

        configureToolButton(backButton, symbol: "chevron.left",
                            label: "返回", action: #selector(backTapped))
        configureToolButton(locateButton, symbol: "scope",
                            label: "定位正在播放", action: #selector(locateTapped))
        view.addSubview(backButton)
        view.addSubview(locateButton)

        // 空态（port-spec 第一条）：居中两行。
        let emptyTitle = UILabel()
        emptyTitle.text = "队列是空的"
        emptyTitle.font = .systemFont(ofSize: 17, weight: .medium)
        emptyTitle.textColor = .white
        let emptyHint = UILabel()
        emptyHint.text = "开始播放任意歌曲后，队列会在这里铺开。"
        emptyHint.font = .systemFont(ofSize: 12)
        emptyHint.textColor = UIColor.white.withAlphaComponent(0.5)
        emptyHint.numberOfLines = 0
        emptyHint.textAlignment = .center
        emptyStack.axis = .vertical
        emptyStack.spacing = 8
        emptyStack.alignment = .center
        emptyStack.addArrangedSubview(emptyTitle)
        emptyStack.addArrangedSubview(emptyHint)
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyStack.isHidden = true
        view.addSubview(emptyStack)

        chrome.isHidden = true
        chrome.alpha = 0
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.onPlayPause = { [weak self] in self?.chromePlayPause() }
        chrome.onPrev = { QueueManager.shared.playPrevious() }
        chrome.onNext = { QueueManager.shared.playNext(manual: true) }
        chrome.onOpenPlayer = { [weak self] in self?.openStageFromLattice() }
        chrome.onSeek = { fraction in
            let engine = PlaybackEngine.shared
            guard engine.duration > 0 else { return }
            engine.seek(to: fraction * engine.duration)
            Breadcrumbs.log("lattice.seek")
        }
        view.addSubview(chrome)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backButton.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            backButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            locateButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            locateButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            locateButton.widthAnchor.constraint(equalToConstant: 44),
            locateButton.heightAnchor.constraint(equalToConstant: 44),
            emptyStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyStack.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 打开快照定死 + 订阅（播放头 live、内容变更显式刷新）。
        applySnapshot(QueueManager.shared.queue,
                      current: QueueManager.shared.currentIndex, initial: true)
        QueueManager.shared.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                guard let self else { return }
                self.applySnapshot(queue, current: QueueManager.shared.currentIndex,
                                   initial: false)
            }
            .store(in: &cancellables)
        QueueManager.shared.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in self?.applyCurrentIndex(index) }
            .store(in: &cancellables)
        PlaybackEngine.shared.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self else { return }
                self.enginePlaying = playing
                self.chrome.refreshPlayGlyph()
                // (72)：播放/暂停翻转要即时落到 now 环的呼吸
                // 态上（此前只有 chrome 字形刷新、tile 不动）。
                self.refreshVisiblePlaybackStates()
            }
            .store(in: &cancellables)
    }

    /// 引擎播放态（(72)：now 环呼吸的驱动源，订阅回主线程写）。
    private var enginePlaying = PlaybackEngine.shared.isPlaying

    /// 可见 cell 播放态全量重配（段位/当前/呼吸）：只动覆层，
    /// 不碰布局与封面。$currentIndex 定向刷牌与 $isPlaying
    /// 翻转共用。
    private func refreshVisiblePlaybackStates() {
        for cell in collectionView.visibleCells {
            guard let latticeCell = cell as? QueueLatticeCell,
                  let item = collectionView.indexPath(for: cell)?.item,
                  item < wallLayout.instances.count else { continue }
            let queueIndex = wallLayout.instances[item].queueIndex
            latticeCell.applyPlaybackState(
                ordinal: queueIndex + 1,
                isCurrent: queueIndex == currentIndex,
                segment: segment(for: queueIndex),
                playing: enginePlaying)
        }
    }

    /// (72) 状态映射自证：当前下标 + 可见区里 now/played 的
    /// 实际落点计数。下一份真机日志凭此一行判「状态没映射
    /// 上」还是「映射上了但看不见」。
    private func logLatticeState() {
        var nowVisible = 0
        var playedVisible = 0
        for cell in collectionView.visibleCells {
            guard let item = collectionView.indexPath(for: cell)?.item,
                  item < wallLayout.instances.count else { continue }
            let queueIndex = wallLayout.instances[item].queueIndex
            if queueIndex == currentIndex { nowVisible += 1 }
            if segment(for: queueIndex) == .played { playedVisible += 1 }
        }
        Breadcrumbs.log("lattice.state cur=\(currentIndex)"
            + " nowVis=\(nowVisible) playedVis=\(playedVisible)")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Breadcrumbs.samplerStart()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Breadcrumbs.samplerStop()
        locateLink?.invalidate()
        locateLink = nil
        chrome.stopProgressDriver()
    }

    private func configureToolButton(_ button: UIButton, symbol: String,
                                     label: String, action: Selector) {
        button.setImage(UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)),
            for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 22
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    // MARK: - 快照与播放头（定向刷牌）

    /// 内容面：快照与现队列不一致才整表替换（id 序列比对）；
    /// 一致时只同步播放头（$queue 与 $currentIndex 常同批到达，
    /// 避免一次切歌走两条刷新路）。
    private func applySnapshot(_ queue: [FoliaTrack], current: Int, initial: Bool) {
        let sameContent = queue.count == tracks.count
            && zip(queue, tracks).allSatisfy { $0.id == $1.id }
        if sameContent && !initial {
            applyCurrentIndex(current)
            return
        }
        tracks = queue
        currentIndex = queue.indices.contains(current) ? current : -1
        snapshotVersion += 1
        wallLayout.totalEntries = tracks.count
        wallLayout.dataVersion = snapshotVersion
        if let expanded = expandedIndex, !tracks.indices.contains(expanded) {
            expandedIndex = nil
            wallLayout.expandedInstanceId = nil
            updateChromeVisibility(animated: false)
        }
        emptyStack.isHidden = !tracks.isEmpty
        locateButton.isEnabled = currentIndex >= 0
        locateButton.alpha = currentIndex >= 0 ? 1 : 0.4
        Breadcrumbs.log("lattice.snap n=\(tracks.count) cur=\(currentIndex) v=\(snapshotVersion)")
        if !didCenterCamera {
            // 空队列打开时定心被 totalEntries 守卫挡下；队列
            // 后到时在此补定心（viewDidLayoutSubviews 不保证
            // 再被调用）。
            centerCameraIfNeeded()
        }
        if didCenterCamera {
            if wallLayout.refreshInstances() {
                collectionView.reloadData()
            } else {
                wallLayout.invalidateLayout()
                collectionView.reloadData()
            }
        }
        logLatticeState()
        syncChrome()
    }

    /// 播放头面（硬约束落点）：只重配可见 cell 中段位/当前态
    /// 发生变化者——不碰布局、不 reloadData、不触发
    /// refreshInstances。切歌跨度大时逐个可见 cell 按现播放头
    /// 复算段位，仍只是 cell 级重配。
    private func applyCurrentIndex(_ index: Int) {
        let valid = tracks.indices.contains(index) ? index : -1
        guard valid != currentIndex else { syncChrome(); return }
        currentIndex = valid
        locateButton.isEnabled = valid >= 0
        locateButton.alpha = valid >= 0 ? 1 : 0.4
        refreshVisiblePlaybackStates()
        logLatticeState()
        syncChrome()
    }

    private func segment(for queueIndex: Int) -> QueueLatticeCell.Segment {
        guard currentIndex >= 0 else { return .upcoming }
        if queueIndex < currentIndex { return .played }
        if queueIndex == currentIndex { return .now }
        return .upcoming
    }

    // MARK: - 相机（有限场钳制＋增量折叠，(59) 纪律同款）

    static func cameraScale(forWidth width: CGFloat) -> Double {
        if width < 640 { return 0.52 }
        if width < 1100 { return 0.64 }
        return 0.76
    }

    /// 有限场相机钳制：可见世界窗必须留在场内（每边放一格的
    /// 橡皮余量）；场小于视口的轴固定居中。硬停不回弹——与
    /// 周期墙的无限平移差别在此，属有限语义本身。
    private func clampedOrigin(_ proposed: CGPoint) -> CGPoint {
        let size = collectionView.bounds.size
        guard size.width > 0, size.height > 0, wallLayout.totalEntries > 0 else { return proposed }
        let field = wallLayout.finiteField(viewSize: size)
        let scale = wallLayout.cameraScale
        let viewWorldW = Double(size.width) / scale
        let viewWorldH = Double(size.height) / scale
        let margin = wallLayout.metrics.pitch
        func clampAxis(_ value: Double, fieldMin: Double, fieldExtent: Double,
                       viewExtent: Double) -> Double {
            if fieldExtent <= viewExtent {
                return fieldMin - (viewExtent - fieldExtent) / 2
            }
            return min(max(value, fieldMin - margin),
                       fieldMin + fieldExtent - viewExtent + margin)
        }
        return CGPoint(
            x: clampAxis(Double(proposed.x), fieldMin: field.x,
                         fieldExtent: field.width, viewExtent: viewWorldW),
            y: clampAxis(Double(proposed.y), fieldMin: field.y,
                         fieldExtent: field.height, viewExtent: viewWorldH))
    }

    private func centerCameraIfNeeded() {
        // bounds 为零（viewDidLoad 阶段）时不定心：零尺寸算出的
        // 原点/单元都是错值且 didCenterCamera 一旦置位不再重算；
        // 真尺寸到达后 viewDidLayoutSubviews 会再调本函数。
        guard !didCenterCamera, wallLayout.totalEntries > 0,
              collectionView.bounds.width > 0, collectionView.bounds.height > 0
        else { return }
        didCenterCamera = true
        wallLayout.cameraScale = Self.cameraScale(forWidth: collectionView.bounds.width)
        let cell = wallLayout.cellViewSize
        collectionView.contentOffset = CGPoint(x: cell.width, y: cell.height)
        // 首帧落点：有当前曲先对准当前曲格，否则场心。
        let size = collectionView.bounds.size
        let scale = wallLayout.cameraScale
        var target = CGPoint(x: 0, y: 0)
        if let rect = currentIndex >= 0
            ? wallLayout.finiteRect(forIndex: currentIndex, viewSize: size) : nil {
            target = CGPoint(
                x: rect.x + rect.width / 2 - Double(size.width) / scale / 2,
                y: rect.y + rect.height / 2 - Double(size.height) / scale / 2)
        } else {
            let field = wallLayout.finiteField(viewSize: size)
            target = CGPoint(
                x: field.x + field.width / 2 - Double(size.width) / scale / 2,
                y: field.y + field.height / 2 - Double(size.height) / scale / 2)
        }
        wallLayout.worldOrigin = clampedOrigin(target)
        wallLayout.refreshInstances()
        collectionView.reloadData()
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
        let scrollStart = CACurrentMediaTime()
        isWrapping = true
        let proposed = CGPoint(
            x: wallLayout.worldOrigin.x + delta.x / CGFloat(wallLayout.cameraScale),
            y: wallLayout.worldOrigin.y + delta.y / CGFloat(wallLayout.cameraScale))
        wallLayout.worldOrigin = clampedOrigin(proposed)
        scrollView.contentOffset = center
        // (59) 同款：身份变了才 reloadData，同键只失效布局换帧。
        let identityChanged = wallLayout.refreshInstances()
        if identityChanged {
            scrollMetrics.noteIdentityChanged()
            collectionView.reloadData()
            scrollMetrics.noteReloadData()
        } else {
            wallLayout.invalidateLayout()
        }
        isWrapping = false
        scrollMetrics.noteScrollActivity(
            layout: wallLayout,
            didScrollMs: (CACurrentMediaTime() - scrollStart) * 1000,
            panDelta: delta)
    }

    // MARK: - 数据源

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        wallLayout.instances.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: QueueLatticeCell.reuseId, for: indexPath) as! QueueLatticeCell
        let instance = wallLayout.instances[indexPath.item]
        guard instance.queueIndex < tracks.count else {
            cell.configureEmpty()
            return cell
        }
        let track = tracks[instance.queueIndex]
        let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
        let pixelExtent = Double(max(frame.width, frame.height)) * Double(UIScreen.main.scale)
        cell.configure(track: track, pixelExtent: pixelExtent)
        cell.applyPlaybackState(
            ordinal: instance.queueIndex + 1,
            isCurrent: instance.queueIndex == currentIndex,
            segment: segment(for: instance.queueIndex),
            playing: enginePlaying)
        return cell
    }

    // MARK: - 点按：展开/收起/双击直播

    private func queueIndex(at point: CGPoint) -> Int? {
        guard let indexPath = collectionView.indexPathForItem(at: point),
              indexPath.item < wallLayout.instances.count else { return nil }
        let queueIndex = wallLayout.instances[indexPath.item].queueIndex
        return tracks.indices.contains(queueIndex) ? queueIndex : nil
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: collectionView)
        guard let queueIndex = queueIndex(at: point) else {
            if expandedIndex != nil { setExpanded(nil) }
            return
        }
        if expandedIndex == queueIndex {
            setExpanded(nil)
        } else {
            setExpanded(queueIndex)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: collectionView)
        guard let queueIndex = queueIndex(at: point) else { return }
        // 双击正在播的块只恢复永不暂停（port-spec 第一条）。
        guard queueIndex != currentIndex else {
            Breadcrumbs.log("lattice.tile dbl cur=\(queueIndex)")
            return
        }
        Breadcrumbs.log("lattice.tile dbl play=\(queueIndex)")
        QueueManager.shared.playAtIndex(queueIndex)
    }

    /// 展开态切换：布局展开位（键含展开态、窗口集不变 → 身份
    /// 不变只失效布局）＋ chrome 显隐。展开中禁 rebase 由布局
    /// 既有口径承担（展开实例钉入新集）。
    private func setExpanded(_ index: Int?) {
        expandedIndex = index
        wallLayout.expandedInstanceId = index.map { "q\($0)" }
        if wallLayout.refreshInstances() {
            collectionView.reloadData()
        } else {
            wallLayout.invalidateLayout()
        }
        // 展开块的文案字号随帧变（cell 在 layoutSubviews 按帧宽
        // 推导），帧变经布局失效自然重排；此处只补一轮可见 cell
        // 状态重配，保证序号牌/段位与展开帧同步。
        refreshVisiblePlaybackStates()
        Breadcrumbs.log("lattice.tile exp=\(index ?? -1)")
        updateChromeVisibility(animated: true)
        syncChrome()
    }

    // MARK: - lattice-chrome 播放条

    private func updateChromeVisibility(animated: Bool) {
        let show = expandedIndex != nil
        if show {
            chrome.isHidden = false
            chrome.startProgressDriver()
        }
        let animations = {
            self.chrome.alpha = show ? 1 : 0
            self.chrome.transform = show ? .identity
                : CGAffineTransform(translationX: 0, y: 12)
        }
        if animated {
            UIView.animate(withDuration: 0.32, delay: 0,
                           usingSpringWithDamping: 0.88, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState], animations: animations) { _ in
                // 竞态守卫：被后续展开打断的收起动画，其
                // completion 不许按旧状态误藏（按当前展开态判）。
                if !show, self.expandedIndex == nil {
                    self.chrome.isHidden = true
                    self.chrome.stopProgressDriver()
                }
            }
        } else {
            animations()
            chrome.isHidden = !show
            if !show { chrome.stopProgressDriver() }
        }
    }

    /// chrome 状态同步点：展开块曲目/是否当前曲一处传入，
    /// 快照/播放头/展开三路变化都经此刷新（播放字形由引擎
    /// $isPlaying 订阅另行保鲜）。
    private func syncChrome() {
        let track = expandedIndex.flatMap {
            tracks.indices.contains($0) ? tracks[$0] : nil
        }
        chrome.configure(expandedTrack: track,
                         isCurrent: expandedIndex != nil && expandedIndex == currentIndex)
    }

    private func chromePlayPause() {
        guard let expanded = expandedIndex else { return }
        if expanded == currentIndex {
            PlaybackEngine.shared.togglePlayPause()
        } else {
            QueueManager.shared.playAtIndex(expanded)
        }
        chrome.refreshPlayGlyph()
    }

    /// 「打开播放器」：走既有开台路（舞台全屏 present，与主页
    /// 墙 openNativeStageFromHome 同形态）。
    private func openStageFromLattice() {
        Breadcrumbs.log("lattice.chrome open=stage")
        let stage = StageViewController()
        stage.modalPresentationStyle = .fullScreen
        present(stage, animated: true)
    }

    // MARK: - 定位当前曲

    @objc private func locateTapped() {
        guard currentIndex >= 0,
              let rect = wallLayout.finiteRect(forIndex: currentIndex,
                                               viewSize: collectionView.bounds.size)
        else { return }
        let size = collectionView.bounds.size
        let scale = wallLayout.cameraScale
        let target = clampedOrigin(CGPoint(
            x: rect.x + rect.width / 2 - Double(size.width) / scale / 2,
            y: rect.y + rect.height / 2 - Double(size.height) / scale / 2))
        let distance = hypot(target.x - wallLayout.worldOrigin.x,
                             target.y - wallLayout.worldOrigin.y)
        locateTargetIndex = currentIndex
        animateWorldOrigin(to: target,
                           duration: min(max(distance / 1400, 0.35), 0.9)) { [weak self] in
            guard let self else { return }
            // 落点自证：目标格入窗且其实例在实例集内。
            let landed = self.wallLayout.instances.contains {
                $0.queueIndex == self.locateTargetIndex
            }
            Breadcrumbs.log("lattice.focus idx=\(self.locateTargetIndex) ok=\(landed ? 1 : 0)")
        }
    }

    private func animateWorldOrigin(to target: CGPoint, duration: TimeInterval,
                                    completion: @escaping () -> Void) {
        locateLink?.invalidate()
        locateStartOrigin = wallLayout.worldOrigin
        locateTargetOrigin = target
        locateDuration = duration
        locateStartTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(locateTick(_:)))
        link.add(to: .main, forMode: .common)
        locateLink = link
        locateCompletion = completion
    }

    private var locateCompletion: (() -> Void)?

    /// 弹簧进度（与曲目墙 locateSpringProgress 同式：ζ=0.85、
    /// ω=6 的欠阻尼阶跃响应，末端自然减速、raw≥1 精确吸附）。
    private static func locateSpringProgress(_ raw: Double) -> Double {
        guard raw > 0 else { return 0 }
        guard raw < 1 else { return 1 }
        let zeta = 0.85
        let omega = 6.0
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        let envelope = exp(-zeta * omega * raw)
        let ratio = zeta / (1 - zeta * zeta).squareRoot()
        return 1 - envelope * (cos(omegaD * raw) + ratio * sin(omegaD * raw))
    }

    @objc private func locateTick(_ link: CADisplayLink) {
        let raw = min((link.timestamp - locateStartTime) / locateDuration, 1)
        let eased = Self.locateSpringProgress(raw)
        wallLayout.worldOrigin = CGPoint(
            x: locateStartOrigin.x + (locateTargetOrigin.x - locateStartOrigin.x) * CGFloat(eased),
            y: locateStartOrigin.y + (locateTargetOrigin.y - locateStartOrigin.y) * CGFloat(eased))
        if FoliaMotion62.reduced(.queueCollage) {
            collectionView.transform = .identity
        } else {
            let bell = CGFloat(eased * (1 - eased) * 4)
            collectionView.transform = CGAffineTransform(
                scaleX: 1 + 0.03 * bell, y: 1 + 0.03 * bell)
        }
        if wallLayout.refreshInstances() {
            collectionView.reloadData()
        } else {
            wallLayout.invalidateLayout()
        }
        if raw >= 1 {
            link.invalidate()
            locateLink = nil
            wallLayout.worldOrigin = locateTargetOrigin
            wallLayout.refreshInstances()
            wallLayout.invalidateLayout()
            collectionView.transform = .identity
            let done = locateCompletion
            locateCompletion = nil
            done?()
        }
    }

    // MARK: - 返回（两段式：先收展开、再退出）

    @objc private func backTapped() {
        if expandedIndex != nil {
            setExpanded(nil)
            return
        }
        dismiss(animated: true)
    }

    // MARK: - 旋转（墙旋转冻结纪律：动画期间零重算、落地收尾）

    override func viewWillTransition(to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard viewIfLoaded != nil, collectionView != nil else { return }
        let fromSize = view.bounds.size
        guard size != fromSize else { return }
        rotationGeneration += 1
        let generation = rotationGeneration
        wallLayout.setRotationFrozen(true)
        // (73) 岛层守护转场期暂停（同主页墙）。
        PetIslandLayer.setRefrontSuspended(true)
        Breadcrumbs.log("lattice.rotate freeze gen=\(generation)")
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            // (73) 重排提前到转场首帧（同主页墙 (73) 注）：
            // 本墙的缩放档随新宽重定原本压在 completion——
            // 落定帧整墙换档即肉眼「再放大」；提前到首帧后
            // 新档随转场刚性旋转呈现，落定无尺度跳变。
            guard generation == self.rotationGeneration else { return }
            self.wallLayout.setRotationFrozen(false)
            // 缩放档随新宽重定、偏移重钉中心单元、原点按新
            // 场钳制——网格列数随新宽高比重排（键含尺寸类
            // 别，失效后 prepare 自动重算）。
            self.wallLayout.cameraScale = Self.cameraScale(forWidth: size.width)
            let cell = self.wallLayout.cellViewSize
            self.collectionView.contentOffset = CGPoint(x: cell.width, y: cell.height)
            self.wallLayout.worldOrigin = self.clampedOrigin(self.wallLayout.worldOrigin)
            self.wallLayout.invalidateLayout()
            if self.wallLayout.lastIdentityChanged {
                self.collectionView.reloadData()
            }
        }) { [weak self] _ in
            guard let self else { return }
            PetIslandLayer.setRefrontSuspended(false)
            PetIslandLayer.shared.refrontIfNeeded()
            guard generation == self.rotationGeneration else {
                Breadcrumbs.log("lattice.rotate stale gen=\(generation)")
                return
            }
            Breadcrumbs.log("lattice.rotate land gen=\(generation)"
                + " instances=\(self.wallLayout.instances.count)")
        }
    }
}

// MARK: - 队列 tile cell（port-spec 第一条的原生换算）

/// 封面全幅（直角）→ 底部渐变罩 → 左上序号牌 → 底部歌名/歌手。
/// 字号按规格 px 与格宽 128 的比值等比换算到帧宽：歌名比
/// 0.21（规格 clamp 22–36px）、歌手比 0.10（规格 13px）；
/// 歌手等比值在手机帧宽下约 6.7pt 低于可读下限，钳 10pt
/// （iOS 适配自查记明）。展开帧（宽 >100pt）换展开档比值
/// （歌名规格 clamp 48–82px ÷ 展开边 264）。
final class QueueLatticeCell: UICollectionViewCell {

    static let reuseId = "QueueLatticeCell"

    enum Segment { case played, now, upcoming }

    private let coverView = UIImageView()
    private let dimView = UIView()
    /// (72) 正在播放的「亮」：accent 描边环 + 光晕 + 播放中
    /// 呼吸。(71) 验收不过的根因之一：now 态此前只有序号牌
    /// 数字染色，tile 本体毫无变化，肉眼等于没亮。本环为独
    /// 立覆层（在文案之上、环外发光靠 shadow），isCurrent
    /// 才显。
    private let ringView = UIView()
    private let gradientView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let badgeView = UIView()
    private let badgeLabel = UILabel()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private var loadTask: Task<Void, Never>?
    private var currentUrl: String?
    private var trackId: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor(white: 0.13, alpha: 1)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.backgroundColor = UIColor(white: 0.13, alpha: 1)
        contentView.addSubview(coverView)

        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.isUserInteractionEnabled = false
        contentView.addSubview(dimView)

        ringView.isUserInteractionEnabled = false
        ringView.isHidden = true
        ringView.layer.borderWidth = 3
        ringView.layer.cornerRadius = 12
        ringView.layer.shadowOffset = .zero
        ringView.layer.shadowRadius = 10
        ringView.layer.shadowOpacity = 0.55
        contentView.addSubview(ringView)

        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.55).cgColor,
        ]
        gradientLayer.locations = [0.45, 1.0]
        gradientView.layer.addSublayer(gradientLayer)
        gradientView.isUserInteractionEnabled = false
        contentView.addSubview(gradientView)

        badgeView.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        badgeView.isUserInteractionEnabled = false
        contentView.addSubview(badgeView)
        badgeLabel.font = .systemFont(ofSize: 10, weight: .heavy)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeView.addSubview(badgeLabel)

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.numberOfLines = 3
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.shadowColor = UIColor.black.withAlphaComponent(0.6)
        titleLabel.shadowOffset = CGSize(width: 0, height: 1)
        titleLabel.layer.shadowRadius = 3
        contentView.addSubview(titleLabel)

        artistLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        artistLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        artistLabel.numberOfLines = 1
        artistLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(artistLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentUrl = nil
        trackId = nil
        coverView.image = nil
        // (72)：播放态覆层随复用清零，防串到下一首的 tile。
        dimView.alpha = 0
        ringView.isHidden = true
        ringView.layer.removeAnimation(forKey: "foliaNowPulse")
    }

    func configureEmpty() {
        loadTask?.cancel()
        coverView.image = nil
        titleLabel.text = nil
        artistLabel.text = nil
        badgeLabel.text = nil
    }

    /// 封面走共用 NativeCoverLoader（96MB cap 单缓存，不另起
    /// 管线）；命中缓存同步上图，未命中异步回图并以 URL 比对
    /// 防串图（与 WallPosterCell 同口径）。
    func configure(track: FoliaTrack, pixelExtent: Double) {
        trackId = track.id
        titleLabel.text = track.title
        artistLabel.text = track.artist
        guard let raw = track.artworkURL?.absoluteString, !raw.isEmpty else {
            coverView.image = nil
            currentUrl = nil
            return
        }
        let tier = NativeCoverLoader.wallTier(raw: raw, pixelExtent: pixelExtent)
        guard let urlString = NativeCoverLoader.shared.proxiedURLString(raw, tier: tier)
        else {
            coverView.image = nil
            currentUrl = nil
            return
        }
        if currentUrl == urlString, coverView.image != nil { return }
        currentUrl = urlString
        if let cached = NativeCoverLoader.shared.cachedImage(for: urlString) {
            coverView.backgroundColor = .clear
            coverView.image = cached
            return
        }
        // (72) 主色占位（同 WallPosterCell 口径）：加载中垫
        // 封面主色/哈希暗调色，不露空黑。
        coverView.backgroundColor =
            NativeCoverLoader.shared.dominantColorAnyTier(raw: raw, excludingTier: tier)
            ?? NativeCoverLoader.placeholderColor(for: raw)
        coverView.image = NativeCoverLoader.shared.cachedImageAnyTier(
            raw: raw, excludingTier: tier)
        let wantedUrl = urlString
        let wantedId = track.id
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let image = await NativeCoverLoader.shared.image(for: urlString, tier: tier)
            guard let self, self.currentUrl == wantedUrl, self.trackId == wantedId,
                  let image else { return }
            self.coverView.backgroundColor = .clear
            self.coverView.image = image
        }
    }

    /// 播放态面（序号牌/段位/当前 accent）：$currentIndex 定向
    /// 刷牌与 cellForItemAt 共用，只动覆层不动封面与布局。
    /// (72) now 态做实：accent 环 + 光晕（播放中呼吸）+ 序号
    /// 牌反转为 accent 底黑字；played 压暗加深到 0.42 并把
    /// 文案一并压暗一档，三段（played/now/upcoming）肉眼可分。
    func applyPlaybackState(ordinal: Int, isCurrent: Bool, segment: Segment,
                            playing: Bool) {
        let text = "\(ordinal)"
        if badgeLabel.text != text {
            badgeLabel.attributedText = NSAttributedString(
                string: text,
                attributes: [.kern: 1.2])
        }
        let accent = ThemeSystem62.currentAccent
        badgeLabel.textColor = isCurrent ? .black : .white
        badgeView.backgroundColor = isCurrent
            ? accent
            : UIColor.black.withAlphaComponent(0.62)
        // 段标记：played 压暗封面（覆层在图上、文案下）。
        dimView.alpha = segment == .played ? 0.42 : 0
        titleLabel.alpha = segment == .played ? 0.55 : 1
        artistLabel.alpha = segment == .played ? 0.45 : 1
        // now 环：显隐 + 配色随主题 accent；播放中呼吸、暂停静亮。
        ringView.isHidden = !isCurrent
        if isCurrent { contentView.bringSubviewToFront(ringView) }
        if isCurrent {
            ringView.layer.borderColor = accent.cgColor
            ringView.layer.shadowColor = accent.cgColor
            if playing {
                if ringView.layer.animation(forKey: "foliaNowPulse") == nil {
                    let pulse = CABasicAnimation(keyPath: "opacity")
                    pulse.fromValue = 0.62
                    pulse.toValue = 1
                    pulse.duration = 1.15
                    pulse.autoreverses = true
                    pulse.repeatCount = .infinity
                    pulse.timingFunction =
                        CAMediaTimingFunction(name: .easeInEaseOut)
                    ringView.layer.add(pulse, forKey: "foliaNowPulse")
                }
            } else {
                ringView.layer.removeAnimation(forKey: "foliaNowPulse")
                ringView.layer.opacity = 1
            }
        } else {
            ringView.layer.removeAnimation(forKey: "foliaNowPulse")
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        coverView.frame = bounds
        dimView.frame = bounds
        ringView.frame = bounds
        gradientView.frame = bounds
        gradientLayer.frame = bounds

        let w = bounds.width
        let expanded = w > 100
        // 序号牌：规格 top/left 14px、padding 5/8（÷128 等比）。
        let badgeInset = max(5, w * 0.11)
        let badgeFont = max(9, w * (expanded ? 0.055 : 0.086))
        badgeLabel.font = .systemFont(ofSize: badgeFont, weight: .heavy)
        let badgeTextWidth = (badgeLabel.text ?? "").size(
            withAttributes: [.font: badgeLabel.font as Any]).width
        let badgePadH = max(4, w * 0.0625)
        let badgePadV = max(2.5, w * 0.039)
        let badgeW = badgeTextWidth + badgePadH * 2 + 2
        let badgeH = badgeFont + badgePadV * 2
        badgeView.frame = CGRect(x: badgeInset, y: badgeInset,
                                 width: badgeW, height: badgeH)
        badgeLabel.frame = badgeView.bounds

        // 底部文案：规格距边 17px（÷128≈0.133）、行距 gap 5px。
        let side = max(7, w * 0.125)
        let bottomInset = expanded ? bounds.height * 0.10 : max(6, w * 0.11)
        let titleFont = expanded
            ? min(max(w * 0.24, 20), 44)
            : min(max(w * 0.21, 11), 19)
        titleLabel.font = .systemFont(ofSize: titleFont, weight: .semibold)
        let artistFont = expanded ? max(12, w * 0.07) : max(10, w * 0.10)
        artistLabel.font = .systemFont(ofSize: artistFont, weight: .semibold)
        let textWidth = w - side * 2
        let artistH = artistFont + 4
        let titleMaxH = titleFont * 1.02 * 3
        let artistY = bounds.height - bottomInset - artistH
        artistLabel.frame = CGRect(x: side, y: artistY, width: textWidth, height: artistH)
        let titleY = artistY - 3 - titleMaxH
        titleLabel.frame = CGRect(x: side, y: titleY, width: textWidth, height: titleMaxH)
    }
}

// MARK: - lattice-chrome 播放条（展开态底部条）

/// 自左至右：播放/暂停（展开块是当前曲=切暂停、否则播该块）
/// → 上一首 → 下一首 → 时间 →「打开播放器」；顶部整宽直角
/// 进度条仅展开块是当前曲时可拖 seek（(70) B4 同款拖动态
/// 守卫：拖动期驱动不覆写、落点保持窗内不回跳）。
/// 两可配槽按 (71) 范围砍掉/后置，不在此条。
final class LatticeChromeView: UIView {

    var onPlayPause: (() -> Void)?
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?
    var onOpenPlayer: (() -> Void)?
    /// seek 落点（0–1），仅当前曲时触发。
    var onSeek: ((Double) -> Void)?

    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let playButton = UIButton(type: .system)
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let timeLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

    private var expandedTrack: FoliaTrack?
    private var expandedIsCurrent = false
    private var progressLink: CADisplayLink?
    private var seekDragging = false
    private var seekHoldUntil: CFTimeInterval = 0
    private var lastTimeText = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)
        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        addSubview(progressTrack)
        progressFill.backgroundColor = ThemeSystem62.currentAccent
        progressTrack.addSubview(progressFill)
        let seekPan = UIPanGestureRecognizer(target: self, action: #selector(seekPanned(_:)))
        progressTrack.addGestureRecognizer(seekPan)
        let seekTap = UITapGestureRecognizer(target: self, action: #selector(seekTapped(_:)))
        progressTrack.addGestureRecognizer(seekTap)

        configureButton(playButton, symbol: "play.fill", label: "播放",
                        action: #selector(playTapped))
        configureButton(prevButton, symbol: "backward.fill", label: "上一首",
                        action: #selector(prevTapped))
        configureButton(nextButton, symbol: "forward.fill", label: "下一首",
                        action: #selector(nextTapped))
        addSubview(playButton)
        addSubview(prevButton)
        addSubview(nextButton)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        addSubview(timeLabel)

        openButton.setImage(UIImage(systemName: "arrow.up.forward.app",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)),
            for: .normal)
        openButton.tintColor = .white
        openButton.accessibilityLabel = "打开播放器"
        openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
        addSubview(openButton)
    }

    private func configureButton(_ button: UIButton, symbol: String,
                                 label: String, action: Selector) {
        button.setImage(UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)),
            for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        progressTrack.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 14)
        layoutProgressFill()
        let rowY: CGFloat = 14
        let rowH: CGFloat = 52
        playButton.frame = CGRect(x: 10, y: rowY, width: 48, height: rowH)
        prevButton.frame = CGRect(x: 62, y: rowY, width: 40, height: rowH)
        nextButton.frame = CGRect(x: 106, y: rowY, width: 40, height: rowH)
        openButton.frame = CGRect(x: bounds.width - 54, y: rowY, width: 44, height: rowH)
        let timeX: CGFloat = 154
        timeLabel.frame = CGRect(x: timeX, y: rowY,
                                 width: max(0, bounds.width - 54 - timeX - 6),
                                 height: rowH)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 66 + safeAreaInsets.bottom)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    // MARK: - 状态同步（VC 在快照/播放头/展开变化时调）

    func configure(expandedTrack: FoliaTrack?, isCurrent: Bool) {
        self.expandedTrack = expandedTrack
        expandedIsCurrent = isCurrent
        refreshPlayGlyph()
        refreshProgress(force: true)
    }

    func refreshPlayGlyph() {
        let engine = PlaybackEngine.shared
        let playing = expandedIsCurrent && engine.isPlaying
        playButton.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)),
            for: .normal)
        playButton.accessibilityLabel = playing ? "暂停" : "播放"
    }

    // MARK: - 进度驱动（展开条在场时跑；拖动态守卫 (70) B4 同款）

    func startProgressDriver() {
        guard progressLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(progressTick(_:)))
        link.add(to: .main, forMode: .common)
        progressLink = link
    }

    func stopProgressDriver() {
        progressLink?.invalidate()
        progressLink = nil
    }

    @objc private func progressTick(_ link: CADisplayLink) {
        refreshProgress(force: false)
    }

    private func refreshProgress(force: Bool) {
        // 拖动态/落点保持窗内不被播放位置覆写（闪帧根治口径）。
        if seekDragging || CACurrentMediaTime() < seekHoldUntil { return }
        let engine = PlaybackEngine.shared
        var fraction = 0.0
        var current = 0.0
        var total = expandedTrack?.duration ?? 0
        if expandedIsCurrent {
            current = engine.currentTime
            if engine.duration > 0 { total = engine.duration }
            if total > 0 { fraction = min(max(current / total, 0), 1) }
        }
        setProgressFraction(fraction)
        let text = "\(Self.timeText(current)) / \(Self.timeText(total))"
        if force || text != lastTimeText {
            lastTimeText = text
            timeLabel.text = text
        }
    }

    private func setProgressFraction(_ fraction: Double) {
        let w = progressTrack.bounds.width * CGFloat(min(max(fraction, 0), 1))
        progressFill.frame = CGRect(x: 0, y: 5, width: w, height: 4)
    }

    private func layoutProgressFill() {
        // 帧宽随轨道宽变时保持当前比例（重排不丢进度）。
        let engine = PlaybackEngine.shared
        var fraction = 0.0
        if expandedIsCurrent, engine.duration > 0 {
            fraction = min(max(engine.currentTime / engine.duration, 0), 1)
        }
        setProgressFraction(fraction)
    }

    private static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    // MARK: - seek（仅展开块是当前曲时可拖，port-spec 第一条）

    private func seekFraction(at point: CGPoint) -> Double {
        guard progressTrack.bounds.width > 0 else { return 0 }
        return min(max(Double(point.x / progressTrack.bounds.width), 0), 1)
    }

    @objc private func seekPanned(_ gesture: UIPanGestureRecognizer) {
        guard expandedIsCurrent else { return }
        let fraction = seekFraction(at: gesture.location(in: progressTrack))
        switch gesture.state {
        case .began, .changed:
            seekDragging = true
            setProgressFraction(fraction)
        case .ended, .cancelled, .failed:
            seekDragging = false
            seekHoldUntil = CACurrentMediaTime() + 0.6
            onSeek?(fraction)
        default:
            break
        }
    }

    @objc private func seekTapped(_ gesture: UITapGestureRecognizer) {
        guard expandedIsCurrent else { return }
        let fraction = seekFraction(at: gesture.location(in: progressTrack))
        setProgressFraction(fraction)
        seekHoldUntil = CACurrentMediaTime() + 0.6
        onSeek?(fraction)
    }

    // MARK: - 按钮

    @objc private func playTapped() { onPlayPause?() }
    @objc private func prevTapped() { onPrev?() }
    @objc private func nextTapped() { onNext?() }
    @objc private func openTapped() { onOpenPlayer?() }
}
