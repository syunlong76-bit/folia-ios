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
    /// (62) 尾波第 4 组：歌词条跟随三压——锚下标缓存（稳态
    /// O(1) 校验、身份变化才全量重找）、base frame＋transform
    /// 平移跟随（拖动期不改 frame、不进歌词窗
    /// layoutSubviews）、didScroll/tick 双路同输入去重。
    private var lyricAnchorItemCache: Int?
    private var lyricFollowExpandedId: String?
    private var lyricOverlayBaseFrame: CGRect?
    private var lastLyricFollowKey: String?
    private var lastLyricFollowOutcome: LyricAnchorOutcome = .noCandidate
    /// 锚出窗隐藏态（3.7 (19)）：原锚滑出 overscan 窗口后歌词
    /// 淡出隐藏（不跨实例重锚、不清行窗），回窗淡入恢复；
    /// 状态翻转由 setLyricAnchorHidden 落面包屑供真机对账。
    private var lyricAnchorHidden = false
    /// 展开卡打点去重：组串未变时跳过重复 log。
    private var lastExpandedCellCrumb: String?
    private let wallLayout = WallLayout()
    /// hero 飞行在途引用（(67) 独立审查修复）：飞行未完又触
    /// 发展开/收起时先把旧飞行瞬时收尾（复原真卡 alpha），防
    /// 对已藏的卡再截空快照与双飞行层叠加。
    private var activeHeroFlight67: HeroFlight67?
    /// 滚动帧统计（(58) 定稿③）：逐秒 wall.scroll 面包屑。
    private let scrollMetrics = WallScrollMetrics(wallName: "tracks")
    /// 旋转代际（(58) 补旋转冻结，与主页墙同款）：中途反向再
    /// 转时只有最新一代的 completion 才收尾解冻。
    private var wallRotationGeneration = 0
    private var collectionView: UICollectionView!
    // 顶部行动胶囊已整段撤除（3.7 (54) 工作流 L）：原 statusLabel
    // 及其 showStatusNotice/statusTapped 一并删除——未登录入口归
    // 主页侧栏账户区、失败重试归失败贴纸点按、定位瞬时提示归窗口
    // 级 toast（NativePlaybackFailureToast.show(message:)）。
    private var backdrop: LoadingBackdropView?
    /// (62) 追加三：歌单页同款导航台（缝合工具条）。
    private var playlistSeamToolbar: SeamToolbarView?
    /// (75) 工具条双向约束组（竖屏绕岛带／横屏 (74) 侧锚），
    /// 与主页墙同构（applySeamBandOrientation 二选一激活）。
    private var seamBandPortrait: [NSLayoutConstraint] = []
    private var seamBandLandscape: [NSLayoutConstraint] = []
    private var seamBandIsPortrait: Bool?
    private var didCenterCamera = false
    private var isWrapping = false

    // 丝滑切入（3.7 (8)）：预加载 + 等首批数据再 present 的信号。
    private(set) var seedReady = false
    /// (62) 尾波第 5 组：主页墙封面单击打开本墙时置 true——
    /// 种子落地且本墙已呈现（或呈现时种子已到）后自动定位并
    /// 展开正在播放的卡（locateCurrentTrack），消费一次即清。
    var locateCurrentTrackWhenReady = false
    private var seedWaiters: [CheckedContinuation<Bool, Never>] = []
    // 加载胶囊已随 (53) L 组提示条删除退役（加载反馈归拍立得
    // 背板 + 小猫贴纸），原 pillShownAt 防闪记账一并删除。
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
    private var miniBarBottomC: NSLayoutConstraint?
    private var miniTrackBottomConstraint: NSLayoutConstraint?
    /// (74) 小横线形态的轨道约束组（同主页墙口径）。
    private var miniTrackLeadC: NSLayoutConstraint?
    private var miniTrackTrailC: NSLayoutConstraint?
    private var miniTrackHeightC: NSLayoutConstraint?
    private var miniTrackCenterXC: NSLayoutConstraint?
    private var miniTrackWidthC: NSLayoutConstraint?
    /// 点播台附加功能行（3.7 (54) 工作流 H 建、(60) 第 7 条迁
    /// 浮层）：五钮行不再装进台本体，改住透明浮层
    /// （MiniBarQuickRowOverlayView）挂本 VC 的 view、锚台顶上
    /// 方 8pt；台高恢复 70。miniQuickRow 指向浮层内的行本体，
    /// 浮层显隐与台 5 秒闲置同钟、点台身空白区呼出、点浮层外
    /// 收起（见 buildMiniBar 与 quickrow overlay 段）。
    private var miniQuickRow: MiniBarQuickRowView?
    private var miniQuickRowOverlay: MiniBarQuickRowOverlayView?
    private var miniQuickRowHideWorkItem: DispatchWorkItem?
    private var miniMainCenterY: [NSLayoutConstraint] = []
    /// 迷你台收起态（3.7 (21)：5 秒无操作自动收成进度条）：
    /// 与 miniBarPresented 分工——后者管在不在场，本标志管
    /// 完整/细条形态。收起形态 (22) 定版：背景全去（主题层/
    /// 毛玻璃/玻璃高光隐藏），只剩轨道+填充+发光圆点步进，
    /// 内容淡出且按钮禁交互。
    private var miniBarCollapsed = false
    /// 点播台点按识别器组（3.7 (61) 第 7 条，与主页墙同构）：
    /// 展开态单击（require 双击+长按失败）/展开态双击/收起态
    /// 单击（无 require 链、即时展开）三件分工，启停由
    /// setMiniBarForm 按形态同步；进度带即时 seek 走 seekHit
    /// 自带识别器（miniSeekTapped），不进本组 require 链。
    private var miniBarTapRecognizer: UITapGestureRecognizer?
    private var miniBarDoubleTapRecognizer: UITapGestureRecognizer?
    private var miniBarCollapsedTapRecognizer: UITapGestureRecognizer?
    /// (78) 第 8 条：播放条根级认领（见 MiniBarRootTap78）。
    private var miniBarRootTap78: MiniBarRootTap78?
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
    /// 主排模式钮（3.7 (55) 工作流 E 修正项，DS 对账）：与主页
    /// 墙同构——主排右端紧凑钮，glyph 随 QueueManager.playMode
    /// 四档各异，点按弹四档菜单点选，与队列面板/设置同一存储
    /// 同步。详注见 HomeWallViewController 同名属性。
    private var miniModeButton: UIButton!
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

    /// (78) 第 7 条宠物登顶（Miller 00:31 拍板）：本页顶部
    /// 同挂岛镜像宠物带，隐藏状态栏（系统时间）让宠物占顶
    /// 部带完整显示。安全区顶恒 59pt（传感器 housing 决
    /// 定、与状态栏显隐无关），既有布局不跳位。
    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = ThemeSystem62.interfaceStyleOverride() // (62) INT-1：明暗三段读主题系统，不再写死深色
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
        // 点播台面板通知接线（3.7 (55) 工作流 E 任务三）：工作
        // 流 C 的顶排面板/命令键 post 这两条通知（object
        // 为发出信号的 quick row 本身），本墙订阅后 present 工
        // 作流 D 的面板（类名定死，处理见 viewDidLoad 后
        // 的 miniBarPanel* 方法）。字幕键信号 .foliaMiniBar-
        // Subtitle 已随 (60) 第 11 条整组删除。
        NotificationCenter.default.addObserver(
            self, selector: #selector(miniBarPanelPanel),
            name: .foliaMiniBarPanel, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(miniBarPanelCommand),
            name: .foliaMiniBarCommand, object: nil)
        // 主排模式钮回显（(55) E 修正项）：模式在队列面板/设置/
        // 顶排任一处变更都经同一 @Published 存储回刷本钮。
        QueueManager.shared.$playMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMiniModeButton() }
            .store(in: &playbackCancellables)

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

        // 顶部行动胶囊整段撤除（3.7 (54) 工作流 L，Miller 拍板
        // 按网页版收口）：墙面顶部彻底无条无胶囊。原胶囊三条
        // 路径的新归宿：未登录入口 → 主页侧栏账户区（本面无此
        // 路径）；最终失败重试 → 失败贴纸 cat-03 点按（见
        // stickerEnsureViews 的 failureStickerTapped）；定位
        // 瞬时提示 → 窗口级 toast。歌单加载反馈仍由
        // LoadingBackdropView 的拍立得 + 捂脸哭小猫承担。

        // (76) ⑧右上角 ✕ 关闭钮摘除（Miller 21:52 截图点
        // 名：钮太小难按、与上方工具条控制区干涉、④左缘返
        // 回落地后没必要）：原 (53) L 组 ✕ 毛玻璃圆钮整件
        // 撤除——不留视觉、不留空占位、不留命中区。关闭路
        // 径不缺失：统一走 ④ 左缘手势（EdgeBack76，落点 =
        // 本页既有 closeTapped：背板 requestClose 契约 +
        // dismiss，加载态同路）；背板自带 onPendingClose 与
        // 展开卡点卡外/下滑等既有关闭路径原样保留。入场动
        // 画页关闭钮是另一页的定版口径，不在此列、未动。
        Breadcrumbs.log("wall.chrome playlist close=removed76")

        // (74) 墙内独立设置齿轮撤除：设置入口统一收进缝合工
        // 具条齿轮（Miller 定：顶部工具条里已有设置，独立页
        // 面形态与独立入口都不要）。原 (53) L 组「本面唯一设
        // 置路径」的保留理由随工具条铺到本面而失效；本面工
        // 具条随之上移到顶部行（见 installPlaylistSeamToolbar）。

        // 氛围底（丝滑切入）：盖在空墙上、垫在胶囊/关闭键下；数据
        // 到达后淡出。封面来自内存缓存（主页墙刚显示过），零等待。
        let backdropView = LoadingBackdropView(title: playlistTitle)
        backdropView.onPendingClose = { [weak self] in
            self?.dismiss(animated: true)
        }
        backdropView.setCover(rawUrl: playlistCoverUrl)
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdropView)
        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        backdrop = backdropView

        installPlaylistSeamToolbar()

        // (76) ④左缘滑动返回（与 ⑧ 摘 ✕ 互为前提、同批落
        // 地）：落点 = closeTapped 既有契约（背板在场时
        // requestClose 先行、加载态同路可退）；点播台条带
        // 内起手排除（防细条左端横拖被返回偷走）；墙面滚
        // 动 pan 须等左缘识别器失败才起（左缘起手先判返
        // 回、非左缘横滑照旧平移）。
        let edgeBack76 = EdgeBack76.install(on: self,
            shouldBeginAt: { [weak self] point in
                guard let self, let bar = self.miniBar,
                      !bar.isHidden else { return true }
                return !bar.frame.contains(point)
            },
            onDismiss: { [weak self] in
                self?.closeTapped()
            })
        if let edgePan = edgeBack76.pan {
            collectionView.panGestureRecognizer.require(toFail: edgePan)
        }

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
        // (69) P9：队列一变（装载/追加/删减/清空）即重配可见
        // cell 的「已在队列」角标，不许陈旧标记。
        QueueManager.shared.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshVisiblePlaybackUI()
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
            .sink { [weak self] _ in
                guard let self, QueueManager.shared.lastError != nil,
                      let pending = self.pendingTrackId else { return }
                self.pendingTrackId = nil
                // (64) U2：按 QueueManager 结构化分类选卡面文案，
                // 不再用 contains("VIP") 子串判定——旧 lastError
                // 恒含「VIP」，timeout/network/other 四类失败此前
                // 全被说成 VIP（取证 §3）。分类与文案成对写入、
                // 先类后文，此处读类时已就位。
                let banner: String
                switch QueueManager.shared.lastErrorClass {
                case "auth-missing":
                    banner = "VIP 或版权受限，点播放重试"
                case "timeout-or-nodes", "timeout":
                    banner = "网络超时，点播放重试"
                case "network":
                    banner = "网络异常，点播放重试"
                default:
                    banner = "播放失败，点播放重试"
                }
                self.failedPlayback = (pending, banner)
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

    // MARK: - 点播台面板通知（(55) E 任务三）与主排模式钮回显
    //
    // 顶排（工作流 C）post .foliaMiniBarPanel / Command，本墙
    // present 工作流 D 的面板（类名定死）；已有面板在呈时不
    // 叠开。字幕键与字幕面板已随 (60) 第 11 条整组删除。模式
    // 钮与主页墙同构：glyph 四档各异（顺序 list.bullet 与循
    // 环 repeat 区分开，防语义撞车），菜单四项与队列面板同
    // 名，写回同一 playMode 存储。

    @objc private func miniBarPanelPanel() {
        presentMiniBarPanel(PlaybackPanelViewController(initialTab: .cover), kind: "panel")
    }

    // (62) WB §4.8：海报墙 S 键打开命令窗口（外接键盘
    // UIKeyCommand，开关 posterWallSHotkeyEnabled 门控）。
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard SettingsStore.posterWallSHotkeyEnabled else { return nil }
        return [UIKeyCommand(title: "命令面板", action: #selector(wb62OpenCommandPalette),
                             input: "s", modifierFlags: [])]
    }

    @objc private func wb62OpenCommandPalette() {
        Breadcrumbs.log("shortcuts62.sKey host=wallproto")
        miniBarPanelCommand()
    }

    @objc private func miniBarPanelCommand() {
        // (62) C2 做真：同 HomeWall——注入跨面回调，队列走
        // PlaybackPanel 队列页签，样式走本墙原生舞台内选择器。
        guard view.window != nil, presentedViewController == nil else {
            Breadcrumbs.log("wall.menu.panel skipped kind=command busy=1 wall=proto")
            return
        }
        Breadcrumbs.log("wall.menu.panel present kind=command62 wall=proto")
        CommandPaletteViewController.present(from: self) { [weak self] palette in
            palette.onOpenQueuePanel = { [weak self] in
                guard let self, self.presentedViewController == nil else { return }
                PlaybackPanelViewController.present(from: self, initialTab: .queue)
            }
            palette.onOpenStylePicker = { [weak self] in
                Breadcrumbs.log("wall62.command stylePicker viaStage=1 wall=proto")
                self?.openNativeStageFromWall()
            }
        }
    }

    private func presentMiniBarPanel(_ panel: UIViewController, kind: String) {
        guard view.window != nil, presentedViewController == nil else {
            Breadcrumbs.log("wall.menu.panel skipped kind=\(kind) busy=1 wall=proto")
            return
        }
        Breadcrumbs.log("wall.menu.panel present kind=\(kind) wall=proto")
        panel.modalPresentationStyle = .pageSheet
        present(panel, animated: true)
    }

    private func refreshMiniModeButton() {
        guard let button = miniModeButton else { return }
        let mode = QueueManager.shared.playMode
        let symbol: String
        switch mode {
        case .off: symbol = "list.bullet"
        case .loopAll: symbol = "repeat"
        case .repeatOne: symbol = "repeat.1"
        case .shuffle: symbol = "shuffle"
        }
        button.setImage(UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)),
            for: .normal)
        button.tintColor = mode == .off
            ? UIColor.white.withAlphaComponent(0.45) : .white
        let items: [(QueueManager.PlayMode, String)] = [
            (.off, "顺序"), (.loopAll, "循环"), (.repeatOne, "单曲"), (.shuffle, "随机"),
        ]
        button.menu = UIMenu(children: items.map { item in
            let action = UIAction(title: item.1) { [weak self] _ in
                QueueManager.shared.playMode = item.0
                Breadcrumbs.log("minibar.mainrow.mode=\(item.0.rawValue)")
                self?.resetMiniIdleTimer()
            }
            action.state = item.0 == mode ? .on : .off
            return action
        })
    }

    /// 底部播放台（3.7 (13) #7；13.1 改版，Miller 2026-11-18 亲定）：
    /// 封面缩略 + 标题/歌手 + 上一曲/播放暂停/下一曲 + 顶部可拖进度。
    /// 交互（3.7 (61) 第 7 条起改全台统一规格，见 miniBarTapped）：
    /// 单击（含封面）= 浮层开关、双击 = 进播放详情页、进度带单击
    /// 即时 seek/可拖动 seek、收起态单击即时展开；按键只管切歌播停。
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
        // (75) 点按到达自证（第 5 项②，同主页墙）。
        bar.onHitLanded = { [weak self, weak bar] in
            guard let self, let bar else { return }
            Breadcrumbs.log("minibar.touch75 host=wallproto"
                + " col=\(self.miniBarCollapsed ? 1 : 0)"
                + " h=\(Int(bar.bounds.height))")
        }
        // (76) ⑤派发段见证接线（(75) 日志判读改靶：到达
        // 环全登记而 expand/dead75 双零 = 死在识别器认领
        // 前）：取消与未认领各落 dead76、行内带当刻三识别
        // 器启停位，下轮日志据此分环（位错 / 中途取消 /
        // 识别饥饿）。未认领只在收起态落痕（展开态按键等
        // 子视图自理的点按不经台身识别器、免假阳性；收起
        // 态点中宠物的序列会与 pet.* 面包屑同刻出现、可
        // 对照剔除）。
        bar.onDispatchCancelled = { [weak self] in
            guard let self else { return }
            Breadcrumbs.log("minibar.dead76 host=wallproto at=cancel"
                + " recog=\(self.miniTapBits())")
        }
        bar.onDispatchUnclaimed = { [weak self] in
            guard let self, self.miniBarCollapsed else { return }
            Breadcrumbs.log("minibar.dead76 host=wallproto at=noRecog"
                + " recog=\(self.miniTapBits())")
        }
        // (77) ⑥认领/救援接线：认领痕在 MiniBarHitView 内
        // 落（claim77）；救援 = 静止短点被外部转场取消时
        // 直接派发展开（disp77 via=rescue 与 claim 对位）。
        bar.crumbHostTag = "wallproto"
        bar.onCancelledTapRescue = { [weak self] in
            guard let self, self.miniBarCollapsed else { return }
            Breadcrumbs.log("minibar.disp77 host=wallproto via=rescue")
            self.expandMiniBar()
        }
        let petStage = MiniBarPetStage(bar: bar)
        view.addSubview(petStage)
        miniPetStage = petStage
        // (78) 第 8 条：根级认领（mb.claim78→mb.disp78→
        // expand），与主页同构——(77) 日志里本页正是细条点
        // 按全灭的现场之一（wallproto 3 次点按 1 次在此）。
        miniBarRootTap78 = MiniBarRootTap78(
            hostView: view, bar: bar, petStage: petStage,
            hostTag: "wallproto",
            isCollapsed: { [weak self] in self?.miniBarCollapsed ?? false },
            expand: { [weak self] in self?.expandMiniBar() })
        // (70) B2：点播台 4s 长按开启宠物手势整套已撤（与切
        // 主题长按同域打架、圆圈干扰操作，Miller 改令）——
        // 台上不再挂任何宠物相关识别器；宠物开关改全局右
        // 下角召唤钮（PetSummonButton70）＋设置开关，关闭
        // 另有长按宠物本体一路。

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

        // 点播台附加功能浮层（3.7 (54) 工作流 H 建上排、(60) 第 7
        // 条迁浮层）：五钮行不再装进台本体，改住透明浮层挂本 VC
        // 的 view（z 序在台之上），底边锚台顶上方 8pt、横向与台
        // 同宽同边距；台高恢复 70（expandedBarHeight）。功能走
        // MiniBarQuickRowView 唯一实现（与舞台/主页墙同件）；点
        // 按先行回调重置无操作计时（浮层自动收起与台闲置同钟）。
        // 宠物层以台顶为地面、零改动。
        let overlay = MiniBarQuickRowOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        miniQuickRowOverlay = overlay
        let quickRow = overlay.quickRow
        miniQuickRow = quickRow
        quickRow.onUserInteraction = { [weak self] in self?.resetMiniIdleTimer() }
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -8),
            overlay.heightAnchor.constraint(equalToConstant: MiniBarQuickRowView.rowHeight),
        ])
        // 点浮层外立即收起（观察式点按，不消费触摸）。
        let overlayOutsideTap = UITapGestureRecognizer(
            target: self, action: #selector(miniQuickRowOutsideTapped(_:)))
        overlayOutsideTap.cancelsTouchesInView = false
        view.addGestureRecognizer(overlayOutsideTap)
        Breadcrumbs.log("minibar.webrow wallproto overlay attached h=\(Int(MiniBarQuickRowView.expandedBarHeight))")

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

        // 主排模式钮（(55) E 修正项）：主排最右端紧凑钮，菜单
        // 点选四档（showsMenuAsPrimaryAction），回显由
        // refreshMiniModeButton 统一刷（订阅在 viewDidLoad）。
        miniModeButton = UIButton(type: .system)
        miniModeButton.tintColor = .white
        miniModeButton.accessibilityLabel = "播放模式"
        miniModeButton.showsMenuAsPrimaryAction = true
        miniModeButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniModeButton)
        refreshMiniModeButton()

        // 播放列表图标已删（3.7 (60) 第 10 条）：顶部 chrome 的
        // miniQueueButton 整钮移除，设置齿轮位置不补位；队列入
        // 口保留点播台面板页签与命令面板，QueuePanelViewController
        // 本体保留。面包屑留痕确认新包在跑。
        Breadcrumbs.log("minibar.queue wallproto removed=(60)")

        // 进度拖动手柄区：盖住底部进度条并向上放宽到 20pt 好按。
        let seekHit = UIView()
        seekHit.backgroundColor = .clear
        seekHit.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(seekHit)
        miniSeekHit = seekHit
        let seekPan = UIPanGestureRecognizer(target: self, action: #selector(miniSeekPanned(_:)))
        seekHit.addGestureRecognizer(seekPan)
        // 进度带单击即时 seek（3.7 (61) 第 7 条区域分域，与主
        // 页墙同构）：seekHit 自带无 require 链的点按识别器，
        // 点按当下即跳点；台身单击/双击对本带落点只做分域跳过。
        let seekTap = UITapGestureRecognizer(target: self, action: #selector(miniSeekTapped(_:)))
        seekHit.addGestureRecognizer(seekTap)

        // 宽度按竖屏定版（3.7 (21)）：居中 + 宽度约束存引用，
        // viewDidLayoutSubviews 按 min(宽,高)−24 更新——横屏时
        // 即竖屏布局宽，左右留白，不再拉伸满宽；高度存引用供
        // 收起形态切换（70↔16）。
        miniBarWidthConstraint = bar.widthAnchor.constraint(
            equalToConstant: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) - 24)
        miniBarHeightConstraint = bar.heightAnchor.constraint(
            equalToConstant: MiniBarQuickRowView.expandedBarHeight)
        miniBarWidthConstraint?.isActive = true
        miniBarHeightConstraint?.isActive = true
        // (74) 轨道约束存引用（收起态换居中小横线，同主页墙）。
        miniTrackLeadC = progressTrack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20)
        miniTrackTrailC = progressTrack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20)
        miniTrackHeightC = progressTrack.heightAnchor.constraint(equalToConstant: 4)
        miniTrackCenterXC = progressTrack.centerXAnchor.constraint(equalTo: bar.centerXAnchor)
        miniTrackWidthC = progressTrack.widthAnchor.constraint(equalToConstant: 134)
        // (77) ②⑤：底锚存引用、按形态切换——展开 −10（窗
        // 口爪印退役后无需再让位 −54）；收起 +31.5 使轨道
        // 中心与 home indicator 中心重合（账见
        // applyMiniBarBottom77）。先按展开值装配。
        miniBarBottomC = bar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bar.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            miniBarBottomC!,

            miniTrackLeadC!,
            miniTrackTrailC!,
            miniTrackHeightC!,
            fill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            fill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            fill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor),

            knob.centerYAnchor.constraint(equalTo: progressTrack.centerYAnchor),
            knob.widthAnchor.constraint(equalToConstant: 9),
            knob.heightAnchor.constraint(equalToConstant: 9),

            miniCover.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            miniCover.widthAnchor.constraint(equalToConstant: 44),
            miniCover.heightAnchor.constraint(equalToConstant: 44),

            miniTitle.leadingAnchor.constraint(equalTo: miniCover.trailingAnchor, constant: 12),
            miniTitle.trailingAnchor.constraint(equalTo: miniPrevButton.leadingAnchor, constant: -6),
            // 标题跟封面顶对齐（旧口径 = 封面顶 +5）：(54) H 主
            // 排下移后改相对锚，形态切换只动 centerY 常量一处。
            miniTitle.topAnchor.constraint(equalTo: miniCover.topAnchor, constant: 5),

            miniArtist.leadingAnchor.constraint(equalTo: miniTitle.leadingAnchor),
            miniArtist.trailingAnchor.constraint(equalTo: miniTitle.trailingAnchor),
            miniArtist.topAnchor.constraint(equalTo: miniTitle.bottomAnchor, constant: 2),

            miniModeButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            miniModeButton.widthAnchor.constraint(equalToConstant: 30),
            miniModeButton.heightAnchor.constraint(equalToConstant: 40),

            miniNextButton.trailingAnchor.constraint(equalTo: miniModeButton.leadingAnchor, constant: -2),
            miniNextButton.widthAnchor.constraint(equalToConstant: 34),
            miniNextButton.heightAnchor.constraint(equalToConstant: 40),

            miniPlayButton.trailingAnchor.constraint(equalTo: miniNextButton.leadingAnchor, constant: -2),
            miniPlayButton.widthAnchor.constraint(equalToConstant: 40),
            miniPlayButton.heightAnchor.constraint(equalToConstant: 40),

            miniPrevButton.trailingAnchor.constraint(equalTo: miniPlayButton.leadingAnchor, constant: -2),
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
        // 主排纵向位置（3.7 (54) H 曾 +15.5、(60) 第 7 条复原）：
        // 上排迁浮层后展开台高回 70，主排中心相对台中心 −5
        // （70 台旧口径，封面 44 居 y 8..52、轨道顶 59 不重叠）；
        // 收起态同 −5。模式钮（(55) E 修正项）同入本组。
        // 形态切换在 setMiniBarForm 里统一改这组常量。
        miniMainCenterY = [miniCover, miniPlayButton, miniPrevButton, miniNextButton, miniModeButton].map {
            $0.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5)
        }
        NSLayoutConstraint.activate(miniMainCenterY)
        // 轨道底距存引用（3.7 (21)）：收起形态 −7→−6 使轨道
        // 在 16pt 细条内居中（轨道高 4：(16−4)/2=6）。
        miniTrackBottomConstraint = progressTrack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -7)
        miniTrackBottomConstraint?.isActive = true
        fill.transform = CGAffineTransform(scaleX: 0, y: 1)

        // 长按切主题（13.5）：tap 须等长按落空才触发（短点按
        // 时触摸抬起即判长按失败）；seek 拖动不与长按互斥（长
        // 按静止触发时拖动尚未产生位移，松手至多以长按点 seek
        // 一次，与点按跳点同义）。
        // 单击/双击统一规格（3.7 (61) 第 7 条，与主页墙同构）：
        // 展开态单击 require(toFail:) 双击与长按两环；双击进
        // 歌曲详情页；收起态细条走独立无链识别器即时展开。
        // 三件启停按形态在 setMiniBarForm 同步。宠物层手势不
        // 经台身、4s 开启手势仍挂台身链外，均不受影响。
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(miniBarLongPressed(_:)))
        longPress.minimumPressDuration = 0.55
        bar.addGestureRecognizer(longPress)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(miniBarDoubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.require(toFail: longPress)
        bar.addGestureRecognizer(doubleTap)
        miniBarDoubleTapRecognizer = doubleTap
        let tap = UITapGestureRecognizer(target: self, action: #selector(miniBarTapped(_:)))
        tap.require(toFail: longPress)
        tap.require(toFail: doubleTap)
        bar.addGestureRecognizer(tap)
        miniBarTapRecognizer = tap
        let collapsedTap = UITapGestureRecognizer(target: self, action: #selector(miniBarCollapsedTapped(_:)))
        collapsedTap.isEnabled = false
        bar.addGestureRecognizer(collapsedTap)
        miniBarCollapsedTapRecognizer = collapsedTap
        // (74) 第 4 项兜底识别器（同主页墙）：与形态无关、
        // 恒启用、无 require 链，几何细条时先纠标志再展开。
        let agnosticTap74 = UITapGestureRecognizer(
            target: self, action: #selector(miniBarAgnosticTapped74(_:)))
        bar.addGestureRecognizer(agnosticTap74)

        applyMiniTheme()
        applyMiniBarSlots()
    }

    /// (74) 第 4 项本面定案：Miller (67) 录屏与 (74) 截图
    /// 两度实报的都是本面（曲目墙）细条点不开——(67) 取证
    /// C① 已判「同步态路径成立、疑标志/识别器启停失同步」
    /// （(63) 前科），(70) 只把几何自愈挂在出现边沿，页面
    /// 存续期再失同步仍复发；(72) 的 MiniBarSingleHost 只
    /// 仲裁「谁能动形态」、不经手命中与识别器启停，故没治
    /// 到这一层。本识别器以台体实际高度为真值分发，失同步
    /// 时先落 heal 面包屑纠正标志再展开，与 expand 内的
    /// minibar expand 行成对构成「点中→展开」自证。
    @objc private func miniBarAgnosticTapped74(_ gesture: UITapGestureRecognizer) {
        // (76) ⑤派发段认领旗（同 miniBarTapped 等各回调）。
        (miniBar as? MiniBarHitView)?.noteRecognizerClaimed()
        guard let bar = miniBar else { return }
        // (75) 死点留痕（同主页墙）：几何守卫拒绝不再静默。
        guard bar.bounds.height <= 20 else {
            Breadcrumbs.log("minibar.dead75 host=wallproto at=geom"
                + " h=\(Int(bar.bounds.height))")
            return
        }
        if !miniBarCollapsed {
            Breadcrumbs.log("minibar.hit host=wallproto heal=flag74")
            miniBarCollapsed = true
            miniPetStage?.barFormChanged(collapsed: true)
        }
        Breadcrumbs.log("minibar.hit host=wallproto via=agnostic74")
        expandMiniBar()
    }

    /// 点播台槽位应用（3.7 (50)）：按 MiniBarSlotSettings 显隐
    /// prev/next 两键（queue 已迁顶部 chrome，见 (53) H 修正）；隐藏时把该键宽度约束置 0，相对链
    /// 上的其余键与标题自动收拢补位（链间距 2pt 残留可忽略）。
    /// 宽度约束经按钮自身 constraints 反查（widthAnchor 常量
    /// 约束归按钮所有），不改构建期的约束块。收起态的 alpha/
    /// 交互名单含隐藏键也无妨：isHidden 恒压过 alpha 与命中。
    private func applyMiniBarSlots() {
        guard let prev = miniPrevButton, let next = miniNextButton else { return }
        applySlot(prev, visible: MiniBarSlotSettings.showPrev, width: 34)
        applySlot(next, visible: MiniBarSlotSettings.showNext, width: 34)
        // queue 键已迁顶部 chrome 排（(53) H 修正），不再受台面
        // 槽位显隐管辖。
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
        // (77) ②进度配色（推翻 (74) 的同色 25% 透明轨）：
        // 全条统一为现行后半段主题色（填充色两形态同规，
        // 收起态仅星空走强金兜底），未填充轨改同色系实色
        // 压暗（foliaDarkenedTrack77）——明度差辨进度，
        // 不再出现前暗后橙双截、不退纯白。
        let singleColor = miniBarCollapsed
            ? Self.miniCollapsedFillColor(for: miniTheme)
            : Self.miniFillColor(for: miniTheme)
        miniProgressFill.backgroundColor = singleColor
        miniProgressTrack.backgroundColor = singleColor.foliaDarkenedTrack77()
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
        // (70) B2：(60) 的宠物域隔离门控随 4s 开启手势整套
        // 撤除——台身长按只剩切主题一职，宠物开关态不再
        // 影响本识别器。
        guard gesture.state == .began, let bar = miniBar, !miniBarCollapsed,
              MiniPlayerTheme.effectsEnabled else { return }
        (miniBar as? MiniBarHitView)?.noteRecognizerClaimed()
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point)
            || miniModeButton.frame.contains(point) { return }
        // 附加功能行已迁浮层（(60) 第 7 条）：浮层不在台身内，
        // 其触摸不进本识别器，旧上排豁免随之退役。
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

    /// 台面单击分发（曲目墙版，3.7 (61) 第 7 条规格＋(62)
    /// 尾波第 5 组手势合并）：本识别器已 require(toFail:)
    /// 双击与 0.55s 长按，触发即「双击失败后的单击」。按键
    /// 各自处理；进度带落点分域跳过（seek 已由 seekHit 自
    /// 带识别器即时完成，见 miniSeekTapped）；**封面区单击
    /// ＝回封面播放页（locateCurrentTrack 定位并展开正在播
    /// 放的卡）**，台身空白/标题区维持浮层开关（已开＝收
    /// 起、不重出；未开＝呼出）。双击仍进详情
    /// （miniBarDoubleTapped），识别器组与 require 链零改动。
    /// 注：宠物占位区的点按被宠物识别器整组接走，永远到不
    /// 了台身——双击须落在台身空白/封面/标题区（验收口径）。
    @objc private func miniBarTapped(_ gesture: UITapGestureRecognizer) {
        (miniBar as? MiniBarHitView)?.noteRecognizerClaimed()
        guard let bar = miniBar else { return }
        // 收起态点按本应走无链的 collapsedTap 即时展开；此处
        // 仅作识别器启停万一失同步时的兜底。
        // (63) 第 2 条几何自愈（与主页墙同构）：标志说展开但
        // 几何已是细条高（≤20）＝形态失同步，先按几何纠正
        // 标志再走既有展开流程，同步时行为不变。
        if miniBarCollapsed || bar.bounds.height <= 20 {
            if !miniBarCollapsed {
                Breadcrumbs.log("minibar.form host=wallproto heal=geom"
                    + " h=\(Int(bar.bounds.height)) flag=0")
                miniBarCollapsed = true
            }
            expandMiniBar()
            return
        }
        // 完整形态的任何点按都算操作，重置无操作计时。
        resetMiniIdleTimer()
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point)
            || miniModeButton.frame.contains(point) { return }
        // 进度带分域（封面优先于进度带：封面下缘与 seekHit
        // 带约 2pt 重叠，该重叠落点归封面规格、不归 seek）。
        if miniSeekHit.frame.contains(point), !miniCover.frame.contains(point) {
            Breadcrumbs.log("minibar.tap host=wallproto zone=seekband action=skip")
            return
        }
        // (62) 尾波第 5 组：封面区单击换动作——回封面播放页，
        // 不再与台身同走浮层开关。
        if miniCover.frame.contains(point) {
            Breadcrumbs.log("minibar.tap host=wallproto zone=cover action=locate")
            locateCurrentTrack()
            return
        }
        if miniQuickRowOverlay?.isShown == true {
            hideMiniQuickRowOverlay(reason: "bar-tap")
            Breadcrumbs.log("minibar.tap host=wallproto action=overlay-hide")
        } else {
            showMiniQuickRowOverlay()
            Breadcrumbs.log("minibar.tap host=wallproto action=overlay-show")
        }
    }

    /// 台面双击分发（曲目墙版，3.7 (61) 第 7 条）：双击进歌
    /// 曲详情页——用本宿主既有路径 openNativeStageFromWall；
    /// 封面同规格参与。进度带分域：双击落带内不触发详情
    /// （每击已由 seekHit 识别器即时 seek）；按键区自理。
    /// 宠物占位区双击被宠物识别器接走、到不了台身。
    @objc private func miniBarDoubleTapped(_ gesture: UITapGestureRecognizer) {
        (miniBar as? MiniBarHitView)?.noteRecognizerClaimed()
        guard let bar = miniBar, !miniBarCollapsed else { return }
        resetMiniIdleTimer()
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point)
            || miniModeButton.frame.contains(point) { return }
        if miniSeekHit.frame.contains(point), !miniCover.frame.contains(point) {
            Breadcrumbs.log("minibar.doubletap host=wallproto zone=seekband action=skip")
            return
        }
        Breadcrumbs.log("minibar.doubletap host=wallproto action=stage")
        // (63) DS R63 B0：分发边界同步落盘（同主页墙）。
        Breadcrumbs.logSync("tap.dispatch host=wallproto")
        openNativeStageFromWall()
    }

    /// 收起态细条单击（3.7 (61) 第 7 条，与主页墙同构）：独
    /// 立识别器、无任何 require 链，点按即时展开。
    @objc private func miniBarCollapsedTapped(_ gesture: UITapGestureRecognizer) {
        (miniBar as? MiniBarHitView)?.noteRecognizerClaimed()
        guard miniBarCollapsed else {
            Breadcrumbs.log("minibar.dead75 host=wallproto at=flag")
            return
        }
        Breadcrumbs.log("minibar.tap host=wallproto collapsed=1 action=expand")
        // (77) ⑥派发环自证：与 claim77（认领）/minibar
        // .expand（展开）三环同轴对位。
        Breadcrumbs.log("minibar.disp77 host=wallproto via=tap")
        expandMiniBar()
    }

    /// 进度带单击即时 seek（3.7 (61) 第 7 条，与主页墙同
    /// 构）：seekHit 自带识别器、无 require 链，触发即跳点
    /// （比例按轨道实际帧算——13.3 口径，点按跳点本为治
    /// 「没办法拖进度」反馈而设）。封面重叠落点归封面规格；
    /// 按键区自理；收起态不 seek。
    @objc private func miniSeekTapped(_ gesture: UITapGestureRecognizer) {
        (miniBar as? MiniBarHitView)?.noteRecognizerClaimed()
        guard let bar = miniBar, !miniBarCollapsed else { return }
        resetMiniIdleTimer()
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point)
            || miniModeButton.frame.contains(point) { return }
        if miniCover.frame.contains(point) { return }
        guard miniSeekHit.frame.contains(point) else { return }
        let track = miniProgressTrack.frame
        let engine = PlaybackEngine.shared
        guard track.width > 0, engine.duration > 0 else { return }
        let fraction = min(max((point.x - track.minX) / track.width, 0), 1)
        setMiniProgress(Double(fraction))
        engine.seek(to: Double(fraction) * engine.duration)
        Breadcrumbs.log("minibar.seek host=wallproto via=seek-tap")
    }

    /// (76) 三识别器启停位（与 minibar.form 的 recog= 同
    /// 序：单击/双击/收起单击），派发段见证行内联用。
    private func miniTapBits() -> String {
        "\((miniBarTapRecognizer?.isEnabled ?? false) ? 1 : 0)"
            + "\((miniBarDoubleTapRecognizer?.isEnabled ?? false) ? 1 : 0)"
            + "\((miniBarCollapsedTapRecognizer?.isEnabled ?? false) ? 1 : 0)"
    }

    /// 点按识别器组按形态启停（3.7 (61) 第 7 条，与主页墙同
    /// 构）：全部形态切换都经 setMiniBarForm 收口到这里。
    private func syncMiniBarTapRecognizers(collapsed: Bool) {
        miniBarTapRecognizer?.isEnabled = !collapsed
        miniBarDoubleTapRecognizer?.isEnabled = !collapsed
        miniBarCollapsedTapRecognizer?.isEnabled = collapsed
    }

    /// 进度拖动（13.1）：拖动中只更新填充，松手才 seek（防拖动
    /// 途中连环跳秒）；轻点进度区同样跳到该位置。终结状态先复位
    /// 拖动标记再走任何守卫——拖动途中切歌使 duration 归零时，
    /// 守卫先行会让标记永不复位、进度填充从此冻结（独立审查中-2）。
    /// 封面/按键的上沿落在命中带里，那里起手不抢手势（低-3）。
    @objc private func miniSeekPanned(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            (miniBar as? MiniBarHitView)?.noteRecognizerClaimed()
        }
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
                || miniModeButton.frame.contains(barPoint) { return }
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
            // 台退场时浮层立即收起（(60) 第 7 条），不许悬空残留。
            hideMiniQuickRowOverlay(reason: "bar-hidden")
        }
        bar.layer.removeAllAnimations()
        if visible {
            if FoliaMotion62.reduced(.microEffects) {
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
            let duration = FoliaMotion62.reduced(.microEffects) ? 0.2 : 0.28
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.curveEaseIn, .beginFromCurrentState], animations: {
                bar.alpha = 0
                if !FoliaMotion62.reduced(.microEffects) {
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
        // 浮层与台闲置同钟（(60) 第 7 条）：浮层在显时顺延其
        // 5 秒自动收起（与台收起同一时刻落点）。
        if miniQuickRowOverlay?.isShown == true {
            scheduleMiniQuickRowAutoHide()
        }
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
        // (72) 单宿主仲裁：非最前宿主不许动形态（防双宿主同动）。
        guard MiniBarSingleHost.shared.isActive("wallproto") else { return }
        guard miniBarPresented, !miniBarCollapsed, !miniSeekDragging,
              let bar = miniBar else { return }
        miniBarCollapsed = true
        miniPetStage?.barFormChanged(collapsed: true)
        cancelMiniIdleTimer()
        // 台收成细条时浮层同钟收起（(60) 第 7 条）。
        hideMiniQuickRowOverlay(reason: "idle")
        Breadcrumbs.log("minibar collapse idle")
        setMiniBarContentsInteractive(false)
        if FoliaMotion62.reduced(.microEffects) {
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
        // (72) 单宿主仲裁（同 collapseMiniBarIdle）。
        // (75) 死点留痕：仲裁拒绝不再静默。
        guard MiniBarSingleHost.shared.isActive("wallproto") else {
            Breadcrumbs.log("minibar.dead75 host=wallproto at=arb")
            return
        }
        guard miniBarCollapsed, let bar = miniBar else {
            resetMiniIdleTimer()
            return
        }
        miniBarCollapsed = false
        miniPetStage?.barFormChanged(collapsed: false)
        Breadcrumbs.log("minibar expand")
        setMiniBarContentsInteractive(true)
        if FoliaMotion62.reduced(.microEffects) {
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
    /// 形态/几何出现边沿重同步（3.7 (70) B3）：(63) 自愈只
    /// 挂 miniBarTapped——标志=展开、几何=细条的失同步态
    /// 下，收起态单击识别器已被 sync 关掉，点按落进展开
    /// 链的双击/长按判定里出不来、根本到不了自愈点（取证
    /// uitaps C① 候选机制，拼贴墙细条点不开）。本方法把
    /// 同一几何判读前移到出现边沿：以 bar 实际高度为真值
    /// （≤20＝细条；≥展开高−4＝展开；中间值是动画中途帧，
    /// 不干预），与标志不符时落 heal=geom、纠正标志并经
    /// setMiniBarForm 收口（识别器启停随之重同步、
    /// minibar.form 面包屑 recog= 三位同行落盘，供下次日
    /// 志一行定案）。首帧未布局（高=0）跳过、不误判。
    private func resyncMiniBarFormToGeometry70() {
        guard let bar = miniBar else { return }
        let height = bar.bounds.height
        guard height > 0 else { return }
        let settledCollapsed = height <= 20
        let settledExpanded = height >= MiniBarQuickRowView.expandedBarHeight - 4
        guard settledCollapsed || settledExpanded else { return }
        let geometryCollapsed = settledCollapsed
        guard geometryCollapsed != miniBarCollapsed else { return }
        Breadcrumbs.log("minibar.form host=wallproto heal=geom"
            + " h=\(Int(height)) flag=\(miniBarCollapsed ? 1 : 0) edge=appear")
        miniBarCollapsed = geometryCollapsed
        setMiniBarForm(collapsed: geometryCollapsed)
    }

    /// (77) ②底锚按形态落位：展开 −10（窗口爪印退役、不
    /// 再让位）；收起与 home indicator 严丝合缝重合——几
    /// 何账（iPhone 14 Pro）：安全区底 34、indicator
    /// 134×5、底边距屏底 ≈8、中心在屏底上方 ≈10.5；收起
    /// 轨道中心 = 台底 −8（台高 16、轨底 −5.5、轨高 5）。
    /// 台底锚（相对安全区底）C 使轨道中心落 indicator 中
    /// 心：C = 34 − 10.5 + 8 = +31.5。无 indicator 机型
    /// （安全区底 0）回落 −10 防台身出屏。宠物层按
    /// bar.frame 跟随（MiniBarPetStage.syncFrame），落位
    /// 变更自动带宠物、无需另动。
    /// (78) 第 1 条修正（与主页同账）：收起 31.5→24.5，整
    /// 条上抬 7pt——轨道带升至屏底上方 15–20，系统小白线
    /// （8–13）只落条身下部空白边距、不压轨道与宠物。
    private func applyMiniBarBottom77(collapsed: Bool) {
        guard let bottomC = miniBarBottomC else { return }
        let inset = view.window?.safeAreaInsets.bottom
            ?? view.safeAreaInsets.bottom
        bottomC.constant = collapsed
            ? (inset > 0 ? 24.5 : -10) : -10
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applyMiniBarBottom77(collapsed: miniBarCollapsed)
    }

    private func setMiniBarForm(collapsed: Bool) {
        // (72) 形态收口同步共享旗标（单宿主交接的对齐源）。
        MiniBarSingleHost.shared.sharedCollapsed = collapsed
        applyMiniBarBottom77(collapsed: collapsed)
        (miniBar as? MiniBarHitView)?.isCollapsedForm = collapsed
        miniBarHeightConstraint?.constant = collapsed ? 16 : MiniBarQuickRowView.expandedBarHeight
        // (60) 第 7 条：展开台高回 70 后主排中心两形态同为 −5。
        for constraint in miniMainCenterY { constraint.constant = -5 }
        // (74) 第 5 项小横线（同主页墙口径）：收起态轨道换
        // 居中 134×5 小横线、圆点收起；台体容器与命中带不
        // 动。底距 −5.5 使 5pt 线在 16pt 容器内居中。
        miniTrackBottomConstraint?.constant = collapsed ? -5.5 : -7
        miniTrackHeightC?.constant = collapsed ? 5 : 4
        miniTrackLeadC?.isActive = !collapsed
        miniTrackTrailC?.isActive = !collapsed
        miniTrackCenterXC?.isActive = collapsed
        miniTrackWidthC?.isActive = collapsed
        miniProgressTrack.layer.cornerRadius = collapsed ? 2.5 : 2
        // (77) ②③：四主题小圆点恢复收起态在场——(74) 细
        // 条改素线时以 isHidden=collapsed 误删；皮肤在
        // refreshMiniProgressChrome 两形态同挂，圆点本体
        // 两形态恒可见（(22)/(23) 旧制：13pt 皮肤压 9pt
        // knob、溢出显示）。
        miniProgressKnob.isHidden = false
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
        // 点按识别器组随形态启停（3.7 (61) 第 7 条）：收起态
        // 只认无链单击即时展开，展开态才挂双击判定链。
        syncMiniBarTapRecognizers(collapsed: collapsed)
        // (63) 第 2 条形态面包屑（与主页墙同构）：标志/几何
        // 高/三识别器启停位同行落盘，供失同步判读。
        Breadcrumbs.log("minibar.form host=wallproto collapsed=\(collapsed ? 1 : 0)"
            + " h=\(Int(miniBarHeightConstraint?.constant ?? -1))"
            + " recog=\((miniBarTapRecognizer?.isEnabled ?? false) ? 1 : 0)"
            + "\((miniBarDoubleTapRecognizer?.isEnabled ?? false) ? 1 : 0)"
            + "\((miniBarCollapsedTapRecognizer?.isEnabled ?? false) ? 1 : 0)")
        refreshMiniProgressChrome()
    }

    private func setMiniBarContentsAlpha(_ alpha: CGFloat) {
        // 圆点不在淡出名单（3.7 (22)）：收起态保留发光圆点
        // 随进度步进，淡出的只有封面/标题/歌手/按键。
        // 附加功能行已迁浮层（(60) 第 7 条），不入台形态名单：
        // 台收起时浮层由 collapseMiniBarIdle 单独收起。
        let views: [UIView?] = [miniCover, miniTitle, miniArtist, miniPlayButton,
                                miniPrevButton, miniNextButton, miniModeButton]
        for view in views {
            view?.alpha = alpha
        }
    }

    private func setMiniBarContentsInteractive(_ interactive: Bool) {
        let buttons: [UIButton?] = [miniPlayButton, miniPrevButton, miniNextButton, miniModeButton]
        for button in buttons {
            button?.isUserInteractionEnabled = interactive
        }
    }

    // MARK: 附加功能浮层（3.7 (60) 第 7 条，曲目墙宿主）
    //
    // 触发 = 点台身空白区（miniBarTapped 末路）；收起 = 与台闲
    // 置同钟 5 秒、点浮层外立即收起、台收起/退场时随台收起。
    // 进出动画在 MiniBarQuickRowOverlayView.setShown 内（系统
    // 弹簧 0.85、自台顶滑入＋淡入）。宠物站位以台顶为地面，
    // 浮层零干涉；台身 0.55s 长按切主题挂在台身上、浮层不在
    // 台内，其触摸不进该识别器，不受影响。

    private func showMiniQuickRowOverlay() {
        guard let overlay = miniQuickRowOverlay, !overlay.isShown else { return }
        overlay.setShown(true)
        Breadcrumbs.log("quickrow.overlay show host=wallproto")
        scheduleMiniQuickRowAutoHide()
    }

    private func hideMiniQuickRowOverlay(reason: String) {
        miniQuickRowHideWorkItem?.cancel()
        miniQuickRowHideWorkItem = nil
        guard let overlay = miniQuickRowOverlay, overlay.isShown else { return }
        overlay.setShown(false)
        Breadcrumbs.log("quickrow.overlay hide host=wallproto reason=\(reason)")
    }

    private func scheduleMiniQuickRowAutoHide() {
        miniQuickRowHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideMiniQuickRowOverlay(reason: "idle")
        }
        miniQuickRowHideWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.miniIdleCollapseDelay, execute: work)
    }

    /// 点浮层外立即收起：观察式识别器（不消费触摸）——落点在
    /// 浮层胶囊或点播台之内都不算「外」。
    @objc private func miniQuickRowOutsideTapped(_ gesture: UITapGestureRecognizer) {
        guard let overlay = miniQuickRowOverlay, overlay.isShown,
              let bar = miniBar else { return }
        let point = gesture.location(in: view)
        if overlay.frame.contains(point) || bar.frame.contains(point) { return }
        hideMiniQuickRowOverlay(reason: "outside-tap")
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
        guard !FoliaMotion62.reduced(.queueCollage) else {
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
            // 瞬时提示（3.7 (54) 工作流 L）：胶囊撤除后改走窗口
            // 级 toast（自动消失、墙面不留条），文案不变。
            NativePlaybackFailureToast.show(message: "当前歌曲不在这个歌单里")
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
            // 落点展开（(62) 尾波第 6 组：原 hero 快照放大已摘
            // 除，走 animateHeroExpansion 的非 hero 路径——布局
            // 弹簧重排落位）。
            self.wallLayout.expandedInstanceId = target.instanceId
            self.animateHeroExpansion(heroImage: nil, sourceFrame: nil,
                                      targetInstanceId: target.instanceId) { [weak self] in
                guard let self else { return }
                self.emphasizeLocateLanding()
                // 落点校验（3.7 (13.2)）：展开落定后核对展开的
                // 确实是冻结目标，不是就纠正/重飞，全程面包屑。
                self.locateFlightInstanceId = target.instanceId
                let gen = self.locateGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.verifyLocateLanding(generation: gen)
                }
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
        // 瞬时提示（3.7 (54) 工作流 L）：改走窗口级 toast，
        // 双歌名证据文案不变（全名仍在面包屑）。
        NativePlaybackFailureToast.show(message: failText)
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
            // 落点展开：与 locateCurrentTrack 同口径，走
            // animateHeroExpansion 非 hero 路径（(62) 尾波第 6
            // 组已摘快照放大）。
            self.wallLayout.expandedInstanceId = target.instanceId
            self.animateHeroExpansion(heroImage: nil, sourceFrame: nil,
                                      targetInstanceId: target.instanceId) { [weak self] in
                guard let self else { return }
                self.emphasizeLocateLanding()
                self.locateFlightInstanceId = target.instanceId
                let gen = self.locateGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.verifyLocateLanding(generation: gen)
                }
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
        wallLayout.worldOrigin = CGPoint(
            x: locateStartOrigin.x + (locateTargetOrigin.x - locateStartOrigin.x) * CGFloat(eased),
            y: locateStartOrigin.y + (locateTargetOrigin.y - locateStartOrigin.y) * CGFloat(eased))
        // 缩放同支弹簧（P6）：飞行中段轻微放大（钟形，峰值
        // 1.03、由同一弹簧进度驱动），落点回到 1.0——位置
        // 与缩放同曲线插值，无分段跳变；Reduce Motion 不缩放。
        if FoliaMotion62.reduced(.queueCollage) {
            collectionView.transform = .identity
        } else {
            let bell = CGFloat(eased * (1 - eased) * 4)
            collectionView.transform = CGAffineTransform(scaleX: 1 + 0.03 * bell,
                                                         y: 1 + 0.03 * bell)
        }
        // (58)：身份判定改用 refreshInstances 返回值（全序列
        // 对比，代指旧 setIdentity 首/尾/计数口径）。
        // (59) 工作流一同修：飞行逐 tick 只写 attributesCache
        // 时 CV 不重读、画面冻在起点（与滚动同病），身份未变
        // 时显式失效布局让本 tick 的帧上屏。
        if wallLayout.refreshInstances() {
            collectionView.reloadData()
        } else {
            wallLayout.invalidateLayout()
        }
        if raw >= 1 {
            link.invalidate()
            locateLink = nil
            // 落点定格干净：原点精确吸附目标、缩放复位，
            // 不留钟形缩放残值给后续展开/歌词锚定。
            wallLayout.worldOrigin = locateTargetOrigin
            wallLayout.refreshInstances()
            wallLayout.invalidateLayout()
            collectionView.transform = .identity
            Breadcrumbs.log("locate flight spring end")
            let done = locateCompletion
            locateCompletion = nil
            done?()
        }
    }

    /// 旋转冻结（3.7 (58) 定稿③补：曲目墙此前从不置冻结，旋转
    /// 期间每中间 bounds 都触发全量重算——与主页墙 (57) A2 同款
    /// 口径）：旋转开始即冻结（动画期间零重算、保留落定前最后
    /// 一套实例/属性随系统变换呈现），coordinator completion
    /// 一次性解冻收尾；中途反向再转只有最新一代 completion
    /// 收尾（代际守卫同主页墙）。
    override func viewWillTransition(to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard viewIfLoaded != nil, collectionView != nil else { return }
        let fromSize = view.bounds.size
        guard size != fromSize else { return }
        wallRotationGeneration += 1
        let generation = wallRotationGeneration
        wallLayout.setRotationFrozen(true)
        // (73) 岛层守护转场期暂停（同主页墙）。
        PetIslandLayer.setRefrontSuspended(true)
        Breadcrumbs.log("wall.rotate freeze gen=\(generation) wall=tracks"
            + " from=\(Int(fromSize.width))x\(Int(fromSize.height))"
            + " to=\(Int(size.width))x\(Int(size.height))")
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            // (75) 工具条朝向组随转场首帧切换（同主页墙）。
            self.applySeamBandOrientation(portrait: size.width < size.height)
            // (73) 重排提前到转场首帧（同主页墙 (73) 注）：
            // 落定帧不再有旧布局→新布局的 snap。
            guard generation == self.wallRotationGeneration else { return }
            self.wallLayout.setRotationFrozen(false)
            self.wallLayout.invalidateLayout()
            // prepare 若因尺寸类别变化换了实例集，同步 reload。
            if self.wallLayout.lastIdentityChanged {
                self.collectionView.reloadData()
            }
        }) { [weak self] _ in
            guard let self else { return }
            PetIslandLayer.setRefrontSuspended(false)
            PetIslandLayer.shared.refrontIfNeeded()
            guard generation == self.wallRotationGeneration else {
                Breadcrumbs.log("wall.rotate superseded gen=\(generation) wall=tracks")
                return
            }
            Breadcrumbs.log("wall.rotate landed gen=\(generation) wall=tracks"
                + " size=\(Int(size.width))x\(Int(size.height))"
                + " instances=\(self.wallLayout.instances.count)"
                + " latticeComputes=\(self.wallLayout.latticeComputeCount)")
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // (72) 单宿主认领：本页在前时迷你台形态归本宿主；
        // 形态与共享旗标不一致时无动画对齐一次（交接不跳变）。
        MiniBarSingleHost.shared.claim("wallproto")
        if miniBarPresented,
           miniBarCollapsed != MiniBarSingleHost.shared.sharedCollapsed {
            let target = MiniBarSingleHost.shared.sharedCollapsed
            miniBarCollapsed = target
            miniPetStage?.barFormChanged(collapsed: target)
            setMiniBarForm(collapsed: target)
            setMiniBarContentsAlpha(target ? 0 : 1)
            setMiniBarContentsInteractive(!target)
        }
        lyricClockDriver.start()
        progressDriver.start()
        miniThemeLayer?.setHostVisible(true)
        // (70) B3：出现边沿先按几何核一次形态/识别器同步。
        resyncMiniBarFormToGeometry70()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // (72) 单宿主让位（底层宿主在自己的 appear 里接认领）。
        MiniBarSingleHost.shared.release("wallproto")
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
        // (70) B3：布局落定后再核一次（viewWillAppear 时帧
        // 可能仍是旧值），失同步在此收口。
        resyncMiniBarFormToGeometry70()
        // (75) 工具条首启定向兜底（同主页墙）。
        applySeamBandOrientation(portrait: view.bounds.width < view.bounds.height)
        Breadcrumbs.log("wall.appear kind=playlist")
        Breadcrumbs.log("tracks appear playlist=\(playlistId)")
        // (62) 尾波第 5 组：种子先于呈现落地时在此消费待定位
        // （种子后到则由 loadEntries 落点消费，标志只认一次）。
        if locateCurrentTrackWhenReady, !entries.isEmpty {
            locateCurrentTrackWhenReady = false
            locateCurrentTrack()
        }
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
        if FoliaMotion62.reduced(.playlistExpand) {
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

    /// 失败态点按失败贴纸重试（3.7 (54) 工作流 L）：行动胶囊
    /// 撤除后，最终失败的重试入口落在失败陪衬贴纸 cat-03 上
    /// （stickerEnsureViews 给它开交互 + 本手势）——原胶囊
    /// statusTapped 的重置口径逐字保留（计数清零、重新加载）。
    @objc private func failureStickerTapped() {
        guard loadFailed else { return }
        Breadcrumbs.log("wallproto failure-sticker tap action=retry")
        loadFailed = false
        loadAttempts = 0
        loadEntries()
    }

    /// (75) 工具条朝向切换（与主页墙同构）。
    func applySeamBandOrientation(portrait: Bool) {
        guard seamBandIsPortrait != portrait,
              !seamBandPortrait.isEmpty, !seamBandLandscape.isEmpty else { return }
        seamBandIsPortrait = portrait
        NSLayoutConstraint.deactivate(portrait ? seamBandLandscape : seamBandPortrait)
        NSLayoutConstraint.activate(portrait ? seamBandPortrait : seamBandLandscape)
        Breadcrumbs.log("seam.wrap75 host=tracks portrait=\(portrait ? 1 : 0)")
    }

    /// 歌单页导航台装配（(62) 追加三、(74) 修订、(75) 再修）：
    /// 与主页同款缝合工具条。几何（先量后装、零重叠）：本
    /// 面顶部行有关闭键（safeArea.top+8 起 44 高、右缘内
    /// 44 宽），工具条整排内容宽 356pt——同高装配时右端让
    /// 关闭键只剩 317pt 装不下，故内容行仍落关闭键行下方
    /// 一排。(75) 竖屏改绕岛带：条体钉屏幕顶边全宽、高
    /// 165（凹口 0–56＋页眉空带＋内容行 115–159＋底衬 6，
    /// 内容行顶 115 与 (74) 的 safeArea.top+56 同位、与关
    /// 闭键纵向零交叠），关闭键容器提至带上层（展开态不
    /// 被毛玻璃盖）；横屏回 (74) 侧锚组（top = safeArea
    /// .top + 56、leading 贴安全区左缘避岛、trailing −12）。
    /// 动作语义（(75) 第 7 项修订）：全局面（设置/账户/
    /// 搜索/导播台）在本面就地展开（SeamToolbarForwarding
    /// .performInPlace）；主页墙状态动作（切段/布局/沉浸/
    /// Lattice/更多）才转发回主页执行（forward），不在本
    /// 面另造行为。
    /// (75) 加载页零帧：背板在场期间整条隐藏（见装配尾）。
    private func installPlaylistSeamToolbar() {
        let toolbar = SeamToolbarView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wrapIslandEnabled = true
        toolbar.contentRowTop = 115
        view.addSubview(toolbar)
        let bandP: [NSLayoutConstraint] = [
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 165),
        ]
        let bandL: [NSLayoutConstraint] = [
            toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
        ]
        seamBandPortrait = bandP
        seamBandLandscape = bandL
        applySeamBandOrientation(
            portrait: UIScreen.main.bounds.width < UIScreen.main.bounds.height)
        if let home = SeamToolbarForwarding.findHomeWall(from: self) {
            let state = home.seamToolbarInitialState
            toolbar.setSegment(state.segment)
            toolbar.setLayoutMode(grid: state.grid)
        }
        SeamToolbarForwarding.applyAccountState(to: toolbar)
        toolbar.onSegmentChanged = { [weak self] segment in
            guard let self else { return }
            SeamToolbarForwarding.forward("segment-\(segment.crumbName)", from: self)
        }
        toolbar.onAvatarTapped = { [weak self] in
            guard let self else { return }
            SeamToolbarForwarding.performInPlace("avatar", from: self, toolbar: toolbar)
        }
        toolbar.onSearchTapped = { [weak self] in
            guard let self else { return }
            SeamToolbarForwarding.performInPlace("search", from: self, toolbar: toolbar)
        }
        toolbar.onSettingsTapped = { [weak self] in
            guard let self else { return }
            SeamToolbarForwarding.performInPlace("settings", from: self, toolbar: toolbar)
        }
        toolbar.onGuideTapped = { [weak self] in
            guard let self else { return }
            SeamToolbarForwarding.performInPlace("guide", from: self, toolbar: toolbar)
        }
        toolbar.onLatticeTapped = { [weak self] in
            guard let self else { return }
            SeamToolbarForwarding.forward("lattice", from: self)
        }
        toolbar.onLayoutTapped = { [weak self] in
            guard let self else { return }
            SeamToolbarForwarding.forward("layout", from: self)
        }
        toolbar.onFullscreenTapped = { [weak self] in
            guard let self else { return }
            SeamToolbarForwarding.forward("fullscreen", from: self)
        }
        playlistSeamToolbar = toolbar
        // (75) 加载页零帧（Miller 20:29 点名）：拍立得背板
        // 在场期间工具条整条隐藏——收起横线与展开条都不许
        // 出现在加载页上；背板淡出完成（onFadedOut）才恢复。
        // 背板若在装配前已被 dismiss（快路径），其 fadeOut
        // 完成回调仍会触发恢复，隐藏不会残留。
        if let backdrop {
            toolbar.isHidden = true
            backdrop.onFadedOut = { [weak toolbar] in
                toolbar?.isHidden = false
                Breadcrumbs.log("seam.wrap75 loading=done bar=back")
            }
            Breadcrumbs.log("seam.wrap75 loading bar=hidden")
        }
        Breadcrumbs.log("wall.seam.playlist installed")
    }

    @objc private func closeTapped() {
        Breadcrumbs.log("wall.chrome.close kind=playlist")
        // 拍立得背板关闭契约（3.7 (24) 起）：旋转动画取消后
        // requestClose 恒放行，点关闭即收墙。
        if let backdrop, !backdrop.requestClose() { return }
        dismiss(animated: true)
    }

    // (76) ⑧：✕ 的按压反馈 closePressBegan/Ended 随钮一
    // 并撤除（作用对象 closeChromeView 已不存在）。

    // (74) wallSettingsTapped 已随墙内独立齿轮一并撤除：
    // 本面设置入口 = 工具条齿轮（转发回主页开设置面板）。

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
                // 加载文字条已删（3.7 (53) L 组）：原「600ms 未落
                // 地才显示加载胶囊」的延迟任务整段退役——加载期
                // 反馈只剩拍立得背板 + 小猫贴纸（LoadingBackdrop-
                // View 在位），种子等待者仍由 seedReady/flush-
                // SeedWaiters 原路收口，不受影响。
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
                    // 数据变更点（(58)）：条目身份代指递增，实例
                    // 集缓存随之失效重算（与 totalEntries 同批）。
                    self.wallLayout.dataVersion += 1
                    // 提示条/胶囊均已删（(53) L 组删条、(54) L
                    // 撤胶囊）：种子落地无任何上屏文案，背板退场、
                    // 墙面即反馈。
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
                    // (62) 尾波第 5 组：待定位且已呈现 → 此刻飞；
                    // 未呈现（预加载先行）时留给 viewDidAppear。
                    if self.locateCurrentTrackWhenReady, self.view.window != nil {
                        self.locateCurrentTrackWhenReady = false
                        self.locateCurrentTrack()
                    }
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
                        // 分页进度文案已删（3.7 (53) L 组）：拼接
                        // 照常推进，只刷新墙面，不再上屏计数。
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
                    if self.loadAttempts < 2 {
                        // 自动重试期不上屏：静默重拉。
                        self.flushSeedWaiters()
                        self.backdrop?.dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                            self?.loadEntries()
                        }
                    } else {
                        // 最终失败落定（3.7 (54) 工作流 L）：胶囊已
                        // 撤，loadFailed 置位即经 didSet 亮出失败
                        // 贴纸 cat-03，重试入口即贴纸点按
                        // （failureStickerTapped），墙面无文字条。
                        self.loadFailed = true
                        Breadcrumbs.log("wallproto entry-state failed reason=load-failed")
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
        // 滚动统计（(58) 定稿③）：本回调耗时计入逐秒 wall.scroll。
        let scrollStart = CACurrentMediaTime()
        isWrapping = true
        wallLayout.worldOrigin = CGPoint(
            x: wallLayout.worldOrigin.x + delta.x / CGFloat(wallLayout.cameraScale),
            y: wallLayout.worldOrigin.y + delta.y / CGFloat(wallLayout.cameraScale))
        scrollView.contentOffset = center
        // (58)：同键滚动只平移帧、身份不变 → 不 reload；身份
        // 变化（rebase/键变）才 reload（计数入 wall.scroll）。
        let identityChanged = wallLayout.refreshInstances()
        if identityChanged {
            scrollMetrics.noteIdentityChanged()
            collectionView.reloadData()
            scrollMetrics.noteReloadData()
        } else {
            // 平移呈现（3.7 (59) 工作流一，与主页墙同修）：同
            // 键新帧只写进 attributesCache、CV 不重读即冻结，
            // 须显式失效布局让本回合布局 pass 把帧换上屏
            // （只换帧不重配 cell，lattice 恒 0）。
            wallLayout.invalidateLayout()
        }
        isWrapping = false
        scrollMetrics.noteScrollActivity(
            layout: wallLayout,
            didScrollMs: (CACurrentMediaTime() - scrollStart) * 1000,
            panDelta: delta)
        updateLyricOverlayFrame()
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
            loadState: loadState,
            inQueue: QueueManager.shared.containsTrack(id: entry.id))
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
        // (62) 尾波第 1 组：同 HomeWall——补呈现守卫＋present 面包屑，
        // 防呈现竞态下第二台覆盖 canonical 登记（双击闪退候选 2）。
        // (63) DS R63 B1：守卫判定同步落盘 guard.decision（带
        // pvc 类名＋闸门相位），begin 行改同步落盘（同主页墙）。
        let gate = StageExitGate.shared
        let gatePhase = gate.canonicalStage == nil ? "idle"
            : (gate.guardActive ? "guard" : "live")
        let pvcName = presentedViewController.map {
            String(describing: type(of: $0))
        } ?? "nil"
        guard view.window != nil, presentedViewController == nil else {
            Breadcrumbs.logSync("guard.decision host=wallproto go=0"
                + " pvc=\(pvcName) gate=\(gatePhase)")
            Breadcrumbs.log("minibar.doubletap action=stage-skipped reason=busy host=wallproto")
            return
        }
        Breadcrumbs.logSync("guard.decision host=wallproto go=1"
            + " pvc=nil gate=\(gatePhase)")
        Breadcrumbs.log("stage open (native) from playlist wall")
        Breadcrumbs.logSync("stage.present.begin host=wallproto")
        let stage = StageViewController()
        stage.modalPresentationStyle = .fullScreen
        present(stage, animated: true) {
            Breadcrumbs.log("stage.present.done host=wallproto")
        }
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
            // (62) 尾波第 4 组：跟随缓存随锚一并作废，新曲重锚。
            lyricAnchorItemCache = nil
            lyricFollowExpandedId = nil
            lyricOverlayBaseFrame = nil
            lastLyricFollowKey = nil
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
        // 双路去重（(62) 尾波第 4 组）：didScroll、viewDid-
        // LayoutSubviews 与歌词 tick 三路都会调本函数；输入
        // （曲目/展开/锚/原点/偏移/实例集代）未变时结论必同，
        // 直回上次结论，不重复全量 filter 与帧落位。
        let followKey = "\(PlaybackEngine.shared.currentTrack?.id ?? "-")"
            + "|\(wallLayout.expandedInstanceId ?? "-")"
            + "|\(wallLayout.worldOrigin.x),\(wallLayout.worldOrigin.y)"
            + "|\(collectionView.contentOffset.x),\(collectionView.contentOffset.y)"
            + "|\(wallLayout.dataVersion)|\(wallLayout.instances.count)"
            + "|\(lyricAnchorInstanceId ?? "-")"
        if followKey == lastLyricFollowKey { return lastLyricFollowOutcome }
        let outcome = updateLyricOverlayFrameImpl()
        lastLyricFollowKey = followKey
        lastLyricFollowOutcome = outcome
        return outcome
    }

    @discardableResult
    private func updateLyricOverlayFrameImpl() -> LyricAnchorOutcome {
        guard lyricOverlay != nil,
              wallLayout.expandedInstanceId != nil,
              let trackId = PlaybackEngine.shared.currentTrack?.id else { return .noCandidate }
        // 锚下标缓存快路（(62) 尾波第 4 组）：锚已定且展开态
        // 自上次全量判定后未变（接管决定仍成立）时，O(1) 校
        // 验缓存下标仍指向锚实例即直达帧落位，跳过 ≤400 实
        // 例的全量 filter。下标处实例易主（rebase/身份变化）
        // 校验不过，落回下方全量逻辑重找（含出窗隐藏判定）。
        if let anchorId = lyricAnchorInstanceId,
           wallLayout.expandedInstanceId == lyricFollowExpandedId,
           let item = lyricAnchorItemCache,
           wallLayout.instances.indices.contains(item),
           wallLayout.instances[item].instanceId == anchorId,
           let attrs = collectionView.layoutAttributesForItem(
               at: IndexPath(item: item, section: 0)) {
            applyLyricOverlayFrame(attrs: attrs, targetId: anchorId,
                                   restoreReason: "back-in-window")
            return .anchored
        }
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
        lyricAnchorItemCache = item
        lyricFollowExpandedId = wallLayout.expandedInstanceId
        applyLyricOverlayFrame(attrs: attrs, targetId: target.instanceId,
                               restoreReason: restoreReason)
        return .anchored
    }

    /// 帧落位（(62) 尾波第 4 组）：目标帧由布局属性按帧公式
    /// 换算（与旧实现逐字一致）。锚/尺寸变化时落 base frame
    /// 并清 transform；尺寸不变的稳态跟随只写 transform 平
    /// 移——合成器直达、不改 frame、不触发 LyricWindowView
    /// 的 layoutSubviews 逐行重设，拖动期歌词条不再与滚动
    /// 处理抢主线程。帧面包屑口径不变（原点按 40pt 网格去
    /// 重），供真机对账锚定是否恒为播放曲实例、帧是否随卡走。
    private func applyLyricOverlayFrame(attrs: UICollectionViewLayoutAttributes,
                                        targetId: String, restoreReason: String) {
        guard let overlay = lyricOverlay else { return }
        let frame = CGRect(
            x: attrs.frame.minX - collectionView.contentOffset.x + collectionView.frame.minX,
            y: attrs.frame.minY - collectionView.contentOffset.y + collectionView.frame.minY,
            width: attrs.frame.width,
            height: attrs.frame.height)
        if let base = lyricOverlayBaseFrame, base.size == frame.size {
            let t = CGAffineTransform(translationX: frame.minX - base.minX,
                                      y: frame.minY - base.minY)
            if overlay.transform != t { overlay.transform = t }
        } else {
            overlay.transform = .identity
            if overlay.frame != frame { overlay.frame = frame }
            lyricOverlayBaseFrame = frame
        }
        setLyricAnchorHidden(false, reason: restoreReason)
        let crumb = "\(targetId)|\(Int(frame.minX / 40))|\(Int(frame.minY / 40))"
        if crumb != lastLyricOverlayCrumb {
            lastLyricOverlayCrumb = crumb
            Breadcrumbs.log("lrc overlay anchor=\(targetId) frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height)) visible=\(!overlay.isHidden)")
        }
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
        QueueManager.shared.setQueue(queue, startingAt: start, source: "native-wall",
                                     sourcePlaylistId: playlistId)
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
        // (72)：预取走低优先级——快滑时可见 cell 的取图恒
        // 排在预取前面（加载器调度），不再互相堵死。
        Task {
            _ = await NativeCoverLoader.shared.image(
                for: urlString, tier: tier, priority: .prefetch)
        }
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

    // MARK: 按压反馈（(60) 第 3 条①）

    func collectionView(_ collectionView: UICollectionView,
                        didHighlightItemAt indexPath: IndexPath) {
        (collectionView.cellForItem(at: indexPath) as? WallPosterCell)?
            .applyPressTransform(true)
    }

    func collectionView(_ collectionView: UICollectionView,
                        didUnhighlightItemAt indexPath: IndexPath) {
        (collectionView.cellForItem(at: indexPath) as? WallPosterCell)?
            .applyPressTransform(false)
    }

    /// 滚动开始即取消全部可见卡的按压态、交还滚动（(60) 第 3 条①）。
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        for cell in collectionView.visibleCells {
            (cell as? WallPosterCell)?.cancelPressForScroll()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let instance = wallLayout.instances[indexPath.item]
        Breadcrumbs.log("wall tap item=\(indexPath.item) queueIndex=\(instance.queueIndex)")
        // 突变前先清被点卡的按压态（bounce 0.96 的 transform/
        // 动画），展开弹簧从干净态起步。
        let sourceCell = collectionView.cellForItem(at: indexPath) as? WallPosterCell
        sourceCell?.contentView.layer.removeAllAnimations()
        sourceCell?.contentView.transform = .identity
        // hero 共享放大（3.7 (67) D 组立、(70) B1 重定）：
        // 飞行对象是封面图本身——突变前取被点卡已加载的
        // UIImage 与封面实际帧（VC 视图坐标），飞行层与布局
        // 弹簧同曲线把封面从原位长大到展开位（收起反向）。
        // (67) 飞整卡快照（连标题/控件拉伸＋落定硬换）是真
        // 机「整个框慢慢放大＋回程卡一下」的定级根因（取证
        // uitaps A）；图未加载到（占位态/cell 不在场）传
        // nil 走无飞行回退，展开本体不变。
        let heroImage = sourceCell?.coverImage
        let heroSourceFrame = sourceCell.map { $0.coverFrame(in: view) }
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
        animateHeroExpansion(heroImage: heroImage,
                             sourceFrame: heroSourceFrame,
                             targetInstanceId: instance.instanceId)
    }

    /// 展开/收起衔接（3.7 (67) D 组重建 hero 共享放大，
    /// (70) B1 飞行对象改封面图本体）：点封面时飞行层
    /// （封面图）与布局弹簧共用同一条 UIViewPropertyAnimator
    /// （0.45s / damping 0.86）——封面从原位平滑长大到展开
    /// 位、其余卡同曲线让位；收起反向。落定走交叉淡化
    /// （HeroFlight67.finish），不再硬换。
    /// 围栏（(61)/(62) 旧失败模式）：①飞行层是纯叠加动画，
    /// 不碰实例集与 worldOrigin——展开态 rebase＋展开实例钉
    /// 入（WallLayout (62) 尾波第 2 组已落地）原样保留，飞
    /// 行中继续平移也不会与实例集脱节；②身份变化路径先
    /// reloadData＋layoutIfNeeded 落定最终帧再起飞，目标帧
    /// 恒取刷新后属性帧，不存在飞向空位/纯黑页；③封面图
    /// 未就绪（另两处定位落点调用恒传 nil）走原无飞行
    /// 路径，展开本体一字不变。按压 bounce 0.96 与定位落
    /// 点强调是另两套代码，不在此列、保留不动。
    private func animateHeroExpansion(heroImage: UIImage?,
                                      sourceFrame: CGRect?,
                                      targetInstanceId: String?,
                                      completion: (() -> Void)? = nil) {
        // 旧飞行未落定先瞬时收尾（审查修复）：复原被藏真卡、
        // 立即摘旧层，本轮呈现不被旧层干扰、也不会双层同屏。
        if let stale = activeHeroFlight67 {
            activeHeroFlight67 = nil
            stale.finishImmediately()
        }
        // 身份判定改用 refreshInstances 返回值（展开/收起只换
        // expandedRects、实例序列不变）。
        let identityChanged = wallLayout.refreshInstances()
        if identityChanged {
            collectionView.reloadData()
            // hero 目标帧须以落定布局为准：身份变化时先强制
            // 一次布局（无 hero 的旧路径靠后续系统布局收尾，
            // 此处提前一帧不改变最终呈现）。
            collectionView.layoutIfNeeded()
        }
        let flight = makeHeroFlight67(
            image: heroImage, sourceFrame: sourceFrame,
            targetInstanceId: targetInstanceId)
        if !identityChanged {
            if FoliaMotion62.reduced(.queueCollage) {
                // (62) 集成对账：减动效时布局重排不走 animator、
                // 直接落位；飞行层同口径不建（makeHeroFlight67
                // 内已按减动效返回 nil）。
                wallLayout.invalidateLayout()
                collectionView.layoutIfNeeded()
            } else {
                let animator = UIViewPropertyAnimator(duration: 0.45, dampingRatio: 0.86) {
                    self.wallLayout.invalidateLayout()
                    self.collectionView.layoutIfNeeded()
                }
                if let flight {
                    animator.addAnimations { flight.fly() }
                    animator.addCompletion { [weak self] _ in
                        flight.finish()
                        if self?.activeHeroFlight67 === flight {
                            self?.activeHeroFlight67 = nil
                        }
                    }
                }
                animator.startAnimation()
            }
        } else if let flight {
            // 身份变化路径布局已瞬时落定：飞行层自带同一条
            // 弹簧曲线独飞，与新布局的终点帧严丝合缝。
            let animator = UIViewPropertyAnimator(duration: 0.45, dampingRatio: 0.86) {
                flight.fly()
            }
            animator.addCompletion { [weak self] _ in
                flight.finish()
                if self?.activeHeroFlight67 === flight {
                    self?.activeHeroFlight67 = nil
                }
            }
            animator.startAnimation()
        }
        refreshVisiblePlaybackUI()
        completion?()
    }

    /// hero 飞行层装配：目标帧 = 目标实例刷新后的最终属性
    /// 帧（CV 坐标→VC 视图坐标）；源/目标是同一张卡（展开与
    /// 收起都然，实例身份不变、下标不变），飞行期间藏真卡
    /// 防双影、落定复原。任一输入缺失/减动效/源=目标时返回
    /// nil（走无飞行路径）。飞行视图以封面 UIImage 新建
    /// （.scaleAspectFill＋圆角 8，与 cell 封面同式）——飞的
    /// 是图本身，不是整卡位图（(70) B1）。
    private func makeHeroFlight67(image: UIImage?,
                                  sourceFrame: CGRect?,
                                  targetInstanceId: String?) -> HeroFlight67? {
        guard let image, let sourceFrame, let targetInstanceId,
              !FoliaMotion62.reduced(.queueCollage),
              let targetIndex = wallLayout.instances.firstIndex(
                where: { $0.instanceId == targetInstanceId }),
              let attrs = wallLayout.layoutAttributesForItem(
                at: IndexPath(item: targetIndex, section: 0))
        else { return nil }
        let targetFrame = collectionView.convert(attrs.frame, to: view)
        guard targetFrame != sourceFrame else { return nil }
        let flightView = UIImageView(image: image)
        flightView.contentMode = .scaleAspectFill
        flightView.clipsToBounds = true
        flightView.layer.cornerRadius = 8
        flightView.isUserInteractionEnabled = false
        let flight = HeroFlight67(view: flightView, targetFrame: targetFrame)
        flight.view.frame = sourceFrame
        view.addSubview(flight.view)
        activeHeroFlight67 = flight
        if let cell = collectionView.cellForItem(
            at: IndexPath(item: targetIndex, section: 0)) {
            cell.alpha = 0
            flight.hiddenCell = cell
        }
        Breadcrumbs.log("wall.hero from=\(Int(sourceFrame.width))x\(Int(sourceFrame.height))"
            + " to=\(Int(targetFrame.width))x\(Int(targetFrame.height))")
        return flight
    }
}

/// hero 飞行层（3.7 (67) D 组立、(70) B1 改飞封面图）：
/// 封面图视图从源帧飞到目标帧（与布局弹簧同一 animator
/// 曲线）；落定交叉淡化摘层并复原被藏的真卡。纯叠加
/// 动画，不持有任何布局状态。
private final class HeroFlight67 {
    let view: UIView
    private let targetFrame: CGRect
    weak var hiddenCell: UICollectionViewCell?

    init(view: UIView, targetFrame: CGRect) {
        self.view = view
        self.targetFrame = targetFrame
    }

    func fly() {
        view.frame = targetFrame
    }

    /// 落定交叉淡化（3.7 (70) B1）：真卡先复原就位（其封
    /// 面/控件已在终态），飞行层 0.12s easeOut 淡出再摘——
    /// 消灭 (67) finish() 的一帧硬换（取证 uitaps A：回程
    /// 末帧差 31.64→0.47 的截断收尾）。
    func finish() {
        hiddenCell?.alpha = 1
        let flying = view
        UIView.animate(withDuration: 0.12, delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            flying.alpha = 0
        } completion: { _ in
            flying.removeFromSuperview()
        }
    }

    /// 瞬时收尾（新一轮展开抢占未落定旧飞行时）：无淡化
    /// 直接摘层＋复原真卡，不让旧层残影干扰新一轮呈现。
    func finishImmediately() {
        view.removeFromSuperview()
        hiddenCell?.alpha = 1
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

    /// 封面图本体（3.7 (70) B1）：hero 飞行对象改封面图本身，
    /// VC 取此图新建飞行视图（不再截整卡快照）。
    var coverImage: UIImage? { imageView.image }

    /// 封面图在目标视图坐标系中的实际帧（3.7 (70) B1）：
    /// imageView 恒占满整卡（layoutSubviews 中 frame =
    /// shadowView.bounds、展开/收起两态同式），故封面帧即
    /// 整卡帧；换算走视图树转换，不假设嵌套层级。
    func coverFrame(in target: UIView) -> CGRect {
        imageView.convert(imageView.bounds, to: target)
    }

    // 展开卡控件（详情 MVP 第一刀）：播放/暂停、红心、迷你进度条；
    // 未展开只留「正在播放」角标。回调由 VC 按实例注入，普通卡
    // （主页墙歌单卡）永不配置、恒隐藏。
    var onPlayTap: (() -> Void)?
    var onLikeTap: (() -> Void)?
    private let playButton = UIButton(type: .system)
    private let likeButton = UIButton(type: .system)
    /// 「已在队列」角标（3.7 (69) P9，社区版借鉴 N4）：展开
    /// 卡控件行中央的覆层小片，不增卡高、不占标题带；显隐
    /// 由 configurePlayback 的 inQueue 驱动，队列变化经宿主
    /// $queue 订阅重配可见 cell，不许陈旧。
    private let queueBadge = UILabel()
    private var queueBadgeVisible = false
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

        queueBadge.text = "✓ 已在队列"
        queueBadge.font = .systemFont(ofSize: 11, weight: .medium)
        queueBadge.textColor = .white
        queueBadge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        queueBadge.layer.cornerRadius = 8
        queueBadge.clipsToBounds = true
        queueBadge.textAlignment = .center
        queueBadge.isHidden = true
        queueBadge.isUserInteractionEnabled = false
        shadowView.addSubview(queueBadge)

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
                           loadState: WallPlayLoadState = .idle,
                           inQueue: Bool = false) {
        controlsVisible = expanded
        playButton.isHidden = !expanded
        likeButton.isHidden = !expanded
        progressTrack.isHidden = !expanded
        playingBadge.isHidden = !isCurrent
        // (69) P9：角标只在展开卡出（未展开卡面维持现行），
        // 当前曲必然在队列内、同样出角标（与播放角标并存）。
        queueBadgeVisible = expanded && inQueue
        queueBadge.isHidden = !queueBadgeVisible
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
        // (68) A1 状态强可视化：已喜欢 = 整钮填充喜欢色＋白心；
        // 未喜欢维持现行（黑 45% 底＋白描边心）。
        likeButton.tintColor = .white
        likeButton.backgroundColor = liked
            ? UIColor(red: 1, green: 0.35, blue: 0.45, alpha: 0.95)
            : UIColor.black.withAlphaComponent(0.45)
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
        // (66) 歌单卡片样式消费（playlistCardStyle62）：纯图
        // 片封面档隐藏标题/副行、封面独占卡面；拍立得卡片档
        // 为现行标题条形态。设置变更经宿主 reloadData 重排。
        let imageOnly = SettingsStore.playlistCardStyle62 == "image"
        // 展开卡底部让位：进度条 3 + 控件行 34，标题/副行整体上移。
        let bottomInset: CGFloat = controlsVisible ? 41 : 4
        let labelHeight: CGFloat = 16
        let hasSubtitle = !(subtitleLabel.text ?? "").isEmpty
        let titleY = bounds.height - bottomInset - labelHeight - (hasSubtitle ? 13 : 0)
        titleLabel.frame = CGRect(
            x: 6, y: titleY,
            width: bounds.width - 12, height: labelHeight)
        titleLabel.isHidden = imageOnly
        subtitleLabel.frame = CGRect(
            x: 6, y: bounds.height - bottomInset - 13,
            width: bounds.width - 12, height: 12)
        subtitleLabel.isHidden = imageOnly || !hasSubtitle
        if controlsVisible {
            let barTop = bounds.height - 37
            playButton.frame = CGRect(x: 8, y: barTop + 2, width: 30, height: 30)
            likeButton.frame = CGRect(x: bounds.width - 38, y: barTop + 2, width: 30, height: 30)
            progressTrack.frame = CGRect(x: 0, y: bounds.height - 3, width: bounds.width, height: 3)
            layoutProgressFill()
            playSpinner.frame = playButton.frame
            // (69) P9：角标居控件行中央（播放/红心钮之间），
            // 固定高 22、宽按文案定尺，不挤标题带、不增卡高。
            if queueBadgeVisible {
                let badgeWidth: CGFloat = 76
                queueBadge.frame = CGRect(
                    x: (bounds.width - badgeWidth) / 2, y: barTop + 6,
                    width: badgeWidth, height: 22)
            }
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

    /// 按压反馈（(60) 第 3 条①，两面墙共用本 cell）：touch-down
    /// （isHighlighted 置真与 VC 的 didHighlightItemAt 同点）缩
    /// 0.96、touch-up/取消以系统弹簧回弹（约 0.25s）；滚动开始
    /// 时 VC 调 cancelPressForScroll 交还滚动、按压态即取消，
    /// 不与平移手势打架。
    override var isHighlighted: Bool {
        didSet { applyPressTransform(isHighlighted) }
    }

    func applyPressTransform(_ pressed: Bool) {
        UIView.animate(withDuration: pressed ? 0.18 : 0.25, delay: 0,
                       usingSpringWithDamping: pressed ? 0.8 : 0.65,
                       initialSpringVelocity: 0.2,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.contentView.transform = pressed
                ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
        }
    }

    /// 滚动接管时取消按压态：立即弹簧回弹，之后 touch 结束时
    /// isHighlighted 复位再调一次回弹为同目标、无副作用。
    func cancelPressForScroll() {
        guard isHighlighted || contentView.transform != .identity else { return }
        applyPressTransform(false)
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
            imageView.backgroundColor = .clear
            stopPlaceholderPulse()
            return
        }
        currentUrl = urlString
        // 缓存命中同步上图：reloadData/复用重建时不先清空、不异步等一帧，
        // 这是拖动闪黑的主修复。
        if let cached = NativeCoverLoader.shared.cachedImage(for: urlString) {
            coverPlaceholder = false
            stopPlaceholderPulse()
            imageView.backgroundColor = .clear
            imageView.image = cached
            return
        }
        // (72) 主色占位：无目标档图时先垫色——任一档已解码图
        // 的主色优先，再无缓存按地址哈希给暗调色，加载中不
        // 许露纯黑（Miller (71)：歌单页滑快了还是黑屏）。
        imageView.backgroundColor =
            NativeCoverLoader.shared.dominantColorAnyTier(raw: pic, excludingTier: tier)
            ?? NativeCoverLoader.placeholderColor(for: pic)
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
                    self.imageView.backgroundColor = .clear
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
            // 失败重试入口（3.7 (54) 工作流 L）：胶囊撤除后本
            // 贴纸是最终失败的唯一可点补救——StickerView 默认
            // 关交互，这里单独给失败贴纸开交互 + 点按手势；
            // 其余贴纸（空态/缓冲）保持不可点、不抢手势。
            failure.isUserInteractionEnabled = true
            failure.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(failureStickerTapped)))
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
