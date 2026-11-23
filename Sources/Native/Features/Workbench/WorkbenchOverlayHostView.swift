import UIKit

// WorkbenchOverlayHostView.swift
//
// (53) A 组工作台浮层宿主（DS 对账结论 1–4 的落点）：
// 1. 不换 root、不建容器 VC——HomeWallViewController 仍是 root，
//    本视图只是叠在 HomeWall.view 上的浮层（HomeWall 侧仅在
//    viewDidLoad 末尾加装本宿主，墙画布/入场/点卡 route 零改动）。
// 2. 关闭态 hitTest 只认把手一个极小命中区，其余全部
//    返回 nil 穿透给墙（平移/点卡/迷你台/齿轮/搜索照常）。
//    （(61) WA：侧栏悬浮头像钮整只删除——它与速记簿热区打架
//    且即 (55)–(58) 幽灵本体；登录入口保留导航台头像＋侧栏内
//    sidebarAvatar 两处，侧栏开合只靠把手与既有手势。）
// 3. 开侧栏只经左缘离散把手（点按或在把手上横拖），不用
//    UIScreenEdgePanGestureRecognizer，不与墙 pan 抢手势；
//    侧栏展开期间经 onSidebarVisibilityChanged 禁墙平移/点按，
//    关闭动画完成后恢复。展开/收起走系统弹簧
//    （UIViewPropertyAnimator + UISpringTimingParameters）。
// 4. 分区页一律从宿主 VC（HomeWall）以既有 present 能力发出，
//    不新建导航根；点播后 dismissToWall 一路关回墙。
//
// 网页版对照（folia-major）：书库窄缝（libraryBravais seam：
// 「书库」标题 + 竖排页签 歌单/电台/专辑/本地 + 账户头像 +
// 底部工具格 搜索/设置，见 PonderBravaisWallParts 的
// BravaisHomeSeam 与 library/core/home 的 HomeViewTab =
// playlist/radio/albums/local/explore）。原生侧形态按触屏
// 改为左缘把手抽屉，构成与入口一一对应：歌单/电台/搜索/
// 专辑/本地 + 头像账户区 + 设置入口。
//
// (58) 定稿①（幽灵头像钮根治，DS Pro 对账定稿）：(54)/(55)/
// (56) 三轮修复都被真机证伪——静态逐路径推演在「animator
// completion 必达＋手势终结事件必达」前提下全收敛到藏，但真
// 机落定开态下 avatarButton 与 handleView 双双可见。三候选机
// 制（取证排序）：第三机制（layoutSubviews 在 transform≠
// identity 时重设 frame → 视觉满开而 presentation.tx 不达
// 标 → 落定对账永不触发）＞ B′（拖动终结被吞、拖动态卡死）
// ＞ A（animator completion 不交付＋presentation 冻结）。
// 本版不再押任何单一收口路径，改单一呈现状态机为唯一事实
// 源：chrome 显隐只由状态机经 applyChrome 派生；面板几何写
// 入收敛到 updateGeometry 单通道、按 generation 校验；拖动
// 态加 500ms 看门狗（与手势真实状态交叉核对）；落定双核
// （状态＋面板实际右缘 model 读法）；不变式自愈带 Pro 门控；
// 每次 chrome 写入落 workbench.chrome.audit 自证面包屑（字
// 段含 gestureRawState/animatorGeneration/animatorIdentity/
// stackHash 与 panelOpenGeom），复现一次即可从日志定罪。
//
// (73) 形态改造（Miller 18:39/18:40 定版）：控制台自左缘
// 抽屉改为顶部控制设置台——
// - 收起态：左上角一条白色横线把手（安全区内贴左），点按
//   展开、在把手上竖拖跟手；收起动画回到该横线处。
// - 展开态：面板自顶部垂下、占据整幅宽度，顶缘正中开灵
//   动岛凹口（竖屏 14 Pro 几何：凹口宽 142、高 54，岛嵌在
//   凹口里露出，面板不压岛）；内容自凹口底之下排布，系
//   统状态栏区域由凹口＋内容顶距让行。横屏岛在左侧边中
//   段：面板整体右让 52pt 避岛，不压岛。
// - 展开/收起仍走本状态机与系统弹簧（animator 不变），几
//   何轴向由 tx 改 ty：关闭位 ty=−panelHeight、满开 0；
//   audit 字段随轴改名 modelTy/presTy/modelBottom/presBottom，
//   geomOK 恒等式改 panelHeight + modelTy。
// - 原左上角独立浮灯泡（WB62 思索钮）撤除：灯泡收进本台
//   底行作「导播台」入口（点开 Ponder62 导览列表面）。
// 功能项一个不少：账户头/三家状态/歌单/电台/搜索/专辑/
// 本地/设置全保留，仅换容器排布（分区改 3×2 格＋导播台行）。

final class WorkbenchOverlayHostView: UIView {

    /// 呈现分区页的宿主（HomeWallViewController）。
    weak var hostViewController: UIViewController?
    /// 侧栏展开态变化（禁/恢复墙交互）：打开在动画开始即报，
    /// 关闭在面板落到关闭位后才报（收起途中墙仍被滑出中的
    /// 面板盖着）；守卫收口路径下面板已在关闭位，等同落定、
    /// 同样在此报。全部发送经 emitSidebarVisibility 对账去重，
    /// false/true 严格配平（(55) 工作流 A）。
    var onSidebarVisibilityChanged: ((Bool) -> Void)?

    /// 意图开关（旧 isSidebarOpen 语义沿用：开/关发起即翻转、
    /// 拖动期保持拖前值、落定后与状态机一致）。真实呈现态以
    /// sidebarState 为准，本旗标只供旧调用点的意图判读。
    var isSidebarOpen: Bool { intentOpen }
    private var intentOpen = false

    // MARK: - 呈现状态机（(58) 定稿①）

    /// 侧栏呈现状态：唯一事实源。closed/open 为落定态，
    /// dragging 为手势跟手期，settling 为 animator 收口期
    /// （generation 代次＋目标向）。
    private enum SidebarState: Equatable {
        case closed
        case open
        case dragging
        case settling(generation: Int, targetOpen: Bool)
    }

    private var sidebarState: SidebarState = .closed
    /// 代次：每次开/关发起或拖动接管递增；旧 animator 的
    /// completion 与几何写入凭代次失效（见 updateGeometry）。
    private var sidebarGeneration = 0
    private var sidebarAnimator: UIViewPropertyAnimator?
    /// 在途 animator 的身份与代次（audit 字段）：无 animator
    /// 时 identity="-"、generation=-1。
    private var animatorIdentity = "-"
    private var animatorGeneration = -1
    /// 当前面板进度（0=关闭位、1=满开位）：progressTransit
    /// 每次写入时更新；动画途中为 model 终点值（与旧版
    /// transform.tx 口径一致）。
    private var currentProgress: CGFloat = 0
    /// 最近一次状态迁移（beginTransition/拖动接管）开始时刻：
    /// 不变式自愈的 300ms 门控据此计时。
    private var lastTransitionBeginAt: CFTimeInterval = 0
    /// 最近一次手势事件时刻（拖动态看门狗的 idle 判定）。
    private var lastGestureEventAt: CFTimeInterval = 0
    /// 最近一次手势回调的真实状态名（audit 的 gestureRawState
    /// 在无活跃识别器时回退到此值）。
    private var lastGestureRawState = "possible"
    /// 当前拖动的所属识别器（双指边缘防抢）：dragging 期间
    /// 只有 owner 识别器的回调能推进/终结本次拖动。
    private var dragOwner: ObjectIdentifier?
    /// 拖动态看门狗（500ms idle 强制迁出，防 B′ 卡死）。
    private var dragWatchdog: Timer?
    /// 看门狗「按住静止」audit 只落一次/拖（防刷屏）。
    private var watchdogHoldLogged = false
    /// 拖动态 audit 节流（20Hz 上限）：写入照常、落行采样——
    /// 落定点位与拖动始终点全量落行，定罪信息不靠拖动中段
    /// 的高频采样。
    private var lastDragAuditAt: CFTimeInterval = 0
    /// 上次 layout 的 bounds 尺寸：面板 frame 只在尺寸变化时
    /// 写（见 layoutSubviews），同尺寸 pass 零 frame 写入。
    private var lastSidebarSize: CGSize = .zero

    private var isDraggingSidebar: Bool {
        if case .dragging = sidebarState { return true }
        return false
    }

    private var sidebarStateName: String {
        switch sidebarState {
        case .closed: return "closed"
        case .open: return "open"
        case .dragging: return "dragging"
        case .settling: return "settling"
        }
    }

    /// 最近一次经 onSidebarVisibilityChanged 实际报出的可见态；
    /// 发送对账的唯一依据，初值与关闭态一致（false）。
    private var reportedSidebarVisible = false

    private let scrimView = UIView()
    private let sidebarView = UIView()
    private let handleView = UIView()
    /// (73) 白线本体（44×5）：handleView 是 60×36 透明命
    /// 中盒（5pt 线直接命中不可靠），白线居其左上呈现。
    private let handleLineView = UIView()
    /// (73) 面板内容容器：整体自 contentTopPad 之下排布
    /// （让灵动岛凹口与状态栏），顶距约束由 layout 按安全
    /// 区/朝向更新。
    private let contentView = UIView()
    private var contentTopConstraint: NSLayoutConstraint?
    /// (73) 面板背景三层（Miller 18:48 定：展开台半透明毛
    /// 玻璃）：系统毛玻璃（systemThickMaterialDark，透出下
    /// 方墙面）＋主题底色 45% 暗调层（保白字对比）＋剪影
    /// 描边层（凹口与底角边缘干净）。前两层各挂一份剪影
    /// mask（even-odd 切灵动岛凹口），内容层（contentView）
    /// 在其上、不参与模糊，文字控件保持清晰。sidebarView
    /// 本体透明，layer.shadowPath 同步剪影形。
    private let panelBlurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemThickMaterialDark))
    private let panelTintView = UIView()
    private let panelBlurMask = CAShapeLayer()
    private let panelTintMask = CAShapeLayer()
    private let panelEdgeLayer = CAShapeLayer()

    /// 手势识别器引用（audit 的 gestureRawState 实时读源＋
    /// 看门狗交叉核对）：build 时各存一份。
    private var handlePanGesture: UIPanGestureRecognizer?
    private var sidebarPanGesture: UIPanGestureRecognizer?
    private var scrimPanGesture: UIPanGestureRecognizer?

    // 侧栏内件
    private let sidebarAvatar = WorkbenchAvatarView()
    private let accountNameLabel = UILabel()
    private let accountHintLabel = UILabel()
    private let providerStack = UIStackView()
    private var providerLabels: [NativeSessionStore.Provider: UILabel] = [:]
    private var providerDots: [NativeSessionStore.Provider: UIView] = [:]

    /// 已加载头像的 URL 键；nil = 还没刷过（旧值 "" 与「无头像」
    /// 的键撞车，首刷时 setFallback 被整段跳过、占位「?」糊脸，
    /// (54) 工作流 N 修）。
    private var avatarLoadKey: String?

    /// (73) 顶部台高度：内容顶距＋内容行高合计，钳制在屏
    /// 高留 56pt 余量内（横屏矮屏不许把底行裁掉）。
    private var panelHeight: CGFloat {
        guard bounds.height > 0 else { return 400 }
        return min(contentTopPad + Self.deskContentHeight,
                   bounds.height - 56)
    }

    /// (73) 内容顶距：竖屏让出灵动岛凹口底（54）再让 8，
    /// 且不低于安全区＋6（状态栏系统件区域让行）；横屏顶
    /// 部无岛，安全区＋10。
    private var contentTopPad: CGFloat {
        if bounds.width < bounds.height, safeAreaInsets.top >= 44 {
            return max(safeAreaInsets.top + 6, Self.islandNotchHeight + 8)
        }
        return safeAreaInsets.top + 10
    }

    /// (73) 灵动岛凹口尺寸（竖屏）：岛本体 ≈126×37、顶距
    /// ≈11（底 ≈48）；凹口宽 142（左右各让 8）、高 54
    /// （底让 6），岛嵌在凹口里完整露出。
    private static let islandNotchWidth: CGFloat = 142
    private static let islandNotchHeight: CGFloat = 54
    /// (73) 横屏让岛：面板左缘右移量（岛深 ≈37＋呼吸 15）。
    private static let landscapeIslandClearance: CGFloat = 52
    /// (73) 内容行高合计（与 build 排布常量对账）：账户头
    /// 70＋三家状态 63＋分隔块 31＋分区格 98＋导播台行
    /// （间距 12＋行 46）＋底垫 14。
    private static let deskContentHeight: CGFloat =
        70 + 63 + 31 + 98 + 12 + 46 + 14

    /// (73) 凹口在面板坐标系的矩形（顶边开口：y 自 −20 起
    /// 切掉面板顶缘中段）；横屏/无岛机型为 nil（不切凹口）。
    private var islandNotchRect: CGRect? {
        guard bounds.width < bounds.height,
              safeAreaInsets.top >= 44 else { return nil }
        let panelW = sidebarView.bounds.width > 0
            ? sidebarView.bounds.width : bounds.width
        return CGRect(x: (panelW - Self.islandNotchWidth) / 2, y: -20,
                      width: Self.islandNotchWidth,
                      height: Self.islandNotchHeight + 20)
    }

    init(hostViewController: UIViewController) {
        self.hostViewController = hostViewController
        super.init(frame: .zero)
        backgroundColor = .clear
        buildScrimAndSidebar()
        buildHandle()
        refreshAccountUI()
        // 强制点位（(58) 定稿①）：回前台时按状态机核对一次
        // 不变式——后台期间被系统搅动的呈现残局在此收口。
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        Breadcrumbs.log("workbench.host.install")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        NotificationCenter.default.removeObserver(self)
        dragWatchdog?.invalidate()
    }

    @objc private func appDidBecomeActive() {
        auditChrome(caller: "didBecomeActive")
        enforceInvariant(caller: "didBecomeActive")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // 强制点位（(58) 定稿①）：入窗时核对一次。
        auditChrome(caller: "didMoveToWindow")
        enforceInvariant(caller: "didMoveToWindow")
    }

    // MARK: - 构建

    private func buildScrimAndSidebar() {
        scrimView.backgroundColor = UIColor.black.withAlphaComponent(1)
        scrimView.alpha = 0
        scrimView.isHidden = true
        scrimView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(scrimTapped)))
        let scrimPan = UIPanGestureRecognizer(target: self, action: #selector(sidebarPanned(_:)))
        scrimView.addGestureRecognizer(scrimPan)
        scrimPanGesture = scrimPan
        addSubview(scrimView)

        // (73) 面板本体透明：背景＝毛玻璃＋暗调层（剪影
        // mask 切底圆角＋灵动岛凹口），阴影沿剪影走
        // （shadowPath 在 layout 的 updatePanelShape 同步）。
        sidebarView.backgroundColor = .clear
        panelBlurView.isUserInteractionEnabled = false
        panelBlurMask.fillRule = .evenOdd
        panelBlurView.layer.mask = panelBlurMask
        sidebarView.addSubview(panelBlurView)
        panelTintView.backgroundColor =
            WorkbenchTheme.background.withAlphaComponent(0.45)
        panelTintView.isUserInteractionEnabled = false
        panelTintMask.fillRule = .evenOdd
        panelTintView.layer.mask = panelTintMask
        sidebarView.addSubview(panelTintView)
        panelEdgeLayer.fillColor = UIColor.clear.cgColor
        panelEdgeLayer.strokeColor =
            UIColor.white.withAlphaComponent(0.14).cgColor
        panelEdgeLayer.lineWidth = 1
        sidebarView.layer.addSublayer(panelEdgeLayer)
        sidebarView.layer.shadowColor = UIColor.black.cgColor
        sidebarView.layer.shadowOpacity = 0.45
        sidebarView.layer.shadowRadius = 24
        sidebarView.layer.shadowOffset = CGSize(width: 0, height: 6)
        let sidebarPan = UIPanGestureRecognizer(target: self, action: #selector(sidebarPanned(_:)))
        sidebarView.addGestureRecognizer(sidebarPan)
        sidebarPanGesture = sidebarPan
        addSubview(sidebarView)

        // (73) 内容容器：顶距由 layout 按安全区/朝向更新
        // （竖屏让凹口、横屏让状态栏），内部排布相对容器。
        contentView.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(contentView)
        let topC = contentView.topAnchor.constraint(
            equalTo: sidebarView.topAnchor, constant: 69)
        contentTopConstraint = topC
        NSLayoutConstraint.activate([
            topC,
            contentView.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor)
        ])

        // —— 账户头（点按进登录页：未登录去登录、已登录去管理）——
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(accountTapped)))
        contentView.addSubview(header)
        sidebarAvatar.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(sidebarAvatar)
        let titleLabel = UILabel()
        titleLabel.text = "书库"
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = WorkbenchTheme.secondary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)
        accountNameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        accountNameLabel.textColor = WorkbenchTheme.primary
        accountNameLabel.lineBreakMode = .byTruncatingTail
        accountNameLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(accountNameLabel)
        accountHintLabel.font = .systemFont(ofSize: 12)
        accountHintLabel.textColor = WorkbenchTheme.secondary
        accountHintLabel.text = "点按管理登录"
        accountHintLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(accountHintLabel)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: contentView.topAnchor),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sidebarAvatar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            sidebarAvatar.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            sidebarAvatar.widthAnchor.constraint(equalToConstant: 48),
            sidebarAvatar.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: sidebarAvatar.trailingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: sidebarAvatar.topAnchor, constant: 1),
            titleLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            accountNameLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            accountNameLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            accountNameLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            accountHintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            accountHintLabel.topAnchor.constraint(equalTo: accountNameLabel.bottomAnchor, constant: 2),
            accountHintLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            header.bottomAnchor.constraint(equalTo: sidebarAvatar.bottomAnchor, constant: 14)
        ])

        // —— 三家登录状态行（B 组 ProviderSessionStatusQuery）——
        providerStack.axis = .vertical
        providerStack.spacing = 6
        providerStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(providerStack)
        for provider in NativeSessionStore.Provider.allCases {
            // 每行自带状态点（8×8，贴行首、与文字同行居中）：
            // 旧版三行只有文字、全侧栏的状态点只长在两个头像上，
            // 关闭态头像浮在侧栏之上时它的绿点正飘进文字行里
            // （(53) 真机截图，(54) 工作流 N 修）。
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            row.translatesAutoresizingMaskIntoConstraints = false
            let dot = UIView()
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.35)
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            row.addArrangedSubview(dot)
            let label = UILabel()
            label.font = .systemFont(ofSize: 12)
            label.textColor = WorkbenchTheme.secondary
            label.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(label)
            providerStack.addArrangedSubview(row)
            providerLabels[provider] = label
            providerDots[provider] = dot
        }
        NSLayoutConstraint.activate([
            providerStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            providerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            providerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])

        let divider = UIView()
        divider.backgroundColor = WorkbenchTheme.hairline
        divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: providerStack.bottomAnchor, constant: 16),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            divider.heightAnchor.constraint(equalToConstant: 1)
        ])

        // —— 分区（(73) 改 3×2 格：功能项一个不少——歌单/
        // 电台/搜索/专辑/本地/设置全在格内） ——
        let sectionsStack = UIStackView()
        sectionsStack.axis = .vertical
        sectionsStack.spacing = 6
        sectionsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sectionsStack)
        let gridRows: [[(WorkbenchSection, String, String)]] = [
            [(.playlists, "music.note.list", "歌单"),
             (.radio, "radio", "电台"),
             (.search, "magnifyingglass", "搜索")],
            [(.albums, "opticaldisc", "专辑"),
             (.local, "folder", "本地"),
             (.settings, "gearshape", "设置")]
        ]
        for rowItems in gridRows {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
            for (section, icon, title) in rowItems {
                row.addArrangedSubview(makeSectionRow(
                    section: section, icon: icon, title: title, compact: true))
            }
            sectionsStack.addArrangedSubview(row)
        }
        NSLayoutConstraint.activate([
            sectionsStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 14),
            sectionsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            sectionsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        ])

        // —— (73) 导播台行：原独立浮灯泡撤除后收进本台底
        // 行——灯泡＋「导播台」，点开 Ponder62 导览列表面
        // （openSection(.guide) 分发）。 ——
        let guideButton = makeSectionRow(section: .guide, icon: "lightbulb",
                                         title: "导播台", compact: true)
        guideButton.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        guideButton.tintColor = UIColor(red: 1.0, green: 0.84, blue: 0.40, alpha: 1)
        let guideHint = UILabel()
        guideHint.text = "功能导览"
        guideHint.font = .systemFont(ofSize: 12.5)
        guideHint.textColor = WorkbenchTheme.secondary
        guideHint.translatesAutoresizingMaskIntoConstraints = false
        guideButton.addSubview(guideHint)
        contentView.addSubview(guideButton)
        NSLayoutConstraint.activate([
            guideButton.topAnchor.constraint(equalTo: sectionsStack.bottomAnchor, constant: 12),
            guideButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            guideButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            guideHint.trailingAnchor.constraint(equalTo: guideButton.trailingAnchor, constant: -14),
            guideHint.centerYAnchor.constraint(equalTo: guideButton.centerYAnchor)
        ])
    }

    /// 分区行（compact＝(73) 顶部台格内紧凑行：高 46、字
    /// 15、内距收紧；非 compact 保留旧 50 高全宽行规格）。
    private func makeSectionRow(section: WorkbenchSection, icon: String,
                                title: String, compact: Bool = false) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon)
        config.imagePadding = compact ? 8 : 14
        config.imagePlacement = .leading
        config.title = title
        config.baseForegroundColor = WorkbenchTheme.primary
        config.contentInsets = compact
            ? NSDirectionalEdgeInsets(top: 11, leading: 10, bottom: 11, trailing: 10)
            : NSDirectionalEdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14)
        let button = UIButton(type: .system)
        button.configuration = config
        button.tintColor = WorkbenchTheme.primary
        button.titleLabel?.font = .systemFont(ofSize: compact ? 15 : 16, weight: .medium)
        button.contentHorizontalAlignment = .leading
        button.backgroundColor = WorkbenchTheme.rowFill
        button.layer.cornerRadius = 12
        button.accessibilityLabel = title
        button.addAction(UIAction { [weak self] _ in
            self?.openSection(section)
        }, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: compact ? 46 : 50).isActive = true
        return button
    }

    private func buildHandle() {
        // (73) 收起态把手：左上角一条白色横线（44×5、安全
        // 区内贴左），只它自己带手势（点按展开顶部台、在把
        // 手上竖拖跟手）。展开/收起动画自此位置生长/收回
        // （面板自顶部垂下、把手随进度淡出，见 applyChrome）。
        // handleView 本体透明作命中盒，白线由子视图呈现。
        handleView.backgroundColor = .clear
        handleLineView.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        handleLineView.layer.cornerRadius = 2.5
        handleLineView.layer.shadowColor = UIColor.black.cgColor
        handleLineView.layer.shadowOpacity = 0.35
        handleLineView.layer.shadowRadius = 3
        handleLineView.layer.shadowOffset = CGSize(width: 0, height: 1)
        handleLineView.isUserInteractionEnabled = false
        handleView.addSubview(handleLineView)
        handleView.accessibilityLabel = "打开控制台"
        handleView.isAccessibilityElement = true
        handleView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleTapped)))
        let handlePan = UIPanGestureRecognizer(target: self, action: #selector(handlePanned(_:)))
        handleView.addGestureRecognizer(handlePan)
        handlePanGesture = handlePan
        addSubview(handleView)
    }

    // MARK: - 布局（安全区/横竖屏）

    override func layoutSubviews() {
        super.layoutSubviews()
        scrimView.frame = bounds
        // 面板 frame（尺寸）只在宿主 bounds 尺寸变化时写，且写
        // 时先卸 transform、写完经 updateGeometry 按状态机现
        // 态恢复位移——(57) 前每个 layout pass 都在 transform
        // ≠identity 时重设 frame（UIKit 明示此用法未定义），
        // 是第三机制（视觉满开而 presentation.tx 不达标）的
        // 头号嫌疑源；(58) 从写入通道上根除：同尺寸 pass 对
        // 面板 frame/transform 零写入。
        let sizeChanged = bounds.size != lastSidebarSize
        if sizeChanged {
            lastSidebarSize = bounds.size
            let height = panelHeight
            let savedTransform = sidebarView.transform
            sidebarView.transform = .identity
            sidebarView.frame = panelFrame(height: height)
            sidebarView.transform = savedTransform
            contentTopConstraint?.constant = contentTopPad
            updatePanelShape()
            // 高度可能变了：按现态进度以新高重申位移（关闭
            // −height、满开 0、途中 −height×(1−progress)）。
            let ty: CGFloat
            switch sidebarState {
            case .closed: ty = -height
            case .open: ty = 0
            case .dragging, .settling: ty = -height * (1 - currentProgress)
            }
            updateGeometry(ty: ty, generation: sidebarGeneration, caller: "layout")
        }
        // (73) 把手：左上角白色横线（安全区内贴左）；命中
        // 盒 60×36 贴安全区顶，白线居盒内左上（8,8）。
        handleView.frame = CGRect(
            x: safeAreaInsets.left + 8, y: safeAreaInsets.top,
            width: 60, height: 36)
        handleLineView.frame = CGRect(x: 8, y: 8, width: 44, height: 5)
        if sizeChanged {
            // 旋转强制点位（(58) 定稿①）：宿主 bounds 尺寸变
            // 化即旋转/分屏落点，在此核对不变式＋落 audit。
            auditChrome(caller: "layout-resize")
            enforceInvariant(caller: "layout-resize")
        }
    }

    /// (73) 面板 frame：竖屏整幅宽贴顶；横屏岛在左侧边中
    /// 段，面板整体右让岛深（不压岛）。
    private func panelFrame(height: CGFloat) -> CGRect {
        if bounds.width > bounds.height {
            let inset = Self.landscapeIslandClearance
            return CGRect(x: inset, y: 0,
                          width: bounds.width - inset, height: height)
        }
        return CGRect(x: 0, y: 0, width: bounds.width, height: height)
    }

    /// (73) 面板剪影：底两角圆角 24；竖屏顶缘正中切灵动
    /// 岛凹口（even-odd 切口、凹口矩形顶边开口）——岛嵌在
    /// 凹口里完整露出、面板不压岛。毛玻璃/暗调两层 mask、
    /// 描边层与阴影路径同步此形。
    private func updatePanelShape() {
        let rect = sidebarView.bounds
        guard rect.width > 0, rect.height > 0 else { return }
        let path = UIBezierPath()
        let r: CGFloat = 24
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        path.addArc(withCenter: CGPoint(x: rect.width - r, y: rect.height - r),
                    radius: r, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: r, y: rect.height))
        path.addArc(withCenter: CGPoint(x: r, y: rect.height - r),
                    radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.close()
        if let notch = islandNotchRect {
            path.append(UIBezierPath(roundedRect: notch, cornerRadius: 20))
            path.usesEvenOddFillRule = true
        }
        panelBlurView.frame = rect
        panelTintView.frame = rect
        panelBlurMask.frame = rect
        panelBlurMask.path = path.cgPath
        panelTintMask.frame = rect
        panelTintMask.path = path.cgPath
        panelEdgeLayer.frame = rect
        panelEdgeLayer.path = path.cgPath
        sidebarView.layer.shadowPath = path.cgPath
    }

    // MARK: - 命中仲裁（DS 结论 2/3）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if sidebarState != .closed {
            // (73) 灵动岛凹口区（面板顶缘中段的空区）不吞触
            // 摸：落 scrim（点按关闭），与「面板外点按关闭」
            // 同语义，岛本体不被面板命中区覆盖。
            if let notch = islandNotchRect {
                let zone = CGRect(
                    x: sidebarView.frame.minX + notch.minX, y: 0,
                    width: notch.width, height: Self.islandNotchHeight)
                if zone.contains(point) { return scrimView }
            }
            // 展开（含动画/拖动中）：宿主整层接管——面板内走
            // super 分发，面板外落 scrim（点按关闭），墙与迷你
            // 台在此期间点不到（且墙交互已由回调禁用）。
            return super.hitTest(point, with: event) ?? scrimView
        }
        // 关闭态：只有把手一个极小命中区，其余穿透给墙。
        if handleView.frame.contains(point) {
            return super.hitTest(point, with: event)
        }
        return nil
    }

    // MARK: - 几何读数（落定双核的几何核，Pro 读法）

    /// CATransform3D → CGAffineTransform（2D 分量）。
    private func affine(from t: CATransform3D) -> CGAffineTransform {
        CGAffineTransform(a: CGFloat(t.m11), b: CGFloat(t.m12),
                          c: CGFloat(t.m21), d: CGFloat(t.m22),
                          tx: CGFloat(t.m41), ty: CGFloat(t.m42))
    }

    /// 面板底缘（model）：center.y − bounds.height/2 +
    /// bounds.applying(model transform).maxY。纯平移下恒等于
    /// panelHeight + ty——audit 的 geomOK 字段逐行自检此恒
    /// 等式（读法写错时 geomOK=0 立即可见，Pro 施工约束）。
    /// （(73) 轴向随形态由右缘/tx 改底缘/ty。）
    private func panelModelBottomEdge() -> CGFloat {
        let h = sidebarView.bounds.height
        return sidebarView.center.y - h / 2
            + sidebarView.bounds.applying(sidebarView.transform).maxY
    }

    /// 面板底缘（presentation：在途动画的呈现值；无呈现层
    /// 时回退 model）。与 model 分家即第三机制的实锤字段。
    private func panelPresentationBottomEdge() -> CGFloat {
        let h = sidebarView.bounds.height
        guard let pres = sidebarView.layer.presentation() else {
            return panelModelBottomEdge()
        }
        return pres.position.y - h / 2
            + sidebarView.bounds.applying(affine(from: pres.transform)).maxY
    }

    private func panelOpenGeom() -> Bool {
        panelModelBottomEdge() >= panelHeight - 0.5
    }

    // MARK: - 自证面包屑（workbench.chrome.audit）

    private static func fmt(_ v: CGFloat) -> String {
        String(format: "%.2f", Double(v))
    }

    /// 调用栈返回地址的 FNV-1a 哈希（audit 的 stackHash）：
    /// 只取地址不符号化，成本可忽略；同一写入点的哈希恒定，
    /// 判读时按哈希归组即可定位是哪条代码路径在写 chrome。
    private func stackHash() -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for address in Thread.callStackReturnAddresses {
            hash ^= UInt64(address.uintValue)
            hash &*= 0x100000001b3
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
    }

    private static func gestureStateName(_ state: UIGestureRecognizer.State) -> String {
        switch state {
        case .possible: return "possible"
        case .began: return "began"
        case .changed: return "changed"
        case .ended: return "ended"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        @unknown default: return "unknown"
        }
    }

    /// 手势真实状态：任一 pan 识别器处活跃态（began/changed）
    /// 时报其实时值；否则报最近一次回调记录的终结态。
    private func gestureRawStateDescription() -> String {
        let pans: [(String, UIPanGestureRecognizer?)] = [
            ("handle", handlePanGesture),
            ("sidebar", sidebarPanGesture),
            ("scrim", scrimPanGesture)
        ]
        for (name, pan) in pans {
            if let pan, pan.state == .began || pan.state == .changed {
                return "\(name):\(Self.gestureStateName(pan.state))"
            }
        }
        return lastGestureRawState
    }

    /// chrome 自证面包屑（(58) 定稿①）：每一次 chrome 写入后
    /// 落一行（拖动中段节流 20Hz，见 applyChrome）。字段全集
    /// ＝定罪映射：modelBottom 与 presBottom 分家→第三机制；
    /// drag=1 恒久而 gesture 已终结→B′；anim 非空且 gen 停
    /// 滞→A；落定末行 handleHidden/panelOpenGeom
    /// 两者须与真机截图逐条对得上（验收判据）。
    private func auditChrome(caller: String, progress: CGFloat? = nil) {
        let modelTy = sidebarView.transform.ty
        let presTy = sidebarView.layer.presentation()
            .map { CGFloat($0.transform.m42) } ?? modelTy
        let modelBottom = panelModelBottomEdge()
        let presBottom = panelPresentationBottomEdge()
        Breadcrumbs.log("workbench.chrome.audit"
            + " caller=\(caller) stack=\(stackHash())"
            + " state=\(sidebarStateName) gen=\(sidebarGeneration)"
            + " anim=\(animatorIdentity) animGen=\(animatorGeneration)"
            + " drag=\(isDraggingSidebar ? 1 : 0)"
            + " gesture=\(gestureRawStateDescription())"
            + (progress.map { " progress=\(Self.fmt($0))" } ?? "")
            + " handleHidden=\(handleView.isHidden ? 1 : 0)"
            + " handleAlpha=\(Self.fmt(handleView.alpha))"
            + " modelTy=\(Self.fmt(modelTy)) presTy=\(Self.fmt(presTy))"
            + " modelBottom=\(Self.fmt(modelBottom)) presBottom=\(Self.fmt(presBottom))"
            + " panelOpenGeom=\(modelBottom >= panelHeight - 0.5 ? 1 : 0)"
            + " geomOK=\(abs(modelBottom - (panelHeight + modelTy)) <= 0.5 ? 1 : 0)")
    }

    // MARK: - chrome 写入唯一通道（applyChrome）

    private enum ChromeMode {
        /// 途中型：只写 alpha（恒可见），供拖动/动画插值。
        case transient(CGFloat)
        /// 落定型：按状态机落定态硬藏/恢复（仅 open/closed 态
        /// 调用；其余态无操作但仍落 audit）。
        case settled
    }

    /// chrome（把手的 isHidden/alpha）写入的唯一通道
    /// （(58) 定稿① Pro 补正：手势回调与 animator 一律不许
    /// 直写 chrome）。每次写入后落 audit（拖动中段 caller=
    /// drag 时节流到 20Hz：写入本身不节流、只采样落行）。
    private func applyChrome(caller: String, mode: ChromeMode) {
        switch mode {
        case .transient(let progress):
            handleView.isHidden = false
            handleView.alpha = 1 - progress
            if caller == "drag" {
                let now = CACurrentMediaTime()
                guard now - lastDragAuditAt >= 0.05 else { return }
                lastDragAuditAt = now
            }
            auditChrome(caller: caller, progress: progress)
        case .settled:
            switch sidebarState {
            case .open:
                handleView.isHidden = true
            case .closed:
                handleView.isHidden = false
                handleView.alpha = 1
            case .dragging, .settling:
                break
            }
            auditChrome(caller: caller)
        }
    }

    // MARK: - 几何写入唯一通道（updateGeometry）

    /// 面板几何（transform）写入的唯一通道（(58) 定稿① Pro
    /// 补正）：按 generation 校验，过期代次的写入一律丢弃并
    /// 落 geomdrop 痕——旧 animator 即使残留引用也写不动面板。
    private func updateGeometry(ty: CGFloat, generation: Int, caller: String) {
        guard generation == sidebarGeneration else {
            Breadcrumbs.log("workbench.chrome.geomdrop caller=\(caller) gen=\(generation) current=\(sidebarGeneration)")
            return
        }
        sidebarView.transform = CGAffineTransform(translationX: 0, y: ty)
    }

    /// 面板进度唯一入口（(58) 定稿①，代旧 applySidebarProgress）：
    /// 手势回调与 animator 只许经此推进——内部依次写面板几
    /// 何（updateGeometry 按当前代次）、scrim alpha、chrome
    /// 途中型 alpha，全部派生自同一 progress。
    private func progressTransit(to progress: CGFloat, caller: String) {
        let clamped = min(max(progress, 0), 1)
        currentProgress = clamped
        updateGeometry(ty: -panelHeight * (1 - clamped),
                       generation: sidebarGeneration, caller: caller)
        scrimView.alpha = 0.5 * clamped
        applyChrome(caller: caller, mode: .transient(clamped))
    }

    // MARK: - 不变式自愈（Pro 门控）

    /// 不变式自愈（(58) 定稿①）：落定态下 chrome 显隐必须由
    /// 状态机唯一决定。启用门控（Pro 补正，三条齐备）：状态
    /// ∈{open,closed}、无在途 animator 正在写（或 model 位移
    /// 已达目标 0.5 内）、距最近迁移开始 ≥300ms。违规分两
    /// 型：chrome 型（显隐/alpha 与状态不符）→ 按落定型硬纠
    /// 正；几何型（面板 model 位移偏离落定位）→ 经
    /// updateGeometry 拉回。纠正必落 invariant.violation。
    private func enforceInvariant(caller: String) {
        guard sidebarState == .open || sidebarState == .closed else { return }
        let targetTy: CGFloat = sidebarState == .open ? 0 : -panelHeight
        let modelTy = sidebarView.transform.ty
        if sidebarAnimator != nil, abs(modelTy - targetTy) > 0.5 { return }
        guard CACurrentMediaTime() - lastTransitionBeginAt >= 0.3 else { return }
        // 几何型违规：落定态面板不在落定位（无 animator 在写
        // 的前提下到不了位，即写入通道外的改动/残局）。
        if abs(modelTy - targetTy) > 0.5 {
            Breadcrumbs.log("invariant.violation caller=\(caller) kind=geometry"
                + " state=\(sidebarStateName) modelTy=\(Self.fmt(modelTy))"
                + " targetTy=\(Self.fmt(targetTy)) panelOpenGeom=\(panelOpenGeom() ? 1 : 0)")
            currentProgress = sidebarState == .open ? 1 : 0
            updateGeometry(ty: targetTy, generation: sidebarGeneration,
                           caller: "invariant-heal")
        }
        // chrome 型违规：显隐/alpha 与落定态派生值不符（(61)
        // WA 删悬浮头像钮后 chrome 只剩把手一件）。
        let chromeViolated: Bool
        if sidebarState == .open {
            chromeViolated = !handleView.isHidden
        } else {
            chromeViolated = handleView.isHidden || handleView.alpha != 1
        }
        if chromeViolated {
            Breadcrumbs.log("invariant.violation caller=\(caller) kind=chrome"
                + " state=\(sidebarStateName)"
                + " handleHidden=\(handleView.isHidden ? 1 : 0)"
                + " panelOpenGeom=\(panelOpenGeom() ? 1 : 0)")
            applyChrome(caller: "invariant-heal", mode: .settled)
        }
    }

    // MARK: - 可见态发送对账（(55) 工作流 A 沿用）

    /// 与最近一次实际报出值相同则不重发。这样拖动 .began 抢
    /// 先报的 (true)、setSidebarOpen 开栏报的 (true)、收口补
    /// 报的 (false) 无论哪条路径先到，回调都只发一次，
    /// false/true 配平、末态恒与面板实际开关态一致。
    private func emitSidebarVisibility(_ visible: Bool, source: String) {
        guard reportedSidebarVisible != visible else {
            Breadcrumbs.log("workbench.sidebar.visibility dedup visible=\(visible) source=\(source)")
            return
        }
        reportedSidebarVisible = visible
        Breadcrumbs.log("workbench.sidebar.visibility visible=\(visible) source=\(source)")
        onSidebarVisibilityChanged?(visible)
    }

    // MARK: - 状态迁移（开/关发起与落定）

    /// 停掉在途 animator 并同步交付其 completion：走
    /// stopAnimation(false) 保留 completion、再
    /// finishAnimation(at: .current) 在当前位置交付——
    /// completion 凭「代次已递增或位置非 .end」自判失效、
    /// 只落 audit、不写 chrome/几何/状态（(55) A 的语义在本
    /// 版由状态机收编）。调用方须在本方法后递增代次或迁
    /// 状态，使旧 completion 的代次判据成立。
    private func stopCurrentAnimator() {
        guard let animator = sidebarAnimator else { return }
        sidebarAnimator = nil
        animatorIdentity = "-"
        animatorGeneration = -1
        animator.stopAnimation(false)
        animator.finishAnimation(at: .current)
    }

    /// 开/关发起（唯一入口）：停旧 animator → 代次递增 →
    /// 状态迁 settling → 按需建新弹簧 animator（或无动画直
    /// 达落定）。animator 的 animations 只经 progressTransit
    /// 写，completion 凭代次＋位置双判据落定。
    private func beginTransition(toOpen open: Bool, animated: Bool,
                                 reason: String, initialVelocityY: CGFloat) {
        stopCurrentAnimator()
        sidebarGeneration += 1
        let gen = sidebarGeneration
        intentOpen = open
        sidebarState = .settling(generation: gen, targetOpen: open)
        lastTransitionBeginAt = CACurrentMediaTime()
        Breadcrumbs.log("workbench.sidebar.\(open ? "open" : "close") reason=\(reason) gen=\(gen)")
        if open {
            scrimView.isHidden = false
            refreshAccountUI()
            emitSidebarVisibility(true, source: "set-open")
        }
        let targetProgress: CGFloat = open ? 1 : 0
        let targetTy = -panelHeight * (1 - targetProgress)
        let currentTy = sidebarView.transform.ty
        guard animated, !UIAccessibility.isReduceMotionEnabled,
              abs(targetTy - currentTy) > 0.5 else {
            progressTransit(to: targetProgress, caller: "settle-immediate")
            settleSidebar(generation: gen, targetOpen: open, caller: "immediate")
            return
        }
        let distance = targetTy - currentTy
        let relativeVelocity = distance != 0
            ? min(max(initialVelocityY / distance, -3), 3) : 0
        let timing = UISpringTimingParameters(
            dampingRatio: 0.86,
            initialVelocity: CGVector(dx: 0, dy: relativeVelocity))
        let animator = UIViewPropertyAnimator(duration: 0.55, timingParameters: timing)
        animator.addAnimations { [weak self] in
            self?.progressTransit(to: targetProgress, caller: "animator")
        }
        animator.addCompletion { [weak self] position in
            guard let self else { return }
            guard gen == self.sidebarGeneration else {
                // 过期代次的 completion：只落 audit 定罪，不许
                // 写 chrome/几何/状态（定稿①代次失效）。
                self.auditChrome(caller: "animator-completion-stale")
                return
            }
            self.sidebarAnimator = nil
            self.animatorIdentity = "-"
            self.animatorGeneration = -1
            if position == .end {
                self.settleSidebar(generation: gen, targetOpen: open,
                                   caller: "animator-completion")
            } else {
                // 被打断（.current/.start）：接管方（拖动/新迁
                // 移）负责后续，本处只记账。
                self.auditChrome(caller: "animator-completion-interrupted")
            }
        }
        sidebarAnimator = animator
        animatorIdentity = "\(ObjectIdentifier(animator).hashValue)"
        animatorGeneration = gen
        animator.startAnimation()
    }

    /// 落定（唯一收口）：状态迁 open/closed → scrim 收尾 →
    /// chrome 落定型派生 → 可见态补报 → 落定 audit ＋
    /// +300ms 双通道自证 → 不变式核对。代次不符的落定一律
    /// 丢弃（过期收口不许动任何东西）。
    private func settleSidebar(generation gen: Int, targetOpen open: Bool, caller: String) {
        guard gen == sidebarGeneration else {
            auditChrome(caller: "settle-stale")
            return
        }
        sidebarState = open ? .open : .closed
        if open {
            scrimView.isHidden = false
            // 对账补报：正常路径 (true) 已在开栏时发出、此处
            // 被去重吞掉；仅当前面发送丢失时在此补齐。
            emitSidebarVisibility(true, source: "finish-open")
        } else {
            scrimView.isHidden = true
            scrimView.alpha = 0
            // 关闭落定才恢复墙交互；经对账发送，与守卫补收
            // 口、动画 completion 哪条先到都只发一次。
            emitSidebarVisibility(false, source: "finish-close")
        }
        applyChrome(caller: "settle-\(caller)", mode: .settled)
        scheduleSettleAudits()
        enforceInvariant(caller: "settle-\(caller)")
    }

    /// 落定自证双通道（(58) 定稿①）：落定行之外，下一
    /// runloop 一行＋300ms 后一行——主线程卡死吞掉定时行时，
    /// 「定时行迟到/缺失」本身即证据；+300ms 行同时再核一次
    /// 不变式（此时 300ms 门控必已满足）。
    private func scheduleSettleAudits() {
        DispatchQueue.main.async { [weak self] in
            self?.auditChrome(caller: "settle+runloop")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.auditChrome(caller: "settle+300ms")
            self.enforceInvariant(caller: "settle+300ms")
        }
    }

    /// 守卫命中时的补收口：目标态已落定且面板已在目标位，
    /// 不等于「什么都不用做」——把面板按现态再钉一次并走
    /// 落定收口，保证 chrome 显隐与墙交互回调必达末态
    /// （(55) A 定案在本版的落点）。
    private func reconcileSettledSidebar(open: Bool, reason: String) {
        stopCurrentAnimator()
        Breadcrumbs.log("workbench.sidebar.reconcile open=\(open) reason=\(reason)")
        progressTransit(to: open ? 1 : 0, caller: "reconcile")
        settleSidebar(generation: sidebarGeneration, targetOpen: open, caller: "reconcile")
    }

    func setSidebarOpen(_ open: Bool, animated: Bool, reason: String,
                        initialVelocityY: CGFloat = 0) {
        // 守卫：目标态已落定且面板已在目标位才算同值；同值
        // 不许整段 return 吞掉收口——先补一次落定收口再返回
        // （(55) 工作流 A 定案：在途 animator 被拖动打断时
        // completion 已丢，硬藏 chrome 与 (false) 发送全押在
        // 收口上，吞掉即冻屏/冻墙）。拖动松手时面板还在途
        // 中（状态为 dragging），不走守卫、继续收口。
        let targetTy: CGFloat = open ? 0 : -panelHeight
        let settledTarget: SidebarState = open ? .open : .closed
        if sidebarState == settledTarget,
           abs(sidebarView.transform.ty - targetTy) <= 0.5 {
            reconcileSettledSidebar(open: open, reason: reason)
            return
        }
        // 已在向同一目标 settling：不重启（防重复请求叠代次、
        // 把在途弹簧打断成跳变）。
        if case .settling(_, let target) = sidebarState, target == open {
            return
        }
        beginTransition(toOpen: open, animated: animated,
                        reason: reason, initialVelocityY: initialVelocityY)
    }

    // MARK: - 开合手势

    @objc private func handleTapped() {
        setSidebarOpen(true, animated: true, reason: "handle-tap")
    }

    @objc private func scrimTapped() {
        setSidebarOpen(false, animated: true, reason: "scrim-tap")
    }

    @objc private func handlePanned(_ gesture: UIPanGestureRecognizer) {
        // 把手只从关闭侧起拖（与旧版 guard !isSidebarOpen 等
        // 价）：已开/正在开途中不受理。
        switch sidebarState {
        case .open, .settling(_, true):
            return
        case .closed, .dragging, .settling(_, false):
            break
        }
        dragSidebar(gesture, opening: true)
    }

    @objc private func sidebarPanned(_ gesture: UIPanGestureRecognizer) {
        // 面板/遮罩只从打开侧起拖（与旧版 guard isSidebarOpen
        // 等价）：已关/正在关途中不受理。
        switch sidebarState {
        case .closed, .settling(_, false):
            return
        case .open, .dragging, .settling(_, true):
            break
        }
        dragSidebar(gesture, opening: false)
    }

    /// 跟手拖动：把手下拖开、面板/遮罩上拖关（(73) 轴向改
    /// 竖向）；松手按速度与进度用系统弹簧收口到开/关。
    /// .began 时停旧 animator、代次递增、状态迁 dragging 并
    /// 启动看门狗；终结（ended/cancelled/failed 同路）经
    /// beginTransition 收口——手势 cancel 也是定稿①的强制
    /// 点位（走同一落定路径）。
    private func dragSidebar(_ gesture: UIPanGestureRecognizer, opening: Bool) {
        let height = panelHeight
        // 双指边缘防抢：dragging 期间只有 owner 识别器能推进/
        // 终结本次拖动（另一识别器的 .began 直接忽略）。
        if case .dragging = sidebarState,
           gesture.state != .possible,
           dragOwner != nil, dragOwner != ObjectIdentifier(gesture) {
            return
        }
        lastGestureRawState = "\(opening ? "handle" : "panel"):\(Self.gestureStateName(gesture.state))"
        switch gesture.state {
        case .began:
            lastGestureEventAt = CACurrentMediaTime()
            watchdogHoldLogged = false
            dragOwner = ObjectIdentifier(gesture)
            stopCurrentAnimator()
            sidebarGeneration += 1
            sidebarState = .dragging
            lastTransitionBeginAt = CACurrentMediaTime()
            scrimView.isHidden = false
            if opening { emitSidebarVisibility(true, source: "drag-began") }
            auditChrome(caller: "drag-began")
            startDragWatchdog()
        case .changed:
            lastGestureEventAt = CACurrentMediaTime()
            let translation = gesture.translation(in: self).y
            let base: CGFloat = opening ? -height : 0
            let ty = min(max(base + translation, -height), 0)
            progressTransit(to: height > 0 ? 1 + ty / height : 0, caller: "drag")
        case .ended, .cancelled, .failed:
            lastGestureEventAt = CACurrentMediaTime()
            dragOwner = nil
            stopDragWatchdog()
            let velocity = gesture.velocity(in: self).y
            let targetOpen: Bool
            if velocity > 350 { targetOpen = true }
            else if velocity < -350 { targetOpen = false }
            else { targetOpen = currentProgress > 0.45 }
            auditChrome(caller: "drag-end")
            beginTransition(toOpen: targetOpen, animated: true,
                            reason: "drag", initialVelocityY: velocity)
        default:
            break
        }
    }

    // MARK: - 拖动态看门狗（500ms，Pro 补正）

    private func startDragWatchdog() {
        stopDragWatchdog()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.dragWatchdogTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        dragWatchdog = timer
    }

    private func stopDragWatchdog() {
        dragWatchdog?.invalidate()
        dragWatchdog = nil
    }

    /// 看门狗 tick（100ms）：与手势真实状态交叉核对——任一
    /// 识别器仍处 began/changed（用户按住面板静止不动也是
    /// 合法拖动）时绝不迁出、只落一行 audit（每次拖一行）；
    /// 全部识别器已终结/未始且 500ms 无手势事件，即终结事
    /// 件被吞（B′ 形态、状态机还卡在 dragging、自愈在拖动态
    /// 又被禁用）——强制迁出 settling 并落 invariant.drag.idle。
    private func dragWatchdogTick() {
        guard case .dragging = sidebarState else {
            stopDragWatchdog()
            return
        }
        guard CACurrentMediaTime() - lastGestureEventAt >= 0.5 else { return }
        let anyActive = [handlePanGesture, sidebarPanGesture, scrimPanGesture]
            .contains { $0?.state == .began || $0?.state == .changed }
        if anyActive {
            if !watchdogHoldLogged {
                watchdogHoldLogged = true
                auditChrome(caller: "watchdog-hold")
            }
            return
        }
        Breadcrumbs.log("invariant.drag.idle progress=\(Self.fmt(currentProgress)) gesture=\(gestureRawStateDescription())")
        stopDragWatchdog()
        dragOwner = nil
        beginTransition(toOpen: currentProgress > 0.45, animated: true,
                        reason: "drag-watchdog", initialVelocityY: 0)
    }

    // MARK: - 账户区（B 组 ProviderSessionStatusQuery，签名见报告）

    private func providerDisplayName(_ provider: NativeSessionStore.Provider) -> String {
        switch provider {
        case .netease: return "网易云"
        case .qq: return "QQ 音乐"
        case .kugou: return "酷狗"
        }
    }

    /// 同步读三家会话状态刷新头像区（无网络、主线程直调）。
    /// 在安装、每次开侧栏、登录成功后各刷一次。
    func refreshAccountUI() {
        let statuses = ProviderSessionStatusQuery.allStatuses()
        let loggedIn = statuses.filter(\.isLoggedIn)
        Breadcrumbs.log("workbench.account.refresh loggedIn=\(loggedIn.map { $0.provider.rawValue }.joined(separator: ","))")
        // 主展示：第一家已登录的昵称；都没有则网易云口径的「未登录」。
        if let primary = loggedIn.first, let name = primary.displayName, !name.isEmpty {
            accountNameLabel.text = name
        } else if loggedIn.isEmpty {
            accountNameLabel.text = "未登录"
        } else {
            accountNameLabel.text = "已登录"
        }
        accountHintLabel.text = loggedIn.isEmpty ? "点按扫码登录" : "点按管理登录"
        for status in statuses {
            let label = providerLabels[status.provider]
            if status.isLoggedIn {
                let name = status.displayName.flatMap { $0.isEmpty ? nil : $0 }
                label?.text = "\(providerDisplayName(status.provider)) · \(name ?? "已登录")"
            } else {
                label?.text = "\(providerDisplayName(status.provider)) · 未登录"
            }
            // 状态点贴本行行首（行视图自带点，见 buildScrimAndSidebar），
            // 按本家登录态着色，不再借头像上的点。
            providerDots[status.provider]?.backgroundColor = status.isLoggedIn
                ? UIColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1)
                : UIColor.white.withAlphaComponent(0.35)
        }
        // 头像：第一家已登录且有头像的；状态点：任一家已登录为亮。
        // （(61) WA：悬浮头像钮已删，只剩侧栏内 sidebarAvatar 一只；
        // 取数路径不变——ProviderSessionStatusQuery 同步读资料缓存，
        // avatarURL 来自 NativeSessionStore.saveProfile 落盘值。）
        let avatarStatus = loggedIn.first { $0.avatarURL != nil } ?? statuses.first { $0.avatarURL != nil }
        let anyLoggedIn = !loggedIn.isEmpty
        sidebarAvatar.setLoggedIn(anyLoggedIn)
        // 占位每次刷新都重算（不许挂在头像加载键变化的分支里：
        // 昵称后到、头像 URL 不变时旧版永远不更新占位）。
        let fallbackName = loggedIn.first?.displayName ?? statuses.first?.displayName
        sidebarAvatar.setFallback(name: fallbackName, hasImage: avatarStatus?.avatarURL != nil)
        let key = avatarStatus?.avatarURL?.absoluteString
        if key != avatarLoadKey {
            avatarLoadKey = key
            let expectedKey = key
            WorkbenchCover.loadAvatar(url: avatarStatus?.avatarURL, into: sidebarAvatar.imageView) { [weak self] in
                self?.avatarLoadKey == expectedKey
            }
        }
    }

    @objc private func accountTapped() {
        presentLogin()
    }

    private func presentLogin() {
        guard let presenter = hostViewController else { return }
        Breadcrumbs.log("workbench.account.openLogin")
        if isSidebarOpen { setSidebarOpen(false, animated: true, reason: "login") }
        let login = LoginViewController()
        login.modalPresentationStyle = .overFullScreen
        login.onLoginSuccess = { [weak self] in
            Breadcrumbs.log("workbench.account.loginSuccess")
            self?.refreshAccountUI()
        }
        presenter.present(login, animated: true)
    }

    // MARK: - 分区呈现（DS 结论 4：从 HomeWall 现有 present 能力发出）

    private func openSection(_ section: WorkbenchSection) {
        guard let presenter = hostViewController else { return }
        Breadcrumbs.log("workbench.open section=\(section.rawValue)")
        setSidebarOpen(false, animated: true, reason: "section")
        switch section {
        case .guide:
            // (73) 导播台：Ponder62 导览列表面（章节化导览，
            // 条目与落点见 Ponder62.chapters）。
            Ponder62.presentList(from: presenter)
        case .search:
            SearchHostPresenter.presentSearch(from: presenter)
        case .settings:
            let settings = SettingsViewController()
            settings.modalPresentationStyle = .overFullScreen
            presenter.present(settings, animated: false)
        case .playlists:
            presentSectionVC(WorkbenchPlaylistListViewController(), from: presenter)
        case .albums:
            presentSectionVC(WorkbenchAlbumListViewController(), from: presenter)
        case .radio:
            presentSectionVC(WorkbenchRadioViewController(), from: presenter)
        case .local:
            presentSectionVC(WorkbenchLocalViewController(), from: presenter)
        }
    }

    private func presentSectionVC(_ vc: WorkbenchSectionViewController,
                                  from presenter: UIViewController) {
        vc.dismissToWall = { [weak presenter] in
            presenter?.dismiss(animated: true)
        }
        vc.modalPresentationStyle = .fullScreen
        presenter.present(vc, animated: true)
    }
}

/// 工作台分区标识（面包屑 workbench.open 的 section 值）。
enum WorkbenchSection: String {
    case playlists
    case radio
    case search
    case albums
    case local
    case settings
    /// (73) 导播台（台内灯泡行，非分区页）。
    case guide
}

/// 圆形头像小件：图 + 无图时昵称首字兜底（没昵称时人形图标
/// 占位，诚实空态，不许「?」糊脸）+ 登录状态点。
final class WorkbenchAvatarView: UIView {

    let imageView = UIImageView()
    private let fallbackLabel = UILabel()
    private let placeholderIcon = UIImageView()
    private let dotView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        fallbackLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        fallbackLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        fallbackLabel.textAlignment = .center
        fallbackLabel.isHidden = true
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallbackLabel)
        placeholderIcon.image = UIImage(systemName: "person.crop.circle.fill")
        placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.45)
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderIcon)
        dotView.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        dotView.layer.cornerRadius = 4
        dotView.layer.borderWidth = 1.5
        dotView.layer.borderColor = UIColor.black.withAlphaComponent(0.6).cgColor
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallbackLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            fallbackLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 22),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 22),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),
            dotView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            dotView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.layer.cornerRadius = bounds.width / 2
    }

    func setLoggedIn(_ loggedIn: Bool) {
        dotView.backgroundColor = loggedIn
            ? UIColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1)
            : UIColor.white.withAlphaComponent(0.35)
    }

    func setFallback(name: String?, hasImage: Bool) {
        if hasImage {
            fallbackLabel.text = nil
            fallbackLabel.isHidden = true
            placeholderIcon.isHidden = true
        } else if let first = name?.first {
            fallbackLabel.text = String(first)
            fallbackLabel.isHidden = false
            placeholderIcon.isHidden = true
        } else {
            // 无图又无昵称：人形图标占位（数据未到的诚实空态）。
            fallbackLabel.text = nil
            fallbackLabel.isHidden = true
            placeholderIcon.isHidden = false
        }
    }
}
