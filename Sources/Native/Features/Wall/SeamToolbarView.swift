import UIKit

/// 缝合工具条的数据段（3.7 (55) 工作流 E）：歌＝用户歌单墙
/// （默认、本体既有数据）；推＝每日推荐歌单（/recommend/
/// resource，歌单形条目、与墙条目模型同构）；探＝探索歌曲
/// 流（每日推荐歌曲 /recommend/songs ＋ 私人 FM /personal_
/// fm，曲目形条目、点按走队列起播）。三段都真接既有数据
/// 通路（NativeDataClient+Workbench），无假段控。
enum SeamSegment: Int, CaseIterable {
    case songs
    case recommend
    case explore

    var title: String {
        switch self {
        case .songs: return "歌"
        case .recommend: return "推"
        case .explore: return "探"
        }
    }

    var crumbName: String {
        switch self {
        case .songs: return "songs"
        case .recommend: return "recommend"
        case .explore: return "explore"
        }
    }
}

/// 主页墙缝合工具条（3.7 (55) 工作流 E）：骑在主页墙顶部
/// 安全区下的一条毛玻璃浮动条，按网页版缝合工具条语义适配
/// 原生墙：歌/推/探三段切换、账户头像（点开登录页）、搜索
/// （SearchWorkspaceView）、设置（SettingsViewController）、
/// 布局钮（网格 ⇄ Bravais 墙）、「…」菜单钮、全屏钮（iOS
/// 无窗口全屏——宿主落为沉浸模式，见 HomeWall 接线）。
///
/// 与侧栏共存口径：账户/搜索/设置与侧栏是双入口并存（同一
/// 目标页、同一登录态显示），不互斥；侧栏打开时本条随墙一
/// 起被侧栏宿主覆盖（宿主层级在上），本条不新造避让。
///
/// 本视图只管呈现与回调分发，数据与呈现目标页全在宿主
/// （HomeWallViewController 的 seam 接线段）。
///
/// 双态（3.7 (60) 第 2 条）：收起态只显示一根白色小横线
/// （36×4pt 圆角 grabber，居中于本条顶部带内，沿用宿主现
/// 安装约束）；点横线以系统弹簧（damping≈0.8）展开全条；
/// 展开后无操作 3.5s 自动收回（任一钮点按重置计时）。展开/
/// 收起只动 transform/alpha，不重排墙面。沉浸模式整条隐藏
/// 的现行逻辑保留、横线同藏（见 setImmersiveHidden）。
/// (86) 第 3/4 条改版：grabber 横线整件撤除（(85) 图五
/// 定案的残留小白线即此线身）——收起态只剩常驻头像＋
/// 不可见展开命中垫（原垫原位）；头像双态恒可见可点。
///
/// 绕岛形态（3.7 (75) 第 3 项，Miller 2026-11-23 20:29/
/// 20:31 点名）：(74) 的直条悬在岛下方、与岛毫无关系被
/// 否。本形态下宿主把本条钉到屏幕顶边全宽（top=0），条
/// 体顶带绕灵动岛：背景顶沿切出凹口包住岛（岛几何与
/// PetIslandLayer 同源：半宽 63、底 48，凹口每侧留 8pt
/// 缝、底留 8pt），内容行落到凹口下方（contentRowTop 由
/// 宿主按本页顶部家具定），收起横线落在岛左近、与岛同
/// 高——条就住在岛那一层高度。横屏宿主改走 (74) 安全区
/// 侧锚约束（岛在侧边），本形态以 bounds 宽<高判定、横
/// 向自动不生效。命中纪律：收起态只认横线命中垫、展开
/// 态只认内容控件，带内空域一律穿透（高带不吞页面点按）。
///
/// (76) 热修（Miller 21:43 录屏否决 (75) 形态）：(75) 的
/// 凹口是 even-odd mask 镂空＋分离描边两条闭合子路径，
/// 且收起时带身随内容组 alpha 归零消失、只剩孤线浮在
/// 砖上——「没画出来」。本版改：带身是一条画出来的带，
/// 单一连续轮廓（顶边下切 r8 fillet → 岛胶囊 +3pt 偏
/// 移弧绕底 → 镜像上行）由毛玻璃 mask／色调填充／描边
/// 三层共用；带身恒可见，收起时形变（CASpring 弹簧）
/// 成贴岛薄框（带底 60），横线落在左臂带身上；展开同
/// 路径形变回全高。几何取值见 bandOutlinePath 处常数。
/// (75) 绕岛背景描边层载体：layer 本体即 CAShapeLayer，
/// 只描边不填充，路径与背景 mask 同源（外轮廓＋凹口）。
private final class SeamShapeBorderView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }
    var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }
}

final class SeamToolbarView: UIView {

    var onSegmentChanged: ((SeamSegment) -> Void)?
    /// (71) 数据段尾「拼」格（队列拼贴）：动作格非数据段——
    /// 点按走本回调 present 队列墙，选中态立即回弹当前数据段。
    var onLatticeTapped: (() -> Void)?
    var onAvatarTapped: (() -> Void)?
    var onSearchTapped: (() -> Void)?
    var onSettingsTapped: (() -> Void)?
    /// (74) 导播台入口（小灯泡）：(73) 工作台大台撤除后
    /// Ponder62 导览入口改挂本条，宿主接 presentList。
    var onGuideTapped: (() -> Void)?
    var onLayoutTapped: (() -> Void)?
    // (77) ④「…」菜单整页取消（Miller 23:02）：moreButton 与
    // WallMoreMenu 一并摘除，连带功能去向见 (77) 报告④。
    var onFullscreenTapped: (() -> Void)?

    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let avatarButton = UIButton(type: .system)
    private let avatarInitial = UILabel()
    /// 头像照片图位（(61) WA 4③）：圆形裁剪、盖在 avatarButton
    /// 之上；无图时透明，露出按钮自身的首字/人形兜底。
    private let avatarImageView = UIImageView()
    /// 头像加载防串图键（当前 URL 串；回调落地前比对，照侧栏同款）。
    private var avatarLoadKey: String?
    /// (78) 第 3 条：占位字图层约束（摘除/挂回时整组开关）。
    private var avatarInitialConstraints: [NSLayoutConstraint] = []
    /// 数据段三段 + (71)「拼」动作格（队列拼贴入口）。
    private let segmentControl = UISegmentedControl(
        items: SeamSegment.allCases.map { $0.title } + ["拼"])
    private let searchButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let guideButton = UIButton(type: .system)
    private let layoutButton = UIButton(type: .system)
    private let fullscreenButton = UIButton(type: .system)

    // 双态（(60) 第 2 条）：收起态承接点按的命中垫（(61)
    // WA 由全条 44pt 全宽带收窄到 76×28，收起态不吞整条
    // 带的墙面点按）、闲置收起计时。
    // (86) 第 4 条：36×4 白色 grabber 横线整件撤除（(85)
    // 图五定案：缝折叠态侧边残留的「小白线」即此线身；
    // (85) 撤的是速记簿把手、此线从未撤过）。命中垫保留
    // 原位原尺寸、改名 expandHitView（无可见绘制），点按
    // 展开通路不变；落 toolbar86 见证。
    // (86) 第 3 条：收起态头像常驻可见可点（见
    // applyToolbarState 的头像豁免与 hitTest 放行）。
    private let expandHitView = UIView()
    private var idleCollapseWorkItem: DispatchWorkItem?
    private(set) var isToolbarExpanded = false

    private(set) var segment: SeamSegment = .songs

    // MARK: - (75) 绕岛形态

    /// 宿主开启（钉顶边全宽时置 true）；实际生效还须
    /// bounds 为竖向（layoutSubviews 判定，横屏自动回落）。
    var wrapIslandEnabled = false
    /// 绕岛态内容行顶在本条内的 y（宿主按本页顶部家具定：
    /// 主页 54＝凹口底 56 上沿贴行、歌单页/舞台按其页眉行
    /// 下沿）。非绕岛态忽略（行 = 全高）。
    var contentRowTop: CGFloat = 54
    /// (78) 第 4 条：平形态内容行顶（缺省 0＝旧行为）。主页
    /// 恒为平形态（带宽>高、wrap 不生效），旧口径行带＝全
    /// 高、控件行心落在带心（104 带心 52）——分段控件上沿
    /// 37 与岛底 48 纵向交叠且横向压进岛左段，Miller 真机
    /// 点名「贴着灵动岛干涉」。主页宿主置 30：行心下移至
    /// 67，分段上沿 52、头像上沿 51，与岛底拉开 3–4pt 间
    /// 距。仅主页宿主赋值，其余宿主恒 0 不动。
    var flatRowTop: CGFloat = 0
    /// 内容行布局带：内容控件的 centerY 全部锚到本带，绕
    /// 岛态带落到凹口下方、平形态带 = 全高（与旧 centerY
    /// 锚本条中心等价）。
    private let rowGuide = UILayoutGuide()
    private var rowTopConstraint: NSLayoutConstraint?
    private var rowHeightConstraint: NSLayoutConstraint?
    /// 绕岛态背景描边（与 mask 同路径 stroke；平形态由
    /// blurView 自带 border 承担、本层隐藏）。
    private let borderView = SeamShapeBorderView()
    /// (76) 带身色调填充层：与描边/mask 同一连续轮廓路径
    /// 的深色半透明填充（载体同 SeamShapeBorderView）。
    private let bandTintView = SeamShapeBorderView()
    private let maskShapeLayer = CAShapeLayer()
    /// (76) 布局尺寸变更面包屑去重（闪屏审计关连用）。
    private var lastLayoutSize: CGSize = .zero
    private var expandHitLeadingConstraint: NSLayoutConstraint?
    private var expandHitCenterYConstraint: NSLayoutConstraint?
    private var wrapActiveNow = false
    /// 灵动岛几何（iPhone 14 Pro 实测口径，与 PetIslandLayer
    /// 同源常量）：半宽 63、顶 11、底 48、中心 y≈29.5。
    private static let islandHalfWidth: CGFloat = 63
    private static let islandBottom: CGFloat = 48
    private static let islandCenterY: CGFloat = 29.5

    /// 全条内容视图组（双态只动这组的 alpha/transform）。
    private var contentViews: [UIView] {
        [blurView, avatarButton, avatarInitial, avatarImageView, segmentControl,
         searchButton, settingsButton, guideButton, layoutButton,
         fullscreenButton]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        blurView.layer.cornerRadius = 22
        blurView.layer.borderWidth = 1
        blurView.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // (76) 带身色调层：垫在毛玻璃之上、描边之下。同一
        // 连续轮廓的深色半透明填充保证亮封面之上带身仍可
        // 读——(75) 只靠 mask 镂空毛玻璃＋分离描边，亮底上
        // 带身近乎不可见，是「没画出来」的成因之一。
        bandTintView.isUserInteractionEnabled = false
        bandTintView.isHidden = true
        bandTintView.shapeLayer.fillColor =
            UIColor.black.withAlphaComponent(0.22).cgColor
        bandTintView.shapeLayer.strokeColor = UIColor.clear.cgColor
        bandTintView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bandTintView)
        NSLayoutConstraint.activate([
            bandTintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bandTintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bandTintView.topAnchor.constraint(equalTo: topAnchor),
            bandTintView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // (75) 绕岛描边层：垫在背景之上、内容之下，初始隐
        // 藏（平形态走 blurView 自带 border）。
        borderView.isUserInteractionEnabled = false
        borderView.isHidden = true
        borderView.shapeLayer.fillColor = UIColor.clear.cgColor
        borderView.shapeLayer.strokeColor =
            UIColor.white.withAlphaComponent(0.25).cgColor
        borderView.shapeLayer.lineWidth = 1
        borderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(borderView)
        NSLayoutConstraint.activate([
            borderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            borderView.topAnchor.constraint(equalTo: topAnchor),
            borderView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // (75) 内容行布局带（见 rowGuide 注释）。
        addLayoutGuide(rowGuide)
        let rowTop = rowGuide.topAnchor.constraint(equalTo: topAnchor)
        let rowHeight = rowGuide.heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            rowGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowTop, rowHeight,
        ])
        rowTopConstraint = rowTop
        rowHeightConstraint = rowHeight

        // 头像：圆形底 + 昵称首字（登录态由宿主回填）；未登录
        // 显示 person 符号。与侧栏头像同一登录态口径。
        avatarButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        avatarButton.layer.cornerRadius = 16
        avatarButton.clipsToBounds = true
        avatarButton.accessibilityLabel = "账户"
        avatarButton.translatesAutoresizingMaskIntoConstraints = false
        avatarButton.setImage(UIImage(systemName: "person.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13)), for: .normal)
        avatarButton.tintColor = .white
        avatarButton.addTarget(self, action: #selector(avatarTapped), for: .touchUpInside)
        addSubview(avatarButton)
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 16
        avatarImageView.isUserInteractionEnabled = false
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarImageView)
        avatarInitial.font = .systemFont(ofSize: 14, weight: .semibold)
        avatarInitial.textColor = .white
        avatarInitial.textAlignment = .center
        avatarInitial.isUserInteractionEnabled = false
        avatarInitial.isHidden = true
        avatarInitial.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarInitial)

        segmentControl.selectedSegmentIndex = SeamSegment.songs.rawValue
        segmentControl.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.28)
        segmentControl.setTitleTextAttributes(
            [.foregroundColor: UIColor.white.withAlphaComponent(0.65),
             .font: UIFont.systemFont(ofSize: 13, weight: .medium)], for: .normal)
        segmentControl.setTitleTextAttributes(
            [.foregroundColor: UIColor.white,
             .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
        segmentControl.translatesAutoresizingMaskIntoConstraints = false
        segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        addSubview(segmentControl)

        configureIcon(searchButton, symbol: "magnifyingglass", label: "搜索",
                      action: #selector(searchTapped))
        configureIcon(settingsButton, symbol: "gearshape", label: "设置",
                      action: #selector(settingsTapped))
        configureIcon(guideButton, symbol: "lightbulb", label: "导播台",
                      action: #selector(guideTapped))
        configureIcon(layoutButton, symbol: "square.grid.2x2", label: "切换布局",
                      action: #selector(layoutTapped))
        configureIcon(fullscreenButton, symbol: "arrow.up.left.and.arrow.down.right",
                      label: "沉浸模式", action: #selector(fullscreenTapped))

        NSLayoutConstraint.activate([
            avatarButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            avatarButton.centerYAnchor.constraint(equalTo: rowGuide.centerYAnchor),
            avatarButton.widthAnchor.constraint(equalToConstant: 32),
            avatarButton.heightAnchor.constraint(equalToConstant: 32),
            avatarInitial.centerXAnchor.constraint(equalTo: avatarButton.centerXAnchor),
            avatarInitial.centerYAnchor.constraint(equalTo: avatarButton.centerYAnchor),
            avatarImageView.centerXAnchor.constraint(equalTo: avatarButton.centerXAnchor),
            avatarImageView.centerYAnchor.constraint(equalTo: avatarButton.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),

            segmentControl.leadingAnchor.constraint(equalTo: avatarButton.trailingAnchor, constant: 8),
            segmentControl.centerYAnchor.constraint(equalTo: rowGuide.centerYAnchor),
            // (74) 宽度账：加导播台灯泡后六钮并排，分段由
            // 132 收至 104、图标钮 36 收至 33，整条内容
            // 6+32+8+104+4+6×33+4 = 356pt，竖屏 369 可用
            // 宽内成立；横屏更宽不顶。
            // (77) ④：「…」钮摘除腾出 33pt，分段等量放宽
            // 104→137（四格均宽 ≈34），总账不变仍 356pt。
            segmentControl.widthAnchor.constraint(equalToConstant: 137),
            segmentControl.heightAnchor.constraint(equalToConstant: 30),

            searchButton.leadingAnchor.constraint(equalTo: segmentControl.trailingAnchor, constant: 4),
            settingsButton.leadingAnchor.constraint(equalTo: searchButton.trailingAnchor),
            guideButton.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor),
            layoutButton.leadingAnchor.constraint(equalTo: guideButton.trailingAnchor),
            fullscreenButton.leadingAnchor.constraint(equalTo: layoutButton.trailingAnchor),
            fullscreenButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
        for button in [searchButton, settingsButton, guideButton, layoutButton, fullscreenButton] {
            NSLayoutConstraint.activate([
                button.centerYAnchor.constraint(equalTo: rowGuide.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 33),
                button.heightAnchor.constraint(equalToConstant: 44),
            ])
        }

        // (86) 第 4 条：展开命中垫（原 grabber 命中垫原位
        // 保留：76×28、leading+2、垂直居中本条；线身已撤、
        // 本垫无任何可见绘制），仅收起态在场，点按即展开。
        // (75) 约束改存引用：绕岛态由 layoutSubviews 按岛
        // 几何改写常数（移到岛左近、与岛同高），平形态恢
        // 复本组数值。
        expandHitView.backgroundColor = .clear
        expandHitView.accessibilityLabel = "展开工具条"
        expandHitView.accessibilityTraits = .button
        expandHitView.translatesAutoresizingMaskIntoConstraints = false
        expandHitView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(expandHitTapped)))
        addSubview(expandHitView)
        let hLead = expandHitView.leadingAnchor.constraint(
            equalTo: leadingAnchor, constant: 2)
        let hCY = expandHitView.centerYAnchor.constraint(equalTo: centerYAnchor)
        expandHitLeadingConstraint = hLead
        expandHitCenterYConstraint = hCY
        NSLayoutConstraint.activate([
            hLead, hCY,
            expandHitView.widthAnchor.constraint(equalToConstant: 76),
            expandHitView.heightAnchor.constraint(equalToConstant: 28),
        ])
        // 初始态 = 收起（头像常驻、无可见线），无动画直接落位。
        applyToolbarState(expanded: false, animated: false, reason: "init")
    }

    // MARK: - (75) 绕岛几何（布局期判定，常数只在变化时写）

    override func layoutSubviews() {
        super.layoutSubviews()
        // (76) 闪屏审计关连埋点：布局尺寸真变更才落痕，
        // 下轮日志可与点按时刻对位（ morph 中途有无重排）。
        if bounds.size != lastLayoutSize {
            if lastLayoutSize != .zero {
                Breadcrumbs.log("seam.morph76 lay w=\(Int(bounds.width))"
                    + " h=\(Int(bounds.height))")
            }
            lastLayoutSize = bounds.size
        }
        let wrap = wrapIslandEnabled && bounds.width > 0
            && bounds.width < bounds.height
        if wrap != wrapActiveNow {
            wrapActiveNow = wrap
            // (77) ①：带身只存于绕岛收起态（贴岛薄框）；
            // 展开态与平形态下面板面恒透明（控件直接浮
            // 墙面），alpha 归带身组统一管（见
            // applyToolbarState），此处只做形态切换落位。
            let bandAlpha: CGFloat = (wrap && !isToolbarExpanded) ? 1 : 0
            blurView.alpha = bandAlpha
            bandTintView.alpha = bandAlpha
            borderView.alpha = bandAlpha
            blurView.transform = .identity
            Breadcrumbs.log("seam.wrap75 \(wrap ? "on" : "off")"
                + " row=\(Int(contentRowTop))")
        }
        // 内容行带：绕岛态落到凹口下方；平形态 = 全高减去
        // 宿主下挪量 flatRowTop（(78) 第 4 条，仅主页非 0）。
        // 下挪只对高带成立：横屏带高 44 时行顶再下挪会把控
        // 件推出带外——带高 <80 自动回落 0（横屏几何与旧版
        // 一字不变，(78) 适配自查抓到的问题）。
        let flatTop = bounds.height >= 80 ? flatRowTop : 0
        let targetTop: CGFloat = wrap ? contentRowTop : flatTop
        let targetHeight: CGFloat = wrap ? 44
            : max(44, bounds.height - flatTop)
        if rowTopConstraint?.constant != targetTop {
            rowTopConstraint?.constant = targetTop
        }
        if rowHeightConstraint?.constant != targetHeight {
            rowHeightConstraint?.constant = targetHeight
        }
        // 背景形态：绕岛态三层（毛玻璃 mask／色调填充／描
        // 边）共用 (76) 单一连续轮廓路径。(77) ①③：带底
        // 恒为收起薄框 60——展开态带身整组淡出（全透明），
        // 路径不再随双态形变（CASpring 路径形变摘除，见
        // applyToolbarState 的 seam.flash77）；平形态回
        // blurView 圆角＋自带 border（但 alpha 恒 0、不出面）。
        if wrap {
            let bottom = Self.slimBandBottom
            let path = Self.bandOutlinePath(width: bounds.width,
                                            bottom: bottom)
            maskShapeLayer.frame = bounds
            maskShapeLayer.path = path
            if blurView.layer.mask !== maskShapeLayer {
                blurView.layer.mask = maskShapeLayer
            }
            blurView.layer.cornerRadius = 0
            blurView.layer.borderWidth = 0
            bandTintView.shapeLayer.path = path
            bandTintView.isHidden = false
            borderView.shapeLayer.path = path
            borderView.isHidden = false
        } else {
            if blurView.layer.mask != nil { blurView.layer.mask = nil }
            blurView.layer.cornerRadius = 22
            blurView.layer.borderWidth = 1
            bandTintView.isHidden = true
            borderView.isHidden = true
        }
        // 命中垫对位：绕岛态落岛左近（与岛同高居中）；平
        // 形态回左锚行内位（(86) 线身撤除后只剩垫的常数）。
        if wrap {
            let islandLeft = bounds.width / 2 - Self.islandHalfWidth
            let cy = Self.islandCenterY - bounds.height / 2
            if expandHitLeadingConstraint?.constant != islandLeft - 70 {
                expandHitLeadingConstraint?.constant = islandLeft - 70
            }
            if expandHitCenterYConstraint?.constant != cy {
                expandHitCenterYConstraint?.constant = cy
            }
        } else {
            if expandHitLeadingConstraint?.constant != 2 {
                expandHitLeadingConstraint?.constant = 2
            }
            if expandHitCenterYConstraint?.constant != 0 {
                expandHitCenterYConstraint?.constant = 0
            }
        }
    }

    // MARK: - (76) 凹口几何（画出来的带、单一连续轮廓）

    /// 间隙：凹口轮廓与岛胶囊之间恒 3pt——偏移弧与岛弧
    /// 同心（圆心同为 (±44.5, 29.5)）、半径差恰 3；顶
    /// fillet 与其切点邻域间隙 ≥3（fillet 圆在偏移弧外侧
    /// 相切接入）。
    private static let notchGap: CGFloat = 3
    /// 凹口半宽 = 岛半宽 63 + 间隙 3。
    private static let notchHalf: CGFloat = 66
    /// 凹口底 = 岛底 48 + 间隙 3。
    private static let notchBottom: CGFloat = 51
    /// 凹口弧半径 = 岛胶囊半径 18.5 + 间隙 3。
    private static let notchArcR: CGFloat = 21.5
    /// 凹口弧圆心横偏移 = 岛半宽 63 − 岛胶囊半径 18.5。
    private static let notchArcDX: CGFloat = 44.5
    /// 顶边下切 fillet 半径（凹角平滑过渡）。
    private static let notchFilletR: CGFloat = 8
    /// 收起态带底：凹口底 51 + 9 底衬 = 60——带身收成贴
    /// 岛薄框、整带仍画在屏上，横线（中心高 29.5）落在
    /// 左臂带身上、不再是浮在砖上的孤线。
    private static let slimBandBottom: CGFloat = 60

    /// (76) 绕岛带轮廓：单一连续路径一条到底——顶边自左
    /// 行至岛左 → r8 凹 fillet 平滑下切 → 沿岛胶囊 +3pt
    /// 偏移弧（r21.5）绕过岛底 → 右侧镜像上行回顶边 →
    /// 续行至右缘 → 下行 → 底角 r22 → 底边 → 左缘闭合。
    /// 不是 mask 镂空＋分离描边（(75) 形态被否）：填充、
    /// 色调、描边三层共用本路径，凹口是轮廓本身的凹部。
    /// bottom = 带底 y（展开 = 本条高、收起 = 60）；命令
    /// 序列与 bottom 无关、恒定同构，故两态路径可由
    /// CASpringAnimation 直接形变插值（形变衔接、非跳变）。
    private static func bandOutlinePath(width w: CGFloat,
                                        bottom h: CGFloat) -> CGPath {
        let cx = w / 2
        let r: CGFloat = 22
        let f = notchFilletR, ar = notchArcR, adx = notchArcDX
        let cy = islandCenterY, nb = notchBottom
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: cx - adx - f, y: 0))
        p.addArc(withCenter: CGPoint(x: cx - adx - f, y: f), radius: f,
                 startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        p.addArc(withCenter: CGPoint(x: cx - adx, y: cy), radius: ar,
                 startAngle: -.pi / 2, endAngle: .pi / 2,
                 clockwise: false)
        p.addLine(to: CGPoint(x: cx + adx, y: nb))
        p.addArc(withCenter: CGPoint(x: cx + adx, y: cy), radius: ar,
                 startAngle: .pi / 2, endAngle: -.pi / 2,
                 clockwise: false)
        p.addArc(withCenter: CGPoint(x: cx + adx + f, y: f), radius: f,
                 startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addArc(withCenter: CGPoint(x: w - r, y: h - r), radius: r,
                 startAngle: 0, endAngle: .pi / 2, clockwise: true)
        p.addLine(to: CGPoint(x: r, y: h))
        p.addArc(withCenter: CGPoint(x: r, y: h - r), radius: r,
                 startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        p.close()
        return p.cgPath
    }

    /// 命中纪律（(75)）：展开态只认内容控件（super 命中
    /// 到本视图/背景即空域、穿透）。高带（绕岛态 100pt+）
    /// 绝不整带吞页面点按。
    /// (86) 第 3/4 条：收起态两路放行——①头像命中区（头
    /// 像常驻可见可点，(85) 定案双态门挡死点头像定位的
    /// 修法）；②展开命中垫（原 grabber 垫、无可见线）。
    /// 其余空域仍穿透给墙面（全带吞触摸会吃掉墙面顶部
    /// 平移/点按，故不采「点工具条区域任意处」字面义，
    /// 命中区＝原垫原位，报告注明）。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01 else { return nil }
        if isToolbarExpanded {
            let hit = super.hitTest(point, with: event)
            return (hit === self || hit === blurView) ? nil : hit
        }
        if avatarButton.frame.contains(point) { return avatarButton }
        return expandHitView.frame.contains(point) ? expandHitView : nil
    }

    // MARK: - 双态（(60) 第 2 条）

    @objc private func expandHitTapped() {
        // (76) 闪屏审计埋点：点按时刻落痕，与 morph/lay
        // 面包屑同轴对位（点按前后各帧状态可复原）。
        Breadcrumbs.log("seam.morph76 tap")
        // (86) 第 4 条：无痕展开入口见证（线身撤除后展开
        // 入口的存活自证）。
        Breadcrumbs.log("toolbar86 hit=expand")
        expandToolbar(reason: "tap")
    }

    func expandToolbar(reason: String) {
        guard !isToolbarExpanded else { scheduleIdleCollapse(); return }
        isToolbarExpanded = true
        Breadcrumbs.log("seam.toolbar expand reason=\(reason)")
        applyToolbarState(expanded: true, animated: true, reason: reason)
        scheduleIdleCollapse()
    }

    func collapseToolbar(reason: String) {
        guard isToolbarExpanded else { return }
        isToolbarExpanded = false
        idleCollapseWorkItem?.cancel()
        idleCollapseWorkItem = nil
        Breadcrumbs.log("seam.toolbar collapse reason=\(reason)")
        applyToolbarState(expanded: false, animated: true, reason: reason)
    }

    /// 沉浸模式（宿主 seamSetImmersive 调用）：整条隐藏；退
    /// 出沉浸回到收起态（头像＋展开命中垫在场，(86) 无线身）。
    func setImmersiveHidden(_ on: Bool) {
        if on {
            idleCollapseWorkItem?.cancel()
            idleCollapseWorkItem = nil
            if isToolbarExpanded {
                isToolbarExpanded = false
                Breadcrumbs.log("seam.toolbar collapse reason=immersive")
                applyToolbarState(expanded: false, animated: false, reason: "immersive")
            }
        }
        isHidden = on
    }

    /// 任一钮点按 = 有操作：重置 3.5s 闲置收回计时。
    private func noteToolbarInteraction() {
        guard isToolbarExpanded else { return }
        scheduleIdleCollapse()
    }

    private func scheduleIdleCollapse() {
        idleCollapseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.collapseToolbar(reason: "idle")
        }
        idleCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private func applyToolbarState(expanded: Bool, animated: Bool, reason: String) {
        expandHitView.isHidden = expanded
        // (77) ①③（Miller 22:58/23:02）：展开面全透明——
        // 带身组（毛玻璃/色调/描边）只在绕岛收起态以贴岛
        // 薄框存在，展开即整组淡出、控件直接浮墙面；平
        // 形态两态皆无面。形变改走与内容组同一条系统弹
        // 簧的 alpha 交叉淡化：(76) 的 CASpring 路径形变
        // （对带 mask 的 UIVisualEffectView 逐帧改 mask
        // 路径）是设置台点按闪屏的头号静态嫌疑，本版整
        // 组摘除（证据链与定级见 (77) 报告③）。
        if wrapActiveNow {
            Breadcrumbs.log("seam.morph76 \(expanded ? "exp" : "col")"
                + " anim=\(animated ? 1 : 0)")
        }
        // (78) 第 2 条见证修复（定案：条件挡住）：(77) 的
        // seam.flash77 与 morph76 exp/col 同被 wrapActiveNow
        // 一门挡住——(77) 真机日志里两者双双 0 次、wrap75
        // on/off 亦 0 次，而主页工具条恒为平形态（实测 lay
        // 尺寸 393×104、宽>高，wrap 判定恒假），见证埋进了
        // 永不执行的分支、(77) 闪屏修法等于无证上路。本版
        // 改无条件落 seam.flash78（带形态位 wrap=）：init 的
        // applyToolbarState 调用同经此地，每条工具条建成即
        // 有一行，站点存活自证。
        Breadcrumbs.log("seam.flash78 wrap=\(wrapActiveNow ? 1 : 0)"
            + " exp=\(expanded ? 1 : 0) anim=\(animated ? 1 : 0)")
        let apply = { [self] in
            for view in contentViews {
                if view === blurView { continue }
                // (86) 第 3 条：头像三件豁免双态淡出——收起
                // 态常驻可见（与 hitTest 头像放行成对，点头
                // 像定位不再被双态门挡死）。
                if view === avatarButton || view === avatarInitial
                    || view === avatarImageView { continue }
                view.alpha = expanded ? 1 : 0
            }
            let bandAlpha: CGFloat = (wrapActiveNow && !expanded) ? 1 : 0
            blurView.alpha = bandAlpha
            bandTintView.alpha = bandAlpha
            borderView.alpha = bandAlpha
            // (86) 第 4 条：grabber 线身已整件撤除，本行随之
            // 退役（展开命中垫的显隐在函数首行 isHidden 管）。
        }
        let setInteraction = { [self] in
            for view in contentViews where view !== blurView && view !== avatarInitial
                && view !== avatarImageView && view !== avatarButton {
                view.isUserInteractionEnabled = expanded
            }
            // (86) 第 3 条：头像收起态恒可交互（与 alpha 豁
            // 免成对）；3.5s 自动收回只收其余控件、头像点
            // 击不再被吞。
            avatarButton.isUserInteractionEnabled = true
        }
        if animated {
            setInteraction()
            UIView.animate(withDuration: 0.45, delay: 0,
                           usingSpringWithDamping: 0.8, initialSpringVelocity: 0.2,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: apply) { [weak self] _ in
                guard let self, self.isToolbarExpanded == expanded else { return }
                Breadcrumbs.log("seam.morph76 done st=\(expanded ? 1 : 0)")
                setInteraction()
            }
        } else {
            apply()
            setInteraction()
        }
        _ = reason
    }

    private func configureIcon(_ button: UIButton, symbol: String, label: String,
                               action: Selector) {
        button.setImage(UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)),
            for: .normal)
        button.tintColor = UIColor.white.withAlphaComponent(0.9)
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        addSubview(button)
    }

    // MARK: - 宿主回填

    /// 段同步（宿主侧回滚/恢复时用，不触发回调）。
    func setSegment(_ newSegment: SeamSegment) {
        segment = newSegment
        segmentControl.selectedSegmentIndex = newSegment.rawValue
    }

    // MARK: - (62) 骑墙缝弹性形态

    private var seamElasticAnimator62: UIViewPropertyAnimator?

    /// 骑墙缝弹性跟随（(62) §1）：宿主滚动时以内容偏移调用，
    /// 本条以欠阻尼弹簧把偏移的 30% 化为纵向弹性位移（钳
    /// ±10pt），停滚后宿主以 0 调用回弹归位。只动 transform，
    /// 不改约束与七路回调。接线在宿主滚动 delegate（WA 文件
    /// 域）——本 API 为 WD 提供面，宿主未接时不生效（报告标注）。
    func applySeamElasticOffset(_ offset: CGFloat) {
        let target = max(-10, min(10, offset * 0.3))
        seamElasticAnimator62?.stopAnimation(true)
        let animator = UIViewPropertyAnimator(
            duration: 0.55,
            timingParameters: UISpringTimingParameters(
                dampingRatio: 0.55, initialVelocity: CGVector(dx: 0, dy: 0.4)))
        animator.addAnimations { [weak self] in
            self?.transform = CGAffineTransform(translationX: 0, y: target)
        }
        seamElasticAnimator62 = animator
        animator.startAnimation()
    }

    /// 布局钮图标随当前形态：网格态显示墙形符号、反之网格。
    func setLayoutMode(grid: Bool) {
        layoutButton.setImage(UIImage(systemName: grid ? "rectangle.3.group" : "square.grid.2x2",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)),
            for: .normal)
        layoutButton.accessibilityLabel = grid ? "切换为照片墙布局" : "切换为网格布局"
    }

    /// 登录态回填：已登录显示昵称首字，未登录回 person 符号
    /// （与侧栏账户头同一口径：双入口、同一登录态显示）。
    /// (61) WA 4③：avatarURLString 有值时用 WorkbenchCover
    /// .loadAvatar 加载真头像（圆形图位盖在兜底之上、带 key
    /// 防串图，照侧栏同款）；无值/加载未回时回退现行首字/
    /// person.fill 逻辑。参数带默认值 nil，旧调用点源码兼容。
    /// (78) 第 3 条：占位字图层挂回（登录无图/换图加载中才
    /// 需要它在场）。约束首次摘除前从本视图约束表里捞出存
    /// 档，挂回时整组重新激活。
    private func attachAvatarInitialIfNeeded() {
        guard avatarInitial.superview == nil else { return }
        addSubview(avatarInitial)
        NSLayoutConstraint.activate(avatarInitialConstraints)
    }

    /// (78) 第 3 条：占位字图层整层摘除——真头像图已落地时
    /// 调用，removeFromSuperview 连图带层一起走，不是改透
    /// 明度（(77) 真机实证：图已显示、字还压在图上）。
    private func detachAvatarInitial() {
        guard avatarInitial.superview != nil else { return }
        if avatarInitialConstraints.isEmpty {
            avatarInitialConstraints = constraints.filter {
                ($0.firstItem as? UIView) == avatarInitial
                    || ($0.secondItem as? UIView) == avatarInitial
            }
        }
        NSLayoutConstraint.deactivate(avatarInitialConstraints)
        avatarInitial.removeFromSuperview()
    }

    func setAccount(nickname: String?, loggedIn: Bool, avatarURLString: String? = nil) {
        if loggedIn, let first = nickname?.first {
            attachAvatarInitialIfNeeded()
            avatarInitial.text = String(first)
            avatarInitial.isHidden = false
            avatarButton.setImage(nil, for: .normal)
        } else {
            avatarInitial.isHidden = true
            avatarButton.setImage(UIImage(systemName: "person.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13)), for: .normal)
        }
        let key = (loggedIn ? avatarURLString : nil).flatMap { $0.isEmpty ? nil : $0 }
        guard key != avatarLoadKey else {
            // 同键重入：图已在位则占位字保持摘除，防回填复活。
            if avatarImageView.image != nil { detachAvatarInitial() }
            return
        }
        avatarLoadKey = key
        guard let key, let url = URL(string: key) else {
            avatarImageView.image = nil
            return
        }
        let expectedKey = key
        WorkbenchCover.loadAvatar(url: url, into: avatarImageView,
            completion: { [weak self] success in
                // 真图落地即整层摘除占位字（(78) 第 3 条）。
                guard let self, success,
                      self.avatarLoadKey == expectedKey else { return }
                self.detachAvatarInitial()
            },
            isCurrent: { [weak self] in
                self?.avatarLoadKey == expectedKey
            })
        // 缓存同步命中在 loadAvatar 返回前已置图（completion
        // 亦已同步回调），此处兜底再核一次，双路都摘干净。
        if avatarImageView.image != nil { detachAvatarInitial() }
        Breadcrumbs.log("seam.toolbar avatar load")
    }

    // MARK: - 动作

    @objc private func segmentChanged() {
        // (71)「拼」格（下标 = 数据段数）：动作格——选中态回弹
        // 当前数据段（程序赋值不触发 .valueChanged、无递归），
        // 只分发 present 回调，数据段状态一字不动。
        if segmentControl.selectedSegmentIndex == SeamSegment.allCases.count {
            segmentControl.selectedSegmentIndex = segment.rawValue
            noteToolbarInteraction()
            Breadcrumbs.log("seam.lattice")
            onLatticeTapped?()
            return
        }
        guard let selected = SeamSegment(rawValue: segmentControl.selectedSegmentIndex) else { return }
        segment = selected
        noteToolbarInteraction()
        onSegmentChanged?(selected)
    }

    @objc private func avatarTapped() { noteToolbarInteraction(); onAvatarTapped?() }
    @objc private func searchTapped() { noteToolbarInteraction(); onSearchTapped?() }
    @objc private func settingsTapped() { noteToolbarInteraction(); onSettingsTapped?() }
    @objc private func guideTapped() {
        noteToolbarInteraction()
        Breadcrumbs.log("seam.guide tap")
        onGuideTapped?()
    }
    @objc private func layoutTapped() {
        noteToolbarInteraction()
        InteractionTrace.shared.beginAction("layout")
        onLayoutTapped?()
    }
    @objc private func fullscreenTapped() {
        noteToolbarInteraction()
        InteractionTrace.shared.beginAction("immersive")
        onFullscreenTapped?()
    }
}

// MARK: - 歌单页转发（(62) 追加三：导航台进歌单）
//
// 歌单墙（WallPrototype）与歌单详情（CollectionView）顶部装
// 同款 SeamToolbarView。其动作语义与主页逐项一致、且都作用
// 于主页墙（切段/布局/沉浸是主页墙的状态，搜索/设置/登录是
// 主页为宿主的呈现）：点按后先关本面回到主页，再调主页既有
// 的 seam 动作实现，不在歌单面内另造一份行为。

extension UIView {
    /// 响应链上最近的视图控制器（SwiftUI 宿主定位用）。
    func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let vc = current as? UIViewController { return vc }
            responder = current.next
        }
        return nil
    }
}

enum SeamToolbarForwarding {

    /// 从呈现链/窗口根定位主页墙。
    static func findHomeWall(from vc: UIViewController) -> HomeWallViewController? {
        var cursor: UIViewController? = vc
        while let current = cursor {
            if let home = current as? HomeWallViewController { return home }
            if let home = searchDeep(current.children) { return home }
            cursor = current.presentingViewController
        }
        if let root = vc.view.window?.rootViewController {
            if let home = root as? HomeWallViewController { return home }
            return searchDeep([root])
        }
        return nil
    }

    private static func searchDeep(_ vcs: [UIViewController]) -> HomeWallViewController? {
        for vc in vcs {
            if let home = vc as? HomeWallViewController { return home }
            if let found = searchDeep(vc.children) { return found }
            if let presented = vc.presentedViewController,
               let found = searchDeep([presented]) { return found }
        }
        return nil
    }

    /// 视图点按入口（SwiftUI 包装层用）：先定位宿主 VC。
    static func activate(_ action: String, from view: UIView) {
        guard let host = view.nearestViewController() else {
            Breadcrumbs.log("seam.forward action=\(action) host=none")
            return
        }
        forward(action, from: host)
    }

    // MARK: - (75) 第 7 项：全局面就地展开

    /// 全局面动作集：设置/账户（扫码登录在账户卡内）/搜索/
    /// 导播台——这些面与主页墙状态无关，任何页面点开都须
    /// 在本页就地呈现，不许先关本页弹回主页（Miller 20:42
    /// 点名：歌单页点设置被弹回主页再开是错的）。只有主页
    /// 墙状态动作（segment-*/lattice/layout/fullscreen/
    /// more）才许走 forward 关页转发。
    static func isGlobalAction(_ action: String) -> Bool {
        ["settings", "avatar", "search", "guide"].contains(action)
    }

    /// 就地呈现全局面（调用方先以 isGlobalAction 把关）。
    /// 返回 true = 已就地处理；false = 非全局面、调用方应
    /// 走 forward。呈现参数与主页 perform 同款（设置＝
    /// SettingsViewController overFullScreen；账户卡＝
    /// popover 锚本面工具条头像位、卡内登录走卡自有弹层；
    /// 搜索/导播台＝各自呈现器从本面发出）。关掉后回到本
    /// 面原位（呈现栈原样压在本面之上、dismiss 即回）。
    @discardableResult
    static func performInPlace(_ action: String,
                               from vc: UIViewController,
                               toolbar: SeamToolbarView?) -> Bool {
        switch action {
        case "settings":
            Breadcrumbs.log("seam.inplace75 action=settings"
                + " host=\(String(describing: type(of: vc)))")
            let settings = SettingsViewController()
            settings.modalPresentationStyle = .overFullScreen
            vc.present(settings, animated: false)
        case "avatar":
            Breadcrumbs.log("seam.inplace75 action=avatar"
                + " host=\(String(describing: type(of: vc)))")
            let card = AccountCard62ViewController()
            card.modalPresentationStyle = .popover
            card.onLoginSuccess = { [weak toolbar] in
                if let toolbar { applyAccountState(to: toolbar) }
            }
            card.onSessionChanged = { [weak toolbar] in
                if let toolbar { applyAccountState(to: toolbar) }
            }
            if let pop = card.popoverPresentationController {
                pop.sourceView = toolbar ?? vc.view
                pop.sourceRect = CGRect(x: 6, y: 6, width: 32, height: 32)
                pop.permittedArrowDirections = [.up]
            }
            vc.present(card, animated: true)
        case "search":
            Breadcrumbs.log("seam.inplace75 action=search"
                + " host=\(String(describing: type(of: vc)))")
            SearchHostPresenter.presentSearch(from: vc)
        case "guide":
            Breadcrumbs.log("seam.inplace75 action=guide"
                + " host=\(String(describing: type(of: vc)))")
            Ponder62.presentList(from: vc)
        default:
            return false
        }
        return true
    }

    /// 视图点按的全局面入口（SwiftUI 包装层用）：定位宿主
    /// VC 后就地呈现，锚点即工具条本体。
    static func activateGlobal(_ action: String, from view: UIView) {
        guard let host = view.nearestViewController() else {
            Breadcrumbs.log("seam.inplace75 action=\(action) host=none")
            return
        }
        performInPlace(action, from: host, toolbar: view as? SeamToolbarView)
    }

    /// 关本面回主页并执行主页工具条同名动作。关闭走当前面
    /// 自己的 dismiss 通路（曲目墙的 StageExitGate veto 拦截
    /// 不被绕过）；关后主页之上若仍有残余呈现层，再补一发
    /// home.dismiss 清干净后执行。
    static func forward(_ action: String, from vc: UIViewController) {
        Breadcrumbs.log("seam.forward action=\(action)"
            + " from=\(String(describing: type(of: vc)))")
        guard let home = findHomeWall(from: vc), home !== vc else {
            vc.dismiss(animated: true)
            return
        }
        vc.dismiss(animated: true) {
            if home.presentedViewController != nil {
                home.dismiss(animated: false) {
                    perform(action, on: home)
                }
            } else {
                perform(action, on: home)
            }
        }
    }

    private static func perform(_ action: String, on home: HomeWallViewController) {
        switch action {
        case "segment-songs": home.seamSegmentSelected(.songs)
        case "segment-recommend": home.seamSegmentSelected(.recommend)
        case "segment-explore": home.seamSegmentSelected(.explore)
        case "avatar": home.seamAvatarTapped()
        case "search":
            Breadcrumbs.log("wall.seam.search")
            SearchHostPresenter.presentSearch(from: home)
        case "settings":
            Breadcrumbs.log("wall.seam.settings")
            let settings = SettingsViewController()
            settings.modalPresentationStyle = .overFullScreen
            home.present(settings, animated: false)
        case "guide":
            // (74) 导播台：导览列表自带呈现面，从主页发出
            // （与原工作台 .guide 行同一落点）。
            Breadcrumbs.log("seam.guide forward")
            Ponder62.presentList(from: home)
        case "lattice":
            // (74) 补接「拼」格转发（此前歌单面工具条未接此
            // 回调）：回主页后走统一落点 present 队列拼贴。
            Breadcrumbs.log("seam.lattice forward")
            QueueLatticeViewController.present(from: home)
        case "layout": home.seamToggleLayout()
        case "fullscreen": home.seamSetImmersive(true)
        default: break
        }
    }

    /// 工具条账户态（与主页 seamRefreshAccount 的同步缓存段
    /// 同源同口径：ProviderSessionStatusQuery 第一家已登录且
    /// 有头像者优先）；网络刷新归主页，本面只读缓存。
    static func applyAccountState(to bar: SeamToolbarView) {
        let statuses = ProviderSessionStatusQuery.allStatuses()
        let loggedIn = statuses.filter(\.isLoggedIn)
        let avatarStatus = loggedIn.first { $0.avatarURL != nil }
            ?? statuses.first { $0.avatarURL != nil }
        bar.setAccount(
            nickname: loggedIn.first?.displayName,
            loggedIn: !loggedIn.isEmpty,
            avatarURLString: avatarStatus?.avatarURL?.absoluteString)
    }

    /// (86) 第 3 条：歌单缝头像同源回填（与工具条同一数
    /// 据口径、同一全局查询，不另开数据源）。
    static func applyAccountState(toSeam seam: PlaylistSeam85View) {
        let statuses = ProviderSessionStatusQuery.allStatuses()
        let loggedIn = statuses.filter(\.isLoggedIn)
        let avatarStatus = loggedIn.first { $0.avatarURL != nil }
            ?? statuses.first { $0.avatarURL != nil }
        seam.setAccount85(
            nickname: loggedIn.first?.displayName,
            loggedIn: !loggedIn.isEmpty,
            avatarURLString: avatarStatus?.avatarURL?.absoluteString)
    }
}
