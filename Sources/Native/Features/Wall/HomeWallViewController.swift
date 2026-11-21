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
    UICollectionViewDataSourcePrefetching, UICollectionViewDelegateFlowLayout {

    private var entries: [WallPrototypeViewController.Entry] = []
    private var playlistIds: [String] = []
    private let wallLayout = WallLayout()
    /// 滚动帧统计（(58) 定稿③）：逐秒 wall.scroll 面包屑。
    private let scrollMetrics = WallScrollMetrics(wallName: "home")
    private var collectionView: UICollectionView!
    // 顶部行动胶囊已整段撤除（3.7 (54) 工作流 L）：原 statusLabel
    // 及其 showStatusNotice/statusTapped 一并删除——未登录入口归
    // 侧栏账户区（与网页版一致）、失败重试归失败贴纸点按、墙面
    // 顶部彻底无条无胶囊。
    /// 入场视频槽位（3.7 (17)，替换 (12) 的电影长卷）：由
    /// EntryIntroPresenter 以横屏 modal 呈现 v5 油画视频。
    /// 触发口径（3.7 (21) 修正，audit-3721 A2）：实例级一次性
    /// ——本实例首次露面才播，同实例后续露面（歌单曲目墙/原生
    /// 舞台等子页 dismiss 返回）不播。判别成立依赖当前拓扑：
    /// 顶层进墙点（3.7 (51) 换根后：SceneDelegate 冷启直建根
    /// 实例；存量 MainViewController 齿轮长按入口同为现场新建）
    /// 都是新建 HomeWall 实例、无复用，故「实例
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
    /// 海报墙回程落位待办（3.7 (40) 项8）：本墙 present 过
    /// 曲目墙（海报 UI）后，下一次露面（曲目墙 dismiss 回
    /// 主页）补一次 beginWallSettle 同族弹簧落位；首露面、
    /// 入场退场露面、舞台/设置返回都不置位，不与入场侧
    /// EntryIntro 的 view 级落位叠加。
    private var posterReturnSettlePending = false
    private var didCenterCamera = false
    /// 旋转冻结代次（3.7 (57) 工作流 A2）：每次
    /// viewWillTransition +1；coordinator completion 只认自己
    /// 那一代——旋转中途反向再转时，旧代 completion 迟到不得
    /// 提前解冻新一代的旋转（见 viewWillTransition）。
    private var wallRotationGeneration = 0
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
    /// 未登录落定态（(51) A 组）：登录主入口在侧栏账户区
    /// （(53) A 组、(54) L 收口）；失败贴纸点按作补救同走登录
    /// （failureStickerTapped 按本标志分发）。
    private var wallNotLoggedIn = false

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
    // 切歌缓冲改触发（3.7 (25)）：点切歌 5s 计时窗 + .waiting 兜底。
    private var stickerBufferTapDeadline: Date?
    private var stickerBufferHideTimer: Timer?
    private var stickerBufferWaiting = false
    // 跳过闪现（3.7 (28)）：令牌防旧的待发隐藏误伤新一轮显示。
    private var stickerSkipFlashToken = 0

    // 底部播放台（3.7 (13.4) #4，Miller 点名）：与曲目墙同款
    // E 液态玻璃台（构造同构、按仓库惯例有意重复）；点按规格
    // (61) 第 7 条起与曲目墙统一（单击浮层/双击详情/进度带
    // 即时 seek，见 miniBarTapped），详情走 openNativeStageFromHome。
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
    /// 主排模式钮（3.7 (55) 工作流 E 修正项，DS 对账）：顶排
    /// 改网页六钮后模式退出顶排，但模式是高频项——主排右端
    /// 补一颗紧凑钮：glyph 随 QueueManager.playMode 四档各异
    /// （顺序 list.bullet / 循环 repeat / 单曲 repeat.1 / 随机
    /// shuffle），点按弹四档菜单点选（非盲循环），与队列面
    /// 板/设置同一存储（QueueManager.playMode）双向同步。
    private var miniModeButton: UIButton!
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
    /// 点播台点按识别器组（3.7 (61) 第 7 条）：展开态单击（require
    /// 双击+长按失败）/展开态双击/收起态单击（无 require 链、即时
    /// 展开）三件分工，启停由 setMiniBarForm 按形态同步（见
    /// syncMiniBarTapRecognizers）；进度带即时 seek 走 seekHit 自带
    /// 识别器（miniSeekTapped），不进本组 require 链。
    private var miniBarTapRecognizer: UITapGestureRecognizer?
    private var miniBarDoubleTapRecognizer: UITapGestureRecognizer?
    private var miniBarCollapsedTapRecognizer: UITapGestureRecognizer?
    /// 迷你台宠物层（3.7 (27)）：纯新增覆盖层，只经下面几处
    /// 一行钩子订阅台子的显隐/形态/切歌边沿，台子逻辑零改动。
    private var miniPetStage: MiniBarPetStage?
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
    /// (51) 右上角关闭键引用：作窗口根时隐藏（见 viewDidAppear）。
    /// (53) L 组改版为 iOS 式 ✕ 毛玻璃圆钮后，引用指整件 chrome
    /// 容器（命中 44pt + 视觉圆 34pt），显隐仍作用于整件。
    private var rootCloseButton: UIView?
    /// 工作台浮层宿主（3.7 (53) A 组）：书库侧栏/头像区叠在
    /// 墙上，关闭态只占把手与头像两个小命中区；侧栏展开时经
    /// 其回调禁墙交互。安装在 viewDidLoad 末尾（见彼处）。
    private var workbenchHost: WorkbenchOverlayHostView?
    /// 速记簿抽屉宿主（(53) D 组装、(54) N 组起持有）：侧栏
    /// 打开时经 setExternallyCovered 整层隐藏（照网页版
    /// is-covered），关栏恢复。
    private var sketchbookDrawer: SketchbookDrawerView?

    // 缝合工具条（3.7 (55) 工作流 E）：工具条视图 + 三段数据
    // + 网格形态 + 过滤 + 沉浸模式，全部状态在此，接线逻辑在
    // 文件尾 seam extension。原始歌单全量（未过滤）存
    // seamRawPlaylists，entries/playlistIds 恒为「当前段 +
    // 隐藏过滤 + 文字过滤」后的呈现集（applyWallData 唯一装配点）。
    private var seamToolbar: SeamToolbarView?
    /// (62) WD §1：墙后层（WallSurfaces62）。墙缝信息条
    /// StripSurface62 已于 (63) 第 4 条按 Miller 令整条摘除。
    private var wallBackdrop62: WallBackdrop62?
    private var seamToolbarTrailing: NSLayoutConstraint?
    /// (62) 集成补接：工具条弹性回零计时（滚动停 0.3s 后归位）。
    private var seamElasticResetWork: DispatchWorkItem?
    /// 歌单→曲目墙共享元素转场的 hero 快照（(60) 第 3 条③）：
    /// beginPosterTransition 起、endPosterTransition 收。
    private var seamPosterHeroView: UIView?
    private var seamSegment: SeamSegment = .songs
    private var seamRawPlaylists: [NativePlaylistSummary] = []
    private var seamRecommendedPlaylists: [NativePlaylistSummary]?
    private var seamExploreTracks: [FoliaTrack]?
    /// 探段当前呈现曲目（过滤后），点按起播的队列即此列。
    private var seamVisibleTracks: [FoliaTrack] = []
    private var seamFilterText = ""
    private var seamFilterBar: UIView?
    private var seamFilterField: UITextField?
    private var gridCollectionView: UICollectionView?
    /// (62) 首页歌曲卡（trackPillShowOnHome 开时墙面同款小卡）。
    private var homeTrackPill62: TrackPill62?
    private var seamGridMode = UserDefaults.standard.bool(forKey: "folia.wall.gridMode")
    private var seamImmersive = false
    private var seamImmersiveTapView: UIView?
    /// 沉浸期被中和的覆盖层原状态（3.7 (61) 第 1.5 条）：进入沉浸
    /// 时存速记簿 covered 态/工作台宿主/宠物层的交互开关，退出
    /// 时逐项恢复（原本就被侧栏 covered 的速记簿不代为解除）。
    private var seamImmersiveSavedSketchbookCovered: Bool?
    private var seamImmersiveSavedWorkbenchEnabled: Bool?
    private var seamImmersiveSavedPetEnabled: Bool?
    private var miniTheme: MiniPlayerTheme = MiniPlayerTheme.effective
    private var miniKnobSkin: UIView?
    /// 玻璃高光两件（顶部亮线 + 极淡白罩）：buildMiniBar 建时
    /// 存引用，供收起态去背景时与主题层/毛玻璃一并隐藏
    /// （3.7 (22)，见 setMiniBarForm）。
    private var miniRimLight: UIView?
    private var miniGlassTint: UIView?

    /// dismiss 统一拦截（3.7 (46)）：同 WallPrototype——带下
    /// canonical 舞台的未登记 dismiss 在 RouteGuard 期内 veto。
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if StageExitGate.shared.shouldVetoDismiss(from: self) { return }
        super.dismiss(animated: flag, completion: completion)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 冷启初始几何自证（(58) 未决清单 #5）：(57) 入场日志里
        // 首轮旋转 from=852x393（冷启瞬间场景横屏尺寸）成因静态
        // 不可推进——此处落墙安装时刻的 bounds 与场景方向，
        // 与 entry rotate 各行对账即可判读初始几何从哪来。
        let sceneOrientation = view.window?.windowScene?.interfaceOrientation
        Breadcrumbs.log("wall.geom.init bounds=\(Int(view.bounds.width))x\(Int(view.bounds.height))"
            + " orient=\(sceneOrientation.map { "\($0.rawValue)" } ?? "nil")")
        // 入场黑帧缝（3.7 (53) I 组定级）：窗口首帧先渲染本视图，
        // 入场 veil 在 viewDidAppear present 时才就位。(61) 第 2
        // 条改口径：墙底改纯黑——dominantColor（橄榄绿 #6A7342）
        // 在帧缺位时会露成平绿画布，垫底只认海报图本体、不认
        // 平均色，与 (59) 黑场第一帧口径一致。
        view.backgroundColor = .black
        // (62) 明暗模式：改读 SettingsStore.daylightMode（窗口级由
        // SceneDelegate 统一 apply；本 VC 不再写死 .dark）。
        overrideUserInterfaceStyle = ThemeSystem62.interfaceStyleOverride()
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
        // 流 C 的点播台上排面板/命令键发出这两条通知，墙面
        // 两台订阅后 present 工作流 D 的面板（类名定死，见文件
        // 尾 seam extension 的 miniBarPanel* 处理）。字幕键信号
        // .foliaMiniBarSubtitle 已随 (60) 第 11 条整组删除。
        NotificationCenter.default.addObserver(
            self, selector: #selector(miniBarPanelPanel),
            name: .foliaMiniBarPanel, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(miniBarPanelCommand),
            name: .foliaMiniBarCommand, object: nil)
        // 隐藏集变更（管理面/长按隐藏）后重装配墙面数据。
        NotificationCenter.default.addObserver(
            self, selector: #selector(seamHiddenPlaylistsChanged),
            name: .foliaHiddenPlaylistsChanged, object: nil)
        // (62) WA 设置变更：侧栏分区显隐/资料库界面即时重读。
        NotificationCenter.default.addObserver(
            self, selector: #selector(home62SettingsChanged),
            name: .foliaSettings62AChanged, object: nil)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: wallLayout)
        // 同 view 底色口径（(61) 第 2 条）：墙画布未铺满/回弹露底时同为纯黑。
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

        // 顶部行动胶囊整段撤除（3.7 (54) 工作流 L，Miller 拍板
        // 按网页版收口）：墙面顶部彻底无条无胶囊。原胶囊两条
        // 路径的新归宿：未登录 → 工作台侧栏账户头/关闭态头像
        // 钮（(53) A 组已落、与网页版账户位同位，点按进三家
        // 登录页）；最终加载失败 → 失败贴纸 cat-03 点按重试
        // （见 stickerEnsureViews 的 failureStickerTapped，
        // 未登录落定态点贴纸同走登录、作最小可点补救）。加载
        // 反馈由入场动画与贴纸层承担，信息文案不上屏。

        // 关闭键（3.7 (53) L 组）：文字胶囊「关闭」→ iOS 系统式
        // ✕ 毛玻璃圆钮。视觉圆 34pt（UIVisualEffectView 系统超薄
        // 材质 + 亮边，与迷你台毛玻璃同款口径）居中于 44pt 命中
        // 容器；锚点与旧胶囊一致（safeArea.top+8、trailing-12）。
        // 关闭行为不变：仍走 closeTapped → dismiss；作窗口根时
        // 整件隐藏（rootCloseButton 指容器，viewDidAppear 收口）。
        // 按压反馈见 closePressBegan/Ended。
        let closeChrome = UIView()
        closeChrome.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeChrome)
        rootCloseButton = closeChrome
        let closeBlur = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        closeBlur.layer.cornerRadius = 17
        closeBlur.layer.borderWidth = 1
        closeBlur.layer.borderColor = UIColor.white.withAlphaComponent(0.30).cgColor
        closeBlur.clipsToBounds = true
        closeBlur.isUserInteractionEnabled = false
        closeBlur.translatesAutoresizingMaskIntoConstraints = false
        closeChrome.addSubview(closeBlur)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
            for: .normal)
        close.tintColor = .white
        close.accessibilityLabel = "关闭"
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.addTarget(self, action: #selector(closePressBegan),
                        for: [.touchDown, .touchDragEnter])
        close.addTarget(self, action: #selector(closePressEnded),
                        for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        closeChrome.addSubview(close)
        NSLayoutConstraint.activate([
            closeChrome.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            closeChrome.widthAnchor.constraint(equalToConstant: 44),
            closeChrome.heightAnchor.constraint(equalToConstant: 44),
            closeBlur.centerXAnchor.constraint(equalTo: closeChrome.centerXAnchor),
            closeBlur.centerYAnchor.constraint(equalTo: closeChrome.centerYAnchor),
            closeBlur.widthAnchor.constraint(equalToConstant: 34),
            closeBlur.heightAnchor.constraint(equalToConstant: 34),
            close.topAnchor.constraint(equalTo: closeChrome.topAnchor),
            close.bottomAnchor.constraint(equalTo: closeChrome.bottomAnchor),
            close.leadingAnchor.constraint(equalTo: closeChrome.leadingAnchor),
            close.trailingAnchor.constraint(equalTo: closeChrome.trailingAnchor)
        ])

        // 墙面齿轮/搜索已删（3.7 (53) L 组入口合并）：工作台
        // 侧栏（(53) A 组）完整覆盖——设置走侧栏底部设置行、
        // 搜索走侧栏搜索分区行、登录走侧栏账户头/关闭态头像
        // 钮，三者与原墙面键调起同一 SettingsViewController /
        // SearchHostPresenter / LoginViewController；桥日志仍
        // 由设置页进入（设置→桥日志）。原 wallSettingsTapped /
        // homeSearchTapped 随键一并删除，无唯一路径丢失。

        // 播放态同步：切歌/播停时刷新台面内容（与曲目墙同构）。
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMiniBar() }
            .store(in: &playbackCancellables)
        PlaybackEngine.shared.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMiniBar() }
            .store(in: &playbackCancellables)
        // 主排模式钮回显（(55) E 修正项）：模式在队列面板/设置/
        // 顶排任一处变更都经同一 @Published 存储回刷本钮。
        QueueManager.shared.$playMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMiniModeButton() }
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

        // 工作台浮层安装（3.7 (53) A 组，DS 对账：不换 root、
        // 不建容器 VC，只在墙上叠一层宿主视图）：关闭态命中
        // 只认把手/头像、其余穿透；侧栏展开时禁墙平移与卡片
        // 点按、关闭恢复。墙画布/入场/点卡 route 均不受影响
        // （宿主不参与这些链，入场 present 走 VC 层级、盖在
        // 宿主之上）。贴纸层视图是懒加的、会盖在本宿主之上，
        // 但其视图不拦触摸（dock 已关交互、失败/缓冲贴纸只在
        // 特定状态短暂出现且不在把手/头像命中区）。
        let workbench = WorkbenchOverlayHostView(hostViewController: self)
        workbench.onSidebarVisibilityChanged = { [weak self] open in
            self?.collectionView.isUserInteractionEnabled = !open
            // 网格形态（(55) E）与墙面同口径：侧栏打开时禁交互。
            self?.gridCollectionView?.isUserInteractionEnabled = !open
            // 速记簿共存（3.7 (54) 工作流 N，照网页版 is-covered
            // 口径）：侧栏打开时速记簿整层隐藏——把手绝不浮压
            // 侧栏之上；关栏原样恢复（抽屉状态保留）。
            self?.sketchbookDrawer?.setExternallyCovered(open)
            Breadcrumbs.log("workbench.wallInteraction enabled=\(!open)")
        }
        workbench.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(workbench)
        NSLayoutConstraint.activate([
            workbench.topAnchor.constraint(equalTo: view.topAnchor),
            workbench.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            workbench.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            workbench.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        workbenchHost = workbench
        // (53) D 组速记簿：左缘把手＋抽屉宿主，装在工作台宿主之后
        // 成为墙面最上层子视图（其 hitTest 只认把手/抽屉、其余穿透，
        // 非模态不挡墙操作；宠物岛走 window.layer 独立层级、互不影响）。
        // (54) N 组起持有引用：侧栏开关经 onSidebarVisibilityChanged
        // 调 setExternallyCovered 整层隐藏/恢复（见上闭包）。
        sketchbookDrawer = SketchbookHost.install(into: view)
        // (53) L 组 chrome 收口留痕：提示条删除 + ✕ 关闭键 +
        // 齿轮/搜索并入侧栏，真机对账以此行确认新包在跑。
        Breadcrumbs.log("wall.chrome home hintBar=removed gearSearch=sidebar close=glass-x")

        // 缝合工具条安装（3.7 (55) 工作流 E、(60) 第 2 条改 z
        // 序）：装在工作台宿主与速记簿之后，工具条本体插到速
        // 记簿宿主之上（见 installSeamChrome），速记簿把手热
        // 区下移 ≥115 与本条纵向错位。接线见文件尾。
        installSeamChrome()
        // (62) WB 钩子总装（动态背景门控/左滑/长按工具条/思索钮）。
        WB62HomeWallHooks.install(in: self)

        loadEntries()
    }

    @objc private func closeTapped() {
        Breadcrumbs.log("wall.chrome.close kind=home")
        dismiss(animated: true)
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
        Breadcrumbs.log("shortcuts62.sKey host=homewall")
        miniBarPanelCommand()
    }

    /// 关闭键按压反馈（3.7 (53) L 组）：按下缩 0.86 + 压暗，
    /// 松手系统弹簧回弹；只动 chrome 容器的 transform/alpha，
    /// 不碰关闭语义。Reduce Motion 时不缩放（guard 直接返回，
    /// ended 仍复位防残留）。
    @objc private func closePressBegan() {
        guard !FoliaMotion62.reduced(.microEffects),
              let chrome = rootCloseButton else { return }
        UIView.animate(withDuration: 0.18, delay: 0,
                       usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            chrome.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
            chrome.alpha = 0.75
        }
    }

    @objc private func closePressEnded() {
        guard let chrome = rootCloseButton else { return }
        UIView.animate(withDuration: 0.35, delay: 0,
                       usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            chrome.transform = .identity
            chrome.alpha = 1
        }
    }

    /// 失败态点按失败贴纸（3.7 (54) 工作流 L）：行动胶囊撤除
    /// 后，失败陪衬贴纸 cat-03 是落定态的最小可点补救（见
    /// stickerEnsureViews 给它开交互 + 本手势），分发与原胶囊
    /// statusTapped 逐字同口径：
    /// - 未登录落定：打开原生登录页（三家登录），成功后重拉
    ///   ——主入口仍是侧栏账户区（网页版同位），此为补救路径。
    /// - 最终加载失败：重置计数重新加载（3.7 (13) #3）。
    @objc private func failureStickerTapped() {
        if wallNotLoggedIn {
            Breadcrumbs.log("home failure-sticker tap action=login")
            let login = LoginViewController()
            login.modalPresentationStyle = .overFullScreen
            login.onLoginSuccess = { [weak self] in
                guard let self else { return }
                self.wallNotLoggedIn = false
                self.loadAttempts = 0
                self.loadEntries()
            }
            present(login, animated: true)
            return
        }
        guard loadFailed else { return }
        Breadcrumbs.log("home failure-sticker tap action=retry")
        loadFailed = false
        loadAttempts = 0
        loadEntries()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // (51) 换根后本墙可作窗口根：无呈现方时「关闭」是空操作死按钮，隐藏之；
        // 被 present 出来时照旧显示（dismiss 回呈现方）。
        rootCloseButton?.isHidden = (presentingViewController == nil && navigationController == nil)
        // 缝合工具条（(55) E）：被 present 时右上 ✕ 与工具条右
        // 端同高，工具条尾距让出 ✕ 的 44pt 命中区；作窗口根
        // 时 ✕ 隐藏、工具条用满宽。登录态头像每次露面刷新
        // （与侧栏账户头同口径）。
        seamToolbarTrailing?.constant =
            (rootCloseButton?.isHidden ?? true) ? -12 : -64
        seamRefreshAccount()
        // (62) 每次露面重读资料库界面选择（设置页改动后回墙生效，
        // 与工具条布局钮同状态源）＋侧栏分区显隐。
        let wantGrid = SettingsStore.librarySuiteChoice == 1
        if wantGrid != seamGridMode { seamToggleLayout() }
        applyHomeTabs62Visibility()
        refreshHomeTrackPill62()
        Breadcrumbs.log("wall.appear kind=home")
        Breadcrumbs.log("home appear")
        // (62) WB §4.8：S 键命令需本墙在响应链上（外接键盘场景）。
        becomeFirstResponder()
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
            // 转场落点留痕（3.7 (40) 项8）：introDidFinish 后
            // 的落点即本露面——退场衔接已由 EntryIntro 侧
            // 直溶 + beginWallSettle（view 级 1.02 弹簧）承
            // 担，本处不叠第二支缩放动画，只落面包屑供真机
            // 对账「播完→主页」衔接是否连续。
            Breadcrumbs.log("transition entry->home appear source=intro-finish")
            // (62) WB §4.7：启动后直达播放界面（入场退场落点消费）。
            WB62HomeWallHooks.entryDidFinish(in: self)
        } else if !didPlayEntryIntro {
            // present 受理才置位：资源缺失/呈现中被拒时不烧掉
            // 本实例唯一的一次，留待下次露面重试，不漏播真入口。
            if EntryIntroPresenter.present(from: self, dataState: { [weak self] in
                self?.entryDataState ?? .failed
            }) {
                didPlayEntryIntro = true
            }
        }
        // 海报墙回程落位（3.7 (40) 项8）：从曲目墙（歌单页）
        // dismiss 回到本主页墙的这次露面，补弹簧落位衔接
        // ——此前只有 present 侧的 crossDissolve、主页侧落
        // 点无任何落位，观感是淡化完硬停/停顿一拍。
        if posterReturnSettlePending {
            posterReturnSettlePending = false
            beginHomeWallReturnSettle(source: "poster-dismiss")
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

    /// 旋转期布局冻结（3.7 (57) 工作流 A2，承 (57) A 报告 §4
    /// 墙侧改动单）：旧链无本覆写，旋转动画的每一中间 bounds
    /// 都经 WallLayout.shouldInvalidateLayout(恒 true)+原始
    /// W/H 指纹触发 layoutLattice 全量重算（≤400 实例），主
    /// 线程被占满、系统旋转动画无法插值——即入场退场录屏里
    /// 「墙面横倒冻结约 0.8s 后猛地正过来」的墙侧共犯。本覆
    /// 写改为：旋转开始即冻结墙布局（动画期间零重算，墙面以
    /// 落定前最后一套属性随系统旋转变换呈现），coordinator
    /// completion 里一次性收尾。快照覆盖法不采用：整屏光栅
    /// 化（≤400 卡）另占 GPU/内存且与宠物/贴纸层级打架，冻结
    /// 已达成动画期间零重算、风险更低。alongside 段刻意传
    /// nil——不借旋转动画做任何墙面工作。
    override func viewWillTransition(to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard viewIfLoaded != nil, collectionView != nil else { return }
        let fromSize = view.bounds.size
        guard size != fromSize else { return }
        wallRotationGeneration += 1
        let generation = wallRotationGeneration
        wallLayout.setRotationFrozen(true)
        Breadcrumbs.log("wall.rotate freeze gen=\(generation)"
            + " from=\(Int(fromSize.width))x\(Int(fromSize.height))"
            + " to=\(Int(size.width))x\(Int(size.height))")
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            // 中途反向再转：旧代 completion 只记账不解冻，新
            // 一代的 completion 才是收尾点（防提前解冻后中间
            // bounds 又触发重算）。
            guard generation == self.wallRotationGeneration else {
                Breadcrumbs.log("wall.rotate superseded gen=\(generation)")
                return
            }
            self.wallLayout.setRotationFrozen(false)
            // 一次性收尾（逐个点名，此外无其他旋转后重排）：
            // ① 墙本体：解冻后唯一一次 invalidate → prepare →
            //    refreshInstances；尺寸类别未变（纯旋转在转置
            //    安全线内）时指纹不变、lattice 零重算，只重建
            //    一次属性帧；类别变了才全量重算一次。
            self.wallLayout.invalidateLayout()
            // (58)：prepare 若因类别变化换了实例集，数据源须
            // 同步 reload（旧版靠后续事件兜底、映射错位窗口
            // 存在）；身份未变则不动。
            if self.wallLayout.lastIdentityChanged {
                self.collectionView.reloadData()
            }
            // ② 迷你台/点播台：宽度按新 bounds 重断言（口径与
            //    viewDidLayoutSubviews 同：min(宽,高)−24，纯旋
            //    转时值不变、横竖屏同宽居中）；台身 centerX/
            //    bottom 安全区锚点由 AutoLayout 随新 bounds 自
            //    动落位，无手动帧。
            if let constraint = self.miniBarWidthConstraint {
                constraint.constant = min(size.width, size.height) - 24
            }
            // ③ 贴纸层：dock/失败/缓冲贴纸是手动帧（缓冲贴纸
            //    依赖迷你台 frame），按新 bounds 重定位一次。
            self.stickerLayoutOverlays()
            // ④ 网格形态：flow 布局按新 bounds 失效一次（与墙
            //    本体同收尾点；网格隐藏时无可见代价）。
            self.gridCollectionView?.collectionViewLayout.invalidateLayout()
            // 其余宿主元素审计结论（不需手动重排）：工作台浮
            // 层/缝合工具条/速记簿/✕ 关闭键均为 AutoLayout 钉
            // 边或安全区锚定，系统布局传递随新 bounds 自动落
            // 位、无自有重算；相机 contentOffset 恒钉中心单元、
            // contentSize 不随 bounds 变（cellViewSize 只由几
            // 何+cameraScale 决定），不需重居中——首次居中未
            // 完成时 viewDidLayoutSubviews 的
            // centerCameraIfNeeded 仍按最终 bounds 接管。
            Breadcrumbs.log("wall.rotate landed gen=\(generation)"
                + " size=\(Int(size.width))x\(Int(size.height))"
                + " instances=\(self.wallLayout.instances.count)"
                + " latticeComputes=\(self.wallLayout.latticeComputeCount)")
        }
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
            // 服务器就绪宽限等待（3.7 (52) 热修）：冷启时墙已是
            // 根、与 LocalServer 异步启动并发；不等就绪就发请求
            // 必然 serverNotReady，且旧重试只有 0.6s 一轮、赶在
            // 服务器起来之前耗尽（(51) 真机：两轮失败永久落
            // 失败页）。在此等 ready（上限 10s，覆盖入场动画的
            // 数据等待窗口）；等待期间 entryDataState 保持
            // .loading，入场继续循环掩盖，不走 data-failed。
            let serverReady = await LocalServer.shared.waitUntilReady(timeout: 10)
            guard generation == self.entryLoadGeneration else { return }
            Breadcrumbs.log("home load attempt=\(loadAttempts)"
                + " serverReady=\(serverReady)"
                + " port=\(LocalServer.shared.port)")
            do {
                // 先从 WebView 重读最新会话（用户可能刚扫码登录），
                // 再探登录态——3.7 (4) 的误判就出在这里。
                await NativeDataClient.shared.refreshWebSession()
                let status = try await NativeDataClient.shared.fetchLoginStatus()
                guard status.loggedIn, let userId = status.userId else {
                    await MainActor.run {
                        guard generation == self.entryLoadGeneration else { return }
                        // 未登录是落定态：入场播完即退场落到失败
                        // 态，不许循环掩盖把用户挡在视频后（3.7
                        // (20)）。墙面不上任何文字（3.7 (54) L）：
                        // 登录主入口在侧栏账户区，失败贴纸点按作
                        // 补救同走登录（failureStickerTapped）。
                        self.entryDataState = .failed
                        self.wallNotLoggedIn = true
                        Breadcrumbs.log("home entry-state failed reason=not-logged-in gen=\(generation)")
                    }
                    return
                }
                // (62) 尾波第 3 组：冷启主线顺手回填资料缓存。
                // fetchLoginStatus 已带 avatarURL，此前整条主线只
                // 用 loggedIn/userId、从不落盘，存量缓存头像键永
                // 不回填（avatar=0 定因断点）。saveProfile 已改
                // 合并语义，此处只传本次真值不会抹其余字段。
                NativeSessionStore.shared.saveProfile(
                    provider: .netease, accountId: userId,
                    displayName: status.nickname,
                    avatarURLString: status.avatarURL)
                let playlists = try await NativeDataClient.shared.fetchUserPlaylists(userId: userId)
                await MainActor.run {
                    guard generation == self.entryLoadGeneration else { return }
                    self.loadAttempts = 0
                    self.loadFailed = false
                    self.wallNotLoggedIn = false
                    self.entryDataState = .ready
                    Breadcrumbs.log("home entries ok n=\(playlists.count)")
                    // 缝合工具条（(55) E）：原始全量存档，呈现集
                    // 由 applyWallData 按当前段/隐藏/过滤统一装配
                    // （歌段即此列过滤后；提示条/胶囊均已删，成功
                    // 态不上屏任何文案，(53)/(54) L 口径不变）。
                    self.seamRawPlaylists = playlists
                    self.applyWallData()
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
                        // 自动重试期不上屏：静默重拉。
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
                        // 墙面无文字条（3.7 (54) L）：失败态由贴纸
                        // 层呈现（entryDataState=.failed → cat-03），
                        // 重试入口即贴纸点按（failureStickerTapped）。
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
        // 网格形态（(55) E）的 collection view 共用本 delegate：
        // 相机折叠只认墙面本体那台，网格滚动不触发。
        guard scrollView === collectionView else { return }
        guard !isWrapping, didCenterCamera else { return }
        let cell = wallLayout.cellViewSize
        guard cell.width > 0, cell.height > 0 else { return }
        let center = CGPoint(x: cell.width, y: cell.height)
        let delta = CGPoint(
            x: scrollView.contentOffset.x - center.x,
            y: scrollView.contentOffset.y - center.y)
        guard delta.x != 0 || delta.y != 0 else { return }
        // (62) 集成补接（WD 待接线项）：缝合工具条骑墙弹性
        // 跟随——滚动位移喂 SeamToolbarView 的弹性 API（欠阻
        // 尼弹簧、偏移 30%、钳 ±10pt），停滚 0.3s 后以 0 回
        // 弹归位。只动工具条自身 transform，与其双态展开/收
        // 起（动内容子视图）不同层、不冲突。
        seamToolbar?.applySeamElasticOffset(delta.y)
        seamElasticResetWork?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            self?.seamToolbar?.applySeamElasticOffset(0)
        }
        seamElasticResetWork = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: reset)
        // 滚动统计（(58) 定稿③）：本回调耗时计入逐秒 wall.scroll。
        let scrollStart = CACurrentMediaTime()
        isWrapping = true
        wallLayout.worldOrigin = CGPoint(
            x: wallLayout.worldOrigin.x + delta.x / CGFloat(wallLayout.cameraScale),
            y: wallLayout.worldOrigin.y + delta.y / CGFloat(wallLayout.cameraScale))
        scrollView.contentOffset = center
        // (58)：同键滚动只平移帧、身份不变 → 不 reload；身份
        // 变化（rebase/键变）才 reload（reloadData 只许在身份
        // 变化点发生，计数入 wall.scroll）。
        let identityChanged = wallLayout.refreshInstances()
        if identityChanged {
            scrollMetrics.noteIdentityChanged()
            collectionView.reloadData()
            scrollMetrics.noteReloadData()
        } else {
            // 平移呈现（3.7 (59) 工作流一）：refreshInstances
            // 只把新帧写进 attributesCache，而 CV 对已可见
            // cell 的帧只在布局失效/reload 时才重读——(58) 同
            // 键路径两者皆无，画面冻结至 rebase 才整屏瞬移
            // （真机证伪）。同键路径在此显式失效布局：CV 本
            // 回合布局 pass 重读全部可见属性帧、只换帧不重
            // 配 cell，位移同帧上屏；prepare 内的二次
            // refreshInstances 是同键纯帧重建（lattice 恒 0、
            // 幂等）。跟手第一性优先于省这一趟算术。
            wallLayout.invalidateLayout()
        }
        isWrapping = false
        scrollMetrics.noteScrollActivity(
            layout: wallLayout,
            didScrollMs: (CACurrentMediaTime() - scrollStart) * 1000,
            panDelta: delta)
    }

    // MARK: - 数据源

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // 网格形态（(55) E）：同数据直列；墙面本体走实例平铺。
        if collectionView === gridCollectionView { return entries.count }
        return wallLayout.instances.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WallPosterCell.reuseId, for: indexPath) as! WallPosterCell
        if collectionView === gridCollectionView {
            let entry = entries[indexPath.item]
            let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
            let pixelExtent = Double(max(frame.width, frame.height)) * Double(UIScreen.main.scale)
            let tier = entry.picUrl.map { NativeCoverLoader.wallTier(raw: $0, pixelExtent: pixelExtent) }
                ?? NativeCoverLoader.tier(forPixelExtent: pixelExtent)
            cell.configure(entry: entry, tier: tier)
            cell.playEntranceIfNeeded(key: entry.id)
            // (62) 网格卡片样式消费：最小透明度（cell alpha 下限由
            // 设置给，呈现取 max）＋3D 卡片（透视倾斜＋高光近似：
            // 绕 X 轴轻倾 6°、m34 透视，诚实近似非真 3D 渲染）。
            cell.alpha = CGFloat(SettingsStore.gridCardMinOpacity)
            if SettingsStore.grid3DCardStyle {
                var transform = CATransform3DIdentity
                transform.m34 = -1.0 / 600
                transform = CATransform3DRotate(transform, 6 * .pi / 180, 1, 0, 0)
                cell.layer.transform = transform
            } else {
                cell.layer.transform = CATransform3DIdentity
            }
            return cell
        }
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
        if collectionView === gridCollectionView {
            for indexPath in indexPaths {
                guard indexPath.item < entries.count,
                      let pic = entries[indexPath.item].picUrl else { continue }
                let tier = NativeCoverLoader.tier(forPixelExtent: 360)
                guard let urlString = NativeCoverLoader.shared.proxiedURLString(pic, tier: tier)
                else { continue }
                if NativeCoverLoader.shared.cachedImage(for: urlString) != nil { continue }
                Task { _ = await NativeCoverLoader.shared.image(for: urlString, tier: tier) }
            }
            return
        }
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

    // MARK: - 转场（3.7 (40) 项8：进/出海报墙的丝滑衔接）

    /// 进海报墙的呈现侧蓄势（与 EntryIntro.beginWallSettle
    /// 同族参数：1.02 蓄势、弹簧 damping 0.9 / velocity
    /// 0.2）：present 的 crossDissolve 段内主页墙轻轻放大，
    /// 目标曲目墙以 1.04→1.0 弹簧落位（WallPrototype
    /// viewDidAppear）同段收尾——两侧同族弹簧 + 交叉淡
    /// 化连续衔接，替原「主页静止一拍 → 淡化硬停」。主
    /// 页被全屏曲目墙盖住后 transform 立即复位（不可见
    /// 时刻复位、无跳变），回程落位另由
    /// beginHomeWallReturnSettle 承担。
    private func beginPosterTransition(source: String, playlistId: String,
                                       heroSnapshot: UIView? = nil,
                                       heroFrame: CGRect? = nil) {
        Breadcrumbs.log("transition home->poster begin source=\(source) playlist=\(playlistId)")
        posterReturnSettlePending = true
        guard !FoliaMotion62.reduced(.playlistExpand) else { return }
        // 共享元素式转场（(60) 第 3 条③）：有被点海报帧为源时，
        // 快照从现帧弹簧放大向全屏中心生长、与 present 的
        // crossDissolve 同段衔接（crossDissolve 降为兜底：无源
        // 帧的菜单入口仍走旧 1.02 蓄势）。
        if let heroSnapshot, let heroFrame {
            heroSnapshot.frame = heroFrame
            heroSnapshot.isUserInteractionEnabled = false
            view.addSubview(heroSnapshot)
            seamPosterHeroView = heroSnapshot
            Breadcrumbs.log("wall.hero expand from=\(Int(heroFrame.minX)),\(Int(heroFrame.minY))"
                + " \(Int(heroFrame.width))x\(Int(heroFrame.height)) source=poster")
            let scale = max(view.bounds.width / max(heroFrame.width, 1),
                            view.bounds.height / max(heroFrame.height, 1))
            UIView.animate(withDuration: 0.55, delay: 0,
                           usingSpringWithDamping: 0.78, initialSpringVelocity: 0.2,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                heroSnapshot.center = self.view.center
                heroSnapshot.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
            // (62) 卡片点开·信息条裂开近似随信息条本体于
            // (63) 第 4 条摘除（StripSurface62 整条删除），
            // hero 放大不再有让位动画对象。
            return
        }
        collectionView.transform = .identity
        UIView.animate(withDuration: 0.45, delay: 0,
                       usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.collectionView.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
        }
    }

    /// present 完成收口：主页已被全屏盖住，此刻复位蓄势
    /// 缩放不可见；落面包屑标记衔接段结束（seed 等待 +
    /// present 动画总时长可由 begin/end 两条对账）。
    private func endPosterTransition(source: String, seedReady: Bool) {
        collectionView.transform = .identity
        // hero 收口（(60) 第 3 条③）：快照淡出撤除，目标墙已
        // 在其下完成 present，不留残影。
        if let hero = seamPosterHeroView {
            seamPosterHeroView = nil
            UIView.animate(withDuration: 0.2) {
                hero.alpha = 0
            } completion: { _ in
                hero.removeFromSuperview()
            }
        }
        Breadcrumbs.log("transition home->poster end source=\(source) seed=\(seedReady)")
    }

    /// 回程落位（beginWallSettle 同族）：曲目墙 dismiss
    /// 回主页的露面处调用——主页墙先置 1.02 蓄势、弹簧
    /// 回 1.00（0.45s / damping 0.9 / velocity 0.2，与入
    /// 场侧墙面落位同参），与 dismiss 的 crossDissolve
    /// 同段并行，消除「歌单 appear → 主页 appear」之间的
    /// 停顿/硬停。作用于 collectionView 而非 view：入场
    /// 侧 beginWallSettle 动的是 presenter.view，两者不
    /// 叠乘。完成复位 transform。
    private func beginHomeWallReturnSettle(source: String) {
        Breadcrumbs.log("transition home settle begin source=\(source)")
        if FoliaMotion62.reduced(.playlistExpand) {
            collectionView.transform = .identity
            Breadcrumbs.log("transition home settle end source=\(source) reduced=1")
            return
        }
        collectionView.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
        UIView.animate(withDuration: 0.45, delay: 0,
                       usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.collectionView.transform = .identity
        } completion: { [weak self] _ in
            self?.collectionView.transform = .identity
            Breadcrumbs.log("transition home settle end source=\(source)")
        }
    }

    // MARK: - 点按：打开该歌单的曲目墙（详情 MVP 前的桥）

    // 按压反馈（(60) 第 3 条①，与曲目墙同 cell 同口径）：
    // touch-down 缩 0.96、touch-up/取消弹簧回弹。
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

    /// 滚动开始即取消按压态、交还滚动（墙面与网格两台同口径）。
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard let cv = scrollView as? UICollectionView else { return }
        for cell in cv.visibleCells {
            (cell as? WallPosterCell)?.cancelPressForScroll()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // 网格形态（(55) E）：索引即条目序，与墙面点卡同路。
        if collectionView === gridCollectionView {
            seamOpenEntry(at: indexPath.item)
            return
        }
        let instance = wallLayout.instances[indexPath.item]
        seamOpenEntry(at: instance.queueIndex)
    }

    /// 点卡统一入口（墙面实例/网格行共用）：探段（曲目形条
    /// 目）以当前呈现列为队列起播；歌/推段（歌单形）打开该
    /// 歌单的曲目墙（下方既有通路）。
    private func seamOpenEntry(at queueIndex: Int) {
        if seamSegment == .explore {
            guard queueIndex < seamVisibleTracks.count else { return }
            Breadcrumbs.log("wall.seam.explore play at=\(queueIndex) n=\(seamVisibleTracks.count)")
            QueueManager.shared.setQueue(
                seamVisibleTracks, startingAt: queueIndex, source: "wall-explore")
            // (62) 播放后进入的视图：起播后按设置路由（默认开台）。
            routeAfterPlayback62()
            return
        }
        guard queueIndex < playlistIds.count, queueIndex < entries.count else { return }
        let entry = entries[queueIndex]
        let wall = WallPrototypeViewController(
            playlistId: playlistIds[queueIndex],
            title: entry.title, coverUrl: entry.picUrl)
        wall.modalPresentationStyle = .fullScreen
        wall.modalTransitionStyle = .crossDissolve
        // 丝滑切入（3.7 (8)）：先预加载，最多等 250ms 让首批数据
        // 落地再 present——预热命中时墙带着内容直接切入，黑屏不
        // 出现；超时照常切入，由墙内氛围底兜住剩余等待。
        // 转场（3.7 (40) 项8 同族弹簧、(60) 第 3 条③共享元素）：
        // 以被点海报卡现帧为源抓快照，present 时 hero 弹簧放
        // 大衔接、crossDissolve 只作无源帧时的兜底（见
        // beginPosterTransition）。
        var heroSnapshot: UIView?
        var heroFrame: CGRect?
        if seamGridMode, let grid = gridCollectionView,
           let cell = grid.cellForItem(at: IndexPath(item: queueIndex, section: 0)) {
            heroSnapshot = cell.snapshotView(afterScreenUpdates: false)
            heroFrame = grid.convert(cell.frame, to: view)
        } else if let item = wallLayout.instances.firstIndex(
                      where: { $0.queueIndex == queueIndex }),
                  let cell = collectionView.cellForItem(
                      at: IndexPath(item: item, section: 0)) {
            heroSnapshot = cell.snapshotView(afterScreenUpdates: false)
            heroFrame = collectionView.convert(cell.frame, to: view)
        }
        beginPosterTransition(source: "tap", playlistId: playlistIds[queueIndex],
                              heroSnapshot: heroSnapshot, heroFrame: heroFrame)
        wall.startPreload()
        Task { [weak self] in
            guard let self else { return }
            let seed = await wall.awaitSeed(timeout: 0.25)
            self.present(wall, animated: true) { [weak self] in
                self?.endPosterTransition(source: "tap", seedReady: seed)
            }
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
        let petStage = MiniBarPetStage(bar: bar)
        view.addSubview(petStage)
        miniPetStage = petStage
        // (60) 第 8 条：4s 长按开启宠物手势挂台身空白域。
        petStage.attachOpenGesture(to: bar)

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

        // 点播台附加功能浮层（3.7 (54) 工作流 H 建上排、(60) 第 7
        // 条迁浮层）：五钮行不再装进台本体，改住透明浮层挂本 VC
        // 的 view（z 序在台之上），底边锚台顶上方 8pt、横向与台
        // 同宽同边距；台高恢复 70（expandedBarHeight）。功能走
        // MiniBarQuickRowView 唯一实现（与曲目墙/舞台同件）；点
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
        Breadcrumbs.log("minibar.webrow homewall overlay attached h=\(Int(MiniBarQuickRowView.expandedBarHeight))")

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

        // 主排模式钮（(55) E 修正项）：主排最右端紧凑钮，菜单
        // 点选四档（showsMenuAsPrimaryAction），glyph/菜单勾选
        // 态由 refreshMiniModeButton 按 QueueManager.playMode
        // 统一回显（订阅在 viewDidLoad、构建后先刷一次）。
        miniModeButton = UIButton(type: .system)
        miniModeButton.tintColor = .white
        miniModeButton.accessibilityLabel = "播放模式"
        miniModeButton.showsMenuAsPrimaryAction = true
        miniModeButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniModeButton)
        refreshMiniModeButton()

        let seekHit = UIView()
        seekHit.backgroundColor = .clear
        seekHit.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(seekHit)
        miniSeekHit = seekHit
        let seekPan = UIPanGestureRecognizer(target: self, action: #selector(miniSeekPanned(_:)))
        seekHit.addGestureRecognizer(seekPan)
        // 进度带单击即时 seek（3.7 (61) 第 7 条区域分域）：seekHit
        // 自带无 require 链的点按识别器，点按当下即跳点，不等台身
        // 单击的双击判定窗口；台身单击/双击识别器对本带落点只做
        // 分域跳过（见 miniBarTapped/miniBarDoubleTapped）。
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
        // 收起态同 −5。形态切换在 setMiniBarForm 里统一改这组
        // 常量。模式钮（(55) E 修正项）同入本组，随形态同位。
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
        // 单击/双击统一规格（3.7 (61) 第 7 条）：展开态单击
        // require(toFail:) 双击与长按两环（双击失败后才触发、
        // 代价约一个双击窗口，换双击无回滚闪烁）；双击进歌曲
        // 详情页；收起态细条走独立无链识别器即时展开。三件的
        // 启停按形态在 setMiniBarForm 同步。宠物层手势不经台
        // 身（宠物识别器整组接走其落点），本链不影响宠物；
        // 4s 开启手势（宠物关闭态）仍挂台身、链外不动。
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

        applyMiniTheme()
        applyMiniBarSlots()
    }

    /// 点播台槽位应用（3.7 (50)）：按 MiniBarSlotSettings 显隐
    /// prev/next 两键（本台无列表键）；隐藏时宽度约束置 0、
    /// 其余键自动收拢补位。宽度约束经按钮自身 constraints
    /// 反查，不改构建期约束块。口径与曲目墙/舞台台一致。
    private func applyMiniBarSlots() {
        guard let prev = miniPrevButton, let next = miniNextButton else { return }
        applySlot(prev, visible: MiniBarSlotSettings.showPrev, width: 34)
        applySlot(next, visible: MiniBarSlotSettings.showNext, width: 34)
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

    /// 主排模式钮回显（(55) E 修正项）：glyph 四档各异（顺序
    /// 与循环不共用 repeat——顺序档用 list.bullet 与顶排/面板
    /// 旧口径的同图区分开，正是本修正要防的「两个打乱键」式
    /// 语义撞车）；菜单四项与队列面板同名（顺序/循环/单曲/
    /// 随机），当前档带勾，点选写回同一 playMode 存储。
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
        // (60) 第 8 条手势域隔离：宠物关闭态下台身空白长按让给
        // 4s 开启手势，切主题不动作（宠物开启态照常）。
        guard gesture.state == .began, let bar = miniBar, !miniBarCollapsed,
              MiniPlayerTheme.effectsEnabled,
              StickerSettings.miniPetsEnabled else { return }
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

    /// 台面单击分发（主页版，3.7 (61) 第 7 条规格＋(62) 尾
    /// 波第 5 组手势合并）：本识别器已 require(toFail:) 双
    /// 击与 0.55s 长按，触发即「双击失败后的单击」。按键各
    /// 自处理；进度带落点分域跳过（seek 已由 seekHit 自带
    /// 识别器即时完成，见 miniSeekTapped）；**封面区单击＝
    /// 回封面播放页（打开当前曲来源歌单的曲目墙并定位展开，
    /// 见 locateCurrentTrackFromCover）**，台身空白/标题区
    /// 维持浮层开关（已开＝收起、不重出；未开＝呼出）。双
    /// 击仍进详情（miniBarDoubleTapped），识别器组与
    /// require 链零改动。
    /// 注：宠物占位区的点按被宠物识别器整组接走，永远到不
    /// 了台身——双击须落在台身空白/封面/标题区（验收口径）。
    @objc private func miniBarTapped(_ gesture: UITapGestureRecognizer) {
        guard let bar = miniBar else { return }
        // 收起态点按本应走无链的 collapsedTap 即时展开；此处
        // 仅作识别器启停万一失同步时的兜底，不走展开态分发。
        // (63) 第 2 条几何自愈：标志说展开（false）但几何已是
        // 细条高（≤20）＝形态失同步——旧路径会落进展开态分
        // 发、命中 seek 带 skip，点细条毫无反应（(62) 反馈现
        // 象）。先按几何把标志纠正为收起，再走既有展开流程；
        // 同步时（几何为展开高）行为与旧版完全一致。
        if miniBarCollapsed || bar.bounds.height <= 20 {
            if !miniBarCollapsed {
                Breadcrumbs.log("minibar.form host=homewall heal=geom"
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
        // 进度带分域（封面优先于进度带，与旧分发序一致：封面
        // 下缘与 seekHit 带约 2pt 重叠，该重叠落点归封面规格、
        // 不归 seek）：带内落点直接返回，seek 已即时发生。
        if miniSeekHit.frame.contains(point), !miniCover.frame.contains(point) {
            Breadcrumbs.log("minibar.tap host=homewall zone=seekband action=skip")
            return
        }
        // (62) 尾波第 5 组：封面区单击换动作——回封面播放页，
        // 不再与台身同走浮层开关。
        if miniCover.frame.contains(point) {
            locateCurrentTrackFromCover()
            return
        }
        if miniQuickRowOverlay?.isShown == true {
            hideMiniQuickRowOverlay(reason: "bar-tap")
            Breadcrumbs.log("minibar.tap host=homewall action=overlay-hide")
        } else {
            showMiniQuickRowOverlay()
            Breadcrumbs.log("minibar.tap host=homewall action=overlay-show")
        }
    }

    /// 台面双击分发（主页版，3.7 (61) 第 7 条）：双击进歌曲详
    /// 情页（openNativeStageFromHome 原路径）；封面同规格参
    /// 与（封面双击同样进详情）。进度带分域：双击落带内不
    /// 触发详情（每击已由 seekHit 识别器即时 seek）；按键区
    /// 自理。宠物占位区双击被宠物识别器接走、到不了台身。
    @objc private func miniBarDoubleTapped(_ gesture: UITapGestureRecognizer) {
        guard let bar = miniBar, !miniBarCollapsed else { return }
        resetMiniIdleTimer()
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point)
            || miniModeButton.frame.contains(point) { return }
        if miniSeekHit.frame.contains(point), !miniCover.frame.contains(point) {
            Breadcrumbs.log("minibar.doubletap host=homewall zone=seekband action=skip")
            return
        }
        Breadcrumbs.log("minibar.doubletap host=homewall action=stage")
        // (63) DS R63 B0：分发边界同步落盘——崩溃会话里本行
        // 在不在，直接判「双击到底有没有走到开台分发」。
        Breadcrumbs.logSync("tap.dispatch host=homewall")
        openNativeStageFromHome()
    }

    /// 封面区单击＝回封面播放页（(62) 尾波第 5 组）：打开当
    /// 前曲来源歌单的曲目墙并定位展开正在播放的卡。来源歌
    /// 单只在队列由歌单墙起播时可知（QueueManager.source-
    /// PlaylistId，歌单墙 setQueue 时传入），且须在本墙歌单
    /// 集内；来源不可知 → 面包屑 locate-miss、无操作（与手
    /// 势合并表口径一致）。呈现走与点卡同路的预加载＋转场，
    /// 定位由曲目墙的 locateCurrentTrackWhenReady 在种子落
    /// 地且已呈现后消费。
    private func locateCurrentTrackFromCover() {
        guard let playlistId = QueueManager.shared.sourcePlaylistId,
              let idx = playlistIds.firstIndex(of: playlistId),
              idx < entries.count else {
            Breadcrumbs.log("minibar.tap host=homewall zone=cover action=locate-miss")
            return
        }
        Breadcrumbs.log("minibar.tap host=homewall zone=cover action=locate playlist=\(playlistId)")
        let entry = entries[idx]
        let wall = WallPrototypeViewController(
            playlistId: playlistId, title: entry.title, coverUrl: entry.picUrl)
        wall.modalPresentationStyle = .fullScreen
        wall.modalTransitionStyle = .crossDissolve
        wall.locateCurrentTrackWhenReady = true
        beginPosterTransition(source: "cover-locate", playlistId: playlistId)
        wall.startPreload()
        Task { [weak self] in
            guard let self else { return }
            let seed = await wall.awaitSeed(timeout: 0.25)
            self.present(wall, animated: true) { [weak self] in
                self?.endPosterTransition(source: "cover-locate", seedReady: seed)
            }
        }
    }

    /// 收起态细条单击（3.7 (61) 第 7 条）：独立识别器、无任何
    /// require 链，点按即时展开回完整形态并重新计时（展开在
    /// expandMiniBar 内），不被双击判定拖延。
    @objc private func miniBarCollapsedTapped(_ gesture: UITapGestureRecognizer) {
        guard miniBarCollapsed else { return }
        Breadcrumbs.log("minibar.tap host=homewall collapsed=1 action=expand")
        expandMiniBar()
    }

    /// 进度带单击即时 seek（3.7 (61) 第 7 条）：seekHit 自带
    /// 识别器、无 require 链，触发即跳点。封面下缘约 2pt 重
    /// 叠落点归封面规格（单击浮层/双击详情），不在此 seek；
    /// 按键区自理；收起态不 seek（细条单击只展开）。
    @objc private func miniSeekTapped(_ gesture: UITapGestureRecognizer) {
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
        Breadcrumbs.log("minibar.seek host=homewall via=seek-tap")
    }

    /// 点按识别器组按形态启停（3.7 (61) 第 7 条）：展开态启
    /// 单击（require 双击/长按）+双击、停收起单击；收起态反
    /// 之。全部形态切换都经 setMiniBarForm 收口到这里，启停
    /// 与形态严格同步。
    private func syncMiniBarTapRecognizers(collapsed: Bool) {
        miniBarTapRecognizer?.isEnabled = !collapsed
        miniBarDoubleTapRecognizer?.isEnabled = !collapsed
        miniBarCollapsedTapRecognizer?.isEnabled = collapsed
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

    // MARK: - 迷你台收起（3.7 (21)：5 秒无操作自动收成进度条，与曲目墙同构）

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
    private func setMiniBarForm(collapsed: Bool) {
        miniBarHeightConstraint?.constant = collapsed ? 16 : MiniBarQuickRowView.expandedBarHeight
        // (60) 第 7 条：展开台高回 70 后主排中心两形态同为 −5。
        for constraint in miniMainCenterY { constraint.constant = -5 }
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
        // 点按识别器组随形态启停（3.7 (61) 第 7 条）：收起态
        // 只认无链单击即时展开，展开态才挂双击判定链。
        syncMiniBarTapRecognizers(collapsed: collapsed)
        // (63) 第 2 条形态面包屑：每次形态收口落一行——标志/
        // 几何高/三识别器启停位同行，下轮日志一次判清标志与
        // 几何是否同值（细条无法展开的判别证据）。
        Breadcrumbs.log("minibar.form host=homewall collapsed=\(collapsed ? 1 : 0)"
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

    // MARK: 附加功能浮层（3.7 (60) 第 7 条，主页墙宿主）
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
        Breadcrumbs.log("quickrow.overlay show host=homewall")
        scheduleMiniQuickRowAutoHide()
    }

    private func hideMiniQuickRowOverlay(reason: String) {
        miniQuickRowHideWorkItem?.cancel()
        miniQuickRowHideWorkItem = nil
        guard let overlay = miniQuickRowOverlay, overlay.isShown else { return }
        overlay.setShown(false)
        Breadcrumbs.log("quickrow.overlay hide host=homewall reason=\(reason)")
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

    /// 原生舞台入口（3.7 (14)，M2'）：与曲目墙同构——舞台全屏
    /// 盖在主页墙上、关闭即纯 dismiss 回墙。跳网页舞台由舞台自
    /// 身叠加 present 网页宿主（3.7 (51) 新链，见 StageView-
    /// Controller 的 jumpToWebStage）；原 openStageFromHome 回
    /// 程票套（存票+收墙+凭票恢复）已随回程票链整链删除
    /// （3.7 (51)）。
    private func openNativeStageFromHome() {
        // (62) 尾波第 1 组：present 无守卫是双击闪退候选 2——呈现
        // 动画期间第二记双击可再造一台并覆盖 canonical 登记。
        // 与面板口径（seamPresentPanel）对齐补守卫＋present 面包屑。
        // (63) DS R63 B1：守卫判定同步落盘一行 guard.decision，
        // 带 presented 顶层类名与闸门相位（兼覆 M4 present/
        // dismiss 交叉判读）；begin 行改同步落盘（M5）。
        let gate = StageExitGate.shared
        let gatePhase = gate.canonicalStage == nil ? "idle"
            : (gate.guardActive ? "guard" : "live")
        let pvcName = presentedViewController.map {
            String(describing: type(of: $0))
        } ?? "nil"
        guard view.window != nil, presentedViewController == nil else {
            Breadcrumbs.logSync("guard.decision host=homewall go=0"
                + " pvc=\(pvcName) gate=\(gatePhase)")
            Breadcrumbs.log("minibar.doubletap action=stage-skipped reason=busy host=homewall")
            return
        }
        Breadcrumbs.logSync("guard.decision host=homewall go=1"
            + " pvc=nil gate=\(gatePhase)")
        Breadcrumbs.log("stage open (native) from home wall")
        Breadcrumbs.logSync("stage.present.begin host=homewall")
        let stage = StageViewController()
        stage.modalPresentationStyle = .fullScreen
        present(stage, animated: true) {
            Breadcrumbs.log("stage.present.done host=homewall")
        }
    }

    /// (62) 播放后进入的视图路由：点歌起播后按 playbackEntryView
    /// 决定去向——stage 开台（默认）、detail 开台后打开播放面板、
    /// stay 留在当前页。仅点歌路径（探段直点起播）走本路由；
    /// 迷你台双击/回到播放页/后台点入等显式导航仍走
    /// openNativeStageFromHome 原路、不受本设置管辖。
    private func routeAfterPlayback62() {
        switch PlaybackEntry62.current {
        case .stay:
            Breadcrumbs.log("entry62 route=stay")
        case .detail:
            Breadcrumbs.log("entry62 route=detail")
            openNativeStageFromHome()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                PlaybackEntry62.openPanelOnPresentedStage(from: self)
            }
        case .stage:
            Breadcrumbs.log("entry62 route=stage")
            openNativeStageFromHome()
        }
    }

    /// 后台点入直达（3.7 (31)）：SceneDelegate 在「曾进后台 + 有活跃
    /// 队列 + 本墙正是顶层」时调用，与本墙既有舞台入口同路。
    func openNativeStageForBackgroundReturn() {
        openNativeStageFromHome()
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
//   小只——dog-05（原地翻滚）与 cat-08（翻滚）按回合轮换，
//   58pt；触发口径 3.7 (25) 改为点切歌即出、约 5s 收，
//   .waiting 仅作兜底（见 stickerNoteTrackChangeTap 状态机）。
// 全部只读既有状态（entryDataState / playbackState），不回写
// 任何状态机；全部贴纸透明底直贴、无底板（3.7 (25) 定案）。

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
            failure.crumbScene = "home-offline"
            failure.isHidden = true
            // 失败落定补救入口（3.7 (54) 工作流 L）：胶囊撤除后
            // 本贴纸是失败态的最小可点补救——StickerView 默认
            // 关交互，这里单独给失败贴纸开交互 + 点按手势（分
            // 发见 failureStickerTapped：未登录走登录、加载失败
            // 走重试）；跑动/缓冲贴纸保持不可点、不抢手势。
            failure.isUserInteractionEnabled = true
            failure.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(failureStickerTapped)))
            view.addSubview(failure)
            stickerFailureView = failure
        }
        if stickerBufferView == nil {
            let buffer = StickerView()
            buffer.crumbScene = "home-buffer"
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
            runner.crumbScene = "home-runner"
            dock.addSubview(runner)
            stickerRunnerView = runner
        }
        runner.layer.removeAllAnimations()
        if useDog {
            runner.frame = CGRect(x: -110, y: 8, width: 100, height: 100)
            runner.setSticker("dog-21", mode: .loop)
        } else {
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

    // MARK: 切歌缓冲（3.7 (25) 改触发，状态机）
    //
    // - 点切歌（迷你台上下曲/点歌起播）→ stickerNoteTrackChangeTap：
    //   立即出贴纸（回合轮换 dog-05/cat-08，均循环），开 5s 计时
    //   窗；窗内再点切歌 → 换回合贴纸并重置 5s。歌曲真正起播不
    //   提前收（满 5s 口径）。
    // - 5s 到点：引擎已非 .waiting → 淡出隐藏；仍 .waiting →
    //   转兜底态继续显示，待离开 .waiting 才收。
    // - 无计时窗时 .waiting 到来 → 兜底直显（旧行为），离开
    //   .waiting 即收。两路冲突以计时窗为准（窗内 .waiting 的
    //   进出不改显隐）。

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
            // 兜底直显：仅在无点切歌计时窗、且当前有曲时。
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

    /// 确定性不可播被自动跳过：迷你台左上落点闪现一次无版权
    /// 贴纸作提示（主页墙无展开曲目卡，只有这一落点）。本墙
    /// 不在屏上时不闪；缓冲状态机忙时不抢视图（台面已有反馈）。
    @objc func stickerTrackSkippedUnplayable() {
        guard view.window != nil else { return }
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
        // 穿模治理（3.7 (25)）：跑动 dock 压到迷你台之下——跑过
        // 时从台身后穿过，不压台面文字与按键。
        if let dock = stickerDock, let bar = miniBar,
           dock.superview === view, bar.superview === view,
           let dockIdx = view.subviews.firstIndex(of: dock),
           let barIdx = view.subviews.firstIndex(of: bar),
           dockIdx > barIdx {
            view.insertSubview(dock, belowSubview: bar)
        }
    }
}

// MARK: - 缝合工具条接线（3.7 (55) 工作流 E）
//
// 工具条本体见 SeamToolbarView；本段只做宿主接线：三段数据
// 装配（applyWallData 是 entries/playlistIds 的唯一装配点）、
// 网格形态、过滤浮层、沉浸模式、「…」菜单五项动作、账户
// 回填、点播台面板通知（任务三）的呈现。

extension HomeWallViewController {

    // MARK: 安装

    func installSeamChrome() {
        // (62) WD §1 墙后层：插在墙画布之下，画布底色改透使
        // 墙后画面（透光封面/模糊/墙后歌词）可见；网格画布
        // 本就 clear 不受影响。墙几何本体不动。
        if wallBackdrop62 == nil {
            let backdrop = WallBackdrop62()
            backdrop.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(backdrop, belowSubview: collectionView)
            NSLayoutConstraint.activate([
                backdrop.topAnchor.constraint(equalTo: view.topAnchor),
                backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            wallBackdrop62 = backdrop
            collectionView.backgroundColor = .clear
        }
        // 网格形态：与墙面同一份 entries 的 flow 呈现，插在墙
        // 画布正上方、其余 chrome 之下；初始按持久化选择显隐。
        let flow = UICollectionViewFlowLayout()
        flow.scrollDirection = .vertical
        flow.minimumInteritemSpacing = 10
        flow.minimumLineSpacing = 14
        flow.sectionInset = UIEdgeInsets(top: 60, left: 14, bottom: 150, right: 14)
        let grid = UICollectionView(frame: view.bounds, collectionViewLayout: flow)
        grid.backgroundColor = .clear
        grid.dataSource = self
        grid.delegate = self
        grid.prefetchDataSource = self
        grid.showsVerticalScrollIndicator = false
        grid.register(WallPosterCell.self, forCellWithReuseIdentifier: WallPosterCell.reuseId)
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(grid, aboveSubview: collectionView)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor),
            grid.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        grid.isHidden = !seamGridMode
        collectionView.isHidden = seamGridMode
        gridCollectionView = grid

        // 工具条 z 序（(60) 第 2 条）：提到速记簿宿主之上作双
        // 保险——速记簿把手热区已下移（edgeTop ≥115）与本条纵
        // 向错位，此处再保顶部条带的命中不被速记簿层拦截。
        // 工作台宿主/侧栏彼此的相对序不动（速记簿原本即在工
        // 作台宿主之上，本条只是越过速记簿一层）。
        let toolbar = SeamToolbarView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        if let drawer = sketchbookDrawer {
            view.insertSubview(toolbar, aboveSubview: drawer)
        } else if let host = workbenchHost {
            view.insertSubview(toolbar, belowSubview: host)
        } else {
            view.addSubview(toolbar)
        }
        seamToolbarTrailing = toolbar.trailingAnchor.constraint(
            equalTo: view.trailingAnchor, constant: -12)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            seamToolbarTrailing!,
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
        ])
        // (63) 第 4 条：墙缝信息条（StripSurface62）按 Miller
        // 令整条摘除——装配块删除后工具条下方区域回归墙面卡
        // 片本体；条本不拦截触摸，顶部热区与层级零变化。
        toolbar.setLayoutMode(grid: seamGridMode)
        toolbar.onSegmentChanged = { [weak self] segment in
            self?.seamSegmentSelected(segment)
        }
        toolbar.onAvatarTapped = { [weak self] in self?.seamAvatarTapped() }
        toolbar.onSearchTapped = { [weak self] in
            guard let self else { return }
            Breadcrumbs.log("wall.seam.search")
            SearchHostPresenter.presentSearch(from: self)
        }
        toolbar.onSettingsTapped = { [weak self] in
            guard let self else { return }
            Breadcrumbs.log("wall.seam.settings")
            let settings = SettingsViewController()
            settings.modalPresentationStyle = .overFullScreen
            self.present(settings, animated: false)
        }
        toolbar.onLayoutTapped = { [weak self] in self?.seamToggleLayout() }
        toolbar.onMoreTapped = { [weak self] anchor in
            self?.seamMoreTapped(anchor: anchor)
        }
        toolbar.onFullscreenTapped = { [weak self] in self?.seamSetImmersive(true) }
        seamToolbar = toolbar

        buildSeamFilterBar(below: toolbar)
        buildSeamImmersiveTapView()
        Breadcrumbs.log("wall.seam.installed grid=\(seamGridMode)")
    }

    private func buildSeamFilterBar(below toolbar: SeamToolbarView) {
        let bar = UIView()
        bar.isHidden = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.layer.cornerRadius = 16
        blur.layer.borderWidth = 1
        blur.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false
        blur.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(blur)
        let field = UITextField()
        field.placeholder = "按标题过滤当前页"
        field.attributedPlaceholder = NSAttributedString(
            string: "按标题过滤当前页",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)])
        field.textColor = .white
        field.font = .systemFont(ofSize: 14)
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.translatesAutoresizingMaskIntoConstraints = false
        field.addTarget(self, action: #selector(seamFilterTextChanged), for: .editingChanged)
        field.addTarget(self, action: #selector(seamFilterDone), for: .editingDidEndOnExit)
        bar.addSubview(field)
        seamFilterField = field
        let clear = UIButton(type: .system)
        clear.setTitle("清除", for: .normal)
        clear.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        clear.tintColor = UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 1)
        clear.translatesAutoresizingMaskIntoConstraints = false
        clear.addTarget(self, action: #selector(seamFilterClearTapped), for: .touchUpInside)
        bar.addSubview(clear)
        if let host = workbenchHost {
            view.insertSubview(bar, belowSubview: host)
        } else {
            view.addSubview(bar)
        }
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            blur.topAnchor.constraint(equalTo: bar.topAnchor),
            blur.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6),
            bar.heightAnchor.constraint(equalToConstant: 44),
            field.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: clear.leadingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            clear.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            clear.widthAnchor.constraint(equalToConstant: 44),
            clear.heightAnchor.constraint(equalToConstant: 44),
        ])
        seamFilterBar = bar
    }

    private func buildSeamImmersiveTapView() {
        let tapView = UIView()
        tapView.backgroundColor = .clear
        tapView.isHidden = true
        tapView.translatesAutoresizingMaskIntoConstraints = false
        tapView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(seamImmersiveTap(_:))))
        if let host = workbenchHost {
            view.insertSubview(tapView, belowSubview: host)
        } else {
            view.addSubview(tapView)
        }
        NSLayoutConstraint.activate([
            tapView.topAnchor.constraint(equalTo: view.topAnchor),
            tapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        seamImmersiveTapView = tapView
    }

    // MARK: 数据装配（唯一装配点）

    /// 按「当前段 → 隐藏过滤 → 文字过滤」装配呈现集。歌段源
    /// 是 loadEntries 的原始全量；推段源是推荐歌单缓存；探段
    /// 源是探索曲目缓存（曲目形，playlistIds 恒空、点按起播）。
    func applyWallData() {
        let hidden = HiddenPlaylistsStore.shared.hiddenIds
        let filter = seamFilterText.trimmingCharacters(in: .whitespaces)
        switch seamSegment {
        case .songs, .recommend:
            var list = (seamSegment == .songs
                ? seamRawPlaylists
                : (seamRecommendedPlaylists ?? []))
                .filter { !hidden.contains($0.id) }
            if !filter.isEmpty {
                list = list.filter { $0.name.localizedCaseInsensitiveContains(filter) }
            }
            playlistIds = list.map(\.id)
            entries = list.map { playlist in
                WallPrototypeViewController.Entry(
                    id: playlist.id,
                    title: playlist.name,
                    picUrl: playlist.coverUrl,
                    subtitle: seamSegment == .songs
                        ? "歌单 · \(playlist.trackCount)"
                        : "推荐歌单 · \(playlist.trackCount)")
            }
            seamVisibleTracks = []
        case .explore:
            var tracks = seamExploreTracks ?? []
            if !filter.isEmpty {
                tracks = tracks.filter {
                    $0.title.localizedCaseInsensitiveContains(filter)
                        || $0.artist.localizedCaseInsensitiveContains(filter)
                }
            }
            seamVisibleTracks = tracks
            playlistIds = []
            entries = tracks.map { track in
                WallPrototypeViewController.Entry(
                    id: track.id,
                    title: track.title,
                    picUrl: track.artworkURL?.absoluteString,
                    subtitle: track.artist)
            }
        }
        // (62) 记住主页卡片位置：开时按落盘顺序重排呈现集（已存
        // 顺序优先、新条目随后），并把当前顺序回存。作用于条目
        // 顺序与网格滚动原点，不动 BravaisFinite 几何本体。
        if SettingsStore.rememberCardPositions, seamSegment != .explore {
            let saved = SettingsStore.wallCardOrder
            if !saved.isEmpty {
                let rank = Dictionary(uniqueKeysWithValues:
                    saved.enumerated().map { ($1, $0) })
                let paired = zip(entries, playlistIds).sorted { a, b in
                    (rank[a.0.id] ?? Int.max) < (rank[b.0.id] ?? Int.max)
                }
                entries = paired.map { $0.0 }
                playlistIds = paired.map { $0.1 }
            }
            SettingsStore.wallCardOrder = entries.map { $0.id }
            Breadcrumbs.log("wall62.cardOrder memory=1 n=\(entries.count)")
        }
        wallLayout.totalEntries = entries.count
        // 数据变更点（(58)）：条目身份代指递增，实例集缓存随之
        // 失效重算（与 totalEntries 同批，此外无第二处赋值）。
        wallLayout.dataVersion += 1
        wallLayout.refreshInstances()
        collectionView.reloadData()
        gridCollectionView?.reloadData()
        centerCameraIfNeeded()
        Breadcrumbs.log("wall.seam.data segment=\(seamSegment.crumbName)"
            + " n=\(entries.count) filter=\(!filter.isEmpty) hidden=\(hidden.count)")
    }

    @objc func seamHiddenPlaylistsChanged() {
        applyWallData()
    }

    // MARK: 三段切换

    func seamSegmentSelected(_ segment: SeamSegment) {
        guard segment != seamSegment else { return }
        seamSegment = segment
        Breadcrumbs.log("wall.seam.segment=\(segment.crumbName)")
        switch segment {
        case .songs:
            applyWallData()
        case .recommend:
            if seamRecommendedPlaylists != nil {
                applyWallData()
            } else {
                loadSeamRecommend()
            }
        case .explore:
            if seamExploreTracks != nil {
                applyWallData()
            } else {
                loadSeamExplore()
            }
        }
    }

    /// 推段加载失败的诚实回退：提示后回歌段（不留假段控、
    /// 不留空白墙假装有内容）。
    private func seamSegmentLoadFailed(_ segment: SeamSegment) {
        Breadcrumbs.log("wall.seam.segment failed=\(segment.crumbName) revert=songs")
        seamSegment = .songs
        seamToolbar?.setSegment(.songs)
        applyWallData()
        let alert = UIAlertController(
            title: segment == .recommend ? "推荐暂时不可用" : "探索暂时不可用",
            message: "需要登录网易云，或网络暂时不可用。已回到你的歌单。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func loadSeamRecommend() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let playlists = try await NativeDataClient.shared.fetchRecommendedPlaylists()
                await MainActor.run {
                    self.seamRecommendedPlaylists = playlists
                    Breadcrumbs.log("wall.seam.recommend ok n=\(playlists.count)")
                    if self.seamSegment == .recommend { self.applyWallData() }
                }
            } catch {
                await MainActor.run {
                    if self.seamSegment == .recommend {
                        self.seamSegmentLoadFailed(.recommend)
                    }
                }
            }
        }
    }

    private func loadSeamExplore() {
        Task { [weak self] in
            guard let self else { return }
            // 每日推荐 + 私人 FM 两路各自成败（工作台电台同口径）：
            // 任一路有货即成段，两路全空才算失败回退。
            async let dailyTask = NativeDataClient.shared.fetchDailySongs()
            async let fmTask = NativeDataClient.shared.fetchPersonalFM()
            let daily = (await try? dailyTask) ?? []
            let fm = (await try? fmTask) ?? []
            var seen = Set<String>()
            let merged = (daily + fm).map(workbenchFoliaTrack).filter {
                seen.insert($0.id).inserted
            }
            await MainActor.run {
                guard self.seamSegment == .explore else { return }
                if merged.isEmpty {
                    self.seamSegmentLoadFailed(.explore)
                } else {
                    self.seamExploreTracks = merged
                    Breadcrumbs.log("wall.seam.explore ok daily=\(daily.count) fm=\(fm.count)")
                    self.applyWallData()
                }
            }
        }
    }

    // MARK: 布局切换（网格 ⇄ Bravais 墙）

    /// 网页 suite 切换版面过渡的原生落点：交叉淡化 + 0.98
    /// 缩放、0.3s 系统弹簧（Home.tsx 的 suite 切换本身无自有
    /// 时序参数、经 registry 换面，故按 iOS 系统转场口径取
    /// 此参，与本仓 (40) 转场同族）。选择落 UserDefaults 记忆。
    func seamToggleLayout() {
        seamGridMode.toggle()
        UserDefaults.standard.set(seamGridMode, forKey: "folia.wall.gridMode")
        // (62) 资料库界面设置项同状态源：写 SettingsStore.librarySuiteChoice
        //（其 setter 双写新键+旧键），设置页改动与工具条钮互跟随。
        SettingsStore.librarySuiteChoice = seamGridMode ? 1 : 0
        seamToolbar?.setLayoutMode(grid: seamGridMode)
        Breadcrumbs.log("wall.seam.layout=\(seamGridMode ? "grid" : "bravais")")
        guard let grid = gridCollectionView else { return }
        let showGrid = seamGridMode
        grid.isHidden = false
        collectionView.isHidden = false
        grid.alpha = showGrid ? 0 : 1
        collectionView.alpha = showGrid ? 1 : 0
        grid.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        collectionView.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            grid.alpha = showGrid ? 1 : 0
            self.collectionView.alpha = showGrid ? 0 : 1
            grid.transform = .identity
            self.collectionView.transform = .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            grid.isHidden = !showGrid
            self.collectionView.isHidden = showGrid
            grid.alpha = 1
            self.collectionView.alpha = 1
            // (61) 第 1.5 条 trace 接线：布局切换完成收口（入口
            // beginAction 由工具条布局钮侧发出，WA 簇接线）。
            InteractionTrace.shared.endAction("layout-done")
            Breadcrumbs.log("wall.seam.trace endAction=layout-done")
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // 只服务网格 flow 布局（墙面本体是自定义 WallLayout、
        // 不走本方法）。三列等宽方卡，封面内标题叠底（cell 本
        // 形），横屏按宽重算列宽、行数自然增减。
        // (62) 网格卡片项消费：卡片最小尺寸决定列数下限；正方形
        // 开关关时卡片改 4:5 竖幅；全画幅封面开时列数按整宽算。
        let width = collectionView.bounds.width
        let bleed = SettingsStore.gridFullBleedCover
        let available = width - (bleed ? 0 : 28) - 20
        let minSide = CGFloat(SettingsStore.gridCardMinSize)
        let columns = max(2, min(4, Int(floor(available / minSide))))
        let side = max(60, floor(available / CGFloat(columns)))
        let height = SettingsStore.gridSquareCards ? side : side * 1.25
        return CGSize(width: side, height: height)
    }

    // MARK: (62) WA 消费面

    @objc func home62SettingsChanged() {
        applyHomeTabs62Visibility()
        refreshHomeTrackPill62()
        // (62) 全画幅封面：开时网格边距收零、封面铺满列宽。
        if let flow = gridCollectionView?.collectionViewLayout as? UICollectionViewFlowLayout {
            flow.sectionInset = SettingsStore.gridFullBleedCover
                ? UIEdgeInsets(top: 60, left: 0, bottom: 150, right: 0)
                : UIEdgeInsets(top: 60, left: 14, bottom: 150, right: 14)
        }
        gridCollectionView?.collectionViewLayout.invalidateLayout()
        gridCollectionView?.reloadData()
    }

    /// 顶部胶囊入口显隐（(62) §4.3）：侧栏分区行按总开关＋5 页签
    /// 开关显隐——关掉的分区行不渲染（isHidden 于 UIStackView 即
    /// 不占位）。映射：歌单→「歌单」、推荐→「电台」、探索→「搜索」、
    /// 专辑→「专辑」、本地→「本地」（原生侧栏既有分区名）。
    func applyHomeTabs62Visibility() {
        guard let host = workbenchHost else { return }
        let master = SettingsStore.homeTabsEnabled
        let map: [String: Bool] = [
            "歌单": master && SettingsStore.showHomeTabPlaylists,
            "电台": master && SettingsStore.showHomeTabRecommend,
            "搜索": master && SettingsStore.showHomeTabExplore,
            "专辑": master && SettingsStore.showHomeTabAlbums,
            "本地": master && SettingsStore.showHomeTabLocal,
        ]
        var applied = 0
        func walk(_ v: UIView) {
            if let button = v as? UIButton,
               let label = button.accessibilityLabel,
               let visible = map[label] {
                button.isHidden = !visible
                applied += 1
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(host)
        if applied > 0 {
            Breadcrumbs.log("wall62.homeTabs master=\(master ? 1 : 0) applied=\(applied)")
        }
    }

    /// 首页歌曲卡：开关开时墙面左上同款 TrackPill62 跟随当前曲。
    func refreshHomeTrackPill62() {
        guard SettingsStore.trackPillShowOnHome else {
            homeTrackPill62?.removeFromSuperview()
            homeTrackPill62 = nil
            return
        }
        if homeTrackPill62 == nil {
            let pill = TrackPill62()
            view.addSubview(pill)
            homeTrackPill62 = pill
        }
        homeTrackPill62?.noteTrackChanged(track: PlaybackEngine.shared.currentTrack)
        if let pill = homeTrackPill62 { pill.place(in: view) }
    }

    // MARK: 长按隐藏（歌单卡上下文菜单）

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        // 探段是曲目、无歌单可隐藏；歌/推段两形态（墙/网格）
        // 同一菜单。隐藏经 HiddenPlaylistsStore 落盘 + 通知回
        // applyWallData 即时生效。
        guard seamSegment != .explore else { return nil }
        let entryIndex: Int
        if collectionView === gridCollectionView {
            entryIndex = indexPath.item
        } else {
            guard indexPath.item < wallLayout.instances.count else { return nil }
            entryIndex = wallLayout.instances[indexPath.item].queueIndex
        }
        guard entryIndex < playlistIds.count, entryIndex < entries.count else { return nil }
        let playlistId = playlistIds[entryIndex]
        let title = entries[entryIndex].title
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let hide = UIAction(title: "隐藏歌单",
                                image: UIImage(systemName: "eye.slash"),
                                attributes: .destructive) { _ in
                HiddenPlaylistsStore.shared.hide(id: playlistId, name: title)
            }
            return UIMenu(children: [hide])
        }
    }

    // MARK: 过滤当前页

    func seamShowFilterBar() {
        guard let bar = seamFilterBar else { return }
        bar.isHidden = false
        bar.alpha = 0
        UIView.animate(withDuration: 0.25) { bar.alpha = 1 }
        seamFilterField?.becomeFirstResponder()
    }

    @objc func seamFilterTextChanged() {
        // 本地过滤：只收窄当前呈现集，不动数据源（applyWallData
        // 恒从原始全量/段缓存装配，清除即全量恢复）。
        seamFilterText = seamFilterField?.text ?? ""
        applyWallData()
    }

    @objc func seamFilterDone() {
        seamFilterField?.resignFirstResponder()
    }

    @objc func seamFilterClearTapped() {
        seamFilterField?.text = ""
        seamFilterText = ""
        applyWallData()
        seamFilterField?.resignFirstResponder()
        UIView.animate(withDuration: 0.25, animations: {
            self.seamFilterBar?.alpha = 0
        }, completion: { [weak self] _ in
            self?.seamFilterBar?.isHidden = true
            self?.seamFilterBar?.alpha = 1
        })
        Breadcrumbs.log("wall.menu.filter cleared")
    }

    // MARK: 沉浸模式（全屏钮的 iOS 平台差异替代、非等价）
    //
    // iOS 无窗口全屏概念：本钮落为沉浸模式——隐藏工具条与点
    // 播台 chrome、只留墙面，点任意处恢复。此为平台差异替代、
    // 与网页版全屏非等价，面包屑与报告均按此口径表述。

    func seamSetImmersive(_ on: Bool) {
        // 工具条全屏钮等一般路径入口：退出统一记 exit-other；
        // 点按退出走 seamImmersiveTap 的 exit-tap 分支。
        applySeamImmersive(on, traceEndReason: on ? nil : "exit-other")
    }

    private func applySeamImmersive(_ on: Bool, traceEndReason: String?) {
        let wasImmersive = seamImmersive
        seamImmersive = on
        Breadcrumbs.log("wall.seam.immersive on=\(on) platformSubstitute=1 nonEquivalent=1")
        // (60) 第 2 条：沉浸隐藏走工具条双态入口——整条与
        // grabber 横线同藏，退出沉浸回落收起态。
        seamToolbar?.setImmersiveHidden(on)
        seamFilterBar?.isHidden = true
        if on {
            // 提层（3.7 (61) 第 1.5 条，修沉浸假卡死结构缺陷）：
            // 原退出热区被 insertSubview 到工作台宿主之下，其上
            // 压着速记簿层与宠物层，落点到不了热区、沉浸退不出
            // 来。进入沉浸时：①存覆盖层原状态；②速记簿整层经
            // setExternallyCovered 藏起并穿透（把手/展开把手/
            // 热区一并不可命中）；③工作台宿主与宠物层关交互
            // （侧栏把手/悬浮头像等残留小件不可命中）；④退出
            // 热区 bringSubviewToFront 到全部覆盖层之上。退出
            // 时逐项恢复原层级与状态。
            if !wasImmersive {
                seamImmersiveSavedSketchbookCovered = sketchbookDrawer?.isExternallyCovered
                seamImmersiveSavedWorkbenchEnabled = workbenchHost?.isUserInteractionEnabled
                seamImmersiveSavedPetEnabled = miniPetStage?.isUserInteractionEnabled
            }
            if sketchbookDrawer?.isExternallyCovered == false {
                sketchbookDrawer?.setExternallyCovered(true)
            }
            workbenchHost?.isUserInteractionEnabled = false
            miniPetStage?.isUserInteractionEnabled = false
            seamImmersiveTapView?.isHidden = false
            if let tapView = seamImmersiveTapView {
                view.bringSubviewToFront(tapView)
            }
            Breadcrumbs.log("wall.seam.immersive zorder raised=1")
            rootCloseButton?.isHidden = true
            miniBar?.alpha = 0
            miniBar?.isUserInteractionEnabled = false
        } else {
            seamImmersiveTapView?.isHidden = true
            if wasImmersive {
                // 恢复原状态：速记簿原本就被外部（侧栏）covered
                // 时不代为解除，只恢复沉浸自己加的那层。
                if let savedCovered = seamImmersiveSavedSketchbookCovered, !savedCovered {
                    sketchbookDrawer?.setExternallyCovered(false)
                }
                if let savedWorkbench = seamImmersiveSavedWorkbenchEnabled {
                    workbenchHost?.isUserInteractionEnabled = savedWorkbench
                }
                if let savedPet = seamImmersiveSavedPetEnabled {
                    miniPetStage?.isUserInteractionEnabled = savedPet
                }
                seamImmersiveSavedSketchbookCovered = nil
                seamImmersiveSavedWorkbenchEnabled = nil
                seamImmersiveSavedPetEnabled = nil
                Breadcrumbs.log("wall.seam.immersive zorder restored=1")
            }
            rootCloseButton?.isHidden =
                (presentingViewController == nil && navigationController == nil)
            miniBar?.alpha = 1
            miniBar?.isUserInteractionEnabled = true
            if let traceEndReason {
                InteractionTrace.shared.endAction(traceEndReason)
                Breadcrumbs.log("wall.seam.trace endAction=\(traceEndReason)")
            }
        }
    }

    @objc func seamImmersiveTap(_ gesture: UITapGestureRecognizer) {
        guard seamImmersive, let tapView = seamImmersiveTapView else { return }
        // (61) 第 1.5 条 trace：退出点按落一行判读料——触点、
        // 命中链前三层（自顶向下含点图层类名）、热区帧。
        let point = gesture.location(in: view)
        InteractionTrace.shared.recordImmersiveTap(
            point: point,
            hitViewChain: seamHitViewChain(at: point),
            seamFrame: tapView.frame,
            seamHit: true)
        Breadcrumbs.log("wall.seam.immersive exit-via-tap")
        applySeamImmersive(false, traceEndReason: "exit-tap")
    }

    /// 命中链取样（供 InteractionTrace）：自顶向下扫本视图直
    /// 接子层，取前三个含点且可见的图层类名；扫不到时回退
    /// hitTest 命中视图类名。
    private func seamHitViewChain(at point: CGPoint) -> [String] {
        var chain: [String] = []
        for subview in view.subviews.reversed() {
            guard chain.count < 3 else { break }
            guard !subview.isHidden, subview.alpha > 0.01 else { continue }
            if subview.convert(subview.bounds, to: view).contains(point) {
                chain.append(String(describing: type(of: subview)))
            }
        }
        if chain.isEmpty, let hit = view.hitTest(point, with: nil) {
            chain.append(String(describing: type(of: hit)))
        }
        return chain
    }

    // MARK: 账户（双入口并存：与侧栏头像同一登录页/同一态）

    func seamAvatarTapped() {
        Breadcrumbs.log("wall.seam.avatar")
        // (62) WD §1：墙上头像改 popover 账户卡（头像/昵称/ID/
        // 登录态/平台丸/退出，见 AccountCard62），不再整页
        // present 登录页；卡内登录走压墙弹层（pageSheet）。
        // 侧栏深处入口保持整页 LoginViewController 不变。
        let card = AccountCard62ViewController()
        card.modalPresentationStyle = .popover
        card.onLoginSuccess = { [weak self] in
            guard let self else { return }
            self.wallNotLoggedIn = false
            self.loadAttempts = 0
            self.loadEntries()
            self.seamRefreshAccount()
        }
        card.onSessionChanged = { [weak self] in self?.seamRefreshAccount() }
        if let pop = card.popoverPresentationController {
            pop.sourceView = seamToolbar ?? view
            pop.sourceRect = CGRect(
                x: (seamToolbar?.bounds.width ?? view.bounds.width) - 44,
                y: 0, width: 44, height: 44)
            pop.permittedArrowDirections = [.up]
        }
        present(card, animated: true)
    }

    /// (62) 追加三：歌单页同款导航台的初始态读口（当前段 +
    /// 布局模式），歌单墙/歌单详情装配工具条时同步用。
    var seamToolbarInitialState: (segment: SeamSegment, grid: Bool) {
        (seamSegment, seamGridMode)
    }

    func seamRefreshAccount() {
        // 同步缓存先行（3.7 (61) 第 1.4 条）：头像 URL 与昵称同
        // 源——ProviderSessionStatusQuery 同步缓存里当前登录平
        // 台的 profile（取数口径与工作台侧栏 refreshAccountUI
        // 一致：第一家已登录且有头像者优先）。先用缓存把工具
        // 条头像刷出来，不等 fetchLoginStatus 网络回程。
        let statuses = ProviderSessionStatusQuery.allStatuses()
        let loggedInStatuses = statuses.filter(\.isLoggedIn)
        let avatarStatus = loggedInStatuses.first { $0.avatarURL != nil }
            ?? statuses.first { $0.avatarURL != nil }
        let avatarURLString = avatarStatus?.avatarURL?.absoluteString
        let syncNickname = loggedInStatuses.first?.displayName
        let syncLoggedIn = !loggedInStatuses.isEmpty
        seamToolbar?.setAccount(
            nickname: syncNickname,
            loggedIn: syncLoggedIn,
            avatarURLString: avatarURLString)
        Breadcrumbs.log("wall.seam.account sync loggedIn=\(syncLoggedIn) avatar=\(avatarURLString != nil ? 1 : 0)")
        Task { [weak self] in
            guard let self else { return }
            let status = try? await NativeDataClient.shared.fetchLoginStatus()
            await MainActor.run {
                // (62) 尾波第 3 组：fetchLoginStatus 自 (61) 起带
                // avatarURL——网络值优先于同步缓存落工具条，并
                // 回填资料缓存（旧注释口径停在 (61) 前、原样回
                // 传缓存值，网络头像永远用不上、存量缓存的头像
                // 键永不回填）。失败时保留已刷的同步缓存值，不
                // 回退成未登录占位。
                guard let status else { return }
                let effectiveAvatar = status.avatarURL ?? avatarURLString
                if status.loggedIn {
                    NativeSessionStore.shared.saveProfile(
                        provider: .netease, accountId: status.userId,
                        displayName: status.nickname,
                        avatarURLString: status.avatarURL)
                }
                self.seamToolbar?.setAccount(
                    nickname: status.nickname ?? syncNickname,
                    loggedIn: status.loggedIn,
                    avatarURLString: effectiveAvatar)
                Breadcrumbs.log("wall.seam.account fetch loggedIn=\(status.loggedIn) avatar=\(effectiveAvatar != nil ? 1 : 0)")
            }
        }
    }

    // MARK: 「…」菜单五项

    func seamMoreTapped(anchor: UIView) {
        let hasQueue = PlaybackEngine.shared.currentTrack != nil
            || !QueueManager.shared.queue.isEmpty
        WallMoreMenu.present(
            from: self, anchor: anchor,
            hasQueue: hasQueue,
            filterActive: !seamFilterText.isEmpty,
            actions: WallMoreMenu.Actions(
                liked: { [weak self] in self?.seamOpenLikedPlaylist() },
                cloud: { [weak self] in
                    guard let self else { return }
                    let drive = CloudDriveViewController()
                    drive.modalPresentationStyle = .fullScreen
                    self.present(drive, animated: true)
                },
                filter: { [weak self] in self?.seamShowFilterBar() },
                manageHidden: { [weak self] in
                    guard let self else { return }
                    let manage = HiddenPlaylistsViewController()
                    manage.modalPresentationStyle = .fullScreen
                    self.present(manage, animated: true)
                },
                backToStage: { [weak self] in self?.openNativeStageFromHome() }))
    }

    /// 喜欢的音乐：原始全量里 specialType=5 的那张（与工作台
    /// 歌单列表同一判据），走既有歌单曲目墙通路；未登录/无此
    /// 歌单时诚实提示，不造假入口。
    private func seamOpenLikedPlaylist() {
        guard let liked = seamRawPlaylists.first(where: { $0.isLikedCollection }) else {
            Breadcrumbs.log("wall.menu.liked missing")
            let alert = UIAlertController(
                title: "未找到「我喜欢的音乐」",
                message: "可能尚未登录网易云，或歌单还没加载完成。",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }
        Breadcrumbs.log("wall.menu.liked id=\(liked.id)")
        seamPresentPlaylistWall(id: liked.id, title: liked.name, coverUrl: liked.coverUrl)
    }

    /// 歌单曲目墙呈现（与点卡同路：预加载 + 同族转场）。
    private func seamPresentPlaylistWall(id: String, title: String, coverUrl: String?) {
        let wall = WallPrototypeViewController(
            playlistId: id, title: title, coverUrl: coverUrl)
        wall.modalPresentationStyle = .fullScreen
        wall.modalTransitionStyle = .crossDissolve
        beginPosterTransition(source: "menu", playlistId: id)
        wall.startPreload()
        Task { [weak self] in
            guard let self else { return }
            let seed = await wall.awaitSeed(timeout: 0.25)
            self.present(wall, animated: true) { [weak self] in
                self?.endPosterTransition(source: "menu", seedReady: seed)
            }
        }
    }

    // MARK: 点播台面板通知（任务三）
    //
    // 工作流 C 的顶排面板/命令键 post .foliaMiniBarPanel /
    // .foliaMiniBarCommand（object 为发出信号的 quick row 本
    // 身），本墙订阅后 present 工作流 D 的面板（类名定死）。
    // 字幕键与字幕面板已随 (60) 第 11 条整组删除。已有面板在
    // 呈时不叠开。

    @objc func miniBarPanelPanel() {
        seamPresentPanel(PlaybackPanelViewController(initialTab: .cover), kind: "panel")
    }

    @objc func miniBarPanelCommand() {
        // (62) C2 做真：命令面板改走 CommandPaletteViewController
        // .present 注入跨面回调（此前裸 present、两回调恒 nil，
        // 「打开队列/选择可视化」点了无落点）。队列 → 本墙呈现
        // PlaybackPanel 队列页签；样式 → 墙面无自有选样式通路，
        // 开原生舞台走舞台内同一选择器通路（面包屑留痕）。
        guard view.window != nil, presentedViewController == nil else {
            Breadcrumbs.log("wall.menu.panel skipped kind=command busy=1")
            return
        }
        Breadcrumbs.log("wall.menu.panel present kind=command62")
        CommandPaletteViewController.present(from: self) { [weak self] palette in
            palette.onOpenQueuePanel = { [weak self] in
                guard let self, self.presentedViewController == nil else { return }
                PlaybackPanelViewController.present(from: self, initialTab: .queue)
            }
            palette.onOpenStylePicker = { [weak self] in
                Breadcrumbs.log("wall62.command stylePicker viaStage=1")
                self?.openNativeStageFromHome()
            }
        }
    }

    private func seamPresentPanel(_ panel: UIViewController, kind: String) {
        guard view.window != nil, presentedViewController == nil else {
            Breadcrumbs.log("wall.menu.panel skipped kind=\(kind) busy=1")
            return
        }
        Breadcrumbs.log("wall.menu.panel present kind=\(kind)")
        panel.modalPresentationStyle = .pageSheet
        present(panel, animated: true)
    }
}
