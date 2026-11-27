import Combine
import SwiftUI
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
    /// (83) 黑屏定案②：方向预取节流戳（滚动回调内 ≥0.3s
    /// 或实例集身份变化才再喂 prefetch82）。
    private var lastPrefetch83: TimeInterval = 0
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
    /// (84) 第 3 条：台身手势背景层（按钮的兄弟层、非祖
    /// 先）——台身识别器只挂本层，见 buildMiniBar 装配。
    private var miniDeckSurface84: UIView?
    private var miniCover: UIImageView!
    private var miniTitle: UILabel!
    private var miniArtist: UILabel!
    private var miniPlayButton: UIButton!
    private var miniPrevButton: UIButton!
    private var miniNextButton: UIButton!
    /// (94) 94-3：台钮最终渲染自证去重键（"btn:glyph"）——
    /// 布局稳定后每字形状态只测一次，播/停切换换键重测；
    /// 不逐布局落行、不逐帧渲染（见 probeDeckRender94）。
    private var deckRenderProbed94 = Set<String>()
    /// (95) deck 探针守卫自证去重键（"pres,coll,win" 组
    /// 合）：守卫未命中时每会话每种组合只落一行 p95 deck
    /// guard，不逐布局落行（见 probeDeckRender94）。
    private var deckGuardLogged95 = Set<String>()
    /// (87) 主题四圆点（台面右上，样片 .tdots）：四套油画
    /// 主题点选切换；收起态随内容组淡出（见
    /// setMiniBarContentsAlpha）。
    // port90（任务 13）：主题四圆点已撤除（长按台面循环主题手势保留）。
    /// (82) 第 7/8 条：控制台入口圆钮（纯图标）＋双时间标
    /// 签。(84) 第 1 条：台面改回 (80) 版为底——台面只留
    /// 播放/上一曲/下一曲/控制台入口四钮；(83) 回台的模
    /// 式钮/列表钮再撤，职能由控制台承接（模式/随机/特
    /// 效/宠物/喜欢/日记本六钮与队列均在 ConsolePanel82）。
    private var miniConsoleButton: UIButton!
    private var miniTimeElapsed: UILabel!
    private var miniTimeDuration: UILabel!
    private var miniTrackTopC: NSLayoutConstraint?
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
    private var miniBarBottomC: NSLayoutConstraint?
    private var miniTrackBottomConstraint: NSLayoutConstraint?
    /// (74) 小横线形态的轨道约束组：展开态 leading/trailing/
    /// height 在场；收起态换 centerX+固定宽 134（见
    /// setMiniBarForm 的形态收口）。
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
    /// 点播台点按识别器组（3.7 (61) 第 7 条）：展开态单击（require
    /// 双击+长按失败）/展开态双击/收起态单击（无 require 链、即时
    /// 展开）三件分工，启停由 setMiniBarForm 按形态同步（见
    /// syncMiniBarTapRecognizers）；进度带即时 seek 走 seekHit 自带
    /// 识别器（miniSeekTapped），不进本组 require 链。
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
    /// (74) 工作台宿主已撤除（见 viewDidLoad 内留痕）：原书
    /// 库侧栏/工作台大台退役，入口全部由缝合工具条承接。
    /// 分区可见性映射（原侧栏行显隐的设置消费点）改存本表，
    /// 由「…」菜单建菜单时消费（applyHomeTabs62Visibility）。
    private var seamSectionVisibility62: [String: Bool] = [:]
    /// 日记本抽屉宿主（(53) D 组装、(54) N 组起持有）：侧栏
    /// 打开时经 setExternallyCovered 整层隐藏（照网页版
    /// is-covered），关栏恢复。
    private var sketchbookDrawer: SketchbookDrawerView?

    // 缝合工具条（3.7 (55) 工作流 E）：工具条视图 + 三段数据
    // + 网格形态 + 过滤 + 沉浸模式，全部状态在此，接线逻辑在
    // 文件尾 seam extension。原始歌单全量（未过滤）存
    // seamRawPlaylists，entries/playlistIds 恒为「当前段 +
    // 隐藏过滤 + 文字过滤」后的呈现集（applyWallData 唯一装配点）。
    private var seamToolbar: SeamToolbarView?
    /// (85) 第 1 条：主页世界缝（HomeSeam85View）＋侧边竖
    /// 标签＋开合补间。（84）左缘固定条 HomeSidebar84View
    /// 已整条撤除（Miller (84) 验收第 1 条：缝须是墙面世
    /// 界的一部分、随墙平移）。
    private var homeSeam85: HomeSeam85View?
    private var seamEdgeTab85: SeamEdgeTab85View?
    /// 缝首规划已完成（相机居中后按 seamPlan85 选界＋让位）。
    private var seamPlanned85 = false
    /// 缝开合/相机让位补间（0.36/0.42s，网页同量级）。
    private var seamTween85: CADisplayLink?
    private var seamTweenStart85: CFTimeInterval = 0
    private var seamTweenFromOrigin85: CGFloat = 0
    private var seamTweenToOrigin85: CGFloat = 0
    private var seamTweenFromWidth85: CGFloat = 0
    private var seamTweenToWidth85: CGFloat = 0
    private var seamTweenOrigin85 = false
    /// (89)B b-seam-present：缝侧展开面板（点页签＝缝右缘
    /// 展开 300 信息条＋列表面板、不离墙）＋其内嵌分区页
    /// （子 VC containment）与头条件。开时建、关时整组拆。
    private var seamPanel89: UIView?
    private var seamPanelTitle89: UILabel?
    private var seamPanelMeta89: UILabel?
    private var seamPanelContent89: UIView?
    private var seamPanelChild89: WorkbenchSectionViewController?
    private var seamPanelTab89: Int = -1
    /// (62) WD §1：墙后层（WallSurfaces62）。墙缝信息条
    /// StripSurface62 已于 (63) 第 4 条按 Miller 令整条摘除。
    private var wallBackdrop62: WallBackdrop62?
    private var seamToolbarTrailing: NSLayoutConstraint?
    /// (75) 工具条双向约束组（竖屏绕岛带／横屏安全区侧锚），
    /// applySeamBandOrientation 按当前朝向二选一激活。
    private var seamBandPortrait: [NSLayoutConstraint] = []
    private var seamBandLandscape: [NSLayoutConstraint] = []
    private var seamBandIsPortrait: Bool?
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
    /// (77) ⑦沉浸退出识别器：挂根视图、仅沉浸期启用、
    /// cancelsTouchesInView=false（点外穿透不吞触摸）。
    private var seamImmersiveExitRecognizer: UITapGestureRecognizer?
    /// 沉浸期被中和的覆盖层原状态（3.7 (61) 第 1.5 条）：进入沉浸
    /// 时存日记本 covered 态/工作台宿主/宠物层的交互开关，退出
    /// 时逐项恢复（原本就被侧栏 covered 的日记本不代为解除）。
    private var seamImmersiveSavedSketchbookCovered: Bool?
    private var seamImmersiveSavedPetEnabled: Bool?
    private var miniTheme: MiniPlayerTheme = MiniPlayerTheme.effective
    private var miniKnobSkin: UIView?
    /// (95) 第 7 条：胶囊台把手内嵌花图（DeckGlyph82.flowerImage
    /// 14pt 铺满 knob）；refreshMiniProgressChrome 只摘
    /// miniKnobSkin、不清 knob 子视图，本图恒在场（该函数尾
    /// 有防摘除重挂守卫）。
    private var miniKnobFlower95: UIImageView?
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

    /// (78) 第 7 条宠物登顶（Miller 00:31 拍板）：本页顶部
    /// 挂岛镜像宠物带——隐藏状态栏（系统时间），宠物占据
    /// 顶部带完整显示、不被时间压。安全区顶在刘海机型由
    /// 传感器 housing 决定、与状态栏显隐无关（恒 59pt），
    /// 锚安全区的既有布局不跳位；逐页复核见 (78) 报告。
    override var prefersStatusBarHidden: Bool { true }

    /// (79) 第 9 条：系统边缘手势延迟——岛宠框压顶缘、
    /// 收起宠坐底部 Home/后台手势区，(78) 判读两处失败
    /// 均呈「触摸被系统整手拿走」签名且全仓零处置。本页
    /// 顶/底缘手势先让 app 内拖动，系统下拉/回主屏改走
    /// 二段式（先露小把手再拉），与 Miller 拍板的宠物
    /// 登顶口径一致。
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.top, .bottom]
    }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

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
        // (82) 第 9 条：灯光状态/焦点变化——两面 collection
        // 都重刷可见砖（开灯走对角波浪、关灯即时压暗）。
        NotificationCenter.default.addObserver(
            self, selector: #selector(wallLightChanged82),
            name: .foliaWallLight82Changed, object: nil)

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
        // (82) 第 7 条：主排模式钮随旧台退役（模式职能进
        // 控制台），原 $playMode 回刷订阅一并撤除。
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

        // (74) 工作台宿主整层撤除：(73) 把设置台做成顶部整幅
        // 大台（真机图1 三家状态文字重叠、导播台与头像挤撞、
        // 整块黑板压墙）被 Miller 判方向错——设置台回归缝合
        // 工具条本体（头像/分段/搜索/齿轮/灯泡导播台/格子/
        // 「…」/全屏），账户/分区/设置/导览入口全部由工具条
        // 承接（分区歌单/电台/专辑/本地收进「…」菜单，见
        // seamMoreTapped）。原 onSidebarVisibilityChanged 的
        // 墙交互锁与日记本 covered 联动随侧栏形态一并退役。
        Breadcrumbs.log("workbench74 desk=removed carrier=seam")
        // (53) D 组日记本：左缘把手＋抽屉宿主
        // 成为墙面最上层子视图（其 hitTest 只认把手/抽屉、其余穿透，
        // 非模态不挡墙操作；宠物岛走 window.layer 独立层级、互不影响）。
        // (54) N 组起持有引用：侧栏开关经 onSidebarVisibilityChanged
        // 调 setExternallyCovered 整层隐藏/恢复（见上闭包）。
        sketchbookDrawer = SketchbookHost.install(into: view)
        // (85) 第 1 条：左上角小白线（日记本静息把手）撤
        // 除在装配点即落旗（(84) 只在侧栏装配处补设、依赖
        // 装配顺序；抽屉本体保留，控制台日记本钮仍可开）。
        sketchbookDrawer?.edgeHandleSuppressed84 = true
        // (53) L 组 chrome 收口留痕：提示条删除 + ✕ 关闭键 +
        // 齿轮/搜索并入侧栏，真机对账以此行确认新包在跑。
        Breadcrumbs.log("wall.chrome home hintBar=removed gearSearch=sidebar close=glass-x")

        // 缝合工具条安装（3.7 (55) 工作流 E、(60) 第 2 条改 z
        // 序）：装在工作台宿主与日记本之后，工具条本体插到速
        // 记簿宿主之上（见 installSeamChrome），日记本把手热
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
        var commands: [UIKeyCommand] = []
        if SettingsStore.posterWallSHotkeyEnabled {
            commands.append(UIKeyCommand(title: "命令面板", action: #selector(wb62OpenCommandPalette),
                                         input: "s", modifierFlags: []))
        }
        // (66) 自定义快捷键（customKeyLetter62/customKeyCommand62
        // 的消费者）：与 S 键同键时 S 优先（设置行已声明）。
        let letter = SettingsStore.customKeyLetter62.lowercased()
        if letter.count == 1, letter != "s" {
            commands.append(UIKeyCommand(title: "自定义命令", action: #selector(wb66CustomKey),
                                         input: letter, modifierFlags: []))
        }
        return commands.isEmpty ? nil : commands
    }

    @objc private func wb62OpenCommandPalette() {
        Breadcrumbs.log("shortcuts62.sKey host=homewall")
        miniBarPanelCommand()
    }

    /// (66) 自定义字母键：执行 customKeyCommand62 所绑命令
    /// （目录 PinnedCommands62.customKeyCatalog66，id 与命
    /// 令面板注册表同源；每条走墙面既有呈现通路）。
    @objc private func wb66CustomKey() {
        let command = SettingsStore.customKeyCommand62
        Breadcrumbs.log("shortcuts66.custom key=1 cmd=\(command)")
        guard presentedViewController == nil else { return }
        switch command {
        case "panel.open":
            PlaybackPanelViewController.present(from: self, initialTab: .cover)
        case "nav.search":
            // 与主页墙放大镜同落点（SearchHostPresenter 统一呈现）。
            SearchHostPresenter.presentSearch(from: self)
        case "nav.settings":
            let settings = SettingsViewController()
            settings.modalPresentationStyle = .overFullScreen
            present(settings, animated: true)
        case "nav.local":
            let local = WorkbenchLocalViewController()
            local.modalPresentationStyle = .fullScreen
            present(local, animated: true)
        case "nav.explore":
            let browse = UIHostingController(rootView: NativeBrowseView())
            browse.modalPresentationStyle = .fullScreen
            present(browse, animated: true)
        case "dir.rescanLocal":
            LocalLibrary62.shared.rescanFolders()
        case "dir.precache":
            Task { _ = await MediaCache62.shared.precacheQueue() }
        case "theme.park":
            ThemeParkViewController.present(from: self)
        case "dafeiyu.open":
            DafeiyuPanel62ViewController.present(from: self)
        case "panel.posterwall":
            LivePosterWall62ViewController.present(from: self)
        case "lyric.checkin":
            Task { _ = await Scrobble62.shared.performCheckIn() }
        default:
            miniBarPanelCommand()
        }
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // (93) C3：版式单一状态回显——歌单页缝胶囊可能已
        // 改 foliaPlaylistLayout91，主页缝开关出现时重读
        // 回刷（此前主页缝无此重读、两页会脱同步）。
        if let seam = homeSeam85 {
            let mode93 = UserDefaults.standard.integer(
                forKey: "foliaPlaylistLayout91")
            if seam.layoutMode92 != mode93 { seam.layoutMode92 = mode93 }
        }
        // (72) 单宿主认领：本页在前时迷你台形态归本宿主；
        // 形态与共享旗标不一致时无动画对齐一次（交接不跳变）。
        MiniBarSingleHost.shared.claim("homewall")
        if miniBarPresented,
           miniBarCollapsed != MiniBarSingleHost.shared.sharedCollapsed {
            let target = MiniBarSingleHost.shared.sharedCollapsed
            miniBarCollapsed = target
            miniPetStage?.barFormChanged(collapsed: target)
            setMiniBarForm(collapsed: target)
            setMiniBarContentsAlpha(target ? 0 : 1)
            setMiniBarContentsInteractive(!target)
        }
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
        // (75) 首启定向兜底（横屏冷启时 install 的屏幕猜测可
        // 能与实际 bounds 不符）：按真实 bounds 校正一次；
        // 另：绕岛带全宽覆顶后，✕ 容器须在带之上（展开态
        // 不被毛玻璃盖住），提回最前（隐藏时为空操作）。
        applySeamBandOrientation(portrait: view.bounds.width < view.bounds.height)
        if let chrome = rootCloseButton { view.bringSubviewToFront(chrome) }
        seamRefreshAccount()
        // (62) 每次露面重读资料库界面选择（设置页改动后回墙生效，
        // 与工具条布局钮同状态源）＋侧栏分区显隐。
        let wantGrid = SettingsStore.librarySuiteChoice == 1
        if wantGrid != seamGridMode { seamToggleLayout() }
        applyHomeTabs62Visibility()
        refreshHomeTrackPill62()
        Breadcrumbs.log("wall.appear kind=home")
        Breadcrumbs.log("home appear")
        // (82) 第 4 条：岛中央簇强制重发（页态=home）。
        PetIslandLayer.shared.forceResendCenter82(page: "home")
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
            // (72)：入场落定 = 灵动岛 bootstrap 的首发稳定
            // 事件（油画期间不落座、防浮在入场画面上抢戏）。
            PetHomeRegistry.shared.reconcileIsland(reason: "intro")
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
        // (72) 单宿主让位。
        MiniBarSingleHost.shared.release("homewall")
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
    /// 已达成动画期间零重算、风险更低。
    /// (73) 时序再改：收尾从 completion 提前到 alongside 首
    /// 帧（见下 alongside 注）——冻结只保留「动画期间不被中
    /// 间 bounds 反复触发重算」一职，实际重排在转场第一帧
    /// 就以最终 bounds 完成，消除落定 snap。
    override func viewWillTransition(to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard viewIfLoaded != nil, collectionView != nil else { return }
        let fromSize = view.bounds.size
        guard size != fromSize else { return }
        wallRotationGeneration += 1
        let generation = wallRotationGeneration
        wallLayout.setRotationFrozen(true)
        // (73) 岛层守护转场期暂停：旋转动画中途不许整层
        // reseatAll 抢主线程（落定 completion 里恢复并补拍）。
        PetIslandLayer.setRefrontSuspended(true)
        Breadcrumbs.log("wall.rotate freeze gen=\(generation)"
            + " from=\(Int(fromSize.width))x\(Int(fromSize.height))"
            + " to=\(Int(size.width))x\(Int(size.height))")
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            // (75) 工具条朝向组随转场首帧切换（与墙重排同拍，
            // 绕岛带/侧锚在旋转全程刚性跟随、不落单帧旧形态）。
            self.applySeamBandOrientation(portrait: size.width < size.height)
            // (73) 墙体重排提前到转场首帧（alongside 在动画
            // 开始时以最终 bounds 执行）：(72) 前收尾全压在
            // completion——旋转变换已播完、冻结的旧布局还多
            // 停一帧，随后一次性换新布局＋reload，呈现为
            // 「闪一下（旧帧）然后再放大（新帧 snap）」。改
            // 为首帧即以最终 bounds 解冻重排：转场全程呈现
            // 的就是最终布局随窗口刚性旋转，落定帧与前一帧
            // 逐位一致、无尺度跳变。重排仍只此一次：纯旋转
            // 尺寸类别不变、走同键平移路，零 lattice 重算；
            // 中途反向再转时新一代 freeze 重新冻结、由新一
            // 代 alongside 收尾，旧代在此落空不解冻。
            guard generation == self.wallRotationGeneration else { return }
            self.wallLayout.setRotationFrozen(false)
            self.wallLayout.invalidateLayout()
            // (58)：prepare 若因类别变化换了实例集，数据源须
            // 同步 reload（旧版靠后续事件兜底、映射错位窗口
            // 存在）；身份未变则不动。
            if self.wallLayout.lastIdentityChanged {
                self.collectionView.reloadData()
            }
        }) { [weak self] _ in
            guard let self else { return }
            // (73) 岛层守护恢复＋即时补一拍：转场期间跳过的
            // 几何同步在此落定帧后一次补齐（不在动画中途）。
            PetIslandLayer.setRefrontSuspended(false)
            PetIslandLayer.shared.refrontIfNeeded()
            // 中途反向再转：旧代 completion 只记账，新一代
            // 才是收尾点。
            guard generation == self.wallRotationGeneration else {
                Breadcrumbs.log("wall.rotate superseded gen=\(generation)")
                return
            }
            // ② 迷你台/点播台：宽度按新 bounds 重断言（口径与
            //    viewDidLayoutSubviews 同：min(宽,高)−24，纯旋
            //    转时值不变、横竖屏同宽居中）；台身 centerX/
            //    bottom 安全区锚点由 AutoLayout 随新 bounds 自
            //    动落位，无手动帧。
            if let constraint = self.miniBarWidthConstraint {
                constraint.constant = min(size.width, size.height) - 24
            }
            // (86) 第 5 条：收起轨宽按新朝向重写（同点收尾）。
            self.refreshTrackWidth86(portrait: size.width < size.height)
            // ③ 贴纸层：dock/失败/缓冲贴纸是手动帧（缓冲贴纸
            //    依赖迷你台 frame），按新 bounds 重定位一次。
            self.stickerLayoutOverlays()
            // ④ 网格形态：flow 布局按新 bounds 失效一次（与墙
            //    本体同收尾点；网格隐藏时无可见代价）。
            self.gridCollectionView?.collectionViewLayout.invalidateLayout()
            // 其余宿主元素审计结论（不需手动重排）：工作台浮
            // 层/缝合工具条/日记本/✕ 关闭键均为 AutoLayout 钉
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
        // (66) 记住墙面位置消费：开时以落盘的 worldOrigin 为
        // 初始相机（wallCamera62，CGPoint? 口径），关时默认居中。
        if SettingsStore.rememberCardPositions,
           let saved = SettingsStore.wallCamera62 {
            wallLayout.worldOrigin = saved
            Breadcrumbs.log("wall66.camera restored=1")
        }
        let cell = wallLayout.cellViewSize
        collectionView.contentOffset = CGPoint(x: cell.width, y: cell.height)
        wallLayout.invalidateLayout()
    }

    private var wallCameraSaveWork66: DispatchWorkItem?

    /// (66) 相机/网格偏移落盘（滚动去抖 0.6s 合并写，避免逐
    /// 事件写盘）；仅「记住墙面位置」开时写。
    private func scheduleWallPositionSave66() {
        guard SettingsStore.rememberCardPositions else { return }
        wallCameraSaveWork66?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            SettingsStore.wallCamera62 = self.wallLayout.worldOrigin
            if let grid = self.gridCollectionView, self.seamGridMode {
                SettingsStore.wallScrollOriginY = Double(grid.contentOffset.y)
            }
        }
        wallCameraSaveWork66 = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
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
        // (85) 第 1 条：缝首规划（相机居中后）＋逐布局落位。
        updateSeam85Frame()
        // (94) 94-3：布局收口后做台钮最终渲染自证（内部去
        // 重：每字形状态只测一次，非逐布局开销）。
        probeDeckRender94()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // (66) 网格形态滚动：只记网格偏移落盘（记住位置开时）。
        if scrollView === gridCollectionView {
            scheduleWallPositionSave66()
            return
        }
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
        // (83) 黑屏定案②：按滚动方向预取下一屏封面——
        // prefetch82 本版真接线（(82) 零调用假交付的纠
        // 正）；实例集身份变化即喂、否则 0.3s 节流。
        let now83 = CACurrentMediaTime()
        if identityChanged || now83 - lastPrefetch83 >= 0.3 {
            lastPrefetch83 = now83
            prefetchWall83(dirX: delta.x > 0 ? 1 : (delta.x < 0 ? -1 : 0),
                            dirY: delta.y > 0 ? 1 : (delta.y < 0 ? -1 : 0),
                            source: "scroll")
        }
        // (66) 相机位置落盘（记住位置开时，去抖合并写）。
        scheduleWallPositionSave66()
        // (85) 第 1 条：缝随相机同帧落位（帧换算在 WallLayout）。
        updateSeam85Frame()
    }

    /// (83) 黑屏定案②③：方向预取／入墙预热共用——以相
    /// 机世界视口为心，运动方向侧扩一屏、余侧扩 0.35
    /// 屏，取实例环内条目封面（queueIndex 去重）按 cell
    /// 同式 tier 喂 prefetch82（.prefetch 低优先级、跳
    /// 过已缓存，计数落 pf83）。dir=(0,0) 即入墙预热：
    /// 当前列表在场实例整环批量入缓存。
    private func prefetchWall83(dirX: Int, dirY: Int, source: String) {
        guard !entries.isEmpty, wallLayout.cameraScale > 0 else { return }
        let viewSize = collectionView.bounds.size.width > 0
            ? collectionView.bounds.size : view.bounds.size
        guard viewSize.width > 0 else { return }
        let vw = Double(viewSize.width) / wallLayout.cameraScale
        let vh = Double(viewSize.height) / wallLayout.cameraScale
        var minX = Double(wallLayout.worldOrigin.x)
        var minY = Double(wallLayout.worldOrigin.y)
        var maxX = minX + vw
        var maxY = minY + vh
        minX -= dirX < 0 ? vw : vw * 0.35
        maxX += dirX > 0 ? vw : vw * 0.35
        minY -= dirY < 0 ? vh : vh * 0.35
        maxY += dirY > 0 ? vh : vh * 0.35
        var seen = Set<Int>()
        var items: [(raw: String, tier: Int, dist: Double)] = []
        // (86) 第 8 条：喂入前按实例中心到视口中心距离升
        // 序——准入上限截断时先丢最远环（旧顺序由实例集
        // 顺序定、与滚动方向无关，近环反而可能被远环挤
        // 掉额度）。
        let centerX = Double(wallLayout.worldOrigin.x) + vw / 2
        let centerY = Double(wallLayout.worldOrigin.y) + vh / 2
        for inst in wallLayout.instances {
            guard inst.queueIndex < entries.count,
                  seen.insert(inst.queueIndex).inserted else { continue }
            let r = inst.rect
            guard r.x + r.width >= minX, r.x <= maxX,
                  r.y + r.height >= minY, r.y <= maxY else { continue }
            guard let pic = entries[inst.queueIndex].picUrl else { continue }
            // (84) 修 a：像素量单源（wallPixelExtent 唯一
            // 出处，与 cell 配置侧同式同键）。
            let pixelExtent = NativeCoverLoader.wallPixelExtent(
                worldExtent: max(r.width, r.height),
                cameraScale: Double(wallLayout.cameraScale))
            let dx = r.x + r.width / 2 - centerX
            let dy = r.y + r.height / 2 - centerY
            items.append((pic, NativeCoverLoader.wallTier(
                raw: pic, pixelExtent: pixelExtent), dx * dx + dy * dy))
        }
        guard !items.isEmpty else { return }
        items.sort { $0.dist < $1.dist }
        NativeCoverLoader.shared.prefetch82(
            items.map { (raw: $0.raw, tier: $0.tier) },
            source: source, wall: "home")
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
            // (84) 修 a：单源（网格无相机：世界边长＝帧边长、cameraScale=1）。
            let pixelExtent = NativeCoverLoader.wallPixelExtent(
                worldExtent: Double(max(frame.width, frame.height)), cameraScale: 1)
            let tier = entry.picUrl.map { NativeCoverLoader.wallTier(raw: $0, pixelExtent: pixelExtent) }
                ?? NativeCoverLoader.tier(forPixelExtent: pixelExtent)
            cell.configure(entry: entry, tier: tier, wall: "home")
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
        // (84) 修 a：配置侧改用实例世界 rect 走单源式（与
        // 预取侧同一表达式、同一缓存键；旧式用布局帧边长，
        // 帧经取整/变换后与世界式可分叉、预取暖错键）。
        let pixelExtent = NativeCoverLoader.wallPixelExtent(
            worldExtent: Double(max(instance.rect.width, instance.rect.height)),
            cameraScale: Double(wallLayout.cameraScale))
        let tier = entry.picUrl.map { NativeCoverLoader.wallTier(raw: $0, pixelExtent: pixelExtent) }
            ?? NativeCoverLoader.tier(forPixelExtent: pixelExtent)
        cell.configure(entry: entry, tier: tier, wall: "home")
        cell.playEntranceIfNeeded(key: entry.id)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        prefetchItemsAt indexPaths: [IndexPath]) {
        if collectionView === gridCollectionView {
            for indexPath in indexPaths {
                guard indexPath.item < entries.count,
                      let pic = entries[indexPath.item].picUrl else { continue }
                // (82) 第 1 条：预取 tier 必须与 cell 配置时
                // 同式计算——旧固定 360 与砖的 wallTier 不
                // 同键、暖的全是别的档，是命中率约 2% 的一
                // 条实根（预取暖错档、砖到场仍 miss）。
                let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
                // (84) 修 a：单源（网格 cameraScale=1）。
                let pixelExtent = NativeCoverLoader.wallPixelExtent(
                    worldExtent: Double(max(frame.width, frame.height)), cameraScale: 1)
                let tier = NativeCoverLoader.wallTier(raw: pic, pixelExtent: pixelExtent)
                guard let urlString = NativeCoverLoader.shared.proxiedURLString(pic, tier: tier)
                else { continue }
                if NativeCoverLoader.shared.cachedImage(for: urlString) != nil { continue }
                // (78) 第 6 条：预取必须走低优先级（wallproto
                // (72) 已落、本宿主漏）——默认 .visible 会让过期
                // 预取占满 4 个取图槽、真可见 cell 在后面干等，
                // 是快滑整墙占位的可疑堵点之一。
                Task { _ = await NativeCoverLoader.shared.image(for: urlString, tier: tier, priority: .prefetch) }
            }
            return
        }
        for indexPath in indexPaths {
            guard indexPath.item < wallLayout.instances.count else { continue }
            let instance = wallLayout.instances[indexPath.item]
            guard instance.queueIndex < entries.count else { continue }
            let entry = entries[instance.queueIndex]
            guard let pic = entry.picUrl else { continue }
            // (84) 修 a：单源（实例世界 rect，与配置侧同式）。
            let pixelExtent = NativeCoverLoader.wallPixelExtent(
                worldExtent: Double(max(instance.rect.width, instance.rect.height)),
                cameraScale: Double(wallLayout.cameraScale))
            let tier = NativeCoverLoader.wallTier(raw: pic, pixelExtent: pixelExtent)
            guard let urlString = NativeCoverLoader.shared.proxiedURLString(pic, tier: tier) else { continue }
            if NativeCoverLoader.shared.cachedImage(for: urlString) != nil { continue }
            // (78) 第 6 条：同上，预取走 .prefetch 低优先级。
            Task { _ = await NativeCoverLoader.shared.image(for: urlString, tier: tier, priority: .prefetch) }
        }
    }

    /// (96) B-4：点开歌单的种子等待窗——tap 处 startPreload 已
    /// 在跑 loadEntries（3.7 (8) 既有预热，本常量只决定 present
    /// 前等种子多久）：0.55s hero 弹簧落位同段掩盖，窗内种子落
    /// 袋时背板 dismiss-before-present、拍立得根本不露面（见
    /// LoadingBackdropView.begin 的 dismissed 门）；窗外仍照常
    /// present、拍立得只作真正加载态。0.55s 弹簧落位本身不动；
    /// 到墙总时长仍由取数决定，本窗只缩短拍立得中间态、不承诺
    /// 更快进墙。旧 0.25s 窗使跳过路径几乎永不可达（取数 4–9s
    /// 实测，见 loadEntries 页大小注释），故放宽到 0.75s。
    private let playlistSeedWait96: TimeInterval = 0.75

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
        // (82) 第 9 条：关灯态首点只点亮该砖（消费本次点
        // 按＋粒子环/拖尾），已亮砖再点才走原动作。
        let lightQueueIndex = collectionView === gridCollectionView
            ? indexPath.item : wallLayout.instances[indexPath.item].queueIndex
        if lightQueueIndex < entries.count {
            let entryId = entries[lightQueueIndex].id
            let previous = WallLight82.focusedId(wall: "home")
            if WallLight82.consumeTapIfNeeded(wall: "home", entryId: entryId) {
                WallLight82.playFocusTap(in: collectionView,
                                         entryId: entryId, previousFocus: previous)
                return
            }
        }
        // 网格形态（(55) E）：索引即条目序，与墙面点卡同路。
        if collectionView === gridCollectionView {
            seamOpenEntry(at: indexPath.item)
            return
        }
        let instance = wallLayout.instances[indexPath.item]
        seamOpenEntry(at: instance.queueIndex)
    }

    /// (82) 第 8 条：控制台日记本钮——切换本墙日记本抽屉
    /// （抽屉本体只装在本墙，控制台经此钩子调用）。
    func toggleSketchbook82() {
        guard let drawer = sketchbookDrawer else { return }
        drawer.setOpen(!drawer.isOpen, source: "console82")
    }

    /// (82) 第 9 条：灯光广播收口——开灯对角波浪点亮、
    /// 关灯即时压暗，两面 collection 同步。
    @objc private func wallLightChanged82() {
        let wave = WallLight82.isOn
        WallLight82.applyToVisibleCells(in: collectionView, wave: wave)
        if let grid = gridCollectionView {
            WallLight82.applyToVisibleCells(in: grid, wave: wave)
        }
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
        // 丝滑切入（3.7 (8)）：先预加载，等种子最多一个
        // playlistSeedWait96 窗（(96) B-4：0.75s，与 0.55s hero
        // 弹簧同段掩盖）再 present——窗内落袋时墙带着内容直接
        // 切入、拍立得不露面；超时照常切入，由墙内氛围底兜住
        // 剩余等待。
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
            let seed = await wall.awaitSeed(timeout: playlistSeedWait96)
            self.present(wall, animated: true) { [weak self] in
                self?.endPosterTransition(source: "tap", seedReady: seed)
            }
        }
    }

    // MARK: - 底部播放台（13.4 #4：与曲目墙同款 E 液态玻璃）

    private func buildMiniBar() {
        let bar = MiniBarHitView()
        bar.backgroundColor = .clear
        // (95) 第 1 条：胶囊台高 62、bar 圆角取半高 31。
        bar.layer.cornerRadius = 31
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOpacity = 0.25
        bar.layer.shadowRadius = 20
        bar.layer.shadowOffset = CGSize(width: 0, height: 8)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        view.addSubview(bar)
        miniBar = bar
        // (75) 点按到达自证（第 5 项②）：触摸真落到台身即
        // 落一行，与 minibar.hit 对位分环（见 MiniBarHitView）。
        bar.onHitLanded = { [weak self, weak bar] in
            guard let self, let bar else { return }
            Breadcrumbs.log("minibar.touch75 host=homewall"
                + " col=\(self.miniBarCollapsed ? 1 : 0)"
                + " h=\(Int(bar.bounds.height))")
        }
        // (77) ⑥：派发段见证补齐三宿主同构（(76) 只接了
        // wallproto）＋认领/救援接线（claim77 在
        // MiniBarHitView 内落、救援 disp77 via=rescue）。
        bar.onDispatchCancelled = { [weak self] in
            guard let self else { return }
            Breadcrumbs.log("minibar.dead76 host=homewall at=cancel"
                + " recog=\(self.miniTapBits())")
        }
        bar.onDispatchUnclaimed = { [weak self] in
            guard let self, self.miniBarCollapsed else { return }
            Breadcrumbs.log("minibar.dead76 host=homewall at=noRecog"
                + " recog=\(self.miniTapBits())")
        }
        bar.crumbHostTag = "homewall"
        bar.onCancelledTapRescue = { [weak self] in
            guard let self, self.miniBarCollapsed else { return }
            Breadcrumbs.log("minibar.disp77 host=homewall via=rescue")
            self.expandMiniBar()
        }
        // (86) 第 9 条：静止点兜底接线（tap86 out=stat86 →
        // 同路展开；expandMiniBar 有形态守卫、与识别器/根
        // 认领重复触发不双开）。
        bar.onStationaryTap86 = { [weak self] in
            guard let self, self.miniBarCollapsed else { return }
            Breadcrumbs.log("minibar.disp86 host=homewall via=stat86")
            self.expandMiniBar()
        }
        let petStage = MiniBarPetStage(bar: bar)
        view.addSubview(petStage)
        miniPetStage = petStage
        // (78) 第 8 条：根级认领——细条点按展开改由根视图识
        // 别器按几何认领（mb.claim78→mb.disp78→expand），
        // 不再只靠台身派发段（(77) 定案整段静默）。
        miniBarRootTap78 = MiniBarRootTap78(
            hostView: view, bar: bar, petStage: petStage,
            hostTag: "homewall",
            isCollapsed: { [weak self] in self?.miniBarCollapsed ?? false },
            expand: { [weak self] in self?.expandMiniBar() })
        // (70) B2：点播台 4s 长按开启宠物手势整套已撤（与切
        // 主题长按同域打架、圆圈干扰操作，Miller 改令）——
        // 台上不再挂任何宠物相关识别器；宠物开关改全局右
        // 下角召唤钮（PetSummonButton70）＋设置开关，关闭
        // 另有长按宠物本体一路。

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.layer.cornerRadius = 31
        blur.layer.borderWidth = 1
        blur.layer.borderColor = UIColor.white.withAlphaComponent(0.30).cgColor
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        // (84) 第 3 条命中结构修法（DS 定案）：毛玻璃只作
        // 视觉、禁交互——台身识别器改挂其下的背景手势层
        // （deckSurface84），按钮不再是任何台身识别器的后
        // 代，祖先链豁免整套退役（见构建尾识别器装配）。
        blur.isUserInteractionEnabled = false
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
        // (84) 第 3 条：台身手势背景层——台身全部识别器
        // （单击/双击/长按/兜底/收起单击）只挂本层；本层是
        // 按钮的**兄弟层**（在按钮之下、非其祖先），按钮触
        // 摸永不进台身识别器链。空白区触摸经毛玻璃（禁交
        // 互）/主题层（恒禁交互）落到本层。
        let deckSurface84 = UIView()
        deckSurface84.backgroundColor = .clear
        deckSurface84.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(deckSurface84)
        miniDeckSurface84 = deckSurface84
        NSLayoutConstraint.activate([
            deckSurface84.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            deckSurface84.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            deckSurface84.topAnchor.constraint(equalTo: bar.topAnchor),
            deckSurface84.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        let themeLayer = MiniPlayerThemeLayer()
        themeLayer.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(themeLayer)
        miniThemeLayer = themeLayer
        // (84) 第 1 条：主题底复原——(82) E 毛玻璃把主题油
        // 画层恒隐藏，Miller 令改回 (80) 版台，主题层重新
        // 在场（收起态由 setMiniBarForm 按形态隐藏，与
        // (80) 同规）。
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
        glassTint.layer.cornerRadius = 31
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
        // (84) 第 3 条：轨道纯视觉禁交互（seek 触摸由上方
        // seekHit 命中带承接），免其截走落向背景层的触摸。
        progressTrack.isUserInteractionEnabled = false
        bar.addSubview(progressTrack)
        miniProgressTrack = progressTrack
        let fill = UIView()
        fill.backgroundColor = .white
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressTrack.addSubview(fill)
        miniProgressFill = fill

        let knob = UIView()
        // (84) 第 1 条：把手复原 (80) 形态——9pt 白色发光
        // 圆点＋主题皮肤叠层（refreshMiniProgressChrome 按
        // (80) 同规重挂皮肤/发光）；(82) 花朵图随 E 台退役。
        knob.backgroundColor = .white
        // (95) 第 7 条：把手 9→14、圆角 4.5→7，内嵌花图铺满。
        knob.layer.cornerRadius = 7
        knob.layer.shadowColor = UIColor.white.cgColor
        knob.layer.shadowOpacity = 0.9
        knob.layer.shadowRadius = 4
        knob.layer.shadowOffset = .zero
        knob.isUserInteractionEnabled = false
        knob.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(knob)
        miniProgressKnob = knob
        let knobFlower95 = UIImageView(image: DeckGlyph82.flowerImage(size: 14))
        knobFlower95.isUserInteractionEnabled = false
        knobFlower95.translatesAutoresizingMaskIntoConstraints = false
        knob.addSubview(knobFlower95)
        miniKnobFlower95 = knobFlower95
        NSLayoutConstraint.activate([
            knobFlower95.leadingAnchor.constraint(equalTo: knob.leadingAnchor),
            knobFlower95.trailingAnchor.constraint(equalTo: knob.trailingAnchor),
            knobFlower95.topAnchor.constraint(equalTo: knob.topAnchor),
            knobFlower95.bottomAnchor.constraint(equalTo: knob.bottomAnchor),
        ])

        miniCover = UIImageView()
        miniCover.contentMode = .scaleAspectFill
        miniCover.clipsToBounds = true
        // (87) 样片台：封面 42 圆角方（10）代 44 圆。
        // (93) B1：封面边长 42→38（台高 112 减一号 0.90）。
        // (95) 第 2 条：封面改 40×40 圆形（圆角 20）。
        miniCover.layer.cornerRadius = 20
        miniCover.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        miniCover.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniCover)
        // (84) 第 1 条：封面/歌手复原上台面（(80) 版式：
        // 左封面＋标题/歌手，点封面区＝定位当前曲的分域语
        // 义随之复原，见 miniBarTapped 的封面帧判定）。

        miniTitle = UILabel()
        // (87) 样片台：标题 15 bold。
        miniTitle.font = .systemFont(ofSize: 15, weight: .bold)
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
        // (84) 第 1 条：播放钮复原 (80) 形态——白字形、无
        // 圆底（(83) 白色大圆随紧凑台退役）；字形仍走
        // DeckGlyph82 现行临时套（J/K/L/M 未定版）。
        // (87) 样片台：播放钮改 42 圆玻璃底（白 0.13）。
        // (93) B1：钮径 42→38、圆角随之 21→19。
        miniPlayButton.tintColor = .white
        miniPlayButton.backgroundColor = .clear
        // (95) 第 4 条：播放钮 46×46、圆角 23。
        // (96) C 项：字形 19→21（回控制台传输行口径）。
        miniPlayButton.layer.cornerRadius = 23
        miniPlayButton.setImage(DeckGlyph82.image(.play, pointSize: 21), for: .normal)
        miniPlayButton.translatesAutoresizingMaskIntoConstraints = false
        miniPlayButton.addTarget(self, action: #selector(miniPlayTapped), for: .touchUpInside)
        miniPlayButton.addTarget(self, action: #selector(miniPlayDown84), for: .touchDown)
        bar.addSubview(miniPlayButton)
        // (96) C 项：播放钮整钮毛玻璃盘撤除（port90 任务 14
        // 旧制）——与 prev/next/console 三钮统一为 A4 渐变面；
        // A4Chrome91 渐变层保留（下行）。
        // port91（任务 3）：台面播放/控制台钮换 A4 玻璃面。
        A4Chrome91.apply(to: miniPlayButton, cornerRadius: 23)

        // (96) C 项：prev/next/console 三钮改 DeckHitButton96
        // （40pt 视觉不动、命中扩到 44）；播放钮 46 不用。
        miniPrevButton = DeckHitButton96(type: .system)
        miniPrevButton.tintColor = .white
        miniPrevButton.setImage(DeckGlyph82.image(.prev, pointSize: 19), for: .normal)
        miniPrevButton.translatesAutoresizingMaskIntoConstraints = false
        miniPrevButton.addTarget(self, action: #selector(miniPrevTapped), for: .touchUpInside)
        miniPrevButton.addTarget(self, action: #selector(miniPrevDown84), for: .touchDown)
        bar.addSubview(miniPrevButton)
        // (95) 第 4 条：prev/next 补 A4 玻璃面（与播放钮同式，
        // 圆角 20；钮层圆角同步供 A4 边框成圆）。
        miniPrevButton.layer.cornerRadius = 20
        A4Chrome91.apply(to: miniPrevButton, cornerRadius: 20)

        miniNextButton = DeckHitButton96(type: .system)
        miniNextButton.tintColor = .white
        miniNextButton.setImage(DeckGlyph82.image(.next, pointSize: 19), for: .normal)
        miniNextButton.translatesAutoresizingMaskIntoConstraints = false
        miniNextButton.addTarget(self, action: #selector(miniNextTapped), for: .touchUpInside)
        miniNextButton.addTarget(self, action: #selector(miniNextDown84), for: .touchDown)
        bar.addSubview(miniNextButton)
        miniNextButton.layer.cornerRadius = 20
        A4Chrome91.apply(to: miniNextButton, cornerRadius: 20)

        // (84) 第 1 条：模式钮/列表钮不上台面——职能由控
        // 制台承接（队列在面板顶部、模式四档在面板功能行，
        // 见 ConsolePanel82）；(83) 的 refreshMiniMode
        // Button83/miniListTapped83 随之整套删除。
        // (82) 第 7/8 条：控制台入口（纯图标圆钮、无字）＋
        // 双时间标签。(84) 第 1 条：入口回主排右端（(80) 版
        // 式右端簇位），30 圆钮视觉不变。
        miniConsoleButton = DeckHitButton96(type: .system)
        // (87) 样片台：控制台钮与播放钮同式 42 圆玻璃底。
        // (93) B1：钮径 42→38、圆角随之 21→19。
        miniConsoleButton.backgroundColor = UIColor.white.withAlphaComponent(0.13)
        // (95) 第 4 条：控制台钮 40×40、圆角 20。
        // (96) C 项：控制台入口字形 20→19，全行字号收为
        // 播放 21 / 其余 19 两档。
        miniConsoleButton.layer.cornerRadius = 20
        miniConsoleButton.setImage(DeckGlyph82.image(.consoleNotes, pointSize: 19), for: .normal)
        miniConsoleButton.tintColor = .white
        miniConsoleButton.accessibilityLabel = "控制台"
        miniConsoleButton.translatesAutoresizingMaskIntoConstraints = false
        miniConsoleButton.addTarget(self, action: #selector(miniConsoleTapped82), for: .touchUpInside)
        miniConsoleButton.addTarget(self, action: #selector(miniConsoleDown84), for: .touchDown)
        bar.addSubview(miniConsoleButton)
        // port91（任务 3）：控制台入口钮 A4 玻璃面（字形已换
        // gen3 双音符上下对称，见 DeckGlyph82.consoleNotes）。
        A4Chrome91.apply(to: miniConsoleButton, cornerRadius: 20)

        // port90：主题四圆点整件撤除，台面右上不再显示主题点。

        miniTimeElapsed = UILabel()
        // (89) §3-6 对齐网页 ProgressBar：时间标签 10px 等宽。
        miniTimeElapsed.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        miniTimeElapsed.textColor = UIColor.white.withAlphaComponent(0.85)
        miniTimeElapsed.text = "0:00"
        miniTimeElapsed.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniTimeElapsed)
        miniTimeDuration = UILabel()
        miniTimeDuration.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        miniTimeDuration.textColor = UIColor.white.withAlphaComponent(0.85)
        miniTimeDuration.textAlignment = .right
        miniTimeDuration.text = "0:00"
        miniTimeDuration.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(miniTimeDuration)

        let seekHit = UIView()
        seekHit.backgroundColor = .clear
        seekHit.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(seekHit)
        // (96) E 项：seek 带降到钮下——带顶盖住钮下沿 14pt 时，
        // 落钮区的点按先到 seekHit 且只跳过不转发，钮有效
        // 点按高只剩约 28pt；改插到进度轨之上、钮与封面之
        // 下，钮区点按归钮、轨区点按归 seek 带。
        bar.insertSubview(seekHit, aboveSubview: progressTrack)
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
        // (74) 轨道约束存引用：收起态要把整宽轨道换成居中
        // 小横线（宽 134、高 5），展开态还原（见 setMiniBarForm）。
        // (82) 第 7 条：展开态轨道夹在双时间标签之间（台内
        // 全宽口径不变，只是两端让给时间）；收起态仍由
        // setMiniBarForm 换 centerX＋134 宽。
        // (95) 第 5/6 条：时间标签两形态恒隐藏（对象与刷新保
        // 留），轨道解除与标签的夹锚、改直锚 bar 两端。
        // (96) E 项：轨两端按胶囊圆角内收 ±24（旧 ±20 在轨
        // 底 y 处恰顶圆弧边界，见 S4-1；24 留 ≈4pt 余量）。
        miniTrackLeadC = progressTrack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 24)
        miniTrackTrailC = progressTrack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -24)
        // (89) §3-4：展开态轨道高 4 → 6（网页 ProgressBar h-1.5）。
        // (95) 第 6 条：展开态轨道高 6 → 3（细轨贴胶囊下沿）。
        miniTrackHeightC = progressTrack.heightAnchor.constraint(equalToConstant: 3)
        Breadcrumbs.log("port89 deck=track6/time10x32 host=home")
        Breadcrumbs.log("p93 deck host=home")
        Breadcrumbs.log("p95 deck capsule h=62 host=home")
        miniTrackCenterXC = progressTrack.centerXAnchor.constraint(equalTo: bar.centerXAnchor)
        // (83) 第 5 条：收起宽 134→140（图像量测系统横线
        // 420px@3x，账见 DeckLayout82 与 (83) 报告）。
        miniTrackWidthC = progressTrack.widthAnchor.constraint(equalToConstant: 140)
        miniBarBottomC = bar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bar.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            // (77) ②⑤：底锚存引用、按形态切换——展开 −10
            // （窗口爪印退役后无需再让位 −54）；收起 +31.5
            // 使轨道中心与 home indicator 中心重合（账见
            // applyMiniBarBottom77）。先按展开值装配。
            miniBarBottomC!,

            miniTrackLeadC!,
            miniTrackTrailC!,
            miniTrackHeightC!,
            fill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            fill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            fill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor),

            // (96) E 项：把手纵向钳制——中心锚台底 −8（14pt
            // 把手底边 = 台底 −1，不露胶囊下沿；旧锚轨心时
            // 底边出台底 3.5pt，见 S4-1）。收起态台高 16 时
            // 中心同为 8，与轨心重合、无形态差。
            knob.centerYAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8),
            knob.widthAnchor.constraint(equalToConstant: 14),
            knob.heightAnchor.constraint(equalToConstant: 14),

            // (95) 第 2 条：封面 leading 11、40×40 圆（纵向由
            // miniMainCenterY 居中组归 0，见构建尾）。
            miniCover.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 11),
            miniCover.widthAnchor.constraint(equalToConstant: 40),
            miniCover.heightAnchor.constraint(equalToConstant: 40),

            // (84) 第 1 条：标题复原 (80) 锚法——封面右侧起、
            // 顶随封面 +5、右界让给主排钮簇。
            // (95) 第 3 条：歌名 leading 改封面 +10、trailing
            // 上限改锚上一曲钮 leading −10（不得钻到钮簇下）；
            // 纵向随封面同组居中（封面 centerY 归 0 后，顶随
            // 封面 +5 的相对关系不变、整组自然居中）。
            miniTitle.leadingAnchor.constraint(equalTo: miniCover.trailingAnchor, constant: 10),
            miniTitle.trailingAnchor.constraint(lessThanOrEqualTo: miniPrevButton.leadingAnchor, constant: -10),
            miniTitle.topAnchor.constraint(equalTo: miniCover.topAnchor, constant: 5),

            miniArtist.leadingAnchor.constraint(equalTo: miniTitle.leadingAnchor),
            miniArtist.trailingAnchor.constraint(equalTo: miniTitle.trailingAnchor),
            miniArtist.topAnchor.constraint(equalTo: miniTitle.bottomAnchor, constant: 2),

            // (84) 第 1 条：主排右端簇复原 (80) 链式锚——
            // 控制台入口居最右（30 圆钮、右距 12），向左依
            // 次下一曲/播放/上一曲（间隙 2、纵向由
            // miniMainCenterY 组统一 −5）。
            // (95) 第 4 条：钮簇改自右向左单链等距 8——控制台
            // （trailing −10、40×40）← 下一曲（40×40）← 播放
            // （46×46、废除 centerX 锚）← 上一曲（40×40）；
            // next/prev 旧账「双双锚 play.leading 重叠」随本
            // 链重排消除。
            miniConsoleButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            miniConsoleButton.widthAnchor.constraint(equalToConstant: 40),
            miniConsoleButton.heightAnchor.constraint(equalToConstant: 40),

            miniNextButton.trailingAnchor.constraint(equalTo: miniConsoleButton.leadingAnchor, constant: -8),
            miniNextButton.widthAnchor.constraint(equalToConstant: 40),
            miniNextButton.heightAnchor.constraint(equalToConstant: 40),

            miniPlayButton.trailingAnchor.constraint(equalTo: miniNextButton.leadingAnchor, constant: -8),
            miniPlayButton.widthAnchor.constraint(equalToConstant: 46),
            miniPlayButton.heightAnchor.constraint(equalToConstant: 46),

            miniPrevButton.trailingAnchor.constraint(equalTo: miniPlayButton.leadingAnchor, constant: -8),
            miniPrevButton.widthAnchor.constraint(equalToConstant: 40),
            miniPrevButton.heightAnchor.constraint(equalToConstant: 40),

            // (86) 第 6 条：双时间距台框 16→28（胶囊弧线内
            // 收后净距仅 ≈10-13pt、字面贴框，审计施工值）。
            miniTimeElapsed.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 28),
            miniTimeElapsed.centerYAnchor.constraint(equalTo: progressTrack.centerYAnchor),
            // (85) 审计四(b)：时间定宽 34→40——34pt 装 11pt
            // "%d:%02d" 在 ≥10 分钟时已贴满、≥100 分钟冒框。
            miniTimeElapsed.widthAnchor.constraint(equalToConstant: 32),

            miniTimeDuration.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -28),
            miniTimeDuration.centerYAnchor.constraint(equalTo: progressTrack.centerYAnchor),
            miniTimeDuration.widthAnchor.constraint(equalToConstant: 32),

            // (82) 第 7 条：seek 命中带改锚进度行（轨顶
            // −9、高 27），不再贴台底。
            // (95) 第 8 条：命中带顶改轨顶 −10、底锚 bar.bottom（删原高 27 常量）。
            // (96) E 项：命中带顶改轨顶 −22、横向随轨道（与
            // 轨同锚）；实高 27pt（22＋轨 3＋轨底 2），恢复
            // (82) 的 27pt 下限。
            miniSeekHit.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            miniSeekHit.trailingAnchor.constraint(equalTo: progressTrack.trailingAnchor),
            miniSeekHit.topAnchor.constraint(equalTo: progressTrack.topAnchor, constant: -22),
            miniSeekHit.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
        miniKnobLeading = knob.leadingAnchor.constraint(
            equalTo: progressTrack.leadingAnchor, constant: -7)
        miniKnobLeading?.isActive = true
        // (84) 第 1 条：主排纵向复原 (80)——封面与四钮同组
        // 居台中心 −5（70 台旧口径：封面 44 居 y 8–52、轨
        // 道顶 59 不重叠），两形态同值（setMiniBarForm 恒
        // 写 −5）。
        // (87) 样片台两行版式：主行上移（台高 84、主行
        // 42 居上部），进度行独立成行于台底。
        // port91（任务 4）：三行构成——封面顶行、控制钮中行。
        // (93) B1：台高 112 重排偏移 −30/＋20 → −28/＋17
        // （顶留 9、行间隔 6/7、钮→轨 6；数组序与
        // setMiniBarForm 逐项回写对应）。
        // (95) 第 4 条：五件（封面/四钮）纵向统一居中，常量
        // 由 −28/+17 全归 0（setMiniBarForm 两形态同值回写）。
        miniMainCenterY = [miniCover, miniPlayButton, miniPrevButton,
                           miniNextButton, miniConsoleButton].map {
            $0.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: 0)
        }
        NSLayoutConstraint.activate(miniMainCenterY)
        // (82) 第 7 条：轨道纵向锚制——展开态一锚在场、收
        // 起态换底锚 −5.5＋高 5（小白条形态），两锚由
        // setMiniBarForm 互斥切换。(83) 第 6 条：展开锚由
        // 「封面底 +13」改「台底 −14」（封面行已退役、三
        // 行版式按台底收口），miniTrackTopC 语义不变（展
        // 开态纵锚）。
        // (84) 第 1 条：展开轨底锚复原 (80) 的 −7（(83) 的
        // −14 系三行版式收口、随紧凑台退役）。
        // (87) 样片台：进度行独立、轨底锚 −9。
        // (95) 第 6 条：展开态轨底锚 −7 → −2（细轨贴胶囊下沿）。
        miniTrackTopC = progressTrack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -2)
        miniTrackTopC?.isActive = true
        miniTrackBottomConstraint = progressTrack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -5.5)
        miniTrackBottomConstraint?.isActive = false
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
        // (84) 第 3 条：识别器组改挂背景手势层（deck
        // Surface84，按钮的兄弟层）——按钮触摸从此不进本
        // 链，(82) 的 delegate 祖先链豁免整套退役（识别器
        // 不再设 delegate）；require 链与启停收口不变。
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(miniBarLongPressed(_:)))
        longPress.minimumPressDuration = 0.55
        deckSurface84.addGestureRecognizer(longPress)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(miniBarDoubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.require(toFail: longPress)
        deckSurface84.addGestureRecognizer(doubleTap)
        miniBarDoubleTapRecognizer = doubleTap
        let tap = UITapGestureRecognizer(target: self, action: #selector(miniBarTapped(_:)))
        tap.require(toFail: longPress)
        tap.require(toFail: doubleTap)
        deckSurface84.addGestureRecognizer(tap)
        miniBarTapRecognizer = tap
        let collapsedTap = UITapGestureRecognizer(target: self, action: #selector(miniBarCollapsedTapped(_:)))
        collapsedTap.isEnabled = false
        deckSurface84.addGestureRecognizer(collapsedTap)
        miniBarCollapsedTapRecognizer = collapsedTap
        // (74) 第 4 项兜底识别器：与形态无关、恒启用、无
        // require 链——几何已是细条（≤20）时任何落在台身的
        // 点按先按几何纠正标志再展开（把 (63) 自愈前移到分
        // 发前，照 (67) 取证修法②）。展开态恒空转放行。
        let agnosticTap74 = UITapGestureRecognizer(
            target: self, action: #selector(miniBarAgnosticTapped74(_:)))
        // (79) 第 7/13 条仲裁改造（头像当机日志定案）：本识
        // 别器原无 require 链且 cancelsTouchesInView 缺省
        // true——每次点按抬手必认领并整手取消台身触摸，单击
        // 识别器被 require(toFail: 双击) 扣住等裁定、等到的
        // 却是取消（mb.tch78 c 率 100%、locate 从未被调用）。
        // 改：不取消他人触摸＋等双击裁定落空才认领（收起态
        // 双击识别器禁用、require 立即满足，细条展开不迟滞）；
        // 几何兜底语义不变。
        agnosticTap74.cancelsTouchesInView = false
        agnosticTap74.require(toFail: doubleTap)
        deckSurface84.addGestureRecognizer(agnosticTap74)

        applyMiniTheme()
        applyMiniBarSlots()
    }

    /// (74) 第 4 项：细条点按的几何兜底（与形态无关）。
    /// 背景定案见 (67) 取证 C① 与 (70) B3 注释：标志=展开、
    /// 几何=细条的失同步态下 collapsedTap 被 sync 关掉、点
    /// 按落进展开链的双击/长按判定里出不来；(70) 只在出现
    /// 边沿按几何自愈，页面存续期间再失同步仍点不开（(73)
    /// 真机依旧、(74) Miller 再报）。本识别器不随形态启停，
    /// 以台体实际高度为真值：≤20 即先落 heal 面包屑纠正标
    /// 志、再走既有 expandMiniBar（其内 minibar expand 一
    /// 行与本行 minibar.hit 成对，即「点中→展开」自证）。
    @objc private func miniBarAgnosticTapped74(_ gesture: UITapGestureRecognizer) {
        guard let bar = miniBar else { return }
        // (75) 死点留痕：几何守卫拒绝不再静默——bounds 高
        // 与形态面包屑的 h=（约束常数）对位即可判布局未落。
        guard bar.bounds.height <= 20 else {
            Breadcrumbs.log("minibar.dead75 host=homewall at=geom"
                + " h=\(Int(bar.bounds.height))")
            return
        }
        if !miniBarCollapsed {
            Breadcrumbs.log("minibar.hit host=homewall heal=flag74")
            miniBarCollapsed = true
            miniPetStage?.barFormChanged(collapsed: true)
        }
        Breadcrumbs.log("minibar.hit host=homewall via=agnostic74")
        expandMiniBar()
    }

    /// 点播台槽位应用（3.7 (50)）：按 MiniBarSlotSettings 显隐
    /// prev/next 两键（本台无列表键）；隐藏时宽度约束置 0、
    /// 其余键自动收拢补位。宽度约束经按钮自身 constraints
    /// 反查，不改构建期约束块。口径与曲目墙/舞台台一致。
    private func applyMiniBarSlots() {
        // (87) 播放台换代：上一曲/下一曲撤下台面、藏进控制
        // 台顶部圆形玻璃钮排——两钮恒隐藏＋宽 0（对象与点
        // 按通路保留）；槽位设置（MiniBarSlotSettings）自此
        // 不再驱动台面两钮显隐。
        // (95) 第 4 条盖过：胶囊台四钮单行（上一曲/播放/下
        // 一曲/控制台）在台面同排——两钮复归台面、宽随新
        // 规格 40（否则构建期 40×40 约束会被本函数写 0、
        // 四钮构成不成立）；槽位设置仍不驱动台面显隐。
        guard let prev = miniPrevButton, let next = miniNextButton else { return }
        applySlot(prev, visible: true, width: 40)
        applySlot(next, visible: true, width: 40)
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

    /// 进度填充与发光圆钮的唯一步进点（与曲目墙同构）：主题
    /// 层的积雪/鲨鳍/流星头位也在此转喂，同源同步。
    private func setMiniProgress(_ fraction: Double) {
        let clamped = CGFloat(min(max(fraction, 0), 1))
        miniProgressFill.transform = CGAffineTransform(scaleX: clamped, y: 1)
        let trackWidth = miniProgressTrack.bounds.width
        if trackWidth > 0 {
            // (83) 把手 14pt 宽，领先常量按半宽居中。
            miniKnobLeading?.constant = clamped * trackWidth - 7
        }
        miniThemeLayer?.setFraction(Double(clamped))
        // (82) 第 7 条：双时间标签随进度同刷（数据源＝引擎
        // currentTime/duration，与轨道同源同时刻）。
        let engine = PlaybackEngine.shared
        miniTimeElapsed?.text = Self.formatDeckTime82(engine.currentTime)
        miniTimeDuration?.text = Self.formatDeckTime82(engine.duration)
    }

    /// (82) 台面时间格式 m:ss（负数/非有限值归 0:00）。
    static func formatDeckTime82(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// 主题应用（13.5）：主题层换装 + 圆点皮肤 + 填充色，只
    /// 动视觉，不碰播放/进度/手势分发。皮肤/填充/圆点的最终
    /// 落色经 refreshMiniProgressChrome 按当前形态收口——
    /// 收起态（(22) 去背景）走对比度兜底口径。
    private func applyMiniTheme() {
        miniThemeLayer?.apply(theme: miniTheme)
        refreshMiniProgressChrome()
        // (82) 第 7 条：字形与主题解耦（DeckGlyph82 单套），
        // 主题切换只剩播/停态回刷。
        refreshDeckIcons82()
    }

    /// (82) 第 7 条：台面字形回刷——仅播/停态（上下曲字形
    /// 恒定，构建时已装）。旧 DeckIconSet81 主题四套字形
    /// 随旧台退役。
    private func refreshDeckIcons82() {
        guard miniPlayButton != nil else { return }
        miniPlayButton.setImage(
            DeckGlyph82.image(
                PlaybackEngine.shared.playbackState == .playing ? .pause : .play,
                // (96) C 项：播放字形回 21（控制台口径）。
                pointSize: 21),
            for: .normal)
        // (94) 94-3：setImage 后重挂字形层——A4 渐变层
        // （A4Chrome91 insert at 0）是仅有的插入子视图
        // （(96) C 项整钮 blur 盘已撤），刷新路径此前只
        // setImage、从不重申 imageView 在插入层之上，主题
        // 刷新（applyMiniTheme→本函数）后字形可被整层盖住；
        // 此处与 refreshMiniBar 两处刷新口统一重挂。
        A4Chrome91.rehangGlyph(of: miniPlayButton)
        // (84) 第 1 条：模式钮已撤下台面，本回刷只剩播/停
        // 态（模式回显在控制台面板内自理）。
    }

    /// (94) 94-3：cov 自证移到按钮最终渲染层。(93) 的自证
    /// 装在 DeckGlyph82 工厂出口、测不到按钮最终渲染——
    /// (93) 真机图三主页墙展开台中央钮仍是空圆。本处在
    /// viewDidLayoutSubviews 收口（布局已稳）时对四钮
    /// layer 做离屏渲染快照，测中心区域字形覆盖率（判据
    /// 见 DeckGlyph82.snapshotCenterCoverage），逐钮落
    /// p94 deck render 行。去重口径：每钮每字形状态只测
    /// 一次（deckRenderProbed94），播/停切换经 refresh-
    /// MiniBar 换图后键变重测；不逐布局、不逐帧。
    /// play/pause 的 cov 低于阈值 0.5%（0.005：A4 play 描
    /// 边字形在 38pt 钮心 60% 区域的实测覆盖应在 3% 量
    /// 级，0.5% 已是「只剩零星像素」的空钮线）时，当场
    /// 以填充路径字形（DeckGlyph82.filledFallbackImage）
    /// 替换钮图并在同行落 fb=1。
    private func probeDeckRender94() {
        // (95) 守卫自证：(94) 日志 p94 deck render 全 0 条
        // 且守卫是否满足无从对账——未命中时按三值组合落
        // 一行低频自证（每会话每组合只落一次），下份日志
        // 能分开「台没展开/已收起/钮不在窗上」与「探针没
        // 跑」。守卫满足并采样（下方 p94 deck render 行）
        // 时不落 guard 行；采样点仍在 viewDidLayoutSubviews
        // 收口、不新增定时器。
        let deckWin95 = miniPlayButton?.window != nil
        guard miniBarPresented, !miniBarCollapsed,
              miniPlayButton != nil, miniPlayButton.window != nil,
              miniPlayButton.bounds.width > 0 else {
            let pres95 = miniBarPresented ? 1 : 0
            let coll95 = miniBarCollapsed ? 1 : 0
            let win95 = deckWin95 ? 1 : 0
            let combo95 = "\(pres95),\(coll95),\(win95)"
            if !deckGuardLogged95.contains(combo95) {
                deckGuardLogged95.insert(combo95)
                Breadcrumbs.log("p95 deck guard pres=\(pres95)"
                    + " coll=\(coll95) win=\(win95)")
            }
            return
        }
        let playing = PlaybackEngine.shared.playbackState == .playing
        probeDeckButton94(miniPlayButton, btn: "play",
                          glyph: playing ? "pause" : "play",
                          kind: playing ? .pause : .play)
        probeDeckButton94(miniPrevButton, btn: "prev", glyph: "prev", kind: nil)
        probeDeckButton94(miniNextButton, btn: "next", glyph: "next", kind: nil)
        probeDeckButton94(miniConsoleButton, btn: "console", glyph: "console", kind: nil)
    }

    private func probeDeckButton94(_ button: UIButton?, btn: String,
                                   glyph: String, kind: DeckGlyph82.Kind?) {
        guard let button, button.bounds.width > 0 else { return }
        let key = "\(btn):\(glyph)"
        guard !deckRenderProbed94.contains(key) else { return }
        deckRenderProbed94.insert(key)
        // ivtop 在重挂前取值：记录 imageView 进探针时是否
        // 已是钮内最上子视图——覆盖者定位的真机证据位，
        // 不许被本探针自己的修复动作污染。
        let ivTop = button.imageView.map {
            button.subviews.last === $0
        } ?? false
        // 测前重挂一次字形层：若 cov 仍低，即排除 z 序因
        // 素、断在渲染/图片本身，fb 兜底随即接管。
        A4Chrome91.rehangGlyph(of: button)
        button.layoutIfNeeded()
        let imgNil = button.image(for: .normal) == nil
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        // 钮 layer 树的离屏快照（drawHierarchy 按 bounds
        // 精确落位，等价渲染 layer 全树、无位置偏移歧义）。
        let snapshot = UIGraphicsImageRenderer(
            bounds: button.bounds, format: format).image { _ in
            button.drawHierarchy(in: button.bounds, afterScreenUpdates: false)
        }
        let cov = DeckGlyph82.snapshotCenterCoverage(snapshot)
        var fb = 0
        // 阈值 0.5%（0.005）：见 probeDeckRender94 注释。
        if let kind, cov < 0.005,
           let filled = DeckGlyph82.filledFallbackImage(kind, pointSize: 21) {
            button.setImage(filled, for: .normal)
            A4Chrome91.rehangGlyph(of: button)
            fb = 1
        }
        Breadcrumbs.log("p94 deck render btn=\(btn) cov=\(Int(cov * 1000))"
            + " img=\(imgNil ? "nil" : "ok") sub=\(button.subviews.count)"
            + " ivtop=\(ivTop ? 1 : 0) fb=\(fb)")
    }

    // (84) 第 1 条：refreshMiniModeButton83 与 miniListTapped83 已随
    // 模式钮/列表钮撤下台面整套删除（职能由控制台承接）。

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
                // (87) 样片花朵把手 17pt（原 13pt 皮肤放大）。
                skin.widthAnchor.constraint(equalToConstant: 17),
                skin.heightAnchor.constraint(equalToConstant: 17),
            ])
            miniKnobSkin = skin
        }
        // (95) 第 7 条：本函数只摘 miniKnobSkin（上方）、不
        // 清 knob 全部子视图，花图子视图恒在场；此处仅作防
        // 摘除重挂守卫（万一花图被其他路径摘除，在此按铺满
        // 约束重挂；不抢主题皮肤的 z 序，皮肤在场时仍盖点）。
        if let flower95 = miniKnobFlower95, flower95.superview == nil {
            miniProgressKnob.addSubview(flower95)
            NSLayoutConstraint.activate([
                flower95.leadingAnchor.constraint(equalTo: miniProgressKnob.leadingAnchor),
                flower95.trailingAnchor.constraint(equalTo: miniProgressKnob.trailingAnchor),
                flower95.topAnchor.constraint(equalTo: miniProgressKnob.topAnchor),
                flower95.bottomAnchor.constraint(equalTo: miniProgressKnob.bottomAnchor),
            ])
        }
        // (84) 第 1 条：把手复原 (80) 口径——有主题皮肤时
        // 皮肤盖点（钮身转清、关发光）；无皮肤时白色发光
        // 点兜底（构建值）。
        if miniKnobSkin != nil {
            miniProgressKnob.backgroundColor = .clear
            miniProgressKnob.layer.shadowOpacity = 0
        } else {
            miniProgressKnob.backgroundColor = .white
            miniProgressKnob.layer.shadowOpacity = 0.9
        }
        if miniBarCollapsed {
            // (82) 第 5 条：收起态改系统白系——填充纯白、
            // 轨道白 35%，对齐 home indicator 观感（旧主题
            // 色整条退役）。
            miniProgressFill.backgroundColor = .white
            miniProgressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        } else {
            // (79) 第 2 条进度配色：全条统一一色——轨道与
            // 填充同色直用；进度辨识靠花朵把手位置。
            let singleColor = Self.miniFillColor(for: miniTheme)
            miniProgressFill.backgroundColor = singleColor
            miniProgressTrack.backgroundColor = singleColor
        }
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
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point)
            || miniConsoleButton.frame.contains(point) { return }
        // 附加功能行已迁浮层（(60) 第 7 条）：浮层不在台身内，
        // 其触摸不进本识别器，旧上排豁免随之退役。
        miniTheme = miniTheme.next
        MiniPlayerTheme.stored = miniTheme
        applyMiniTheme()
        NotificationCenter.default.post(name: .foliaMiniPlayerThemeChanged, object: nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        resetMiniIdleTimer()
    }

    // (84) 第 3 条：四钮 touchDown 见证（与 up 分离落痕）。
    @objc private func miniPlayDown84() {
        Tap84.log(host: "homewall", btn: "play", ev: "down", view: miniPlayButton)
    }

    @objc private func miniPrevDown84() {
        Tap84.log(host: "homewall", btn: "prev", ev: "down", view: miniPrevButton)
    }

    @objc private func miniNextDown84() {
        Tap84.log(host: "homewall", btn: "next", ev: "down", view: miniNextButton)
    }

    @objc private func miniConsoleDown84() {
        Tap84.log(host: "homewall", btn: "console", ev: "down", view: miniConsoleButton)
    }

    @objc private func miniPlayTapped() {
        Tap84.log(host: "homewall", btn: "play", ev: "up", view: miniPlayButton)
        DeckTap82.log(host: "home", zone: "play", view: miniPlayButton)
        resetMiniIdleTimer()
        PlaybackEngine.shared.togglePlayPause()
    }

    @objc private func miniPrevTapped() {
        Tap84.log(host: "homewall", btn: "prev", ev: "up", view: miniPrevButton)
        DeckTap82.log(host: "home", zone: "prev", view: miniPrevButton)
        resetMiniIdleTimer()
        stickerNoteTrackChangeTap()
        QueueManager.shared.playPrevious()
    }

    @objc private func miniNextTapped() {
        Tap84.log(host: "homewall", btn: "next", ev: "up", view: miniNextButton)
        DeckTap82.log(host: "home", zone: "next", view: miniNextButton)
        resetMiniIdleTimer()
        stickerNoteTrackChangeTap()
        QueueManager.shared.playNext(manual: true)
    }

    /// (82) 第 8 条：控制台入口——升起 ConsolePanel82
    /// （队列/功能行/音量/外观/灯钮/帮助全在面板内）。
    @objc private func miniConsoleTapped82() {
        Tap84.log(host: "homewall", btn: "console", ev: "up", view: miniConsoleButton)
        DeckTap82.log(host: "home", zone: "console", view: miniConsoleButton)
        resetMiniIdleTimer()
        ConsolePanel82.present(from: self)
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
            || miniConsoleButton.frame.contains(point) { return }
        // 进度带分域（标题优先于进度带，与旧封面分发序一
        // 致）：带内落点直接返回，seek 已即时发生。
        if miniSeekHit.frame.contains(point), !miniTitle.frame.contains(point) {
            Breadcrumbs.log("minibar.tap host=homewall zone=seekband action=skip")
            return
        }
        // (62) 尾波第 5 组：封面区单击换动作——回封面播放页，
        // 不再与台身同走浮层开关。
        if miniTitle.frame.contains(point) {
            locateCurrentTrackFromCover()
            return
        }
        // (82) 第 8 条：台身空白单击改开控制台面板（旧附
        // 加功能浮层退役为入口——其职能已全进控制台；浮
        // 层件本身在曲目墙/舞台仍有旧入口，本宿主不再呼
        // 出）。
        if let bar = miniBar { DeckTap82.log(host: "home", zone: "body", view: bar) }
        ConsolePanel82.present(from: self)
        Breadcrumbs.log("minibar.tap host=homewall action=console82")
    }

    /// 台面双击分发（主页版，3.7 (61) 第 7 条）：双击进歌曲详
    /// 情页（openNativeStageFromHome 原路径）；封面同规格参
    /// 与（封面双击同样进详情）。进度带分域：双击落带内不
    /// 触发详情（每击已由 seekHit 识别器即时 seek）；按键区
    /// 自理。宠物占位区双击被宠物识别器接走、到不了台身。
    @objc private func miniBarDoubleTapped(_ gesture: UITapGestureRecognizer) {
        // (83) 第 2 条取证：双击全路径同步落盘（只取证、
        // 不改分发逻辑；步名见 DblTap83）。
        DblTap83.step("home", "recv")
        guard let bar = miniBar, !miniBarCollapsed else {
            DblTap83.step("home", "guardform")
            return
        }
        resetMiniIdleTimer()
        let point = gesture.location(in: bar)
        if miniPlayButton.frame.contains(point)
            || miniPrevButton.frame.contains(point)
            || miniNextButton.frame.contains(point)
            || miniConsoleButton.frame.contains(point) {
            DblTap83.step("home", "skipbtn")
            return
        }
        if miniSeekHit.frame.contains(point), !miniTitle.frame.contains(point) {
            Breadcrumbs.log("minibar.doubletap host=homewall zone=seekband action=skip")
            DblTap83.step("home", "skipseek")
            return
        }
        Breadcrumbs.log("minibar.doubletap host=homewall action=stage")
        // (63) DS R63 B0：分发边界同步落盘——崩溃会话里本行
        // 在不在，直接判「双击到底有没有走到开台分发」。
        Breadcrumbs.logSync("tap.dispatch host=homewall")
        DblTap83.arm("home")
        DblTap83.step("home", "call")
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
            // (81) 第 2 条改绑：来源不可知不再静默无操作
            // （(79) 判读定案：动作语义对不上 Miller「切换
            // 到正在播放的歌曲」且 miss 完全静默）——直达
            // 在播歌曲的呈现：打开当前曲的舞台详情页。无
            // 在播曲目时给 toast 可见反馈，同样不静默。
            if let current = PlaybackEngine.shared.currentTrack {
                // (82) 第 3 条：统一语义落痕 locate82（与歌
                // 单墙共用点按分发口径：本墙无此曲→来源墙
                // →舞台兜底）。
                Breadcrumbs.log("locate82 host=home via=stage id=\(current.id)")
                Breadcrumbs.logSync("tap.dispatch host=homewall via=cover82")
                openNativeStageFromHome()
            } else {
                Breadcrumbs.log("locate82 host=home via=none id=-")
                NativePlaybackFailureToast.show(message: "现在没有正在播放的歌曲")
            }
            return
        }
        if let currentId = PlaybackEngine.shared.currentTrack?.id {
            Breadcrumbs.log("locate82 host=home via=wall id=\(currentId)")
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
            let seed = await wall.awaitSeed(timeout: playlistSeedWait96)
            self.present(wall, animated: true) { [weak self] in
                self?.endPosterTransition(source: "cover-locate", seedReady: seed)
            }
        }
    }

    /// 收起态细条单击（3.7 (61) 第 7 条）：独立识别器、无任何
    /// require 链，点按即时展开回完整形态并重新计时（展开在
    /// expandMiniBar 内），不被双击判定拖延。
    @objc private func miniBarCollapsedTapped(_ gesture: UITapGestureRecognizer) {
        (miniBar as? MiniBarHitView)?.noteRecognizerClaimed()
        guard miniBarCollapsed else {
            Breadcrumbs.log("minibar.dead75 host=homewall at=flag")
            return
        }
        Breadcrumbs.log("minibar.tap host=homewall collapsed=1 action=expand")
        // (77) ⑥派发环自证（claim77→disp77→expand 三环）。
        Breadcrumbs.log("minibar.disp77 host=homewall via=tap")
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
            || miniConsoleButton.frame.contains(point) { return }
        if miniTitle.frame.contains(point) { return }
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
    /// (77) ⑥派发段见证的识别器启停位串（与 wallproto 同构）。
    private func miniTapBits() -> String {
        "\((miniBarTapRecognizer?.isEnabled ?? false) ? 1 : 0)"
            + "\((miniBarDoubleTapRecognizer?.isEnabled ?? false) ? 1 : 0)"
            + "\((miniBarCollapsedTapRecognizer?.isEnabled ?? false) ? 1 : 0)"
    }

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
            if miniTitle.frame.contains(barPoint)
                || miniPlayButton.frame.contains(barPoint)
                || miniPrevButton.frame.contains(barPoint)
                || miniNextButton.frame.contains(barPoint)
                || miniConsoleButton.frame.contains(barPoint) { return }
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
        // (72) 单宿主仲裁：非最前宿主不许动形态（防双宿主同动）。
        guard MiniBarSingleHost.shared.isActive("homewall") else { return }
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
        // (75) 死点留痕：仲裁拒绝不再静默（点按已到此环时
        // 日志能直接判是仲裁卡住、不是命中链断）。
        guard MiniBarSingleHost.shared.isActive("homewall") else {
            Breadcrumbs.log("minibar.dead75 host=homewall at=arb")
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
    /// (77) ②底锚按形态落位（几何账与 wallproto 同注：
    /// 展开 −10、收起 +31.5 与 home indicator 中心重合、
    /// 无 indicator 机型回落 −10；宠物层按 bar.frame 跟随）。
    /// (78) 第 1 条修正：收起常数 31.5→24.5——(77) 的严丝
    /// 合缝重合做过头，系统小白线（屏底上方 8–13pt 带）整
    /// 条压在轨道（同带 8–13）与宠物上。本版整条上抬 7pt：
    /// 轨道中心升至屏底上方 17.5、轨道带 15–20，小白线只
    /// 落在条身下部空白边距（条底 9.5–15 无轨道无宠物），
    /// 与轨道之间留 2pt 净空。展开 −10 不变。
    private func applyMiniBarBottom77(collapsed: Bool) {
        guard let bottomC = miniBarBottomC else { return }
        let inset = view.window?.safeAreaInsets.bottom
            ?? view.safeAreaInsets.bottom
        // (84) 第 2 条：改回 (80) 形态——我方轨贴在系统小
        // 白线**上方**、不重叠：C = inset − 9.5（竖屏 24.5
        // ＝(80) 常数逐点复原、轨带 15–20 对线带 8–13 留
        // 2pt 净空；横屏 11.5 同式，账见 DeckLayout84）。
        // (83) 的 inset−2.5 使轨带落回 8–13 与线重合（Miller
        // ⑥点名），本版盖过。
        bottomC.constant = collapsed
            ? DeckLayout84.collapsedBottomConstant(safeAreaBottom: inset) : -10
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
        // (84) 第 1 条：主排纵向复原 (80)——两形态恒同值。
        // (87) 样片台两行版式：恒 −14（台高 84 的主行位）。
        // port91（任务 4）：三行位恒定。(93) B1：偏移 −28/＋17。
        // (95) 第 4 条：五件居中组两形态恒归 0。
        for constraint in miniMainCenterY {
            constraint.constant = 0
        }
        // (95) 第 5 条：双时间标签展开/收起两形态均不显示
        // （对象与 setMiniProgress 的刷新逻辑保留不删）。
        miniTimeElapsed.isHidden = true
        miniTimeDuration.isHidden = true
        // (74) 第 5 项小横线：收起态轨道不再整宽——换居中
        // 134×5 圆角小横线（Home 指示条量级），进度填充仍在
        // 线内表达（fill 宽随轨道宽、scaleX 分数不变）；圆点
        // 收起（线身不再挂点）。台体容器不动（宽/高/命中带
        // 原样，命中区不随视觉缩小——第 4 项反方向纪律）。
        // 底距 −5.5 使 5pt 线在 16pt 容器内居中。
        miniTrackBottomConstraint?.constant = collapsed ? -5.5 : -7
        // (81) 第 1 条两态口径（盖过 (79) 的恒 134——展开台
        // 里短轨悬在中段系 (79) 做过头，Miller (79) 验收图
        // 证点名）：收起态居中 134×5 短轨（与 home
        // indicator 同尺寸、横竖屏同规不拉长）；展开态还
        // 原台内全宽长 seek 轨（lead/trail ±24（(96) E 项
        // 由 ±20 内收）、高 6、圆角
        // 3，(89) 对齐网页轨道高）。花朵圆点把手两态恒在场（下文
        // isHidden=false 与皮肤重挂不变）。
        if collapsed {
            miniTrackLeadC?.isActive = false
            miniTrackTrailC?.isActive = false
            miniTrackCenterXC?.isActive = true
            miniTrackWidthC?.isActive = true
            miniTrackHeightC?.constant = 5
            miniProgressTrack.layer.cornerRadius = 2.5
            // (82) 第 7 条：收起态轨道换底锚（顶锚撤）。
            miniTrackTopC?.isActive = false
            miniTrackBottomConstraint?.isActive = true
        } else {
            miniTrackCenterXC?.isActive = false
            miniTrackWidthC?.isActive = false
            miniTrackLeadC?.isActive = true
            miniTrackTrailC?.isActive = true
            // (95) 第 6 条：展开态轨道高 6 → 3（收起态 5 不动）。
            miniTrackHeightC?.constant = 3
            miniProgressTrack.layer.cornerRadius = 3
            // (82) 第 7 条：展开态轨道换顶锚（底锚撤）。
            miniTrackBottomConstraint?.isActive = false
            miniTrackTopC?.isActive = true
        }
        // (77) ②③：四主题小圆点恢复收起态在场（(74) 以
        // isHidden=collapsed 误删；皮肤两形态同挂、圆点
        // 本体恒可见，(22)/(23) 旧制）。
        miniProgressKnob.isHidden = false
        // (84) 第 1 条：把手已复原 (80) 圆点/皮肤形态——收
        // 起态不再压平（(82) 的 0.25 压平是花朵把手专用，
        // 随花朵退役；(80)/(23) 口径圆点两态同形）。
        miniProgressKnob.transform = .identity
        // (95) 第 1 条：展开圆角随胶囊新高改 31（收起 8 不动）。
        let radius: CGFloat = collapsed ? 8 : 31
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
        // (84) 第 1 条：主题层复原 (80) 形态口径——展开在
        // 场、收起隐藏（去背景纪律不变）。
        miniThemeLayer?.isHidden = collapsed
        miniBlurView?.isHidden = collapsed
        miniRimLight?.isHidden = collapsed
        miniGlassTint?.isHidden = collapsed
        // 点按识别器组随形态启停（3.7 (61) 第 7 条）：收起态
        // 只认无链单击即时展开，展开态才挂双击判定链。
        syncMiniBarTapRecognizers(collapsed: collapsed)
        // (85) 第 3 条（审计四(a)）：收起态 seek 命中带禁交
        // 互——(84) 识别器改挂背景层后，seek 带（整台宽×
        // 27pt）在收起态正盖住细条中央带、其回调收起态空
        // 转，点中央的展开点按被它截走（点边缘活、点中央
        // 死＝「有时不弹」）。两态互斥后收起态点细条任意
        // 位置都落背景层的 collapsedTap → expandMiniBar；
        // 展开态 seek 点按/拖动行为不变。判读路径：收起态
        // 中央点 → minibar.touch75 → mb.claim78/minibar
        // .tap collapsed=1 → minibar expand（与 seek85 本行
        // hit=0 同窗对位）。
        miniSeekHit.isUserInteractionEnabled = !collapsed
        Breadcrumbs.log("seek85 host=home hit=\(collapsed ? 0 : 1)")
        // (63) 第 2 条形态面包屑：每次形态收口落一行——标志/
        // 几何高/三识别器启停位同行，下轮日志一次判清标志与
        // 几何是否同值（细条无法展开的判别证据）。
        // (81) 第 1 条：tw= 轨道目标宽同行落盘（收起 134／
        // 展开＝台宽−40），下轮日志免像素量测即可自证两态。
        Breadcrumbs.log("minibar.form host=homewall collapsed=\(collapsed ? 1 : 0)"
            + " h=\(Int(miniBarHeightConstraint?.constant ?? -1))"
            + " tw=\(collapsed ? 140 : Int(miniBarWidthConstraint?.constant ?? 0) - 40)"
            + " recog=\((miniBarTapRecognizer?.isEnabled ?? false) ? 1 : 0)"
            + "\((miniBarDoubleTapRecognizer?.isEnabled ?? false) ? 1 : 0)"
            + "\((miniBarCollapsedTapRecognizer?.isEnabled ?? false) ? 1 : 0)")
        // (84) 第 2 条：小白条形态自证新口径——收起轨宽按
        // 朝向（竖 140 实测／横 209 惯例值，DeckLayout84）、
        // gap＝轨底与系统小白线顶的相接间隙（2pt、不重
        // 合）；展开态沿旧口径（gap=-1/r=2）。
        let fmPortrait84 = view.bounds.width <= view.bounds.height
        if collapsed {
            miniTrackWidthC?.constant =
                DeckLayout84.collapsedTrackWidth(portrait: fmPortrait84)
        }
        Breadcrumbs.log("minibar.fm84 host=home"
            + " col=\(collapsed ? 1 : 0)"
            + " tw=\(collapsed ? Int(DeckLayout84.collapsedTrackWidth(portrait: fmPortrait84)) : Int(miniBarWidthConstraint?.constant ?? 0) - 116)"
            + " th=\(collapsed ? 5 : 4)"
            + " gap=\(collapsed ? 2 : -1)"
            + " r=\(collapsed ? "2.5" : "2")"
            + " orient=\(fmPortrait84 ? "port" : "land")")
        refreshMiniProgressChrome()
    }

    /// (86) 第 5 条：旋转落定按新朝向重写收起轨宽。轨宽
    /// 唯一写入点在 setMiniBarForm 尾部、按当刻 bounds 算
    /// 朝向——旋转不触发形态函数时，竖屏写下的 140 永远
    /// 留在横屏（(85) 图四定案：量测差 ≈78pt 与代码推演
    /// 吻合）。completion 按新 size 重跑同一写入，常数
    /// 218/140 不动；fm86 恒落行——横屏与舞台样本自此
    /// 必有（补 (84)(85) 两轮 fm84 横屏零样本的缺口）。
    private func refreshTrackWidth86(portrait: Bool) {
        let tw = DeckLayout84.collapsedTrackWidth(portrait: portrait)
        if miniBarCollapsed { miniTrackWidthC?.constant = tw }
        Breadcrumbs.log("fm86 host=homewall"
            + " orient=\(portrait ? "port" : "land")"
            + " col=\(miniBarCollapsed ? 1 : 0) tw=\(Int(tw))")
    }

    private func setMiniBarContentsAlpha(_ alpha: CGFloat) {
        // 圆点不在淡出名单（3.7 (22)）：收起态保留发光圆点
        // 随进度步进，淡出的只有封面/标题/歌手/按键。
        // 附加功能行已迁浮层（(60) 第 7 条），不入台形态名单：
        // 台收起时浮层由 collapseMiniBarIdle 单独收起。
        let views: [UIView?] = [miniCover, miniTitle, miniArtist, miniPlayButton,
                                miniPrevButton, miniNextButton, miniConsoleButton,
                                miniTimeElapsed, miniTimeDuration]
        for view in views {
            view?.alpha = alpha
        }
    }

    private func setMiniBarContentsInteractive(_ interactive: Bool) {
        let buttons: [UIButton?] = [miniPlayButton, miniPrevButton, miniNextButton,
                                    miniConsoleButton]
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
            DeckGlyph82.image(engine.playbackState == .playing ? .pause : .play,
                              // (96) C 项：播放字形回 21（控制台口径）。
                              pointSize: 21),
            for: .normal)
        // (94) 94-3：setImage 后重挂字形层（同 refreshDeck-
        // Icons82 口径：钮内 A4 渐变插入层之上须恒为
        // imageView，刷新路径不许只换图不重申 z 序）。
        A4Chrome91.rehangGlyph(of: miniPlayButton)
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
            // (83) 第 2 条取证：双击链守卫拦截步（同步落盘）。
            DblTap83.step("home", "guard0")
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
            // (83) 第 2 条取证：present 完成步改同步落盘
            // （(82) 窗 present.done 全窗 0 次——本步在不在
            // 直接判呈现链是否走完）。
            DblTap83.step("home", "done")
        }
    }

    /// (62) 播放后进入的视图路由：点歌起播后按 playbackEntryView
    /// 决定去向——stage 开台（默认）、detail 开台后打开播放面板、
    /// stay 留在当前页、lattice 打开队列拼贴（(71) 补档）。仅点歌路径（探段直点起播）走本路由；
    /// 迷你台双击/回到播放页/后台点入等显式导航仍走
    /// openNativeStageFromHome 原路、不受本设置管辖。
    private func routeAfterPlayback62() {
        switch PlaybackEntry62.current {
        case .stay:
            Breadcrumbs.log("entry62 route=stay")
        case .lattice:
            // (71) Lattice 档：起播后 present 队列拼贴墙。
            Breadcrumbs.log("entry62 route=lattice")
            QueueLatticeViewController.present(from: self)
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

    /// (75) 工具条朝向切换：竖屏激活绕岛带组、横屏激活安
    /// 全区侧锚组；同值重复调用为空操作（viewDidAppear 每
    /// 次露面调用作首启定向兜底，不产生约束抖动）。
    func applySeamBandOrientation(portrait: Bool) {
        guard seamBandIsPortrait != portrait,
              !seamBandPortrait.isEmpty, !seamBandLandscape.isEmpty else { return }
        seamBandIsPortrait = portrait
        NSLayoutConstraint.deactivate(portrait ? seamBandLandscape : seamBandPortrait)
        NSLayoutConstraint.activate(portrait ? seamBandPortrait : seamBandLandscape)
        Breadcrumbs.log("seam.wrap75 host=home portrait=\(portrait ? 1 : 0)")
    }

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
        // (66) 初始即网格形态时恢复落盘偏移（布局完成后执行，
        // contentSize 就绪才生效）。
        if seamGridMode, SettingsStore.rememberCardPositions {
            let savedY = CGFloat(SettingsStore.wallScrollOriginY)
            if savedY > 0 {
                DispatchQueue.main.async {
                    grid.contentOffset = CGPoint(x: grid.contentOffset.x, y: savedY)
                }
            }
        }

        // 工具条 z 序（(60) 第 2 条）：提到日记本宿主之上作双
        // 保险——日记本把手热区已下移（edgeTop ≥115）与本条纵
        // 向错位，此处再保顶部条带的命中不被日记本层拦截。
        // (75) 第 3 项双向约束组：竖屏＝绕岛带（钉屏幕顶边
        // 全宽、高 104：凹口 0–56＋内容行 54–98＋底衬 6，
        // 条体绕岛、横线落岛左近）；横屏＝(74) 安全区侧锚
        // （岛在侧边、leading 贴安全区左缘即避岛）。切换点
        // 在 viewWillTransition 与 viewDidAppear（首启定向）。
        let toolbar = SeamToolbarView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wrapIslandEnabled = true
        toolbar.contentRowTop = 54
        // (78) 第 4 条（仅主页）：平形态内容行下挪 30——控
        // 件行心 52→67，分段上沿 52/头像上沿 51 与岛底 48
        // 拉开 3–4pt 间距，不再贴岛干涉（(77)⑨ 的贴岛口径
        // 只动了从不生效的绕岛形态、本条补到平形态本尊）。
        toolbar.flatRowTop = 30
        if let drawer = sketchbookDrawer {
            view.insertSubview(toolbar, aboveSubview: drawer)
        } else {
            view.addSubview(toolbar)
        }
        let bandP: [NSLayoutConstraint] = [
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 104),
        ]
        seamToolbarTrailing = toolbar.trailingAnchor.constraint(
            equalTo: view.trailingAnchor, constant: -12)
        let bandL: [NSLayoutConstraint] = [
            toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            seamToolbarTrailing!,
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
        ]
        seamBandPortrait = bandP
        seamBandLandscape = bandL
        applySeamBandOrientation(
            portrait: UIScreen.main.bounds.width < UIScreen.main.bounds.height)
        // (63) 第 4 条：墙缝信息条（StripSurface62）按 Miller
        // 令整条摘除——装配块删除后工具条下方区域回归墙面卡
        // 片本体；条本不拦截触摸，顶部热区与层级零变化。
        toolbar.setLayoutMode(grid: seamGridMode)
        toolbar.onSegmentChanged = { [weak self] segment in
            self?.seamSegmentSelected(segment)
        }
        // (71)「拼」格：present 队列拼贴墙（与 .lattice 路由档、
        // 命令面板 navigate-lattice 共用同一落点）。
        toolbar.onLatticeTapped = { [weak self] in
            guard let self else { return }
            QueueLatticeViewController.present(from: self)
        }
        // port88：工具条头像已摘除——(85) 第 2 条的头像绑
        // 定位随之退役，账户卡入口只剩设置页账户组（见
        // SettingsViewController 账户卡钮）。
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
        // (74) 导播台入口改挂工具条灯泡（原工作台 .guide 行
        // 退役）：落点仍是 Ponder62 导览列表。
        toolbar.onGuideTapped = { [weak self] in
            guard let self else { return }
            Breadcrumbs.log("wall.seam.guide")
            Ponder62.presentList(from: self)
        }
        toolbar.onLayoutTapped = { [weak self] in self?.seamToggleLayout() }
        toolbar.onFullscreenTapped = { [weak self] in self?.seamSetImmersive(true) }
        seamToolbar = toolbar
        installHomeSeam85()

        buildSeamFilterBar(below: toolbar)
        buildSeamImmersiveExitRecognizer77()
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
        view.addSubview(bar)
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

    /// (77) ⑦沉浸退出改结构（推翻 (61) 的全屏透明热区
    /// 视图）：旧热区是根视图的一个子视图，靠
    /// bringSubviewToFront 抢层位——(76) 真机实证全屏点
    /// 按全灭（软锁，时段落在日志缺口内、具体覆盖者未定
    /// 案）。新结构不设任何全屏覆盖视图：退出识别器直接
    /// 挂根视图，根视图层级内一切子视图的点按都沿响应链
    /// 到达它，与兄弟视图 z 序无关；cancelsTouchesInView
    /// =false——退出点按不被吞、同一下继续穿透到墙面内
    /// 容。识别器仅在沉浸期 isEnabled，任何中间态都不存
    /// 在「全屏视图吞触摸」的构件。
    private func buildSeamImmersiveExitRecognizer77() {
        let recognizer = UITapGestureRecognizer(
            target: self, action: #selector(seamImmersiveTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.isEnabled = false
        view.addGestureRecognizer(recognizer)
        seamImmersiveExitRecognizer = recognizer
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
        // (83) 黑屏定案③：入墙预热——数据落地即把当前在
        // 场实例环封面按已解码档批量喂缓存（pf83 src=
        // warm），首屏与紧邻屏不再等滚动才开取。
        prefetchWall83(dirX: 0, dirY: 0, source: "warm")
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
        // (66) 切到网格时恢复落盘偏移（记住位置开时）。
        if showGrid, SettingsStore.rememberCardPositions {
            let savedY = CGFloat(SettingsStore.wallScrollOriginY)
            if savedY > 0 {
                grid.contentOffset = CGPoint(x: grid.contentOffset.x, y: savedY)
            }
        }
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

    /// 分区入口显隐（(62) §4.3、(74) 改消费点）：原侧栏分区行
    /// 随工作台撤除，分区收进工具条「…」菜单——本函数不再走
    /// 视图树改 isHidden，改把总开关＋5 页签开关算成映射存
    /// 表，seamMoreTapped 建菜单时按表过滤（关掉的分区不进
    /// 菜单）。映射口径不变：歌单→「歌单」、推荐→「电台」、
    /// 探索→「搜索」、专辑→「专辑」、本地→「本地」。
    func applyHomeTabs62Visibility() {
        let master = SettingsStore.homeTabsEnabled
        seamSectionVisibility62 = [
            "歌单": master && SettingsStore.showHomeTabPlaylists,
            "电台": master && SettingsStore.showHomeTabRecommend,
            "搜索": master && SettingsStore.showHomeTabExplore,
            "专辑": master && SettingsStore.showHomeTabAlbums,
            "本地": master && SettingsStore.showHomeTabLocal,
        ]
        Breadcrumbs.log("wall62.homeTabs master=\(master ? 1 : 0) carrier=menu")
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
        // (60) 第 2 条：沉浸隐藏走工具条双态入口——整条
        // 同藏，退出沉浸回落收起态（(86) 起收起态为头像＋
        // 无痕展开垫、无 grabber 线身）。
        seamToolbar?.setImmersiveHidden(on)
        seamFilterBar?.isHidden = true
        if on {
            // 提层（3.7 (61) 第 1.5 条，修沉浸假卡死结构缺陷）：
            // 原退出热区被 insertSubview 到工作台宿主之下，其上
            // 压着日记本层与宠物层，落点到不了热区、沉浸退不出
            // 来。进入沉浸时：①存覆盖层原状态；②日记本整层经
            // setExternallyCovered 藏起并穿透（把手/展开把手/
            // 热区一并不可命中）；③工作台宿主与宠物层关交互
            // （侧栏把手/悬浮头像等残留小件不可命中）；④退出
            // 热区 bringSubviewToFront 到全部覆盖层之上。退出
            // 时逐项恢复原层级与状态。
            if !wasImmersive {
                seamImmersiveSavedSketchbookCovered = sketchbookDrawer?.isExternallyCovered
                seamImmersiveSavedPetEnabled = miniPetStage?.isUserInteractionEnabled
            }
            if sketchbookDrawer?.isExternallyCovered == false {
                sketchbookDrawer?.setExternallyCovered(true)
            }
            // (74) 工作台宿主已撤除，沉浸中和名单只剩宠物层。
            miniPetStage?.isUserInteractionEnabled = false
            // (77) ⑦：退出识别器随沉浸启用（无覆盖视图、无
            // 层位可抢），展开自证 seam.lock77 in（仅真边沿）。
            seamImmersiveExitRecognizer?.isEnabled = true
            if !wasImmersive { Breadcrumbs.log("seam.lock77 in") }
            Breadcrumbs.log("wall.seam.immersive zorder raised=1")
            rootCloseButton?.isHidden = true
            miniBar?.alpha = 0
            miniBar?.isUserInteractionEnabled = false
        } else {
            // (77) ⑦：退出自证——点按退出记 via=tap pass=1
            // （识别器不取消触摸、同一下穿透到墙面内容）；
            // 其他路径退出记 via=other。
            seamImmersiveExitRecognizer?.isEnabled = false
            if wasImmersive {
                Breadcrumbs.log(traceEndReason == "exit-tap"
                    ? "seam.lock77 out via=tap pass=1"
                    : "seam.lock77 out via=other")
            }
            if wasImmersive {
                // 恢复原状态：日记本原本就被外部（侧栏）covered
                // 时不代为解除，只恢复沉浸自己加的那层。
                if let savedCovered = seamImmersiveSavedSketchbookCovered, !savedCovered {
                    sketchbookDrawer?.setExternallyCovered(false)
                }
                if let savedPet = seamImmersiveSavedPetEnabled {
                    miniPetStage?.isUserInteractionEnabled = savedPet
                }
                seamImmersiveSavedSketchbookCovered = nil
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
        guard seamImmersive else { return }
        // (61) 第 1.5 条 trace：退出点按落一行判读料——触点、
        // 命中链前三层（自顶向下含点图层类名）、热区帧。
        // (77) ⑦：热区帧 = 根视图 bounds（识别器挂根视图、
        // 无独立热区视图）。
        let point = gesture.location(in: view)
        InteractionTrace.shared.recordImmersiveTap(
            point: point,
            hitViewChain: seamHitViewChain(at: point),
            seamFrame: view.bounds,
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

    // port88：seamAvatarTapped（墙上点头像开账户卡）随工
    // 具条头像摘除整组退役——其全部调用方（转发链
    // "avatar" 动作）已同包摘除；账户卡入口只剩设置页账
    // 户组，侧栏深处入口保持整页 LoginViewController 不变。

    /// (62) 追加三：歌单页同款导航台的初始态读口（当前段 +
    /// 布局模式），歌单墙/歌单详情装配工具条时同步用。
    var seamToolbarInitialState: (segment: SeamSegment, grid: Bool) {
        (seamSegment, seamGridMode)
    }

    /// (85) 第 1 条：主页世界缝装配——撤 (84) 左缘固定条，
    /// 改网页版式「墙中间裂开的缝」：缝锚在世界块边界上、
    /// 随墙相机平移（帧由 wallLayout.seamGeometry85 逐帧
    /// 换算，实例让位在 WallLayout.rebuildAttributes 内）。
    /// z 序：点播台之下（台横贯底部中央、缝内容底内边距
    /// 已避台）、工具条之下。缝本体只认按钮命中（见
    /// HomeSeam85View），不吞墙面平移手势。
    private func installHomeSeam85() {
        guard homeSeam85 == nil else { return }
        let seam = HomeSeam85View()
        seam.isHidden = true
        if let bar = miniBar {
            view.insertSubview(seam, belowSubview: bar)
        } else if let toolbar = seamToolbar {
            view.insertSubview(seam, belowSubview: toolbar)
        } else {
            view.addSubview(seam)
        }
        seam.onFold = { [weak self] in self?.foldHomeSeam85() }
        // (89)B b-seam-present：四页签改走缝侧展开面板（分
        // 区 VC 以子 VC 嵌入面板内容区，不再全屏 present；
        // presentSidebarSection84 全屏路径保留给其他调用方）。
        seam.onPlaylists = { [weak self] in
            self?.presentSeamPanel89(
                tab: 0, title: "歌单", WorkbenchPlaylistListViewController())
        }
        seam.onRadio = { [weak self] in
            self?.presentSeamPanel89(
                tab: 1, title: "电台", WorkbenchRadioViewController())
        }
        seam.onAlbums = { [weak self] in
            self?.presentSeamPanel89(
                tab: 3, title: "专辑", WorkbenchAlbumListViewController())
        }
        seam.onLocal = { [weak self] in
            self?.presentSeamPanel89(
                tab: 4, title: "本地", WorkbenchLocalViewController())
        }
        // (89)B b-seam-tabs：探索复用工具条段控的现行入口
        // （seamSegmentSelected(.explore)，与 SeamToolbar-
        // View 的 segment-explore 同一通路，不新造数据路）。
        seam.onExplore = { [weak self] in
            guard let self else { return }
            self.closeSeamPanel89()
            self.homeSeam85?.selectedTabIndex = 2
            Breadcrumbs.log("port89 seamtab=explore")
            self.seamSegmentSelected(.explore)
        }
        // (89)B b-seam-tabs：Navidrome 只呈空态页（未接入
        // 本地库的 Navidrome 浏览在本地分区内另有入口；本
        // 页签不接 NavidromeClient62、不造假数据）。
        seam.onNavidrome = { [weak self] in
            guard let self else { return }
            self.closeSeamPanel89()
            self.homeSeam85?.selectedTabIndex = 5
            Breadcrumbs.log("port89 seamtab=navidrome-empty")
            let empty = SeamNavidromeEmpty89ViewController()
            empty.modalPresentationStyle = .fullScreen
            self.present(empty, animated: true)
        }
        // (89)B b-seam-narrow：书库标题切换 64/120 档。
        seam.onToggleWide89 = { [weak self] in self?.toggleHomeSeamWide89() }
        // (89)B b-seam-narrow：宽档初值与持久化档同步。
        seam.displayWide89 = SeamState85.narrow120
        seam.onLiked = { [weak self] in self?.openLikedPlaylist85() }
        // (86) 第 1 条：直达双列补云盘（呈现与命令面板
        // nav.cloud 同款：fullScreen）。
        seam.onCloud = { [weak self] in
            guard let self else { return }
            let drive = CloudDriveViewController()
            drive.modalPresentationStyle = .fullScreen
            self.present(drive, animated: true)
        }
        seam.onSearch = { [weak self] in
            guard let self else { return }
            SearchHostPresenter.presentSearch(from: self)
        }
        seam.onSettings = { [weak self] in
            guard let self else { return }
            let settings = SettingsViewController()
            settings.modalPresentationStyle = .overFullScreen
            self.present(settings, animated: false)
        }
        seam.onQueue = { [weak self] in
            guard let self else { return }
            QueueLatticeViewController.present(from: self)
        }
        seam.onMore = { [weak self] in self?.presentSeamMore85() }
        // (92) 任务 11：缝内版式开关写歌单页同一持久化键
        // （foliaPlaylistLayout91），歌单页出现时重读对齐；
        // 初值由缝视图自读同一键，不在此另设。
        seam.onLayoutMode92 = { mode in
            UserDefaults.standard.set(mode, forKey: "foliaPlaylistLayout91")
            Breadcrumbs.log("p92 plist mode=\(mode) src=seam")
            Breadcrumbs.log("p93 layout sw=\(SeamGlyph93.layoutName93(mode))")
        }
        // (93) C1：缝底控制台入口——与台面控制台钮同一落
        // 点（ConsolePanel82.present）。
        seam.onConsole93 = { [weak self] in
            guard let self else { return }
            ConsolePanel82.present(from: self)
        }
        // (93) C2：缝内日记本入口——DiaryViewController90
        // 无挂歌打开（tagged: nil），与控制台日记本钮同页。
        seam.onDiary93 = { [weak self] in
            guard let self else { return }
            let diary = DiaryViewController90(tagged: nil)
            diary.modalPresentationStyle = .fullScreen
            self.present(diary, animated: true)
        }
        homeSeam85 = seam
        let tab = SeamEdgeTab85View()
        tab.isHidden = true
        view.insertSubview(tab, belowSubview: seam)
        tab.onTap = { [weak self] in self?.reopenHomeSeam85() }
        seamEdgeTab85 = tab
        wallLayout.seamEnabled85 = true
        Breadcrumbs.log("seam85 on host=home hidden=\(SeamState85.levelHidden ? 1 : 0)")
    }

    /// 缝首规划：相机居中后按 seamPlan85 选界——首次直接
    /// 落位（入场视频掩盖、无需补间）；用户折叠后重开走
    /// reopenHomeSeam85 的补间路径。
    private func planHomeSeam85IfNeeded() {
        guard !seamPlanned85, didCenterCamera, homeSeam85 != nil else { return }
        seamPlanned85 = true
        if SeamState85.levelHidden {
            wallLayout.seamOpenWidth85 = 0
            updateSeam85Frame()
            return
        }
        // (89)B b-seam-narrow：开口宽读当前档（64/120）。
        let openW = seamOpenWidth89()
        let plan = wallLayout.seamPlan85(openWidth: openW, preferX: nil)
        wallLayout.seamAnchorX85 = plan.anchor
        wallLayout.worldOrigin.x = plan.originX
        wallLayout.seamOpenWidth85 = openW
        _ = wallLayout.refreshInstances()
        collectionView.reloadData()
        updateSeam85Frame()
        Breadcrumbs.log("seam85 plan host=home anchor=\(Int(plan.anchor))")
    }

    /// (89)B b-seam-narrow：当前档开口宽（书脊 64／窄缝
    /// 120，SeamState85.narrow120 单源）。
    private func seamOpenWidth89() -> CGFloat {
        SeamState85.narrow120 ? 120 : 64
    }

    /// 折叠：开口补间收 0（0.36s），等级落盘（跨面沿用）。
    private func foldHomeSeam85() {
        // (89)B b-seam-present：折叠缝连带收缝侧面板。
        closeSeamPanel89()
        SeamState85.levelHidden = true
        startSeamTween85(toWidth: 0, toOriginX: nil)
        Breadcrumbs.log("seam85 fold host=home")
    }

    /// 侧边标签重开：在当前视口重新选界（旧锚多半已出
    /// 界），相机让位＋开口补间同程（0.42s）。
    private func reopenHomeSeam85() {
        SeamState85.levelHidden = false
        // (89)B b-seam-narrow：重开回当前档宽（64/120）。
        let openW = seamOpenWidth89()
        let plan = wallLayout.seamPlan85(openWidth: openW, preferX: nil)
        wallLayout.seamAnchorX85 = plan.anchor
        seamPlanned85 = true
        startSeamTween85(toWidth: openW, toOriginX: plan.originX)
        Breadcrumbs.log("seam85 reopen host=home anchor=\(Int(plan.anchor))")
    }

    /// (89)B b-seam-narrow：点「书库」标题翻档——持久化
    /// 翻转、缝排版切档、按新宽重新选界并走既有补间重排
    /// （与 reopenHomeSeam85 同路）。
    private func toggleHomeSeamWide89() {
        let wide = !SeamState85.narrow120
        SeamState85.narrow120 = wide
        homeSeam85?.displayWide89 = wide
        let target = seamOpenWidth89()
        let plan = wallLayout.seamPlan85(openWidth: target, preferX: nil)
        wallLayout.seamAnchorX85 = plan.anchor
        seamPlanned85 = true
        startSeamTween85(toWidth: target, toOriginX: plan.originX)
        Breadcrumbs.log("port89 seamwide=\(wide ? 120 : 64)")
    }

    /// 缝开合补间（CADisplayLink 驱动：开口 0.36s、相机
    /// 0.42s 网页同量级，easeInOut；逐帧写 worldOrigin/
    /// seamOpenWidth85 并走既有帧重建路径，不 reloadData）。
    private func startSeamTween85(toWidth: CGFloat, toOriginX: CGFloat?) {
        seamTween85?.invalidate()
        seamTweenStart85 = CACurrentMediaTime()
        seamTweenFromWidth85 = wallLayout.seamOpenWidth85
        seamTweenToWidth85 = toWidth
        seamTweenFromOrigin85 = wallLayout.worldOrigin.x
        seamTweenToOrigin85 = toOriginX ?? wallLayout.worldOrigin.x
        seamTweenOrigin85 = toOriginX != nil
        let link = CADisplayLink(target: self, selector: #selector(seamTweenStep85(_:)))
        link.add(to: .main, forMode: .common)
        seamTween85 = link
    }

    @objc private func seamTweenStep85(_ link: CADisplayLink) {
        let duration = seamTweenOrigin85 ? 0.42 : 0.36
        let t = min(1, (CACurrentMediaTime() - seamTweenStart85) / duration)
        let e = t * t * (3 - 2 * t)
        wallLayout.seamOpenWidth85 = seamTweenFromWidth85
            + (seamTweenToWidth85 - seamTweenFromWidth85) * CGFloat(e)
        if seamTweenOrigin85 {
            wallLayout.worldOrigin.x = seamTweenFromOrigin85
                + (seamTweenToOrigin85 - seamTweenFromOrigin85) * CGFloat(e)
        }
        _ = wallLayout.refreshInstances()
        wallLayout.invalidateLayout()
        updateSeam85Frame()
        if t >= 1 {
            link.invalidate()
            if seamTween85 === link { seamTween85 = nil }
        }
    }

    /// 缝帧逐帧收口（滚动/布局/补间共用）：按 seamGeo-
    /// metry85 落缝视图帧与内容淡出、侧边标签显隐与贴边。
    /// 网格形态下缝不存在（另一面墙），整套隐藏。
    private func updateSeam85Frame() {
        guard let seam = homeSeam85 else { return }
        if seamGridMode || seamImmersive {
            seam.isHidden = true
            seamEdgeTab85?.isHidden = true
            // (89)B b-seam-present：网格/沉浸形态下缝不存在，
            // 缝侧面板随之隐藏（内容不拆、回墙形态恢复再显）。
            seamPanel89?.isHidden = true
            return
        }
        planHomeSeam85IfNeeded()
        let geo = wallLayout.seamGeometry85()
        let hidden = SeamState85.levelHidden
        if hidden || geo.width < 1 {
            seam.isHidden = true
        } else {
            seam.isHidden = false
            seam.frame = CGRect(
                x: geo.screenX - geo.width / 2, y: 0,
                width: geo.width, height: view.bounds.height)
            seam.contentTopInset = view.safeAreaInsets.top + 56
            seam.contentBottomInset = view.safeAreaInsets.bottom + 116
            // (89)B b-seam-narrow：淡出基准宽按当前档（64/120）。
            seam.contentOpacity = SeamState85.contentOpacity(
                rendered: geo.width, content: seamOpenWidth89())
        }
        // (89)B b-seam-present：面板锚缝右缘、随缝帧逐帧跟位。
        layoutSeamPanel89()
        // 侧边标签：折叠态恒显；开着但被平移挤出视口
        // （collapsed）时显在缝离开的那侧。首规划未成
        // （数据未到）前不显，免加载期边缘闪现。
        guard let tab = seamEdgeTab85 else { return }
        if seamPlanned85, hidden || geo.collapsed {
            tab.isHidden = false
            let side = hidden ? (geo.side == 0 ? -1 : geo.side) : geo.side
            let tabW: CGFloat = 20, tabH: CGFloat = 96
            tab.frame = CGRect(
                x: side < 0 ? 0 : view.bounds.width - tabW,
                y: view.bounds.height * 0.42,
                width: tabW, height: tabH)
        } else {
            tab.isHidden = true
        }
    }

    /// 中段直达入口「我喜欢的音乐」：在当前呈现集里找喜
    /// 欢歌单（网易云惯例：歌单名即「我喜欢的音乐」/以用
    /// 户名开头）打开其曲目墙（与点海报同路）；不在当前
    /// 集时给可见反馈、不静默。
    private func openLikedPlaylist85() {
        let idx = entries.indices.first { i in
            entries[i].title.contains("我喜欢的音乐")
        }
        guard let idx, idx < playlistIds.count else {
            NativePlaybackFailureToast.show(message: "喜欢歌单不在当前列表里")
            Breadcrumbs.log("seam85 liked miss")
            return
        }
        let entry = entries[idx]
        let wall = WallPrototypeViewController(
            playlistId: playlistIds[idx], title: entry.title, coverUrl: entry.picUrl)
        wall.modalPresentationStyle = .fullScreen
        wall.modalTransitionStyle = .crossDissolve
        beginPosterTransition(source: "seam-liked", playlistId: playlistIds[idx])
        wall.startPreload()
        Task { [weak self] in
            guard let self else { return }
            let seed = await wall.awaitSeed(timeout: playlistSeedWait96)
            self.present(wall, animated: true) { [weak self] in
                self?.endPosterTransition(source: "seam-liked", seedReady: seed)
            }
        }
    }

    /// 工具格「⋯」菜单（网页同位：本面项在前、app 级在
    /// 后）：管理隐藏（已隐藏歌单的恢复面，HiddenPlay-
    /// listsStore 真源）／回到播放页（有在播时开舞台）／
    /// 折叠缝。无对应原生面的项不列（不做假按钮）。
    private func presentSeamMore85() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let hidden = HiddenPlaylistsStore.shared.hiddenIds
        if !hidden.isEmpty {
            sheet.addAction(UIAlertAction(
                title: "恢复已隐藏歌单（\(hidden.count)）", style: .default) { _ in
                    // unhide 内部已发 .foliaHiddenPlaylistsChanged。
                    for id in hidden { HiddenPlaylistsStore.shared.unhide(id: id) }
                    Breadcrumbs.log("seam85 more unhide n=\(hidden.count)")
                })
        }
        if PlaybackEngine.shared.currentTrack != nil {
            sheet.addAction(UIAlertAction(
                title: "回到播放页", style: .default) { [weak self] _ in
                    self?.openNativeStageFromHome()
                })
        }
        sheet.addAction(UIAlertAction(title: "折叠缝", style: .default) { [weak self] _ in
            self?.foldHomeSeam85()
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = homeSeam85 ?? view
            pop.sourceRect = CGRect(x: 32, y: view.bounds.height - 200, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    // port88：avatarLocate85（(85) 第 2 条点头像＝定位正在
    // 播放）随头像摘除整组退役——两处绑定（工具条/主页缝）
    // 已摘、本体无调用方。台身标题区单击定位
    // （locateCurrentTrackFromCover）是另一入口、不在本退役
    // 范围，原样保留。

    /// 分区页呈现（与 WorkbenchOverlayHostView.present-
    /// SectionVC 同式：fullScreen＋dismissToWall 回墙）。
    /// (89)B 起缝页签改走缝侧面板（presentSeamPanel89），
    /// 本全屏路径保留给其他调用方、原样不动。
    private func presentSidebarSection84(_ vc: WorkbenchSectionViewController) {
        vc.dismissToWall = { [weak self] in
            self?.dismiss(animated: true)
        }
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    // MARK: (89)B b-seam-present 缝侧展开面板
    //
    // 网页口径：点集合＝缝变 300 信息条＋列表面板、不离
    // 墙。原生落点：面板锚在缝右缘（宽 min(300, 屏宽−
    // 缝右缘−12)、上下与缝内容 insets 同域），毛玻璃底；
    // 头条＝返回钮＋分区标题＋计数；内容区内嵌分区 VC
    // （presentSidebarSection84 的同一批目标 VC、无导航
    // 包装——原实现即裸 VC fullScreen 呈出，故照原样以
    // 子 VC containment 嵌入，不加包装）。

    /// 开面板/切内容：已有子 VC 先全套摘除再嵌新的；页
    /// 签选中态同步（selectedTabIndex）。
    private func presentSeamPanel89(
        tab: Int, title: String, _ vc: WorkbenchSectionViewController) {
        let panel = seamPanel89 ?? buildSeamPanel89()
        removeSeamPanelChild89()
        // 点播回墙收口改指面板：先关分区页自己再呈出的面
        // （曲目列表等由分区页 present），再收面板。
        vc.dismissToWall = { [weak self, weak vc] in
            vc?.dismiss(animated: true)
            self?.closeSeamPanel89()
        }
        guard let content = seamPanelContent89 else { return }
        addChild(vc)
        content.addSubview(vc.view)
        seamPanelChild89 = vc
        vc.view.frame = content.bounds
        vc.view.layoutIfNeeded()
        layoutSeamPanelContent89()
        vc.didMove(toParent: self)
        seamPanelTab89 = tab
        seamPanelTitle89?.text = title
        seamPanelMeta89?.text = nil
        homeSeam85?.selectedTabIndex = tab
        panel.isHidden = false
        layoutSeamPanel89()
        refreshSeamPanelMeta89()
        // 分区数据多为异步回填：1s 后按表中实数再刷一次计数。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak vc] in
            guard let self, self.seamPanelChild89 === vc else { return }
            self.refreshSeamPanelMeta89()
        }
        Breadcrumbs.log("port89 seampanel=open tab=\(tab)")
    }

    /// 面板本体（懒建）：毛玻璃（UIVisualEffectView＋黑
    /// 0.25 tint）＋头条（返回 32×32 chevron.left／标题
    /// 16 semibold／计数 12pt 白 0.6）＋内容区（裁剪，子
    /// VC 视图嵌入）。z 序与缝同格：点播台/工具条之下。
    private func buildSeamPanel89() -> UIView {
        let panel = UIView()
        panel.layer.cornerRadius = 16
        panel.clipsToBounds = true
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.frame = panel.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        panel.addSubview(blur)
        let tint = UIView()
        tint.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        tint.frame = panel.bounds
        tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        panel.addSubview(tint)
        let back = UIButton(type: .system)
        back.setImage(UIImage(
            systemName: "chevron.left",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 14, weight: .semibold)), for: .normal)
        back.tintColor = .white
        back.accessibilityLabel = "返回"
        back.addTarget(self, action: #selector(seamPanelBackTapped89),
                       for: .touchUpInside)
        back.tag = 8901
        panel.addSubview(back)
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        panel.addSubview(titleLabel)
        seamPanelTitle89 = titleLabel
        let metaLabel = UILabel()
        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        panel.addSubview(metaLabel)
        seamPanelMeta89 = metaLabel
        let content = UIView()
        content.clipsToBounds = true
        panel.addSubview(content)
        seamPanelContent89 = content
        if let bar = miniBar {
            view.insertSubview(panel, belowSubview: bar)
        } else if let toolbar = seamToolbar {
            view.insertSubview(panel, belowSubview: toolbar)
        } else {
            view.addSubview(panel)
        }
        seamPanel89 = panel
        return panel
    }

    /// 面板逐帧定位（updateSeam85Frame 尾调）：锚缝右缘，
    /// 上下＝缝内容 insets 同域；缝隐藏/面板未开时只隐藏
    /// 不拆（折叠缝的拆除走 closeSeamPanel89）。
    private func layoutSeamPanel89() {
        guard let panel = seamPanel89 else { return }
        guard let seam = homeSeam85, !seam.isHidden else {
            panel.isHidden = true
            return
        }
        let x = seam.frame.maxX
        let w = min(300, view.bounds.width - x - 12)
        let top = seam.contentTopInset
        let bottom = view.bounds.height - seam.contentBottomInset
        panel.frame = CGRect(
            x: x, y: top, width: max(0, w), height: max(0, bottom - top))
        panel.isHidden = w < 40
        // 头条排版：返回钮 32×32 左 10；标题/计数两行在其右。
        if let back = panel.viewWithTag(8901) {
            back.frame = CGRect(x: 10, y: 10, width: 32, height: 32)
        }
        seamPanelTitle89?.frame = CGRect(
            x: 52, y: 8, width: max(0, w - 62), height: 20)
        seamPanelMeta89?.frame = CGRect(
            x: 52, y: 29, width: max(0, w - 62), height: 14)
        seamPanelContent89?.frame = CGRect(
            x: 0, y: 52, width: max(0, w), height: max(0, bottom - top - 52))
        layoutSeamPanelContent89()
    }

    /// 子 VC 视图落位：分区页自带顶栏（关闭钮＋标题）由
    /// 面板头条代行——把子视图上移其 contentView 起点，
    /// 内容区裁剪正好藏起子顶栏，列表本体自内容区顶起。
    private func layoutSeamPanelContent89() {
        guard let content = seamPanelContent89,
              let vc = seamPanelChild89, vc.view.superview === content
        else { return }
        vc.view.frame = content.bounds
        vc.view.layoutIfNeeded()
        let shift = vc.contentView.frame.minY
        vc.view.frame = CGRect(
            x: 0, y: -shift, width: content.bounds.width,
            height: content.bounds.height + shift)
    }

    /// 子 VC 全套摘除（willMove/removeFromParent 成套）。
    private func removeSeamPanelChild89() {
        guard let vc = seamPanelChild89 else { return }
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        seamPanelChild89 = nil
    }

    /// 收面板：摘子 VC、拆面板本体、页签选中态回歌单
    /// （主页墙本体即歌单集）。未开时静默。
    private func closeSeamPanel89() {
        guard seamPanel89 != nil else { return }
        removeSeamPanelChild89()
        seamPanel89?.removeFromSuperview()
        seamPanel89 = nil
        seamPanelTitle89 = nil
        seamPanelMeta89 = nil
        seamPanelContent89 = nil
        seamPanelTab89 = -1
        if let seam = homeSeam85, seam.selectedTabIndex != 0 {
            seam.selectedTabIndex = 0
        }
        Breadcrumbs.log("port89 seampanel=close")
    }

    @objc private func seamPanelBackTapped89() {
        closeSeamPanel89()
    }

    /// 头条计数：分区 VC 的条数在其私有数组内（本包文件
    /// 范围外不可直读），改读内嵌列表的实时行数——显示
    /// 的就是计数的，不造数；无表/无行时留空。
    private func refreshSeamPanelMeta89() {
        guard let vc = seamPanelChild89, let meta = seamPanelMeta89,
              let table = findSeamPanelTable89(in: vc.view) else { return }
        var count = 0
        for section in 0..<table.numberOfSections {
            count += table.numberOfRows(inSection: section)
        }
        meta.text = count > 0 ? "\(count) 项" : nil
    }

    private func findSeamPanelTable89(in root: UIView) -> UITableView? {
        if let table = root as? UITableView { return table }
        for sub in root.subviews {
            if let table = findSeamPanelTable89(in: sub) { return table }
        }
        return nil
    }

    /// port88 瘦身：原「缝账户回显」的两路 UI 回填（工具条
    /// 头像 setAccount、主页缝头像 setAccount85）随头像摘除
    /// 退役；本函数只剩资料缓存刷新一职——fetchLoginStatus
    /// 回程把网易云资料回填 NativeSessionStore（(62) 尾波
    /// 第 3 组口径：网络值落盘，侧栏账户区/设置页账户组同
    /// 源读它）。露面调用点不变（viewWillAppear）。
    func seamRefreshAccount() {
        Task { [weak self] in
            guard let self else { return }
            let status = try? await NativeDataClient.shared.fetchLoginStatus()
            await MainActor.run {
                guard let status else { return }
                if status.loggedIn {
                    NativeSessionStore.shared.saveProfile(
                        provider: .netease, accountId: status.userId,
                        displayName: status.nickname,
                        avatarURLString: status.avatarURL)
                }
                Breadcrumbs.log("wall.seam.account fetch loggedIn=\(status.loggedIn) avatar=\(status.avatarURL != nil ? 1 : 0)")
            }
        }
    }

    // (77) ④「…」菜单整页取消：seamMoreTapped 与其专属落点
    // （喜欢歌单直达/分区页呈现）随页摘除；连带功能去向见
    // (77) 报告④。过滤条与隐藏管理页本体保留（dormant，
    // 无入口——报告已明示随页取消、不悄悄蒸发）。

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

// (84) 第 3 条：(82) 的 UIGestureRecognizerDelegate 祖先链
// 豁免扩展整套删除——台身识别器已改挂背景手势层（按钮的
// 兄弟层、非祖先），豁免失去存在前提（DS 定案）。

/// (89)B b-seam-tabs：Navidrome 页签空态页——只呈标题与
/// 「暂未接入」文案，不接 NavidromeClient62、不造假数据
/// （真浏览入口在本地分区内，本页签待后续包接通）。
final class SeamNavidromeEmpty89ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(
            red: 22.0 / 255, green: 22.0 / 255, blue: 27.0 / 255, alpha: 1)
        let titleLabel = UILabel()
        titleLabel.text = "Navidrome"
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        let noteLabel = UILabel()
        noteLabel.text = "暂未接入"
        noteLabel.font = .systemFont(ofSize: 14)
        noteLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        noteLabel.textAlignment = .center
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(noteLabel)
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 15, weight: .semibold)), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        closeButton.layer.cornerRadius = 16
        closeButton.accessibilityLabel = "关闭"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped89),
                              for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(
                equalTo: view.centerYAnchor, constant: -16),
            noteLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            noteLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor, constant: 8),
            closeButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            closeButton.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @objc private func closeTapped89() {
        dismiss(animated: true)
    }
}
