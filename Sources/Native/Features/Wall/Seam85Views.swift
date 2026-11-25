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

    /// (89)B b-seam-narrow：首页窄缝 120 档开关（网页
    /// BRAVAIS_SEAM_HOME_WIDTH=120）。true 时主页缝开口
    /// 宽走 120 宽档排版，false 回书脊 64；点缝上「书库」
    /// 标题切换（见 HomeSeam85View.onToggleWide89）。
    static var narrow120: Bool {
        get { UserDefaults.standard.bool(forKey: "folia.seam89.narrow120") }
        set { UserDefaults.standard.set(newValue, forKey: "folia.seam89.narrow120") }
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
/// → 底部工具格（搜索/设置／队列/⋯）。
/// port88：账户头像位整件摘除（Miller 2026-11-25 定「头
/// 像全部去掉」，工坊基线同口径）；点头像定位随之退役。
/// 选中态两套（网页 fb3）：一级页签＝填色块；本面无二级
/// 切换（原生分区是独立面、经页签进入），中段直达入口
/// 是普通按钮形态、不冒充页签。
/// 命中纪律同 (84) 侧栏：hitTest 只认按钮本体，缝背景一
/// 律穿透——缝随墙走、不是拖动把手。
final class HomeSeam85View: UIView {

    var onFold: (() -> Void)?
    var onPlaylists: (() -> Void)?
    var onRadio: (() -> Void)?
    /// (89)B b-seam-tabs：补探索/Navidrome 两页签（网页
    /// resolveHomeTabs 原序），tag 2/5。
    var onExplore: (() -> Void)?
    var onAlbums: (() -> Void)?
    var onLocal: (() -> Void)?
    var onNavidrome: (() -> Void)?
    /// (89)B b-seam-narrow：点「书库」标题切换 64/120 档。
    var onToggleWide89: (() -> Void)?
    var onLiked: (() -> Void)?
    /// (86) 第 1 条：直达入口补云盘列（网页双列同式）。
    var onCloud: (() -> Void)?
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

    /// (89)B b-seam-tabs：一级页签标题（网页 resolveHome-
    /// Tabs 原序），tag 与下标同序 0-5。横/竖两种标题形态
    /// 都由此表生成（竖排走 Seam85Text.vertical）。
    private let tabTitles89 = ["歌单", "电台", "探索", "专辑", "本地", "Navidrome"]

    /// (89)B b-seam-tabs：当前选中页签下标（默认 0＝歌单，
    /// 主页墙本体即歌单集）；宿主点哪个页签选哪个，不再
    /// 恒 0。赋值即刷新选中态。
    var selectedTabIndex: Int = 0 {
        didSet { refreshTabSelection() }
    }

    /// (89)B b-seam-narrow：宽档（120）排版开关。true 时
    /// layoutSubviews 走宽档：内容宽＝bounds.width、页签
    /// 横排整行、直达两整行、工具格底部一排；标题形态随
    /// 档切换（横排原文/竖排逐字）。
    var displayWide89: Bool = false {
        didSet { applyDisplayMode89() }
    }

    private let backdrop86 = SeamBackdrop86()
    private let contentView = UIView()
    private let libraryLabel = UILabel()
    private let foldButton = UIButton(type: .system)
    private var tabButtons: [UIButton] = []
    private let likedButton = UIButton(type: .system)
    private let cloudButton = UIButton(type: .system)
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
        // (89)B b-seam-narrow：「书库」标题即 64/120 档切换
        // 钮（点按翻档，宿主经 onToggleWide89 走既有补间
        // 重排）。命中纪律随之放行标题本体（见 hitTest）。
        libraryLabel.isUserInteractionEnabled = true
        libraryLabel.addGestureRecognizer(UITapGestureRecognizer(
            target: self, action: #selector(libraryTapped89)))
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
        // (89)B b-seam-tabs：4 → 6（补探索 tag2、Navidrome
        // tag5，网页 resolveHomeTabs 原序，见 tabTitles89）。
        for (index, title) in tabTitles89.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(Seam85Text.vertical(title), for: .normal)
            button.titleLabel?.numberOfLines = 0
            // (89) §5-8：缝页签字号对齐网页 14。
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
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

        // port88：头像钮已摘除——本缝自上而下为书库行→折
        // 叠钮→页签→直达双列→工具格，无账户位。

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
        // port88 见证：主页缝建成即无头像位（站点存活自证）。
        Breadcrumbs.log("port88 seam=avatarless host=home")
    }

    private func refreshTabSelection() {
        for (index, button) in tabButtons.enumerated() {
            // (89)B b-seam-tabs：选中下标改读 selectedTab-
            // Index（宿主同步），不再恒 0。
            let selected = index == selectedTabIndex
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

    /// (89)B b-seam-narrow：档位形态切换——页签与直达钮
    /// 同时备横/竖两种标题，displayWide89 翻转时换标题、
    /// 对齐与字号，再走 layoutSubviews 的对应排版分支。
    private func applyDisplayMode89() {
        for (index, button) in tabButtons.enumerated() {
            let title = tabTitles89[index]
            button.setTitle(displayWide89 ? title : Seam85Text.vertical(title),
                            for: .normal)
            button.contentHorizontalAlignment = displayWide89 ? .left : .center
            button.contentEdgeInsets = displayWide89
                ? UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 0) : .zero
        }
        likedButton.setTitle(displayWide89
            ? "我喜欢的音乐" : Seam85Text.vertical("我喜欢的音乐"), for: .normal)
        cloudButton.setTitle(displayWide89
            ? "云盘" : Seam85Text.vertical("云盘"), for: .normal)
        for button in [likedButton, cloudButton] {
            button.titleLabel?.font = .systemFont(ofSize: displayWide89 ? 12 : 11)
            button.contentHorizontalAlignment = displayWide89 ? .left : .center
            button.contentVerticalAlignment = displayWide89 ? .center : .top
        }
        libraryLabel.textAlignment = displayWide89 ? .left : .center
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop86.frame = bounds
        // (89)B b-seam-narrow：宽档内容宽＝bounds.width
        // （宿主给 120）；窄档维持 64 居中。
        let contentW: CGFloat = displayWide89 ? bounds.width : 64
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
        // (89)B b-seam-narrow：宽档书库标题左对齐、折叠钮靠右。
        libraryLabel.frame = CGRect(
            x: displayWide89 ? 10 : 0, y: 0.028 * H,
            width: displayWide89 ? contentW - 20 : contentW,
            height: max(16, 0.022 * H))
        // (89) §5-7：折叠钮 28 → 36（网页缝图标钮 36×36）。
        foldButton.frame = displayWide89
            ? CGRect(x: contentW - 46, y: 0.066 * H, width: 36, height: 36)
            : CGRect(x: cx - 18, y: 0.066 * H, width: 36, height: 36)
        if displayWide89 {
            // (89)B b-seam-narrow 宽档排版：页签横排整行
            // （行高 36、宽＝内容宽−20、步距 40、起位仍
            // 0.118H；选中态仍白 pill、圆角取半行高）；直
            // 达改两整行横排（0.64H 起、行高 30、步距 34）；
            // 工具格改底部一排 4 图标（区位同窄档）。
            for (index, button) in tabButtons.enumerated() {
                button.frame = CGRect(
                    x: 10, y: 0.118 * H + CGFloat(index) * 40,
                    width: contentW - 20, height: 36)
                button.layer.cornerRadius = 18
            }
            likedButton.frame = CGRect(
                x: 10, y: 0.64 * H, width: contentW - 20, height: 30)
            cloudButton.frame = CGRect(
                x: 10, y: 0.64 * H + 34, width: contentW - 20, height: 30)
            let toolsH = 0.08 * H
            let toolsTop = H - 0.025 * H - toolsH
            let toolStep = (contentW - 20) / 4
            for (index, button) in toolButtons.enumerated() {
                button.frame = CGRect(
                    x: 10 + toolStep * CGFloat(index) + (toolStep - 28) / 2,
                    y: toolsTop + (toolsH - 28) / 2, width: 28, height: 28)
            }
            return
        }
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
        // 止于 0.64H＋84 < 工具格区，下方原账户区（0.782H）
        // 已随 port88 头像摘除留空。
        let shortcutH: CGFloat = 84
        likedButton.frame = CGRect(
            x: cx - 32, y: 0.64 * H, width: 28, height: shortcutH)
        cloudButton.frame = CGRect(
            x: cx + 4, y: 0.64 * H, width: 28, height: shortcutH)
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
            // (89)B b-seam-narrow：书库标题是 64/120 档切换
            // 钮（手势挂标签本体），与控件同格放行；其余
            // 背景穿透纪律不变。
            if view is UIControl || view === libraryLabel { return hit }
            if view === self { break }
            node = view.superview
        }
        return nil
    }

    // port88：账户回显（setAccount85）随头像摘除整组退役；
    // 账户态展示归设置页账户组与侧栏账户区，本缝不再回填。

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
        // (89)B b-seam-tabs：tag 与 tabTitles89 同序 0-5
        // （探索 2、Navidrome 5 为本包新增分发）。
        switch sender.tag {
        case 0:
            Breadcrumbs.log("sidebar85 tap dest=playlists")
            onPlaylists?()
        case 1:
            Breadcrumbs.log("sidebar85 tap dest=radio")
            onRadio?()
        case 2:
            Breadcrumbs.log("sidebar85 tap dest=explore")
            onExplore?()
        case 3:
            Breadcrumbs.log("sidebar85 tap dest=albums")
            onAlbums?()
        case 4:
            Breadcrumbs.log("sidebar85 tap dest=local")
            onLocal?()
        default:
            Breadcrumbs.log("sidebar85 tap dest=navidrome")
            onNavidrome?()
        }
    }

    /// (89)B b-seam-narrow：点「书库」标题切换 64/120 档
    /// （翻档与补间重排在宿主侧）。
    @objc private func libraryTapped89() {
        Breadcrumbs.log("sidebar85 tap dest=librarywide")
        onToggleWide89?()
    }

    @objc private func likedTapped() {
        Breadcrumbs.log("sidebar85 tap dest=liked")
        onLiked?()
    }

    @objc private func cloudTapped() {
        Breadcrumbs.log("sidebar85 tap dest=cloud")
        onCloud?()
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

    var contentTopInset: CGFloat = 108
    var contentBottomInset: CGFloat = 132
    var contentOpacity: CGFloat = 1 {
        didSet {
            spineContent.alpha = contentOpacity
            fullContent.alpha = contentOpacity
        }
    }

    private(set) var expanded = false
    /// (89)B b-seam-tilt：倾斜 −4° 容器（网页 BRAVAIS_
    /// TILT_DEG collection=−4；主页缝 0° 不动）。缝内全
    /// 部层（缝纸/书脊/展开档）挂此容器整体倾斜，本视图
    /// 不裁剪、命中由 UIKit 按 transform 自动换算。
    private let tiltContainer89 = UIView()
    private let backdrop86 = SeamBackdrop86()
    private let spineContent = UIView()
    private let fullContent = UIView()
    private let backButton = UIButton(type: .system)
    private let foldButton = UIButton(type: .system)
    private let titleButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
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
        // (89)B b-seam-tilt：三层改挂倾斜容器（层序不变：
        // 缝纸→书脊→展开档）。
        addSubview(tiltContainer89)
        tiltContainer89.addSubview(backdrop86)
        let seamPress = UILongPressGestureRecognizer(
            target: self, action: #selector(seamLongPressed86))
        seamPress.minimumPressDuration = 0.55
        addGestureRecognizer(seamPress)
        tiltContainer89.addSubview(spineContent)
        tiltContainer89.addSubview(fullContent)
        fullContent.isHidden = true
        Breadcrumbs.log("port89 seamtilt=-4")

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
        // port88：书脊头像（(86) 第 3 条常驻位）整件摘除，
        // 计数与播放钮之间的 0.70H 段留空。
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
        // port88 见证：歌单缝建成即无头像位（站点存活自证）。
        Breadcrumbs.log("port88 seam=avatarless host=wall")
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

    // port88：书脊头像回填（setAccount85）随头像摘除整组退役。

    /// (86) 第 2 条：缝上长按 0.55s 切主题（同主页缝）。
    @objc private func seamLongPressed86(
        _ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        SeamThemeCycle86.cycle()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // (89)B b-seam-tilt：容器在 bounds 上下各扩 40 后
        // 旋转 −4°（倾斜后上下缘不露缺口）；容器内排版坐
        // 标随之多 40 的纵偏移，top 补偿后内容在缝视图内
        // 的落位与倾斜前一致。下文宽度基准改容器宽。落
        // 位走 bounds＋center（带 transform 时 frame 未定义）。
        tiltContainer89.bounds = CGRect(
            x: 0, y: 0, width: bounds.width, height: bounds.height + 80)
        tiltContainer89.center = CGPoint(x: bounds.midX, y: bounds.midY)
        tiltContainer89.transform = CGAffineTransform(
            rotationAngle: -4 * .pi / 180)
        let areaW = tiltContainer89.bounds.width
        backdrop86.frame = tiltContainer89.bounds
        let top = contentTopInset + 40
        let contentH = max(0, bounds.height - contentTopInset - contentBottomInset)
        // 书脊内容（64 宽居中）。
        spineContent.frame = CGRect(
            x: (areaW - 64) / 2, y: top, width: 64, height: contentH)
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
        // (89) §5-7：书脊折叠钮 32 → 36（网页缝图标钮 36×36）。
        foldButton.frame = CGRect(x: cx - 18, y: 0.088 * H, width: 36, height: 36)
        titleButton.frame = CGRect(
            x: 12, y: 0.16 * H, width: 40, height: 0.38 * H)
        countLabel.frame = CGRect(
            x: 8, y: 0.56 * H, width: 48, height: 0.06 * H)
        // 计数（止 0.62H）与播放（起 0.84H）之间空段：
        // port88 前为头像位（0.70H 起 32 圆），已摘除留空。
        playButton.frame = CGRect(x: cx - 18, y: 0.84 * H, width: 36, height: 36)
        // (89) §5-7：展开钮 28 → 36（网页缝图标钮 36×36）。
        expandButton.frame = CGRect(x: cx - 18, y: 0.905 * H, width: 36, height: 36)
        // 展开档内容（300 宽居中、左对齐排版）。
        fullContent.frame = CGRect(
            x: (areaW - 300) / 2, y: top, width: 300, height: contentH)
        // (89) §5-7：展开档返回钮 28 → 32（网页返回钮 32×32）。
        fullBackButton.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
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
}
