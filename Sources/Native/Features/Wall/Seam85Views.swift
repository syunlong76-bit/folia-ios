import UIKit

/// (85) 第 1 条：世界缝共享等级（网页 bravaisSeamLevel 同
/// 式：全局一个等级、跨面沿用——主页折叠后进歌单，缝仍是
/// 折叠的）。手机档只有 spine（64 书脊）/ hidden 两级；
/// 歌单的展开档（300 完整条）是面内状态、不入本存储。
enum SeamState85 {
    static var levelHidden: Bool {
        get { UserDefaults.standard.bool(forKey: "folia.seam85.hidden") }
        set { UserDefaults.standard.set(newValue, forKey: "folia.seam85.hidden") }
    }

    /// 网页 contentOpacityFor 同式：开口窄于排版宽时内容
    /// 随之淡出（开到 35% 以下不可见）。
    static func contentOpacity(rendered: CGFloat, content: CGFloat) -> CGFloat {
        max(0, min(1, (rendered / max(content, 1) - 0.35) / 0.65))
    }
}

/// 竖排文字（字间换行，与 (84) 侧栏/网页 writing-mode 同
/// 视觉语言）。
enum Seam85Text {
    static func vertical(_ text: String) -> String {
        text.map { String($0) }.joined(separator: "\n")
    }
}

/// (86) 第 1/2 条：缝底（两缝共用）——缝纸改网页原值
/// rgba(22,22,27,0.8)＋0 0 18px 黑投影（(85) 的黑 0.34
/// 平涂＋白发丝线整组退役）；油画底与点播台同源 4 套
/// （MiniPlayerTheme.stored 单源、.foliaMiniPlayerTheme-
/// Changed 通知跟随），层序＝缝纸→油画→scrim→内容。
/// 油画 alpha 0.6＋scrim 黑 0.30（点播台 scrim 为 0.18，
/// 缝内全是竖排小字、按可读性加深，取值见 (86) 报告）；
/// 主题 none 时油画/scrim 同隐、只剩缝纸。本层不接手
/// 势（缝命中纪律不变：只认控件本体）。
final class SeamBackdrop86: UIView {

    private let imageView = UIImageView()
    private let scrimView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 22.0 / 255, green: 22.0 / 255,
                                  blue: 27.0 / 255, alpha: 0.8)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.55
        layer.shadowRadius = 9
        layer.shadowOffset = .zero
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.alpha = 0.6
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        scrimView.backgroundColor = UIColor.black.withAlphaComponent(0.30)
        scrimView.isUserInteractionEnabled = false
        addSubview(scrimView)
        refreshTheme86()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged86),
            name: .foliaMiniPlayerThemeChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        scrimView.frame = bounds
    }

    @objc private func themeChanged86() { refreshTheme86() }

    private func refreshTheme86() {
        let image = MiniPlayerThemeLayer.backgroundImage(
            for: MiniPlayerTheme.effective)
        imageView.image = image
        imageView.isHidden = image == nil
        scrimView.isHidden = image == nil
    }
}

/// (86) 第 2 条：缝上长按 0.55s 切主题——与点播台长按
/// 同一通路（写 MiniPlayerTheme.stored.next＋发同一通
/// 知，主题单源不分叉；特效总开关关时停用、同台口
/// 径）。识别器挂缝本体：触摸落在缝内任一控件上时祖先
/// 识别器同收，认领即 cancelsTouchesInView、控件不误
/// 触；缝空域穿透纪律不变（空域触摸归墙、长按不达）。
enum SeamThemeCycle86 {
    static func cycle() {
        guard MiniPlayerTheme.effectsEnabled else { return }
        MiniPlayerTheme.stored = MiniPlayerTheme.stored.next
        NotificationCenter.default.post(
            name: .foliaMiniPlayerThemeChanged, object: nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Breadcrumbs.log("seam86 theme=\(MiniPlayerTheme.stored.rawValue)")
    }
}

/// 缝宿主侧边竖标签（网页 BRAVAIS_EDGE_TAB）：缝折叠或被
/// 平移挤出视口时出现在屏幕侧边，点它在当前视口重新裂开。
final class SeamEdgeTab85View: UIView {

    var onTap: (() -> Void)?

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.42)
        layer.cornerRadius = 8
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        label.text = Seam85Text.vertical("书库")
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)
        addGestureRecognizer(UITapGestureRecognizer(
            target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }

    @objc private func tapped() { onTap?() }
}

/// (85) 第 1 条：主页缝内容（书脊档 64，网页 BravaisSeam-
/// Home compact 同构成）：书库行 → 折叠钮 → 竖排页签
/// （歌单/电台/专辑/本地）→ 中段直达入口（我喜欢的音乐）
/// → 账户头像 → 底部工具格（搜索/设置／队列/⋯）。
/// 选中态两套（网页 fb3）：一级页签＝填色块；本面无二级
/// 切换（原生分区是独立面、经页签进入），中段直达入口
/// 是普通按钮形态、不冒充页签。
/// 命中纪律同 (84) 侧栏：hitTest 只认按钮本体，缝背景一
/// 律穿透——缝随墙走、不是拖动把手。
final class HomeSeam85View: UIView {

    var onFold: (() -> Void)?
    var onPlaylists: (() -> Void)?
    var onRadio: (() -> Void)?
    var onAlbums: (() -> Void)?
    var onLocal: (() -> Void)?
    var onLiked: (() -> Void)?
    /// (86) 第 1 条：直达入口补云盘列（网页双列同式）。
    var onCloud: (() -> Void)?
    var onAvatar: (() -> Void)?
    var onSearch: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQueue: (() -> Void)?
    var onMore: (() -> Void)?

    /// 内容纵向内边距（宿主按工具条/点播台占位设定）。
    var contentTopInset: CGFloat = 108
    var contentBottomInset: CGFloat = 132
    /// 内容淡出（宿主按渲染开口逐帧喂，见 SeamState85）。
    var contentOpacity: CGFloat = 1 {
        didSet { contentView.alpha = contentOpacity }
    }

    private let backdrop86 = SeamBackdrop86()
    private let contentView = UIView()
    private let libraryLabel = UILabel()
    private let foldButton = UIButton(type: .system)
    private var tabButtons: [UIButton] = []
    private let likedButton = UIButton(type: .system)
    private let cloudButton = UIButton(type: .system)
    private let avatarButton = UIButton(type: .custom)
    private let avatarImageView = UIImageView()
    private let avatarInitialLabel = UILabel()
    /// (86) 第 2 条：头像加载防串图键（当前 URL 串）。
    private var avatarLoadKey86: String?
    private var toolButtons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build() {
        // (86) 第 1/2 条：缝纸＋油画底由 SeamBackdrop86 承
        // 担（本视图底色清零）；长按 0.55s 切主题挂本体。
        backgroundColor = .clear
        addSubview(backdrop86)
        let seamPress = UILongPressGestureRecognizer(
            target: self, action: #selector(seamLongPressed86))
        seamPress.minimumPressDuration = 0.55
        addGestureRecognizer(seamPress)
        contentView.isUserInteractionEnabled = true
        addSubview(contentView)

        // 书库标题（网页：extrabold＋字距 0.3em＋white/85）。
        libraryLabel.attributedText = NSAttributedString(
            string: "书库",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                .kern: 3.6,
            ])
        libraryLabel.textAlignment = .center
        contentView.addSubview(libraryLabel)

        // 折叠钮（网页：裸 chevron、white/55、无底衬）。
        foldButton.setImage(UIImage(
            systemName: "chevron.left",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13, weight: .semibold)), for: .normal)
        foldButton.tintColor = UIColor.white.withAlphaComponent(0.55)
        foldButton.accessibilityLabel = "折叠"
        foldButton.addTarget(self, action: #selector(foldTapped), for: .touchUpInside)
        contentView.addSubview(foldButton)

        // 一级页签（竖排）：歌单默认选中（主页墙当前面即
        // 歌单集，与 (84) 侧栏去向表一致）。字重改网页
        // bold；圆角在布局时按帧高取半成全圆 pill。
        for (index, title) in ["歌单", "电台", "专辑", "本地"].enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(Seam85Text.vertical(title), for: .normal)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
            button.titleLabel?.textAlignment = .center
            button.accessibilityLabel = title
            button.tag = index
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            contentView.addSubview(button)
            tabButtons.append(button)
        }
        refreshTabSelection()

        // 中段直达（网页：双列竖排小字、white/55、无分隔
        // 线）——我喜欢的音乐＋云盘，两列顶对齐。
        for (button, title, action) in [
            (likedButton, "我喜欢的音乐", #selector(likedTapped)),
            (cloudButton, "云盘", #selector(cloudTapped)),
        ] as [(UIButton, String, Selector)] {
            button.setTitle(Seam85Text.vertical(title), for: .normal)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.font = .systemFont(ofSize: 11)
            button.titleLabel?.textAlignment = .center
            button.setTitleColor(UIColor.white.withAlphaComponent(0.55), for: .normal)
            button.contentVerticalAlignment = .top
            button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
            button.accessibilityLabel = title
            button.addTarget(self, action: action, for: .touchUpInside)
            contentView.addSubview(button)
        }

        avatarButton.layer.cornerRadius = 16
        avatarButton.clipsToBounds = true
        avatarButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        // (86) 第 1 条：账户圆补网页白 0.25 描边。
        avatarButton.layer.borderWidth = 1
        avatarButton.layer.borderColor =
            UIColor.white.withAlphaComponent(0.25).cgColor
        avatarButton.accessibilityLabel = "定位正在播放"
        avatarButton.addTarget(self, action: #selector(avatarTapped), for: .touchUpInside)
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isUserInteractionEnabled = false
        avatarButton.addSubview(avatarImageView)
        avatarInitialLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        avatarInitialLabel.textColor = .white
        avatarInitialLabel.textAlignment = .center
        avatarInitialLabel.isUserInteractionEnabled = false
        avatarButton.addSubview(avatarInitialLabel)
        contentView.addSubview(avatarButton)
        setAccount85(nickname: nil, loggedIn: false, avatarURLString: nil)

        for (glyph, label, action) in [
            ("magnifyingglass", "搜索", #selector(searchTapped)),
            ("gearshape", "设置", #selector(settingsTapped)),
            ("list.bullet", "队列", #selector(queueTapped)),
            ("ellipsis", "更多", #selector(moreTapped)),
        ] as [(String, String, Selector)] {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: glyph), for: .normal)
            // (86) 第 1 条：工具格去芯片底（网页裸图标
            // white/70、无底衬无圆角）。
            button.tintColor = UIColor.white.withAlphaComponent(0.7)
            button.accessibilityLabel = label
            button.addTarget(self, action: action, for: .touchUpInside)
            contentView.addSubview(button)
            toolButtons.append(button)
        }
    }

    private func refreshTabSelection() {
        for (index, button) in tabButtons.enumerated() {
            let selected = index == 0
            // (86) 第 1 条：网页选中态——白 0.9 全圆 pill＋
            // 深色字；未选透明底＋white/62。（(85) 做反：
            // 白 0.13 方块底＋白字，审计三⑤定案走样。）
            button.backgroundColor = selected
                ? UIColor.white.withAlphaComponent(0.9) : .clear
            button.setTitleColor(selected
                ? UIColor(red: 22.0 / 255, green: 22.0 / 255,
                          blue: 27.0 / 255, alpha: 1)
                : UIColor.white.withAlphaComponent(0.62), for: .normal)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop86.frame = bounds
        let contentW: CGFloat = 64
        let top = contentTopInset
        let bottom = bounds.height - contentBottomInset
        let contentH = max(0, bottom - top)
        contentView.frame = CGRect(
            x: (bounds.width - contentW) / 2, y: top, width: contentW, height: contentH)
        let cx = contentW / 2
        let H = contentH
        // (86) 第 1 条：全改网页相对比例（BRAVAIS_HOME_
        // SEAM_GEOMETRY／WallParts 渲染同数，基准＝内容
        // 高 H；(85) 的固定 pt 排版整组退役）。
        libraryLabel.frame = CGRect(
            x: 0, y: 0.028 * H, width: contentW, height: max(16, 0.022 * H))
        foldButton.frame = CGRect(x: cx - 14, y: 0.066 * H, width: 28, height: 28)
        // 页签：top 0.118H 起、步距 0.07H、高 0.062H、宽
        // 0.40×缝宽＝26 居中；圆角取帧高一半成全圆 pill。
        for (index, button) in tabButtons.enumerated() {
            let tabH = 0.062 * H
            button.frame = CGRect(
                x: cx - 13, y: (0.118 + CGFloat(index) * 0.07) * H,
                width: 26, height: tabH)
            button.layer.cornerRadius = tabH / 2
        }
        // 中段直达：双列、top 0.64H（网页同位）；列宽 28、
        // 两列内沿距中线 4（列间隙 ≈ 网页 12% 口径）。列
        // 高 84＝6 字竖排实需（11pt 行高 ≈13.4×6＋inset），
        // 止于 0.64H＋84 < 账户区 0.782H、不压头像。
        let shortcutH: CGFloat = 84
        likedButton.frame = CGRect(
            x: cx - 32, y: 0.64 * H, width: 28, height: shortcutH)
        cloudButton.frame = CGRect(
            x: cx + 4, y: 0.64 * H, width: 28, height: shortcutH)
        // 账户位：top 0.782H、高 0.072H 区内 32 圆居中
        // （网页圆宽 26% 缝宽≈17pt 触控过小，沿 (85) 的
        // 32pt 口径、白 0.25 描边已在 build 补）。
        let accountZoneH = 0.072 * H
        avatarButton.frame = CGRect(
            x: cx - 16,
            y: 0.782 * H + max(0, (accountZoneH - 32) / 2),
            width: 32, height: 32)
        avatarImageView.frame = avatarButton.bounds
        avatarInitialLabel.frame = avatarButton.bounds
        // 工具格：贴底（底距 0.025H）、区高 0.08H、两行
        // 两列裸图标（28×28 在格内居中、无底衬）。
        let toolsH = 0.08 * H
        let toolsTop = H - 0.025 * H - toolsH
        for (index, button) in toolButtons.enumerated() {
            let col = CGFloat(index % 2), row = CGFloat(index / 2)
            let cellH = toolsH / 2
            button.frame = CGRect(
                x: cx - 30 + col * 32,
                y: toolsTop + row * cellH + (cellH - 28) / 2,
                width: 28, height: 28)
        }
    }

    // MARK: 命中纪律（只认按钮本体，其余穿透给墙面）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        var node: UIView? = hit
        while let view = node {
            if view is UIControl { return hit }
            if view === self { break }
            node = view.superview
        }
        return nil
    }

    // MARK: 账户回显（与 HomeSidebar84View.setAccount84 同口径）

    func setAccount85(nickname: String?, loggedIn: Bool, avatarURLString: String?) {
        // (86) 第 2 条：头像改走 WorkbenchCover.loadAvatar
        // 代理链（工具条同款）——旧裸 URLSession 直下原始
        // URL：网易云头像是 http 明文域、被 ATS 拦，且失
        // 败静默、永远停占位「大」字（(85) 图一定案）。失
        // 败落 seam86 见证（ok/fail＋原因），不许静默。
        avatarLoadKey86 = avatarURLString
        if loggedIn, let nickname, !nickname.isEmpty {
            avatarInitialLabel.text = String(nickname.prefix(1))
            avatarButton.setImage(nil, for: .normal)
        } else {
            avatarInitialLabel.text = nil
            avatarButton.setImage(
                UIImage(systemName: "person.crop.circle"), for: .normal)
            avatarButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        }
        avatarImageView.image = nil
        avatarInitialLabel.isHidden = false
        guard loggedIn else {
            Breadcrumbs.log("seam86 avatar host=home ok=0 rsn=nologin")
            return
        }
        guard let avatarURLString, let url = URL(string: avatarURLString) else {
            Breadcrumbs.log("seam86 avatar host=home ok=0 rsn=nourl")
            return
        }
        let key = avatarURLString
        WorkbenchCover.loadAvatar(url: url, into: avatarImageView,
            completion: { [weak self] ok in
                guard let self, self.avatarLoadKey86 == key else { return }
                if ok {
                    self.avatarInitialLabel.isHidden = true
                    Breadcrumbs.log("seam86 avatar host=home ok=1")
                } else {
                    Breadcrumbs.log("seam86 avatar host=home ok=0 rsn=load")
                }
            },
            isCurrent: { [weak self] in self?.avatarLoadKey86 == key })
    }

    /// (86) 第 2 条：缝上长按 0.55s 切主题（通路见
    /// SeamThemeCycle86）。
    @objc private func seamLongPressed86(
        _ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        SeamThemeCycle86.cycle()
    }

    // MARK: 点按（逐项落痕 sidebar85）

    @objc private func foldTapped() {
        Breadcrumbs.log("sidebar85 tap dest=fold")
        onFold?()
    }

    @objc private func tabTapped(_ sender: UIButton) {
        switch sender.tag {
        case 0:
            Breadcrumbs.log("sidebar85 tap dest=playlists")
            onPlaylists?()
        case 1:
            Breadcrumbs.log("sidebar85 tap dest=radio")
            onRadio?()
        case 2:
            Breadcrumbs.log("sidebar85 tap dest=albums")
            onAlbums?()
        default:
            Breadcrumbs.log("sidebar85 tap dest=local")
            onLocal?()
        }
    }

    @objc private func likedTapped() {
        Breadcrumbs.log("sidebar85 tap dest=liked")
        onLiked?()
    }

    @objc private func cloudTapped() {
        Breadcrumbs.log("sidebar85 tap dest=cloud")
        onCloud?()
    }

    @objc private func avatarTapped() {
        Breadcrumbs.log("sidebar85 tap dest=avatar")
        onAvatar?()
    }

    @objc private func searchTapped() {
        Breadcrumbs.log("sidebar85 tap dest=search")
        onSearch?()
    }

    @objc private func settingsTapped() {
        Breadcrumbs.log("sidebar85 tap dest=settings")
        onSettings?()
    }

    @objc private func queueTapped() {
        Breadcrumbs.log("sidebar85 tap dest=queue")
        onQueue?()
    }

    @objc private func moreTapped() {
        Breadcrumbs.log("sidebar85 tap dest=more")
        onMore?()
    }
}

/// (85) 第 1 条：歌单页缝（网页 BravaisSeamCollection 同
/// 骨架）：书脊档（64）＝返回 ‹ → 折叠 → 竖排歌单名（点
/// 它展开）→ 竖排计数 → 播放钮 → 展开钮；展开档（300）
/// ＝返回＋横排标题＋计数＋播放全部/加入队列＋收起。
/// 构成与主页缝不同（集合的身份与动作）、骨架同。
final class PlaylistSeam85View: UIView {

    var onBack: (() -> Void)?
    var onFold: (() -> Void)?
    var onPlayAll: (() -> Void)?
    var onAppendQueue: (() -> Void)?
    var onExpandChange: ((Bool) -> Void)?
    /// (86) 第 3 条：书脊补常驻头像入口（与主页缝同位口
    /// 径：下段、播放钮上方），宿主绑定位。
    var onAvatar: (() -> Void)?

    var contentTopInset: CGFloat = 108
    var contentBottomInset: CGFloat = 132
    var contentOpacity: CGFloat = 1 {
        didSet {
            spineContent.alpha = contentOpacity
            fullContent.alpha = contentOpacity
        }
    }

    private(set) var expanded = false
    private let backdrop86 = SeamBackdrop86()
    private let spineContent = UIView()
    private let fullContent = UIView()
    private let backButton = UIButton(type: .system)
    private let foldButton = UIButton(type: .system)
    private let titleButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    // (86) 第 3 条：书脊头像（构成同主页缝）。
    private let avatarButton = UIButton(type: .custom)
    private let avatarImageView = UIImageView()
    private let avatarInitialLabel = UILabel()
    private var avatarLoadKey86: String?
    // 展开档
    private let fullBackButton = UIButton(type: .system)
    private let fullTitleLabel = UILabel()
    private let fullMetaLabel = UILabel()
    private let fullPlayButton = UIButton(type: .system)
    private let fullAppendButton = UIButton(type: .system)
    private let fullFoldButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build() {
        // (86) 第 1/2 条：缝纸＋油画底同主页缝（SeamBack-
        // drop86）；长按切主题同挂本体。
        backgroundColor = .clear
        addSubview(backdrop86)
        let seamPress = UILongPressGestureRecognizer(
            target: self, action: #selector(seamLongPressed86))
        seamPress.minimumPressDuration = 0.55
        addGestureRecognizer(seamPress)
        addSubview(spineContent)
        addSubview(fullContent)
        fullContent.isHidden = true

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.accessibilityLabel = "返回"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        spineContent.addSubview(backButton)
        // 折叠钮去芯片底（网页裸钮，同主页缝）。
        foldButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        foldButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        foldButton.accessibilityLabel = "折叠"
        foldButton.addTarget(self, action: #selector(foldTapped), for: .touchUpInside)
        spineContent.addSubview(foldButton)
        titleButton.titleLabel?.numberOfLines = 0
        titleButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        titleButton.titleLabel?.textAlignment = .center
        titleButton.setTitleColor(.white, for: .normal)
        titleButton.accessibilityLabel = "展开信息条"
        titleButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        spineContent.addSubview(titleButton)
        countLabel.numberOfLines = 0
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        countLabel.textAlignment = .center
        spineContent.addSubview(countLabel)
        // 播放钮去底衬（网页书脊裸钮，同折叠钮口径）。
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.tintColor = .white
        playButton.accessibilityLabel = "播放全部"
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        spineContent.addSubview(playButton)
        // (86) 第 3 条：书脊头像（白 0.25 描边、构成同主页缝）。
        avatarButton.layer.cornerRadius = 16
        avatarButton.clipsToBounds = true
        avatarButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        avatarButton.layer.borderWidth = 1
        avatarButton.layer.borderColor =
            UIColor.white.withAlphaComponent(0.25).cgColor
        avatarButton.accessibilityLabel = "定位正在播放"
        avatarButton.addTarget(self, action: #selector(avatarTapped), for: .touchUpInside)
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isUserInteractionEnabled = false
        avatarButton.addSubview(avatarImageView)
        avatarInitialLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        avatarInitialLabel.textColor = .white
        avatarInitialLabel.textAlignment = .center
        avatarInitialLabel.isUserInteractionEnabled = false
        avatarButton.addSubview(avatarInitialLabel)
        spineContent.addSubview(avatarButton)
        setAccount85(nickname: nil, loggedIn: false, avatarURLString: nil)
        expandButton.setImage(
            UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        expandButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        expandButton.accessibilityLabel = "展开信息条"
        expandButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        spineContent.addSubview(expandButton)

        fullBackButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        fullBackButton.tintColor = .white
        fullBackButton.accessibilityLabel = "返回"
        fullBackButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        fullContent.addSubview(fullBackButton)
        fullTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        fullTitleLabel.textColor = .white
        fullTitleLabel.numberOfLines = 2
        fullContent.addSubview(fullTitleLabel)
        fullMetaLabel.font = .systemFont(ofSize: 12)
        fullMetaLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        fullContent.addSubview(fullMetaLabel)
        for (button, title, glyph, action) in [
            (fullPlayButton, "播放全部", "play.fill", #selector(playTapped)),
            (fullAppendButton, "加入队列", "text.badge.plus", #selector(appendTapped)),
        ] as [(UIButton, String, String, Selector)] {
            button.setImage(UIImage(systemName: glyph), for: .normal)
            button.setTitle("  " + title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.tintColor = .white
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
            button.layer.cornerRadius = 12
            button.contentHorizontalAlignment = .left
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 0)
            button.accessibilityLabel = title
            button.addTarget(self, action: action, for: .touchUpInside)
            fullContent.addSubview(button)
        }
        fullFoldButton.setTitle("收起", for: .normal)
        fullFoldButton.titleLabel?.font = .systemFont(ofSize: 13)
        fullFoldButton.setTitleColor(UIColor.white.withAlphaComponent(0.75), for: .normal)
        fullFoldButton.accessibilityLabel = "收起信息条"
        fullFoldButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        fullContent.addSubview(fullFoldButton)
    }

    /// 数据回填（标题/计数）：宿主在种子落地与条目变化时调。
    func setPlaylist85(title: String, count: Int) {
        titleButton.setTitle(Seam85Text.vertical(title), for: .normal)
        countLabel.text = Seam85Text.vertical("\(count) 首")
        fullTitleLabel.text = title
        fullMetaLabel.text = "\(count) 首"
    }

    func setExpanded85(_ expanded: Bool) {
        self.expanded = expanded
        spineContent.isHidden = expanded
        fullContent.isHidden = !expanded
        setNeedsLayout()
    }

    /// (86) 第 2/3 条：书脊头像回填——与主页缝同链
    /// （WorkbenchCover.loadAvatar 代理链＋seam86 见证，
    /// host=wall 区分两缝）。
    func setAccount85(nickname: String?, loggedIn: Bool, avatarURLString: String?) {
        avatarLoadKey86 = avatarURLString
        if loggedIn, let nickname, !nickname.isEmpty {
            avatarInitialLabel.text = String(nickname.prefix(1))
            avatarButton.setImage(nil, for: .normal)
        } else {
            avatarInitialLabel.text = nil
            avatarButton.setImage(
                UIImage(systemName: "person.crop.circle"), for: .normal)
            avatarButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        }
        avatarImageView.image = nil
        avatarInitialLabel.isHidden = false
        guard loggedIn else {
            Breadcrumbs.log("seam86 avatar host=wall ok=0 rsn=nologin")
            return
        }
        guard let avatarURLString, let url = URL(string: avatarURLString) else {
            Breadcrumbs.log("seam86 avatar host=wall ok=0 rsn=nourl")
            return
        }
        let key = avatarURLString
        WorkbenchCover.loadAvatar(url: url, into: avatarImageView,
            completion: { [weak self] ok in
                guard let self, self.avatarLoadKey86 == key else { return }
                if ok {
                    self.avatarInitialLabel.isHidden = true
                    Breadcrumbs.log("seam86 avatar host=wall ok=1")
                } else {
                    Breadcrumbs.log("seam86 avatar host=wall ok=0 rsn=load")
                }
            },
            isCurrent: { [weak self] in self?.avatarLoadKey86 == key })
    }

    /// (86) 第 2 条：缝上长按 0.55s 切主题（同主页缝）。
    @objc private func seamLongPressed86(
        _ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        SeamThemeCycle86.cycle()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop86.frame = bounds
        let top = contentTopInset
        let contentH = max(0, bounds.height - contentTopInset - contentBottomInset)
        // 书脊内容（64 宽居中）。
        spineContent.frame = CGRect(
            x: (bounds.width - 64) / 2, y: top, width: 64, height: contentH)
        let cx: CGFloat = 32
        let H = contentH
        // (86) 第 1 条：书脊改网页相对比例（BRAVAIS_SPINE_
        // GEOMETRY 同数，基准＝内容高 H）：back top 0.024、
        // fold 0.088、title top 0.16 高 0.38、count top
        // 0.56 高 0.06、play top 0.84、expand top 0.905；
        // 钮宽网页 0.6×缝宽≈38、原生触控帧 32 居中代偿
        // （报告注明）。标题不再弹性拉满、计数不再随标题
        // 底漂移（(85) 走样两处）。
        backButton.frame = CGRect(x: cx - 16, y: 0.024 * H, width: 32, height: 32)
        foldButton.frame = CGRect(x: cx - 16, y: 0.088 * H, width: 32, height: 32)
        titleButton.frame = CGRect(
            x: 12, y: 0.16 * H, width: 40, height: 0.38 * H)
        countLabel.frame = CGRect(
            x: 8, y: 0.56 * H, width: 48, height: 0.06 * H)
        // 头像：计数（止 0.62H）与播放（起 0.84H）之间空
        // 段居中（0.70H 起 32 圆）。
        avatarButton.frame = CGRect(x: cx - 16, y: 0.70 * H, width: 32, height: 32)
        avatarImageView.frame = avatarButton.bounds
        avatarInitialLabel.frame = avatarButton.bounds
        playButton.frame = CGRect(x: cx - 18, y: 0.84 * H, width: 36, height: 36)
        expandButton.frame = CGRect(x: cx - 14, y: 0.905 * H, width: 28, height: 28)
        // 展开档内容（300 宽居中、左对齐排版）。
        fullContent.frame = CGRect(
            x: (bounds.width - 300) / 2, y: top, width: 300, height: contentH)
        fullBackButton.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        fullTitleLabel.frame = CGRect(x: 36, y: 2, width: 264, height: 44)
        fullMetaLabel.frame = CGRect(x: 36, y: 48, width: 264, height: 18)
        fullPlayButton.frame = CGRect(x: 16, y: 84, width: 268, height: 44)
        fullAppendButton.frame = CGRect(x: 16, y: 136, width: 268, height: 44)
        fullFoldButton.frame = CGRect(x: 16, y: 188, width: 60, height: 28)
    }

    // MARK: 命中纪律（只认按钮本体，其余穿透给墙面）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        var node: UIView? = hit
        while let view = node {
            if view is UIControl { return hit }
            if view === self { break }
            node = view.superview
        }
        return nil
    }

    // MARK: 点按（逐项落痕 sidebar85）

    @objc private func backTapped() {
        Breadcrumbs.log("sidebar85 tap dest=back")
        onBack?()
    }

    @objc private func foldTapped() {
        Breadcrumbs.log("sidebar85 tap dest=fold")
        onFold?()
    }

    @objc private func playTapped() {
        Breadcrumbs.log("sidebar85 tap dest=playall")
        onPlayAll?()
    }

    @objc private func appendTapped() {
        Breadcrumbs.log("sidebar85 tap dest=append")
        onAppendQueue?()
    }

    @objc private func expandTapped() {
        Breadcrumbs.log("sidebar85 tap dest=\(expanded ? "spine" : "expand")")
        onExpandChange?(!expanded)
    }

    @objc private func avatarTapped() {
        Breadcrumbs.log("sidebar85 tap dest=avatar")
        onAvatar?()
    }
}
