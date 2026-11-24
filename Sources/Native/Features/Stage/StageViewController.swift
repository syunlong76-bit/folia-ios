import UIKit
import Combine
import QuartzCore
import PhotosUI
import UniformTypeIdentifiers
import WebKit

// 原生舞台页壳（3.7 (14)，M2'）：全屏舞台——封面氛围背景、
// LyricStage 协议驱动的歌词面、与迷你台/展开卡同一命令入口的
// 控制层。入口由双墙迷你台/双击卡片改道至此（网页 openStage
// 保留为回退与未迁样式的去处，不删）。
//
// 命令入口（与现役双墙逐行同构，全仓无 PlayerAction 枚举）：
//  toggle → PlaybackEngine.togglePlayPause；next/prev →
//  QueueManager.playNext(manual:)/playPrevious；seek →
//  PlaybackEngine.seek(to:)；红心 → LikesStore.toggle + 云端
//  setLike 同步（失败回滚，同展开卡 likeTapped）。
final class StageViewController: UIViewController {

    /// (79) 第 6 条：舞台本体补状态栏隐藏——(78) 报告把同
    /// 文件 WebStageHostViewController 的 override 记错到
    /// 本类头上，本体实际缺失、播放页时钟必现。本版与另
    /// 四页（主页/歌单/拼贴/入场）对齐恒隐藏。
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

    /// 跳网页舞台（用户选未迁样式 / 提示条回网页 / 挂载失败回退）：
    /// 3.7 (51) 起不再由墙 VC 注入回调——回程票链已整链删除，
    /// jumpToWebStage 改为本台自身叠加 present 网页宿主（见文件
    /// 尾 WebStageHostViewController），关网页舞台 dismiss 即回
    /// 本台。原 onRequestWebStage 注入点随之退役。

    private let engine = PlaybackEngine.shared
    private let queueManager = QueueManager.shared

    // MARK: 视图

    // 自定义背景层（3.7 (47)）：舞台最底层，位于宿主封面
    // 氛围三件套之下；生效时三件套隐藏、底图换成用户自选
    // 的图片/动图/视频。装配与播放控制见文件尾 custombg 段。
    private let customBgView = CustomBackgroundView()
    private let backdropImageView = UIImageView()
    private let backdropBlur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let backdropTint = UIView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let likeButton = UIButton(type: .system)
    private let styleButton = UIButton(type: .system)
    private let noticeBar = UIView()
    private let noticeLabel = UILabel()
    private let noticeWebButton = UIButton(type: .system)
    private let noticeCloseButton = UIButton(type: .system)
    private let rendererContainer = UIView()
    // (62) WA 预留：WD 簇墙后画面挂载点——位于背景层之上、
    // renderer 容器之下；viewDidLoad 调 StageBackdrop62.attach。
    let backdrop62Container = UIView()
    // (62) WA 新增面：舞台歌曲卡 / 声线追踪 / 常显切歌箭头 / 顶栏模糊。
    private let trackPill62 = TrackPill62()
    private let soundTracing62 = SoundTracingView62()
    private var headerBlur62: UIVisualEffectView?
    private let alwaysPrev62 = UIButton(type: .system)
    private let alwaysNext62 = UIButton(type: .system)
    private var stageBarDragStartHeight62: CGFloat = 70
    // 底部字幕层已于 (60) 第 11 条整组删除（SubtitleOverlayView/
    // SubtitleSettingsPanel/SubtitleSettingsStore 三文件退役）：
    // 特效画面不再有宿主级小字行。汪汪队底部提词条 teleBar 已
    // 于 (65) A 组在渲染器内整条摘除（v3b 定版无下胶囊条）。
    // 点播台（3.7 (32) 同步改造）：原固定 128pt 控制带（私有
    // 进度条 + 时间标签 + 44/64/44 三键）整体换成与墙台同规
    // 格的点播台——70pt 玻璃胶囊 + 同款主题层 + 可拖进度轨，
    // 闲置 5 秒收成 16pt 细条（命中带 44pt）；去重变体：不
    // 带封面缩略与标题/歌手行（页眉已有），只留控制与进度
    // + 时间标签。实现见文件内「点播台」MARK 段，与墙台的
    // 参数逐项对齐（弹簧/时长/填充色/圆点皮肤）。
    private let stageBar = MiniBarHitView()
    // (68) B 组出样：全宽控制条与其点屏识别器（开关缺省关，
    // 关时识别器 disabled、本条恒隐藏，舞台行为与现行一致；
    // 本体在 StageWideBar68.swift，可整体摘除）。
    private var wideBar68: StageWideBar68?
    private var wideBarTap68: UITapGestureRecognizer?
    private var stageBlurView: UIVisualEffectView?
    /// (84) 第 3 条：台身手势背景层（按钮的兄弟层，同两面墙）。
    private var stageDeckSurface84: UIView?
    private var stageThemeLayer: MiniPlayerThemeLayer?
    private var stageRimLight: UIView?
    private var stageGlassTint: UIView?
    private var stageProgressTrack: UIView?
    private var stageProgressFill: UIView?
    private var stageProgressKnob: UIView?
    private var stageKnobSkin: UIView?
    private var stageSeekHit: UIView?
    private let currentTimeLabel = UILabel()
    private let totalTimeLabel = UILabel()
    private let prevButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    /// (82) 第 7/8 条：E 极简台补件——台内封面/歌名/歌手
    /// （与两面墙同位同尺寸）＋控制台入口圆钮。旧模式钮/
    /// 爪印/槽位钮保留对象但不再上台（职能进控制台），
    /// 既有回刷代码对未上台视图无副作用。
    private let stageConsoleButton82 = UIButton(type: .system)
    private let stageCover82 = UIImageView()
    private let stageTitle82 = UILabel()
    private let stageArtist82 = UILabel()
    /// (83) 第 6 条：实际上台的模式钮/列表钮（网页版紧凑
    /// 台，控制行两端）——与下文 stageModeButton（(55) 模
    /// 板对象、(82) 起不上台、仅供菜单/状态回刷）分工不
    /// 混用，菜单动作同源（写 QueueManager.playMode）。
    private let stageModeButton83 = UIButton(type: .system)
    private let stageListButton83 = UIButton(type: .system)
    private var stageTrackTopC: NSLayoutConstraint?
    /// 主排模式可见钮（3.7 (55) 工作流 D/DS 修正3）：主排右侧紧凑
    /// 钮，glyph 随 QueueManager.playMode 四档变，点按弹 UIMenu
    /// 四档点选（非盲循环）；与队列面板/播放面板同一 playMode 存储。
    private let stageModeButton = UIButton(type: .system)
    /// (79) 第 1 条：舞台台面常驻爪印钮（模式钮右侧、总时长
    /// 标签左侧的 24pt 窄位——舞台主排已满，此位为唯一空隙）。
    private let stagePawButton = DeckPawButton79()
    /// (81) 第 7 条：宠物专属带上次下发值（变化才落痕）。
    private var lastPetBand81: CGFloat = -1
    /// (66) 进度条两端功能槽位钮（barSlotLeft62/Right62 的
    /// 消费者）：落在时间标签与中央簇之间的空隙，不动 (55)
    /// 定版五钮浮层；配置随 refresh62Settings 重建。
    private let stageSlotLeft66 = UIButton(type: .system)
    private let stageSlotRight66 = UIButton(type: .system)
    /// (66) 点播台顶缘拖高柄（设置「在播放页拖动调整」的
    /// 定位脉冲目标）。
    private var stageBarDragHandle66: UIView?
    // 播放列表图标（顶栏 queueButton）已于 (60) 第 10 条删除：
    // 队列入口保留点播台面板页签与命令面板，QueuePanel 本体不动。
    private var stageBarWidthConstraint: NSLayoutConstraint?
    private var stageBarHeightConstraint: NSLayoutConstraint?
    private var stageBarBottomC: NSLayoutConstraint?
    private var stageTrackBottomConstraint: NSLayoutConstraint?
    /// (74) 小横线形态的轨道约束组（同两面墙台口径）。
    private var stageTrackLeadC: NSLayoutConstraint?
    private var stageTrackTrailC: NSLayoutConstraint?
    private var stageTrackHeightC: NSLayoutConstraint?
    private var stageTrackCenterXC: NSLayoutConstraint?
    private var stageTrackWidthC: NSLayoutConstraint?
    /// 点播台附加功能行（3.7 (54) 工作流 H 建、(60) 第 7 条迁
    /// 浮层）：五钮行（喜欢/星标/打乱/面板/命令，字幕钮已随第
    /// 11 条删）不再装进点播台本体，改住透明浮层
    /// （MiniBarQuickRowOverlayView）挂本 VC 的 view、锚台顶上
    /// 方 8pt；台高恢复 70（expandedBarHeight）。stageQuickRow
    /// 指向浮层内的行本体（回调接线用），浮层显隐与点播台 5 秒
    /// 闲置同钟、点台身空白区呼出、点浮层外收起（见 quickrow
    /// overlay 段）。喜欢态变化经回调同步顶栏红心。
    private var stageQuickRow: MiniBarQuickRowView?
    private var stageQuickRowOverlay: MiniBarQuickRowOverlayView?
    private var stageQuickRowHideWorkItem: DispatchWorkItem?
    private var stageMainCenterY: [NSLayoutConstraint] = []
    private var stageKnobLeading: NSLayoutConstraint?
    private var stageTheme: MiniPlayerTheme = MiniPlayerTheme.effective
    private var stageBarCollapsed = false
    /// 台身双击识别器（3.7 (61) 第 7 条）：随台形态启停——收
    /// 起态禁用以保细条单击即时展开（见 syncStageBarDouble-
    /// TapEnabled）。
    private var stageBarDoubleTap: UITapGestureRecognizer?
    /// (78) 第 8 条：播放条根级认领（见 MiniBarRootTap78）。
    private var stageBarRootTap78: MiniBarRootTap78?
    private var stageBarPresented = false
    private var stageSeekDragging = false
    /// seek 落点保持窗（3.7 (70) B4）：.ended 发 seek 后、
    /// 驱动重锚收敛前冻结驱动写点，免落点回跳；目标秒数
    /// 与截止时刻（+300ms）成对记，任一满足即放行。
    private var seekHoldTarget70: TimeInterval?
    private var seekHoldDeadline70: CFTimeInterval = 0
    /// 拖动期被守卫挡下的驱动回调计数（seek 落点时一行
    /// 面包屑自证 seek.guard）。
    private var seekGuardBlocked70 = 0
    private var stageIdleWorkItem: DispatchWorkItem?
    private var stagePetStage: MiniBarPetStage?
    /// (74) 本页缝合工具条（三页清单之三，播放详情页）。
    private var stageSeamToolbar: SeamToolbarView?
    /// (75) 工具条双向约束组（竖屏绕岛带／横屏 (74) 侧锚），
    /// 与主页墙同构（applySeamBandOrientation 二选一激活）。
    private var seamBandPortrait: [NSLayoutConstraint] = []
    private var seamBandLandscape: [NSLayoutConstraint] = []
    private var seamBandIsPortrait: Bool?

    // MARK: 状态

    private var context: LyricStageContext!
    private var renderer: LyricStageRenderer?
    private var activeStyleId: String = LyricStageRegistry.defaultStyleId
    /// 网页运行嵌入态（3.7 (67) A2/A4）：当前以网页运行呈现
    /// 的样式 id（nil=原生呈现）；webBackingRenderer 是淡换期
    /// 间垫底的旧原生渲染器，回执/超时淡换完成后才拆。
    private var webEmbedStyleId: String?
    private weak var webBackingRenderer: LyricStageRenderer?
    private var webSwapGeneration = 0
    private var webFadeWorkItem: DispatchWorkItem?
    /// 网页→网页切换快照盖（3.7 (70) B6）：切换前对当前
    /// WebView 的截图覆盖层，压住页面自切的清屏帧；首帧回
    /// 执/超时在 completeWebFade 同一出口交叉淡出后摘除。
    private var webSwitchCover70: UIView?
    /// (81) 第 3 条：特效层旋转盖——旋转冻结拍对 WebView
    /// 截图盖住网页层，转场期只随容器弹性拉伸（不再被系
    /// 统快照当刚性平面倾斜）；落定后等网页层新尺寸首帧
    /// 回执（或 0.9s 超时）才交叉淡出。量测三点落
    /// webfx.rot81（freeze/landed/ready），下轮日志可量化。
    private var webRotCover81: UIImageView?
    private var webRotRevealWork81: DispatchWorkItem?
    private var webRotGen81 = 0
    private var webRotStart81: CFTimeInterval = 0
    /// §0 量测节流（3.7 (67) B 组）：tick.pos 每 30 帧一行、
    /// sync.per5 每 5 秒一行。
    private var syncProbeTickCount = 0
    private var lastSyncPer5At: CFTimeInterval = 0
    private var anchor = PlaybackAnchor(
        trackId: "", positionAtAnchor: 0,
        wallTimeAtAnchor: CACurrentMediaTime(), rate: 0, anchorSeq: 0)
    private var cancellables = Set<AnyCancellable>()
    private var linesCache: [String: [LyricLine]] = [:]
    private var palette: PaletteTokens = .neutralDark
    private var currentTrackId: String? = nil
    private var backdropTrackId: String? = nil
    private var lyricsTask: Task<Void, Never>?
    private var backdropTask: Task<Void, Never>?
    /// (80) 切歌边沿时刻（handleTrackChanged 入口记）：歌词
    /// 就绪延迟 prep.ms80 的起点，与 loadLyrics 各落定路径对位。
    private var lyricSwitchAt80: CFTimeInterval = 0

    // 贴纸层（3.7 (24)，纯新增视图层）：拉歌词角标（renderer
    // 容器右上）、无歌词陪衬（容器居中）、红心庆祝（容器右
    // 上内侧）。方法全在文件尾 extension；显隐只由既有取
    // 词/点赞落点的一行钩子驱动，不改任何歌词/时钟逻辑。
    private var stickerFetchBadge: StickerView?
    private var stickerNoLyrics: StickerView?
    private var stickerLike: StickerView?
    private let progressDriver = StageProgressDriver()
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var frameDurations: [Double] = []
    private var driftTimer: Timer?
    /// 舞台速退探针（3.7 (41) 组2取证，只记日志不改逻辑）：
    /// SceneDelegate 每次 route 派发开台/归位时以 Date() 武装；
    /// 本台若在 3 秒内被 dismiss，viewWillDisappear 落
    /// `nowplaying.route stage-exit-quick dt=` 面包屑，供下轮
    /// 定性「开台约 1 秒舞台消失」是手动关还是自动退。
    static var routeExitProbeArmedAt: Date?
    /// 本台在 StageExitGate 的登记 token（3.7 (46)）：viewDidLoad
    /// 时向闸门登记 canonical 实例并领取，route 成功校验与全部
    /// 退出面包屑按它对齐实例。(45) 的 gateEventSeq 推断式自弃
    /// 已随 DS 定案废除——用户意图只认显式信号。
    private(set) var stageToken = "-"
    /// 防卡死守卫证明状态（3.7 (44) 建，(45) R-4 补口径）：
    /// mountRenderer 装配样式时武装 pending 并重置此处状态。
    /// (44) 口径只看帧存活（满 60 帧或 2 秒），两个缺口
    /// （审计候选 4）：①开台后立刻被切后台/正常关台的健康
    /// 样式 pending 未清，下次启动遭误报回退；②帧能跑只证
    /// 明 frameTick 存活，成图落地、歌词到货等异步完成点若
    /// 崩在证明之后，守卫不会回退、死循环可复现。(45) 证
    /// 明条件改为三路任一：帧条件（60 帧/2s）与「歌词首次
    /// applied」两者皆达（via=frames+lyrics）；或开台存活
    /// 满 5 秒兜底（via=window，覆盖无歌词/纯器乐等歌词永
    /// 不到货的场面）；或舞台正常 teardown（via=teardown，
    /// 开过又正常关掉 = 活过）。进程未及任一证明就消亡时，
    /// pending 留给下次启动的 runLaunchStyleGuard 回退。
    private var styleProofStyleId: String?
    /// 样式打开追踪状态（3.7 (61) 第 3 条）：mountRenderer 每次
    /// 装配重置；frameStep 首帧提交后落 style.firstFrame
    /// .commit.alive 并推进 StyleOpenTrace 标记（只触发一次）。
    private var styleTraceStyleId: String?
    private var styleTraceDataHash = ""
    private var styleTraceFirstFrameLogged = false
    /// (63) DS R63 埋点状态：装配相位（pre=未装配/mount=装配
    /// 中/ready=装配完成），供 swap.begin 标注换装落在哪个
    /// 相位（候选 2 判别）；首 tick 面包屑只落一次锁存。
    private var asmPhase63 = "pre"
    private var didLogFirstTick63 = false
    private var styleProofFrames = 0
    private var styleProofArmedAt: CFTimeInterval = 0
    private var styleProofFramesOK = false
    private var styleProofLyricsApplied = false
    /// settle 稳态重锚（3.7 (41) 组3，移植墙面 LyricClockDriver
    /// (20) 定案纪律）：瞬态锚（开台/切歌/播停翻转）在 +0.35s
    /// 做一次无条件稳态重锚，纠正起播瞬态锚的亚阈值恒定相位
    /// 差（舞台此前无 settle、阈值死区内恒差可整场存活——
    /// 审计 lyric-sync 候选 1）。窗口内漂移重锚可重新武装，
    /// 上限 3 次（墙面 (22) 同口径）。
    private var settleTimer: Timer?
    private var settleReanchorAt: CFTimeInterval?
    private var settleTrackId: String?
    private var settleRearmCount = 0
    private static let settleWindow: CFTimeInterval = 0.35
    private static let settleRearmLimit = 3
    /// 舞台行级面包屑去重状态（3.7 (41) 组3）：只在（曲目,
    /// 行号）变化时落盘，与墙面 lrc line 同口径。
    private var lastStageLineTrackId: String?
    private var lastStageLineIndex: Int?
    /// sync.probe 扫光 50% 过线状态位（3.7 (53) 工作流 F，
    /// 只埋点不改行为）：记住已落屑的（曲目, 行号），每行
    /// 只触发一次；当前行与记录不符即视为新行未过线（行
    /// 切换/切曲时自然复位，无额外重置点）。
    private var syncProbeSweepTrackId: String?
    private var syncProbeSweepLineIndex: Int?
    private var gateTimer: Timer?
    private var lastLayoutSize: CGSize = .zero
    /// (76) 旋转管线对齐墙面 (73) 的四件：代际计数、冻结
    /// 旗（冻结期 layoutStage 只记待办、不以中间 bounds
    /// 反复全量重算）、待重排旗、本代 layoutStage 运行次
    /// 数（落定自证 runs=，目标与墙面同级 = 1）。
    private var stageRotationGeneration = 0
    /// (82) 第 6 条：rot82 量测起点（旋转开始时刻，landed/
    /// ready 两点同源计时；全样式落痕、不再只限网页嵌入）。
    private var stageRotStart82: CFTimeInterval = 0
    /// (84) 第 5 条：本次旋转的 freeze→ready 毫秒（原生路
    /// 径在 alongside 布局落定点写、网页路径在揭盖点写）；
    /// landed 汇总时读，−1＝ready 未达。
    private var stageRotReadyMs84: Int = -1
    private var stageRotationFrozen = false
    private var stageLayoutPending = false
    private var stageLayoutRuns = 0
    /// (86) 第 9 条：alongside 已排轮的几何（尺寸＋安全
    /// 区），completion 据此判补轮——一致即零补轮、landed
    /// runs 收敛为 1（(85) 实锤旧法解冻后中间 bounds 反复
    /// 触发全量 layoutStage、横→竖 runs=6／f2l=329ms）。
    private var stageRotLaidSize86: CGSize = .zero
    private var stageRotLaidInsets86: UIEdgeInsets = .zero
    private var lastTimeLabelSecond = -1
    private var tornDown = false
    private var webJumpFired = false
    private var noticeDismissed = false

    // MARK: 顶栏自动隐藏（3.7 (46)，Miller 规格）
    //
    // 顶栏整条（歌名/歌手/喜欢/样式胶囊/关闭）开台或恢复后 5 秒
    // 无操作淡出隐藏；单击不触发恢复（仅在顶栏可见时顺延隐藏
    // 计时）；淡入淡出走 iOS 系统弹簧/自然减速；全样式通用
    // （页眉在本控制器层、与渲染器无关）；底部播放条不动。隐
    // 藏只是 alpha/显隐，与 StageExitGate 的退出守卫无关
    // （隐藏≠退出）。（74）恢复口径按 Miller 更正：单击显示
    // 歌名（经 require(toFail: 三击) 的时序门，见装配处）、
    // 双击绑歌名已摘除，另有 appear/track-change/设置关自
    // 动隐藏三源。

    private var headerHideWorkItem: DispatchWorkItem?
    /// (76) 单击显示歌名的时序门状态：待触发的 show 排期
    /// 与三击抑制窗（见 stageHeaderSingleTapped74）。
    private var headerShowWorkItem: DispatchWorkItem?
    private var headerShowSuppressUntil: TimeInterval = 0
    private var headerChromeHidden = false
    /// (74) 第 9 项（更正口径）：单击显示歌名识别器——须等
    /// 三击识别失败才触发（require(toFail:)），故存引用待
    /// 三击装配时接线。三击识别器同存（接线与自证用）。
    private var stageHeaderSingleTap74: UITapGestureRecognizer?
    private var stageTripleTap74: UITapGestureRecognizer?

    private var stageHeaderViews: [UIView] {
        // (53) H 修正：播放列表入口曾在本顶栏隐藏排；(60) 第 10
        // 条已删该钮（queueButton），名单同步摘除。
        [closeButton, titleLabel, artistLabel, likeButton, styleButton]
    }

    private func installStageHeaderAutoHideRecognizers() {
        // (74) 第 9 项（Miller 19:48 更正口径，覆盖先前一版）：
        // 本页点按正道＝单击显示歌名、三击只切特效。
        // ①双击绑歌名的识别器已整路摘除（原 stageHeader-
        //   DoubleTapped 及其 view 级双击识别器删除）——双击
        //   不再有任何歌名行为；
        // ②单击显示歌名：singleTap74 的回调走 (76) 显式时
        //   序门（排 0.35s、三击识别取消＋抑制窗）——三击
        //   序列中歌名全程不出现（治旧病：三击途中点按被
        //   先行识别、切特效时歌名跟着闪）；真单击延迟约
        //   一个多击窗口（≈0.35s，Miller 已认可接受范围）。
        //   原 (74) 的 require(toFail: 三击) 跨视图接线已
        //   摘除（(76) ⑦静态审：接线完整但啮合不可证、真
        //   机失效，见 stageHeaderSingleTapped74 注）；
        // ③单击观察器保留：不消费触摸、只在顶栏可见时即时
        //   顺延隐藏计时（不等 ②的延迟，防计时在延迟内到点）。
        let singleTap74 = UITapGestureRecognizer(
            target: self, action: #selector(stageHeaderSingleTapped74))
        singleTap74.cancelsTouchesInView = false
        view.addGestureRecognizer(singleTap74)
        stageHeaderSingleTap74 = singleTap74
        let tapObserver = UITapGestureRecognizer(
            target: self, action: #selector(stageHeaderAnyTapped))
        tapObserver.cancelsTouchesInView = false
        view.addGestureRecognizer(tapObserver)
    }

    /// 单击显示歌名。(74) 实现靠 require(toFail: 三击) 压
    /// 住单击；(76) 静态审（报告⑦）：装配与接线在 (75) 后
    /// 完整无损、(75) 也未改本链，但跨视图失败依赖的实际
    /// 啮合取决于两识别器对同一触摸集的跟踪，落点不同即
    /// 表现不同，静态不可证、真机已失效。改显式时序门：
    /// 单击到达即排 0.35s 后 show（与 (74) 延迟同量级）；
    /// 三击识别即取消排期并开 0.4s 抑制窗——无论两识别
    /// 器同帧回调谁先谁后，三击序列里歌名都不出现（不
    /// 闪）；真单击到点未被取消才 showStageHeader。
    @objc private func stageHeaderSingleTapped74() {
        let now = CACurrentMediaTime()
        guard now >= headerShowSuppressUntil else {
            Breadcrumbs.log("stage.tap76 skip=triple")
            return
        }
        // (77) 落点补全：重排期取消旧排期也落痕——(76) 日志
        // 只有 gate 一行、sched 后无 fire/cancel 即属此类静
        // 默路径，下轮判读须每条 sched 都有落点。
        if headerShowWorkItem != nil {
            headerShowWorkItem?.cancel()
            Breadcrumbs.log("stage.tap76 cancel why=resched")
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.view.window != nil else {
                Breadcrumbs.log("stage.tap76 cancel why=window")
                return
            }
            guard CACurrentMediaTime() >= self.headerShowSuppressUntil
            else {
                Breadcrumbs.log("stage.tap76 cancel why=suppress")
                return
            }
            Breadcrumbs.log("stage.tap76 fire")
            self.showStageHeader(source: "tap76")
        }
        headerShowWorkItem = work
        Breadcrumbs.log("stage.tap76 sched")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35,
                                      execute: work)
    }

    private func scheduleStageHeaderHide() {
        headerHideWorkItem?.cancel()
        headerHideWorkItem = nil
        // (62) 自动隐藏控制栏设置化：关时顶栏常显、不排隐藏计时。
        guard SettingsStore.headerAutoHideEnabled else { return }
        guard !headerChromeHidden else { return }
        let work = DispatchWorkItem { [weak self] in self?.hideStageHeader() }
        headerHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func hideStageHeader() {
        guard !headerChromeHidden, view.window != nil else { return }
        headerChromeHidden = true
        // (62) 始终显示播放页返回按钮：closeButton 脱离自动隐藏组常显。
        let targets = stageHeaderViews.filter {
            !(SettingsStore.alwaysShowBackButton && $0 === closeButton)
        }
        for v in targets { v.isUserInteractionEnabled = false }
        UIView.animate(withDuration: 0.3, delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState]) {
            for v in targets { v.alpha = 0 }
        } completion: { _ in
            if self.headerChromeHidden {
                for v in targets { v.isHidden = true }
            }
        }
        Breadcrumbs.log("stage header auto-hide")
    }

    private func showStageHeader(source: String) {
        let wasHidden = headerChromeHidden
        headerChromeHidden = false
        for v in stageHeaderViews {
            v.isHidden = false
            v.isUserInteractionEnabled = true
        }
        if wasHidden {
            UIView.animate(withDuration: 0.35, delay: 0,
                           usingSpringWithDamping: 0.9,
                           initialSpringVelocity: 0,
                           options: [.beginFromCurrentState]) {
                for v in self.stageHeaderViews { v.alpha = 1 }
            }
            Breadcrumbs.log("stage header restore src=\(source)")
        }
        scheduleStageHeaderHide()
    }

    /// 单击观察（不消费触摸）：顶栏可见时任一单击 = 有操作，
    /// 顺延隐藏计时；顶栏已隐藏时单击不恢复（规格：单击不触发）。
    @objc private func stageHeaderAnyTapped() {
        if !headerChromeHidden { scheduleStageHeaderHide() }
    }

    // MARK: 样式三击轮换（3.7 (61) 第 6 条，Miller 改判）
    //
    // 舞台画面（rendererContainer 歌词/背景区）快速三击 →
    // 洗牌袋（StageStyleCycleBag）取下一只 → 走与样式选择器
    // 完全相同的选样式通路（applyNativeStyleSelection /
    // applyWebStyleSelection，含 StageStyleStore 持久化、
    // mountRenderer 的 style-guard 武装、汪汪队宠物迁移）。
    //
    // (54) 工作流 R 的 5 秒长按切样式本版退役：长按识别器与
    // 进度环 observer 接线已整组摘除（observer/环类本体曾留
    // 在 StageStyleCycleBag.swift 供宠物 4s 开启手势共用；
    // (70) B2 该手势整套撤除后两类已整类删除）。三击识别
    // 器自身不加任何 require。（74）第 9 项手势互斥反接在
    // 单击一侧：单击显示歌名 require(toFail: 三击)（见
    // installStyleCycleRecognizers 接线）——三击是本页唯一
    // 多击手势、序列全程歌名不出现；双击无任何绑定。
    //
    // 识别区纪律：识别器只挂 rendererContainer——点播台
    // （stageBar 及其宠物层 stagePetStage）、顶栏按钮、提示
    // 条都是它的兄弟视图而非子孙，从它们上面起的手势天然
    // 不进本识别器；容器内的贴纸浮层（StickerView）一律
    // isUserInteractionEnabled=false、触摸穿透，无死点。

    private func installStyleCycleRecognizers() {
        let tripleTap = UITapGestureRecognizer(
            target: self, action: #selector(styleCycleTripleTapped))
        tripleTap.numberOfTapsRequired = 3
        tripleTap.cancelsTouchesInView = false
        rendererContainer.addGestureRecognizer(tripleTap)
        stageTripleTap74 = tripleTap
        // (74) 第 9 项手势互斥曾在此接线：单击 require
        // (toFail: 三击)。(76) ⑦改显式时序门（见
        // stageHeaderSingleTapped74）：require 接线摘除，
        // 三击识别时在 styleCycleTripleTapped 内取消单击
        // 排期并开抑制窗。装配顺序仍为顶栏识别器先行。
        Breadcrumbs.log("stage.tap76 gate=timer")
    }

    @objc private func styleCycleTripleTapped() {
        // (76) 时序门：三击成立 → 单击的待触发 show 作废
        // （歌名不闪），抑制窗盖住同帧回调次序差。
        headerShowSuppressUntil = CACurrentMediaTime() + 0.4
        if headerShowWorkItem != nil {
            headerShowWorkItem?.cancel()
            headerShowWorkItem = nil
            Breadcrumbs.log("stage.tap76 cancel")
        }
        cycleToNextStyle(source: "tripleTap")
    }

    // MARK: (68) B 组出样·全宽控制条装配

    /// 装配：条本体加在视图最上层（layoutStage 每帧按安全区
    /// 定帧并在可见时置顶）；识别器与三击同挂 rendererContainer
    /// ——点播台/顶栏/提示条都是其兄弟视图，从它们上面起的手
    /// 势天然不进本识别器（与三击识别区纪律同构）。命令闭包
    /// 全部走既有落点（toggle/prev/next/seek 与点播台同路）。
    private func installWideBar68() {
        let bar = StageWideBar68()
        bar.onTogglePlay = { [weak self] in
            self?.handleCommand(LyricStageCommand(kind: .toggle, source: "widebar68"))
        }
        bar.onPrev = { [weak self] in
            self?.handleCommand(LyricStageCommand(kind: .prev, source: "widebar68"))
        }
        bar.onNext = { [weak self] in
            self?.handleCommand(LyricStageCommand(kind: .next, source: "widebar68"))
        }
        bar.onSeek = { [weak self] fraction in
            guard let self else { return }
            self.performSeek(to: fraction * self.engine.duration,
                             source: "widebar68")
        }
        view.addSubview(bar)
        wideBar68 = bar
        let tap = UITapGestureRecognizer(
            target: self, action: #selector(wideBarStageTapped68))
        tap.cancelsTouchesInView = false
        rendererContainer.addGestureRecognizer(tap)
        wideBarTap68 = tap
        syncWideBar68()
    }

    /// 开关同步（viewWillAppear 与设置变更通知共用出口）：
    /// 关 → 识别器停用＋条立即收起；开 → 识别器启用（条仍
    /// 待点屏唤出，不自动弹出）。
    private func syncWideBar68() {
        let enabled = SettingsStore.wideBar68Enabled
        wideBarTap68?.isEnabled = enabled
        if !enabled { wideBar68?.hideNow() }
    }

    /// 点屏：条已可见则只续命（与顶栏 tapObserver 顺延口径
    /// 一致），未可见则先喂当前进度再唤出。
    @objc private func wideBarStageTapped68() {
        guard SettingsStore.wideBar68Enabled, let bar = wideBar68 else { return }
        if bar.isBarVisible {
            bar.poke()
            return
        }
        let duration = engine.duration
        let fraction = duration > 0 ? positionNow() / duration : 0
        bar.update(fraction: fraction, playing: engine.isPlaying,
                   duration: duration)
        bar.show()
    }

    /// 三击轮换落点：向洗牌袋取下一只并经统一选样式通路
    /// 落地（持久化写在本方法、与选择器点选时的写点一致）；
    /// 触发瞬间只有中档触觉、无任何屏幕提示（(70) B5，
    /// Miller 点名：三击切特效时屏幕中央不许再弹样式名
    /// toast——旧 showStyleCycleToast 整组已摘，切换事实以
    /// 面包屑为准）。落点分流与选择器同口径：本台可呈现
    /// （原生渲染或网页嵌入）走统一通路、内部再按运行方式
    /// 分流；皆不可呈现才跳全屏网页舞台兜底。
    private func cycleToNextStyle(source: String) {
        let from = activeStyleId
        guard let draw = StageStyleCycleBag.shared.next(currentStyleId: from) else {
            Breadcrumbs.log("style.cycle.skip source=\(source) from=\(from) reason=single-selectable")
            return
        }
        guard let info = LyricStageRegistry.info(for: draw.styleId) else { return }
        StageStyleStore.currentStyleId = draw.styleId
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Breadcrumbs.log("style.cycle.switch source=\(source) from=\(from) to=\(draw.styleId)"
            + " round=\(draw.round) remaining=\(draw.remaining)")
        // (80) 逐歌记忆：三击是用户在本曲的显式切换，记入
        // 本曲记忆（自动通路不经此、不自记）。
        noteSongStyleMemory80(draw.styleId)
        if info.isStagePresentable {
            applyNativeStyleSelection(draw.styleId)
        } else {
            applyWebStyleSelection(info, reason: "cycle web style \(draw.styleId)")
        }
    }

    /// 选样式统一落点·原生（样式选择器手选与三击轮换共用，
    /// 结果完全一致）：袋子对账 + 藏未迁提示条 + 换装。
    /// 换装经 swapRenderer → 旧渲染器 unmount / 新渲染器
    /// mount+setLifecycle，汪汪队样式的宠物迁移
    /// （PetConcertRelocation begin/end）由渲染器生命周期
    /// 自动触发；style-guard pending 由 mountRenderer 武装。
    /// 持久化（StageStyleStore.currentStyleId）由各调用方在
    /// 进本落点前写好（选择器点选时点、轮换触发时点）。
    private func applyNativeStyleSelection(_ styleId: String) {
        // (63) DS R63 B2 装配相位·选样式入口（选择器/三击/
        // INT-14 实时换装共用本落点）。
        Breadcrumbs.log("asm.select style=\(styleId) via=apply")
        StageStyleCycleBag.shared.noteExternalSelection(styleId)
        noticeBar.isHidden = true
        view.setNeedsLayout()
        swapRenderer(to: styleId)
    }

    /// 选样式统一落点·网页兜底（同上共用）：袋子对账 + 跳
    /// 网页舞台（reason 标明入口，与既有面包屑口径一致）。
    private func applyWebStyleSelection(_ info: LyricStageStyleInfo, reason: String) {
        StageStyleCycleBag.shared.noteExternalSelection(info.id)
        jumpToWebStage(reason: reason)
    }

    // MARK: 逐歌记忆（3.7 (80) 第 3 项）

    /// 记录钩子：用户在本曲播放中手动切样式（选择器点选 /
    /// 三击轮换）后把 trackId→styleId 存入 SongStyleMemory80。
    /// 自动通路（每首歌随机 handleRandomStylePerSong62、记忆
    /// 套用本身）不经此——不会自记自套。无当前曲时为空操作。
    private func noteSongStyleMemory80(_ styleId: String) {
        guard let track = engine.currentTrack else { return }
        SongStyleMemory80.shared.record(trackId: track.id, styleId: styleId)
    }

    /// 套用钩子（切歌边沿，handleTrackChanged 内调）：本曲有
    /// 记忆样式且与当前不同 → 走统一选样式通路切过去。不写
    /// StageStyleStore.currentStyleId——记忆是逐歌的，不许污
    /// 染「最近选择」的全局口径（下台重开时 sink 首发会再套
    /// 一次，幂等）。不弹任何提示，事实以 style.mem80 为准。
    private func applySongStyleMemory80(for track: FoliaTrack) {
        guard let remembered = SongStyleMemory80.shared.style(for: track.id),
              remembered != activeStyleId,
              let info = LyricStageRegistry.info(for: remembered),
              !LyricStageRegistry.isLocked(remembered) else { return }
        Breadcrumbs.log("style.mem80 apply track=\(track.id) style=\(remembered)")
        if info.isStagePresentable {
            applyNativeStyleSelection(remembered)
        } else {
            applyWebStyleSelection(info, reason: "song-memory80 \(remembered)")
        }
    }

    // MARK: 生命周期

    deinit {
        NotificationCenter.default.removeObserver(self)
        StageExitGate.shared.unregisterStage(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 闸门登记（3.7 (46)）：本台成为 canonical 舞台，领取
        // token；此后一切退出必经 StageExitGate。
        stageToken = StageExitGate.shared.registerStage(self)
        // 协议留痕（3.7 (50)，DS YRC50 评审）：每台建立打一次，
        // 真机据此确认实际下发的协议版本与逐字能力位。
        Breadcrumbs.log("stage protocol v=\(LyricStageProtocolInfo.version)"
            + " hostWordSync=\(LyricStageProtocolInfo.hostCapabilities.supportsWordSync ? 1 : 0)")
        view.backgroundColor = .black
        buildLayout()
        // (62) WD 墙后画面挂载（WA 预留点，签名任务定死）。
        StageBackdrop62.attach(to: backdrop62Container)
        install62Chrome()
        // (62) INT-6：触摸光效挂载 + 切歌转场宿主注入（WB 两
        // 件，WA 未接线、集成补）：光效层挂舞台根视图（内部
        // 读 touchGlowEnabled 自门控）；转场动画的宿主视图由
        // 本台提供。
        TouchGlow62.attach(to: view)
        TransitionAnim62.hostViewProvider = { [weak self] in self?.view }
        // 自定义背景（3.7 (47)）：槽位有记录则装配并藏起宿主
        // 氛围层；播放由 viewWillAppear/Disappear 钩子管。
        refreshCustomBackground()
        installStageHeaderAutoHideRecognizers()
        // 样式三击轮换（3.7 (61) 第 6 条）：rendererContainer
        // 三击切特效；（54) 的 5 秒长按已退役。
        installStyleCycleRecognizers()
        // (68) B 组出样：全宽控制条装配（开关关时仅装隐藏
        // 视图＋disabled 识别器，零行为差异）。
        installWideBar68()
        // (76) ④左缘滑动返回：落点 = closeTapped →
        // closeStage（StageExitGate 闸门登记后 dismiss，契
        // 约不绕行；闸门 veto 时 EdgeBack76 自废交互并落
        // edge.back76 veto）。起手排除点播台条带（台上宠
        // 物拖拽/高度拖拽都在条带内）与顶栏区由系统边缘带
        // 天然覆盖；舞台既有 tap 链（三击/单击）为离散手
        // 势、与 pan 不共存于同一触摸序列，无接线冲突。
        EdgeBack76.install(on: self,
            shouldBeginAt: { [weak self] point in
                guard let self else { return true }
                return !self.stageBar.frame.contains(point)
            },
            onDismiss: { [weak self] in
                self?.closeTapped()
            })
        // 网页运行首帧回执（3.7 (67) A4）：桥转交本台处理淡换。
        WebEffectBridge.shared.onStyleFrame = { [weak self] styleId in
            self?.handleWebStyleFrame(styleId)
        }
        context = LyricStageContext(
            sendCommand: { [weak self] command in self?.handleCommand(command) },
            currentAnchor: { [weak self] in
                self?.anchor ?? PlaybackAnchor(
                    trackId: "", positionAtAnchor: 0,
                    wallTimeAtAnchor: CACurrentMediaTime(), rate: 0, anchorSeq: 0)
            })
        resolveInitialStyle()
        // 订阅的 sink 会立即以当前值首发（有曲走 handleTrackChanged），
        // 不需要再显式调一次，避免双跑取词；无曲时 sink 不触发刷新，
        // 这里补一次页眉空态。
        subscribePlayback()
        refreshHeader()
        reanchor(armSettle: true)
        // 贴纸层（3.7 (24)，纯新增）：建贴纸视图与陪伴宠物。
        stickerInstall()
        // 冷启恢复队列装载（3.7 (44)）：冷启自动 route 取消
        // 后，恢复态队列的装载改由「用户开台」触发——本台是
        // 所有开台入口（墙点歌台/迷你台/热后台 route）的唯
        // 一汇点。非恢复态为无操作（QueueManager 内部以
        // hasRestoredQueue 把关）；装载走现换地址、默认保持
        // 暂停（resumeRestoredQueue 既定语义不变）。
        QueueManager.shared.resumeRestoredQueue()
        // (62) 集成补接（WD 待接线项）：每首歌随机选出新样式
        // 后（RandomStylePerSong62 广播），舞台在场时实时换
        // 装；未开台时下次开台读 currentStyleId 自然生效。
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRandomStylePerSong62),
            name: .foliaStyleRandom62, object: nil)
        // (63) DS R63 B3 门控状态行：开台落一次 INT-14 开关
        // 值——关时候选 2（切歌随机换装竞态）直接出局，不必
        // 再向用户核对开关状态。
        Breadcrumbs.log("int14.setting on=\(SettingsStore.randomPerSongEnabled62 ? 1 : 0)")
    }

    /// 每首歌随机实时换装：走选样式统一通路（袋子对账 +
    /// swapRenderer），已是当前样式时不重复换装。
    @objc private func handleRandomStylePerSong62() {
        let target = StageStyleStore.currentStyleId
        guard target != activeStyleId else { return }
        Breadcrumbs.log("stage62.randomPerSong live-swap to=\(target)")
        applyNativeStyleSelection(target)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // (83) 第 2 条取证：双击链在飞时落 step=appear 收尾
        // （呈现链活着走到的第一个生命周期点；普通开台不
        // 落，见 DblTap83）。
        DblTap83.consumeAppear()
        // (74) 工具条提层：台面渲染层在演期间会后加子视图，
        // 每次回台把工具条提回最上（只动 z 序）。
        if let seamToolbar = stageSeamToolbar {
            view.bringSubviewToFront(seamToolbar)
        }
        // (68) B 组：全宽控制条开关回台同步（设置里关掉时回
        // 台不得残留识别器/条体）。
        syncWideBar68()
        Breadcrumbs.samplerStart()
        Breadcrumbs.log("stage gate enter style=\(activeStyleId) token=\(stageToken)")
        progressDriver.onFraction = { [weak self] fraction in
            guard let self else { return }
            // 拖动态守卫（3.7 (70) B4，与墙台 !miniSeekDragging
            // 对齐）：拖动中驱动不许写点——否则填充/圆点在
            // 手指位置与播放位置之间逐帧轮写＝闪帧（取证
            // uitaps C② 已定级，舞台接线独缺此守卫）。挡下
            // 次数在 seek 落点时一行自证。
            if self.stageSeekDragging {
                self.seekGuardBlocked70 += 1
                return
            }
            // seek 落点保持窗（3.7 (70) B4）：驱动重锚（漂移
            // >0.25s 连续 2 帧）收敛前，写点冻结在落点呈现
            // 上；rawPlayhead 进入目标 ±0.25s 或 300ms 超时
            // 任一满足即放行，消灭落点回跳。
            if let target = self.seekHoldTarget70 {
                let playhead = fraction * self.engine.duration
                if abs(playhead - target) <= 0.25
                    || CACurrentMediaTime() >= self.seekHoldDeadline70 {
                    self.seekHoldTarget70 = nil
                } else {
                    return
                }
            }
            self.setStageProgress(fraction)
        }
        progressDriver.start()
        // 自定义背景回台恢复（3.7 (47)）：动图/视频续播。
        customBgView.play()
        startDisplayLink()
        // 点播台在场边沿（3.7 (32)）：主题层门控 + 宠物钩子 +
        // 无操作计时，与墙台 setMiniBarVisible 同构。
        stageBarPresented = true
        stageThemeLayer?.setHostVisible(true)
        stageThemeLayer?.setBarVisible(true)
        if stageBarCollapsed { resetStageBarFormInstant() }
        stagePetStage?.barPresentationChanged(true)
        resetStageIdleTimer()
        // 顶栏自动隐藏计时（3.7 (46)）：开台/恢复即起 5 秒。
        if headerChromeHidden { showStageHeader(source: "appear") }
        else { scheduleStageHeaderHide() }
        driftTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkDrift()
        }
        gateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self else { return }
            Breadcrumbs.log("stage gate +30s frames \(self.frameStatsText())")
        }
        renderer?.setLifecycle(engine.isPlaying ? .playing : .paused, active: true)
    }

    /// (75) 旋转时工具条朝向组随转场首帧切换（本类此前无
    /// viewWillTransition 重写，此为唯一新增用途）。
    /// (76) 旋转管线对齐墙面 (73)（Miller 21:49 点名播放
    /// 页转动不流畅）：此前本页旋转只有朝向切换一职——
    /// viewDidLayoutSubviews 在转场期间被中间 bounds 反
    /// 复触发、layoutStage 全量几何（渲染器帧/chrome 帧/
    /// 贴纸定位/全员 bringToFront）一遍遍重算，关键路径
    /// 还叠着岛层 refront。改与墙面同构：冻结（中间
    /// bounds 只记待办）→ alongside 首帧以最终 bounds 解
    /// 冻单次重排 → completion 恢复 refront 并补一拍；
    /// 代际守卫防中途反向再转时旧代误解冻。演唱会几何仍
    /// 由 layoutStage 按最终 bounds 一次算清（横竖屏双向
    /// 独立成立的口径不变、只是不再中途反复算）。
    override func viewWillTransition(to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard viewIfLoaded != nil, size != view.bounds.size else {
            coordinator.animate(alongsideTransition: { [weak self] _ in
                self?.applySeamBandOrientation(
                    portrait: size.width < size.height)
            }, completion: nil)
            return
        }
        stageRotationGeneration += 1
        let generation = stageRotationGeneration
        stageRotationFrozen = true
        stageLayoutRuns = 0
        // (82) 第 6 条：rot82 冻结量测点——去掉 webEmbed-
        // StyleId 门控，原生样式旋转同样落痕（三点：freeze
        // 此处／landed 转场完成／ready 新尺寸首帧落定）。
        stageRotStart82 = CACurrentMediaTime()
        stageRotReadyMs84 = -1
        // (84) 第 5 条：旋转三点改同步落盘（logSync）＋
        // landed 摘要存 UserDefaults、下次启动补发——三
        // 个会话 rot82 零行（导出截断嫌疑）自此杜绝。
        Breadcrumbs.logSync("rot84 freeze gen=\(generation)"
            + " style=\(activeStyleId)"
            + " web=\(webEmbedStyleId != nil ? 1 : 0)")
        // (86) 第 9 条：rot86 逐段见证（freeze 此处／landed
        // 在 completion／reveal 在 revealWebRotCover81，三
        // 段毫秒分开落盘）。
        Breadcrumbs.logSync("rot86 freeze gen=\(generation)"
            + " style=\(activeStyleId)"
            + " web=\(webEmbedStyleId != nil ? 1 : 0)")
        Breadcrumbs.log("rot82 freeze gen=\(generation)"
            + " style=\(activeStyleId)"
            + " web=\(webEmbedStyleId != nil ? 1 : 0)"
            + " to=\(Int(size.width))x\(Int(size.height))")
        // (73 墙面同款）岛层守护转场期暂停：旋转中途不许
        // refront/reseat 抢主线程，落定后补一拍。
        PetIslandLayer.setRefrontSuspended(true)
        Breadcrumbs.log("stage.rotate freeze gen=\(generation)"
            + " from=\(Int(view.bounds.width))x\(Int(view.bounds.height))"
            + " to=\(Int(size.width))x\(Int(size.height))")
        // (81) 第 3 条：网页特效层纳入同一冻结管线——冻
        // 结拍先给 WebView 截图盖层（与 (70) B6 切换盖同
        // 法），转场期网页层本体藏在盖下、不再被系统旋转
        // 快照当刚性平面倾斜/侧躺；落定后等新尺寸首帧回
        // 执再揭（见 armWebRotReveal81）。
        if webEmbedStyleId != nil {
            beginWebRotCover81(generation: generation)
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.applySeamBandOrientation(portrait: size.width < size.height)
            guard generation == self.stageRotationGeneration else { return }
            // (86) 第 9 条：冻结保持到 completion——旧法在
            // 此处即解冻，转场动画期间中间 bounds/安全区多
            // 次变化、每次 viewDidLayoutSubviews 都全量
            // layoutStage（(85) 横→竖 runs=6）。改：冻结中
            // 以最终 bounds 单轮排版（layoutStage 不查冻结
            // 旗、直调即排），记录已排几何；转场期间的布
            // 局请求只记 pending，completion 几何一致即零
            // 补轮。
            if self.stageLayoutPending {
                self.stageLayoutPending = false
                self.layoutStage()
                self.pushSnapshot()
                self.stageRotLaidSize86 = size
                self.stageRotLaidInsets86 = self.view.safeAreaInsets
                // (82) 第 6 条：rot82 ready 量测点——新尺寸
                // 首帧布局＋快照已落（原生样式路径；网页样
                // 式另由 webfx.rot81 ready 对位）。
                let ms = Int((CACurrentMediaTime() - self.stageRotStart82) * 1000)
                self.stageRotReadyMs84 = ms
                Breadcrumbs.logSync("rot84 ready gen=\(generation) ms=\(ms)")
                Breadcrumbs.log("rot82 ready gen=\(generation) ms=\(ms)")
            }
            // (86) 第 9 条：网页层重排提前到转场期发（新尺
            // 寸已定）——揭盖回执在转场期内即可到达并由
            // handleWebStyleFrame 直揭，不再串行等 landed
            // 后才催（(85) 实锤揭盖迟到 278ms）。
            if self.webEmbedStyleId != nil {
                WebEffectBridge.shared.nudgeEffectResize81()
            }
        }) { [weak self] _ in
            PetIslandLayer.setRefrontSuspended(false)
            PetIslandLayer.shared.refrontIfNeeded()
            guard let self,
                  generation == self.stageRotationGeneration else { return }
            // (86) 第 9 条：解冻＋按需补轮——转场期 pending
            // 的布局请求若几何与 alongside 已排一致（纯旋
            // 转常态），零补轮、runs 收敛为 1；不一致才补
            // 一轮并落 extra=1。
            self.stageRotationFrozen = false
            var extraRun86 = 0
            if self.stageLayoutPending {
                self.stageLayoutPending = false
                if self.view.bounds.size != self.stageRotLaidSize86
                    || self.view.safeAreaInsets != self.stageRotLaidInsets86 {
                    self.layoutStage()
                    self.pushSnapshot()
                    extraRun86 = 1
                }
            }
            Breadcrumbs.log("stage.rotate76 landed gen=\(generation)"
                + " runs=\(self.stageLayoutRuns)")
            // (82) 第 6 条：rot82 landed 量测点（全样式）。
            let landedMs = Int((CACurrentMediaTime() - self.stageRotStart82) * 1000)
            Breadcrumbs.log("rot82 landed gen=\(generation) ms=\(landedMs)")
            Breadcrumbs.logSync("rot86 landed gen=\(generation)"
                + " f2l=\(landedMs) runs=\(self.stageLayoutRuns)"
                + " extra=\(extraRun86)")
            // (84) 第 5 条：旋转摘要同步落盘＋存 UserDefaults
            // 待下次启动补发（emitted=false）。f2r＝freeze→
            // ready 毫秒（判别字段）；网页样式 ready 在揭盖
            // 点回填（见 revealWebRotCover81）。
            let summary84: [String: Any] = [
                "gen": generation, "f2l": landedMs,
                "f2r": self.stageRotReadyMs84,
                "style": self.activeStyleId,
                "web": self.webEmbedStyleId != nil ? 1 : 0,
                "emitted": false,
            ]
            UserDefaults.standard.set(summary84, forKey: "folia.rot84.last")
            Breadcrumbs.logSync("rot84 gen=\(generation)"
                + " f2l=\(landedMs)"
                + " f2r=\(self.stageRotReadyMs84)"
                + " style=\(self.activeStyleId)"
                + " web=\(self.webEmbedStyleId != nil ? 1 : 0)")
            // (86) 第 5 条：收起轨宽按新朝向重写（同点收尾）。
            self.refreshTrackWidth86(portrait: size.width < size.height)
            if self.webRotCover81 != nil {
                Breadcrumbs.log("webfx.rot81 landed gen=\(generation)")
                self.armWebRotReveal81(generation: generation)
            }
        }
    }

    /// (81) 第 3 条：旋转冻结拍给网页层上截图盖。截图是
    /// 异步的——回图时若旋转代已过期（反向再转/已摘嵌）
    /// 整发作废。盖与 (70) B6 同法：scaleToFill＋弹性宽
    /// 高，转场期随容器拉伸（0.3s 级旋转里拉伸远轻于刚
    /// 性倾斜与黑窗）。
    private func beginWebRotCover81(generation: Int) {
        webRotGen81 += 1
        let rotGen = webRotGen81
        webRotStart81 = CACurrentMediaTime()
        webRotRevealWork81?.cancel()
        webRotRevealWork81 = nil
        let webView = WebEffectBridge.shared.webView
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self, rotGen == self.webRotGen81,
                  self.webEmbedStyleId != nil else { return }
            guard let image else {
                Breadcrumbs.log("webfx.rot81 freeze miss=1")
                return
            }
            self.webRotCover81?.removeFromSuperview()
            let cover = UIImageView(image: image)
            cover.frame = self.rendererContainer.bounds
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            cover.contentMode = .scaleToFill
            cover.isUserInteractionEnabled = false
            self.rendererContainer.addSubview(cover)
            self.webRotCover81 = cover
            Breadcrumbs.log("webfx.rot81 freeze gen=\(generation)")
        }
    }

    /// (81) 第 3 条：落定后揭盖武装——催网页层按新尺寸
    /// 重排（桥侧 dispatch resize），等其首帧回执
    /// （handleWebStyleFrame 转交）或 0.9s 超时，任一先
    /// 到即交叉淡出盖层并落 ready 量测（ms=冻结→揭盖）。
    private func armWebRotReveal81(generation: Int) {
        // (86) 第 9 条：nudge 已提前到 alongside 转场期发
        // （新尺寸一定即催网页层重排、回执到达由
        // handleWebStyleFrame 直揭），此处不再重复催——
        // 只留 0.9s 超时兜底（回执永不到时防永盖）。
        let rotGen = webRotGen81
        webRotRevealWork81?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, rotGen == self.webRotGen81 else { return }
            self.revealWebRotCover81(via: "tmo")
        }
        webRotRevealWork81 = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func revealWebRotCover81(via: String) {
        guard let cover = webRotCover81 else { return }
        webRotCover81 = nil
        webRotRevealWork81?.cancel()
        webRotRevealWork81 = nil
        let ms = Int((CACurrentMediaTime() - webRotStart81) * 1000)
        Breadcrumbs.log("webfx.rot81 ready via=\(via) ms=\(ms)")
        // (86) 第 9 条：rot86 reveal 段（freeze→揭盖毫秒，
        // 与 landed 分开落盘——判读揭盖是否仍串行迟到）。
        Breadcrumbs.logSync("rot86 reveal ms=\(ms) via=\(via)")
        // (84) 第 5 条：网页样式的 ready 点在此——回填本次
        // 旋转摘要的 f2r 并同步落盘（landed 时 ready 未达
        // 的补行）；gen 对位用 webRotGen81。
        stageRotReadyMs84 = ms
        if var saved = UserDefaults.standard.dictionary(forKey: "folia.rot84.last"),
           (saved["gen"] as? Int) == webRotGen81,
           (saved["f2r"] as? Int ?? -1) < 0 {
            saved["f2r"] = ms
            UserDefaults.standard.set(saved, forKey: "folia.rot84.last")
        }
        Breadcrumbs.logSync("rot84 ready gen=\(webRotGen81) ms=\(ms) web=1")
        UIView.animate(withDuration: 0.25, delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            cover.alpha = 0
        } completion: { _ in
            cover.removeFromSuperview()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // (75) 工具条首启定向兜底（同主页墙）。
        applySeamBandOrientation(portrait: view.bounds.width < view.bounds.height)
        // RouteGuard presented 模式（3.7 (46)）：守卫窗顺延到
        // appear+3s（DS 成功标准以 viewDidAppear 为锚）。
        StageExitGate.shared.noteStageAppeared(token: stageToken)
        // (82) 第 4 条：岛中央簇强制重发（页态=stage）。
        PetIslandLayer.shared.forceResendCenter82(page: "stage")
        // (63) DS R63 B6：运行期起点行——appear 后首个主线程
        // tick 落一行。崩溃日志尾停在 asm.done 之后、有本行
        // ＝崩点在装配完成后的运行期（M2 方向）；无本行＝崩
        // 在 present/装配段内（候选 1/4 方向）。
        if !didLogFirstTick63 {
            didLogFirstTick63 = true
            DispatchQueue.main.async {
                Breadcrumbs.log("runtime.tick first=1")
            }
        }
    }

    /// dismiss 统一拦截（3.7 (46)）：未登记来源、会带下本台且
    /// RouteGuard 在期的 dismiss 在此 veto（不调 super）；只解
    /// 本台之上盖层（样式选择器等）的 dismiss 由闸门放行。
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if StageExitGate.shared.shouldVetoDismiss(from: self) { return }
        super.dismiss(animated: flag, completion: completion)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // (68) B 组：全宽条离台即收（舞台实例复用，不残留到
        // 下次开台）。
        wideBar68?.hideNow()
        // 自定义背景离台暂停（3.7 (47)）。
        customBgView.pause()
        progressDriver.stop()
        stageBarPresented = false
        cancelStageIdleTimer()
        headerHideWorkItem?.cancel()
        headerHideWorkItem = nil
        // (77) 落点补全：离台取消待触发的单击 show 也落痕。
        if headerShowWorkItem != nil {
            Breadcrumbs.log("stage.tap76 cancel why=exit")
        }
        headerShowWorkItem?.cancel()
        headerShowWorkItem = nil
        stageThemeLayer?.setHostVisible(false)
        stageThemeLayer?.setBarVisible(false)
        stagePetStage?.barPresentationChanged(false)
        stopDisplayLink()
        driftTimer?.invalidate()
        driftTimer = nil
        gateTimer?.invalidate()
        gateTimer = nil
        renderer?.setLifecycle(engine.isPlaying ? .playing : .paused, active: false)
        Breadcrumbs.samplerStop()
        if isBeingDismissed {
            // 速退探针结算（3.7 (41) 组2）：route 开台后 3 秒
            // 内被 dismiss 才落盘，超时自动作废不留痕。
            if let armedAt = Self.routeExitProbeArmedAt {
                Self.routeExitProbeArmedAt = nil
                let dt = Date().timeIntervalSince(armedAt)
                if dt <= 3 {
                    Breadcrumbs.log("nowplaying.route stage-exit-quick dt=\(String(format: "%.2f", dt))")
                }
            }
            Breadcrumbs.log("stage gate exit token=\(stageToken) frames \(frameStatsText())")
            // 闸门旁路检测（3.7 (46)）：本次 dismiss 若无放行凭
            // 据且 RouteGuard 在期 = 未知路径带下舞台，闸门落
            // exit.bypass 并按配额触发同代际 reenter / giveup。
            StageExitGate.shared.noteStageDismissed(self)
            teardown()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // (76) 冻结期（旋转转场中）：不以中间 bounds 全量
        // 重算，只记待办——alongside 首帧以最终 bounds 单
        // 次补齐（layoutStage + pushSnapshot）。
        if stageRotationFrozen {
            stageLayoutPending = true
        } else {
            layoutStage()
        }
        if view.bounds.size != lastLayoutSize {
            lastLayoutSize = view.bounds.size
            if !stageRotationFrozen { pushSnapshot() }
        }
    }

    private func teardown() {
        guard !tornDown else { return }
        tornDown = true
        // 三击轮换的袋子轮次状态是进程级、保留不动（(70)
        // B5 起切换无屏幕提示，旧 toast 收尾随之退役）。
        // 守卫证明·teardown 路（3.7 (45) R-4）：本台只在正常
        // dismiss 时走 teardown——开过又正常关掉即该样式活
        // 过，清 pending，免健康样式下次启动遭误报回退。
        finishStyleProof(via: "teardown")
        settleTimer?.invalidate()
        settleTimer = nil
        settleReanchorAt = nil
        // 网页运行嵌入收尾（3.7 (67) A2）：WebView 摘回桥侧
        // （页面不销毁，全屏网页舞台仍可复用同一实例）。
        detachWebEmbed()
        lyricsTask?.cancel()
        backdropTask?.cancel()
        renderer?.setLifecycle(.destroyed, active: false)
        renderer?.unmount()
        renderer = nil
        cancellables.removeAll()
    }

    // MARK: 布局

    private func buildLayout() {
        view.insertSubview(customBgView, at: 0)
        backdropImageView.contentMode = .scaleAspectFill
        backdropImageView.clipsToBounds = true
        backdropBlur.alpha = 0.55
        // (62) INT-6：原生毛玻璃背景开关消费（WB 键
        // stageBackdropBlurEnabled，默认开）——关时 effect 置
        // nil，模糊层整体不渲染（后续自定义背景的显隐切换只
        // 动 isHidden、不复活模糊）。
        if !SettingsStore.stageBackdropBlurEnabled {
            backdropBlur.effect = nil
        }
        backdropTint.backgroundColor = palette.background.withAlphaComponent(0.5)
        for v in [backdropImageView, backdropBlur, backdropTint] as [UIView] {
            view.addSubview(v)
        }
        closeButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        likeButton.tintColor = .white
        // (68) A1 状态强可视化：已喜欢态整钮填充变色，钮体
        // 38×38 圆角 19 成圆钮（填充在 refreshLikeButton 切换）。
        likeButton.layer.cornerRadius = 19
        likeButton.layer.masksToBounds = true
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        artistLabel.font = .systemFont(ofSize: 13)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        artistLabel.textAlignment = .center
        artistLabel.lineBreakMode = .byTruncatingTail
        styleButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        styleButton.setTitleColor(.white, for: .normal)
        styleButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        styleButton.layer.cornerRadius = 12
        styleButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        styleButton.addTarget(self, action: #selector(styleTapped), for: .touchUpInside)
        for v in [closeButton, titleLabel, artistLabel, likeButton, styleButton] as [UIView] {
            view.addSubview(v)
        }
        noticeBar.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        noticeBar.layer.cornerRadius = 10
        noticeBar.isHidden = true
        noticeLabel.font = .systemFont(ofSize: 12)
        noticeLabel.textColor = .white
        noticeLabel.numberOfLines = 2
        noticeWebButton.setTitle("回网页版", for: .normal)
        noticeWebButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        noticeWebButton.setTitleColor(UIColor(red: 0.65, green: 0.85, blue: 1, alpha: 1), for: .normal)
        noticeWebButton.addTarget(self, action: #selector(noticeWebTapped), for: .touchUpInside)
        noticeCloseButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        noticeCloseButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        noticeCloseButton.addTarget(self, action: #selector(noticeCloseTapped), for: .touchUpInside)
        noticeBar.addSubview(noticeLabel)
        noticeBar.addSubview(noticeWebButton)
        noticeBar.addSubview(noticeCloseButton)
        view.addSubview(noticeBar)
        // (62) 顶栏模糊背景：插在顶栏控件之下、画面之上。
        let headerBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        headerBlur.isUserInteractionEnabled = false
        headerBlur.isHidden = !SettingsStore.headerBlurEnabled
        view.addSubview(headerBlur)
        headerBlur62 = headerBlur
        // (62) WD 挂载点与 62 新增面（层序：backdrop62 < renderer）。
        backdrop62Container.isUserInteractionEnabled = false
        view.addSubview(backdrop62Container)
        view.addSubview(rendererContainer)
        view.addSubview(trackPill62)
        soundTracing62.isHidden = !SettingsStore.soundTracingEnabled
        view.addSubview(soundTracing62)
        for (button, symbol, action) in [
            (alwaysPrev62, "chevron.left.circle.fill", #selector(alwaysPrev62Tapped)),
            (alwaysNext62, "chevron.right.circle.fill", #selector(alwaysNext62Tapped)),
        ] as [(UIButton, String, Selector)] {
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.tintColor = UIColor.white.withAlphaComponent(0.85)
            button.addTarget(self, action: action, for: .touchUpInside)
            button.isHidden = !SettingsStore.alwaysShowSkipButtons
            view.addSubview(button)
        }
        // 点播台（3.7 (32)）：与墙台同规格的台体在此装配，
        // 三键仍走既有按钮与命令入口（handleCommand 同路）。
        // 附加功能浮层在 buildStageBar 内随台一并装配（锚台顶）。
        buildStageBar()
        // (74) 缝合工具条铺到播放详情页（三页清单之三）：与
        // 主页/歌单页同款同口径（左上锚、绕岛、系统弹簧）。
        installStageSeamToolbar74()
        refreshPlayButton()
        refreshLikeButton()
        // 主题变更通知（设置页/任一台长按）→ 本台同步换装。
        NotificationCenter.default.addObserver(
            self, selector: #selector(stageThemeSettingsChanged),
            name: .foliaMiniPlayerThemeChanged, object: nil)
        // 点播台按钮槽位变更（3.7 (50)，设置页）即时同步。
        NotificationCenter.default.addObserver(
            self, selector: #selector(stageBarSlotsChanged),
            name: .foliaMiniBarSlotsChanged, object: nil)
        // 点播台顶排信号订阅（3.7 (55) 工作流 D，名称由工作流 C
        // 定死）：格子钮 → 播放面板、命令钮 → 命令面板。信号由
        // 三台的 quick row 都可能发出，本台只在自身在窗
        // （view.window != nil）时响应（handler 内守卫）。字幕钮
        // 信号 .foliaMiniBarSubtitle 已随 (60) 第 11 条整组删除。
        NotificationCenter.default.addObserver(
            self, selector: #selector(stageMiniBarPanelTapped),
            name: .foliaMiniBarPanel, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(stageMiniBarCommandTapped),
            name: .foliaMiniBarCommand, object: nil)
    }

    // MARK: (62) WA 接线

    private func install62Chrome() {
        // 底部组件拖动调整：在点播台顶缘加一条 16pt 拖动带（不抢
        // 台身既有手势域），纵向拖动改 bottomBarHeight 并落盘。
        let handle = UIView()
        handle.backgroundColor = .clear
        handle.translatesAutoresizingMaskIntoConstraints = false
        stageBar.addSubview(handle)
        stageBarDragHandle66 = handle
        NSLayoutConstraint.activate([
            handle.topAnchor.constraint(equalTo: stageBar.topAnchor),
            handle.leadingAnchor.constraint(equalTo: stageBar.leadingAnchor),
            handle.trailingAnchor.constraint(equalTo: stageBar.trailingAnchor),
            handle.heightAnchor.constraint(equalToConstant: 16),
        ])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(stageBarHeightDrag62(_:)))
        handle.addGestureRecognizer(pan)
        NotificationCenter.default.addObserver(
            self, selector: #selector(settings62AChanged),
            name: .foliaSettings62AChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(settings62AChanged),
            name: .foliaTheme62Changed, object: nil)
        // (66) 设置页「在播放页拖动调整」按钮的定位信号。
        NotificationCenter.default.addObserver(
            self, selector: #selector(stageBarLocate66),
            name: .foliaStageBarLocate66, object: nil)
        refresh62Settings()
        Breadcrumbs.log("stage62.install scene=\(SceneSystem62.params().label)"
            + " soundTracing=\(SettingsStore.soundTracingEnabled ? 1 : 0)"
            + " barH=\(Int(SettingsStore.bottomBarHeight))")
    }

    @objc private func settings62AChanged() {
        refresh62Settings()
        refreshCustomBackground()
        // (68) B 组：全宽控制条开关即时同步（同台在场时改
        // 设置返回即生效/摘除）。
        syncWideBar68()
        view.setNeedsLayout()
    }

    /// (62) 设置即时消费：底栏高度/隐藏、顶栏模糊、常显箭头、声线、
    /// 右侧按钮隐藏、主题强调色（点播台主题底色＋样式钮）。
    private func refresh62Settings() {
        if !stageBarCollapsed {
            // (81) 第 9 条：统一高 70，不再读 bottomBarHeight。
            stageBarHeightConstraint?.constant = MiniBarQuickRowView.expandedBarHeight
        }

        stageBar.isHidden = SettingsStore.hideBottomBar
        headerBlur62?.isHidden = !SettingsStore.headerBlurEnabled
        alwaysPrev62.isHidden = !SettingsStore.alwaysShowSkipButtons
        alwaysNext62.isHidden = !SettingsStore.alwaysShowSkipButtons
        soundTracing62.isHidden = !SettingsStore.soundTracingEnabled
        let hideRight = SettingsStore.hideRightButtons
        likeButton.isHidden = hideRight
        styleButton.isHidden = hideRight
        // 主题消费：点播台玻璃底掺当前主题背景调、样式钮底掺强调色。
        stageGlassTint?.backgroundColor =
            ThemeSystem62.currentBackground.withAlphaComponent(0.45)
        styleButton.backgroundColor =
            ThemeSystem62.currentAccent.withAlphaComponent(0.25)
        if !SettingsStore.headerAutoHideEnabled, headerChromeHidden {
            showStageHeader(source: "62-autohide-off")
        }
        // (66) 透明舞台背景消费：开时舞台自有底图层全撤、根
        // 视图透明（露出下层墙面），与 /obs 页同键同义。
        let transparent = SettingsStore.transparentStageBackground62
        view.backgroundColor = transparent ? .clear : .black
        backdrop62Container.isHidden = transparent
        backdropImageView.isHidden = transparent
        backdropBlur.isHidden = transparent
        backdropTint.isHidden = transparent
        // (66) 进度条两端槽位钮按当前键值重建。
        configureStageSlot66(stageSlotLeft66, function: SettingsStore.barSlotLeft62)
        configureStageSlot66(stageSlotRight66, function: SettingsStore.barSlotRight62)
    }

    /// (66) 槽位钮配置：功能集与设置行同表
    /// （SettingsStore.barSlotFunctions62），动作分发复用台
    /// 既有通路（prev/next/like/队列面板/模式菜单/睡眠菜单）。
    private func configureStageSlot66(_ button: UIButton, function: String) {
        button.menu = nil
        button.showsMenuAsPrimaryAction = false
        button.removeTarget(nil, action: nil, for: .allEvents)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        func setGlyph(_ name: String) {
            button.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
        }
        switch function {
        case "prev":
            setGlyph("backward.end.fill")
            button.accessibilityLabel = "上一首（槽位）"
            button.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
            button.isHidden = false
        case "next":
            setGlyph("forward.end.fill")
            button.accessibilityLabel = "下一首（槽位）"
            button.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
            button.isHidden = false
        case "like":
            setGlyph("heart")
            button.accessibilityLabel = "喜欢（槽位）"
            button.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
            button.isHidden = false
        case "queue":
            setGlyph("list.bullet")
            button.accessibilityLabel = "播放队列（槽位）"
            button.addTarget(self, action: #selector(stageSlotQueue66), for: .touchUpInside)
            button.isHidden = false
        case "mode":
            setGlyph("repeat")
            button.accessibilityLabel = "播放模式（槽位）"
            button.menu = stageModeButton.menu
            button.showsMenuAsPrimaryAction = true
            button.isHidden = false
        case "sleep":
            setGlyph("moon.zzz")
            button.accessibilityLabel = "睡眠定时（槽位）"
            let actions = SleepTimerController.presets.filter { $0 > 0 }.map { minutes in
                UIAction(title: "\(minutes) 分钟后停止") { _ in
                    SleepTimerController.shared.set(minutes: minutes)
                    Breadcrumbs.log("stage66.slot sleep=\(minutes)")
                }
            } + [UIAction(title: "取消定时", attributes: .destructive) { _ in
                SleepTimerController.shared.cancel()
            }]
            button.menu = UIMenu(title: "睡眠定时", children: actions)
            button.showsMenuAsPrimaryAction = true
            button.isHidden = false
        default:
            button.isHidden = true
        }
    }

    @objc private func stageSlotQueue66() {
        resetStageIdleTimer()
        PlaybackPanelViewController.present(from: self, initialTab: .queue)
    }

    /// (66) 设置页「在播放页拖动调整」：脉冲高亮点播台顶缘
    /// 拖高柄两轮，提示拖动位置（与 bottomBarHeight 同通路）。
    @objc private func stageBarLocate66() {
        guard let handle = stageBarDragHandle66, !stageBarCollapsed else { return }
        Breadcrumbs.log("stage66.locate pulse=1")
        handle.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        UIView.animate(withDuration: 0.45, delay: 0,
                       options: [.autoreverse, .repeat, .curveEaseInOut]) {
            handle.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            handle.layer.removeAllAnimations()
            handle.backgroundColor = .clear
        }
    }

    @objc private func stageBarHeightDrag62(_ gesture: UIPanGestureRecognizer) {
        // (81) 第 9 条：台高全页统一 70 后，(62) 拖动调高
        // 退役——拖动不再改高（识别器保留装配、动作空转并
        // 在抬手时落痕说明，避免设置页「拖动调整」入口点
        // 到台上拖动无任何反馈的静默失效）。
        if gesture.state == .ended {
            Breadcrumbs.log("deck.size81 drag=retired h=70")
        }
    }

    @objc private func alwaysPrev62Tapped() { queueManager.playPrevious() }
    @objc private func alwaysNext62Tapped() { queueManager.playNext(manual: true) }

    private func layoutStage() {
        stageLayoutRuns += 1
        let bounds = view.bounds
        let safe = view.safeAreaInsets
        customBgView.frame = bounds
        backdropImageView.frame = bounds
        backdropBlur.frame = bounds
        backdropTint.frame = bounds
        backdrop62Container.frame = bounds
        let headerTop = safe.top + 6
        closeButton.frame = CGRect(x: 12, y: headerTop, width: 38, height: 38)
        likeButton.frame = CGRect(x: bounds.width - 50, y: headerTop, width: 38, height: 38)
        let titleWidth = bounds.width - 120
        titleLabel.frame = CGRect(x: 60, y: headerTop, width: titleWidth, height: 22)
        artistLabel.frame = CGRect(x: 60, y: headerTop + 22, width: titleWidth, height: 17)
        styleButton.sizeToFit()
        styleButton.frame = CGRect(
            x: bounds.width - styleButton.bounds.width - 14,
            y: headerTop + 44, width: styleButton.bounds.width, height: 24)
        var contentTop = headerTop + 76
        if !noticeBar.isHidden {
            noticeBar.frame = CGRect(x: 16, y: contentTop, width: bounds.width - 32, height: 40)
            noticeCloseButton.frame = CGRect(x: noticeBar.bounds.width - 34, y: 5, width: 30, height: 30)
            noticeWebButton.sizeToFit()
            noticeWebButton.frame = CGRect(
                x: noticeBar.bounds.width - 44 - noticeWebButton.bounds.width,
                y: 5, width: noticeWebButton.bounds.width, height: 30)
            noticeLabel.frame = CGRect(
                x: 10, y: 4, width: noticeWebButton.frame.minX - 16, height: 32)
            contentTop += 48
        }
        // 点播台几何（3.7 (32)）：宽 = min(屏宽, 屏高) − 24
        // 居中（横屏同宽不拉伸，与墙台 (21) 定版一致，约束在
        // buildStageBar 定、此处按当前尺寸更新常量）；台顶 =
        // 屏底 − 安全区 − 10 − 形态高（展开 70 / 收起 16）。
        // 台内子视图全走约束（同墙台结构），此处不再逐个定
        // 帧。歌词容器底边到台顶上 4pt。
        stageBarWidthConstraint?.constant =
            min(bounds.width, bounds.height) - 24
        // (81) 第 9 条：几何高与统一台同值（展开 70），不
        // 再读 bottomBarHeight（controlsTop/chromeInsets
        // 全链随此对齐）。
        let barHeight: CGFloat = stageBarCollapsed ? 16
            : MiniBarQuickRowView.expandedBarHeight
        let controlsTop = bounds.height - safe.bottom - 10 - barHeight
        // 全样式全幅（3.7 (60) 第 4 条，取代 (55)/(57) 的 petconcert
        // 独占全幅特判）：rendererContainer 对全部样式一律 = view
        // bounds，chrome（顶栏/提示条/点播台/附加功能浮层）浮压
        // 其上——此前其余 20 样式被 contentTop..controlsTop 的带
        // 状容器限高（横屏只剩约 150pt），是「很多特效横屏半幅」
        // 的统一成因；各样式内部既已 bounds 自适应，容器放大即
        // 全屏。演唱会行为不变（它本来就是全幅）。浮名（世界
        // 制）、群唱（居中面板）、静止（限宽槽）属构图设计、不
        // 强行拉满，仍按各自内部几何走。
        rendererContainer.frame = bounds
        renderer?.view.frame = rendererContainer.bounds
        // (62) 新增面几何：顶栏模糊带 / 歌曲卡（按位置设置）/ 声线框 /
        // 常显切歌箭头（左右中段）。
        headerBlur62?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerTop + 52)
        if !trackPill62.isHidden { trackPill62.place(in: view) }
        soundTracing62.frame = CGRect(x: bounds.width - 188, y: headerTop + 78,
                                      width: 176, height: 46)
        alwaysPrev62.frame = CGRect(x: 6, y: bounds.height / 2 - 22, width: 44, height: 44)
        alwaysNext62.frame = CGRect(x: bounds.width - 50, y: bounds.height / 2 - 22,
                                    width: 44, height: 44)
        for chrome62 in [trackPill62, soundTracing62, alwaysPrev62, alwaysNext62] as [UIView] {
            view.bringSubviewToFront(chrome62)
        }
        if let hb = headerBlur62 { view.bringSubviewToFront(hb) }
        for chrome in [closeButton, likeButton,
                       titleLabel, artistLabel, styleButton,
                       noticeBar, stageBar] as [UIView] {
            view.bringSubviewToFront(chrome)
        }
        if let overlay = stageQuickRowOverlay {
            view.bringSubviewToFront(overlay)
        }
        // (68) B 组：全宽条帧（全宽、贴底，内容行高＋底部安全
        // 区填充；横竖屏同式，宽随 bounds 全幅、行高恒定）；
        // 可见时置顶盖住点播台所在带，自隐后点播台原样露出。
        if let bar = wideBar68 {
            let barHeight = StageWideBar68.contentHeight + safe.bottom
            bar.frame = CGRect(x: 0, y: bounds.height - barHeight,
                               width: bounds.width, height: barHeight)
            if !bar.isHidden { view.bringSubviewToFront(bar) }
        }
        // 统一 chromeInsets 规则（(60) 第 4 条）：把当前 chrome
        // 占用（顶栏高 = contentTop、点播台当前形态高含安全区与
        // 间距）算成 insets 下发当前渲染器；只有下部构图重心的
        // 样式实现内缩（pendolo 表盘中心上移 bottom/2、cappella
        // 面板上移 bottom/2），其余走协议默认空实现忽略。
        // (81) 第 7 条：详情页宠物专属带——展开态且宠物开
        // 启时，底部 inset 再加 52（宠物身高 48＋4 间隙）：
        // 歌词列表/构图按 inset 在宠物带上方收尾，宠物只
        // 在台顶这条专属带里活动、不再骑台沿压列表。收起
        // 态宠物在细条上嬉戏（定版形态）不预留。
        let petBand81: CGFloat = (!stageBarCollapsed
            && StickerSettings.miniPetsEnabled) ? 52 : 0
        if petBand81 != lastPetBand81 {
            lastPetBand81 = petBand81
            Breadcrumbs.log("deck.pet81 band=\(Int(petBand81))")
        }
        let chromeInsets = UIEdgeInsets(
            top: contentTop, left: 0,
            bottom: bounds.height - controlsTop + petBand81, right: 0)
        renderer?.applyChromeInsets(chromeInsets)
        // 贴纸层（3.7 (24)，纯新增）：贴纸与陪伴宠物定位。
        stickerLayoutOverlays()
    }

    // MARK: 样式解析与渲染方装配

    private func resolveInitialStyle() {
        let recorded = StageStyleStore.currentStyleId
        activeStyleId = StageStyleStore.effectiveStyleId()
        // (63) DS R63 B2 装配相位·开台初始选样式。
        Breadcrumbs.log("asm.select style=\(activeStyleId) via=initial")
        mountRenderer(styleId: activeStyleId)
        // 三击轮换对账（3.7 (54) 工作流 R 立、(61) 改三击）：
        // 开台初始样式即当前样式，从洗牌袋本轮余量剔除（轮
        // 次跨开台保留）。
        StageStyleCycleBag.shared.noteExternalSelection(activeStyleId)
        if !StageStyleStore.currentStyleIsPresentable && !noticeDismissed {
            let recordedName = LyricStageRegistry.info(for: recorded)?.displayName ?? recorded
            let effectiveName = LyricStageRegistry.info(for: activeStyleId)?.displayName ?? activeStyleId
            noticeLabel.text = "当前样式『\(recordedName)』尚未原生化，暂时用『\(effectiveName)』"
            noticeBar.isHidden = false
        }
        refreshStyleButton()
    }

    private func mountRenderer(styleId: String) {
        // 网页运行（3.7 (67) A2）：运行位为网页的样式不建原生
        // 渲染器，WebView 常驻进 rendererContainer 同级呈现。
        if StageRuntimeStore.isWeb(styleId) {
            mountWebRenderer(styleId: styleId)
            return
        }
        guard let info = LyricStageRegistry.info(for: styleId),
              let factory = info.factory else {
            // 已迁样式却拿不到工厂 = 装配异常，走回退不硬撑。
            jumpToWebStage(reason: "no renderer factory for \(styleId)")
            return
        }
        // 打开追踪·装配开始（3.7 (61) 第 3 条，DS R61 Q2 定
        // 案）：dataHash 取装配此刻的曲目+已缓存行表（与
        // makeSnapshot 同源）；标记先行落盘——进程死在装配
        // 中途时 lastMarker 停在 open。
        let traceTrackId = engine.currentTrack?.id
        let traceLines = traceTrackId.flatMap { linesCache[$0] } ?? []
        let traceHash = StyleOpenTrace.dataHash(trackId: traceTrackId, lines: traceLines)
        styleTraceStyleId = styleId
        styleTraceDataHash = traceHash
        styleTraceFirstFrameLogged = false
        StyleOpenTrace.mark("open", styleId: styleId, dataHash: traceHash)
        Breadcrumbs.log("style.open.begin style=\(styleId) dataHash=\(traceHash)")
        // (63) DS R63 B2 装配相位行（全同步落盘，M5）：init/
        // mount 前后各一行——崩溃日志尾停在哪对之间，装配期
        // trap（候选 1）就钉在哪一步，不再只有 open/assembly
        // 两端粗粒度二分。
        asmPhase63 = "mount"
        Breadcrumbs.logSync("asm.init.pre style=\(styleId)")
        let next = factory()
        Breadcrumbs.logSync("asm.init.post style=\(styleId)")
        Breadcrumbs.logSync("asm.mount.pre style=\(styleId)")
        next.mount(context: context)
        Breadcrumbs.logSync("asm.mount.post style=\(styleId)")
        // gate 解码图像清单（3.7 (26)，R40 Q4 口径）：本期两
        // 样式为 UIKit/文本类，渲染方自身解码图像 0 张、无
        // Metal 纹理；舞台唯一解码图像是宿主背景封面（到货
        // 时由 applyBackdrop 落 `stage gate backdrop decoded`
        // 一行，含像素尺寸与估算 MB）。
        Breadcrumbs.log("stage gate decoded style=\(styleId) rendererImages=0 textOnly=1 metalTextures=0")
        // 激活样式 footprint 自证（3.7 (60) 第 4 条）：Breadcrumbs
        // .log 尾巴恒带 footprintMB=（Breadcrumbs 内部采样口径），
        // 本行即「激活时刻全应用 footprint」的可判读记录。
        Breadcrumbs.log("stage.style.footprint style=\(styleId)")
        rendererContainer.addSubview(next.view)
        next.view.frame = rendererContainer.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        renderer = next
        next.applySnapshot(makeSnapshot())
        next.setLifecycle(engine.isPlaying ? .playing : .paused, active: isViewLoaded && view.window != nil)
        // 打开追踪·装配完成（3.7 (61) 第 3 条）：mount+apply-
        // Snapshot+setLifecycle 全返回才落本行并推进标记；
        // phys/avail/memWarn 为采样此刻值（Breadcrumbs 尾巴另
        // 带同口径 availMB/footprintMB 可交叉对账）。
        StyleOpenTrace.mark("assembly", styleId: styleId, dataHash: traceHash)
        Breadcrumbs.log("style.assembly.done style=\(styleId) dataHash=\(traceHash) \(StyleOpenTrace.memoryFields())")
        // (63) DS R63 B2/B6：装配完成行（同步落盘）——与
        // style.assembly.done 同点，短名供判读表对位；此后
        // asmPhase63=ready，swap.begin 的 phase 据此判读。
        asmPhase63 = "ready"
        Breadcrumbs.logSync("asm.done style=\(styleId)")
        StageStyleStore.lastNativeStyleId = styleId
        // 防卡死守卫武装（3.7 (44)）：样式装配即落 pending，
        // 待证明存活后清除（见 styleProof* 状态）。(45) R-4：
        // 歌词里程碑的初值取当前曲是否已在 linesCache——切
        // 样式时歌词早已到货，不必等下一首歌才算达标。
        StageStyleStore.armStylePending(styleId)
        styleProofStyleId = styleId
        styleProofFrames = 0
        styleProofArmedAt = CACurrentMediaTime()
        styleProofFramesOK = false
        styleProofLyricsApplied =
            currentTrackId.flatMap { linesCache[$0] } != nil
        // §0 估算器来源（3.7 (67) B 组）：浮名/回环/莫奈三式
        // 绕开统一 singingRatio 收口走私有估算（plan §0 定性），
        // 其余原生样式走统一收口；判读按本行分组。
        let privateEstimators: Set<String> = ["fume", "claddagh", "monet"]
        Breadcrumbs.log("est.src style=\(styleId) est=\(privateEstimators.contains(styleId) ? "private" : "unified")")
    }

    /// 防卡死守卫证明结算（3.7 (45) R-4）：三路证明共用此
    /// 出口——清 pending 并落 proven 面包屑（via 标明路径）。
    /// 未武装/已证明时为空操作。
    private func finishStyleProof(via: String) {
        guard let proofStyle = styleProofStyleId else { return }
        styleProofStyleId = nil
        StageStyleStore.clearStylePending()
        Breadcrumbs.log("stage style-guard proven style=\(proofStyle) via=\(via)")
    }

    /// 歌词 applied 里程碑（3.7 (45) R-4）：loadLyrics 三条
    /// 落定路径（实例缓存命中/仓库命中/网络解析完成）各调
    /// 一次。只置标志，证明结算仍在 frameStep/teardown。
    private func noteStyleProofLyricsApplied() {
        styleProofLyricsApplied = true
    }

    private func swapRenderer(to styleId: String) {
        // (63) DS R63 B3：换装入口同步落盘，带装配相位——
        // phase=mount 时换装落在半装配状态（候选 2 的指纹），
        // phase=ready 为常规换装；出口落 swap.done 对位。
        Breadcrumbs.logSync("swap.begin phase=\(asmPhase63)"
            + " from=\(activeStyleId) to=\(styleId)")
        // 网页运行分流（3.7 (67) A2）：目标式运行位为网页时走
        // 嵌入淡换（旧帧垫底、首帧回执放行），不走原生换装链。
        if StageRuntimeStore.isWeb(styleId) {
            swapToWebRenderer(styleId: styleId)
            refreshStyleButton()
            Breadcrumbs.log("swap.done phase=\(asmPhase63) to=\(styleId)")
            return
        }
        // 网页运行 → 原生：原生层在网页层之上装配（既有转场），
        // 落定后摘网页层（detachWebEmbed 延后一拍执行）。
        let leavingWebEmbed = webEmbedStyleId != nil
        // (62) INT-13：样式切换转场接线（WD StyleSwapTransition62
        // 帮助类）——旧层快照淡出 + 新层首帧淡入（系统弹簧）。
        let swapTransition = StyleSwapTransition62(container: rendererContainer)
        swapTransition.begin(oldView: renderer?.view)
        renderer?.setLifecycle(.destroyed, active: false)
        renderer?.unmount()
        renderer?.view.removeFromSuperview()
        renderer = nil
        activeStyleId = styleId
        mountRenderer(styleId: styleId)
        swapTransition.finish(newView: renderer?.view)
        if leavingWebEmbed {
            // 代次校验（(67) 独立审查修复）：0.5s 内切回网页样式
            // 时 armWebFade 已递增 webSwapGeneration，这发迟到的
            // detach 不许误拆新一轮淡换（WebView 被摘＋alpha 停
            // 0 ＝台面空白）。
            let detachGeneration = webSwapGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.webSwapGeneration == detachGeneration else { return }
                self.detachWebEmbed()
            }
        }
        refreshStyleButton()
        Breadcrumbs.log("stage gate style switch to=\(styleId)")
        Breadcrumbs.log("swap.done phase=\(asmPhase63) to=\(styleId)")
    }

    // MARK: 网页运行嵌入（3.7 (67) A2/A4）

    /// 开台初始装配·网页运行：无旧帧垫底，WebView 先藏（alpha
    /// 0），首帧回执或超时后淡入——与换装淡换同一出口。
    private func mountWebRenderer(styleId: String) {
        armWebStyleProof(styleId: styleId)
        embedWebView()
        WebEffectBridge.shared.webView.alpha = 0
        webEmbedStyleId = styleId
        syncWebTouch81()
        WebEffectBridge.shared.isEmbeddedInStage = true
        WebEffectBridge.shared.pushSnapshot()
        WebEffectBridge.shared.pushVisual(lyricMode: styleId, backgroundMode: nil)
        armWebFade(backing: nil)
        Breadcrumbs.log("webfx.mount style=\(styleId) via=initial \(StyleOpenTrace.memoryFields())")
        Breadcrumbs.log("est.src style=\(styleId) est=web")
    }

    /// 换装·网页运行：原生→网页时旧渲染器留作垫底（淡换完成
    /// 才拆）；网页→网页时页面自切——(70) B6 起先铺快照盖
    /// 再下发（见 installWebSwitchCoverThenPush），回执/超时
    /// 在 completeWebFade 同一出口结算。
    private func swapToWebRenderer(styleId: String) {
        if webEmbedStyleId == styleId {
            WebEffectBridge.shared.pushVisual(lyricMode: styleId, backgroundMode: nil)
            return
        }
        let backing = renderer
        // 网页→网页（已结算网页态再切网页式）：无原生垫底、
        // WebView alpha 恒 1，页面自切的清屏帧会透过透明页
        // （html,body background:0 0）与无底色的
        // rendererContainer 露出舞台黑底＝一闪黑屏（(70)
        // B6 定级）。此路改走快照盖；其余两路（原生→网页、
        // 未结算网页→网页尚有原生垫底）维持 (67) 直发。
        let isWebToWeb = webEmbedStyleId != nil && backing == nil
        activeStyleId = styleId
        armWebStyleProof(styleId: styleId)
        embedWebView()
        if backing != nil {
            WebEffectBridge.shared.webView.alpha = 0
        }
        webEmbedStyleId = styleId
        syncWebTouch81()
        WebEffectBridge.shared.isEmbeddedInStage = true
        if isWebToWeb {
            installWebSwitchCoverThenPush(styleId: styleId)
        } else {
            WebEffectBridge.shared.pushSnapshot()
            WebEffectBridge.shared.pushVisual(lyricMode: styleId, backgroundMode: nil)
            armWebFade(backing: backing)
        }
        Breadcrumbs.log("webfx.mount style=\(styleId) via=swap \(StyleOpenTrace.memoryFields())")
        Breadcrumbs.log("est.src style=\(styleId) est=web")
    }

    /// 网页→网页切换的快照盖（3.7 (70) B6）：对当前 WebView
    /// 用 WKWebView 官方 takeSnapshot 截图（异步、内容进程
    /// 合成后回图），回图后把图作不透明覆盖层压在 WebView
    /// 之上，再下发 pushSnapshot/pushVisual 并武装淡换——
    /// 页面自切全程被盖遮住，completeWebFade 在首帧回执
    /// （ack）或超时（1.8s/冷启 6s、既有口径）任一结算时把
    /// 盖交叉淡出，超时也只淡出不露黑。取图失败（image 为
    /// nil）则无盖直发（退回 (67) 行为、面包屑留痕）；截图
    /// 在途时目标式已被新一轮切换改写则整发作废，不下发
    /// 陈旧样式。
    private func installWebSwitchCoverThenPush(styleId: String) {
        let webView = WebEffectBridge.shared.webView
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self, self.webEmbedStyleId == styleId else { return }
            if let image {
                self.webSwitchCover70?.removeFromSuperview()
                let cover = UIImageView(image: image)
                cover.frame = self.rendererContainer.bounds
                cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                cover.contentMode = .scaleToFill
                cover.isUserInteractionEnabled = false
                self.rendererContainer.addSubview(cover)
                self.webSwitchCover70 = cover
                Breadcrumbs.log("webfx.cover style=\(styleId)")
            } else {
                Breadcrumbs.log("webfx.cover style=\(styleId) miss=1")
            }
            WebEffectBridge.shared.pushSnapshot()
            WebEffectBridge.shared.pushVisual(lyricMode: styleId, backgroundMode: nil)
            self.armWebFade(backing: nil)
        }
    }

    /// 网页运行同样武装防卡死守卫（(67) 独立审查修复）：网页
    /// 分支此前提前 return、守卫从未武装，页面加载失败/JS 崩
    /// 溃时开台长期空白无回退。证明双路结算——首帧回执在
    /// completeWebFade 的 ack 路径调 finishStyleProof；帧＋歌
    /// 词窗口在 frameStep 同一出口兜底。未 proven 而进程被杀
    /// 时，下次开台按 (44) 口径回退经典式。
    private func armWebStyleProof(styleId: String) {
        StageStyleStore.armStylePending(styleId)
        styleProofStyleId = styleId
        styleProofFrames = 0
        styleProofArmedAt = CACurrentMediaTime()
        styleProofFramesOK = false
        styleProofLyricsApplied =
            currentTrackId.flatMap { linesCache[$0] } != nil
    }

    /// WebView 嵌入 rendererContainer（与原生渲染器同级）：
    /// 交互全关——手势穿透回原生台面（三击轮换等识别器挂在
    /// container 上，照常收触）。
    private func embedWebView() {
        let webView = WebEffectBridge.shared.webView
        if webView.superview !== rendererContainer {
            webView.removeFromSuperview()
            rendererContainer.addSubview(webView)
            // 共享 WebView 的 translates 在 MainViewController/
            // 全屏宿主侧被置 false，本处走 frame＋autoresizing
            // 布局，必须显式置 true 才有约束保护（审查修复）；
            // detach 时复原 false。
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.frame = rendererContainer.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        webView.isUserInteractionEnabled = false
        rendererContainer.bringSubviewToFront(webView)
    }

    /// (81) 第 6 条：町景手势断点修复。断点定案（代码坐
    /// 实）：嵌入态 WebView 交互被整体关死（embedWebView
    /// 的 isUserInteractionEnabled=false 是 (67) 的穿透纪
    /// 律），网页层收不到任何触摸——町景的 OrbitControls
    /// 在源码与打包产物里都完好（createMachiRuntime 构
    /// 造时挂在画布上、enablePan/damping 全开），断点不
    /// 在网页侧、也不在打包差异，而在原生这一关。(79)
    /// 审计只核了网页链与「原生无拦截」，漏了交互总开关
    /// 本身。修法：仅町景嵌入时放行 WebView 交互（其余
    /// 网页样式维持穿透纪律、原生手势链零改动），并关
    /// WebView 自带滚动（防 scrollView 抢拖动；页面本体
    /// 非滚动布局）。原生三击/单击识别器挂在
    /// rendererContainer（祖先），触摸经子视图照常上达，
    /// 与町景拖拽分工：点按归原生、拖拽/捏合归画布。
    private func syncWebTouch81() {
        let webView = WebEffectBridge.shared.webView
        let machi = webEmbedStyleId == "machi"
        webView.isUserInteractionEnabled = machi
        webView.scrollView.isScrollEnabled = !machi
        Breadcrumbs.log("webfx.machi81 touch=\(machi ? 1 : 0)")
    }

    /// 淡换武装：回执（handleWebStyleFrame）或 1.8 秒超时任一
    /// 先到即淡换。超时取 1.8s 而非审计的 600ms：网页侧慢样式
    /// 首帧等待上限 FIRST_FRAME_LIMIT_MS=1500ms，600ms 会在
    /// 浮名等慢样式上抢跑露空档；旧帧全程垫底、不黑等。
    private func armWebFade(backing: LyricStageRenderer?) {
        webBackingRenderer = backing
        webSwapGeneration += 1
        let generation = webSwapGeneration
        webFadeWorkItem?.cancel()
        // 冷启放宽（(67) 独立审查修复）：页面尚在首装（bundle
        // 解析＋桥握手）时 1.8s 必然迟到、会淡入未就绪页；页
        // 面未 loaded 时放宽到 6s 并落 cold 面包屑区分。1.8s
        // 口径只覆盖「页面已就绪、样式首帧慢」一件事。
        let pageReady = WebEffectBridge.shared.isPageLoaded
        let timeout: TimeInterval = pageReady ? 1.8 : 6.0
        if !pageReady {
            Breadcrumbs.log("webfx.cold style=\(webEmbedStyleId ?? "-")")
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.webSwapGeneration else { return }
            Breadcrumbs.log("webfx.ackto style=\(self.webEmbedStyleId ?? "-")")
            self.completeWebFade(generation: generation, via: "timeout")
        }
        webFadeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func handleWebStyleFrame(_ styleId: String) {
        // (81) 第 3 条：旋转揭盖等的是同一路首帧回执——
        // 盖在场时先结算揭盖（与样式淡换武装相互独立）。
        if webRotCover81 != nil, styleId == webEmbedStyleId {
            revealWebRotCover81(via: "ack")
        }
        guard styleId == webEmbedStyleId, webFadeWorkItem != nil else { return }
        completeWebFade(generation: webSwapGeneration, via: "ack")
    }

    /// 淡换出口：网页层 0.35s easeOut 淡入，完成后拆垫底的
    /// 原生渲染器（汪汪队迁移等生命周期随 unmount 自然结算）。
    /// 网页→网页的快照盖（(70) B6）也在本出口同 0.35s 交叉
    /// 淡出后摘除——回执（ack）与超时（timeout）同一结算，
    /// 超时也只淡出、不露黑。
    private func completeWebFade(generation: Int, via: String) {
        guard generation == webSwapGeneration, webEmbedStyleId != nil else { return }
        webFadeWorkItem?.cancel()
        webFadeWorkItem = nil
        Breadcrumbs.log("webfx.fade via=\(via) style=\(webEmbedStyleId ?? "-")")
        // 首帧回执到 = 网页样式存活证明（守卫结算，审查修复）。
        if via == "ack" { finishStyleProof(via: "web-frame") }
        let webView = WebEffectBridge.shared.webView
        if let cover = webSwitchCover70 {
            webSwitchCover70 = nil
            UIView.animate(withDuration: 0.35, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) {
                cover.alpha = 0
            } completion: { _ in
                cover.removeFromSuperview()
            }
        }
        UIView.animate(withDuration: 0.35, delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            webView.alpha = 1
        } completion: { [weak self] _ in
            guard let self, generation == self.webSwapGeneration,
                  let old = self.webBackingRenderer else { return }
            self.webBackingRenderer = nil
            old.setLifecycle(.destroyed, active: false)
            old.unmount()
            old.view.removeFromSuperview()
            if self.renderer === old { self.renderer = nil }
        }
    }

    /// 摘嵌：WebView 回桥侧待命（页面不销毁），嵌入态清零。
    private func detachWebEmbed() {
        webFadeWorkItem?.cancel()
        webFadeWorkItem = nil
        webSwapGeneration += 1
        webBackingRenderer = nil
        // 快照盖（(70) B6）随摘嵌一并清，勿带出本台。
        webSwitchCover70?.removeFromSuperview()
        webSwitchCover70 = nil
        // (81) 第 3 条：旋转盖同清、揭盖计时作废。
        webRotGen81 += 1
        webRotRevealWork81?.cancel()
        webRotRevealWork81 = nil
        webRotCover81?.removeFromSuperview()
        webRotCover81 = nil
        guard webEmbedStyleId != nil else { return }
        let webView = WebEffectBridge.shared.webView
        if webView.superview === rendererContainer {
            webView.removeFromSuperview()
        }
        // 交互标志复原：嵌入态关交互是本台口径，全屏网页舞台
        // 宿主共用同一 WebView 实例，不许把关着的标志带过去。
        // (81) 第 6 条：町景放行时关过的自带滚动一并复原。
        webView.isUserInteractionEnabled = true
        webView.scrollView.isScrollEnabled = true
        // 布局标志复原（embed 时置 true 走 autoresizing，全屏
        // 宿主/MainViewController 口径为 false 约束布局）。
        webView.translatesAutoresizingMaskIntoConstraints = false
        WebEffectBridge.shared.isEmbeddedInStage = false
        webEmbedStyleId = nil
    }

    private func refreshStyleButton() {
        // (74) 第 8 项（Miller 定）：详情页右上角两样显示撤
        // 掉——①当前特效名不许显示；②「网页运行」徽标（(67)
        // A3/(70) 加的后缀）不许显示。胶囊只保留中性入口名
        // 「样式」（点按开选择器的切换入口与逻辑不动，特效
        // 本身不动）。原标题形如「样式 · 凝彩 · 网页运行」。
        styleButton.setTitle("样式", for: .normal)
        view.setNeedsLayout()
    }

    // MARK: 播放状态订阅

    private func subscribePlayback() {
        engine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self else { return }
                if track?.id != self.currentTrackId {
                    if let track { self.handleTrackChanged(to: track) }
                    else {
                        self.currentTrackId = nil
                        self.refreshHeader()
                        self.pushSnapshot()
                    }
                }
            }
            .store(in: &cancellables)
        engine.$currentArtwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                guard let self, let image, self.engine.currentTrack != nil else { return }
                self.applyBackdrop(image: image, trackId: self.engine.currentTrack?.id)
            }
            .store(in: &cancellables)
        engine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reanchor(armSettle: true)
                self.refreshPlayButton()
                self.renderer?.setLifecycle(
                    self.engine.isPlaying ? .playing : .paused,
                    active: self.view.window != nil)
            }
            .store(in: &cancellables)
        // 模式钮同步（3.7 (55) 工作流 D）：任一入口（队列面板/
        // 播放面板/顶排旧路）改 playMode，本钮 glyph 与菜单勾选
        // 即时跟随——同一 @Published 存储，无第二状态。
        queueManager.$playMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStageModeButton() }
            .store(in: &cancellables)
    }

    private func handleTrackChanged(to track: FoliaTrack) {
        lyricSwitchAt80 = CACurrentMediaTime()
        currentTrackId = track.id
        backdropTrackId = nil
        palette = .neutralDark
        backdropImageView.image = nil
        backdropTint.backgroundColor = palette.background.withAlphaComponent(0.5)
        refreshHeader()
        refreshLikeButton()
        reanchor(armSettle: true)
        pushSnapshot()
        loadLyrics(for: track)
        // (80) 逐歌记忆套用：本曲有记忆样式则切过去（在取词
        // 之后、与渲染器首帧同边沿；无记忆时为空操作）。
        applySongStyleMemory80(for: track)
        loadBackdropFallback(for: track)
        Breadcrumbs.log("stage track \(track.id) title=\(track.title)")
        // 点播台切歌边沿（3.7 (32)，与墙 refreshMiniBar 同
        // 构）：宠物切歌钩子 + 收起态先展开、否则重置计时。
        stagePetStage?.setTrack(id: track.id)
        // (62) 舞台歌曲卡：切歌通知（显隐/时长/位置由卡内读设置）。
        trackPill62.noteTrackChanged(track: track)
        trackPill62.place(in: view)
        if stageBarCollapsed { expandStageBar() } else { resetStageIdleTimer() }
        // 顶栏（3.7 (46)）：切歌时顶栏已隐藏则短暂恢复亮出新
        // 歌名，5 秒后照常自动隐藏；可见时只重置计时。
        if headerChromeHidden { showStageHeader(source: "track-change") }
        else { scheduleStageHeaderHide() }
    }

    private func refreshHeader() {
        let track = engine.currentTrack
        titleLabel.text = track?.title ?? "暂无播放"
        artistLabel.text = track?.artist ?? ""
        totalTimeLabel.text = Self.formatTime(engine.duration)
        // (82) 第 7 条：台内封面行同刷（与两面墙同源）。
        stageTitle82.text = track?.title ?? ""
        stageArtist82.text = track?.artist ?? ""
        if let art = engine.currentArtwork {
            stageCover82.image = art
        } else if let url = track?.artworkURL {
            let raw = url.absoluteString
            let tier = NativeCoverLoader.tier(forPixelExtent: 126)
            if let proxied = NativeCoverLoader.shared.proxiedURLString(raw, tier: tier) {
                if let cached = NativeCoverLoader.shared.cachedImage(for: proxied) {
                    stageCover82.image = cached
                } else {
                    stageCover82.image = nil
                    let trackId = track?.id
                    Task { [weak self] in
                        let image = await NativeCoverLoader.shared.image(for: proxied, tier: tier)
                        await MainActor.run {
                            guard let self,
                                  PlaybackEngine.shared.currentTrack?.id == trackId
                            else { return }
                            self.stageCover82.image = image
                        }
                    }
                }
            }
        } else {
            stageCover82.image = nil
        }
    }

    private func refreshPlayButton() {
        // (82) 第 7 条：字形走 DeckGlyph82（与两面墙同套）。
        playButton.setImage(
            DeckGlyph82.image(engine.isPlaying ? .pause : .play, pointSize: 21),
            for: .normal)
    }

    /// (82) 第 7 条：台面字形回刷——仅播/停态（上下曲字
    /// 形恒定、构建时已装）。旧 DeckIconSet81 随旧台退役。
    private func refreshDeckIcons82() {
        refreshPlayButton()
        // (83) 第 6 条：模式钮（stageModeButton83）随同点回刷。
        refreshStageModeButton83()
    }

    /// (83) 第 6 条：实际上台模式钮的字形＋菜单回刷——与
    /// 两面墙/控制台同源同字（顺序/循环/单曲/随机、off
    /// 压暗）；菜单动作与 (55) 模板钮 refreshStageMode
    /// Button 同路写 QueueManager.playMode，两钮状态经
    /// 本函数与模板回刷各自收口、不互相冒充。
    private func refreshStageModeButton83() {
        let mode = QueueManager.shared.playMode
        let glyph: DeckGlyph82.Kind
        switch mode {
        case .off: glyph = .modeSequence
        case .loopAll: glyph = .modeRepeat
        case .repeatOne: glyph = .modeRepeatOne
        case .shuffle: glyph = .shuffle
        }
        stageModeButton83.setImage(DeckGlyph82.image(glyph, pointSize: 16), for: .normal)
        stageModeButton83.tintColor = mode == .off
            ? UIColor.white.withAlphaComponent(0.55) : .white
        let items: [(QueueManager.PlayMode, String)] = [
            (.off, "顺序"), (.loopAll, "循环"), (.repeatOne, "单曲"), (.shuffle, "随机"),
        ]
        stageModeButton83.menu = UIMenu(children: items.map { item in
            let action = UIAction(title: item.1) { [weak self] _ in
                guard let self else { return }
                DeckTap82.log(host: "stage", zone: "mode", view: self.stageModeButton83)
                QueueManager.shared.playMode = item.0
                self.refreshStageModeButton83()
                self.refreshStageModeButton()
                self.resetStageIdleTimer()
                Breadcrumbs.log("deck83 mode host=stage m=\(item.0.rawValue)")
            }
            action.state = item.0 == mode ? .on : .off
            return action
        })
    }

    /// (83) 第 6 条：列表钮——播放队列面板（同一静态入口）。
    @objc private func stageListTapped83() {
        DeckTap82.log(host: "stage", zone: "list", view: stageListButton83)
        resetStageIdleTimer()
        QueuePanelViewController.present(from: self) { [weak self] in
            self?.resetStageIdleTimer()
        }
    }

    private func refreshLikeButton() {
        let liked = engine.currentTrack.map { LikesStore.shared.isLiked($0.id) } ?? false
        likeButton.setImage(
            UIImage(systemName: liked ? "heart.fill" : "heart"), for: .normal)
        // (68) A1：已喜欢 = 整钮填充喜欢色＋白心（不再只是描边
        // 心变色）；未喜欢维持现行（白描边心、无填充）。
        likeButton.tintColor = .white
        likeButton.backgroundColor = liked
            ? UIColor(red: 1, green: 0.35, blue: 0.45, alpha: 1) : .clear
    }

    // MARK: 歌词与封面

    /// 取词（3.7 (23) 改经共享仓库 LyricRepository）：此前舞台
    /// 每次打开都是新实例、实例级缓存恒空，进台才向 EdgeOne
    /// 现拉 /lyric（真机约 3s「暂无歌词」，audit-3723 §5.2），
    /// 且与墙面已取过的同一首歌不共享。改走仓库：墙面取过或
    /// 本会话开台取过的歌，仓库命中即时派生舞台形状（同一
    /// 张合并表）；实例级 linesCache 只留派生结果，不再决定
    /// 是否发网络请求。
    private func loadLyrics(for track: FoliaTrack) {
        if linesCache[track.id] != nil {
            logPrepMeasure80(trackId: track.id, path: "cache", hit: false)
            pushSnapshot()
            noteStyleProofLyricsApplied()
            // 贴纸层（3.7 (24)，纯新增钩子）：缓存命中即已落定。
            stickerLyricsResolved(lines: linesCache[track.id] ?? [])
            return
        }
        // (80) 下一首预备命中：协调器在上一首播放期间已预拉
        // ＋预派生行表，直接落定（就绪延迟应 ≈0–数 ms，见
        // logPrepMeasure80）；未命中照走下面原路，不更慢。
        if let prepared = NextTrackPrep80.shared.consume(trackId: track.id) {
            linesCache[track.id] = prepared.lines
            logPrepMeasure80(trackId: track.id, path: "prep", hit: true)
            pushSnapshot()
            noteStyleProofLyricsApplied()
            stickerLyricsResolved(lines: prepared.lines)
            return
        }
        if let hit = LyricRepository.shared.cachedEntry(for: track.id) {
            linesCache[track.id] = LyricParser.stageLines(
                from: hit.lines, trackDuration: track.duration,
                singingRatio: hit.singingRatio)
            logPrepMeasure80(trackId: track.id, path: "repo", hit: false)
            pushSnapshot()
            noteStyleProofLyricsApplied()
            // 贴纸层（3.7 (24)，纯新增钩子）：仓库命中即已落定。
            stickerLyricsResolved(lines: linesCache[track.id] ?? [])
            return
        }
        lyricsTask?.cancel()
        // 贴纸层（3.7 (24)，纯新增钩子）：网络取词开始，亮角标。
        stickerLyricsFetching()
        let trackId = track.id
        let duration = track.duration
        lyricsTask = Task { [weak self] in
            let entry = await LyricRepository.shared.entry(for: trackId)
            guard let self, !Task.isCancelled, self.currentTrackId == trackId else { return }
            let lines = LyricParser.stageLines(from: entry.lines, trackDuration: duration,
                                               singingRatio: entry.singingRatio)
            self.linesCache[trackId] = lines
            self.logPrepMeasure80(trackId: trackId, path: "net", hit: false)
            // wordLines（3.7 (50)，DS YRC50 评审）：证明真戳已
            // 进入舞台行表（与仓库 lrc source 的 withWords 对照，
            // 两处一致才算管线全通）。
            let wordLines = lines.filter { $0.words != nil }.count
            Breadcrumbs.log("stage lrc parsed track=\(trackId) lines=\(lines.count) source=\(entry.source) wordLines=\(wordLines)")
            // §0 扫光相位来源（3.7 (67) B 组）：无戳行的词分布
            // 由 r（singingRatio）合成——相位误差的来源点在此
            // 记账（r 值＋wordSrc 分组），与 sync.probe sweep50
            // 的实测过线时刻对位判读。
            Breadcrumbs.log("sweep.ph src=parser track=\(trackId) r=\(SyncProbe67.fmt(entry.singingRatio)) src=\(SyncProbe67.wordSource(of: lines)) lines=\(lines.count)")
            self.noteStyleProofLyricsApplied()
            self.pushSnapshot()
            // 贴纸层（3.7 (24)，纯新增钩子）：取词落定。
            self.stickerLyricsResolved(lines: lines)
        }
    }

    /// (80) 预备量测出口：自切歌边沿（lyricSwitchAt80）到行
    /// 表落定 linesCache 的延迟，四条落定路径（cache/prep/
    /// repo/net）各一行。prep.hit80 记命中与否、prep.ms80 记
    /// 毫秒与路径——判读时 prep 路径的 ms 应≈个位数，net 路
    /// 径即现拉全程（与 (71) 实测 2.1s 歌词迟到同口径对位）。
    private func logPrepMeasure80(trackId: String, path: String, hit: Bool) {
        let ms = Int((CACurrentMediaTime() - lyricSwitchAt80) * 1000)
        Breadcrumbs.log("prep.hit80 hit=\(hit ? 1 : 0) track=\(trackId)")
        Breadcrumbs.log("prep.ms80 ms=\(ms) path=\(path) track=\(trackId)")
    }

    private func loadBackdropFallback(for track: FoliaTrack) {
        guard engine.currentArtwork == nil, let raw = track.artworkURL?.absoluteString else { return }
        backdropTask?.cancel()
        let trackId = track.id
        backdropTask = Task { [weak self] in
            let loader = NativeCoverLoader.shared
            let urlString = loader.proxiedURLString(raw, tier: 1024) ?? raw
            let image = await loader.image(for: urlString, tier: 1024)
            guard let self, !Task.isCancelled, self.currentTrackId == trackId,
                  let image, self.engine.currentArtwork == nil else { return }
            self.applyBackdrop(image: image, trackId: trackId)
        }
    }

    private func applyBackdrop(image: UIImage, trackId: String?) {
        guard backdropTrackId != trackId else { return }
        backdropTrackId = trackId
        backdropImageView.image = image
        palette = StagePalette.tokens(from: image)
        // (62) 主题系统：封面到货生成歌曲主题（StagePalette 既有通路）；
        // 优先自定义时以所选预设强调色覆写 palette accent（三处消费之一）。
        ThemeSystem62.noteTrackArtwork(image: image, trackId: trackId)
        if SettingsStore.preferCustomTheme {
            palette.accent = ThemeSystem62.selectedPreset.accent
            Breadcrumbs.log("theme62.stage palette accent=custom-preset")
        } else if ThemeSystem62.songThemeActive {
            Breadcrumbs.log("theme62.stage palette accent=song-theme")
        }
        // (62) 场景系统：tint alpha 走场景基线（影厅更暗、书房更柔）。
        backdropTint.backgroundColor = palette.background
            .withAlphaComponent(CGFloat(SceneSystem62.params().tintAlpha))
        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        let estMB = Double(pixelWidth * pixelHeight * 4) / 1_048_576
        Breadcrumbs.log(String(
            format: "stage gate backdrop decoded %dx%d estMB=%.1f",
            pixelWidth, pixelHeight, estMB))
        pushSnapshot()
    }

    // MARK: 快照与锚点

    private func makeSnapshot() -> LyricStageSnapshot {
        let track = engine.currentTrack
        return LyricStageSnapshot(
            protocolVersion: LyricStageProtocolInfo.version,
            track: track.map { TrackMeta(track: $0) },
            lines: track.flatMap { linesCache[$0.id] } ?? [],
            palette: palette,
            styleId: activeStyleId,
            styleVersion: LyricStageRegistry.info(for: activeStyleId)?.styleVersion ?? 1,
            viewport: LyricStageViewport(
                size: view.bounds.size,
                safeAreaInsets: view.safeAreaInsets,
                dynamicTypeScale: 1),
            anchor: anchor,
            hostCapabilities: LyricStageProtocolInfo.hostCapabilities,
            ext: ["entry": "native-stage"])
    }

    private func pushSnapshot() {
        renderer?.applySnapshot(makeSnapshot())
        refreshHeader()
    }

    /// 锚点（3.7 (23) 改真值，DS R49 Q2）：此前取
    /// engine.currentTime——200ms 周期 observer 的台阶缓存，
    /// 引擎自家注释明文禁止歌词锚点读它（恒滞后真值
    /// 0–200ms）；且 checkDrift 拿同一缓存自比，恒定滞后永
    /// 不纠正（audit-3723 §5.1 实测舞台翻行晚行界
    /// +0.48~0.68s 的主因）。改直读 rawPlayhead() 真值；每
    /// 次重锚落 `stage anchor` 面包屑（锚值 + raw 与旧台阶
    /// 缓存之差），补舞台路径此前零锚点埋点的可观测性缺口。
    ///
    /// armSettle（3.7 (41) 组3，移植墙面 (20) 定案）：瞬态锚
    /// （开台/切歌/播停翻转）采在播放器时钟起步瞬态上，外推
    /// 可带进亚阈值恒定相位差（墙面实测约 +0.09–0.10）且死
    /// 区内无人纠正、整场存活。修法同墙面：瞬态锚在 +0.35s
    /// 后做一次稳态重锚（performSettle），纠正量落
    /// `stage settle drift=`；漂移重锚采行进中真值、不 arm，
    /// 避免链式重锚（窗口内重武装见 checkDrift）。
    private func reanchor(armSettle: Bool = false) {
        let raw = engine.rawPlayhead()
        anchor = PlaybackAnchor(
            trackId: engine.currentTrack?.id ?? "",
            positionAtAnchor: raw,
            wallTimeAtAnchor: CACurrentMediaTime(),
            rate: engine.isPlaying ? 1 : 0,
            anchorSeq: anchor.anchorSeq + 1)
        Breadcrumbs.log("stage anchor pos=\(String(format: "%.3f", raw)) cacheDelta=\(String(format: "%.3f", raw - engine.currentTime)) seq=\(anchor.anchorSeq)")
        // §0 出声基准·锚点采样（3.7 (67) B 组）：起播/切歌/播停
        // 与漂移重锚各一行，route/outLat/ioBuf 与 raw 同行对位。
        let af0 = SyncProbe67.audioFields()
        Breadcrumbs.log("sync.snd0 arm=\(armSettle ? 1 : 0) raw=\(SyncProbe67.fmt(raw)) route=\(af0.route) outLat=\(SyncProbe67.fmt(af0.outLat)) ioBuf=\(SyncProbe67.fmt(af0.ioBuf)) wall=\(SyncProbe67.fmt(CACurrentMediaTime()))")
        if armSettle {
            settleRearmCount = 0
            if engine.isPlaying, LyricTiming.settleReanchorEnabled {
                settleTrackId = engine.currentTrack?.id
                settleReanchorAt = CACurrentMediaTime() + Self.settleWindow
                settleTimer?.invalidate()
                settleTimer = Timer.scheduledTimer(
                    withTimeInterval: Self.settleWindow, repeats: false) { [weak self] _ in
                    self?.performSettle()
                }
            } else {
                if settleReanchorAt != nil {
                    Breadcrumbs.log("stage settle disarm reason=not-playing")
                }
                disarmSettle()
            }
        }
    }

    private func disarmSettle() {
        settleTimer?.invalidate()
        settleTimer = nil
        settleReanchorAt = nil
        settleTrackId = nil
    }

    /// 稳态重锚落点（3.7 (41) 组3）：武装时刻 +0.35s 触发；
    /// 已暂停/已切歌则作废并留痕（墙面同口径）。纠正量同记
    /// 三基准（engine 台阶缓存 / rawPlayhead 真值 / 锚外推），
    /// 与墙面 `lrc clock settle drift=` 同字段供对账。
    private func performSettle() {
        settleTimer = nil
        guard settleReanchorAt != nil else { return }
        settleReanchorAt = nil
        guard LyricTiming.settleReanchorEnabled else { return }
        guard engine.isPlaying else {
            Breadcrumbs.log("stage settle disarm reason=paused")
            return
        }
        guard engine.currentTrack?.id == settleTrackId else {
            Breadcrumbs.log("stage settle disarm reason=track-changed")
            return
        }
        let extrapolated = positionNow()
        let raw = engine.rawPlayhead()
        let drift = raw - extrapolated
        reanchor()
        Breadcrumbs.log("stage settle drift=\(String(format: "%.3f", drift)) engine=\(String(format: "%.3f", engine.currentTime)) raw=\(String(format: "%.3f", raw)) extrapolated=\(String(format: "%.3f", extrapolated))")
        // §0 出声基准·settle 补读（3.7 (67) B 组）：现行 settle
        // 行同点补 outLat/route，判读恒定偏移时先扣出声延迟。
        let afS = SyncProbe67.audioFields()
        Breadcrumbs.log("sync.setl drift=\(SyncProbe67.fmt(drift)) judge=\(SyncProbe67.fmt(extrapolated)) raw=\(SyncProbe67.fmt(raw)) route=\(afS.route) outLat=\(SyncProbe67.fmt(afS.outLat))")
    }

    private func positionNow() -> TimeInterval {
        // 全局歌词时间轴偏移（3.7 (55) 工作流 G 做真、协调者集成）：
        // 舞台链与墙链（LyricTiming.lead）同吃 SettingsStore 偏移，
        // 正值歌词提前、负值延后，改设置即时生效。
        anchor.position(atWallTime: CACurrentMediaTime())
            + SettingsStore.lyricTimelineOffsetSeconds
    }

    /// 漂移校正（3.7 (23) 定比对对象为 rawPlayhead 真值、禁
    /// 自比；3.7 (41) 组3 纠偏纪律向墙面看齐）：阈值改用墙面
    /// 同一常量 LyricTiming.reanchorThreshold（0.12，不再各
    /// 守一套死区），超限即重锚——去掉 (23) 的连续 2 次确认
    /// （≈0.6s 确认窗被审计点名为锯齿来源；墙面逐帧即时重
    /// 锚已实证稳定）。0.3s 检查周期保留（本台无逐帧时钟维
    /// 护点，frameStep 只管渲染与行级面包屑）。settle 武装
    /// 窗口内的漂移重锚按墙面 (22) 口径重新武装 settle，上
    /// 限 3 次，超限永久解除并留痕。
    private func checkDrift() {
        guard engine.currentTrack != nil else { return }
        guard abs(engine.rawPlayhead() - positionNow())
                > LyricTiming.reanchorThreshold else { return }
        let settleWasArmed = settleReanchorAt != nil
        reanchor()
        if settleWasArmed {
            if LyricTiming.settleReanchorEnabled, engine.isPlaying,
               settleRearmCount < Self.settleRearmLimit {
                settleRearmCount += 1
                settleTrackId = engine.currentTrack?.id
                settleReanchorAt = CACurrentMediaTime() + Self.settleWindow
                settleTimer?.invalidate()
                settleTimer = Timer.scheduledTimer(
                    withTimeInterval: Self.settleWindow, repeats: false) { [weak self] _ in
                    self?.performSettle()
                }
                Breadcrumbs.log("stage settle rearm n=\(settleRearmCount) reason=drift")
            } else {
                disarmSettle()
                Breadcrumbs.log("stage settle disarm reason=drift-cap n=\(settleRearmCount)")
            }
        }
    }

    // MARK: 命令处理（与迷你台/展开卡同一入口）

    private func handleCommand(_ command: LyricStageCommand) {
        Breadcrumbs.log("stage cmd \(command.kind.logName) from=\(command.source)")
        switch command.kind {
        case .toggle:
            engine.togglePlayPause()
        case .seek(let position):
            performSeek(to: position, source: command.source)
        case .next:
            queueManager.playNext(manual: true)
        case .prev:
            queueManager.playPrevious()
        case .like:
            toggleLike()
        case .close:
            closeStage()
        }
    }

    private func performSeek(to position: TimeInterval, source: String) {
        engine.seek(to: position)
        anchor = PlaybackAnchor(
            trackId: engine.currentTrack?.id ?? "",
            positionAtAnchor: position,
            wallTimeAtAnchor: CACurrentMediaTime(),
            rate: engine.isPlaying ? 1 : 0,
            anchorSeq: anchor.anchorSeq + 1)
        Breadcrumbs.log("stage gate seek to=\(Int(position))s from=\(source)")
    }

    private func toggleLike() {
        guard let track = engine.currentTrack else { return }
        let id = track.id
        let newState = LikesStore.shared.toggle(id)
        refreshLikeButton()
        // 贴纸层（3.7 (24)，纯新增）：点亮时红心左侧浮贴纸；
        // 取消收藏补依依不舍贴纸（3.7 (28)），同一落点成对。
        if newState { stickerShowLikeCelebration() }
        else { stickerShowUnlikeSticker() }
        Task { [weak self] in
            do {
                _ = try await NativeDataClient.shared.setLike(trackId: id, like: newState)
            } catch {
                LikesStore.shared.toggle(id)
                self?.refreshLikeButton()
            }
        }
    }

    private func closeStage() {
        // 统一退出闸门（3.7 (46)）：用户关台先登记来源再
        // dismiss；守卫期内用户退出立即放行并 settle route。
        guard StageExitGate.shared.requestExit(
            source: .userCloseTap, userInitiated: true, stage: self,
            caller: "closeStage") else { return }
        dismiss(animated: true)
    }

    private func jumpToWebStage(reason: String) {
        guard !webJumpFired else { return }
        webJumpFired = true
        // 嵌入态先摘嵌（(67) 独立审查修复）：全屏宿主与台面嵌
        // 入共用同一 WebView，带嵌入态跳走会把「关交互＋已摘
        // 出容器」的中间态带进宿主，且宿主关闭后嵌入状态残
        // 留、台面网页层消失。摘嵌后宿主自管该 WebView，关闭
        // 时 onClosed 按需重装本台当前样式。
        if webEmbedStyleId != nil { detachWebEmbed() }
        Breadcrumbs.log("stage fallback to web: \(reason)")
        // 跳网页舞台 = 程序化正当转移（3.7 (46)）：目的地仍是
        // 舞台，闸门放行并 settle route，不走守卫 veto。
        StageExitGate.shared.approveProgrammaticExit(stage: self, reason: reason)
        // (51) 新链：网页舞台叠加 present 在本台之上（旧链是替
        // 换式：关原生舞台+收整摞墙、靠回程票重建）。本台不退
        // 场——播放/队列/所选样式状态原样保留；网页舞台关闭后
        // 宿主 dismiss，呈现栈直接落回本台。
        // 轻量返回上下文 = 打开网页舞台前本台在演的原生样式 id
        // （activeStyleId）：宿主关闭时把 StageStyleStore 的选
        // 择器状态对齐回它（选网页样式时写入的 web id 只服务
        // 本次网页会话，关后不许与本台实际样式脱节）。
        let returnStyleId = activeStyleId
        let host = WebStageHostViewController()
        host.modalPresentationStyle = .fullScreen
        host.onClosed = { [weak self] in
            guard let self else { return }
            self.webJumpFired = false
            if StageStyleStore.currentStyleId != returnStyleId {
                StageStyleStore.currentStyleId = returnStyleId
            }
            // 跳走前若摘过嵌（审查修复）：台面已无任何呈现层，
            // 按返回样式重装一遍（原生/网页由运行位分流）。
            if self.webEmbedStyleId == nil && self.renderer == nil {
                self.applyNativeStyleSelection(returnStyleId)
            }
            Breadcrumbs.log("webstage return style=\(returnStyleId)")
        }
        let presentHost = { [weak self] in
            guard let self else { return }
            guard self.presentedViewController == nil else {
                self.webJumpFired = false
                Breadcrumbs.log("webstage present skipped reason=already-presenting")
                return
            }
            self.present(host, animated: true) {
                // 宿主在场后才请前端开页：openStage 意图投给已
                // 入窗的 WebView（13.5 闭环口径不变）。
                WebEffectBridge.shared.requestOpenStage()
            }
        }
        // 装配失败回退（mountRenderer 在 viewDidLoad 内调本函
        // 数）时本台尚在被呈现途中，同帧 present 必失败，延一
        // 拍等本台落位；其余入口（选择器/提示条）本台已在窗内，
        // 直接呈现。
        if isBeingPresented || view.window == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { presentHost() }
        } else {
            presentHost()
        }
    }

    // MARK: 按钮动作

    @objc private func closeTapped() { closeStage() }
    // (84) 第 3 条：四钮 touchDown 见证（同两面墙）。
    @objc private func stagePlayDown84() {
        Tap84.log(host: "stage", btn: "play", ev: "down", view: playButton)
    }

    @objc private func stagePrevDown84() {
        Tap84.log(host: "stage", btn: "prev", ev: "down", view: prevButton)
    }

    @objc private func stageNextDown84() {
        Tap84.log(host: "stage", btn: "next", ev: "down", view: nextButton)
    }

    @objc private func stageConsoleDown84() {
        Tap84.log(host: "stage", btn: "console", ev: "down", view: stageConsoleButton82)
    }

    @objc private func playTapped() {
        Tap84.log(host: "stage", btn: "play", ev: "up", view: playButton)
        DeckTap82.log(host: "stage", zone: "play", view: playButton)
        resetStageIdleTimer()
        scheduleStageHeaderHide()
        handleCommand(LyricStageCommand(kind: .toggle, source: "stage.controls"))
    }
    @objc private func prevTapped() {
        Tap84.log(host: "stage", btn: "prev", ev: "up", view: prevButton)
        DeckTap82.log(host: "stage", zone: "prev", view: prevButton)
        resetStageIdleTimer()
        scheduleStageHeaderHide()
        handleCommand(LyricStageCommand(kind: .prev, source: "stage.controls"))
    }
    @objc private func nextTapped() {
        Tap84.log(host: "stage", btn: "next", ev: "up", view: nextButton)
        DeckTap82.log(host: "stage", zone: "next", view: nextButton)
        resetStageIdleTimer()
        scheduleStageHeaderHide()
        handleCommand(LyricStageCommand(kind: .next, source: "stage.controls"))
    }

    /// (82) 第 8 条：控制台入口——升起 ConsolePanel82。
    @objc private func stageConsoleTapped82() {
        Tap84.log(host: "stage", btn: "console", ev: "up", view: stageConsoleButton82)
        DeckTap82.log(host: "stage", zone: "console", view: stageConsoleButton82)
        resetStageIdleTimer()
        ConsolePanel82.present(from: self)
    }

    // 播放列表图标 queueTapped 已于 (60) 第 10 条随钮删除；队列
    // 面板改由点播台面板页签/命令面板进入（QueuePanel 本体保留）。
    @objc private func likeTapped() {
        scheduleStageHeaderHide()
        handleCommand(LyricStageCommand(kind: .like, source: "stage.controls"))
    }

    /// (82) 第 8 条：控制台特效钮入口（控制台先自关再调
    /// 本方法开选择器，呈现链不断）。
    func openStylePicker82() { styleTapped() }

    @objc private func styleTapped() {
        let picker = StageStylePickerViewController(activeStyleId: activeStyleId)
        picker.onPickNative = { [weak self] styleId in
            guard let self else { return }
            StageStyleStore.currentStyleId = styleId
            self.dismiss(animated: true) { [weak self] in
                self?.noteSongStyleMemory80(styleId)
                self?.applyNativeStyleSelection(styleId)
            }
        }
        picker.onPickWeb = { [weak self] info in
            guard let self else { return }
            StageStyleStore.currentStyleId = info.id
            self.dismiss(animated: true) { [weak self] in
                self?.noteSongStyleMemory80(info.id)
                self?.applyWebStyleSelection(
                    info, reason: "picker web style \(info.id)")
            }
        }
        picker.onOpenWebStage = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) { [weak self] in
                self?.jumpToWebStage(reason: "picker open web stage entry")
            }
        }
        picker.onPickCustomBackground = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) { [weak self] in
                self?.presentCustomBackgroundPicker()
            }
        }
        picker.onClearCustomBackground = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                CustomBackgroundStore.clear()
                Breadcrumbs.log("custombg.clear")
                self.refreshCustomBackground()
            }
        }
        picker.modalPresentationStyle = .pageSheet
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(picker, animated: true)
    }

    // MARK: 模式可见钮（3.7 (55) 工作流 D/DS 修正3）

    /// 四档顺序与命名：与队列面板 modes / 播放面板 modes 同表
    /// （顺序 off / 循环 loopAll / 单曲 repeatOne / 随机 shuffle）。
    private static let stageModeEntries: [(mode: QueueManager.PlayMode, name: String, glyph: String)] = [
        (.off, "顺序", "arrow.right"),
        (.loopAll, "循环", "repeat"),
        (.repeatOne, "单曲", "repeat.1"),
        (.shuffle, "随机", "shuffle"),
    ]

    /// glyph 语义：与既有顶排/迷你台模式图标同套（循环 repeat、
    /// 单曲 repeat.1、随机 shuffle）；顺序（off）原同套里与循环
    /// 共用 repeat 只靠明暗区分——正是 (55) 必修「图标语义撞车」
    /// 的原案，故本钮给顺序独立 glyph arrow.right（直行=顺序播
    /// 放），四档互不相同；off 态另保留 0.45 明暗作第二信号。
    private func refreshStageModeButton() {
        let mode = queueManager.playMode
        let entry = Self.stageModeEntries.first { $0.mode == mode }
        // (82) 第 7 条：字形走 DeckGlyph82（四档同一映射）；
        // 本钮已不上台（模式职能进控制台），回刷仅保持对
        // 象状态一致。菜单项图仍用条目 SF 名。
        let glyph82: DeckGlyph82.Kind
        switch mode {
        case .off: glyph82 = .modeSequence
        case .loopAll: glyph82 = .modeRepeat
        case .repeatOne: glyph82 = .modeRepeatOne
        case .shuffle: glyph82 = .shuffle
        }
        stageModeButton.setImage(
            DeckGlyph82.image(glyph82, pointSize: 15),
            for: .normal)
        stageModeButton.tintColor = mode == .off
            ? UIColor.white.withAlphaComponent(0.45) : .white
        stageModeButton.accessibilityLabel = "播放模式：\(entry?.name ?? "")"
        let actions = Self.stageModeEntries.map { item in
            UIAction(title: item.name,
                     image: UIImage(systemName: item.glyph),
                     state: item.mode == mode ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.resetStageIdleTimer()
                self.queueManager.playMode = item.mode
                Breadcrumbs.log("stage mode=\(item.mode.rawValue) src=mode-button")
            }
        }
        stageModeButton.menu = UIMenu(title: "播放模式", children: actions)
        stageModeButton.showsMenuAsPrimaryAction = true
    }

    // MARK: 面板呈现（3.7 (55) 工作流 D：播放面板/命令面板）
    //
    // 入口都是点播台顶排信号（工作流 C 发出、本台在
    // buildLayout 订阅）：呈现一律 pageSheet（命令面板大 detent
    // 在其自身 present 内定），不触发舞台 viewWillDisappear、
    // 不惊动 StageExitGate；关闭后由各面板自身 onDismiss/系统
    // dismiss 回落，宿主在这里只重置无操作计时与顶栏隐藏
    // （handler 进入时已做）。字幕面板入口已随 (60) 第 11 条删除。

    /// 本台响应信号的守卫：三台 quick row 都发同一信号，只有真
    /// 正 在窗且未在呈现其他面的舞台响应（墙台在场时本台不在窗，
    /// 天然不响应）。
    private func stagePanelSignalAllowed(_ name: String) -> Bool {
        guard view.window != nil, presentedViewController == nil else {
            Breadcrumbs.log("stage.panel.signal skip name=\(name) reason=not-top")
            return false
        }
        resetStageIdleTimer()
        scheduleStageHeaderHide()
        return true
    }

    @objc private func stageMiniBarPanelTapped() {
        guard stagePanelSignalAllowed("panel") else { return }
        PlaybackPanelViewController.present(from: self)
    }

    @objc private func stageMiniBarCommandTapped() {
        guard stagePanelSignalAllowed("command") else { return }
        CommandPaletteViewController.present(from: self) { [weak self] palette in
            guard let self else { return }
            // 跨面跳转：命令面板关闭后由本台呈现目标面（样式选择
            // 必须走本台的选样式通路，见 presentStylePickerForPalette）。
            // 字幕调节跳转已随 (60) 第 11 条删除（面板本体退役）。
            palette.onOpenQueuePanel = { [weak self] in
                guard let self, self.presentedViewController == nil else { return }
                PlaybackPanelViewController.present(from: self, initialTab: .queue)
            }
            palette.onOpenStylePicker = { [weak self] in
                self?.presentStylePickerForPalette()
            }
        }
    }

    /// 命令面板「选择可视化」的落点：与 styleTapped 同一套选择器
    /// 接线（onPickNative/onPickWeb/onOpenWebStage/onPickCustom-
    /// Background + 清除背景），保证经命令面板选样式与顶栏样式钮
    /// 选样式结果完全一致（同一 applyNativeStyleSelection 通路）。
    private func presentStylePickerForPalette() {
        guard presentedViewController == nil else { return }
        let picker = StageStylePickerViewController(activeStyleId: activeStyleId)
        picker.onPickNative = { [weak self] styleId in
            guard let self else { return }
            StageStyleStore.currentStyleId = styleId
            self.dismiss(animated: true) { [weak self] in
                self?.noteSongStyleMemory80(styleId)
                self?.applyNativeStyleSelection(styleId)
            }
        }
        picker.onPickWeb = { [weak self] info in
            guard let self else { return }
            StageStyleStore.currentStyleId = info.id
            self.dismiss(animated: true) { [weak self] in
                self?.noteSongStyleMemory80(info.id)
                self?.applyWebStyleSelection(
                    info, reason: "palette web style \(info.id)")
            }
        }
        picker.onOpenWebStage = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) { [weak self] in
                self?.jumpToWebStage(reason: "palette open web stage entry")
            }
        }
        picker.onPickCustomBackground = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) { [weak self] in
                self?.presentCustomBackgroundPicker()
            }
        }
        picker.onClearCustomBackground = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                CustomBackgroundStore.clear()
                Breadcrumbs.log("custombg.clear")
                self.refreshCustomBackground()
            }
        }
        picker.modalPresentationStyle = .pageSheet
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        Breadcrumbs.log("stage.palette.stylePicker open")
        present(picker, animated: true)
    }

    @objc private func noticeWebTapped() {
        // 回网页版看的正是当前记录样式：三击轮换袋子同步对
        // 账（该样式本轮不再被递出，见工作流 R 对账规则）。
        StageStyleCycleBag.shared.noteExternalSelection(StageStyleStore.currentStyleId)
        jumpToWebStage(reason: "notice web jump style=\(StageStyleStore.currentStyleId)")
    }

    @objc private func noticeCloseTapped() {
        noticeDismissed = true
        noticeBar.isHidden = true
        view.setNeedsLayout()
    }

    // MARK: - 点播台（3.7 (32)：与墙台同规格的同步改造）
    //
    // 结构与参数逐项对齐墙台（WallPrototypeViewController 的
    // buildMiniBar 一族）：70pt 玻璃胶囊（systemUltraThin-
    // MaterialDark + 1pt 亮边 + rim 高光 + 0.06 白罩）、同款
    // MiniPlayerThemeLayer 主题层（同一主题来源/存储/变更通
    // 知）、底部内缘进度轨（左右内缩 20、高 4、底距 −7）+
    // 发光圆钮/主题圆点皮肤、底部 20pt seek 命中带（拖动只
    // 更填充、松手 seek；点按按轨道实际帧算比例跳点）、长按
    // 0.55s 循环切主题、闲置 5 秒收成 16pt 细条（轨道底距
    // −6、圆角 8、命中带纵向外扩 14pt 至 44pt、主题层/毛玻
    // 璃/高光全隐、填充走收起态兜底色、圆点保留主题皮肤）、
    // 形态弹簧 0.5s/damping 0.85/velocity 0.1、Reduce Motion
    // 降级为 0.2s 纯 alpha。去重变体差异只有两处：无封面缩
    // 略与标题/歌手行（页眉已有）；三键居中排布（墙台靠右，
    // 因其左侧有封面标题），两侧补时间标签（旧控制带既有
    // 元素保留）。命令落点与墙完全相同：toggle →
    // PlaybackEngine.togglePlayPause、next/prev →
    // QueueManager（经 handleCommand 统一入口）、seek →
    // PlaybackEngine.seek（经 performSeek）。进度源仍是既有
    // StageProgressDriver（viewWillDisappear 必 stop），不新
    // 造第二套。

    /// (75) 工具条朝向切换（与主页墙同构）。
    func applySeamBandOrientation(portrait: Bool) {
        guard seamBandIsPortrait != portrait,
              !seamBandPortrait.isEmpty, !seamBandLandscape.isEmpty else { return }
        seamBandIsPortrait = portrait
        NSLayoutConstraint.deactivate(portrait ? seamBandLandscape : seamBandPortrait)
        NSLayoutConstraint.activate(portrait ? seamBandPortrait : seamBandLandscape)
        Breadcrumbs.log("seam.wrap75 host=stage portrait=\(portrait ? 1 : 0)")
    }

    /// (74) 播放详情页缝合工具条：与主页/歌单页同款。落位：
    /// 本页顶部行是舞台头（关闭键/标题/喜欢，safe.top+6 起
    /// 38 高、样式钮至 +74），工具条落其下——top = safeArea
    /// .top + 82（= layoutStage 的 contentTop），左锚贴安全
    /// 区（横屏绕岛）、全宽、44 高；收起横线在左端（条内左
    /// 锚）。动作全转发回主页（与歌单页同路）：本台 dismiss
    /// 有 StageExitGate 守卫，转发前先经闸门程序化放行
    /// （approveProgrammaticExit），不绕闸。
    /// (75) 竖屏改绕岛带：条体钉屏幕顶边全宽、高 191（凹
    /// 口 0–56＋舞台头空带＋内容行 141–185＋底衬 6，内容
    /// 行顶 141 与 (74) 的 safeArea.top+82 同位）；横屏回
    /// (74) 侧锚组。带内空域点按穿透（SeamToolbarView 命
    /// 中纪律），舞台头控件在带下仍可点。
    private func installStageSeamToolbar74() {
        let toolbar = SeamToolbarView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wrapIslandEnabled = true
        toolbar.contentRowTop = 141
        view.addSubview(toolbar)
        let bandP: [NSLayoutConstraint] = [
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 191),
        ]
        let bandL: [NSLayoutConstraint] = [
            toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 82),
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
            self?.stageSeamForward74("segment-\(segment.crumbName)")
        }
        toolbar.onAvatarTapped = { [weak self] in self?.stageSeamForward74("avatar") }
        toolbar.onSearchTapped = { [weak self] in self?.stageSeamForward74("search") }
        toolbar.onSettingsTapped = { [weak self] in self?.stageSeamForward74("settings") }
        toolbar.onGuideTapped = { [weak self] in self?.stageSeamForward74("guide") }
        toolbar.onLatticeTapped = { [weak self] in self?.stageSeamForward74("lattice") }
        toolbar.onLayoutTapped = { [weak self] in self?.stageSeamForward74("layout") }
        toolbar.onFullscreenTapped = { [weak self] in self?.stageSeamForward74("fullscreen") }
        stageSeamToolbar = toolbar
        Breadcrumbs.log("stage.seam74 installed")
    }

    /// (74) 舞台工具条动作转发：先经 StageExitGate 程序化
    /// 放行（目的地是主页既有面、正当转移），再走统一转发
    /// （关本台回主页执行主页同名动作）。
    /// (75) 第 7 项分流：全局面（设置/账户/搜索/导播台）在
    /// 本页就地展开——不关台、不经闸门（闸门只管离台）；
    /// 只有主页墙状态动作仍走关台转发。
    private func stageSeamForward74(_ action: String) {
        if SeamToolbarForwarding.isGlobalAction(action) {
            SeamToolbarForwarding.performInPlace(
                action, from: self, toolbar: stageSeamToolbar)
            return
        }
        StageExitGate.shared.approveProgrammaticExit(stage: self, reason: "seam74-\(action)")
        SeamToolbarForwarding.forward(action, from: self)
    }

    private func buildStageBar() {
        let bar = stageBar
        bar.backgroundColor = .clear
        bar.layer.cornerRadius = 35
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOpacity = 0.25
        bar.layer.shadowRadius = 20
        bar.layer.shadowOffset = CGSize(width: 0, height: 8)
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        // (75) 点按到达自证（第 5 项②，同两面墙台）。
        bar.onHitLanded = { [weak self, weak bar] in
            guard let self, let bar else { return }
            Breadcrumbs.log("minibar.touch75 host=stage"
                + " col=\(self.stageBarCollapsed ? 1 : 0)"
                + " h=\(Int(bar.bounds.height))")
        }
        // (77) ⑥：派发段见证补齐三宿主同构＋认领/救援接
        // 线。本宿主识别器位只有双击一位（单击走 require
        // 链），recog 位按本宿主实有记。
        bar.onDispatchCancelled = { [weak self] in
            guard let self else { return }
            Breadcrumbs.log("minibar.dead76 host=stage at=cancel"
                + " recog=\((self.stageBarDoubleTap?.isEnabled ?? false) ? 1 : 0)")
        }
        bar.onDispatchUnclaimed = { [weak self] in
            guard let self, self.stageBarCollapsed else { return }
            Breadcrumbs.log("minibar.dead76 host=stage at=noRecog"
                + " recog=\((self.stageBarDoubleTap?.isEnabled ?? false) ? 1 : 0)")
        }
        bar.crumbHostTag = "stage"
        bar.onCancelledTapRescue = { [weak self] in
            guard let self, self.stageBarCollapsed else { return }
            Breadcrumbs.log("minibar.disp77 host=stage via=rescue")
            self.expandStageBar()
        }
        // (86) 第 9 条：静止点兜底接线（同两面墙口径）。
        bar.onStationaryTap86 = { [weak self] in
            guard let self, self.stageBarCollapsed else { return }
            Breadcrumbs.log("minibar.disp86 host=stage via=stat86")
            self.expandStageBar()
        }
        // 宠物层（细修 B）：详情页台班底，钩子与墙等价。
        let petStage = MiniBarPetStage(bar: bar, role: .stage)
        view.addSubview(petStage)
        stagePetStage = petStage
        // (78) 第 8 条：根级认领（mb.claim78→mb.disp78→
        // expand），与两墙同构。
        stageBarRootTap78 = MiniBarRootTap78(
            hostView: view, bar: bar, petStage: petStage,
            hostTag: "stage",
            isCollapsed: { [weak self] in self?.stageBarCollapsed ?? false },
            expand: { [weak self] in self?.expandStageBar() })
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
        // (84) 第 3 条：毛玻璃禁交互（命中结构，同两面墙）。
        blur.isUserInteractionEnabled = false
        bar.addSubview(blur)
        stageBlurView = blur

        // (84) 第 3 条：台身手势背景层（按钮的兄弟层、非祖
        // 先）——台身识别器组改挂本层，(82) delegate 豁免
        // 整套退役。
        let deckSurface84 = UIView()
        deckSurface84.backgroundColor = .clear
        deckSurface84.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(deckSurface84)
        stageDeckSurface84 = deckSurface84
        NSLayoutConstraint.activate([
            deckSurface84.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            deckSurface84.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            deckSurface84.topAnchor.constraint(equalTo: bar.topAnchor),
            deckSurface84.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        let themeLayer = MiniPlayerThemeLayer()
        themeLayer.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(themeLayer)
        stageThemeLayer = themeLayer
        // (84) 第 1 条：主题底复原（(82) E 毛玻璃恒隐藏退役）。

        let rimLight = UIView()
        rimLight.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        rimLight.layer.cornerRadius = 0.5
        rimLight.isUserInteractionEnabled = false
        rimLight.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(rimLight)
        stageRimLight = rimLight
        let glassTint = UIView()
        glassTint.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        glassTint.layer.cornerRadius = 35
        glassTint.isUserInteractionEnabled = false
        glassTint.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(glassTint)
        stageGlassTint = glassTint

        // 点播台附加功能浮层（3.7 (54) 工作流 H 建上排、(60) 第 7
        // 条迁浮层）：五钮行不再装进台本体，改住透明浮层挂本 VC
        // 的 view（z 序在台之上），底边锚台顶上方 8pt、横向与台
        // 同宽同边距；台高恢复 70。功能走 MiniBarQuickRowView 唯
        // 一实现（与两面墙台同件）；点按先行回调重置无操作计时
        // （浮层自动收起与台闲置同钟，见 quickrow overlay 段）；
        // 喜欢态变化回调刷新顶栏红心（同一 LikesStore 真源两处
        // 回显不许打架）。宠物层以台顶为地面、零改动（浮层在其
        // 上方呼出/收起，不改宠物站位）。
        let overlay = MiniBarQuickRowOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        stageQuickRowOverlay = overlay
        let quickRow = overlay.quickRow
        stageQuickRow = quickRow
        quickRow.onUserInteraction = { [weak self] in self?.resetStageIdleTimer() }
        quickRow.onLikeStateChanged = { [weak self] in self?.refreshLikeButton() }
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -8),
            overlay.heightAnchor.constraint(equalToConstant: MiniBarQuickRowView.rowHeight),
        ])
        // 点浮层外立即收起（观察式点按，不消费触摸、不与台身/
        // 舞台既有手势互斥）：落在浮层胶囊与台身之外才收。
        let overlayOutsideTap = UITapGestureRecognizer(
            target: self, action: #selector(stageQuickRowOutsideTapped(_:)))
        overlayOutsideTap.cancelsTouchesInView = false
        view.addGestureRecognizer(overlayOutsideTap)
        Breadcrumbs.log("minibar.webrow stage overlay attached h=\(Int(MiniBarQuickRowView.expandedBarHeight))")

        let progressTrack = UIView()
        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        progressTrack.layer.cornerRadius = 2
        progressTrack.clipsToBounds = true
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        // (84) 第 3 条：轨道纯视觉禁交互（同两面墙）。
        progressTrack.isUserInteractionEnabled = false
        bar.addSubview(progressTrack)
        stageProgressTrack = progressTrack
        let fill = UIView()
        fill.backgroundColor = .white
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressTrack.addSubview(fill)
        stageProgressFill = fill
        fill.transform = CGAffineTransform(scaleX: 0, y: 1)

        // (84) 第 1 条：把手复原 (80) 形态——9pt 白色发光
        // 圆点＋主题皮肤叠层（同两面墙）；(82) 花朵图退役。
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
        stageProgressKnob = knob

        for label in [currentTimeLabel, totalTimeLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = UIColor.white.withAlphaComponent(0.6)
            label.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(label)
        }
        totalTimeLabel.textAlignment = .right

        // 三键字形与墙台同值（play 19pt / prev·next 15pt，
        // semibold）；命令走既有 handleCommand 入口。
        // (83) 第 6 条：播放钮改白色大圆＋深色字形（同两面
        // 墙；refreshPlayButton 只换图不换 tint/底色）。
        // (84) 第 1 条：播放钮复原 (80) 形态（白字形、无圆
        // 底）；(83) 白圆＋深色字形退役。
        playButton.tintColor = .white
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(stagePlayDown84), for: .touchDown)
        bar.addSubview(playButton)
        // (82) 第 7 条：字形走 DeckGlyph82 独立绘制函数。
        prevButton.setImage(DeckGlyph82.image(.prev, pointSize: 19), for: .normal)
        nextButton.setImage(DeckGlyph82.image(.next, pointSize: 19), for: .normal)
        for button in [prevButton, nextButton] {
            button.tintColor = .white
            button.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(button)
        }
        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        prevButton.addTarget(self, action: #selector(stagePrevDown84), for: .touchDown)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(stageNextDown84), for: .touchDown)

        // 模式可见钮（3.7 (55) 工作流 D/DS 修正3）：主排右侧紧凑钮
        // （next 右侧、右时间标签左侧，34×40 命中区；台宽 =
        // min(屏宽,屏高)−24 ≥ 351 时中排右界约 231、时间标签左界
        // 约 291，间隙 60 足够容纳，不挤压既有三键与时间标签）。
        // glyph/菜单在 refreshStageModeButton 按 playMode 现态重建，
        // 点按弹 UIMenu 四档点选（非盲循环），写同一 playMode 存储。
        // (82) 第 7/8 条：模式钮/爪印不上台（职能进控制台
        // 面板）；对象保留、回刷照旧（对未上台视图无副作用）。
        stageModeButton.tintColor = .white
        stageModeButton.translatesAutoresizingMaskIntoConstraints = false
        refreshStageModeButton()
        stagePawButton.translatesAutoresizingMaskIntoConstraints = false
        stagePawButton.onUserInteraction = { [weak self] in self?.resetStageIdleTimer() }

        // (82) 第 7 条：台内封面/歌名/歌手＋控制台入口
        // （与两面墙同位同尺寸同字形）。
        // (83) 第 6 条：网页版紧凑台——封面/歌手保留刷新、
        // 隐藏不上台面；歌名居中作第一行；控制台入口移进
        // 度行右端收小 30；模式/列表钮实际上台（两端）。
        stageCover82.contentMode = .scaleAspectFill
        stageCover82.clipsToBounds = true
        stageCover82.layer.cornerRadius = 22
        stageCover82.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        stageCover82.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stageCover82)
        // (84) 第 1 条：封面/歌手复原上台面（(80) 版式）。
        stageTitle82.font = .systemFont(ofSize: 14, weight: .semibold)
        stageTitle82.textColor = .white
        stageTitle82.lineBreakMode = .byTruncatingTail
        stageTitle82.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stageTitle82)
        stageArtist82.font = .systemFont(ofSize: 12)
        stageArtist82.textColor = UIColor.white.withAlphaComponent(0.6)
        stageArtist82.lineBreakMode = .byTruncatingTail
        stageArtist82.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stageArtist82)
        stageModeButton83.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        stageModeButton83.layer.cornerRadius = 19
        stageModeButton83.tintColor = .white
        stageModeButton83.accessibilityLabel = "播放模式"
        stageModeButton83.showsMenuAsPrimaryAction = true
        stageModeButton83.translatesAutoresizingMaskIntoConstraints = false
        // (84) 第 1 条：模式钮撤下台面（职能由控制台承
        // 接）——对象与回刷保留、不 addSubview（同 (82)
        // stageModeButton 的处置，约束亦不装配）。
        refreshStageModeButton83()
        stageListButton83.setImage(DeckGlyph82.image(.list, pointSize: 17), for: .normal)
        stageListButton83.tintColor = .white
        stageListButton83.accessibilityLabel = "播放队列"
        stageListButton83.translatesAutoresizingMaskIntoConstraints = false
        stageListButton83.addTarget(self, action: #selector(stageListTapped83), for: .touchUpInside)
        // (84) 第 1 条：列表钮撤下台面（队列由控制台承
        // 接）——不 addSubview、约束不装配。
        stageConsoleButton82.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        stageConsoleButton82.layer.cornerRadius = 15
        stageConsoleButton82.setImage(DeckGlyph82.image(.console, pointSize: 15), for: .normal)
        stageConsoleButton82.tintColor = .white
        stageConsoleButton82.accessibilityLabel = "控制台"
        stageConsoleButton82.translatesAutoresizingMaskIntoConstraints = false
        stageConsoleButton82.addTarget(self, action: #selector(stageConsoleTapped82), for: .touchUpInside)
        stageConsoleButton82.addTarget(self, action: #selector(stageConsoleDown84), for: .touchDown)
        bar.addSubview(stageConsoleButton82)

        // 播放列表入口已于 (60) 第 10 条整钮删除（原 (48) 落台面、
        // (53) H 迁顶栏隐藏排）；队列面板本体保留，经面板页签进入。

        let seekHit = UIView()
        seekHit.backgroundColor = .clear
        seekHit.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(seekHit)
        stageSeekHit = seekHit
        let seekPan = UIPanGestureRecognizer(target: self, action: #selector(stageSeekPanned(_:)))
        seekHit.addGestureRecognizer(seekPan)

        stageBarBottomC = bar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        stageBarWidthConstraint = bar.widthAnchor.constraint(
            equalToConstant: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) - 24)
        // (81) 第 9 条：展开高与全页统一为 70（expandedBar-
        // Height 唯一出处）——(62) 的 bottomBarHeight 可调高
        // 度自此不再驱动台高（Miller 定版：任何页面同一尺
        // 寸；(79) 验收「详情页播放台又变大了」即此漂移）。
        stageBarHeightConstraint = bar.heightAnchor.constraint(
            equalToConstant: MiniBarQuickRowView.expandedBarHeight)
        stageBarWidthConstraint?.isActive = true
        stageBarHeightConstraint?.isActive = true
        // (74) 轨道约束存引用（收起态换居中 134×5 小横线）。
        // (82) 第 7 条：展开态轨道夹在双时间标签之间（与墙台同式）。
        stageTrackLeadC = progressTrack.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 8)
        stageTrackTrailC = progressTrack.trailingAnchor.constraint(equalTo: totalTimeLabel.leadingAnchor, constant: -8)
        stageTrackHeightC = progressTrack.heightAnchor.constraint(equalToConstant: 4)
        stageTrackCenterXC = progressTrack.centerXAnchor.constraint(equalTo: bar.centerXAnchor)
        // (83) 第 5 条：收起宽 134→140（量测对齐，同两面墙）。
        stageTrackWidthC = progressTrack.widthAnchor.constraint(equalToConstant: 140)
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bar.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            // (77) ②⑤：底锚按形态切换（展开 −10/收起
            // +31.5 与 indicator 重合，见 applyStageBarBottom77）。
            stageBarBottomC!,

            blur.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            blur.topAnchor.constraint(equalTo: bar.topAnchor),
            blur.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            themeLayer.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            themeLayer.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            themeLayer.topAnchor.constraint(equalTo: bar.topAnchor),
            themeLayer.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            rimLight.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 30),
            rimLight.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -30),
            rimLight.topAnchor.constraint(equalTo: bar.topAnchor, constant: 1),
            rimLight.heightAnchor.constraint(equalToConstant: 1),
            glassTint.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            glassTint.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            glassTint.topAnchor.constraint(equalTo: bar.topAnchor),
            glassTint.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            // (74) 轨道约束存引用（收起态换居中小横线）。
            stageTrackLeadC!,
            stageTrackTrailC!,
            stageTrackHeightC!,
            fill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            fill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            fill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor),

            knob.centerYAnchor.constraint(equalTo: progressTrack.centerYAnchor),
            knob.widthAnchor.constraint(equalToConstant: 9),
            knob.heightAnchor.constraint(equalToConstant: 9),

            currentTimeLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 28),
            currentTimeLabel.centerYAnchor.constraint(equalTo: progressTrack.centerYAnchor),
            // (85) 审计四(b)：双时间与墙台同锚同宽、定宽
            // 40（≥10 分钟不冒框）；(86) 第 6 条：距台框
            // 16→28 内收（三宿主一致，胶囊弧线净距）。
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 40),
            totalTimeLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -28),
            totalTimeLabel.centerYAnchor.constraint(equalTo: progressTrack.centerYAnchor),
            totalTimeLabel.widthAnchor.constraint(equalToConstant: 40),

            // (84) 第 1 条：封面/标题复原 (80) 锚法（封面左
            // 置 44、标题贴封面右）。
            stageCover82.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            stageCover82.widthAnchor.constraint(equalToConstant: 44),
            stageCover82.heightAnchor.constraint(equalToConstant: 44),
            stageTitle82.leadingAnchor.constraint(equalTo: stageCover82.trailingAnchor, constant: 12),
            stageTitle82.trailingAnchor.constraint(lessThanOrEqualTo: prevButton.leadingAnchor, constant: -6),
            stageTitle82.topAnchor.constraint(equalTo: stageCover82.topAnchor, constant: 5),
            stageArtist82.leadingAnchor.constraint(equalTo: stageTitle82.leadingAnchor),
            stageArtist82.trailingAnchor.constraint(equalTo: stageTitle82.trailingAnchor),
            stageArtist82.topAnchor.constraint(equalTo: stageTitle82.bottomAnchor, constant: 2),

            // (84) 第 1 条：主排复原 (80) 居中三键（播放 40、
            // 上下曲 34×40、间距 20）；模式/列表钮已撤下台
            // 面、约束不装配；控制台入口保留进度行右端现位
            // （(82)/(83) 舞台位，与墙台主排位不同——舞台
            // (80) 主排为居中三键、无右端簇，报告注明）。
            playButton.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 40),
            playButton.heightAnchor.constraint(equalToConstant: 40),
            prevButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -20),
            prevButton.widthAnchor.constraint(equalToConstant: 34),
            prevButton.heightAnchor.constraint(equalToConstant: 40),
            nextButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 20),
            nextButton.widthAnchor.constraint(equalToConstant: 34),
            nextButton.heightAnchor.constraint(equalToConstant: 40),
            // (85) 审计四(b)：控制台钮移出进度行、回主排
            // 右端（与墙台同位：trailing −12、纵向随主排
            // 组 −5，见 stageMainCenterY）；进度行右端让给
            // 右时间标签。
            stageConsoleButton82.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            // 纵向恒为主排位（收起态该钮 alpha 0 不上屏、
            // 不必随收起组换位；恒定约束免收起态纵向无约束）。
            stageConsoleButton82.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
            stageConsoleButton82.widthAnchor.constraint(equalToConstant: 30),
            stageConsoleButton82.heightAnchor.constraint(equalToConstant: 30),

            // (82) 第 7 条：seek 命中带改锚进度行。
            seekHit.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            seekHit.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            seekHit.topAnchor.constraint(equalTo: progressTrack.topAnchor, constant: -9),
            seekHit.heightAnchor.constraint(equalToConstant: 27),
        ])
        stageKnobLeading = knob.leadingAnchor.constraint(
            equalTo: progressTrack.leadingAnchor, constant: -4.5)
        stageKnobLeading?.isActive = true
        // (82) 第 7 条：轨道纵锚制（展开）/底锚（收起）由
        // setStageBarForm 互斥切换，先按展开装配。(83) 第
        // 6 条：展开锚改台底 −14（封面行退役，同两面墙）。
        // (84) 第 1 条：展开轨底锚复原 (80) 的 −7。
        stageTrackTopC = progressTrack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -7)
        stageTrackTopC?.isActive = true
        stageTrackBottomConstraint = progressTrack.bottomAnchor.constraint(
            equalTo: bar.bottomAnchor, constant: -5.5)
        stageTrackBottomConstraint?.isActive = false
        // (83) 第 6 条：控制行纵向——展开态居台中心（常量
        // 0，台高 106；(82) 的 +30/132 已盖过）；时间标签
        // 锚轨道、控制台钮锚进度行，均不入本组。形态切换
        // 在 setStageBarForm 收口。
        // (84) 第 1 条：主排纵向复原 (80)——封面与三键同组
        // 居台中心 −5（模式/列表钮已撤、退出本组）。
        stageMainCenterY = [stageCover82, playButton, prevButton, nextButton].map {
            $0.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5)
        }
        NSLayoutConstraint.activate(stageMainCenterY)
        // (83) 双击闪退定行删除：原「模式钮纵向跟随主排」
        // 约束块（stageModeButton/stagePawButton 锚主排）
        // 整段已删——(82) 提交 90aa29c1 删两钮 addSubview
        // （不上台）却漏删本块，两钮 superview 恒 nil、无
        // 共同祖先，activate 必抛未捕获 NSException
        // （.ips 2026-11-24 201414 定行：EXC_CRASH/SIGABRT，
        // 栈止于 buildStageBar 本段，(82) 开台 100% 必崩）。
        // 两钮存储对象、refreshStageModeButton 回刷与爪印
        // 回调全保留不动（见 forensics/crash-diagnosis-
        // 2026-11-24-201414.md 与 (83) 报告）。

        // (66) 进度条两端槽位钮装配：左钮落在当前时间标签右
        // 侧空隙、右钮落在总时长标签左侧空隙（台宽 ≥351 时
        // 两空隙 ≥30pt，26pt 钮不挤压既有三键/模式钮/标签）；
        // 纵向跟随主排 centerY。内容由 refresh62Settings 按
        // barSlotLeft62/Right62 配置，none 时整钮隐藏。
        // (82) 第 7 条：槽位钮不上台（E 极简台无其位）；
        // 对象与设置保留、回刷照旧（未上台无副作用），其
        // 约束块随之不装配。
        for slot in [stageSlotLeft66, stageSlotRight66] {
            slot.tintColor = .white
            slot.translatesAutoresizingMaskIntoConstraints = false
        }
        if false {
        NSLayoutConstraint.activate([
            stageSlotLeft66.leadingAnchor.constraint(
                equalTo: currentTimeLabel.trailingAnchor, constant: 2),
            stageSlotLeft66.centerYAnchor.constraint(
                equalTo: playButton.centerYAnchor),
            stageSlotLeft66.widthAnchor.constraint(equalToConstant: 26),
            stageSlotLeft66.heightAnchor.constraint(equalToConstant: 40),
            stageSlotRight66.trailingAnchor.constraint(
                equalTo: totalTimeLabel.leadingAnchor, constant: -2),
            stageSlotRight66.centerYAnchor.constraint(
                equalTo: playButton.centerYAnchor),
            stageSlotRight66.widthAnchor.constraint(equalToConstant: 26),
            stageSlotRight66.heightAnchor.constraint(equalToConstant: 40),
        ])
        }

        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(stageBarLongPressed(_:)))
        longPress.minimumPressDuration = 0.55
        deckSurface84.addGestureRecognizer(longPress)
        // 单击/双击规格（3.7 (61) 第 7 条，镜像全台）：双击 →
        // 进歌曲详情页（见 stageBarDoubleTapped 的宿主接法说
        // 明）；单击 require(toFail: 双击)——既有 require 长按
        // 一环保留、只加双击一环（代价 +~0.3s 换无回滚闪烁，
        // 取证 §4 推荐案 a）。收起态细条单击须即时展开、不等
        // 双击失败：双击识别器随形态启停（syncStageBarDouble-
        // TapEnabled），收起时禁用、单击的 require 立即满足。
        let doubleTap = UITapGestureRecognizer(
            target: self, action: #selector(stageBarDoubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        deckSurface84.addGestureRecognizer(doubleTap)
        stageBarDoubleTap = doubleTap
        let tap = UITapGestureRecognizer(target: self, action: #selector(stageBarTapped(_:)))
        tap.require(toFail: longPress)
        tap.require(toFail: doubleTap)
        deckSurface84.addGestureRecognizer(tap)
        // (74) 第 4 项兜底识别器（同两面墙台）：与形态无关、
        // 恒启用、无 require 链，几何细条时先纠标志再展开。
        let agnosticTap74 = UITapGestureRecognizer(
            target: self, action: #selector(stageBarAgnosticTapped74(_:)))
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
        // (84) 第 3 条：识别器改挂背景手势层＋(82) delegate
        // 豁免接线整套退役（同两面墙）。
        deckSurface84.addGestureRecognizer(agnosticTap74)
        syncStageBarDoubleTapEnabled()

        applyStageTheme()
        applyStageBarSlots()
    }

    /// 点播台槽位应用（3.7 (50)）：按 MiniBarSlotSettings 显隐
    /// prev/next 两键（queue 已迁顶栏，见 (53) H 修正）；隐藏时宽度约束置 0、链上其余键向
    /// 中心收拢（时间标签锚在台体两端、不受影响）。宽度约束
    /// 经按钮自身 constraints 反查，不改构建期约束块。口径与
    /// 两面墙台一致；收起态 alpha/交互名单含隐藏键无妨，
    /// isHidden 恒压过 alpha 与命中。
    private func applyStageBarSlots() {
        // (62) 槽位扩展集与既有三键取交集：barSlots62 决定候选集
        // （prev/next/queue/like/mode/sleep），MiniBarSlotSettings
        // 三键为既有显隐真源；mode 键管舞台主排模式钮，like/sleep
        // 在舞台无独立钮（like 在顶栏、sleep 在面板），仅落面包屑。
        let slots62 = SettingsStore.barSlots62
        applySlot(prevButton, visible: MiniBarSlotSettings.showPrev && slots62.contains("prev"), width: 34)
        applySlot(nextButton, visible: MiniBarSlotSettings.showNext && slots62.contains("next"), width: 34)
        stageModeButton.isHidden = !slots62.contains("mode")
        // queue 键已迁顶栏隐藏排（(53) H 修正），不再受台面槽位
        // 显隐管辖；MiniBarSlotSettings.showQueue 对墙原型台与
        // MiniPlayerView 组件仍有效。
    }

    private func applySlot(_ button: UIButton, visible: Bool, width: CGFloat) {
        button.isHidden = !visible
        if let constraint = button.constraints.first(where: {
            $0.firstAttribute == .width && $0.secondItem == nil
        }) {
            constraint.constant = visible ? width : 0
        }
    }

    @objc private func stageBarSlotsChanged() {
        applyStageBarSlots()
    }

    /// 进度填充与圆钮的唯一步进点（与墙 setMiniProgress 同
    /// 构）：StageProgressDriver 逐帧喂、拖动/点按跳点先行
    /// 预览都走这里；主题层积雪/鲨鳍/流星头位同源转喂。
    private func setStageProgress(_ fraction: Double) {
        let clamped = CGFloat(min(max(fraction, 0), 1))
        stageProgressFill?.transform = CGAffineTransform(scaleX: clamped, y: 1)
        if let trackWidth = stageProgressTrack?.bounds.width, trackWidth > 0 {
            // (83) 把手 14pt 宽，领先常量按半宽居中。
            stageKnobLeading?.constant = clamped * trackWidth - 7
        }
        stageThemeLayer?.setFraction(Double(clamped))
        // (68) B 组：全宽条可见时同源喂入（同一 fraction，不
        // 另起进度源）；不可见时零开销跳过。
        if let bar = wideBar68, bar.isBarVisible {
            bar.update(fraction: Double(clamped),
                       playing: engine.isPlaying, duration: engine.duration)
        }
    }

    private func applyStageTheme() {
        stageThemeLayer?.apply(theme: stageTheme)
        refreshStageProgressChrome()
        // (82) 第 7 条：字形与主题解耦（DeckGlyph82 单套）。
        refreshDeckIcons82()
    }

    /// 填充/圆点配色的形态收口（与墙 refreshMiniProgress-
    /// Chrome 同值）：展开 = 主题口径；收起 = 兜底色（星空
    /// 强金），圆点两形态都保留主题皮肤、无皮肤才白发光点。
    private func refreshStageProgressChrome() {
        stageKnobSkin?.removeFromSuperview()
        stageKnobSkin = nil
        if let skin = MiniPlayerThemeLayer.knobSkinView(for: stageTheme) {
            skin.translatesAutoresizingMaskIntoConstraints = false
            stageProgressKnob?.addSubview(skin)
            NSLayoutConstraint.activate([
                skin.centerXAnchor.constraint(equalTo: stageProgressKnob!.centerXAnchor),
                skin.centerYAnchor.constraint(equalTo: stageProgressKnob!.centerYAnchor),
                skin.widthAnchor.constraint(equalToConstant: 13),
                skin.heightAnchor.constraint(equalToConstant: 13),
            ])
            stageKnobSkin = skin
        }
        // (84) 第 1 条：把手复原 (80) 口径（同两面墙）。
        if stageKnobSkin != nil {
            stageProgressKnob?.backgroundColor = .clear
            stageProgressKnob?.layer.shadowOpacity = 0
        } else {
            stageProgressKnob?.backgroundColor = .white
            stageProgressKnob?.layer.shadowOpacity = 0.9
        }
        if stageBarCollapsed {
            // (82) 第 5 条：收起态改系统白系（填充纯白、
            // 轨道白 35%），对齐 home indicator 观感。
            stageProgressFill?.backgroundColor = .white
            stageProgressTrack?.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        } else {
            // (79) 第 2 条进度配色：全条统一一色。
            let singleColor = Self.stageFillColor(for: stageTheme)
            stageProgressFill?.backgroundColor = singleColor
            stageProgressTrack?.backgroundColor = singleColor
        }
    }

    /// 与墙 miniFillColor 同值（主题填充色）。
    private static func stageFillColor(for theme: MiniPlayerTheme) -> UIColor {
        switch theme {
        case .meadow: return UIColor(red: 0.96, green: 0.72, blue: 0.25, alpha: 1)
        case .star: return UIColor(red: 1, green: 0.91, blue: 0.62, alpha: 1)
        default: return .white
        }
    }

    /// 与墙 miniCollapsedFillColor 同值（收起态兜底）。
    private static func stageCollapsedFillColor(for theme: MiniPlayerTheme) -> UIColor {
        switch theme {
        case .star: return UIColor(red: 1, green: 0.80, blue: 0.28, alpha: 1)
        default: return stageFillColor(for: theme)
        }
    }

    @objc private func stageThemeSettingsChanged() {
        let eff = MiniPlayerTheme.effective
        guard eff != stageTheme else { return }
        stageTheme = eff
        applyStageTheme()
    }

    /// 长按台身循环切主题（与墙同规：收起态不切、按键区不
    /// 切、总开关关时停用；切换落盘 + 发同一变更通知）。
    @objc private func stageBarLongPressed(_ gesture: UILongPressGestureRecognizer) {
        // (70) B2：(60) 的宠物域隔离门控随 4s 开启手势整套
        // 撤除——台身长按只剩切主题一职，宠物开关态不再
        // 影响本识别器。
        guard gesture.state == .began, !stageBarCollapsed,
              MiniPlayerTheme.effectsEnabled else { return }
        let point = gesture.location(in: stageBar)
        if playButton.frame.contains(point)
            || prevButton.frame.contains(point)
            || nextButton.frame.contains(point)
            || stageConsoleButton82.frame.contains(point) { return }
        // 附加功能行已迁浮层（(60) 第 7 条）：浮层不在台身内，
        // 其触摸不进本识别器，无须再豁免（旧上排豁免随之退役）。
        stageTheme = stageTheme.next
        MiniPlayerTheme.stored = stageTheme
        applyStageTheme()
        NotificationCenter.default.post(name: .foliaMiniPlayerThemeChanged, object: nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        resetStageIdleTimer()
    }

    /// 双击识别器随形态启停（3.7 (61) 第 7 条）：收起态细条
    /// 单击展开必须即时、不等双击失败——收起时禁用双击识别
    /// 器，单击的 require(toFail:) 对禁用识别器立即满足；展
    /// 开态启用，单击等双击落空才触发（+~0.3s）。形态变更点
    /// （build/collapse/expand/在场复位）各调一次本方法收口。
    private func syncStageBarDoubleTapEnabled() {
        stageBarDoubleTap?.isEnabled = !stageBarCollapsed
    }

    /// (74) 第 4 项兜底（同两面墙台）：与形态无关的恒启用
    /// 识别器，几何细条（≤20）时先按几何纠正标志（含双击
    /// 启停收口）再展开，不等 require 链落空。
    @objc private func stageBarAgnosticTapped74(_ gesture: UITapGestureRecognizer) {
        // (75) 死点留痕（同两面墙台）：几何守卫拒绝不再静默。
        guard stageBar.bounds.height <= 20 else {
            Breadcrumbs.log("minibar.dead75 host=stage at=geom"
                + " h=\(Int(stageBar.bounds.height))")
            return
        }
        if !stageBarCollapsed {
            Breadcrumbs.log("minibar.hit host=stage heal=flag74")
            stageBarCollapsed = true
            syncStageBarDoubleTapEnabled()
        }
        Breadcrumbs.log("minibar.hit host=stage via=agnostic74")
        expandStageBar()
    }

    /// 台面点按分发（与墙同构）：收起态只展开；展开态按键
    /// 各自处理、底部进度带按轨道实际帧跳点、其余台身空白
    /// 区开关附加功能浮层（(60) 第 7 条呼出、(61) 第 7 条补
    /// 「浮层开时单击＝收起」）。任何点按重置无操作计时。
    /// 本识别器经 require(toFail:) 等双击落空后才触发（展开
    /// 态，(61) 第 7 条）；收起态双击识别器禁用、即时触发。
    @objc private func stageBarTapped(_ gesture: UITapGestureRecognizer) {
        // (63) 第 2 条几何自愈（与两墙同构）：标志说展开但几
        // 何已是细条高（≤20）＝形态失同步，先按几何纠正标志
        // （含双击识别器启停收口）再走既有展开流程。
        if stageBarCollapsed || stageBar.bounds.height <= 20 {
            if !stageBarCollapsed {
                Breadcrumbs.log("minibar.form host=stage heal=geom"
                    + " h=\(Int(stageBar.bounds.height)) flag=0")
                stageBarCollapsed = true
                syncStageBarDoubleTapEnabled()
            }
            // (77) ⑥派发环自证（claim77→disp77→expand）。
            stageBar.noteRecognizerClaimed()
            Breadcrumbs.log("minibar.disp77 host=stage via=tap")
            expandStageBar()
            return
        }
        resetStageIdleTimer()
        let point = gesture.location(in: stageBar)
        if playButton.frame.contains(point)
            || prevButton.frame.contains(point)
            || nextButton.frame.contains(point)
            || stageModeButton83.frame.contains(point)
            || stageListButton83.frame.contains(point)
            || stageConsoleButton82.frame.contains(point) { return }
        if let seekHit = stageSeekHit, seekHit.frame.contains(point) {
            guard let track = stageProgressTrack?.frame, track.width > 0,
                  engine.duration > 0 else { return }
            let fraction = min(max((point.x - track.minX) / track.width, 0), 1)
            setStageProgress(Double(fraction))
            performSeek(to: Double(fraction) * engine.duration, source: "stage.bar.tap")
            return
        }
        // (82) 第 8 条：台身空白单击改开控制台面板（旧浮
        // 层退役为入口，与两面墙同修）。
        DeckTap82.log(host: "stage", zone: "body", view: stageBar)
        ConsolePanel82.present(from: self)
        Breadcrumbs.log("minibar.tap host=stage action=console82")
    }

    /// 台身双击（3.7 (61) 第 7 条）：规格为「进歌曲详情页」。
    /// 本宿主的实际接法：舞台宿主本体即歌曲详情页——主页台
    /// 封面单击的详情路由（HomeWall.openNativeStageFromHome）
    /// 呈现的正是 StageViewController，本台面无封面元素、亦
    /// 无更深一层的独立详情路由；FullPlayerContainer 在现行
    /// 代码中无 UIKit 呈现点（RenderStateCenter.isFullPlayer-
    /// Open 仅记录字段、不参与呈现计算），故双击不叠加呈现，
    /// 只落面包屑自证「已在详情页」。分域纪律与单击同构：
    /// 按键区自理、进度带双击不进详情（保留给单击 seek 的域
    /// 隔离，取证 §4 第 2 项）；宠物占位区点按归宠物识别器、
    /// 到不了本识别器（结构事实，验收单明示口径同全台）。
    @objc private func stageBarDoubleTapped(_ gesture: UITapGestureRecognizer) {
        // (83) 第 2 条取证：舞台台面双击（自宿主、无 present）
        // 同步落盘分步——与墙侧链同名册，崩溃回收一并判读。
        DblTap83.step("stage", "recv")
        guard !stageBarCollapsed else {
            DblTap83.step("stage", "guardform")
            return
        }
        resetStageIdleTimer()
        let point = gesture.location(in: stageBar)
        if playButton.frame.contains(point)
            || prevButton.frame.contains(point)
            || nextButton.frame.contains(point)
            || stageModeButton83.frame.contains(point)
            || stageListButton83.frame.contains(point)
            || stageConsoleButton82.frame.contains(point) {
            DblTap83.step("stage", "skipbtn")
            return
        }
        if let seekHit = stageSeekHit, seekHit.frame.contains(point) {
            DblTap83.step("stage", "skipseek")
            return
        }
        Breadcrumbs.log("stage.bar doubletap detail=self-host track=\(currentTrackId ?? "-")")
        DblTap83.step("stage", "self")
    }

    /// 进度拖动（与墙同构）：拖动只更填充、松手才 seek；拖
    /// 动期间挂起无操作计时；收起态不响应。
    @objc private func stageSeekPanned(_ gesture: UIPanGestureRecognizer) {
        guard stageSeekHit != nil else { return }
        let barPoint = gesture.location(in: stageBar)
        guard let track = stageProgressTrack?.frame, track.width > 0 else {
            if gesture.state == .ended || gesture.state == .cancelled
                || gesture.state == .failed {
                stageSeekDragging = false
                resetStageIdleTimer()
            }
            return
        }
        let fraction = min(max((barPoint.x - track.minX) / track.width, 0), 1)
        switch gesture.state {
        case .began:
            if stageBarCollapsed { return }
            if playButton.frame.contains(barPoint)
                || prevButton.frame.contains(barPoint)
                || nextButton.frame.contains(barPoint)
                || stageModeButton83.frame.contains(barPoint)
                || stageListButton83.frame.contains(barPoint)
                || stageConsoleButton82.frame.contains(barPoint) { return }
            guard engine.duration > 0 else { return }
            stageSeekDragging = true
            cancelStageIdleTimer()
            setStageProgress(Double(fraction))
        case .changed:
            guard stageSeekDragging else { return }
            setStageProgress(Double(fraction))
        case .ended:
            guard stageSeekDragging else { return }
            stageSeekDragging = false
            resetStageIdleTimer()
            guard engine.duration > 0 else { return }
            let target = Double(fraction) * engine.duration
            // 落点保持窗开窗（3.7 (70) B4）：先记目标与截止
            // 再发 seek；拖动期守卫战绩一行自证（无挡下则
            // 不落，免噪音）。
            seekHoldTarget70 = target
            seekHoldDeadline70 = CACurrentMediaTime() + 0.3
            if seekGuardBlocked70 > 0 {
                Breadcrumbs.log("seek.guard n=\(seekGuardBlocked70)")
                seekGuardBlocked70 = 0
            }
            performSeek(to: target, source: "stage.bar.seek")
        case .cancelled, .failed:
            stageSeekDragging = false
            seekGuardBlocked70 = 0
            resetStageIdleTimer()
        default:
            break
        }
    }

    // MARK: 点播台收起（与墙同规：5 秒无操作自动收成细条）

    private static let stageIdleCollapseDelay: TimeInterval = 5

    private func resetStageIdleTimer() {
        stageIdleWorkItem?.cancel()
        stageIdleWorkItem = nil
        // 浮层与台闲置同钟（(60) 第 7 条）：浮层在显时，任一台面
        // 操作（含浮层钮点按经 onUserInteraction 回到这里）同时
        // 顺延浮层的 5 秒自动收起。
        if stageQuickRowOverlay?.isShown == true {
            scheduleStageQuickRowAutoHide()
        }
        guard stageBarPresented, !stageBarCollapsed, !stageSeekDragging else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.collapseStageBarIdle()
        }
        stageIdleWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.stageIdleCollapseDelay, execute: work)
    }

    private func cancelStageIdleTimer() {
        stageIdleWorkItem?.cancel()
        stageIdleWorkItem = nil
    }

    private func collapseStageBarIdle() {
        guard stageBarPresented, !stageBarCollapsed, !stageSeekDragging else { return }
        stageBarCollapsed = true
        syncStageBarDoubleTapEnabled()
        stagePetStage?.barFormChanged(collapsed: true)
        cancelStageIdleTimer()
        // 台收成细条时浮层同钟收起（(60) 第 7 条），不许悬在细条上方。
        hideStageQuickRowOverlay(reason: "idle")
        Breadcrumbs.log("stage bar collapse idle")
        setStageBarContentsInteractive(false)
        if UIAccessibility.isReduceMotionEnabled {
            setStageBarForm(collapsed: true)
            UIView.animate(withDuration: 0.2) { self.setStageBarContentsAlpha(0) }
            return
        }
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0.1,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.setStageBarForm(collapsed: true)
            self.setStageBarContentsAlpha(0)
            self.view.layoutIfNeeded()
        }
    }

    private func expandStageBar() {
        guard stageBarCollapsed else {
            resetStageIdleTimer()
            return
        }
        stageBarCollapsed = false
        syncStageBarDoubleTapEnabled()
        stagePetStage?.barFormChanged(collapsed: false)
        Breadcrumbs.log("stage bar expand")
        setStageBarContentsInteractive(true)
        if UIAccessibility.isReduceMotionEnabled {
            setStageBarForm(collapsed: false)
            UIView.animate(withDuration: 0.2) { self.setStageBarContentsAlpha(1) }
        } else {
            UIView.animate(withDuration: 0.5, delay: 0,
                           usingSpringWithDamping: 0.85, initialSpringVelocity: 0.1,
                           options: [.curveEaseOut, .allowUserInteraction]) {
                self.setStageBarForm(collapsed: false)
                self.setStageBarContentsAlpha(1)
                self.view.layoutIfNeeded()
            }
        }
        resetStageIdleTimer()
    }

    /// (77) ②底锚按形态落位（几何账同两墙：展开 −10、
    /// 收起 +31.5 与 home indicator 中心重合、无
    /// indicator 机型回落 −10；宠物层按 bar.frame 跟随）。
    /// (78) 第 1 条修正（与两墙同账）：收起 31.5→24.5，整
    /// 条上抬 7pt——轨道带升至屏底上方 15–20，系统小白线
    /// （8–13）只落条身下部空白边距、不压轨道与宠物。
    /// (83) 第 5 条量测盖过（同两面墙）：容器底距改公式
    /// inset − 2.5，轨带恰落系统横线带 8–13pt。
    private func applyStageBarBottom77(collapsed: Bool) {
        guard let bottomC = stageBarBottomC else { return }
        let inset = view.window?.safeAreaInsets.bottom
            ?? view.safeAreaInsets.bottom
        // (84) 第 2 条：改回 (80) 形态公式（同两面墙）。
        bottomC.constant = collapsed
            ? DeckLayout84.collapsedBottomConstant(safeAreaBottom: inset) : -10
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applyStageBarBottom77(collapsed: stageBarCollapsed)
    }

    private func setStageBarForm(collapsed: Bool) {
        applyStageBarBottom77(collapsed: collapsed)
        stageBar.isCollapsedForm = collapsed
        stageBarHeightConstraint?.constant = collapsed
            ? 16 : MiniBarQuickRowView.expandedBarHeight
        // (84) 第 1 条：主排纵向复原 (80)——两形态恒 −5。
        for constraint in stageMainCenterY { constraint.constant = -5 }
        // (74) 第 5 项小横线（同两面墙台口径）：收起态轨道
        // 换居中 134×5 小横线、圆点收起；台体容器与命中带
        // 不动。底距 −5.5 使 5pt 线在 16pt 容器内居中。
        stageTrackBottomConstraint?.constant = collapsed ? -5.5 : -7
        // (81) 第 1 条两态口径（盖过 (79) 的恒 134，与两
        // 面墙台同账）：收起态居中 134×5 短轨；展开态还
        // 原台内全宽长 seek 轨（lead/trail ±20、高 4、圆
        // 角 2，装配原值）。注：舞台展开首呈现走装配默认
        // 即全宽、本就正确（(79) 判读坐实），本函数被调
        // 用时按两态收口即可，不另加开台补调。
        if collapsed {
            stageTrackLeadC?.isActive = false
            stageTrackTrailC?.isActive = false
            stageTrackCenterXC?.isActive = true
            stageTrackWidthC?.isActive = true
            stageTrackHeightC?.constant = 5
            stageProgressTrack?.layer.cornerRadius = 2.5
            // (82) 第 7 条：收起态轨道换底锚（顶锚撤）。
            stageTrackTopC?.isActive = false
            stageTrackBottomConstraint?.isActive = true
        } else {
            stageTrackCenterXC?.isActive = false
            stageTrackWidthC?.isActive = false
            stageTrackLeadC?.isActive = true
            stageTrackTrailC?.isActive = true
            stageTrackHeightC?.constant = 4
            stageProgressTrack?.layer.cornerRadius = 2
            // (82) 第 7 条：展开态轨道换顶锚（底锚撤）。
            stageTrackBottomConstraint?.isActive = false
            stageTrackTopC?.isActive = true
        }
        // (77) ②③：四主题小圆点恢复收起态在场（(74) 误删，
        // 两形态恒可见、皮肤两形态同挂）。
        stageProgressKnob?.isHidden = false
        // (84) 第 1 条：把手已复原 (80) 圆点/皮肤形态，收
        // 起态不再压平（同两面墙）。
        stageProgressKnob?.transform = .identity
        let radius: CGFloat = collapsed ? 8 : 35
        stageBar.layer.cornerRadius = radius
        stageBlurView?.layer.cornerRadius = radius
        stageBar.hitExpansionY = collapsed ? 14 : 0
        // (84) 第 1 条：主题层复原 (80) 形态口径（同两面墙）。
        stageThemeLayer?.isHidden = collapsed
        stageBlurView?.isHidden = collapsed
        stageRimLight?.isHidden = collapsed
        stageGlassTint?.isHidden = collapsed
        // (85) 第 3 条（审计四(a)，同两面墙）：收起态 seek
        // 命中带禁交互，堵其截走细条中央带展开点按的盲区
        // （舞台 seek 带只有 pan、无 tap，收起态拖动本就不
        // 响应，禁交互后点按直达台身识别器组展开）。
        stageSeekHit?.isUserInteractionEnabled = !collapsed
        Breadcrumbs.log("seek85 host=stage hit=\(collapsed ? 0 : 1)")
        // (63) 第 2 条形态面包屑（舞台宿主）：标志/几何高/双
        // 击识别器启停位同行（本宿主形态识别器只有双击一位，
        // 单击恒启停于 require 链，见 syncStageBarDoubleTapEnabled）。
        Breadcrumbs.log("minibar.form host=stage collapsed=\(collapsed ? 1 : 0)"
            + " h=\(Int(stageBarHeightConstraint?.constant ?? -1))"
            + " tw=\(collapsed ? 140 : Int(stageBarWidthConstraint?.constant ?? 0) - 40)"
            + " recog=\((stageBarDoubleTap?.isEnabled ?? false) ? 1 : 0)")
        // (84) 第 2 条：小白条形态自证新口径（同两面墙）。
        let fmPortrait84 = view.bounds.width <= view.bounds.height
        if collapsed {
            stageTrackWidthC?.constant =
                DeckLayout84.collapsedTrackWidth(portrait: fmPortrait84)
        }
        Breadcrumbs.log("minibar.fm84 host=stage"
            + " col=\(collapsed ? 1 : 0)"
            + " tw=\(collapsed ? Int(DeckLayout84.collapsedTrackWidth(portrait: fmPortrait84)) : Int(stageBarWidthConstraint?.constant ?? 0) - 136)"
            + " th=\(collapsed ? 5 : 4)"
            + " gap=\(collapsed ? 2 : -1)"
            + " r=\(collapsed ? "2.5" : "2")"
            + " orient=\(fmPortrait84 ? "port" : "land")")
        refreshStageProgressChrome()
    }

    /// (86) 第 5 条：旋转落定按新朝向重写收起轨宽（同两面
    /// 墙口径：写入时机修法，常数 218/140 不动，fm86 恒
    /// 落行保 host=stage 横屏样本）。
    private func refreshTrackWidth86(portrait: Bool) {
        let tw = DeckLayout84.collapsedTrackWidth(portrait: portrait)
        if stageBarCollapsed { stageTrackWidthC?.constant = tw }
        Breadcrumbs.log("fm86 host=stage"
            + " orient=\(portrait ? "port" : "land")"
            + " col=\(stageBarCollapsed ? 1 : 0) tw=\(Int(tw))")
    }

    private func setStageBarContentsAlpha(_ alpha: CGFloat) {
        // 圆点不淡出（收起态保留主题圆点随进度步进，同墙）。
        // 附加功能行已迁浮层（(60) 第 7 条），不入台形态名单：
        // 台收起时浮层由 collapseStageBarIdle 单独收起。
        for view in [currentTimeLabel, totalTimeLabel,
                     playButton, prevButton, nextButton,
                     stageModeButton83, stageListButton83,
                     stageConsoleButton82, stageCover82,
                     stageTitle82, stageArtist82] as [UIView] {
            view.alpha = alpha
        }
    }

    private func setStageBarContentsInteractive(_ interactive: Bool) {
        for button in [playButton, prevButton, nextButton,
                       stageModeButton83, stageListButton83,
                       stageConsoleButton82] {
            button.isUserInteractionEnabled = interactive
        }
    }

    // MARK: 附加功能浮层（3.7 (60) 第 7 条，舞台宿主）
    //
    // 触发 = 点台身空白区（stageBarTapped 末路）；收起 = 与点播
    // 台闲置同钟（呼出/任一操作后 5 秒，resetStageIdleTimer 顺
    // 延）、点浮层外立即收起、台收成细条时随台收起。进出动画在
    // MiniBarQuickRowOverlayView.setShown 内（系统弹簧 0.85、
    // 自台顶滑入＋淡入）。宠物站位以台顶为地面，浮层零干涉。

    private func showStageQuickRowOverlay() {
        guard let overlay = stageQuickRowOverlay, !overlay.isShown else { return }
        overlay.setShown(true)
        Breadcrumbs.log("quickrow.overlay show host=stage")
        scheduleStageQuickRowAutoHide()
    }

    private func hideStageQuickRowOverlay(reason: String) {
        stageQuickRowHideWorkItem?.cancel()
        stageQuickRowHideWorkItem = nil
        guard let overlay = stageQuickRowOverlay, overlay.isShown else { return }
        overlay.setShown(false)
        Breadcrumbs.log("quickrow.overlay hide host=stage reason=\(reason)")
    }

    private func scheduleStageQuickRowAutoHide() {
        stageQuickRowHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideStageQuickRowOverlay(reason: "idle")
        }
        stageQuickRowHideWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.stageIdleCollapseDelay, execute: work)
    }

    /// 点浮层外立即收起：观察式识别器（不消费触摸）——落点在浮
    /// 层胶囊或点播台之内都不算「外」；舞台三击切样式挂在
    /// rendererContainer、台身 0.55s 长按切主题挂在台身上，本
    /// 识别器 cancelsTouchesInView=false 且不 require 任何互斥，
    /// 两者不被破坏。
    @objc private func stageQuickRowOutsideTapped(_ gesture: UITapGestureRecognizer) {
        guard let overlay = stageQuickRowOverlay, overlay.isShown else { return }
        let point = gesture.location(in: view)
        if overlay.frame.contains(point) || stageBar.frame.contains(point) { return }
        hideStageQuickRowOverlay(reason: "outside-tap")
    }

    /// 在场边沿的形态无动画复位：收起态不跨呈现周期残留。
    private func resetStageBarFormInstant() {
        stageBarCollapsed = false
        syncStageBarDoubleTapEnabled()
        setStageBarForm(collapsed: false)
        setStageBarContentsAlpha(1)
        setStageBarContentsInteractive(true)
    }

    // MARK: 帧驱动与 gate 统计

    private final class DisplayLinkProxy: NSObject {
        weak var owner: StageViewController?
        @objc func step(_ link: CADisplayLink) { owner?.frameStep(link) }
    }
    private let linkProxy = DisplayLinkProxy()

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        linkProxy.owner = self
        let link = CADisplayLink(target: linkProxy, selector: #selector(DisplayLinkProxy.step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        // (62) INT-6：帧率限制消费（WB FoliaMotion62）——设置
        // 开启时按上限夹 preferredFrameRateRange。
        FoliaMotion62.applyFrameRate(to: link)
        lastFrameTimestamp = 0
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func frameStep(_ link: CADisplayLink) {
        if lastFrameTimestamp > 0 {
            let dt = link.timestamp - lastFrameTimestamp
            if dt > 0 && dt < 0.5 {
                frameDurations.append(dt)
                if frameDurations.count > 7200 { frameDurations.removeFirst(1800) }
            }
        }
        lastFrameTimestamp = link.timestamp
        let position = positionNow()
        logStageLineIfChanged(position: position)
        // §0 呈现钟采样（3.7 (67) B 组）：tick.pos 每 30 帧一行
        // （0.5s@60fps，全量逐 tick 会淹没 2MB 日志环）；sync
        // .per5 每 5 秒一行判漂移（judge−raw 趋势＋出声读数）。
        syncProbeTickCount += 1
        if syncProbeTickCount % 30 == 0 {
            Breadcrumbs.log("tick.pos pos=\(SyncProbe67.fmt(position)) raw=\(SyncProbe67.fmt(engine.rawPlayhead())) wall=\(SyncProbe67.fmt(link.timestamp)) style=\(activeStyleId)")
        }
        if link.timestamp - lastSyncPer5At >= 5 {
            lastSyncPer5At = link.timestamp
            let af5 = SyncProbe67.audioFields()
            let raw5 = engine.rawPlayhead()
            let src5 = currentTrackId.flatMap { linesCache[$0] }
                .map { SyncProbe67.wordSource(of: $0) } ?? "none"
            Breadcrumbs.log("sync.per5 judge=\(SyncProbe67.fmt(position)) raw=\(SyncProbe67.fmt(raw5)) dJudge=\(SyncProbe67.fmt(raw5 - position)) route=\(af5.route) outLat=\(SyncProbe67.fmt(af5.outLat)) src=\(src5) style=\(activeStyleId) wall=\(SyncProbe67.fmt(link.timestamp))")
        }
        renderer?.frameTick(position: position)
        // (62) 声线追踪：开启时逐帧喂电平近似线（无真实频谱源，见视图头注）。
        if SettingsStore.soundTracingEnabled {
            soundTracing62.update(playing: engine.isPlaying, position: position)
        }
        // 打开追踪·首帧存活（3.7 (61) 第 3 条）：渲染器首帧
        // tick 后的 CATransaction 完成回调 = 该帧已提交合成；
        // 只落一次（styleTraceFirstFrameLogged 锁存、每次装配
        // 重置）。进程死在首帧提交前时本行缺失、lastMarker
        // 停在 assembly，与 style.assembly.done 对位二分。
        if !styleTraceFirstFrameLogged, let traceStyle = styleTraceStyleId {
            styleTraceFirstFrameLogged = true
            let traceHash = styleTraceDataHash
            // (63) DS R63 B2 首帧相位：pre 在首个帧 tick 同步
            // 落盘，post 在 CATransaction 完成（帧已提交合成）
            // 时同步落盘——尾停在 pre 无 post ＝死在首帧提交前。
            Breadcrumbs.logSync("asm.frame.pre style=\(traceStyle)")
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                Breadcrumbs.logSync("asm.frame.post style=\(traceStyle)")
                StyleOpenTrace.mark("firstFrame", styleId: traceStyle, dataHash: traceHash)
                Breadcrumbs.log("style.firstFrame.commit.alive style=\(traceStyle) dataHash=\(traceHash) \(StyleOpenTrace.memoryFields())")
            }
            CATransaction.commit()
        }
        // 宿主级字幕层已于 (60) 第 11 条整组删除：frameStep 不再
        // 逐帧喂行。汪汪队歌词呈现走渲染器内主胶囊（底部提词条
        // 已于 (65) 摘除），同样不经宿主。
        // 防卡死守卫证明（3.7 (44) 建，(45) R-4 补口径）：
        // 帧条件（满 60 帧或存活满 2 秒）只置 framesOK，还须
        // 歌词首次 applied 才结算（via=frames+lyrics），覆
        // 盖异步落地盲区；存活满 5 秒兜底结算（via=window）。
        if styleProofStyleId != nil {
            styleProofFrames += 1
            let proofElapsed = CACurrentMediaTime() - styleProofArmedAt
            if styleProofFrames >= 60 || proofElapsed >= 2 {
                styleProofFramesOK = true
            }
            if styleProofFramesOK && styleProofLyricsApplied {
                finishStyleProof(via: "frames+lyrics")
            } else if proofElapsed >= 5 {
                finishStyleProof(via: "window")
            }
        }
        let second = Int(position)
        if second != lastTimeLabelSecond {
            lastTimeLabelSecond = second
            currentTimeLabel.text = Self.formatTime(position)
            if engine.duration > 0 { totalTimeLabel.text = Self.formatTime(engine.duration) }
        }
    }

    /// 舞台行级面包屑（3.7 (41) 组3）：与墙面 `lrc line` /
    /// `lrc flip src=judge` 同构——lineStart/judge/raw/engine/
    /// delta 同定义（judge = 本台锚外推位置即呈现钟；raw =
    /// rawPlayhead 真值；engine = 200ms 台阶缓存；delta =
    /// judge − engine）。补审计 lyric-sync §5 的舞台零行级
    /// 埋点缺口：此前舞台翻行迟到无任何日志可量，本版起每
    /// 次（曲目, 行号）变化落一行 `stage line`、真翻行再补
    /// `stage flip src=judge judgeLag=`（judge 越过行界的
    /// 量）。暂停时 position 冻结、行号恒定，不刷屏；seek
    /// 跳行同样落盘（judgeLag 即落点在行内的相位）。
    private func logStageLineIfChanged(position: TimeInterval) {
        guard let track = engine.currentTrack,
              let lines = linesCache[track.id], !lines.isEmpty else { return }
        // 当前行 = start <= position 的最后一行（行表按 start
        // 升序，二分）；position 在首行之前时取首行（前奏预告，
        // 与墙面同口径）。
        var idx = 0
        var lo = 0, hi = lines.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= position {
                idx = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        // sync.probe 扫光 50% 过线（3.7 (53) 工作流 F，只
        // 埋点）：扫光由同一呈现钟 position 驱动（宿主帧循
        // 环喂给各渲染方），position 跨过本行时间跨度中点
        // 即扫光过半——判定点只能落在本函数：GlowWordView /
        // StageSweepWordView 均为词级视图，无曲目/行号/
        // rawPlayhead 可见性（且 GlowWordEngine 纪律为只消
        // 费宿主喂入位置）。状态位保证每行只落一条；拼串
        // 只发生在真正过线的那一帧，逐帧零格式化。
        if syncProbeSweepTrackId != track.id
            || syncProbeSweepLineIndex != idx {
            syncProbeSweepTrackId = track.id
            syncProbeSweepLineIndex = idx
            let line = lines[idx]
            let mid = line.start + (line.end - line.start) * 0.5
            if mid > line.start, position >= mid {
                Breadcrumbs.log("sync.probe kind=sweep50 track=\(track.id) lineIdx=\(idx) lineStart=\(String(format: "%.3f", line.start)) mid=\(String(format: "%.3f", mid)) judgeNow=\(String(format: "%.3f", position)) rawPlayhead=\(String(format: "%.3f", engine.rawPlayhead())) wall=\(String(format: "%.3f", CACurrentMediaTime()))")
            } else {
                // 尚未过线：清掉记录，下帧继续判定（记录只
                // 在落屑后才成为「已触发」的锁存）。
                syncProbeSweepTrackId = nil
                syncProbeSweepLineIndex = nil
            }
        }
        if lastStageLineTrackId == track.id, lastStageLineIndex == idx { return }
        let isFlip = lastStageLineTrackId == track.id && lastStageLineIndex != nil
        lastStageLineTrackId = track.id
        lastStageLineIndex = idx
        Breadcrumbs.log("stage line track=\(track.id) idx=\(idx) lineStart=\(String(format: "%.3f", lines[idx].start)) judge=\(String(format: "%.3f", position)) raw=\(String(format: "%.3f", engine.rawPlayhead())) engine=\(String(format: "%.3f", engine.currentTime)) delta=\(String(format: "%.3f", position - engine.currentTime))")
        if isFlip {
            Breadcrumbs.log("stage flip src=judge track=\(track.id) idx=\(idx) judgeLag=\(String(format: "%.3f", position - lines[idx].start))")
            // sync.probe judge 翻行（3.7 (53) 工作流 F，只
            // 埋点）：与 sweep50 同字段同口径——judgeNow =
            // 本台锚外推呈现钟（与 stage line 的 judge 同
            // 值）、rawPlayhead = PlaybackEngine 真值直读、
            // wall = CACurrentMediaTime 墙钟戳；两探针的
            // judgeNow − rawPlayhead 差值可比对恒定偏移。
            Breadcrumbs.log("sync.probe kind=judge track=\(track.id) lineIdx=\(idx) lineStart=\(String(format: "%.3f", lines[idx].start)) judgeNow=\(String(format: "%.3f", position)) rawPlayhead=\(String(format: "%.3f", engine.rawPlayhead())) wall=\(String(format: "%.3f", CACurrentMediaTime()))")
            // §0 出声基准·翻行同帧（3.7 (67) B 组）：judge/raw
            // 与出声估计 sndEst 同行落盘，dJudge/dSnd 分开判读
            // （呈现钟偏差 vs 出声链偏差），按 wordSrc 分组。
            let afF = SyncProbe67.audioFields()
            let rawF = engine.rawPlayhead()
            let sndEst = rawF - afF.outLat
            Breadcrumbs.log("sync.snd idx=\(idx) judge=\(SyncProbe67.fmt(position)) raw=\(SyncProbe67.fmt(rawF)) sndEst=\(SyncProbe67.fmt(sndEst)) dJudge=\(SyncProbe67.fmt(position - lines[idx].start)) dSnd=\(SyncProbe67.fmt(sndEst - lines[idx].start)) route=\(afF.route) outLat=\(SyncProbe67.fmt(afF.outLat)) ioBuf=\(SyncProbe67.fmt(afF.ioBuf)) src=\(SyncProbe67.wordSource(of: lines)) style=\(activeStyleId) wall=\(SyncProbe67.fmt(CACurrentMediaTime()))")
        }
    }

    private func frameStatsText() -> String {
        guard !frameDurations.isEmpty else { return "mean=n/a p95=n/a n=0" }
        let sorted = frameDurations.sorted()
        let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        let mean = frameDurations.reduce(0, +) / Double(frameDurations.count)
        return String(format: "mean=%.1fms p95=%.1fms n=%d",
                      mean * 1000, sorted[index] * 1000, sorted.count)
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private extension LyricStageCommand.Kind {
    var logName: String {
        switch self {
        case .toggle: return "toggle"
        case .seek(let position): return "seek(\(Int(position)))"
        case .next: return "next"
        case .prev: return "prev"
        case .like: return "like"
        case .close: return "close"
        }
    }
}

// MARK: - 贴纸层（3.7 (24)，纯新增视图层）
//
// 场景（scene-mapping.md 终版；3.7 (25) 修订）：
// - 拉歌词：取词在途时 renderer 容器右上内侧亮 dog-06 角标
//   （探头张望，40pt，循环；抠图透明底直贴、无底板）。
// - 没找到歌词：取词落定且行为空时，cat-11（流泪转圈）
//   72pt 居中于容器中央上方（「暂无歌词」标签上方），播
//   一次停末帧。
// - 点红心：点亮时 dog-11（抱爱心）64pt 浮在容器右上内侧
//   （取词角标在显时左移让位），播 2 圈后淡出；旧落点（红心
//   按钮左侧）会压标题右端，(25) 迁走。
// - 播放陪伴：(25) 的框内陪伴层（CompanionPetView）已于
//   3.7 (27) 按 Miller 定案整体删除（「都没看见出现过」），
//   表情包互动主场迁至迷你台/进度条（MiniBarPetStage）。
// 显隐只由取词/点赞既有落点的一行钩子驱动；歌词数据、时钟
// 与渲染逻辑零改动。

extension StageViewController {

    func stickerInstall() {
        let badge = StickerView()
        badge.crumbScene = "stage-lyric-fetch"
        badge.isHidden = true
        view.addSubview(badge)
        stickerFetchBadge = badge
        let noLyrics = StickerView()
        noLyrics.crumbScene = "stage-no-lyrics"
        noLyrics.isHidden = true
        view.addSubview(noLyrics)
        stickerNoLyrics = noLyrics
        let like = StickerView()
        like.crumbScene = "stage-like"
        like.isHidden = true
        view.addSubview(like)
        stickerLike = like
        stickerLayoutOverlays()
    }

    func stickerLyricsFetching() {
        stickerNoLyrics?.isHidden = true
        guard let badge = stickerFetchBadge else { return }
        if badge.isHidden {
            badge.setSticker("dog-06", mode: .loop)
            badge.isHidden = false
        }
    }

    func stickerLyricsResolved(lines: [LyricLine]) {
        stickerFetchBadge?.isHidden = true
        if lines.isEmpty {
            stickerNoLyrics?.setSticker("cat-11", mode: .once(holdLast: true))
            stickerNoLyrics?.isHidden = false
        } else {
            stickerNoLyrics?.isHidden = true
        }
    }

    func stickerShowLikeCelebration() {
        guard let like = stickerLike else { return }
        like.alpha = 1
        like.isHidden = false
        // 轮廓柔光（3.7 (28)）：dog-11 线条型浅色主体，深色
        // 封面上靠一圈极淡亮边保轮廓可辨。
        like.silhouetteHaloEnabled = true
        like.setSticker("dog-11", mode: .loops(2))
        like.onFinished = { [weak like] in
            UIView.animate(withDuration: 0.3) {
                like?.alpha = 0
            } completion: { _ in
                like?.isHidden = true
                like?.alpha = 1
            }
        }
        stickerLayoutOverlays()
    }

    /// 取消收藏（3.7 (28) 新增，与收藏庆祝成对）：同一落点冒
    /// cat-04（单爪抹泪，映射里「取消收藏」场景的定案主选），
    /// 播一次停末帧、多停留 1.1s 再淡出。
    func stickerShowUnlikeSticker() {
        guard let like = stickerLike else { return }
        like.alpha = 1
        like.isHidden = false
        like.silhouetteHaloEnabled = false
        like.setSticker("cat-04", mode: .once(holdLast: true))
        like.onFinished = { [weak like] in
            UIView.animate(withDuration: 0.3, delay: 1.1, options: []) {
                like?.alpha = 0
            } completion: { _ in
                like?.isHidden = true
                like?.alpha = 1
            }
        }
        stickerLayoutOverlays()
    }

    func stickerLayoutOverlays() {
        let region = rendererContainer.frame
        if let badge = stickerFetchBadge {
            badge.frame = CGRect(
                x: region.maxX - 12 - 40, y: region.minY + 12,
                width: 40, height: 40)
        }
        if let noLyrics = stickerNoLyrics {
            noLyrics.frame = CGRect(
                x: region.midX - 36, y: region.midY - 56 - 36,
                width: 72, height: 72)
        }
        if let like = stickerLike {
            // 穿模治理（3.7 (25)）：迁到容器右上内侧纯封面/歌词
            // 空区；取词角标同在右上时左移 48 让位，不叠贴。
            var likeX = region.maxX - 12 - 64
            if let badge = stickerFetchBadge, !badge.isHidden {
                likeX -= 48
            }
            like.frame = CGRect(
                x: likeX, y: region.minY + 12,
                width: 64, height: 64)
        }
    }
}

// MARK: - 自定义背景（3.7 (47)）

extension StageViewController: PHPickerViewControllerDelegate {

    /// 按槽位现状装配/卸下自定义背景，并同步宿主氛围三件套
    /// 显隐。viewDidLoad、选入成功、恢复样式背景三处调用。
    func refreshCustomBackground() {
        // (62) 视频层升格：独立开关开且视频层槽有内容时优先用视频层
        // 槽（与 (47) 自定义背景槽分开）；否则沿 (47) 自定义背景槽。
        let videoEntry = SettingsStore.videoLayerEnabled
            ? CustomBackgroundStore.currentVideoLayer : nil
        let entry = videoEntry ?? CustomBackgroundStore.current
        if let entry {
            customBgView.apply(kind: entry.kind, url: entry.url)
            // (62) 不透明度/填充方式真消费。
            customBgView.applyLayerRendering(
                opacity: SettingsStore.videoLayerOpacity,
                fill: SettingsStore.videoLayerFillMode == 0)
            backdropImageView.isHidden = true
            backdropBlur.isHidden = true
            backdropTint.isHidden = true
            Breadcrumbs.log("custombg.apply kind=\(entry.kind.rawValue)"
                + " layer=\(videoEntry != nil ? "video62" : "custom47")")
            if view.window != nil { customBgView.play() }
        } else {
            customBgView.clearContent()
            customBgView.alpha = 1
            // (66) 透明舞台背景开时不复显底图层（refresh62Settings 同口径）。
            let transparent = SettingsStore.transparentStageBackground62
            backdropImageView.isHidden = transparent
            backdropBlur.isHidden = transparent
            backdropTint.isHidden = transparent
        }
        // 渲染器让位联动（3.7 (50)，(47) 挂账①）：莫奈/浮名自带
        // 底靠渲染器在 applySnapshot 时直读 Store 让位——台开着
        // 选入/清除背景只走本函数，不重推快照则要等下一次切歌
        // 才生效。renderer 未装配（viewDidLoad 路径）时跳过，
        // 装配后的首次快照自会读到当前 Store 状态。
        if renderer != nil { pushSnapshot() }
    }

    func presentCustomBackgroundPicker() {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 1
        // .current 取原文件（GIF/APNG 帧与视频原片不被转码）。
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController,
                didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadFileRepresentation(
                forTypeIdentifier: UTType.movie.identifier
            ) { [weak self] url, _ in
                guard let self else { return }
                guard let url else {
                    self.customBgFail(reason: "no-file")
                    return
                }
                // 临时文件仅在回调存活期内有效，装槽必须同步完成。
                self.installCustomBackground(sourceURL: url, kind: .video)
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadFileRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { [weak self] url, _ in
                guard let self else { return }
                guard let url else {
                    self.customBgFail(reason: "no-file")
                    return
                }
                let kind: CustomBackgroundKind =
                    CustomBackgroundStore.imageFrameCount(at: url) > 1
                    ? .animated : .image
                self.installCustomBackground(sourceURL: url, kind: kind)
            }
        } else {
            customBgFail(reason: "unsupported-type")
        }
    }

    private func installCustomBackground(sourceURL: URL,
                                         kind: CustomBackgroundKind) {
        do {
            let bytes = try CustomBackgroundStore.install(
                sourceURL: sourceURL, kind: kind)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                Breadcrumbs.log(
                    "custombg.set kind=\(kind.rawValue) bytes=\(bytes)")
                self.refreshCustomBackground()
            }
        } catch CustomBackgroundStore.InstallError.tooLarge(let limit) {
            customBgFail(reason: "too-large limit=\(limit)")
        } catch {
            customBgFail(reason: "copy-failed")
        }
    }

    private func customBgFail(reason: String) {
        Breadcrumbs.log("custombg.fail reason=\(reason)")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil else { return }
            let message: String
            if reason.hasPrefix("too-large") {
                message = "文件太大了：图片/动图上限 30MB，视频上限 200MB。"
            } else if reason == "unsupported-type" {
                message = "这个文件类型不支持做背景。"
            } else {
                message = "背景没存上，请再试一次。"
            }
            let alert = UIAlertController(
                title: "自定义背景", message: message,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            self.present(alert, animated: true)
        }
    }
}

// MARK: - 网页舞台宿主（3.7 (51) 新链）

/// 未迁样式的网页舞台兜底宿主（3.7 (51)）：全屏承载桥的 WebView，
/// 由原生舞台叠加 present——本包后唯一允许的网页通道（样式选择器
/// 8 个未迁样式 sonnet/tempera/lumiere/hanabi/machi/nebbia/pendolo/
/// diorama 选中仍走它）。
///
/// 新旧差异：旧链是替换式呈现——关原生舞台、收整摞原生墙、请前端
/// 在根 WebView 里开页，关页后靠回程票（WallReturnTicketStore）重
/// 建主页墙+曲目墙恢复上下文；新链是叠加式——原生舞台不退场，宿
/// 主盖在其上，网页舞台关闭（前端 stageClosed 过桥）后宿主自
/// dismiss，呈现栈直接落回原生舞台，播放/队列/样式状态全保留，
/// 无票据、无重建。宿主另带一个原生「关闭」键作逃生口（网页无响
/// 应/未落到播放页时用户仍能退回原生舞台）。
///
/// 桥开页提示条（13.5）与桥致命错误浮层原挂 MainViewController 作
/// 根时承载，已随 (51) 换根摘除其安装点；这两件只在 WebView 在场
/// 时有意义，改由本宿主在 WebView 之上承载，行为口径不变。
final class WebStageHostViewController: UIViewController {

    /// 宿主被 dismiss 后回调一次（原生舞台据此复位跳网页标志、
    /// 对齐样式选择器状态到返回上下文）。
    var onClosed: (() -> Void)?
    private var didFireClosed = false
    private var noticeView: UIView?
    private var noticeLabel: UILabel?
    private var noticeRetryButton: UIButton?
    private var noticeRetryLeading: NSLayoutConstraint?
    private var noticeRetryTrailing: NSLayoutConstraint?
    private var noticeLabelTrailing: NSLayoutConstraint?
    private var fatalErrorView: UIView?
    private var cancellables = Set<AnyCancellable>()

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black

        let webView = WebEffectBridge.shared.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // 逃生关闭键（与主页墙关闭键同款式）：网页舞台自有关闭
        // 走 stageClosed 通道，本键只兜网页无响应的场面。
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

        // 前端 stageClosed 过桥（桥转发 .foliaStageClosed）：网页
        // 舞台已关，宿主自 dismiss 回原生舞台。
        NotificationCenter.default.addObserver(
            self, selector: #selector(webStageClosed),
            name: .foliaStageClosed, object: nil)

        // 开页提示条（13.5）：原 MainViewController 的安装点随换
        // 根摘除，改挂本宿主。
        WebEffectBridge.shared.onOpenStageNotice = { [weak self] notice in
            self?.updateNotice(notice)
        }
        // 桥致命错误浮层：同上，改挂本宿主。
        WebEffectBridge.shared.$lastFatalError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if error != nil {
                    self?.showFatalErrorOverlay()
                } else {
                    self?.hideFatalErrorOverlay()
                }
            }
            .store(in: &cancellables)
        Breadcrumbs.log("webstage host loaded")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed, !didFireClosed else { return }
        didFireClosed = true
        // 提示回调只在宿主在场时归本宿主，退场即摘除，防桥把
        // 后续开页提示投给已退场的宿主。
        WebEffectBridge.shared.onOpenStageNotice = nil
        Breadcrumbs.log("webstage host closed")
        onClosed?()
    }

    @objc private func webStageClosed() {
        dismiss(animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: 开页提示条（13.5，与原 MainViewController 承载同口径）

    private func updateNotice(_ notice: WebEffectBridge.OpenStageNotice?) {
        guard let notice else {
            noticeView?.removeFromSuperview()
            noticeView = nil
            return
        }
        if noticeView == nil {
            let pill = UIView()
            pill.backgroundColor = UIColor.black.withAlphaComponent(0.78)
            pill.layer.cornerRadius = 16
            pill.layer.borderWidth = 0.5
            pill.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
            pill.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.textColor = .white
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false

            let retry = UIButton(type: .system)
            retry.setTitle("重试", for: .normal)
            retry.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            retry.tintColor = .white
            retry.translatesAutoresizingMaskIntoConstraints = false
            retry.addTarget(self, action: #selector(retryOpenStage), for: .touchUpInside)

            pill.addSubview(label)
            pill.addSubview(retry)
            view.addSubview(pill)
            // opening 态没有重试按钮：按钮隐藏时改走 label 直达
            // 右缘的约束（13.5 审查低-3，同原承载口径）。
            let retryLeading = retry.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10)
            let retryTrailing = retry.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12)
            let labelTrailing = label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14)
            labelTrailing.isActive = false
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                pill.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
                pill.heightAnchor.constraint(equalToConstant: 32),
                label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
                label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
                retryLeading,
                retryTrailing,
                retry.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
            ])
            noticeRetryLeading = retryLeading
            noticeRetryTrailing = retryTrailing
            noticeLabelTrailing = labelTrailing
            noticeView = pill
            noticeLabel = label
            noticeRetryButton = retry
        }
        switch notice {
        case .opening:
            noticeLabel?.text = "正在打开播放页…"
            noticeRetryButton?.isHidden = true
            noticeRetryLeading?.isActive = false
            noticeRetryTrailing?.isActive = false
            noticeLabelTrailing?.isActive = true
        case .failed:
            noticeLabel?.text = "播放页没打开"
            noticeRetryButton?.isHidden = false
            noticeLabelTrailing?.isActive = false
            noticeRetryLeading?.isActive = true
            noticeRetryTrailing?.isActive = true
        }
        if let pill = noticeView {
            view.bringSubviewToFront(pill)
        }
    }

    @objc private func retryOpenStage() {
        WebEffectBridge.shared.retryOpenStage()
    }

    // MARK: 桥致命错误浮层（与原 MainViewController 承载同口径）

    private func showFatalErrorOverlay() {
        guard fatalErrorView == nil else { return }
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "页面进程反复中断，已停止自动恢复"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let retry = UIButton(type: .system)
        retry.setTitle("重新加载", for: .normal)
        retry.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        retry.addTarget(self, action: #selector(retryWebContent), for: .touchUpInside)
        retry.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(retry)
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -24),
            retry.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            retry.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16)
        ])
        fatalErrorView = container
    }

    private func hideFatalErrorOverlay() {
        fatalErrorView?.removeFromSuperview()
        fatalErrorView = nil
    }

    @objc private func retryWebContent() {
        WebEffectBridge.shared.retryAfterFatalError()
    }
}

// (84) 第 3 条：(82) 的 UIGestureRecognizerDelegate 豁免扩展已删（同两面墙）。
