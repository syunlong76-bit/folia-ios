import Combine
import UIKit

/// 回程票链已整链退役（3.7 (51)）：WallReturnTicket /
/// WallReturnTicketStore 定义删除。关原生舞台 = 纯 dismiss 回墙；
/// 网页舞台改为叠加 present 在原生舞台之上（WebStageHostViewController），
/// 关闭后 dismiss 回原生舞台，不再靠票据重建墙。前端 stageClosed 的
/// 通知名 foliaStageClosed 随桥收尾迁至 WebEffectBridge.swift 定义。

/// 歌词行（统一行模型）：time = 翻行时刻（秒），来源由
/// LyricTiming.flipSource 决定（3.7 (20) 起默认 LRC：onset
/// 实测 LRC 无系统偏差、YRC 系统性偏晚，见 LyricTiming 注释；
/// (19) 曾以 YRC 头戳为行时刻)。words 非 nil = 该行带逐字戳
/// （扫光按真戳推进；双表合并时已按 LRC 行窗重标定）；nil =
/// 行级路径（扫光线性插值）。
struct LyricLineData {
    let time: Double
    let text: String
    let words: [LyricWordStamp]?
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
    /// 进度逐帧插值（13.4）：台面与展开卡的进度线由它推；
    /// 歌词窗口已移交 lyricClockDriver 逐帧推进（包一 P2/P3）。
    private let progressDriver = StageProgressDriver()
    private let lyricClockDriver = LyricClockDriver()
    /// 翻行事件锚定（3.7 (21)）：行界注册到引擎 active 轨的
    /// boundary observer，翻行只认事件；lyricClockDriver 退为
    /// 只驱动扫光/进度。注册失败降级时（driver.isDegraded）本
    /// VC 回落时钟逐帧比对（(20) 口径）。
    private let lyricFlipDriver = LyricBoundaryFlipDriver()
    private var lyricOverlay: LyricWindowView?
    private var lyricSessionTrackId: String?
    private var firstAudioTrackId: String?
    /// 台内主题层（13.5 定版形态）：画与动画收进台内，替代
    /// 13.4 被否的台上方主题带；长按台身循环切换、UserDefaults
    /// 持久化（见 MiniPlayerTheme）。
    private var miniThemeLayer: MiniPlayerThemeLayer?
    private var miniTheme: MiniPlayerTheme = MiniPlayerTheme.effective
    private var miniKnobSkin: UIView?
    /// 玻璃高光两件（顶部亮线 + 极淡白罩）：buildMiniBar 建时
    /// 存引用，供收起态去背景时与主题层/毛玻璃一并隐藏
    /// （3.7 (22)，见 setMiniBarForm）。
    private var miniRimLight: UIView?
    private var miniGlassTint: UIView?
    /// 播放三态（DS26）：原生点播在途的曲目 id，起播确认或失败即清。
    private var pendingTrackId: String?
    /// 原生点播失败的曲目与短文案（展开卡失败条用）。
    private var failedPlayback: (id: String, message: String)?
    /// 滚动歌词取数在途集（3.7 (23) 起只防本 VC 重复起 Task；
    /// 缓存与网络合并归 LyricRepository 共享层，墙面逐帧 tick
    /// 同步读仓库 cachedEntry）。
    private var lyricFetchInFlight: Set<String> = []
    /// 歌词窗口去重与滑入判定：同曲且索引恰好 +1 才滑入，其余 snap。
    private var lastLyricTrackId: String?
    private var lastLyricIndex: Int?
    /// 前奏预告态去重（3.7 (13) #2）：同 idx 下 active 翻转要重下发。
    private var lastLyricActive = true
    /// 翻行分段埋点（3.7 (23)）：judge 判定提交翻行后记
    /// (行号, 提交单调时刻)，下一帧 tick 顶部落「判定→呈现」
    /// 段耗时（lrc flip present dt=），与 boundary 校准源的
    /// 回调延迟分开量——audit-3723 未确认的 +0.3s 内部构成分
    /// 段靠它定案。
    private var pendingFlipPresent: (idx: Int, wall: CFTimeInterval)?
    /// seek 边沿跟踪（3.7 (23)）：seek 在途不提交翻行；落定
    /// 后首帧清去重态、按 judge 直接重算当前行（不滑行、不
    /// 补翻）。
    private var wasSeekPendingLyric = false
    /// 歌词帧锚定（3.7 (17)）：当前锚定的播放曲实例 id（hysteresis
    /// 保持，见 updateLyricOverlayFrame）+ 帧面包屑去重串（锚 id 与
    /// 40pt 网格化原点，未变不重复落盘）。
    private var lyricAnchorInstanceId: String?
    private var lastLyricOverlayCrumb: String?
    /// 锚出窗隐藏态（3.7 (19)）：原锚滑出 overscan 窗口后歌词
    /// 淡出隐藏（不跨实例重锚、不清行窗），回窗淡入恢复；
    /// 状态翻转由 setLyricAnchorHidden 落面包屑供真机对账。
    private var lyricAnchorHidden = false
    /// 展开卡打点去重：组串未变时跳过重复 log。
    private var lastExpandedCellCrumb: String?
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
    private var loadFailed = false {
        // 贴纸层（3.7 (24)，纯新增）：只驱动失败陪衬贴纸显隐。
        didSet { stickerFailureStateChanged() }
    }

    // 贴纸层状态（3.7 (24)，纯新增视图层）：加载失败陪衬、
    // 空歌单、切歌缓冲。视图懒建，方法全在文件尾 extension。
    private var stickerFailureView: StickerView?
    private var stickerFailureReplayTimer: Timer?
    private var stickerEmptyView: StickerView?
    private var stickerEmptyEpisode = 0
    private var stickerBufferView: StickerView?
    private var stickerBufferEpisode = 0
    private var stickerBufferVisible = false
    // 切歌缓冲改触发（3.7 (25)）：点切歌 5s 计时窗 + .waiting 兜底。
    private var stickerBufferTapDeadline: Date?
    private var stickerBufferHideTimer: Timer?
    private var stickerBufferWaiting = false
    // 跳过闪现（3.7 (28)）：令牌防旧的待发隐藏误伤新一轮显示。
    private var stickerSkipFlashToken = 0
    /// 底部播放台（3.7 (13) #7；13.1 改版）：网页风迷你播放器，
    /// 点封面定位、点台身进播放页、进度可拖（Miller 13.1 定版）。
    private var miniBar: UIView?
    /// 台面毛玻璃层（3.7 (20)）：入场时 effect 从 nil 渐入做
    /// 「显影」联动，须持有引用（原为 buildMiniBar 局部量）。
    private var miniBlurView: UIVisualEffectView?
    /// 迷你台逻辑显隐（3.7 (20)）：动画边沿的唯一事实源，与
    /// isHidden（视觉落定态）分工，防进/退动画互相打架。
    private var miniBarPresented = false
    /// 迷你台尺寸约束（3.7 (21)）：宽度按竖屏定版居中（横屏
    /// 不拉伸，viewDidLayoutSubviews 按 min(宽,高) 更新）、
    /// 高度在完整/收起两形态间切换。
    private var miniBarWidthConstraint: NSLayoutConstraint?
    private var miniBarHeightConstraint: NSLayoutConstraint?
    private var miniTrackBottomConstraint: NSLayoutConstraint?
    /// 迷你台收起态（3.7 (21)：5 秒无操作自动收成进度条）：
    /// 与 miniBarPresented 分工——后者管在不在场，本标志管
    /// 完整/细条形态。收起形态 (22) 定版：背景全去（主题层/
    /// 毛玻璃/玻璃高光隐藏），只剩轨道+填充+发光圆点步进，
    /// 内容淡出且按钮禁交互。
    private var miniBarCollapsed = false
    /// 迷你台宠物层（3.7 (27)）：纯新增覆盖层，只经下面几处
    /// 一行钩子订阅台子的显隐/形态/切歌边沿，台子逻辑零改动。
    private var miniPetStage: MiniBarPetStage?
    private var miniIdleWorkItem: DispatchWorkItem?
    /// 上次 refreshMiniBar 同步的曲目 id：识别切歌（切歌先
    /// 完整形态再起计时）。
    private var miniLastTrackId: String?
    private var miniCover: UIImageView!
    private var miniTitle: UILabel!
    private var miniArtist: UILabel!
    private var miniPlayButton: UIButton!
    private var miniPrevButton: UIButton!
    private var miniNextButton: UIButton!
    private var miniQueueButton: UIButton!
    private var miniSeekHit: UIView!
    private var miniProgressFill: UIView!
    /// 进度拖动中：心跳不覆盖填充，松手 seek 后恢复。
    private var miniSeekDragging = false
    private var miniProgressTrack: UIView!
    private var miniProgressKnob: UIView!
    private var miniKnobLeading: NSLayoutConstraint?
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

    /// dismiss 统一拦截（3.7 (46)）：本墙 dismiss 若会带下其上
    /// 呈现的 canonical 舞台且无 StageExitGate 放行凭据、守卫
    /// 在期 → veto；只解墙自身之上盖层时闸门自动放行。
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if StageExitGate.shared.shouldVetoDismiss(from: self) { return }
        super.dismiss(animated: flag, completion: completion)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        // 播放台特效总开关/主题变更（设置页）即时同步。
        NotificationCenter.default.addObserver(
            self, selector: #selector(miniPlayerThemeSettingsChanged),
            name: .foliaMiniPlayerThemeChanged, object: nil)
        // 点播台按钮槽位变更（3.7 (50)，设置页）即时同步。
        NotificationCenter.default.addObserver(
            self, selector: #selector(miniBarSlotsChanged),
            name: .foliaMiniBarSlotsChanged, object: nil)
        // 确定性不可播被自动跳过（3.7 (28)）：闪现提示贴纸。
        NotificationCenter.default.addObserver(
            self, selector: #selector(stickerTrackSkippedUnplayable),
            name: .foliaTrackSkippedUnplayable, object: nil)

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

        // 墙内设置齿轮（3.7 (36)）：固定左上角（顶部带右上角是
        // 关闭键、正中是状态条，左上角不挡拼贴操作），样式与主
        // 界面边缘齿轮一致（34×34、半透明），点按打开同一个设
        // 置页；边缘老齿轮保留不动。
        let settingsGear = UIButton(type: .system)
        settingsGear.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        settingsGear.tintColor = .white
        settingsGear.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        settingsGear.layer.cornerRadius = 17
        settingsGear.alpha = 0.5
        settingsGear.accessibilityLabel = "设置"
        settingsGear.translatesAutoresizingMaskIntoConstraints = false
        settingsGear.addTarget(self, action: #selector(wallSettingsTapped), for: .touchUpInside)
        view.addSubview(settingsGear)
        NSLayoutConstraint.activate([
            settingsGear.widthAnchor.constraint(equalToConstant: 34),
            settingsGear.heightAnchor.constraint(equalToConstant: 34),
            settingsGear.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            settingsGear.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
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
        // 贴纸层（3.7 (24)，纯新增订阅）：切歌缓冲态驱动缓冲
        // 贴纸显隐，只读引擎状态，不回写。
        PlaybackEngine.shared.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.stickerBufferStateChanged(state) }
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
        progressDriver.onFraction = { [weak self] fraction in
            guard let self else { return }
            if let bar = self.miniBar, !bar.isHidden, !self.miniSeekDragging {
                self.setMiniProgress(fraction)
            }
            self.updateExpandedCardProgress(fraction)
        }

        let overlay = LyricWindowView()
        overlay.isHidden = true
        overlay.clock = { [weak self] in
            self?.lyricClockDriver.interpolatedNow() ?? PlaybackEngine.shared.rawPlayhead()
        }
        if let bar = miniBar { view.insertSubview(overlay, belowSubview: bar) } else { view.addSubview(overlay) }
        lyricOverlay = overlay
        lyricClockDriver.onTick = { [weak self] now in self?.lyricSessionTick(now: now) }

        loadEntries()
    }

    /// 底部播放台（3.7 (13) #7；13.1 改版，Miller 2026-11-18 亲定）：
    /// 封面缩略 + 标题/歌手 + 上一曲/播放暂停/下一曲 + 顶部可拖进度。
    /// 交互：点封面 = 定位到正在播放的歌曲；点台身 = 进播放详情页
    /// （openStage 同路）；进度条可拖动 seek；按键只管切歌播停。
    private func buildMiniBar() {
        // 3.7 (13.3) E 液态玻璃版（Miller 在 A–I 九款里点选 E）：
        // 全圆角玻璃胶囊——超薄系统材质 + 亮边描边 + 顶部高光线
        // 模拟 iOS 26 Liquid Glass 的折射 rim；封面改圆形；进度
        // 按 Miller 定版移到底部内缘：发光填充 + 发光圆钮把手，
        // 底部整带可拖可点。bar 本体只做容器与阴影，材质由第一
        // 层 UIVisualEffectView 承担并自裁圆角。
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
        let petStage = MiniBarPetStage(bar: bar)
        view.addSubview(petStage)
        miniPetStage = petStage

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

        // 玻璃高光：顶部一条亮线 + 整体一层极淡白罩，模拟玻璃
        // 边缘的折射光。不拦手势。
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

        // 发光圆钮：挂在轨道层外（轨道 clipsToBounds 会裁掉光晕），
        // 位置由 setMiniProgress 按填充比例同步。
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
        miniPrevButton.setImage(UIImage(systemName: "backward.end.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        miniPrevButton.translatesAutoresizingMaskIntoConstraints = false
        miniPrevButton.addTarget(self, action: #selector(miniPrevTapped), for: .touchUpInside)
        bar.addSubview(miniPrevButton)

        miniNextButton = UIButton(type: .system)
        miniNextButton.tintColor = .white
        miniNextButton.setImage(UIImage(systemName: "forward.end.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        miniNextButton.translatesAutoresizingMaskIntoConstraints = false
        miniNextButton.addTarget(self, action: #selector(miniNextTapped), for: .touchUpInside)
        bar.addSubview(miniNextButton)

        // 播放列表入口（3.7 (48)）：台面最右新增一键，开原生队列
        // 面板（管理面全在面板内，台面骨架不动）。键位链随既有
        // prev/play/next 相对约束自动左移，标题尾随 prev 不受影响。
        miniQueueButton = UIButton(type: .system)
        miniQueueButton.tintColor = .white
        miniQueueButton.setImage(UIImage(systemName: "music.note.list",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        miniQueueButton.translatesAutoresizingMaskIntoConstraints = false
        miniQueueButton.addTarget(self, action: #selector(miniQueueTapped), for: .touchUpInside)
        bar.addSubview(miniQueueButton)

        // 进度拖动手柄区：盖住底部进度条并向上放宽到 20pt 好按。
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

            miniNextButton.trailingAnchor.constraint(equalTo: miniQueueButton.leadingAnchor, constant: -2),
            miniNextButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            miniNextButton.widthAnchor.constraint(equalToConstant: 34),
            miniNextButton.heightAnchor.constraint(equalToConstant: 40),

            miniQueueButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            miniQueueButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            miniQueueButton.widthAnchor.constraint(equalToConstant: 34),
            miniQueueButton.heightAnchor.constraint(equalToConstant: 40),

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
        applyMiniBarSlots()
    }

    /// 点播台槽位应用（3.7 (50)）：按 MiniBarSlotSettings 显隐
    /// prev/next/queue 三键；隐藏时把该键宽度约束置 0，相对链
    /// 上的其余键与标题自动收拢补位（链间距 2pt 残留可忽略）。
    /// 宽度约束经按钮自身 constraints 反查（widthAnchor 常量
    /// 约束归按钮所有），不改构建期的约束块。收起态的 alpha/
    /// 交互名单含隐藏键也无妨：isHidden 恒压过 alpha 与命中。
    private func applyMiniBarSlots() {
        guard let prev = miniPrevButton, let next = miniNextButton,
              let queue = miniQueueButton else { return }
        applySlot(prev, visible: MiniBarSlotSettings.showPrev, width: 34)
        applySlot(next, visible: MiniBarSlotSettings.showNext, width: 34)
        applySlot(queue, visible: MiniBarSlotSettings.showQueue, width: 34)
    }

    private func applySlot(_ button: UIButton, visible: Bool, width: CGFloat) {
        button.isHidden = !visible
        if let constraint = button.constraints.first(where: {
            $0.firstAttribute == .width && $0.secondItem == nil
        }) {
            constraint.constant = visible ? width : 0
        }
    }

    @objc private func miniBarSlotsChanged() {
        applyMiniBarSlots()
    }

    /// 进度填充与发光圆钮的唯一步进点：心跳、拖动、点按跳点都走
    /// 这里，保证填充比例与圆钮位置永远一致。主题层的积雪/
    /// 鲨鳍/流星头位也在此转喂，同源同步。
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
            || miniNextButton.frame.contains(point)
            || miniQueueButton.frame.contains(point) { return }
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
        stickerNoteTrackChangeTap()
        QueueManager.shared.playPrevious()
    }

    @objc private func miniNextTapped() {
        resetMiniIdleTimer()
        stickerNoteTrackChangeTap()
        QueueManager.shared.playNext(manual: true)
    }

    /// 播放列表面板（3.7 (48)）：面板存续期间台面被 sheet 覆盖，
    /// 关闭后重置无操作计时，避免一关面板台面已收起。
    @objc private func miniQueueTapped() {
        resetMiniIdleTimer()
        QueuePanelViewController.present(from: self) { [weak self] in
            self?.resetMiniIdleTimer()
        }
    }

    /// 台面点按分发（13.1 定版、13.3 进度带改点按跳点）：按键各自
    /// 处理；封面 = 定位；底部进度带 = 跳到点按位置；其余台身 =
    /// 进播放详情页。封面判定仍先于进度带（两者仅在封面下缘约
    /// 2pt 相接，先判进度带会让点封面下缘变成跳进度）。
    @objc private func miniBarTapped(_ gesture: UITapGestureRecognizer) {
        guard let bar = miniBar else { return }
        // 收起态点按（3.7 (21)）：只展开回完整形态并重新计时，
        // 不走原分发（不 seek/不开台/不定位）。
        if miniBarCollapsed {
            expandMiniBar()
            return
        }
        // 完整形态的任何点按都算操作，重置无操作计时。
        resetMiniIdleTimer()
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point)
            || miniQueueButton.frame.contains(point) { return }
        if miniCover.frame.contains(point) {
            locateCurrentTrack()
            return
        }
        if miniSeekHit.frame.contains(point) {
            // 13.3 新增点按跳点：13.2 的点按被静默吞掉，是 Miller
            // 「没办法拖进度」反馈的来源之一。比例按轨道实际
            // 帧算，不按整条台面宽。
            let track = miniProgressTrack.frame
            let engine = PlaybackEngine.shared
            guard track.width > 0, engine.duration > 0 else { return }
            let fraction = min(max((point.x - track.minX) / track.width, 0), 1)
            setMiniProgress(Double(fraction))
            engine.seek(to: Double(fraction) * engine.duration)
            return
        }
        openNativeStageFromWall()
    }

    /// 进度拖动（13.1）：拖动中只更新填充，松手才 seek（防拖动
    /// 途中连环跳秒）；轻点进度区同样跳到该位置。终结状态先复位
    /// 拖动标记再走任何守卫——拖动途中切歌使 duration 归零时，
    /// 守卫先行会让标记永不复位、进度填充从此冻结（独立审查中-2）。
    /// 封面/按键的上沿落在命中带里，那里起手不抢手势（低-3）。
    @objc private func miniSeekPanned(_ gesture: UIPanGestureRecognizer) {
        guard miniSeekHit != nil, miniBar != nil else { return }
        let engine = PlaybackEngine.shared
        // 比例按轨道实际帧算（13.3）：轨道左右各内缩 20pt，按整条
        // 台面宽算会让拖动位置与填充对不上。轨道尚未布局（宽为 0）
        // 时整体不处理：算不出比例硬走流程会把填充清零、松手把歌
        // 跳回开头（13.3 独立审查低-1）；终结态仍先复位拖动标记。
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
                || miniNextButton.frame.contains(barPoint)
                || miniQueueButton.frame.contains(barPoint) { return }
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

    /// 迷你台显隐边沿动画（3.7 (20)，audit-3720 §三规格；与
    /// 主页墙同构）：只认 miniBarPresented 的 false↔true 边沿
    /// ——内容刷新（播/停、切歌）每次都走 refreshMiniBar，但
    /// 动画只在 currentTrack nil→非 nil（入场）与非 nil→nil
    /// （退场）时播。入场：alpha 0→1 + 自下方 16pt 升起回落 +
    /// 缩放 0.98→1，系统弹簧 0.65s/damping 0.88；台面毛玻璃
    /// effect 从 nil 在同一段动画里渐入（系统交叉淡化）——
    /// 玻璃「显影」即像画慢慢铺开；封面以 0.05s 延迟做
    /// 0.92→1 次级缩放。退场对称：0.28s 淡出 + 下沉 8pt，
    /// 完成后才置 hidden。Reduce Motion 时降级为纯 alpha
    /// 淡化（0.2s、无位移缩放、effect 直接置位）。
    private func setMiniBarVisible(_ visible: Bool) {
        guard let bar = miniBar else { return }
        miniThemeLayer?.setBarVisible(visible)
        guard visible != miniBarPresented else { return }
        miniBarPresented = visible
        // 显隐边沿留痕（3.7 (29)）：guard 已保证 visible 与旧值
        // 相反，old 即 !visible；附当时宠物开关值便于对账。
        Breadcrumbs.log("minibar.visibility.edge requested=\(visible)"
            + " old=\(!visible) new=\(visible)"
            + " miniPets=\(StickerSettings.miniPetsEnabled)")
        miniPetStage?.barPresentationChanged(visible)
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

    // MARK: - 迷你台收起（3.7 (21)：5 秒无操作自动收成进度条，与主页墙同构）

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
        miniPetStage?.barFormChanged(collapsed: true)
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
        miniPetStage?.barFormChanged(collapsed: false)
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
                                miniPrevButton, miniNextButton, miniQueueButton]
        for view in views {
            view?.alpha = alpha
        }
    }

    private func setMiniBarContentsInteractive(_ interactive: Bool) {
        let buttons: [UIButton?] = [miniPlayButton, miniPrevButton, miniNextButton, miniQueueButton]
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

    /// 播放台内容同步：有当前曲才显示；封面优先引擎现图，缺了走
    /// 封面链按当前曲 id 校验后补。
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
            miniPetStage?.setTrack(id: track.id)
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

    /// 点播放台封面定位（3.7 (13) #7；13.1 改点封面）：相机平滑
    /// 移到当前曲最近的一份拷贝并展开（时长按距离缩放、展开步
    /// 交叉淡化，治 13 真机「衔接不丝滑」）；当前曲不在本歌单
    /// 时给人话提示。
    /// 定位目标冻结（3.7 (13.2)，DS34）：点按瞬间定格目标 id/标题/
    /// 下标，飞行、校验、纠正全程用冻结值——飞行途中若发生切歌，
    /// 实时 currentTrack 已是下一首，拿它校验会把纠正带偏。
    private var locateTargetId: String?
    private var locateTargetTitle: String?
    private var locateTargetIndex: Int?
    private var locateReflied = false
    /// 本次飞行要展开的实例（校验时与当前展开态比对，区分落点错与
    /// 用户已接管展开态——独立审查中-1）；代次防旧校验在新飞行途中
    /// 误触发（低-2）。
    private var locateFlightInstanceId: String?
    private var locateGeneration = 0

    /// P6 落点强调（3.7 (40) 项9）：飞行落定、展开交叉淡化
    /// 后，墙面以 1.02 蓄势经系统弹簧（0.5s / damping
    /// 0.85，与迷你台收起弹簧同参）落回 1.0，给落点弹性
    /// 收尾，替原「淡化完即硬停」；完成复位 transform、
    /// 无残留遮罩/缩放。展开本身仍走既有交叉淡化，不另
    /// 造 morph（(13) 已否伪 morph 与播放页动画打架）。
    private func emphasizeLocateLanding() {
        Breadcrumbs.log("locate land settle begin")
        guard !UIAccessibility.isReduceMotionEnabled else {
            collectionView.transform = .identity
            Breadcrumbs.log("locate land settle end reduced=1")
            return
        }
        collectionView.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0.1,
                       options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.collectionView.transform = .identity
        } completion: { [weak self] _ in
            self?.collectionView.transform = .identity
            Breadcrumbs.log("locate land settle end")
        }
    }

    private func locateCurrentTrack() {
        locateGeneration += 1
        guard let current = PlaybackEngine.shared.currentTrack else { return }
        let currentId = current.id
        // 全部匹配都数：id 若重复，firstIndex 会命中第一个而非本曲，
        // sameId>1 时面包屑立现（DS34 字段清单）。
        let matches = entries.indices.filter { entries[$0].id == currentId }
        locateTargetId = currentId
        locateTargetTitle = current.title
        locateTargetIndex = matches.first
        locateReflied = false
        Breadcrumbs.log("locate start target=\(currentId) title=\(current.title) "
            + "queueIndex=\(matches.first ?? -1) sameId=\(matches.count) "
            + "ui=\(miniTitle.text ?? "") entries=\(entries.count)/\(wallLayout.totalEntries)")
        guard let queueIndex = matches.first else {
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
            self.emphasizeLocateLanding()
            // 落点校验（3.7 (13.2)）：淡化落定后核对展开的确实是
            // 冻结目标，不是就纠正/重飞，全程面包屑（DS34）。
            self.locateFlightInstanceId = target.instanceId
            let gen = self.locateGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.verifyLocateLanding(generation: gen)
            }
        }
    }

    /// 落点校验与纠正（3.7 (13.2)）：展开实例的条目 id 与冻结目标
    /// 不符时，先在当前实例集里找同 queueIndex 的实例改展开；找不
    /// 到允许重飞一次；再失败记 FAIL 并给人话提示。
    private func verifyLocateLanding(generation: Int) {
        guard let targetId = locateTargetId,
              let targetIndex = locateTargetIndex else { return }
        // 代次过期（新定位已起飞）或展开态已被用户接管（收起/改展开
        // 了别的卡）：不判落点错，收手（独立审查中-1/低-2）。
        guard generation == locateGeneration,
              wallLayout.expandedInstanceId == locateFlightInstanceId else {
            Breadcrumbs.log("locate verify skipped gen=\(generation)/\(locateGeneration)")
            return
        }
        let expanded = wallLayout.instances.first {
            $0.instanceId == wallLayout.expandedInstanceId
        }
        let gotId = expanded.flatMap {
            $0.queueIndex < entries.count ? entries[$0.queueIndex].id : nil
        }
        if gotId == targetId {
            Breadcrumbs.log("locate ok target=\(targetId) queueIndex=\(targetIndex)")
            return
        }
        let gotTitle = expanded.flatMap {
            $0.queueIndex < entries.count ? entries[$0.queueIndex].title : nil
        }
        Breadcrumbs.log("locate verify FAIL expected=\(targetId) "
            + "got=\(gotId ?? "nil") expandedQueueIndex=\(expanded?.queueIndex ?? -1) "
            + "expectedTitle=\(locateTargetTitle ?? "") gotTitle=\(gotTitle ?? "nil")")
        // 纠正：同 queueIndex 的拷贝挑离视口中心最近的一份（低-1），
        // 改完复验 id，仍不符继续走重飞/失败路径，不静默收场。
        let scale = wallLayout.cameraScale
        let centerX = Double(wallLayout.worldOrigin.x)
            + Double(collectionView.bounds.width) / scale / 2
        let centerY = Double(wallLayout.worldOrigin.y)
            + Double(collectionView.bounds.height) / scale / 2
        let correct = wallLayout.instances
            .filter { $0.queueIndex == targetIndex }
            .min { a, b in
                let da = pow(a.rect.x + a.rect.width / 2 - centerX, 2)
                    + pow(a.rect.y + a.rect.height / 2 - centerY, 2)
                let db = pow(b.rect.x + b.rect.width / 2 - centerX, 2)
                    + pow(b.rect.y + b.rect.height / 2 - centerY, 2)
                return da < db
            }
        if let correct,
           correct.queueIndex < entries.count,
           entries[correct.queueIndex].id == targetId {
            wallLayout.expandedInstanceId = correct.instanceId
            locateFlightInstanceId = correct.instanceId
            wallLayout.refreshInstances()
            collectionView.reloadData()
            Breadcrumbs.log("locate corrected instance=\(correct.instanceId) entry=\(targetId)")
            return
        }
        if !locateReflied {
            locateReflied = true
            Breadcrumbs.log("locate refly target=\(targetId) queueIndex=\(targetIndex)")
            locateCurrentTrackFrozen()
            return
        }
        // 失败提示直接报双歌名（13.3，DS35 最小证据要求）：用户一张
        // 截图就能定案落点错在哪，不必再取日志。歌名各截 12 字防
        // 长名把胶囊撑截断（13.3 独立审查低-3），全名在面包屑里。
        let wantShort = String((locateTargetTitle ?? targetId).prefix(12))
        let gotShort = String((gotTitle ?? "未知").prefix(12))
        let failText = "定位失败：要找《\(wantShort)》，落到《\(gotShort)》"
        statusLabel.text = failText
        statusLabel.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.statusLabel.text == failText else { return }
            self.statusLabel.text = "墙原型：\(self.wallLayout.totalEntries) 首 · 拖动平移 · 点按展开"
        }
    }

    /// 重飞（校验纠正专用）：目标已冻结，直接按冻结下标找最近拷贝，
    /// 不重读 currentTrack（防切歌竞态把目标带偏，DS34）。
    private func locateCurrentTrackFrozen() {
        locateGeneration += 1
        guard let targetIndex = locateTargetIndex else { return }
        let scale = wallLayout.cameraScale
        let viewWorldW = Double(collectionView.bounds.width) / scale
        let viewWorldH = Double(collectionView.bounds.height) / scale
        let centerX = Double(wallLayout.worldOrigin.x) + viewWorldW / 2
        let centerY = Double(wallLayout.worldOrigin.y) + viewWorldH / 2
        guard let target = WallGeometry.locateNearestInstance(
            geometry: wallLayout.geometry, totalEntries: wallLayout.totalEntries,
            queueIndex: targetIndex, pointX: centerX, pointY: centerY,
            metrics: wallLayout.metrics) else { return }
        if wallLayout.expandedInstanceId != nil {
            wallLayout.expandedInstanceId = nil
            wallLayout.refreshInstances()
            collectionView.reloadData()
        }
        let targetOrigin = CGPoint(
            x: CGFloat(target.rect.x + target.rect.width / 2 - viewWorldW / 2),
            y: CGFloat(target.rect.y + target.rect.height / 2 - viewWorldH / 2))
        let distance = hypot(targetOrigin.x - wallLayout.worldOrigin.x,
                             targetOrigin.y - wallLayout.worldOrigin.y)
        let duration = min(0.85, max(0.45, Double(distance) * 0.00035))
        animateWorldOrigin(to: targetOrigin, duration: duration) { [weak self] in
            guard let self else { return }
            self.wallLayout.expandedInstanceId = target.instanceId
            self.wallLayout.refreshInstances()
            UIView.transition(with: self.collectionView, duration: 0.25,
                              options: [.transitionCrossDissolve]) {
                self.collectionView.reloadData()
            }
            self.emphasizeLocateLanding()
            self.locateFlightInstanceId = target.instanceId
            let gen = self.locateGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.verifyLocateLanding(generation: gen)
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
        // P6 飞行起飞留痕（3.7 (40) 项9）：弹簧口径与参数供
        // 真机对账（damping 与全仓既有弹簧 0.85–0.88 同族）。
        Breadcrumbs.log("locate flight spring begin dur=\(String(format: "%.2f", duration)) damping=0.85")
        let link = CADisplayLink(target: self, selector: #selector(locateTick(_:)))
        link.add(to: .main, forMode: .common)
        locateLink = link
    }

    /// P6 弹簧进度（3.7 (40) 项9）：欠阻尼弹簧阶跃响应
    /// （ζ=0.85、归一化 ω=6），替原 easeInOut 三次曲线
    /// （raw<0.5 ? 2raw² : …）——原曲线中段近匀速、末端
    /// 硬停，是真机「近匀速长距离平移 + 突兀落点」的主因。
    /// 弹簧进度起步速度为零、中段快、末段自然减速收敛，
    /// 超调约 0.6%（不可见量级），raw≥1 由 tick 精确吸附
    /// 目标点。位置与缩放共用同一进度（见 locateTick 的
    /// 钟形缩放），不分段、不另起第二支动画。
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
        let before = setIdentity()
        wallLayout.worldOrigin = CGPoint(
            x: locateStartOrigin.x + (locateTargetOrigin.x - locateStartOrigin.x) * CGFloat(eased),
            y: locateStartOrigin.y + (locateTargetOrigin.y - locateStartOrigin.y) * CGFloat(eased))
        // 缩放同支弹簧（P6）：飞行中段轻微放大（钟形，峰值
        // 1.03、由同一弹簧进度驱动），落点回到 1.0——位置
        // 与缩放同曲线插值，无分段跳变；Reduce Motion 不缩放。
        if UIAccessibility.isReduceMotionEnabled {
            collectionView.transform = .identity
        } else {
            let bell = CGFloat(eased * (1 - eased) * 4)
            collectionView.transform = CGAffineTransform(scaleX: 1 + 0.03 * bell,
                                                         y: 1 + 0.03 * bell)
        }
        wallLayout.refreshInstances()
        if setIdentity() != before { collectionView.reloadData() }
        if raw >= 1 {
            link.invalidate()
            locateLink = nil
            // 落点定格干净：原点精确吸附目标、缩放复位，
            // 不留钟形缩放残值给后续展开/歌词锚定。
            wallLayout.worldOrigin = locateTargetOrigin
            wallLayout.refreshInstances()
            collectionView.transform = .identity
            Breadcrumbs.log("locate flight spring end")
            let done = locateCompletion
            locateCompletion = nil
            done?()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lyricClockDriver.start()
        progressDriver.start()
        miniThemeLayer?.setHostVisible(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        lyricClockDriver.stop()
        // 翻行 observer 随墙消失解绑防泄漏（回墙后 tick 重新绑定）。
        lyricFlipDriver.unbind()
        // 迷你台无操作计时随墙消失取消（回墙 viewDidAppear 续命）。
        cancelMiniIdleTimer()
        setLyricOverlayVisible(false)
        progressDriver.stop()
        miniThemeLayer?.setHostVisible(false)
        locateLink?.invalidate()
        locateLink = nil
        locateCompletion = nil
        // P6 状态干净（3.7 (40) 项9）：飞行途中离墙时缩放
        // 必须复位，不许把钟形缩放残值带回下次露面。
        collectionView.transform = .identity
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Breadcrumbs.log("wall.appear kind=playlist")
        Breadcrumbs.log("tracks appear playlist=\(playlistId)")
        Breadcrumbs.samplerStart()
        refreshMiniBar()
        // 迷你台无操作计时（3.7 (21)）：回墙即续命（在场且
        // 完整形态才起，resetMiniIdleTimer 内部把关）。
        resetMiniIdleTimer()
        // 转场落位（3.7 (40) 项8）：入场 1.04 蓄势的收回改系统
        // 弹簧（原为 0.35s curveEaseOut 非弹簧收尾，与主页侧
        // crossDissolve 叠化不在同一族、落点生硬）。与 (23)
        // 齿轮进主页的叠化直溶同族：交叉淡化（present 侧
        // .crossDissolve）+ 轻微缩放弹簧落位；完成复位
        // transform，不留残留缩放。Reduce Motion 直接落位。
        Breadcrumbs.log("transition poster settle begin playlist=\(playlistId)")
        if UIAccessibility.isReduceMotionEnabled {
            collectionView.transform = .identity
            Breadcrumbs.log("transition poster settle end reduced=1")
        } else {
            UIView.animate(withDuration: 0.55, delay: 0,
                           usingSpringWithDamping: 0.86, initialSpringVelocity: 0.12,
                           options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                self.collectionView.transform = .identity
            } completion: { [weak self] _ in
                self?.collectionView.transform = .identity
                Breadcrumbs.log("transition poster settle end playlist=\(self?.playlistId ?? "-")")
            }
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
        // 拍立得背板关闭契约（3.7 (24) 起）：旋转动画取消后
        // requestClose 恒放行，点关闭即收墙。
        if let backdrop, !backdrop.requestClose() { return }
        dismiss(animated: true)
    }

    /// 墙内齿轮打开设置页：与主界面边缘齿轮同一呈现方式
    /// （overFullScreen 浮层、animated: false）。
    @objc private func wallSettingsTapped() {
        let settings = SettingsViewController()
        settings.modalPresentationStyle = .overFullScreen
        present(settings, animated: false)
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
        // 贴纸层（3.7 (24)，纯新增）：新一轮加载先收空态贴纸。
        stickerLoadStarted()
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
                    self.loadAttempts = 0
                    self.loadFailed = false
                    Breadcrumbs.log("tracks seed ok n=\(seed.count)/\(total)")
                    self.seedReady = true
                    self.flushSeedWaiters()
                    self.waveStart = Date()
                    self.backdrop?.dismiss()
                    // 贴纸层（3.7 (24)，纯新增）：空歌单出空态贴纸。
                    if total == 0 { self.stickerShowEmptyPlaylist() }
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        centerCameraIfNeeded()
        updateLyricOverlayFrame()
        // 迷你台宽度按竖屏定版（3.7 (21)）：min(宽,高) 即竖屏
        // 布局宽（横屏时宽高互换），减两侧各 12 边距；横竖屏
        // 同一宽度、居中，横屏左右留白。
        let portraitBarWidth = min(view.bounds.width, view.bounds.height) - 24
        if let constraint = miniBarWidthConstraint,
           abs(constraint.constant - portraitBarWidth) > 0.5 {
            constraint.constant = portraitBarWidth
        }
        // 贴纸层（3.7 (24)，纯新增）：失败/空态/缓冲贴纸定位。
        stickerLayoutOverlays()
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
        updateLyricOverlayFrame()
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
        if instance.instanceId == wallLayout.expandedInstanceId {
            let crumb = "\(indexPath.item)|\(instance.queueIndex)|\(tier)|\(!cell.hasCoverImage)|\(cell.hasPlaceholderCover)"
            if crumb != lastExpandedCellCrumb {
                lastExpandedCellCrumb = crumb
                Breadcrumbs.log("wall expanded cell item=\(indexPath.item) queueIndex=\(instance.queueIndex) tier=\(tier) imageNil=\(!cell.hasCoverImage) placeholder=\(cell.hasPlaceholderCover)")
            }
        }
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
        let queueIndex = instance.queueIndex
        cell.onPlayTap = { [weak self] in self?.playTapped(queueIndex: queueIndex) }
        cell.onLikeTap = { [weak self] in self?.likeTapped(queueIndex: queueIndex) }
    }

    /// 原生舞台入口（3.7 (14)，M2'）：迷你台台身与双击卡片改走
    /// 原生舞台。墙不退场——舞台全屏盖在墙上、关闭即纯 dismiss
    /// 回墙。跳网页舞台（未迁样式/回退）由舞台自身叠加 present
    /// 网页宿主（3.7 (51) 新链，见 StageViewController 的
    /// jumpToWebStage）；原 openStageFromWall 回程票套（存票+收
    /// 墙+凭票恢复）已随回程票链整链删除（3.7 (51)）。
    private func openNativeStageFromWall() {
        Breadcrumbs.log("stage open (native) from playlist wall")
        let stage = StageViewController()
        stage.modalPresentationStyle = .fullScreen
        present(stage, animated: true)
    }

    /// 后台点入直达（3.7 (31)）：SceneDelegate 在「曾进后台 + 有活跃
    /// 队列 + 本墙正是顶层」时调用，与迷你台/双击卡同路进原生舞台，
    /// 不另造入口。
    func openNativeStageForBackgroundReturn() {
        openNativeStageFromWall()
    }

    /// 双击卡片进播放页（3.7 (13) #8b）：双击的不是当前曲时先切
    /// 队列再开页（原生队列同步落位，桥快照即新当前曲）；单击
    /// 展开保持原样、不等双击判定，第一击的展开是无害前置。
    @objc private func wallDoubleTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              indexPath.item < wallLayout.instances.count else { return }
        var instance = wallLayout.instances[indexPath.item]
        // 命中加固（3.7 (13.2)）：第一击展开会重排布局，第二击的落点
        // 按新布局命中可能落到邻卡；落点若在已展开卡的框内，以展开
        // 卡为准——用户双击的只会是刚展开的那张。
        if let expandedId = wallLayout.expandedInstanceId,
           let expItem = wallLayout.instances.firstIndex(where: { $0.instanceId == expandedId }),
           let attrs = collectionView.layoutAttributesForItem(
               at: IndexPath(item: expItem, section: 0)),
           attrs.frame.contains(point),
           wallLayout.instances[expItem].queueIndex != instance.queueIndex {
            Breadcrumbs.log("wall double tap hit corrected expanded=\(wallLayout.instances[expItem].queueIndex) raw=\(instance.queueIndex)")
            instance = wallLayout.instances[expItem]
        }
        guard instance.queueIndex < entries.count else { return }
        Breadcrumbs.log("wall double tap queueIndex=\(instance.queueIndex) id=\(entries[instance.queueIndex].id) title=\(entries[instance.queueIndex].title)")
        if PlaybackEngine.shared.currentTrack?.id != entries[instance.queueIndex].id {
            startQueueAt(queueIndex: instance.queueIndex)
        }
        openNativeStageFromWall()
    }

    private func refreshVisiblePlaybackUI() {
        for case let cell as WallPosterCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  indexPath.item < wallLayout.instances.count else { continue }
            applyPlaybackState(to: cell, instance: wallLayout.instances[indexPath.item])
        }
    }

    /// 展开卡进度线逐帧推进（progressDriver 回调）：只认展开中的
    /// 当前曲卡，与 lyricSessionTick 的歌词推进分工。
    private func updateExpandedCardProgress(_ fraction: Double) {
        guard let currentId = PlaybackEngine.shared.currentTrack?.id else { return }
        for case let cell as WallPosterCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  indexPath.item < wallLayout.instances.count else { continue }
            let instance = wallLayout.instances[indexPath.item]
            guard instance.queueIndex < entries.count,
                  entries[instance.queueIndex].id == currentId,
                  wallLayout.expandedInstanceId == instance.instanceId else { continue }
            cell.updateProgress(fraction)
        }
    }

    /// 滚动歌词会话（包一 P2/P3）：歌词渲染在独立 overlay 上、
    /// 不绑 cell——展开实例不在 visibleCells、cell 被复用、展开
    /// 别的卡时都不再灭词。
    ///
    /// 翻行主路径（3.7 (23)，DS R49 改主推荐）：由呈现钟 judge
    /// 直驱——本 tick 的 now 即 lyricClockDriver 的 judge
    /// （rawPlayhead 锚定、与扫光同钟），逐帧按时间区间取最后
    /// 命中行，judge 跨行界即当帧提交行状态（高亮+扫光相位
    /// 经 setWindow 同帧下发），窗体滑行动画只动 transform、
    /// 随后落位，高亮不等落位。翻行与扫光同钟后，audit-3723
    /// 拍到的「同卡两钟不一致」（扫光已过半而行未翻）在结构
    /// 上不可能再出现。(21) 的 boundary 事件驱动降为校准源：
    /// lyricFlipDriver 照常 bind/tick（注册、护栏、延迟采样、
    /// 兜底状态机保留），其 currentIndex 不再决定 UI 当前行，
    /// 只供同行翻行时落 judge 与 boundary 两源 lag 之差对账。
    private func lyricSessionTick(now: Double) {
        // 翻行呈现段埋点（3.7 (23)）：上一帧提交的翻行在本帧
        // 顶部结算「判定→呈现」耗时——tick 由显示链驱动，本
        // 帧即提交后的首个呈现帧。
        if let pending = pendingFlipPresent {
            pendingFlipPresent = nil
            Breadcrumbs.log("lrc flip present idx=\(pending.idx) dt=\(String(format: "%.3f", CACurrentMediaTime() - pending.wall))")
        }
        let engine = PlaybackEngine.shared
        guard let track = engine.currentTrack, engine.duration > 0 else {
            setLyricOverlayVisible(false)
            return
        }
        if engine.isPlaying, engine.currentTime > 0, firstAudioTrackId != track.id {
            firstAudioTrackId = track.id
            Breadcrumbs.log("lrc first-audio track=\(track.id) mediaTime=\(String(format: "%.3f", engine.currentTime)) mono=\(String(format: "%.3f", CACurrentMediaTime()))")
        }
        if lyricSessionTrackId != track.id {
            lyricSessionTrackId = track.id
            lastLyricIndex = nil
            lyricAnchorInstanceId = nil
            // 切歌先解绑旧曲行界（新曲歌词到手后 tick 内重新绑定）。
            lyricFlipDriver.unbind()
            // 切歌重置锚隐藏态：淡出动画与 alpha 不许带进新曲。
            if lyricAnchorHidden {
                lyricAnchorHidden = false
                lyricOverlay?.layer.removeAllAnimations()
                lyricOverlay?.alpha = 1
            }
        }
        guard wallLayout.expandedInstanceId != nil else {
            setLyricOverlayVisible(false)
            return
        }
        guard let entry = LyricRepository.shared.cachedEntry(for: track.id) else {
            ensureLyrics(for: track.id)
            setLyricOverlayVisible(false)
            return
        }
        let lines = entry.lines
        guard !lines.isEmpty else {
            setLyricOverlayVisible(false)
            return
        }
        // 校准源推进（3.7 (23)）：boundary 驱动照常绑定与推进
        // 护栏状态机（注册/兜底/延迟采样保留），但不再决定翻
        // 行；其兜底状态仍供下方 lineActive 的事件兜底判据。
        lyricFlipDriver.bind(trackId: track.id, lines: lines)
        lyricFlipDriver.tick(rawNow: engine.rawPlayhead(),
                             isPlaying: engine.isPlaying,
                             seekPending: engine.isSeekPending)
        // seek 护栏（3.7 (23)）：在途不提交翻行（judge 在落点
        // 定案前是旧锚外推）；落定边沿清去重态，下一帧起按
        // judge 直接重算当前行、直落不滑行。
        if engine.isSeekPending {
            wasSeekPendingLyric = true
            return
        }
        if wasSeekPendingLyric {
            wasSeekPendingLyric = false
            lastLyricIndex = nil
            lastLyricActive = true
        }
        // 翻行判定（3.7 (23) 主路径）：judge 按时间区间取最后
        // 命中行（二分）。一帧内跨多界（密集行/主线程卡顿后
        // 恢复）只提交最终行——中间行不逐个补翻，即密集行合
        // 并；暂停时 judge 冻结（时钟驱动锚为暂停态），idx
        // 恒定不翻；恢复时时钟以 rawPlayhead 重锚，judge 即
        // 当前位置、直接落当前行不补翻。
        let idx = Self.judgeLineIndex(in: lines, at: now + LyricTiming.lead)
        // 前奏预告态（3.7 (13) #2）：还没唱到首行时窗口只预告，
        // 不点亮不扫光；active 翻转也要重下发（同 idx 不能被去重吞掉）。
        // 事件路径下当前行已被 boundary/代翻消费即视为已激活
        // （呈现 now (22) 起与媒体时刻同尺，此条只作事件路径
        // 的兜底判据）。
        let lineActive = lines[idx].time <= now + LyricTiming.lead
            || (lyricFlipDriver.isActive && idx <= lyricFlipDriver.consumedThrough)
        // 帧锚定（3.7 (17) 口径 + (19) 出窗策略）：歌词只在锚得
        // 到播放曲自己的封面卡时显示。.anchored / .outOfWindow
        // 的可见性由 updateLyricOverlayFrame 内的锚状态机管理
        // （出窗淡出隐藏、不清行窗，回窗淡入恢复）；只有
        // .noCandidate（窗内无播放曲实例且无原锚）走硬隐藏。
        let anchorOutcome = updateLyricOverlayFrame()
        if anchorOutcome == .noCandidate {
            setLyricOverlayVisible(false)
        }
        if lastLyricTrackId == track.id, lastLyricIndex == idx,
           lastLyricActive == lineActive { return }
        if lastLyricIndex != idx || lastLyricTrackId != track.id {
            Breadcrumbs.log("lrc line track=\(track.id) idx=\(idx) lineStart=\(String(format: "%.3f", lines[idx].time)) judge=\(String(format: "%.3f", now)) raw=\(String(format: "%.3f", engine.rawPlayhead())) engine=\(String(format: "%.3f", engine.currentTime)) delta=\(String(format: "%.3f", now - engine.currentTime)) outLat=\(String(format: "%.3f", lyricClockDriver.rawOutputLatency)) route=\(lyricClockDriver.currentRouteName)")
        }
        // 翻行提交埋点（3.7 (23)）：同曲行号变化 = 一次 judge
        // 翻行——落提交时刻（present 段在下一帧 tick 顶部结
        // 算）与两源对账：judgeLag = 本帧 judge 越过行界的量；
        // boundary 已翻到同一行时同记其回调 lag 与差值，未翻
        // 到记 na（下版日志据此看两源谁先谁后、差多少）。
        if lastLyricTrackId == track.id, let prev = lastLyricIndex, prev != idx {
            pendingFlipPresent = (idx: idx, wall: CACurrentMediaTime())
            let judgeLag = now - lines[idx].time
            if let boundary = lyricFlipDriver.lastBoundaryFlip, boundary.index == idx {
                Breadcrumbs.log("lrc flip src=judge track=\(track.id) idx=\(idx) judgeLag=\(String(format: "%.3f", judgeLag)) boundaryLag=\(String(format: "%.3f", boundary.lag)) delta=\(String(format: "%.3f", judgeLag - boundary.lag))")
            } else {
                Breadcrumbs.log("lrc flip src=judge track=\(track.id) idx=\(idx) judgeLag=\(String(format: "%.3f", judgeLag)) boundaryLag=na")
            }
        }
        // 当前行时长：有下一行按行距夹取，末行按字数估（DS27 定版）。
        // 3.7 (43) 路3：再乘演唱跨度压缩比 r（仓库标定，与舞
        // 台均分共用同一 r 源）——lineDuration 只喂扫光的行级
        // 回落路径（有逐字戳时 sweepTick 走真戳、不读它），
        // 乘 r 即把行尾气口从扫光跨度里摘掉，翻行判定不读
        // 此值、零触碰。
        let duration: Double
        if idx + 1 < lines.count {
            duration = min(max(lines[idx + 1].time - lines[idx].time, 0.8), 10)
                * entry.singingRatio
        } else {
            duration = min(max(Double(lines[idx].text.count) * 0.4, 2.5), 8)
                * entry.singingRatio
        }
        // 6 行窗口：当前行居中（行 2），行 5 是滑入预备行。
        let texts = (-2...3).map { offset -> String in
            let j = idx + offset
            return (j >= 0 && j < lines.count) ? lines[j].text : ""
        }
        // 最小驻留（3.7 (23)）：新行驻留短于滑行时长（0.18s）
        // 时不滑行——滑完之前又要翻行只会积压动画，直落呈现。
        let dwell = idx + 1 < lines.count
            ? lines[idx + 1].time - lines[idx].time : Double.infinity
        let slide = lastLyricTrackId == track.id && lastLyricIndex == idx - 1
            && dwell >= 0.18
        lastLyricTrackId = track.id
        lastLyricIndex = idx
        lastLyricActive = lineActive
        lyricOverlay?.setWindow(texts: texts, lineStart: lines[idx].time,
                                lineDuration: duration, slide: slide,
                                lineActive: lineActive,
                                lineWords: lines[idx].words)
    }

    /// judge 当前行判定（3.7 (23)）：按时间区间取最后一个行
    /// 界 ≤ t 的行（二分）；t 早于首行返回 0（前奏预告态由
    /// lineActive=false 表达）。行表按时间升序（解析器保证）。
    private static func judgeLineIndex(in lines: [LyricLineData], at t: Double) -> Int {
        var lo = 0
        var hi = lines.count - 1
        var result = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= t {
                result = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    private func setLyricOverlayVisible(_ show: Bool) {
        guard let overlay = lyricOverlay else { return }
        if show {
            overlay.isHidden = false
        } else {
            guard !overlay.isHidden else { return }
            overlay.isHidden = true
            overlay.clear()
            lastLyricIndex = nil
        }
    }

    /// 锚定结果三态（3.7 (19)）：.anchored 已锚上并可见；
    /// .outOfWindow 原锚出 overscan 窗口、已淡出隐藏（行窗保
    /// 持，回窗恢复）；.noCandidate 窗内无播放曲实例且无原锚
    /// （含无展开/无当前曲），由 tick 走硬隐藏。
    private enum LyricAnchorOutcome {
        case anchored, outOfWindow, noCandidate
    }

    /// overlay 帧锚定（3.7 (17) 口径，Miller 13:04 定版；(19)
    /// 出窗策略经 DS R44 对账）：歌词帧只锚「正在播放歌曲的封
    /// 面卡实例」在墙坐标系中的世界矩形，平移时随卡一起移动；
    /// 不停靠视口、不压别曲封面。
    ///
    /// 帧换算与相机折叠模型对齐：布局属性帧 =（世界 − 原点）×
    /// scale + contentOffset，视觉帧 = 属性帧 − contentOffset +
    /// collectionView 在 view 中的原点（本 VC 中 collectionView
    /// 铺满 view、原点为 0，仍按通式写）。取属性帧而非 cell 帧：
    /// 不依赖 cell 是否在场，消除 reload 间隙的贴合/停靠横跳；
    /// 展开中的播放曲实例自动取到展开块矩形。
    ///
    /// 候选集（3.7 (19) 收紧）：同曲多实例只允许两个候选——
    /// 展开中的播放曲实例（接管成为新原锚）与原锚本身。原锚
    /// 仍在实例窗口内就保持（hysteresis）；原锚滑出 overscan
    /// 窗口时**隐藏不重锚**——(17) 的旧行为是就近改锚到同曲
    /// 另一张平铺封面，歌词瞬移他卡（audit-3718 §三推测头号，
    /// R44 采纳修法）；原锚或展开实例回窗时淡入恢复，隐藏期
    /// 间 tick 照常推进行窗与扫光（不清行窗），恢复即是当前
    /// 行与当前相位、无闪。无原锚时首次锚定取窗内离视口中心
    /// 最近的实例成为原锚，此后不再跨实例。
    @discardableResult
    private func updateLyricOverlayFrame() -> LyricAnchorOutcome {
        guard let overlay = lyricOverlay,
              wallLayout.expandedInstanceId != nil,
              let trackId = PlaybackEngine.shared.currentTrack?.id else { return .noCandidate }
        // 实例窗口 = 当前 instances 集（世界窗 + overscan 900）。
        let inWindow = wallLayout.instances.filter {
            $0.queueIndex < entries.count && entries[$0.queueIndex].id == trackId
        }
        let expanded = wallLayout.expandedInstanceId.flatMap { id in
            inWindow.first { $0.instanceId == id }
        }
        let currentAnchor = lyricAnchorInstanceId.flatMap { id in
            inWindow.first { $0.instanceId == id }
        }
        let target: QueueInstance?
        var restoreReason = "back-in-window"
        if let expanded, expanded.instanceId != lyricAnchorInstanceId {
            // 展开接管：展开的正是播放曲卡，它成为新原锚。
            target = expanded
            restoreReason = "expanded-takeover"
        } else if let currentAnchor {
            target = currentAnchor
        } else if lyricAnchorInstanceId != nil {
            // 原锚出窗：隐藏，不跨实例重锚。
            setLyricAnchorHidden(true, reason: "out-of-window")
            return .outOfWindow
        } else if let expanded {
            target = expanded
        } else if !inWindow.isEmpty {
            // 首次锚定：窗内离视口中心最近的实例成为原锚。
            let centerWorld = CGPoint(
                x: Double(wallLayout.worldOrigin.x) + Double(view.bounds.width) / wallLayout.cameraScale / 2,
                y: Double(wallLayout.worldOrigin.y) + Double(view.bounds.height) / wallLayout.cameraScale / 2)
            target = inWindow.min { a, b in
                let da = hypot(a.rect.left + a.rect.width / 2 - Double(centerWorld.x),
                               a.rect.top + a.rect.height / 2 - Double(centerWorld.y))
                let db = hypot(b.rect.left + b.rect.width / 2 - Double(centerWorld.x),
                               b.rect.top + b.rect.height / 2 - Double(centerWorld.y))
                return da < db
            }
            restoreReason = "initial-anchor"
        } else {
            // 窗内无播放曲实例且无原锚：无处可锚，帧不许停在旧
            // 视口坐标冒充锚定（(15) 的冻结帧正是此形态）。
            return .noCandidate
        }
        guard let target,
              let item = wallLayout.instances.firstIndex(where: { $0.instanceId == target.instanceId }),
              let attrs = collectionView.layoutAttributesForItem(at: IndexPath(item: item, section: 0))
        else {
            // 实例在集内但属性帧暂取不到（布局间隙）：按出窗
            // 处理，不冒充锚定。
            setLyricAnchorHidden(true, reason: "attrs-missing")
            return .outOfWindow
        }
        lyricAnchorInstanceId = target.instanceId
        let frame = CGRect(
            x: attrs.frame.minX - collectionView.contentOffset.x + collectionView.frame.minX,
            y: attrs.frame.minY - collectionView.contentOffset.y + collectionView.frame.minY,
            width: attrs.frame.width,
            height: attrs.frame.height)
        if overlay.frame != frame { overlay.frame = frame }
        setLyricAnchorHidden(false, reason: restoreReason)
        // 帧面包屑：锚实例 id + 帧矩形（原点按 40pt 网格去重，
        // 平移时约每 40pt 一条，不刷屏）；供真机对账锚定是否恒
        // 为播放曲实例、帧是否随卡走。
        let crumb = "\(target.instanceId)|\(Int(frame.minX / 40))|\(Int(frame.minY / 40))"
        if crumb != lastLyricOverlayCrumb {
            lastLyricOverlayCrumb = crumb
            Breadcrumbs.log("lrc overlay anchor=\(target.instanceId) frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height)) visible=\(!overlay.isHidden)")
        }
        return .anchored
    }

    /// 锚出窗隐藏/恢复的视觉状态机（3.7 (19)）：隐藏走 0.2s
    /// 边缘淡出（不用硬切消失，与 iOS 动效口径一致）、动画完
    /// 成才置 isHidden；恢复淡入。隐藏期间不清行窗、不重置
    /// 行索引——tick 继续下发 setWindow，扫光按时钟自走，
    /// 恢复时即是当前行当前相位。状态每次翻转落一行面包屑
    /// （anchor-state=hide/restore + reason），供真机对账。
    private func setLyricAnchorHidden(_ hidden: Bool, reason: String) {
        guard let overlay = lyricOverlay else { return }
        if hidden {
            guard !lyricAnchorHidden else { return }
            lyricAnchorHidden = true
            Breadcrumbs.log("lrc overlay anchor-state=hide reason=\(reason) anchor=\(lyricAnchorInstanceId ?? "-")")
            UIView.animate(withDuration: 0.2, animations: {
                overlay.alpha = 0
            }, completion: { _ in
                // 动画期间若已恢复（flag 翻回），不许再藏。
                if self.lyricAnchorHidden { overlay.isHidden = true }
            })
        } else {
            if lyricAnchorHidden {
                lyricAnchorHidden = false
                Breadcrumbs.log("lrc overlay anchor-state=restore reason=\(reason) anchor=\(lyricAnchorInstanceId ?? "-")")
                overlay.isHidden = false
                UIView.animate(withDuration: 0.2) {
                    overlay.alpha = 1
                }
            } else if overlay.isHidden {
                // 硬隐藏（clear 路径）后的常规再现：直接显示。
                overlay.alpha = 1
                overlay.isHidden = false
            }
        }
    }

    /// 歌词预取（3.7 (23) 改经共享仓库）：取数链（/lyric/new
    /// 双表合并、失败回落 /lyric）与缓存策略（LRU/正负 TTL/
    /// 并发合并）全在 LyricRepository；本方法只防本 VC 重复
    /// 起 Task，到手后清去重态让 tick 按仓库行表重下发。面
    /// 包屑口径不变（lines/source/flip 供真机对账翻行源）。
    private func ensureLyrics(for trackId: String) {
        guard LyricRepository.shared.cachedEntry(for: trackId) == nil,
              !lyricFetchInFlight.contains(trackId) else { return }
        lyricFetchInFlight.insert(trackId)
        Breadcrumbs.log("lrc fetch start track=\(trackId)")
        Task { [weak self] in
            let entry = await LyricRepository.shared.entry(for: trackId)
            await MainActor.run {
                guard let self else { return }
                Breadcrumbs.log("lrc parsed track=\(trackId) lines=\(entry.lines.count) source=\(entry.source) flip=\(entry.flip)")
                self.lyricFetchInFlight.remove(trackId)
                self.lastLyricIndex = nil
            }
        }
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
        // 贴纸层（3.7 (25)）：点歌起播 = 点切歌手势，缓冲贴纸
        // 计时窗由此开窗（状态机见文件尾 extension）。
        stickerNoteTrackChangeTap()
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
        // 贴纸层（3.7 (24)，纯新增）：点亮红心时展开卡上浮贴纸；
        // 取消收藏补依依不舍贴纸（3.7 (28)），同一落点成对。
        if newState { stickerCelebrateLike(queueIndex: queueIndex) }
        else { stickerUncelebrateLike(queueIndex: queueIndex) }
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
            prefetchInstance(at: indexPath)
        }
    }

    private func prefetchInstance(at indexPath: IndexPath) {
        guard indexPath.item < wallLayout.instances.count else { return }
        let instance = wallLayout.instances[indexPath.item]
        guard instance.queueIndex < entries.count else { return }
        let entry = entries[instance.queueIndex]
        guard let pic = entry.picUrl else { return }
        let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
        let pixelExtent = Double(max(frame.width, frame.height)) * Double(UIScreen.main.scale)
        let tier = NativeCoverLoader.wallTier(raw: pic, pixelExtent: pixelExtent)
        guard let urlString = NativeCoverLoader.shared.proxiedURLString(pic, tier: tier) else { return }
        if NativeCoverLoader.shared.cachedImage(for: urlString) != nil { return }
        Task { _ = await NativeCoverLoader.shared.image(for: urlString, tier: tier) }
    }

    private func prefetchExpandedNeighbors(queueIndex: Int) {
        var warmed = Set<Int>()
        for neighbor in [queueIndex - 1, queueIndex + 1] {
            guard entries.indices.contains(neighbor) else { continue }
            for (item, instance) in wallLayout.instances.enumerated()
            where instance.queueIndex == neighbor {
                guard warmed.insert(instance.queueIndex).inserted else { continue }
                prefetchInstance(at: IndexPath(item: item, section: 0))
            }
            if let pic = entries[neighbor].picUrl,
               let url = NativeCoverLoader.shared.proxiedURLString(pic, tier: 1024),
               NativeCoverLoader.shared.cachedImage(for: url) == nil {
                Task { _ = await NativeCoverLoader.shared.image(for: url, tier: 1024) }
            }
        }
    }

    // MARK: - 点按展开

    /// 最近一次展开的卡与时刻（双击第二击防误收起，13.2 审查中-2）。
    private var lastExpandInstanceId: String?
    private var lastExpandAt: CFTimeInterval = 0

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let instance = wallLayout.instances[indexPath.item]
        Breadcrumbs.log("wall tap item=\(indexPath.item) queueIndex=\(instance.queueIndex)")
        let before = setIdentity()
        // 3.7 (3)：不再跳切相机居中（那是生硬感主源）——原地弹簧重排：
        // 被点卡在原地长大、同块卡让位，镜头不动。
        if wallLayout.expandedInstanceId == instance.instanceId {
            // 展开后 0.4 秒内又点同一张：这是双击的第二击，不收起——
            // 先收起会让双击命中加固失去展开卡参照（独立审查中-2）。
            if lastExpandInstanceId == instance.instanceId,
               CACurrentMediaTime() - lastExpandAt < 0.4 {
                Breadcrumbs.log("wall tap collapse suppressed (double-tap second hit)")
                return
            }
            wallLayout.expandedInstanceId = nil
        } else {
            wallLayout.expandedInstanceId = instance.instanceId
            lastExpandInstanceId = instance.instanceId
            lastExpandAt = CACurrentMediaTime()
            // 展开即预取（DS26 深度 1）：只解这一首的播放地址入缓存，
            // 用户真点播放时少等一程取流。元数据未补到的序号跳过。
            if instance.queueIndex < nativeTracks.count {
                QueueManager.shared.prefetchStream(
                    for: foliaTrack(for: nativeTracks[instance.queueIndex]))
            }
            for q in [instance.queueIndex - 1, instance.queueIndex, instance.queueIndex + 1] {
                guard entries.indices.contains(q), let pic = entries[q].picUrl else { continue }
                let tileHit: Bool
                if let tileUrl = NativeCoverLoader.shared.proxiedURLString(pic, tier: NativeCoverLoader.wallTier(raw: pic, pixelExtent: 512)) {
                    tileHit = NativeCoverLoader.shared.cachedImage(for: tileUrl) != nil
                } else { tileHit = false }
                let hiHit: Bool
                if let hiUrl = NativeCoverLoader.shared.proxiedURLString(pic, tier: 1024) {
                    hiHit = NativeCoverLoader.shared.cachedImage(for: hiUrl) != nil
                } else { hiHit = false }
                Breadcrumbs.log("wall expand target queueIndex=\(q) cachedTile=\(tileHit) cached1024=\(hiHit)")
            }
            prefetchExpandedNeighbors(queueIndex: instance.queueIndex)
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
    private var coverPlaceholder = false
    var hasPlaceholderCover: Bool { coverPlaceholder }
    var hasCoverImage: Bool { imageView.image != nil }

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
    private var controlsVisible = false
    private var progressValue: Double = 0

    // 贴纸层（3.7 (24)，纯新增）：无版权/VIP 失败时错误条上方
    // 居中出哭猫（轮换池见 showFailureSticker）；点亮红心时
    // 红心上方浮 dog-11。均为叠加视图，不改既有控件逻辑。
    private var failureSticker: StickerView?
    private var failureStickerShown = false
    private static var failureEpisode = 0
    private var likeSticker: StickerView?

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
        // 贴纸层（3.7 (24)，纯新增）：失败态进出只切贴纸显隐，
        // 同一失败回合内重复 configure 不重播。
        if case .failed = loadState, expanded {
            if !failureStickerShown { showFailureSticker() }
        } else if failureStickerShown {
            failureStickerShown = false
            failureSticker?.isHidden = true
            failureSticker?.pause()
        }
        setLiked(liked)
        setNeedsLayout()
    }

    /// 无版权/VIP 贴纸轮换（映射定案）：主选 cat-20（头部特写
    /// 甩泪）与轮换 cat-10（嚎哭趴倒）、cat-05 截段（f0–f17）
    /// 交替，序列 cat-20 → cat-10 → cat-20 → cat-05 循环，
    /// 保证主选占比且同一只不连着出现两遍。均播一次停末帧。
    /// 失败贴纸轮换取只（持久失败态与 (28) 跳过闪现共用同一
    /// 轮换序，保证同一只不连着出现两遍）。
    static func nextFailureStickerAsset() -> String {
        let pool = ["cat-20", "cat-10", "cat-20", "cat-05"]
        let asset = pool[failureEpisode % pool.count]
        failureEpisode += 1
        return asset
    }

    private func showFailureSticker() {
        failureStickerShown = true
        let asset = Self.nextFailureStickerAsset()
        let sticker: StickerView
        if let existing = failureSticker {
            sticker = existing
        } else {
            sticker = StickerView()
            shadowView.addSubview(sticker)
            failureSticker = sticker
        }
        sticker.crumbScene = "card-failure"
        sticker.setSticker(asset, mode: .once(holdLast: true))
        sticker.isHidden = false
        setNeedsLayout()
    }

    /// 点亮红心庆祝（映射定案）：dog-11 抱爱心在红心按钮上方
    /// 浮出，播 2 圈（约 2.6s）后淡出。由 VC 的 likeTapped 在
    /// 新状态为已收藏时调用。
    func showLikeCelebration() {
        let sticker: StickerView
        if let existing = likeSticker {
            sticker = existing
        } else {
            sticker = StickerView()
            shadowView.addSubview(sticker)
            likeSticker = sticker
        }
        sticker.alpha = 1
        sticker.isHidden = false
        // 轮廓柔光（3.7 (28)）：dog-11 线条型浅色主体，深色
        // 封面上靠一圈极淡亮边保轮廓可辨。
        sticker.silhouetteHaloEnabled = true
        sticker.crumbScene = "card-like"
        sticker.setSticker("dog-11", mode: .loops(2))
        sticker.onFinished = { [weak sticker] in
            UIView.animate(withDuration: 0.3) {
                sticker?.alpha = 0
            } completion: { _ in
                sticker?.isHidden = true
                sticker?.alpha = 1
            }
        }
        setNeedsLayout()
    }

    /// 取消收藏（3.7 (28) 新增，与收藏庆祝成对）：同一落点冒
    /// cat-04（单爪抹泪，映射里「取消收藏」场景的定案主选），
    /// 播一次停末帧、多停留 1.1s 再淡出。由 VC 的 likeTapped
    /// 在新状态为未收藏时调用。
    func showUnlikeSticker() {
        let sticker: StickerView
        if let existing = likeSticker {
            sticker = existing
        } else {
            sticker = StickerView()
            shadowView.addSubview(sticker)
            likeSticker = sticker
        }
        sticker.alpha = 1
        sticker.isHidden = false
        sticker.silhouetteHaloEnabled = false
        sticker.crumbScene = "card-like"
        sticker.setSticker("cat-04", mode: .once(holdLast: true))
        sticker.onFinished = { [weak sticker] in
            UIView.animate(withDuration: 0.3, delay: 1.1, options: []) {
                sticker?.alpha = 0
            } completion: { _ in
                sticker?.isHidden = true
                sticker?.alpha = 1
            }
        }
        setNeedsLayout()
    }

    // 跳过闪现（3.7 (28)）：独立视图，与持久失败贴纸同落点
    // （卡内左上角），不碰 failureStickerShown 状态机。
    private var skipSticker: StickerView?
    private var skipFlashWork: DispatchWorkItem?

    /// 确定性不可播被自动跳过时闪现一次无版权贴纸作提示。
    /// 持久失败贴纸在显时不叠加。
    func flashSkipSticker() {
        guard !failureStickerShown else { return }
        let sticker: StickerView
        if let existing = skipSticker {
            sticker = existing
        } else {
            sticker = StickerView()
            shadowView.addSubview(sticker)
            skipSticker = sticker
        }
        sticker.alpha = 1
        sticker.isHidden = false
        sticker.crumbScene = "card-skip"
        sticker.setSticker(Self.nextFailureStickerAsset(), mode: .once(holdLast: true))
        setNeedsLayout()
        skipFlashWork?.cancel()
        let work = DispatchWorkItem { [weak sticker] in
            UIView.animate(withDuration: 0.3) {
                sticker?.alpha = 0
            } completion: { _ in
                sticker?.isHidden = true
                sticker?.alpha = 1
            }
        }
        skipFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
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
            // 贴纸层穿模治理（3.7 (25)）：失败贴纸 64pt 移到
            // 卡内左上角纯封面区——避错误条（barTop-19）、标题
            // 带（titleY 起）、底部控件行与右上角播放角标；
            // 红心贴纸 64pt 仍居红心按钮正上方，但下沿抬到标题
            // 带上沿之上 4pt，长标题尾行也不被压。
            failureSticker?.frame = CGRect(
                x: 8, y: 8, width: 64, height: 64)
            skipSticker?.frame = CGRect(
                x: 8, y: 8, width: 64, height: 64)
            likeSticker?.frame = CGRect(
                x: bounds.width - 38 - 17,
                y: max(8, titleY - 4 - 64),
                width: 64, height: 64)
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
            coverPlaceholder = false
            imageView.image = nil
            stopPlaceholderPulse()
            return
        }
        currentUrl = urlString
        // 缓存命中同步上图：reloadData/复用重建时不先清空、不异步等一帧，
        // 这是拖动闪黑的主修复。
        if let cached = NativeCoverLoader.shared.cachedImage(for: urlString) {
            coverPlaceholder = false
            stopPlaceholderPulse()
            imageView.image = cached
            return
        }
        if let placeholder = NativeCoverLoader.shared.cachedImageAnyTier(raw: pic, excludingTier: tier) {
            coverPlaceholder = true
            stopPlaceholderPulse()
            imageView.image = placeholder
        } else {
            coverPlaceholder = false
            imageView.image = nil
            startPlaceholderPulse()
        }
        loadTask = Task { [weak self] in
            let image = await NativeCoverLoader.shared.image(for: urlString, tier: tier)
            guard let self else { return }
            await MainActor.run {
                guard self.currentUrl == urlString else { return }
                self.stopPlaceholderPulse()
                if let image {
                    self.coverPlaceholder = false
                    self.imageView.image = image
                }
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
        coverPlaceholder = false
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
        progressValue = 0
        // 贴纸层（3.7 (24)）：复用时收起两只贴纸。
        failureStickerShown = false
        failureSticker?.isHidden = true
        likeSticker?.isHidden = true
        likeSticker?.alpha = 1
        // 跳过闪现（3.7 (28)）：复用时一并收起并取消待发淡出。
        skipFlashWork?.cancel()
        skipFlashWork = nil
        skipSticker?.isHidden = true
        skipSticker?.alpha = 1
    }
}

// MARK: - 贴纸层（3.7 (24)，纯新增视图层）
//
// 场景（scene-mapping.md 终版）：
// - 断网/加载失败：最终失败态居中 cat-03（80pt，播一次；
//   失败持续存在时每 8 秒低频重播）——与主页墙同规。
// - 歌单为空：种子落地且 total == 0 时居中 90pt，按打开
//   回合轮换 cat-17（躺平，循环）/ cat-24（抱手机泪成滩，
//   循环）/ cat-14（蜷躺抱手机，播一次停末帧；外卖袋道具
//   文字为 Miller 破例可用，Q4 裁决）。
// - 切歌缓冲：与主页墙同规（dog-05 / cat-08 回合轮换，
//   迷你台封面角上方 58pt）。
// 全部只读既有状态，不回写任何状态机。

extension WallPrototypeViewController {

    private func stickerEnsureViews() {
        if stickerFailureView == nil {
            let failure = StickerView()
            failure.crumbScene = "wall-offline"
            failure.isHidden = true
            view.addSubview(failure)
            stickerFailureView = failure
        }
        if stickerEmptyView == nil {
            let empty = StickerView()
            empty.crumbScene = "wall-playlist-empty"
            empty.isHidden = true
            view.addSubview(empty)
            stickerEmptyView = empty
        }
        if stickerBufferView == nil {
            let buffer = StickerView()
            buffer.crumbScene = "wall-buffer"
            buffer.isHidden = true
            view.addSubview(buffer)
            stickerBufferView = buffer
        }
    }

    // MARK: 失败陪衬

    func stickerFailureStateChanged() {
        stickerEnsureViews()
        if loadFailed {
            stickerFailureView?.setSticker("cat-03", mode: .once(holdLast: true))
            stickerFailureView?.isHidden = false
            stickerLayoutOverlays()
            stickerFailureReplayTimer?.invalidate()
            stickerFailureReplayTimer = Timer.scheduledTimer(
                withTimeInterval: 8, repeats: true) { [weak self] _ in
                    guard let self, self.loadFailed,
                          self.view.window != nil else {
                        self?.stickerFailureReplayTimer?.invalidate()
                        self?.stickerFailureReplayTimer = nil
                        return
                    }
                    self.stickerFailureView?.restart()
                }
        } else {
            stickerFailureReplayTimer?.invalidate()
            stickerFailureReplayTimer = nil
            stickerFailureView?.isHidden = true
        }
    }

    // MARK: 空歌单

    func stickerLoadStarted() {
        stickerEmptyView?.isHidden = true
    }

    func stickerShowEmptyPlaylist() {
        stickerEnsureViews()
        guard let empty = stickerEmptyView else { return }
        stickerEmptyEpisode += 1
        switch stickerEmptyEpisode % 3 {
        case 1:
            empty.setSticker("cat-17", mode: .loop)
        case 2:
            empty.setSticker("cat-24", mode: .loop)
        default:
            empty.setSticker("cat-14", mode: .once(holdLast: true))
        }
        empty.isHidden = false
        stickerLayoutOverlays()
    }

    // MARK: 切歌缓冲（3.7 (25) 改触发，状态机与主页墙同构）
    //
    // - 点切歌（迷你台上下曲/点卡起播/双击起播）→ 立即出贴纸
    //   （回合轮换 dog-05/cat-08，均循环），开 5s 计时窗；窗内
    //   再点切歌 → 换回合贴纸并重置 5s；起播不提前收。
    // - 5s 到点：已非 .waiting → 淡出；仍 .waiting → 转兜底，
    //   待离开 .waiting 才收。
    // - 无计时窗时 .waiting 到来 → 兜底直显，离开即收。冲突
    //   以计时窗为准。

    func stickerNoteTrackChangeTap() {
        stickerEnsureViews()
        stickerBufferEpisode += 1
        stickerShowBufferSticker()
        stickerBufferTapDeadline = Date().addingTimeInterval(5)
        stickerBufferHideTimer?.invalidate()
        stickerBufferHideTimer = Timer.scheduledTimer(
            withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.stickerBufferTapDeadline = nil
            if !self.stickerBufferWaiting {
                self.stickerHideBufferSticker()
            }
        }
    }

    private func stickerShowBufferSticker() {
        guard let buffer = stickerBufferView else { return }
        let asset = stickerBufferEpisode % 2 == 1 ? "dog-05" : "cat-08"
        buffer.layer.removeAllAnimations()
        if buffer.assetName != asset || !stickerBufferVisible {
            buffer.onFinished = nil
            buffer.setSticker(asset, mode: .loop)
        }
        buffer.alpha = 1
        buffer.isHidden = false
        stickerBufferVisible = true
        stickerLayoutOverlays()
    }

    private func stickerHideBufferSticker() {
        guard let buffer = stickerBufferView, stickerBufferVisible else { return }
        stickerBufferVisible = false
        UIView.animate(withDuration: 0.3, animations: {
            buffer.alpha = 0
        }, completion: { _ in
            buffer.isHidden = true
            buffer.alpha = 1
        })
    }

    func stickerBufferStateChanged(_ state: PlaybackState) {
        stickerBufferWaiting = state == .waiting
        if state == .waiting {
            if stickerBufferTapDeadline == nil, !stickerBufferVisible,
               PlaybackEngine.shared.currentTrack != nil {
                stickerEnsureViews()
                stickerBufferEpisode += 1
                stickerShowBufferSticker()
            }
        } else if stickerBufferTapDeadline == nil {
            stickerHideBufferSticker()
        }
    }

    // MARK: 跳过闪现（3.7 (28)）

    /// 确定性不可播被自动跳过：迷你台落点 + 展开卡落点各闪现
    /// 一次无版权贴纸作提示（复用既有失败贴纸轮换与落点，
    /// 不新造 UI）。本墙不在屏上时不闪。
    @objc func stickerTrackSkippedUnplayable() {
        guard view.window != nil else { return }
        stickerFlashSkipAtMiniBar()
        if let expandedId = wallLayout.expandedInstanceId,
           let item = wallLayout.instances.firstIndex(where: {
               $0.instanceId == expandedId
           }),
           let cell = collectionView.cellForItem(
               at: IndexPath(item: item, section: 0)) as? WallPosterCell {
            cell.flashSkipSticker()
        }
    }

    /// 迷你台左上落点闪现：缓冲状态机忙时（点切歌 5s 窗 /
    /// .waiting 兜底在显）不抢视图——台面已有反馈；空闲时在
    /// 同一落点闪现 1.3s。令牌防待发隐藏误伤后续正常显示。
    private func stickerFlashSkipAtMiniBar() {
        guard !stickerBufferVisible, stickerBufferTapDeadline == nil,
              !stickerBufferWaiting else { return }
        stickerEnsureViews()
        guard let buffer = stickerBufferView else { return }
        stickerSkipFlashToken += 1
        let token = stickerSkipFlashToken
        buffer.layer.removeAllAnimations()
        buffer.onFinished = nil
        buffer.setSticker(WallPosterCell.nextFailureStickerAsset(),
                          mode: .once(holdLast: true))
        buffer.alpha = 1
        buffer.isHidden = false
        stickerLayoutOverlays()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self, weak buffer] in
            guard let self, self.stickerSkipFlashToken == token,
                  !self.stickerBufferVisible,
                  self.stickerBufferTapDeadline == nil else { return }
            buffer?.isHidden = true
        }
    }

    // MARK: 红心庆祝（展开卡）

    func stickerCelebrateLike(queueIndex: Int) {
        guard let expandedId = wallLayout.expandedInstanceId,
              let item = wallLayout.instances.firstIndex(where: {
                  $0.instanceId == expandedId && $0.queueIndex == queueIndex
              }),
              let cell = collectionView.cellForItem(
                  at: IndexPath(item: item, section: 0)) as? WallPosterCell
        else { return }
        cell.showLikeCelebration()
    }

    /// 取消收藏贴纸入口（3.7 (28)）：与 stickerCelebrateLike
    /// 同一展开卡定位，cell 内同落点冒 cat-04。
    func stickerUncelebrateLike(queueIndex: Int) {
        guard let expandedId = wallLayout.expandedInstanceId,
              let item = wallLayout.instances.firstIndex(where: {
                  $0.instanceId == expandedId && $0.queueIndex == queueIndex
              }),
              let cell = collectionView.cellForItem(
                  at: IndexPath(item: item, section: 0)) as? WallPosterCell
        else { return }
        cell.showUnlikeSticker()
    }

    // MARK: 定位

    func stickerLayoutOverlays() {
        let bounds = view.bounds
        guard bounds.width > 0 else { return }
        if let failure = stickerFailureView {
            failure.frame = CGRect(
                x: (bounds.width - 80) / 2, y: (bounds.height - 80) / 2 - 24,
                width: 80, height: 80)
        }
        if let empty = stickerEmptyView {
            empty.frame = CGRect(
                x: (bounds.width - 90) / 2, y: (bounds.height - 90) / 2 - 24,
                width: 90, height: 90)
        }
        if let buffer = stickerBufferView, let bar = miniBar {
            buffer.frame = CGRect(
                x: bar.frame.minX + 4, y: bar.frame.minY - 64,
                width: 58, height: 58)
        }
    }
}
