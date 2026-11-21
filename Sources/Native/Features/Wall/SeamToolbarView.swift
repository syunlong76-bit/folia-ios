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
final class SeamToolbarView: UIView {

    var onSegmentChanged: ((SeamSegment) -> Void)?
    var onAvatarTapped: (() -> Void)?
    var onSearchTapped: (() -> Void)?
    var onSettingsTapped: (() -> Void)?
    var onLayoutTapped: (() -> Void)?
    /// 「…」点按：回调带本钮作 action sheet 的锚点。
    var onMoreTapped: ((UIView) -> Void)?
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
    private let segmentControl = UISegmentedControl(
        items: SeamSegment.allCases.map { $0.title })
    private let searchButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let layoutButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let fullscreenButton = UIButton(type: .system)

    // 双态（(60) 第 2 条）：grabber 横线 + 命中垫（收起态承接
    // 点按；(61) WA 由全条 44pt 全宽带收窄到线身＋适度外扩
    // 76×28 居中，收起态不再吞整条带的墙面点按）、闲置收起计时。
    private let grabberView = UIView()
    private let grabberHitView = UIView()
    private var idleCollapseWorkItem: DispatchWorkItem?
    private(set) var isToolbarExpanded = false

    private(set) var segment: SeamSegment = .songs

    /// 全条内容视图组（双态只动这组的 alpha/transform）。
    private var contentViews: [UIView] {
        [blurView, avatarButton, avatarInitial, avatarImageView, segmentControl,
         searchButton, settingsButton, layoutButton, moreButton,
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
        configureIcon(layoutButton, symbol: "square.grid.2x2", label: "切换布局",
                      action: #selector(layoutTapped))
        configureIcon(moreButton, symbol: "ellipsis", label: "更多",
                      action: #selector(moreTapped))
        configureIcon(fullscreenButton, symbol: "arrow.up.left.and.arrow.down.right",
                      label: "沉浸模式", action: #selector(fullscreenTapped))

        NSLayoutConstraint.activate([
            avatarButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            avatarButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarButton.widthAnchor.constraint(equalToConstant: 32),
            avatarButton.heightAnchor.constraint(equalToConstant: 32),
            avatarInitial.centerXAnchor.constraint(equalTo: avatarButton.centerXAnchor),
            avatarInitial.centerYAnchor.constraint(equalTo: avatarButton.centerYAnchor),
            avatarImageView.centerXAnchor.constraint(equalTo: avatarButton.centerXAnchor),
            avatarImageView.centerYAnchor.constraint(equalTo: avatarButton.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),

            segmentControl.leadingAnchor.constraint(equalTo: avatarButton.trailingAnchor, constant: 8),
            segmentControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            segmentControl.widthAnchor.constraint(equalToConstant: 108),
            segmentControl.heightAnchor.constraint(equalToConstant: 30),

            searchButton.leadingAnchor.constraint(equalTo: segmentControl.trailingAnchor, constant: 4),
            settingsButton.leadingAnchor.constraint(equalTo: searchButton.trailingAnchor),
            layoutButton.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor),
            moreButton.leadingAnchor.constraint(equalTo: layoutButton.trailingAnchor),
            fullscreenButton.leadingAnchor.constraint(equalTo: moreButton.trailingAnchor),
            fullscreenButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
        for button in [searchButton, settingsButton, layoutButton, moreButton, fullscreenButton] {
            NSLayoutConstraint.activate([
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 36),
                button.heightAnchor.constraint(equalToConstant: 44),
            ])
        }

        // grabber 横线（(60) 第 2 条）：36×4pt 白色圆角，居中于
        // 本条（宿主安装在安全区顶下方，位置口径不变）；命中垫
        // (61) WA 收窄为 76×28 居中于线身、仅收起态在场，点按即展开。
        grabberView.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        grabberView.layer.cornerRadius = 2
        grabberView.isUserInteractionEnabled = false
        grabberView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grabberView)
        grabberHitView.backgroundColor = .clear
        grabberHitView.accessibilityLabel = "展开工具条"
        grabberHitView.accessibilityTraits = .button
        grabberHitView.translatesAutoresizingMaskIntoConstraints = false
        grabberHitView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(grabberTapped)))
        addSubview(grabberHitView)
        NSLayoutConstraint.activate([
            grabberView.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabberView.centerYAnchor.constraint(equalTo: centerYAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 36),
            grabberView.heightAnchor.constraint(equalToConstant: 4),
            grabberHitView.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabberHitView.centerYAnchor.constraint(equalTo: centerYAnchor),
            grabberHitView.widthAnchor.constraint(equalToConstant: 76),
            grabberHitView.heightAnchor.constraint(equalToConstant: 28),
        ])
        // 初始态 = 收起（只剩横线），无动画直接落位。
        applyToolbarState(expanded: false, animated: false, reason: "init")
    }

    // MARK: - 双态（(60) 第 2 条）

    @objc private func grabberTapped() {
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

    /// 沉浸模式（宿主 seamSetImmersive 调用）：整条隐藏、横线
    /// 同藏；退出沉浸回到收起态（横线在场）。
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
        grabberHitView.isHidden = expanded
        let apply = { [self] in
            for view in contentViews {
                view.alpha = expanded ? 1 : 0
            }
            blurView.transform = expanded
                ? .identity
                : CGAffineTransform(scaleX: 0.92, y: 0.55)
            grabberView.alpha = expanded ? 0 : 1
        }
        let setInteraction = { [self] in
            for view in contentViews where view !== blurView && view !== avatarInitial
                && view !== avatarImageView {
                view.isUserInteractionEnabled = expanded
            }
        }
        if animated {
            setInteraction()
            UIView.animate(withDuration: 0.45, delay: 0,
                           usingSpringWithDamping: 0.8, initialSpringVelocity: 0.2,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: apply) { [weak self] _ in
                guard let self, self.isToolbarExpanded == expanded else { return }
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
    func setAccount(nickname: String?, loggedIn: Bool, avatarURLString: String? = nil) {
        if loggedIn, let first = nickname?.first {
            avatarInitial.text = String(first)
            avatarInitial.isHidden = false
            avatarButton.setImage(nil, for: .normal)
        } else {
            avatarInitial.isHidden = true
            avatarButton.setImage(UIImage(systemName: "person.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13)), for: .normal)
        }
        let key = (loggedIn ? avatarURLString : nil).flatMap { $0.isEmpty ? nil : $0 }
        guard key != avatarLoadKey else { return }
        avatarLoadKey = key
        guard let key, let url = URL(string: key) else {
            avatarImageView.image = nil
            return
        }
        let expectedKey = key
        WorkbenchCover.loadAvatar(url: url, into: avatarImageView) { [weak self] in
            self?.avatarLoadKey == expectedKey
        }
        Breadcrumbs.log("seam.toolbar avatar load")
    }

    // MARK: - 动作

    @objc private func segmentChanged() {
        guard let selected = SeamSegment(rawValue: segmentControl.selectedSegmentIndex) else { return }
        segment = selected
        noteToolbarInteraction()
        onSegmentChanged?(selected)
    }

    @objc private func avatarTapped() { noteToolbarInteraction(); onAvatarTapped?() }
    @objc private func searchTapped() { noteToolbarInteraction(); onSearchTapped?() }
    @objc private func settingsTapped() { noteToolbarInteraction(); onSettingsTapped?() }
    @objc private func layoutTapped() {
        noteToolbarInteraction()
        InteractionTrace.shared.beginAction("layout")
        onLayoutTapped?()
    }
    @objc private func moreTapped() { noteToolbarInteraction(); onMoreTapped?(moreButton) }
    @objc private func fullscreenTapped() {
        noteToolbarInteraction()
        InteractionTrace.shared.beginAction("immersive")
        onFullscreenTapped?()
    }
}

/// 「…」菜单（3.7 (55) 工作流 E）：五项——喜欢的音乐 /
/// 云盘 / 过滤当前页 / 管理隐藏 / 回到播放页。以 action
/// sheet 呈现（iPad/横屏经锚点 popover 落位），每次点开按
/// 当下状态现建：无队列时「回到播放页」置灰（UIAlertAction
/// .isEnabled = false），过滤激活时该项带状态文案。动作全
/// 部由宿主以闭包注入，本枚举只管菜单形态与面包屑词根。
enum WallMoreMenu {

    struct Actions {
        var liked: () -> Void
        var cloud: () -> Void
        var filter: () -> Void
        var manageHidden: () -> Void
        var backToStage: () -> Void
    }

    static func present(from host: UIViewController, anchor: UIView,
                        hasQueue: Bool, filterActive: Bool, actions: Actions) {
        Breadcrumbs.log("wall.menu.open hasQueue=\(hasQueue) filter=\(filterActive)")
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "喜欢的音乐", style: .default) { _ in
            Breadcrumbs.log("wall.menu.pick item=liked")
            actions.liked()
        })
        sheet.addAction(UIAlertAction(title: "云盘", style: .default) { _ in
            Breadcrumbs.log("wall.menu.pick item=cloud")
            actions.cloud()
        })
        sheet.addAction(UIAlertAction(
            title: filterActive ? "过滤当前页（已激活）" : "过滤当前页",
            style: .default) { _ in
            Breadcrumbs.log("wall.menu.pick item=filter")
            actions.filter()
        })
        sheet.addAction(UIAlertAction(title: "管理隐藏", style: .default) { _ in
            Breadcrumbs.log("wall.menu.pick item=hidden")
            actions.manageHidden()
        })
        let back = UIAlertAction(title: "回到播放页", style: .default) { _ in
            Breadcrumbs.log("wall.menu.pick item=stage")
            actions.backToStage()
        }
        back.isEnabled = hasQueue
        sheet.addAction(back)
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
            popover.permittedArrowDirections = [.up, .down]
        }
        host.present(sheet, animated: true)
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
        case "layout": home.seamToggleLayout()
        case "more": home.seamMoreTapped(anchor: home.view)
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
}
