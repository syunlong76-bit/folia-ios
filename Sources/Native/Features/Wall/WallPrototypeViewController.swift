import Combine
import UIKit

/// 回程票（3.7 (13) #6）：进播放页前存下曲目墙上下文，前端
/// stageClosed 到达后 MainViewController 按票重呈主页墙并直达
/// 本歌单曲目墙，恢复相机与展开项。
struct WallReturnTicket {
    let playlistId: String
    let title: String?
    let coverUrl: String?
    let worldOrigin: CGPoint
    let contentOffset: CGPoint
    let expandedInstanceId: String?
    let expandedQueueIndex: Int?
}

enum WallReturnTicketStore {
    static var pending: WallReturnTicket?
}

extension Notification.Name {
    /// 前端 stageClosed 已过桥（WebEffectBridge 转发）。
    static let foliaStageClosed = Notification.Name("FoliaStageClosed")
}

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
    /// 歌词窗口去重与滑入判定：同曲且索引恰好 +1 才滑入，其余 snap。
    private var lastLyricTrackId: String?
    private var lastLyricIndex: Int?
    /// 前奏预告态去重（3.7 (13) #2）：同 idx 下 active 翻转要重下发。
    private var lastLyricActive = true
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
    /// 加载失败重试（3.7 (13) #3）：自动重试一次，之后点按重试。
    private var loadAttempts = 0
    private var loadFailed = false
    /// 回程恢复（3.7 (13) #6）：重呈时由主页墙注入，种子落地后应用。
    var pendingReturnTicket: WallReturnTicket?
    /// 底部播放台（3.7 (13) #7；13.1 改版）：网页风迷你播放器，
    /// 点封面定位、点台身进播放页、进度可拖（Miller 13.1 定版）。
    private var miniBar: UIView?
    private var miniCover: UIImageView!
    private var miniTitle: UILabel!
    private var miniArtist: UILabel!
    private var miniPlayButton: UIButton!
    private var miniPrevButton: UIButton!
    private var miniNextButton: UIButton!
    private var miniSeekHit: UIView!
    private var miniProgressFill: UIView!
    /// 进度拖动中：心跳不覆盖填充，松手 seek 后恢复。
    private var miniSeekDragging = false
    /// 定位动画（CADisplayLink 驱动，DS31）：起点/目标/时长/收尾。
    private var locateLink: CADisplayLink?
    private var locateStartOrigin: CGPoint = .zero
    private var locateStartTime: CFTimeInterval = 0
    private var locateTargetOrigin: CGPoint = .zero
    private var locateDuration: TimeInterval = 0.45
    private var locateCompletion: (() -> Void)?

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
        // 双击进播放页（3.7 (13) #8b）：独立识别器，不给单击展开
        // 加 require(toFail:) 延迟。
        let doubleTap = UITapGestureRecognizer(
            target: self, action: #selector(wallDoubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        collectionView.addGestureRecognizer(doubleTap)
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

        // 氛围底（丝滑切入）：盖在空墙上、垫在胶囊/关闭键下；数据
        // 到达后淡出。封面来自内存缓存（主页墙刚显示过），零等待。
        let backdropView = LoadingBackdropView(title: playlistTitle)
        backdropView.onPendingClose = { [weak self] in
            self?.dismiss(animated: true)
        }
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
                self.refreshMiniBar()
            }
            .store(in: &playbackCancellables)
        PlaybackEngine.shared.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshVisiblePlaybackUI()
                self?.refreshMiniBar()
            }
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

        buildMiniBar()

        loadEntries()
    }

    /// 底部播放台（3.7 (13) #7；13.1 改版，Miller 2026-11-18 亲定）：
    /// 封面缩略 + 标题/歌手 + 上一曲/播放暂停/下一曲 + 顶部可拖进度。
    /// 交互：点封面 = 定位到正在播放的歌曲；点台身 = 进播放详情页
    /// （openStage 同路）；进度条可拖动 seek；按键只管切歌播停。
    private func buildMiniBar() {
        let bar = UIView()
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        bar.layer.cornerRadius = 16
        bar.clipsToBounds = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        view.addSubview(bar)
        miniBar = bar

        let progressTrack = UIView()
        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(progressTrack)
        let fill = UIView()
        fill.backgroundColor = .white
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressTrack.addSubview(fill)
        miniProgressFill = fill

        miniCover = UIImageView()
        miniCover.contentMode = .scaleAspectFill
        miniCover.clipsToBounds = true
        miniCover.layer.cornerRadius = 8
        miniCover.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        miniCover.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniCover)

        miniTitle = UILabel()
        miniTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        miniTitle.textColor = .white
        miniTitle.lineBreakMode = .byTruncatingTail
        miniTitle.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniTitle)

        miniArtist = UILabel()
        miniArtist.font = .systemFont(ofSize: 11)
        miniArtist.textColor = UIColor.white.withAlphaComponent(0.6)
        miniArtist.lineBreakMode = .byTruncatingTail
        miniArtist.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniArtist)

        miniPlayButton = UIButton(type: .system)
        miniPlayButton.tintColor = .white
        miniPlayButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        miniPlayButton.translatesAutoresizingMaskIntoConstraints = false
        miniPlayButton.addTarget(self, action: #selector(miniPlayTapped), for: .touchUpInside)
        bar.addSubview(miniPlayButton)

        miniPrevButton = UIButton(type: .system)
        miniPrevButton.tintColor = .white
        miniPrevButton.setImage(UIImage(systemName: "backward.fill"), for: .normal)
        miniPrevButton.translatesAutoresizingMaskIntoConstraints = false
        miniPrevButton.addTarget(self, action: #selector(miniPrevTapped), for: .touchUpInside)
        bar.addSubview(miniPrevButton)

        miniNextButton = UIButton(type: .system)
        miniNextButton.tintColor = .white
        miniNextButton.setImage(UIImage(systemName: "forward.fill"), for: .normal)
        miniNextButton.translatesAutoresizingMaskIntoConstraints = false
        miniNextButton.addTarget(self, action: #selector(miniNextTapped), for: .touchUpInside)
        bar.addSubview(miniNextButton)

        // 进度拖动手柄区：盖住顶部进度条并上下放宽到 20pt 好按。
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
            bar.heightAnchor.constraint(equalToConstant: 60),

            progressTrack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            progressTrack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            progressTrack.topAnchor.constraint(equalTo: bar.topAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 2),
            fill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            fill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            fill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor),

            miniCover.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            miniCover.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            miniCover.widthAnchor.constraint(equalToConstant: 42),
            miniCover.heightAnchor.constraint(equalToConstant: 42),

            miniTitle.leadingAnchor.constraint(equalTo: miniCover.trailingAnchor, constant: 10),
            miniTitle.trailingAnchor.constraint(equalTo: miniPrevButton.leadingAnchor, constant: -6),
            miniTitle.topAnchor.constraint(equalTo: bar.topAnchor, constant: 12),

            miniArtist.leadingAnchor.constraint(equalTo: miniTitle.leadingAnchor),
            miniArtist.trailingAnchor.constraint(equalTo: miniTitle.trailingAnchor),
            miniArtist.topAnchor.constraint(equalTo: miniTitle.bottomAnchor, constant: 2),

            miniNextButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -6),
            miniNextButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            miniNextButton.widthAnchor.constraint(equalToConstant: 34),
            miniNextButton.heightAnchor.constraint(equalToConstant: 40),

            miniPlayButton.trailingAnchor.constraint(equalTo: miniNextButton.leadingAnchor, constant: -2),
            miniPlayButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            miniPlayButton.widthAnchor.constraint(equalToConstant: 40),
            miniPlayButton.heightAnchor.constraint(equalToConstant: 40),

            miniPrevButton.trailingAnchor.constraint(equalTo: miniPlayButton.leadingAnchor, constant: -2),
            miniPrevButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            miniPrevButton.widthAnchor.constraint(equalToConstant: 34),
            miniPrevButton.heightAnchor.constraint(equalToConstant: 40),

            miniSeekHit.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            miniSeekHit.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            miniSeekHit.topAnchor.constraint(equalTo: bar.topAnchor),
            miniSeekHit.heightAnchor.constraint(equalToConstant: 20),
        ])
        fill.transform = CGAffineTransform(scaleX: 0, y: 1)

        let tap = UITapGestureRecognizer(target: self, action: #selector(miniBarTapped(_:)))
        bar.addGestureRecognizer(tap)
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

    /// 台面点按分发（13.1）：按键与进度区各自处理；封面 = 定位；
    /// 其余台身 = 进播放详情页。
    @objc private func miniBarTapped(_ gesture: UITapGestureRecognizer) {
        guard let bar = miniBar else { return }
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point)
            || miniSeekHit.frame.contains(point) { return }
        if miniCover.frame.contains(point) {
            locateCurrentTrack()
            return
        }
        openStageFromWall()
    }

    /// 进度拖动（13.1）：拖动中只更新填充，松手才 seek（防拖动
    /// 途中连环跳秒）；轻点进度区同样跳到该位置。终结状态先复位
    /// 拖动标记再走任何守卫——拖动途中切歌使 duration 归零时，
    /// 守卫先行会让标记永不复位、进度填充从此冻结（独立审查中-2）。
    /// 封面/按键的上沿落在命中带里，那里起手不抢手势（低-3）。
    @objc private func miniSeekPanned(_ gesture: UIPanGestureRecognizer) {
        guard let hit = miniSeekHit, hit.bounds.width > 0 else { return }
        let engine = PlaybackEngine.shared
        let fraction = min(max(gesture.location(in: hit).x / hit.bounds.width, 0), 1)
        switch gesture.state {
        case .began:
            let barPoint = gesture.location(in: miniBar)
            if miniCover.frame.contains(barPoint)
                || miniPlayButton.frame.contains(barPoint)
                || miniPrevButton.frame.contains(barPoint)
                || miniNextButton.frame.contains(barPoint) { return }
            guard engine.duration > 0 else { return }
            miniSeekDragging = true
            miniProgressFill.transform = CGAffineTransform(scaleX: fraction, y: 1)
        case .changed:
            guard miniSeekDragging else { return }
            miniProgressFill.transform = CGAffineTransform(scaleX: fraction, y: 1)
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

    /// 播放台内容同步：有当前曲才显示；封面优先引擎现图，缺了走
    /// 封面链按当前曲 id 校验后补。
    private func refreshMiniBar() {
        guard let bar = miniBar else { return }
        let engine = PlaybackEngine.shared
        guard let track = engine.currentTrack else {
            bar.isHidden = true
            return
        }
        bar.isHidden = false
        miniTitle.text = track.title
        miniArtist.text = track.artist
        miniPlayButton.setImage(
            UIImage(systemName: engine.playbackState == .playing ? "pause.fill" : "play.fill"),
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

    /// 点播放台封面定位（3.7 (13) #7；13.1 改点封面）：相机平滑
    /// 移到当前曲最近的一份拷贝并展开（时长按距离缩放、展开步
    /// 交叉淡化，治 13 真机「衔接不丝滑」）；当前曲不在本歌单
    /// 时给人话提示。
    private func locateCurrentTrack() {
        guard let currentId = PlaybackEngine.shared.currentTrack?.id else { return }
        guard let queueIndex = entries.firstIndex(where: { $0.id == currentId }) else {
            statusLabel.text = "当前歌曲不在这个歌单里"
            statusLabel.isHidden = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, self.statusLabel.text == "当前歌曲不在这个歌单里" else { return }
                self.statusLabel.text = "墙原型：\(self.wallLayout.totalEntries) 首 · 拖动平移 · 点按展开"
            }
            return
        }
        let scale = wallLayout.cameraScale
        let viewWorldW = Double(collectionView.bounds.width) / scale
        let viewWorldH = Double(collectionView.bounds.height) / scale
        let centerX = Double(wallLayout.worldOrigin.x) + viewWorldW / 2
        let centerY = Double(wallLayout.worldOrigin.y) + viewWorldH / 2
        guard let target = WallGeometry.locateNearestInstance(
            geometry: wallLayout.geometry, totalEntries: wallLayout.totalEntries,
            queueIndex: queueIndex, pointX: centerX, pointY: centerY,
            metrics: wallLayout.metrics) else { return }
        Breadcrumbs.log("locate queueIndex=\(queueIndex)")
        if wallLayout.expandedInstanceId != nil {
            wallLayout.expandedInstanceId = nil
            wallLayout.refreshInstances()
            collectionView.reloadData()
        }
        let targetOrigin = CGPoint(
            x: CGFloat(target.rect.x + target.rect.width / 2 - viewWorldW / 2),
            y: CGFloat(target.rect.y + target.rect.height / 2 - viewWorldH / 2))
        // 时长按距离缩放：远距离仍是 0.45 秒会显得猛冲急停（13.1）。
        let distance = hypot(targetOrigin.x - wallLayout.worldOrigin.x,
                             targetOrigin.y - wallLayout.worldOrigin.y)
        let duration = min(0.85, max(0.45, Double(distance) * 0.00035))
        animateWorldOrigin(to: targetOrigin, duration: duration) { [weak self] in
            guard let self else { return }
            self.wallLayout.expandedInstanceId = target.instanceId
            self.wallLayout.refreshInstances()
            // 展开是布局突变：交叉淡化盖住硬跳（13.1 衔接丝滑）。
            UIView.transition(with: self.collectionView, duration: 0.25,
                              options: [.transitionCrossDissolve]) {
                self.collectionView.reloadData()
            }
        }
    }

    /// 世界原点插值动画（定位专用）：CADisplayLink 按屏幕刷新
    /// 驱动（DS31：Timer 与刷新不同步、真机易抖），逐帧走既有
    /// 折叠同款更新（refreshInstances + 身份变了才 reloadData）。
    private func animateWorldOrigin(to target: CGPoint, duration: TimeInterval,
                                    completion: @escaping () -> Void) {
        locateLink?.invalidate()
        locateStartOrigin = wallLayout.worldOrigin
        locateTargetOrigin = target
        locateDuration = duration
        locateStartTime = CACurrentMediaTime()
        locateCompletion = completion
        let link = CADisplayLink(target: self, selector: #selector(locateTick(_:)))
        link.add(to: .main, forMode: .common)
        locateLink = link
    }

    @objc private func locateTick(_ link: CADisplayLink) {
        let raw = min((link.timestamp - locateStartTime) / locateDuration, 1)
        let eased = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
        let before = setIdentity()
        wallLayout.worldOrigin = CGPoint(
            x: locateStartOrigin.x + (locateTargetOrigin.x - locateStartOrigin.x) * CGFloat(eased),
            y: locateStartOrigin.y + (locateTargetOrigin.y - locateStartOrigin.y) * CGFloat(eased))
        wallLayout.refreshInstances()
        if setIdentity() != before { collectionView.reloadData() }
        if raw >= 1 {
            link.invalidate()
            locateLink = nil
            let done = locateCompletion
            locateCompletion = nil
            done?()
        }
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
        locateLink?.invalidate()
        locateLink = nil
        locateCompletion = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Breadcrumbs.log("tracks appear playlist=\(playlistId)")
        Breadcrumbs.samplerStart()
        refreshMiniBar()
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut]) {
            self.collectionView.transform = .identity
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Breadcrumbs.samplerStop()
        Breadcrumbs.log("tracks disappear playlist=\(playlistId)")
    }

    /// 失败态点按状态胶囊：重置计数重新加载（3.7 (13) #3）。
    @objc private func statusTapped() {
        guard loadFailed else { return }
        loadFailed = false
        loadAttempts = 0
        statusLabel.text = "墙原型加载中…"
        loadEntries()
    }

    @objc private func closeTapped() {
        // 拍立得翻面中关闭被背板拦截记账，落定后经 onPendingClose 回来。
        if let backdrop, !backdrop.requestClose() { return }
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
        loadAttempts += 1
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
                    if self.pendingReturnTicket != nil {
                        self.applyReturnTicket()
                    } else {
                        self.centerCameraIfNeeded()
                    }
                    // 丝滑切入收口：唤醒等数据的 present、氛围底退场、
                    // 首屏波次从此刻起算。
                    self.loadAttempts = 0
                    self.loadFailed = false
                    Breadcrumbs.log("tracks seed ok n=\(seed.count)/\(total)")
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
                // 原始错误只进日志，标签只给人话（3.7 (13) #3）；
                // 自动重试一次，之后点按重试。
                await MainActor.run {
                    FoliaBridgeLogStore.shared.write(
                        level: "error", module: "wall",
                        message: "tracks load failed playlist=\(self.playlistId) attempt=\(self.loadAttempts): \(error)")
                    Breadcrumbs.log("tracks load failed attempt=\(self.loadAttempts)")
                    self.statusLabel.isHidden = false
                    if self.loadAttempts < 2 {
                        self.statusLabel.text = "加载失败，正在重试…"
                        self.flushSeedWaiters()
                        self.backdrop?.dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                            self?.loadEntries()
                        }
                    } else {
                        self.loadFailed = true
                        self.statusLabel.text = "加载失败，点按这里重试"
                        self.flushSeedWaiters()
                        self.backdrop?.dismiss()
                    }
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

    /// 回程票应用（3.7 (13) #6）：种子落地后恢复相机（worldOrigin
    /// 与 contentOffset 成对）与展开项。展开实例 id 按确定性生成
    /// 应原样命中；不在新实例集时退到同序号离视口中心最近的一份。
    private func applyReturnTicket() {
        guard let ticket = pendingReturnTicket else { return }
        pendingReturnTicket = nil
        didCenterCamera = true
        wallLayout.cameraScale = Self.cameraScale(forWidth: collectionView.bounds.width)
        wallLayout.worldOrigin = ticket.worldOrigin
        wallLayout.expandedInstanceId = nil
        wallLayout.refreshInstances()
        collectionView.contentOffset = ticket.contentOffset
        if let expandedId = ticket.expandedInstanceId,
           wallLayout.instances.contains(where: { $0.instanceId == expandedId }) {
            wallLayout.expandedInstanceId = expandedId
        } else if let queueIndex = ticket.expandedQueueIndex {
            let centerWorld = CGPoint(
                x: Double(ticket.worldOrigin.x) + Double(collectionView.bounds.width) / wallLayout.cameraScale / 2,
                y: Double(ticket.worldOrigin.y) + Double(collectionView.bounds.height) / wallLayout.cameraScale / 2)
            let nearest = wallLayout.instances
                .filter { $0.queueIndex == queueIndex }
                .min { a, b in
                    let da = hypot(a.rect.left + a.rect.width / 2 - Double(centerWorld.x),
                                   a.rect.top + a.rect.height / 2 - Double(centerWorld.y))
                    let db = hypot(b.rect.left + b.rect.width / 2 - Double(centerWorld.x),
                                   b.rect.top + b.rect.height / 2 - Double(centerWorld.y))
                    return da < db
                }
            wallLayout.expandedInstanceId = nearest?.instanceId
        }
        wallLayout.refreshInstances()
        collectionView.reloadData()
        Breadcrumbs.log("return ticket applied playlist=\(ticket.playlistId)")
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
        // 展开卡是当前曲且词已到手：作废歌词窗口索引，下一拍心跳重刷
        // （收起时 cell 已清窗口，光靠索引去重会漏刷）。
        if wallLayout.expandedInstanceId == instance.instanceId, isCurrent,
           lyricCache[entry.id] != nil {
            lastLyricIndex = nil
        }
        cell.lyricClock = { PlaybackEngine.shared.currentTime }
        let queueIndex = instance.queueIndex
        cell.onPlayTap = { [weak self] in self?.playTapped(queueIndex: queueIndex) }
        cell.onLikeTap = { [weak self] in self?.likeTapped(queueIndex: queueIndex) }
    }

    /// 进播放页（3.7 (13) #5/#6/#8b）：双击卡片触发。先存回程票，
    /// 再请前端开播放页（主态直达），最后收起整摞原生墙——转场
    /// 只剩墙淡出，不再叠封面飞行动画（(12) 的伪 morph 与播放页
    /// 自带动画打架，Miller 点名不流畅，已删）。
    private func openStageFromWall() {
        let expanded = wallLayout.instances.first {
            $0.instanceId == wallLayout.expandedInstanceId
        }
        WallReturnTicketStore.pending = WallReturnTicket(
            playlistId: playlistId,
            title: playlistTitle,
            coverUrl: playlistCoverUrl,
            worldOrigin: wallLayout.worldOrigin,
            contentOffset: collectionView.contentOffset,
            expandedInstanceId: wallLayout.expandedInstanceId,
            expandedQueueIndex: expanded?.queueIndex)
        Breadcrumbs.log("stage open, ticket saved playlist=\(playlistId)")
        WebEffectBridge.shared.requestOpenStage()
        var host: UIViewController = self
        while let presenter = host.presentingViewController { host = presenter }
        if host !== self { host.dismiss(animated: true) }
    }

    /// 双击卡片进播放页（3.7 (13) #8b）：双击的不是当前曲时先切
    /// 队列再开页（原生队列同步落位，桥快照即新当前曲）；单击
    /// 展开保持原样、不等双击判定，第一击的展开是无害前置。
    @objc private func wallDoubleTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              indexPath.item < wallLayout.instances.count else { return }
        let instance = wallLayout.instances[indexPath.item]
        guard instance.queueIndex < entries.count else { return }
        Breadcrumbs.log("wall double tap queueIndex=\(instance.queueIndex)")
        if PlaybackEngine.shared.currentTrack?.id != entries[instance.queueIndex].id {
            startQueueAt(queueIndex: instance.queueIndex)
        }
        openStageFromWall()
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
        // 底部播放台进度（3.7 (13) #7）：同一心跳顺手推进；
        // 拖动中不覆盖（13.1 可拖进度）。
        if let bar = miniBar, !bar.isHidden, !miniSeekDragging {
            let fraction = max(0, min(1, engine.currentTime / engine.duration))
            miniProgressFill.transform = CGAffineTransform(scaleX: CGFloat(fraction), y: 1)
        }
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
        // 前奏预告态（3.7 (13) #2）：还没唱到首行时窗口只预告，
        // 不点亮不扫光；active 翻转也要重下发（同 idx 不能被去重吞掉）。
        let lineActive = lines[idx].time <= currentTime + 0.15
        if lastLyricTrackId == trackId, lastLyricIndex == idx,
           lastLyricActive == lineActive { return }
        let slide = lastLyricTrackId == trackId && lastLyricIndex == idx - 1
        lastLyricTrackId = trackId
        lastLyricIndex = idx
        lastLyricActive = lineActive
        // 6 行窗口：当前行居中（行 2），行 5 是滑入预备行。
        let texts = (-2...3).map { offset -> String in
            let j = idx + offset
            return (j >= 0 && j < lines.count) ? lines[j].text : ""
        }
        // 当前行时长：有下一行按行距夹取，末行按字数估（DS27 定版）。
        let duration: Double
        if idx + 1 < lines.count {
            duration = min(max(lines[idx + 1].time - lines[idx].time, 0.8), 10)
        } else {
            duration = min(max(Double(lines[idx].text.count) * 0.4, 2.5), 8)
        }
        cell.setLyricWindow(texts: texts, lineStart: lines[idx].time,
                            lineDuration: duration, slide: slide,
                            lineActive: lineActive)
    }

    private func ensureLyrics(for trackId: String) {
        guard lyricCache[trackId] == nil,
              !lyricFetchInFlight.contains(trackId) else { return }
        lyricFetchInFlight.insert(trackId)
        Breadcrumbs.log("lrc fetch start track=\(trackId)")
        Task { [weak self] in
            let text = try? await EdgeOneAPIClient.shared.fetchLyricText(songId: trackId)
            let parsed = text.map { Self.parseLRC($0) } ?? []
            await MainActor.run {
                guard let self else { return }
                Breadcrumbs.log("lrc parsed track=\(trackId) lines=\(parsed.count)")
                self.lyricFetchInFlight.remove(trackId)
                self.lyricCache[trackId] = parsed
                self.lastLyricIndex = nil
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
        let sorted = out.sorted { $0.time < $1.time }
        // 制作名单行只在首个正文行之前过滤（3.7 (13) #2，DS30
        // 位置约束）：正文开始后出现的同形行是歌词本体，不动。
        return Array(sorted.drop(while: { isCreditLine($0.text) }))
    }

    /// 制作名单行识别（3.7 (13) #2）：网易云 LRC 开头是制作名单
    /// （作词/作曲/制作人/监制/混音/母带…），时间戳挤在亚秒级，
    /// (12) 里被当歌词行逐行扫光。只认「名目 + 冒号」或英文
    /// "X by" 形状；叙事行（如「妈妈：…」）不在名目表里。
    private static let creditPrefixes = [
        "作词", "作曲", "编曲", "制作人", "监制", "混音", "母带",
        "录音", "和声", "配唱", "音乐总监", "出品", "发行",
        "统筹", "企划", "演唱", "原唱", "OP", "SP"
    ]

    private static func isCreditLine(_ text: String) -> Bool {
        for prefix in creditPrefixes where text.hasPrefix(prefix) {
            // 冒号前可能带空格（「作词 : 林夕」），先削掉再判。
            let rest = text.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("：") || rest.hasPrefix(":") { return true }
        }
        let lower = text.lowercased()
        return lower.hasPrefix("lyrics by") || lower.hasPrefix("composed by")
            || lower.hasPrefix("produced by") || lower.hasPrefix("arranged by")
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
        startQueueAt(queueIndex: queueIndex)
    }

    /// 队列真源切换（playTapped 与双击进播放页共用）：按全量 id
    /// 骨架建队列、从目标曲起播，三态由订阅收尾。
    private func startQueueAt(queueIndex: Int) {
        guard queueIndex < entries.count else { return }
        let tappedId = entries[queueIndex].id
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
        Breadcrumbs.log("wall tap item=\(indexPath.item) queueIndex=\(instance.queueIndex)")
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
    private let playButton = UIButton(type: .system)
    private let likeButton = UIButton(type: .system)
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let playingBadge = UIButton(type: .system)
    private let playSpinner = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    // 展开卡滚动歌词（3.7 (12) 全套，DS27 对账定版）：字号随卡宽
    // 自适应 + Songti + 6 行容器滑入 + 当前行扫光（CADisplayLink
    // 按引擎时钟推进）+ 呼吸缩放 + 柔光罩。动画只挂歌词子视图，
    // 不碰 cell 根 transform（与按压缩放/入场动画互不干扰）。
    private let lyricScrimView = UIView()
    private let lyricGradient = CAGradientLayer()
    private let lyricClipView = UIView()
    private let lyricLinesContainer = UIView()
    private var lyricPlainLabels: [Int: UILabel] = [:]
    private let lyricSweepView = SweepLyricLineView()
    private var lyricTexts: [String] = []
    private var lyricLineHeight: CGFloat = 27
    private var lyricCurrentFontSize: CGFloat = 16
    private var lyricNeighborFontSize: CGFloat = 13
    private var lastLyricClipWidth: CGFloat = -1
    private var sweepDisplayLink: CADisplayLink?
    private var sweepProxy: SweepLinkProxy?
    private var sweepLineStart: Double = 0
    private var sweepLineDuration: Double = 1
    /// 歌词时钟（VC 注入 = 引擎 currentTime）：扫光据此推进，暂停即冻结。
    var lyricClock: (() -> Double)?
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

        // 角标退回纯指示（3.7 (13) #8b，Miller 定）：进播放页改走
        // 双击卡片，角标只表示「正在播放」、不可点。
        playingBadge.setImage(UIImage(systemName: "speaker.wave.2.fill"), for: .normal)
        playingBadge.tintColor = .white
        playingBadge.layer.shadowColor = UIColor.black.cgColor
        playingBadge.layer.shadowOpacity = 0.8
        playingBadge.layer.shadowRadius = 2
        playingBadge.layer.shadowOffset = .zero
        playingBadge.isUserInteractionEnabled = false
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

        // 柔光罩（歌词区可读性垫层）+ 裁剪窗 + 6 行容器（行 2 = 扫光行）。
        lyricScrimView.isHidden = true
        lyricScrimView.layer.cornerRadius = 10
        lyricScrimView.clipsToBounds = true
        lyricGradient.colors = [
            UIColor.black.withAlphaComponent(0.30).cgColor,
            UIColor.black.withAlphaComponent(0.08).cgColor
        ]
        lyricScrimView.layer.addSublayer(lyricGradient)
        shadowView.addSubview(lyricScrimView)

        lyricClipView.clipsToBounds = true
        lyricClipView.isHidden = true
        shadowView.addSubview(lyricClipView)
        lyricClipView.addSubview(lyricLinesContainer)
        for row in 0..<6 {
            if row == 2 {
                lyricLinesContainer.addSubview(lyricSweepView)
            } else {
                let label = UILabel()
                label.textAlignment = .center
                label.textColor = .white
                label.layer.shadowColor = UIColor.black.cgColor
                label.layer.shadowOpacity = 0.85
                label.layer.shadowRadius = 2
                label.layer.shadowOffset = .zero
                lyricPlainLabels[row] = label
                lyricLinesContainer.addSubview(label)
            }
        }
    }

    @objc private func playButtonTapped() { onPlayTap?() }
    @objc private func likeButtonTapped() { onLikeTap?() }

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
        if !expanded {
            setLyricWindow(texts: [], lineStart: 0, lineDuration: 0, slide: false)
        }
        setLiked(liked)
        setNeedsLayout()
    }

    /// 滚动歌词窗口（6 行：当前行居行 2、行 5 为滑入预备行）：
    /// slide 为真且 cell 现渲染的中心行与新窗口行 1 对得上时，整列
    /// 上滑一行再落位重渲染；其余情况直接落位。空窗口 = 整组收起。
    func setLyricWindow(texts: [String], lineStart: Double,
                        lineDuration: Double, slide: Bool,
                        lineActive: Bool = true) {
        let hasContent = texts.contains { !$0.isEmpty }
        lyricScrimView.isHidden = !hasContent
        lyricClipView.isHidden = !hasContent
        guard hasContent else {
            lyricTexts = []
            stopSweep()
            return
        }
        let canSlide = slide && lyricTexts.count == 6 && texts.count == 6
            && !lyricTexts[2].isEmpty && lyricTexts[2] == texts[1]
        lyricTexts = texts
        if canSlide {
            // 现渲染的行 1...5 恰好是新窗口的可见行，整列上滑一行。
            UIView.animate(withDuration: 0.18, delay: 0,
                           options: [.curveEaseOut]) {
                self.lyricLinesContainer.transform =
                    CGAffineTransform(translationX: 0, y: -self.lyricLineHeight)
            } completion: { _ in
                self.lyricLinesContainer.transform = .identity
                self.renderLyricWindow()
                if lineActive {
                    self.beginSweep(lineStart: lineStart, lineDuration: lineDuration)
                    self.playLyricBreathing()
                } else {
                    // 前奏预告：扫光停在 0（只剩暗字），不呼吸。
                    self.stopSweep()
                    self.lyricSweepView.progress = 0
                }
            }
        } else {
            lyricLinesContainer.layer.removeAllAnimations()
            lyricLinesContainer.transform = .identity
            renderLyricWindow()
            if lineActive {
                beginSweep(lineStart: lineStart, lineDuration: lineDuration)
                playLyricBreathing()
            } else {
                stopSweep()
                lyricSweepView.progress = 0
            }
        }
        setNeedsLayout()
    }

    private func renderLyricWindow() {
        let alphas: [CGFloat] = [0.28, 0.45, 1, 0.45, 0.28, 0.28]
        for row in 0..<6 {
            let text = row < lyricTexts.count ? lyricTexts[row] : ""
            if row == 2 {
                lyricSweepView.setText(lyricAttributed(text, center: true))
            } else if let label = lyricPlainLabels[row] {
                label.attributedText = lyricAttributed(text, center: false)
                label.alpha = alphas[row]
            }
        }
    }

    /// Songti 排版（唱片内页感）：当前行粗体 + 字距 1.2，邻行细体
    /// + 字距 0.6；字体名取不到时回系统粗/细体（DS27 定版）。
    private func lyricAttributed(_ text: String, center: Bool) -> NSAttributedString {
        let font: UIFont = center
            ? (UIFont(name: "STSongti-SC-Bold", size: lyricCurrentFontSize)
               ?? .systemFont(ofSize: lyricCurrentFontSize, weight: .bold))
            : (UIFont(name: "STSongti-SC-Light", size: lyricNeighborFontSize)
               ?? .systemFont(ofSize: lyricNeighborFontSize, weight: .light))
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: center ? 1.2 : 0.6
        ])
    }

    /// 扫光起跑：CADisplayLink 每帧按引擎时钟算进度（0.3 秒心跳
    /// 只够换行、不够驱动扫光，DS27 定版）。link 经弱代理转发
    /// （3.7 (13) #1）：直连 cell 会被 link 强持无法释放。
    private func beginSweep(lineStart: Double, lineDuration: Double) {
        sweepLineStart = lineStart
        sweepLineDuration = max(lineDuration, 0.1)
        lyricSweepView.progress = 0
        sweepDisplayLink?.invalidate()
        let proxy = SweepLinkProxy()
        proxy.owner = self
        let link = CADisplayLink(target: proxy, selector: #selector(SweepLinkProxy.tick))
        proxy.link = link
        sweepProxy = proxy
        link.add(to: .main, forMode: .common)
        sweepDisplayLink = link
        sweepTick()
    }

    func sweepTick() {
        guard window != nil, let clock = lyricClock else { stopSweep(); return }
        let p = (clock() - sweepLineStart) / sweepLineDuration
        lyricSweepView.progress = min(max(p, 0), 1)
        if p >= 1 { stopSweep() }
    }

    private func stopSweep() {
        sweepDisplayLink?.invalidate()
        sweepDisplayLink = nil
        sweepProxy = nil
    }

    /// 呼吸缩放：只作用当前行视图，滑入落位后 1.04 弹簧落回。
    private func playLyricBreathing() {
        lyricSweepView.layer.removeAllAnimations()
        lyricSweepView.transform = .identity
        UIView.animate(withDuration: 0.10, delay: 0, options: [.curveEaseOut]) {
            self.lyricSweepView.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
        } completion: { _ in
            UIView.animate(withDuration: 0.22, delay: 0,
                           usingSpringWithDamping: 0.6, initialSpringVelocity: 0.3,
                           options: []) {
                self.lyricSweepView.transform = .identity
            }
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
        // 滚动歌词：字号随歌词区宽度自适应（DS27 公式），宽度变化
        // 超 1pt 才重算并重渲染；窗口居卡片中上部（避开底部控件行）。
        let clipWidth = max(bounds.width - 20, 0)
        if clipWidth > 0, abs(clipWidth - lastLyricClipWidth) > 1 {
            lastLyricClipWidth = clipWidth
            lyricCurrentFontSize = min(max(clipWidth * 0.048, 13), 22)
            lyricNeighborFontSize = max(lyricCurrentFontSize * 0.78, 11)
            lyricLineHeight = (lyricCurrentFontSize * 1.65).rounded()
            if !lyricTexts.isEmpty { renderLyricWindow() }
        }
        let lyricTop = bounds.height * 0.40 - lyricLineHeight * 2.5
        let clipFrame = CGRect(x: 10, y: lyricTop, width: clipWidth,
                               height: lyricLineHeight * 5)
        lyricScrimView.frame = clipFrame
        lyricGradient.frame = lyricScrimView.bounds
        lyricClipView.frame = clipFrame
        lyricLinesContainer.frame = CGRect(x: 0, y: 0, width: clipWidth,
                                           height: lyricLineHeight * 6)
        for row in 0..<6 {
            let frame = CGRect(x: 0, y: CGFloat(row) * lyricLineHeight,
                               width: clipWidth, height: lyricLineHeight)
            if row == 2 { lyricSweepView.frame = frame }
            else { lyricPlainLabels[row]?.frame = frame }
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

    deinit {
        sweepDisplayLink?.invalidate()
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
        controlsVisible = false
        playButton.isHidden = true
        likeButton.isHidden = true
        progressTrack.isHidden = true
        playingBadge.isHidden = true
        playSpinner.stopAnimating()
        playSpinner.isHidden = true
        errorLabel.isHidden = true
        errorLabel.text = nil
        stopSweep()
        lyricClock = nil
        lyricTexts = []
        lyricLinesContainer.layer.removeAllAnimations()
        lyricLinesContainer.transform = .identity
        lyricSweepView.layer.removeAllAnimations()
        lyricSweepView.transform = .identity
        lyricSweepView.progress = 0
        lyricScrimView.isHidden = true
        lyricClipView.isHidden = true
        progressValue = 0
    }
}

/// CADisplayLink 弱代理（3.7 (13) #1）：link 强持 target，直连
/// cell 会钉住 cell 无法释放；代理弱持 cell，cell 已释放时自停表。
private final class SweepLinkProxy: NSObject {
    weak var owner: WallPosterCell?
    weak var link: CADisplayLink?

    @objc func tick() {
        guard let owner else {
            link?.invalidate()
            return
        }
        owner.sweepTick()
    }
}

/// 当前行扫光视图（3.7 (12)）：暗字打底 + 亮字被 mask 按进度裁切，
/// 唱到哪亮到哪。mask 按文本实际宽度居中起算（居中文本不能从
/// label 左缘扫起）；进度由 cell 的 CADisplayLink 按引擎时钟推进。
private final class SweepLyricLineView: UIView {
    private let dimLabel = UILabel()
    private let brightLabel = UILabel()
    private let maskLayer = CALayer()
    var progress: Double = 0 {
        didSet { if progress != oldValue { updateMask() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for label in [dimLabel, brightLabel] {
            label.textAlignment = .center
            label.textColor = .white
            addSubview(label)
        }
        dimLabel.alpha = 0.38
        maskLayer.backgroundColor = UIColor.black.cgColor
        brightLabel.layer.mask = maskLayer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setText(_ attributed: NSAttributedString) {
        dimLabel.attributedText = attributed
        brightLabel.attributedText = attributed
        updateMask()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimLabel.frame = bounds
        brightLabel.frame = bounds
        updateMask()
    }

    private func updateMask() {
        guard bounds.width > 0,
              let text = dimLabel.attributedText, text.length > 0 else {
            maskLayer.frame = .zero
            return
        }
        let attrs = text.attributes(at: 0, effectiveRange: nil)
        let textWidth = ceil((text.string as NSString).size(withAttributes: attrs).width)
        let span = min(textWidth, bounds.width)
        let startX = textWidth >= bounds.width ? 0 : (bounds.width - textWidth) / 2
        maskLayer.frame = CGRect(x: startX, y: 0,
                                 width: span * CGFloat(progress),
                                 height: bounds.height)
    }
}

