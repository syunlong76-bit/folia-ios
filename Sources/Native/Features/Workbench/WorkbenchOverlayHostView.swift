import UIKit

// WorkbenchOverlayHostView.swift
//
// (53) A 组工作台浮层宿主（DS 对账结论 1–4 的落点）：
// 1. 不换 root、不建容器 VC——HomeWallViewController 仍是 root，
//    本视图只是叠在 HomeWall.view 上的浮层（HomeWall 侧仅在
//    viewDidLoad 末尾加装本宿主，墙画布/入场/点卡 route 零改动）。
// 2. 关闭态 hitTest 只认把手与头像两个极小命中区，其余全部
//    返回 nil 穿透给墙（平移/点卡/迷你台/齿轮/搜索照常）。
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

final class WorkbenchOverlayHostView: UIView {

    /// 呈现分区页的宿主（HomeWallViewController）。
    weak var hostViewController: UIViewController?
    /// 侧栏展开态变化（禁/恢复墙交互）：打开在动画开始即报，
    /// 关闭在动画完成才报（收起途中墙仍被滑出中的面板盖着）。
    var onSidebarVisibilityChanged: ((Bool) -> Void)?

    private(set) var isSidebarOpen = false
    private var isDraggingSidebar = false
    private var sidebarAnimator: UIViewPropertyAnimator?

    private let scrimView = UIView()
    private let sidebarView = UIView()
    private let handleView = UIView()
    private let handleChevron = UIImageView()
    private let avatarButton = WorkbenchAvatarView()

    // 侧栏内件
    private let sidebarAvatar = WorkbenchAvatarView()
    private let accountNameLabel = UILabel()
    private let accountHintLabel = UILabel()
    private let providerStack = UIStackView()
    private var providerLabels: [NativeSessionStore.Provider: UILabel] = [:]

    private var avatarLoadKey = ""

    private var panelWidth: CGFloat {
        bounds.width > 0 ? min(304, bounds.width * 0.84) : 304
    }

    init(hostViewController: UIViewController) {
        self.hostViewController = hostViewController
        super.init(frame: .zero)
        backgroundColor = .clear
        buildScrimAndSidebar()
        buildHandleAndAvatarButton()
        refreshAccountUI()
        Breadcrumbs.log("workbench.host.install")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - 构建

    private func buildScrimAndSidebar() {
        scrimView.backgroundColor = UIColor.black.withAlphaComponent(1)
        scrimView.alpha = 0
        scrimView.isHidden = true
        scrimView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(scrimTapped)))
        scrimView.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(sidebarPanned(_:))))
        addSubview(scrimView)

        sidebarView.backgroundColor = WorkbenchTheme.background
        sidebarView.layer.shadowColor = UIColor.black.cgColor
        sidebarView.layer.shadowOpacity = 0.45
        sidebarView.layer.shadowRadius = 24
        sidebarView.layer.shadowOffset = CGSize(width: 6, height: 0)
        sidebarView.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(sidebarPanned(_:))))
        addSubview(sidebarView)

        // —— 账户头（点按进登录页：未登录去登录、已登录去管理）——
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(accountTapped)))
        sidebarView.addSubview(header)
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
            header.topAnchor.constraint(equalTo: sidebarView.topAnchor),
            header.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            sidebarAvatar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            sidebarAvatar.topAnchor.constraint(equalTo: header.topAnchor, constant: 56),
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
        sidebarView.addSubview(providerStack)
        for provider in NativeSessionStore.Provider.allCases {
            let label = UILabel()
            label.font = .systemFont(ofSize: 12)
            label.textColor = WorkbenchTheme.secondary
            label.translatesAutoresizingMaskIntoConstraints = false
            providerStack.addArrangedSubview(label)
            providerLabels[provider] = label
        }
        NSLayoutConstraint.activate([
            providerStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            providerStack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 20),
            providerStack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -16)
        ])

        let divider = UIView()
        divider.backgroundColor = WorkbenchTheme.hairline
        divider.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: providerStack.bottomAnchor, constant: 16),
            divider.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 20),
            divider.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -20),
            divider.heightAnchor.constraint(equalToConstant: 1)
        ])

        // —— 分区行 ——
        let sectionsStack = UIStackView()
        sectionsStack.axis = .vertical
        sectionsStack.spacing = 4
        sectionsStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(sectionsStack)
        let sections: [(WorkbenchSection, String, String)] = [
            (.playlists, "music.note.list", "歌单"),
            (.radio, "radio", "电台"),
            (.search, "magnifyingglass", "搜索"),
            (.albums, "opticaldisc", "专辑"),
            (.local, "folder", "本地")
        ]
        for (section, icon, title) in sections {
            sectionsStack.addArrangedSubview(makeSectionRow(section: section, icon: icon, title: title))
        }
        NSLayoutConstraint.activate([
            sectionsStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 14),
            sectionsStack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 12),
            sectionsStack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -12)
        ])

        // —— 底部设置入口（只调起既有 SettingsViewController）——
        let settingsButton = makeSectionRow(section: .settings, icon: "gearshape", title: "设置")
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(settingsButton)
        NSLayoutConstraint.activate([
            settingsButton.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 12),
            settingsButton.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -12),
            settingsButton.bottomAnchor.constraint(equalTo: sidebarView.safeAreaLayoutGuide.bottomAnchor, constant: -14)
        ])
    }

    private func makeSectionRow(section: WorkbenchSection, icon: String, title: String) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon)
        config.imagePadding = 14
        config.imagePlacement = .leading
        config.title = title
        config.baseForegroundColor = WorkbenchTheme.primary
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14)
        let button = UIButton(type: .system)
        button.configuration = config
        button.tintColor = WorkbenchTheme.primary
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.contentHorizontalAlignment = .leading
        button.backgroundColor = WorkbenchTheme.rowFill
        button.layer.cornerRadius = 12
        button.accessibilityLabel = title
        button.addAction(UIAction { [weak self] _ in
            self?.openSection(section)
        }, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }

    private func buildHandleAndAvatarButton() {
        // 左缘离散把手：18×80 的小片，只它自己带手势（点按开、
        // 在把手上横拖跟手），不设全高边缘手势。
        handleView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        handleView.layer.cornerRadius = 9
        handleView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        handleView.layer.borderWidth = 1
        handleView.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        handleView.accessibilityLabel = "打开书库"
        handleView.isAccessibilityElement = true
        handleView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleTapped)))
        handleView.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(handlePanned(_:))))
        addSubview(handleView)
        handleChevron.image = UIImage(systemName: "chevron.right")
        handleChevron.tintColor = UIColor.white.withAlphaComponent(0.85)
        handleChevron.contentMode = .scaleAspectFit
        handleChevron.isUserInteractionEnabled = false
        handleChevron.translatesAutoresizingMaskIntoConstraints = false
        handleView.addSubview(handleChevron)
        NSLayoutConstraint.activate([
            handleChevron.centerXAnchor.constraint(equalTo: handleView.centerXAnchor),
            handleChevron.centerYAnchor.constraint(equalTo: handleView.centerYAnchor),
            handleChevron.widthAnchor.constraint(equalToConstant: 10),
            handleChevron.heightAnchor.constraint(equalToConstant: 16)
        ])

        // 命中由本宿主 hitTest 在关闭态直派（点中头像 frame 才
        // 把事件交回 super 分发落到这个 tap 手势上）。
        addSubview(avatarButton)
        avatarButton.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(avatarTapped)))
    }

    // MARK: - 布局（安全区/横竖屏：frame 全在 layoutSubviews 按当前 bounds 重算）

    override func layoutSubviews() {
        super.layoutSubviews()
        scrimView.frame = bounds
        let width = panelWidth
        sidebarView.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        sidebarView.layer.shadowPath = UIBezierPath(rect: sidebarView.bounds).cgPath
        // 非拖动/非动画时把关闭态位移对齐当前宽度（旋转后宽度变了要跟上）。
        if !isSidebarOpen, !isDraggingSidebar, sidebarAnimator == nil {
            sidebarView.transform = CGAffineTransform(translationX: -width, y: 0)
        } else if isSidebarOpen, !isDraggingSidebar, sidebarAnimator == nil {
            sidebarView.transform = .identity
        }
        handleView.frame = CGRect(x: 0, y: bounds.height * 0.36, width: 18, height: 80)
        let avatarSize: CGFloat = 40
        avatarButton.frame = CGRect(
            x: 10, y: safeAreaInsets.top + 50, width: avatarSize, height: avatarSize)
    }

    // MARK: - 命中仲裁（DS 结论 2/3）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if isSidebarOpen || isDraggingSidebar || sidebarAnimator != nil {
            // 展开（含动画/拖动中）：宿主整层接管——面板内走
            // super 分发，面板外落 scrim（点按关闭），墙与迷你
            // 台在此期间点不到（且墙交互已由回调禁用）。
            return super.hitTest(point, with: event) ?? scrimView
        }
        // 关闭态：只有头像与把手两个极小命中区，其余穿透给墙。
        if avatarButton.frame.contains(point) {
            return super.hitTest(point, with: event)
        }
        if handleView.frame.contains(point) {
            return super.hitTest(point, with: event)
        }
        return nil
    }

    // MARK: - 开合（系统弹簧）

    @objc private func handleTapped() {
        setSidebarOpen(true, animated: true, reason: "handle-tap")
    }

    @objc private func scrimTapped() {
        setSidebarOpen(false, animated: true, reason: "scrim-tap")
    }

    @objc private func handlePanned(_ gesture: UIPanGestureRecognizer) {
        guard !isSidebarOpen else { return }
        dragSidebar(gesture, opening: true)
    }

    @objc private func sidebarPanned(_ gesture: UIPanGestureRecognizer) {
        guard isSidebarOpen else { return }
        dragSidebar(gesture, opening: false)
    }

    /// 跟手拖动：把手右拖开、面板/遮罩左拖关；松手按速度与
    /// 进度用系统弹簧收口到开/关。
    private func dragSidebar(_ gesture: UIPanGestureRecognizer, opening: Bool) {
        let width = panelWidth
        switch gesture.state {
        case .began:
            sidebarAnimator?.stopAnimation(true)
            sidebarAnimator = nil
            isDraggingSidebar = true
            scrimView.isHidden = false
            if opening { onSidebarVisibilityChanged?(true) }
        case .changed:
            let translation = gesture.translation(in: self).x
            let base: CGFloat = opening ? -width : 0
            let tx = min(max(base + translation, -width), 0)
            applySidebarProgress(tx: tx)
        case .ended, .cancelled, .failed:
            isDraggingSidebar = false
            let velocity = gesture.velocity(in: self).x
            let tx = sidebarView.transform.tx
            let progress = 1 + tx / width
            let targetOpen: Bool
            if velocity > 350 { targetOpen = true }
            else if velocity < -350 { targetOpen = false }
            else { targetOpen = progress > 0.45 }
            setSidebarOpen(targetOpen, animated: true, reason: "drag",
                           initialVelocityX: velocity)
        default:
            break
        }
    }

    private func applySidebarProgress(tx: CGFloat) {
        let width = panelWidth
        sidebarView.transform = CGAffineTransform(translationX: tx, y: 0)
        let progress = width > 0 ? 1 + tx / width : 0
        scrimView.alpha = 0.5 * progress
        let chromeAlpha = 1 - progress
        handleView.alpha = chromeAlpha
        avatarButton.alpha = chromeAlpha
    }

    func setSidebarOpen(_ open: Bool, animated: Bool, reason: String,
                        initialVelocityX: CGFloat = 0) {
        // 守卫：目标态已落定且面板已在目标位才跳过；拖动松手时
        // isSidebarOpen 可能与目标同值但面板还在途中，必须继续
        // 走完收口（否则墙交互的恢复回调永远不到）。
        let targetTx: CGFloat = open ? 0 : -panelWidth
        guard open != isSidebarOpen
            || abs(sidebarView.transform.tx - targetTx) > 0.5 else { return }
        isSidebarOpen = open
        Breadcrumbs.log("workbench.sidebar.\(open ? "open" : "close") reason=\(reason)")
        if open {
            refreshAccountUI()
            scrimView.isHidden = false
            onSidebarVisibilityChanged?(true)
        }
        sidebarAnimator?.stopAnimation(true)
        sidebarAnimator = nil
        let currentTx = sidebarView.transform.tx
        guard animated, !UIAccessibility.isReduceMotionEnabled,
              abs(targetTx - currentTx) > 0.5 else {
            applySidebarProgress(tx: targetTx)
            finishSidebarAnimation(open: open, completed: true)
            return
        }
        let distance = targetTx - currentTx
        let relativeVelocity = distance != 0
            ? min(max(initialVelocityX / distance, -3), 3) : 0
        let timing = UISpringTimingParameters(
            dampingRatio: 0.86,
            initialVelocity: CGVector(dx: relativeVelocity, dy: 0))
        let animator = UIViewPropertyAnimator(duration: 0.55, timingParameters: timing)
        animator.addAnimations { [weak self] in
            self?.applySidebarProgress(tx: targetTx)
        }
        animator.addCompletion { [weak self] position in
            guard let self else { return }
            self.sidebarAnimator = nil
            self.finishSidebarAnimation(open: open, completed: position == .end)
        }
        sidebarAnimator = animator
        animator.startAnimation()
    }

    private func finishSidebarAnimation(open: Bool, completed: Bool) {
        // 只认与现态一致的收口：动画被反向打断时旧 completion
        // 会以 .current 落到这里，此时现态已翻转，不许它再动
        // scrim/把手/墙交互（防「开到一半被关、scrim 被旧收口藏掉」）。
        if open {
            if isSidebarOpen { scrimView.isHidden = false }
        } else if !isSidebarOpen {
            scrimView.isHidden = true
            scrimView.alpha = 0
            handleView.alpha = 1
            avatarButton.alpha = 1
            // 关闭落定才恢复墙交互。
            onSidebarVisibilityChanged?(false)
        }
        _ = completed
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
        }
        // 头像：第一家已登录且有头像的；状态点：任一家已登录为亮。
        let avatarStatus = loggedIn.first { $0.avatarURL != nil } ?? statuses.first { $0.avatarURL != nil }
        let anyLoggedIn = !loggedIn.isEmpty
        avatarButton.setLoggedIn(anyLoggedIn)
        sidebarAvatar.setLoggedIn(anyLoggedIn)
        let key = avatarStatus?.avatarURL?.absoluteString ?? ""
        if key != avatarLoadKey {
            avatarLoadKey = key
            let expectedKey = key
            WorkbenchCover.loadAvatar(url: avatarStatus?.avatarURL, into: avatarButton.imageView) { [weak self] in
                self?.avatarLoadKey == expectedKey
            }
            WorkbenchCover.loadAvatar(url: avatarStatus?.avatarURL, into: sidebarAvatar.imageView) { [weak self] in
                self?.avatarLoadKey == expectedKey
            }
            let fallbackName = loggedIn.first?.displayName ?? statuses.first?.displayName
            avatarButton.setFallback(name: fallbackName, hasImage: avatarStatus?.avatarURL != nil)
            sidebarAvatar.setFallback(name: fallbackName, hasImage: avatarStatus?.avatarURL != nil)
        }
    }

    @objc private func avatarTapped() {
        // 关闭态点头像：直接进登录页（不先开侧栏）。
        presentLogin()
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
}

/// 圆形头像小件：图 + 无图时昵称首字兜底 + 登录状态点。
final class WorkbenchAvatarView: UIView {

    let imageView = UIImageView()
    private let fallbackLabel = UILabel()
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
        fallbackLabel.text = "?"
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallbackLabel)
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
        } else if let first = name?.first {
            fallbackLabel.text = String(first)
        } else {
            fallbackLabel.text = "?"
        }
    }
}
